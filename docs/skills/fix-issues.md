# /fix-issues

> Work through a backlog of GitHub issues in one sprint: pick the issues, fix each in isolation, run the tests, and (optionally) open and land a pull request per fix. Recurring via `every SCHEDULE`; `stop`/`next` manage the schedule. `sync` refreshes issue trackers and closes already-fixed issues; `plan` drafts plans for issues too complex to fix in a sprint.

## What it does

`/fix-issues N` runs a batch bug-fixing sprint over your GitHub issues. You give it a count `N`, and it prioritizes that many open issues, fixes each one in its own isolated worktree, runs the test suite before anything is committed, and writes a sprint report you can hand off to `/fix-report`. With the `auto` flag it lands each fix for you (via `/land-pr` in PR mode); without it, it asks for approval at the key gates first.

Each issue is fixed and committed separately, so the history stays clean and one bad fix never blocks the others. Before fixing anything, the agent reads each issue's full body — not just the title — so the fix matches what the issue actually asked for.

The same command also schedules itself to run again (`every SCHEDULE`), keeps your issue trackers in sync with GitHub and closes issues that are already fixed (`sync`), drafts plans for issues that are too big for a quick fix (`plan`), and manages the dashboard queue that feeds the sprint (`add` / `remove` / `reconsider`).

## Usage

```
/fix-issues N [focus|dashboard] [auto] [every SCHEDULE] [now] [pr|direct]
/fix-issues sync
/fix-issues plan [auto]
/fix-issues stop
/fix-issues next
/fix-issues add <N> [column] [pos]
/fix-issues remove <N> [column]
/fix-issues reconsider <N>
```

## Typical usage

The most common way to run `/fix-issues` is as a recurring, autonomous queue worker: a small count, `auto`, and a schedule. For example, fix one issue every 30 minutes from the dashboard queue and land each as a PR:

```
/fix-issues 1 every 30m dashboard auto
```

A one-time burst is just as common — fix several issues now, each as its own PR:

```
/fix-issues 5 auto pr
```

And a daily catch-up sprint that also runs once immediately:

```
/fix-issues 10 auto every day at 9am now
```

Running `/fix-issues` with no count and no subcommand doesn't start a sprint — it reports whether a recurring sprint is scheduled and prints a short usage hint.

## Companion skills

- **`/fix-report`** — the reporting companion. After a sprint, `/fix-report` summarizes the sprint report, closes the resolved issues on GitHub, updates trackers, and cleans up worktrees. `/fix-issues` deliberately leaves those wrap-up actions to `/fix-report`.
- **`/investigate`** — when an issue's root cause isn't clear enough to fix directly, `/investigate` proves the cause first; its fix can then be handled by `/fix-issues` or one of the one-commit skills.
- **`/draft-plan`** — issues too large for a sprint are routed here. `/fix-issues plan` drafts a plan for each skipped issue so `/run-plan` can execute it later.
- **`/land-pr`** — dispatched automatically in PR mode to push the branch, open the PR, watch CI, and merge. You never call it yourself.

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `N` | Yes (sprints) | Number of issues to fix (e.g., `30`) |
| `focus` | No | Prioritize a specific domain (`new`, `correctness`, `codegen`, `ui`, `tests`, or any domain found in your trackers) |
| `dashboard` | No | Pick the issues from the dashboard's Ready queue instead of the default priority order |
| `auto` | No | Run without stopping for confirmation: skip the issue-list approval, land each fix, and merge the sprint-report PR |
| `every SCHEDULE` | No | Self-schedule recurring runs (`4h`, `30m`, `day at 9am`, `weekday at 9am`) |
| `now` | No | Run immediately (with `every`: run now AND schedule) |
| `pr` | No | Land each fix as its own pull request on a named branch |
| `direct` | No | Land each fix straight onto main, no pull request (requires an unprotected main) |

### Subcommands

#### `sync`

