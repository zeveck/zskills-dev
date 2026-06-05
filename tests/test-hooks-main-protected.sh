#!/bin/bash
# Tests for hooks (sub-suite, Test Suite Parallelization Phase 1b).
# Project hook main_protected enforcement: branch-gated commit/cherry-pick/push, extract_cd_target multi-line bash (#93), push-segment scoping rules a/b/c (#81).
# This file is a MOVE of sections out of the former tests/test-hooks.sh
# monolith — every assertion is preserved verbatim. Run from repo root or
# any cwd: bash tests/test-hooks-main-protected.sh
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

echo "=== Project hook: main_protected enforcement ==="



# Test: main_protected blocks commit on main
RESULT=$(run_main_protected_test "main" '{"execution": {"main_protected": true}}' "git commit -m test")
if [[ "$RESULT" == *"main branch is protected"* ]]; then
  pass "main_protected: commit on main blocked"
else
  fail "main_protected: commit on main should be blocked, got: $RESULT"
fi

# Test: main_protected allows commit on feature branch
RESULT=$(run_main_protected_test "feat/test" '{"execution": {"main_protected": true}}' "git commit -m test")
if [[ "$RESULT" != *"main branch is protected"* ]]; then
  pass "main_protected: commit on feature branch allowed"
else
  fail "main_protected: commit on feature branch should be allowed, got: $RESULT"
fi

# Test: main_protected false allows commit on main
RESULT=$(run_main_protected_test "main" '{"execution": {"main_protected": false}}' "git commit -m test")
if [[ "$RESULT" != *"main branch is protected"* ]]; then
  pass "main_protected: false allows commit on main"
else
  fail "main_protected: false should allow commit on main, got: $RESULT"
fi

# Test: no config file allows commit on main
RESULT=$(run_main_protected_test "main" "" "git commit -m test")
if [[ "$RESULT" != *"main branch is protected"* ]]; then
  pass "main_protected: no config allows commit on main"
else
  fail "main_protected: no config should allow commit on main, got: $RESULT"
fi

# Test: main_protected blocks cherry-pick on main
RESULT=$(run_main_protected_test "main" '{"execution": {"main_protected": true}}' "git cherry-pick abc123")
if [[ "$RESULT" == *"main branch is protected"* ]]; then
  pass "main_protected: cherry-pick on main blocked"
else
  fail "main_protected: cherry-pick on main should be blocked, got: $RESULT"
fi

# ─── Wrapper-bypass closure (#399): bash -c / eval / sh -c forms ───
# Without is_git_subcommand_in_wrappers, an agent could route around
# main_protected via `bash -c 'git commit -m foo'`. These tests assert the
# hook now catches the wrapper-bypass class for commit / cherry-pick / push.

# WB-MP1: bash -c 'git commit' on protected main → blocked.
RESULT=$(run_main_protected_test "main" '{"execution": {"main_protected": true}}' "bash -c 'git commit -m test'")
if [[ "$RESULT" == *"main branch is protected"* ]]; then
  pass "main_protected #399: bash -c 'git commit' on main blocked"
else
  fail "main_protected #399: bash -c 'git commit' on main should be blocked, got: $RESULT"
fi

# WB-MP2: eval 'git commit' on protected main → blocked.
RESULT=$(run_main_protected_test "main" '{"execution": {"main_protected": true}}' "eval 'git commit -m test'")
if [[ "$RESULT" == *"main branch is protected"* ]]; then
  pass "main_protected #399: eval 'git commit' on main blocked"
else
  fail "main_protected #399: eval 'git commit' on main should be blocked, got: $RESULT"
fi

# WB-MP3: sh -c 'git cherry-pick' on protected main → blocked.
RESULT=$(run_main_protected_test "main" '{"execution": {"main_protected": true}}' "sh -c 'git cherry-pick abc123'")
if [[ "$RESULT" == *"main branch is protected"* ]]; then
  pass "main_protected #399: sh -c 'git cherry-pick' on main blocked"
else
  fail "main_protected #399: sh -c 'git cherry-pick' on main should be blocked, got: $RESULT"
fi

# WB-MP4: bash -c 'git push origin main' on protected main → blocked.
RESULT=$(run_main_protected_test "feat/test" '{"execution": {"main_protected": true}}' "bash -c 'git push origin main'")
if [[ "$RESULT" == *"Cannot push to main"* ]]; then
  pass "main_protected #399: bash -c 'git push origin main' blocked"
