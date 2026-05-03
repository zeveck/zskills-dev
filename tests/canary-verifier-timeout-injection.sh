#!/usr/bin/env bash
# tests/canary-verifier-timeout-injection.sh
#
# Phase 4 canary 2 — VERIFIER_AGENT_FIX plan.
#
# SCOPE: pure-shell integration assertion that the L0 plumbing for the
# verifier subagent's Bash-tool timeout injection is intact across both
# the source hook (`hooks/inject-bash-timeout.sh`) and the mirror that
# the harness actually loads (`.claude/hooks/inject-bash-timeout.sh`),
# AND that the verifier agent definition (`.claude/agents/verifier.md`)
# still declares the PreToolUse hook on Bash with the right command.
#
# WHAT THIS CANARY IS:
#   * A runtime assertion that `inject-bash-timeout.sh` exists, is
#     executable, byte-identical between source and mirror, behaves
#     correctly on synthetic JSON envelopes (probe / real-injection /
#     already-sufficient cases), and remains wired into the verifier
#     agent frontmatter.
#
# WHAT THIS CANARY IS NOT:
#   * A live subagent dispatch. The "verifier-actually-injects" loop
#     closure (probe step in the original Phase 4.2 spec — dispatch
#     `subagent_type: "verifier"` with a Bash call that would have hit
#     the 120s default and assert it returns) is not reachable from
#     pure shell — `Agent` is not a CLI tool. That property IS exercised
#     end-to-end every time a real `/run-plan` Phase 3 verifier
#     dispatch runs against a long-running test suite (which is the
#     entire reason this hook exists). This canary covers everything
#     that CAN be asserted from CI; the live-dispatch property is
#     covered by every successful verifier dispatch in production.
#
# Per the Phase 4.2 spec's "acceptable simplification" — the unit-level
# behavior is already covered by `tests/test-inject-bash-timeout.sh`
# (5 cases, byte-level injection round-tripping). This canary is the
# integration cross-cut: source/mirror parity + frontmatter wiring +
# 3-case smoke that the script still works when called the way the
# harness calls it.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SRC_HOOK="$REPO_ROOT/hooks/inject-bash-timeout.sh"
MIRROR_HOOK="$REPO_ROOT/.claude/hooks/inject-bash-timeout.sh"
VERIFIER_AGENT="$REPO_ROOT/.claude/agents/verifier.md"

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

echo "=== canary-verifier-timeout-injection ==="

# --------------------------------------------------------------------
# Assertion 1 — source hook exists and is executable
# --------------------------------------------------------------------
if [ -f "$SRC_HOOK" ] && [ -x "$SRC_HOOK" ]; then
  pass "source hook exists and is executable: hooks/inject-bash-timeout.sh"
else
  fail "source hook missing or not executable" "path=$SRC_HOOK"
fi

# --------------------------------------------------------------------
# Assertion 2 — mirror hook exists and is executable
# --------------------------------------------------------------------
if [ -f "$MIRROR_HOOK" ] && [ -x "$MIRROR_HOOK" ]; then
  pass "mirror hook exists and is executable: .claude/hooks/inject-bash-timeout.sh"
else
  fail "mirror hook missing or not executable" "path=$MIRROR_HOOK"
fi

# --------------------------------------------------------------------
# Assertion 3 — source and mirror are byte-identical
# Drift here means a Phase 5 mirror step was skipped and the harness
# is loading stale code.
# --------------------------------------------------------------------
if diff -q "$SRC_HOOK" "$MIRROR_HOOK" >/dev/null 2>&1; then
  pass "source and mirror inject-bash-timeout.sh are byte-identical"
else
  fail "source and mirror inject-bash-timeout.sh diverge" "$(diff -u "$SRC_HOOK" "$MIRROR_HOOK" | head -20)"
fi

# --------------------------------------------------------------------
# Assertion 4 — verifier agent frontmatter declares the hook
# --------------------------------------------------------------------
if [ ! -f "$VERIFIER_AGENT" ]; then
  fail "verifier agent definition missing" "expected: $VERIFIER_AGENT"
