---
name: zskills-dashboard
disable-model-invocation: true
argument-hint: "[start|stop|status|restart]"
description: >-
  Local web dashboard — plans, issues, worktrees, branches, tracking
  activity, drag-and-drop priority queue. Starts a detached Python HTTP
  server on a port from DEV_PORT / dev_server.default_port / port.sh; stop
  sends SIGTERM; restart = stop+start (for code reloads). State at
  .zskills/monitor-state.json.
metadata:
  version: "2026.06.05+2d9c2f"
---

# /zskills-dashboard — Local Dashboard

`/zskills-dashboard` exposes the Phase 5 Python dashboard server as a
first-class skill. It launches the server detached (so it survives the
parent shell), records the live PID/port in
`.zskills/dashboard-server.pid`, and provides start/stop/status modes.

The server itself is `skills/zskills-dashboard/scripts/zskills_monitor/`
(stdlib-only Python, localhost-bound, atomic-write state). This skill
body wraps it: port resolution, PID-file handling, process-identity
checks (command name AND cwd), tracking markers for state-changing
modes, and a SIGTERM-only stop path on POSIX (CLAUDE.md rule — never
escalate to SIGKILL). On Windows (Git-Bash / MSYS), where Python runs no
SIGTERM handler, stop instead requests a graceful `taskkill //PID`, then
escalates to a TARGETED `taskkill //PID //F` of the single verified PID
(never a port/name mass-kill) — see the stop section.

## Arguments

```
/zskills-dashboard start    # launch detached server, write PID file
/zskills-dashboard stop     # SIGTERM the server, remove PID file
/zskills-dashboard status   # report PID, port, uptime, log path
/zskills-dashboard restart  # stop then start (pick up Python changes)
```

`status` is the default when `$ARGUMENTS` is empty.

**Parsing rule.** Treat `$ARGUMENTS` as a single token (lowercased,
trimmed). Anything that is not `start`, `stop`, `status`, `restart`,
or empty is a usage error:

> Usage: /zskills-dashboard [start|stop|status|restart]

Exit 2.

## Worktree override — `ZSKILLS_DASHBOARD_ROOT`

By default the dashboard anchors to the main checkout so all sessions
share one canonical view.  When an agent in a worktree needs to verify
**its own** frontend changes visually, set the `ZSKILLS_DASHBOARD_ROOT`
environment variable to the worktree path before invoking
`/zskills-dashboard start`:

```
ZSKILLS_DASHBOARD_ROOT=/tmp/zskills-do-foo /zskills-dashboard start
```

This overrides `MAIN_ROOT` in the SKILL.md setup block and passes
`--main-root` to the Python server so that both the collector
(`collect.py:_resolve_main_root`) and the static-file serving use the
worktree's filesystem instead of main's.

When the variable is unset or empty, behavior is unchanged — the
dashboard serves from the main checkout as before.

The Python server also accepts `--main-root DIR` directly on the CLI
(used by tests); the env var is the agent-facing surface.

## Step 0 — Common setup (every mode)

Anchor `MAIN_ROOT` to the main checkout by default.  If
`ZSKILLS_DASHBOARD_ROOT` is set to an existing directory, use that
instead — this is the worktree-override path documented above.
The PID file, log file, and tracking markers all live under
`$MAIN_ROOT/.zskills/`.

```bash
if [ -n "${ZSKILLS_DASHBOARD_ROOT:-}" ] && [ -d "$ZSKILLS_DASHBOARD_ROOT" ]; then
  MAIN_ROOT=$(cd "$ZSKILLS_DASHBOARD_ROOT" && pwd)
elif [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR" ]; then
  MAIN_ROOT=$(cd "$CLAUDE_PROJECT_DIR" && pwd)
else
  MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
fi
PID_FILE="$MAIN_ROOT/.zskills/dashboard-server.pid"
LOG_FILE="$MAIN_ROOT/.zskills/dashboard-server.log"
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}/skills/zskills-dashboard/scripts" ]; then
  PKG_PARENT="${CLAUDE_PLUGIN_ROOT}/skills/zskills-dashboard/scripts"
else
  PKG_PARENT="$MAIN_ROOT/skills/zskills-dashboard/scripts"
fi
# Dual-lane resolution: plugin install (${CLAUDE_PLUGIN_ROOT}) first, then
# .claude/skills/... mirror (legacy /update-zskills install lane), then
# source-tree fallback (zskills repo + tests).
if [ -x "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/port.sh" ]; then
  PORT_SCRIPT="${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/port.sh"
else
  PORT_SCRIPT="$MAIN_ROOT/.claude/skills/update-zskills/scripts/port.sh"
  [ -x "$PORT_SCRIPT" ] || PORT_SCRIPT="$MAIN_ROOT/skills/update-zskills/scripts/port.sh"
fi
if [ -x "${CLAUDE_PLUGIN_ROOT}/skills/create-worktree/scripts/sanitize-pipeline-id.sh" ]; then
  SANITIZE_SCRIPT="${CLAUDE_PLUGIN_ROOT}/skills/create-worktree/scripts/sanitize-pipeline-id.sh"
else
  SANITIZE_SCRIPT="$MAIN_ROOT/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh"
  [ -x "$SANITIZE_SCRIPT" ] || SANITIZE_SCRIPT="$MAIN_ROOT/skills/create-worktree/scripts/sanitize-pipeline-id.sh"
fi

# Server's own scripts dir is in-skill — no install/source split.
mkdir -p "$MAIN_ROOT/.zskills"

# Platform detector (#1093/#1096 stop-path mirror). The PID file holds the
# server's *Windows* PID (os.getpid), so on Git-Bash/MSYS the POSIX
# kill/lsof//proc primitives — which key on MSYS PIDs — target the wrong
# thing. ZSK_WIN gates each POSIX-only operation; the POSIX branch stays
# byte-for-byte unchanged on Linux/macOS (ZSK_WIN=0).
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) ZSK_WIN=1 ;;
  *)                    ZSK_WIN=0 ;;
esac

# port_has_listener PORT — returns 0 if some process is LISTENing on PORT,
# 1 otherwise. Shared by the start pre-flight and the stop release-verify so
# both sites branch on the same platform logic.
#   POSIX:   lsof -iTCP:PORT -sTCP:LISTEN (unchanged from the pre-Windows path)
#   Windows: lsof is ABSENT; netstat IS present. `netstat -ano` lists every
#            socket with state; a LISTENING row for :PORT means in-use.
port_has_listener() {
  local _port="$1"
  if [ "$ZSK_WIN" -eq 1 ]; then
    netstat -ano 2>/dev/null | grep -E ":$_port[[:space:]]" | grep -qi LISTENING
  else
    lsof -iTCP:"$_port" -sTCP:LISTEN >/dev/null 2>&1
  fi
}
```

