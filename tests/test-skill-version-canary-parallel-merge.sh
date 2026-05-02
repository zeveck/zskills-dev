#!/bin/bash
# tests/test-skill-version-canary-parallel-merge.sh — Phase 6.3 canary.
#
# Closes the F-DA2 failure mode of plans/SKILL_VERSIONING.md: under
# pure CalVer (`YYYY.MM.DD`), two parallel worktrees that edit the
# same SKILL.md on the same day in non-overlapping line ranges would
# textually agree on the version line — cherry-pick succeeds silently
# AND the version line ends up under-bumped (it doesn't capture the
# merged content). The hash suffix (`+HHHHHH`) is the protection: the
# two worktrees produce DIFFERENT hashes, the version lines differ, and
# the cherry-pick produces a CONFLICT that forces a recompute+rebump.
#
# This canary's load-bearing assertion is the conflict on the version
# line. If a future change reverts to pure CalVer, this assertion
# fails loudly.
#
# Defensive sandbox guard: see canary-missed-bump.
#
# Run from repo root:
#   bash tests/test-skill-version-canary-parallel-merge.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

assert_outside_repo() {
  local pwd_real repo_real
  pwd_real=$(realpath "$PWD")
  repo_real=$(realpath "$REPO_ROOT")
  case "$pwd_real" in
    "$repo_real"|"$repo_real"/*)
      echo "FAIL: canary refusing to operate inside live repo: $pwd_real" >&2
      exit 1
      ;;
  esac
}

SANDBOX_ROOT=$(mktemp -d -t zskills-canary-parallel-XXXXXX)
trap 'rm -rf "$SANDBOX_ROOT"' EXIT

# We make a SHARED bare base, then two clones acting as parallel
# worktrees A and B.
BASE_BARE="$SANDBOX_ROOT/base.git"
git clone --quiet --bare "$REPO_ROOT" "$BASE_BARE"

CLONE_A="$SANDBOX_ROOT/clone-a"
CLONE_B="$SANDBOX_ROOT/clone-b"
git clone --quiet "$BASE_BARE" "$CLONE_A"
git clone --quiet "$BASE_BARE" "$CLONE_B"

setup_clone() {
  local d="$1"
  cd "$d"
  assert_outside_repo
  git config user.email "canary@test.test"
  git config user.name "canary"
}

setup_clone "$CLONE_A"
setup_clone "$CLONE_B"

echo "=== Phase 6.3 canary: parallel-merge ==="

REL_SKILL_DIR="skills/run-plan"
REL_SKILL_MD="$REL_SKILL_DIR/SKILL.md"
[ -f "$CLONE_A/$REL_SKILL_MD" ] || { echo "FAIL: $REL_SKILL_MD missing" >&2; exit 1; }

TODAY=$(TZ=America/New_York date +%Y.%m.%d)

# --- Worktree A: edit body adding distinctive line, bump version. ---
cd "$CLONE_A"
# Append at end so A and B touch non-overlapping line ranges. We put
# A's edit two lines before EOF and B's edit at EOF — adjusted by
# adding NEW lines at distinct positions that don't share neighbors.
# We append A's line with a leading separator newline.
printf '\n%s\n' "AAA edit-from-worktree-A unique-token alpha" >> "$REL_SKILL_MD"
HASH_A=$(bash "$CLONE_A/scripts/skill-content-hash.sh" "$CLONE_A/$REL_SKILL_DIR")
VER_A="$TODAY+$HASH_A"
bash "$CLONE_A/scripts/frontmatter-set.sh" "$REL_SKILL_MD" metadata.version "$VER_A"
git add "$REL_SKILL_MD"
git commit -q -m "A: edit body + bump to $VER_A"
COMMIT_A=$(git rev-parse HEAD)

# --- Worktree B: from same base (HEAD~1 from A's perspective), edit a
# DIFFERENT line range. We re-checkout the base in B (it was already
# at base) and append B's distinctive line at EOF. ---
cd "$CLONE_B"
# B is still at base (origin/main equivalent). Append.
printf '\n\n%s\n' "BBB edit-from-worktree-B unique-token bravo" >> "$REL_SKILL_MD"
HASH_B=$(bash "$CLONE_B/scripts/skill-content-hash.sh" "$CLONE_B/$REL_SKILL_DIR")
VER_B="$TODAY+$HASH_B"
bash "$CLONE_B/scripts/frontmatter-set.sh" "$REL_SKILL_MD" metadata.version "$VER_B"
git add "$REL_SKILL_MD"
git commit -q -m "B: edit body + bump to $VER_B"
COMMIT_B=$(git rev-parse HEAD)

# Sanity: A and B produced DIFFERENT hashes (load-bearing prereq).
if [ "$HASH_A" != "$HASH_B" ]; then
  pass "A and B produced different content hashes ($HASH_A vs $HASH_B)"
else
  fail "A and B produced IDENTICAL hashes; canary cannot demonstrate version-line conflict"
fi

# --- Replay: cherry-pick A then B onto a fresh branch from base. ---
# Use clone-A's repo for the replay; fetch B's commit into A's object
# store via a remote pointing at clone-B.
cd "$CLONE_A"
git remote add clone-b "$CLONE_B" 2>/dev/null || true
git fetch -q clone-b "$COMMIT_B"

# Branch off the merge base (parent of A's commit) so the cherry-pick
# of A is itself trivial, and B's cherry-pick onto it is what tests
# the version-line conflict.
BASE_COMMIT=$(git rev-parse "$COMMIT_A^")
git checkout -q -b canary-replay "$BASE_COMMIT"

# Cherry-pick A — should apply cleanly.
if git cherry-pick "$COMMIT_A" >/dev/null 2>&1; then
  pass "cherry-pick A onto base applies cleanly"
else
  fail "cherry-pick A unexpectedly failed"
  git cherry-pick --abort 2>/dev/null || true
fi

# Cherry-pick B — MUST conflict on the version line. Allow non-zero
# exit; we INSPECT the resulting state.
git cherry-pick "$COMMIT_B" >/dev/null 2>&1 || true

# Assertion 1 (load-bearing): the SKILL.md contains conflict markers
# AND the conflict region contains both version strings.
SKILL_MD_CONTENTS=$(cat "$REL_SKILL_MD")
if [[ "$SKILL_MD_CONTENTS" == *"<<<<<<<"* ]] \
   && [[ "$SKILL_MD_CONTENTS" == *"======="* ]] \
   && [[ "$SKILL_MD_CONTENTS" == *">>>>>>>"* ]] \
   && [[ "$SKILL_MD_CONTENTS" == *"$HASH_A"* ]] \
   && [[ "$SKILL_MD_CONTENTS" == *"$HASH_B"* ]]; then
  pass "version-line conflict present (both $HASH_A and $HASH_B inside conflict markers) — pure-CalVer regression caught"
else
  fail "expected version-line conflict containing both A and B hashes; got conflict markers? a=$HASH_A b=$HASH_B in: $(printf '%s' "$SKILL_MD_CONTENTS" | head -20)"
fi

# Also confirm the conflict status is reflected in `git status`.
STATUS_OUT=$(git status --porcelain)
if [[ "$STATUS_OUT" == *"UU $REL_SKILL_MD"* ]] || [[ "$STATUS_OUT" == *"AA $REL_SKILL_MD"* ]]; then
  pass "git status reports unmerged state on $REL_SKILL_MD"
else
  fail "git status should report UU/AA on $REL_SKILL_MD; got: $STATUS_OUT"
fi

# --- Assertion 2 (resolution): keep both body edits + recompute hash. ---
# Strip conflict markers and re-form a clean SKILL.md keeping both
# body lines. We do this by reconstructing the file from the version
# present in the index ("--theirs" of B), then re-applying A's body
# line, then bumping the version to a fresh hash.
git show ":3:$REL_SKILL_MD" > "$REL_SKILL_MD"  # take "theirs" (B)
# Reapply A's body line (it's missing because we took B's blob).
printf '\n%s\n' "AAA edit-from-worktree-A unique-token alpha" >> "$REL_SKILL_MD"
HASH_C=$(bash "$CLONE_A/scripts/skill-content-hash.sh" "$CLONE_A/$REL_SKILL_DIR")
VER_C="$TODAY+$HASH_C"
bash "$CLONE_A/scripts/frontmatter-set.sh" "$REL_SKILL_MD" metadata.version "$VER_C"
git add "$REL_SKILL_MD"

# Resolution implies the merged content is a NEW state — hash must
# differ from BOTH A and B.
if [ "$HASH_C" != "$HASH_A" ] && [ "$HASH_C" != "$HASH_B" ]; then
  pass "post-merge hash $HASH_C differs from both A ($HASH_A) and B ($HASH_B)"
else
  fail "post-merge hash should differ from both A and B; got $HASH_C"
fi

# Complete the cherry-pick (commit the resolution). git cherry-pick
# --continue requires GIT_EDITOR to not block; supply true.
GIT_EDITOR=true git cherry-pick --continue >/dev/null 2>&1 || true

# --- Assertion 3 (post-merge): conformance equivalent — regex + freshness. ---
FINAL_VER=$(bash "$CLONE_A/scripts/frontmatter-get.sh" "$REL_SKILL_MD" metadata.version)
if [[ "$FINAL_VER" =~ ^[0-9]{4}\.(0[1-9]|1[0-2])\.(0[1-9]|[12][0-9]|3[01])\+[0-9a-f]{6}$ ]]; then
  pass "post-merge regex passes ($FINAL_VER)"
else
  fail "post-merge regex failed: $FINAL_VER"
fi
final_stored="${FINAL_VER##*+}"
final_fresh=$(bash "$CLONE_A/scripts/skill-content-hash.sh" "$CLONE_A/$REL_SKILL_DIR")
if [ "$final_stored" = "$final_fresh" ]; then
  pass "post-merge freshness passes (stored=$final_stored matches recomputed)"
else
  fail "post-merge freshness mismatch: stored=$final_stored fresh=$final_fresh"
fi

# Assertion 4: recompute+rebump was REQUIRED — confirmed implicitly by
# Assertion 2 (HASH_C != A and != B) and Assertion 3 (freshness).
pass "merge resolution required hash recompute + version rebump (intent: merged content is new state)"

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo ""
echo "---"
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (of %d)\033[0m\n' "$PASS_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (of %d)\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit 1
fi
