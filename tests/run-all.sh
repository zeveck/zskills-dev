#!/bin/bash
# Run all test suites and report results.
# Run from repo root: bash tests/run-all.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export CLAUDE_PROJECT_DIR="$REPO_ROOT"

# Shared "Results:" line parser (#587-hardened anchored regex), factored out
# so serial + parallel runners share one parsing contract. parse_results
# echoes "PASS FAIL"; this caller retains exit-code capture, accumulation,
# the 0/0 fall-through, and the OVERALL_EXIT flip on any non-zero suite rc.
. "$SCRIPT_DIR/lib/parse-results.sh"

TOTAL_PASS=0
TOTAL_FAIL=0
OVERALL_EXIT=0

# ──────────────────────────────────────────────────────────────────────────
# SUITE_PROVENANCE Phase 1 (#1166) — provenance header. Emitted ONCE by the
# MAIN process to stdout, BEFORE any suite output, in BOTH parallel (default)
# and serial (ZSKILLS_PARALLEL=0) modes. The caller's `> file` redirect
# captures it as the result file's header; the sourced validator
# tests/lib/suite-result-valid.sh later answers "is this result still TRUE for
# the current tree?". run-all.sh does NOT `cd` (REPO_ROOT is exported above but
# there is zero `cd`), so EVERY git call MUST pass `-C "$REPO_ROOT"` — a bare
# `git rev-parse` would read the caller's cwd. The bottom `Overall:` tally is
# UNTOUCHED. On git-absent each field is emitted EMPTY (fail-safe); the
# validator treats an empty tree/fingerprint/epoch as malformed → full re-run.
PROV_TREE="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || true)"
# CONTENT-sensitive fingerprint: committed HEAD + ALL tracked changes
# (git diff HEAD covers staged+unstaged CONTENT) + the CONTENT of every
# untracked-not-ignored file (--exclude-standard honors .gitignore). This
# hashes file CONTENT, not just changed PATHS, so it FLIPS on a content-only
# edit to an already-modified file (which a porcelain formula would miss).
PROV_FINGERPRINT="$(
  {
    git -C "$REPO_ROOT" rev-parse HEAD
    git -C "$REPO_ROOT" diff HEAD
    git -C "$REPO_ROOT" ls-files --others --exclude-standard -z \
      | while IFS= read -r -d '' f; do
          printf '%s\0' "$f"
          git -C "$REPO_ROOT" hash-object "$REPO_ROOT/$f"
        done
  } 2>/dev/null | git -C "$REPO_ROOT" hash-object --stdin 2>/dev/null || true
)"
PROV_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
PROV_EPOCH="$(date -u +%s)"
PROV_COMMAND="tests/run-all.sh"
echo "zskills-suite-provenance: v1"
echo "tree=$PROV_TREE"
echo "fingerprint=$PROV_FINGERPRINT"
echo "timestamp=$PROV_TIMESTAMP"
echo "epoch=$PROV_EPOCH"
echo "command=$PROV_COMMAND"

# ──────────────────────────────────────────────────────────────────────────
# TEST_SUITE_PARALLELIZATION Phase 4 — bounded-worker PARALLEL fan-out is the
# DEFAULT; ZSKILLS_PARALLEL=0 is the opt-OUT to the byte-identical serial
# reference path. DESIGN CHOICE: the fan-out lives IN run-all.sh (NOT a separate
# run-all-parallel.sh), per the plan + Critical Invariants — this keeps the
# literal `run_suite "<name>" "<path>"` registry (the 23-suite self-assert
# greps + the suite-registry lib's static parse) anchored in ONE file. The
# registry lines below are UNCHANGED; only the dispatch behavior of run_suite
# is mode-aware:
#
#   • Parallel (default, ZSKILLS_PARALLEL unset/1): run_suite COLLECTS each
#     (name, script) into ordered arrays instead of running it. After all the
#     literal registration lines have executed (collecting the full set,
#     including the conditional RUN_RACE_TESTS / RUN_E2E `if` blocks and the
#     attended gate's branch), a driver at the bottom: (a) subtracts the
#     Phase-3 serial bucket, (b) dedupes the live-load double-registration,
#     (c) fans the remaining POOL out at min(configured, nproc) workers, (d)
#     runs the serial bucket OUTSIDE the pool, and (e) reports in REGISTERED
#     order.
#   • Serial (opt-out, ZSKILLS_PARALLEL=0): run_suite runs each suite inline,
#     accumulating immediately — the original behavior, verbatim. This is the
#     escape hatch for debugging an interleaved failure.
#
# The pool / serial-bucket split + serial-bucket execution reuse the Phase 0
# + Phase 3 registry helpers (is_serial_suite / serial_run_attended_live_load)
# from tests/lib/suite-registry.sh — sourced only on the parallel path.
ZSKILLS_PARALLEL="${ZSKILLS_PARALLEL:-1}"

