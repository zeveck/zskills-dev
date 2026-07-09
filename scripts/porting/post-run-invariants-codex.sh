#!/bin/bash
# scripts/porting/post-run-invariants-codex.sh — End-of-run assertions for
# runner-managed run-plan executions (CODEX_PORT_PLAN Phase 1, WI 1.3 — spec
# change 14, INVARIANTS-REFORK).
#
# RE-FORKED from the CURRENT upstream skills/run-plan/scripts/
# post-run-invariants.sh (235 lines at re-fork time — worktree-aware
# PROJECT_ROOT resolution, `.zskills/landed` new-path-first dual-read), then
# parametrized with --base-branch / --remote / --report (the fork-era
# parametrization re-applied). Do NOT carry the April-2026 fork copy — it
# greps the legacy root `.landed` path only. Body edits beyond the
# parametrization are deliberately minimal so upstream diffs stay reviewable.
#
# Purpose: make silent-failure accumulation structurally impossible. After
# a plan run completes (PR mode, cherry-pick mode, or delegate mode), the
# orchestrator MUST invoke this script. It asserts:
#   1. Worktree directory gone from disk
#   2. Worktree removed from git's worktree registry
#   3. Local feature branch deleted (when landed)
#   4. Remote feature branch deleted (when landed)
#   5. Plan report exists at the expected path
#   6. No 🟡 In Progress rows linger in the tracker
#   7. Local main reconcilable with origin/main (warn, not fail — user may
#      have legitimate unpushed work)
#
# Any invariant violation exits non-zero with a specific error. This is
# the mechanical gate that catches silent failures in land-phase.sh or
# the orchestrator's own cleanup. Prose-in-SKILL.md was not enough;
# the LLM may skip prose under compaction. This script WILL run.
#
# Usage:
#   bash $(basename "$0") \
#     --worktree <path> \
#     --branch <name> \
#     --landed-status <status> \
#     --plan-slug <slug> \
#     --plan-file <path> \
#     [--base-branch <name>]   # integration branch (default: main)
#     [--remote <name>]        # remote name (default: origin)
#     [--report <path>]        # explicit report path (default: resolve
#                              #   $ZSKILLS_REPORTS_DIR/plan-<slug>.md via
#                              #   the zskills-paths.sh helper when present)
#
# Core args required. Use empty string for irrelevant ones (e.g., direct
# mode has no worktree/branch — pass empty and the related checks skip).
# In a PORTED tree the zskills-paths.sh helper does not exist — pass
# --report explicitly there (the report invariant fails loudly, never
# silently skips, when neither resolution path is available).

set -u

WORKTREE_PATH=""
BRANCH_NAME=""
LANDED_STATUS=""
PLAN_SLUG=""
PLAN_FILE=""
BASE_BRANCH="main"
REMOTE="origin"
REPORT_ARG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --worktree)      WORKTREE_PATH="$2"; shift 2 ;;
    --branch)        BRANCH_NAME="$2"; shift 2 ;;
    --landed-status) LANDED_STATUS="$2"; shift 2 ;;
    --plan-slug)     PLAN_SLUG="$2"; shift 2 ;;
    --plan-file)     PLAN_FILE="$2"; shift 2 ;;
    --base-branch)   BASE_BRANCH="$2"; shift 2 ;;
    --remote)        REMOTE="$2"; shift 2 ;;
    --report)        REPORT_ARG="$2"; shift 2 ;;
    *)               echo "ERROR: unknown arg '$1'" >&2; exit 2 ;;
  esac
done
[ -n "$BASE_BRANCH" ] || BASE_BRANCH="main"
[ -n "$REMOTE" ] || REMOTE="origin"

# Resolve MAIN_ROOT for git-state queries (worktree registry, branch
# refs, origin, fetch+merge-base). These ALWAYS point at main, even in
# PR mode — the registry, local branch list, and remote-tracking refs
# live on main's .git, not the worktree's.
MAIN_ROOT_GIT_DIR=$(git rev-parse --git-common-dir 2>/dev/null)
if [ -z "$MAIN_ROOT_GIT_DIR" ]; then
  echo "ERROR: post-run-invariants.sh must run from inside a git repository" >&2
  exit 1
