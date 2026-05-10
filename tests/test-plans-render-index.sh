#!/bin/bash
# Tests for skills/plans/scripts/render-index.py (issue #215).
#
# The helper renders PLAN_INDEX.md markdown from a zskills_monitor.collect
# JSON snapshot on stdin. The 7 cases below exercise the precedence rules
# the prose loop used to bury inside SKILL.md, where the agent could
# easily miss them:
#
#   1. Canary precedence — `status: complete` does not promote a canary
#      out of the Canaries section (the exact bug PR #214's rebuild hit).
#   2. Meta-plan sub-plan indentation.
#   3. Ready ordering (queue.column=="ready" first by queue.index).
#   4. Empty section rendering.
#   5. Priority labels (High/Medium/Low).
#   6. Empty/malformed stdin → non-zero exit + diagnostic.
#   7. Idempotency.
#
# Run from repo root: bash tests/test-plans-render-index.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RENDER="$REPO_ROOT/skills/plans/scripts/render-index.py"

TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
mkdir -p "$TEST_OUT"
RESULTS="$TEST_OUT/test-plans-render-index.log"
: > "$RESULTS"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  printf '\033[32m  PASS\033[0m %s\n' "$1"
  printf '  PASS %s\n' "$1" >> "$RESULTS"
  PASS_COUNT=$((PASS_COUNT + 1))
}
fail() {
  printf '\033[31m  FAIL\033[0m %s\n' "$1"
  printf '  FAIL %s\n' "$1" >> "$RESULTS"
  if [ -n "${2:-}" ]; then
    printf '         %s\n' "$2"
    printf '         %s\n' "$2" >> "$RESULTS"
  fi
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

if [ ! -f "$RENDER" ]; then
  fail "render-index.py exists at $RENDER"
  printf 'Results: %d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
  exit 1
fi
pass "render-index.py exists"

if [ ! -x "$RENDER" ]; then
  fail "render-index.py is executable"
else
  pass "render-index.py is executable"
fi

# ---------------------------------------------------------------------------
# Helper — run the renderer with a literal JSON snapshot and capture both
# stdout and exit code.
# ---------------------------------------------------------------------------
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT

run_render() {
  # $1: path to a JSON file; writes stdout to $SCRATCH/out.md;
  # echoes the exit code on stdout.
  local snap="$1"
  set +e
  python3 "$RENDER" --rebuilt-at "2026-05-10 12:00 ET" \
    < "$snap" > "$SCRATCH/out.md" 2> "$SCRATCH/err.txt"
  local rc=$?
  set -e
  echo "$rc"
}

# ---------------------------------------------------------------------------
# Case 1: Canary with status=complete stays in Canaries, NOT Complete.
# This is the exact bug PR #214 hit.
# ---------------------------------------------------------------------------
echo ""
echo "=== Case 1: canary precedence (status=complete does not promote) ==="

cat > "$SCRATCH/case1.json" <<'JSON'
{
  "plans": [
    {
      "slug": "canary1-happy",
      "file": "docs/plans/CANARY1_HAPPY.md",
      "title": "Canary 1 Happy",
      "status": "complete",
      "created": "2026-04-20",
      "issue": null,
      "blurb": "Happy-path canary.",
      "phase_count": 1,
      "phases_done": 1,
      "phases": [{"n": "1", "name": "Run", "status": "done", "commit": "abc", "notes": ""}],
      "category": "canary",
      "meta_plan": false,
      "sub_plans": [],
      "queue": {"column": null, "index": -1, "mode": null}
    }
  ]
}
JSON
RC=$(run_render "$SCRATCH/case1.json")
if [ "$RC" -ne 0 ]; then
  fail "Case 1: renderer exits 0" "rc=$RC; stderr: $(cat "$SCRATCH/err.txt")"
else
  pass "Case 1: renderer exits 0"
fi

# The plan should appear under ## Canaries, not under ## Complete.
CANARIES_BODY=$(awk '/^## Canaries/{flag=1; next} /^## /{flag=0} flag' "$SCRATCH/out.md")
COMPLETE_BODY=$(awk '/^## Complete/{flag=1; next} /^## /{flag=0} flag' "$SCRATCH/out.md")
if echo "$CANARIES_BODY" | grep -q 'CANARY1_HAPPY.md'; then
  pass "Case 1: CANARY1_HAPPY.md appears in Canaries section"
else
  fail "Case 1: CANARY1_HAPPY.md missing from Canaries"
fi
if echo "$COMPLETE_BODY" | grep -q 'CANARY1_HAPPY.md'; then
  fail "Case 1: CANARY1_HAPPY.md leaked into Complete (precedence broken)"
else
  pass "Case 1: CANARY1_HAPPY.md NOT in Complete (precedence preserved)"
fi
# Totals line must show 1 canary, 0 complete.
if grep -q 'Totals: 1 plans — 0 ready, 0 in progress, 0 complete, 1 canaries' "$SCRATCH/out.md"; then
  pass "Case 1: totals reflect canary-not-complete bucketing"
else
  fail "Case 1: totals wrong" "$(grep '^Totals:' "$SCRATCH/out.md")"
fi

# ---------------------------------------------------------------------------
# Case 2: Meta-plan with 2 sub-plans, all complete. Meta-plan appears once,
# sub-plans indented with ↳; sub-plans do NOT appear as top-level entries.
# ---------------------------------------------------------------------------
echo ""
echo "=== Case 2: meta-plan sub-plan indentation ==="

cat > "$SCRATCH/case2.json" <<'JSON'
{
  "plans": [
    {
      "slug": "runtime-parity-meta",
      "file": "docs/plans/RUNTIME_PARITY_META.md",
      "title": "Runtime Parity Meta",
      "status": "complete",
      "created": "2026-04-01",
      "issue": null,
      "blurb": "Meta-plan blurb.",
      "phase_count": 2,
      "phases_done": 2,
      "phases": [],
      "category": "executable",
      "meta_plan": true,
      "sub_plans": ["sub-a", "sub-b"],
      "queue": {"column": null, "index": -1, "mode": null}
    },
    {
      "slug": "sub-a",
      "file": "docs/plans/SUB_A.md",
      "title": "Sub A",
      "status": "complete",
      "created": "2026-04-02",
      "issue": null,
      "blurb": "Sub A blurb.",
      "phase_count": 3,
      "phases_done": 3,
      "phases": [],
      "category": "executable",
      "meta_plan": false,
      "sub_plans": [],
      "queue": {"column": null, "index": -1, "mode": null}
    },
    {
      "slug": "sub-b",
      "file": "docs/plans/SUB_B.md",
      "title": "Sub B",
      "status": "complete",
      "created": "2026-04-03",
      "issue": null,
      "blurb": "Sub B blurb.",
      "phase_count": 2,
      "phases_done": 2,
      "phases": [],
      "category": "executable",
      "meta_plan": false,
      "sub_plans": [],
      "queue": {"column": null, "index": -1, "mode": null}
    }
  ]
}
JSON
RC=$(run_render "$SCRATCH/case2.json")
if [ "$RC" -ne 0 ]; then
  fail "Case 2: renderer exits 0" "stderr: $(cat "$SCRATCH/err.txt")"
else
  pass "Case 2: renderer exits 0"
fi

COMPLETE_BODY=$(awk '/^## Complete/{flag=1; next} /^## /{flag=0} flag' "$SCRATCH/out.md")
# Meta-plan must appear once at top-level.
META_HITS=$(echo "$COMPLETE_BODY" | grep -cF 'RUNTIME_PARITY_META.md' || true)
if [ "$META_HITS" -eq 1 ]; then
  pass "Case 2: meta-plan appears exactly once in Complete"
else
  fail "Case 2: meta-plan appears $META_HITS times in Complete (expected 1)"
fi
# Sub-plans must appear with ↳ prefix and NOT as bare top-level rows.
if echo "$COMPLETE_BODY" | grep -qF '↳ [SUB_A.md]'; then
  pass "Case 2: SUB_A.md indented with ↳"
else
  fail "Case 2: SUB_A.md missing ↳ indentation" "Complete body: $COMPLETE_BODY"
fi
if echo "$COMPLETE_BODY" | grep -qF '↳ [SUB_B.md]'; then
  pass "Case 2: SUB_B.md indented with ↳"
else
  fail "Case 2: SUB_B.md missing ↳ indentation"
fi
# Negative: a row starting "| [SUB_A.md]" without the ↳ prefix would be
# a top-level leak.
if echo "$COMPLETE_BODY" | grep -qE '^\| \[SUB_A\.md\]'; then
  fail "Case 2: SUB_A.md leaks as top-level row in Complete"
else
  pass "Case 2: SUB_A.md does NOT appear as top-level row"
fi
if echo "$COMPLETE_BODY" | grep -qE '^\| \[SUB_B\.md\]'; then
  fail "Case 2: SUB_B.md leaks as top-level row in Complete"
else
  pass "Case 2: SUB_B.md does NOT appear as top-level row"
fi

# ---------------------------------------------------------------------------
# Case 3: Ready ordering — queue.column=="ready" entries come first in
# queue.index order, then default-column ready entries by recency.
# ---------------------------------------------------------------------------
echo ""
echo "=== Case 3: ready ordering ==="

cat > "$SCRATCH/case3.json" <<'JSON'
{
  "plans": [
    {
      "slug": "default-old",
      "file": "docs/plans/DEFAULT_OLD.md",
      "title": "Default Old",
      "status": "active",
      "created": "2026-01-01",
      "issue": null,
      "blurb": "Old default.",
      "phase_count": 3,
      "phases_done": 0,
      "phases": [],
      "category": "executable",
      "meta_plan": false,
      "sub_plans": [],
      "queue": {"column": null, "index": -1, "mode": null}
    },
    {
      "slug": "default-new",
      "file": "docs/plans/DEFAULT_NEW.md",
      "title": "Default New",
      "status": "active",
      "created": "2026-05-01",
      "issue": null,
      "blurb": "New default.",
      "phase_count": 3,
      "phases_done": 0,
      "phases": [],
      "category": "executable",
      "meta_plan": false,
      "sub_plans": [],
      "queue": {"column": null, "index": -1, "mode": null}
    },
    {
      "slug": "explicit-second",
      "file": "docs/plans/EXPLICIT_SECOND.md",
      "title": "Explicit Second",
      "status": "active",
      "created": "2026-04-01",
      "issue": null,
      "blurb": "Second in explicit queue.",
      "phase_count": 3,
      "phases_done": 2,
      "phases": [],
      "category": "executable",
      "meta_plan": false,
      "sub_plans": [],
      "queue": {"column": "ready", "index": 1, "mode": null}
    },
    {
      "slug": "explicit-first",
      "file": "docs/plans/EXPLICIT_FIRST.md",
      "title": "Explicit First",
      "status": "active",
      "created": "2026-04-01",
      "issue": null,
      "blurb": "First in explicit queue.",
      "phase_count": 3,
      "phases_done": 0,
      "phases": [],
      "category": "executable",
      "meta_plan": false,
      "sub_plans": [],
      "queue": {"column": "ready", "index": 0, "mode": null}
    }
  ]
}
JSON
RC=$(run_render "$SCRATCH/case3.json")
if [ "$RC" -ne 0 ]; then
  fail "Case 3: renderer exits 0"
else
  pass "Case 3: renderer exits 0"
fi

READY_BODY=$(awk '/^## Ready to Run/{flag=1; next} /^## /{flag=0} flag' "$SCRATCH/out.md")
# Extract rows in order and check the slugs land in: explicit-first,
# explicit-second, default-new, default-old.
ROW_ORDER=$(echo "$READY_BODY" \
  | grep -oE 'EXPLICIT_FIRST\.md|EXPLICIT_SECOND\.md|DEFAULT_NEW\.md|DEFAULT_OLD\.md' \
  | awk '!seen[$0]++')
EXPECTED="EXPLICIT_FIRST.md
EXPLICIT_SECOND.md
DEFAULT_NEW.md
DEFAULT_OLD.md"
if [ "$ROW_ORDER" = "$EXPECTED" ]; then
  pass "Case 3: ready ordering correct (explicit-by-index, then default-by-recency)"
else
  fail "Case 3: ready ordering wrong" "got:
$ROW_ORDER
expected:
$EXPECTED"
fi

# ---------------------------------------------------------------------------
# Case 4: Empty section rendering.
# ---------------------------------------------------------------------------
echo ""
echo "=== Case 4: empty section emits (none) row ==="

cat > "$SCRATCH/case4.json" <<'JSON'
{
  "plans": [
    {
      "slug": "only-complete",
      "file": "docs/plans/ONLY_COMPLETE.md",
      "title": "Only Complete",
      "status": "complete",
      "created": "2026-04-01",
      "issue": null,
      "blurb": "All done.",
      "phase_count": 2,
      "phases_done": 2,
      "phases": [],
      "category": "executable",
      "meta_plan": false,
      "sub_plans": [],
      "queue": {"column": null, "index": -1, "mode": null}
    }
  ]
}
JSON
RC=$(run_render "$SCRATCH/case4.json")
if [ "$RC" -ne 0 ]; then
  fail "Case 4: renderer exits 0"
else
  pass "Case 4: renderer exits 0"
fi

READY_BODY=$(awk '/^## Ready to Run/{flag=1; next} /^## /{flag=0} flag' "$SCRATCH/out.md")
if echo "$READY_BODY" | grep -qF '| (none) |'; then
  pass "Case 4: empty Ready section renders | (none) | placeholder"
else
  fail "Case 4: empty Ready section missing (none) row" "Ready body: $READY_BODY"
fi

# ---------------------------------------------------------------------------
# Case 5: Priority labels.
#   - issue field set → High
#   - created within 14 days → Medium
#   - created >14 days ago → Low
# Use a wide enough gap that the test stays correct regardless of the day
# the test runs.
# ---------------------------------------------------------------------------
echo ""
echo "=== Case 5: priority labels ==="

RECENT=$(date -d "today - 3 days" +%Y-%m-%d 2>/dev/null \
  || python3 -c 'import datetime; print((datetime.date.today() - datetime.timedelta(days=3)).isoformat())')
OLD=$(date -d "today - 60 days" +%Y-%m-%d 2>/dev/null \
  || python3 -c 'import datetime; print((datetime.date.today() - datetime.timedelta(days=60)).isoformat())')

cat > "$SCRATCH/case5.json" <<JSON
{
  "plans": [
    {
      "slug": "with-issue",
      "file": "docs/plans/WITH_ISSUE.md",
      "title": "With Issue",
      "status": "active",
      "created": "$OLD",
      "issue": "42",
      "blurb": "Has issue ref.",
      "phase_count": 3,
      "phases_done": 0,
      "phases": [],
      "category": "executable",
      "meta_plan": false,
      "sub_plans": [],
      "queue": {"column": null, "index": -1, "mode": null}
    },
    {
      "slug": "recent-no-issue",
      "file": "docs/plans/RECENT_NO_ISSUE.md",
      "title": "Recent No Issue",
      "status": "active",
      "created": "$RECENT",
      "issue": null,
      "blurb": "Recent.",
      "phase_count": 3,
      "phases_done": 0,
      "phases": [],
      "category": "executable",
      "meta_plan": false,
      "sub_plans": [],
      "queue": {"column": null, "index": -1, "mode": null}
    },
    {
      "slug": "old-no-issue",
      "file": "docs/plans/OLD_NO_ISSUE.md",
      "title": "Old No Issue",
      "status": "active",
      "created": "$OLD",
      "issue": null,
      "blurb": "Old.",
      "phase_count": 3,
      "phases_done": 0,
      "phases": [],
      "category": "executable",
      "meta_plan": false,
      "sub_plans": [],
      "queue": {"column": null, "index": -1, "mode": null}
    }
  ]
}
JSON
RC=$(run_render "$SCRATCH/case5.json")
if [ "$RC" -ne 0 ]; then
  fail "Case 5: renderer exits 0"
else
  pass "Case 5: renderer exits 0"
fi

# Each plan should have its expected priority label in its row.
READY_BODY=$(awk '/^## Ready to Run/{flag=1; next} /^## /{flag=0} flag' "$SCRATCH/out.md")
HIGH_ROW=$(echo "$READY_BODY" | grep -F 'WITH_ISSUE.md')
MEDIUM_ROW=$(echo "$READY_BODY" | grep -F 'RECENT_NO_ISSUE.md')
LOW_ROW=$(echo "$READY_BODY" | grep -F 'OLD_NO_ISSUE.md')

if echo "$HIGH_ROW" | grep -qF ' High '; then
  pass "Case 5: with-issue plan labelled High"
else
  fail "Case 5: with-issue NOT labelled High" "row: $HIGH_ROW"
fi
if echo "$MEDIUM_ROW" | grep -qF ' Medium '; then
  pass "Case 5: recent-no-issue plan labelled Medium"
else
  fail "Case 5: recent-no-issue NOT labelled Medium" "row: $MEDIUM_ROW"
fi
if echo "$LOW_ROW" | grep -qF ' Low '; then
  pass "Case 5: old-no-issue plan labelled Low"
else
  fail "Case 5: old-no-issue NOT labelled Low" "row: $LOW_ROW"
fi

# ---------------------------------------------------------------------------
# Case 6: Malformed / empty stdin → non-zero exit with diagnostic.
# ---------------------------------------------------------------------------
echo ""
echo "=== Case 6: malformed stdin → non-zero exit ==="

# Empty stdin.
set +e
echo "" | python3 "$RENDER" --rebuilt-at "x" > "$SCRATCH/out6a.md" 2> "$SCRATCH/err6a.txt"
RC_A=$?
set -e
if [ "$RC_A" -ne 0 ]; then
  pass "Case 6: empty stdin exits non-zero (rc=$RC_A)"
else
  fail "Case 6: empty stdin unexpectedly succeeded"
fi
if grep -qF 'ERROR' "$SCRATCH/err6a.txt"; then
  pass "Case 6: empty stdin emits ERROR diagnostic"
else
  fail "Case 6: empty stdin missing ERROR diagnostic" "stderr: $(cat "$SCRATCH/err6a.txt")"
fi

# Invalid JSON.
set +e
echo "not json {" | python3 "$RENDER" --rebuilt-at "x" > "$SCRATCH/out6b.md" 2> "$SCRATCH/err6b.txt"
RC_B=$?
set -e
if [ "$RC_B" -ne 0 ]; then
  pass "Case 6: invalid JSON exits non-zero (rc=$RC_B)"
else
  fail "Case 6: invalid JSON unexpectedly succeeded"
fi

# Valid JSON but missing 'plans' key.
set +e
echo '{"x": 1}' | python3 "$RENDER" --rebuilt-at "x" > "$SCRATCH/out6c.md" 2> "$SCRATCH/err6c.txt"
RC_C=$?
set -e
if [ "$RC_C" -ne 0 ]; then
  pass "Case 6: missing 'plans' key exits non-zero (rc=$RC_C)"
else
  fail "Case 6: missing 'plans' key unexpectedly succeeded"
fi

# ---------------------------------------------------------------------------
# Case 7: Idempotency — same input → byte-identical output.
# ---------------------------------------------------------------------------
echo ""
echo "=== Case 7: idempotency ==="

# Use case 2 (more interesting structure than case 1).
python3 "$RENDER" --rebuilt-at "fixed-ts" < "$SCRATCH/case2.json" > "$SCRATCH/run1.md"
python3 "$RENDER" --rebuilt-at "fixed-ts" < "$SCRATCH/case2.json" > "$SCRATCH/run2.md"
if cmp -s "$SCRATCH/run1.md" "$SCRATCH/run2.md"; then
  pass "Case 7: two runs produce byte-identical output"
else
  fail "Case 7: two runs differ" "$(diff "$SCRATCH/run1.md" "$SCRATCH/run2.md" | head -20)"
fi

# Different timestamps still produce identical body modulo the timestamp.
python3 "$RENDER" --rebuilt-at "ts-A" < "$SCRATCH/case2.json" > "$SCRATCH/runA.md"
python3 "$RENDER" --rebuilt-at "ts-B" < "$SCRATCH/case2.json" > "$SCRATCH/runB.md"
DIFF_LINES=$(diff "$SCRATCH/runA.md" "$SCRATCH/runB.md" | grep -c '^[<>]')
# Two lines differ — one < and one > on the rebuilt-at line.
if [ "$DIFF_LINES" -eq 2 ]; then
  pass "Case 7: timestamp is the ONLY source of variance"
else
  fail "Case 7: more than just timestamp differs" \
    "$(diff "$SCRATCH/runA.md" "$SCRATCH/runB.md" | head)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "---"
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' \
  "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
