# /run-plan

> Execute a drafted plan, one phase at a time: read the plan, implement the next incomplete phase in an isolated worktree, verify it with a separate agent, update the plan's progress, and land the result. Can run every remaining phase autonomously. `status` shows progress; `stop`/`next` manage scheduling.

## What it does

`/run-plan` takes a plan file — the kind `/draft-plan` produces — and works through it phase by phase. For each phase it reads the plan to find the next incomplete phase, dispatches the implementation in an isolated worktree, hands the result to a separate verification agent, updates the plan's progress tracking, writes a report, and lands the change to `main`.

Point it at a plan and it runs just the next incomplete phase. Add `finish` and it runs all remaining phases in order, stopping the moment a phase fails verification or hits a conflict. Each phase still gets full verification, testing, and all the usual safety checks — `finish` changes how many phases run, not how carefully each one is done.

When you run every phase autonomously (`finish auto`), each phase runs as its own separate turn rather than all in one long-running context. That keeps a fresh context per phase, so a long multi-phase plan doesn't accumulate fatigue across the run: the first phase starts right away and each later phase begins once the previous one has landed.

How the result reaches `main` depends on the landing mode (see Arguments). In a protected-`main` repo the common shape is a pull request: `/run-plan` works in a feature-branch worktree, verifies, opens a PR, and lands it. Before running a phase it checks that phase's dependencies — if a prerequisite phase isn't done yet, it stops cleanly and tells you which one is missing.

## Usage

```
/run-plan <plan-file> [phase|finish|status] [auto] [pr|direct] [every SCHEDULE] [now]
/run-plan stop
/run-plan next
```

## Typical usage

The most common form is a plan path plus `finish auto` — run every remaining phase autonomously:

```
/run-plan plans/FEATURE_PLAN.md finish auto
/run-plan plans/FEATURE_PLAN.md finish auto pr
/run-plan plans/FEATURE_PLAN.md auto every 4h now
/run-plan plans/FEATURE_PLAN.md status
```

Run `/run-plan plans/X.md` on its own to do just the next phase interactively. Add `finish` to work through every remaining phase, and `auto` to run them without pausing for approval. Use `every SCHEDULE` (optionally with `now`) to drive the plan on a recurring cron instead.

## Companion skills

- **`/draft-plan`** — the prior step. `/draft-plan` produces the plan file that `/run-plan` then executes; the two are sequential, not alternatives.
- **`/refine-plan`** — corrects a plan mid-execution. When `/run-plan` detects that reality has drifted from the plan's spec, it refreshes the plan with `/refine-plan` before continuing.
- **`/draft-tests`** — the test-spec sibling of the plan-authoring family, used to author the test specs a plan's phases are checked against.
- **`/verify-changes`** — the verification gate `/run-plan` runs over each phase's work (and over all phases combined at the end of a `finish` run).
- **`/land-pr`** — dispatched by `/run-plan` to land each phase as a PR (push, CI polling, fix-cycle on failure). You never type it directly.
- **`/work-on-plans`** — drives a queue of plan-ready plans, dispatching `/run-plan` for each one.

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `plan-file` | Yes | Path to the plan file, e.g. `plans/FEATURE_PLAN.md` |
| `phase` | No | A specific phase to run, e.g. `4a`. If omitted, the next incomplete phase is detected automatically |
| `finish` | No | Run all remaining phases in order until the plan is complete |
| `status` | No | Show plan progress (read-only — no work is done) |
| `auto` | No | Run without pausing for approval, and auto-merge the PR in PR mode (see below) |
| `pr` | No | Land each phase via a pull request on a feature branch |
| `direct` | No | Work directly on `main`, with no PR and no cherry-pick |
| `every SCHEDULE` | No | Run on a recurring schedule (`4h`, `30m`, `day at 9am`) |
| `now` | No | Run immediately (with `every`: run now and schedule) |

`auto` makes the run autonomous: it skips the approval prompts and human-review pauses (the between-phase pause, drift findings, staleness checks, and verifier-fail review) so the skill can run unattended. Where a phase lands as a pull request, `auto` also auto-merges that PR. In cherry-pick or direct mode there is no PR to merge, so `auto` only removes the pauses.

Landing mode is resolved in this order: an explicit `pr` or `direct` argument wins; otherwise the `execution.landing` default in `.claude/zskills-config.json` is used; otherwise it falls back to cherry-pick (work in a worktree, cherry-pick the result to `main`). `direct` mode is rejected when `execution.main_protected` is `true` — use `pr` instead.

`finish` and `every` are mutually exclusive: `finish auto` schedules its own per-phase runs internally, while `every` sets a recurring cron at a cadence you choose. Use one or the other, not both.

## Subcommands

### `status`

Show the plan's progress: every phase with its status (Done, In Progress, Next, Blocked), what's next, and which dependencies are still outstanding. Read-only — no agents are dispatched and no work is done. If a recurring schedule is active, it's shown too.

### `stop`

Cancel any active `/run-plan` schedule for this session and release the plan's claims. Takes precedence over every other argument.

### `next`

Report when the next scheduled run will fire, as both a relative ("~2h 15m") and an absolute time. If no schedule is active, it says so.

### `now` (standalone)

`/run-plan now` (with no plan file) triggers the active schedule's plan immediately, without waiting for the next fire. The schedule stays active.

## Examples

```
/run-plan plans/FEATURE_PLAN.md
/run-plan plans/FEATURE_PLAN.md 4b
/run-plan plans/FEATURE_PLAN.md finish
/run-plan plans/FEATURE_PLAN.md finish auto
/run-plan plans/FEATURE_PLAN.md finish auto pr
/run-plan plans/FEATURE_PLAN.md auto every 4h now
/run-plan plans/FEATURE_PLAN.md direct
/run-plan plans/FEATURE_PLAN.md status
/run-plan now
/run-plan stop
/run-plan next
```

## Common Patterns

- **Single phase:** `/run-plan plans/X.md` — run the next incomplete phase interactively.
- **Full autonomous execution:** `/run-plan plans/X.md finish auto pr` — run every remaining phase, each as an auto-merged PR.
- **Scheduled execution:** `/run-plan plans/X.md auto every 4h now` — schedule recurring runs and start immediately.
- **Check progress:** `/run-plan plans/X.md status` — see which phases are done, in progress, or blocked.
- **Resume early:** `/run-plan now` — trigger the active schedule without waiting for the next fire.

## Tips & Gotchas

- `finish` and `every` are mutually exclusive — `finish auto` runs each phase as its own turn; `every` sets a recurring cron at your chosen cadence.
- Landing mode resolves from an explicit `pr`/`direct` argument first, then the `execution.landing` config default, then cherry-pick.
- `direct` mode is incompatible with `execution.main_protected: true`; use `pr` instead.
- A phase whose dependencies aren't done yet stops the run cleanly and reports which prerequisite is missing.
- The schedule is session-scoped — it ends when the session ends.
- A failing phase stops the run there; `auto` mode tries one fix cycle before giving up.
