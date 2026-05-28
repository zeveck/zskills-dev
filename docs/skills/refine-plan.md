# /refine-plan

> Refine an in-progress plan by reviewing remaining phases against completed work. Dispatches reviewer + devil's-advocate agents to surface stale references, invalidated assumptions, and specification gaps, then refines until convergence.

## Usage

```
/refine-plan <plan-file> [rounds N] [auto] [guidance...]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `plan-file` | Yes | Path to the existing plan file |
| `rounds N` | No | Maximum adversarial review rounds |
| `auto` | No | Skip confirmation checkpoints; dispatch `/land-pr` for results |
| `guidance` | No | Additional guidance for the refinement |

## Examples

```
/refine-plan plans/FEATURE_PLAN.md
/refine-plan plans/FEATURE_PLAN.md rounds 5
/refine-plan plans/FEATURE_PLAN.md auto
/refine-plan plans/FEATURE_PLAN.md The solver API changed since Phase 2
```

## Common Patterns

- **Mid-execution refresh:** `/refine-plan plans/X.md` -- update remaining phases based on what was actually built
- **With context:** `/refine-plan plans/X.md The API signature changed in Phase 3`
- **Auto (from /run-plan):** `/refine-plan plans/X.md auto` -- used when `/run-plan` detects staleness

## Tips & Gotchas

- Must run at top level -- internally dispatches reviewer, devil's-advocate, and refiner sub-agents
- Completed phases are NEVER modified -- they are read-only context, not modification targets
- Immutability is verified mechanically: completed phase sections must be byte-identical before and after
- The key insight: plans drift during execution. Completed phases may have built something different from what was specified. This skill closes that gap.
- Appends a Drift Log and Plan Review section to the plan
- `/run-plan` auto-dispatches `/refine-plan` when it detects staleness markers in the plan
