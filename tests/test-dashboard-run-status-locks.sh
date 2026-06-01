#!/bin/bash
# Tests for the run-status widget locks introduced by issue #930:
#
#   1. Default-mode chip lock parity with #874 / #858: when the active
#      /work-on-plans schedule has an explicit mode token in argv
#      (state==="scheduled" + schedule_mode set, not "inherit"), every
#      cron fire dispatches that mode literally — the saved default_mode
#      is ignored. The chip must surface a live mirror of the cron-pinned
#      mode, render visibly locked, and setDefaultMode() must early-return
#      with a toast. The lock must remain restricted to the cron-pinned
#      mode (i.e., the chip stays editable when state===scheduled with
#      schedule_mode null or "inherit"), and the existing #858 sprint
#      lock must NOT regress.
#
#   2. Stop button gate on trigger_configured: the scheduled-branch Stop
#      button renders unconditionally pre-fix and POSTs to /api/trigger
#      which 501s without dashboard.work_on_plans_trigger set. Post-fix,
#      Stop only renders when trigger_configured is true.
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
# Default-mode chip lock matrix + Stop-button gate (DOM-stubbed).
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
const renderDefModeBlk   = extractBlock(src, /\nfunction renderDefaultMode\(mode, ws\)/, "\n}\n");
const setDefaultModeBlk  = extractBlock(src, /\nasync function setDefaultMode\(mode\)/, "\n}\n");
const renderRunStatusBlk = extractBlock(src, /\nfunction renderRunStatus\(ws\)/, "\n}\n");
const elBlock            = extractBlock(src, /\nfunction el\(tag, opts\)/, "\n}\n");

// Minimal DOM: dm-phase / dm-finish buttons + run-status container.
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
    classList: {
      _set: null,
      add(c) { this._set.add(c); },
      remove(c) { this._set.delete(c); },
      contains(c) { return this._set.has(c); },
    },
  };
}

