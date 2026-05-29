#!/bin/bash
# Tests for the per-tab unread-dot indicator in app.js (issue #802).
#
# Node-stubbed DOM harness — mirrors the extract-and-exec style of
# tests/test-plan-claim-render-dom.sh. The dot logic spans module-level
# state (lastViewed / currentTabFingerprint / activeTab) plus two functions
# (updateTabDots, setActiveTab); we extract those plus the bookkeeping the
# render loop performs and drive them through a minimal DOM stub.
#
# Concerns:
#   T802.a  No dots at initial load (lastViewed seeded from first snapshot).
#   T802.b  A meaningful change to an inactive tab produces a dot on it.
#   T802.c  Activating a dotted tab clears its dot.
#   T802.d  A volatile-only change (age tick, no real change) → NO dot,
#           because the reused fingerprints exclude volatile fields.
#
# Plus static-grep contracts (markup + CSS rule presence).
#
# Run from repo root: bash tests/test-tab-dot-render-dom.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATIC_DIR="$REPO_ROOT/skills/zskills-dashboard/scripts/zskills_monitor/static"
APP_JS="$STATIC_DIR/app.js"
APP_CSS="$STATIC_DIR/app.css"
INDEX_HTML="$STATIC_DIR/index.html"

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

if [ ! -f "$APP_JS" ] || [ ! -f "$APP_CSS" ] || [ ! -f "$INDEX_HTML" ]; then
  fail "static/{app.js,app.css,index.html} exist at expected paths"
  print_summary_and_exit
fi

# ---------------------------------------------------------------------------
# Static-grep contract: markup + CSS rule presence
# ---------------------------------------------------------------------------

if grep -q 'class="tab-dot"' "$INDEX_HTML"; then
  pass "index.html declares a .tab-dot span on the tab buttons"
else
  fail "index.html missing class=\"tab-dot\" span"
fi
if grep -q 'tab-dot-sr' "$INDEX_HTML"; then
  pass "index.html declares a screen-reader '(updated)' label (tab-dot-sr)"
else
  fail "index.html missing tab-dot-sr screen-reader label"
fi
if grep -q '\.tab-dot' "$APP_CSS"; then
  pass "app.css declares a .tab-dot rule"
else
  fail "app.css missing .tab-dot rule"
fi

if ! command -v node >/dev/null 2>&1; then
  skip "node not available — DOM tests skipped"
  print_summary_and_exit
fi

# ---------------------------------------------------------------------------
# Node-driven DOM behaviour
# ---------------------------------------------------------------------------

