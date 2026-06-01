#!/bin/bash
# test-inflight-batch-guard.sh — issue #877.
#
# Tests the shared session-scoped in-flight guard helper
# (skills/create-worktree/scripts/check-inflight-batch.sh) and the
# three call-site wirings (sprint.md, execute.md, qe-audit SKILL.md).
#
# Helper unit tests:
#   - resolve-session-id returns a non-empty stable value
#   - write + check (same session) → exit 0 (in-flight)
#   - write + check (different session) → exit 1 (proceed)
#   - write + check with max-age-seconds=0 → stale escape → exit 1
#   - clear removes the sentinel
#   - list emits TSV for live sentinels
#
# Wiring assertions (one per skill):
#   - skills/fix-issues/modes/sprint.md sources the helper at pickup entry
#   - skills/work-on-plans/modes/execute.md ditto at Step 4
#   - skills/qe-audit/SKILL.md ditto at Phase 0b
#   AND each writes + clears the sentinel via the helper.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$REPO_ROOT/skills/create-worktree/scripts/check-inflight-batch.sh"

PASS=0
FAIL=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

SCRATCH="/tmp/test-inflight-batch-guard-$$"
cleanup() {
  if [ -n "${TEST_KEEP_SCRATCH:-}" ]; then return; fi
  [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
}
trap cleanup EXIT INT TERM
mkdir -p "$SCRATCH"

# Fixture: real git repo so MAIN_ROOT resolves.
FIXTURE="$SCRATCH/fixture"
mkdir -p "$FIXTURE"
(
  cd "$FIXTURE"
  git init -q
  git config user.email "t@t"
  git config user.name "t"
  git commit --allow-empty -q -m init
) || { fail "fixture init" "git init failed"; echo "Results: $PASS passed, $((FAIL+1)) failed"; exit 1; }

echo "=== helper presence + executability ==="
if [ -x "$HELPER" ]; then
  pass "helper exists and is executable"
else
  fail "helper exists and is executable" "missing or non-executable at $HELPER"
  echo "Results: $PASS passed, $((FAIL)) failed"; exit 1
fi

echo ""
echo "=== resolve-session-id ==="
SID=$(cd "$FIXTURE" && bash "$HELPER" resolve-session-id)
if [ -n "$SID" ]; then
  pass "resolve-session-id returns non-empty value ($SID)"
else
  fail "resolve-session-id returns non-empty value" "got empty"
fi

# Stability across calls in the same shell.
SID2=$(cd "$FIXTURE" && bash "$HELPER" resolve-session-id)
if [ "$SID" = "$SID2" ]; then
  pass "resolve-session-id is stable across calls in same shell"
else
  fail "resolve-session-id is stable across calls in same shell" \
       "first=$SID second=$SID2"
fi

echo ""
echo "=== check (no sentinel) → proceed ==="
(cd "$FIXTURE" && bash "$HELPER" check fix-issues --session-id "TEST-SID-1" >/dev/null 2>&1)
rc=$?
if [ "$rc" -eq 1 ]; then
  pass "check returns rc=1 when no sentinel"
else
  fail "check returns rc=1 when no sentinel" "got rc=$rc"
fi

echo ""
echo "=== write + check (same session) → in-flight ==="
(cd "$FIXTURE" && bash "$HELPER" write fix-issues --pipeline-id "fix-issues.test-A" --session-id "TEST-SID-1") || \
  fail "write" "exit non-zero"
out=$(cd "$FIXTURE" && bash "$HELPER" check fix-issues --session-id "TEST-SID-1" 2>/dev/null)
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "check returns rc=0 (in-flight) when matching sentinel exists"
else
  fail "check returns rc=0 (in-flight) when matching sentinel exists" "got rc=$rc"
fi
if printf '%s' "$out" | grep -q "fix-issues.test-A"; then
  pass "check stdout includes the matching pipeline-id"
else
  fail "check stdout includes the matching pipeline-id" "stdout='$out'"
fi

echo ""
echo "=== check (different session) → proceed ==="
(cd "$FIXTURE" && bash "$HELPER" check fix-issues --session-id "TEST-SID-2" >/dev/null 2>&1)
rc=$?
if [ "$rc" -eq 1 ]; then
  pass "check returns rc=1 when sentinel exists for a different session"
else
  fail "check returns rc=1 when sentinel exists for a different session" "got rc=$rc"
fi

echo ""
echo "=== staleness escape (max-age=0) ==="
(cd "$FIXTURE" && bash "$HELPER" check fix-issues --session-id "TEST-SID-1" --max-age-seconds 0 >/dev/null 2>&1)
rc=$?
if [ "$rc" -eq 1 ]; then
  pass "stale sentinel (max-age=0) → escape (rc=1)"
else
  fail "stale sentinel (max-age=0) → escape (rc=1)" "got rc=$rc"
fi
# After stale escape, sentinel must be removed.
remaining=$(cd "$FIXTURE" && bash "$HELPER" list fix-issues 2>/dev/null)
if [ -z "$remaining" ]; then
  pass "stale escape removes the orphan sentinel"
else
  fail "stale escape removes the orphan sentinel" "list still emits: $remaining"
fi

echo ""
echo "=== write + clear ==="
(cd "$FIXTURE" && bash "$HELPER" write fix-issues --pipeline-id "fix-issues.test-B" --session-id "TEST-SID-1") \
  || fail "write" "exit non-zero"
(cd "$FIXTURE" && bash "$HELPER" clear fix-issues --pipeline-id "fix-issues.test-B")
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "clear returns rc=0"
else
  fail "clear returns rc=0" "got rc=$rc"
fi
remaining=$(cd "$FIXTURE" && bash "$HELPER" list fix-issues 2>/dev/null)
if [ -z "$remaining" ]; then
  pass "clear removes the sentinel"
else
  fail "clear removes the sentinel" "list still emits: $remaining"
fi
# Idempotent: clear an already-cleared sentinel.
(cd "$FIXTURE" && bash "$HELPER" clear fix-issues --pipeline-id "fix-issues.test-B")
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "clear is idempotent (re-clear returns rc=0)"
else
  fail "clear is idempotent" "got rc=$rc"
fi

echo ""
echo "=== multi-skill isolation ==="
(cd "$FIXTURE" && bash "$HELPER" write fix-issues --pipeline-id "fix-issues.iso" --session-id "TEST-SID-1")
(cd "$FIXTURE" && bash "$HELPER" check work-on-plans --session-id "TEST-SID-1" >/dev/null 2>&1)
rc=$?
if [ "$rc" -eq 1 ]; then
  pass "fix-issues sentinel does not gate work-on-plans"
else
  fail "fix-issues sentinel does not gate work-on-plans" "got rc=$rc"
fi
(cd "$FIXTURE" && bash "$HELPER" check qe-audit --session-id "TEST-SID-1" >/dev/null 2>&1)
rc=$?
if [ "$rc" -eq 1 ]; then
  pass "fix-issues sentinel does not gate qe-audit"
else
  fail "fix-issues sentinel does not gate qe-audit" "got rc=$rc"
fi
(cd "$FIXTURE" && bash "$HELPER" clear fix-issues --pipeline-id "fix-issues.iso") >/dev/null 2>&1

echo ""
echo "=== input-validation ==="
# Bad skill name (contains uppercase / slash).
(cd "$FIXTURE" && bash "$HELPER" check 'BadSkill' >/dev/null 2>&1)
rc=$?
if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
  pass "invalid skill name rejected (usage error rc=$rc)"
else
  fail "invalid skill name rejected" "got rc=$rc"
fi
(cd "$FIXTURE" && bash "$HELPER" write fix-issues --pipeline-id '../escape' --session-id 'X' >/dev/null 2>&1)
rc=$?
if [ "$rc" -ne 0 ]; then
  pass "invalid pipeline-id rejected (rc=$rc)"
else
  fail "invalid pipeline-id rejected" "got rc=0"
fi

echo ""
echo "=== #908 — prefer CLAUDE_CODE_SESSION_ID for session resolution ==="
# resolve-session-id prefers the harness-provided env var (cc- prefix).
SID_ENV=$(cd "$FIXTURE" && CLAUDE_CODE_SESSION_ID="UUID-ABC-123" bash "$HELPER" resolve-session-id)
if [ "$SID_ENV" = "cc-UUID-ABC-123" ]; then
  pass "resolve-session-id prefers CLAUDE_CODE_SESSION_ID (#908)"
else
  fail "resolve-session-id prefers CLAUDE_CODE_SESSION_ID (#908)" "got '$SID_ENV'"
fi
# Falls back to proc/file resolution (non-cc) when the env var is absent.
SID_FB=$(cd "$FIXTURE" && env -u CLAUDE_CODE_SESSION_ID bash "$HELPER" resolve-session-id)
if [ -n "$SID_FB" ] && [ "${SID_FB#cc-}" = "$SID_FB" ]; then
  pass "resolve-session-id falls back (non-cc) when env var unset (#908)"
else
  fail "resolve-session-id falls back when env var unset (#908)" "got '$SID_FB'"
fi
# End-to-end: the env-var session scopes the guard (same id → in-flight;
# different id → proceed) even with no --session-id override.
(cd "$FIXTURE" && CLAUDE_CODE_SESSION_ID="UUID-ENV-1" bash "$HELPER" write fix-issues --pipeline-id "fix-issues.env1" >/dev/null 2>&1)
(cd "$FIXTURE" && CLAUDE_CODE_SESSION_ID="UUID-ENV-1" bash "$HELPER" check fix-issues >/dev/null 2>&1); rc_same=$?
(cd "$FIXTURE" && CLAUDE_CODE_SESSION_ID="UUID-ENV-2" bash "$HELPER" check fix-issues >/dev/null 2>&1); rc_diff=$?
if [ "$rc_same" -eq 0 ] && [ "$rc_diff" -eq 1 ]; then
  pass "env-var session scoping: same id in-flight, different proceeds (#908)"
else
  fail "env-var session scoping (#908)" "same=$rc_same(want 0) diff=$rc_diff(want 1)"
fi

echo ""
echo "=== call-site wiring assertions ==="

assert_wired() {
  local label="$1"; local file="$2"; local fragment="$3"
  if grep -q "$fragment" "$file"; then
    pass "$label"
  else
    fail "$label" "fragment '$fragment' not found in $file"
  fi
}

# /fix-issues sprint mode — check + write + clear all present.
SPRINT="$REPO_ROOT/skills/fix-issues/modes/sprint.md"
assert_wired "fix-issues sprint: check call" "$SPRINT" '"\$INFLIGHT_HELPER" check fix-issues'
assert_wired "fix-issues sprint: write call" "$SPRINT" '"\$INFLIGHT_HELPER" write fix-issues'
assert_wired "fix-issues sprint: clear call" "$SPRINT" '"\$INFLIGHT_HELPER" clear fix-issues'
# Skip skipping message anchored as the spec wording.
assert_wired "fix-issues sprint: skip message" "$SPRINT" 'skipping redundant cron pickup'

# /work-on-plans execute mode.
EXECUTE="$REPO_ROOT/skills/work-on-plans/modes/execute.md"
assert_wired "work-on-plans execute: check call" "$EXECUTE" '"\$INFLIGHT_HELPER" check work-on-plans'
assert_wired "work-on-plans execute: write call" "$EXECUTE" '"\$INFLIGHT_HELPER" write work-on-plans'
assert_wired "work-on-plans execute: clear call" "$EXECUTE" '"\$INFLIGHT_HELPER" clear work-on-plans'
assert_wired "work-on-plans execute: skip message" "$EXECUTE" 'skipping redundant cron pickup'

# /qe-audit.
QE="$REPO_ROOT/skills/qe-audit/SKILL.md"
assert_wired "qe-audit: check call" "$QE" '"\$INFLIGHT_HELPER" check qe-audit'
assert_wired "qe-audit: write call" "$QE" '"\$INFLIGHT_HELPER" write qe-audit'
assert_wired "qe-audit: clear call" "$QE" '"\$INFLIGHT_HELPER" clear qe-audit'
assert_wired "qe-audit: skip message" "$QE" 'skipping redundant cron pickup'

# Mirror parity: each .claude/skills/<skill>/ has the same wiring.
for pair in "fix-issues/modes/sprint.md" "work-on-plans/modes/execute.md" "qe-audit/SKILL.md"; do
  SRC="$REPO_ROOT/skills/$pair"
  DST="$REPO_ROOT/.claude/skills/$pair"
  if diff -q "$SRC" "$DST" >/dev/null 2>&1; then
    pass "mirror parity: $pair"
  else
    fail "mirror parity: $pair" "src and .claude/skills mirror differ"
  fi
done

# Helper itself mirrored too.
SRC_HELPER="$REPO_ROOT/skills/create-worktree/scripts/check-inflight-batch.sh"
DST_HELPER="$REPO_ROOT/.claude/skills/create-worktree/scripts/check-inflight-batch.sh"
if diff -q "$SRC_HELPER" "$DST_HELPER" >/dev/null 2>&1; then
  pass "mirror parity: helper script"
else
  fail "mirror parity: helper script" "src and .claude/skills mirror differ"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