fi
MAIN_ROOT=$(cd "$MAIN_ROOT_GIT_DIR/.." && pwd)
if [ -z "$MAIN_ROOT" ] || [ "$MAIN_ROOT" = "/" ]; then
  echo "ERROR: MAIN_ROOT resolved to '$MAIN_ROOT' — aborting" >&2
  exit 1
fi

# Resolve PROJECT_ROOT for path resolution (REPORT_PATH, plan tracker
# reads). When the orchestrator passed --worktree <path> AND that path
# exists on disk, the worktree IS the project root — the feature-branch
# bookkeeping (audit dir, tracker) lives there in PR mode. Otherwise
# PROJECT_ROOT defaults to the current repo's working tree (show-toplevel),
# which equals MAIN_ROOT in direct/main mode but resolves correctly when
# the script is invoked from inside a worktree without the --worktree arg
# (e.g., test fixtures, ad-hoc invocations). Falls back to MAIN_ROOT if
# show-toplevel is unavailable.
if [ -n "$WORKTREE_PATH" ] && [ -d "$WORKTREE_PATH" ]; then
  PROJECT_ROOT="$WORKTREE_PATH"
else
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
  [ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$MAIN_ROOT"
fi

# Source the helper with PROJECT_ROOT (worktree path in PR mode, main
# in direct mode) so $ZSKILLS_AUDIT_DIR resolves to the right tree.
ZSKILLS_PATHS_ROOT="$PROJECT_ROOT"
# Lane-agnostic resolution of the sibling-skill helper: BASH_SOURCE-relative
# (plugin tree + legacy mirror are both 1:1, so ../../update-zskills/scripts/
# is correct on both lanes), with the consumer-mirror path as a fallback.
_self_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
for _cand in "$_self_dir/../../update-zskills/scripts/zskills-paths.sh" \
             "$PROJECT_ROOT/.claude/skills/update-zskills/scripts/zskills-paths.sh"; do
  [ -f "$_cand" ] && { source "$_cand"; break; }
done
unset _self_dir _cand

INVARIANT_FAILED=0

# 1. Worktree directory gone from disk
if [ -n "$WORKTREE_PATH" ]; then
  if [ -d "$WORKTREE_PATH" ]; then
    echo "INVARIANT-FAIL (#1): worktree still on disk at $WORKTREE_PATH" >&2
    INVARIANT_FAILED=1
  fi
fi

# 2. Worktree gone from git's worktree registry
if [ -n "$WORKTREE_PATH" ]; then
  if git -C "$MAIN_ROOT" worktree list --porcelain | grep -q "^worktree $WORKTREE_PATH$"; then
    echo "INVARIANT-FAIL (#2): $WORKTREE_PATH still in git worktree registry" >&2
    INVARIANT_FAILED=1
  fi
fi

# 3. Local feature branch gone (both modes — land-phase.sh deletes on 'landed')
if [ -n "$BRANCH_NAME" ] && [ "$BRANCH_NAME" != "$BASE_BRANCH" ] \
   && [ "$BRANCH_NAME" != "main" ] && [ "$BRANCH_NAME" != "master" ]; then
  if git -C "$MAIN_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    # Only fail if status was 'landed' — pr-ready/conflict intentionally keep
    # the branch around.
    if [ "$LANDED_STATUS" = "landed" ]; then
      echo "INVARIANT-FAIL (#3): local branch $BRANCH_NAME still exists after landed" >&2
      INVARIANT_FAILED=1
    fi
  fi
fi

# 4. Remote feature branch gone (PR mode landed only)
# Distinguish three ls-remote outcomes (prior version conflated them):
#   exit 0   → branch exists on origin → INVARIANT FAIL (should have been deleted)
#   exit 2   → branch absent on origin (with --exit-code) → invariant satisfied
#   exit 128 → origin unreachable / auth / config error → FAIL LOUDLY
# Prior behavior treated 2 and 128 identically as "pass," meaning a broken
# remote silently satisfied invariant #4. Mirrors land-phase.sh's pattern.
if [ -n "$BRANCH_NAME" ] && [ "$LANDED_STATUS" = "landed" ]; then
  LS_REMOTE_ERR=$(git -C "$MAIN_ROOT" ls-remote --exit-code --heads "$REMOTE" "$BRANCH_NAME" 2>&1 >/dev/null)
  LS_RC=$?
  case "$LS_RC" in
    0)
      echo "INVARIANT-FAIL (#4): remote branch $REMOTE/$BRANCH_NAME still exists after landed" >&2
      INVARIANT_FAILED=1
      ;;
    2)
      : # absent — invariant satisfied
      ;;
    *)
      echo "INVARIANT-FAIL (#4): ls-remote for $REMOTE/$BRANCH_NAME failed with exit $LS_RC — cannot verify deletion (remote unreachable, misconfigured, or auth failure)" >&2
      [ -n "$LS_REMOTE_ERR" ] && echo "  git stderr: $LS_REMOTE_ERR" >&2
      INVARIANT_FAILED=1
      ;;
  esac
