#!/bin/bash
# Tests for skills/zskills-dashboard/scripts/zskills_monitor/static/* — the
# Phase 6 read-only dashboard UI.
#
# Strategy: static-grep AC + live-server smoke fetches. Browser-based UI
# behaviour (modal open/close, dim class, error banner toggling) is
# documented as a manual playwright-cli checklist in the phase report;
# we verify the *contract* (file content, served bytes, HTTP codes,
# content-type) here so the suite stays fast and offline-safe.
#
# Run from repo root: bash tests/test_zskills_monitor_dashboard_ui.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PKG_PARENT="$REPO_ROOT/skills/zskills-dashboard/scripts"
SERVER_PY="$PKG_PARENT/zskills_monitor/server.py"
STATIC_DIR="$PKG_PARENT/zskills_monitor/static"
INDEX_HTML="$STATIC_DIR/index.html"
APP_JS="$STATIC_DIR/app.js"
APP_CSS="$STATIC_DIR/app.css"

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

if [ ! -f "$INDEX_HTML" ] || [ ! -f "$APP_JS" ] || [ ! -f "$APP_CSS" ]; then
  fail "static/{index.html,app.js,app.css} all exist"
  print_summary_and_exit
fi
pass "static/{index.html,app.js,app.css} all exist"

###############################################################################
# Block 1 — static-grep ACs (no server required)
###############################################################################

echo ""
echo "=== Phase 6 AC: static-grep contract ==="

# AC: no innerHTML except hardcoded chrome (// chrome-only).
HITS=$(grep -nE '\.innerHTML\s*=' "$APP_JS" | grep -vE '//\s*chrome-only' || true)
if [ -z "$HITS" ]; then
  pass "AC: XSS innerHTML grep returns no lines"
else
  fail "AC: forbidden innerHTML lines: $HITS"
fi

# AC: no setInterval.
if ! grep -nE 'setInterval\s*\(' "$APP_JS" >/dev/null; then
  pass "AC: setInterval not used (setTimeout recursion only)"
else
  fail "AC: setInterval is used; must be setTimeout-recursion"
fi

# AC: no inline event handlers in any static file.
if ! grep -nE 'onclick=|onload=' "$STATIC_DIR" -r >/dev/null; then
  pass "AC: no inline onclick=/onload= handlers"
else
  fail "AC: found inline event handlers"
fi

# AC: no external https:// imports.
if ! grep -nE "import\s+.+from\s+[\"']https?:" "$APP_JS" >/dev/null; then
  pass "AC: no external script imports"
else
  fail "AC: external https:// imports detected"
fi

# AC: CSS variables — count of --bg/--surface/--accent must be ≥ 3.
COUNT=$(grep -c '^\s*--bg:\|^\s*--surface:\|^\s*--accent:' "$APP_CSS" || true)
if [ "${COUNT:-0}" -ge 3 ]; then
  pass "AC: CSS vars (--bg/--surface/--accent) found ($COUNT ≥ 3)"
else
  fail "AC: CSS vars insufficient ($COUNT < 3)"
fi

# AC: deterministic poll interval (2000ms cited in plan).
if grep -qE 'POLL_INTERVAL_MS\s*=\s*2000' "$APP_JS"; then
  pass "AC: POLL_INTERVAL_MS = 2000"
else
  fail "AC: POLL_INTERVAL_MS != 2000"
fi

# AC: cache:'no-store' on every fetch (one in main poll, one each in modals).
NO_STORE_COUNT=$(grep -c 'cache:[[:space:]]*"no-store"' "$APP_JS" || true)
if [ "${NO_STORE_COUNT:-0}" -ge 2 ]; then
  pass "AC: cache:'no-store' on fetch calls ($NO_STORE_COUNT)"
else
  fail "AC: cache:'no-store' missing on some fetches ($NO_STORE_COUNT)"
fi

# AC: visibilitychange handler present.
if grep -q "visibilitychange" "$APP_JS"; then
  pass "AC: visibilitychange handler present"
else
  fail "AC: missing visibilitychange handler"
fi

# AC: Esc handler present.
if grep -qE '"Escape"' "$APP_JS"; then
  pass "AC: Escape key handler present"
else
  fail "AC: missing Escape handler"
fi

# AC: index.html ships <script type="module"> referencing /app.js
if grep -qE '<script[[:space:]]+type="module"[[:space:]]+src="/app\.js"' "$INDEX_HTML"; then
  pass "AC: index.html loads /app.js as ES module"
else
  fail "AC: index.html missing module-script tag for /app.js"
fi

# AC: index.html links /app.css
if grep -qE '<link[[:space:]]+rel="stylesheet"[[:space:]]+href="/app\.css"' "$INDEX_HTML"; then
  pass "AC: index.html links /app.css"
else
  fail "AC: index.html missing /app.css <link>"
fi

# AC: five panels (Plans, Issues, Worktrees, Branches, Activity) + errors banner element.
for panel in panel-plans panel-issues panel-worktrees panel-branches panel-activity; do
  if grep -q "$panel" "$INDEX_HTML"; then
    pass "AC: panel class present: $panel"
  else
    fail "AC: missing panel class: $panel"
  fi
