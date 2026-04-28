#!/bin/bash
# Tests for skills/run-plan/scripts/plan-drift-correct.sh.
#
# Covers all three modes (--parse, --drift, --correct) across the five
# supported <stated> forms (range, ≤, ≥, ~/literal, exactly), plus the
# error / "unsupported" / "unlocatable" exit branches. Per CLAUDE.md,
# scratch fixtures live under /tmp/zskills-tests/<basename-of-cwd>/.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/skills/run-plan/scripts/plan-drift-correct.sh"

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
echo "=== Phase 3.5 orchestration: simulated end-to-end --parse → --drift → --correct ==="
# Simulates the orchestrator's workflow: an agent's combined report contains a
# PLAN-TEXT-DRIFT token; a stale plan file's acceptance band gets corrected.
E2E_REPORT="$TEST_OUT/e2e-report.txt"
cat > "$E2E_REPORT" <<'EOF'
Implementation report.

PLAN-TEXT-DRIFT: phase=2 bullet=1 field=skill-line-count plan=approximately 357 actual=277

Done.
EOF
E2E_PLAN="$TEST_OUT/e2e-plan.md"
cat > "$E2E_PLAN" <<'EOF'
## Phase 2 — Foo

### Acceptance Criteria

- [ ] Skill is approximately 357 lines after restructure.
- [ ] Other thing.
EOF
parse_out=$(bash "$SCRIPT" --parse "$E2E_REPORT" 2>&1); parse_rc=$?
e2e_record="2|1|skill-line-count|approximately 357|277"
if [ "$parse_rc" = "0" ] && [ "$parse_out" = "$e2e_record" ]; then
  # Decompose record (using bash IFS split; no eval, no $(()) over user input).
  IFS='|' read -r e2e_phase e2e_bullet _e2e_field e2e_stated e2e_actual <<< "$parse_out"
  drift_out=$(bash "$SCRIPT" --drift "$e2e_stated" "$e2e_actual" 2>&1); drift_rc=$?
  if [ "$drift_rc" = "0" ] && [ "$drift_out" = "23" ]; then
    bash "$SCRIPT" --correct "$E2E_PLAN" "$e2e_phase" "$e2e_bullet" "$e2e_actual" --audit "$e2e_stated" >/dev/null 2>&1
    correct_rc=$?
    if [ "$correct_rc" = "0" ] \
        && grep -q 'Skill is 277 lines after restructure' "$E2E_PLAN" \
        && grep -q 'Auto-corrected' "$E2E_PLAN" \
        && grep -q 'was approximately 357' "$E2E_PLAN"; then
      pass "Phase 3.5 e2e: parse → drift → correct lands audited band"
    else
      fail "Phase 3.5 e2e: --correct stage failed (rc=$correct_rc, plan content unexpected)"
    fi
  else
    fail "Phase 3.5 e2e: --drift stage — expected '23', got rc=$drift_rc out='$drift_out'"
  fi
else
  fail "Phase 3.5 e2e: --parse stage — expected rc=0 + '$e2e_record', got rc=$parse_rc out='$parse_out'"
fi

echo ""
echo "=== Phase 3.5 orchestration: thrash determinism (same phase+bullet, repeat --correct) ==="
# The orchestrator enforces the thrash-rule (abort on second correction). The
# script itself must be deterministic on repeat: a second --correct invocation
# with a literal that matches the post-first-correction text must succeed and
# produce the same end-state band, so the orchestrator's re-detection of a
# PLAN-TEXT-DRIFT token after a correction reflects a real drift, not script
# nondeterminism.
THRASH_PLAN="$TEST_OUT/thrash-plan.md"
cat > "$THRASH_PLAN" <<'EOF'
## Phase 1 — Bar

### Acceptance Criteria

- [ ] Foo is approximately 100 widgets.
EOF
bash "$SCRIPT" --correct "$THRASH_PLAN" 1 1 "120" --audit "approximately 100" >/dev/null 2>&1
first_rc=$?
# After first correction, the line literal is now "120"; second --correct must
# locate the new literal and rewrite to a third value deterministically.
bash "$SCRIPT" --correct "$THRASH_PLAN" 1 1 "150" --audit "120" >/dev/null 2>&1
second_rc=$?
audit_count=$(grep -o 'Auto-corrected' "$THRASH_PLAN" | wc -l | tr -d ' ')
if [ "$first_rc" = "0" ] && [ "$second_rc" = "0" ] \
    && grep -q 'Foo is 150 widgets' "$THRASH_PLAN" \
    && [ "$audit_count" = "2" ]; then
  pass "Phase 3.5 thrash: --correct deterministic on repeat (orchestrator enforces abort, not script)"
else
  fail "Phase 3.5 thrash: first_rc=$first_rc second_rc=$second_rc, audit-comments=$audit_count"
