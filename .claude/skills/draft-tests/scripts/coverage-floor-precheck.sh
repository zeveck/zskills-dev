#!/bin/bash
# coverage-floor-precheck.sh -- Phase 4 orchestrator-level coverage-floor
# pre-check for /draft-tests.
#
# Runs BEFORE dispatching the reviewer/DA agents each round (per WI 4.8 /
# AC-4.8). Operates on a per-round merged candidate file to unify
# first-invocation, re-invocation, and backfill-invocation semantics.
#
# Algorithm (verbatim from Phase 4 spec):
#   1. Read the plan file's current bytes.
#   2. Read the round-N drafter output (round 0) or refiner round-(N-1)
#      output (round >= 1).
#   3. Construct the candidate by overlaying the drafter/refiner's
#      `### Tests` subsections. Write to
#      `/tmp/draft-tests-candidate-round-<N>-<slug>.md`.
#   4. Read `non_delegate_pending_phases:` and `ac_less:` from the
#      parsed-state file (single source of truth -- no re-derivation).
#   5. For every AC in those phases, grep the candidate for
#      `risk: AC-<phase>.<n>[<sub-letter>]?`. For each AC lacking a
#      spec, synthesise:
#          Coverage floor violated: AC-N.M has no spec.
#          Blast radius: major - coverage floor is the convergence precondition.
#   6. Write the synthetic findings to <findings-out>.
#
# Usage:
#   bash coverage-floor-precheck.sh \
#       <plan-file> <parsed-state> <round-input> <round-n> <slug> \
#       <candidate-out> <findings-out>
#
# Arguments:
#   <plan-file>        Path to the plan .md.
#   <parsed-state>     `/tmp/draft-tests-parsed-<slug>.md` (Phase 1).
#   <round-input>      Drafter round-0 output (round 0) OR refiner
#                      round-(N-1) output (round >= 1). May be `/dev/null`
#                      to test plan-alone behaviour.
#   <round-n>          Current round number.
#   <slug>             Plan slug.
#   <candidate-out>    Output path for the merged candidate file.
#                      Conventionally
#                      `/tmp/draft-tests-candidate-round-<N>-<slug>.md`.
#   <findings-out>     Output path for synthesised coverage-floor findings.
#                      Empty file = floor met.
#
# Exit codes:
#   0 -- candidate written; findings written (may be empty).
#   2 -- usage error.
#   3 -- input file missing.

set -eu

PLAN_FILE="${1:-}"
PARSED_STATE="${2:-}"
ROUND_INPUT="${3:-}"
ROUND_N="${4:-}"
SLUG="${5:-}"
CANDIDATE_OUT="${6:-}"
FINDINGS_OUT="${7:-}"

if [ -z "$PLAN_FILE" ] || [ -z "$PARSED_STATE" ] || [ -z "$ROUND_INPUT" ] \
   || [ -z "$ROUND_N" ] || [ -z "$SLUG" ] || [ -z "$CANDIDATE_OUT" ] \
   || [ -z "$FINDINGS_OUT" ]; then
  echo "Usage: $0 <plan-file> <parsed-state> <round-input> <round-n> <slug> <candidate-out> <findings-out>" >&2
  exit 2
fi

for f in "$PLAN_FILE" "$PARSED_STATE"; do
  if [ ! -f "$f" ]; then
    echo "Error: input file '$f' not found." >&2
    exit 3
  fi
done

# ROUND_INPUT may be /dev/null (intentional plan-alone test).
if [ "$ROUND_INPUT" != "/dev/null" ] && [ ! -f "$ROUND_INPUT" ]; then
  echo "Error: round-input '$ROUND_INPUT' not found." >&2
  exit 3
fi

# ----------------------------------------------------------------------
# Read parsed-state lists (single source of truth -- per WI 4.8 step 4).
# ----------------------------------------------------------------------
read_state_list() {
  local key="$1"
  awk -v k="$key:" '
    $0 == k { active=1; next }
    active && /^  / { sub(/^  /, ""); print; next }
    active && /^[^ ]/ { active=0 }
  ' "$PARSED_STATE"
}

mapfile -t NON_DELEGATE_PENDING < <(read_state_list non_delegate_pending_phases)
mapfile -t AC_LESS              < <(read_state_list ac_less)

declare -A AC_LESS_SET
for pid in "${AC_LESS[@]:-}"; do
  [ -z "$pid" ] && continue
  AC_LESS_SET["$pid"]=1
done

