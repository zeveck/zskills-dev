#!/bin/bash
# tests/test-plan-claim-cron-fire-state-machine.sh — Phase 2a W2a.9 / AC2a.3.
#
# Exercises all three branches of the W2a.3 cron-fire dormant-window state
# machine, simulated by running the state-machine fence body against
# pre-staged claim-dir states. Branches:
#   (1) refresh exit 0 → proceed (claim present, pipeline matches).
#   (2) refresh exit 12 → STOP (claim present, pipeline mismatch).
#   (3) refresh exit 2 → re-acquire via claim-plan.sh acquire.
#       (3a) re-acquire returns 0 → proceed.
#       (3b) re-acquire returns 10 → STOP with "acquired by another
#            pipeline during cron-fire dormant window" message.
#
# Implementation: the state-machine fence is reproduced verbatim from
# the W2a.3 design block here as a shell function `run_state_machine`,
# and the test pre-stages the on-disk claim state for each branch.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAIM_SH="$REPO_ROOT/skills/run-plan/scripts/claim-plan.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SCRATCH_ROOT="/tmp/test-plan-claim-cron-state-$$"
cleanup() {
  if [ -n "${TEST_KEEP_SCRATCH:-}" ]; then return; fi
  if [ -d "$SCRATCH_ROOT" ]; then
    find "$SCRATCH_ROOT" -mindepth 1 -delete 2>/dev/null || true
    rmdir "$SCRATCH_ROOT" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM
mkdir -p "$SCRATCH_ROOT"

export CLAUDE_PROJECT_DIR="$REPO_ROOT"

echo "=== plan-claim cron-fire dormant-window state machine ==="

FIXTURE="$SCRATCH_ROOT/fixture"
mkdir -p "$FIXTURE"
( cd "$FIXTURE" && git init -q && git config user.email "t@t" && git config user.name "t" \
  && git commit --allow-empty -q -m "init" ) \
  || { echo "FATAL: fixture init failed" >&2; exit 1; }

# Verbatim copy of the W2a.3 state-machine fence as a function.
run_state_machine() {
  local slug="$1" pid="$2"
  set +e
  bash "$CLAIM_SH" refresh "$slug" \
    --require-pipeline "$pid" \
    --current-phase "test-phase"
  local rc=$?
  set -e
  case "$rc" in
    0) return 0 ;;
    12) echo "Claim was taken over by another pipeline; aborting." >&2; return 1 ;;
    2)
      set +e
      bash "$CLAIM_SH" acquire "$slug" --pipeline-id "$pid"
      local rc2=$?
      set -e
      if [ "$rc2" -eq 10 ]; then
        echo "Claim was acquired by another pipeline during the cron-fire dormant window; aborting." >&2
        return 1
      fi
      [ "$rc2" -eq 0 ] || { echo "Re-acquire failed (rc=$rc2)" >&2; return 1; }
      return 0
      ;;
    *) echo "Refresh failed (rc=$rc)" >&2; return 1 ;;
  esac
}

# ─────────────────────────────────────────────────────────────────────
# Branch 1: refresh exit 0 (claim present + pipeline matches).
# ─────────────────────────────────────────────────────────────────────
rm -rf "$FIXTURE/.zskills/claims"
SLUG="branch-1-proceed"
PIPELINE="run-plan.$SLUG"
( cd "$FIXTURE" && bash "$CLAIM_SH" acquire "$SLUG" --pipeline-id "$PIPELINE" >/dev/null 2>&1 ) \
  || { fail "branch-1 setup" "could not acquire claim"; }

out_file="$SCRATCH_ROOT/branch1.out"
( cd "$FIXTURE" && run_state_machine "$SLUG" "$PIPELINE" ) > "$out_file" 2>&1
sm_rc=$?
if [ "$sm_rc" -eq 0 ]; then
  pass "branch 1 (refresh exit 0 → proceed): state machine returns 0"
else
  fail "branch 1: state machine rc" "expected 0, got $sm_rc; output: $(cat "$out_file")"
fi
if ! grep -q "aborting" "$out_file"; then
  pass "branch 1: no abort message"
else
  fail "branch 1: no abort message" "stdout=$(cat "$out_file")"
fi

# ─────────────────────────────────────────────────────────────────────
# Branch 2: refresh exit 12 (claim present + pipeline mismatch).
# ─────────────────────────────────────────────────────────────────────
rm -rf "$FIXTURE/.zskills/claims"
SLUG="branch-2-mismatch"
OTHER_PIPELINE="run-plan.other"
OUR_PIPELINE="run-plan.us"
( cd "$FIXTURE" && bash "$CLAIM_SH" acquire "$SLUG" --pipeline-id "$OTHER_PIPELINE" >/dev/null 2>&1 ) \
  || { fail "branch-2 setup" "could not acquire claim as other"; }

