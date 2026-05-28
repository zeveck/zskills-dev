#!/bin/bash
# Headless sim-logic tests for demo/demo-sim.js (the browser-only JS port of
# the former demo/demo_server.py Simulation). Asserts (no HTTP, no browser —
# pure Simulation logic, run under node):
#   (a) a dragged item persists across a state rebuild (no snap-back)
#   (b) an item placed in Ready picks up a claim and eventually completes
#   (c) the concurrency cap holds (<=N in-flight even with >N in Ready)
#   (d) items NOT in Ready never get a claim or auto-move
#   structural: queues expose completed; demo block advertises interactive/concurrency
#   (lifecycle a-f) clock anchor, seed counts, branch/worktree/activity lifecycle,
#     newest-first activity, landing-mode dimension
#   (eg1-eg4) easter eggs + overachiever
#
# This is the JS-port equivalent of the retired test-demo-server-interactive.sh.
# Equivalent coverage is preserved assertion-for-assertion.
#
# The sim clock uses a monotonic seconds clock; tests fast-forward by rewinding
# sim.startTime (exactly as the Python test rewound start_time), which an
# elapsed()-based clock makes deterministic.
#
# Run from repo root: bash tests/test-demo-sim.sh
# Per CLAUDE.md: the sim is pure logic (no DOM, no async I/O), so a node stub
# harness is faster and just as accurate as a browser run. The browser path is
# exercised separately via playwright-cli against demo/index.html.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SIM_JS="$REPO_ROOT/demo/demo-sim.js"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
skip() { printf '\033[33m  SKIP\033[0m %s\n' "$1"; SKIP_COUNT=$((SKIP_COUNT + 1)); }

print_summary_and_exit() {
  echo ""
  echo "---"
  local total=$((PASS_COUNT + FAIL_COUNT))
  if [ "$FAIL_COUNT" -eq 0 ]; then
    printf '\033[32mResults: %d passed, %d failed\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT"
    exit 0
  else
    printf '\033[31mResults: %d passed, %d failed\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT"
    exit 1
  fi
}

if [ ! -f "$SIM_JS" ]; then
  fail "demo/demo-sim.js exists at expected path"
  print_summary_and_exit
fi

if ! command -v node >/dev/null 2>&1; then
  skip "node not available — demo sim tests skipped"
  print_summary_and_exit
fi

NODE_OUT=$(SIM_JS_PATH="$SIM_JS" node "$SCRIPT_DIR/test-demo-sim.mjs" 2>&1)
NODE_RC=$?

echo "$NODE_OUT"

# Re-emit each node OK/FAIL line through the bash counters so the outer
# run-all.sh parser sees a single canonical Results line from this wrapper.
while IFS= read -r line; do
  case "$line" in
    OK\ *)   pass "${line#OK }" ;;
    FAIL\ *) fail "${line#FAIL }" ;;
  esac
done <<< "$NODE_OUT"

if [ "$NODE_RC" != "0" ] && [ "$FAIL_COUNT" -eq 0 ]; then
  fail "node harness exited non-zero ($NODE_RC) with no per-test failures parsed"
fi

# Registration self-check.
if grep -q "test-demo-sim.sh" "$REPO_ROOT/tests/run-all.sh"; then
  pass "tests/run-all.sh references test-demo-sim.sh"
else
  fail "tests/run-all.sh missing test-demo-sim.sh registration"
fi

print_summary_and_exit
