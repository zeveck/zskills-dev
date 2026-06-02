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

  # Extract counts from the canonical "Results: <N> passed, <N> failed"
  # line. Anchor to that exact line shape so any inner-test diagnostics
  # (e.g., test-hooks.sh's fixture-extension synthetic-fixture run that
  # nests a `tests/test-skill-conformance.sh` invocation — see #587) can't
  # leak a count into the outer parser. Strip ANSI color codes first
  # (some suites colorize Results in red/green). If no canonical line is
  # found in the output, fall through with 0/0 — the suite's own exit
  # code still flips OVERALL_EXIT below, so an unparseable suite is not
  # silently dropped.
  local passed failed results_line stripped
  stripped=$(echo "$output" | sed -E $'s/\x1b\\[[0-9;]*m//g')
  results_line=$(echo "$stripped" | grep -E '^Results: [0-9]+ passed,( [0-9]+ failed|.* [0-9]+ failed)' | tail -1)
  if [[ -n "$results_line" ]]; then
    passed=$(echo "$results_line" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+')
    failed=$(echo "$results_line" | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+')
  else
    passed=0
    failed=0
  fi

  TOTAL_PASS=$((TOTAL_PASS + ${passed:-0}))
  TOTAL_FAIL=$((TOTAL_FAIL + ${failed:-0}))

  if [[ $exit_code -ne 0 ]]; then
    OVERALL_EXIT=1
  fi
}

run_suite "test-hooks.sh" "tests/test-hooks.sh"
run_suite "test-tokenize-then-walk.sh" "tests/test-tokenize-then-walk.sh"
run_suite "test-hook-helper-drift.sh" "tests/test-hook-helper-drift.sh"
run_suite "test-resolve-effective-worktree-root.sh" "tests/test-resolve-effective-worktree-root.sh"
run_suite "test-hooks-mirror-parity.sh" "tests/test-hooks-mirror-parity.sh"
run_suite "test-skills-mirror-parity.sh" "tests/test-skills-mirror-parity.sh"
run_suite "test-inject-bash-timeout.sh" "tests/test-inject-bash-timeout.sh"
run_suite "test-verify-response-validate.sh" "tests/test-verify-response-validate.sh"
run_suite "canary-verifier-agent-discovery-part1.sh" "tests/canary-verifier-agent-discovery-part1.sh"
run_suite "canary-verifier-timeout-injection.sh" "tests/canary-verifier-timeout-injection.sh"
run_suite "canary-verify-response-validate.sh" "tests/canary-verify-response-validate.sh"
run_suite "canary-ensure-worktree.sh" "tests/canary-ensure-worktree.sh"
run_suite "test-port.sh" "tests/test-port.sh"
run_suite "test-apply-preset.sh" "tests/test-apply-preset.sh"
run_suite "test-compute-cron-fire.sh" "tests/test-compute-cron-fire.sh"
run_suite "test-create-worktree.sh" "tests/test-create-worktree.sh"
run_suite "test-skill-content-hash.sh" "tests/test-skill-content-hash.sh"
run_suite "test-skill-description-budget.sh" "tests/test-skill-description-budget.sh"
run_suite "test-skill-version-compare.sh" "tests/test-skill-version-compare.sh"
run_suite "test-skill-conformance.sh" "tests/test-skill-conformance.sh"
run_suite "test-no-conflict-markers.sh" "tests/test-no-conflict-markers.sh"
run_suite "test-skill-version-enforcement.sh" "tests/test-skill-version-enforcement.sh"
run_suite "test-skill-version-canary-missed-bump.sh" "tests/test-skill-version-canary-missed-bump.sh"
run_suite "test-skill-version-canary-correct-bump.sh" "tests/test-skill-version-canary-correct-bump.sh"
run_suite "test-skill-version-canary-parallel-merge.sh" "tests/test-skill-version-canary-parallel-merge.sh"
run_suite "test-skill-version-canary-revert.sh" "tests/test-skill-version-canary-revert.sh"
run_suite "test-draft-tests.sh" "tests/test-draft-tests.sh"
run_suite "test-draft-tests-phase2.sh" "tests/test-draft-tests-phase2.sh"
run_suite "test-draft-tests-phase3.sh" "tests/test-draft-tests-phase3.sh"
run_suite "test-draft-tests-phase4.sh" "tests/test-draft-tests-phase4.sh"
run_suite "test-draft-tests-phase5.sh" "tests/test-draft-tests-phase5.sh"
run_suite "test-briefing-parity.sh" "tests/test-briefing-parity.sh"
run_suite "test-briefing-worktrees-merged-diverged.sh" "tests/test-briefing-worktrees-merged-diverged.sh"
run_suite "test-briefing-dogfooding.sh" "tests/test-briefing-dogfooding.sh"
run_suite "test-briefing-units.sh" "tests/test-briefing-units.sh"
run_suite "test-skill-invariants.sh" "tests/test-skill-invariants.sh"
run_suite "test-issue-380-committed-state-checks.sh" "tests/test-issue-380-committed-state-checks.sh"
run_suite "test-phase-5b-gate.sh" "tests/test-phase-5b-gate.sh"
run_suite "test-run-plan-sync-pr-body-progress.sh" "tests/test-run-plan-sync-pr-body-progress.sh"
run_suite "test-runplan-defer-backoff.sh" "tests/test-runplan-defer-backoff.sh"
run_suite "test-scope-halt.sh" "tests/test-scope-halt.sh"
run_suite "test-canary-failures.sh" "tests/test-canary-failures.sh"
run_suite "test-block-bad-cron.sh" "tests/test-block-bad-cron.sh"
run_suite "test-block-stale-skill-version.sh" "tests/test-block-stale-skill-version.sh"
run_suite "test-block-stale-skill-version-sandbox.sh" "tests/test-block-stale-skill-version-sandbox.sh"
run_suite "test-block-bypassed-land-pr.sh" "tests/test-block-bypassed-land-pr.sh"
run_suite "test-block-main-edits.sh" "tests/test-block-main-edits.sh"
run_suite "test-tracking-integration.sh" "tests/test-tracking-integration.sh"
run_suite "test-quickfix.sh" "tests/test-quickfix.sh"
run_suite "test-fix-issues.sh" "tests/test-fix-issues.sh"
run_suite "test-fix-issues-dashboard.sh" "tests/test-fix-issues-dashboard.sh"
run_suite "test-fix-issues-bootstrap.sh" "tests/test-fix-issues-bootstrap.sh"
run_suite "test-fix-issues-worktree-cap.sh" "tests/test-fix-issues-worktree-cap.sh"
run_suite "test-fix-issues-sprint-worktree-gate.sh" "tests/test-fix-issues-sprint-worktree-gate.sh"
run_suite "test-fix-issues-sprint-land-pr.sh" "tests/test-fix-issues-sprint-land-pr.sh"
run_suite "test-fix-issues-phase2-source-filter.sh" "tests/test-fix-issues-phase2-source-filter.sh"
run_suite "test-fix-issues-skip-persistence.sh" "tests/test-fix-issues-skip-persistence.sh"
run_suite "test-fix-issues-skip-effective-reason.sh" "tests/test-fix-issues-skip-effective-reason.sh"
run_suite "test-do.sh" "tests/test-do.sh"
# SEAM_HARDENING_HIGH Phase 3 — extract-and-run the real /commit arg-parser
# + the real /commit pr canonical /land-pr caller loop. These supersede the
# static-grep coverage that used to live in tests/test-commit.sh (removed).
run_suite "test-commit-parsing.sh" "tests/test-commit-parsing.sh"
run_suite "test-commit-pr-caller-loop.sh" "tests/test-commit-pr-caller-loop.sh"
run_suite "test-fix-report-smoke.sh" "tests/test-fix-report-smoke.sh"
run_suite "test-draft-plan-args-smoke.sh" "tests/test-draft-plan-args-smoke.sh"
# SEAM_HARDENING_REST Phase 5b — extract-and-run the research-and-go
# landing-mode regex + labeled presence-anchor for the model-layer
# decompose→dispatch core.
run_suite "test-research-and-go-args-smoke.sh" "tests/test-research-and-go-args-smoke.sh"
# SEAM_HARDENING_HIGH Phase 5 — extract-and-run the real draft-plan Phase-6 /
# refine-plan Phase-5 worktree-commit + /land-pr-result-parse fences (exit-1
# guards + allow-list parse), plus the refine-plan `## Argument parser` fence.
run_suite "test-draft-plan-phase6-fences.sh" "tests/test-draft-plan-phase6-fences.sh"
run_suite "test-refine-plan.sh" "tests/test-refine-plan.sh"
run_suite "test-add-example-smoke.sh" "tests/test-add-example-smoke.sh"
run_suite "test-add-block-smoke.sh" "tests/test-add-block-smoke.sh"
# Opt-in race-isolation test for the #594 fix pattern. Adds ~2-3 min
# to run-all.sh (20+5 conformance invocations), and the value is
# documentation-of-bug-class rather than direct regression coverage —
# the actual fix-regression guard lives in tests/test-skill-conformance.sh
# (PID-scope structural pin). Opt in with RUN_RACE_TESTS=1.
if [ -n "${RUN_RACE_TESTS:-}" ]; then
  run_suite "test-fixture-race-isolation.sh" "tests/test-fixture-race-isolation.sh"
fi
run_suite "test-frontmatter-helpers.sh" "tests/test-frontmatter-helpers.sh"
run_suite "test-update-zskills-migration.sh" "tests/test-update-zskills-migration.sh"
run_suite "test-update-zskills-agent-install" "tests/test-update-zskills-agent-install.sh"
run_suite "test-update-zskills-paths-migration.sh" "tests/test-update-zskills-paths-migration.sh"
run_suite "test-migrate-paths-awk.sh" "tests/test-migrate-paths-awk.sh"
run_suite "test-update-zskills-rerender.sh" "tests/test-update-zskills-rerender.sh"
run_suite "test-update-zskills-lane-aware.sh" "tests/test-update-zskills-lane-aware.sh"
run_suite "test-managed-md-up-to-date.sh" "tests/test-managed-md-up-to-date.sh"
run_suite "test-mirror-skill.sh" "tests/test-mirror-skill.sh"
run_suite "test-cleanup-merged-ahead-gate.sh" "tests/test-cleanup-merged-ahead-gate.sh"
run_suite "test-cleanup-merged-review.sh" "tests/test-cleanup-merged-review.sh"
run_suite "test-cleanup-merged-namelist.sh" "tests/test-cleanup-merged-namelist.sh"
run_suite "test-land-pr-scripts.sh" "tests/test-land-pr-scripts.sh"
run_suite "test-land-pr-worktree-detect.sh" "tests/test-land-pr-worktree-detect.sh"
run_suite "test-land-pr-post-merge-ff.sh" "tests/test-land-pr-post-merge-ff.sh"
run_suite "test-land-pr-auto-rebase-behind.sh" "tests/test-land-pr-auto-rebase-behind.sh"
run_suite "test-land-pr-drive-automerge.sh" "tests/test-land-pr-drive-automerge.sh"
run_suite "test-land-pr-rebase-rc14-parser.sh" "tests/test-land-pr-rebase-rc14-parser.sh"
# SEAM_HARDENING_HIGH Phase 1 — extract-and-run lib self-test. The libs it
# exercises (tests/lib/extract-fence.sh, tests/lib/landpr-harness.sh) are
# sourceable libraries, NOT suites, so they are intentionally NOT registered.
run_suite "test-extract-fence-lib.sh" "tests/test-extract-fence-lib.sh"
run_suite "test-land-pr-tracking-copy.sh" "tests/test-land-pr-tracking-copy.sh"
run_suite "test-landed-schema.sh" "tests/test-landed-schema.sh"
run_suite "test-landed-status-vocabulary.sh" "tests/test-landed-status-vocabulary.sh"
run_suite "test-zskills-paths.sh" "tests/test-zskills-paths.sh"
run_suite "test-zskills-skills-root.sh" "tests/test-zskills-skills-root.sh"
run_suite "test-zskills-resolve-config.sh" "tests/test-zskills-resolve-config.sh"
run_suite "test-json-set-string-field.sh" "tests/test-json-set-string-field.sh"
run_suite "test-skill-version-delta.sh" "tests/test-skill-version-delta.sh"
run_suite "test-update-zskills-version-surface.sh" "tests/test-update-zskills-version-surface.sh"
run_suite "test-skill-file-drift.sh" "tests/test-skill-file-drift.sh"
run_suite "test-skill-file-drift-extended-scope.sh" "tests/test-skill-file-drift-extended-scope.sh"
run_suite "test-plan-drift-correct.sh" "tests/test-plan-drift-correct.sh"
run_suite "test-plans-render-index.sh" "tests/test-plans-render-index.sh"
run_suite "test-work-on-plans.sh" "tests/test-work-on-plans.sh"
run_suite "test-work-on-plans-dispatch-seam.sh" "tests/test-work-on-plans-dispatch-seam.sh"
run_suite "test_zskills_monitor_collect.sh" "tests/test_zskills_monitor_collect.sh"
run_suite "test_zskills_monitor_server.sh" "tests/test_zskills_monitor_server.sh"
run_suite "test_zskills_monitor_csrf.sh" "tests/test_zskills_monitor_csrf.sh"
run_suite "test-stub-callouts.sh" "tests/test-stub-callouts.sh"
run_suite "test-post-create-worktree.sh" "tests/test-post-create-worktree.sh"
run_suite "test-pr-preflight.sh" "tests/test-pr-preflight.sh"
run_suite "test_zskills_monitor_dashboard_ui.sh" "tests/test_zskills_monitor_dashboard_ui.sh"
run_suite "test-dashboard-branch-cleanup-cmd.sh" "tests/test-dashboard-branch-cleanup-cmd.sh"
run_suite "test_zskills_dashboard_skill.sh" "tests/test_zskills_dashboard_skill.sh"
run_suite "test_zskills_dashboard_disconnect_debounce.sh" "tests/test_zskills_dashboard_disconnect_debounce.sh"
run_suite "test-issues-skip-reason-parse.sh" "tests/test-issues-skip-reason-parse.sh"
run_suite "test-pid-file-self-heal.sh" "tests/test-pid-file-self-heal.sh"
run_suite "test-migrate-flat-tracking-markers.sh" "tests/test-migrate-flat-tracking-markers.sh"
run_suite "test_plans_rebuild_uses_collect.sh" "tests/test_plans_rebuild_uses_collect.sh"
run_suite "test-post-run-invariants-ls-remote.sh" "tests/test-post-run-invariants-ls-remote.sh"
run_suite "test-fix-issues-claim-script.sh" "tests/test-fix-issues-claim-script.sh"
run_suite "test-fix-issues-claim-acquire-inline.sh" "tests/test-fix-issues-claim-acquire-inline.sh"
run_suite "test-fix-issues-claim-release-pr.sh" "tests/test-fix-issues-claim-release-pr.sh"
run_suite "test-fix-issues-claim-release-cherry-pick.sh" "tests/test-fix-issues-claim-release-cherry-pick.sh"
run_suite "test-fix-issues-claim-release-direct.sh" "tests/test-fix-issues-claim-release-direct.sh"
run_suite "test-fix-issues-claim-collector.sh" "tests/test-fix-issues-claim-collector.sh"
run_suite "test-fix-issues-claim-render-dom.sh" "tests/test-fix-issues-claim-render-dom.sh"
run_suite "test-dashboard-completed-readonly.sh" "tests/test-dashboard-completed-readonly.sh"
run_suite "test-dashboard-complete-render-drag.sh" "tests/test-dashboard-complete-render-drag.sh"
run_suite "test-dashboard-backlog-bidir.sh" "tests/test-dashboard-backlog-bidir.sh"
run_suite "test-backfill-plan-completed.sh" "tests/test-backfill-plan-completed.sh"
run_suite "test-fix-issues-claim-race-e2e.sh" "tests/test-fix-issues-claim-race-e2e.sh"
run_suite "test-fix-issues-claim-race-baseline.sh" "tests/test-fix-issues-claim-race-baseline.sh"
run_suite "test-fix-issues-claim-conformance.sh" "tests/test-fix-issues-claim-conformance.sh"
run_suite "test-fix-issues-claim-regression-single.sh" "tests/test-fix-issues-claim-regression-single.sh"
run_suite "test-plan-claim-script.sh" "tests/test-plan-claim-script.sh"
run_suite "test-plan-claim-race-baseline.sh" "tests/test-plan-claim-race-baseline.sh"
run_suite "test-plan-claim-hook-deny.sh" "tests/test-plan-claim-hook-deny.sh"
run_suite "test-plan-claim-main-root-anchor.sh" "tests/test-plan-claim-main-root-anchor.sh"
run_suite "test-plan-claim-race-e2e.sh" "tests/test-plan-claim-race-e2e.sh"
run_suite "test-plan-claim-release-phase6.sh" "tests/test-plan-claim-release-phase6.sh"
run_suite "test-plan-claim-release-stop.sh" "tests/test-plan-claim-release-stop.sh"
run_suite "test-plan-claim-release-window.sh" "tests/test-plan-claim-release-window.sh"
run_suite "test-plan-claim-release-already-complete.sh" "tests/test-plan-claim-release-already-complete.sh"
run_suite "test-plan-claim-selection-filter.sh" "tests/test-plan-claim-selection-filter.sh"
run_suite "test-work-on-plans-parallel-selection.sh" "tests/test-work-on-plans-parallel-selection.sh"
run_suite "test-plan-claim-filter-edge-cases.sh" "tests/test-plan-claim-filter-edge-cases.sh"
run_suite "test-fix-issues-selection-filter.sh" "tests/test-fix-issues-selection-filter.sh"
run_suite "test-plan-claim-collector.sh" "tests/test-plan-claim-collector.sh"
run_suite "test-plan-claim-render-dom.sh" "tests/test-plan-claim-render-dom.sh"
run_suite "test-mode-chip-three-state.sh" "tests/test-mode-chip-three-state.sh"
run_suite "test-dashboard-run-status-locks.sh" "tests/test-dashboard-run-status-locks.sh"
run_suite "test-tab-dot-render-dom.sh" "tests/test-tab-dot-render-dom.sh"
run_suite "test-doc-viewer-renderer.sh" "tests/test-doc-viewer-renderer.sh"
run_suite "test-doc-viewer-shell.sh" "tests/test-doc-viewer-shell.sh"
run_suite "test-doc-viewer-routing.sh" "tests/test-doc-viewer-routing.sh"
run_suite "test-doc-viewer-styling.sh" "tests/test-doc-viewer-styling.sh"
run_suite "test-doc-viewer-catalog.sh" "tests/test-doc-viewer-catalog.sh"
run_suite "test-doc-viewer-frontmatter.sh" "tests/test-doc-viewer-frontmatter.sh"
run_suite "test-plan-claim-handleaction-guard.sh" "tests/test-plan-claim-handleaction-guard.sh"
run_suite "test-plan-claim-moveall-skip.sh" "tests/test-plan-claim-moveall-skip.sh"
run_suite "test-plan-claim-fingerprint.sh" "tests/test-plan-claim-fingerprint.sh"
run_suite "test-plan-claim-conformance.sh" "tests/test-plan-claim-conformance.sh"
run_suite "test-claim-self-reentry.sh" "tests/test-claim-self-reentry.sh"
run_suite "test-inflight-batch-guard.sh" "tests/test-inflight-batch-guard.sh"
run_suite "test-demo-sim.sh" "tests/test-demo-sim.sh"
run_suite "test-plugin-manifest.sh" "tests/test-plugin-manifest.sh"
run_suite "test-plugin-marketplace.sh" "tests/test-plugin-marketplace.sh"
run_suite "test-plugin-ref-consistency.sh" "tests/test-plugin-ref-consistency.sh"
run_suite "test-plugin-self-load.sh" "tests/test-plugin-self-load.sh"
run_suite "test-plugin-live-load.sh" "tests/test-plugin-live-load.sh"
run_suite "test-plugin-mirrorless-resolution.sh" "tests/test-plugin-mirrorless-resolution.sh"
run_suite "test-plugin-d4-hook-siblings.sh" "tests/test-plugin-d4-hook-siblings.sh"
run_suite "test-plugin-hooks-integrity.sh" "tests/test-plugin-hooks-integrity.sh"
# Phase 2 — SessionStart materialiser + dual-install detection + renderer.
run_suite "test-sessionstart-materialise.sh" "tests/test-sessionstart-materialise.sh"
run_suite "test-sessionstart-materialise-overwrite-guard.sh" "tests/test-sessionstart-materialise-overwrite-guard.sh"
run_suite "test-sessionstart-dual-install-detect.sh" "tests/test-sessionstart-dual-install-detect.sh"
run_suite "test-synthetic-consumer-install.sh" "tests/test-synthetic-consumer-install.sh"
run_suite "test-render-managed-rules-correctness.sh" "tests/test-render-managed-rules-correctness.sh"
run_suite "test-managed-md-renderer-equivalence.sh" "tests/test-managed-md-renderer-equivalence.sh"
run_suite "test-inject-bash-timeout-parity.sh" "tests/test-inject-bash-timeout-parity.sh"
run_suite "test-verify-response-validate-parity.sh" "tests/test-verify-response-validate-parity.sh"
run_suite "test-hook-template-sibling.sh" "tests/test-hook-template-sibling.sh"
# Phase 3 — dual-path recognition + cron-fire path-aware rules + frontmatter survival.
run_suite "test-cron-prefix-or-match.sh" "tests/test-cron-prefix-or-match.sh"
run_suite "test-cron-fire-rule-dual-path.sh" "tests/test-cron-fire-rule-dual-path.sh"
run_suite "test-skill-frontmatter-survival.sh" "tests/test-skill-frontmatter-survival.sh"

# Phase 5 — bidirectional lane switch + hook double-fire conditional-skip shim.
run_suite "test-switch-install-path.sh" "tests/test-switch-install-path.sh"
run_suite "test-plugin-hook-skip-on-double-register.sh" "tests/test-plugin-hook-skip-on-double-register.sh"

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