# Ordered collection arrays (parallel mode). Index-aligned: REG_NAMES[i] is
# the display name, REG_SCRIPTS[i] the script path, REG_ATTENDED[i] is 1 iff
# the attended-gate-pass branch registered it with ZSKILLS_LIVE_ATTENDED=1.
REG_NAMES=()
REG_SCRIPTS=()
REG_ATTENDED=()

run_suite() {
  local name="$1"
  local script="$2"

  if [[ "$ZSKILLS_PARALLEL" == "1" ]]; then
    # Parallel mode: COLLECT, don't run. ZSKILLS_LIVE_ATTENDED is only set in
    # the attended-gate-pass arm's `ZSKILLS_LIVE_ATTENDED=1 run_suite ...`
    # prefix; capture it so the parallel driver can drop the live-load
    # registration entirely (it is dispatched ONCE via the serial bucket).
    REG_NAMES+=("$name")
    REG_SCRIPTS+=("$script")
    REG_ATTENDED+=("${ZSKILLS_LIVE_ATTENDED:-0}")
    return 0
  fi

  echo ""
  printf '\033[1mTests: %s\033[0m\n' "$name"

  output=$(bash "$REPO_ROOT/$script" 2>&1)
  local exit_code=$?

  echo "$output"

  # Extract counts from the canonical "Results: <N> passed, <N> failed"
  # line via the shared parser (tests/lib/parse-results.sh). It strips ANSI
  # color codes and anchors to that exact line shape so any inner-test
  # diagnostics (e.g., test-hooks.sh's fixture-extension synthetic-fixture
  # run that nests a `tests/test-skill-conformance.sh` invocation — see #587)
  # can't leak a count into the outer parser. If no canonical line is found,
  # parse_results returns "0 0"; the suite's own exit code still flips
  # OVERALL_EXIT below, so an unparseable suite is not silently dropped.
  local passed failed
  read -r passed failed < <(parse_results "$output")

  TOTAL_PASS=$((TOTAL_PASS + ${passed:-0}))
  TOTAL_FAIL=$((TOTAL_FAIL + ${failed:-0}))

  if [[ $exit_code -ne 0 ]]; then
    OVERALL_EXIT=1
  fi
}

