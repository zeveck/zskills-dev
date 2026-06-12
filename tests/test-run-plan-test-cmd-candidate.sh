#!/bin/bash
# tests/test-run-plan-test-cmd-candidate.sh — #1164.
#
# Behavioral regression for the /run-plan FULL_TEST_CMD three-case
# resolution fence in skills/run-plan/SKILL.md. The Case-2 refusal ("test
# infra detected but testing.full_cmd is empty") previously dead-ended an
# overnight /run-plan with no concrete next step. The fix NAMES a detected
# candidate command in the refusal so the user can set testing.full_cmd.
#
# This test EXTRACTS the resolution fence from the SKILL.md and RUNS it
# against fixture project roots, asserting:
#   - Case 1 (config set): TEST_MODE=config, no refusal.
#   - Case 2 (infra, no cmd): exit 1, refusal NAMES a concrete candidate.
#   - Case 3 (no infra): TEST_MODE=skipped, exit 0, no refusal.
#   - Candidate selection: package.json "test" -> "npm test";
#     tests/run-all.sh -> "bash tests/run-all.sh"; pytest.ini -> "pytest".
#
# The fence is extracted between two stable landmarks so a SKILL.md edit
# that drops the candidate naming makes this test fail loudly.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_MD="$REPO_ROOT/skills/run-plan/SKILL.md"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SCRATCH_ROOT="/tmp/test-run-plan-test-cmd-candidate-$$"
cleanup() {
  [ -n "${TEST_KEEP_SCRATCH:-}" ] && { echo "TEST_KEEP_SCRATCH set — leaving $SCRATCH_ROOT" >&2; return; }
  [ -d "$SCRATCH_ROOT" ] && rm -rf "$SCRATCH_ROOT"
}
trap cleanup EXIT INT TERM
mkdir -p "$SCRATCH_ROOT"

[ -f "$SKILL_MD" ] || { echo "FATAL: SKILL.md not found at $SKILL_MD" >&2; exit 1; }

