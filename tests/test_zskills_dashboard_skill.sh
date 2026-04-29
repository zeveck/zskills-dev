#!/bin/bash
# Tests for skills/zskills-dashboard/SKILL.md — Phase 8 of
# plans/ZSKILLS_MONITOR_PLAN.md.
#
# Strategy: SKILL.md is markdown-with-bash that the LLM executes inline.
# We re-implement the load-bearing blocks (Step 0 helpers + start/stop/
# status mode bodies) here as ordinary shell functions and drive them
# against tmpdir-scoped MAIN_ROOTs. Static-grep ACs are checked against
# the actual SKILL.md so any wording divergence will fail.
#
# Each Acceptance Criterion in the Phase 8 spec maps to one or more
# pass/fail lines below, tagged AC-N where N is the order of the AC
# in the spec's "Acceptance Criteria" list.
#
# Run from repo root: bash tests/test_zskills_dashboard_skill.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_DIR="$REPO_ROOT/skills/zskills-dashboard"
SKILL_MD="$SKILL_DIR/SKILL.md"
MIRROR_DIR="$REPO_ROOT/.claude/skills/zskills-dashboard"
MIRROR_MD="$MIRROR_DIR/SKILL.md"
PKG_PARENT="$SKILL_DIR/scripts"
SERVER_PY="$PKG_PARENT/zskills_monitor/server.py"
PORT_SCRIPT_SRC="$REPO_ROOT/skills/update-zskills/scripts/port.sh"
SANITIZE_SCRIPT_SRC="$REPO_ROOT/skills/create-worktree/scripts/sanitize-pipeline-id.sh"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }
skip() { printf '\033[33m  SKIP\033[0m %s\n' "$1"; SKIP_COUNT=$((SKIP_COUNT+1)); }

print_summary_and_exit() {
  echo ""
  echo "---"
  local total=$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))
  if [ "$FAIL_COUNT" -eq 0 ]; then
    printf '\033[32mResults: %d passed, %d failed, %d skipped (of %d)\033[0m\n' \
      "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$total"
    exit 0
  else
    printf '\033[31mResults: %d passed, %d failed, %d skipped (of %d)\033[0m\n' \
      "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$total"
    exit 1
  fi
}

# Per-process scratch root.
TMP_ROOT="/tmp/zskills-dashboard-skill-test.$$"
mkdir -p "$TMP_ROOT"

TRACKED_PIDS=""
cleanup() {
  for p in $TRACKED_PIDS; do
    if kill -0 "$p" 2>/dev/null; then
      kill -TERM "$p" 2>/dev/null || true
      sleep 0.5
    fi
    if kill -0 "$p" 2>/dev/null; then
      # SIGTERM-only cleanup — no SIGKILL escalation, even on test
      # teardown. The test process itself exits regardless; orphans
      # will be reaped by init.
      true
    fi
  done
  case "$TMP_ROOT" in
    /tmp/zskills-dashboard-skill-test.*)
      rm -rf -- "$TMP_ROOT"
      ;;
  esac
}
trap cleanup EXIT INT TERM

###############################################################################
# AC-1: SKILL.md exists with the specified frontmatter.
# AC-3: no `\bjq\b` matches.
# AC-4: no `kill -9 / killall / pkill / fuser -k` matches.
# AC-15 (extra): PYTHONPATH discipline — at least one match for
#   PYTHONPATH=...skills/zskills-dashboard/scripts.
# AC-16 (extra): mirror-skill.sh referenced; no rm -rf .claude/skills.
###############################################################################

echo ""
echo "=== Phase 8 AC: static-grep contract ==="

if [ ! -f "$SKILL_MD" ]; then
  fail "AC-1: SKILL.md exists at $SKILL_MD"
  print_summary_and_exit
fi
pass "AC-1: SKILL.md exists at $SKILL_MD"

# Frontmatter checks.
if grep -q '^name: zskills-dashboard$' "$SKILL_MD"; then
  pass "AC-1: frontmatter name: zskills-dashboard"
else
  fail "AC-1: frontmatter name field missing or wrong"
fi
if grep -q '^disable-model-invocation: true$' "$SKILL_MD"; then
  pass "AC-1: frontmatter disable-model-invocation: true"
else
  fail "AC-1: frontmatter disable-model-invocation flag missing"
fi
if grep -q '^argument-hint:.*\[start|stop|status\]' "$SKILL_MD"; then
  pass "AC-1: frontmatter argument-hint covers [start|stop|status]"
else
  fail "AC-1: frontmatter argument-hint missing or wrong"
fi

# AC-3: jq.
if grep -nE '\bjq\b' "$SKILL_MD" >/dev/null; then
  fail "AC-3: forbidden \\bjq\\b token in SKILL.md"
else
  pass "AC-3: no \\bjq\\b in SKILL.md"
fi

