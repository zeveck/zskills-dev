#!/bin/bash
# Tests for hooks/block-unsafe-generic.sh
# Run from repo root: bash tests/test-hooks.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/hooks/block-unsafe-generic.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  printf '\033[32m  PASS\033[0m %s\n' "$1"
  ((PASS_COUNT++))
}

fail() {
  printf '\033[31m  FAIL\033[0m %s\n' "$1"
  ((FAIL_COUNT++))
}

# --- Helper: run hook with a Bash command, expect deny ---
expect_deny() {
  local label="$1"
  local cmd="$2"
  local result
  result=$(echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$cmd\"}}" | bash "$HOOK" 2>/dev/null)
  if [[ "$result" == *"permissionDecision"*"deny"* ]]; then
    pass "deny: $label"
  else
    fail "deny: $label — expected deny, got: $result"
  fi
}

# --- Helper: run hook with a Bash command, expect allow (empty output) ---
expect_allow() {
  local label="$1"
  local cmd="$2"
  local result
  result=$(echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$cmd\"}}" | bash "$HOOK" 2>/dev/null)
  if [[ -z "$result" ]]; then
    pass "allow: $label"
  else
    fail "allow: $label — got unexpected output: $result"
  fi
}

echo "=== Hook deny patterns ==="

# 1. git stash drop / clear — destroys stashed work
expect_deny "git stash drop" "git stash drop"
expect_deny "git stash clear" "git stash clear"

# 1b. git stash that CREATES a stash (modifies working tree) — counterfactual
# testing pattern the CLAUDE.md rule bans; concrete past failure was a
# pre-commit reviewer unstaging caller's staged files via stash-pop.
expect_deny "git stash (bare)" "git stash"
expect_deny "git stash -u" "git stash -u"
expect_deny "git stash -u -m msg" "git stash -u -m pre-check-stash"
expect_deny "git stash push -m" "git stash push -m something"
expect_deny "git stash save" "git stash save old-style-label"
# Read / recovery operations stay allowed
expect_allow "git stash apply" "git stash apply"
expect_allow "git stash list" "git stash list"
expect_allow "git stash show" "git stash show"
expect_allow "git stash pop" "git stash pop"
# git stash create and store operate on the object db, not the working tree
expect_allow "git stash create" "git stash create"

# 1c. Overmatch-prevention: text that MENTIONS stash but isn't invoking it.
# These broke before command-boundary gating — hook matched on any substring
# containing "git stash" (commit messages, grep args, echo/printf content,
# even the hook's own error message output).
expect_allow "commit msg w/ stash text" "git commit -m msg-about-git-stash-push"
expect_allow "echo w/ stash text" "echo git-stash-push-blocked"
expect_allow "grep stash in file" "grep stash file.md"
expect_allow "printf w/ stash text" "printf %s git-stash-push"

# 1d. Command-boundary matches: real invocations after shell separators.
expect_deny "&& git stash" "cd foo && git stash"
expect_deny "; git stash" "echo ok; git stash"

# 2. git checkout -- file
expect_deny "git checkout -- file" "git checkout -- file.js"

# 3. git restore file
expect_deny "git restore file" "git restore file.js"

# 4. git clean -fd
expect_deny "git clean -fd" "git clean -fd"

# 5. git reset --hard
expect_deny "git reset --hard" "git reset --hard"

# 6. kill -9 / killall / pkill
expect_deny "kill -9 1234" "kill -9 1234"
expect_deny "killall node" "killall node"
expect_deny "pkill node" "pkill node"

# 7. fuser -k
expect_deny "fuser -k 8080" "fuser -k 8080"

# 8. rm -rf
expect_deny "rm -rf /tmp/foo" "rm -rf /tmp/foo"

# 9. git add . / -A / --all
expect_deny "git add ." "git add . "
expect_deny "git add -A" "git add -A"
expect_deny "git add --all" "git add --all"

# 10. git commit --no-verify
expect_deny "git commit --no-verify" "git commit --no-verify -m \"msg\""

echo ""
echo "=== Hook allow patterns ==="

expect_allow "git status" "git status"
expect_allow "git log --oneline" "git log --oneline"
expect_allow "git add file.js" "git add file.js"
expect_allow "git commit -m msg" "git commit -m \"msg\""
# (bare git stash moved to deny list — see above)
expect_allow "rm file.js (no -rf)" "rm file.js"
expect_allow "kill 1234 (no -9)" "kill 1234"

echo ""
echo "=== Push: block main/master ==="

# Bare push (no remote/refspec) — the hook falls back to `git branch --show-current`.
# Test BOTH branch states to prove the fallback actually differentiates:
# - On main: BLOCK (agents shouldn't push main)
# - On feature branch: ALLOW (feature branches are fine)
# The outer env's branch state is unreliable (CI runs on PR branches), so each
# test creates a controlled temp git repo.
bare_push_test() {
  local label="$1" branch="$2" expected="$3"
  local tmp
  tmp=$(mktemp -d)
  (cd "$tmp" && git init -q -b "$branch" 2>/dev/null \
    || (cd "$tmp" && git init -q && git checkout -b "$branch" 2>/dev/null))
  local result
  result=$(cd "$tmp" && echo '{"tool_name":"Bash","tool_input":{"command":"git push"}}' | bash "$HOOK" 2>/dev/null)
  rm -rf "$tmp"
  if [ "$expected" = "deny" ]; then
    if [[ "$result" == *"permissionDecision"*"deny"* ]]; then
      pass "$label"
    else
      fail "$label — expected deny, got: $result"
    fi
  else
    if [[ "$result" != *"permissionDecision"*"deny"* ]]; then
      pass "$label"
    else
      fail "$label — expected allow, got: $result"
    fi
  fi
}

bare_push_test "deny: git push (bare, on main)" "main" "deny"
bare_push_test "deny: git push (bare, on master)" "master" "deny"
bare_push_test "allow: git push (bare, on feature branch)" "feat/test" "allow"

# Explicit target tests — don't depend on current branch (parser extracts target)
expect_deny "git push origin main" "git push origin main"
expect_deny "git push -u origin main" "git push -u origin main"

echo ""
echo "=== Non-Bash tool_name ==="

