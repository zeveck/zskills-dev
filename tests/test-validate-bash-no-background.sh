#!/usr/bin/env bash
# Tests for hooks/validate-bash-no-background.sh
# Run from repo root: bash tests/test-validate-bash-no-background.sh
#
# VERIFIER_AGENT_FIX Phase 1.4 — 6 cases.
# Each case asserts a precise outcome (no "acceptable false-positive"
# cases). Case 4 specifically asserts the content-only
# `echo "...run_in_background\":true..."` is ALLOWED — the regress test
# for the C4 strict-regex resolution.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/hooks/validate-bash-no-background.sh"

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

run_hook() {
  printf '%s' "$1" | bash "$HOOK"
}

expect_block() {
  local label="$1"
  local input="$2"
  local result
  result=$(run_hook "$input")
  if [[ "$result" == *'"decision": "block"'* ]]; then
    pass "block: $label"
  else
    fail "block: $label" "expected block, got: ${result:-<empty>}"
  fi
}

expect_allow() {
  local label="$1"
  local input="$2"
  local result
  result=$(run_hook "$input")
  if [[ -z "$result" ]]; then
    pass "allow: $label"
  else
    fail "allow: $label" "expected empty output, got: $result"
  fi
}

echo "=== validate-bash-no-background.sh ==="

# Case 1: top-level run_in_background:true → BLOCK
expect_block "case 1: top-level run_in_background:true" \
  '{"command":"npm test","run_in_background":true}'

# Case 2: top-level run_in_background:false → ALLOW
expect_allow "case 2: run_in_background:false" \
  '{"command":"npm test","run_in_background":false}'

# Case 3: field absent → ALLOW
expect_allow "case 3: field absent" \
  '{"command":"npm test"}'

# Case 4 (strict-regex check / C4 regress): literal substring inside
# a quoted command-string value, NOT as a top-level key → ALLOW.
# The leading [{,] boundary in the regex prevents this content-only
# match from triggering the block.
expect_allow "case 4: content-only literal substring inside command string (C4 regress)" \
  '{"command":"echo \"run_in_background\\\":true is in a string\""}'

# Case 5: whitespace variants → BLOCK
expect_block "case 5: whitespace variants" \
  '{"command":"npm test", "run_in_background" : true }'

# Case 6: key followed by another key (verifies trailing-boundary
# class ([[:space:]]|,|}) against a ,"description":... follow-up).
expect_block "case 6: key followed by another key (trailing-boundary regress)" \
  '{"command":"npm test","run_in_background":true,"description":"runs tests"}'

echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
