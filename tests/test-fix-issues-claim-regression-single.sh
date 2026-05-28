#!/bin/bash
# tests/test-fix-issues-claim-regression-single.sh — Phase 4 W4.3.
#
# Mechanism-layer assertions that gate AC A7 — "single-pipeline
# dashboard mode behaviour is byte-for-byte identical to today when only
# one /fix-issues is running". The end-to-end /fix-issues 3 dashboard
# auto regression remains a manual PR-body repro step (the slash command
# is not runnable from a bash test).
#
# Cases:
#   1. Sequential acquire 1, 2, 3 — all exit 0; three claim dirs exist.
#   2. block-fix-issue-unclaimed.sh hook against a `fix-issue-1` payload
#      with claim present — exit 0 (no spurious deny in single-pipeline
#      path).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAIM_SH="$REPO_ROOT/skills/fix-issues/scripts/claim-issue.sh"
HOOK="$REPO_ROOT/hooks/block-fix-issue-unclaimed.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SCRATCH_ROOT="/tmp/test-claim-regression-single-$$"
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
  echo "FATAL: $CLAIM_SH missing" >&2; exit 1
fi
if [ ! -f "$HOOK" ]; then
  echo "FATAL: $HOOK missing" >&2; exit 1
fi

echo "=== Single-pipeline regression (A7 mechanism layer) ==="

FIXTURE="$SCRATCH_ROOT/fixture"
mkdir -p "$FIXTURE"
( cd "$FIXTURE" && git init -q && git config user.email "t@t" && git config user.name "t" \
  && git commit --allow-empty -q -m "init" ) \
  || { echo "FATAL: fixture init failed" >&2; exit 1; }

# ───────────────────────────────────────────────────────────────────────
# Test 1: sequential acquires 1, 2, 3 all succeed; three dirs exist.
# ───────────────────────────────────────────────────────────────────────
(
  cd "$FIXTURE" || exit 1
  for n in 1 2 3; do
    out=$(bash "$CLAIM_SH" acquire "$n" --pipeline-id "pipe-single" --sprint-id "sprint-single" 2>&1)
    rc=$?
    if [ "$rc" -ne 0 ]; then
      echo "FAIL_REASON acquire $n returned $rc, expected 0; out: $out"
      exit 1
    fi
    if [ ! -d "$FIXTURE/.zskills/claims/issue-$n" ]; then
      echo "FAIL_REASON claim dir issue-$n not created"
      exit 1
    fi
  done
  exit 0
)
if [ "$?" -eq 0 ]; then
  pass "sequential acquire 1, 2, 3 — all exit 0; three claim dirs created"
else
  fail "sequential acquires" "see FAIL_REASON above"
fi

# ───────────────────────────────────────────────────────────────────────
# Test 2: hook against fix-issue-1 payload with claim present — exit 0
# (no spurious deny in single-pipeline path).
# ───────────────────────────────────────────────────────────────────────
(
  cd "$FIXTURE" || exit 1
  # Claim issue-1 already exists from Test 1.
  payload=$(python3 -c "
import json
print(json.dumps({
    'tool_name': 'Bash',
    'tool_input': {
        'command': 'bash $REPO_ROOT/skills/create-worktree/scripts/create-worktree.sh --prefix fix-issue --purpose \"fix-issues; issue=1\" --pipeline-id pipe-single 1'
    }
}))
")
  stdout=$(echo "$payload" | bash "$HOOK" 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "FAIL_REASON hook returned $rc, expected 0 (allow); out: $stdout"
    exit 1
  fi
  if echo "$stdout" | grep -q '"permissionDecision":"deny"'; then
    echo "FAIL_REASON hook emitted deny envelope despite claim present: $stdout"
    exit 1
  fi
  exit 0
)
if [ "$?" -eq 0 ]; then
  pass "hook allows fix-issue-1 create-worktree call when claim is present (no spurious deny in single-pipeline path)"
else
  fail "hook allow on present claim (single-pipeline)" "see FAIL_REASON above"
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
