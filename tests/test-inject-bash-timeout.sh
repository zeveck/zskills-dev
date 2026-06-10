#!/usr/bin/env bash
# Tests for hooks/inject-bash-timeout.sh
# Run from repo root: bash tests/test-inject-bash-timeout.sh
#
# VERIFIER_AGENT_FIX (D'' rework). Layer 0 hook ensures every Bash call
# from the verifier subagent gets at least timeout: 600000.
#
# Cases:
#   1. Already-sufficient timeout (>= 600000) → no `updatedInput` (allow as-is)
#   2. Insufficient timeout → `updatedInput` with timeout: 600000, command preserved
#   3. Missing timeout field → `updatedInput` with timeout: 600000, command preserved
#   4. run_in_background:true + insufficient timeout → both preserved AND timeout set
#   5. Bare tool_input (not wrapped in envelope) → still injects correctly
#   11-18. T-A agent-identity filter (INSTALL_REDESIGN Phase 2): absent ⇒
#          EXTEND; basename ∈ {verifier, implementer} (bare AND plugin-scoped
#          `zs:` forms) ⇒ EXTEND; foreign ⇒ pass through (bare allow).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/hooks/inject-bash-timeout.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  printf '\033[32m  PASS\033[0m %s\n' "$1"
  ((PASS_COUNT++))
}

fail() {
  printf '\033[31m  FAIL\033[0m %s\n' "$1"
  printf '    %s\n' "$2"
  ((FAIL_COUNT++))
}

run_hook() {
  printf '%s' "$1" | bash "$HOOK"
}

echo "=== inject-bash-timeout.sh ==="

# Case 1 — already-sufficient timeout: no updatedInput should appear
INPUT_1='{"tool_name":"Bash","tool_input":{"command":"npm test","timeout":600000}}'
RESULT=$(run_hook "$INPUT_1")
if [[ "$RESULT" == *'"permissionDecision":"allow"'* ]] && [[ "$RESULT" != *'updatedInput'* ]]; then
  pass "case 1: timeout already 600000 → allow as-is (no updatedInput)"
else
  fail "case 1: timeout already sufficient should yield no updatedInput" "got: $RESULT"
fi

# Case 1b — already-sufficient larger timeout
INPUT_1B='{"tool_name":"Bash","tool_input":{"command":"sleep 1","timeout":900000}}'
RESULT=$(run_hook "$INPUT_1B")
if [[ "$RESULT" == *'"permissionDecision":"allow"'* ]] && [[ "$RESULT" != *'updatedInput'* ]]; then
  pass "case 1b: timeout already 900000 → allow as-is"
else
  fail "case 1b: timeout >= 600000 should not be downgraded" "got: $RESULT"
fi

# Case 2 — insufficient timeout: updatedInput with command preserved + timeout=600000
INPUT_2='{"tool_name":"Bash","tool_input":{"command":"npm test","timeout":60000}}'
RESULT=$(run_hook "$INPUT_2")
if [[ "$RESULT" == *'"updatedInput"'* ]] \
  && [[ "$RESULT" == *'"timeout": 600000'* || "$RESULT" == *'"timeout":600000'* ]] \
  && [[ "$RESULT" == *'"command": "npm test"'* || "$RESULT" == *'"command":"npm test"'* ]]; then
  pass "case 2: insufficient timeout → updatedInput sets 600000, preserves command"
else
  fail "case 2: insufficient timeout should be replaced with 600000" "got: $RESULT"
fi

# Case 3 — missing timeout field: same outcome as case 2
INPUT_3='{"tool_name":"Bash","tool_input":{"command":"npm test"}}'
RESULT=$(run_hook "$INPUT_3")
if [[ "$RESULT" == *'"updatedInput"'* ]] \
  && [[ "$RESULT" == *'"timeout": 600000'* || "$RESULT" == *'"timeout":600000'* ]] \
  && [[ "$RESULT" == *'"command": "npm test"'* || "$RESULT" == *'"command":"npm test"'* ]]; then
  pass "case 3: missing timeout → updatedInput adds 600000, preserves command"
else
  fail "case 3: missing timeout should add 600000" "got: $RESULT"
fi

# Case 4 — run_in_background:true preserved alongside injected timeout
INPUT_4='{"tool_name":"Bash","tool_input":{"command":"npm test","run_in_background":true}}'
RESULT=$(run_hook "$INPUT_4")
if [[ "$RESULT" == *'"updatedInput"'* ]] \
  && [[ "$RESULT" == *'"timeout": 600000'* || "$RESULT" == *'"timeout":600000'* ]] \
  && [[ "$RESULT" == *'"run_in_background": true'* || "$RESULT" == *'"run_in_background":true'* ]] \
  && [[ "$RESULT" == *'"command": "npm test"'* || "$RESULT" == *'"command":"npm test"'* ]]; then
  pass "case 4: run_in_background:true preserved AND timeout set"