else
  fail "main_protected #399: bash -c 'git push origin main' should be blocked, got: $RESULT"
fi

# WB-MP5: nested bash -c 'sh -c "git commit"' on protected main → blocked
# (#399's bounded-depth recursion).
RESULT=$(run_main_protected_test "main" '{"execution": {"main_protected": true}}' "bash -c 'sh -c \\\"git commit -m test\\\"'")
if [[ "$RESULT" == *"main branch is protected"* ]]; then
  pass "main_protected #399: nested bash -c 'sh -c \"git commit\"' blocked"
else
  fail "main_protected #399: nested wrapper should be blocked, got: $RESULT"
fi

# Test: main_protected blocks push to main
RESULT=$(run_main_protected_test "main" '{"execution": {"main_protected": true}}' "git push origin main")
if [[ "$RESULT" == *"Cannot push to main"* ]]; then
  pass "main_protected: push to main blocked"
else
  fail "main_protected: push to main should be blocked, got: $RESULT"
fi

# Test: main_protected allows push on feature branch
RESULT=$(run_main_protected_test "feat/test" '{"execution": {"main_protected": true}}' "git push -u origin feat/test")
if [[ "$RESULT" != *"Cannot push to main"* ]]; then
  pass "main_protected: push on feature branch allowed"
else
  fail "main_protected: push on feature branch should be allowed, got: $RESULT"
fi

# Test: main_protected allows literal feature-branch refspec (regression guard —
# the old `origin[[:space:]]+[a-zA-Z]` heuristic accepted this; make sure the
# new three-case rule still allows it).
RESULT=$(run_main_protected_test "feat/test" '{"execution": {"main_protected": true}}' "git push origin feat/foo")
if [[ "$RESULT" != *"Cannot push to main"* ]]; then
  pass "main_protected: push origin feat/foo (literal feature branch) allowed"
else
  fail "main_protected: push origin feat/foo should be allowed, got: $RESULT"
fi

# Test: main_protected allows variable-bearing push target (the false-positive
# the new rule is designed to eliminate). Old rule blocked because
# `origin[[:space:]]+[a-zA-Z]` didn't match `origin "$BRANCH"` (starts with `"`),
# which flipped the negated check into "looks like a bare push → block".
# Note: on `main`, because the helper's git repo has main_protected=true. The
# command's refspec is a variable — hook can't statically prove it isn't "main",
# but the rule deliberately trusts it (see the block comment in the hook).
RESULT=$(run_main_protected_test "main" '{"execution": {"main_protected": true}}' 'git push -u origin \"$BRANCH\"')
if [[ "$RESULT" != *"Cannot push to main"* ]]; then
  pass "main_protected: push origin \"\$BRANCH\" (variable-bearing target) allowed"
else
  fail "main_protected: push origin \"\$BRANCH\" should be allowed, got: $RESULT"
fi

# Test: alternative variable name — same semantics.
RESULT=$(run_main_protected_test "main" '{"execution": {"main_protected": true}}' 'git push origin \"$BRANCH_NAME\"')
if [[ "$RESULT" != *"Cannot push to main"* ]]; then
  pass "main_protected: push origin \"\$BRANCH_NAME\" (variable-bearing target) allowed"
else
  fail "main_protected: push origin \"\$BRANCH_NAME\" should be allowed, got: $RESULT"
fi

# Test: main_protected still blocks master explicitly (paired with the main case).
RESULT=$(run_main_protected_test "master" '{"execution": {"main_protected": true}}' "git push origin master")
if [[ "$RESULT" == *"Cannot push to main"* ]]; then
  pass "main_protected: push origin master blocked"
else
  fail "main_protected: push origin master should be blocked, got: $RESULT"
fi

# Test: main_protected blocks force-push to main (new `+main` case explicitly
# covered by rule (a)).
RESULT=$(run_main_protected_test "feat/test" '{"execution": {"main_protected": true}}' "git push origin +main")
if [[ "$RESULT" == *"Cannot push to main"* ]]; then
  pass "main_protected: push origin +main (force-prefix) blocked"
else
  fail "main_protected: push origin +main should be blocked, got: $RESULT"
