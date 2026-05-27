# /cleanup-merged

> Post-PR-merge local normalization: fetch-and-prune origin, switch off merged feature branches, pull main, and delete local branches whose upstream is gone or whose PR has merged.

## Usage

```
/cleanup-merged [--dry-run | -n] [--review]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `--dry-run` / `-n` | No | Report what would happen without modifying anything |
| `--review` | No | Per-branch merit-based classification with interactive picker |

## Examples

```
/cleanup-merged
/cleanup-merged --dry-run
/cleanup-merged -n
/cleanup-merged --review
```

## Common Patterns

- **After merging a PR:** `/cleanup-merged` -- fetch, switch to main, pull, delete merged branches
- **Preview first:** `/cleanup-merged --dry-run` -- see what would be deleted before committing
- **Thorough cleanup:** `/cleanup-merged --review` -- classify every branch and worktree, then pick what to clean

## Tips & Gotchas

- Safe to run any time -- bails on a dirty working tree
- Never deletes a branch with unpushed commits
- `--dry-run` and `--review` are mutually exclusive
- Review mode classifies branches per merit rules and presents an interactive picker
- Uses `gh` for PR status checks when available; falls back gracefully without it
