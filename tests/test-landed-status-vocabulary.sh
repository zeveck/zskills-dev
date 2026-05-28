#!/bin/bash
# tests/test-landed-status-vocabulary.sh
#
# Conformance: every status value any writer emits into a `.landed` marker
# must appear in BOTH reader whitelists:
#   - skills/briefing/scripts/briefing.py classify_worktrees status set
#   - skills/fix-report/SKILL.md documented closed status set
#
# Closes issue #518: failure-class statuses (`failed`, `direct-push-failed`,
# `direct-verify-failed`) were emitted by writers but absent from reader
# whitelists, causing failed sprints to silently fall through to the
# generic mtime-bucket "old worktree" category.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export CLAUDE_PROJECT_DIR="$REPO_ROOT"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  printf '\033[32m  PASS\033[0m %s\n' "$1"
  ((PASS_COUNT++))
}

fail() {
  printf '\033[31m  FAIL\033[0m %s\n' "$1"
  ((FAIL_COUNT++))
}

echo "=== Landed status vocabulary conformance (issue #518) ==="

# Canonical set of `.landed` `status:` values any writer is allowed to emit.
# This is the source-of-truth list; the test asserts (a) every value here
# appears as a writer emission somewhere under skills/, and (b) every value
# here appears in BOTH reader whitelists. Adding a new writer-emitted
# status requires editing this list AND both readers.
WRITER_STATUSES=(
  "full"
  "landed"
  "partial"
  "pr-ready"
  "pr-ci-failing"
  "pr-failed"
  "conflict"
  "pr-state-unknown"
  "failed"
  "direct-push-failed"
  "direct-verify-failed"
)

BRIEFING_PY="$REPO_ROOT/skills/briefing/scripts/briefing.py"
FIX_REPORT_MD="$REPO_ROOT/skills/fix-report/SKILL.md"

if [[ ! -f "$BRIEFING_PY" ]]; then
  fail "missing reader file: $BRIEFING_PY"
fi
if [[ ! -f "$FIX_REPORT_MD" ]]; then
  fail "missing reader file: $FIX_REPORT_MD"
fi

# ---------------------------------------------------------------------
# Part A: every canonical status appears as a writer emission.
# Writers either emit `status: <X>` as a literal line in a heredoc, or
# document the value in land-pr/SKILL.md's canonical `<required>` list.
# We accept either form.
# ---------------------------------------------------------------------
echo ""
echo "--- Part A: writer-emission coverage ---"

# Aggregate all writer-side `status:` mentions across heredoc bodies and
# prose mentions ("write status: <X>" / "writes `.landed` with status:
# <X>"). Restrict the search to skills/ so this test stays independent of
# .claude/ mirror state. The status keyword may appear at column 0 inside
# a heredoc OR mid-sentence in prose (e.g., "write status: foo and...").
WRITER_HAYSTACK=$(grep -rhE 'status:[[:space:]]+[a-z][a-z-]*' \
  "$REPO_ROOT/skills/" --include="*.md" --include="*.sh" 2>/dev/null)

# Also include the land-pr inline-documented set (the `<required>` line
# enumerates the canonical PR-status vocabulary in a comment).
LAND_PR_DOC=$(grep -E 'status:[[:space:]]*<required>' \
  "$REPO_ROOT/skills/land-pr/SKILL.md" 2>/dev/null || true)

for status in "${WRITER_STATUSES[@]}"; do
  if echo "$WRITER_HAYSTACK" | grep -qE "status:[[:space:]]+${status}([^a-z-]|$)" \
     || echo "$LAND_PR_DOC" | grep -qE "(^|[^a-z-])${status}([^a-z-]|$)"; then
    pass "writer emits status: $status"
  else
    fail "writer-emission gap: no writer site emits 'status: $status' under skills/"
  fi
done

