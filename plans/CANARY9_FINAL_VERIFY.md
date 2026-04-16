---
title: Canary 9 — Cross-Branch Final-Verify Gating End-to-End
created: 2026-04-16
status: active
---

# Plan: Canary 9 — Cross-Branch Final-Verify Gating End-to-End

## Overview

Regression canary for the **cross-branch final-verify gate** that
`faab84b` deleted and Phase B restored. Validates the full loop:
`/research-and-go` creates the `requires.verify-changes.final.<META_SLUG>`
marker at Step 0; sub-plan phases land without being blocked by that
marker; when all phases complete, meta-plan Phase 5b's final-verify
gate defers, schedules a `/verify-changes branch` cron, self-reschedules
with exponential backoff, and finally lets the pipeline complete after
the branch-scope verification writes its fulfillment marker.

This is a **manual canary** — it requires multiple cron-fired turns
over real wall-clock time (10 min minimum, up to ~2 h if the verify
takes a while).

## Setup

1. Clean `.zskills/tracking/` of any `requires.verify-changes.final.*`
   or `fulfilled.verify-changes.final.*` markers from prior runs.

2. Identify a trivial synthetic goal that can decompose into exactly
   ONE sub-plan with 2 phases. Example: `add a trivial canary9 marker
   file with a two-phase trivial content change`.

3. Confirm `/research-and-plan` and `/run-plan` are up-to-date with
   Phase B's restorations (meta-plan scope naming,
   `requires.verify-changes.final.<META_PLAN_SLUG>` creation).

## Procedure

Run: `/research-and-go add a trivial canary9 marker file with a two-phase trivial content change`

Let the full pipeline run end-to-end. Do not intervene unless the
acceptance criteria below fail.

## Verification

Time-order (each check observes state at a specific milestone):

1. **Step 0: marker created.** Immediately after `/research-and-go`'s
   Step 0 runs (the meta-plan drafting step), verify:
   ```bash
   ls .zskills/tracking/requires.verify-changes.final.*
   ```
   Exactly one file exists. Its suffix is `meta-<SLUG>` where SLUG
   matches the description tokens (e.g., `meta-canary9-marker-file`).

2. **Sub-plan executes per-phase normally.** Each sub-plan phase
   lands per `/run-plan`'s usual flow. The final-verify marker does
   NOT block sub-plan commits — sub-plans have their own tracking
   scope (`run-plan.<SUB_SLUG>`, not `.<META_SLUG>`), and the hook's
   suffix filter skips the meta-level marker for them.

3. **Phase 5c detects "all done + marker + no fulfillment".** When
   the last sub-plan phase lands, `/run-plan`'s meta-plan Phase 5c
   arrives with all phases done. At that point Phase 5b's final-verify
   gate fires. Observe in the transcript:
   - "Final cross-branch verify pending (attempt 1)."
   - Verify cron scheduled: `Run /verify-changes branch tracking-id=<META_SLUG>`.
   - Re-entry cron scheduled at +10 min (first attempt backoff).
   - `.zskills/tracking/verify-pending-attempts.<META_SLUG>` exists
     with content `1`.

4. **`/verify-changes branch` runs at top level** (cron-fired turn,
   ~1 min after the gate). Observe:
   - Reports written under `reports/verify-branch-<META_SLUG>.md`.
   - Fulfillment marker created:
     `.zskills/tracking/fulfilled.verify-changes.final.<META_SLUG>`.

5. **Re-entry cron fires `/run-plan ... finish auto`.** On the
   next fire (10+ min after gate defer), `/run-plan` re-enters
   Phase 5b's gate, sees fulfillment exists, deletes the attempt
   counter, and proceeds to sub-steps 1–4.

6. **Pipeline completes.** Meta-plan frontmatter set to
   `status: complete`. No residual `requires.verify-changes.final.*`
   enforcement remains (auto-wipe via the Phase B flow).

## Backoff-progression variant (optional, time-consuming)

If you want to exercise the full backoff schedule (10 → 20 → 40 → 60),
intentionally delay fulfillment:

1. After step 3 above, IMMEDIATELY after the attempt 1 gate fires,
   delete the verify cron before it can run:
   `CronDelete <the verify cron id>`.
2. Wait for re-entry (10 min). Observe attempt becomes 2, backoff = 20.
3. Delete the newly-scheduled verify cron (if attempt 1's was replaced).
4. Wait for re-entry (20 min). Observe attempt = 3, backoff = 40.
5. Repeat one more iteration. Observe attempt = 4, backoff capped at 60.
6. Finally, allow `/verify-changes branch` to run. Observe fulfillment,
   attempt counter deletion, Phase 5b completion.

This exercises the backoff table (locked down by
`tests/test-phase-5b-gate.sh`) under real wall-clock time.

## Failure modes

- **Sub-plan gets blocked by meta marker.** Indicates hook suffix
  scoping leaked. Re-run `tests/test-hooks.sh` case B (sub-plan
  doesn't see parent's marker). Fix the hook, not the plan.
- **Verify cron never fires.** Step 3's gate scheduled the cron but
  Claude Code didn't fire it. Check `CronList` output at defer+1min
  to confirm the entry exists. If it does and still doesn't fire,
  escalate — Claude Code's scheduler is broken, not /run-plan.
- **Fulfillment written to wrong path.** `/verify-changes branch`
  wrote `fulfilled.verify-changes.<META_SLUG>` instead of
  `fulfilled.verify-changes.final.<META_SLUG>`. Indicates Phase H's
  parser or marker-stem logic drifted. Re-run
  `tests/test-skill-invariants.sh` check "verify-changes: branch-
  scope marker stem".

## Why manual

Requires real cron firing across real wall-clock elapsed time (10+
minutes minimum, longer for backoff progression), real subagent
dispatch by the cron-fired /verify-changes turn, and real filesystem
state on tracking markers. The unit test (`tests/test-phase-5b-gate.sh`)
covers the state-machine logic; CANARY9 validates the scheduler and
session boundaries work under actual Claude Code runtime.
