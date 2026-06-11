#!/bin/bash
# tests/test-hook-helper-drift.sh — assert inlined helpers in
# hooks/block-unsafe-*.sh* are byte-identical to their source-of-truth bodies
# under hooks/_lib/. CI gate per D7. Plan B's hook is added here as an
# additional consumer in Phase 6 (or via /refine-plan if Plan B is still
# pending).
#
# Round-2 R2-M-2 fix: tests/test-helpers.sh does NOT exist in this repo
# (verified empirically). Define pass/fail inline mirroring the
# tests/test-hooks.sh:12-22 pattern. Do NOT add a new repo-level helpers
# file in this plan — Phase 5.4's commit boundary excludes it.
#
# Source-of-truth files (iterated; sed extracts the function body from each):
#   hooks/_lib/git-tokenwalk.sh
#     - is_git_subcommand, is_destruct_command,
#       is_git_subcommand_in_chain, is_destruct_command_in_chain,
#       is_gh_pr_subcommand, is_gh_pr_subcommand_in_chain,
#       is_gh_pr_subcommand_in_wrappers
#   hooks/_lib/resolve-effective-worktree-root.sh (#401)
#     - extract_cd_target, resolve_effective_worktree_root
set -e
PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS $*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo "FAIL $*"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# Map each inlined function name to its source-of-truth file under hooks/_lib/.
# When a new helper joins hooks/_lib/, add it here.
fn_source() {
  case "$1" in
    is_git_subcommand|is_destruct_command|is_git_subcommand_in_chain|is_destruct_command_in_chain|is_destruct_command_in_wrappers|is_git_subcommand_in_wrappers|is_gh_pr_subcommand|is_gh_pr_subcommand_in_chain|is_gh_pr_subcommand_in_wrappers)
      echo "hooks/_lib/git-tokenwalk.sh" ;;
    extract_cd_target|resolve_effective_worktree_root)
      echo "hooks/_lib/resolve-effective-worktree-root.sh" ;;
    zskills_resolve_python)
      echo "hooks/_lib/resolve-python.sh" ;;
    zskills_normalize_tool_path)
      echo "hooks/_lib/normalize-tool-path.sh" ;;
    *)
      echo "" ;;
  esac
}

