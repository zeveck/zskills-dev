#!/bin/bash
# Tests for moveAllInColumn skipping claimed plan cards (Phase 3 of
# plans/plans-claim-chip-parity.md, W3.13).
#
# `moveAllInColumn` already respects per-card aria-disabled (PR #617 +
# code comment at app.js line 688: "claimed cards are skipped"). The
# function is kind-generic — when called with kind="plan", it must skip
# any plan card whose aria-disabled="true" attribute matches the
# claim-chip render contract from W3.4.
#
# Run from repo root: bash tests/test-plan-claim-moveall-skip.sh

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

# Static grep: kind-generic aria-disabled skip pattern lives in moveAllInColumn.
if grep -A 60 'async function moveAllInColumn' "$APP_JS" | grep -q 'aria-disabled.*true'; then
  pass "moveAllInColumn references aria-disabled='true' (per-card skip pattern)"
else
  fail "moveAllInColumn missing aria-disabled='true' skip check"
fi

if grep -A 60 'async function moveAllInColumn' "$APP_JS" | grep -q 'shakeCard'; then
  pass "moveAllInColumn calls shakeCard on skipped (claimed) cards"
else
  fail "moveAllInColumn missing shakeCard call for skipped cards"
fi

# Confirm moveAllInColumn dispatches via movePlan for kind="plan".
if grep -A 80 'async function moveAllInColumn' "$APP_JS" | grep -q 'await movePlan'; then
  pass "moveAllInColumn dispatches movePlan for kind=plan"
else
  fail "moveAllInColumn missing movePlan dispatch"
fi

if ! command -v node >/dev/null 2>&1; then
  skip "node not available — moveAll dispatch test skipped"
  print_summary_and_exit
fi

NODE_OUT=$(APP_JS_PATH="$APP_JS" node - <<'NODE'
const fs = require("fs");
const src = fs.readFileSync(process.env.APP_JS_PATH, "utf8");

// -----------------------------------------------------------------
// DOM stub w/ querySelectorAll for the dropzone walk + querySelector
// for the live-recheck.
// -----------------------------------------------------------------
const allNodes = [];
function makeNode(tag) {
  const node = {
    tagName: tag.toUpperCase(),
    className: "",
    textContent: "",
    attrs: {},
    children: [],
    parent: null,
    style: {},
    classList: {
      _set: new Set(),
      add(c) { this._set.add(c); },
      remove(c) { this._set.delete(c); },
      contains(c) { return this._set.has(c); },
    },
    setAttribute(k, v) { this.attrs[k] = String(v); },
    getAttribute(k) { return this.attrs[k] == null ? null : this.attrs[k]; },
    removeAttribute(k) { delete this.attrs[k]; },
    appendChild(c) { c.parent = this; this.children.push(c); return c; },
  };
  allNodes.push(node);
  return node;
}

function matchesSelector(node, sel) {
  // We implement only the selectors moveAllInColumn uses:
  //   'ul.dropzone[data-kind="plan"][data-column="ready"] > li.card'
  //   'ul.dropzone[data-kind="plan"] > li.card[data-slug="<id>"]'
  // Plus the implicit > li.card child selector.
  // Parse: ul.dropzone[data-kind="X"][data-column="Y"] > li.card
  let m = sel.match(/^ul\.dropzone\[data-kind="([^"]+)"\]\[data-column="([^"]+)"\] > li\.card$/);
  if (m) {
    const [, kind, col] = m;
    return node.tagName === "LI" &&
      /(^|\s)card(\s|$)/.test(node.className) &&
      node.parent && node.parent.tagName === "UL" &&
      /(^|\s)dropzone(\s|$)/.test(node.parent.className) &&
      node.parent.attrs["data-kind"] === kind &&
      node.parent.attrs["data-column"] === col;
  }
  // ul.dropzone[data-kind="X"] > li.card[data-slug="ID"]
  m = sel.match(/^ul\.dropzone\[data-kind="([^"]+)"\] > li\.card\[data-slug="([^"]+)"\]$/);
  if (m) {
    const [, kind, slug] = m;
    return node.tagName === "LI" &&
      /(^|\s)card(\s|$)/.test(node.className) &&
      node.attrs["data-slug"] === slug &&
      node.parent && node.parent.tagName === "UL" &&
      /(^|\s)dropzone(\s|$)/.test(node.parent.className) &&
      node.parent.attrs["data-kind"] === kind;
  }
  // ul.dropzone[data-kind="X"] > li.card[data-number="ID"]
  m = sel.match(/^ul\.dropzone\[data-kind="([^"]+)"\] > li\.card\[data-number="([^"]+)"\]$/);
  if (m) {
    const [, kind, num] = m;
    return node.tagName === "LI" &&
      /(^|\s)card(\s|$)/.test(node.className) &&
      node.attrs["data-number"] === num &&
      node.parent && node.parent.tagName === "UL" &&
      /(^|\s)dropzone(\s|$)/.test(node.parent.className) &&
      node.parent.attrs["data-kind"] === kind;
  }
  return false;
}

const document = {
  createElement(tag) { return makeNode(tag); },
  querySelectorAll(sel) {
    return allNodes.filter(n => matchesSelector(n, sel));
  },
  querySelector(sel) {
    return allNodes.find(n => matchesSelector(n, sel)) || null;
  },
};
const window = {
  confirm(_msg) { return true; },
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

// Required constants from app.js: PLAN_COLUMNS, ISSUE_COLUMNS,
// PLAN_COLUMN_LABELS, ISSUE_COLUMN_LABELS, MOVE_ALL_CONFIRM_THRESHOLD.
const constsRegexes = [
  /const\s+PLAN_COLUMNS\s*=\s*\[[^\]]*\];/,
  /const\s+ISSUE_COLUMNS\s*=\s*\[[^\]]*\];/,
  /const\s+PLAN_COLUMN_LABELS\s*=\s*\{[\s\S]*?\};/,
  /const\s+ISSUE_COLUMN_LABELS\s*=\s*\{[\s\S]*?\};/,
  /const\s+MOVE_ALL_CONFIRM_THRESHOLD\s*=\s*\d+\s*;/,
];
let constsSrc = "";
for (const re of constsRegexes) {
  const m = src.match(re);
  if (!m) throw new Error("missing const: " + re);
  constsSrc += m[0] + "\n";
}

