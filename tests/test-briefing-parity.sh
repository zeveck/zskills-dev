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

# ---------------------------------------------------------------------
# Port-failure regression guard (restored from pre-#312 test history;
# see issue #338). Original section was trimmed in 1690c93 alongside the
# cjs retirement, but the Python invariant remains worth asserting.
#
# Invariant: when port.sh is NOT installed at
# .claude/skills/update-zskills/scripts/port.sh, briefing.py must
# (a) exit 0 and (b) emit zero `localhost:` URLs. The pre-Phase-4
# fallback (`port = '8080'`) would emit `localhost:8080/...`
# unconditionally; this guards against that regression returning.
# ---------------------------------------------------------------------
echo ""
echo "=== Port-failure regression guard (no port.sh installed) ==="

FIXTURE_DIR="/tmp/zskills-briefing-fixture-noport-$$"
rm -rf "$FIXTURE_DIR"
mkdir -p "$FIXTURE_DIR/skills/briefing/scripts"
# .git marker so find_repo_root anchors at FIXTURE_DIR (and therefore
# the absent .claude/skills/update-zskills/scripts/port.sh is what gets
# resolved — NOT the real one from the surrounding repo).
mkdir -p "$FIXTURE_DIR/.git"
# Copy briefing.py into the fixture so __file__ / _SCRIPT_DIR resolve
# to fixture paths. (find_repo_root walks up from the script's
# directory, not cwd.) NO port.sh is installed in the fixture's
# .claude/skills/update-zskills/scripts/ tree — that absence is the
# whole point of the test.
cp "$REPO_ROOT/skills/briefing/scripts/briefing.py" \
   "$FIXTURE_DIR/skills/briefing/scripts/briefing.py"

# Ensure cleanup even on early exit / failures below.
trap 'rm -rf "$TEST_TMPDIR" "$FIXTURE_DIR"' EXIT

noport_py_out="$FIXTURE_DIR/.py-summary.txt"
py_exit=0
(cd "$FIXTURE_DIR" && python3 \
  "$FIXTURE_DIR/skills/briefing/scripts/briefing.py" summary --since=24h) \
  >"$noport_py_out" 2>"$FIXTURE_DIR/.py-err.txt" || py_exit=$?

# AC 1: briefing.py exits 0 with missing port.sh.
if [[ "$py_exit" -eq 0 ]]; then
  pass "port-failure: briefing.py exits 0 on missing port.sh"
else
  fail "port-failure: briefing.py exit=$py_exit on missing port.sh"
fi

# AC 2: no localhost: URL in stdout.
# `grep -c` returns exit 1 when there are zero matches; the count is
# still printed (as "0"), but we tolerate the empty-output case too.
py_localhost=$(grep -c 'localhost:' "$noport_py_out" 2>/dev/null)
[[ -z "$py_localhost" ]] && py_localhost=0
if [[ "$py_localhost" -eq 0 ]]; then
  pass "port-failure: briefing.py emits no localhost: URL"
else
  fail "port-failure: briefing.py emitted $py_localhost localhost: URL(s)"
fi

echo ""
echo "---"
printf 'Results: %d passed, %d failed, %d skipped (of %d)\n' \
  "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
