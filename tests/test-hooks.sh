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

# These run on main branch, so all pushes should be blocked
expect_deny "git push (bare, on main)" "git push"
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
  (cd "$TEST_TMPDIR" && git clone --bare "$TEST_TMPDIR" "$TEST_REMOTE" 2>/dev/null && git remote add origin "$TEST_REMOTE" 2>/dev/null && git fetch origin 2>/dev/null && git branch -u origin/master 2>/dev/null)
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
  mkdir -p "$test_tmpdir/.claude/tracking"

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
mkdir -p "$push_tracking_tmpdir/.claude/tracking"
cp "$PROJECT_HOOK" "$push_tracking_tmpdir/.claude/hooks/block-unsafe-project.sh"
sed -i 's|{{UNIT_TEST_CMD}}|npm test|g' "$push_tracking_tmpdir/.claude/hooks/block-unsafe-project.sh"
sed -i 's|{{FULL_TEST_CMD}}|npm run test:all|g' "$push_tracking_tmpdir/.claude/hooks/block-unsafe-project.sh"
sed -i 's|{{UI_FILE_PATTERNS}}|src/ui/|g' "$push_tracking_tmpdir/.claude/hooks/block-unsafe-project.sh"
printf '{"scripts":{"test":"vitest","test:all":"vitest run"}}\n' > "$push_tracking_tmpdir/package.json"
printf 'npm run test:all\n' > "$push_tracking_tmpdir/.transcript"
(cd "$push_tracking_tmpdir" && git init -q && git checkout -b main 2>/dev/null && git add -A && git commit -q -m "init" 2>/dev/null)
(cd "$push_tracking_tmpdir" && git checkout -b feat/test 2>/dev/null && echo "var x=1;" > app.js && git add app.js && git commit -q -m "add code" 2>/dev/null)
# Add a requires file without fulfilled — should block push with code files
touch "$push_tracking_tmpdir/.claude/tracking/requires.verify-changes"
PUSH_JSON="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push -u origin feat/test\"},\"transcript_path\":\"$push_tracking_tmpdir/.transcript\"}"
PUSH_RESULT=$(echo "$PUSH_JSON" | REPO_ROOT="$push_tracking_tmpdir" bash "$push_tracking_tmpdir/.claude/hooks/block-unsafe-project.sh" 2>/dev/null)
if [[ "$PUSH_RESULT" == *"Required skill invocation"* ]]; then
  pass "push tracking: no-upstream fallback detects code files and enforces tracking"
else
  fail "push tracking: no-upstream fallback should detect code files, got: $PUSH_RESULT"
fi
rm -rf "$push_tracking_tmpdir"

echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
