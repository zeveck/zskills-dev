#!/bin/bash
# tests/test-plan-claim-race-baseline.sh — Phase 1 W1.6.
#
# Mirror of tests/test-fix-issues-claim-race-baseline.sh for the plan-side
# atomic-mkdir primitive. Two backgrounded `claim-plan.sh acquire` calls
# from a clean state on the SAME slug: exactly one must return 0 and
# exactly one must return 10 (EEXIST). The asymmetry is the POSIX atomic
# mkdir guarantee — the loser sees "File exists" and exits 10, never 0.
#
# Pairs structurally with claim-issue.sh's baseline test and W1.5's
# "duplicate acquire returns exit 10" assertion; this one specifically
# exercises the BACKGROUNDED-CONCURRENT shape (vs serial duplicate).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAIM_SH="$REPO_ROOT/skills/run-plan/scripts/claim-plan.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SCRATCH_ROOT="/tmp/test-plan-claim-race-baseline-$$"
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

# claim-plan.sh's _locate_sanitizer falls back to CLAUDE_PROJECT_DIR for
# the sanitize-pipeline-id.sh lookup; point it at the repo root.
export CLAUDE_PROJECT_DIR="$REPO_ROOT"

echo "=== claim-plan.sh parallel-acquire baseline race ==="

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
  bash "$CLAIM_SH" acquire same-slug --pipeline-id "run-plan.A" > "$out_a" 2>&1
  echo $? > "$ec_a"
) &
(
  cd "$FIXTURE" || exit 1
  bash "$CLAIM_SH" acquire same-slug --pipeline-id "run-plan.B" > "$out_b" 2>&1
  echo $? > "$ec_b"
) &
wait

rc_a=$(cat "$ec_a")
rc_b=$(cat "$ec_b")

# Exactly one 0 and one 10.
if { [ "$rc_a" = "0" ] && [ "$rc_b" = "10" ]; } || { [ "$rc_a" = "10" ] && [ "$rc_b" = "0" ]; }; then
  pass "parallel acquire on same slug: exactly one exit 0 + one exit 10 (rc_a=$rc_a rc_b=$rc_b)"
else
  fail "parallel acquire exit codes" "expected (0,10) or (10,0); got rc_a=$rc_a rc_b=$rc_b"
fi

# Exactly one claim.json exists with a pipeline_id matching the winner.
CLAIM_FILE="$FIXTURE/.zskills/claims/plan-same-slug/claim.json"
if [ ! -f "$CLAIM_FILE" ]; then
  fail "race winner left claim.json on disk" "no file at $CLAIM_FILE"
else
  PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
  WINNER=$("$PYTHON" -c "import json; print(json.load(open('$CLAIM_FILE'))['pipeline_id'])")
  case "$WINNER" in
    run-plan.A|run-plan.B)
      # And winner's exit code must be 0; the loser's the 10.
      if [ "$rc_a" = "0" ] && [ "$WINNER" = "run-plan.A" ]; then
        pass "race winner identity consistent (A won, A had rc=0)"
      elif [ "$rc_b" = "0" ] && [ "$WINNER" = "run-plan.B" ]; then
        pass "race winner identity consistent (B won, B had rc=0)"
      else
        fail "winner identity mismatch" "winner=$WINNER rc_a=$rc_a rc_b=$rc_b"
      fi
      ;;
    *)
      fail "race winner pipeline_id" "unexpected value '$WINNER'"
      ;;
  esac
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
