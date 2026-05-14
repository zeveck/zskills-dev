#!/bin/bash
# tests/test-land-pr-post-merge-ff.sh — regression tests for Issue #254.
#
# /land-pr Step 7b (`Fast-forward local main after successful merge`) was
# added to close the post-squash-merge stale-main gap. Without it, local
# main's ref + working tree stay at the pre-merge SHA after a successful
# squash-merge, causing downstream skills (worktree creation, status
# checks) to anchor on stale ground state. The fix surfaces all four
# skip conditions as WARN/INFO and never overwrites local work.
#
# This test extracts the FF block from SKILL.md (by anchor verification)
# and runs the reference implementation against real git fixtures.
# Failure here means SKILL.md drifted from the reference implementation
# and Issue #254 may have regressed.
#
# Cases (all four enumerated in issue #254's "Tests" section item 1):
#   a. clean + on-base + behind-origin    → FF happens (main advances)
#   b. clean + on-feature-branch          → INFO skip, no ref change
#   c. dirty + on-base                    → WARN skip, no ref change
#   d. clean + on-base + ahead-of-origin  → WARN skip, no ref change

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_FILE="$REPO_ROOT/skills/land-pr/SKILL.md"

PASS=0
FAIL=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

if [ ! -f "$SKILL_FILE" ]; then
  echo "FAIL: SKILL.md not found at $SKILL_FILE" >&2
  exit 1
fi

# ---- Anchor regression guard ----------------------------------------
# Verify SKILL.md still contains the Step 7b sentinel and key fixture
# strings so silent prose drift can't drop the step.
for anchor in \
  'Step 7b — Fast-forward local main' \
  'MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir' \
  'merge --ff-only "origin/$BASE_BRANCH"' \
  'is $AHEAD commit(s) ahead of origin'
do
  if ! grep -qF "$anchor" "$SKILL_FILE"; then
    fail "[anchor] SKILL.md missing Step 7b anchor: $anchor" "(Issue #254 regression)"
  else
    pass "[anchor] SKILL.md contains Step 7b anchor: $anchor"
  fi
done

# ---- Reference implementation (must mirror SKILL.md Step 7b) --------
# Run as a function so each case can supply its own MAIN_ROOT, BASE,
# AHEAD-or-not, etc. Stderr is captured to a buffer per call so we can
# assert on the WARN/INFO messages.
run_ff_block() {
  # Required env: MERGE_REQUESTED, PR_STATE, BASE_BRANCH, MAIN_ROOT (real)
  # Optional: BRANCH_SLUG
  : "${BRANCH_SLUG:=test}"
  if [ "$MERGE_REQUESTED" = "true" ] && [ "$PR_STATE" = "MERGED" ]; then
    # Use the caller-provided MAIN_ROOT directly (the SKILL.md block
    # resolves it from git-common-dir, but each test fixture sets up
    # its own repo and passes the path in — same result).
    if [ -z "$MAIN_ROOT" ] || { [ ! -d "$MAIN_ROOT/.git" ] && [ ! -f "$MAIN_ROOT/.git" ]; }; then
      echo "WARN: /land-pr Step 7b: could not resolve MAIN_ROOT; skipping local-main FF" >&2
    else
      MAIN_HEAD_REF=$(git -C "$MAIN_ROOT" symbolic-ref --short HEAD 2>/dev/null || echo "")
      MAIN_DIRTY=""
      if [ -n "$MAIN_HEAD_REF" ]; then
        MAIN_DIRTY=$(git -C "$MAIN_ROOT" status --porcelain 2>/dev/null | head -1)
      fi
      AHEAD=$(git -C "$MAIN_ROOT" rev-list --count "origin/$BASE_BRANCH..$BASE_BRANCH" 2>/dev/null || echo "0")

      if [ "$MAIN_HEAD_REF" != "$BASE_BRANCH" ]; then
        echo "INFO: /land-pr Step 7b: MAIN_ROOT not on $BASE_BRANCH (HEAD=$MAIN_HEAD_REF); skipping local-main FF" >&2
      elif [ -n "$MAIN_DIRTY" ]; then
        echo "WARN: /land-pr Step 7b: MAIN_ROOT working tree dirty; skipping local-main FF" >&2
      elif [ "$AHEAD" -gt 0 ]; then
        echo "WARN: /land-pr Step 7b: local $BASE_BRANCH is $AHEAD commit(s) ahead of origin — refusing FF" >&2
      else
        FF_STDERR="/tmp/land-pr-ff-stderr-$BRANCH_SLUG-$$.log"
        if git -C "$MAIN_ROOT" fetch origin "$BASE_BRANCH" 2>"$FF_STDERR" \
           && git -C "$MAIN_ROOT" merge --ff-only "origin/$BASE_BRANCH" 2>>"$FF_STDERR"; then
          echo "INFO: /land-pr Step 7b: fast-forwarded local $BASE_BRANCH to origin/$BASE_BRANCH"
          rm -f "$FF_STDERR"
        else
          echo "WARN: /land-pr Step 7b: fetch+ff-merge failed (see $FF_STDERR); local $BASE_BRANCH not updated" >&2
        fi
      fi
    fi
  fi
}

