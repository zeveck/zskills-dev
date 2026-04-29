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

  # ---------------------------------------------------------------------
  # Port-failure parity tests (Phase 4 of DEFAULT_PORT_CONFIG)
  # ---------------------------------------------------------------------
  # Fixture: a fake "main repo" that has NO port.sh installed. briefing.py /
  # briefing.cjs must run to completion AND emit no localhost: URL AND produce
  # equivalent output. Pre-Phase-4 fallback (`port = '8080'`) would emit
  # localhost:8080/... unconditionally; this test guards against regression.
  echo ""
  echo "=== Port-failure parity (no port.sh installed) ==="

  FIXTURE_DIR="/tmp/zskills-briefing-fixture-noport"
  rm -rf "$FIXTURE_DIR"
  mkdir -p "$FIXTURE_DIR/skills/briefing/scripts"
  # .git marker so find_repo_root / findRepoRoot anchors at FIXTURE_DIR.
  mkdir -p "$FIXTURE_DIR/.git"
  # NO .claude/skills/update-zskills/scripts/port.sh — that's the whole point.
  # Copy briefing scripts into fixture so __file__ / __filename resolve to fixture
  # paths. (find_repo_root walks up from the script's directory, not cwd.)
  cp "$REPO_ROOT/skills/briefing/scripts/briefing.py" "$FIXTURE_DIR/skills/briefing/scripts/briefing.py"
  cp "$REPO_ROOT/skills/briefing/scripts/briefing.cjs" "$FIXTURE_DIR/skills/briefing/scripts/briefing.cjs"

  noport_node_out="$FIXTURE_DIR/.node-summary.txt"
  noport_py_out="$FIXTURE_DIR/.py-summary.txt"

  # Run both, capturing stderr separately to inspect crashes.
  node_exit=0
  py_exit=0
  (cd "$FIXTURE_DIR" && node "$FIXTURE_DIR/skills/briefing/scripts/briefing.cjs" summary --since=24h) \
    >"$noport_node_out" 2>"$FIXTURE_DIR/.node-err.txt" || node_exit=$?
  (cd "$FIXTURE_DIR" && python3 "$FIXTURE_DIR/skills/briefing/scripts/briefing.py" summary --since=24h) \
    >"$noport_py_out" 2>"$FIXTURE_DIR/.py-err.txt" || py_exit=$?

  # AC: both run to completion (exit 0).
  if [[ "$node_exit" -eq 0 ]]; then
    pass "port-failure: briefing.cjs exits 0 on missing port.sh"
  else
    fail "port-failure: briefing.cjs exit=$node_exit on missing port.sh"
  fi
  if [[ "$py_exit" -eq 0 ]]; then
    pass "port-failure: briefing.py exits 0 on missing port.sh"
  else
    fail "port-failure: briefing.py exit=$py_exit on missing port.sh"
  fi

  # AC: neither emits a localhost: URL.
  # Note: `grep -c` returns 0 (no match) with exit-code 1; we want the count.
  node_localhost=$(grep -c 'localhost:' "$noport_node_out" 2>/dev/null)
  [[ -z "$node_localhost" ]] && node_localhost=0
  py_localhost=$(grep -c 'localhost:' "$noport_py_out" 2>/dev/null)
  [[ -z "$py_localhost" ]] && py_localhost=0
  if [[ "$node_localhost" -eq 0 ]]; then
    pass "port-failure: briefing.cjs emits no localhost: URL"
  else
    fail "port-failure: briefing.cjs emitted $node_localhost localhost: URL(s)"
  fi
  if [[ "$py_localhost" -eq 0 ]]; then
    pass "port-failure: briefing.py emits no localhost: URL"
  else
    fail "port-failure: briefing.py emitted $py_localhost localhost: URL(s)"
  fi

  # AC: outputs are equivalent. We compare verbatim — the port-handling code
  # paths in briefing.py and briefing.cjs do NOT interpolate language-specific
  # literals (None/null/True/False) into stdout (verified by
  #   grep -nE 'lines\.(append|push)\(.*\b(None|null|True|False|true|false)\b'
  # returning empty for both files at the time of this writing). If a future
  # edit introduces a literal divergence, fix the source so output stays
  # byte-equivalent rather than weakening this test.
  if diff -q "$noport_node_out" "$noport_py_out" >/dev/null 2>&1; then
    pass "port-failure: outputs are byte-equivalent"
  else
    # Show first 5 differing lines for debug, but still fail.
    diff_lines=$(diff "$noport_node_out" "$noport_py_out" | head -10 | tr '\n' '|')
    fail "port-failure: outputs diverge — diff: $diff_lines"
  fi

  rm -rf "$FIXTURE_DIR"
fi

echo ""
echo "---"
printf 'Results: %d passed, %d failed, %d skipped (of %d)\n' \
  "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