for HOOK in hooks/block-unsafe-project.sh.template hooks/block-unsafe-generic.sh hooks/block-stale-skill-version.sh hooks/block-bypassed-land-pr.sh; do
  # Helper coverage per hook (which inlined helpers are present in each):
  #   project hook              : is_git_subcommand, is_git_subcommand_in_chain,
  #                               is_git_subcommand_in_wrappers,
  #                               extract_cd_target, resolve_effective_worktree_root
  #   generic hook              : is_git_subcommand, is_destruct_command,
  #                               is_git_subcommand_in_chain, is_destruct_command_in_chain,
  #                               is_git_subcommand_in_wrappers
  #   stale-skill-version hook  : is_git_subcommand, is_git_subcommand_in_chain,
  #                               is_git_subcommand_in_wrappers,
  #                               extract_cd_target, resolve_effective_worktree_root
  #   block-bypassed-land-pr.sh : is_gh_pr_subcommand, is_gh_pr_subcommand_in_chain,
  #                               is_gh_pr_subcommand_in_wrappers
  #     (Plan LAND_PR_BYPASS_HARDENING Phase 4 — 4th drift-gated hook)
  # is_git_subcommand_in_wrappers added in #399 — git-side closure of the
  # bash -c / eval / sh -c wrapper-bypass class.
  # extract_cd_target + resolve_effective_worktree_root added in #401 —
  # consolidated cd-target / worktree-root resolution helper.
  for FN in is_git_subcommand is_destruct_command is_git_subcommand_in_chain is_destruct_command_in_chain is_destruct_command_in_wrappers is_git_subcommand_in_wrappers is_gh_pr_subcommand is_gh_pr_subcommand_in_chain is_gh_pr_subcommand_in_wrappers extract_cd_target resolve_effective_worktree_root; do
    # is_destruct_command is only inlined in generic hook; skip for project + stale-skill-version + bypassed-land-pr.
    [[ "$FN" == "is_destruct_command" && "$HOOK" == *project* ]] && continue
    [[ "$FN" == "is_destruct_command" && "$HOOK" == *stale-skill-version* ]] && continue
    [[ "$FN" == "is_destruct_command" && "$HOOK" == *bypassed-land-pr* ]] && continue
    # Chain wrappers: now also inlined in stale-skill-version (#393's fix —
    # cd-chained `cd /tmp/wt && git commit` must match for worktree commits).
    # bypassed-land-pr still skips (uses gh-pr chain walker, not git).
    [[ "$FN" == "is_git_subcommand_in_chain" && "$HOOK" == *bypassed-land-pr* ]] && continue
    # is_git_subcommand_in_wrappers (#399): inlined in the three git-side
    # hooks; bypassed-land-pr uses the gh-pr equivalent so skip.
    [[ "$FN" == "is_git_subcommand_in_wrappers" && "$HOOK" == *bypassed-land-pr* ]] && continue
    # is_destruct_command_in_chain is only inlined in the generic hook.
    [[ "$FN" == "is_destruct_command_in_chain" && "$HOOK" == *project* ]] && continue
    [[ "$FN" == "is_destruct_command_in_chain" && "$HOOK" == *stale-skill-version* ]] && continue
    [[ "$FN" == "is_destruct_command_in_chain" && "$HOOK" == *bypassed-land-pr* ]] && continue
    # is_destruct_command_in_wrappers (#586) is only inlined in the generic
    # hook (same scope as the destruct-base + destruct-chain helpers).
    [[ "$FN" == "is_destruct_command_in_wrappers" && "$HOOK" == *project* ]] && continue
    [[ "$FN" == "is_destruct_command_in_wrappers" && "$HOOK" == *stale-skill-version* ]] && continue
    [[ "$FN" == "is_destruct_command_in_wrappers" && "$HOOK" == *bypassed-land-pr* ]] && continue
    # is_git_subcommand is NOT inlined in bypassed-land-pr (that hook only
    # walks gh pr tokens, not git tokens).
    [[ "$FN" == "is_git_subcommand" && "$HOOK" == *bypassed-land-pr* ]] && continue
    # is_gh_pr_subcommand{,_in_chain,_in_wrappers} are ONLY inlined in bypassed-land-pr.
    [[ "$FN" == "is_gh_pr_subcommand" && "$HOOK" != *bypassed-land-pr* ]] && continue
    [[ "$FN" == "is_gh_pr_subcommand_in_chain" && "$HOOK" != *bypassed-land-pr* ]] && continue
    [[ "$FN" == "is_gh_pr_subcommand_in_wrappers" && "$HOOK" != *bypassed-land-pr* ]] && continue
    # Worktree-root resolvers (#401): inlined ONLY in project and
    # stale-skill-version hooks. Skip for generic and bypassed-land-pr
    # (neither needs to act on the agent's worktree root).
    [[ "$FN" == "extract_cd_target" && "$HOOK" == *unsafe-generic* ]] && continue
    [[ "$FN" == "extract_cd_target" && "$HOOK" == *bypassed-land-pr* ]] && continue
    [[ "$FN" == "resolve_effective_worktree_root" && "$HOOK" == *unsafe-generic* ]] && continue
    [[ "$FN" == "resolve_effective_worktree_root" && "$HOOK" == *bypassed-land-pr* ]] && continue
    SRC="$(fn_source "$FN")"
    if [ -z "$SRC" ] || [ ! -f "$SRC" ]; then
      fail "drift: $HOOK $FN source-of-truth file not found ($SRC)"
      continue
    fi
    if diff <(sed -n "/^$FN()/,/^}$/p" "$HOOK") \
            <(sed -n "/^$FN()/,/^}$/p" "$SRC") \
            > /dev/null; then
      pass "drift: $HOOK $FN matches source-of-truth"
    else
      fail "drift: $HOOK $FN drifted from $SRC"
    fi
  done
done