result=$(echo '{"tool_name":"Read","tool_input":{"file_path":"/tmp/foo"}}' | bash "$HOOK" 2>/dev/null)
if [[ -z "$result" ]]; then
  pass "non-Bash tool_name exits silently"
else
  fail "non-Bash tool_name — got unexpected output: $result"
fi

echo ""
echo "=== Edge cases ==="

# Empty command field
result=$(echo '{"tool_name":"Bash","tool_input":{"command":""}}' | bash "$HOOK" 2>/dev/null)
if [[ -z "$result" ]]; then
  pass "empty command exits silently"
else
  fail "empty command — got unexpected output: $result"
fi

# tool_name with extra whitespace in JSON
result=$(echo '{"tool_name": "Bash","tool_input":{"command":"git reset --hard"}}' | bash "$HOOK" 2>/dev/null)
if [[ "$result" == *"permissionDecision"*"deny"* ]]; then
  pass "tool_name with space after colon still detected"
else
  fail "tool_name with space after colon — expected deny, got: $result"
fi

echo ""

# ─── Project hook test harness ───
PROJECT_HOOK="hooks/block-unsafe-project.sh.template"
TEST_TMPDIR=""

setup_project_test() {
  TEST_TMPDIR=$(mktemp -d)
  mkdir -p "$TEST_TMPDIR/.claude/hooks"
  mkdir -p "$TEST_TMPDIR/.zskills/tracking"

  # Copy and configure the hook template
  cp "$PROJECT_HOOK" "$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh"
  sed -i 's|{{UNIT_TEST_CMD}}|npm test|g' "$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh"
  sed -i 's|{{FULL_TEST_CMD}}|npm run test:all|g' "$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh"
  sed -i 's|{{UI_FILE_PATTERNS}}|src/ui/|g' "$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh"

  # Create mock package.json with test script
  printf '{"scripts":{"test":"vitest","test:all":"vitest run"}}\n' > "$TEST_TMPDIR/package.json"

  # Create mock transcript with test command AND pipeline ID declaration.
  # ZSKILLS_PIPELINE_ID triggers the transcript-based pipeline association
  # (tier 2) so tracking enforcement fires for orchestrator-on-main tests.
  printf 'ZSKILLS_PIPELINE_ID=run-plan.test-plan\nnpm run test:all\n' > "$TEST_TMPDIR/.transcript"

  # Initialize git repo (needed for git diff --cached, git-common-dir, etc.)
  (cd "$TEST_TMPDIR" && git init -q && git add -A && git commit -q -m "init" 2>/dev/null)
}