fi

# Test: main_protected blocks HEAD:main refspec (new rule (b)).
RESULT=$(run_main_protected_test "feat/test" '{"execution": {"main_protected": true}}' "git push origin HEAD:main")
if [[ "$RESULT" == *"Cannot push to main"* ]]; then
  pass "main_protected: push origin HEAD:main (refspec) blocked"
else
  fail "main_protected: push origin HEAD:main should be blocked, got: $RESULT"
fi

# Test: main_protected blocks HEAD:master refspec (new rule (b)).
RESULT=$(run_main_protected_test "feat/test" '{"execution": {"main_protected": true}}' "git push origin HEAD:master")
if [[ "$RESULT" == *"Cannot push to main"* ]]; then
  pass "main_protected: push origin HEAD:master (refspec) blocked"
else
  fail "main_protected: push origin HEAD:master should be blocked, got: $RESULT"
fi

# Issue #392: <localref>:main refspec — main_protected must broaden rule (b)
# beyond HEAD:main to catch arbitrary local-side names. Pre-fix the regex
# required a literal "HEAD:" prefix; "feat:main" evaded both rule (a)
# (which requires main immediately after origin) and rule (b).
RESULT=$(run_main_protected_test "feat/test" '{"execution": {"main_protected": true}}' "git push origin feat:main")
if [[ "$RESULT" == *"Cannot push to main"* ]]; then
  pass "main_protected: push origin feat:main (#392) blocked"
else
  fail "main_protected: push origin feat:main should be blocked, got: $RESULT"
fi

RESULT=$(run_main_protected_test "feat/test" '{"execution": {"main_protected": true}}' "git push origin localbranch:main")
if [[ "$RESULT" == *"Cannot push to main"* ]]; then
  pass "main_protected: push origin localbranch:main (#392) blocked"
else
  fail "main_protected: push origin localbranch:main should be blocked, got: $RESULT"
fi

RESULT=$(run_main_protected_test "feat/test" '{"execution": {"main_protected": true}}' "git push origin :main")
if [[ "$RESULT" == *"Cannot push to main"* ]]; then
  pass "main_protected: push origin :main (deletion attempt — #392) blocked"
else
  fail "main_protected: push origin :main should be blocked, got: $RESULT"
fi

RESULT=$(run_main_protected_test "feat/test" '{"execution": {"main_protected": true}}' "git push origin abc123:master")
if [[ "$RESULT" == *"Cannot push to main"* ]]; then
  pass "main_protected: push origin abc123:master (#392) blocked"
else
  fail "main_protected: push origin abc123:master should be blocked, got: $RESULT"
fi

# Issue #470: project-hook rule (b) — `feat:+main` slipped because the regex
# didn't allow an optional `+` between `:` and `main`. Generic hook caught
# this via the `${X##*:}` + `${X#+}` layered normalization, but the project
# hook (active under main_protected: true) didn't.
RESULT=$(run_main_protected_test "feat/test" '{"execution": {"main_protected": true}}' "git push origin feat:+main")
if [[ "$RESULT" == *"Cannot push to main"* ]]; then
  pass "main_protected: push origin feat:+main (#470 — force after refspec colon) blocked"
else
  fail "main_protected: push origin feat:+main should be blocked, got: $RESULT"
fi

# Issue #470: project-hook rule (a) — `refs/heads/main` slipped because
# neither rule allowed the fully-qualified `refs/heads/` prefix. Git accepts
# this as equivalent to `main`.
RESULT=$(run_main_protected_test "feat/test" '{"execution": {"main_protected": true}}' "git push origin refs/heads/main")
if [[ "$RESULT" == *"Cannot push to main"* ]]; then
  pass "main_protected: push origin refs/heads/main (#470 — fully-qualified ref) blocked"
else
  fail "main_protected: push origin refs/heads/main should be blocked, got: $RESULT"
fi

# Issue #470: project-hook rule (a) — `refs/heads/master` equivalent.
RESULT=$(run_main_protected_test "feat/test" '{"execution": {"main_protected": true}}' "git push origin refs/heads/master")
if [[ "$RESULT" == *"Cannot push to main"* ]]; then
  pass "main_protected: push origin refs/heads/master (#470) blocked"
else
  fail "main_protected: push origin refs/heads/master should be blocked, got: $RESULT"