fi

# 5. Plan report exists. --report (parametrization) wins; else fall back to
# the zskills-paths.sh-resolved $ZSKILLS_REPORTS_DIR (present only when the
# helper sourced above was found). Neither available → FAIL LOUDLY: a ported
# tree without the helper must pass --report, and a silent skip here would be
# exactly the silent-failure class this script exists to kill.
if [ -n "$REPORT_ARG" ]; then
  REPORT_PATH="$REPORT_ARG"
  if [ ! -f "$REPORT_PATH" ]; then
    echo "INVARIANT-FAIL (#5): plan report missing at $REPORT_PATH — Phase 5 didn't run or wrote elsewhere" >&2
    INVARIANT_FAILED=1
  fi
elif [ -n "$PLAN_SLUG" ]; then
  if [ -z "${ZSKILLS_REPORTS_DIR:-}" ]; then
    echo "INVARIANT-FAIL (#5): cannot resolve report path — zskills-paths.sh helper unavailable and no --report passed" >&2
    INVARIANT_FAILED=1
  else
    REPORT_PATH="$ZSKILLS_REPORTS_DIR/plan-${PLAN_SLUG}.md"
    if [ ! -f "$REPORT_PATH" ]; then
      echo "INVARIANT-FAIL (#5): plan report missing at $REPORT_PATH — Phase 5 didn't run or wrote elsewhere" >&2
      INVARIANT_FAILED=1
    fi
  fi
fi

# 6. No 🟡 In Progress rows linger in the tracker.
# Scoped to markdown table rows (lines starting with '|'). Bare whole-file
# grep false-positives on prose, Drift Log sections, and code-fence
# examples that mention the sentinel character — the invariant's real
# concern is the Progress Tracker table, which is always pipe-delimited.
if [ -n "$PLAN_FILE" ] && [ -f "$PLAN_FILE" ]; then
  if grep -qE '^\|.*🟡' "$PLAN_FILE"; then
    echo "INVARIANT-FAIL (#6): plan $PLAN_FILE still has 🟡 In Progress rows after run" >&2
    grep -nE '^\|.*🟡' "$PLAN_FILE" >&2
    INVARIANT_FAILED=1
  fi
fi

# #8: the landed marker recorded an UNKNOWN PR state (gh pr view
# rate-limited) — manual reconciliation required.
# Dual-read (Phase 8 root-turd consolidation): .zskills/landed first, then
# the legacy root .landed for pre-move worktrees; new path wins when both.
if [ -n "$WORKTREE_PATH" ]; then
  LANDED_MARKER="$WORKTREE_PATH/.zskills/landed"
  [ -f "$LANDED_MARKER" ] || LANDED_MARKER="$WORKTREE_PATH/.landed"
  if [ -f "$LANDED_MARKER" ]; then
    if grep -q '^status: pr-state-unknown$' "$LANDED_MARKER"; then
      INVARIANT_FAILED=1
      echo "INVARIANT-FAIL (#8): $LANDED_MARKER has status: pr-state-unknown — gh pr view could not verify; manual reconciliation required" >&2
    fi
  fi
