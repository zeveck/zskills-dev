# Skill Coverage Ledger — 2026-05-28

> Snapshot built during the `verification-2026.05.0` launch-readiness effort.
> Purpose: replace the impression that "~21 skills are thinly covered" with a
> measured per-skill picture, and decide *which* verification layer each skill
> actually needs. Frames per the 3-layer model
> (`feedback_canary_job_a_b_equivocation`):
>
> - **Layer 1 — deterministic surface → shell smokes, CI-gated.** Arg-parse,
>   mode dispatch, tracking-marker writes, config reads, scaffold. Does not rot.
> - **Layer 2 — integration/dispatch reality → measured dogfooding.** zskills
>   builds itself with its own skills; *measure* that usage, don't duplicate it.
> - **Layer 3 — LLM-judgment quality → genuinely hard, OUT OF SCOPE for now.**
>   "Does /draft-plan make GOOD plans? Does /qe-audit triage right?" No shell
>   test catches drift. Flagged here as **judgment, deferred** — not built.

## Method

For each skill: dedicated unit-test file(s) (name-matched + broad grep,
excluding `test-skill-conformance.sh`); conformance mentions in
`tests/test-skill-conformance.sh`; dogfooding evidence (feature branches +
scoped commit subjects over the last ~3 weeks); markdown-canary status.

Counts are coarse proxies (substring matches over/undercount), used only to
sort skills into coverage tiers — not as precise metrics.

## Core skills (25)

| Skill | Unit tests | Conf. | Dogfooded | Layer-1 status | Verdict |
|---|---|---|---|---|---|
| briefing | test-briefing-parity, test-briefing-worktrees-merged-diverged | 1 | fix(briefing)×6 | covered | **OK** |
| cleanup-merged | test-cleanup-merged-{ahead-gate,namelist,review} | 0 | recent | covered | **OK** |
| commit | test-commit | 41 | fix(commit)×2 | covered | **OK** |
| create-worktree | test-create-worktree, test-post-create-worktree | 10 | fix(create-worktree)×2 | covered | **OK** |
| do | test-do | 50 | 64 branches | heavily | **OK** |
| doc | — | 0 | — | **GAP** | **L1 smoke** (arg/mode dispatch: blocks\|examples\|newsletter) |
| draft-plan | — | 11 | 14 branches | dogfooded, no unit | **L3 deferred** (plan quality) + thin L1 |
| draft-tests | test-draft-tests{,-phase2..5} | 29 | recent | covered | **OK** |
| fix-issues | 20 files | 56 | 182 branches | heavily | **OK** |
| fix-report | (generic only) | 1 | fix(fix-report)×3 | **GAP** | **L1 smoke** (report parse + landing arg) |
| investigate | — | 0 | — | none | **L3 deferred** (root-cause judgment) |
| land-pr | 8 files | 123 | every sprint PR | heavily | **OK** |
| manual-testing | — | 0 | — | reference/recipe | **L3 deferred** (browser recipe; no det. surface) |
| plans | test-plans-render-index, test_plans_rebuild_uses_collect + plan-claim suite | 19 | recent | covered | **OK** |
| qe-audit | (generic only) | 14 | fix(qe-audit)×3 | partial | **L3 deferred** (triage quality) + thin L1 (issue dedup/format) |
| quickfix | test-quickfix | 32 | 8 branches | covered | **OK** |
| refine-plan | test-plan-drift-correct, test-skill-file-drift | 13 | 4 branches | partial | **L3 deferred** (review quality); drift mechanism covered |
| research-and-go | (generic only) | 3 | — | none | **L3 deferred** (orchestration judgment) |
| research-and-plan | (generic only) | 6 | — | none | **L3 deferred** (decomposition judgment) |
| run-plan | test-run-plan-sync-pr-body-progress, test-runplan-defer-backoff + full plan-claim suite | 122 | dogfooded | heavily | **OK** |
| session-report | (generic only) | 0 | — | **GAP** | **L1 smoke** (git/PR ground-truth audit parse) |
| update-zskills | 5 files | 62 | fix(update-zskills)×7 | heavily | **OK** |
| verify-changes | test-scope-halt + generic e2e | 13 | recent | partial | **L3 deferred** (verification quality); scope-halt mechanism covered |
| work-on-plans | test-work-on-plans{,-parallel-selection} + plan-claim | 0 | recent | covered | **OK** |
| zskills-dashboard | test_zskills_{dashboard,monitor}_* (8 files) | 5 | many | covered | **OK** |

## Block-diagram skills (5)

