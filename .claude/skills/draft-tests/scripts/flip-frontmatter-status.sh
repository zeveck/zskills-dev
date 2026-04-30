#!/bin/bash
# flip-frontmatter-status.sh -- Phase 5 WI 5.6 single-purpose
# frontmatter `status:` flip for /draft-tests.
#
# When `/draft-tests` appends a backfill phase to a plan whose YAML
# frontmatter has `status: complete`, it MUST flip `status` to
# `status: active` in the same write. `/run-plan` treats
# `status: complete` as terminal and would otherwise refuse to execute
# the new backfill phase, silently orphaning it.
#
# Per AC-5.8:
#   - On a plan with `status: complete` where backfill is appended:
#     resulting plan has `status: active`; every other frontmatter
#     field is byte-identical.
#   - On a plan where the skill does NOT append a backfill phase:
#     frontmatter is byte-identical including `status:` (this script
#     is simply not invoked in that case).
#
# This is the ONLY frontmatter mutation the skill is permitted to make
# (per Design & Constraints "Frontmatter flip is single-purpose").
#
# Usage:
#   bash flip-frontmatter-status.sh <plan-file> [<should-flip>]
#
# Arguments:
#   <plan-file>     Path to the plan .md file. Mutated in place IFF
#                   the frontmatter currently contains `status: complete`
#                   AND <should-flip> is non-zero (default 1).
#   <should-flip>   Optional caller-driven gate. Pass `0` to make this
#                   script a no-op (used as a defensive double-check
#                   before mutation; default 1).
#
# Exit codes:
#   0 -- mutation completed (or no-op because status was not `complete`
#        OR should-flip was 0).
#   2 -- usage error.
#   3 -- input file missing.

set -eu

PLAN_FILE="${1:-}"
SHOULD_FLIP="${2:-1}"

if [ -z "$PLAN_FILE" ]; then
  echo "Usage: $0 <plan-file> [<should-flip>]" >&2
  exit 2
fi

if [ ! -f "$PLAN_FILE" ]; then
  echo "Error: plan file '$PLAN_FILE' not found." >&2
  exit 3
fi

if [ "$SHOULD_FLIP" = "0" ]; then
  exit 0
fi

# ----------------------------------------------------------------------
# Mutate ONLY the `status:` line in the YAML frontmatter (between the
# first two `---` lines). All other lines are byte-identical.
# ----------------------------------------------------------------------
mapfile -t LINES < "$PLAN_FILE"
N=${#LINES[@]}

in_fm=0
fm_seen_open=0
flipped=0
for ((i=0; i<N; i++)); do
  line="${LINES[$i]}"
  if [ $i -eq 0 ] && [ "$line" = "---" ]; then
    in_fm=1
    fm_seen_open=1
    continue
  fi
  if [ $in_fm -eq 1 ] && [ "$line" = "---" ]; then
    in_fm=0
    break
  fi
  if [ $in_fm -eq 1 ]; then
    if [[ "$line" =~ ^status:[[:space:]]*complete[[:space:]]*$ ]]; then
      LINES[$i]="status: active"
      flipped=1
    fi
  fi
done

if [ $flipped -eq 0 ]; then
  # No change required -- plan is byte-identical.
  exit 0
fi

TMP="$(mktemp)"
{
  for ((i=0; i<N; i++)); do
    printf '%s\n' "${LINES[$i]}"
  done
} > "$TMP"

if [ "$(tail -c1 "$PLAN_FILE" | od -An -c | tr -d ' ')" != '\n' ]; then
  truncate -s -1 "$TMP"
fi
mv "$TMP" "$PLAN_FILE"

exit 0
