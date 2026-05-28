# /cleanup-merged

> Post-PR-merge local normalization: fetch-and-prune origin, switch off merged feature branches, pull main, and delete local branches whose upstream is gone or whose PR has merged. Preview by default.

## Usage

```
/cleanup-merged              preview local branches
/cleanup-merged apply        execute local deletions
/cleanup-merged remote       preview remote branch deletions
/cleanup-merged remote apply execute remote deletions
/cleanup-merged all          preview both local + remote
/cleanup-merged all apply    execute both
```

## Positional Tokens

| Token | Description |
|-------|-------------|
| `apply` | Execute the deletions shown in preview |
| `remote` | Scope to remote branches (requires `gh`) |
| `all` | Scope to both local + remote branches |

## Protected Branches

Configure branches that should never be deleted in `.claude/zskills-config.json`:

```json
{ "cleanup": { "protected_branches": ["docs/run-order-guide"] } }
```

Protected branches are marked `PROTECTED (config)` in preview and skipped automatically during apply.

## Examples

```
/cleanup-merged                  preview what would be deleted locally
/cleanup-merged apply            delete merged local branches
/cleanup-merged remote           preview stale remote branches
/cleanup-merged remote apply     delete merged remote branches
/cleanup-merged all              preview everything
/cleanup-merged all apply        clean up everything
```

## Common Patterns

- **After merging a PR:** `/cleanup-merged` -- preview, then `/cleanup-merged apply` to execute
- **Full cleanup:** `/cleanup-merged all apply` -- local + remote in one pass
- **Remote only:** `/cleanup-merged remote apply` -- clean stale remote branches without touching local

## Tips & Gotchas

- Preview is the default -- safe to run any time
- Bails on a dirty working tree
- Never deletes a branch with unpushed commits
- Remote cleanup requires `gh` for PR-state gating (never deletes branches with open PRs)
- Protected branches from config are always skipped
- Legacy `--dry-run` and `--review` flags work as aliases for one release cycle