fi

# Issue #470: combined force + fully-qualified.
RESULT=$(run_main_protected_test "feat/test" '{"execution": {"main_protected": true}}' "git push origin +refs/heads/main")
if [[ "$RESULT" == *"Cannot push to main"* ]]; then
  pass "main_protected: push origin +refs/heads/main (#470 — force + fully-qualified) blocked"
else
  fail "main_protected: push origin +refs/heads/main should be blocked, got: $RESULT"
fi

# Issue #470: combined refspec + fully-qualified — rule (b).
RESULT=$(run_main_protected_test "feat/test" '{"execution": {"main_protected": true}}' "git push origin feat:refs/heads/main")
if [[ "$RESULT" == *"Cannot push to main"* ]]; then
  pass "main_protected: push origin feat:refs/heads/main (#470 — refspec + fully-qualified) blocked"
else
  fail "main_protected: push origin feat:refs/heads/main should be blocked, got: $RESULT"
fi

# Regression guard: rule (b)'s broadened regex must NOT trip on a legitimate
# feature-branch refspec (no `:main` / `:master` suffix). Pairs with the
# existing literal feature-branch refspec test for rule (a).
RESULT=$(run_main_protected_test "feat/test" '{"execution": {"main_protected": true}}' "git push origin feat/test:feat/test")
if [[ "$RESULT" != *"Cannot push to main"* ]]; then
  pass "main_protected: push origin feat/test:feat/test (refspec, non-main remote) allowed"
else
  fail "main_protected: push origin feat/test:feat/test should be allowed, got: $RESULT"
fi

# Test: main_protected blocks naked `git push` while on main (rule (c) — the
# default push targets the current branch).
RESULT=$(run_main_protected_test "main" '{"execution": {"main_protected": true}}' "git push")
if [[ "$RESULT" == *"Cannot push to main"* ]]; then
  pass "main_protected: naked git push on main blocked"
else
  fail "main_protected: naked git push on main should be blocked, got: $RESULT"
fi

echo ""
echo "=== Project hook: extract_cd_target multi-line bash (issue #93) ==="

# Background: the hook's extract_cd_target uses [[:space:]] as a stop-class
# in its regex. JSON wire format escapes embedded newlines as the literal
# two-character sequence `\n` — which [[:space:]] does NOT match. Without
# decoding `\n` → real newline in the sed pre-processing, multi-line bash
# like `cd /tmp/feature-worktree\ngit commit -m foo` captured
# `/tmp/feature-worktree\ngit` (with literal backslash-n) into the path,
# the [ -d ] check failed, extract_cd_target returned empty, and is_on_main
# fell back to ambient cwd (main repo on main) → blocked legitimate
# feature-branch commits.
#
# Helper: run hook with a custom JSON envelope (no test-cmd shell-quoting),
# in a configured main repo, against a separately-created feature-branch
# tmpdir referenced via `cd /tmp/...`. Does NOT set REPO_ROOT — that env
# override would short-circuit is_on_main before extract_cd_target runs.
run_extract_cd_target_test() {
  local main_branch="$1"   # branch the "main repo" is on (the ambient cwd)
  local feat_branch="$2"   # branch the cd-target worktree is on
  local raw_command="$3"   # literal command string (may contain \n)
  local main_tmpdir
  local feat_tmpdir
  main_tmpdir=$(mktemp -d)
  feat_tmpdir=$(mktemp -d)

  # --- Main repo (hook's ambient cwd) ---
  mkdir -p "$main_tmpdir/.claude/hooks"
  mkdir -p "$main_tmpdir/.zskills/tracking"
  cp "$PROJECT_HOOK" "$main_tmpdir/.claude/hooks/block-unsafe-project.sh"
  printf '{"scripts":{"test":"vitest","test:all":"vitest run"}}\n' > "$main_tmpdir/package.json"
  printf 'npm run test:all\n' > "$main_tmpdir/.transcript"
  cat > "$main_tmpdir/.claude/zskills-config.json" <<'EOF'
{
  "testing": {
    "unit_cmd": "npm test",
    "full_cmd": "npm run test:all"
  },
  "ui": {
    "file_patterns": "src/ui/"
  },
  "execution": {
    "main_protected": true
  }
}
EOF
  (cd "$main_tmpdir" && git init -q && git checkout -b "$main_branch" 2>/dev/null && git add -A && git -c user.email=t@t -c user.name=t commit -q -m "init" 2>/dev/null)

  # --- Feature worktree (separate dir referenced via cd) ---
  (cd "$feat_tmpdir" && git init -q && git checkout -b "$feat_branch" 2>/dev/null && echo x > x && git add x && git -c user.email=t@t -c user.name=t commit -q -m "init" 2>/dev/null)

  # Build JSON: "command" must be LAST field (greedy sed quirk, see helper above).
  # Substitute the feat_tmpdir into the raw command. The caller-supplied raw_command
  # contains literal `\n` sequences — these must reach the hook unescaped (i.e., as
  # the two characters backslash-n), which is exactly the JSON wire format the bug
  # is about. printf with %s preserves them.
  local cmd_with_path
  cmd_with_path=$(printf '%s' "$raw_command" | sed "s|FEAT_TMPDIR|$feat_tmpdir|g")
  local json
  json="{\"tool_name\":\"Bash\",\"transcript_path\":\"$main_tmpdir/.transcript\",\"tool_input\":{\"command\":\"$cmd_with_path\"}}"

  # Run hook in main_tmpdir cwd, with NO REPO_ROOT override so is_on_main
  # exercises extract_cd_target. LOCAL_ROOT/TRACKING_ROOT are set to the
  # main repo so the tracking guard reads from the fixture (no .zskills-tracked
  # there → tracking enforcement skipped, isolating this test to extract_cd_target).
  local result
  result=$(echo "$json" | (
    cd "$main_tmpdir" &&
    LOCAL_ROOT="$main_tmpdir" \
    TRACKING_ROOT="$main_tmpdir" \
    bash "$main_tmpdir/.claude/hooks/block-unsafe-project.sh" 2>/dev/null
  ))

  # Cleanup
  rm -rf "$main_tmpdir" "$feat_tmpdir"
  echo "$result"
}

