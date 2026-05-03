#!/usr/bin/env bash
# tests/canary-verify-response-validate.sh
#
# Phase 4 canary 3 — VERIFIER_AGENT_FIX plan.
#
# SCOPE: pure-shell test of `hooks/verify-response-validate.sh` (Layer 3
# universal failure-protocol primitive). The script is independently
# testable — no live subagent dispatch required.
#
# This canary EXTENDS `tests/test-verify-response-validate.sh` (which
# covers the 5-case core: A clean, B stalled-tail, C stalled-early-tail-
# clean, D sub-200-byte, E empty) with a threshold-calibration matrix
# (sub-cases F + G) so the 200-byte cutoff is example-driven, not
# arbitrary.
#
# Sub-cases:
#   A — clean ≥200-byte response, no stalled patterns → exit 0
#   B — stalled phrase in last 10 lines → exit 1, stderr names phrase
#   C — stalled phrase in EARLIER lines, recovered tail → exit 0
#   D — sub-200-byte response → exit 1, stderr names threshold
#   E — empty response → exit 1
#   F (a/b/c) — three realistic ≥200-byte "tests skipped" attestations,
#               all expect exit 0 (positive threshold-calibration)
#   G (a/b/c) — three sub-200-byte stubs, all expect exit 1 with stderr
#               referencing the threshold (negative threshold-calibration)

set -u

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

# run_case <fixture> → sets EXIT and STDERR globals
run_case() {
  local fixture="$1"
  local stderr_file
  stderr_file=$(mktemp)
  printf '%s' "$fixture" | bash "$HOOK" 2>"$stderr_file"
  EXIT=$?
  STDERR=$(cat "$stderr_file")
  rm -f "$stderr_file"
}

echo "=== canary-verify-response-validate ==="

# --------------------------------------------------------------------
# Sub-case A — clean ≥200-byte response, no stalled patterns → exit 0
# --------------------------------------------------------------------
A_FIXTURE='Verification report for Phase 3.

Diff reviewed: skills/run-plan/SKILL.md updated with subagent_type: "verifier" parameter at the dispatch site, Failure Protocol section inserted with 7 stalled-string whitelist entries, and the 200-byte minimum-length signal documented.

Tests: 2056/2056 passed. No new failures vs baseline.

AC-3.1 PASS, AC-3.2 PASS, AC-3.3 PASS. Verification complete.'
run_case "$A_FIXTURE"
if [ "$EXIT" -eq 0 ] && [ -z "$STDERR" ]; then
  pass "A: clean ≥200-byte response → exit 0, no stderr"
else
  fail "A: clean response should pass" "exit=$EXIT stderr=$STDERR"
fi

# --------------------------------------------------------------------
# Sub-case B — stalled phrase in last 10 lines → exit 1, stderr names
# phrase
# --------------------------------------------------------------------
B_FIXTURE='Verification report. Diff reviewed for plan acceptance criteria.

I attempted to run the test suite. The Bash call started, then took longer than expected.

I tried backgrounding the run to keep watching it.

Tests are running. Let me wait for the monitor.'
run_case "$B_FIXTURE"
if [ "$EXIT" -eq 1 ] && [[ "$STDERR" == *"FAIL"* ]] \
   && { [[ "$STDERR" == *"tests are running. let me wait"* ]] || [[ "$STDERR" == *"let me wait for the monitor"* ]]; }; then
  pass "B: stalled phrase in last 10 lines → exit 1, stderr names phrase"
else
  fail "B: stalled-tail should fail with named phrase" "exit=$EXIT stderr=$STDERR"
fi

# --------------------------------------------------------------------
# Sub-case C — stalled phrase in EARLIER lines, clean tail → exit 0
# (last-10-lines anchor is load-bearing — agent quoting the trigger
# phrase in earlier prose must NOT trip the check)
# --------------------------------------------------------------------
C_FIXTURE='I considered backgrounding the test run, which is the "tests are running. let me wait for the monitor" anti-pattern. I rejected that approach.

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
run_case "$C_FIXTURE"
if [ "$EXIT" -eq 0 ] && [ -z "$STDERR" ]; then
  pass "C: stalled phrase in early lines, recovered tail → exit 0"
else
  fail "C: agent that recovered should pass" "exit=$EXIT stderr=$STDERR"
fi

