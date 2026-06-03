#!/bin/bash
# test-plan-skip-clear-paths.sh — Phase 2 (DASHBOARD_RUNSTATUS_CLEANUP_PLAN).
# Integration coverage for the THREE plans-skip clear paths plus
# idempotency + bad-payload + sibling preservation.
#
# Paths:
#   (a) claim-acquire — claim-plan.sh:cmd_acquire pops plans.skipped[<slug>].
#   (b) pin-toggle    — POST /api/queue with a changed pin pops the slug.
#   (b') column-cross drag without pin change — skip mark SURVIVES.
#   (b'') sibling slug toggle — only toggled slug clears; others survive.
#   (c) × dismiss     — POST /api/plan-skip-dismiss with {slug} pops + bumps.
#
# Idempotency: dismiss when absent → 200, no write.
# Bad payload: missing slug → 400, malformed JSON → 400.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVER="$REPO_ROOT/skills/zskills-dashboard/scripts/zskills_monitor/server.py"
CLAIM="$REPO_ROOT/skills/run-plan/scripts/claim-plan.sh"

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

SCRATCH="/tmp/test-plan-skip-clear-paths-$$"
cleanup() {
  [ -n "${TEST_KEEP_SCRATCH:-}" ] && return
  if [ -d "$SCRATCH" ]; then
    find "$SCRATCH" -type d -exec chmod u+rwx {} \; 2>/dev/null || true
    rm -rf "$SCRATCH"
  fi
}
trap cleanup EXIT INT TERM
mkdir -p "$SCRATCH"

# Resolve interpreter — same precedence as the rest of the codebase.
PY="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
if [ -z "$PY" ]; then
  fail "interpreter resolution" "no python3 / python available"
  print_summary_and_exit
fi

# --- helpers ----------------------------------------------------------------
make_main_root() {
  local d="$1"
  mkdir -p "$d"
  ( cd "$d" && git init -q && git config user.email t@t && git config user.name t \
      && git commit --allow-empty -q -m init ) >/dev/null
  mkdir -p "$d/.zskills"
}

seed_state() {
  local file="$1"; shift
  "$PY" -c "$@" > "$file"
}

