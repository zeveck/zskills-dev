#!/bin/bash
# skills/update-zskills/scripts/zskills-paths.sh — sourceable shim.
# Resolves $ZSKILLS_PLANS_DIR, $ZSKILLS_ISSUES_DIR, $ZSKILLS_AUDIT_DIR from
# .claude/zskills-config.json.
#
# Usage:
#   # Default: harness sets $CLAUDE_PROJECT_DIR.
#   source "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-paths.sh"
#   # PR-mode override (worktree): caller sets $ZSKILLS_PATHS_ROOT.
#   ZSKILLS_PATHS_ROOT="$WORKTREE_PATH" \
#     source "$WORKTREE_PATH/.claude/skills/update-zskills/scripts/zskills-paths.sh"
#
# Contract:
#   - Project root: prefer $ZSKILLS_PATHS_ROOT, else $CLAUDE_PROJECT_DIR.
#     If both unset, helper fails loud (non-zero, stderr naming both vars).
#   - Config cascade (INSTALL_REDESIGN Phase 5): PROJECT
#     <root>/.claude/zskills-config.json > USER
#     $HOME/.claude/zskills-config.json > built-in defaults. Two-pass read
#     (user body first, then project body); a key whose regex MATCHES in the
#     project body wins, so a present-but-EMPTY project value falls through
#     to the built-in default even when the user tier set one. Note the user
#     tier is always $HOME — $ZSKILLS_PATHS_ROOT only overrides the PROJECT
#     root (worktree anchor), never the user tier.
#   - Empty / missing config keys at both tiers → built-in defaults
#     docs/plans | docs/issues | docs/reports (PINNED ≡ zskills-defaults.json
#     by the congruence check in tests/test-skill-conformance.sh; the prior
#     legacy plans/ + .zskills/audit fallbacks were re-specced by Phase 5).
#     Audit dir is always <root>/.zskills/audit.
#   - Resolved values are absolute. Relative paths in config are JOINED
#     with <root> (including paths starting with "../" — they resolve
#     against <root>, NOT the caller's cwd). Absolute paths (starting
#     with "/") are used as-is.
#   - Idempotent — re-sourcing yields the same vars.
#   - Internal vars prefixed `_ZSK_PATHS_` and unset at end.
#   - No stdout (sourceable; would corrupt caller capture). Errors → stderr.
#   - Resolved vars are SET but NOT export-ed. Callers spawning child
#     processes (Python, node) MUST `export ZSKILLS_PLANS_DIR` etc.
#     themselves immediately after sourcing. See caller-side examples below.

# Resolve project root with precedence: ZSKILLS_PATHS_ROOT (PR-mode
# worktree anchor) → CLAUDE_PROJECT_DIR (harness-set) → git-common-dir
# fallback (orchestrator-side Bash where harness didn't inject the var
# — see zskills-resolve-config.sh for the documented-design rationale).
_ZSK_PATHS_ROOT="${ZSKILLS_PATHS_ROOT:-${CLAUDE_PROJECT_DIR:-}}"
if [ -z "$_ZSK_PATHS_ROOT" ]; then
  if _ZSK_PATHS_COMMON_DIR=$(git rev-parse --git-common-dir 2>/dev/null) \
       && _ZSK_PATHS_ROOT=$(cd "$_ZSK_PATHS_COMMON_DIR/.." && pwd); then
    if [ -z "${_ZSK_FALLBACK_WARNED:-}" ]; then
      echo "WARN: zskills: neither ZSKILLS_PATHS_ROOT nor CLAUDE_PROJECT_DIR set; fell back to $_ZSK_PATHS_ROOT via git-common-dir" >&2
      _ZSK_FALLBACK_WARNED=1
    fi
    unset _ZSK_PATHS_COMMON_DIR
  else
    echo "zskills-paths.sh: neither ZSKILLS_PATHS_ROOT nor CLAUDE_PROJECT_DIR is set, and not in a git repo — caller must provide one (absolute path)" >&2
    unset _ZSK_PATHS_COMMON_DIR
    # Use return when sourced, exit when executed (mirror dual-mode pattern
    # from sanitize-pipeline-id.sh).
    (return 0 2>/dev/null) && return 1 || exit 1
  fi