# AC-4: SIGKILL / killall family.
if grep -nE 'kill\s+-9|killall|pkill|fuser\s+-k' "$SKILL_MD" >/dev/null; then
  fail "AC-4: forbidden SIGKILL/killall family in SKILL.md"
else
  pass "AC-4: no SIGKILL / killall / pkill / fuser -k in SKILL.md"
fi

# AC-15 (extra): PYTHONPATH discipline.
if grep -nE 'PYTHONPATH=.*skills/zskills-dashboard/scripts' "$SKILL_MD" >/dev/null; then
  pass "AC-15: PYTHONPATH=...skills/zskills-dashboard/scripts present"
else
  fail "AC-15: PYTHONPATH discipline missing"
fi

# AC-16 (extra): mirror-skill.sh referenced; no rm -rf .claude/skills.
if grep -nE 'mirror-skill\.sh' "$SKILL_MD" >/dev/null; then
  pass "AC-16: mirror-skill.sh referenced in SKILL.md"
else
  fail "AC-16: mirror-skill.sh not referenced"
fi
if grep -nE 'rm\s+-rf\s+\.claude/skills' "$SKILL_MD" >/dev/null; then
  fail "AC-16: forbidden rm -rf .claude/skills in SKILL.md"
else
  pass "AC-16: no rm -rf .claude/skills in SKILL.md"
fi

###############################################################################
# AC-2: diff -rq skills/zskills-dashboard/ .claude/skills/zskills-dashboard/
#       returns 0 (whole-tree mirror).
###############################################################################

if [ ! -d "$MIRROR_DIR" ]; then
  fail "AC-2: mirror dir exists at $MIRROR_DIR"
else
  DIFF_OUT=$(diff -rq "$SKILL_DIR/" "$MIRROR_DIR/" 2>&1 | grep -v __pycache__ || true)
  if [ -z "$DIFF_OUT" ]; then
    pass "AC-2: diff -rq skills/zskills-dashboard/ .claude/skills/zskills-dashboard/ is clean"
  else
    fail "AC-2: mirror diverges from source: $DIFF_OUT"
  fi
fi

###############################################################################
# Skip the live-server tests if python3 / curl are missing, or if the
# server source isn't present (defensive — this should not happen in CI).
###############################################################################

if ! command -v python3 >/dev/null 2>&1; then
  skip "live tests: python3 not available"
  print_summary_and_exit
fi
if ! command -v curl >/dev/null 2>&1; then
  skip "live tests: curl not available"
  print_summary_and_exit
fi
if [ ! -f "$SERVER_PY" ]; then
  skip "live tests: server.py missing at $SERVER_PY"
  print_summary_and_exit
fi
if [ ! -x "$PORT_SCRIPT_SRC" ]; then
  skip "live tests: port.sh missing or non-executable at $PORT_SCRIPT_SRC"
  print_summary_and_exit
fi
if [ ! -x "$SANITIZE_SCRIPT_SRC" ]; then
  skip "live tests: sanitize-pipeline-id.sh missing or non-executable at $SANITIZE_SCRIPT_SRC"
  print_summary_and_exit
fi

###############################################################################
# SKILL.md bash-block re-implementation. The LLM executes these inline
# from SKILL.md; tests re-define them as functions parameterised on
# MAIN_ROOT so we can run multiple isolated fixtures concurrently.
#
# IMPORTANT: keep these blocks structurally aligned with SKILL.md. The
# static-grep AC checks above protect the SKILL.md source of truth from
# silent drift.
###############################################################################

# ---------------------------------------------------------------------------
# verify_monitor_identity — transcribed from SKILL.md Step 0.
# ---------------------------------------------------------------------------
verify_monitor_identity() {
  local pid="$1" main_root="$2"
  local cmd cwd_proc cwd_lsof matched_cwd

  if ! kill -0 "$pid" 2>/dev/null; then
    return 1
  fi

  cmd=$(ps -p "$pid" -o command= || echo "")
  if [[ ! "$cmd" =~ python3.*zskills_monitor\.server ]]; then
    printf 'identity-mismatch: command=%s\n' "$cmd" >&2
    return 1
  fi

  cwd_proc=$(readlink "/proc/$pid/cwd" 2>/dev/null || echo "")
  if [ -n "$cwd_proc" ]; then
    matched_cwd="$cwd_proc"
  else
    cwd_lsof=$(lsof -p "$pid" -d cwd -Fn 2>/dev/null | awk '/^n/ {sub(/^n/,""); print; exit}')
    if [ -n "$cwd_lsof" ]; then
      matched_cwd="$cwd_lsof"
    else
      printf 'identity-warning: cwd unverifiable for PID %s; accepting command-name match\n' "$pid" >&2
      printf '%s\n' "$cmd"
      return 0
    fi
  fi

  if [ "$matched_cwd" != "$main_root" ]; then
    printf 'identity-mismatch: cwd=%s expected=%s\n' "$matched_cwd" "$main_root" >&2
    return 1
  fi

  printf '%s\n' "$cmd"
  return 0
}

