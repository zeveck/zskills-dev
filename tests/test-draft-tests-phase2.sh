#!/bin/bash
# Tests for skills/draft-tests/ -- Phase 2 (language detection,
# test-file discovery, calibration signal, no-test-setup recommendation,
# byte-preserving Prerequisites insertion, three-case test-cmd resolution).
#
# Phase 2 spec: plans/DRAFT_TESTS_SKILL_PLAN.md, work items 2.1-2.7,
# acceptance criteria AC-2.1 through AC-2.10.
#
# Run from repo root: bash tests/test-draft-tests-phase2.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_DIR="$REPO_ROOT/skills/draft-tests"
SKILL_MD="$SKILL_DIR/SKILL.md"
DETECT_SCRIPT="$SKILL_DIR/scripts/detect-language.sh"
PREREQ_SCRIPT="$SKILL_DIR/scripts/insert-prerequisites.sh"
PARSE_SCRIPT="$SKILL_DIR/scripts/parse-plan.sh"
FIXTURES="$REPO_ROOT/tests/fixtures/draft-tests"
P2="$FIXTURES/p2"

TEST_OUT="/tmp/zskills-tests/$(basename "$REPO_ROOT")/draft-tests-p2"
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

# Read a scalar key from the detection-state file ("key: value" form).
read_state_scalar() {
  local state_file="$1" key="$2"
  awk -v k="$key:" '$1 == k { sub(/^[^:]+:[[:space:]]*/, ""); print; exit }' "$state_file"
}

# Read the recommendation_text block (between begin/end markers).
read_recommendation_text() {
  local state_file="$1"
  awk '
    /^recommendation_text_begin$/ { active=1; next }
    /^recommendation_text_end$/ { active=0; next }
    active { print }
  ' "$state_file"
}

# ==========================================================================
# AC-2.1 -- JS-only project recommends vitest (or jest if mentioned).
# ==========================================================================
echo ""
echo "=== AC-2.1 -- JS-only language detection ==="

JS_STATE="$TEST_OUT/js-only-state.md"
bash "$DETECT_SCRIPT" "$P2/js-only" "$JS_STATE" 2>"$TEST_OUT/js-only-stderr.log"
rc=$?
if [ $rc -eq 0 ]; then
  pass "AC-2.1: detect-language.sh exits 0 on js-only fixture"
else
  fail "AC-2.1: detect-language.sh exited rc=$rc on js-only fixture"
fi

JS_LANGS="$(read_state_list "$JS_STATE" languages)"
if [ "$JS_LANGS" = "javascript" ]; then
  pass "AC-2.1: languages = {javascript}"
else
  fail "AC-2.1: languages mismatch (got: '$JS_LANGS')"
fi

JS_RECS="$(read_state_list "$JS_STATE" recommendations)"
if [ "$JS_RECS" = "javascript: vitest" ]; then
  pass "AC-2.1: recommendation = vitest (no jest reference)"
else
  fail "AC-2.1: recommendations mismatch (got: '$JS_RECS')"
fi

# Now mutate the fixture to mention jest and re-run -> recommendation = jest.
JS_JEST_DIR="$TEST_OUT/js-jest"
mkdir -p "$JS_JEST_DIR"
cat > "$JS_JEST_DIR/package.json" <<'EOF'
{
  "name": "js-jest-fixture",
  "version": "0.0.1",
  "devDependencies": { "jest": "^29.0.0" }
}
EOF
JS_JEST_STATE="$TEST_OUT/js-jest-state.md"
bash "$DETECT_SCRIPT" "$JS_JEST_DIR" "$JS_JEST_STATE" 2>/dev/null
JS_JEST_RECS="$(read_state_list "$JS_JEST_STATE" recommendations)"
if [ "$JS_JEST_RECS" = "javascript: jest" ]; then
  pass "AC-2.1: recommendation = jest when package.json mentions jest"
else
  fail "AC-2.1: jest recommendation mismatch (got: '$JS_JEST_RECS')"
fi

