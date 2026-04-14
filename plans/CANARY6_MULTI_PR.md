---
title: Canary 6 — Multi-PR Sequential PR-Mode Regression
created: 2026-04-14
status: active
---

# Plan: Canary 6 — Multi-PR Sequential PR-Mode Regression

## Overview

Regression canary for the scenario **none of Canaries 1-5 covered**: two PR-mode plan runs executed *sequentially as separate PRs* on the same codebase. This is the exact scenario that produced local-main divergence across EXECUTION_MODES Phases 4 → 5a → 5b.

Each phase runs as its own `/run-plan <plan> <phase> pr auto` invocation (NOT `finish` mode — each phase gets its own PR, merged independently, before the next phase starts). Validates that:

- Post-PR-#13 `/run-plan` commits orchestrator bookkeeping on the feature branch, not local main.
- After each PR's squash-merge, local `main` fast-forwards cleanly onto `origin/main` with no divergent bookkeeping commits.
- Sequential phases don't compound divergence.
- `land-phase.sh` deletes the remote feature branch after landing.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 -- Create canary6 file | ✅ Done | `e76f772` | Trivial file creation, one phase per PR |
| 2 -- Append to canary6 file | ⬜ | | Trivial edit, second sequential PR |

## Phase 1 -- Create canary6 file

### Goal

Create `canary/canary6.txt` with a single line. Trivial implementation — the point is to exercise `/run-plan pr` end-to-end, not to build anything.

### Work Items

- [ ] Create directory `canary/` if it doesn't exist
- [ ] Create file `canary/canary6.txt` with contents:
  ```
  Canary 6 Phase 1: created
  ```
- [ ] Verify file exists, single line, exact content

### Acceptance Criteria

- [ ] `canary/canary6.txt` exists
- [ ] File has exactly one line: `Canary 6 Phase 1: created`
- [ ] `bash tests/test-hooks.sh` continues to pass (116/116)
- [ ] PR #X merged to `origin/main` via auto-merge
- [ ] After merge, local `main` fast-forwards cleanly via `git pull --ff-only` (no rebase conflicts, no divergent commits)
- [ ] Remote `feat/canary6-multi-pr` branch is deleted post-merge

### Dependencies

None.

## Phase 2 -- Append to canary6 file

### Goal

Append a second line to `canary/canary6.txt`. This is the critical phase — it runs after Phase 1 has merged, so `origin/main` has advanced. This is the scenario where divergence compounded before PR #13's fix.

### Work Items

- [ ] Append to `canary/canary6.txt`:
  ```
  Canary 6 Phase 2: appended
  ```
- [ ] Verify file has exactly two lines, both in correct order

### Acceptance Criteria

- [ ] `canary/canary6.txt` has two lines total:
  ```
  Canary 6 Phase 1: created
  Canary 6 Phase 2: appended
  ```
- [ ] `bash tests/test-hooks.sh` continues to pass (116/116)
- [ ] PR #Y merged to `origin/main` via auto-merge
- [ ] After merge, local `main` fast-forwards cleanly (STILL no divergent commits — this is the regression signal)
- [ ] Remote `feat/canary6-multi-pr` branch is deleted post-merge
- [ ] **Cross-phase check (the regression indicator):** the `/refine-plan`-style reality check — after Phase 2's PR merges, is local `main == origin/main`? If yes: fix works. If no: bug is back or incomplete.

### Dependencies

Phase 1 must be fully landed on `origin/main` before Phase 2 starts (that's the whole point of the test — exercise the sequential-PR-against-advanced-main scenario).

## Verification after completion

After both phases merge:

1. `git fetch origin main && git log origin/main..main` — must be empty (no local commits ahead).
2. `git log main..origin/main` — must be empty (no local commits behind).
3. `git worktree list` — no leftover canary6 worktrees.
4. `git ls-remote --heads origin | grep canary6` — no leftover remote branch.
5. `cat canary/canary6.txt` (on main) — exactly two lines as specified above.
6. `reports/plan-canary6-multi-pr.md` exists with both phase sections, both marked Landed.

If all 6 checks pass, the PR-mode fix is empirically validated. If any fail, the fix is incomplete.
