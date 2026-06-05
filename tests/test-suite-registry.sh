#!/bin/bash
# tests/test-suite-registry.sh — self-test for tests/lib/suite-registry.sh
# (TEST_SUITE_PARALLELIZATION Phase 0).
#
# list_registered_suites STATICALLY parses the `run_suite "<name>" "<path>"`
# registration lines out of run-all.sh so a parallel runner can fan the same
# suite set the serial runner runs. This suite pins that contract:
#   1. The `run_suite() {` function-DEFINITION line is EXCLUDED.
#   2. tests/test-plugin-live-load.sh (registered twice via the attended
#      if/else) is DEDUPED to a single entry.
#   3. The 3 conditional/gated suites are reported by list_conditional_suites
#      as METADATA (gate + path), and the two purely-conditional ones
#      (race-isolation, e2e) are NOT in the unconditional list.
#   4. A handful of known-registered suites ARE present (explicit
#      enumeration — NOT a raw `grep -c '^[[:space:]]*run_suite'` count, which
#      is 208 and wrong because it includes the function-def line and the
#      double live-load registration).
#   5. The parser does NOT execute run-all.sh (static parse only).
#
# If any of these break, a parallel runner would fan the wrong suite set;
# this suite is the tripwire.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=tests/lib/suite-registry.sh
. "$SCRIPT_DIR/lib/suite-registry.sh"

PASS=0
FAIL=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

SUITES="$(list_registered_suites)"

# ── 1. function-def line excluded ─────────────────────────────────────
# The bare token `run_suite` (the function definition `run_suite() {`) must
# never appear as a suite path.
if printf '%s\n' "$SUITES" | grep -qx 'run_suite'; then
  fail "[funcdef] excluded" "bare 'run_suite' leaked as a suite entry"
elif printf '%s\n' "$SUITES" | grep -q '() {'; then
  fail "[funcdef] excluded" "function-def fragment leaked as a suite entry"
else
  pass "[funcdef] run_suite() function-definition line excluded"
fi

# ── 2. live-load deduped to exactly one entry ─────────────────────────
LIVE_COUNT="$(printf '%s\n' "$SUITES" | grep -c '^tests/test-plugin-live-load\.sh$')"
if [ "$LIVE_COUNT" -eq 1 ]; then
  pass "[dedupe] test-plugin-live-load.sh appears exactly once (registered twice)"
else
  fail "[dedupe] live-load count" "expected 1, got $LIVE_COUNT"
fi

# ── 3. conditional suites are metadata; race/e2e NOT in unconditional ─
COND="$(list_conditional_suites)"
# Expect exactly the 3 gated registrations, tab-separated gate<TAB>path.
expected_cond=$'RUN_RACE_TESTS\ttests/test-fixture-race-isolation.sh\nRUN_E2E\ttests/e2e-parallel-pipelines.sh\nattended\ttests/test-plugin-live-load.sh'
if [ "$COND" = "$expected_cond" ]; then
  pass "[metadata] list_conditional_suites returns the 3 gated suites with gate tags"
else
  fail "[metadata] conditional set" "got: $(printf '%s' "$COND" | tr '\n' '|')"
fi

# The two purely-conditional suites must NOT be in the unconditional list.
if printf '%s\n' "$SUITES" | grep -qx 'tests/test-fixture-race-isolation.sh'; then
  fail "[metadata] race-isolation excluded" "RUN_RACE_TESTS suite leaked into unconditional list"
else
  pass "[metadata] test-fixture-race-isolation.sh kept OUT of unconditional list"
fi
if printf '%s\n' "$SUITES" | grep -qx 'tests/e2e-parallel-pipelines.sh'; then
  fail "[metadata] e2e excluded" "RUN_E2E suite leaked into unconditional list"
else
  pass "[metadata] e2e-parallel-pipelines.sh kept OUT of unconditional list"
fi

# ── 4. explicit enumeration of known-registered suites ────────────────
# NOT a raw grep -c. Each of these is a real run_suite registration; assert
# presence by exact path.
for known in \
  tests/test-hooks-block-unsafe.sh \
  tests/test-hooks-bypass-generic.sh \
  tests/test-hooks-bypass-project.sh \
  tests/test-hooks-main-protected.sh \
  tests/test-hooks-worktree-cd.sh \
  tests/test-hooks-agent.sh \
  tests/test-hooks-warn-drift.sh \
  tests/test-hooks-misc.sh \
  tests/test-skill-conformance.sh \
  tests/test-do.sh \
  tests/test-fix-issues.sh \
  tests/test-parse-results.sh \
  tests/test-suite-registry.sh \
  tests/test-plugin-live-load.sh \
  tests/test-switch-install-path.sh ; do
  if printf '%s\n' "$SUITES" | grep -qx "$known"; then
    pass "[enum] $known is in the registered set"
  else
    fail "[enum] $known" "expected in registered set, absent"
  fi
done