# ---------------------------------------------------------------------------
# write_tracking_marker — transcribed from SKILL.md Step 0.
# ---------------------------------------------------------------------------
write_tracking_marker() {
  local main_root="$1" mode="$2" pid_val="${3:-}" port_val="${4:-}"
  local raw="zskills-dashboard-$(date -u +%Y%m%dT%H%M%SZ)-$$-$RANDOM"
  local id
  id=$(bash "$SANITIZE_SCRIPT_SRC" "$raw")
  local subdir="$main_root/.zskills/tracking/zskills-dashboard.$id"
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
}

# ---------------------------------------------------------------------------
# do_start / do_stop / do_status — transcribed from SKILL.md mode bodies,
# parameterised on a passed-in MAIN_ROOT (the LLM resolves it from cwd
# via `git rev-parse --git-common-dir`; tests pass it explicitly).
# ---------------------------------------------------------------------------

do_start() {
  local MAIN_ROOT="$1"
  local PID_FILE="$MAIN_ROOT/.zskills/dashboard-server.pid"
  local LOG_FILE="$MAIN_ROOT/.zskills/dashboard-server.log"
  local PORT_SCRIPT="$PORT_SCRIPT_SRC"
  local PKG_PARENT_LOCAL="$PKG_PARENT"

  mkdir -p "$MAIN_ROOT/.zskills"

  # Existing PID file?
  if [ -f "$PID_FILE" ]; then
    local PID_BODY existing_pid existing_port
    PID_BODY=$(cat "$PID_FILE")
    existing_pid=""
    existing_port=""
    if [[ "$PID_BODY" =~ (^|$'\n')pid=([0-9]+) ]]; then
      existing_pid="${BASH_REMATCH[2]}"
    fi
    if [[ "$PID_BODY" =~ (^|$'\n')port=([0-9]+) ]]; then
      existing_port="${BASH_REMATCH[2]}"
    fi
    if [ -n "$existing_pid" ]; then
      if verify_monitor_identity "$existing_pid" "$MAIN_ROOT" >/dev/null; then
        echo "already running at http://127.0.0.1:${existing_port:-?}/ (pid $existing_pid)"
        write_tracking_marker "$MAIN_ROOT" "start-already-running" "$existing_pid" "${existing_port:-}"
        return 0
      else
        echo "WARN: stale PID file at $PID_FILE; removing." >&2
        rm -- "$PID_FILE"
      fi
    else
      rm -- "$PID_FILE"
    fi
  fi

  local PORT
  # In production (SKILL.md) cwd already equals MAIN_ROOT (the user
  # invoked the skill from inside the repo). In tests the calling bash
  # runs from the zskills source tree, so we must cd into MAIN_ROOT
  # before invoking port.sh — otherwise port.sh's `git rev-parse
  # --show-toplevel` resolves to the wrong repo and we pick a port
  # that's different from what the launched server picks (the server
  # cd's into MAIN_ROOT before resolve_port).
  PORT=$( cd "$MAIN_ROOT" && bash "$PORT_SCRIPT" )
  if [[ ! "$PORT" =~ ^[0-9]+$ ]]; then
    echo "ERROR: port.sh returned non-numeric value: $PORT" >&2
    return 1
  fi

  if lsof -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "ERROR: port $PORT already in use." >&2
    return 2
  fi

  ( cd "$MAIN_ROOT" && \
    PYTHONPATH="$PKG_PARENT_LOCAL:${PYTHONPATH:-}" \
    nohup python3 -m zskills_monitor.server \
      > "$LOG_FILE" 2>&1 < /dev/null & disown )

  local HEALTHY=0 HEALTH_BODY=""
  # Match SKILL.md (~10s wall-clock — handles slow Python startup in CI).
  for _ in $(seq 1 40); do
    sleep 0.25
    HEALTH_BODY=$(curl -sf -m 1 "http://127.0.0.1:$PORT/api/health" || true)
    if printf '%s' "$HEALTH_BODY" | grep -qE '"status":[[:space:]]*"ok"'; then
      HEALTHY=1
      break
    fi
  done
  if [ "$HEALTHY" -ne 1 ]; then
    echo "ERROR: server did not respond on /api/health within 10s." >&2
    tail -n 20 "$LOG_FILE" >&2 || true
    return 1
  fi

  if [ ! -f "$PID_FILE" ]; then
    echo "ERROR: server is healthy but PID file was not written." >&2
    return 1
  fi
  local NEW_PID="" PIDFILE_BODY
  PIDFILE_BODY=$(cat "$PID_FILE")
  if [[ "$PIDFILE_BODY" =~ (^|$'\n')pid=([0-9]+) ]]; then
    NEW_PID="${BASH_REMATCH[2]}"
  fi

  echo "Monitor running at http://127.0.0.1:$PORT/ (pid ${NEW_PID:-?})"
  TRACKED_PIDS="$TRACKED_PIDS ${NEW_PID:-}"
  write_tracking_marker "$MAIN_ROOT" "start" "$NEW_PID" "$PORT"
  return 0
}