# Test: multi-line `cd /tmp/feat-wt\ngit commit` from a main-repo cwd does NOT
# block. Pre-fix: extract_cd_target captured "/tmp/.../wt\ngit", failed [ -d ],
# is_on_main fell back to main → "main branch is protected". Post-fix: \n is
# decoded, target captures cleanly, is_on_main resolves to feat/test → allowed.
RESULT=$(run_extract_cd_target_test "main" "feat/test" 'cd FEAT_TMPDIR\ngit commit -m foo')
if [[ "$RESULT" != *"main branch is protected"* ]]; then
  pass "extract_cd_target: multi-line cd \\n git commit (issue #93) allowed"
else
  fail "extract_cd_target: multi-line cd \\n git commit should be allowed, got: $RESULT"
fi

# Test: same case with `cd /tmp/feat-wt && git commit` (single-line) — must
# also be allowed. Pins the existing-behavior baseline so the \n decoding
# change can't regress the && form.
RESULT=$(run_extract_cd_target_test "main" "feat/test" 'cd FEAT_TMPDIR && git commit -m foo')
if [[ "$RESULT" != *"main branch is protected"* ]]; then
  pass "extract_cd_target: single-line cd && git commit allowed (baseline)"
else
  fail "extract_cd_target: single-line cd && git commit should be allowed, got: $RESULT"
fi

# Test: the multi-line form with the FEATURE worktree on `main` (i.e., the
# cd target IS a main branch) must still be BLOCKED. Confirms extract_cd_target
# is correctly resolving to the cd target — not silently allowing everything.
RESULT=$(run_extract_cd_target_test "main" "main" 'cd FEAT_TMPDIR\ngit commit -m foo')
if [[ "$RESULT" == *"main branch is protected"* ]]; then
  pass "extract_cd_target: multi-line cd to main-branch worktree blocked"
else
  fail "extract_cd_target: multi-line cd to main-branch worktree should be blocked, got: $RESULT"
fi

echo ""
echo "=== Project hook: push-segment scoping (rules a/b) ==="

# Background: rules (a) and (b) used to scan the entire $COMMAND buffer, which
# false-positived on multi-statement commands like
# `git fetch origin main && git push -u origin feat/foo` — "origin main" in
# the fetch portion tripped rule (a). The fix scopes the regex to PUSH_ARGS
# (the bounded post-`git push` segment, mirroring block-unsafe-generic.sh).
# These tests pin both the regression cases (must ALLOW) and the BLOCK cases
# the fix must keep working.

