#!/bin/bash
# scripts/post-run-invariants.sh — End-of-run assertions for /run-plan.
#
# Purpose: make silent-failure accumulation structurally impossible. After
# a plan run completes (PR mode, cherry-pick mode, or delegate mode), the
# orchestrator MUST invoke this script. It asserts:
#   1. Worktree directory gone from disk
#   2. Worktree removed from git's worktree registry
#   3. Local feature branch deleted (when landed)
#   4. Remote feature branch deleted (when landed)
#   5. Plan report exists at the expected path
#   6. No 🟡 In Progress rows linger in the tracker
#   7. Local main reconcilable with origin/main (warn, not fail — user may
#      have legitimate unpushed work)
#
# Any invariant violation exits non-zero with a specific error. This is
# the mechanical gate that catches silent failures in land-phase.sh or
# the orchestrator's own cleanup. Prose-in-SKILL.md was not enough;
# the LLM may skip prose under compaction. This script WILL run.
#
# Usage:
#   bash scripts/post-run-invariants.sh \
#     --worktree <path> \
#     --branch <name> \
#     --landed-status <status> \
#     --plan-slug <slug> \
#     --plan-file <path>
#
# All args required. Use empty string for irrelevant ones (e.g., direct
# mode has no worktree/branch — pass empty and the related checks skip).

set -u

WORKTREE_PATH=""
BRANCH_NAME=""
LANDED_STATUS=""
PLAN_SLUG=""
PLAN_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --worktree)      WORKTREE_PATH="$2"; shift 2 ;;
    --branch)        BRANCH_NAME="$2"; shift 2 ;;
    --landed-status) LANDED_STATUS="$2"; shift 2 ;;
    --plan-slug)     PLAN_SLUG="$2"; shift 2 ;;
    --plan-file)     PLAN_FILE="$2"; shift 2 ;;
    *)               echo "ERROR: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

# Resolve MAIN_ROOT the same careful way land-phase.sh does.
MAIN_ROOT_GIT_DIR=$(git rev-parse --git-common-dir 2>/dev/null)
if [ -z "$MAIN_ROOT_GIT_DIR" ]; then
  echo "ERROR: post-run-invariants.sh must run from inside a git repository" >&2
  exit 1
fi
MAIN_ROOT=$(cd "$MAIN_ROOT_GIT_DIR/.." && pwd)
if [ -z "$MAIN_ROOT" ] || [ "$MAIN_ROOT" = "/" ]; then
  echo "ERROR: MAIN_ROOT resolved to '$MAIN_ROOT' — aborting" >&2
  exit 1
fi

INVARIANT_FAILED=0

# 1. Worktree directory gone from disk
if [ -n "$WORKTREE_PATH" ]; then
  if [ -d "$WORKTREE_PATH" ]; then
    echo "INVARIANT-FAIL (#1): worktree still on disk at $WORKTREE_PATH" >&2
    INVARIANT_FAILED=1
  fi
fi

# 2. Worktree gone from git's worktree registry
if [ -n "$WORKTREE_PATH" ]; then
  if git -C "$MAIN_ROOT" worktree list --porcelain | grep -q "^worktree $WORKTREE_PATH$"; then
    echo "INVARIANT-FAIL (#2): $WORKTREE_PATH still in git worktree registry" >&2
    INVARIANT_FAILED=1
  fi
fi

# 3. Local feature branch gone (both modes — land-phase.sh deletes on 'landed')
if [ -n "$BRANCH_NAME" ] && [ "$BRANCH_NAME" != "main" ] && [ "$BRANCH_NAME" != "master" ]; then
  if git -C "$MAIN_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    # Only fail if status was 'landed' — pr-ready/conflict intentionally keep
    # the branch around.
    if [ "$LANDED_STATUS" = "landed" ]; then
      echo "INVARIANT-FAIL (#3): local branch $BRANCH_NAME still exists after landed" >&2
      INVARIANT_FAILED=1
    fi
  fi
fi

# 4. Remote feature branch gone (PR mode landed only)
if [ -n "$BRANCH_NAME" ] && [ "$LANDED_STATUS" = "landed" ]; then
  if git -C "$MAIN_ROOT" ls-remote --exit-code --heads origin "$BRANCH_NAME" >/dev/null 2>&1; then
    echo "INVARIANT-FAIL (#4): remote branch origin/$BRANCH_NAME still exists after landed" >&2
    INVARIANT_FAILED=1
  fi
fi

# 5. Plan report exists
if [ -n "$PLAN_SLUG" ]; then
  REPORT_PATH="$MAIN_ROOT/reports/plan-${PLAN_SLUG}.md"
  if [ ! -f "$REPORT_PATH" ]; then
    echo "INVARIANT-FAIL (#5): plan report missing at $REPORT_PATH — Phase 5 didn't run or wrote elsewhere" >&2
    INVARIANT_FAILED=1
  fi
fi

# 6. No 🟡 In Progress rows linger in the tracker.
# Scoped to markdown table rows (lines starting with '|'). Bare whole-file
# grep false-positives on prose, Drift Log sections, and code-fence
# examples that mention the sentinel character — the invariant's real
# concern is the Progress Tracker table, which is always pipe-delimited.
if [ -n "$PLAN_FILE" ] && [ -f "$PLAN_FILE" ]; then
  if grep -qE '^\|.*🟡' "$PLAN_FILE"; then
    echo "INVARIANT-FAIL (#6): plan $PLAN_FILE still has 🟡 In Progress rows after run" >&2
    grep -nE '^\|.*🟡' "$PLAN_FILE" >&2
    INVARIANT_FAILED=1
  fi
fi

# 7. Local main reconcilable with origin/main — WARN not FAIL
# Users may have legitimate unpushed work on local main; we don't reject,
# but we surface it clearly so squash-merge divergence doesn't accumulate
# invisibly.
if ! git -C "$MAIN_ROOT" fetch origin main 2>/dev/null; then
  echo "INVARIANT-WARN (#7): 'git fetch origin main' failed — cannot verify local main alignment" >&2
elif ! git -C "$MAIN_ROOT" merge-base --is-ancestor main origin/main 2>/dev/null; then
  TREE_DIFF=$(git -C "$MAIN_ROOT" diff origin/main main 2>/dev/null | wc -l)
  if [ "$TREE_DIFF" -eq 0 ]; then
    echo "INVARIANT-WARN (#7): local main has commits absent from origin/main but tree is identical (squash-merge divergence). Safe to resolve with: git reset --hard origin/main" >&2
  else
    echo "INVARIANT-WARN (#7): local main diverges from origin/main with $TREE_DIFF lines of real diff — manual reconciliation needed" >&2
  fi
fi

if [ "$INVARIANT_FAILED" -ne 0 ]; then
  echo "" >&2
  echo "Post-run invariants failed. Inspect and resolve before next run." >&2
  exit 1
fi
echo "Post-run invariants: all checks passed."
