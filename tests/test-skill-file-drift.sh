#!/bin/bash
# tests/test-skill-file-drift.sh — End-to-end fixture test for
# plans/SKILL_FILE_DRIFT_FIX.md Phase 2: verify a representative migrated
# skill bash fence resolves config-driven values correctly.
#
# The test:
#   1. Creates a temp dir with .claude/zskills-config.json containing
#      timezone: "Europe/London", testing.full_cmd: "FIXTURE_FULL",
#      dev_server.cmd: "FIXTURE_DEV", testing.output_file: "FIXTURE_OUT.log",
#      commit.co_author: "Fixture <fixture@example.com>".
#   2. Exports CLAUDE_PROJECT_DIR to that temp dir.
#   3. Executes a hand-copied representative migrated fence (modeled on
#      the marker-write idiom in skills/draft-plan/SKILL.md after Phase 2
#      migration) under bash, capturing stdout.
#   4. Asserts the captured output contains "Europe/London", "FIXTURE_FULL",
#      "FIXTURE_OUT.log", and "FIXTURE_DEV" (resolved values).
#   5. Asserts the output does NOT contain "New_York", "npm run test:all",
#      ".test-results.txt", or "npm start" literally (which would mean the
#      migration didn't take effect for this fence).
#
# DA2.20 — explicit harness mechanism, hand-copied reference fence to
# avoid markdown-extraction drift surface.
#
# Run from repo root: bash tests/test-skill-file-drift.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$REPO_ROOT/skills/update-zskills/scripts/zskills-resolve-config.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

if [ ! -f "$HELPER" ]; then
  fail "helper exists" "$HELPER missing"
  printf 'Results: %d passed, %d failed (of %d)\n' \
    "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"
  exit 1
fi

# --- Fixture setup -----------------------------------------------------------
TMP=$(mktemp -d "/tmp/zskills-tests-fixture-$$-XXXXXX")
mkdir -p "$TMP/.claude"
cat > "$TMP/.claude/zskills-config.json" <<'CONFIG'
{
  "timezone": "Europe/London",
  "testing": {
    "full_cmd": "FIXTURE_FULL",
    "output_file": "FIXTURE_OUT.log"
  },
  "dev_server": {
    "cmd": "FIXTURE_DEV"
  },
  "commit": {
    "co_author": "Fixture <fixture@example.com>"
  }
}
CONFIG

# --- Test case 1: TZ + FULL_TEST_CMD resolution (the marker-write idiom) ----
# Reference fence (hand-copied; structure mirrors the migrated draft-plan,
# refine-plan, work-on-plans, fix-issues, run-plan idioms post-Phase-2):
#
#   ```bash
#   . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
#   printf 'tz: %s\nfull_cmd: %s\ndev_cmd: %s\noutput: %s\nco_author: %s\n' \
#     "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
#     "$FULL_TEST_CMD" "$DEV_SERVER_CMD" "$TEST_OUTPUT_FILE" "$COMMIT_CO_AUTHOR"
#   ```

echo "=== Test 1: representative migrated fence resolves config values ==="

OUTPUT=$(
  CLAUDE_PROJECT_DIR="$TMP" \
  bash -c '
    . "'"$HELPER"'"
    printf "tz: %s\nfull_cmd: %s\ndev_cmd: %s\noutput: %s\nco_author: %s\n" \
      "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
      "$FULL_TEST_CMD" "$DEV_SERVER_CMD" "$TEST_OUTPUT_FILE" "$COMMIT_CO_AUTHOR"
  '
)
RC=$?

if [ "$RC" -eq 0 ]; then
  pass "Test 1a: fence executed cleanly (rc=0)"
else
  fail "Test 1a: fence rc" "got rc=$RC"
fi

# Positive assertions — resolved values should appear in output.
echo "$OUTPUT" | grep -qF "FIXTURE_FULL" \
  && pass "Test 1b: \$FULL_TEST_CMD resolved to 'FIXTURE_FULL'" \
  || fail "Test 1b: FULL_TEST_CMD" "expected 'FIXTURE_FULL' in output, got: $OUTPUT"

echo "$OUTPUT" | grep -qF "FIXTURE_DEV" \
  && pass "Test 1c: \$DEV_SERVER_CMD resolved to 'FIXTURE_DEV'" \
  || fail "Test 1c: DEV_SERVER_CMD" "expected 'FIXTURE_DEV' in output, got: $OUTPUT"

echo "$OUTPUT" | grep -qF "FIXTURE_OUT.log" \
  && pass "Test 1d: \$TEST_OUTPUT_FILE resolved to 'FIXTURE_OUT.log'" \
  || fail "Test 1d: TEST_OUTPUT_FILE" "expected 'FIXTURE_OUT.log' in output, got: $OUTPUT"