# Phase 1b: the former tests/test-hooks.sh monolith is split into 8 independent
# sub-suites, each sourcing tests/lib/hooks-harness.sh. The literal registry
# stays here (the Phase 4 parallel runner READS it). Σ of the 8 sub-suite pass
# counts == the monolith's 2384 (no self-registration → net-zero whole-suite
# change). The monolith is removed (no shim) to avoid double-counting.
run_suite "test-hooks-block-unsafe.sh" "tests/test-hooks-block-unsafe.sh"
run_suite "test-block-unmaterialised-skill.sh" "tests/test-block-unmaterialised-skill.sh"
run_suite "test-hooks-bypass-generic.sh" "tests/test-hooks-bypass-generic.sh"
run_suite "test-hooks-bypass-project.sh" "tests/test-hooks-bypass-project.sh"
run_suite "test-hooks-main-protected.sh" "tests/test-hooks-main-protected.sh"
run_suite "test-hooks-worktree-cd.sh" "tests/test-hooks-worktree-cd.sh"
run_suite "test-hooks-agent.sh" "tests/test-hooks-agent.sh"
run_suite "test-hooks-warn-drift.sh" "tests/test-hooks-warn-drift.sh"
run_suite "test-hooks-misc.sh" "tests/test-hooks-misc.sh"
run_suite "test-hooks-helpers.sh" "tests/test-hooks-helpers.sh"
run_suite "test-tokenize-then-walk.sh" "tests/test-tokenize-then-walk.sh"
run_suite "test-hook-helper-drift.sh" "tests/test-hook-helper-drift.sh"
run_suite "test-zskills-enforcement-lib.sh" "tests/test-zskills-enforcement-lib.sh"
run_suite "test-normalize-tool-path.sh" "tests/test-normalize-tool-path.sh"
run_suite "test-resolve-effective-worktree-root.sh" "tests/test-resolve-effective-worktree-root.sh"
run_suite "test-resolve-python.sh" "tests/test-resolve-python.sh"
run_suite "test-python-resolver-drift.sh" "tests/test-python-resolver-drift.sh"
# #1086 — END-TO-END guard for the MS-Store broken-python3 stub class: puts a
# broken `python3` FIRST on PATH (real `python` behind it) and runs the actual
# SessionStart rules hook + a /briefing skill-body fence, asserting both
# resolve via $PYTHON and nothing runs real work through the stub. (Catches
# the python-resolution class only; NOT a full Windows qual — see the file
# header.)
run_suite "test-broken-python3-stub-e2e.sh" "tests/test-broken-python3-stub-e2e.sh"
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
run_suite "test-move-to-worktree.sh" "tests/test-move-to-worktree.sh"
run_suite "test-skill-content-hash.sh" "tests/test-skill-content-hash.sh"
run_suite "test-skill-description-budget.sh" "tests/test-skill-description-budget.sh"
run_suite "test-skill-version-compare.sh" "tests/test-skill-version-compare.sh"
run_suite "test-skill-conformance.sh" "tests/test-skill-conformance.sh"
# #1102 — standing guard against the false-pass-on-stale-/tmp class: a test
# checking a hardcoded /tmp/<artifact> for output a ${TMPDIR:-/tmp}-honoring
# script actually writes under $TMPDIR (caught once in #1100).
run_suite "test-tmpdir-hardcode-guard.sh" "tests/test-tmpdir-hardcode-guard.sh"
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
run_suite "test-block-fix-issue-unclaimed-ownership.sh" "tests/test-block-fix-issue-unclaimed-ownership.sh"
run_suite "test-block-main-edits.sh" "tests/test-block-main-edits.sh"
run_suite "test-tracking-integration.sh" "tests/test-tracking-integration.sh"
run_suite "test-fix-issues.sh" "tests/test-fix-issues.sh"
run_suite "test-fix-issues-dashboard.sh" "tests/test-fix-issues-dashboard.sh"
run_suite "test-fix-issues-bare-invocation.sh" "tests/test-fix-issues-bare-invocation.sh"
run_suite "test-fix-issues-bootstrap.sh" "tests/test-fix-issues-bootstrap.sh"
run_suite "test-fix-issues-worktree-cap.sh" "tests/test-fix-issues-worktree-cap.sh"
run_suite "test-fix-issues-sprint-worktree-gate.sh" "tests/test-fix-issues-sprint-worktree-gate.sh"
run_suite "test-fix-issues-sprint-land-pr.sh" "tests/test-fix-issues-sprint-land-pr.sh"
run_suite "test-fix-issues-phase2-source-filter.sh" "tests/test-fix-issues-phase2-source-filter.sh"
run_suite "test-fix-issues-skip-persistence.sh" "tests/test-fix-issues-skip-persistence.sh"
run_suite "test-fix-issues-skip-effective-reason.sh" "tests/test-fix-issues-skip-effective-reason.sh"
run_suite "test-do.sh" "tests/test-do.sh"
run_suite "test-do-issue-num-parser.sh" "tests/test-do-issue-num-parser.sh"
run_suite "test-do-multi-issue-fanout.sh" "tests/test-do-multi-issue-fanout.sh"
run_suite "test-do-pr-claim-release.sh" "tests/test-do-pr-claim-release.sh"
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
run_suite "test-update-zskills-init.sh" "tests/test-update-zskills-init.sh"
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
# TEST_SUITE_PARALLELIZATION Phase 0 — self-tests for the shared infra libs.
# tests/lib/parse-results.sh (Results-line parser) + tests/lib/suite-registry.sh
# (registered-suite enumerator) are sourceable libraries, NOT suites, so they
# are intentionally NOT registered; these two ARE the registered self-tests.
run_suite "test-parse-results.sh" "tests/test-parse-results.sh"
run_suite "test-suite-registry.sh" "tests/test-suite-registry.sh"
# #1186 — completeness gate: every on-disk tests/test-*.sh MUST be referenced
# in run-all.sh (or carry an inline-reasoned allowlist entry). Statically
# greps the registry; does NOT execute run-all.sh.
run_suite "test-suite-registration-complete.sh" "tests/test-suite-registration-complete.sh"
# SUITE_PROVENANCE Phase 1 (#1166) — self-test for the sourceable validator
# lib tests/lib/suite-result-valid.sh (which is NOT registered as a run_suite,
# same as parse-results.sh / suite-registry.sh above).
run_suite "test-suite-result-valid.sh" "tests/test-suite-result-valid.sh"
run_suite "test-land-pr-tracking-copy.sh" "tests/test-land-pr-tracking-copy.sh"
run_suite "test-landed-schema.sh" "tests/test-landed-schema.sh"
run_suite "test-landed-status-vocabulary.sh" "tests/test-landed-status-vocabulary.sh"
run_suite "test-zskills-paths.sh" "tests/test-zskills-paths.sh"
run_suite "test-zskills-skills-root.sh" "tests/test-zskills-skills-root.sh"
run_suite "test-zsh-fence-resolution.sh" "tests/test-zsh-fence-resolution.sh"
run_suite "test-zsh-fence-semantics.sh" "tests/test-zsh-fence-semantics.sh"
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
run_suite "test-monitor-state-queue-post-preservation.sh" "tests/test-monitor-state-queue-post-preservation.sh"
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
run_suite "test-mark-plan-complete.sh" "tests/test-mark-plan-complete.sh"
run_suite "test-fix-issues-claim-race-e2e.sh" "tests/test-fix-issues-claim-race-e2e.sh"
run_suite "test-fix-issues-claim-race-baseline.sh" "tests/test-fix-issues-claim-race-baseline.sh"
run_suite "test-fix-issues-claim-conformance.sh" "tests/test-fix-issues-claim-conformance.sh"
run_suite "test-fix-issues-claim-regression-single.sh" "tests/test-fix-issues-claim-regression-single.sh"
run_suite "test-plan-claim-script.sh" "tests/test-plan-claim-script.sh"
run_suite "test-run-plan-test-cmd-candidate.sh" "tests/test-run-plan-test-cmd-candidate.sh"
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
run_suite "test-plans-skip-chip.sh" "tests/test-plans-skip-chip.sh"
run_suite "test-plan-skip-clear-paths.sh" "tests/test-plan-skip-clear-paths.sh"
run_suite "test-issues-skip-dismiss-ui.sh" "tests/test-issues-skip-dismiss-ui.sh"
run_suite "test-issue-reconsider-endpoint.sh" "tests/test-issue-reconsider-endpoint.sh"
run_suite "test-activity-feed-skip-status.sh" "tests/test-activity-feed-skip-status.sh"
run_suite "test-tab-dot-render-dom.sh" "tests/test-tab-dot-render-dom.sh"
run_suite "test-doc-viewer-renderer.sh" "tests/test-doc-viewer-renderer.sh"
run_suite "test-doc-viewer-shell.sh" "tests/test-doc-viewer-shell.sh"
run_suite "test-doc-viewer-routing.sh" "tests/test-doc-viewer-routing.sh"
run_suite "test-doc-viewer-styling.sh" "tests/test-doc-viewer-styling.sh"
run_suite "test-doc-viewer-catalog.sh" "tests/test-doc-viewer-catalog.sh"
run_suite "test-doc-viewer-frontmatter.sh" "tests/test-doc-viewer-frontmatter.sh"
run_suite "test-doc-viewer-parity.sh" "tests/test-doc-viewer-parity.sh"
run_suite "test-doc-viewer-nojekyll.sh" "tests/test-doc-viewer-nojekyll.sh"
run_suite "test-plan-claim-handleaction-guard.sh" "tests/test-plan-claim-handleaction-guard.sh"
run_suite "test-plan-claim-moveall-skip.sh" "tests/test-plan-claim-moveall-skip.sh"
run_suite "test-plan-claim-fingerprint.sh" "tests/test-plan-claim-fingerprint.sh"
run_suite "test-plan-claim-conformance.sh" "tests/test-plan-claim-conformance.sh"
run_suite "test-claim-plan-heartbeat.sh" "tests/test-claim-plan-heartbeat.sh"
run_suite "test-claim-self-reentry.sh" "tests/test-claim-self-reentry.sh"
run_suite "test-inflight-batch-guard.sh" "tests/test-inflight-batch-guard.sh"
run_suite "test-inflight-reentry-guard.sh" "tests/test-inflight-reentry-guard.sh"
run_suite "test-demo-sim.sh" "tests/test-demo-sim.sh"
run_suite "test-plugin-manifest.sh" "tests/test-plugin-manifest.sh"
# INSTALL_REDESIGN Phase 2 (1A) — root agents/ vs .claude/agents parity.
run_suite "test-agents-parity.sh" "tests/test-agents-parity.sh"
run_suite "test-plugin-marketplace.sh" "tests/test-plugin-marketplace.sh"
run_suite "test-plugin-ref-consistency.sh" "tests/test-plugin-ref-consistency.sh"
run_suite "test-plugin-self-load.sh" "tests/test-plugin-self-load.sh"
# #991 — deterministic unit test for the attended capability-gate decision
# (runs without live `claude`); the gate itself wires in just below.
run_suite "test-attended-gate.sh" "tests/test-attended-gate.sh"

