# /zskills-dashboard

> Local web dashboard -- plans, issues, worktrees, branches, tracking activity, drag-and-drop priority queue. Starts a detached Python HTTP server; stop sends SIGTERM; restart = stop+start.

## Usage

```
/zskills-dashboard [start|stop|status|restart]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `start` | No | Launch detached server, write PID file |
| `stop` | No | SIGTERM the server, remove PID file |
| `status` | No | Report PID, port, uptime, log path (default when no args) |
| `restart` | No | Stop then start (pick up Python code changes) |

## Examples

```
/zskills-dashboard
/zskills-dashboard start
/zskills-dashboard stop
/zskills-dashboard status
/zskills-dashboard restart
```

## Common Patterns

- **Start the dashboard:** `/zskills-dashboard start` -- launch the web dashboard
- **Check status:** `/zskills-dashboard status` (or just `/zskills-dashboard`) -- see if the server is running
- **After code changes:** `/zskills-dashboard restart` -- pick up Python changes
- **Clean shutdown:** `/zskills-dashboard stop` -- SIGTERM the server

## Tips & Gotchas

- The server is a stdlib-only Python HTTP server, localhost-bound
- State is stored in `.zskills/monitor-state.json` with atomic writes
- PID file is at `.zskills/dashboard-server.pid`
- Port resolution uses `DEV_PORT` env var, `dev_server.default_port` from config, or `port.sh`
- Stop uses SIGTERM only -- never escalates to SIGKILL (per CLAUDE.md process-kill rules)
- Process identity checks verify both command name AND cwd to avoid killing wrong processes
- The dashboard survives the parent shell (runs detached)
- `ZSKILLS_DASHBOARD_ROOT` env var overrides the default main-checkout anchor
