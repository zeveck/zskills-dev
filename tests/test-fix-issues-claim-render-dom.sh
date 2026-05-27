#!/bin/bash
# Tests for fix-issues claim chip render path in app.js (Phase 3 of
# plans/fix-issues-claims.md).
#
# Three concerns are checked here in node-stubbed JS:
#   T3.2.a  buildIssueCard renders claim chip + aria-disabled
#   T3.2.b  handleAction guards block move/remove on claimed cards
#   T3.2.c  fingerprintIssues changes across (no-claim, pending, full) shapes
#   T3.2.d  Chip-text fallback (R2.7): empty relativeTime coalesces to "?"
#
# Plus a static contract grep (CSS + collector field shape).
#
# Run from repo root: bash tests/test-fix-issues-claim-render-dom.sh

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
# Static-grep contract: CSS class names + collector field allow-list
# ---------------------------------------------------------------------------

if grep -q '\.claim-chip--in-flight' "$APP_CSS"; then
  pass "app.css declares .claim-chip--in-flight rule"
else
  fail "app.css missing .claim-chip--in-flight rule"
fi

if grep -q 'cursor: not-allowed' "$APP_CSS" && grep -q 'aria-disabled="true"' "$APP_CSS"; then
  pass "app.css declares .card[aria-disabled='true'] cursor styling"
else
  fail "app.css missing .card[aria-disabled='true'] cursor: not-allowed"
fi

# Collector field allow-list — host_pid and worktree_path MUST NOT appear
# in the `issue["claim"]` dict construction.
if grep -q 'issue\["claim"\]' "$COLLECT_PY"; then
  if grep -A 7 'issue\["claim"\]' "$COLLECT_PY" | grep -E 'host_pid|worktree_path' >/dev/null; then
    fail "collect.py leaks host_pid / worktree_path into issue['claim']"
  else
    pass "collect.py issue['claim'] allow-list excludes host_pid + worktree_path"
  fi
else
  fail "collect.py does not assign issue['claim']"
fi

# Collector calls _read_claims and gates on main_root.
if grep -q 'def _read_claims' "$COLLECT_PY"; then
  pass "collect.py defines _read_claims"
else
  fail "collect.py missing _read_claims definition"
fi
# The gating check verifies (a) the call exists, and (b) the call is
# inside an `if main_root is not None:` block (not unconditional). We
# inspect the lines preceding the call rather than a fixed window after
# the gate, since the gate and call can be separated by the existing
# skip-index machinery.
if grep -q '_read_claims(main_root)' "$COLLECT_PY"; then
  # Anchor the gate search inside _annotate_issues_queue specifically.
  # After Phase 3 (plans-claim-chip-parity), _annotate_plans_queue also
  # contains its own `if main_root is not None:` gate for the parallel
  # _read_plan_claims call; picking `head -1` across the whole file
  # would target the plans-queue gate instead of the issues-queue gate
  # that this assertion is about.
  ANNOT_LINE=$(grep -n '^def _annotate_issues_queue' "$COLLECT_PY" | head -1 | cut -d: -f1)
  if [ -z "$ANNOT_LINE" ]; then
    fail "_annotate_issues_queue function definition not found"
  else
    # First `if main_root is not None` line AT OR AFTER the function start.
    GATE_LINE=$(awk -v start="$ANNOT_LINE" 'NR >= start && /if main_root is not None/ { print NR; exit }' "$COLLECT_PY")
    CALL_LINE=$(awk -v start="$ANNOT_LINE" 'NR >= start && /_read_claims\(main_root\)/ && !/def _read_claims/ { print NR; exit }' "$COLLECT_PY")
    if [ -n "$GATE_LINE" ] && [ -n "$CALL_LINE" ] && [ "$CALL_LINE" -gt "$GATE_LINE" ]; then
      # Confirm no `else:` or dedented statement appears between gate and
      # call — defensive against future refactors moving the call out.
      BETWEEN=$(sed -n "$((GATE_LINE+1)),$((CALL_LINE-1))p" "$COLLECT_PY" | grep -E '^[^ ]|^    [^ ]' | grep -vE '^(    )+[^ ]' || true)
      if [ -z "$BETWEEN" ]; then
        pass "_annotate_issues_queue gates _read_claims call on main_root is not None"
      else
        fail "_annotate_issues_queue: _read_claims appears outside the main_root gate"
      fi
    else
      fail "_annotate_issues_queue does not gate _read_claims on main_root"
    fi
  fi
