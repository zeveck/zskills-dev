#!/usr/bin/env bash
# zskills-hook-version: 2026.06.9
# inject-bash-timeout.sh — PreToolUse hook for Bash (verifier/implementer).
#
# Layer 0 of the VERIFIER_AGENT_FIX D'' architecture. Ensures `timeout` is at
# least 600000 ms (10 minutes) on every Bash call so test-suite invocations
# do not hit the default 120s tool timeout. The 120s timeout was the root
# cause of the bg+Monitor recovery reflex that hung verifier dispatches
# (see plans/VERIFIER_AGENT_FIX.md).
#
# Delivery (INSTALL_REDESIGN Phase 2, branch T-A) — the SAME byte-identical
# script serves BOTH lanes:
#   - Legacy /update-zskills lane: declared in the verifier/implementer
#     agent FRONTMATTER (.claude/agents/{verifier,implementer}.md), invoking
#     $CLAUDE_PROJECT_DIR/.claude/hooks/inject-bash-timeout.sh. That stdin
#     carries NO agent-identity field — absent identity ⇒ EXTEND below, which
#     is exactly right: a frontmatter-declared call IS a verifier/implementer
#     call by construction.
#   - Plugin lane: registered in hooks/hooks.json (PreToolUse/Bash), invoking
#     ${CLAUDE_PLUGIN_ROOT}/hooks/inject-bash-timeout.sh. hooks.json hooks
#     fire on EVERY Bash call (orchestrator + every subagent) and the stdin
#     envelope carries a top-level `agent_type` on subagent calls (Phase 1
#     claim-2 finding: bare name for project agents, PLUGIN-SCOPED, e.g.
#     `zs:verifier`, for plugin agents; ABSENT on orchestrator main-thread
#     calls). The T-A identity filter below extends {verifier, implementer}
#     (matched by basename, so both `verifier` and `zs:verifier` forms pass),
#     passes FOREIGN agents through unmodified, and extends identity-less
#     calls (orchestrator widening = accepted T-B-equivalent semantics; the
#     legacy frontmatter path rides the same absent⇒EXTEND rule).
#   On a dual-delivery consumer (frontmatter AND hooks.json both firing for
#   one Bash call) the double-fire is idempotent: setting timeout=600000
#   twice produces the same envelope.
#
# Reads the full PreToolUse JSON envelope from stdin. If the embedded
# `tool_input.timeout` is already >= 600000, allow as-is (no `updatedInput`).
# If a top-level `agent_type` names a FOREIGN agent (basename not in
# {verifier, implementer}), allow as-is (pass through, no `updatedInput`).
# Otherwise return permissionDecision=allow with `updatedInput` preserving
# all original tool_input fields and setting `timeout: 600000`.
#
# Implementation note: the `command` field can contain arbitrary quotes,
# backslashes, and newlines that are awkward to round-trip through pure
# bash regex. We use Python for the JSON parse + reserialize to keep the
# escaping correct. Per zskills convention: no jq; python is acceptable
# in hook scripts when bash JSON construction would be brittle. The
# interpreter is resolved via zskills_resolve_python: $ZSKILLS_PYTHON (env
# override, for Windows / non-standard distros) → `python3` → `python`, each
# candidate probe-RUN so a non-executable MS Store stub is skipped.
#
# Stdin shape: PreToolUse harness envelopes vary. Two supported shapes —
#   1. The full envelope `{"tool_name":"Bash","tool_input":{...},...}`
#   2. The bare tool_input object `{"command":"...","timeout":...}`
# We auto-detect: if the parsed JSON has a "tool_input" dict, use it;
# otherwise treat the whole object as the tool_input. This keeps the
# hook usable from both the live harness and direct unit tests.

set -u

# D16(a) conditional-skip shim — defers to a settings.json-registered
# same-basename sibling on a dual-lane consumer. The legacy lane delivers
# this script via agent FRONTMATTER (never settings.json), so the shim
# no-ops there; sourcing it keeps the "every hooks.json hook sources the
# shim" integrity gate (test-plugin-hooks-integrity.sh Gap 2) exclusion-free.
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_lib/plugin-hook-skip-if-mirrored.sh" ] && source "${CLAUDE_PLUGIN_ROOT}/hooks/_lib/plugin-hook-skip-if-mirrored.sh"

