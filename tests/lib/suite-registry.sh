# tests/lib/suite-registry.sh — registered-suite enumerator for the serial
# (run-all.sh) and the future parallel suite runners.
#
# SOURCEABLE LIBRARY, NOT A SUITE. Do NOT register in run-all.sh as a
# `run_suite`. `tests/test-suite-registry.sh` is the registered self-test
# that exercises these functions.
#
# Statically parses the `run_suite "<name>" "<path>"` registration lines out
# of tests/run-all.sh WITHOUT executing it, so a parallel runner can fan the
# same set of suites the serial runner runs. The parse:
#   (a) EXCLUDES the `run_suite() {` function-definition line.
#   (b) DEDUPES tests/test-plugin-live-load.sh, which is registered twice via
#       the attended-gate if/else (one ZSKILLS_LIVE_ATTENDED=1 arm, one
#       plain arm) — it is one suite, counted once.
#   (c) Treats the 3 conditional/gated suites as METADATA, not bare entries:
#         RUN_RACE_TESTS  → tests/test-fixture-race-isolation.sh
#         RUN_E2E         → tests/e2e-parallel-pipelines.sh
#         attended        → tests/test-plugin-live-load.sh
#       (test-plugin-live-load.sh is ALSO an unconditional suite — it always
#       runs, gated only on whether §B runs live — so it appears in the
#       unconditional list AND is flagged here as attended-gated metadata.)
#
# Resolve the path to run-all.sh relative to THIS file so callers in any cwd
# get the right registry.
_suite_registry_runall() {
  local self_dir
  self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  echo "$self_dir/../run-all.sh"
}

# list_registered_suites
#   Echoes the DISTINCT unconditional suite paths (one per line, in
#   first-appearance order), with:
#     - the `run_suite() {` function-definition line EXCLUDED, and
#     - tests/test-plugin-live-load.sh DEDUPED to a single entry.
#   Conditional/gated suites are NOT included here — they are metadata; see
#   list_conditional_suites. Parses statically; does NOT execute run-all.sh.
list_registered_suites() {
  local runall
  runall="$(_suite_registry_runall)"

  # Match an actual registration CALL: optional leading whitespace, then
  # `run_suite "<name>" "<path>"`. The function-definition line is
  # `run_suite() {` — the `(` immediately after the name means it never
  # matches this `run_suite[[:space:]]+"` shape, so (a) is satisfied by the
  # pattern itself. Extract the 2nd quoted field (the path) and dedupe by
  # first appearance. The 3 conditional/gated suite paths are EXCLUDED here
  # (they are reported by list_conditional_suites as metadata); their
  # registrations sit inside `if` blocks but still carry a `run_suite "..."`
  # line, so they must be filtered by path.
  awk '
    BEGIN {
      cond["tests/test-fixture-race-isolation.sh"] = 1
      cond["tests/e2e-parallel-pipelines.sh"] = 1
    }
    match($0, /^[[:space:]]*run_suite[[:space:]]+"[^"]*"[[:space:]]+"[^"]*"/) {
      # Pull the 2nd double-quoted field = the script path.
      line = $0
      # Strip up to and including the first quoted field.
      sub(/^[[:space:]]*run_suite[[:space:]]+"[^"]*"[[:space:]]+"/, "", line)
      sub(/".*$/, "", line)
      if (line in cond) next
      if (!(line in seen)) {
        seen[line] = 1
        print line
      }
    }
  ' "$runall"
}

# list_conditional_suites
#   Echoes the 3 conditional/gated suites as metadata, one per line, in the
#   form "<gate>\t<path>" (tab-separated):
#       RUN_RACE_TESTS  tests/test-fixture-race-isolation.sh
#       RUN_E2E         tests/e2e-parallel-pipelines.sh
#       attended        tests/test-plugin-live-load.sh
#   This is a STATIC, intentional enumeration of the gated registrations in
#   run-all.sh — the gates are env-var / capability conditions a static
#   parse cannot evaluate, so they are reported as metadata for the caller
#   to decide on. (test-plugin-live-load.sh additionally appears in
#   list_registered_suites because it always runs; the attended gate only
#   controls whether its §B runs live.)
list_conditional_suites() {
  printf 'RUN_RACE_TESTS\ttests/test-fixture-race-isolation.sh\n'
  printf 'RUN_E2E\ttests/e2e-parallel-pipelines.sh\n'
  printf 'attended\ttests/test-plugin-live-load.sh\n'
}

