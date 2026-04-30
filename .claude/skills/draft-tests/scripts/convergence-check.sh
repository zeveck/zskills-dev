#!/bin/bash
# convergence-check.sh -- Phase 4 orchestrator-level convergence
# determination for /draft-tests.
#
# Reads a refiner round output file (containing a disposition table) and
# a coverage-floor findings file produced by coverage-floor-precheck.sh,
# then applies the FOUR positive conditions from Phase 4 Design &
# Constraints:
#
#   1. Every AC across all Pending non-delegate phases has >= 1 spec
#      referencing it (coverage floor -- enforced via the precheck input).
#   2. Every spec has a literal expected value or named exception.
#      (Surfaces as a Verified finding type "vague expected" in the
#      disposition table; we check by ensuring no unresolved finding
#      with that disposition pattern remains.)
#   3. No finding from this round duplicates a previous round's finding
#      after refiner's dedup pass. (Surfaces as `Justified - duplicate of
#      round N-1` rows; those are OK by themselves, but they are NOT
#      counted as substantive blockers.)
#   4. All findings are either resolved or have blast radius = minor
#      (dropped at refiner stage).
#
# CRITICAL: this is the ORCHESTRATOR's mechanical judgment. Per Design &
# Constraints and CLAUDE.md memory anchor
# `feedback_convergence_orchestrator_judgment.md`, NEVER accept a
# refiner agent's "CONVERGED" / "no further refinement needed" /
# equivalent self-call as authoritative -- the refiner just refined and
# is biased toward declaring its own work done. The presence of those
# strings in the refiner output is IGNORED by this script. This is the
# load-bearing AC-4.9 negative-case guard.
#
# Usage:
#   bash convergence-check.sh <refiner-output> <coverage-floor-findings>
#
# Arguments:
#   <refiner-output>             Refiner round-N output file containing
#                                a disposition table.
#   <coverage-floor-findings>    Synthetic coverage-floor findings file
#                                from coverage-floor-precheck.sh. Empty
#                                file = floor met.
#
# Exit codes:
#   0 -- converged. Stdout: `CONVERGED`.
#   1 -- not converged. Stdout: `NOT CONVERGED: <reason>` (one or more
#        lines, each naming a positive condition that failed).
#   2 -- usage error.
#   3 -- input file missing.

set -u

REFINER_OUTPUT="${1:-}"
FLOOR_FINDINGS="${2:-}"

if [ -z "$REFINER_OUTPUT" ] || [ -z "$FLOOR_FINDINGS" ]; then
  echo "Usage: $0 <refiner-output> <coverage-floor-findings>" >&2
  exit 2
fi

for f in "$REFINER_OUTPUT" "$FLOOR_FINDINGS"; do
  if [ ! -f "$f" ]; then
    echo "Error: input file '$f' not found." >&2
    exit 3
  fi
done

REASONS=()

