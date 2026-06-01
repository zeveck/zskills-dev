#!/bin/bash
# tests/test-land-pr-tracking-copy.sh — regression tests for Issue #604.
#
# /land-pr Step 7c (`Copy worktree tracking markers to main`) was added to
# close the gap where /run-plan PR mode's per-phase
# step.run-plan.<id>.{implement,verify,report} markers live in the
# worktree's gitignored .zskills/tracking/ subtree and disappear when the
# worktree is removed post-merge. The hook gate (block-unsafe-project.sh
# enforce_step_verify_marker) then blocks subsequent phases' commits
# because main has .verify but no .report companion.
#
# EXTRACT-AND-RUN (SEAM_HARDENING_HIGH Phase 1 pilot): this test no longer
# carries a re-implemented copy of Step 7c. It EXTRACTS the real Step 7c
# ```bash fence out of skills/land-pr/SKILL.md via tests/lib/extract-fence.sh
# and RUNS it against tmpdir fixtures. The fence resolves COPY_MAIN_ROOT from
# `git rev-parse --git-common-dir`; we shim git (tests/lib/landpr-harness.sh
# mkshim) to point it at each fixture's own MAIN_ROOT and drop a real `.git`
# marker there so the production `.git`-existence guard passes. Mutating the
# production fence (e.g. dropping the cp -af) makes this suite FAIL — that is
# the point: the test exercises production code, not a copy.
#
# Cases:
#   a. Happy path — markers copied
#   b. Worktree subdir missing — INFO skip, no copy
#   c. PIPELINE_ID unresolvable — INFO skip, no copy
#   d. MERGE_REQUESTED=false — no-op
#   e. Pre-existing main markers overwritten (last-run-wins)
#   f. requires.* and fulfilled.* siblings also copied (not just step.*)
#   g. ZSKILLS_PIPELINE_ID overrides TRACKING_ID

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_FILE="$REPO_ROOT/skills/land-pr/SKILL.md"

# shellcheck source=tests/lib/extract-fence.sh
. "$SCRIPT_DIR/lib/extract-fence.sh"
# shellcheck source=tests/lib/landpr-harness.sh
. "$SCRIPT_DIR/lib/landpr-harness.sh"

PASS=0
FAIL=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

if [ ! -f "$SKILL_FILE" ]; then
  echo "FAIL: SKILL.md not found at $SKILL_FILE" >&2
  exit 1
fi

# ---- Anchor regression guard ----------------------------------------
# Verify SKILL.md still contains the Step 7c sentinel and key fixture
# strings so silent prose drift can't drop the step.
for anchor in \
  'Step 7c — Copy worktree tracking markers to main' \
  'COPY_PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-${TRACKING_ID:+run-plan.$TRACKING_ID}}"' \
  'cp -af "$WT_TRACK/." "$MAIN_TRACK/"' \
  'last-run-wins'
do
  if ! grep -qF "$anchor" "$SKILL_FILE"; then
    fail "[anchor] SKILL.md missing Step 7c anchor: $anchor" "(Issue #604 regression)"
  else
    pass "[anchor] SKILL.md contains Step 7c anchor: $anchor"
  fi
done

# ---- Extract the REAL Step 7c fence from production SKILL.md ---------
FIXTURE=$(mktemp -d "/tmp/land-pr-tracking-copy-test.XXXXXX")
trap 'rm -rf "$FIXTURE"' EXIT

STEP7C_FENCE="$FIXTURE/step7c.sh"
if ! extract_fence_between "$SKILL_FILE" \
      'Step 7c — Copy worktree tracking markers to main' \
      'Step 8 — Compose' 1 0 > "$STEP7C_FENCE"; then
  echo "FAIL: could not extract Step 7c fence from $SKILL_FILE" >&2
  exit 1
fi
# Sanity: the extracted fence is the real one (carries the production cp line).
if ! grep -qF 'cp -af "$WT_TRACK/." "$MAIN_TRACK/"' "$STEP7C_FENCE"; then
  echo "FAIL: extracted fence does not contain the production cp -af line" >&2
  exit 1
fi
pass "[extract] Step 7c production fence extracted from SKILL.md"

# Run the EXTRACTED production fence in a subshell with:
#   - a git shim that returns "$COPY_MAIN_ROOT/.git" for --git-common-dir,
#     so the fence resolves COPY_MAIN_ROOT to our fixture's main root;
#   - the input-prelude seeded so `set -u` does not abort on unbound vars;
#   - per-case overrides exported by the caller before invocation.
# COPY_MAIN_ROOT is passed in directly by each case (the fence's own
# git-common-dir resolution lands on the same path because the shim echoes
# "$MAIN/.git"). A real .git marker is dropped in $main so the fence's
# `.git`-existence guard passes.
run_real_step7c() {
  local wt="$1" main="$2"
  # Real .git marker so the production guard
  #   [ ! -d "$COPY_MAIN_ROOT/.git" ] && [ ! -f "$COPY_MAIN_ROOT/.git" ]
  # does not short-circuit to the WARN branch.
  mkdir -p "$main/.git"
  local shim="$FIXTURE/shim-$$-$RANDOM"
  mkshim "$shim" "$wt" "$main" "0" "gnu" "feat/x"
  (
    set +e
    set -u
    export PATH="$shim/bin:$PATH"
    # Seed inputs, then apply per-case overrides (already exported by caller).
    seed_caller_loop_inputs
    # shellcheck disable=SC1090
    . "$STEP7C_FENCE"
  )
}

