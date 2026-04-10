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
  mkdir -p "$TEST_TMPDIR/.claude/tracking"

  # Copy and configure the hook template
  cp "$PROJECT_HOOK" "$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh"
  sed -i 's|{{UNIT_TEST_CMD}}|npm test|g' "$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh"
  sed -i 's|{{FULL_TEST_CMD}}|npm run test:all|g' "$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh"
  sed -i 's|{{UI_FILE_PATTERNS}}|src/ui/|g' "$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh"

  # Create mock package.json with test script
  printf '{"scripts":{"test":"vitest","test:all":"vitest run"}}\n' > "$TEST_TMPDIR/package.json"

  # Create mock transcript with test command AND a pipeline skill invocation
  # (the latter satisfies the Change 6 session-aware guard so tracking
  # enforcement actually fires when expected)
  printf '/run-plan plans/foo.md\nnpm run test:all\n' > "$TEST_TMPDIR/.transcript"

  # Initialize git repo (needed for git diff --cached, etc.)
  (cd "$TEST_TMPDIR" && git init -q && git add -A && git commit -q -m "init" 2>/dev/null)
}

teardown_project_test() {
  [ -n "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
  TEST_TMPDIR=""
}

expect_project_deny() {
  local cmd="$1"
  local json="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$cmd\"},\"transcript_path\":\"$TEST_TMPDIR/.transcript\"}"
  local result
  result=$(echo "$json" | REPO_ROOT="$TEST_TMPDIR" bash "$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh" 2>/dev/null)
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
  result=$(echo "$json" | REPO_ROOT="$TEST_TMPDIR" bash "$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh" 2>/dev/null)
  if [[ -z "$result" ]] || [[ "$result" != *"deny"* ]]; then
    pass "$cmd → allowed (expected)"
  else
    fail "$cmd → denied (expected allow)"
  fi
}

echo "=== Project hook: tracking file protection ==="

setup_project_test

# Block recursive rm of tracking directory
expect_project_deny "rm -rf .claude/tracking"
expect_project_deny "rm -r .claude/tracking"
expect_project_deny "rm -fr .claude/tracking"

# Allow individual file deletion within tracking directory
expect_project_allow "rm .claude/tracking/requires.foo"
expect_project_allow "rm -f .claude/tracking/pipeline.active"

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
touch "$TEST_TMPDIR/.claude/tracking/requires.verify-changes"
# Stage a code file so it's not content-only
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
expect_project_deny "git commit -m test"
teardown_project_test

# Test: requires.X with fulfilled.X allows git commit
setup_project_test
touch "$TEST_TMPDIR/.claude/tracking/requires.verify-changes"
touch "$TEST_TMPDIR/.claude/tracking/fulfilled.verify-changes"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
expect_project_allow "git commit -m test"
teardown_project_test

# Test: delegation blocks git cherry-pick too
setup_project_test
touch "$TEST_TMPDIR/.claude/tracking/requires.verify-changes"
expect_project_deny "git cherry-pick abc123"
teardown_project_test

echo ""
echo "=== Project hook: step enforcement ==="

# Test: step.X.implement without step.X.verify blocks
setup_project_test
touch "$TEST_TMPDIR/.claude/tracking/step.phase1.implement"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
expect_project_deny "git commit -m test"
teardown_project_test

# Test: step.X.implement with step.X.verify but no step.X.report blocks
setup_project_test
touch "$TEST_TMPDIR/.claude/tracking/step.phase1.implement"
touch "$TEST_TMPDIR/.claude/tracking/step.phase1.verify"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
expect_project_deny "git commit -m test"
teardown_project_test

# Test: step.X.implement + step.X.verify + step.X.report allows
setup_project_test
touch "$TEST_TMPDIR/.claude/tracking/step.phase1.implement"
touch "$TEST_TMPDIR/.claude/tracking/step.phase1.verify"
touch "$TEST_TMPDIR/.claude/tracking/step.phase1.report"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
expect_project_allow "git commit -m test"
teardown_project_test

# Test: phasestep.* markers are ignored (not enforced)
setup_project_test
touch "$TEST_TMPDIR/.claude/tracking/phasestep.phase1.implement"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
expect_project_allow "git commit -m test"
teardown_project_test

# Test: step enforcement on cherry-pick
setup_project_test
touch "$TEST_TMPDIR/.claude/tracking/step.phase1.implement"
expect_project_deny "git cherry-pick abc123"
teardown_project_test

echo ""
echo "=== Project hook: staleness protection ==="

# Test: stale pipeline.active (>8h) allows commit despite requires.*
setup_project_test
touch "$TEST_TMPDIR/.claude/tracking/requires.verify-changes"
touch "$TEST_TMPDIR/.claude/tracking/pipeline.active"
# Make pipeline.active look old (>8h = 480min)
touch -t 202501010000 "$TEST_TMPDIR/.claude/tracking/pipeline.active"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
expect_project_allow "git commit -m test"
teardown_project_test

echo ""
echo "=== Project hook: backward compatibility ==="

# Test: no tracking dir → silently passes
setup_project_test
rmdir "$TEST_TMPDIR/.claude/tracking"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
expect_project_allow "git commit -m test"
teardown_project_test

# Test: content-only commits bypass tracking enforcement
setup_project_test
touch "$TEST_TMPDIR/.claude/tracking/requires.verify-changes"
(cd "$TEST_TMPDIR" && echo "content" > readme.md && git add readme.md)
expect_project_allow "git commit -m test"
teardown_project_test

echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
