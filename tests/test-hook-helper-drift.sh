#!/bin/bash
# tests/test-hook-helper-drift.sh — assert inlined helpers in
# hooks/block-unsafe-*.sh* are byte-identical to hooks/_lib/git-tokenwalk.sh.
# CI gate per D7. Plan B's hook is added here as an additional consumer
# in Phase 6 (or via /refine-plan if Plan B is still pending).
#
# Round-2 R2-M-2 fix: tests/test-helpers.sh does NOT exist in this repo
# (verified empirically). Define pass/fail inline mirroring the
# tests/test-hooks.sh:12-22 pattern. Do NOT add a new repo-level helpers
# file in this plan — Phase 5.4's commit boundary excludes it.
set -e
PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS $*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo "FAIL $*"; FAIL_COUNT=$((FAIL_COUNT+1)); }
for HOOK in hooks/block-unsafe-project.sh.template hooks/block-unsafe-generic.sh; do
  for FN in is_git_subcommand is_destruct_command; do
    # is_destruct_command is only inlined in generic hook; skip for project.
    [[ "$FN" == "is_destruct_command" && "$HOOK" == *project* ]] && continue
    if diff <(sed -n "/^$FN()/,/^}$/p" "$HOOK") \
            <(sed -n "/^$FN()/,/^}$/p" hooks/_lib/git-tokenwalk.sh) \
            > /dev/null; then
      pass "drift: $HOOK $FN matches source-of-truth"
    else
      fail "drift: $HOOK $FN drifted from hooks/_lib/git-tokenwalk.sh"
    fi
  done
done

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
exit $FAIL_COUNT
