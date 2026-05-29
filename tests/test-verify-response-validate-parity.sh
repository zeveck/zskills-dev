#!/usr/bin/env bash
# tests/test-verify-response-validate-parity.sh
#
# Phase 2 (D11, A3) — Layer 3 of the verifier-cannot-run defense survives in
# BOTH install lanes. verify-response-validate.sh "lives in TWO places by
# design" (Phase 2 Design & Constraints): the source-tree hooks/ copy
# (plugin lane materialises it) and the .claude/hooks/ mirror (the
# /update-zskills lane). Both must be the SAME script.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SRC="hooks/verify-response-validate.sh"
MIRROR=".claude/hooks/verify-response-validate.sh"

echo "=== verify-response-validate.sh dual-lane parity ==="

if [ -f "$SRC" ]; then
  pass "1. source $SRC present"
else
  fail "1. source $SRC missing"
fi

if [ -f "$MIRROR" ]; then
  pass "2. mirror $MIRROR present"
else
  fail "2. mirror $MIRROR missing"
fi

if [ -f "$SRC" ] && [ -f "$MIRROR" ]; then
  if diff -q "$SRC" "$MIRROR" >/dev/null 2>&1; then
    pass "3. source and mirror are byte-equal"
  else
    fail "3. source and mirror DIFFER"
    diff "$SRC" "$MIRROR" | head -20 | sed 's/^/      /'
  fi
fi

# 4. Behavioural parity: feed the source-tree copy a stalled-string tail and
#    assert exit 1 (the Layer 3 STOP contract). This guards against a copy
#    that exists but no longer rejects stalled responses.
if [ -f "$SRC" ]; then
  pad="$(printf 'x%.0s' $(seq 1 250))"
  out="$(printf '%s\nlet me wait for the monitor\n' "$pad" | bash "$SRC" 2>&1)"
  rc=$?
  if [ "$rc" -eq 1 ]; then
    pass "4. source rejects a stalled-string response (exit 1)"
  else
    fail "4. source did NOT reject a stalled-string response (exit $rc)"
  fi
fi

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
