#!/bin/bash
# pr-merge.sh — Conditionally request auto-merge on a PR.
#
# Owner: /land-pr (skills/land-pr).
# Spec:  plans/PR_LANDING_UNIFICATION.md WI 1.6.
#
# Behavior:
#   1. If --auto-flag != true, emit MERGE_REQUESTED=false MERGE_REASON=auto-not-requested, exit 0.
#   2. If --ci-status not in {pass, none, skipped}, emit
#      MERGE_REQUESTED=false MERGE_REASON=ci-not-passing, exit 0.
#   3. `gh pr merge --auto --squash`. If stderr matches the auto-merge-
#      disabled-on-repo pattern, treat as benign — emit
#      MERGE_REQUESTED=false MERGE_REASON=auto-merge-disabled-on-repo,
#      exit 0.
#   4. On other gh failure: write stderr to a sidecar, emit
#      MERGE_REQUESTED=false MERGE_REASON=gh-error CALL_ERROR_FILE=<path>,
#      exit 30.
#   5. On success: retry `gh pr view --json state --jq .state` up to
#      3× with 2s/4s backoff. Emit MERGE_REQUESTED=true PR_STATE=...
#      (UNKNOWN if all retries fail).
#
# Args:
#   --pr        <number>
#   --auto-flag <true|false>
#   --ci-status <pass|fail|pending|none|skipped|unknown>
#
# Stdout (KEY=VALUE):
#   MERGE_REQUESTED=<bool>
#   MERGE_REASON=<token>
#   PR_STATE=<OPEN|MERGED|UNKNOWN> (only when MERGE_REQUESTED=true)
#   CALL_ERROR_FILE=<path> (only on exit 30)
#
# Exits:
#   0  — request decision made (not-requested OR requested successfully)
#   30 — gh pr merge failed for non-benign reason
#   2  — usage error

set -u

PR_NUMBER=""
AUTO_FLAG=""
CI_STATUS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --pr)         shift; PR_NUMBER="${1:-}" ;;
    --auto-flag)  shift; AUTO_FLAG="${1:-}" ;;
    --ci-status)  shift; CI_STATUS="${1:-}" ;;
    *) echo "ERROR: pr-merge.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
  shift || true
done

for v in PR_NUMBER AUTO_FLAG CI_STATUS; do
  if [ -z "${!v}" ]; then
    echo "ERROR: pr-merge.sh: --${v,,} is required" >&2
    exit 2
  fi
done

if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "ERROR: pr-merge.sh: --pr must be numeric (got '$PR_NUMBER')" >&2
  exit 2
fi

# Step 1 — auto-flag != true → not requested.
if [ "$AUTO_FLAG" != "true" ]; then
  echo "MERGE_REQUESTED=false"
  echo "MERGE_REASON=auto-not-requested"
  exit 0
fi

# Step 2 — CI must be in {pass, none, skipped} for merge to be safe.
case "$CI_STATUS" in
  pass|none|skipped) : ;;
  *)
    echo "MERGE_REQUESTED=false"
    echo "MERGE_REASON=ci-not-passing"
    exit 0
    ;;
esac

# Step 3 — Request auto-merge with squash.
STDERR_LOG="/tmp/land-pr-merge-stderr-$PR_NUMBER-$$.log"

set +e
gh pr merge "$PR_NUMBER" --auto --squash >/dev/null 2>"$STDERR_LOG"
MERGE_RC=$?
set -e

if [ "$MERGE_RC" -ne 0 ]; then
  STDERR_TEXT=$(cat "$STDERR_LOG")

  # Step 4 — auto-merge disabled on repo? Treat as benign.
  if [[ "$STDERR_TEXT" =~ auto[-\ ]merge.*not.*allowed|auto[-\ ]merge.*disabled|repo.*does\ not\ allow\ auto[-\ ]merge ]]; then
    echo "MERGE_REQUESTED=false"
    echo "MERGE_REASON=auto-merge-disabled-on-repo"
    exit 0
  fi

  # Other gh error — capture stderr to sidecar (per WI 1.7: never inline
  # multi-line stderr text into the result file).
  ERR_FILE="/tmp/land-pr-merge-error-$PR_NUMBER-$$.txt"
  cp "$STDERR_LOG" "$ERR_FILE"
  echo "MERGE_REQUESTED=false"
  echo "MERGE_REASON=gh-error"
  echo "CALL_ERROR_FILE=$ERR_FILE"
  exit 30
fi

# Step 5 — Merge requested. Probe state with retries.
PR_STATE="UNKNOWN"
SLEEP_SCHEDULE=(0 2 4)
for attempt in 0 1 2; do
  if [ "${SLEEP_SCHEDULE[$attempt]}" -gt 0 ]; then
    sleep "${SLEEP_SCHEDULE[$attempt]}"
  fi
  STATE_OUT=""
  if STATE_OUT=$(gh pr view "$PR_NUMBER" --json state --jq '.state' 2>"$STDERR_LOG"); then
    if [ -n "$STATE_OUT" ]; then
      PR_STATE="$STATE_OUT"
      break
    fi
  fi
done

echo "MERGE_REQUESTED=true"
echo "PR_STATE=$PR_STATE"
exit 0
