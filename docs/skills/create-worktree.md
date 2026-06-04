# /create-worktree

> Create a git worktree for agent work, on a fresh branch off `main`. Most of the time another skill runs this for you; you rarely call it by hand.

<details class="flow-cmd" open>
<summary>How it runs — set up a worktree</summary>

<div class="flow">
<div class="flow-step"><p>The <strong>agent</strong> prunes, fetches, and ff-merges main</p></div>
<div class="flow-step"><p>It creates the worktree on a branch</p></div>
<div class="flow-step"><p>It writes the <code>.zskills-tracked</code> marker</p></div>
<div class="flow-step"><p>It returns the path to the caller</p></div>
</div>

</details>

## What it does

`/create-worktree` sets up a fresh [git worktree](https://git-scm.com/docs/git-worktree) — a separate checkout of the repository in its own directory — so an agent can work on a change in isolation, without disturbing your main checkout. You give it a short slug; it picks a directory and a branch name from that slug, creates the worktree there, and prints the worktree's absolute path so the caller can `cd` into it and start working.

By default it first tidies up: it prunes stale worktree entries, fetches `main` from the remote, and fast-forwards your local `main` to match, so the new worktree starts from current code. You can skip this tidy-up with `--no-preflight` when the caller has already refreshed `main`.

This is the shared building block that every isolation-using skill relies on. `/do`, `/run-plan`, `/fix-issues`, and others call it to get a clean worktree before they make changes — which is why you seldom type `/create-worktree` yourself. It is still a normal command you *can* run directly when you want a worktree to experiment in.

## Usage

```
/create-worktree <slug> [--prefix P] [--branch-name REF] [--from B] [--root R]
                 [--purpose TEXT] [--allow-resume] [--no-preflight]
```

The simplest form is just a slug:

```
/create-worktree my-feature
```

That creates a worktree directory named after your project and the slug (for example `/tmp/zskills-my-feature`), on a new branch `wt-my-feature`, branched from `main`. It prints the path; you `cd` there and work.

## Typical usage

When you run it by hand, you almost always want only the slug — and optionally a purpose note so it's clear later what the worktree was for:

```
/create-worktree my-feature
/create-worktree spike-dark-mode --purpose "Experimenting with a dark theme"
/create-worktree fix-login --from release-2.0
```

Add `--from B` to branch off something other than `main`. Add `--allow-resume` to reuse an existing branch that's already ahead of the base instead of failing. The other flags (`--prefix`, `--branch-name`, `--root`) are mostly used by the skills that call `/create-worktree` internally, to control exactly where the worktree lands and what its branch is named.

## Companion skills

`/create-worktree` is the worktree-setup primitive the rest of the catalog builds on, so its companions are the skills that call it before they begin work:

- **[`/do`](do.md)** — opens a worktree through `/create-worktree` when it isolates a single change.
- **[`/run-plan`](run-plan.md)** — creates a worktree per plan execution so each plan's work stays isolated.
- **[`/fix-issues`](fix-issues.md)** — creates a worktree when working a backlog of issues in isolation.
- **[`/commit`](commit.md)** — lands the work done inside a worktree back onto `main`; it also refuses to clean up a worktree whose tracking files were accidentally committed.
- **[`/update-zskills`](update-zskills.md)** — installs and configures the worktree machinery (including where worktrees are created).

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `slug` | Yes | A short name for the worktree (letters, digits, `.`, `_`, `-`). It becomes part of the directory name and the branch name. |
| `--prefix P` | No | Adds `P-` to both the branch name and the directory name (no slashes allowed). |
| `--branch-name REF` | No | Use this exact branch name instead of the auto-generated `wt-<slug>`. |
| `--from B` | No | Base branch to create the worktree from. Defaults to `main`. |
| `--root R` | No | Put the worktree under directory `R` instead of the default location. |
| `--purpose TEXT` | No | Record a human-readable note describing what the worktree is for. Without it, no note is written. |
| `--allow-resume` | No | Attach to an existing branch that's already ahead of the base, instead of treating that as an error. |
| `--no-preflight` | No | Skip the prune + fetch + fast-forward step. Use when `main` is already up to date. |

Where worktrees are created is set by `execution.worktree_root` in `.claude/zskills-config.json` (default `/tmp`); the directory leaf combines your project name, any prefix, and the slug.

The command exits with an error (rather than silently doing the wrong thing) when the slug is malformed, when the target directory already exists, or when the branch is in a state that needs your decision — for example, a branch that's behind the base, or one that's ahead of the base without `--allow-resume`.

## See also

- [`/do`](do.md) — the most common skill that opens a worktree for you.
- [Workflows](../guides/workflows.md) — how worktrees fit into the landing modes.
