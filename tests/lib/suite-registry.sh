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