# ==========================================================================
# AC-2.2 -- Python-only project recommends pytest.
# ==========================================================================
echo ""
echo "=== AC-2.2 -- Python language detection ==="

PY_STATE="$TEST_OUT/py-only-state.md"
bash "$DETECT_SCRIPT" "$P2/py-only" "$PY_STATE" 2>/dev/null
PY_LANGS="$(read_state_list "$PY_STATE" languages)"
PY_RECS="$(read_state_list "$PY_STATE" recommendations)"
if [ "$PY_LANGS" = "python" ]; then
  pass "AC-2.2: languages = {python}"
else
  fail "AC-2.2: languages mismatch (got: '$PY_LANGS')"
fi
if [ "$PY_RECS" = "python: pytest" ]; then
  pass "AC-2.2: recommendation = pytest"
else
  fail "AC-2.2: recommendation mismatch (got: '$PY_RECS')"
fi

# ==========================================================================
# AC-2.3 -- Polyglot project (go.mod + package.json) -> per-subtree
# recommendations.
# ==========================================================================
echo ""
echo "=== AC-2.3 -- Polyglot language detection ==="

POLY_STATE="$TEST_OUT/polyglot-state.md"
bash "$DETECT_SCRIPT" "$P2/polyglot-go-js" "$POLY_STATE" 2>/dev/null
POLY_LANGS="$(read_state_list "$POLY_STATE" languages | LC_ALL=C sort)"
EXPECTED_POLY="$(printf 'go\njavascript' | LC_ALL=C sort)"
if [ "$POLY_LANGS" = "$EXPECTED_POLY" ]; then
  pass "AC-2.3: polyglot languages = {go, javascript}"
else
  fail "AC-2.3: polyglot languages mismatch (got: '$POLY_LANGS')"
fi
POLY_RECS="$(read_state_list "$POLY_STATE" recommendations | LC_ALL=C sort)"
EXPECTED_POLY_RECS="$(printf 'go: go test\njavascript: vitest' | LC_ALL=C sort)"
if [ "$POLY_RECS" = "$EXPECTED_POLY_RECS" ]; then
  pass "AC-2.3: polyglot per-subtree recommendations (go: go test, javascript: vitest)"
else
  fail "AC-2.3: polyglot recommendations mismatch (got:
$POLY_RECS
expected:
$EXPECTED_POLY_RECS)"
fi

# AC-2.9 is partially covered here too: parsed/detection state records the
# test-file path list (none in this fixture, since it has no tests, but
# the `test_files:` key MUST be present in the format).
if grep -q '^test_files:$' "$POLY_STATE"; then
  pass "AC-2.9 (additive schema): test_files: key present in detection-state"
else
  fail "AC-2.9 (additive schema): test_files: key missing"
fi

# ==========================================================================
# AC-2.4 -- No recognized manifest -> drafter prompt contains the literal
# string "no configured test runner".
# ==========================================================================
echo ""
echo "=== AC-2.4 -- No-manifest fixture / no configured test runner ==="

NM_STATE="$TEST_OUT/no-manifest-state.md"
bash "$DETECT_SCRIPT" "$P2/no-manifest" "$NM_STATE" 2>/dev/null
NM_LANGS="$(read_state_list "$NM_STATE" languages)"
if [ -z "$NM_LANGS" ]; then
  pass "AC-2.4: languages = {} on no-manifest fixture"
else
  fail "AC-2.4: languages should be empty on no-manifest (got: '$NM_LANGS')"
fi
NM_REC_TEXT="$(read_recommendation_text "$NM_STATE")"
if printf '%s' "$NM_REC_TEXT" | grep -F -q 'no configured test runner'; then
  pass "AC-2.4: drafter-prompt input contains literal 'no configured test runner'"
else
  fail "AC-2.4: drafter-prompt input missing 'no configured test runner' literal"
  echo "        recommendation_text was:" >&2
  printf '%s\n' "$NM_REC_TEXT" >&2
fi

