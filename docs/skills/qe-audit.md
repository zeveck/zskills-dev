# /qe-audit

> QE audit: check recent commits for test coverage gaps, or bash/stress-test features to find bugs. Files GitHub issues for findings. Recurring via `every SCHEDULE`; `stop`/`next` manage it.

<details class="flow-cmd" open>
<summary>How it runs — hunt gaps, file issues</summary>

<div class="flow">
<div class="flow-step"><p>The <strong>original agent</strong> scans recent commits for risky changes</p></div>
<div class="flow-step"><p><strong>Audit subagents</strong> comb the batches in parallel with fresh eyes</p></div>
<div class="flow-step"><p>The <strong>original agent</strong> re-verifies each finding</p></div>
<div class="flow-step"><p>It files GitHub issues with repro recipes</p></div>
</div>

</details>

## What it does

`/qe-audit` runs a quality-engineering pass over your recent work and files GitHub issues for what it finds. It does not fix anything — it looks for missing tests, coverage gaps, and bugs, and turns each real finding into an issue you (or `/fix-issues`) can act on later.

It has two ways of looking. The default, **commit audit**, reviews the commits made since the last audit: it reads each diff and the related tests, and asks whether the tests are meaningful, whether anything is left uncovered, and whether any bug slipped in. The second, **bash mode**, is adversarial stress-testing of a feature: it picks an area (one you name, or an under-tested one it chooses), then tries to break it with edge cases, unusual inputs, and unexpected workflows — empty values, boundary conditions, rapid or out-of-order actions, invalid state. Both modes end the same way: they file GitHub issues for real findings and write a short report of what they did.

Every finding is checked against the actual code before an issue is filed. If a finding claims a file says something, a line is missing, or a commit fixed a bug, `/qe-audit` confirms that against the source first; a finding it can't confirm is recorded as unverified rather than filed. The bar for filing is deliberately high — a finding has to be a real problem a user or agent would plausibly hit, not just something theoretically possible — so a quiet run that files nothing is a normal, healthy result, not a failure.

`/qe-audit` deliberately files issues instead of fixing them: it finds the problems, and `/fix-issues` fixes them. Together they form a feedback loop — `/qe-audit` finds gaps, `/fix-issues` closes them, and the next `/qe-audit` validates that the fixes actually held.

## Usage

```
/qe-audit [bash [area]] [every SCHEDULE] [now]
/qe-audit stop
/qe-audit next
```

A bare `/qe-audit` runs a commit audit immediately. Add `bash` to switch to stress-test mode. Add `every SCHEDULE` to turn it into a recurring audit, and `now` to also run straight away.

## Typical usage

The most common form is a bare audit or a stress test, often on a schedule that keeps it running in the background:

```
/qe-audit
/qe-audit bash
/qe-audit bash undo/redo
/qe-audit bash solver
/qe-audit every day at 9am
/qe-audit every 4h now
/qe-audit bash every 12h
```

A bare `/qe-audit` audits the commits since the last run. `/qe-audit bash` stress-tests an under-tested area it picks for you; name an area (`/qe-audit bash solver`) to point it somewhere specific. Add `every SCHEDULE` to schedule recurring runs, with `now` to also run immediately. Once scheduled, `/qe-audit next` tells you when the next run fires and `/qe-audit stop` cancels it.

## Companion skills

- **`/fix-issues`** — the other half of the loop. `/qe-audit` files the issues; `/fix-issues` drives the backlog and fixes them. The separation is deliberate: audit finds, fix-issues fixes, audit validates.
- **`/verify-changes`** — the close peer to be clear about. `/verify-changes` checks *your* specific recent changes and gates a commit; `/qe-audit` hunts across recent work for gaps and bugs and files issues, generating work rather than gating it. Reach for `/verify-changes` to confirm a change is sound; reach for `/qe-audit` to go looking for problems.
- **`/draft-plan`** — where a big finding goes. When a finding is too large to be a single issue, it becomes a plan for `/draft-plan` to research and decompose.
- **`/manual-testing`** — used inside bash mode to exercise UI features through a real browser when stress-testing the editor or other interactive surfaces.

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `bash` | No | Switch to bash/stress-test mode instead of the default commit audit |
| `area` | No (with bash) | Specific feature area to stress-test (e.g., `undo/redo`, `solver`, `codegen`); omit it and `/qe-audit` picks an under-tested area itself |
| `every SCHEDULE` | No | Self-schedule recurring runs (`4h`, `2h`, `30m`, `12h`, `day at 9am`, `weekday at 9am`) |
| `now` | No | Run immediately (with `every`: run now *and* schedule); a bare invocation already runs immediately |
| `stop` | No | Cancel any recurring `/qe-audit` run; takes precedence over everything else |
| `next` | No | Report when the next scheduled run will fire; takes precedence over everything but `stop` |

A bare invocation always runs immediately, so `now` only matters alongside `every`. Scheduling re-registers itself on each run so the recurrence keeps going, and a scheduled audit runs autonomously — it does not pause for approval. The schedule lasts as long as the session: it stops when the session ends.

## Examples

```
/qe-audit
/qe-audit bash
/qe-audit bash undo/redo
/qe-audit bash solver
/qe-audit bash solver every 6h
/qe-audit every day at 9am
/qe-audit every day at 9am now
/qe-audit every weekday at 9am
/qe-audit bash every 12h now
/qe-audit next
/qe-audit stop
```

## Common Patterns

- **Daily audit:** `/qe-audit every day at 9am` — schedule a daily commit audit, first run tomorrow morning
- **Targeted stress test:** `/qe-audit bash solver` — stress-test the solver specifically
- **Recurring stress test:** `/qe-audit bash solver every 6h` — bash the solver every six hours
- **Quality feedback loop:** `/qe-audit` finds gaps, `/fix-issues` fixes them, the next `/qe-audit` validates the fixes

## Tips & Gotchas

- Both modes file GitHub issues for their findings and end with a short report.
- The commit audit examines the commits since the last audit, not the entire codebase; with no new commits it reports that and stops.
- A run that files zero issues is a normal, healthy result — `/qe-audit` only files findings it has confirmed against the actual code and judged worth acting on.
- Bash mode is adversarial — it actively tries to break the feature with edge cases, unusual inputs, and unexpected workflows.
- `/qe-audit` files issues but never fixes them inline; pair it with `/fix-issues` to close what it finds.
- Scheduling follows the same `every SCHEDULE` pattern as the other recurring skills, and the schedule dies when the session dies.
