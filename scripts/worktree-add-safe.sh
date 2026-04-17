#!/bin/bash
# scripts/worktree-add-safe.sh BRANCH_NAME WORKTREE_PATH [BASE_BRANCH=main]
# Creates a git worktree safely — either fresh, or a verified-legitimate
# resume. Fails loud on poisoned or ambiguous branch state.
set -eu
BRANCH_NAME="${1:?missing branch name}"
WORKTREE_PATH="${2:?missing worktree path}"
BASE="${3:-main}"

# Case 1: worktree dir already exists. Caller should have handled this
# upstream; if we get here, it's a bug.
if [ -d "$WORKTREE_PATH" ]; then
  echo "ERROR: worktree path $WORKTREE_PATH already exists — caller must" \
       "handle resume before invoking this helper." >&2
  exit 2
fi

# Case 2: branch does not exist anywhere — fresh create from BASE.
if ! git rev-parse --verify --quiet "$BRANCH_NAME" >/dev/null; then
  if ! git rev-parse --verify --quiet "origin/$BRANCH_NAME" >/dev/null; then
    # Fresh branch — create and attach.
    git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" "$BASE"
    exit 0
  fi
fi

# Case 3: branch exists locally or on remote. Classify.
#
# Prefer LOCAL branch info if available; else inspect origin.
REF="$BRANCH_NAME"
if ! git rev-parse --verify --quiet "$REF" >/dev/null; then
  REF="origin/$BRANCH_NAME"
fi

# Count commits ahead of BASE on the candidate branch.
AHEAD=$(git rev-list --count "$BASE..$REF" 2>/dev/null || echo "0")
BEHIND=$(git rev-list --count "$REF..$BASE" 2>/dev/null || echo "0")

# Classify:
if [ "$AHEAD" = "0" ] && [ "$BEHIND" = "0" ]; then
  # Branch is equivalent to BASE (likely merged-and-not-deleted).
  # Delete it and create fresh.
  echo "NOTE: branch $BRANCH_NAME is equivalent to $BASE — deleting stale ref and creating fresh." >&2
  git branch -D "$BRANCH_NAME" 2>/dev/null || true
  git push origin --delete "$BRANCH_NAME" 2>/dev/null || true
  git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" "$BASE"
  exit 0
fi

if [ "$BEHIND" -gt 0 ] && [ "$AHEAD" = "0" ]; then
  # Branch is strictly behind BASE — this means BASE advanced and
  # branch wasn't rebased. This is a poisoning indicator.
  echo "ERROR: branch $BRANCH_NAME is $BEHIND commits BEHIND $BASE with zero commits ahead — poisoned stale branch." >&2
  echo "       Manual reconciliation required: either rebase the branch, delete it, or use a different plan slug." >&2
  exit 3
fi

# Branch is ahead of BASE — potentially legitimate resume.
# Require caller to opt in via env var ZSKILLS_ALLOW_BRANCH_RESUME=1.
if [ "${ZSKILLS_ALLOW_BRANCH_RESUME:-}" != "1" ]; then
  echo "ERROR: branch $BRANCH_NAME exists with $AHEAD commits ahead of $BASE." >&2
  echo "       This may be a legitimate multi-phase resume OR a poisoned stale branch." >&2
  echo "       To proceed: set ZSKILLS_ALLOW_BRANCH_RESUME=1 (caller must verify branch fitness first)." >&2
  echo "       To abort and reset: git branch -D $BRANCH_NAME && git push origin --delete $BRANCH_NAME" >&2
  exit 4
fi

# Caller opted in — attach worktree to existing branch.
echo "NOTE: resuming on existing branch $BRANCH_NAME ($AHEAD commits ahead of $BASE)." >&2
git worktree add "$WORKTREE_PATH" "$BRANCH_NAME"
exit 0
