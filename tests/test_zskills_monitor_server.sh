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

# Config is read-only for the server (issue #165). The fixture config
# above does NOT include a dashboard block; the server must not mutate
# the file on startup. /update-zskills owns the dashboard-block
# migration (skills/update-zskills/SKILL.md Step 3.6), not the server.
if grep -qE '"dashboard":' "$MR1/.claude/zskills-config.json"; then
  fail "server mutated zskills-config.json (added dashboard block) — must be read-only per issue #165"
else
  pass "server is read-only on zskills-config.json (dashboard block not added)"
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

  # #473: activity[] filter must match the canonical `pipeline` key
  # (not the old `pipeline_id`). Seed TWO tracking pipelines:
  #   (a) run-sample-plan-001 — matches the plan slug; MUST appear in activity[].
  #   (b) run-other-002       — unrelated; MUST NOT appear in activity[].
  # Issue #517 negative-case: without (b) the test passes even if the
  # slug filter is removed entirely (activity[] just returns all
  # pipelines). The EXCLUSION assertion is what makes this load-bearing
  # for the #473 fix.
  mkdir -p "$MR5/.zskills/tracking/run-sample-plan-001"
  cat >"$MR5/.zskills/tracking/run-sample-plan-001/fulfilled.test" <<'MARKER'
date: 2026-05-20T10:00:00-04:00
skill: test
status: ok
output: /dev/null
MARKER
  mkdir -p "$MR5/.zskills/tracking/run-other-002"
  cat >"$MR5/.zskills/tracking/run-other-002/fulfilled.test" <<'MARKER'
date: 2026-05-20T11:00:00-04:00
skill: test
status: ok
output: /dev/null
MARKER
  PLAN_BODY=$(curl -sf -m 3 "http://127.0.0.1:$PORT_D/api/plan/sample-plan")
  # Positive: activity[] non-empty AND contains the matching pipeline.
  if printf '%s' "$PLAN_BODY" | grep -q '"activity":[[:space:]]*\[[[:space:]]*{' \
     && printf '%s' "$PLAN_BODY" | grep -q '"pipeline":[[:space:]]*"run-sample-plan-001"'; then
    pass "/api/plan activity[] filters on canonical 'pipeline' key (#473)"
  else
    fail "/api/plan activity[] empty or missing seeded marker (#473); body: $PLAN_BODY"
  fi
  # Negative (issue #517): the unrelated pipeline MUST NOT appear in
  # activity[]. If the slug filter regresses (returns all pipelines),
  # this assertion fails.
  if printf '%s' "$PLAN_BODY" | grep -q '"pipeline":[[:space:]]*"run-other-002"'; then
    fail "/api/plan activity[] leaked unrelated pipeline 'run-other-002' (slug filter regressed; #517); body: $PLAN_BODY"
  else
    pass "/api/plan activity[] excludes unrelated pipeline 'run-other-002' (#517 negative case)"
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

  # CSRF: missing Origin → 200 (Phase 5b: broadened policy accepts
  # empty-Origin same-origin POSTs; OWASP-recommended posture for
  # localhost-bound services). Body validation still applies downstream.
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H 'Content-Type: application/json' \
    -d '{"plans":{"drafted":[],"reviewed":[],"ready":[]},"issues":{"triage":[],"ready":[]}}' \
    "http://127.0.0.1:$PORT_D/api/queue")
  if [ "$CODE" = "200" ]; then
    pass "POST /api/queue without Origin → 200 (relaxed in Phase 5b)"
  else
    fail "POST /api/queue no-origin → $CODE (expected 200 per Phase 5b)"
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
  QPOST_BODY=$(curl -s -X POST \
    -H "Origin: http://127.0.0.1:$PORT_D" \
    -H 'Content-Type: application/json' \
    -d '{"plans":{"drafted":[{"slug":"sample-plan"}],"reviewed":[],"ready":[]},"issues":{"triage":[42],"ready":[]}}' \
    -w '\n%{http_code}' \
    "http://127.0.0.1:$PORT_D/api/queue")
  CODE=$(printf '%s\n' "$QPOST_BODY" | tail -n1)
  BODY=$(printf '%s\n' "$QPOST_BODY" | sed '$d')
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
  # Response body shape: must include both `updated_at` (legacy) and
  # `state_updated_at` (snap-back race fix — client uses this as the
  # lastCommittedAt watermark for applySnapshot's stale-guard).
  SHAPE_OK=$(printf '%s' "$BODY" | python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.read())
