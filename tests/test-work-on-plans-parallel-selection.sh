#!/bin/bash
# test-work-on-plans-parallel-selection.sh — AC2b.2.
#
# SCOPE (DA2.7 — honest framing): This test asserts the STEADY-STATE
# closure of the selection-aware filter. Specifically:
#   * Invocation A has acquired a plan-foo claim and the claim.json
#     exists on disk.
#   * Invocation B runs Step 4's filter against plans.ready=[foo]
#     AFTER that claim landed.
#   * The filter drops `foo` from B's dispatch list.
#
# This test does NOT assert structural closure of the FRESH-START race
# (two simultaneous /work-on-plans invocations both observing an empty
# claims dir before either acquires). Per D4 / Overview / DA2.7, that
# residual window is bounded by /run-plan Phase 1's atomic-mkdir acquire
# (one returns exit 10) — NOT by this filter. The filter is a steady-
# state optimisation that prevents redundant /run-plan dispatch when a
# claim is already on disk; both invocations passing the filter on a
# truly empty claims dir is correct behaviour for THIS filter.
#
# Wiring assertion: the test also confirms the work-on-plans SKILL.md
# Step 4 references the filter script so the wiring stays live.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FILTER="$REPO_ROOT/skills/work-on-plans/scripts/filter-in-flight-plan-claims.sh"
CLAIM_SH="$REPO_ROOT/skills/run-plan/scripts/claim-plan.sh"
SKILL_MD="$REPO_ROOT/skills/work-on-plans/SKILL.md"
SKILL_DIR="$REPO_ROOT/skills/work-on-plans"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SCRATCH="/tmp/test-work-on-plans-parallel-selection-$$"
cleanup() {
  if [ -n "${TEST_KEEP_SCRATCH:-}" ]; then return; fi
  [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
}
trap cleanup EXIT INT TERM
mkdir -p "$SCRATCH"

echo "=== work-on-plans parallel selection — STEADY-STATE only (AC2b.2 / DA2.7) ==="

# Fixture: real git repo so MAIN_ROOT resolves.
FIXTURE="$SCRATCH/fixture"
mkdir -p "$FIXTURE"
(
  cd "$FIXTURE"
  git init -q
  git config user.email "t@t"
  git config user.name "t"
  git commit --allow-empty -q -m "init"
) || { fail "fixture init" "git init failed"; echo "Results: $PASS_COUNT passed, $((FAIL_COUNT + 1)) failed"; exit 1; }

# Phase A: Invocation A acquires plan-foo claim (synthesising the
# steady-state precondition).
(
  cd "$FIXTURE"
  bash "$CLAIM_SH" acquire foo --pipeline-id "run-plan.foo.A"
) >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then
  fail "Invocation A acquire" "exit $rc"
  echo "Results: $PASS_COUNT passed, $((FAIL_COUNT + 1)) failed"
  exit 1
fi
pass "Invocation A acquired plan-foo claim"

# Phase B: Invocation B runs the filter against plans.ready=[foo].
# Simulate Step 4 directly (the test focuses on the filter behaviour
# the SKILL.md prose invokes, not on dispatching /run-plan itself).
INPUT=$'foo'
STDOUT_FILE="$SCRATCH/B.stdout"
STDERR_FILE="$SCRATCH/B.stderr"
(
  cd "$FIXTURE"
  printf '%s\n' "$INPUT" | bash "$FILTER"
) >"$STDOUT_FILE" 2>"$STDERR_FILE"
rc=$?

if [ "$rc" -eq 0 ]; then
  pass "Invocation B filter exits 0"
else
  fail "Invocation B filter exits 0" "got rc=$rc"
fi

# Core steady-state assertion: B's filtered output is empty (foo dropped).
if [ ! -s "$STDOUT_FILE" ]; then
  pass "Invocation B dispatch list is empty (foo filtered after A's claim landed)"
else
  fail "Invocation B dispatch list is empty" "stdout was: $(cat "$STDOUT_FILE")"
fi

# Stderr report.
if grep -qE 'Skipped 1 plan\(s\) currently in-flight: foo' "$STDERR_FILE"; then
  pass "Invocation B stderr reports the skipped foo"
else
  fail "Invocation B stderr Skipped-N" "stderr was: $(cat "$STDERR_FILE")"
fi

# Skill dir wiring: Step 4 invokes the filter script.
# The reference may be in SKILL.md or modes/execute.md.
if grep -rqF 'filter-in-flight-plan-claims.sh' "$SKILL_DIR"; then
  pass "Skill dir Step 4 references filter-in-flight-plan-claims.sh"
else
  fail "SKILL.md wiring" "filter script not referenced in $SKILL_DIR"
fi

# Honest-framing self-check: this test's NAME + its leading comment must
# document the STEADY-STATE scope explicitly (DA2.7). Grep for the
# anchor phrase so a future "simplification" cannot silently drop it.
if grep -qF 'STEADY-STATE' "$0"; then
  pass "test file documents STEADY-STATE scope (DA2.7 honesty anchor)"
else
  fail "STEADY-STATE scope documentation" "anchor missing in test file"
fi

echo ""
echo "---"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
[ "$FAIL_COUNT" -eq 0 ]