teardown_project_test() {
  [ -n "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
  [ -n "$TEST_REMOTE" ] && rm -rf "$TEST_REMOTE"
  TEST_TMPDIR=""
  TEST_REMOTE=""
}

# Helper: set up a bare remote so git diff @{u}..HEAD works in push tests
setup_push_remote() {
  TEST_REMOTE=$(mktemp -d)
  # Detect the actual branch name (master vs main depending on git config).
  # Hardcoding origin/master broke when init.defaultBranch=main was set in CI.
  (cd "$TEST_TMPDIR" && \
   git clone --bare "$TEST_TMPDIR" "$TEST_REMOTE" 2>/dev/null && \
   git remote add origin "$TEST_REMOTE" 2>/dev/null && \
   git fetch origin 2>/dev/null && \
   _CB=$(git branch --show-current 2>/dev/null) && \
   git branch -u "origin/$_CB" 2>/dev/null)
}

expect_project_deny() {
  local cmd="$1"
  local json="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$cmd\"},\"transcript_path\":\"$TEST_TMPDIR/.transcript\"}"
  local result
  result=$(echo "$json" | REPO_ROOT="$TEST_TMPDIR" TRACKING_ROOT="$TEST_TMPDIR" bash -c "cd '$TEST_TMPDIR' && bash '$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh'" 2>/dev/null)
  if [[ "$result" == *"permissionDecision"*"deny"* ]]; then
    pass "$cmd → denied (expected)"
  else
    fail "$cmd → allowed (expected deny)"
  fi
}

expect_project_allow() {
  local cmd="$1"
  local json="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$cmd\"},\"transcript_path\":\"$TEST_TMPDIR/.transcript\"}"
  local result
  result=$(echo "$json" | REPO_ROOT="$TEST_TMPDIR" TRACKING_ROOT="$TEST_TMPDIR" bash -c "cd '$TEST_TMPDIR' && bash '$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh'" 2>/dev/null)
  if [[ -z "$result" ]] || [[ "$result" != *"deny"* ]]; then
    pass "$cmd → allowed (expected)"
  else
    fail "$cmd → denied (expected allow)"
  fi
}

echo "=== Project hook: tracking file protection ==="

setup_project_test

# Block recursive rm of tracking directory
expect_project_deny "rm -rf .zskills/tracking"
expect_project_deny "rm -r .zskills/tracking"
expect_project_deny "rm -fr .zskills/tracking"

# Allow individual file deletion within tracking directory
expect_project_allow "rm .zskills/tracking/requires.foo"
expect_project_allow "rm -f .zskills/tracking/requires.old"

# Block execution of clear-tracking script
expect_project_deny "bash scripts/clear-tracking.sh"
expect_project_deny "sh scripts/clear-tracking.sh"
expect_project_deny "./scripts/clear-tracking.sh"

# Allow reading clear-tracking script
expect_project_allow "cat scripts/clear-tracking.sh"
expect_project_allow "grep -n confirm scripts/clear-tracking.sh"

teardown_project_test

echo ""
echo "=== Project hook: delegation enforcement ==="

# Test: requires.X without fulfilled.X blocks git commit
setup_project_test
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.test-plan"
# Stage a code file so it's not content-only
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
expect_project_deny "git commit -m test"
teardown_project_test

# Test: requires.X with fulfilled.X allows git commit
setup_project_test
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.test-plan"
touch "$TEST_TMPDIR/.zskills/tracking/fulfilled.verify-changes.run-plan.test-plan"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
expect_project_allow "git commit -m test"
teardown_project_test

# Test: delegation blocks git cherry-pick too
setup_project_test
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.test-plan"
expect_project_deny "git cherry-pick abc123"
teardown_project_test

echo ""
echo "=== Project hook: step enforcement ==="

# Test: step.X.implement without step.X.verify blocks
setup_project_test
touch "$TEST_TMPDIR/.zskills/tracking/step.run-plan.test-plan.implement"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
expect_project_deny "git commit -m test"
teardown_project_test

# Test: step.X.implement with step.X.verify but no step.X.report blocks
setup_project_test
touch "$TEST_TMPDIR/.zskills/tracking/step.run-plan.test-plan.implement"
touch "$TEST_TMPDIR/.zskills/tracking/step.run-plan.test-plan.verify"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
expect_project_deny "git commit -m test"
teardown_project_test

# Test: step.X.implement + step.X.verify + step.X.report allows
setup_project_test
touch "$TEST_TMPDIR/.zskills/tracking/step.run-plan.test-plan.implement"
touch "$TEST_TMPDIR/.zskills/tracking/step.run-plan.test-plan.verify"
touch "$TEST_TMPDIR/.zskills/tracking/step.run-plan.test-plan.report"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
expect_project_allow "git commit -m test"
teardown_project_test

# Test: phasestep.* markers are ignored (not enforced)
setup_project_test
touch "$TEST_TMPDIR/.zskills/tracking/phasestep.run-plan.test-plan.implement"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
expect_project_allow "git commit -m test"
teardown_project_test

# Test: step enforcement on cherry-pick
setup_project_test
touch "$TEST_TMPDIR/.zskills/tracking/step.run-plan.test-plan.implement"
expect_project_deny "git cherry-pick abc123"
teardown_project_test

echo ""
echo "=== Project hook: no staleness bypass ==="

# Test: stale requires.* (>8h) STILL blocks — no staleness bypass
setup_project_test
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.test-plan"
# Make requires file look old (>8h = 480min)
touch -t 202501010000 "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.test-plan"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
expect_project_deny "git commit -m test"
teardown_project_test

# Test: fresh requires.* also blocks (same behavior as stale)
setup_project_test
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.test-plan"
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
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.test-plan"
(cd "$TEST_TMPDIR" && echo "content" > readme.md && git add readme.md)
expect_project_allow "git commit -m test"
teardown_project_test

echo ""
echo "=== Project hook: .zskills-tracked pipeline association ==="

# Test: .zskills-tracked file associates agent with pipeline
setup_project_test
printf 'run-plan.thermal-domain\n' > "$TEST_TMPDIR/.zskills-tracked"
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.thermal-domain"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
# Remove transcript so ONLY .zskills-tracked provides the association
rm -f "$TEST_TMPDIR/.transcript"
printf 'npm run test:all\n' > "$TEST_TMPDIR/.transcript"
expect_project_deny "git commit -m test"
teardown_project_test

# Test: .zskills-tracked with fulfilled requirement allows commit
setup_project_test
printf 'run-plan.thermal-domain\n' > "$TEST_TMPDIR/.zskills-tracked"
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.thermal-domain"
touch "$TEST_TMPDIR/.zskills/tracking/fulfilled.verify-changes.run-plan.thermal-domain"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
rm -f "$TEST_TMPDIR/.transcript"
printf 'npm run test:all\n' > "$TEST_TMPDIR/.transcript"
expect_project_allow "git commit -m test"
teardown_project_test

# Test: no .zskills-tracked AND no pipeline in transcript → skip enforcement
setup_project_test
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.thermal-domain"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
# Transcript has test command but NO pipeline skill
rm -f "$TEST_TMPDIR/.transcript"
printf 'npm run test:all\n' > "$TEST_TMPDIR/.transcript"
expect_project_allow "git commit -m test"
teardown_project_test

echo ""
echo "=== Project hook: pipeline scoping (suffix matching) ==="

# Test: Pipeline A's markers don't block Pipeline B
setup_project_test
printf 'run-plan.pipeline-B\n' > "$TEST_TMPDIR/.zskills-tracked"
# Create unfulfilled requirement for pipeline A (different pipeline)
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.pipeline-A"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
rm -f "$TEST_TMPDIR/.transcript"
printf 'npm run test:all\n' > "$TEST_TMPDIR/.transcript"
expect_project_allow "git commit -m test"
teardown_project_test

# Test: Same pipeline's markers DO block
setup_project_test
printf 'run-plan.pipeline-B\n' > "$TEST_TMPDIR/.zskills-tracked"
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.pipeline-B"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
rm -f "$TEST_TMPDIR/.transcript"
printf 'npm run test:all\n' > "$TEST_TMPDIR/.transcript"
expect_project_deny "git commit -m test"
teardown_project_test

# Test: Transcript ZSKILLS_PIPELINE_ID scopes to specific pipeline
setup_project_test
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.pipeline-A"
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.pipeline-B"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
# Transcript declares pipeline A → only pipeline A markers checked
rm -f "$TEST_TMPDIR/.transcript"
printf 'npm run test:all\nZSKILLS_PIPELINE_ID=run-plan.pipeline-A\n' > "$TEST_TMPDIR/.transcript"
# Pipeline A unfulfilled → blocked
expect_project_deny "git commit -m test"
teardown_project_test

# Test: Transcript pipeline ID with fulfilled marker allows commit
setup_project_test
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.pipeline-A"
touch "$TEST_TMPDIR/.zskills/tracking/fulfilled.verify-changes.run-plan.pipeline-A"
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.pipeline-B"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
# Transcript declares pipeline A → pipeline B's unfulfilled marker invisible
rm -f "$TEST_TMPDIR/.transcript"
printf 'npm run test:all\nZSKILLS_PIPELINE_ID=run-plan.pipeline-A\n' > "$TEST_TMPDIR/.transcript"
expect_project_allow "git commit -m test"
teardown_project_test

# Test: Transcript last-match wins (sequential runs in same session)
setup_project_test
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.pipeline-A"
touch "$TEST_TMPDIR/.zskills/tracking/fulfilled.verify-changes.run-plan.pipeline-A"
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.pipeline-B"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
# Two pipeline IDs in transcript — last one wins (pipeline B)
rm -f "$TEST_TMPDIR/.transcript"
printf 'npm run test:all\nZSKILLS_PIPELINE_ID=run-plan.pipeline-A\nZSKILLS_PIPELINE_ID=run-plan.pipeline-B\n' > "$TEST_TMPDIR/.transcript"
# Pipeline B unfulfilled ��� blocked (even though pipeline A is fulfilled)
expect_project_deny "git commit -m test"
teardown_project_test

# Test: Step scoping — pipeline B's impl marker doesn't block pipeline A
setup_project_test
printf 'run-plan.pipeline-A\n' > "$TEST_TMPDIR/.zskills-tracked"
touch "$TEST_TMPDIR/.zskills/tracking/step.run-plan.pipeline-B.implement"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
rm -f "$TEST_TMPDIR/.transcript"
printf 'npm run test:all\n' > "$TEST_TMPDIR/.transcript"
expect_project_allow "git commit -m test"
teardown_project_test

# Test: Suffix matching prevents false positives (ID "plan" does NOT match "run-plan.thermal-domain")
setup_project_test
printf 'plan\n' > "$TEST_TMPDIR/.zskills-tracked"
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
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.test-plan"
# Add a code file commit after the remote baseline so @{u}..HEAD has code
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js && git commit -q -m "code")
expect_project_deny "git push origin main"
teardown_project_test

