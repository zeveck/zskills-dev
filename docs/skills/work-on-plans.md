# /work-on-plans

> Batch-execute the prioritized ready queue from the dashboard: reads `.zskills/monitor-state.json` (`plans.ready`) and dispatches `/run-plan auto [finish]` per entry, honoring each plan's queued mode. Also manages the queue (`add`/`rank`/`remove`/`default`) and recurring schedules.

## Usage

```
/work-on-plans
/work-on-plans N [phase|finish] [continue]
/work-on-plans all [phase|finish] [continue]
/work-on-plans add <slug> [pos]
/work-on-plans rank <slug> <pos>
/work-on-plans remove <slug>
/work-on-plans default <phase|finish>
/work-on-plans every SCHEDULE [phase|finish] [--force]
/work-on-plans stop
/work-on-plans next
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| (no args) | -- | List the ready queue (read-only) |
| `N` | No | Number of plans to execute from the ready queue |
| `all` | No | Execute all plans in the ready queue |
| `phase` | No | Override dispatch mode to single-phase per plan |
| `finish` | No | Override dispatch mode to finish-all-phases per plan |
| `continue` | No | Continue to next plan on failure instead of stopping |
| `next` | No | Print active schedule (read-only) |
| `stop` | No | Cancel any active cron |

## Subcommands

### `add <slug> [pos]`

Add a plan to the ready queue. The slug must match `^[a-z][a-z0-9-]*$` (no digit-prefix). Optional 1-based position for insertion; default appends.

### `rank <slug> <pos>`

Move an existing ready-queue entry to a new 1-based position.

### `remove <slug>`

Remove a plan from the ready queue. Idempotent -- missing slug exits cleanly.

### `default <phase|finish>`

Set the top-level `default_mode` for newly added entries. Does not mutate saved per-entry modes.

### `every SCHEDULE [phase|finish] [--force]`

Register a recurring cron. Each fire dispatches `/work-on-plans all <schedule_mode>`. Mode is captured at registration (CLI flag > current `default_mode` > `"phase"`). Finish mode requires SCHEDULE >= 1h to avoid collision with `/run-plan`'s phase-chaining crons. Use `--force` to take over a schedule owned by another session.

### `stop`

Cancel the active cron and reset state to idle.

## Examples

```
/work-on-plans
/work-on-plans 3
/work-on-plans all finish
/work-on-plans 5 phase continue
/work-on-plans add my-feature-plan
/work-on-plans add my-feature-plan 1
/work-on-plans rank my-feature-plan 3
/work-on-plans remove my-feature-plan
/work-on-plans default finish
/work-on-plans every 4h
/work-on-plans every 2h phase
/work-on-plans every day at 9am finish --force
/work-on-plans stop
/work-on-plans next
```

## Common Patterns

- **Check queue:** `/work-on-plans` -- see what's queued and the default mode
- **Run top 3:** `/work-on-plans 3` -- execute the first 3 plans from the ready queue
- **Run everything:** `/work-on-plans all finish` -- finish all phases of every queued plan
- **Resilient batch:** `/work-on-plans all continue` -- if one plan fails, skip it and continue
- **Scheduled execution:** `/work-on-plans every 4h phase` -- run one phase per plan every 4 hours
- **Priority management:** use `add`, `rank`, `remove` to curate the queue; use `default` to set the baseline mode

## Tips & Gotchas

- Must run at top level (needs the Agent tool to dispatch `/run-plan` via the Skill tool)
- Mode override (`phase`/`finish`) is per-batch only -- it does not mutate saved per-entry modes or `default_mode`
- `phase` and `finish` are mutually exclusive
- Finish-mode schedules require intervals >= 1h to avoid nested cron collision
- All read-modify-write operations against `monitor-state.json` are serialized via `flock -x`
- If `monitor-state.json` is missing, it is auto-created (seeded from `PLAN_INDEX.md` or plan frontmatter)
- Unknown slugs fail loud -- the skill never silently skips a queued slug whose plan file is missing
- `/run-plan` resolves its own landing mode from config -- `/work-on-plans` does not pass landing-mode flags
- Schedule mode is captured at registration and persists -- to change mode, `stop` and re-register
