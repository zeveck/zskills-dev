---
title: Canary 8 — Parallel Pipelines Don't Cross-Block
created: 2026-04-16
status: active
---

# Plan: Canary 8 — Parallel Pipelines Don't Cross-Block

## Overview

Parallel pipelines are a **core requirement** of the system, not an
afterthought. This canary validates that two `/run-plan` invocations
executing at the same time, on disjoint plans, complete independently —
neither pipeline's tracking markers block the other's commits or pushes.

The automated foundation (hook suffix-match filter cases A–F in
`tests/test-hooks.sh` after this Phase F lands) already proves the
mechanism. CANARY8 validates real end-to-end behavior with Claude Code
firing cron schedules, multiple sessions, actual git state, and the
hook under real inputs.

This is a **manual canary** — parallel session orchestration is hard
to automate without a fleet harness.

## Setup

Before running:

1. Pick two disjoint canary plans (both trivial, 1 phase each):
   - Pipeline A: `plans/CANARY8_P_A.md` — creates `canary/p-a.txt`
   - Pipeline B: `plans/CANARY8_P_B.md` — creates `canary/p-b.txt`

   (Draft these ahead of time with `/draft-plan` if they don't exist.)

2. Fresh `.zskills/tracking/` state — remove any leftover requires.*
   or fulfilled.* markers from prior runs.

3. Confirm `git status` is clean.

## Procedure

In two separate top-level Claude Code sessions (or two REPL windows
connected to the same repo), run simultaneously:

- Session 1: `/run-plan plans/CANARY8_P_A.md 1 auto`
- Session 2: `/run-plan plans/CANARY8_P_B.md 1 auto`

(Start them within 10 seconds of each other. Exact simultaneity doesn't
matter — overlap during the implement/verify window does.)

Let both pipelines run to completion (landing).

## Verification

1. **Both pipelines complete without error.** No session reports
   "HALTED", "blocked by tracking requirement", or similar cross-
   pipeline interference.

2. **Pipeline A's requires.* markers never block Pipeline B's
   commits** (and vice versa). Inspect each session's transcript —
   the hook output for every Bash-tool commit attempt must reference
   the OWN pipeline's markers only, never the other's.

3. **Tracking markers are independent after landing.** Post-run
   `.zskills/tracking/` contains fulfillment markers for both
   pipelines; neither pipeline's requires marker leaked into the
   other's scope.

4. **Canary files both exist on main.**
   - `canary/p-a.txt` — created by Pipeline A's Phase 1.
   - `canary/p-b.txt` — created by Pipeline B's Phase 1.

5. **`tests/test-hooks.sh` still passes.** The hook behavior is
   unchanged; this is a smoke check that nothing regressed during
   the parallel run.

6. **Cross-check with Phase F's unit tests.** The cases A–F
   pipeline-scoping filter tests (extension in `tests/test-hooks.sh`)
   should have passed before CANARY8 ran. If they failed, do not run
   CANARY8 — fix the mechanism first. CANARY8 validates end-to-end
   behavior; the unit tests validate the filter itself.

## Failure modes to watch for

- **Cross-block on pre-landing hook:** Pipeline A's commit is
  refused because Pipeline B's `requires.*` marker is present.
  Indicates suffix-matching in the hook is broken (re-run the
  case-A–F unit tests; they will also fail).
- **Tracker file overwrites:** Phase B's session writes to the
  same tracker file Phase A is reading. Indicates per-pipeline
  tracker scoping drifted.
- **Cron collision:** Both pipelines schedule next-phase crons
  that fire in the wrong session. Less likely with 1-phase plans;
  watch anyway.

If any failure mode fires, file an issue with:
- Both plan paths.
- The full transcripts of both sessions.
- The `.zskills/tracking/` listing at the moment of failure.
- The hook's decision output (from stderr/stdout of the refused op).

## Why this is a manual canary

Running two Claude Code sessions in parallel against the same repo
requires:
- Two live REPL attachments (no scripted fleet orchestration in-tree).
- Real cron firing per session.
- Real file-system contention on `.zskills/tracking/` and the git
  index.

None of these are automatable without a cloud harness. The unit tests
(cases A–F) lock down the mechanism; CANARY8 validates the mechanism
holds under real-world contention.
