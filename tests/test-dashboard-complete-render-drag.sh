#!/bin/bash
# Tests for Issue #905 — Dashboard: client-side half of #853.
#
# Two coupled fixes covered here:
#
#   Gap 1 — Render override in deepCloneQueues. A plan whose server-
#           annotated queue.column is "completed" must render under
#           Completed even when the state file pins it elsewhere. A
#           plan whose server queue.column is anything else (and
#           especially when status: active is pinned to backlog) must
#           continue to honor its pin (rule (i) narrowness).
#
#   Gap 2 — Drag-to-Completed safety hatch in onDragEnter / onDragOver
#           / onDrop. Allow drops onto Completed ONLY when the dragged
#           plan's status is "complete" or "landed". Reject other
#           statuses with no highlight + no POST (existing read-only
#           guard remains terminal for them).
#
# Run from repo root: bash tests/test-dashboard-complete-render-drag.sh
#
# Server-side per-slug status gate is covered in
# tests/test_zskills_monitor_server.sh (#905 plans.completed ... cases).

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

// Extract the functions we exercise.
function extractBlock(text, startRe, endMarker) {
  const m = text.match(startRe);
  if (!m) throw new Error("start pattern not found: " + startRe);
  const startIdx = m.index;
  const tail = text.slice(startIdx);
  const endIdx = tail.indexOf(endMarker);
  if (endIdx < 0) throw new Error("end marker not found: " + endMarker);
  return tail.slice(0, endIdx + endMarker.length);
}

