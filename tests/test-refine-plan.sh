#!/bin/bash
# tests/test-refine-plan.sh — extract-and-run the REAL /refine-plan Phase-5
# commit + /land-pr fences, the post-write tracking marker lifecycle, and the
# new `## Argument parser` fence.
#
# SEAM_HARDENING_HIGH Phase 5. No suite exercised /refine-plan before; its
# Phase-5 worktree-commit + land-pr-result-parse fences were green-by-absence
# (multiple exit-1 guards untested). This is the refine-plan twin of
# tests/test-draft-plan-phase6-fences.sh.
#
# Per-skill indent asymmetry (M4): refine-plan's commit fence is FLUSH-LEFT
# (column-0 body) → extracted with strip-indent=0, UNLIKE draft-plan's
# 3-space-indented fence. The commit subject drives through a SHARED
# `case "refine-plan" in` block → asserting the subject runs the real case.
#
# The `## Argument parser` fence is the Phase-5 structural edit's product: it
# consolidates plan-file / `rounds N` / `auto` / guidance parsing (previously
# split between the preamble loop and prose) into one extractable fence. We
# extract-and-run it across the documented Examples.
#
# Mutating any production fence (drop the staged-set guard, the out-of-tree
# guard, an allow-list key, the refine-plan case-arm, the auto regex) makes
# assertions here FAIL.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/skills/refine-plan/SKILL.md"

# shellcheck source=tests/lib/extract-fence.sh
. "$SCRIPT_DIR/lib/extract-fence.sh"

PASS=0
FAIL=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

if [ ! -f "$SKILL" ]; then
  echo "FAIL: refine-plan SKILL.md not found at $SKILL" >&2
  exit 1
fi

echo "=== refine-plan Phase-5 fences + arg-parser — extract-and-run (Phase 5) ==="

