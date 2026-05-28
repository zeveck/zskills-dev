# /fix-issues

> Orchestrate a batch bug-fixing sprint: dispatch implementers in per-issue worktrees, verify, optionally auto-land via /land-pr. Recurring via `every SCHEDULE`; `stop`/`next` manage it. `sync` updates trackers and closes already-fixed issues; `plan` drafts plans for skipped ones.

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

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `N` | Yes (sprints) | Number of issues to fix (e.g., `30`) |
| `focus` | No | Prioritize a specific domain (`new`, `correctness`, `codegen`, `ui`, `tests`, etc.) |
| `dashboard` | No | Source candidates from the dashboard Ready queue instead of the model-layer rubric |
| `auto` | No | Bypass confirmation gates; auto-land per-issue fix PRs; auto-merge sprint-report PR |
| `every SCHEDULE` | No | Self-schedule recurring runs (`4h`, `30m`, `day at 9am`, `weekday at 9am`) |
| `now` | No | Run immediately (with `every`: run now AND schedule) |
| `pr` | No | Land each fix via a per-issue PR on a named branch |
| `direct` | No | Land each fix by fast-forward-merging into main (no PR) |

## Subcommands

### `sync`

Update all issue tracker files from GitHub, research new issues, and verify/close issues that appear already fixed. Always interactive -- presents findings and asks before closing. Steps:

1. Fetch and update trackers from GitHub
2. Dispatch research agents for unresearched issues (also checks if issues are already fixed)
3. Present findings with verdicts (FIXED, LIKELY FIXED, NOT FIXED, UNCLEAR)
4. Stage local tracker and sprint-report updates for approved issues
5. Commit, dispatch `/land-pr` for the sync PR, then close approved issues on GitHub (only after PR merges)

### `plan [auto]`

Draft plans for issues previously skipped as "too complex." Scans the sprint report for skipped items and dispatches `/draft-plan` for each. No fixing -- just creates plans for `/run-plan` to execute later. With `auto`, plans all found issues without selection.

### `stop`

Cancel any existing `/fix-issues` cron and exit. Takes precedence over all other arguments.

### `next`

Check when the next scheduled run will fire. Shows relative and absolute time.

### `add <N> [column] [pos]`

Add an issue to a dashboard queue column. Early-exit subcommand that mutates `.zskills/monitor-state.json` and exits.

- `<N>` -- GitHub issue number (required)
- `[column]` -- One of `triage`, `ready`, `backlog` (default: `ready`)
- `[pos]` -- 1-based insertion position (default: append)

### `remove <N> [column]`

Remove an issue from a dashboard queue column.

- `<N>` -- GitHub issue number (required)
- `[column]` -- One of `triage`, `ready`, `backlog` (default: `ready`)

### `reconsider <N>`

Flag a previously-skipped issue for re-evaluation on the next sprint. Annotates the issue's section in `ISSUES_PLAN.md` with a reconsidered marker so Phase 2 re-triages it independently.

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

- **Queue-worker pattern:** `/fix-issues 1 every 30m dashboard auto` -- fix one issue every 30 minutes from the dashboard Ready queue
- **Daily sprint:** `/fix-issues 10 auto every day at 9am now` -- schedule daily at 9am and run immediately
- **One-time burst:** `/fix-issues 5 auto pr` -- fix 5 issues autonomously, each as a separate PR
- **Sync hygiene:** `/fix-issues sync` before starting a sprint to ensure trackers are up to date
- **Plan complex issues:** after a sprint skips issues, `/fix-issues plan auto` to draft plans for them

## Tips & Gotchas

- `auto` does NOT bypass the human-approval gate on `gh issue close` in sync mode -- only the tracker-PR auto-merge is unconditional
- `dashboard` is mutually exclusive with `focus`, `sync`, `plan`, `stop`, `next`, `add`, `remove`, and `reconsider`
- `direct` mode is incompatible with `execution.main_protected: true`
- Cron is session-scoped -- it dies when the session dies
- `every SCHEDULE` implies `auto` (scheduling only makes sense for autonomous runs)
- Landing mode resolution: explicit argument > config default (`execution.landing`) > `cherry-pick` fallback
- The skill runs at the top level -- it cannot be dispatched from a subagent