# --------------------------------------------------------------------
# Sub-case D — sub-200-byte response → exit 1, stderr names threshold
# --------------------------------------------------------------------
D_FIXTURE='Tests passed.'
run_case "$D_FIXTURE"
if [ "$EXIT" -eq 1 ] && [[ "$STDERR" == *"200"* ]] && [[ "$STDERR" == *"FAIL"* ]]; then
  pass "D: sub-200-byte response → exit 1, stderr names threshold"
else
  fail "D: short response should fail with threshold" "exit=$EXIT stderr=$STDERR"
fi

# --------------------------------------------------------------------
# Sub-case E — empty response → exit 1
# --------------------------------------------------------------------
run_case ''
if [ "$EXIT" -eq 1 ] && [[ "$STDERR" == *"FAIL"* ]]; then
  pass "E: empty response → exit 1"
else
  fail "E: empty response should fail" "exit=$EXIT stderr=$STDERR"
fi

# --------------------------------------------------------------------
# Sub-case F — positive threshold-calibration. Three realistic ≥200-byte
# "tests skipped" attestations. All expect exit 0 — these are exactly
# the kind of skipped-test reports the verifier produces on phases
# where the test surface is intentionally empty (markdown-only edits,
# CHANGELOG bumps, references/ docs).
# --------------------------------------------------------------------
F_A='Tests: skipped — no test infra detected. TEST_MODE=skipped per zskills-config.json. Phase scope is markdown-only (CLAUDE.md edits + plan refinement). No code surface to exercise. Verification consists of grep audits of section anchors — passed.'
run_case "$F_A"
if [ "$EXIT" -eq 0 ] && [ -z "$STDERR" ]; then
  pass "F-a: realistic markdown-only skipped attestation → exit 0"
else
  fail "F-a: realistic skipped attestation should pass" "exit=$EXIT stderr=$STDERR"
fi

F_B="Tests: skipped — phase scope is content-only (CHANGELOG entry + frontmatter status update). I read the diff; CHANGELOG entry resolves to today's date and references the correct issues. PLAN_INDEX.md move is correct. No assertion failures."
run_case "$F_B"
if [ "$EXIT" -eq 0 ] && [ -z "$STDERR" ]; then
  pass "F-b: realistic CHANGELOG-only skipped attestation → exit 0"
else
  fail "F-b: realistic skipped attestation should pass" "exit=$EXIT stderr=$STDERR"
fi

F_C='Tests: skipped — TEST_MODE=skipped per zskills-config.json. The phase touches only references/ docs; the test config explicitly excludes references/ from the test surface. Verified the markdown renders without warnings via mdformat --check.'
run_case "$F_C"
if [ "$EXIT" -eq 0 ] && [ -z "$STDERR" ]; then
  pass "F-c: realistic references-only skipped attestation → exit 0"
else
  fail "F-c: realistic skipped attestation should pass" "exit=$EXIT stderr=$STDERR"
fi

# --------------------------------------------------------------------
# Sub-case G — negative threshold-calibration. Three sub-200-byte stubs.
# All expect exit 1 with stderr referencing the 200-byte threshold.
# These are the failure mode the threshold exists to catch: agent ends
# its turn with a one-token "ok" instead of an attestation.
# --------------------------------------------------------------------
G_A='ok done'
run_case "$G_A"
if [ "$EXIT" -eq 1 ] && [[ "$STDERR" == *"200"* ]] && [[ "$STDERR" == *"FAIL"* ]]; then
  pass "G-a: 'ok done' stub → exit 1, stderr names threshold"
else
  fail "G-a: stub response should fail with threshold" "exit=$EXIT stderr=$STDERR"
fi

G_B='verified'
run_case "$G_B"
if [ "$EXIT" -eq 1 ] && [[ "$STDERR" == *"200"* ]] && [[ "$STDERR" == *"FAIL"* ]]; then
  pass "G-b: 'verified' stub → exit 1, stderr names threshold"
else
  fail "G-b: stub response should fail with threshold" "exit=$EXIT stderr=$STDERR"
fi

G_C='Tests: passed'
run_case "$G_C"
if [ "$EXIT" -eq 1 ] && [[ "$STDERR" == *"200"* ]] && [[ "$STDERR" == *"FAIL"* ]]; then
  pass "G-c: 'Tests: passed' stub → exit 1, stderr names threshold"
else
  fail "G-c: stub response should fail with threshold" "exit=$EXIT stderr=$STDERR"
fi

echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
