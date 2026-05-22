#!/bin/bash
# tests/test-plan-claim-release-already-complete.sh — Phase 2a W2a.13 / AC2a.4 site 2.
#
# Verifies Phase 5b §0a (`### 0a. Idempotent early-exit`) release semantics:
#   (1) SKILL.md conformance: §0a section contains a single
#       `claim-plan.sh release` call BEFORE the no-op exit message; uses
#       `--require-pipeline "$PIPELINE_ID"`; suppresses errors via
#       `2>/dev/null || true` (exit 12 tolerated — another pipeline owns).
#   (2) Happy path: acquire as pipeline A, run §0a release as A, claim is
#       removed.
#   (3) Mismatch path: acquire as pipeline A, run §0a release as pipeline B,
#       Failure Protocol is NOT triggered (rc tolerated via `|| true`),
#       claim remains owned by pipeline A.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_MD="$REPO_ROOT/skills/run-plan/SKILL.md"
CLAIM_SH="$REPO_ROOT/skills/run-plan/scripts/claim-plan.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SCRATCH_ROOT="/tmp/test-plan-claim-already-complete-$$"
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

echo "=== plan-claim release at §0a Idempotent early-exit (site 2) ==="

# ─────────────────────────────────────────────────────────────────────
# Part 1: SKILL.md conformance
# ─────────────────────────────────────────────────────────────────────
section_0a=$(awk '
  /^### 0a\. Idempotent early-exit$/ { p = 1; next }
  p && /^(### |## )/ { p = 0 }
  p { print }
' "$SKILL_MD")

release_count=$(printf '%s\n' "$section_0a" | grep -cE '^[[:space:]]*release "\$PLAN_SLUG"' || true)
if [ "$release_count" = "1" ]; then
  pass "§0a contains exactly one claim-plan.sh release call"
else
  fail "§0a release count" "expected 1, got $release_count"
fi

# Uses --require-pipeline "$PIPELINE_ID"
if printf '%s\n' "$section_0a" | grep -q -- '--require-pipeline "\$PIPELINE_ID"'; then
  pass "§0a release uses --require-pipeline \"\$PIPELINE_ID\""
else
  fail "§0a release pipeline guard" "expected --require-pipeline \"\$PIPELINE_ID\""
fi

# Suppress errors via `2>/dev/null || true`
if printf '%s\n' "$section_0a" | grep -q '2>/dev/null \|\| true\|2>/dev/null || true'; then
  pass "§0a release suppresses errors (exit 12 tolerated)"
else
  fail "§0a release error suppression" "no '2>/dev/null || true' tail; exit 12 would falsely Failure-Protocol"
fi

# ─────────────────────────────────────────────────────────────────────
# Part 2: happy path — acquire then release as same pipeline
# ─────────────────────────────────────────────────────────────────────
FIXTURE="$SCRATCH_ROOT/fixture"
mkdir -p "$FIXTURE"
( cd "$FIXTURE" && git init -q && git config user.email "t@t" && git config user.name "t" \
  && git commit --allow-empty -q -m "init" ) \
  || { echo "FATAL: fixture init failed" >&2; exit 1; }

PLAN_SLUG="already-complete"
PIPELINE_A="run-plan.A"
PIPELINE_B="run-plan.B"

( cd "$FIXTURE" && bash "$CLAIM_SH" acquire "$PLAN_SLUG" --pipeline-id "$PIPELINE_A" >/dev/null 2>&1 ) \
  || { fail "happy-path setup" "could not acquire as A"; exit 1; }

# Run the §0a release verbatim (with `|| true` tail).
( cd "$FIXTURE" && \
  bash "$CLAIM_SH" release "$PLAN_SLUG" --require-pipeline "$PIPELINE_A" 2>/dev/null || true )

if [ ! -d "$FIXTURE/.zskills/claims/plan-$PLAN_SLUG" ]; then
  pass "happy path: §0a release removes claim when pipeline matches"
else
  fail "happy path: §0a release" "claim dir remained after matched §0a release"
fi

# ─────────────────────────────────────────────────────────────────────
# Part 3: mismatch path — exit 12 tolerated, claim remains
# ─────────────────────────────────────────────────────────────────────
( cd "$FIXTURE" && bash "$CLAIM_SH" acquire "$PLAN_SLUG" --pipeline-id "$PIPELINE_A" >/dev/null 2>&1 ) \
  || { fail "mismatch setup" "could not re-acquire as A"; exit 1; }

# Run the §0a release as pipeline B; with `|| true`, the harness should NOT
# crash (verified by checking the test continues past it).
set +e
( cd "$FIXTURE" && \
  bash "$CLAIM_SH" release "$PLAN_SLUG" --require-pipeline "$PIPELINE_B" 2>/dev/null || true )
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
  pass "mismatch path: §0a release with wrong pipeline tolerated (overall rc=0 via || true)"
else
  fail "mismatch path: exit code" "expected 0 (tolerated), got $rc"
fi

# Claim dir must still be present and still owned by A.
claim_file="$FIXTURE/.zskills/claims/plan-$PLAN_SLUG/claim.json"
if [ -f "$claim_file" ]; then
  actual_pid=$(python3 -c "import json, sys; print(json.load(open(sys.argv[1])).get('pipeline_id',''))" "$claim_file")
  if [ "$actual_pid" = "$PIPELINE_A" ]; then
    pass "mismatch path: claim still owned by pipeline A"
  else
    fail "mismatch path: claim ownership" "expected $PIPELINE_A, got $actual_pid"
  fi
else
  fail "mismatch path: claim preservation" "claim was removed despite pipeline mismatch"
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
