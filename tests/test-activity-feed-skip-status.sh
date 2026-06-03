#!/bin/bash
# test-activity-feed-skip-status.sh — Phase 3 (DASHBOARD_RUNSTATUS_CLEANUP_PLAN).
# Node-DOM stub coverage for the activity-feed SKIP pill (a-status-skip).
# Asserts that activityStatusClass maps "skip"/"skipped" → "a-status-skip"
# and that renderActivity emits a pill with that class for a step record.

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

# Static-grep: confirm CSS + JS wiring.
if grep -qE 'a-status-skip' "$APP_JS"; then
  pass "app.js declares a-status-skip"
else
  fail "app.js missing a-status-skip"
fi
if grep -qE 'a-status-skip' "$APP_CSS"; then
  pass "app.css declares .a-status-skip rule"
else
  fail "app.css missing .a-status-skip rule"
fi

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
const document = { createElement(tag) { return makeNode(tag); } };

function extractBlock(text, startRe, endMarker) {
  const m = text.match(startRe);
  if (!m) throw new Error("start pattern not found: " + startRe);
  const startIdx = m.index;
  const tail = text.slice(startIdx);
  const endIdx = tail.indexOf(endMarker);
  if (endIdx < 0) throw new Error("end marker not found: " + endMarker);
  return tail.slice(0, endIdx + endMarker.length);
}

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

// Case 1: activityStatusClass mapping (the load-bearing arm).
const classBlock = extractBlock(src, /\nfunction activityStatusClass\(/, "\n}\n");
(new Function("globalThis", classBlock + "\nglobalThis.__cls = activityStatusClass;"))(globalThis);
const cls = globalThis.__cls;

expect(cls("skip"), "a-status-skip", "activityStatusClass('skip') → a-status-skip");
expect(cls("skipped"), "a-status-skip", "activityStatusClass('skipped') → a-status-skip");
expect(cls("SKIP"), "a-status-skip", "case-insensitive uppercase");
expect(cls("pass"), "a-status-pass", "pass mapping preserved");
expect(cls("fail"), "a-status-fail", "fail mapping preserved");
expect(cls("running"), "a-status-running", "running mapping preserved");
expect(cls(""), "", "empty status → empty class");
expect(cls("unknown"), "", "unknown status → empty class");

// Case 2: renderActivity emits a pill with a-status-skip for a skip record.
const elBlock           = extractBlock(src, /\nfunction el\(tag, opts\)/, "\n}\n");
const relativeTimeBlock = extractBlock(src, /\nfunction relativeTime\(/, "\n}\n");
const renderBlock       = extractBlock(src, /\nfunction renderActivity\(/, "\n}\n");

// Stub the DOM lookup $(id) to return makeNode("div").
const body = makeNode("div");
const empty = makeNode("div");
empty.hidden = false;
const $stub = function(id) {
  if (id === "activity-body") return body;
  if (id === "activity-empty") return empty;
  return null;
};

// `clear(body)` is called inside renderActivity; provide a stub.
// activityStatusClass must be defined in the SAME Function scope as
// renderActivity (the closure captures by lexical scope, not via globalThis).
const harness = `
var repoUrl = "https://example.invalid/repo";
function clear(node) { node.children = []; }
${elBlock}
${relativeTimeBlock}
${classBlock}
${renderBlock}
globalThis.__renderActivity = renderActivity;
`;
(new Function("document", "$", "globalThis", harness))(document, $stub, globalThis);

const renderActivity = globalThis.__renderActivity;

const activity = [{
  kind: "step",
  id: "work-on-plans.S1.p1",
  status: "skip",
  output: "mode_mismatch: finish≠phase",
  pipeline: "work-on-plans.S1",
  skill: "work-on-plans",
  timestamp: "2026-06-02T12:00:00+00:00",
}];

renderActivity(activity);

// Walk body.children → first row → find a span whose className includes
// a-status-skip and pill.
function flatten(root, acc) {
  acc = acc || [];
  acc.push(root);
  for (const c of (root.children || [])) flatten(c, acc);
  return acc;
}
const all = flatten(body);
const pill = all.find(n =>
  (n.className || "").indexOf("a-status-skip") >= 0 &&
  (n.className || "").indexOf("pill") >= 0
);
expectTrue(pill, "rendered pill with class 'pill a-status-skip'");
if (pill) {
  expect(pill.textContent, "skip", "pill textContent === record.status");
}

// Output text — renderActivity does NOT currently render `a.output` in
// the default activity-row branch (it composes `kind + id` into the mid
// span). Assert the kind+id text is present so a future extension that
// surfaces the output doesn't silently regress this case.
const midText = all.map(n => n.textContent || "").join("");
expectTrue(midText.indexOf("step") >= 0, "row text includes kind ('step')");
expectTrue(midText.indexOf("work-on-plans.S1.p1") >= 0, "row text includes record id");
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

# Registration check
if grep -q "test-activity-feed-skip-status.sh" "$REPO_ROOT/tests/run-all.sh"; then
  pass "tests/run-all.sh registers test-activity-feed-skip-status.sh"
else
  fail "tests/run-all.sh missing test-activity-feed-skip-status.sh registration"
fi

print_summary_and_exit
