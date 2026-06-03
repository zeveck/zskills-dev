# /cleanup-merged

> Catches your local clone up after a PR merges on GitHub: fetch-and-prune,
> switch off a merged feature branch, pull main, and delete local branches
> whose work is already on main. Preview by default.

## What it does

After you merge a pull request on GitHub, your local clone still has the
old branch checked out and the merged feature branches sitting around.
`/cleanup-merged` brings the clone back in sync. It runs three steps in
order: it fetches from `origin` and prunes stale remote-tracking refs; if
you are currently on a merged feature branch it switches you to `main` and
pulls the latest; then it deletes the local feature branches whose work has
already landed on `main`.

A branch counts as "already landed" when any of these is true: its upstream
on the remote is gone, its PR shows as merged, or its tip is fully contained
in `main` (zero commits ahead). Each of those means the branch carries
nothing that isn't already on `main`, so deleting it loses no work.

It is safe to run at any time. The command refuses to do anything if your
working tree is dirty — commit, stash, or discard your changes first — and
it never deletes a branch that has commits you haven't pushed (unless you
name that branch explicitly with `--force`). Running it when there is
nothing to clean up just fetches, confirms `main` is current, and exits.

**Preview by default.** A bare `/cleanup-merged` shows you exactly what it
would delete and ends with a hint to run `/cleanup-merged apply` to execute.
Nothing is deleted until you add `apply`.

If a merged branch is still checked out in a separate worktree,
`/cleanup-merged` removes that worktree first (when it is clean) before
deleting the branch. A worktree with uncommitted changes is left alone with
a warning so you can inspect it yourself, and the main repo's own checkout is
never removed.

## Typical usage

The normal flow is two commands — preview, then apply:

```
/cleanup-merged          preview what would be deleted locally
/cleanup-merged apply    delete the merged local branches
```

You can widen the scope to also remove stale branches on the remote, or
narrow it to specific branches you name:

```
/cleanup-merged local apply            execute local deletions (same as bare apply)
/cleanup-merged all apply              clean up local + remote in one pass
/cleanup-merged remote apply           only the remote, leave local alone
/cleanup-merged apply feat/a feat/b    only these two local branches
/cleanup-merged apply --force feat/wip delete a named branch not yet merged
```

A good cadence: run it after a PR merges, before you start a new feature so
you branch off an up-to-date `main`, or as a sweep when `git branch` shows
stale branches piling up.

## Companion skills

`/cleanup-merged` is the local-clone cleanup step you run **after** any
landing skill has merged a PR. Its companions are the PR-landing skills
themselves:

- **`/commit`, `/do`, `/quickfix`, `/fix-issues`, `/work-on-plans`** — the
  skills that produce and land PRs. Once their PR merges on GitHub, run
  `/cleanup-merged` to bring your clone up to date.
- **`/land-pr`** — the shared helper those skills dispatch to actually open
  and merge the PR (it is dispatched for you, not typed directly).

These deliberately split cleanup by landing style: `/commit land` handles
the post-landing tidy-up for cherry-pick-mode worktrees, while
`/cleanup-merged` handles the post-merge normalization for PR-mode work,
since a PR merge happens asynchronously when a human clicks "merge" on
GitHub.

## Arguments

`/cleanup-merged` takes order-independent positional tokens plus one dashed
flag.

| Token | What it does |
|-------|--------------|
| `apply` | Execute the deletions. Without it, the command only previews. |
| `local` | Limit to local branches. This is the default, so a bare `/cleanup-merged` and `/cleanup-merged local` do the same thing. |
| `remote` | Also delete merged branches on the remote (`origin`). Requires the `gh` CLI for PR-state checking. |
| `all` | Both local and remote. |
| `<branch>` | Any token that isn't a recognized keyword is treated as a branch name and **narrows** the run to only the branches you name. |
| `--force` | Override the merged-check and the unpushed-commits guard — but only for branches you name explicitly. |

**Branch names narrow the candidate set.** When you pass branch names, only
those branches are considered (the full scan is skipped). Naming a branch
does not bypass safety: each named branch is still checked for merge status,
for unpushed commits, and against the protected list. Names without `apply`
preview only.

**`--force` is narrow on purpose.** It lets you delete a branch you named
that isn't yet confirmed merged, by overriding only the merged-check and the
unpushed-commits guard. It has no effect on branches you didn't name (the
full-scan path ignores it).

**Protected branches are never deleted.** List branches you want kept under
`cleanup.protected_branches` in `.claude/zskills-config.json`:

```json
{ "cleanup": { "protected_branches": ["docs/run-order-guide"] } }
```

A protected branch is marked `PROTECTED (config)` in the preview and skipped
during apply. This is sacrosanct — naming a protected branch, even with
`--force`, just prints a refusal notice and skips it. No token or
combination of flags can delete a config-protected branch.

The older `--dry-run` / `-n` and `--review` flags still work as aliases (for
one release cycle, removed after 2026-07-01) and print a deprecation notice
pointing you at the current form.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success, or preview complete |
| 1 | `git` is not installed |
| 2 | Bad argument |
| 3 | Working tree is dirty — refused to proceed |
| 4 | `git fetch` failed |
| 5 | `git checkout` or `git pull` failed |
