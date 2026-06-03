#!/bin/bash
# test-issue-reconsider-endpoint.sh — Phase 3 (DASHBOARD_RUNSTATUS_CLEANUP_PLAN).
# Integration coverage for /api/issue-reconsider:
#   - present + integer payload → 200, issues.reconsider contains [N],
#     issues.skipped[N] STILL PRESENT (sticky), updated_at bumped.
#   - re-POST same number → 200, list unchanged (dedup), updated_at NOT
#     bumped on the no-op dedup path.
#   - bad payloads ({}, {number:0}, {number:"x"}, malformed JSON) → 400.
#   - wrong Origin (CSRF) → 403.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVER="$REPO_ROOT/skills/zskills-dashboard/scripts/zskills_monitor/server.py"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

print_summary_and_exit() {
  echo ""
  echo "---"
  if [ "$FAIL_COUNT" -eq 0 ]; then
    printf '\033[32mResults: %d passed, 0 failed\033[0m\n' "$PASS_COUNT"
    exit 0
  else
    printf '\033[31mResults: %d passed, %d failed\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT"
    exit 1
  fi
}

SCRATCH="/tmp/test-issue-reconsider-endpoint-$$"
cleanup() {
  [ -n "${TEST_KEEP_SCRATCH:-}" ] && return
  if [ -n "${SERVER_PID:-}" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  if [ -d "$SCRATCH" ]; then
    find "$SCRATCH" -type d -exec chmod u+rwx {} \; 2>/dev/null || true
    rm -rf "$SCRATCH"
  fi
}
trap cleanup EXIT INT TERM
mkdir -p "$SCRATCH"

PY="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
if [ -z "$PY" ]; then
  fail "interpreter resolution" "no python3 / python available"
  print_summary_and_exit
fi

make_main_root() {
  local d="$1"
  mkdir -p "$d"
  ( cd "$d" && git init -q && git config user.email t@t && git config user.name t \
      && git commit --allow-empty -q -m init ) >/dev/null
  mkdir -p "$d/.zskills"
}

read_updated_at() {
  local file="$1"
  "$PY" -c "
import json, sys
try:
    print(json.load(open(sys.argv[1])).get('updated_at', ''))
except Exception:
    pass
" "$file"
}

read_reconsider() {
  local file="$1"
  "$PY" -c "
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    print(json.dumps((data.get('issues', {}) or {}).get('reconsider', [])))
except Exception:
    pass
" "$file"
}

read_skipped_key() {
  local file="$1" key="$2"
  "$PY" -c "
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    skipped = (data.get('issues', {}) or {}).get('skipped', {}) or {}
    print('present' if sys.argv[2] in skipped else 'absent')
except Exception:
    print('error')
" "$file" "$key"
}

SERVER_PID=""
SERVER_PORT=""

start_server() {
  local main_root="$1"
  local logfile="$2"
  SERVER_PORT=$("$PY" -c "
import socket
s = socket.socket()
s.bind(('127.0.0.1', 0))
print(s.getsockname()[1])
s.close()
")
  PYTHONPATH="$REPO_ROOT/skills/zskills-dashboard/scripts" \
    "$PY" -m zskills_monitor.server \
    --main-root "$main_root" --port "$SERVER_PORT" >"$logfile" 2>&1 &
  SERVER_PID=$!
  local i
  for i in $(seq 1 30); do
    if "$PY" -c "
import socket, sys
s = socket.socket()
try:
    s.settimeout(0.3)
    s.connect(('127.0.0.1', $SERVER_PORT))
    s.close()
except Exception:
    sys.exit(1)
" 2>/dev/null; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

stop_server() {
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  SERVER_PID=""
  SERVER_PORT=""
}

# POST with the matching Origin header (passes _origin_ok).
http_post() {
  local path="$1" body="$2"
  "$PY" - "127.0.0.1" "$SERVER_PORT" "$path" "$body" <<'PY'
import sys, urllib.request, urllib.error
host, port, path, body = sys.argv[1:5]
req = urllib.request.Request(
    f"http://{host}:{port}{path}",
    data=body.encode("utf-8"),
    method="POST",
    headers={"Content-Type": "application/json", "Origin": f"http://{host}:{port}"},
)
try:
    resp = urllib.request.urlopen(req, timeout=5)
    print(resp.status)
    print(resp.read().decode("utf-8"))
except urllib.error.HTTPError as e:
    print(e.code)
    print(e.read().decode("utf-8"))
PY
}

# POST with a wrong Origin header (should fail _origin_ok → 403).
http_post_bad_origin() {
  local path="$1" body="$2"
  "$PY" - "127.0.0.1" "$SERVER_PORT" "$path" "$body" <<'PY'
import sys, urllib.request, urllib.error
host, port, path, body = sys.argv[1:5]
req = urllib.request.Request(
    f"http://{host}:{port}{path}",
    data=body.encode("utf-8"),
    method="POST",
    headers={"Content-Type": "application/json", "Origin": "http://evil.invalid:9999"},
)
try:
    resp = urllib.request.urlopen(req, timeout=5)
    print(resp.status)
    print(resp.read().decode("utf-8"))
except urllib.error.HTTPError as e:
    print(e.code)
    print(e.read().decode("utf-8"))
PY
}

seed_state_with_skip() {
  local state="$1" num="$2"
  "$PY" -c "
import json, sys
num = int(sys.argv[1])
data = {
  'version': '1.2',
  'plans': {},
  'issues': {
    'triage': [], 'ready': [num], 'backlog': [],
    'skipped': {str(num): {'code': 'plan-scale', 'label': 'too big'}},
  },
  'updated_at': 'T_orig',
}
print(json.dumps(data, indent=2))
" "$num" > "$state"
}

# ---------------------------------------------------------------------------
# Case 1: present + integer → 200, reconsider contains [42], skipped intact,
# updated_at bumped.
# ---------------------------------------------------------------------------
test_reconsider_appends_sticky_skip() {
  local d="$SCRATCH/case-1"
  make_main_root "$d"
  local state="$d/.zskills/monitor-state.json"
  seed_state_with_skip "$state" 42

  if ! start_server "$d" "$d/server.log"; then
    fail "(1) server start" "$(cat "$d/server.log" 2>/dev/null | head -20)"
    return
  fi

  local before=$(read_updated_at "$state")
  local out
  out=$(http_post "/api/issue-reconsider" '{"number":42}')
  local status=$(printf '%s' "$out" | head -1)
  if [ "$status" != "200" ]; then
    fail "(1) reconsider returns 200" "status=$status body=$(printf '%s' "$out" | tail -1)"
    stop_server
    return
  fi
  pass "(1) /api/issue-reconsider returns 200 on integer payload"

  local list=$(read_reconsider "$state")
  if [ "$list" = "[42]" ]; then
    pass "(1) issues.reconsider == [42] after append"
  else
    fail "(1) issues.reconsider == [42] after append" "got: $list"
  fi

  local skipped_status=$(read_skipped_key "$state" 42)
  if [ "$skipped_status" = "present" ]; then
    pass "(1) issues.skipped['42'] STILL PRESENT (sticky semantics)"
  else
    fail "(1) issues.skipped['42'] STILL PRESENT (sticky semantics)" "got: $skipped_status"
  fi

  local after=$(read_updated_at "$state")
  if [ "$after" != "$before" ] && [ -n "$after" ]; then
    pass "(1) updated_at bumped after append"
  else
    fail "(1) updated_at bumped after append" "before='$before' after='$after'"
  fi
  stop_server
}

# ---------------------------------------------------------------------------
# Case 2: re-POST same number → 200, dedup, updated_at NOT bumped.
# ---------------------------------------------------------------------------
test_reconsider_dedup_idempotent() {
  local d="$SCRATCH/case-2"
  make_main_root "$d"
  local state="$d/.zskills/monitor-state.json"
  "$PY" -c "
import json
data = {
  'version': '1.2',
  'plans': {},
  'issues': {
    'triage': [], 'ready': [42], 'backlog': [],
    'skipped': {'42': {'code': 'plan-scale', 'label': 'too big'}},
    'reconsider': [42],  # already present
  },
  'updated_at': 'T_orig',
}
print(json.dumps(data, indent=2))
" > "$state"

  if ! start_server "$d" "$d/server.log"; then
    fail "(2) server start" "$(cat "$d/server.log" 2>/dev/null | head -20)"
    return
  fi

  local before=$(read_updated_at "$state")
  local out
  out=$(http_post "/api/issue-reconsider" '{"number":42}')
  local status=$(printf '%s' "$out" | head -1)
  if [ "$status" != "200" ]; then
    fail "(2) re-POST returns 200" "status=$status"
    stop_server
    return
  fi
  pass "(2) /api/issue-reconsider re-POST returns 200"

  local list=$(read_reconsider "$state")
  if [ "$list" = "[42]" ]; then
    pass "(2) issues.reconsider unchanged on dedup (still [42])"
  else
    fail "(2) issues.reconsider unchanged on dedup" "got: $list"
  fi

  local after=$(read_updated_at "$state")
  if [ "$after" = "$before" ]; then
    pass "(2) updated_at NOT bumped on idempotent dedup"
  else
    fail "(2) updated_at NOT bumped on idempotent dedup" "before='$before' after='$after'"
  fi
  stop_server
}

# ---------------------------------------------------------------------------
# Case 3: bad payloads → 400.
# ---------------------------------------------------------------------------
test_bad_payloads() {
  local d="$SCRATCH/case-3"
  make_main_root "$d"
  local state="$d/.zskills/monitor-state.json"
  printf '{}\n' > "$state"

  if ! start_server "$d" "$d/server.log"; then
    fail "(3) server start" "$(cat "$d/server.log" 2>/dev/null | head -20)"
    return
  fi

  local out status

  # {} — no number key
  out=$(http_post "/api/issue-reconsider" '{}')
  status=$(printf '%s' "$out" | head -1)
  if [ "$status" = "400" ]; then
    pass "(3) {} → 400"
  else
    fail "(3) {} → 400" "status=$status"
  fi

  # {number:0} — not > 0
  out=$(http_post "/api/issue-reconsider" '{"number":0}')
  status=$(printf '%s' "$out" | head -1)
  if [ "$status" = "400" ]; then
    pass "(3) {number:0} → 400"
  else
    fail "(3) {number:0} → 400" "status=$status"
  fi

  # {number:"x"} — string, not int
  out=$(http_post "/api/issue-reconsider" '{"number":"x"}')
  status=$(printf '%s' "$out" | head -1)
  if [ "$status" = "400" ]; then
    pass "(3) {number:'x'} → 400"
  else
    fail "(3) {number:'x'} → 400" "status=$status"
  fi

  # malformed JSON
  out=$(http_post "/api/issue-reconsider" 'not-json{{')
  status=$(printf '%s' "$out" | head -1)
  if [ "$status" = "400" ]; then
    pass "(3) malformed JSON → 400"
  else
    fail "(3) malformed JSON → 400" "status=$status"
  fi

  # negative number
  out=$(http_post "/api/issue-reconsider" '{"number":-5}')
  status=$(printf '%s' "$out" | head -1)
  if [ "$status" = "400" ]; then
    pass "(3) {number:-5} → 400"
  else
    fail "(3) {number:-5} → 400" "status=$status"
  fi

  stop_server
}

# ---------------------------------------------------------------------------
# Case 4: CSRF — wrong Origin → 403.
# ---------------------------------------------------------------------------
test_csrf_gate() {
  local d="$SCRATCH/case-4"
  make_main_root "$d"
  local state="$d/.zskills/monitor-state.json"
  seed_state_with_skip "$state" 99

  if ! start_server "$d" "$d/server.log"; then
    fail "(4) server start" "$(cat "$d/server.log" 2>/dev/null | head -20)"
    return
  fi

  local out
  out=$(http_post_bad_origin "/api/issue-reconsider" '{"number":99}')
  local status=$(printf '%s' "$out" | head -1)
  if [ "$status" = "403" ]; then
    pass "(4) wrong Origin → 403"
  else
    fail "(4) wrong Origin → 403" "status=$status body=$(printf '%s' "$out" | tail -1)"
  fi

  # Verify no write happened: reconsider list still absent or empty.
  local list=$(read_reconsider "$state")
  if [ "$list" = "[]" ] || [ -z "$list" ]; then
    pass "(4) reconsider list NOT written on 403 (no side-effect)"
  else
    fail "(4) reconsider list NOT written on 403" "got: $list"
  fi
  stop_server
}

# --- Run all -----------------------------------------------------------------
echo "=== Issue-reconsider endpoint (Phase 3) ==="

test_reconsider_appends_sticky_skip
test_reconsider_dedup_idempotent
test_bad_payloads
test_csrf_gate

# Registration check
if grep -q "test-issue-reconsider-endpoint.sh" "$REPO_ROOT/tests/run-all.sh"; then
  pass "tests/run-all.sh registers test-issue-reconsider-endpoint.sh"
else
  fail "tests/run-all.sh registers test-issue-reconsider-endpoint.sh" "missing"
fi

print_summary_and_exit
