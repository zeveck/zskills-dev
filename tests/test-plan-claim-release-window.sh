#!/bin/bash
# tests/test-plan-claim-release-window.sh — Phase 2a W2a.12 / AC2a.5.
#
# Explicit regression: assert NO `claim-plan.sh release` call appears
# in Phase 5b §1-5 (the frontmatter-flip + CI-poll wait window). Releasing
# the claim during Phase 5b §1-5 would leave the plan unclaimed for the
# 10+ minute /land-pr CI-poll window, allowing a second /work-on-plans
# dispatch to re-pick the plan and double-fire /land-pr.
#
# The §1-5 window is bounded by `### 1. Audit phase compliance` and the
# next major header (`### Post-report tracking` OR `## Phase 5c`).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_MD="$REPO_ROOT/skills/run-plan/modes/execute-phase.md"
CLAIM_SH="$REPO_ROOT/skills/run-plan/scripts/claim-plan.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SCRATCH_ROOT="/tmp/test-plan-claim-window-$$"
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

echo "=== plan-claim release window: NO release in Phase 5b §1-5 ==="

# Extract the section bounded by `### 1. Audit phase compliance` and the
# next header at same-or-shallower depth (next `### ` or `## `).
section_content=$(awk '
  /^### 1\. Audit phase compliance$/ { p = 1; next }
  p && /^(### |## )/ { p = 0 }
  p { print }
' "$SKILL_MD")

if [ -z "$section_content" ]; then
  fail "section extraction" "could not locate `### 1. Audit phase compliance` section"
else
  release_count=$(printf '%s\n' "$section_content" | grep -cE '^[[:space:]]*release "\$PLAN_SLUG"' || true)
  if [ "$release_count" = "0" ]; then
    pass "Phase 5b §1 (audit) section contains NO claim-plan.sh release calls"
  else
    fail "Phase 5b §1 release present" "found $release_count claim-plan.sh release calls in §1-5 window"
  fi
fi

# Walk all §1-5 sub-sections individually (DA2.4 — be specific).
for hdr in \
  "### 1. Audit phase compliance" \
  "### 2. Close linked issue (if any)" \
  "### 3. Update plan frontmatter" \
  "### 4. Update sprint report" \
  "### 5. Remind about stale tracking markers"; do
  sub_content=$(awk -v h="$hdr" '
    $0 == h { p = 1; next }
    p && /^(### |## )/ { p = 0 }
    p { print }
  ' "$SKILL_MD")
  release_count=$(printf '%s\n' "$sub_content" | grep -cE '^[[:space:]]*release "\$PLAN_SLUG"' || true)
  if [ "$release_count" = "0" ]; then
    pass "'$hdr' contains NO claim-plan.sh release"
  else
    fail "'$hdr' release count" "expected 0, got $release_count"
  fi
done

# Also assert the §0a release IS present (positive control — proves the
# negative assertion above isn't because the regex is broken).
section_0a=$(awk '
  /^### 0a\. Idempotent early-exit$/ { p = 1; next }
  p && /^(### |## )/ { p = 0 }
  p { print }
' "$SKILL_MD")
release_count_0a=$(printf '%s\n' "$section_0a" | grep -cE '^[[:space:]]*release "\$PLAN_SLUG"' || true)
if [ "$release_count_0a" = "1" ]; then
  pass "positive control: §0a Idempotent early-exit contains 1 release call"
else
  fail "positive control: §0a release" "expected 1, got $release_count_0a"
fi

# End-to-end: assert that if a /run-plan-style fence executes Phase 5b §1-5
# work without releasing, the claim remains on disk throughout. (This is a
# minimal simulation — we acquire + perform any benign git op + assert
# claim still present.)
FIXTURE="$SCRATCH_ROOT/fixture"
mkdir -p "$FIXTURE"
( cd "$FIXTURE" && git init -q && git config user.email "t@t" && git config user.name "t" \
  && git commit --allow-empty -q -m "init" ) \
  || { echo "FATAL: fixture init failed" >&2; exit 1; }

PLAN_SLUG="window-test"
PIPELINE="run-plan.$PLAN_SLUG"
( cd "$FIXTURE" && bash "$CLAIM_SH" acquire "$PLAN_SLUG" --pipeline-id "$PIPELINE" >/dev/null 2>&1 ) \
  || { fail "fixture acquire" "could not acquire claim"; exit 1; }

# Simulate Phase 5b §1-5 work: write some files, commit, sleep briefly
# (mimic CI poll latency). Throughout, no release call should fire.
( cd "$FIXTURE" && echo "frontmatter flipped" > plan.md && git add plan.md \
  && git commit -q -m "chore: mark plan complete" )
sleep 1

if [ -d "$FIXTURE/.zskills/claims/plan-$PLAN_SLUG" ] \
   && [ -f "$FIXTURE/.zskills/claims/plan-$PLAN_SLUG/claim.json" ]; then
  pass "claim remains on disk through simulated Phase 5b §1-5 window"
else
  fail "claim window persistence" "claim was removed during §1-5 simulation"
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
