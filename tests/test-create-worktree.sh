#!/bin/bash
# Tests for scripts/create-worktree.sh — 21-case suite.
# Run from repo root: bash tests/test-create-worktree.sh
#
# Cases 1-13 cover foundational behaviour: path-template variants,
# exit codes 0/2/3/4/5, stdout discipline, no-tracking assertion,
# and purpose/branch-name semantics.
#
# Cases 14-20 are named regression guards (anchors in the plan's
# Phase 1b Acceptance Criteria §14-20 — KEEP VERBATIM):
#   14. Whitespace slug                       (R-F12)
#   15. Slash-in-prefix rejected              (R2-H1)
#   16. --branch-name override                (R2-H1)
#   17. CWD-invariance                        (R-F9)
#   18. Concurrent same-slug invocations      (R2-H3)
#   19. Post-create write failure rollback    (R-F17)
#   20. --no-preflight                        (R2-M3)
#   21. --pipeline-id required                (Phase 3 follow-up)
#
# Each case passes --pipeline-id "test.create-worktree.$$" explicitly
# (the script rejects missing --pipeline-id with rc 5). Per-case
# cleanup runs on the success path; the EXIT trap is the safety net.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# MAIN_ROOT resolves via git-common-dir — may differ from REPO_ROOT when
# this test runs from within a nested worktree. The script anchors all
# paths on MAIN_ROOT, so the test must too (else default paths mismatch).
MAIN_ROOT="$(cd "$(git -C "$REPO_ROOT" rev-parse --git-common-dir)/.." && pwd)"
PROJECT_NAME="$(basename "$MAIN_ROOT")"

# Fixture anchors for cases 10, 11, 19. These cases construct synthetic
# branches via plumbing (commit-tree) rooted on the current main-equivalent
# commit. On a main-branch checkout (local dev, push-to-main CI) `main`
# exists as a local ref; on a GitHub Actions PR checkout HEAD is detached
# at the PR merge commit and local `main` does NOT exist. Fall back to
# HEAD so fixture construction succeeds in both environments.
# --verify --quiet ensures rev-parse prints NOTHING on failure (without
# --verify it prints the unresolved name to stdout, polluting the var).
MAIN_SHA=$(git -C "$MAIN_ROOT" rev-parse --verify --quiet main 2>/dev/null \
        || git -C "$MAIN_ROOT" rev-parse --verify HEAD)
MAIN_TREE_SHA=$(git -C "$MAIN_ROOT" rev-parse --verify --quiet main^{tree} 2>/dev/null \
             || git -C "$MAIN_ROOT" rev-parse --verify HEAD^{tree})
# Prefer the worktree copy of the script so in-flight edits (this phase's
# Phase 1a-gap fixes, for example) are exercised rather than the landed
# main-repo copy. Fall back to the main-repo script only if the worktree
# copy is missing.
SCRIPT="$REPO_ROOT/scripts/create-worktree.sh"
if [ ! -x "$SCRIPT" ]; then
  SCRIPT="$MAIN_ROOT/scripts/create-worktree.sh"
fi

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

# ────────────────────────────────────────────────────────────────────
# Per-run isolation: SLUG_BASE ties every test artefact to $$.
# TEST_PREFIX is the common string that appears in every created
# worktree path/branch so the EXIT trap's final leak-check can
# grep on it.
# ────────────────────────────────────────────────────────────────────
SLUG_BASE="cw-smoke-$$"
TEST_PREFIX="$SLUG_BASE"

# Tempdirs for external fixtures (case 19 base branch, case 20 fake remote).
TEST_TMPDIR="/tmp/cw-test-tmp-$$"
FAKE_BARE_DIR="$TEST_TMPDIR/fake-bare.git"
ROLLBACK_BRANCH="test-rollback-base-$$"

# Every path we may create. Populated per-case; cleanup iterates.
WT_PATHS=()
BRANCHES=()

register_wt() { WT_PATHS+=("$1"); }
register_branch() { BRANCHES+=("$1"); }