NODE_OUT=$(APP_JS_PATH="$APP_JS" node - <<'NODE'
const fs = require("fs");
const src = fs.readFileSync(process.env.APP_JS_PATH, "utf8");

// --------------------------- minimal DOM stub ---------------------------
function makeNode(tag) {
  const node = {
    tagName: (tag || "div").toUpperCase(),
    className: "",
    textContent: "",
    attrs: {},
    children: [],
    setAttribute(k, v) { this.attrs[k] = String(v); },
    getAttribute(k) { return this.attrs[k] == null ? null : this.attrs[k]; },
    removeAttribute(k) { delete this.attrs[k]; },
    hasAttribute(k) { return Object.prototype.hasOwnProperty.call(this.attrs, k); },
    appendChild(c) { this.children.push(c); return c; },
    querySelector(sel) {
      const cls = sel.replace(/^\./, "");
      for (const c of this.children) {
        if ((c.className || "").split(/\s+/).indexOf(cls) >= 0) return c;
      }
      return null;
    },
  };
  return node;
}

// Build the three tab buttons, each with a .tab-dot and .tab-dot-sr child,
// plus the three panels. Dots start hidden (matches index.html markup).
const elements = {};
for (const slug of ["plans", "issues", "branches"]) {
  const btn = makeNode("button");
  btn.attrs["aria-selected"] = slug === "plans" ? "true" : "false";
  const dot = makeNode("span"); dot.className = "tab-dot"; dot.attrs.hidden = "";
  const sr = makeNode("span"); sr.className = "sr-only tab-dot-sr"; sr.attrs.hidden = "";
  btn.appendChild(dot); btn.appendChild(sr);
  elements["tab-" + slug] = btn;
  const panel = makeNode("div");
  elements[slug] = panel;
}
const document = {
  getElementById(id) { return elements[id] || null; },
};
const location = { hash: "" };
const history = { replaceState() {} };

function extractBlock(text, startRe, endMarker) {
  const m = text.match(startRe);
  if (!m) throw new Error("start pattern not found: " + startRe);
  const tail = text.slice(m.index);
  const endIdx = tail.indexOf(endMarker);
  if (endIdx < 0) throw new Error("end marker not found: " + endMarker);
  return tail.slice(0, endIdx + endMarker.length);
}

// Real fingerprint functions under test — proves volatile-safety end to end.
const fpPlansBlock    = extractBlock(src, /\nfunction fingerprintPlans\(/, "\n}\n");
const fpIssuesBlock   = extractBlock(src, /\nfunction fingerprintIssues\(/, "\n}\n");
const fpBranchesBlock = extractBlock(src, /\nfunction fingerprintBranches\(/, "\n}\n");
const updateDotsBlock = extractBlock(src, /\nfunction updateTabDots\(/, "\n}\n");
const setActiveBlock  = extractBlock(src, /\nfunction setActiveTab\(/, "\n}\n");

const harness = `
const TAB_SLUGS = ["plans", "issues", "branches"];
const PLAN_COLUMNS = ["drafted", "ready", "in-progress", "completed"];
const ISSUE_COLUMNS = ["triage", "ready", "in-progress", "completed"];
const lastViewed = { plans: null, issues: null, branches: null };
const currentTabFingerprint = { plans: null, issues: null, branches: null };
let activeTab = "plans";
// Stubs for fingerprint helpers used by the real functions.
function backedBranchSet() { return new Set(); }
function worktreesByBranch() { return new Map(); }
const getCompletedWindow = undefined;

${fpPlansBlock}
${fpIssuesBlock}
${fpBranchesBlock}
${updateDotsBlock}
${setActiveBlock}

// Mirror the applySnapshot dot-bookkeeping (the exact block from app.js).
function applyDotBookkeeping(plansFp, issuesFp, branchesFp) {
  currentTabFingerprint.plans = plansFp;
  currentTabFingerprint.issues = issuesFp;
  currentTabFingerprint.branches = branchesFp;
  for (const tab of TAB_SLUGS) {
    if (lastViewed[tab] === null) lastViewed[tab] = currentTabFingerprint[tab];
  }
  if (TAB_SLUGS.includes(activeTab)) lastViewed[activeTab] = currentTabFingerprint[activeTab];
  updateTabDots();
}

globalThis.__fns = {
  fingerprintPlans, fingerprintIssues, fingerprintBranches,
  updateTabDots, setActiveTab, applyDotBookkeeping,
  lastViewed, currentTabFingerprint,
  getActiveTab: () => activeTab,
};
`;

(new Function("document", "location", "history", "globalThis", harness))(
  document, location, history, globalThis);

const F = globalThis.__fns;

function dotHidden(slug) {
  const dot = elements["tab-" + slug].querySelector(".tab-dot");
  return dot.hasAttribute("hidden");
}
function srHidden(slug) {
  const sr = elements["tab-" + slug].querySelector(".tab-dot-sr");
  return sr.hasAttribute("hidden");
}
function expectTrue(actual, label) {
  if (actual) console.log("OK " + label);
  else { console.log("FAIL " + label); process.exitCode = 1; }
}

// Fixture: queues (empty) + snapshots.
const emptyQueues = { default_mode: "phase", plans: {}, issues: {} };

function plansSnap(extra) {
  return [{ slug: "p1", title: "Plan one", status: "active",
    phase_count: 5, phases_done: 2, blurb: "", ...(extra || {}) }];
}
function issuesSnap(extra) {
  return [{ number: 10, title: "Issue ten", labels: [], created_at: "2026-01-01T00:00:00Z",
    ...(extra || {}) }];
}
function branchesSnap(extra) {
  return [{ name: "feat/x", last_commit_at: "2026-01-01T00:00:00Z",
    last_commit_subject: "hi", upstream: "origin/feat/x", ...(extra || {}) }];
}

function fp(plans, issues, branches) {
  return [
    F.fingerprintPlans(plans, emptyQueues, "phase"),
    F.fingerprintIssues(issues, emptyQueues),
    F.fingerprintBranches(branches, []),
  ];
}

// ---- T802.a: no dots at initial load ----
let [pf, ifp, bf] = fp(plansSnap(), issuesSnap(), branchesSnap());
F.applyDotBookkeeping(pf, ifp, bf);
expectTrue(dotHidden("plans") && dotHidden("issues") && dotHidden("branches"),
  "T802.a no dots on any tab at initial load");
expectTrue(srHidden("issues") && srHidden("branches"),
  "T802.a no screen-reader '(updated)' label at initial load");

// ---- T802.b: meaningful change to an inactive tab produces a dot ----
// Active tab is "plans". Change the ISSUES data meaningfully (title change).
[pf, ifp, bf] = fp(plansSnap(), issuesSnap({ title: "Issue ten CHANGED" }), branchesSnap());
F.applyDotBookkeeping(pf, ifp, bf);
expectTrue(!dotHidden("issues"), "T802.b inactive 'issues' tab gets a dot on meaningful change");
expectTrue(!srHidden("issues"), "T802.b inactive 'issues' tab exposes screen-reader '(updated)'");
expectTrue(dotHidden("plans"), "T802.b active 'plans' tab never dots");
expectTrue(dotHidden("branches"), "T802.b unchanged 'branches' tab has no dot");

// ---- T802.c: activating the dotted tab clears its dot ----
F.setActiveTab("issues");
expectTrue(dotHidden("issues"), "T802.c activating 'issues' clears its dot");
expectTrue(srHidden("issues"), "T802.c activating 'issues' clears its sr label");
expectTrue(F.getActiveTab() === "issues", "T802.c activeTab updated to 'issues'");
// And it stays cleared on the next poll with the same data.
[pf, ifp, bf] = fp(plansSnap(), issuesSnap({ title: "Issue ten CHANGED" }), branchesSnap());
F.applyDotBookkeeping(pf, ifp, bf);
expectTrue(dotHidden("issues"), "T802.c 'issues' stays cleared on next poll (now active)");

// ---- T802.d: volatile-only change produces NO dot on inactive tab ----
// Switch active back to plans so issues/branches are inactive.
F.setActiveTab("plans");
// Establish a baseline with a claim present on an issue.
const claimedIssue = issuesSnap({
  title: "Issue ten CHANGED",
  claim: { pipeline_id: "fix-issues.10", started_at: "2026-05-01T00:00:00Z",
           current_phase: "Phase 1", age_seconds: 5, host_pid: 123 },
});
[pf, ifp, bf] = fp(plansSnap(), claimedIssue, branchesSnap());
F.applyDotBookkeeping(pf, ifp, bf);  // plans active → issues becomes seen? no, only active seeded
// issues is inactive; its fp just changed (claim appeared) so it dots — mark it seen:
F.setActiveTab("issues");
F.setActiveTab("plans");
expectTrue(dotHidden("issues"), "T802.d issues cleared after viewing (pre-volatile baseline)");
// Now tick ONLY the volatile fields (age_seconds + a fresh host_pid churn).
const volatileTick = issuesSnap({
  title: "Issue ten CHANGED",
  claim: { pipeline_id: "fix-issues.10", started_at: "2026-05-01T00:00:00Z",
           current_phase: "Phase 1", age_seconds: 99, host_pid: 999 },
});
const [pf2, ifp2, bf2] = fp(plansSnap(), volatileTick, branchesSnap());
// The fingerprint itself must be byte-identical despite age/pid churn:
expectTrue(ifp2 === ifp,
  "T802.d issues fingerprint is volatile-safe (age_seconds/host_pid churn excluded)");
F.applyDotBookkeeping(pf2, ifp2, bf2);
expectTrue(dotHidden("issues"),
  "T802.d volatile-only change produces NO dot on inactive 'issues' tab");

// Sanity: a real meaningful change (issue title) on the still-inactive
// issues tab DOES dot — proves the volatile-safe path didn't just disable
// dotting. (The issues claim tuple is [pipeline_id, started_at]; a bare
// current_phase tick is intentionally NOT a meaningful issues change, so we
// use a title change to represent real news.)
const realTitle = issuesSnap({ title: "Issue ten REALLY changed now" });
const [pf4, ifp4, bf4] = fp(plansSnap(), realTitle, branchesSnap());
F.applyDotBookkeeping(pf4, ifp4, bf4);
expectTrue(!dotHidden("issues"),
  "T802.d sanity: a real meaningful change still dots inactive 'issues'");
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
if grep -q "test-tab-dot-render-dom.sh" "$REPO_ROOT/tests/run-all.sh"; then
  pass "tests/run-all.sh references test-tab-dot-render-dom.sh"
else
  fail "tests/run-all.sh missing test-tab-dot-render-dom.sh registration"
fi

print_summary_and_exit
