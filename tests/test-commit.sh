#!/bin/bash
# Tests for skills/commit/SKILL.md and skills/commit/modes/pr.md — issue
# #236: /commit pr needs positional `auto` mode (sibling to #235).
#
# Sibling of test-quickfix.sh Cases 54–56. Static-grep against the SKILL
# source — /commit pr has no extractable preflight slice to drive
# end-to-end without a heavy fixture (no model-layer parser test seam
# like /quickfix has). Source-level invariants are the load-bearing
# regression guard.
#
# Cases:
#   1. argument-hint contains positional `auto` (issue #236)
#   2. AUTO_FLAG=0 default + case-insensitive `auto` token recognition
#      in the top-level argument parser
#   3. SCOPE_HINT strip — `auto` does not leak into PR title / scope
#      hint (both PR-mode parse paths: explicit `/commit pr` AND
#      config-default-to-pr `/commit auto`)
#   4. modes/pr.md Step 4 conditionally appends `--auto` to LAND_ARGS
#      when AUTO_FLAG=1 (the load-bearing change for issue #236)
#   5. modes/pr.md "PR mode does NOT" note documents the gate (no longer
#      blanket "no --auto passed to /land-pr" — must reflect #236)
#
# Run from repo root: bash tests/test-commit.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/skills/commit/SKILL.md"
PR_MODE="$REPO_ROOT/skills/commit/modes/pr.md"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  printf '\033[32m  PASS\033[0m %s\n' "$1"
  PASS_COUNT=$((PASS_COUNT + 1))
}
fail() {
  printf '\033[31m  FAIL\033[0m %s\n' "$1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

echo "=== /commit — positional auto (issue #236) ==="

# ────────────────────────────────────────────────────────────────────
# Case 1 — argument-hint advertises positional `auto`.
# ────────────────────────────────────────────────────────────────────
if grep -qE '^argument-hint: ".*\[auto\].*"' "$SKILL"; then
  pass "1  argument-hint advertises positional [auto] (issue #236)"
else
  fail "1  argument-hint missing [auto] — issue #236"
fi

# ────────────────────────────────────────────────────────────────────
# Case 2 — AUTO_FLAG=0 default + case-insensitive `auto` token regex
# in the top-level argument parser.
# ────────────────────────────────────────────────────────────────────
AUTO_DEFAULT=$(grep -cE '^AUTO_FLAG=0$' "$SKILL" 2>/dev/null | head -1)
AUTO_DEFAULT=${AUTO_DEFAULT:-0}
AUTO_REGEX=$(grep -cE '\[aA\]\[uU\]\[tT\]\[oO\]' "$SKILL" 2>/dev/null | head -1)
AUTO_REGEX=${AUTO_REGEX:-0}
if [ "$AUTO_DEFAULT" -ge 1 ] && [ "$AUTO_REGEX" -ge 1 ]; then
  pass "2  AUTO_FLAG=0 default + case-insensitive [aA][uU][tT][oO] regex present"
else
  fail "2  parser: AUTO_FLAG-default-count=$AUTO_DEFAULT auto-regex-count=$AUTO_REGEX (each want >=1)"
fi

# ────────────────────────────────────────────────────────────────────
# Case 3 — SCOPE_HINT strip in BOTH parse paths. The `auto` token must
# not leak into PR title / scope-hint usage. The strip happens in two
# places: (a) explicit `/commit pr ...` branch where SCOPE_HINT is
# computed via `cut -d' ' -f2-` then sed-stripped; (b) config-default
# branch where SCOPE_HINT is computed from $ARGUMENTS directly with the
# same sed. Both must use the case-insensitive `[aA][uU][tT][oO]`
# pattern. Counting the strip-sed occurrences: expect >= 2.
# ────────────────────────────────────────────────────────────────────
SCOPE_STRIP=$(grep -cE "sed -E 's/\(\^\|\[\[:space:\]\]\)\[aA\]\[uU\]\[tT\]\[oO\]" "$SKILL" 2>/dev/null | head -1)
SCOPE_STRIP=${SCOPE_STRIP:-0}
if [ "$SCOPE_STRIP" -ge 2 ]; then
  pass "3  SCOPE_HINT strip-sed in both parse paths ($SCOPE_STRIP occurrences, want >=2)"
else
  fail "3  SCOPE_HINT strip-sed: $SCOPE_STRIP occurrences (want >=2 — explicit + config-default branches)"
fi

# ────────────────────────────────────────────────────────────────────
# Case 4 — modes/pr.md Step 4 conditionally appends `--auto` to
# LAND_ARGS when AUTO_FLAG=1. THE load-bearing change for issue #236.
# Exact form: `[ "${AUTO_FLAG:-0}" = "1" ] && LAND_ARGS="$LAND_ARGS --auto"`
# (matches sibling /quickfix in PR #235 — same idiom).
# ────────────────────────────────────────────────────────────────────
GATED_APPEND=$(grep -cE '\[ "\$\{AUTO_FLAG:-0\}" = "1" \] && LAND_ARGS="\$LAND_ARGS --auto"' "$PR_MODE" 2>/dev/null | head -1)
GATED_APPEND=${GATED_APPEND:-0}
if [ "$GATED_APPEND" -ge 1 ]; then
  pass "4  modes/pr.md: conditional --auto LAND_ARGS append present (issue #236)"
else
  fail "4  modes/pr.md: gated --auto append count=$GATED_APPEND (want >=1)"
fi

# ────────────────────────────────────────────────────────────────────
# Case 5 — modes/pr.md "PR mode does NOT" note documents the gate.
# Pre-#236 line was literally: "Auto-merge (no `--auto` passed to
# `/land-pr`)". That blanket statement must be gone. The replacement
# documents that auto-merge is gated on the positional `auto` token
# (the cross-issue invariant per the issue body's constraint).
# ────────────────────────────────────────────────────────────────────
OLD_BLANKET=$(grep -cE 'Auto-merge \(no `--auto` passed to `/land-pr`\)' "$PR_MODE" 2>/dev/null | head -1)
OLD_BLANKET=${OLD_BLANKET:-0}
NEW_GATED=$(grep -cE 'unless the positional `auto` token is passed' "$PR_MODE" 2>/dev/null | head -1)
NEW_GATED=${NEW_GATED:-0}
if [ "$OLD_BLANKET" -eq 0 ] && [ "$NEW_GATED" -ge 1 ]; then
  pass "5  modes/pr.md: old blanket 'no --auto' gone ($OLD_BLANKET), new gated prose present ($NEW_GATED) — issue #236"
else
  fail "5  modes/pr.md: old-blanket=$OLD_BLANKET (want 0), new-gated-prose=$NEW_GATED (want >=1)"
fi

echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"
[ "$FAIL_COUNT" -eq 0 ]
