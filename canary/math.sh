#!/bin/bash
add() { echo $(( $1 + $2 )); }
multiply() { echo $(( $1 * $2 )); }
# Self-test
PASS=0; FAIL=0
[ "$(add 2 3)" = "5" ] && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
[ "$(multiply 4 5)" = "20" ] && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
