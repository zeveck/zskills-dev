# /work-on-plans

> Drive your ready plans as a batch: take the plans queued as ready and run each one with `/run-plan` until it lands. Curate the queue (`add`/`rank`/`remove`/`default`) and run on a recurring schedule. The plan-side counterpart to `/fix-issues` for bugs.

## What it does

`/work-on-plans` works through your queue of ready-to-run plans, running each one for you. It is the way to sprint across the plan backlog instead of starting plans one at a time: you give it a count (or `all`), and it runs that many plans from the front of the queue, each one through `/run-plan`.

For each plan it picks, `/work-on-plans` runs `/run-plan` to execute it. By default each plan runs to completion — all of its phases — and lands as a pull request, so a batch of three ready plans becomes three finished plans. If you would rather pace the work one phase per plan instead, add the `phase` token. When a plan finishes, it drops off the ready queue so it won't be picked up again.

It is the plan-side counterpart to `/fix-issues`: where `/fix-issues` drives a backlog of bugs, `/work-on-plans` drives the backlog of plans. Run bare with no arguments, it just lists the ready queue so you can see what is queued and in what order, without changing anything.

Because it runs the queue rather than a single named plan, `/work-on-plans` also lets you manage that queue: add a plan to it, re-order entries by priority, remove one, or set the default mode new entries inherit.

If a plan in the queue points at a plan file that no longer exists, `/work-on-plans` stops and tells you rather than silently skipping it — that way you know to remove the stale entry.

## Usage

```
/work-on-plans
/work-on-plans N [phase|finish] [every SCHEDULE] [now] [continue] [--force]
/work-on-plans all [phase|finish] [every SCHEDULE] [now] [continue] [--force]
/work-on-plans add <slug> [pos]
/work-on-plans rank <slug> <pos>
/work-on-plans remove <slug>
/work-on-plans default <phase|finish>
/work-on-plans stop
/work-on-plans next
```

## Typical usage

The common form is a count plus a mode, often on a recurring schedule so the queue drains over time:

```
/work-on-plans
/work-on-plans 3
/work-on-plans all finish
/work-on-plans 1 finish every 1h now
```

Run bare, it lists the ready queue. Give it a number to run that many plans from the front of the queue, or `all` to run every queued plan. Add `every SCHEDULE` to make it recurring — each fire runs the count you gave it (one plan per hour, in the example above), so the queue drains a few plans at a time rather than all at once. Add `now` alongside `every` to also run immediately instead of waiting for the first scheduled fire.

## Companion skills

- **`/run-plan`** — the executor `/work-on-plans` calls for each plan. `/work-on-plans` is the batch driver; `/run-plan` does the actual phase-by-phase work on one plan. When you only have one plan to run, use `/run-plan` directly.
- **`/plans`** — the read-only plan dashboard. Check `/plans` first to review what's ready and in what order before kicking off a batch.
- **`/draft-plan`** — produces the plan files in the first place. A plan has to be drafted and marked ready before `/work-on-plans` will run it.
- **`/zskills-dashboard`** — the interactive status UI for in-flight pipelines; it reads the same ready queue `/work-on-plans` drains, and is where you can interactively prioritize it.
- **`/fix-issues`** — the bug-backlog counterpart. Same batch-and-schedule shape, but it drives issues instead of plans.

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| (no args) | -- | List the ready queue (read-only) |
| `N` | No | Run this many plans from the front of the ready queue |
| `all` | No | Run every plan in the ready queue |
| `phase` | No | Run one phase per plan instead of running each to completion |
| `finish` | No | Run each plan to completion (this is the default) |
| `continue` | No | If one plan fails, skip it and keep going instead of stopping |
| `every SCHEDULE` | No | Run on a recurring schedule (`1h`, `4h`, `day at 9am`); each fire runs the count |
| `now` | No | With `every`, run immediately as well as scheduling |
| `--force` | No | Take over a recurring schedule currently owned by another session |
| `next` | No | Print the active schedule (read-only) |
| `stop` | No | Cancel any active schedule |

`phase` and `finish` are mutually exclusive — pass at most one. The mode you pass applies to that batch only; it does not change the saved mode on individual queue entries or the queue-wide default (use the `default` subcommand for that).

A count and a schedule combine: `/work-on-plans 1 finish every 1h now` runs one plan now and one more every hour, so each fire drains just the count you gave rather than the whole queue. A bare `every SCHEDULE` with no leading count runs the whole queue on each fire.

`/work-on-plans` runs at the top level of your session so it can hand each plan to `/run-plan`; it cannot run as a dispatched sub-task, and will tell you so if you try.

## Subcommands

### `add <slug> [pos]`

Add a plan to the ready queue by its slug. The slug must start with a letter and contain only lowercase letters, digits, and hyphens. An optional 1-based position inserts it there; with no position it is appended to the end.

### `rank <slug> <pos>`

Move a plan already in the ready queue to a new 1-based position, re-prioritizing it.

### `remove <slug>`

Remove a plan from the ready queue. Removing a slug that isn't there exits cleanly, so it's safe to run either way.

### `default <phase|finish>`

Set the default mode that newly added queue entries inherit. It does not change the mode already saved on existing entries.

### `next`

Print the active recurring schedule, if any. Read-only.

### `stop`

Cancel the active recurring schedule.

## Examples

```
/work-on-plans
/work-on-plans 3
/work-on-plans all finish
/work-on-plans 5 phase continue
/work-on-plans 1 finish every 1h now
/work-on-plans add my-feature-plan
/work-on-plans add my-feature-plan 1
/work-on-plans rank my-feature-plan 3
/work-on-plans remove my-feature-plan
/work-on-plans default finish
/work-on-plans stop
/work-on-plans next
```

## Common Patterns

- **Check the queue:** `/work-on-plans` — see what's queued and in what order before running anything
- **Run the top few:** `/work-on-plans 3` — run the first three plans in the queue, each to completion
- **Run everything:** `/work-on-plans all finish` — finish every queued plan
- **Resilient batch:** `/work-on-plans all continue` — if one plan fails, skip it and keep going
- **Drain over time:** `/work-on-plans 1 finish every 1h now` — run one plan now, then one more each hour
- **Curate priorities:** use `add`, `rank`, and `remove` to shape the queue; use `default` to set the baseline mode

## Tips & Gotchas

- The default mode is `finish` — each plan runs to completion and lands as one pull request. Add `phase` only when you want to pace the work a single phase per plan.
- A mode you pass on the command line (`phase`/`finish`) applies to that batch only; it does not change the saved mode on queue entries or the queue-wide default.
- A count combines with a schedule: each scheduled fire runs the count you gave, not the whole queue. A bare `every SCHEDULE` with no count runs everything on each fire.
- A recurring schedule remembers the mode it was registered with — to change it, `stop` the schedule and register a new one.
- Recurring `finish`-mode schedules require intervals of at least an hour; `phase` mode has no minimum.
- A plan must be drafted and marked ready before `/work-on-plans` will run it — `/draft-plan` and `/plans` are how plans get there.
- If a queued plan's file is missing, `/work-on-plans` stops and tells you instead of silently skipping it, so you can remove the stale entry.
- `/work-on-plans` does not choose how each plan lands — `/run-plan` decides that from its own configuration.