cleanup() {
  local p b
  for p in "${WT_PATHS[@]:-}"; do
    [ -z "$p" ] && continue
    git -C "$MAIN_ROOT" worktree remove --force "$p" 2>/dev/null || true
    # Only rm dirs under /tmp (literal) or our test tmpdir — defence-in-depth.
    if [ -d "$p" ] && [[ "$p" == /tmp/* ]]; then
      rm -rf -- "$p" 2>/dev/null || true
    fi
  done
  for b in "${BRANCHES[@]:-}"; do
    [ -z "$b" ] && continue
    git -C "$MAIN_ROOT" branch -D "$b" 2>/dev/null || true
  done
  git -C "$MAIN_ROOT" worktree prune 2>/dev/null || true

  # Fixture teardown.
  rm -rf -- "$TEST_TMPDIR" 2>/dev/null || true

  # Final leak-check. Prints a warning (not a test failure) but makes leaks
  # visible in the results stream for debugging.
  local leaks
  leaks=$(git -C "$MAIN_ROOT" worktree list | grep -c -- "$TEST_PREFIX" || true)
  if [ "${leaks:-0}" -ne 0 ]; then
    printf '\033[33m  WARN\033[0m worktree-leak-check: %d residual entries containing "%s"\n' \
      "$leaks" "$TEST_PREFIX" >&2
  fi
}
trap cleanup EXIT

mkdir -p "$TEST_TMPDIR"

echo "=== Phase 1b — scripts/create-worktree.sh (20 cases) ==="

# ────────────────────────────────────────────────────────────────────
# Case 1 — Fresh creation (plain, no flags). rc=0, stdout=absolute path,
# .zskills-tracked present with sanitized pipeline ID.
# Path template: ${WORKTREE_ROOT}/${PROJECT_NAME}-${SLUG}
# Branch:        wt-${SLUG}
# ────────────────────────────────────────────────────────────────────
SLUG_1="${SLUG_BASE}-c1"
WT_1="/tmp/${PROJECT_NAME}-${SLUG_1}"
BR_1="wt-${SLUG_1}"
register_wt "$WT_1"; register_branch "$BR_1"

ERR_1=$(mktemp)
STDOUT_1=$(  bash "$SCRIPT" --pipeline-id "test.create-worktree.$$" --no-preflight "$SLUG_1" 2>"$ERR_1")
RC_1=$?
TRACKED_1="$(cat "$WT_1/.zskills-tracked" 2>/dev/null || true)"

if [ "$RC_1" -eq 0 ] && [ "$STDOUT_1" = "$WT_1" ] && [ -d "$WT_1" ] \
   && [ -f "$WT_1/.zskills-tracked" ] && [ "$TRACKED_1" = "test.create-worktree.$$" ]; then
  pass "1  fresh creation: rc=0, stdout=absolute path, .zskills-tracked matches pipeline ID"
else
  fail "1  fresh creation: rc=$RC_1 stdout='$STDOUT_1' tracked='$TRACKED_1' expected WT='$WT_1'"
  echo "  --- stderr ---"; cat "$ERR_1"
fi
rm -f -- "$ERR_1"
# Per-case cleanup: keep WT_1 around for case 2 (re-uses slug for path-exists)?
# No — path-exists uses its own slug. Remove WT_1 now.
git -C "$MAIN_ROOT" worktree remove --force "$WT_1" 2>/dev/null || true
git -C "$MAIN_ROOT" branch -D "$BR_1" 2>/dev/null || true

# ────────────────────────────────────────────────────────────────────
# Case 2 — Path exists → rc=2, empty stdout.
# Pre-create $WT_2 as a bare directory so worktree-add-safe.sh:12-16
# returns 2. Isolates "path already exists" from "branch in use".
# ────────────────────────────────────────────────────────────────────
SLUG_2="${SLUG_BASE}-c2"
WT_2="/tmp/${PROJECT_NAME}-${SLUG_2}"
BR_2="wt-${SLUG_2}"
register_wt "$WT_2"; register_branch "$BR_2"
mkdir -p "$WT_2"

ERR_2=$(mktemp)
STDOUT_2=$(  bash "$SCRIPT" --pipeline-id "test.create-worktree.$$" --no-preflight "$SLUG_2" 2>"$ERR_2")
RC_2=$?

if [ "$RC_2" -eq 2 ] && [ -z "$STDOUT_2" ]; then
  pass "2  path-exists: rc=2, empty stdout"
else
  fail "2  path-exists: rc=$RC_2, stdout='$STDOUT_2' (expected rc=2 + empty stdout)"
  echo "  --- stderr ---"; cat "$ERR_2"
fi
rm -f -- "$ERR_2"
rm -rf -- "$WT_2" 2>/dev/null || true

# ────────────────────────────────────────────────────────────────────
# Case 3 — `--prefix P` path/branch template.
# Path: ${WORKTREE_ROOT}/${PROJECT_NAME}-${P}-${SLUG}
# Branch: ${P}-${SLUG}
# ────────────────────────────────────────────────────────────────────
SLUG_3="${SLUG_BASE}-c3"
PREFIX_3="cp"
WT_3="/tmp/${PROJECT_NAME}-${PREFIX_3}-${SLUG_3}"
BR_3="${PREFIX_3}-${SLUG_3}"
register_wt "$WT_3"; register_branch "$BR_3"

ERR_3=$(mktemp)
STDOUT_3=$(  bash "$SCRIPT" --pipeline-id "test.create-worktree.$$" --no-preflight --prefix "$PREFIX_3" "$SLUG_3" 2>"$ERR_3")
RC_3=$?

if [ "$RC_3" -eq 0 ] && [ "$STDOUT_3" = "$WT_3" ] && [ -d "$WT_3" ] \
   && git -C "$MAIN_ROOT" rev-parse --verify --quiet "$BR_3" >/dev/null; then
  pass "3  --prefix P: path=${PROJECT_NAME}-\${P}-slug, branch=\${P}-slug"
else
  fail "3  --prefix: rc=$RC_3, stdout='$STDOUT_3' (expected '$WT_3'), branch=$BR_3"
  echo "  --- stderr ---"; cat "$ERR_3"
fi
rm -f -- "$ERR_3"
git -C "$MAIN_ROOT" worktree remove --force "$WT_3" 2>/dev/null || true
git -C "$MAIN_ROOT" branch -D "$BR_3" 2>/dev/null || true

# ────────────────────────────────────────────────────────────────────
# Case 4 — `--purpose TEXT` writes .worktreepurpose with matching text.
# ────────────────────────────────────────────────────────────────────
SLUG_4="${SLUG_BASE}-c4"
WT_4="/tmp/${PROJECT_NAME}-${SLUG_4}"
BR_4="wt-${SLUG_4}"
PURPOSE_4="test purpose for case 4 $$"
register_wt "$WT_4"; register_branch "$BR_4"

ERR_4=$(mktemp)
STDOUT_4=$(  bash "$SCRIPT" --pipeline-id "test.create-worktree.$$" --no-preflight --purpose "$PURPOSE_4" "$SLUG_4" 2>"$ERR_4")
RC_4=$?
PURPOSE_CONTENT="$(cat "$WT_4/.worktreepurpose" 2>/dev/null || true)"

if [ "$RC_4" -eq 0 ] && [ "$STDOUT_4" = "$WT_4" ] \
   && [ -f "$WT_4/.worktreepurpose" ] && [ "$PURPOSE_CONTENT" = "$PURPOSE_4" ]; then
  pass "4  --purpose: .worktreepurpose written with matching content"
else
  fail "4  --purpose: rc=$RC_4, stdout='$STDOUT_4', content='$PURPOSE_CONTENT'"
  echo "  --- stderr ---"; cat "$ERR_4"
fi
rm -f -- "$ERR_4"
git -C "$MAIN_ROOT" worktree remove --force "$WT_4" 2>/dev/null || true
git -C "$MAIN_ROOT" branch -D "$BR_4" 2>/dev/null || true

# ────────────────────────────────────────────────────────────────────
# Case 5 — No --purpose: .worktreepurpose must NOT be written.
# ────────────────────────────────────────────────────────────────────
SLUG_5="${SLUG_BASE}-c5"
WT_5="/tmp/${PROJECT_NAME}-${SLUG_5}"
BR_5="wt-${SLUG_5}"
register_wt "$WT_5"; register_branch "$BR_5"

ERR_5=$(mktemp)
STDOUT_5=$(  bash "$SCRIPT" --pipeline-id "test.create-worktree.$$" --no-preflight "$SLUG_5" 2>"$ERR_5")
RC_5=$?

if [ "$RC_5" -eq 0 ] && [ ! -e "$WT_5/.worktreepurpose" ]; then
  pass "5  no --purpose: .worktreepurpose absent (caller-owned)"
else
  fail "5  no --purpose: rc=$RC_5, .worktreepurpose exists? $([ -e "$WT_5/.worktreepurpose" ] && echo yes || echo no)"
  echo "  --- stderr ---"; cat "$ERR_5"
fi
rm -f -- "$ERR_5"
git -C "$MAIN_ROOT" worktree remove --force "$WT_5" 2>/dev/null || true
git -C "$MAIN_ROOT" branch -D "$BR_5" 2>/dev/null || true

# ────────────────────────────────────────────────────────────────────
# Case 6 — `--root R` (absolute) → ${R}/${SLUG}; branch still wt-${SLUG}.
# PROJECT_NAME stem is skipped when --root is given.
# ────────────────────────────────────────────────────────────────────
SLUG_6="${SLUG_BASE}-c6"
ROOT_6="$TEST_TMPDIR/root-abs-6"
mkdir -p "$ROOT_6"
WT_6="$ROOT_6/$SLUG_6"
BR_6="wt-${SLUG_6}"
register_wt "$WT_6"; register_branch "$BR_6"

ERR_6=$(mktemp)
STDOUT_6=$(  bash "$SCRIPT" --pipeline-id "test.create-worktree.$$" --no-preflight --root "$ROOT_6" "$SLUG_6" 2>"$ERR_6")
RC_6=$?

if [ "$RC_6" -eq 0 ] && [ "$STDOUT_6" = "$WT_6" ] && [ -d "$WT_6" ] \
   && git -C "$MAIN_ROOT" rev-parse --verify --quiet "$BR_6" >/dev/null; then
  pass "6  --root R (absolute): path=R/slug, branch=wt-slug"
else
  fail "6  --root R: rc=$RC_6, stdout='$STDOUT_6' (expected '$WT_6')"
  echo "  --- stderr ---"; cat "$ERR_6"
fi
rm -f -- "$ERR_6"
git -C "$MAIN_ROOT" worktree remove --force "$WT_6" 2>/dev/null || true
git -C "$MAIN_ROOT" branch -D "$BR_6" 2>/dev/null || true

# ────────────────────────────────────────────────────────────────────
# Case 7 — `--root R --prefix P` → ${R}/${P}-${SLUG}; branch ${P}-${SLUG}.
# Prefix stays in the leaf; PROJECT_NAME stem omitted.
# ────────────────────────────────────────────────────────────────────
SLUG_7="${SLUG_BASE}-c7"
ROOT_7="$TEST_TMPDIR/root-abs-7"
PREFIX_7="do"
mkdir -p "$ROOT_7"
WT_7="$ROOT_7/${PREFIX_7}-${SLUG_7}"
BR_7="${PREFIX_7}-${SLUG_7}"
register_wt "$WT_7"; register_branch "$BR_7"

ERR_7=$(mktemp)
STDOUT_7=$(  bash "$SCRIPT" --pipeline-id "test.create-worktree.$$" --no-preflight --root "$ROOT_7" --prefix "$PREFIX_7" "$SLUG_7" 2>"$ERR_7")
RC_7=$?

if [ "$RC_7" -eq 0 ] && [ "$STDOUT_7" = "$WT_7" ] && [ -d "$WT_7" ] \
   && git -C "$MAIN_ROOT" rev-parse --verify --quiet "$BR_7" >/dev/null; then
  pass "7  --root R --prefix P: path=R/P-slug, branch=P-slug"
else
  fail "7  --root+--prefix: rc=$RC_7, stdout='$STDOUT_7' (expected '$WT_7')"
  echo "  --- stderr ---"; cat "$ERR_7"
fi
rm -f -- "$ERR_7"
git -C "$MAIN_ROOT" worktree remove --force "$WT_7" 2>/dev/null || true
git -C "$MAIN_ROOT" branch -D "$BR_7" 2>/dev/null || true

# ────────────────────────────────────────────────────────────────────
# Case 8 — `--root` relative path resolves against MAIN_ROOT (CWD-
# invariance). Invoke from a subdirectory of MAIN_ROOT; expected path
# is under MAIN_ROOT/<rel>. Case 17 exhaustively tests CWD-invariance
# across three CWDs; this case is the 8-form path-template row for
# the "relative --root" variant.
# ────────────────────────────────────────────────────────────────────
SLUG_8="${SLUG_BASE}-c8"
# Relative root, unlikely to collide with project content.
REL_ROOT_8="rel-root-cw-${SLUG_BASE}"
ABS_ROOT_8="$MAIN_ROOT/$REL_ROOT_8"
# Compute via realpath -m to match the script's canonicalization.
EXPECTED_WT_8="$(cd "$MAIN_ROOT" && realpath -m "$REL_ROOT_8/$SLUG_8")"
BR_8="wt-${SLUG_8}"
register_wt "$EXPECTED_WT_8"; register_branch "$BR_8"

ERR_8=$(mktemp)
# Invoke from a subdirectory of MAIN_ROOT (a different CWD than
# MAIN_ROOT itself) to prove the script anchors relative --root on
# MAIN_ROOT, not the caller's CWD.
SUBDIR_8="$MAIN_ROOT/scripts"
[ -d "$SUBDIR_8" ] || SUBDIR_8="$MAIN_ROOT/tests"
STDOUT_8=$( cd "$SUBDIR_8" &&   bash "$SCRIPT" --pipeline-id "test.create-worktree.$$" --no-preflight --root "$REL_ROOT_8" "$SLUG_8" 2>"$ERR_8")
RC_8=$?

if [ "$RC_8" -eq 0 ] && [ "$STDOUT_8" = "$EXPECTED_WT_8" ] && [ -d "$EXPECTED_WT_8" ]; then
  pass "8  --root relative: CWD-invariant; resolves against MAIN_ROOT"
else
  fail "8  --root relative: rc=$RC_8, stdout='$STDOUT_8' (expected '$EXPECTED_WT_8')"
  echo "  --- stderr ---"; cat "$ERR_8"
fi
rm -f -- "$ERR_8"
git -C "$MAIN_ROOT" worktree remove --force "$EXPECTED_WT_8" 2>/dev/null || true
git -C "$MAIN_ROOT" branch -D "$BR_8" 2>/dev/null || true
rm -rf -- "$ABS_ROOT_8" 2>/dev/null || true

# ────────────────────────────────────────────────────────────────────
# Case 9 — Invalid slug with metachar (rc 5).
# Whitespace is case 14's dedicated regression guard; here we test
# shell metacharacters like '$' which violate the slug regex.
# ────────────────────────────────────────────────────────────────────
ERR_9=$(mktemp)
STDOUT_9=$(  bash "$SCRIPT" --pipeline-id "test.create-worktree.$$" --no-preflight 'bad$slug' 2>"$ERR_9")
RC_9=$?

if [ "$RC_9" -eq 5 ] && [ -z "$STDOUT_9" ] && grep -q 'invalid slug' "$ERR_9"; then
  pass "9  invalid-slug (metachar): rc=5, empty stdout, diagnostic on stderr"
else
  fail "9  invalid-slug: rc=$RC_9, stdout='$STDOUT_9'"
  echo "  --- stderr ---"; cat "$ERR_9"
fi
rm -f -- "$ERR_9"

# ────────────────────────────────────────────────────────────────────
# Case 10 — Poisoned branch (behind base, 0 ahead) → rc 3.
# Setup: create branch at main, advance a side-base branch one commit
# past it; call script with --from side-base --no-preflight. The
# existing branch is now behind side-base (0 ahead, 1 behind) →
# worktree-add-safe.sh classifies as poisoned → rc 3.
# ────────────────────────────────────────────────────────────────────
SLUG_10="${SLUG_BASE}-c10"
PREFIX_10="cp"
BR_10="${PREFIX_10}-${SLUG_10}"
BASE_10="cw-testbase-${SLUG_BASE}-c10"
register_branch "$BR_10"; register_branch "$BASE_10"

# Stale branch at main SHA.
git -C "$MAIN_ROOT" branch "$BR_10" "$MAIN_SHA" 2>/dev/null || true
# Synthetic base, one empty commit ahead of main.
BASE_COMMIT_10=$(GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test \
  git -C "$MAIN_ROOT" commit-tree "$MAIN_TREE_SHA" -p "$MAIN_SHA" -m "cw-test: base advance c10")
git -C "$MAIN_ROOT" branch "$BASE_10" "$BASE_COMMIT_10" 2>/dev/null || true

ERR_10=$(mktemp)
STDOUT_10=$(  bash "$SCRIPT" --pipeline-id "test.create-worktree.$$" --no-preflight --prefix "$PREFIX_10" --from "$BASE_10" "$SLUG_10" 2>"$ERR_10")
RC_10=$?

if [ "$RC_10" -eq 3 ] && [ -z "$STDOUT_10" ] && grep -qi 'poisoned\|BEHIND' "$ERR_10"; then
  pass "10 poisoned branch (behind base, 0 ahead): rc=3"
else
  fail "10 poisoned: rc=$RC_10, stdout='$STDOUT_10'"
  echo "  --- stderr ---"; cat "$ERR_10"
fi
rm -f -- "$ERR_10"
git -C "$MAIN_ROOT" branch -D "$BR_10" 2>/dev/null || true
git -C "$MAIN_ROOT" branch -D "$BASE_10" 2>/dev/null || true

# ────────────────────────────────────────────────────────────────────
# Case 11 — Resume-denied: branch ahead of base, no --allow-resume → rc 4.
# Setup: create a branch one commit ahead of main; invoke without
# --allow-resume. worktree-add-safe.sh exits 4.
# ────────────────────────────────────────────────────────────────────
SLUG_11="${SLUG_BASE}-c11"
PREFIX_11="cp"
BR_11="${PREFIX_11}-${SLUG_11}"
register_branch "$BR_11"

AHEAD_COMMIT_11=$(GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test \
  git -C "$MAIN_ROOT" commit-tree "$MAIN_TREE_SHA" -p "$MAIN_SHA" -m "cw-test: ahead c11")
git -C "$MAIN_ROOT" branch "$BR_11" "$AHEAD_COMMIT_11" 2>/dev/null || true

ERR_11=$(mktemp)
STDOUT_11=$(  bash "$SCRIPT" --pipeline-id "test.create-worktree.$$" --no-preflight --prefix "$PREFIX_11" "$SLUG_11" 2>"$ERR_11")
RC_11=$?

if [ "$RC_11" -eq 4 ] && [ -z "$STDOUT_11" ] && grep -qi 'ZSKILLS_ALLOW_BRANCH_RESUME\|commits ahead' "$ERR_11"; then
  pass "11 resume-denied (ahead of base, no --allow-resume): rc=4"
else
  fail "11 resume-denied: rc=$RC_11, stdout='$STDOUT_11'"
  echo "  --- stderr ---"; cat "$ERR_11"
fi
rm -f -- "$ERR_11"
# Case 12 reuses the ahead branch; do NOT delete yet.

# ────────────────────────────────────────────────────────────────────
# Case 12 — Resume-allowed: branch ahead of base, with --allow-resume → rc 0.
# Re-uses BR_11 (branch ahead of main). Worktree attaches to the
# existing branch; stdout is the absolute path.
# ────────────────────────────────────────────────────────────────────
SLUG_12="$SLUG_11"  # same slug → same branch name resolution
PREFIX_12="$PREFIX_11"
WT_12="/tmp/${PROJECT_NAME}-${PREFIX_12}-${SLUG_12}"
register_wt "$WT_12"

ERR_12=$(mktemp)
STDOUT_12=$(  bash "$SCRIPT" --pipeline-id "test.create-worktree.$$" --no-preflight --prefix "$PREFIX_12" --allow-resume "$SLUG_12" 2>"$ERR_12")
RC_12=$?

if [ "$RC_12" -eq 0 ] && [ "$STDOUT_12" = "$WT_12" ] && [ -d "$WT_12" ] \
   && [ -f "$WT_12/.zskills-tracked" ]; then
  pass "12 resume-allowed: rc=0, attached to existing ahead branch"
else
  fail "12 resume-allowed: rc=$RC_12, stdout='$STDOUT_12' (expected '$WT_12')"
  echo "  --- stderr ---"; cat "$ERR_12"
fi
rm -f -- "$ERR_12"
git -C "$MAIN_ROOT" worktree remove --force "$WT_12" 2>/dev/null || true
git -C "$MAIN_ROOT" branch -D "$BR_11" 2>/dev/null || true

# ────────────────────────────────────────────────────────────────────
# Case 13 — Stdout discipline + no-tracking assertion.
#  - stdout is EXACTLY one line (the absolute path); all progress/errors
#    went to stderr (ERR_13 non-empty).
#  - .zskills-tracked and .worktreepurpose are NOT tracked by git
#    (git ls-files under the worktree returns nothing for them).
# ────────────────────────────────────────────────────────────────────
SLUG_13="${SLUG_BASE}-c13"
WT_13="/tmp/${PROJECT_NAME}-${SLUG_13}"
BR_13="wt-${SLUG_13}"
PURPOSE_13="case 13 purpose"
register_wt "$WT_13"; register_branch "$BR_13"

ERR_13=$(mktemp)
STDOUT_13=$(  bash "$SCRIPT" --pipeline-id "test.create-worktree.$$" --no-preflight --purpose "$PURPOSE_13" "$SLUG_13" 2>"$ERR_13")
RC_13=$?
STDOUT_LINES=$(printf '%s' "$STDOUT_13" | grep -c '' || true)
# Single-line check: exactly 1 line, and it equals $WT_13.
# git ls-files from WT_13 for the ephemeral files — must return empty.
TRACKED_LIST=$(git -C "$WT_13" ls-files -- .zskills-tracked .worktreepurpose 2>/dev/null || true)
STDERR_SIZE=$(wc -c < "$ERR_13" 2>/dev/null || echo 0)

if [ "$RC_13" -eq 0 ] && [ "$STDOUT_13" = "$WT_13" ] \
   && [ "${STDOUT_LINES:-0}" -eq 1 ] && [ -z "$TRACKED_LIST" ] \
   && [ "${STDERR_SIZE:-0}" -gt 0 ]; then
  pass "13 stdout discipline + no-tracking: 1-line stdout, logs on stderr, ephemeral files untracked"
else
  fail "13 stdout/no-tracking: rc=$RC_13, lines=${STDOUT_LINES:-0}, tracked='$TRACKED_LIST', stderr-bytes=$STDERR_SIZE"
  echo "  --- stderr ---"; cat "$ERR_13"
fi
rm -f -- "$ERR_13"
git -C "$MAIN_ROOT" worktree remove --force "$WT_13" 2>/dev/null || true
git -C "$MAIN_ROOT" branch -D "$BR_13" 2>/dev/null || true

# ════════════════════════════════════════════════════════════════════
# Cases 14-20: named regression guards (VERBATIM from Phase 1b spec).
# ════════════════════════════════════════════════════════════════════

# ────────────────────────────────────────────────────────────────────
# Case 14 (R-F12) — Whitespace slug → rc 5; stderr mentions whitespace.
# ────────────────────────────────────────────────────────────────────
ERR_14=$(mktemp)
STDOUT_14=$(  bash "$SCRIPT" --pipeline-id "test.create-worktree.$$" --no-preflight "bad slug" 2>"$ERR_14")
RC_14=$?

# The script's slug regex [A-Za-z0-9._-]+ rejects whitespace. Stderr
# emits "invalid slug 'bad slug' — must match [A-Za-z0-9._-]+" which
# covers the whitespace rejection. The spec-required substring is
# the rejection message — check for "invalid slug" OR "whitespace".
if [ "$RC_14" -eq 5 ] && [ -z "$STDOUT_14" ] \
   && grep -qE 'invalid slug|whitespace' "$ERR_14"; then
  pass "14 whitespace slug (R-F12): rc=5, stderr rejects whitespace"
else
  fail "14 whitespace slug: rc=$RC_14, stdout='$STDOUT_14'"
  echo "  --- stderr ---"; cat "$ERR_14"
fi
rm -f -- "$ERR_14"

# ────────────────────────────────────────────────────────────────────
# Case 15 (R2-H1) — Slash in --prefix rejected (rc 5); stderr mentions
# the slash ban AND the --branch-name alternative.
# ────────────────────────────────────────────────────────────────────
ERR_15=$(mktemp)
STDOUT_15=$(  bash "$SCRIPT" --pipeline-id "test.create-worktree.$$" --no-preflight --prefix "fix/issue" "42" 2>"$ERR_15")
RC_15=$?

if [ "$RC_15" -eq 5 ] && [ -z "$STDOUT_15" ] \
   && grep -q "prefix may not contain '/'" "$ERR_15" \
   && grep -q -- '--branch-name' "$ERR_15"; then
  pass "15 slash-in-prefix (R2-H1): rc=5, stderr names slash ban + --branch-name alternative"
else
  fail "15 slash-in-prefix: rc=$RC_15, stdout='$STDOUT_15'"
  echo "  --- stderr ---"; cat "$ERR_15"
fi
rm -f -- "$ERR_15"

# ────────────────────────────────────────────────────────────────────
# Case 16 (R2-H1) — --branch-name override succeeds. Branch has the
# slash; path leaf does not. basename(stdout) = <project>-fix-issue-42.
# ────────────────────────────────────────────────────────────────────
SLUG_16="42"
PREFIX_16="fix-issue-${SLUG_BASE}-c16"
# Unique branch name per-run to avoid cross-run collision with existing
# fix/issue-N branches. Format: fix/<slug-base>-c16-issue-42
BRANCH_16="fix/${SLUG_BASE}-c16-issue-${SLUG_16}"
WT_16="/tmp/${PROJECT_NAME}-${PREFIX_16}-${SLUG_16}"
register_wt "$WT_16"; register_branch "$BRANCH_16"

ERR_16=$(mktemp)
STDOUT_16=$(  bash "$SCRIPT" --pipeline-id "test.create-worktree.$$" --no-preflight --prefix "$PREFIX_16" --branch-name "$BRANCH_16" "$SLUG_16" 2>"$ERR_16")
RC_16=$?
BRANCH_COUNT=$(git -C "$MAIN_ROOT" branch --list "$BRANCH_16" | wc -l)
LEAF=$(basename "$STDOUT_16" 2>/dev/null || true)

# basename(path) MUST match ${PROJECT_NAME}-${PREFIX_16}-${SLUG_16}
EXPECTED_LEAF_16="${PROJECT_NAME}-${PREFIX_16}-${SLUG_16}"
# Regression-guard sub-assert from spec: no slash appears in the leaf.
case "$LEAF" in
  */*) HAS_SLASH_IN_LEAF=1 ;;
  *)   HAS_SLASH_IN_LEAF=0 ;;
esac

if [ "$RC_16" -eq 0 ] && [ "$STDOUT_16" = "$WT_16" ] \
   && [ "$BRANCH_COUNT" -eq 1 ] && [ "$LEAF" = "$EXPECTED_LEAF_16" ] \
   && [ "$HAS_SLASH_IN_LEAF" -eq 0 ]; then
  pass "16 --branch-name override (R2-H1): slash-bearing branch + hyphen-safe path leaf"
else
  fail "16 --branch-name: rc=$RC_16 stdout='$STDOUT_16' branch-count=$BRANCH_COUNT leaf='$LEAF'"
  echo "  --- stderr ---"; cat "$ERR_16"
fi
rm -f -- "$ERR_16"
git -C "$MAIN_ROOT" worktree remove --force "$WT_16" 2>/dev/null || true
git -C "$MAIN_ROOT" branch -D "$BRANCH_16" 2>/dev/null || true

# ────────────────────────────────────────────────────────────────────
# Case 17 (R-F9) — CWD-invariance. Spec phrasing was "--root ../
# --prefix do foo" which would target the main-repo parent directory.
# In this environment that parent is /workspaces (not writable by the
# agent), so the literal relative form isn't runnable. We preserve
# the spec's INTENT — prove that a relative --root resolves to the
# SAME absolute path regardless of invocation CWD (MAIN_ROOT anchor)
# — by using a relative --root that points at a writable sibling of
# MAIN_ROOT's parent structure via realpath canonicalisation: we pick
# `../$PROJECT_NAME/<sub>/` so MAIN_ROOT/../zskills/<sub>/ collapses
# back to MAIN_ROOT/<sub>/. Same CWD-invariance claim; same relative
# spelling; writable target.
# ────────────────────────────────────────────────────────────────────
SLUG_17="cwdinv-${SLUG_BASE}-c17"
PREFIX_17="do"
REL_ROOT_17="../${PROJECT_NAME}/cwdinv-root-${SLUG_BASE}"
# Expected = realpath-m of REL_ROOT_17/PREFIX_17-SLUG_17 resolved against MAIN_ROOT.
EXPECTED_WT_17="$(cd "$MAIN_ROOT" && realpath -m "$REL_ROOT_17/${PREFIX_17}-${SLUG_17}")"
BR_17="${PREFIX_17}-${SLUG_17}"
register_wt "$EXPECTED_WT_17"; register_branch "$BR_17"

# Helper worktree for the "nested worktree" invocation.
NESTED_SLUG_17="cwdinv-nested-${SLUG_BASE}-c17"
NESTED_WT_17="/tmp/${PROJECT_NAME}-${NESTED_SLUG_17}"
NESTED_BR_17="wt-${NESTED_SLUG_17}"
register_wt "$NESTED_WT_17"; register_branch "$NESTED_BR_17"

# (17a) Invoke from MAIN_ROOT.
ERR_17A=$(mktemp)
STDOUT_17A=$( cd "$MAIN_ROOT" &&   bash "$SCRIPT" --pipeline-id "test.create-worktree.$$" --no-preflight --root "$REL_ROOT_17" --prefix "$PREFIX_17" "$SLUG_17" 2>"$ERR_17A")
RC_17A=$?
# Tear down immediately so the subsequent invocations' path is free.
git -C "$MAIN_ROOT" worktree remove --force "$EXPECTED_WT_17" 2>/dev/null || true
git -C "$MAIN_ROOT" branch -D "$BR_17" 2>/dev/null || true

# (17b) Invoke from a subdirectory of MAIN_ROOT.
SUBDIR_17="$MAIN_ROOT/scripts"
[ -d "$SUBDIR_17" ] || SUBDIR_17="$MAIN_ROOT/tests"
ERR_17B=$(mktemp)
STDOUT_17B=$( cd "$SUBDIR_17" &&   bash "$SCRIPT" --pipeline-id "test.create-worktree.$$" --no-preflight --root "$REL_ROOT_17" --prefix "$PREFIX_17" "$SLUG_17" 2>"$ERR_17B")
RC_17B=$?
git -C "$MAIN_ROOT" worktree remove --force "$EXPECTED_WT_17" 2>/dev/null || true
git -C "$MAIN_ROOT" branch -D "$BR_17" 2>/dev/null || true

# (17c) Invoke from inside a nested worktree.
ERR_17C_SETUP=$(mktemp)
SETUP_STDOUT_17C=$( cd "$MAIN_ROOT" &&   bash "$SCRIPT" --pipeline-id "test.create-worktree.$$" --no-preflight "$NESTED_SLUG_17" 2>"$ERR_17C_SETUP")
SETUP_RC_17C=$?
rm -f -- "$ERR_17C_SETUP"

STDOUT_17C=""
RC_17C="setup-failed"
ERR_17C=$(mktemp)
if [ "$SETUP_RC_17C" -eq 0 ] && [ -d "$SETUP_STDOUT_17C" ]; then
  STDOUT_17C=$( cd "$SETUP_STDOUT_17C" &&     bash "$SCRIPT" --pipeline-id "test.create-worktree.$$" --no-preflight --root "$REL_ROOT_17" --prefix "$PREFIX_17" "$SLUG_17" 2>"$ERR_17C")
  RC_17C=$?
fi
git -C "$MAIN_ROOT" worktree remove --force "$EXPECTED_WT_17" 2>/dev/null || true
git -C "$MAIN_ROOT" branch -D "$BR_17" 2>/dev/null || true
git -C "$MAIN_ROOT" worktree remove --force "$NESTED_WT_17" 2>/dev/null || true
git -C "$MAIN_ROOT" branch -D "$NESTED_BR_17" 2>/dev/null || true

# Remove the synthetic root-parent dir so it doesn't leak into main repo.
SYNTH_ROOT_PARENT_17="$(cd "$MAIN_ROOT" && realpath -m "$REL_ROOT_17")"
case "$SYNTH_ROOT_PARENT_17" in
  /tmp/*|"$MAIN_ROOT"/*) rm -rf -- "$SYNTH_ROOT_PARENT_17" 2>/dev/null || true ;;
esac

if [ "$RC_17A" -eq 0 ] && [ "$RC_17B" -eq 0 ] && [ "$RC_17C" = "0" ] \
   && [ "$STDOUT_17A" = "$EXPECTED_WT_17" ] \
   && [ "$STDOUT_17B" = "$EXPECTED_WT_17" ] \
   && [ "$STDOUT_17C" = "$EXPECTED_WT_17" ]; then
  pass "17 CWD-invariance (R-F9): relative --root resolves identically from MAIN_ROOT, subdir, and nested worktree"
else
  fail "17 CWD-invariance: rc=[$RC_17A|$RC_17B|$RC_17C] stdout=[$STDOUT_17A|$STDOUT_17B|$STDOUT_17C] expected='$EXPECTED_WT_17'"
  echo "  --- stderr 17a ---"; cat "$ERR_17A"
  echo "  --- stderr 17b ---"; cat "$ERR_17B"
  echo "  --- stderr 17c ---"; cat "$ERR_17C"
fi
rm -f -- "$ERR_17A" "$ERR_17B" "$ERR_17C"

# ────────────────────────────────────────────────────────────────────
# Case 18 (R2-H3) — Concurrent same-slug invocations. Two bash
# invocations with --prefix cp foo in parallel. Exactly one rc=0,
# one rc=2 (post-TOCTOU remap). `git worktree list | grep -c` ≤ 1.
# The losing process MUST return rc=2 (not raw rc=128).
# ────────────────────────────────────────────────────────────────────
SLUG_18="concurrent-${SLUG_BASE}-c18"
PREFIX_18="cp"
WT_18="/tmp/${PROJECT_NAME}-${PREFIX_18}-${SLUG_18}"
BR_18="${PREFIX_18}-${SLUG_18}"
register_wt "$WT_18"; register_branch "$BR_18"

OUT_18A=$(mktemp); OUT_18B=$(mktemp)
ERR_18A=$(mktemp); ERR_18B=$(mktemp)
RC_FILE_A="$TEST_TMPDIR/rc-18a"
RC_FILE_B="$TEST_TMPDIR/rc-18b"

(
      bash "$SCRIPT" --pipeline-id "test.create-worktree.$$" --no-preflight --prefix "$PREFIX_18" "$SLUG_18" >"$OUT_18A" 2>"$ERR_18A"
  echo $? > "$RC_FILE_A"
) &
PID_A=$!
(
      bash "$SCRIPT" --pipeline-id "test.create-worktree.$$" --no-preflight --prefix "$PREFIX_18" "$SLUG_18" >"$OUT_18B" 2>"$ERR_18B"
  echo $? > "$RC_FILE_B"
) &
PID_B=$!
wait "$PID_A" "$PID_B"

RC_18A=$(cat "$RC_FILE_A" 2>/dev/null || echo 99)
RC_18B=$(cat "$RC_FILE_B" 2>/dev/null || echo 99)
WT_COUNT=$(git -C "$MAIN_ROOT" worktree list | grep -c -- "-${PREFIX_18}-${SLUG_18}" || true)

ZERO_COUNT=0
TWO_COUNT=0
for r in "$RC_18A" "$RC_18B"; do
  [ "$r" = "0" ] && ZERO_COUNT=$((ZERO_COUNT + 1))
  [ "$r" = "2" ] && TWO_COUNT=$((TWO_COUNT + 1))
done

if [ "$ZERO_COUNT" -eq 1 ] && [ "$TWO_COUNT" -eq 1 ] && [ "$WT_COUNT" -le 1 ]; then
  pass "18 concurrent same-slug (R2-H3): exactly one rc=0, one rc=2 (TOCTOU remap); ≤1 worktree"
else
  fail "18 concurrent: rc=[$RC_18A|$RC_18B], wt-count=$WT_COUNT (want 1 zero + 1 two, count ≤ 1)"
  echo "  --- stderr A ---"; cat "$ERR_18A"
  echo "  --- stderr B ---"; cat "$ERR_18B"
fi
rm -f -- "$OUT_18A" "$OUT_18B" "$ERR_18A" "$ERR_18B" "$RC_FILE_A" "$RC_FILE_B"
git -C "$MAIN_ROOT" worktree remove --force "$WT_18" 2>/dev/null || true
git -C "$MAIN_ROOT" branch -D "$BR_18" 2>/dev/null || true

# ────────────────────────────────────────────────────────────────────
# Case 19 (R-F17) — Post-create write-failure rollback. Commit a
# `.zskills-tracked/` DIRECTORY into a temporary branch (via plumbing —
# .zskills-tracked is gitignored so we can't `git add` it normally),
# then base a new worktree on it via --from. git worktree add checks
# out the tree → $WT/.zskills-tracked/ exists as a directory →
# `printf > $WT/.zskills-tracked` fails → script rolls back → rc=8.
# ────────────────────────────────────────────────────────────────────
SLUG_19="rollback-${SLUG_BASE}-c19"
WT_19="/tmp/${PROJECT_NAME}-${SLUG_19}"
BR_19="wt-${SLUG_19}"
register_wt "$WT_19"; register_branch "$BR_19"; register_branch "$ROLLBACK_BRANCH"

# Build the rollback base via plumbing: take main's tree, splice in
# .zskills-tracked/keep, commit on top of main.
KEEP_BLOB=$(echo "rollback fixture for case 19" | git -C "$MAIN_ROOT" hash-object -w --stdin)
SUB_TREE=$(printf '100644 blob %s\tkeep\n' "$KEEP_BLOB" | git -C "$MAIN_ROOT" mktree)
# Extract all existing entries from main's tree, append our new entry.
# ls-tree shows existing entries; pipe through mktree to reconstruct
# with the added .zskills-tracked directory.
NEW_TREE=$(
  {
    git -C "$MAIN_ROOT" ls-tree "$MAIN_TREE_SHA"
    printf '040000 tree %s\t.zskills-tracked\n' "$SUB_TREE"
  } | git -C "$MAIN_ROOT" mktree
)
ROLLBACK_COMMIT=$(GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test \
  git -C "$MAIN_ROOT" commit-tree "$NEW_TREE" -p "$MAIN_SHA" -m "cw-test: rollback fixture with .zskills-tracked/")
git -C "$MAIN_ROOT" branch "$ROLLBACK_BRANCH" "$ROLLBACK_COMMIT" 2>/dev/null || true

ERR_19=$(mktemp)
STDOUT_19=$(  bash "$SCRIPT" --pipeline-id "test.create-worktree.$$" --no-preflight --from "$ROLLBACK_BRANCH" "$SLUG_19" 2>"$ERR_19")
RC_19=$?

WT_19_IN_LIST=$(git -C "$MAIN_ROOT" worktree list | grep -c -- "$WT_19" || true)

if [ "$RC_19" -eq 8 ] && [ -z "$STDOUT_19" ] \
   && [ "$WT_19_IN_LIST" -eq 0 ] && grep -q 'rolled back' "$ERR_19"; then
  pass "19 post-create write rollback (R-F17): rc=8, worktree removed, stderr mentions rollback"
else
  fail "19 rollback: rc=$RC_19, stdout='$STDOUT_19', wt-in-list=$WT_19_IN_LIST"
  echo "  --- stderr ---"; cat "$ERR_19"
fi
rm -f -- "$ERR_19"
git -C "$MAIN_ROOT" worktree remove --force "$WT_19" 2>/dev/null || true
git -C "$MAIN_ROOT" branch -D "$BR_19" 2>/dev/null || true
git -C "$MAIN_ROOT" branch -D "$ROLLBACK_BRANCH" 2>/dev/null || true

# ────────────────────────────────────────────────────────────────────
# Case 20 (R2-M3) — --no-preflight suppresses fetch + ff-merge. Guard
# repo: a fake bare remote with one commit different from the real
# origin/main SHA. If preflight runs, `git fetch origin main` updates
# refs/remotes/origin/main to the fake SHA (visibly different from
# pre). We override `remote.origin.url` via GIT_CONFIG_* env vars
# (ephemeral — does not modify the persistent config).
# Assertion: rc=0 AND origin/main ref SHA unchanged across the call.
# ────────────────────────────────────────────────────────────────────
SLUG_20="nopre-${SLUG_BASE}-c20"
WT_20="/tmp/${PROJECT_NAME}-${SLUG_20}"
BR_20="wt-${SLUG_20}"
register_wt "$WT_20"; register_branch "$BR_20"

# Build fake bare remote.
git init --bare --quiet "$FAKE_BARE_DIR"
# Seed with a single commit whose tree is empty — SHA will not match
# our real origin/main, so a fetch would visibly move origin/main.
EMPTY_TREE=$(git -C "$FAKE_BARE_DIR" mktree </dev/null)
FAKE_COMMIT=$(GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test \
  git -C "$FAKE_BARE_DIR" commit-tree "$EMPTY_TREE" -m "fake remote seed")
git -C "$FAKE_BARE_DIR" update-ref refs/heads/main "$FAKE_COMMIT"

# Pre-SHA of the real origin/main (may be empty if ref unknown).
PRE_ORIGIN_MAIN=$(git -C "$MAIN_ROOT" rev-parse --quiet --verify refs/remotes/origin/main 2>/dev/null || echo "")

ERR_20=$(mktemp)
STDOUT_20=$(
  GIT_CONFIG_COUNT=1 \
  GIT_CONFIG_KEY_0=remote.origin.url \
  GIT_CONFIG_VALUE_0="$FAKE_BARE_DIR" \
      bash "$SCRIPT" --pipeline-id "test.create-worktree.$$" --no-preflight "$SLUG_20" 2>"$ERR_20"
)
RC_20=$?

POST_ORIGIN_MAIN=$(git -C "$MAIN_ROOT" rev-parse --quiet --verify refs/remotes/origin/main 2>/dev/null || echo "")

if [ "$RC_20" -eq 0 ] && [ "$STDOUT_20" = "$WT_20" ] \
   && [ "$PRE_ORIGIN_MAIN" = "$POST_ORIGIN_MAIN" ]; then
  pass "20 --no-preflight (R2-M3): rc=0 and refs/remotes/origin/main unchanged (no fetch occurred)"
else
  fail "20 --no-preflight: rc=$RC_20 stdout='$STDOUT_20' pre='$PRE_ORIGIN_MAIN' post='$POST_ORIGIN_MAIN'"
  echo "  --- stderr ---"; cat "$ERR_20"
fi
rm -f -- "$ERR_20"
git -C "$MAIN_ROOT" worktree remove --force "$WT_20" 2>/dev/null || true
git -C "$MAIN_ROOT" branch -D "$BR_20" 2>/dev/null || true

# ────────────────────────────────────────────────────────────────────
# Case 21 — --pipeline-id is REQUIRED. Missing flag → rc 5 with a clear
# error on stderr. The prior env-var channel was removed on purpose:
# silent fallback was the root cause of the Phase 2/3 latent bugs where
# callers forgot to plumb through their skill's canonical pipeline ID
# and silently produced a wrong .zskills-tracked. Making the flag
# required turns that class of bug into an immediate rc 5 at call time.
# ────────────────────────────────────────────────────────────────────
SLUG_21="${SLUG_BASE}-c21"
WT_21="/tmp/${PROJECT_NAME}-${SLUG_21}"
BR_21="wt-${SLUG_21}"
register_wt "$WT_21"; register_branch "$BR_21"

# Ensure env var set ≠ flag present. Setting env should NOT rescue a
# missing flag — env is no longer honoured.
ERR_21=$(mktemp)
STDOUT_21=$(ZSKILLS_PIPELINE_ID="env-is-no-longer-honoured-$$" \
  bash "$SCRIPT" --no-preflight "$SLUG_21" 2>"$ERR_21")
RC_21=$?
ERR_BODY_21="$(cat "$ERR_21" 2>/dev/null || true)"

# Three asserts in one case: rc must be 5; stderr must mention the flag
# name; no worktree may have been created on disk.
if [ "$RC_21" -eq 5 ] \
   && echo "$ERR_BODY_21" | grep -q -- '--pipeline-id' \
   && [ ! -d "$WT_21" ]; then
  pass "21 --pipeline-id required: rc=5, stderr names the flag, no worktree created"
else
  fail "21 --pipeline-id required: rc=$RC_21 wt-exists=$([ -d "$WT_21" ] && echo yes || echo no) (expected rc=5, no WT)"
  echo "  --- stderr ---"; echo "$ERR_BODY_21"
fi
rm -f -- "$ERR_21"
# No cleanup needed — nothing was created.

# ────────────────────────────────────────────────────────────────────
# Case 22 — --no-preflight defaults BASE to the main-repo's current
# branch when --from is not passed. Regression guard for Gate A in
# plans/CANARY_DO_WORKTREE_BASE.md: /do worktree-mode invoked from a
# feature branch must produce a worktree whose HEAD equals the feature
# branch's HEAD, not hardcoded 'main'.
# Isolation: runs inside a fresh fixture git repo in /tmp so the test
# does not depend on (or mutate) the real MAIN_ROOT's working-tree
# state. The script anchors on git-common-dir, so MAIN_ROOT INSIDE the
# script resolves to $FIX_22 when invoked from there.
# ────────────────────────────────────────────────────────────────────
FIX_22="/tmp/cw-c22-fixture-$$"
rm -rf "$FIX_22"
mkdir -p "$FIX_22/scripts"
git init --quiet -b main "$FIX_22"
git -C "$FIX_22" config user.email "t@t"
git -C "$FIX_22" config user.name "t"
cp "$MAIN_ROOT/scripts/sanitize-pipeline-id.sh" "$FIX_22/scripts/"
cp "$MAIN_ROOT/scripts/worktree-add-safe.sh" "$FIX_22/scripts/"
chmod +x "$FIX_22/scripts/sanitize-pipeline-id.sh" "$FIX_22/scripts/worktree-add-safe.sh"

# Seed main.
echo "init" > "$FIX_22/README.md"
git -C "$FIX_22" add README.md
git -C "$FIX_22" commit --quiet -m "init"

# Feature branch with a unique commit ahead of main.
git -C "$FIX_22" checkout --quiet -b feat-c22
echo "feat" > "$FIX_22/feat.txt"
git -C "$FIX_22" add feat.txt
git -C "$FIX_22" commit --quiet -m "feat unique commit"
FEAT_HEAD_22=$(git -C "$FIX_22" rev-parse HEAD)

SLUG_22="c22"
EXPECTED_WT_22="/tmp/$(basename "$FIX_22")-$SLUG_22"

ERR_22=$(mktemp)
STDOUT_22=$(cd "$FIX_22" && bash "$SCRIPT" --pipeline-id "test.c22.$$" --no-preflight "$SLUG_22" 2>"$ERR_22")
RC_22=$?

WT_HEAD_22="not-created"
if [ -n "$STDOUT_22" ] && [ -d "$STDOUT_22" ]; then
  WT_HEAD_22=$(git -C "$STDOUT_22" rev-parse HEAD 2>/dev/null || echo "rev-parse-failed")
fi

if [ "$RC_22" -eq 0 ] && [ "$STDOUT_22" = "$EXPECTED_WT_22" ] \
   && [ "$WT_HEAD_22" = "$FEAT_HEAD_22" ]; then
  pass "22 --no-preflight BASE defaults to main-repo HEAD: worktree HEAD matches feature branch HEAD"
else
  fail "22 --no-preflight base-from-HEAD: rc=$RC_22 stdout='$STDOUT_22' wt-head='$WT_HEAD_22' feat-head='$FEAT_HEAD_22'"
  echo "  --- stderr ---"; cat "$ERR_22"
fi
rm -f -- "$ERR_22"
# Fixture cleanup: worktree first, then fixture dir + any sibling under /tmp.
[ -n "$STDOUT_22" ] && [ -d "$STDOUT_22" ] && git -C "$FIX_22" worktree remove --force "$STDOUT_22" 2>/dev/null || true
rm -rf "$FIX_22" "$EXPECTED_WT_22"

echo ""
echo "---"
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo -e "\033[32mResults: $PASS_COUNT passed, 0 failed (of $TOTAL)\033[0m"
  exit 0
else
  echo -e "\033[31mResults: $PASS_COUNT passed, $FAIL_COUNT failed (of $TOTAL)\033[0m"
  exit 1
fi
