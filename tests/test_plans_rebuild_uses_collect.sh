#!/bin/bash
# Tests for skills/plans/SKILL.md (Phase 9 of plans/ZSKILLS_MONITOR_PLAN.md):
# verifies that `/plans rebuild | next | details` consume the Phase 4 Python
# aggregator (skills/zskills-dashboard/scripts/zskills_monitor/collect.py) as
# the single source of truth for plan classification.
#
# Two layers of coverage:
#  1) SKILL.md prose layer — grep that the new wrapper invocation, JSON-field
#     references, and section mapping are present, and that the OLD prose
#     classifier is gone.
#  2) Aggregator-output layer — invoke the aggregator against test fixtures,
#     apply the section mapping documented in the SKILL.md, and assert each
#     fixture lands in the expected section.
#
# Per-test scratch log goes to $TEST_OUT/test_plans_rebuild_uses_collect.log.
# This is NOT the canonical $TEST_OUT/.test-results.txt verifier capture
# (CLAUDE.md "Capture test output to a file" idiom) — that path is owned by
# the OUTER runner capture (e.g. `bash tests/run-all.sh > .../.test-results.txt`)
# and must not be truncated by individual tests, or earlier failures vanish.
#
# Run from repo root: bash tests/test_plans_rebuild_uses_collect.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_MD="$REPO_ROOT/skills/plans/SKILL.md"
MIRROR_MD="$REPO_ROOT/.claude/skills/plans/SKILL.md"
PKG_PARENT="$REPO_ROOT/skills/zskills-dashboard/scripts"
COLLECT_PY="$PKG_PARENT/zskills_monitor/collect.py"
FIXTURES="$REPO_ROOT/tests/fixtures/monitor"

TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
mkdir -p "$TEST_OUT"
RESULTS="$TEST_OUT/test_plans_rebuild_uses_collect.log"
: > "$RESULTS"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

pass() {
  printf '\033[32m  PASS\033[0m %s\n' "$1"
  printf '  PASS %s\n' "$1" >> "$RESULTS"
  PASS_COUNT=$((PASS_COUNT + 1))
}
fail() {
  printf '\033[31m  FAIL\033[0m %s\n' "$1"
  printf '  FAIL %s\n' "$1" >> "$RESULTS"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}
skip() {
  printf '\033[33m  SKIP\033[0m %s\n' "$1"
  printf '  SKIP %s\n' "$1" >> "$RESULTS"
  SKIP_COUNT=$((SKIP_COUNT + 1))
}

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------
echo "=== Phase 9: /plans rebuild uses collect.py — preconditions ==="

if [ ! -f "$SKILL_MD" ]; then
  fail "skills/plans/SKILL.md exists"
  printf 'Results: %d passed, %d failed, %d skipped\n' \
    "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
  exit 1
fi
pass "skills/plans/SKILL.md exists"

if [ ! -f "$COLLECT_PY" ]; then
  fail "collect.py exists at expected path ($COLLECT_PY)"
  printf 'Results: %d passed, %d failed, %d skipped\n' \
    "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
  exit 1
fi
pass "collect.py exists at expected path"

# ---------------------------------------------------------------------------
# Layer 1: SKILL.md prose grep checks (matches AC-1 through AC-4 verbatim)
# ---------------------------------------------------------------------------
echo ""
echo "=== Phase 9 AC-1: SKILL.md references zskills_monitor.collect ==="

if grep -nE 'zskills_monitor\.collect|collect_snapshot' "$SKILL_MD" > /dev/null 2>&1; then
  pass "AC-1: SKILL.md references zskills_monitor.collect or collect_snapshot"
else
  fail "AC-1: SKILL.md does not reference zskills_monitor.collect"
fi

echo ""
echo "=== Phase 9 AC-2: SKILL.md uses canonical PYTHONPATH prefix ==="

if grep -nE 'PYTHONPATH.*skills/zskills-dashboard/scripts' "$SKILL_MD" > /dev/null 2>&1; then
  pass "AC-2: SKILL.md uses canonical PYTHONPATH=...skills/zskills-dashboard/scripts prefix"
else
  fail "AC-2: SKILL.md missing canonical PYTHONPATH prefix"
fi

echo ""
echo "=== Phase 9 AC-3: SKILL.md references Phase 4 category/meta_plan fields ==="

if grep -nE '"category"\s*:\s*"(canary|issue_tracker|reference|executable)"|"meta_plan"\s*:\s*true' \
    "$SKILL_MD" > /dev/null 2>&1; then
  pass "AC-3: SKILL.md references category/meta_plan field shape"
else
  fail "AC-3: SKILL.md missing category/meta_plan JSON-field reference"
fi

echo ""
echo "=== Phase 9 AC-4: old prose classifier removed ==="

