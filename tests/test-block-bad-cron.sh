#!/usr/bin/env bash
# Tests for hooks/block-bad-cron.sh
# Run from repo root: bash tests/test-block-bad-cron.sh
#
# Coverage:
#   T1  Allow: recurring=true future fire (*/5 * * * *)
#   T2  Allow: recurring=false fire ~2h ahead
#   T3  DENY: synthetic repro of 2026-05-19 bug — `3 16 19 5 *` recurring=false,
#       FAKE_NOW = 2026-05-19 16:31:00 UTC (cron evaluated by scheduler in
#       container UTC, next match is 2027) → no-match-in-8-days reason
#   T4  DENY: recurring=false with fire >7 days out
#   T5  Allow w/ WARN: garbage cron expression
#   T6  Allow: recurring=true 0 0 31 2 * (Feb 31 never matches)
#   T7  Fallthrough: tool_name=Bash → exit 0, no stdout (early filter)
#   T8a TZ resolution: TMPDIR config with "timezone":"Europe/London" → deny
#       message contains 'Europe/London'
#   T8b TZ resolution fallback: no config → does NOT contain 'America/New_York'

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/hooks/block-bad-cron.sh"

TEST_OUT="/tmp/zskills-tests/$(basename "$REPO_ROOT")-block-bad-cron"
mkdir -p "$TEST_OUT"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  printf '\033[32m  PASS\033[0m %s\n' "$1"
  PASS_COUNT=$((PASS_COUNT + 1))
}
fail() {
  printf '\033[31m  FAIL\033[0m %s\n' "$1"
  printf '    %s\n' "$2"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

echo "=== block-bad-cron.sh ==="

# Default CLAUDE_PROJECT_DIR to repo root for cases that don't override.
export CLAUDE_PROJECT_DIR="$REPO_ROOT"

# Helper — invoke the hook with stdin envelope; capture stdout/stderr/exit.
run_hook() {
  local input="$1"
  local _err
  _err=$(mktemp -p /tmp zskills-cronhook-err-XXXX)
  HOOK_OUT=$(printf '%s' "$input" | bash "$HOOK" 2>"$_err")
  HOOK_EXIT=$?
  HOOK_ERR=$(cat "$_err")
  rm -f "$_err"
}

# Helper — set FAKE_NOW_EPOCH from a UTC time string.
fake_now() {
  TZ=UTC date -d "$1" +%s
}

# ─────────────── T1: recurring=true future fire → allow ───────────
export FAKE_NOW_EPOCH=$(fake_now "2026-05-19 12:00:00")
run_hook '{"tool_name":"CronCreate","tool_input":{"cron":"*/5 * * * *","recurring":true,"prompt":"hi"}}'
if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_OUT" ]; then
  pass "T1: recurring=true future fire → allow (empty stdout, exit 0)"
else
  fail "T1: recurring=true should allow" "exit=$HOOK_EXIT stdout=$HOOK_OUT err=$HOOK_ERR"
fi
unset FAKE_NOW_EPOCH

# ─────────────── T2: recurring=false fire 2h ahead → allow ────────
# FAKE_NOW=2026-05-19 12:00 UTC, cron=0 14 19 5 * → fires 14:00 UTC same day.
export FAKE_NOW_EPOCH=$(fake_now "2026-05-19 12:00:00")
run_hook '{"tool_name":"CronCreate","tool_input":{"cron":"0 14 19 5 *","recurring":false,"prompt":"hi"}}'
if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_OUT" ]; then
  pass "T2: recurring=false +2h → allow"
else
  fail "T2: recurring=false +2h should allow" "exit=$HOOK_EXIT stdout=$HOOK_OUT err=$HOOK_ERR"
fi
unset FAKE_NOW_EPOCH

# ─────────────── T3: SYNTHETIC REPRO 2026-05-19 BUG ───────────────
# cron=3 16 19 5 *, recurring=false, FAKE_NOW=2026-05-19 16:31:00 UTC.
# 16:03 UTC has already passed for May 19 at 16:31. No year field → next
# match is May 19 2027 → no match in 8 days → DENY.
export FAKE_NOW_EPOCH=$(fake_now "2026-05-19 16:31:00")
run_hook '{"tool_name":"CronCreate","tool_input":{"cron":"3 16 19 5 *","recurring":false,"prompt":"hi"}}'
T3_OK=1
[ "$HOOK_EXIT" -eq 0 ] || T3_OK=0
[[ "$HOOK_OUT" == *'"permissionDecision":"deny"'* ]] || T3_OK=0
[[ "$HOOK_OUT" == *'STOP:'* ]] || T3_OK=0
[[ "$HOOK_OUT" == *'container TZ'* ]] || T3_OK=0
[[ "$HOOK_OUT" == *'8 days'* ]] || T3_OK=0
# Valid JSON envelope.
if command -v python3 >/dev/null; then
  python3 -c 'import json,sys; json.loads(sys.stdin.read())' <<< "$HOOK_OUT" >/dev/null 2>&1 || T3_OK=0
fi
if [ "$T3_OK" -eq 1 ]; then
  pass "T3: synthetic 2026-05-19 repro → DENY w/ container-TZ + 8-day reason"
else
  fail "T3: synthetic repro must deny" "exit=$HOOK_EXIT stdout=$HOOK_OUT err=$HOOK_ERR"
fi
unset FAKE_NOW_EPOCH

# ─────────────── T4: recurring=false fire >7 days out → DENY ──────
# now=2026-05-19 00:00 UTC, cron=0 12 26 5 * → fires 7.5 days later (within 8)
export FAKE_NOW_EPOCH=$(fake_now "2026-05-19 00:00:00")
run_hook '{"tool_name":"CronCreate","tool_input":{"cron":"0 12 26 5 *","recurring":false,"prompt":"hi"}}'
T4_OK=1
[ "$HOOK_EXIT" -eq 0 ] || T4_OK=0
[[ "$HOOK_OUT" == *'"permissionDecision":"deny"'* ]] || T4_OK=0
[[ "$HOOK_OUT" == *'7 days'* ]] || T4_OK=0
if [ "$T4_OK" -eq 1 ]; then
  pass "T4: recurring=false fire >7 days → DENY w/ session-lifetime reason"
else
  fail "T4: fire >7d should deny" "exit=$HOOK_EXIT stdout=$HOOK_OUT err=$HOOK_ERR"
fi
unset FAKE_NOW_EPOCH

# ─────────────── T5: garbage cron → allow + WARN to stderr ────────
run_hook '{"tool_name":"CronCreate","tool_input":{"cron":"not a cron","recurring":false,"prompt":"hi"}}'
T5_OK=1
[ "$HOOK_EXIT" -eq 0 ] || T5_OK=0
[ -z "$HOOK_OUT" ] || T5_OK=0
[[ "$HOOK_ERR" == *parse* ]] || T5_OK=0
if [ "$T5_OK" -eq 1 ]; then
  pass "T5: garbage cron → allow + 'parse' WARN on stderr"
else
  fail "T5: garbage should allow w/ WARN" "exit=$HOOK_EXIT stdout=$HOOK_OUT err=$HOOK_ERR"
fi

# ─────────────── T6: recurring=true 0 0 31 2 * → allow ────────────
# Feb-31 never matches (no Feb 31st exists). With recurring=true, the
# no-match rule must NOT fire.
export FAKE_NOW_EPOCH=$(fake_now "2026-05-19 00:00:00")
run_hook '{"tool_name":"CronCreate","tool_input":{"cron":"0 0 31 2 *","recurring":true,"prompt":"hi"}}'
if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_OUT" ]; then
  pass "T6: recurring=true Feb-31 → allow (no-match rule must not fire on recurring)"
else
  fail "T6: recurring=true Feb-31 should allow" "exit=$HOOK_EXIT stdout=$HOOK_OUT err=$HOOK_ERR"
fi
unset FAKE_NOW_EPOCH

# ─────────────── T7: tool_name=Bash → fallthrough ─────────────────
run_hook '{"tool_name":"Bash","tool_input":{"command":"echo hi"}}'
if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_OUT" ]; then
  pass "T7: tool_name=Bash → fallthrough, no stdout, exit 0"
else
  fail "T7: Bash should fall through" "exit=$HOOK_EXIT stdout=$HOOK_OUT err=$HOOK_ERR"
fi

# ─────────────── T8a: TZ resolution from TMPDIR config ────────────
T8_TMP=$(mktemp -d -p /tmp zskills-cronhook-T8-XXXX)
mkdir -p "$T8_TMP/.claude"
cat > "$T8_TMP/.claude/zskills-config.json" <<'CFG_EOF'
{"timezone":"Europe/London"}
CFG_EOF
(
  export CLAUDE_PROJECT_DIR="$T8_TMP"
  export FAKE_NOW_EPOCH=$(fake_now "2026-05-19 16:31:00")
  printf '%s' '{"tool_name":"CronCreate","tool_input":{"cron":"3 16 19 5 *","recurring":false,"prompt":"hi"}}' | bash "$HOOK"
) > "$TEST_OUT/t8a.out" 2>"$TEST_OUT/t8a.err"
T8A_OUT=$(cat "$TEST_OUT/t8a.out")
if [[ "$T8A_OUT" == *'"permissionDecision":"deny"'* ]] && [[ "$T8A_OUT" == *'Europe/London'* ]]; then
  pass "T8a: TMPDIR config 'Europe/London' → deny msg contains Europe/London"
else
  fail "T8a: TMPDIR London config" "out=$T8A_OUT err=$(cat "$TEST_OUT/t8a.err")"
fi
rm -rf "$T8_TMP"

# ─────────────── T8b: TZ resolution fallback (no config) ──────────
# Goal: prove America/New_York is NOT hardcoded. With config absent, the
# fallback ladder is $TIMEZONE → $TZ → /etc/timezone → "UTC". On this
# devcontainer /etc/timezone is "Etc/UTC", so the deny message MUST NOT
# contain "America/New_York".
T8B_TMP=$(mktemp -d -p /tmp zskills-cronhook-T8b-XXXX)
mkdir -p "$T8B_TMP/.claude"
# No config file written.
(
  export CLAUDE_PROJECT_DIR="$T8B_TMP"
  unset TIMEZONE
  unset TZ
  export FAKE_NOW_EPOCH=$(fake_now "2026-05-19 16:31:00")
  printf '%s' '{"tool_name":"CronCreate","tool_input":{"cron":"3 16 19 5 *","recurring":false,"prompt":"hi"}}' | bash "$HOOK"
) > "$TEST_OUT/t8b.out" 2>"$TEST_OUT/t8b.err"
T8B_OUT=$(cat "$TEST_OUT/t8b.out")
if [[ "$T8B_OUT" == *'"permissionDecision":"deny"'* ]] && [[ "$T8B_OUT" != *'America/New_York'* ]]; then
  pass "T8b: no config → fallback NOT America/New_York (drift PR UTC convention honored)"
else
  fail "T8b: fallback should NOT be America/New_York" "out=$T8B_OUT err=$(cat "$TEST_OUT/t8b.err")"
fi
rm -rf "$T8B_TMP"

echo ""
echo "---"
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
