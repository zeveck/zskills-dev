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

# AC (#778): visibilitychange still force-refreshes the state poll on focus.
if grep -A4 'addEventListener("visibilitychange"' "$APP_JS" | grep -q 'schedulePoll(0)'; then
  pass "AC #778: focus triggers immediate schedulePoll(0)"
else
  fail "AC #778: visibilitychange must force-refresh schedulePoll(0) on focus"
fi

# AC (#778): slow background poll while hidden — named hidden interval ≈ 60s.
if grep -qE 'HIDDEN_POLL_INTERVAL_MS\s*=\s*60000' "$APP_JS"; then
  pass "AC #778: HIDDEN_POLL_INTERVAL_MS = 60000 (slow hidden heartbeat)"
else
  fail "AC #778: missing HIDDEN_POLL_INTERVAL_MS = 60000"
fi

# AC (#778): reschedule delay is driven by document.hidden — visible→2s,
# hidden→60s. The shared helper returns HIDDEN_POLL_INTERVAL_MS when hidden
# and POLL_INTERVAL_MS otherwise.
if grep -qE 'document\.hidden\s*\?\s*HIDDEN_POLL_INTERVAL_MS\s*:\s*POLL_INTERVAL_MS' "$APP_JS"; then
  pass "AC #778: poll delay driven by document.hidden (hidden→60s, visible→2s)"
else
  fail "AC #778: poll delay must branch on document.hidden (hidden→HIDDEN_POLL_INTERVAL_MS, visible→POLL_INTERVAL_MS)"
fi

# AC (#778) REGRESSION GUARD: the old hard-stop teardown is GONE. Pre-fix
# pollOnce did `if (document.hidden) { pollTimer = null; return; }` which
# killed the loop while hidden. Assert the nulling-then-returning teardown
# does not remain.
if grep -Pzoq 'pollTimer\s*=\s*null;\s*\n\s*return;' "$APP_JS"; then
  fail "AC #778: pollOnce still tears down the loop (pollTimer = null; return;) when hidden"
else
  pass "AC #778: pollOnce hidden-teardown removed (loop not killed when hidden)"
fi

# AC (#778): pollOnce reschedules via the hidden-aware delay
# so the loop keeps ticking (slowly) while hidden.
if grep -qE 'schedulePoll\(\s*nextPollDelay\(\)\s*\)' "$APP_JS"; then
  pass "AC #778: pollOnce reschedules via schedulePoll(nextPollDelay())"
else
  fail "AC #778: pollOnce must reschedule via schedulePoll(nextPollDelay())"
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

# AC: three panels (Plans, Issues, Branches) + errors banner element.
for panel in panel-plans panel-issues panel-branches; do
  if grep -q "$panel" "$INDEX_HTML"; then
    pass "AC: panel class present: $panel"
  else
    fail "AC: missing panel class: $panel"
  fi
done
if grep -q 'id="activity-strip"' "$INDEX_HTML"; then
  pass "AC: activity-strip present"
else
  fail "AC: activity-strip missing"
fi
if ! grep -q 'panel-worktrees\|id="worktrees-body"\|id="tab-worktrees"' "$INDEX_HTML"; then
  pass "AC: worktrees panel removed from index.html"
else
  fail "AC: worktrees panel still present in index.html"
fi
if grep -q 'id="errors-banner"' "$INDEX_HTML"; then
  pass "AC: errors-banner element exists"
else
  fail "AC: errors-banner missing"
fi

# AC: dim class — CSS rule exists (available for future use); JS no longer
# applies it to backed-branch cards (branches render at full opacity per
# UI-polish round 2).
if grep -qE '\.card\.dim' "$APP_CSS"; then
  pass "AC: dim CSS class defined in stylesheet"
else
  fail "AC: dim CSS class missing from CSS"
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
# AC: column-header move-all chevrons (Issues + Plans panels)
###############################################################################

echo ""
echo "=== Column move-all chevrons (Issues + Plans) ==="

# Each of the 4 actions registers in handleAction's dispatch table.
for act in plan-move-all-left plan-move-all-right issue-move-all-left issue-move-all-right; do
  if grep -qE "\"$act\"" "$APP_JS"; then
    pass "move-all action declared: $act"
  else
    fail "move-all action missing: $act"
  fi
done

# makeColumnMoveAllBtn helper exists and emits aria-label + tabindex.
if grep -qE 'function makeColumnMoveAllBtn' "$APP_JS"; then
  pass "makeColumnMoveAllBtn helper defined"
else
  fail "makeColumnMoveAllBtn helper missing"
fi
if grep -qE 'tabindex.*"0"' "$APP_JS" && grep -qE 'move-all-btn' "$APP_JS"; then
  pass "move-all buttons get tabindex=0 (keyboard parity)"
else
  fail "move-all buttons missing tabindex=0"
fi

# aria-label parity — template composes "<src col> <noun> to <dst col>" at
# render time using {PLAN,ISSUE}_COLUMN_LABELS lookups, so verify the
# template + composition rather than the materialised strings.
ISSUES_TPL_HITS=$(grep -cE '"Move all unclaimed " \+ ISSUE_COLUMN_LABELS\[c\] \+ " issues to " \+ (prev|next)Label' "$APP_JS" || true)
if [ "${ISSUES_TPL_HITS:-0}" -ge 2 ]; then
  pass "Issues aria-label template emits both directions (Triage→Ready, Ready→Triage)"
else
  fail "Issues aria-label template hits: $ISSUES_TPL_HITS (expected ≥2)"
fi
PLANS_TPL_HITS=$(grep -cE '"Move all unclaimed " \+ PLAN_COLUMN_LABELS\[c\] \+ " plans to " \+ (prev|next)Label' "$APP_JS" || true)
if [ "${PLANS_TPL_HITS:-0}" -ge 2 ]; then
  pass "Plans aria-label template emits both directions (4 effective labels across 3 columns)"
else
  fail "Plans aria-label template hits: $PLANS_TPL_HITS (expected ≥2)"
fi
# Sanity: PLAN_COLUMN_LABELS / ISSUE_COLUMN_LABELS are the substitution
# source. If those constants drift, the rendered labels drift with them.
if grep -qE 'PLAN_COLUMN_LABELS = \{' "$APP_JS" && grep -qE 'ISSUE_COLUMN_LABELS = \{' "$APP_JS"; then
  pass "{PLAN,ISSUE}_COLUMN_LABELS maps define substitution targets"
else
  fail "{PLAN,ISSUE}_COLUMN_LABELS missing — aria-labels would render undefined"
fi

# Claim-respect: source of truth is aria-disabled (NOT chip presence).
# moveAllInColumn must filter on aria-disabled AND re-check it in-loop.
if grep -qE 'function moveAllInColumn' "$APP_JS"; then
  pass "moveAllInColumn function defined"
else
  fail "moveAllInColumn function missing"
fi
# Count occurrences of aria-disabled checks inside moveAllInColumn — must
# appear at least twice (snapshot filter + in-loop re-check).
ARIA_HITS=$(awk '/function moveAllInColumn/{flag=1} flag{print} /^}/&&flag{flag=0}' "$APP_JS" \
  | grep -c 'aria-disabled' || true)
if [ "${ARIA_HITS:-0}" -ge 2 ]; then
  pass "moveAllInColumn checks aria-disabled twice (snapshot + in-loop re-check) — found $ARIA_HITS"
else
  fail "moveAllInColumn aria-disabled checks insufficient ($ARIA_HITS < 2)"
fi

# Confirm threshold > 10 unclaimed cards.
if grep -qE 'MOVE_ALL_CONFIRM_THRESHOLD\s*=\s*10' "$APP_JS"; then
  pass "MOVE_ALL_CONFIRM_THRESHOLD = 10"
else
  fail "MOVE_ALL_CONFIRM_THRESHOLD missing or != 10"
fi
if grep -qE 'window\.confirm\(' "$APP_JS"; then
  pass "window.confirm() gate present for >threshold move-all"
else
  fail "window.confirm() gate missing"
fi
# The confirm message must name the count, source column, and dest column.
if grep -qE '"Move " \+ .*" unclaimed " \+ srcLabel \+ " " \+ noun \+ " to " \+ dstLabel' "$APP_JS"; then
  pass "confirm() message includes count + source col + dest col"
else
  fail "confirm() message format unexpected — must include count/source/dest"
fi

# Shake animation: keyframe definition + class binding + JS toggle.
if grep -qE '@keyframes shake-skip' "$APP_CSS"; then
  pass "@keyframes shake-skip defined in app.css"
else
  fail "@keyframes shake-skip missing in app.css"
fi
if grep -qE '\.card\.shake' "$APP_CSS"; then
  pass ".card.shake rule binds the animation"
else
  fail ".card.shake rule missing"
fi
# Shake must be VISUALLY OBVIOUS — at least one keyframe step ≥6px.
SHAKE_BLOCK=$(awk '/@keyframes shake-skip/{flag=1} flag{print} /^}/&&flag{flag=0}' "$APP_CSS")
if printf '%s' "$SHAKE_BLOCK" | grep -qE 'translateX\(-?([6-9]|[1-9][0-9])(\.[0-9]+)?px\)'; then
  pass "shake animation has ≥6px horizontal jitter (visible, not subtle)"
else
  fail "shake animation jitter < 6px (too subtle)"
fi
if grep -qE 'function shakeCard' "$APP_JS"; then
  pass "shakeCard() helper in app.js"
else
  fail "shakeCard() helper missing"
fi
if grep -qE "classList\.add\(['\"]shake['\"]" "$APP_JS"; then
  pass "shake class is added in JS"
else
  fail "shake class never added in JS"
fi

# Adjacent-only: Triage has no « (no plan-move-all-left targeting triage),
# Ready (issues) has no », Drafted has no «, Ready (plans) has no ».
# We verify the asymmetry indirectly via the column-head injection logic:
# the chevron is emitted only when ci > 0 (for «) or ci < length-1 (for »).
if grep -qE 'ci > 0' "$APP_JS" && grep -qE 'ci < (PLAN|ISSUE)_COLUMNS\.length - 1' "$APP_JS"; then
  pass "adjacent-only guards present (no skip-column chevrons)"
else
  fail "adjacent-only guards missing — possible skip-column move-all bug"
fi

###############################################################################
# AC: per-column collapse toggle (chevron in every column-head)
###############################################################################

echo ""
echo "=== Per-column collapse toggle ==="

# 1. column_head_has_collapse_toggle — every column-head renderer (active
#    plans row, active issues row, below-panel band) appends a
#    .column-collapse-toggle button. We verify via the appendCollapseToggle
#    helper (single call site per renderer) — three hits total.
TOGGLE_HITS=$(grep -cE 'appendCollapseToggle\(head,' "$APP_JS" || true)
if [ "${TOGGLE_HITS:-0}" -ge 3 ]; then
  pass "column_head_has_collapse_toggle: appendCollapseToggle wired in ≥3 renderers (got $TOGGLE_HITS)"
