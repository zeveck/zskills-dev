#!/bin/bash
# Tests for scripts/stop-dev.sh
# Run from repo root: bash tests/test-stop-dev.sh
#
# Contract under test:
#   - no var/dev.pid => exit 0, print "not running"
#   - PIDs in var/dev.pid => SIGTERM each, wait up to GRACE seconds, clear PID file
#   - PID that ignores SIGTERM => exit 1, DO NOT escalate to SIGKILL
#   - Non-numeric / blank entries are skipped, not fatal

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STOP_DEV="$REPO_ROOT/scripts/stop-dev.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; ((PASS_COUNT++)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; ((FAIL_COUNT++)); }

# Each test runs in its own temp "project root" so the script's
# PROJECT_ROOT resolution (based on the script path) is simulated by
# copying stop-dev.sh into a scripts/ dir inside the temp root.
make_fake_root() {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/scripts" "$tmp/var"
  cp "$STOP_DEV" "$tmp/scripts/stop-dev.sh"
  chmod +x "$tmp/scripts/stop-dev.sh"
  echo "$tmp"
}

echo "=== stop-dev.sh behavioral tests ==="

# --- Test 1: No PID file ---
T=$(make_fake_root)
out=$(STOP_DEV_GRACE_SECONDS=1 bash "$T/scripts/stop-dev.sh" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [[ "$out" == *"dev server not running"* ]]; then
  pass "no PID file => exit 0, 'not running'"
else
  fail "no PID file — rc=$rc output: $out"
fi
rm -rf "$T"

# --- Test 2: PID file with a live sleep process that respects SIGTERM ---
T=$(make_fake_root)
sleep 30 &
SLEEP_PID=$!
echo "$SLEEP_PID" > "$T/var/dev.pid"
out=$(STOP_DEV_GRACE_SECONDS=3 bash "$T/scripts/stop-dev.sh" 2>&1)
rc=$?
# Give the kernel a moment to reap
sleep 0.2
if [ "$rc" -eq 0 ] && ! kill -0 "$SLEEP_PID" 2>/dev/null && [ ! -f "$T/var/dev.pid" ]; then
  pass "live PID stopped via SIGTERM, PID file removed"
else
  fail "live PID — rc=$rc still_alive=$(kill -0 $SLEEP_PID 2>/dev/null && echo yes || echo no) pid_file_exists=$([ -f "$T/var/dev.pid" ] && echo yes || echo no) output: $out"
  # Cleanup if test failed
  kill -TERM "$SLEEP_PID" 2>/dev/null
fi
rm -rf "$T"

# --- Test 3: PID file with a PID that's already dead ---
T=$(make_fake_root)
# Spawn and reap a quick process to get a PID that will be dead by the time the script reads it
sh -c 'true' &
DEAD_PID=$!
wait "$DEAD_PID" 2>/dev/null
echo "$DEAD_PID" > "$T/var/dev.pid"
out=$(STOP_DEV_GRACE_SECONDS=1 bash "$T/scripts/stop-dev.sh" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [[ "$out" == *"already gone"* ]] && [ ! -f "$T/var/dev.pid" ]; then
  pass "already-dead PID => exit 0, reported, PID file cleaned"
else
  fail "already-dead PID — rc=$rc output: $out pid_file_exists=$([ -f "$T/var/dev.pid" ] && echo yes || echo no)"
fi
rm -rf "$T"

# --- Test 4: PID that ignores SIGTERM — must report and exit 1, NOT escalate to SIGKILL ---
T=$(make_fake_root)
# Bash that traps and ignores SIGTERM, sleeps long enough to outlive the test
bash -c 'trap "" TERM; sleep 30' &
IGNORE_PID=$!
# Give the trap a moment to install
sleep 0.3
echo "$IGNORE_PID" > "$T/var/dev.pid"
out=$(STOP_DEV_GRACE_SECONDS=2 bash "$T/scripts/stop-dev.sh" 2>&1)
rc=$?
if [ "$rc" -eq 1 ] && [[ "$out" == *"still running"* ]] && [[ "$out" == *"not escalating"* ]] && kill -0 "$IGNORE_PID" 2>/dev/null; then
  pass "SIGTERM-ignoring PID => exit 1, reported, no escalation"
else
  fail "SIGTERM-ignoring PID — rc=$rc still_alive=$(kill -0 $IGNORE_PID 2>/dev/null && echo yes || echo no) output: $out"
fi
# Hard-cleanup the stubborn process (the test itself is allowed to use SIGKILL; the script is not)
kill -KILL "$IGNORE_PID" 2>/dev/null
wait "$IGNORE_PID" 2>/dev/null
rm -rf "$T"

# --- Test 5: Blank lines and non-numeric entries are tolerated ---
T=$(make_fake_root)
sleep 30 &
SLEEP_PID=$!
{
  echo ""
  echo "  "
  echo "not-a-pid"
  echo "$SLEEP_PID"
  echo ""
} > "$T/var/dev.pid"
out=$(STOP_DEV_GRACE_SECONDS=3 bash "$T/scripts/stop-dev.sh" 2>&1)
rc=$?
sleep 0.2
if [ "$rc" -eq 0 ] && ! kill -0 "$SLEEP_PID" 2>/dev/null && [[ "$out" == *"skipping non-numeric"* ]]; then
  pass "blank/non-numeric entries skipped; real PID still killed"
else
  fail "blank/non-numeric — rc=$rc still_alive=$(kill -0 $SLEEP_PID 2>/dev/null && echo yes || echo no) output: $out"
  kill -TERM "$SLEEP_PID" 2>/dev/null
fi
rm -rf "$T"

# --- Test 6: Empty PID file (no entries) ---
T=$(make_fake_root)
: > "$T/var/dev.pid"
out=$(STOP_DEV_GRACE_SECONDS=1 bash "$T/scripts/stop-dev.sh" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [[ "$out" == *"no PIDs"* ]] && [ ! -f "$T/var/dev.pid" ]; then
  pass "empty PID file => exit 0, cleaned"
else
  fail "empty PID file — rc=$rc output: $out"
fi
rm -rf "$T"

# --- Test 7: Multiple live PIDs (concurrently-style) ---
T=$(make_fake_root)
sleep 30 &
PID_A=$!
sleep 30 &
PID_B=$!
{ echo "$PID_A"; echo "$PID_B"; } > "$T/var/dev.pid"
out=$(STOP_DEV_GRACE_SECONDS=3 bash "$T/scripts/stop-dev.sh" 2>&1)
rc=$?
sleep 0.2
if [ "$rc" -eq 0 ] && ! kill -0 "$PID_A" 2>/dev/null && ! kill -0 "$PID_B" 2>/dev/null && [ ! -f "$T/var/dev.pid" ]; then
  pass "multiple live PIDs all stopped"
else
  fail "multiple live — rc=$rc a_alive=$(kill -0 $PID_A 2>/dev/null && echo yes || echo no) b_alive=$(kill -0 $PID_B 2>/dev/null && echo yes || echo no) output: $out"
  kill -TERM "$PID_A" "$PID_B" 2>/dev/null
fi
rm -rf "$T"

echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
