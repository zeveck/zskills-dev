# Case Study: Draft Plan vs. CODEX Plan for Z Skills Codex Support

## Summary

This case study compares two plans for adding first-class Codex support to
Z Skills while preserving Claude Code support:

- `CODEX_ZSKILLS_REPORT.md`
- `CODEX_PLAN_ZSKILLS_CODEX_SUPPORT_PLAN.md`
- `DRAFT_PLAN_CODEX_ZSKILLS_CODEX_SUPPORT_PLAN.md`

## Methodology

Both plans were produced in Codex 5.5, but with different planning workflows:

- `CODEX_PLAN_ZSKILLS_CODEX_SUPPORT_PLAN.md` was created using Codex planning
  mode.
- `DRAFT_PLAN_CODEX_ZSKILLS_CODEX_SUPPORT_PLAN.md` was created using the
  Z Skills `draft-plan` skill loaded into Codex 5.5.

That distinction matters for interpretation. The comparison is not only between
two plan documents; it is also a small methodology case study comparing native
Codex planning mode against a Z Skills planning workflow running in the same
model family.

`CODEX_ZSKILLS_REPORT.md` should be treated as a shared evidence base for both
plans. It records the observed state of installed Codex skills, identifies the
strongest and weakest Codex fits, and surfaces the Claude-specific assumptions
that the plans attempt to address.

The stronger execution plan is
`DRAFT_PLAN_CODEX_ZSKILLS_CODEX_SUPPORT_PLAN.md`.

The draft plan is more likely to produce a solid and correct outcome because it
turns the goal into an implementable sequence: inventory, renderer, runtime
paths, scheduler bridge, skill conversion, installer flow, conformance tests,
and documentation. It also carries explicit acceptance criteria and a recorded
review disposition.

The CODEX plan is still valuable. It is architecturally sharper in several
places, especially around provider contracts, deterministic load order,
scheduler semantics, and leakage testing. The best path is to use the draft
plan as the execution base and merge in the strongest contracts from the CODEX
plan before implementation.

## Recommendation

Use `DRAFT_PLAN_CODEX_ZSKILLS_CODEX_SUPPORT_PLAN.md` as the working plan.

Before executing it, amend it with four concepts from
`CODEX_PLAN_ZSKILLS_CODEX_SUPPORT_PLAN.md`:

1. A machine-readable provider manifest.
2. Deterministic provider/module load-order rules and load-graph tests.
3. A settled Codex scheduler state layout with jobs, locks, and run records.
4. An earlier proof point for the hard paths: `update-zskills` and `run-plan`.

This combines the draft plan's operational structure with the CODEX plan's
stronger architectural guardrails.

## Why The Draft Plan Is More Likely To Succeed

### It Has A Real Execution Sequence

The draft plan is organized into six dependent phases:

- Compatibility contract and inventory.
- Shared-source markers and generator.
- Runtime paths, config, and scheduler bridge.
- Capability-based orchestration conversion.
- Installer and distribution flow.
- Cross-agent test matrix and documentation.

That sequencing matters. The plan starts by discovering and classifying the
actual Claude-specific anchors before attempting broad conversion. It then
builds rendering mechanics, runtime support, and tests before completing the
installer and documentation flow.

The CODEX plan has phases, but they are broader and less directly taskable. It
is better as an architecture note than as a sprint-ready implementation plan.

### It Defines Concrete Script Surfaces

The draft plan names specific scripts or script classes:

- `scripts/audit-agent-specifics.sh`
- `scripts/render-skills.sh`
- `scripts/zskills-config-path.sh`
- `scripts/zskills-scheduler.sh`
- `scripts/install-zskills.sh --target <claude|codex|both>`

This improves executability. A future implementer can work through tangible
artifacts and tests instead of translating architecture prose into tool surfaces
from scratch.

The CODEX plan identifies important capabilities, but it does not consistently
turn them into concrete file paths, command surfaces, and per-phase acceptance
criteria.

### It Has Better Acceptance Criteria

Each phase in the draft plan includes acceptance criteria. These criteria are
specific enough to drive review:

