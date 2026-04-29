#!/bin/bash
# zskills-resolve-config.sh — sourceable helper that resolves zskills-config
# fields into shell vars at the point of source.
#
# Usage (one-line preamble at top of any skill bash fence that needs config):
#   . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
#   # vars now set: $UNIT_TEST_CMD $FULL_TEST_CMD $TIMEZONE $DEV_SERVER_CMD
#   #               $TEST_OUTPUT_FILE $COMMIT_CO_AUTHOR
#
# Contract:
#   - Reads .claude/zskills-config.json from $CLAUDE_PROJECT_DIR.
#   - Pure bash regex (BASH_REMATCH); never invokes jq.
#   - All 6 vars initialized to empty string BEFORE regex test
#     (empty-pattern-guard from DRIFT_ARCH_FIX Phase 1).
#   - Empty / missing / malformed config → empty vars, no abort.
#   - Idempotent — sourcing twice yields the same vars.
#   - No opinionated defaults; consumer decides empty handling.
#   - Unsets _ZSK_-prefixed internals at end so caller env stays clean.
#
# Coexistence: same directory hosts zskills-stub-lib.sh, which exposes
# `zskills_dispatch_stub`. Domain-disjoint — no naming collisions.

# Fail loud if CLAUDE_PROJECT_DIR is absent. The harness sets it for spawned
# bash blocks; tests/run-all.sh exports it from REPO_ROOT.
: "${CLAUDE_PROJECT_DIR:?CLAUDE_PROJECT_DIR not set — harness or tests/run-all.sh export missing}"

_ZSK_CFG="$CLAUDE_PROJECT_DIR/.claude/zskills-config.json"

# Initialize all 6 vars to empty FIRST (empty-pattern-guard).
UNIT_TEST_CMD=""
FULL_TEST_CMD=""
TIMEZONE=""
DEV_SERVER_CMD=""
TEST_OUTPUT_FILE=""
COMMIT_CO_AUTHOR=""

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
  unset _ZSK_CFG_BODY
fi

unset _ZSK_CFG