else
  fail "column_head_has_collapse_toggle: expected ≥3 appendCollapseToggle calls, got $TOGGLE_HITS"
fi
# Helper itself must construct a button with the class + data-action.
# Since UI-polish round 2 the toggle carries both the shared base class
# (.column-head-btn) and the toggle-specific class (.column-collapse-toggle).
if grep -qE 'function appendCollapseToggle' "$APP_JS" \
   && grep -qE 'cls:\s*"column-head-btn column-collapse-toggle"' "$APP_JS" \
   && grep -qE '"data-action":\s*"column-collapse-toggle"' "$APP_JS"; then
  pass "appendCollapseToggle helper emits .column-head-btn.column-collapse-toggle button with data-action"
else
  fail "appendCollapseToggle helper missing or malformed (class / data-action)"
fi

# 2. collapse_toggle_persists_to_localstorage — source uses localStorage
#    .setItem / .getItem / .removeItem against COLLAPSE_KEY_PREFIX.
if grep -qE 'COLLAPSE_KEY_PREFIX\s*=\s*"zskills:dashboard:collapsed:"' "$APP_JS"; then
  pass "collapse_toggle_persists_to_localstorage: COLLAPSE_KEY_PREFIX constant present"
else
  fail "collapse_toggle_persists_to_localstorage: COLLAPSE_KEY_PREFIX missing"
fi
if grep -qE 'localStorage\.getItem\(\s*COLLAPSE_KEY_PREFIX' "$APP_JS" \
   && grep -qE 'localStorage\.setItem\(\s*COLLAPSE_KEY_PREFIX' "$APP_JS" \
   && grep -qE 'localStorage\.removeItem\(\s*COLLAPSE_KEY_PREFIX' "$APP_JS"; then
  pass "collapse_toggle_persists_to_localstorage: get/set/remove on prefixed key"
else
  fail "collapse_toggle_persists_to_localstorage: missing one of get/set/remove on COLLAPSE_KEY_PREFIX"
fi
# Click delegation: handleAction has a column-collapse-toggle case.
if grep -qE 'action === "column-collapse-toggle"' "$APP_JS"; then
  pass "handleAction handles column-collapse-toggle"
else
  fail "handleAction missing column-collapse-toggle branch"
fi

# 3. collapsed_column_hides_dropzone — CSS hides .dropzone under
#    .column.collapsed. Match the precise selector with display:none.
if grep -nE '\.column\.collapsed\s*>\s*\.dropzone' "$APP_CSS" >/dev/null \
   && awk '/\.column\.collapsed[[:space:]]*>[[:space:]]*\.dropzone/{flag=1} flag && /display:[[:space:]]*none/{print; exit}' "$APP_CSS" | grep -q 'display:[[:space:]]*none'; then
  pass "collapsed_column_hides_dropzone: .column.collapsed > .dropzone { display: none }"
else
  fail "collapsed_column_hides_dropzone: missing CSS rule hiding dropzone under .column.collapsed"
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
if grep -q '<title>Z Skills Dashboard</title>' "$MR/root.body"; then
  pass "GET / body contains <title>Z Skills Dashboard</title>"
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

###############################################################################
# Block 3 — Phase 7: interactive queue + write-back
###############################################################################

echo ""
echo "=== Phase 7 AC: static-grep contract ==="

# AC: drag handlers wired (HTML5 native: dragstart/dragend/dragenter/dragleave/dragover/drop).
for ev in dragstart dragend dragenter dragleave dragover drop; do
  if grep -q "addEventListener(\"$ev\"" "$APP_JS"; then
    pass "AC: drag event $ev wired via addEventListener"
  else
    fail "AC: drag event $ev NOT wired"
  fi
done

# AC: queue endpoint constant present. Other API URL constants were
# pruned by the DASHBOARD_RUNSTATUS_CLEANUP rip.
for url in /api/queue; do
  if grep -q "\"$url\"" "$APP_JS"; then
    pass "AC: $url URL constant present"
  else
    fail "AC: $url URL constant missing"
  fi
done

# AC: cache:'no-store' on every fetch site. Post run-status-rip the
# fetch sites are poll + queue + plan + issue (modal fetches).
NO_STORE_COUNT=$(grep -c 'cache:[[:space:]]*"no-store"' "$APP_JS" || true)
if [ "${NO_STORE_COUNT:-0}" -ge 4 ]; then
  pass "AC: cache:'no-store' on every fetch ($NO_STORE_COUNT ≥ 4)"
else
  fail "AC: cache:'no-store' missing on some fetches ($NO_STORE_COUNT)"
fi

# AC: no innerHTML except chrome-only.
HITS=$(grep -nE '\.innerHTML\s*=' "$APP_JS" | grep -vE '//\s*chrome-only' || true)
if [ -z "$HITS" ]; then
  pass "AC: Phase 7 introduces no innerHTML"
else
  fail "AC: forbidden innerHTML lines: $HITS"
fi

# AC: no setInterval (still setTimeout-recursion only).
if ! grep -nE 'setInterval\s*\(' "$APP_JS" >/dev/null; then
  pass "AC: setInterval still not used"
else
  fail "AC: setInterval is used; must be setTimeout-recursion"
fi

# AC: no inline event handlers in the static dir.
if ! grep -nE 'onclick=|onload=' "$STATIC_DIR" -r >/dev/null; then
  pass "AC: no inline onclick=/onload= handlers (Phase 7)"
else
  fail "AC: found inline event handlers"
fi

# Issue #988 — Default-mode chip and in-flight-sprint footnote REMOVED.
# Verify they are GONE from index.html (regression guard).
if ! grep -q 'id="dm-phase"' "$INDEX_HTML" && ! grep -q 'id="dm-finish"' "$INDEX_HTML"; then
  pass "AC (#988): default-mode segmented buttons removed from index.html"
else
  fail "AC (#988): default-mode buttons still present"
fi
if ! grep -q 'id="default-mode-footnote"' "$INDEX_HTML"; then
  pass "AC (#988): default-mode footnote element removed"
else
  fail "AC (#988): default-mode footnote element still present"
fi

# Issue #988 — dashboard title is an anchor to the deployed docs page.
if grep -q 'id="dashboard-title-link"' "$INDEX_HTML" \
   && grep -q 'zskills-dashboard-the-browser-view' "$INDEX_HTML"; then
  pass "AC (#988): dashboard title is an anchor to inspecting-and-monitoring#zskills-dashboard-the-browser-view"
else
  fail "AC (#988): dashboard title anchor missing"
fi

# AC: aria-live regions for plans/issues announcements.
if grep -q 'id="plans-live"' "$INDEX_HTML" && grep -q 'aria-live="polite"' "$INDEX_HTML"; then
  pass "AC: plans-live aria-live region present"
else
  fail "AC: plans-live region missing"
fi

# AC (DASHBOARD_RUNSTATUS_CLEANUP Phase 1): run-status widget root
# element REMOVED. The pill + its supporting JS/CSS/server endpoints
# were ripped in Phase 1; the AC is now an absence assertion.
if grep -q 'id="run-status"' "$INDEX_HTML"; then
  fail "AC: run-status widget root still present (must be removed Phase 1)"
else
  pass "AC: run-status widget root removed"
fi

# AC: PLAN_COLUMNS / ISSUE_COLUMNS constants in app.js.
if grep -q 'PLAN_COLUMNS' "$APP_JS" && grep -q 'ISSUE_COLUMNS' "$APP_JS"; then
  pass "AC: PLAN_COLUMNS / ISSUE_COLUMNS constants present"
else
  fail "AC: column constants missing"
fi

