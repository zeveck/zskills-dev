#!/bin/bash
# tests/test-land-pr-rebase-rc14-parser.sh — regression test for Issue #420.
#
# PR #419 (closing #397) added pr-rebase.sh exit code 14 for
# REASON=wrong-current-branch (HEAD != $BRANCH assertion). The
# script-level guard correctly prevents the wrong-branch rebase, but
# /land-pr Step 3's result-parser previously only mapped RC 10 (-> STATUS=
# rebase-conflict) and RC 11 (-> STATUS=rebase-failed). RC 14 fell through
# to STATUS="" (empty), so the .landed marker had no status row and the
# orchestrator's result-file STATUS was empty — leaving callers ambiguous.
#
# This test has two layers (matches tests/test-land-pr-post-merge-ff.sh):
#
#   1. Anchor regression guards — grep SKILL.md for sentinel strings that
#      MUST survive future edits. Failure means the Step 3 parser prose
#      has drifted and Issue #420 may have regressed.
#
#   2. Reference-implementation harness — exercise the parser logic with
#      mocked pr-rebase.sh stdout + return codes; assert STATUS maps
#      correctly for RC 0, 10, 11, 14 (and that REASON survives).

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

# ---- Layer 1: Anchor regression guards ------------------------------
# These sentinels are the load-bearing prose of the Step 3 RC parser.
# Future edits MUST preserve them, or the Issue #420 fix has regressed.
for anchor in \
  'if [ "$REBASE_RC" -eq 10 ]; then' \
  'elif [ "$REBASE_RC" -eq 11 ]; then' \
  'elif [ "$REBASE_RC" -eq 14 ]; then' \
  'Issue #420: pr-rebase.sh exits 14 when CWD'"'"'s HEAD != $BRANCH'
do
  if ! grep -qF "$anchor" "$SKILL_FILE"; then
    fail "[anchor] SKILL.md missing Step 3 RC parser anchor: $anchor" "(Issue #420 regression)"
  else
    pass "[anchor] SKILL.md contains Step 3 RC parser anchor: $anchor"
  fi
done

# RC 14 must map to rebase-failed (NOT rebase-conflict, NOT empty).
# The mapping line lives within ~3 lines of the RC 14 guard. Verify by
# extracting the small block.
RC14_BLOCK=$(awk '
  /elif \[ "\$REBASE_RC" -eq 14 \]; then/ { found=1; print; next }
  found && /^  fi$/                       { print; exit }
  found                                    { print }
' "$SKILL_FILE")
if echo "$RC14_BLOCK" | grep -qF 'STATUS="rebase-failed"'; then
  pass "[mapping] RC 14 block sets STATUS=rebase-failed"
else
  fail "[mapping] RC 14 block STATUS" "block was: $RC14_BLOCK"
fi

# Result-file schema enumerates rebase-failed (was added pre-#420 for
# the RC 11 case; #420 reuses the same token). Sanity check.
if grep -qF 'rebase-failed' "$SKILL_FILE"; then
  pass "[schema] SKILL.md schema enumerates rebase-failed"
else
  fail "[schema] schema missing rebase-failed" "(would orphan the RC 14 mapping)"
fi

# ---- Layer 2: Reference-implementation harness ----------------------
# Run the parser as a function. We synthesize the REBASE_STDOUT/RC the
# way Step 3 does (KEY=VALUE lines + numeric exit code), then exercise
# the if/elif/elif/elif ladder. The function body MUST mirror the
# SKILL.md prose — if a future edit changes the SKILL.md ladder, this
# function will diverge and a SKILL.md-grep anchor above will catch it.
run_step3_parser() {
  # Inputs (caller sets these):
  #   REBASE_STDOUT — string with KEY=VALUE lines
  #   REBASE_RC     — numeric exit code from pr-rebase.sh
  # Outputs (echo as KEY=VALUE on stdout):
  #   STATUS, REASON, CONFLICT_FILES_LIST
  local STATUS="" REASON="" CONFLICT_FILES_LIST=""

  while IFS='=' read -r KEY VALUE; do
    case "$KEY" in
      CONFLICT_FILES_LIST) CONFLICT_FILES_LIST="$VALUE" ;;
      REASON) REASON="$VALUE" ;;
    esac
  done <<<"$REBASE_STDOUT"

  if [ "$REBASE_RC" -eq 10 ]; then
    STATUS="rebase-conflict"
  elif [ "$REBASE_RC" -eq 11 ]; then
    STATUS="rebase-failed"
  elif [ "$REBASE_RC" -eq 14 ]; then
    STATUS="rebase-failed"
  fi

  echo "STATUS=$STATUS"
  echo "REASON=$REASON"
  echo "CONFLICT_FILES_LIST=$CONFLICT_FILES_LIST"
}

