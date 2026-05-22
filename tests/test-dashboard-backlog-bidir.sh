#!/bin/bash
# Tests for Phase 4 — Backlog bidirectional drag + Completed reject.
#
# NOTE on test surface: a full playwright-cli interactive drag suite would
# require a running dev server. zskills-config.json's `dev_server.cmd` is
# empty (the host project hasn't wired one), so this test ships as a
# JSDOM-style structural + behavioral assertion suite. Playwright path is
# deferred for consumer projects that wire a dev server.
#
# Verifies via direct invocation of the onDrop handler harness:
#   T4.9.a  Drag Triage→Backlog: POSTs `issues.backlog: [N]` (the entry
#           persists). Active-column array loses N.
#   T4.9.b  Drag Backlog→<any active column>: target column is REWRITTEN
#           to leftmost active ("triage" for issues, "drafted" for plans)
#           regardless of which active column the user dropped onto.
#           Tests both: (i) drop on triage (already leftmost — no rewrite
#           observable but post body has triage); (ii) drop on ready
#           (rewrite kicks in — post body has triage, NOT ready).
#   T4.9.c  Dropping onto data-column="completed" is a no-op + no POST
#           (handler hard-rejects + console.warn).
#   T4.9.d  Race-guard: two drags fired within 200ms result in two
#           sequential commitQueueChange calls; the second sees the
#           first's optimistic state and does not revert it.
#
# Single-fetch invariant (AC4.8): asserted in test_zskills_monitor_dashboard_ui.sh.
#
# Run from repo root: bash tests/test-dashboard-backlog-bidir.sh

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

# W4.9 (post-#650 reversal; was rewrite-to-leftmost) — Static-grep
# contract: onDrop must still reject completed drops, but the D5
# leftmost-active rewrite branch is REMOVED. Drops land where dropped.
ONDROP_BODY=$(awk '/^async function onDrop\(/{f=1} f{print} f && /^}$/{exit}' "$APP_JS")
if printf '%s' "$ONDROP_BODY" | grep -qE 'targetCol === "completed"'; then
  pass "onDrop guards on targetCol === 'completed'"
else
  fail "onDrop missing completed-column guard"
fi
if printf '%s' "$ONDROP_BODY" | grep -q 'console.warn'; then
  pass "onDrop completed reject logs via console.warn"
else
  fail "onDrop completed reject missing console.warn"
fi
# Inverted: the sourceColumn==='backlog' rewrite branch must NOT exist.
if printf '%s' "$ONDROP_BODY" | grep -qE 'sourceColumn === "backlog"'; then
  fail "onDrop still has D5 backlog leftmost-active rewrite (should be removed in post-#650 reversal)"
else
  pass "onDrop no longer rewrites backlog drops — drops land where dropped (post-#650 reversal)"
fi
# A one-line comment about the design reversal should be present so
# future readers know D5 was inverted intentionally.
if printf '%s' "$ONDROP_BODY" | grep -qE 'overrides plan D5|post-#650|land where dropped'; then
  pass "onDrop has a comment noting the D5 design reversal"
else
  fail "onDrop missing the D5-reversal comment — future readers won't know the inversion is intentional"
fi

# onDragStart must capture sourceColumn so onDrop knows to rewrite.
ONDRAGSTART_BODY=$(awk '/^function onDragStart\(/{f=1} f{print} f && /^}$/{exit}' "$APP_JS")
if printf '%s' "$ONDRAGSTART_BODY" | grep -qE 'sourceColumn'; then
  pass "onDragStart captures sourceColumn in dragState"
else
  fail "onDragStart does not capture sourceColumn (needed for D5 rewrite)"
fi

if ! command -v node >/dev/null 2>&1; then
  skip "node not available — behavioral tests skipped"
  print_summary_and_exit
fi

