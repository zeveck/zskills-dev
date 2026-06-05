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
  tests/test-hooks.sh \
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
