#!/bin/bash
# Issue #516 regression: cleanup-merged classifier and Phase 5 default
# mode must NOT classify a branch as REMOVE when the PR is reported
# MERGED but the local branch has commits not on main. `gh pr view` is
# sticky after merge, so PR=MERGED + ahead>0 is a known silent-loss
# vector — surface, don't auto-remove.
#
# Two surfaces under test:
#   A. The classify() function (Phase 7 --review mode): asserts Rule 11
#      fires (DECIDE) for PR=MERGED + ahead>0, instead of Rule 3 (REMOVE).
#   B. The Phase 5 default-mode bash loop body: asserts that an ahead-
#      count gate appears between the unpushed-commit guard and the
#      worktree-remove call.
#
# Run from repo root: bash tests/test-cleanup-merged-ahead-gate.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/skills/cleanup-merged/SKILL.md"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

echo "=== cleanup-merged ahead-count gate (issue #516) ==="

# ── A. Phase 7 classify() — dynamic check ─────────────────────────────
# Reuse the shim-extraction technique from test-cleanup-merged-review.sh.

WORK="/tmp/zskills-tests/$(basename "$REPO_ROOT")/cleanup-ahead-gate-$$"
rm -rf "$WORK"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

awk '
  /^  # Classifier — given branch/ { capturing = 1 }
  capturing { print }
  capturing && /^  \}$/ { exit }
' "$SKILL" > "$WORK/classify-fn-body.txt"

awk '
  /^  matches_long_running\(\) \{/ { capturing = 1 }
  capturing { print }
  capturing && /^  \}$/ { count++; if (count >= 1) exit }
' "$SKILL" > "$WORK/matches-fn-body.txt"

CLASSIFIER_SHIM="$WORK/classifier-shim.sh"
{
  echo "#!/bin/bash"
  echo "set -u"
  echo "LONG_RUNNING_PATTERNS=()"
  cat "$WORK/matches-fn-body.txt"
  cat "$WORK/classify-fn-body.txt"
  echo ""
  echo 'VERDICT=""; RULE_NUM=""; RULE_DESC=""'
  echo 'classify "$BR" "$WT" "$LK" "$AH" "$UG" "$PR" "$DT" "$LS"'
  echo 'echo "VERDICT=$VERDICT RULE_NUM=$RULE_NUM RULE_DESC=$RULE_DESC"'
} > "$CLASSIFIER_SHIM"
chmod +x "$CLASSIFIER_SHIM"

if ! grep -q 'VERDICT="DECIDE"' "$WORK/classify-fn-body.txt"; then
  fail "extracted classify() body looks empty/malformed — aborting"
  echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
  exit 1
fi

run_classify() {
  local desc="$1" want_v="$2" want_n="$3"
  shift 3
  local out
  out=$("$@" bash "$CLASSIFIER_SHIM" 2>&1)
  if echo "$out" | grep -q "VERDICT=$want_v RULE_NUM=$want_n"; then
    pass "rule $want_n: $desc → $want_v"
  else
    fail "rule $want_n: $desc → expected $want_v/$want_n, got: $out"
  fi
}

# Core regression: PR=MERGED + ahead>0 must NOT be REMOVE.
run_classify "PR=MERGED + ahead=1 (one post-merge commit) → DECIDE rule 11" \
  "DECIDE" "11" \
  env BR="feat/x" WT="/tmp/x" LK="0" AH="1" UG="0" PR="MERGED" DT="" LS=""

run_classify "PR=MERGED + ahead=5 (several post-merge commits) → DECIDE rule 11" \
  "DECIDE" "11" \
  env BR="feat/x" WT="/tmp/x" LK="0" AH="5" UG="0" PR="MERGED" DT="" LS=""

# Boundary: PR=MERGED + ahead=0 still REMOVE (rule 3).
run_classify "PR=MERGED + ahead=0 → REMOVE rule 3 (unchanged)" \
  "REMOVE" "3" \
  env BR="feat/x" WT="/tmp/x" LK="0" AH="0" UG="0" PR="MERGED" DT="" LS=""

