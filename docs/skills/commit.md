# /commit

> Commit your current work safely, and optionally push it, open a pull
> request, or land worktree commits onto main.

<details class="flow-cmd" open>
<summary>How it runs — safe, scoped commit</summary>

<div class="flow">
<div class="flow-step"><p>The <strong>original agent</strong> inventories all uncommitted changes</p></div>
<div class="flow-step"><p>It scopes the commit and traces imports and dependencies</p></div>
<div class="flow-step"><p>A <strong>reviewer subagent</strong> checks the staged change</p></div>
<div class="flow-step"><p>The <strong>original agent</strong> commits, then optionally pushes or opens a PR</p></div>
</div>

</details>

## What it does

`/commit` is the user-facing way to turn the changes in your working tree
into a clean commit. It is built to commit *your* work without picking up or
harming changes that other sessions or agents left in the tree.

When you run it, the skill looks at everything that has changed, decides
which files belong to the work you are committing and which are unrelated,
and stages only the related ones — always by name, never with a
catch-all `git add`. It traces dependencies as it goes: if a file you are
committing depends on another uncommitted file, that file is pulled in too,
so you do not ship a commit that references something that was left behind.
Unrelated changes are left untouched. If a single file mixes your work with
someone else's, the skill stops and asks rather than guessing.

Before the commit is written it runs the full test suite when code was
staged (it skips tests for content-only changes like Markdown or images),
drafts a commit message in the style of your recent history, and has a
fresh reviewer look over the staged diff to catch missing files, stray
files, or problems in the change. If anything looks wrong, it stops and
reports instead of committing.

Beyond the basic commit, `/commit` can also:

- **Push** the commit to the remote.
- **Open a pull request** to main (`/commit pr`) — push the current branch,
  create the PR, watch its CI, and fix failures, by handing off to the
  `/land-pr` skill described under "Companion skills" below.
- **Land** worktree commits onto main by cherry-picking them
  (`/commit land`), running tests, and recording that the worktree's work
  has been merged.

If you do not type a mode, `/commit` reads your project's configured default
landing behavior and acts accordingly — so on a project set up to land work
through pull requests, a bare `/commit` opens a PR for you without you
retyping `pr` each time.

## Typical usage

The common cases, from lightest to heaviest:

```
/commit
/commit skill updates
/commit push
/commit pr
/commit pr auto
```

- `/commit` — commit the related changes; figure out the scope from the
  diffs.
- `/commit skill updates` — the same, but the free-text **scope hint**
  (`skill updates`) guides which files count as related. The hint narrows
  the search; the skill still checks the diffs.
- `/commit push` — commit, then push to the remote.
- `/commit pr` — push the current branch and open a pull request to main.
  This is the recommended way for you to land work as a PR (it requires a
  clean working tree, so commit first).
- `/commit pr automerge` — the same, plus request that the PR auto-merge
  once CI passes.

To land a feature branch as a PR, `/commit pr` is the path to reach for. It
is one of the supported entry points for opening pull requests; you do not
call the underlying landing machinery yourself.

## Companion skills

`/commit` is the shared landing step for staged work, and several skills use
it that way:

- **`/land-pr`** — the skill `/commit pr` hands off to in order to push the
  branch, create the pull request, monitor CI, and run the fix cycle on a
  failure. `/land-pr` is an internal helper you do not type directly; reach
  for it through `/commit pr`.
- **`/do`** — the everyday skill for one-commit changes. It carries a change
  through triage, review, and landing, and calls `/commit` to land its work.
- **`/run-plan`** and **`/fix-issues`** — larger orchestration skills that
  also land their work through `/commit` and `/land-pr`.
- **`/cleanup-merged`** — run this *after* a PR you opened with `/commit pr`
  has merged, to bring your local clone back up to date.
- **`/update-zskills`** — configures the project settings `/commit` reads,
  such as the default landing behavior and the commit co-author trailer.

## Arguments

`/commit` takes optional positional tokens. Order matters only for `pr`,
which must come first.

| Argument | What it does |
|----------|--------------|
| `pr` | Push the current branch and open a pull request to main. Must be the **first** token — this prevents a scope hint that happens to contain "pr" from triggering PR mode. Requires a clean working tree. |
| `scope` | A free-text hint (e.g. `skill updates`, `parser reset button fix`) that guides which files count as related. Advisory — the skill still reads the diffs. |
| `push` | Commit, then push to the remote. |
| `land` | Cherry-pick the current worktree's commits onto main, run tests, and record that the work has landed. Only valid when you are in a worktree. |
| `auto` | In PR mode, run unattended. Does not auto-merge; see `automerge`. |
| `automerge` | In PR mode, request that the pull request auto-merge once CI passes. Implies `auto`. Has no effect with `push` or `land`. |

If you give no mode token at all, `/commit` reads your project's configured
default landing behavior to decide what to do — on a project that lands
through pull requests, a bare `/commit` behaves like `/commit pr`.

## Tips & Gotchas

- `auto` runs unattended but does not merge; use `automerge` for unattended + auto-merge.

