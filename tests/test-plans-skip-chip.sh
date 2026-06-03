#!/bin/bash
# test-plans-skip-chip.sh — Phase 2 (DASHBOARD_RUNSTATUS_CLEANUP_PLAN).
# Node-DOM stub coverage for the plans SKIP chip render + × dismiss arm
# + fingerprintPlans extension. Mirrors test-mode-chip-three-state.sh.

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
# Static-grep: confirm the wiring is present in app.js.
# ---------------------------------------------------------------------------

for sym in 'plan-skip-dismiss' 'postPlanSkipDismiss' 'skip-dismiss-btn' 'skip-chip-label'; do
  if grep -qF "$sym" "$APP_JS"; then
    pass "app.js declares $sym"
  else
    fail "app.js missing $sym"
  fi
done

# fingerprintPlans must include skip_reason (so × clicks trigger re-render).
if grep -qE 'p\.skip_reason' "$APP_JS"; then
  pass "fingerprintPlans references p.skip_reason (re-render gate)"
else
  fail "fingerprintPlans missing p.skip_reason"
fi

# Literal × character must NOT be used in the dismiss-button render path
# (chip uses SVG_ICONS.x for idiom continuity).
# Scope: the SKIP-chip render block in buildPlanCard. Grep for a literal
# `×` character on a line near skip-dismiss-btn.
if grep -B2 -A6 'skip-dismiss-btn' "$APP_JS" | grep -qE 'text:[[:space:]]*"\xc3\x97"'; then
  fail "literal × character found in skip-dismiss-btn render (must use SVG_ICONS.x)"
else
  pass "skip-dismiss-btn uses SVG_ICONS.x (no literal × char)"
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