fi

echo ""
echo "=== Phase 3.5 orchestration: >20% drift escalation signal ==="
# >20% drift case from decision-table: orchestrator reads --drift output and
# routes >20 to ABORT (no --correct call). Verify --drift returns >20 in
# representative shapes.
out=$(bash "$SCRIPT" --drift "100" "200" 2>&1)
if [ "$out" = "100" ]; then
  pass "Phase 3.5 escalate: literal 100 vs 200 → drift=100 (>20, ABORT)"
else
  fail "Phase 3.5 escalate: literal — expected 100, got '$out'"
fi

out=$(bash "$SCRIPT" --drift "approximately 50" "100" 2>&1)
if [ "$out" = "100" ]; then
  pass "Phase 3.5 escalate: approximately 50 vs 100 → drift=100 (>20, ABORT)"
else
  fail "Phase 3.5 escalate: approximately — expected 100, got '$out'"
fi

echo ""
echo "=== Phase 3.5 orchestration: multi-drift report → per-record correction ==="
# Two drifts in one combined-report; orchestrator parses, drifts each, corrects
# each independently. End state: both bands rewritten with audit comments.
MULTI_REPORT="$TEST_OUT/e2e-multi-report.txt"
cat > "$MULTI_REPORT" <<'EOF'
PLAN-TEXT-DRIFT: phase=1 bullet=1 field=count-a plan=approximately 100 actual=110
PLAN-TEXT-DRIFT: phase=1 bullet=2 field=count-b plan=at most 50 actual=45
EOF
MULTI_PLAN="$TEST_OUT/e2e-multi-plan.md"
cat > "$MULTI_PLAN" <<'EOF'
## Phase 1 — Multi

### Acceptance Criteria

- [ ] Count A is approximately 100.
- [ ] Count B is at most 50.
EOF
parsed=$(bash "$SCRIPT" --parse "$MULTI_REPORT" 2>&1); prc=$?
expected_two='1|1|count-a|approximately 100|110
1|2|count-b|at most 50|45'
if [ "$prc" = "0" ] && [ "$parsed" = "$expected_two" ]; then
  multi_ok=1
  while IFS='|' read -r mp mb _mf ms ma; do
    bash "$SCRIPT" --correct "$MULTI_PLAN" "$mp" "$mb" "$ma" --audit "$ms" >/dev/null 2>&1 || multi_ok=0
  done <<< "$parsed"
  if [ "$multi_ok" = "1" ] \
      && grep -q 'Count A is 110' "$MULTI_PLAN" \
      && grep -q 'Count B is 45' "$MULTI_PLAN" \
      && [ "$(grep -c 'Auto-corrected' "$MULTI_PLAN")" = "2" ]; then
    pass "Phase 3.5 multi: parse → loop → correct lands two audited bands"
  else
    fail "Phase 3.5 multi: corrections didn't land cleanly (multi_ok=$multi_ok)"
  fi
else
  fail "Phase 3.5 multi: --parse expected 2 records, got rc=$prc out='$parsed'"
fi

echo ""
echo "=== --eval: integer arithmetic happy path ==="
# expect_eval <label> <expr> <expected-stdout>
expect_eval() {
  local label="$1" expr="$2" expected="$3"
  local out
  out=$(bash "$SCRIPT" --eval "$expr" 2>&1)
  local rc=$?
  if [ "$rc" = "0" ] && [ "$out" = "$expected" ]; then
    pass "$label  ($expr → $out)"
  else
    fail "$label — expected '$expected' rc=0, got '$out' rc=$rc  ($expr)"
  fi
}

expect_eval "AC: 417 - 94 - 60 + 15"          "417 - 94 - 60 + 15"  278
expect_eval "simple add 100 + 200"             "100 + 200"           300
expect_eval "single integer 42"                "42"                  42
expect_eval "leading minus -5 + 10"            "-5 + 10"             5
expect_eval "negative result 10 - 100"         "10 - 100"            -90
expect_eval "whitespace tolerant 1+2"          "1+2"                 3
expect_eval "extra whitespace tolerant"        "  10   +   20   "    30
expect_eval "tab whitespace"                   $'1\t+\t2'            3
expect_eval "long chain"                       "1 + 2 + 3 + 4 + 5"   15

