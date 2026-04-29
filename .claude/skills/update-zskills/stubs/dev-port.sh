#!/bin/bash
# dev-port.sh -- override port derivation for this project.
# Print the desired port to stdout and exit 0; or exit 0 with
# empty stdout to fall through to the built-in algorithm
# (8080 for main repo; deterministic hash 9000-60000 per
# worktree).
#
# Arguments (positional):
#   $1  PROJECT_ROOT  current project root
#   $2  MAIN_REPO     configured main_repo_path (or "")
#
# Example: derive port from a `.port` file at the project root.
#
#   if [ -f "$1/.port" ]; then
#     cat "$1/.port"
#   fi
#
# See .claude/skills/update-zskills/references/stub-callouts.md.
exit 0