# Should return NO matches in the new SKILL.md.
if grep -nE 'classify as \*\*Ready\*\*|classify every `\.md`' \
    "$SKILL_MD" > /dev/null 2>&1; then
  fail "AC-4: SKILL.md still contains old prose classifier phrasing"
else
  pass "AC-4: old prose classifier ('classify every .md', 'classify as Ready') removed"
fi

# ---------------------------------------------------------------------------
# Layer 1b: source/mirror parity (AC-5)
# ---------------------------------------------------------------------------
echo ""
echo "=== Phase 9 AC-5: source/mirror byte-parity ==="

if [ ! -f "$MIRROR_MD" ]; then
  fail "AC-5: .claude/skills/plans/SKILL.md mirror exists"
else
  if cmp -s "$SKILL_MD" "$MIRROR_MD"; then
    pass "AC-5: skills/plans/SKILL.md == .claude/skills/plans/SKILL.md (byte-identical)"
  else
    fail "AC-5: skills/plans/SKILL.md and .claude/skills/plans/SKILL.md diverge"
  fi
fi

# Stronger: full directory diff (matches AC-5 invocation verbatim).
DIFF_OUT=$(diff -rq "$REPO_ROOT/skills/plans/" "$REPO_ROOT/.claude/skills/plans/" 2>&1 \
  | grep -v __pycache__ || true)
if [ -z "$DIFF_OUT" ]; then
  pass "AC-5: diff -rq skills/plans/ .claude/skills/plans/ clean (modulo __pycache__)"
else
  fail "AC-5: diff -rq output non-empty: $DIFF_OUT"
fi

# ---------------------------------------------------------------------------
# Layer 2: aggregator-output layer — exercise the section mapping against
# real fixtures, asserting each lands in the expected section
# ---------------------------------------------------------------------------
echo ""
echo "=== Phase 9 AC-6: section mapping matches Phase 4 categorization rules ==="

if ! command -v python3 >/dev/null 2>&1; then
  skip "python3 not available — skipping aggregator-output tests"
