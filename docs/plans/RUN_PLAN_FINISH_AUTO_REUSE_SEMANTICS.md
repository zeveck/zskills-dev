---
issue: 191
title: /run-plan finish — cherry-pick mode reuses plan-scoped worktree
created: 2026-05-11
status: complete
---

# Plan: /run-plan finish — cherry-pick mode reuses plan-scoped worktree

> **Landing mode: PR** — This plan targets PR-based landing. All phases use worktree isolation with a named feature branch.

## Overview

Issue [#191](https://github.com/zeveck/zskills-dev/issues/191) reports that `/run-plan finish auto` is wasteful in cherry-pick mode: it creates a new worktree per phase and lands each phase to main individually. The user's expectation — confirmed via session discussion — is that cherry-pick mode in `finish` / `finish auto` invocations should match PR mode: **one plan-scoped worktree shared across all phases, accumulate commits, land once at the end**.

PR mode already implements this correctly (`SKILL.md:1198`: `WORKTREE_PATH="/tmp/${PROJECT_NAME}-pr-${PLAN_SLUG}"` — no phase suffix; one branch per plan; one PR per plan). The bug is isolated to cherry-pick mode + the docs that contradict themselves about which contract is in effect.

**Scope:** change cherry-pick mode's worktree-creation + landing behavior for `finish` and `finish auto` invocations. Leave explicit single-phase invocations (`/run-plan plan.md 3`) untouched — those keep per-phase worktree + per-phase landing.

## Locked decisions

- **D1 — Scope is finish modes only.** `/run-plan plan.md <phase>` (explicit single-phase) continues to use phase-scoped worktree (`-cp-${PLAN_SLUG}-phase-${PHASE}`) and lands that single phase. `/run-plan plan.md finish` and `/run-plan plan.md finish auto` switch to plan-scoped worktree (`-cp-${PLAN_SLUG}` — no phase suffix) and accumulate commits across all phases, landing once after the final phase.
- **D2 — Detection of "is this the final phase"** uses the plan tracker. After implementing the current phase, scan the plan's Progress Tracker. If at least one ⬚ (not-started) row remains, schedule the next cron and do NOT land. If zero ⬚ rows remain, this is the final phase → land all accumulated commits via cherry-pick sequence. Re-use the cherry-pick landing flow that runs today; the only change is gating it on "final phase detected."
- **D3 — Cherry-pick mode in finish modes mirrors PR mode's worktree path shape, with a different prefix.** Cherry-pick: `/tmp/${PROJECT_NAME}-cp-${PLAN_SLUG}` (no `-phase-${PHASE}`). PR: `/tmp/${PROJECT_NAME}-pr-${PLAN_SLUG}` (unchanged). The `--prefix cp` argument to `create-worktree.sh` stays the same; only the slug changes.
- **D4 — Worktree resume detection** uses the same directory-based check PR mode uses today (`SKILL.md:1206-1209`). When a cron-fired turn re-enters the orchestrator, an existing plan-scoped cherry-pick worktree means we resume rather than create. This was implicit in the previous per-phase model because each phase's worktree was unique; in the plan-scoped model the resume detection is essential.
- **D5 — Conformance test 146 changes shape, not deletes.** The current assertion `check_fixed run-plan "cp worktree slug suffix" '"${PLAN_SLUG}-phase-${PHASE}"'` becomes one assertion locking the new finish-mode shape (`"${PLAN_SLUG}"` with no phase suffix) + a separate assertion locking the single-phase-invocation shape (still `"${PLAN_SLUG}-phase-${PHASE}"`). Two assertions instead of one; both fire.
- **D6 — CANARY7 keeps its intent.** CANARY7's purpose is to verify "each plan phase fires as its own top-level cron-fired turn, NOT as two phases looped inside one long session." That intent is orthogonal to per-phase vs per-plan landing. Update its ACs: drop "Phase 1 lands (worktree-mode cherry-pick to main, or PR merge)" from Phase 1 ACs; move the landing assertion to Phase 2's ACs as "after Phase 2, all accumulated commits land via cherry-pick sequence." The chunked-execution regression signal stays intact.
- **D7 — finish-mode.md:94-97** ("User Verify items in chunked mode... Per-phase landing IS the chunked model — do NOT hold landing until all phases complete") is rewritten to match the new contract: "In finish/finish-auto mode, landing happens once after the final phase. User Verify items accumulate across phases and are presented in the final-phase completion message before landing."
- **D8 — modes/cherry-pick.md:65** ("In `finish` mode: all phases share one worktree.") is already correct under the new contract — no change. The previously-aspirational sentence becomes accurate.
- **D9 — modes/pr.md misleading comments** (line 298: `$WORKTREE_PATH = the per-phase PR-mode worktree`; line 301: `$BRANCH_NAME = the per-phase or per-plan feature branch`) are clarified to describe the actual plan-scoped reality. This is a small in-scope cleanup since the wording was specifically called out as the source of the Codex runner's misreading.
- **D10 — No new env var, no new schema field, no new helper script.** The change is in the cherry-pick block at SKILL.md:972-989 + the cherry-pick landing flow in modes/cherry-pick.md + the conformance test + CANARY7. Detection of finish-mode-or-not uses the existing `$FINISH_MODE` variable that the rest of run-plan already reads.
- **D11 — Mirror discipline.** `bash scripts/mirror-skill.sh run-plan`. `metadata.version` bumps once.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Cherry-pick worktree-creation gating on finish mode | ✅ | `1ec786b` | AC1.6 plan-drift logged (see report) |
| 2 — Cherry-pick landing-flow gating on final-phase + finish-mode.md/cherry-pick.md prose updates | ✅ | `bb0319d` | |
| 3 — Conformance test + CANARY7 + modes/pr.md comment cleanup | ✅ | `bf984db` | Conformance 358→359 (+1 from slug-shape split); CANARY7 ACs updated |

## Phase 1 — Cherry-pick worktree-creation gating on finish mode

### Goal

Change cherry-pick mode's worktree-creation block (`SKILL.md:972-989`) so finish/finish-auto invocations use a plan-scoped slug (`${PLAN_SLUG}`) and explicit single-phase invocations continue to use the phase-scoped slug (`${PLAN_SLUG}-phase-${PHASE}`). Add resume detection symmetric to PR mode's at SKILL.md:1206-1209.

### Work Items

- [ ] **WI 1.1 — Read SKILL.md around line 972-989 in full** and identify the existing `$FINISH_MODE` variable (set elsewhere in run-plan's argument parsing). Confirm the variable's values are something like `"finish"` / `"finish-auto"` / empty-or-other; quote the actual literal values from the source. (Read SKILL.md `FINISH_MODE=` to find the assignment site before specifying the conditional.)
- [ ] **WI 1.2 — Rewrite the cherry-pick worktree-creation block** at SKILL.md:972-989 to gate on finish-mode. New shape:
  ```bash
  PLAN_SLUG=$(basename "$PLAN_FILE" .md | tr '[:upper:]' '[:lower:]' | tr '_' '-')
  PROJECT_NAME=$(basename "$PROJECT_ROOT")
  
  # In finish/finish-auto modes, use one plan-scoped worktree shared
  # across all phases (Issue #191). In explicit single-phase invocations,
  # use a phase-scoped worktree.
  if [ "$FINISH_MODE" = "finish" ] || [ "$FINISH_MODE" = "finish-auto" ]; then
    CP_WORKTREE_PATH="/tmp/${PROJECT_NAME}-cp-${PLAN_SLUG}"
    CP_SLUG="${PLAN_SLUG}"
  else
    CP_WORKTREE_PATH="/tmp/${PROJECT_NAME}-cp-${PLAN_SLUG}-phase-${PHASE}"
    CP_SLUG="${PLAN_SLUG}-phase-${PHASE}"
  fi
  
  # Resume detection: directory-based, symmetric to PR mode's check at
  # SKILL.md:1206-1209. An existing plan-scoped cherry-pick worktree
  # means we're resuming the same plan across cron turns.
  if [ -d "$CP_WORKTREE_PATH" ]; then
    echo "Resuming existing cherry-pick worktree at $CP_WORKTREE_PATH"
    WORKTREE_PATH="$CP_WORKTREE_PATH"
  else
    WT=$(bash "$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/create-worktree.sh" \
      --prefix cp \
      --allow-resume \
      --purpose "run-plan cherry-pick; plan=${PLAN_SLUG}; phase=${PHASE}; finish-mode=${FINISH_MODE:-single}" \
      --pipeline-id "run-plan.${TRACKING_ID}" \
      "${CP_SLUG}")
    RC=$?
    if [ "$RC" -ne 0 ]; then
      echo "create-worktree failed (rc=$RC) for cherry-pick mode" >&2
      exit "$RC"
    fi
    WORKTREE_PATH="$WT"
  fi
  ```
  The `--allow-resume` flag is required because in finish modes the same branch (`cp-${PLAN_SLUG}`) is reused across phases. Without `--allow-resume`, create-worktree.sh would refuse to reuse the branch on the second cron-fired turn.
- [ ] **WI 1.3 — Update the explanatory comment at SKILL.md:992-993** that says "Cherry-pick mode: one worktree per phase, auto-named branch, /tmp/ path. After landing (cherry-pick to main), worktree is removed." New text:
  ```markdown
  Cherry-pick mode worktree scope:
  - finish / finish-auto: one plan-scoped worktree shared across phases
    (path `/tmp/${PROJECT_NAME}-cp-${PLAN_SLUG}`, branch
    `cp-${PLAN_SLUG}`). Commits accumulate across phases; landing happens
    once after the final phase (see Phase 2's landing flow). Worktree is
    removed only after the final landing.
  - Single-phase invocations (`/run-plan plan.md <phase>`): one phase-
    scoped worktree (path `/tmp/${PROJECT_NAME}-cp-${PLAN_SLUG}-phase-${PHASE}`,
    branch `cp-${PLAN_SLUG}-phase-${PHASE}`). Lands that one phase.
    Worktree removed after that phase's landing.
  ```
- [ ] **WI 1.4 — Bump `metadata.version` on SKILL.md** to today's date + new content hash.
- [ ] **WI 1.5 — Mirror.** `bash scripts/mirror-skill.sh run-plan`. `diff -rq` empty.
- [ ] **WI 1.6 — Run the test suite.** `bash tests/run-all.sh` — Phase 1 alone breaks conformance test 146 (it expects the OLD per-phase shape). Document the expected failure count; Phase 3 unwinds it.
- [ ] **WI 1.7 — Single commit.** Phase 1 lands as one commit.

### Acceptance Criteria

- [ ] AC1.1 — `grep -nE 'FINISH_MODE.*finish|CP_WORKTREE_PATH' skills/run-plan/SKILL.md` returns hits in the cherry-pick worktree-creation region.
- [ ] AC1.2 — `grep -F '/tmp/${PROJECT_NAME}-cp-${PLAN_SLUG}-phase-${PHASE}' skills/run-plan/SKILL.md` still returns at least one hit (the single-phase path, in the else branch).
- [ ] AC1.3 — `grep -F '/tmp/${PROJECT_NAME}-cp-${PLAN_SLUG}"' skills/run-plan/SKILL.md` returns at least one hit (the finish-mode path, no phase suffix).
- [ ] AC1.4 — `diff -rq skills/run-plan .claude/skills/run-plan` empty.
- [ ] AC1.5 — `bash scripts/skill-version-stage-check.sh` exits 0.
- [ ] AC1.6 — `bash tests/run-all.sh` reports exactly 1 conformance failure (the old `cp worktree slug suffix` check). This is intentional and unwound in Phase 3.
- [ ] AC1.7 — Single commit.

### Dependencies

None.

## Phase 2 — Cherry-pick landing-flow gating on final-phase + prose updates

### Goal

Change the cherry-pick landing flow so finish/finish-auto invocations accumulate commits and land once after the final phase. Update `finish-mode.md:94-97` to invert the per-phase-landing prose. `modes/cherry-pick.md:65` already correctly says "all phases share one worktree" — that becomes accurate by Phase 1.

### Work Items

- [ ] **WI 2.1 — Identify the cherry-pick landing call site** in `skills/run-plan/SKILL.md` (or wherever the cherry-pick land flow is invoked from Phase 6). Find by grep: `grep -nE 'modes/cherry-pick|cherry-pick.*land' skills/run-plan/SKILL.md`. The change is: in finish/finish-auto modes, only invoke the landing flow when the plan's Progress Tracker has zero remaining ⬚ rows. In single-phase mode, invoke as today.
- [ ] **WI 2.2 — Add a final-phase detection helper inline** (no new helper script — keep it as bash in SKILL.md). Reuse the plan-tracker parsing primitives that already exist (look for `Phase.*Status` table parsing already done elsewhere in SKILL.md). The check: count rows where Status column is `⬚`. If zero remaining, this is the final phase.
- [ ] **WI 2.3 — Gate the cherry-pick landing block** on `[ "$FINISH_MODE" != "finish" ] && [ "$FINISH_MODE" != "finish-auto" ] || [ "$REMAINING_PHASES" -eq 0 ]`. Single-phase mode lands as before; finish modes land only when no phases remain.
- [ ] **WI 2.4 — Rewrite `skills/run-plan/references/finish-mode.md:92-97`** (the "User Verify items in chunked mode" subsection). New text:
  ```markdown
  ### User Verify items in chunked mode

  In chunked `finish` / `finish auto` modes (cherry-pick AND PR mode),
  landing happens ONCE after the final phase. Per-phase landing is NOT
  the chunked model — it was the previous cherry-pick behavior fixed by
  Issue #191.

  If individual phases have User Verify items, accumulate them across
  phases. In the FINAL phase's completion message, output the accumulated
  User Verify items from all phases together, then land once after the
  user has reviewed all of them.
  ```
- [ ] **WI 2.5 — Verify `modes/cherry-pick.md:65`** matches the new contract. The existing line says "In `finish` mode: all phases share one worktree. Do NOT land individual phases as they complete — wait until ALL phases are done, then land everything together." This is now accurate; no change needed beyond verifying the line.
- [ ] **WI 2.6 — Update `modes/pr.md:298` and :301 misleading comments** (the source of the Codex runner's misreading):
  - Line 298: `#   $WORKTREE_PATH = the per-phase PR-mode worktree` → `#   $WORKTREE_PATH = the plan-scoped PR-mode worktree (one per plan, reused across all phases in finish/finish-auto modes; see Issue #191)`
  - Line 301: `#   $BRANCH_NAME   = the per-phase or per-plan feature branch` → `#   $BRANCH_NAME   = the plan-scoped feature branch (one per plan; phase number does NOT appear in branch name)`
- [ ] **WI 2.7 — Bump `metadata.version`** on SKILL.md (cumulative with Phase 1's bump; only one bump per commit, so this commit also bumps).
- [ ] **WI 2.8 — Mirror + run suite.** `bash scripts/mirror-skill.sh run-plan` + `bash tests/run-all.sh`. After Phase 2, conformance test 146 still fails (Phase 3 unwinds it). No new failures.
- [ ] **WI 2.9 — Single commit for Phase 2.**

### Acceptance Criteria

- [ ] AC2.1 — `grep -F 'REMAINING_PHASES' skills/run-plan/SKILL.md` returns at least one hit (the final-phase detection).
- [ ] AC2.2 — `grep -F 'Per-phase landing is NOT the chunked model' skills/run-plan/references/finish-mode.md` returns 1 hit (the inverted prose).
- [ ] AC2.3 — `grep -F 'the plan-scoped PR-mode worktree' skills/run-plan/modes/pr.md` returns 1 hit (replacement of the misleading comment).
- [ ] AC2.4 — `grep -F 'per-phase PR-mode worktree' skills/run-plan/modes/pr.md` returns 0 hits (the old misleading wording is gone).
- [ ] AC2.5 — `diff -rq skills/run-plan .claude/skills/run-plan` empty.
- [ ] AC2.6 — `bash scripts/skill-version-stage-check.sh` exits 0.
- [ ] AC2.7 — `bash tests/run-all.sh` failure count = Phase 1 commit-time failure count (no regressions; conformance test 146 still expected to fail until Phase 3).
- [ ] AC2.8 — Single commit.

### Dependencies

Phase 1.

## Phase 3 — Conformance test + CANARY7 + tests for the new contract

### Goal

Update conformance test 146 to the new shape. Update CANARY7's ACs to reflect "land once after Phase 2." Add new tests if needed to lock the finish-mode-uses-plan-scoped-worktree contract.

### Work Items

- [ ] **WI 3.1 — Update `tests/test-skill-conformance.sh:146`** from:
  ```bash
  check_fixed run-plan "cp worktree slug suffix"      '"${PLAN_SLUG}-phase-${PHASE}"'
  ```
  to two assertions:
  ```bash
  check_fixed run-plan "cp worktree slug (single-phase)" '"${PLAN_SLUG}-phase-${PHASE}"'
  check_fixed run-plan "cp worktree slug (finish-mode)"  '"${PLAN_SLUG}"'
  ```
  Both should fire on the new SKILL.md (Phase 1's edits put both literals in the source).
- [ ] **WI 3.2 — Update CANARY7's Phase 1 AC** to remove "Phase 1 lands (worktree-mode cherry-pick to main, or PR merge)" — that's no longer the contract for finish-mode runs. New Phase 1 AC: "Phase 1 commit exists in the shared cherry-pick worktree on branch `cp-canary7-chunked-finish`."
- [ ] **WI 3.3 — Update CANARY7's Phase 2 AC** to add: "After Phase 2 completes, all accumulated commits (Phase 1 + Phase 2) land via single cherry-pick sequence to main. Plan frontmatter status is set to `complete`."
- [ ] **WI 3.4 — Run the test suite.** `bash tests/run-all.sh` should now pass at pre-Phase-1 baseline + the 1 new conformance assertion (the second slug-shape check). The expected conformance failure from Phase 1/2 is now resolved.
- [ ] **WI 3.5 — Update Drift Log on docs/plans/ADAPTIVE_CRON_BACKOFF.md** if the changes touch its tracker-row count. Probably not needed — ADAPTIVE_CRON_BACKOFF is `status: complete` and immutable. Skip unless verification shows otherwise.
- [ ] **WI 3.6 — Single commit for Phase 3.**

### Acceptance Criteria

- [ ] AC3.1 — `grep -F 'cp worktree slug (single-phase)' tests/test-skill-conformance.sh` returns 1 hit.
- [ ] AC3.2 — `grep -F 'cp worktree slug (finish-mode)' tests/test-skill-conformance.sh` returns 1 hit.
- [ ] AC3.3 — `bash tests/test-skill-conformance.sh` exits 0 (all assertions pass).
- [ ] AC3.4 — `bash tests/run-all.sh` failure count = 0 (Phase 1's intentional regression is unwound).
- [ ] AC3.5 — CANARY7's Phase 1 AC no longer references "Phase 1 lands"; the landing assertion is in Phase 2's ACs.
- [ ] AC3.6 — Single commit.

### Dependencies

Phases 1 + 2.

## Cross-cutting concerns

### Skill-versioning discipline

`skills/run-plan/SKILL.md` is touched in Phase 1 and Phase 2. `metadata.version` bumps once per commit. Phase 3 only edits `tests/` and `docs/plans/CANARY7_CHUNKED_FINISH.md` — outside the skill's content-hash surface; no additional bump.

### Verifier subagent + Layer 0/Layer 3 protocol

Per Plan A. All three phases verified by `subagent_type: "verifier"` + `verify-response-validate.sh`.

### Coordination with sibling work

- **PR #221** (#212 — extract PR-body sync helper). Independent; no file overlap. Likely lands before this plan.
- **PR #222** (#215+#216). Touches `skills/plans/` + `skills/draft-plan/` + `skills/research-and-plan/` — independent from this plan's `/run-plan` scope.
- **CANARY7** is referenced in the existing tests/conformance; the Phase 3 update is the only modification.

### Manual verification

CANARY7 with the new contract is the runtime regression detector. To manually verify after this plan lands, run:
```
/run-plan docs/plans/CANARY7_CHUNKED_FINISH.md finish auto
```
Expected behavior: each phase fires as its own cron-fired turn (CANARY7's original purpose); commits accumulate in `/tmp/zskills-cp-canary7-chunked-finish` across both phases; landing happens once after Phase 2 completes; main repo's `canary/canary7.txt` shows both lines after the single cherry-pick.

## Plan Quality

**Drafting process:** /draft-plan with orchestrator-direct verification (extensive session-discussion clarified scope; formal Round 1 adversarial review available on request).
**Convergence:** Scope confirmed with user before drafting. Each load-bearing anchor (SKILL.md:972-989, SKILL.md:1198, finish-mode.md:94-97, conformance test 146, CANARY7 ACs) was verified by direct read before being cited in this plan.
**Remaining concerns:** None substantive; ready for /run-plan execution or formal adversarial review if desired.

### Round History

| Phase of drafting | Outcome |
|-------------------|---------|
| Initial draft (this session, earlier) | Drafted with wrong premise — assumed PR mode was per-phase. Two reviewer + DA rounds caught this. |
| User clarification | Distinguished PR mode (correct: plan-scoped) from cherry-pick mode (incorrect: per-phase). |
| Re-draft (this file) | Scope: cherry-pick mode only, finish/finish-auto only. Plan-scoped worktree, accumulate commits, land at final phase. Misleading pr.md comments cleaned up as in-scope side fix. |
