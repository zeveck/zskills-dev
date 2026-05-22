#!/bin/bash
# tests/test-plan-claim-release-phase6.sh — Phase 2a W2a.10 / AC2a.4 site 3.
#
# Asserts:
#   (1) skills/run-plan/SKILL.md contains a `claim-plan.sh release` call
#       within the `### Post-landing tracking` section window.
#   (2) The release call appears AFTER the
#       `fulfilled.run-plan.$TRACKING_ID` marker write line (the canonical
#       run-plan-internal terminal-merge anchor per DA3.3 / W2a.4 site 3).
#   (3) The release call uses `--require-pipeline "$PIPELINE_ID"` (single-
#       slug release for the current plan, not a walk).
#   (4) Exit 12 path invokes Failure Protocol (regex assertion: the section
#       contains either an explicit Failure Protocol invocation or an
#       `exit 1` arm gated on rc == 12).
#   (5) End-to-end with claim-plan.sh: after `fulfilled.run-plan.<id>` is
#       written, calling release with the matching pipeline removes the
#       claim dir; calling release with a mismatched pipeline returns
#       exit 12 and leaves the claim intact.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_MD="$REPO_ROOT/skills/run-plan/SKILL.md"
CLAIM_SH="$REPO_ROOT/skills/run-plan/scripts/claim-plan.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SCRATCH_ROOT="/tmp/test-plan-claim-release-phase6-$$"
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

echo "=== plan-claim release at Post-landing tracking (site 3) ==="

# ─────────────────────────────────────────────────────────────────────
# Part 1: SKILL.md conformance (section-scoped anchors)
# ─────────────────────────────────────────────────────────────────────

# Extract the Post-landing tracking section content.
section_content=$(awk '
  /^### Post-landing tracking$/ { p = 1; next }
  p && /^(### |## )/ { p = 0 }
  p { print }
' "$SKILL_MD")

# (1) release call within section
release_count=$(printf '%s\n' "$section_content" | grep -cE '^[[:space:]]*release "\$PLAN_SLUG"' || true)
if [ "$release_count" = "1" ]; then
  pass "Post-landing tracking contains exactly one claim-plan.sh release call"
else
  fail "Post-landing release count" "expected 1, got $release_count"
fi

# (3) --require-pipeline "$PIPELINE_ID"
if printf '%s\n' "$section_content" | grep -q -- '--require-pipeline "\$PIPELINE_ID"'; then
  pass "release uses --require-pipeline \"\$PIPELINE_ID\" (single-slug, not walk)"
else
  fail "release pipeline guard" "expected --require-pipeline \"\$PIPELINE_ID\""
fi

# (2) release after fulfilled.run-plan marker write
fulfilled_line=$(grep -n 'fulfilled\.run-plan\.\$TRACKING_ID' "$SKILL_MD" | awk -F: '$0 ~ /\.zskills\/tracking/' | head -1 | cut -d: -f1)
release_line=$(grep -nE '^[[:space:]]*release "\$PLAN_SLUG"' "$SKILL_MD" | awk -F: '{print $1}' | while IFS= read -r ln; do
  hdr=$(awk -v n="$ln" 'NR<=n && /^(### |## )/ { last=$0 } END { print last }' "$SKILL_MD")
  if [ "$hdr" = "### Post-landing tracking" ]; then echo "$ln"; fi
done | head -1)
if [ -n "$fulfilled_line" ] && [ -n "$release_line" ] && [ "$release_line" -gt "$fulfilled_line" ]; then
  pass "release call (line $release_line) appears AFTER fulfilled.run-plan write (line $fulfilled_line)"
else
  fail "release vs fulfilled ordering" "fulfilled_line=$fulfilled_line release_line=$release_line"
fi

# (4) exit 12 → Failure Protocol path
if printf '%s\n' "$section_content" | grep -q 'rc.*12\|"\$rc" -eq 12'; then
  pass "release exit 12 has explicit error-handling arm"
else
  fail "release exit 12 arm" "no rc==12 handler in Post-landing section"
fi
# Must also exit 1 (Failure Protocol) on mismatch
if printf '%s\n' "$section_content" | grep -A 3 'rc.*12\|"\$rc" -eq 12' | grep -q 'exit 1'; then
  pass "release exit 12 invokes Failure Protocol (exit 1)"
else
  fail "release exit 12 -> Failure Protocol" "no exit 1 after rc==12 arm"
fi

# ─────────────────────────────────────────────────────────────────────
# Part 2: end-to-end claim-plan.sh release semantics
# ─────────────────────────────────────────────────────────────────────

FIXTURE="$SCRATCH_ROOT/fixture"
mkdir -p "$FIXTURE"
( cd "$FIXTURE" && git init -q && git config user.email "t@t" && git config user.name "t" \
  && git commit --allow-empty -q -m "init" ) \
  || { echo "FATAL: fixture init failed" >&2; exit 1; }

PLAN_SLUG="phase6-release"
PIPELINE="run-plan.$PLAN_SLUG"

# Acquire then write a fake fulfilled marker (simulates running through to
# Post-landing).
( cd "$FIXTURE" && bash "$CLAIM_SH" acquire "$PLAN_SLUG" --pipeline-id "$PIPELINE" >/dev/null 2>&1 ) || {
  fail "fixture acquire" "couldn't acquire claim"
  exit 1
}
mkdir -p "$FIXTURE/.zskills/tracking/$PIPELINE"
printf 'skill: run-plan\nid: %s\nstatus: complete\n' "$PLAN_SLUG" \
  > "$FIXTURE/.zskills/tracking/$PIPELINE/fulfilled.run-plan.$PLAN_SLUG"

# Matching pipeline → release succeeds.
( cd "$FIXTURE" && bash "$CLAIM_SH" release "$PLAN_SLUG" --require-pipeline "$PIPELINE" )
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "release with matching pipeline returns exit 0"
else
  fail "release with matching pipeline" "got rc=$rc"
fi
if [ ! -d "$FIXTURE/.zskills/claims/plan-$PLAN_SLUG" ]; then
  pass "claim dir removed after matched release"
else
  fail "claim dir post-release" "$FIXTURE/.zskills/claims/plan-$PLAN_SLUG still exists"
fi

# Now test pipeline-mismatch path. Re-acquire under PIPELINE; try release
# with WRONG pipeline; assert exit 12 and claim still intact.
( cd "$FIXTURE" && bash "$CLAIM_SH" acquire "$PLAN_SLUG" --pipeline-id "$PIPELINE" >/dev/null 2>&1 ) || {
  fail "fixture re-acquire" "couldn't re-acquire claim"
  exit 1
}
( cd "$FIXTURE" && bash "$CLAIM_SH" release "$PLAN_SLUG" --require-pipeline "run-plan.other" 2>/dev/null )
rc=$?
if [ "$rc" -eq 12 ]; then
  pass "release with mismatched pipeline returns exit 12"
else
  fail "release with mismatched pipeline" "expected 12, got $rc"
fi
if [ -d "$FIXTURE/.zskills/claims/plan-$PLAN_SLUG" ]; then
  pass "claim dir preserved on mismatched release"
else
  fail "claim dir on mismatched release" "claim dir was wrongly removed"
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