# Test: git push allowed when requirement fulfilled
setup_project_test
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.test-plan"
touch "$TEST_TMPDIR/.zskills/tracking/fulfilled.verify-changes.run-plan.test-plan"
expect_project_allow "git push origin main"
teardown_project_test

# Test: git push blocked by step without verification
setup_project_test
setup_push_remote
touch "$TEST_TMPDIR/.zskills/tracking/step.run-plan.test-plan.implement"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js && git commit -q -m "code")
expect_project_deny "git push origin main"
teardown_project_test

# Test: git push with pipeline scoping
setup_project_test
printf 'run-plan.pipeline-A\n' > "$TEST_TMPDIR/.zskills-tracked"
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.pipeline-B"
rm -f "$TEST_TMPDIR/.transcript"
printf 'npm run test:all\n' > "$TEST_TMPDIR/.transcript"
expect_project_allow "git push origin main"
teardown_project_test

# Test: content-only push allowed despite unfulfilled requirements
setup_project_test
setup_push_remote
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.test-plan"
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
echo "=== Project hook: main_protected enforcement ==="

# Helper: run hook in a temp git repo with specific branch and config
run_main_protected_test() {
  local branch="$1"
  local config_content="$2"
  local cmd="$3"
  local test_tmpdir
  test_tmpdir=$(mktemp -d)

  mkdir -p "$test_tmpdir/.claude/hooks"
  mkdir -p "$test_tmpdir/.zskills/tracking"

  # Copy and configure the hook template
  cp "$PROJECT_HOOK" "$test_tmpdir/.claude/hooks/block-unsafe-project.sh"
  sed -i 's|{{UNIT_TEST_CMD}}|npm test|g' "$test_tmpdir/.claude/hooks/block-unsafe-project.sh"
  sed -i 's|{{FULL_TEST_CMD}}|npm run test:all|g' "$test_tmpdir/.claude/hooks/block-unsafe-project.sh"
  sed -i 's|{{UI_FILE_PATTERNS}}|src/ui/|g' "$test_tmpdir/.claude/hooks/block-unsafe-project.sh"

  # Create mock package.json and transcript
  printf '{"scripts":{"test":"vitest","test:all":"vitest run"}}\n' > "$test_tmpdir/package.json"
  printf 'npm run test:all\n' > "$test_tmpdir/.transcript"

  # Initialize git repo on specified branch
  (cd "$test_tmpdir" && git init -q && git checkout -b "$branch" 2>/dev/null && git add -A && git commit -q -m "init" 2>/dev/null)

  # Write config if provided
  if [ -n "$config_content" ]; then
    cat > "$test_tmpdir/.claude/zskills-config.json" <<EOF
$config_content
EOF
  fi

  local json="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$cmd\"},\"transcript_path\":\"$test_tmpdir/.transcript\"}"
  # Override LOCAL_ROOT and TRACKING_ROOT so the hook resolves to the fixture,
  # not the caller's worktree. Without these, the hook's push-path tracking
  # block reads .zskills-tracked + tracking markers from wherever the test was
  # invoked from (typically a zskills-tracked worktree with accumulated commits),
  # firing the tracking guard before the main_protected check this test asserts.
  local result
  result=$(echo "$json" | \
    REPO_ROOT="$test_tmpdir" \
    LOCAL_ROOT="$test_tmpdir" \
    TRACKING_ROOT="$test_tmpdir" \
    bash "$test_tmpdir/.claude/hooks/block-unsafe-project.sh" 2>/dev/null)

  # Cleanup
  rm -rf "$test_tmpdir"
  echo "$result"
}

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

# Test: push tracking works before first push (no upstream) — code-files detection fallback
push_tracking_tmpdir=$(mktemp -d)
mkdir -p "$push_tracking_tmpdir/.claude/hooks"
mkdir -p "$push_tracking_tmpdir/.zskills/tracking"
cp "$PROJECT_HOOK" "$push_tracking_tmpdir/.claude/hooks/block-unsafe-project.sh"
sed -i 's|{{UNIT_TEST_CMD}}|npm test|g' "$push_tracking_tmpdir/.claude/hooks/block-unsafe-project.sh"
sed -i 's|{{FULL_TEST_CMD}}|npm run test:all|g' "$push_tracking_tmpdir/.claude/hooks/block-unsafe-project.sh"
sed -i 's|{{UI_FILE_PATTERNS}}|src/ui/|g' "$push_tracking_tmpdir/.claude/hooks/block-unsafe-project.sh"
printf '{"scripts":{"test":"vitest","test:all":"vitest run"}}\n' > "$push_tracking_tmpdir/package.json"
printf 'npm run test:all\n' > "$push_tracking_tmpdir/.transcript"
(cd "$push_tracking_tmpdir" && git init -q && git checkout -b main 2>/dev/null && git add -A && git commit -q -m "init" 2>/dev/null)
(cd "$push_tracking_tmpdir" && git checkout -b feat/test 2>/dev/null && echo "var x=1;" > app.js && git add app.js && git commit -q -m "add code" 2>/dev/null)
# Pipeline association via .zskills-tracked (required by the modern push tracking block)
printf 'run-plan.test-plan\n' > "$push_tracking_tmpdir/.zskills-tracked"
# Add a requires file without fulfilled — should block push with code files
touch "$push_tracking_tmpdir/.zskills/tracking/requires.verify-changes.run-plan.test-plan"
PUSH_JSON="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push -u origin feat/test\"},\"transcript_path\":\"$push_tracking_tmpdir/.transcript\"}"
PUSH_RESULT=$(cd "$push_tracking_tmpdir" && echo "$PUSH_JSON" | REPO_ROOT="$push_tracking_tmpdir" LOCAL_ROOT="$push_tracking_tmpdir" TRACKING_ROOT="$push_tracking_tmpdir" bash "$push_tracking_tmpdir/.claude/hooks/block-unsafe-project.sh" 2>/dev/null)
if [[ "$PUSH_RESULT" == *"Required skill invocation"* ]] || [[ "$PUSH_RESULT" == *"not yet fulfilled"* ]]; then
  pass "push tracking: no-upstream fallback detects code files and enforces tracking"