# ──────────────────────────────────────────────────────────────────────
# Serial-only bucket (TEST_SUITE_PARALLELIZATION Phase 3).
#
# These suites are GENUINELY UNPARALLELIZABLE and MUST run in a serial
# phase, OUTSIDE the parallel pool the Phase-4 runner fans:
#
#   serial    tests/test_zskills_monitor_server.sh
#       Binds a real HTTP server on a $$-derived port (19000+$$%500 range)
#       and spawns heavy server child processes. Two copies racing in the
#       parallel pool would collide on the port / fight over the server
#       lifecycle, so it is pinned serial.
#   serial    tests/test_zskills_monitor_csrf.sh
#   serial    tests/test_zskills_monitor_dashboard_ui.sh
#   serial    tests/test_zskills_dashboard_skill.sh
#   serial    tests/test-monitor-state-queue-post-preservation.sh
#   serial    tests/test-pid-file-self-heal.sh
#       The rest of the LIVE-SERVER class: each boots a real
#       `python3 -m zskills_monitor.server` HTTP server in the background and
#       probes it over a TCP port. The four $$-derived ones map $$ into
#       OVERLAPPING windows (monitor_server 19000-19499, dashboard_ui
#       19500-19899, dashboard_skill 19800-19899 — overlaps dashboard_ui,
#       csrf 20000-20499, state-queue 21000-21499); two of them fanned
#       concurrently can land on the SAME port and the loser's server fails
#       to bind. test-pid-file-self-heal.sh uses a single FIXED port (19994)
#       and a single FIXED fixture path (/tmp/zskills-pid-self-heal-test),
#       so it is a non-isolatable singleton in the same heavy-server class.
#       All are pinned serial so they never race in the pool. (Phase 4 fix —
#       dashboard_skill was the observed flake; the siblings are pinned
#       proactively, same class, to avoid whack-a-mole.) NOTE the live-server
#       suite test-plan-skip-clear-paths.sh is NOT pinned: it binds an
#       OS-assigned ephemeral port (socket bind to 0) under a $$-scoped
#       fixture, so it cannot collide and stays in the parallel pool.
#   serial    tests/test-plugin-live-load.sh
#       The attended live-load suite reads/writes a GLOBAL throttle marker
#       (~/.zskills/last-attended-plugin-run) and, when the gate passes,
#       runs live `claude` — both global side effects that cannot be run
#       concurrently with a second copy of themselves or anything else
#       that touches that marker. It is pinned serial AND carries the
#       attended-gate decision (see serial_run_attended_live_load below).
#
# NOTE: all serial suites ALSO appear in list_registered_suites (they are
# unconditional registrations in run-all.sh — monitor_server always runs;
# live-load always runs, gated only on whether §B runs live). The Phase-4
# parallel runner consumes list_registered_suites for the pool and SUBTRACTS
# list_serial_suites to form the parallel set, then runs the serial bucket in
# its own phase. This mirrors how list_conditional_suites reports metadata
# WITHOUT removing live-load from the unconditional list — same pattern, so
# the existing registry contract (live-load present in the registered set)
# is preserved.
list_serial_suites() {
  printf 'serial\ttests/test_zskills_monitor_server.sh\n'
  printf 'serial\ttests/test_zskills_monitor_csrf.sh\n'
  printf 'serial\ttests/test_zskills_monitor_dashboard_ui.sh\n'
  printf 'serial\ttests/test_zskills_dashboard_skill.sh\n'
  printf 'serial\ttests/test-monitor-state-queue-post-preservation.sh\n'
  printf 'serial\ttests/test-pid-file-self-heal.sh\n'
  # KEEP test-plugin-live-load.sh LAST: the run-all.sh serial-bucket driver
  # iterates this list and dispatches the attended live-load via
  # serial_run_attended_live_load (the verbatim attended gate), every other
  # entry via a plain run_suite. The driver keys that special-case off this
  # exact path, so its position here is informational only (the driver
  # matches by path, not by order), but listing it last keeps the
  # plain-vs-attended split readable.
  printf 'serial\ttests/test-plugin-live-load.sh\n'
}

# is_serial_suite <path>
#   Exit 0 iff <path> is in the serial-only bucket. Convenience predicate for
#   the Phase-4 runner to filter list_registered_suites down to the parallel
#   pool (skip any path for which is_serial_suite returns 0).
is_serial_suite() {
  local q="$1" gate path
  while IFS=$'\t' read -r gate path; do
    [ "$path" = "$q" ] && return 0
  done < <(list_serial_suites)
  return 1
}

# serial_run_attended_live_load <run_suite_fn>
#   Run tests/test-plugin-live-load.sh ONCE, applying the attended-gate
#   decision logic CARRIED VERBATIM from run-all.sh:284-295. The caller
#   passes the name of its `run_suite`-equivalent function (the serial phase's
#   suite runner); this carries the gate so the serial bucket reproduces the
#   EXACT decision (capability + throttle) the serial run-all.sh applies —
#   the ZSKILLS_LIVE_ATTENDED=1 + attended_gate_refresh_marker branch when the
#   gate passes, the plain branch otherwise — running the suite exactly once.
#
#   $1 is invoked as: "$1" "<display-name>" "<suite-path>"  (run_suite's shape).
#   On the gate-pass branch the function exports ZSKILLS_LIVE_ATTENDED=1 only
#   for that single invocation (subshell), matching run-all.sh's per-call
#   prefix, then refreshes the marker.
serial_run_attended_live_load() {
  local run_suite_fn="$1"
  local self_dir
  self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # Source the SAME decision library run-all.sh uses.
  . "$self_dir/attended-gate.sh"
  local ATTENDED_MARKER ATTENDED_THROTTLE_SECONDS ATTENDED_NOW
  ATTENDED_MARKER="${HOME:-/tmp}/.zskills/last-attended-plugin-run"
  ATTENDED_THROTTLE_SECONDS="${ZSKILLS_ATTENDED_THROTTLE_SECONDS:-14400}"  # ~4h
  ATTENDED_NOW="$(date +%s)"
  if attended_gate_should_run "$ATTENDED_MARKER" "$ATTENDED_NOW" "$ATTENDED_THROTTLE_SECONDS"; then
    echo ""
    echo "[#991] attended gate PASSED (claude + creds present, throttle window elapsed) — running §B live."
    ZSKILLS_LIVE_ATTENDED=1 "$run_suite_fn" "test-plugin-live-load.sh" "tests/test-plugin-live-load.sh"
    attended_gate_refresh_marker "$ATTENDED_MARKER" "$ATTENDED_NOW"
  else
    "$run_suite_fn" "test-plugin-live-load.sh" "tests/test-plugin-live-load.sh"
  fi
}
