#!/bin/bash
# Wrapper for tests/test-demo-server-interactive.py — exercises the
# interactive demo server's SIM LOGIC headlessly (no HTTP, no browser):
#   (a) a dragged item persists across a state rebuild
#   (b) an item placed in Ready picks up a claim and eventually completes
#   (c) the concurrency cap holds (<=N in-flight even with >N in Ready)
#   (d) items NOT in Ready never get a claim or auto-move
#
# Run from repo root: bash tests/test-demo-server-interactive.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
skip() { printf '\033[33m  SKIP\033[0m %s\n' "$1"; SKIP_COUNT=$((SKIP_COUNT + 1)); }

print_summary_and_exit() {
  echo ""
  echo "---"
  local total=$((PASS_COUNT + FAIL_COUNT))
  if [ "$FAIL_COUNT" -eq 0 ]; then
    printf '\033[32mResults: %d passed, %d failed\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT"
    exit 0
  else
    printf '\033[31mResults: %d passed, %d failed\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT"
    exit 1
  fi
}

# Resolve Python (project convention: python3, fall back to python).
PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
if [ -z "$PYTHON" ]; then
  skip "Python 3 not available — demo sim tests skipped"
  print_summary_and_exit
fi

PY_OUT=$("$PYTHON" "$SCRIPT_DIR/test-demo-server-interactive.py" 2>&1)
PY_RC=$?
echo "$PY_OUT"

# Re-emit each python OK/FAIL line through the bash counters so the outer
# run-all.sh parser sees a single canonical Results line from this wrapper.
while IFS= read -r line; do
  case "$line" in
    OK\ *)   pass "${line#OK }" ;;
    FAIL\ *) fail "${line#FAIL }" ;;
  esac
done <<< "$PY_OUT"

if [ "$PY_RC" != "0" ] && [ "$FAIL_COUNT" -eq 0 ]; then
  fail "python harness exited non-zero ($PY_RC) with no per-test failures parsed"
fi

# Registration self-check.
if grep -q "test-demo-server-interactive.sh" "$REPO_ROOT/tests/run-all.sh"; then
  pass "tests/run-all.sh references test-demo-server-interactive.sh"
else
  fail "tests/run-all.sh missing test-demo-server-interactive.sh registration"
fi

print_summary_and_exit