fi

# Lane-portable skills root via env-independent self-location. This script
# lives at <skills_root>/update-zskills/scripts/ on BOTH lanes (plugin:
# ${CLAUDE_PLUGIN_ROOT}/skills/...; legacy: $CLAUDE_PROJECT_DIR/.claude/skills/...),
# so resolving its own dir is lane-agnostic, env-independent, cwd-independent,
# worktree-safe, and symlink-safe (readlink -f). Replaces the broken
# ${CLAUDE_PLUGIN_ROOT:-} guard (the :- form is never harness-substituted and
# is empty in the script env on the plugin lane → mis-resolved mirror-less).
#
# ${BASH_SOURCE[0]:-$0}: SHELL-portable self-location (issue #1149). Claude
# Code's Bash tool runs skill fences under the user's snapshot shell — zsh on
# default macOS/dev setups — where BASH_SOURCE is unset; a bare
# ${BASH_SOURCE[0]} expanded empty and this line silently resolved
# <cwd>/../.. as the skills root. zsh's default FUNCTION_ARGZERO sets $0 to
# the sourced file's path, so the fallback keeps self-location correct there
# (same idiom as sanitize-pipeline-id.sh / claim-*.sh dual-mode detection).
ZSKILLS_SKILLS_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]:-$0}")")/../.." && pwd)"
export ZSKILLS_SKILLS_ROOT

# Pre-init vars to empty (empty-pattern-guard from DRIFT_ARCH_FIX). NOT export.
ZSKILLS_PLANS_DIR=""
ZSKILLS_ISSUES_DIR=""
ZSKILLS_AUDIT_DIR=""
ZSKILLS_REPORTS_DIR=""

_ZSK_PATHS_CFG="$_ZSK_PATHS_ROOT/.claude/zskills-config.json"
_ZSK_PATHS_USER_CFG="${HOME:-}/.claude/zskills-config.json"
_ZSK_PATHS_PLANS_RAW=""
_ZSK_PATHS_ISSUES_RAW=""
_ZSK_PATHS_REPORTS_RAW=""

# Extract the three output.* keys from one config body (any tier). Each
# key's regex is an independent presence test: a match OVERWRITES the RAW
# var, so calling this on the user body first, then the project body,
# implements "project match wins; user fills project-absent keys"
# (INSTALL_REDESIGN Phase 5 two-pass cascade).
#
# Nested-key scoping per zskills-resolve-config.sh idiom (BASH_REMATCH).
# Trailing `[^}]*\}` closing-brace anchor (round-3 reviewer F6): a
# malformed input like `{"output":{"plans_dir":"DROP"}` (missing outer
# `}`) used to match because `[^}]*` greedily consumed past the value;
# the trailing `\}` requires a real close, so unbalanced JSON falls
# back to the built-in defaults instead of yielding a path-shaped string.
_zsk_paths_extract_keys() {
  local _zsk_paths_body="$1"
  if [[ "$_zsk_paths_body" =~ \"output\"[[:space:]]*:[[:space:]]*\{[^}]*\"plans_dir\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"[^}]*\} ]]; then
    _ZSK_PATHS_PLANS_RAW="${BASH_REMATCH[1]}"
  fi
  if [[ "$_zsk_paths_body" =~ \"output\"[[:space:]]*:[[:space:]]*\{[^}]*\"issues_dir\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"[^}]*\} ]]; then
    _ZSK_PATHS_ISSUES_RAW="${BASH_REMATCH[1]}"
  fi
  if [[ "$_zsk_paths_body" =~ \"output\"[[:space:]]*:[[:space:]]*\{[^}]*\"reports_dir\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"[^}]*\} ]]; then
    _ZSK_PATHS_REPORTS_RAW="${BASH_REMATCH[1]}"
  fi
}

