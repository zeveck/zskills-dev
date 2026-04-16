#!/bin/bash
# Tests for /run-plan's halt-on-scope-flag bash detection.
#
# /run-plan's pre-landing checklist greps the /verify-changes report
# for the scope-violation flag ("⚠️ Flag") and halts if present.
# The detection logic lives in skills/run-plan/SKILL.md under
# "Pre-landing checklist" step 6. This test re-implements the
# detection bash inline (as `scope_halt_check()`) and exercises it
# against synthesized verify-report files.
#
# Assertions target the public contract:
#   - report contains ⚠️ Flag  → exit non-zero, stderr mentions HALTED + report path
#   - report has Scope Assessment but no flag → exit zero
#   - report file missing → exit zero (graceful — old plans without /verify-changes)
#
# Does NOT test the LLM judgment that produces the flag (that's CANARY11).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  printf '\033[32m  PASS\033[0m %s\n' "$1"
  PASS_COUNT=$((PASS_COUNT+1))
}

fail() {
  printf '\033[31m  FAIL\033[0m %s\n' "$1"
  FAIL_COUNT=$((FAIL_COUNT+1))
}

# Re-implementation of /run-plan's scope-halt check.
# Inputs: $VERIFY_REPORT (path, may not exist).
# Output: stderr message + non-zero exit if flagged.
#         Zero exit (silent) if report missing OR clean.
scope_halt_check() {
  if [ -f "$VERIFY_REPORT" ] && grep -q '⚠️ Flag' "$VERIFY_REPORT"; then
    echo "HALTED: /verify-changes flagged scope violations in $VERIFY_REPORT." >&2
    echo "Review the Scope Assessment section, fix the diff, re-verify, and re-run." >&2
    return 1
  fi
  return 0
}

# Fixture helpers.
make_flagged_report() {
  local f="$1"
  cat > "$f" <<'REPORT'
# Verify Changes Report

## Summary
All tests green. Scope issue detected.

## Scope Assessment

Reviewed diff against plan goal.

| File | Verdict | Reason |
|------|---------|--------|
| src/feature.js | OK | In-scope for phase 2 |
| src/unrelated.js | ⚠️ Flag | Not referenced by plan — looks like drive-by refactor |

## Recommendations
Remove the unrelated change before landing.
REPORT
}

make_clean_scope_report() {
  local f="$1"
  cat > "$f" <<'REPORT'
# Verify Changes Report

## Summary
All tests green.

## Scope Assessment

Reviewed diff against plan goal.

| File | Verdict | Reason |
|------|---------|--------|
| src/feature.js | OK | In-scope for phase 2 |
| src/feature.test.js | OK | Test for the above |

## Recommendations
Good to land.
REPORT
}

# Case 1: report exists, has flagged row → halt fires.
TMP=$(mktemp -d)
VERIFY_REPORT="$TMP/verify-worktree-feature.md"
make_flagged_report "$VERIFY_REPORT"
STDERR_OUT=$(scope_halt_check 2>&1 >/dev/null)
RC=$?
rm -rf "$TMP"
if [ $RC -ne 0 ] && [[ "$STDERR_OUT" == *"HALTED"* ]] \
   && [[ "$STDERR_OUT" == *"verify-worktree-feature.md"* ]]; then
  pass "case 1: flagged report → exit non-zero, HALTED + report path in stderr"
else
  fail "case 1: flagged report — rc=$RC, stderr: $STDERR_OUT"
fi

# Case 2: report exists, Scope Assessment present but no flag → no halt.
TMP=$(mktemp -d)
VERIFY_REPORT="$TMP/verify-worktree-feature.md"
make_clean_scope_report "$VERIFY_REPORT"
STDERR_OUT=$(scope_halt_check 2>&1 >/dev/null)
RC=$?
rm -rf "$TMP"
if [ $RC -eq 0 ] && [ -z "$STDERR_OUT" ]; then
  pass "case 2: clean Scope Assessment → exit 0, no stderr"
else
  fail "case 2: clean report — rc=$RC, stderr: $STDERR_OUT"
fi

# Case 3: report file missing → graceful pass (old plans without
# /verify-changes invocations).
TMP=$(mktemp -d)
VERIFY_REPORT="$TMP/does-not-exist.md"
STDERR_OUT=$(scope_halt_check 2>&1 >/dev/null)
RC=$?
rm -rf "$TMP"
if [ $RC -eq 0 ] && [ -z "$STDERR_OUT" ]; then
  pass "case 3: missing report → exit 0, graceful silent pass"
else
  fail "case 3: missing report — rc=$RC, stderr: $STDERR_OUT"
fi

# Case 4: report exists with ⚠️ Flag inside a fenced code block that
# LOOKS like prose about the flag convention. The grep is substring-
# based by design, so this SHOULD halt — the halt is conservative
# (false-positive-biased) per the skill's pre-landing checklist rule.
# If the skill's grep pattern tightens later, this test must update.
TMP=$(mktemp -d)
VERIFY_REPORT="$TMP/prose-mention.md"
cat > "$VERIFY_REPORT" <<'REPORT'
# Notes
The review format uses ⚠️ Flag in the Verdict column to mark concerns.
REPORT
STDERR_OUT=$(scope_halt_check 2>&1 >/dev/null)
RC=$?
rm -rf "$TMP"
if [ $RC -ne 0 ] && [[ "$STDERR_OUT" == *"HALTED"* ]]; then
  pass "case 4: prose mention of flag → halts (conservative: false-positive bias is a safety feature)"
else
  fail "case 4: prose mention — rc=$RC, stderr: $STDERR_OUT"
fi

# Case 5: verify the skill's pre-landing checklist actually uses the
# grep pattern this test validates. If the skill changes the pattern,
# this test drifts out of sync.
if grep -F "grep -q \"⚠️ Flag\"" "$REPO_ROOT/skills/run-plan/SKILL.md" >/dev/null; then
  pass "skill pre-landing checklist uses the '⚠️ Flag' grep pattern"
else
  fail "skill does not use 'grep -q \"⚠️ Flag\"' — test may be out of sync"
fi

# Case 6: verify the skill uses the HALTED error message prefix.
if grep -q 'HALTED: /verify-changes flagged scope violations' "$REPO_ROOT/skills/run-plan/SKILL.md"; then
  pass "skill emits 'HALTED: /verify-changes flagged scope violations' message"
else
  fail "skill missing HALTED error message prefix"
fi

echo ""
echo "---"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