# ---- Fixture setup --------------------------------------------------
# Each case gets its own MAIN_ROOT (a local clone of an "origin" bare
# repo) so we can control behind/ahead/dirty state independently.
FIXTURE=$(mktemp -d "/tmp/land-pr-ff-test.XXXXXX")
trap 'rm -rf "$FIXTURE"' EXIT

# Build a bare "origin" repo with two commits on main.
ORIGIN="$FIXTURE/origin.git"
git init -q --bare -b main "$ORIGIN"

SEED="$FIXTURE/seed"
git init -q -b main "$SEED"
git -C "$SEED" config user.email t@t
git -C "$SEED" config user.name t
echo "v1" > "$SEED/file.txt"
git -C "$SEED" add file.txt
git -C "$SEED" commit -q -m "v1"
git -C "$SEED" remote add origin "$ORIGIN"
git -C "$SEED" push -q origin main

# Add a second commit on origin's main so a fresh clone is "behind" by 1.
echo "v2" >> "$SEED/file.txt"
git -C "$SEED" add file.txt
git -C "$SEED" commit -q -m "v2"
git -C "$SEED" push -q origin main

clone_main_root() {
  local dest="$1"
  git clone -q "$ORIGIN" "$dest"
  git -C "$dest" config user.email t@t
  git -C "$dest" config user.name t
  # Reset to v1 so we are behind origin by 1 commit (the canonical
  # post-squash-merge state).
  local v1_sha
  v1_sha=$(git -C "$dest" rev-list --max-parents=0 HEAD)
  git -C "$dest" reset -q --hard "$v1_sha"
}

# ===== Case (a): clean + on-base + behind-origin → FF happens ==========
CASE_A="$FIXTURE/case-a"
clone_main_root "$CASE_A"
before_a=$(git -C "$CASE_A" rev-parse HEAD)
origin_a=$(git -C "$CASE_A" rev-parse origin/main)
if [ "$before_a" = "$origin_a" ]; then
  fail "[caseA] fixture sanity" "expected behind state, got HEAD==origin/main"
fi
stderr_a=$( MERGE_REQUESTED=true PR_STATE=MERGED BASE_BRANCH=main \
            MAIN_ROOT="$CASE_A" run_ff_block 2>&1 1>/dev/null )
after_a=$(git -C "$CASE_A" rev-parse HEAD)
origin_a_after=$(git -C "$CASE_A" rev-parse origin/main)
if [ "$after_a" = "$origin_a_after" ] && [ "$after_a" != "$before_a" ]; then
  pass "[caseA] clean+behind → local main fast-forwarded to origin/main"
else
  fail "[caseA] FF expected" "before=$before_a after=$after_a origin=$origin_a_after"
fi