# Pass 1: USER tier ($HOME — independent of the project-root override).
if [ -n "${HOME:-}" ] && [ -f "$_ZSK_PATHS_USER_CFG" ]; then
  _ZSK_PATHS_USER_BODY=$(cat "$_ZSK_PATHS_USER_CFG" 2>/dev/null) || _ZSK_PATHS_USER_BODY=""
  _zsk_paths_extract_keys "$_ZSK_PATHS_USER_BODY"
  unset _ZSK_PATHS_USER_BODY
fi

# Pass 2: PROJECT tier (a project match wins over the user tier).
if [ -f "$_ZSK_PATHS_CFG" ]; then
  _ZSK_PATHS_BODY=$(cat "$_ZSK_PATHS_CFG" 2>/dev/null) || _ZSK_PATHS_BODY=""
  _zsk_paths_extract_keys "$_ZSK_PATHS_BODY"
  unset _ZSK_PATHS_BODY
fi
unset -f _zsk_paths_extract_keys

# Both tiers empty (or empty-string value) → built-in defaults (cascade
# tier 3). Values are PINNED ≡ skills/update-zskills/scripts/
# zskills-defaults.json by the congruence check in
# tests/test-skill-conformance.sh; the marker line names the JSON key path.
# (Phase 5 re-spec: the prior legacy fallbacks — plans/ for plans+issues,
# .zskills/audit for reports — are replaced by the canonical docs/ layout
# so zero-config consumers get the documented defaults.)
# zskills-defaults-congruence: output.plans_dir
[ -z "$_ZSK_PATHS_PLANS_RAW" ]   && _ZSK_PATHS_PLANS_RAW="docs/plans"
# zskills-defaults-congruence: output.issues_dir
[ -z "$_ZSK_PATHS_ISSUES_RAW" ]  && _ZSK_PATHS_ISSUES_RAW="docs/issues"
# zskills-defaults-congruence: output.reports_dir
[ -z "$_ZSK_PATHS_REPORTS_RAW" ] && _ZSK_PATHS_REPORTS_RAW="docs/reports"

# Resolve absolute. Only "/" prefix is treated as already-absolute. All
# other forms (including "..", "../..", "../foo") are JOINED with <root>;
# this preserves intent for `plans_dir: "../external/zskills"` (resolves
# to <root>/../external/zskills) and avoids the prior "use as-is" trap
# where "../external/zskills" would resolve against the caller's cwd.
case "$_ZSK_PATHS_PLANS_RAW" in
  /*) ZSKILLS_PLANS_DIR="$_ZSK_PATHS_PLANS_RAW" ;;
  *)  ZSKILLS_PLANS_DIR="$_ZSK_PATHS_ROOT/$_ZSK_PATHS_PLANS_RAW" ;;
esac
case "$_ZSK_PATHS_ISSUES_RAW" in
  /*) ZSKILLS_ISSUES_DIR="$_ZSK_PATHS_ISSUES_RAW" ;;
  *)  ZSKILLS_ISSUES_DIR="$_ZSK_PATHS_ROOT/$_ZSK_PATHS_ISSUES_RAW" ;;
esac
ZSKILLS_AUDIT_DIR="$_ZSK_PATHS_ROOT/.zskills/audit"
case "$_ZSK_PATHS_REPORTS_RAW" in
  /*) ZSKILLS_REPORTS_DIR="$_ZSK_PATHS_REPORTS_RAW" ;;
  *)  ZSKILLS_REPORTS_DIR="$_ZSK_PATHS_ROOT/$_ZSK_PATHS_REPORTS_RAW" ;;
esac

unset _ZSK_PATHS_ROOT _ZSK_PATHS_CFG _ZSK_PATHS_USER_CFG _ZSK_PATHS_PLANS_RAW _ZSK_PATHS_ISSUES_RAW _ZSK_PATHS_REPORTS_RAW