# Sanity: the unconditional count must be well below the naive raw count of
# 208 (`grep -c '^[[:space:]]*run_suite' run-all.sh`), proving the function-def
# line and the double live-load registration were collapsed — and at least
# the bulk of the suites survived.
COUNT="$(printf '%s\n' "$SUITES" | grep -c .)"
RAW="$(grep -c '^[[:space:]]*run_suite' "$REPO_ROOT/tests/run-all.sh")"
if [ "$COUNT" -lt "$RAW" ] && [ "$COUNT" -gt 150 ]; then
  pass "[count] distinct unconditional count ($COUNT) < raw grep count ($RAW)"
else
  fail "[count] distinct vs raw" "distinct=$COUNT raw=$RAW (expected 150 < distinct < raw)"
fi

# ── 4b. serial-only bucket (Phase 3 + Phase 4) ────────────────────────
# list_serial_suites reports the genuinely-unparallelizable suites as
# "serial<TAB>path", and is_serial_suite is the matching predicate. The set:
# the LIVE-SERVER class (monitor_server + csrf + dashboard_ui +
# dashboard_skill + state-queue + pid-file-self-heal — each boots a real HTTP
# server on a contendable port) plus the attended live-load (global throttle
# marker + live `claude`). All MUST still be present in the unconditional
# registered set (they are unconditional registrations; the parallel runner
# SUBTRACTS the serial bucket to form the parallel pool — it does not depend
# on them being absent from the list). live-load is kept LAST so the run-all.sh
# serial driver's plain-vs-attended split reads cleanly (the driver matches by
# path, not order). Phase 4 widened this set from 2 → 7 to fix the
# dashboard_skill port-collision flake and proactively pin its siblings.
SERIAL="$(list_serial_suites)"
expected_serial=$'serial\ttests/test_zskills_monitor_server.sh\nserial\ttests/test_zskills_monitor_csrf.sh\nserial\ttests/test_zskills_monitor_dashboard_ui.sh\nserial\ttests/test_zskills_dashboard_skill.sh\nserial\ttests/test-monitor-state-queue-post-preservation.sh\nserial\ttests/test-pid-file-self-heal.sh\nserial\ttests/test-plugin-live-load.sh'
if [ "$SERIAL" = "$expected_serial" ]; then
  pass "[serial] list_serial_suites returns the live-server class + attended live-load with serial tag"
else
  fail "[serial] serial set" "got: $(printf '%s' "$SERIAL" | tr '\n' '|')"
fi

# is_serial_suite predicate: true for every serial path, false for an
# arbitrary parallel-pool suite.
for _ss in \
  tests/test_zskills_monitor_server.sh \
  tests/test_zskills_monitor_csrf.sh \
  tests/test_zskills_monitor_dashboard_ui.sh \
  tests/test_zskills_dashboard_skill.sh \
  tests/test-monitor-state-queue-post-preservation.sh \
  tests/test-pid-file-self-heal.sh \
  tests/test-plugin-live-load.sh; do
  if is_serial_suite "$_ss"; then
    pass "[serial] is_serial_suite true for $_ss"
  else
    fail "[serial] is_serial_suite $_ss" "expected true, got false"
  fi
done
if is_serial_suite "tests/test-do.sh"; then
  fail "[serial] is_serial_suite test-do.sh" "expected false (parallel-pool suite), got true"
else
  pass "[serial] is_serial_suite false for a parallel-pool suite (test-do.sh)"
fi
# test-plan-skip-clear-paths.sh boots a live server too, but on an EPHEMERAL
# OS-assigned port (bind 0) so it is collision-safe and stays in the pool —
# it must NOT be pinned serial.
if is_serial_suite "tests/test-plan-skip-clear-paths.sh"; then
  fail "[serial] is_serial_suite plan-skip-clear-paths" "expected false (ephemeral-port, pool-safe), got true"
else
  pass "[serial] is_serial_suite false for ephemeral-port live-server suite (plan-skip-clear-paths)"
fi

# Every serial suite must still be present in the unconditional registered set
# (the parallel runner relies on subtracting the serial bucket, NOT on their
# absence). All are plain unconditional registrations except live-load, which
# is the deduped attended registration.
for _ss in \
  tests/test_zskills_monitor_server.sh \
  tests/test_zskills_monitor_csrf.sh \
  tests/test_zskills_monitor_dashboard_ui.sh \
  tests/test_zskills_dashboard_skill.sh \
  tests/test-monitor-state-queue-post-preservation.sh \
  tests/test-pid-file-self-heal.sh \
  tests/test-plugin-live-load.sh; do
  if printf '%s\n' "$SUITES" | grep -qx "$_ss"; then
    pass "[serial] $_ss still present in unconditional registered set"
  else
    fail "[serial] $_ss in registered set" "expected present, absent"
  fi
done

