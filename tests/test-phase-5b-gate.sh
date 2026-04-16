#!/bin/bash
# Tests for /run-plan Phase 5b's final-verify gate state machine.
#
# Gate behavior is specified in skills/run-plan/SKILL.md, Phase 5b
# section 0b ("Final-verify gate"). The gate's bash is entangled
# with Phase 5b prose, so this test re-implements the state-machine
# logic inline as `phase_5b_gate()` — matching the skill's algorithm
# exactly — and exercises it against synthesized tracking state.
#
# Assertions target the gate's PUBLIC CONTRACT:
#   - idempotent early-exit when frontmatter says status: complete
#   - branch selection (marker+fulfilled, marker-only, no-marker)
#   - attempt counter progression (1, 2, 3, 4+)
#   - backoff schedule (10, 20, 40, 60 min) capped at 60
#   - cron A ("verify cron") scheduled ONLY on attempt 1
#   - cron B ("re-entry cron") scheduled on every attempt
#   - counter file deleted when fulfillment arrives
#
# If the real skill's gate diverges from this state machine, the
# skill is wrong OR this test is stale — read both, decide which.
# The invariants test (test-skill-invariants.sh) locks down anchors
# ("Final-verify gate", idempotent early-exit line) so the gate
# cannot be silently deleted.

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

# Re-implementation of the Phase 5b gate state machine. Reads:
#   FRONTMATTER_STATUS, MARKER, FULFILLED, ATTEMPTS_FILE
# Emits decisions as structured text on stdout:
#   EXIT <reason>   — return 0 and do no work (early exit or gate defer)
#   PROCEED         — fall through to Phase 5b steps 1–4
# And side-effect lines for the mocked scheduler:
#   CRON_VERIFY <prompt>
#   CRON_REENTRY <backoff_min> <prompt>
#   WRITE_COUNTER <value>
#   DELETE_COUNTER
phase_5b_gate() {
  # 0a. Idempotent early-exit
  if [ "$FRONTMATTER_STATUS" = "complete" ]; then
    echo "EXIT idempotent-early-exit"
    return 0
  fi

  # 0b. Final-verify gate
  if [ ! -f "$MARKER" ]; then
    # Case: no marker → proceed (standalone plan)
    echo "PROCEED no-marker"
    return 0
  fi
  if [ -f "$FULFILLED" ]; then
    # Case: fulfilled → delete counter, proceed
    echo "DELETE_COUNTER"
    echo "PROCEED fulfilled"
    return 0
  fi

  # Marker exists AND fulfillment missing → self-rescheduling branch
  if [ -f "$ATTEMPTS_FILE" ]; then
    ATTEMPT=$(( $(cat "$ATTEMPTS_FILE") + 1 ))
  else
    ATTEMPT=1
  fi
  echo "WRITE_COUNTER $ATTEMPT"

  case "$ATTEMPT" in
    1) BACKOFF_MIN=10 ;;
    2) BACKOFF_MIN=20 ;;
    3) BACKOFF_MIN=40 ;;
    *) BACKOFF_MIN=60 ;;
  esac

  if [ "$ATTEMPT" -eq 1 ]; then
    echo "CRON_VERIFY Run /verify-changes branch tracking-id=$TRACKING_ID"
  fi
  echo "CRON_REENTRY $BACKOFF_MIN Run /run-plan $PLAN_FILE finish auto"
  echo "EXIT gate-defer attempt=$ATTEMPT backoff=$BACKOFF_MIN"
  return 0
}

# Fixture setup
setup_fixture() {
  FIXTURE_DIR=$(mktemp -d)
  mkdir -p "$FIXTURE_DIR/tracking"
  MARKER="$FIXTURE_DIR/tracking/requires.verify-changes.final.demo"
  FULFILLED="$FIXTURE_DIR/tracking/fulfilled.verify-changes.final.demo"
  ATTEMPTS_FILE="$FIXTURE_DIR/tracking/verify-pending-attempts.demo"
  TRACKING_ID="demo"
  PLAN_FILE="plans/demo.md"
  FRONTMATTER_STATUS="active"
}

teardown_fixture() {
  [ -n "$FIXTURE_DIR" ] && rm -rf "$FIXTURE_DIR"
  FIXTURE_DIR=""
}

# Case 1: marker exists, no fulfillment, no attempt counter → defer,
# counter becomes 1, both crons scheduled, backoff = 10.
setup_fixture
: > "$MARKER"
OUT=$(phase_5b_gate)
teardown_fixture
if [[ "$OUT" == *"WRITE_COUNTER 1"* ]] \
   && [[ "$OUT" == *"CRON_VERIFY Run /verify-changes branch tracking-id=demo"* ]] \
   && [[ "$OUT" == *"CRON_REENTRY 10 Run /run-plan"* ]] \
   && [[ "$OUT" == *"EXIT gate-defer attempt=1 backoff=10"* ]]; then
  pass "case 1: attempt=1 → counter=1, verify cron + 10min re-entry"
else
  fail "case 1: attempt=1 — got: $OUT"
fi

# Case 2: attempt counter = 1 → next attempt becomes 2, backoff = 20,
# NO verify cron this round (already scheduled on attempt 1).
setup_fixture
: > "$MARKER"
echo 1 > "$ATTEMPTS_FILE"
OUT=$(phase_5b_gate)
teardown_fixture
if [[ "$OUT" == *"WRITE_COUNTER 2"* ]] \
   && [[ "$OUT" != *"CRON_VERIFY"* ]] \
   && [[ "$OUT" == *"CRON_REENTRY 20"* ]] \
   && [[ "$OUT" == *"EXIT gate-defer attempt=2 backoff=20"* ]]; then
  pass "case 2: attempt=2 → backoff=20, no verify cron reschedule"
