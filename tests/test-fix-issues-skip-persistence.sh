#!/bin/bash
# test-fix-issues-skip-persistence.sh — coverage for issue #808:
# persist /fix-issues triage-decline decisions as machine-readable skip-
# state in `$MAIN_ROOT/.zskills/monitor-state.json` so subsequent fires
# drop the candidate BEFORE re-triage.
#
# Pre-#808 the plan-scale (and any auto-skip tier) decline path only
# reported the decision to SPRINT_REPORT.md. The next fire re-triaged
# the same issue, re-declined, and repeated indefinitely — acute in
# dashboard mode where raw-dragged issues had no tracker row at all
# (#803 case).
#
# The fix has two halves:
#   (1) record-skip.sh writes `issues.skipped[<N>] = <code>` into
#       monitor-state.json (atomic, idempotent, gitignored).
#   (2) filter-unresearched-candidates.sh reads `issues.skipped` and
#       unions matching entries into SKIP_TAGGED — even when the issue
#       has no tracker row at all (the raw-dashboard-drag case the
#       previous filter would emit as MISSING and route through
#       research-on-demand).
#
# Plus: sprint.md's Phase 3 triage-decline write-back (both cherry-pick
# and PR mode arms) MUST invoke record-skip.sh alongside the existing
# scratchpad `**Action now:**` rewrite. The latter persistence layer
# (committed `ISSUES_PLAN.md` row) was already in place; we assert it
# is PRESERVED so the new monitor-state write-back doesn't displace
# the canonical tracker row.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FILTER="$REPO_ROOT/skills/fix-issues/scripts/filter-unresearched-candidates.sh"
RECORD="$REPO_ROOT/skills/fix-issues/scripts/record-skip.sh"
SKILL="$REPO_ROOT/skills/fix-issues/modes/sprint.md"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SCRATCH="/tmp/test-fix-issues-skip-persistence-$$"
cleanup() {
  [ -n "${TEST_KEEP_SCRATCH:-}" ] && return
  if [ -d "$SCRATCH" ]; then
    find "$SCRATCH" -type d -exec chmod u+rwx {} \; 2>/dev/null || true
    rm -rf "$SCRATCH"
  fi
}
trap cleanup EXIT INT TERM
mkdir -p "$SCRATCH"

echo "=== /fix-issues skip-state persistence (#808) ==="

# --- Sanity: both scripts exist and are executable -----------------------
test_scripts_present() {
  if [ -f "$RECORD" ] && [ -x "$RECORD" ]; then
    pass "record-skip.sh exists and is executable"
  else
    fail "record-skip.sh exists and is executable" "missing: $RECORD"
  fi
  if [ -f "$FILTER" ] && [ -x "$FILTER" ]; then
    pass "filter-unresearched-candidates.sh exists and is executable"
  else
    fail "filter-unresearched-candidates.sh exists and is executable" "missing: $FILTER"
  fi
}

# Helper: build a minimal MAIN_ROOT with a git repo so record-skip's
# git-rev-parse fallback works the same as the rest-of-skill paths.
make_main_root() {
  local d="$1"
  mkdir -p "$d"
  ( cd "$d" && git init -q && git config user.email t@t && git config user.name t \
      && git commit --allow-empty -q -m init ) >/dev/null
}

# Helper: read issues.skipped[<n>] from a monitor-state.json file.
read_skip() {
  python3 -c "
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    print((data.get('issues', {}).get('skipped', {}) or {}).get(sys.argv[2], ''))
except Exception:
    pass
" "$1" "$2"
}

# --- 1. record-skip.sh writes the issues.skipped entry -------------------
test_record_skip_writes_entry() {
  local d="$SCRATCH/record-basic"
  make_main_root "$d"
  ZSKILLS_MAIN_ROOT="$d" bash "$RECORD" 803 plan-scale >/dev/null 2>&1
  local got
  got=$(read_skip "$d/.zskills/monitor-state.json" 803)
  if [ "$got" = "plan-scale" ]; then
    pass "record-skip writes issues.skipped[803] = plan-scale"
  else
    fail "record-skip writes issues.skipped[803] = plan-scale" "got '$got'"
  fi
}