# #991 — capability-gate + throttle the live plugin runtime checks (§B of
# test-plugin-live-load.sh) so they auto-run when the machine CAN (claude CLI +
# credentials present) and SKIP cleanly when it can't (CI: no `claude`), with a
# throttle so we don't add live-`claude` time to EVERY full-suite run. The
# marker is stored OUT OF TREE (~/.zskills/last-attended-plugin-run) so it never
# pollutes `git status`, survives worktree removal, and applies globally. When
# the gate fails (CI, or throttled) we leave ZSKILLS_LIVE_ATTENDED unset → §B
# SKIPs exactly as before, so CI behavior is byte-for-byte unchanged.
if [[ "$ZSKILLS_PARALLEL" == "1" ]]; then
  # Parallel mode: the attended gate (capability + throttle + marker refresh)
  # and the single live-load dispatch are owned by the serial-bucket driver
  # (serial_run_attended_live_load) at the bottom — live-load is in the
  # Phase-3 serial bucket (global throttle marker + live `claude`, both
  # un-parallelizable). We DO collect a single live-load registration here so
  # list_registered_suites parity holds, but WITHOUT evaluating the gate or
  # refreshing the marker (that would double-refresh against the serial
  # driver). The collected entry is later SUBTRACTED from the pool by
  # is_serial_suite, so it never enters the parallel fan-out.
  run_suite "test-plugin-live-load.sh" "tests/test-plugin-live-load.sh"
