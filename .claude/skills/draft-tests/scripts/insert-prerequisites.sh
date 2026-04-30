#!/bin/bash
# insert-prerequisites.sh -- AC-2.10 byte-preserving insertion / replacement
# of `## Prerequisites` between `## Overview` and `## Progress Tracker` in
# a plan file.
#
# Usage:
#   bash insert-prerequisites.sh <plan-file> <prereq-text-file>
#
# Arguments:
#   <plan-file>          Plan markdown file. Mutated in place. Every
#                        level-2 section other than `## Prerequisites`
#                        MUST be byte-identical before/after (broad form
#                        per Phase 2 AC-2.10 -- including non-canonical
#                        sections like `## Anti-Patterns -- Hard
#                        Constraints`, `## Non-Goals`, etc.).
#   <prereq-text-file>   File containing the verbatim `## Prerequisites`
#                        block (heading line + body) to insert. Trailing
#                        newline normalised to one blank line below the
#                        block.
#
# Behaviour:
#   - If `## Prerequisites` already exists in the plan, the existing block
#     is replaced in place (boundaries: heading line through the byte
#     before the next `## ` heading at column 0 outside fenced code
#     blocks).
#   - If `## Prerequisites` does not exist, the block is inserted on a
#     blank line BEFORE `## Progress Tracker`. Insertion preserves the
#     exact lines that surround the insertion point: the rule is "find
#     the line index of `## Progress Tracker`; insert the block followed
#     by one blank line BEFORE it; do not consume / mutate the blank
#     line that the source had above the tracker (if any)."
#   - If the plan has no `## Progress Tracker` heading, exit non-zero
#     with an error -- the orchestrator should call this only when a
#     tracker is known to exist (refuse-to-run check in Phase 1
#     guarantees this for /draft-tests).
#
# Fenced-code-block awareness mirrors parse-plan.sh: a `## ` line inside
# ```` ``` ```` blocks is NOT a heading.

set -eu

PLAN_FILE="${1:-}"
PREREQ_FILE="${2:-}"

if [ -z "$PLAN_FILE" ] || [ -z "$PREREQ_FILE" ]; then
  echo "Usage: $0 <plan-file> <prereq-text-file>" >&2
  exit 2
fi
if [ ! -f "$PLAN_FILE" ]; then
  echo "Error: plan file '$PLAN_FILE' not found." >&2
  exit 3
fi
if [ ! -f "$PREREQ_FILE" ]; then
  echo "Error: prereq text file '$PREREQ_FILE' not found." >&2
  exit 3
fi

mapfile -t LINES < "$PLAN_FILE"
N=${#LINES[@]}

# Detect original trailing-newline state. mapfile strips a single trailing
# newline; we need to preserve.
ORIG_TRAILING_NL=1
if [ "$(tail -c1 "$PLAN_FILE" | od -An -c | tr -d ' ')" != '\n' ]; then
  ORIG_TRAILING_NL=0
fi

# Pass 1 -- find Prerequisites and Progress Tracker line indices, fenced-aware.
in_code=0
PREREQ_START=-1
PREREQ_END=-1
TRACKER_LINE=-1
declare -a L2_INDICES
for ((i=0; i<N; i++)); do
  line="${LINES[$i]}"
  if [[ "$line" =~ ^\`\`\` ]]; then
    in_code=$((1 - in_code))
    continue
  fi
  if [ $in_code -ne 0 ]; then continue; fi
  if [[ "$line" =~ ^##[[:space:]] ]]; then
    L2_INDICES+=("$i")
    if [ $PREREQ_START -ne -1 ] && [ $PREREQ_END -eq -1 ]; then
      PREREQ_END=$((i - 1))
    fi
    if [[ "$line" =~ ^##[[:space:]]+Prerequisites[[:space:]]*$ ]]; then
      PREREQ_START=$i
    fi
    if [[ "$line" =~ ^##[[:space:]]+Progress[[:space:]]+Tracker ]]; then
      TRACKER_LINE=$i
    fi
  fi
done
# If PREREQ_START was set and no later L2 closed it, end-of-file is the
# (exclusive) end -- but Prerequisites should never be the last section in
# practice. Bound by N-1 defensively.
if [ $PREREQ_START -ne -1 ] && [ $PREREQ_END -eq -1 ]; then
  PREREQ_END=$((N - 1))
fi

if [ $TRACKER_LINE -eq -1 ]; then
  echo "Error: no '## Progress Tracker' section in '$PLAN_FILE'." >&2
  exit 4
fi

# Read the prereq block content. Trim a trailing newline if any (we re-add
# exactly one separator blank line below).
PREREQ_RAW="$(cat "$PREREQ_FILE")"
# Drop a trailing single newline.
PREREQ_RAW="${PREREQ_RAW%$'\n'}"

# Build the new plan content.
TMP_OUT="$(mktemp)"

if [ $PREREQ_START -ne -1 ]; then
  # Replace existing Prerequisites block in place.
  {
    for ((i=0; i<PREREQ_START; i++)); do
      printf '%s\n' "${LINES[$i]}"
    done
    printf '%s\n' "$PREREQ_RAW"
    # Ensure exactly one blank line follows before the rest. If the
    # next surviving line (PREREQ_END+1) is already blank, do nothing
    # extra; else insert a blank line.
    next_idx=$((PREREQ_END + 1))
    if [ $next_idx -lt $N ]; then
      if [ -n "${LINES[$next_idx]:-}" ]; then
        printf '\n'
      fi
    fi
    for ((i=PREREQ_END+1; i<N; i++)); do
      printf '%s\n' "${LINES[$i]}"
    done
  } > "$TMP_OUT"
else
  # Insert before Progress Tracker, byte-preserving every other section.
  # Behavior:
  #   - Print every line up to and INCLUDING TRACKER_LINE-1 (i.e., keep
  #     the blank line that conventionally sits above ## Progress Tracker
  #     -- it logically belongs to the prior Overview section and must
  #     not be moved).
  #   - Print the Prerequisites block.
  #   - Print exactly ONE blank-line separator before the tracker.
  #   - Print TRACKER_LINE..N-1 (the tracker and beyond).
  #
  # Net effect (when prior layout has a single blank between Overview's
  # closing line and `## Progress Tracker`):
  #
  #   ...Overview body...
  #   <blank>          <-- preserved (Overview's tail)
  #   ## Prerequisites <-- inserted block
  #   <body>
  #   <blank>          <-- inserted separator
  #   ## Progress Tracker
  #
  # When AC-2.10 awk-extracts `## Overview` (heading up to next `## `),
  # both runs yield IDENTICAL bytes -- the original file's blank above
  # tracker is preserved.
  {
    for ((i=0; i<TRACKER_LINE; i++)); do
      printf '%s\n' "${LINES[$i]}"
    done
    printf '%s\n' "$PREREQ_RAW"
    printf '\n'
    for ((i=TRACKER_LINE; i<N; i++)); do
      printf '%s\n' "${LINES[$i]}"
    done
  } > "$TMP_OUT"
fi

# Restore original trailing-newline state.
if [ "$ORIG_TRAILING_NL" -eq 0 ]; then
  truncate -s -1 "$TMP_OUT"
fi

mv "$TMP_OUT" "$PLAN_FILE"
exit 0