TMP=$(mktemp -d "/tmp/refine-plan-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

# ── Extract the commit fence (FLUSH-LEFT → strip-indent=0) ──────────────
COMMIT_FENCE="$TMP/commit-fence.sh"
if ! extract_fence_between "$SKILL" \
      '^### Auto-commit the plan file' \
      '^### Auto-land via' 1 0 > "$COMMIT_FENCE"; then
  echo "FAIL: could not extract Phase-5 commit fence from $SKILL" >&2
  exit 1
fi
if grep -qF 'TOPLEVEL=$(git rev-parse --show-toplevel)' "$COMMIT_FENCE" \
   && grep -qF '"$MAIN_ROOT"/*) PLAN_FILE="$TOPLEVEL/${PLAN_FILE#"$MAIN_ROOT/"}" ;;' "$COMMIT_FENCE" \
   && grep -qF 'refine-plan) COMMIT_MSG_SUBJECT="docs(plans): refine $BASE" ;;' "$COMMIT_FENCE" \
   && grep -qF 'unexpected staged set' "$COMMIT_FENCE" \
   && grep -qF 'is outside worktree' "$COMMIT_FENCE"; then
  pass "[extract] commit fence carries remap / refine-case / staged-guard / out-of-tree landmarks"
else
  fail "[extract] commit fence landmarks" "missing remap/refine-case/staged/out-of-tree landmark"
fi
# FLUSH-LEFT: the MAIN_ROOT line is already at column 0 with strip-indent=0.
if grep -qE '^MAIN_ROOT=\$\(cd ' "$COMMIT_FENCE"; then
  pass "[extract] flush-left fence extracted at column 0 with strip-indent=0"
else
  fail "[extract] flush-left" "MAIN_ROOT= not at column 0"
fi

# ── Extract the land-pr fence (column-0 → strip-indent=0) ───────────────
LANDPR_FENCE="$TMP/landpr-fence.sh"
if ! extract_fence_between "$SKILL" \
      '^### Auto-land via' \
      '^### Post-write tracking' 1 0 > "$LANDPR_FENCE"; then
  echo "FAIL: could not extract Phase-5 land-pr fence from $SKILL" >&2
  exit 1
fi
if grep -qF 'STATUS|PR_URL|PR_NUMBER|CI_STATUS|PR_STATE|REASON)' "$LANDPR_FENCE" \
   && grep -qF '*) ;;  # unknown keys ignored (forward-compat)' "$LANDPR_FENCE" \
   && grep -qF 'produced no result file' "$LANDPR_FENCE"; then
  pass "[extract] land-pr fence carries allow-list / unknown-key / no-result-file landmarks"
else
  fail "[extract] land-pr fence landmarks" "missing allow-list/unknown-key/no-result landmark"
fi

# ── Extract the post-write tracking fence (column-0) ────────────────────
TRACK_FENCE="$TMP/track-fence.sh"
if ! extract_fence_between "$SKILL" \
      '^### Post-write tracking' \
      '^### Present the result' 1 0 > "$TRACK_FENCE"; then
  echo "FAIL: could not extract post-write tracking fence from $SKILL" >&2
  exit 1
fi

# ── Real git sandbox: main repo + worktree ──────────────────────────────
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
( cd "$MAIN" && git worktree add -q -b feat/refineplan-test "$WT" ) \
  || { echo "FAIL: git worktree add" >&2; exit 1; }

# Hermetic config stubs (the fences source zskills-{paths,resolve-config}.sh).
FAKE_PROJECT="$TMP/fake"
mkdir -p "$FAKE_PROJECT/.claude/skills/update-zskills/scripts"
: > "$FAKE_PROJECT/.claude/skills/update-zskills/scripts/zskills-paths.sh"
cat > "$FAKE_PROJECT/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh" <<'EOF'
COMMIT_CO_AUTHOR=""
TIMEZONE="UTC"
EOF

# run_commit_fence — drive the EXTRACTED commit fence. Input: PLAN_FILE.
run_commit_fence() {
  local plan_file="$1"
  RC_ERR="$TMP/commit.stderr"; : > "$RC_ERR"
  RC_OUT=$( exec 2>"$RC_ERR"
    set +e
    set -u
    export CLAUDE_PROJECT_DIR="$FAKE_PROJECT"
    unset CLAUDE_PLUGIN_ROOT
    cd "$WT"
    WT_PATH="$WT"
    PLAN_FILE="$plan_file"
    # shellcheck disable=SC1090
    . "$COMMIT_FENCE"
    printf 'SUBJECT=%s\n' "${COMMIT_MSG_SUBJECT:-<unset>}"
    printf 'FILE_REL=%s\n' "${FILE_REL:-<unset>}"
  )
  RC_RC=$?
}
val() { printf '%s\n' "$2" | sed -n "s/^$1=//p" | head -1; }

# ── Case 1: subject is `docs(plans): refine <base>` (shared case-stmt) ──
mkdir -p "$WT/plans"
echo "# plan" > "$WT/plans/EXECUTION_MODES.md"
run_commit_fence "$MAIN/plans/EXECUTION_MODES.md"   # MAIN-anchored → remapped
if [ "$RC_RC" -eq 0 ] \
   && [ "$(val SUBJECT "$RC_OUT")" = "docs(plans): refine EXECUTION_MODES" ] \
   && [ "$(val FILE_REL "$RC_OUT")" = "plans/EXECUTION_MODES.md" ] \
   && git -C "$WT" log -1 --pretty=%s | grep -qxF "docs(plans): refine EXECUTION_MODES"; then
  pass "1  COMMIT_MSG_SUBJECT = 'docs(plans): refine EXECUTION_MODES' (shared case \"refine-plan\"), remap+commit"
else
  fail "1  subject/remap" "rc=$RC_RC subject='$(val SUBJECT "$RC_OUT")' file_rel='$(val FILE_REL "$RC_OUT")' err='$(cat "$RC_ERR")'"
fi

# ── Case 2: escaping `../*` path → exit 1 (out-of-tree guard) ───────────
echo x > "$TMP/OUTSIDE.md"
run_commit_fence "$TMP/OUTSIDE.md"
if [ "$RC_RC" -eq 1 ] && grep -qF 'is outside worktree' "$RC_ERR"; then
  pass "2  escaping ../* PLAN_FILE → exit 1 'is outside worktree'"
else
  fail "2  out-of-tree guard" "rc=$RC_RC err='$(cat "$RC_ERR")'"
fi

# ── Case 3: unexpected (two-file) staged set → exit 1 ───────────────────
echo "# plan2" > "$WT/plans/SECOND.md"
echo extra > "$WT/extra.txt"
git -C "$WT" add extra.txt
run_commit_fence "$WT/plans/SECOND.md"
if [ "$RC_RC" -eq 1 ] && grep -qF 'unexpected staged set' "$RC_ERR"; then
  pass "3  two-file staged set → exit 1 'unexpected staged set'"
else
  fail "3  staged-set guard" "rc=$RC_RC err='$(cat "$RC_ERR")'"
fi
git -C "$WT" reset -q || true

# ── land-pr result-parse fence ──────────────────────────────────────────
LANDPR_PATCHED="$TMP/landpr-patched.sh"
sed 's#RESULT_FILE="/tmp/land-pr-result-refine-plan-\${SLUG}-\$\$.txt"#RESULT_FILE="$PREPARED_RESULT_FILE"#' \
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
    PLAN_FILE="$WT/plans/EXECUTION_MODES.md"
    TRACKING_ID="execution-modes"
    ROUND=2
    PREPARED_RESULT_FILE="$rf"
    # shellcheck disable=SC1090
    . "$LANDPR_PATCHED"
  )
  LP_RC=$?
}