done
if grep -q 'id="errors-banner"' "$INDEX_HTML"; then
  pass "AC: errors-banner element exists"
else
  fail "AC: errors-banner missing"
fi

# AC: dim class is wired for backed-branch dedup.
if grep -qE 'card[[:space:]]+dim|"card dim"' "$APP_JS" && grep -qE '\.card\.dim' "$APP_CSS"; then
  pass "AC: dim CSS class wired in JS + CSS"
else
  fail "AC: dim class missing from JS or CSS"
fi

# AC: "Landed in <ref>" + "Pending" tokens for plan modal phase rows.
if grep -q '"Landed in"' "$APP_JS" || grep -qE 'Landed in ' "$APP_JS"; then
  pass "AC: 'Landed in' token in app.js"
else
  fail "AC: 'Landed in' token missing in app.js"
fi
if grep -qE '"Pending"|" Pending"|Pending"' "$APP_JS"; then
  pass "AC: 'Pending' token in app.js"
else
  fail "AC: 'Pending' token missing in app.js"
fi

# AC: 'Disconnected' banner copy is in index.html.
if grep -q 'Disconnected' "$INDEX_HTML"; then
  pass "AC: 'Disconnected' banner text present"
else
  fail "AC: 'Disconnected' banner missing"
fi

# AC: aria-modal="true" on modal-root.
if grep -qE 'aria-modal="true"' "$INDEX_HTML"; then
  pass "AC: modal has aria-modal=\"true\""
else
  fail "AC: modal missing aria-modal"
fi

###############################################################################
# Block 2 — live-server smoke (start server, fetch /, /app.js, /app.css)
###############################################################################

if ! command -v python3 >/dev/null 2>&1; then
  skip "python3 not available — skipping live-server smoke"
  print_summary_and_exit
fi
if ! command -v curl >/dev/null 2>&1; then
  skip "curl not available — skipping live-server smoke"
  print_summary_and_exit
fi
if [ ! -f "$SERVER_PY" ]; then
  skip "server.py missing — skipping live smoke"
  print_summary_and_exit
fi

TMP_ROOT="/tmp/zskills-monitor-ui-test.$$"
mkdir -p "$TMP_ROOT"

TRACKED_PIDS=""
cleanup() {
  for p in $TRACKED_PIDS; do
    if kill -0 "$p" 2>/dev/null; then
      kill -TERM "$p" 2>/dev/null || true
      sleep 0.5
    fi
  done
  if [ -d "$TMP_ROOT" ]; then
    rm -rf "$TMP_ROOT"
  fi
}
trap cleanup EXIT INT TERM

BASE_PORT=$(( 19500 + ($$ % 400) ))
PORT="$BASE_PORT"

MR="$TMP_ROOT/mr"
mkdir -p "$MR/.claude" "$MR/plans" "$MR/reports"
cat >"$MR/.claude/zskills-config.json" <<EOF
{
  "dev_server": { "default_port": $PORT },
  "execution": { "landing": "pr" }
}
EOF
# Plan with one phase having a non-null commit and another null — used by
# AC for the plan modal "Landed in" / "Pending" UI strings (server-side
# the data drives that, here we just confirm the fixture lands at all).
cat >"$MR/plans/UI_FIXTURE_PLAN.md" <<'EOF'
---
title: UI Fixture Plan
status: active
---

> Landing mode: pr

## Overview
A plan used by Phase 6 UI tests.

## Phase 1 — Done phase
## Phase 2 — Pending phase

## Progress Tracker

| Phase | Status | Commit     | Notes            |
|-------|--------|------------|------------------|
| 1     | done   | `1abcdef0` | initial landing  |
| 2     | todo   | —          |                  |
EOF

PYTHONPATH="$PKG_PARENT" python3 -m zskills_monitor.server \
  --main-root "$MR" --port "$PORT" >>"$MR/server.log" 2>&1 &
SERVER_PID=$!
TRACKED_PIDS="$TRACKED_PIDS $SERVER_PID"

# Wait up to 3s for /api/health.
ready=0
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
  if curl -sf -m 1 "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.25
done
if [ "$ready" -ne 1 ]; then
  fail "server did not start on port $PORT (see $MR/server.log)"
  print_summary_and_exit
fi
pass "server started on port $PORT"

# /  →  index.html (200, text/html)
HEADERS=$(curl -s -D - -o "$MR/root.body" -m 3 "http://127.0.0.1:$PORT/")
CODE=$(printf '%s' "$HEADERS" | head -1 | awk '{print $2}')
CT=$(printf '%s' "$HEADERS" | grep -i '^content-type:' | head -1 | tr -d '\r')
if [ "$CODE" = "200" ]; then
  pass "GET / → 200"
else
  fail "GET / → $CODE"
fi
if printf '%s' "$CT" | grep -qi 'text/html'; then
  pass "GET / Content-Type is text/html"
else
  fail "GET / Content-Type unexpected: $CT"