- New skills or helper assets fail inventory until classified.
- Renderer fixture tests cover target blocks and malformed markers.
- Config resolver tests cover both-config-present cases.
- Scheduler tests use a fake runner and do not invoke Codex.
- Installer dry-run tests prove target-specific file lists.
- Cross-agent conformance fails when operational requirements leak into the
  wrong output.

The CODEX plan includes a strong final acceptance list and good test categories,
but it does not break completion down as rigorously by phase.

### It Fixes Review-Identified Problems

The draft plan includes a "Plan Quality" section showing issues found and fixed
during review. Important fixes include:

- Moving full forbidden-anchor cleanup out of the renderer-only phase.
- Adding a scheduler runner contract.
- Avoiding a hard assumption that Codex delegation is always named
  `spawn_agent`.
- Making config lookup target-aware.
- Adding a concrete installer target surface.
- Defining Codex install locations.

Those fixes are not cosmetic. They directly address likely failure modes in a
Claude-to-Codex support plan.

## Where The CODEX Plan Is Stronger

### Provider Contract As A First-Class Object

The CODEX plan explicitly says provider support should be represented in a
machine-readable manifest instead of inferred from prose. It lists capabilities
such as:

- scheduler
- delegation
- hook/enforcement model
- config paths
- install target
- log/session state
- command surface
- rules/instructions output

The draft plan has compatibility docs and generated artifacts, but it should
make this provider manifest a formal deliverable. Without that, the system could
drift back toward scattered conditionals and adapter prose.

### Deterministic Progressive Disclosure Load Order

The CODEX plan specifies a clear load order:

```text
SKILL.md bootstrap
  -> provider/<provider>.md
  -> modes/<mode>.md
  -> references/*.md as needed
```

This is stronger than relying only on inline source markers. The draft plan's
marker-based approach is easier to land, but it risks becoming noisy in complex
skills unless a load contract or equivalent conformance check exists.

The best synthesis is to allow narrow source markers where they keep shared
prose readable, while still requiring provider contracts and load-graph tests
for complex runtime behavior.

### Scheduler Semantics Are Clearer

The CODEX plan gives a stronger scheduler model:

- structured job data
- idempotency keys
- lock files
- status transitions
- bounded retries
- interrupted job recovery
- allowed skill/mode validation
- human-runnable continuation commands

The draft plan includes most of these ideas, but leaves the queue location
somewhat open. It should settle the durable state layout before implementation,
preferably with separate locations for shared state and Codex runtime state.

### Earlier Hard-Path Validation

The CODEX plan proposes migrating `update-zskills` first and `run-plan` next.
That is a useful architectural proof because those are among the hardest pieces:

- `update-zskills` validates installer, renderer, distribution, and managed
  guidance behavior.
- `run-plan` validates scheduler, delegation, tracking, continuation, and
  verification behavior.

The draft plan converts high-fit skills first and low-fit orchestration skills
last. That lowers early implementation risk, but it may delay discovering that
the architecture is insufficient for the core orchestration workflows.

A better order would preserve the draft plan's phases, but introduce an early
thin-slice proof for `update-zskills` and `run-plan` before broad conversion.

## Risks In The Draft Plan

### Marker Sprawl

The draft plan prefers source markers such as:

```text
<!-- zskills:agent claude -->
<!-- zskills:agent codex -->
<!-- zskills:agent shared -->
```

This is practical, but it can become hard to maintain if large portions of
skills diverge by provider. The plan should set a threshold: narrow differences
can use markers, while larger runtime differences should move to provider or
mode modules.

### "Adapter Snippets" Could Be Too Weak

The draft plan describes agent-specific behavior through "a small compatibility
contract, adapter snippets, generated install targets, and conformance tests."
That is mostly sound, but "adapter snippets" risks preserving the existing
shallow "Codex Port Notes" pattern unless the compatibility contract is
enforceable.

The plan should explicitly say that adapter snippets are generated artifacts or
bounded source fragments, not a free-form prose layer that tries to override
contradictory instructions later in a skill.

### Delayed Validation Of Orchestration

The draft plan converts low-fit orchestration skills last. That is reasonable
for incremental delivery, but it delays the most important correctness test.
Codex support for Z Skills is not proven until orchestration skills work under
Codex constraints.

The plan should include an early vertical slice through `update-zskills` and
`run-plan`, even if full conversion remains later.