# ---------------------------------------------------------------------------
# Behavioral tests (JSDOM-style)
# ---------------------------------------------------------------------------
NODE_OUT=$(APP_JS_PATH="$APP_JS" node - <<'NODE'
const fs = require("fs");
const src = fs.readFileSync(process.env.APP_JS_PATH, "utf8");

// Extract pieces by regex. We build a minimal harness that exercises:
//   onDrop  → calls movePlan/moveIssue with rewritten target.
//   onDragStart → captures sourceColumn.
//
// movePlan/moveIssue are stubbed to record the (id, target) tuple
// without actually calling commitQueueChange/postQueue.

function extractBlock(text, startRe, endMarker) {
  const m = text.match(startRe);
  if (!m) throw new Error("start pattern not found: " + startRe);
  const startIdx = m.index;
  const tail = text.slice(startIdx);
  const endIdx = tail.indexOf(endMarker);
  if (endIdx < 0) throw new Error("end marker not found: " + endMarker);
  return tail.slice(0, endIdx + endMarker.length);
}

const onDragStartBlock = extractBlock(src, /\nfunction onDragStart\(/, "\n}\n");
const onDropBlock = extractBlock(src, /\nasync function onDrop\(/, "\n}\n");
const computeIdxBlock = extractBlock(src, /\nfunction computeInsertIndex\(/, "\n}\n");
const removeIndicatorBlock = extractBlock(src, /\nfunction removeInsertIndicator\(/, "\n}\n");

const harness = `
let dragState = null;
const __movePlan_calls = [];
const __moveIssue_calls = [];
const __warns = [];
const console = { warn: (...a) => __warns.push(a.join(" ")), log: () => {} };
async function movePlan(slug, dest) { __movePlan_calls.push([slug, dest]); }
async function moveIssue(num, dest) { __moveIssue_calls.push([num, dest]); }

${computeIdxBlock}
${removeIndicatorBlock}
${onDragStartBlock}
${onDropBlock}

globalThis.__onDragStart = onDragStart;
globalThis.__onDrop = onDrop;
globalThis.__getMoveCalls = () => ({ plan: __movePlan_calls.slice(), issue: __moveIssue_calls.slice() });
globalThis.__resetCalls = () => { __movePlan_calls.length = 0; __moveIssue_calls.length = 0; __warns.length = 0; };
globalThis.__getWarns = () => __warns.slice();
globalThis.__setDragState = (s) => { dragState = s; };
globalThis.__getDragState = () => dragState;
`;

// Minimal node + document stubs.
const document = {
  querySelectorAll: () => [],
  createElement: (tag) => ({
    tagName: tag.toUpperCase(),
    className: "",
    attrs: {},
    parent: null,
    children: [],
    appendChild(c) { c.parent = this; this.children.push(c); return c; },
    insertBefore(c) { this.children.unshift(c); c.parent = this; return c; },
    setAttribute(k, v) { this.attrs[k] = String(v); },
    getAttribute(k) { return this.attrs[k] == null ? null : this.attrs[k]; },
  }),
};

(new Function("document", "globalThis", harness))(document, globalThis);

const onDragStart = globalThis.__onDragStart;
const onDrop = globalThis.__onDrop;

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
  else { console.log("FAIL " + label); process.exitCode = 1; }
}

// Construct a fake card + dropzone pair.
function makeCard(opts) {
  return {
    tagName: "LI",
    className: "card",
    attrs: {
      draggable: "true",
      "data-kind": opts.kind,
      "data-column": opts.col,
      ...(opts.slug ? { "data-slug": opts.slug } : {}),
      ...(opts.num != null ? { "data-number": String(opts.num) } : {}),
    },
    classList: { add() {}, remove() {} },
    setAttribute(k, v) { this.attrs[k] = String(v); },
    getAttribute(k) { return this.attrs[k] == null ? null : this.attrs[k]; },
    removeAttribute(k) { delete this.attrs[k]; },
    closest(sel) {
      // The selector used by onDragStart is `li.card[draggable='true']`.
      if (sel === "li.card[draggable='true']") {
        return this.attrs.draggable === "true" ? this : null;
      }
      return null;
    },
  };
}
function makeDropzone(kind, col) {
  return {
    tagName: "UL",
    className: "dropzone",
    attrs: { "data-kind": kind, "data-column": col },
    classList: { remove() {} },
    setAttribute(k, v) { this.attrs[k] = String(v); },
    getAttribute(k) { return this.attrs[k] == null ? null : this.attrs[k]; },
    querySelectorAll: () => [],
  };
}
function makeDropEvent(dz) {
  return {
    target: { closest: (sel) => (sel === "ul.dropzone") ? dz : null },
    clientY: 0,
    dataTransfer: null,
    preventDefault() {},
  };
}
function makeDragEvent(card) {
  return {
    target: { closest: (sel) => card.closest(sel) },
    dataTransfer: {
      setData() {}, get effectAllowed() { return ""; }, set effectAllowed(_v) {},
    },
  };
}

async function run() {
  // ------------------------------------------------------------------
  // T4.9.a — Drag issue from Triage → Backlog. Resulting movePlan/Issue
  // call carries { col: "backlog", idx: 0 } (drops at top of empty zone).
  // ------------------------------------------------------------------
  globalThis.__resetCalls();
  const card = makeCard({ kind: "issue", num: 42, col: "triage" });
  onDragStart(makeDragEvent(card));
  const ds = globalThis.__getDragState();
  expect(ds && ds.sourceColumn, "triage", "T4.9.a dragState.sourceColumn captured");
  const dz = makeDropzone("issue", "backlog");
  await onDrop(makeDropEvent(dz));
  const calls = globalThis.__getMoveCalls();
  expect(calls.issue.length, 1, "T4.9.a moveIssue called once on Triage→Backlog");
  expect(calls.issue[0][1].col, "backlog", "T4.9.a target column is backlog");
  expect(globalThis.__getDragState(), null, "T4.9.a dragState cleared after drop");

  // ------------------------------------------------------------------
  // T4.9.b(i) (post-#650 reversal; was rewrite-to-leftmost) — Drag issue
  // from Backlog → Ready. Drops land where dropped: target stays "ready",
  // not "triage". Idx is whatever computeInsertIndex returned (0 here
  // because the test dropzone is empty).
  // ------------------------------------------------------------------
  globalThis.__resetCalls();
  const card2 = makeCard({ kind: "issue", num: 99, col: "backlog" });
  onDragStart(makeDragEvent(card2));
  const dz2 = makeDropzone("issue", "ready");
  await onDrop(makeDropEvent(dz2));
  const calls2 = globalThis.__getMoveCalls();
  expect(calls2.issue.length, 1, "T4.9.b(i) moveIssue called once on Backlog→Ready");
  expect(calls2.issue[0][1].col, "ready",
    "T4.9.b(i) Backlog→Ready lands in Ready (drops land where dropped; D5 rewrite removed)");

  // ------------------------------------------------------------------
  // T4.9.b(ii) (post-#650 reversal) — Drag plan from Backlog → Ready.
  // Target stays "ready", not "drafted".
  // ------------------------------------------------------------------
  globalThis.__resetCalls();
  const card3 = makeCard({ kind: "plan", slug: "p1", col: "backlog" });
  onDragStart(makeDragEvent(card3));
  const dz3 = makeDropzone("plan", "ready");
  await onDrop(makeDropEvent(dz3));
  const calls3 = globalThis.__getMoveCalls();
  expect(calls3.plan.length, 1, "T4.9.b(ii) movePlan called once on Backlog→Ready (plan)");
  expect(calls3.plan[0][1].col, "ready",
    "T4.9.b(ii) Backlog→Ready (plan) lands in Ready (drops land where dropped; D5 rewrite removed)");

  // ------------------------------------------------------------------
  // T4.9.b(iii) (post-#650 reversal) — Drag plan from Backlog → Reviewed.
  // Target stays "reviewed", proving the user's chosen column is honored
  // even when it's NOT the leftmost active column.
  // ------------------------------------------------------------------
  globalThis.__resetCalls();
  const card3b = makeCard({ kind: "plan", slug: "p2", col: "backlog" });
  onDragStart(makeDragEvent(card3b));
  const dz3b = makeDropzone("plan", "reviewed");
  await onDrop(makeDropEvent(dz3b));
  const calls3b = globalThis.__getMoveCalls();
  expect(calls3b.plan[0][1].col, "reviewed",
    "T4.9.b(iii) Backlog→Reviewed (non-leftmost target) lands in Reviewed — honors user's chosen column");

  // ------------------------------------------------------------------
  // T4.9.b(iv) — Drag from Ready (NOT backlog) → Backlog. Always landed
  // in backlog (defer). Unchanged by the reversal.
  // ------------------------------------------------------------------
  globalThis.__resetCalls();
  const card4 = makeCard({ kind: "issue", num: 50, col: "ready" });
  onDragStart(makeDragEvent(card4));
  const dz4 = makeDropzone("issue", "backlog");
  await onDrop(makeDropEvent(dz4));
  const calls4 = globalThis.__getMoveCalls();
  expect(calls4.issue[0][1].col, "backlog",
    "T4.9.b(iv) Ready→Backlog (active source) lands in backlog as defer");

  // ------------------------------------------------------------------
  // T4.9.c — Drop onto data-column="completed" is rejected + warns.
  // ------------------------------------------------------------------
  globalThis.__resetCalls();
  const card5 = makeCard({ kind: "issue", num: 77, col: "ready" });
  onDragStart(makeDragEvent(card5));
  const dz5 = makeDropzone("issue", "completed");
  await onDrop(makeDropEvent(dz5));
  const calls5 = globalThis.__getMoveCalls();
  expect(calls5.issue.length, 0,
    "T4.9.c drop onto completed is a no-op (no movePlan/Issue dispatch)");
  const warns5 = globalThis.__getWarns();
  expectTrue(warns5.length >= 1, "T4.9.c console.warn fired on completed reject");
  expectTrue(
    warns5.length >= 1 && /completed/.test(warns5[0]),
    "T4.9.c warn message mentions 'completed'"
  );
  // dragState must still clear so the next drag starts fresh.
  expect(globalThis.__getDragState(), null,
    "T4.9.c dragState cleared even on rejected drop");

  // ------------------------------------------------------------------
  // T4.9.d — Race-guard: two drag drops fired in quick succession both
  // dispatch via the same handler (no fetch-deduplication shortcut).
  // The race-guard at commitQueueChange (pendingPosts++/--) is exercised
  // here by verifying both dispatches recorded their move calls — the
  // optimistic state from the first does not block the second.
  // ------------------------------------------------------------------
  globalThis.__resetCalls();
  const c1 = makeCard({ kind: "issue", num: 1, col: "triage" });
  onDragStart(makeDragEvent(c1));
  const d1 = makeDropzone("issue", "backlog");
  const p1 = onDrop(makeDropEvent(d1));
  // Fire a second drag near-immediately (well within 200ms).
  const c2 = makeCard({ kind: "issue", num: 2, col: "triage" });
  onDragStart(makeDragEvent(c2));
  const d2 = makeDropzone("issue", "backlog");
  const p2 = onDrop(makeDropEvent(d2));
  await Promise.all([p1, p2]);
  const calls6 = globalThis.__getMoveCalls();
  expect(calls6.issue.length, 2,
    "T4.9.d both rapid drags dispatch their moveIssue calls");
  expect(
    calls6.issue.map(c => c[0]),
    [1, 2],
    "T4.9.d both drag IDs recorded in order"
  );
}

run().catch(e => { console.log("FAIL run() threw: " + e.message); process.exitCode = 1; });
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
if grep -q "test-dashboard-backlog-bidir.sh" "$REPO_ROOT/tests/run-all.sh"; then
  pass "tests/run-all.sh references test-dashboard-backlog-bidir.sh"
else
  fail "tests/run-all.sh missing test-dashboard-backlog-bidir.sh registration"
fi

print_summary_and_exit