else
  . "$REPO_ROOT/tests/lib/attended-gate.sh"
  ATTENDED_MARKER="${HOME:-/tmp}/.zskills/last-attended-plugin-run"
  ATTENDED_THROTTLE_SECONDS="${ZSKILLS_ATTENDED_THROTTLE_SECONDS:-14400}"  # ~4h
  ATTENDED_NOW="$(date +%s)"
  if attended_gate_should_run "$ATTENDED_MARKER" "$ATTENDED_NOW" "$ATTENDED_THROTTLE_SECONDS"; then
    echo ""
    echo "[#991] attended gate PASSED (claude + creds present, throttle window elapsed) — running §B live."
    ZSKILLS_LIVE_ATTENDED=1 run_suite "test-plugin-live-load.sh" "tests/test-plugin-live-load.sh"
    attended_gate_refresh_marker "$ATTENDED_MARKER" "$ATTENDED_NOW"
  else
    run_suite "test-plugin-live-load.sh" "tests/test-plugin-live-load.sh"
  fi
fi
run_suite "test-plugin-mirrorless-resolution.sh" "tests/test-plugin-mirrorless-resolution.sh"
run_suite "test-plugin-d4-hook-siblings.sh" "tests/test-plugin-d4-hook-siblings.sh"
# #1002 — dev→prod URL rewrite + strip parity in the shared finalizer.
run_suite "test-build-rewrite-dev-urls.sh" "tests/test-build-rewrite-dev-urls.sh"
run_suite "test-build-rewrite-marketplace-repo.sh" "tests/test-build-rewrite-marketplace-repo.sh"
run_suite "test-prod-tree-no-dev-urls.sh" "tests/test-prod-tree-no-dev-urls.sh"
run_suite "test-build-prod-strip-parity.sh" "tests/test-build-prod-strip-parity.sh"
run_suite "test-plugin-hooks-integrity.sh" "tests/test-plugin-hooks-integrity.sh"
# Session-logging capability — Stop/SubagentStop renderer + permission merge,
# passive/fail-open PermissionRequest hook, and the session-logs.sh helper.
run_suite "test-session-logging.sh" "tests/test-session-logging.sh"
# (The materialiser / overwrite-guard / dual-install-detect suites were
# deleted in INSTALL_REDESIGN Phase 7 — subject-removal with the SessionStart
# materialiser hook; the D27 probe's survivors are covered via
# detect-install-state.sh's callers.)
# #1119 / Phase 7 — SessionStart setup greeting (systemMessage on stdout)
# toward the one-time /zs:update-zskills init.
run_suite "test-sessionstart-greeting.sh" "tests/test-sessionstart-greeting.sh"
# INSTALL_REDESIGN Phase 4 (R-b) — SessionStart rules delivery via additionalContext.
run_suite "test-session-rules-context.sh" "tests/test-session-rules-context.sh"
run_suite "test-synthetic-consumer-install.sh" "tests/test-synthetic-consumer-install.sh"
run_suite "test-verify-install.sh" "tests/test-verify-install.sh"
run_suite "test-render-managed-rules-correctness.sh" "tests/test-render-managed-rules-correctness.sh"
# (test-managed-md-renderer-equivalence.sh was deleted in INSTALL_REDESIGN
# Phase 7 — subject-removal: its subject was the no-sentinel vs --sentinel
# render-path byte-equivalence, and the --sentinel path died with the D20
# convention; the surviving render properties are pinned by
# test-render-managed-rules-correctness.sh cases 1/2/6b.)
run_suite "test-inject-bash-timeout-parity.sh" "tests/test-inject-bash-timeout-parity.sh"
# test-verify-response-validate-parity.sh DELETED (INSTALL_REDESIGN Phase 3,
# subject-removal): the hooks/ + .claude/hooks/ copies it compared no longer
# exist — the script is skill-bundled at skills/update-zskills/scripts/, and
# its source↔mirror parity is owned by test-skills-mirror-parity.sh.
run_suite "test-hook-template-sibling.sh" "tests/test-hook-template-sibling.sh"
# Phase 3 — dual-path recognition + cron-fire path-aware rules + frontmatter survival.
run_suite "test-cron-prefix-or-match.sh" "tests/test-cron-prefix-or-match.sh"
run_suite "test-cron-fire-rule-dual-path.sh" "tests/test-cron-fire-rule-dual-path.sh"
run_suite "test-skill-frontmatter-survival.sh" "tests/test-skill-frontmatter-survival.sh"

