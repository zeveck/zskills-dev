#!/bin/bash
# Tests for run-plan claim-file collector in collect.py (Phase 3 of
# plans/plans-claim-chip-parity.md).
#
# Wrapper around tests/test-plan-claim-collector.py — the actual
# assertions live in Python (stdlib unittest, no pytest dep). This
# script runs the unittest module and translates each TestCase result
# into the dashboard test format (PASS/FAIL lines + a Results: line).
#
# Run from repo root: bash tests/test-plan-claim-collector.sh
# Output is captured by tests/run-all.sh into the per-worktree
# .test-results.txt per CLAUDE.md.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PKG_PARENT="$REPO_ROOT/skills/zskills-dashboard/scripts"
PY_TEST="$SCRIPT_DIR/test-plan-claim-collector.py"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
skip() { printf '\033[33m  SKIP\033[0m %s\n' "$1"; SKIP_COUNT=$((SKIP_COUNT + 1)); }

# ---------------------------------------------------------------------------
# Python interpreter resolution (CLAUDE.md "Python is required" idiom).
# ---------------------------------------------------------------------------
PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python || true)}"
if [ -z "$PYTHON" ]; then
  echo "python3 not available — skipping all tests"
  skip "python3 not available"
  echo ""
  echo "---"
  printf 'Results: %d passed, %d failed, %d skipped (of %d)\n' \
    "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" \
    "$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))"
  exit 0
fi

if [ ! -f "$PY_TEST" ]; then
  fail "test-plan-claim-collector.py exists at expected path"
  printf 'Results: %d passed, %d failed, %d skipped\n' \
    "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
  exit 1
fi

# ---------------------------------------------------------------------------
# Run the unittest module.
# ---------------------------------------------------------------------------
echo "=== Phase 3: run-plan claim-file collector (collect.py._read_plan_claims) ==="

TMP_RAW=$(mktemp)
PYTHONPATH="$PKG_PARENT" "$PYTHON" "$PY_TEST" -v > "$TMP_RAW" 2>&1
PY_RC=$?

# unittest verbose emits `... ok` / `... FAIL` / `... ERROR` per test.
while IFS= read -r line; do
  case "$line" in
    *" ... ok")
      name="${line% ... ok}"
      pass "$name"
      ;;
    *" ... FAIL"|*" ... ERROR")
      name="${line% ... *}"
      fail "$name"
      ;;
    *" ... skipped"*)
      name="${line% ... skipped*}"
      skip "$name"
      ;;
  esac
done < "$TMP_RAW"

if [ "$FAIL_COUNT" -gt 0 ] || [ "$PY_RC" -ne 0 ]; then
  echo ""
  echo "--- unittest output ---"
  cat "$TMP_RAW"
  echo "--- end unittest output ---"
fi
rm -f "$TMP_RAW"

if [ "$PY_RC" -ne 0 ] && [ "$FAIL_COUNT" -eq 0 ]; then
  fail "unittest runner exited rc=$PY_RC with no per-test failures parsed (import/collection error?)"
fi

# ---------------------------------------------------------------------------
# AC: registered in tests/run-all.sh
# ---------------------------------------------------------------------------
if grep -q "test-plan-claim-collector.sh" "$REPO_ROOT/tests/run-all.sh"; then
  pass "tests/run-all.sh references test-plan-claim-collector.sh"
else
  fail "tests/run-all.sh missing test-plan-claim-collector.sh registration"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "---"
TOTAL=$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '\033[32mResults: %d passed, %d failed, %d skipped (of %d)\033[0m\n' \
    "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed, %d skipped (of %d)\033[0m\n' \
    "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$TOTAL"
  exit 1
fi