fi

# #9: requires.land-pr.<id> exists but fulfilled.land-pr.<id> missing.
# In-session signal for the Phase-6-skip case where /run-plan PR mode
# wrote requires.land-pr.<id> at skill entry but /land-pr never reached
# the merge gate (skipped, errored, or completed without fulfilling).
# Only fails when LANDED_STATUS=landed — direct/cherry-pick modes never
# write requires.land-pr, and pr-ready/conflict states legitimately
# leave the requires unmet pending follow-up.
# The hook (block-unsafe-project.sh) catches this on the *next* git op;
# this invariant catches it in-session before the orchestrator exits.
if [ -n "$PLAN_SLUG" ] && [ "$LANDED_STATUS" = "landed" ]; then
  TRACKING_ID="$PLAN_SLUG"
  PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
  EXPECTED_REQUIRES="$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/requires.land-pr.$TRACKING_ID"
  EXPECTED_FULFILLED="$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/fulfilled.land-pr.$TRACKING_ID"
  if [ -f "$EXPECTED_REQUIRES" ] && [ ! -f "$EXPECTED_FULFILLED" ]; then
    echo "INVARIANT-FAIL (#9): $EXPECTED_REQUIRES exists but $EXPECTED_FULFILLED missing — /land-pr was supposed to write fulfillment on row-6 merge gate (MERGE_REQUESTED=true AND PR_STATE=MERGED AND CI_STATUS pass-or-none) but didn't" >&2
    INVARIANT_FAILED=1
  fi
fi

# 7. Local base branch reconcilable with $REMOTE/$BASE_BRANCH — WARN not FAIL
# Users may have legitimate unpushed work on the local base branch; we don't
# reject, but we surface it clearly so squash-merge divergence doesn't
# accumulate invisibly.
# Capture stderr instead of swallowing it with 2>/dev/null — when fetch
# fails (remote unreachable, auth, config), the agent reading the warn
# needs the underlying git error to diagnose. Same antipattern as
# Invariant #4 above: blind suppression loses diagnostic signal.
FETCH_ERR=$(git -C "$MAIN_ROOT" fetch "$REMOTE" "$BASE_BRANCH" 2>&1 >/dev/null)
FETCH_RC=$?
if [ "$FETCH_RC" -ne 0 ]; then
  echo "INVARIANT-WARN (#7): 'git fetch $REMOTE $BASE_BRANCH' failed with exit $FETCH_RC — cannot verify local $BASE_BRANCH alignment" >&2
  [ -n "$FETCH_ERR" ] && echo "  git stderr: $FETCH_ERR" >&2
elif ! git -C "$MAIN_ROOT" merge-base --is-ancestor "$BASE_BRANCH" "$REMOTE/$BASE_BRANCH" 2>/dev/null; then
  TREE_DIFF=$(git -C "$MAIN_ROOT" diff "$REMOTE/$BASE_BRANCH" "$BASE_BRANCH" 2>/dev/null | wc -l)
  if [ "$TREE_DIFF" -eq 0 ]; then
    echo "INVARIANT-WARN (#7): local $BASE_BRANCH has commits absent from $REMOTE/$BASE_BRANCH but tree is identical (squash-merge divergence). Safe to resolve with: git reset --hard $REMOTE/$BASE_BRANCH" >&2
  else
    echo "INVARIANT-WARN (#7): local $BASE_BRANCH diverges from $REMOTE/$BASE_BRANCH with $TREE_DIFF lines of real diff — manual reconciliation needed" >&2
  fi
fi

if [ "$INVARIANT_FAILED" -ne 0 ]; then
  echo "" >&2
  echo "Post-run invariants failed. Inspect and resolve before next run." >&2
  exit 1
fi
echo "Post-run invariants: all checks passed."
