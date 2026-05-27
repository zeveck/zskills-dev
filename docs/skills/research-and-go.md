# /research-and-go

> Full pipeline: decompose a broad goal into sub-plans, draft each with adversarial review, then execute all of them autonomously via `/run-plan`. One command, walk away.

## Usage

```
/research-and-go <description>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `description` | Yes | The broad goal, in natural language |

## Examples

```
/research-and-go Build a complete physics simulation engine
/research-and-go Add dark mode support with theme persistence
/research-and-go Implement undo/redo for the block editor with state snapshots
```

## Common Patterns

- **Full autonomous execution:** `/research-and-go Build an RPG` -- decompose, plan, review, and execute everything
- **When you trust the pipeline:** use when you want end-to-end execution from a single description without checkpoints

## Tips & Gotchas

- Must run at top level -- internally dispatches multiple sub-agents
- Same as `/research-and-plan` but continues into execution via `/run-plan` after planning
- For more control, use `/research-and-plan` (plan only) then `/run-plan` (execute) separately
- The planning phase uses adversarial review -- multiple agents research, draft, and review each sub-plan
- Execution happens via `/run-plan` for each sub-plan in dependency order