# Boundary: rule 11 must NOT fire on upstream-gone alone (squash-merge
# case — ahead>0 is expected when the squash creates a different SHA;
# the Phase 5 unpushed-commit guard handles the un-squashed leak path).
run_classify "upstream-gone + ahead=3 (squash-merge) → REMOVE rule 3" \
  "REMOVE" "3" \
  env BR="feat/x" WT="/tmp/x" LK="0" AH="3" UG="1" PR="" DT="" LS=""

# Rule 11 must yield to rule 1 (locked) and rule 2 (long-running).
run_classify "locked beats rule 11" "KEEP" "1" \
  env BR="feat/x" WT="/tmp/x" LK="1" AH="3" UG="0" PR="MERGED" DT="" LS=""

# ── B. Phase 5 default-mode bash loop — static check ──────────────────
# The Phase 5 loop must include an ahead-count gate for PR=MERGED before
# `git worktree remove` / `git branch -D`. The gate is keyed to PR_STATE
# string compare + ahead-count + a SKIP path.

PHASE5_SLICE=$(awk '
  /^## Phase 5 — Default mode/{capture=1}
  /^## Phase 6 —/{exit}
  capture {print}
' "$SKILL")

if [ -z "$PHASE5_SLICE" ]; then
  # Phase header text may have evolved; fall back to a broader range.
  PHASE5_SLICE=$(sed -n '195,325p' "$SKILL")
fi

if echo "$PHASE5_SLICE" | grep -qE 'PR_STATE.*=.*MERGED.*\&\&|PR_STATE.*=.*MERGED.*]; then'; then
  pass "Phase 5: PR_STATE=MERGED branch present"
else
  fail "Phase 5: no PR_STATE=MERGED gate (issue #516 ahead-count check missing)"
fi

if echo "$PHASE5_SLICE" | grep -qE 'rev-list --count.*MAIN_BRANCH\.\.|rev-list --count "\$MAIN_BRANCH'; then
  pass "Phase 5: rev-list --count ahead-check present"
else
  fail "Phase 5: rev-list --count ahead-check missing"
fi

if echo "$PHASE5_SLICE" | grep -qE 'AHEAD.*-gt.*0|ahead.*-gt.*0' && \
   echo "$PHASE5_SLICE" | grep -qE 'commits not on main|investigate|not auto-remove'; then
  pass "Phase 5: ahead>0 SKIP path with explanatory message"
else
  fail "Phase 5: ahead>0 SKIP path or message missing"
fi

# Ordering: the gate must appear BEFORE the worktree-remove block.
GATE_LINE=$(echo "$PHASE5_SLICE" | grep -n 'rev-list --count "\$MAIN_BRANCH\.\.\$branch"' | head -1 | cut -d: -f1)
REMOVE_LINE=$(echo "$PHASE5_SLICE" | grep -n 'git worktree remove "\$WORKTREE_FOR_BRANCH"' | head -1 | cut -d: -f1)
if [ -n "$GATE_LINE" ] && [ -n "$REMOVE_LINE" ] && [ "$GATE_LINE" -lt "$REMOVE_LINE" ]; then
  pass "Phase 5: ahead-count gate precedes worktree remove"
else
  fail "Phase 5: gate ordering wrong (gate line=$GATE_LINE, remove line=$REMOVE_LINE)"
fi

# ── C. Mirror sync ────────────────────────────────────────────────────
MIRROR="$REPO_ROOT/.claude/skills/cleanup-merged/SKILL.md"
if [ -f "$MIRROR" ]; then
  if diff -q "$SKILL" "$MIRROR" >/dev/null; then
    pass "mirror sync: source SKILL.md == .claude/skills/cleanup-merged/SKILL.md"
  else
    fail "mirror drift: skills/ vs .claude/skills/ cleanup-merged SKILL.md differ"
  fi
else
  fail ".claude/skills/cleanup-merged/SKILL.md missing"
fi

BRIEFING_MIRROR="$REPO_ROOT/.claude/skills/briefing/scripts/briefing.py"
if [ -f "$BRIEFING_MIRROR" ]; then
  if diff -q "$REPO_ROOT/skills/briefing/scripts/briefing.py" "$BRIEFING_MIRROR" >/dev/null; then
    pass "mirror sync: source briefing.py == .claude mirror briefing.py"
  else
    fail "mirror drift: skills/ vs .claude/skills/ briefing.py differ"
  fi
else
  fail ".claude/skills/briefing/scripts/briefing.py missing"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] && exit 0 || exit 1