else
  fail "case 4: run_in_background should be preserved while timeout is injected" "got: $RESULT"
fi

# Case 5 — bare tool_input shape (no outer wrapper) still works
INPUT_5='{"command":"echo hi"}'
RESULT=$(run_hook "$INPUT_5")
if [[ "$RESULT" == *'"updatedInput"'* ]] \
  && [[ "$RESULT" == *'"timeout": 600000'* || "$RESULT" == *'"timeout":600000'* ]] \
  && [[ "$RESULT" == *'"command": "echo hi"'* || "$RESULT" == *'"command":"echo hi"'* ]]; then
  pass "case 5: bare tool_input (no envelope) → still injects timeout"
else
  fail "case 5: bare tool_input should still get injected" "got: $RESULT"
fi

# Case 6 — command with internal quotes/escapes round-trips correctly
INPUT_6='{"tool_name":"Bash","tool_input":{"command":"echo \"hello world\""}}'
RESULT=$(run_hook "$INPUT_6")
if [[ "$RESULT" == *'"updatedInput"'* ]] \
  && [[ "$RESULT" == *'"timeout": 600000'* || "$RESULT" == *'"timeout":600000'* ]] \
  && [[ "$RESULT" == *'hello world'* ]]; then
  pass "case 6: command with embedded quotes round-trips"
else
  fail "case 6: command with embedded quotes should be preserved" "got: $RESULT"
fi

# --- ZSKILLS_PYTHON env-override + probe-resolution (issue #1075) ---
#
# The resolver is zskills_resolve_python (hooks/_lib/resolve-python.sh, inlined):
# it PROBE-RUNS each candidate ($ZSKILLS_PYTHON → python3 → python), accepting
# only one that exits 0 on a Python-3 probe. A non-executable / non-Python-3
# candidate (the Windows MS Store `python3` stub) is SKIPPED, not latched.
# Layer 0 fails OPEN: with NO working interpreter it emits a bare allow and
# exits 0 (a PreToolUse hook that exits 1 could block the Bash call).
#
# Behaviors locked in:
#   7. Default — unset ZSKILLS_PYTHON, python3 on PATH → normal injection works.
#   8. Bad ZSKILLS_PYTHON override (nonexistent path) → resolver SKIPS it and
#      falls through to the real python3 on PATH → injection STILL works
#      (graceful fall-through, the #1075 fix; the old shim latched the empty
#      override and lost injection).
#   9. No working Python anywhere (only a Windows-style stub `python3` on PATH,
#      ZSKILLS_PYTHON unset) → fail OPEN: bare allow + exit 0, NOT exit 1.
#  10. Stub python3 first on PATH but a real `python` later → resolver skips the
#      stub and injects a valid envelope.

# Case 7 — default behavior: unset ZSKILLS_PYTHON, normal PATH, injection works.
INPUT_7='{"tool_name":"Bash","tool_input":{"command":"npm test"}}'
RESULT=$(unset ZSKILLS_PYTHON && printf '%s' "$INPUT_7" | bash "$HOOK")
if [[ "$RESULT" == *'"updatedInput"'* ]] \
  && [[ "$RESULT" == *'"timeout": 600000'* || "$RESULT" == *'"timeout":600000'* ]]; then
  pass "case 7: ZSKILLS_PYTHON unset → default python3 resolution, injection works"
else
  fail "case 7: default branch should still inject timeout" "got: $RESULT"
fi

# Case 8 — bad ZSKILLS_PYTHON override falls through to a real interpreter.
# The resolver's `command -v "$cand"` fails for the nonexistent path, so it
# moves on to python3/python and injection still works. (Pre-#1075 the shim
# latched the empty override and produced NO updatedInput.)
INPUT_8='{"tool_name":"Bash","tool_input":{"command":"npm test"}}'
RESULT=$(printf '%s' "$INPUT_8" | ZSKILLS_PYTHON=/nonexistent/python-binary-xyz bash "$HOOK" 2>/dev/null)
if [[ "$RESULT" == *'"updatedInput"'* ]] \
  && [[ "$RESULT" == *'"timeout": 600000'* || "$RESULT" == *'"timeout":600000'* ]]; then
  pass "case 8: bad ZSKILLS_PYTHON override → resolver falls through to real python3, injection works"
else
  fail "case 8: bad override should fall through to a working interpreter" "got: $RESULT"
fi

