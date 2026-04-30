#!/bin/bash
# Tests for skills/draft-tests/ -- Phase 3 (drafting agent and test-spec
# format).
#
# Phase 3 spec: plans/DRAFT_TESTS_SKILL_PLAN.md, work items 3.1-3.8,
# acceptance criteria AC-3.1 through AC-3.6.
#
# Tests mechanically exercise the orchestrator (`draft-orchestrator.sh`)
# and append script (`append-tests-section.sh`) by stubbing the
# drafter agent's output as a pre-built specs file. No live LLM calls.
#
# Run from repo root: bash tests/test-draft-tests-phase3.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_DIR="$REPO_ROOT/skills/draft-tests"
SKILL_MD="$SKILL_DIR/SKILL.md"
PARSE_SCRIPT="$SKILL_DIR/scripts/parse-plan.sh"
APPEND_SCRIPT="$SKILL_DIR/scripts/append-tests-section.sh"
ORCH_SCRIPT="$SKILL_DIR/scripts/draft-orchestrator.sh"
FIXTURES="$REPO_ROOT/tests/fixtures/draft-tests"
P3="$FIXTURES/p3"

TEST_OUT="/tmp/zskills-tests/$(basename "$REPO_ROOT")/draft-tests-p3"
mkdir -p "$TEST_OUT"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# Read a parsed-state list (lines under a `<key>:` heading, indented two
# spaces) into stdout. Stops at the next non-indented line.
read_state_list() {
  local state_file="$1" key="$2"
  awk -v k="$key:" '
    $0 == k { active=1; next }
    active && /^  / { sub(/^  /, ""); print; next }
    active && /^[^ ]/ { active=0 }
  ' "$state_file"
}

