#!/bin/bash
# Tests for Phase 4 — Completed cards are read-only.
#
# Asserts (via JSDOM-style node DOM render of app.js's buildIssueCard /
# buildPlanCard):
#   T4.8.a  buildIssueCard(col="completed") emits no draggable=true,
#           no .claim-chip, no .card-controls, no .remove-btn.
#   T4.8.b  buildPlanCard(col="completed") emits no draggable=true,
#           no .card-controls, no .remove-btn. Title text is plain
#           (no card-title-link anchor — DA10).
#   T4.8.c  Negative controls — the SAME cards rendered at an active
#           column (col="ready" for issues, col="ready" for plans)
#           DO emit draggable=true + .card-controls.
#
# Mirrors the JSDOM stub pattern from tests/test-fix-issues-claim-render-dom.sh.
#
# Run from repo root: bash tests/test-dashboard-completed-readonly.sh

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

NODE_OUT=$(APP_JS_PATH="$APP_JS" node - <<'NODE'
const fs = require("fs");
const src = fs.readFileSync(process.env.APP_JS_PATH, "utf8");

// -----------------------------------------------------------------
// Minimal DOM stub matching test-fix-issues-claim-render-dom.sh.
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
    closest() { return null; },
  };
  return node;
}

const document = { createElement(tag) { return makeNode(tag); } };

// Extract the helpers and the two builder functions.
function extractBlock(text, startRe, endMarker) {
  const m = text.match(startRe);
  if (!m) throw new Error("start pattern not found: " + startRe);
  const startIdx = m.index;
  const tail = text.slice(startIdx);
  const endIdx = tail.indexOf(endMarker);
  if (endIdx < 0) throw new Error("end marker not found: " + endMarker);
  return tail.slice(0, endIdx + endMarker.length);
}