else
  # Canary fixture → Canaries section (regardless of status).
  CAT_CANARY=$(PYTHONPATH="$PKG_PARENT" python3 -m zskills_monitor.collect \
    --fixture "$FIXTURES/category-canary" 2>&1 | python3 -c '
import json,sys
d=json.load(sys.stdin)
p=d["plans"][0]
# Apply SKILL.md section mapping.
status = p["status"]
cat = p["category"]
phases_done = p["phases_done"]
phase_count = p["phase_count"]
queue_col = (p.get("queue") or {}).get("column")
if cat == "canary":
    section = "Canaries"
elif cat in ("reference","issue_tracker"):
    section = "Reference"
elif status in ("complete","landed"):
    section = "Complete"
elif cat == "executable" and status == "conflict":
    section = "Needs Review"
elif cat == "executable" and status == "active" and phases_done >= 1 and phases_done < phase_count:
    section = "In Progress"
elif (cat == "executable" and status == "active" and phases_done == 0 and queue_col != "ready") or queue_col == "ready":
    section = "Ready to Run"
else:
    section = "Other"
print(section)
' 2>&1)
  if [ "$CAT_CANARY" = "Canaries" ]; then
    pass "AC-6: category-canary fixture lands in Canaries section"
  else
    fail "AC-6: category-canary fixture → got '$CAT_CANARY', expected 'Canaries'"
  fi

  # Issue-tracker fixture → Reference section.
  CAT_ISSUES=$(PYTHONPATH="$PKG_PARENT" python3 -m zskills_monitor.collect \
    --fixture "$FIXTURES/category-issues" 2>&1 | python3 -c '
import json,sys
d=json.load(sys.stdin)
p=d["plans"][0]
status = p["status"]; cat = p["category"]
phases_done = p["phases_done"]; phase_count = p["phase_count"]
queue_col = (p.get("queue") or {}).get("column")
if cat == "canary": section = "Canaries"
elif cat in ("reference","issue_tracker"): section = "Reference"
elif status in ("complete","landed"): section = "Complete"
elif cat == "executable" and status == "conflict": section = "Needs Review"
elif cat == "executable" and status == "active" and phases_done >= 1 and phases_done < phase_count: section = "In Progress"
elif (cat == "executable" and status == "active" and phases_done == 0 and queue_col != "ready") or queue_col == "ready": section = "Ready to Run"
else: section = "Other"
print(section)
' 2>&1)
  if [ "$CAT_ISSUES" = "Reference" ]; then
    pass "AC-6: category-issues fixture lands in Reference section"
  else
    fail "AC-6: category-issues fixture → got '$CAT_ISSUES', expected 'Reference'"
  fi

  # Meta-plan executable fixture (no progress, status=active) → Ready to Run.
  CAT_META=$(PYTHONPATH="$PKG_PARENT" python3 -m zskills_monitor.collect \
    --fixture "$FIXTURES/category-meta" 2>&1 | python3 -c '
import json,sys
d=json.load(sys.stdin)
p=d["plans"][0]
status = p["status"]; cat = p["category"]
phases_done = p["phases_done"]; phase_count = p["phase_count"]
queue_col = (p.get("queue") or {}).get("column")
meta = p["meta_plan"]; subs = p["sub_plans"]
if cat == "canary": section = "Canaries"
elif cat in ("reference","issue_tracker"): section = "Reference"
elif status in ("complete","landed"): section = "Complete"
elif cat == "executable" and status == "conflict": section = "Needs Review"
elif cat == "executable" and status == "active" and phases_done >= 1 and phases_done < phase_count: section = "In Progress"
elif (cat == "executable" and status == "active" and phases_done == 0 and queue_col != "ready") or queue_col == "ready": section = "Ready to Run"
else: section = "Other"
sub_str = ",".join(subs)
print(section + "|meta=" + str(meta) + "|subs=" + sub_str)
' 2>&1)
  if [ "$CAT_META" = "Ready to Run|meta=True|subs=sub" ]; then
    pass "AC-6: category-meta fixture lands in Ready to Run, meta_plan=True, sub_plans=['sub']"
  else
    fail "AC-6: category-meta fixture → got '$CAT_META'"
  fi

  # with-state fixture has queue.column=ready → Ready to Run regardless of phase progress.
  CAT_READY=$(PYTHONPATH="$PKG_PARENT" python3 -m zskills_monitor.collect \
    --fixture "$FIXTURES/with-state" 2>&1 | python3 -c '
import json,sys
d=json.load(sys.stdin)
p=d["plans"][0]
status = p["status"]; cat = p["category"]
phases_done = p["phases_done"]; phase_count = p["phase_count"]
queue_col = (p.get("queue") or {}).get("column")
if cat == "canary": section = "Canaries"
elif cat in ("reference","issue_tracker"): section = "Reference"
elif status in ("complete","landed"): section = "Complete"
elif cat == "executable" and status == "conflict": section = "Needs Review"
elif cat == "executable" and status == "active" and phases_done >= 1 and phases_done < phase_count: section = "In Progress"
elif (cat == "executable" and status == "active" and phases_done == 0 and queue_col != "ready") or queue_col == "ready": section = "Ready to Run"
else: section = "Other"
print(f"{section}|queue_col={queue_col}")
' 2>&1)
  if [ "$CAT_READY" = "Ready to Run|queue_col=ready" ]; then
    pass "AC-6: with-state (queue.column=ready) fixture lands in Ready to Run"
  else
    fail "AC-6: with-state fixture → got '$CAT_READY'"
  fi

  # ---------------------------------------------------------------------------
  # AC-7: smoke — invoke aggregator against the live repo and verify
  # the plan-set matches what plans/PLAN_INDEX.md references.
  # ---------------------------------------------------------------------------
  echo ""
  echo "=== Phase 9 AC-7: live smoke — plan-set parity with PLAN_INDEX.md ==="

  if [ -f "$REPO_ROOT/plans/PLAN_INDEX.md" ]; then
    LIVE_OUT=$(PYTHONPATH="$PKG_PARENT" python3 -m zskills_monitor.collect \
      --repo-root "$REPO_ROOT" 2>&1)
    LIVE_RC=$?
    if [ "$LIVE_RC" -ne 0 ]; then
      fail "AC-7: aggregator CLI against repo root exits 0 (rc=$LIVE_RC)"
    else
      pass "AC-7: aggregator CLI against repo root exits 0"

      # Plans the aggregator reports (basename, sorted).
      AGG_PLANS=$(printf '%s' "$LIVE_OUT" | python3 -c '
import json,sys,os
d=json.load(sys.stdin)
names = sorted(os.path.basename(p["file"]) for p in d["plans"])
print("\n".join(names))
')
      # Plan filenames referenced in PLAN_INDEX.md (markdown link basenames).
      INDEX_PLANS=$(grep -oE '\[[A-Z][A-Za-z0-9_]*\.md\]' "$REPO_ROOT/plans/PLAN_INDEX.md" \
        | sed 's/^\[//; s/\]$//' \
        | sort -u)
      # The aggregator reports ALL top-level plans/*.md including the
      # cross-platform-hooks.md lower-cased ones; the index normalises
      # those into the Reference section. We assert that EVERY plan in
      # the index is also reported by the aggregator (subset relation).
      MISSING=""
      while IFS= read -r idx_plan; do
        [ -z "$idx_plan" ] && continue
        if ! printf '%s\n' "$AGG_PLANS" | grep -Fxq "$idx_plan"; then
          MISSING="$MISSING $idx_plan"
        fi
      done <<< "$INDEX_PLANS"
      if [ -z "$MISSING" ]; then
        pass "AC-7: every plan in PLAN_INDEX.md is reported by zskills_monitor.collect"
      else
        fail "AC-7: aggregator missing plans found in PLAN_INDEX.md:$MISSING"
      fi

      # No Python tracebacks in stderr/stdout.
      if printf '%s' "$LIVE_OUT" | grep -qE 'Traceback|Error:'; then
        fail "AC-7: aggregator output contains Python traceback or 'Error:'"
      else
        pass "AC-7: aggregator output contains no Python traceback"
      fi

      # Cross-check section assignment of canaries: every plan whose name
      # starts with CANARY in the aggregator should have category=="canary".
      MISMATCH=$(printf '%s' "$LIVE_OUT" | python3 -c '
import json,sys,os
d=json.load(sys.stdin)
bad = []
for p in d["plans"]:
    base = os.path.basename(p["file"])
    is_canary_by_name = base.startswith("CANARY")
    is_canary_by_cat = p["category"] == "canary"
    if is_canary_by_name != is_canary_by_cat:
        cat = p["category"]
        bad.append(base + ": name-says-canary=" + str(is_canary_by_name) + " but category=" + cat)
print("|".join(bad))
')
      if [ -z "$MISMATCH" ]; then
        pass "AC-7: every CANARY*.md plan has category==canary in aggregator output"
      else
        fail "AC-7: canary name/category mismatch: $MISMATCH"
      fi

      # Cross-check: any plan ending in _ISSUES.md → category=="issue_tracker".
      ISSUES_MISMATCH=$(printf '%s' "$LIVE_OUT" | python3 -c '
import json,sys,os,re
d=json.load(sys.stdin)
bad = []
for p in d["plans"]:
    base = os.path.basename(p["file"])
    if re.search(r"_ISSUES\.md$", base) and p["category"] != "issue_tracker":
        bad.append(base + ": category=" + p["category"])
print("|".join(bad))
')
      if [ -z "$ISSUES_MISMATCH" ]; then
        pass "AC-7: every *_ISSUES.md plan has category==issue_tracker"
      else
        fail "AC-7: _ISSUES.md / issue_tracker mismatch: $ISSUES_MISMATCH"
      fi
    fi
  else
    skip "AC-7: plans/PLAN_INDEX.md absent (skipping live smoke)"
  fi

  # ---------------------------------------------------------------------------
  # AC-9: python-missing failure mode — invoking the SKILL.md prose's CLI
  # with PATH stripped of python3 must exit non-zero (no silent fallback).
  # ---------------------------------------------------------------------------
  echo ""
  echo "=== Phase 9 AC-9: python3-missing failure is loud ==="

  # Run the canonical CLI line with an empty PATH; expect non-zero.
  TMP_DIR=$(mktemp -d)
  trap "rm -rf '$TMP_DIR'" EXIT
  set +e
  env -i HOME="$HOME" PATH="$TMP_DIR" \
    bash -c 'PYTHONPATH="'"$PKG_PARENT"'" python3 -m zskills_monitor.collect --fixture "'"$FIXTURES/minimal"'"' \
    > /dev/null 2>&1
  RC=$?
  set -e
  if [ "$RC" -ne 0 ]; then
    pass "AC-9: invocation with empty PATH (no python3) exits non-zero (rc=$RC)"
  else
    fail "AC-9: invocation with empty PATH unexpectedly succeeded — silent fallback?"
  fi

  # Stronger: the SKILL.md says rebuild must exit non-zero AND emit a
  # diagnostic when the CLI fails. Check the rebuild prose contains the
  # relevant exit-1 + ERROR-message pattern.
  if grep -nE 'echo "ERROR:.*python3 -m zskills_monitor\.collect failed' "$SKILL_MD" > /dev/null 2>&1; then
    pass "AC-9: SKILL.md prose includes loud ERROR diagnostic on CLI failure"
  else
    fail "AC-9: SKILL.md prose missing loud ERROR diagnostic"
  fi
fi

# ---------------------------------------------------------------------------
# Final: registered in run-all.sh
# ---------------------------------------------------------------------------
echo ""
echo "=== Phase 9: registration in tests/run-all.sh ==="

if grep -F 'tests/test_plans_rebuild_uses_collect.sh' "$REPO_ROOT/tests/run-all.sh" > /dev/null 2>&1; then
  pass "registered in tests/run-all.sh"
else
  fail "not registered in tests/run-all.sh"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "---"
TOTAL=$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))
printf 'Results: %d passed, %d failed, %d skipped (of %d)\n' \
  "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$TOTAL"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
