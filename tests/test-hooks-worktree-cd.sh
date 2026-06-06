#!/bin/bash
# Tests for hooks (sub-suite, Test Suite Parallelization Phase 1b).
# Project hook main_protected worktree-cd awareness: hook resolves the cd target so cross-worktree commits on a feature branch are correctly allowed/denied.
# This file is a MOVE of sections out of the former tests/test-hooks.sh
# monolith — every assertion is preserved verbatim. Run from repo root or
# any cwd: bash tests/test-hooks-worktree-cd.sh
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

# shellcheck source=tests/lib/hooks-harness.sh
. "$SCRIPT_DIR/lib/hooks-harness.sh"

echo "=== Project hook: main_protected — worktree-cd awareness ==="

# Background: hooks run in a separate process whose cwd is the main repo on
# `main`; when an agent does `cd /tmp/wt && git commit ...`, env vars from the
# agent shell don't propagate into the hook process. Before the fix to
# is_on_main(), the predicate read the hook's ambient branch (main) and
# wrongly blocked commits on feature-branch worktrees. These tests deliberately
# do NOT set REPO_ROOT so the hook's cd-target detection is exercised.

# Helper: simulates main-repo-on-main + a separate worktree on a chosen branch,
# runs the hook with cwd=main, command = `cd $worktree && <cmd>`. Returns the
# hook's stdout (deny JSON or empty).
run_worktree_cd_test() {
  local wt_branch="$1"   # branch the worktree is on
  local subcmd="$2"      # the git command to run inside the worktree
  local config_content='{"execution": {"main_protected": true}}'
  local main_tmpdir wt_tmpdir
  main_tmpdir=$(mktemp -d)
  wt_tmpdir=$(mktemp -d)

  # Setup main repo on main with main_protected=true
  mkdir -p "$main_tmpdir/.claude/hooks"
  cp "$PROJECT_HOOK" "$main_tmpdir/.claude/hooks/block-unsafe-project.sh"
  printf '{"scripts":{"test":"vitest","test:all":"vitest run"}}\n' > "$main_tmpdir/package.json"
  printf 'npm run test:all\n' > "$main_tmpdir/.transcript"
  (cd "$main_tmpdir" && git init -q && git checkout -b main 2>/dev/null && git add -A && git commit -q -m "init" 2>/dev/null)
  # Merge caller's partial config with default test-cmd / UI fields so runtime
  # read populates all hook vars.
  CALLER_CFG="$config_content" python3 -c '
import json, os
caller = json.loads(os.environ["CALLER_CFG"])
defaults = {"testing": {"unit_cmd": "npm test", "full_cmd": "npm run test:all"}, "ui": {"file_patterns": "src/ui/"}}
for k, v in defaults.items():
    caller.setdefault(k, v)
print(json.dumps(caller))
' > "$main_tmpdir/.claude/zskills-config.json"

  # Setup separate "worktree" on the requested branch (a fresh repo is
  # equivalent for the predicate's purpose — git -C reports its own branch).
  (cd "$wt_tmpdir" && git init -q && git checkout -b "$wt_branch" 2>/dev/null && git commit -q --allow-empty -m "wt init" 2>/dev/null)

  local cmd="cd $wt_tmpdir && $subcmd"
  local json="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$cmd\"},\"transcript_path\":\"$main_tmpdir/.transcript\"}"

  # Critical: cwd=main (so ambient is on `main`), and DO NOT set REPO_ROOT.
  # This exercises extract_cd_target inside the hook's is_on_main predicate.
  local result
  result=$(cd "$main_tmpdir" && echo "$json" | bash "$main_tmpdir/.claude/hooks/block-unsafe-project.sh" 2>/dev/null)

  rm -rf "$main_tmpdir" "$wt_tmpdir"
  echo "$result"
}

# Worktree on feature branch — commit must be ALLOWED (the bug we're fixing).
RESULT=$(run_worktree_cd_test "feat/touch-grass" "git commit -m test")
if [[ "$RESULT" != *"main branch is protected"* ]]; then
  pass "main_protected + worktree-cd: commit on feature-branch worktree allowed"
else
  fail "main_protected + worktree-cd: commit on feature-branch worktree should be allowed, got: $RESULT"
fi

# Worktree happens to be on main — commit must STILL be blocked.
RESULT=$(run_worktree_cd_test "main" "git commit -m test")
if [[ "$RESULT" == *"main branch is protected"* ]]; then
  pass "main_protected + worktree-cd: commit on main-via-worktree still blocked"
