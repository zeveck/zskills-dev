# /run-plan

> Execute the next phase of a plan: parse status, dispatch implementation in a worktree, verify via a separate agent, update progress, write the plan report, and optionally auto-land to main. Self-schedules via cron; use `next` to check, `stop` to cancel.

## Usage

```
/run-plan <plan-file> [phase|finish|status] [auto] [pr|direct] [every SCHEDULE] [now]
/run-plan stop
/run-plan next
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `plan-file` | Yes | Path to plan file (e.g., `plans/FEATURE_PLAN.md`) |
| `phase` | No | Specific phase to run (e.g., `4a`). If omitted, auto-detects next incomplete phase |
| `finish` | No | Run ALL remaining phases sequentially until the plan is complete |
| `status` | No | Show plan progress (read-only, no agents dispatched) |
| `auto` | No | Skip approval prompts, auto-merge resulting PRs |
| `pr` | No | Land via PR on a named branch |
| `direct` | No | Work directly on main (no PR, no cherry-pick) |
| `every SCHEDULE` | No | Self-schedule recurring runs (`4h`, `30m`, `day at 9am`) |
| `now` | No | Run immediately (with `every`: run now AND schedule) |

## Subcommands

### `status`

Show plan progress: all phases, their status (Done, In Progress, Not Started, Blocked), and what's next. Read-only -- no agents dispatched. If a cron is active, also shows the schedule.

### `finish`

Run all remaining phases sequentially. Without `auto`: pauses between phases to show results and ask "continue?" With `auto` (`finish auto`): each phase runs as its own cron-fired turn with ~5 min between phases. If any phase fails, stops there.

### `stop`

Cancel any existing `/run-plan` cron, release all plan claims, and exit. Takes precedence over all other arguments.

### `next`

Check when the next scheduled run will fire. Shows both relative and absolute time.

### `now` (standalone)

Trigger the active cron's plan immediately. Extracts N, plan-file, auto, and schedule from the cron's prompt and runs. The cron stays active.

## Examples

```
/run-plan plans/FEATURE_PLAN.md
/run-plan plans/FEATURE_PLAN.md 4b
/run-plan plans/FEATURE_PLAN.md finish
/run-plan plans/FEATURE_PLAN.md finish auto
/run-plan plans/FEATURE_PLAN.md auto every 4h
/run-plan plans/FEATURE_PLAN.md auto every 4h now
/run-plan plans/FEATURE_PLAN.md finish auto pr
/run-plan plans/FEATURE_PLAN.md direct
/run-plan plans/FEATURE_PLAN.md status
/run-plan now
/run-plan stop
/run-plan next
```

## Common Patterns

- **Single phase:** `/run-plan plans/X.md` -- run the next incomplete phase interactively
- **Full autonomous execution:** `/run-plan plans/X.md finish auto pr` -- run all remaining phases, each as a PR, auto-merged
- **Scheduled execution:** `/run-plan plans/X.md auto every 4h now` -- schedule recurring runs and start immediately
- **Check progress:** `/run-plan plans/X.md status` -- see which phases are done, in progress, or blocked
- **Resume after pause:** `/run-plan now` -- trigger the active cron early without waiting for the next fire

## Tips & Gotchas

- `finish` and `every` are mutually exclusive -- `finish auto` schedules its own internal one-shot crons
- `finish auto` is a composite alias: it sets both `FINISH_MODE=finish-auto` and `AUTO_FLAG=1`
- Landing mode resolution: explicit argument > config default (`execution.landing`) > `cherry-pick` fallback
- `direct` mode is incompatible with `execution.main_protected: true`
- The plan file is parsed using LLM comprehension, not rigid regex -- it handles progress tracker tables, numbered phase sections, checklists, and narrative formats
- Cron is session-scoped -- it dies when the session dies
- In PR mode, plan tracker updates commit on the feature branch (not main) until the squash merge lands
- Phase dependencies are checked before execution -- if a prerequisite phase is not Done, the skill stops
- An adaptive backoff mechanism handles "in progress" phases: the cron cadence slows from `*/1` to `*/10` to `*/30` to `*/60` based on consecutive defers