# Build a fake-interpreter dir with a Windows-style MS Store `python3` stub:
# prints the store message to stderr and exits 9009. Plus a TOOLS dir holding
# symlinks to the few real binaries the hook itself shells out to (`bash` to
# start the subshell, `cat` for the `INPUT=$(cat)` read) so the masked-PATH
# subshell can run WITHOUT leaking the host's real python3 onto PATH.
BASH_BIN=$(command -v bash)
CAT_BIN=$(command -v cat)
TOOLS_DIR=$(mktemp -d)
ln -s "$BASH_BIN" "$TOOLS_DIR/bash"
ln -s "$CAT_BIN" "$TOOLS_DIR/cat"
STUB_DIR=$(mktemp -d)
cat > "$STUB_DIR/python3" <<'STUB'
#!/bin/sh
echo "Python was not found; run without arguments to install from the Microsoft Store." >&2
exit 9009
STUB
chmod +x "$STUB_DIR/python3"

# Case 9 — no WORKING python anywhere (only the stub) → fail OPEN, exit 0.
# PATH = stub dir + tools (bash only); ZSKILLS_PYTHON unset. The resolver runs
# the stub, sees it exit non-zero, finds no other candidate, returns empty →
# the hook emits a bare allow and exits 0 (NOT 1).
INPUT_9='{"tool_name":"Bash","tool_input":{"command":"npm test"}}'
RESULT=$(printf '%s' "$INPUT_9" | (unset ZSKILLS_PYTHON; PATH="$STUB_DIR:$TOOLS_DIR" "$BASH_BIN" "$HOOK") 2>/dev/null)
EXIT_CODE=$?
if [[ "$RESULT" == *'"permissionDecision":"allow"'* ]] \
  && [[ "$RESULT" != *'updatedInput'* ]] \
  && [[ "$EXIT_CODE" -eq 0 ]]; then
  pass "case 9: only a Windows-style stub python3 → fail OPEN (bare allow, exit 0)"
else
  fail "case 9: missing working python should fail OPEN, not exit 1" "exit=$EXIT_CODE result=$RESULT"
fi

# Case 10 — stub python3 first on PATH, real `python` later → resolver skips the
# stub and produces a valid injected envelope. Back the real `python` with the
# host interpreter via a /bin/sh wrapper (absolute interpreter path, PATH-safe).
REAL_PY=$(command -v python3 || command -v python)
REAL_DIR=$(mktemp -d)
cat > "$REAL_DIR/python" <<REALPY
#!/bin/sh
exec "$REAL_PY" "\$@"
REALPY
chmod +x "$REAL_DIR/python"
INPUT_10='{"tool_name":"Bash","tool_input":{"command":"npm test"}}'
RESULT=$(printf '%s' "$INPUT_10" | (unset ZSKILLS_PYTHON; PATH="$STUB_DIR:$REAL_DIR:$TOOLS_DIR" "$BASH_BIN" "$HOOK") 2>/dev/null)
EXIT_CODE=$?
if [[ "$RESULT" == *'"updatedInput"'* ]] \
  && [[ "$RESULT" == *'"timeout": 600000'* || "$RESULT" == *'"timeout":600000'* ]] \
  && [[ "$EXIT_CODE" -eq 0 ]]; then
  pass "case 10: stub python3 first, real python later → stub skipped, valid injection"
else
  fail "case 10: should skip stub python3 and inject via real python" "exit=$EXIT_CODE result=$RESULT"
fi

rm -rf "$TOOLS_DIR" "$STUB_DIR" "$REAL_DIR"

# --- T-A agent-identity filter (INSTALL_REDESIGN Phase 2) ---
#
# Phase-1 Findings (claim 2): the hooks.json PreToolUse stdin envelope carries
# a top-level `agent_type` on SUBAGENT Bash calls — the bare agent name for
# project agents ("verifier") but a PLUGIN-SCOPED value ("zs:verifier") under
# marketplace installs — and NO field on orchestrator main-thread calls.
# Pinned T-A semantics (hooks/inject-bash-timeout.sh):
#   absent  ⇒ EXTEND  (legacy frontmatter path + orchestrator widening)
#   basename ∈ {verifier, implementer} ⇒ EXTEND (bare AND `zs:`-scoped forms)
#   foreign ⇒ PASS THROUGH (bare allow, no updatedInput)

# Case 11 — agent_type "verifier" (bare) → extends.
INPUT_11='{"agent_type":"verifier","tool_name":"Bash","tool_input":{"command":"npm test"}}'
RESULT=$(run_hook "$INPUT_11")
if [[ "$RESULT" == *'"updatedInput"'* ]] \
  && [[ "$RESULT" == *'"timeout": 600000'* || "$RESULT" == *'"timeout":600000'* ]]; then
  pass "case 11: agent_type verifier → extends to 600000"
else
  fail "case 11: bare verifier identity should extend" "got: $RESULT"
fi

# Case 12 — agent_type "implementer" (bare) → extends.
INPUT_12='{"agent_type":"implementer","tool_name":"Bash","tool_input":{"command":"npm test"}}'
RESULT=$(run_hook "$INPUT_12")
if [[ "$RESULT" == *'"updatedInput"'* ]] \
  && [[ "$RESULT" == *'"timeout": 600000'* || "$RESULT" == *'"timeout":600000'* ]]; then
  pass "case 12: agent_type implementer → extends to 600000"
