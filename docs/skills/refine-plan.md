# /refine-plan

> Refine an in-progress plan by reviewing its remaining phases against the work that has actually been built. Surfaces stale references, invalidated assumptions, and specification gaps, then refines until the review converges. Completed phases are never modified.

## What it does

`/refine-plan` takes a plan you are partway through executing and brings its **unfinished** phases back in line with reality. Plans drift during execution: the phases you have already shipped may have built something a little different from what was originally written down, while the phases still ahead of you keep referencing the original spec. `/refine-plan` closes that gap — it reviews only the remaining phases against what was *actually* built, not what was *planned*, and rewrites them so the rest of the execution stays accurate.

The work you have already completed is treated as fixed, shipped reality. `/refine-plan` reads it for context but **never changes it** — not a single phase that is already done, not even a heading typo. That immutability is a guarantee you can rely on: the only thing `/refine-plan` edits is the set of phases you have not finished yet.

To do this, it runs an adversarial review of the remaining phases. One pass reviews them for stale references, inconsistencies, mis-sized work, specification gaps, broken dependencies, and acceptance criteria that no longer hold; a second, deliberately skeptical pass hunts for ways the remaining work will fail given what is already built — invalidated assumptions, duplicated work, deferred hard parts, hidden dependencies, scope creep, and integration risks. The findings are then resolved: every finding is either fixed in the plan text or justified with evidence, and the cited evidence is re-checked before any fix is applied. This repeats for a few rounds until the review stops turning up substantive problems.

When it finishes, `/refine-plan` writes the updated plan back to the same file, in place. It appends two new sections so future readers understand what changed: a **Drift Log** documenting where completed phases diverged from the plan as originally drafted, and a **Plan Review** summarizing the rounds of review and any concerns left open. It then points you at `/run-plan` to continue execution.

If the plan has no remaining phases — everything is already done — `/refine-plan` exits cleanly and tells you there is nothing to refine.

## Usage

```
/refine-plan <plan-file> [rounds N] [auto] [guidance...]
```

## Typical usage

The common form is just the plan file: point `/refine-plan` at the plan you are executing and let it review the remaining phases against what has shipped.

```
/refine-plan plans/EXECUTION_MODES.md
/refine-plan plans/FEATURE_PLAN.md rounds 3
/refine-plan plans/FEATURE_PLAN.md the solver API changed since the earlier phases
/refine-plan plans/FEATURE_PLAN.md auto
```

You can add trailing free-text guidance to steer what the review pressure-tests (for example, a known change since an earlier phase landed). Add `auto` to have the refined plan opened as a pull request and merged once it passes CI, instead of leaving it committed for you to land yourself.

## Companion skills

- **`/draft-plan`** — creates the plan in the first place. `/draft-plan` researches and decomposes a goal into a phased plan file; `/refine-plan` adjusts that file once execution is underway.
- **`/run-plan`** — executes the plan, phase by phase. Run `/run-plan` to continue after `/refine-plan` has refreshed the remaining phases — they are sequential steps, not alternatives.
- **`/draft-tests`** — the test-spec sibling in the planning family; authors test specifications that accompany a plan.

The natural flow is `/draft-plan` (create) → `/run-plan` (execute) → `/refine-plan` (refine mid-execution when reality has drifted) → `/run-plan` (resume).

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `plan-file` | Yes | Path to the plan `.md` file to refine. A bare filename is resolved against your plans directory; a path with a `/` is used as-is. |
| `rounds N` | No | Maximum review/refine cycles. Default is 2. The process exits early if a round converges (no substantive new issues). |
| `auto` | No | After the refined plan is committed, open a pull request, monitor CI, and auto-merge. Without `auto`, the refined plan is committed but no PR is opened — you land it yourself. |
| `guidance...` | No | Any trailing free text becomes guidance that steers what the review focuses on. It is treated as priming for the review, not as fact to act on blindly. |

The default of 2 rounds is lighter than `/draft-plan`'s 3, because this is a refinement pass on an existing plan rather than blank-slate creation. The `auto` token mirrors the same token in `/run-plan`, `/do`, `/fix-issues`, `/quickfix`, and `/draft-plan`.

## Examples

```
/refine-plan plans/EXECUTION_MODES.md
/refine-plan plans/EXECUTION_MODES.md rounds 3
/refine-plan THERMAL_PLAN.md
/refine-plan plans/FEATURE.md the solver API changed since the earlier phases
/refine-plan plans/FOO.md rounds 3 expand the audit to all config fields
/refine-plan plans/FEATURE_PLAN.md auto
```

## Common Patterns

- **Mid-execution refresh:** `/refine-plan plans/X.md` — bring the remaining phases in line with what the completed phases actually built.
- **With context:** `/refine-plan plans/X.md the API signature changed since an earlier phase` — steer the review toward a known change.
- **More review rounds:** `/refine-plan plans/X.md rounds 3` — push for an extra adversarial pass on a high-stakes plan.
- **Refine and land:** `/refine-plan plans/X.md auto` — refine, then open and auto-merge the PR.

## Tips & Gotchas

- Completed phases are never modified — they are read-only context, and the refined file preserves them, the frontmatter, the overview, and the progress tracker exactly as they were.
- The review hunts for plans that drifted during execution: completed phases may have built something different from the spec, and remaining phases still reference the original. That gap is exactly what `/refine-plan` exists to close.
- A `## Drift Log` and a `## Plan Review` section are appended to the plan so future readers can see what diverged and how the refinement went.
- If every phase is already complete, `/refine-plan` exits without changes — point it at a plan that still has remaining phases.
- After refining, continue execution with `/run-plan <plan-file>`.
