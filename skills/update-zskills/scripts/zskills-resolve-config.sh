#!/bin/bash
# zskills-resolve-config.sh — sourceable helper that resolves zskills-config
# fields into shell vars at the point of source.
#
# Usage (one-line preamble at top of any skill bash fence that needs config):
#   . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
#   # vars now set: $UNIT_TEST_CMD $FULL_TEST_CMD $TIMEZONE $DEV_SERVER_CMD
#   #               $TEST_OUTPUT_FILE $COMMIT_CO_AUTHOR $ZSKILLS_VERSION
#
# Contract:
#   - Reads .claude/zskills-config.json from $CLAUDE_PROJECT_DIR.
#   - Pure bash regex (BASH_REMATCH); never invokes jq.
#   - All 7 vars initialized to empty string BEFORE regex test
#     (empty-pattern-guard from DRIFT_ARCH_FIX Phase 1).
#   - Empty / missing / malformed config → empty vars, no abort.
#   - Idempotent — sourcing twice yields the same vars.
#   - No opinionated defaults; consumer decides empty handling.
#   - Unsets _ZSK_-prefixed internals at end so caller env stays clean.
#
# Coexistence: same directory hosts zskills-stub-lib.sh, which exposes
# `zskills_dispatch_stub`. Domain-disjoint — no naming collisions.

# CLAUDE_PROJECT_DIR resolution.
#
# Anthropic's harness only documents this var as set for hook subprocesses
# (https://code.claude.com/docs/en/hooks — "Command hook fields / Exec
# form and shell form"); it is NOT documented to be set in Bash-tool
# subshells. tests/run-all.sh exports it for tests. When neither path
# applies (orchestrator-side Bash from inside a skill), we fall back to
# the canonical "find main repo from anywhere" idiom used elsewhere in
# this codebase (ensure-worktree.sh, create-worktree.sh, land-phase.sh):
# `git rev-parse --git-common-dir`, whose result resolves through
# worktree links back to the main repo's `.git`. Then dirname gives the
# main repo root — matching the harness-set semantics.
#
# The stderr WARN fires once per shell (via _ZSK_FALLBACK_WARNED sentinel)
# so the harness gap stays visible without spamming every source.
#
# Outside a git repo, no clean fallback exists and zskills cannot function;
# fail with a clear error.
if [ -z "${CLAUDE_PROJECT_DIR:-}" ]; then
  if _ZSK_COMMON_DIR=$(git rev-parse --git-common-dir 2>/dev/null) \
       && CLAUDE_PROJECT_DIR=$(cd "$_ZSK_COMMON_DIR/.." && pwd); then
    export CLAUDE_PROJECT_DIR
    if [ -z "${_ZSK_FALLBACK_WARNED:-}" ]; then
      echo "WARN: zskills: CLAUDE_PROJECT_DIR not set by harness; fell back to $CLAUDE_PROJECT_DIR via git-common-dir" >&2
      _ZSK_FALLBACK_WARNED=1
    fi
    unset _ZSK_COMMON_DIR
  else
    echo "ERROR: zskills: CLAUDE_PROJECT_DIR not set and not in a git repo — cannot resolve project root" >&2
    unset _ZSK_COMMON_DIR
    return 127 2>/dev/null || exit 127
  fi
fi

_ZSK_CFG="$CLAUDE_PROJECT_DIR/.claude/zskills-config.json"

# Initialize all 7 vars to empty FIRST (empty-pattern-guard).
UNIT_TEST_CMD=""
FULL_TEST_CMD=""
TIMEZONE=""
DEV_SERVER_CMD=""
TEST_OUTPUT_FILE=""
COMMIT_CO_AUTHOR=""
ZSKILLS_VERSION=""

if [ -f "$_ZSK_CFG" ]; then
  _ZSK_CFG_BODY=$(cat "$_ZSK_CFG" 2>/dev/null) || _ZSK_CFG_BODY=""
  if [[ "$_ZSK_CFG_BODY" =~ \"unit_cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    UNIT_TEST_CMD="${BASH_REMATCH[1]}"
  fi
  if [[ "$_ZSK_CFG_BODY" =~ \"full_cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    FULL_TEST_CMD="${BASH_REMATCH[1]}"
  fi
  if [[ "$_ZSK_CFG_BODY" =~ \"timezone\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    TIMEZONE="${BASH_REMATCH[1]}"
  fi
  # dev_server.cmd: scope via enclosing "dev_server" object to disambiguate
  # from any other "cmd" key (e.g. testing.cmd).
  if [[ "$_ZSK_CFG_BODY" =~ \"dev_server\"[[:space:]]*:[[:space:]]*\{[^}]*\"cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    DEV_SERVER_CMD="${BASH_REMATCH[1]}"
  fi
  if [[ "$_ZSK_CFG_BODY" =~ \"output_file\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    TEST_OUTPUT_FILE="${BASH_REMATCH[1]}"
  fi
  # commit.co_author: scope via enclosing "commit" object to disambiguate
  # from a hypothetical top-level "co_author".
  if [[ "$_ZSK_CFG_BODY" =~ \"commit\"[[:space:]]*:[[:space:]]*\{[^}]*\"co_author\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    COMMIT_CO_AUTHOR="${BASH_REMATCH[1]}"
  fi
  # zskills_version: top-level optional string. The installed-version
  # fingerprint of zskills (date+hash). Empty when not yet written.
  if [[ "$_ZSK_CFG_BODY" =~ \"zskills_version\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    ZSKILLS_VERSION="${BASH_REMATCH[1]}"
  fi
  unset _ZSK_CFG_BODY
fi

unset _ZSK_CFG
