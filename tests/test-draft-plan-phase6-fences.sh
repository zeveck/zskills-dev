#!/bin/bash
# tests/test-draft-plan-phase6-fences.sh — extract-and-run the REAL
# /draft-plan Phase-6 worktree-commit fence + the /land-pr-result-parse fence.
#
# SEAM_HARDENING_HIGH Phase 5. These two fences were green-by-absence: no
# suite exercised the worktree-commit path's MAIN→TOPLEVEL OUTPUT_FILE remap,
# its FILE_REL normalization, the two exit-1 guards (out-of-tree path,
# unexpected staged set), the COMMIT_MSG_SUBJECT case-stmt, or the allow-list
# result parser (with its unknown-key-ignored + missing-file WARN branches).
#
# Strategy: EXTRACT the real fences via tests/lib/extract-fence.sh and DRIVE
# them in a real `git worktree add` sandbox. The commit fence is 3-space
# indented (nested in the Phase-6 list) → strip-indent=1. The land-pr fence
# is column-0 → strip-indent=0; it is gated behind `[ "$AUTO_FLAG" = "1" ]`
# and its dispatch is a comment, so the RESULT_FILE we pre-stage is the
# injection point.
#
# Mutating the production fences (dropping the remap, the staged-set guard,
# the out-of-tree guard, an allow-list key) makes assertions here FAIL —
# hollow-green protection presence-greps cannot give.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/skills/draft-plan/SKILL.md"

# shellcheck source=tests/lib/extract-fence.sh
. "$SCRIPT_DIR/lib/extract-fence.sh"

PASS=0
FAIL=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

if [ ! -f "$SKILL" ]; then
  echo "FAIL: draft-plan SKILL.md not found at $SKILL" >&2
  exit 1
fi

echo "=== draft-plan Phase-6 commit + land-pr fences — extract-and-run (Phase 5) ==="