fi
if grep -q '<title>Z Skills Monitor</title>' "$MR/root.body"; then
  pass "GET / body contains <title>Z Skills Monitor</title>"
else
  fail "GET / body missing dashboard title"
fi
if grep -q 'id="errors-banner"' "$MR/root.body"; then
  pass "GET / body contains errors-banner element"
else
  fail "GET / body missing errors-banner"
fi

# /app.js  →  application/javascript
HEADERS=$(curl -s -D - -o "$MR/app.js.body" -m 3 "http://127.0.0.1:$PORT/app.js")
CODE=$(printf '%s' "$HEADERS" | head -1 | awk '{print $2}')
CT=$(printf '%s' "$HEADERS" | grep -i '^content-type:' | head -1 | tr -d '\r')
if [ "$CODE" = "200" ]; then
  pass "GET /app.js → 200"
else
  fail "GET /app.js → $CODE"
fi
if printf '%s' "$CT" | grep -qi 'application/javascript'; then
  pass "GET /app.js Content-Type is application/javascript"
else
  fail "GET /app.js Content-Type unexpected: $CT"
fi
JS_SIZE=$(wc -c < "$MR/app.js.body")
if [ "${JS_SIZE:-0}" -gt 100 ]; then
  pass "GET /app.js body size > 100 bytes ($JS_SIZE)"
else
  fail "GET /app.js body suspiciously small ($JS_SIZE)"
fi

# /app.css  →  text/css
HEADERS=$(curl -s -D - -o "$MR/app.css.body" -m 3 "http://127.0.0.1:$PORT/app.css")
CODE=$(printf '%s' "$HEADERS" | head -1 | awk '{print $2}')
CT=$(printf '%s' "$HEADERS" | grep -i '^content-type:' | head -1 | tr -d '\r')
if [ "$CODE" = "200" ]; then
  pass "GET /app.css → 200"
else
  fail "GET /app.css → $CODE"
fi
if printf '%s' "$CT" | grep -qi 'text/css'; then
  pass "GET /app.css Content-Type is text/css"
else
  fail "GET /app.css Content-Type unexpected: $CT"
fi
CSS_SIZE=$(wc -c < "$MR/app.css.body")
if [ "${CSS_SIZE:-0}" -gt 100 ]; then
  pass "GET /app.css body size > 100 bytes ($CSS_SIZE)"
else
  fail "GET /app.css body suspiciously small ($CSS_SIZE)"
fi

# /api/state structure (smoke — full shape covered by collect/server tests).
STATE_JSON=$(curl -sf -m 3 "http://127.0.0.1:$PORT/api/state")
for key in '"plans"' '"issues"' '"worktrees"' '"branches"' '"activity"' '"errors"'; do
  if printf '%s' "$STATE_JSON" | grep -q "$key"; then
    pass "GET /api/state contains $key"
  else
    fail "GET /api/state missing $key"
  fi
done

# /api/plan/<slug> for the fixture
PLAN_BODY=$(curl -sf -m 3 "http://127.0.0.1:$PORT/api/plan/ui-fixture-plan")
if printf '%s' "$PLAN_BODY" | grep -q '"slug":[[:space:]]*"ui-fixture-plan"'; then
  pass "GET /api/plan/ui-fixture-plan returns the fixture"
else
  fail "GET /api/plan/ui-fixture-plan unexpected: $(printf '%s' "$PLAN_BODY" | head -c 200)"
fi
# Phase 1 should have a non-null commit; phase 2 should be null.
# (Modal renders these as 'Landed in <ref>' and 'Pending' respectively.)
if printf '%s' "$PLAN_BODY" | grep -q '"commit":[[:space:]]*"1abcdef0"'; then
  pass "fixture plan phase 1 has commit (UI renders 'Landed in')"
else
  fail "fixture plan phase 1 commit missing"
fi
if printf '%s' "$PLAN_BODY" | grep -q '"commit":[[:space:]]*null'; then
  pass "fixture plan phase 2 has null commit (UI renders 'Pending')"
else
  fail "fixture plan phase 2 not null"
fi

# Two consecutive /api/state GETs → byte-equal errors[] (Phase 4 sort).
S1=$(curl -sf -m 3 "http://127.0.0.1:$PORT/api/state")
S2=$(curl -sf -m 3 "http://127.0.0.1:$PORT/api/state")
E1=$(printf '%s' "$S1" | python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); print(json.dumps(d.get("errors",[]),sort_keys=True))')
E2=$(printf '%s' "$S2" | python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); print(json.dumps(d.get("errors",[]),sort_keys=True))')
if [ "$E1" = "$E2" ]; then
  pass "two consecutive /api/state GETs return byte-equal errors[] (banner stable)"
else
  fail "errors[] differs across consecutive polls"
fi

# Stop server cleanly via SIGTERM and verify port is released.
kill -TERM "$SERVER_PID" 2>/dev/null || true
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    break
  fi
  sleep 0.5
done
if ! kill -0 "$SERVER_PID" 2>/dev/null; then
  pass "server exits cleanly on SIGTERM"
else
  fail "server did not exit on SIGTERM"
fi

print_summary_and_exit