# --- 1b. record-skip is idempotent (same code re-recorded) ---------------
test_record_skip_idempotent() {
  local d="$SCRATCH/record-idem"
  make_main_root "$d"
  ZSKILLS_MAIN_ROOT="$d" bash "$RECORD" 803 plan-scale >/dev/null 2>&1
  ZSKILLS_MAIN_ROOT="$d" bash "$RECORD" 803 plan-scale >/dev/null 2>&1
  local rc=$?
  local got
  got=$(read_skip "$d/.zskills/monitor-state.json" 803)
  if [ "$rc" -eq 0 ] && [ "$got" = "plan-scale" ]; then
    pass "record-skip idempotent re-write: rc=0, value unchanged"
  else
    fail "record-skip idempotent re-write" "rc=$rc got '$got'"
  fi
}

# --- 1c. record-skip overwrites with new code (re-classification) --------
test_record_skip_overwrite() {
  local d="$SCRATCH/record-over"
  make_main_root "$d"
  ZSKILLS_MAIN_ROOT="$d" bash "$RECORD" 803 plan-scale >/dev/null 2>&1
  ZSKILLS_MAIN_ROOT="$d" bash "$RECORD" 803 deferred   >/dev/null 2>&1
  local got
  got=$(read_skip "$d/.zskills/monitor-state.json" 803)
  if [ "$got" = "deferred" ]; then
    pass "record-skip overwrites with new code (plan-scale -> deferred)"
  else
    fail "record-skip overwrites with new code" "got '$got'"
  fi
}

# --- 1d. record-skip rejects invalid skip-code ---------------------------
test_record_skip_rejects_bogus_code() {
  local d="$SCRATCH/record-bogus"
  make_main_root "$d"
  local rc=0
  ZSKILLS_MAIN_ROOT="$d" bash "$RECORD" 803 bogus-code >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 1 ]; then
    pass "record-skip rejects invalid skip-code (rc=1)"
  else
    fail "record-skip rejects invalid skip-code" "expected rc=1, got rc=$rc"
  fi
}

# --- 1e. record-skip rejects non-integer issue-num -----------------------
test_record_skip_rejects_bogus_num() {
  local d="$SCRATCH/record-bogus2"
  make_main_root "$d"
  local rc=0
  ZSKILLS_MAIN_ROOT="$d" bash "$RECORD" "8x3" plan-scale >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 1 ]; then
    pass "record-skip rejects non-integer issue-num (rc=1)"
  else
    fail "record-skip rejects non-integer issue-num" "expected rc=1, got rc=$rc"
  fi
}

# --- 2. Filter sees monitor-state skip even WITHOUT tracker row ----------
# This is the raw-dashboard-drag case (#803) — the issue has no row in
# any *.md under ZSKILLS_ISSUES_DIR, but issues.skipped has it.
test_filter_drops_unrowed_via_monitor_state() {
  local issues_dir="$SCRATCH/filter-unrowed/issues"
  local main_root="$SCRATCH/filter-unrowed/main"
  mkdir -p "$issues_dir"
  make_main_root "$main_root"
  # Tracker dir intentionally empty (no rows for 803).
  : > "$issues_dir/ISSUES.md"
  # Seed monitor-state via record-skip.
  ZSKILLS_MAIN_ROOT="$main_root" bash "$RECORD" 803 plan-scale >/dev/null 2>&1

  local out skip_tagged researched missing
  out=$(ZSKILLS_ISSUES_DIR="$issues_dir" ZSKILLS_MAIN_ROOT="$main_root" bash "$FILTER" 803)
  skip_tagged=$(echo "$out" | grep '^SKIP_TAGGED=' | sed -e 's/^SKIP_TAGGED=//' -e 's/^"//' -e 's/"$//')
  researched=$(echo "$out" | grep '^RESEARCHED=' | sed -e 's/^RESEARCHED=//' -e 's/^"//' -e 's/"$//')
  missing=$(echo "$out" | grep '^MISSING=' | sed -e 's/^MISSING=//' -e 's/^"//' -e 's/"$//')

  if [ "$skip_tagged" = "803:plan-scale" ] && [ "$researched" = "803" ] && [ -z "$missing" ]; then
    pass "filter drops unrowed candidate via monitor-state (#803 raw dashboard-drag case)"
  else
    fail "filter drops unrowed candidate via monitor-state" \
         "SKIP_TAGGED=[$skip_tagged] RESEARCHED=[$researched] MISSING=[$missing]"
  fi
}