else
  fail "_annotate_issues_queue does not call _read_claims(main_root)"
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
// Minimal DOM stub. Each "node" tracks tag, attrs, className,
// textContent, children; ancestor-walking is required for the
// closest('selector') match used by the action-dispatch guard.
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
    setAttribute(k, v) { this.attrs[k] = String(v); },
    getAttribute(k) { return this.attrs[k] == null ? null : this.attrs[k]; },
    removeAttribute(k) { delete this.attrs[k]; },
    appendChild(c) { c.parent = this; this.children.push(c); return c; },
    // Very-narrow closest: only the selectors used in app.js below.
    //   li.card[aria-disabled="true"][data-kind="issue"]
    closest(sel) {
      let cur = this;
      while (cur) {
        if (matchesSelector(cur, sel)) return cur;
        cur = cur.parent;
      }
      return null;
    },
    addEventListener() {},
  };
  return node;
}
function matchesSelector(node, sel) {
  // Hand-parse only the one selector form we use in the test.
  // Accept either `li.card[aria-disabled="true"][data-kind="issue"]`
  // or the same with no `li.card` prefix (defensive).
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

// -----------------------------------------------------------------
// Extract the helpers + buildIssueCard + handleAction's guard block.
// -----------------------------------------------------------------
function extractBlock(text, startRe, endMarker) {
  const m = text.match(startRe);
  if (!m) throw new Error("start pattern not found: " + startRe);
  const startIdx = m.index;
  const tail = text.slice(startIdx);
  const endIdx = tail.indexOf(endMarker);
  if (endIdx < 0) throw new Error("end marker not found: " + endMarker);
  return tail.slice(0, endIdx + endMarker.length);
}

// Build the harness incrementally:
//   - el(), titleNode, relativeTime, issueUrl, makeIssueMoveBtn,
//     buildIssueCard, fingerprintIssues
//   - a stripped-down handleAction that only contains the guard +
//     issue-up..remove handlers (just enough to verify guard behavior).

const elBlock = extractBlock(src, /\nfunction el\(tag, opts\)/, "\n}\n");
const titleNodeBlock = extractBlock(src, /\nfunction titleNode\(/, "\n}\n");
const relativeTimeBlock = extractBlock(src, /\nfunction relativeTime\(/, "\n}\n");
const issueUrlBlock = extractBlock(src, /\nfunction issueUrl\(/, "\n}\n");
const makeBtnBlock = extractBlock(src, /\nfunction makeIssueMoveBtn\(/, "\n}\n");
const makeCopyBtnBlock = extractBlock(src, /\nfunction makeCopyBtn\(/, "\n}\n");
const buildCardBlock = extractBlock(src, /\nfunction buildIssueCard\(/, "\n  return card;\n}\n");
const fingerprintBlock = extractBlock(src, /\nfunction fingerprintIssues\(/, "\n}\n");

// Constants required by fingerprintIssues:
//   const ISSUE_COLUMNS = [...]
const issueColumnsMatch = src.match(/const\s+ISSUE_COLUMNS\s*=\s*\[[^\]]*\];/);
if (!issueColumnsMatch) throw new Error("ISSUE_COLUMNS const not found");
const issueColumnsBlock = issueColumnsMatch[0];

// Extract just the issue-action portion of handleAction. Wrap into a
// standalone function `dispatchIssueAction(action, target, deps)` that
// invokes the guard + delegates issue-up/down/left/right/remove to
// injected fakes — exactly the contract we want to verify.
const guardSrc = extractBlock(
  src,
  /\/\/ Guard: claimed issues are in-flight on another pipeline/,
  '  if (action === "issue-remove") return removeIssue(num);'
);

// Build the full harness source.
const harness = `
let repoUrl = "https://example.invalid/repo";
if (typeof navigator === "undefined") globalThis.navigator = {};
if (!navigator.clipboard) navigator.clipboard = { writeText: function() { return Promise.resolve(); } };
var SVG_ICONS = {chevronLeft:"",chevronsLeft:"",chevronRight:"",chevronsRight:"",arrowUp:"",arrowDown:"",arrowLeft:"",arrowRight:"",x:"",copy:"",minus:"",plus:""};
var MOVE_ICON_MAP = {};
${issueColumnsBlock}

${elBlock}

${titleNodeBlock}

${relativeTimeBlock}

${issueUrlBlock}

${makeBtnBlock}

${makeCopyBtnBlock}

${buildCardBlock}

${fingerprintBlock}

// Test wrapper: drives the guard + 5 issue actions with injected fakes.
let __calls = { moveIssue: [], removeIssue: [], showToast: [] };
function moveIssue(num, dir) { __calls.moveIssue.push([num, dir]); }
function removeIssue(num) { __calls.removeIssue.push([num]); }
function showToast(msg, kind) { __calls.showToast.push([msg, kind]); }
function dispatchIssueAction(action, target) {
  const numStr = target.getAttribute("data-number");
  const num = numStr ? parseInt(numStr, 10) : NaN;
${guardSrc}
}

globalThis.__el = el;
globalThis.__buildIssueCard = buildIssueCard;
globalThis.__fingerprintIssues = fingerprintIssues;
globalThis.__dispatchIssueAction = dispatchIssueAction;
globalThis.__getCalls = function() { return __calls; };
globalThis.__resetCalls = function() {
  __calls.moveIssue = []; __calls.removeIssue = []; __calls.showToast = [];
};
globalThis.__ISSUE_COLUMNS = ISSUE_COLUMNS;
`;

// Provide document + a tiny $() stub (titleNode doesn't use it).
const $stub = function() { return null; };
(new Function("document", "$", "globalThis", harness))(document, $stub, globalThis);

const buildIssueCard = globalThis.__buildIssueCard;
const fingerprintIssues = globalThis.__fingerprintIssues;
const dispatchIssueAction = globalThis.__dispatchIssueAction;

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

// Helper: walk children to find a node by class.
function findByClass(root, cls) {
  if ((root.className || "").split(/\s+/).indexOf(cls) >= 0) return root;
  for (const c of (root.children || [])) {
    const hit = findByClass(c, cls);
    if (hit) return hit;
  }
  return null;
}

// ------------------------------------------------------------------
// T3.2.a — buildIssueCard renders the claim chip + aria-disabled
// ------------------------------------------------------------------
{
  const issue = {
    number: 42,
    title: "Test issue",
    labels: [],
    claim: {
      pipeline_id: "fix-issues.sprint-20260521-010731-foo",
      sprint_id: "sprint-20260521-010731-foo",
      age_seconds: 30,
      started_at: new Date(Date.now() - 30000).toISOString(),
      pipeline_short: "010731-foo",
    },
  };
  const card = buildIssueCard(issue, 42, "ready");
  expect(card.getAttribute("aria-disabled"), "true",
    "claimed card sets aria-disabled='true'");
  expect(card.getAttribute("draggable"), null,
    "claimed card removes draggable attribute");
  const chip = findByClass(card, "claim-chip");
  expectTrue(chip, "claim chip rendered for claimed issue");
  if (chip) {
    expectTrue(chip.textContent.indexOf("in-flight") >= 0,
      "chip text contains 'in-flight'");
    expectTrue(chip.textContent.indexOf("010731-foo") >= 0,
      "chip text contains pipeline_short '010731-foo'");
    expectTrue(/(s|m|h|d) ago$/.test(chip.textContent) ||
               chip.textContent.indexOf("just now") >= 0,
      "chip text contains a non-empty age suffix");
  }
}

// ------------------------------------------------------------------
// T3.2.a-2 — unclaimed card remains drag-enabled, no chip
// ------------------------------------------------------------------
{
  const issue = { number: 7, title: "Unclaimed", labels: [] };
  const card = buildIssueCard(issue, 7, "ready");
  expect(card.getAttribute("aria-disabled"), null,
    "unclaimed card has no aria-disabled attribute");
  expect(card.getAttribute("draggable"), "true",
    "unclaimed card retains draggable='true'");
  expect(findByClass(card, "claim-chip"), null,
    "no claim-chip rendered when issue.claim absent");
}

// ------------------------------------------------------------------
// W4.10 — completed_column_no_claim_chip: even with a populated claim
// payload, an issue rendered at col="completed" must NOT emit a
// .claim-chip element. Locks PR #600's aria-disabled invariant on the
// completed column (a completed item is released by definition).
// ------------------------------------------------------------------
{
  const issue = {
    number: 8675309,
    title: "Completed-but-with-claim payload",
    labels: [],
    claim: {
      pipeline_id: "fix-issues.sprint-foo",
      sprint_id: "sprint-foo",
      age_seconds: 120,
      started_at: new Date(Date.now() - 120000).toISOString(),
      pipeline_short: "010731-foo",
    },
  };
  const card = buildIssueCard(issue, 8675309, "completed");
  expect(findByClass(card, "claim-chip"), null,
    "completed_column_no_claim_chip — [data-column='completed'] .claim-chip count is 0");
  expect(card.getAttribute("aria-disabled"), null,
    "completed_column_no_claim_chip — completed card has no aria-disabled (claim-chip path suppressed)");
  expect(card.getAttribute("draggable"), null,
    "completed_column_no_claim_chip — completed card has no draggable attribute");
  expect(card.getAttribute("data-column"), "completed",
    "completed_column_no_claim_chip — data-column='completed' preserved");
}

// ------------------------------------------------------------------
// T3.2.d — chip-text fallback (R2.7): unparseable started_at yields "?"
// ------------------------------------------------------------------
{
  const issue = {
    number: 99,
    title: "Pending metadata",
    labels: [],
    claim: {
      pipeline_id: "fix-issues.sprint-20260521-010731-foo",
      sprint_id: null,
      age_seconds: null,
      started_at: "garbage-not-iso8601",
      pipeline_short: "010731-foo",
    },
  };
  const card = buildIssueCard(issue, 99, "ready");
  const chip = findByClass(card, "claim-chip");
  expectTrue(chip, "chip rendered with unparseable started_at");
  if (chip) {
    expect(chip.textContent, "in-flight · 010731-foo · ?",
      "chip text coalesces empty relativeTime to '?' (R2.7 fallback)");
  }
}

// ------------------------------------------------------------------
// T3.2.d-2 — null pipeline_short also falls back to "?"
// ------------------------------------------------------------------
{
  const issue = {
    number: 100,
    title: "All-null claim (sweep-while-flush)",
    labels: [],
    claim: {
      pipeline_id: null, sprint_id: null, age_seconds: null,
      started_at: null, pipeline_short: null,
    },
  };
  const card = buildIssueCard(issue, 100, "ready");
  const chip = findByClass(card, "claim-chip");
  expectTrue(chip, "chip rendered for null-metadata claim");
  if (chip) {
    expect(chip.textContent, "in-flight · ? · ?",
      "all-null claim chip text is 'in-flight · ? · ?'");
  }
}

// ------------------------------------------------------------------
// T3.2.b — handleAction guards block move/remove on claimed cards
// ------------------------------------------------------------------
{
  // Build a claimed card and pull out the keyboard-move buttons. The
  // guard at the dispatcher uses target.closest(...) — so we point the
  // "target" at one of the controls (which lives inside the card).
  const issue = {
    number: 50,
    title: "Claimed",
    labels: [],
    claim: {
      pipeline_id: "fix-issues.sprint-20260521-010731-foo",
      sprint_id: "s", age_seconds: 5,
      started_at: new Date().toISOString(), pipeline_short: "010731-foo",
    },
  };
  const card = buildIssueCard(issue, 50, "ready");
  // Find the move/remove buttons (children of the controls row).
  function findAllByAttr(root, k, v) {
    const out = [];
    if ((root.attrs || {})[k] === v) out.push(root);
    for (const c of (root.children || [])) {
      for (const hit of findAllByAttr(c, k, v)) out.push(hit);
    }
    return out;
  }
  const actions = ["issue-up", "issue-down", "issue-left", "issue-right"];
  for (const action of actions) {
    const btns = findAllByAttr(card, "data-action", action);
    expectTrue(btns.length >= 1, "control button for " + action + " present");
    globalThis.__resetCalls();
    dispatchIssueAction(action, btns[0]);
    const calls = globalThis.__getCalls();
    expect(calls.moveIssue.length + calls.removeIssue.length, 0,
      "guard blocks move/remove for action=" + action + " on claimed card");
    expectTrue(calls.showToast.length === 1,
      "showToast fired exactly once for action=" + action);
    if (calls.showToast.length === 1) {
      expect(calls.showToast[0][0],
        "Issue is in-flight; release the claim or wait for completion.",
        "toast message text for action=" + action);
      expect(calls.showToast[0][1], "info",
        "toast kind is 'info' for action=" + action);
    }
  }
}

// ------------------------------------------------------------------
// T3.2.b-2 — negative control: handlers DO fire on unclaimed cards
// ------------------------------------------------------------------
{
  const issue = { number: 60, title: "Unclaimed", labels: [] };
  const card = buildIssueCard(issue, 60, "ready");
  function findAllByAttr(root, k, v) {
    const out = [];
    if ((root.attrs || {})[k] === v) out.push(root);
    for (const c of (root.children || [])) {
      for (const hit of findAllByAttr(c, k, v)) out.push(hit);
    }
    return out;
  }
  globalThis.__resetCalls();
  for (const action of ["issue-up", "issue-down", "issue-left", "issue-right"]) {
    const btn = findAllByAttr(card, "data-action", action)[0];
    dispatchIssueAction(action, btn);
  }
  const calls = globalThis.__getCalls();
  expect(calls.moveIssue.length, 4,
    "moveIssue called 4x for unclaimed card (up/down/left/right)");
  expect(calls.showToast.length, 0,
    "no toast fired for unclaimed card actions");
}

// ------------------------------------------------------------------
// T3.2.c — fingerprintIssues regression (DA5)
// 3 snapshots of issue 5 (no-claim, pending-claim, full-claim) must
// produce 3 distinct fingerprint strings.
// ------------------------------------------------------------------
{
  const queues = { issues: { triage: [], ready: [5], "in-progress": [], done: [] } };
  const baseIssue = {
    number: 5, title: "Same title", labels: [], created_at: "2026-05-21T00:00:00Z",
  };
  const noClaim = { ...baseIssue };
  const pendingClaim = {
    ...baseIssue,
    claim: { pipeline_id: null, sprint_id: null, age_seconds: null,
             started_at: null, pipeline_short: null },
  };
  const fullClaim = {
    ...baseIssue,
    claim: {
      pipeline_id: "fix-issues.sprint-20260521-010731-foo",
      sprint_id: "sprint-20260521-010731-foo",
      age_seconds: 10,
      started_at: "2026-05-21T01:07:31+00:00",
      pipeline_short: "010731-foo",
    },
  };
  const fpNo = fingerprintIssues([noClaim], queues);
  const fpPending = fingerprintIssues([pendingClaim], queues);
  const fpFull = fingerprintIssues([fullClaim], queues);
  expectTrue(fpNo !== fpPending,
    "fingerprint differs between no-claim and pending-claim");
  expectTrue(fpPending !== fpFull,
    "fingerprint differs between pending-claim and full-claim");
  expectTrue(fpNo !== fpFull,
    "fingerprint differs between no-claim and full-claim");
}

// ------------------------------------------------------------------
// T3.2.c-2 — fingerprintIssues regression: same full-claim shape
// across two calls produces the SAME fingerprint (no spurious churn).
// ------------------------------------------------------------------
{
  const queues = { issues: { triage: [], ready: [5], "in-progress": [], done: [] } };
  const issue = {
    number: 5, title: "Same", labels: [], created_at: "2026-05-21T00:00:00Z",
    claim: {
      pipeline_id: "fix-issues.sprint-20260521-010731-foo",
      sprint_id: "sprint-20260521-010731-foo",
      age_seconds: 10,
      started_at: "2026-05-21T01:07:31+00:00",
      pipeline_short: "010731-foo",
    },
  };
  const a = fingerprintIssues([issue], queues);
  const b = fingerprintIssues([issue], queues);
  expect(a, b, "fingerprintIssues is stable across repeated calls");
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
if grep -q "test-fix-issues-claim-render-dom.sh" "$REPO_ROOT/tests/run-all.sh"; then
  pass "tests/run-all.sh references test-fix-issues-claim-render-dom.sh"
else
  fail "tests/run-all.sh missing test-fix-issues-claim-render-dom.sh registration"
fi

print_summary_and_exit
