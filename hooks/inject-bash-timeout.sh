#!/usr/bin/env bash
# inject-bash-timeout.sh — PreToolUse hook for Bash (verifier subagent).
#
# Layer 0 of the VERIFIER_AGENT_FIX D'' architecture. Ensures `timeout` is at
# least 600000 ms (10 minutes) on every Bash call so test-suite invocations
# do not hit the default 120s tool timeout. The 120s timeout was the root
# cause of the bg+Monitor recovery reflex that hung verifier dispatches
# (see plans/VERIFIER_AGENT_FIX.md).
#
# Reads the full PreToolUse JSON envelope from stdin. If the embedded
# `tool_input.timeout` is already >= 600000, allow as-is (no `updatedInput`).
# Otherwise return permissionDecision=allow with `updatedInput` preserving
# all original tool_input fields and setting `timeout: 600000`.
#
# Implementation note: the `command` field can contain arbitrary quotes,
# backslashes, and newlines that are awkward to round-trip through pure
# bash regex. We use python3 for the JSON parse + reserialize to keep the
# escaping correct. Per zskills convention: no jq; python is acceptable
# in hook scripts when bash JSON construction would be brittle.
#
# Stdin shape: PreToolUse harness envelopes vary. Two supported shapes —
#   1. The full envelope `{"tool_name":"Bash","tool_input":{...},...}`
#   2. The bare tool_input object `{"command":"...","timeout":...}`
# We auto-detect: if the parsed JSON has a "tool_input" dict, use it;
# otherwise treat the whole object as the tool_input. This keeps the
# hook usable from both the live harness and direct unit tests.

set -u

INPUT=$(cat)
MIN_TIMEOUT=600000

# Cheap pre-check: if the input already names a sufficient timeout, skip
# python entirely. The bash regex is approximate (matches anywhere in the
# JSON) which is fine — the only risk is a false-positive on a `command`
# field literally containing `"timeout":600000`, which is harmless because
# we'd then allow a Bash call that already had its own large timeout.
CURRENT_TIMEOUT=0
if [[ "$INPUT" =~ \"timeout\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
  CURRENT_TIMEOUT="${BASH_REMATCH[1]}"
fi

if [ "$CURRENT_TIMEOUT" -ge "$MIN_TIMEOUT" ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
  exit 0
fi

# Need to inject. Round-trip via python3 for correct JSON escaping.
# We pass MIN_TIMEOUT as an env var (stdin must stay free for the JSON
# envelope; argv-vs-stdin separation is what `python3 -c` gets us).
PY_OUT=$(printf '%s' "$INPUT" | MIN_TIMEOUT="$MIN_TIMEOUT" python3 -c '
import json, os, sys
min_timeout = int(os.environ["MIN_TIMEOUT"])
raw = sys.stdin.read()
try:
    env = json.loads(raw)
except Exception:
    sys.stdout.write("{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"allow\"}}")
    sys.exit(0)
if isinstance(env, dict) and isinstance(env.get("tool_input"), dict):
    tool_input = env["tool_input"]
elif isinstance(env, dict):
    tool_input = env
else:
    tool_input = {}
updated = dict(tool_input)
updated["timeout"] = min_timeout
out = {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow", "updatedInput": updated}}
sys.stdout.write(json.dumps(out))
' 2>/dev/null)

if [ -z "$PY_OUT" ]; then
  # python failed (missing python3 / parse error / unexpected). Permissive
  # fallback: allow as-is. Layer 3 (verify-response-validate.sh) catches
  # any downstream verifier failure regardless.
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
  exit 0
fi

printf '%s' "$PY_OUT"
exit 0