# ───────────────────────────────────────────────────────────────────────
# Extract the resolution fence. Landmarks:
#   START: the line `FULL_TEST_CMD=""`
#   END:   the closing ``` that terminates that bash fence.
# We capture from the first `FULL_TEST_CMD=""` line through the next bare
# ``` fence-close. This is the body of the three-case decision tree.
# ───────────────────────────────────────────────────────────────────────
FENCE="$SCRATCH_ROOT/fence.sh"
awk '
  /^FULL_TEST_CMD=""$/ { capture=1 }
  capture && /^```[[:space:]]*$/ { exit }
  capture { print }
' "$SKILL_MD" > "$FENCE"

if ! grep -q 'TEST_INFRA_DETECTED' "$FENCE"; then
  fail "fence extraction" "extracted fence missing TEST_INFRA_DETECTED — landmark drift?"
  echo ""
  printf '\033[31mResults: %d passed, %d failed\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT"
  exit 1
fi
pass "extracted resolution fence from SKILL.md"

# Run the fence against a given PROJECT_ROOT. Captures combined stdout+stderr
# to $OUT_FILE and the exit code to $RC. The fence reads PROJECT_ROOT and
# emits TEST_MODE / refusal text; we echo TEST_MODE at the end for Case 1/3.
run_fence() {
  local proj="$1"
  RC=0
  OUT=$(
    PROJECT_ROOT="$proj" CLAUDE_PROJECT_DIR="$proj" bash -c "
      $(cat "$FENCE")
      echo \"TEST_MODE_RESULT=\${TEST_MODE:-<unset>}\"
    " 2>&1
  ) || RC=$?
}

# ───────────────────────────────────────────────────────────────────────
# Case 1: config sets testing.full_cmd -> TEST_MODE=config, rc 0.
# ───────────────────────────────────────────────────────────────────────
P1="$SCRATCH_ROOT/case1"
mkdir -p "$P1/.claude"
cat > "$P1/.claude/zskills-config.json" <<'JSON'
{ "testing": { "full_cmd": "bash tests/run-all.sh" } }
JSON
run_fence "$P1"
if [ "$RC" -eq 0 ] && echo "$OUT" | grep -q 'TEST_MODE_RESULT=config'; then
  pass "Case 1: config set -> TEST_MODE=config, rc 0"
else
  fail "Case 1" "rc=$RC out=<$OUT>"
fi

# ───────────────────────────────────────────────────────────────────────
# Case 3: no infra, no config -> TEST_MODE=skipped, rc 0.
# ───────────────────────────────────────────────────────────────────────
P3="$SCRATCH_ROOT/case3"
mkdir -p "$P3"
run_fence "$P3"
if [ "$RC" -eq 0 ] && echo "$OUT" | grep -q 'TEST_MODE_RESULT=skipped'; then
  pass "Case 3: no infra -> TEST_MODE=skipped, rc 0"
else
  fail "Case 3" "rc=$RC out=<$OUT>"
fi

# ───────────────────────────────────────────────────────────────────────
# Case 2a: package.json with a "test" script -> rc 1, refusal NAMES
# "npm test".
# ───────────────────────────────────────────────────────────────────────
P2a="$SCRATCH_ROOT/case2a"
mkdir -p "$P2a"
cat > "$P2a/package.json" <<'JSON'
{ "scripts": { "test": "vitest run" } }
JSON
run_fence "$P2a"
if [ "$RC" -eq 1 ] \
   && echo "$OUT" | grep -q 'test infra detected but testing.full_cmd is empty' \
   && echo "$OUT" | grep -q 'a likely command is: npm test'; then
  pass "Case 2a: package.json test script -> rc 1, refusal names 'npm test' (#1164)"
else
  fail "Case 2a candidate naming" "rc=$RC out=<$OUT>"
fi

# ───────────────────────────────────────────────────────────────────────
# Case 2b: tests/run-all.sh -> rc 1, refusal NAMES "bash tests/run-all.sh".
# ───────────────────────────────────────────────────────────────────────
P2b="$SCRATCH_ROOT/case2b"
mkdir -p "$P2b/tests"
echo '#!/bin/bash' > "$P2b/tests/run-all.sh"
run_fence "$P2b"
if [ "$RC" -eq 1 ] \
   && echo "$OUT" | grep -q 'a likely command is: bash tests/run-all.sh'; then
  pass "Case 2b: tests/run-all.sh -> refusal names 'bash tests/run-all.sh' (#1164)"
else
  fail "Case 2b candidate naming" "rc=$RC out=<$OUT>"
fi

# ───────────────────────────────────────────────────────────────────────
# Case 2c: pytest.ini -> rc 1, refusal NAMES "pytest".
# ───────────────────────────────────────────────────────────────────────
P2c="$SCRATCH_ROOT/case2c"
mkdir -p "$P2c"
echo '[pytest]' > "$P2c/pytest.ini"
run_fence "$P2c"
if [ "$RC" -eq 1 ] && echo "$OUT" | grep -q 'a likely command is: pytest'; then
  pass "Case 2c: pytest.ini -> refusal names 'pytest' (#1164)"
else
  fail "Case 2c candidate naming" "rc=$RC out=<$OUT>"
fi

# ───────────────────────────────────────────────────────────────────────
# Case 2d: the refusal also points at testing.full_cmd in the config and
# names the candidate inside the JSON example (concrete, copy-pasteable).
# ───────────────────────────────────────────────────────────────────────
if echo "$OUT" | grep -q '"full_cmd": "pytest"' \
   && echo "$OUT" | grep -q 'testing.full_cmd'; then
  pass "Case 2: refusal shows a copy-pasteable testing.full_cmd JSON example (#1164)"
else
  fail "Case 2 JSON example" "out=<$OUT>"
fi

# ───────────────────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────────────────
echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (%d total)\033[0m\n' "$PASS_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (%d total)\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit 1
fi