# AC: renderIssues honors its `queues` argument for column membership
# (mirrors renderPlans). Without this, optimistic drag-and-drop renders
# from the stale per-issue server annotation `it.queue.column` and the
# card snaps back until the next poll. Regression guard for the
# renderIssues-ignores-queues bug.
RENDER_ISSUES_BODY=$(awk '
  /^function renderIssues\(/ { flag=1 }
  flag { print }
  flag && /^}$/ { exit }
' "$APP_JS")
if echo "$RENDER_ISSUES_BODY" | grep -qE 'queues\.issues\[c\]|queues && queues\.issues'; then
  pass "AC: renderIssues references queues.issues (optimistic-render contract)"
else
  fail "AC: renderIssues does not reference queues.issues — regression of optimistic-render bug"
fi

# AC: applySnapshot passes lastGoodQueues (not raw `queues`) to renderIssues
# and fingerprintIssues, so new GH issues present in snap.issues but absent
# from monitor-state.json's queue arrays (deepCloneQueues adds inferred
# entries) still render. Regression guard for the new-issue auto-pickup bug
# introduced when PR #353 made renderIssues honor its queues argument.
# Scoped to applySnapshot's body (commitQueueChange uses same function names
# but a different pattern, so a whole-file grep would false-positive).
APPLY_BODY=$(awk '
  /^function applySnapshot\(/ { flag=1 }
  flag { print }
  flag && /^}$/ { exit }
' "$APP_JS")
if echo "$APPLY_BODY" | grep -qF 'renderIssues(snap.issues || [], lastGoodQueues)' \
   && ! echo "$APPLY_BODY" | grep -qF 'renderIssues(snap.issues || [], queues)'; then
  pass "AC: applySnapshot calls renderIssues with lastGoodQueues (not raw queues)"
else
  fail "AC: applySnapshot must call renderIssues with lastGoodQueues, not raw queues — new-issue auto-pickup regression"
fi
if echo "$APPLY_BODY" | grep -qF 'fingerprintIssues(snap.issues || [], lastGoodQueues)' \
   && ! echo "$APPLY_BODY" | grep -qF 'fingerprintIssues(snap.issues || [], queues)'; then
  pass "AC: applySnapshot calls fingerprintIssues with lastGoodQueues (not raw queues)"
else
  fail "AC: applySnapshot must call fingerprintIssues with lastGoodQueues, not raw queues — fingerprint drift on new issues"
fi

# AC (issue #336): deepCloneQueues gates the prune-against-live-issues
# pass on the `issuesFetchOk` parameter, and applySnapshot passes
# `snap.issues_fetch_ok !== false` (defaulting to true) when calling it.
# Without this gate, a cold-start gh-list failure (issues=[]) triggers
# the prune block to drop every queued number, and the next drag-POST
# persists the wiped queues — corrupting user-set ordering.
DEEPCLONE_BODY=$(awk '
  /^function deepCloneQueues\(/ { flag=1 }
  flag { print }
  flag && /^}$/ { exit }
' "$APP_JS")
if echo "$DEEPCLONE_BODY" | grep -qE 'function deepCloneQueues\(.*issuesFetchOk\)'; then
  pass "AC: deepCloneQueues accepts issuesFetchOk parameter (#336)"
else
  fail "AC: deepCloneQueues signature missing issuesFetchOk param (#336)"
fi
if echo "$DEEPCLONE_BODY" | grep -qF 'issuesFetchOk && !liveIssueNumbers.has(num)'; then
  pass "AC: deepCloneQueues prune-pass gated on issuesFetchOk (#336)"
else
  fail "AC: deepCloneQueues prune pass not gated on issuesFetchOk — cold-start corruption regression (#336)"
fi
if echo "$APPLY_BODY" | grep -qF 'snap.issues_fetch_ok !== false'; then
  pass "AC: applySnapshot reads snap.issues_fetch_ok (#336)"
else
  fail "AC: applySnapshot does not consume snap.issues_fetch_ok — fix not wired (#336)"
fi

# AC: Reconciliation suppress window present (1500ms).
if grep -q 'POST_RECONCILE_SUPPRESS_MS' "$APP_JS" && grep -q '1500' "$APP_JS"; then
  pass "AC: reconciliation suppress window 1500ms present"
else
  fail "AC: reconciliation window missing"
fi

# AC: Mode chip and remove button structure in source.
if grep -q '"mode-chip"' "$APP_JS" && grep -q '"remove-btn"' "$APP_JS"; then
  pass "AC: mode-chip + remove-btn render code present"
else
  fail "AC: mode-chip / remove-btn missing"
fi

# AC: Move buttons (↑ ↓ ← →) wired with action attributes.
for act in plan-up plan-down plan-left plan-right issue-up issue-down issue-left issue-right; do
  if grep -q "\"$act\"" "$APP_JS"; then
    pass "AC: action $act wired"
  else
    fail "AC: action $act missing"
  fi
done

###############################################################################
# Block 3b — Phase 3: Completed + Backlog below-panel band (static-grep)
#
# Strategy: the test file is static-grep based (no JSDOM); each Phase-3
# acceptance test reads from the source code's structural contract.
# Manual playwright-cli verification (W3.13) covers the visual layer.
###############################################################################

echo ""
echo "=== Phase 3 AC: below-panel band + truncation banner (W3.9–W3.12b) ==="

# W3.1 sanity — extended column tuples include `backlog` and `completed`.
# Match in source order so the deny-test for "render-only inclusion" still
# holds (Phase 5's conformance check pins exact tuple ordering).
if grep -qE 'PLAN_COLUMNS = \["drafted", *"reviewed", *"ready", *"backlog", *"discarded", *"completed"\]' "$APP_JS"; then
  pass "W3.1: PLAN_COLUMNS extended with backlog + discarded + completed (#677)"
else
  fail "W3.1: PLAN_COLUMNS tuple did not extend correctly (expected [drafted, reviewed, ready, backlog, discarded, completed])"
fi
if grep -qE 'ISSUE_COLUMNS = \["triage", *"ready", *"backlog", *"completed"\]' "$APP_JS"; then
  pass "W3.1: ISSUE_COLUMNS extended with backlog + completed"
else
  fail "W3.1: ISSUE_COLUMNS tuple did not extend correctly"
fi
if grep -q 'backlog: "Backlog"' "$APP_JS" && grep -q 'completed: "Completed"' "$APP_JS"; then
  pass "W3.1: PLAN_COLUMN_LABELS / ISSUE_COLUMN_LABELS include Backlog + Completed"
else
  fail "W3.1: column labels missing Backlog/Completed entries"
fi

# W3.2 — deepCloneQueues writes a `completed` bucket for plans + issues
# via the same PLAN_COLUMNS / ISSUE_COLUMNS loop. The existing iteration
# at lines 403-404 (now ranging over the extended tuple) is the regression
# pin from #355 / PR #361 — this assertion fails if a future edit
# de-couples the allocator from the constant.
DEEPCLONE_BODY=$(awk '
  /^function deepCloneQueues\(/ { flag=1 }
  flag { print }
  flag && /^}$/ { exit }
' "$APP_JS")
if echo "$DEEPCLONE_BODY" | grep -qE 'for \(const c of PLAN_COLUMNS\) out\.plans\[c\] = \[\]'; then
  pass "W3.2: deepCloneQueues allocates plan buckets from PLAN_COLUMNS"
else
  fail "W3.2: deepCloneQueues plan allocator lost its PLAN_COLUMNS loop"
fi
if echo "$DEEPCLONE_BODY" | grep -qE 'for \(const c of ISSUE_COLUMNS\) out\.issues\[c\] = \[\]'; then
  pass "W3.2: deepCloneQueues allocates issue buckets from ISSUE_COLUMNS"
else
  fail "W3.2: deepCloneQueues issue allocator lost its ISSUE_COLUMNS loop"
fi

# W3.2b — postQueue strips `completed` before sending so the server
# validator does not 400 on otherwise-valid drag commits.
POSTQUEUE_BODY=$(awk '
  /^async function postQueue\(/ { flag=1 }
  flag { print }
  flag && /^}$/ { exit }
' "$APP_JS")
if echo "$POSTQUEUE_BODY" | grep -qE 'stripCompleted|completed' \
   && echo "$POSTQUEUE_BODY" | grep -qE 'if \(k === "completed"\) continue'; then
  pass "W3.2b: postQueue strips plans.completed / issues.completed before POST"
else
  fail "W3.2b: postQueue does not strip completed — server will 400 on drag commits"
fi

# W3.3 — fingerprintPlans / fingerprintIssues iterate the extended tuple,
# so drag-into-backlog and column-membership churn invalidate the
# fingerprint and trigger a re-render. (Mechanically satisfied by the
# `for (const c of PLAN_COLUMNS)` loop in each function.)
FPP_BODY=$(awk '
  /^function fingerprintPlans\(/ { flag=1 }
  flag { print }
  flag && /^}$/ { exit }
' "$APP_JS")
FPI_BODY=$(awk '
  /^function fingerprintIssues\(/ { flag=1 }
  flag { print }
  flag && /^}$/ { exit }
' "$APP_JS")
if echo "$FPP_BODY" | grep -qE 'for \(const c of PLAN_COLUMNS\)'; then
  pass "W3.3: fingerprintPlans enumerates PLAN_COLUMNS (picks up new columns)"
else
  fail "W3.3: fingerprintPlans does not loop PLAN_COLUMNS — drag-into-backlog will not re-render"
fi
if echo "$FPI_BODY" | grep -qE 'for \(const c of ISSUE_COLUMNS\)'; then
  pass "W3.3: fingerprintIssues enumerates ISSUE_COLUMNS"
else
  fail "W3.3: fingerprintIssues does not loop ISSUE_COLUMNS — drag-into-backlog will not re-render"
fi

# W3.3b — deepCloneQueues_skips_null_column_plans: Bug B from PR #650
# fields-plumbing. The inferred-entry loop previously coerced
# `(p.queue && p.queue.column) || "drafted"` — so any plan whose Python-
# side _infer_default_column returned None (historical complete, outside
# window, unbackfilled) got silently re-routed into Drafted, inflating
# that column. Fix asserts: (1) the literal `|| "drafted"` fallback is
# gone from the plan-inference branch, and (2) the new guard
# `if (!col || PLAN_COLUMNS.indexOf(col) < 0) continue;` is present.
# Issue `|| "triage"` fallbacks at the issue-inference branch + the
# fingerprintIssues line are intentionally untouched — _infer_issue_default_column
# always returns "completed" or "triage", never None.
DEEPCLONE_BODY_FRESH=$(awk '
  /^function deepCloneQueues\(/ { flag=1 }
  flag { print }
  flag && /^}$/ { exit }
' "$APP_JS")
# Negative assertion: the plan-inference branch must NOT carry `|| "drafted"`.
# Use a precise pattern — `p.queue.column` followed by `|| "drafted"` — so the
# issue branch's `it.queue.column || "triage"` is unaffected. The plan-branch
# selector is the only one referencing p.queue (vs it.queue).
if echo "$DEEPCLONE_BODY_FRESH" | grep -qE 'p\.queue && p\.queue\.column\) \|\| "drafted"'; then
  fail "W3.3b: deepCloneQueues still has p.queue.column || \"drafted\" — Bug B alive"
else
  pass "W3.3b: deepCloneQueues no longer coerces null plan column to drafted (Bug B fix)"
fi
# Positive assertion: the new guard MUST be present in the plan-inference branch.
if echo "$DEEPCLONE_BODY_FRESH" | grep -qE 'const col = p\.queue && p\.queue\.column' \
   && echo "$DEEPCLONE_BODY_FRESH" | grep -qE 'if \(!col \|\| PLAN_COLUMNS\.indexOf\(col\) < 0\) continue'; then
  pass "W3.3b: deepCloneQueues guards null plan column with skip (Bug B fix)"
else
  fail "W3.3b: deepCloneQueues plan-inference guard missing — null-column plans will re-leak"
fi
# fingerprintPlans must also drop the `|| "drafted"` coercion so the
# fingerprint stays truthful about hidden plans (drag-into-or-out-of
# "hidden" still re-renders, but no fake "drafted" tuple).
FPP_BODY_FRESH=$(awk '
  /^function fingerprintPlans\(/ { flag=1 }
  flag { print }
  flag && /^}$/ { exit }
' "$APP_JS")
if echo "$FPP_BODY_FRESH" | grep -qE '\|\| "drafted"'; then
  fail "W3.3b: fingerprintPlans still has || \"drafted\" — fingerprint lies about hidden plans"
else
  pass "W3.3b: fingerprintPlans drops || \"drafted\" coercion (Bug B fix)"
fi
# Issue-side fallbacks must remain untouched — _infer_issue_default_column
# returns "triage" as its non-completed default, so the defensive `|| "triage"`
# is correct and not part of Bug B. Pin this so a future cleanup doesn't
# accidentally strip both.
if grep -qE 'it\.queue && it\.queue\.column\) \|\| "triage"' "$APP_JS"; then
  pass "W3.3b: issue || \"triage\" fallback preserved (correct for issues; not Bug B)"
else
  fail "W3.3b: issue || \"triage\" fallback was stripped — issues will now leak as null-column"
fi
# W3.3 — truncation flag participates in fingerprintIssues so the banner
# rerenders on flag toggle.
if echo "$FPI_BODY" | grep -qE 'closed_issues_truncated'; then
  pass "W3.3: fingerprintIssues includes closed_issues_truncated flag"
else
  fail "W3.3: fingerprintIssues missing truncation flag — banner won't toggle on flag change"
fi

# W3.4 — renderBelowPanelBand helper exists and is invoked from both
# renderPlans (kind: "plan") and renderIssues (kind: "issue").
if grep -qE 'function renderBelowPanelBand\(' "$APP_JS"; then
  pass "W3.4: renderBelowPanelBand helper defined"
else
  fail "W3.4: renderBelowPanelBand helper missing"
fi
# Markup contract: class="below-panel-band" with data-column children
# data-column="completed" and data-column="backlog" — emitted by the
# helper via BELOW_BAND_COLUMNS iteration.
if grep -qE 'cls: "below-panel-band"' "$APP_JS"; then
  pass "W3.4: below-panel-band element class emitted"
else
  fail "W3.4: .below-panel-band element class missing from source"
fi
if grep -qE 'BELOW_BAND_COLUMNS = \["backlog", *"discarded", *"completed"\]' "$APP_JS"; then
  pass "W3.4: BELOW_BAND_COLUMNS = [backlog, discarded, completed] (sub-column order, #677)"
else
  fail "W3.4: BELOW_BAND_COLUMNS tuple missing or out of order (expected [backlog, discarded, completed])"
fi
# Invocation sites — once from renderPlans, once from renderIssues.
BAND_CALL_COUNT=$(grep -cE 'renderBelowPanelBand\(\{' "$APP_JS" || true)
if [ "${BAND_CALL_COUNT:-0}" -ge 2 ]; then
  pass "W3.4: renderBelowPanelBand invoked from at least 2 sites (renderPlans + renderIssues)"
else
  fail "W3.4: renderBelowPanelBand invocation count = $BAND_CALL_COUNT (expected ≥ 2)"
fi
# Active row of renderPlans iterates ACTIVE_PLAN_COLUMNS — band's columns
# are not duplicated into the active row.
RENDER_PLANS_BODY=$(awk '
  /^function renderPlans\(/ { flag=1 }
  flag { print }
  flag && /^}$/ { exit }
' "$APP_JS")
if echo "$RENDER_PLANS_BODY" | grep -qE 'for \(const c of ACTIVE_PLAN_COLUMNS\)'; then
  pass "W3.4: renderPlans active row iterates ACTIVE_PLAN_COLUMNS"
else
  fail "W3.4: renderPlans does not use ACTIVE_PLAN_COLUMNS — backlog/completed would render in active grid"
fi
RENDER_ISSUES_BODY=$(awk '
  /^function renderIssues\(/ { flag=1 }
  flag { print }
  flag && /^}$/ { exit }
' "$APP_JS")
if echo "$RENDER_ISSUES_BODY" | grep -qE 'for \(const c of ACTIVE_ISSUE_COLUMNS\)'; then
  pass "W3.4: renderIssues active row iterates ACTIVE_ISSUE_COLUMNS"
else
  fail "W3.4: renderIssues does not use ACTIVE_ISSUE_COLUMNS — backlog/completed would render in active grid"
fi

# W3.5 — CSS layout primitive .below-panel-band with grid + 2-column
# template, visual separator, and hidden display:none for empty collapse.
if grep -qE '^\.below-panel-band' "$APP_CSS"; then
  pass "W3.5: .below-panel-band CSS rule defined"
else
  fail "W3.5: .below-panel-band CSS rule missing"
fi
if grep -qE 'grid-template-columns: 1fr 1fr' "$APP_CSS"; then
  pass "W3.5: 2-column grid template (1fr 1fr) declared"
else
  fail "W3.5: 2-column grid template missing"
fi
if grep -qE 'border-top:[^;]*dashed' "$APP_CSS"; then
  pass "W3.5: dashed border-top visual separator from active row"
else
  fail "W3.5: dashed border-top separator missing"
fi
if grep -qE '\.below-panel-band\[hidden\][^{]*\{[[:space:]]*display:[[:space:]]*none' "$APP_CSS"; then
  pass "W3.5: .below-panel-band[hidden] collapses via display:none"
else
  fail "W3.5: [hidden] display:none rule missing"
fi
# D3 — band layout is STANDALONE, not composed with .columns-2. The CSS
# rule must not chain `.below-panel-band.columns-2` or vice versa.
if ! grep -qE '\.below-panel-band\.columns-2|\.columns-2\.below-panel-band' "$APP_CSS"; then
  pass "W3.5 / D3: .below-panel-band is standalone (not composed with .columns-2)"
else
  fail "W3.5 / D3: .below-panel-band composed with .columns-2 (D3 violation)"
fi

# W3.7 (post-#650 reversal) — Below-panel band ALWAYS visible. The prior
# count-derived collapse (`if (totalCount === 0) band.setAttribute("hidden", "")`)
# was removed because the collapsing band created a moving-target UX:
# Backlog should always present as a stable drop affordance, and Completed
# should always show its header (even at 0) so the user has a stable
# spatial anchor. Backlog still renders a placeholder when empty.
BAND_BODY=$(awk '
  /^function renderBelowPanelBand\(/ { flag=1 }
  flag { print }
  flag && /^}$/ { exit }
' "$APP_JS")
# Negative assertion: the collapse predicate must NOT exist anymore.
if echo "$BAND_BODY" | grep -qE 'setAttribute\("hidden"'; then
  fail "W3.7: band must NOT call setAttribute('hidden',...) — collapse logic removed in post-#650 reversal"
else
  pass "W3.7: band has no setAttribute('hidden',...) call — always-visible reversal landed"
fi
# Negative assertion: the dead totalCount accumulator must also be gone.
if echo "$BAND_BODY" | grep -qE 'totalCount \+= arr\.length'; then
  fail "W3.7: dead totalCount accumulator still present — should be removed"
else
  pass "W3.7: dead totalCount accumulator removed alongside collapse predicate"
fi
if echo "$BAND_BODY" | grep -qE 'if \(c === "backlog" && arr\.length === 0\)'; then
  pass "W3.7: Backlog renders placeholder drop-target when empty"
else
  fail "W3.7: Backlog empty-state placeholder missing"
fi
if echo "$BAND_BODY" | grep -qE 'Drag here to defer'; then
  pass "W3.7: Backlog placeholder text 'Drag here to defer' present"
else
  fail "W3.7: Backlog placeholder text missing"
fi

# W3.7b — Truncation banner. The template literal interpolates
# closed_issues_limit TWICE so the operator sees the literal current
# value, not a placeholder. Both interpolations pull from the same
# variable (W3.12b regression — protects against accidental
# field-name-as-literal text).
BANNER_BODY=$(awk '
  /^function renderTruncationBanner\(/ { flag=1 }
  flag { print }
  flag && /^}$/ { exit }
' "$APP_JS")
if [ -n "$BANNER_BODY" ]; then
  pass "W3.7b: renderTruncationBanner helper defined"
else
  fail "W3.7b: renderTruncationBanner helper missing"
fi
if echo "$BANNER_BODY" | grep -qE 'truncation-banner'; then
  pass "W3.7b: banner emits .truncation-banner class"
else
  fail "W3.7b: .truncation-banner class missing from helper"
fi
if echo "$BANNER_BODY" | grep -qE 'flags\.closed_issues_truncated'; then
  pass "W3.7b: banner gates on flags.closed_issues_truncated"
else
  fail "W3.7b: banner gate flag missing"
fi
# Count of `${closed_issues_limit}` template-interpolations — MUST be 2
# (DA3.4 / R7b: two-interpolation contract so the operator sees the
# actual value twice, including the "currently N" parenthetical).
INTERP_COUNT=$(echo "$BANNER_BODY" | grep -oE '\$\{closed_issues_limit\}' | wc -l)
if [ "${INTERP_COUNT:-0}" -eq 2 ]; then
  pass "W3.7b: banner interpolates \${closed_issues_limit} twice (DA3.4)"
else
  fail "W3.7b: banner interpolation count = $INTERP_COUNT (expected 2)"
fi
if echo "$BANNER_BODY" | grep -q 'execution.dashboard_completed_limit'; then
  pass "W3.7b: banner names the config field execution.dashboard_completed_limit"
else
  fail "W3.7b: banner missing config-field name"
fi

###############################################################################
# Phase 3 named tests per spec (W3.9, W3.10, W3.11, W3.12, W3.12b)
###############################################################################

# W3.9 — renders_completed_band_below_issues_panel
# Static-grep variant: renderIssues invokes renderBelowPanelBand with
# kind:"issue" + the queues argument; the helper emits data-column attrs
# for "completed" and "backlog". A fixture issue at queue.column=
# completed reaches the helper via deepCloneQueues' inferred-entry pass
# (line 449-455) which already iterates the extended ISSUE_COLUMNS.
ISSUES_BAND_CALL=$(echo "$RENDER_ISSUES_BODY" | grep -cE 'renderBelowPanelBand\(\{' || true)
if [ "${ISSUES_BAND_CALL:-0}" -ge 1 ] \
   && echo "$RENDER_ISSUES_BODY" | grep -qE 'kind: "issue"'; then
  pass "renders_completed_band_below_issues_panel — renderIssues calls renderBelowPanelBand(kind:issue)"
else
  fail "renders_completed_band_below_issues_panel — wiring missing"
fi
# Card rendering hook — buildIssueCard called from within the helper for
# the issue path.
if echo "$BAND_BODY" | grep -qE 'buildIssueCard\(issue, num, c\)'; then
  pass "renders_completed_band_below_issues_panel — band renders buildIssueCard for issue path"
else
  fail "renders_completed_band_below_issues_panel — buildIssueCard not invoked in band"
fi

# W3.10 — renders_backlog_band_below_plans_panel
PLANS_BAND_CALL=$(echo "$RENDER_PLANS_BODY" | grep -cE 'renderBelowPanelBand\(\{' || true)
if [ "${PLANS_BAND_CALL:-0}" -ge 1 ] \
   && echo "$RENDER_PLANS_BODY" | grep -qE 'kind: "plan"'; then
  pass "renders_backlog_band_below_plans_panel — renderPlans calls renderBelowPanelBand(kind:plan)"
else
  fail "renders_backlog_band_below_plans_panel — wiring missing"
fi
if echo "$BAND_BODY" | grep -qE 'buildPlanCard\('; then
  pass "renders_backlog_band_below_plans_panel — band renders buildPlanCard for plan path"
else
  fail "renders_backlog_band_below_plans_panel — buildPlanCard not invoked in band"
fi

# W3.11 (post-#650 reversal; was below_panel_band_visible_when_backlog_empty_but_no_completed)
# Reframed: the band is ALWAYS visible, no matter which sub-column is
# empty. The Backlog dropzone must be present (it's the user's defer
# affordance) and Completed must render its header even at zero.
if echo "$BAND_BODY" | grep -qE 'data-column": c'; then
  pass "below_panel_band_always_visible — Backlog dropzone <ul> wired (data-column=c, accepts drops)"
else
  fail "below_panel_band_always_visible — Backlog dropzone <ul> missing data-column wiring"
fi
# Completed column-head must be appended unconditionally; the loop over
# BELOW_BAND_COLUMNS already does this, but pin the absence of any
# completed-specific skip-when-empty guard.
if echo "$BAND_BODY" | grep -qE 'completed.*continue|completed.*return'; then
  fail "below_panel_band_always_visible — Completed has an early-skip when empty (should always render)"
else
  pass "below_panel_band_always_visible — Completed renders unconditionally (no skip-when-empty)"
fi

# W3.12 (post-#650 reversal; was below_panel_band_collapse_when_both_empty)
# Old behavior: band sets `hidden=""` when totalCount===0. New behavior:
# band always renders so the spatial layout is stable. Assert the
# inversion: no `hidden` attribute is ever set on the band element.
if echo "$BAND_BODY" | grep -qE 'band\.setAttribute\("hidden"'; then
  fail "below_panel_band_always_visible_with_backlog_droptarget — band must NOT set hidden attribute"
else
  pass "below_panel_band_always_visible_with_backlog_droptarget — band does not call setAttribute('hidden') (always visible)"
fi

# W3.12b — truncation_banner_renders_with_actual_limit_value
# Two-interpolation contract + no field-name-without-value text leak.
# (1) Source contains ${closed_issues_limit} exactly twice in the helper.
# (2) Source does NOT contain a literal "${closed_issues_limit}" inside
#     single-quotes / double-quotes (which would render as the
#     placeholder string instead of interpolating).
if [ "${INTERP_COUNT:-0}" -eq 2 ]; then
  pass "truncation_banner_renders_with_actual_limit_value — template interpolates limit twice"
else
  fail "truncation_banner_renders_with_actual_limit_value — interpolation count != 2 ($INTERP_COUNT)"
fi
# Negative regression: a "${closed_issues_limit}" literal inside
# double-quoted or single-quoted strings would render as text. Backticks
# are the only valid wrapper.
if ! grep -nE "[\"']\\\$\\{closed_issues_limit\\}[\"']" "$APP_JS" >/dev/null; then
  pass "truncation_banner_renders_with_actual_limit_value — no quoted-string \${closed_issues_limit} (no placeholder leak)"
else
  fail "truncation_banner_renders_with_actual_limit_value — quoted-string \${closed_issues_limit} found (would render as literal)"
fi
# Banner gates on flag — absence/false implies no banner render. The
# helper returns early when the flag is falsy.
if echo "$BANNER_BODY" | grep -qE 'if \(!flags\.closed_issues_truncated\) return'; then
  pass "truncation_banner_renders_with_actual_limit_value — no banner when flag absent/false"
else
  fail "truncation_banner_renders_with_actual_limit_value — early-return guard missing"
fi

###############################################################################
# Phase 4 named tests (W4.11 — move-all chevron absence on completed;
# W4.12 — single fetch helper post). Static-grep contract pins.
###############################################################################

echo ""
echo "=== Phase 4 AC: drag-target wiring + Completed read-only (W4.11–W4.12) ==="

# W4.11 — move_all_chevron_absent_on_completed
# The active row already iterates ACTIVE_PLAN_COLUMNS / ACTIVE_ISSUE_COLUMNS
# (excludes completed). The below-panel band MUST NOT emit a move-all-group
# inside its completed sub-column, but MUST emit one inside its backlog
# sub-column. Static-grep against renderBelowPanelBand body — guard is
# `if (c === "backlog")` BEFORE the move-all-group construction.
BAND_BODY=$(awk '
  /^function renderBelowPanelBand\(/ { flag=1 }
  flag { print }
  flag && /^}$/ { exit }
' "$APP_JS")

if echo "$BAND_BODY" | grep -qE 'if \(c === "backlog"\)'; then
  pass "W4.11 move_all_chevron_absent_on_completed — band gates move-all on backlog (not completed)"
else
  fail "W4.11 move_all_chevron_absent_on_completed — band missing 'if (c === \"backlog\")' chevron guard"
fi

if echo "$BAND_BODY" | grep -qE 'makeColumnMoveAllBtn\('; then
  pass "W4.11 move_all_chevron_absent_on_completed — backlog emits makeColumnMoveAllBtn"
else
  fail "W4.11 move_all_chevron_absent_on_completed — backlog sub-column missing chevron emit"
fi

# Verify the move-all-group construction inside the band is INSIDE the
# `if (c === "backlog")` block — extract a 12-line window after the guard
# and confirm it contains the class string.
GUARD_WINDOW=$(echo "$BAND_BODY" | awk '/if \(c === "backlog"\)/{f=12} f{print; f--}')
if echo "$GUARD_WINDOW" | grep -q 'cls: "move-all-group"'; then
  pass "W4.11 move_all_chevron_absent_on_completed — move-all-group inside backlog guard"
else
  fail "W4.11 move_all_chevron_absent_on_completed — move-all-group not inside backlog guard"
fi

# W4.12 — single_fetch_helper_post
# AC4.8: `grep -cE 'fetch\([^)]*api/queue' app.js == 1` — the postQueue
# helper is the sole POST site for /api/queue. Anchored on `fetch(`
# call-syntax so comments / JSDoc / error strings mentioning the path
# don't false-match. (Race-guard `pendingPosts++/--` is composed by
# routing every drag through commitQueueChange → postQueue.)
FETCH_COUNT=$(grep -cE 'fetch\([^)]*api/queue' "$APP_JS" || true)
if [ "${FETCH_COUNT:-0}" -eq 1 ]; then
  pass "W4.12 single_fetch_helper_post — exactly 1 fetch(...api/queue...) site (AC4.8)"
else
  fail "W4.12 single_fetch_helper_post — found $FETCH_COUNT fetch(...api/queue...) sites; expected 1"
fi

# W4.12b — onDrop hard-rejects data-column="completed" drops (AC4.6 pin).
ONDROP_BODY=$(awk '
  /^async function onDrop\(/ { flag=1 }
  flag { print }
  flag && /^}$/ { exit }
' "$APP_JS")
if echo "$ONDROP_BODY" | grep -qE 'targetCol === "completed"'; then
  pass "W4.12b onDrop hard-rejects targetCol === 'completed' (AC4.6)"
else
  fail "W4.12b onDrop missing completed-target reject (AC4.6)"
fi

# W4.12c (post-#650 reversal) — D5 leftmost-active rewrite REMOVED.
# Drops from Backlog now land where dropped (the user's chosen active
# column is honored). Assert the inversion: no sourceColumn==='backlog'
# branch survives, and a comment notes the reversal.
if echo "$ONDROP_BODY" | grep -qE 'sourceColumn === "backlog"'; then
  fail "W4.12c onDrop still rewrites backlog drops — D5 rewrite should be removed (post-#650 reversal, AC4.5 inverted)"
else
  pass "W4.12c onDrop no longer rewrites backlog→active drops (lands where dropped; post-#650 reversal)"
fi
if echo "$ONDROP_BODY" | grep -qE 'overrides plan D5|post-#650|land where dropped'; then
  pass "W4.12c onDrop has a comment noting the D5 design reversal"
else
  fail "W4.12c onDrop missing D5-reversal comment — future readers won't know the inversion is intentional"
fi

###############################################################################
# Block 3b — Favicon + Completed-dropzone read-only cursor (post-#654 cleanup)
###############################################################################

echo ""
echo "=== Post-#654 cleanup: favicon + completed-dropzone cursor ==="

# index.html must link the SVG favicon. Browsers without the link tag
# fall back to /favicon.ico; the server routes BOTH paths to favicon.svg
# (see below) but having the explicit <link> is what gives well-behaved
# UAs the right MIME type without a redirect.
if grep -qE '<link[[:space:]]+rel="icon"[[:space:]]+type="image/svg\+xml"[[:space:]]+href="/favicon.svg"' "$INDEX_HTML"; then
  pass "index_html_links_favicon_svg — <link rel=\"icon\" type=\"image/svg+xml\" href=\"/favicon.svg\">"
else
  fail "index_html_links_favicon_svg — head missing the favicon <link>"
fi

# server.py must route BOTH /favicon.svg AND /favicon.ico to the SVG
# asset (Firefox/Chrome accept image/svg+xml for either path; serving
# from a single asset avoids a separate .ico build step).
if grep -qE 'decoded_path == "/favicon\.svg"' "$SERVER_PY" \
   && grep -qE '_serve_static_file\("favicon\.svg",[[:space:]]*"image/svg\+xml"\)' "$SERVER_PY"; then
  pass "server_routes_favicon_svg — server.py routes /favicon.svg and /favicon.ico"
else
  fail "server_routes_favicon_svg — server.py missing /favicon.svg or /favicon.ico route to favicon.svg"
fi
# Sibling: /favicon.ico exists as its own decoded_path arm.
if grep -qE 'decoded_path == "/favicon\.ico"' "$SERVER_PY"; then
  pass "server_routes_favicon_ico — server.py routes /favicon.ico"
else
  fail "server_routes_favicon_ico — server.py missing /favicon.ico arm (browsers default to this path)"
fi

# Favicon asset must be present in static/.
if [ -f "$STATIC_DIR/favicon.svg" ] && [ -s "$STATIC_DIR/favicon.svg" ]; then
  pass "favicon_svg_asset_present — static/favicon.svg exists and is non-empty"
else
  fail "favicon_svg_asset_present — static/favicon.svg missing or empty"
fi

# CSS must read-only-mark the Completed dropzone via cursor: not-allowed.
# Verify the rule is keyed on [data-column="completed"] AND that the
# declaration block contains `cursor: not-allowed`. Implementation:
# extract the rule block for the selector and assert the declaration is
# inside it (a bare `cursor: not-allowed` elsewhere wouldn't count).
COMPLETED_BLOCK=$(awk '
  /\.dropzone\[data-column="completed"\][[:space:]]*\{/ {p=1}
  p {print}
  p && /\}/ {p=0; print "----"}
' "$APP_CSS")
if echo "$COMPLETED_BLOCK" | grep -qE 'cursor:[[:space:]]*not-allowed'; then
  pass "dropzone_completed_cursor_not_allowed — .dropzone[data-column=\"completed\"] has cursor: not-allowed"
else
  fail "dropzone_completed_cursor_not_allowed — .dropzone[data-column=\"completed\"] missing cursor: not-allowed"
fi

###############################################################################
# Issue #677 — Discarded column for plans (v1, plans-only)
###############################################################################

echo ""
echo "=== Issue #677: Discarded column for plans ==="

# plan_card_x_routes_to_discarded — the ✕ button on a plan card now
# dispatches the `plan-discard` action, which routes to discardPlan(slug).
# discardPlan splices the entry from its current column and pushes it onto
# state.plans.discarded. This is the root-cause fix for the no-op ✕
# button (state-file said nothing, inference fallback re-routed status:
# active plans back to Drafted).
if grep -qE '"data-action": *"plan-discard"' "$APP_JS"; then
  pass "#677 plan_card_x_routes_to_discarded: ✕ button data-action=\"plan-discard\""
else
  fail "#677 plan_card_x_routes_to_discarded: ✕ button missing data-action=\"plan-discard\""
fi
# handleAction has a plan-discard branch dispatching to discardPlan(slug).
if grep -qE 'action === "plan-discard".*discardPlan|if \(action === "plan-discard"\) return discardPlan' "$APP_JS"; then
  pass "#677 plan_card_x_routes_to_discarded: handleAction → discardPlan(slug)"
else
  fail "#677 plan_card_x_routes_to_discarded: handleAction missing plan-discard → discardPlan wiring"
fi
# discardPlan body pushes the entry onto next.plans.discarded.
DISCARD_BODY=$(awk '
  /^async function discardPlan\(/ { flag=1 }
  flag { print }
  flag && /^}$/ { exit }
' "$APP_JS")
if echo "$DISCARD_BODY" | grep -qE 'next\.plans\.discarded\.push'; then
  pass "#677 plan_card_x_routes_to_discarded: discardPlan pushes onto next.plans.discarded"
else
  fail "#677 plan_card_x_routes_to_discarded: discardPlan does not push onto next.plans.discarded"
fi
# Old `plan-remove` action must be gone (renamed per design table).
if grep -qE '"data-action": *"plan-remove"|action === "plan-remove"' "$APP_JS"; then
  fail "#677 legacy plan-remove action still present (should be renamed to plan-discard)"
else
  pass "#677 legacy plan-remove action removed (renamed to plan-discard)"
fi
# Aria-live announcement must say "Discarded plan" (not "Removed plan").
if echo "$DISCARD_BODY" | grep -qE 'announce\("plans-live", *"Discarded plan "'; then
  pass "#677: discardPlan announces \"Discarded plan <slug>\" (aria-live)"
else
  fail "#677: discardPlan aria-live announcement does not say \"Discarded plan\""
fi

# discarded_column_renders_collapsed_by_default — the COLLAPSED_BY_DEFAULT
# Set contains "discarded", and isCollapsed consults it when no
# localStorage entry exists. Tests the structural contract from app.js
# directly (JSDOM-style integration deferred to the playwright-cli
# verification recipe in the issue body).
# Issue #717 expanded the set with branch-section keys; the contract is
# that "discarded" MUST be present (not necessarily the only member).
if grep -qE 'COLLAPSED_BY_DEFAULT *= *new Set\(\[.*"discarded"' "$APP_JS"; then
  pass "#677 discarded_column_renders_collapsed_by_default: COLLAPSED_BY_DEFAULT contains \"discarded\""
else
  fail "#677 discarded_column_renders_collapsed_by_default: COLLAPSED_BY_DEFAULT constant missing or does not contain \"discarded\""
fi
# isCollapsed must consult COLLAPSED_BY_DEFAULT when no localStorage entry.
ISCOLLAPSED_BODY=$(awk '
  /^function isCollapsed\(/ { flag=1 }
  flag { print }
  flag && /^}$/ { exit }
' "$APP_JS")
if echo "$ISCOLLAPSED_BODY" | grep -qE 'COLLAPSED_BY_DEFAULT\.has\(col\)'; then
  pass "#677: isCollapsed consults COLLAPSED_BY_DEFAULT for absent-key fallback"
else
  fail "#677: isCollapsed does not consult COLLAPSED_BY_DEFAULT for fallback"
fi
# setCollapsed must write "0" (not removeItem) when expanding a
# default-collapsed column, so the user's expand choice survives reloads.
SETCOLLAPSED_BODY=$(awk '
  /^function setCollapsed\(/ { flag=1 }
  flag { print }
  flag && /^}$/ { exit }
' "$APP_JS")
if echo "$SETCOLLAPSED_BODY" | grep -qE 'COLLAPSED_BY_DEFAULT\.has\(col\)' \
   && echo "$SETCOLLAPSED_BODY" | grep -qE 'setItem\(.*, *"0"\)'; then
  pass "#677: setCollapsed persists explicit-expand of default-collapsed columns (writes \"0\")"
else
  fail "#677: setCollapsed does not persist explicit-expand of default-collapsed columns"
fi

# PLAN_COLUMN_LABELS must include Discarded.
if grep -q 'discarded: "Discarded"' "$APP_JS"; then
  pass "#677: PLAN_COLUMN_LABELS includes Discarded"
else
  fail "#677: PLAN_COLUMN_LABELS missing Discarded label"
fi

# Below-band renderBelowPanelBand must skip discarded for the issues kind
# (issues-side support deferred). Inspect the band body for the guard.
BAND_BODY=$(awk '
  /^function renderBelowPanelBand\(/ { flag=1 }
  flag { print }
  flag && /^}$/ { exit }
' "$APP_JS")
if echo "$BAND_BODY" | grep -qE 'c === "discarded" *&& *kind *!== *"plan"'; then
  pass "#677: renderBelowPanelBand skips discarded for issues (plans-only v1)"
else
  fail "#677: renderBelowPanelBand does not skip discarded for issues — would render empty placeholder"
fi

###############################################################################
# Block 4 — Phase 7: live write-back smoke (server already running)
###############################################################################

echo ""
echo "=== Phase 7 AC: live write-back smoke ==="

# Re-use the running server from Block 2 — same port, same MAIN_ROOT ($MR).

# AC: POST /api/queue WITHOUT Origin → 200 (Phase 5b: relaxed policy).
# Cross-origin still 403; that invariant is exercised by
# tests/test_zskills_monitor_csrf.sh and the wrong-Origin case in
# tests/test_zskills_monitor_server.sh.
CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
  -H 'Content-Type: application/json' \
  -d '{"plans":{"drafted":[],"reviewed":[],"ready":[]},"issues":{"triage":[],"ready":[]}}' \
  "http://127.0.0.1:$PORT/api/queue")
if [ "$CODE" = "200" ]; then
  pass "AC: POST /api/queue without Origin → 200 (relaxed in Phase 5b)"
else
  fail "AC: POST /api/queue no-origin → $CODE (expected 200 per Phase 5b)"
fi

# AC: POST /api/queue WITH valid Origin → 200 + state file written.
STATE_FILE="$MR/.zskills/monitor-state.json"
rm -f "$STATE_FILE"
CODE=$(curl -s -o "$MR/post.body" -w '%{http_code}' -X POST \
  -H "Origin: http://127.0.0.1:$PORT" \
  -H 'Content-Type: application/json' \
  -d '{"default_mode":"phase","plans":{"drafted":[{"slug":"ui-fixture-plan"}],"reviewed":[],"ready":[]},"issues":{"triage":[],"ready":[]}}' \
  "http://127.0.0.1:$PORT/api/queue")
if [ "$CODE" = "200" ]; then
  pass "AC: POST /api/queue with valid Origin → 200"
else
  fail "AC: POST /api/queue valid → $CODE (body=$(head -c 200 "$MR/post.body"))"
fi
if [ -f "$STATE_FILE" ] && grep -q '"ui-fixture-plan"' "$STATE_FILE"; then
  pass "AC: monitor-state.json updated by POST"
else
  fail "AC: monitor-state.json not updated"
fi

# AC: default_mode flips on POST.
DM_BEFORE=$(grep -E '"default_mode"' "$STATE_FILE" | head -1)
curl -s -o /dev/null -X POST \
  -H "Origin: http://127.0.0.1:$PORT" \
  -H 'Content-Type: application/json' \
  -d '{"default_mode":"finish","plans":{"drafted":[{"slug":"ui-fixture-plan"}],"reviewed":[],"ready":[]},"issues":{"triage":[],"ready":[]}}' \
  "http://127.0.0.1:$PORT/api/queue"
DM_AFTER=$(grep -E '"default_mode"' "$STATE_FILE" | head -1)
if printf '%s' "$DM_AFTER" | grep -q '"finish"'; then
  pass "AC: default_mode flipped to finish via POST"
else
  fail "AC: default_mode did not flip (before=$DM_BEFORE after=$DM_AFTER)"
fi

# AC: per-row mode override persisted.
curl -s -o /dev/null -X POST \
  -H "Origin: http://127.0.0.1:$PORT" \
  -H 'Content-Type: application/json' \
  -d '{"plans":{"drafted":[],"reviewed":[],"ready":[{"slug":"ui-fixture-plan","mode":"finish"}]},"issues":{"triage":[],"ready":[]}}' \
  "http://127.0.0.1:$PORT/api/queue"
if grep -qE '"mode":[[:space:]]*"finish"' "$STATE_FILE"; then
  pass "AC: per-row mode override persisted"
else
  fail "AC: per-row mode override not persisted"
fi

# AC: invalid POST (unknown column) → 400 + state UNCHANGED.
HASH_BEFORE=$(cksum "$STATE_FILE" | awk '{print $1}')
CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
  -H "Origin: http://127.0.0.1:$PORT" \
  -H 'Content-Type: application/json' \
  -d '{"plans":{"drafted":[],"NOT_A_COLUMN":[],"reviewed":[],"ready":[]},"issues":{"triage":[],"ready":[]}}' \
  "http://127.0.0.1:$PORT/api/queue")
HASH_AFTER=$(cksum "$STATE_FILE" | awk '{print $1}')
if [ "$CODE" = "400" ] && [ "$HASH_BEFORE" = "$HASH_AFTER" ]; then
  pass "AC: invalid POST (unknown column) → 400, state unchanged"
else
  fail "AC: invalid POST: code=$CODE hash_changed=$([ "$HASH_BEFORE" = "$HASH_AFTER" ] && echo no || echo yes)"
fi

# AC: 100 consecutive POSTs leave state file as valid JSON.
for i in $(seq 1 100); do
  curl -s -o /dev/null -X POST \
    -H "Origin: http://127.0.0.1:$PORT" \
    -H 'Content-Type: application/json' \
    -d '{"plans":{"drafted":[{"slug":"ui-fixture-plan"}],"reviewed":[],"ready":[]},"issues":{"triage":[],"ready":[]}}' \
    "http://127.0.0.1:$PORT/api/queue"
done
if python3 -c "import json,sys; json.loads(open('$STATE_FILE').read()); print('ok')" >/dev/null 2>&1; then
  pass "AC: state file is valid JSON after 100 consecutive POSTs"
else
  fail "AC: state file invalid after 100 POSTs"
fi

# AC: 20 parallel POSTs all return 2xx, final file is valid JSON.
PAR_TMP="$MR/par-codes.txt"
: > "$PAR_TMP"
PAR_PIDS=""
for i in $(seq 1 20); do
  (curl -s -o /dev/null -w '%{http_code}\n' -X POST \
    -H "Origin: http://127.0.0.1:$PORT" \
    -H 'Content-Type: application/json' \
    -d "{\"plans\":{\"drafted\":[{\"slug\":\"ui-fixture-plan\"}],\"reviewed\":[],\"ready\":[]},\"issues\":{\"triage\":[$i],\"ready\":[]}}" \
    "http://127.0.0.1:$PORT/api/queue" >> "$PAR_TMP") &
  PAR_PIDS="$PAR_PIDS $!"
done
# Wait only for the curl children, not the long-running server PID.
for p in $PAR_PIDS; do wait "$p" || true; done
ANY_5XX=0
while read -r line; do
  case "$line" in
    5*) ANY_5XX=1 ;;
  esac
done < "$PAR_TMP"
if [ "$ANY_5XX" -eq 0 ]; then
  pass "AC: 20 parallel POSTs all without 5xx"
else
  fail "AC: at least one 5xx in 20 parallel POSTs"
fi
if python3 -c "import json,sys; json.loads(open('$STATE_FILE').read()); print('ok')" >/dev/null 2>&1; then
  pass "AC: state file valid JSON after 20 parallel POSTs"
else
  fail "AC: state file invalid after parallel POSTs"
fi

# AC: Two-tab last-write-wins. POST1 then POST2 sequentially with &.
curl -s -o /dev/null -X POST \
  -H "Origin: http://127.0.0.1:$PORT" \
  -H 'Content-Type: application/json' \
  -d '{"plans":{"drafted":[{"slug":"a-plan"},{"slug":"b-plan"},{"slug":"c-plan"}],"reviewed":[],"ready":[]},"issues":{"triage":[],"ready":[]}}' \
  "http://127.0.0.1:$PORT/api/queue" &
P1=$!
curl -s -o /dev/null -X POST \
  -H "Origin: http://127.0.0.1:$PORT" \
  -H 'Content-Type: application/json' \
  -d '{"plans":{"drafted":[{"slug":"c-plan"},{"slug":"b-plan"},{"slug":"a-plan"}],"reviewed":[],"ready":[]},"issues":{"triage":[],"ready":[]}}' \
  "http://127.0.0.1:$PORT/api/queue" &
P2=$!
wait "$P1" "$P2"
# Final state must match exactly one payload (last-writer-wins). Both
# orderings include the same three slugs, so verify the file is parseable
# and the slug list is exactly {a-plan, b-plan, c-plan} in some order.
if python3 -c "import json; d=json.loads(open('$STATE_FILE').read()); slugs=[e['slug'] for e in d['plans']['drafted']]; assert sorted(slugs)==['a-plan','b-plan','c-plan'], slugs; print('ok')" >/dev/null 2>&1; then
  pass "AC: two-tab last-write-wins: final state matches one full payload"
else
  fail "AC: two-tab race produced half-merged state"
fi

###############################################################################
# Block — Issue #675: Section-nav pill strip (static-grep)
###############################################################################

echo ""
echo "=== Issue #675 AC: section-nav pill strip ==="

# 675-1: buildSectionNavStrip helper defined in app.js.
if grep -qE 'function buildSectionNavStrip\(' "$APP_JS"; then
  pass "#675: buildSectionNavStrip helper defined"
else
  fail "#675: buildSectionNavStrip helper missing"
fi

# 675-2: buildNavPill helper defined (constructs each pill button).
if grep -qE 'function buildNavPill\(' "$APP_JS"; then
  pass "#675: buildNavPill helper defined"
else
  fail "#675: buildNavPill helper missing"
fi

# 675-3: section-nav-strip class emitted with data-kind attribute.
if grep -qE 'cls: "section-nav-strip"' "$APP_JS"; then
  pass "#675: .section-nav-strip element class emitted"
else
  fail "#675: .section-nav-strip element class missing"
fi

# 675-4: renderPlans invokes buildSectionNavStrip("plan", ...).
RENDER_PLANS_BODY=$(awk '
  /^function renderPlans\(/ { flag=1 }
  flag { print }
  flag && /^}$/ { exit }
' "$APP_JS")
if echo "$RENDER_PLANS_BODY" | grep -qE 'buildSectionNavStrip\("plan"'; then
  pass "#675: renderPlans calls buildSectionNavStrip for plans"
else
  fail "#675: renderPlans does not invoke buildSectionNavStrip"
fi

# 675-5: renderIssues invokes buildSectionNavStrip("issue", ...).
RENDER_ISSUES_BODY=$(awk '
  /^function renderIssues\(/ { flag=1 }
  flag { print }
  flag && /^}$/ { exit }
' "$APP_JS")
if echo "$RENDER_ISSUES_BODY" | grep -qE 'buildSectionNavStrip\("issue"'; then
  pass "#675: renderIssues calls buildSectionNavStrip for issues"
else
  fail "#675: renderIssues does not invoke buildSectionNavStrip"
fi

# 675-6: Pills use scrollIntoView for smooth scrolling.
if grep -qE 'scrollIntoView.*behavior.*smooth' "$APP_JS"; then
  pass "#675: scrollIntoView({ behavior: 'smooth' }) wired"
else
  fail "#675: scrollIntoView smooth behavior missing"
fi

# 675-7: Click handler expands collapsed column before scrolling.
if grep -qE 'section-nav-pill' "$APP_JS" \
   && grep -qE 'isCollapsed.*kind.*col' "$APP_JS" \
   && grep -qE 'setCollapsed.*kind.*col.*false' "$APP_JS"; then
  pass "#675: section-nav-pill handler expands collapsed sections before scrolling"
else
  fail "#675: section-nav-pill expand-before-scroll coordination missing"
fi

# 675-8: CSS for .section-nav-strip defined.
if grep -qE '\.section-nav-strip' "$APP_CSS"; then
  pass "#675: .section-nav-strip CSS rule defined"
else
  fail "#675: .section-nav-strip CSS rule missing"
fi

# 675-9: CSS for .section-nav-pill defined.
if grep -qE '\.section-nav-pill' "$APP_CSS"; then
  pass "#675: .section-nav-pill CSS rule defined"
else
  fail "#675: .section-nav-pill CSS rule missing"
fi

# 675-10: Sticky positioning for the strip.
if grep -A5 '\.section-nav-strip' "$APP_CSS" | grep -q 'sticky'; then
  pass "#675: .section-nav-strip uses position: sticky"
else
  fail "#675: .section-nav-strip missing sticky positioning"
fi

###############################################################################
# Block — Issue #676: Completed-window dropdown (static-grep)
###############################################################################

echo ""
echo "=== Issue #676 AC: completed-window dropdown ==="

# 676-1: COMPLETED_WINDOW_KEY_PREFIX localStorage key defined.
if grep -qE 'COMPLETED_WINDOW_KEY_PREFIX\s*=\s*"zskills:dashboard:completed-window:"' "$APP_JS"; then
  pass "#676: COMPLETED_WINDOW_KEY_PREFIX constant defined"
else
  fail "#676: COMPLETED_WINDOW_KEY_PREFIX constant missing"
fi

# 676-2: getCompletedWindow + setCompletedWindow helpers defined.
if grep -qE 'function getCompletedWindow\(' "$APP_JS" \
   && grep -qE 'function setCompletedWindow\(' "$APP_JS"; then
  pass "#676: getCompletedWindow + setCompletedWindow helpers defined"
else
  fail "#676: completed-window localStorage helpers missing"
fi

# 676-3: completed-window-select dropdown emitted in renderBelowPanelBand.
BAND_BODY=$(awk '
  /^function renderBelowPanelBand\(/ { flag=1 }
  flag { print }
  flag && /^}$/ { exit }
' "$APP_JS")
if echo "$BAND_BODY" | grep -qE 'completed-window-select'; then
  pass "#676: completed-window dropdown injected in renderBelowPanelBand"
else
  fail "#676: completed-window dropdown missing from renderBelowPanelBand"
fi

# 676-4: Dropdown options include 7d, 14d, 30d, 90d, All.
if grep -qE '"7d"' "$APP_JS" \
   && grep -qE '"14d"' "$APP_JS" \
   && grep -qE '"30d"' "$APP_JS" \
   && grep -qE '"90d"' "$APP_JS" \
   && grep -qE '"All"' "$APP_JS"; then
  pass "#676: dropdown options 7d/14d/30d/90d/All present"
else
  fail "#676: dropdown options incomplete"
fi

# 676-5: Change handler wired for completed-window-select.
if grep -qE 'addEventListener.*"change"' "$APP_JS" \
   && grep -qE '\.completed-window-select' "$APP_JS"; then
  pass "#676: change event handler wired for completed-window dropdown"
else
  fail "#676: change handler for dropdown missing"
fi

# 676-6: configCompletedDays updated from snap.config.
if grep -qE 'snap\.config\.dashboard_completed_days' "$APP_JS"; then
  pass "#676: configCompletedDays updated from snapshot config"
else
  fail "#676: configCompletedDays not wired to snapshot config"
fi

# 676-7: deepCloneQueues applies client-side window filter for plans.
DEEPCLONE_BODY=$(awk '
  /^function deepCloneQueues\(/ { flag=1 }
  flag { print }
  flag && /^}$/ { exit }
' "$APP_JS")
if echo "$DEEPCLONE_BODY" | grep -qE 'getCompletedWindow.*plan' \
   && echo "$DEEPCLONE_BODY" | grep -qE 'planCutoff'; then
  pass "#676: deepCloneQueues applies client-side window filter for plans"
else
  fail "#676: client-side plan window filter missing from deepCloneQueues"
fi

# 676-8: deepCloneQueues applies client-side window filter for issues.
if echo "$DEEPCLONE_BODY" | grep -qE 'getCompletedWindow.*issue' \
   && echo "$DEEPCLONE_BODY" | grep -qE 'issueCutoff'; then
  pass "#676: deepCloneQueues applies client-side window filter for issues"
else
  fail "#676: client-side issue window filter missing from deepCloneQueues"
fi

# 676-9: completed-window preference participates in fingerprint.
FPP_BODY=$(awk '
  /^function fingerprintPlans\(/ { flag=1 }
  flag { print }
  flag && /^}$/ { exit }
' "$APP_JS")
FPI_BODY=$(awk '
  /^function fingerprintIssues\(/ { flag=1 }
  flag { print }
  flag && /^}$/ { exit }
' "$APP_JS")
if echo "$FPP_BODY" | grep -qE 'getCompletedWindow|_gcw' \
   && echo "$FPI_BODY" | grep -qE 'getCompletedWindow|_gcwI'; then
  pass "#676: completed-window preference participates in fingerprints"
else
  fail "#676: fingerprint does not include completed-window preference"
fi

# 676-10: CSS for .completed-window-select defined.
if grep -qE '\.completed-window-select' "$APP_CSS"; then
  pass "#676: .completed-window-select CSS rule defined"
else
  fail "#676: .completed-window-select CSS rule missing"
fi

# 676-11: Server-side collect.py exposes config.dashboard_completed_days in snapshot.
if grep -qE 'dashboard_completed_days.*window_days|"dashboard_completed_days"' \
   "$REPO_ROOT/skills/zskills-dashboard/scripts/zskills_monitor/collect.py"; then
  pass "#676: collect.py exposes dashboard_completed_days in snapshot config"
else
  fail "#676: collect.py missing dashboard_completed_days in snapshot"
fi

###############################################################################
# Issue #700 — Dashboard UI polish: collapse toggle, collapsed preview,
# move-all button styling
###############################################################################

echo ""
echo "=== Issue #700: collapse toggle, collapsed preview strip, move-all styling ==="

# 700-1..5: Collapse toggle styling — shared base class .column-head-btn
# carries padding, border-radius, transition, and hover background (UI-polish
# round 2 unified column-header buttons into a single base).  The toggle also
# has its own selector for margin-left + width.
if grep -qE '\.column-head-btn\b' "$APP_CSS" \
   && awk '/\.column-head-btn[[:space:]]*\{/{flag=1} flag && /padding:[[:space:]]*3px 7px/{found=1; exit} flag && /\}/{flag=0} END{exit !found}' "$APP_CSS"; then
  pass "#700: column-head-btn base has padding 3px 7px"
else
  fail "#700: column-head-btn base padding missing"
fi

if awk '/\.column-head-btn[[:space:]]*\{/{flag=1} flag && /border-radius:[[:space:]]*6px/{found=1; exit} flag && /\}/{flag=0} END{exit !found}' "$APP_CSS"; then
  pass "#700: column-head-btn border-radius is 6px"
else
  fail "#700: column-head-btn border-radius missing"
fi

if awk '/\.column-head-btn:hover/{flag=1} flag && /background:/{found=1; exit} flag && /\}/{flag=0} END{exit !found}' "$APP_CSS"; then
  pass "#700: column-head-btn hover has background"
else
  fail "#700: column-head-btn hover missing background"
fi

if awk '/\.column-head-btn[[:space:]]*\{/{flag=1} flag && /transition:/{found=1; exit} flag && /\}/{flag=0} END{exit !found}' "$APP_CSS"; then
  pass "#700: column-head-btn has CSS transition"
else
  fail "#700: column-head-btn missing CSS transition"
fi

# Collapse toggle retains its own selector for margin-left + width override.
if grep -qE '\.column-collapse-toggle\b' "$APP_CSS" \
   && awk '/\.column-collapse-toggle[[:space:]]*\{/{flag=1} flag && /width:[[:space:]]*28px/{found=1; exit} flag && /\}/{flag=0} END{exit !found}' "$APP_CSS"; then
  pass "#700: collapse toggle retains width: 28px"
else
  fail "#700: collapse toggle width override missing"
fi

# 700-6: Collapsed-summary CSS rule defined.
if grep -qE '\.collapsed-summary\b' "$APP_CSS"; then
  pass "#700: .collapsed-summary CSS rule defined"
else
  fail "#700: .collapsed-summary CSS rule missing"
fi

# 700-7: Collapsed-summary preview row CSS sub-rule defined. The summary
# renders one mini-card row (id + title) per previewed item.
if grep -qE '\.collapsed-summary-row' "$APP_CSS"; then
  pass "#700: .collapsed-summary-row CSS rule defined"
else
  fail "#700: .collapsed-summary-row CSS rule missing"
fi

# 700-8: Collapsed-summary per-row title CSS sub-rule defined, plus the
# bottom-pinned aggregate footer that summarizes chip counts.
if grep -qE '\.collapsed-summary-title\b' "$APP_CSS" && grep -qE '\.collapsed-summary-footer' "$APP_CSS"; then
  pass "#700: .collapsed-summary-title + .collapsed-summary-footer CSS rules defined"
else
  fail "#700: .collapsed-summary-title / .collapsed-summary-footer CSS rule missing"
fi

# 700-9: applyCollapseStateToColumn builds a collapsed-summary element when
# the column is collapsed. Verify by grepping for the class in the JS body.
COLLAPSE_BODY=$(awk '
  /^function applyCollapseStateToColumn\(/ { flag=1 }
  flag { print }
  flag && /^}$/ { exit }
' "$APP_JS")
if echo "$COLLAPSE_BODY" | grep -qE 'collapsed-summary'; then
  pass "#700: applyCollapseStateToColumn renders collapsed-summary element"
else
  fail "#700: applyCollapseStateToColumn does not render collapsed-summary"
fi

# 700-10: The collapsed-summary uses card titles from the hidden dropzone.
if echo "$COLLAPSE_BODY" | grep -qE 'card-title.*card-title-link|\.card-title-link'; then
  pass "#700: collapsed-summary extracts card titles from dropzone"
else
  fail "#700: collapsed-summary does not extract card titles"
fi

# 700-11: The collapsed-summary is removed when expanded.
if echo "$COLLAPSE_BODY" | grep -qE 'removeChild.*existingSummary|existingSummary.*removeChild'; then
  pass "#700: collapsed-summary removed on expand"
else
  fail "#700: collapsed-summary not removed on expand"
fi

# 700-12: Collapsed-summary carries data-action="column-collapse-toggle" so
# clicking it expands the column (reuses the existing delegated handler).
if echo "$COLLAPSE_BODY" | grep -qE '"data-action".*"column-collapse-toggle"'; then
  pass "#700: collapsed-summary is clickable (data-action=column-collapse-toggle)"
else
  fail "#700: collapsed-summary missing data-action for click-to-expand"
fi

# 700-13..16: Move-all button inherits from .column-head-btn base (UI-polish
# round 2).  The JS assigns cls: "column-head-btn move-all-btn".  All styling
# comes from the base; no dedicated .move-all-btn {} block needed.
if grep -qE 'cls:\s*"column-head-btn move-all-btn"' "$APP_JS"; then
  pass "#700: move-all-btn carries column-head-btn base class in JS"
else
  fail "#700: move-all-btn missing column-head-btn base class in JS"
fi

# Base provides border-radius, padding, transition, background.
if awk '/\.column-head-btn[[:space:]]*\{/{flag=1} flag && /background:.*--surface2/{found=1; exit} flag && /\}/{flag=0} END{exit !found}' "$APP_CSS"; then
  pass "#700: column-head-btn background is var(--surface2)"
else
  fail "#700: column-head-btn background is NOT var(--surface2)"
fi

echo ""
echo "=== Branches panel: 4 accurate buckets + protected shield ==="

# BRANCH_SECTIONS must enumerate the 4 buckets in order.
if grep -qE 'var BRANCH_SECTIONS = \["active", "landed", "local", "remote-only"\]' "$APP_JS"; then
  pass "branches: BRANCH_SECTIONS = active/landed/local/remote-only"
else
  fail "branches: BRANCH_SECTIONS does not enumerate the 4 buckets"
fi

# Label map must carry all 4 labels, including the honest renames.
if grep -qE '"local": "Local \(no worktree\)"' "$APP_JS" \
   && grep -qE '"remote-only": "Remote only"' "$APP_JS" \
   && grep -qE '"active": "Active"' "$APP_JS" \
   && grep -qE '"landed": "Landed"' "$APP_JS"; then
  pass "branches: BRANCH_SECTION_LABELS carries all 4 bucket labels"
else
  fail "branches: BRANCH_SECTION_LABELS missing one of the 4 bucket labels"
fi

# classifyBranch must resolve all 4 buckets: worktree+landed→landed,
# worktree→active, locality==remote-only→remote-only, else→local.
CLASSIFY_BODY=$(awk '
  /^function classifyBranch\(/ { flag=1 }
  flag { print }
  flag && /^}$/ { exit }
' "$APP_JS")
if echo "$CLASSIFY_BODY" | grep -qE 'w && w\.landed.*return "landed"' \
   && echo "$CLASSIFY_BODY" | grep -qE 'if \(w\) return "active"' \
   && echo "$CLASSIFY_BODY" | grep -qE 'b\.locality === "remote-only".*return "remote-only"' \
   && echo "$CLASSIFY_BODY" | grep -qE 'return "local"'; then
  pass "branches: classifyBranch resolves active/landed/local/remote-only"
else
  fail "branches: classifyBranch missing one of the 4 bucket resolutions: got '$CLASSIFY_BODY'"
fi

# Both large/low-action buckets (local + remote-only) collapse by default.
if grep -qE 'COLLAPSED_BY_DEFAULT *= *new Set\(\[.*"branch-local".*"branch-remote-only"' "$APP_JS"; then
  pass "branches: local + remote-only buckets collapsed by default"
else
  fail "branches: COLLAPSED_BY_DEFAULT missing branch-local / branch-remote-only"
fi

# renderBranches groups object must seed all 4 buckets.
if grep -qE 'var groups = \{ "active": \[\], "landed": \[\], "local": \[\], "remote-only": \[\] \}' "$APP_JS"; then
  pass "branches: renderBranches groups object seeds all 4 buckets"
else
  fail "branches: renderBranches groups object does not seed all 4 buckets"
fi

# Protected shield: a branch card whose `protected` field is true renders a
# shield indicator with a descriptive title (config protection, not GitHub).
BRANCHCARD_BODY=$(awk '
  /^function buildBranchCard\(/ { flag=1 }
  flag { print }
  flag && /^}$/ { exit }
' "$APP_JS")
if echo "$BRANCHCARD_BODY" | grep -qE 'b\.protected' \
   && echo "$BRANCHCARD_BODY" | grep -q 'branch-protected-shield' \
   && echo "$BRANCHCARD_BODY" | grep -qi 'cleanup.protected_branches'; then
  pass "branches: protected shield rendered on protected cards (config-protection labeled)"
else
  fail "branches: buildBranchCard missing protected-shield rendering: got '$BRANCHCARD_BODY'"
fi

# Issue #776 — display normalization: the worktree-row landed pill renders
# stored `full` (cherry-pick landing) as "LANDED" text, so it reads the same
# as the PR-flow `landed`. This is DISPLAY-ONLY — landedPillClass color
# mapping and the stored marker status are unchanged. `partial` keeps its own
# label and must NOT be collapsed.
if echo "$BRANCHCARD_BODY" | grep -qE 'status === "full" \? "landed" : status'; then
  pass "branches: landed pill displays stored 'full' as 'landed' text (#776)"
else
  fail "branches: buildBranchCard does not normalize 'full' -> 'landed' display text (#776): got '$BRANCHCARD_BODY'"
fi
# Guard: the display normalization must NOT collapse `partial` into landed —
# `partial` is a distinct state that keeps its own label (rendered uppercase
# as PARTIAL via the .pill text-transform).
if echo "$BRANCHCARD_BODY" | grep -qE '=== "partial"'; then
  fail "branches: display logic must not special-case 'partial' (it keeps its own label) (#776): got '$BRANCHCARD_BODY'"
else
  pass "branches: 'partial' is not collapsed by the display normalization — keeps PARTIAL label (#776)"
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
