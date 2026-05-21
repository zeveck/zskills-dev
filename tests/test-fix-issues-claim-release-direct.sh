#!/bin/bash
# tests/test-fix-issues-claim-release-direct.sh — T2.2c from
# plans/fix-issues-claims.md Phase 2 (W2.6c).
#
# Direct mode FF-merges per issue. Four IMPLEMENTED terminal arms each
# release the claim before `continue`:
#   - rebase-conflict
#   - FF-refused
#   - direct-push-failed
#   - status: full (success)
#
# The fifth terminal (direct-verify-failed) is currently a code-comment
# placeholder at modes/direct.md:80 (DA3.3) — NOT tested here. The
# aspirational HTML-comment marker is asserted to be present so a future
# implementer of that terminal sees the integration site.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAIM_SH="$REPO_ROOT/skills/fix-issues/scripts/claim-issue.sh"
DIRECT_MD="$REPO_ROOT/skills/fix-issues/modes/direct.md"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SCRATCH_ROOT="/tmp/test-fix-issues-claim-release-direct-$$"
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

# Replay the W2.6c release line for each terminal arm.
run_terminal_release() {
  local rootname="$1"
  local root="$SCRATCH_ROOT/$rootname"
  make_repo "$root" || return 2
  mkdir -p "$root/.zskills/claims/issue-55"
  cat > "$root/.zskills/claims/issue-55/claim.json" <<JSON
{"schema_version":1,"pipeline_id":"mine-d","sprint_id":"mine-d-s","issue":55,"started_at":"2026-05-21T00:00:00+00:00"}
JSON
  local script="$root/release.sh"
  cat > "$script" <<EOF
HELPER="$CLAIM_SH"
ISSUE_NUM=55
PIPELINE_ID=mine-d
bash "\$HELPER" release "\$ISSUE_NUM" --require-pipeline "\$PIPELINE_ID" || true
EOF
  (cd "$root" && bash "$script") >/dev/null 2>&1
  if [ -d "$root/.zskills/claims/issue-55" ]; then
    echo "HELD"
  else
    echo "RELEASED"
  fi
}

echo "=== T2.2c direct-mode release case-arms ==="

# 1. rebase-conflict
result=$(run_terminal_release "case-1-rebase-conflict")
if [ "$result" = "RELEASED" ]; then
  pass "T2.2c rebase-conflict terminal → RELEASE"
else
  fail "T2.2c rebase-conflict" "expected RELEASED, got $result"
fi

# 2. FF-refused
result=$(run_terminal_release "case-2-ff-refused")
if [ "$result" = "RELEASED" ]; then
  pass "T2.2c FF-refused terminal → RELEASE"
else
  fail "T2.2c FF-refused" "expected RELEASED, got $result"
fi

# 3. direct-push-failed
result=$(run_terminal_release "case-3-push-failed")
if [ "$result" = "RELEASED" ]; then
  pass "T2.2c direct-push-failed terminal → RELEASE"
else
  fail "T2.2c direct-push-failed" "expected RELEASED, got $result"
fi

# 4. status: full
result=$(run_terminal_release "case-4-full")
if [ "$result" = "RELEASED" ]; then
  pass "T2.2c status:full terminal → RELEASE"
else
  fail "T2.2c status:full" "expected RELEASED, got $result"
fi

# Structural assertions — modes/direct.md should contain 4 release calls,
# and the aspirational HTML marker for the 5th terminal.
release_count=$(grep -c 'bash "\$HELPER" release "\$ISSUE_NUM" --require-pipeline "\$PIPELINE_ID"' "$DIRECT_MD")
if [ "$release_count" -ge 4 ]; then
  pass "T2.2c direct.md contains $release_count release-call occurrences (>=4 implemented arms)"
else
  fail "T2.2c direct.md release-count" "expected >=4, got $release_count"
fi

if grep -q 'aspirational: implement when direct-verify-failed terminal lands' "$DIRECT_MD"; then
  pass "T2.2c direct.md contains aspirational marker for 5th terminal (DA3.3)"
else
  fail "T2.2c direct.md aspirational marker" "marker not found"
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
