#!/bin/bash
# Tests for scripts/create-worktree.sh — Phase 1a smoke.
# Run from repo root: bash tests/test-create-worktree.sh
#
# Exactly two cases per plans/CREATE_WORKTREE_SKILL.md WI 1a.16:
#   1. Fresh creation rc=0, stdout=path, .zskills-tracked present
#   2. Path-exists rc=2 on second invocation with same slug; empty stdout
#
# Not yet registered in tests/run-all.sh — Phase 1b WI 1b.2 does that.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# MAIN_ROOT resolves via git-common-dir — may differ from REPO_ROOT when
# this test runs from within a nested worktree. The script anchors all
# paths on MAIN_ROOT, so the test must too (else default paths mismatch).
MAIN_ROOT="$(cd "$(git -C "$REPO_ROOT" rev-parse --git-common-dir)/.." && pwd)"
PROJECT_NAME="$(basename "$MAIN_ROOT")"
SCRIPT="$MAIN_ROOT/scripts/create-worktree.sh"
if [ ! -x "$SCRIPT" ]; then
  # Fallback: when the script has been modified locally in this worktree
  # but not yet landed, exercise the worktree copy so the smoke test
  # covers the code under review.
  SCRIPT="$REPO_ROOT/scripts/create-worktree.sh"
fi

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  printf '\033[32m  PASS\033[0m %s\n' "$1"
  PASS_COUNT=$((PASS_COUNT + 1))
}
fail() {
  printf '\033[31m  FAIL\033[0m %s\n' "$1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

# Per-run isolation: each test uses a unique slug tied to $$ so parallel
# pipelines / repeated runs don't collide. The script places worktrees
# under /tmp/<project>-<slug> by default; we clean both that path and
# the git branch after each case.
SLUG_BASE="cw-smoke-$$"
SLUG_1="${SLUG_BASE}-fresh"
SLUG_2="${SLUG_BASE}-exists"

WT1="/tmp/${PROJECT_NAME}-${SLUG_1}"
WT2="/tmp/${PROJECT_NAME}-${SLUG_2}"
BRANCH1="wt-${SLUG_1}"
BRANCH2="wt-${SLUG_2}"

cleanup() {
  # Best-effort cleanup — may be called on failure paths.
  git -C "$MAIN_ROOT" worktree remove --force "$WT1" 2>/dev/null || true
  git -C "$MAIN_ROOT" worktree remove --force "$WT2" 2>/dev/null || true
  rm -rf "$WT1" "$WT2" 2>/dev/null || true
  git -C "$MAIN_ROOT" branch -D "$BRANCH1" 2>/dev/null || true
  git -C "$MAIN_ROOT" branch -D "$BRANCH2" 2>/dev/null || true
  git -C "$MAIN_ROOT" worktree prune 2>/dev/null || true
}
trap cleanup EXIT

# Pre-clean in case a prior aborted run left residue with the same $$.
cleanup

echo "=== Phase 1a smoke — scripts/create-worktree.sh ==="

# ────────────────────────────────────────────────────────────────────
# Case 1: fresh creation rc=0, stdout=path, .zskills-tracked present.
# ────────────────────────────────────────────────────────────────────
ERR1=$(mktemp)
OUT1=$(ZSKILLS_PIPELINE_ID="test.create-worktree.$$" \
  bash "$SCRIPT" --no-preflight "$SLUG_1" 2>"$ERR1")
RC1=$?

if [ "$RC1" -eq 0 ] && [ "$OUT1" = "$WT1" ] && [ -d "$WT1" ] && [ -f "$WT1/.zskills-tracked" ]; then
  # Verify .zskills-tracked contents are sanitized and match the pipeline ID
  TRACKED=$(cat "$WT1/.zskills-tracked" 2>/dev/null || echo "")
  if [ "$TRACKED" = "test.create-worktree.$$" ]; then
    pass "fresh creation: rc=0, stdout=path, worktree + .zskills-tracked present, pipeline ID matches"
  else
    fail "fresh creation: .zskills-tracked content='$TRACKED' did not match 'test.create-worktree.$$'"
    echo "  --- stderr ---"
    cat "$ERR1"
  fi
else
  fail "fresh creation: rc=$RC1, stdout='$OUT1', expected path '$WT1'"
  echo "  --- stderr ---"
  cat "$ERR1"
fi
rm -f "$ERR1"

# ────────────────────────────────────────────────────────────────────
# Case 2: path-exists rc=2, empty stdout.
# To avoid depending on case 1's outcome, we pre-create $WT2 as a
# bare directory — the script must refuse with rc=2. This isolates
# "path already exists" from "branch already attached", matching how
# worktree-add-safe.sh:12-16 classifies it.
# ────────────────────────────────────────────────────────────────────
mkdir -p "$WT2"
ERR2=$(mktemp)
OUT2=$(ZSKILLS_PIPELINE_ID="test.create-worktree.$$" \
  bash "$SCRIPT" --no-preflight "$SLUG_2" 2>"$ERR2")
RC2=$?

if [ "$RC2" -eq 2 ] && [ -z "$OUT2" ]; then
  pass "path-exists: rc=2, empty stdout"
else
  fail "path-exists: rc=$RC2, stdout='$OUT2' (expected rc=2 and empty stdout)"
  echo "  --- stderr ---"
  cat "$ERR2"
fi
rm -f "$ERR2"

echo ""
echo "---"
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo -e "\033[32mResults: $PASS_COUNT passed, 0 failed (of $TOTAL)\033[0m"
  exit 0
else
  echo -e "\033[31mResults: $PASS_COUNT passed, $FAIL_COUNT failed (of $TOTAL)\033[0m"
  exit 1
fi
