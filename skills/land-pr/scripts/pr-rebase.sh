#!/bin/bash
# pr-rebase.sh — Rebase a feature branch onto its base.
#
# Owner: /land-pr (skills/land-pr).
# Spec:  plans/PR_LANDING_UNIFICATION.md WI 1.3.
#
# Behavior:
#   - Idempotent: a no-op rebase ("already up to date") exits 0.
#   - On rebase conflicts: capture conflict-file list to a sidecar
#     BEFORE calling `git rebase --abort` (post-abort the U-state files
#     are gone). Emit CONFLICT_FILES_LIST=<sidecar> to stdout, exit 10.
#   - On other failures (not in repo, branch absent, fetch failure,
#     abort failure): emit `REASON=<token>` to stdout, exit 11.
#
# Args:
#   --branch <name>   feature branch (required)
#   --base   <name>   base branch (default: main)
#
# Stdout: KEY=VALUE lines (CONFLICT_FILES_LIST, REASON).
# Stderr: human-readable error text.
#
# Exits:
#   0  — clean rebase or already up to date
#   10 — rebase conflicts (CONFLICT_FILES_LIST sidecar populated)
#   11 — other failure (REASON populated)
#   2  — usage error

set -u

BRANCH=""
BASE="main"

while [ $# -gt 0 ]; do
  case "$1" in
    --branch) shift; BRANCH="${1:-}" ;;
    --base)   shift; BASE="${1:-}" ;;
    *) echo "ERROR: pr-rebase.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
  shift || true
done

if [ -z "$BRANCH" ]; then
  echo "ERROR: pr-rebase.sh: --branch is required" >&2
  exit 2
fi
if [ -z "$BASE" ]; then
  echo "ERROR: pr-rebase.sh: --base must be non-empty" >&2
  exit 2
fi

# Branch names commonly contain `/` (smoke/foo, feat/bar) — sanitize for
# use in sidecar filenames so we never create unintended /tmp subdirs.
BRANCH_SLUG="${BRANCH//\//-}"
STDERR_LOG="/tmp/land-pr-rebase-stderr-$BRANCH_SLUG-$$.log"

# 1. Verify we're inside a git repo.
if ! git rev-parse --is-inside-work-tree >"$STDERR_LOG" 2>&1; then
  echo "ERROR: pr-rebase.sh: not inside a git repository" >&2
  cat "$STDERR_LOG" >&2
  echo "REASON=not-a-repo"
  exit 11
fi

# 2. Verify the branch exists locally OR resolves on the remote.
if ! git rev-parse --verify "refs/heads/$BRANCH" >"$STDERR_LOG" 2>&1; then
  if ! git ls-remote --exit-code --heads origin "$BRANCH" >"$STDERR_LOG" 2>&1; then
    echo "ERROR: pr-rebase.sh: branch '$BRANCH' not found locally or on origin" >&2
    cat "$STDERR_LOG" >&2
    echo "REASON=branch-absent"
    exit 11
  fi
fi

# 3. Fetch the base.
if ! git fetch origin "$BASE" >"$STDERR_LOG" 2>&1; then
  echo "ERROR: pr-rebase.sh: git fetch origin $BASE failed" >&2
  cat "$STDERR_LOG" >&2
  echo "REASON=network"
  exit 11
fi

# 4. Rebase onto origin/$BASE. Idempotent — "already up to date" exits 0.
if git rebase "origin/$BASE" >"$STDERR_LOG" 2>&1; then
  exit 0
fi

# 5. Rebase failed. Determine if it's a conflict (we have unmerged paths)
#    or some other failure mode. CRITICAL: capture conflict files BEFORE
#    `git rebase --abort` resets the working tree (post-abort, U-state
#    files are gone — see DA2-7 + run-plan/modes/pr.md:30,121 sites).
CONFLICT_FILES=$(git diff --name-only --diff-filter=U)

if [ -n "$CONFLICT_FILES" ]; then
  SIDECAR="/tmp/land-pr-conflict-files-$BRANCH_SLUG-$$.txt"
  printf '%s\n' "$CONFLICT_FILES" > "$SIDECAR"

  if [ ! -s "$SIDECAR" ]; then
    echo "WARN: pr-rebase.sh: empty conflict-files sidecar at $SIDECAR" >&2
  fi

  # Now safe to abort.
  if ! git rebase --abort >"$STDERR_LOG" 2>&1; then
    echo "ERROR: pr-rebase.sh: git rebase --abort failed — repo in intermediate state, manual cleanup needed" >&2
    cat "$STDERR_LOG" >&2
    echo "REASON=abort-failed"
    exit 11
  fi

  echo "CONFLICT_FILES_LIST=$SIDECAR"
  exit 10
fi

# 6. Non-conflict rebase failure.
echo "ERROR: pr-rebase.sh: rebase failed without conflict markers" >&2
cat "$STDERR_LOG" >&2
echo "REASON=rebase-failed"
exit 11
