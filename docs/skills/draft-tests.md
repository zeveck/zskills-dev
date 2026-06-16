# /draft-tests

> Drafts test specifications into an existing plan's pending phases through adversarial review. Adds a `### Tests` subsection to each phase that still needs work; already-completed phases are never touched. Sister skill to `/draft-plan`, scoped to test specs.

<details class="flow-cmd" open>
<summary>How it runs — test specs into a plan</summary>

<div class="flow">
<div class="flow-step"><p>The <strong>original agent</strong> reads the plan's pending phases — completed phases are never touched</p></div>
<div class="flow-step"><p>A <strong>QE-reviewer subagent</strong> and a <strong>devil's-advocate subagent</strong> draft the test specs</p></div>
<div class="flow-step"><p>A <strong>refiner subagent</strong> sharpens them, looping until converged</p></div>
<div class="flow-step"><p>The <strong>original agent</strong> writes a Tests subsection into each pending phase</p></div>
</div>

</details>

## What it does

`/draft-tests` takes a plan file — the kind `/draft-plan` produces — and writes test specifications into it. For every phase that is still pending, it appends a `### Tests` subsection describing what that phase should be tested for. It then pressure-tests those specs through several rounds of adversarial review and refinement, the same way `/draft-plan` pressure-tests a plan, until the specs hold up.

The test specs live inside the plan itself, riding along in the phases that `/run-plan` later executes. There is no separate test document and no extra setup for `/run-plan` — the implementing agent that runs each phase simply finds the `### Tests` subsection already there. The reader of those specs is that agent, not a human, so the specs are written for it.

Phases that are already completed are never modified — `/draft-tests` only adds specs to pending work. If it notices that a completed phase is missing test coverage, it does not edit that phase; instead it adds a new phase at the end of the plan that backfills tests for the completed work, leaving everything that was already in the plan intact.

`/draft-tests` is the test-spec member of the plan-authoring family. Where `/draft-plan` drafts the plan and `/refine-plan` adjusts a plan mid-flight, `/draft-tests` is scoped narrowly to adding test specifications — same adversarial-review approach, applied only to the test specs.

## Usage

```
/draft-tests <plan-file> [rounds N] [auto] [guidance...]
```

`/draft-tests` runs at the top level (typed as a slash command or dispatched via the Skill tool); it cannot run as a subagent because it internally launches its own review agents.

## Typical usage

The common form is a plan path, optionally with focus guidance:

```
/draft-tests plans/FEATURE.md
/draft-tests FEATURE.md
/draft-tests plans/FEATURE.md rounds 4
/draft-tests plans/FOO.md focus on integration tests
/draft-tests plans/FOO.md rounds 3 emphasize property-based coverage
```

A bare plan name (no slash) is resolved against the project's plans directory, so `/draft-tests FEATURE.md` reads `FEATURE.md` from there. Any extra words after the plan file and recognized options are treated as guidance that steers what the review focuses on.

## Companion skills

- **`/draft-plan`** — the sister skill. `/draft-plan` drafts the plan; `/draft-tests` adds the test specs to it. Same adversarial-review approach, scoped to test specs. Run `/draft-tests` on a plan `/draft-plan` produced.
- **`/run-plan`** — what executes the plan afterward. The test specs `/draft-tests` writes ride along inside the phases `/run-plan` runs, so the implementing agent picks them up automatically.
- **`/refine-plan`** — the other plan-adjusting skill. `/refine-plan` adjusts a plan mid-flight; `/draft-tests` is the narrower tool that only adds test specs. Both leave completed phases untouched.
- **`/do`** — for one-off changes that don't need a plan at all; reach for it instead of the plan-authoring family when the work is a single pass.

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `plan-file` | Yes | Path to the existing plan file. A path containing `/` is used as-is; a bare name resolves against the project's plans directory. |
| `rounds N` | No | Maximum number of review/refine cycles. Defaults to 3. |
| `auto` | No | After the spec-augmented plan is committed, open a pull request and watch CI. Does NOT auto-merge; see `automerge`. |
| `automerge` | No | Same as `auto`, plus auto-merge the PR once CI passes. Implies `auto`. |
| `guidance` | No | Any extra words become focus guidance that steers what the review pressure-tests (e.g. "focus on integration tests"). |

The plan file is detected as the first argument that contains `/` or ends in `.md`. `rounds` must be followed by a number to count; `rounds` with no number after it is treated as guidance. The `auto` token is matched case-insensitively as a standalone word. Anything left over is joined into the guidance text — guidance shapes what the review looks at, it is not taken as fact, so the same verify-before-acting discipline still applies.

If no plan file is found, `/draft-tests` reports the usage line and stops.

## Examples

```
/draft-tests plans/FEATURE.md
/draft-tests plans/FEATURE.md rounds 4
/draft-tests FEATURE.md
/draft-tests plans/FOO.md focus on integration tests
/draft-tests plans/FOO.md rounds 3 emphasize property-based coverage
/draft-tests plans/FEATURE.md auto
```

## Common Patterns

- **Add tests after drafting a plan:** `/draft-tests plans/X.md` — run it on a freshly drafted plan to add test specs before `/run-plan` executes it.
- **Steer the focus:** `/draft-tests plans/X.md focus on error handling and edge cases` — guide what the review pressure-tests.
- **More review depth:** `/draft-tests plans/X.md rounds 5` — allow more review/refine cycles for a thorny test surface.
- **Draft and ship:** `/draft-tests plans/X.md automerge` — commit the spec-augmented plan, open a PR, and auto-merge it once CI passes.

## Tips & Gotchas

- `/draft-tests` runs at the top level — it launches its own review agents, so it can't run as a subagent. Type it as a slash command or dispatch it via the Skill tool.
- Completed phases are never modified. A gap in already-completed work is surfaced as a new backfill phase at the end of the plan, not by editing the finished phases.
- The test specs go inside the plan's phases; there is no separate test document to maintain and nothing extra to wire up for `/run-plan`.
- Sections after the last phase are left exactly as they were, so trailing notes and appendices survive untouched.
- `auto` opens a PR and watches CI but does not merge; `automerge` does both. The same tokens are used by `/draft-plan`, `/run-plan`, `/do`, `/fix-issues`, and `/refine-plan`. Neither skips or shortens the review.
- `auto` runs unattended but does not merge; use `automerge` for unattended + auto-merge.
