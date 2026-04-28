#!/bin/bash
# Tests for scripts/plan-drift-correct.sh.
#
# Covers all three modes (--parse, --drift, --correct) across the five
# supported <stated> forms (range, ≤, ≥, ~/literal, exactly), plus the
# error / "unsupported" / "unlocatable" exit branches. Per CLAUDE.md,
# scratch fixtures live under /tmp/zskills-tests/<basename-of-cwd>/.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/plan-drift-correct.sh"

TEST_OUT="/tmp/zskills-tests/$(basename "$REPO_ROOT")/plan-drift-correct"
mkdir -p "$TEST_OUT"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# expect_drift <label> <stated> <actual> <expected-stdout>
expect_drift() {
  local label="$1" stated="$2" actual="$3" expected="$4"
  local out
  out=$(bash "$SCRIPT" --drift "$stated" "$actual" 2>&1)
  if [ "$out" = "$expected" ]; then
    pass "$label  ($stated × $actual → $out)"
  else
    fail "$label — expected '$expected', got '$out'  ($stated × $actual)"
  fi
}

# expect_rc <label> <args...>  ENV: EXPECTED_RC
expect_rc() {
  local expected_rc="$1"; shift
  local label="$1"; shift
  bash "$SCRIPT" "$@" >/dev/null 2>&1
  local rc=$?
  if [ "$rc" = "$expected_rc" ]; then
    pass "$label (rc=$rc)"
  else
    fail "$label — expected rc=$expected_rc, got rc=$rc"
  fi
}

echo "=== --drift: range form ==="
# midpoint(340,380)=360; |277-360|=83; ceil(83*100/360)=ceil(23.06)=24
expect_drift "range hyphen 340-380 vs 277"   "340-380" 277 24
# en-dash variant: midpoint(340,380)=360; |360-360|=0
expect_drift "range en-dash 340–380 vs 360"  "340–380" 360 0
expect_drift "range 100-200 vs 150"          "100-200" 150 0

echo ""
echo "=== --drift: ≤ / <= / 'at most' form ==="
expect_drift "≤50 vs 40 (within bound)"      "≤50" 40 0
expect_drift "<=50 vs 60 (over bound)"       "<=50" 60 20
expect_drift "'at most 50' vs 60"            "at most 50" 60 20

echo ""
echo "=== --drift: ≥ / >= / 'at least' form ==="
expect_drift "≥35 vs 50 (within bound)"      "≥35" 50 0
expect_drift ">=35 vs 20 (under bound)"      ">=35" 20 43
expect_drift "'at least 35' vs 20"           "at least 35" 20 43

echo ""
echo "=== --drift: ~ / approximately / expected / literal form ==="
expect_drift "~357 vs 277"                   "~357" 277 23
expect_drift "approximately 100 vs 90"       "approximately 100" 90 10
expect_drift "expected 100 vs 110"           "expected 100" 110 10
expect_drift "literal 100 vs 90"             "100" 90 10

echo ""
echo "=== --drift: exactly form ==="
expect_drift "exactly 5 vs 5"                "exactly 5" 5 0
expect_drift "exactly 5 vs 6 (mismatch → 999)" "exactly 5" 6 999

echo ""
echo "=== --drift: unsupported form returns rc=2 ==="
expect_rc 2 "'roughly 400-600' is unsupported"     --drift "roughly 400-600" 500
expect_rc 2 "'(40 + 12)' is unsupported"           --drift "(40 + 12)" 50

echo ""
echo "=== --parse: well-formed token ==="
WELL="$TEST_OUT/well-formed.txt"
cat > "$WELL" <<'EOF'
Lots of report text here.

PLAN-TEXT-DRIFT: phase=1 bullet=3 field=skill-line-count plan=340-380 actual=277

More text.
EOF
out=$(bash "$SCRIPT" --parse "$WELL" 2>&1); rc=$?
expected_one='1|3|skill-line-count|340-380|277'
if [ "$rc" = "0" ] && [ "$out" = "$expected_one" ]; then
  pass "parse: single well-formed token"
else
  fail "parse: single well-formed — got rc=$rc, out='$out'"
fi

echo ""
echo "=== --parse: multiple tokens, one file ==="
MULTI="$TEST_OUT/multi-token.txt"
cat > "$MULTI" <<'EOF'
PLAN-TEXT-DRIFT: phase=1 bullet=3 field=skill-line-count plan=340-380 actual=277
Some intervening prose.
PLAN-TEXT-DRIFT: phase=4A bullet=2 field=test-count plan=at most 50 actual=60
EOF
out=$(bash "$SCRIPT" --parse "$MULTI" 2>&1); rc=$?
expected_multi='1|3|skill-line-count|340-380|277
4A|2|test-count|at most 50|60'
if [ "$rc" = "0" ] && [ "$out" = "$expected_multi" ]; then
  pass "parse: multiple tokens emit one record per line"