const deepCloneBlock = extractBlock(src, /\nfunction deepCloneQueues\(/, "\n  return out;\n}\n");
const isAllowedBlock = extractBlock(src, /\nfunction isCompletedDropAllowed\(/, "\n}\n");

// Constants the function depends on.
const PLAN_COLUMNS = ["drafted", "reviewed", "ready", "backlog", "discarded", "completed"];
const ISSUE_COLUMNS = ["triage", "ready", "backlog", "completed"];

const harness = `
const PLAN_COLUMNS = ${JSON.stringify(PLAN_COLUMNS)};
const ISSUE_COLUMNS = ${JSON.stringify(ISSUE_COLUMNS)};
// Stub getCompletedWindow to disable the completed-window filter
// (return "all"); the override should function independently of the
// filter window.
function getCompletedWindow(_kind) { return "all"; }

${deepCloneBlock}
${isAllowedBlock}

globalThis.__deepCloneQueues = deepCloneQueues;
globalThis.__isCompletedDropAllowed = isCompletedDropAllowed;
`;

(new Function("globalThis", harness))(globalThis);

const deepCloneQueues = globalThis.__deepCloneQueues;
const isCompletedDropAllowed = globalThis.__isCompletedDropAllowed;

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
function expectFalse(actual, label) {
  if (!actual) console.log("OK " + label);
  else {
    console.log("FAIL " + label + " (got truthy " + JSON.stringify(actual) + ")");
    process.exitCode = 1;
  }
}

// ------------------------------------------------------------------
// Gap 1 — Render override.
// A plan pinned in state.plans.ready whose server queue.column is
// "completed" must end up in out.plans.completed (NOT out.plans.ready),
// AND must NOT appear twice. Reproduces the live #905 bug with
// brainstorm-mode-plan.
// ------------------------------------------------------------------
{
  const queues = {
    plans: {
      drafted: [],
      reviewed: [],
      ready: [{ slug: "stuck-completed" }],
      backlog: [],
      discarded: [],
      completed: [],
    },
    issues: { triage: [], ready: [], backlog: [], completed: [] },
  };
  const plans = [
    {
      slug: "stuck-completed",
      status: "complete",
      completed: "2026-06-01T00:00:00Z",
      queue: { column: "completed", index: -1, mode: null },
    },
  ];
  const out = deepCloneQueues(queues, plans, [], true);
  expect(out.plans.ready, [],
    "Gap 1 — pinned-in-ready slug with server completed override is NOT in out.plans.ready");
  expect(out.plans.completed.length, 1,
    "Gap 1 — completed-override slug appears in out.plans.completed");
  expect(out.plans.completed[0].slug, "stuck-completed",
    "Gap 1 — completed slug routed to Completed by inference");
  // Negative duplication check.
  let appearances = 0;
  for (const c of PLAN_COLUMNS) {
    for (const e of out.plans[c]) {
      if ((typeof e === "string" ? e : e.slug) === "stuck-completed") appearances++;
    }
  }
  expect(appearances, 1, "Gap 1 — completed slug appears EXACTLY once across all columns");
}

// ------------------------------------------------------------------
// Gap 1 negative — narrowness invariant (rule (i) intact for non-complete).
// A status:active plan pinned to backlog must STAY in backlog. The
// override only relaxes for queue.column === "completed".
// ------------------------------------------------------------------
{
  const queues = {
    plans: {
      drafted: [],
      reviewed: [],
      ready: [],
      backlog: [{ slug: "active-in-backlog" }],
      discarded: [],
      completed: [],
    },
    issues: { triage: [], ready: [], backlog: [], completed: [] },
  };
  const plans = [
    {
      slug: "active-in-backlog",
      status: "active",
      // Server respects the pin → queue.column = "backlog".
      queue: { column: "backlog", index: 0, mode: null },
    },
  ];
  const out = deepCloneQueues(queues, plans, [], true);
  expect(out.plans.backlog.length, 1,
    "Gap 1 narrowness — active plan pinned to backlog stays in backlog");
  expect(out.plans.backlog[0].slug, "active-in-backlog",
    "Gap 1 narrowness — pinned slug preserved in backlog");
  expect(out.plans.completed, [],
    "Gap 1 narrowness — non-complete plan NOT in completed");
}

// ------------------------------------------------------------------
// Gap 1 mixed — completed override + writable pin coexist.
// One status:active plan pinned to ready stays in ready; one
// status:complete plan pinned to ready (e.g. stale historical pin)
// moves to completed via the override.
// ------------------------------------------------------------------
{
  const queues = {
    plans: {
      drafted: [],
      reviewed: [],
      ready: [{ slug: "active-keep" }, { slug: "complete-move" }],
      backlog: [],
      discarded: [],
      completed: [],
    },
    issues: { triage: [], ready: [], backlog: [], completed: [] },
  };
  const plans = [
    {
      slug: "active-keep",
      status: "active",
      queue: { column: "ready", index: 0, mode: null },
    },
    {
      slug: "complete-move",
      status: "complete",
      completed: "2026-06-01T00:00:00Z",
      queue: { column: "completed", index: -1, mode: null },
    },
  ];
  const out = deepCloneQueues(queues, plans, [], true);
  expect(out.plans.ready.length, 1,
    "Gap 1 mixed — only the active plan remains in ready");
  expect(out.plans.ready[0].slug, "active-keep",
    "Gap 1 mixed — active-keep stays in ready");
  expect(out.plans.completed.length, 1,
    "Gap 1 mixed — complete plan moved to completed");
  expect(out.plans.completed[0].slug, "complete-move",
    "Gap 1 mixed — complete-move surfaces in completed");
}

// ------------------------------------------------------------------
// Gap 2 — isCompletedDropAllowed gate.
// Plan kind + status:complete → true; status:landed → true; any other
// status / kind → false.
// ------------------------------------------------------------------
expectTrue(isCompletedDropAllowed({ kind: "plan", slug: "x", planStatus: "complete" }),
  "Gap 2 — plan w/ status:complete allowed");
expectTrue(isCompletedDropAllowed({ kind: "plan", slug: "x", planStatus: "landed" }),
  "Gap 2 — plan w/ status:landed allowed");
expectFalse(isCompletedDropAllowed({ kind: "plan", slug: "x", planStatus: "active" }),
  "Gap 2 — plan w/ status:active rejected");
expectFalse(isCompletedDropAllowed({ kind: "plan", slug: "x", planStatus: null }),
  "Gap 2 — plan w/ null status rejected");
expectFalse(isCompletedDropAllowed({ kind: "plan", slug: "x", planStatus: "" }),
  "Gap 2 — plan w/ empty status rejected");
expectFalse(isCompletedDropAllowed({ kind: "issue", num: "1", planStatus: "complete" }),
  "Gap 2 — issue kind rejected even with planStatus:complete (no analogous hatch)");
expectFalse(isCompletedDropAllowed(null),
  "Gap 2 — null dragState rejected");

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

# ------------------------------------------------------------------
# Source-level invariants — the override comment must cite #853 / #905
# so a future refactor doesn't silently regress the override without
# updating the rationale block.
# ------------------------------------------------------------------
if grep -q "Completion override (#905" "$APP_JS"; then
  pass "app.js carries the #905 completion-override rationale comment"
else
  fail "app.js missing the #905 completion-override rationale comment"
fi

if grep -q "isCompletedDropAllowed" "$APP_JS"; then
  pass "app.js defines isCompletedDropAllowed gate"
else
  fail "app.js missing isCompletedDropAllowed gate"
fi

# postQueue must consult opts.includeCompletedPlans (don't unconditionally strip).
if grep -q "includeCompletedPlans" "$APP_JS"; then
  pass "postQueue honors includeCompletedPlans opt"
else
  fail "postQueue still unconditionally strips plans.completed"
fi

# Registration check.
if grep -q "test-dashboard-complete-render-drag.sh" "$REPO_ROOT/tests/run-all.sh"; then
  pass "tests/run-all.sh references test-dashboard-complete-render-drag.sh"
else
  fail "tests/run-all.sh missing test-dashboard-complete-render-drag.sh registration"
fi

print_summary_and_exit
