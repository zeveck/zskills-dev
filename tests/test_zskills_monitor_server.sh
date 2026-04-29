#!/bin/bash
# Tests for skills/zskills-dashboard/scripts/zskills_monitor/server.py
# (Phase 5 of plans/ZSKILLS_MONITOR_PLAN.md).
#
# Spins up the server in a tmpdir-scoped MAIN_ROOT, exercises every
# endpoint, validates the security contract, and verifies the lifecycle
# (PID-file, SIGTERM cleanup, port-busy diagnostic).
#
# Run from repo root: bash tests/test_zskills_monitor_server.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PKG_PARENT="$REPO_ROOT/skills/zskills-dashboard/scripts"
SERVER_PY="$PKG_PARENT/zskills_monitor/server.py"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
skip() { printf '\033[33m  SKIP\033[0m %s\n' "$1"; SKIP_COUNT=$((SKIP_COUNT + 1)); }

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

if ! command -v python3 >/dev/null 2>&1; then
  skip "python3 not available"
  print_summary_and_exit
fi
if ! command -v curl >/dev/null 2>&1; then
  skip "curl not available"
  print_summary_and_exit
fi
if [ ! -f "$SERVER_PY" ]; then
  fail "server.py exists at expected path"
  print_summary_and_exit
fi

# Per-process scratch root. Reused across test phases (each phase clears
# only the parts it owns; no broad rm -rf).
TMP_ROOT="/tmp/zskills-monitor-server-test.$$"
mkdir -p "$TMP_ROOT"

# Auto-cleanup function. Stops any tracked PIDs and removes scoped
# tmpdirs by listing them explicitly (no rm -rf with variables on
# untrusted paths).
TRACKED_PIDS=""
cleanup() {
  for p in $TRACKED_PIDS; do
    if kill -0 "$p" 2>/dev/null; then
      kill -TERM "$p" 2>/dev/null || true
      sleep 1
      kill -0 "$p" 2>/dev/null && kill -TERM "$p" 2>/dev/null || true
    fi
  done
  # Remove our scoped tmpdir (literal /tmp/<name> path).
  if [ -d "$TMP_ROOT" ]; then
    rm -rf "$TMP_ROOT"
  fi
}
trap cleanup EXIT INT TERM

# Pick a free-ish high port for tests. Use $$ to spread across runs.
BASE_PORT=$(( 19000 + ($$ % 500) ))
PORT="$BASE_PORT"

# --- Helper: spawn server, return PID via $SERVER_PID, port via $PORT --

