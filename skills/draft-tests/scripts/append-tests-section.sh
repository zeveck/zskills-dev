#!/bin/bash
# append-tests-section.sh -- Phase 3 mechanical `### Tests` subsection
# inserter for /draft-tests.
#
# Reads a plan file and inserts a `### Tests` subsection into a single
# named phase, at the position-priority slot defined by Phase 3 WI 3.5:
#
#   (1) immediately after the phase's `### Acceptance Criteria` block;
#   (2) else after `### Design & Constraints`;
#   (3) else after `### Work Items`;
#   (4) never before `### Goal`, never inside an `### Execution: ...`
#       subsection.
#
# If `### Tests` already exists in the phase (re-invocation), this script
# is a no-op -- the plan file is left byte-identical. (Phase 5's
# refinement path handles updates to existing `### Tests` content.)
#
# Usage:
#   bash append-tests-section.sh <plan-file> <phase-id> <tests-body-file>
#
# Arguments:
#   <plan-file>         Path to the plan .md file. Mutated in place.
#   <phase-id>          Phase identifier (e.g. "3", "1a", "3b-i") matching
#                       the `## Phase <id>` heading literally.
#   <tests-body-file>   Path to a file whose contents become the body of
#                       the new `### Tests` subsection (the lines BELOW
#                       the heading). Caller is responsible for the body
#                       content. The script appends a single trailing
#                       blank line after the body.
#
# The inserted block looks like:
#
#   ### Tests
#
#   <contents of tests-body-file>
#
# Section-boundary scanning is fenced-code-block-aware: ``` toggles an
# `in_code` flag and `## ` / `### ` heading detection runs only when
# `in_code == 0` -- mirrors parse-plan.sh's invariant.

set -eu

PLAN_FILE="${1:-}"
PHASE_ID="${2:-}"
BODY_FILE="${3:-}"

if [ -z "$PLAN_FILE" ] || [ -z "$PHASE_ID" ] || [ -z "$BODY_FILE" ]; then
  echo "Usage: $0 <plan-file> <phase-id> <tests-body-file>" >&2
  exit 2
fi

if [ ! -f "$PLAN_FILE" ]; then
  echo "Error: plan file '$PLAN_FILE' not found." >&2
  exit 3
fi

if [ ! -f "$BODY_FILE" ]; then
  echo "Error: tests-body file '$BODY_FILE' not found." >&2
  exit 4
fi

