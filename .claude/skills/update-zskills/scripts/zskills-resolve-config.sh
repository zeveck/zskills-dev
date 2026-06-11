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
# Contract (config cascade — INSTALL_REDESIGN Phase 5):
#   - Resolution order per key: PROJECT .claude/zskills-config.json (under
#     $CLAUDE_PROJECT_DIR) > USER $HOME/.claude/zskills-config.json >
#     built-in defaults. Implemented as a two-pass read: the user body is
#     extracted FIRST, then the project body; a key whose regex MATCHES in
#     the project body wins (match-success = presence — the pragmatic
#     presence test for the bash-regex family). A present-but-EMPTY project
#     value ("key": "") therefore wins over a non-empty user value (and then
#     falls through to the built-in default, when the key has one).
#   - PROJECT-TIER-ONLY keys (never read from the user tier):
#       * execution.* — repo discipline, not a user preference (the Phase 5
#         family-5 rule: execution.* does not cascade from the user tier
#         ANYWHERE in the cascade).
#       * zskills_version — the per-project install stamp; falls back to the
#         `version:` line of .zskills/init-done, never to the user tier.
#   - Built-in defaults (filled after both passes, for still-empty keys):
#     TIMEZONE→UTC, TEST_OUTPUT_FILE→.test-results.txt. The cmd vars
#     ($UNIT_TEST_CMD/$FULL_TEST_CMD/$DEV_SERVER_CMD) and $COMMIT_CO_AUTHOR
#     have NO sane built-in and stay empty (consuming skills' config-driven
#     three-case trees handle empty). Values are PINNED to the canonical
#     skills/update-zskills/scripts/zskills-defaults.json by the
#     `zskills-defaults-congruence` markers below (enforced by
#     tests/test-skill-conformance.sh).
#   - Pure bash regex (BASH_REMATCH); never invokes jq.
#   - String vars initialized to empty string BEFORE regex test
#     (empty-pattern-guard from DRIFT_ARCH_FIX Phase 1).
#   - Missing / malformed config at either tier → that tier's regexes simply
#     don't match (fail-open), no abort.
#   - Idempotent — sourcing twice yields the same vars.
#   - $ZSKILLS_MAX_CONCURRENT_WORKTREES defaults to 3 when absent/malformed
#     so /fix-issues' aggregate live-worktree cap stays bounded for
#     consumers who haven't touched config (#295).
#   - Unsets _ZSK_-prefixed internals (and the _zsk_* helper fn) at end so
#     caller env stays clean.
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

# Shell-portable self-location (issue #1149). Claude Code's Bash tool runs
# skill fences under the user's snapshot shell — zsh on default macOS/dev
# setups — where BASH_SOURCE is unset: a bare ${BASH_SOURCE[0]} expanded
# empty, the sibling-source below degenerated to `. ./zskills-paths.sh`
# (cwd-relative, absent in a consumer repo), $ZSKILLS_SKILLS_ROOT stayed
# empty, and the Layer-3 validator path became /update-zskills/... → 127.
# zsh's default FUNCTION_ARGZERO sets $0 to the sourced file's path, so
# ${BASH_SOURCE[0]:-$0} self-locates correctly under bash AND zsh (same
# idiom as sanitize-pipeline-id.sh / claim-*.sh dual-mode detection).
_ZSK_SELF_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]:-$0}")")"

# Source the sibling path-resolution helper so every fence that sources this
# config helper ALSO gets $ZSKILLS_SKILLS_ROOT (the lane-portable skills root
# used by Family-2 bundled-script invocations). Corrected Family-1 bootstrap:
# plugin lane lives under .../skills/update-zskills/scripts/, legacy lane under
# $CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/. The guard avoids a
# redundant re-source within one shell; zskills-paths.sh is independently
# idempotent. CLAUDE_PROJECT_DIR is resolved above before this runs, so the
# legacy branch anchors on the same project root as the rest of this helper.
if [ -z "${ZSKILLS_SKILLS_ROOT:-}" ]; then
  # zskills-paths.sh is a sibling in this same scripts/ dir on both lanes —
  # source it env-independently (the ${CLAUDE_PLUGIN_ROOT:-} guard was broken
  # mirror-less: empty in the script env → fell to the absent legacy mirror).
  . "$_ZSK_SELF_DIR/zskills-paths.sh"