# ===== Case 1: RC 0 success → STATUS empty (caller proceeds to Step 4)
REBASE_STDOUT="" REBASE_RC=0 OUT=$(run_step3_parser)
S=$(echo "$OUT" | grep '^STATUS=' | cut -d= -f2-)
if [ -z "$S" ]; then
  pass "[case1] RC 0 (success) → STATUS empty"
else
  fail "[case1] RC 0 STATUS" "expected empty got '$S'"
fi

# ===== Case 2: RC 10 conflict → STATUS=rebase-conflict, CONFLICT_FILES_LIST captured
REBASE_STDOUT=$'CONFLICT_FILES_LIST=/tmp/conflict-sidecar.txt'
REBASE_RC=10
OUT=$(run_step3_parser)
S=$(echo "$OUT" | grep '^STATUS=' | cut -d= -f2-)
C=$(echo "$OUT" | grep '^CONFLICT_FILES_LIST=' | cut -d= -f2-)
if [ "$S" = "rebase-conflict" ] && [ "$C" = "/tmp/conflict-sidecar.txt" ]; then
  pass "[case2] RC 10 → STATUS=rebase-conflict + CONFLICT_FILES_LIST captured"
else
  fail "[case2] RC 10" "STATUS='$S' CONFLICT_FILES_LIST='$C'"
fi

# ===== Case 3: RC 11 generic rebase failure → STATUS=rebase-failed, REASON captured
REBASE_STDOUT=$'REASON=abort-failed'
REBASE_RC=11
OUT=$(run_step3_parser)
S=$(echo "$OUT" | grep '^STATUS=' | cut -d= -f2-)
R=$(echo "$OUT" | grep '^REASON=' | cut -d= -f2-)
if [ "$S" = "rebase-failed" ] && [ "$R" = "abort-failed" ]; then
  pass "[case3] RC 11 → STATUS=rebase-failed + REASON captured"
else
  fail "[case3] RC 11" "STATUS='$S' REASON='$R'"
fi

# ===== Case 4: RC 14 wrong-current-branch → STATUS=rebase-failed, REASON=wrong-current-branch
# This is the Issue #420 case. Pre-fix the parser fell through to STATUS="".
REBASE_STDOUT=$'REASON=wrong-current-branch'
REBASE_RC=14
OUT=$(run_step3_parser)
S=$(echo "$OUT" | grep '^STATUS=' | cut -d= -f2-)
R=$(echo "$OUT" | grep '^REASON=' | cut -d= -f2-)
if [ "$S" = "rebase-failed" ] && [ "$R" = "wrong-current-branch" ]; then
  pass "[case4] RC 14 (wrong-current-branch) → STATUS=rebase-failed + REASON=wrong-current-branch (Issue #420)"
else
  fail "[case4] RC 14 (Issue #420)" "STATUS='$S' REASON='$R' (expected STATUS=rebase-failed REASON=wrong-current-branch)"
fi

# ===== Case 5: unknown RC (e.g., 99) → STATUS empty (explicit fall-through).
# Documents that the parser is closed on {10, 11, 14}; any new pr-rebase.sh
# exit code added in the future needs its own mapping (same pattern as #420).
REBASE_STDOUT="" REBASE_RC=99 OUT=$(run_step3_parser)
S=$(echo "$OUT" | grep '^STATUS=' | cut -d= -f2-)
if [ -z "$S" ]; then
  pass "[case5] unknown RC 99 → STATUS empty (documents closed mapping set; add new RC explicitly)"
else
  fail "[case5] unknown RC fall-through" "STATUS='$S' (expected empty)"
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
