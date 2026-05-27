# /commit

> Safe commit workflow with optional scope hint. Inventories all changes, classifies related vs. unrelated files, traces dependencies, protects other agents' work, and optionally pushes, lands worktree commits, or opens a PR via `/land-pr`.

## Usage

```
/commit [pr] [scope] [push|land] [auto]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `pr` | No | Push current branch and create a PR to main (must be FIRST token) |
| `scope` | No | Free-text scope hint to guide which files to commit (e.g., `skill updates`, `parser reset button fix`) |
| `push` | No | Commit and push to remote |
| `land` | No | Cherry-pick worktree commits into main (worktree only) |
| `auto` | No | Auto-merge the resulting PR (PR mode only) |

## Subcommands

### `pr`

Push the current branch and create a PR to main. Requires a clean working tree. The `pr` token must be the first argument. Everything after `pr` is the scope hint.

### `push`

Commit all related changes and push to the remote.

### `land`

Cherry-pick worktree commits onto main. Only available when running in a worktree. Handles the full landing flow: cherry-pick, test suite, `.landed` marker.

## Examples

```
/commit
/commit skill updates
/commit push
/commit parser reset button fix push
/commit land
/commit pr
/commit pr fix pr comments
/commit pr auto
```

## Common Patterns

- **Basic commit:** `/commit` -- inventories changes, classifies related vs. unrelated, commits related files
- **Scoped commit:** `/commit skill updates` -- scope hint guides which files are related
- **Commit and push:** `/commit push` -- commit then push to remote
- **Land worktree work:** `/commit land` -- cherry-pick worktree commits to main, run tests, write `.landed` marker
- **Open a PR:** `/commit pr` -- push branch and create a PR
- **PR with auto-merge:** `/commit pr auto` -- push, create PR, request auto-merge

## Tips & Gotchas

- `pr` is recognized ONLY as the first token to prevent false-triggering on scope hints containing "pr"
- When no mode token is supplied, the skill consults `execution.landing` in config
- The skill traces import dependencies -- if file A imports file B and both are uncommitted, both are staged
- Unrelated changes in the working tree are left alone -- only related files are staged
- `auto` is only meaningful in PR mode; it has no effect with `push` or `land`
- `/commit land` dispatches the full landing script: try cherry-pick (no stash), run tests, write `.landed` marker
- Never uses `git add .` or `git add -A` -- stages files by name only