# Targeted scope = non_delegate_pending - ac_less (Phase 4 WI 4.8 step 4).
declare -a TARGET_PHASES
for pid in "${NON_DELEGATE_PENDING[@]:-}"; do
  [ -z "$pid" ] && continue
  if [ "${AC_LESS_SET[$pid]:-0}" = "1" ]; then
    continue
  fi
  TARGET_PHASES+=("$pid")
done

# ----------------------------------------------------------------------
# Build the merged candidate. Plan bytes first, then any specs from the
# round input appended verbatim. This is sufficient for the grep-based
# coverage check: a `risk: AC-N.M` reference appearing in EITHER source
# counts as coverage. The grep target is the merged candidate -- never
# the plan alone, never the drafter-output alone (per AC-4.8).
# ----------------------------------------------------------------------
{
  cat "$PLAN_FILE"
  if [ "$ROUND_INPUT" != "/dev/null" ]; then
    # Append a separator and the round-input content. Both Phase 3
    # drafter output and Phase 4 refiner output contain `### Tests`
    # subsections OR `risk:` references that the grep needs to see.
    printf '\n\n<!-- merged-candidate-overlay round=%s -->\n' "$ROUND_N"
    cat "$ROUND_INPUT"
  fi
} > "$CANDIDATE_OUT"

# ----------------------------------------------------------------------
# For each target phase, locate the `### Acceptance Criteria` block in
# the plan and enumerate its `AC-<phase>.<n>[<sub-letter>]?` IDs.
# Then grep the candidate for `risk: <id>` -- emit a synthetic finding
# if missing.
#
# AC-ID extraction is fenced-code-block-aware (mirrors the parse-plan
# invariant); sub-phase ids like `3b` are matched literally.
# ----------------------------------------------------------------------
extract_acs_for_phase() {
  local pid="$1"
  # Note: mawk does not support 3-argument match(); use match() + RSTART/
  # RLENGTH and substr() in POSIX-portable form. We anchor with `- [`
  # and explicit AC- prefix patterns.
  awk -v target="$pid" '
    BEGIN { in_code=0; in_phase=0; in_ac=0 }
    /^```/ { in_code = 1 - in_code; next }
    in_code { next }
    /^## Phase / {
      line=$0
      sub(/^## Phase[[:space:]]+/, "", line)
      n = split(line, parts, /[ \t:]/)
      cur = parts[1]
      in_phase = (cur == target) ? 1 : 0
      in_ac = 0
      next
    }
    !in_phase { next }
    /^## / { exit }
    /^### Acceptance Criteria/ { in_ac=1; next }
    /^### / { in_ac=0; next }
    in_ac {
      # Canonical AC bullet form:
      #   - [ ] AC-<phase>.<n>[<sub-letter>]? -- text
      # Phase numeral may itself include a sub-letter (3b).
      # Match prefix `- [<x>] AC-` then capture AC-<phase-num>.<n>.
      if ($0 ~ /^- \[[ xX]\] AC-[0-9]+[a-z]?\.[0-9]+[a-z]?/) {
        # Strip prefix `- [<x>] ` (8 chars: dash, space, bracket, marker, bracket, space).
        rest = $0
        sub(/^- \[[ xX]\] /, "", rest)
        # Now `rest` begins with the AC-id followed by ` ` or `-`.
        # Extract leading AC-N.M[a-z]? token.
        # Pattern: AC- digits letter? . digits letter?.
        if (match(rest, /^AC-[0-9]+[a-z]?\.[0-9]+[a-z]?/) > 0) {
          ac_id = substr(rest, RSTART, RLENGTH)
          print ac_id
        }
      }
    }
  ' "$PLAN_FILE"
}

: > "$FINDINGS_OUT"

for pid in "${TARGET_PHASES[@]:-}"; do
  [ -z "$pid" ] && continue
  while IFS= read -r ac_id; do
    [ -z "$ac_id" ] && continue
    # Grep the candidate (merged) for `risk: <ac_id>`.
    # The pattern admits the `[risk: <id>]` bracket form too because the
    # bullet form is `[risk: AC-N.M]` (per Phase 3 spec).
    if ! grep -E -q -- "risk:[[:space:]]*${ac_id}([^a-zA-Z0-9]|\$)" "$CANDIDATE_OUT"; then
      printf 'Coverage floor violated: %s has no spec. Blast radius: major - coverage floor is the convergence precondition.\n' "$ac_id" >> "$FINDINGS_OUT"
    fi
  done < <(extract_acs_for_phase "$pid")
done

exit 0
