#!/bin/bash
# Tests for skills/briefing/scripts/briefing.py (and parity with briefing.cjs)
# Run from repo root: bash tests/test-briefing-parity.sh

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

HAS_NODE=false
HAS_PYTHON=false
command -v node >/dev/null 2>&1 && HAS_NODE=true
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
echo "=== Parity tests (node vs python3) ==="

if [[ "$HAS_NODE" == "false" ]]; then
  skip "parity tests (node not available)"
else
  # JSON subcommands: compare structure
  json_cmds=("commits --since=24h" "worktrees" "checkboxes")
  for cmd in "${json_cmds[@]}"; do
    # shellcheck disable=SC2086
    node_out=$(cd "$REPO_ROOT" && node "$REPO_ROOT/skills/briefing/scripts/briefing.cjs" $cmd 2>/dev/null)
    # shellcheck disable=SC2086
    py_out=$(cd "$REPO_ROOT" && python3 "$REPO_ROOT/skills/briefing/scripts/briefing.py" $cmd 2>/dev/null)

    # Both should produce valid JSON — compare top-level keys
    node_keys=$(echo "$node_out" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    if isinstance(d, dict):
        print(' '.join(sorted(d.keys())))
    elif isinstance(d, list):
        print('list:' + str(len(d)))
    else:
        print(type(d).__name__)
except:
    print('PARSE_ERROR')
" 2>/dev/null)

    py_keys=$(echo "$py_out" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    if isinstance(d, dict):
        print(' '.join(sorted(d.keys())))
    elif isinstance(d, list):
        print('list:' + str(len(d)))
    else:
        print(type(d).__name__)
except:
    print('PARSE_ERROR')
" 2>/dev/null)

    if [[ "$node_keys" == "PARSE_ERROR" && "$py_keys" == "PARSE_ERROR" ]]; then
      # Both failed to parse — might be empty results, still parity
      pass "parity: $cmd (both returned non-JSON, consistent)"
    elif [[ "$node_keys" == "$py_keys" ]]; then
      pass "parity: $cmd (keys match: $node_keys)"
    else
      fail "parity: $cmd — node keys=[$node_keys] vs py keys=[$py_keys]"
    fi
  done

  # Text subcommand: summary — compare line count
  node_summary=$(cd "$REPO_ROOT" && node "$REPO_ROOT/skills/briefing/scripts/briefing.cjs" summary --since=24h 2>/dev/null)
  py_summary=$(cd "$REPO_ROOT" && python3 "$REPO_ROOT/skills/briefing/scripts/briefing.py" summary --since=24h 2>/dev/null)

  node_lines=$(echo "$node_summary" | wc -l)
  py_lines=$(echo "$py_summary" | wc -l)

  # Allow line counts to differ by up to 30% or 5 lines
  diff=$((node_lines - py_lines))
  diff=${diff#-}  # absolute value
  if [[ "$diff" -le 5 || "$diff" -le $((node_lines * 30 / 100)) ]]; then
    pass "parity: summary (line counts close: node=$node_lines, py=$py_lines)"
  else
    fail "parity: summary (line counts diverge: node=$node_lines, py=$py_lines)"
  fi
fi

echo ""
echo "---"
printf 'Results: %d passed, %d failed, %d skipped (of %d)\n' \
  "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