# Detection still proceeds (rc=0) and no fatal error is reported.
if bash "$DETECT_SCRIPT" "$P2/no-manifest" "$NM_STATE" 2>/dev/null; then
  pass "AC-2.4: detect-language.sh proceeds (rc=0) without recognized manifest"
else
  fail "AC-2.4: detect-language.sh aborted on no-manifest fixture"
fi

# ==========================================================================
# AC-2.5 -- Config has full_cmd/unit_cmd -> drafter prompt contains the
# value verbatim and detection is informational only.
# ==========================================================================
echo ""
echo "=== AC-2.5 -- Config-first verbatim test command ==="

CS_STATE="$TEST_OUT/config-set-state.md"
bash "$DETECT_SCRIPT" "$P2/config-set" "$CS_STATE" 2>/dev/null
CS_FULL="$(read_state_scalar "$CS_STATE" config_full_cmd)"
CS_UNIT="$(read_state_scalar "$CS_STATE" config_unit_cmd)"
CS_CASE="$(read_state_scalar "$CS_STATE" case)"
if [ "$CS_FULL" = "make test-everything" ]; then
  pass "AC-2.5: config_full_cmd = 'make test-everything' (verbatim)"
else
  fail "AC-2.5: config_full_cmd mismatch (got: '$CS_FULL')"
fi
if [ "$CS_UNIT" = "make test-unit" ]; then
  pass "AC-2.5: config_unit_cmd = 'make test-unit' (verbatim)"
else
  fail "AC-2.5: config_unit_cmd mismatch (got: '$CS_UNIT')"
fi
if [ "$CS_CASE" = "1" ]; then
  pass "AC-2.5: case = 1 (config-set; detection downgraded to informational)"
else
  fail "AC-2.5: case mismatch (got: '$CS_CASE'; expected 1)"
fi
# In case=1, no Prerequisites recommendation is emitted.
CS_REC_TEXT="$(read_recommendation_text "$CS_STATE")"
if [ -z "$CS_REC_TEXT" ]; then
  pass "AC-2.5: recommendation_text empty in case=1 (no Prerequisites recommendation)"
else
  fail "AC-2.5: recommendation_text non-empty in case=1 (got: '$CS_REC_TEXT')"
fi

# ==========================================================================
# AC-2.6 -- JS describe/it tests -> calibration signal names that
# convention; specs use compatible terminology.
# ==========================================================================
echo ""
echo "=== AC-2.6 -- JS describe/it calibration ==="

EX_STATE="$TEST_OUT/existing-js-tests-state.md"
bash "$DETECT_SCRIPT" "$P2/existing-js-tests" "$EX_STATE" 2>/dev/null
SIG_FILE="$(read_state_scalar "$EX_STATE" calibration_signal_file)"
if [ -n "$SIG_FILE" ] && [ -f "$SIG_FILE" ]; then
  pass "AC-2.6: calibration_signal_file produced and exists"
else
  fail "AC-2.6: calibration_signal_file missing or empty (got: '$SIG_FILE')"
fi
if grep -F -q 'naming_convention: describe/it' "$SIG_FILE"; then
  pass "AC-2.6: signal names describe/it convention"
else
  fail "AC-2.6: signal does not name describe/it convention"
  cat "$SIG_FILE" >&2 || true
fi
if grep -F -q 'fixture_style: present' "$SIG_FILE"; then
  pass "AC-2.6: signal records beforeEach fixture style"
else
  fail "AC-2.6: signal missing beforeEach fixture detection"
fi
if grep -F -q 'assertion_library: expect' "$SIG_FILE"; then
  pass "AC-2.6: signal records expect() assertion library"
else
  fail "AC-2.6: signal missing expect() detection"
fi

# ==========================================================================
# AC-2.7 -- Detection failure (malformed JSON manifest) is logged to
# stderr; produces "language undetectable"; skill run completes
# successfully with no recommendation.
# ==========================================================================
echo ""
echo "=== AC-2.7 -- Graceful fallback on malformed manifest ==="

