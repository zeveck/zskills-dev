#!/bin/bash
# Tests for the connection-failure debounce in static/app.js
# (Phase 5d, plan docs/plans/DASHBOARD_TABS_AND_RENAME.md).
#
# Exercises setConnected(ok) directly with a minimal DOM stub via node.
# Validates the debounce contract:
#   - a single failure does NOT flip the banner visible
#   - DISCONNECT_FAILURE_THRESHOLD consecutive failures DO flip it
#   - a single subsequent success clears the banner
#
# Stdlib-only: requires node (already a dev-env tool per tests/test-hooks.sh).
#
# Run from repo root: bash tests/test_zskills_dashboard_disconnect_debounce.sh

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

if ! command -v node >/dev/null 2>&1; then
  skip "node not available"
  print_summary_and_exit
fi
if [ ! -f "$APP_JS" ]; then
  fail "app.js exists at expected path"
  print_summary_and_exit
fi

# --- Sanity: debounce constants present in app.js ---
if grep -q 'DISCONNECT_FAILURE_THRESHOLD' "$APP_JS"; then
  pass "DISCONNECT_FAILURE_THRESHOLD constant declared"
else
  fail "DISCONNECT_FAILURE_THRESHOLD missing from app.js"
fi
if grep -q 'connectionFailureCount' "$APP_JS"; then
  pass "connectionFailureCount state variable declared"
else
  fail "connectionFailureCount missing from app.js"
fi

# --- Node-driven contract test ---
# Extract the relevant block from app.js (constant + state var + setConnected
# function) and drive it through three scenarios with a minimal DOM stub.

NODE_OUT=$(APP_JS_PATH="$APP_JS" node - <<'NODE'
const fs = require("fs");
const src = fs.readFileSync(process.env.APP_JS_PATH, "utf8");

// Extract: const DISCONNECT_FAILURE_THRESHOLD ...; let connectionFailureCount...;
// function setConnected(ok) { ... }
function extractRange(src, startRe, endRe) {
  const startMatch = src.match(startRe);
  if (!startMatch) throw new Error("start pattern not found: " + startRe);
  const startIdx = startMatch.index;
  // Find the matching closing brace by counting from the function body.
  // Simpler: search for the next blank line after the function's closing }.
  const after = src.slice(startIdx);
  const endMatch = after.match(endRe);
  if (!endMatch) throw new Error("end pattern not found");
  return after.slice(0, endMatch.index + endMatch[0].length);
}

// Extract from the threshold const through the end of setConnected (closing `}`
// followed by a blank line — robust to function-body line counts).
const block = extractRange(
  src,
  /const DISCONNECT_FAILURE_THRESHOLD/,
  /\nfunction _resetConnectionDebounceForTests\(\) \{[\s\S]*?\n\}/
);

// Minimal DOM stub: $("conn-banner") returns an object with a hidden flag.
const banner = { hidden: true };
function $ (id) {
  if (id === "conn-banner") return banner;
  throw new Error("unexpected DOM lookup: " + id);
}

// Evaluate the extracted block in a fresh scope (sloppy mode so `let` and
// `const` declarations remain accessible to subsequent eval-injected code).
const harness = `
${block}
// Expose to outer scope via globalThis.
globalThis.__setConnected = setConnected;
globalThis.__reset = _resetConnectionDebounceForTests;
globalThis.__threshold = DISCONNECT_FAILURE_THRESHOLD;
`;
// eslint-disable-next-line no-eval
(new Function("$", "globalThis", harness))($, globalThis);

const setConnected = globalThis.__setConnected;
const reset = globalThis.__reset;
const THRESHOLD = globalThis.__threshold;

function expect(actual, expected, label) {
  if (actual !== expected) {
    console.log("FAIL " + label + " (got " + JSON.stringify(actual) +
      ", expected " + JSON.stringify(expected) + ")");
    process.exitCode = 1;
  } else {
    console.log("OK " + label);
  }
}

// Scenario (a): single transient failure does NOT flip the banner.
reset();
banner.hidden = true;
setConnected(false);
expect(banner.hidden, true,
  "single failure with threshold=" + THRESHOLD + " keeps banner hidden");

// Scenario (b): THRESHOLD consecutive failures DO flip the banner.
reset();
banner.hidden = true;
for (let i = 0; i < THRESHOLD; i++) setConnected(false);
expect(banner.hidden, false,
  THRESHOLD + " consecutive failures show banner");

// Scenario (c): a single subsequent success clears the banner.
setConnected(true);
expect(banner.hidden, true,
  "single success after threshold failures clears banner");

// Scenario (d): success resets the failure count.
reset();
banner.hidden = true;
setConnected(false);              // 1 fail
setConnected(true);               // reset
setConnected(false);              // 1 fail (post-reset)
expect(banner.hidden, true,
  "intervening success resets failure count (banner stays hidden)");

// Scenario (e): THRESHOLD is exactly 2 (locked-in expectation).
expect(THRESHOLD, 2,
  "DISCONNECT_FAILURE_THRESHOLD === 2");
NODE
)
NODE_RC=$?

APP_JS_PATH="$APP_JS" NODE_OUT_FOR_GREP="$NODE_OUT"

echo "$NODE_OUT"

# Translate node's OK/FAIL lines into pass/fail.
while IFS= read -r line; do
  case "$line" in
    OK\ *) pass "${line#OK }" ;;
    FAIL\ *) fail "${line#FAIL }" ;;
  esac
done <<< "$NODE_OUT"

if [ "$NODE_RC" != "0" ]; then
  fail "node harness exited non-zero ($NODE_RC)"
fi

print_summary_and_exit
