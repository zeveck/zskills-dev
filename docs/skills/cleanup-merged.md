# /cleanup-merged

> Post-PR-merge local normalization: fetch-and-prune origin, switch off merged feature branches, pull main, and delete local branches whose upstream is gone, whose PR has merged, or whose tip is fully contained in main (0 commits ahead). Preview by default.

## Usage

```
/cleanup-merged                       preview local branches
/cleanup-merged apply                 execute local deletions
/cleanup-merged local                 preview local (explicit local token)
/cleanup-merged local apply           execute local deletions
/cleanup-merged remote                preview remote branch deletions
/cleanup-merged remote apply          execute remote deletions
/cleanup-merged all                   preview both local + remote
/cleanup-merged all apply             execute both
/cleanup-merged apply <br> <br>...    narrow to NAMED local branches, then apply
/cleanup-merged remote apply <br>...  narrow to NAMED remote branches, then apply
/cleanup-merged apply --force <br>... override merged-check + unpushed guard for NAMED branches
```

## Positional Tokens

| Token | Description |
|-------|-------------|
| `apply` | Execute the deletions shown in preview |
| `local` | Scope to local branches (the default; token exists for symmetry) |
| `remote` | Scope to remote branches (requires `gh`) |
| `all` | Scope to both local + remote branches |
| `<branch>` | Any non-keyword positional is a branch NAME — narrows the candidate set to only the named branches. |

## Flags

| Flag | Description |
|------|-------------|
| `--force` | Override the merged-check + unpushed guard, ONLY for branches you explicitly name. NEVER overrides protected-skip. Dashed form (issue #810) — matches `/do`, `/work-on-plans`, `/quickfix`. |

## Branch Names (narrowing)

Pass explicit branch names to consider ONLY those branches instead of
scanning all refs. Names do **not** bypass safety: each named branch is
still subject to merged-confirmation, the unpushed-commits guard, and the
protected-skip. Names without `apply` are preview-only.

- `local` (or default) names route to local deletion (`git branch -d`,
  `-D` only under `--force` for unmerged).
- `remote` names route to remote deletion (`git push origin --delete`).

## --force

`--force` overrides ONLY the merged-check and the unpushed-commits guard,
and ONLY for branches you explicitly name. It lets you delete a named
branch that is not yet confirmed merged.

**`--force` can NEVER delete a config-protected branch.** Naming a protected
branch (with or without `--force`) emits a loud
`PROTECTED (config) ... — refusing to delete even with --force` notice and
skips it. The protected-skip is sacrosanct — no token or naming
combination overrides it.

## Protected Branches

Configure branches that should never be deleted in `.claude/zskills-config.json`:

```json
{ "cleanup": { "protected_branches": ["docs/run-order-guide"] } }
```

Protected branches are marked `PROTECTED (config)` in preview and skipped automatically during apply — including when named explicitly with `--force`.

## Examples

```
/cleanup-merged                  preview what would be deleted locally
/cleanup-merged apply            delete merged local branches
/cleanup-merged remote           preview stale remote branches
/cleanup-merged remote apply     delete merged remote branches
/cleanup-merged all              preview everything
/cleanup-merged all apply        clean up everything
/cleanup-merged local apply feat/foo feat/bar   delete just those two local branches
/cleanup-merged apply --force feat/wip          delete a named unmerged local branch
```

## Common Patterns

- **After merging a PR:** `/cleanup-merged` -- preview, then `/cleanup-merged apply` to execute
- **Full cleanup:** `/cleanup-merged all apply` -- local + remote in one pass
- **Remote only:** `/cleanup-merged remote apply` -- clean stale remote branches without touching local
- **Pick-and-choose (from dashboard Branches tab):** select branches, copy the emitted `/cleanup-merged local apply <names>` command, run it

## Tips & Gotchas

- Preview is the default -- safe to run any time
- Bails on a dirty working tree
- Never deletes a branch with unpushed commits (unless you name it explicitly with `--force`)
- Remote cleanup requires `gh` for PR-state gating (never deletes branches with open PRs)
- Protected branches from config are always skipped -- `--force` can never override this
- Legacy `--dry-run` and `--review` flags work as aliases for one release cycle