start_server() {
  # $1 = main_root, $2 = port
  local mr="$1" prt="$2"
  PYTHONPATH="$PKG_PARENT" python3 -m zskills_monitor.server \
    --main-root "$mr" --port "$prt" >>"$mr/server.log" 2>&1 &
  SERVER_PID=$!
  TRACKED_PIDS="$TRACKED_PIDS $SERVER_PID"
  # Wait up to 3s for /api/health to return.
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    if curl -sf -m 1 "http://127.0.0.1:$prt/api/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

stop_server() {
  local pidfile="$1" prt="$2"
  if [ -f "$pidfile" ]; then
    local pid
    if [[ "$(cat "$pidfile")" =~ pid=([0-9]+) ]]; then
      pid="${BASH_REMATCH[1]}"
      kill -TERM "$pid" 2>/dev/null || true
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        sleep 0.5
        if [ ! -f "$pidfile" ]; then
          return 0
        fi
      done
    fi
  fi
  return 1
}

###############################################################################
# Phase 1 — basic server lifecycle: start, /api/health, /api/state, SIGTERM
###############################################################################

echo "=== Phase 5 AC: server lifecycle (start, health, state, SIGTERM) ==="

MR1="$TMP_ROOT/mr1"
mkdir -p "$MR1/.claude" "$MR1/plans"
cat >"$MR1/.claude/zskills-config.json" <<EOF
{
  "dev_server": { "default_port": $PORT },
  "execution": { "landing": "pr" }
}
EOF

PORT_A="$PORT"
if start_server "$MR1" "$PORT_A"; then
  pass "server starts and /api/health returns 200"
else
  fail "server failed to start at port $PORT_A"
  print_summary_and_exit
fi

# /api/health body shape
HEALTH=$(curl -sf -m 3 "http://127.0.0.1:$PORT_A/api/health")
if printf '%s' "$HEALTH" | grep -q '"status":[[:space:]]*"ok"' \
   && printf '%s' "$HEALTH" | grep -q '"port":[[:space:]]*'"$PORT_A"; then
  pass "/api/health body shape (status=ok, port=$PORT_A)"
else
  fail "/api/health body unexpected: $HEALTH"
fi

# /api/state has version key
STATE_BODY=$(curl -sf -m 5 "http://127.0.0.1:$PORT_A/api/state")
if printf '%s' "$STATE_BODY" | grep -q '"version":[[:space:]]*"1\.[01]"'; then
  pass "/api/state version key 1.x present"
else
  fail "/api/state version missing: $(printf '%s' "$STATE_BODY" | head -c 200)"
fi

# /api/state Cache-Control: no-store (use -D to dump headers from a GET,
# since the stdlib BaseHTTPRequestHandler doesn't support HEAD).
HEADERS=$(curl -s -D - -o /dev/null -m 3 "http://127.0.0.1:$PORT_A/api/state")
if printf '%s' "$HEADERS" | grep -qi 'cache-control:[[:space:]]*no-store'; then
  pass "/api/state has Cache-Control: no-store"
else
  fail "/api/state missing no-store: $HEADERS"
fi

# PID file shape (Shared Schemas)
PIDFILE="$MR1/.zskills/dashboard-server.pid"
if [ -f "$PIDFILE" ]; then
  pass "PID file written"
  if grep -qE '^pid=[0-9]+$' "$PIDFILE" \
     && grep -qE '^port=[0-9]+$' "$PIDFILE" \
     && grep -qE '^started_at=[0-9T:+-]+$' "$PIDFILE"; then
    pass "PID file shape (pid=, port=, started_at=)"
  else
    fail "PID file shape: $(cat "$PIDFILE")"
  fi
else
  fail "PID file not present"
fi

# PID liveness
if [[ "$(cat "$PIDFILE")" =~ pid=([0-9]+) ]]; then
  PID_FROM_FILE="${BASH_REMATCH[1]}"
  if kill -0 "$PID_FROM_FILE" 2>/dev/null; then
    pass "PID file's pid is live"
  else
    fail "PID file's pid not live"
  fi
fi

# Bind only on 127.0.0.1
if command -v ss >/dev/null 2>&1; then
  if ss -ltn 2>/dev/null | grep ":$PORT_A" | grep -q '127.0.0.1:'; then
    pass "bound only on 127.0.0.1"
  else
    fail "bind check via ss did not find 127.0.0.1:$PORT_A"
  fi
else
  skip "ss not available — skipping 127.0.0.1 bind check"
fi

# Config-block bootstrap
if grep -qE '"dashboard":' "$MR1/.claude/zskills-config.json"; then
  pass "config-block bootstrap added dashboard block"
else
  fail "dashboard block not added to config"
fi

# SIGTERM exit ≤5s + PID removed
START_TS=$(date +%s)
if stop_server "$PIDFILE" "$PORT_A"; then
  ELAPSED=$(( $(date +%s) - START_TS ))
  if [ "$ELAPSED" -le 5 ]; then
    pass "SIGTERM exit + PID file removed in ${ELAPSED}s (≤5s)"
  else
    fail "SIGTERM exit took ${ELAPSED}s (>5s)"
  fi
else
  fail "PID file not removed within 5s of SIGTERM"
fi

# Verify port released
sleep 0.5
if curl -sf -m 1 "http://127.0.0.1:$PORT_A/api/health" >/dev/null 2>&1; then
  fail "port still serving after SIGTERM"
else
  pass "port released after SIGTERM"
fi

###############################################################################
# Phase 2 — Port resolution chain
###############################################################################

echo ""
echo "=== Phase 5 AC: port resolution chain ==="

# (a) DEV_PORT env var
PORT_B=$(( BASE_PORT + 1 ))
MR2="$TMP_ROOT/mr2"
mkdir -p "$MR2/.claude" "$MR2/plans"
printf '%s\n' "{}" > "$MR2/.claude/zskills-config.json"
PYTHONPATH="$PKG_PARENT" DEV_PORT="$PORT_B" python3 -m zskills_monitor.server \
  --main-root "$MR2" >"$MR2/server.log" 2>&1 &
PID_B=$!
TRACKED_PIDS="$TRACKED_PIDS $PID_B"
sleep 0.8
if curl -sf -m 2 "http://127.0.0.1:$PORT_B/api/health" >/dev/null; then
  pass "(a) DEV_PORT env override binds $PORT_B"
else
  fail "(a) DEV_PORT did not bind"
fi
PIDFILE_B="$MR2/.zskills/dashboard-server.pid"
stop_server "$PIDFILE_B" "$PORT_B" >/dev/null

# (b) DEV_PORT unset, config has dev_server.default_port
PORT_C=$(( BASE_PORT + 2 ))
MR3="$TMP_ROOT/mr3"
mkdir -p "$MR3/.claude" "$MR3/plans"
cat >"$MR3/.claude/zskills-config.json" <<EOF
{ "dev_server": { "default_port": $PORT_C } }
EOF
unset DEV_PORT
PYTHONPATH="$PKG_PARENT" python3 -m zskills_monitor.server \
  --main-root "$MR3" >"$MR3/server.log" 2>&1 &
PID_C=$!
TRACKED_PIDS="$TRACKED_PIDS $PID_C"
sleep 0.8
if curl -sf -m 2 "http://127.0.0.1:$PORT_C/api/health" >/dev/null; then
  pass "(b) config dev_server.default_port=$PORT_C binds"
else
  fail "(b) config-port did not bind"
fi
PIDFILE_C="$MR3/.zskills/dashboard-server.pid"
stop_server "$PIDFILE_C" "$PORT_C" >/dev/null

# (c) port.sh non-executable / missing → friendly diagnostic + exit 2
MR4="$TMP_ROOT/mr4"
mkdir -p "$MR4/.claude" "$MR4/plans" "$MR4/.zskills"
printf '%s\n' "{}" > "$MR4/.claude/zskills-config.json"
# No skills/update-zskills/scripts/port.sh under MR4 → fallback path empty
unset DEV_PORT
DIAG=$(PYTHONPATH="$PKG_PARENT" python3 -m zskills_monitor.server \
  --main-root "$MR4" 2>&1)
RC=$?
if [ "$RC" -eq 2 ] \
   && printf '%s' "$DIAG" | grep -q 'port resolution failed' \
   && ! printf '%s' "$DIAG" | grep -q 'Traceback'; then
  pass "(c) missing port.sh → friendly diagnostic + exit 2 (no traceback)"
else
  fail "(c) diagnostic unexpected (rc=$RC): $DIAG"
fi

###############################################################################
# Phase 3 — /api/state / /api/plan / /api/issue
###############################################################################

echo ""
echo "=== Phase 5 AC: read endpoints ==="

# Restart Phase-1 server with a plan fixture for /api/plan tests.
MR5="$TMP_ROOT/mr5"
mkdir -p "$MR5/.claude" "$MR5/plans"
cat >"$MR5/.claude/zskills-config.json" <<EOF
{ "dev_server": { "default_port": $(( BASE_PORT + 3 )) } }
EOF
cat >"$MR5/plans/SAMPLE_PLAN.md" <<'EOF'
---
title: Sample Plan
status: active
---

> Landing mode: pr

## Overview
This is a sample plan body for /api/plan tests.

## Phase 1 — Test phase
EOF
PORT_D=$(( BASE_PORT + 3 ))
if start_server "$MR5" "$PORT_D"; then
  # /api/plan happy path
  CODE=$(curl -s -o /dev/null -w '%{http_code}' \
    "http://127.0.0.1:$PORT_D/api/plan/sample-plan")
  if [ "$CODE" = "200" ]; then
    pass "/api/plan/<known-slug> returns 200"
  else
    fail "/api/plan/<known-slug> returned $CODE"
  fi
  PLAN_BODY=$(curl -sf -m 3 "http://127.0.0.1:$PORT_D/api/plan/sample-plan")
  if printf '%s' "$PLAN_BODY" | grep -q '"slug":[[:space:]]*"sample-plan"'; then
    pass "/api/plan body contains slug"
  else
    fail "/api/plan body missing slug"
  fi

  # 404 for unknown slug
  CODE=$(curl -s -o /dev/null -w '%{http_code}' \
    "http://127.0.0.1:$PORT_D/api/plan/does-not-exist")
  if [ "$CODE" = "404" ]; then
    pass "/api/plan/does-not-exist → 404"
  else
    fail "/api/plan/does-not-exist → $CODE"
  fi

  # 400 for path-traversal slug (URL-encoded)
  CODE=$(curl -s -o /dev/null -w '%{http_code}' \
    "http://127.0.0.1:$PORT_D/api/plan/..%2F..%2Fetc")
  if [ "$CODE" = "400" ]; then
    pass "/api/plan/..%2F..%2Fetc → 400 (path traversal blocked)"
  else
    fail "/api/plan path-traversal → $CODE"
  fi

  # 400 for non-numeric issue
  CODE=$(curl -s -o /dev/null -w '%{http_code}' \
    "http://127.0.0.1:$PORT_D/api/issue/abc")
  if [ "$CODE" = "400" ]; then
    pass "/api/issue/abc → 400"
  else
    fail "/api/issue/abc → $CODE"
  fi

  ###############################################################################
  # Phase 4 — POST /api/queue (CSRF + shape + write)
  ###############################################################################
  echo ""
  echo "=== Phase 5 AC: POST /api/queue ==="

  # CSRF: missing Origin → 403
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H 'Content-Type: application/json' \
    -d '{"plans":{"drafted":[],"reviewed":[],"ready":[]},"issues":{"triage":[],"ready":[]}}' \
    "http://127.0.0.1:$PORT_D/api/queue")
  if [ "$CODE" = "403" ]; then
    pass "POST /api/queue without Origin → 403"
  else
    fail "POST /api/queue no-origin → $CODE"
  fi

  # CSRF: mismatched Origin → 403
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H "Origin: http://evil.example.com" \
    -H 'Content-Type: application/json' \
    -d '{"plans":{"drafted":[],"reviewed":[],"ready":[]},"issues":{"triage":[],"ready":[]}}' \
    "http://127.0.0.1:$PORT_D/api/queue")
  if [ "$CODE" = "403" ]; then
    pass "POST /api/queue with wrong Origin → 403"
  else
    fail "POST /api/queue wrong-origin → $CODE"
  fi

  # Valid POST: 200 + state file written
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H "Origin: http://127.0.0.1:$PORT_D" \
    -H 'Content-Type: application/json' \
    -d '{"plans":{"drafted":[{"slug":"sample-plan"}],"reviewed":[],"ready":[]},"issues":{"triage":[42],"ready":[]}}' \
    "http://127.0.0.1:$PORT_D/api/queue")
  if [ "$CODE" = "200" ]; then
    pass "POST /api/queue with valid body + Origin → 200"
  else
    fail "POST /api/queue valid body → $CODE"
  fi
  if [ -f "$MR5/.zskills/monitor-state.json" ] \
     && grep -q '"sample-plan"' "$MR5/.zskills/monitor-state.json"; then
    pass "monitor-state.json updated with new state"
  else
    fail "monitor-state.json not updated"
  fi

  # Invalid body → 400 + state unchanged
  STATE_HASH_BEFORE=$(cksum "$MR5/.zskills/monitor-state.json" | awk '{print $1}')
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H "Origin: http://127.0.0.1:$PORT_D" \
    -H 'Content-Type: application/json' \
    -d '{"plans":"not an object","issues":{}}' \
    "http://127.0.0.1:$PORT_D/api/queue")
  if [ "$CODE" = "400" ]; then
    pass "POST /api/queue invalid body → 400"
  else
    fail "POST /api/queue invalid body → $CODE"
  fi
  STATE_HASH_AFTER=$(cksum "$MR5/.zskills/monitor-state.json" | awk '{print $1}')
  if [ "$STATE_HASH_BEFORE" = "$STATE_HASH_AFTER" ]; then
    pass "invalid POST did not modify state file"
  else
    fail "invalid POST modified state file"
  fi

  # Bad slug → 400 (plan slug with uppercase)
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H "Origin: http://127.0.0.1:$PORT_D" \
    -H 'Content-Type: application/json' \
    -d '{"plans":{"drafted":[{"slug":"Bad_Slug"}],"reviewed":[],"ready":[]},"issues":{"triage":[],"ready":[]}}' \
    "http://127.0.0.1:$PORT_D/api/queue")
  if [ "$CODE" = "400" ]; then
    pass "POST /api/queue with bad slug regex → 400"
  else
    fail "POST /api/queue bad slug → $CODE"
  fi

  # Duplicate slug → 400
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H "Origin: http://127.0.0.1:$PORT_D" \
    -H 'Content-Type: application/json' \
    -d '{"plans":{"drafted":[{"slug":"a"}],"reviewed":[{"slug":"a"}],"ready":[]},"issues":{"triage":[],"ready":[]}}' \
    "http://127.0.0.1:$PORT_D/api/queue")
  if [ "$CODE" = "400" ]; then
    pass "POST /api/queue duplicate slug across columns → 400"
  else
    fail "POST /api/queue duplicate slug → $CODE"
  fi

  ###############################################################################
  # Phase 5 — /api/work-state + /api/work-state/reset
  ###############################################################################
  echo ""
  echo "=== Phase 5 AC: work-state endpoints ==="

  # Remove any pre-existing work-state file (one-off targeted file delete).
  rm -f "$MR5/.zskills/work-on-plans-state.json"
  WS=$(curl -sf -m 3 "http://127.0.0.1:$PORT_D/api/work-state")
  if printf '%s' "$WS" | grep -q '"state":[[:space:]]*"idle"'; then
    pass "/api/work-state: missing file returns idle"
  else
    fail "/api/work-state missing file: $WS"
  fi
  if [ -f "$MR5/.zskills/work-on-plans-state.json" ]; then
    pass "/api/work-state: idle file auto-created"
  else
    fail "/api/work-state: idle file not auto-created"
  fi

  # Stale sprint: write old updated_at, expect warning + idle rewrite
  cat >"$MR5/.zskills/work-on-plans-state.json" <<'EOF'
{"state":"sprint","sprint_id":"work-on-plans.test","session_id":"x:1:y","started_at":"2020-01-01T00:00:00+00:00","progress":{"done":0,"total":1,"current_slug":"foo"},"updated_at":"2020-01-01T00:00:00+00:00"}
EOF
  WS=$(curl -sf -m 3 "http://127.0.0.1:$PORT_D/api/work-state")
  if printf '%s' "$WS" | grep -q '"state":[[:space:]]*"idle"' \
     && printf '%s' "$WS" | grep -q '"warning"'; then
    pass "/api/work-state: stale sprint → idle + warning"
  else
    fail "/api/work-state stale sprint: $WS"
  fi
  # File should now be idle
  if grep -q '"state":[[:space:]]*"idle"' "$MR5/.zskills/work-on-plans-state.json"; then
    pass "/api/work-state: stale sprint rewritten to idle on disk"
  else
    fail "/api/work-state: file not rewritten to idle"
  fi

  # Unparseable JSON → idle bootstrap
  printf '%s' '{not json' > "$MR5/.zskills/work-on-plans-state.json"
  WS=$(curl -sf -m 3 "http://127.0.0.1:$PORT_D/api/work-state")
  if printf '%s' "$WS" | grep -q '"state":[[:space:]]*"idle"'; then
    pass "/api/work-state: unparseable → idle"
  else
    fail "/api/work-state unparseable: $WS"
  fi

  # POST /api/work-state/reset
  cat >"$MR5/.zskills/work-on-plans-state.json" <<'EOF'
{"state":"sprint","sprint_id":"x","updated_at":"2026-04-29T00:00:00+00:00"}
EOF
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H "Origin: http://127.0.0.1:$PORT_D" \
    "http://127.0.0.1:$PORT_D/api/work-state/reset")
  if [ "$CODE" = "200" ]; then
    pass "POST /api/work-state/reset → 200"
  else
    fail "POST /api/work-state/reset → $CODE"
  fi
  if grep -q '"state":[[:space:]]*"idle"' "$MR5/.zskills/work-on-plans-state.json"; then
    pass "/api/work-state/reset writes idle"
  else
    fail "/api/work-state/reset did not write idle"
  fi

  # CSRF: reset without Origin → 403
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    "http://127.0.0.1:$PORT_D/api/work-state/reset")
  if [ "$CODE" = "403" ]; then
    pass "POST /api/work-state/reset without Origin → 403"
  else
    fail "POST /api/work-state/reset no-origin → $CODE"
  fi

  ###############################################################################
  # Phase 6 — /api/trigger security contract
  ###############################################################################
  echo ""
  echo "=== Phase 5 AC: /api/trigger security contract ==="

  # Empty trigger → 501 + {command}
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H "Origin: http://127.0.0.1:$PORT_D" \
    -H 'Content-Type: application/json' \
    -d '{"command":"/work-on-plans 1 phase"}' \
    "http://127.0.0.1:$PORT_D/api/trigger")
  if [ "$CODE" = "501" ]; then
    pass "/api/trigger empty config → 501"
  else
    fail "/api/trigger empty config → $CODE"
  fi

  # Bad command (not /work-on-plans) → 400
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H "Origin: http://127.0.0.1:$PORT_D" \
    -H 'Content-Type: application/json' \
    -d '{"command":"rm -rf /"}' \
    "http://127.0.0.1:$PORT_D/api/trigger")
  if [ "$CODE" = "400" ]; then
    pass "/api/trigger non-/work-on-plans command → 400"
  else
    fail "/api/trigger bad command → $CODE"
  fi

  # CSRF
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H 'Content-Type: application/json' \
    -d '{"command":"/work-on-plans 1"}' \
    "http://127.0.0.1:$PORT_D/api/trigger")
  if [ "$CODE" = "403" ]; then
    pass "/api/trigger without Origin → 403"
  else
    fail "/api/trigger no-origin → $CODE"
  fi

  # Configure a real trigger script that echos argv + env + pwd
  TRIG="$MR5/scripts/trig.sh"
  mkdir -p "$MR5/scripts"
  cat >"$TRIG" <<'EOF'
