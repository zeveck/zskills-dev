---
name: zskills-dashboard
disable-model-invocation: true
argument-hint: "[start|stop|status]"
description: >-
  Local web dashboard for this repo — plans, issues, worktrees,
  branches, tracking activity, drag-and-drop priority queue.
  Starts a detached Python HTTP server on a port resolved from
  DEV_PORT / dev_server.default_port / port.sh; stop sends SIGTERM.
  State at .zskills/monitor-state.json. Usage:
  /zskills-dashboard [start|stop|status].
---

# /zskills-dashboard — Local Monitor Dashboard

`/zskills-dashboard` exposes the Phase 5 Python monitor server as a
first-class skill. It launches the server detached (so it survives the
parent shell), records the live PID/port in
`.zskills/dashboard-server.pid`, and provides start/stop/status modes.

The server itself is `skills/zskills-dashboard/scripts/zskills_monitor/`
(stdlib-only Python, localhost-bound, atomic-write state). This skill
body wraps it: port resolution, PID-file handling, process-identity
checks (command name AND cwd), tracking markers for state-changing
modes, and a SIGTERM-only stop path (CLAUDE.md rule — never escalate
to SIGKILL).

## Arguments

```
/zskills-dashboard start    # launch detached server, write PID file
/zskills-dashboard stop     # SIGTERM the server, remove PID file
/zskills-dashboard status   # report PID, port, uptime, log path
```

`status` is the default when `$ARGUMENTS` is empty.

**Parsing rule.** Treat `$ARGUMENTS` as a single token (lowercased,
trimmed). Anything that is not `start`, `stop`, `status`, or empty is
a usage error:

> Usage: /zskills-dashboard [start|stop|status]

Exit 2.

## Step 0 — Common setup (every mode)

Anchor `MAIN_ROOT` to the main checkout regardless of which worktree
the skill was invoked from. The PID file, log file, and tracking
markers all live under `$MAIN_ROOT/.zskills/`.

```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
PID_FILE="$MAIN_ROOT/.zskills/dashboard-server.pid"
LOG_FILE="$MAIN_ROOT/.zskills/dashboard-server.log"
PKG_PARENT="$MAIN_ROOT/skills/zskills-dashboard/scripts"
PORT_SCRIPT="$MAIN_ROOT/.claude/skills/update-zskills/scripts/port.sh"
SANITIZE_SCRIPT="$MAIN_ROOT/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh"

# Source-tree fallback (zskills repo + tests). In normal installed use the
# .claude/skills/... paths are canonical.
[ -x "$PORT_SCRIPT" ] || PORT_SCRIPT="$MAIN_ROOT/skills/update-zskills/scripts/port.sh"
[ -x "$SANITIZE_SCRIPT" ] || SANITIZE_SCRIPT="$MAIN_ROOT/skills/create-worktree/scripts/sanitize-pipeline-id.sh"

# Server's own scripts dir is in-skill — no install/source split.
mkdir -p "$MAIN_ROOT/.zskills"
```

### Process-identity check (shared by start and stop)

Whenever a PID is read from the PID file, verify TWO things before
trusting it:

1. **Command-name match.** `ps -p $PID -o command=` output must match
   `python3.*zskills_monitor.server`.
2. **Cwd match.** The process's cwd must equal `$MAIN_ROOT`. On Linux
   read `/proc/$PID/cwd`; on macOS or Linux without `/proc`, fall back
   to `lsof -p $PID -d cwd -Fn` and parse the `n<path>` line. If both
   methods fail (permission denied or tool missing), skip the cwd
   check and log a warning to stderr — fall through on command-name
   match alone.

If EITHER check fails (command-name mismatch OR cwd-mismatch when
verifiable), the PID is stale, PID-reused, or belongs to a different
worktree's monitor — do NOT kill it. Treat the PID file as stale.

