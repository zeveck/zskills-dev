# /verify-changes

> Verify all recent changes: review diffs, check that unit/e2e tests cover the changes, run all tests, manually verify UI changes with playwright-cli, fix problems, re-verify until clean, then report with recommendations.

## Usage

```
/verify-changes [scope: worktree | branch | last [N]]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `worktree` | No | Verify changes in the current worktree |
| `branch` | No | Verify all commits on the current branch |
| `last N` | No | Verify the last N commits |

When no scope is given, defaults to verifying the current working tree changes.

## Examples

```
/verify-changes
/verify-changes worktree
/verify-changes branch
/verify-changes last 3
```

## Common Patterns

- **Pre-commit verification:** `/verify-changes` -- verify everything before committing
- **Worktree review:** `/verify-changes worktree` -- review all changes in a worktree before landing
- **Branch audit:** `/verify-changes branch` -- verify all commits on the current feature branch

## Tips & Gotchas

- When invoked at top level (with the Agent tool), dispatches fresh sub-agents for each verification phase -- strongest fresh-eyes guarantee
- When invoked from within a verifier subagent, falls through to inline single-context verification
- The 7-phase verification covers: diff review, test coverage audit, full test suite, manual UI verification (if applicable), fix problems, re-verify, report
- Never verifies from memory -- always reads actual diffs and runs actual tests
- Dispatched verification agents use `subagent_type: "verifier"` with Layer 3 response validation
- UI changes require visual verification via playwright-cli screenshots and interactive testing
- The skill resolves `$FULL_TEST_CMD` from config -- does not hardcode test commands
