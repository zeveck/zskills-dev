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

MAIN_ROOT_GIT_DIR=$(git rev-parse --git-common-dir 2>/dev/null)
if [ -z "$MAIN_ROOT_GIT_DIR" ]; then
  echo "ERROR: land-phase.sh must be run from inside a git repository (cannot resolve MAIN_ROOT)" >&2
  exit 1
fi
MAIN_ROOT=$(cd "$MAIN_ROOT_GIT_DIR/.." && pwd)
if [ -z "$MAIN_ROOT" ] || [ "$MAIN_ROOT" = "/" ]; then
  echo "ERROR: MAIN_ROOT resolved to empty or root ('$MAIN_ROOT') — aborting" >&2
  exit 1
fi

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
BRANCH=$(git -C "$WORKTREE_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

# Ephemeral pipeline files that agents should leave UNTRACKED. If any of
# these are tracked, the run-plan / verifier prompts leaked them into a
# commit — that's a contract violation to surface, not silently work around.
EPHEMERAL_FILES=(".test-results.txt" ".test-baseline.txt" ".worktreepurpose" ".zskills-tracked")
for f in "${EPHEMERAL_FILES[@]}"; do
  if [ -f "$WORKTREE_PATH/$f" ]; then
    # git ls-files exits 0 and prints a path if tracked; empty if not tracked
    tracked=$(git -C "$WORKTREE_PATH" ls-files --error-unmatch "$f" 2>/dev/null || echo "")
    if [ -n "$tracked" ]; then
      echo "ERROR: $f is git-tracked in $WORKTREE_PATH but should be untracked."
      echo "An agent committed it. Fix the /run-plan or verifier prompt to not 'git add' this file,"
      echo "then 'git rm' it from the feature branch and re-land. Refusing to proceed."
      exit 1
    fi
    # Untracked — safe to remove
    if ! rm "$WORKTREE_PATH/$f"; then
      echo "ERROR: Failed to rm untracked $WORKTREE_PATH/$f"
      exit 1
    fi
  fi
done

# .landed is also untracked, so it blocks `git worktree remove`. Remove it
# right before removal, but SAVE its content so we can restore on failure
# (preserving proof-of-landing for retry/diagnosis).
LANDED_CONTENT=$(cat "$WORKTREE_PATH/.landed")
if ! rm "$WORKTREE_PATH/.landed"; then
  echo "ERROR: Failed to rm $WORKTREE_PATH/.landed"
  exit 1
fi

# Confirm worktree working tree is clean before removal — otherwise
# git worktree remove refuses and the residue is invisible to callers
# that only check exit code. Use git status --porcelain to detect any
# staged/unstaged changes or untracked files we didn't anticipate.
if [ -n "$(git -C "$WORKTREE_PATH" status --porcelain 2>/dev/null)" ]; then
  # Restore .landed so the marker isn't lost while we report
  printf '%s\n' "$LANDED_CONTENT" > "$WORKTREE_PATH/.landed"
  echo "ERROR: Worktree $WORKTREE_PATH is not clean — cannot safely remove."
  echo "Current dirty state:"
  git -C "$WORKTREE_PATH" status --porcelain | head -20
  echo ""
  echo ".landed marker restored for retry. Investigate dirty state before re-running."
  exit 1
fi

if ! git worktree remove "$WORKTREE_PATH"; then
  # Restore .landed so retry is possible
  mkdir -p "$WORKTREE_PATH"
  printf '%s\n' "$LANDED_CONTENT" > "$WORKTREE_PATH/.landed"
  echo "ERROR: Failed to remove worktree $WORKTREE_PATH"
  echo "Contents:"
  ls -A "$WORKTREE_PATH" 2>/dev/null | head -20
  echo ".landed marker restored for retry."
  exit 1
fi

# Verify worktree is actually gone from filesystem AND from git's worktree registry
if [ -d "$WORKTREE_PATH" ]; then
  echo "ERROR: $WORKTREE_PATH still exists on disk after 'git worktree remove'"
  exit 1
fi
if git -C "$MAIN_ROOT" worktree list --porcelain | grep -q "^worktree $WORKTREE_PATH$"; then
  echo "ERROR: $WORKTREE_PATH still in git worktree registry after removal"
  exit 1
fi

# 4. Delete local branch — VERIFY it actually goes away.
# When status: landed (PR squash-merged), the feature branch's commits are
# reshaped into a squash commit on origin/main; the original commits are
# not reachable from local main as individual objects, so `git branch -d`
# refuses. We use -D because the content is safe on origin/main.
# For other statuses (pr-ready, pr-ci-failing, conflict), we keep the
# branch — work isn't fully landed yet.
if [ -n "$BRANCH" ] && [ "$BRANCH" != "main" ] && [ "$BRANCH" != "master" ] && [ "$BRANCH" != "HEAD" ]; then
  if echo "$LANDED_CONTENT" | grep -q "^status: landed"; then
    # Use git -C "$MAIN_ROOT" so the command works regardless of caller's CWD.
    # Important when the caller's CWD was the worktree we just removed.
    if ! git -C "$MAIN_ROOT" branch -D "$BRANCH"; then
      echo "ERROR: git branch -D $BRANCH failed"
      exit 1
    fi
    # Verify gone
    if git -C "$MAIN_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
      echo "ERROR: local branch $BRANCH still exists after 'git branch -D'"
      exit 1
    fi
  else
    echo "Keeping local branch $BRANCH (status is not 'landed' — work not fully merged)."
  fi
fi

# 5. Delete remote branch — only when status: landed (PR merged).
# Distinguish three ls-remote outcomes (prior version conflated them):
#   exit 0   → branch exists on origin → delete it
#   exit 2   → branch doesn't exist on origin (with --exit-code) → skip
#   exit 128 → origin unreachable / auth / config error → FAIL LOUDLY
# Prior behavior treated 2 and 128 identically as "skip," meaning a broken
# remote silently passed as "already gone." `git -C "$MAIN_ROOT"` ensures
# this works regardless of caller's CWD.
if [ -n "$BRANCH" ] && [ "$BRANCH" != "main" ] && [ "$BRANCH" != "master" ] && [ "$BRANCH" != "HEAD" ]; then
  if echo "$LANDED_CONTENT" | grep -q "^status: landed"; then
    git -C "$MAIN_ROOT" ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1
    LS_RC=$?
    case "$LS_RC" in
      0)
        # Branch exists on origin — delete it
        if ! git -C "$MAIN_ROOT" push origin --delete "$BRANCH"; then
          echo "ERROR: git push origin --delete $BRANCH failed"
          echo "Remote branch may still exist. Check auth / permissions."
          exit 1
        fi
        # Verify gone on remote
        git -C "$MAIN_ROOT" ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
          echo "ERROR: remote branch $BRANCH still on origin after --delete push"
          exit 1
        fi
        ;;
      2)
        # --exit-code: branch genuinely absent on origin — safe to skip
        echo "Remote branch $BRANCH already absent — skipping delete."
        ;;
      *)
        # Exit 128 (fatal: origin unreachable, auth error, etc.) or unexpected code.
        # This was previously conflated with "already absent," silently allowing a
        # broken remote to masquerade as a clean state. Surface it.
        echo "ERROR: git ls-remote for $BRANCH failed with exit $LS_RC — origin unreachable, misconfigured, or auth failure" >&2
        echo "Cannot verify whether remote branch needs deletion. Fix the remote state and re-run." >&2
        exit 1
        ;;
    esac
  fi
fi

echo "Worktree removed: $WORKTREE_PATH"
