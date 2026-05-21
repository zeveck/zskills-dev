#!/bin/bash
# tests/test-fix-issues-claim-race-e2e.sh — Phase 4 W4.1.
#
# Load-bearing concurrency proof for plans/fix-issues-claims.md:
# two backgrounded subshells call claim-issue.sh acquire 42 against the
# same fixture repo. The atomic-mkdir primitive guarantees exactly one
# winner (exit 0) and one loser (exit 10), regardless of wall-clock
# spacing — this stands in for two concurrent /fix-issues sessions in
# two terminals (real cross-process semantics, not Python threading).
#
# Asserts:
#   - exactly one subshell exits 0; the other exits 10
#   - claim.json on disk contains the winner's pipeline_id
#
# Concurrent-pipeline framing per plan W4.1: the two `&` subshells are
# separate OS processes with independent timing. No spacing control is
# needed; mkdir is the atomic primitive that wins exactly one.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAIM_SH="$REPO_ROOT/skills/fix-issues/scripts/claim-issue.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SCRATCH_ROOT="/tmp/test-claim-race-e2e-$$"
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

if [ ! -f "$CLAIM_SH" ]; then
  echo "FATAL: claim-issue.sh missing at $CLAIM_SH" >&2
  exit 1
fi

echo "=== claim-issue.sh real-process race (E2E) ==="

# Fresh fixture git repo so claim-issue.sh's MAIN_ROOT resolves cleanly.
FIXTURE="$SCRATCH_ROOT/fixture"
mkdir -p "$FIXTURE"
( cd "$FIXTURE" && git init -q && git config user.email "t@t" && git config user.name "t" \
  && git commit --allow-empty -q -m "init" ) \
  || { echo "FATAL: fixture init failed" >&2; exit 1; }

# Per-iteration concurrency check. Repeat several times to make ordering
# bias unlikely — atomic mkdir should produce exactly-one-winner every time.
ITERATIONS=5
overall_ok=1
for i in $(seq 1 "$ITERATIONS"); do
  # Clean slate for this iteration.
  rm -rf "$FIXTURE/.zskills/claims"

  out_a="$SCRATCH_ROOT/iter-${i}-stdout.A"
  out_b="$SCRATCH_ROOT/iter-${i}-stdout.B"
  ec_a="$SCRATCH_ROOT/iter-${i}-ec.A"
  ec_b="$SCRATCH_ROOT/iter-${i}-ec.B"

  (
    cd "$FIXTURE" || exit 1
    bash "$CLAIM_SH" acquire 42 --pipeline-id "pipe-A-$i" --sprint-id "sprint-A-$i" > "$out_a" 2>&1
    echo $? > "$ec_a"
  ) &
  (
    cd "$FIXTURE" || exit 1
    bash "$CLAIM_SH" acquire 42 --pipeline-id "pipe-B-$i" --sprint-id "sprint-B-$i" > "$out_b" 2>&1
    echo $? > "$ec_b"
  ) &
  wait

  rc_a=$(cat "$ec_a")
  rc_b=$(cat "$ec_b")

  # Exactly-one-winner: (0,10) or (10,0).
  if ! { { [ "$rc_a" = "0" ] && [ "$rc_b" = "10" ]; } || { [ "$rc_a" = "10" ] && [ "$rc_b" = "0" ]; }; }; then
    fail "iteration $i exactly-one-winner" "rc_a=$rc_a rc_b=$rc_b (expected one 0, one 10); A stdout: $(cat "$out_a"); B stdout: $(cat "$out_b")"
    overall_ok=0
    continue
  fi

  # On-disk winner persistence.
  if [ "$rc_a" = "0" ]; then
    expected_pipeline="pipe-A-$i"
  else
    expected_pipeline="pipe-B-$i"
  fi
  claim_file="$FIXTURE/.zskills/claims/issue-42/claim.json"
  if [ ! -f "$claim_file" ]; then
    fail "iteration $i winner claim.json on disk" "claim.json missing at $claim_file"
    overall_ok=0
    continue
  fi
  actual_pipeline=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    print(json.load(f).get('pipeline_id',''))
" "$claim_file")
  if [ "$actual_pipeline" != "$expected_pipeline" ]; then
    fail "iteration $i winner pipeline_id persists" "expected=$expected_pipeline actual=$actual_pipeline"
    overall_ok=0
    continue
  fi
done

if [ "$overall_ok" = "1" ]; then
  pass "race-e2e: $ITERATIONS rounds, exactly-one-winner with on-disk pipeline_id matching the winner each time"
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