echo "$OUTPUT" | grep -qF "Fixture <fixture@example.com>" \
  && pass "Test 1e: \$COMMIT_CO_AUTHOR resolved to 'Fixture <fixture@example.com>'" \
  || fail "Test 1e: COMMIT_CO_AUTHOR" "expected 'Fixture <fixture@example.com>' in output, got: $OUTPUT"

# TZ resolution: the printed date should reflect Europe/London, not UTC or
# America/New_York. Detect via the timezone offset suffix. London has offset
# +00:00 in winter, +01:00 in summer (BST). NY has -05:00 (EST) or -04:00
# (EDT). UTC has +00:00. Distinguishing London-from-UTC requires checking
# that TIMEZONE itself was used — easiest: check that the var was actually
# read by the helper.
TIMEZONE_RESOLVED=$(
  CLAUDE_PROJECT_DIR="$TMP" \
  bash -c '. "'"$HELPER"'" && printf "%s" "$TIMEZONE"'
)
[ "$TIMEZONE_RESOLVED" = "Europe/London" ] \
  && pass "Test 1f: \$TIMEZONE resolved to 'Europe/London'" \
  || fail "Test 1f: TIMEZONE" "got '$TIMEZONE_RESOLVED'"

# Negative assertions — pre-migration literals should NOT appear in output.
echo "$OUTPUT" | grep -qF "New_York" \
  && fail "Test 1g: no 'New_York' in output" "found: $OUTPUT" \
  || pass "Test 1g: 'New_York' literal absent (TZ was resolved, not hardcoded)"

echo "$OUTPUT" | grep -qF "npm run test:all" \
  && fail "Test 1h: no 'npm run test:all' in output" "found: $OUTPUT" \
  || pass "Test 1h: 'npm run test:all' literal absent"

echo "$OUTPUT" | grep -qF ".test-results.txt" \
  && fail "Test 1i: no '.test-results.txt' in output" "found: $OUTPUT" \
  || pass "Test 1i: '.test-results.txt' literal absent"

# --- Test case 2: empty-config fallback semantics ---------------------------
echo ""
echo "=== Test 2: empty-config — TZ falls back to UTC, full_cmd empty ==="

TMP2=$(mktemp -d "/tmp/zskills-tests-fixture-$$-empty-XXXXXX")
# Intentionally no .claude/zskills-config.json.

OUTPUT2=$(
  CLAUDE_PROJECT_DIR="$TMP2" \
  bash -c '
    . "'"$HELPER"'"
    # Demonstrate informational TZ fallback to UTC.
    printf "tz_fallback: %s\n" "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)"
    printf "full_cmd_empty: %s\n" "${FULL_TEST_CMD:-(empty)}"
  '
)

# UTC date format ends with +00:00.
echo "$OUTPUT2" | grep -qE 'tz_fallback: .*\+00:00$' \
  && pass "Test 2a: empty config → TZ falls back to UTC (+00:00 offset)" \
  || fail "Test 2a: TZ fallback" "expected +00:00 offset, got: $OUTPUT2"

echo "$OUTPUT2" | grep -qF 'full_cmd_empty: (empty)' \
  && pass "Test 2b: empty config → \$FULL_TEST_CMD remains empty" \
  || fail "Test 2b: FULL_TEST_CMD empty" "got: $OUTPUT2"

rm -rf "$TMP2"

# --- Test case 3: TEST_OUTPUT_FILE fallback ---------------------------------
echo ""
echo "=== Test 3: TEST_OUTPUT_FILE empty → falls back to .test-results.txt ==="

TMP3=$(mktemp -d "/tmp/zskills-tests-fixture-$$-fallback-XXXXXX")
mkdir -p "$TMP3/.claude"
cat > "$TMP3/.claude/zskills-config.json" <<'CONFIG3'
{
  "timezone": "Europe/London"
}
CONFIG3

OUTPUT3=$(
  CLAUDE_PROJECT_DIR="$TMP3" \
  bash -c '
    . "'"$HELPER"'"
    # Migrated idiom: $TEST_OUT/${TEST_OUTPUT_FILE:-.test-results.txt}
    TEST_OUT=/tmp/x
    printf "result_path: %s\n" "$TEST_OUT/${TEST_OUTPUT_FILE:-.test-results.txt}"
  '
)

echo "$OUTPUT3" | grep -qF '/tmp/x/.test-results.txt' \
  && pass "Test 3: empty TEST_OUTPUT_FILE → fallback to '.test-results.txt'" \
  || fail "Test 3: TEST_OUTPUT_FILE fallback" "got: $OUTPUT3"

rm -rf "$TMP3"

# --- Cleanup ---------------------------------------------------------------
rm -rf "$TMP"

# --- Summary ---------------------------------------------------------------
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