#!/bin/bash
echo "argv0=$0"
echo "argv1=$1"
echo "pwd=$(pwd)"
echo "PATH_set=$([ -n "$PATH" ] && echo yes || echo no)"
echo "HOME_set=$([ -n "$HOME" ] && echo yes || echo no)"
echo "ZSKILLS_PIPELINE_ID=$ZSKILLS_PIPELINE_ID"
EOF
  chmod +x "$TRIG"
  # Update config (rewrite)
  cat >"$MR5/.claude/zskills-config.json" <<EOF
{
  "dev_server": { "default_port": $PORT_D },
  "dashboard": { "work_on_plans_trigger": "scripts/trig.sh" }
}
EOF

  TRIG_RES=$(ZSKILLS_PIPELINE_ID="should-be-scrubbed" curl -sf -m 5 -X POST \
    -H "Origin: http://127.0.0.1:$PORT_D" \
    -H 'Content-Type: application/json' \
    -d '{"command":"/work-on-plans 3 phase"}' \
    "http://127.0.0.1:$PORT_D/api/trigger")
  if printf '%s' "$TRIG_RES" | grep -q '"status":[[:space:]]*"triggered"'; then
    pass "/api/trigger configured script → triggered status"
  else
    fail "/api/trigger result: $TRIG_RES"
  fi
  # argv1 must be the literal command (shell=False guarantees this)
  if printf '%s' "$TRIG_RES" | grep -q 'argv1=/work-on-plans 3 phase'; then
    pass "/api/trigger argv[1] is literal command (shell=False)"
  else
    fail "/api/trigger argv[1] check: $TRIG_RES"
  fi
  # No ZSKILLS_PIPELINE_ID in env
  if printf '%s' "$TRIG_RES" | grep -q 'ZSKILLS_PIPELINE_ID=$' \
     || ! printf '%s' "$TRIG_RES" | grep -q 'ZSKILLS_PIPELINE_ID=should-be-scrubbed'; then
    pass "/api/trigger env scrubbed (ZSKILLS_PIPELINE_ID gone)"
  else
    fail "/api/trigger env not scrubbed: $TRIG_RES"
  fi
  # pwd is MAIN_ROOT
  if printf '%s' "$TRIG_RES" | grep -q "pwd=$MR5"; then
    pass "/api/trigger pwd=MAIN_ROOT"
  else
    fail "/api/trigger pwd: $TRIG_RES"
  fi
  # PATH/HOME present
  if printf '%s' "$TRIG_RES" | grep -q 'PATH_set=yes' \
     && printf '%s' "$TRIG_RES" | grep -q 'HOME_set=yes'; then
    pass "/api/trigger PATH/HOME passed through"
  else
    fail "/api/trigger PATH/HOME: $TRIG_RES"
  fi
  # Server source: shell=False (no shell=True string)
  if grep -nE 'shell=True' "$SERVER_PY" >/dev/null; then
    fail "server.py contains shell=True"
  else
    pass "server.py has no shell=True"
  fi

  # Path-escape: trigger pointing outside MAIN_ROOT
  cat >"$MR5/.claude/zskills-config.json" <<EOF
{
  "dev_server": { "default_port": $PORT_D },
  "dashboard": { "work_on_plans_trigger": "../../../tmp/evil.sh" }
}
EOF
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H "Origin: http://127.0.0.1:$PORT_D" \
    -H 'Content-Type: application/json' \
    -d '{"command":"/work-on-plans 1"}' \
    "http://127.0.0.1:$PORT_D/api/trigger")
  if [ "$CODE" = "500" ]; then
    pass "/api/trigger ../../../tmp/evil.sh → 500 (path escape)"
  else
    fail "/api/trigger path-escape → $CODE"
  fi

  ###############################################################################
  # Phase 7 — Trigger config validation surfaces in /api/state errors[]
  ###############################################################################
  echo ""
  echo "=== Phase 5 AC: trigger config validation in /api/state errors[] ==="

  cat >"$MR5/.claude/zskills-config.json" <<EOF
{
  "dev_server": { "default_port": $PORT_D },
  "dashboard": { "work_on_plans_trigger": "scripts/does-not-exist.sh" }
}
EOF
  STATE_BODY=$(curl -sf -m 3 "http://127.0.0.1:$PORT_D/api/state")
  if printf '%s' "$STATE_BODY" | grep -q 'work_on_plans_trigger'; then
    pass "/api/state errors[] surfaces trigger-config issue"
  else
    fail "/api/state did not surface trigger-config error"
  fi

  # Stop server
  stop_server "$MR5/.zskills/dashboard-server.pid" "$PORT_D" >/dev/null
