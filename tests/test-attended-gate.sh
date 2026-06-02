#!/usr/bin/env bash
# tests/test-attended-gate.sh
#
# Deterministic unit test for the #991 capability-gate + throttle decision in
# tests/lib/attended-gate.sh. Exercises every branch of
# attended_gate_should_run WITHOUT a live `claude` CLI or real credentials —
# capability presence is injected via the ZSKILLS_GATE_FORCE_CLAUDE /
# ZSKILLS_GATE_FORCE_CREDS env overrides, and the throttle is driven with a
# synthetic "now" epoch and a temp marker file.
#
# No jq — Python json per `## Python is required` (not needed here).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$REPO_ROOT/tests/lib/attended-gate.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

echo "=== attended-gate (#991 capability-gate + throttle) ==="

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

THROTTLE=14400           # ~4h, same default as run-all.sh
NOW=1000000             # synthetic "now" epoch

# Helper: assert the gate decision. Usage:
#   expect_gate <expected: run|skip> <description> <marker_path>
# Capability is set by the caller via the FORCE env overrides.
expect_gate() {
  local expected="$1" desc="$2" marker="$3"
  if attended_gate_should_run "$marker" "$NOW" "$THROTTLE"; then
    local got="run"
  else
    local got="skip"
  fi
  if [ "$got" = "$expected" ]; then
    pass "$desc (gate=$got)"
  else
    fail "$desc — expected gate=$expected, got gate=$got"
  fi
}

# ── Branch 1: claude absent → gate FALSE (SKIP), regardless of creds/marker ──
# This is the CI path. No marker present (would otherwise be stale → run).
ZSKILLS_GATE_FORCE_CLAUDE=0 ZSKILLS_GATE_FORCE_CREDS=1 \
  expect_gate skip "claude absent → SKIP (CI path)" "$TMP/marker-noclaude"

# ── Branch 2: creds absent → gate FALSE (SKIP), even with claude present ──────
ZSKILLS_GATE_FORCE_CLAUDE=1 ZSKILLS_GATE_FORCE_CREDS=0 \
  expect_gate skip "creds absent → SKIP" "$TMP/marker-nocreds"

# ── Branch 3: marker FRESH (within window) → gate FALSE (throttled) ──────────
# Write a marker timestamped just inside the throttle window.
FRESH_MARKER="$TMP/marker-fresh"
printf '%s\n' "$((NOW - THROTTLE + 60))" > "$FRESH_MARKER"
ZSKILLS_GATE_FORCE_CLAUDE=1 ZSKILLS_GATE_FORCE_CREDS=1 \
  expect_gate skip "claude+creds present, marker fresh → SKIP (throttled)" "$FRESH_MARKER"

# ── Branch 4a: marker STALE (older than window) + claude + creds → gate TRUE ──
STALE_MARKER="$TMP/marker-stale"
printf '%s\n' "$((NOW - THROTTLE - 60))" > "$STALE_MARKER"
ZSKILLS_GATE_FORCE_CLAUDE=1 ZSKILLS_GATE_FORCE_CREDS=1 \
  expect_gate run "claude+creds present, marker stale → RUN" "$STALE_MARKER"

# ── Branch 4b: marker ABSENT (never run) + claude + creds → gate TRUE ─────────
ZSKILLS_GATE_FORCE_CLAUDE=1 ZSKILLS_GATE_FORCE_CREDS=1 \
  expect_gate run "claude+creds present, marker absent → RUN (never run yet)" "$TMP/marker-absent"

# ── Extra: malformed (non-numeric) marker is treated as stale → RUN ──────────
BAD_MARKER="$TMP/marker-bad"
printf '%s\n' "garbage" > "$BAD_MARKER"
ZSKILLS_GATE_FORCE_CLAUDE=1 ZSKILLS_GATE_FORCE_CREDS=1 \
  expect_gate run "claude+creds present, marker malformed → RUN (treated as stale)" "$BAD_MARKER"

# ── refresh_marker writes a numeric epoch and creates the parent dir ─────────
REFRESH_MARKER="$TMP/newdir/last-attended-plugin-run"
attended_gate_refresh_marker "$REFRESH_MARKER" "$NOW"
if [ -f "$REFRESH_MARKER" ] && [ "$(cat "$REFRESH_MARKER")" = "$NOW" ]; then
  pass "refresh_marker creates parent dir and writes the epoch"
else
  fail "refresh_marker — expected $NOW at $REFRESH_MARKER, got '$(cat "$REFRESH_MARKER" 2>/dev/null)'"
fi

# ── End-to-end throttle: after a refresh, an immediate re-check SKIPs ─────────
ZSKILLS_GATE_FORCE_CLAUDE=1 ZSKILLS_GATE_FORCE_CREDS=1 \
  expect_gate skip "after refresh at NOW, immediate re-check → SKIP (throttled)" "$REFRESH_MARKER"

echo ""
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '\033[32mResults: %d passed, %d failed\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT"
else
  printf '\033[31mResults: %d passed, %d failed\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT"
  exit 1
fi
