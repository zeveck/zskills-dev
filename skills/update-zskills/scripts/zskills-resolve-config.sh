#!/bin/bash
# zskills-resolve-config.sh — sourceable helper that resolves zskills-config
# fields into shell vars at the point of source.
#
# Usage (one-line preamble at top of any skill bash fence that needs config):
#   . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
#   # vars now set: $UNIT_TEST_CMD $FULL_TEST_CMD $TIMEZONE $DEV_SERVER_CMD
#   #               $TEST_OUTPUT_FILE $COMMIT_CO_AUTHOR $ZSKILLS_VERSION
#   #               $ZSKILLS_MAX_CONCURRENT_WORKTREES
#
# Contract:
#   - Reads .claude/zskills-config.json from $CLAUDE_PROJECT_DIR.
#   - Pure bash regex (BASH_REMATCH); never invokes jq.
#   - String vars initialized to empty string BEFORE regex test
#     (empty-pattern-guard from DRIFT_ARCH_FIX Phase 1).
#   - Empty / missing / malformed config → empty string vars, no abort.
#   - Idempotent — sourcing twice yields the same vars.
#   - No opinionated defaults for string vars; consumer decides empty handling.
#   - $ZSKILLS_MAX_CONCURRENT_WORKTREES is the ONE exception: it defaults
#     to 3 when absent/malformed so /fix-issues' aggregate live-worktree
#     cap stays bounded for consumers who haven't touched config (#295).
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

# Initialize string vars to empty FIRST (empty-pattern-guard).
UNIT_TEST_CMD=""
FULL_TEST_CMD=""
TIMEZONE=""
DEV_SERVER_CMD=""
TEST_OUTPUT_FILE=""
COMMIT_CO_AUTHOR=""
ZSKILLS_VERSION=""
# Default the live-worktree-cap to 3 (preserves status quo behavior pre-#295
# for consumers who never set this field). Re-evaluated below if config sets it.
ZSKILLS_MAX_CONCURRENT_WORKTREES=3

if [ -f "$_ZSK_CFG" ]; then
  _ZSK_CFG_BODY=$(cat "$_ZSK_CFG" 2>/dev/null) || _ZSK_CFG_BODY=""
  # testing.unit_cmd / testing.full_cmd / testing.output_file: scope via
  # enclosing "testing" object to disambiguate from any other block that
  # happens to carry an identically-named key (e.g. a sibling "ui" or
  # "execution" block declaring its own "unit_cmd"). Mirrors the
  # dev_server.cmd scoping below. The bash =~ engine is single-line but
  # [^}] matches newlines, so this works on both compact and canonical
  # multi-line JSON. Issue #395 (same class as #400 fixed in #422).
  if [[ "$_ZSK_CFG_BODY" =~ \"testing\"[[:space:]]*:[[:space:]]*\{[^}]*\"unit_cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    UNIT_TEST_CMD="${BASH_REMATCH[1]}"
  fi
  if [[ "$_ZSK_CFG_BODY" =~ \"testing\"[[:space:]]*:[[:space:]]*\{[^}]*\"full_cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
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
  if [[ "$_ZSK_CFG_BODY" =~ \"testing\"[[:space:]]*:[[:space:]]*\{[^}]*\"output_file\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
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
  # execution.max_concurrent_worktrees: integer (unquoted in JSON). Used by
  # /fix-issues to bound sprint-wide aggregate live worktrees (issue #295).
  # We accept any positive integer; if the value is malformed (non-integer
  # or <=0), keep the default of 3 from the initializer above.
  if [[ "$_ZSK_CFG_BODY" =~ \"execution\"[[:space:]]*:[[:space:]]*\{[^}]*\"max_concurrent_worktrees\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
    _ZSK_MCW="${BASH_REMATCH[1]}"
    if [ "$_ZSK_MCW" -ge 1 ] 2>/dev/null; then
      ZSKILLS_MAX_CONCURRENT_WORKTREES="$_ZSK_MCW"
    fi
    unset _ZSK_MCW
  fi
  unset _ZSK_CFG_BODY
fi

unset _ZSK_CFG
