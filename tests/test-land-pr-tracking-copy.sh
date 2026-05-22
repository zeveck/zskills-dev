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
# This test extracts the Step 7c block from SKILL.md (by anchor
# verification) and runs a reference implementation against tmpdir
# fixtures. Failure here means SKILL.md drifted from the reference
# implementation and Issue #604 may have regressed.
#
# Cases:
#   a. Happy path — markers copied
#   b. Worktree subdir missing — INFO skip, no copy
#   c. PIPELINE_ID unresolvable — INFO skip, no copy
#   d. MERGE_REQUESTED=false — no-op
#   e. Pre-existing main markers overwritten (last-run-wins)
#   f. requires.* and fulfilled.* siblings also copied (not just step.*)

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

# ---- Reference implementation (must mirror SKILL.md Step 7c) --------
# Run as a function so each case can supply its own env. Stderr is
# captured per call so we can assert on the WARN/INFO messages.
# COPY_MAIN_ROOT is passed in directly by the test (the SKILL.md block
# resolves it from git-common-dir, but each fixture sets up its own
# layout — same shape, same behavior).
run_copy_block() {
  : "${BRANCH_SLUG:=test}"
  if [ "$MERGE_REQUESTED" = "true" ] && [ "$PR_STATE" = "MERGED" ] && [ -n "$WORKTREE_PATH" ]; then
    local COPY_PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-${TRACKING_ID:+run-plan.$TRACKING_ID}}"
    # In production the block re-resolves COPY_MAIN_ROOT from git-common-dir;
    # for the test we accept a pre-set COPY_MAIN_ROOT env override so each
    # case can point at its own tmpdir without needing a real git repo.
    if [ -z "$COPY_PIPELINE_ID" ]; then
      echo "INFO: /land-pr Step 7c: no PIPELINE_ID resolvable (no --tracking-id and no ZSKILLS_PIPELINE_ID); skipping tracking copy"
    elif [ -z "$COPY_MAIN_ROOT" ]; then
      echo "WARN: /land-pr Step 7c: could not resolve MAIN_ROOT; skipping tracking copy" >&2
    else
      local WT_TRACK="$WORKTREE_PATH/.zskills/tracking/$COPY_PIPELINE_ID"
      local MAIN_TRACK="$COPY_MAIN_ROOT/.zskills/tracking/$COPY_PIPELINE_ID"
      if [ -d "$WT_TRACK" ]; then
        mkdir -p "$MAIN_TRACK"
        local CP_STDERR="/tmp/land-pr-tracking-copy-stderr-$BRANCH_SLUG-$$.log"
        if cp -af "$WT_TRACK/." "$MAIN_TRACK/" 2>"$CP_STDERR"; then
          echo "INFO: /land-pr Step 7c: copied $WT_TRACK/. → $MAIN_TRACK/ (last-run-wins)"
          rm -f "$CP_STDERR"
        else
          echo "WARN: /land-pr Step 7c: cp -af failed (see $CP_STDERR); tracking markers not fully copied" >&2
        fi
      else
        echo "INFO: /land-pr Step 7c: no worktree tracking subdir at $WT_TRACK; skipping copy"
      fi
    fi
  fi
}

# ---- Fixture setup --------------------------------------------------
FIXTURE=$(mktemp -d "/tmp/land-pr-tracking-copy-test.XXXXXX")
trap 'rm -rf "$FIXTURE"' EXIT

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
  TRACKING_ID="testplan" run_copy_block ) >/dev/null 2>&1
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
stderr_b=$( MERGE_REQUESTED=true PR_STATE=MERGED \
            WORKTREE_PATH="$CASE_B_WT" COPY_MAIN_ROOT="$CASE_B_MAIN" \
            TRACKING_ID="testplan" run_copy_block 2>&1 1>/dev/null )
B_DEST="$CASE_B_MAIN/.zskills/tracking/run-plan.testplan"
# stdout INFO is captured to stdout, not stderr; we accept either path.
out_b=$( MERGE_REQUESTED=true PR_STATE=MERGED \
         WORKTREE_PATH="$CASE_B_WT" COPY_MAIN_ROOT="$CASE_B_MAIN" \
         TRACKING_ID="testplan" run_copy_block 2>&1 )
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
         TRACKING_ID="" ZSKILLS_PIPELINE_ID="" run_copy_block 2>&1 )
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
  TRACKING_ID="testplan" run_copy_block ) >/dev/null 2>&1
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
  TRACKING_ID="testplan" run_copy_block ) >/dev/null 2>&1
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
  TRACKING_ID="testplan" run_copy_block ) >/dev/null 2>&1
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
  run_copy_block ) >/dev/null 2>&1
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
