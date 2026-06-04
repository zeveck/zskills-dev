# /land-pr

> **An internal helper — you don't call this one directly.** `/land-pr` is
> marked `user-invocable: false`, which means typing it at the slash prompt
> gets you nowhere. Other skills dispatch it behind the scenes when they need
> to ship a branch.
>
> **To land a branch as a PR, use [`/commit pr`](commit.md)** (or one of the
> other callers below). `/commit pr` figures out the title and body, then runs
> `/land-pr` for you with the right setup.

## What it does

When a skill has a feature branch that's ready to ship, it hands the branch to
`/land-pr`, which carries it the rest of the way: it rebases the branch onto
`main`, pushes it, creates the PR (or picks up an existing one), watches CI
until the checks finish, and — when the caller asked to auto-merge — merges it
and brings your local `main` up to date. If `main` moves while CI is running,
`/land-pr` rebases and re-checks on its own so the PR doesn't get stuck waiting.
You don't see any of this directly; you see the finished PR (and, with
auto-merge, the merged result) reported back by whichever skill you ran.

## Who runs it for you

Eight skills dispatch `/land-pr`. Reach for whichever fits your task — they all
land the branch through this same helper:

- [`/commit pr`](commit.md) — the most direct way to ship a branch you've
  already prepared
- [`/do pr`](do.md) — a single change, done in an isolated worktree
- [`/fix-issues pr`](fix-issues.md) — work through a backlog of issues
- [`/run-plan`](run-plan.md) — execute a multi-phase plan
- [`/draft-plan`](draft-plan.md) — land a newly drafted plan
- [`/refine-plan`](refine-plan.md) — land changes to an in-progress plan
- [`/draft-tests`](draft-tests.md) — land test specifications into a plan

## See also

- [`/commit`](commit.md) — the user-facing skill that ships a branch for you
- [Workflows](../guides/workflows.md) — when each landing skill is the right pick