const nodes = {
  "dm-phase": makeNode("dm-phase", "button"),
  "dm-finish": makeNode("dm-finish", "button"),
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
let lastGoodDefaultMode = "phase";
let setDefaultModeCommitted = null;
let lastToast = null;

if (typeof navigator === "undefined") globalThis.navigator = {};
if (!navigator.clipboard) navigator.clipboard = { writeText: function() { return Promise.resolve(); } };
var SVG_ICONS = { copy: "" };

function clear(node) { node.children = []; node.classes.clear(); }
function showToast(msg, kind) { lastToast = { msg: String(msg), kind: kind }; }
function announce() {}
function clonedQueues() { return { default_mode: lastGoodDefaultMode, plans: {}, issues: {} }; }
async function commitQueueChange(next) {
  setDefaultModeCommitted = next.default_mode;
  lastGoodDefaultMode = next.default_mode;
  return true;
}
function formatLocalTime(s) { return s || "?"; }
function relativeTime(s) { return s || "?"; }

${elBlock}

${renderDefModeBlk}

${renderRunStatusBlk}

${setDefaultModeBlk}

globalThis.__renderDefaultMode = renderDefaultMode;
globalThis.__renderRunStatus = renderRunStatus;
globalThis.__setDefaultMode = setDefaultMode;
globalThis.__setLastWorkState = (ws) => { lastWorkState = ws; };
globalThis.__getLastToast = () => lastToast;
globalThis.__resetToast = () => { lastToast = null; };
globalThis.__getCommitted = () => setDefaultModeCommitted;
globalThis.__resetCommitted = () => { setDefaultModeCommitted = null; };
globalThis.__getLastGoodDefaultMode = () => lastGoodDefaultMode;
globalThis.__setLastGoodDefaultMode = (m) => { lastGoodDefaultMode = m; };
`;

(new Function("document", "$", "globalThis", harness))(document, $stub, globalThis);

const renderDefaultMode = globalThis.__renderDefaultMode;
const renderRunStatus = globalThis.__renderRunStatus;
const setDefaultMode = globalThis.__setDefaultMode;

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
function expectFalse(actual, label) {
  if (!actual) console.log("OK " + label);
  else { console.log("FAIL " + label + " (got truthy " + JSON.stringify(actual) + ")"); process.exitCode = 1; }
}

function resetNodes() {
  for (const k of Object.keys(nodes)) {
    nodes[k].attrs = {};
    nodes[k].children = [];
    nodes[k].classes.clear();
    nodes[k].className = "";
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
  const phase = nodes["dm-phase"];
  const finish = nodes["dm-finish"];
  const root = nodes["run-status"];

  // -----------------------------------------------------------------------
  // Bug 1 — Default-mode chip lock matrix.
  // -----------------------------------------------------------------------

  // Case A: state==="sprint" — existing #858 sprint-lock fires (don't regress).
  resetNodes();
  globalThis.__setLastWorkState({ state: "sprint", batch_mode: "finish" });
  globalThis.__setLastGoodDefaultMode("phase");
  renderDefaultMode("phase", { state: "sprint", batch_mode: "finish" });
  expect(phase.getAttribute("data-locked"), "true", "sprint: dm-phase data-locked=true (no regression)");
  expect(finish.getAttribute("data-locked"), "true", "sprint: dm-finish data-locked=true (no regression)");
  expectTrue(
    (phase.getAttribute("title") || "").indexOf("Sprint in flight") >= 0,
    "sprint: tooltip mentions sprint-in-flight (#858 wording preserved)"
  );
  expect(finish.getAttribute("aria-pressed"), "true", "sprint: dm-finish active (mirrors batch_mode=finish)");
  globalThis.__resetCommitted();
  globalThis.__resetToast();
  await setDefaultMode("phase");
  expect(globalThis.__getCommitted(), null, "sprint: setDefaultMode early-returns (no commit)");
  expectTrue(
    (globalThis.__getLastToast() || {}).msg
      && globalThis.__getLastToast().msg.indexOf("sprint is in flight") >= 0,
    "sprint: toast wording is the #858 sprint variant"
  );

  // Case B: state==="scheduled", schedule_mode==="finish" — cron-pinned lock.
  resetNodes();
  globalThis.__setLastWorkState({ state: "scheduled", schedule_mode: "finish" });
  globalThis.__setLastGoodDefaultMode("phase");
  renderDefaultMode("phase", { state: "scheduled", schedule_mode: "finish" });
  expect(phase.getAttribute("data-locked"), "true",
    "scheduled+pin=finish: dm-phase data-locked=true");
  expect(finish.getAttribute("data-locked"), "true",
    "scheduled+pin=finish: dm-finish data-locked=true");
  expect(finish.getAttribute("aria-pressed"), "true",
    "scheduled+pin=finish: dm-finish is the active chip (mirrors cron-pinned mode)");
  expect(phase.getAttribute("aria-pressed"), "false",
    "scheduled+pin=finish: dm-phase NOT active");
  expectTrue(
    (phase.getAttribute("title") || "").indexOf("/work-on-plans schedule pins mode to 'finish'") >= 0,
    "scheduled+pin=finish: tooltip names the cron-pinned mode"
  );
  globalThis.__resetCommitted();
  globalThis.__resetToast();
  await setDefaultMode("phase");
  expect(globalThis.__getCommitted(), null,
    "scheduled+pin=finish: setDefaultMode early-returns (no commit)");
  expectTrue(
    (globalThis.__getLastToast() || {}).msg
      && globalThis.__getLastToast().msg.indexOf("/work-on-plans schedule pins mode to 'finish'") >= 0,
    "scheduled+pin=finish: toast names the cron-pinned mode"
  );

  // Case C: state==="scheduled", schedule_mode==="phase" — cron-pinned lock to phase.
  resetNodes();
  globalThis.__setLastWorkState({ state: "scheduled", schedule_mode: "phase" });
  globalThis.__setLastGoodDefaultMode("finish");
  renderDefaultMode("finish", { state: "scheduled", schedule_mode: "phase" });
  expect(phase.getAttribute("data-locked"), "true",
    "scheduled+pin=phase: dm-phase data-locked=true");
  expect(finish.getAttribute("data-locked"), "true",
    "scheduled+pin=phase: dm-finish data-locked=true");
  expect(phase.getAttribute("aria-pressed"), "true",
    "scheduled+pin=phase: dm-phase active (mirrors cron-pinned mode, ignores saved default_mode=finish)");
  expect(finish.getAttribute("aria-pressed"), "false",
    "scheduled+pin=phase: dm-finish NOT active");
  globalThis.__resetCommitted();
  await setDefaultMode("finish");
  expect(globalThis.__getCommitted(), null,
    "scheduled+pin=phase: setDefaultMode early-returns (no commit)");

  // Case D: state==="scheduled", schedule_mode==null — chip is EDITABLE.
  resetNodes();
  globalThis.__setLastWorkState({ state: "scheduled" });
  globalThis.__setLastGoodDefaultMode("phase");
  renderDefaultMode("phase", { state: "scheduled" });
  expectFalse(phase.getAttribute("data-locked"),
    "scheduled+no-pin: dm-phase NOT locked (no schedule_mode → editable)");
  expectFalse(finish.getAttribute("data-locked"),
    "scheduled+no-pin: dm-finish NOT locked");
  expectFalse(phase.getAttribute("title"),
    "scheduled+no-pin: no lock tooltip");
  globalThis.__resetCommitted();
  await setDefaultMode("finish");
  expect(globalThis.__getCommitted(), "finish",
    "scheduled+no-pin: setDefaultMode proceeds (commit recorded)");

  // Case E: state==="scheduled", schedule_mode==="inherit" — sentinel for no-pin, editable.
  resetNodes();
  globalThis.__setLastWorkState({ state: "scheduled", schedule_mode: "inherit" });
  globalThis.__setLastGoodDefaultMode("phase");
  renderDefaultMode("phase", { state: "scheduled", schedule_mode: "inherit" });
  expectFalse(phase.getAttribute("data-locked"),
    "scheduled+inherit-sentinel: dm-phase NOT locked (inherit == no pin)");
  expectFalse(finish.getAttribute("data-locked"),
    "scheduled+inherit-sentinel: dm-finish NOT locked");
  globalThis.__resetCommitted();
  await setDefaultMode("finish");
  expect(globalThis.__getCommitted(), "finish",
    "scheduled+inherit-sentinel: setDefaultMode proceeds (commit recorded)");

  // Case F: state==="idle" — chip editable as today.
  resetNodes();
  globalThis.__setLastWorkState({ state: "idle" });
  globalThis.__setLastGoodDefaultMode("phase");
  renderDefaultMode("phase", { state: "idle" });
  expectFalse(phase.getAttribute("data-locked"), "idle: dm-phase NOT locked");
  expectFalse(finish.getAttribute("data-locked"), "idle: dm-finish NOT locked");
  globalThis.__resetCommitted();
  await setDefaultMode("finish");
  expect(globalThis.__getCommitted(), "finish",
    "idle: setDefaultMode proceeds (commit recorded)");

  // -----------------------------------------------------------------------
  // Bug 2 — Stop-button gate on trigger_configured.
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

print_summary_and_exit
