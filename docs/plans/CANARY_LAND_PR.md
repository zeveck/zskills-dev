---
title: Canary — /land-pr End-to-End (PR_LANDING_UNIFICATION Phase 6 WI 6.2)
created: 2026-05-01
status: ready
---

# Plan: Canary — /land-pr End-to-End

> **Landing mode: PR** -- This canary exercises the unified `/land-pr`
> dispatch path: `/run-plan` (caller) → `/land-pr` (callee) → CI fail
> on attempt 1 → fix-cycle dispatch → CI pass on attempt 2 → auto-merge.

## Overview

Single-phase plan that deliberately seeds a CI failure on attempt 1
(via skill-mirror drift, same as `CI_FIX_CYCLE_CANARY`) but with the
post-PR-LANDING-UNIFICATION dispatch contract: `/run-plan`'s PR mode
no longer owns the inline rebase + push + create + monitor + merge
implementation. Those primitives moved to `/land-pr`, and `/run-plan`
dispatches `/land-pr` via the Skill tool, then waits on the result file
(`/tmp/land-pr-result-*.txt`) and feeds CI failures back into the
fix-cycle agent.

This canary validates the full caller-loop pattern documented in
`skills/land-pr/references/caller-loop-pattern.md`:

1. `/run-plan` PR mode prepares branch + body + dispatches `/land-pr`.
2. `/land-pr` runs `pr-rebase.sh` → `pr-push-and-create.sh` →
   `pr-monitor.sh` synchronously; CI fails on attempt 1; result file
   written with `STATUS=ci-failing`, `CI_LOG_FILE=/tmp/land-pr-ci-log-*`.
3. `/run-plan` parses the result file via the allow-list parser (NEVER
   `source`s it), reads `CI_LOG_FILE`, dispatches a fix-cycle agent.
4. Fix agent reads the CI log, fixes the drift, commits, pushes.
5. `/run-plan` re-dispatches `/land-pr` (still in caller-loop iteration
   2). `pr-monitor.sh` re-polls; CI passes; `pr-merge.sh` requests
   auto-merge.
6. Result file: `STATUS=landed`, `PR_STATE=MERGED`, `CI_STATUS=pass`.
7. `.landed` written by `/run-plan`'s post-invariants step (NOT by
   `/land-pr` — caller owns the marker write per WI 1.7 contract).

This canary is the unified successor to `CI_FIX_CYCLE_CANARY.md` —
that older canary tested the inline-block era. After PR_LANDING_UNIFICATION
landed, the same scenario must succeed via the dispatch path.

## Success criteria (whole run)

- PR merges cleanly **after exactly one fix-cycle iteration**.
- `.landed` shows `status: landed`, `ci: pass`, `pr_state: MERGED`.
- Final main contains IDENTICAL `skills/land-pr-canary/SKILL.md` and
  `.claude/skills/land-pr-canary/SKILL.md`.
- `post-run-invariants.sh` → exit 0.
- `/run-plan`'s caller loop iterated exactly twice:
  - Iteration 1: `STATUS=ci-failing`, `CI_LOG_FILE` non-empty,
    fix-cycle dispatched.
  - Iteration 2: `STATUS=landed`, no fix-cycle.
- Result file (`/tmp/land-pr-result-*.txt`) was parsed via the
  allow-list parser — verified by absence of `source` / `.` against
  the result file in `/run-plan`'s caller-loop bash.
- All 4 `/land-pr` scripts (`pr-rebase.sh`, `pr-push-and-create.sh`,
  `pr-monitor.sh`, `pr-merge.sh`) were invoked at least once during
  the run (verified via debug trace or `set -x` capture if needed).

## Setup