else
  fail "push tracking: no-upstream fallback should detect code files, got: $PUSH_RESULT"
fi
rm -rf "$push_tracking_tmpdir"


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

LAND_SCRIPT="$REPO_ROOT/scripts/land-phase.sh"

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

# ─── block-agents.sh.template tests ───
echo "=== block-agents.sh — agents.min_model enforcement ==="

AGENTS_HOOK="$REPO_ROOT/hooks/block-agents.sh.template"

# Helper: run agent hook with tool_name=Agent, optional model field
run_agent_hook() {
  local model_field="$1"    # e.g. '"model":"haiku"' or ""
  local config_json="$2"    # content of .claude/zskills-config.json or ""
  local tmp_repo
  tmp_repo=$(mktemp -d)
  mkdir -p "$tmp_repo/.claude"
  (cd "$tmp_repo" && git init -q 2>/dev/null)

  if [ -n "$config_json" ]; then
    printf '%s\n' "$config_json" > "$tmp_repo/.claude/zskills-config.json"
  fi

  local tool_input
  if [ -n "$model_field" ]; then
    tool_input="{\"tool_name\":\"Agent\",\"tool_input\":{${model_field},\"prompt\":\"Do something\"}}"
  else
    tool_input="{\"tool_name\":\"Agent\",\"tool_input\":{\"prompt\":\"Do something\"}}"
  fi

  local result
  result=$(echo "$tool_input" | REPO_ROOT="$tmp_repo" bash "$AGENTS_HOOK" 2>/dev/null)
  rm -rf "$tmp_repo"
  echo "$result"
}

# 1. No config → pass through (no enforcement)
result=$(run_agent_hook '"model":"haiku"' "")
if [[ -z "$result" ]]; then
  pass "no config → always allow"
else
  fail "no config → expected allow, got: $result"
fi

# 2. min_model=sonnet, dispatch model=haiku → deny
CONFIG_SONNET='{"agents":{"min_model":"claude-sonnet-4-6"}}'
result=$(run_agent_hook '"model":"claude-haiku-4-5"' "$CONFIG_SONNET")
if [[ "$result" == *"permissionDecision"*"deny"* ]]; then
  pass "min_model=sonnet, model=haiku → deny"
else
  fail "min_model=sonnet, model=haiku → expected deny, got: $result"
fi

# 3. min_model=sonnet, dispatch model=sonnet → allow
result=$(run_agent_hook '"model":"claude-sonnet-4-6"' "$CONFIG_SONNET")
if [[ -z "$result" ]]; then
  pass "min_model=sonnet, model=sonnet → allow"
else
  fail "min_model=sonnet, model=sonnet → expected allow, got: $result"
fi

# 4. min_model=sonnet, dispatch model=opus → allow
result=$(run_agent_hook '"model":"claude-opus-4-6"' "$CONFIG_SONNET")
if [[ -z "$result" ]]; then
  pass "min_model=sonnet, model=opus → allow"
else
  fail "min_model=sonnet, model=opus → expected allow, got: $result"
fi

# 5. min_model=sonnet, no model in tool_input → allow (unknown=0, pass-through)
result=$(run_agent_hook "" "$CONFIG_SONNET")
if [[ -z "$result" ]]; then
  pass "min_model=sonnet, no model field → allow (residual case)"
else
  fail "min_model=sonnet, no model field → expected allow, got: $result"
fi

# 6. Non-Agent tool_name → ignore entirely
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | bash "$AGENTS_HOOK" 2>/dev/null)
if [[ -z "$result" ]]; then
  pass "non-Agent tool_name → pass through (not our concern)"
else
  fail "non-Agent tool_name → expected silent pass, got: $result"
fi

# 7. min_model=haiku, dispatch model=haiku → allow (haiku meets haiku)
CONFIG_HAIKU='{"agents":{"min_model":"claude-haiku-4-5"}}'
result=$(run_agent_hook '"model":"claude-haiku-4-5"' "$CONFIG_HAIKU")
if [[ -z "$result" ]]; then
  pass "min_model=haiku, model=haiku → allow"
else
  fail "min_model=haiku, model=haiku → expected allow, got: $result"
fi

# 8. Unknown model family → always allow (future-proofing)
result=$(run_agent_hook '"model":"claude-nova-4-6"' "$CONFIG_SONNET")
if [[ -z "$result" ]]; then
  pass "unknown model family (claude-nova) → allow (ordinal=0 passes)"
else
  fail "unknown model family → expected allow, got: $result"
fi

