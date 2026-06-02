#!/bin/bash
# Tests for the run-status widget gates introduced by issue #930:
#
#   1. Stop button gate on trigger_configured: the scheduled-branch Stop
#      button renders unconditionally pre-fix and POSTs to /api/trigger
#      which 501s without dashboard.work_on_plans_trigger set. Post-fix,
#      Stop only renders when trigger_configured is true.
#
# (Per issue #988, the original Bug 1 — default-mode chip lock parity —
# is gone with the chip itself; renderDefaultMode / setDefaultMode were
# removed from app.js. The Stop-gate + showToast cases below remain.)
#
# Run from repo root: bash tests/test-dashboard-run-status-locks.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATIC_DIR="$REPO_ROOT/skills/zskills-dashboard/scripts/zskills_monitor/static"
APP_JS="$STATIC_DIR/app.js"

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

if [ ! -f "$APP_JS" ]; then
  fail "static/app.js exists at expected path"
  print_summary_and_exit
fi

if ! command -v node >/dev/null 2>&1; then
  skip "node not available — DOM tests skipped"
  print_summary_and_exit
fi

# ---------------------------------------------------------------------------
# Stop-button gate on trigger_configured (DOM-stubbed).
# (Issue #988 dropped the default-mode chip; the prior chip-lock cases
# A-F are gone with the chip itself. Stop-gate + showToast remain below.)
# ---------------------------------------------------------------------------

