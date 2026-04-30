#!/bin/bash
# re-invocation-detect.sh -- Phase 5 WI 5.5 re-invocation detection for
# /draft-tests.
#
# Determines whether the plan file already contains at least one
# `### Tests` subsection at column 0 outside fenced code blocks. If so,
# the invocation is REFINEMENT mode: the existing specs are the round-0
# draft; the Phase 4 review loop runs against them; the refined output
# is written back in place.
#
# Per WI 5.5 / AC-5.5: re-running on a plan that already has `### Tests`
# subsections refines them in place (no duplicated headings, no nested
# subsections) and appends a `## Test Spec Revisions` row per phase
# whose specs changed. Append/idempotency is handled by
# append-tests-section.sh's existing skip path; this script is the
# detection helper.
#
# Usage:
#   bash re-invocation-detect.sh <plan-file>
#
# Exit codes:
#   0 -- re-invocation detected (>= 1 `### Tests` subsection present).
#        Stdout: `re-invocation`.
#   1 -- no `### Tests` subsection -- first invocation. Stdout: `first`.
#   2 -- usage error.
#   3 -- input file missing.

set -eu

PLAN_FILE="${1:-}"
if [ -z "$PLAN_FILE" ]; then
  echo "Usage: $0 <plan-file>" >&2
  exit 2
fi
if [ ! -f "$PLAN_FILE" ]; then
  echo "Error: plan file '$PLAN_FILE' not found." >&2
  exit 3
fi

# Fenced-code-block-aware scan for `### Tests` at column 0.
found=$(awk '
  BEGIN { in_code=0; found=0 }
  /^```/ { in_code = 1 - in_code; next }
  in_code { next }
  /^### Tests([[:space:]]|$)/ { found=1; exit }
  END { print found }
' "$PLAN_FILE")

if [ "$found" = "1" ]; then
  echo "re-invocation"
  exit 0
fi
echo "first"
exit 1
