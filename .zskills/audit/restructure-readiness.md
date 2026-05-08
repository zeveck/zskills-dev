# RESTRUCTURE Readiness Report

**Date:** 2026-04-19 (America/New_York)
**HEAD:** `131d0b7` test(skill-conformance): honor REPO_ROOT env override
**Plan target:** `plans/RESTRUCTURE_RUN_PLAN.md` — reorganize `/run-plan`, `/commit`, `/do`, `/fix-issues` using progressive disclosure (SKILL.md → modes/*.md + references/*.md).

## TL;DR

**Ready to start RESTRUCTURE.** All three pre-work items from the safety-net plan are complete:

- **A — Skill-conformance test** ✅ — 86 grep-based invariants across the four target skills + `/verify-changes`. Catches silent drops of critical patterns during extraction. Drift detection empirically verified (stripping one pattern fires exactly one FAIL).
- **B — Cron math extraction** ✅ — `scripts/compute-cron-fire.sh` + 29-case test suite. Replaces three inlined copies in `/run-plan`; fixes a latent day/month/year rollover bug in the process.
- **C — Static baseline snapshot** ✅ — `reports/baseline-pre-restructure.md` captures SKILL.md file sizes, SHA-256 hashes, H2/H3 header inventories, shipped scripts, and coverage summary. Dynamic canary runs deferred to user (autonomous execution creates PRs and costs hours of wall time).

Test suite: **531 / 531** passing unit + integration, **542 / 542** with E2E. Mirrors in sync. Working tree clean.

## What the safety net catches

| Failure mode | Caught by | How |
|---|---|---|
| RESTRUCTURE drops a specific code block or named variable | `test-skill-conformance.sh` | Greps the whole `skills/<skill>/` tree (recursive — finds it whether it ended up in SKILL.md, modes/*.md, or references/*.md). 86 patterns. |
| Critical section header is renamed or removed | `test-skill-conformance.sh` | Structural landmarks (`^## Phase 5c`, `^## Failure Protocol`, etc.) are explicit patterns. |
| Cron-firing math regresses | `test-compute-cron-fire.sh` | 29 cases covering :00/:30 avoidance, minute/hour/day/month/year rollover, leap year, usage errors. |
| Preset UX breaks (config write / hook splice / idempotency) | `test-apply-preset.sh` | 16 cases covering legacy hook splice, missing `execution` key, compact JSON, error paths. |
| Hook regex accidentally changes | `test-hooks.sh` | Broad coverage of destructive-op policy, tracking enforcement, push-block toggle, edge cases. |
| `.claude/` mirrors drift from `skills/` sources | `test-skill-invariants.sh` | `diff -q` assertions. |
| Tracking markers enforce incorrectly | `test-tracking-integration.sh`, `test-phase-5b-gate.sh` | Real marker files, real hook invocations. |
| Parallel pipelines collide | `e2e-parallel-pipelines.sh` (opt-in) | Two concurrent pipelines against real git worktrees. |
| Install audit claims files that don't ship | Fresh-clone smoke test | We ran this during the migrate-tracking incident; would catch similar drift. |

## What the safety net does NOT catch (honest gaps)

| Failure mode | Why not | Mitigation |
|---|---|---|
| Phase ORDERING within a skill (e.g., Phase 5 must complete before Phase 6) | Grep patterns can check for presence, not order | Relies on RESTRUCTURE's byte-preservation rule + canary runs |
| Coherent blocks (re-push → --watch → re-check → auto-merge) get split across files incoherently | Conformance test checks for individual pieces, not their adjacency | Canary runs (CI_FIX_CYCLE_CANARY) exercise the whole block end-to-end |
| Semantic drift in prose (e.g., "must not" changes to "should not") | Conformance test explicitly excludes prose by design (too fragile) | Unavoidable unless we switch to strict byte-hash comparison, which would block every cosmetic edit |
| Cross-skill references (e.g., `/fix-issues` links to `/run-plan`'s CI block) break after split | No cross-skill assertion in the tests | Canary coverage (CI fix cycle runs `/fix-issues pr`, exercising the cross-ref) |
| PR-mode bookkeeping commits end up on wrong branch | "`PR-mode bookkeeping`" phrase is grep-checked but the actual `cd $WORKTREE_PATH` ordering isn't | Canary CANARY10_PR_MODE and CANARY6_MULTI_PR exercise this end-to-end |

All listed gaps have canary coverage. The canaries in `plans/` are the integration-level safety net; they just don't run automatically.

## Dynamic coverage — what the user should consider running

Before starting RESTRUCTURE Phase 1, the user may want to run a subset of canaries to capture their current outcome shape. The RESTRUCTURE plan's **Phase 5** reruns CANARY1/6/7/8 + CI_FIX_CYCLE post-restructure; having pre-restructure captures lets you diff outcome shape, not just pass/fail.

Recommended pre-restructure runs (in priority order):

1. **CANARY7_CHUNKED_FINISH** — exercises cron spacing (my compute-cron-fire.sh change; highest regression risk).
2. **CI_FIX_CYCLE_CANARY** — the CI fix-cycle is the most complex block in `/run-plan` and RESTRUCTURE will move it. Pre/post diff would catch subtle ordering breakage.
3. **CANARY10_PR_MODE** or **CANARY6_MULTI_PR** — PR-mode bookkeeping is the "commit to feature branch, not main" contract; both exercise it.
4. **CANARY1_HAPPY** or **CANARY5_AUTONOMOUS** — cheapest full-pipeline sanity.
5. **CANARY8_PARALLEL** + **PARALLEL_CANARY A/B** — parallel pipelines; optional if you trust `e2e-parallel-pipelines.sh`.

Running all five would be ~2-3 hours of wall time, mostly waiting for CI. Skipping is acceptable — the static safety net covers most concerns — but a single run of CANARY7 + CI_FIX_CYCLE is the highest-ROI insurance.

## Commits landed in this prep sequence

| Commit | What |
|---|---|
| `273597f` | test(skills): add test-skill-conformance.sh — 88-pattern gate (shipped in 2026.04.0) |
| `46739d3` | fix(update-zskills): remove audit entry for deleted migrate-tracking.sh |
| `14dea81` | docs(readme): simplify agent install instructions to one-liner |
| `d1b1425` | feat(scripts): compute-cron-fire.sh + 29-case test suite |
| `64ee65b` | refactor(run-plan): delegate cron math to compute-cron-fire.sh |
| `62d7237` | docs(reports): add static pre-RESTRUCTURE baseline snapshot |
| `131d0b7` | test(skill-conformance): honor REPO_ROOT env override |

Tag `2026.04.0` currently points at `14dea81` (matched across dev and prod). The newer commits (`d1b1425`..`131d0b7`) are unpushed as of this report. **Decision point for user:** push these to both remotes before starting RESTRUCTURE (so it works against latest), OR ship them as part of the RESTRUCTURE closeout tag. My lean is **push now** — compute-cron-fire.sh is a bug fix (day/month/year rollover), worth getting out regardless of RESTRUCTURE timing.

## Greenlight

From a safety-net perspective, **RESTRUCTURE can start.** The static gates will catch most byte-preservation violations; canary runs post-restructure (Phase 5 of the RESTRUCTURE plan) will catch the rest.

If the user wants extra assurance before starting, running CANARY7 + CI_FIX_CYCLE once against current main (pre-RESTRUCTURE) captures the reference shape for diffing. Optional but cheap insurance.

No blockers. No pending fixes. Recommend: push the 4 unpushed commits, then start RESTRUCTURE Phase 1 (`/commit` restructure).