except Exception as e:
    print("PARSE_FAIL:" + str(e))
    sys.exit()
ok = d.get("ok") is True
has_ua = isinstance(d.get("updated_at"), str) and d.get("updated_at")
has_sua = isinstance(d.get("state_updated_at"), str) and d.get("state_updated_at")
eq = d.get("updated_at") == d.get("state_updated_at")
print(f"ok={ok} ua={bool(has_ua)} sua={bool(has_sua)} eq={eq}")
')
  if [ "$SHAPE_OK" = "ok=True ua=True sua=True eq=True" ]; then
    pass "POST /api/queue response includes ok + updated_at + state_updated_at (equal)"
  else
    fail "POST /api/queue response shape wrong: '$SHAPE_OK'"
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
  # Phase 2 (completed-backlog-sections) — backlog accepted, completed rejected,
  # state-file version bumped to 1.2.
  #
  # NOTE: every PHASE-2 POST below preserves the existing `sample-plan`
  # drafted entry and `42` triage entry so the downstream Issue #281
  # regression block still finds them (the POST handler rewrites the
  # entire state-file body each time; omitting them here would delete them).
  ###############################################################################
  echo ""
  echo "=== Phase 2: backlog accepted / completed rejected / version 1.2 ==="

  # W2.6 — validate_queue_body_accepts_backlog: POST with issues.backlog
  # and plans.backlog returns 200 (validator returns None → handler writes).
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H "Origin: http://127.0.0.1:$PORT_D" \
    -H 'Content-Type: application/json' \
    -d '{"plans":{"drafted":[{"slug":"sample-plan"}],"reviewed":[],"ready":[],"backlog":[{"slug":"backlog-plan"}]},"issues":{"triage":[42],"ready":[],"backlog":[123]}}' \
    "http://127.0.0.1:$PORT_D/api/queue")
  if [ "$CODE" = "200" ]; then
    pass "validate_queue_body_accepts_backlog: POST with plans.backlog + issues.backlog → 200"
  else
    fail "validate_queue_body_accepts_backlog: → $CODE (expected 200)"
  fi

  # Issue #677 — validate_queue_body_accepts_discarded: POST with
  # plans.discarded returns 200 (server-side PLAN_COLUMNS now includes
  # discarded as a writable column, parallel to backlog). Plans-only in
  # v1 — issues-side support deferred (ISSUE_COLUMNS unchanged).
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H "Origin: http://127.0.0.1:$PORT_D" \
    -H 'Content-Type: application/json' \
    -d '{"plans":{"drafted":[{"slug":"sample-plan"}],"reviewed":[],"ready":[],"backlog":[],"discarded":[{"slug":"discarded-plan"}]},"issues":{"triage":[42],"ready":[],"backlog":[123]}}' \
    "http://127.0.0.1:$PORT_D/api/queue")
  if [ "$CODE" = "200" ]; then
    pass "validate_queue_body_accepts_discarded: POST with plans.discarded → 200 (#677)"
  else
    fail "validate_queue_body_accepts_discarded: → $CODE (expected 200)"
  fi
  # Persisted: the discarded slug must be present in monitor-state.json.
  if grep -q '"discarded-plan"' "$MR5/.zskills/monitor-state.json"; then
    pass "validate_queue_body_accepts_discarded: plans.discarded entry persisted (#677)"
  else
    fail "validate_queue_body_accepts_discarded: plans.discarded entry missing in state file (#677)"
  fi
  # Issues-side discarded is NOT accepted in v1 (#677 plans-only) — the
  # generic unknown-column path rejects it.
  RESP_DI=$(curl -s -X POST \
    -H "Origin: http://127.0.0.1:$PORT_D" \
    -H 'Content-Type: application/json' \
    -d '{"plans":{"drafted":[],"reviewed":[],"ready":[]},"issues":{"triage":[],"ready":[],"discarded":[123]}}' \
    -w '\n%{http_code}' \
    "http://127.0.0.1:$PORT_D/api/queue")
  CODE_DI=$(printf '%s\n' "$RESP_DI" | tail -n1)
  if [ "$CODE_DI" = "400" ]; then
    pass "validate_queue_body_rejects_issues_discarded_in_post: issues.discarded → 400 (#677 plans-only v1)"
  else
    fail "validate_queue_body_rejects_issues_discarded_in_post: issues.discarded → $CODE_DI (expected 400)"
  fi

  # W2.7 — validate_queue_body_rejects_completed_in_post (plans.completed)
  RESP=$(curl -s -X POST \
    -H "Origin: http://127.0.0.1:$PORT_D" \
    -H 'Content-Type: application/json' \
    -d '{"plans":{"drafted":[],"reviewed":[],"ready":[],"completed":[{"slug":"x"}]},"issues":{"triage":[],"ready":[]}}' \
    -w '\n%{http_code}' \
    "http://127.0.0.1:$PORT_D/api/queue")
  CODE=$(printf '%s\n' "$RESP" | tail -n1)
  BODY=$(printf '%s\n' "$RESP" | sed '$d')
  if [ "$CODE" = "400" ]; then
    pass "validate_queue_body_rejects_completed_in_post: plans.completed → 400"
  else
    fail "validate_queue_body_rejects_completed_in_post: plans.completed → $CODE"
  fi
  if printf '%s' "$BODY" | grep -q "completed column is read-only"; then
    pass "validate_queue_body_rejects_completed_in_post: plans error contains read-only message"
  else
    fail "validate_queue_body_rejects_completed_in_post: plans error missing read-only message: $BODY"
  fi

  # W2.7 — analogous case for issues.completed
  RESP=$(curl -s -X POST \
    -H "Origin: http://127.0.0.1:$PORT_D" \
    -H 'Content-Type: application/json' \
    -d '{"plans":{"drafted":[],"reviewed":[],"ready":[]},"issues":{"triage":[],"ready":[],"completed":[123]}}' \
    -w '\n%{http_code}' \
    "http://127.0.0.1:$PORT_D/api/queue")
  CODE=$(printf '%s\n' "$RESP" | tail -n1)
  BODY=$(printf '%s\n' "$RESP" | sed '$d')
  if [ "$CODE" = "400" ]; then
    pass "validate_queue_body_rejects_completed_in_post: issues.completed → 400"
  else
    fail "validate_queue_body_rejects_completed_in_post: issues.completed → $CODE"
  fi
  if printf '%s' "$BODY" | grep -q "completed column is read-only"; then
    pass "validate_queue_body_rejects_completed_in_post: issues error contains read-only message"
  else
    fail "validate_queue_body_rejects_completed_in_post: issues error missing read-only message: $BODY"
  fi

  # Clarifying assertion: the read-only message must NOT collide with the
  # generic "unexpected ... column" path (W2.2 specificity contract).
  if printf '%s' "$BODY" | grep -q "unexpected issues column"; then
    fail "validate_queue_body_rejects_completed_in_post: completed error collides with generic unknown-column path"
  else
    pass "validate_queue_body_rejects_completed_in_post: completed error is distinct from generic unknown-column"
  fi

  # W2.8 — queue_post_roundtrip_backlog: POST a backlog entry, GET
  # /api/state, assert entry is present AND persisted state file's
  # "version" is "1.2". (sample-plan + 42 preserved so #281 regression
  # block finds them downstream.)
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H "Origin: http://127.0.0.1:$PORT_D" \
    -H 'Content-Type: application/json' \
    -d '{"plans":{"drafted":[{"slug":"sample-plan"}],"reviewed":[],"ready":[],"backlog":[{"slug":"backlog-roundtrip"}]},"issues":{"triage":[42],"ready":[],"backlog":[424242]}}' \
    "http://127.0.0.1:$PORT_D/api/queue")
  if [ "$CODE" = "200" ]; then
    pass "queue_post_roundtrip_backlog: POST → 200"
  else
    fail "queue_post_roundtrip_backlog: POST → $CODE"
  fi
  # State file must report version 1.2 and contain the new backlog entries.
  if grep -q '"version": "1.2"' "$MR5/.zskills/monitor-state.json"; then
    pass "queue_post_roundtrip_backlog: persisted state file version == 1.2"
  else
    fail "queue_post_roundtrip_backlog: persisted state file version != 1.2 ($(grep version "$MR5/.zskills/monitor-state.json" | head -1))"
  fi
  if grep -q '"backlog-roundtrip"' "$MR5/.zskills/monitor-state.json"; then
    pass "queue_post_roundtrip_backlog: plans.backlog entry persisted"
  else
    fail "queue_post_roundtrip_backlog: plans.backlog entry missing in state file"
  fi
  if grep -q '424242' "$MR5/.zskills/monitor-state.json"; then
    pass "queue_post_roundtrip_backlog: issues.backlog entry persisted"
  else
    fail "queue_post_roundtrip_backlog: issues.backlog entry missing in state file"
  fi
  # GET /api/state must also surface the new backlog entry.
  GOT_BACKLOG=$(curl -sf -m 5 "http://127.0.0.1:$PORT_D/api/state" \
    | PYTHONPATH="$PKG_PARENT" python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    plans = (d.get("queues") or {}).get("plans") or {}
    backlog = plans.get("backlog") or []
    found = False
    for ent in backlog:
        if isinstance(ent, dict) and ent.get("slug") == "backlog-roundtrip":
            found = True
            break
        if isinstance(ent, str) and ent == "backlog-roundtrip":
            found = True
            break
    print("FOUND" if found else "MISSING")
except Exception as e:
    print(f"PARSE_ERROR: {e}")
')
  if [ "$GOT_BACKLOG" = "FOUND" ]; then
    pass "queue_post_roundtrip_backlog: GET /api/state surfaces plans.backlog entry"
  else
    fail "queue_post_roundtrip_backlog: GET state missing backlog entry: $GOT_BACKLOG"
  fi

  ###############################################################################
  # Issue #281 regression — POST→GET main_root symmetry
  # POST handlers anchor on ctx['main_root']; GET /api/state must
  # surface that SAME root in snapshot.repo_root, even when the server
  # process's cwd differs from MAIN_ROOT (the classic asymmetry trigger).
  # Pre-#281, collect_snapshot would `_resolve_main_root` from its own
  # cwd; the GET could therefore disagree with where POST wrote.
  ###############################################################################
  echo ""
  echo "=== Issue #281 regression: POST/GET main_root symmetry ==="

  # MR5 is /tmp/.../mr5 and is NOT a git checkout (no .git). Confirm
  # the server bound MAIN_ROOT to MR5 (where POST writes go).
  if [ -f "$MR5/.zskills/monitor-state.json" ]; then
    pass "#281 setup: POST wrote state under MR5 (ctx['main_root'])"
  else
    fail "#281 setup: monitor-state.json not under MR5"
  fi

  # GET /api/state must report repo_root == MR5, matching where POST
  # wrote. Use python so we don't introduce a jq dependency (zskills
  # convention: no jq).
  GET_ROOT=$(curl -sf -m 5 "http://127.0.0.1:$PORT_D/api/state" \
    | PYTHONPATH="$PKG_PARENT" python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get("repo_root", ""))
except Exception as e:
    print(f"PARSE_ERROR: {e}")
')
  EXPECTED_ROOT=$(cd "$MR5" && pwd -P)
  if [ "$GET_ROOT" = "$EXPECTED_ROOT" ]; then
    pass "#281: GET /api/state repo_root matches POST's MAIN_ROOT ($EXPECTED_ROOT)"
  else
    fail "#281: GET repo_root='$GET_ROOT' != expected='$EXPECTED_ROOT' — POST/GET asymmetry"
  fi

  # The POSTed sample-plan slug must be visible in the GET snapshot's
  # queues block — proves the GET is reading the SAME state file POST
  # wrote, anchored on the SAME main_root. Pre-#281, if `_resolve_main_root`
  # inside collect_snapshot ever drifted (e.g. server cwd != MR5), the
  # GET would read a different .zskills/monitor-state.json and the
  # POSTed slug would be missing.
  SAW_POSTED_SLUG=$(curl -sf -m 5 "http://127.0.0.1:$PORT_D/api/state" \
    | PYTHONPATH="$PKG_PARENT" python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    plans = (d.get("queues") or {}).get("plans") or {}
    for col, entries in plans.items():
        for ent in entries:
            if isinstance(ent, dict) and ent.get("slug") == "sample-plan":
                print("FOUND")
                sys.exit(0)
            if isinstance(ent, str) and ent == "sample-plan":
                print("FOUND")
                sys.exit(0)
    print("MISSING")
except Exception as e:
    print(f"PARSE_ERROR: {e}")
')
  if [ "$SAW_POSTED_SLUG" = "FOUND" ]; then
    pass "#281: GET snapshot reflects POST-written slug (POST/GET read same MAIN_ROOT)"
  else
    fail "#281: POSTed slug missing from GET — POST/GET resolved different MAIN_ROOTs ($SAW_POSTED_SLUG)"
  fi

  # Defense in depth: even if the server process's cwd changes (e.g.
  # an operator cd's elsewhere and inotify-triggers a fresh snapshot),
  # the GET path must STILL anchor on ctx['main_root']. We can't easily
  # chdir the running server from the test, but we CAN drive a fresh
  # /api/state from a curl run with the test shell sitting in /tmp —
  # the server is what resolves, not the client. If the server were
  # honoring its own cwd (the pre-#281 risk), it would have been
  # /tmp/zskills-monitor-server-test.$$ at start_server time (TMP_ROOT),
  # not MR5. The fact that the assertions above pass already proves
  # the symmetry — record an explicit assertion line for the audit.
  pass "#281: ctx['main_root'] is the single source of truth for POST + GET"

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

  # CSRF: reset without Origin → 200 (Phase 5b: relaxed policy accepts
  # empty Origin via _origin_ok; reset endpoint reuses _origin_ok).
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    "http://127.0.0.1:$PORT_D/api/work-state/reset")
  if [ "$CODE" = "200" ]; then
    pass "POST /api/work-state/reset without Origin → 200 (relaxed in Phase 5b)"
  else
    fail "POST /api/work-state/reset no-origin → $CODE (expected 200 per Phase 5b)"
  fi

  # CSRF defense: reset with cross-origin Origin → 403 (invariant preserved)
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H "Origin: http://evil.example.com" \
    "http://127.0.0.1:$PORT_D/api/work-state/reset")
  if [ "$CODE" = "403" ]; then
    pass "POST /api/work-state/reset with cross-origin → 403 (invariant)"
  else
    fail "POST /api/work-state/reset cross-origin → $CODE (expected 403)"
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

  # CSRF: trigger without Origin → 501 (Phase 5b: _origin_ok accepts
  # empty Origin; trigger config remains empty for this MR so the
  # response is 501 — proving the Origin check no longer short-circuits
  # to 403 for missing Origin).
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H 'Content-Type: application/json' \
    -d '{"command":"/work-on-plans 1"}' \
    "http://127.0.0.1:$PORT_D/api/trigger")
  if [ "$CODE" = "501" ]; then
    pass "/api/trigger without Origin → 501 (relaxed CSRF in Phase 5b; empty trigger config)"
  else
    fail "/api/trigger no-origin → $CODE (expected 501 per Phase 5b + empty trigger config)"
  fi

  # CSRF defense: trigger with cross-origin Origin → 403 (invariant preserved)
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H "Origin: http://evil.example.com" \
    -H 'Content-Type: application/json' \
    -d '{"command":"/work-on-plans 1"}' \
    "http://127.0.0.1:$PORT_D/api/trigger")
  if [ "$CODE" = "403" ]; then
    pass "/api/trigger with cross-origin → 403 (invariant)"
  else
    fail "/api/trigger cross-origin → $CODE (expected 403)"
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

