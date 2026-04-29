#!/bin/bash
# start-dev.sh -- Sanctioned way to start your dev server.
#
# CONFIGURE: replace the body below with your start command.
# Contract: write each child PID to var/dev.pid (one per line)
# on start. var/ is gitignored.
#
# Example:
#   mkdir -p var
#   npm run dev > var/dev.log 2>&1 &
#   echo $! > var/dev.pid
#
# Pair: scripts/stop-dev.sh reads var/dev.pid and SIGTERMs each
# PID. See .claude/skills/update-zskills/references/stub-callouts.md.

echo "start-dev.sh: not configured. Edit scripts/start-dev.sh with your dev-start command (and write child PIDs to var/dev.pid)." >&2
exit 1
