#!/usr/bin/env bash
# tests/canary-verifier-agent-discovery-part1.sh
#
# Phase 1.1 canary, script 1 of 2 — VERIFIER_AGENT_FIX plan.
#
# This canary is auto-discovered at session start; it cannot run within a
# single CI process. Phase 1.1's gate is the manual two-step run by a
# developer at plan-execution time. CI registration in tests/run-all.sh
# invokes Script 1 only (which exits 0 cleanly after printing
# instructions); Script 2 is a developer-driven follow-up.
#
# What this script does:
#   1. Copies the fixture agent definition from
#      tests/fixtures/canary-agents/canary-readonly.md to
#      .claude/agents/canary-readonly.md so the next Claude Code session
#      auto-discovers it at start.
#   2. Prints the verbatim restart instruction to stdout.
#   3. Exits 0. Script 1 does NOT dispatch.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FIXTURE="$REPO_ROOT/tests/fixtures/canary-agents/canary-readonly.md"
INSTALL_DIR="$REPO_ROOT/.claude/agents"
INSTALL_PATH="$INSTALL_DIR/canary-readonly.md"

if [ ! -f "$FIXTURE" ]; then
  echo "ERROR: canary fixture missing: $FIXTURE" >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
cp "$FIXTURE" "$INSTALL_PATH"

# Verify install
if [ ! -f "$INSTALL_PATH" ]; then
  echo "ERROR: failed to install canary fixture to $INSTALL_PATH" >&2
  exit 1
fi

echo "Canary fixture installed: $INSTALL_PATH"
echo ""
cat <<'INSTRUCTION'
This canary requires a fresh Claude Code session — `.claude/agents/`
is auto-discovered only at session start (priority 3, per
code.claude.com/docs/en/sub-agents). Restart Claude Code now (or
open a new session) and run:
    bash tests/canary-verifier-agent-discovery-part2.sh
INSTRUCTION

exit 0
