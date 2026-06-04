# /zskills-dashboard

> Local web dashboard for plan, issue, and run status — plans, issues, worktrees, branches, tracking activity, and a drag-and-drop priority queue. `start` launches it, `stop` shuts it down, `status` reports whether it's running, `restart` picks up code changes.

<details class="flow-cmd" open>
<summary>How it runs — local web UI</summary>

<div class="flow">
<div class="flow-step"><p>The <strong>agent</strong> starts the dashboard server, detached</p></div>
<div class="flow-step"><p><strong>You</strong> view plans, issues, and worktrees in the browser</p></div>
<div class="flow-step"><p><strong>You</strong> drag cards to prioritize across the Accepted and Ready columns</p></div>
<div class="flow-step optional"><p><strong>You</strong> can hit the Run button to trigger a run</p></div>
</div>

</details>

## What it does

`/zskills-dashboard` runs a small web dashboard on your own machine that gives you one place to see what's in flight: your plan files, open issues, worktrees, branches, and the tracking activity of running pipelines. It serves a page you open in a browser at a `http://127.0.0.1:<port>/` URL the skill prints when it starts.

The dashboard is a live view, not a report. From it you can see which plans are ready, in progress, or done, and you can reorder the priority queue by dragging entries — the dashboard is the interactive place to prioritize work, the counterpart to the read-only `/plans` listing. If you have wired up the optional trigger script (see Arguments), the dashboard also shows a "Run" button that kicks off a `/work-on-plans` run for the plans you've queued.

The server keeps running in the background after the command returns, so the dashboard stays up across sessions; one dashboard serves all your sessions from the main checkout. You start it once and leave it running, check on it with `status`, and shut it down with `stop` when you're done.

## Usage

```
/zskills-dashboard [start|stop|status|restart]
```

With no argument, `/zskills-dashboard` reports status.

## Typical usage

You start the dashboard once and leave it up:

```
/zskills-dashboard start
```

That prints the URL to open in your browser. Later, check whether it's still running and how long it's been up:

```
/zskills-dashboard status
```

When you're done, shut it down cleanly:

```
/zskills-dashboard stop
```

If you've changed the dashboard's own code and want the running server to pick up the change, restart it:

```
/zskills-dashboard restart
```

## Companion skills

- **`/work-on-plans`** runs the ready plans in a batch. The dashboard's priority queue is where you decide their order; its optional "Run" button hands the chosen run off to `/work-on-plans`.
- **`/plans`** is the read-only command-line listing of the same plan status the dashboard shows. Use `/plans` for a quick text survey; open `/zskills-dashboard` when you want to drag entries and reprioritize interactively.
- **`/run-plan`** executes a single plan. The dashboard shows you which plans are ready so you can pick one to run.

## Arguments

`/zskills-dashboard` takes one optional positional argument naming the action. With no argument it reports status.

| Argument | Required | Description |
|----------|----------|-------------|
| `start` | No | Launch the dashboard server in the background and print the URL |
| `stop` | No | Shut the dashboard server down cleanly |
| `status` | No | Report whether the server is running, with its URL and uptime (the default when you give no argument) |
| `restart` | No | Stop and start again, to pick up code changes to the dashboard |

Anything other than `start`, `stop`, `status`, `restart`, or nothing is a usage error.

Two optional settings affect the dashboard, both read from `.claude/zskills-config.json` (the dashboard never writes your config):

- The port the dashboard listens on comes from the `DEV_PORT` environment variable if set, otherwise the `dev_server.default_port` config field, otherwise a default. `start` prints the resulting URL.
- The "Run" button is shown only when you set `dashboard.work_on_plans_trigger` to a small trigger script you provide. No script ships by default; until you wire one, the button is hidden.

If you're working in a worktree and want the dashboard to show that worktree's files instead of the main checkout, set the `ZSKILLS_DASHBOARD_ROOT` environment variable to the worktree path before running `/zskills-dashboard start`. Left unset, the dashboard serves the main checkout, which is the usual case.