else
  fail "main_protected + worktree-cd: commit on main-via-worktree should be blocked, got: $RESULT"
fi

# Worktree on feature branch — cherry-pick must be ALLOWED (same bug class).
RESULT=$(run_worktree_cd_test "feat/touch-grass" "git cherry-pick abc123")
if [[ "$RESULT" != *"main branch is protected"* ]]; then
  pass "main_protected + worktree-cd: cherry-pick on feature-branch worktree allowed"
else
  fail "main_protected + worktree-cd: cherry-pick on feature-branch worktree should be allowed, got: $RESULT"
fi

# Worktree on feature branch — push to feature must be ALLOWED.
RESULT=$(run_worktree_cd_test "feat/touch-grass" "git push -u origin feat/touch-grass")
if [[ "$RESULT" != *"Cannot push to main"* ]]; then
  pass "main_protected + worktree-cd: push feature branch from worktree allowed"
else
  fail "main_protected + worktree-cd: push feature branch from worktree should be allowed, got: $RESULT"
fi

# Test: push tracking works before first push (no upstream) — code-files detection fallback
push_tracking_tmpdir=$(mktemp -d)
mkdir -p "$push_tracking_tmpdir/.claude/hooks"
mkdir -p "$push_tracking_tmpdir/.zskills/tracking"
cp "$PROJECT_HOOK" "$push_tracking_tmpdir/.claude/hooks/block-unsafe-project.sh"
cat > "$push_tracking_tmpdir/.claude/zskills-config.json" <<'EOF'
{
  "testing": {"unit_cmd": "npm test", "full_cmd": "npm run test:all"},
  "ui": {"file_patterns": "src/ui/"}
}
EOF
printf '{"scripts":{"test":"vitest","test:all":"vitest run"}}\n' > "$push_tracking_tmpdir/package.json"
printf 'npm run test:all\n' > "$push_tracking_tmpdir/.transcript"
(cd "$push_tracking_tmpdir" && git init -q && git checkout -b main 2>/dev/null && git add -A && git commit -q -m "init" 2>/dev/null)
(cd "$push_tracking_tmpdir" && git checkout -b feat/test 2>/dev/null && echo "var x=1;" > app.js && git add app.js && git commit -q -m "add code" 2>/dev/null)
# Pipeline association via .zskills-tracked (required by the modern push tracking block)
printf 'run-plan.test-plan\n' > "$push_tracking_tmpdir/.zskills-tracked"
# Add a requires file without fulfilled — should block push with code files
# (Option B: markers live in the per-pipeline subdir)
mkdir -p "$push_tracking_tmpdir/.zskills/tracking/run-plan.test-plan"
touch "$push_tracking_tmpdir/.zskills/tracking/run-plan.test-plan/requires.verify-changes.test-plan"
PUSH_JSON="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push -u origin feat/test\"},\"transcript_path\":\"$push_tracking_tmpdir/.transcript\"}"
PUSH_RESULT=$(cd "$push_tracking_tmpdir" && echo "$PUSH_JSON" | REPO_ROOT="$push_tracking_tmpdir" LOCAL_ROOT="$push_tracking_tmpdir" TRACKING_ROOT="$push_tracking_tmpdir" bash "$push_tracking_tmpdir/.claude/hooks/block-unsafe-project.sh" 2>/dev/null)
if [[ "$PUSH_RESULT" == *"Required skill invocation"* ]] || [[ "$PUSH_RESULT" == *"not yet fulfilled"* ]]; then
  pass "push tracking: no-upstream fallback detects code files and enforces tracking"
else
  fail "push tracking: no-upstream fallback should detect code files, got: $PUSH_RESULT"
fi
rm -rf "$push_tracking_tmpdir"


# === BLOCK_UNSAFE_HARDENING bypass canaries — project hook ===
# Phase 3.4 (BLOCK_UNSAFE_HARDENING): bypass-canary integration tests for the
# tokenize-then-walk migration of `git[[:space:]]+(commit|cherry-pick|push)`
# outer gates. R1, R2, R4 reproducers from Phase 1 reference doc; R3 omitted
# (UNTRACED per round-1 DA-C-1, AC9). PR4-PR6 are class-pinned negatives
# (grep "git <verb>" file.sh on main → ALLOW). PR7-PR9 are positive
# regressions. PR10 is the bypass-canary battery for is_git_subcommand
# top-level git-flag combinations (XCC5-XCC14 + JSON quote-injection).
# setup_project_test_on_main is provided by tests/lib/hooks-harness.sh
# (folded in via the harness sourcing test-hooks-helpers.sh) — sourced once
# at the top of this file, so no per-section source is needed here.

