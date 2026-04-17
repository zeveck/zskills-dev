#!/bin/bash
# Run all test suites and report results.
# Run from repo root: bash tests/run-all.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TOTAL_PASS=0
TOTAL_FAIL=0
OVERALL_EXIT=0

run_suite() {
  local name="$1"
  local script="$2"

  echo ""
  printf '\033[1mTests: %s\033[0m\n' "$name"

  output=$(bash "$REPO_ROOT/$script" 2>&1)
  local exit_code=$?

  echo "$output"

  # Extract counts from the "Results: X passed, Y failed" line
  local passed failed
  passed=$(echo "$output" | grep -oP '\d+(?= passed)' | tail -1)
  failed=$(echo "$output" | grep -oP '\d+(?= failed)' | tail -1)

  TOTAL_PASS=$((TOTAL_PASS + ${passed:-0}))
  TOTAL_FAIL=$((TOTAL_FAIL + ${failed:-0}))

  if [[ $exit_code -ne 0 ]]; then
    OVERALL_EXIT=1
  fi
}

run_suite "test-hooks.sh" "tests/test-hooks.sh"
run_suite "test-port.sh" "tests/test-port.sh"
run_suite "test-briefing-parity.sh" "tests/test-briefing-parity.sh"
run_suite "test-skill-invariants.sh" "tests/test-skill-invariants.sh"
run_suite "test-phase-5b-gate.sh" "tests/test-phase-5b-gate.sh"
run_suite "test-scope-halt.sh" "tests/test-scope-halt.sh"
run_suite "test-canary-failures.sh" "tests/test-canary-failures.sh"

echo ""
echo "=============================="
TOTAL=$((TOTAL_PASS + TOTAL_FAIL))
if [[ "$TOTAL_FAIL" -eq 0 ]]; then
  printf '\033[32mOverall: %d/%d passed, 0 failed\033[0m\n' "$TOTAL_PASS" "$TOTAL"
else
  printf '\033[31mOverall: %d/%d passed, %d failed\033[0m\n' "$TOTAL_PASS" "$TOTAL" "$TOTAL_FAIL"
fi

exit $OVERALL_EXIT