## Risks In The CODEX Plan

### Less Executable

The CODEX plan has strong principles and contracts, but fewer concrete
implementation steps. It does not provide the same level of phase-by-phase work
items, dependencies, and acceptance criteria as the draft plan.

That makes it more likely that two implementers would interpret it differently.
For a cross-provider migration, that ambiguity is risky.

### Codex Delegation Is Too Concrete

The CODEX plan specifically names `spawn_agent` in its Codex delegation
contract. That is less future-proof than the draft plan's capability-detected
language:

- use a Codex delegation tool only when the runtime exposes one
- require explicit user permission for delegation or parallel agent work
- otherwise run inline and report freshness mode

The draft language is better because it describes the behavioral contract
rather than one runtime's current tool name.

### Config Lookup Is Not Target-Aware Enough

The CODEX plan gives Codex config precedence as:

1. `.codex/zskills-config.json`
2. `.claude/zskills-config.json`

That is correct for Codex, but incomplete for a dual-target installer. Claude
must prefer `.claude` when both files exist, and Codex must prefer `.codex`.
The draft plan explicitly fixes this with target-aware config lookup.

### Provider Modules May Be Too Heavy Everywhere

The CODEX plan suggests skill-local provider modules for each provider. That is
appropriate for complex runtime behavior, but may be too much ceremony for
skills that only need small path or wording differences.

The draft plan's marker approach is likely easier to land. The final design
should support both:

- source markers for narrow conditional fragments
- provider modules for substantial runtime behavior

## What Each Plan Missed

### Additional Detail The Draft Plan Should Add

- Define the provider manifest schema and make it a generated/tested artifact.
- Define when to use inline markers versus provider modules.
- Settle queue and runtime-state paths before implementation.
- Add an early vertical slice for `update-zskills` and `run-plan`.
- Explicitly say adapter snippets cannot override contradictory shared
  instructions by prose alone.
- Add a provider compatibility status field per skill, generated from the
  manifest or inventory.

### Additional Detail The CODEX Plan Should Add

- Convert its architecture into phase-level work items.
- Add dependencies for each phase.
- Add per-phase acceptance criteria.
- Generalize Codex delegation away from a specific tool name.
- Make config precedence target-aware.
- Specify installer command surfaces and dry-run behavior.
- Define how source markers and provider modules can coexist.

## Combined Plan Shape

A stronger merged plan would look like this:

1. Inventory all Claude-specific and Codex-specific anchors.
2. Define a machine-readable provider manifest.
3. Define source markers for narrow differences and provider modules for large
   runtime differences.
4. Build the renderer and fixture tests.
5. Add target-aware config resolution.
6. Add the Codex external scheduler bridge with settled state paths.
7. Prove the architecture with a thin slice of `update-zskills` and `run-plan`.
8. Convert high-fit and medium-fit skills.
9. Complete orchestration skills.
10. Finish installer, conformance tests, release docs, and public mirror drift
    checks.

This keeps the draft plan's manageable execution flow while forcing the hardest
architecture assumptions to be proven early.

## Second-Agent Review

A second agent independently reviewed both plans and the preliminary assessment.
It agreed with the main conclusion:

- The draft plan is more likely to produce a solid implementation because it is
  operationally stronger.
- The CODEX plan should not be dismissed as merely less actionable because it
  contains concrete contracts the draft should absorb.

The second review specifically highlighted these CODEX plan strengths:

- machine-readable provider manifest
- deterministic load order
- load-graph tests
- clearer scheduler state model
- early focus on `update-zskills` and `run-plan`

It also agreed that the CODEX plan has weaker execution detail, over-specifies
Codex delegation by naming `spawn_agent`, and lacks target-aware config lookup.

## Final Judgment

The draft plan should be the base. It is more complete as an executable plan
and has already incorporated review feedback on several important failure
modes.

The CODEX plan should be treated as an architectural supplement. Its best ideas
should be patched into the draft before implementation, especially the provider
manifest, deterministic load graph, stricter scheduler state model, and early
hard-path validation.

Taken together, the two plans point to a clear answer: do not choose between
execution quality and architectural rigor. Use the draft plan to drive the work,
but strengthen it with the CODEX plan's enforceable contracts.
