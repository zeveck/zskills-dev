# PR #70 Batch — Execution Order Guide

This is the recommended order for running every plan, queued `/quickfix`, and open issue committed in [PR #70](https://github.com/zeveck/zskills-dev/pull/70) plus issues [#56](https://github.com/zeveck/zskills-dev/issues/56), [#58](https://github.com/zeveck/zskills-dev/issues/58), and [#65](https://github.com/zeveck/zskills-dev/issues/65).

Order matters because several items churn the same files (`skills/update-zskills/SKILL.md`, `dev_server.default_port` schema, the `update-zskills` mirror). Two `/refine-plan` reconciliations are required mid-stream — the rest reduces to staleness gates inside the plans themselves.

---

## Drift log

- **2026-04-27 (early)** — Issue #58 (`main_protected` push-guard regex false-positive) was already closed by [PR #73](https://github.com/zeveck/zskills-dev/pull/73) merged the same day this guide was written. The fix segment-scopes rules (a) and (b) to the `git push` portion of `$COMMAND` (`hooks/block-unsafe-project.sh.template:639-655`) and adds 9 regression tests in `tests/test-hooks.sh`. **Step removed from Phase A**; subsequent steps renumbered.
- **2026-04-27 (mid)** — Issue #56 closed by [PR #74](https://github.com/zeveck/zskills-dev/pull/74) merged. Phase A item 1 marked complete.
- **2026-04-27 (late)** — A drift across 5 PR-creating skills (`/run-plan`, `/commit pr`, `/do pr`, `/fix-issues pr`, `/quickfix`) was surfaced during the `/fix-issues 56 + 58` sprint: each skill duplicates the canonical `gh pr create` + CI poll + fix cycle + auto-merge pattern, with inconsistent gating and one skill (`/quickfix`) opting out entirely. [PR #75](https://github.com/zeveck/zskills-dev/pull/75) (merged 2026-04-27 22:51, commit `82ee65f`) fixes the `/fix-issues` half — interactive PR-mode now runs the full pipeline except the final `gh pr merge`, matching `/run-plan`, `/commit pr`, and `/do pr`. The broader unification was explicitly deferred by PR #75 as out-of-scope ("future `/draft-plan` candidate").
- **2026-04-27 (later)** — `plans/PR_LANDING_UNIFICATION.md` drafted on branch `plans/pr-landing-unification` (worktree `/tmp/zskills-worktrees/pr-landing-unification`). 912 lines, 7 phases (1A foundation → 1B validation → 2 `/run-plan` → 3 `/commit pr`+`/do pr` → 4 `/fix-issues pr` → 5 `/quickfix` → 6 conformance), produced via `/draft-plan rounds 3` + `/refine-plan` YAGNI pass. Creates a new `/land-pr` skill that the 5 callers dispatch via the Skill tool. Branch is based on `47e8344` (pre-PR #75); needs rebase onto main before landing. Phase F entry below moves from "needs draft" to "needs merge".

---

## TL;DR — execution checklist

Status legend: `[x]` complete · `[ ]` pending · `[~]` in flight (PR open or plan being drafted)

#### Phase A — pre-flight (fixes the tools the plans use to land)

- [x] `/fix-issues 56` — `/commit` respects `execution.landing` (PR #74, merged 2026-04-27)
- [ ] `/quickfix ← QF1` — slug-namespace `/draft-plan` review files
- [ ] `/quickfix ← QF2` — orchestrator-judgment convergence fix
- [ ] `/quickfix ← QF4` — `/refine-plan` positional-tail guidance
- [ ] `/run-plan plans/IMPROVE_STALENESS_DETECTION.md` *(optional but recommended early)*

#### Phase B — foundation

- [ ] `/run-plan plans/SCRIPTS_INTO_SKILLS_PLAN.md` *(lands first; gates Tier-2)*

#### Phase C — DEFAULT_PORT reconciliation (mandatory /refine-plan)

- [ ] `/refine-plan plans/DEFAULT_PORT_CONFIG.md` *(strip WI 1.1–1.3 — redundant after Phase B)*
- [ ] `/run-plan plans/DEFAULT_PORT_CONFIG.md` *(now: backfill = WI 1.4 only)*

#### Phase D — Tier-2 plans (run sequentially to reduce mirror churn)

- [ ] `/run-plan plans/CONSUMER_STUB_CALLOUTS_PLAN.md`
- [ ] `/run-plan plans/SKILL_FILE_DRIFT_FIX.md`

#### Phase E — /update-zskills source discovery (must wait for B+C+D)

- [ ] `/quickfix ← QF3` *(explicitly deferred until SCRIPTS_INTO_SKILLS, SKILL_FILE_DRIFT_FIX, DEFAULT_PORT_CONFIG land)*

#### Phase F — independent plans (any order, post-Phase B is safest)

- [ ] `/run-plan plans/BLOCK_DIAGRAM_TRACKING_CATCHUP.md` — closes Issue #65
- [ ] `/run-plan plans/DRAFT_TESTS_SKILL_PLAN.md`
- [ ] `/run-plan plans/QUICKFIX_DO_TRIAGE_PLAN.md`
- [ ] `/run-plan plans/ZSKILLS_MONITOR_PLAN.md`
- [x] `/draft-plan plans/PR_LANDING_UNIFICATION.md` — extract canonical `gh pr create` + CI poll + fix-cycle + auto-merge pattern into a new `/land-pr` skill consumed by all 5 PR-creating skills. Drafted on branch `plans/pr-landing-unification` (2026-04-27).
- [ ] **Rebase + merge** branch `plans/pr-landing-unification` onto main, then `/run-plan plans/PR_LANDING_UNIFICATION.md`. Branch is based on `47e8344` (pre-#75) — rebase first to pick up the PR #75 gating fix that the plan inherits from.

#### Phase G — deferred

- `plans/GITLAB_SUPPORT_DRAFT_PLAN_PROMPTS.md` *(reference; not executable yet)*

---

## Why this order — the load-bearing constraints

### 1. Pre-flight quickfixes & issues come before every plan

These four items all touch the **tooling that plans use to land**: `/commit`, `/draft-plan`, `/refine-plan`. Landing them first means every subsequent `/run-plan`, `/refine-plan`, or `/quickfix` runs against fixed orchestration code instead of carrying the bugs forward.

| Item | Touches | Why first |
|---|---|---|
| Issue #56 | `skills/commit/SKILL.md` (config-read for `execution.landing`) | `/commit` is invoked at the end of every plan landing; today it ignores the `pr` mode the plans assume. |
| QF1 | `skills/draft-plan/SKILL.md:L126` | Concurrent `/draft-plan` runs collide on `/tmp/draft-plan-review-round-N.md`. |
| QF2 | `skills/draft-plan/SKILL.md` + `skills/refine-plan/SKILL.md` (4 sites total) | Convergence is an orchestrator judgment, not the refiner's self-call; the buggy behavior currently rubber-stamps "CONVERGED" mid-loop. |
| QF4 | `skills/refine-plan/SKILL.md` (Arguments + Phase 2) | Adds positional-tail guidance arg so `/refine-plan plans/X.md anti-deferral focus` works. Useful for the Phase C reconciliation below. |

These are mutually independent — order within Phase A doesn't matter — but **all four must land before Phase B** so the Phase-B/C/D plans don't trip them.

(Issue #58 was originally listed here; closed via PR #73 — see Drift log above.)

### 2. SCRIPTS_INTO_SKILLS_PLAN is the foundation gate

Two plans hard-block on it via in-plan staleness gates:

- `CONSUMER_STUB_CALLOUTS_PLAN.md` — Phase 1 staleness gate halts `/run-plan` if `SCRIPTS_INTO_SKILLS_PLAN` status ≠ `complete`.
- `SKILL_FILE_DRIFT_FIX.md` — Phase 0 has the same gate.

A third plan **overlaps** but doesn't gate:

- `DEFAULT_PORT_CONFIG.md` — duplicates `SCRIPTS_INTO_SKILLS Phase 3a` work items 3a.4c.i/ii/iii (schema field, this-repo config, greenfield template). PLAN_INDEX explicitly says: *"reconcile via /refine-plan after one of the two lands."*

Running `SCRIPTS_INTO_SKILLS_PLAN.md` first is the canonical path because it's the more structural change and the two follow-up plans (CONSUMER_STUB_CALLOUTS, SKILL_FILE_DRIFT_FIX) anchor on its Tier-1 layout.

### 3. DEFAULT_PORT_CONFIG needs `/refine-plan` mid-stream

After Phase B lands, `DEFAULT_PORT_CONFIG.md` Phase 1 work items 1.1–1.3 are already done by `SCRIPTS_INTO_SKILLS_PLAN` Phase 3a. The remaining novel work is **WI 1.4 (backfill logic in `/update-zskills` for existing configs)** plus Phases 2–5.

**Mandatory step**: `/refine-plan plans/DEFAULT_PORT_CONFIG.md` between Phase B and Phase C. The refine pass strips WIs 1.1–1.3 as done-elsewhere and validates the surviving backfill scope. Skipping this means `/run-plan` will spend a phase double-writing the schema field and possibly fail acceptance criteria that test for "field added by this plan."

If you'd rather run `DEFAULT_PORT_CONFIG.md` first, the symmetric reconciliation works (`/refine-plan plans/SCRIPTS_INTO_SKILLS_PLAN.md` after) — but `SCRIPTS_INTO_SKILLS_PLAN` is bigger and more structural, so foundation-first is cleaner.

### 4. CONSUMER_STUB_CALLOUTS and SKILL_FILE_DRIFT_FIX should run sequentially, not in parallel

Both Tier-2 plans add files to `.claude/skills/update-zskills/`:

- `CONSUMER_STUB_CALLOUTS` adds `zskills-stub-lib.sh`.
- `SKILL_FILE_DRIFT_FIX` adds `zskills-resolve-config.sh`.

Both use `rm -rf .claude/skills/update-zskills && cp -a skills/update-zskills/ ...` discipline. Running them in parallel risks the second wiping the first's mirror copy. Sequential execution avoids that with no extra coordination.

There's no hard ordering between the two — pick whichever you'd rather land first. CONSUMER_STUB → DRIFT_FIX is the order matching the Tier-2 priority in PLAN_INDEX.

### 5. QF3 is *deferred by design*

`QUEUED_QUICKFIXES.md` Prompt 3 explicitly states:

> queued instead because (a) low urgency — doesn't break installs, just produces silent re-clone when a non-`/tmp` clone exists; (b) `skills/update-zskills/SKILL.md` is going to churn from active plans (DEFAULT_PORT_CONFIG, SCRIPTS_INTO_SKILLS_PLAN, SKILL_FILE_DRIFT_FIX) — running this now would create a refine-after-rebase loop.

Run QF3 only **after Phases B + C + D-DriftFix** complete. It's anchored on the section name and 4-tier probe rather than line numbers, so it survives the file churn.

### 6. Issue #65 → run the existing plan, not `/fix-issues`

`BLOCK_DIAGRAM_TRACKING_CATCHUP.md` (3 phases, in PR #70) was authored specifically for Issue #65. The plan goes beyond a raw fix and adds:

- Phase 1: core marker migration (19 sites in `add-block` + `add-example`).
- Phase 2: lint guard + 2 new canary test cases.
- Phase 3: framework-coverage CI guard preventing recurrence.

**Use `/run-plan plans/BLOCK_DIAGRAM_TRACKING_CATCHUP.md`** — `/fix-issues 65` would land Phase 1 only and skip the enforcement that prevents the issue from re-emerging on the next batch migration.

The plan is fully independent of the Phase B/C/D chain (block-diagram is its own skill family, no shared files), so it can run any time after Phase A. Doing it after Phase B is mildly safer — `IMPROVE_STALENESS_DETECTION` and the canonical-config helpers will already be in place.

### 7. Independent plans in Phase F

These four plans share no files, no schema fields, and no skill mirrors with each other or with Phase B–E:

- `BLOCK_DIAGRAM_TRACKING_CATCHUP.md` — block-diagram only.
- `DRAFT_TESTS_SKILL_PLAN.md` — new `skills/draft-tests/` skill.
- `QUICKFIX_DO_TRIAGE_PLAN.md` — `skills/quickfix/` + `skills/do/` triage gates.
- `ZSKILLS_MONITOR_PLAN.md` — new `/zskills-dashboard` + `/work-on-plans` skills, adds its own config block.

Run in any order. Two soft considerations:

- **Run after QF2 lands** (which it already has by Phase A). DRAFT_TESTS and QUICKFIX_DO_TRIAGE both reference adversarial-review patterns; if either was authored against the old "refiner self-declares" model, consider an optional `/refine-plan` first. Not strictly required — the convergence behavior change is a mechanical fix that doesn't invalidate plan content.
- **ZSKILLS_MONITOR_PLAN refresh is in PR #70** (`/zskills-monitor` → `/zskills-dashboard`). Run it as-is.

### 8. GITLAB_SUPPORT_DRAFT_PLAN_PROMPTS — defer indefinitely

PLAN_INDEX flags it as `Reference (deferred)`. It's planning prompts for *future* work, not an executable plan. Hard prerequisites: `SCRIPTS_INTO_SKILLS_PLAN`, `SKILL_FILE_DRIFT_FIX`, `CONSUMER_STUB_CALLOUTS_PLAN` all complete + a real GitLab project to test against. Don't `/run-plan` this; revisit when both conditions are met.

---

## Refine-plan checklist

Required:

- [ ] `/refine-plan plans/DEFAULT_PORT_CONFIG.md` — between Phase B and Phase C. Mandatory; the plan duplicates work that Phase B will already have done.

Optional / consider:

- [ ] `/refine-plan plans/DRAFT_TESTS_SKILL_PLAN.md` — only if you suspect the adversarial-review wording in the plan was authored against the pre-QF2 convergence model.
- [ ] `/refine-plan plans/QUICKFIX_DO_TRIAGE_PLAN.md` — same caveat.

Not needed:

- `BLOCK_DIAGRAM_TRACKING_CATCHUP.md`, `ZSKILLS_MONITOR_PLAN.md`, `IMPROVE_STALENESS_DETECTION.md`, `CONSUMER_STUB_CALLOUTS_PLAN.md`, `SKILL_FILE_DRIFT_FIX.md`, `SCRIPTS_INTO_SKILLS_PLAN.md` — all freshly authored or refreshed in PR #70 against current state; no stale assumptions to refine.

---

## Conflict matrix (load-bearing files only)

| File / surface | Touched by |
|---|---|
| `skills/commit/SKILL.md` | Issue #56 |
| `skills/draft-plan/SKILL.md` | QF1, QF2 |
| `skills/refine-plan/SKILL.md` | QF2, QF4 |
| `skills/update-zskills/SKILL.md` | SCRIPTS_INTO_SKILLS_PLAN, SKILL_FILE_DRIFT_FIX, DEFAULT_PORT_CONFIG, CONSUMER_STUB_CALLOUTS_PLAN, QF3 |
| `.claude/skills/update-zskills/` (mirror) | CONSUMER_STUB_CALLOUTS_PLAN, SKILL_FILE_DRIFT_FIX (run sequentially) |
| `.claude/zskills-config.json` schema → `dev_server.default_port` | SCRIPTS_INTO_SKILLS_PLAN Phase 3a, DEFAULT_PORT_CONFIG Phase 1 (overlap → refine) |
| `block-diagram/add-block/SKILL.md` + `add-example/SKILL.md` | BLOCK_DIAGRAM_TRACKING_CATCHUP.md (Issue #65) — isolated |
| `skills/draft-tests/` (new) | DRAFT_TESTS_SKILL_PLAN.md — isolated |
| `skills/quickfix/` + `skills/do/` | QUICKFIX_DO_TRIAGE_PLAN.md — isolated |
| `/zskills-dashboard` + `/work-on-plans` (new) | ZSKILLS_MONITOR_PLAN.md — isolated |

---

## Source documents

- PR #70: <https://github.com/zeveck/zskills-dev/pull/70>
- Issues: ~~[#56](https://github.com/zeveck/zskills-dev/issues/56)~~ (closed by PR #74) · ~~[#58](https://github.com/zeveck/zskills-dev/issues/58)~~ (closed by PR #73) · [#65](https://github.com/zeveck/zskills-dev/issues/65)
- [PR #75](https://github.com/zeveck/zskills-dev/pull/75) — `/fix-issues` PR-mode gating fix, merged 2026-04-27
- `QUEUED_QUICKFIXES.md` (repo root) — full prompts for QF1–QF4
- `plans/PLAN_INDEX.md` — auto-generated dependency notes
