#!/bin/bash
# Tests for the $ZSKILLS_SKILLS_ROOT export added to
# skills/update-zskills/scripts/zskills-paths.sh
# (plans/PLUGIN_LANE_SCRIPT_RESOLUTION.md Phase 1, W1.1/W1.5).
#
# $ZSKILLS_SKILLS_ROOT is the lane-portable absolute path to the installed
# skills tree, used by Family-2 bundled-script invocations:
#   - Plugin lane: ${CLAUDE_PLUGIN_ROOT}/skills (the plugin tree).
#   - /update-zskills lane: $CLAUDE_PROJECT_DIR/.claude/skills (the mirror).
#
# Critically, the legacy branch anchors on $CLAUDE_PROJECT_DIR ONLY — NOT
# $ZSKILLS_PATHS_ROOT. A worktree-anchoring session (which sets
# ZSKILLS_PATHS_ROOT for plans/issues/audit resolution) must NOT redirect the
# skills root to the worktree's mirror, because bundled-script invocation
# behavior today is hardcoded to $CLAUDE_PROJECT_DIR/.claude/skills/... (the
# main repo). Case 3 is the regression guard for plan-quality finding DA#1.
#
# Cases:
#   1. CLAUDE_PLUGIN_ROOT set AND ${CLAUDE_PLUGIN_ROOT}/skills exists →
#      $ZSKILLS_SKILLS_ROOT == ${CLAUDE_PLUGIN_ROOT}/skills.
#   1b. CLAUDE_PLUGIN_ROOT set but ${CLAUDE_PLUGIN_ROOT}/skills MISSING →
#      falls back to $CLAUDE_PROJECT_DIR/.claude/skills (dir-existence gate).
#   2. CLAUDE_PLUGIN_ROOT unset →
#      $ZSKILLS_SKILLS_ROOT == $CLAUDE_PROJECT_DIR/.claude/skills.
#   3. ZSKILLS_PATHS_ROOT exported to a worktree path, CLAUDE_PLUGIN_ROOT unset
#      → $ZSKILLS_SKILLS_ROOT STILL == $CLAUDE_PROJECT_DIR/.claude/skills
#      (regression guard: NOT anchored on ZSKILLS_PATHS_ROOT).
#   4. $ZSKILLS_SKILLS_ROOT IS exported (Family-2 callers spawn children).
#
# Run from repo root: bash tests/test-zskills-skills-root.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$REPO_ROOT/skills/update-zskills/scripts/zskills-paths.sh"

TEST_OUT="/tmp/zskills-tests/$(basename "$REPO_ROOT")"
mkdir -p "$TEST_OUT"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

if [ ! -f "$HELPER" ]; then
  fail "helper exists at expected path" "$HELPER missing"
  printf 'Results: %d passed, %d failed (of %d)\n' \
    "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"
  exit 1
fi

# --- Case 1: plugin lane — CLAUDE_PLUGIN_ROOT set + skills/ exists ----------
echo "=== Case 1: CLAUDE_PLUGIN_ROOT set + skills/ exists → \$ZSKILLS_SKILLS_ROOT = <plugin>/skills ==="
T1=$(mktemp -d /tmp/zskills-skills-root-t1-XXXXXX)
mkdir -p "$T1/plugin/skills"   # the plugin tree's skills dir
mkdir -p "$T1/project/.claude"
RESULT1=$(
  CLAUDE_PLUGIN_ROOT="$T1/plugin" CLAUDE_PROJECT_DIR="$T1/project" \
  bash -c '. "'"$HELPER"'" && printf "%s\n" "$ZSKILLS_SKILLS_ROOT"'
)
[ "$RESULT1" = "$T1/plugin/skills" ] \
  && pass "Case 1: plugin lane → \$ZSKILLS_SKILLS_ROOT = '<plugin>/skills'" \
  || fail "Case 1: \$ZSKILLS_SKILLS_ROOT" "got '$RESULT1', expected '$T1/plugin/skills'"
rm -rf "$T1"

