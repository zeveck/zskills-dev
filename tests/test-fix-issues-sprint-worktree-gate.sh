#!/usr/bin/env bash
# tests/test-fix-issues-sprint-worktree-gate.sh
#
# Issue #325 schema test — asserts that:
#   1. `/fix-issues` SKILL.md has an ensure-worktree.sh preamble in
#      sprint mode (in addition to the pre-existing sync-mode preamble).
#   2. `/fix-report` SKILL.md has an ensure-worktree.sh preamble at
#      entry (it had none before #325).
#   3. Both preambles use the canonical `bash "$HELPER" \` invocation
#      pattern checked by tests/test-skill-conformance.sh's
#      "ensure-worktree caller contract" scan, so they automatically
#      pass the --pipeline-id contract test.
#
# WHY a schema test (not a full end-to-end fixture): exercising the
# sprint-mode preamble end-to-end requires recursively dispatching
# `/fix-issues` against a fake GitHub state — far too heavy for a unit
# test. The schema assertion catches the regression class the issue
# describes (Phase 5 SPRINT_REPORT.md write happens BEFORE a worktree
# is created) by pinning the preamble block to a location ABOVE Phase
# 5's `## Phase 5 — Write Sprint Report` heading in fix-issues, and at
# entry (above `## Step 1`) in fix-report.
#
# Sister to tests/canary-ensure-worktree.sh, which tests the helper
# script itself; this test pins the per-skill ADOPTION.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

FI_SKILL="$REPO_ROOT/skills/fix-issues/SKILL.md"
FR_SKILL="$REPO_ROOT/skills/fix-report/SKILL.md"

# ─────────────────────────────────────────────────────────────────
# Assertion 1: fix-issues has at least TWO `bash "$HELPER"` calls
# (sync + sprint). The conformance test only checks presence; we
# pin the count so regressing the sprint preamble fails loudly.
# ─────────────────────────────────────────────────────────────────
echo "=== fix-issues sprint preamble (issue #325) ==="

HELPER_COUNT=$(grep -c 'bash "\$HELPER"' "$FI_SKILL" 2>/dev/null || echo 0)
if [ "$HELPER_COUNT" -ge 2 ]; then
  pass "fix-issues has $HELPER_COUNT ensure-worktree.sh dispatches (>=2: sync + sprint)"
else
  fail "fix-issues has only $HELPER_COUNT ensure-worktree.sh dispatch(es); expected >=2 (sync + sprint preamble)"
fi

# ─────────────────────────────────────────────────────────────────
# Assertion 2: the sprint preamble appears BEFORE `## Phase 5`.
# Otherwise the gate runs too late and Phase 5's SPRINT_REPORT.md
# write lands on main — the regression #325 closes.
# ─────────────────────────────────────────────────────────────────
PHASE5_LINE=$(grep -n '^## Phase 5' "$FI_SKILL" | head -1 | cut -d: -f1)
SPRINT_GATE_LINE=$(grep -n '^### Sprint worktree gate' "$FI_SKILL" | head -1 | cut -d: -f1)
if [ -z "$PHASE5_LINE" ]; then
  fail "fix-issues: '## Phase 5' heading not found (skill structure changed?)"
elif [ -z "$SPRINT_GATE_LINE" ]; then
  fail "fix-issues: '### Sprint worktree gate' heading not found (preamble missing or renamed)"
elif [ "$SPRINT_GATE_LINE" -ge "$PHASE5_LINE" ]; then
  fail "fix-issues: sprint worktree gate at line $SPRINT_GATE_LINE is AFTER '## Phase 5' at line $PHASE5_LINE (Phase 5 will dirty main)"
else
  pass "fix-issues: sprint worktree gate (line $SPRINT_GATE_LINE) precedes Phase 5 (line $PHASE5_LINE)"
fi

# ─────────────────────────────────────────────────────────────────
# Assertion 3: sprint preamble passes --pipeline-id (sanity — the
# conformance caller-contract scan already checks this, but pin
# here so a future refactor that splits the prefix breaks one test
# instead of silently weakening the contract).
# ─────────────────────────────────────────────────────────────────
if [ -n "$SPRINT_GATE_LINE" ]; then
  # Look at the next 25 lines after the heading for the preamble body.
  slice=$(sed -n "${SPRINT_GATE_LINE},$((SPRINT_GATE_LINE + 25))p" "$FI_SKILL")
  if echo "$slice" | grep -q -- '--prefix fix-issues' && echo "$slice" | grep -q -- '--pipeline-id'; then
    pass "fix-issues sprint preamble passes --prefix fix-issues + --pipeline-id"
  else
    fail "fix-issues sprint preamble missing --prefix fix-issues or --pipeline-id"
  fi