# Regression case (this bug): fetch-then-push on a feature branch.
RESULT=$(run_main_protected_test "feat/foo" '{"execution": {"main_protected": true}}' "git fetch origin main && git push -u origin feat/foo")
if [[ "$RESULT" != *"Cannot push to main"* ]]; then
  pass "push-scope: fetch origin main && push -u origin feat/foo allowed"
else
  fail "push-scope: fetch origin main && push -u origin feat/foo should be allowed, got: $RESULT"
fi

# Regression case (semicolon variant of the same chain).
RESULT=$(run_main_protected_test "chore/foo" '{"execution": {"main_protected": true}}' "git fetch origin main; git push -u origin chore/foo")
if [[ "$RESULT" != *"Cannot push to main"* ]]; then
  pass "push-scope: fetch origin main; push -u origin chore/foo allowed"
else
  fail "push-scope: fetch origin main; push -u origin chore/foo should be allowed, got: $RESULT"
fi

# BLOCK: explicit `git push origin main` (rule a).
RESULT=$(run_main_protected_test "feat/test" '{"execution": {"main_protected": true}}' "git push origin main")
if [[ "$RESULT" == *"Cannot push to main"* ]]; then
  pass "push-scope: git push origin main blocked"
else
  fail "push-scope: git push origin main should be blocked, got: $RESULT"
fi

# BLOCK: master variant of rule (a).
RESULT=$(run_main_protected_test "feat/test" '{"execution": {"main_protected": true}}' "git push origin master")
if [[ "$RESULT" == *"Cannot push to main"* ]]; then
  pass "push-scope: git push origin master blocked"
else
  fail "push-scope: git push origin master should be blocked, got: $RESULT"
fi

# BLOCK: rule (a) with -u flag (flags must be skipped, target still detected).
RESULT=$(run_main_protected_test "feat/test" '{"execution": {"main_protected": true}}' "git push -u origin main")
if [[ "$RESULT" == *"Cannot push to main"* ]]; then
  pass "push-scope: git push -u origin main blocked"
else
  fail "push-scope: git push -u origin main should be blocked, got: $RESULT"
fi

# BLOCK: force-prefix form `+main`.
RESULT=$(run_main_protected_test "feat/test" '{"execution": {"main_protected": true}}' "git push origin +main")
if [[ "$RESULT" == *"Cannot push to main"* ]]; then
  pass "push-scope: git push origin +main blocked"
else
  fail "push-scope: git push origin +main should be blocked, got: $RESULT"
fi

# BLOCK: delete-refspec form `:main`.
RESULT=$(run_main_protected_test "feat/test" '{"execution": {"main_protected": true}}' "git push origin :main")
if [[ "$RESULT" == *"Cannot push to main"* ]]; then
  pass "push-scope: git push origin :main (delete-refspec) blocked"
else
  fail "push-scope: git push origin :main should be blocked, got: $RESULT"
fi

# BLOCK: bare HEAD:main (rule b — no `origin` token).
RESULT=$(run_main_protected_test "feat/test" '{"execution": {"main_protected": true}}' "git push HEAD:main")
if [[ "$RESULT" == *"Cannot push to main"* ]]; then
  pass "push-scope: git push HEAD:main blocked"
else
  fail "push-scope: git push HEAD:main should be blocked, got: $RESULT"
fi

# BLOCK: bare HEAD:master (rule b — master variant).
RESULT=$(run_main_protected_test "feat/test" '{"execution": {"main_protected": true}}' "git push HEAD:master")
if [[ "$RESULT" == *"Cannot push to main"* ]]; then
  pass "push-scope: git push HEAD:master blocked"
else
  fail "push-scope: git push HEAD:master should be blocked, got: $RESULT"
fi

echo ""
echo "=== Project hook: rule (c) push-segment scoping (issue #81) ==="

