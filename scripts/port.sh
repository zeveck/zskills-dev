#!/bin/bash
# port.sh -- deterministic dev-server port for the current project root.
#
# Main repo ({{MAIN_REPO_PATH}}) -> 8080 (backward compatible).
# Worktrees -> stable port in 9000-60000 derived from the project root path.
# DEV_PORT env var overrides everything.
#
# Usage:  bash scripts/port.sh   (prints port to stdout)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MAIN_REPO='{{MAIN_REPO_PATH}}'
DEFAULT_PORT=8080
RANGE_START=9000
RANGE_SIZE=51000  # 9000-60000

# DEV_PORT env var overrides everything
if [[ -n "$DEV_PORT" ]]; then
  echo "$DEV_PORT"
  exit 0
fi

# Main repo gets the default port
if [[ "$MAIN_REPO" != '{{MAIN_REPO_PATH}}' ]] && [[ "$PROJECT_ROOT" == "$MAIN_REPO" ]]; then
  echo "$DEFAULT_PORT"
  exit 0
fi

# Worktrees get a deterministic port from their path hash
# Use cksum for portability (POSIX, available everywhere bash is)
HASH=$(printf '%s' "$PROJECT_ROOT" | cksum | awk '{print $1}')
PORT=$(( RANGE_START + (HASH % RANGE_SIZE) ))
echo "$PORT"
