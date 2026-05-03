#!/usr/bin/env bash
# hooks/validate-bash-no-background.sh
#
# PreToolUse hook for the verifier and commit-reviewer subagents.
# Rejects any Bash tool_input where `run_in_background` is `true`.
#
# Why: wake events for backgrounded processes do not reliably deliver to
# one-shot subagent dispatches; the verifier ends its turn waiting for a
# Monitor signal that never arrives, and the orchestrator concludes
# "tests not meaningfully runnable" — a verification FAIL silently
# routed around. See VERIFIER_AGENT_FIX plan, Phase 1.4.
#
# Strategy: bash regex only (no jq). Match the literal JSON key
# "run_in_background": true at OBJECT-KEY positions only — the leading
# [{,] character class anchors the match after either the object opener
# `{` or an inter-key separator `,`. This prevents content-only matches
# (e.g., echo of a string containing the literal substring) from
# triggering the block.
set -euo pipefail

INPUT="$(cat)"

# Match "run_in_background": true ONLY at JSON object-key positions.
# The leading [{,] requires the key be at top level OR after a sibling key.
# Whitespace-tolerant. Case-sensitive 'true' (per JSON spec).
if [[ "$INPUT" =~ [\{,][[:space:]]*\"run_in_background\"[[:space:]]*:[[:space:]]*true([[:space:]]|,|\}) ]]; then
  cat <<'JSON'
{
  "decision": "block",
  "reason": "Bash(run_in_background: true) is forbidden in this subagent. Wake events for background processes do not reliably deliver to one-shot subagent dispatches; foreground-Bash with explicit timeout: 600000 and capture output to a file. See skills/verify-changes/SKILL.md and CLAUDE.md (verifier-cannot-run rule)."
}
JSON
  exit 0
fi

# Default: allow (emit no decision).
exit 0