Refresh every issue tracker from GitHub, research new issues, and verify-then-close issues that already appear fixed. Always interactive — it presents what it found and asks before closing anything. The flow:

1. Fetch the latest issues from GitHub and update the local trackers.
2. Research any issues that haven't been looked at yet, checking whether each is already resolved in the code.
3. Present its findings with a verdict per issue (fixed, likely fixed, not fixed, or unclear).
4. Stage the tracker and report updates for the issues you approve.
5. Commit, open a PR for the tracker updates, and close the approved issues on GitHub only after that PR merges.

#### `plan [auto]`

Draft plans for issues a previous sprint skipped as too complex. It reads the skipped items from the sprint report and dispatches `/draft-plan` for each — no fixing, just plans for `/run-plan` to execute later. With `auto`, it plans every found issue without asking you to pick.

#### `stop`

Cancel any recurring `/fix-issues` sprint and exit. Takes precedence over every other argument.

#### `next`

Report when the next scheduled sprint will run, in both relative and absolute time, and how many issues are waiting in the queue.

#### `add <N> [column] [pos]`

Add an issue to a queue column on the dashboard, then exit without running a sprint.

- `<N>` — GitHub issue number (required)
- `[column]` — `triage`, `ready`, or `backlog` (default: `ready`)
- `[pos]` — 1-based position to insert at (default: append to the end)

#### `remove <N> [column]`

Remove an issue from a queue column.

- `<N>` — GitHub issue number (required)
- `[column]` — `triage`, `ready`, or `backlog` (default: `ready`)

#### `reconsider <N>`

Flag a previously-skipped issue so the next sprint re-evaluates it from scratch instead of skipping it again. It's a one-shot signal: the issue is re-triaged once on the next run, then the flag clears.

## Examples

```
/fix-issues 30
/fix-issues 10 correctness
/fix-issues 5 auto
/fix-issues 5 auto every 4h
/fix-issues 5 auto every 4h now
/fix-issues 10 auto every day at 9am
/fix-issues sync
/fix-issues plan
/fix-issues plan auto
/fix-issues stop
/fix-issues next
/fix-issues 5 auto pr
/fix-issues 3 auto direct
/fix-issues 1 every 30m dashboard auto
/fix-issues 3 dashboard
/fix-issues add 700
/fix-issues add 700 triage
/fix-issues add 700 ready 1
/fix-issues remove 700
/fix-issues reconsider 717
```

## Common Patterns

- **Queue-worker:** `/fix-issues 1 every 30m dashboard auto` -- fix one issue every 30 minutes from the dashboard Ready queue, autonomously
- **Daily sprint:** `/fix-issues 10 auto every day at 9am now` -- schedule a daily sprint and run one immediately
- **One-time burst:** `/fix-issues 5 auto pr` -- fix 5 issues autonomously, each as its own PR
- **Sync hygiene:** `/fix-issues sync` before a sprint to refresh trackers and clear out already-fixed issues
- **Plan the hard ones:** after a sprint skips complex issues, `/fix-issues plan auto` to draft plans for them

## Tips & Gotchas

- The `sync` command always asks before closing an issue on GitHub -- there is no autonomous mode for it, even when you would otherwise expect `auto` to skip confirmations
- `dashboard` can't be combined with `focus`, `sync`, `plan`, `stop`, `next`, `add`, `remove`, or `reconsider` -- it's a way of choosing which issues to fix, not a separate command
- `direct` mode lands fixes straight onto main, so it only works when main isn't protected; use `pr` instead on a protected main
- A scheduled sprint lasts only as long as the session that created it -- re-run `/fix-issues ... every ...` to restart it after the session ends
- `every SCHEDULE` always runs autonomously, so adding it implies `auto` even if you don't type `auto`
- When you don't specify `pr` or `direct`, the landing style falls back to your project's configured default, or to cherry-picking the fix back to main if nothing is configured
- The sprint always runs the full test suite before any fix is committed, and never weakens a test to make it pass
