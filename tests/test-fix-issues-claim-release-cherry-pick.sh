#!/bin/bash
# tests/test-fix-issues-claim-release-cherry-pick.sh — T2.2b from
# plans/fix-issues-claims.md Phase 2 (W2.6b).
#
# Cherry-pick mode iterates worktrees in prose; per-worktree terminal
# actions release the claim in both arms:
#   - status: full   (successful cherry-pick)   → RELEASE
#   - status: partial (cherry-pick conflict)    → RELEASE
#
# Both arms are tested by replaying the W2.6b shell fragment
# (`bash "$HELPER" release "$ISSUE_NUM" --require-pipeline "$PIPELINE_ID" || true`)
# against a pre-acquired claim.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAIM_SH="$REPO_ROOT/skills/fix-issues/scripts/claim-issue.sh"
CHERRY_PICK_MD="$REPO_ROOT/skills/fix-issues/modes/cherry-pick.md"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SCRATCH_ROOT="/tmp/test-fix-issues-claim-release-cherry-pick-$$"
cleanup() {
  if [ -d "$SCRATCH_ROOT" ]; then
    find "$SCRATCH_ROOT" -mindepth 1 -delete 2>/dev/null || true
    rmdir "$SCRATCH_ROOT" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM
mkdir -p "$SCRATCH_ROOT"

make_repo() {
  local repo="$1"
  mkdir -p "$repo"
  (cd "$repo" && git init -q && git config user.email "t@t" && git config user.name "t" \
    && git commit --allow-empty -q -m "init") || return 1
}

# Each terminal action (status:full and status:partial) ends with the
# release call. Replay that line.
run_terminal_release() {
  local rootname="$1"
  local root="$SCRATCH_ROOT/$rootname"
  make_repo "$root" || return 2
  mkdir -p "$root/.zskills/claims/issue-77"
  cat > "$root/.zskills/claims/issue-77/claim.json" <<JSON
{"schema_version":1,"pipeline_id":"mine-cp","sprint_id":"mine-cp-s","issue":77,"started_at":"2026-05-21T00:00:00+00:00"}
JSON
  local script="$root/release.sh"
  cat > "$script" <<EOF
HELPER="$CLAIM_SH"
ISSUE_NUM=77
PIPELINE_ID=mine-cp
bash "\$HELPER" release "\$ISSUE_NUM" --require-pipeline "\$PIPELINE_ID" || true
EOF
  (cd "$root" && bash "$script") >/dev/null 2>&1
  if [ -d "$root/.zskills/claims/issue-77" ]; then
    echo "HELD"
  else
    echo "RELEASED"
  fi
}

echo "=== T2.2b cherry-pick release case-arms ==="

# Arm 5b — status: full (success)
result=$(run_terminal_release "case-5b-full")
if [ "$result" = "RELEASED" ]; then
  pass "T2.2b step-5b (status: full) → RELEASE"
else
  fail "T2.2b step-5b" "expected RELEASED, got $result"
fi

# Arm 5c — status: partial (cherry-pick conflict)
result=$(run_terminal_release "case-5c-partial")
if [ "$result" = "RELEASED" ]; then
  pass "T2.2b step-5c (status: partial) → RELEASE"
else
  fail "T2.2b step-5c" "expected RELEASED, got $result"
fi

# Structural assertion — cherry-pick.md contains release calls in both
# step-5b (status: full) and step-5c (status: partial) fence blocks.
# Count: expect at least 2 release-call occurrences inside the file.
release_count=$(grep -c 'bash "\$HELPER" release "\$ISSUE_NUM" --require-pipeline "\$PIPELINE_ID"' "$CHERRY_PICK_MD")
if [ "$release_count" -ge 2 ]; then
  pass "T2.2b cherry-pick.md contains $release_count release-call occurrences (>=2)"
else
  fail "T2.2b cherry-pick.md release-count" "expected >=2, got $release_count"
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