# ── Case 4: allow-list parse — known parsed, unknown ignored, file rm'd ─
run_landpr_fence 1 STATUS=created PR_URL=http://x/9 CI_STATUS=pass \
  GIZMO=ignored PR_STATE=OPEN
if [ "$LP_RC" -eq 0 ] \
   && grep -qF 'STATUS=created CI_STATUS=pass PR=http://x/9' "$LP_ERR" \
   && [ ! -f "$TMP/lp-result.txt" ]; then
  pass "4  land-pr allow-list parse: known keys parsed, unknown (GIZMO) ignored, result rm'd"
else
  fail "4  land-pr allow-list" "rc=$LP_RC err='$(cat "$LP_ERR")' result-present=$([ -f "$TMP/lp-result.txt" ] && echo yes || echo no)"
fi

# ── Case 5: missing result file → WARN ──────────────────────────────────
run_landpr_fence 0
if [ "$LP_RC" -eq 0 ] && grep -qF 'produced no result file' "$LP_ERR"; then
  pass "5  missing result file → WARN 'produced no result file'"
else
  fail "5  missing-file WARN" "rc=$LP_RC err='$(cat "$LP_ERR")'"
fi

# ── Case 6: marker lifecycle — step + fulfilled markers written ─────────
# The post-write tracking fence writes step.refine-plan.<id>.finalize and
# fulfilled.refine-plan.<id> under .zskills/tracking/<pipeline>/.
ML_ERR="$TMP/ml.stderr"; : > "$ML_ERR"
( exec 2>"$ML_ERR"
  set +e
  set -u
  export CLAUDE_PROJECT_DIR="$FAKE_PROJECT"
  unset CLAUDE_PLUGIN_ROOT ZSKILLS_PIPELINE_ID
  export ZSKILLS_SKILLS_ROOT="$REPO_ROOT/skills"
  cd "$WT"
  TRACKING_ID="execution-modes"
  PLAN_FILE="$WT/plans/EXECUTION_MODES.md"
  # The production fence writes into an existing per-pipeline subdir (the
  # caller's earlier tracking-fulfillment fence creates it). Pre-create it,
  # mirroring that contract.
  mkdir -p "$MAIN/.zskills/tracking/refine-plan.execution-modes"
  # shellcheck disable=SC1090
  . "$TRACK_FENCE"
)
STEP="$MAIN/.zskills/tracking/refine-plan.execution-modes/step.refine-plan.execution-modes.finalize"
FULF="$MAIN/.zskills/tracking/refine-plan.execution-modes/fulfilled.refine-plan.execution-modes"
if [ -f "$STEP" ] && [ -f "$FULF" ] \
   && grep -qF 'status: complete' "$FULF" \
   && grep -qF 'skill: refine-plan' "$FULF"; then
  pass "6  post-write tracking writes step.finalize + fulfilled (status: complete)"
else
  fail "6  marker lifecycle" "step=$([ -f "$STEP" ] && echo y || echo n) fulfilled=$([ -f "$FULF" ] && echo y || echo n) err='$(cat "$ML_ERR")'"
fi

# ── Argument parser fence ───────────────────────────────────────────────
ARGP_FENCE="$TMP/argp-fence.sh"
if ! extract_fence_between "$SKILL" \
      '^## Argument parser$' \
      '^Examples:$' 1 0 > "$ARGP_FENCE"; then
  echo "FAIL: could not extract Argument parser fence from $SKILL" >&2
  exit 1