# --- Case 1b: CLAUDE_PLUGIN_ROOT set but skills/ MISSING → legacy fallback ---
echo ""
echo "=== Case 1b: CLAUDE_PLUGIN_ROOT set but <plugin>/skills missing → legacy fallback ==="
T1B=$(mktemp -d /tmp/zskills-skills-root-t1b-XXXXXX)
mkdir -p "$T1B/plugin"          # NO skills/ subdir under the plugin root
mkdir -p "$T1B/project/.claude"
RESULT1B=$(
  CLAUDE_PLUGIN_ROOT="$T1B/plugin" CLAUDE_PROJECT_DIR="$T1B/project" \
  bash -c '. "'"$HELPER"'" && printf "%s\n" "$ZSKILLS_SKILLS_ROOT"'
)
[ "$RESULT1B" = "$T1B/project/.claude/skills" ] \
  && pass "Case 1b: missing plugin skills/ → legacy '<project>/.claude/skills'" \
  || fail "Case 1b: \$ZSKILLS_SKILLS_ROOT" "got '$RESULT1B', expected '$T1B/project/.claude/skills'"
rm -rf "$T1B"

# --- Case 2: legacy lane — CLAUDE_PLUGIN_ROOT unset -------------------------
echo ""
echo "=== Case 2: CLAUDE_PLUGIN_ROOT unset → \$ZSKILLS_SKILLS_ROOT = <project>/.claude/skills ==="
T2=$(mktemp -d /tmp/zskills-skills-root-t2-XXXXXX)
mkdir -p "$T2/.claude/skills"
RESULT2=$(
  CLAUDE_PROJECT_DIR="$T2" \
  bash -c 'unset CLAUDE_PLUGIN_ROOT; . "'"$HELPER"'" && printf "%s\n" "$ZSKILLS_SKILLS_ROOT"'
)
[ "$RESULT2" = "$T2/.claude/skills" ] \
  && pass "Case 2: legacy lane → \$ZSKILLS_SKILLS_ROOT = '<project>/.claude/skills'" \
  || fail "Case 2: \$ZSKILLS_SKILLS_ROOT" "got '$RESULT2', expected '$T2/.claude/skills'"
rm -rf "$T2"

# --- Case 3: regression guard — ZSKILLS_PATHS_ROOT must NOT redirect --------
echo ""
echo "=== Case 3: ZSKILLS_PATHS_ROOT=<worktree> (plugin unset) → skills root STILL <project>/.claude/skills ==="
T3=$(mktemp -d /tmp/zskills-skills-root-t3-XXXXXX)
mkdir -p "$T3/main/.claude/skills"
mkdir -p "$T3/worktree/.claude/skills"
RESULT3=$(
  CLAUDE_PROJECT_DIR="$T3/main" ZSKILLS_PATHS_ROOT="$T3/worktree" \
  bash -c 'unset CLAUDE_PLUGIN_ROOT; . "'"$HELPER"'" && printf "%s\n" "$ZSKILLS_SKILLS_ROOT"'
)
[ "$RESULT3" = "$T3/main/.claude/skills" ] \
  && pass "Case 3 (DA#1 guard): ZSKILLS_PATHS_ROOT does NOT redirect skills root — stays <project>/.claude/skills" \
  || fail "Case 3 (DA#1 guard): \$ZSKILLS_SKILLS_ROOT" "got '$RESULT3', expected '$T3/main/.claude/skills' (must NOT be the worktree)"
rm -rf "$T3"

# --- Case 4: ZSKILLS_SKILLS_ROOT is exported -------------------------------
echo ""
echo "=== Case 4: \$ZSKILLS_SKILLS_ROOT is exported (visible to child processes) ==="
T4=$(mktemp -d /tmp/zskills-skills-root-t4-XXXXXX)
mkdir -p "$T4/.claude/skills"
RESULT4=$(
  CLAUDE_PROJECT_DIR="$T4" \
  bash -c 'unset CLAUDE_PLUGIN_ROOT; . "'"$HELPER"'" && env | grep "^ZSKILLS_SKILLS_ROOT="'
)
[ "$RESULT4" = "ZSKILLS_SKILLS_ROOT=$T4/.claude/skills" ] \
  && pass "Case 4: \$ZSKILLS_SKILLS_ROOT exported and visible in env" \
  || fail "Case 4: export" "got '$RESULT4', expected 'ZSKILLS_SKILLS_ROOT=$T4/.claude/skills'"
rm -rf "$T4"

# --- Summary ---------------------------------------------------------------
echo ""
echo "---"
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (of %d)\033[0m\n' "$PASS_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (of %d)\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit 1
fi