# Helper: build a worktree-side tracking subdir populated with a full
# set of markers (step.*, requires.*, fulfilled.*).
seed_worktree_markers() {
  local wt="$1"
  local pid="$2"
  local subdir="$wt/.zskills/tracking/$pid"
  mkdir -p "$subdir"
  printf 'phase: 2\n' > "$subdir/step.run-plan.testplan.implement"
  printf 'phase: 3\n' > "$subdir/step.run-plan.testplan.verify"
  printf 'phase: 5\n' > "$subdir/step.run-plan.testplan.report"
  printf 'role: requires\n' > "$subdir/requires.run-plan.testplan"
  printf 'role: fulfilled\n' > "$subdir/fulfilled.run-plan.testplan"
}

# ===== Case (a): Happy path — markers copied ===========================
CASE_A_WT="$FIXTURE/case-a-wt"
CASE_A_MAIN="$FIXTURE/case-a-main"
mkdir -p "$CASE_A_MAIN"
seed_worktree_markers "$CASE_A_WT" "run-plan.testplan"
( MERGE_REQUESTED=true PR_STATE=MERGED \
  WORKTREE_PATH="$CASE_A_WT" COPY_MAIN_ROOT="$CASE_A_MAIN" \
  TRACKING_ID="testplan" \
  run_real_step7c "$CASE_A_WT" "$CASE_A_MAIN" ) >/dev/null 2>&1
A_DEST="$CASE_A_MAIN/.zskills/tracking/run-plan.testplan"
if [ -f "$A_DEST/step.run-plan.testplan.implement" ] \
   && [ -f "$A_DEST/step.run-plan.testplan.verify" ] \
   && [ -f "$A_DEST/step.run-plan.testplan.report" ]; then
  pass "[caseA] all three step.* markers copied to main"
else
  fail "[caseA] step.* markers" "ls $A_DEST: $(ls "$A_DEST" 2>&1 || echo MISSING)"
fi

# ===== Case (b): Worktree subdir missing — INFO skip, no copy =========
CASE_B_WT="$FIXTURE/case-b-wt"
CASE_B_MAIN="$FIXTURE/case-b-main"
mkdir -p "$CASE_B_WT" "$CASE_B_MAIN"  # WT exists but no .zskills/tracking/<pid>
B_DEST="$CASE_B_MAIN/.zskills/tracking/run-plan.testplan"
out_b=$( MERGE_REQUESTED=true PR_STATE=MERGED \
         WORKTREE_PATH="$CASE_B_WT" COPY_MAIN_ROOT="$CASE_B_MAIN" \
         TRACKING_ID="testplan" \
         run_real_step7c "$CASE_B_WT" "$CASE_B_MAIN" 2>&1 )
if [ ! -d "$B_DEST" ]; then
  pass "[caseB] missing worktree subdir → main subdir not created"
else
  fail "[caseB] no-copy expected" "$B_DEST exists"
fi
if echo "$out_b" | grep -qF "no worktree tracking subdir"; then
  pass "[caseB] INFO log emitted (no worktree tracking subdir)"
else
  fail "[caseB] INFO log" "out: $out_b"
fi

# ===== Case (c): PIPELINE_ID unresolvable — INFO skip =================
CASE_C_WT="$FIXTURE/case-c-wt"
CASE_C_MAIN="$FIXTURE/case-c-main"
seed_worktree_markers "$CASE_C_WT" "run-plan.testplan"
mkdir -p "$CASE_C_MAIN"
# Neither TRACKING_ID nor ZSKILLS_PIPELINE_ID set → COPY_PIPELINE_ID empty.
out_c=$( MERGE_REQUESTED=true PR_STATE=MERGED \
         WORKTREE_PATH="$CASE_C_WT" COPY_MAIN_ROOT="$CASE_C_MAIN" \
         TRACKING_ID="" ZSKILLS_PIPELINE_ID="" \
         run_real_step7c "$CASE_C_WT" "$CASE_C_MAIN" 2>&1 )
if [ ! -d "$CASE_C_MAIN/.zskills" ]; then
  pass "[caseC] empty PIPELINE_ID → no main .zskills dir created"
else
  fail "[caseC] no-copy expected" ".zskills exists in $CASE_C_MAIN"