else
  fail "case 12: bare implementer identity should extend" "got: $RESULT"
fi

# Case 13 — plugin-scoped agent_type "zs:verifier" (marketplace install form)
# → extends. The Phase-1 shape-(b) probe recorded scoped values even for
# bare-name dispatch, so suffix matching is load-bearing, not defensive.
INPUT_13='{"agent_type":"zs:verifier","tool_name":"Bash","tool_input":{"command":"npm test"}}'
RESULT=$(run_hook "$INPUT_13")
if [[ "$RESULT" == *'"updatedInput"'* ]] \
  && [[ "$RESULT" == *'"timeout": 600000'* || "$RESULT" == *'"timeout":600000'* ]]; then
  pass "case 13: agent_type zs:verifier (plugin-scoped) → extends to 600000"
else
  fail "case 13: plugin-scoped verifier identity should extend" "got: $RESULT"
fi

# Case 14 — plugin-scoped agent_type "zs:implementer" → extends.
INPUT_14='{"agent_type":"zs:implementer","tool_name":"Bash","tool_input":{"command":"npm test"}}'
RESULT=$(run_hook "$INPUT_14")
if [[ "$RESULT" == *'"updatedInput"'* ]] \
  && [[ "$RESULT" == *'"timeout": 600000'* || "$RESULT" == *'"timeout":600000'* ]]; then
  pass "case 14: agent_type zs:implementer (plugin-scoped) → extends to 600000"
else
  fail "case 14: plugin-scoped implementer identity should extend" "got: $RESULT"
fi

# Case 15 — NO agent_type field → EXTENDS. Pins the absent⇒extend rule the
# identity-less cases 2-10 already imply: the legacy frontmatter path feeds
# this same script identity-less stdin, and orchestrator main-thread calls
# carry no agent_type (accepted T-B-equivalent widening, recorded in the
# Phase-1 claim-2 Findings row).
INPUT_15='{"tool_name":"Bash","tool_input":{"command":"npm test","timeout":60000}}'
RESULT=$(run_hook "$INPUT_15")
if [[ "$RESULT" == *'"updatedInput"'* ]] \
  && [[ "$RESULT" == *'"timeout": 600000'* || "$RESULT" == *'"timeout":600000'* ]]; then
  pass "case 15: absent agent_type → EXTENDS (absent⇒extend rule pinned)"
else
  fail "case 15: identity-less envelope must still extend" "got: $RESULT"
fi

# Case 16 — foreign agent_type ("Explore") → pass through: bare allow, NO
# updatedInput. A foreign subagent keeps its own timeout semantics.
INPUT_16='{"agent_type":"Explore","tool_name":"Bash","tool_input":{"command":"npm test"}}'
RESULT=$(run_hook "$INPUT_16")
if [[ "$RESULT" == *'"permissionDecision":"allow"'* ]] && [[ "$RESULT" != *'updatedInput'* ]]; then
  pass "case 16: foreign agent_type Explore → pass through (no updatedInput)"
else
  fail "case 16: foreign agent should pass through unmodified" "got: $RESULT"
fi

# Case 17 — foreign plugin-scoped agent_type → pass through.
INPUT_17='{"agent_type":"zsprobe:zsprobe-agent","tool_name":"Bash","tool_input":{"command":"npm test"}}'
RESULT=$(run_hook "$INPUT_17")
if [[ "$RESULT" == *'"permissionDecision":"allow"'* ]] && [[ "$RESULT" != *'updatedInput'* ]]; then
  pass "case 17: foreign scoped agent_type zsprobe:zsprobe-agent → pass through"
else
  fail "case 17: foreign scoped agent should pass through unmodified" "got: $RESULT"
fi

# Case 18 — identity is parsed from JSON, not regex-matched: an identity-LESS
# envelope whose command STRING contains a foreign agent_type literal must
# still EXTEND (a naive regex extraction would false-positive on the command
# text and wrongly pass through — losing Layer 0 for exactly the verifier
# runs that test this hook).
INPUT_18='{"tool_name":"Bash","tool_input":{"command":"printf %s \"{\\\"agent_type\\\":\\\"Explore\\\"}\" | bash hook.sh"}}'
RESULT=$(run_hook "$INPUT_18")
if [[ "$RESULT" == *'"updatedInput"'* ]] \
  && [[ "$RESULT" == *'"timeout": 600000'* || "$RESULT" == *'"timeout":600000'* ]]; then
  pass "case 18: foreign agent_type literal INSIDE command text → still extends (JSON parse, not regex)"
else
  fail "case 18: command-embedded agent_type literal must not confuse the filter" "got: $RESULT"
fi

echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