# ─── auto/inherit resolution tests ───
# Helper: run agent hook with transcript_path in the hook input payload.
run_agent_hook_with_transcript() {
  local model_field="$1"       # e.g. '"model":"haiku"' or ""
  local config_json="$2"       # config content
  local transcript_content="$3" # JSONL lines for the transcript
  local tmp_repo tmp_transcript
  tmp_repo=$(mktemp -d)
  tmp_transcript=$(mktemp)
  mkdir -p "$tmp_repo/.claude"
  (cd "$tmp_repo" && git init -q 2>/dev/null)

  if [ -n "$config_json" ]; then
    printf '%s\n' "$config_json" > "$tmp_repo/.claude/zskills-config.json"
  fi
  printf '%s\n' "$transcript_content" > "$tmp_transcript"

  local tool_input
  if [ -n "$model_field" ]; then
    tool_input="{\"tool_name\":\"Agent\",\"transcript_path\":\"$tmp_transcript\",\"tool_input\":{${model_field},\"prompt\":\"Do something\"}}"
  else
    tool_input="{\"tool_name\":\"Agent\",\"transcript_path\":\"$tmp_transcript\",\"tool_input\":{\"prompt\":\"Do something\"}}"
  fi

  local result
  result=$(echo "$tool_input" | REPO_ROOT="$tmp_repo" bash "$AGENTS_HOOK" 2>/dev/null)
  rm -rf "$tmp_repo" "$tmp_transcript"
  echo "$result"
}

# 9. min_model=auto + transcript says opus + dispatch=sonnet → deny
CONFIG_AUTO='{"agents":{"min_model":"auto"}}'
TRANSCRIPT_OPUS='{"role":"assistant","model":"claude-opus-4-6","content":"hi"}'
result=$(run_agent_hook_with_transcript '"model":"claude-sonnet-4-6"' "$CONFIG_AUTO" "$TRANSCRIPT_OPUS")
if [[ "$result" == *"permissionDecision"*"deny"* ]]; then
  pass "min_model=auto (resolves to opus), model=sonnet → deny"
else
  fail "min_model=auto resolved to opus, sonnet dispatch → expected deny, got: $result"
fi

# 10. min_model=auto + transcript says opus + dispatch=opus → allow
result=$(run_agent_hook_with_transcript '"model":"claude-opus-4-6"' "$CONFIG_AUTO" "$TRANSCRIPT_OPUS")
if [[ -z "$result" ]]; then
  pass "min_model=auto (resolves to opus), model=opus → allow"
else
  fail "min_model=auto resolved to opus, opus dispatch → expected allow, got: $result"
fi

# 11. min_model=inherit alias works the same as auto
CONFIG_INHERIT='{"agents":{"min_model":"inherit"}}'
result=$(run_agent_hook_with_transcript '"model":"claude-sonnet-4-6"' "$CONFIG_INHERIT" "$TRANSCRIPT_OPUS")
if [[ "$result" == *"permissionDecision"*"deny"* ]]; then
  pass "min_model=inherit (alias of auto) → resolves same"
else
  fail "min_model=inherit → expected same resolution as auto, got: $result"
fi

# 12. min_model=auto + transcript unreadable → falls back to sonnet floor (blocks haiku, allows sonnet)
# Simulate an unresolvable auto by omitting transcript_path entirely
tmp_repo=$(mktemp -d)
mkdir -p "$tmp_repo/.claude"
(cd "$tmp_repo" && git init -q 2>/dev/null)
printf '%s\n' "$CONFIG_AUTO" > "$tmp_repo/.claude/zskills-config.json"
result=$(echo '{"tool_name":"Agent","tool_input":{"model":"claude-haiku-4-5","prompt":"x"}}' \
  | REPO_ROOT="$tmp_repo" bash "$AGENTS_HOOK" 2>/dev/null)
rm -rf "$tmp_repo"
if [[ "$result" == *"permissionDecision"*"deny"* ]]; then
  pass "min_model=auto, no transcript_path → falls back to sonnet floor (blocks haiku)"
else
  fail "min_model=auto, no transcript_path → expected fallback deny, got: $result"
fi

# 13. min_model=auto + transcript says sonnet + dispatch=sonnet → allow (session matches)
TRANSCRIPT_SONNET='{"role":"assistant","model":"claude-sonnet-4-6","content":"hi"}'
result=$(run_agent_hook_with_transcript '"model":"claude-sonnet-4-6"' "$CONFIG_AUTO" "$TRANSCRIPT_SONNET")
if [[ -z "$result" ]]; then
  pass "min_model=auto (resolves to sonnet), model=sonnet → allow"
else
  fail "min_model=auto resolved to sonnet, sonnet dispatch → expected allow, got: $result"
fi

# 14. min_model=auto + transcript says sonnet + dispatch=haiku → deny
result=$(run_agent_hook_with_transcript '"model":"claude-haiku-4-5"' "$CONFIG_AUTO" "$TRANSCRIPT_SONNET")
if [[ "$result" == *"permissionDecision"*"deny"* ]]; then
  pass "min_model=auto (resolves to sonnet), model=haiku → deny"
else
  fail "min_model=auto resolved to sonnet, haiku dispatch → expected deny, got: $result"
fi

# 15. CRITICAL regression test: transcript ends with "<synthetic>" — the auto
# resolver must IGNORE this entry (real Claude Code transcripts end this way)
# and pick the last valid family-keyword model. Without the filter, ordinal=0
# means the haiku floor silently disappears.
TRANSCRIPT_WITH_SYNTHETIC='{"type":"assistant","message":{"model":"claude-opus-4-6","role":"assistant"}}
{"type":"assistant","message":{"model":"claude-opus-4-6","role":"assistant"}}
{"type":"assistant","message":{"model":"<synthetic>","role":"assistant"}}'
result=$(run_agent_hook_with_transcript '"model":"claude-haiku-4-5"' "$CONFIG_AUTO" "$TRANSCRIPT_WITH_SYNTHETIC")
if [[ "$result" == *"permissionDecision"*"deny"* ]]; then
  pass "min_model=auto, transcript trailing <synthetic> → resolves to last valid family (opus), haiku denied"
else
  fail "min_model=auto, <synthetic> regression: expected deny (Haiku under Opus floor), got: $result"
fi

# 16. min_model=auto + transcript ONLY has <synthetic> (no valid family) →
# fallback to sonnet floor
TRANSCRIPT_ONLY_SYNTHETIC='{"type":"assistant","message":{"model":"<synthetic>","role":"assistant"}}'
result=$(run_agent_hook_with_transcript '"model":"claude-haiku-4-5"' "$CONFIG_AUTO" "$TRANSCRIPT_ONLY_SYNTHETIC")
if [[ "$result" == *"permissionDecision"*"deny"* ]]; then
  pass "min_model=auto, transcript only has <synthetic> → fallback sonnet floor denies haiku"
