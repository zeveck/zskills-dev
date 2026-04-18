---
title: CI Fix Cycle Canary
created: 2026-04-18
status: active
---

# Plan: CI Fix Cycle Canary

> **Landing mode: PR** -- This plan targets PR-based landing. The whole
> point is to exercise `/run-plan`'s CI auto-fix cycle (PR-mode specific).

## Overview

Single-phase plan that deliberately seeds a skill-mirror drift in the
same commit that creates a new canary skill. Verifier + local tests
**pass** (no drift check locally), so the commit lands on the feature
branch. **CI's drift step** (defined in `.github/workflows/test.yml`
— the `for src in skills/*/SKILL.md; do ... diff -q ...` loop) catches
the mismatch on push and fails the run.

This exercises the full CI-fix-cycle machinery in `/run-plan` Phase 6
PR-mode:

1. Push → PR created → CI runs → drift check fails.
2. `/run-plan` reads the CI log, posts an initial PR-comment status,
   dispatches a fix agent (attempt 1 of `ci.max_fix_attempts`).
3. Fix agent reads `gh run view --log-failed`, sees `DRIFT:
   .claude/skills/ci-fix-canary/SKILL.md differs from skills/...`,
   overwrites the mirror with the source file's content, commits, pushes.
4. CI re-runs → drift resolved → passes.
5. Auto-merge fires, PR becomes MERGED, worktree cleanup runs,
   `post-run-invariants.sh` passes 7/7.

## Success criteria (whole run)

- PR merges cleanly **after exactly one fix-cycle iteration**.
- `.landed` shows `status: landed`, `ci: pass`, `pr_state: MERGED`.
- Final main contains IDENTICAL `skills/ci-fix-canary/SKILL.md` and
  `.claude/skills/ci-fix-canary/SKILL.md`.
- `post-run-invariants.sh` → exit 0.
- PR has exactly one CI-status comment edited across the cycle (not
  a new comment per attempt — the skill edits in place).

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Seed skill-mirror drift | 🟡 | `ceeb4a6` | drift committed; awaiting CI-fail → fix-cycle → re-pass |

## Phase 1 — Seed skill-mirror drift

### Goal

Introduce a new minimal skill and its `.claude/` mirror with content
that differs between source and mirror. Local tests pass (baseline
preserved). CI's drift step is expected to fail.

### Work Items

- [ ] Create `skills/ci-fix-canary/SKILL.md` with this EXACT content
      (note trailing newline):

      ```
      # /ci-fix-canary — CI Fix Cycle Canary

      A placeholder skill created solely to exercise the CI auto-fix cycle
      via a deliberate skill-mirror drift. Safe to remove after the canary
      run lands.
      ```

- [ ] Create `.claude/skills/ci-fix-canary/SKILL.md` with DIFFERENT
      content (any single-line change is enough to trip `diff -q`):

      ```
      # /ci-fix-canary — CI Fix Cycle Canary (MIRROR — INTENTIONALLY OUT OF SYNC)

      Mirror is deliberately out-of-sync with skills/ci-fix-canary/SKILL.md
      so CI's drift step fails on first push. The fix agent should
      overwrite this file with the content of skills/ci-fix-canary/SKILL.md
      to resolve the drift.
      ```

### Design & Constraints

- Touch ONLY these two files. No other changes. No tests added, no
  existing tests modified, no hook changes, no run-all.sh changes.
- Local tests must remain at their current baseline count (367/367 or
  whatever the current baseline is at run time). `tests/run-all.sh`
  does NOT include a drift check — the drift test lives only in
  `.github/workflows/test.yml`. So the verifier's local run passes
  cleanly against these two files.
- The verifier receives instructions that this drift is INTENTIONAL
  (per this plan). The verifier must commit both files as-is without
  trying to reconcile them locally. If the verifier "helpfully"
  mirrors the source over the mirror before committing, the canary
  fails its purpose — treat that as a verification-protocol violation
  and STOP.

### Acceptance Criteria (Phase 1 alone)

- [ ] Both files exist after the verifier's commit:
      `skills/ci-fix-canary/SKILL.md` AND
      `.claude/skills/ci-fix-canary/SKILL.md`.
- [ ] `diff -q skills/ci-fix-canary/SKILL.md .claude/skills/ci-fix-canary/SKILL.md`
      reports `differ` (non-zero exit). This is the DESIRED state for
      Phase 1's commit; it's the failure-trigger for CI.
- [ ] `bash tests/run-all.sh` passes at the current baseline count
      (367/367 today). Local tests are unaffected by the drift.
- [ ] Worktree diff shows exactly two new files and nothing else.

### Dependencies

None.

### Verification (phase-exit)

Automatic. Post-landing success is validated at the plan level by the
"Success criteria (whole run)" section above — **not** at Phase 1's
exit, because Phase 1's exit is the intentional-drift commit which
deliberately leaves CI in a failing state until the fix cycle resolves it.

## Expected behavior — fix agent attempt 1

The `/run-plan` CI fix cycle dispatches a fresh fix agent with the
failing log in `/tmp/ci-failure-<PR#>.txt`. Expected agent actions:

1. Read the failure log → identifies
   `DRIFT: .claude/skills/ci-fix-canary/SKILL.md differs from skills/ci-fix-canary/SKILL.md`.
2. Read `skills/ci-fix-canary/SKILL.md` and
   `.claude/skills/ci-fix-canary/SKILL.md` to confirm drift content.
3. Overwrite `.claude/skills/ci-fix-canary/SKILL.md` with the content
   of `skills/ci-fix-canary/SKILL.md` (the mirror convention places
   source as the authority). Any other fix direction (deleting either
   file) is acceptable but sub-optimal.
4. Run local tests to confirm no regression.
5. Commit `fix: sync ci-fix-canary mirror`.
6. Push to feature branch; orchestrator re-polls CI.

**Max attempts: 2** (per config default). If the agent somehow can't
resolve in 2 tries, the plan's `.landed` marker will show
`status: pr-ci-failing` and `/run-plan` exits cleanly — which is also
a valid canary result (proves exhaustion works). But attempt 1 should
succeed for this specific failure mode.

## Cleanup note

This canary leaves two files on main after successful landing
(`skills/ci-fix-canary/SKILL.md` and the synced mirror). They are
labeled clearly as canary artifacts. Delete them in a follow-up
commit when the user confirms the canary run is over.
