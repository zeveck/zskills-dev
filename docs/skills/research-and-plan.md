# /research-and-plan

> Decompose a broad goal into a sequence of executable sub-plans. Researches the domain, identifies sub-problems and dependencies, produces a meta-plan whose phases each delegate to `/run-plan`.

## Usage

```
/research-and-plan [output FILE] [auto] <broad goal description>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `description` | Yes | The broad goal, in natural language |
| `output FILE` | No | Meta-plan output path (default: auto-derived `<slug>_META.md`) |
| `auto` | No | Skip the decomposition confirmation checkpoint |

## Examples

```
/research-and-plan Build a complete physics simulation engine
/research-and-plan output plans/PHYSICS_META.md Build physics simulation
/research-and-plan auto Implement undo/redo for the block editor
```

## Common Patterns

- **Standard decomposition:** `/research-and-plan Build physics blocks` -- research, decompose, draft each sub-plan
- **Custom output:** `/research-and-plan output plans/PHYSICS_META.md Build physics blocks`
- **Review before execution:** use `/research-and-plan` to produce the meta-plan, review it, then `/run-plan` to execute

## Tips & Gotchas

- Must run at top level -- internally dispatches reviewer, devil's-advocate, and refiner sub-agents
- The output is a meta-plan whose phases are pure delegation -- each phase invokes `/run-plan` on a sub-plan
- No drafting happens during execution -- all sub-plans are drafted upfront
- For fully autonomous operation (plan + execute), use `/research-and-go` instead
- If escalated from `/draft-plan` (the goal is too broad for a single plan), the escalation context is preserved
