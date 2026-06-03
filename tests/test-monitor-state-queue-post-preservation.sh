#!/bin/bash
# tests/test-monitor-state-queue-post-preservation.sh
#
# Phase 1 of DASHBOARD_RUNSTATUS_CLEANUP — verifies the queue-POST
# handler in skills/zskills-dashboard/scripts/zskills_monitor/server.py
# PRESERVES BY DEFAULT every key the writer does not own.
#
# Specifically: for each of `plans.skipped`, `issues.skipped`, and
# `issues.reconsider`, this test:
#   1. spawns the server with --main-root pointing at a fresh tmpdir;
#   2. seeds .zskills/monitor-state.json with the preserved key populated;
#   3. POSTs /api/queue with a body that mutates only the writable
#      columns (plans.ready and issues.triage) and OMITS the preserved
#      key entirely;
#   4. asserts the response is 200 and the seeded key survives in the
#      on-disk state with the same shape + values, that `updated_at`
#      advanced, that `version` was bumped to "1.2" (writer-owned
#      override), and that `default_mode` was taken from the payload.
#
# Without preserve-by-default, every drag-drop on the dashboard wipes
# `plans.skipped` / `issues.skipped` / `issues.reconsider` — the
# pre-existing latent bug for #813 / #733 that this refactor closes.

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

TMP_ROOT="/tmp/zskills-monitor-queue-preservation.$$"
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

# Choose a base port keyed off $$ to spread across parallel test runs.
BASE_PORT=$(( 21000 + ($$ % 500) ))

start_server() {
  local mr="$1" prt="$2"
  PYTHONPATH="$PKG_PARENT" python3 -m zskills_monitor.server \
    --main-root "$mr" --port "$prt" >>"$mr/server.log" 2>&1 &
  SERVER_PID=$!
  TRACKED_PIDS="$TRACKED_PIDS $SERVER_PID"
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    if curl -sf -m 1 "http://127.0.0.1:$prt/api/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

stop_server() {
  local pidfile="$1"
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

# Seed a monitor-state.json under MAIN_ROOT with the requested key.
# Args: $1=MAIN_ROOT, $2=python-dict-literal for the seed doc.
# Writes <MR>/.zskills/monitor-state.json atomically (via mv).
seed_state() {
  local mr="$1" pydoc="$2"
  mkdir -p "$mr/.zskills"
  python3 - <<PY
import json, os
doc = $pydoc
path = "$mr/.zskills/monitor-state.json"
with open(path + ".tmp", "w") as f:
    json.dump(doc, f, indent=2)
os.replace(path + ".tmp", path)
PY
}

# Run one preservation case. Args:
#   $1 = human label for the case (used in pass/fail messages)
#   $2 = python dict literal seeding monitor-state.json
#   $3 = python expression evaluated against the post-POST state doc
#        that must return True for preservation to be confirmed
#        (variable name `d` is bound to the parsed state dict)
run_case() {
  local label="$1" seed_doc="$2" preserved_pred="$3"

  local MR="$TMP_ROOT/case-${label// /-}"
  local PORT="$BASE_PORT"
  BASE_PORT=$((BASE_PORT + 1))
  mkdir -p "$MR/.claude"
  echo '{"dev_server": {"default_port": '"$PORT"'}}' > "$MR/.claude/zskills-config.json"

  seed_state "$MR" "$seed_doc"
  local seeded_updated_at
  seeded_updated_at=$(python3 -c "import json; print(json.load(open('$MR/.zskills/monitor-state.json')).get('updated_at',''))")

  if ! start_server "$MR" "$PORT"; then
    fail "$label: server did not start on port $PORT"
    return
  fi

  # POST /api/queue with ONLY writable columns mutated; omits the
  # preserved key entirely. version "1.5" in the payload should be
  # ignored — the server pins "1.2" as a writer-owned scalar.
  local body
  body='{
    "default_mode": "finish",
    "version": "1.5",
    "plans": {
      "drafted": [],
      "reviewed": [],
      "ready": [{"slug":"new-plan"}],
      "backlog": [],
      "discarded": []
    },
    "issues": {
      "triage": [42],
      "ready": [],
      "backlog": []
    }
  }'

  local CODE
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H "Origin: http://127.0.0.1:$PORT" \
    -H 'Content-Type: application/json' \
    -d "$body" \
    "http://127.0.0.1:$PORT/api/queue")
  if [ "$CODE" = "200" ]; then
    pass "$label: POST /api/queue returns 200"
  else
    fail "$label: POST /api/queue returned $CODE (expected 200)"
    stop_server "$MR/.zskills/dashboard-server.pid"
    return
  fi

  # Pull out preserved-key / writer-owned assertions via Python so each
  # check has a precise message.
  local result
  result=$(python3 - <<PY
import json
d = json.load(open("$MR/.zskills/monitor-state.json"))
checks = []
# Preservation predicate, supplied by the caller.
try:
    ok = bool($preserved_pred)
except Exception as e:
    ok = False
    checks.append(f"predicate_error:{e}")
checks.append("preserved=" + ("yes" if ok else "no"))
# Writer-owned: version pinned to "1.2".
checks.append("version=" + str(d.get("version")))
# Writer-owned: default_mode set from payload ("finish").
checks.append("default_mode=" + str(d.get("default_mode")))
# updated_at must have changed from the seeded value.
ua = d.get("updated_at", "")
seed = "$seeded_updated_at"
checks.append("updated_at_changed=" + ("yes" if ua and ua != seed else "no"))
# Writable column overlay landed: plans.ready and issues.triage carry payload values.
checks.append("plans_ready_slug=" + ((d.get("plans",{}).get("ready") or [{}])[0].get("slug","") if d.get("plans",{}).get("ready") else ""))
checks.append("issues_triage_first=" + str((d.get("issues",{}).get("triage") or [None])[0]))
print("|".join(checks))
PY
)
  if [[ "$result" == *"preserved=yes"* ]]; then
    pass "$label: preserved key survived the POST"
  else
    fail "$label: preserved key was wiped ($result)"
  fi
  if [[ "$result" == *"version=1.2"* ]]; then
    pass "$label: version pinned to '1.2' (writer-owned override)"
  else
    fail "$label: version not pinned to '1.2' ($result)"
  fi
  if [[ "$result" == *"default_mode=finish"* ]]; then
    pass "$label: default_mode set from payload"
  else
    fail "$label: default_mode not set from payload ($result)"
  fi
  if [[ "$result" == *"updated_at_changed=yes"* ]]; then
    pass "$label: updated_at advanced"
  else
    fail "$label: updated_at did not advance ($result)"
  fi
  if [[ "$result" == *"plans_ready_slug=new-plan"* ]]; then
    pass "$label: writable column plans.ready overlay landed"
  else
    fail "$label: plans.ready overlay missing ($result)"
  fi
  if [[ "$result" == *"issues_triage_first=42"* ]]; then
    pass "$label: writable column issues.triage overlay landed"
  else
    fail "$label: issues.triage overlay missing ($result)"
  fi

  stop_server "$MR/.zskills/dashboard-server.pid"
}