fi
if grep -qF 'AUTO_FLAG=1' "$ARGP_FENCE" \
   && grep -qF 'ROUNDS_MAX="$tok"' "$ARGP_FENCE" \
   && grep -qF 'GUIDANCE' "$ARGP_FENCE"; then
  pass "[extract] arg-parser fence carries AUTO_FLAG / ROUNDS_MAX / GUIDANCE landmarks"
else
  fail "[extract] arg-parser landmarks" "missing AUTO_FLAG/ROUNDS_MAX/GUIDANCE"
fi

# argp — run the EXTRACTED arg-parser fence with $ARGUMENTS set; echo outputs.
argp() { # $1 = ARGUMENTS
  ( set +e; set -u
    ZSKILLS_PLANS_DIR="plans"
    ARGUMENTS="$1"
    unset PLAN_FILE 2>/dev/null || true
    # shellcheck disable=SC1090
    . "$ARGP_FENCE"
    printf 'PLAN_FILE=%s|ROUNDS_MAX=%s|AUTO_FLAG=%s|GUIDANCE=%s\n' \
      "${PLAN_FILE:-}" "$ROUNDS_MAX" "$AUTO_FLAG" "$GUIDANCE" )
}
assert_argp() { # $1 label  $2 ARGUMENTS  $3 expected
  local got; got=$(argp "$2")
  if [ "$got" = "$3" ]; then
    pass "$1"
  else
    fail "$1" "got='$got' want='$3'"
  fi
}

# Plan-file resolution: bare *.md resolves via $ZSKILLS_PLANS_DIR; pathed as-is.
assert_argp "7  bare *.md → \$ZSKILLS_PLANS_DIR/, default 2 rounds" \
  "THERMAL_PLAN.md" \
  "PLAN_FILE=plans/THERMAL_PLAN.md|ROUNDS_MAX=2|AUTO_FLAG=0|GUIDANCE="
assert_argp "8  pathed plan file used as-is" \
  "plans/EXECUTION_MODES.md" \
  "PLAN_FILE=plans/EXECUTION_MODES.md|ROUNDS_MAX=2|AUTO_FLAG=0|GUIDANCE="
# rounds N: consumed, sets ROUNDS_MAX.
assert_argp "9  rounds N sets ROUNDS_MAX, consumed (not guidance)" \
  "plans/EXECUTION_MODES.md rounds 3" \
  "PLAN_FILE=plans/EXECUTION_MODES.md|ROUNDS_MAX=3|AUTO_FLAG=0|GUIDANCE="
# rounds before plan-file (Arguments example).
assert_argp "10 rounds N before plan file → plan file still detected, 2 rounds" \
  "rounds 2 plans/FEATURE.md" \
  "PLAN_FILE=plans/FEATURE.md|ROUNDS_MAX=2|AUTO_FLAG=0|GUIDANCE="
# auto: whitespace-anchored, case-insensitive, consumed.
assert_argp "11 auto sets AUTO_FLAG=1, consumed (not guidance)" \
  "plans/FOO.md auto" \
  "PLAN_FILE=plans/FOO.md|ROUNDS_MAX=2|AUTO_FLAG=1|GUIDANCE="
assert_argp "12 AUTO (uppercase) → AUTO_FLAG=1" \
  "plans/FOO.md AUTO rounds 2" \
  "PLAN_FILE=plans/FOO.md|ROUNDS_MAX=2|AUTO_FLAG=1|GUIDANCE="
# guidance tail joins remaining tokens.
assert_argp "13 guidance tail joined with spaces, plan/rounds/auto consumed" \
  "plans/X.md auto rounds 5 deepen the convergence checks" \
  "PLAN_FILE=plans/X.md|ROUNDS_MAX=5|AUTO_FLAG=1|GUIDANCE=deepen the convergence checks"
# `rounds` NOT followed by a number is guidance, not the keyword.
assert_argp "14 rounds-without-number is guidance (default 2 rounds)" \
  "plans/FOO.md rounds notanumber here" \
  "PLAN_FILE=plans/FOO.md|ROUNDS_MAX=2|AUTO_FLAG=0|GUIDANCE=rounds notanumber here"
# trailing bare `rounds` is guidance.
assert_argp "15 trailing bare rounds is guidance" \
  "plans/FOO.md rounds" \
  "PLAN_FILE=plans/FOO.md|ROUNDS_MAX=2|AUTO_FLAG=0|GUIDANCE=rounds"

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
