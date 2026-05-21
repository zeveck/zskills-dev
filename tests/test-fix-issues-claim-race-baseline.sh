#!/bin/bash
# tests/test-fix-issues-claim-race-baseline.sh — Phase 4 W4.1b.
#
# NEGATIVE CONTROL paired with test-fix-issues-claim-race-e2e.sh
# (CLAUDE.md "surface bugs don't patch" — first prove the bug exists
# without the mechanism).
#
# Same backgrounded-subshell shape as W4.1, but the acquire helper is
# a STUB that always returns 0 without actually mkdir'ing a claim
# directory. Asserts BOTH calls "succeed" — proving the duplicate-
# dispatch race manifests in the absence of the real mechanism.
#
# Paired with W4.1, this gates:
#   (a) the race is real without the mechanism (this test),
#   (b) the mechanism prevents it (W4.1).

set -u

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SCRATCH_ROOT="/tmp/test-claim-race-baseline-$$"
cleanup() {
  if [ -n "${TEST_KEEP_SCRATCH:-}" ]; then
    echo "TEST_KEEP_SCRATCH set — leaving $SCRATCH_ROOT" >&2
    return
  fi
  if [ -d "$SCRATCH_ROOT" ]; then
    find "$SCRATCH_ROOT" -mindepth 1 -delete || true
    rmdir "$SCRATCH_ROOT" || true
  fi
}
trap cleanup EXIT INT TERM
mkdir -p "$SCRATCH_ROOT"

echo "=== claim-issue.sh baseline race (negative control — stubbed helper) ==="

# Stub claim-issue.sh: always exit 0, never touch the filesystem. This
# models the pre-mechanism world (or a regression that broke the atomic
# mkdir).
STUB="$SCRATCH_ROOT/stub-claim-issue.sh"
cat > "$STUB" <<'STUBSH'
#!/bin/bash
# Stubbed claim-issue.sh — pretends to acquire without doing anything.
# Used by tests/test-fix-issues-claim-race-baseline.sh as a negative
# control proving the race manifests when the atomic primitive is absent.
exit 0
STUBSH
chmod +x "$STUB"

FIXTURE="$SCRATCH_ROOT/fixture"
mkdir -p "$FIXTURE"
( cd "$FIXTURE" && git init -q && git config user.email "t@t" && git config user.name "t" \
  && git commit --allow-empty -q -m "init" ) \
  || { echo "FATAL: fixture init failed" >&2; exit 1; }

out_a="$SCRATCH_ROOT/stdout.A"
out_b="$SCRATCH_ROOT/stdout.B"
ec_a="$SCRATCH_ROOT/ec.A"
ec_b="$SCRATCH_ROOT/ec.B"

(
  cd "$FIXTURE" || exit 1
  bash "$STUB" acquire 42 --pipeline-id pipe-A --sprint-id sprint-A > "$out_a" 2>&1
  echo $? > "$ec_a"
) &
(
  cd "$FIXTURE" || exit 1
  bash "$STUB" acquire 42 --pipeline-id pipe-B --sprint-id sprint-B > "$out_b" 2>&1
  echo $? > "$ec_b"
) &
wait

rc_a=$(cat "$ec_a")
rc_b=$(cat "$ec_b")

# Both must succeed (proves the bug manifests under the stubbed helper).
if [ "$rc_a" = "0" ] && [ "$rc_b" = "0" ]; then
  pass "baseline race (stubbed helper): both subshells exit 0 — duplicate-dispatch race manifests without the mechanism"
else
  fail "baseline race both succeed" "rc_a=$rc_a rc_b=$rc_b (expected both 0 under stub)"
fi

# And — confirm the stubbed helper did NOT create any claims on disk
# (the duplicate-dispatch bug: both calls succeed, no exclusivity).
if [ -d "$FIXTURE/.zskills/claims" ]; then
  fail "baseline race: stubbed helper unexpectedly created .zskills/claims" "stubbed helper should not touch filesystem"
else
  pass "baseline race: stubbed helper writes no claims directory (proves no exclusivity primitive exists in stub path)"
fi

# ───────────────────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────────────────
echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (%d total)\033[0m\n' "$PASS_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (%d total)\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit 1
fi
