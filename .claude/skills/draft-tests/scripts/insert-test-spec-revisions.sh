#!/bin/bash
# insert-test-spec-revisions.sh -- Phase 5 WI 5.7 `## Test Spec
# Revisions` section inserter / updater for /draft-tests.
#
# Appends (or updates) a `## Test Spec Revisions` section in the plan
# file. Placement (per AC-5.11):
#
#   last `## Phase ...`
#   -> any existing `## Drift Log` (left byte-identical)
#   -> any existing `## Plan Review` (left byte-identical)
#   -> THIS section (`## Test Spec Revisions`)
#   -> any other user-authored trailing non-phase level-2 sections
#      (e.g., `## Plan Quality`, `## Anti-Patterns -- Hard Constraints`,
#      `## Non-Goals`, etc.)
#
# Trailing-section detection is the BROAD FORM: any `## <name>` outside
# fenced code blocks AFTER the last `## Phase` is a trailing section,
# NOT a closed enumeration. Use the same awk-style `in_code` state
# tracker as parse-plan.sh and append-tests-section.sh -- heading
# detection runs only when in_code == 0.
#
# Format (2-column, per AC-5.6 -- never `/refine-plan`'s 4-column form):
#
#   ## Test Spec Revisions
#
#   One row per invocation. Column "Change" summarises structural deltas
#   (spec counts, AC coverage changes, backfill appends) -- never full
#   spec text.
#
#   | Date | Change |
#   |------|--------|
#   | 2026-04-29 | Phase 4: refined spec for AC-4.1; Appended Phase 7 for backfill of Completed phases 2, 3 |
#
# If the section already exists, this script appends a new row to the
# table -- preserving prior rows and the section heading byte-identical.
# If the section does not exist, the script creates it with the
# specified leading prose + first row.
#
# Usage:
#   bash insert-test-spec-revisions.sh \
#       <plan-file> <date> <change-text>
#
# Arguments:
#   <plan-file>     Path to the plan .md file. Mutated in place.
#   <date>          Date string for the row's first column
#                   (e.g., 2026-04-29). Caller must pass the resolved
#                   date -- this script is timezone-agnostic.
#   <change-text>   The change-summary text for the row's second column.
#                   Must NOT contain a literal `|` -- caller is expected
#                   to escape pipes.
#
# Exit codes:
#   0 -- section appended / new row added.
#   2 -- usage error.
#   3 -- input file missing.

set -eu

PLAN_FILE="${1:-}"
DATE="${2:-}"
CHANGE="${3:-}"

if [ -z "$PLAN_FILE" ] || [ -z "$DATE" ] || [ -z "$CHANGE" ]; then
  echo "Usage: $0 <plan-file> <date> <change-text>" >&2
  exit 2
fi

if [ ! -f "$PLAN_FILE" ]; then
  echo "Error: plan file '$PLAN_FILE' not found." >&2
  exit 3
fi

