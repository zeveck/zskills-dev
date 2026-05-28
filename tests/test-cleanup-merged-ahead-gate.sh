#!/bin/bash
# Issue #516 regression: cleanup-merged Phase 5 local-branch scan must
# NOT delete a branch when the PR is reported MERGED but the local
# branch has commits not on main. `gh pr view` is sticky after merge,
# so PR=MERGED + ahead>0 is a known silent-loss vector — surface, don't
# auto-remove.
#
# Surface under test:
#   The Phase 5 local-branch-scan bash loop body: asserts that an ahead-
#   count gate appears between the unpushed-commit guard and the
#   worktree-remove call.
#
# Note: The old --review mode's classify() function (which had a
# parallel Rule 11 check) was removed in the issue #716 redesign.
# The Phase 5 ahead-count gate is the remaining enforcement point.
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

# ── Phase 5 local-branch-scan bash loop — static check ──────────────
# The Phase 5 loop must include an ahead-count gate for PR=MERGED before
# `git worktree remove` / `git branch -D`. The gate is keyed to PR_STATE
# string compare + ahead-count + a SKIP path.

PHASE5_SLICE=$(awk '
  /^## Phase 5 — Local branch scan/{capture=1}
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

# ── Mirror sync ────────────────────────────────────────────────────
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