### Process-identity check (shared by start and stop)

Whenever a PID is read from the PID file, verify TWO things before
trusting it:

1. **Command-name match.** `ps -p $PID -o command=` output must match
   `python[0-9.]*.*zskills_monitor.server` (python or python3 — the launch
   uses `"$PYTHON"`, which may resolve to either, #1083).
2. **Cwd match.** The process's cwd must equal `$MAIN_ROOT`. On Linux
   read `/proc/$PID/cwd`; on macOS or Linux without `/proc`, fall back
   to `lsof -p $PID -d cwd -Fn` and parse the `n<path>` line. If both
   methods fail (permission denied or tool missing), skip the cwd
   check and log a warning to stderr — fall through on command-name
   match alone.

If EITHER check fails (command-name mismatch OR cwd-mismatch when
verifiable), the PID is stale, PID-reused, or belongs to a different
worktree's dashboard — do NOT kill it. Treat the PID file as stale.

**Windows (Git-Bash / MSYS) degraded identity (#1093/#1096 stop-path).**
Windows has neither `/proc` nor `lsof`, and `ps`'s command column does not
carry the `python … zskills_monitor.server` argv reliably — so the POSIX
two-checks cannot run. On Windows (`ZSK_WIN=1`) the helper degrades to three
Windows-tool checks, ALL of which must pass:
  1. **Alive** — `tasklist //FI "PID eq $PID"` lists the PID (liveness).
  2. **Owns our port** — `netstat -ano` shows the PID as the LISTENING
     owner of our port (the `ZSK_IDENTITY_PORT` global the caller sets).
  3. **Image is python** — `tasklist` shows the PID's image as `python*.exe`.
The cwd-identity check is belt-and-suspenders and is simply unavailable on
Windows; "owns our port + is python + alive" is the strongest identity the
platform affords before a targeted kill. Identity is verified BEFORE any
`taskkill`, exactly as the POSIX path verifies before `kill`.

```bash
# Returns 0 if PID is alive AND identity matches; 1 otherwise.
# Stdout is the matched command name (for diagnostics on mismatch).
verify_monitor_identity() {
  local pid="$1"
  local cmd cwd_proc cwd_lsof matched_cwd

  # Windows (Git-Bash / MSYS) degraded identity (#1093/#1096). No /proc, no
  # lsof, and the MSYS `kill -0` keys on MSYS PIDs while the PID file holds
  # the server's Windows PID — so the POSIX path below cannot run here.
  # Three Windows-tool checks, ALL required: alive (tasklist), owns our port
  # (netstat LISTENING owner == PID on ZSK_IDENTITY_PORT), image is python
  # (tasklist image == python*.exe). cwd-identity is unavailable on Windows.
  if [ "${ZSK_WIN:-0}" -eq 1 ]; then
    local tl_line
    # tasklist row for this PID (//NH = no header). 2>/dev/null because a
    # dead PID yields "INFO: No tasks…" on stderr — the expected branch.
    tl_line=$(tasklist //FI "PID eq $pid" //NH 2>/dev/null)
    # Alive: the PID must appear as a whole word in the row.
    if ! printf '%s' "$tl_line" | grep -q "\b$pid\b"; then
      return 1
    fi
    # Image is python*.exe (the server is launched via "$PYTHON").
    if ! printf '%s' "$tl_line" | grep -qiE '(^|[[:space:]])python[0-9.]*\.exe'; then
      printf 'identity-mismatch: image=%s\n' "$(printf '%s' "$tl_line" | awk '{print $1}')" >&2
      return 1
    fi
    # Owns our port: netstat must show the PID as the LISTENING owner of
    # ZSK_IDENTITY_PORT (the last column of a netstat -ano row is the PID).
    if [ -n "${ZSK_IDENTITY_PORT:-}" ]; then
      if ! netstat -ano 2>/dev/null | grep -E ":$ZSK_IDENTITY_PORT[[:space:]]" \
           | grep -i LISTENING | grep -qw "$pid"; then
        printf 'identity-mismatch: PID %s is not the LISTENING owner of port %s\n' "$pid" "$ZSK_IDENTITY_PORT" >&2
        return 1
      fi
    fi
    printf 'python (windows, pid %s, port %s)\n' "$pid" "${ZSK_IDENTITY_PORT:-?}"
    return 0
  fi

  # Liveness — kill -0 with a 2>/dev/null because failure here is the
  # expected branch (dead PID).
  if ! kill -0 "$pid" 2>/dev/null; then
    return 1
  fi

  cmd=$(ps -p "$pid" -o command= || echo "")
  # Match python OR python3 (the launch uses "$PYTHON", which may resolve to
  # either an absolute /…/python or /…/python3 path — #1083).
  if [[ ! "$cmd" =~ python[0-9.]*.*zskills_monitor\.server ]]; then
    printf 'identity-mismatch: command=%s\n' "$cmd" >&2
    return 1
  fi

  # cwd verification — Linux /proc first, lsof fallback. Both
  # operations may fail (tool missing, permissions) — that branch is
  # expected, so 2>/dev/null is allowed here per CLAUDE.md rule
  # exception ("where the failure is the expected branch").
  cwd_proc=$(readlink "/proc/$pid/cwd" 2>/dev/null || echo "")
  if [ -n "$cwd_proc" ]; then
    matched_cwd="$cwd_proc"
  else
    cwd_lsof=$(lsof -p "$pid" -d cwd -Fn 2>/dev/null | awk '/^n/ {sub(/^n/,""); print; exit}')
    if [ -n "$cwd_lsof" ]; then
      matched_cwd="$cwd_lsof"
    else
      # Neither method worked — log and accept command-name match alone.
      printf 'identity-warning: cwd unverifiable for PID %s (no /proc, no lsof output); accepting command-name match\n' "$pid" >&2
      printf '%s\n' "$cmd"
      return 0
    fi
  fi

  if [ "$matched_cwd" != "$MAIN_ROOT" ]; then
    printf 'identity-mismatch: cwd=%s expected=%s\n' "$matched_cwd" "$MAIN_ROOT" >&2
    return 1
  fi

  printf '%s\n' "$cmd"
  return 0
}
```

### Tracking marker helper (state-changing modes only)

`start` and `stop` write a `fulfilled.zskills-dashboard.<id>` marker
under `.zskills/tracking/zskills-dashboard.<id>/`. `status` is
read-only and writes nothing (per Phase 8 spec — avoids flooding
tracking with one subdir per status check).

```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
write_tracking_marker() {
  local mode="$1" pid_val="${2:-}" port_val="${3:-}"
  local raw="zskills-dashboard-$(date -u +%Y%m%dT%H%M%SZ)"
  local id
  id=$(bash "$SANITIZE_SCRIPT" "$raw")
  local subdir="$MAIN_ROOT/.zskills/tracking/zskills-dashboard.$id"
  mkdir -p "$subdir"
  local marker="$subdir/fulfilled.zskills-dashboard.$id"
  {
    printf 'skill: zskills-dashboard\n'
    printf 'id: %s\n' "$id"
    printf 'mode: %s\n' "$mode"
    [ -n "$pid_val" ] && printf 'pid: %s\n' "$pid_val"
    [ -n "$port_val" ] && printf 'port: %s\n' "$port_val"
    printf 'status: complete\n'
    printf 'date: %s\n' "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)"
  } > "$marker"
  echo "ZSKILLS_PIPELINE_ID=zskills-dashboard.$id"
}
```

## Mode dispatch

```bash
SUB="${ARGUMENTS:-status}"
SUB=$(printf '%s' "$SUB" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
[ -z "$SUB" ] && SUB="status"

case "$SUB" in
  start)   ;;
  stop)    ;;
  status)  ;;
  restart) ;;
  *)
    echo "Usage: /zskills-dashboard [start|stop|status|restart]" >&2
    exit 2
    ;;
esac
```

## start — launch detached server

> **Run `start` as a single Bash invocation.** Resolving `$PYTHON`, the pre-flight check, and the detached launch share one shell — execute the steps below inline as one command; do NOT compile them into a helper script (e.g. `.zskills/dashboard-run.sh`).

1. **Inspect existing PID file.** If present, parse `pid` and `port`
   via `BASH_REMATCH`, run liveness + identity check. On match,
   announce "already running" and exit 0. On mismatch, warn and remove
   the stale PID file before continuing.

2. **Resolve the port.** Invoke the canonical `port.sh` (Phase 5's
   resolution chain — `DEV_PORT` env > `dev_server.default_port` >
   stub callout > built-in mapping).

3. **Pre-flight.** If something is already listening on the port,
   print the friendly busy diagnostic and exit 2.

4. **Launch detached.** `nohup "$PYTHON" -m zskills_monitor.server`
   under `cd "$MAIN_ROOT"` with `PYTHONPATH` pointing at
   `$MAIN_ROOT/skills/zskills-dashboard/scripts` so the package is on
   `sys.path` (per DA-5). Redirect stdout+stderr to
   `.zskills/dashboard-server.log`; close stdin to prevent terminal
   read-block; `disown` so the process is detached from the parent
   shell job table.

5. **Verify.** Sleep briefly, then `curl -sf
   http://127.0.0.1:$PORT/api/health` and require `"status":"ok"`.
   On success, print the URL and exit 0; on failure, print the last
   20 lines of the log and exit 1 (do NOT SIGTERM — there may be
   nothing running).

```bash
if [ "$SUB" = "start" ]; then
  # Resolve $PYTHON (Windows MS-Store-stub guard, #1083) for the launch below.
  if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
    export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
    . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
  else
    . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
  fi
  [ -n "$PYTHON" ] || { echo "ERROR: zskills requires Python 3 — install it or set ZSKILLS_PYTHON" >&2; exit 1; }
  EXISTING_PID=""
  EXISTING_PORT=""
  if [ -f "$PID_FILE" ]; then
    PID_BODY=$(cat "$PID_FILE")
    if [[ "$PID_BODY" =~ (^|$'\n')pid=([0-9]+) ]]; then
      EXISTING_PID="${BASH_REMATCH[2]}"
    fi
    if [[ "$PID_BODY" =~ (^|$'\n')port=([0-9]+) ]]; then
      EXISTING_PORT="${BASH_REMATCH[2]}"
    fi

    if [ -n "$EXISTING_PID" ]; then
      # Thread the PID file's port to the identity helper for the Windows
      # degraded "owns our port" check (no-op on POSIX, which uses /proc/lsof).
      ZSK_IDENTITY_PORT="${EXISTING_PORT:-}"
      if verify_monitor_identity "$EXISTING_PID" >/dev/null; then
        echo "already running at http://127.0.0.1:${EXISTING_PORT:-?}/ (pid $EXISTING_PID)"
        write_tracking_marker "start-already-running" "$EXISTING_PID" "${EXISTING_PORT:-}"
        exit 0
      else
        echo "WARN: stale PID file at $PID_FILE (pid $EXISTING_PID does not match zskills_monitor); removing." >&2
        rm -- "$PID_FILE"
      fi
    else
      echo "WARN: PID file $PID_FILE has no parseable pid= line; removing." >&2
      rm -- "$PID_FILE"
    fi
  fi

  # Resolve port via canonical port.sh.
  if [ ! -x "$PORT_SCRIPT" ]; then
    echo "ERROR: port resolver not found at $PORT_SCRIPT" >&2
    exit 1
  fi
  PORT=$(bash "$PORT_SCRIPT")
  if [[ ! "$PORT" =~ ^[0-9]+$ ]]; then
    echo "ERROR: port.sh returned non-numeric value: $PORT" >&2
    exit 1
  fi

  # Pre-flight: refuse if another holder owns the port. port_has_listener
  # branches POSIX (lsof) vs Windows (netstat) internally; the holder
  # diagnostic is lsof-only (POSIX), netstat-derived on Windows.
  if port_has_listener "$PORT"; then
    if [ "$ZSK_WIN" -eq 1 ]; then
      HOLDER=$(netstat -ano 2>/dev/null | grep -E ":$PORT[[:space:]]" | grep -i LISTENING | tr '\n' ' ')
    else
      HOLDER=$(lsof -iTCP:"$PORT" -sTCP:LISTEN -Fpcn 2>/dev/null | head -20 | tr '\n' ' ')
    fi
    echo "ERROR: port $PORT is already in use (holder: $HOLDER). Stop the holder manually or set DEV_PORT to a free port; do NOT use SIGKILL." >&2
    exit 2
  fi

  # Launch detached. cd into MAIN_ROOT so the server's resolve_main_root
  # cwd-walk lands here. PYTHONPATH prepend keeps the package importable
  # without an install. nohup + disown survives parent-shell exit.
  # Note: PYTHONPATH resolves at runtime to either
  # PYTHONPATH=${CLAUDE_PLUGIN_ROOT}/skills/zskills-dashboard/scripts (plugin lane)
  # or PYTHONPATH=$MAIN_ROOT/skills/zskills-dashboard/scripts (source/legacy) —
  # see PKG_PARENT dual-lane resolution above (per DA-5). The path-list
  # separator is interpreter-derived (os.pathsep), NOT a hardcoded ':' —
  # native Windows Python reports ';' even under Git Bash, so a hardcoded
  # ':' (plus the trailing-empty colon from "$PKG_PARENT:${PYTHONPATH:-}")
  # would yield one invalid entry and a ModuleNotFoundError: zskills_monitor.
  DASH_PYSEP=$("$PYTHON" -c 'import os,sys; sys.stdout.write(os.pathsep)')
  if [ -n "${PYTHONPATH:-}" ]; then
    DASH_PYTHONPATH="$PKG_PARENT$DASH_PYSEP$PYTHONPATH"
  else
    DASH_PYTHONPATH="$PKG_PARENT"
  fi
  # When ZSKILLS_DASHBOARD_ROOT is set, pass --main-root so the server's
  # collector reads state from the override path (worktree verification).
  MAIN_ROOT_FLAG=""
  if [ -n "${ZSKILLS_DASHBOARD_ROOT:-}" ]; then
    MAIN_ROOT_FLAG="--main-root $MAIN_ROOT"
  fi
  # Pass --port "$PORT" explicitly so the server binds the SAME port the
  # health-check below probes. Without it the server self-resolves and can
  # land on a different port (e.g. fallback 8080) than $PORT from port.sh,
  # making a healthy server look broken. Export CLAUDE_PLUGIN_ROOT so the
  # server's shipped-helper resolution (briefing.py, port.sh) can find the
  # plugin lane on a mirror-less plugin install.
  ( cd "$MAIN_ROOT" && \
    PYTHONPATH="$DASH_PYTHONPATH" \
    CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}" \
    ZSKILLS_DASHBOARD_ROOT="${ZSKILLS_DASHBOARD_ROOT:-}" \
    nohup "$PYTHON" -m zskills_monitor.server --port "$PORT" $MAIN_ROOT_FLAG \
      > "$LOG_FILE" 2>&1 < /dev/null & disown )

  # Health-check loop — up to ~10s for bind + first response. Python
  # interpreter startup + module imports take 1-2s on common Linux,
  # longer under containers / slow CI; we don't want a healthy server
  # to look "broken" because the parent shell polled too eagerly.
  HEALTHY=0
  HEALTH_BODY=""
  for _ in $(seq 1 40); do
    sleep 0.25
    HEALTH_BODY=$(curl -sf -m 1 "http://127.0.0.1:$PORT/api/health" || true)
    # Server emits JSON with `"status": "ok"` (note the space after the
    # colon — Python's json.dumps default). Tolerate either spacing in
    # the assertion.
    if printf '%s' "$HEALTH_BODY" | grep -qE '"status":[[:space:]]*"ok"'; then
      HEALTHY=1
      break
    fi
  done

  if [ "$HEALTHY" -ne 1 ]; then
    echo "ERROR: server did not respond on http://127.0.0.1:$PORT/api/health within 10s." >&2
    echo "Last 20 lines of $LOG_FILE:" >&2
    tail -n 20 "$LOG_FILE" >&2 || true
    exit 1
  fi

  # Verify PID file landed (server writes it after bind). Read pid for
  # the tracking marker.
  if [ ! -f "$PID_FILE" ]; then
    echo "ERROR: server is healthy but PID file was not written at $PID_FILE." >&2
    exit 1
  fi
  PIDFILE_BODY=$(cat "$PID_FILE")
  NEW_PID=""
  if [[ "$PIDFILE_BODY" =~ (^|$'\n')pid=([0-9]+) ]]; then
    NEW_PID="${BASH_REMATCH[2]}"
  fi

  echo "Dashboard running at http://127.0.0.1:$PORT/  (pid ${NEW_PID:-?}, log $LOG_FILE)"
  write_tracking_marker "start" "$NEW_PID" "$PORT"
  exit 0
fi
```

## stop — SIGTERM and clean up

1. No PID file → "No running dashboard (no PID file)." Exit 0
   (idempotent).

2. Parse `pid` and `port`. If the PID is not alive, the file is stale
   — remove it and exit 0.

3. **Process-identity check** (command name AND cwd on POSIX; degraded
   alive + owns-our-port + is-python on Windows, per F-11 and #1093/#1096).
   If it fails, print the mismatch diagnostic and **refuse to kill** — exit
   1 without touching the unrelated process.

4. **POSIX:** `kill -TERM $PID`. Poll `kill -0 $PID` every 200ms for up to
   5s. **Windows:** the PID file holds the server's Windows PID and Python
   on Windows runs no SIGTERM handler, so a graceful close is requested via
   `taskkill //PID $PID` FIRST (no `//F`), polling liveness via `tasklist`
   for up to 5s.

5. **POSIX:** if still alive after 5s, refuse to escalate to SIGKILL
   (CLAUDE.md rule) — print a manual-recovery message and exit 1.
   **Windows:** if still alive after the bounded wait, escalate to
   `taskkill //PID $PID //F` — a *targeted* force-terminate of the SINGLE
   verified PID (identity already confirmed above), NOT a port/name
   mass-kill. The skill removes the PID file itself afterward, since the
   force-terminate runs no Python cleanup handler.

6. Verify the port is free (`lsof` on POSIX, `netstat` on Windows, via
   `port_has_listener`). Remove the PID file. Exit 0.

```bash
if [ "$SUB" = "stop" ]; then
  if [ ! -f "$PID_FILE" ]; then
    echo "No running dashboard (no PID file)."
    write_tracking_marker "stop-no-pidfile"
    exit 0
  fi

  PID_BODY=$(cat "$PID_FILE")
  STOP_PID=""
  STOP_PORT=""
  if [[ "$PID_BODY" =~ (^|$'\n')pid=([0-9]+) ]]; then
    STOP_PID="${BASH_REMATCH[2]}"
  fi
  if [[ "$PID_BODY" =~ (^|$'\n')port=([0-9]+) ]]; then
    STOP_PORT="${BASH_REMATCH[2]}"
  fi

  if [ -z "$STOP_PID" ]; then
    echo "ERROR: PID file at $PID_FILE has no parseable pid= line; remove it manually." >&2
    exit 1
  fi

  # Liveness — POSIX `kill -0` keys on MSYS PIDs and the PID file holds the
  # server's *Windows* PID, so on Windows liveness goes through tasklist.
  # In both branches failure here is the expected (dead-PID) path. The POSIX
  # branch is byte-for-byte the original `kill -0` stale-check.
  if [ "$ZSK_WIN" -eq 1 ]; then
    if ! tasklist //FI "PID eq $STOP_PID" //NH 2>/dev/null | grep -q "\b$STOP_PID\b"; then
      echo "Dashboard PID file is stale (PID $STOP_PID is not running). Removing $PID_FILE."
      rm -- "$PID_FILE"
      write_tracking_marker "stop-stale-pidfile" "$STOP_PID" "${STOP_PORT:-}"
      exit 0
    fi
  else
    # kill -0 — failure is the expected branch (dead PID), so 2>/dev/null
    # is allowed here per CLAUDE.md rule.
    if ! kill -0 "$STOP_PID" 2>/dev/null; then
      echo "Dashboard PID file is stale (PID $STOP_PID is not running). Removing $PID_FILE."
      rm -- "$PID_FILE"
      write_tracking_marker "stop-stale-pidfile" "$STOP_PID" "${STOP_PORT:-}"
      exit 0
    fi
  fi

  # Identity check — refuse to kill on mismatch. Thread the PID file's port
  # to the helper for the Windows degraded "owns our port" check (no-op on
  # POSIX, which uses command-name + /proc/lsof cwd).
  ZSK_IDENTITY_PORT="${STOP_PORT:-}"
  IDENTITY_CMD=""
  if ! IDENTITY_CMD=$(verify_monitor_identity "$STOP_PID"); then
    # Re-read for diagnostics. POSIX uses ps/proc/lsof (absent on Windows);
    # Windows uses tasklist + netstat.
    if [ "$ZSK_WIN" -eq 1 ]; then
      DIAG_CMD=$(tasklist //FI "PID eq $STOP_PID" //NH 2>/dev/null | awk '{print $1}' || echo "<gone>")
      DIAG_CWD="<unavailable-on-windows>"
    else
      DIAG_CMD=$(ps -p "$STOP_PID" -o command= || echo "<gone>")
      DIAG_CWD=$(readlink "/proc/$STOP_PID/cwd" 2>/dev/null \
        || lsof -p "$STOP_PID" -d cwd -Fn 2>/dev/null | awk '/^n/ {sub(/^n/,""); print; exit}' \
        || echo "<unknown>")
    fi
    echo "PID $STOP_PID does not appear to be zskills-dashboard for this repo (matched: $DIAG_CMD; cwd: $DIAG_CWD). Refusing to kill. Remove the PID file manually if stale." >&2
    exit 1
  fi

  if [ "$ZSK_WIN" -eq 1 ]; then
    # Windows: Python runs no SIGTERM handler, so request a graceful close
    # via `taskkill //PID` FIRST (no //F). This is a TARGETED kill of the
    # SINGLE verified PID from the PID file — identity confirmed above — NOT
    # a port/name mass-kill, so it is consistent with the "never escalate to
    # a process-mass-kill tool" rule (that rule targets mass-kills).
    taskkill //PID "$STOP_PID" >/dev/null 2>&1 || true
    EXITED=0
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do
      if ! tasklist //FI "PID eq $STOP_PID" //NH 2>/dev/null | grep -q "\b$STOP_PID\b"; then
        EXITED=1
        break
      fi
      sleep 0.2
    done
    if [ "$EXITED" -ne 1 ]; then
      # Bounded graceful wait elapsed — escalate to a TARGETED force-terminate
      # of the SINGLE verified PID (//F). Still NOT a mass-kill. The skill
      # removes the PID file itself below since //F runs no Python cleanup.
      taskkill //PID "$STOP_PID" //F >/dev/null 2>&1 || true
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        if ! tasklist //FI "PID eq $STOP_PID" //NH 2>/dev/null | grep -q "\b$STOP_PID\b"; then
          EXITED=1
          break
        fi
        sleep 0.2
      done
      if [ "$EXITED" -ne 1 ]; then
        echo "Dashboard did not exit after taskkill //F for PID $STOP_PID (port $STOP_PORT). Investigate manually." >&2
        exit 1
      fi
    fi
  else
    # SIGTERM only — never escalate to SIGKILL or use process-mass-kill tools.
    if ! kill -TERM "$STOP_PID"; then
      echo "ERROR: kill -TERM $STOP_PID failed." >&2
      exit 1
    fi

    # Poll for exit (up to ~5s, 200ms granularity).
    EXITED=0
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do
      if ! kill -0 "$STOP_PID" 2>/dev/null; then
        EXITED=1
        break
      fi
      sleep 0.2
    done

    if [ "$EXITED" -ne 1 ]; then
      echo "Dashboard did not exit within 5s. Run 'lsof -i :$STOP_PORT' and stop manually; do NOT escalate to SIGKILL." >&2
      exit 1
    fi
  fi

  # Verify port released. A still-present listener after exit is suspicious.
  # port_has_listener branches lsof (POSIX) vs netstat (Windows) internally.
  if [ -n "$STOP_PORT" ]; then
    if port_has_listener "$STOP_PORT"; then
      echo "WARN: PID $STOP_PID is gone but port $STOP_PORT still has a listener. Investigate before next start." >&2
    fi
  fi

  # Remove PID file (server's own SIGTERM handler already removes it,
  # but belt-and-suspenders for cases where the file outlived the process).
  if [ -f "$PID_FILE" ]; then
    rm -- "$PID_FILE"
  fi

  echo "Dashboard stopped (pid $STOP_PID, port ${STOP_PORT:-?})."
  write_tracking_marker "stop" "$STOP_PID" "${STOP_PORT:-}"
  exit 0
fi
```

## status — read-only health report

1. No PID file → "Dashboard not running." Exit 0.

2. Parse `pid`, `port`, `started_at` via `BASH_REMATCH`. If
   `started_at` does not match `^[0-9T:+-]+$`, treat the PID file as
   malformed: print a recovery diagnostic and exit 1 (per DA-8).

3. `kill -0 $PID`. If the process is dead, the PID file is stale —
   print a recovery message and exit 1 (do NOT auto-clean; status is
   read-only).

4. Compute uptime from `started_at` (ISO-8601) using `date -d`
   arithmetic; print URL, PID, uptime, log path. Exit 0.

```bash
if [ "$SUB" = "status" ]; then
  if [ ! -f "$PID_FILE" ]; then
    echo "Dashboard not running."
    exit 0
  fi

  PID_BODY=$(cat "$PID_FILE")
  ST_PID=""
  ST_PORT=""
  ST_STARTED=""
  if [[ "$PID_BODY" =~ (^|$'\n')pid=([0-9]+) ]]; then
    ST_PID="${BASH_REMATCH[2]}"
  fi
  if [[ "$PID_BODY" =~ (^|$'\n')port=([0-9]+) ]]; then
    ST_PORT="${BASH_REMATCH[2]}"
  fi
  if [[ "$PID_BODY" =~ (^|$'\n')started_at=([^[:space:]]+) ]]; then
    ST_STARTED="${BASH_REMATCH[2]}"
  fi

  if [ -z "$ST_PID" ] || [ -z "$ST_PORT" ] || [ -z "$ST_STARTED" ]; then
    echo "PID file at $PID_FILE is missing required fields (pid/port/started_at). rm it and retry /zskills-dashboard start" >&2
    exit 1
  fi

  if [[ ! "$ST_STARTED" =~ ^[0-9T:+-]+$ ]]; then
    echo "PID file at $PID_FILE has malformed started_at; rm it and retry /zskills-dashboard start" >&2
    exit 1
  fi

  # kill -0 — failure is the expected branch (dead PID), so 2>/dev/null
  # is allowed here per CLAUDE.md rule.
  if ! kill -0 "$ST_PID" 2>/dev/null; then
    echo "Dashboard PID file is stale (PID $ST_PID not running). Run 'lsof -i :$ST_PORT' to verify port is free, then retry /zskills-dashboard start." >&2
    exit 1
  fi

  # Compute uptime via GNU date arithmetic. The started_at line is ISO-8601
  # with timezone, which `date -d` accepts directly.
  NOW_EPOCH=$(date +%s)
  STARTED_EPOCH=$(date -d "$ST_STARTED" +%s 2>/dev/null || echo "")
  if [ -z "$STARTED_EPOCH" ]; then
    UPTIME_STR="(uptime unknown — date -d could not parse '$ST_STARTED')"
  else
    SECS=$((NOW_EPOCH - STARTED_EPOCH))
    [ "$SECS" -lt 0 ] && SECS=0
    H=$((SECS / 3600))
    M=$(((SECS % 3600) / 60))
    S=$((SECS % 60))
    UPTIME_STR=$(printf '%dh %dm %ds' "$H" "$M" "$S")
  fi

  cat <<STATUS_EOF
Dashboard running at http://127.0.0.1:$ST_PORT/
  pid:      $ST_PID
  started:  $ST_STARTED
  uptime:   $UPTIME_STR
  log:      $LOG_FILE
STATUS_EOF
  exit 0
fi
```

## restart — stop then start

Equivalent to `/zskills-dashboard stop` followed by `/zskills-dashboard start`. The long-running Python process imports modules once at startup; static HTML/CSS/JS is read from disk per-request, but a change to `skills/zskills-dashboard/scripts/zskills_monitor/*.py` (server, collector, route handlers) requires the process to restart to take effect. Use `restart` to pick up Python source changes without manually issuing two commands.

**Procedure when `$SUB == "restart"`:**

1. **Run the stop procedure** (the entire `## stop — SIGTERM and clean up` section above):
   - If `$PID_FILE` does not exist, the stop is a no-op (no running server to terminate); continue to step 2.
   - If `$PID_FILE` exists, run stop's steps 1–6 verbatim. Identity-check refusals abort the restart with the same exit-1 contract as plain `stop`; do NOT proceed to start a competing server.
   - On successful stop (or stale-pid cleanup), the PID file is removed and a tracking marker is written.
2. **Run the start procedure** (the entire `## start — launch detached server` section above), steps 1–5 verbatim. A second tracking marker is written. The restart event is captured as the marker pair.

The skill is interpreted by Claude top-to-bottom. When dispatching `restart`, run the two procedures above in sequence — there is no duplicate bash block here because both pieces already exist verbatim higher in this file. Treat the restart as the literal composition `stop && start`.

## Mirror

After every edit, regenerate the `.claude/skills/zskills-dashboard/`
mirror via the Tier-2 hook-compatible script:

```bash
bash scripts/mirror-skill.sh zskills-dashboard
```

`mirror-skill.sh` does per-file `rm` for orphan removal — it never
invokes a recursive remove of the mirror tree, which the project's
`block-unsafe-generic.sh` hook would block. After the script returns,
`diff -rq skills/zskills-dashboard/ .claude/skills/zskills-dashboard/`
must be empty.

## Configuration

**Read-only boundary.** The server reads `.claude/zskills-config.json`
(never writes); writes only to `.zskills/*` (its own state — PID file,
log file, monitor-state.json, tracking markers). The server treats
absent/missing fields as empty rather than mutating user config.

The dashboard reads `.claude/zskills-config.json` for one field:

- `dev_server.default_port` (integer) — default port when neither
  `DEV_PORT` env nor a stub callout overrides. Read by `port.sh`.

## Tracking markers

`start` and `stop` (and their no-op / stale variants) write a
`fulfilled.zskills-dashboard.<id>` under
`.zskills/tracking/zskills-dashboard.<id>/`. The id is
`zskills-dashboard-<utc-timestamp>` passed through
`sanitize-pipeline-id.sh`. Subdir-name layout is Option B per
`docs/tracking/TRACKING_NAMING.md`.

`status` is read-only and writes nothing.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success (server running, stopped cleanly, or no-op idempotent path) |
| 1 | Health check failed, identity mismatch (refused to kill), stale PID file under `status`, or PID-file malformed |
| 2 | Usage error, port already in use under `start`, or unknown subcommand |

## Key rules

- **SIGTERM only (POSIX); targeted taskkill (Windows).** On POSIX, never
  escalate to SIGKILL and never reach for process-mass-kill tools (the
  obvious ones are forbidden by CLAUDE.md); on a stuck process, surface
  manual-recovery instructions and exit 1. On Windows (Git-Bash / MSYS),
  Python runs no SIGTERM handler, so stop requests a graceful
  `taskkill //PID $PID` and, if still alive after the bounded wait,
  escalates to `taskkill //PID $PID //F` — a TARGETED force-terminate of
  the SINGLE verified PID from the PID file (identity confirmed first),
  NEVER a port/name mass-kill. This is consistent with the mass-kill
  prohibition, which targets unverified-PID-source mass-kills.
- **Never bypass identity check.** On POSIX both command-name AND cwd must
  match before `stop` will signal a PID; on Windows the degraded check
  (alive + owns-our-port + is-python) must pass. Same defense applies on
  `start` when checking an existing PID file.
- **No JSON CLI parser.** Use `BASH_REMATCH` for all parsing (PID
  file is `.env`-style; config reads via `port.sh`'s own bash regex).
  Per zskills convention.
- **No `2>/dev/null` on fallible operations.** The two exceptions
  documented in CLAUDE.md apply here: `kill -0` (liveness — failure
  IS the dead-PID branch) and `readlink /proc/$PID/cwd` /
  `lsof -p ... -d cwd` (non-Linux fallback — failure IS the missing-
  /proc branch).
- **MAIN_ROOT-anchored paths.** Every read/write goes through
  `$MAIN_ROOT/.zskills/...`, never cwd-relative — invoking the skill
  from a worktree must still see the main repo's PID file.
- **PYTHONPATH discipline.** `start` prepends `$PKG_PARENT` to
  `PYTHONPATH` — resolved dual-lane to
  `${CLAUDE_PLUGIN_ROOT}/skills/zskills-dashboard/scripts` (plugin lane)
  or `$MAIN_ROOT/skills/zskills-dashboard/scripts` (source/legacy) — so
  `python3 -m zskills_monitor.server` resolves the package without an
  install step (per DA-5). The path-list separator is interpreter-derived
  (`$("$PYTHON" -c '...os.pathsep')`), not a hardcoded `:` — native Windows
  Python reports `;` even under Git Bash, and the prepend avoids a
  trailing-empty separator so no invalid entry is produced.
- **Verify after every state change.** `start` curls
  `/api/health`; `stop` polls `kill -0` then verifies the port is
  freed via `lsof`.
- **Tracking markers for state-changing modes only.** `start` and
  `stop` write `fulfilled.zskills-dashboard.<id>`; `status` does not.
- **Mirror via `scripts/mirror-skill.sh`** — never use a recursive
  remove on the mirror tree (hook will block).