# zskills_resolve_python — print path to a working Python 3 interpreter, or
# empty if none. Probe-RUNS each candidate (existence is NOT enough: on Windows
# `command -v python3` finds the MS Store App-Execution-Alias stub, which exits
# non-zero when run). Honors ZSKILLS_PYTHON. Rejects python2.
zskills_resolve_python() {
  local cand
  for cand in "${ZSKILLS_PYTHON:-}" python3 python; do
    [ -n "$cand" ] || continue
    command -v "$cand" >/dev/null 2>&1 || continue
    if "$cand" -c 'import sys; sys.exit(0 if sys.version_info[0]==3 else 1)' >/dev/null 2>&1; then
      command -v "$cand"; return 0
    fi
  done
  return 1
}

# Resolve a WORKING Python 3 interpreter once. A failed probe yields empty
# (NOT the MS Store stub path), so the [ -n "$PYTHON" ] guard below is honest.
PYTHON="$(zskills_resolve_python || true)"
# Layer 0 MUST fail-OPEN: a PreToolUse hook that `exit 1`s can block the Bash
# call it was meant to assist. With no working Python we cannot inject the
# timeout, so emit a bare allow and let the call proceed unmodified.
if [ -z "$PYTHON" ]; then
  echo "inject-bash-timeout.sh: WARN no working Python 3 found; timeout not injected — set ZSKILLS_PYTHON" >&2
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
  exit 0
fi

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
PY_OUT=$(printf '%s' "$INPUT" | MIN_TIMEOUT="$MIN_TIMEOUT" "$PYTHON" -c '
import json, os, sys
min_timeout = int(os.environ["MIN_TIMEOUT"])
raw = sys.stdin.read()
try:
    env = json.loads(raw)
except Exception:
    sys.stdout.write("{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"allow\"}}")
    sys.exit(0)
agent_type = None
if isinstance(env, dict) and isinstance(env.get("tool_input"), dict):
    tool_input = env["tool_input"]
    # Identity lives at the TOP LEVEL of the full harness envelope (Phase 1
    # claim-2 finding), never inside tool_input. Only read it from the full
    # envelope shape; the bare tool_input shape is by construction a direct
    # unit-test / frontmatter-style call with no identity (absent => extend).
    agent_type = env.get("agent_type")
elif isinstance(env, dict):
    tool_input = env
else:
    tool_input = {}
# T-A identity filter (INSTALL_REDESIGN Phase 2):
#   absent / non-string  => EXTEND (orchestrator main-thread calls carry no
#                           agent_type — accepted T-B-equivalent widening —
#                           and the legacy frontmatter path is identity-less
#                           by construction);
#   basename in {verifier, implementer} => EXTEND (accepts both bare
#                           `verifier` and plugin-scoped `zs:verifier` forms
#                           — marketplace installs scope the value);
#   anything else        => PASS THROUGH (bare allow, no updatedInput): a
#                           foreign subagent keeps its own timeout semantics.
# Parsed from JSON (not regex) so a `command` string that merely CONTAINS
# an agent_type literal can never confuse the filter.
if isinstance(agent_type, str) and agent_type:
    if agent_type.rsplit(":", 1)[-1] not in ("verifier", "implementer"):
        sys.stdout.write("{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"allow\"}}")
        sys.exit(0)
updated = dict(tool_input)
updated["timeout"] = min_timeout
out = {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow", "updatedInput": updated}}
sys.stdout.write(json.dumps(out))
' 2>/dev/null)

if [ -z "$PY_OUT" ]; then
  # python failed (parse error / unexpected; a missing interpreter already
  # fail-opened above). Permissive fallback: allow as-is. Layer 3
  # (verify-response-validate.sh) catches any downstream verifier failure
  # regardless.
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
  exit 0
fi

printf '%s' "$PY_OUT"
exit 0
