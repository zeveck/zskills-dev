# PR #70 Batch — Execution Order Guide

This is the recommended order for running every plan, queued `/quickfix`, and open issue committed in [PR #70](https://github.com/zeveck/zskills-dev/pull/70) plus issues [#56](https://github.com/zeveck/zskills-dev/issues/56), [#58](https://github.com/zeveck/zskills-dev/issues/58), and [#65](https://github.com/zeveck/zskills-dev/issues/65).

Order matters because several items churn the same files (`skills/update-zskills/SKILL.md`, `dev_server.default_port` schema, the `update-zskills` mirror). Two `/refine-plan` reconciliations are required mid-stream — the rest reduces to staleness gates inside the plans themselves.

---

## Drift log

- **2026-04-27 (early)** — Issue #58 (`main_protected` push-guard regex false-positive) was already closed by [PR #73](https://github.com/zeveck/zskills-dev/pull/73) merged the same day this guide was written. The fix segment-scopes rules (a) and (b) to the `git push` portion of `$COMMAND` (`hooks/block-unsafe-project.sh.template:639-655`) and adds 9 regression tests in `tests/test-hooks.sh`. **Step removed from Phase A**; subsequent steps renumbered.
- **2026-04-27 (mid)** — Issue #56 closed by [PR #74](https://github.com/zeveck/zskills-dev/pull/74) merged. Phase A item 1 marked complete.
- **2026-04-27 (late)** — A drift across 5 PR-creating skills (`/run-plan`, `/commit pr`, `/do pr`, `/fix-issues pr`, `/quickfix`) was surfaced during the `/fix-issues 56 + 58` sprint: each skill duplicates the canonical `gh pr create` + CI poll + fix cycle + auto-merge pattern, with inconsistent gating and one skill (`/quickfix`) opting out entirely. [PR #75](https://github.com/zeveck/zskills-dev/pull/75) (merged 2026-04-27 22:51, commit `82ee65f`) fixes the `/fix-issues` half — interactive PR-mode now runs the full pipeline except the final `gh pr merge`, matching `/run-plan`, `/commit pr`, and `/do pr`. The broader unification was explicitly deferred by PR #75 as out-of-scope ("future `/draft-plan` candidate").
- **2026-04-27 (later)** — `plans/PR_LANDING_UNIFICATION.md` drafted on branch `plans/pr-landing-unification` (worktree `/tmp/zskills-worktrees/pr-landing-unification`). 912 lines, 7 phases (1A foundation → 1B validation → 2 `/run-plan` → 3 `/commit pr`+`/do pr` → 4 `/fix-issues pr` → 5 `/quickfix` → 6 conformance), produced via `/draft-plan rounds 3` + `/refine-plan` YAGNI pass. Creates a new `/land-pr` skill that the 5 callers dispatch via the Skill tool. Branch is based on `47e8344` (pre-PR #75); needs rebase onto main before landing. Phase F entry below moves from "needs draft" to "needs merge".
- **2026-04-28** — Session-of-2026-04-28 PRs merged: PR #76 (no-Haiku CLAUDE.md rule), PR #77 (PR_LANDING_UNIFICATION plan onto main → executable now), PR #78 (QUEUED_QUICKFIXES QF2 + QF4 revised per Opus re-review — when you run those quickfixes, copy from the revised file), PR #79 (QF1 done), PR #80 (`/quickfix` now returns user to base branch on success — fixes a session-friction gap that surfaced during the QF1 run). [Issue #81](https://github.com/zeveck/zskills-dev/issues/81) filed: `main_protected` push-guard rule (c) false-positives on literal `git push` substrings (e.g. inside grep args) — non-blocking but worth picking up alongside the QF2/QF4 runs.
- **2026-04-28 (late)** — Session-end status: Phase A pre-flight is **fully complete**. PR #82 (QF2 — orchestrator-judgment convergence fix), PR #85 (QF4 — `/refine-plan` positional-tail guidance + spaces fix), PR #86 (Issue #83 — `/research-and-plan` Step 3 orchestrator-judgment), PR #87 (Issue #81 — push-guard rule (c) + outer-regex EOL fix), PR #88 (Issue #84 — `scripts/mirror-skill.sh` helper). Three new follow-up issues filed and resolved in-session: Issue #83 (closed by PR #86), Issue #84 (closed by PR #88). Issue #81 closed by PR #87. **Open issues remaining: #65 (block-diagram tracking — addressed by `BLOCK_DIAGRAM_TRACKING_CATCHUP.md` plan in Phase F) and #67 (GitLab support — explicitly deferred).** **/refine-plan triggers added inline** to Phase D and Phase F entries (previously missing from the execution checklist; pre-run hygiene to absorb drift from prior-phase landings).
- **2026-04-28 (later)** — `IMPROVE_STALENESS_DETECTION.md` landed via chunked `finish auto` PR mode: PR #90 (Phase 1: `PLAN-TEXT-DRIFT:` token + `scripts/plan-drift-correct.sh`, 34 cases), PR #91 (Phase 2: `## Phase 3.5` post-implement auto-correct gate, +5 cases), PR #92 (Phase 3: pre-dispatch arithmetic gate sub-checks `a`/`b` + `--eval` token-walking parser with injection canary, +29 cases). Plan frontmatter `status: complete`. 863 → 931 tests passing (+68 plan-drift cases total). The defense-in-depth chain is now complete: `/refine-plan` Dimension 7 (pre-authoring) + Phase 1 step 6 b (pre-dispatch) + Phase 3.5 (post-implement). All 3 layers share the `PLAN-TEXT-DRIFT:` vocabulary and the `plan-drift-correct.sh` helper. Phase A of ROG: every item now `[x]`.
- **2026-04-28 (latest)** — `SCRIPTS_INTO_SKILLS_PLAN.md` (Phase B foundation) landed via chunked `finish auto` PR mode after `/refine-plan` (PR #94 absorbed since-draft drift: `mirror-skill.sh` + `plan-drift-correct.sh` registry entries, hook-blocked `rm -rf .claude/skills/X` recipes replaced with `bash scripts/mirror-skill.sh`, `git rev-parse <commit>:<wildcard-path>` rewrite). Then 6 PRs: #95 (Phase 1: dead-ref cleanup + `script-ownership.md` registry, 14 Tier-1 + 4 Tier-2), #96 (Phase 2: 7 single-owner Tier-1 scripts moved into owning skills), #97 (Phase 3a+3b combined: 7 shared Tier-1 scripts moved + cross-skill caller sweep across 13 skills + hooks + 6 tests + docs + port.sh PROJECT_ROOT bug fix + DEFAULT_PORT_CONFIG Phase 1 inline schema/this-repo-config/template), #98 (Phase 4: `/update-zskills` Step D rewrite + Step D.5 stale-Tier-1 migration via 26-hash known-shipped fixture + CRLF-normalizing hash compare + `command -v git` pre-flight + `port_script` strip; +12 migration tests), #99 (Phase 5: residual sweep + `port_script` schema field removal), #100 (Phase 6: CHANGELOG + RELEASING.md migration note + PLAN_INDEX move + frontmatter flip). Plan frontmatter `status: complete; completed: 2026-04-28`. 931 → 943 tests. **Phase B of ROG complete; DEFAULT_PORT_CONFIG Phase 1 was reconciled inline and is no longer needed as a separate plan**. ROG Phase C's `/refine-plan plans/DEFAULT_PORT_CONFIG.md` step still applies — refine should detect the inline-landed work and strip those WIs.
- **2026-04-29** — `ZSKILLS_MONITOR_PLAN.md` landed via PR-mode chunked `finish auto`. Refine via PR #101 (2026-04-28; +685/-247 absorbing post-PR-#100 SCRIPTS_INTO_SKILLS drift). Then 9 phase PRs: #102 (Phase 1: `/work-on-plans` execute-only CLI, 943→943 + new skill 677 lines), #104 (Phase 2: retire `/plans work` modes), #107 (Phase 3: queue mutation + scheduling subcommands; SKILL 677→1249, +28 tests), #108 (Phase 4: 1277-line `collect.py` data aggregator; +29 tests), #111 (Phase 5: HTTP server with security contract; +53 tests), #113 (Phase 6: read-only dashboard UI; +45 tests, 1111/1111), #115 (Phase 7: drag-drop + write-back; +47 tests, 1158/1158), #116 (Phase 8: `/zskills-dashboard` skill with cmd+cwd identity check; +35 tests, 1193/1193), #117 (Phase 9: `/plans rebuild` migrated to Python aggregator, no bash fallback; +20 tests, 1213/1213). PR #118 marks plan complete. **Phase F's ZSKILLS_MONITOR_PLAN entry is done; new `/work-on-plans` and `/zskills-dashboard` skills shipped.** Two parallel sessions during this stretch landed `BLOCK_DIAGRAM_TRACKING_CATCHUP.md` (PR #109) and `CONSUMER_STUB_CALLOUTS_PLAN.md` (PR #106).

---

## TL;DR — execution checklist

Status legend: `[x]` complete · `[ ]` pending · `[~]` in flight (PR open or plan being drafted)

#### Phase A — pre-flight (fixes the tools the plans use to land)

- [x] `/fix-issues 56` — `/commit` respects `execution.landing` (PR #74, merged 2026-04-27)
- [x] `/quickfix ← QF1` — slug-namespace `/draft-plan` review files (PR #79, merged 2026-04-28)
- [x] `/quickfix ← QF2` — orchestrator-judgment convergence fix (PR #82, merged 2026-04-28)
- [x] `/quickfix ← QF4` — `/refine-plan` positional-tail guidance + spaces-in-paths fix (PR #85, merged 2026-04-28)
- [x] `/run-plan plans/IMPROVE_STALENESS_DETECTION.md` — landed via PRs #90, #91, #92 (chunked finish auto, 2026-04-28)

#### Phase B — foundation

- [x] `/run-plan plans/SCRIPTS_INTO_SKILLS_PLAN.md` — landed via PRs #94 (refine-plan), #95, #96, #97, #98, #99, #100 (chunked finish auto, 2026-04-28)

#### Phase C — DEFAULT_PORT reconciliation (mandatory /refine-plan)

- [ ] `/refine-plan plans/DEFAULT_PORT_CONFIG.md` *(strip WI 1.1–1.3 — redundant after Phase B)*
- [ ] `/run-plan plans/DEFAULT_PORT_CONFIG.md` *(now: backfill = WI 1.4 only)*

#### Phase D — Tier-2 plans (run sequentially to reduce mirror churn)

- [x] `/refine-plan plans/CONSUMER_STUB_CALLOUTS_PLAN.md` — landed via PR #105 (2026-04-28)
- [x] `/run-plan plans/CONSUMER_STUB_CALLOUTS_PLAN.md` — landed via PR #106 (2026-04-29; parallel session)
- [ ] `/refine-plan plans/SKILL_FILE_DRIFT_FIX.md` — pre-run hygiene; absorbs drift from Phase B + Phase D-prior.
- [ ] `/run-plan plans/SKILL_FILE_DRIFT_FIX.md`

#### Phase E — /update-zskills source discovery (must wait for B+C+D)

- [ ] `/quickfix ← QF3` *(explicitly deferred until SCRIPTS_INTO_SKILLS, SKILL_FILE_DRIFT_FIX, DEFAULT_PORT_CONFIG land)*

#### Phase F — independent plans (any order, post-Phase B is safest)

For each item: `/refine-plan` first to absorb drift introduced by Phase B / C / D landings since the plan was authored, then `/run-plan`. Skip the refine step only if you've verified the plan has no touchpoints with what's landed since.

- [x] `/refine-plan plans/BLOCK_DIAGRAM_TRACKING_CATCHUP.md` — landed via PR #103 (2026-04-28)
- [x] `/run-plan plans/BLOCK_DIAGRAM_TRACKING_CATCHUP.md` — landed via PR #109 (2026-04-29; closes Issue #65)
- [ ] `/refine-plan plans/DRAFT_TESTS_SKILL_PLAN.md`
- [ ] `/run-plan plans/DRAFT_TESTS_SKILL_PLAN.md`
- [ ] `/refine-plan plans/QUICKFIX_DO_TRIAGE_PLAN.md`
- [ ] `/run-plan plans/QUICKFIX_DO_TRIAGE_PLAN.md`
- [x] `/refine-plan plans/ZSKILLS_MONITOR_PLAN.md` — landed via PR #101 (2026-04-28)
- [x] `/run-plan plans/ZSKILLS_MONITOR_PLAN.md` — landed via PRs #102, #104, #107, #108, #111, #113, #115, #116, #117 + #118 bookkeeping (2026-04-28 → 2026-04-29). All 9 phases complete; +270 tests (943 → 1213). New `/work-on-plans` + `/zskills-dashboard` skills; HTTP server with drag-drop dashboard; `/plans rebuild` migrated to Python aggregator.
- [x] `/draft-plan plans/PR_LANDING_UNIFICATION.md` — extract canonical `gh pr create` + CI poll + fix-cycle + auto-merge pattern into a new `/land-pr` skill consumed by all 5 PR-creating skills. [PR #77](https://github.com/zeveck/zskills-dev/pull/77) merged 2026-04-28; plan now on main.
- [ ] `/refine-plan plans/PR_LANDING_UNIFICATION.md` *(highest drift risk — plan was authored against pre-PR-#75 main; refine to absorb the merged QF/issue fixes)*
- [ ] `/run-plan plans/PR_LANDING_UNIFICATION.md`

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
