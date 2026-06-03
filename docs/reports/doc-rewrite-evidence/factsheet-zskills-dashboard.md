# Fact sheet — `docs/skills/zskills-dashboard.md`

Every factual claim in the rewritten `docs/skills/zskills-dashboard.md`, paired
with the verbatim source line that backs it. Format:
`doc sentence → skills/zskills-dashboard/SKILL.md:LINE: "<verbatim quoted text>"`.
Companion/usage citations use `COMPANIONS.md:LINE` / `USAGE_MAP.md:LINE`.

R5 note: the rewrite strips the implementer-voice internals present in the prior
doc — "stdlib-only Python HTTP server", "atomic writes", "process identity
checks (command name AND cwd)", the PID-file path, the SIGTERM/SIGKILL kill
mechanics, and the "Phase 5" phase reference. Port/PID plumbing is dropped except
the user-observable URL and port-resolution order. `grep -nEf banned-terms.txt
docs/skills/zskills-dashboard.md` returns no hits.

---

## "What it does" section

- It is a local web dashboard for plans, issues, worktrees, branches, tracking
  activity, and a drag-and-drop priority queue →
  skills/zskills-dashboard/SKILL.md:6: "Local web dashboard — plans, issues, worktrees, branches, tracking"
  skills/zskills-dashboard/SKILL.md:7: "activity, drag-and-drop priority queue. Starts a detached Python HTTP"

- It serves a page you open in a browser at a `http://127.0.0.1:<port>/` URL the
  skill prints when it starts →
  skills/zskills-dashboard/SKILL.md:355: "echo \"Dashboard running at http://127.0.0.1:$PORT/  (pid ${NEW_PID:-?}, log $LOG_FILE)\""

- It is a live, interactive view; you reorder the priority queue by dragging →
  skills/zskills-dashboard/SKILL.md:6: "Local web dashboard — plans, issues, worktrees, branches, tracking"
  skills/zskills-dashboard/SKILL.md:7: "activity, drag-and-drop priority queue. Starts a detached Python HTTP"

- The dashboard is the interactive place to prioritize work, the counterpart to
  the read-only `/plans` listing →
  (cross-doc, from /plans SKILL.md cited in COMPANIONS) skills/plans/SKILL.md:187: "   > queue. For interactive prioritization, open /zskills-dashboard."
  COMPANIONS.md:99: "| `zskills-dashboard` | `work-on-plans`, `create-worktree`, `update-zskills` | The status UI for in-flight pipelines; reads what `/work-on-plans` and others write. |"

- If you wire the optional trigger script, the dashboard shows a "Run" button
  that kicks off a `/work-on-plans` run for the queued plans →
  skills/zskills-dashboard/SKILL.md:588: "  to a user-owned trigger script. When set, the dashboard's \"Run\""
  skills/zskills-dashboard/SKILL.md:589: "  button posts to `/api/trigger`, which spawns the script with the"
  skills/zskills-dashboard/SKILL.md:590: "  selected `/work-on-plans` invocation as argv[1]. **No default script"

- The server keeps running in the background after the command returns / stays up
  across sessions →
  skills/zskills-dashboard/SKILL.md:18: "first-class skill. It launches the server detached (so it survives the"
  skills/zskills-dashboard/SKILL.md:19: "parent shell), records the live PID/port in"

- One dashboard serves all your sessions from the main checkout →
  skills/zskills-dashboard/SKILL.md:50: "By default the dashboard anchors to the main checkout so all sessions"
  skills/zskills-dashboard/SKILL.md:51: "share one canonical view."

## "Typical usage" / "Usage" section

- `start` launches the server in the background and prints the URL →
  skills/zskills-dashboard/SKILL.md:32: "/zskills-dashboard start    # launch detached server, write PID file"
  skills/zskills-dashboard/SKILL.md:355: "echo \"Dashboard running at http://127.0.0.1:$PORT/  (pid ${NEW_PID:-?}, log $LOG_FILE)\""

- `status` reports whether it's running, with URL and uptime →
  skills/zskills-dashboard/SKILL.md:34: "/zskills-dashboard status   # report PID, port, uptime, log path"
  skills/zskills-dashboard/SKILL.md:534: "Dashboard running at http://127.0.0.1:$ST_PORT/"
  skills/zskills-dashboard/SKILL.md:537: "  uptime:   $UPTIME_STR"

- `stop` shuts the server down cleanly →
  skills/zskills-dashboard/SKILL.md:33: "/zskills-dashboard stop     # SIGTERM the server, remove PID file"

- `restart` picks up code changes to the dashboard →
  skills/zskills-dashboard/SKILL.md:35: "/zskills-dashboard restart  # stop then start (pick up Python changes)"
  skills/zskills-dashboard/SKILL.md:546: "to take effect. Use `restart` to pick up Python source changes without"

- With no argument, `/zskills-dashboard` reports status →
  skills/zskills-dashboard/SKILL.md:38: "`status` is the default when `$ARGUMENTS` is empty."

- (usage-shape note) `/zskills-dashboard` is interactively typed, not cron-driven
  — argument shapes pulled from the body + argument-hint, not the usage map →
  USAGE_MAP.md:62: "**Never observed in the `Run /<skill>` cron form:** `/create-worktree`,"
  USAGE_MAP.md:64: "`/manual-testing`, `/research-and-go`, `/research-and-plan`, `/zskills-dashboard`."