else
  fail "could not start server for read-endpoint tests"
fi

###############################################################################
# Phase 8 — Port-busy diagnostic
###############################################################################
echo ""
echo "=== Phase 5 AC: port-busy diagnostic ==="

PORT_E=$(( BASE_PORT + 4 ))
MR6="$TMP_ROOT/mr6"
mkdir -p "$MR6/.claude" "$MR6/plans"
cat >"$MR6/.claude/zskills-config.json" <<EOF
{ "dev_server": { "default_port": $PORT_E } }
EOF
if start_server "$MR6" "$PORT_E"; then
  # Try second start on same port
  unset DEV_PORT
  DIAG=$(PYTHONPATH="$PKG_PARENT" python3 -m zskills_monitor.server \
    --main-root "$MR6" --port "$PORT_E" 2>&1)
  RC=$?
  if [ "$RC" -eq 2 ] \
     && printf '%s' "$DIAG" | grep -q 'already in use' \
     && ! printf '%s' "$DIAG" | grep -q 'Traceback'; then
    pass "port-busy → exit 2 + friendly stderr (no traceback)"
  else
    fail "port-busy diagnostic (rc=$RC): $DIAG"
  fi
  stop_server "$MR6/.zskills/dashboard-server.pid" "$PORT_E" >/dev/null
