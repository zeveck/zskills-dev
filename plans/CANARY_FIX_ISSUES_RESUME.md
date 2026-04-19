---
title: Canary — /fix-issues resume reuses existing branch under ZSKILLS_ALLOW_BRANCH_RESUME
created: 2026-04-19
status: active
---

# Canary: /fix-issues Resume Semantics

## Overview

Exercises `/fix-issues` PR mode against an issue whose branch `fix/issue-N` already exists locally with commits ahead of main, with `ZSKILLS_ALLOW_BRANCH_RESUME=1`. Asserts the migrated flow **reuses the existing worktree/branch** instead of erroring (rc=4) or suffixing a timestamp.

Guards against a regression in `CREATE_WORKTREE_SKILL.md` Phase 3 WI 3.1: if `create-worktree.sh`'s rc=2/rc=4 semantics don't perfectly mirror `worktree-add-safe.sh`'s path-exists-resume path under the opt-in env var, multi-issue PR flows break when retried.

This canary is meant to be run manually after CREATE_WORKTREE Phase 3 lands.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Canary exercise | ⬚ | | manual; GitHub issue-99 required |

## Phase 1 — Canary Exercise

### Goal

Verify that re-running `/fix-issues 99 pr` after a prior invocation left `fix/issue-99` + worktree in place succeeds (rc=0) and reuses the existing branch rather than creating `fix/issue-99-<timestamp>` or erroring.

### Work Items

- [ ] 1.1 — Pre-flight: create a throwaway GitHub issue.
  ```bash
  ISSUE_NUM=$(gh issue create --title "canary resume (temp)" --body "canary fix-issues resume test" | grep -oE '[0-9]+$')
  echo "using issue #$ISSUE_NUM"
  # Ensure no prior branch or worktree for this number
  git branch --list "fix/issue-$ISSUE_NUM" | wc -l  # must be 0
  ```
- [ ] 1.2 — First invocation: `/fix-issues $ISSUE_NUM pr`. Let it create worktree + branch + a commit (doesn't need to finish; abort after the first `.zskills-tracked` is written).
- [ ] 1.3 — Sanity-check intermediate state:
  ```bash
  [ -d "/tmp/$(basename $(pwd))-fix-issue-$ISSUE_NUM" ] && echo "worktree ok"
  git show-ref --verify "refs/heads/fix/issue-$ISSUE_NUM" && echo "branch ok"
  ```
  Both must echo "ok".
- [ ] 1.4 — Re-exercise: re-run `/fix-issues $ISSUE_NUM pr` in the same session (or a new one).
- [ ] 1.5 — Assert resume semantics via three independent checks:
  1. `git branch --list "fix/issue-$ISSUE_NUM*" | wc -l` returns exactly 1 — no timestamped suffix branch was created.
  2. `ls -d /tmp/$(basename $(pwd))-fix-issue-$ISSUE_NUM*/ | wc -l` returns exactly 1 — same worktree directory as the first invocation, no sibling variant.
  3. `.zskills-tracked` contents match between first-invocation snapshot and post-re-invocation read. `diff` exits 0.
- [ ] 1.6 — Cleanup: `git worktree remove /tmp/$(basename $(pwd))-fix-issue-$ISSUE_NUM && git branch -D "fix/issue-$ISSUE_NUM" && gh issue close "$ISSUE_NUM"`.

### Acceptance Criteria

- [ ] All three WI 1.5 sub-checks pass. If any fails, the migration broke resume semantics (rc=2/rc=4 mismatch, path collision handler, or tracking-marker rewrite) — revert Phase 3 WI 3.1.

### Dependencies

CREATE_WORKTREE Phase 3 complete.

## Validation history

| Date | Result | Notes |
|------|--------|-------|