fi
if echo "$out_c" | grep -qF "no PIPELINE_ID resolvable"; then
  pass "[caseC] INFO log emitted (no PIPELINE_ID resolvable)"
else
  fail "[caseC] INFO log" "out: $out_c"
fi

# ===== Case (d): MERGE_REQUESTED=false — no-op =========================
CASE_D_WT="$FIXTURE/case-d-wt"
CASE_D_MAIN="$FIXTURE/case-d-main"
seed_worktree_markers "$CASE_D_WT" "run-plan.testplan"
mkdir -p "$CASE_D_MAIN"
( MERGE_REQUESTED=false PR_STATE=OPEN \
  WORKTREE_PATH="$CASE_D_WT" COPY_MAIN_ROOT="$CASE_D_MAIN" \
  TRACKING_ID="testplan" \
  run_real_step7c "$CASE_D_WT" "$CASE_D_MAIN" ) >/dev/null 2>&1
if [ ! -d "$CASE_D_MAIN/.zskills" ]; then
  pass "[caseD] MERGE_REQUESTED=false → no copy attempted"
else
  fail "[caseD] no-op expected" ".zskills exists in $CASE_D_MAIN"
fi

# ===== Case (e): Pre-existing main markers overwritten (last-run-wins) ==
CASE_E_WT="$FIXTURE/case-e-wt"
CASE_E_MAIN="$FIXTURE/case-e-main"
seed_worktree_markers "$CASE_E_WT" "run-plan.testplan"
# Pre-seed main with STALE content for one marker.
E_MAIN_SUBDIR="$CASE_E_MAIN/.zskills/tracking/run-plan.testplan"
mkdir -p "$E_MAIN_SUBDIR"
printf 'STALE\n' > "$E_MAIN_SUBDIR/step.run-plan.testplan.verify"
( MERGE_REQUESTED=true PR_STATE=MERGED \
  WORKTREE_PATH="$CASE_E_WT" COPY_MAIN_ROOT="$CASE_E_MAIN" \
  TRACKING_ID="testplan" \
  run_real_step7c "$CASE_E_WT" "$CASE_E_MAIN" ) >/dev/null 2>&1
if grep -qF "phase: 3" "$E_MAIN_SUBDIR/step.run-plan.testplan.verify"; then
  pass "[caseE] stale main marker overwritten by fresh worktree content"
else
  fail "[caseE] last-run-wins" "content: $(cat "$E_MAIN_SUBDIR/step.run-plan.testplan.verify" 2>&1)"
fi

# ===== Case (f): requires.* and fulfilled.* siblings also copied =======
CASE_F_WT="$FIXTURE/case-f-wt"
CASE_F_MAIN="$FIXTURE/case-f-main"
seed_worktree_markers "$CASE_F_WT" "run-plan.testplan"
mkdir -p "$CASE_F_MAIN"
( MERGE_REQUESTED=true PR_STATE=MERGED \
  WORKTREE_PATH="$CASE_F_WT" COPY_MAIN_ROOT="$CASE_F_MAIN" \
  TRACKING_ID="testplan" \
  run_real_step7c "$CASE_F_WT" "$CASE_F_MAIN" ) >/dev/null 2>&1
F_DEST="$CASE_F_MAIN/.zskills/tracking/run-plan.testplan"
if [ -f "$F_DEST/requires.run-plan.testplan" ] \
   && [ -f "$F_DEST/fulfilled.run-plan.testplan" ]; then
  pass "[caseF] requires.* and fulfilled.* siblings copied alongside step.*"
else
  fail "[caseF] siblings copy" "ls $F_DEST: $(ls "$F_DEST" 2>&1)"
fi

# ===== Case (g): ZSKILLS_PIPELINE_ID overrides TRACKING_ID =============
CASE_G_WT="$FIXTURE/case-g-wt"
CASE_G_MAIN="$FIXTURE/case-g-main"
seed_worktree_markers "$CASE_G_WT" "custom.pipeline.id"
mkdir -p "$CASE_G_MAIN"
( MERGE_REQUESTED=true PR_STATE=MERGED \
  WORKTREE_PATH="$CASE_G_WT" COPY_MAIN_ROOT="$CASE_G_MAIN" \
  TRACKING_ID="something-else" ZSKILLS_PIPELINE_ID="custom.pipeline.id" \
  run_real_step7c "$CASE_G_WT" "$CASE_G_MAIN" ) >/dev/null 2>&1
if [ -f "$CASE_G_MAIN/.zskills/tracking/custom.pipeline.id/step.run-plan.testplan.implement" ]; then
  pass "[caseG] ZSKILLS_PIPELINE_ID takes precedence over TRACKING_ID"
else
  fail "[caseG] env override" "ls $CASE_G_MAIN/.zskills/tracking: $(ls "$CASE_G_MAIN/.zskills/tracking" 2>&1)"
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
