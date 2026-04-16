---
title: Canary 7 — Chunked Finish Auto End-to-End
created: 2026-04-16
status: active
---

# Plan: Canary 7 — Chunked Finish Auto End-to-End

## Overview

Regression canary for the **chunked finish auto** execution mode that
`faab84b` silently deleted and Phase A restored. A 2-phase plan is run
with `/run-plan plans/CANARY7_CHUNKED_FINISH.md finish auto`. The point:
each plan phase must fire as its own top-level cron-fired turn, NOT as
two phases looped inside one long session.

If this canary fails, chunked execution is broken — late-phase fatigue
returns and verification gets skipped on the last phase. That is the
original failure mode this mode exists to prevent.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 -- Create canary7 file | ⬜ | | Trivial file create |
| 2 -- Append second line  | ⬜ | | Trivial file append |

## Phase 1 -- Create canary7 file

### Goal

Create `canary/canary7.txt` with a single line. Trivial implementation —
the point is to exercise chunked `/run-plan finish auto` end-to-end, not
to build anything substantive.

### Work Items

- [ ] Create directory `canary/` if it doesn't exist.
- [ ] Create file `canary/canary7.txt` with exactly one line:
  ```
  Canary 7 Phase 1: chunked turn 1
  ```

### Acceptance Criteria

- [ ] `canary/canary7.txt` exists on the worktree branch.
- [ ] File has exactly one line: `Canary 7 Phase 1: chunked turn 1`.
- [ ] Phase 1 lands (worktree-mode cherry-pick to main, or PR merge).
- [ ] A one-shot cron for `/run-plan plans/CANARY7_CHUNKED_FINISH.md finish auto`
      exists in `CronList` output when Phase 1's cron-fired turn exits.

### Dependencies

None.

## Phase 2 -- Append second line

### Goal

Append a second line to `canary/canary7.txt`. This phase must fire in a
**separate cron-fired turn** from Phase 1 — that is the regression signal.

### Work Items

- [ ] Append one line to `canary/canary7.txt`:
  ```
  Canary 7 Phase 2: chunked turn 2
  ```

### Acceptance Criteria

- [ ] `canary/canary7.txt` has exactly two lines in this order:
  ```
  Canary 7 Phase 1: chunked turn 1
  Canary 7 Phase 2: chunked turn 2
  ```
- [ ] Phase 2 lands successfully.
- [ ] Plan frontmatter status is set to `complete`.

### Dependencies

Phase 1 must be fully landed before Phase 2 starts — and more
specifically, the between-phases cron-fired turn boundary must have
actually occurred (see Verification below).

## Verification (USER PROCEDURE — run after both phases complete)

This canary's distinguishing claim is that Phase 1 and Phase 2 each run
in their own top-level cron-fired turn. Verify it mechanically, not by
vibe:

1. **Per-phase tracker step-marker mtimes diverge by a cron interval.**
   The `step.run-plan.canary7-chunked-finish.implement` marker in
   `.zskills/tracking/` is re-written by Phase 1 and Phase 2. Before
   Phase 2 starts, capture Phase 1's `implement` mtime (or retrieve
   from git log of the tracker commits). After Phase 2 lands, compare
   the two mtimes. Expected gap: at least the one-shot cron interval
   (~60 s target, because `finish auto` schedules the next-phase cron
   1–2 min out). If the gap is under 10 s, both phases ran in ONE turn
   — regression.

   **Do NOT use wall-clock between user's turns.** User perception can
   be <60 s due to minute-rollover rounding. Use the marker mtimes.

2. **A one-shot cron was actually scheduled between phases.** After
   Phase 1's cron-fired turn exits but BEFORE Phase 2 fires, run
   `CronList` (via Claude Code) and confirm an entry whose prompt
   matches `.*finish auto` and whose `recurring` field is `false`.

3. **Idempotent re-entry ran on Phase 2's turn.** Phase 2's turn must
   execute Phase 1's Step 0 idempotency check first. Verify:
   - At the moment Phase 2's turn starts, the plan tracker already
     marks Phase 1 as Done.
   - Phase 2's turn does NOT rewrite Phase 1's marker or re-land Phase 1.
   - Phase 2's turn transcript (if retained) shows the "Step 0:
     Idempotent re-entry check (chunked finish auto only)" pre-amble.

4. **Frontmatter finalized after Phase 2 lands.** Plan file's YAML
   frontmatter has `status: complete`. This comes from Phase 5b sub-
   step 3.

5. **No residual finish-auto cron after completion.** After Phase 2
   lands, `CronList` must NOT contain a lingering `.*finish auto` cron
   for this plan. If one is still scheduled, Phase 5c's "all phases
   done → do NOT schedule next cron" guard is broken.

If all 5 checks pass: chunked finish auto is working. If any fail, file
an issue with the plan path, Phase 1 & Phase 2 marker mtimes, the
CronList snapshot, and the transcript of the turn that fails the check.