# serial_run_attended_live_load carries the attended-gate decision VERBATIM
# and runs the suite EXACTLY ONCE. Drive the gate purely via env (no live
# claude): force capability ON + a fresh throttle marker that is OLD enough to
# pass, then assert the gate-pass branch fired (ZSKILLS_LIVE_ATTENDED=1 set for
# the single call) and the marker was refreshed. Use a fake run_suite stub
# that records the call count + the flag it saw.
GATE_TMP=$(mktemp -d)
GATE_MARKER="$GATE_TMP/.zskills/last-attended-plugin-run"
mkdir -p "$(dirname "$GATE_MARKER")"
echo "1" > "$GATE_MARKER"            # epoch 1 → ancient → throttle elapsed
CALL_LOG="$GATE_TMP/calls"; : > "$CALL_LOG"
fake_run_suite() {
  # Record: which suite + whether ZSKILLS_LIVE_ATTENDED reached this call.
  printf '%s\tlive=%s\n' "$2" "${ZSKILLS_LIVE_ATTENDED:-unset}" >> "$CALL_LOG"
}
(
  export HOME="$GATE_TMP"
  export ZSKILLS_GATE_FORCE_CLAUDE=1 ZSKILLS_GATE_FORCE_CREDS=1
  export ZSKILLS_ATTENDED_THROTTLE_SECONDS=1
  serial_run_attended_live_load fake_run_suite >/dev/null 2>&1
)
GATE_CALLS=$(grep -c . "$CALL_LOG" || echo 0)
GATE_LIVE_LINE=$(grep -c 'live=1' "$CALL_LOG" || echo 0)
GATE_MARKER_VAL=$(cat "$GATE_TMP/.zskills/last-attended-plugin-run" 2>/dev/null || echo "")
if [ "$GATE_CALLS" -eq 1 ] && [ "$GATE_LIVE_LINE" -eq 1 ]; then
  pass "[serial] serial_run_attended_live_load runs live-load ONCE with gate PASS (ZSKILLS_LIVE_ATTENDED=1)"
else
  fail "[serial] gate-pass branch" "calls=$GATE_CALLS live=1-lines=$GATE_LIVE_LINE (expected 1 call, 1 live)"
fi
# Marker must have been refreshed to a fresh epoch (no longer the ancient '1').
if [ -n "$GATE_MARKER_VAL" ] && [ "$GATE_MARKER_VAL" != "1" ]; then
  pass "[serial] gate-pass refreshes the throttle marker"
else
  fail "[serial] marker refresh" "marker='$GATE_MARKER_VAL' (expected fresh epoch, not '1')"
fi

# Gate-FAIL branch: force capability OFF → plain branch, ONE call, no flag.
CALL_LOG2="$GATE_TMP/calls2"; : > "$CALL_LOG2"
fake_run_suite2() { printf '%s\tlive=%s\n' "$2" "${ZSKILLS_LIVE_ATTENDED:-unset}" >> "$CALL_LOG2"; }
(
  export HOME="$GATE_TMP"
  export ZSKILLS_GATE_FORCE_CLAUDE=0 ZSKILLS_GATE_FORCE_CREDS=0
  serial_run_attended_live_load fake_run_suite2 >/dev/null 2>&1
)
GATE2_CALLS=$(grep -c . "$CALL_LOG2" || echo 0)
GATE2_UNSET=$(grep -c 'live=unset' "$CALL_LOG2" || echo 0)
if [ "$GATE2_CALLS" -eq 1 ] && [ "$GATE2_UNSET" -eq 1 ]; then
  pass "[serial] serial_run_attended_live_load runs live-load ONCE on gate FAIL (no ZSKILLS_LIVE_ATTENDED)"
else
  fail "[serial] gate-fail branch" "calls=$GATE2_CALLS unset-lines=$GATE2_UNSET (expected 1 call, 1 unset)"
fi
rm -rf "$GATE_TMP"

# ── 5. parser must NOT execute run-all.sh ─────────────────────────────
# Poison run-all by making its execution observably fail: copy it to a temp
# fixture, prepend an `exit 7 / touch SENTINEL` that WOULD fire if sourced or
# run, point the lib at it, and confirm the parse still yields entries without
# the sentinel existing. We do this by re-deriving the runall path via an
# isolated copy of the lib in a temp dir.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/lib"
cp "$SCRIPT_DIR/lib/suite-registry.sh" "$TMP/lib/suite-registry.sh"
SENTINEL="$TMP/EXECUTED"
{
  echo '#!/bin/bash'
  echo "touch \"$SENTINEL\""   # fires ONLY if run-all.sh is executed/sourced
  echo 'run_suite "alpha" "tests/alpha.sh"'
  echo 'run_suite "beta" "tests/beta.sh"'
} > "$TMP/run-all.sh"

# Source the copied lib so _suite_registry_runall resolves to $TMP/run-all.sh.
(
  . "$TMP/lib/suite-registry.sh"
  out="$(list_registered_suites)"
  echo "$out" > "$TMP/out.txt"
)
if [ -f "$SENTINEL" ]; then
  fail "[static] no-execute" "run-all.sh was executed/sourced (sentinel created)"
elif grep -qx 'tests/alpha.sh' "$TMP/out.txt" && grep -qx 'tests/beta.sh' "$TMP/out.txt"; then
  pass "[static] parses run-all.sh statically without executing it"
else
  fail "[static] parse" "expected alpha/beta paths; got: $(tr '\n' '|' < "$TMP/out.txt")"
fi

echo ""
echo "---"
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (of %d)\033[0m\n' "$PASS" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (of %d)\033[0m\n' "$PASS" "$FAIL" "$TOTAL"
  exit 1
fi
