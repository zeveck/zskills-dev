#!/bin/bash
# test-plan-claim-selection-filter.sh — AC2b.1: the user-steering gate.
#
# Synthesise `.zskills/claims/plan-foo/claim.json` via `claim-plan.sh
# acquire` (preferred — exercises the real schema per DA2.12), feed
# READY_LINES=[foo, bar] through filter-in-flight-plan-claims.sh, assert:
#   (a) `foo` is filtered out of stdout
#   (b) `bar` is preserved in stdout
#   (c) stderr contains "Skipped 1 plan(s) currently in-flight: foo"

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FILTER="$REPO_ROOT/skills/work-on-plans/scripts/filter-in-flight-plan-claims.sh"
CLAIM_SH="$REPO_ROOT/skills/run-plan/scripts/claim-plan.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SCRATCH="/tmp/test-plan-claim-selection-filter-$$"
cleanup() {
  if [ -n "${TEST_KEEP_SCRATCH:-}" ]; then return; fi
  [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
}
trap cleanup EXIT INT TERM
mkdir -p "$SCRATCH"

echo "=== plan-claim selection filter (AC2b.1) ==="

# Sanity: filter script + claim-plan.sh exist and are executable.
if [ ! -x "$FILTER" ]; then
  fail "filter script executable" "$FILTER not found or not executable"
  echo "Results: $PASS_COUNT passed, $((FAIL_COUNT + 1)) failed"
  exit 1
fi
if [ ! -x "$CLAIM_SH" ]; then
  fail "claim-plan.sh executable" "$CLAIM_SH not found or not executable"
  echo "Results: $PASS_COUNT passed, $((FAIL_COUNT + 1)) failed"
  exit 1
fi
pass "filter + claim-plan.sh present and executable"

# Build a real git fixture so MAIN_ROOT resolves predictably.
FIXTURE="$SCRATCH/fixture"
mkdir -p "$FIXTURE"
(
  cd "$FIXTURE"
  git init -q
  git config user.email "t@t"
  git config user.name "t"
  git commit --allow-empty -q -m "init"
) || { fail "fixture init" "git init failed"; echo "Results: $PASS_COUNT passed, $((FAIL_COUNT + 1)) failed"; exit 1; }

# Acquire a real claim for slug "foo".
(
  cd "$FIXTURE"
  bash "$CLAIM_SH" acquire foo --pipeline-id "run-plan.foo.test"
) >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then
  fail "acquire claim for foo" "exit $rc"
  echo "Results: $PASS_COUNT passed, $((FAIL_COUNT + 1)) failed"
  exit 1
fi
pass "acquired claim plan-foo via claim-plan.sh acquire"

# Verify claim.json exists.
if [ ! -f "$FIXTURE/.zskills/claims/plan-foo/claim.json" ]; then
  fail "claim.json on disk" "missing $FIXTURE/.zskills/claims/plan-foo/claim.json"
else
  pass "claim.json present on disk"
fi

# Run the filter from inside the fixture (MAIN_ROOT will resolve to $FIXTURE).
INPUT=$'foo\nbar'
STDOUT_FILE="$SCRATCH/stdout.txt"
STDERR_FILE="$SCRATCH/stderr.txt"
(
  cd "$FIXTURE"
  printf '%s' "$INPUT" | bash "$FILTER"
) >"$STDOUT_FILE" 2>"$STDERR_FILE"
rc=$?

if [ "$rc" -eq 0 ]; then
  pass "filter exits 0"
else
  fail "filter exits 0" "got rc=$rc"
fi

# Assertion (a): foo is filtered.
if ! grep -qE '^foo$' "$STDOUT_FILE"; then
  pass "foo is filtered out of stdout"
else
  fail "foo is filtered out of stdout" "found foo in stdout: $(cat "$STDOUT_FILE")"
fi

# Assertion (b): bar is preserved.
if grep -qE '^bar$' "$STDOUT_FILE"; then
  pass "bar is preserved in stdout"
else
  fail "bar is preserved in stdout" "stdout was: $(cat "$STDOUT_FILE")"
fi

# Assertion (c): stderr Skipped-N line.
if grep -qE 'Skipped 1 plan\(s\) currently in-flight: foo' "$STDERR_FILE"; then
  pass "stderr contains 'Skipped 1 plan(s) currently in-flight: foo'"
else
  fail "stderr Skipped-N line" "stderr was: $(cat "$STDERR_FILE")"
fi

# TSV-input variant: input lines with multiple TSV columns must filter
# by the FIRST column (slug), preserving the full TSV row downstream.
INPUT_TSV=$'foo\tphase\tmode-a\nbar\tphase\tmode-b'
STDOUT_FILE2="$SCRATCH/stdout-tsv.txt"
(
  cd "$FIXTURE"
  printf '%s' "$INPUT_TSV" | bash "$FILTER"
) >"$STDOUT_FILE2" 2>/dev/null
# Use printf to build the literal bar TSV row (grep -F means fixed string).
BAR_ROW=$(printf 'bar\tphase\tmode-b')
if ! grep -qE '^foo' "$STDOUT_FILE2" && grep -qF -- "$BAR_ROW" "$STDOUT_FILE2"; then
  pass "TSV input: foo row filtered, bar row preserved with all columns"
else
  fail "TSV input filtering" "stdout was: $(cat "$STDOUT_FILE2")"
fi

echo ""
echo "---"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
[ "$FAIL_COUNT" -eq 0 ]
