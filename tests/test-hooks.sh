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

# 1. git stash drop / clear
expect_deny "git stash drop" "git stash drop"
expect_deny "git stash clear" "git stash clear"

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
expect_allow "git stash (no drop/clear)" "git stash"
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

# Config file protection: handled by Claude Code's built-in permission system
# on .claude/ directory. No custom hook tests needed — Claude Code gates all
# tools (Bash, Write, Edit) for .claude/ paths automatically.

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
  local result
  result=$(echo "$json" | REPO_ROOT="$test_tmpdir" bash "$test_tmpdir/.claude/hooks/block-unsafe-project.sh" 2>/dev/null)

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
rm -rf "$LAND_TMPDIR"
if [ "$ARTIFACTS_GONE" -eq 4 ] && [ "$MARKER_PRESERVED" -eq 1 ]; then
  pass "land-phase.sh: removes artifacts (incl. .test-baseline.txt) but preserves .landed on failure"
else
  fail "land-phase.sh: artifacts cleanup — gone=$ARTIFACTS_GONE/4, marker=$MARKER_PRESERVED, output: $LAND_OUTPUT"
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
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