```bash
# Returns 0 if PID is alive AND identity matches; 1 otherwise.
# Stdout is the matched command name (for diagnostics on mismatch).
verify_monitor_identity() {
  local pid="$1"
  local cmd cwd_proc cwd_lsof matched_cwd

  # Liveness — kill -0 with a 2>/dev/null because failure here is the
  # expected branch (dead PID).
  if ! kill -0 "$pid" 2>/dev/null; then
    return 1
  fi

  cmd=$(ps -p "$pid" -o command= || echo "")
  if [[ ! "$cmd" =~ python3.*zskills_monitor\.server ]]; then
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
    printf 'date: %s\n' "$(TZ=America/New_York date -Iseconds)"
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
  start)  ;;
  stop)   ;;
  status) ;;
  *)
    echo "Usage: /zskills-dashboard [start|stop|status]" >&2
    exit 2
    ;;
esac
```

## start — launch detached server

1. **Inspect existing PID file.** If present, parse `pid` and `port`
   via `BASH_REMATCH`, run liveness + identity check. On match,
   announce "already running" and exit 0. On mismatch, warn and remove
   the stale PID file before continuing.

2. **Resolve the port.** Invoke the canonical `port.sh` (Phase 5's
   resolution chain — `DEV_PORT` env > `dev_server.default_port` >
   stub callout > built-in mapping).

3. **Pre-flight.** If something is already listening on the port,
   print the friendly busy diagnostic and exit 2.

