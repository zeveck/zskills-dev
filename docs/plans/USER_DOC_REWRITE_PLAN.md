---
title: User-Doc Rewrite — docs/skills then docs/guides
created: 2026-06-02
status: active
---

# Plan: User-Doc Rewrite (docs/skills → docs/guides)

> **Landing mode: PR** (`main_protected: true`). **Executed by the top-level orchestrator, not `/run-plan`.** The per-doc pipeline fans out several agents per doc, and a `/run-plan` phase implementer is itself a subagent that cannot dispatch sub-subagents (Anthropic design) — so it could not run the pipeline. The orchestrator dispatches the agents directly, does each phase's work in a worktree, and lands each phase as an auto-merged PR via `/land-pr`. Mode is automatic under locked-main — never pass a redundant `pr` token.

## Overview

The catalog-visible docs (`docs/skills/*.md`, `docs/guides/*.md`) were largely written by **transcribing internal reasoning** — release-management caveats, hook mechanics, phase numbers, work-item IDs — onto pages that are meant to be plain, user-facing skill references. The result is two compounding defects:

1. **Inaccuracy.** Docs assert things that are false, stale, or overstated. The codebase moves underneath them (e.g. `do.md`'s verification claim was made accurate only by the #1014 work, merged as PR #1016 / commit `908c403` *after* the most recent audit).
2. **Wrong altitude.** Even accurate sentences are written in implementer voice ("the materialiser", "sentinel-gated", "Phase 0a", "WI 1.5.5", `${CLAUDE_PLUGIN_ROOT}`), or hedge themselves into technical correctness at the cost of readability.

**Goal:** every catalog doc reads as a clean, trustworthy, user-facing reference for a *technical-but-uninitiated* reader — someone who knows software but not zskills internals. Each doc answers, in plain prose: **what the skill does · its typical usage · its companion skills · its arguments.** Behavior and observable output, never internals. Nothing overstated.

**The failure mode this plan exists to defeat.** A prior session repeatedly *claimed* it had read source and audited docs, then admitted it had skimmed and guessed. This plan makes "I read it" **mechanically provable** rather than asserted, and treats every agent (and the orchestrator) as suspect until its claims are backed by quoted source lines.

### The 46-finding audit is an expired sample, not a worklist

Issue **#1020** records a 46-finding audit from PR #984. Those findings are **hypotheses, already partly stale** — at least one (the `do.md:73` verification claim) was resolved by the #1014 work (merged as PR #1016 / `908c403`) *after* the audit ran, so acting on it would have *re-broken* a correct sentence. This plan therefore **re-derives ground truth for every doc from current source**, using #1020 only as a hint about where rot concentrates. We fix the **whole shape**, not the sample.

### Non-goals

- **Not** a redesign of the docs' structure — the existing skeleton (summary / usage / arguments / examples) is mostly fine; this is rewrite-in-place at the right altitude.
- **Not** a skill-behavior change. Where a doc rewrite *uncovers* a skill bug or a surprising inconsistency, that finding goes to `DISCREPANCIES.md` for the user to rule on — it is **not** silently documented as a feature, and **not** patched here (zskills "surface bugs, don't patch").
- **Does not** rewrite `docs/skills/manual-testing.md` (owned by #1012) or the dev-vs-prod URL / install-path content in `docs/guides/inspecting-and-monitoring.md` (overlaps #1002). Those rows are deferred to the issue owners.

## The Rubric (every phase's implementer and verifier consume this)

These rules are the standard each rewritten doc is held to. They are referenced by every per-doc phase; Phase 0 lands them as a standalone rubric file the implementers read.

**R1 — Right-shape-but-inaccurate is the dominant risk.** A doc can read perfectly and still lie. Every factual claim is verified against *current* source (`skills/<name>/SKILL.md` + `modes/` + `references/`, `CLAUDE.md`, hooks). A claim with no supporting source line does not ship.

**R2 — Universals demand an exception hunt.** "all", "always", "every", "never", "regardless of mode" read as authoritative and are the easiest claims to falsify with one carve-out. For each universal, the verifier performs a *dedicated* search for the falsifying exception. If one exists, the claim is rescoped to plain truth; if none is exhibited, the universal is treated as **unverified, not passed**. The hunt is a **checklist, not a vibe**: for each universal, check (a) config fields that gate it (`execution.landing`, `main_protected`), (b) hook fences, (c) the CLAUDE.md decision/flag tables, (d) the skill's own `modes/` files, (e) the peer-skill docs. "Ran one grep, found nothing" is not a hunt.

**R3 — Plain-and-true beats technically-correct-and-messy.** When a simple statement would overstate, do **not** bolt on qualifiers until it is bulletproof (that produces the hedge-soup seen in `installing-zskills.md`). In priority order: **(a) raise altitude** to observable behavior the user can rely on; **(b) drop the edge case** if the user won't hit it or care; **(c) only if genuinely user-relevant**, one short scoped clause — never a qualifier-nest.

**R4 — Modes are a thin axis; describe behavior once.** A skill's behavior is stated **uniformly**. The only things mode changes are: *does it use a worktree? does it open a PR? how much ceremony?* Do **not** narrate behavior mode-by-mode. The phrases "regardless of mode" and "in PR mode… / in worktree mode…" are themselves the tell of mode-by-mode thinking — delete them and state the behavior plainly. (Note: which *modes are even available* is config-conditional — `direct`/`cherry-pick` are illegal under `main_protected` — so docs lead with the common protected-main default and don't drown the reader in the full mode matrix.) **R4 flattens *narration*, not *truth*.** Where a mode genuinely changes behavior in a way the user can hit — e.g. `/do` skips `/verify-changes` for content-only changes (`skills/do/SKILL.md`, `modes/pr.md`) — keep it as one short scoped clause (R3-c). Deleting a *true* carve-out to satisfy R4 is a regression, not a fix; that is the R2↔R4 balance.

**R5 — No internals voice.** Banned from user prose unless the user observably encounters the term: "materialiser", "sentinel", "atomic/atomically", "Phase 0a/Nx", "WI N.N", "Tier 1/Tier 2", `${CLAUDE_PLUGIN_ROOT}`, "static-grep", "preset-owned", "git-common-dir", internal `#issue` links, and like jargon. Lead with what the user does or expects, never with how the implementation works. (Phase 0 finalizes the banned-term list.)

**R6 — Companion skills must agree across docs.** Every doc's "companion skills" section is drawn from one canonical companion-skill graph (Phase 0), so the docs cross-reference each other consistently.

**R7 — Peers read as peers.** Co-equal skills (e.g. `/do` ↔ `/quickfix`) get equal-quality docs regardless of which the author personally uses. Usage-log mining (Phase 0) is a **single-user-biased** signal — it informs realistic "typical usage" examples, but never justifies under-serving a peer skill the sample happens to avoid.

## The per-doc pipeline (how each doc gets rewritten and proven)

Each doc is rewritten through three roles, all dispatched by the **top-level orchestrator** (which has `Agent` access). This is *why* the plan is executed by the orchestrator and not `/run-plan`: a `/run-plan` phase implementer is itself a subagent and **cannot dispatch sub-subagents** (Anthropic design), so it could not fan out the pipeline. The orchestrator runs the roles as separate agents per doc (or per small group) and spot-checks their output. The orchestrator may scale the agent count to the work — the role separation, not a fixed headcount, is what matters:

1. **Extract + write (a dispatched implementer agent).** Reads the *full* source for each skill in the group, then commits, alongside the rewritten doc, a **fact sheet**: every factual claim the doc makes, each tied to a `SKILL.md:LINE` citation + quote. Arguments come from `argument-hint`; companion skills from the Phase-0 graph; typical-usage from the Phase-0 usage map. **The fact sheet proves a line was *located*, not that it *supports* the claim** — a skimming agent can grep a real line, quote it verbatim, and still attach it to a doc sentence it does not back. So each entry pairs the citation with **the exact doc sentence it backs** (claim↔quote adjacency), written as `path:line: "<verbatim quote>"` so the quote is mechanically re-checkable. Citation *existence* is cheap; *correspondence* (does this line support this sentence?) is the load-bearing check — that is the verifier's job (step 2), not a mechanical guarantee. The doc may state nothing absent from its fact sheet. The agent also records any cross-mode / cross-skill surprises as discrepancy notes. (Extract and write may be one agent or two; if one, the fact sheet must still be committed as the inspectable proof-of-read.)

2. **Adversarial re-read (a separate dispatched verifier agent).** A *suspect* reviewer that trusts neither the fact sheet nor the draft. It **independently re-reads the source** and produces a verdict ledger: each doc claim → supported / unsupported / overstated, with the source line; each universal → exception-hunt result (R2); plus a **readability/altitude gate** (R3/R4/R5: would a technical newcomer understand this in one read, with no internals?). Any unsupported/overstated claim, fabricated citation, surviving jargon, or hedge-soup → **fail**, back to step 1.

3. **Spot-check + curate (the top-level orchestrator).** First a **mechanical citation check** — `sed -n '<line>p'` each cited `path:line` and assert the quoted substring actually appears there (100% coverage, cheap; catches fabricated line numbers). Then a **semantic** re-check of a sample biased to **every universal-quantifier claim (R2) plus a random `max(3, ceil(claims/3))`**, weighted to the back half of long source files where skim-fabrication concentrates (agent reports are themselves hypotheses). Then folds the discrepancy notes into `docs/reports/SKILL_DISCREPANCIES.md`. A verifier "looks fine" with no citation ledger is a failure signal, not a pass. **The mechanical check guarantees the line exists and the quote is real; it does NOT guarantee the quote supports the claim — that is the semantic sample's job.**

## Deliverables

- **Rewritten catalog docs**, landed as thematic PRs grouped by peer-family.
- **`docs/reports/SKILL_DISCREPANCIES.md`** (outside the viewer catalog so it stays a working doc): cross-skill inconsistencies and surprising cross-mode behavior, each entry tagged with the orchestrator's **hypothesis of intent (intentional vs. surprising)** and a request for the user's ruling. Divergence ≠ bug — some is deliberate (e.g. `/do`'s `stop [query]`/`next [query]` disambiguators exist because `/do` *could* fan out parallel crons in one session; most schedulable skills correctly use bare `every`/`stop`/`next`). Entries never assert a verdict; they ask. **Intake is bounded** to avoid a judgment swamp: log an entry only when the inconsistency (a) would change a user-facing doc claim, or (b) looks like a real skill bug — pure stylistic variation is not logged. Soft-cap ~20 entries; beyond that, record the *count* of un-enumerated extras rather than listing every one.
- **Per-doc fact sheets + verdict ledgers** committed as review evidence (kept under `docs/reports/doc-rewrite-evidence/` so they're out of the catalog).

## Shared Conventions

### Scope and order

- **25 skill docs** in `docs/skills/` (1:1 with `skills/<name>/`), plus the `docs/skills/block-diagram/` set and `docs/skills/README.md`. **Primary.**
- **5 guides** in `docs/guides/` (you rated these "not terrible"). **Secondary — after skills are solid.**
- Within scope, peers are rewritten **together** (R7), highest-leverage families first.

### Coordination

- `manual-testing.md` **prose** → **#1012** (in flight now — makes `/manual-testing` `user-invocable: false`). Do not rewrite its body here. Its **nav placement** (move into the new "Internal Skills" section, alongside `/land-pr`) **is** ours — see Phase 6.
- `inspecting-and-monitoring.md` dev/prod-URL + install-path content → **#1002** (rewrite the rest of that guide normally; leave those rows to #1002).
- A doc-rewrite that touches a `skills/<name>/SKILL.md` source (e.g. to fix a leaked phase-number the doc mirrors) bumps `metadata.version` and mirrors per repo discipline — but the default expectation is **docs-only** edits.

### Per-phase mechanics

- Each phase = one peer-family. The implementer reads every source file at HEAD (line numbers shift; roles don't).
- Acceptance is checked by the verifier's ledger **and** the orchestrator's spot-check before the phase's PR lands.
- `docs/reports/SKILL_DISCREPANCIES.md` accumulates across phases; the final phase consolidates and presents it.
- **Phases land strictly serially.** Each phase's PR is fully merged and its tracking markers cleaned before the next phase's agents are dispatched. No per-doc agent dispatches `/land-pr` — only the orchestrator lands, once per phase (avoids the serial-`requires.land-pr` deadlock CLAUDE.md warns about).
- **Catalog regen on H1 change.** The viewer nav is generated into `docs/DocsRegistry.js` by `scripts/build-catalog.sh` (DO NOT hand-edit), and `tests/test-doc-viewer-catalog.sh` byte-diffs it as a drift gate; the nav entry `name` derives from each doc's H1. So if a rewrite changes a doc's H1, re-run `bash scripts/build-catalog.sh` and commit the regenerated `docs/DocsRegistry.js` in the SAME PR, or the drift gate fails the landing.
- **`inspecting-and-monitoring.md` parity gate.** `tests/test-doc-viewer-parity.sh` asserts the rendered `.md` carries every distinctive token from the hand-built `.html`. A rewrite that drops tokens trips it; if a drop is deliberate, update `HTML_ONLY_OK_TOKENS` with a reason.
- **`bash tests/run-all.sh` must pass before each phase PR lands** (catches the catalog drift gate, parity gate, and any conformance gate touched).

---

## Phase 0 — Foundations (rubric, companion graph, usage map, scaffolds)

_Status: pending._ One-time shared groundwork every later phase consumes. No catalog doc is rewritten in this phase.

- [ ] **Land the Rubric** (`docs/reports/doc-rewrite-evidence/RUBRIC.md`): R1–R7 above, plus the finalized **banned-term list** (seed from R5; expand by grepping the current docs for internals vocabulary). This is the file phase implementers and verifiers are pointed at. Also emit the list as a grep-able artifact `docs/reports/doc-rewrite-evidence/banned-terms.txt` — one `grep -E` pattern per line, properly escaped (`materialiser`, `sentinel`, `Phase 0a`, `WI [0-9]`, `\$\{CLAUDE_PLUGIN_ROOT\}`, …) — so every later phase's "banned-term grep clean" acceptance is the concrete command `grep -nEf docs/reports/doc-rewrite-evidence/banned-terms.txt <phase docs>`.
- [ ] **Build the canonical companion-skill graph** (`.../COMPANIONS.md`): for each skill, its typical companion skills and the "which skill for which input" mapping, reconciled against the CLAUDE.md decision table. Source-cited.
- [ ] **Mine the usage logs** (`.../USAGE_MAP.md`): a **bounded** pass over the project's `~/.claude/projects/.../*.jsonl` transcripts (~107 files, ~725 MB — stream line by line, never load whole files) extracting both typed `/<skill>` invocations and cron `Run /<skill>` / `Run /zs:<skill>` forms → per-skill counts + argument shapes, plus a "never observed" list. A small streaming Python/grep pass is fine; if it proves costly, downgrade to `grep -ohE '(^|Run )/(zs:)?[a-z-]+'` and **label it a sample, not a census**. **Stamp the file**: *single-user-biased sample — informs examples, never deprioritizes peers (R7).*
- [ ] **Scaffold `docs/reports/SKILL_DISCREPANCIES.md`** with the intentional-vs-surprising entry template and the seed entry: *mode-availability is config-conditional (`direct`/`cherry-pick` illegal under `main_protected`; appending `pr` is redundant under locked-main) — real modality, should be consistent across skills; user to rule.*

**Acceptance:**
- [ ] RUBRIC.md, `banned-terms.txt`, COMPANIONS.md, USAGE_MAP.md, SKILL_DISCREPANCIES.md exist with the content above; USAGE_MAP carries the bias stamp; `banned-terms.txt` is valid `grep -E` (`grep -nEf docs/reports/doc-rewrite-evidence/banned-terms.txt docs/skills/*.md` runs without regex error).
- [ ] COMPANIONS.md cross-checked against the CLAUDE.md decision table (no skill contradicts it).
- [ ] No catalog `docs/skills/` or `docs/guides/` file modified in this phase (`git diff --stat` touches only `docs/reports/`).

## Phase 1 — Execution peers: do, quickfix, commit, land-pr, cleanup-merged

_Status: pending._ The `/do` ↔ `/quickfix` peer pair is the anchor (R7) — they must read as co-equal. `land-pr` is `user-invocable: false` and must say so plainly without dumping its result-code list.

- [ ] Run the per-doc pipeline on each of `do.md`, `quickfix.md`, `commit.md`, `land-pr.md`, `cleanup-merged.md`.
- [ ] `do.md` / `quickfix.md`: present as parallel peers; describe verification/behavior uniformly (R4 — no "regardless of mode").
- [ ] `land-pr.md`: lead with "internal helper — typing it directly won't work; use `/commit pr`"; drop the implementer result-code enumeration. (Its **nav** move into the Internal Skills section happens in Phase 6.)
- [ ] Record discrepancy notes (e.g. the config-conditional mode availability) to `SKILL_DISCREPANCIES.md`.

**Acceptance:**
- [ ] Each doc has a committed fact sheet (line+quote citations) and a verifier verdict ledger with zero unsupported/overstated claims.
- [ ] Banned-term grep over the five docs returns no hits (per RUBRIC list).
- [ ] Orchestrator spot-check of ≥3 citations per doc against source confirms them.
- [ ] No "regardless of mode" / per-mode behavior narration remains.

## Phase 2 — Planning peers: draft-plan, run-plan, refine-plan, draft-tests, plans

_Status: pending._ The plan-authoring family; cross-references between them must be consistent (R6).

- [ ] Run the per-doc pipeline on `draft-plan.md`, `run-plan.md`, `refine-plan.md`, `draft-tests.md`, `plans.md`.
- [ ] `run-plan.md`: fix the `auto` description (mode-conflated — cherry-pick mode has no PR to auto-merge); replace cron-cadence mechanics with user-relevant "long phases don't burn context".
- [ ] `plans.md`: strip implementer voice ("collect.py", "thin renderer", "canonical classifier").

**Acceptance:**
- [ ] Fact sheet + clean verdict ledger per doc; banned-term grep clean; ≥3 citation spot-checks per doc; companion sections agree with COMPANIONS.md.

## Phase 3 — Backlog/decompose peers: fix-issues, fix-report, work-on-plans, research-and-plan, research-and-go

_Status: pending._ The "drive a backlog / decompose a goal" family.

- [ ] Run the per-doc pipeline on `fix-issues.md`, `fix-report.md`, `work-on-plans.md`, `research-and-plan.md`, `research-and-go.md`.
- [ ] `research-and-plan` ↔ `research-and-go`: present as the stop-after-draft vs. continue-into-execution pair, uniformly.
- [ ] Sweep the "Tips & Gotchas" tails flagged in #1020 for these docs.

**Acceptance:**
- [ ] Fact sheet + clean verdict ledger per doc; banned-term grep clean; ≥3 citation spot-checks per doc; companion sections agree.

## Phase 4 — Diagnose/verify peers: investigate, qe-audit, verify-changes, session-report

_Status: pending._

- [ ] Run the per-doc pipeline on `investigate.md`, `qe-audit.md`, `verify-changes.md`, `session-report.md`.
- [ ] `session-report.md`: add the missing `handoff` mode (source `argument-hint: "[handoff]"`).
- [ ] `verify-changes.md`: remove `subagent_type:"verifier"` / "Layer 3" internals.

**Acceptance:**
- [ ] Fact sheet + clean verdict ledger per doc; banned-term grep clean; ≥3 citation spot-checks per doc; `handoff` mode documented and source-cited.

## Phase 5 — Infra/meta peers: update-zskills, create-worktree, briefing, zskills-dashboard, doc

_Status: pending._ (`manual-testing.md` excluded — owned by #1012.) This phase also picks up **`doc.md`** — the 25th skill doc, which earlier drafts left unassigned.

- [ ] Run the per-doc pipeline on `update-zskills.md`, `create-worktree.md`, `briefing.md`, `zskills-dashboard.md`, `doc.md`.
- [ ] `create-worktree.md`: drop the made-up "Two-Tier Contract / Tier 1 / Tier 2" terminology.
- [ ] `zskills-dashboard.md`: drop "stdlib-only Python HTTP server / atomic writes / process identity checks" impl tips.
- [ ] `update-zskills.md`: the **only** base-doc reference to the block-diagram add-ons that is allowed — a brief note that an install flag exists to add them. Do **not** document the add-on skills themselves (see Phase 6).

**Acceptance:**
- [ ] Fact sheet + clean verdict ledger per doc; banned-term grep clean; ≥3 citation spot-checks per doc.

## Phase 6 — Nav: Internal Skills section (catalog-generator change) + docs/skills/README.md

_Status: pending._ **This phase is NOT docs-only** — the viewer nav is machine-generated, so an "Internal Skills" section requires generator + test code changes. Block-diagram exclusion already holds for free.

**The mechanism (verified against source):** the nav comes from `docs/DocsRegistry.js`, generated by `scripts/build-catalog.sh` (header: *DO NOT EDIT BY HAND*) from three hard-coded sections — `Start here`, `Guides`, `Skills` (`build-catalog.sh` `SECTIONS`, ~L66-70). `tests/test-doc-viewer-catalog.sh` asserts the section list is **exactly** `Start here Guides Skills` (L95) and byte-diffs `DocsRegistry.js` against a fresh generator run (drift gate, L86-92). So a 4th section is a **code change**, and the test must move with it.

- [ ] **Generator:** extend `scripts/build-catalog.sh` to emit an "Internal Skills" section, classifying a `docs/skills/<name>.md` as internal when `skills/<name>/SKILL.md` carries `user-invocable: false` (enumerate frontmatter — do not hand-curate a list). Regenerate `docs/DocsRegistry.js` *via the generator*, never by hand.
- [ ] **Render:** confirm `docs/docs-app.js` renders the new section header like the others (it iterates `DOCS_CATALOG` sections, one header each); add a path only if the design needs it.
- [ ] **Test:** update `tests/test-doc-viewer-catalog.sh` `EXPECTED_ORDER` to include `Internal Skills` and adjust the entry-count assertions. Legit per "never weaken tests" — the expectation genuinely changed; this is **in-scope work, not an afterthought**.
- [ ] **Membership branches on live state:** `/land-pr` is internal today; `/manual-testing` joins **iff #1012 has merged** at execution time (it makes manual-testing `user-invocable: false`). Branch on the live frontmatter enumeration — never a hardcoded count.
- [ ] **`docs/skills/README.md`:** rewrite the lede and recompute the counts from `grep -rl 'user-invocable: false' skills/*/SKILL.md`. The current "23 user-facing + 2 internal" is **already wrong** (only `/land-pr` is internal today) — fix to ground truth, do not match the stale claim.
- [ ] **Block-diagram: no action.** `build-catalog.sh` and `test-doc-viewer-catalog.sh` already exclude `docs/skills/block-diagram/`; just confirm the invariant. The only base mention stays `update-zskills.md`'s install-flag note (Phase 5).

**Acceptance:**
- [ ] `bash scripts/build-catalog.sh` regenerates `docs/DocsRegistry.js` with an "Internal Skills" section; the regenerated registry is committed in the same PR (drift gate green).
- [ ] `bash tests/test-doc-viewer-catalog.sh` passes with the updated `EXPECTED_ORDER`.
- [ ] The Internal section contains exactly the live `user-invocable: false` set (`/land-pr`, plus `/manual-testing` iff #1012 merged); those docs are absent from the "Skills" section.
- [ ] `docs/skills/README.md` counts match `grep -rl 'user-invocable: false' skills/*/SKILL.md`; banned-term grep clean.
- [ ] `grep -q 'docs/skills/block-diagram/' docs/DocsRegistry.js` returns nothing (exclusion invariant holds).

## Phase 7 — Guides (secondary): README, installing-zskills, switching-install-lanes, tracking-overview, inspecting-and-monitoring, workflows

_Status: pending._ Guides are less broken than skill docs but carry the heaviest hedge-soup (`installing-zskills`) and the worst single doc (`tracking-overview`). `inspecting-and-monitoring.md` is rewritten **except** its dev/prod-URL + install-path content (→ #1002).

- [ ] `tracking-overview.md`: reconcile against `docs/tracking/TRACKING_NAMING.md` + current hook — the flat-vs-per-pipeline-subdir layout examples are wrong; the "suffix matching" section is obsolete; the "enforced on commit/cherry-pick/push identically" claim needs the on-main scoping checked (R2). Likely a near-rewrite.
- [ ] `installing-zskills.md`: de-hedge the lede (R3) — "pick one lane; you can't run both" without "end-state/not-tiered/not-deprecated" defensiveness; replace materialiser/sentinel/`${CLAUDE_PLUGIN_ROOT}` prose with plain user-facing behavior.
- [ ] `switching-install-lanes.md`: strip "D25 / lock-LAST / basename-gated / sentinel-gated" vocabulary.
- [ ] `workflows.md`: the dashed-`--auto`-belongs-to-`/land-pr` statement is actually **correct** (CLAUDE.md flag convention: `/land-pr` is the one skill taking `--auto` with dashes). The real defect is the over-broad "never type a dashed flag yourself" generalization — carve out the user-facing `--force` (`/do`, `/quickfix`, `/work-on-plans`, `/cleanup-merged`) and `--rounds N` (`/do`).
- [ ] `README.md` (guides index): align with the rewritten guides.

**Acceptance:**
- [ ] Fact sheet + clean verdict ledger per guide; banned-term grep clean; `tracking-overview` layout examples match `TRACKING_NAMING.md`; #1002-owned content left untouched and noted.

## Phase 8 — Discrepancy review & consolidation

_Status: pending._ Close the loop on the second deliverable.

- [ ] Consolidate `SKILL_DISCREPANCIES.md`: dedupe, ensure every entry carries an intent hypothesis + a user-ruling request.
- [ ] Present to the user for ruling. For each "surprising" (likely-bug) entry the user confirms, file a GitHub issue (skill-fix, not doc). For "intentional" entries, add a one-line doc note only where user-relevant.
- [ ] Final consistency pass: every doc's companion section still agrees with COMPANIONS.md after all rewrites.

**Acceptance:**
- [ ] `SKILL_DISCREPANCIES.md` reviewed with the user; issues filed for confirmed bugs.
- [ ] No catalog doc contradicts another on companion skills or shared command grammar.
- [ ] `bash tests/run-all.sh` passes (doc-conformance / link-check suites green).

## Drift Log

No completed phases — the plan was drafted (PR #1021) and immediately refined; all phases are reviewed as remaining. This log records the structural changes the refinement round made vs. the drafted version.

| Area | Drafted | After refinement | Why |
|------|---------|------------------|-----|
| Phase 6 | "Add Internal Skills section to nav" as a docs-only edit | Re-scoped to a generator + test code change (`build-catalog.sh`, `docs-app.js`, `test-doc-viewer-catalog.sh`) | Nav is generated into `docs/DocsRegistry.js` (DO-NOT-EDIT); a 4th section needs code + the exact-3-section test moved |
| Scope | 25 docs claimed; phases enumerated 24 | `doc.md` added to Phase 5 | `doc.md`/`skills/doc/` existed but was unassigned |
| Anti-skim pipeline | "fact sheet = proof of read; skimmers can't fabricate" | claim↔quote adjacency + `path:line:"quote"` format + mechanical sed-check (100%) + semantic sample biased to universals | A real line can be grepped and mischaracterized; existence ≠ correspondence |
| Rubric R2/R4 | R2 "dedicated search"; R4 "delete mode narration" | R2 given a concrete checklist; R4 clarified to flatten narration but keep TRUE carve-outs | R2/R4 pulled against each other; risked deleting real carve-outs (e.g. `do.md` content-only skip) |
| Per-phase mechanics | (none on landing/catalog) | serial landing, H1→catalog-regen, parity gate, `run-all.sh` gate | CLAUDE.md serial-`requires.land-pr` rule; catalog drift gate; `test-doc-viewer-parity.sh` |
| Refs | `#1014` cited as the landing PR | corrected to PR #1016 / `908c403` (#1014 is the issue) | the plan's own R1 — stale reference |
| Phase 0 | banned-terms as prose; usage-mining unbounded | `banned-terms.txt` grep artifact; bounded streaming over 725 MB of transcripts | acceptance must be mechanically checkable; mining was a hidden swamp |
| Discrepancies | unbounded intake | confidence threshold + ~20 soft cap | avoid a Phase-8 judgment swamp |

## Plan Review

**Refinement process:** `/refine-plan` with 1 round of adversarial review (reviewer + devil's-advocate, both grounded in the live repo; orchestrator verified every load-bearing finding against source before baking).
**Convergence:** Converged at round 1 — all substantive findings dispositioned (fixed or justified); the two CRITICAL findings (Phase 6 catalog generation, missing `doc.md`) and the HIGH anti-skim hole were verified true and fixed.
**Remaining concerns:** Execution is a large multi-PR effort; the plan is orchestrator-executed (not `/run-plan`) and lands phases strictly serially. #1002 / #1012 are OPEN — Phase 6 (manual-testing nav) and Phase 7 (inspecting-and-monitoring URLs) branch on their merge state at execution time.

### Round History
| Round | Reviewer | Devil's Advocate | Substantive | Resolved |
|-------|----------|------------------|-------------|----------|
| 1 | 11 findings | 9 findings | ~13 (deduped) | all fixed or justified |

**Verified-then-fixed (load-bearing):** Phase 6 catalog generation (`DocsRegistry.js` generated, `EXPECTED_ORDER='Start here Guides Skills'`); `doc.md` unassigned; only `/land-pr` is `user-invocable: false` + #1012 OPEN; `#1014`→#1016; parity gate real; block-diagram already excluded.
**Justified — not acted on:** "forbidden-literals fires on docs" (does not — targets `skills/**`); "context exhaustion 3×25" (sub-agent contexts are separate; per-phase grouping bounds it); "#1020 as worklist" (already treated as expired sample).
