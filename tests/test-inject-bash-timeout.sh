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

# --- ZSKILLS_PYTHON env-override shim (PR #302, issue #321) ---
#
# The shim is:
#   PYTHON=${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}
#   [ -n "$PYTHON" ] || { echo "ERROR: install Python 3 (or set ZSKILLS_PYTHON)" >&2; exit 1; }
#
# Three behaviors to lock in:
#   7. Default — unset ZSKILLS_PYTHON, python3 on PATH → normal injection works
#      (proves the default branch of the shim still resolves a working interpreter).
#   8. Env override honored — ZSKILLS_PYTHON=/nonexistent/python causes the python
#      step to fail (binary not executable); the hook does NOT fall back to the
#      default python3 — it hits the permissive fallback (allow with no
#      updatedInput). If the override were ignored, the default python3 would
#      succeed and we'd see updatedInput.
#   9. Loud-error branch — unset ZSKILLS_PYTHON AND mask python3/python from
#      PATH → hook prints "ERROR: install Python 3" to stderr and exits non-zero.

# Case 7 — default behavior: unset ZSKILLS_PYTHON, normal PATH, injection works.
INPUT_7='{"tool_name":"Bash","tool_input":{"command":"npm test"}}'
RESULT=$(unset ZSKILLS_PYTHON && printf '%s' "$INPUT_7" | bash "$HOOK")
if [[ "$RESULT" == *'"updatedInput"'* ]] \
  && [[ "$RESULT" == *'"timeout": 600000'* || "$RESULT" == *'"timeout":600000'* ]]; then
  pass "case 7: ZSKILLS_PYTHON unset → default python3 resolution, injection works"
else
  fail "case 7: default branch should still inject timeout" "got: $RESULT"
fi

# Case 8 — env override is honored. Point ZSKILLS_PYTHON at a non-executable path.
# The hook's [ -n "$PYTHON" ] guard passes (string is non-empty), then the python
# invocation fails (no such binary), PY_OUT is empty, and the permissive fallback
# returns a bare allow with no updatedInput. If the override were silently
# ignored, the default python3 would succeed and we'd see updatedInput — so
# "no updatedInput" is the positive signal that the override took effect.
INPUT_8='{"tool_name":"Bash","tool_input":{"command":"npm test"}}'
RESULT=$(printf '%s' "$INPUT_8" | ZSKILLS_PYTHON=/nonexistent/python-binary-xyz bash "$HOOK" 2>/dev/null)
if [[ "$RESULT" == *'"permissionDecision":"allow"'* ]] && [[ "$RESULT" != *'updatedInput'* ]]; then
  pass "case 8: ZSKILLS_PYTHON=/nonexistent → override honored (permissive fallback, no updatedInput)"
else
  fail "case 8: bad ZSKILLS_PYTHON override should NOT fall through to default python3" "got: $RESULT"
fi

# Case 9 — loud-error branch. Mask python3 AND python from PATH (point PATH at
# an empty directory) and unset ZSKILLS_PYTHON. The shim's `command -v` lookups
# both fail, $PYTHON ends up empty, the guard fires, hook prints to stderr and
# exits non-zero. We resolve bash by absolute path because the wiped PATH won't
# find `bash` either.
BASH_BIN=$(command -v bash)
EMPTY_PATH_DIR=$(mktemp -d)
INPUT_9='{"tool_name":"Bash","tool_input":{"command":"npm test"}}'
# Run hook in a subshell with sanitized env. Capture stderr; redirect stdout
# away so it doesn't pollute the captured string. Exit code of the rightmost
# command of the pipe is propagated out of `$(...)`.
STDERR_OUT=$(printf '%s' "$INPUT_9" | (unset ZSKILLS_PYTHON; PATH="$EMPTY_PATH_DIR" "$BASH_BIN" "$HOOK") 2>&1 >/dev/null)
EXIT_CODE=$?
rmdir "$EMPTY_PATH_DIR"
if [[ "$STDERR_OUT" == *"ERROR: install Python 3"* ]] && [[ "$EXIT_CODE" -ne 0 ]]; then
  pass "case 9: no python3/python on PATH + no ZSKILLS_PYTHON → loud error + non-zero exit"
else
  fail "case 9: missing python should produce loud error" "exit=$EXIT_CODE stderr=$STDERR_OUT"
fi

echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