fi

# Working-Python-3 interpreter resolution.
#
# Every skill bash fence that sources this prelude gets $PYTHON exported here,
# so fences can invoke `"$PYTHON" …` instead of a bare `python3` (which on
# Windows resolves to the broken MS Store App-Execution-Alias stub — see #1075,
# #1083). The probe RUNS each candidate (existence is not enough: the stub
# exists on PATH but exits non-zero). Honors ZSKILLS_PYTHON; rejects python2.
#
# Canonical source of this probe is hooks/_lib/resolve-python.sh
# (zskills_resolve_python). KEEP THE PROBE IN SYNC with that file — the
# tests/test-python-resolver-drift.sh gate asserts the candidate-walk +
# version-check stay identical across the two.
#
# Guarded as a cheap no-op when $PYTHON is already a working Python 3 (so the
# 60×-per-run sourcing in /fix-issues etc. doesn't re-probe each time). When no
# working interpreter is found, $PYTHON is set to "" — the prelude stays safe to
# source (no exit/return nonzero); each fence guards its own use of $PYTHON.
if [ -z "${PYTHON:-}" ] || ! "$PYTHON" -c 'import sys; sys.exit(0 if sys.version_info[0]==3 else 1)' >/dev/null 2>&1; then
  PYTHON=""
  for _ZSK_PYCAND in "${ZSKILLS_PYTHON:-}" python3 python; do
    [ -n "$_ZSK_PYCAND" ] || continue
    command -v "$_ZSK_PYCAND" >/dev/null 2>&1 || continue
    if "$_ZSK_PYCAND" -c 'import sys; sys.exit(0 if sys.version_info[0]==3 else 1)' >/dev/null 2>&1; then
      PYTHON="$(command -v "$_ZSK_PYCAND")"
      break
    fi
  done
  unset _ZSK_PYCAND
fi
export PYTHON

_ZSK_CFG="$CLAUDE_PROJECT_DIR/.claude/zskills-config.json"
_ZSK_USER_CFG="${HOME:-}/.claude/zskills-config.json"

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
# Dashboard Completed-window config (W1.6 of completed-backlog-sections).
# Days = recency window; Limit = max closed-issue payload size.
ZSKILLS_DASHBOARD_COMPLETED_DAYS=14
ZSKILLS_DASHBOARD_COMPLETED_LIMIT=500