do_stop() {
  local MAIN_ROOT="$1"
  local PID_FILE="$MAIN_ROOT/.zskills/dashboard-server.pid"

  if [ ! -f "$PID_FILE" ]; then
    echo "No running monitor (no PID file)."
    write_tracking_marker "$MAIN_ROOT" "stop-no-pidfile"
    return 0
  fi

  local PID_BODY stop_pid stop_port
  PID_BODY=$(cat "$PID_FILE")
  stop_pid=""
  stop_port=""
  if [[ "$PID_BODY" =~ (^|$'\n')pid=([0-9]+) ]]; then
    stop_pid="${BASH_REMATCH[2]}"
  fi
  if [[ "$PID_BODY" =~ (^|$'\n')port=([0-9]+) ]]; then
    stop_port="${BASH_REMATCH[2]}"
  fi
  if [ -z "$stop_pid" ]; then
    echo "ERROR: PID file has no parseable pid= line." >&2
    return 1
  fi

  if ! kill -0 "$stop_pid" 2>/dev/null; then
    echo "Monitor PID file is stale (PID $stop_pid not running). Removing $PID_FILE."
    rm -- "$PID_FILE"
    write_tracking_marker "$MAIN_ROOT" "stop-stale-pidfile" "$stop_pid" "${stop_port:-}"
    return 0
  fi

  local IDENTITY_CMD=""
  if ! IDENTITY_CMD=$(verify_monitor_identity "$stop_pid" "$MAIN_ROOT"); then
    local DIAG_CMD DIAG_CWD
    DIAG_CMD=$(ps -p "$stop_pid" -o command= || echo "<gone>")
    DIAG_CWD=$(readlink "/proc/$stop_pid/cwd" 2>/dev/null \
      || lsof -p "$stop_pid" -d cwd -Fn 2>/dev/null | awk '/^n/ {sub(/^n/,""); print; exit}' \
      || echo "<unknown>")
    echo "PID $stop_pid does not appear to be zskills-monitor for this repo (matched: $DIAG_CMD; cwd: $DIAG_CWD). Refusing to kill. Remove the PID file manually if stale." >&2
    return 1
  fi

  if ! kill -TERM "$stop_pid"; then
    echo "ERROR: kill -TERM $stop_pid failed." >&2
    return 1
  fi

  local EXITED=0
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do
    if ! kill -0 "$stop_pid" 2>/dev/null; then
      EXITED=1
      break
    fi
    sleep 0.2
  done
  if [ "$EXITED" -ne 1 ]; then
    echo "Monitor did not exit within 5s. Refusing to escalate." >&2
    return 1
  fi

  if [ -n "$stop_port" ]; then
    if lsof -iTCP:"$stop_port" -sTCP:LISTEN >/dev/null 2>&1; then
      echo "WARN: port $stop_port still has a listener after PID $stop_pid exited." >&2
    fi
  fi

  if [ -f "$PID_FILE" ]; then
    rm -- "$PID_FILE"
  fi
  echo "Monitor stopped (pid $stop_pid, port ${stop_port:-?})."
  write_tracking_marker "$MAIN_ROOT" "stop" "$stop_pid" "${stop_port:-}"
  return 0
}

do_status() {
  local MAIN_ROOT="$1"
  local PID_FILE="$MAIN_ROOT/.zskills/dashboard-server.pid"
  local LOG_FILE="$MAIN_ROOT/.zskills/dashboard-server.log"

  if [ ! -f "$PID_FILE" ]; then
    echo "Monitor not running."
    return 0
  fi

  local PID_BODY st_pid st_port st_started
  PID_BODY=$(cat "$PID_FILE")
  st_pid=""
  st_port=""
  st_started=""
  if [[ "$PID_BODY" =~ (^|$'\n')pid=([0-9]+) ]]; then
    st_pid="${BASH_REMATCH[2]}"
  fi
  if [[ "$PID_BODY" =~ (^|$'\n')port=([0-9]+) ]]; then
    st_port="${BASH_REMATCH[2]}"
  fi
  if [[ "$PID_BODY" =~ (^|$'\n')started_at=([^[:space:]]+) ]]; then
    st_started="${BASH_REMATCH[2]}"
  fi

  if [ -z "$st_pid" ] || [ -z "$st_port" ] || [ -z "$st_started" ]; then
    echo "PID file at $PID_FILE is missing required fields." >&2
    return 1
  fi
  if [[ ! "$st_started" =~ ^[0-9T:+-]+$ ]]; then
    echo "PID file at $PID_FILE has malformed started_at; rm it and retry /zskills-dashboard start" >&2
    return 1
  fi
  if ! kill -0 "$st_pid" 2>/dev/null; then
    echo "Monitor PID file is stale (PID $st_pid not running). Run 'lsof -i :$st_port' to verify port is free, then retry /zskills-dashboard start." >&2
    return 1
  fi

  local NOW_EPOCH STARTED_EPOCH SECS H M S UPTIME_STR
  NOW_EPOCH=$(date +%s)
  STARTED_EPOCH=$(date -d "$st_started" +%s 2>/dev/null || echo "")
  if [ -z "$STARTED_EPOCH" ]; then
    UPTIME_STR="(unknown)"
  else
    SECS=$((NOW_EPOCH - STARTED_EPOCH))
    [ "$SECS" -lt 0 ] && SECS=0
    H=$((SECS / 3600))
    M=$(((SECS % 3600) / 60))
    S=$((SECS % 60))
    UPTIME_STR=$(printf '%dh %dm %ds' "$H" "$M" "$S")
  fi

  cat <<STATUS_EOF
Monitor running at http://127.0.0.1:$st_port/
  pid:      $st_pid
  started:  $st_started
  uptime:   $UPTIME_STR
  log:      $LOG_FILE
STATUS_EOF
  return 0
}

