---
title: Canary — /do worktree mode preserves user's current HEAD as base branch
created: 2026-04-19
status: active
---

# Canary: /do Worktree Mode Base-Branch Preservation

## Overview

Exercises `/do ... worktree` from a non-main feature branch and asserts the created worktree branches from the user's current HEAD, not from `origin/main`. Guards against a regression mode in `CREATE_WORKTREE_SKILL.md` Phase 3 WI 3.3: if `--no-preflight` isn't threaded correctly into the `create-worktree.sh` invocation, the new flow silently fetches + ff-merges and branches from `origin/main` — a functional shift users wouldn't notice until their worktree lacks their in-flight feature commits.

This canary is meant to be run manually after CREATE_WORKTREE Phase 3 lands.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Canary exercise | ⬚ | | manual |

## Phase 1 — Canary Exercise

### Goal

Verify that `/do "X" worktree` invoked while on feature branch `canary/do-base-N` produces a worktree whose HEAD reaches a commit unique to that feature branch (proving the base-branch preservation semantic).

### Work Items

- [ ] 1.1 — Pre-flight: create feature branch and unique commit. Use whichever remote name the repo configures (`dev`, `origin`, etc.); substitute throughout.
  ```bash
  REMOTE=$(git remote | head -1)
  git checkout main && git pull "$REMOTE" main
  git checkout -b canary/do-base-$$
  echo "canary-marker-$(date +%s)" > canary-marker.txt
  git add canary-marker.txt
  git commit -m "canary: unique marker for base-branch test"
  UNIQUE_COMMIT=$(git rev-parse HEAD)
  ```
- [ ] 1.2 — Exercise: `/do "add comment to canary-marker.txt" worktree` (or any trivial task).
- [ ] 1.3 — Observe: worktree created at `../do-<slug>` (or per config). Note its path as `$WT`.
- [ ] 1.4 — Assert: `git -C $WT log --format=%H | grep -q "$UNIQUE_COMMIT"` — exit 0. The worktree's history includes the feature-branch commit, proving it branched from feat-branch HEAD, not `origin/main`.
- [ ] 1.5 — Cleanup: `cd $MAIN_REPO && git worktree remove $WT && git branch -D canary/do-base-$$ && rm canary-marker.txt`. **If WI 1.4 failed**, skip cleanup first and inspect `$WT/.git`, `git -C $WT log`, to capture evidence before reverting Phase 3.

### Acceptance Criteria

- [ ] WI 1.4 grep exits 0. If it exits 1, the migration lost `--no-preflight` wiring and `/do` worktree mode now silently rebases users onto main. Report and revert Phase 3.

### Dependencies

CREATE_WORKTREE Phase 3 complete.

## Validation history

| Date | Result | Notes |
|------|--------|-------|
