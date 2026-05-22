#!/bin/bash
# tests/test-plan-claim-heartbeat.sh — Phase 2a W2a.8 / AC2a.2.
#
# Two-part test:
#   (1) Conformance: assert SKILL.md prose contains a `claim-plan.sh refresh`
#       call within each of the 6 section-header-anchored windows (DA2.6 —
#       line-number-resistant, NOT line-number-anchored).
#   (2) End-to-end: directly exercise `claim-plan.sh refresh` to confirm
#       `last_heartbeat_at` actually advances when the refresh fence runs.
#       Walks through the section headers, calling refresh once per section
#       with the section header as --current-phase, and asserts the
#       on-disk last_heartbeat_at is strictly later after each refresh.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_MD="$REPO_ROOT/skills/run-plan/SKILL.md"
CLAIM_SH="$REPO_ROOT/skills/run-plan/scripts/claim-plan.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SCRATCH_ROOT="/tmp/test-plan-claim-heartbeat-$$"
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

echo "=== plan-claim heartbeat (SKILL.md conformance + e2e refresh) ==="

# ─────────────────────────────────────────────────────────────────────
# Part 1: section-header-anchored conformance
# ─────────────────────────────────────────────────────────────────────

# Sections that must each contain exactly one `claim-plan.sh refresh`
# call within the window from their header to the next `^### ` or
# `^## ` line (whichever comes first).
SECTIONS=(
  "### Parse plan"
  "### Post-implementation tracking"
  "### Post-verification tracking"
  "### 5. Marker ordering and failure handling"
  "### Post-report tracking"
  "### 0b. Final-verify gate"
)

for section in "${SECTIONS[@]}"; do
  # awk: print lines inside the named section (between its header and the
  # next ^### or ^## line). Then count refresh calls.
  count=$(awk -v hdr="$section" '
    $0 == hdr { p = 1; next }
    p && /^(### |## )/ { p = 0 }
    p { print }
  ' "$SKILL_MD" | grep -cE '^[[:space:]]*refresh "\$PLAN_SLUG"' || true)
  if [ "$count" = "1" ]; then
    pass "section-scoped refresh: '$section' contains exactly one claim-plan.sh refresh call"
  else
    fail "section-scoped refresh: '$section'" "expected 1 refresh call, found $count"
  fi
done

# ─────────────────────────────────────────────────────────────────────
# Part 2: end-to-end refresh advances last_heartbeat_at
# ─────────────────────────────────────────────────────────────────────

FIXTURE="$SCRATCH_ROOT/fixture"
mkdir -p "$FIXTURE"
( cd "$FIXTURE" && git init -q && git config user.email "t@t" && git config user.name "t" \
  && git commit --allow-empty -q -m "init" ) \
  || { echo "FATAL: fixture init failed" >&2; exit 1; }

PLAN_SLUG="heartbeat-test"
PIPELINE_ID="run-plan.$PLAN_SLUG"
( cd "$FIXTURE" && bash "$CLAIM_SH" acquire "$PLAN_SLUG" --pipeline-id "$PIPELINE_ID" >/dev/null 2>&1 ) \
  || { fail "fixture acquire" "could not acquire claim"; exit 1; }

claim_file="$FIXTURE/.zskills/claims/plan-$PLAN_SLUG/claim.json"
read_heartbeat() {
  python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    print(json.load(f).get('last_heartbeat_at',''))
" "$claim_file"
}
read_phase() {
  python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    print(json.load(f).get('current_phase',''))
" "$claim_file"
}

prev_hb=$(read_heartbeat)
prev_idx=0
for section in "${SECTIONS[@]}"; do
  # claim.json mtime granularity is seconds; sleep 1 to ensure
  # last_heartbeat_at actually changes.
  sleep 1
  ( cd "$FIXTURE" && bash "$CLAIM_SH" refresh "$PLAN_SLUG" \
       --require-pipeline "$PIPELINE_ID" \
       --current-phase "${section#### }" >/dev/null 2>&1 ) \
    || { fail "refresh for $section" "claim-plan.sh refresh exit non-zero"; continue; }
  new_hb=$(read_heartbeat)
  new_phase=$(read_phase)
  if [ "$new_hb" = "$prev_hb" ]; then
    fail "heartbeat advances at '$section'" "last_heartbeat_at unchanged: $new_hb"
  else
    pass "heartbeat advances at '$section' (prev=$prev_hb new=$new_hb)"
  fi
  expected_phase="${section#### }"
  if [ "$new_phase" = "$expected_phase" ]; then
    pass "current_phase recorded verbatim at '$section'"
  else
    fail "current_phase at '$section'" "expected='$expected_phase' got='$new_phase'"
  fi
  prev_hb="$new_hb"
  prev_idx=$((prev_idx + 1))
done

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (%d total)\033[0m\n' "$PASS_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (%d total)\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit 1
fi
