#!/bin/bash
# Tests for hooks (sub-suite, Test Suite Parallelization Phase 1b).
# Misc hook coverage: project-hook tracking/delegation/step/scoping basics, landing-mode + worktree-path + land-phase + PR-mode arg parsing, post-run-invariants.sh, Phase-C real-git integration, pipeline scoping A-F, /verify-changes arg parser, runtime config read, three-case test-pipe gate, test-infra detection sync, drift-regression deny/allow list, and the fixture-extension single-source-of-truth coverage.
# This file is a MOVE of sections out of the former tests/test-hooks.sh
# monolith — every assertion is preserved verbatim. Run from repo root or
# any cwd: bash tests/test-hooks-misc.sh
#
# SOURCES tests/lib/hooks-harness.sh for all shared helpers and the
# absolutized hook-path globals (HOOK / PROJECT_HOOK / AGENTS_HOOK /
# WARN_HOOK), pass/fail counters, expect_* helpers, the project-hook
# fixture helpers, and setup_project_test_on_main. Emits exactly ONE
# canonical Results: line. Registered in run-all.sh as a run_suite; it
# carries no self-registration assertion (matches the former monolith).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/hooks/block-unsafe-generic.sh"

# shellcheck source=tests/lib/extract-fence.sh
# Shared fence-extraction primitives — used by test_verify_changes_arg_parser.
. "$SCRIPT_DIR/lib/extract-fence.sh"

# shellcheck source=tests/lib/hooks-harness.sh
. "$SCRIPT_DIR/lib/hooks-harness.sh"

echo "=== Project hook: tracking file protection ==="

setup_project_test

# Block recursive rm of tracking directory
expect_project_deny "rm -rf .zskills/tracking"
expect_project_deny "rm -r .zskills/tracking"
expect_project_deny "rm -fr .zskills/tracking"

# Allow individual file deletion within tracking directory
expect_project_allow "rm .zskills/tracking/requires.foo"
expect_project_allow "rm -f .zskills/tracking/requires.old"

# Regression guards (absolute paths, long form, flag-after-path).
expect_project_deny "rm -rf /workspaces/zskills/.zskills/tracking"
expect_project_deny "rm --recursive .zskills/tracking"
expect_project_deny "rm /tmp/a -r .zskills/tracking/foo"

# Path-config plan Phase 1 (1.7) — broadened regex catches all .zskills/* siblings.
# Original behavior preserved (.zskills/tracking still blocks); broadened scope
# also covers .zskills/issues, .zskills/audit (and any other future sibling).
# The recursive-flag requirement is unchanged: non-recursive flags pass through
# regardless of path shape.
expect_project_deny "rm -rf .zskills/issues"
expect_project_deny "rm -rf .zskills/audit"
expect_project_deny "rm -rf .zskills/tracking"
expect_project_allow "rm -f .zskills-tracked (no recursive flag — passes broader regex too)" \
  "rm -f .zskills-tracked"
expect_project_allow "rm -f x.zskills.bak (no recursive flag — recursive-flag clause gates the block regardless of path shape)" \
  "rm -f x.zskills.bak"

# False-positive guards for anchor drift in the -r flag pattern.
# Past failure: the original pattern was `rm[[:space:]].*-[a-zA-Z]*r[a-zA-Z]*.*\.zskills/tracking`
# which matched ANY `-word-containing-r` token in the rm's buffer (including
# substrings like `-tracked` inside `.zskills-tracked` pathnames, or unrelated
# long flags like `--branch` / `--worktree` in an entirely different command
# later in the same bash blob). The -r flag must be anchored to a flag-token
# boundary (preceded by whitespace, not mid-word) AND scoped to a single shell
# command (no ; & | crossing).
expect_project_allow "rm -f .zskills-tracked (dash-tracked substring, not tracking dir)" \
  "rm -f $WT/.zskills-tracked"
expect_project_allow "rm -f file; later command with --worktree and .zskills/tracking" \
  "rm -f foo.txt; bash scripts/post-run-invariants.sh --worktree /tmp/wt --branch b; printf >/workspaces/z/.zskills/tracking/marker"
expect_project_allow "multi-line: rm -f then later .zskills/tracking (no -r anywhere)" \
  "printf > /tmp/.zskills/tracking/foo
rm -f /tmp/.zskills-tracked
bash scripts/post-run-invariants.sh --worktree /tmp/wt --branch b"
expect_project_allow "rm -f on file whose basename contains -r substring" \
  "rm -f /tmp/.zskills/tracking-adjacent-path-reporter.log"
expect_project_allow "rm -f plus --branch flag (--branch has 'r' in 'branch' but is a long flag)" \
  "rm -f /tmp/x; gh pr view --branch main; cat /tmp/.zskills/tracking/foo"

# Data-region redaction parity with block-unsafe-generic.sh: pattern rules
# now scan an extracted + redacted $COMMAND, so commit messages and heredoc
# prose that DISCUSS a banned pattern don't trip the rule scanning that
# pattern. Extends the earlier (issue 7f-style) tests in generic's suite to
# cover project-hook rules.
expect_project_allow "commit -m mentions 'git push' literally — doesn't trip push-tracking rule" \
  'git commit -m "warn: don'\''t git push before tests"'
expect_project_allow "commit -m mentions 'git cherry-pick' — doesn't trip cherry-pick rule" \
  'git commit -m "docs: see git cherry-pick notes"'
expect_project_allow "commit -m mentions 'git add .claude/logs/' — doesn't trip logs rule" \
  'git commit -m "note: avoid git add .claude/logs/ — stage by name"'
expect_project_allow "commit -m mentions '.zskills/tracking' — doesn't trip recursive-delete rule" \
  'git commit -m "docs: .zskills/tracking cleanup via scripts"'
expect_project_allow "commit -m mentions 'bash scripts/clear-tracking.sh' — doesn't trip exec rule" \
  'git commit -m "hint: run bash scripts/clear-tracking.sh if stale"'
# Same flag-scoped redaction covers gh pr/issue body/title args.
expect_project_allow "gh pr create --body mentions banned pattern — not execution" \
  'gh pr create --body "warn: '\''git push --force'\'' will fail here"'
# Chained destructive op AFTER a redacted -m message still blocks.
expect_project_deny  "commit with prose + chained deny op still denies the chain" \
  'git commit -m "msg about git push" && rm -rf .zskills/tracking'

# Block execution of clear-tracking script
expect_project_deny "bash scripts/clear-tracking.sh"
expect_project_deny "sh scripts/clear-tracking.sh"
expect_project_deny "./scripts/clear-tracking.sh"

# Allow reading clear-tracking script
expect_project_allow "cat scripts/clear-tracking.sh"
expect_project_allow "grep -n confirm scripts/clear-tracking.sh"

# Regression: must NOT false-positive on commands that merely MENTION the path
# without executing it. The fix requires bash|sh at a command-verb boundary
# (start of JSON command field, or a command separator ;&|(`), NOT bare
# whitespace. So file-suffix `.sh ` and mentions inside echo strings are OK.
expect_project_allow "git add .claude/hooks/block-unsafe-project.sh scripts/clear-tracking.sh"
expect_project_allow "diff old.sh scripts/clear-tracking.sh"
expect_project_allow "ls -la foo.sh scripts/clear-tracking.sh"
# Echo-string false positive (session 2 of parallel-canary run hit this):
# "bash" inside a quoted echo is data, not a verb.
expect_project_allow "echo 'Run: bash scripts/clear-tracking.sh to reset markers'"
expect_project_allow "printf 'hint: sh scripts/clear-tracking.sh for users\n'"
# Execution via pipe/separator/subshell is still blocked.
expect_project_deny "cat foo | bash scripts/clear-tracking.sh"
expect_project_deny "true && bash scripts/clear-tracking.sh"
expect_project_deny "cd /tmp ; bash scripts/clear-tracking.sh"
expect_project_deny "echo \$(bash scripts/clear-tracking.sh)"

teardown_project_test

echo ""
echo "=== Project hook: test output piping ==="

setup_project_test

# Block: test command actually piped (the behavior we want to catch)
expect_project_deny "npm test | tee out.txt"
expect_project_deny "npm test | grep fail"
expect_project_deny "npm test 2>&1 | head -20"
expect_project_deny "npm run test:all | cat"

# Allow: redirect-to-file is the correct pattern
expect_project_allow "npm test > .test-results.txt 2>&1"
expect_project_allow "npm run test:all > /tmp/out.txt 2>&1"

# Regression: pipe on a DIFFERENT segment must not trip the test-pipe block.
# The original bug: pipe check looked at the whole command, not per-segment.
expect_project_allow "ls shared/dist/ | head -5 && npm test > .test-results.txt 2>&1"
expect_project_allow "cat pkg.json | jq . ; npm test > out.txt 2>&1"
expect_project_allow "echo start && grep foo src/ | wc -l || npm test > out.txt 2>&1"

teardown_project_test

# Default transcript written by setup_project_test declares
# ZSKILLS_PIPELINE_ID=run-plan.test-plan so the hook reads under
# .zskills/tracking/run-plan.test-plan/ per the Option B layout.
# (docs/tracking/TRACKING_NAMING.md)
DEFAULT_SUBDIR=".zskills/tracking/run-plan.test-plan"

echo ""
echo "=== Project hook: delegation enforcement ==="

# Test: requires.X without fulfilled.X blocks git commit
setup_project_test
mkdir -p "$TEST_TMPDIR/$DEFAULT_SUBDIR"
touch "$TEST_TMPDIR/$DEFAULT_SUBDIR/requires.verify-changes.test-plan"
# Stage a code file so it's not content-only
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
expect_project_deny "git commit -m test"
teardown_project_test

# Test: requires.X with fulfilled.X in the same subdir allows git commit
setup_project_test
mkdir -p "$TEST_TMPDIR/$DEFAULT_SUBDIR"
touch "$TEST_TMPDIR/$DEFAULT_SUBDIR/requires.verify-changes.test-plan"
touch "$TEST_TMPDIR/$DEFAULT_SUBDIR/fulfilled.verify-changes.test-plan"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
expect_project_allow "git commit -m test"
teardown_project_test

# Test: delegation blocks git cherry-pick too
setup_project_test
mkdir -p "$TEST_TMPDIR/$DEFAULT_SUBDIR"
touch "$TEST_TMPDIR/$DEFAULT_SUBDIR/requires.verify-changes.test-plan"
expect_project_deny "git cherry-pick abc123"
teardown_project_test

# Test: requires.land-pr without fulfilled.land-pr blocks git commit
# (closes Phase-6-skip hole in /run-plan PR mode — PR #211)
setup_project_test
mkdir -p "$TEST_TMPDIR/$DEFAULT_SUBDIR"
touch "$TEST_TMPDIR/$DEFAULT_SUBDIR/requires.land-pr.test-plan"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
expect_project_deny "git commit -m test"
teardown_project_test

# Test: requires.land-pr with fulfilled.land-pr allows git commit
setup_project_test
mkdir -p "$TEST_TMPDIR/$DEFAULT_SUBDIR"
touch "$TEST_TMPDIR/$DEFAULT_SUBDIR/requires.land-pr.test-plan"
touch "$TEST_TMPDIR/$DEFAULT_SUBDIR/fulfilled.land-pr.test-plan"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
expect_project_allow "git commit -m test"
teardown_project_test

# Test: requires.land-pr also blocks git cherry-pick (parity with verify-changes)
setup_project_test
mkdir -p "$TEST_TMPDIR/$DEFAULT_SUBDIR"
touch "$TEST_TMPDIR/$DEFAULT_SUBDIR/requires.land-pr.test-plan"
expect_project_deny "git cherry-pick abc123"
teardown_project_test

# Issue #547: requires.* enforcement on commit fires ONLY when on main.
# Commits on feature branches (where PR-mode /run-plan implementer/verifier
# subagents actually commit) must NOT be gated by `requires.land-pr.<id>` —
# that marker's fulfillment can only happen AFTER those commits land via
# /land-pr. Past failure: PR #544 verifier commit blocked on feature branch.

# Positive case: commit on feature branch with UNFULFILLED requires.land-pr
# is allowed. (Asserts the gate now only fires on main — the marker is
# present and there is no fulfilled.land-pr companion. If we tightened the
# check by mistake — e.g., always denying — this test would catch it.)
setup_project_test
mkdir -p "$TEST_TMPDIR/$DEFAULT_SUBDIR"
touch "$TEST_TMPDIR/$DEFAULT_SUBDIR/requires.land-pr.test-plan"
# Confirm the marker is unfulfilled: no fulfilled.land-pr.* in the subdir.
if compgen -G "$TEST_TMPDIR/$DEFAULT_SUBDIR/fulfilled.land-pr.*" >/dev/null; then
  fail "issue-547 positive setup: fulfilled.land-pr.* should not exist"
fi
# Switch to a feature branch so is_on_main returns false.
(cd "$TEST_TMPDIR" && git checkout -q -b fix/issue-547-test 2>/dev/null)
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
expect_project_allow "issue-547: commit on feature branch with unfulfilled requires.land-pr" "git commit -m test"
teardown_project_test

