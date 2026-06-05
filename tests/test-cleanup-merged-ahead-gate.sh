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
# shellcheck source=tests/lib/extract-fence.sh
. "$SCRIPT_DIR/lib/extract-fence.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

echo "=== cleanup-merged Phase 5 gate (issues #516 + #755) ==="

# ── Phase 5 local-branch-scan bash loop — static checks ─────────────
# The Phase 5 loop must include the post-merge-work gate for PR=MERGED
# before `git worktree remove` / `git branch -D`.
#
# Migrated from a bespoke inline awk slice to the shared
# extract_sentinel_block: the slice is everything strictly between the
# Phase 5 and Phase 6 section headers (the section headers themselves are
# not referenced by any assertion below). GAWK-portable landmarks use
# POSIX char classes for literal metacharacters.
PHASE5_SLICE=$(extract_sentinel_block "$SKILL" \
  '^## Phase 5 — Local branch scan' \
  '^## Phase 6 —')

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
# starts at `if [ "$PR_STATE" = "MERGED" ] && [ "$UPSTREAM_GONE" = "0" ]`
# (the namelist feature added a trailing `&& [ "$NAMED_FORCE" -eq 0 ]`
# guard so `force` on a named branch bypasses the post-merge gate; the
# behavioral harness below sets NAMED_FORCE=0 to exercise the non-force
# path) and ends at the matching `fi` (before the worktree comment).
#
# Migrated to the shared extract_sentinel_block: bracket the post-merge
# gate `if … fi` exclusively between the comment that immediately precedes
# the `if` ("# unsafe delete.") and the "# Apply-mode reason string"
# comment that immediately follows the closing `fi`. The slice thus contains
# exactly the `if [ "$PR_STATE" = "MERGED" ] … fi` block. POSIX char classes
# for the literal `.`/`:` so gawk emits no warning.
#
# Note: the gate block now also pushes the SKIP classification into
# LOCAL_TO_SKIP[] for the preview-mode grouped output. The
# `LOCAL_SKIPPED=$((LOCAL_SKIPPED+1))` counter still increments, so the
# behavioral assertions below remain a valid skip-vs-not-skip oracle.
GATE_BLOCK=$(extract_sentinel_block "$SKILL" \
  '^[[:space:]]*#[[:space:]]+unsafe delete[.]$' \
  '^[[:space:]]*# Apply-mode reason string')

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
    NAMED_FORCE=0   # exercise the non-force post-merge gate path
    APPLY=1         # exercise the per-line SKIP echo (preview-mode array
                    # push is functionally equivalent — issue #1113 grouped
                    # output kept apply-path per-line progress unchanged).

    run_gate() {
      branch="$1"
      LOCAL_SKIPPED=0
      LOCAL_TO_SKIP=()
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

# ── Issue #781: contained-in-main (0-ahead) branches are deletable ──
# A local branch whose tip is fully contained in main (0 commits ahead,
# `git merge-base --is-ancestor branch main`) carries zero unique commits
# and must be flagged WOULD-DELETE in preview / removed via `git branch -d`
# on apply — even with NO PR and NO upstream-gone signal. The negative
# case (a branch with commits NOT on main) must still be preserved, and a
# protected branch that happens to be 0-ahead must still be SKIPPED.

echo ""
echo "=== Issue #781: contained-in-main (0-ahead) candidate gate ==="

# Static: the candidate gate must add the contained-in-main signal and
# route it through a LOCAL ancestor check (no gh) — the candidate gate is
# the only place MERGED can flip to 1 without PR=MERGED / upstream-gone.
if echo "$PHASE5_SLICE" | grep -qE 'CONTAINED=1' \
   && echo "$PHASE5_SLICE" | grep -qE 'merge-base --is-ancestor "\$branch" "\$MAIN_BRANCH"'; then
  pass "Phase 5: contained-in-main detected via local merge-base --is-ancestor (issue #781)"
else
  fail "Phase 5: contained-in-main (CONTAINED) local detection missing (issue #781)"
fi

# The contained class must feed the MERGED candidate gate.
if echo "$PHASE5_SLICE" | grep -qE 'MERGED=1' \
   && echo "$PHASE5_SLICE" | grep -qE '\[ "\$CONTAINED" -eq 1 \]'; then
  pass "Phase 5: CONTAINED flips MERGED candidate gate (issue #781)"
else
  fail "Phase 5: CONTAINED does not feed the MERGED candidate gate (issue #781)"
fi

# The contained class must NOT require a gh call (the ancestor check is
# local). The PR-state lookup is gated on CONTAINED -eq 0.
if echo "$PHASE5_SLICE" | grep -qE 'HAVE_GH" -eq 1 \] && \[ "\$CONTAINED" -eq 0 \]'; then
  pass "Phase 5: PR-state gh lookup skipped for contained branches (issue #781, no gh call)"
else
  fail "Phase 5: contained branch still gated behind a gh PR-state lookup (issue #781)"
fi

# Behavioral: drive the REAL candidate-gate + delete-flag logic extracted
# from the skill against real git branches. We splice together the actual
# snippets the skill uses (CONTAINED detection, MERGED gate, DEL_FLAG
# selection) so we exercise real code, not a paraphrase.
# Migrated to the shared extract_sentinel_block. The CONTAINED detection +
# PR-state lookup + MERGED candidate gate live in one contiguous run; bracket
# it exclusively between the comment that precedes `CONTAINED=0` ("… skip the
# gh round-trip when it holds.") and the "# Merged-check:" comment that
# follows the `MERGED=1` `fi`.
CONTAINED_BLOCK=$(extract_sentinel_block "$SKILL" \
  '^[[:space:]]*#[[:space:]].*skip the gh round-trip when it holds[.]$' \
  '^[[:space:]]*# Merged-check:')
# Delete-flag selection: bracket exclusively between the last comment line of
# the #816 explainer ("… lossless by construction.") and the un-indented
# `done < <(git for-each-ref …` that closes the loop. The captured slice runs
# from the `if [ "$NAMED_FORCE" -eq 1 ]; then` DEL_FLAG selection through the
# `git branch "$DEL_FLAG"` delete block (its `      fi`), stopping before the
# loop's outer `    fi` (which would be unbalanced if included).
# End landmark is the loop's OUTER `fi` at exactly 4-space indent (`^    fi$`).
# The DEL_FLAG block's own `fi`s are 6- and 8-space indented, so this matches
# the outer loop fi first and the captured slice stops just before it —
# leaving the eval'd block balanced.
DELFLAG_BLOCK=$(extract_sentinel_block "$SKILL" \
  '^[[:space:]]*#[[:space:]].*lossless by construction[.]$' \
  '^    fi$')

if [ -z "$CONTAINED_BLOCK" ] || [ -z "$DELFLAG_BLOCK" ]; then
  fail "Issue #781: could not extract candidate/delete-flag blocks for behavioral test"
else
  pass "Issue #781: candidate + delete-flag blocks extracted for behavioral test"

  TMP781=$(mktemp -d)
  (
    cd "$TMP781" || exit 1
    git init -q -b main .
    git config user.email t@t.t; git config user.name t
    git commit -q --allow-empty -m base

    # contained: 0 ahead of main — tip IS an ancestor of main. Create the
    # branch, then advance main past it so the branch tip is contained.
    git checkout -q -b contained
    git checkout -q main
    git commit -q --allow-empty -m "main advances; contained tip now in main"

    # ahead: carries a commit NOT on main (must be preserved).
    git checkout -q -b ahead
    git commit -q --allow-empty -m "unique work not on main"

    # protected-contained: 0 ahead AND in the protected list (must SKIP).
    git checkout -q main
    git checkout -q -b protected-contained
    git checkout -q main
    git commit -q --allow-empty -m "main advances; protected-contained tip now in main"

    git checkout -q main

    # Harness for the candidate gate: returns MERGED + REASON + CONTAINED.
    MAIN_BRANCH=main
    UPSTREAM_GONE=0
    NAMED_FORCE=0
    HAVE_GH=0   # no gh — proves the contained class needs no gh call

    decide() {
      branch="$1"
      eval "$CONTAINED_BLOCK"
      echo "MERGED=$MERGED CONTAINED=$CONTAINED"
    }

    # Scenario A: contained branch -> MERGED candidate gate flips to 1.
    A=$(decide contained)
    if echo "$A" | grep -q 'MERGED=1' && echo "$A" | grep -q 'CONTAINED=1'; then
      echo "A_PASS"
    else
      echo "A_FAIL: $A"
    fi

    # Scenario B: ahead branch -> NOT a candidate (MERGED stays 0).
    B=$(decide ahead)
    if echo "$B" | grep -q 'MERGED=0' && echo "$B" | grep -q 'CONTAINED=0'; then
      echo "B_PASS"
    else
      echo "B_FAIL: $B"
    fi

    # Scenario C: apply path deletes a contained branch via `git branch -d`
    # (NOT -D). Drive the real DEL_FLAG selection block, then the delete.
    branch=contained
    PR_STATE=""
    REASON="contained in main"
    DEL_FLAG=""
    LOCAL_DELETED=0
    LOCAL_SKIPPED=0
    eval "$DELFLAG_BLOCK" >/dev/null 2>&1
    if [ "$DEL_FLAG" = "-d" ] && ! git show-ref --verify --quiet refs/heads/contained; then
      echo "C_PASS"
    else
      echo "C_FAIL: DEL_FLAG=$DEL_FLAG still_exists=$(git show-ref --verify --quiet refs/heads/contained && echo yes || echo no)"
    fi

    # Scenario D: the ahead branch is NOT deletable with -d (safety: -d
    # refuses a not-fully-merged branch). Confirms the negative case can
    # never be lost via the safe-delete path.
    if ! git branch -d ahead >/dev/null 2>&1 && git show-ref --verify --quiet refs/heads/ahead; then
      echo "D_PASS"
    else
      echo "D_FAIL: ahead branch was deletable via -d (would lose unique commits)"
    fi
  ) > "$TMP781/out" 2>&1

  if grep -q 'A_PASS' "$TMP781/out"; then
    pass "Behavioral #781: contained-in-main branch (no PR, no upstream-gone) is a delete candidate"
  else
    fail "Behavioral #781: contained-in-main branch not flagged as candidate"
    sed 's/^/    /' "$TMP781/out"
  fi

  if grep -q 'B_PASS' "$TMP781/out"; then
    pass "Behavioral #781 (negative): branch with commits NOT on main is preserved (not a candidate)"
  else
    fail "Behavioral #781 (negative): a branch ahead of main was wrongly flagged"
    sed 's/^/    /' "$TMP781/out"
  fi

  if grep -q 'C_PASS' "$TMP781/out"; then
    pass "Behavioral #781: apply path deletes contained branch via git branch -d (not -D)"
  else
    fail "Behavioral #781: contained branch not removed via -d"
    sed 's/^/    /' "$TMP781/out"
  fi

  if grep -q 'D_PASS' "$TMP781/out"; then
    pass "Behavioral #781: -d refuses the ahead branch (negative case can never be lost)"
  else
    fail "Behavioral #781: -d wrongly deleted an ahead branch"
    sed 's/^/    /' "$TMP781/out"
  fi

  rm -rf "$TMP781"
fi

# Protected + contained: a config-protected branch that is 0-ahead must
# STILL be skipped (the protected check runs FIRST, before CONTAINED is
# ever computed). Verify the protected-skip precedes the candidate gate.
PROT_LINE=$(echo "$PHASE5_SLICE" | grep -n 'is_protected "\$branch"' | head -1 | cut -d: -f1)
CONT_LINE=$(echo "$PHASE5_SLICE" | grep -n 'CONTAINED=0' | head -1 | cut -d: -f1)
if [ -n "$PROT_LINE" ] && [ -n "$CONT_LINE" ] && [ "$PROT_LINE" -lt "$CONT_LINE" ]; then
  pass "Issue #781: protected-skip precedes the contained-in-main candidate gate (protected 0-ahead branch still SKIPPED)"
else
  fail "Issue #781: protected-skip ordering wrong (protected line=$PROT_LINE, contained line=$CONT_LINE)"
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
