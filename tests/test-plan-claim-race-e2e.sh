#!/bin/bash
# tests/test-plan-claim-race-e2e.sh — Phase 2a W2a.7 / AC2a.1.
#
# Mirrors tests/test-fix-issues-claim-race-e2e.sh for the plan-side acquire
# fence prose path. Two backgrounded subshells simulate the W2a.1 acquire
# bash fence ("set +e; bash claim-plan.sh acquire ...; case $rc in 10) echo
# decline; exit 0;; ...") executed against the same plan slug in a clean
# fixture repo. The atomic-mkdir primitive guarantees exactly one winner
# (exit 0) and one loser (exit 0 BUT decline-message-emitted) regardless
# of wall-clock spacing.
#
# Asserts (mirrors AC2a.1):
#   - exactly one subshell exits 0 with NO decline message (the acquirer);
#     the other exits 0 WITH a decline message containing the slug
#   - claim.json on disk contains the winner's pipeline_id
#   - the decline message names the plan slug (so the user can tell which
#     plan was declined when multiple are in flight)

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAIM_SH="$REPO_ROOT/skills/run-plan/scripts/claim-plan.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SCRATCH_ROOT="/tmp/test-plan-claim-race-e2e-$$"
cleanup() {
  if [ -n "${TEST_KEEP_SCRATCH:-}" ]; then
    echo "TEST_KEEP_SCRATCH set — leaving $SCRATCH_ROOT" >&2
    return
  fi
  if [ -d "$SCRATCH_ROOT" ]; then
    find "$SCRATCH_ROOT" -mindepth 1 -delete 2>/dev/null || true
    rmdir "$SCRATCH_ROOT" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM
mkdir -p "$SCRATCH_ROOT"

export CLAUDE_PROJECT_DIR="$REPO_ROOT"

if [ ! -f "$CLAIM_SH" ]; then
  echo "FATAL: claim-plan.sh missing at $CLAIM_SH" >&2
  exit 1
fi

echo "=== plan-claim race E2E (W2a.1 acquire-fence prose simulation) ==="

# Fresh fixture so MAIN_ROOT resolves locally.
FIXTURE="$SCRATCH_ROOT/fixture"
mkdir -p "$FIXTURE"
( cd "$FIXTURE" && git init -q && git config user.email "t@t" && git config user.name "t" \
  && git commit --allow-empty -q -m "init" ) \
  || { echo "FATAL: fixture init failed" >&2; exit 1; }

# Simulate the W2a.1 prose acquire fence as a function. Mirror the case
# arm: exit 10 → decline message + exit 0. Other arms map per W2a.1
# error-mapping table.
plan_acquire_fence() {
  local fixture="$1" slug="$2" pid="$3" out_file="$4" ec_file="$5"
  (
    cd "$fixture" || { echo 99 > "$ec_file"; exit 99; }
    set +e
    bash "$CLAIM_SH" acquire "$slug" --pipeline-id "$pid" > "$out_file" 2>&1
    local rc=$?
    set -e
    local fence_rc
    case "$rc" in
      0) fence_rc=0 ;;
      10) echo "Plan $slug is in-flight by another pipeline; this invocation declined." >> "$out_file"; fence_rc=0 ;;
      11) echo "claim-plan.sh acquire infrastructure failure" >> "$out_file"; fence_rc=1 ;;
      2)  echo "claim-plan.sh acquire usage error" >> "$out_file"; fence_rc=2 ;;
      *)  echo "claim-plan.sh acquire unexpected rc=$rc" >> "$out_file"; fence_rc=1 ;;
    esac
    echo "$fence_rc" > "$ec_file"
  )
}

ITERATIONS=5
overall_ok=1
for i in $(seq 1 "$ITERATIONS"); do
  rm -rf "$FIXTURE/.zskills/claims"
  SLUG="race-plan-$i"
  out_a="$SCRATCH_ROOT/iter-${i}-stdout.A"
  out_b="$SCRATCH_ROOT/iter-${i}-stdout.B"
  ec_a="$SCRATCH_ROOT/iter-${i}-ec.A"
  ec_b="$SCRATCH_ROOT/iter-${i}-ec.B"

  plan_acquire_fence "$FIXTURE" "$SLUG" "run-plan.A-$i" "$out_a" "$ec_a" &
  plan_acquire_fence "$FIXTURE" "$SLUG" "run-plan.B-$i" "$out_b" "$ec_b" &
  wait

  rc_a=$(cat "$ec_a"); rc_b=$(cat "$ec_b")

  # Both fence invocations exit 0 (per W2a.1 case arm — decline is a
  # graceful exit 0, not a failure).
  if [ "$rc_a" != "0" ] || [ "$rc_b" != "0" ]; then
    fail "iteration $i: both fences exit 0" "rc_a=$rc_a rc_b=$rc_b"
    overall_ok=0
    continue
  fi

  # Exactly one decline message printed.
  decline_count=0
  for f in "$out_a" "$out_b"; do
    if grep -q "Plan $SLUG is in-flight by another pipeline" "$f"; then
      decline_count=$((decline_count + 1))
    fi
  done
  if [ "$decline_count" != "1" ]; then
    fail "iteration $i: exactly one decline" "decline_count=$decline_count; A: $(cat "$out_a") | B: $(cat "$out_b")"
    overall_ok=0
    continue
  fi

  # Winner's pipeline_id on disk.
  claim_file="$FIXTURE/.zskills/claims/plan-$SLUG/claim.json"
  if [ ! -f "$claim_file" ]; then
    fail "iteration $i: winner claim.json" "missing at $claim_file"
    overall_ok=0
    continue
  fi
  winner=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    print(json.load(f).get('pipeline_id',''))
" "$claim_file")
  case "$winner" in
    run-plan.A-$i|run-plan.B-$i) : ;;
    *) fail "iteration $i: winner pipeline_id" "got '$winner'"; overall_ok=0; continue ;;
  esac

  # Winner's stdout should NOT contain decline message; loser's should.
  if grep -q "declined" "$out_a"; then loser_out="$out_a"; else loser_out="$out_b"; fi
  if ! grep -q "Plan $SLUG is in-flight by another pipeline" "$loser_out"; then
    fail "iteration $i: decline message names slug" "loser=$loser_out content=$(cat "$loser_out")"
    overall_ok=0
    continue
  fi
done

if [ "$overall_ok" = "1" ]; then
  pass "race-e2e: $ITERATIONS rounds, exactly-one-winner with decline message naming the slug"
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