else
  # Extract frontmatter (between first two --- lines) and confirm the
  # PreToolUse Bash hook references inject-bash-timeout.sh.
  FRONTMATTER=$(awk '/^---$/{c++; if (c==2) exit; next} c==1' "$VERIFIER_AGENT")
  if echo "$FRONTMATTER" | grep -q 'PreToolUse' \
     && echo "$FRONTMATTER" | grep -q 'matcher:.*Bash' \
     && echo "$FRONTMATTER" | grep -q 'inject-bash-timeout.sh'; then
    pass "verifier agent frontmatter declares PreToolUse hook on Bash matching inject-bash-timeout.sh"
  else
    fail "verifier agent frontmatter missing PreToolUse Bash inject-bash-timeout.sh" "frontmatter:
$FRONTMATTER"
  fi
fi

# --------------------------------------------------------------------
# Behavior smoke — invoke the source hook with synthetic JSON envelopes
# the way the harness calls it. These are NOT a duplicate of
# test-inject-bash-timeout.sh's 5-case unit test — these are the
# integration cross-cut: probe (no crash on degenerate input), real
# injection (the load-bearing path), and already-sufficient (no
# regression to the no-op path).
# --------------------------------------------------------------------

# --------------------------------------------------------------------
# Assertion 5 — probe (gate): empty stdin must not crash the hook.
# A degenerate envelope (no JSON at all) must yield a clean
# `permissionDecision:allow` with no `updatedInput`. If this asserts
# fails, the hook is fragile and any future shape-change in the
# harness envelope will silently break verifier dispatches.
# --------------------------------------------------------------------
PROBE_OUT=$(printf '' | bash "$SRC_HOOK" 2>/dev/null)
PROBE_EXIT=$?
if [ "$PROBE_EXIT" -eq 0 ] \
   && [[ "$PROBE_OUT" == *'"permissionDecision":"allow"'* ]] \
   && [[ "$PROBE_OUT" != *'updatedInput'* ]]; then
  pass "probe: empty stdin → exit 0, allow-without-updatedInput"
else
  fail "probe: empty stdin should yield clean allow-without-updatedInput" "exit=$PROBE_EXIT out=$PROBE_OUT"
fi

# --------------------------------------------------------------------
# Assertion 6 — real injection: a Bash command with no `timeout` and
# a runtime that would hit the default 120s tool timeout (sleep 130)
# must get `timeout: 600000` injected. This is THE load-bearing case;
# the entire D'' architecture exists because this used to silently
# fail (the 120s default triggered the bg+Monitor recovery reflex).
# --------------------------------------------------------------------
REAL_INPUT='{"tool_name":"Bash","tool_input":{"command":"sleep 130 && echo done"}}'
REAL_OUT=$(printf '%s' "$REAL_INPUT" | bash "$SRC_HOOK")
REAL_EXIT=$?
if [ "$REAL_EXIT" -eq 0 ] \
   && [[ "$REAL_OUT" == *'"updatedInput"'* ]] \
   && { [[ "$REAL_OUT" == *'"timeout": 600000'* ]] || [[ "$REAL_OUT" == *'"timeout":600000'* ]]; } \
   && [[ "$REAL_OUT" == *'sleep 130'* ]]; then
  pass "real-injection: sleep 130 with no timeout → updatedInput sets timeout 600000, command preserved"
else
  fail "real-injection: long-sleep command without timeout should get 600000 injected" "exit=$REAL_EXIT out=$REAL_OUT"
fi

# --------------------------------------------------------------------
# Assertion 7 — already-sufficient timeout: no `updatedInput`, no
# regression to the no-op path. A Bash call that already names
# timeout >= 600000 must NOT trigger an `updatedInput` (otherwise we
# unnecessarily round-trip every well-formed call through python and
# risk shape drift over time).
# --------------------------------------------------------------------
SUFFICIENT_INPUT='{"tool_name":"Bash","tool_input":{"command":"npm test","timeout":900000}}'
SUFFICIENT_OUT=$(printf '%s' "$SUFFICIENT_INPUT" | bash "$SRC_HOOK")
SUFFICIENT_EXIT=$?
if [ "$SUFFICIENT_EXIT" -eq 0 ] \
   && [[ "$SUFFICIENT_OUT" == *'"permissionDecision":"allow"'* ]] \
   && [[ "$SUFFICIENT_OUT" != *'updatedInput'* ]]; then
  pass "no-op: timeout already 900000 → allow-without-updatedInput (no regression)"
else
  fail "no-op: already-sufficient timeout should yield allow-without-updatedInput" "exit=$SUFFICIENT_EXIT out=$SUFFICIENT_OUT"
fi

echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