# ----------------------------------------------------------------------
# Condition 1: coverage floor met (no synthetic findings remaining
# unresolved). The simplest check: the floor-findings file is empty, OR
# every floor-finding's AC ID appears as `Fixed` in the disposition
# table.
# ----------------------------------------------------------------------
if [ -s "$FLOOR_FINDINGS" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    # Extract AC ID from "Coverage floor violated: AC-N.M has no spec."
    if [[ "$line" =~ Coverage[[:space:]]floor[[:space:]]violated:[[:space:]]+(AC-[0-9]+[a-z]?\.[0-9]+[a-z]?) ]]; then
      ac_id="${BASH_REMATCH[1]}"
      # Look for a disposition table row mentioning this AC ID with
      # disposition "Fixed". The row format is (per AC-4.4):
      #   | <Finding text> | <Evidence> | <Disposition> |
      # We accept either `Fixed` or `fixed` and require the AC ID to
      # appear in the same table row.
      if ! grep -E -q "\\|.*${ac_id}.*\\|.*\\|[[:space:]]*[Ff]ixed" "$REFINER_OUTPUT"; then
        REASONS+=("coverage floor unresolved: $ac_id has no spec and no Fixed disposition")
      fi
    fi
  done < "$FLOOR_FINDINGS"
fi

# ----------------------------------------------------------------------
# Condition 4 (and 2 implicitly): no unresolved moderate/major
# findings.
#
# Disposition-table rows use the form:
#   | <Finding> | <Evidence> | <Disposition> |
# Disposition column begins with one of `Fixed`, `Justified`,
# `Justified - duplicate ...`. Blast radius is encoded inside the
# Finding column as `Blast radius: <minor|moderate|major>`.
#
# Logic:
#   - Skip rows whose disposition is `Fixed` (resolved).
#   - Skip rows whose disposition starts with `Justified - duplicate`
#     (deduped against prior round) -- these are dropped, not unresolved.
#   - Skip rows whose Finding column has `Blast radius: minor` (dropped
#     at refiner stage per WI 4.5).
#   - Any remaining row whose Finding contains `Blast radius: moderate`
#     OR `Blast radius: major` is an unresolved blocker.
# ----------------------------------------------------------------------
parse_disposition_rows() {
  awk '
    BEGIN { in_table=0 }
    /^\|[[:space:]]*[Ff]inding[[:space:]]*\|/ { in_table=1; next }
    /^\|[[:space:]]*-+[[:space:]]*\|/ { next }
    in_table && /^\|/ {
      # Split on `|` and trim each cell.
      n = split($0, cells, /\|/)
      finding=""; evidence=""; disp=""
      # cells[1] is empty (line starts with |); cells[2..4] are columns.
      if (n >= 4) {
        finding = cells[2]; evidence = cells[3]; disp = cells[4]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", finding)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", evidence)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", disp)
        printf "%s\x1F%s\x1F%s\n", finding, evidence, disp
      }
      next
    }
    in_table && !/^\|/ { in_table=0 }
  ' "$REFINER_OUTPUT"
}

UNRESOLVED_COUNT=0
DUP_UNRESOLVED_COUNT=0

while IFS=$'\x1F' read -r finding evidence disp; do
  [ -z "${finding:-}" ] && continue
  # Skip Fixed rows.
  if [[ "$disp" =~ ^[Ff]ixed ]]; then
    continue
  fi
  # Skip Justified-duplicate rows.
  if [[ "$disp" =~ ^[Jj]ustified[[:space:]]+[-—][[:space:]]+duplicate ]]; then
    continue
  fi
  # Determine blast radius from the Finding text.
  blast=""
  if [[ "$finding" =~ [Bb]last[[:space:]]radius:[[:space:]]*(minor|moderate|major) ]]; then
    blast="${BASH_REMATCH[1]}"
  fi
  # Minor findings are dropped at refiner stage -- not blockers.
  if [ "$blast" = "minor" ]; then
    continue
  fi
  # Anything left at moderate or major is unresolved.
  if [ "$blast" = "moderate" ] || [ "$blast" = "major" ]; then
    UNRESOLVED_COUNT=$((UNRESOLVED_COUNT + 1))
    REASONS+=("unresolved $blast finding: $finding ($disp)")
  fi
done < <(parse_disposition_rows)

# ----------------------------------------------------------------------
# Condition 3: no fresh round-N finding duplicates round-(N-1). The
# refiner's dedup marks duplicates `Justified - duplicate of round N-1`
# (skipped above). If the refiner failed to mark a duplicate, it
# surfaces as a regular Justified row whose Finding text matches a prior
# round's finding -- but we cannot detect that from this script alone
# (we don't have prior-round findings here). The `review-loop.sh`
# wrapper passes the prior-round findings file to this script as the
# coverage-findings input merge, OR can run a separate dup check.
# For v1, condition 3 is enforced via the refiner prompt + the fact
# that any unresolved duplicate would surface as a moderate/major-blast
# Justified row (caught above). The condition is implicit -- we don't
# add a separate failure path here.
# ----------------------------------------------------------------------

# ----------------------------------------------------------------------
# Apply final judgment. The orchestrator's check IGNORES any literal
# "CONVERGED" / "no further refinement needed" prose claim from the
# refiner -- we never even look at it. AC-4.9 negative-case guard.
# ----------------------------------------------------------------------
if [ ${#REASONS[@]} -eq 0 ]; then
  echo "CONVERGED"
  exit 0
fi

echo "NOT CONVERGED:"
for r in "${REASONS[@]}"; do
  echo "  $r"
done
exit 1
