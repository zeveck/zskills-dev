#!/bin/bash
# pr-monitor.sh — Block until a PR's CI checks complete; report pass/fail.
#
# Owner: /land-pr (skills/land-pr).
# Spec:  plans/PR_LANDING_UNIFICATION.md WI 1.5.
#
# Consolidated successor to skills/commit/scripts/poll-ci.sh. Differences
# from poll-ci.sh:
#   - Emits structured KEY=VALUE on stdout (CI_STATUS, CI_LOG_FILE).
#   - Captures failure log to a sidecar file (--log-out) for fix-cycle agents.
#   - All stderr from fallible gh calls goes to a captured log file —
#     never silently dropped via 2>/dev/null. (Past failure: poll-ci.sh
#     used 2>/dev/null at lines 34/49/51, hiding gh auth errors. See
#     CLAUDE.md "skill-framework repo — surface bugs, don't patch.")
#   - Uses WATCH_EXIT (not WATCH_RC) — DA2-5: matches the existing
#     conformance assertion at tests/test-skill-conformance.sh:68 so
#     the assertion is mechanically relocatable in WI 2.7.
#
# Args:
#   --pr      <number>   GitHub PR number (required, digits only)
#   --timeout <sec>      seconds to wait on `--watch` (default 600)
#   --log-out <path>     where to write the failure log (required)
#
# Stdout (KEY=VALUE):
#   CI_STATUS=pass|fail|pending|none|unknown
#   CI_LOG_FILE=<path-or-empty>
#
# Exits:
#   0  — poll completed (regardless of pass/fail)
#   2  — usage error
#   20 — pre-condition failed (PR not numeric, or `gh auth status` fails)

set -u

PR_NUMBER=""
TIMEOUT=600
LOG_OUT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --pr)      shift; PR_NUMBER="${1:-}" ;;
    --timeout) shift; TIMEOUT="${1:-}" ;;
    --log-out) shift; LOG_OUT="${1:-}" ;;
    *) echo "ERROR: pr-monitor.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
  shift || true
done

if [ -z "$PR_NUMBER" ]; then
  echo "ERROR: pr-monitor.sh: --pr is required" >&2
  exit 2
fi
if [ -z "$LOG_OUT" ]; then
  echo "ERROR: pr-monitor.sh: --log-out is required" >&2
  exit 2
fi
if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "ERROR: pr-monitor.sh: --pr must be numeric (got '$PR_NUMBER')" >&2
  exit 20
fi
if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]]; then
  echo "ERROR: pr-monitor.sh: --timeout must be numeric (got '$TIMEOUT')" >&2
  exit 2
fi

STDERR_LOG="$LOG_OUT.stderr"

# Pre-flight: gh auth must work before we try to query.
if ! gh auth status >"$STDERR_LOG" 2>&1; then
  echo "ERROR: pr-monitor.sh: gh auth status failed — see $STDERR_LOG" >&2
  cat "$STDERR_LOG" >&2
  exit 20
fi

# Step 1 — Pre-check loop. Up to 3 attempts × 10s for checks to register.
CHECK_COUNT=0
for _i in 1 2 3; do
  PR_CHECKS_JSON=""
  if PR_CHECKS_JSON=$(gh pr checks "$PR_NUMBER" --json name 2>"$STDERR_LOG"); then
    # `gh pr checks --json name` returns a JSON array. Detect "non-empty
    # array" via bash regex: any object inside the brackets.
    if [[ "$PR_CHECKS_JSON" =~ \[[[:space:]]*\{ ]]; then
      CHECK_COUNT=1
      break
    fi
  fi
  sleep 10
done

# Step 2 — No checks ever registered. Emit none and exit cleanly.
if [ "$CHECK_COUNT" -eq 0 ]; then
  echo "CI_STATUS=none"
  echo "CI_LOG_FILE="
  exit 0
fi

# Step 3 — Initial poll: `timeout <T> gh pr checks <PR> --watch`. The
# --watch exit code is unreliable across gh versions, so we ONLY trust
# the exit code from `timeout(1)` to mean "still running" (124).
# Otherwise we re-check explicitly below.
set +e
timeout "$TIMEOUT" gh pr checks "$PR_NUMBER" --watch >/dev/null 2>"$STDERR_LOG"
WATCH_EXIT=$?
set -e

# Step 4 — Honor only WATCH_EXIT=124 (timeout's "still running" signal).
if [ "$WATCH_EXIT" -eq 124 ]; then
  echo "CI_STATUS=pending"
  echo "CI_LOG_FILE="
  exit 0
fi

# Step 5 — Re-check (per fix 87af82a). `gh pr checks` (no --watch) DOES
# signal pass/fail/pending via exit code: 0=pass, 1=fail, 8=pending.
set +e
gh pr checks "$PR_NUMBER" >/dev/null 2>"$STDERR_LOG"
RECHECK_RC=$?
set -e

CI_STATUS="unknown"
case "$RECHECK_RC" in
  0) CI_STATUS="pass" ;;
  1) CI_STATUS="fail" ;;
  8) CI_STATUS="pending" ;;
  *) CI_STATUS="unknown" ;;
esac

# Step 6 — On fail, attempt to capture the failure log to $LOG_OUT.
CI_LOG_FILE=""
if [ "$CI_STATUS" = "fail" ]; then
  # Extract a run ID from `gh pr checks --json link`. Bash regex on the
  # URL — actions URLs end with `/runs/<run-id>` (sometimes followed by
  # `/job/<job-id>` for job-level links).
  CHECKS_LINKS_JSON=""
  RUN_ID=""
  if CHECKS_LINKS_JSON=$(gh pr checks "$PR_NUMBER" --json link 2>"$STDERR_LOG"); then
    if [[ "$CHECKS_LINKS_JSON" =~ /runs/([0-9]+) ]]; then
      RUN_ID="${BASH_REMATCH[1]}"
    fi
  fi

  if [ -n "$RUN_ID" ]; then
    if gh run view --log-failed "$RUN_ID" >"$LOG_OUT" 2>"$STDERR_LOG"; then
      CI_LOG_FILE="$LOG_OUT"
    else
      # gh run view failed — leave CI_LOG_FILE empty so caller's fix
      # agent handles "missing log" gracefully (per spec).
      CI_LOG_FILE=""
    fi
  fi
  # If RUN_ID extraction failed, CI_LOG_FILE stays empty.
fi

echo "CI_STATUS=$CI_STATUS"
echo "CI_LOG_FILE=$CI_LOG_FILE"
exit 0
