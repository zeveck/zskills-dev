#!/bin/bash
# test-inflight-reentry-guard.sh — issue #883.
#
# Tests the per-work-identity in-flight guard wired into /run-plan and
# /do. Builds on the shared session-scoped helper from #877; #883 added
# an optional `--pipeline-id` filter to `check` so the skip-key matches
# THIS plan / THIS task in flight, not "any same-skill run."
#
# Helper-level unit tests (the #883 additions):
#   - check with --pipeline-id filter matches only the named pipeline_id
#   - check with --pipeline-id filter ignores other-pipeline same-session sentinels
#   - two different pipeline_ids under the same skill+session both proceed
#     when filtered; both skip when unfiltered (back-compat with #877)
#   - input validation: bad --pipeline-id rejected at check time
#
# Wiring assertions:
#   - skills/run-plan/SKILL.md sources the helper at the same-plan guard
#     fence (check + write with --pipeline-id)
#   - skills/run-plan/modes/execute-phase.md clears the sentinel at the
#     Phase 5b no-op AND Phase 6 terminal-merge release points
#   - skills/do/modes/{pr,worktree,direct}.md source the helper at the
#     entry guard
#   - skills/do/SKILL.md Phase 5 Report clears the sentinel (worktree
#     and direct modes; pr clears inline in modes/pr.md's finalize)
#   - mirror parity for the modified files

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$REPO_ROOT/skills/create-worktree/scripts/check-inflight-batch.sh"

PASS=0
FAIL=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

SCRATCH="/tmp/test-inflight-reentry-guard-$$"
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

echo "=== helper presence ==="
if [ -x "$HELPER" ]; then
  pass "helper exists and is executable"
else
  fail "helper exists and is executable" "missing or non-executable at $HELPER"
  echo "Results: $PASS passed, $FAIL failed"; exit 1
fi

echo ""
echo "=== check --pipeline-id (same work in flight, same session) ==="
(cd "$FIXTURE" && bash "$HELPER" write run-plan --pipeline-id "run-plan.plan-a" --session-id "TEST-SID-1")
out=$(cd "$FIXTURE" && bash "$HELPER" check run-plan --session-id "TEST-SID-1" --pipeline-id "run-plan.plan-a" 2>/dev/null)
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "check rc=0 (in-flight) when filter matches existing pipeline_id"
else
  fail "check rc=0 (in-flight) when filter matches existing pipeline_id" "got rc=$rc"
fi
if printf '%s' "$out" | grep -q "run-plan.plan-a"; then
  pass "check stdout names the matching pipeline_id"
else
  fail "check stdout names the matching pipeline_id" "stdout='$out'"
fi

echo ""
echo "=== check --pipeline-id filter ignores other-pipeline sentinels ==="
(cd "$FIXTURE" && bash "$HELPER" write run-plan --pipeline-id "run-plan.plan-b" --session-id "TEST-SID-1")
# Now two sentinels exist for run-plan: plan-a and plan-b (same session).
# Filtering on plan-c should still PROCEED (no plan-c sentinel exists).
(cd "$FIXTURE" && bash "$HELPER" check run-plan --session-id "TEST-SID-1" --pipeline-id "run-plan.plan-c" >/dev/null 2>&1)
rc=$?
if [ "$rc" -eq 1 ]; then
  pass "filter on non-existent pipeline_id → proceed (rc=1)"
else
  fail "filter on non-existent pipeline_id → proceed (rc=1)" "got rc=$rc"