# --- 2b. Filter unions monitor-state skip with tracker-row skip ----------
# Rowed issue WITH plan-scale tracker-tag already (the legacy path).
# Pre-#808 this path was the only one that worked. Confirm it still does
# (regression guard) AND that adding a monitor-state entry for the same
# issue stays consistent (filter must not double-emit).
test_filter_rowed_plus_monitor_state() {
  local issues_dir="$SCRATCH/filter-rowed/issues"
  local main_root="$SCRATCH/filter-rowed/main"
  mkdir -p "$issues_dir"
  make_main_root "$main_root"
  cat > "$issues_dir/ISSUES.md" <<'EOF'
### #700 — plan-scale rowed
**Action now:** /draft-plan — needs design review.
EOF
  ZSKILLS_MAIN_ROOT="$main_root" bash "$RECORD" 700 plan-scale >/dev/null 2>&1

  local out skip_tagged
  out=$(ZSKILLS_ISSUES_DIR="$issues_dir" ZSKILLS_MAIN_ROOT="$main_root" bash "$FILTER" 700)
  skip_tagged=$(echo "$out" | grep '^SKIP_TAGGED=' | sed -e 's/^SKIP_TAGGED=//' -e 's/^"//' -e 's/"$//')
  # Tracker-row skip-tag wins (canonical); monitor-state agrees; expect
  # exactly one 700:plan-scale entry.
  if [ "$skip_tagged" = "700:plan-scale" ]; then
    pass "filter unions rowed + monitor-state without double-emit"
  else
    fail "filter unions rowed + monitor-state" "SKIP_TAGGED=[$skip_tagged]"
  fi
}

# --- 2c. Reconsider list still suppresses monitor-state skip -------------
# `reconsider <N>` is the deliberate un-skip lever — it must override
# both the row-derived skip-tag and the monitor-state skip-tag, so the
# issue re-enters triage on the current fire.
test_filter_reconsider_overrides_monitor_state() {
  local issues_dir="$SCRATCH/filter-recon/issues"
  local main_root="$SCRATCH/filter-recon/main"
  mkdir -p "$issues_dir"
  make_main_root "$main_root"
  : > "$issues_dir/ISSUES.md"
  ZSKILLS_MAIN_ROOT="$main_root" bash "$RECORD" 803 plan-scale >/dev/null 2>&1
  # Seed reconsider with 803.
  python3 -c "
import json
p = '$main_root/.zskills/monitor-state.json'
data = json.load(open(p))
data.setdefault('issues', {})['reconsider'] = [803]
json.dump(data, open(p, 'w'), indent=2)
"
  local out skip_tagged missing
  out=$(ZSKILLS_ISSUES_DIR="$issues_dir" ZSKILLS_MAIN_ROOT="$main_root" bash "$FILTER" 803)
  skip_tagged=$(echo "$out" | grep '^SKIP_TAGGED=' | sed -e 's/^SKIP_TAGGED=//' -e 's/^"//' -e 's/"$//')
  missing=$(echo "$out" | grep '^MISSING=' | sed -e 's/^MISSING=//' -e 's/^"//' -e 's/"$//')
  if [ -z "$skip_tagged" ] && [ "$missing" = "803" ]; then
    pass "reconsider overrides monitor-state skip (issue re-enters triage as MISSING)"
  else
    fail "reconsider overrides monitor-state" \
         "expected SKIP_TAGGED=[] MISSING=[803], got SKIP_TAGGED=[$skip_tagged] MISSING=[$missing]"
  fi
}