# ----------------------------------------------------------------------
# Read the plan into an array.
# ----------------------------------------------------------------------
mapfile -t LINES < "$PLAN_FILE"
N=${#LINES[@]}

# ----------------------------------------------------------------------
# Locate the phase: a line `## Phase <PHASE_ID>` (followed by space, em-
# dash, double-dash, colon, or end-of-line) at column 0 outside fenced
# code blocks. End is the next `## ` heading outside fences or EOF.
# ----------------------------------------------------------------------
phase_start=-1
phase_end=-1
in_code=0
for ((i=0; i<N; i++)); do
  line="${LINES[$i]}"
  if [[ "$line" =~ ^\`\`\` ]]; then
    in_code=$((1 - in_code))
    continue
  fi
  if [ $in_code -ne 0 ]; then continue; fi
  if [ $phase_start -eq -1 ]; then
    # Anchor: match the literal phase id followed by whitespace, em-dash,
    # double-dash, colon, or end-of-line. Use a literal-id compare to
    # avoid regex-meta surprises in the id.
    if [[ "$line" =~ ^##[[:space:]]+Phase[[:space:]]+([^[:space:]:]+) ]]; then
      this_id="${BASH_REMATCH[1]}"
      this_id="${this_id%:}"
      if [ "$this_id" = "$PHASE_ID" ]; then
        phase_start=$i
      fi
    fi
  else
    if [[ "$line" =~ ^##[[:space:]] ]]; then
      phase_end=$((i - 1))
      break
    fi
  fi
done
if [ $phase_start -eq -1 ]; then
  echo "Error: phase '$PHASE_ID' not found in '$PLAN_FILE'." >&2
  exit 5
fi
if [ $phase_end -eq -1 ]; then
  phase_end=$((N - 1))
fi

# ----------------------------------------------------------------------
# Within [phase_start..phase_end], locate `### ` subsections. Skip
# anything inside a fenced code block. Track:
#   - existing `### Tests` (idempotent skip)
#   - last line of `### Acceptance Criteria` body (priority 1)
#   - last line of `### Design & Constraints` body (priority 2)
#   - last line of `### Work Items` body (priority 3)
#   - any `### Execution: ` subsection (do NOT insert inside it)
# Each "last line of <subsection> body" = last line BEFORE the next
# `### ` or `## ` heading at column 0 outside fences.
# ----------------------------------------------------------------------
# Collect every level-3 heading inside the phase (outside fences) with
# its line index and the heading text.
declare -a SUB_INDICES
declare -a SUB_NAMES
in_code=0
for ((i=phase_start; i<=phase_end; i++)); do
  line="${LINES[$i]}"
  if [[ "$line" =~ ^\`\`\` ]]; then
    in_code=$((1 - in_code))
    continue
  fi
  if [ $in_code -ne 0 ]; then continue; fi
  if [[ "$line" =~ ^###[[:space:]]+(.*)$ ]]; then
    SUB_INDICES+=("$i")
    SUB_NAMES+=("${BASH_REMATCH[1]}")
  fi
done

NUM_SUBS=${#SUB_INDICES[@]}

# Helper: given index k into SUB_*, return the last line of that
# subsection's body (line BEFORE the next ### / ## heading or phase_end).
sub_body_end() {
  local k=$1
  if [ $((k + 1)) -lt $NUM_SUBS ]; then
    echo $((${SUB_INDICES[$((k + 1))]} - 1))
  else
    echo $phase_end
  fi
}

# Find indices of the load-bearing subsections.
ac_idx=-1
dc_idx=-1
wi_idx=-1
tests_idx=-1
for ((k=0; k<NUM_SUBS; k++)); do
  name="${SUB_NAMES[$k]}"
  case "$name" in
    "Acceptance Criteria"|"Acceptance Criteria"*)
      [ "$ac_idx" -eq -1 ] && ac_idx=$k
      ;;
    "Design & Constraints"|"Design & Constraints"*)
      [ "$dc_idx" -eq -1 ] && dc_idx=$k
      ;;
    "Work Items"|"Work Items"*)
      [ "$wi_idx" -eq -1 ] && wi_idx=$k
      ;;
    "Tests"|"Tests"*)
      [ "$tests_idx" -eq -1 ] && tests_idx=$k
      ;;
  esac
done

# Idempotent re-invocation: if `### Tests` already exists in the phase,
# do nothing. Phase 5's refinement path handles updates.
if [ $tests_idx -ne -1 ]; then
  exit 0
fi

# Compute insertion line (insert AFTER this line index, i.e. content
# goes at index insert_after + 1). Position priority:
#   1. After the AC block.
#   2. Else after Design & Constraints.
#   3. Else after Work Items.
#   4. Otherwise: refuse (no anchor; ac-less skip should have been
#      applied upstream by the orchestrator). Exit non-zero so the
#      orchestrator surfaces this as a defect.
insert_after=-1
if [ $ac_idx -ne -1 ]; then
  insert_after=$(sub_body_end $ac_idx)
elif [ $dc_idx -ne -1 ]; then
  insert_after=$(sub_body_end $dc_idx)
elif [ $wi_idx -ne -1 ]; then
  insert_after=$(sub_body_end $wi_idx)
else
  echo "Error: phase '$PHASE_ID' has no anchor (### Acceptance Criteria, ### Design & Constraints, or ### Work Items) for inserting ### Tests; orchestrator should have skipped this phase." >&2
  exit 6
fi

# ----------------------------------------------------------------------
# Build the inserted block. The block is:
#
#   <blank line>
#   ### Tests
#   <blank line>
#   <body lines from BODY_FILE>
#   <blank line>
#
# We emit a leading blank line iff the line at insert_after is non-blank
# (so the heading visually separates from the prior subsection's body).
# We emit a trailing blank line iff the line at insert_after+1 is non-
# blank (so the next subsection's heading separates correctly). When the
# anchor body is followed by a blank line that is itself followed by the
# next heading, both spacing conditions naturally hold.
# ----------------------------------------------------------------------
mapfile -t BODY_LINES < "$BODY_FILE"
# Strip a single trailing blank from BODY_LINES (we add our own blank
# after).
if [ ${#BODY_LINES[@]} -gt 0 ] && [ -z "${BODY_LINES[-1]}" ]; then
  unset 'BODY_LINES[-1]'
fi

# Compose the insertion array.
declare -a BLOCK
# Leading blank if anchor's last line is non-blank.
if [ -n "${LINES[$insert_after]:-}" ]; then
  BLOCK+=("")
fi
BLOCK+=("### Tests")
BLOCK+=("")
for bl in "${BODY_LINES[@]:-}"; do
  BLOCK+=("$bl")
done
# Trailing blank to separate from the next subsection (always include;
# we'll dedupe if the next line is already blank).
BLOCK+=("")

# If the line at insert_after+1 is already blank, skip our trailing blank
# to avoid a double blank line.
if [ $((insert_after + 1)) -lt $N ] && [ -z "${LINES[$((insert_after + 1))]:-}" ]; then
  unset 'BLOCK[-1]'
fi

# ----------------------------------------------------------------------
# Write the new plan file.
# ----------------------------------------------------------------------
tmp_out="$(mktemp)"
{
  for ((i=0; i<=insert_after; i++)); do
    printf '%s\n' "${LINES[$i]}"
  done
  for bl in "${BLOCK[@]:-}"; do
    printf '%s\n' "$bl"
  done
  for ((i=insert_after+1; i<N; i++)); do
    printf '%s\n' "${LINES[$i]}"
  done
} > "$tmp_out"

# Preserve original trailing-newline state. mapfile strips a single
# trailing newline from the final element if the file had one; printf
# above re-adds one per line, so a file that originally lacked a final
# newline will gain one. Restore to match.
if [ "$(tail -c1 "$PLAN_FILE" | od -An -c | tr -d ' ')" != '\n' ]; then
  truncate -s -1 "$tmp_out"
fi
mv "$tmp_out" "$PLAN_FILE"

exit 0