# ── zskills_resolve_python drift (issue #1075) ──────────────────────────────
# Source-of-truth body lives in hooks/_lib/resolve-python.sh. Unlike the
# git-tokenwalk family (inlined into a handful of block-* hooks), this resolver
# is inlined into EVERY hook/helper that needs a working Python 3 interpreter —
# the plugin-served and legacy-mirror hooks cannot reach _lib at runtime
# reliably, so the body must be pasted in. Each inlining consumer
# is listed here; the body (extracted between `^zskills_resolve_python()` and
# the first `^}$`) must be byte-identical to the source-of-truth. The two prose
# fences (skills/do/SKILL.md, skills/draft-plan/references/brainstorm.md) embed
# the SAME function inside a bash block; the sed extraction is fence-agnostic
# (it anchors on the function definition at column 0) so they are gated too.
RESOLVE_PYTHON_CONSUMERS=(
  hooks/inject-bash-timeout.sh
  hooks/block-bad-cron.sh
  hooks/block-fix-issue-unclaimed.sh
  hooks/block-run-plan-unclaimed.sh
  hooks/log-permission-request.sh
  hooks/log-session-stop.sh
  hooks/_lib/detect-install-state.sh
  hooks/_lib/plugin-hook-skip-if-mirrored.sh
  scripts/build-catalog.sh
  scripts/build-plugin-release.sh
  scripts/switch-install-path.sh
  scripts/_lib/finalize-prod-tree.sh
  skills/update-zskills/verifiers/verify-install-lib.sh
  skills/update-zskills/scripts/init-state.sh
  skills/update-zskills/scripts/migrate-paths.sh
  skills/update-zskills/scripts/session-logs.sh
  skills/create-worktree/scripts/check-inflight-batch.sh
  skills/create-worktree/scripts/claim-self-reentry.sh
  skills/fix-issues/scripts/claim-issue.sh
  skills/fix-issues/scripts/filter-in-flight-issue-claims.sh
  skills/fix-issues/scripts/filter-unresearched-candidates.sh
  skills/fix-issues/scripts/record-skip.sh
  skills/run-plan/scripts/claim-plan.sh
  skills/work-on-plans/scripts/filter-in-flight-plan-claims.sh
  skills/work-on-plans/scripts/filter-mode-mismatch-plans.sh
  skills/do/SKILL.md
  skills/draft-plan/references/brainstorm.md
)
RP_SRC="$(fn_source zskills_resolve_python)"
if [ -z "$RP_SRC" ] || [ ! -f "$RP_SRC" ]; then
  fail "drift: zskills_resolve_python source-of-truth file not found ($RP_SRC)"
else
  for CONSUMER in "${RESOLVE_PYTHON_CONSUMERS[@]}"; do
    if [ ! -f "$CONSUMER" ]; then
      fail "drift: $CONSUMER zskills_resolve_python consumer file not found"
      continue
    fi
    if diff <(sed -n "/^zskills_resolve_python()/,/^}$/p" "$CONSUMER") \
            <(sed -n "/^zskills_resolve_python()/,/^}$/p" "$RP_SRC") \
            > /dev/null; then
      pass "drift: $CONSUMER zskills_resolve_python matches source-of-truth"
    else
      fail "drift: $CONSUMER zskills_resolve_python drifted from $RP_SRC"
    fi
  done
fi

# ── zskills_normalize_tool_path drift (Windows-native-path normaliser) ──────
# Source-of-truth body lives in hooks/_lib/normalize-tool-path.sh. Like the
# resolver, it is inlined VERBATIM into each consuming hook (the legacy-mirror
# hooks under .claude/hooks/ cannot reach _lib at runtime — .claude/hooks/_lib/
# is not mirrored), so the body must be byte-identical to the source-of-truth.
NORMALIZE_PATH_CONSUMERS=(
  hooks/block-main-edits.sh
  hooks/warn-config-drift.sh
)
NP_SRC="$(fn_source zskills_normalize_tool_path)"
if [ -z "$NP_SRC" ] || [ ! -f "$NP_SRC" ]; then
  fail "drift: zskills_normalize_tool_path source-of-truth file not found ($NP_SRC)"
else
  for CONSUMER in "${NORMALIZE_PATH_CONSUMERS[@]}"; do
    if [ ! -f "$CONSUMER" ]; then
      fail "drift: $CONSUMER zskills_normalize_tool_path consumer file not found"
      continue
    fi
    if diff <(sed -n "/^zskills_normalize_tool_path()/,/^}$/p" "$CONSUMER") \
            <(sed -n "/^zskills_normalize_tool_path()/,/^}$/p" "$NP_SRC") \
            > /dev/null; then
      pass "drift: $CONSUMER zskills_normalize_tool_path matches source-of-truth"
    else
      fail "drift: $CONSUMER zskills_normalize_tool_path drifted from $NP_SRC"
    fi
  done
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
exit $FAIL_COUNT