const elBlock = extractBlock(src, /\nfunction el\(tag, opts\)/, "\n}\n");
const titleNodeBlock = extractBlock(src, /\nfunction titleNode\(/, "\n}\n");
const relativeTimeBlock = extractBlock(src, /\nfunction relativeTime\(/, "\n}\n");
const issueUrlBlock = extractBlock(src, /\nfunction issueUrl\(/, "\n}\n");
const planUrlBlock = extractBlock(src, /\nfunction planUrl\(/, "\n}\n");
const makeIssueBtnBlock = extractBlock(src, /\nfunction makeIssueMoveBtn\(/, "\n}\n");
const makeMoveBtnBlock = extractBlock(src, /\nfunction makeMoveBtn\(/, "\n}\n");
const statusPillBlock = extractBlock(src, /\nfunction statusPillClass\(/, "\n}\n");
const modePillBlock = extractBlock(src, /\nfunction modePillClass\(/, "\n}\n");
const currentEntryModeBlock = extractBlock(src, /\nfunction currentEntryMode\(/, "\n}\n");
const buildIssueBlock = extractBlock(src, /\nfunction buildIssueCard\(/, "\n  return card;\n}\n");
const buildPlanBlock = extractBlock(src, /\nfunction buildPlanCard\(/, "\n  return card;\n}\n");

// Pull repoUrl initial value so issueUrl works.
const harness = `
let repoUrl = "https://example.invalid/repo";
let lastGoodQueues = null;

${elBlock}
${titleNodeBlock}
${relativeTimeBlock}
${issueUrlBlock}
${planUrlBlock}
${makeIssueBtnBlock}
${makeMoveBtnBlock}
${statusPillBlock}
${modePillBlock}
${currentEntryModeBlock}
${buildIssueBlock}
${buildPlanBlock}

globalThis.__buildIssueCard = buildIssueCard;
globalThis.__buildPlanCard = buildPlanCard;
`;

(new Function("document", "globalThis", harness))(document, globalThis);

const buildIssueCard = globalThis.__buildIssueCard;
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

// Recursive find-by-class.
function findByClass(root, cls) {
  if ((root.className || "").split(/\s+/).indexOf(cls) >= 0) return root;
  for (const c of (root.children || [])) {
    const hit = findByClass(c, cls);
    if (hit) return hit;
  }
  return null;
}

// ------------------------------------------------------------------
// T4.8.a — buildIssueCard(col="completed") is read-only.
// ------------------------------------------------------------------
{
  // Even with a claim payload, completed cards MUST NOT render the chip.
  const issue = {
    number: 42,
    title: "Done issue",
    labels: [],
    claim: {
      pipeline_id: "fix-issues.foo",
      sprint_id: "foo",
      age_seconds: 30,
      started_at: new Date(Date.now() - 30000).toISOString(),
      pipeline_short: "010731-foo",
    },
  };
  const card = buildIssueCard(issue, 42, "completed");
  expect(card.getAttribute("draggable"), null,
    "T4.8.a completed issue has no draggable attribute");
  expect(card.getAttribute("aria-disabled"), null,
    "T4.8.a completed issue has no aria-disabled (no claim chip path)");
  expect(findByClass(card, "claim-chip"), null,
    "T4.8.a completed issue has no .claim-chip");
  expect(findByClass(card, "card-controls"), null,
    "T4.8.a completed issue has no .card-controls block");
  expect(findByClass(card, "remove-btn"), null,
    "T4.8.a completed issue has no .remove-btn (no per-card ✕)");
  expect(card.getAttribute("data-column"), "completed",
    "T4.8.a completed issue retains data-column='completed'");
}

// ------------------------------------------------------------------
// T4.8.b — buildPlanCard(col="completed") is read-only + plain title.
// ------------------------------------------------------------------
{
  const plan = {
    slug: "demo-plan",
    title: "Demo plan",
    status: "complete",
    landing_mode: "phase",
    phase_count: 3,
    phases_done: 3,
    blurb: "Done.",
  };
  const card = buildPlanCard(plan, "demo-plan", "completed", "phase");
  expect(card.getAttribute("draggable"), null,
    "T4.8.b completed plan has no draggable attribute");
  expect(findByClass(card, "card-controls"), null,
    "T4.8.b completed plan has no .card-controls block");
  expect(findByClass(card, "remove-btn"), null,
    "T4.8.b completed plan has no .remove-btn");
  // DA10 — completed plans render plain title text, no card-title-link.
  expect(findByClass(card, "card-title-link"), null,
    "T4.8.b completed plan has no .card-title-link anchor (DA10)");
  expectTrue(findByClass(card, "card-title"),
    "T4.8.b completed plan emits plain .card-title span");
}

// ------------------------------------------------------------------
// T4.8.c — Negative controls. SAME cards at an active column DO get
// draggable + controls (sanity that the gate is column-conditioned).
// ------------------------------------------------------------------
{
  const issue = { number: 7, title: "Active issue", labels: [] };
  const card = buildIssueCard(issue, 7, "ready");
  expect(card.getAttribute("draggable"), "true",
    "T4.8.c ready issue retains draggable='true'");
  expectTrue(findByClass(card, "card-controls"),
    "T4.8.c ready issue emits .card-controls block");
  expectTrue(findByClass(card, "remove-btn"),
    "T4.8.c ready issue emits .remove-btn");
}
{
  // file:"plans/live.md" supplies the planUrl, so titleNode emits the
  // anchor (.card-title-link) branch — confirming the active-column
  // form differs from the .card-title-only completed branch.
  const plan = {
    slug: "live", title: "Live plan", status: "active",
    landing_mode: "phase", phase_count: 2, phases_done: 1, blurb: "",
    file: "plans/live.md",
  };
  const card = buildPlanCard(plan, "live", "ready", "phase");
  expect(card.getAttribute("draggable"), "true",
    "T4.8.c ready plan retains draggable='true'");
  expectTrue(findByClass(card, "card-controls"),
    "T4.8.c ready plan emits .card-controls block");
  // active plans render the link form (card-title-link), not plain
  expectTrue(findByClass(card, "card-title-link"),
    "T4.8.c ready plan emits .card-title-link anchor (active-column form)");
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

# Registration check.
if grep -q "test-dashboard-completed-readonly.sh" "$REPO_ROOT/tests/run-all.sh"; then
  pass "tests/run-all.sh references test-dashboard-completed-readonly.sh"
else
  fail "tests/run-all.sh missing test-dashboard-completed-readonly.sh registration"
fi

print_summary_and_exit
