#!/bin/bash
# Tests for run-plan claim chip render path in app.js (Phase 3 of
# plans/plans-claim-chip-parity.md, W3.11).
#
# Node-stubbed JS harness — mirrors tests/test-fix-issues-claim-render-dom.sh
# for the issue-side chip. Concerns:
#   T3.11.a  buildPlanCard renders claim chip + aria-disabled
#   T3.11.b  Chip text format: "in-flight · <pidShort> · phase N/M · <ageStr>"
#   T3.11.c  Unparseable current_phase falls back to "phase ?/M"
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
const modePillCls     = extractBlock(src, /\nfunction modePillClass\(/, "\n}\n");
const makeMoveBtnBlk  = extractBlock(src, /\nfunction makeMoveBtn\(/, "\n}\n");
const makeCopyBtnBlk  = extractBlock(src, /\nfunction makeCopyBtn\(/, "\n}\n");
const buildPlanBlock  = extractBlock(src, /\nfunction buildPlanCard\(/, "\n  return card;\n}\n");

// currentEntryMode is used inside buildPlanCard for the ready-column
// mode chip — stub it.
const harness = `
let repoUrl = "https://example.invalid/repo";
if (typeof navigator === "undefined") globalThis.navigator = {};
if (!navigator.clipboard) navigator.clipboard = { writeText: function() { return Promise.resolve(); } };
function currentEntryMode(_slug) { return null; }

${elBlock}

${titleNodeBlock}

${relativeTimeBlock}

${planUrlBlock}

${statusPillCls}

${modePillCls}

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

// ------------------------------------------------------------------
// T3.11.a — claim chip renders + aria-disabled + draggable removed
// ------------------------------------------------------------------
{
  const plan = {
    slug: "foo",
    title: "Test plan",
    status: "active",
    landing_mode: "pr",
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
// T3.11.b — chip text format "in-flight · <pid> · phase N/M · <age>"
// ------------------------------------------------------------------
{
  const plan = {
    slug: "bar", title: "P", status: "active", landing_mode: "pr",
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
    expectTrue(chip.textContent.indexOf("in-flight") >= 0,
      "chip text starts with 'in-flight'");
    expectTrue(chip.textContent.indexOf("bar-xyz") >= 0,
      "chip text contains pipeline_short 'bar-xyz'");
    expectTrue(chip.textContent.indexOf("phase 3/5") >= 0,
      "chip text contains 'phase 3/5'");
    expectTrue(/(s|m|h|d) ago/.test(chip.textContent) ||
               chip.textContent.indexOf("just now") >= 0,
      "chip text contains a non-empty age suffix");
    // Strict format spec: "in-flight · <pidShort> · phase N/M · <ageStr>"
    expectTrue(/^in-flight · bar-xyz · phase 3\/5 · /.test(chip.textContent),
      "chip text matches format spec prefix 'in-flight · <pid> · phase N/M · '");
  }
}

// ------------------------------------------------------------------
// T3.11.c — unparseable current_phase falls back to "phase ?/M"
// ------------------------------------------------------------------
{
  const plan = {
    slug: "section-name", title: "P", status: "active", landing_mode: "pr",
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
    expectTrue(chip.textContent.indexOf("phase ?/6") >= 0,
      "section-name current_phase falls back to 'phase ?/6'");
  }
}

// ------------------------------------------------------------------
// T3.11.c-2 — null current_phase falls back to "phase ?/M"
// ------------------------------------------------------------------
{
  const plan = {
    slug: "null-phase", title: "P", status: "active", landing_mode: "pr",
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
    expectTrue(chip.textContent.indexOf("phase ?/4") >= 0,
      "null current_phase falls back to 'phase ?/4'");
  }
}

// ------------------------------------------------------------------
// T3.11.d — null pipeline_short / started_at fall back to "?"
// ------------------------------------------------------------------
{
  const plan = {
    slug: "pending", title: "P", status: "active", landing_mode: "pr",
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
    expect(chip.textContent, "in-flight · ? · phase ?/3 · ?",
      "all-null claim chip text is 'in-flight · ? · phase ?/3 · ?'");
  }
}

// ------------------------------------------------------------------
// T3.11.e — unclaimed plan retains draggable + no chip
// ------------------------------------------------------------------
{
  const plan = {
    slug: "fresh", title: "Unclaimed", status: "active", landing_mode: "pr",
    phase_count: 3, phases_done: 0,
  };
  const card = buildPlanCard(plan, "fresh", "drafted", "phase");
  expect(card.getAttribute("aria-disabled"), null,
    "unclaimed plan card has no aria-disabled");
  expect(card.getAttribute("draggable"), "true",
    "unclaimed plan card retains draggable='true'");
  expect(findByClass(card, "claim-chip"), null,
    "no claim-chip rendered when plan.claim absent");
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
