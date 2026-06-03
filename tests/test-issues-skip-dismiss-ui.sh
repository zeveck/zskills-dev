#!/bin/bash
# test-issues-skip-dismiss-ui.sh — Phase 3 (DASHBOARD_RUNSTATUS_CLEANUP_PLAN).
# Node-DOM stub coverage for the Issues SKIP chip × dismiss render +
# fingerprintIssues skip_reason extension + postIssueReconsider fetch
# semantics. Mirrors test-plans-skip-chip.sh.

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

# ---------------------------------------------------------------------------
# Static-grep: confirm the wiring is present.
# ---------------------------------------------------------------------------

for sym in 'issue-skip-dismiss' 'postIssueReconsider' '/api/issue-reconsider' 'data-issue-number'; do
  if grep -qF "$sym" "$APP_JS"; then
    pass "app.js declares $sym"
  else
    fail "app.js missing $sym"
  fi
done

# fingerprintIssues must include skip_reason (so × clicks → next fire's
# skip-state clear triggers re-render).
if grep -qE 'i\.skip_reason' "$APP_JS"; then
  pass "fingerprintIssues references i.skip_reason (re-render gate)"
else
  fail "fingerprintIssues missing i.skip_reason"
fi

# Literal × must NOT be in the issues skip-dismiss render path.
if grep -B2 -A6 'issue-skip-dismiss' "$APP_JS" | grep -qE 'text:[[:space:]]*"\xc3\x97"'; then
  fail "literal × character found in issue-skip-dismiss render (must use SVG_ICONS.x)"
else
  pass "issue-skip-dismiss button uses SVG_ICONS.x (no literal × char)"
fi

# ---------------------------------------------------------------------------
# Node DOM behavior
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

