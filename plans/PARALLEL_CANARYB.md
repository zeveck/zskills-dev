---
title: Parallel Pipeline Canary B
created: 2026-04-18
status: complete
---

# Plan: Parallel Pipeline Canary B

> **Landing mode: PR** -- This plan targets PR-based landing. All phases
> use worktree isolation with a named feature branch.

## Overview

Minimal single-phase plan for in-vivo validation of concurrent
`/run-plan` execution. Adds exactly one isolated doc file. Designed to
run simultaneously with `plans/PARALLEL_CANARYA.md` in a separate Claude
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
| 1 — Create canary-B.md | 🟡 In Progress | `53c62e2` | One file, baseline tests preserved |

## Phase 1 — Create docs/canary-parallel-B.md

### Goal

Create exactly one new file with a fixed, trivial payload. No other
changes.

### Work Items

- [ ] Create `docs/canary-parallel-B.md` with this exact content:

      ```
      # Parallel Pipeline Canary B

      Marker file from PARALLEL_CANARYB.

      This file validates that two concurrent `/run-plan` sessions
      operating on the same repository complete without tracking-marker
      cross-pollination, worktree collisions, or branch collisions.

      Companion: docs/canary-parallel-A.md (written by PARALLEL_CANARYA).
      ```

      Verification: `test -f docs/canary-parallel-B.md && head -2 docs/canary-parallel-B.md | grep -q 'Canary B'`.

### Design & Constraints

- **Touch only `docs/canary-parallel-B.md`**. Do not modify, create, or
  delete any other file — including `docs/canary-parallel-A.md` if it
  happens to appear in the worktree mid-run (which should not happen
  since the two pipelines use separate worktrees).
- Do not touch `skills/`, `.claude/`, `hooks/`, `scripts/`, `tests/`,
  or any existing file under `docs/`.
- No tests to write — the work is a single static file.

### Acceptance Criteria

- [ ] `test -f docs/canary-parallel-B.md` → exit 0.
      Verification: the file exists.
- [ ] File's first non-empty line is `# Parallel Pipeline Canary B`.
      Verification: `head -1 docs/canary-parallel-B.md`.
- [ ] `bash tests/run-all.sh` passes (baseline preserved; this plan
      must not regress any existing test).
      Verification: tail of results shows `Overall: N/N passed, 0 failed`.
- [ ] `git diff --name-only main..HEAD` lists exactly
      `docs/canary-parallel-B.md` (plus any tracker/report bookkeeping
      commits added by the orchestrator in PR mode).
      Verification: no other source files modified.

### Dependencies

None.

### Verification (phase-exit)

Automatic: the acceptance criteria above.
