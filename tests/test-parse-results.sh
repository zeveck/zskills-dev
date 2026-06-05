#!/bin/bash
# tests/test-parse-results.sh — self-test for tests/lib/parse-results.sh
# (TEST_SUITE_PARALLELIZATION Phase 0).
#
# parse_results is the shared "Results:" line parser factored out of
# run-all.sh so serial + parallel runners share one parsing contract. This
# suite pins that contract:
#   1. Plain (un-colorized) Results line → "PASS FAIL".
#   2. ANSI-colorized Results line (green/red) → same "PASS FAIL".
#   3. No Results line in the output → "0 0" fall-through.
#   4. The #587 hardening: a nested inner `Results:` diagnostic line that is
#      NOT column-anchored must NOT leak its count; only the canonical
#      `^Results:` line is parsed, and the LAST one wins.
#   5. A non-zero "failed" count is reported faithfully.
#
# If any of these break, both the serial and the future parallel runner would
# miscount; this suite is the tripwire.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=tests/lib/parse-results.sh
. "$SCRIPT_DIR/lib/parse-results.sh"

PASS=0
FAIL=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

# Helper: assert parse_results <output> echoes exactly <expected>.
expect() {
  local label="$1" output="$2" expected="$3" got
  got="$(parse_results "$output")"
  if [ "$got" = "$expected" ]; then
    pass "$label"
  else
    fail "$label" "expected '$expected', got '$got'"
  fi
}

# ── 1. Plain Results line ─────────────────────────────────────────────
plain=$'  PASS something\n  PASS other\nResults: 42 passed, 0 failed (of 42)'
expect "[plain] '42 passed, 0 failed' → '42 0'" "$plain" "42 0"

# ── 2. ANSI-colorized Results line (green) ────────────────────────────
green=$'  ok\n\033[32mResults: 713 passed, 0 failed (of 713)\033[0m'
expect "[ansi-green] colorized line strips ANSI → '713 0'" "$green" "713 0"

# ANSI-colorized failing Results line (red).
red=$'  bad\n\033[31mResults: 10 passed, 3 failed (of 13)\033[0m'
expect "[ansi-red] colorized failing line → '10 3'" "$red" "10 3"

# ── 3. No Results line → 0/0 fall-through ─────────────────────────────
noresults=$'  PASS a\n  PASS b\n(no canonical results line here)'
expect "[fallthrough] no Results line → '0 0'" "$noresults" "0 0"

# Empty output → 0/0.
expect "[fallthrough] empty output → '0 0'" "" "0 0"

# ── 4. #587 hardening: non-anchored inner Results must NOT leak ───────
# A nested diagnostic line whose `Results:` is NOT at column 0 (indented /
# prefixed) must be ignored; only the canonical `^Results:` line is parsed.
nested=$'running nested suite...\n    Results: 999 passed, 99 failed (of 1098)\nResults: 50 passed, 0 failed (of 50)'
expect "[hardening] indented inner Results ignored; canonical wins → '50 0'" "$nested" "50 0"

# When two canonical `^Results:` lines appear, the LAST one wins (tail -1).
twolines=$'Results: 5 passed, 0 failed (of 5)\nmore output\nResults: 7 passed, 1 failed (of 8)'
expect "[hardening] last canonical Results line wins → '7 1'" "$twolines" "7 1"

# ── 5. Non-zero failed count faithfully reported ──────────────────────
failing=$'Results: 100 passed, 7 failed (of 107)'
expect "[failcount] non-zero failed reported → '100 7'" "$failing" "100 7"

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