## "Companion skills" section

- Companions are `/work-on-plans`, `/plans`, `/run-plan` (R6) →
  COMPANIONS.md:99: "| `zskills-dashboard` | `work-on-plans`, `create-worktree`, `update-zskills` | The status UI for in-flight pipelines; reads what `/work-on-plans` and others write. |"
  COMPANIONS.md:88: "| `plans` | `run-plan`, `work-on-plans`, `zskills-dashboard`, `update-zskills` | The plan-catalog index; `/work-on-plans` and `/run-plan` consume the queue it builds. |"

- `/work-on-plans` runs ready plans in a batch; the dashboard's "Run" button
  hands the chosen run off to `/work-on-plans` →
  skills/zskills-dashboard/SKILL.md:589: "  button posts to `/api/trigger`, which spawns the script with the"
  skills/zskills-dashboard/SKILL.md:590: "  selected `/work-on-plans` invocation as argv[1]. **No default script"

- `/plans` is the read-only listing of the same plan status; the dashboard is the
  interactive reprioritization surface →
  (cross-doc) skills/plans/SKILL.md:186: "   > Note: this ranking is independent of the monitor dashboard's Ready"
  skills/plans/SKILL.md:187: "   > queue. For interactive prioritization, open /zskills-dashboard."

- `/run-plan` executes a single plan; the dashboard shows which plans are ready →
  COMPANIONS.md:88: "| `plans` | `run-plan`, `work-on-plans`, `zskills-dashboard`, `update-zskills` | The plan-catalog index; `/work-on-plans` and `/run-plan` consume the queue it builds. |"
  skills/zskills-dashboard/SKILL.md:6: "Local web dashboard — plans, issues, worktrees, branches, tracking"

## "Arguments" section

- The argument-hint lists the four modes →
  skills/zskills-dashboard/SKILL.md:4: "argument-hint: \"[start|stop|status|restart]\""

- `start` launches the server and prints the URL →
  skills/zskills-dashboard/SKILL.md:32: "/zskills-dashboard start    # launch detached server, write PID file"

- `stop` shuts the server down →
  skills/zskills-dashboard/SKILL.md:33: "/zskills-dashboard stop     # SIGTERM the server, remove PID file"

- `status` reports running state with URL and uptime; default with no argument →
  skills/zskills-dashboard/SKILL.md:34: "/zskills-dashboard status   # report PID, port, uptime, log path"
  skills/zskills-dashboard/SKILL.md:38: "`status` is the default when `$ARGUMENTS` is empty."

- `restart` stops then starts to pick up code changes →
  skills/zskills-dashboard/SKILL.md:35: "/zskills-dashboard restart  # stop then start (pick up Python changes)"

- Anything other than the four modes or empty is a usage error →
  skills/zskills-dashboard/SKILL.md:41: "**Parsing rule.** Treat `$ARGUMENTS` as a single token (lowercased,"
  skills/zskills-dashboard/SKILL.md:42: "trimmed). Anything that is not `start`, `stop`, `status`, `restart`,"
  skills/zskills-dashboard/SKILL.md:43: "or empty is a usage error:"

- Both settings come from `.claude/zskills-config.json`, which the dashboard
  reads but never writes →
  skills/zskills-dashboard/SKILL.md:575: "**Read-only boundary.** The server reads `.claude/zskills-config.json`"
  skills/zskills-dashboard/SKILL.md:576: "(never writes); writes only to `.zskills/*` (its own state — PID file,"

- The port comes from `DEV_PORT` env, else `dev_server.default_port`, else a
  default →
  skills/zskills-dashboard/SKILL.md:585: "- `dev_server.default_port` (integer) — default port when neither"
  skills/zskills-dashboard/SKILL.md:586: "  `DEV_PORT` env nor a stub callout overrides. Read by `port.sh`."

- The "Run" button shows only when `dashboard.work_on_plans_trigger` is set to a
  script you provide; no script ships by default; the button is hidden otherwise →
  skills/zskills-dashboard/SKILL.md:590: "  selected `/work-on-plans` invocation as argv[1]. **No default script"
  skills/zskills-dashboard/SKILL.md:591: "  is shipped** — this is plumbing the consumer must wire. If the field"
  skills/zskills-dashboard/SKILL.md:592: "  is absent or empty, the Run button is hidden client-side and"

- Setting `ZSKILLS_DASHBOARD_ROOT` to a worktree path makes the dashboard serve
  that worktree's files; unset, it serves the main checkout (the usual case) →
  skills/zskills-dashboard/SKILL.md:52: "When an agent in a worktree needs to verify"
  skills/zskills-dashboard/SKILL.md:53: "**its own** frontend changes visually, set the `ZSKILLS_DASHBOARD_ROOT`"
  skills/zskills-dashboard/SKILL.md:54: "environment variable to the worktree path before invoking"
  skills/zskills-dashboard/SKILL.md:65: "When the variable is unset or empty, behavior is unchanged — the"
  skills/zskills-dashboard/SKILL.md:66: "dashboard serves from the main checkout as before."