| Skill | Unit tests | Conf. | Layer-1 status | Verdict |
|---|---|---|---|---|
| add-block | (generic only) | 2 | **GAP** | **L1 smoke** (scaffold step structure) |
| add-example | test-mirror-skill (partial) | 1 | thin | **L1 smoke** (model file + registration scaffold) |
| model-design | — | 0 | reference | **L3 deferred** (design-guidance quality; no det. surface) |
| review-feedback | (generic only) | 0 | **GAP** | **L1 smoke** (feedback-JSON parse) |
| screenshots | — | 0 | reference | **L3 deferred** (recipe; no det. surface) |

## Findings

1. **The "~21 thinly-covered skills" estimate was too pessimistic.** Most
   skills carry dedicated unit tests, substantial conformance coverage, AND
   heavy dogfooding. The genuinely **OK** set is 15 of 25 core + 1 of 5
   block-diagram = 16/30.

2. **Genuine Layer-1 smoke gaps (deterministic surface, no dedicated unit
   test): 6 skills** — `doc`, `fix-report`, `session-report`, `add-block`,
   `add-example`, `review-feedback`. Plus *partial* L1 surface worth a thin
   smoke on `qe-audit` (issue dedup/format) and `draft-plan` (arg/mode parse).
   This is the concrete Layer-1 build list for the smokes plan (TRACK A #3).

3. **Layer-3 (judgment, deferred — no cheap automated verification): 10
   skills** — `draft-plan`, `investigate`, `qe-audit`, `refine-plan`,
   `research-and-go`, `research-and-plan`, `verify-changes`, `model-design`,
   `manual-testing`, `screenshots`. These are validated by Layer-2 dogfooding
   (catches catastrophic failure) but their *quality* drift is not
   shell-detectable. Per user 2026-05-28, Layer-3 verification is explicitly
   out of scope; these are flagged, not built.

4. **Layer-2 (dogfooding) is strong but unmeasured.** Branch/commit evidence
   shows `/fix-issues` (182 branches), `/do` (64), `/draft-plan` (14),
   `/quickfix` (8), `/run-plan`, `/land-pr`, `/update-zskills` all running
   continuously. TRACK A #3 should add a harness that *measures* this
   (skill ran N× successfully this week) rather than duplicating it as canaries.

## Kept-markdown-canary disposition map

The 7 markdown canaries retained after PR #762. Each is dispositioned against
this ledger. Markdown canaries left in `docs/plans/` rot because they *look*
like Job-A (CI) assets but are Job-B (one-time live) artifacts.

| Canary | Nature | Disposition | Rationale |
|---|---|---|---|
| `CANARY1_HAPPY` | Job-B: PR→CI→auto-merge happy path | **Retire → archive** | Dogfooded 100s of times via every sprint PR; `status: complete` since 2026-05-10 |
| `CANARY8_PARALLEL` | Job-B: parallel pipelines don't cross-block | **Retire → archive** | Mechanism covered by `test-hooks.sh` suffix-match cases A–F + `tests/e2e-parallel-pipelines.sh`; e2e dogfooded by concurrent sprints |
| `CANARY_LAND_PR` | Job-B: /land-pr fix-cycle e2e | **Retire → archive** | `/land-pr` has 8 dedicated tests + 123 conformance; fix-cycle path dogfooded whenever a sprint PR's CI fails |
| `CANARY_BYPASS_DETECT` | Hook decision surface vs synthesized envelopes in sandbox | **Convert → smoke** (build in TRACK A #3) | Already shaped like a Layer-1 smoke; `tests/test-block-bypassed-land-pr.sh` exists — verify it covers the canary's cases, fill gaps, then retire the markdown |
| `CANARY11_SCOPE_VIOLATION` | Layer-3: LLM scope-vs-plan judgment quality | **Keep → relabel as eval** (`docs/evals/`) | Tests `/verify-changes` reviewer judgment; bash mechanism locked by `test-scope-halt.sh`; NOT shell-replaceable |
| `CANARY11_TEST_PLAN` | Synthetic input fixture for CANARY11 | **Keep → move with CANARY11** | Eval input fixture; moves alongside its eval |
| `REBASE_CONFLICT_CANARY` | Layer-3: agent-assisted intelligent rebase-conflict merge | **Keep → relabel as eval** (`docs/evals/`) | Mechanical rebase paths covered by `test-land-pr-auto-rebase-behind` + `test-land-pr-rebase-rc14-parser`; the "read both sides and merge intelligently" branch is judgment |

**Executed in this PR:** archive the 3 retire-as-dogfooded canaries; create
`docs/evals/` (with a README explaining these are Layer-3 judgment evals — run
manually/periodically, NOT CI-gated) and move the 3 keep-as-eval canaries
there. `CANARY_BYPASS_DETECT` stays put pending the TRACK A #3 smokes plan.
