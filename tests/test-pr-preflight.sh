#!/bin/bash
# Tests for skills/run-plan/scripts/pr-preflight.sh — the open-PR file-path
# conflict gate that self-filters the pipeline's own PR (issue #177).
# Run from repo root: bash tests/test-pr-preflight.sh
#
# Coverage:
#   1. No open PRs touch path           → exit 0, empty stdout
#   2. One PR touches path, NOT excluded → exit 1, stdout = that PR
#   3. Only the excluded PR matches      → exit 0, empty stdout (#177 case)
#   4. Multiple match, one excluded      → exit 1, stdout = remaining PRs
#   5. --exclude-pr omitted              → no exclusion (returns all matches)
#   6. Missing --path-prefix             → exit 2 (arg error)
#   7. Bad --exclude-pr (non-numeric)    → exit 2 (arg error)
#   8. Empty `[]` JSON                   → exit 0
#   9. Path prefix matches in one PR but not another (boundary) → only that PR

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/skills/run-plan/scripts/pr-preflight.sh"

WORK="/tmp/zskills-tests/$(basename "$REPO_ROOT")/pr-preflight"
rm -rf "$WORK"
mkdir -p "$WORK"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# Helper: run the script with a JSON override, capture stdout/exit.
# Args: $1=label, $2=expected_exit, $3=expected_stdout (newline-joined),
#       $4=json, $5..=script args
run_case() {
  local label="$1" expected_exit="$2" expected_stdout="$3" json="$4"; shift 4
  local actual_stdout actual_exit
  actual_stdout=$(GH_PR_LIST_JSON_OVERRIDE="$json" bash "$SCRIPT" "$@" 2>/dev/null) || actual_exit=$?
  actual_exit="${actual_exit:-0}"

  if [ "$actual_exit" != "$expected_exit" ]; then
    fail "$label — expected exit=$expected_exit got exit=$actual_exit (stdout: '$actual_stdout')"
    return
  fi
  if [ "$actual_stdout" != "$expected_stdout" ]; then
    fail "$label — expected stdout='$expected_stdout' got stdout='$actual_stdout'"
    return
  fi
  pass "$label (exit=$actual_exit)"
}

# Helper: run without setting GH_PR_LIST_JSON_OVERRIDE (for arg-error cases).
run_no_override() {
  local label="$1" expected_exit="$2"; shift 2
  local actual_exit
  bash "$SCRIPT" "$@" >/dev/null 2>&1 || actual_exit=$?
  actual_exit="${actual_exit:-0}"
  if [ "$actual_exit" = "$expected_exit" ]; then
    pass "$label (exit=$actual_exit)"
  else
    fail "$label — expected exit=$expected_exit got exit=$actual_exit"
  fi
}

echo "=== pr-preflight.sh tests ==="

# ---------------------------------------------------------------
# Case 1: No open PRs touch path → exit 0, empty stdout
# ---------------------------------------------------------------
JSON_NO_MATCH='[{"number":100,"title":"A","files":[{"path":"src/foo.js"}]},{"number":101,"title":"B","files":[{"path":"docs/bar.md"}]}]'
run_case "1: no PR touches path" 0 "" "$JSON_NO_MATCH" \
  --path-prefix "skills/update-zskills/" --exclude-pr 175

# ---------------------------------------------------------------
# Case 2: One PR matches, not the excluded one → exit 1, stdout = that PR
# ---------------------------------------------------------------
JSON_ONE_MATCH='[{"number":175,"title":"self","files":[{"path":"src/foo.js"}]},{"number":200,"title":"other","files":[{"path":"skills/update-zskills/SKILL.md"},{"path":"src/bar.js"}]}]'
run_case "2: one PR matches, not excluded" 1 "200" "$JSON_ONE_MATCH" \
  --path-prefix "skills/update-zskills/" --exclude-pr 175

# ---------------------------------------------------------------
# Case 3: Only excluded PR matches (the #177 bug case) → exit 0, empty
# ---------------------------------------------------------------
JSON_ONLY_SELF='[{"number":175,"title":"self","files":[{"path":"skills/update-zskills/SKILL.md"},{"path":"plans/SKILL_VERSIONING.md"}]},{"number":200,"title":"other","files":[{"path":"src/foo.js"}]}]'
run_case "3: only excluded PR matches (#177 bug case)" 0 "" "$JSON_ONLY_SELF" \
  --path-prefix "skills/update-zskills/" --exclude-pr 175

# ---------------------------------------------------------------
# Case 4: Multiple match, one excluded → exit 1, stdout = remaining PRs (newline-joined)
# ---------------------------------------------------------------
JSON_MULTI_MATCH='[{"number":175,"title":"self","files":[{"path":"skills/update-zskills/SKILL.md"}]},{"number":200,"title":"other-a","files":[{"path":"skills/update-zskills/foo.md"}]},{"number":201,"title":"other-b","files":[{"path":"skills/update-zskills/bar.md"},{"path":"src/x.js"}]}]'
run_case "4: multiple match, one excluded" 1 "200
201" "$JSON_MULTI_MATCH" \
  --path-prefix "skills/update-zskills/" --exclude-pr 175

# ---------------------------------------------------------------
# Case 5: --exclude-pr omitted → no exclusion (returns all matches incl. 175)
# ---------------------------------------------------------------
run_case "5: --exclude-pr omitted (no exclusion)" 1 "175
200
201" "$JSON_MULTI_MATCH" \
  --path-prefix "skills/update-zskills/"

# ---------------------------------------------------------------
# Case 6: Missing --path-prefix → exit 2
# ---------------------------------------------------------------
run_no_override "6: missing --path-prefix exits 2" 2 --exclude-pr 175

# ---------------------------------------------------------------
# Case 7: Bad --exclude-pr (non-numeric) → exit 2
# ---------------------------------------------------------------
run_no_override "7: non-numeric --exclude-pr exits 2" 2 \
  --path-prefix "skills/foo/" --exclude-pr "abc"

# ---------------------------------------------------------------
# Case 8: Empty `[]` JSON → exit 0
# ---------------------------------------------------------------
run_case "8: empty JSON array" 0 "" "[]" \
  --path-prefix "skills/update-zskills/" --exclude-pr 175

# ---------------------------------------------------------------
# Case 9: Boundary — path prefix is a substring of another path that
# should NOT match (e.g. 'skills/update' should NOT match 'skills/update-zskills/'
# when prefix is 'skills/update-zskills-other/').
# ---------------------------------------------------------------
JSON_NEAR_MISS='[{"number":300,"title":"near","files":[{"path":"skills/update-zskills/SKILL.md"}]},{"number":301,"title":"hit","files":[{"path":"skills/update-zskills-other/SKILL.md"}]}]'
run_case "9: prefix discriminates near-miss paths" 1 "301" "$JSON_NEAR_MISS" \
  --path-prefix "skills/update-zskills-other/" --exclude-pr 175

echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"
if [ "$FAIL_COUNT" -gt 0 ]; then exit 1; fi
exit 0
