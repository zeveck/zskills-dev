#!/bin/bash
# test-inflight-guard.sh — behavioral coverage for the cron-overlap
# in-flight guard (issue #877 queue-pickup; sibling #883 same-work key).
#
# Exercises skills/create-worktree/scripts/check-inflight-batch.sh directly
# (standalone — no skill dispatch). The helper is the shared detection
# primitive both #877 (queue-pickup, no --work-id) and #883 (same-work,
# --work-id) build on. Contract under test:
#   exit 0  = IN-FLIGHT  → caller skips; stdout = sentinel basename
#   exit 1  = PROCEED    → no match, or any error/ambiguity (fail-open)
#
# Cases:
#   1  skip when a same-session sentinel is fresh        → exit 0 + basename
#   2  proceed when the sentinel is stale (>max-age)     → exit 1 + file removed
#   3  proceed when the sentinel is a different session  → exit 1 (parallel pipeline)
#   4  --work-id match (#883)                            → exit 0
#   4b --work-id mismatch (#883)                         → exit 1
#   5  empty --session (CLAUDE_CODE_SESSION_ID unset)    → exit 1 (fail-open)
#   6  no sentinel present                               → exit 1
#   7  fresh sentinel with unparseable startedAt         → exit 0 (treated fresh, not deleted)
#   8  epoch startedAt aging                             → fresh exit 0, stale exit 1
#   9  structural: each pickup worker wires the guard    → grep the 3 skill files

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$REPO_ROOT/skills/create-worktree/scripts/check-inflight-batch.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SCRATCH="$(mktemp -d "/tmp/test-inflight-guard-XXXXXX")"
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

SID="session-aaaa-1111"
OTHER="session-bbbb-2222"
GLOB='.zskills/tracking/*/pipeline.fix-issues.*'
TRACK="$SCRATCH/.zskills/tracking/fix-issues.sprint-x"
mkdir -p "$TRACK"

# Helper to write a guard sentinel.
write_sentinel() {
  # $1 = runid suffix, $2 = session, $3 = startedAt, $4 = workId(optional)
  local f="$TRACK/pipeline.fix-issues.$1"
  {
    echo "skill: fix-issues"
    echo "session: $2"
    [ -n "${4:-}" ] && echo "workId: $4"
    echo "startedAt: $3"
  } > "$f"
  printf '%s' "$f"
}

run_guard() {
  # echoes stdout; sets GUARD_RC
  GUARD_OUT="$(bash "$HELPER" --root "$SCRATCH" --glob "$GLOB" "$@" 2>/dev/null)"
  GUARD_RC=$?
}

NOW_EPOCH=$(date +%s)
NOW_ISO=$(date -Iseconds)

# ── Case 1: same-session fresh → exit 0 + basename ──────────────────────
rm -f "$TRACK"/pipeline.fix-issues.*
write_sentinel "sprint-1" "$SID" "$NOW_ISO" >/dev/null
run_guard --session "$SID"
if [ "$GUARD_RC" -eq 0 ] && [ "$GUARD_OUT" = "pipeline.fix-issues.sprint-1" ]; then
  pass "case1 same-session-fresh → exit 0 + basename"
else
  fail "case1 same-session-fresh" "rc=$GUARD_RC out='$GUARD_OUT' (want rc=0 out=pipeline.fix-issues.sprint-1)"
fi

# ── Case 2: stale → exit 1 + file removed ───────────────────────────────
rm -f "$TRACK"/pipeline.fix-issues.*
STALE_ISO=$(date -d "@$((NOW_EPOCH - 99999))" -Iseconds)
SF=$(write_sentinel "sprint-2" "$SID" "$STALE_ISO")
run_guard --session "$SID" --max-age-seconds 21600
if [ "$GUARD_RC" -eq 1 ] && [ ! -f "$SF" ]; then
  pass "case2 stale → exit 1 + sentinel removed"
else
  fail "case2 stale" "rc=$GUARD_RC fileExists=$([ -f "$SF" ] && echo yes || echo no) (want rc=1, removed)"
fi

# ── Case 3: different session → exit 1, NOT removed ─────────────────────
rm -f "$TRACK"/pipeline.fix-issues.*
OF=$(write_sentinel "sprint-3" "$OTHER" "$NOW_ISO")
run_guard --session "$SID"
if [ "$GUARD_RC" -eq 1 ] && [ -f "$OF" ]; then
  pass "case3 different-session → exit 1 (parallel pipeline untouched)"
