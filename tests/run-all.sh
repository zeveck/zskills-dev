#!/bin/bash
# Run all test suites and report results.
# Run from repo root: bash tests/run-all.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export CLAUDE_PROJECT_DIR="$REPO_ROOT"

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
run_suite "test-apply-preset.sh" "tests/test-apply-preset.sh"
run_suite "test-compute-cron-fire.sh" "tests/test-compute-cron-fire.sh"
run_suite "test-create-worktree.sh" "tests/test-create-worktree.sh"
run_suite "test-skill-conformance.sh" "tests/test-skill-conformance.sh"
run_suite "test-draft-tests.sh" "tests/test-draft-tests.sh"
run_suite "test-draft-tests-phase2.sh" "tests/test-draft-tests-phase2.sh"
run_suite "test-draft-tests-phase3.sh" "tests/test-draft-tests-phase3.sh"
run_suite "test-draft-tests-phase4.sh" "tests/test-draft-tests-phase4.sh"
run_suite "test-draft-tests-phase5.sh" "tests/test-draft-tests-phase5.sh"
run_suite "test-briefing-parity.sh" "tests/test-briefing-parity.sh"
run_suite "test-skill-invariants.sh" "tests/test-skill-invariants.sh"
run_suite "test-phase-5b-gate.sh" "tests/test-phase-5b-gate.sh"
run_suite "test-runplan-defer-backoff.sh" "tests/test-runplan-defer-backoff.sh"
run_suite "test-scope-halt.sh" "tests/test-scope-halt.sh"
run_suite "test-canary-failures.sh" "tests/test-canary-failures.sh"
run_suite "test-tracking-integration.sh" "tests/test-tracking-integration.sh"
run_suite "test-quickfix.sh" "tests/test-quickfix.sh"
run_suite "test-update-zskills-migration.sh" "tests/test-update-zskills-migration.sh"
run_suite "test-update-zskills-rerender.sh" "tests/test-update-zskills-rerender.sh"
run_suite "test-mirror-skill.sh" "tests/test-mirror-skill.sh"
run_suite "test-zskills-resolve-config.sh" "tests/test-zskills-resolve-config.sh"
run_suite "test-skill-file-drift.sh" "tests/test-skill-file-drift.sh"
run_suite "test-plan-drift-correct.sh" "tests/test-plan-drift-correct.sh"
run_suite "test-work-on-plans.sh" "tests/test-work-on-plans.sh"
run_suite "test_zskills_monitor_collect.sh" "tests/test_zskills_monitor_collect.sh"
run_suite "test_zskills_monitor_server.sh" "tests/test_zskills_monitor_server.sh"
run_suite "test-stub-callouts.sh" "tests/test-stub-callouts.sh"
run_suite "test-post-create-worktree.sh" "tests/test-post-create-worktree.sh"
run_suite "test_zskills_monitor_dashboard_ui.sh" "tests/test_zskills_monitor_dashboard_ui.sh"
run_suite "test_zskills_dashboard_skill.sh" "tests/test_zskills_dashboard_skill.sh"
run_suite "test_plans_rebuild_uses_collect.sh" "tests/test_plans_rebuild_uses_collect.sh"

# Opt-in end-to-end smoke for parallel pipelines. Heavier than unit tests
# (real git repos, concurrent writes), so it runs only when RUN_E2E is set.
if [ -n "${RUN_E2E:-}" ]; then
  run_suite "e2e-parallel-pipelines.sh" "tests/e2e-parallel-pipelines.sh"
fi

echo ""
echo "=============================="
TOTAL=$((TOTAL_PASS + TOTAL_FAIL))
if [[ "$TOTAL_FAIL" -eq 0 ]]; then
  printf '\033[32mOverall: %d/%d passed, 0 failed\033[0m\n' "$TOTAL_PASS" "$TOTAL"
else
  printf '\033[31mOverall: %d/%d passed, %d failed\033[0m\n' "$TOTAL_PASS" "$TOTAL" "$TOTAL_FAIL"
fi

exit $OVERALL_EXIT
