#!/usr/bin/env bash
# Tests for hooks/verify-response-validate.sh
# Run from repo root: bash tests/test-verify-response-validate.sh
#
# VERIFIER_AGENT_FIX (D'' rework). Layer 3 universal failure-protocol
# primitive applied at all 5 verifier-dispatch sites.
#
# Cases:
#   1. Normal long verifier response with no stalled patterns → exit 0
#   2. Stalled-string in last 10 lines → exit 1, stderr names the pattern
#   3. Sub-200-byte response → exit 1, stderr names the threshold
#   4. Empty response → exit 1
#   5. Stalled-string in EARLIER lines (not last 10) → exit 0 (recovered)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/hooks/verify-response-validate.sh"

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

echo "=== verify-response-validate.sh ==="

# Case 1 — Normal verifier response, well over 200 bytes, clean trailer
NORMAL_RESPONSE='Verification report for Phase 2.

Diff reviewed: skills/run-plan/SKILL.md updated with subagent_type: "verifier" parameter at the dispatch site, and the Failure Protocol section was inserted with all 7 stalled-string whitelist entries plus the 200-byte minimum-length signal.

Tests: 2056/2056 passed. No new failures vs baseline.

AC-2.1 PASS, AC-2.2 PASS, AC-2.3 PASS, AC-2.4 PASS.

Verification complete. Ready to commit.'
STDERR_FILE=$(mktemp)
printf '%s' "$NORMAL_RESPONSE" | bash "$HOOK" 2>"$STDERR_FILE"
EXIT=$?
STDERR=$(cat "$STDERR_FILE")
rm -f "$STDERR_FILE"
if [ "$EXIT" -eq 0 ] && [ -z "$STDERR" ]; then
  pass "case 1: normal long response → exit 0, no stderr"
else
  fail "case 1: normal response should pass" "exit=$EXIT stderr=$STDERR"
fi

# Case 2 — Stalled-string in last 10 lines → exit 1, stderr names pattern
STALLED_LAST='Verification report. Diff reviewed for plan acceptance criteria.

I attempted to run the test suite. The Bash call started, then took longer than expected.

I tried backgrounding the run to keep watching it.

Tests are running. Let me wait for the monitor.'
STDERR_FILE=$(mktemp)
printf '%s' "$STALLED_LAST" | bash "$HOOK" 2>"$STDERR_FILE"
EXIT=$?
STDERR=$(cat "$STDERR_FILE")
rm -f "$STDERR_FILE"
if [ "$EXIT" -eq 1 ] && [[ "$STDERR" == *"FAIL"* ]] && \
   { [[ "$STDERR" == *"tests are running. let me wait"* ]] || [[ "$STDERR" == *"let me wait for the monitor"* ]]; }; then
  pass "case 2: stalled phrase in last 10 lines → exit 1, stderr names pattern"
else
  fail "case 2: stalled phrase in tail should fail with named pattern" "exit=$EXIT stderr=$STDERR"
fi

# Case 3 — Sub-200-byte response → exit 1, stderr names threshold
SHORT_RESPONSE='Tests passed.'
STDERR_FILE=$(mktemp)
printf '%s' "$SHORT_RESPONSE" | bash "$HOOK" 2>"$STDERR_FILE"
EXIT=$?
STDERR=$(cat "$STDERR_FILE")
rm -f "$STDERR_FILE"
if [ "$EXIT" -eq 1 ] && [[ "$STDERR" == *"200"* ]] && [[ "$STDERR" == *"FAIL"* ]]; then
  pass "case 3: sub-200-byte response → exit 1, stderr names threshold"
else
  fail "case 3: short response should fail with threshold" "exit=$EXIT stderr=$STDERR"
fi

# Case 4 — Empty response → exit 1
STDERR_FILE=$(mktemp)
printf '' | bash "$HOOK" 2>"$STDERR_FILE"
EXIT=$?
STDERR=$(cat "$STDERR_FILE")
rm -f "$STDERR_FILE"
if [ "$EXIT" -eq 1 ] && [[ "$STDERR" == *"FAIL"* ]]; then
  pass "case 4: empty response → exit 1"
else
  fail "case 4: empty response should fail" "exit=$EXIT stderr=$STDERR"
fi

# Case 5 — Stalled-string in EARLIER lines, not last 10 → exit 0 (agent recovered)
RECOVERED='I considered backgrounding the test run, which is the "tests are running. let me wait for the monitor" anti-pattern. I rejected that approach.

Instead I ran the suite foreground with timeout: 600000.

Line 4 of body.
Line 5 of body.
Line 6 of body.
Line 7 of body.
Line 8 of body.
Line 9 of body.
Line 10 of body.
Line 11 of body.
Line 12 of body.
Line 13 of body.
Line 14 of body.
Line 15 of body.

Tests: 2056/2056 passed against baseline. AC checks complete. Ready to commit.'
STDERR_FILE=$(mktemp)
printf '%s' "$RECOVERED" | bash "$HOOK" 2>"$STDERR_FILE"
EXIT=$?
STDERR=$(cat "$STDERR_FILE")
rm -f "$STDERR_FILE"
if [ "$EXIT" -eq 0 ] && [ -z "$STDERR" ]; then
  pass "case 5: stalled phrase in EARLY lines, recovered in tail → exit 0"
else
  fail "case 5: agent that recovered should pass" "exit=$EXIT stderr=$STDERR"
fi

echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