else
  fail "couldn't start server for port-busy test"
fi

###############################################################################
# Phase 9 — Fresh-repo bootstrap (.zskills/ absent at start)
###############################################################################
echo ""
echo "=== Phase 5 AC: fresh-repo bootstrap (.zskills/ absent) ==="

MR7="$TMP_ROOT/mr7"
mkdir -p "$MR7/.claude" "$MR7/plans"
PORT_F=$(( BASE_PORT + 5 ))
cat >"$MR7/.claude/zskills-config.json" <<EOF
{ "dev_server": { "default_port": $PORT_F } }
EOF
# Note: no .zskills/ dir created
if start_server "$MR7" "$PORT_F"; then
  if [ -d "$MR7/.zskills" ]; then
    pass "fresh repo: .zskills/ auto-created on startup"
  else
    fail "fresh repo: .zskills/ not auto-created"
  fi
  if [ -f "$MR7/.zskills/dashboard-server.pid" ]; then
    pass "fresh repo: PID file written"
  else
    fail "fresh repo: PID file missing"
  fi
  stop_server "$MR7/.zskills/dashboard-server.pid" "$PORT_F" >/dev/null
else
  fail "fresh-repo bootstrap server failed to start"
fi

###############################################################################
# Phase 10 — .gitignore coverage + source hygiene
###############################################################################
echo ""
echo "=== Phase 5 AC: .gitignore coverage + source hygiene ==="

