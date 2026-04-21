---
name: cleanup-merged
disable-model-invocation: true
argument-hint: "[--dry-run | -n]"
description: >-
  Post-PR-merge local state normalization. Fetches origin with --prune,
  switches off a feature branch whose PR has merged (or whose upstream is
  gone), pulls the main branch, and deletes local feature branches whose
  upstream was removed or whose PR has merged. Bails on a dirty working
  tree. Skips branches with unpushed commits. --dry-run reports without
  modifying anything. Use after merging a PR on GitHub to catch local
  state up and drop stale branches.
---

# /cleanup-merged — Post-PR-merge local normalization

`/cleanup-merged` catches your local clone up after a PR merges on
GitHub. It does three things in order: fetch-and-prune, switch to the
main branch and pull, then delete local feature branches whose remotes
are gone or whose PRs are merged.

**Ultrathink throughout.**

Safe to run any time. The skill bails on a dirty working tree and
never deletes a branch with unpushed commits.

## Arguments

- `--dry-run` / `-n` — report what would happen without modifying
  anything. Useful to preview deletions on the first run.

## Phase 1 — Preflight

### WI 1.1 — Tool availability

```bash
if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: /cleanup-merged requires git." >&2
  exit 1
fi

HAVE_GH=1
if ! command -v gh >/dev/null 2>&1; then
  HAVE_GH=0
  echo "NOTE: gh not on PATH; falling back to upstream-gone detection only." >&2
fi
```

### WI 1.2 — Argument parse

```bash
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    *)
      echo "ERROR: unknown argument '$arg'. Usage: /cleanup-merged [--dry-run|-n]" >&2
      exit 2
      ;;
  esac
done
```

### WI 1.3 — Locate main-repo root and detect main branch

```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
cd "$MAIN_ROOT"

MAIN_BRANCH="main"
if ! git show-ref --verify --quiet refs/heads/main \
   && git show-ref --verify --quiet refs/heads/master; then
  MAIN_BRANCH="master"
fi
```

### WI 1.4 — Bail on dirty tree

Untracked files count as dirty: `/cleanup-merged` will `git checkout
main` and `git pull`, which would dump new untracked files back out or
could conflict with an uncommitted edit the user hasn't saved yet.

```bash
if [ -n "$(git status --porcelain)" ]; then
  echo "ERROR: working tree is not clean. Commit, stash, or discard changes first." >&2
  git status --short >&2
  exit 3
fi
```

## Phase 2 — Fetch and prune

```bash
echo "Fetching origin with --prune..."
if ! git fetch origin --prune; then
  echo "ERROR: git fetch failed. Check network/auth." >&2
  exit 4
fi
```

`--prune` removes remote-tracking refs whose upstreams are gone. After
this, `git branch -vv` shows `: gone]` next to local branches whose
remote was deleted — the primary signal for detecting merged PRs when
GitHub's auto-delete-head-branches setting is on.

## Phase 3 — Switch off a merged feature branch (if applicable)

If the current branch is not the main branch, check whether its PR is
merged or its upstream is gone. If so, switch to main so we can delete
the branch later.

```bash
CURRENT=$(git rev-parse --abbrev-ref HEAD)
SWITCHED=0

if [ "$CURRENT" != "$MAIN_BRANCH" ]; then
  UPSTREAM_GONE=0
  if git branch -vv | grep -qE "^\* $CURRENT .*: gone\]"; then
    UPSTREAM_GONE=1
  fi

  PR_STATE=""
  if [ "$HAVE_GH" -eq 1 ]; then
    PR_STATE=$(gh pr view "$CURRENT" --json state -q .state 2>/dev/null || echo "")
  fi

  if [ "$UPSTREAM_GONE" -eq 1 ] || [ "$PR_STATE" = "MERGED" ]; then
    REASON=$([ "$PR_STATE" = "MERGED" ] && echo "PR merged" || echo "upstream gone")
    echo "Current branch '$CURRENT' is safe to leave ($REASON). Switching to $MAIN_BRANCH..."
    if [ "$DRY_RUN" -eq 0 ]; then
      if ! git checkout "$MAIN_BRANCH"; then
        echo "ERROR: failed to checkout $MAIN_BRANCH." >&2
        exit 5
      fi
      SWITCHED=1
    fi
  else
    echo "Current branch '$CURRENT' is not merged (PR state: ${PR_STATE:-unknown}); staying here. Run from $MAIN_BRANCH or after merging to clean it up."
  fi
fi
```

## Phase 4 — Pull main

Only pull if we are on the main branch. A dry-run skips the pull
because we promised not to modify anything.

