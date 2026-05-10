---
title: Chunked Finish-Auto Cron Canary
created: 2026-04-18
status: complete
---

# Plan: Chunked Finish-Auto Cron Canary

> **Landing mode: PR** -- All phases accumulate on one feature branch;
> one PR; squash-merge at the end.

## Overview

Three trivial, file-independent phases designed specifically to exercise
`/run-plan`'s chunked `finish auto` cron mechanism under the post-`b172366`
**+5-minute spacing**.

Each phase runs as its own cron-fired top-level turn, scheduled by the
previous turn's Phase 5c block. Phase 1 runs immediately on invocation.
Phase 2 fires ~5 min after Phase 1 lands on the feature branch. Phase 3
fires ~5 min after Phase 2. Phase 3's turn also does the final push →
PR → CI → auto-merge (the last phase owns the landing).

**What this validates (primarily):**

- Chunked cron scheduling arrives: Phase 2 and Phase 3 actually fire
  (not "pinned-date miss-by-365-days" silent-stall). `b172366` bumped the
  spacing from +1 to +5 precisely to avoid the observed jitter-induced
  miss; we want a clean run under the new spacing to corroborate.
- Fresh top-level context per phase: each cron-fired turn should have
  the `Agent` tool (dispatches impl + verify agents) and produce its
  own verifier commit on the feature branch.
- Inter-phase rebase-onto-origin/main (rebase-point-1) keeps the branch
  current. Should be no-ops here since no external commits are expected
  during the ~15-min window, but the path should still execute cleanly.
- At Phase 3 end: rebase-point-2 + push + PR + CI + auto-merge + squash
  merge on main + worktree/branch cleanup + post-run-invariants 7/7.

**What this does NOT robustly prove**: that the +5 fix specifically
eliminates the jitter miss. The original symptom was intermittent —
a clean run of +5 is consistent with the bug being gone OR with us
happening not to hit jitter this time. Still worth recording a clean
end-to-end result for the post-fix regression baseline.

## Success criteria (whole run)

- All three phases land on `feat/chunked-cron-canary`, each via its own
  cron-fired turn (verify via CronList during the run).
- PR merges cleanly on Phase 3's turn.
- Final main contains all three files:
  `docs/chunked-canary/phase-{1,2,3}.md`.
- `.landed` (Phase 3) shows `status: landed`, `ci: pass`,
  `pr_state: MERGED`.
- `post-run-invariants.sh` → exit 0.
- No cron is left orphaned after the final phase (Phase 5c case 3:
  "All phases done → do NOT schedule a next-phase cron").

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Create phase-1.md | ✅ | `1a39978` | phase-1.md on branch; user-invoked initial turn |
| 2 — Create phase-2.md | ✅ | `ddc1e29` | cron-fired (cron 9d6409e1, +5 spacing) — CLEAN FIRE |
| 3 — Create phase-3.md | ✅ | `e6c5e24` | cron-fired (cron f1629378, +5 spacing) — CLEAN FIRE; also lands the plan |

## Phase 1 — Create docs/chunked-canary/phase-1.md

### Goal

Create one file, no other changes. This phase's turn schedules the
Phase 2 cron before exiting.

### Work Items

- [ ] Create `docs/chunked-canary/phase-1.md` with this content:

      ```
      # Chunked Cron Canary — Phase 1

      This file was created in the first cron-fired turn of
      `/run-plan plans/CHUNKED_CRON_CANARY.md finish auto pr`. Its
      mere existence on the feature branch after the run validates
      that Phase 1 completed and committed.
      ```

### Design & Constraints

- Touch only `docs/chunked-canary/phase-1.md`.
- Local tests must pass at baseline.
- Do NOT touch Phase 2 or Phase 3 files.

### Acceptance Criteria

- [ ] `test -f docs/chunked-canary/phase-1.md` → 0.
- [ ] `bash tests/run-all.sh` passes at baseline.
- [ ] `git diff --name-only main..HEAD` (after verifier's commit) lists
      exactly `docs/chunked-canary/phase-1.md`.
- [ ] Phase 5c schedules a one-shot cron for `/run-plan plans/CHUNKED_CRON_CANARY.md finish auto`
      ~5 min out.

### Dependencies

None.

## Phase 2 — Create docs/chunked-canary/phase-2.md

### Goal

Fires from a cron scheduled by Phase 1's turn. Same shape as Phase 1
but a different file. Schedules Phase 3 cron before exiting.

### Work Items

- [ ] Create `docs/chunked-canary/phase-2.md` with this content:

      ```
      # Chunked Cron Canary — Phase 2

      This file was created in a cron-fired turn triggered ~5 min
      after Phase 1 landed. Its existence proves inter-phase cron
      scheduling and re-entry work under +5-minute spacing.
      ```

### Design & Constraints

- Touch only `docs/chunked-canary/phase-2.md`.
- Local tests must pass at baseline (now 367 + 1 from Phase 1 commit
  already on branch = still 367/367 since phase-1.md is a doc file and
  doesn't count in test runner).
- Do NOT touch Phase 1 or Phase 3 files.

### Acceptance Criteria

- [ ] `test -f docs/chunked-canary/phase-2.md` → 0.
- [ ] Phase 1's file still exists.
- [ ] Phase 5c schedules Phase 3 cron (~5 min out).

### Dependencies

Phase 1.

## Phase 3 — Create docs/chunked-canary/phase-3.md + LAND

### Goal

Final phase's cron-fired turn creates the last file AND lands the plan:
Phase 5b (plan completion) + Phase 6 PR-mode land (rebase, mark ✅,
push, create PR, CI poll, auto-merge, .landed, land-phase.sh,
post-run-invariants).

### Work Items

- [ ] Create `docs/chunked-canary/phase-3.md` with this content:

      ```
      # Chunked Cron Canary — Phase 3

      This file was created in the final cron-fired turn. The same
      turn also landed the whole plan: pushed the feature branch,
      created the PR, watched CI, auto-merged on green, and ran
      post-run-invariants.
      ```

- [ ] Plan landing: push → PR → CI pass → auto-merge → `status: landed`.

### Design & Constraints

- Touch only `docs/chunked-canary/phase-3.md` during impl.
- **No next-phase cron** should be scheduled after this phase — Phase 5c
  case 3 ("all phases done") applies.
- Verify `CronList` is empty after the final turn exits (modulo any
  unrelated crons).

### Acceptance Criteria

- [ ] All three files on final main.
- [ ] PR merged cleanly.
- [ ] post-run-invariants exit 0.
- [ ] Plan frontmatter `status: complete`.
- [ ] No orphan crons left from this pipeline.

### Dependencies

Phase 1, Phase 2.

## Cleanup note

Landed files (`docs/chunked-canary/phase-{1,2,3}.md`) are trivial canary
artifacts. Delete in a follow-up commit when the user confirms the run
is over, along with prior canary artifacts (`docs/canary-parallel-{A,B}.md`,
`skills/ci-fix-canary/`, `.claude/skills/ci-fix-canary/`).