out_file="$SCRATCH_ROOT/branch2.out"
( cd "$FIXTURE" && run_state_machine "$SLUG" "$OUR_PIPELINE" ) > "$out_file" 2>&1
sm_rc=$?
if [ "$sm_rc" -eq 1 ]; then
  pass "branch 2 (refresh exit 12 → STOP): state machine returns 1"
else
  fail "branch 2: state machine rc" "expected 1, got $sm_rc; output: $(cat "$out_file")"
fi
if grep -q "Claim was taken over by another pipeline; aborting" "$out_file"; then
  pass "branch 2: taken-over abort message present"
else
  fail "branch 2: abort message" "missing 'taken over' message; output: $(cat "$out_file")"
fi

# ─────────────────────────────────────────────────────────────────────
# Branch 3a: refresh exit 2 (claim absent) → re-acquire succeeds.
# ─────────────────────────────────────────────────────────────────────
rm -rf "$FIXTURE/.zskills/claims"
SLUG="branch-3a-reacquire"
PIPELINE="run-plan.$SLUG"
# Don't pre-create the claim — refresh will exit 2.

out_file="$SCRATCH_ROOT/branch3a.out"
( cd "$FIXTURE" && run_state_machine "$SLUG" "$PIPELINE" ) > "$out_file" 2>&1
sm_rc=$?
if [ "$sm_rc" -eq 0 ]; then
  pass "branch 3a (refresh exit 2 → re-acquire 0 → proceed): state machine returns 0"
else
  fail "branch 3a: state machine rc" "expected 0, got $sm_rc; output: $(cat "$out_file")"
fi
# claim.json should now exist with our pipeline
claim_file="$FIXTURE/.zskills/claims/plan-$SLUG/claim.json"
if [ -f "$claim_file" ]; then
  actual_pid=$(python3 -c "import json, sys; print(json.load(open(sys.argv[1])).get('pipeline_id',''))" "$claim_file")
  if [ "$actual_pid" = "$PIPELINE" ]; then
    pass "branch 3a: re-acquired claim contains our pipeline_id"
  else
    fail "branch 3a: re-acquired pipeline" "expected=$PIPELINE actual=$actual_pid"
  fi
else
  fail "branch 3a: claim.json on disk" "missing at $claim_file"
fi

# ─────────────────────────────────────────────────────────────────────
# Branch 3b: refresh exit 2 (claim absent) → re-acquire returns 10 (race).
# To simulate: claim dir gets created by an "other" pipeline between
# refresh and re-acquire. We do this by leaving a claim from another
# pipeline on disk and clearing claim.json so refresh sees "claim absent".
# Actually simpler: claim is present but for ANOTHER pipeline — but
# then refresh returns 12, not 2. The true "claim absent + race-lost
# re-acquire" requires a window we can't deterministically reproduce
# without forking. Use the existing claim-dir-with-other-pipeline
# scenario as the closest reproducible analog by stating the fence
# directly with a re-acquire that hits another pipeline's claim.
# ─────────────────────────────────────────────────────────────────────
rm -rf "$FIXTURE/.zskills/claims"
SLUG="branch-3b-race"
PIPELINE="run-plan.$SLUG"
OTHER="run-plan.race-winner"

# Stage: claim dir exists but claim.json is missing (mimics the partial-
# acquire window the W2a.3 state machine handles).
mkdir -p "$FIXTURE/.zskills/claims/plan-$SLUG"
# Now race a separate pipeline in via acquire BEFORE we run the state
# machine — that gives us EEXIST on re-acquire.
# But: refresh will see "claim dir exists, claim.json missing" → exit 2.
# Then re-acquire will see "claim dir exists" → exit 10.
out_file="$SCRATCH_ROOT/branch3b.out"
( cd "$FIXTURE" && run_state_machine "$SLUG" "$PIPELINE" ) > "$out_file" 2>&1
sm_rc=$?
if [ "$sm_rc" -eq 1 ]; then
  pass "branch 3b (refresh exit 2 → re-acquire exit 10 → STOP): state machine returns 1"
else
  fail "branch 3b: state machine rc" "expected 1, got $sm_rc; output: $(cat "$out_file")"
fi
if grep -q "Claim was acquired by another pipeline during the cron-fire dormant window; aborting" "$out_file"; then
  pass "branch 3b: race-lost abort message present"
else
  fail "branch 3b: abort message" "missing race-lost message; output: $(cat "$out_file")"
fi

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (%d total)\033[0m\n' "$PASS_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (%d total)\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit 1
fi
