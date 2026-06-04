# /plans

> Plan dashboard. View plan status, find the next ready plan. For batch execution, see `/work-on-plans`.

<details class="flow-cmd" open>
<summary>How it runs — read-only</summary>

<div class="flow">
<div class="flow-step"><p>The <strong>agent</strong> scans the plans and parses each one's status</p></div>
<div class="flow-step"><p>It shows every status and the next ready plan — read-only, nothing runs</p></div>
</div>

</details>

## What it does

`/plans` is a read-only dashboard over your plan files. Run it and it shows you,
at a glance, which plans exist, which are ready to run, which are mid-execution,
and which are finished — so you can decide what to work on next without opening
each plan file yourself.

The plain `/plans` view groups your plans into sections — Ready to Run, In
Progress, Needs Review, Complete, Canaries, and Reference — and highlights the
top-priority ready plan with a suggested `/run-plan` command you can copy. Plans
already in progress show how far along they are — for example, four of eight
phases done.

It never changes your plan files. It only reads them to build the dashboard, and
it keeps the displayed information current automatically: whenever your plans
have changed since the last time you looked, `/plans` refreshes before showing
you anything, so you don't see stale status. If it ever can't read your plans, it
reports the error and stops rather than showing you a guess.

## Typical usage

The common way to use it is bare, to survey the landscape before deciding what to
do:

```
/plans
```

When you just want the single next thing to run, ask for it directly — `/plans
next` prints the highest-priority ready plan together with the exact `/run-plan`
command to start it. When you have many plans and can't remember what each one is
about, `/plans details` lists every plan with a one-line description. After
changing or adding plan files you don't need to refresh by hand, but `/plans
rebuild` forces a rescan if you want one.

A natural sequence is to run `/plans` to review the queue, then hand the work off
to `/run-plan` (for one plan) or `/work-on-plans` (to run several in a batch).

## Companion skills

- **`/run-plan`** executes one plan. `/plans next` hands you the exact
  `/run-plan` command for the top-priority ready plan, so the two are designed to
  be used back to back.
- **`/work-on-plans`** runs the ready plans in a batch. `/plans` is the natural
  thing to check first, to review the queue before batch execution kicks off.
- **`/draft-plan`** produces the plan files in the first place; `/plans` then
  surfaces them in the dashboard once they exist.
- **`/zskills-dashboard`** is the interactive status UI for in-flight pipelines.
  `/plans` notes that its ranking is independent of that dashboard's Ready queue,
  and points you there for interactive prioritization.

## Arguments

`/plans` takes one optional positional argument that selects the view. With no
argument it shows the dashboard.

| Argument | Required | Description |
|----------|----------|-------------|
| (no args) | -- | Display the current plan dashboard, highlighting the top-priority ready plan |
| `rebuild` | No | Rescan and reclassify all plans, regenerating the index |
| `next` | No | Show the highest-priority ready-to-run plan with its `/run-plan` command |
| `details` | No | Show every plan with a one-line description, grouped by status |

## Examples

```
/plans
/plans next
/plans details
/plans rebuild
```

## Tips & gotchas

- You rarely need `/plans rebuild` — the bare `/plans` view already refreshes
  itself whenever your plans have changed, so the status you see is current.
- Canaries are shown as a count and never promoted into Ready or In Progress;
  their state reflects tracker bookkeeping, not actual run history.
- To run plans rather than just view them, reach for `/run-plan` (one plan) or
  `/work-on-plans` (a batch) — `/plans` itself only reports.
