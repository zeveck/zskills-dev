#!/bin/bash
# Tests for backfill-plan-completed.sh
#
# Covers:
#   T672.1  Script does not fail with "unbound variable" when
#           CLAUDE_PROJECT_DIR is unset (the bug fixed in #672).
#
# Run from repo root: bash tests/test-backfill-plan-completed.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BACKFILL_SCRIPT="skills/zskills-dashboard/scripts/backfill-plan-completed.sh"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
skip() { printf '\033[33m  SKIP\033[0m %s\n' "$1"; SKIP_COUNT=$((SKIP_COUNT + 1)); }

print_summary_and_exit() {
  echo ""
  echo "---"
  local total=$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))
  if [ "$FAIL_COUNT" -eq 0 ]; then
    printf '\033[32mResults: %d passed, %d failed, %d skipped (of %d)\033[0m\n' \
      "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$total"
    exit 0
  else
    printf '\033[31mResults: %d passed, %d failed, %d skipped (of %d)\033[0m\n' \
      "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$total"
    exit 1
  fi
}

if [ ! -f "$REPO_ROOT/$BACKFILL_SCRIPT" ]; then
  fail "backfill script exists at expected path"
  print_summary_and_exit
fi

# ── T672.1 — no "unbound variable" crash when CLAUDE_PROJECT_DIR unset ──

# Run the script in a subshell with CLAUDE_PROJECT_DIR explicitly unset.
# The script should NOT crash with "unbound variable". It should either
# succeed (exit 0) or fail gracefully for other reasons (e.g., no plans
# to backfill), but never with exit code 1 and the specific "unbound
# variable" error message on stderr.
output="$(cd "$REPO_ROOT" && env -u CLAUDE_PROJECT_DIR bash "$BACKFILL_SCRIPT" 2>&1)" || true
rc=$?

if echo "$output" | grep -q "unbound variable"; then
  fail "T672.1 — script crashes with 'unbound variable' when CLAUDE_PROJECT_DIR is unset"
  echo "    stderr/stdout contained: $(echo "$output" | grep 'unbound variable')"
else
  pass "T672.1 — no 'unbound variable' error when CLAUDE_PROJECT_DIR is unset (exit $rc)"
fi

print_summary_and_exit
