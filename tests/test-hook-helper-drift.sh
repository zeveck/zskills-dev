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
for HOOK in hooks/block-unsafe-project.sh.template hooks/block-unsafe-generic.sh hooks/block-stale-skill-version.sh; do
  # Helper coverage per hook (which inlined helpers are present in each):
  #   project hook            : is_git_subcommand,                  is_git_subcommand_in_chain
  #   generic hook            : is_git_subcommand, is_destruct_command,
  #                             is_git_subcommand_in_chain, is_destruct_command_in_chain
  #   stale-skill-version hook: is_git_subcommand
  for FN in is_git_subcommand is_destruct_command is_git_subcommand_in_chain is_destruct_command_in_chain; do
    # is_destruct_command is only inlined in generic hook; skip for project + stale-skill-version.
    [[ "$FN" == "is_destruct_command" && "$HOOK" == *project* ]] && continue
    [[ "$FN" == "is_destruct_command" && "$HOOK" == *stale-skill-version* ]] && continue
    # Chain wrappers are only inlined in the two block-unsafe hooks.
    # Skip stale-skill-version (no chain wrapper needed — that hook's
    # callers operate on the redacted single-segment COMMAND already).
    [[ "$FN" == "is_git_subcommand_in_chain" && "$HOOK" == *stale-skill-version* ]] && continue
    # is_destruct_command_in_chain is only inlined in the generic hook.
    [[ "$FN" == "is_destruct_command_in_chain" && "$HOOK" == *project* ]] && continue
    [[ "$FN" == "is_destruct_command_in_chain" && "$HOOK" == *stale-skill-version* ]] && continue
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
