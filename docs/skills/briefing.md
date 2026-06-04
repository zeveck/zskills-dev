# /briefing

> Generate a project briefing: worktree status, open checkboxes, recent commits. Modes: summary (default), report, verify, current, worktrees. Period: 1h, 6h, 24h, 1d, 2d, 7d.

<details class="flow-cmd" open>
<summary>How it runs — project status</summary>

<div class="flow">
<div class="flow-step"><p>The <strong>agent</strong> scans the current repo state</p></div>
<div class="flow-step"><p>It reports commits, worktrees, and open checkboxes</p></div>
</div>

</details>

## What it does

`/briefing` gathers the current state of your project and presents it as a structured briefing. It looks at three things: the status of your worktrees, the open sign-off checkboxes (`[ ]` items) sitting in report files, and the recent commits that have landed on `main`. The result is a quick read on what needs your attention, what is in flight, and what has already landed.

By default it prints a short triage view to the terminal, grouped into buckets: what needs attention (worktrees awaiting review, unchecked checkboxes, uncommitted files), what has landed recently, what is still in flight, and what is quiet and needs no action. The output is shown to you exactly as the helper produces it — it is not summarized or rephrased.

`/briefing` has several modes that change what it focuses on:

- **summary** (the default) — the short, terminal-only triage view described above.
- **report** — a detailed Markdown report written to a file. The helper prints the path; checkboxes you already ticked off in an earlier same-day report are carried forward automatically.
- **verify** — a sign-off dashboard of the open `[ ]` items across your report files, with the file paths so you can open each one, check the items, and be done. This mode is about report sign-offs, not worktrees.
- **current** — what is actively in flight right now: worktrees touched in the last couple of hours, worktrees that are finished but not yet landed, empty worktrees, uncommitted changes on `main`, and any stashes.
- **worktrees** — a detailed worktree inventory with cleanup readiness: which worktrees are safe to remove (with copy-pasteable removal commands), which still need their logs extracted first, and which still hold unlanded commits. It only reports — it never removes anything.

All modes are read-only: `/briefing` tells you the state of the project, it does not change it.

The **report** mode takes an optional time period that bounds how far back it looks: `1h`, `6h`, `24h` (the default), `1d`, `2d`, or `7d`.

`/briefing` can also run on a schedule — append `every SCHEDULE` to any mode to have it run recurrently (the schedule is tied to the current session). The `stop` and `next` subcommands cancel a scheduled briefing and show when the next one will fire.

## Typical usage

The common case is a bare `/briefing` for a quick status read, or `report` with a period for something you want to keep:

```
/briefing
/briefing report 7d
/briefing report 24h every day at 9am
/briefing worktrees
/briefing verify
```

A bare invocation gives you the summary triage view. Add `report` and a period for a written report. Add `every SCHEDULE` to a report invocation to get a recurring briefing (for example, a daily 9 AM report). Use `worktrees` before a cleanup pass to see what is safe to remove, and `verify` when you want to walk through pending sign-offs.

## Companion skills

- **`/fix-issues`** — one of the long-running orchestration skills `/briefing` reports on. When `/fix-issues` works a backlog into worktrees and commits, `/briefing` surfaces what landed and what still needs review.
- **`/run-plan`** — likewise a long-running skill whose worktrees, landed commits, and report sign-offs show up in a briefing. Run `/briefing verify` after a plan run to pick up any open sign-off items.
- **`/update-zskills`** — the install and configuration skill. It sets up the configuration `/briefing` reads (audit and report directories, the source-clone path it checks for zskills updates).

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| (no args) | -- | Summary mode (the default) |
| `summary` | No | The same summary mode, named explicitly |
| `report [period]` | No | Write a detailed Markdown report for the given time period |
| `verify` | No | Show the open sign-off checkboxes across report files |
| `current` | No | Show what is actively in flight right now |
| `worktrees` | No | Show a worktree inventory with cleanup readiness |
| `stop` | No | Cancel scheduled briefings |
| `next` | No | Show the next scheduled briefing time |

### Period

Used with the `report` mode to bound how far back it looks: `1h`, `6h`, `24h` (the default), `1d`, `2d`, or `7d`.

### Scheduling

Append `every SCHEDULE` to any mode to run the briefing recurrently — for example `every day at 9am`, `every weekday at 9am`, `every hour`, or `every 2h`. Add `now` style timing in the schedule as you would for other skills. The schedule lives with the current session; if the session ends, the schedule is lost. Use `stop` to cancel it and `next` to see when it will next fire.

## Examples

```
/briefing
/briefing summary
/briefing report
/briefing report 7d
/briefing report 24h every day at 9am
/briefing verify
/briefing current
/briefing worktrees
/briefing stop
/briefing next
```

## Common Patterns

- **Quick status check:** `/briefing` — summary of the project state.
- **Weekly report:** `/briefing report 7d` — a detailed report covering the last 7 days.
- **Daily scheduled briefing:** `/briefing report 24h every day at 9am` — schedule a daily report.
- **Worktree inventory:** `/briefing worktrees` — see every worktree and whether it is safe to remove.
- **Walk through sign-offs:** `/briefing verify` — list the open `[ ]` items and the files to open them in.

## Tips & Gotchas

- `/briefing` requires Python 3; if it is not on your PATH, the skill prints a clear error and stops.
- The script's output is shown to you verbatim — it is formatted to be read directly, not summarized.
- Every mode is read-only. `worktrees` shows you removal commands but never runs them; always extract a worktree's logs before removing it.
- The `report` mode preserves checkboxes you ticked in an earlier same-day report, so re-running it the same day does not lose your progress.
- The `summary` and `report` modes also note whether your installed zskills version is behind the source clone, when one is found.