1. Confirm remote named `dev` (or the user's preferred dev remote)
   points at a GitHub repository with Actions configured. The CI
   workflow MUST include the skill-mirror drift check at
   `.github/workflows/test.yml:82-122` (PR #149's `for src in
   skills/*/SKILL.md` loop).
2. Confirm `gh auth status` is authenticated.
3. Local main is up-to-date with remote (`git fetch dev && git status`
   shows "Your branch is up to date").
4. No lingering `feat/canary-land-pr-*` branches local or remote.
5. `/land-pr` scripts present and executable:
   ```bash
   for s in pr-rebase pr-push-and-create pr-monitor pr-merge; do
     [ -x "skills/land-pr/scripts/$s.sh" ] || echo "MISSING: $s.sh"
   done
   ```
6. Conformance baseline green: `bash tests/test-skill-conformance.sh`
   passes (the WI 6.1 cross-skill tripwires must already be passing
   before the canary runs — those tripwires asserting "no inline gh
   pr create / checks --watch / merge outside /land-pr" are themselves
   the static drift-prevention layer that this canary's behavioral
   layer complements).

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Seed land-pr drift + run dispatch cycle | ⬜ Ready | — | manual canary; user runs end-to-end |

## Phase 1 — Seed land-pr drift + run dispatch cycle

### Goal

Introduce a new minimal skill (`/land-pr-canary`) with a deliberate
source/mirror drift, then run `/run-plan plans/CANARY_LAND_PR.md
finish auto pr` and observe the full /land-pr dispatch + fix-cycle +
auto-merge end-to-end.

### Work Items

- [ ] Create `skills/land-pr-canary/SKILL.md` with this content (note
      trailing newline):

      ```
      ---
      name: land-pr-canary
      description: Placeholder skill for the /land-pr end-to-end canary
      ---

      # /land-pr-canary — /land-pr End-to-End Canary

      A placeholder skill created solely to exercise the unified
      `/land-pr` dispatch path. Safe to remove after the canary run
      lands.
      ```

- [ ] Create `.claude/skills/land-pr-canary/SKILL.md` with DIFFERENT
      content (any single-line change is enough to trip `diff -q` in
      `.github/workflows/test.yml`):

      ```
      ---
      name: land-pr-canary
      description: Placeholder skill for the /land-pr end-to-end canary
      ---

      # /land-pr-canary — /land-pr End-to-End Canary (MIRROR — DRIFT)

      Mirror is deliberately out-of-sync so CI's drift step fails on
      first push. The fix agent should mirror the source file using
      `bash scripts/mirror-skill.sh land-pr-canary` (per load-bearing
      decision #10 — never `rm -rf`).
      ```

- [ ] Run `/run-plan plans/CANARY_LAND_PR.md finish auto pr`. Expected
      sequence:

      1. `/run-plan` parses Phase 1 → dispatches implementer agent in a
         worktree at `/tmp/<project>-pr-canary-land-pr`.
      2. Implementer creates the two files, commits them (drift present).
      3. `/run-plan` runs verifier; verifier passes locally (no drift
         check in `tests/run-all.sh`).
      4. `/run-plan` reaches Phase 6 PR mode → constructs PR title +
         body (with `<!-- run-plan:progress:start --> ... <!--
         run-plan:progress:end -->` markers) → writes body to temp file
         → invokes `/land-pr` via the Skill tool with `--branch=...
         --base=main --body-file=... --pr-title=... --auto`.
      5. **Iteration 1 of caller loop:**
         - `/land-pr` runs `pr-rebase.sh` (clean — no upstream changes).
         - `pr-push-and-create.sh` pushes branch + creates PR via
           `gh pr create` (the ONLY remaining live invocation outside
           prose, per WI 6.1 cross-skill tripwire).
         - `pr-monitor.sh` polls CI via `timeout <T> gh pr checks <PR>
           --watch` then bare re-check (per fix 87af82a).
         - CI fails on the drift step (`.github/workflows/test.yml`
           catches `skills/land-pr-canary/SKILL.md != .claude/skills/
           land-pr-canary/SKILL.md`).
         - `/land-pr` writes result file with `STATUS=ci-failing`,
           `PR_URL=...`, `PR_NUMBER=...`, `CI_STATUS=fail`,
           `CI_LOG_FILE=/tmp/land-pr-ci-log-...`,
           `MERGE_REQUESTED=false`.
      6. `/run-plan`'s caller loop parses the result file via the
         allow-list parser (key set: `STATUS|PR_URL|PR_NUMBER|
         CI_STATUS|CI_LOG_FILE|MERGE_REQUESTED|...`). NEVER `source`s
         the file (verified by `check_not land-pr "no source-based
         result parsing in caller pattern"` already in conformance).
      7. `/run-plan` reads `$CI_LOG_FILE`, dispatches a fix-cycle agent
         at orchestrator level (NOT inside the caller loop's Agent
         block — verified by WI 6.1 cross-skill orchestrator-dispatch
         heuristic).
      8. Fix agent reads `gh run view --log-failed`, sees the drift
         message, runs `bash scripts/mirror-skill.sh land-pr-canary`
         (or copies source over mirror), commits, pushes.
      9. **Iteration 2 of caller loop:**
         - `/run-plan` re-dispatches `/land-pr` with the same args.
         - `pr-rebase.sh` is idempotent (clean).
         - `pr-push-and-create.sh` finds existing PR (no recreate).
         - `pr-monitor.sh` re-polls; CI passes.
         - `pr-merge.sh` requests `gh pr merge --auto --squash`. PR
           is auto-mergeable; merge fires (or queues, then completes).
         - `/land-pr` writes result file with `STATUS=landed`,
           `PR_STATE=MERGED`, `CI_STATUS=pass`,
           `MERGE_REQUESTED=true`.
      10. `/run-plan`'s caller loop exits successfully (1 fix-cycle
          iteration + 1 success iteration = 2 total).
      11. `/run-plan` writes `.landed` via `commit/scripts/write-landed.sh`,
          runs `post-run-invariants.sh`, cleans up worktree.

- [ ] Verify final state:

      ```bash
      # PR merged
      gh pr view <PR_NUMBER> --json state,mergeCommit | head

      # .landed marker present and well-formed
      cat plans/canary-land-pr/.landed   # or wherever /run-plan placed it

      # Source/mirror parity
      diff -q skills/land-pr-canary/SKILL.md .claude/skills/land-pr-canary/SKILL.md

      # Conformance still green (WI 6.1 tripwires haven't regressed)
      bash tests/test-skill-conformance.sh | grep -E "(cross-skill|Results:)"

      # Post-run invariants
      bash .claude/skills/run-plan/scripts/post-run-invariants.sh
      ```

      All five commands must succeed (PR `MERGED`, `.landed`
      `status: landed`, `diff -q` silent, conformance 0 failures,
      invariants exit 0).

- [ ] Cleanup (after successful run):

      ```bash
      # Remove canary skill from main (next commit)
      bash scripts/mirror-skill.sh land-pr-canary --delete   # if helper supports it
      # OR manually:
      rm -rf skills/land-pr-canary .claude/skills/land-pr-canary
      git add -A && git commit -m "Remove /land-pr-canary post-canary"
      git push dev main
      ```

### Failure modes (what to look for if the canary fails)

These are the canary's diagnostic anchors — if `/run-plan` reports a
failure, check these in order:

1. **Caller loop didn't iterate twice** — symptom: `.landed`
   `status: ci-failing` with no fix attempt. Root cause: `/run-plan`'s
   caller loop missing the `STATUS=ci-failing → dispatch fix agent →
   re-iterate` branch. Verify against
   `skills/land-pr/references/caller-loop-pattern.md`.

2. **Result file parsed via `source`** — symptom: shell injection from
   CI stderr or `CALL_ERROR` content; possibly hung shell. Root cause:
   `/run-plan` regressed the allow-list parser. Conformance assertion
   `check_not land-pr "no source-based result parsing in caller
   pattern"` should already catch this; if it didn't, the regex
   needs tightening.

3. **Inline `gh pr create` fired instead of `/land-pr` dispatch** —
   symptom: PR opened but no result file written; `/run-plan` confused.
   Root cause: a regression re-introduced inline PR-landing in
   `/run-plan/modes/pr.md`. WI 6.1 cross-skill tripwire
   `[cross-skill] no inline gh pr create (skills/)` should catch
   this at conformance time before the canary runs; if it didn't,
   the start-of-line anchor regex needs review.

4. **Auto-merge didn't fire** — symptom: `STATUS=pr-ready` after CI
   pass; PR sits unmerged. Root cause: `/land-pr` invoked without
   `--auto`, OR `pr-merge.sh`'s `if [ "$AUTO_FLAG" != "true" ]` guard
   is wrong. Verify `--auto` is in the dispatch args; verify
   `tests/test-land-pr-scripts.sh` covers the auto-merge path.

5. **Mirror drift not fixed** — symptom: fix-cycle iteration ran but CI
   still fails on iteration 2. Root cause: fix agent didn't actually
   resolve the drift; verify the agent ran `mirror-skill.sh` (or an
   equivalent), and verify `git log` shows a new commit on the feature
   branch between iterations 1 and 2.

## Notes for first-runner

- This is a **manual canary** — it requires real GitHub state. The
  user has confirmed they're happy to run this end-to-end manually.
- Keep `gh run watch` open in another terminal during iteration 1 to
  observe CI failure timing — this helps validate `pr-monitor.sh`'s
  timeout behavior.
- If the canary succeeds, mark Phase 1 ✅ Done in the Progress Tracker
  and append a one-line note (date + PR number + iteration count) so
  future runs can verify regression-free behavior.
- `CI_FIX_CYCLE_CANARY.md` (the pre-unification predecessor) remains
  in the canary set as a historical reference; it should NOT be
  re-run — its inline implementation is gone.
