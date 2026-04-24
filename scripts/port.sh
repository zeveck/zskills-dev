#!/bin/bash
# port.sh -- deterministic dev-server port for the current project root.
#
# Main repo (dev_server.main_repo_path, read at runtime from
# .claude/zskills-config.json) -> 8080 (backward compatible).
# Worktrees -> stable port in 9000-60000 derived from the project root path.
# DEV_PORT env var overrides everything.
#
# Usage:  bash scripts/port.sh   (prints port to stdout)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── Runtime config read (eliminates install-time drift) ───
# Read dev_server.main_repo_path from the checked-out config.
_ZSK_REPO_ROOT="${REPO_ROOT:-$(git -C "$PROJECT_ROOT" rev-parse --show-toplevel 2>/dev/null || echo "$PROJECT_ROOT")}"
_ZSK_CFG="$_ZSK_REPO_ROOT/.claude/zskills-config.json"
MAIN_REPO=""
if [ -f "$_ZSK_CFG" ]; then
  _ZSK_CFG_BODY=$(cat "$_ZSK_CFG" 2>/dev/null) || _ZSK_CFG_BODY=""
  # Scope to dev_server.main_repo_path via enclosing "dev_server" object.
  if [[ "$_ZSK_CFG_BODY" =~ \"dev_server\"[[:space:]]*:[[:space:]]*\{[^}]*\"main_repo_path\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    MAIN_REPO="${BASH_REMATCH[1]}"
  fi
  unset _ZSK_CFG_BODY
fi
unset _ZSK_REPO_ROOT _ZSK_CFG

DEFAULT_PORT=8080
RANGE_START=9000
RANGE_SIZE=51000  # 9000-60000

# DEV_PORT env var overrides everything
if [[ -n "$DEV_PORT" ]]; then
  echo "$DEV_PORT"
  exit 0
fi

# Main repo gets the default port
if [[ -n "$MAIN_REPO" ]] && [[ "$PROJECT_ROOT" == "$MAIN_REPO" ]]; then
  echo "$DEFAULT_PORT"
  exit 0
fi

# Worktrees get a deterministic port from their path hash
# Use cksum for portability (POSIX, available everywhere bash is)
HASH=$(printf '%s' "$PROJECT_ROOT" | cksum | awk '{print $1}')
PORT=$(( RANGE_START + (HASH % RANGE_SIZE) ))
echo "$PORT"
