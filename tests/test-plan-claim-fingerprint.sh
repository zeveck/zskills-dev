#!/bin/bash
# Tests for fingerprintPlans claim-state regression (Phase 3 of
# plans/plans-claim-chip-parity.md, W3.14).
#
# W3.3 contract (post-#684 cleanup): fingerprintPlans includes
# `[claim.pipeline_id, claim.current_phase]` per plan row. Phase
# advances drive re-renders so the chip's `phase N/M` segment updates
# as the pipeline progresses. (Prior to #684, the second tuple element
# was last_heartbeat_at — now removed as a duplicate of started_at.)
#
# This test verifies fingerprint output differs for (no claim, pending
# claim with null fields, full claim, full claim with phase advance).
#
# Run from repo root: bash tests/test-plan-claim-fingerprint.sh

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

# Static grep: fingerprintPlans references current_phase (post-#684
# cleanup — phase advances drive re-renders).
if grep -A 30 "function fingerprintPlans" "$APP_JS" | grep -q 'current_phase'; then
  pass "fingerprintPlans includes claim.current_phase (chip re-renders on phase advance)"
else
  fail "fingerprintPlans does NOT include claim.current_phase — chip won't re-render on phase advance"
fi

if grep -A 30 "function fingerprintPlans" "$APP_JS" | grep -q 'pipeline_id'; then
  pass "fingerprintPlans includes claim.pipeline_id"
else
  fail "fingerprintPlans missing claim.pipeline_id reference"
fi

if ! command -v node >/dev/null 2>&1; then
  skip "node not available — fingerprint dispatch test skipped"
  print_summary_and_exit
fi

NODE_OUT=$(APP_JS_PATH="$APP_JS" node - <<'NODE'
const fs = require("fs");
const src = fs.readFileSync(process.env.APP_JS_PATH, "utf8");

function extractBlock(text, startRe, endMarker) {
  const m = text.match(startRe);
  if (!m) throw new Error("start pattern not found: " + startRe);
  const startIdx = m.index;
  const tail = text.slice(startIdx);
  const endIdx = tail.indexOf(endMarker);
  if (endIdx < 0) throw new Error("end marker not found: " + endMarker);
  return tail.slice(0, endIdx + endMarker.length);
}

// PLAN_COLUMNS const required by fingerprintPlans.
const planColumnsMatch = src.match(/const\s+PLAN_COLUMNS\s*=\s*\[[^\]]*\];/);
if (!planColumnsMatch) throw new Error("PLAN_COLUMNS const not found");
const fingerprintBlock = extractBlock(src, /\nfunction fingerprintPlans\(/, "\n}\n");

const harness = `
${planColumnsMatch[0]}

${fingerprintBlock}

globalThis.__fingerprintPlans = fingerprintPlans;
`;
(new Function("globalThis", harness))(globalThis);
const fingerprintPlans = globalThis.__fingerprintPlans;

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

// ------------------------------------------------------------------
// 4 snapshots of plan slug=foo: no-claim, pending-claim, full-claim,
// full-claim-phase-advanced. All four must produce distinct
// fingerprints.
// ------------------------------------------------------------------
const queues = {
  plans: {
    drafted: [], reviewed: [],
    ready: [{ slug: "foo", mode: "phase" }],
    "in-progress": [], done: [],
  },
};
const base = {
  slug: "foo", title: "Same", status: "active",
  phase_count: 5, phases_done: 0, blurb: "",
  queue: { column: "ready", index: 0, mode: "phase" },
};
const noClaim = { ...base };
const pendingClaim = {
  ...base,
  claim: {
    pipeline_id: null, started_at: null,
    current_phase: null, age_seconds: null, pipeline_short: null,
  },
};
const fullClaim = {
  ...base,
  claim: {
    pipeline_id: "run-plan.foo",
    started_at: "2026-05-22T01:00:00+00:00",
    current_phase: "Phase 2",
    age_seconds: 60,
    pipeline_short: "foo-abc",
  },
};
const fullClaimPhaseAdvanced = {
  ...base,
  claim: {
    pipeline_id: "run-plan.foo",
    started_at: "2026-05-22T01:00:00+00:00",
    // current_phase moved forward — simulates a phase boundary
    // emission between dashboard polls.
    current_phase: "Phase 3",
    age_seconds: 60,
    pipeline_short: "foo-abc",
  },
};

const fpNo      = fingerprintPlans([noClaim],                 queues, "phase");
const fpPending = fingerprintPlans([pendingClaim],            queues, "phase");
const fpFull    = fingerprintPlans([fullClaim],               queues, "phase");
const fpFullAdv = fingerprintPlans([fullClaimPhaseAdvanced],  queues, "phase");

expectTrue(fpNo !== fpPending,
  "fingerprint differs between no-claim and pending-claim");
expectTrue(fpPending !== fpFull,
  "fingerprint differs between pending-claim and full-claim");
expectTrue(fpNo !== fpFull,
  "fingerprint differs between no-claim and full-claim");
expectTrue(fpFull !== fpFullAdv,
  "fingerprint differs after phase advance (chip re-renders so phase N/M updates)");

// Stability: same input shape → same fingerprint.
const fpFull2 = fingerprintPlans([fullClaim], queues, "phase");
expect(fpFull, fpFull2, "fingerprintPlans stable across repeated calls");

// Deterministic on identical input — no spurious churn.
const fpFull3 = fingerprintPlans([fullClaim], queues, "phase");
const fpFull4 = fingerprintPlans([fullClaim], queues, "phase");
expect(fpFull3, fpFull4, "fingerprintPlans deterministic on identical input");
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

if grep -q "test-plan-claim-fingerprint.sh" "$REPO_ROOT/tests/run-all.sh"; then
  pass "tests/run-all.sh references test-plan-claim-fingerprint.sh"
else
  fail "tests/run-all.sh missing test-plan-claim-fingerprint.sh registration"
fi

print_summary_and_exit