# Extract the six USER-CASCADABLE string keys from one config body (any
# tier). Each key's regex is an independent presence test: a key that
# matches OVERWRITES the var (so calling this on the user body first, then
# the project body, implements "project match wins; user fills
# project-absent keys"). Keys that do NOT match leave the var untouched.
#
# testing.unit_cmd / testing.full_cmd / testing.output_file: scope via
# enclosing "testing" object to disambiguate from any other block that
# happens to carry an identically-named key (e.g. a sibling "ui" or
# "execution" block declaring its own "unit_cmd"). Mirrors the
# dev_server.cmd scoping. The bash =~ engine is single-line but
# [^}] matches newlines, so this works on both compact and canonical
# multi-line JSON. Issue #395 (same class as #400 fixed in #422).
_zsk_extract_cascade_keys() {
  # zsh portability (#1154): under zsh's snapshot-shell, `[[ =~ ]]` populates
  # $match/$mbegin natively and leaves $BASH_REMATCH bash-incompatible (1 ==
  # whole match, captures shifted) UNLESS both KSH_ARRAYS and BASH_REMATCH
  # are set. LOCAL_OPTIONS scopes the change to this function so the caller's
  # zsh options are untouched on return; the guard is a no-op under bash
  # (no `setopt` builtin, ZSH_VERSION unset). Without this, every cascade key
  # silently extracted empty under zsh and fell to built-in defaults.
  if [ -n "${ZSH_VERSION:-}" ]; then
    setopt LOCAL_OPTIONS KSH_ARRAYS BASH_REMATCH 2>/dev/null
  fi
  local _zsk_body="$1"
  if [[ "$_zsk_body" =~ \"testing\"[[:space:]]*:[[:space:]]*[{][^}]*\"unit_cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    UNIT_TEST_CMD="${BASH_REMATCH[1]}"
  fi
  if [[ "$_zsk_body" =~ \"testing\"[[:space:]]*:[[:space:]]*[{][^}]*\"full_cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    FULL_TEST_CMD="${BASH_REMATCH[1]}"
  fi
  if [[ "$_zsk_body" =~ \"timezone\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    TIMEZONE="${BASH_REMATCH[1]}"
  fi
  # dev_server.cmd: scope via enclosing "dev_server" object to disambiguate
  # from any other "cmd" key (e.g. testing.cmd).
  if [[ "$_zsk_body" =~ \"dev_server\"[[:space:]]*:[[:space:]]*[{][^}]*\"cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    DEV_SERVER_CMD="${BASH_REMATCH[1]}"
  fi
  if [[ "$_zsk_body" =~ \"testing\"[[:space:]]*:[[:space:]]*[{][^}]*\"output_file\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    TEST_OUTPUT_FILE="${BASH_REMATCH[1]}"
  fi
  # commit.co_author: scope via enclosing "commit" object to disambiguate
  # from a hypothetical top-level "co_author".
  if [[ "$_zsk_body" =~ \"commit\"[[:space:]]*:[[:space:]]*[{][^}]*\"co_author\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    COMMIT_CO_AUTHOR="${BASH_REMATCH[1]}"
  fi
}

# ── Pass 1: USER tier ($HOME/.claude/zskills-config.json) ──────────────────
# Cascadable string keys only. execution.* and zskills_version are
# PROJECT-TIER-ONLY (see contract above) and are never read here.
if [ -n "${HOME:-}" ] && [ -f "$_ZSK_USER_CFG" ]; then
  _ZSK_USER_BODY=$(cat "$_ZSK_USER_CFG" 2>/dev/null) || _ZSK_USER_BODY=""
  _zsk_extract_cascade_keys "$_ZSK_USER_BODY"
  unset _ZSK_USER_BODY
fi

# Project-tier-only key extraction (zskills_version + execution.*). Wrapped
# in a function for the SAME zsh-portability reason as _zsk_extract_cascade_keys
# (#1154): the LOCAL_OPTIONS-scoped KSH_ARRAYS/BASH_REMATCH guard only reverts
# at function scope, so these matches must run inside a function (not at the
# sourced top level, where the option flip would leak into the caller's shell).
_zsk_extract_project_only_keys() {
  if [ -n "${ZSH_VERSION:-}" ]; then
    setopt LOCAL_OPTIONS KSH_ARRAYS BASH_REMATCH 2>/dev/null
  fi
  local _zsk_body="$1"
  # zskills_version: top-level optional string. The installed-version
  # fingerprint of zskills (date+hash). PROJECT-TIER-ONLY (per-project
  # install stamp); falls back to .zskills/init-done below when absent.
  if [[ "$_zsk_body" =~ \"zskills_version\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    ZSKILLS_VERSION="${BASH_REMATCH[1]}"
  fi
  # execution.max_concurrent_worktrees: integer (unquoted in JSON). Used by
  # /fix-issues to bound sprint-wide aggregate live worktrees (issue #295).
  # We accept any positive integer; if the value is malformed (non-integer
  # or <=0), keep the default of 3 from the initializer above.
  if [[ "$_zsk_body" =~ \"execution\"[[:space:]]*:[[:space:]]*[{][^}]*\"max_concurrent_worktrees\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
    local _zsk_mcw="${BASH_REMATCH[1]}"
    if [ "$_zsk_mcw" -ge 1 ] 2>/dev/null; then
      ZSKILLS_MAX_CONCURRENT_WORKTREES="$_zsk_mcw"
    fi
  fi
  # execution.dashboard_completed_days: integer, default 14, min 1. Used
  # by collect.py / Python via stdlib json (this resolver mirrors for
  # shell consumers). Same BASH_REMATCH scoping idiom as
  # max_concurrent_worktrees.
  if [[ "$_zsk_body" =~ \"execution\"[[:space:]]*:[[:space:]]*[{][^}]*\"dashboard_completed_days\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
    local _zsk_dcd="${BASH_REMATCH[1]}"
    if [ "$_zsk_dcd" -ge 1 ] 2>/dev/null; then
      ZSKILLS_DASHBOARD_COMPLETED_DAYS="$_zsk_dcd"
    fi
  fi
  # execution.dashboard_completed_limit: integer, default 500, min 1.
  # Caps the bounded closed-issue fetch (D6 of completed-backlog-sections).
  if [[ "$_zsk_body" =~ \"execution\"[[:space:]]*:[[:space:]]*[{][^}]*\"dashboard_completed_limit\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
    local _zsk_dcl="${BASH_REMATCH[1]}"
    if [ "$_zsk_dcl" -ge 1 ] 2>/dev/null; then
      ZSKILLS_DASHBOARD_COMPLETED_LIMIT="$_zsk_dcl"
    fi
  fi
}

# ── Pass 2: PROJECT tier (a project match wins over the user tier) ─────────
if [ -f "$_ZSK_CFG" ]; then
  _ZSK_CFG_BODY=$(cat "$_ZSK_CFG" 2>/dev/null) || _ZSK_CFG_BODY=""
  _zsk_extract_cascade_keys "$_ZSK_CFG_BODY"
  _zsk_extract_project_only_keys "$_ZSK_CFG_BODY"
  unset _ZSK_CFG_BODY
fi
unset -f _zsk_extract_cascade_keys
unset -f _zsk_extract_project_only_keys

# ── ZSKILLS_VERSION fallback: the init-done marker's `version:` line ───────
# Config-less consumers carry the installed version in the init-done marker
# (written by the Phase 6a explicit init: `version:` + `date:` lines). The
# marker path comes from init-state.sh — the #1132 single path definition,
# shipped in this same directory (shell-portable self-location via
# $_ZSK_SELF_DIR, captured above — works under zsh fence shells too, #1149)
# — never a re-typed literal (Phase 6a item A0 closed the documented Phase 5
# re-type window). If init-state.sh is somehow unreachable, the fallback is
# skipped and ZSKILLS_VERSION stays empty (fail-open, no literal fallback).
if [ -z "$ZSKILLS_VERSION" ] && [ -f "$_ZSK_SELF_DIR/init-state.sh" ]; then
  # shellcheck source=skills/update-zskills/scripts/init-state.sh
  . "$_ZSK_SELF_DIR/init-state.sh"
  if [ -f "$CLAUDE_PROJECT_DIR/$ZSKILLS_INIT_DONE_REL" ]; then
    while IFS= read -r _ZSK_IDLINE || [ -n "$_ZSK_IDLINE" ]; do
      case "$_ZSK_IDLINE" in
        version:*)
          ZSKILLS_VERSION="${_ZSK_IDLINE#version:}"
          # Trim surrounding whitespace.
          ZSKILLS_VERSION="${ZSKILLS_VERSION#"${ZSKILLS_VERSION%%[![:space:]]*}"}"
          ZSKILLS_VERSION="${ZSKILLS_VERSION%"${ZSKILLS_VERSION##*[![:space:]]}"}"
          break
          ;;
      esac
    done < "$CLAUDE_PROJECT_DIR/$ZSKILLS_INIT_DONE_REL"
    unset _ZSK_IDLINE
  fi
fi

# ── Built-in defaults (cascade tier 3) — fill still-empty keys ──────────────
# Values are PINNED ≡ skills/update-zskills/scripts/zskills-defaults.json by
# the congruence check in tests/test-skill-conformance.sh ("config-cascade
# built-in defaults congruence"); the marker line names the JSON key path.
# zskills-defaults-congruence: timezone
if [ -z "$TIMEZONE" ]; then TIMEZONE="UTC"; fi
# zskills-defaults-congruence: testing.output_file
if [ -z "$TEST_OUTPUT_FILE" ]; then TEST_OUTPUT_FILE=".test-results.txt"; fi

unset _ZSK_CFG _ZSK_USER_CFG _ZSK_SELF_DIR
