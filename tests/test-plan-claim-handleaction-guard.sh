#!/bin/bash
# Tests for handleAction plan-* guard on claimed cards (Phase 3 of
# plans/plans-claim-chip-parity.md, W3.12).
#
# When a plan card is in-flight (aria-disabled=true), the keyboard
# move/discard buttons (plan-up / plan-down / plan-left / plan-right /
# plan-discard) MUST be blocked with a toast — preserving the symmetric
# discipline from the issue side (DA11). toggle-mode is NOT blocked
# (user can re-pick landing mode without disturbing the in-flight run).
# (Issue #677 renamed plan-remove → plan-discard; the discard action
# moves the plan to the Discarded column instead of silently no-op'ing
# via the inference fallback.)
#
# Run from repo root: bash tests/test-plan-claim-handleaction-guard.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_JS="$REPO_ROOT/skills/zskills-dashboard/scripts/zskills_monitor/static/app.js"

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
  fail "app.js exists at expected path"
  print_summary_and_exit
fi

# Static grep: guard prose exists in handleAction.
if grep -q "Plan is in-flight; release the claim or wait for completion." "$APP_JS"; then
  pass "handleAction contains plan-side claim toast message"
else
  fail "handleAction missing plan-side claim toast message"
fi

if grep -q 'data-kind="plan"' "$APP_JS" && grep -q 'aria-disabled="true"' "$APP_JS"; then
  pass "handleAction selector includes data-kind=plan + aria-disabled=true"
else
  fail "handleAction selector missing plan-kind aria-disabled match"
fi

