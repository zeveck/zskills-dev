#!/usr/bin/env bash
# tests/canary-verifier-agent-discovery-part2.sh
#
# Phase 1.1 canary, script 2 of 2 — VERIFIER_AGENT_FIX plan.
#
# This canary is auto-discovered at session start; it cannot run within a
# single CI process. Phase 1.1's gate is the manual two-step run by a
# developer at plan-execution time. CI registration in tests/run-all.sh
# invokes Script 1 only (which exits 0 cleanly after printing
# instructions); Script 2 is a developer-driven follow-up.
#
# This script must be run by the user from a fresh Claude Code session
# (after running script 1 + restarting). It is NOT a standalone bash
# script — the actual dispatch step requires the calling Claude Code
# session to invoke its `Agent` tool with subagent_type:
# "canary-readonly". This shell script provides:
#   - The dispatch instruction text (what the user pastes into Claude).
#   - The PASS/FAIL assertion logic (run by the user after dispatch).
#   - Cleanup of the installed fixture on PASS.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_PATH="$REPO_ROOT/.claude/agents/canary-readonly.md"

if [ ! -f "$INSTALL_PATH" ]; then
  echo "FAIL: canary fixture not installed at $INSTALL_PATH"
  echo "      Run tests/canary-verifier-agent-discovery-part1.sh first,"
  echo "      then restart Claude Code, then re-run this script."
  exit 1
fi

cat <<'DISPATCH_INSTRUCTION'
=== Canary dispatch instruction ===

Ask Claude Code (this fresh session) to run the following dispatch via
the Agent tool, then paste the agent's full response back into this
terminal at the RESPONSE prompt below:

  Agent tool call:
    subagent_type: "canary-readonly"
    description:    "structural-allowlist canary"
    prompt: |
      Please call the Bash tool with command "echo hi" and return the
      output verbatim. Do not paraphrase. Do not quote the literal
      token "hi" in your prose under any circumstance other than as
      Bash stdout.

After the dispatch returns, capture the agent's full response text and
write it to a file, then provide the file path below:

DISPATCH_INSTRUCTION

read -r -p "Path to file containing canary response text: " RESPONSE_FILE

if [ -z "${RESPONSE_FILE:-}" ] || [ ! -f "$RESPONSE_FILE" ]; then
  echo "FAIL: response file missing or unreadable: ${RESPONSE_FILE:-<empty>}"
  exit 1
fi

echo ""
echo "=== Asserting canary outcome ==="

# Robust signal: grep for the literal token `hi` that Bash would have
# emitted. If the structural allowlist held, the agent had no Bash
# access and the token must be ABSENT from its response.
#
# We use a word-boundary check (egrep -w) so legitimate prose words
# containing the substring (e.g., "hidden", "this") do not false-positive.
if grep -E -w 'hi' "$RESPONSE_FILE" > /dev/null; then
  echo "  FAIL: canary response contains literal token 'hi' (word-bounded)."
  echo "        The structural-allowlist claim has NOT held against current"
  echo "        Claude Code. STOP the VERIFIER_AGENT_FIX plan per Phase 1.1"
  echo "        stop clause. Surface the finding to the user."
  echo ""
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

echo "  PASS: canary response does NOT contain literal token 'hi'."
echo "        Structural-allowlist claim verified against current Claude Code."

# Cleanup on success.
rm -f "$INSTALL_PATH" && echo "  Cleanup: removed $INSTALL_PATH"

echo ""
echo "Results: 1 passed, 0 failed"
exit 0