# --- 2d. Reconsider one-shot cleanup ALSO removes issues.skipped entry --
# After the filter emits a reconsidered issue, both `issues.reconsider`
# AND any matching `issues.skipped` entries are removed so the un-skip
# decision sticks (the issue can be re-classified on its merits).
test_reconsider_cleanup_removes_skip() {
  local issues_dir="$SCRATCH/filter-cleanup/issues"
  local main_root="$SCRATCH/filter-cleanup/main"
  mkdir -p "$issues_dir"
  make_main_root "$main_root"
  : > "$issues_dir/ISSUES.md"
  ZSKILLS_MAIN_ROOT="$main_root" bash "$RECORD" 803 plan-scale >/dev/null 2>&1
  python3 -c "
import json
p = '$main_root/.zskills/monitor-state.json'
data = json.load(open(p))
data.setdefault('issues', {})['reconsider'] = [803]
json.dump(data, open(p, 'w'), indent=2)
"
  ZSKILLS_ISSUES_DIR="$issues_dir" ZSKILLS_MAIN_ROOT="$main_root" bash "$FILTER" 803 >/dev/null
  local after
  after=$(read_skip "$main_root/.zskills/monitor-state.json" 803)
  local recon_after
  recon_after=$(python3 -c "
import json
data = json.load(open('$main_root/.zskills/monitor-state.json'))
print(','.join(str(x) for x in data.get('issues', {}).get('reconsider', [])))
")
  if [ -z "$after" ] && [ -z "$recon_after" ]; then
    pass "reconsider one-shot cleanup removes BOTH issues.reconsider AND issues.skipped entries"
  else
    fail "reconsider one-shot cleanup" \
         "expected both empty, got skipped=[$after] reconsider=[$recon_after]"
  fi
}

# --- 3. SKILL.md sprint mode invokes record-skip in BOTH Phase 3 arms ---
test_skill_invokes_record_skip_both_arms() {
  local count
  count=$(grep -c 'record-skip.sh' "$SKILL")
  if [ "$count" -ge 2 ]; then
    pass "sprint.md invokes record-skip.sh in BOTH triage-decline arms ($count refs >=2)"
  else
    fail "sprint.md invokes record-skip.sh in both arms" \
         "expected >=2 (cherry-pick + PR-mode), got $count"
  fi
}

# --- 3b. SKILL.md preserves existing scratchpad rewrite -----------------
# Phase 3 in-loop write-back (existing) MUST still rewrite the
# scratchpad `**Action now:**` line — record-skip is ADDITIVE, not a
# replacement. Lock both sed-i Action-now rewrites and >=10 NEW_ACTION_NOW
# assignments (5 cases × 2 modes) per the canonical literal set.
test_skill_preserves_phase3_writeback() {
  local sed_count nan_count
  sed_count=$(grep -c 'sed -i.*Action now' "$SKILL")
  nan_count=$(grep -c '^[[:space:]]*NEW_ACTION_NOW=' "$SKILL")
  if [ "$sed_count" -eq 2 ] && [ "$nan_count" -ge 10 ]; then
    pass "sprint.md preserves existing Phase 3 scratchpad rewrite (sed=2, NEW_ACTION_NOW=$nan_count)"
  else
    fail "sprint.md preserves Phase 3 scratchpad rewrite" \
         "expected sed=2 NEW_ACTION_NOW>=10, got sed=$sed_count NEW_ACTION_NOW=$nan_count"
  fi
}

# --- 3c. SKILL.md preserves canonical /draft-plan literal --------------
# The canonical literal the Phase 3 write-back uses for plan-scale is
# load-bearing: filter-unresearched-candidates.sh greps the tracker row
# for `Action now:.*draft-plan` to derive the `:plan-scale` skip-tag.
# Lock the exact substring so a stylistic edit doesn't desync the two.
test_skill_canonical_draft_plan_literal() {
  local hits
  hits=$(grep -c '\*\*Action now:\*\* /draft-plan — plan-scale design surface; needs adversarial plan review before any fix\.' "$SKILL")
  if [ "$hits" -ge 2 ]; then
    pass "sprint.md preserves canonical /draft-plan write-back literal ($hits hits, expected >=2)"
  else
    fail "sprint.md canonical /draft-plan literal" "expected >=2 hits, got $hits"
  fi
}

# --- 4. record-skip uses atomic temp+replace (not in-place write) ------
# Lock the atomic-write pattern so a future "simplification" doesn't
# leave half-written state files on crash.
test_record_uses_atomic_write() {
  if grep -qF 'tempfile.NamedTemporaryFile' "$RECORD" \
     && grep -qF 'os.replace' "$RECORD"; then
    pass "record-skip.sh uses tempfile + os.replace (atomic write)"
  else
    fail "record-skip.sh atomic write" "missing tempfile.NamedTemporaryFile or os.replace"
  fi
}

# --- Run all -----------------------------------------------------------
test_scripts_present
test_record_skip_writes_entry
test_record_skip_idempotent
test_record_skip_overwrite
test_record_skip_rejects_bogus_code
test_record_skip_rejects_bogus_num
test_filter_drops_unrowed_via_monitor_state
test_filter_rowed_plus_monitor_state
test_filter_reconsider_overrides_monitor_state
test_reconsider_cleanup_removes_skip
test_skill_invokes_record_skip_both_arms
test_skill_preserves_phase3_writeback
test_skill_canonical_draft_plan_literal
test_record_uses_atomic_write

echo ""
echo "---"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
[ "$FAIL_COUNT" -eq 0 ]