const moveAllBlock = extractBlock(src, /\nasync function moveAllInColumn\(/, "\n}\n");
const shakeCardBlock = extractBlock(src, /\nfunction shakeCard\(/, "\n}\n");

const harness = `
${constsSrc}

let __calls = { movePlan: [], moveIssue: [], shaken: [] };
async function movePlan(slug, dir) { __calls.movePlan.push([slug, dir]); }
async function moveIssue(num, dir) { __calls.moveIssue.push([num, dir]); }
// shakeCard is reused unchanged; allow it to mutate the test stub.
${shakeCardBlock}
// Wrap shakeCard so we can track invocations on top of its real
// classList.add/remove behaviour.
const __realShakeCard = shakeCard;
function shakeCardTracked(card) {
  __calls.shaken.push(card.attrs["data-slug"] || card.attrs["data-number"] || "?");
  __realShakeCard(card);
}
// Re-bind the local name shakeCard inside moveAllInColumn:
//   (we replace the identifier "shakeCard(" -> "shakeCardTracked(" only
//    inside the moveAllInColumn fn body).
${moveAllBlock.replace(/shakeCard\(/g, "shakeCardTracked(")}

globalThis.__moveAllInColumn = moveAllInColumn;
globalThis.__getCalls = function() { return __calls; };
globalThis.__resetCalls = function() {
  __calls.movePlan = []; __calls.moveIssue = []; __calls.shaken = [];
};
`;

(new Function("document", "window", "globalThis", "setTimeout", harness))(
  document, window, globalThis,
  function setTimeoutStub(fn, _ms) { /* no-op */ }
);

const moveAllInColumn = globalThis.__moveAllInColumn;

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

// ------------------------------------------------------------------
// Build a synthetic plan dropzone with 3 cards (one claimed in the middle).
// ------------------------------------------------------------------
function buildPlanColumn(column, cardSpecs) {
  // cardSpecs: [{slug, claimed?}]
  const ul = makeNode("ul");
  ul.className = "dropzone";
  ul.attrs["data-kind"] = "plan";
  ul.attrs["data-column"] = column;
  for (const spec of cardSpecs) {
    const li = makeNode("li");
    li.className = "card";
    li.attrs["data-kind"] = "plan";
    li.attrs["data-slug"] = spec.slug;
    li.attrs["data-column"] = column;
    if (spec.claimed) li.attrs["aria-disabled"] = "true";
    ul.appendChild(li);
  }
  return ul;
}

// Adjacent column (ready -> in-progress): must exist as a target,
// even if empty. The function reads PLAN_COLUMNS to derive the
// neighbour index, no need for an actual sibling dropzone since the
// dispatch only invokes movePlan(slug, dir).
//
// Top-level await isn't available in (new Function) wrapper; use .then
// on the promise + process.exit on completion so assertions run before
// node exits.
globalThis.__resetCalls();
buildPlanColumn("ready", [
  { slug: "alpha", claimed: false },
  { slug: "beta",  claimed: true  },  // <-- claimed, must be skipped
  { slug: "gamma", claimed: false },
]);
// "ready" is the last column in PLAN_COLUMNS (drafted, reviewed, ready) —
// move-right would be no-op. Use "left" so the source column has a valid
// adjacent neighbour (reviewed).
moveAllInColumn("plan", "ready", "left").then(() => {
  const calls = globalThis.__getCalls();
  // movePlan should be called for alpha + gamma, NOT beta.
  const moved = calls.movePlan.map(c => c[0]).sort();
  expect(moved, ["alpha", "gamma"],
    "movePlan called for unclaimed plans only (beta skipped)");
  // beta is shaken (snapshot-time skip).
  expect(calls.shaken.indexOf("beta") >= 0, true,
    "claimed plan 'beta' is shaken (snapshot-time skip)");
  expect(calls.movePlan.length, 2,
    "exactly 2 movePlan dispatches (1 claimed skipped of 3 total)");
}).catch(err => {
  console.log("FAIL moveAllInColumn threw: " + (err && err.message || err));
  process.exitCode = 1;
});
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

if grep -q "test-plan-claim-moveall-skip.sh" "$REPO_ROOT/tests/run-all.sh"; then
  pass "tests/run-all.sh references test-plan-claim-moveall-skip.sh"
else
  fail "tests/run-all.sh missing test-plan-claim-moveall-skip.sh registration"
fi

print_summary_and_exit
