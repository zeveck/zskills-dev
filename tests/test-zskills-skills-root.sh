#!/bin/bash
# Tests for the $ZSKILLS_SKILLS_ROOT export in
# skills/update-zskills/scripts/zskills-paths.sh
# (PLUGIN_LANE_ROOT_RESOLUTION_FIX Phase 1, TARGET 1).
#
# $ZSKILLS_SKILLS_ROOT is the lane-portable absolute path to the installed
# skills tree, used by Family-2 bundled-script invocations. It is now resolved
# by ENV-INDEPENDENT self-location: the script lives at
# <skills_root>/update-zskills/scripts/zskills-paths.sh on BOTH lanes
#   - Plugin lane: ${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/
#   - /update-zskills lane: $CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/
# so resolving its own dir's `../..` yields <skills_root> on either lane.
#
# Why env-independent (the #1026 fix): the harness substitutes only the BARE
# ${CLAUDE_PLUGIN_ROOT} token in skill MARKDOWN; it does NOT substitute the
# ${CLAUDE_PLUGIN_ROOT:-} form and the var is ABSENT from the env of any script
# a skill launches/sources. The OLD `[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]`-gated
# resolution therefore ALWAYS fell to the (absent) legacy mirror on a
# mirror-less plugin consumer. BASH_SOURCE self-location needs NO env var, so it
# resolves correctly on the plugin lane, the legacy lane, from any cwd, inside a
# worktree, and through symlinks (readlink -f). These cases assert that
# env-independence directly: $ZSKILLS_SKILLS_ROOT is keyed on the script's own
# location, NOT on CLAUDE_PLUGIN_ROOT / CLAUDE_PROJECT_DIR / ZSKILLS_PATHS_ROOT.
#
# Cases:
#   1. Copied into a synthetic <plugin>/skills/update-zskills/scripts/ layout
#      with CLAUDE_PLUGIN_ROOT pointing ELSEWHERE → $ZSKILLS_SKILLS_ROOT resolves
#      to the synthetic <plugin>/skills (the script's own ../.., NOT the env var).
#   2. Copied into a synthetic <project>/.claude/skills/update-zskills/scripts/
#      layout with CLAUDE_PLUGIN_ROOT UNSET → $ZSKILLS_SKILLS_ROOT resolves to
#      <project>/.claude/skills (the script's own ../..).
#   3. Same as Case 2 but ZSKILLS_PATHS_ROOT exported to a DIFFERENT worktree
#      path → $ZSKILLS_SKILLS_ROOT is UNAFFECTED (env-independent; the worktree
#      anchor used for plans/issues/audit must NOT redirect the skills root).
#   4. cwd-independence: run from `/` with both env vars unset → still resolves
#      to the script's own ../.. (proves no reliance on PWD or env).
#   5. $ZSKILLS_SKILLS_ROOT IS exported (Family-2 callers spawn children).
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

# install_helper <skills_root_dir> — copy zskills-paths.sh into the canonical
# <skills_root>/update-zskills/scripts/ layout under the given skills root and
# echo the installed helper's absolute path.
install_helper() {
  local skills_root="$1"
  mkdir -p "$skills_root/update-zskills/scripts"
  cp "$HELPER" "$skills_root/update-zskills/scripts/zskills-paths.sh"
  printf '%s\n' "$skills_root/update-zskills/scripts/zskills-paths.sh"
}

# --- Case 1: plugin layout, CLAUDE_PLUGIN_ROOT points ELSEWHERE -------------
# Env-independence: the script's own ../.. wins over the env var. We install the
# helper into <T1>/plugin/skills/... but point CLAUDE_PLUGIN_ROOT at a DECOY
# dir; the result must be the install location, NOT the decoy.
echo "=== Case 1: plugin layout, env var points elsewhere → \$ZSKILLS_SKILLS_ROOT = installed <plugin>/skills (self-located) ==="
T1=$(mktemp -d /tmp/zskills-skills-root-t1-XXXXXX)
mkdir -p "$T1/decoy/skills" "$T1/project/.claude"
H1=$(install_helper "$T1/plugin/skills")
RESULT1=$(
  CLAUDE_PLUGIN_ROOT="$T1/decoy" CLAUDE_PROJECT_DIR="$T1/project" \
  bash -c '. "'"$H1"'" && printf "%s\n" "$ZSKILLS_SKILLS_ROOT"'
)
[ "$RESULT1" = "$T1/plugin/skills" ] \
  && pass "Case 1: self-located plugin skills root (ignores decoy CLAUDE_PLUGIN_ROOT)" \
  || fail "Case 1: \$ZSKILLS_SKILLS_ROOT" "got '$RESULT1', expected '$T1/plugin/skills'"
rm -rf "$T1"