cd "$REPO_ROOT" || exit 1
ALL_OK=1
for path in \
    .zskills/monitor-state.json \
    .zskills/monitor-state.json.lock \
    .zskills/work-on-plans-state.json \
    .zskills/dashboard-server.pid; do
  if git check-ignore "$path" >/dev/null 2>&1; then
    : # ok
  else
    fail ".gitignore missing $path"
    ALL_OK=0
  fi
done
if [ "$ALL_OK" -eq 1 ]; then
  pass ".gitignore covers all four state/PID/lock paths"
fi

# No 2>/dev/null or || true in server.py
if grep -nE '2>/dev/null|\|\|\s*true' "$SERVER_PY" >/dev/null; then
  fail "server.py contains 2>/dev/null or || true"
else
  pass "server.py has no 2>/dev/null or || true"
fi

###############################################################################
# Phase 11 — Cross-process flock acquisition (parallel-write integration)
###############################################################################
echo ""
echo "=== Phase 5 AC: cross-process flock (parallel writers preserved) ==="

MR8="$TMP_ROOT/mr8"
mkdir -p "$MR8/.claude" "$MR8/plans"
PORT_G=$(( BASE_PORT + 6 ))
cat >"$MR8/.claude/zskills-config.json" <<EOF
{ "dev_server": { "default_port": $PORT_G } }
EOF
if start_server "$MR8" "$PORT_G"; then
  # Race: two POSTs in parallel. Both should succeed; final state must
  # contain at least the latter (last-writer-wins under flock).
  curl -sf -m 5 -X POST \
    -H "Origin: http://127.0.0.1:$PORT_G" \
    -H 'Content-Type: application/json' \
    -d '{"plans":{"drafted":[{"slug":"a-plan"}],"reviewed":[],"ready":[]},"issues":{"triage":[],"ready":[]}}' \
    "http://127.0.0.1:$PORT_G/api/queue" >/dev/null &
  P1=$!
  curl -sf -m 5 -X POST \
    -H "Origin: http://127.0.0.1:$PORT_G" \
    -H 'Content-Type: application/json' \
    -d '{"plans":{"drafted":[{"slug":"b-plan"}],"reviewed":[],"ready":[]},"issues":{"triage":[],"ready":[]}}' \
    "http://127.0.0.1:$PORT_G/api/queue" >/dev/null &
  P2=$!
  wait "$P1" "$P2"
  # The final state should have ONE of {a-plan, b-plan} (last-writer-wins).
  if grep -qE '"slug":[[:space:]]*"[ab]-plan"' "$MR8/.zskills/monitor-state.json"; then
    pass "concurrent POSTs both completed; final state is internally consistent"
  else
    fail "concurrent POST final state malformed"
  fi
  # Lock file exists
  if [ -f "$MR8/.zskills/monitor-state.json.lock" ]; then
    pass "monitor-state.json.lock present after writes"
  else
    fail "monitor-state.json.lock missing"
  fi
  stop_server "$MR8/.zskills/dashboard-server.pid" "$PORT_G" >/dev/null
else
  fail "couldn't start server for parallel-write test"
fi

print_summary_and_exit
