#!/bin/bash
# Tests for scripts/port.sh
# Run from repo root: bash tests/test-port.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PORT_SCRIPT="$REPO_ROOT/skills/update-zskills/scripts/port.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  printf '\033[32m  PASS\033[0m %s\n' "$1"
  ((PASS_COUNT++))
}

fail() {
  printf '\033[31m  FAIL\033[0m %s\n' "$1"
  ((FAIL_COUNT++))
}

echo "=== port.sh tests ==="

# 1. Determinism: run 3 times, verify same output
run1=$(bash "$PORT_SCRIPT")
run2=$(bash "$PORT_SCRIPT")
run3=$(bash "$PORT_SCRIPT")
if [[ "$run1" == "$run2" && "$run2" == "$run3" ]]; then
  pass "deterministic output ($run1)"
else
  fail "non-deterministic: got $run1, $run2, $run3"
fi

# 2. DEV_PORT override
override=$(DEV_PORT=3000 bash "$PORT_SCRIPT")
if [[ "$override" == "3000" ]]; then
  pass "DEV_PORT override (3000)"
else
  fail "DEV_PORT override — expected 3000, got $override"
fi

# 3. Port range: output should be between 9000-60000 (unless DEV_PORT set)
port=$(bash "$PORT_SCRIPT")
if [[ "$port" -ge 9000 && "$port" -le 60000 ]]; then
  pass "port in range 9000-60000 ($port)"
else
  # Could be 8080 if MAIN_REPO matches — that's also valid
  if [[ "$port" == "8080" ]]; then
    pass "port is default 8080 (main repo match)"
  else
    fail "port out of range — got $port"
  fi
fi

# 4. Numeric output
if [[ "$port" =~ ^[0-9]+$ ]]; then
  pass "numeric output ($port)"
else
  fail "non-numeric output: $port"
fi

echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