echo ""
echo "=== --eval: unsupported operators / chars rejected with rc=2 ==="
expect_rc 2 "AC: '417 * 2' (multiplication)"   --eval "417 * 2"
expect_rc 2 "division '10 / 2'"                --eval "10 / 2"
expect_rc 2 "parens '(1 + 2)'"                 --eval "(1 + 2)"
expect_rc 2 "variable 'x + 1'"                 --eval "x + 1"
expect_rc 2 "decimal '1.5 + 2'"                --eval "1.5 + 2"
expect_rc 2 "comma '1, 2'"                     --eval "1, 2"
expect_rc 2 "shell metachar '\$(echo 1)'"      --eval '$(echo 1)'
expect_rc 2 "backtick injection"               --eval '`id`'
expect_rc 2 "semicolon"                        --eval "1 ; 2"
expect_rc 2 "empty expression"                 --eval ""
expect_rc 2 "whitespace-only expression"       --eval "   "
expect_rc 2 "trailing operator '1 + 2 +'"      --eval "1 + 2 +"
expect_rc 2 "leading operator-only expr"       --eval "+"
expect_rc 2 "missing arg (no expr)"            --eval

echo ""
echo "=== --eval: pre-dispatch arithmetic gate (Phase 1 step 6 sub-check b) ==="
# Simulates orchestrator workflow: plan-text drift between an extraction
# rule "extract lines 100-200" and an acceptance band "50-70 lines."
# Math: 200 - 100 + 1 = 101 (derived). Band midpoint is 60. Drift is large.
derived=$(bash "$SCRIPT" --eval "200 - 100 + 1" 2>&1); ev_rc=$?
if [ "$ev_rc" = "0" ] && [ "$derived" = "101" ]; then
  pass "pre-dispatch: --eval derives 101 from 'lines 100-200' rule"
else
  fail "pre-dispatch: --eval expected 101, got rc=$ev_rc out='$derived'"
fi

# Feed derived value into --drift against the stated band "50-70"
drift_out=$(bash "$SCRIPT" --drift "50-70" "$derived" 2>&1); dr_rc=$?
# midpoint(50,70)=60; |101-60|=41; ceil(41*100/60)=ceil(68.33)=69
if [ "$dr_rc" = "0" ] && [ "$drift_out" = "69" ]; then
  pass "pre-dispatch: --drift '50-70' vs derived=101 → 69% (large, escalate)"
else
  fail "pre-dispatch: --drift expected 69, got rc=$dr_rc out='$drift_out'"
fi

# Verify the drift is >20%, which the orchestrator would route to ABORT/refine-plan.
if [ "$drift_out" -gt 20 ] 2>/dev/null; then
  pass "pre-dispatch: drift=$drift_out exceeds 20% threshold (orchestrator escalates)"
else
  fail "pre-dispatch: drift=$drift_out should exceed 20% but did not"
fi

echo ""
echo "=== --eval: pre-dispatch 'non-derivable' skip path ==="
# Phase 3 plan: when an acceptance bullet has a numeric claim but the
# extraction rule isn't one of the supported forms (literal arithmetic,
# 'lines N-M'), the orchestrator skips the bullet. The script's role in
# this path is: --eval rejects the unsupported expression with rc=2, and
# the orchestrator interprets rc=2 as "non-derivable, skip."
bash "$SCRIPT" --eval "roughly N lines per Y files" >/dev/null 2>&1
nd_rc=$?
if [ "$nd_rc" = "2" ]; then
  pass "pre-dispatch: --eval rc=2 on natural-language rule → 'non-derivable' skip"
else
  fail "pre-dispatch: --eval on non-derivable expected rc=2, got rc=$nd_rc"
fi

# Same for an extraction rule with multiplication (out of v1 grammar).
bash "$SCRIPT" --eval "10 * 5" >/dev/null 2>&1
nd2_rc=$?
if [ "$nd2_rc" = "2" ]; then
  pass "pre-dispatch: --eval rc=2 on multiplication → 'non-derivable' skip"
else
  fail "pre-dispatch: --eval on multiplication expected rc=2, got rc=$nd2_rc"
fi

echo ""
echo "=== --eval: injection-surface containment ==="
# DA-7 concern: untrusted plan text reaches --eval; ensure no shell
# expansion / no command execution. The ONLY valid output is an integer
# or rc=2. We assert no marker-file is created by these inputs.
INJ_MARK="$TEST_OUT/eval-injection-canary-$$.flag"
rm -f "$INJ_MARK"
# Each of these should rc=2 without side effects.
bash "$SCRIPT" --eval "\$(touch $INJ_MARK)" >/dev/null 2>&1 || true
bash "$SCRIPT" --eval "1; touch $INJ_MARK" >/dev/null 2>&1 || true
bash "$SCRIPT" --eval "1 \`touch $INJ_MARK\`" >/dev/null 2>&1 || true
bash "$SCRIPT" --eval "1 && touch $INJ_MARK" >/dev/null 2>&1 || true
if [ ! -e "$INJ_MARK" ]; then
  pass "pre-dispatch: --eval rejects shell-injection surface (no marker created)"
else
  fail "pre-dispatch: --eval LEAKED — marker file '$INJ_MARK' was created"
  rm -f "$INJ_MARK"
fi

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
