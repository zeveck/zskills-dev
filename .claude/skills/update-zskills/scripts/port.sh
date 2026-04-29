#!/bin/bash
# port.sh -- deterministic dev-server port for the current project root.
#
# Main repo (dev_server.main_repo_path, read at runtime from
# .claude/zskills-config.json) -> dev_server.default_port (default 8080).
# Worktrees -> stable port in 9000-60000 derived from the project root path.
# DEV_PORT env var overrides everything.
#
# Usage:  bash $(basename "$0")   (prints port to stdout)
#
# Precedence: DEV_PORT env -> dev-port.sh stub (consumer-provided) ->
# dev_server.default_port (main-repo branch; fail-loud if absent) -> worktree-hash.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# PROJECT_ROOT must come from the invocation context, not the script
# location. After the move into skills/update-zskills/scripts/, the script
# can be invoked from any consumer repo via the shipped .claude/skills/
# tree, so $SCRIPT_DIR/.. would point inside the skill bundle, not the
# repo root. Use git rev-parse --show-toplevel; fall back to PWD when
# invoked outside a git repo.
PROJECT_ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

DEFAULT_PORT=""
RANGE_START=9000
RANGE_SIZE=51000  # 9000-60000

# ─── Runtime config read (eliminates install-time drift) ───
# Read dev_server.main_repo_path AND dev_server.default_port from the
# checked-out config. PROJECT_ROOT IS the repo root, so the config lives
# at $PROJECT_ROOT/.claude/zskills-config.json.
_ZSK_REPO_ROOT="${REPO_ROOT:-$PROJECT_ROOT}"
_ZSK_CFG="$_ZSK_REPO_ROOT/.claude/zskills-config.json"
MAIN_REPO=""
if [ -f "$_ZSK_CFG" ]; then
  _ZSK_CFG_BODY=$(cat "$_ZSK_CFG" 2>/dev/null) || _ZSK_CFG_BODY=""
  # Scope to dev_server.main_repo_path via enclosing "dev_server" object.
  if [[ "$_ZSK_CFG_BODY" =~ \"dev_server\"[[:space:]]*:[[:space:]]*\{[^}]*\"main_repo_path\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    MAIN_REPO="${BASH_REMATCH[1]}"
  fi
  # Same scoping pattern: extract dev_server.default_port (numeric).
  if [[ "$_ZSK_CFG_BODY" =~ \"dev_server\"[[:space:]]*:[[:space:]]*\{[^{}]*\"default_port\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
    DEFAULT_PORT="${BASH_REMATCH[1]}"
  fi
  unset _ZSK_CFG_BODY
fi

# DEV_PORT env var overrides everything
if [[ -n "$DEV_PORT" ]]; then
  echo "$DEV_PORT"
  exit 0
fi

# ─── Consumer dev-port.sh callout (stub-callout convention) ───
_STUB_LIB="${CLAUDE_PROJECT_DIR:-$PROJECT_ROOT}/.claude/skills/update-zskills/scripts/zskills-stub-lib.sh"
if [ -f "$_STUB_LIB" ]; then
  # shellcheck disable=SC1090
  . "$_STUB_LIB"
  zskills_dispatch_stub dev-port.sh "$PROJECT_ROOT" -- \
    "$PROJECT_ROOT" "$MAIN_REPO"
  if [ "${ZSKILLS_STUB_INVOKED:-0}" = "1" ] && [ "${ZSKILLS_STUB_RC:-0}" -eq 0 ]; then
    # Trim leading/trailing whitespace; require a positive
    # integer (no leading zero, no embedded newlines, rejects
    # bare "0" which is not a valid TCP port).
    _PORT_TRIMMED="${ZSKILLS_STUB_STDOUT#"${ZSKILLS_STUB_STDOUT%%[![:space:]]*}"}"
    _PORT_TRIMMED="${_PORT_TRIMMED%"${_PORT_TRIMMED##*[![:space:]]}"}"
    if [[ "$_PORT_TRIMMED" =~ ^[1-9][0-9]+$ ]]; then
      echo "$_PORT_TRIMMED"
      exit 0
    elif [ -n "$_PORT_TRIMMED" ]; then
      echo "zskills: dev-port.sh returned non-numeric/invalid stdout '$ZSKILLS_STUB_STDOUT'; falling through to built-in" >&2
    fi
    # empty stdout = silent fall-through (no warning)
    unset _PORT_TRIMMED
  fi
  # non-zero rc from stub: also fall through (warning emitted by lib)
elif [ -n "$CLAUDE_PROJECT_DIR" ]; then
  echo "port.sh: stub-lib missing at $_STUB_LIB; consumer stubs disabled. Run /update-zskills to repair." >&2
fi
unset _STUB_LIB

# Main repo gets the default port
if [[ -n "$MAIN_REPO" ]] && [[ "$PROJECT_ROOT" == "$MAIN_REPO" ]]; then
  if [[ -z "$DEFAULT_PORT" ]]; then
    echo "port.sh: dev_server.default_port not set in $_ZSK_CFG. Open this repo in Claude Code and run /update-zskills (a Claude Code slash command, not a shell command) to backfill the field, or set DEV_PORT=NNNN env var to override per-invocation." >&2
    exit 1
  fi
  echo "$DEFAULT_PORT"
  exit 0
fi
unset _ZSK_REPO_ROOT _ZSK_CFG

# Worktrees get a deterministic port from their path hash
# Use cksum for portability (POSIX, available everywhere bash is)
HASH=$(printf '%s' "$PROJECT_ROOT" | cksum | awk '{print $1}')
PORT=$(( RANGE_START + (HASH % RANGE_SIZE) ))
echo "$PORT"