# ---------------------------------------------------------------------
# Part B: every writer-emitted status appears in briefing.py's reader
# whitelist. We grep the file for each status as a quoted literal — the
# whitelist sets at briefing.py:397, :411, :430 use Python tuple syntax
# with single-quoted strings.
# ---------------------------------------------------------------------
echo ""
echo "--- Part B: briefing.py reader-whitelist coverage ---"

BRIEFING_BODY=$(cat "$BRIEFING_PY")

for status in "${WRITER_STATUSES[@]}"; do
  if echo "$BRIEFING_BODY" | grep -qE "'${status}'"; then
    pass "briefing.py recognizes status: $status"
  else
    fail "briefing.py reader gap: '${status}' not in any status whitelist"
  fi
done

# ---------------------------------------------------------------------
# Part C: every writer-emitted status appears in fix-report/SKILL.md's
# documented closed status set (line ~161) or status table.
# ---------------------------------------------------------------------
echo ""
echo "--- Part C: fix-report/SKILL.md reader-whitelist coverage ---"

FIX_REPORT_BODY=$(cat "$FIX_REPORT_MD")

for status in "${WRITER_STATUSES[@]}"; do
  # Accept the status token at any word boundary within the file
  # (backticked literal, inside the `status: A | B | ...` closed set,
  # prose mention, etc.). Token-boundary anchors prevent partial matches
  # (e.g., 'failed' matching 'pr-failed').
  if echo "$FIX_REPORT_BODY" | grep -qE "(^|[^a-z-])${status}([^a-z-]|$)"; then
    pass "fix-report/SKILL.md recognizes status: $status"
  else
    fail "fix-report/SKILL.md reader gap: '${status}' not in documented status set"
  fi
done

# ---------------------------------------------------------------------
# Part D: display normalization (issue #776).
# `full` (cherry-pick landing) and `landed` (PR landing) both mean
# "everything is on main"; the dashboard Branches pill must DISPLAY `full`
# as "LANDED" so it reads the same. This is purely the human-readable label
# — the STORED `.landed` status stays `full`, and the matching/color logic
# (landedPillClass mapping `full` and `landed` to the same class) is
# unchanged. `partial` is a distinct state and must NOT be collapsed.
# ---------------------------------------------------------------------
echo ""
echo "--- Part D: display normalization (issue #776) ---"

APP_JS="$REPO_ROOT/skills/zskills-dashboard/scripts/zskills_monitor/static/app.js"

if [[ ! -f "$APP_JS" ]]; then
  fail "missing dashboard file: $APP_JS"
else
  APP_JS_BODY=$(cat "$APP_JS")

  # D1: the worktree-row pill renders stored `full` as `landed` text.
  if echo "$APP_JS_BODY" | grep -qE 'status === "full" \? "landed" : status'; then
    pass "app.js displays stored 'full' as 'landed' text (#776)"
  else
    fail "app.js display gap: 'full' not normalized to 'landed' display text (#776)"
  fi

  # D2: STORED vocabulary preserved — landedPillClass still recognizes BOTH
  # `full` and `landed` (same green class). The color/matching logic is
  # explicitly out of scope for the display-only change.
  if echo "$APP_JS_BODY" | grep -qE 's === "full" \|\| s === "landed"'; then
    pass "app.js landedPillClass still maps 'full' AND 'landed' to the same class (matching logic unchanged)"
  else
    fail "app.js regression: landedPillClass no longer maps both 'full' and 'landed' (matching logic must be unchanged) (#776)"
  fi

  # D3: `partial` is NOT collapsed by the display normalization — it keeps
  # its own label and its own class.
  if echo "$APP_JS_BODY" | grep -qE 'text: status === "full" \? "landed" : status' \
     && ! echo "$APP_JS_BODY" | grep -qE 'text: status === "partial"'; then
    pass "app.js does not collapse 'partial' — it keeps its own PARTIAL label (#776)"
  else
    fail "app.js regression: 'partial' display label appears collapsed (#776)"
  fi
fi

echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' \
  "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
