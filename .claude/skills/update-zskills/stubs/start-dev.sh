#!/bin/bash
# start-dev.sh -- Sanctioned way to start your dev server.
#
# CONFIGURE: replace the body below with your start command.
# Contract: write each child PID to .zskills/dev-server.pid (one per line)
# on start. .zskills/ is gitignored.
#
# Example:
#   mkdir -p .zskills
#   npm run dev > .zskills/dev-server.log 2>&1 &
#   echo $! > .zskills/dev-server.pid
#
# Pair: scripts/stop-dev.sh reads .zskills/dev-server.pid and SIGTERMs each
# PID. See .claude/skills/update-zskills/references/stub-callouts.md.

echo "start-dev.sh: not configured. Edit scripts/start-dev.sh with your dev-start command (and write child PIDs to .zskills/dev-server.pid)." >&2
exit 1