# PR1 — Reproducer R1: grep -n on the installed hook mentioning "git commit".
# Pre-migration this trips the line-411 outer gate (transcript-based commit
# verification); post-migration the tokenize-then-walk classifier sees `grep`
# as the first non-flag token, so the gate doesn't fire.
setup_project_test_on_main
expect_project_allow "PR1: R1 grep mention" "grep -n 'git commit\\|...' /workspaces/zskills/.claude/hooks/block-unsafe-project.sh"
teardown_project_test

# PR2 — Reproducer R2: sed -n on the hook source. Same class as R1.
setup_project_test_on_main
expect_project_allow "PR2: R2 sed mention" "sed -n '404,420p' /workspaces/zskills/.claude/hooks/block-unsafe-project.sh"
teardown_project_test

# (PR3 — REMOVED per round-1 DA-C-1; R3 was UNTRACED.)

# PR3 — Reproducer R4: grep -nE on tests/test-hooks.sh whose pattern lists
# `git commit` and similar tokens. Pre-migration the outer-gate substring
# regex matches the literal pattern argument; post-migration it does not.
setup_project_test_on_main
expect_project_allow "PR3: R4 grep mention" "grep -nE '(commit.*OR|over-match|grep.*git commit|sed.*block-unsafe|...)' /workspaces/zskills/tests/test-hooks.sh"
teardown_project_test

# PR4 — Class-pinned negative (commit): mention of `git commit` inside a
# grep argument while on main → ALLOW (no real git invocation).
setup_project_test_on_main
expect_project_allow "PR4: class-pinned negative commit" 'grep "git commit" file.sh'
teardown_project_test

# PR5 — Class-pinned negative (cherry-pick).
setup_project_test_on_main
expect_project_allow "PR5: class-pinned negative cherry-pick" 'grep "git cherry-pick" file.sh'
teardown_project_test

# PR6 — Class-pinned negative (push). Verifies the outer-gate doesn't fire
# on `grep "git push" file.sh`. (Existing rule (c) test at line 1385 covers
# the inner check; this verifies the outer gate.)
setup_project_test_on_main
expect_project_allow "PR6: class-pinned negative push" 'grep "git push" file.sh'
teardown_project_test

# PR7 — Positive regression (commit on main): the migration must not weaken
# the existing main_protected enforcement.
setup_project_test_on_main
expect_project_deny "PR7: positive regression — commit on main" 'git commit -m "x"'
teardown_project_test

# PR8 — Positive regression (cherry-pick on main).
setup_project_test_on_main
expect_project_deny "PR8: positive regression — cherry-pick on main" "git cherry-pick abc123"
teardown_project_test

# PR9 — Positive regression (naked push to main, rule c).
setup_project_test_on_main
expect_project_deny "PR9: positive regression — naked push to main (rule c)" "git push"
teardown_project_test

# PR10 — Bypass-canary battery for is_git_subcommand against the project hook.
# Parameterized over XCC5-XCC14 (top-level git-flag combinations) plus one
# JSON quote-injection assertion (round-1 DA-H-1). Each case pairs with
# setup_project_test_on_main + teardown_project_test.

# XCC5 — `git -C /tmp/foo commit -m bar`: real commit through `-C path` → DENY.
setup_project_test_on_main
expect_project_deny "PR10/XCC5: git -C path commit on main" 'git -C /tmp/foo commit -m bar'
teardown_project_test

# XCC6 — `git -C /tmp/foo log`: not a commit → ALLOW.
setup_project_test_on_main
expect_project_allow "PR10/XCC6: git -C path log on main" "git -C /tmp/foo log"
teardown_project_test

# XCC7 — `git -c user.email=x@y.z commit -m msg`: real commit through `-c k=v` → DENY.
setup_project_test_on_main
expect_project_deny "PR10/XCC7: git -c k=v commit on main" 'git -c user.email=x@y.z commit -m msg'
teardown_project_test