NODE_OUT=$(APP_JS_PATH="$APP_JS" node - <<'NODE'
const fs = require("fs");
const src = fs.readFileSync(process.env.APP_JS_PATH, "utf8");

function extractBlock(text, startRe, endMarker) {
  const m = text.match(startRe);
  if (!m) throw new Error("start pattern not found: " + startRe);
  const startIdx = m.index;
  const tail = text.slice(startIdx);
  const endIdx = tail.indexOf(endMarker);
  if (endIdx < 0) throw new Error("end marker not found: " + endMarker);
  return tail.slice(0, endIdx + endMarker.length);
}

// Real functions under test, lifted verbatim from app.js.
const renderRunStatusBlk = extractBlock(src, /\nfunction renderRunStatus\(ws\)/, "\n}\n");
const elBlock            = extractBlock(src, /\nfunction el\(tag, opts\)/, "\n}\n");

// Minimal DOM: run-status container only (chip-related nodes dropped per #988).
function makeNode(id, tag) {
  return {
    id,
    tagName: (tag || "div").toUpperCase(),
    className: "",
    textContent: "",
    innerHTML: "",
    attrs: {},
    children: [],
    parent: null,
    hidden: false,
    style: {},
    classes: new Set(),
    setAttribute(k, v) { this.attrs[k] = String(v); },
    getAttribute(k) { return this.attrs[k] == null ? null : this.attrs[k]; },
    removeAttribute(k) { delete this.attrs[k]; },
    appendChild(c) { c.parent = this; this.children.push(c); return c; },
    closest() { return null; },
    addEventListener() {},
    // DOM `firstChild` getter — surfaces children[0] so production-code
    // checks like `if (!root.firstChild)` (issue #995's empty-render
    // guard) behave like a real browser instead of always being truthy.
    get firstChild() { return this.children.length > 0 ? this.children[0] : null; },
    classList: {
      _set: null,
      add(c) { this._set.add(c); },
      remove(c) { this._set.delete(c); },
      contains(c) { return this._set.has(c); },
    },
  };
}

const nodes = {
  "run-status": makeNode("run-status", "div"),
};
for (const k of Object.keys(nodes)) {
  nodes[k].classList._set = nodes[k].classes;
}
const $stub = (id) => (id in nodes ? nodes[id] : null);

const document = {
  createElement(tag) { return makeNode(null, tag); },
};

const harness = `
let lastWorkState = null;

if (typeof navigator === "undefined") globalThis.navigator = {};
if (!navigator.clipboard) navigator.clipboard = { writeText: function() { return Promise.resolve(); } };
var SVG_ICONS = { copy: "" };

function clear(node) { node.children = []; node.classes.clear(); }
function showToast() {}
function formatLocalTime(s) { return s || "?"; }
function relativeTime(s) { return s || "?"; }

${elBlock}

${renderRunStatusBlk}

globalThis.__renderRunStatus = renderRunStatus;
`;

(new Function("document", "$", "globalThis", harness))(document, $stub, globalThis);

const renderRunStatus = globalThis.__renderRunStatus;

function expect(actual, expected, label) {
  const aStr = JSON.stringify(actual);
  const eStr = JSON.stringify(expected);
  if (aStr !== eStr) {
    console.log("FAIL " + label + " (got " + aStr + ", expected " + eStr + ")");
    process.exitCode = 1;
  } else {
    console.log("OK " + label);
  }
}
function expectTrue(actual, label) {
  if (actual) console.log("OK " + label);
  else { console.log("FAIL " + label + " (got falsy " + JSON.stringify(actual) + ")"); process.exitCode = 1; }
}

function resetNodes() {
  for (const k of Object.keys(nodes)) {
    nodes[k].attrs = {};
    nodes[k].children = [];
    nodes[k].classes.clear();
    nodes[k].className = "";
    nodes[k].hidden = false;
  }
}

function findByClass(root, cls) {
  if ((root.className || "").split(/\s+/).indexOf(cls) >= 0) return root;
  for (const c of (root.children || [])) {
    const hit = findByClass(c, cls);
    if (hit) return hit;
  }
  return null;
}

(async () => {
  const root = nodes["run-status"];

  // -----------------------------------------------------------------------
  // Stop-button gate on trigger_configured.
  // -----------------------------------------------------------------------

  // Case G: state==="scheduled", trigger_configured===false — NO Stop button.
  resetNodes();
  renderRunStatus({
    state: "scheduled",
    schedule: "every 1h",
    next_fire_at: "2026-06-01T12:00:00+00:00",
    trigger_configured: false,
  });
  expect(findByClass(root, "run-stop-btn"), null,
    "scheduled + trigger_configured=false: Stop button NOT rendered");

  // Case H: state==="scheduled", trigger_configured===true — Stop button DOES render.
  resetNodes();
  renderRunStatus({
    state: "scheduled",
    schedule: "every 1h",
    next_fire_at: "2026-06-01T12:00:00+00:00",
    trigger_configured: true,
  });
  const stopBtn = findByClass(root, "run-stop-btn");
  expectTrue(stopBtn, "scheduled + trigger_configured=true: Stop button renders");
  if (stopBtn) {
    expect(stopBtn.getAttribute("data-action"), "run-stop",
      "scheduled + trigger_configured=true: Stop wired to data-action=run-stop");
  }

  // Case I: state==="scheduled", trigger_configured omitted (falsy) — NO Stop button.
  resetNodes();
  renderRunStatus({
    state: "scheduled",
    schedule: "every 1h",
    next_fire_at: "2026-06-01T12:00:00+00:00",
  });
  expect(findByClass(root, "run-stop-btn"), null,
    "scheduled + trigger_configured omitted: Stop button NOT rendered (defaults to false)");

  // -----------------------------------------------------------------------
  // Issue #995 — phantom-pill hide guard.
  // The empty .run-status container would otherwise still draw a visible
  // border + padding "pill" in the demo's idle + no-trigger + no-warning
  // state. renderRunStatus must set root.hidden=true when no children
  // were appended, and root.hidden=false on every live render path.
  // -----------------------------------------------------------------------

  // Case M: state==="idle", trigger_configured=false, no warning —
  //   NO children appended AND root.hidden===true.
  resetNodes();
  renderRunStatus({
    state: "idle",
    trigger_configured: false,
  });
  expect(root.children.length, 0,
    "idle + no trigger + no warning: no children appended");
  expect(root.hidden, true,
    "idle + no trigger + no warning: root.hidden=true (phantom pill suppressed)");

  // Case N: state==="idle", trigger_configured=true — Run controls
  //   ARE rendered AND root.hidden===false.
  resetNodes();
  renderRunStatus({
    state: "idle",
    trigger_configured: true,
  });
  expectTrue(findByClass(root, "run-btn"),
    "idle + trigger_configured=true: ▶ Run top N button rendered");
  expect(root.hidden, false,
    "idle + trigger_configured=true: root.hidden=false (pill visible)");

  // Case O: state==="idle" + warning present, no trigger — warning text
  //   IS rendered AND root.hidden===false.
  resetNodes();
  renderRunStatus({
    state: "idle",
    trigger_configured: false,
    warning: "Background process exited unexpectedly",
  });
  expectTrue(findByClass(root, "run-text"),
    "idle + warning: warning text rendered");
  expect(root.hidden, false,
    "idle + warning: root.hidden=false (pill visible)");

  // Case P: state==="scheduled" — pill always renders, root.hidden===false.
  resetNodes();
  renderRunStatus({
    state: "scheduled",
    schedule: "every 1h",
    next_fire_at: "2026-06-01T12:00:00+00:00",
    trigger_configured: true,
  });
  expect(root.hidden, false,
    "scheduled: root.hidden=false (pill visible)");

  // Case Q: state==="sprint" — pill always renders, root.hidden===false.
  resetNodes();
  renderRunStatus({
    state: "sprint",
    progress: { done: 1, total: 3, current_slug: "PLAN_X" },
  });
  expect(root.hidden, false,
    "sprint: root.hidden=false (pill visible)");

  // Case R: state==="stale-scheduled" — pill always renders, root.hidden===false.
  resetNodes();
  renderRunStatus({
    state: "stale-scheduled",
  });
  expect(root.hidden, false,
    "stale-scheduled: root.hidden=false (pill visible)");

  // Case S: state==="stale-sprint" — pill always renders, root.hidden===false.
  resetNodes();
  renderRunStatus({
    state: "stale-sprint",
    updated_at: "2026-06-01T00:00:00+00:00",
  });
  expect(root.hidden, false,
    "stale-sprint: root.hidden=false (pill visible)");

  // Case T: transition from idle-empty (hidden=true) → scheduled — the
  //   second render must unhide. This is the regression case the
  //   top-of-function `root.hidden = false` guards against.
  resetNodes();
  renderRunStatus({ state: "idle", trigger_configured: false });
  expect(root.hidden, true, "transition setup: idle-empty hidden=true");
  renderRunStatus({
    state: "scheduled",
    schedule: "every 1h",
    next_fire_at: "2026-06-01T12:00:00+00:00",
    trigger_configured: true,
  });
  expect(root.hidden, false,
    "transition: idle-empty → scheduled unhides root (no phantom invisible pill)");
})();
NODE
)
NODE_RC=$?

