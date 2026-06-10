#!/usr/bin/env bash
# Tests for skills/update-zskills/scripts/verify-response-validate.sh
# (skill-bundled as of INSTALL_REDESIGN Phase 3 — formerly a hook).
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
#   6-15. Paraphrase class (issue #480) — broadened PATTERNS_STALLED entries
#         each fire on a plausible paraphrase the original 7-entry whitelist
#         missed.
#   16-18. Positive paraphrase cases that LOOK similar but should pass
#          (verifier has positive evidence of test completion).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/skills/update-zskills/scripts/verify-response-validate.sh"

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

# --- Paraphrase class (issue #480) ---
# Each case is the verifier ending its turn with a paraphrase of "I'm not
# actually verifying, I'm waiting." All should EXIT 1.

# Helper for paraphrase cases: a long body of legitimate-looking prose,
# then the trailer phrase under test. The body satisfies the 200-byte
# minimum so only the trailer drives the fail/pass outcome.
PARAPHRASE_BODY='Verification report for the dispatched change. I reviewed the diff for skills/run-plan/SKILL.md and the supporting test fixture additions. The change touches the Failure Protocol section and adds a stalled-string check downstream of the dispatch. I attempted to run the full suite to confirm no regression.

Body line A. Body line B. Body line C. Body line D. Body line E.
'

run_paraphrase_fail() {
  local label="$1"
  local trailer="$2"
  local response="$PARAPHRASE_BODY
$trailer"
  local stderr_file
  stderr_file=$(mktemp)
  printf '%s' "$response" | bash "$HOOK" 2>"$stderr_file"
  local exit_code=$?
  local stderr_text
  stderr_text=$(cat "$stderr_file")
  rm -f "$stderr_file"
  if [ "$exit_code" -eq 1 ] && [[ "$stderr_text" == *"stalled-string pattern"* ]]; then
    pass "$label"
  else
    fail "$label" "exit=$exit_code stderr=$stderr_text"
  fi
}

run_paraphrase_pass() {
  local label="$1"
  local trailer="$2"
  local response="$PARAPHRASE_BODY
$trailer"
  local stderr_file
  stderr_file=$(mktemp)
  printf '%s' "$response" | bash "$HOOK" 2>"$stderr_file"
  local exit_code=$?
  local stderr_text
  stderr_text=$(cat "$stderr_file")
  rm -f "$stderr_file"
  if [ "$exit_code" -eq 0 ] && [ -z "$stderr_text" ]; then
    pass "$label"
  else
    fail "$label" "exit=$exit_code stderr=$stderr_text"
  fi
}

# Negative (should-fail) paraphrase cases — each was a clean PASS before #480.
run_paraphrase_fail "case 6: 'I'll wait for the test suite to finish'" \
  "I'll wait for the test suite to finish before reporting."

run_paraphrase_fail "case 7: 'I will wait for the test run'" \
  "I will wait for the test run to complete."

run_paraphrase_fail "case 8: 'let me wait for the test command'" \
  "Let me wait for the test command output."

run_paraphrase_fail "case 9: 'running in background, will check back'" \
  "The suite is running in background, will check back shortly."

run_paraphrase_fail "case 10: 'running in the background'" \
  "Tests started; they are running in the background now."

run_paraphrase_fail "case 11: 'is still running'" \
  "The implementation agent is still running and I will report once done."

run_paraphrase_fail "case 12: 'still running in'" \
  "The build is still running in CI; I cannot confirm yet."

run_paraphrase_fail "case 13: 'come back to check'" \
  "I'll come back to check once the long-running task finishes."

run_paraphrase_fail "case 14: 'I'll poll'" \
  "I'll poll the background process every few minutes."

run_paraphrase_fail "case 15: 'still in progress'" \
  "The verification step is still in progress."

run_paraphrase_fail "case 16: 'will poll later'" \
  "I will poll later once the suite produces output."

# Positive (should-pass) cases — verifier has POSITIVE evidence of test
# completion in the tail. These would not have triggered the old 7-entry
# whitelist, and must NOT trigger the broadened one either.
run_paraphrase_pass "case 17: 'tests passed, waiting for CI to merge'" \
  "Tests: 3636/3636 passed locally. AC checks complete. Waiting for CI to merge the PR, then sprint done."

run_paraphrase_pass "case 18: 'tests passed locally; auto-merge enabled'" \
  "Local suite: 3636/3636 passed. Diff matches plan. Auto-merge enabled on the PR; this report concludes."

run_paraphrase_pass "case 19: 'all tests passed, ready to commit'" \
  "All tests passed (3636/3636). AC-1 PASS, AC-2 PASS. Ready to commit."

echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