TMP=$(mktemp -d "/tmp/draft-plan-phase6.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

# ── Extract the commit fence (3-space indent → strip-indent=1) ──────────
# Bracket exactly the worktree-commit fence: it opens after the
# "Auto-commit the plan file" landmark and before the "Auto-land via" one.
COMMIT_FENCE="$TMP/commit-fence.sh"
if ! extract_fence_between "$SKILL" \
      '^3[.] [*][*]Auto-commit the plan file' \
      '^4[.] [*][*]Auto-land via' 1 1 > "$COMMIT_FENCE"; then
  echo "FAIL: could not extract Phase-6 commit fence from $SKILL" >&2
  exit 1
fi
# Sanity: landmarks present, column-0 after strip-indent.
if grep -qF 'TOPLEVEL=$(git rev-parse --show-toplevel)' "$COMMIT_FENCE" \
   && grep -qF '"$MAIN_ROOT"/*) OUTPUT_FILE="$TOPLEVEL/${OUTPUT_FILE#"$MAIN_ROOT/"}" ;;' "$COMMIT_FENCE" \
   && grep -qF 'draft-plan)  COMMIT_MSG_SUBJECT="docs(plans): draft $BASE" ;;' "$COMMIT_FENCE" \
   && grep -qF 'unexpected staged set' "$COMMIT_FENCE" \
   && grep -qF 'is outside worktree' "$COMMIT_FENCE"; then
  pass "[extract] commit fence carries remap / subject-case / staged-guard / out-of-tree landmarks"
else
  fail "[extract] commit fence landmarks" "missing remap/subject/staged/out-of-tree landmark"
fi
# strip-indent worked: the MAIN_ROOT line begins at column 0.
if grep -qE '^MAIN_ROOT=\$\(cd ' "$COMMIT_FENCE"; then
  pass "[extract] strip-indent=1 dedented commit fence to column 0"
else
  fail "[extract] strip-indent" "MAIN_ROOT= not at column 0 (strip-indent failed)"
fi

# ── Extract the land-pr result-parse fence (column-0 → strip-indent=0) ──
LANDPR_FENCE="$TMP/landpr-fence.sh"
if ! extract_fence_between "$SKILL" \
      '^4[.] [*][*]Auto-land via' \
      '^5[.] [*][*]Plan index' 1 0 > "$LANDPR_FENCE"; then
  echo "FAIL: could not extract Phase-6 land-pr fence from $SKILL" >&2
  exit 1
fi
if grep -qF 'STATUS|PR_URL|PR_NUMBER|CI_STATUS|PR_STATE|REASON)' "$LANDPR_FENCE" \
   && grep -qF '*) ;;  # unknown keys ignored (forward-compat)' "$LANDPR_FENCE" \
   && grep -qF 'produced no result file' "$LANDPR_FENCE"; then
  pass "[extract] land-pr fence carries allow-list / unknown-key / no-result-file landmarks"
else
  fail "[extract] land-pr fence landmarks" "missing allow-list/unknown-key/no-result landmark"
fi

# ── Real git sandbox: main repo + a `git worktree add` worktree ─────────
# A real worktree is required because the commit fence reads
# `git rev-parse --git-common-dir` / `--show-toplevel` and stages+commits.
MAIN="$TMP/main"
mkdir -p "$MAIN"
( cd "$MAIN"
  git init -q
  git config user.email t@t.t
  git config user.name t
  git config commit.gpgsign false
  mkdir -p plans
  echo seed > seed.txt
  git add -A && git commit -qm seed
) || { echo "FAIL: sandbox init" >&2; exit 1; }
WT="$TMP/wt"
( cd "$MAIN" && git worktree add -q -b feat/draftplan-test "$WT" ) \
  || { echo "FAIL: git worktree add" >&2; exit 1; }

# Fake the two sourced config scripts so the fence runs hermetically. The
# fence sources zskills-paths.sh and zskills-resolve-config.sh; we provide
# no-op stubs that set only what the fence reads (COMMIT_CO_AUTHOR), so the
# real config resolver and the host repo do not enter the picture.
FAKE_SKILLS="$TMP/fake/skills/update-zskills/scripts"
mkdir -p "$FAKE_SKILLS"
: > "$FAKE_SKILLS/zskills-paths.sh"
cat > "$FAKE_SKILLS/zskills-resolve-config.sh" <<'EOF'
COMMIT_CO_AUTHOR=""
EOF
FAKE_PROJECT="$TMP/fake"
mkdir -p "$FAKE_PROJECT/.claude/skills/update-zskills/scripts"
cp "$FAKE_SKILLS/zskills-paths.sh" "$FAKE_PROJECT/.claude/skills/update-zskills/scripts/"
cp "$FAKE_SKILLS/zskills-resolve-config.sh" "$FAKE_PROJECT/.claude/skills/update-zskills/scripts/"

# run_commit_fence — run the EXTRACTED commit fence in a clean subshell.
# Inputs via env: OUTPUT_FILE (the plan path the fence stages+commits).
# Sets: RC_OUT (subject echoed), RC_RC, RC_ERR.
run_commit_fence() {
  local out_file="$1"
  RC_ERR="$TMP/commit.stderr"
  : > "$RC_ERR"
  RC_OUT=$( exec 2>"$RC_ERR"
    set +e
    set -u
    export CLAUDE_PROJECT_DIR="$FAKE_PROJECT"
    unset CLAUDE_PLUGIN_ROOT
    cd "$WT"
    WT_PATH="$WT"
    OUTPUT_FILE="$out_file"
    # shellcheck disable=SC1090
    . "$COMMIT_FENCE"
    printf 'SUBJECT=%s\n' "${COMMIT_MSG_SUBJECT:-<unset>}"
    printf 'FILE_REL=%s\n' "${FILE_REL:-<unset>}"
  )
  RC_RC=$?
}
val() { printf '%s\n' "$2" | sed -n "s/^$1=//p" | head -1; }

# ── Case 1: MAIN-anchored OUTPUT_FILE remaps to TOPLEVEL + commits ──────
# Write the plan into the worktree, but pass a MAIN_ROOT-anchored path; the
# fence's R3-1 remap must rewrite it to $WT/... and commit it.
mkdir -p "$WT/plans"
echo "# plan" > "$WT/plans/THERMAL.md"
run_commit_fence "$MAIN/plans/THERMAL.md"
if [ "$RC_RC" -eq 0 ] \
   && [ "$(val SUBJECT "$RC_OUT")" = "docs(plans): draft THERMAL" ] \
   && [ "$(val FILE_REL "$RC_OUT")" = "plans/THERMAL.md" ] \
   && git -C "$WT" log -1 --pretty=%s | grep -qxF "docs(plans): draft THERMAL"; then
  pass "1  MAIN-anchored OUTPUT_FILE remaps to TOPLEVEL, FILE_REL normalizes, commit lands"
else
  fail "1  remap+commit" "rc=$RC_RC subject='$(val SUBJECT "$RC_OUT")' file_rel='$(val FILE_REL "$RC_OUT")' err='$(cat "$RC_ERR")'"
fi

# ── Case 2: already-TOPLEVEL-relative OUTPUT_FILE normalizes the same ───
echo "# plan2" > "$WT/plans/SECOND.md"
run_commit_fence "$WT/plans/SECOND.md"
if [ "$RC_RC" -eq 0 ] \
   && [ "$(val FILE_REL "$RC_OUT")" = "plans/SECOND.md" ] \
   && [ "$(val SUBJECT "$RC_OUT")" = "docs(plans): draft SECOND" ]; then
  pass "2  TOPLEVEL-anchored OUTPUT_FILE → FILE_REL normalizes to plans/SECOND.md"
else
  fail "2  FILE_REL normalize" "rc=$RC_RC file_rel='$(val FILE_REL "$RC_OUT")' err='$(cat "$RC_ERR")'"
fi

# ── Case 3: escaping `../*` path → exit 1 (out-of-tree guard) ───────────
# A path OUTSIDE the worktree must hit the `/*|../*` guard and exit 1.
echo x > "$TMP/OUTSIDE.md"
run_commit_fence "$TMP/OUTSIDE.md"
if [ "$RC_RC" -eq 1 ] && grep -qF 'is outside worktree' "$RC_ERR"; then
  pass "3  escaping ../* OUTPUT_FILE → exit 1 'is outside worktree'"
else
  fail "3  out-of-tree guard" "rc=$RC_RC err='$(cat "$RC_ERR")'"
fi

# ── Case 4: two-file staged set → exit 1 (unexpected staged set) ────────
# Pre-stage a second file so `git add $FILE_REL` leaves TWO files staged;
# the staged-set guard must fire.
echo "# plan3" > "$WT/plans/THIRD.md"
echo extra > "$WT/extra.txt"
git -C "$WT" add extra.txt
run_commit_fence "$WT/plans/THIRD.md"
if [ "$RC_RC" -eq 1 ] && grep -qF 'unexpected staged set' "$RC_ERR"; then
  pass "4  two-file staged set → exit 1 'unexpected staged set'"
else
  fail "4  staged-set guard" "rc=$RC_RC err='$(cat "$RC_ERR")'"
fi
git -C "$WT" reset -q || true

# ── land-pr result-parse fence: allow-list + unknown-key + WARN ─────────
# The fence is gated behind AUTO_FLAG=1 && TOPLEVEL!=MAIN_ROOT and its
# `# Skill: { skill: "land-pr" ... }` dispatch is a comment, so a pre-staged
# RESULT_FILE drives the post-dispatch allow-list parser. We rewrite the
# fence's RESULT_FILE assignment to our staged path.
LANDPR_PATCHED="$TMP/landpr-patched.sh"
sed 's#RESULT_FILE="/tmp/land-pr-result-draft-plan-\${SLUG}-\$\$.txt"#RESULT_FILE="$PREPARED_RESULT_FILE"#' \
  "$LANDPR_FENCE" > "$LANDPR_PATCHED"
if grep -qF 'RESULT_FILE="$PREPARED_RESULT_FILE"' "$LANDPR_PATCHED"; then
  : # ok
else
  echo "FAIL: RESULT_FILE redirect rewrite did not apply to land-pr fence" >&2
  exit 1
fi

run_landpr_fence() { # $1 = stage-result (1/0); remaining = result kvs
  local stage="$1"; shift
  local rf="$TMP/lp-result.txt"
  rm -f "$rf"
  if [ "$stage" -eq 1 ]; then
    : > "$rf"
    local kv; for kv in "$@"; do printf '%s\n' "$kv" >> "$rf"; done
  fi
  LP_ERR="$TMP/lp.stderr"; : > "$LP_ERR"
  LP_OUT=$( exec 2>"$LP_ERR"
    set +e
    set -u
    export CLAUDE_PROJECT_DIR="$FAKE_PROJECT"
    unset CLAUDE_PLUGIN_ROOT
    cd "$WT"
    AUTO_FLAG=1
    TOPLEVEL="$WT"
    MAIN_ROOT="$MAIN"
    OUTPUT_FILE="$WT/plans/THERMAL.md"
    TRACKING_ID="thermal"
    ROUND=2
    PREPARED_RESULT_FILE="$rf"
    # shellcheck disable=SC1090
    . "$LANDPR_PATCHED"
  )
  LP_RC=$?
}

# ── Case 5: allow-list parse — known keys echoed, unknown ignored ───────
run_landpr_fence 1 STATUS=created PR_URL=http://x/1 CI_STATUS=pass \
  FROBNICATE=ignored PR_STATE=OPEN
if [ "$LP_RC" -eq 0 ] \
   && grep -qF 'STATUS=created CI_STATUS=pass PR=http://x/1' "$LP_ERR"; then
  pass "5  land-pr allow-list parse: known keys parsed, unknown key (FROBNICATE) ignored"
else
  fail "5  land-pr allow-list" "rc=$LP_RC err='$(cat "$LP_ERR")'"
fi
# The result file must be removed after parse.
if [ ! -f "$TMP/lp-result.txt" ]; then
  pass "6  land-pr parse rm -f's the result file after reading"
else
  fail "6  result-file cleanup" "result file still present"
fi

# ── Case 7: missing result file → WARN branch ──────────────────────────
run_landpr_fence 0
if [ "$LP_RC" -eq 0 ] && grep -qF 'produced no result file' "$LP_ERR"; then
  pass "7  missing result file → WARN 'produced no result file'"
else
  fail "7  missing-file WARN" "rc=$LP_RC err='$(cat "$LP_ERR")'"
fi

# ── Case 8: COMMIT_MSG_SUBJECT case-stmt is keyed on draft-plan ─────────
# The literal `case "draft-plan" in` selects the draft arm; mutating the
# case head would change the subject (proven behaviorally by Case 1, but
# pin the case-key here so a SKILL.md edit that swaps the literal is caught).
if grep -qF 'case "draft-plan" in' "$COMMIT_FENCE"; then
  pass "8  commit fence's subject case keys on the literal \"draft-plan\""
else
  fail "8  subject case-key" "expected 'case \"draft-plan\" in' in commit fence"
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