read_skipped_keys() {
  local file="$1"
  "$PY" -c "
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    keys = sorted((data.get('plans', {}).get('skipped', {}) or {}).keys())
    print(' '.join(keys))
except Exception:
    pass
" "$file"
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

# --- Path (a): claim-acquire clears plans.skipped[<slug>] ------------------
test_claim_acquire_clears_skip() {
  local d="$SCRATCH/path-a"
  make_main_root "$d"
  local state="$d/.zskills/monitor-state.json"
  "$PY" -c "
import json
data = {
  'version': '1.2',
  'plans': {'ready': [{'slug': 'p1'}], 'skipped': {
    'p1': {'code': 'mode-mismatch', 'reason': 'finish≠phase', 'sprint_id': 'S0', 'at': '2026-06-02T12:00:00+00:00'}
  }},
  'issues': {},
  'updated_at': '2026-06-02T12:00:00+00:00',
}
print(json.dumps(data, indent=2))
" > "$state"

  ( cd "$d" && bash "$CLAIM" acquire p1 --pipeline-id test_acquire ) >/dev/null 2>&1
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "(a) claim-acquire returns 0" "rc=$rc"
    return
  fi
  pass "(a) claim-acquire returns 0"

  local keys=$(read_skipped_keys "$state")
  if [ -z "$keys" ]; then
    pass "(a) plans.skipped cleared after claim-acquire"
  else
    fail "(a) plans.skipped cleared after claim-acquire" "remaining: $keys"
  fi
}

# --- Server-driven tests need an HTTP server. Spawn one in the background.
SERVER_PID=""
SERVER_PORT=""

start_server() {
  local main_root="$1"
  local logfile="$2"
  # Pick an ephemeral free port.
  SERVER_PORT=$("$PY" -c "
import socket
s = socket.socket()
s.bind(('127.0.0.1', 0))
print(s.getsockname()[1])
s.close()
")
  # Run the server module via `python3 -m zskills_monitor.server`
  # with PYTHONPATH set to the package root.
  PYTHONPATH="$REPO_ROOT/skills/zskills-dashboard/scripts" \
    "$PY" -m zskills_monitor.server \
    --main-root "$main_root" --port "$SERVER_PORT" >"$logfile" 2>&1 &
  SERVER_PID=$!
  # Wait for readiness.
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

http_post() {
  local path="$1" body="$2"
  "$PY" - "127.0.0.1" "$SERVER_PORT" "$path" "$body" <<'PY'
import sys, urllib.request, json
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

# Probe the server CLI to confirm it exposes --main-root.
probe_server_cli() {
  PYTHONPATH="$REPO_ROOT/skills/zskills-dashboard/scripts" \
    "$PY" -m zskills_monitor.server --help 2>&1 | head -30
}

# --- Path (b): pin-toggle via /api/queue clears plans.skipped[<slug>] ------
test_pin_toggle_clears_skip() {
  local d="$SCRATCH/path-b"
  make_main_root "$d"
  local state="$d/.zskills/monitor-state.json"
  "$PY" -c "
import json
data = {
  'version': '1.2',
  'plans': {
    'drafted': [], 'reviewed': [],
    'ready': [{'slug': 'p1', 'mode': 'phase'}],
    'backlog': [], 'discarded': [],
    'skipped': {
      'p1': {'code': 'mode-mismatch', 'reason': 'finish≠phase', 'sprint_id': 'S0', 'at': 'T0'}
    },
  },
  'issues': {'triage': [], 'ready': [], 'backlog': []},
  'updated_at': 'T0',
}
print(json.dumps(data, indent=2))
" > "$state"

  if ! start_server "$d" "$d/server.log"; then
    fail "(b) server start" "$(cat "$d/server.log" 2>/dev/null | head -20)"
    return
  fi

  # Toggle pin phase → finish in /api/queue.
  local body='{"plans":{"drafted":[],"reviewed":[],"ready":[{"slug":"p1","mode":"finish"}],"backlog":[],"discarded":[]},"issues":{"triage":[],"ready":[],"backlog":[]}}'
  local out
  out=$(http_post "/api/queue" "$body")
  local status=$(printf '%s' "$out" | head -1)
  if [ "$status" != "200" ]; then
    fail "(b) /api/queue returns 200 on pin toggle" "status=$status body=$(printf '%s' "$out" | tail -1)"
    stop_server
    return
  fi
  pass "(b) /api/queue returns 200 on pin toggle"

  local keys=$(read_skipped_keys "$state")
  if [ -z "$keys" ]; then
    pass "(b) plans.skipped cleared after pin-toggle"
  else
    fail "(b) plans.skipped cleared after pin-toggle" "remaining: $keys"
  fi
  stop_server
}

# --- Path (b'): column-cross drag without pin change → skip mark SURVIVES.
test_column_cross_drag_preserves_skip() {
  local d="$SCRATCH/path-bp"
  make_main_root "$d"
  local state="$d/.zskills/monitor-state.json"
  "$PY" -c "
import json
data = {
  'version': '1.2',
  'plans': {
    'drafted': [], 'reviewed': [],
    'ready': [{'slug': 'p1', 'mode': 'phase'}],
    'backlog': [], 'discarded': [],
    'skipped': {
      'p1': {'code': 'mode-mismatch', 'reason': 'finish≠phase', 'sprint_id': 'S0', 'at': 'T0'}
    },
  },
  'issues': {'triage': [], 'ready': [], 'backlog': []},
  'updated_at': 'T0',
}
print(json.dumps(data, indent=2))
" > "$state"

  if ! start_server "$d" "$d/server.log"; then
    fail "(b') server start" "$(cat "$d/server.log" 2>/dev/null | head -20)"
    return
  fi

  # Move p1 from ready → backlog WITHOUT changing the pin.
  local body='{"plans":{"drafted":[],"reviewed":[],"ready":[],"backlog":[{"slug":"p1","mode":"phase"}],"discarded":[]},"issues":{"triage":[],"ready":[],"backlog":[]}}'
  local out
  out=$(http_post "/api/queue" "$body")
  local status=$(printf '%s' "$out" | head -1)
  if [ "$status" != "200" ]; then
    fail "(b') /api/queue returns 200 on column-cross" "status=$status"
    stop_server
    return
  fi
  pass "(b') /api/queue returns 200 on column-cross drag"

  local keys=$(read_skipped_keys "$state")
  if [ "$keys" = "p1" ]; then
    pass "(b') plans.skipped[p1] SURVIVES column-cross without pin change"
  else
    fail "(b') plans.skipped[p1] SURVIVES column-cross without pin change" "got: '$keys'"
  fi
  stop_server
}

# --- Path (b''): sibling slug toggled; unrelated slug's skip SURVIVES.
test_sibling_skip_preserved() {
  local d="$SCRATCH/path-bpp"
  make_main_root "$d"
  local state="$d/.zskills/monitor-state.json"
  "$PY" -c "
import json
data = {
  'version': '1.2',
  'plans': {
    'drafted': [], 'reviewed': [],
    'ready': [{'slug': 'p1'}, {'slug': 'p2'}],
    'backlog': [], 'discarded': [],
    'skipped': {
      'p1': {'code': 'mode-mismatch', 'reason': 'a≠b', 'sprint_id': 'S0', 'at': 'T0'},
      'p2': {'code': 'mode-mismatch', 'reason': 'a≠b', 'sprint_id': 'S0', 'at': 'T0'},
    },
  },
  'issues': {'triage': [], 'ready': [], 'backlog': []},
  'updated_at': 'T0',
}
print(json.dumps(data, indent=2))
" > "$state"

  if ! start_server "$d" "$d/server.log"; then
    fail "(b'') server start" "$(cat "$d/server.log" 2>/dev/null | head -20)"
    return
  fi
  # Toggle p1's pin only. p2 stays bare.
  local body='{"plans":{"drafted":[],"reviewed":[],"ready":[{"slug":"p1","mode":"phase"},{"slug":"p2"}],"backlog":[],"discarded":[]},"issues":{"triage":[],"ready":[],"backlog":[]}}'
  local out
  out=$(http_post "/api/queue" "$body")
  local status=$(printf '%s' "$out" | head -1)
  if [ "$status" != "200" ]; then
    fail "(b'') /api/queue returns 200" "status=$status"
    stop_server
    return
  fi
  pass "(b'') /api/queue returns 200 on sibling toggle"

  local keys=$(read_skipped_keys "$state")
  if [ "$keys" = "p2" ]; then
    pass "(b'') only p1 cleared; p2's skip mark survives"
  else
    fail "(b'') only p1 cleared; p2 survives" "got: '$keys'"
  fi
  stop_server
}

# --- Path (c): × dismiss endpoint clears + bumps updated_at -----------------
test_dismiss_endpoint_clears_and_bumps() {
  local d="$SCRATCH/path-c"
  make_main_root "$d"
  local state="$d/.zskills/monitor-state.json"
  "$PY" -c "
import json
data = {
  'version': '1.2',
  'plans': {
    'drafted': [], 'reviewed': [], 'ready': [], 'backlog': [], 'discarded': [],
    'skipped': {
      'p1': {'code': 'mode-mismatch', 'reason': 'a≠b', 'sprint_id': 'S0', 'at': 'T_orig'}
    },
  },
  'issues': {'triage': [], 'ready': [], 'backlog': []},
  'updated_at': 'T_orig',
}
print(json.dumps(data, indent=2))
" > "$state"

  if ! start_server "$d" "$d/server.log"; then
    fail "(c) server start" "$(cat "$d/server.log" 2>/dev/null | head -20)"
    return
  fi

  local before=$(read_updated_at "$state")
  local out
  out=$(http_post "/api/plan-skip-dismiss" '{"slug":"p1"}')
  local status=$(printf '%s' "$out" | head -1)
  if [ "$status" != "200" ]; then
    fail "(c) dismiss returns 200" "status=$status body=$(printf '%s' "$out" | tail -1)"
    stop_server
    return
  fi
  pass "(c) /api/plan-skip-dismiss returns 200 on present slug"

  local keys=$(read_skipped_keys "$state")
  if [ -z "$keys" ]; then
    pass "(c) plans.skipped cleared after × dismiss"
  else
    fail "(c) plans.skipped cleared after × dismiss" "remaining: $keys"
  fi

  local after=$(read_updated_at "$state")
  if [ "$after" != "$before" ] && [ -n "$after" ]; then
    pass "(c) updated_at bumped after dismiss"
  else
    fail "(c) updated_at bumped after dismiss" "before='$before' after='$after'"
  fi
  stop_server
}

# --- Idempotency: dismiss when slug absent → 200 + NO write -----------------
test_dismiss_idempotent_when_absent() {
  local d="$SCRATCH/idemp"
  make_main_root "$d"
  local state="$d/.zskills/monitor-state.json"
  "$PY" -c "
import json
data = {
  'version': '1.2',
  'plans': {
    'drafted': [], 'reviewed': [], 'ready': [], 'backlog': [], 'discarded': [],
    'skipped': {},  # absent
  },
  'issues': {'triage': [], 'ready': [], 'backlog': []},
  'updated_at': 'T_orig',
}
print(json.dumps(data, indent=2))
" > "$state"

  if ! start_server "$d" "$d/server.log"; then
    fail "(idemp) server start" "$(cat "$d/server.log" 2>/dev/null | head -20)"
    return
  fi

  local before=$(read_updated_at "$state")
  local out
  out=$(http_post "/api/plan-skip-dismiss" '{"slug":"missing"}')
  local status=$(printf '%s' "$out" | head -1)
  if [ "$status" != "200" ]; then
    fail "(idemp) dismiss returns 200 when slug absent" "status=$status"
    stop_server
    return
  fi
  pass "(idemp) /api/plan-skip-dismiss returns 200 on absent slug"

  local after=$(read_updated_at "$state")
  if [ "$after" = "$before" ]; then
    pass "(idemp) updated_at NOT bumped on idempotent dismiss"
  else
    fail "(idemp) updated_at NOT bumped on idempotent dismiss" "before='$before' after='$after'"
  fi
  stop_server
}

# --- Bad payload: missing slug → 400, malformed JSON → 400 -----------------
test_bad_payload() {
  local d="$SCRATCH/bad"
  make_main_root "$d"
  local state="$d/.zskills/monitor-state.json"
  printf '{}\n' > "$state"

  if ! start_server "$d" "$d/server.log"; then
    fail "(bad) server start" "$(cat "$d/server.log" 2>/dev/null | head -20)"
    return
  fi

  local out
  out=$(http_post "/api/plan-skip-dismiss" '{}')
  local status=$(printf '%s' "$out" | head -1)
  if [ "$status" = "400" ]; then
    pass "(bad) missing slug → 400"
  else
    fail "(bad) missing slug → 400" "status=$status"
  fi

  out=$(http_post "/api/plan-skip-dismiss" 'not-json{{')
  status=$(printf '%s' "$out" | head -1)
  if [ "$status" = "400" ]; then
    pass "(bad) malformed JSON → 400"
  else
    fail "(bad) malformed JSON → 400" "status=$status"
  fi
  stop_server
}

# --- Run all -----------------------------------------------------------------
echo "=== Plan-skip three clear paths (Phase 2) ==="

# Probe whether the server CLI supports the flags we use; if --no-pid-file
# isn't supported, skip the server-side tests (Path a still works since it
# doesn't need an HTTP server).
HELP_OUT=$(probe_server_cli)
if echo "$HELP_OUT" | grep -qE -- '--main-root'; then
  pass "server CLI exposes --main-root"
else
  fail "server CLI exposes --main-root" "got: $HELP_OUT"
fi

test_claim_acquire_clears_skip

# Decide whether the server is HTTP-spawnable in this harness. The
# zskills_monitor server's main() may require additional flags; if the
# spawn loop above can't get a port, the server-driven tests will report
# failures naturally — we don't pre-gate.
test_pin_toggle_clears_skip
test_column_cross_drag_preserves_skip
test_sibling_skip_preserved
test_dismiss_endpoint_clears_and_bumps
test_dismiss_idempotent_when_absent
test_bad_payload

# Registration check
if grep -q "test-plan-skip-clear-paths.sh" "$REPO_ROOT/tests/run-all.sh"; then
  pass "tests/run-all.sh registers test-plan-skip-clear-paths.sh"
else
  fail "tests/run-all.sh registers test-plan-skip-clear-paths.sh" "missing"
fi

print_summary_and_exit