echo "$NODE_OUT"

while IFS= read -r line; do
  case "$line" in
    OK\ *) pass "${line#OK }" ;;
    FAIL\ *) fail "${line#FAIL }" ;;
  esac
done <<< "$NODE_OUT"

if [ "$NODE_RC" != "0" ] && [ "$FAIL_COUNT" -eq 0 ]; then
  fail "node harness exited non-zero ($NODE_RC) with no per-test failures parsed"
fi

# ---------------------------------------------------------------------------
# Issue #940 — showToast optional action-button arg (DOM-stubbed).
#
# The locked-chip toast now passes a 3rd arg {actionLabel, onAction} so the
# user can recover from an externally-killed cron via the existing
# /api/work-state/reset endpoint. Verify both backward-compat (2-arg) and
# the new 3-arg form.
# ---------------------------------------------------------------------------

TOAST_NODE_OUT=$(APP_JS_PATH="$APP_JS" node - <<'NODE'
const fs = require("fs");
const src = fs.readFileSync(process.env.APP_JS_PATH, "utf8");

function extractBlock(text, startRe, endMarker) {
  const m = text.match(startRe);
  if (!m) throw new Error("start pattern not found: " + startRe);
  const startIdx = m.index;
  const tail = text.slice(startIdx);
  const endIdx = tail.indexOf(endMarker);
  if (endIdx < 0) throw new Error("end marker not found: " + endMarker);
  return tail.slice(0, endIdx + endMarker.length);
}

const showToastBlk = extractBlock(src, /\nfunction showToast\(message, kind, opts\)/, "\n}\n");
const elBlock      = extractBlock(src, /\nfunction el\(tag, opts\)/, "\n}\n");

function makeNode(id, tag) {
  return {
    id,
    tagName: (tag || "div").toUpperCase(),
    className: "",
    textContent: "",
    innerHTML: "",
    attrs: {},
    children: [],
    parent: null,
    _listeners: {},
    setAttribute(k, v) { this.attrs[k] = String(v); },
    getAttribute(k) { return this.attrs[k] == null ? null : this.attrs[k]; },
    removeAttribute(k) { delete this.attrs[k]; },
    appendChild(c) { c.parent = this; this.children.push(c); return c; },
    removeChild(c) {
      const i = this.children.indexOf(c);
      if (i >= 0) { this.children.splice(i, 1); c.parent = null; }
      return c;
    },
    get parentNode() { return this.parent; },
    addEventListener(ev, fn) {
      if (!this._listeners[ev]) this._listeners[ev] = [];
      this._listeners[ev].push(fn);
    },
    dispatch(ev) {
      const fns = this._listeners[ev] || [];
      const results = [];
      for (const fn of fns) results.push(fn());
      return Promise.all(results);
    },
  };
}

const toastRegion = makeNode("toast-region", "div");
const nodes = { "toast-region": toastRegion };
const $stub = (id) => (id in nodes ? nodes[id] : null);
const document = { createElement(tag) { return makeNode(null, tag); } };

// Stub setTimeout (no-op so our DOM isn't auto-cleared mid-assert).
const setTimeoutStub = () => 0;

const harness = `
${elBlock}
${showToastBlk}
globalThis.__showToast = showToast;
`;

(new Function("document", "$", "setTimeout", "globalThis", harness))(
  document, $stub, setTimeoutStub, globalThis
);

const showToast = globalThis.__showToast;

function expect(actual, expected, label) {
  const aStr = JSON.stringify(actual);
  const eStr = JSON.stringify(expected);
  if (aStr !== eStr) {
    console.log("FAIL " + label + " (got " + aStr + ", expected " + eStr + ")");
    process.exitCode = 1;
  } else {
    console.log("OK " + label);
  }
}
function expectTrue(actual, label) {
  if (actual) console.log("OK " + label);
  else { console.log("FAIL " + label + " (got falsy " + JSON.stringify(actual) + ")"); process.exitCode = 1; }
}

function findByClass(root, cls) {
  if ((root.className || "").split(/\s+/).indexOf(cls) >= 0) return root;
  for (const c of (root.children || [])) {
    const hit = findByClass(c, cls);
    if (hit) return hit;
  }
  return null;
}

function resetRegion() { toastRegion.children = []; }

(async () => {
  // Case J: 2-arg showToast does NOT render an action button (back-compat).
  resetRegion();
  showToast("hello", "info");
  expect(toastRegion.children.length, 1, "2-arg showToast: one toast appended");
  const toast2 = toastRegion.children[0];
  expect(findByClass(toast2, "toast-action"), null,
    "2-arg showToast: no toast-action button rendered");
  expectTrue(findByClass(toast2, "toast-close"),
    "2-arg showToast: close button still rendered");

  // Case K: 3-arg showToast DOES render a button, click invokes onAction.
  resetRegion();
  let onActionCalls = 0;
  showToast("locked", "info", {
    actionLabel: "Force unlock",
    onAction: async () => { onActionCalls += 1; },
  });
  expect(toastRegion.children.length, 1, "3-arg showToast: one toast appended");
  const toast3 = toastRegion.children[0];
  const actionBtn = findByClass(toast3, "toast-action");
  expectTrue(actionBtn, "3-arg showToast: toast-action button rendered");
  if (actionBtn) {
    expect(actionBtn.tagName, "BUTTON",
      "3-arg showToast: action element is a <button>");
    expect(actionBtn.textContent, "Force unlock",
      "3-arg showToast: action button label is 'Force unlock'");
    expect(actionBtn.getAttribute("type"), "button",
      "3-arg showToast: action button has type=button");
  }
  // Simulate click and let the async handler complete.
  if (actionBtn) await actionBtn.dispatch("click");
  expect(onActionCalls, 1, "3-arg showToast: clicking action invokes onAction once");
  // After click, the toast is dismissed (removed from region).
  expect(toastRegion.children.length, 0,
    "3-arg showToast: toast removed from region after action click");

  // Case L: 3-arg showToast with only actionLabel (no onAction) — no button.
  resetRegion();
  showToast("msg", "info", { actionLabel: "Nope" });
  const toast4 = toastRegion.children[0];
  expect(findByClass(toast4, "toast-action"), null,
    "3-arg showToast missing onAction: action button NOT rendered");
})();
NODE
)
TOAST_NODE_RC=$?

echo "$TOAST_NODE_OUT"

while IFS= read -r line; do
  case "$line" in
    OK\ *) pass "${line#OK }" ;;
    FAIL\ *) fail "${line#FAIL }" ;;
  esac
done <<< "$TOAST_NODE_OUT"

if [ "$TOAST_NODE_RC" != "0" ] && [ "$FAIL_COUNT" -eq 0 ]; then
  fail "showToast node harness exited non-zero ($TOAST_NODE_RC) with no per-test failures parsed"
fi

print_summary_and_exit