const elBlock            = extractBlock(src, /\nfunction el\(tag, opts\)/, "\n}\n");
const titleNodeBlock     = extractBlock(src, /\nfunction titleNode\(/, "\n}\n");
const issueUrlBlock      = extractBlock(src, /\nfunction issueUrl\(/, "\n}\n");
const relativeTimeBlock  = extractBlock(src, /\nfunction relativeTime\(/, "\n}\n");
const makeIssueMoveBtn   = extractBlock(src, /\nfunction makeIssueMoveBtn\(/, "\n}\n");
const makeCopyBtnBlock   = extractBlock(src, /\nfunction makeCopyBtn\(/, "\n}\n");
const buildIssueBlock    = extractBlock(src, /\nfunction buildIssueCard\(/, "\n  return card;\n}\n");

const harness = `
let repoUrl = "https://example.invalid/repo";
if (typeof navigator === "undefined") globalThis.navigator = {};
if (!navigator.clipboard) navigator.clipboard = { writeText: function() { return Promise.resolve(); } };
var SVG_ICONS = {chevronLeft:"",chevronsLeft:"",chevronRight:"",chevronsRight:"",arrowUp:"",arrowDown:"",arrowLeft:"",arrowRight:"",x:'<svg data-icon="x"></svg>',copy:"",minus:"",plus:"",lock:'<svg data-icon="lock"></svg>'};
var MOVE_ICON_MAP = {};

${elBlock}

${titleNodeBlock}

${issueUrlBlock}

${relativeTimeBlock}

${makeIssueMoveBtn}

${makeCopyBtnBlock}

${buildIssueBlock}

globalThis.__buildIssueCard = buildIssueCard;
`;

const $stub = function() { return null; };
(new Function("document", "$", "globalThis", harness))(document, $stub, globalThis);

const buildIssueCard = globalThis.__buildIssueCard;

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

function makeSkippedIssue(num, opts) {
  opts = opts || {};
  const i = {
    number: num,
    title: "Issue title " + num,
    labels: [],
    created_at: new Date(Date.now() - 86400000).toISOString(),
    skip_reason: opts.skip_reason || {
      code: "plan-scale",
      label: "too big",
      source: "tracker line 3",
    },
  };
  if (opts.withClaim) {
    i.claim = {
      pipeline_id: "fix-issues." + num,
      started_at: new Date(Date.now() - 60000).toISOString(),
      pipeline_short: String(num) + "-abc",
    };
  }
  return i;
}

// Case 1: issue with skip_reason, no claim → SKIP chip rendered with × button.
{
  const card = buildIssueCard(makeSkippedIssue(42), 42, "ready");
  const chip = findByClass(card, "skip-chip");
  expectTrue(chip, "skip-chip rendered (no claim, ready column)");
  if (chip) {
    expectTrue((chip.className || "").indexOf("skip-chip--plan-scale") >= 0,
      "skip-chip carries plan-scale code class");
    const label = findByClass(card, "skip-chip-label");
    expectTrue(label, "skip-chip-label child rendered");
    if (label) {
      expectTrue((label.textContent || "").indexOf("skip:") >= 0,
        "label includes 'skip:' prefix");
      expectTrue((label.textContent || "").indexOf("plan-scale") >= 0,
        "label includes code");
      expectTrue((label.textContent || "").indexOf("too big") >= 0,
        "label includes the human label");
    }
    const btn = findByClass(card, "skip-dismiss-btn");
    expectTrue(btn, "× dismiss button rendered");
    if (btn) {
      expect(btn.getAttribute("data-action"), "issue-skip-dismiss",
        "× button data-action=issue-skip-dismiss");
      expect(btn.getAttribute("data-issue-number"), "42",
        "× button data-issue-number=42");
      expectTrue((btn.getAttribute("aria-label") || "").indexOf("Reconsider") >= 0,
        "× button aria-label mentions Reconsider");
      expectTrue((btn.innerHTML || "").indexOf("svg") >= 0,
        "× button innerHTML carries SVG (SVG_ICONS.x)");
    }
  }
}

// Case 2: same skip_reason BUT issue has a live claim → SKIP chip NOT rendered
//         (mutual exclusion from #862/#898).
{
  const card = buildIssueCard(
    makeSkippedIssue(42, { withClaim: true }),
    42, "ready",
  );
  const chip = findByClass(card, "skip-chip");
  expect(chip, null,
    "skip-chip suppressed when issue has live claim (mutual exclusion)");
}

// Case 3: × click → fetch to /api/issue-reconsider with {number} body.
{
  const postBlock = extractBlock(src, /\nasync function postIssueReconsider\(/, "\n}\n");
  let captured = null;
  const fetchStub = function(url, opts) {
    captured = { url: url, opts: opts };
    return Promise.resolve({ ok: true });
  };
  const showToastStub = function() {};
  (new Function("fetch", "showToast",
    postBlock + "\nglobalThis.__post = postIssueReconsider;"
  ))(fetchStub, showToastStub);
  globalThis.__post(42).then(function() {
    expectTrue(captured, "fetch invoked");
    if (captured) {
      expect(captured.url, "/api/issue-reconsider",
        "× click POSTs to /api/issue-reconsider");
      expect(captured.opts.method, "POST", "method=POST");
      let body = null;
      try { body = JSON.parse(captured.opts.body); } catch (_) {}
      expect(body && body.number, 42, "body.number === target number");
    }
  });
}

// Case 4: fingerprintIssues includes skip_reason. Flip skip_reason between
//         snapshots; assert fingerprint changes.
{
  const fpBlock = extractBlock(src, /\nfunction fingerprintIssues\(/, "\n}\n");
  (new Function("globalThis", `
    var ISSUE_COLUMNS = ["triage","ready","backlog","completed"];
    var getCompletedWindow = function() { return null; };
    ${fpBlock}
    globalThis.__fp = fingerprintIssues;
  `))(globalThis);
  const fp = globalThis.__fp;
  const queues = { issues: { ready: [42] } };
  const a1 = [{number: 42, title: "T", labels: [], created_at: "2026-06-02"}];
  const a2 = [{number: 42, title: "T", labels: [], created_at: "2026-06-02",
    skip_reason: { code: "plan-scale", label: "too big" }}];
  const fp1 = fp(a1, queues);
  const fp2 = fp(a2, queues);
  expectTrue(fp1 !== fp2,
    "fingerprintIssues diverges when skip_reason added (re-render gate)");
}

// Case 5: unresearched skip_reason → NO chip (per existing #445 behavior).
{
  const card = buildIssueCard(
    makeSkippedIssue(42, { skip_reason: { code: "unresearched", label: "n/a" } }),
    42, "ready",
  );
  const chip = findByClass(card, "skip-chip");
  expect(chip, null,
    "skip-chip suppressed for unresearched code (existing #445 invariant preserved)");
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

# Registration check
if grep -q "test-issues-skip-dismiss-ui.sh" "$REPO_ROOT/tests/run-all.sh"; then
  pass "tests/run-all.sh registers test-issues-skip-dismiss-ui.sh"
else
  fail "tests/run-all.sh missing test-issues-skip-dismiss-ui.sh registration"
fi

print_summary_and_exit
