#!/bin/bash
# Tests for skills/briefing/scripts/briefing.py
# Run from repo root: bash tests/test-briefing-parity.sh
#
# Historical note: this file previously asserted runtime parity between
# briefing.cjs and briefing.py. The cjs fork was retired in #289 (Python
# became the single runtime; see CLAUDE.md "Python is required"). The
# filename is retained for git-history continuity; the contents are now
# pure smoke tests against briefing.py.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export CLAUDE_PROJECT_DIR="$REPO_ROOT"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

pass() {
  printf '\033[32m  PASS\033[0m %s\n' "$1"
  ((PASS_COUNT++))
}

fail() {
  printf '\033[31m  FAIL\033[0m %s\n' "$1"
  ((FAIL_COUNT++))
}

skip() {
  printf '\033[33m  SKIP\033[0m %s\n' "$1"
  ((SKIP_COUNT++))
}

HAS_PYTHON=false
command -v python3 >/dev/null 2>&1 && HAS_PYTHON=true

echo "=== briefing.py smoke tests ==="

if [[ "$HAS_PYTHON" == "false" ]]; then
  echo "python3 not available — skipping all tests"
  skip "python3 not available"
  echo ""
  echo "---"
  printf 'Results: %d passed, %d failed, %d skipped (of %d)\n' \
    "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))"
  exit 0
fi

# Use a temp directory for report output to avoid polluting the repo
TEST_TMPDIR=$(mktemp -d)
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# Smoke test all subcommands with python3
# Note: "report" writes files, so redirect its output to the temp dir
smoke_cmds=(
  "summary"
  "report --since=24h --output=$TEST_TMPDIR/briefing-test.md"
  "verify"
  "current"
  "worktrees"
  "commits --since=24h"
  "checkboxes"
)

for cmd in "${smoke_cmds[@]}"; do
  # shellcheck disable=SC2086
  output=$(cd "$REPO_ROOT" && python3 "$REPO_ROOT/skills/briefing/scripts/briefing.py" $cmd 2>&1)
  exit_code=$?
  if [[ $exit_code -eq 0 && -n "$output" ]]; then
    pass "python3 briefing.py $cmd"
  elif [[ $exit_code -eq 0 && -z "$output" ]]; then
    # Some subcommands may produce empty output legitimately (e.g. no checkboxes)
    pass "python3 briefing.py $cmd (empty but exit 0)"
  else
    fail "python3 briefing.py $cmd (exit=$exit_code)"
  fi
done

echo ""
echo "---"
printf 'Results: %d passed, %d failed, %d skipped (of %d)\n' \
  "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
