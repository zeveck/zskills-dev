#!/bin/bash
# Tests for the execution-mode chip three-state machine on plan cards
# (issue #814). Node-stubbed harness mirroring tests/test-plan-claim-render-dom.sh.
#
# State machine (from issue #814):
#   queued          — !plan.claim. Click cycles inherit ⇄ phase ⇄ finish.
#   running-phase   — plan.claim AND effective mode === "phase".
#                     One-way escalate-to-finish.
#   running-finish  — plan.claim AND effective mode === "finish".
#                     LOCKED — click is a no-op (button disabled).
#
# Effective mode = currentEntryMode(slug) || defaultMode || "phase".
#
# Run from repo root: bash tests/test-mode-chip-three-state.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATIC_DIR="$REPO_ROOT/skills/zskills-dashboard/scripts/zskills_monitor/static"
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

if [ ! -f "$APP_JS" ] || [ ! -f "$APP_CSS" ]; then
  fail "static/{app.js,app.css} exist at expected paths"
  print_summary_and_exit
fi

# ---------------------------------------------------------------------------
# Static-grep: confirm the dashed-dim inherit treatment is gone, the
# three data-state rules are present, and the dropped escalate affordance
# is actually gone (toggle-mode is the only chip action; only
# running-finish locks).
# ---------------------------------------------------------------------------

# Old dashed-dim rule must not appear with its previous shape (selector
# without data-state qualifier + border-style:dashed).
if grep -qE '^\.mode-chip\[data-source="inherit"\] \{' "$APP_CSS"; then
  fail "old dashed-dim .mode-chip[data-source=\"inherit\"] rule still present (should be removed in favor of state-qualified rule)"
else
  pass "old dashed-dim .mode-chip[data-source=\"inherit\"] rule dropped"
fi

# The replacement queued-inherit rule MUST be state-qualified.
if grep -qF '.mode-chip[data-state="queued"][data-source="inherit"]' "$APP_CSS"; then
  pass "queued+inherit rule is state-qualified (.mode-chip[data-state=\"queued\"][data-source=\"inherit\"])"
else
  fail "missing state-qualified queued+inherit rule"
fi

for state in "queued" "running-phase" "running-finish"; do
  if grep -qF ".mode-chip[data-state=\"$state\"]" "$APP_CSS"; then
    pass "app.css declares .mode-chip[data-state=\"$state\"] rule"
  else
    fail "app.css missing .mode-chip[data-state=\"$state\"] rule"
  fi
done

if grep -qE 'cursor:\s*not-allowed' "$APP_CSS"; then
  pass "app.css uses cursor:not-allowed (lock cue)"
else
  fail "app.css missing cursor:not-allowed for locked state"
fi

if grep -qE 'action === "escalate-mode"' "$APP_JS"; then
  fail "handleAction still dispatches escalate-mode (should be removed — escalate affordance was dropped)"
else
  pass "handleAction no longer dispatches escalate-mode (dropped)"
fi

if grep -qE 'async function escalatePlanMode\(' "$APP_JS"; then
  fail "escalatePlanMode function still present (should be removed)"
else
  pass "escalatePlanMode function removed (dropped affordance)"
fi

# ---------------------------------------------------------------------------
# Node DOM behaviour
# ---------------------------------------------------------------------------

if ! command -v node >/dev/null 2>&1; then
  skip "node not available — DOM tests skipped"
  print_summary_and_exit
fi