fi

# ─────────────────────────────────────────────────────────────────
# Assertion 4: fix-report adopts the preamble (issue #325 bundled
# fix — same hole in finalize step). The preamble appears BEFORE
# `## Step 1` so all file writes (Steps 2, 5, 7, 8) land in the
# worktree under main_protected: true.
# ─────────────────────────────────────────────────────────────────
echo ""
echo "=== fix-report worktree gate (issue #325) ==="

FR_HELPER_COUNT=$(grep -c 'bash "\$HELPER"' "$FR_SKILL" 2>/dev/null || echo 0)
if [ "$FR_HELPER_COUNT" -ge 1 ]; then
  pass "fix-report has $FR_HELPER_COUNT ensure-worktree.sh dispatch (>=1)"
else
  fail "fix-report has $FR_HELPER_COUNT ensure-worktree.sh dispatch; expected >=1 (entry preamble)"
fi

FR_STEP1_LINE=$(grep -n '^## Step 1' "$FR_SKILL" | head -1 | cut -d: -f1)
FR_GATE_LINE=$(grep -n '^## Worktree gate' "$FR_SKILL" | head -1 | cut -d: -f1)
if [ -z "$FR_STEP1_LINE" ]; then
  fail "fix-report: '## Step 1' heading not found (skill structure changed?)"
elif [ -z "$FR_GATE_LINE" ]; then
  fail "fix-report: '## Worktree gate' heading not found (preamble missing or renamed)"
elif [ "$FR_GATE_LINE" -ge "$FR_STEP1_LINE" ]; then
  fail "fix-report: worktree gate at line $FR_GATE_LINE is AFTER '## Step 1' at line $FR_STEP1_LINE"
else
  pass "fix-report: worktree gate (line $FR_GATE_LINE) precedes Step 1 (line $FR_STEP1_LINE)"
fi

if [ -n "$FR_GATE_LINE" ]; then
  slice=$(sed -n "${FR_GATE_LINE},$((FR_GATE_LINE + 30))p" "$FR_SKILL")
  if echo "$slice" | grep -q -- '--prefix fix-report' && echo "$slice" | grep -q -- '--pipeline-id'; then
    pass "fix-report worktree gate passes --prefix fix-report + --pipeline-id"
  else
    fail "fix-report worktree gate missing --prefix fix-report or --pipeline-id"
  fi
fi

# ─────────────────────────────────────────────────────────────────
# Assertion 5: sprint-level SPRINT_REPORT.md /land-pr dispatch
# exists AFTER per-issue landing. Without it, the worktree-resident
# SPRINT_REPORT.md commit never ships.
# ─────────────────────────────────────────────────────────────────
SPRINT_LAND_LINE=$(grep -n '^### Sprint-level SPRINT_REPORT.md landing' "$FI_SKILL" | head -1 | cut -d: -f1)
POST_LAND_LINE=$(grep -n '^### Post-land tracking' "$FI_SKILL" | head -1 | cut -d: -f1)
if [ -z "$SPRINT_LAND_LINE" ]; then
  fail "fix-issues: '### Sprint-level SPRINT_REPORT.md landing' subsection missing (Phase 6 cannot ship the report)"
elif [ -z "$POST_LAND_LINE" ]; then
  fail "fix-issues: '### Post-land tracking' subsection missing (Phase 6 cleanup malformed)"
elif [ "$SPRINT_LAND_LINE" -ge "$POST_LAND_LINE" ]; then
  fail "fix-issues: sprint-level land subsection (line $SPRINT_LAND_LINE) must precede Post-land tracking (line $POST_LAND_LINE)"
else
  pass "fix-issues: sprint-level /land-pr dispatch (line $SPRINT_LAND_LINE) precedes Post-land tracking (line $POST_LAND_LINE)"
fi

# ─────────────────────────────────────────────────────────────────
# Source/mirror parity (general invariant; pinned here so a broken
# mirror surfaces in THIS test too, not only the conformance test).
# ─────────────────────────────────────────────────────────────────
echo ""
echo "=== source/mirror parity ==="
for s in fix-issues fix-report; do
  if diff -q "$REPO_ROOT/skills/$s/SKILL.md" "$REPO_ROOT/.claude/skills/$s/SKILL.md" >/dev/null 2>&1; then
    pass "skills/$s/SKILL.md ≡ .claude/skills/$s/SKILL.md"
  else
    fail "skills/$s/SKILL.md ≠ .claude/skills/$s/SKILL.md (mirror drift)"
  fi
done

echo ""
echo "---"
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
