# /add-block

> Step-by-step guide for adding new block types. Use when the user asks to "add a block", "create a new block", or "implement a block".

## Usage

```
/add-block
```

No arguments -- the skill guides you through the interactive workflow after you provide the block name.

## Workflow

All implementation happens in a pre-created worktree. The skill follows a 13-step process:

0. Research existing similar blocks
1. Define the block interface (ports, parameters)
2. Implement the block class
3. Register the block in the block library
4. Add unit tests
5. Add codegen support
6. Add codegen tests
7. Create an example model
8. Add block documentation
9. Add block explorer entry
10. Take screenshots
11. Verify all tests pass
12. Land the changes

## Examples

```
/add-block
```

Then provide the block name when prompted (e.g., "PID Controller", "Integrator", "Derivative").

## Common Patterns

- **Single block:** `/add-block` then specify one block type
- **After adding:** use `/add-example` to create additional example models for the new block

## Tips & Gotchas

- All 13 steps must be completed -- no partial implementations
- The implementation agent runs in a worktree with `FIRST: cd $WORKTREE_PATH` as a mandatory first action
- Dispatches an implementer subagent for the actual coding work
- The worktree is created via `ensure-worktree.sh`, not manual `git worktree add`