fi
# But filter on plan-b still matches.
(cd "$FIXTURE" && bash "$HELPER" check run-plan --session-id "TEST-SID-1" --pipeline-id "run-plan.plan-b" >/dev/null 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "filter on plan-b still matches its own sentinel (rc=0)"
else
  fail "filter on plan-b still matches its own sentinel (rc=0)" "got rc=$rc"
fi

echo ""
echo "=== two different plans in same session → both proceed when filtered ==="
# Imagine /run-plan invocations for plan-x and plan-y both starting fresh
# in the same session. Each should see no in-flight sentinel for its own
# pipeline_id, even though the other plan's sentinel exists.
(cd "$FIXTURE" && bash "$HELPER" write run-plan --pipeline-id "run-plan.plan-x" --session-id "TEST-SID-2")
(cd "$FIXTURE" && bash "$HELPER" check run-plan --session-id "TEST-SID-2" --pipeline-id "run-plan.plan-y" >/dev/null 2>&1)
rc=$?
if [ "$rc" -eq 1 ]; then
  pass "different plan in same session → proceeds (rc=1) when filtered"
else
  fail "different plan in same session → proceeds (rc=1) when filtered" "got rc=$rc"
fi
# Sanity: unfiltered check (the #877 shape) still reports in-flight for
# the same skill+session — back-compat.
(cd "$FIXTURE" && bash "$HELPER" check run-plan --session-id "TEST-SID-2" >/dev/null 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "unfiltered check (no --pipeline-id) still reports in-flight (back-compat with #877)"
else
  fail "unfiltered check still reports in-flight (back-compat)" "got rc=$rc"
fi

echo ""
echo "=== stale-escape applies under --pipeline-id filter ==="
# Same-pipeline match with max-age=0 should still escape (stale-reclaim
# robustness trap from #877 stays in force under the new filter).
(cd "$FIXTURE" && bash "$HELPER" check run-plan --session-id "TEST-SID-2" --pipeline-id "run-plan.plan-x" --max-age-seconds 0 >/dev/null 2>&1)
rc=$?
if [ "$rc" -eq 1 ]; then
  pass "stale escape applies even with --pipeline-id match (rc=1)"
else
  fail "stale escape applies even with --pipeline-id match (rc=1)" "got rc=$rc"
fi
# After stale escape, the sentinel must be removed (orphan reclaim).
remaining=$(cd "$FIXTURE" && bash "$HELPER" list run-plan 2>/dev/null | grep "run-plan.plan-x" || true)
if [ -z "$remaining" ]; then
  pass "stale escape removed the run-plan.plan-x sentinel"
else
  fail "stale escape removed the run-plan.plan-x sentinel" "list still has: $remaining"
fi

# Clean up remaining sentinels from earlier tests.
(cd "$FIXTURE" && bash "$HELPER" clear run-plan --pipeline-id "run-plan.plan-a") >/dev/null 2>&1
(cd "$FIXTURE" && bash "$HELPER" clear run-plan --pipeline-id "run-plan.plan-b") >/dev/null 2>&1

echo ""
echo "=== input validation: bad --pipeline-id rejected at check ==="
(cd "$FIXTURE" && bash "$HELPER" check run-plan --session-id "X" --pipeline-id '../escape' >/dev/null 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
  pass "check rejects path-traversal in --pipeline-id (rc=2)"
else
  fail "check rejects path-traversal in --pipeline-id (rc=2)" "got rc=$rc"
fi

echo ""
echo "=== /do same-task re-fire skip ==="
# Simulate /do composing the same TASK_SLUG twice (cron re-fire). First
# fire writes do.fix-readme sentinel; second fire's check should skip.
(cd "$FIXTURE" && bash "$HELPER" write do --pipeline-id "do.fix-readme" --session-id "TEST-SID-DO")
(cd "$FIXTURE" && bash "$HELPER" check do --session-id "TEST-SID-DO" --pipeline-id "do.fix-readme" >/dev/null 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "/do same-task re-fire detects sentinel and skips (rc=0)"
else
  fail "/do same-task re-fire detects sentinel and skips (rc=0)" "got rc=$rc"
fi

echo ""
echo "=== /do different-task in same session → proceeds ==="
(cd "$FIXTURE" && bash "$HELPER" check do --session-id "TEST-SID-DO" --pipeline-id "do.different-task" >/dev/null 2>&1)
rc=$?
if [ "$rc" -eq 1 ]; then
  pass "/do different-task proceeds even while another /do is in flight"
else
  fail "/do different-task proceeds" "got rc=$rc"
fi
(cd "$FIXTURE" && bash "$HELPER" clear do --pipeline-id "do.fix-readme") >/dev/null 2>&1

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

# /run-plan SKILL.md — same-plan guard fence (check + write with
# --pipeline-id).
RP_SKILL="$REPO_ROOT/skills/run-plan/SKILL.md"
assert_wired "run-plan SKILL.md: check call w/ --pipeline-id" "$RP_SKILL" \
  '"\$INFLIGHT_HELPER" check run-plan --pipeline-id "\$PIPELINE_ID"'
assert_wired "run-plan SKILL.md: write call w/ --pipeline-id" "$RP_SKILL" \
  '"\$INFLIGHT_HELPER" write run-plan --pipeline-id "\$PIPELINE_ID"'
assert_wired "run-plan SKILL.md: skip message" "$RP_SKILL" \
  'skipping redundant cron re-fire'
assert_wired "run-plan SKILL.md: same-plan guard heading" "$RP_SKILL" \
  'Same-plan in-flight guard (issue #883)'

# /run-plan modes/execute-phase.md — two clear sites (5b no-op + 6 terminal merge).
RP_EXEC="$REPO_ROOT/skills/run-plan/modes/execute-phase.md"
clear_count=$(grep -c '"\$INFLIGHT_HELPER" clear run-plan' "$RP_EXEC" || true)
if [ "$clear_count" -ge 2 ]; then
  pass "run-plan execute-phase.md: at least 2 clear sites (got $clear_count)"
else
  fail "run-plan execute-phase.md: at least 2 clear sites" "got $clear_count"
fi
assert_wired "run-plan execute-phase.md: clear w/ --pipeline-id" "$RP_EXEC" \
  '"\$INFLIGHT_HELPER" clear run-plan --pipeline-id "\$PIPELINE_ID"'

# /do mode files — entry-guard wiring.
DO_PR="$REPO_ROOT/skills/do/modes/pr.md"
DO_WT="$REPO_ROOT/skills/do/modes/worktree.md"
DO_DIR="$REPO_ROOT/skills/do/modes/direct.md"
DO_SKILL="$REPO_ROOT/skills/do/SKILL.md"

assert_wired "do pr.md: check call w/ --pipeline-id" "$DO_PR" \
  '"\$INFLIGHT_HELPER" check do --pipeline-id'
assert_wired "do pr.md: write call w/ --pipeline-id" "$DO_PR" \
  '"\$INFLIGHT_HELPER" write do --pipeline-id'
assert_wired "do pr.md: clear call (in modes/pr.md finalize)" "$DO_PR" \
  '"\$INFLIGHT_HELPER" clear do --pipeline-id'
assert_wired "do pr.md: skip message" "$DO_PR" \
  'skipping redundant cron re-fire'

assert_wired "do worktree.md: check call w/ --pipeline-id" "$DO_WT" \
  '"\$INFLIGHT_HELPER" check do --pipeline-id "\$PIPELINE_ID"'
assert_wired "do worktree.md: write call w/ --pipeline-id" "$DO_WT" \
  '"\$INFLIGHT_HELPER" write do --pipeline-id "\$PIPELINE_ID"'

assert_wired "do direct.md: check call w/ --pipeline-id" "$DO_DIR" \
  '"\$INFLIGHT_HELPER" check do --pipeline-id "\$PIPELINE_ID"'
assert_wired "do direct.md: write call w/ --pipeline-id" "$DO_DIR" \
  '"\$INFLIGHT_HELPER" write do --pipeline-id "\$PIPELINE_ID"'

assert_wired "do SKILL.md Phase 5: clear call (worktree/direct terminal)" "$DO_SKILL" \
  '"\$INFLIGHT_HELPER" clear do --pipeline-id'
assert_wired "do SKILL.md Phase 5: issue #883 annotation" "$DO_SKILL" \
  'Issue #883'

echo ""
echo "=== mirror parity (.claude/skills) ==="
for pair in \
  "create-worktree/scripts/check-inflight-batch.sh" \
  "run-plan/SKILL.md" \
  "run-plan/modes/execute-phase.md" \
  "do/SKILL.md" \
  "do/modes/pr.md" \
  "do/modes/worktree.md" \
  "do/modes/direct.md"; do
  SRC="$REPO_ROOT/skills/$pair"
  DST="$REPO_ROOT/.claude/skills/$pair"
  if diff -q "$SRC" "$DST" >/dev/null 2>&1; then
    pass "mirror parity: $pair"
  else
    fail "mirror parity: $pair" "src and .claude/skills mirror differ"
  fi
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
