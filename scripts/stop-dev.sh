#!/bin/bash
# stop-dev.sh -- Sanctioned way to stop your dev server.
#
# CONFIGURE: replace the body below with your stop logic.
# Contract: read PIDs from var/dev.pid (one per line) and
# SIGTERM each. Pair with scripts/start-dev.sh which writes
# to var/dev.pid on start.
#
# NEVER use kill -9, killall, pkill, or fuser -k -- the
# generic hook blocks them and they can hit other sessions'
# processes.
#
# See .claude/skills/update-zskills/references/stub-callouts.md.

echo "stop-dev.sh: not configured. Edit scripts/stop-dev.sh with your dev-stop command (read PIDs from var/dev.pid; kill -TERM each). See .claude/skills/update-zskills/references/stub-callouts.md." >&2
exit 1
