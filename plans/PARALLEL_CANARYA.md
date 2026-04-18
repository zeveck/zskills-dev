---
title: Parallel Pipeline Canary A
created: 2026-04-18
status: complete
---

# Plan: Parallel Pipeline Canary A

> **Landing mode: PR** -- This plan targets PR-based landing. All phases
> use worktree isolation with a named feature branch.

## Overview

Minimal single-phase plan for in-vivo validation of concurrent
`/run-plan` execution. Adds exactly one isolated doc file. Designed to
run simultaneously with `plans/PARALLEL_CANARYB.md` in a separate Claude
Code session.

**Success criteria for the parallel run as a whole** (not for this plan
alone):

- Both PRs merge cleanly.
- No tracking markers cross between the two pipelines'
  `.zskills/tracking/run-plan.parallel-canary-*/` subdirs.
- No `fulfilled.run-plan.parallel-canary-{a,b}` collision on main.
- `post-run-invariants.sh` returns 0 for both.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Create canary-A.md | ✅ | `a889c7f` | file created, 364/364 tests pass |

## Phase 1 — Create docs/canary-parallel-A.md

### Goal

Create exactly one new file with a fixed, trivial payload. No other
changes.

### Work Items

- [ ] Create `docs/canary-parallel-A.md` with this exact content:

      ```
      # Parallel Pipeline Canary A

      Marker file from PARALLEL_CANARYA.

      This file validates that two concurrent `/run-plan` sessions
      operating on the same repository complete without tracking-marker
      cross-pollination, worktree collisions, or branch collisions.

      Companion: docs/canary-parallel-B.md (written by PARALLEL_CANARYB).
      ```

      Verification: `test -f docs/canary-parallel-A.md && head -2 docs/canary-parallel-A.md | grep -q 'Canary A'`.

### Design & Constraints

- **Touch only `docs/canary-parallel-A.md`**. Do not modify, create, or
  delete any other file — including `docs/canary-parallel-B.md` if it
  happens to appear in the worktree mid-run (which should not happen
  since the two pipelines use separate worktrees).
- Do not touch `skills/`, `.claude/`, `hooks/`, `scripts/`, `tests/`,
  or any existing file under `docs/`.
- No tests to write — the work is a single static file.

### Acceptance Criteria

- [ ] `test -f docs/canary-parallel-A.md` → exit 0.
      Verification: the file exists.
- [ ] File's first non-empty line is `# Parallel Pipeline Canary A`.
      Verification: `head -1 docs/canary-parallel-A.md`.
- [ ] `bash tests/run-all.sh` passes (baseline preserved; this plan
      must not regress any existing test).
      Verification: tail of results shows `Overall: N/N passed, 0 failed`.
- [ ] `git diff --name-only main..HEAD` lists exactly
      `docs/canary-parallel-A.md` (plus any tracker/report bookkeeping
      commits added by the orchestrator in PR mode).
      Verification: no other source files modified.

### Dependencies

None.

### Verification (phase-exit)

Automatic: the acceptance criteria above.