4. **Launch detached.** `nohup python3 -m zskills_monitor.server`
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

  # Pre-flight: refuse if another holder owns the port.
  if lsof -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    HOLDER=$(lsof -iTCP:"$PORT" -sTCP:LISTEN -Fpcn 2>/dev/null | head -20 | tr '\n' ' ')
    echo "ERROR: port $PORT is already in use (holder: $HOLDER). Stop the holder manually or set DEV_PORT to a free port; do NOT use SIGKILL." >&2
    exit 2
  fi

  # Launch detached. cd into MAIN_ROOT so the server's resolve_main_root
  # cwd-walk lands here. PYTHONPATH prepend keeps the package importable
  # without an install. nohup + disown survives parent-shell exit.
  # Note: PYTHONPATH="$PKG_PARENT:..." resolves at runtime to
  # PYTHONPATH=$MAIN_ROOT/skills/zskills-dashboard/scripts:... (per DA-5).
  ( cd "$MAIN_ROOT" && \
    PYTHONPATH="$PKG_PARENT:${PYTHONPATH:-}" \
    nohup python3 -m zskills_monitor.server \
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

  echo "Monitor running at http://127.0.0.1:$PORT/  (pid ${NEW_PID:-?}, log $LOG_FILE)"
  write_tracking_marker "start" "$NEW_PID" "$PORT"
  exit 0
fi
```

## stop — SIGTERM and clean up

1. No PID file → "No running monitor (no PID file)." Exit 0
   (idempotent).

2. Parse `pid` and `port`. If the PID is not alive, the file is stale
   — remove it and exit 0.

3. **Process-identity check** (command name AND cwd, per F-11). If
   EITHER fails, print the mismatch diagnostic and **refuse to kill**
   — exit 1 without touching the unrelated process.

4. `kill -TERM $PID`. Poll `kill -0 $PID` every 200ms for up to 5s.

5. If the process is still alive after 5s, refuse to escalate to
   SIGKILL (CLAUDE.md rule). Print a manual-recovery message and
   exit 1.

6. Verify the port is free with `lsof`. Remove the PID file. Exit 0.

```bash
if [ "$SUB" = "stop" ]; then
  if [ ! -f "$PID_FILE" ]; then
    echo "No running monitor (no PID file)."
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

  # kill -0 — failure is the expected branch (dead PID), so 2>/dev/null
  # is allowed here per CLAUDE.md rule.
  if ! kill -0 "$STOP_PID" 2>/dev/null; then
    echo "Monitor PID file is stale (PID $STOP_PID is not running). Removing $PID_FILE."
    rm -- "$PID_FILE"
    write_tracking_marker "stop-stale-pidfile" "$STOP_PID" "${STOP_PORT:-}"
    exit 0
  fi

  # Identity check — refuse to kill on either command-name OR cwd mismatch.
  IDENTITY_CMD=""
  if ! IDENTITY_CMD=$(verify_monitor_identity "$STOP_PID"); then
    # Re-read for diagnostics.
    DIAG_CMD=$(ps -p "$STOP_PID" -o command= || echo "<gone>")
    DIAG_CWD=$(readlink "/proc/$STOP_PID/cwd" 2>/dev/null \
      || lsof -p "$STOP_PID" -d cwd -Fn 2>/dev/null | awk '/^n/ {sub(/^n/,""); print; exit}' \
      || echo "<unknown>")
    echo "PID $STOP_PID does not appear to be zskills-monitor for this repo (matched: $DIAG_CMD; cwd: $DIAG_CWD). Refusing to kill. Remove the PID file manually if stale." >&2
    exit 1
  fi

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
    echo "Monitor did not exit within 5s. Run 'lsof -i :$STOP_PORT' and stop manually; do NOT escalate to SIGKILL." >&2
    exit 1
  fi

  # Verify port released. lsof returning 0 (still LISTENing) is failure.
  if [ -n "$STOP_PORT" ]; then
    if lsof -iTCP:"$STOP_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
      echo "WARN: PID $STOP_PID is gone but port $STOP_PORT still has a listener. Investigate before next start." >&2
    fi
  fi

  # Remove PID file (server's own SIGTERM handler already removes it,
  # but belt-and-suspenders for cases where the file outlived the process).
  if [ -f "$PID_FILE" ]; then
    rm -- "$PID_FILE"
  fi

  echo "Monitor stopped (pid $STOP_PID, port ${STOP_PORT:-?})."
  write_tracking_marker "stop" "$STOP_PID" "${STOP_PORT:-}"
  exit 0
fi
```

## status — read-only health report

1. No PID file → "Monitor not running." Exit 0.

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
    echo "Monitor not running."
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
    echo "Monitor PID file is stale (PID $ST_PID not running). Run 'lsof -i :$ST_PORT' to verify port is free, then retry /zskills-dashboard start." >&2
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
Monitor running at http://127.0.0.1:$ST_PORT/
  pid:      $ST_PID
  started:  $ST_STARTED
  uptime:   $UPTIME_STR
  log:      $LOG_FILE
STATUS_EOF
  exit 0
fi
```

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

The dashboard reads `.claude/zskills-config.json` for two fields:

- `dev_server.default_port` (integer) — default port when neither
  `DEV_PORT` env nor a stub callout overrides. Read by `port.sh`.
- `dashboard.work_on_plans_trigger` (string, optional) — relative path
  to a user-owned trigger script. When set, the dashboard's "Run"
  button posts to `/api/trigger`, which spawns the script with the
  selected `/work-on-plans` invocation as argv[1]. **No default script
  is shipped** — this is plumbing the consumer must wire. If the field
  is absent or empty, the Run button is hidden client-side and
  `/api/trigger` returns 501.

Example `dashboard.work_on_plans_trigger` (consumer-authored):

```bash
#!/bin/bash
# scripts/work-on-plans-trigger.sh — consumer-owned plumbing for the
# dashboard's Run button. argv[1] is the /work-on-plans command line.
exec >>".zskills/work-on-plans-trigger.log" 2>&1
echo "[$(date -Iseconds)] trigger: $1"
# Drop a request file your session-watching tool can pick up:
mkdir -p .zskills/triggers
printf '%s\n' "$1" > ".zskills/triggers/$(date -u +%Y%m%dT%H%M%SZ).cmd"
```

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

- **SIGTERM only.** Never escalate to SIGKILL, and never reach for
  process-mass-kill tools (the obvious ones are forbidden by
  CLAUDE.md). On a stuck process, surface manual-recovery
  instructions and exit 1.
- **Never bypass identity check.** Both command-name AND cwd must
  match before `stop` will signal a PID. Same defense applies on
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
- **PYTHONPATH discipline.** `start` prepends
  `$MAIN_ROOT/skills/zskills-dashboard/scripts` to `PYTHONPATH` so
  `python3 -m zskills_monitor.server` resolves the package without an
  install step (per DA-5).
- **Verify after every state change.** `start` curls
  `/api/health`; `stop` polls `kill -0` then verifies the port is
  freed via `lsof`.
- **Tracking markers for state-changing modes only.** `start` and
  `stop` write `fulfilled.zskills-dashboard.<id>`; `status` does not.
- **Mirror via `scripts/mirror-skill.sh`** — never use a recursive
  remove on the mirror tree (hook will block).
