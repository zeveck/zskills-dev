# Seam / Autonomous-Exercise Coverage Ledger — 2026-05-29

> Companion to `skill-coverage-ledger-2026-05-28.md`. That ledger answered
> *"does each skill have a test + dogfooding"* (a proxy). This one answers the
> deeper question the proxy hid: **for each skill, how much of its failure
> surface can be exercised AUTONOMOUSLY and REPEATABLY (not a one-shot manual
> canary), and where the existing tests only *look* green.**
>
> Built by a 30-agent surface-mapping pass (one agent per skill; `screenshots`
> excluded — it's an asset dir, `domain-skills.png`, not a skill). Each agent
> classified the skill's behavior into the **judgment line**: below it =
> deterministic mechanics (arg-parse, mode dispatch, tracking-marker lifecycle,
> caller-loop / `.landed` result-file handling, hook-gate interactions,
> agent-return handling, parse/render) = autonomously exercisable; above it =
> LLM-judgment quality (is the plan *good*, did triage size *right*) = Layer-3,
> deferred by standing decision.

## The headline finding

**"Tests pass" badly overstated our coverage — and the most-covered skills are
the hollowest.** 12 of 30 skills have tests that **execute a re-implementation
or embedded copy of the skill's logic, not the production code** — the #809
pattern (a green test over a code path production never takes). The worst are
the *highest-traffic* skills:

- **`do` / `quickfix`** — their seam tests (`test-quickfix.sh` Cases 47/48)
  assert against a hand-written `TRIAGE_SIM`/`REVIEW_SIM` built *inline in the
  test*; the production `SKILL.md` seam path is never executed. The sim's
  redirect-message text has **already drifted** from production (`force to
  bypass` vs `--force`), proving the test would stay green if the real message
  broke. `do` has *no* seam test of its own — it defers to quickfix's sims, and
  its triage/cron-ordering is guarded only by a static grep.
- **`run-plan`** — three tests (`test-runplan-defer-backoff.sh` et al.) each
  flagged in their *own headers* as "re-implements the logic."
- **`land-pr`** — `run_auto_rebase_block` / `run_copy_block` / `run_ff_block`
  are re-implemented blocks, not extracted production fences.
- **`verify-changes`** — a private `parse_args()` copy inside `test-hooks.sh`.
- **`work-on-plans`, `zskills-dashboard`, `plans`** — re-defined/transcribed
  copies of the skill functions.

**Root cause is a *technique*, not 12 separate bugs:** the repo's prevailing
test idiom is **"embed a faithful copy of the bash and assert against it."**
That idiom *generates* hollow-green tests by construction. Four skills
(`draft-plan`, `fix-issues`, `add-block`, `add-example`) embed-but-add a
`grep -qF` **parity gate** that fails on drift — those are *mitigated*, not
hollow. The fix for the rest is one principle, not twelve patches:

> **North star: EXTRACT-AND-RUN the production fence, don't embed a copy.**
> `tests/test-do.sh`'s `extract_*` helpers and `test-cleanup-merged-ahead-gate.sh`
> already do this — awk-extract the real fenced block from `SKILL.md` (or source
> the real script) and execute *that*. A test that runs production code can't
> drift green. Where the flow needs an injected decision, add a `_ZSKILLS_TEST_`
> seam (proven in `do`/`quickfix`) so the surrounding machinery runs for real.

## Verdict distribution (30 skills)

- **SOLID — 9:** below-line surface meaningfully exercised through production paths.
  `fix-issues`, `create-worktree`, `draft-tests`, `cleanup-merged`,
  `update-zskills`, `briefing`, `fix-report`, `plans`, `add-example`.
  (`fix-issues`/`plans`/`add-example` carry a *mild* re-impl note but are
  parity-gated or otherwise sound.)
- **THIN — 12:** real coverage gaps and/or hollow-green re-impl tests.
  `do`, `quickfix`, `run-plan`, `land-pr`, `commit`, `work-on-plans`,
  `draft-plan`, `refine-plan`, `research-and-go`, `zskills-dashboard`,
  `verify-changes`, `add-block`.
- **JUDGMENT-DEFERRED — 9:** no executable surface; only LLM-judgment quality,
  which is out of scope by standing decision. `investigate`, `qe-audit`,
  `research-and-plan`, `review-feedback`, `session-report`, `doc`,
  `manual-testing`, `model-design`, `migrate-crons`.
  These are validated by dogfooding (catches catastrophic failure), not by
  shell tests — and the ledger says so honestly rather than calling them "OK."

## How much is autonomously exercisable

The reassuring half: **the bug-prone surface is almost entirely below the
judgment line** — and #809 confirms real bugs live in the mechanics
(a marker-dropping bridge), not in the LLM judgment. For the orchestration/
landing skills, ~70–85% of the failure surface is reachable by extract-and-run
+ seams + sandbox harnesses (git-init + worktree-add + synthesized `.landed`/
tracking fixtures, or a faked `land-pr` result-file). Only content quality is
irreducibly above the line.

Two reference techniques, both already proven in-repo:
1. **Extract-and-run** (`test-do.sh` `extract_*`) — run the real `SKILL.md` fence.
2. **Faked result-file caller-loop harness** (`test-fix-issues-sprint-land-pr.sh`)
   — git shim + pre-staged `$RESULT_FILE` to drive every STATUS×CI_STATUS branch.

## Prioritized seam-build backlog

**HIGH (8) — orchestration/landing/marker-lifecycle, real bug-risk, unexercised
or hollow:** `do`, `quickfix`, `run-plan`, `land-pr`, `commit`, `draft-plan`,
`refine-plan`, `work-on-plans`. Each needs: convert its hollow/re-impl tests to
extract-and-run, and (where the flow gates on a model decision) add a
`_ZSKILLS_TEST_` seam + a caller-loop/result-file or sandbox harness driving
the real fences.

**MED (4):** `fix-issues` (mild parity-gated re-impl → tighten), `research-and-go`,
`verify-changes` (private parser copy → extract), `zskills-dashboard`
(transcribed copies → extract/import).

**LOW (5):** `briefing`, `cleanup-merged`, `create-worktree`, `draft-tests`,
`add-block`, `add-example` — small import-and-call unit additions only.

**NONE (13):** SOLID skills with no gap + the 9 JUDGMENT-DEFERRED.

## Per-skill table

| Skill | Verdict | Seam-build priority | Has seam | Hollow/re-impl test |
|---|---|---|---|---|
| `do` | THIN | high | yes | YES |
| `quickfix` | THIN | high | yes | YES |
| `fix-issues` | SOLID | med | no | YES |
| `run-plan` | THIN | high | no | YES |
| `land-pr` | THIN | high | no | YES |
| `commit` | THIN | high | no | — |
| `create-worktree` | SOLID | none | no | — |
| `work-on-plans` | THIN | high | no | YES |
| `draft-plan` | THIN | high | no | YES |
| `draft-tests` | SOLID | low | yes | — |
| `refine-plan` | THIN | high | no | — |
| `research-and-go` | THIN | med | no | — |
| `research-and-plan` | JUDGMENT-DEFERRED | low | no | — |
| `cleanup-merged` | SOLID | low | yes | — |
| `update-zskills` | SOLID | none | no | — |
| `migrate-crons` | JUDGMENT-DEFERRED | none | no | — |
| `briefing` | SOLID | low | yes | — |
| `plans` | SOLID | none | no | YES |
| `session-report` | JUDGMENT-DEFERRED | none | no | — |
| `fix-report` | SOLID | none | no | — |
| `zskills-dashboard` | THIN | med | no | YES |
| `investigate` | JUDGMENT-DEFERRED | none | no | — |
| `qe-audit` | JUDGMENT-DEFERRED | none | no | — |
| `verify-changes` | THIN | med | no | YES |
| `review-feedback` | JUDGMENT-DEFERRED | none | no | — |
| `doc` | JUDGMENT-DEFERRED | none | no | — |
| `manual-testing` | JUDGMENT-DEFERRED | none | no | — |
| `model-design` | JUDGMENT-DEFERRED | none | no | — |
| `add-block` | THIN | low | no | YES |
| `add-example` | SOLID | none | no | YES |

## What ships from here

1. This ledger (the map).
2. A `/draft-plan`-reviewed plan scoped to the **8 HIGH-priority skills**, whose
   north star is *convert embed-and-assert → extract-and-run* + add seams, so
   the highest-bug-risk skills get tests that exercise production code. Built
   and landed via `/run-plan finish auto`.
3. The MED/LOW backlog is a documented follow-up (a second plan), not bundled
   into the first — keeps each phase implementable.
4. The 9 JUDGMENT-DEFERRED skills stay deferred and labeled; no manufactured seams.

**Honest caveat:** this map is itself produced by LLM agents reading code, so it
reduces — does not eliminate — hollow-green risk (each verdict carries file:line
evidence in the raw results for spot-checking). The durable guarantee comes from
the extract-and-run tests the plan builds, which execute production code.
