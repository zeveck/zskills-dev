# /quickfix

> Turn a small change on your main branch into a one-commit pull request,
> without setting up a separate working directory.

## What it does

`/quickfix` takes the change you have on your main checkout and ships it as a
single-commit PR. It stays on main the whole time: it creates a feature branch
in place, commits your change onto it, pushes the branch, opens the PR, watches
CI, and fixes failures if any come up. There is no separate worktree and no
cherry-pick step.

It works two ways, and figures out which one you mean automatically by looking
at your working tree before it does anything:

- If you have uncommitted edits on main and you give a description, `/quickfix`
  picks up those edits and commits them under your description.
- If your tree is clean and you give a description, `/quickfix` has an agent
  make the change for you, then commits it.

Either way you give a description (with a clean tree the description is the only
input, so it is required). The change then runs through the same path: the skill
sizes up the request, has a fresh agent review the plan, commits, verifies the
result, pushes, opens the PR, and watches CI — handing the PR creation,
CI-watching, and any fix-up cycle to `/land-pr` behind the scenes.

A couple of things to expect along the way:

- Before committing, `/quickfix` runs your project's test command. If the tests
  fail, it leaves your edits in your working tree, switches you back to your
  starting branch, and removes the feature branch it created — so nothing is
  lost and you are back where you started.
- It also has a separate verification pass that checks your change is actually
  sound (the same check `/verify-changes` performs) before pushing.
- If your request looks bigger than one quick fix — several files named in the
  description, an "add feature"/"rewrite"/"refactor" verb, two unrelated things
  joined by "and", or a reference to an existing plan file — `/quickfix` stops
  and points you at a better-suited skill (`/draft-plan` or `/run-plan`)
  instead of forging ahead. You can override that with `--force`.

`/quickfix` is built for PR-style projects. If your project is configured to
land work a different way, `/quickfix` won't fight it: it prints a short note
redirecting you to `/do` (for worktree-based projects) or `/commit` (for
direct-to-main projects) and stops, so you can re-run the right skill.

## Typical usage

The common shape is a description, optionally followed by `auto` to merge the
PR once CI is green:

```
/quickfix Fix README typo
/quickfix Fix the broken link in docs/intro.md auto
/quickfix Update CHANGELOG with v0.5 release notes
```

Reach for `/quickfix` when the change is small enough that spinning up an
isolated worktree would be more ceremony than the change is worth, but you still
want it to land as a reviewable PR.

`/quickfix` and `/do` are co-equal peers — same lifecycle, same one-commit-PR
result, both landing through `/land-pr`. The only real difference is where the
work happens: `/quickfix` works in place on main, while `/do` works in an
isolated worktree. Pick based on your project's policy, not on how big the task
is. Projects that protect main require the worktree isolation `/do` gives, so
they use `/do`; other projects can use either.

## Companion skills

- **`/do`** — the peer of `/quickfix`. Same lifecycle and same PR shape; `/do`
  uses an isolated worktree where `/quickfix` works in place on main. Choose by
  project policy.
- **`/draft-plan`** and **`/run-plan`** — where `/quickfix` sends you when a
  request is too large for one quick fix. `/draft-plan` researches and breaks
  the work into a plan; `/run-plan` executes a plan that already exists.
- **`/investigate`** — use this first when you don't yet know the root cause of
  a bug. `/quickfix` assumes the fix is already understood; `/investigate`
  proves the cause, and the fix it lands on may then be shipped with `/quickfix`
  or `/do`.
- **`/fix-issues`** — for working through a backlog of GitHub issues in batches,
  rather than a single in-flight change.
- **`/land-pr`** — the helper `/quickfix` dispatches to push the branch, open
  the PR, watch CI, and run the fix cycle. You don't call it yourself.
- **`/cleanup-merged`** — run this after your PR merges to catch your local
  clone up (switch to main, pull, delete the merged branch).

## Arguments

```
/quickfix [<description>] [auto] [from-here] [skip-tests] [--force] [--branch <name>] [--rounds N]
```

| Argument | Required | What it does |
|----------|----------|--------------|
| `<description>` | Conditional | What to fix. Required when your tree is clean (there's nothing to infer from); optional when you have uncommitted edits, where it labels the commit. |
| `auto` | No | Merge the resulting PR automatically once CI passes (and skip the in-place "commit all of these files?" confirmation). |
| `from-here` | No | Allow `/quickfix` to run from a branch other than main/master, basing the feature branch off your current checkout. |
| `skip-tests` | No | Skip the pre-commit test run. Warn-only — use only for emergency hotfixes where the test suite is unrelated to your change. |
| `--force` | No | Proceed even when `/quickfix` wanted to redirect you to a bigger skill or its plan review rejected the change. A safety-gate override, dashed to match `/do`, `/work-on-plans`, and `/cleanup-merged`. |
| `--branch <name>` | No | Use this exact branch name instead of the auto-generated one. |
| `--rounds N` | No | How many plan-review/refine cycles to run before committing (default 1). `0` skips the review entirely. |
| `--no-claim` | No | Treat any `#N` issue reference in the description as a passing mention only. By default, if your description mentions an issue another pipeline is actively working, `/quickfix` stops to avoid duplicating that work; `--no-claim` tells it the reference is incidental ("fix tooltip, related to #340") and to carry on. Not shown in the usage line, but accepted. |

By default the feature branch is named `quickfix/<short-summary>`, where the
prefix comes from your project's `execution.branch_prefix` setting and the
summary is derived from your description. `--branch` overrides the whole name.
