#!/bin/bash
# verify-completed-checksums.sh -- Phase 5 WI 5.8 / AC-5.9 Completed-
# phase checksum verification before final write.
#
# Re-reads each Completed phase section bytes (using the same broad-form,
# fenced-code-block-aware boundary as parse-plan.sh) and re-computes the
# SHA-256. Compares against the value stored in parsed-state's
# `completed_phases:` list. If any differ, the script STOPS with a
# non-zero exit code and emits a clear error naming the drifted phases.
#
# This guards the final-write moment: if the plan-mutating sequence in
# Phases 3+5 has accidentally touched a Completed phase, the skill must
# refuse to write.
#
# Usage:
#   bash verify-completed-checksums.sh <plan-file> <parsed-state>
#
# Exit codes:
#   0 -- all Completed phases byte-identical to Phase 1 checksum.
#   1 -- one or more drifted; error message lists each on stderr.
#   2 -- usage error.
#   3 -- input file missing.

set -u

PLAN_FILE="${1:-}"
PARSED_STATE="${2:-}"

if [ -z "$PLAN_FILE" ] || [ -z "$PARSED_STATE" ]; then
  echo "Usage: $0 <plan-file> <parsed-state>" >&2
  exit 2
fi
for f in "$PLAN_FILE" "$PARSED_STATE"; do
  if [ ! -f "$f" ]; then
    echo "Error: input file '$f' not found." >&2
    exit 3
  fi
done

# ----------------------------------------------------------------------
# Read parsed-state's completed_phases entries (id:sha256).
# ----------------------------------------------------------------------
mapfile -t COMPLETED_ENTRIES < <(awk '
  $0 == "completed_phases:" { active=1; next }
  active && /^  / { sub(/^  /, ""); print; next }
  active && /^[^ ]/ { active=0 }
' "$PARSED_STATE")

if [ "${#COMPLETED_ENTRIES[@]}" -eq 0 ]; then
  # No Completed phases -- nothing to verify. Pass.
  exit 0
fi

# ----------------------------------------------------------------------
# Read plan file lines, identify each Completed phase's body, and
# compute SHA-256 of those bytes. Identical algorithm to parse-plan.sh.
# ----------------------------------------------------------------------
mapfile -t LINES < "$PLAN_FILE"
N=${#LINES[@]}

declare -a L2_INDICES
declare -a L2_IS_PHASE
declare -a PHASE_IDS_BODY
declare -a PHASE_LINE_START
in_code=0
for ((i=0; i<N; i++)); do
  line="${LINES[$i]}"
  if [[ "$line" =~ ^\`\`\` ]]; then
    in_code=$((1 - in_code))
    continue
  fi
  if [ $in_code -ne 0 ]; then continue; fi
  if [[ "$line" =~ ^##[[:space:]] ]]; then
    L2_INDICES+=("$i")
    if [[ "$line" =~ ^##[[:space:]]+Phase[[:space:]]+([^[:space:]:]+) ]]; then
      pid="${BASH_REMATCH[1]}"
      pid="${pid%:}"
      PHASE_IDS_BODY+=("$pid")
      PHASE_LINE_START+=("$i")
      L2_IS_PHASE+=("1")
    else
      L2_IS_PHASE+=("0")
    fi
  fi
done
NUM_PHASES=${#PHASE_IDS_BODY[@]}
NUM_L2=${#L2_INDICES[@]}
declare -a PHASE_LINE_END
for ((k=0; k<NUM_PHASES; k++)); do
  start=${PHASE_LINE_START[$k]}
  end=$((N - 1))
  for ((m=0; m<NUM_L2; m++)); do
    li=${L2_INDICES[$m]}
    if [ $li -gt $start ]; then
      end=$((li - 1))
      break
    fi
  done
  PHASE_LINE_END+=("$end")
done

declare -A PHASE_START_BY_ID
declare -A PHASE_END_BY_ID
for ((k=0; k<NUM_PHASES; k++)); do
  PHASE_START_BY_ID["${PHASE_IDS_BODY[$k]}"]="${PHASE_LINE_START[$k]}"
  PHASE_END_BY_ID["${PHASE_IDS_BODY[$k]}"]="${PHASE_LINE_END[$k]}"
done

# ----------------------------------------------------------------------
# For each (pid, expected_sha) pair from parsed-state, recompute the
# SHA from the current plan body and diff.
# ----------------------------------------------------------------------
DRIFTED=()
for entry in "${COMPLETED_ENTRIES[@]}"; do
  [ -z "$entry" ] && continue
  pid="${entry%%:*}"
  expected_sha="${entry#*:}"
  start_line="${PHASE_START_BY_ID[$pid]:-}"
  end_line="${PHASE_END_BY_ID[$pid]:-}"
  if [ -z "$start_line" ] || [ -z "$end_line" ]; then
    DRIFTED+=("$pid (phase no longer present in plan)")
    continue
  fi
  tmp_section="$(mktemp)"
  {
    for ((j=start_line; j<=end_line; j++)); do
      printf '%s\n' "${LINES[$j]}"
    done
  } > "$tmp_section"
  actual_sha=$(sha256sum "$tmp_section" | awk '{print $1}')
  rm -f "$tmp_section"
  if [ "$actual_sha" != "$expected_sha" ]; then
    DRIFTED+=("$pid (expected $expected_sha, got $actual_sha)")
  fi
done

if [ "${#DRIFTED[@]}" -gt 0 ]; then
  echo "Error: Completed-phase checksum drift detected. The following Completed phases differ from their Phase 1 checksums:" >&2
  for d in "${DRIFTED[@]}"; do
    echo "  - Phase $d" >&2
  done
  echo "Refusing to write the plan file. Re-inspect any edits and re-run." >&2
  exit 1
fi

exit 0
