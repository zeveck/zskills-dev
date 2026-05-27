# /briefing

> Generate a project briefing: worktree status, open checkboxes, recent commits. Modes: summary (default), report, verify, current, worktrees. Period: 1h, 6h, 24h, 2d, 7d.

## Usage

```
/briefing [report [period]] | verify | current | worktrees | [summary] | stop | next
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| (no args) | -- | Summary mode (default) |
| `summary` | No | Explicit summary mode |
| `report [period]` | No | Detailed report for a time period |
| `verify` | No | Verify mode |
| `current` | No | Current state mode |
| `worktrees` | No | Worktree status mode |
| `stop` | No | Cancel scheduled briefings |
| `next` | No | Show next scheduled briefing time |

### Period Shorthand

Used with `report` mode: `1h`, `6h`, `24h` (default), `1d`, `2d`, `7d`

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

- **Quick status check:** `/briefing` -- summary of project state
- **Weekly report:** `/briefing report 7d` -- detailed report covering the last 7 days
- **Daily scheduled briefing:** `/briefing report 24h every day at 9am` -- schedule a daily report
- **Worktree inventory:** `/briefing worktrees` -- see all worktrees and their status

## Tips & Gotchas

- The briefing helper is a Python script (`briefing.py`) -- requires Python 3
- Script output is presented verbatim -- it is not summarized or rephrased
- Scheduling follows the same `every SCHEDULE` pattern as other skills
- `stop` and `next` manage the scheduled briefing cron