if ! command -v node >/dev/null 2>&1; then
  skip "node not available — guard dispatch tests skipped"
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
    attrs: {},
    children: [],
    parent: null,
    hidden: false,
    style: {},
    setAttribute(k, v) { this.attrs[k] = String(v); },
    getAttribute(k) { return this.attrs[k] == null ? null : this.attrs[k]; },
    removeAttribute(k) { delete this.attrs[k]; },
    appendChild(c) { c.parent = this; this.children.push(c); return c; },
    closest(sel) {
      let cur = this;
      while (cur) {
        if (matchesSelector(cur, sel)) return cur;
        cur = cur.parent;
      }
      return null;
    },
  };
  return node;
}
function matchesSelector(node, sel) {
  // Plan-side guard selector form:
  //   li.card[aria-disabled="true"][data-kind="plan"]
  if (sel === 'li.card[aria-disabled="true"][data-kind="plan"]') {
    return (
      node.tagName === "LI" &&
      /(^|\s)card(\s|$)/.test(node.className) &&
      node.attrs["aria-disabled"] === "true" &&
      node.attrs["data-kind"] === "plan"
    );
  }
  // Issue-side selector form (defensive — guard should NOT match plan cards).
  if (sel === 'li.card[aria-disabled="true"][data-kind="issue"]') {
    return (
      node.tagName === "LI" &&
      /(^|\s)card(\s|$)/.test(node.className) &&
      node.attrs["aria-disabled"] === "true" &&
      node.attrs["data-kind"] === "issue"
    );
  }
  return false;
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

const elBlock        = extractBlock(src, /\nfunction el\(tag, opts\)/, "\n}\n");
const titleNodeBlock = extractBlock(src, /\nfunction titleNode\(/, "\n}\n");
const relativeTimeBlock = extractBlock(src, /\nfunction relativeTime\(/, "\n}\n");
const planUrlBlock   = extractBlock(src, /\nfunction planUrl\(/, "\n}\n");
const statusPillCls  = extractBlock(src, /\nfunction statusPillClass\(/, "\n}\n");
const modePillCls    = extractBlock(src, /\nfunction modePillClass\(/, "\n}\n");
const makeMoveBtnBlk = extractBlock(src, /\nfunction makeMoveBtn\(/, "\n}\n");
const buildPlanBlock = extractBlock(src, /\nfunction buildPlanCard\(/, "\n  return card;\n}\n");

// Extract the plan-action guard block — the literal slice from the
// "Guard: claimed plans" comment through the toggle-mode return line.
const guardSrc = extractBlock(
  src,
  /\/\/ Guard: claimed plans are in-flight on another \/run-plan pipeline\./,
  '  if (action === "toggle-mode") return togglePlanMode(slug);'
);

const harness = `
let repoUrl = "https://example.invalid/repo";
function currentEntryMode(_slug) { return null; }

${elBlock}

${titleNodeBlock}

${relativeTimeBlock}

${planUrlBlock}

${statusPillCls}

${modePillCls}

${makeMoveBtnBlk}

${buildPlanBlock}

// Injected fakes the guard delegates to.
let __calls = { movePlan: [], discardPlan: [], togglePlanMode: [], showToast: [] };
function movePlan(slug, dir) { __calls.movePlan.push([slug, dir]); }
function discardPlan(slug) { __calls.discardPlan.push([slug]); }
function togglePlanMode(slug) { __calls.togglePlanMode.push([slug]); }
function showToast(msg, kind) { __calls.showToast.push([msg, kind]); }

function dispatchPlanAction(action, target) {
  const slug = target.getAttribute("data-slug");
${guardSrc}
}

globalThis.__buildPlanCard = buildPlanCard;
globalThis.__dispatchPlanAction = dispatchPlanAction;
globalThis.__getCalls = function() { return __calls; };
globalThis.__resetCalls = function() {
  __calls.movePlan = []; __calls.discardPlan = [];
  __calls.togglePlanMode = []; __calls.showToast = [];
};
`;

const $stub = function() { return null; };
(new Function("document", "$", "globalThis", harness))(document, $stub, globalThis);

const buildPlanCard = globalThis.__buildPlanCard;
const dispatchPlanAction = globalThis.__dispatchPlanAction;

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

function findAllByAttr(root, k, v) {
  const out = [];
  if ((root.attrs || {})[k] === v) out.push(root);
  for (const c of (root.children || [])) {
    for (const hit of findAllByAttr(c, k, v)) out.push(hit);
  }
  return out;
}

// ------------------------------------------------------------------
// Claimed plan card — all 5 keyboard buttons must show toast + no-op
// ------------------------------------------------------------------
{
  const plan = {
    slug: "blocked", title: "P", status: "active", landing_mode: "pr",
    phase_count: 5, phases_done: 1,
    claim: {
      pipeline_id: "run-plan.blocked",
      started_at: new Date().toISOString(),
      current_phase: "Phase 2",
      age_seconds: 30,
      pipeline_short: "blk-abc",
    },
  };
  const card = buildPlanCard(plan, "blocked", "in-progress", "phase");

  const actions = ["plan-up", "plan-down", "plan-left", "plan-right", "plan-discard"];
  for (const action of actions) {
    const btns = findAllByAttr(card, "data-action", action);
    expectTrue(btns.length >= 1, "control button for " + action + " present");
    globalThis.__resetCalls();
    dispatchPlanAction(action, btns[0]);
    const calls = globalThis.__getCalls();
    expect(calls.movePlan.length + calls.discardPlan.length, 0,
      "guard blocks move/discard for action=" + action + " on claimed plan");
    expectTrue(calls.showToast.length === 1,
      "showToast fired exactly once for action=" + action);
    if (calls.showToast.length === 1) {
      expect(calls.showToast[0][0],
        "Plan is in-flight; release the claim or wait for completion.",
        "toast message text for action=" + action);
      expect(calls.showToast[0][1], "info",
        "toast kind is 'info' for action=" + action);
    }
  }

  // toggle-mode: NOT blocked. The user can re-pick landing mode without
  // disturbing the in-flight run. (Card has no toggle-mode button when
  // it's in the 'in-progress' column — that's only on Ready cards — so
  // we synthesize a synthetic target with the right attrs.)
  globalThis.__resetCalls();
  const fakeToggleTarget = makeNode("button");
  fakeToggleTarget.attrs["data-slug"] = "blocked";
  // Parent it to the claimed card so closest() walks succeed.
  fakeToggleTarget.parent = card;
  dispatchPlanAction("toggle-mode", fakeToggleTarget);
  const togglecalls = globalThis.__getCalls();
  expect(togglecalls.togglePlanMode.length, 1,
    "togglePlanMode fires on claimed plan (allowed action — only column/queue mutations blocked)");
  expect(togglecalls.showToast.length, 0,
    "toggle-mode does NOT trigger the in-flight toast");
}

// ------------------------------------------------------------------
// Unclaimed plan card — all 5 actions fire normally
// ------------------------------------------------------------------
{
  const plan = {
    slug: "free", title: "P", status: "active", landing_mode: "pr",
    phase_count: 3, phases_done: 0,
  };
  const card = buildPlanCard(plan, "free", "drafted", "phase");
  globalThis.__resetCalls();
  for (const action of ["plan-up", "plan-down", "plan-left", "plan-right"]) {
    const btn = findAllByAttr(card, "data-action", action)[0];
    dispatchPlanAction(action, btn);
  }
  const rmBtn = findAllByAttr(card, "data-action", "plan-discard")[0];
  dispatchPlanAction("plan-discard", rmBtn);
  const calls = globalThis.__getCalls();
  expect(calls.movePlan.length, 4,
    "movePlan called 4x for unclaimed plan (up/down/left/right)");
  expect(calls.discardPlan.length, 1,
    "discardPlan called 1x for unclaimed plan");
  expect(calls.showToast.length, 0,
    "no toast fired for unclaimed plan actions");
}

// ------------------------------------------------------------------
// Claimed ISSUE card — plan-side guard must NOT block (selector
// specificity check; closest() with data-kind=plan should not match
// data-kind=issue parent).
// ------------------------------------------------------------------
{
  // Build a synthetic claimed issue card stand-in.
  const card = makeNode("li");
  card.className = "card";
  card.attrs["data-kind"] = "issue";
  card.attrs["aria-disabled"] = "true";
  card.attrs["data-slug"] = "irrelevant";
  const btn = makeNode("button");
  btn.attrs["data-action"] = "plan-up";
  btn.attrs["data-slug"] = "irrelevant";
  btn.parent = card;
  globalThis.__resetCalls();
  dispatchPlanAction("plan-up", btn);
  const calls = globalThis.__getCalls();
  // Guard SHOULD NOT fire (different data-kind). movePlan IS expected
  // to fire because no plan-kind claimed ancestor matched.
  expect(calls.showToast.length, 0,
    "plan-side guard does NOT match data-kind=issue ancestor (selector specificity)");
  expect(calls.movePlan.length, 1,
    "movePlan still fires when claimed ancestor has data-kind=issue");
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

if grep -q "test-plan-claim-handleaction-guard.sh" "$REPO_ROOT/tests/run-all.sh"; then
  pass "tests/run-all.sh references test-plan-claim-handleaction-guard.sh"
else
  fail "tests/run-all.sh missing test-plan-claim-handleaction-guard.sh registration"
fi

print_summary_and_exit