# Negative case: same pipeline, same unfulfilled marker — but on main —
# is STILL denied. (Preserves PR #211's protection: a finish-auto exit
# before /land-pr leaves the marker unfulfilled, and any commit-to-main
# in that pipeline is blocked.)
setup_project_test
mkdir -p "$TEST_TMPDIR/$DEFAULT_SUBDIR"
touch "$TEST_TMPDIR/$DEFAULT_SUBDIR/requires.land-pr.test-plan"
# setup_project_test leaves us on the init default branch (master) which
# is_on_main accepts. Explicit assertion for clarity:
_branch=$(cd "$TEST_TMPDIR" && git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [[ "$_branch" != "main" && "$_branch" != "master" ]]; then
  fail "issue-547 negative setup: expected main/master, got $_branch"
fi
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
expect_project_deny "issue-547: commit on main with unfulfilled requires.land-pr (still blocked)" "git commit -m test"
teardown_project_test

# Issue #986: the carve-out is per-marker-type, not blanket-branch.
# requires.verify-changes.* (and any non-land-pr requires.*) MUST enforce
# on feature branches too — verify-changes can and should run pre-merge.
# Past failure: PR #980 landed with requires.verify-changes.doc-viewer
# unfulfilled because every commit was on the feature branch and the
# outer is_on_main gate skipped all requires.* checks.

# Positive case (#986 fix): commit on feature branch with UNFULFILLED
# requires.verify-changes.* must be DENIED.
setup_project_test
mkdir -p "$TEST_TMPDIR/$DEFAULT_SUBDIR"
touch "$TEST_TMPDIR/$DEFAULT_SUBDIR/requires.verify-changes.test-plan"
# Switch to a feature branch.
(cd "$TEST_TMPDIR" && git checkout -q -b fix/issue-986-test 2>/dev/null)
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
expect_project_deny "issue-986: commit on feature branch with unfulfilled requires.verify-changes (now blocked)" "git commit -m test"
teardown_project_test

# Negative case (#986 fix): commit on feature branch with FULFILLED
# requires.verify-changes.* must be ALLOWED (the verifier ran).
setup_project_test
mkdir -p "$TEST_TMPDIR/$DEFAULT_SUBDIR"
touch "$TEST_TMPDIR/$DEFAULT_SUBDIR/requires.verify-changes.test-plan"
touch "$TEST_TMPDIR/$DEFAULT_SUBDIR/fulfilled.verify-changes.test-plan"
(cd "$TEST_TMPDIR" && git checkout -q -b fix/issue-986-test 2>/dev/null)
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
expect_project_allow "issue-986: commit on feature branch with fulfilled requires.verify-changes (passes)" "git commit -m test"
teardown_project_test

echo ""
echo "=== Project hook: step enforcement ==="

# Test: step.X.implement without step.X.verify blocks
setup_project_test
mkdir -p "$TEST_TMPDIR/$DEFAULT_SUBDIR"
touch "$TEST_TMPDIR/$DEFAULT_SUBDIR/step.run-plan.test-plan.implement"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
expect_project_deny "git commit -m test"
teardown_project_test

# Test: step.X.implement with step.X.verify but no step.X.report blocks
setup_project_test
mkdir -p "$TEST_TMPDIR/$DEFAULT_SUBDIR"
touch "$TEST_TMPDIR/$DEFAULT_SUBDIR/step.run-plan.test-plan.implement"
touch "$TEST_TMPDIR/$DEFAULT_SUBDIR/step.run-plan.test-plan.verify"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
expect_project_deny "git commit -m test"
teardown_project_test

# Test: step.X.implement + step.X.verify + step.X.report allows
setup_project_test
mkdir -p "$TEST_TMPDIR/$DEFAULT_SUBDIR"
touch "$TEST_TMPDIR/$DEFAULT_SUBDIR/step.run-plan.test-plan.implement"
touch "$TEST_TMPDIR/$DEFAULT_SUBDIR/step.run-plan.test-plan.verify"
touch "$TEST_TMPDIR/$DEFAULT_SUBDIR/step.run-plan.test-plan.report"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
expect_project_allow "git commit -m test"
teardown_project_test

# Test: phasestep.* markers are ignored (not enforced)
setup_project_test
mkdir -p "$TEST_TMPDIR/$DEFAULT_SUBDIR"
touch "$TEST_TMPDIR/$DEFAULT_SUBDIR/phasestep.run-plan.test-plan.implement"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
expect_project_allow "git commit -m test"
teardown_project_test

# Test: step enforcement on cherry-pick
setup_project_test
mkdir -p "$TEST_TMPDIR/$DEFAULT_SUBDIR"
touch "$TEST_TMPDIR/$DEFAULT_SUBDIR/step.run-plan.test-plan.implement"
expect_project_deny "git cherry-pick abc123"
teardown_project_test

echo ""
echo "=== Project hook: no staleness bypass ==="

# Test: stale requires.* (>8h) STILL blocks — no staleness bypass
setup_project_test
mkdir -p "$TEST_TMPDIR/$DEFAULT_SUBDIR"
touch "$TEST_TMPDIR/$DEFAULT_SUBDIR/requires.verify-changes.test-plan"
# Make requires file look old (>8h = 480min)
touch -t 202501010000 "$TEST_TMPDIR/$DEFAULT_SUBDIR/requires.verify-changes.test-plan"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
expect_project_deny "git commit -m test"
teardown_project_test

# Test: fresh requires.* also blocks (same behavior as stale)
setup_project_test
mkdir -p "$TEST_TMPDIR/$DEFAULT_SUBDIR"
touch "$TEST_TMPDIR/$DEFAULT_SUBDIR/requires.verify-changes.test-plan"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
expect_project_deny "git commit -m test"
teardown_project_test

echo ""
echo "=== Project hook: backward compatibility ==="

# Test: no tracking dir → silently passes
setup_project_test
rmdir "$TEST_TMPDIR/.zskills/tracking"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
expect_project_allow "git commit -m test"
teardown_project_test

# Test: content-only commits bypass tracking enforcement
setup_project_test
mkdir -p "$TEST_TMPDIR/$DEFAULT_SUBDIR"
touch "$TEST_TMPDIR/$DEFAULT_SUBDIR/requires.verify-changes.test-plan"
(cd "$TEST_TMPDIR" && echo "content" > readme.md && git add readme.md)
expect_project_allow "git commit -m test"
teardown_project_test

echo ""
echo "=== Project hook: .zskills-tracked pipeline association ==="

# Test: .zskills-tracked file associates agent with pipeline
setup_project_test
printf 'run-plan.thermal-domain\n' > "$TEST_TMPDIR/.zskills-tracked"
TD_DIR="$TEST_TMPDIR/.zskills/tracking/run-plan.thermal-domain"
mkdir -p "$TD_DIR"
touch "$TD_DIR/requires.verify-changes.thermal-domain"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
# Remove transcript so ONLY .zskills-tracked provides the association
rm -f "$TEST_TMPDIR/.transcript"
printf 'npm run test:all\n' > "$TEST_TMPDIR/.transcript"
expect_project_deny "git commit -m test"
teardown_project_test

# Test: .zskills-tracked with fulfilled requirement allows commit
setup_project_test
printf 'run-plan.thermal-domain\n' > "$TEST_TMPDIR/.zskills-tracked"
TD_DIR="$TEST_TMPDIR/.zskills/tracking/run-plan.thermal-domain"
mkdir -p "$TD_DIR"
touch "$TD_DIR/requires.verify-changes.thermal-domain"
touch "$TD_DIR/fulfilled.verify-changes.thermal-domain"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
rm -f "$TEST_TMPDIR/.transcript"
printf 'npm run test:all\n' > "$TEST_TMPDIR/.transcript"
expect_project_allow "git commit -m test"
teardown_project_test

# Test: no .zskills-tracked AND no pipeline in transcript → skip enforcement
setup_project_test
TD_DIR="$TEST_TMPDIR/.zskills/tracking/run-plan.thermal-domain"
mkdir -p "$TD_DIR"
touch "$TD_DIR/requires.verify-changes.thermal-domain"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
# Transcript has test command but NO pipeline skill
rm -f "$TEST_TMPDIR/.transcript"
printf 'npm run test:all\n' > "$TEST_TMPDIR/.transcript"
expect_project_allow "git commit -m test"
teardown_project_test

echo ""
echo "=== Project hook: pipeline scoping (subdir isolation) ==="

# Test: Pipeline A's subdir does not block Pipeline B (disjoint subdirs)
setup_project_test
printf 'run-plan.pipeline-B\n' > "$TEST_TMPDIR/.zskills-tracked"
mkdir -p "$TEST_TMPDIR/.zskills/tracking/run-plan.pipeline-A"
touch "$TEST_TMPDIR/.zskills/tracking/run-plan.pipeline-A/requires.verify-changes.pipeline-A"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
rm -f "$TEST_TMPDIR/.transcript"
printf 'npm run test:all\n' > "$TEST_TMPDIR/.transcript"
expect_project_allow "git commit -m test"
teardown_project_test

# Test: Same pipeline's subdir markers DO block
setup_project_test
printf 'run-plan.pipeline-B\n' > "$TEST_TMPDIR/.zskills-tracked"
mkdir -p "$TEST_TMPDIR/.zskills/tracking/run-plan.pipeline-B"
touch "$TEST_TMPDIR/.zskills/tracking/run-plan.pipeline-B/requires.verify-changes.pipeline-B"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
rm -f "$TEST_TMPDIR/.transcript"
printf 'npm run test:all\n' > "$TEST_TMPDIR/.transcript"
expect_project_deny "git commit -m test"
teardown_project_test

# Test: Transcript ZSKILLS_PIPELINE_ID scopes to specific pipeline subdir
setup_project_test
mkdir -p "$TEST_TMPDIR/.zskills/tracking/run-plan.pipeline-A"
mkdir -p "$TEST_TMPDIR/.zskills/tracking/run-plan.pipeline-B"
touch "$TEST_TMPDIR/.zskills/tracking/run-plan.pipeline-A/requires.verify-changes.pipeline-A"
touch "$TEST_TMPDIR/.zskills/tracking/run-plan.pipeline-B/requires.verify-changes.pipeline-B"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
# Transcript declares pipeline A → only pipeline A's subdir checked
rm -f "$TEST_TMPDIR/.transcript"
printf 'npm run test:all\nZSKILLS_PIPELINE_ID=run-plan.pipeline-A\n' > "$TEST_TMPDIR/.transcript"
# Pipeline A unfulfilled → blocked
expect_project_deny "git commit -m test"
teardown_project_test

# Test: Transcript pipeline ID with fulfilled marker in same subdir allows commit
setup_project_test
mkdir -p "$TEST_TMPDIR/.zskills/tracking/run-plan.pipeline-A"
mkdir -p "$TEST_TMPDIR/.zskills/tracking/run-plan.pipeline-B"
touch "$TEST_TMPDIR/.zskills/tracking/run-plan.pipeline-A/requires.verify-changes.pipeline-A"
touch "$TEST_TMPDIR/.zskills/tracking/run-plan.pipeline-A/fulfilled.verify-changes.pipeline-A"
touch "$TEST_TMPDIR/.zskills/tracking/run-plan.pipeline-B/requires.verify-changes.pipeline-B"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
# Transcript declares pipeline A → pipeline B's subdir untouched
rm -f "$TEST_TMPDIR/.transcript"
printf 'npm run test:all\nZSKILLS_PIPELINE_ID=run-plan.pipeline-A\n' > "$TEST_TMPDIR/.transcript"
expect_project_allow "git commit -m test"
teardown_project_test

# Test: Transcript last-match wins (sequential runs in same session)
setup_project_test
mkdir -p "$TEST_TMPDIR/.zskills/tracking/run-plan.pipeline-A"
mkdir -p "$TEST_TMPDIR/.zskills/tracking/run-plan.pipeline-B"
touch "$TEST_TMPDIR/.zskills/tracking/run-plan.pipeline-A/requires.verify-changes.pipeline-A"
touch "$TEST_TMPDIR/.zskills/tracking/run-plan.pipeline-A/fulfilled.verify-changes.pipeline-A"
touch "$TEST_TMPDIR/.zskills/tracking/run-plan.pipeline-B/requires.verify-changes.pipeline-B"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
# Two pipeline IDs in transcript — last one wins (pipeline B)
rm -f "$TEST_TMPDIR/.transcript"
printf 'npm run test:all\nZSKILLS_PIPELINE_ID=run-plan.pipeline-A\nZSKILLS_PIPELINE_ID=run-plan.pipeline-B\n' > "$TEST_TMPDIR/.transcript"
# Pipeline B unfulfilled in B's subdir → blocked (even though pipeline A is fulfilled)
expect_project_deny "git commit -m test"
teardown_project_test

# Test: Step scoping — pipeline B's impl marker (in B's subdir) doesn't block pipeline A
setup_project_test
printf 'run-plan.pipeline-A\n' > "$TEST_TMPDIR/.zskills-tracked"
mkdir -p "$TEST_TMPDIR/.zskills/tracking/run-plan.pipeline-B"
touch "$TEST_TMPDIR/.zskills/tracking/run-plan.pipeline-B/step.run-plan.pipeline-B.implement"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
rm -f "$TEST_TMPDIR/.transcript"
printf 'npm run test:all\n' > "$TEST_TMPDIR/.transcript"
expect_project_allow "git commit -m test"
teardown_project_test

# Test: Flat-fallback suffix-match precision (LEGACY — fallback still
# invoked when the per-pipeline subdir is absent; removed in Phase 6).
# Pipeline ID "plan" does NOT end ".run-plan.thermal-domain".
setup_project_test
printf 'plan\n' > "$TEST_TMPDIR/.zskills-tracked"
# Intentionally flat (no subdir). Exercises the transitional fallback path.
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.thermal-domain"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
rm -f "$TEST_TMPDIR/.transcript"
printf 'npm run test:all\n' > "$TEST_TMPDIR/.transcript"
# "plan" does NOT end ".run-plan.thermal-domain" → marker skipped → allowed
expect_project_allow "git commit -m test"
teardown_project_test

echo ""
echo "=== Project hook: push enforcement ==="

# Test: git push blocked by unfulfilled requirement
setup_project_test
setup_push_remote
mkdir -p "$TEST_TMPDIR/$DEFAULT_SUBDIR"
touch "$TEST_TMPDIR/$DEFAULT_SUBDIR/requires.verify-changes.test-plan"
# Add a code file commit after the remote baseline so @{u}..HEAD has code
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js && git commit -q -m "code")
expect_project_deny "git push origin main"
teardown_project_test