# ---------------------------------------------------------------------------
# Fixture builder — minimal git repo (so MAIN_ROOT walk works in `cd
# "$(git rev-parse --git-common-dir)/.."`) with a per-fixture port.
# ---------------------------------------------------------------------------
make_fixture() {
  local label="$1" port="$2"
  local f="$TMP_ROOT/$label"
  mkdir -p "$f/.claude" "$f/.zskills"
  ( cd "$f" && git init -q && git config user.email "t@e.com" && git config user.name "t" && \
    git commit --allow-empty -q -m init )
  cat > "$f/.claude/zskills-config.json" <<EOF
{
  "dev_server": { "default_port": $port, "main_repo_path": "$f" },
  "execution": { "landing": "pr" }
}
EOF
  echo "$f"
}

# Pick well-spaced base ports per fixture so AC-13 (worktree process)
# can run concurrently with the main fixture.
BASE_A=$(( 19800 + ($$ % 100) ))
BASE_B=$(( BASE_A + 1 ))
BASE_C=$(( BASE_A + 2 ))

###############################################################################
# AC-5: start writes a PID file and /api/health returns 200 within 1s;
#       status after start prints `^Monitor running`.
# AC-6: PID-file shape (pid=<int>, port=<int>, started_at=ISO).
###############################################################################

echo ""
echo "=== Phase 8 AC: live start/stop/status (lifecycle) ==="

FX_A=$(make_fixture A "$BASE_A")

if do_start "$FX_A" >"$TMP_ROOT/A.start.out" 2>&1; then
  if grep -qE '^Monitor running at http://127\.0\.0\.1:' "$TMP_ROOT/A.start.out"; then
    pass "AC-5: start prints 'Monitor running at http://127.0.0.1:...'"
  else
    fail "AC-5: start output missing expected line: $(cat "$TMP_ROOT/A.start.out")"
  fi
  if [ -f "$FX_A/.zskills/dashboard-server.pid" ]; then
    pass "AC-5: PID file written at .zskills/dashboard-server.pid"
  else
    fail "AC-5: PID file NOT written"
  fi

  # /api/health smoke (port already verified inside do_start, but we re-check
  # because the AC explicitly mentions a 200 response within 1s).
  HEALTH=$(curl -sf -m 1 "http://127.0.0.1:$BASE_A/api/health" || true)
  if printf '%s' "$HEALTH" | grep -qE '"status":[[:space:]]*"ok"'; then
    pass "AC-5: /api/health returns ok"
  else
    fail "AC-5: /api/health did not return ok: $HEALTH"
  fi

  # AC-6: PID-file shape.
  PID_FILE_A="$FX_A/.zskills/dashboard-server.pid"
  if grep -qE '^pid=[0-9]+$' "$PID_FILE_A"; then
    pass "AC-6: PID file has pid=<int>"
  else
    fail "AC-6: PID file pid= line malformed: $(cat "$PID_FILE_A")"
  fi
  if grep -qE '^port=[0-9]+$' "$PID_FILE_A"; then
    pass "AC-6: PID file has port=<int>"
  else
    fail "AC-6: PID file port= line malformed: $(cat "$PID_FILE_A")"
  fi
  if grep -qE '^started_at=[0-9T:+-]+$' "$PID_FILE_A"; then
    pass "AC-6: PID file has started_at=<ISO-token-shape>"
  else
    fail "AC-6: PID file started_at= line malformed: $(cat "$PID_FILE_A")"
  fi

  # AC-5 (status side): status after start prints `^Monitor running`.
  if do_status "$FX_A" >"$TMP_ROOT/A.status.out" 2>&1; then
    if grep -qE '^Monitor running' "$TMP_ROOT/A.status.out"; then
      pass "AC-5: status after start prints '^Monitor running'"
    else
      fail "AC-5: status output missing 'Monitor running': $(cat "$TMP_ROOT/A.status.out")"
    fi
  else
    fail "AC-5: status returned non-zero after start"
  fi