else
  fail "min_model=auto, only <synthetic> → expected fallback deny, got: $result"
fi

echo ""
echo "=== post-run-invariants.sh ==="

INV_SCRIPT="$REPO_ROOT/scripts/post-run-invariants.sh"

# 17. All checks skipped (empty args, must run in a git repo) → pass with message
(cd "$REPO_ROOT" && bash "$INV_SCRIPT" > /tmp/inv-test.txt 2>&1)
INV_RC=$?
if [ $INV_RC -eq 0 ] && grep -q "all checks passed" /tmp/inv-test.txt; then
  pass "post-run-invariants.sh: empty args → skips all → pass"
else
  fail "post-run-invariants.sh: empty args — rc=$INV_RC, output: $(cat /tmp/inv-test.txt)"
fi
rm -f /tmp/inv-test.txt

# 18. Nonexistent worktree path (should skip — invariant #1/#2 only fires when path provided AND exists)
# Actually invariant #1 requires the path NOT to exist; passing a nonexistent path should PASS.
(cd "$REPO_ROOT" && bash "$INV_SCRIPT" --worktree /tmp/nonexistent-invariant-test-$$ > /tmp/inv-test.txt 2>&1)
INV_RC=$?
if [ $INV_RC -eq 0 ]; then
  pass "post-run-invariants.sh: nonexistent worktree path → invariant #1 passes"
else
  fail "post-run-invariants.sh: nonexistent worktree — rc=$INV_RC, output: $(cat /tmp/inv-test.txt)"
fi
rm -f /tmp/inv-test.txt

# 19. Existing worktree path (fail invariant #1)
TMP_WT=$(mktemp -d)
(cd "$REPO_ROOT" && bash "$INV_SCRIPT" --worktree "$TMP_WT" > /tmp/inv-test.txt 2>&1)
INV_RC=$?
rm -rf "$TMP_WT"
if [ $INV_RC -ne 0 ] && grep -q "INVARIANT-FAIL (#1)" /tmp/inv-test.txt; then
  pass "post-run-invariants.sh: existing worktree path → invariant #1 fails loudly"
else
  fail "post-run-invariants.sh: existing worktree — rc=$INV_RC, output: $(cat /tmp/inv-test.txt)"
fi
rm -f /tmp/inv-test.txt

# 20. Plan file with 🟡 row → fail invariant #6
TMP_PLAN=$(mktemp)
printf '# Plan\n| 1 | 🟡 In Progress | abc |\n' > "$TMP_PLAN"
(cd "$REPO_ROOT" && bash "$INV_SCRIPT" --plan-file "$TMP_PLAN" > /tmp/inv-test.txt 2>&1)
INV_RC=$?
rm -f "$TMP_PLAN"
if [ $INV_RC -ne 0 ] && grep -q "INVARIANT-FAIL (#6)" /tmp/inv-test.txt; then
  pass "post-run-invariants.sh: plan with 🟡 → invariant #6 fails"
else
  fail "post-run-invariants.sh: plan with 🟡 — rc=$INV_RC, output: $(cat /tmp/inv-test.txt)"
fi
rm -f /tmp/inv-test.txt

# 21. Not in git repo → exits 1 with clear error
(cd /tmp && bash "$INV_SCRIPT" > /tmp/inv-test.txt 2>&1)
INV_RC=$?
if [ $INV_RC -ne 0 ] && grep -q "must run from inside a git repository" /tmp/inv-test.txt; then
  pass "post-run-invariants.sh: outside git repo → loud error, exit 1"
else
  fail "post-run-invariants.sh: outside git repo — rc=$INV_RC, output: $(cat /tmp/inv-test.txt)"
fi
rm -f /tmp/inv-test.txt

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
(cd "$REPO_ROOT" && bash "$INV_SCRIPT" --plan-slug "$TMP_SLUG" > /tmp/inv-test.txt 2>&1)
INV_RC=$?
if [ $INV_RC -ne 0 ] && grep -q "INVARIANT-FAIL (#5)" /tmp/inv-test.txt; then
  pass "post-run-invariants.sh: missing plan report → invariant #5 fails"
else
  fail "post-run-invariants.sh: missing plan report — rc=$INV_RC, output: $(cat /tmp/inv-test.txt)"
fi
rm -f /tmp/inv-test.txt

# 26. post-run-invariants.sh: lingering local branch after 'landed' → invariant #3 fails.
# Create a branch named 'invariant-zombie-test-$$' referencing HEAD; pass landed status.
ZOMBIE_BRANCH="invariant-zombie-test-$$"
git -C "$REPO_ROOT" branch "$ZOMBIE_BRANCH" HEAD 2>/dev/null
(cd "$REPO_ROOT" && bash "$INV_SCRIPT" --branch "$ZOMBIE_BRANCH" --landed-status landed > /tmp/inv-test.txt 2>&1)
INV_RC=$?
git -C "$REPO_ROOT" branch -D "$ZOMBIE_BRANCH" >/dev/null 2>&1
if [ $INV_RC -ne 0 ] && grep -q "INVARIANT-FAIL (#3)" /tmp/inv-test.txt; then
  pass "post-run-invariants.sh: local branch lingers after landed → invariant #3 fails"
else
  fail "post-run-invariants.sh: zombie local branch — rc=$INV_RC, output: $(cat /tmp/inv-test.txt)"
fi
rm -f /tmp/inv-test.txt

# 27. post-run-invariants.sh: local branch with 'pr-ready' status → does NOT fail
# (intentional — pr-ready means work not fully landed, branch is kept).
KEEP_BRANCH="invariant-keep-test-$$"
git -C "$REPO_ROOT" branch "$KEEP_BRANCH" HEAD 2>/dev/null
(cd "$REPO_ROOT" && bash "$INV_SCRIPT" --branch "$KEEP_BRANCH" --landed-status pr-ready > /tmp/inv-test.txt 2>&1)
INV_RC=$?
git -C "$REPO_ROOT" branch -D "$KEEP_BRANCH" >/dev/null 2>&1
# Exit may be nonzero if other invariants fire (fetch warning etc.), but invariant #3 must NOT fire.
if ! grep -q "INVARIANT-FAIL (#3)" /tmp/inv-test.txt; then
  pass "post-run-invariants.sh: pr-ready status → invariant #3 does NOT fire (branch kept intentionally)"
