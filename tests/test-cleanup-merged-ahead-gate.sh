#!/bin/bash
# Issue #516 / #755 regression: cleanup-merged Phase 5 local-branch scan.
#
# #516: must NOT delete a branch when the PR is reported MERGED but the
# local branch carries commits made AFTER the merged PR head (post-merge
# work) — `gh pr view` is sticky after merge, so this is a real silent-
# loss vector; surface, don't auto-remove.
#
# #755: must NOT skip a normal squash-merged branch. Under squash-merge
# the squash commit on main has a different SHA, so the raw
# `git rev-list --count main..branch` is ALWAYS > 0 and the old gate
# skipped essentially every merged branch. The gate now compares the
# local tip to the merged PR's recorded head SHA (headRefOid):
#   tip == PR head     -> safe to delete (the squash case)
#   tip descends head  -> post-merge work -> SKIP (the #516 protection)
#   PR head missing     -> conservative ahead-count fallback
#
# Surface under test:
#   The Phase 5 local-branch-scan bash loop body, exercised both
#   statically (the gate text/ordering) and behaviorally (the extracted
#   gate logic run against stubbed `gh` + real git branches).
#
# Note: The old --review mode's classify() function (which had a
# parallel Rule 11 check) was removed in the issue #716 redesign.
# The Phase 5 gate is the remaining enforcement point.
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

echo "=== cleanup-merged Phase 5 gate (issues #516 + #755) ==="

# ── Phase 5 local-branch-scan bash loop — static checks ─────────────
# The Phase 5 loop must include the post-merge-work gate for PR=MERGED
# before `git worktree remove` / `git branch -D`.

PHASE5_SLICE=$(awk '
  /^## Phase 5 — Local branch scan/{capture=1}
  /^## Phase 6 —/{exit}
  capture {print}
' "$SKILL")

if [ -z "$PHASE5_SLICE" ]; then
  # Phase header text may have evolved; fall back to a broader range.
  PHASE5_SLICE=$(sed -n '195,400p' "$SKILL")
fi

if echo "$PHASE5_SLICE" | grep -qE 'PR_STATE.*=.*MERGED.*\&\&|PR_STATE.*=.*MERGED.*]; then'; then
  pass "Phase 5: PR_STATE=MERGED branch present"
else
  fail "Phase 5: no PR_STATE=MERGED gate present"
fi

# #755: the gate compares the local tip to the merged PR head SHA.
if echo "$PHASE5_SLICE" | grep -q 'headRefOid' \
   && echo "$PHASE5_SLICE" | grep -qE 'merge-base --is-ancestor.*PR_HEAD.*LOCAL_TIP'; then
  pass "Phase 5: gate compares local tip to PR headRefOid (issue #755)"
else
  fail "Phase 5: gate does not compare tip to PR headRefOid (issue #755 fix missing)"
fi

# #516: descendant-of-PR-head SKIP path with explanatory message.
if echo "$PHASE5_SLICE" | grep -qE 'post-merge work' \
   && echo "$PHASE5_SLICE" | grep -qE 'SKIP.*ahead of the merged PR head'; then
  pass "Phase 5: post-merge-work SKIP path present (issue #516 protection)"
else
  fail "Phase 5: post-merge-work SKIP path or message missing"
fi

# gh-fallback: conservative ahead-count gate when PR head unavailable.
if echo "$PHASE5_SLICE" | grep -qE 'rev-list --count "\$MAIN_BRANCH' \
   && echo "$PHASE5_SLICE" | grep -qE 'PR head unavailable'; then
  pass "Phase 5: conservative ahead-count fallback when PR head unavailable"
else
  fail "Phase 5: gh-fallback ahead-count gate missing"
fi

# Ordering: the gate must appear BEFORE the worktree-remove block.
GATE_LINE=$(echo "$PHASE5_SLICE" | grep -n 'headRefOid' | head -1 | cut -d: -f1)
REMOVE_LINE=$(echo "$PHASE5_SLICE" | grep -n 'git worktree remove "\$WORKTREE_FOR_BRANCH"' | head -1 | cut -d: -f1)
if [ -n "$GATE_LINE" ] && [ -n "$REMOVE_LINE" ] && [ "$GATE_LINE" -lt "$REMOVE_LINE" ]; then
  pass "Phase 5: gate precedes worktree remove"
else
  fail "Phase 5: gate ordering wrong (gate line=$GATE_LINE, remove line=$REMOVE_LINE)"
fi

# ── Behavioral: extract the gate logic and run it against stubs ──────
# Extract just the PR_STATE==MERGED gate `if` block from the skill so
# we exercise the REAL decision logic (not a paraphrase). The block
# starts at `if [ "$PR_STATE" = "MERGED" ] && [ "$UPSTREAM_GONE" = "0" ];`
# and ends at the matching `fi` (the line before the worktree comment).
GATE_BLOCK=$(echo "$PHASE5_SLICE" | awk '
  /if \[ "\$PR_STATE" = "MERGED" \] && \[ "\$UPSTREAM_GONE" = "0" \]; then/{capture=1}
  capture {print}
  capture && /^    fi$/{exit}
')

if [ -z "$GATE_BLOCK" ]; then
  fail "Phase 5: could not extract gate block for behavioral test"
else
  pass "Phase 5: gate block extracted for behavioral test"

  # Build a throwaway git repo with two scenarios.
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  STUBDIR="$TMP/stub"
  mkdir -p "$STUBDIR"

  (
    cd "$TMP" || exit 1
    git init -q -b main .
    git config user.email t@t.t; git config user.name t
    git commit -q --allow-empty -m base

    # squash-merged branch: tip == PR head (its own head), but main has a
    # DIFFERENT squash SHA. This is the #755 case that was wrongly SKIP'd.
    git checkout -q -b squashed
    git commit -q --allow-empty -m "feature work"
    SQUASHED_HEAD=$(git rev-parse squashed)

    # post-merge-work branch: an extra commit sits AFTER the PR head.
    git checkout -q -b postmerge "$SQUASHED_HEAD"
    PR_HEAD_POSTMERGE=$(git rev-parse postmerge)
    git commit -q --allow-empty -m "commit made after PR merged"

    # Simulate main getting a separate squash commit (different SHA) so
    # rev-list main..branch > 0 for both branches (the squash reality).
    git checkout -q main
    git commit -q --allow-empty -m "squash commit (different SHA)"

    # Stub gh: returns the recorded PR head per branch.
    cat > "$STUBDIR/gh" <<STUB
#!/bin/bash
# gh pr view <branch> --json headRefOid -q .headRefOid
#  \$1=pr  \$2=view  \$3=<branch>
branch="\$3"
case "\$branch" in
  squashed)  echo "$SQUASHED_HEAD" ;;
  postmerge) echo "$PR_HEAD_POSTMERGE" ;;
  *) exit 1 ;;
