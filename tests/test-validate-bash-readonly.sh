#!/usr/bin/env bash
# Tests for hooks/validate-bash-readonly.sh
# Run from repo root: bash tests/test-validate-bash-readonly.sh
#
# VERIFIER_AGENT_FIX Phase 1.5 — adversarial-bypass cases per N6.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/hooks/validate-bash-readonly.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  printf '\033[32m  PASS\033[0m %s\n' "$1"
  ((PASS_COUNT++))
}

fail() {
  printf '\033[31m  FAIL\033[0m %s\n' "$1"
  printf '    %s\n' "$2"
  ((FAIL_COUNT++))
}

# Build a JSON tool_input with the given command. We need to escape
# inner double quotes for JSON validity. Backslashes and quotes in the
# command are escaped here; subshell parens and pipes are JSON-safe.
make_input() {
  local cmd="$1"
  # Escape \ first, then ".
  local esc="${cmd//\\/\\\\}"
  esc="${esc//\"/\\\"}"
  printf '{"command":"%s"}' "$esc"
}

run_hook() {
  printf '%s' "$1" | bash "$HOOK"
}

expect_block() {
  local label="$1"
  local cmd="$2"
  local input result
  input=$(make_input "$cmd")
  result=$(run_hook "$input")
  if [[ "$result" == *'"decision": "block"'* ]]; then
    pass "block: $label"
  else
    fail "block: $label" "cmd=[$cmd] expected block, got: ${result:-<empty>}"
  fi
}

expect_allow() {
  local label="$1"
  local cmd="$2"
  local input result
  input=$(make_input "$cmd")
  result=$(run_hook "$input")
  if [[ -z "$result" ]]; then
    pass "allow: $label"
  else
    fail "allow: $label" "cmd=[$cmd] expected empty output, got: $result"
  fi
}

echo "=== validate-bash-readonly.sh — adversarial bypass (N6) ==="

# BLOCK assertions
expect_block "env-var prefix bypass: FOO=bar rm /etc/x" "FOO=bar rm /etc/x"
expect_block "&&-chain bypass: git diff && rm foo" "git diff && rm foo"
expect_block "subshell bypass: (rm foo)" "(rm foo)"
expect_block "pipe-tail bypass: echo x | rm foo" "echo x | rm foo"
expect_block "top-level baseline: rm foo" "rm foo"

# Forbidden git verbs (sample — verifies the git-verb branch fires)
expect_block "git stash" "git stash"
expect_block "git commit -m msg" "git commit -m msg"
expect_block "git checkout main" "git checkout main"
expect_block "git push" "git push"

# ALLOW assertions
expect_allow "test runner: npm test" "npm test"
expect_allow "test runner: bash tests/run-all.sh" "bash tests/run-all.sh"
expect_allow "test runner: bash scripts/test-all.sh" "bash scripts/test-all.sh"
expect_allow "no forbidden verb: git diff && grep foo" "git diff && grep foo"
expect_allow "read-only git: git diff" "git diff"
expect_allow "identifier-boundary regress: mvbacon foo" "mvbacon foo"

# Additional identifier-boundary regress cases — substrings of forbidden
# verbs inside longer identifiers MUST NOT match.
expect_allow "identifier-boundary: rmdir-helper" "rmdir-helper foo"
expect_allow "identifier-boundary: copy_files" "copy_files src dst"

echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
