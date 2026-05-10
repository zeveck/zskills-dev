---
title: Rebase-Conflict Canary (manual, two-session)
created: 2026-04-18
status: active
---

# Plan: Rebase-Conflict Canary (manual, two-session)

> **Landing mode: PR** -- Exercises rebase-point-2 (before-push) conflict
> handling in `/run-plan` Phase 6 PR mode.

## Overview

Validates `/run-plan`'s **agent-assisted rebase-conflict resolution**
block in Phase 6 PR-mode landing. Specifically the `≤5 conflict files`
branch that reads both sides and merges intelligently, and the abort-
and-bail fallback when the resolve fails or the agent isn't confident.

**This is a two-session canary** because reproducing a rebase-conflict
requires `origin/main` to advance DURING the canary's run, between
verification and push. A single-session `/run-plan` invocation cannot
produce the conflict on its own.

Session 1 (canary): runs `/run-plan docs/plans/REBASE_CONFLICT_CANARY.md auto pr`.
Session 2 (coordinator): pushes a conflicting change to
`docs/rebase-conflict-target.md` on main while Session 1 is between
verification and push.

## Timing

Session 1 will take ~30-45 s from invocation to Phase 6's push.
Session 2 needs to push its conflicting edit BEFORE Session 1 reaches
the `git rebase origin/main` inside Phase 6's before-push block.

In practice: kick off Session 1, immediately (within 10 seconds)
make the conflicting edit + push in Session 2. If the timing misses,
no conflict occurs and the canary reports a successful clean run
(informative but doesn't exercise the conflict path).

## What to look for

### Happy case — agent-assisted resolve succeeds

- Session 1 rebase attempt fails with conflict on `docs/rebase-conflict-target.md`.
- `CONFLICT_COUNT=1` ≤ 5 → enter agent-assisted resolve block.
- Agent reads both sides, produces merged version preserving both edits.
- `git add` + `git rebase --continue`.
- Local tests run + pass.
- Push → PR → CI → auto-merge.
- Final main: merged version contains both canary's edit AND coordinator's edit.
- `.landed status: landed`, post-run-invariants 7/7.

### Bail case — agent can't resolve

- Session 2 makes a harder conflict that's not cleanly mergeable.
- Agent attempts resolve, tests fail after, or agent decides not to guess.
- `git rebase --abort`, write `.landed status: conflict`, emit
  the "How to resume" instructions, exit 1.
- Worktree stays (user resumes manually).

## Setup

1. Seed `docs/rebase-conflict-target.md` on main with baseline content:
   ```
   # Rebase Conflict Target
   
   Line 1: baseline content.
   ```
2. Both sessions start from the same commit.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Edit rebase-conflict-target.md line 1 | ⬚ | | |

## Phase 1 — Edit docs/rebase-conflict-target.md line 1

### Goal

Make one non-trivial edit to line 1 of
`docs/rebase-conflict-target.md`. Session 2 edits the SAME line
concurrently, producing a rebase conflict at Phase 6 before-push.

### Work Items

- [ ] Change line 1 of `docs/rebase-conflict-target.md` from
      `Line 1: baseline content.` to
      `Line 1: session-1 (run-plan) modified this line.`

### Design & Constraints

- Touch only `docs/rebase-conflict-target.md`.
- Local tests must remain at baseline.
- Do NOT pre-seed the conflict in this same commit — the conflict is
  introduced externally via Session 2's push.

### Session 2 coordinator script

Run concurrently in a separate Claude Code session or terminal:

```bash
cd /workspaces/zskills
# Wait ~5s for Session 1 to start, then inject conflicting edit:
sleep 5
git fetch origin main
git checkout main
sed -i 's/^Line 1: baseline content.$/Line 1: session-2 (coordinator) modified this line./' docs/rebase-conflict-target.md
git add docs/rebase-conflict-target.md
git commit -m "chore: coordinator injects conflicting edit for REBASE_CONFLICT_CANARY"
git push
echo "Coordinator push done. Session 1 should now hit conflict at rebase-point-2."
```

### Acceptance Criteria

- [ ] Session 1's log shows "REBASE CONFLICT:" at rebase-point-2.
- [ ] Session 1 enters agent-assisted resolve block (≤5 files).
- [ ] Either:
      (a) resolve succeeds → tests pass → push → PR → merge, OR
      (b) resolve fails → `.landed status: conflict` with resume
          instructions.
- [ ] No silent resolve — log must clearly indicate which branch.

### Dependencies

None.

## Cleanup note

After the run: delete `docs/rebase-conflict-target.md` in a follow-up
commit. The file is a test fixture with no long-term value.