else
  fail "parse: multi — got rc=$rc, out='$out'"
fi

echo ""
echo "=== --parse: malformed token rejection ==="
# Field with colon
BAD_FIELD="$TEST_OUT/bad-field.txt"
cat > "$BAD_FIELD" <<'EOF'
PLAN-TEXT-DRIFT: phase=1 bullet=3 field=has:colon plan=10 actual=20
EOF
expect_rc 1 "parse: field with ':' rejected"  --parse "$BAD_FIELD"

# Field with '=' (would create parse ambiguity)
BAD_EQ="$TEST_OUT/bad-eq.txt"
cat > "$BAD_EQ" <<'EOF'
PLAN-TEXT-DRIFT: phase=1 bullet=3 field=has=eq plan=10 actual=20
EOF
expect_rc 1 "parse: field with '=' rejected"  --parse "$BAD_EQ"

# Missing 'actual=' altogether
BAD_MISSING="$TEST_OUT/bad-missing.txt"
cat > "$BAD_MISSING" <<'EOF'
PLAN-TEXT-DRIFT: phase=1 bullet=3 field=foo plan=10
EOF
expect_rc 1 "parse: missing 'actual=' rejected"  --parse "$BAD_MISSING"

echo ""
echo "=== --correct: in-place edit with audit comment ==="
PLAN="$TEST_OUT/plan-correct.md"
cat > "$PLAN" <<'EOF'
## Phase 1 — Foo

### Acceptance Criteria

- [ ] Skill is approximately 357 lines (target band 340-380).
- [ ] Test count at most 50.

## Phase 2 — Bar

### Acceptance Criteria

- [ ] Something.
EOF
bash "$SCRIPT" --correct "$PLAN" 1 1 "277" --audit "approximately 357" >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then
  fail "correct: exit code 0 expected, got $rc"
else
  if grep -q 'Skill is 277 lines' "$PLAN" && grep -q 'Auto-corrected' "$PLAN" && grep -q 'was approximately 357' "$PLAN"; then
    pass "correct: bullet rewritten + audit comment appended"
  else
    fail "correct: edit didn't apply expected substitutions in $PLAN"
  fi
fi

echo ""
echo "=== --correct: phase not found ==="
PLAN_NF="$TEST_OUT/plan-no-phase.md"
cat > "$PLAN_NF" <<'EOF'
## Phase 1 — Foo

### Acceptance Criteria

- [ ] Approximately 100.
EOF
expect_rc 1 "correct: phase 7 (not present) returns rc=1"  --correct "$PLAN_NF" 7 1 "200" --audit "Approximately 100"

echo ""
echo "=== --correct: bullet ordinal too large ==="
expect_rc 1 "correct: bullet 99 doesn't exist returns rc=1"  --correct "$PLAN_NF" 1 99 "200" --audit "Approximately 100"

echo ""
echo "=== --correct: --audit literal not found ==="
expect_rc 1 "correct: --audit literal not in line returns rc=1"  --correct "$PLAN_NF" 1 1 "200" --audit "completely-unrelated-string"

echo ""
echo "=== --correct: --audit required (no heuristic substitution) ==="
expect_rc 1 "correct: missing --audit refused"  --correct "$PLAN_NF" 1 1 "200"

echo ""
echo "=== --correct: invalid phase / bullet syntax ==="
expect_rc 2 "correct: phase 'abc' is invalid"  --correct "$PLAN_NF" "abc" 1 "200" --audit "Approximately 100"
expect_rc 2 "correct: bullet '0' is invalid (must be ≥1)"  --correct "$PLAN_NF" 1 0 "200" --audit "Approximately 100"

echo ""
echo "=== general usage errors ==="
expect_rc 2 "no args"  ""
expect_rc 2 "unknown mode"  --bogus
expect_rc 2 "drift: missing actual"  --drift "100"
expect_rc 2 "drift: non-integer actual"  --drift "100" "ten"
expect_rc 2 "parse: file not found"  --parse "/tmp/zskills-tests/nonexistent-$$.txt"

echo ""
echo "---"
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (of %d)\033[0m\n' "$PASS_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (of %d)\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit 1
fi