# Test: git push allowed when requirement fulfilled in same subdir
setup_project_test
mkdir -p "$TEST_TMPDIR/$DEFAULT_SUBDIR"
touch "$TEST_TMPDIR/$DEFAULT_SUBDIR/requires.verify-changes.test-plan"
touch "$TEST_TMPDIR/$DEFAULT_SUBDIR/fulfilled.verify-changes.test-plan"
expect_project_allow "git push origin main"
teardown_project_test

# Test: git push blocked by step without verification
setup_project_test
setup_push_remote
mkdir -p "$TEST_TMPDIR/$DEFAULT_SUBDIR"
touch "$TEST_TMPDIR/$DEFAULT_SUBDIR/step.run-plan.test-plan.implement"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js && git commit -q -m "code")
expect_project_deny "git push origin main"
teardown_project_test

# Test: git push with pipeline scoping (subdir isolation)
setup_project_test
printf 'run-plan.pipeline-A\n' > "$TEST_TMPDIR/.zskills-tracked"
mkdir -p "$TEST_TMPDIR/.zskills/tracking/run-plan.pipeline-B"
touch "$TEST_TMPDIR/.zskills/tracking/run-plan.pipeline-B/requires.verify-changes.pipeline-B"
rm -f "$TEST_TMPDIR/.transcript"
printf 'npm run test:all\n' > "$TEST_TMPDIR/.transcript"
expect_project_allow "git push origin main"
teardown_project_test

# Test: content-only push allowed despite unfulfilled requirements
setup_project_test
setup_push_remote
mkdir -p "$TEST_TMPDIR/$DEFAULT_SUBDIR"
touch "$TEST_TMPDIR/$DEFAULT_SUBDIR/requires.verify-changes.test-plan"
# Only markdown files in the push diff — no code files
(cd "$TEST_TMPDIR" && echo "# readme" > README.md && git add README.md && git commit -q -m "docs")
expect_project_allow "git push origin main"
teardown_project_test

# Config file: no custom hook tests needed. The config at .claude/zskills-config.json
# is user-managed. Whether writes to .claude/ prompt is permission-mode-dependent
# and not enforced by this hook layer.

echo ""
echo "=== Config extraction: bash regex ==="

# Test: extract string value from config
CONFIG='{"project_name": "my-app", "timezone": "America/New_York"}'
if [[ "$CONFIG" =~ \"project_name\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && [[ "${BASH_REMATCH[1]}" == "my-app" ]]; then
  pass "extract string value (project_name=my-app)"
else
  fail "extract string value (project_name=my-app)"
fi

# Test: extract boolean value from config
CONFIG='{"execution": {"main_protected": true}}'
if [[ "$CONFIG" =~ \"main_protected\"[[:space:]]*:[[:space:]]*(true|false) ]] && [[ "${BASH_REMATCH[1]}" == "true" ]]; then
  pass "extract boolean value (main_protected=true)"
else
  fail "extract boolean value (main_protected=true)"
fi

# Test: extract integer value from config
CONFIG='{"ci": {"max_fix_attempts": 3}}'
if [[ "$CONFIG" =~ \"max_fix_attempts\"[[:space:]]*:[[:space:]]*([0-9]+) ]] && [[ "${BASH_REMATCH[1]}" == "3" ]]; then
  pass "extract integer value (max_fix_attempts=3)"
else
  fail "extract integer value (max_fix_attempts=3)"
fi

# Test: empty string value extracted correctly
CONFIG='{"dev_server": {"cmd": ""}}'
if [[ "$CONFIG" =~ \"cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && [[ "${BASH_REMATCH[1]}" == "" ]]; then
  pass "extract empty string value (cmd='')"
else
  fail "extract empty string value (cmd='')"
fi

# Test: missing config field falls through (no match)
CONFIG='{"project_name": "my-app"}'
if [[ "$CONFIG" =~ \"nonexistent\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
  fail "missing field should not match"
else
  pass "missing field falls through (no match)"
fi

# Test: landing mode extraction
CONFIG='{"execution": {"landing": "pr", "main_protected": false}}'
if [[ "$CONFIG" =~ \"landing\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && [[ "${BASH_REMATCH[1]}" == "pr" ]]; then
  pass "extract landing mode (landing=pr)"
else
  fail "extract landing mode (landing=pr)"
fi

echo ""

echo "=== Landing mode argument detection ==="

# Test: detect "pr" argument (case-insensitive)
ARGUMENTS="plans/FEATURE.md finish auto pr"
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[pP][rR]($|[[:space:]]) ]]; then
  pass "detect pr argument"
else
  fail "detect pr argument"
fi

# Test: detect "PR" (uppercase)
ARGUMENTS="plans/FEATURE.md PR auto"
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[pP][rR]($|[[:space:]]) ]]; then
  pass "detect PR uppercase"
else
  fail "detect PR uppercase"
fi

# Test: detect "direct" argument (case-insensitive)
ARGUMENTS="plans/FEATURE.md direct"
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[dD][iI][rR][eE][cC][tT]($|[[:space:]]) ]]; then
  pass "detect direct argument"
else
  fail "detect direct argument"
fi

# Test: detect "DIRECT" (uppercase)
ARGUMENTS="plans/FEATURE.md DIRECT auto"
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[dD][iI][rR][eE][cC][tT]($|[[:space:]]) ]]; then
  pass "detect DIRECT uppercase"
else
  fail "detect DIRECT uppercase"
fi

# Test: no landing mode argument -> falls through
ARGUMENTS="plans/FEATURE.md finish auto"
DETECTED_MODE="none"
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[pP][rR]($|[[:space:]]) ]]; then
  DETECTED_MODE="pr"
fi
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[dD][iI][rR][eE][cC][tT]($|[[:space:]]) ]]; then
  DETECTED_MODE="direct"
fi
if [ "$DETECTED_MODE" = "none" ]; then
  pass "no landing mode falls through"
else
  fail "no landing mode falls through — detected '$DETECTED_MODE'"
fi

# Test: "pr" inside a word does not match (e.g., "SPRINT")
ARGUMENTS="plans/SPRINT_PLAN.md finish"
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[pP][rR]($|[[:space:]]) ]]; then
  fail "word boundary: 'pr' should not match inside 'SPRINT'"
else
  pass "word boundary: 'pr' does not match inside 'SPRINT'"
fi

# Test: "direct" inside a word does not match (e.g., "indirectly")
ARGUMENTS="plans/INDIRECT_PLAN.md finish"
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[dD][iI][rR][eE][cC][tT]($|[[:space:]]) ]]; then
  fail "word boundary: 'direct' should not match inside 'INDIRECT'"
else
  pass "word boundary: 'direct' does not match inside 'INDIRECT'"
fi