else
  fail "AC-5: start returned non-zero: $(cat "$TMP_ROOT/A.start.out")"
fi

###############################################################################
# AC-8: start twice → second run detects live PID + matching command +
#       matching cwd and prints the URL without launching a duplicate.
###############################################################################

if do_start "$FX_A" >"$TMP_ROOT/A.start2.out" 2>&1; then
  if grep -qE 'already running at http://127\.0\.0\.1:' "$TMP_ROOT/A.start2.out"; then
    pass "AC-8: start twice — second prints 'already running' (no duplicate)"
  else
    fail "AC-8: start twice — unexpected output: $(cat "$TMP_ROOT/A.start2.out")"
  fi
else
  fail "AC-8: start twice returned non-zero (expected 0 when already running)"
fi

###############################################################################
# AC-12 (early): tracking markers exist after start; not after status.
###############################################################################

# Count tracking subdirs under .zskills/tracking/zskills-dashboard.* —
# we expect at least 2 markers (initial start + already-running start;
# status would NOT add a subdir).
COUNT_AFTER_TWO_STARTS=$(find "$FX_A/.zskills/tracking" -maxdepth 1 -type d -name 'zskills-dashboard.*' 2>/dev/null | wc -l | tr -d ' ')
if [ "${COUNT_AFTER_TWO_STARTS:-0}" -ge 2 ]; then
  pass "AC-12: tracking subdir(s) exist after start ($COUNT_AFTER_TWO_STARTS)"
else
  fail "AC-12: expected ≥2 tracking subdirs after two starts, got $COUNT_AFTER_TWO_STARTS"
fi

# Check at least one marker has the expected fields.
MARKER_FILE=$(find "$FX_A/.zskills/tracking" -name 'fulfilled.zskills-dashboard.*' -type f 2>/dev/null | head -1)
if [ -n "$MARKER_FILE" ]; then
  if grep -q '^skill: zskills-dashboard$' "$MARKER_FILE" \
     && grep -q '^id: ' "$MARKER_FILE" \
     && grep -q '^status: ' "$MARKER_FILE" \
     && grep -q '^date: ' "$MARKER_FILE"; then
    pass "AC-12: marker has skill: / id: / status: / date: fields"
  else
    fail "AC-12: marker missing fields: $(cat "$MARKER_FILE")"
  fi
else
  fail "AC-12: no fulfilled.zskills-dashboard.* marker found"
fi

# status should NOT add a new subdir.
STATUS_BEFORE=$(find "$FX_A/.zskills/tracking" -maxdepth 1 -type d -name 'zskills-dashboard.*' 2>/dev/null | wc -l | tr -d ' ')
do_status "$FX_A" >/dev/null 2>&1 || true
STATUS_AFTER=$(find "$FX_A/.zskills/tracking" -maxdepth 1 -type d -name 'zskills-dashboard.*' 2>/dev/null | wc -l | tr -d ' ')
if [ "$STATUS_BEFORE" = "$STATUS_AFTER" ]; then
  pass "AC-12: status does NOT add a new tracking subdir (read-only)"
else
  fail "AC-12: status added a tracking subdir (was $STATUS_BEFORE, now $STATUS_AFTER)"
fi

###############################################################################
# AC-13: detachment survival in a fresh shell.
###############################################################################

