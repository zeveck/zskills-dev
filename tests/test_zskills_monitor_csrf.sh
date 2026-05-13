#!/bin/bash
# Tests for the relaxed _origin_ok policy (Phase 5b, plan
# docs/plans/DASHBOARD_TABS_AND_RENAME.md). Spins up a dashboard server
# bound to a free high port and exercises every documented Origin case.
#
# Run from repo root: bash tests/test_zskills_monitor_csrf.sh

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

TMP_ROOT="/tmp/zskills-monitor-csrf-test.$$"
mkdir -p "$TMP_ROOT"

TRACKED_PIDS=""
cleanup() {
  for p in $TRACKED_PIDS; do
    if kill -0 "$p" 2>/dev/null; then
      kill -TERM "$p" 2>/dev/null || true
      sleep 1
      kill -0 "$p" 2>/dev/null && kill -TERM "$p" 2>/dev/null || true
    fi
  done
  if [ -d "$TMP_ROOT" ]; then
    rm -rf "$TMP_ROOT"
  fi
}
trap cleanup EXIT INT TERM

# Pick a free-ish high port — distinct from the monitor_server suite's range.
BASE_PORT=$(( 20000 + ($$ % 500) ))
PORT="$BASE_PORT"

MR="$TMP_ROOT/mr"
mkdir -p "$MR/.claude" "$MR/plans" "$MR/.zskills"
cat >"$MR/.claude/zskills-config.json" <<EOF
{
  "dev_server": { "default_port": $PORT },
  "execution": { "landing": "pr" }
}
EOF
# Seed an empty queue state so /api/queue payload validation passes.
cat >"$MR/.zskills/monitor-state.json" <<'EOF'
{
  "version": "1.1",
  "default_mode": "phase",
  "plans": {"drafted": [], "reviewed": [], "ready": []},
  "issues": {"triage": [], "ready": []},
  "updated_at": "2026-01-01T00:00:00+00:00"
}
EOF

# Start server.
PYTHONPATH="$PKG_PARENT" python3 -m zskills_monitor.server \
  --main-root "$MR" --port "$PORT" >>"$MR/server.log" 2>&1 &
SERVER_PID=$!
TRACKED_PIDS="$TRACKED_PIDS $SERVER_PID"

# Wait up to 3s for readiness.
READY=0
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
  if curl -sf -m 1 "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 0.25
done
if [ "$READY" != "1" ]; then
  fail "server failed to start at port $PORT"
  print_summary_and_exit
fi
pass "server started at port $PORT"

# Valid body (sent on every test).
BODY='{"default_mode":"phase","plans":{"drafted":[],"reviewed":[],"ready":[]},"issues":{"triage":[],"ready":[]}}'

# Helper: POST /api/queue with given Origin header (or none if "-").
# Echoes the HTTP status code only.
post_with_origin() {
  local origin="$1"
  local body="$2"
  if [ "$origin" = "-" ]; then
    curl -s -o /dev/null -w '%{http_code}' \
      -X POST -H 'Content-Type: application/json' \
      "http://127.0.0.1:$PORT/api/queue" -d "$body"
  else
    curl -s -o /dev/null -w '%{http_code}' \
      -X POST -H "Origin: $origin" -H 'Content-Type: application/json' \
      "http://127.0.0.1:$PORT/api/queue" -d "$body"
  fi
}

# --- Acceptance Criterion (a): same-host POST accepted (200) ---
CODE=$(post_with_origin "http://127.0.0.1:$PORT" "$BODY")
if [ "$CODE" = "200" ]; then
  pass "same-host 127.0.0.1 Origin accepted (200)"
else
  fail "same-host 127.0.0.1 Origin returned $CODE (expected 200)"
fi

CODE=$(post_with_origin "http://localhost:$PORT" "$BODY")
if [ "$CODE" = "200" ]; then
  pass "same-host localhost Origin accepted (200)"
else
  fail "same-host localhost Origin returned $CODE (expected 200)"
fi

# --- Acceptance Criterion (b): cross-origin POST rejected (403) ---
CODE=$(post_with_origin "http://evil.com" "$BODY")
if [ "$CODE" = "403" ]; then
  pass "cross-origin evil.com Origin rejected (403)"
else
  fail "cross-origin Origin returned $CODE (expected 403)"
fi

CODE=$(post_with_origin "http://example.org:$PORT" "$BODY")
if [ "$CODE" = "403" ]; then
  pass "cross-origin example.org Origin rejected (403)"
else
  fail "cross-origin example.org returned $CODE (expected 403)"
fi

# --- Acceptance Criterion (c): user-deployment Origins captured in 5a now succeed. ---
# 5a-repro showed these all returned 403 BEFORE the fix:
#   - no Origin header
#   - Origin: null
#   - Origin: https://127.0.0.1:<port>

CODE=$(post_with_origin "-" "$BODY")  # no Origin header
if [ "$CODE" = "200" ]; then
  pass "missing Origin header accepted (200)"
else
  fail "missing Origin header returned $CODE (expected 200 post-5b)"
fi

CODE=$(post_with_origin "null" "$BODY")
if [ "$CODE" = "200" ]; then
  pass "Origin: null accepted (200)"
else
  fail "Origin: null returned $CODE (expected 200 post-5b)"
fi

CODE=$(post_with_origin "https://127.0.0.1:$PORT" "$BODY")
if [ "$CODE" = "200" ]; then
  pass "https://127.0.0.1:PORT (TLS-fronted proxy scheme) accepted (200)"
else
  fail "https same-host Origin returned $CODE (expected 200 post-5b)"
fi

# --- Acceptance Criterion: port-mismatch is rejected (defense). ---
# A localhost Origin pointing at a DIFFERENT port should still be 403:
# it's a different origin per the same-origin policy.
OTHER_PORT=$((PORT + 1))
CODE=$(post_with_origin "http://127.0.0.1:$OTHER_PORT" "$BODY")
if [ "$CODE" = "403" ]; then
  pass "localhost Origin with mismatched port rejected (403)"
else
  fail "localhost Origin different port returned $CODE (expected 403)"
fi

# --- Acceptance Criterion: localhost Origin without port (proxy-stripped) accepted. ---
CODE=$(post_with_origin "http://localhost" "$BODY")
if [ "$CODE" = "200" ]; then
  pass "localhost Origin without explicit port accepted (200)"
else
  fail "localhost Origin without port returned $CODE (expected 200)"
fi

# --- Defense: empty body still 400 (Origin check passes, body validation fires). ---
CODE=$(curl -s -o /dev/null -w '%{http_code}' \
  -X POST -H "Origin: http://127.0.0.1:$PORT" \
  -H 'Content-Type: application/json' \
  "http://127.0.0.1:$PORT/api/queue" -d '{}')
if [ "$CODE" = "400" ]; then
  pass "Origin-accepted invalid body still 400 (validation downstream of CSRF check)"
else
  fail "valid Origin + invalid body returned $CODE (expected 400)"
fi

# Stop the server cleanly.
kill -TERM "$SERVER_PID" 2>/dev/null || true
wait "$SERVER_PID" 2>/dev/null || true

print_summary_and_exit