const elBlock          = extractBlock(src, /\nfunction el\(tag, opts\)/, "\n}\n");
const titleNodeBlock   = extractBlock(src, /\nfunction titleNode\(/, "\n}\n");
const relativeTimeBlock = extractBlock(src, /\nfunction relativeTime\(/, "\n}\n");
const planUrlBlock     = extractBlock(src, /\nfunction planUrl\(/, "\n}\n");
const statusPillCls    = extractBlock(src, /\nfunction statusPillClass\(/, "\n}\n");
const makeMoveBtnBlk   = extractBlock(src, /\nfunction makeMoveBtn\(/, "\n}\n");
const makeCopyBtnBlk   = extractBlock(src, /\nfunction makeCopyBtn\(/, "\n}\n");
const buildPlanBlock   = extractBlock(src, /\nfunction buildPlanCard\(/, "\n  return card;\n}\n");

const harness = `
let repoUrl = "https://example.invalid/repo";
if (typeof navigator === "undefined") globalThis.navigator = {};
if (!navigator.clipboard) navigator.clipboard = { writeText: function() { return Promise.resolve(); } };
var SVG_ICONS = {chevronLeft:"",chevronsLeft:"",chevronRight:"",chevronsRight:"",arrowUp:"",arrowDown:"",arrowLeft:"",arrowRight:"",x:'<svg data-icon="x"></svg>',copy:"",minus:"",plus:"",lock:'<svg data-icon="lock"></svg>'};
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

function makeSkippedPlan(slug, opts) {
  opts = opts || {};
  const p = {
    slug: slug,
    title: "Skipped plan " + slug,
    status: "active",
    phase_count: 3,
    phases_done: 0,
    skip_reason: opts.skip_reason || {
      code: "mode-mismatch",
      reason: "finish≠phase",
      sprint_id: "sprint-X",
      at: "2026-06-02T12:00:00+00:00",
    },
  };
  if (opts.withClaim) {
    p.claim = {
      pipeline_id: "run-plan." + slug,
      started_at: new Date(Date.now() - 60000).toISOString(),
      current_phase: "Phase 1",
      age_seconds: 60,
      pipeline_short: slug + "-abc",
      dispatch_mode: opts.dispatch_mode || "phase",
    };
  }
  return p;
}

// Case 1: plan with skip_reason, no claim, ready column → SKIP chip rendered.
{
  globalThis.__entryMode = null;
  const card = buildPlanCard(makeSkippedPlan("p-skip"), "p-skip", "ready");
  const chip = findByClass(card, "skip-chip");
  expectTrue(chip, "skip-chip rendered (no claim, ready column)");
  if (chip) {
    expectTrue((chip.className || "").indexOf("skip-chip--mode-mismatch") >= 0,
      "skip-chip carries mode-mismatch code class");
    const label = findByClass(card, "skip-chip-label");
    expectTrue(label, "skip-chip-label child rendered");
    if (label) {
      expectTrue((label.textContent || "").indexOf("skip:") >= 0,
        "skip-chip label includes 'skip:' prefix");
      expectTrue((label.textContent || "").indexOf("mode-mismatch") >= 0,
        "skip-chip label includes code");
      expectTrue((label.textContent || "").indexOf("≠") >= 0,
        "skip-chip label includes the reason (finish≠phase)");
    }
    const btn = findByClass(card, "skip-dismiss-btn");
    expectTrue(btn, "× dismiss button rendered");
    if (btn) {
      expect(btn.getAttribute("data-action"), "plan-skip-dismiss",
        "× button data-action=plan-skip-dismiss");
      expect(btn.getAttribute("data-slug"), "p-skip",
        "× button carries data-slug");
      expectTrue((btn.getAttribute("aria-label") || "").indexOf("Dismiss") >= 0,
        "× button aria-label mentions Dismiss");
      expectTrue((btn.innerHTML || "").indexOf("svg") >= 0,
        "× button innerHTML carries SVG (SVG_ICONS.x)");
    }
  }
}

// Case 2: same skip_reason BUT plan has a live claim → SKIP chip NOT rendered
//         (mutual exclusion mirrors #862/#898).
{
  globalThis.__entryMode = null;
  const card = buildPlanCard(
    makeSkippedPlan("p-claimed-skip", { withClaim: true }),
    "p-claimed-skip", "ready",
  );
  const chip = findByClass(card, "skip-chip");
  expect(chip, null,
    "skip-chip suppressed when plan has live claim (mutual exclusion)");
}

// Case 3: non-ready column → no skip chip even with skip_reason.
{
  globalThis.__entryMode = null;
  const card = buildPlanCard(makeSkippedPlan("p-backlog"), "p-backlog", "backlog");
  const chip = findByClass(card, "skip-chip");
  expect(chip, null, "skip-chip not rendered on non-ready column");
}

// Case 4: × click via fetch — mock global fetch and call postPlanSkipDismiss.
//         The arm calls fetch("/api/plan-skip-dismiss", { method: POST, body }).
{
  // Extract postPlanSkipDismiss and evaluate it with a stubbed fetch.
  const postBlock = extractBlock(src, /\nasync function postPlanSkipDismiss\(/, "\n}\n");
  let captured = null;
  const fetchStub = function(url, opts) {
    captured = { url: url, opts: opts };
    return Promise.resolve({ ok: true });
  };
  const showToastStub = function() {};
  (new Function("fetch", "showToast", postBlock + "\nglobalThis.__post = postPlanSkipDismiss;"))(
    fetchStub, showToastStub,
  );
  globalThis.__post("my-slug").then(function() {
    expectTrue(captured, "fetch invoked");
    if (captured) {
      expect(captured.url, "/api/plan-skip-dismiss",
        "× click POSTs to /api/plan-skip-dismiss");
      expect(captured.opts.method, "POST", "method=POST");
      let body = null;
      try { body = JSON.parse(captured.opts.body); } catch (_) {}
      expect(body && body.slug, "my-slug", "body.slug === target slug");
    }
  });
}

// Case 5: fingerprintPlans includes skip_reason. Flip skip_reason between
//         snapshots; assert fingerprint changes.
{
  const fpBlock = extractBlock(src, /\nfunction fingerprintPlans\(/, "\n}\n");
  // Build a minimal stand-in for the PLAN_COLUMNS const + getCompletedWindow.
  (new Function("globalThis", `
    var PLAN_COLUMNS = ["drafted","reviewed","ready","backlog","discarded"];
    var getCompletedWindow = function() { return null; };
    ${fpBlock}
    globalThis.__fp = fingerprintPlans;
  `))(globalThis);
  const fp = globalThis.__fp;
  const queues = { plans: { ready: [{slug:"a"}] } };
  const a1 = [{slug: "a", title: "A", status: "ok", phase_count: 1, phases_done: 0, blurb: ""}];
  const a2 = [{slug: "a", title: "A", status: "ok", phase_count: 1, phases_done: 0, blurb: "",
    skip_reason: { code: "mode-mismatch", reason: "finish≠phase" }}];
  const fp1 = fp(a1, queues);
  const fp2 = fp(a2, queues);
  expectTrue(fp1 !== fp2,
    "fingerprintPlans diverges when skip_reason added (re-render gate)");
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
if grep -q "test-plans-skip-chip.sh" "$REPO_ROOT/tests/run-all.sh"; then
  pass "tests/run-all.sh registers test-plans-skip-chip.sh"
else
  fail "tests/run-all.sh missing test-plans-skip-chip.sh registration"
fi

print_summary_and_exit