else
  fail "post-run-invariants.sh: pr-ready incorrectly triggered #3 — output: $(cat /tmp/inv-test.txt)"
fi
rm -f /tmp/inv-test.txt

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
echo "=== Pipeline scoping filter: A–F (cross-pipeline marker isolation) ==="

# test_pipeline_scoping_filter — the foundation for CANARY8's claim
# that parallel pipelines don't cross-block. If these cases pass,
# the suffix-match filter in hooks/block-unsafe-project.sh.template
# is mechanically guaranteed to isolate one pipeline's tracking
# markers from another.
#
# Naming convention mirrors real pipeline naming:
#   research-and-go.<SCOPE>        — parent meta-orchestrator
#   run-plan.meta-<SCOPE>          — meta-plan (META_ prefix from Phase B)
#   run-plan.<SUB_PLAN_SLUG>       — each sub-plan
#
# The hook strips the leading prefix via ${PIPELINE_ID#*.} and
# pattern-matches against each marker's basename. Two pipelines
# with different suffixes after that stripping cannot cross-block.
test_pipeline_scoping_filter() {
  # Case A — exact-match enforce: marker .meta-foo + PIPELINE_ID
  # run-plan.meta-foo + code commit → hook BLOCKS.
  setup_project_test
  touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.final.meta-foo"
  (cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
  rm -f "$TEST_TMPDIR/.transcript"
  printf 'npm run test:all\nZSKILLS_PIPELINE_ID=run-plan.meta-foo\n' > "$TEST_TMPDIR/.transcript"
  expect_project_deny "git commit -m test"
  teardown_project_test

  # Case B — sub-plan does not see parent's marker: same marker +
  # PIPELINE_ID run-plan.foo-backend → hook ALLOWS.
  setup_project_test
  touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.final.meta-foo"
  (cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
  rm -f "$TEST_TMPDIR/.transcript"
  printf 'npm run test:all\nZSKILLS_PIPELINE_ID=run-plan.foo-backend\n' > "$TEST_TMPDIR/.transcript"
  expect_project_allow "git commit -m test"
  teardown_project_test

  # Case C — research-and-go scope does NOT see meta marker:
  # PIPELINE_ID research-and-go.foo, marker .meta-foo. Suffix after
  # stripping is `foo`; pattern `*.foo` requires base to end with
  # literal `.foo`. `meta-foo` ends with `-foo`, not `.foo`. No match
  # → hook ALLOWS. This is what makes the SCOPE/META_PLAN_SLUG
  # distinction safe.
  setup_project_test
  touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.final.meta-foo"
  (cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
  rm -f "$TEST_TMPDIR/.transcript"
  printf 'npm run test:all\nZSKILLS_PIPELINE_ID=research-and-go.foo\n' > "$TEST_TMPDIR/.transcript"
  expect_project_allow "git commit -m test"
  teardown_project_test

  # Case D — collision case (edge): same suffix after stripping.
  # PIPELINE_ID research-and-go.meta-foo, marker .meta-foo. Both
  # strip to `meta-foo`; pattern `*.meta-foo` matches base ending
  # `.meta-foo`. → hook BLOCKS. Documents that users must not pick
  # goal descriptions whose SCOPE collides with META_PLAN_SLUG
  # naming. Not a normal scenario — requires hand-crafted inputs.
  setup_project_test
  touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.final.meta-foo"
  (cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
  rm -f "$TEST_TMPDIR/.transcript"
  printf 'npm run test:all\nZSKILLS_PIPELINE_ID=research-and-go.meta-foo\n' > "$TEST_TMPDIR/.transcript"
  expect_project_deny "git commit -m test"
  teardown_project_test

  # Case E — empty PIPELINE_ID (no .zskills-tracked, no transcript
  # declaration) → no association → skip enforcement → hook ALLOWS.
  # Per hook's "Neither → unrelated session → skip enforcement"
  # branch (line 207 of block-unsafe-project.sh.template).
  setup_project_test
  touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.final.meta-foo"
  (cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
  rm -f "$TEST_TMPDIR/.transcript"
  printf 'npm run test:all\n' > "$TEST_TMPDIR/.transcript"
  expect_project_allow "git commit -m test"
  teardown_project_test

  # Case F — no marker present at all: empty tracking dir + any
  # PIPELINE_ID + code commit → hook ALLOWS.
  setup_project_test
  # tracking dir is empty (no marker files)
  (cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
  rm -f "$TEST_TMPDIR/.transcript"
  printf 'npm run test:all\nZSKILLS_PIPELINE_ID=run-plan.meta-foo\n' > "$TEST_TMPDIR/.transcript"
  expect_project_allow "git commit -m test"
  teardown_project_test
}
test_pipeline_scoping_filter

echo ""
echo "=== /verify-changes \$ARGUMENTS parser (extracted from skill) ==="

# test_verify_changes_arg_parser — re-implements the parser from
# skills/verify-changes/SKILL.md under "Parsing $ARGUMENTS" and
# exercises it against token strings. Locks down Phase H's parser
# before any cron-fired use.
#
# The parser is a small for-token case statement:
#   tracking-id=X  → TRACKING_ID=X
#   worktree|branch|last → SCOPE=<token>
#   [0-9]*         → if SCOPE=="last", SCOPE="last N"
# Order-independent; unknown tokens are tolerated (ignored).
test_verify_changes_arg_parser() {
  parse_args() {
    SCOPE=""
    TRACKING_ID=""
    for tok in $1; do
      case "$tok" in
        tracking-id=*) TRACKING_ID="${tok#tracking-id=}" ;;
        worktree|branch|last) SCOPE="$tok" ;;
        [0-9]*) [ "$SCOPE" = "last" ] && SCOPE="last $tok" ;;
      esac
    done
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
}
test_verify_changes_arg_parser

echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
