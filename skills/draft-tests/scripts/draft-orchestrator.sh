#!/bin/bash
# draft-orchestrator.sh -- Phase 3 mechanical orchestrator for /draft-tests.
#
# Reads the Phase 1 parsed-state file, iterates over every Pending
# non-delegate non-ac-less phase, fetches per-phase spec text from a
# pre-built specs file (the drafter agent's output), and calls
# append-tests-section.sh to insert each phase's `### Tests` subsection
# into the plan at the position-priority slot.
#
# This script is the SEAM between the LLM-driven drafting agent and the
# deterministic file mutation. The drafting agent (dispatched from
# SKILL.md prose) produces a SPECS FILE on disk; this orchestrator
# consumes it. Tests stub the agent by writing the specs file directly,
# bypassing model invocation -- that is intentional and Phase 6's
# AC-4.5-style "no live LLM in tests" pattern.
#
# Usage:
#   bash draft-orchestrator.sh \
#       <plan-file> <parsed-state> <specs-file> <draft-round-out> [<round-n>]
#
# Arguments:
#   <plan-file>          Plan .md to mutate. The plan is updated in place
#                        with one `### Tests` subsection per Pending non-
#                        delegate non-ac-less phase. Already-present
#                        `### Tests` subsections are left untouched
#                        (idempotent re-invocation -- per AC-3.5).
#   <parsed-state>       Phase 1 parsed-state file
#                        (`/tmp/draft-tests-parsed-<slug>.md`). Read for
#                        `non_delegate_pending_phases:`, `delegate_phases:`,
#                        and `ac_less:` lists. SINGLE SOURCE OF TRUTH --
#                        this script MUST NOT re-derive delegate-ness or
#                        ac-less-ness from the plan body (per WI 3.5/3.6
#                        and AC-3.6).
#   <specs-file>         Pre-built per-phase spec bodies. Format:
#                          phase: <id>
#                          <body line 1>
#                          <body line 2>
#                          ...
#                          phase: <id>
#                          ...
#                        Each `phase:` opens a section; the body lines
#                        below it are the contents to drop into that
#                        phase's `### Tests` body.
#   <draft-round-out>    Per-round drafter output file
#                        (`/tmp/draft-tests-draft-round-N-<slug>.md`).
#                        Written by this script. Contains
#                        `drafted_phases:`, `delegate_skipped_phases:`,
#                        `ac_less_skipped_phases:`, `idempotent_skipped_phases:`,
#                        and the per-phase spec bodies for Phase 4 to
#                        consume.
#   <round-n>            (optional) Round number, default 0. The drafter
#                        runs at round 0; refiner rounds reuse the same
#                        format with N >= 1.
#
# Exit codes:
#   0 -- all targeted phases successfully appended (or idempotently
#        skipped); draft-round file written.
#   2 -- usage error.
#   3 -- input file missing.
#   4 -- specs-file missing required phase (a Pending non-delegate non-
#        ac-less phase had no spec body).

set -eu

PLAN_FILE="${1:-}"
PARSED_STATE="${2:-}"
SPECS_FILE="${3:-}"
ROUND_OUT="${4:-}"
ROUND_N="${5:-0}"

if [ -z "$PLAN_FILE" ] || [ -z "$PARSED_STATE" ] || [ -z "$SPECS_FILE" ] || [ -z "$ROUND_OUT" ]; then
  echo "Usage: $0 <plan-file> <parsed-state> <specs-file> <draft-round-out> [<round-n>]" >&2
  exit 2
fi

for f in "$PLAN_FILE" "$PARSED_STATE" "$SPECS_FILE"; do
  if [ ! -f "$f" ]; then
    echo "Error: input file '$f' not found." >&2
    exit 3
  fi
done

# Resolve owner skill dir for cross-skill script invocation. Prefer the
# CLAUDE_PROJECT_DIR mirror (consumer install); fall back to source-tree
# `$REPO_ROOT/skills/draft-tests/scripts/` (zskills tests).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APPEND_SCRIPT="$SCRIPT_DIR/append-tests-section.sh"
if [ ! -x "$APPEND_SCRIPT" ] && [ ! -f "$APPEND_SCRIPT" ]; then
  echo "Error: append-tests-section.sh not found at '$APPEND_SCRIPT'." >&2
  exit 3
fi

# ----------------------------------------------------------------------
# Read the parsed-state lists.
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
mapfile -t DELEGATE_PHASES      < <(read_state_list delegate_phases)
mapfile -t AC_LESS              < <(read_state_list ac_less)

# Build a set of ac-less phase ids for O(1) lookup.
declare -A AC_LESS_SET
for pid in "${AC_LESS[@]:-}"; do
  [ -z "$pid" ] && continue
  AC_LESS_SET["$pid"]=1
done

