#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/calc.sh" 2>/dev/null  # source without running self-tests

sum() {
  local total=0
  for n in "$@"; do total=$(add $total $n); done
  echo $total
}

mean() {
  local s=$(sum "$@")
  echo $(divide $s $#)
}

# Self-test
PASS=0; FAIL=0
check() {
  local name="$1" got="$2" want="$3"
  if [ "$got" = "$want" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $name — got $got, want $want"; fi
}
check "sum 1 2 3 4 5" "$(sum 1 2 3 4 5)" "15"
check "mean 10 20 30" "$(mean 10 20 30)" "20"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