esac
STUB
    chmod +x "$STUBDIR/gh"

    export PATH="$STUBDIR:$PATH"
    MAIN_BRANCH=main
    PR_STATE=MERGED
    UPSTREAM_GONE=0

    run_gate() {
      branch="$1"
      LOCAL_SKIPPED=0
      OUT=$(
        for _once in 1; do
          eval "$GATE_BLOCK"
        done
        echo "SKIPPED=$LOCAL_SKIPPED"
      )
      echo "$OUT"
    }

    # Scenario 1 (#755): squash-merged, tip == PR head -> must NOT skip.
    R1=$(run_gate squashed)
    if echo "$R1" | grep -q 'SKIPPED=0' && ! echo "$R1" | grep -qE '^[[:space:]]*SKIP[[:space:]]'; then
      echo "BEHAVE1_PASS"
    else
      echo "BEHAVE1_FAIL: $R1"
    fi

    # Scenario 2 (#516): tip descends PR head -> must SKIP.
    R2=$(run_gate postmerge)
    if echo "$R2" | grep -q 'SKIPPED=1' && echo "$R2" | grep -q 'SKIP.*postmerge'; then
      echo "BEHAVE2_PASS"
    else
      echo "BEHAVE2_FAIL: $R2"
    fi
  ) > "$TMP/behave.out" 2>&1

  if grep -q 'BEHAVE1_PASS' "$TMP/behave.out"; then
    pass "Behavioral #755: squash-merged branch (tip == PR head) is deletable, NOT skipped"
  else
    fail "Behavioral #755: squash-merged branch wrongly skipped"
    sed 's/^/    /' "$TMP/behave.out"
  fi

  if grep -q 'BEHAVE2_PASS' "$TMP/behave.out"; then
    pass "Behavioral #516: branch with commit after PR head is still SKIP'd"
  else
    fail "Behavioral #516: post-merge-work branch not skipped"
    sed 's/^/    /' "$TMP/behave.out"
  fi
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