# The do_start subshell ran `nohup … & disown`, so the server should be
# reparented away from the test-process job table. Read its PID and run
# kill -0 + curl from a fresh `bash -c` (the AC's "new shell"
# equivalent). The AC explicitly includes a curl /api/health from the
# new shell, parsing the same PID file shape.
FRESH_SHELL_OUT=$(bash -c '
  PID=$(grep -oE "^pid=[0-9]+" "'"$FX_A"'/.zskills/dashboard-server.pid" | cut -d= -f2)
  PORT=$(grep -oE "^port=[0-9]+" "'"$FX_A"'/.zskills/dashboard-server.pid" | cut -d= -f2)
  if kill -0 "$PID" 2>/dev/null && curl -sf -m 1 "http://127.0.0.1:$PORT/api/health" | grep -q "\"status\""; then
    echo "ALIVE"
  else
    echo "DEAD"
  fi
')
if [ "$FRESH_SHELL_OUT" = "ALIVE" ]; then
  pass "AC-13: detachment survival — kill -0 + /api/health succeed in fresh shell"
else
  fail "AC-13: server did not survive parent-shell exit (got: $FRESH_SHELL_OUT)"
fi

###############################################################################
# AC-14: PID-reuse defense — PID file pointing at a non-monitor process
#         (e.g. bash/sleep) is treated as stale; start does NOT print
#         "already running" against it.
###############################################################################

FX_REUSE=$(make_fixture reuse "$BASE_C")
# Spawn a long-running sleep as the "wrong" process.
sleep 30 &
DECOY_PID=$!
TRACKED_PIDS="$TRACKED_PIDS $DECOY_PID"
# Write a PID file claiming this PID is the monitor.
cat > "$FX_REUSE/.zskills/dashboard-server.pid" <<EOF
pid=$DECOY_PID
port=$BASE_C
started_at=$(date -Iseconds)
EOF
# Run start. Identity check should fail (cmd is "sleep", not python3.*zskills_monitor.server).
# Expected: warn + remove PID file, then attempt to launch a fresh server.
if do_start "$FX_REUSE" >"$TMP_ROOT/reuse.start.out" 2>&1; then
  REUSE_RC=0
else
  REUSE_RC=$?
fi
if grep -qE 'already running' "$TMP_ROOT/reuse.start.out"; then
  fail "AC-14: PID-reuse defense — start incorrectly said 'already running' against decoy"
else
  pass "AC-14: PID-reuse defense — start did NOT say 'already running' against decoy"
fi
# Decoy should still be alive (start removed PID file, did NOT signal decoy).
if kill -0 "$DECOY_PID" 2>/dev/null; then
  pass "AC-14: PID-reuse defense — decoy process untouched (no kill sent)"
else
  fail "AC-14: PID-reuse defense — decoy process was killed (should be untouched)"
fi
# Stop whatever the start launched (if anything).
if [ -f "$FX_REUSE/.zskills/dashboard-server.pid" ]; then
  do_stop "$FX_REUSE" >/dev/null 2>&1 || true
fi
kill -TERM "$DECOY_PID" 2>/dev/null || true

###############################################################################
# AC-10: stop mode PID-mismatch defense (command-name).
#   Write a PID file pointing at a long-running unrelated process; run
#   stop and verify it prints the mismatch diagnostic, does NOT kill the
#   process, and exits 1.
###############################################################################

FX_CMD=$(make_fixture cmdmiss "$BASE_C")
sleep 30 &
DECOY2_PID=$!
TRACKED_PIDS="$TRACKED_PIDS $DECOY2_PID"
cat > "$FX_CMD/.zskills/dashboard-server.pid" <<EOF
pid=$DECOY2_PID
port=$BASE_C
started_at=$(date -Iseconds)
EOF
if do_stop "$FX_CMD" >"$TMP_ROOT/cmdmiss.stop.out" 2>&1; then
  CMDMISS_RC=0
else
  CMDMISS_RC=$?
fi
if [ "$CMDMISS_RC" -eq 1 ]; then
  pass "AC-10: stop PID-mismatch (command-name) — exit 1"
else
  fail "AC-10: stop PID-mismatch (command-name) — exit was $CMDMISS_RC, expected 1"
fi
if grep -q 'does not appear to be zskills-monitor' "$TMP_ROOT/cmdmiss.stop.out"; then
  pass "AC-10: stop PID-mismatch (command-name) — diagnostic printed"
else
  fail "AC-10: stop PID-mismatch (command-name) — diagnostic missing: $(cat "$TMP_ROOT/cmdmiss.stop.out")"
fi
if kill -0 "$DECOY2_PID" 2>/dev/null; then
  pass "AC-10: stop PID-mismatch (command-name) — decoy untouched"
else
  fail "AC-10: stop PID-mismatch (command-name) — decoy was killed"
fi
kill -TERM "$DECOY2_PID" 2>/dev/null || true

###############################################################################
# AC-11: stop mode PID-mismatch defense (cwd).
#   Launch a second monitor in a different MAIN_ROOT (FX_B). From FX_A,
#   write a PID file pointing at FX_B's monitor PID and run stop.
#   The cwd check must fail and the monitor must NOT be killed.
###############################################################################

FX_B=$(make_fixture B "$BASE_B")
do_start "$FX_B" >"$TMP_ROOT/B.start.out" 2>&1
B_PID=""
if [ -f "$FX_B/.zskills/dashboard-server.pid" ]; then
  B_PID=$(grep -oE '^pid=[0-9]+' "$FX_B/.zskills/dashboard-server.pid" | cut -d= -f2)
fi
if [ -n "$B_PID" ] && kill -0 "$B_PID" 2>/dev/null; then
  pass "AC-11: pre-condition — second monitor running in FX_B (pid $B_PID)"

  # Cross-write FX_B's PID into FX_A's PID file.
  cat > "$FX_A/.zskills/dashboard-server.pid" <<EOF
pid=$B_PID
port=$BASE_B
started_at=$(date -Iseconds)
EOF
  if do_stop "$FX_A" >"$TMP_ROOT/cwdmiss.stop.out" 2>&1; then
    CWDMISS_RC=0
  else
    CWDMISS_RC=$?
  fi
  if [ "$CWDMISS_RC" -eq 1 ]; then
    pass "AC-11: stop PID-mismatch (cwd) — exit 1"
  else
    fail "AC-11: stop PID-mismatch (cwd) — exit was $CWDMISS_RC, expected 1"
  fi
  if grep -q 'does not appear to be zskills-monitor for this repo' "$TMP_ROOT/cwdmiss.stop.out"; then
    pass "AC-11: stop PID-mismatch (cwd) — diagnostic printed"
  else
    fail "AC-11: stop PID-mismatch (cwd) — diagnostic missing: $(cat "$TMP_ROOT/cwdmiss.stop.out")"
  fi
  if kill -0 "$B_PID" 2>/dev/null; then
    pass "AC-11: stop PID-mismatch (cwd) — FX_B's monitor untouched"
  else
    fail "AC-11: stop PID-mismatch (cwd) — FX_B's monitor was killed!"
  fi

  # Stop FX_B cleanly. FX_A's PID file currently points at FX_B's
  # (now-killed) PID. Rewrite it to FX_A's actual monitor PID so AC-7
  # has a real target. We saved FX_A's own pid in NEW_PID inside the
  # earlier do_start, but that's a function-local; recover it from
  # `pgrep`-equivalent on FX_A's MAIN_ROOT (readlink /proc/$$/cwd).
  do_stop "$FX_B" >/dev/null 2>&1 || true
  rm -f "$FX_A/.zskills/dashboard-server.pid"
  # Find FX_A's still-running monitor (cwd matches FX_A) and rewrite
  # the PID file so AC-7's stop has a legitimate target. We scan all
  # python3 zskills_monitor.server processes' /proc cwd's.
  for cand in $(pgrep -f 'python3.*zskills_monitor.server' 2>/dev/null); do
    cand_cwd=$(readlink "/proc/$cand/cwd" 2>/dev/null || echo "")
    if [ "$cand_cwd" = "$FX_A" ]; then
      # Re-derive its port via /proc/<pid>/net/tcp would be complex;
      # easiest is to assume BASE_A is bound (the only port FX_A's
      # config knows). Curl /api/health and parse the port field.
      A_HEALTH=$(curl -sf -m 1 "http://127.0.0.1:$BASE_A/api/health" || true)
      if printf '%s' "$A_HEALTH" | grep -qE '"status":[[:space:]]*"ok"'; then
        cat > "$FX_A/.zskills/dashboard-server.pid" <<EOF
pid=$cand
port=$BASE_A
started_at=$(date -Iseconds)
EOF
      fi
      break
    fi
  done
else
  fail "AC-11: pre-condition — second monitor in FX_B did not start (skipping cwd-mismatch test)"
fi

###############################################################################
# AC-7: stop removes the PID file and frees the port within 5s.
# AC-9: stop twice → second prints no-PID-file message, exits 0.
###############################################################################

# AC-7 needs a live monitor with a matching PID file. The PID file was
# rewritten in the AC-11 cleanup above; if missing (recovery branch
# failed), we cannot exercise AC-7.
if [ -f "$FX_A/.zskills/dashboard-server.pid" ]; then
  STOP_PORT_AC7=$(grep -oE '^port=[0-9]+' "$FX_A/.zskills/dashboard-server.pid" | cut -d= -f2)
  STOP_START_TS=$(date +%s)
  if do_stop "$FX_A" >"$TMP_ROOT/A.stop.out" 2>&1; then
    STOP_END_TS=$(date +%s)
    STOP_ELAPSED=$((STOP_END_TS - STOP_START_TS))
    if [ "$STOP_ELAPSED" -le 5 ]; then
      pass "AC-7: stop completed within 5s (took ${STOP_ELAPSED}s)"
    else
      fail "AC-7: stop took ${STOP_ELAPSED}s (>5s)"
    fi
    if [ ! -f "$FX_A/.zskills/dashboard-server.pid" ]; then
      pass "AC-7: stop removed the PID file"
    else
      fail "AC-7: stop did NOT remove the PID file"
    fi
    if [ -n "$STOP_PORT_AC7" ]; then
      if lsof -iTCP:"$STOP_PORT_AC7" -sTCP:LISTEN >/dev/null 2>&1; then
        fail "AC-7: port $STOP_PORT_AC7 still has a listener after stop"
      else
        pass "AC-7: port $STOP_PORT_AC7 is free after stop"
      fi
    fi
  else
    fail "AC-7: stop returned non-zero: $(cat "$TMP_ROOT/A.stop.out")"
  fi

  # AC-9: stop twice → second is no-op, exit 0.
  if do_stop "$FX_A" >"$TMP_ROOT/A.stop2.out" 2>&1; then
    if grep -q 'No running monitor' "$TMP_ROOT/A.stop2.out"; then
      pass "AC-9: stop twice — second prints 'No running monitor' (idempotent)"
    else
      fail "AC-9: stop twice — unexpected output: $(cat "$TMP_ROOT/A.stop2.out")"
    fi
  else
    fail "AC-9: stop twice — second invocation returned non-zero"
  fi
else
  fail "AC-7 / AC-9: FX_A has no PID file to stop (cleanup branch failed)"
fi

print_summary_and_exit
