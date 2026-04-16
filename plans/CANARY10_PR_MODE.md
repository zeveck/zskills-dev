---
title: Canary 10 — PR Mode End-to-End
created: 2026-04-16
status: complete
---

# Plan: Canary 10 — PR Mode End-to-End

## Overview

Regression canary for **PR mode** execution. A 2-phase plan is run with
`/run-plan <plan> finish auto pr`. Validates that per-phase commits
land on a feature branch (NOT main), the pipeline opens a PR at
completion, CI runs, the PR auto-merges, and feature-branch cleanup
happens cleanly.

This canary complements CANARY6 (sequential-PR regression for PR-mode
bookkeeping on main) by exercising the single-PR happy path for
`finish auto pr`. CANARY6 and CANARY10 together span both PR-mode
scenarios.

This is a **manual canary** — it requires real GitHub state (PR
creation, GitHub Actions run, merge). The user has explicitly
confirmed they're happy to run this manually.

## Setup

1. Confirm remote named `origin` (or the user's preferred dev remote)
   points at a GitHub repository with Actions configured to pass on
   trivial commits.
2. Confirm `gh auth status` is authenticated.
3. Local main is up-to-date with remote (`git fetch && git status` shows
   "Your branch is up to date").
4. No lingering `feat/canary10-*` branches remote or local.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 -- Create canary10 file | ✅ Done | `bbec8c3` | PR-mode (landed via squash) |
| 2 -- Append second line   | ✅ Done | `b5ea9be` | PR-mode (landed via squash) |

## Phase 1 -- Create canary10 file

### Goal

Create `canary/canary10.txt` with a single line. Trivial — the point
is to exercise the `finish auto pr` flow end-to-end.

### Work Items

- [ ] Create `canary/canary10.txt` with exactly:
  ```
  Canary 10 Phase 1: PR mode
  ```

### Acceptance Criteria

- [ ] File exists on the **feature branch** (not main) after Phase 1.
- [ ] Phase 1 commit is on the feature branch; `git log main..<branch>`
      shows exactly the Phase 1 implementation commit plus any
      orchestrator bookkeeping commits.
- [ ] `main` is NOT advanced by Phase 1.

## Phase 2 -- Append second line

### Goal

Append a second line.

### Work Items

- [ ] Append one line to `canary/canary10.txt`:
  ```
  Canary 10 Phase 2: PR mode
  ```

### Acceptance Criteria

- [ ] File on feature branch has two lines in order.
- [ ] Phase 2 commit also on feature branch.

## Procedure

Run: `/run-plan plans/CANARY10_PR_MODE.md finish auto pr`

Walk away. Monitor the PR after ~3 min:
- `gh pr list --state open --label canary` (or by branch name).
- Check Actions runs in the GitHub UI.

## Verification (run after pipeline completes)

1. **Per-phase commits on feature branch, not main.**
   ```bash
   git fetch origin
   # Before the PR merges:
   git log origin/main..origin/feat/canary10-* --oneline
   ```
   Shows at least Phase 1 impl, Phase 2 impl, and orchestrator
   bookkeeping commits. `git log main..origin/feat/...` locally
   shows the same.

2. **PR created by `gh pr create`.** `gh pr list` shows a PR from
   `feat/canary10-*` to `main`. Body references the plan file.

3. **CI ran.** `gh pr view <N> --json statusCheckRollup` shows at
   least one successful check suite.

4. **PR auto-merged.** `gh pr view <N> --json state` returns
   `MERGED`. Merge strategy matches project default (squash merge
   in most projects).

5. **Remote feature branch deleted post-merge.**
   `git ls-remote --heads origin | grep canary10` is empty.
   `land-phase.sh` deletes the remote branch after auto-merge.

6. **Local main fast-forwards cleanly.**
   ```bash
   git checkout main
   git pull --ff-only origin main
   ```
   No merge conflicts, no "diverged" message, no rebase prompts.

7. **`canary/canary10.txt` on main has both lines.**
   ```bash
   cat canary/canary10.txt
   ```
   Two lines in order.

8. **No local divergence remnants.**
   ```bash
   git log origin/main..main   # empty — no ahead commits
   git log main..origin/main   # empty — no behind commits
   ```
   (This is the key CANARY6-regression cross-check: if orchestrator
   bookkeeping leaked onto main instead of the feature branch, this
   will fail.)

9. **No leftover worktrees.** `git worktree list` has no `canary10`
   entries.

## Failure modes

- **Commits landed on main instead of feature branch.** PR-mode
  bookkeeping regressed. Re-run CANARY6 to confirm; fix the bookkeeping
  path.
- **PR created but CI never runs.** GitHub Actions not configured or
  workflow file missing. Set up the project first, then re-run.
- **PR merged but feature branch still present.** `land-phase.sh`'s
  remote-branch deletion path is broken. Check its output.
- **`git pull --ff-only` fails post-merge.** Local main has divergent
  commits — CANARY6-class bug has returned.

## Why manual

Requires real GitHub state: a real remote, real PR creation, real CI
execution, real merge. These cannot be mocked in `tests/run-all.sh`
without a full GitHub-API fake. The user has committed to running
this by hand post-restoration.