NODE_OUT=$(APP_JS_PATH="$APP_JS" node - <<'NODE'
const fs = require("fs");
const src = fs.readFileSync(process.env.APP_JS_PATH, "utf8");

function makeNode(tag) {
  const node = {
    tagName: tag.toUpperCase(),
    className: "",
    textContent: "",
    innerHTML: "",
    attrs: {},
    children: [],
    parent: null,
    hidden: false,
    style: {},
    setAttribute(k, v) { this.attrs[k] = String(v); },
    getAttribute(k) { return this.attrs[k] == null ? null : this.attrs[k]; },
    removeAttribute(k) { delete this.attrs[k]; },
    appendChild(c) { c.parent = this; this.children.push(c); return c; },
    closest(_sel) { return null; },
    addEventListener() {},
  };
  return node;
}
const document = {
  createElement(tag) { return makeNode(tag); },
};

function extractBlock(text, startRe, endMarker) {
  const m = text.match(startRe);
  if (!m) throw new Error("start pattern not found: " + startRe);
  const startIdx = m.index;
  const tail = text.slice(startIdx);
  const endIdx = tail.indexOf(endMarker);
  if (endIdx < 0) throw new Error("end marker not found: " + endMarker);
  return tail.slice(0, endIdx + endMarker.length);
}

const elBlock          = extractBlock(src, /\nfunction el\(tag, opts\)/, "\n}\n");
const titleNodeBlock   = extractBlock(src, /\nfunction titleNode\(/, "\n}\n");
const relativeTimeBlock = extractBlock(src, /\nfunction relativeTime\(/, "\n}\n");
const planUrlBlock     = extractBlock(src, /\nfunction planUrl\(/, "\n}\n");
const statusPillCls    = extractBlock(src, /\nfunction statusPillClass\(/, "\n}\n");
const makeMoveBtnBlk   = extractBlock(src, /\nfunction makeMoveBtn\(/, "\n}\n");
const makeCopyBtnBlk   = extractBlock(src, /\nfunction makeCopyBtn\(/, "\n}\n");
const buildPlanBlock   = extractBlock(src, /\nfunction buildPlanCard\(/, "\n  return card;\n}\n");

// Test-controlled entry-mode stub. Override via global __entryMode before
// each test case.
const harness = `
let repoUrl = "https://example.invalid/repo";
if (typeof navigator === "undefined") globalThis.navigator = {};
if (!navigator.clipboard) navigator.clipboard = { writeText: function() { return Promise.resolve(); } };
var SVG_ICONS = {chevronLeft:"",chevronsLeft:"",chevronRight:"",chevronsRight:"",arrowUp:"",arrowDown:"",arrowLeft:"",arrowRight:"",x:"",copy:"",minus:"",plus:"",lock:"<svg data-icon=\\"lock\\"></svg>"};
var MOVE_ICON_MAP = {};
function currentEntryMode(_slug) { return globalThis.__entryMode || null; }

${elBlock}

${titleNodeBlock}

${relativeTimeBlock}

${planUrlBlock}

${statusPillCls}

${makeMoveBtnBlk}

${makeCopyBtnBlk}

${buildPlanBlock}

globalThis.__buildPlanCard = buildPlanCard;
`;

const $stub = function() { return null; };
(new Function("document", "$", "globalThis", harness))(document, $stub, globalThis);

const buildPlanCard = globalThis.__buildPlanCard;

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
  else {
    console.log("FAIL " + label + " (got falsy " + JSON.stringify(actual) + ")");
    process.exitCode = 1;
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

function makeClaimedPlan(slug, phaseCount) {
  return {
    slug: slug,
    title: "P",
    status: "active",
    phase_count: phaseCount,
    phases_done: 0,
    claim: {
      pipeline_id: "run-plan." + slug,
      started_at: new Date(Date.now() - 60000).toISOString(),
      current_phase: "Phase 1",
      age_seconds: 60,
      pipeline_short: slug + "-abc",
    },
  };
}

function makeUnclaimedPlan(slug, phaseCount) {
  return {
    slug: slug,
    title: "P",
    status: "active",
    phase_count: phaseCount,
    phases_done: 0,
  };
}

// ------------------------------------------------------------------
// State: QUEUED — unclaimed plan in 'ready' column
// ------------------------------------------------------------------

// Q1: inherit (entry.mode=null, defaultMode=phase). Real button, NOT dashed.
{
  globalThis.__entryMode = null;
  const card = buildPlanCard(makeUnclaimedPlan("q-inherit", 3), "q-inherit", "ready", "phase");
  const chip = findByClass(card, "mode-chip");
  expectTrue(chip, "queued-inherit: chip rendered");
  if (chip) {
    expect(chip.getAttribute("data-state"), "queued", "queued-inherit: data-state=queued");
    expect(chip.getAttribute("data-source"), "inherit", "queued-inherit: data-source=inherit");
    expect(chip.getAttribute("data-action"), "toggle-mode", "queued-inherit: data-action=toggle-mode (cycle)");
    expectTrue(chip.textContent.indexOf("phase") >= 0, "queued-inherit: chip shows effective mode 'phase'");
    expect(chip.getAttribute("disabled"), null, "queued-inherit: not disabled");
  }
}

// Q2: explicit phase override.
{
  globalThis.__entryMode = "phase";
  const card = buildPlanCard(makeUnclaimedPlan("q-phase", 3), "q-phase", "ready", "finish");
  const chip = findByClass(card, "mode-chip");
  expectTrue(chip, "queued-explicit-phase: chip rendered");
  if (chip) {
    expect(chip.getAttribute("data-state"), "queued", "queued-explicit-phase: data-state=queued");
    expect(chip.getAttribute("data-source"), "explicit", "queued-explicit-phase: data-source=explicit");
    expect(chip.getAttribute("data-action"), "toggle-mode", "queued-explicit-phase: action=toggle-mode");
    expectTrue(chip.textContent.indexOf("phase") >= 0, "queued-explicit-phase: chip text shows 'phase'");
  }
}

// Q3: explicit finish override.
{
  globalThis.__entryMode = "finish";
  const card = buildPlanCard(makeUnclaimedPlan("q-finish", 3), "q-finish", "ready", "phase");
  const chip = findByClass(card, "mode-chip");
  expectTrue(chip, "queued-explicit-finish: chip rendered");
  if (chip) {
    expect(chip.getAttribute("data-state"), "queued", "queued-explicit-finish: data-state=queued");
    expect(chip.getAttribute("data-source"), "explicit", "queued-explicit-finish: data-source=explicit");
    expect(chip.getAttribute("data-action"), "toggle-mode", "queued-explicit-finish: action=toggle-mode");
    expectTrue(chip.textContent.indexOf("finish") >= 0, "queued-explicit-finish: chip text shows 'finish'");
  }
}

// ------------------------------------------------------------------
// State: RUNNING-PHASE — claimed, effective mode = phase
// ------------------------------------------------------------------

// RP1: claimed + inherit + defaultMode=phase → running-phase.
{
  globalThis.__entryMode = null;
  const card = buildPlanCard(makeClaimedPlan("rp-inherit", 5), "rp-inherit", "ready", "phase");
  const chip = findByClass(card, "mode-chip");
  expectTrue(chip, "running-phase (inherit): chip rendered");
  if (chip) {
    expect(chip.getAttribute("data-state"), "running-phase",
      "running-phase (inherit): data-state=running-phase (for CSS colorize)");
    expect(chip.getAttribute("data-action"), "toggle-mode",
      "running-phase: action=toggle-mode (same cycle as queued — escalate affordance dropped)");
    expect(chip.textContent.trim(), "phase",
      "running-phase: chip text is just the mode (no arrow affordance)");
    // Must NOT be locked.
    expect(chip.getAttribute("disabled"), null, "running-phase: chip is enabled (not locked)");
    expect(chip.getAttribute("aria-disabled"), null, "running-phase: no aria-disabled on chip");
  }
}

// RP2: claimed + entry.mode=phase explicit override → running-phase.
{
  globalThis.__entryMode = "phase";
  const card = buildPlanCard(makeClaimedPlan("rp-explicit", 5), "rp-explicit", "ready", "finish");
  const chip = findByClass(card, "mode-chip");
  expectTrue(chip, "running-phase (explicit): chip rendered");
  if (chip) {
    expect(chip.getAttribute("data-state"), "running-phase",
      "running-phase (explicit): data-state=running-phase even when default is finish");
    expect(chip.getAttribute("data-action"), "toggle-mode",
      "running-phase (explicit): action=toggle-mode");
  }
}

// ------------------------------------------------------------------
// State: RUNNING-FINISH — claimed, effective mode = finish — LOCKED
// ------------------------------------------------------------------

// RF1: claimed + entry.mode=finish → running-finish, locked.
{
  globalThis.__entryMode = "finish";
  const card = buildPlanCard(makeClaimedPlan("rf-explicit", 5), "rf-explicit", "ready", "phase");
  const chip = findByClass(card, "mode-chip");
  expectTrue(chip, "running-finish (explicit): chip rendered");
  if (chip) {
    expect(chip.getAttribute("data-state"), "running-finish",
      "running-finish (explicit): data-state=running-finish");
    expect(chip.getAttribute("data-action"), null,
      "running-finish: NO data-action (click is a no-op)");
    expect(chip.getAttribute("disabled"), "disabled",
      "running-finish: button is disabled");
    expect(chip.getAttribute("aria-disabled"), "true",
      "running-finish: aria-disabled=true (announces 'locked' to assistive tech)");
    // Lock icon (svg with data-icon="lock") is present in innerHTML.
    const lockEl = findByClass(card, "mode-chip-lock");
    expectTrue(lockEl !== null || (chip.innerHTML || "").indexOf("lock") >= 0,
      "running-finish: lock icon present in chip");
    // Text still mentions finish.
    expectTrue((chip.innerHTML || chip.textContent || "").indexOf("finish") >= 0,
      "running-finish: chip text/html includes 'finish'");
  }
}

// RF2: claimed + inherit + defaultMode=finish → running-finish, locked.
{
  globalThis.__entryMode = null;
  const card = buildPlanCard(makeClaimedPlan("rf-inherit", 5), "rf-inherit", "ready", "finish");
  const chip = findByClass(card, "mode-chip");
  expectTrue(chip, "running-finish (inherit): chip rendered");
  if (chip) {
    expect(chip.getAttribute("data-state"), "running-finish",
      "running-finish (inherit defaultMode=finish): data-state=running-finish");
    expect(chip.getAttribute("disabled"), "disabled",
      "running-finish (inherit): button is disabled (no-op)");
  }
}

// ------------------------------------------------------------------
// Negative: a non-ready column has no mode chip at all.
// ------------------------------------------------------------------
{
  globalThis.__entryMode = null;
  const card = buildPlanCard(makeUnclaimedPlan("backlog-plan", 3), "backlog-plan", "backlog", "phase");
  const chip = findByClass(card, "mode-chip");
  expect(chip, null, "non-ready column: no mode-chip rendered");
}
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
# Registration check
# ---------------------------------------------------------------------------
if grep -q "test-mode-chip-three-state.sh" "$REPO_ROOT/tests/run-all.sh"; then
  pass "tests/run-all.sh references test-mode-chip-three-state.sh"
else
  fail "tests/run-all.sh missing test-mode-chip-three-state.sh registration"
fi

print_summary_and_exit
