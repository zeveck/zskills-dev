#!/bin/bash
# Tests for run-plan claim chip render path in app.js (Phase 3 of
# plans/plans-claim-chip-parity.md, W3.11).
#
# Node-stubbed JS harness — mirrors tests/test-fix-issues-claim-render-dom.sh
# for the issue-side chip. Concerns:
#   T3.11.a  buildPlanCard renders claim chip + aria-disabled
#   T3.11.b  Chip text: "working on phase N · <pidShort> · <ageStr>" (no /M,
#            no "in-flight" prefix); progress bar reads N/M from the claim.
#   T3.11.c  Non-numeric current_phase → "working on <header>" verbatim
#   T3.11.d  Null pipeline_short / started_at fall back to "?"
#   T3.11.e  Unclaimed plan retains draggable + no chip
#
# Plus static-grep contracts (CSS class reuse + collector field shape).
#
# Run from repo root: bash tests/test-plan-claim-render-dom.sh
# Per CLAUDE.md: playwright-cli is the project's browser tool, but
# buildPlanCard is pure DOM-construction code with no async I/O — a node
# stub harness is faster and just as accurate for the render assertions.
# A future end-to-end playwright check (W5.2) covers the live dashboard.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATIC_DIR="$REPO_ROOT/skills/zskills-dashboard/scripts/zskills_monitor/static"
APP_JS="$STATIC_DIR/app.js"
APP_CSS="$STATIC_DIR/app.css"
COLLECT_PY="$REPO_ROOT/skills/zskills-dashboard/scripts/zskills_monitor/collect.py"

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
# Static-grep contract: CSS class reuse + collector field allow-list
# ---------------------------------------------------------------------------

# Plan side reuses the existing .claim-chip--in-flight rule (theme-agnostic
# per D6 — no new CSS). Confirm the rule exists.
if grep -q '\.claim-chip--in-flight' "$APP_CSS"; then
  pass "app.css declares .claim-chip--in-flight rule (reused by plan side)"
else
  fail "app.css missing .claim-chip--in-flight rule"
fi

# Collector field allow-list — host_pid and worktree_path MUST NOT appear
# in the `plan["claim"]` dict construction (mirror of issue-side discipline).
if grep -q 'plan\["claim"\]' "$COLLECT_PY"; then
  if grep -A 8 'plan\["claim"\]' "$COLLECT_PY" | grep -E 'host_pid|worktree_path' >/dev/null; then
    fail "collect.py leaks host_pid / worktree_path into plan['claim']"
  else
    pass "collect.py plan['claim'] allow-list excludes host_pid + worktree_path"
  fi
else
  fail "collect.py does not assign plan['claim']"
fi

# Collector defines _read_plan_claims and gates on main_root.
if grep -q 'def _read_plan_claims' "$COLLECT_PY"; then
  pass "collect.py defines _read_plan_claims"
else
  fail "collect.py missing _read_plan_claims definition"
fi
if grep -q '_read_plan_claims(main_root)' "$COLLECT_PY"; then
  GATE_LINE=$(grep -n 'if main_root is not None' "$COLLECT_PY" | head -1 | cut -d: -f1)
  CALL_LINE=$(grep -n '_read_plan_claims(main_root)' "$COLLECT_PY" | grep -v 'def _read_plan_claims' | head -1 | cut -d: -f1)
  if [ -n "$GATE_LINE" ] && [ -n "$CALL_LINE" ] && [ "$CALL_LINE" -gt "$GATE_LINE" ]; then
    pass "_annotate_plans_queue gates _read_plan_claims call on main_root is not None"
  else
    fail "_annotate_plans_queue does not gate _read_plan_claims on main_root"
  fi
else
  fail "_annotate_plans_queue does not call _read_plan_claims(main_root)"
fi

# ---------------------------------------------------------------------------
# Node-driven DOM behaviour
# ---------------------------------------------------------------------------

if ! command -v node >/dev/null 2>&1; then
  skip "node not available — DOM tests skipped"
  print_summary_and_exit
fi