# Count `### Tests` subsections in a plan (outside fenced code blocks).
count_tests_subsections() {
  awk '
    BEGIN { in_code=0; n=0 }
    /^```/ { in_code = 1 - in_code; next }
    in_code { next }
    /^### Tests([ \t]|$)/ { n++ }
    END { print n }
  ' "$1"
}

# Count `### Tests` subsections inside a specific phase body.
count_tests_in_phase() {
  local plan="$1" pid="$2"
  awk -v target="$pid" '
    BEGIN { in_code=0; in_phase=0; n=0 }
    /^```/ { in_code = 1 - in_code; next }
    in_code { next }
    /^## Phase / {
      line=$0
      sub(/^## Phase[[:space:]]+/, "", line)
      split(line, parts, /[ \t:]/)
      pid = parts[1]
      if (pid == target) { in_phase=1; next }
      if (in_phase) { exit }
      next
    }
    in_phase && /^## / { exit }
    in_phase && /^### Tests([ \t]|$)/ { n++ }
    END { print n }
  ' "$plan"
}

# Set up a fresh working copy of a fixture under TEST_OUT/<slug>/<plan>.
prepare_fixture() {
  local fixture="$1" slug="$2"
  local dir="$TEST_OUT/$slug"
  mkdir -p "$dir"
  cp "$fixture" "$dir/plan.md"
  printf '%s' "$dir/plan.md"
}

# ==========================================================================
# AC-3.1 -- N − K subsections (4 non-delegate phases, K=1 ac-less => 3 Tests).
# ==========================================================================
echo ""
echo "=== AC-3.1 -- N − K coverage ==="

PLAN1="$(prepare_fixture "$P3/n-minus-k.md" n-minus-k)"
STATE1="$TEST_OUT/n-minus-k/parsed.md"
bash "$PARSE_SCRIPT" "$PLAN1" "$STATE1" 2>"$TEST_OUT/n-minus-k/parse.stderr"
rc=$?
if [ $rc -eq 0 ]; then
  pass "AC-3.1: parse-plan.sh exits 0 on n-minus-k fixture"
else
  fail "AC-3.1: parse-plan.sh exited rc=$rc on n-minus-k fixture"
fi

NDP="$(read_state_list "$STATE1" non_delegate_pending_phases | LC_ALL=C sort | tr '\n' ',' )"
ACL="$(read_state_list "$STATE1" ac_less | LC_ALL=C sort | tr '\n' ',')"
if [ "$NDP" = "1,2,3,4," ]; then
  pass "AC-3.1: parsed-state non_delegate_pending = {1,2,3,4}"
else
  fail "AC-3.1: non_delegate_pending mismatch (got '$NDP')"
fi
if [ "$ACL" = "3," ]; then
  pass "AC-3.1: parsed-state ac_less = {3}"
else
  fail "AC-3.1: ac_less mismatch (got '$ACL')"
fi

# Build a specs file for the 3 non-ac-less phases.
SPECS1="$TEST_OUT/n-minus-k/specs.md"
cat > "$SPECS1" <<'EOF'
phase: 1
- [unit] [risk: AC-1.1] given input 0, when first() is called, expect output 1.
phase: 2
- [unit] [risk: AC-2.1] given input "a", when second() is called, expect output "A".
phase: 4
- [unit] [risk: AC-4.1] given input [], when fourth() is called, expect raises ValueError("empty input").
EOF

ROUND1="$TEST_OUT/n-minus-k/draft-round-0.md"
bash "$ORCH_SCRIPT" "$PLAN1" "$STATE1" "$SPECS1" "$ROUND1" 0 \
  > "$TEST_OUT/n-minus-k/orch.stdout" 2> "$TEST_OUT/n-minus-k/orch.stderr"
rc=$?
if [ $rc -eq 0 ]; then
  pass "AC-3.1: draft-orchestrator.sh exits 0 on n-minus-k fixture"
else
  fail "AC-3.1: draft-orchestrator.sh exited rc=$rc — stderr: $(cat "$TEST_OUT/n-minus-k/orch.stderr" 2>/dev/null)"
fi

TOTAL_TESTS="$(count_tests_subsections "$PLAN1")"
if [ "$TOTAL_TESTS" = "3" ]; then
  pass "AC-3.1: plan has exactly N−K=3 ### Tests subsections"
else
  fail "AC-3.1: expected 3 ### Tests subsections, got $TOTAL_TESTS"
fi

# Each non-ac-less Pending phase has exactly one Tests subsection.
for pid in 1 2 4; do
  cnt="$(count_tests_in_phase "$PLAN1" "$pid")"
  if [ "$cnt" = "1" ]; then
    pass "AC-3.1: phase $pid has exactly 1 ### Tests subsection"
  else
    fail "AC-3.1: phase $pid has $cnt ### Tests subsections (expected 1)"
  fi
done

# Phase 3 (ac-less) has zero Tests subsections.
ACLESS_CNT="$(count_tests_in_phase "$PLAN1" 3)"
if [ "$ACLESS_CNT" = "0" ]; then
  pass "AC-3.1: ac-less phase 3 has zero ### Tests subsections"
else
  fail "AC-3.1: ac-less phase 3 has $ACLESS_CNT ### Tests subsections (expected 0)"
fi

# Each subsection contains at least one bullet with `risk: AC-<phase>.<n>`.
for pid in 1 2 4; do
  if grep -E -q "risk: AC-${pid}\.[0-9]+" "$PLAN1"; then
    pass "AC-3.1: phase $pid spec references its own AC via risk:"
  else
    fail "AC-3.1: phase $pid spec missing risk: AC-${pid}.N reference"
  fi
done

# Round-0 output records drafted_phases = {1,2,4}.
DRAFTED="$(read_state_list "$ROUND1" drafted_phases | LC_ALL=C sort | tr '\n' ',')"
if [ "$DRAFTED" = "1,2,4," ]; then
  pass "AC-3.1: round-0 drafted_phases = {1,2,4}"
else
  fail "AC-3.1: round-0 drafted_phases mismatch (got '$DRAFTED')"
fi

# AC-less skipped is recorded.
ACLESSDRAFT="$(read_state_list "$ROUND1" ac_less_skipped_phases | LC_ALL=C sort | tr '\n' ',')"
if [ "$ACLESSDRAFT" = "3," ]; then
  pass "AC-3.1: round-0 ac_less_skipped_phases = {3}"
else
  fail "AC-3.1: round-0 ac_less_skipped_phases mismatch (got '$ACLESSDRAFT')"
fi

# ==========================================================================
# AC-3.2 -- spec format regex (one-line and multi-line) including sub-letter.
# ==========================================================================
echo ""
echo "=== AC-3.2 -- spec format regex conformance ==="

PLAN2="$(prepare_fixture "$P3/regex-conformance.md" regex-conformance)"
STATE2="$TEST_OUT/regex-conformance/parsed.md"
bash "$PARSE_SCRIPT" "$PLAN2" "$STATE2" 2>/dev/null

# Specs file with both one-line and multi-line forms, including a
# sub-letter AC reference (AC-1.6c).
SPECS2="$TEST_OUT/regex-conformance/specs.md"
cat > "$SPECS2" <<'EOF'
phase: 1
- [unit] [risk: AC-1.1] given f(0), when called, expect output 0.
- [integration] [risk: AC-1.6c] given config flag set to true, when service starts, expect log line "subletter ok" emitted.
- [property] [risk: AC-1.1] property: for all positive integers n, expect f(n) > f(n-1).
- [e2e] [risk: AC-1.6c] multi-line spec name
  - Input: a fully-rendered SVG with 3 nodes and 4 edges (literal fixture file fixtures/svg-3n-4e.xml)
  - Action: invoke the simulate() pipeline with default seed 42
  - Expected: pipeline returns {status: "ok", node_count: 3, edge_count: 4}
  - Rationale: covers the integration of the renderer with the simulator under stable conditions.
EOF

ROUND2="$TEST_OUT/regex-conformance/draft-round-0.md"
bash "$ORCH_SCRIPT" "$PLAN2" "$STATE2" "$SPECS2" "$ROUND2" 0 \
  > "$TEST_OUT/regex-conformance/orch.stdout" 2> "$TEST_OUT/regex-conformance/orch.stderr"
rc=$?
if [ $rc -eq 0 ]; then
  pass "AC-3.2: orchestrator exits 0 on regex-conformance fixture"
else
  fail "AC-3.2: orchestrator exited rc=$rc"
fi

# Extract every spec bullet from the inserted ### Tests subsection.
SPEC_BULLETS="$TEST_OUT/regex-conformance/spec-bullets.txt"
awk '
  BEGIN { in_code=0; in_tests=0 }
  /^```/ { in_code = 1 - in_code; next }
  in_code { next }
  /^### Tests([ \t]|$)/ { in_tests=1; next }
  in_tests && /^### / { in_tests=0; next }
  in_tests && /^## / { in_tests=0; next }
  in_tests && /^- \[/ { print }
' "$PLAN2" > "$SPEC_BULLETS"

# AC-3.2 regex (extended).
RE='^- \[(unit|integration|property|e2e)\] \[risk: AC-[0-9]+[a-z]?\.[0-9]+[a-z]?\]'
n_total=0
n_match=0
while IFS= read -r bullet; do
  n_total=$((n_total + 1))
  if [[ "$bullet" =~ $RE ]]; then
    n_match=$((n_match + 1))
  fi
done < "$SPEC_BULLETS"

if [ "$n_total" -gt 0 ] && [ "$n_match" -eq "$n_total" ]; then
  pass "AC-3.2: every spec bullet ($n_total) matches the canonical header regex"
else
  fail "AC-3.2: $n_match/$n_total spec bullets matched the canonical regex (regex: $RE)"
fi

# Verify the sub-letter AC-1.6c is admitted.
if grep -E -q '^- \[(unit|integration|property|e2e)\] \[risk: AC-1\.6c\]' "$SPEC_BULLETS"; then
  pass "AC-3.2: sub-letter AC-1.6c is admitted by the regex (matched)"
else
  fail "AC-3.2: sub-letter AC-1.6c bullet missing or did not match canonical regex"
fi

# Verify the multi-line expansion (Input/Action/Expected/Rationale)
# survived insertion.
if grep -F -q '  - Input:' "$PLAN2" \
   && grep -F -q '  - Action:' "$PLAN2" \
   && grep -F -q '  - Expected:' "$PLAN2" \
   && grep -F -q '  - Rationale:' "$PLAN2"; then
  pass "AC-3.2: multi-line expansion (Input/Action/Expected/Rationale) preserved"
else
  fail "AC-3.2: multi-line expansion sub-bullets missing in the plan"
fi

# ==========================================================================
# AC-3.3 -- vague placeholder regression (negative assertion).
# ==========================================================================
echo ""
echo "=== AC-3.3 -- vague placeholder regression ==="

# Reuse the n-minus-k post-orchestration plan and the regex-conformance
# plan and assert no spec bullet contains a blocked vague word in the
# Expected/expect clause. The blocklist reflects the AC-3.3 wording.
BLOCKLIST_RE='\bsomething\b|\bappropriate\b|\breasonable\b|\bsensible\b|\bproperly\b'

# Build a synthetic specs file containing a vague placeholder; orchestrator
# accepts it (it is the drafter's job not to produce these), but the
# regression test scans the specs we produced under the GOOD fixtures
# above and asserts the blocked pattern is absent.

# Scan all spec bullets we authored in AC-3.1 and AC-3.2 for blocked
# vague words. They were authored to be literal — none should match.
all_spec_files=("$SPECS1" "$SPECS2")
violations=0
for sf in "${all_spec_files[@]}"; do
  while IFS= read -r line; do
    [[ "$line" =~ ^phase: ]] && continue
    if [[ "$line" =~ $BLOCKLIST_RE ]]; then
      violations=$((violations + 1))
      printf '    blocked-word in: %s\n' "$line" >&2
    fi
  done < "$sf"
done
if [ "$violations" -eq 0 ]; then
  pass "AC-3.3: zero vague placeholders in test-authored spec corpus"
else
  fail "AC-3.3: $violations spec bullets contain a vague placeholder word"
fi

# Negative-control: a fixture spec WITH a vague placeholder must trigger
# the regression detector. (Confirms the test logic itself is correct.)
NEGATIVE_SPECS="$TEST_OUT/regex-conformance/negative-specs.txt"
printf -- '- [unit] [risk: AC-1.1] given input, when called, expect something appropriate.\n' > "$NEGATIVE_SPECS"
if grep -E -q "$BLOCKLIST_RE" "$NEGATIVE_SPECS"; then
  pass "AC-3.3: negative control — blocklist detects the vague phrasing"
else
  fail "AC-3.3: negative control — blocklist failed to detect 'something appropriate'"
fi

# ==========================================================================
# AC-3.4 -- config-set vs config-absent in drafter prompt assembly.
# Mechanical proxy: SKILL.md prose contains the assembly logic mandating
# either verbatim cmd or the literal "no configured test runner" string.
# Phase 2 already verifies the detection-state path. Here we verify the
# Phase 3 prose mandates the prompt-assembly behavior.
# ==========================================================================
echo ""
echo "=== AC-3.4 -- config-set vs config-absent prompt assembly ==="

if grep -F -q 'config_unit_cmd' "$SKILL_MD"; then
  pass "AC-3.4: SKILL.md Phase 3 prose references config_unit_cmd from detection-state"
else
  fail "AC-3.4: SKILL.md Phase 3 prose missing config_unit_cmd reference"
fi

if grep -F -q 'no configured test runner' "$SKILL_MD"; then
  pass "AC-3.4: SKILL.md Phase 3 prose mandates literal 'no configured test runner' string"
else
  fail "AC-3.4: SKILL.md Phase 3 prose missing 'no configured test runner' literal"
fi

# Verify that running detect-language.sh on the config-set fixture
# resolves config_unit_cmd to the configured value, which the Phase 3
# prompt-assembly logic must pass verbatim.
DETECT_SCRIPT="$SKILL_DIR/scripts/detect-language.sh"
DETECT_STATE="$TEST_OUT/detect-config-set.md"
bash "$DETECT_SCRIPT" "$P3/../p2/config-set" "$DETECT_STATE" 2>/dev/null
CONFIG_UNIT="$(awk -F': *' '$1 == "config_unit_cmd" { sub(/^[^:]+:[[:space:]]*/, ""); print; exit }' "$DETECT_STATE")"
if [ "$CONFIG_UNIT" = "make test-unit" ]; then
  pass "AC-3.4: config-set fixture surfaces config_unit_cmd = 'make test-unit'"
else
  fail "AC-3.4: config_unit_cmd mismatch (got '$CONFIG_UNIT', expected 'make test-unit')"
fi

# Config-absent: a fresh empty project.
EMPTY_PROJECT="$TEST_OUT/empty-project"
mkdir -p "$EMPTY_PROJECT/.claude"
DETECT_STATE_EMPTY="$TEST_OUT/detect-empty.md"
bash "$DETECT_SCRIPT" "$EMPTY_PROJECT" "$DETECT_STATE_EMPTY" 2>/dev/null
CONFIG_UNIT_EMPTY="$(awk -F': *' '$1 == "config_unit_cmd" { sub(/^[^:]+:[[:space:]]*/, ""); print; exit }' "$DETECT_STATE_EMPTY")"
if [ -z "$CONFIG_UNIT_EMPTY" ]; then
  pass "AC-3.4: config-absent fixture leaves config_unit_cmd empty (triggers 'no configured test runner' branch)"
else
  fail "AC-3.4: config_unit_cmd should be empty in config-absent path (got '$CONFIG_UNIT_EMPTY')"
fi

# ==========================================================================
# AC-3.5 -- re-invocation idempotency (byte-identical second run).
# ==========================================================================
echo ""
echo "=== AC-3.5 -- re-invocation idempotency ==="

PLAN5="$(prepare_fixture "$P3/idempotency.md" idempotency)"
STATE5="$TEST_OUT/idempotency/parsed.md"
bash "$PARSE_SCRIPT" "$PLAN5" "$STATE5" 2>/dev/null

SPECS5="$TEST_OUT/idempotency/specs.md"
cat > "$SPECS5" <<'EOF'
phase: 1
- [unit] [risk: AC-1.1] given x = 0, when one() is called, expect output 0.
phase: 2
- [unit] [risk: AC-2.1] given x = 1, when two() is called, expect output 2.
EOF

ROUND5_FIRST="$TEST_OUT/idempotency/round-0-first.md"
bash "$ORCH_SCRIPT" "$PLAN5" "$STATE5" "$SPECS5" "$ROUND5_FIRST" 0 \
  > /dev/null 2> "$TEST_OUT/idempotency/orch1.stderr"
rc1=$?
PLAN5_SNAPSHOT="$TEST_OUT/idempotency/plan-after-first.md"
cp "$PLAN5" "$PLAN5_SNAPSHOT"

# Second run: same inputs.
ROUND5_SECOND="$TEST_OUT/idempotency/round-0-second.md"
bash "$ORCH_SCRIPT" "$PLAN5" "$STATE5" "$SPECS5" "$ROUND5_SECOND" 0 \
  > /dev/null 2> "$TEST_OUT/idempotency/orch2.stderr"
rc2=$?

if [ $rc1 -eq 0 ] && [ $rc2 -eq 0 ]; then
  pass "AC-3.5: orchestrator exits 0 on first AND second runs"
else
  fail "AC-3.5: orchestrator rc1=$rc1 rc2=$rc2 (expected 0,0)"
fi

if cmp -s "$PLAN5_SNAPSHOT" "$PLAN5"; then
  pass "AC-3.5: plan file byte-identical between first and second runs"
else
  fail "AC-3.5: plan file differs between runs (diff -u below)"
  diff -u "$PLAN5_SNAPSHOT" "$PLAN5" | head -40 >&2
fi

# Second-run round-0 output records the phases as idempotently skipped.
IDEMPOTENT="$(read_state_list "$ROUND5_SECOND" idempotent_skipped_phases | LC_ALL=C sort | tr '\n' ',')"
if [ "$IDEMPOTENT" = "1,2," ]; then
  pass "AC-3.5: round-0 second-run idempotent_skipped_phases = {1,2}"
else
  fail "AC-3.5: round-0 second-run idempotent_skipped_phases mismatch (got '$IDEMPOTENT')"
fi

# Drafted_phases on the second run is empty (everything was skipped).
DRAFTED2="$(read_state_list "$ROUND5_SECOND" drafted_phases | LC_ALL=C sort | tr '\n' ',')"
if [ -z "$DRAFTED2" ]; then
  pass "AC-3.5: round-0 second-run drafted_phases is empty"
else
  fail "AC-3.5: round-0 second-run drafted_phases should be empty (got '$DRAFTED2')"
fi

# Confirm exactly one ### Tests subsection per phase (no nesting/dup).
for pid in 1 2; do
  cnt="$(count_tests_in_phase "$PLAN5" "$pid")"
  if [ "$cnt" = "1" ]; then
    pass "AC-3.5: phase $pid has exactly 1 ### Tests subsection after re-run"
  else
    fail "AC-3.5: phase $pid has $cnt ### Tests subsections after re-run (expected 1)"
  fi
done

# ==========================================================================
# AC-3.6 -- delegate phases skipped + set-equality of delegate_phases:
# (parsed-state) vs delegate_skipped_phases: (drafter output).
# ==========================================================================
echo ""
echo "=== AC-3.6 -- delegate skip and set-equality ==="

PLAN6="$(prepare_fixture "$P3/delegate-skip.md" delegate-skip)"
STATE6="$TEST_OUT/delegate-skip/parsed.md"
bash "$PARSE_SCRIPT" "$PLAN6" "$STATE6" 2>/dev/null

DELEGATE_LIST="$(read_state_list "$STATE6" delegate_phases | LC_ALL=C sort | tr '\n' ',')"
NDP_LIST="$(read_state_list "$STATE6" non_delegate_pending_phases | LC_ALL=C sort | tr '\n' ',')"
if [ "$DELEGATE_LIST" = "2," ]; then
  pass "AC-3.6: parsed-state delegate_phases = {2}"
else
  fail "AC-3.6: delegate_phases mismatch (got '$DELEGATE_LIST')"
fi
if [ "$NDP_LIST" = "1,3," ]; then
  pass "AC-3.6: parsed-state non_delegate_pending_phases = {1,3}"
else
  fail "AC-3.6: non_delegate_pending_phases mismatch (got '$NDP_LIST')"
fi

SPECS6="$TEST_OUT/delegate-skip/specs.md"
cat > "$SPECS6" <<'EOF'
phase: 1
- [unit] [risk: AC-1.1] given x = 0, when normal() is called, expect output 0.
phase: 3
- [unit] [risk: AC-3.1] given x = 1, when normal_two() is called, expect output 1.
EOF

ROUND6="$TEST_OUT/delegate-skip/draft-round-0.md"
bash "$ORCH_SCRIPT" "$PLAN6" "$STATE6" "$SPECS6" "$ROUND6" 0 \
  > /dev/null 2> "$TEST_OUT/delegate-skip/orch.stderr"
rc=$?
if [ $rc -eq 0 ]; then
  pass "AC-3.6: orchestrator exits 0 on delegate-skip fixture"
else
  fail "AC-3.6: orchestrator rc=$rc — stderr: $(cat "$TEST_OUT/delegate-skip/orch.stderr")"
fi

# Delegate phase 2 has zero ### Tests subsections.
DEL_CNT="$(count_tests_in_phase "$PLAN6" 2)"
if [ "$DEL_CNT" = "0" ]; then
  pass "AC-3.6: delegate phase 2 has zero ### Tests subsections"
else
  fail "AC-3.6: delegate phase 2 has $DEL_CNT ### Tests subsections (expected 0)"
fi

# Non-delegate phases 1 and 3 each have one.
for pid in 1 3; do
  cnt="$(count_tests_in_phase "$PLAN6" "$pid")"
  if [ "$cnt" = "1" ]; then
    pass "AC-3.6: non-delegate phase $pid has exactly 1 ### Tests subsection"
  else
    fail "AC-3.6: non-delegate phase $pid has $cnt ### Tests subsections (expected 1)"
  fi
done

# Set-equality of delegate_phases (parsed-state) vs delegate_skipped_phases (drafter output).
PARSED_DEL="$(read_state_list "$STATE6" delegate_phases | LC_ALL=C sort)"
DRAFTED_DEL="$(read_state_list "$ROUND6" delegate_skipped_phases | LC_ALL=C sort)"
if [ "$PARSED_DEL" = "$DRAFTED_DEL" ]; then
  pass "AC-3.6: delegate_phases (parsed-state) == delegate_skipped_phases (drafter output) as sets"
else
  fail "AC-3.6: set inequality between delegate_phases and delegate_skipped_phases (parsed='$PARSED_DEL' drafted='$DRAFTED_DEL')"
fi

# Single-source-of-truth check: orchestrator did NOT consult plan body
# for delegate-classification (negative test). Mutate the plan to remove
# the `### Execution: delegate` line and confirm the orchestrator's
# delegate_skipped_phases list still tracks the parsed-state.
PLAN6_MUT="$(prepare_fixture "$P3/delegate-skip.md" delegate-skip-mutated)"
STATE6_MUT="$TEST_OUT/delegate-skip-mutated/parsed.md"
bash "$PARSE_SCRIPT" "$PLAN6_MUT" "$STATE6_MUT" 2>/dev/null
# Now strip the `### Execution: delegate` line from the plan AFTER parsing.
sed -i '/^### Execution: delegate/d' "$PLAN6_MUT"

# Specs file MUST include all 3 phases now (since delegate is no longer
# in the plan body — but parsed-state still says phase 2 is delegate, so
# orchestrator should still skip it).
SPECS6_MUT="$TEST_OUT/delegate-skip-mutated/specs.md"
cat > "$SPECS6_MUT" <<'EOF'
phase: 1
- [unit] [risk: AC-1.1] given x = 0, when normal() is called, expect output 0.
phase: 3
- [unit] [risk: AC-3.1] given x = 1, when normal_two() is called, expect output 1.
EOF
ROUND6_MUT="$TEST_OUT/delegate-skip-mutated/draft-round-0.md"
bash "$ORCH_SCRIPT" "$PLAN6_MUT" "$STATE6_MUT" "$SPECS6_MUT" "$ROUND6_MUT" 0 \
  > /dev/null 2> "$TEST_OUT/delegate-skip-mutated/orch.stderr"
rc=$?
if [ $rc -eq 0 ]; then
  pass "AC-3.6: orchestrator exits 0 even when plan body was mutated (single-source-of-truth)"
else
  fail "AC-3.6: orchestrator rc=$rc on plan-mutated single-source-of-truth case"
fi

DEL_CNT_MUT="$(count_tests_in_phase "$PLAN6_MUT" 2)"
if [ "$DEL_CNT_MUT" = "0" ]; then
  pass "AC-3.6: phase 2 STILL skipped when plan-body delegate marker was removed (parsed-state authoritative)"
else
  fail "AC-3.6: phase 2 not skipped after plan-body mutation; orchestrator re-derived from plan body (defect)"
fi

DRAFTED_DEL_MUT="$(read_state_list "$ROUND6_MUT" delegate_skipped_phases | LC_ALL=C sort)"
if [ "$DRAFTED_DEL_MUT" = "$PARSED_DEL" ]; then
  pass "AC-3.6: delegate_skipped_phases tracks parsed-state, not plan body (single-source-of-truth)"
else
  fail "AC-3.6: delegate_skipped_phases regressed to plan-body grep ('$DRAFTED_DEL_MUT' vs parsed '$PARSED_DEL')"
fi

# ==========================================================================
# Position-priority verification (WI 3.5).
# Build a fixture variant where the AC block is the third subsection so
# we can assert the ### Tests insertion lands immediately after the AC
# block (not after Work Items / Design & Constraints / Goal).
# ==========================================================================
echo ""
echo "=== Position priority (WI 3.5) ==="

# Use idempotency fixture (Goal -> Work Items -> Acceptance Criteria ->
# Dependencies). After insertion, ### Tests should land between the AC
# block body and the next ### Dependencies heading (not after Work Items).
POS_PLAN="$TEST_OUT/idempotency/plan.md"
# Verify the line directly above ### Dependencies of phase 1 is part of
# the inserted ### Tests body (i.e., Tests inserted between AC and Deps).
# We grep for the ordering: AC heading -> Tests heading -> Dependencies heading.
ORDER=$(awk '
  BEGIN { in_phase=0; in_code=0; cur_phase="" }
  /^```/ { in_code = 1 - in_code; next }
  in_code { next }
  /^## Phase 1 / { in_phase=1; next }
  in_phase && /^## / { exit }
  in_phase && /^### Acceptance Criteria/ { print "AC"; next }
  in_phase && /^### Tests/ { print "T"; next }
  in_phase && /^### Dependencies/ { print "D"; next }
' "$POS_PLAN" | tr '\n' ',')

if [ "$ORDER" = "AC,T,D," ]; then
  pass "Position priority: phase 1 sequence is AC -> Tests -> Dependencies (inserted after AC)"
else
  fail "Position priority: expected 'AC,T,D,' got '$ORDER'"
fi

# Phase variant where the only anchor is Work Items (no AC block).
# Use the n-minus-k fixture's Phase 3 (ac-less) as a control: the
# orchestrator must SKIP it (no ### Tests appended), per WI 3.5 ac-less
# rule. Already verified above. We additionally cover the priority-3
# fallback by adding a fixture variant.
NOAC_DIR="$TEST_OUT/no-ac-block"
mkdir -p "$NOAC_DIR"
cat > "$NOAC_DIR/plan.md" <<'EOF'
---
title: No-AC-Anchor Fixture
created: 2026-04-29
status: active
---

# Plan: No-AC-Anchor

## Overview

Phase 1 has Work Items and Design & Constraints but no AC block;
parser will mark it ac-less, so orchestrator MUST skip. This documents
the priority-1/2/3 fallback path: in real plans, phases without ACs
are skipped wholesale. Phase 2 is a normal phase (priority-1 anchor).

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — NoAC | ⬚ | | ac-less |
| 2 — Normal | ⬚ | | normal |

---

## Phase 1 — NoAC

### Goal

This phase has no AC block.

### Work Items

- [ ] 1.1 — placeholder.

### Design & Constraints

- one constraint.

### Dependencies

None.

---

## Phase 2 — Normal

### Goal

Normal phase.

### Work Items

- [ ] 2.1 — work.

### Acceptance Criteria

- [ ] criterion (assign AC-2.1).

### Dependencies

Phase 1.
EOF

NOAC_STATE="$NOAC_DIR/parsed.md"
bash "$PARSE_SCRIPT" "$NOAC_DIR/plan.md" "$NOAC_STATE" 2>/dev/null
NOAC_ACL="$(read_state_list "$NOAC_STATE" ac_less | LC_ALL=C sort | tr '\n' ',')"
if [ "$NOAC_ACL" = "1," ]; then
  pass "Position priority: ac-less phase classified into ac_less list (skipped wholesale)"
else
  fail "Position priority: expected ac_less = {1}, got '$NOAC_ACL'"
fi

NOAC_SPECS="$NOAC_DIR/specs.md"
cat > "$NOAC_SPECS" <<'EOF'
phase: 2
- [unit] [risk: AC-2.1] given input 0, when normal() is called, expect output 0.
EOF
NOAC_ROUND="$NOAC_DIR/round-0.md"
bash "$ORCH_SCRIPT" "$NOAC_DIR/plan.md" "$NOAC_STATE" "$NOAC_SPECS" "$NOAC_ROUND" 0 \
  > /dev/null 2>"$NOAC_DIR/orch.stderr"
rc=$?
if [ $rc -eq 0 ]; then
  pass "Position priority: orchestrator exits 0 (ac-less phase 1 skipped, phase 2 drafted)"
else
  fail "Position priority: orchestrator rc=$rc on no-ac-block fixture"
fi
PHASE1_TESTS="$(count_tests_in_phase "$NOAC_DIR/plan.md" 1)"
if [ "$PHASE1_TESTS" = "0" ]; then
  pass "Position priority: ac-less phase 1 received zero ### Tests (orchestrator-side skip)"
else
  fail "Position priority: ac-less phase 1 received $PHASE1_TESTS ### Tests (expected 0)"
fi

# ==========================================================================
# Drafter never writes test code (AC-3.3 corollary): SKILL.md prose says so.
# ==========================================================================
echo ""
echo "=== Drafter never writes test code framing ==="

if grep -F -q 'Drafter never writes test code' "$SKILL_MD"; then
  pass "SKILL.md prose contains 'Drafter never writes test code' framing"
else
  fail "SKILL.md prose missing 'Drafter never writes test code' framing"
fi
if grep -F -q 'Anti-pattern' "$SKILL_MD"; then
  pass "SKILL.md prose contains the anti-pattern list"
else
  fail "SKILL.md prose missing anti-pattern list"
fi

# ==========================================================================
# Tier-1 registration for both new scripts (parity with Phase 2).
# ==========================================================================
echo ""
echo "=== Tier-1 hash registration ==="

OWN_FILE="$REPO_ROOT/skills/update-zskills/references/script-ownership.md"
HASH_FILE="$REPO_ROOT/skills/update-zskills/references/tier1-shipped-hashes.txt"
STALE_FILE="$REPO_ROOT/skills/update-zskills/SKILL.md"

for script_name in append-tests-section.sh draft-orchestrator.sh; do
  if grep -E -q "\| \`$script_name\`[[:space:]]+\|[[:space:]]*1[[:space:]]*\|[[:space:]]+\`draft-tests\`" "$OWN_FILE"; then
    pass "$script_name registered as Tier 1 owned by draft-tests"
  else
    fail "$script_name NOT registered as Tier 1 / draft-tests"
  fi
  STALE_HIT=$(grep -c "^  $script_name$" "$STALE_FILE" || true)
  if [ "${STALE_HIT:-0}" -ge 1 ]; then
    pass "$script_name appears in update-zskills STALE_LIST"
  else
    fail "$script_name MISSING from update-zskills STALE_LIST"
  fi
  ACTUAL_HASH=$(git hash-object "$REPO_ROOT/skills/draft-tests/scripts/$script_name")
  if grep -F -q -x "$ACTUAL_HASH" "$HASH_FILE"; then
    pass "$script_name hash $ACTUAL_HASH present in tier1-shipped-hashes.txt"
  else
    fail "$script_name hash $ACTUAL_HASH MISSING from tier1-shipped-hashes.txt"
  fi
done

# ==========================================================================
# SKILL.md prose contains Phase 3 framing references.
# ==========================================================================
echo ""
echo "=== Phase 3 SKILL.md prose ==="

for needle in \
  'append-tests-section.sh' \
  'draft-orchestrator.sh' \
  'senior QE' \
  'one-line bullet' \
  'multi-line expansion' \
  'risk: AC-' \
  'position priority' \
  'idempotent' \
  'delegate_skipped_phases' \
  'single-source-of-truth' \
  'Anti-pattern' \
  'Drafter never writes test code'
do
  if grep -F -q -- "$needle" "$SKILL_MD"; then
    pass "SKILL.md mentions: $needle"
  else
    fail "SKILL.md missing: $needle"
  fi
done

# ==========================================================================
# Summary
# ==========================================================================
echo ""
echo "---"
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ $FAIL_COUNT -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (of %d)\033[0m\n' "$PASS_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (of %d)\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit 1
fi
