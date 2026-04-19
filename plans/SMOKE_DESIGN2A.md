---
title: Design 2a Chunking Smoke
created: 2026-04-19
status: active
---

# Plan: Design 2a Chunking Smoke

> **Landing mode: direct** -- This plan targets direct-to-main landing.
> No worktree isolation.

## Overview

Runtime smoke for Design 2a recurring-cron chunking (commit `20fd09c`). Two trivial phases, each appending a line to `reports/smoke-design2a.md`. Exercises:

1. Phase 1 runs (cron absent → Phase 5c creates recurring `*/1 * * * *` cron).
2. Cron fires → Phase 2 runs in a fresh cron-fired turn.
3. Phase 2 completion + Phase 5b sets `status: complete`.
4. Next cron fire → Phase 1 Step 0 Case 1 deletes the cron.

**Smoke-only.** Do NOT modify any file under `skills/`, `scripts/`, `tests/`, or `hooks/`. Cleanup at pipeline end: `git rm reports/smoke-design2a.md` as part of Phase 2's work.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Create smoke file (line 1) | ✅ | (pending commit hash) | Direct mode: file created + verified inline |
| 2 — Append line 2 and remove smoke file | ⬚ | | |

---

## Phase 1 — Create smoke file (line 1)

### Goal

Create `reports/smoke-design2a.md` with a single line: `smoke-phase-1`.

### Execution: direct

Work happens directly on main (no worktree). The agent creates the file, stages it, and commits.

### Work Items

- [ ] 1.1 Create `reports/smoke-design2a.md` containing exactly the line `smoke-phase-1` followed by a newline.
- [ ] 1.2 Verify `cat reports/smoke-design2a.md` returns `smoke-phase-1`.
- [ ] 1.3 Stage and commit with message: `chore(smoke): design-2a smoke phase 1`.

### Design & Constraints

- Direct landing mode (Phase 6 is a no-op in direct mode; work already on main after commit).
- No tests — byte content IS the check.
- No agent dispatch needed in strict terms (trivial work). The orchestrator may execute inline for this smoke; formal agent dispatch is acceptable if preferred but optional.

### Acceptance Criteria

- [ ] `reports/smoke-design2a.md` exists in the repo.
- [ ] Its content is exactly `smoke-phase-1\n` (6 bytes of text + 1 newline = 15 bytes total).
- [ ] `wc -l reports/smoke-design2a.md` reports 1.
- [ ] Commit landed on main: `git log --oneline -1` shows `chore(smoke): design-2a smoke phase 1`.

### Dependencies

None.

---

## Phase 2 — Append line 2 and remove smoke file

### Goal

Append `smoke-phase-2` to `reports/smoke-design2a.md`, verify, THEN remove the file as cleanup in the same commit.

### Execution: direct

### Work Items

- [ ] 2.1 Append a newline-terminated line `smoke-phase-2` to `reports/smoke-design2a.md`.
- [ ] 2.2 Verify the file has exactly 2 lines via `wc -l`.
- [ ] 2.3 After verification passes, `git rm reports/smoke-design2a.md` to clean up the repo.
- [ ] 2.4 Commit with message: `chore(smoke): design-2a smoke phase 2 + cleanup`.

### Design & Constraints

- Same as Phase 1.
- The verification in 2.2 runs BEFORE the removal in 2.3 — critical ordering.

### Acceptance Criteria

- [ ] Phase 2's commit on main contains both the append (line 2) AND the removal (git rm).
- [ ] Post-commit, `reports/smoke-design2a.md` does NOT exist.
- [ ] Commit message: `chore(smoke): design-2a smoke phase 2 + cleanup`.

### Dependencies

Phase 1 must have created the file.