else
  fail "case 2: attempt=2 — got: $OUT"
fi

# Case 2b: attempt counter = 2 → next attempt = 3, backoff = 40.
setup_fixture
: > "$MARKER"
echo 2 > "$ATTEMPTS_FILE"
OUT=$(phase_5b_gate)
teardown_fixture
if [[ "$OUT" == *"WRITE_COUNTER 3"* ]] \
   && [[ "$OUT" != *"CRON_VERIFY"* ]] \
   && [[ "$OUT" == *"CRON_REENTRY 40"* ]] \
   && [[ "$OUT" == *"EXIT gate-defer attempt=3 backoff=40"* ]]; then
  pass "case 2b: attempt=3 → backoff=40"
else
  fail "case 2b: attempt=3 — got: $OUT"
fi

# Case 2c: attempt counter = 3 → next attempt = 4, backoff capped at 60.
setup_fixture
: > "$MARKER"
echo 3 > "$ATTEMPTS_FILE"
OUT=$(phase_5b_gate)
teardown_fixture
if [[ "$OUT" == *"WRITE_COUNTER 4"* ]] \
   && [[ "$OUT" == *"CRON_REENTRY 60"* ]] \
   && [[ "$OUT" == *"EXIT gate-defer attempt=4 backoff=60"* ]]; then
  pass "case 2c: attempt=4 → backoff=60 (cap)"
else
  fail "case 2c: attempt=4 — got: $OUT"
fi

# Case 2d: attempt counter = 10 → backoff stays at 60 (still capped).
setup_fixture
: > "$MARKER"
echo 10 > "$ATTEMPTS_FILE"
OUT=$(phase_5b_gate)
teardown_fixture
if [[ "$OUT" == *"WRITE_COUNTER 11"* ]] \
   && [[ "$OUT" == *"CRON_REENTRY 60"* ]] \
   && [[ "$OUT" == *"EXIT gate-defer attempt=11 backoff=60"* ]]; then
  pass "case 2d: attempt=11 → backoff stays at 60 (cap holds)"
else
  fail "case 2d: attempt=11 — got: $OUT"
fi

# Case 3: fulfillment exists → gate proceeds, counter marked for delete.
setup_fixture
: > "$MARKER"
: > "$FULFILLED"
echo 2 > "$ATTEMPTS_FILE"
OUT=$(phase_5b_gate)
teardown_fixture
if [[ "$OUT" == *"DELETE_COUNTER"* ]] \
   && [[ "$OUT" == *"PROCEED fulfilled"* ]] \
   && [[ "$OUT" != *"CRON_VERIFY"* ]] \
   && [[ "$OUT" != *"CRON_REENTRY"* ]]; then
  pass "case 3: fulfilled → DELETE_COUNTER + PROCEED, no crons"
else
  fail "case 3: fulfilled — got: $OUT"
fi

# Case 4: no marker → gate proceeds directly.
setup_fixture
OUT=$(phase_5b_gate)
teardown_fixture
if [[ "$OUT" == *"PROCEED no-marker"* ]] \
   && [[ "$OUT" != *"CRON_VERIFY"* ]] \
   && [[ "$OUT" != *"CRON_REENTRY"* ]] \
   && [[ "$OUT" != *"WRITE_COUNTER"* ]]; then
  pass "case 4: no marker → PROCEED, no scheduler side effects"
else
  fail "case 4: no marker — got: $OUT"
fi

# Case 5: frontmatter status: complete → idempotent early-exit fires
# BEFORE the gate. No scheduler actions even if marker is unfulfilled.
setup_fixture
: > "$MARKER"   # marker present, would normally trigger defer
FRONTMATTER_STATUS="complete"
OUT=$(phase_5b_gate)
teardown_fixture
if [[ "$OUT" == *"EXIT idempotent-early-exit"* ]] \
   && [[ "$OUT" != *"CRON_VERIFY"* ]] \
   && [[ "$OUT" != *"CRON_REENTRY"* ]] \
   && [[ "$OUT" != *"WRITE_COUNTER"* ]] \
   && [[ "$OUT" != *"PROCEED"* ]]; then
  pass "case 5: frontmatter complete → idempotent early-exit, no gate actions"
else
  fail "case 5: frontmatter complete — got: $OUT"
fi

# Case 6: verify the gate logic in the actual skill matches the
# reference implementation's backoff table. Grep for each case arm.
if grep -q '1) BACKOFF_MIN=10' "$REPO_ROOT/skills/run-plan/SKILL.md" \
   && grep -q '2) BACKOFF_MIN=20' "$REPO_ROOT/skills/run-plan/SKILL.md" \
   && grep -q '3) BACKOFF_MIN=40' "$REPO_ROOT/skills/run-plan/SKILL.md" \
   && grep -q '\*) BACKOFF_MIN=60' "$REPO_ROOT/skills/run-plan/SKILL.md"; then
  pass "backoff table in skill matches (10, 20, 40, 60)"
else
  fail "backoff table in skill does not match reference 10/20/40/60"
fi

# Case 7: verify "On attempt 1 only" guidance for verify-cron scheduling.
if grep -q 'On attempt 1 only' "$REPO_ROOT/skills/run-plan/SKILL.md"; then
  pass "skill documents 'On attempt 1 only' for verify-cron scheduling"
else
  fail "skill missing 'On attempt 1 only' guidance"
fi

echo ""
echo "---"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