# XCC8 — `git --no-pager commit -m foo`: real commit with --no-pager → DENY.
setup_project_test_on_main
expect_project_deny "PR10/XCC8: git --no-pager commit on main" 'git --no-pager commit -m foo'
teardown_project_test

# XCC9 — `git --git-dir=/x commit`: real commit with --git-dir=val → DENY.
setup_project_test_on_main
expect_project_deny "PR10/XCC9: git --git-dir=val commit on main" "git --git-dir=/x commit"
teardown_project_test

# XCC10 — `git -P commit`: real commit with `-P` short flag → DENY.
setup_project_test_on_main
expect_project_deny "PR10/XCC10: git -P commit on main" "git -P commit"
teardown_project_test

# XCC11 — `git -C /tmp -c user.email=x commit`: chained -C and -c → DENY.
setup_project_test_on_main
expect_project_deny "PR10/XCC11: git -C path -c k=v commit on main" "git -C /tmp -c user.email=x commit"
teardown_project_test

# XCC12 — `git --git-dir=/x --work-tree=/y commit -m msg`: two long flags → DENY.
setup_project_test_on_main
expect_project_deny "PR10/XCC12: git --git-dir --work-tree commit on main" 'git --git-dir=/x --work-tree=/y commit -m msg'
teardown_project_test

# XCC13 — `git --no-pager log`: subcommand after flag-skip is `log` → ALLOW.
setup_project_test_on_main
expect_project_allow "PR10/XCC13: git --no-pager log on main" "git --no-pager log"
teardown_project_test

# XCC14 — `git -C /tmp diff`: not a commit/cherry-pick/push → ALLOW.
setup_project_test_on_main
expect_project_allow "PR10/XCC14: git -C path diff on main" "git -C /tmp diff"
teardown_project_test

# XCC15 (#1133) — SPACE-separated multi-arg git GLOBAL flags before a commit
# must skip the value token so `commit` is recognized as the subcommand → DENY
# on main. Pre-#1133 the flag-skip loop only knew `-C`/`-c`, so the value was
# misread as the subcommand and the commit gate never fired. The fused form
# (XCC12) was always handled; these pin the space form.
setup_project_test_on_main
expect_project_deny "PR10/XCC15: git --git-dir <dir> commit on main (#1133)" "git --git-dir /x/.git commit -m msg"
teardown_project_test
setup_project_test_on_main
expect_project_deny "PR10/XCC16: git --work-tree <dir> commit on main (#1133)" "git --work-tree /y commit -m msg"
teardown_project_test
setup_project_test_on_main
expect_project_deny "PR10/XCC17: git --namespace <ns> commit on main (#1133)" "git --namespace foo commit -m msg"
teardown_project_test
# XCC18 (#1133) — space-form flag before a NON-mutating subcommand → ALLOW
# (the value token must not be misread as a mutating subcommand).
setup_project_test_on_main
expect_project_allow "PR10/XCC18: git --git-dir <dir> log on main (#1133)" "git --git-dir /x/.git log"
teardown_project_test

# JSON quote-injection (round-1 DA-H-1): `git "commit" -m "x"` should still
# DENY — the helper unwraps one quote layer on the subcommand token.
setup_project_test_on_main
expect_project_deny "PR10/JSON-quote-injection: git \"commit\" on main" 'git "commit" -m "x"'
teardown_project_test


# === BLOCK_UNSAFE_HARDENING class-pinned acceptance matrices (migrated subset) ===
# Phase 5.2 + 5.3 of plans/BLOCK_UNSAFE_HARDENING.md. These are GENERATED-LOOP
# acceptance canaries that pin the bug class (regex over whole-buffer scan)
# rather than any specific shape. Negative matrices: 144 project-hook + 192
# generic-hook + 24 adjacent-class = 360 negative cases that must ALLOW.
# Positive matrix: 24 cases that must DENY (5.3).
#
# Per-iteration setup_project_test_on_main is MANDATORY (round-2 R2-H-2 /
# DA2-H-4) — silent cross-case state contamination would otherwise let case
# N+1 pass vacuously because case N left state. Cost ~10s acceptable.
#
# CHANGELOG bullet 4 documents that the bug class remains open for the
# UNMIGRATED subset (rm -rf / find -delete / rsync --delete / xargs ... rm /
# fuser -k); those verbs are NOT exercised by these matrices.
# setup_project_test_on_main is provided by tests/lib/hooks-harness.sh
# (sourced once at the top of this file).



echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
