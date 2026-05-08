---
title: GitLab Support — Planning Prompts (deferred)
created: 2026-04-26
status: deferred
type: prompts-document
---

# GitLab Support — Planning Prompts

**This is not a plan. It is reference material for a future planning round.** Run the prompts inside this document only after the prerequisites below have landed, ideally from a GitLab-hosted project where `glab` is empirically testable.

## Why this document exists

zskills will be used in GitLab environments. Today, roughly 100+ `gh <subcommand>` invocations across 16+ skill files assume GitHub; a consumer on GitLab cannot use zskills as-is without manually adapting every skill that touches PRs or issues.

The work is real, not speculative. But planning it now would produce a stale plan because:

- **Three active plans in `plans/` touch the same surface** this work would build on. Drafting before they land guarantees mass refinement.
- **Empirical glab testing requires a GitLab project.** A shim built entirely in this repo (GitHub-hosted, no GitLab project to PR against) ships with speculative validation. Running the work from a project that actually uses GitLab tests every adapter behavior end-to-end against real glab + real GitLab CI.
- **A first research pass had known staleness risk.** It cited at least one bug report (glab issue #1344) without verifying current resolution status. Every technical claim about glab's surface that any future plan rests on must be re-verified at draft time, not inherited from a stale snapshot.

## Hard prerequisites

These plans must be landed (status: complete) before drafting begins:

- `plans/SCRIPTS_INTO_SKILLS_PLAN.md` — establishes Tier 1 / Tier 2 for skill-owned scripts. The hosting-CLI shim is Tier 1; its location depends on this plan landing.
- `plans/SKILL_FILE_DRIFT_FIX.md` — establishes the canonical config-resolution helper at `skills/update-zskills/scripts/zskills-resolve-config.sh`. Any new config field added by this work reads through that helper.
- `plans/CONSUMER_STUB_CALLOUTS_PLAN.md` — formalizes the consumer stub-callout convention. May turn out to be the natural shape for consumer-overridable hosting-CLI selection; should be checked against once landed.

## Constraints any future plan must respect

- **Single shim, not per-skill switching.** Skills invoke ONE indirection (e.g., `bash hub.sh pr create ...`); the shim layer absorbs gh/glab divergence in one place. No per-skill `if gh: ... else if glab: ...` blocks across the skill bodies. Cleanliness is load-bearing.
- **Both hosts first-class.** "GitLab technically works but functions less well in practice" is a fail. Auto-merge, CI polling, JSON parity, draft MRs, issue lifecycle, log reads — full parity at the user-visible surface, not "works on GitHub, kind of works on GitLab."
- **No jq.** Per `feedback_no_jq_in_skills.md`. JSON normalization between gh and glab uses BASH_REMATCH only.
- **No premature back-compat.** Config schema is the contract. Existing gh-only consumers update their config on next `/update-zskills`. No code-level fallback to old field names.
- **Surface bugs visibly.** If a host CLI has a real limitation, the shim fails loud with a recommended workaround. Don't quietly route around in adapter code; that gets multiplied across every downstream consumer.
- **Active-plan respect.** SCRIPTS_INTO_SKILLS Tier framework, SKILL_FILE_DRIFT_FIX canonical config helper, CONSUMER_STUB_CALLOUTS stub-callout convention — all govern where new code goes, how it's installed, and how consumers customize it.

## Re-verification checklist (run BEFORE accepting prior facts)

The earlier research summary at `/tmp/draft-plan-research-glab-support.md` (if still on disk) is suggestive only. Every claim it makes about glab needs re-verification against the current glab CLI version when planning resumes:

- [ ] `glab` auto-merge: current state of `glab mr merge --when-pipeline-succeeds`. Does the flag work today, or is the API workaround (`glab api projects/:id/merge_requests/:mr_iid -X PUT -f merge_when_pipeline_succeeds=true`) still required? Verify against current glab release notes; do NOT trust prior bug-report citations without checking resolution status.
- [ ] `glab mr view` / `glab issue view` JSON output: does current glab support field selection (e.g., `--json field1,field2`), or only full-doc output? Sample command output, don't trust documentation alone.
- [ ] `glab ci status --live`: exit-code behavior on success / failure / timeout. Is it reliable enough to replace gh's `--watch` semantics?
- [ ] `glab` GraphQL support: still REST-only, or has GraphQL shipped?
- [ ] Issue/MR ID model: what does current glab API return — `.iid`, `.id`, both? What do the gh equivalents return? Ground every JSON-shape claim in actual command output.
- [ ] Draft MRs: behavior of `glab mr create --draft` and `glab mr update --ready` in current version.
- [ ] CI log access on GitLab: replacement story for gh's `gh run view --log-failed`. Does glab expose a clean equivalent, or is it `glab api` to a pipeline-jobs endpoint?
- [ ] Re-grep zskills source: count of `gh <sub>` invocations and their file distribution. Earlier research found 102 across 16 files; the prerequisite plans WILL change file paths and may consolidate / split invocations. Re-verify.

## Recommended approach: `/research-and-plan`

The work is large enough (≥100 call sites, multi-faceted divergence, install + migration + testing concerns) that a single `/draft-plan` would produce vague phases. `/research-and-plan` decomposes broad goals into focused sub-plans with explicit dependency ordering — the right tool for this scale.

### Prompt to run

```
/research-and-plan Add GitLab (glab) support to zskills as a first-class hosting CLI alongside GitHub (gh).

Context: zskills will be used in GitLab environments. Today ~100+ `gh <subcommand>` invocations across 16+ skill files assume GitHub. Per-skill switching logic would bloat skills and violate cleanliness; the design must absorb hosting-CLI divergence in ONE place (a shim or equivalent indirection) so skills stay clean.

Hard constraints (every sub-plan must respect):
- Single shim, not per-skill switching. Skills call one indirection; divergence lives in one place. No per-skill `if gh / else if glab` blocks.
- Both hosts first-class. "GitLab technically works but functions less well in practice" is a fail. Auto-merge, CI polling, JSON parity, draft MRs, issue lifecycle, log reads — full parity at the user-visible surface.
- No jq (per zskills convention). BASH_REMATCH only.
- No premature back-compat. Config schema is the contract.
- Surface bugs visibly. If a CLI has a real limitation, fail loud with a documented workaround; don't quietly route around in adapter code.
- Active-plan respect: SCRIPTS_INTO_SKILLS Tier 1/2 framework, SKILL_FILE_DRIFT_FIX canonical config helper, CONSUMER_STUB_CALLOUTS stub-callout convention.

Open questions for the decomposition to investigate (sub-plans should resolve these, not the meta-plan):
- Where does the shim live? Single Tier 1 script in an owning skill (which skill?), sourceable bash library, or per-domain helpers (PR, issue, CI)?
- Auto-merge: gh and glab both have it. What's the unified contract the shim exposes? What gets polyfilled vs deferred to a doc-pointer-with-workaround?
- CI polling: gh has `gh pr checks --watch`. glab equivalent has different semantics. Unified poll model — what shape?
- JSON normalization: glab returns full docs (no field selection); gh returns selected fields. How is field-extraction normalized through the shim? Per the no-jq rule, BASH_REMATCH for every read.
- Issue/MR ID: GitHub `.number`, GitLab `.iid`. Does the shim canonicalize, or do callers handle?
- Install detection: does `/update-zskills` audit detect either CLI, gate on a config field, or both? What's the new config field's name, location, and migration path for existing gh-only consumers?
- Migration: existing zskills consumers all use gh today. How do they transition? Does the shim default to gh when the field is unset, or does `/update-zskills` backfill?
- Testing: how is the test matrix structured? Mock the shim, run against both real CLIs in CI, or scope tests to the configured CLI per-consumer?

Out of scope:
- Third hosting CLIs (Bitbucket's `bb`, Gitea's `tea`, AWS CodeCommit, etc.). The design should not foreclose them but is not required to deliver them.
- Re-litigating whether to do this. Decided: yes.

Re-verification REQUIRED before any sub-plan drafts:
- glab's current CLI surface (auto-merge, JSON output flags, CI status semantics, GraphQL support, issue/MR ID model, draft-MR support, CI-log access). Prior research is stale.
- Current zskills `gh` invocation count and file distribution after SCRIPTS_INTO_SKILLS, SKILL_FILE_DRIFT_FIX, and CONSUMER_STUB_CALLOUTS land. Re-grep before drafting; do not trust prior counts.

Run from: ideally a GitLab-hosted project that uses zskills, where the shim can be tested empirically against real glab + real GitLab CI. A GitHub-only checkout produces speculative adapters with weak validation.
```

## Alternative fallback: N specific `/draft-plan` prompts

If `/research-and-plan` is overkill (or its decomposition has shipped by the time this work starts), the natural sub-plan shape is approximately:

1. **Hosting-CLI shim infrastructure** — design + implement the indirection layer; resolve the "where does it live" and "what's the contract" questions; ship one or more bash helpers; write the shim's own tests.
2. **Skill-side migration sweep** — convert all `gh <sub>` invocations across skill files to use the shim. Mechanical sweep with re-verified count of call sites.
3. **Install + audit + config integration** — `/update-zskills` audit detects the configured CLI; new config field; migration path for existing gh-only consumers.
4. **Testing matrix and CI** — runs against both real CLIs (or documents why mocking suffices); canary plans validate end-to-end on each host.

If pursuing this route, draft each sub-plan individually with `/draft-plan` at the time, with current research grounding each one. Don't pre-bake answers in the prompt; ship context, withhold answers.

## Where this work should run

A GitLab-hosted project that consumes zskills is the ideal environment:

- The shim's behavior on glab is empirically validated against a real GitLab API and a real GitLab CI pipeline, not speculatively designed.
- The fail-loud-on-limitation approach is verified by actually triggering each limitation in a working environment.
- PR-mode skill flows (auto-merge, CI polling, fix cycles) are exercised against a real GitLab merge-request workflow.
- The "both hosts first-class" parity bar is checkable end-to-end.

Running from this repo (zskills, GitHub-hosted) is feasible but produces weaker validation: shim adapters can be unit-tested against mocked CLI output, but no real GitLab project exists to PR against, so /run-plan PR mode and CI integration cannot be fully exercised.

## Originator context

User Simon Greenwold raised the gh/glab compatibility question in feedback. The initial response scoped it out as "one user has asked, not enough demand." User subsequently clarified that zskills will be used in GitLab environments — the work is real. This document captures the result.

## Tracking

The original `/draft-plan` invocation (tracking ID `glab-support`) was paused at the user-checkpoint and superseded by this document. The fulfillment marker is set to status: superseded so future agents understand the path.

GitHub issue tracking the deferred work: [zskills-dev#67](https://github.com/zeveck/zskills-dev/issues/67) — "GitLab (glab) support — deferred until prerequisite plans land".