else
  fail "case3 different-session" "rc=$GUARD_RC fileExists=$([ -f "$OF" ] && echo yes || echo no) (want rc=1, kept)"
fi

# ── Case 4: --work-id match (#883) → exit 0 ─────────────────────────────
rm -f "$TRACK"/pipeline.fix-issues.*
write_sentinel "sprint-4" "$SID" "$NOW_ISO" "plan-alpha" >/dev/null
run_guard --session "$SID" --work-id "plan-alpha"
if [ "$GUARD_RC" -eq 0 ]; then
  pass "case4 work-id match → exit 0"
else
  fail "case4 work-id match" "rc=$GUARD_RC (want 0)"
fi

# ── Case 4b: --work-id mismatch (#883) → exit 1 ─────────────────────────
run_guard --session "$SID" --work-id "plan-beta"
if [ "$GUARD_RC" -eq 1 ]; then
  pass "case4b work-id mismatch → exit 1"
else
  fail "case4b work-id mismatch" "rc=$GUARD_RC (want 1)"
fi

# ── Case 5: empty session → exit 1 (fail-open) ──────────────────────────
rm -f "$TRACK"/pipeline.fix-issues.*
write_sentinel "sprint-5" "$SID" "$NOW_ISO" >/dev/null
run_guard --session ""
if [ "$GUARD_RC" -eq 1 ]; then
  pass "case5 empty-session → exit 1 (fail-open)"
else
  fail "case5 empty-session" "rc=$GUARD_RC (want 1)"
fi

# ── Case 6: no sentinel → exit 1 ────────────────────────────────────────
rm -f "$TRACK"/pipeline.fix-issues.*
run_guard --session "$SID"
if [ "$GUARD_RC" -eq 1 ]; then
  pass "case6 no-sentinel → exit 1"
else
  fail "case6 no-sentinel" "rc=$GUARD_RC (want 1)"
fi

# ── Case 7: unparseable startedAt → treated fresh, exit 0, not removed ──
rm -f "$TRACK"/pipeline.fix-issues.*
UF=$(write_sentinel "sprint-7" "$SID" "not-a-date")
run_guard --session "$SID"
if [ "$GUARD_RC" -eq 0 ] && [ -f "$UF" ]; then
  pass "case7 unparseable-startedAt → exit 0 (fresh, not deleted)"
else
  fail "case7 unparseable-startedAt" "rc=$GUARD_RC fileExists=$([ -f "$UF" ] && echo yes || echo no) (want rc=0, kept)"
fi

# ── Case 8: epoch startedAt aging ───────────────────────────────────────
rm -f "$TRACK"/pipeline.fix-issues.*
write_sentinel "sprint-8a" "$SID" "$NOW_EPOCH" >/dev/null
run_guard --session "$SID"
RC_FRESH=$GUARD_RC
rm -f "$TRACK"/pipeline.fix-issues.*
write_sentinel "sprint-8b" "$SID" "$((NOW_EPOCH - 99999))" >/dev/null
run_guard --session "$SID" --max-age-seconds 21600
RC_STALE=$GUARD_RC
if [ "$RC_FRESH" -eq 0 ] && [ "$RC_STALE" -eq 1 ]; then
  pass "case8 epoch aging → fresh exit 0, stale exit 1"
else
  fail "case8 epoch aging" "fresh=$RC_FRESH stale=$RC_STALE (want 0,1)"
fi

# ── Case 9: structural — each pickup worker wires the guard ─────────────
WIRE_OK=1
for spec in \
  "fix-issues:skills/fix-issues/modes/sprint.md" \
  "work-on-plans:skills/work-on-plans/modes/execute.md" \
  "qe-audit:skills/qe-audit/SKILL.md"; do
  label="${spec%%:*}"; file="${spec#*:}"
  if ! grep -q 'check-inflight-batch.sh' "$REPO_ROOT/$file"; then
    fail "case9 wiring ($label)" "no check-inflight-batch.sh call in $file"
    WIRE_OK=0
  fi
done
[ "$WIRE_OK" -eq 1 ] && pass "case9 all 3 pickup workers wire the guard"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