NODE_OUT=$(APP_JS_PATH="$APP_JS" node - <<'NODE'
const fs = require("fs");
const src = fs.readFileSync(process.env.APP_JS_PATH, "utf8");

// -----------------------------------------------------------------
// Minimal DOM stub (parallels test-fix-issues-claim-render-dom.sh).
// -----------------------------------------------------------------
function makeNode(tag) {
  const node = {
    tagName: tag.toUpperCase(),
    className: "",
    textContent: "",
    attrs: {},
    children: [],
    parent: null,
    hidden: false,
    style: {},
    setAttribute(k, v) { this.attrs[k] = String(v); },
    getAttribute(k) { return this.attrs[k] == null ? null : this.attrs[k]; },
    removeAttribute(k) { delete this.attrs[k]; },
    appendChild(c) { c.parent = this; this.children.push(c); return c; },
    closest(_sel) { return null; },  // unused in buildPlanCard render
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

// Helpers needed by buildPlanCard:
const elBlock         = extractBlock(src, /\nfunction el\(tag, opts\)/, "\n}\n");
const titleNodeBlock  = extractBlock(src, /\nfunction titleNode\(/, "\n}\n");
const relativeTimeBlock = extractBlock(src, /\nfunction relativeTime\(/, "\n}\n");
const planUrlBlock    = extractBlock(src, /\nfunction planUrl\(/, "\n}\n");
const statusPillCls   = extractBlock(src, /\nfunction statusPillClass\(/, "\n}\n");
const makeMoveBtnBlk  = extractBlock(src, /\nfunction makeMoveBtn\(/, "\n}\n");
const makeCopyBtnBlk  = extractBlock(src, /\nfunction makeCopyBtn\(/, "\n}\n");
const buildPlanBlock  = extractBlock(src, /\nfunction buildPlanCard\(/, "\n  return card;\n}\n");

// currentEntryMode is used inside buildPlanCard for the ready-column
// mode chip — stub it.
const harness = `
let repoUrl = "https://example.invalid/repo";
if (typeof navigator === "undefined") globalThis.navigator = {};
if (!navigator.clipboard) navigator.clipboard = { writeText: function() { return Promise.resolve(); } };
var SVG_ICONS = {chevronLeft:"",chevronsLeft:"",chevronRight:"",chevronsRight:"",arrowUp:"",arrowDown:"",arrowLeft:"",arrowRight:"",x:"",copy:"",minus:"",plus:""};
var MOVE_ICON_MAP = {};
function currentEntryMode(_slug) { return null; }

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

// The stub's textContent is per-node (not aggregated over descendants),
// so collect all descendant text to assert on labels held by child spans.
function collectText(node) {
  let s = node.textContent || "";
  for (const c of (node.children || [])) s += collectText(c);
  return s;
}

// ------------------------------------------------------------------
// T3.11.a — claim chip renders + aria-disabled + draggable removed
// ------------------------------------------------------------------
{
  const plan = {
    slug: "foo",
    title: "Test plan",
    status: "active",
    phase_count: 5,
    phases_done: 2,
    blurb: "",
    claim: {
      pipeline_id: "run-plan.foo",
      started_at: new Date(Date.now() - 60000).toISOString(),
      current_phase: "Phase 3",
      age_seconds: 30,
      pipeline_short: "foo-abc",
    },
  };
  const card = buildPlanCard(plan, "foo", "in-progress", "phase");
  expect(card.getAttribute("aria-disabled"), "true",
    "claimed plan card sets aria-disabled='true'");
  expect(card.getAttribute("draggable"), null,
    "claimed plan card removes draggable attribute");
  expect(card.getAttribute("data-kind"), "plan",
    "card data-kind='plan' encoded");
  const chip = findByClass(card, "claim-chip");
  expectTrue(chip, "claim chip rendered for claimed plan");
  expectTrue(chip && /claim-chip--in-flight/.test(chip.className),
    "chip has claim-chip--in-flight modifier (theme-agnostic CSS reuse)");
}

// ------------------------------------------------------------------
// T3.11.#884.a — gate (a): claimed plan card is non-draggable + carries
// the claim-lock class + a tooltip naming the in-flight pipeline short id.
// (The draggable-removed assertion lives in T3.11.a above.)
// ------------------------------------------------------------------
{
  const plan = {
    slug: "lockdrag", title: "Lock drag", status: "active",
    phase_count: 5, phases_done: 2,
    claim: {
      pipeline_id: "run-plan.lockdrag",
      started_at: new Date(Date.now() - 60000).toISOString(),
      current_phase: "Phase 3",
      age_seconds: 60,
      pipeline_short: "ld-abc",
    },
  };
  // Use a non-ready, non-completed column so the X button is rendered
  // (Ready also renders it; "drafted" keeps the card simple).
  const card = buildPlanCard(plan, "lockdrag", "drafted", "phase");
  expect(card.getAttribute("draggable"), null,
    "#884 gate(a): claimed plan card has no draggable attribute");
  expectTrue(/(^|\s)claim-locked(\s|$)/.test(card.className),
    "#884 gate(a): claimed plan card carries claim-locked class");
  expect(card.getAttribute("title"),
    "Locked while plan is being worked (pipeline ld-abc).",
    "#884 gate(a): card tooltip names the in-flight pipeline short id");
}

// ------------------------------------------------------------------
// T3.11.#884.c — gate (c): claimed plan's X (discard) button is disabled
// + dimmed (claim-locked class) + carries the lock tooltip + has NO
// data-action (so the delegated dispatcher never routes the click).
// ------------------------------------------------------------------
{
  const plan = {
    slug: "lockx", title: "Lock X", status: "active",
    phase_count: 5, phases_done: 2,
    claim: {
      pipeline_id: "run-plan.lockx",
      started_at: new Date(Date.now() - 60000).toISOString(),
      current_phase: "Phase 3",
      age_seconds: 60,
      pipeline_short: "lx-abc",
    },
  };
  const card = buildPlanCard(plan, "lockx", "ready", "phase");
  // The X button is the .remove-btn descendant.
  const rmBtn = findByClass(card, "remove-btn");
  expectTrue(rmBtn, "#884 gate(c): X (remove-btn) rendered on claimed plan card");
  if (rmBtn) {
    expect(rmBtn.getAttribute("disabled"), "disabled",
      "#884 gate(c): claimed X has disabled attribute");
    expect(rmBtn.getAttribute("aria-disabled"), "true",
      "#884 gate(c): claimed X has aria-disabled='true'");
    expect(rmBtn.getAttribute("data-action"), null,
      "#884 gate(c): claimed X has NO data-action (click never routes)");
    expect(rmBtn.getAttribute("title"),
      "Locked while plan is being worked (pipeline lx-abc).",
      "#884 gate(c): claimed X tooltip names the in-flight pipeline");
    expectTrue(/(^|\s)claim-locked(\s|$)/.test(rmBtn.className),
      "#884 gate(c): claimed X carries claim-locked class (dim styling)");
  }
}

// ------------------------------------------------------------------
// T3.11.b — chip text format "working on phase N · <pid> · <age>"
// The N/M progress framing now lives on the bar (driven from the same
// claim.current_phase); the chip is the liveness/activity indicator and
// drops the redundant "/M" denominator and the "in-flight" prefix.
// ------------------------------------------------------------------
{
  const plan = {
    slug: "bar", title: "P", status: "active",
    phase_count: 5, phases_done: 0,
    claim: {
      pipeline_id: "run-plan.bar",
      started_at: new Date(Date.now() - 60000).toISOString(),
      current_phase: "Phase 3",
      age_seconds: 30,
      pipeline_short: "bar-xyz",
    },
  };
  const card = buildPlanCard(plan, "bar", "in-progress", "phase");
  const chip = findByClass(card, "claim-chip");
  expectTrue(chip, "chip exists for format-spec check");
  if (chip) {
    expectTrue(chip.textContent.indexOf("working on phase 3") >= 0,
      "chip text contains 'working on phase 3'");
    expectTrue(chip.textContent.indexOf("bar-xyz") >= 0,
      "chip text contains pipeline_short 'bar-xyz'");
    expectTrue(chip.textContent.indexOf("/5") < 0 &&
               chip.textContent.indexOf("in-flight") < 0,
      "chip drops the redundant '/M' denominator and 'in-flight' prefix");
    expectTrue(/(s|m|h|d) ago/.test(chip.textContent) ||
               chip.textContent.indexOf("just now") >= 0,
      "chip text contains a non-empty age suffix");
    // Strict format spec: "working on phase N · <pidShort> · <ageStr>"
    expectTrue(/^working on phase 3 · bar-xyz · /.test(chip.textContent),
      "chip text matches format spec prefix 'working on phase N · <pid> · '");
  }
  // Bar is driven from the claim's current_phase when claimed (NOT the
  // stale main-tracker phases_done): phases_done=0 but current_phase=Phase 3
  // → ratio "3 / 5 phases".
  const cardText = collectText(card);
  expectTrue(cardText.indexOf("3 / 5 phases") >= 0,
    "progress bar reads '3 / 5 phases' from claim.current_phase, not '0 / 5'");
  expectTrue(cardText.indexOf("0 / 5 phases") < 0,
    "progress bar does NOT show stale phases_done '0 / 5'");
}

// ------------------------------------------------------------------
// T3.11.c — unparseable current_phase falls back to "phase ?/M"
// ------------------------------------------------------------------
{
  const plan = {
    slug: "section-name", title: "P", status: "active",
    phase_count: 6, phases_done: 0,
    claim: {
      pipeline_id: "run-plan.section-name",
      started_at: new Date(Date.now() - 60000).toISOString(),
      current_phase: "Parse plan",  // section-name header, no "Phase N"
      age_seconds: 30,
      pipeline_short: "section-abc",
    },
  };
  const card = buildPlanCard(plan, "section-name", "in-progress", "phase");
  const chip = findByClass(card, "claim-chip");
  expectTrue(chip, "chip exists with section-name current_phase");
  if (chip) {
    // Non-numeric current_phase: show the raw header verbatim, not "phase ?".
    expectTrue(chip.textContent.indexOf("working on Parse plan") >= 0,
      "section-name current_phase shows 'working on Parse plan' verbatim");
    expectTrue(chip.textContent.indexOf("phase ?") < 0,
      "no 'phase ?' fragment for non-numeric current_phase");
  }
}

// ------------------------------------------------------------------
// T3.11.c-2 — null current_phase falls back to "phase ?/M"
// ------------------------------------------------------------------
{
  const plan = {
    slug: "null-phase", title: "P", status: "active",
    phase_count: 4, phases_done: 0,
    claim: {
      pipeline_id: "run-plan.null-phase",
      started_at: new Date().toISOString(),
      current_phase: null,
      age_seconds: 1,
      pipeline_short: "np",
    },
  };
  const card = buildPlanCard(plan, "null-phase", "in-progress", "phase");
  const chip = findByClass(card, "claim-chip");
  expectTrue(chip, "chip exists with null current_phase");
  if (chip) {
    // Null/absent current_phase: bare "in-flight" fallback, no phase fragment.
    expectTrue(/^in-flight · /.test(chip.textContent),
      "null current_phase falls back to bare 'in-flight · ...'");
    expectTrue(chip.textContent.indexOf("phase") < 0,
      "no 'phase' fragment when current_phase is null");
  }
}

// ------------------------------------------------------------------
// T3.11.d — null pipeline_short / started_at fall back to "?"
// ------------------------------------------------------------------
{
  const plan = {
    slug: "pending", title: "P", status: "active",
    phase_count: 3, phases_done: 0,
    claim: {
      pipeline_id: null,
      started_at: null,
      current_phase: null,
      age_seconds: null,
      pipeline_short: null,
    },
  };
  const card = buildPlanCard(plan, "pending", "in-progress", "phase");
  const chip = findByClass(card, "claim-chip");
  expectTrue(chip, "chip rendered for null-metadata claim");
  if (chip) {
    // Null current_phase → bare "in-flight"; null pid/age → "?".
    expect(chip.textContent, "in-flight · ? · ?",
      "all-null claim chip text is 'in-flight · ? · ?'");
  }
}

// ------------------------------------------------------------------
// T3.11.e — unclaimed plan retains draggable + no chip
// ------------------------------------------------------------------
{
  const plan = {
    slug: "fresh", title: "Unclaimed", status: "active",
    phase_count: 3, phases_done: 0,
  };
  const card = buildPlanCard(plan, "fresh", "drafted", "phase");
  expect(card.getAttribute("aria-disabled"), null,
    "unclaimed plan card has no aria-disabled");
  expect(card.getAttribute("draggable"), "true",
    "unclaimed plan card retains draggable='true'");
  expect(findByClass(card, "claim-chip"), null,
    "no claim-chip rendered when plan.claim absent");
  // #884 back-compat: no claim-lock affordances when plan.claim absent.
  expectTrue(!/(^|\s)claim-locked(\s|$)/.test(card.className),
    "#884 back-compat: unclaimed card has NO claim-locked class");
  expect(card.getAttribute("title"), null,
    "#884 back-compat: unclaimed card has no claim-lock tooltip");
  const rmBtn = findByClass(card, "remove-btn");
  expectTrue(rmBtn, "#884 back-compat: X (remove-btn) rendered on unclaimed plan");
  if (rmBtn) {
    expect(rmBtn.getAttribute("data-action"), "plan-discard",
      "#884 back-compat: unclaimed X retains data-action='plan-discard'");
    expect(rmBtn.getAttribute("disabled"), null,
      "#884 back-compat: unclaimed X is not disabled");
    expectTrue(!/(^|\s)claim-locked(\s|$)/.test(rmBtn.className),
      "#884 back-compat: unclaimed X has no claim-locked class");
  }
}

// ------------------------------------------------------------------
// T3.11.#874.a — Ready col + claim.dispatch_mode='finish' → mode chip
// LOCKED, regardless of entryMode/defaultMode. This is the core
// regression gate: post wrapper-idle, the chip MUST still read locked.
// ------------------------------------------------------------------
{
  const plan = {
    slug: "lockfinish", title: "Locked finish", status: "active",
    phase_count: 5, phases_done: 2,
    claim: {
      pipeline_id: "run-plan.lockfinish",
      started_at: new Date(Date.now() - 60000).toISOString(),
      current_phase: "Phase 3",
      age_seconds: 60,
      pipeline_short: "lock-abc",
      dispatch_mode: "finish",
    },
  };
  // defaultMode="phase" — the precedence MUST come from the claim, not
  // the dashboard default. This is exactly the post-wrapper-idle case.
  const card = buildPlanCard(plan, "lockfinish", "ready", "phase");
  const modeChip = findByClass(card, "mode-chip");
  expectTrue(modeChip,
    "mode-chip rendered on Ready card with claim.dispatch_mode='finish'");
  if (modeChip) {
    expect(modeChip.getAttribute("data-state"), "running-finish",
      "#874: data-state='running-finish' (LOCKED) when claim.dispatch_mode='finish'");
    expect(modeChip.getAttribute("aria-disabled"), "true",
      "#874: aria-disabled='true' when LOCKED");
    expect(modeChip.getAttribute("disabled"), "disabled",
      "#874: disabled attr present when LOCKED");
    // Critically: NO data-action — the chip is informational only when
    // locked, never togglable.
    expect(modeChip.getAttribute("data-action"), null,
      "#874: no data-action='toggle-mode' when LOCKED");
  }
}

// ------------------------------------------------------------------
// T3.11.#874.b — Pre-#874 claim (no dispatch_mode) renders exactly as
// before: defaultMode/entryMode precedence; defaultMode='phase' → NOT
// locked (running-phase, togglable).
// ------------------------------------------------------------------
{
  const plan = {
    slug: "precompat", title: "Back-compat", status: "active",
    phase_count: 4, phases_done: 1,
    claim: {
      pipeline_id: "run-plan.precompat",
      started_at: new Date(Date.now() - 60000).toISOString(),
      current_phase: "Phase 2",
      age_seconds: 60,
      pipeline_short: "pc-abc",
      // dispatch_mode intentionally absent (or null surfaced by collector).
    },
  };
  const card = buildPlanCard(plan, "precompat", "ready", "phase");
  const modeChip = findByClass(card, "mode-chip");
  expectTrue(modeChip, "mode-chip rendered for pre-#874 claim");
  if (modeChip) {
    expect(modeChip.getAttribute("data-state"), "running-phase",
      "#874 back-compat: pre-#874 claim + defaultMode='phase' → 'running-phase' (NOT locked)");
    expect(modeChip.getAttribute("aria-disabled"), null,
      "#874 back-compat: no aria-disabled when not locked");
  }
}

// ------------------------------------------------------------------
// T3.11.#874.c — explicit dispatch_mode='phase' on a claim suppresses
// the lock even if a future caller toggled to finish via the chip.
// ------------------------------------------------------------------
{
  const plan = {
    slug: "phasepin", title: "Phase-pinned", status: "active",
    phase_count: 4, phases_done: 1,
    claim: {
      pipeline_id: "run-plan.phasepin",
      started_at: new Date(Date.now() - 60000).toISOString(),
      current_phase: "Phase 2",
      age_seconds: 60,
      pipeline_short: "pp-abc",
      dispatch_mode: "phase",
    },
  };
  const card = buildPlanCard(plan, "phasepin", "ready", "phase");
  const modeChip = findByClass(card, "mode-chip");
  expectTrue(modeChip, "mode-chip rendered for dispatch_mode='phase' claim");
  if (modeChip) {
    expect(modeChip.getAttribute("data-state"), "running-phase",
      "#874: dispatch_mode='phase' on claim → 'running-phase' (NOT locked)");
  }
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
if grep -q "test-plan-claim-render-dom.sh" "$REPO_ROOT/tests/run-all.sh"; then
  pass "tests/run-all.sh references test-plan-claim-render-dom.sh"
else
  fail "tests/run-all.sh missing test-plan-claim-render-dom.sh registration"
fi

print_summary_and_exit