# Targeted phases = non_delegate_pending - ac_less.
declare -a TARGET_PHASES
for pid in "${NON_DELEGATE_PENDING[@]:-}"; do
  [ -z "$pid" ] && continue
  if [ "${AC_LESS_SET[$pid]:-0}" = "1" ]; then
    continue
  fi
  TARGET_PHASES+=("$pid")
done

# ----------------------------------------------------------------------
# Parse the specs file into per-phase body files in a tmpdir.
# ----------------------------------------------------------------------
TMPDIR_SPECS="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_SPECS"' EXIT

current_phase=""
current_out=""
while IFS= read -r line || [ -n "$line" ]; do
  if [[ "$line" =~ ^phase:[[:space:]]*(.+)$ ]]; then
    current_phase="${BASH_REMATCH[1]}"
    # Trim trailing whitespace.
    current_phase="$(printf '%s' "$current_phase" | sed 's/[[:space:]]*$//')"
    current_out="$TMPDIR_SPECS/$current_phase"
    : > "$current_out"
    continue
  fi
  if [ -n "$current_phase" ]; then
    printf '%s\n' "$line" >> "$current_out"
  fi
done < "$SPECS_FILE"

# ----------------------------------------------------------------------
# For each targeted phase, check whether the plan already has a `### Tests`
# subsection (idempotent skip), else append it.
# ----------------------------------------------------------------------
declare -a DRAFTED_PHASES
declare -a IDEMPOTENT_SKIPPED

# Helper: detect existing `### Tests` in the named phase using the same
# fenced-code-block-aware scan as append-tests-section.sh.
phase_has_tests() {
  local pid="$1"
  awk -v target="$pid" '
    BEGIN { in_code=0; in_phase=0; found=0 }
    /^```/ { in_code = 1 - in_code; next }
    in_code { next }
    /^## Phase / {
      # Extract phase id after "## Phase ".
      line=$0
      sub(/^## Phase[[:space:]]+/, "", line)
      # phase id = leading non-space token, strip trailing colon.
      n = split(line, parts, /[ \t:]/)
      pid = parts[1]
      if (pid == target) { in_phase=1 } else if (in_phase) { exit }
      next
    }
    in_phase && /^## / { exit }
    in_phase && /^### Tests([ \t]|$)/ { found=1; exit }
    END { exit found ? 0 : 1 }
  ' "$PLAN_FILE"
}

for pid in "${TARGET_PHASES[@]:-}"; do
  [ -z "$pid" ] && continue
  if phase_has_tests "$pid"; then
    IDEMPOTENT_SKIPPED+=("$pid")
    continue
  fi
  body="$TMPDIR_SPECS/$pid"
  if [ ! -f "$body" ]; then
    echo "Error: specs-file '$SPECS_FILE' has no 'phase: $pid' section for non-delegate non-ac-less Pending phase '$pid'." >&2
    exit 4
  fi
  bash "$APPEND_SCRIPT" "$PLAN_FILE" "$pid" "$body"
  DRAFTED_PHASES+=("$pid")
done

# ----------------------------------------------------------------------
# Write the draft-round-N output file. Phase 4 reads this for review.
# Phase 6 conformance test reads `delegate_skipped_phases:` for AC-3.6
# set-equality verification (pairs with parsed-state `delegate_phases:`).
# ----------------------------------------------------------------------
{
  printf 'plan_file: %s\n' "$PLAN_FILE"
  printf 'parsed_state: %s\n' "$PARSED_STATE"
  printf 'specs_file: %s\n' "$SPECS_FILE"
  printf 'round: %s\n' "$ROUND_N"
  printf 'drafted_phases:\n'
  for pid in "${DRAFTED_PHASES[@]:-}"; do
    [ -z "$pid" ] && continue
    printf '  %s\n' "$pid"
  done
  printf 'delegate_skipped_phases:\n'
  for pid in "${DELEGATE_PHASES[@]:-}"; do
    [ -z "$pid" ] && continue
    printf '  %s\n' "$pid"
  done
  printf 'ac_less_skipped_phases:\n'
  for pid in "${AC_LESS[@]:-}"; do
    [ -z "$pid" ] && continue
    printf '  %s\n' "$pid"
  done
  printf 'idempotent_skipped_phases:\n'
  for pid in "${IDEMPOTENT_SKIPPED[@]:-}"; do
    [ -z "$pid" ] && continue
    printf '  %s\n' "$pid"
  done
  # Embed the per-phase spec bodies so Phase 4's reviewer/DA can
  # round-trip the canonical text without re-reading the plan file.
  printf 'specs_begin\n'
  for pid in "${DRAFTED_PHASES[@]:-}"; do
    [ -z "$pid" ] && continue
    printf 'phase: %s\n' "$pid"
    cat "$TMPDIR_SPECS/$pid"
  done
  printf 'specs_end\n'
} > "$ROUND_OUT"

exit 0
