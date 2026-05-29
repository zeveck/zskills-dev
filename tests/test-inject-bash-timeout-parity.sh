#!/usr/bin/env bash
# tests/test-inject-bash-timeout-parity.sh
#
# Phase 2 (D11, A3) — Layer 0 of the verifier-cannot-run defense survives in
# BOTH install lanes. The /update-zskills lane installs
# inject-bash-timeout.sh into .claude/hooks/; the plugin lane ships it under
# hooks/ and materialises it (W2.1) into the same destination. Both copies
# must be the SAME script.
#
# This parity test asserts the source-tree hooks/inject-bash-timeout.sh and
# the mirror .claude/hooks/inject-bash-timeout.sh are byte-equal, AND that
# the materialiser's sentinelled copy is byte-equal modulo the leading
# sentinel line. If the two ever drift, one lane runs a different Layer 0
# hook than the other.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SRC="hooks/inject-bash-timeout.sh"
MIRROR=".claude/hooks/inject-bash-timeout.sh"

echo "=== inject-bash-timeout.sh dual-lane parity ==="

# 1. Source exists.
if [ -f "$SRC" ]; then
  pass "1. source $SRC present"
else
  fail "1. source $SRC missing"
fi

# 2. Mirror exists.
if [ -f "$MIRROR" ]; then
  pass "2. mirror $MIRROR present"
else
  fail "2. mirror $MIRROR missing"
fi

# 3. Source and mirror are byte-equal (both lanes run the SAME Layer 0 hook).
if [ -f "$SRC" ] && [ -f "$MIRROR" ]; then
  if diff -q "$SRC" "$MIRROR" >/dev/null 2>&1; then
    pass "3. source and mirror are byte-equal"
  else
    fail "3. source and mirror DIFFER"
    diff "$SRC" "$MIRROR" | head -20 | sed 's/^/      /'
  fi
fi

# 4. Source carries the line-2 zskills-hook-version stamp (the version-skew
#    guard in plugin-hook-skip-if-mirrored.sh depends on it).
if [ -f "$SRC" ] && head -n 5 "$SRC" | grep -q 'zskills-hook-version:'; then
  pass "4. source carries zskills-hook-version stamp"
else
  fail "4. source missing zskills-hook-version stamp"
fi

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