# ===== Case (b): clean + on-feature-branch → INFO skip, no ref change ==
CASE_B="$FIXTURE/case-b"
clone_main_root "$CASE_B"
git -C "$CASE_B" checkout -q -b feat/x
before_b_main=$(git -C "$CASE_B" rev-parse main)
stderr_b=$( MERGE_REQUESTED=true PR_STATE=MERGED BASE_BRANCH=main \
            MAIN_ROOT="$CASE_B" run_ff_block 2>&1 1>/dev/null )
after_b_main=$(git -C "$CASE_B" rev-parse main)
if [ "$after_b_main" = "$before_b_main" ]; then
  pass "[caseB] on-feature-branch → main ref unchanged"
else
  fail "[caseB] no ref change" "before=$before_b_main after=$after_b_main"
fi
if echo "$stderr_b" | grep -qF "MAIN_ROOT not on main"; then
  pass "[caseB] INFO log emitted (MAIN_ROOT not on main)"
else
  fail "[caseB] INFO log" "stderr: $stderr_b"
fi

# ===== Case (c): dirty + on-base → WARN skip, no ref change ===========
CASE_C="$FIXTURE/case-c"
clone_main_root "$CASE_C"
before_c=$(git -C "$CASE_C" rev-parse HEAD)
echo "dirty" >> "$CASE_C/file.txt"   # uncommitted modification
stderr_c=$( MERGE_REQUESTED=true PR_STATE=MERGED BASE_BRANCH=main \
            MAIN_ROOT="$CASE_C" run_ff_block 2>&1 1>/dev/null )
after_c=$(git -C "$CASE_C" rev-parse HEAD)
if [ "$after_c" = "$before_c" ]; then
  pass "[caseC] dirty tree → HEAD unchanged"
else
  fail "[caseC] no ref change" "before=$before_c after=$after_c"
fi
if echo "$stderr_c" | grep -qF "working tree dirty"; then
  pass "[caseC] WARN log emitted (working tree dirty)"
else
  fail "[caseC] WARN log" "stderr: $stderr_c"
fi

# ===== Case (d): clean + on-base + ahead-of-origin → WARN, no ref change
CASE_D="$FIXTURE/case-d"
clone_main_root "$CASE_D"
# Make local main AHEAD of origin: reset to v1, then add a local commit
# that origin doesn't have. Origin is at v2; local will be at v1 + local
# commit ("ahead by 1 relative to origin/main"... but also behind by 1).
# To be unambiguously "ahead of origin" with no behind, fetch+reset to
# origin first, THEN commit locally.
git -C "$CASE_D" fetch -q origin main
git -C "$CASE_D" reset -q --hard origin/main
echo "local-only" >> "$CASE_D/file.txt"
git -C "$CASE_D" add file.txt
git -C "$CASE_D" commit -q -m "local-only commit"
before_d=$(git -C "$CASE_D" rev-parse HEAD)
ahead_d=$(git -C "$CASE_D" rev-list --count origin/main..main)
if [ "$ahead_d" -lt 1 ]; then
  fail "[caseD] fixture sanity" "expected ahead>=1 got $ahead_d"
fi
stderr_d=$( MERGE_REQUESTED=true PR_STATE=MERGED BASE_BRANCH=main \
            MAIN_ROOT="$CASE_D" run_ff_block 2>&1 1>/dev/null )
after_d=$(git -C "$CASE_D" rev-parse HEAD)
if [ "$after_d" = "$before_d" ]; then
  pass "[caseD] ahead-of-origin → HEAD unchanged"
else
  fail "[caseD] no ref change" "before=$before_d after=$after_d"
fi
if echo "$stderr_d" | grep -qF "ahead of origin"; then
  pass "[caseD] WARN log emitted (ahead of origin)"
else
  fail "[caseD] WARN log" "stderr: $stderr_d"
fi

echo ""
echo "---"
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (of %d)\033[0m\n' "$PASS" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (of %d)\033[0m\n' "$PASS" "$FAIL" "$TOTAL"
  exit 1
fi
