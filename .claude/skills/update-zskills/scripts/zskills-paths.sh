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
#   - Empty / missing config keys → fall back to LEGACY <root>/plans for
#     PLANS_DIR and ISSUES_DIR. Audit dir is always <root>/.zskills/audit.
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

# Lane-portable skills root. Plugin: the plugin tree (never a worktree). Legacy: the consumer
# mirror under $CLAUDE_PROJECT_DIR — anchored on CLAUDE_PROJECT_DIR (NOT ZSKILLS_PATHS_ROOT),
# matching today's hardcoded `$CLAUDE_PROJECT_DIR/.claude/skills/...` invocation behavior.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}/skills" ]; then
  ZSKILLS_SKILLS_ROOT="${CLAUDE_PLUGIN_ROOT}/skills"
else
  ZSKILLS_SKILLS_ROOT="${CLAUDE_PROJECT_DIR:-}/.claude/skills"
fi
export ZSKILLS_SKILLS_ROOT

# Pre-init vars to empty (empty-pattern-guard from DRIFT_ARCH_FIX). NOT export.
ZSKILLS_PLANS_DIR=""
ZSKILLS_ISSUES_DIR=""
ZSKILLS_AUDIT_DIR=""
ZSKILLS_REPORTS_DIR=""

_ZSK_PATHS_CFG="$_ZSK_PATHS_ROOT/.claude/zskills-config.json"
_ZSK_PATHS_PLANS_RAW=""
_ZSK_PATHS_ISSUES_RAW=""
_ZSK_PATHS_REPORTS_RAW=""

if [ -f "$_ZSK_PATHS_CFG" ]; then
  _ZSK_PATHS_BODY=$(cat "$_ZSK_PATHS_CFG" 2>/dev/null) || _ZSK_PATHS_BODY=""
  # Nested-key scoping per zskills-resolve-config.sh idiom (BASH_REMATCH).
  # Trailing `[^}]*\}` closing-brace anchor (round-3 reviewer F6): a
  # malformed input like `{"output":{"plans_dir":"DROP"}` (missing outer
  # `}`) used to match because `[^}]*` greedily consumed past the value;
  # the trailing `\}` requires a real close, so unbalanced JSON falls
  # back to legacy plans/ instead of yielding a path-shaped string.
  if [[ "$_ZSK_PATHS_BODY" =~ \"output\"[[:space:]]*:[[:space:]]*\{[^}]*\"plans_dir\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"[^}]*\} ]]; then
    _ZSK_PATHS_PLANS_RAW="${BASH_REMATCH[1]}"
  fi
  if [[ "$_ZSK_PATHS_BODY" =~ \"output\"[[:space:]]*:[[:space:]]*\{[^}]*\"issues_dir\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"[^}]*\} ]]; then
    _ZSK_PATHS_ISSUES_RAW="${BASH_REMATCH[1]}"
  fi
  if [[ "$_ZSK_PATHS_BODY" =~ \"output\"[[:space:]]*:[[:space:]]*\{[^}]*\"reports_dir\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"[^}]*\} ]]; then
    _ZSK_PATHS_REPORTS_RAW="${BASH_REMATCH[1]}"
  fi
  unset _ZSK_PATHS_BODY
fi

# Empty config (or empty-string value) → LEGACY plans/ for plans_dir +
# issues_dir; LEGACY .zskills/audit for reports_dir (silent back-compat —
# pre-migration consumers wrote work-trail reports there, so their existing
# .zskills/audit/plan-*.md writes continue working unchanged when the
# config key is absent or empty).
[ -z "$_ZSK_PATHS_PLANS_RAW" ]   && _ZSK_PATHS_PLANS_RAW="plans"
[ -z "$_ZSK_PATHS_ISSUES_RAW" ]  && _ZSK_PATHS_ISSUES_RAW="plans"
[ -z "$_ZSK_PATHS_REPORTS_RAW" ] && _ZSK_PATHS_REPORTS_RAW=".zskills/audit"

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

unset _ZSK_PATHS_ROOT _ZSK_PATHS_CFG _ZSK_PATHS_PLANS_RAW _ZSK_PATHS_ISSUES_RAW _ZSK_PATHS_REPORTS_RAW
