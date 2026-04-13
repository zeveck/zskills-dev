#!/bin/bash
add() { echo $(( $1 + $2 )); }
subtract() { echo $(( $1 - $2 )); }
multiply() { echo $(( $1 * $2 )); }
divide() { echo $(( $1 / $2 )); }

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  # self-test only runs when executed directly, not when sourced
  PASS=0; FAIL=0
  check() {
    local name="$1" got="$2" want="$3"
    if [ "$got" = "$want" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $name — got $got, want $want"; fi
  }
  check "add 5 3" "$(add 5 3)" "8"
  check "subtract 10 3" "$(subtract 10 3)" "7"
  check "multiply 4 6" "$(multiply 4 6)" "24"
  check "divide 20 4" "$(divide 20 4)" "5"
  echo "$PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
fi
