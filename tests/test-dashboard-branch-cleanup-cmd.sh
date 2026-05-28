#!/bin/bash
# Tests for the dashboard Branches-tab bulk bar emitting a runnable
# /cleanup-merged command (issue #717 follow-up: pick-and-choose cleanup).
#
# The bulk bar used to copy bare branch names; it now copies a runnable
# `/cleanup-merged <mode> apply <names>` command. The mode is driven by the
# section bucket: `remote-only` -> remote; local buckets -> local.
#
# Strategy:
#   Static-grep: the handler builds a command, the helper exists, and the
#   protected-defensive-exclusion is wired.
#   Behavioral (node): extract buildCleanupMergedCommand and assert the
#   exact string per bucket.
#
# Run from repo root: bash tests/test-dashboard-branch-cleanup-cmd.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_JS="$REPO_ROOT/skills/zskills-dashboard/scripts/zskills_monitor/static/app.js"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }
skip() { printf '\033[33m  SKIP\033[0m %s\n' "$1"; SKIP_COUNT=$((SKIP_COUNT+1)); }

print_summary_and_exit() {
  echo ""
  echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed, $SKIP_COUNT skipped"
  [ "$FAIL_COUNT" -eq 0 ] && exit 0 || exit 1
}

echo "=== dashboard Branches bulk bar — /cleanup-merged command emission ==="

if [ ! -f "$APP_JS" ]; then
  fail "app.js exists"
  print_summary_and_exit
fi

# ── Static-grep ──────────────────────────────────────────────────────

# Bulk-copy handler builds the command via the helper.
if grep -q 'buildCleanupMergedCommand(sectionKey, names)' "$APP_JS"; then
  pass "branch-bulk-copy handler calls buildCleanupMergedCommand"
else
  fail "branch-bulk-copy handler does not build /cleanup-merged command"
fi

# Helper function present and emits a /cleanup-merged command.
if grep -q 'function buildCleanupMergedCommand' "$APP_JS" \
   && grep -q '"/cleanup-merged "' "$APP_JS"; then
  pass "buildCleanupMergedCommand helper emits /cleanup-merged command"
else
  fail "buildCleanupMergedCommand helper missing or wrong"
fi

# Mode is driven by the remote-only bucket.
if grep -q 'sectionKey === "remote-only" ? "remote" : "local"' "$APP_JS"; then
  pass "mode is driven by the remote-only bucket (else local)"
else
  fail "mode-from-bucket logic missing"
fi

# Defensive protected exclusion in the handler.
if grep -q 'getAttribute("data-protected") === "true"' "$APP_JS"; then
  pass "handler defensively excludes data-protected branches"
else
  fail "handler does not exclude protected branches defensively"
fi

# Protected checkbox carries data-protected.
if grep -q 'cbAttrs\["data-protected"\] = "true"' "$APP_JS"; then
  pass "protected branch checkbox carries data-protected"
else
  fail "protected branch checkbox does not carry data-protected"
fi

# ── Behavioral (node) ────────────────────────────────────────────────
if ! command -v node >/dev/null 2>&1; then
  skip "node not available — command-emission behavioral test skipped"
  print_summary_and_exit
fi

NODE_OUT=$(APP_JS_PATH="$APP_JS" node - <<'NODE'
const fs = require("fs");
const src = fs.readFileSync(process.env.APP_JS_PATH, "utf8");

function extractBlock(text, startRe, endMarker) {
  const m = text.match(startRe);
  if (!m) throw new Error("start pattern not found: " + startRe);
  const tail = text.slice(m.index);
  const endIdx = tail.indexOf(endMarker);
  if (endIdx < 0) throw new Error("end marker not found: " + endMarker);
  return tail.slice(0, endIdx + endMarker.length);
}

const helperBlock = extractBlock(src, /\nfunction buildCleanupMergedCommand\(/, "\n}\n");
const harness = helperBlock + "\nglobalThis.__buildCmd = buildCleanupMergedCommand;\n";
(new Function("globalThis", harness))(globalThis);
const buildCmd = globalThis.__buildCmd;

function expect(actual, expected, label) {
  if (actual !== expected) {
    console.log("FAIL " + label + " (got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected) + ")");
    process.exitCode = 1;
  } else {
    console.log("OK " + label);
  }
}

// Local buckets -> local apply.
expect(buildCmd("active", ["feat/a", "feat/b"]),
  "/cleanup-merged local apply feat/a feat/b", "active bucket -> local apply");
expect(buildCmd("landed", ["feat/x"]),
  "/cleanup-merged local apply feat/x", "landed bucket -> local apply");
expect(buildCmd("local", ["wip/1", "wip/2"]),
  "/cleanup-merged local apply wip/1 wip/2", "local bucket -> local apply");

// remote-only bucket -> remote apply.
expect(buildCmd("remote-only", ["origin-feat", "old-branch"]),
  "/cleanup-merged remote apply origin-feat old-branch", "remote-only bucket -> remote apply");
NODE
)
NODE_RC=$?

echo "$NODE_OUT" | sed 's/^/    /'
OK_N=$(echo "$NODE_OUT" | grep -c '^OK ')
FAIL_N=$(echo "$NODE_OUT" | grep -c '^FAIL ')

if [ "$NODE_RC" -eq 0 ] && [ "$FAIL_N" -eq 0 ] && [ "$OK_N" -ge 4 ]; then
  pass "behavioral: buildCleanupMergedCommand emits correct string per bucket ($OK_N checks)"
else
  fail "behavioral: command-emission mismatch (rc=$NODE_RC, ok=$OK_N, fail=$FAIL_N)"
fi

print_summary_and_exit