MM_STATE="$TEST_OUT/malformed-state.md"
MM_STDERR="$TEST_OUT/malformed-stderr.log"
bash "$DETECT_SCRIPT" "$P2/malformed-manifest" "$MM_STATE" 2>"$MM_STDERR"
rc=$?
if [ $rc -eq 0 ]; then
  pass "AC-2.7: detect-language.sh exits 0 on malformed manifest (graceful fallback)"
else
  fail "AC-2.7: detect-language.sh exited rc=$rc on malformed manifest"
fi
MM_STATUS="$(read_state_scalar "$MM_STATE" detection_status)"
if [ "$MM_STATUS" = "undetectable" ]; then
  pass "AC-2.7: detection_status = undetectable on malformed manifest"
else
  fail "AC-2.7: detection_status mismatch (got: '$MM_STATUS')"
fi
if grep -q 'malformed package.json' "$MM_STDERR"; then
  pass "AC-2.7: failure logged to stderr"
else
  fail "AC-2.7: stderr log missing 'malformed package.json' message"
  cat "$MM_STDERR" >&2 || true
fi

# ==========================================================================
# AC-2.8 -- ≥4 test files per language -> calibration signal reads at
# most 3 files per language and the structured summary is ≤ 20 lines per
# language.
# ==========================================================================
echo ""
echo "=== AC-2.8 -- Calibration signal bounds ==="

EX_TEST_FILES="$(read_state_list "$EX_STATE" test_files | grep -c '^javascript:' || true)"
if [ "$EX_TEST_FILES" -ge 4 ]; then
  pass "AC-2.8: existing-js-tests fixture has >=4 candidate JS files (got $EX_TEST_FILES)"
else
  fail "AC-2.8: existing-js-tests fixture has <4 candidate JS files (got $EX_TEST_FILES)"
fi

# Count javascript section lines in the signal file (between `## javascript`
# and the next `## ` header or EOF).
SIG_JS_LINES="$(awk '
  /^## javascript$/ { active=1; count=0; next }
  active && /^## / { exit }
  active { count++ }
  END { print count }
' "$SIG_FILE")"
if [ -z "$SIG_JS_LINES" ]; then SIG_JS_LINES=0; fi
if [ "$SIG_JS_LINES" -le 20 ]; then
  pass "AC-2.8: javascript signal section <= 20 lines (got $SIG_JS_LINES)"
else
  fail "AC-2.8: javascript signal section exceeds 20 lines (got $SIG_JS_LINES)"
fi