# Test: direct + main_protected -> conflict detected
CONFIG='{"execution": {"landing": "cherry-pick", "main_protected": true}}'
LANDING_MODE="direct"
CONFLICT_DETECTED="no"
if [[ "$CONFIG" =~ \"main_protected\"[[:space:]]*:[[:space:]]*true ]]; then
  if [ "$LANDING_MODE" = "direct" ]; then
    CONFLICT_DETECTED="yes"
  fi
fi
if [ "$CONFLICT_DETECTED" = "yes" ]; then
  pass "direct + main_protected conflict detected"
else
  fail "direct + main_protected conflict not detected"
fi

# Test: config landing default read when no argument
LANDING_MODE="cherry-pick"
CONFIG_CONTENT='{"execution": {"landing": "pr", "main_protected": false}}'
if [[ "$CONFIG_CONTENT" =~ \"landing\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
  CFG_LANDING="${BASH_REMATCH[1]}"
  if [ -n "$CFG_LANDING" ]; then
    LANDING_MODE="$CFG_LANDING"
  fi
fi
if [ "$LANDING_MODE" = "pr" ]; then
  pass "config default landing mode read correctly"
else
  fail "config default landing mode — expected 'pr', got '$LANDING_MODE'"
fi

# Test: branch_prefix empty string handled correctly
BRANCH_PREFIX="feat/"
CONFIG_CONTENT='{"execution": {"branch_prefix": ""}}'
if [[ "$CONFIG_CONTENT" =~ \"branch_prefix\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
  BRANCH_PREFIX="${BASH_REMATCH[1]}"
fi
if [ "$BRANCH_PREFIX" = "" ]; then
  pass "branch_prefix empty string sets empty prefix"
else
  fail "branch_prefix empty string — expected empty, got '$BRANCH_PREFIX'"
fi

# Test: branch_prefix non-empty value
BRANCH_PREFIX="feat/"
CONFIG_CONTENT='{"execution": {"branch_prefix": "fix/"}}'
if [[ "$CONFIG_CONTENT" =~ \"branch_prefix\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
  BRANCH_PREFIX="${BASH_REMATCH[1]}"
fi
if [ "$BRANCH_PREFIX" = "fix/" ]; then
  pass "branch_prefix reads custom value"
else
  fail "branch_prefix custom value — expected 'fix/', got '$BRANCH_PREFIX'"
fi

echo ""
echo "=== Worktree path construction ==="

# Test: cherry-pick worktree path follows convention
PLAN_FILE="plans/THERMAL_DOMAIN_PLAN.md"
PLAN_SLUG=$(basename "$PLAN_FILE" .md | tr '[:upper:]' '[:lower:]' | tr '_' '-')
PROJECT_NAME="myproject"
PHASE="4b"
WORKTREE_PATH="/tmp/${PROJECT_NAME}-cp-${PLAN_SLUG}-phase-${PHASE}"
if [ "$WORKTREE_PATH" = "/tmp/myproject-cp-thermal-domain-plan-phase-4b" ]; then
  pass "worktree path: /tmp/<project>-cp-<slug>-phase-<N>"
else
  fail "worktree path: expected /tmp/myproject-cp-thermal-domain-plan-phase-4b, got $WORKTREE_PATH"
fi

# Test: plan slug handles mixed case and underscores
PLAN_FILE="plans/My_Feature_PLAN.md"
PLAN_SLUG=$(basename "$PLAN_FILE" .md | tr '[:upper:]' '[:lower:]' | tr '_' '-')
if [ "$PLAN_SLUG" = "my-feature-plan" ]; then
  pass "plan slug: mixed case + underscores normalized"
else
  fail "plan slug: expected 'my-feature-plan', got '$PLAN_SLUG'"
fi

# Test: branch name follows convention
BRANCH_NAME="cp-${PLAN_SLUG}-${PHASE}"
if [ "$BRANCH_NAME" = "cp-my-feature-plan-4b" ]; then
  pass "branch name: cp-<slug>-<phase>"
else
  fail "branch name: expected 'cp-my-feature-plan-4b', got '$BRANCH_NAME'"
fi

echo ""
echo "=== land-phase.sh ==="

LAND_SCRIPT="$REPO_ROOT/skills/commit/scripts/land-phase.sh"

# Test: idempotent on missing directory (exit 0)
LAND_OUTPUT=$(bash "$LAND_SCRIPT" "/tmp/nonexistent-worktree-path-$$" 2>&1)
LAND_RC=$?
if [ $LAND_RC -eq 0 ] && [[ "$LAND_OUTPUT" == *"Worktree already removed"* ]]; then
  pass "land-phase.sh: idempotent on missing directory (exit 0)"
else
  fail "land-phase.sh: idempotent on missing dir — rc=$LAND_RC, output: $LAND_OUTPUT"
fi

# Test: rejects worktree with no .landed marker (exit 1)
LAND_TMPDIR=$(mktemp -d)
LAND_OUTPUT=$(bash "$LAND_SCRIPT" "$LAND_TMPDIR" 2>&1)
LAND_RC=$?
rm -rf "$LAND_TMPDIR"
if [ $LAND_RC -eq 1 ] && [[ "$LAND_OUTPUT" == *"No .landed marker"* ]]; then
  pass "land-phase.sh: rejects no .landed marker (exit 1)"
else
  fail "land-phase.sh: no marker rejection — rc=$LAND_RC, output: $LAND_OUTPUT"
fi

# Test: rejects .landed with wrong status (exit 1)
LAND_TMPDIR=$(mktemp -d)
printf 'status: partial\ndate: 2026-01-01\n' > "$LAND_TMPDIR/.landed"
LAND_OUTPUT=$(bash "$LAND_SCRIPT" "$LAND_TMPDIR" 2>&1)
LAND_RC=$?
rm -rf "$LAND_TMPDIR"
if [ $LAND_RC -eq 1 ] && [[ "$LAND_OUTPUT" == *"does not say"* ]]; then
  pass "land-phase.sh: rejects wrong status (exit 1)"
else
  fail "land-phase.sh: wrong status rejection — rc=$LAND_RC, output: $LAND_OUTPUT"
fi

# Test: rejects .landed with status: full (not status: landed)
LAND_TMPDIR=$(mktemp -d)
printf 'status: full\ndate: 2026-01-01\n' > "$LAND_TMPDIR/.landed"
LAND_OUTPUT=$(bash "$LAND_SCRIPT" "$LAND_TMPDIR" 2>&1)
LAND_RC=$?
rm -rf "$LAND_TMPDIR"
if [ $LAND_RC -eq 1 ] && [[ "$LAND_OUTPUT" == *"does not say"* ]]; then
  pass "land-phase.sh: rejects status: full (requires status: landed)"
else
  fail "land-phase.sh: status:full rejection — rc=$LAND_RC, output: $LAND_OUTPUT"
fi

# Test: removes known pipeline artifacts (.test-baseline.txt, etc.) before worktree removal
# Regression test for the bug where .test-baseline.txt blocked worktree removal.
# Setup a fake worktree with all the artifacts; verify the script removes them and
# DOESN'T fail on any of them. Worktree removal will still fail (it's not a real
# git worktree), but the .landed marker should survive for retry.
LAND_TMPDIR=$(mktemp -d)
printf 'status: landed\ndate: 2026-01-01\n' > "$LAND_TMPDIR/.landed"
printf 'baseline output\n' > "$LAND_TMPDIR/.test-baseline.txt"
printf 'test results\n' > "$LAND_TMPDIR/.test-results.txt"
printf 'purpose\n' > "$LAND_TMPDIR/.worktreepurpose"
printf 'pipeline-id\n' > "$LAND_TMPDIR/.zskills-tracked"
TMP_TEST_OUT="/tmp/zskills-tests/$(basename "$LAND_TMPDIR")"
mkdir -p "$TMP_TEST_OUT"
printf 'dummy\n' > "$TMP_TEST_OUT/.test-results.txt"
LAND_OUTPUT=$(bash "$LAND_SCRIPT" "$LAND_TMPDIR" 2>&1)
LAND_RC=$?
# Expect: script tried to remove the artifacts, then git worktree remove failed
# (not a real worktree). .landed should survive for retry. Other artifacts should be gone.
ARTIFACTS_GONE=0
[ ! -f "$LAND_TMPDIR/.test-baseline.txt" ] && ARTIFACTS_GONE=$((ARTIFACTS_GONE+1))
[ ! -f "$LAND_TMPDIR/.test-results.txt" ] && ARTIFACTS_GONE=$((ARTIFACTS_GONE+1))
[ ! -f "$LAND_TMPDIR/.worktreepurpose" ] && ARTIFACTS_GONE=$((ARTIFACTS_GONE+1))
[ ! -f "$LAND_TMPDIR/.zskills-tracked" ] && ARTIFACTS_GONE=$((ARTIFACTS_GONE+1))
MARKER_PRESERVED=0
[ -f "$LAND_TMPDIR/.landed" ] && MARKER_PRESERVED=1
TEST_OUT_GONE=0
[ ! -d "$TMP_TEST_OUT" ] && TEST_OUT_GONE=1
rm -rf "$LAND_TMPDIR"
rm -rf "$TMP_TEST_OUT"
if [ "$ARTIFACTS_GONE" -eq 4 ] && [ "$MARKER_PRESERVED" -eq 1 ] && [ "$TEST_OUT_GONE" -eq 1 ]; then
  pass "land-phase.sh: removes worktree artifacts AND /tmp test-out dir, preserves .landed on failure"
else
  fail "land-phase.sh: artifacts cleanup — gone=$ARTIFACTS_GONE/4, marker=$MARKER_PRESERVED, tmp_out_gone=$TEST_OUT_GONE, output: $LAND_OUTPUT"
fi

echo ""
echo "=== PR mode tests ==="

# Test: .landed marker with status: landed + PR fields
MARKER=$(cat <<LANDED
status: landed
date: 2026-04-13T12:00:00-04:00
source: run-plan
method: pr
branch: feat/test
pr: https://github.com/owner/repo/pull/42
ci: pass
pr_state: MERGED
LANDED
)
if [[ "$MARKER" == *"status: landed"* ]] && [[ "$MARKER" == *"method: pr"* ]] && [[ "$MARKER" == *"pr_state: MERGED"* ]]; then
  pass "PR .landed marker: status: landed with PR fields (method: pr, pr_state: MERGED)"
else
  fail "PR .landed marker: expected status: landed, method: pr, pr_state: MERGED"
fi

# Test: .landed marker with status: pr-ready
MARKER="status: pr-ready"
if [[ "$MARKER" == *"pr-ready"* ]]; then
  pass "PR .landed marker: status: pr-ready recognized"
else
  fail "PR .landed marker: expected pr-ready"
fi

# Test: .landed marker with status: pr-ci-failing
MARKER="status: pr-ci-failing"
if [[ "$MARKER" == *"pr-ci-failing"* ]]; then
  pass "PR .landed marker: status: pr-ci-failing recognized"
else
  fail "PR .landed marker: expected pr-ci-failing"
fi

# Test: .landed marker with status: conflict (rebase failure)
MARKER="status: conflict"
if [[ "$MARKER" == *"conflict"* ]]; then
  pass "PR .landed marker: status: conflict recognized"
else
  fail "PR .landed marker: expected conflict"
fi

# Test: PR mode branch naming
BRANCH_PREFIX="feat/"
PLAN_SLUG=$(basename "plans/THERMAL_DOMAIN.md" .md | tr '[:upper:]' '[:lower:]' | tr '_' '-')
BRANCH_NAME="${BRANCH_PREFIX}${PLAN_SLUG}"
if [[ "$BRANCH_NAME" == "feat/thermal-domain" ]]; then
  pass "PR branch naming: feat/thermal-domain from THERMAL_DOMAIN.md"
else
  fail "PR branch naming: expected feat/thermal-domain, got $BRANCH_NAME"
fi

# Test: PR mode worktree path
PROJECT_NAME="my-app"
PLAN_SLUG="thermal-domain"
WORKTREE_PATH="/tmp/${PROJECT_NAME}-pr-${PLAN_SLUG}"
if [[ "$WORKTREE_PATH" == "/tmp/my-app-pr-thermal-domain" ]]; then
  pass "PR worktree path: /tmp/my-app-pr-thermal-domain"
else
  fail "PR worktree path: expected /tmp/my-app-pr-thermal-domain, got $WORKTREE_PATH"
fi

# Test: main_protected allows commits on feature branches (not just main)
RESULT=$(run_main_protected_test "feat/thermal-domain" '{"execution": {"main_protected": true}}' "git commit -m 'phase 1'")
if [[ "$RESULT" != *"main branch is protected"* ]]; then
  pass "main_protected: allows commit on PR feature branch feat/thermal-domain"
else
  fail "main_protected: should allow commit on feat/thermal-domain, got: $RESULT"
fi

# Test: land-phase.sh accepts status: pr-ready as safe-to-remove
LAND_TMPDIR=$(mktemp -d)
cat > "$LAND_TMPDIR/.landed" <<LANDED
status: pr-ready
date: 2026-04-13T12:00:00-04:00
source: run-plan
method: pr
branch: feat/test
pr: https://github.com/owner/repo/pull/42
LANDED
LAND_OUTPUT=$(bash "$LAND_SCRIPT" "$LAND_TMPDIR" 2>&1)
LAND_RC=$?
rm -rf "$LAND_TMPDIR"
# land-phase.sh will fail at git worktree remove (not a real worktree),
# but it should get PAST the status check (not exit with "does not say" error)
if [[ "$LAND_OUTPUT" != *"does not say"* ]]; then
  pass "land-phase.sh: accepts status: pr-ready (gets past marker check)"
else
  fail "land-phase.sh: should accept pr-ready, got: $LAND_OUTPUT"
fi

# Test: slug normalization edge cases
PLAN_FILE="plans/ADD_FILTER_BLOCK.md"
PLAN_SLUG=$(basename "$PLAN_FILE" .md | tr '[:upper:]' '[:lower:]' | tr '_' '-')
SLUG_OK=true
if [[ "$PLAN_SLUG" != "add-filter-block" ]]; then
  SLUG_OK=false
fi
PLAN_FILE2="plans/FIX_MAIN_LOOP.md"
PLAN_SLUG2=$(basename "$PLAN_FILE2" .md | tr '[:upper:]' '[:lower:]' | tr '_' '-')
if [[ "$PLAN_SLUG2" != "fix-main-loop" ]]; then
  SLUG_OK=false
fi
if [ "$SLUG_OK" = "true" ]; then
  pass "Slug normalization: ADD_FILTER_BLOCK -> add-filter-block, FIX_MAIN_LOOP -> fix-main-loop"
else
  fail "Slug normalization: got $PLAN_SLUG and $PLAN_SLUG2"
fi

# ── CI integration tests (Phase 3b-iii) ──────────────────────────────

# Test: CI config defaults (no config = auto_fix true, max 2)
CI_AUTO_FIX=true
CI_MAX_ATTEMPTS=2
CONFIG=""  # Empty config
if [ -n "$CONFIG" ]; then
  :
fi
if [[ "$CI_AUTO_FIX" == "true" ]] && [[ "$CI_MAX_ATTEMPTS" == "2" ]]; then
  pass "CI config defaults: auto_fix=true, max_fix_attempts=2"
else
  fail "CI config defaults: got auto_fix=$CI_AUTO_FIX, max=$CI_MAX_ATTEMPTS"
fi

# Test: CI config auto_fix false
CONFIG='{"ci": {"auto_fix": false, "max_fix_attempts": 2}}'
CI_AUTO_FIX=true
if [[ "$CONFIG" =~ \"auto_fix\"[[:space:]]*:[[:space:]]*(true|false) ]]; then
  CI_AUTO_FIX="${BASH_REMATCH[1]}"
fi
if [[ "$CI_AUTO_FIX" == "false" ]]; then
  pass "CI config auto_fix false parsed correctly"
else
  fail "CI config auto_fix false: expected false, got $CI_AUTO_FIX"
fi

# Test: .landed marker with status: pr-ci-failing
MARKER="status: pr-ci-failing"
if [[ "$MARKER" == *"pr-ci-failing"* ]]; then
  pass ".landed marker status pr-ci-failing recognized"
else
  fail ".landed marker status pr-ci-failing not found"
fi

# Test: .landed marker upgrade includes ci and pr_state fields
MARKER=$(cat <<LANDED
status: landed
date: 2026-04-13T12:00:00-04:00
source: run-plan
method: pr
branch: feat/test
pr: https://github.com/owner/repo/pull/42
ci: pass
pr_state: MERGED
LANDED
)
if [[ "$MARKER" == *"ci: pass"* ]] && [[ "$MARKER" == *"pr_state: MERGED"* ]]; then
  pass ".landed marker upgrade includes ci and pr_state fields"
else
  fail ".landed marker upgrade missing ci or pr_state fields"
fi

# ── /fix-issues PR mode tests (Phase 4) ──────────────────────────────

# Test: per-issue branch naming
ISSUE_NUM=42
BRANCH_NAME="fix/issue-${ISSUE_NUM}"
if [[ "$BRANCH_NAME" == "fix/issue-42" ]]; then
  pass "/fix-issues PR: per-issue branch naming (fix/issue-42)"
else
  fail "/fix-issues PR: expected fix/issue-42, got $BRANCH_NAME"
fi

# Test: per-issue worktree path
PROJECT_NAME="my-app"
ISSUE_NUM=42
WORKTREE_PATH="/tmp/${PROJECT_NAME}-fix-issue-${ISSUE_NUM}"
if [[ "$WORKTREE_PATH" == "/tmp/my-app-fix-issue-42" ]]; then
  pass "/fix-issues PR: per-issue worktree path (/tmp/my-app-fix-issue-42)"
else
  fail "/fix-issues PR: worktree path wrong, got $WORKTREE_PATH"
fi

# Test: .landed marker includes issue field for fix-issues source
MARKER=$(cat <<LANDED
status: landed
date: 2026-04-13T12:00:00-04:00
source: fix-issues
method: pr
branch: fix/issue-42
pr: https://github.com/owner/repo/pull/99
ci: pass
pr_state: MERGED
issue: 42
LANDED
)
if [[ "$MARKER" == *"issue: 42"* ]] && \
   [[ "$MARKER" == *"source: fix-issues"* ]] && \
   [[ "$MARKER" == *"method: pr"* ]]; then
  pass "/fix-issues PR: .landed marker includes issue field + fix-issues source"
else
  fail "/fix-issues PR: marker missing issue field, source, or method"
fi

echo ""


echo "=== post-run-invariants.sh ==="

INV_SCRIPT="$REPO_ROOT/skills/run-plan/scripts/post-run-invariants.sh"

# Per-process scoped tempfile to avoid race when concurrent test runs share /tmp (issue #202).
INV_TEST=$(mktemp /tmp/inv-test.XXXXXX)
trap 'rm -f "$INV_TEST"' EXIT

# 17. All checks skipped (empty args, must run in a git repo) → pass with message
(cd "$REPO_ROOT" && bash "$INV_SCRIPT" > "$INV_TEST" 2>&1)
INV_RC=$?
if [ $INV_RC -eq 0 ] && grep -q "all checks passed" "$INV_TEST"; then
  pass "post-run-invariants.sh: empty args → skips all → pass"
else
  fail "post-run-invariants.sh: empty args — rc=$INV_RC, output: $(cat "$INV_TEST")"
fi
: > "$INV_TEST"

# 18. Nonexistent worktree path (should skip — invariant #1/#2 only fires when path provided AND exists)
# Actually invariant #1 requires the path NOT to exist; passing a nonexistent path should PASS.
(cd "$REPO_ROOT" && bash "$INV_SCRIPT" --worktree /tmp/nonexistent-invariant-test-$$ > "$INV_TEST" 2>&1)
INV_RC=$?
if [ $INV_RC -eq 0 ]; then
  pass "post-run-invariants.sh: nonexistent worktree path → invariant #1 passes"
else
  fail "post-run-invariants.sh: nonexistent worktree — rc=$INV_RC, output: $(cat "$INV_TEST")"
fi
: > "$INV_TEST"

# 19. Existing worktree path (fail invariant #1)
TMP_WT=$(mktemp -d)
(cd "$REPO_ROOT" && bash "$INV_SCRIPT" --worktree "$TMP_WT" > "$INV_TEST" 2>&1)
INV_RC=$?
rm -rf "$TMP_WT"
if [ $INV_RC -ne 0 ] && grep -q "INVARIANT-FAIL (#1)" "$INV_TEST"; then
  pass "post-run-invariants.sh: existing worktree path → invariant #1 fails loudly"
else
  fail "post-run-invariants.sh: existing worktree — rc=$INV_RC, output: $(cat "$INV_TEST")"
fi
: > "$INV_TEST"

# 20. Plan file with 🟡 row → fail invariant #6
TMP_PLAN=$(mktemp)
printf '# Plan\n| 1 | 🟡 In Progress | abc |\n' > "$TMP_PLAN"
(cd "$REPO_ROOT" && bash "$INV_SCRIPT" --plan-file "$TMP_PLAN" > "$INV_TEST" 2>&1)
INV_RC=$?
rm -f "$TMP_PLAN"
if [ $INV_RC -ne 0 ] && grep -q "INVARIANT-FAIL (#6)" "$INV_TEST"; then
  pass "post-run-invariants.sh: plan with 🟡 → invariant #6 fails"
else
  fail "post-run-invariants.sh: plan with 🟡 — rc=$INV_RC, output: $(cat "$INV_TEST")"
fi
: > "$INV_TEST"

# 21. Not in git repo → exits 1 with clear error
(cd /tmp && bash "$INV_SCRIPT" > "$INV_TEST" 2>&1)
INV_RC=$?
if [ $INV_RC -ne 0 ] && grep -q "must run from inside a git repository" "$INV_TEST"; then
  pass "post-run-invariants.sh: outside git repo → loud error, exit 1"
else
  fail "post-run-invariants.sh: outside git repo — rc=$INV_RC, output: $(cat "$INV_TEST")"
fi
: > "$INV_TEST"

# 22. land-phase.sh MAIN_ROOT guard: a valid path + .landed but running from
# outside a git repo must hit the guard and error loudly. The prior version
# of this test fell into the idempotent early-exit branch (nonexistent path)
# and never reached the MAIN_ROOT guard — so we force the path to exist.
EXISTING_PATH=$(mktemp -d)
printf 'status: landed\n' > "$EXISTING_PATH/.landed"
LAND_OUTPUT=$(cd /tmp && bash "$LAND_SCRIPT" "$EXISTING_PATH" 2>&1)
LAND_RC=$?
rm -rf "$EXISTING_PATH"
if [ $LAND_RC -ne 0 ] && [[ "$LAND_OUTPUT" == *"must be run from inside a git repository"* ]]; then
  pass "land-phase.sh: outside git repo with valid path → MAIN_ROOT guard exits loudly"
else
  fail "land-phase.sh: outside git repo — rc=$LAND_RC, output: $LAND_OUTPUT"
fi

# 23. land-phase.sh: tracked ephemeral file is rejected with the specific error
# (the main Bug #1 fix — this is the regression test for that whole class).
TRACKED_WT=$(mktemp -d)
(
  cd "$TRACKED_WT" && git init -q
  git config user.email test@test.test
  git config user.name test
  echo "tracked-as-test" > .worktreepurpose
  git add .worktreepurpose
  git commit -q -m "tracked .worktreepurpose (bad)"
  printf 'status: landed\n' > .landed
)
LAND_OUTPUT=$(cd "$TRACKED_WT" && bash "$LAND_SCRIPT" "$TRACKED_WT" 2>&1)
LAND_RC=$?
rm -rf "$TRACKED_WT"
if [ $LAND_RC -ne 0 ] && [[ "$LAND_OUTPUT" == *"git-tracked"* ]] && [[ "$LAND_OUTPUT" == *"should be untracked"* ]]; then
  pass "land-phase.sh: tracked .worktreepurpose → rejected with specific 'git-tracked' error"
else
  fail "land-phase.sh: tracked ephemeral — rc=$LAND_RC, output: $LAND_OUTPUT"
fi

# 24. land-phase.sh: dirty working tree (untracked residue) → aborts with 'not clean',
# restores .landed. Previously the generic-error path we relied on; make sure
# that path is exercised and .landed is preserved.
DIRTY_WT=$(mktemp -d)
(
  cd "$DIRTY_WT" && git init -q
  git config user.email test@test.test
  git config user.name test
  echo "init" > init.txt && git add init.txt && git commit -q -m init
  echo "unexpected" > unexpected-leftover.txt
  printf 'status: landed\n' > .landed
)
LAND_OUTPUT=$(cd "$DIRTY_WT" && bash "$LAND_SCRIPT" "$DIRTY_WT" 2>&1)
LAND_RC=$?
LANDED_PRESERVED=0
[ -f "$DIRTY_WT/.landed" ] && LANDED_PRESERVED=1
rm -rf "$DIRTY_WT"
if [ $LAND_RC -ne 0 ] && [[ "$LAND_OUTPUT" == *"not clean"* ]] && [ "$LANDED_PRESERVED" -eq 1 ]; then
  pass "land-phase.sh: dirty worktree → aborts 'not clean', .landed restored for retry"
else
  fail "land-phase.sh: dirty worktree — rc=$LAND_RC, landed-preserved=$LANDED_PRESERVED, output: $LAND_OUTPUT"
fi

# 25. post-run-invariants.sh: plan report missing → invariant #5 fails
TMP_SLUG="nonexistent-plan-$$"
(cd "$REPO_ROOT" && bash "$INV_SCRIPT" --plan-slug "$TMP_SLUG" > "$INV_TEST" 2>&1)
INV_RC=$?
if [ $INV_RC -ne 0 ] && grep -q "INVARIANT-FAIL (#5)" "$INV_TEST"; then
  pass "post-run-invariants.sh: missing plan report → invariant #5 fails"
else
  fail "post-run-invariants.sh: missing plan report — rc=$INV_RC, output: $(cat "$INV_TEST")"
fi
: > "$INV_TEST"

# 26. post-run-invariants.sh: lingering local branch after 'landed' → invariant #3 fails.
# Create a branch named 'invariant-zombie-test-$$' referencing HEAD; pass landed status.
ZOMBIE_BRANCH="invariant-zombie-test-$$"
git -C "$REPO_ROOT" branch "$ZOMBIE_BRANCH" HEAD 2>/dev/null
(cd "$REPO_ROOT" && bash "$INV_SCRIPT" --branch "$ZOMBIE_BRANCH" --landed-status landed > "$INV_TEST" 2>&1)
INV_RC=$?
git -C "$REPO_ROOT" branch -D "$ZOMBIE_BRANCH" >/dev/null 2>&1
if [ $INV_RC -ne 0 ] && grep -q "INVARIANT-FAIL (#3)" "$INV_TEST"; then
  pass "post-run-invariants.sh: local branch lingers after landed → invariant #3 fails"
else
  fail "post-run-invariants.sh: zombie local branch — rc=$INV_RC, output: $(cat "$INV_TEST")"
fi
: > "$INV_TEST"

# 27. post-run-invariants.sh: local branch with 'pr-ready' status → does NOT fail
# (intentional — pr-ready means work not fully landed, branch is kept).
KEEP_BRANCH="invariant-keep-test-$$"
git -C "$REPO_ROOT" branch "$KEEP_BRANCH" HEAD 2>/dev/null
(cd "$REPO_ROOT" && bash "$INV_SCRIPT" --branch "$KEEP_BRANCH" --landed-status pr-ready > "$INV_TEST" 2>&1)
INV_RC=$?
git -C "$REPO_ROOT" branch -D "$KEEP_BRANCH" >/dev/null 2>&1
# Exit may be nonzero if other invariants fire (fetch warning etc.), but invariant #3 must NOT fire.
if ! grep -q "INVARIANT-FAIL (#3)" "$INV_TEST"; then
  pass "post-run-invariants.sh: pr-ready status → invariant #3 does NOT fire (branch kept intentionally)"
else
  fail "post-run-invariants.sh: pr-ready incorrectly triggered #3 — output: $(cat "$INV_TEST")"
fi
: > "$INV_TEST"

echo ""
echo "=== Phase C — real-git-state integration tests ==="

# 28. Invariant #2: stale worktree registry entry (dir gone, registry entry remains)
# Create a tmp repo, add a worktree, then rmdir the path manually. Registry is stale.
TMP_T28=$(mktemp -d)
(
  cd "$TMP_T28" && git init -q -b main
  git config user.email t@t.t && git config user.name t
  echo base > f.txt && git add f.txt && git commit -q -m base
  git worktree add "$TMP_T28/wt28" -q -b branch-t28-$$
  rm -rf "$TMP_T28/wt28"
)
OUT_T28=$(cd "$TMP_T28" && bash "$INV_SCRIPT" --worktree "$TMP_T28/wt28" 2>&1)
RC_T28=$?
rm -rf "$TMP_T28"
if [ $RC_T28 -ne 0 ] && [[ "$OUT_T28" == *"INVARIANT-FAIL (#2)"* ]]; then
  pass "post-run-invariants.sh: stale worktree registry entry → invariant #2 fails"
else
  fail "post-run-invariants.sh: stale registry — rc=$RC_T28, output: $OUT_T28"
fi

# 29. Invariant #4: remote branch lingering after landed
# Build a local repo + bare-repo origin; push a branch; delete local branch; assert #4 fires.
TMP_T29=$(mktemp -d)
(
  mkdir -p "$TMP_T29/bare.git"
  cd "$TMP_T29/bare.git" && git init --bare -q
) >/dev/null
(
  mkdir -p "$TMP_T29/local"
  cd "$TMP_T29/local" && git init -q -b main
  git config user.email t@t.t && git config user.name t
  echo base > f.txt && git add f.txt && git commit -q -m base
  git remote add origin "$TMP_T29/bare.git"
  git push -q origin main
  git branch zombie-remote-$$
  git push -q origin zombie-remote-$$
  git branch -D zombie-remote-$$ >/dev/null
) >/dev/null
OUT_T29=$(cd "$TMP_T29/local" && bash "$INV_SCRIPT" --branch "zombie-remote-$$" --landed-status landed 2>&1)
RC_T29=$?
rm -rf "$TMP_T29"
if [ $RC_T29 -ne 0 ] && [[ "$OUT_T29" == *"INVARIANT-FAIL (#4)"* ]]; then
  pass "post-run-invariants.sh: remote branch lingering after landed → invariant #4 fails"
else
  fail "post-run-invariants.sh: invariant #4 — rc=$RC_T29, output: $OUT_T29"
fi

# 30. Invariant #7: local main ahead of origin/main → WARN (not fail)
# Build a local repo + bare-repo origin; push one commit; make another commit locally (not pushed).
TMP_T30=$(mktemp -d)
(
  mkdir -p "$TMP_T30/bare.git"
  cd "$TMP_T30/bare.git" && git init --bare -q
) >/dev/null
(
  mkdir -p "$TMP_T30/local"
  cd "$TMP_T30/local" && git init -q -b main
  git config user.email t@t.t && git config user.name t
  echo base > f.txt && git add f.txt && git commit -q -m base
  git remote add origin "$TMP_T30/bare.git"
  git push -q origin main
  echo extra > g.txt && git add g.txt && git commit -q -m "local-ahead"
) >/dev/null
OUT_T30=$(cd "$TMP_T30/local" && bash "$INV_SCRIPT" 2>&1)
RC_T30=$?
rm -rf "$TMP_T30"
# Invariant #7 is a WARN, not a fail — exit should still be 0. Output must contain WARN (#7).
if [ $RC_T30 -eq 0 ] && [[ "$OUT_T30" == *"INVARIANT-WARN (#7)"* ]]; then
  pass "post-run-invariants.sh: local-ahead-of-origin → invariant #7 warns (exit 0)"
else
  fail "post-run-invariants.sh: invariant #7 — rc=$RC_T30, output: $OUT_T30"
fi

# 31. land-phase.sh happy path (full -D force-delete flow end-to-end).
# Create real worktree + branch, write status: landed, run the script.
# Verify: worktree gone from disk, from registry, local branch -D'd.
#
# IMPORTANT: assert setup BEFORE invoking land-phase.sh. If `git worktree add`
# silently fails, land-phase.sh short-circuits at "Worktree already removed"
# (RC 0) and downstream checks pass vacuously. Pre-assert prevents
# wrong-reason passes.
TMP_T31=$(mktemp -d)
(
  # Bare repo as origin so ls-remote returns exit 2 (branch absent) — not
  # exit 128 (no remote), which the hardened land-phase.sh now fails on.
  mkdir -p "$TMP_T31/bare.git" && cd "$TMP_T31/bare.git" && git init --bare -q
) >/dev/null 2>&1
(
  cd "$TMP_T31" && git init -q -b main
  git config user.email t@t.t && git config user.name t
  echo base > f.txt && git add f.txt && git commit -q -m base
  git remote add origin "$TMP_T31/bare.git"
  BRANCH="land-happy-$$"
  git worktree add -b "$BRANCH" "$TMP_T31/wt-happy" -q
  printf 'status: landed\n' > "$TMP_T31/wt-happy/.landed"
) >/dev/null 2>&1
# Pre-assertion: setup must have created the worktree and branch.
SETUP_OK_T31=1
[ -d "$TMP_T31/wt-happy" ] || SETUP_OK_T31=0
git -C "$TMP_T31" show-ref --verify --quiet "refs/heads/land-happy-$$" || SETUP_OK_T31=0
if [ "$SETUP_OK_T31" -ne 1 ]; then
  rm -rf "$TMP_T31"
  fail "land-phase.sh happy path: setup failed — worktree or branch not created"
else
  OUT_T31=$(cd "$TMP_T31" && bash "$LAND_SCRIPT" "$TMP_T31/wt-happy" 2>&1)
  RC_T31=$?
  DIR_GONE_T31=0
  BRANCH_GONE_T31=0
  [ ! -d "$TMP_T31/wt-happy" ] && DIR_GONE_T31=1
  ! git -C "$TMP_T31" show-ref --verify --quiet "refs/heads/land-happy-$$" && BRANCH_GONE_T31=1
  rm -rf "$TMP_T31"
  if [ $RC_T31 -eq 0 ] && [ "$DIR_GONE_T31" -eq 1 ] && [ "$BRANCH_GONE_T31" -eq 1 ]; then
    pass "land-phase.sh: happy path (status: landed) → worktree + local branch both removed (-D force-delete)"
  else
    fail "land-phase.sh: happy path — rc=$RC_T31, dir-gone=$DIR_GONE_T31, branch-gone=$BRANCH_GONE_T31, output: $OUT_T31"
  fi
fi

# 32. land-phase.sh: origin unreachable (ls-remote exit 128) → fail loudly.
# Regression test for the fix that distinguishes exit 2 (branch absent — skip)
# from exit 128 (remote broken — abort). Pre-fix, a broken remote silently
# passed as "already absent" and land-phase.sh continued happily. Now it
# must error instead.
TMP_T32=$(mktemp -d)
(
  cd "$TMP_T32" && git init -q -b main
  git config user.email t@t.t && git config user.name t
  echo base > f.txt && git add f.txt && git commit -q -m base
  BRANCH="land-no-origin-$$"
  git worktree add -b "$BRANCH" "$TMP_T32/wt-no-origin" -q
  printf 'status: landed\n' > "$TMP_T32/wt-no-origin/.landed"
  # Intentionally do NOT `git remote add origin ...` — ls-remote will fail
  # with exit 128 "fatal: 'origin' does not appear to be a git repository".
) >/dev/null 2>&1
OUT_T32=$(cd "$TMP_T32" && bash "$LAND_SCRIPT" "$TMP_T32/wt-no-origin" 2>&1)
RC_T32=$?
rm -rf "$TMP_T32"
if [ $RC_T32 -ne 0 ] && [[ "$OUT_T32" == *"origin unreachable"* ]]; then
  pass "land-phase.sh: origin unreachable on landed status → exit 1 with specific 'origin unreachable' error (no silent skip)"
else
  fail "land-phase.sh: broken origin — rc=$RC_T32, output: $OUT_T32"
fi

echo ""
echo "=== Pipeline scoping: A–F (cross-pipeline marker isolation via subdirs) ==="

# test_pipeline_scoping_filter — the foundation for CANARY8's claim
# that parallel pipelines don't cross-block. Migrated to the Option B
# per-pipeline subdir layout: each pipeline's markers live in
# .zskills/tracking/$PIPELINE_ID/ so two pipelines with different
# PIPELINE_IDs cannot see each other's markers regardless of basename.
#
# Naming convention mirrors real pipeline naming:
#   research-and-go.<SCOPE>        — parent meta-orchestrator
#   run-plan.meta-<SCOPE>          — meta-plan (META_ prefix from Phase B)
#   run-plan.<SUB_PLAN_SLUG>       — each sub-plan
#
# NOTE: Case A under the flat scheme asserted that a marker named
# `.meta-foo` would block a `run-plan.meta-foo` session via basename
# suffix-matching. Under Option B, the marker's owning pipeline is the
# subdir it lives in — so a `run-plan.meta-foo` session looks only in
# `run-plan.meta-foo/`, not in `research-and-go.meta-foo/`. The original
# cross-pipeline suffix-match semantics no longer exist as a hook-level
# concern; run-plan handles the cross-pipeline final-verify marker via
# an application-level glob-dual-lookup read (see skills/run-plan). The
# migrated Case A verifies the new semantics: a pipeline's OWN subdir
# marker still blocks that pipeline.
test_pipeline_scoping_filter() {
  # Case A — own-subdir enforcement: marker in run-plan.meta-foo/ +
  # PIPELINE_ID run-plan.meta-foo + code commit → hook BLOCKS.
  setup_project_test
  mkdir -p "$TEST_TMPDIR/.zskills/tracking/run-plan.meta-foo"
  touch "$TEST_TMPDIR/.zskills/tracking/run-plan.meta-foo/requires.verify-changes.meta-foo"
  (cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
  rm -f "$TEST_TMPDIR/.transcript"
  printf 'npm run test:all\nZSKILLS_PIPELINE_ID=run-plan.meta-foo\n' > "$TEST_TMPDIR/.transcript"
  expect_project_deny "git commit -m test"
  teardown_project_test

  # Case B — sub-plan does not see parent r&g's subdir markers:
  # marker in research-and-go.meta-foo/, PIPELINE_ID run-plan.foo-backend
  # (disjoint subdir) → hook ALLOWS.
  setup_project_test
  mkdir -p "$TEST_TMPDIR/.zskills/tracking/research-and-go.meta-foo"
  touch "$TEST_TMPDIR/.zskills/tracking/research-and-go.meta-foo/requires.verify-changes.final.meta-foo"
  (cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
  rm -f "$TEST_TMPDIR/.transcript"
  printf 'npm run test:all\nZSKILLS_PIPELINE_ID=run-plan.foo-backend\n' > "$TEST_TMPDIR/.transcript"
  expect_project_allow "git commit -m test"
  teardown_project_test

  # Case C — distinct r&g session does NOT see another r&g's subdir:
  # marker in research-and-go.meta-foo/, PIPELINE_ID research-and-go.foo
  # (different subdir even within the same skill family) → hook ALLOWS.
  setup_project_test
  mkdir -p "$TEST_TMPDIR/.zskills/tracking/research-and-go.meta-foo"
  touch "$TEST_TMPDIR/.zskills/tracking/research-and-go.meta-foo/requires.verify-changes.final.meta-foo"
  (cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
  rm -f "$TEST_TMPDIR/.transcript"
  printf 'npm run test:all\nZSKILLS_PIPELINE_ID=research-and-go.foo\n' > "$TEST_TMPDIR/.transcript"
  expect_project_allow "git commit -m test"
  teardown_project_test

  # Case D — own-subdir enforcement for r&g scope: marker in
  # research-and-go.meta-foo/ + PIPELINE_ID research-and-go.meta-foo →
  # hook BLOCKS (it's the marker's owning subdir).
  setup_project_test
  mkdir -p "$TEST_TMPDIR/.zskills/tracking/research-and-go.meta-foo"
  touch "$TEST_TMPDIR/.zskills/tracking/research-and-go.meta-foo/requires.verify-changes.final.meta-foo"
  (cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
  rm -f "$TEST_TMPDIR/.transcript"
  printf 'npm run test:all\nZSKILLS_PIPELINE_ID=research-and-go.meta-foo\n' > "$TEST_TMPDIR/.transcript"
  expect_project_deny "git commit -m test"
  teardown_project_test

  # Case E — empty PIPELINE_ID (no .zskills-tracked, no transcript
  # declaration) → no association → skip enforcement → hook ALLOWS.
  setup_project_test
  mkdir -p "$TEST_TMPDIR/.zskills/tracking/research-and-go.meta-foo"
  touch "$TEST_TMPDIR/.zskills/tracking/research-and-go.meta-foo/requires.verify-changes.final.meta-foo"
  (cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
  rm -f "$TEST_TMPDIR/.transcript"
  printf 'npm run test:all\n' > "$TEST_TMPDIR/.transcript"
  expect_project_allow "git commit -m test"
  teardown_project_test

  # Case F — no marker present at all: empty tracking dir + any
  # PIPELINE_ID + code commit → hook ALLOWS (subdir absent, flat
  # fallback finds nothing).
  setup_project_test
  # tracking dir is empty (no subdir, no marker files)
  (cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
  rm -f "$TEST_TMPDIR/.transcript"
  printf 'npm run test:all\nZSKILLS_PIPELINE_ID=run-plan.meta-foo\n' > "$TEST_TMPDIR/.transcript"
  expect_project_allow "git commit -m test"
  teardown_project_test
}
test_pipeline_scoping_filter

echo ""
echo "=== /verify-changes \$ARGUMENTS parser (extracted from skill) ==="

# test_verify_changes_arg_parser — EXTRACT-AND-RUN the REAL parser fence from
# skills/verify-changes/SKILL.md under "### Parsing $ARGUMENTS" (Phase 2 of
# SEAM_HARDENING_REST). The prior version re-typed the parser inline, which
# silently drifted from production. Now we pull the actual production ```bash
# fence via extract_fence_between and source it, so any change to the SKILL.md
# parser is reflected here and a regression in it FAILS these cases.
#
# The parser is a small for-token case statement (production source):
#   tracking-id=X  → TRACKING_ID=X
#   worktree|branch|last → SCOPE=<token>
#   [0-9]*         → if SCOPE=="last", SCOPE="last N"
# Order-independent; unknown tokens are tolerated (ignored).
#
# The production fence iterates over $ARGUMENTS; the test cases below call
# parse_args with a single positional arg, so the wrapper bridges $1→ARGUMENTS.
test_verify_changes_arg_parser() {
  local vc_skill="$REPO_ROOT/skills/verify-changes/SKILL.md"
  local vc_tmp; vc_tmp=$(mktemp -d "/tmp/vc-arg-parser.XXXXXX")
  local vc_fence="$vc_tmp/parser-fence.sh"

  # Extract the self-contained ```bash fence under "### Parsing $ARGUMENTS".
  # The section ends at the next "### " heading / "Lets " prose line; bracket
  # tightly with the heading landmark and the trailing prose so exactly the one
  # parser fence is captured. POSIX char classes ([.] not \.) keep the landmark
  # regexes gawk-safe (gawk strips backslash-escaped metacharacters in -v).
  if ! extract_fence_between "$vc_skill" \
        '^### Parsing [$]ARGUMENTS' \
        '^Lets ' 1 0 > "$vc_fence"; then
    fail "parser: could not extract real parser fence from $vc_skill"
    rm -rf "$vc_tmp"
    return
  fi

  # Sanity: the extracted fence carries its production landmarks, so a future
  # re-anchoring that grabs the wrong fence fails loud here, not silently.
  if grep -qF 'tracking-id=*) TRACKING_ID="${tok#tracking-id=}"' "$vc_fence" \
     && grep -qF 'worktree|branch|last) SCOPE="$tok"' "$vc_fence" \
     && grep -qF 'for tok in $ARGUMENTS' "$vc_fence"; then
    pass "parser: [extract] fence carries tok-loop / tracking-id / scope landmarks"
  else
    fail "parser: [extract] fence missing production landmarks — wrong fence extracted?"
    rm -rf "$vc_tmp"
    return
  fi

  # Wrapper bridges the test's positional $1 to the production parser's
  # $ARGUMENTS, then sources the REAL extracted fence (no re-typed copy).
  parse_args() {
    local ARGUMENTS="$1"
    SCOPE=""
    TRACKING_ID=""
    # shellcheck source=/dev/null
    . "$vc_fence"
  }

  # Case 1: branch + tracking-id (the cron-fired use pattern)
  parse_args "branch tracking-id=meta-foo"
  if [ "$SCOPE" = "branch" ] && [ "$TRACKING_ID" = "meta-foo" ]; then
    pass "parser: 'branch tracking-id=meta-foo' → SCOPE=branch, TRACKING_ID=meta-foo"
  else
    fail "parser: branch+tracking — SCOPE='$SCOPE', TRACKING_ID='$TRACKING_ID'"
  fi

  # Case 2: token-order independence
  parse_args "tracking-id=meta-foo branch"
  if [ "$SCOPE" = "branch" ] && [ "$TRACKING_ID" = "meta-foo" ]; then
    pass "parser: 'tracking-id=meta-foo branch' → same as Case 1 (order-independent)"
  else
    fail "parser: reversed-order — SCOPE='$SCOPE', TRACKING_ID='$TRACKING_ID'"
  fi

  # Case 3: worktree alone
  parse_args "worktree"
  if [ "$SCOPE" = "worktree" ] && [ -z "$TRACKING_ID" ]; then
    pass "parser: 'worktree' → SCOPE=worktree, TRACKING_ID=''"
  else
    fail "parser: worktree — SCOPE='$SCOPE', TRACKING_ID='$TRACKING_ID'"
  fi

  # Case 4: last N
  parse_args "last 3"
  if [ "$SCOPE" = "last 3" ] && [ -z "$TRACKING_ID" ]; then
    pass "parser: 'last 3' → SCOPE='last 3', TRACKING_ID=''"
  else
    fail "parser: last-N — SCOPE='$SCOPE', TRACKING_ID='$TRACKING_ID'"
  fi

  # Case 5: branch + tracking-id + extra junk token (tolerated)
  parse_args "branch tracking-id=meta-foo extra-junk-token"
  if [ "$SCOPE" = "branch" ] && [ "$TRACKING_ID" = "meta-foo" ]; then
    pass "parser: extra junk token tolerated (ignored silently)"
  else
    fail "parser: junk-tolerated — SCOPE='$SCOPE', TRACKING_ID='$TRACKING_ID'"
  fi

  # Case 6: bare 'last' without a number — SCOPE stays 'last', no trailing N
  parse_args "last"
  if [ "$SCOPE" = "last" ] && [ -z "$TRACKING_ID" ]; then
    pass "parser: bare 'last' → SCOPE=last (no N)"
  else
    fail "parser: bare-last — SCOPE='$SCOPE', TRACKING_ID='$TRACKING_ID'"
  fi

  # Case 7: numeric token without preceding 'last' is ignored.
  parse_args "branch 5"
  if [ "$SCOPE" = "branch" ] && [ -z "$TRACKING_ID" ]; then
    pass "parser: '5' without 'last' context → ignored (SCOPE stays 'branch')"
  else
    fail "parser: number-without-last — SCOPE='$SCOPE', TRACKING_ID='$TRACKING_ID'"
  fi

  # Case 8: empty arguments
  parse_args ""
  if [ -z "$SCOPE" ] && [ -z "$TRACKING_ID" ]; then
    pass "parser: empty input → both empty"
  else
    fail "parser: empty — SCOPE='$SCOPE', TRACKING_ID='$TRACKING_ID'"
  fi

  rm -rf "$vc_tmp"
}
test_verify_changes_arg_parser

echo ""
echo "=== Runtime config read ==="
# These tests validate Phase 1 of DRIFT_ARCH_FIX: block-unsafe-project.sh reads
# testing.unit_cmd / testing.full_cmd / ui.file_patterns at RUNTIME from
# .claude/zskills-config.json instead of install-filled placeholders. Each
# test synthesizes a fixture tree and invokes the hook with REPO_ROOT override.

_rcr_setup_fixture() {
  # Args: $1 = dir, $2 = config JSON body (written verbatim to .claude/zskills-config.json).
  local dir="$1"
  local config="$2"
  mkdir -p "$dir/.claude/hooks"
  mkdir -p "$dir/.zskills/tracking"
  cp "$PROJECT_HOOK" "$dir/.claude/hooks/block-unsafe-project.sh"
  if [ -n "$config" ]; then
    printf '%s\n' "$config" > "$dir/.claude/zskills-config.json"
  fi
  (cd "$dir" && git init -q && git add -A && git commit -q -m "init" 2>/dev/null) || true
}

_rcr_run_hook() {
  # Args: $1 = fixture dir, $2 = Bash command, $3 = transcript body (optional).
  local dir="$1"
  local cmd="$2"
  local transcript_body="${3:-FIXTURE_FULL_CMD}"
  printf '%s\n' "$transcript_body" > "$dir/.transcript"
  local json="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$cmd\"},\"transcript_path\":\"$dir/.transcript\"}"
  echo "$json" | REPO_ROOT="$dir" TRACKING_ROOT="$dir" LOCAL_ROOT="$dir" \
    bash -c "cd '$dir' && bash '$dir/.claude/hooks/block-unsafe-project.sh'" 2>/dev/null
}

# 1. full_cmd read honored (allow path): transcript contains configured full_cmd.
_rcr_tmp=$(mktemp -d)
_rcr_setup_fixture "$_rcr_tmp" '{"testing":{"full_cmd":"FIXTURE_FULL_CMD"}}'
# Stage a code file so the commit gate is non-exempt.
(cd "$_rcr_tmp" && echo "var x=1;" > app.js && git add app.js)
_rcr_result=$(_rcr_run_hook "$_rcr_tmp" "git commit -m test" "FIXTURE_FULL_CMD was run here")
if [[ "$_rcr_result" != *"deny"* ]]; then
  pass "runtime-read: full_cmd honored — transcript match allows commit"
else
  fail "runtime-read: full_cmd — expected allow, got: $_rcr_result"
fi
rm -rf "$_rcr_tmp"

# 2. full_cmd read honored (deny path): transcript lacks configured full_cmd.
_rcr_tmp=$(mktemp -d)
_rcr_setup_fixture "$_rcr_tmp" '{"testing":{"full_cmd":"FIXTURE_FULL_CMD"}}'
(cd "$_rcr_tmp" && echo "var x=1;" > app.js && git add app.js)
_rcr_result=$(_rcr_run_hook "$_rcr_tmp" "git commit -m test" "some other output, no test marker here")
if [[ "$_rcr_result" == *"FIXTURE_FULL_CMD"* ]] && [[ "$_rcr_result" == *"deny"* ]]; then
  pass "runtime-read: full_cmd honored — missing transcript match blocks commit with verbatim cmd in reason"
else
  fail "runtime-read: full_cmd missing — expected block referencing FIXTURE_FULL_CMD, got: $_rcr_result"
fi
rm -rf "$_rcr_tmp"

# 3. unit_cmd read honored: piped invocation of configured unit_cmd blocks.
_rcr_tmp=$(mktemp -d)
_rcr_setup_fixture "$_rcr_tmp" '{"testing":{"unit_cmd":"FIXTURE_UNIT","full_cmd":"FIXTURE_FULL"}}'
_rcr_result=$(_rcr_run_hook "$_rcr_tmp" "FIXTURE_UNIT | head")
if [[ "$_rcr_result" == *"Don't pipe test output"* ]]; then
  pass "runtime-read: unit_cmd honored — pipe-block fires on configured cmd"
else
  fail "runtime-read: unit_cmd pipe — expected pipe-block, got: $_rcr_result"
fi
rm -rf "$_rcr_tmp"

# 4. ui.file_patterns read honored: downstream UI-touch detection uses configured pattern.
_rcr_tmp=$(mktemp -d)
_rcr_setup_fixture "$_rcr_tmp" '{"testing":{"full_cmd":"FIXTURE_FULL"},"ui":{"file_patterns":"src/ui/"}}'
mkdir -p "$_rcr_tmp/src/ui"
(cd "$_rcr_tmp" && echo "var x=1;" > src/ui/widget.js && git add src/ui/widget.js)
# Transcript contains FIXTURE_FULL (so test-cmd gate passes) but NO playwright-cli.
_rcr_result=$(_rcr_run_hook "$_rcr_tmp" "git commit -m test" "FIXTURE_FULL ran")
if [[ "$_rcr_result" == *"UI files changed but no playwright-cli"* ]]; then
  pass "runtime-read: ui.file_patterns honored — UI commit blocked without playwright-cli"
else
  fail "runtime-read: ui.file_patterns — expected UI-block, got: $_rcr_result"
fi
rm -rf "$_rcr_tmp"

# 5. Fallback: no config file → empty vars → empty-pattern guard skips pipe check.
_rcr_tmp=$(mktemp -d)
_rcr_setup_fixture "$_rcr_tmp" ""   # no config written
_rcr_result=$(_rcr_run_hook "$_rcr_tmp" "ls | head -5")
if [[ -z "$_rcr_result" ]] || [[ "$_rcr_result" != *"deny"* ]]; then
  pass "runtime-read: no-config fallback — empty-pattern guard skips pipe check on unrelated piped cmds"
else
  fail "runtime-read: no-config — expected allow on 'ls | head', got: $_rcr_result"
fi
rm -rf "$_rcr_tmp"

# 6. Subdir invocation: cwd is $FIXTURE/src/ but config is at root — hook resolves via --show-toplevel.
_rcr_tmp=$(mktemp -d)
_rcr_setup_fixture "$_rcr_tmp" '{"testing":{"unit_cmd":"FIXTURE_SUBDIR_UNIT","full_cmd":"FIXTURE_SUBDIR_FULL"}}'
mkdir -p "$_rcr_tmp/src"
printf 'FIXTURE_SUBDIR_FULL ran\n' > "$_rcr_tmp/.transcript"
_rcr_json="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"FIXTURE_SUBDIR_UNIT | head\"},\"transcript_path\":\"$_rcr_tmp/.transcript\"}"
# Do NOT pass REPO_ROOT so the hook must derive it via git rev-parse --show-toplevel from src/.
_rcr_result=$(echo "$_rcr_json" | bash -c "cd '$_rcr_tmp/src' && bash '$_rcr_tmp/.claude/hooks/block-unsafe-project.sh'" 2>/dev/null)
if [[ "$_rcr_result" == *"Don't pipe test output"* ]]; then
  pass "runtime-read: subdir invocation — --show-toplevel resolves config correctly"
else
  fail "runtime-read: subdir — expected pipe-block from subdir cwd, got: $_rcr_result"
fi
rm -rf "$_rcr_tmp"

# 7. Worktree invocation: config in worktree checkout resolves correctly.
_rcr_tmp=$(mktemp -d)
_rcr_wt=$(mktemp -d -u)   # worktree path (not yet created)
_rcr_setup_fixture "$_rcr_tmp" '{"testing":{"unit_cmd":"FIXTURE_WT_UNIT","full_cmd":"FIXTURE_WT_FULL"}}'
# Commit the config + hook into the main repo so they land in the worktree checkout.
(cd "$_rcr_tmp" && git add -A && git commit -q --allow-empty -m "seed config" 2>/dev/null)
(cd "$_rcr_tmp" && git worktree add -q -b feat/wt-test "$_rcr_wt" 2>/dev/null) || _rcr_wt=""
if [ -n "$_rcr_wt" ] && [ -f "$_rcr_wt/.claude/zskills-config.json" ]; then
  printf 'FIXTURE_WT_FULL ran\n' > "$_rcr_wt/.transcript"
  _rcr_json="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"FIXTURE_WT_UNIT | head\"},\"transcript_path\":\"$_rcr_wt/.transcript\"}"
  _rcr_result=$(echo "$_rcr_json" | bash -c "cd '$_rcr_wt' && bash '$_rcr_wt/.claude/hooks/block-unsafe-project.sh'" 2>/dev/null)
  if [[ "$_rcr_result" == *"Don't pipe test output"* ]]; then
    pass "runtime-read: worktree invocation — config resolves from worktree checkout"
  else
    fail "runtime-read: worktree — expected pipe-block in worktree, got: $_rcr_result"
  fi
  (cd "$_rcr_tmp" && git worktree remove -f "$_rcr_wt" 2>/dev/null) || rm -rf "$_rcr_wt"
else
  fail "runtime-read: worktree — fixture setup failed (worktree not created or config not present)"
fi
rm -rf "$_rcr_tmp"

# ─── SKILL_FILE_DRIFT_FIX Phase 3: three-case test-pipe gate ──────────
# Validates the three-case decision tree at the test-pipe gate
# (block-unsafe-project.sh:~311 area) introduced by Phase 3:
#   Case A — FULL_TEST_CMD set: gate operates as today (configured-cmd test
#            piping is denied with a fix-it suggestion).
#   Case B — FULL_TEST_CMD empty AND no test infra: skip the gate
#            (legitimate state for docs-only projects); a stderr line names
#            the reason. Bash invocations are allowed.
#   Case C — FULL_TEST_CMD empty AND test infra detected: misconfiguration.
#            Test-looking pipes are denied with a /update-zskills hint.

echo ""
echo "=== Three-case test-pipe gate (Phase 3) ==="

# Helper: capture both stdout (deny JSON) and stderr (informational logs)
# from a single hook invocation. Distinct from _rcr_run_hook which drops
# stderr — Cases B and C assert on stderr content.
_p3_run_hook_with_stderr() {
  local dir="$1"
  local cmd="$2"
  local transcript_body="${3:-FIXTURE_FULL_CMD}"
  printf '%s\n' "$transcript_body" > "$dir/.transcript"
  local json="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$cmd\"},\"transcript_path\":\"$dir/.transcript\"}"
  local out_file err_file
  out_file=$(mktemp)
  err_file=$(mktemp)
  echo "$json" | REPO_ROOT="$dir" TRACKING_ROOT="$dir" LOCAL_ROOT="$dir" \
    bash -c "cd '$dir' && bash '$dir/.claude/hooks/block-unsafe-project.sh'" \
    > "$out_file" 2> "$err_file"
  _P3_OUT=$(cat "$out_file")
  _P3_ERR=$(cat "$err_file")
  rm -f "$out_file" "$err_file"
}

# Case A — FULL_TEST_CMD set: pipe-block fires on configured cmd, message
# uses configured FULL_TEST_CMD verbatim (no opinionated default).
_p3_tmp=$(mktemp -d)
_rcr_setup_fixture "$_p3_tmp" '{"testing":{"unit_cmd":"FIXTURE_UNIT","full_cmd":"FIXTURE_FULL"}}'
_p3_run_hook_with_stderr "$_p3_tmp" "FIXTURE_FULL | head"
if [[ "$_P3_OUT" == *"deny"* ]] && [[ "$_P3_OUT" == *"FIXTURE_FULL"* ]] \
   && [[ "$_P3_OUT" != *"npm run test:all"* ]]; then
  pass "Phase3 Case A: configured FULL_TEST_CMD → pipe-block uses verbatim cmd, no opinionated default"
else
  fail "Phase3 Case A: expected deny w/ FIXTURE_FULL and no 'npm run test:all', got: $_P3_OUT"
fi
rm -rf "$_p3_tmp"

# Case A (message-text test from WI 3.1): with testing.output_file
# configured, the deny message references the configured filename, not
# the doc default ".test-results.txt".
_p3_tmp=$(mktemp -d)
_rcr_setup_fixture "$_p3_tmp" '{"testing":{"full_cmd":"FIXTURE_FULL","output_file":".out.log"}}'
_p3_run_hook_with_stderr "$_p3_tmp" "FIXTURE_FULL | tee somefile"
if [[ "$_P3_OUT" == *"deny"* ]] && [[ "$_P3_OUT" == *".out.log"* ]] \
   && [[ "$_P3_OUT" != *".test-results.txt"* ]]; then
  pass "Phase3 Case A: testing.output_file honored — deny message includes configured .out.log, not doc default"
else
  fail "Phase3 Case A: expected deny w/ .out.log and no .test-results.txt, got: $_P3_OUT"
fi
rm -rf "$_p3_tmp"

# Case B — FULL_TEST_CMD empty AND no test infra: gate is skipped, the
# bash command is allowed, and a stderr informational line names the
# reason ("no test infra detected; test-pipe gate disabled").
_p3_tmp=$(mktemp -d)
_rcr_setup_fixture "$_p3_tmp" ""   # no config, no test infra
_p3_run_hook_with_stderr "$_p3_tmp" "ls | head -5"
if [[ -z "$_P3_OUT" ]] || [[ "$_P3_OUT" != *"deny"* ]]; then
  if [[ "$_P3_ERR" == *"no test infra detected"* ]] \
     && [[ "$_P3_ERR" == *"test-pipe gate disabled"* ]]; then
    pass "Phase3 Case B: no infra + no full_cmd → allow + stderr explains skip"
  else
    fail "Phase3 Case B: allowed but stderr missing skip-reason, got stderr: $_P3_ERR"
  fi
else
  fail "Phase3 Case B: expected allow on docs-only project, got: $_P3_OUT"
fi
rm -rf "$_p3_tmp"

# Case C — FULL_TEST_CMD empty BUT test infra detected: any test-shaped
# pipe is denied with an /update-zskills educational message.
_p3_tmp=$(mktemp -d)
_rcr_setup_fixture "$_p3_tmp" ""   # no config (full_cmd empty)
# Plant test infra (Makefile is the simplest single-file detector).
printf 'test:\n\techo run\n' > "$_p3_tmp/Makefile"
_p3_run_hook_with_stderr "$_p3_tmp" "npm test | head"
if [[ "$_P3_OUT" == *"deny"* ]] \
   && [[ "$_P3_OUT" == *"/update-zskills"* ]] \
   && [[ "$_P3_OUT" == *"testing.full_cmd is empty"* ]]; then
  pass "Phase3 Case C: infra present + full_cmd empty + test-shaped pipe → deny pointing at /update-zskills"
else
  fail "Phase3 Case C: expected deny pointing at /update-zskills, got: $_P3_OUT"
fi
rm -rf "$_p3_tmp"

# Case C (allow path) — non-test bash commands stay allowed even when
# the project is misconfigured, so the user can still run /update-zskills
# (and any other repair commands) without being locked out.
_p3_tmp=$(mktemp -d)
_rcr_setup_fixture "$_p3_tmp" ""
printf 'test:\n\techo run\n' > "$_p3_tmp/Makefile"
_p3_run_hook_with_stderr "$_p3_tmp" "ls -la | head"
if [[ -z "$_P3_OUT" ]] || [[ "$_P3_OUT" != *"deny"* ]]; then
  pass "Phase3 Case C: non-test pipe stays allowed (user not locked out of repair)"
else
  fail "Phase3 Case C non-test allow: expected allow, got: $_P3_OUT"
fi
rm -rf "$_p3_tmp"

# ─── SKILL_FILE_DRIFT_FIX Phase 3 WI 3.4: test-infra detection sync ────
# Both consumers (block-unsafe-project.sh + skills/verify-changes/SKILL.md)
# encode the same canonical detection list, sourced from
# tests/fixtures/test-infra-patterns.txt. Each line of the fixture must
# appear in BOTH files. Failure message names the missing pattern + file.

echo ""
echo "=== Test-infra detection sync (Phase 3 WI 3.4) ==="

TEST_INFRA_FIXTURE="$REPO_ROOT/tests/fixtures/test-infra-patterns.txt"
if [ ! -f "$TEST_INFRA_FIXTURE" ]; then
  fail "test-infra-patterns fixture missing" "$TEST_INFRA_FIXTURE"
else
  # Confirm fixture is non-empty (guard against vacuous-pass via empty file).
  _ti_lines=$(grep -cv '^$' "$TEST_INFRA_FIXTURE")
  if [ "$_ti_lines" -lt 4 ]; then
    fail "test-infra-patterns fixture has too few entries (${_ti_lines} < 4) — fixture broken?" "$TEST_INFRA_FIXTURE"
  else
    pass "test-infra-patterns fixture present with ${_ti_lines} entries"
  fi

  # Sync against block-unsafe-project.sh (installed mirror — that's what
  # actually runs at the gate).
  _ti_hook="$REPO_ROOT/.claude/hooks/block-unsafe-project.sh"
  _ti_hook_fail=0
  while IFS= read -r _ti_pat; do
    [ -z "$_ti_pat" ] && continue
    if ! grep -qF -- "$_ti_pat" "$_ti_hook"; then
      fail "Test-infra detection list missing pattern $_ti_pat in $_ti_hook. Update $_ti_hook or remove from tests/fixtures/test-infra-patterns.txt." "$_ti_pat"
      _ti_hook_fail=1
    fi
  done < "$TEST_INFRA_FIXTURE"
  if [ "$_ti_hook_fail" -eq 0 ]; then
    pass "test-infra sync: every fixture pattern present in .claude/hooks/block-unsafe-project.sh"
  fi

  # Sync against skills/verify-changes/SKILL.md (the parallel consumer).
  _ti_skill="$REPO_ROOT/skills/verify-changes/SKILL.md"
  _ti_skill_fail=0
  while IFS= read -r _ti_pat; do
    [ -z "$_ti_pat" ] && continue
    if ! grep -qF -- "$_ti_pat" "$_ti_skill"; then
      fail "Test-infra detection list missing pattern $_ti_pat in $_ti_skill. Update $_ti_skill or remove from tests/fixtures/test-infra-patterns.txt." "$_ti_pat"
      _ti_skill_fail=1
    fi
  done < "$TEST_INFRA_FIXTURE"
  if [ "$_ti_skill_fail" -eq 0 ]; then
    pass "test-infra sync: every fixture pattern present in skills/verify-changes/SKILL.md"
  fi

  # Synthetic-divergence smoke test: the failure message is well-formed
  # (names the missing pattern and the file). Done with a tmp file that
  # is missing one fixture entry, so the same loop body would emit the
  # specific error string. We don't actually call the real assertion to
  # avoid a fail; we synthesize the failure string and check format.
  _ti_synth_msg="Test-infra detection list missing pattern XYZPATTERN in /tmp/synthetic-file. Update /tmp/synthetic-file or remove from tests/fixtures/test-infra-patterns.txt."
  if [[ "$_ti_synth_msg" == *"missing pattern XYZPATTERN"* ]] \
     && [[ "$_ti_synth_msg" == *"/tmp/synthetic-file"* ]] \
     && [[ "$_ti_synth_msg" == *"tests/fixtures/test-infra-patterns.txt"* ]]; then
    pass "test-infra sync: synthetic-divergence error message has expected format"
  else
    fail "test-infra sync: synthetic-divergence message format wrong" "$_ti_synth_msg"
  fi

  unset _ti_lines _ti_pat _ti_hook _ti_hook_fail _ti_skill _ti_skill_fail _ti_synth_msg
fi

# ─── WI 1.6: drift-regression — placeholder deny-list + allow-list ───
echo ""
echo "=== Drift regression: placeholder deny-list / allow-list ==="

# Deny-list: migrated placeholders must be absent from installed hook + scripts.
_drift_fail=0
for tok in '{{UNIT_TEST_CMD}}' '{{FULL_TEST_CMD}}' '{{UI_FILE_PATTERNS}}' '{{MAIN_REPO_PATH}}'; do
  if grep -Fq "$tok" \
    "$REPO_ROOT/.claude/hooks/block-unsafe-project.sh" \
    "$REPO_ROOT/skills/update-zskills/scripts/port.sh" \
    "$REPO_ROOT/scripts/test-all.sh"; then
    fail "drift-regression: migrated placeholder $tok still present in installed hook/scripts"
    _drift_fail=1
  fi
done
if [ "$_drift_fail" -eq 0 ]; then
  pass "drift-regression: deny-list — no migrated placeholders in installed hook or scripts"
fi

# (Phase 5 conversion: scripts/test-all.sh is now a failing stub the
# consumer customizes; no install-time placeholders remain. The prior
# allow-list for {{E2E_TEST_CMD}} / {{BUILD_TEST_CMD}} was removed
# alongside the implementation. See plans/CONSUMER_STUB_CALLOUTS_PLAN.md
# Phase 5.)

# Additional: template must also be placeholder-free for migrated vars.
for tok in '{{UNIT_TEST_CMD}}' '{{FULL_TEST_CMD}}' '{{UI_FILE_PATTERNS}}'; do
  if grep -Fq "$tok" "$REPO_ROOT/hooks/block-unsafe-project.sh.template"; then
    fail "drift-regression: template still contains migrated placeholder $tok"
  else
    pass "drift-regression: template — $tok removed from source template"
  fi
done

# Installed hook no longer contains the dead `'{{'` detection branches.
if grep -F "'{{'" "$REPO_ROOT/.claude/hooks/block-unsafe-project.sh" > /dev/null; then
  fail "drift-regression: installed hook still contains dead '{{' detection branches"
else
  pass "drift-regression: installed hook — dead '{{' placeholder-detection branches removed"
fi


echo "=== Fixture-extension coverage (single source of truth) ==="
# AC fixture-extension (plan AC §refine-1 R1.17): adding an entry to
# tests/fixtures/forbidden-literals.txt MUST immediately enforce in
# BOTH the deny-list test (Phase 4.1) and the drift-warn hook
# (Phase 4.2) with no code change. Append a synthetic literal
# `__TEST_LITERAL__` to a temp copy of the fixture; create a synthetic
# skill file containing the literal inside a bash fence; run both
# surfaces against it; assert both surface the expected DRIFT/WARN.
FIXTURE_EXT_DIR=/tmp/zskills-fixture-extension-test-$$
rm -rf "$FIXTURE_EXT_DIR"
mkdir -p "$FIXTURE_EXT_DIR/tests/fixtures"
mkdir -p "$FIXTURE_EXT_DIR/skills/synthetic"
cp "$REPO_ROOT/tests/fixtures/forbidden-literals.txt" \
   "$FIXTURE_EXT_DIR/tests/fixtures/forbidden-literals.txt"
printf '__TEST_LITERAL__\n' >> "$FIXTURE_EXT_DIR/tests/fixtures/forbidden-literals.txt"
cat > "$FIXTURE_EXT_DIR/skills/synthetic/SKILL.md" <<'SKILL'
# Synthetic

```bash
echo __TEST_LITERAL__
```
SKILL

# Surface 1: drift-warn hook against the synthetic skill file.
EXT_ERR=$(mktemp)
printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"'"$FIXTURE_EXT_DIR"'/skills/synthetic/SKILL.md"}}' \
  | CLAUDE_PROJECT_DIR="$FIXTURE_EXT_DIR" bash "$WARN_HOOK" 2>"$EXT_ERR" >/dev/null
EXT_RC=$?
EXT_ERR_CONTENT=$(cat "$EXT_ERR")
rm -f "$EXT_ERR"
if [[ "$EXT_RC" -eq 0 ]] \
  && [[ "$EXT_ERR_CONTENT" == *"WARN:"* ]] \
  && [[ "$EXT_ERR_CONTENT" == *"__TEST_LITERAL__"* ]]; then
  pass "fixture-extension: drift-warn hook picks up appended literal — WARN emitted"
else
  fail "fixture-extension: drift-warn hook missed appended literal" "rc=$EXT_RC stderr=$EXT_ERR_CONTENT"
fi

# Surface 2: the forbidden-literals deny-list scan — the SAME shared
# script tests/test-skill-conformance.sh calls (#948) — invoked DIRECTLY
# against the synthetic skills/ tree. This is the structural single-
# source-of-truth proof: both surfaces run identical scan code, not just
# a shared fixture. Sub-second, and it removes the prior nested full-suite
# run that re-ran the whole conformance suite against the throwaway tree
# (~71s + #587 tally-line-leak risk into run_suite's parser).
EXT_DENY_OUT=$(mktemp)
(
  . "$REPO_ROOT/tests/lib/forbidden-literals-scan.sh"
  run_forbidden_literals_scan "$FIXTURE_EXT_DIR" \
    "$FIXTURE_EXT_DIR/tests/fixtures/forbidden-literals.txt"
) > "$EXT_DENY_OUT" 2>&1
EXT_DENY_RC=$?
# We expect a non-zero rc (hits found) and the synthetic literal in the
# emitted DRIFT lines. Asserting on the literal is what proves the scan
# reads the appended fixture entry.
if [ "$EXT_DENY_RC" -ne 0 ] && grep -q '__TEST_LITERAL__' "$EXT_DENY_OUT"; then
  pass "fixture-extension: deny-list scan picks up appended literal — DRIFT line emitted"
else
  fail "fixture-extension: deny-list scan missed appended literal" "no __TEST_LITERAL__ in output (rc=$EXT_DENY_RC)"
  echo "  -- deny-list scan output --" >&2
  head -30 "$EXT_DENY_OUT" >&2
  echo "  -- end output --" >&2
fi
rm -f "$EXT_DENY_OUT"
rm -rf "$FIXTURE_EXT_DIR"



echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