echo ""
echo "=== Phase 1 AC: queue-POST preserves plans.skipped ==="
run_case "plans.skipped" \
  '{"version":"1.2","default_mode":"phase","updated_at":"2020-01-01T00:00:00+00:00","plans":{"drafted":[],"reviewed":[],"ready":[],"backlog":[],"discarded":[],"skipped":{"foo-plan":"already done"}},"issues":{"triage":[],"ready":[],"backlog":[]}}' \
  'd.get("plans",{}).get("skipped") == {"foo-plan":"already done"}'

echo ""
echo "=== Phase 1 AC: queue-POST preserves issues.skipped ==="
run_case "issues.skipped" \
  '{"version":"1.2","default_mode":"phase","updated_at":"2020-01-01T00:00:00+00:00","plans":{"drafted":[],"reviewed":[],"ready":[],"backlog":[],"discarded":[]},"issues":{"triage":[],"ready":[],"backlog":[],"skipped":{"123":"out of scope"}}}' \
  'd.get("issues",{}).get("skipped") == {"123":"out of scope"}'

echo ""
echo "=== Phase 1 AC: queue-POST preserves issues.reconsider ==="
run_case "issues.reconsider" \
  '{"version":"1.2","default_mode":"phase","updated_at":"2020-01-01T00:00:00+00:00","plans":{"drafted":[],"reviewed":[],"ready":[],"backlog":[],"discarded":[]},"issues":{"triage":[],"ready":[],"backlog":[],"reconsider":[42,99]}}' \
  'd.get("issues",{}).get("reconsider") == [42, 99]'

print_summary_and_exit