# Confirm the signal references at most 3 representative files (the
# imports_excerpt is from a single representative file -- the signal does
# not raw-include test-file contents). We assert the per-file content
# blocks number <= 3 by checking that `representative_file:` appears
# exactly once per language section.
SIG_REPS_JS=$(awk '
  /^## javascript$/ { in_js=1; next }
  in_js && /^## / { in_js=0 }
  in_js && /^representative_file:/ { count++ }
  END { print count+0 }
' "$SIG_FILE")
if [ "$SIG_REPS_JS" = "1" ]; then
  pass "AC-2.8: exactly one representative_file recorded for javascript (top-3 reduced to single representative)"
else
  fail "AC-2.8: representative_file count for javascript = $SIG_REPS_JS (expected 1)"
fi

# Negative form: the signal file MUST NOT contain raw bodies of any test
# file (no `it('handles a basic case'` substring etc.) -- only the
# imports_excerpt, which is by spec the top-10 lines of the rep file.
# Spot-check: the rep file's beforeEach/it body lines should NOT all be
# pasted into the signal.
SIG_BODY_LINES=$(grep -c "expect.*toBe(" "$SIG_FILE" || true)
if [ "${SIG_BODY_LINES:-0}" -le 1 ]; then
  pass "AC-2.8: signal does not paste raw test-body content (expect/toBe count <=1; got $SIG_BODY_LINES)"
else
  fail "AC-2.8: signal pastes raw test bodies (expect/toBe count = $SIG_BODY_LINES)"
fi

# ==========================================================================
# AC-2.9 -- Detection-state file records the full test-file path list
# (not contents) for each detected language.
# ==========================================================================
echo ""
echo "=== AC-2.9 -- Test-file path list persisted ==="

EX_TF="$(read_state_list "$EX_STATE" test_files | grep '^javascript:' | sort)"
N_TF="$(printf '%s\n' "$EX_TF" | grep -c .)"
if [ "$N_TF" -ge 4 ]; then
  pass "AC-2.9: detection-state lists all >=4 JS test files (got $N_TF)"
else
  fail "AC-2.9: detection-state lists $N_TF JS test files; expected >=4"
fi
# Each entry is `<lang>:<absolute-path>`; the path must point at an
# existing file, NOT contain test-file contents.
EX_FAIL=0
while IFS= read -r entry; do
  [ -z "$entry" ] && continue
  path="${entry#javascript:}"
  if [ ! -f "$path" ]; then
    EX_FAIL=1
    fail "AC-2.9: test-file path '$path' does not exist"
    break
  fi
  if [ "$(wc -l < "$path")" -gt 1000 ]; then
    EX_FAIL=1
    fail "AC-2.9: test-file path entry suspiciously long; not a path"
    break
  fi
done <<< "$EX_TF"
if [ $EX_FAIL -eq 0 ]; then
  pass "AC-2.9: every test-file entry is an existing path (not embedded contents)"
fi

# ==========================================================================
# AC-2.10 -- Insert ## Prerequisites between ## Overview and ## Progress
# Tracker; every other level-2 section MUST be byte-identical before/after,
# including non-canonical trailing sections.
# ==========================================================================
echo ""
echo "=== AC-2.10 -- Byte-preserving Prerequisites insertion ==="

PR_PLAN_ORIG="$TEST_OUT/prereq-trailing-orig.md"
PR_PLAN_WORK="$TEST_OUT/prereq-trailing-work.md"
cp "$P2/prereq-trailing/plan.md" "$PR_PLAN_ORIG"
cp "$P2/prereq-trailing/plan.md" "$PR_PLAN_WORK"

# Build a Prerequisites block (the block to insert).
PREREQ_BODY="$TEST_OUT/prereq-body.md"
cat > "$PREREQ_BODY" <<'EOF'
## Prerequisites

> **Test-runner recommendation:** this project has no configured test
> runner. Recommended: `pytest` (Python detected from pyproject.toml).
> Add `[tool.pytest.ini_options]` and a `tests/` directory before
> running the first test-bearing phase.
EOF

bash "$PREREQ_SCRIPT" "$PR_PLAN_WORK" "$PREREQ_BODY" 2>"$TEST_OUT/prereq-stderr.log"
rc=$?
if [ $rc -eq 0 ]; then
  pass "AC-2.10: insert-prerequisites.sh exits 0"
else
  fail "AC-2.10: insert-prerequisites.sh exited rc=$rc"
  cat "$TEST_OUT/prereq-stderr.log" >&2 || true
fi

# Confirm Prerequisites was inserted.
if grep -q '^## Prerequisites$' "$PR_PLAN_WORK"; then
  pass "AC-2.10: ## Prerequisites heading inserted"
else
  fail "AC-2.10: ## Prerequisites heading NOT inserted"
fi

# Confirm Prerequisites comes BEFORE Progress Tracker and AFTER Overview.
PREREQ_LN=$(grep -n '^## Prerequisites$' "$PR_PLAN_WORK" | head -1 | cut -d: -f1)
TRACKER_LN=$(grep -n '^## Progress Tracker' "$PR_PLAN_WORK" | head -1 | cut -d: -f1)
OVERVIEW_LN=$(grep -n '^## Overview$' "$PR_PLAN_WORK" | head -1 | cut -d: -f1)
if [ -n "$PREREQ_LN" ] && [ -n "$TRACKER_LN" ] && [ -n "$OVERVIEW_LN" ] \
   && [ "$OVERVIEW_LN" -lt "$PREREQ_LN" ] && [ "$PREREQ_LN" -lt "$TRACKER_LN" ]; then
  pass "AC-2.10: Prerequisites is between Overview and Progress Tracker"
else
  fail "AC-2.10: Prerequisites placement wrong (Overview=$OVERVIEW_LN Prereq=$PREREQ_LN Tracker=$TRACKER_LN)"
fi

# Byte-identical preservation: extract every level-2 section other than
# Prerequisites from BOTH original and mutated files; compare byte-by-byte.
extract_section() {
  local file="$1" heading="$2"
  awk -v want="$heading" '
    BEGIN { in_code=0; in_section=0 }
    /^```/ { in_code = 1 - in_code; if (in_section) print; next }
    in_code==0 && /^## / {
      if (in_section) exit
      if ($0 == want) in_section=1
    }
    in_section { print }
  ' "$file"
}

for HEAD in \
  '## Overview' \
  '## Progress Tracker' \
  '## Phase 1 — Stub' \
  '## Anti-Patterns -- Hard Constraints' \
  '## Non-Goals' \
  '## Risks and Mitigations'
do
  ORIG_SLICE="$TEST_OUT/orig-slice.txt"
  WORK_SLICE="$TEST_OUT/work-slice.txt"
  extract_section "$PR_PLAN_ORIG" "$HEAD" > "$ORIG_SLICE"
  extract_section "$PR_PLAN_WORK" "$HEAD" > "$WORK_SLICE"
  if [ ! -s "$ORIG_SLICE" ]; then
    fail "AC-2.10: original fixture missing section '$HEAD' (test setup error)"
    continue
  fi
  if cmp -s "$ORIG_SLICE" "$WORK_SLICE"; then
    pass "AC-2.10: section '$HEAD' byte-identical before/after Prerequisites insertion"
  else
    fail "AC-2.10: section '$HEAD' DIFFERS after Prerequisites insertion"
    diff "$ORIG_SLICE" "$WORK_SLICE" | head -20 >&2
  fi
done

# Idempotency: a second invocation replaces the existing block in place,
# does not duplicate.
bash "$PREREQ_SCRIPT" "$PR_PLAN_WORK" "$PREREQ_BODY" 2>/dev/null
COUNT=$(grep -c '^## Prerequisites$' "$PR_PLAN_WORK")
if [ "$COUNT" = "1" ]; then
  pass "AC-2.10: re-running insert-prerequisites.sh keeps exactly one Prerequisites block (replaces in place)"
else
  fail "AC-2.10: re-run produced $COUNT Prerequisites blocks (expected 1)"
fi

# ==========================================================================
# Skill ownership / hash file registration.
# ==========================================================================
echo ""
echo "=== Phase 2 helper-script registration ==="

OWN_FILE="$REPO_ROOT/skills/update-zskills/references/script-ownership.md"
for script_name in detect-language.sh insert-prerequisites.sh; do
  if grep -F -q "\`$script_name\`" "$OWN_FILE"; then
    pass "script-ownership.md registers $script_name"
  else
    fail "script-ownership.md does NOT register $script_name"
  fi
  if grep -E -q "\| \`$script_name\`[[:space:]]+\|[[:space:]]*1[[:space:]]*\|[[:space:]]+\`draft-tests\`" "$OWN_FILE"; then
    pass "$script_name registered as Tier 1 owned by draft-tests"
  else
    fail "$script_name NOT registered as Tier 1 / draft-tests"
  fi
  STALE_LIST_HIT=$(grep -c "^  $script_name$" "$REPO_ROOT/skills/update-zskills/SKILL.md" || true)
  if [ "${STALE_LIST_HIT:-0}" -ge 1 ]; then
    pass "$script_name appears in update-zskills STALE_LIST"
  else
    fail "$script_name MISSING from update-zskills STALE_LIST"
  fi
done

# ==========================================================================
# SKILL.md prose contains Phase 2 framing references.
# ==========================================================================
echo ""
echo "=== Phase 2 SKILL.md prose ==="

for needle in \
  'detect-language.sh' \
  'insert-prerequisites.sh' \
  'language detection' \
  'three-case' \
  'no configured test runner' \
  'calibration signal' \
  'config-first' \
  'Prerequisites'
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