# ----------------------------------------------------------------------
# Read the plan into an array.
# ----------------------------------------------------------------------
mapfile -t LINES < "$PLAN_FILE"
N=${#LINES[@]}

# ----------------------------------------------------------------------
# Locate every level-2 heading at column 0 outside fenced code blocks.
# Track the line index, the heading name, and whether it is a `## Phase`.
# ----------------------------------------------------------------------
declare -a L2_LINES
declare -a L2_NAMES
declare -a L2_IS_PHASE
in_code=0
for ((i=0; i<N; i++)); do
  line="${LINES[$i]}"
  if [[ "$line" =~ ^\`\`\` ]]; then
    in_code=$((1 - in_code))
    continue
  fi
  if [ $in_code -ne 0 ]; then continue; fi
  if [[ "$line" =~ ^##[[:space:]]+(.*)$ ]]; then
    L2_LINES+=("$i")
    L2_NAMES+=("${BASH_REMATCH[1]}")
    if [[ "${BASH_REMATCH[1]}" =~ ^Phase[[:space:]] ]]; then
      L2_IS_PHASE+=("1")
    else
      L2_IS_PHASE+=("0")
    fi
  fi
done

NUM_L2=${#L2_LINES[@]}

# Find the last phase index in L2_*.
last_phase_l2=-1
for ((k=0; k<NUM_L2; k++)); do
  if [ "${L2_IS_PHASE[$k]}" = "1" ]; then
    last_phase_l2=$k
  fi
done

# ----------------------------------------------------------------------
# Find an existing `## Test Spec Revisions` section.
# ----------------------------------------------------------------------
existing_tsr_l2=-1
for ((k=0; k<NUM_L2; k++)); do
  name="${L2_NAMES[$k]}"
  if [[ "$name" =~ ^Test[[:space:]]+Spec[[:space:]]+Revisions ]]; then
    existing_tsr_l2=$k
    break
  fi
done

# ----------------------------------------------------------------------
# CASE A: section exists. Append a new row to its table.
# ----------------------------------------------------------------------
if [ $existing_tsr_l2 -ge 0 ]; then
  tsr_start=${L2_LINES[$existing_tsr_l2]}
  if [ $((existing_tsr_l2 + 1)) -lt $NUM_L2 ]; then
    tsr_end=$((${L2_LINES[$((existing_tsr_l2 + 1))]} - 1))
  else
    tsr_end=$((N - 1))
  fi
  # Find the LAST table row (line starting with `|`) inside the
  # section. Append our new row after it.
  last_row=-1
  for ((j=tsr_start; j<=tsr_end; j++)); do
    if [[ "${LINES[$j]}" =~ ^\| ]]; then
      last_row=$j
    fi
  done
  if [ $last_row -lt 0 ]; then
    # No table at all -- append a fresh table at the end of the section.
    last_row=$tsr_end
  fi
  TMP="$(mktemp)"
  {
    for ((i=0; i<=last_row; i++)); do
      printf '%s\n' "${LINES[$i]}"
    done
    printf '| %s | %s |\n' "$DATE" "$CHANGE"
    for ((i=last_row+1; i<N; i++)); do
      printf '%s\n' "${LINES[$i]}"
    done
  } > "$TMP"
  if [ "$(tail -c1 "$PLAN_FILE" | od -An -c | tr -d ' ')" != '\n' ]; then
    truncate -s -1 "$TMP"
  fi
  mv "$TMP" "$PLAN_FILE"
  exit 0
fi

# ----------------------------------------------------------------------
# CASE B: section does NOT exist. Create it.
#
# Placement: after `## Drift Log` (if exists) AND `## Plan Review` (if
# exists). I.e., insert IMMEDIATELY AFTER whichever of those is the
# latest in the file, OR (if neither exists) immediately after the last
# `## Phase ...`. Subsequent user-authored trailing sections like
# `## Plan Quality` / `## Anti-Patterns -- Hard Constraints` /
# `## Non-Goals` follow this section.
# ----------------------------------------------------------------------
drift_log_l2=-1
plan_review_l2=-1
for ((k=0; k<NUM_L2; k++)); do
  name="${L2_NAMES[$k]}"
  if [[ "$name" =~ ^Drift[[:space:]]+Log ]]; then
    drift_log_l2=$k
  elif [[ "$name" =~ ^Plan[[:space:]]+Review ]]; then
    plan_review_l2=$k
  fi
done

# Determine the anchor index (the L2 we insert AFTER) and the index of
# the section we insert BEFORE.
anchor_l2=-1
if [ $plan_review_l2 -gt $anchor_l2 ]; then anchor_l2=$plan_review_l2; fi
if [ $drift_log_l2 -gt $anchor_l2 ]; then anchor_l2=$drift_log_l2; fi
if [ $anchor_l2 -lt 0 ]; then
  # Neither Drift Log nor Plan Review exist -- anchor is the last
  # `## Phase`.
  anchor_l2=$last_phase_l2
fi

# The line BEFORE which we insert our new section. It is the start line
# of the L2 immediately AFTER anchor_l2 (the next trailing section); if
# anchor_l2 is the last L2, we append at end of file.
if [ $anchor_l2 -lt 0 ]; then
  # No phases either? Fall back to end of file.
  insert_before=$N
elif [ $((anchor_l2 + 1)) -lt $NUM_L2 ]; then
  insert_before=${L2_LINES[$((anchor_l2 + 1))]}
else
  insert_before=$N
fi

# Build the new section block.
declare -a BLOCK
BLOCK+=("## Test Spec Revisions")
BLOCK+=("")
BLOCK+=("One row per invocation. Column \"Change\" summarises structural deltas")
BLOCK+=("(spec counts, AC coverage changes, backfill appends) -- never full")
BLOCK+=("spec text.")
BLOCK+=("")
BLOCK+=("| Date | Change |")
BLOCK+=("|------|--------|")
BLOCK+=("| $DATE | $CHANGE |")
BLOCK+=("")

TMP="$(mktemp)"
{
  for ((i=0; i<insert_before; i++)); do
    printf '%s\n' "${LINES[$i]}"
  done
  # Ensure there is a blank line separator BEFORE our heading if the
  # previous line is non-blank.
  if [ "$insert_before" -gt 0 ] && [ -n "${LINES[$((insert_before - 1))]}" ]; then
    printf '\n'
  fi
  for bl in "${BLOCK[@]}"; do
    printf '%s\n' "$bl"
  done
  for ((i=insert_before; i<N; i++)); do
    printf '%s\n' "${LINES[$i]}"
  done
} > "$TMP"

if [ "$(tail -c1 "$PLAN_FILE" | od -An -c | tr -d ' ')" != '\n' ]; then
  truncate -s -1 "$TMP"
fi
mv "$TMP" "$PLAN_FILE"

exit 0