###############################################################################
# Phase 12 — index.html cache-bust: ?v=<mtime_ns> substituted on /
###############################################################################
echo ""
echo "=== Phase 12: index.html cache-bust (?v= on app.css / app.js refs) ==="

MR9="$TMP_ROOT/mr9"
mkdir -p "$MR9/.claude" "$MR9/plans"
PORT_H=$(( BASE_PORT + 7 ))
cat >"$MR9/.claude/zskills-config.json" <<EOF
{ "dev_server": { "default_port": $PORT_H } }
EOF
if start_server "$MR9" "$PORT_H"; then
  INDEX_BODY=$(curl -sf -m 3 "http://127.0.0.1:$PORT_H/")
  if printf '%s' "$INDEX_BODY" | grep -qE 'href="/app\.css\?v=[0-9]+"'; then
    pass "served / contains href=\"/app.css?v=<digits>\""
  else
    fail "served / missing cache-bust on app.css: $(printf '%s' "$INDEX_BODY" | grep -oE 'href="/app\.css[^"]*"' | head -1)"
  fi
  if printf '%s' "$INDEX_BODY" | grep -qE 'src="/app\.js\?v=[0-9]+"'; then
    pass "served / contains src=\"/app.js?v=<digits>\""
  else
    fail "served / missing cache-bust on app.js: $(printf '%s' "$INDEX_BODY" | grep -oE 'src="/app\.js[^"]*"' | head -1)"
  fi
  # Two requests should return the same ?v= value when the asset is
  # unchanged (mtime stable). Tolerate the FS quirk where mtime_ns may
  # tick by one if the assets were just written by mirror-skill.sh, by
  # extracting the value and comparing.
  V1=$(printf '%s' "$INDEX_BODY" | grep -oE '/app\.css\?v=[0-9]+' | head -1)
  INDEX_BODY2=$(curl -sf -m 3 "http://127.0.0.1:$PORT_H/")
  V2=$(printf '%s' "$INDEX_BODY2" | grep -oE '/app\.css\?v=[0-9]+' | head -1)
  if [ -n "$V1" ] && [ "$V1" = "$V2" ]; then
    pass "cache-bust value stable across two consecutive requests"
  else
    fail "cache-bust value not stable: V1=$V1 V2=$V2"
  fi
  stop_server "$MR9/.zskills/dashboard-server.pid" "$PORT_H" >/dev/null
else
  fail "couldn't start server for cache-bust test"
fi

###############################################################################
# Phase 2 (completed-backlog-sections) W2.9 — static-source assertion:
# every "version": "1.1" literal in server.py is gone, and the v1.2
# replacement is present at every write site (>= 4).
###############################################################################
echo ""
echo "=== Phase 2: state_file_version_bumped_all_sites ==="

V11_COUNT=$(grep -c '"version": "1.1"' "$SERVER_PY" || true)
V12_COUNT=$(grep -c '"version": "1.2"' "$SERVER_PY" || true)
if [ "$V11_COUNT" = "0" ]; then
  pass "state_file_version_bumped_all_sites: zero \"version\": \"1.1\" literals in server.py"
else
  fail "state_file_version_bumped_all_sites: $V11_COUNT \"version\": \"1.1\" literals still present"
fi
if [ "$V12_COUNT" -ge 4 ]; then
  pass "state_file_version_bumped_all_sites: $V12_COUNT \"version\": \"1.2\" literals present (>= 4)"
else
  fail "state_file_version_bumped_all_sites: only $V12_COUNT \"version\": \"1.2\" literals (expected >= 4)"
fi

print_summary_and_exit
