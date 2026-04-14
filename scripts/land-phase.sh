#!/bin/bash
# scripts/land-phase.sh — Post-landing cleanup: verify .landed, extract logs, remove worktree
# Usage: bash scripts/land-phase.sh <worktree-path>
#
# Prerequisites: orchestrator already cherry-picked, ran tests, wrote .landed marker.
# This script handles the mechanical cleanup. Idempotent — safe to re-run.

WORKTREE_PATH="$1"

# Idempotency: if worktree is already gone, nothing to do
if [ ! -d "$WORKTREE_PATH" ]; then
  echo "Worktree already removed: $WORKTREE_PATH"
  exit 0
fi

MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)

# 1. Verify .landed marker (proof work is on main — refuse without it)
if [ ! -f "$WORKTREE_PATH/.landed" ]; then
  echo "ERROR: No .landed marker in $WORKTREE_PATH. Cannot clean up without proof of landing."
  exit 1
fi
if ! grep -qE 'status: (landed|pr-ready)' "$WORKTREE_PATH/.landed"; then
  echo "ERROR: .landed marker does not say 'status: landed' or 'status: pr-ready'. Current status:"
  cat "$WORKTREE_PATH/.landed"
  exit 1
fi

# 2. Extract logs not yet on main (MUST succeed before we destroy the worktree)
if [ -d "$WORKTREE_PATH/.claude/logs" ]; then
  if ! mkdir -p "$MAIN_ROOT/.claude/logs"; then
    echo "ERROR: Could not create $MAIN_ROOT/.claude/logs — aborting cleanup to preserve logs"
    exit 1
  fi
  for log in "$WORKTREE_PATH/.claude/logs/"*.md; do
    [ -f "$log" ] || continue
    if [ ! -f "$MAIN_ROOT/.claude/logs/$(basename "$log")" ]; then
      if ! cp "$log" "$MAIN_ROOT/.claude/logs/"; then
        echo "ERROR: Failed to copy $log — aborting cleanup to preserve logs"
        exit 1
      fi
    fi
  done
fi

# 3. Remove worktree (critical — fail loudly if this doesn't work)
BRANCH=$(git -C "$WORKTREE_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
# Remove known pipeline artifacts.
rm -f "$WORKTREE_PATH/.test-results.txt" \
      "$WORKTREE_PATH/.test-baseline.txt" \
      "$WORKTREE_PATH/.worktreepurpose" \
      "$WORKTREE_PATH/.zskills-tracked"

# .landed is also untracked, so it blocks `git worktree remove`. Remove it
# right before removal, but SAVE its content so we can restore on failure
# (preserving proof-of-landing for retry/diagnosis).
LANDED_CONTENT=$(cat "$WORKTREE_PATH/.landed")
rm -f "$WORKTREE_PATH/.landed"

git worktree remove "$WORKTREE_PATH" 2>&1
if [ $? -ne 0 ]; then
  # Restore .landed so retry is possible
  mkdir -p "$WORKTREE_PATH"
  printf '%s\n' "$LANDED_CONTENT" > "$WORKTREE_PATH/.landed"
  echo "ERROR: Failed to remove worktree $WORKTREE_PATH"
  echo "Unexpected files in worktree — investigate before retrying."
  echo ".landed marker restored for retry."
  ls -A "$WORKTREE_PATH" 2>/dev/null | head -20
  exit 1
fi

# 4. Delete local branch (best-effort — may already be gone)
if [ -n "$BRANCH" ] && [ "$BRANCH" != "main" ] && [ "$BRANCH" != "HEAD" ]; then
  git branch -d "$BRANCH" 2>/dev/null || true
fi

# 5. Delete remote branch if it was pushed and PR is merged.
# PR mode branches get pushed during landing; after squash-merge the
# remote branch is no longer needed. Without this cleanup, every PR-mode
# run leaves a stale branch on origin that clutters the branch list.
# Best-effort: silently skip if the remote branch doesn't exist, isn't
# configured, or we don't have permission.
if [ -n "$BRANCH" ] && [ "$BRANCH" != "main" ] && [ "$BRANCH" != "HEAD" ]; then
  # Only attempt if origin has this branch AND the worktree's .landed
  # status indicates the PR actually merged (avoid deleting branches of
  # pr-ready or pr-ci-failing workflows the user may still need).
  # We read the .landed content captured before removal (line 44 area).
  if echo "$LANDED_CONTENT" | grep -q "^status: landed"; then
    git push origin --delete "$BRANCH" 2>/dev/null || true
  fi
fi

echo "Worktree removed: $WORKTREE_PATH"