# Background: rule (c) ("naked push while on main") used to scan the entire
# $COMMAND for `origin[[:space:]]`. That false-positived whenever the literal
# string `git push` appeared inside a quoted argument (grep/sed/echo/awk
# scanning a file or message that mentions "git push") AND there was no
# `origin ` substring elsewhere in the command AND the agent was on main.
# The fix scopes rule (c) to PUSH_ARGS — the bounded post-`git push` segment.
# These tests pin the BLOCK cases that must keep working AND the ALLOW cases
# the fix is supposed to unblock.

# BLOCK (true naked push, the case rule c was designed for): on main, bare
# `git push` defaults to pushing the current branch (main). Must still block.
RESULT=$(run_main_protected_test "main" '{"execution": {"main_protected": true}}' "git push")
if [[ "$RESULT" == *"Cannot push to main"* ]]; then
  pass "rule-c: naked git push on main blocked"
else
  fail "rule-c: naked git push on main should be blocked, got: $RESULT"
fi

# BLOCK (flag-only push on main): `git push -u` has no positional args, so
# PUSH_ARGS extraction yields empty. Must still block.
RESULT=$(run_main_protected_test "main" '{"execution": {"main_protected": true}}' "git push -u")
if [[ "$RESULT" == *"Cannot push to main"* ]]; then
  pass "rule-c: git push -u (flag only) on main blocked"
else
  fail "rule-c: git push -u (flag only) on main should be blocked, got: $RESULT"
fi

# ALLOW (the false-positive from issue #81): on main, grep for the literal
# string "git push" inside a file. The hook's outer gate matches `git push"`
# (where the trailing `"` closes a quoted shell arg). Pre-fix, rule (c) then
# scanned $COMMAND, saw no `origin ` substring, and blocked. PUSH_ARGS scoping
# fixes this — PUSH_ARGS contains the trailing tokens after `git push`, which
# is non-empty (`" some-file.sh"`), so rule (c) skips. Note: JSON encoding of
# the embedded double-quote requires `\"` here so the test fixture's bash-to-
# JSON interpolation produces a literal `"` in the extracted command.
RESULT=$(run_main_protected_test "main" '{"execution": {"main_protected": true}}' 'grep -n \"git push\" some-file.sh')
if [[ "$RESULT" != *"Cannot push to main"* ]]; then
  pass "rule-c: grep \"git push\" some-file.sh on main allowed (issue #81)"
else
  fail "rule-c: grep \"git push\" some-file.sh on main should be allowed, got: $RESULT"
fi

# ALLOW (echo with literal substring): on main, echo a string that mentions
# "git push". Same shape as the grep case — quoted-argument false-positive.
RESULT=$(run_main_protected_test "main" '{"execution": {"main_protected": true}}' 'echo \"remember to git push\" >> notes.md')
if [[ "$RESULT" != *"Cannot push to main"* ]]; then
  pass "rule-c: echo \"remember to git push\" on main allowed"
else
  fail "rule-c: echo \"remember to git push\" on main should be allowed, got: $RESULT"
fi

# ALLOW (feature-branch push while branch is main): rule (c) keys off
# is_on_main, but PUSH_ARGS contains positional args (`origin feat/foo`), so
# rule (c) must skip. Rules (a)/(b) inspect PUSH_ARGS and find no main/master,
# so they also pass. End result: allowed.
RESULT=$(run_main_protected_test "main" '{"execution": {"main_protected": true}}' "git push -u origin feat/foo")
if [[ "$RESULT" != *"Cannot push to main"* ]]; then
  pass "rule-c: git push -u origin feat/foo (while on main) allowed"
else
  fail "rule-c: git push -u origin feat/foo (while on main) should be allowed, got: $RESULT"
fi

# ALLOW (the original #58 case, plus #81 scoping check): fetch-then-push of
# a feature branch while on main. The fetch portion contains `origin main`,
# but rule (a) is scoped to PUSH_ARGS so it doesn't fire; rule (c) sees
# PUSH_ARGS=`origin feat/foo` (non-empty) so it doesn't fire either.
RESULT=$(run_main_protected_test "main" '{"execution": {"main_protected": true}}' "git fetch origin main && git push -u origin feat/foo")
if [[ "$RESULT" != *"Cannot push to main"* ]]; then
  pass "rule-c: git fetch origin main && git push -u origin feat/foo (while on main) allowed"
else
  fail "rule-c: git fetch origin main && git push -u origin feat/foo (while on main) should be allowed, got: $RESULT"
fi

echo ""


echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
