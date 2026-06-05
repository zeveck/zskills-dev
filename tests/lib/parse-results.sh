# tests/lib/parse-results.sh — shared "Results:" line parser for the
# serial (run-all.sh) and the future parallel suite runners.
#
# SOURCEABLE LIBRARY, NOT A SUITE. Do NOT register in run-all.sh as a
# `run_suite`. `tests/test-parse-results.sh` is the registered self-test
# that exercises this function.
#
# Factored verbatim out of tests/run-all.sh (the ANSI-strip + anchored
# `Results:` regex, formerly run-all.sh:34–43) so serial and parallel
# runners share ONE parsing contract and the #587-hardened regex lives in a
# single place.
#
# parse_results <output>
#   Echoes exactly "PASS FAIL" (two space-separated integers) extracted from
#   the canonical `Results: <N> passed, <N> failed` line in <output>.
#
#   The parse is DELIBERATELY narrow:
#     - It strips ANSI color codes first (some suites colorize Results
#       red/green).
#     - It anchors to the exact `^Results: <N> passed, ... <N> failed` line
#       shape so any inner-test diagnostics (e.g. test-hooks.sh's
#       fixture-extension synthetic-fixture run that nests a
#       `tests/test-skill-conformance.sh` invocation — see #587) can't leak a
#       count into the outer parser. The regex is the #587-hardened form and
#       is preserved EXACTLY.
#     - If no canonical line is found it echoes "0 0" (the no-Results-line
#       fall-through). This function does NOT decide whether that 0/0 is a
#       failure — the CALLER still owns exit-code capture and the OVERALL_EXIT
#       flip on any non-zero suite rc, so an unparseable-but-nonzero-exit
#       suite is NOT silently dropped.
parse_results() {
  local output="$1"
  local passed failed results_line stripped
  stripped=$(echo "$output" | sed -E $'s/\x1b\\[[0-9;]*m//g')
  results_line=$(echo "$stripped" | grep -E '^Results: [0-9]+ passed,( [0-9]+ failed|.* [0-9]+ failed)' | tail -1)
  if [[ -n "$results_line" ]]; then
    passed=$(echo "$results_line" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+')
    failed=$(echo "$results_line" | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+')
  else
    passed=0
    failed=0
  fi
  echo "${passed:-0} ${failed:-0}"
}