```bash
ON_MAIN=0
[ "$(git rev-parse --abbrev-ref HEAD)" = "$MAIN_BRANCH" ] && ON_MAIN=1

if [ "$ON_MAIN" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
  echo "Pulling $MAIN_BRANCH..."
  if ! git pull origin "$MAIN_BRANCH"; then
    echo "ERROR: git pull failed." >&2
    exit 5
  fi
fi
```

## Phase 5 — Scan and delete merged branches

For every local branch other than the main branch and the currently
checked-out branch, check the same two signals (upstream gone, PR
merged). Skip branches with unpushed commits unless the upstream is
gone — if the remote is gone, the commits were either squash-merged or
the branch was abandoned; either way, the local commits match no live
ref.

```bash
CURRENT=$(git rev-parse --abbrev-ref HEAD)
DELETED=0
SKIPPED=0

while IFS= read -r branch; do
  [ -z "$branch" ] && continue
  [ "$branch" = "$MAIN_BRANCH" ] && continue
  [ "$branch" = "$CURRENT" ] && continue

  UPSTREAM_GONE=0
  if git branch -vv | grep -qE "^  $branch .*: gone\]"; then
    UPSTREAM_GONE=1
  fi

  PR_STATE=""
  if [ "$HAVE_GH" -eq 1 ]; then
    PR_STATE=$(gh pr view "$branch" --json state -q .state 2>/dev/null || echo "")
  fi

  MERGED=0
  if [ "$UPSTREAM_GONE" -eq 1 ] || [ "$PR_STATE" = "MERGED" ]; then
    MERGED=1
  fi

  [ "$MERGED" -eq 0 ] && continue

  # Unpushed-commit guard (squash-merge still counts commits as unpushed
  # because the squash SHA is different). Only honor the guard when the
  # upstream is NOT gone — a gone upstream plus PR=MERGED means the
  # commits reached main via squash.
  UNPUSHED=""
  if [ "$UPSTREAM_GONE" -eq 0 ]; then
    UNPUSHED=$(git log "$branch" --not --remotes --oneline 2>/dev/null | head -1)
  fi

  if [ -n "$UNPUSHED" ]; then
    echo "  SKIP   $branch (has unpushed commits; delete manually with 'git branch -D $branch' if intentional)"
    SKIPPED=$((SKIPPED+1))
    continue
  fi

  REASON=$([ "$PR_STATE" = "MERGED" ] && echo "PR merged" || echo "upstream gone")
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  WOULD-DELETE $branch ($REASON)"
    DELETED=$((DELETED+1))
  else
    if git branch -D "$branch" >/dev/null; then
      echo "  DELETED $branch ($REASON)"
      DELETED=$((DELETED+1))
    else
      echo "  FAILED  $branch (git branch -D exited non-zero)" >&2
      SKIPPED=$((SKIPPED+1))
    fi
  fi
done < <(git for-each-ref --format='%(refname:short)' refs/heads/)
```

## Phase 6 — Summary

```bash
echo ""
if [ "$DRY_RUN" -eq 1 ]; then
  echo "cleanup-merged (dry-run): would delete $DELETED, skip $SKIPPED. Nothing was modified."
else
  echo "cleanup-merged: deleted $DELETED branches, skipped $SKIPPED."
  if [ "$SWITCHED" -eq 1 ]; then
    echo "(switched to $MAIN_BRANCH and pulled.)"
  elif [ "$ON_MAIN" -eq 1 ]; then
    echo "(on $MAIN_BRANCH, pulled latest.)"
  fi
fi
exit 0
```

## Exit codes

| rc | Meaning |
|----|---------|
| 0 | Success (or dry-run complete) |
| 1 | Missing required tool (git) |
| 2 | Bad argument |
| 3 | Dirty working tree — refuses to proceed |
| 4 | `git fetch` failed |
| 5 | `git checkout` or `git pull` failed |

## Coexistence with other skills

- `/commit land` — post-landing cleanup for cherry-pick mode worktrees.
- `/cleanup-merged` — post-PR-merge cleanup for PR mode (this skill).

Different modes, different cleanup. Cherry-pick commits land on main
inline; PR merges are async (human clicks "merge" on GitHub), so PR
mode needs a separate normalize step.

## When to run

Any time a PR has merged on GitHub and you want your local clone to
reflect it. Typical cadence:

- After `/quickfix`, `/do pr`, `/commit pr`, or any PR-mode skill,
  once the PR has merged.
- Before starting a new feature so you're branching off up-to-date
  main.
- As a cleanup sweep when `git branch` shows stale feature branches
  piling up.

Running it with nothing to do is safe and fast — it fetches, confirms
main is current, finds no merged branches, and exits.
