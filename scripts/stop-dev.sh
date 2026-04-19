#!/bin/bash
# stop-dev.sh — Stop this worktree's dev server cleanly (SIGTERM only).
#
# Reads one PID per line from var/dev.pid (written by your `npm run dev`
# or equivalent) and sends SIGTERM to each, then waits briefly to confirm
# they exited. Does NOT escalate to SIGKILL — if a process ignores
# SIGTERM, report and fail; that escalation stays a user decision.
#
# This is the approved way to stop a dev server. The generic hook blocks
# `kill -9`, `killall`, `pkill`, `fuser -k` (they can hit other sessions'
# dev servers and container-critical processes). SIGTERM, scoped to PIDs
# your own dev server recorded, is safe and not blocked.
#
# Exit codes:
#   0 — all PIDs stopped (or no PID file, i.e. dev server not running)
#   1 — one or more PIDs still running after the grace period

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PID_FILE="$PROJECT_ROOT/var/dev.pid"
GRACE_SECONDS="${STOP_DEV_GRACE_SECONDS:-5}"

BOLD='\033[1m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

if [ ! -f "$PID_FILE" ]; then
  echo "dev server not running (no $PID_FILE)"
  exit 0
fi

# Collect PIDs (one per line, skip blanks and non-numeric)
PIDS=()
while IFS= read -r line || [ -n "$line" ]; do
  # Strip whitespace
  pid="${line//[[:space:]]/}"
  [ -z "$pid" ] && continue
  if [[ "$pid" =~ ^[0-9]+$ ]]; then
    PIDS+=("$pid")
  else
    printf "${YELLOW}warn${RESET}: skipping non-numeric entry: %q\n" "$line"
  fi
done < "$PID_FILE"

if [ "${#PIDS[@]}" -eq 0 ]; then
  echo "dev server not running (no PIDs in $PID_FILE)"
  rm -f "$PID_FILE"
  exit 0
fi

printf "${BOLD}stopping %d dev-server PID(s) with SIGTERM${RESET}\n" "${#PIDS[@]}"

LIVE_PIDS=()
for pid in "${PIDS[@]}"; do
  if ! kill -0 "$pid" 2>/dev/null; then
    printf "  %s: ${YELLOW}already gone${RESET}\n" "$pid"
    continue
  fi
  if kill -TERM "$pid" 2>/dev/null; then
    printf "  %s: SIGTERM sent\n" "$pid"
    LIVE_PIDS+=("$pid")
  else
    printf "  %s: ${RED}SIGTERM failed${RESET} (permission denied or race)\n" "$pid"
  fi
done

# Grace period: poll up to GRACE_SECONDS for each live PID to exit
STILL_RUNNING=()
if [ "${#LIVE_PIDS[@]}" -gt 0 ]; then
  deadline=$(( $(date +%s) + GRACE_SECONDS ))
  remaining=("${LIVE_PIDS[@]}")
  while [ "${#remaining[@]}" -gt 0 ] && [ "$(date +%s)" -lt "$deadline" ]; do
    sleep 1
    next=()
    for pid in "${remaining[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then
        next+=("$pid")
      fi
    done
    remaining=("${next[@]}")
  done
  STILL_RUNNING=("${remaining[@]}")
fi

if [ "${#STILL_RUNNING[@]}" -gt 0 ]; then
  printf "${RED}still running after %ds:${RESET}\n" "$GRACE_SECONDS"
  for pid in "${STILL_RUNNING[@]}"; do
    printf "  %s\n" "$pid"
  done
  printf "${YELLOW}not escalating to SIGKILL.${RESET} Ask the user to stop these manually.\n"
  exit 1
fi

printf "${GREEN}all dev-server PIDs stopped${RESET}\n"
rm -f "$PID_FILE"
exit 0