# --- Case 2: legacy layout, CLAUDE_PLUGIN_ROOT unset -----------------------
echo ""
echo "=== Case 2: legacy layout, CLAUDE_PLUGIN_ROOT unset → \$ZSKILLS_SKILLS_ROOT = installed <project>/.claude/skills ==="
T2=$(mktemp -d /tmp/zskills-skills-root-t2-XXXXXX)
H2=$(install_helper "$T2/.claude/skills")
RESULT2=$(
  CLAUDE_PROJECT_DIR="$T2" \
  bash -c 'unset CLAUDE_PLUGIN_ROOT; . "'"$H2"'" && printf "%s\n" "$ZSKILLS_SKILLS_ROOT"'
)
[ "$RESULT2" = "$T2/.claude/skills" ] \
  && pass "Case 2: self-located legacy skills root (<project>/.claude/skills)" \
  || fail "Case 2: \$ZSKILLS_SKILLS_ROOT" "got '$RESULT2', expected '$T2/.claude/skills'"
rm -rf "$T2"

# --- Case 3: regression guard — ZSKILLS_PATHS_ROOT must NOT redirect --------
# A worktree-anchoring session sets ZSKILLS_PATHS_ROOT for plans/issues/audit
# resolution; that must NOT redirect the skills root (which self-locates).
echo ""
echo "=== Case 3: ZSKILLS_PATHS_ROOT=<worktree> set → skills root UNAFFECTED (self-located, not env-anchored) ==="
T3=$(mktemp -d /tmp/zskills-skills-root-t3-XXXXXX)
mkdir -p "$T3/worktree/.claude/skills"   # a decoy worktree mirror
H3=$(install_helper "$T3/main/.claude/skills")
RESULT3=$(
  CLAUDE_PROJECT_DIR="$T3/main" ZSKILLS_PATHS_ROOT="$T3/worktree" \
  bash -c 'unset CLAUDE_PLUGIN_ROOT; . "'"$H3"'" && printf "%s\n" "$ZSKILLS_SKILLS_ROOT"'
)
[ "$RESULT3" = "$T3/main/.claude/skills" ] \
  && pass "Case 3 (DA#1 guard): ZSKILLS_PATHS_ROOT does NOT redirect skills root — stays at the installed location" \
  || fail "Case 3 (DA#1 guard): \$ZSKILLS_SKILLS_ROOT" "got '$RESULT3', expected '$T3/main/.claude/skills' (must NOT be the worktree)"
rm -rf "$T3"

# --- Case 4: cwd-independence — run from / (skills root NOT keyed on PWD) ----
# A valid CLAUDE_PROJECT_DIR is provided (the helper needs one for its config
# root), but cwd is '/' and CLAUDE_PROJECT_DIR points at a DIFFERENT dir than
# the install location. The self-located skills root must be the INSTALL dir's
# ../.., proving it is keyed on BASH_SOURCE, never on PWD or CLAUDE_PROJECT_DIR.
echo ""
echo "=== Case 4: cwd-independent — run from '/' (skills root keyed on BASH_SOURCE, not PWD/CLAUDE_PROJECT_DIR) ==="
T4=$(mktemp -d /tmp/zskills-skills-root-t4-XXXXXX)
mkdir -p "$T4/elsewhere/.claude"
H4=$(install_helper "$T4/skills")
RESULT4=$(
  CLAUDE_PROJECT_DIR="$T4/elsewhere" \
  bash -c 'unset CLAUDE_PLUGIN_ROOT ZSKILLS_PATHS_ROOT; cd / && . "'"$H4"'" && printf "%s\n" "$ZSKILLS_SKILLS_ROOT"'
)
[ "$RESULT4" = "$T4/skills" ] \
  && pass "Case 4: cwd-independent self-location (resolves to installed <skills_root> from cwd '/', not CLAUDE_PROJECT_DIR)" \
  || fail "Case 4: \$ZSKILLS_SKILLS_ROOT" "got '$RESULT4', expected '$T4/skills'"
rm -rf "$T4"

# --- Case 5: ZSKILLS_SKILLS_ROOT is exported -------------------------------
echo ""
echo "=== Case 5: \$ZSKILLS_SKILLS_ROOT is exported (visible to child processes) ==="
T5=$(mktemp -d /tmp/zskills-skills-root-t5-XXXXXX)
H5=$(install_helper "$T5/.claude/skills")
RESULT5=$(
  CLAUDE_PROJECT_DIR="$T5" \
  bash -c 'unset CLAUDE_PLUGIN_ROOT; . "'"$H5"'" && env | grep "^ZSKILLS_SKILLS_ROOT="'
)
[ "$RESULT5" = "ZSKILLS_SKILLS_ROOT=$T5/.claude/skills" ] \
  && pass "Case 5: \$ZSKILLS_SKILLS_ROOT exported and visible in env" \
  || fail "Case 5: export" "got '$RESULT5', expected 'ZSKILLS_SKILLS_ROOT=$T5/.claude/skills'"
rm -rf "$T5"

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
