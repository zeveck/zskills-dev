# /add-example

> Create an example model for one or more block types. Handles model file construction, registration, unit + codegen tests, screenshots, and verification.

## Usage

```
/add-example <block-type(s)> [concept hint]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `block-type(s)` | Yes | Which block(s) the example must feature (comma-separated for batch) |
| `concept hint` | No | Real-world model concept (e.g., "PID temperature control") |

## Examples

```
/add-example Integrator
/add-example Integrator,Derivative PID temperature control
/add-example Scope real-time signal monitoring
```

## Common Patterns

- **Single block example:** `/add-example Integrator` -- create an example featuring the Integrator block
- **Multi-block example:** `/add-example Integrator,Derivative PID temperature control` -- create an example that showcases multiple blocks in a real-world context
- **After /add-block:** typically follows `/add-block` to create additional examples for newly added blocks

## Tips & Gotchas

- All implementation happens in a pre-created worktree via `ensure-worktree.sh`
- When dispatched from `/add-block`, the worktree gate is a no-op (parent's worktree is reused)
- The full workflow covers: research, model file construction, registration, unit tests, codegen tests, screenshots, and verification
