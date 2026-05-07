#!/bin/bash
# Tests for scripts/skill-version-compare.sh
# Run from repo root: bash tests/test-skill-version-compare.sh
#
# Coverage (issue #178):
#   1. Same date, different hash      → exit 0 (same-day re-edit is a valid bump)
#   2. Same date, same hash           → exit 1 (no bump — byte-identical)
#   3. Newer date                     → exit 0
#   4. Older date                     → exit 1 (regression)
#   5. Newer date, smaller hash       → exit 0 (date wins over hash ordering)
#   6. Malformed <old>                → exit 2
#   7. Malformed <new>                → exit 2
#   8. Missing args (0 / 1)           → exit 2

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CMP="$REPO_ROOT/scripts/skill-version-compare.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# Run the comparator and capture exit code without aborting under set -e.
run_cmp() {
  bash "$CMP" "$@" >/dev/null 2>&1
  echo $?
}

assert_exit() {
  # $1 = label, $2 = expected exit, $3 = actual exit
  if [ "$2" -eq "$3" ]; then
    pass "$1 (exit=$3)"
  else
    fail "$1 — expected exit $2, got $3"
  fi
}

echo "=== skill-version-compare tests ==="

# 1. Same date, different hash → valid bump (the reason issue #178 exists)
ec=$(run_cmp "2026.04.30+aaa111" "2026.04.30+bbb222")
assert_exit "same date, different hash → valid bump" 0 "$ec"

# 2. Same date, same hash → no bump
ec=$(run_cmp "2026.04.30+aaa111" "2026.04.30+aaa111")
assert_exit "same date, same hash → no bump" 1 "$ec"

# 3. Newer date → valid bump
ec=$(run_cmp "2026.04.30+aaa111" "2026.05.01+bbb222")
assert_exit "newer date → valid bump" 0 "$ec"

# 4. Older date → regression
ec=$(run_cmp "2026.04.30+aaa111" "2026.04.29+bbb222")
assert_exit "older date → regression" 1 "$ec"

# 5. Newer date with lexically smaller hash → valid bump (date wins)
ec=$(run_cmp "2026.04.30+ffffff" "2026.05.01+000000")
assert_exit "newer date + smaller hash → valid bump (date wins)" 0 "$ec"

# Bonus: cross-year boundary handles correctly.
ec=$(run_cmp "2026.12.31+aaa111" "2027.01.01+aaa111")
assert_exit "cross-year boundary → valid bump" 0 "$ec"

# Bonus: same date / same hash but second-passed-uppercase → malformed (regex strict)
ec=$(run_cmp "2026.04.30+aaa111" "2026.04.30+AAA111")
assert_exit "uppercase hash in <new> → malformed" 2 "$ec"

# 6. Malformed <old>
ec=$(run_cmp "not-a-version" "2026.04.30+aaa111")
assert_exit "malformed <old> → exit 2" 2 "$ec"

# Malformed <old> — short hash
ec=$(run_cmp "2026.04.30+aaa11" "2026.04.30+bbb222")
assert_exit "malformed <old> (5-char hash) → exit 2" 2 "$ec"

# 7. Malformed <new>
ec=$(run_cmp "2026.04.30+aaa111" "2026.4.30+bbb222")
assert_exit "malformed <new> (unpadded month) → exit 2" 2 "$ec"

# Malformed <new> — month 13
ec=$(run_cmp "2026.04.30+aaa111" "2026.13.01+bbb222")
assert_exit "malformed <new> (month 13) → exit 2" 2 "$ec"

# 8. Missing args
ec=$(run_cmp)
assert_exit "no args → exit 2" 2 "$ec"

ec=$(run_cmp "2026.04.30+aaa111")
assert_exit "1 arg → exit 2" 2 "$ec"

ec=$(run_cmp "2026.04.30+aaa111" "2026.05.01+bbb222" "extra-arg")
assert_exit "3 args → exit 2" 2 "$ec"

# Empty arg
ec=$(run_cmp "" "2026.04.30+aaa111")
assert_exit "empty <old> → exit 2" 2 "$ec"

ec=$(run_cmp "2026.04.30+aaa111" "")
assert_exit "empty <new> → exit 2" 2 "$ec"

# Stderr message check on a non-bump case mentions the date/hash for diagnosis.
err=$(bash "$CMP" "2026.04.30+aaa111" "2026.04.30+aaa111" 2>&1 >/dev/null || true)
if [[ "$err" == *"NOT A BUMP"* ]] && [[ "$err" == *"2026.04.30+aaa111"* ]]; then
  pass "no-bump stderr names the offending version"
else
  fail "no-bump stderr names the offending version — got: $err"
fi

err=$(bash "$CMP" "garbage" "2026.04.30+aaa111" 2>&1 >/dev/null || true)
if [[ "$err" == *"ERROR"* ]] && [[ "$err" == *"garbage"* ]]; then
  pass "malformed stderr names the offending arg"
else
  fail "malformed stderr names the offending arg — got: $err"
fi

echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"
if [ "$FAIL_COUNT" -gt 0 ]; then exit 1; fi
exit 0
