#!/bin/bash
# Tests for scripts/compute-cron-fire.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/skills/run-plan/scripts/compute-cron-fire.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# expect <label> <time-string> <args> <expected-output>
expect() {
  local label="$1" time="$2" args="$3" expected="$4"
  local epoch actual
  epoch=$(date -d "$time" +%s 2>/dev/null)
  if [ -z "$epoch" ]; then
    fail "$label — could not parse time string '$time'"
    return
  fi
  # shellcheck disable=SC2086
  actual=$(FAKE_NOW_EPOCH="$epoch" bash "$SCRIPT" $args 2>&1)
  if [ "$actual" = "$expected" ]; then
    pass "$label ($time $args → $actual)"
  else
    fail "$label — expected '$expected', got '$actual' ($time $args)"
  fi
}

# expect_rc <label> <args> <expected-rc>
expect_rc() {
  local label="$1" args="$2" expected_rc="$3"
  # shellcheck disable=SC2086
  bash "$SCRIPT" $args >/dev/null 2>&1
  local rc=$?
  if [ "$rc" = "$expected_rc" ]; then
    pass "$label (args='$args' → rc=$rc)"
  else
    fail "$label — expected rc=$expected_rc, got rc=$rc (args='$args')"
  fi
}

echo "=== Normal case (default +5) ==="
expect "+5 at 10:00 → 10:05"                    "2026-04-19 10:00:00" ""                "05 10 19 04 *"
expect "+5 at 10:12 → 10:17"                    "2026-04-19 10:12:00" ""                "17 10 19 04 *"

echo ""
echo "=== :00 avoidance ==="
expect "+5 at 10:55 → 11:00 → bump 11:01"       "2026-04-19 10:55:00" ""                "01 11 19 04 *"
expect "+5 at 11:55 → 12:00 → bump 12:01"       "2026-04-19 11:55:00" ""                "01 12 19 04 *"

echo ""
echo "=== :30 avoidance ==="
expect "+5 at 10:25 → 10:30 → bump 10:31"       "2026-04-19 10:25:00" ""                "31 10 19 04 *"
expect "+5 at 11:25 → 11:30 → bump 11:31"       "2026-04-19 11:25:00" ""                "31 11 19 04 *"

echo ""
echo "=== --allow-marks disables avoidance ==="
expect "+5 at 10:55 without bump"               "2026-04-19 10:55:00" "--allow-marks"   "00 11 19 04 *"
expect "+5 at 10:25 without bump"               "2026-04-19 10:25:00" "--allow-marks"   "30 10 19 04 *"

echo ""
echo "=== Hour rollover ==="
expect "+5 at 10:58 → 11:03"                    "2026-04-19 10:58:00" ""                "03 11 19 04 *"
expect "+5 at 23:58 → 00:03 APR 20 (day rollover)" \
                                                "2026-04-19 23:58:00" ""                "03 00 20 04 *"

echo ""
echo "=== Day rollover at month boundary ==="
expect "+5 at Apr 30 23:58 → May 1 00:03"       "2026-04-30 23:58:00" ""                "03 00 01 05 *"
expect "+5 at Feb 28 23:58 (non-leap) → Mar 1"  "2027-02-28 23:58:00" ""                "03 00 01 03 *"
expect "+5 at Feb 29 23:58 (leap 2028) → Mar 1" "2028-02-29 23:58:00" ""                "03 00 01 03 *"
expect "+5 at Feb 28 23:58 (leap 2028) → Feb 29" "2028-02-28 23:58:00" ""               "03 00 29 02 *"

echo ""
echo "=== Year rollover ==="
expect "+5 at Dec 31 23:58 → Jan 1 00:03"       "2026-12-31 23:58:00" ""                "03 00 01 01 *"

echo ""
echo "=== :00/:30 avoidance cascading into rollover ==="
expect "+5 at 23:55 → 00:00 → bump 00:01 next day" \
                                                "2026-04-19 23:55:00" ""                "01 00 20 04 *"
expect "+5 at Dec 31 23:55 → 00:00 → bump 00:01 next year" \
                                                "2026-12-31 23:55:00" ""                "01 00 01 01 *"

echo ""
echo "=== Custom offset ==="
expect "offset 10 at 10:00 → 10:10"             "2026-04-19 10:00:00" "--offset 10"     "10 10 19 04 *"
expect "offset 1 at 10:00 → 10:01"              "2026-04-19 10:00:00" "--offset 1"      "01 10 19 04 *"
expect "offset 60 at 10:00 → 11:00 → bump 11:01" \
                                                "2026-04-19 10:00:00" "--offset 60"     "01 11 19 04 *"
expect "offset 1440 at Apr 19 10:00 → Apr 20 10:00 → bump 10:01" \
                                                "2026-04-19 10:00:00" "--offset 1440"   "01 10 20 04 *"

echo ""
echo "=== :00/:30 boundary precision ==="
expect "offset 5 at 10:54 → 10:59 (no bump; only :00 and :30 bump)" \
                                                "2026-04-19 10:54:00" ""                "59 10 19 04 *"
expect "offset 5 at 10:26 → 10:31 (no bump; already past :30)" \
                                                "2026-04-19 10:26:00" ""                "31 10 19 04 *"
expect "offset 5 at 11:54 → 11:59"              "2026-04-19 11:54:00" ""                "59 11 19 04 *"

echo ""
echo "=== Usage errors ==="
expect_rc "unknown flag"    "--bogus"       2
expect_rc "bad offset (text)" "--offset foo" 2
expect_rc "zero offset (must be ≥1)" "--offset 0" 2
expect_rc "negative offset"  "--offset -5"  2
expect_rc "help flag"        "--help"       0

echo ""
echo "---"
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (of %d)\033[0m\n' "$PASS_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (of %d)\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit 1
fi