# Phase 5 — hook double-fire conditional-skip shim. (The lane-switch suite
# was deleted in INSTALL_REDESIGN Phase 7 with the switch machinery —
# subject-removal; a consumer switches lanes by uninstalling one lane and
# installing the other.)
run_suite "test-plugin-hook-skip-on-double-register.sh" "tests/test-plugin-hook-skip-on-double-register.sh"

# CODEX_PORT_PLAN Phase 0 — Codex porting probe kit (container-runnable: no
# codex binary needed; exercises --list, refusal, --validate, summary format,
# and the Git-Bash/BSD portability self-check).
run_suite "test-porting-probe-kit.sh" "tests/test-porting-probe-kit.sh"

# Opt-in end-to-end smoke for parallel pipelines. Heavier than unit tests
# (real git repos, concurrent writes), so it runs only when RUN_E2E is set.
if [ -n "${RUN_E2E:-}" ]; then
  run_suite "e2e-parallel-pipelines.sh" "tests/e2e-parallel-pipelines.sh"
fi

# ──────────────────────────────────────────────────────────────────────────
# TEST_SUITE_PARALLELIZATION Phase 4 — parallel driver. Runs ONLY when
# ZSKILLS_PARALLEL=1; in serial mode this whole block is skipped and the
# inline run_suite accumulation above is authoritative (byte-identical legacy
# behavior). At this point the registration arrays (REG_NAMES / REG_SCRIPTS /
# REG_ATTENDED) hold every suite the serial run would have run, in registered
# order, with the conditional `if` blocks and the attended branch already
# resolved by their own gates.
if [[ "$ZSKILLS_PARALLEL" == "1" ]]; then
  # Phase 0 + Phase 3 registry helpers: is_serial_suite (pool/serial split)
  # and serial_run_attended_live_load (the verbatim attended-gate live-load).
  . "$SCRIPT_DIR/lib/suite-registry.sh"

  # Worker cap = literal min(configured, nproc) — a CEILING at nproc so the
  # 4-core CI runner is never oversubscribed. Resolves to `configured` on the
  # 32-core dev box, to 4 on ubuntu-latest. ZSKILLS_PARALLEL_JOBS overrides
  # `configured` (lets the perf AC force a 4-worker CI estimate locally).
  CONFIGURED_WORKERS="${ZSKILLS_PARALLEL_JOBS:-12}"
  NPROC="$( (command -v nproc >/dev/null 2>&1 && nproc) || echo 1)"
  WORKERS="$CONFIGURED_WORKERS"
  if [[ "$NPROC" -lt "$WORKERS" ]]; then
    WORKERS="$NPROC"
  fi
  [[ "$WORKERS" -lt 1 ]] && WORKERS=1

  # Per-suite output/rc capture dir (out of tree → never in `git status`).
  PARALLEL_DIR="$(mktemp -d -t zskills-runall-parallel-XXXXXX)"
  parallel_cleanup() {
    [ -n "${PARALLEL_DIR:-}" ] && [ -d "$PARALLEL_DIR" ] && \
      { find "$PARALLEL_DIR" -mindepth 1 -delete 2>/dev/null; rmdir "$PARALLEL_DIR" 2>/dev/null; }
  }
  trap parallel_cleanup EXIT INT TERM

  # The worker subshell function: run ONE suite with its own TMPDIR (Phase 2
  # WI3 isolation) under a per-suite `timeout 600` (SIGTERMs its own child;
  # NO kill/pkill), capturing stdout+stderr to <slug>.out and the rc to
  # <slug>.rc. parse_results runs in the MAIN process after wait (the worker
  # only persists raw output + rc), so an empty/unparseable .out still flips
  # OVERALL_EXIT via its nonzero .rc.
  #
  # REPO_ROOT and the capture dir are passed as ARGUMENTS, NOT exported into
  # the suite env. This is load-bearing for parity: the serial run_suite runs
  # each suite with only CLAUDE_PROJECT_DIR exported (run-all.sh:7) — REPO_ROOT
  # is a plain local there. Several suites invoke hooks (block-main-edits.sh,
  # tokenize-then-walk, block-unsafe-*) that PREFER an inherited `REPO_ROOT`
  # over their own test-set CLAUDE_PROJECT_DIR sandbox; exporting REPO_ROOT to
  # the workers would point those hooks at the real worktree (a linked git
  # worktree → the hook no-ops), silently turning real DENY assertions into
  # empty-envelope FAILs. So the worker sets neither — it inherits the SAME env
  # the serial path gives a suite (CLAUDE_PROJECT_DIR only), plus its private
  # TMPDIR.
  run_suite_worker() {
    local repo_root="$1" pdir="$2" script="$3" slug="$4"
    local suite_tmp
    suite_tmp="$(mktemp -d)"
    TMPDIR="$suite_tmp" timeout 600 bash "$repo_root/$script" \
      > "$pdir/$slug.out" 2>&1
    echo "$?" > "$pdir/$slug.rc"
    find "$suite_tmp" -mindepth 1 -delete 2>/dev/null
    rmdir "$suite_tmp" 2>/dev/null
  }
  export -f run_suite_worker
  # Only CLAUDE_PROJECT_DIR is exported (already exported at run-all.sh:7) —
  # matching the serial suite env exactly. REPO_ROOT / PARALLEL_DIR travel as
  # worker arguments, never as exported env (see worker comment above).

  # Build the PARALLEL POOL = registered set MINUS the Phase-3 serial bucket,
  # de-duped (the live-load double-registration collapses to one entry, which
  # is_serial_suite then removes — it is dispatched once via the serial
  # bucket). POOL_NAMES / POOL_SCRIPTS / POOL_SLUGS stay index-aligned and in
  # REGISTERED order so results print deterministically (human parity with
  # serial). The slug is a filesystem-safe, collision-free key.
  POOL_NAMES=()
  POOL_SCRIPTS=()
  POOL_SLUGS=()
  declare -A _pool_seen=()
  for i in "${!REG_SCRIPTS[@]}"; do
    s="${REG_SCRIPTS[$i]}"
    is_serial_suite "$s" && continue          # serial bucket → outside pool
    [[ -n "${_pool_seen[$s]:-}" ]] && continue  # dedupe (e.g. live-load arms)
    _pool_seen[$s]=1
    POOL_NAMES+=("${REG_NAMES[$i]}")
    POOL_SCRIPTS+=("$s")
    POOL_SLUGS+=("$(printf '%05d_%s' "${#POOL_SLUGS[@]}" "$(echo "$s" | tr '/.' '__')")")
  done

  echo ""
  echo "== TEST_SUITE_PARALLELIZATION Phase 4 — PARALLEL fan-out =="
  echo "   pool suites: ${#POOL_SCRIPTS[@]}   workers: $WORKERS (min(configured=$CONFIGURED_WORKERS, nproc=$NPROC))   capture: $PARALLEL_DIR"

  # Bounded fan-out: launch up to $WORKERS suites at a time, reaping with
  # `wait -n` (NO kill/pkill). Each suite is its own backgrounded
  # run_suite_worker.
  running=0
  for i in "${!POOL_SCRIPTS[@]}"; do
    run_suite_worker "$REPO_ROOT" "$PARALLEL_DIR" "${POOL_SCRIPTS[$i]}" "${POOL_SLUGS[$i]}" &
    running=$((running + 1))
    if [[ "$running" -ge "$WORKERS" ]]; then
      wait -n
      running=$((running - 1))
    fi
  done
  wait   # reap the remaining in-flight workers

  # Accumulate POOL results in REGISTERED order via parse_results (one parsing
  # contract, shared with serial). An empty/no-Results .out yields "0 0" but
  # its nonzero .rc still flips OVERALL_EXIT — the unparseable-but-nonzero
  # signal is preserved.
  for i in "${!POOL_SCRIPTS[@]}"; do
    slug="${POOL_SLUGS[$i]}"
    out="$PARALLEL_DIR/$slug.out"
    rc_file="$PARALLEL_DIR/$slug.rc"
    suite_out=""
    [ -f "$out" ] && suite_out="$(cat "$out")"
    suite_rc=1
    [ -f "$rc_file" ] && suite_rc="$(cat "$rc_file")"

    echo ""
    printf '\033[1mTests: %s\033[0m\n' "${POOL_NAMES[$i]}"
    echo "$suite_out"

    read -r passed failed < <(parse_results "$suite_out")
    TOTAL_PASS=$((TOTAL_PASS + ${passed:-0}))
    TOTAL_FAIL=$((TOTAL_FAIL + ${failed:-0}))
    if [[ "${suite_rc:-1}" -ne 0 ]]; then
      OVERALL_EXIT=1
    fi
  done

  # ── Serial bucket — run OUTSIDE the pool (Phase 3 + Phase 4) ────────────
  # These suites are genuinely un-parallelizable (the LIVE-SERVER class: a
  # real HTTP server on a $$-derived or fixed port; plus the attended
  # live-load's global throttle marker + live `claude`). They run serially
  # via the SAME inline run_suite (serial accumulation path), since
  # ZSKILLS_PARALLEL toggling is what gated collection vs run. We temporarily
  # flip to serial so run_suite executes inline for the bucket.
  #
  # GENERIC DISPATCH over list_serial_suites (Phase 4): the bucket is no
  # longer a hardcoded two-suite list. We iterate EVERY entry the registry
  # pins serial so a newly-pinned suite (e.g. the dashboard live-server suite)
  # actually executes here, OUTSIDE the pool — otherwise is_serial_suite would
  # subtract it from the parallel set but it would never run, dropping its
  # passes and breaking parity. The attended live-load is the ONE entry that
  # carries a gate (capability + throttle + marker refresh), so it is
  # dispatched via serial_run_attended_live_load; every other entry is a
  # plain inline run_suite. We match the live-load entry by PATH (order-
  # independent).
  echo ""
  echo "== Phase 3/4 serial bucket — run OUTSIDE the parallel pool =="
  ZSKILLS_PARALLEL=0
  while IFS=$'\t' read -r _serial_gate _serial_path; do
    if [[ "$_serial_path" == "tests/test-plugin-live-load.sh" ]]; then
      # attended live-load: verbatim attended gate, dispatched once via helper.
      serial_run_attended_live_load run_suite
    else
      # plain live-server suite (monitor_server, csrf, dashboard_ui,
      # dashboard_skill, state-queue, pid-file-self-heal): inline run_suite.
      run_suite "$(basename "$_serial_path")" "$_serial_path"
    fi
  done < <(list_serial_suites)
  ZSKILLS_PARALLEL=1
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
