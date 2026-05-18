#!/bin/bash
# tests/test-migrate-paths-awk.sh — direct unit-tests for the 3-tuple
# write_output_block() function inside migrate-paths.sh, in isolation
# from the migrator's outer bash scaffolding.
#
# Per REPORTS_DIR_MIGRATION.md WI 1.7-bis: the 3-tuple awk extension
# (which-keys-already-present × which-key-is-last × indent variance) is
# the highest-risk change in Phase 1. Each fixture-case validates one
# comma-state edge condition directly.
#
# Driver strategy: rather than fragile line-range extraction, we extract
# the named function write_output_block() from migrate-paths.sh by
# locating its `write_output_block() {` opener and matching closing `}`,
# then source it into a subshell that points $CFG at the fixture file.
# Output is validated as parseable JSON via python3 and compared to the
# canonicalized expected.json.
#
# Cases live as triplets under tests/fixtures/migrate-paths-awk/<case>/:
#   input.json       — config bytes the migrator was about to mutate
#   env              — sourced file defining plans, issues, reports vars
#   expected.json    — canonical JSON the migrator should produce
#
# Pass-gate (AC-1.14): exit 0; PASS == fixture-directory count (9 at draft).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/migrate-paths-awk"
MIGRATE_SCRIPT="$REPO_ROOT/skills/update-zskills/scripts/migrate-paths.sh"
TEST_OUT="/tmp/zskills-tests/$(basename "$REPO_ROOT")"
mkdir -p "$TEST_OUT"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

if [ ! -d "$FIXTURE_DIR" ]; then
  fail "fixture dir exists" "$FIXTURE_DIR missing"
  echo "Results: 0 passed, 1 failed (of 1)"
  exit 1
fi

# Extract write_output_block() function body from migrate-paths.sh into a
# standalone runnable. We rely on the function name being stable and the
# matching `}` being at column 0 (which it is — function closers in this
# file are unindented).
EXTRACTED_FN="$TEST_OUT/write-output-block-extracted.sh"
awk '
  /^write_output_block\(\) \{/ { capture = 1 }
  capture { print }
  capture && /^\}$/ { capture = 0 }
' "$MIGRATE_SCRIPT" > "$EXTRACTED_FN"

if ! grep -q '^write_output_block()' "$EXTRACTED_FN"; then
  fail "function extraction" "could not extract write_output_block from $MIGRATE_SCRIPT"
  echo "Results: 0 passed, 1 failed (of 1)"
  exit 1
fi

# Run a fixture case: source the extracted function with $CFG pointed at a
# fresh copy of input.json, call write_output_block "$plans" "$issues"
# "$reports", and capture the mutated config.
run_case() {
  local case_dir="$1"
  local case_name
  case_name=$(basename "$case_dir")

  if [ ! -f "$case_dir/input.json" ] || [ ! -f "$case_dir/env" ] || [ ! -f "$case_dir/expected.json" ]; then
    fail "$case_name: triplet present" "missing input.json/env/expected.json"
    return
  fi

  local work
  work=$(mktemp -d "$TEST_OUT/case-${case_name}-XXXX")
  cp "$case_dir/input.json" "$work/cfg.json"

  # Source env (sets plans, issues, reports).
  local plans="" issues="" reports=""
  # shellcheck source=/dev/null
  . "$case_dir/env"

  # Invoke extracted function in a subshell with CFG bound to work copy.
  local actual_out actual_rc
  actual_out=$(
    set +u
    CFG="$work/cfg.json"
    # Source the function definition.
    # shellcheck source=/dev/null
    . "$EXTRACTED_FN"
    write_output_block "$plans" "$issues" "$reports"
  )
  actual_rc=$?
  if [ "$actual_rc" -ne 0 ]; then
    fail "$case_name: write_output_block rc" "rc=$actual_rc out=$actual_out"
    rm -rf -- "$work"
    return
  fi

  # Validate JSON.
  if ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$work/cfg.json" 2>/dev/null; then
    fail "$case_name: output is valid JSON" "$(cat "$work/cfg.json")"
    rm -rf -- "$work"
    return
  fi

  # Canonicalize and compare.
  local actual_norm expected_norm
  actual_norm=$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])),sort_keys=False,indent=2))' "$work/cfg.json")
  expected_norm=$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])),sort_keys=False,indent=2))' "$case_dir/expected.json")

  if [ "$actual_norm" = "$expected_norm" ]; then
    pass "$case_name: canonical JSON matches expected"
  else
    fail "$case_name: canonical JSON mismatch" "diff:$(diff <(echo "$actual_norm") <(echo "$expected_norm") | head -40)"
  fi
  rm -rf -- "$work"
}

# Iterate every fixture directory.
for case_dir in "$FIXTURE_DIR"/*/; do
  [ -d "$case_dir" ] || continue
  run_case "$case_dir"
done

echo
echo "---"
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (of %d)\033[0m\n' "$PASS_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (of %d)\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit 1
fi
