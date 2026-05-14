#!/bin/bash
# Tests for the PID-file self-heal behavior in server.py _handle_health.
#
# Contract: if the PID file at .zskills/dashboard-server.pid is missing
# while the server is alive, the next /api/health request must re-write
# the PID file (best-effort).
#
# This closes the gap where an external `rm` (e.g., a stale-cleanup script
# from another session) leaves the running server with no on-disk PID
# record, breaking `/zskills-dashboard status`.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# Test fixture in /tmp so .zskills/ writes are isolated. Pick a high-numbered
# port (>= 19990) to avoid collisions with the user's running dashboards or
# any other test fixture.
FIXTURE=/tmp/zskills-pid-self-heal-test
PORT=19994
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/.zskills"

PID_FILE="$FIXTURE/.zskills/dashboard-server.pid"
LOG_FILE="$FIXTURE/.zskills/dashboard-server.log"

# Start a server bound to the fixture, on the chosen port.
PYTHONPATH="$REPO_ROOT/skills/zskills-dashboard/scripts" \
  nohup python3 -m zskills_monitor.server \
    --main-root "$FIXTURE" --port "$PORT" \
    > "$LOG_FILE" 2>&1 &
SERVER_PID=$!
disown 2>/dev/null

# Wait up to 5s for server health.
HEALTHY=0
for _ in $(seq 1 25); do
  sleep 0.2
  if curl -sf -m 1 "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; then
    HEALTHY=1
    break
  fi
done

if [ "$HEALTHY" -ne 1 ]; then
  fail "preflight — server failed to come up on port $PORT"
  echo "  last 20 lines of server log:"
  tail -20 "$LOG_FILE" >&2
  kill -TERM "$SERVER_PID" 2>/dev/null
  rm -rf "$FIXTURE"
  echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT+FAIL_COUNT)))"
  exit 1
fi
pass "preflight — server alive on port $PORT (pid $SERVER_PID)"

# Case 1: PID file was written at startup (sanity).
if [ -f "$PID_FILE" ] && grep -q "pid=$SERVER_PID" "$PID_FILE"; then
  pass "PID file written at startup with correct pid"
else
  fail "PID file missing or incorrect at startup"
fi

# Case 2: Remove the PID file externally (simulating an `rm` from another
# session), then poll /api/health. Server must re-write the file.
rm -f "$PID_FILE"
if [ -f "$PID_FILE" ]; then
  fail "could not remove PID file pre-test"
else
  pass "PID file removed (simulating external rm)"
fi

curl -sf -m 2 "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1
# Give the write a moment to land (atomic rename is fast but not instant).
for _ in 1 2 3 4 5; do
  [ -f "$PID_FILE" ] && break
  sleep 0.2
done

if [ -f "$PID_FILE" ]; then
  pass "PID file self-healed after /api/health request"
else
  fail "PID file NOT re-created after /api/health (self-heal did not fire)"
fi

# Case 3: The self-healed PID file has the correct pid + port + started_at.
if [ -f "$PID_FILE" ] \
   && grep -q "pid=$SERVER_PID" "$PID_FILE" \
   && grep -q "port=$PORT" "$PID_FILE" \
   && grep -qE 'started_at=[0-9T:+-]+' "$PID_FILE"; then
  pass "self-healed PID file has pid, port, and started_at"
else
  fail "self-healed PID file is missing required fields"
  echo "  content:"
  cat "$PID_FILE" 2>&1 | sed 's/^/    /'
fi

# Case 4: Repeated /api/health calls with the file present are a no-op
# (the existence check short-circuits before the write).
# Capture the file's mtime, request /api/health, confirm mtime did NOT
# change. (sleep 1 ensures mtime granularity is sufficient.)
sleep 1
MTIME_BEFORE=$(stat -c '%Y' "$PID_FILE")
curl -sf -m 2 "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1
MTIME_AFTER=$(stat -c '%Y' "$PID_FILE")
if [ "$MTIME_BEFORE" = "$MTIME_AFTER" ]; then
  pass "/api/health hot path is a no-op when PID file is present (no churn)"
else
  fail "/api/health re-writes PID file even when present (mtime changed: $MTIME_BEFORE → $MTIME_AFTER)"
fi

# Cleanup: SIGTERM the server. CLAUDE.md rule — never SIGKILL.
kill -TERM "$SERVER_PID" 2>/dev/null
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    break
  fi
  sleep 0.2
done
rm -rf "$FIXTURE"

echo
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (of %d)\033[0m\n' "$PASS_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (of %d)\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit 1
fi
