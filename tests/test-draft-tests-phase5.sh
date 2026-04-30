#!/bin/bash
# Tests for skills/draft-tests/ -- Phase 5 (backfill mechanics and
# re-invocation).
#
# Phase 5 spec: plans/DRAFT_TESTS_SKILL_PLAN.md, work items 5.1-5.8
# (plus 5.3b), acceptance criteria AC-5.1 through AC-5.11.
#
# All agent dispatches are stubbed (per AC-4.5 -- no live LLM calls).
# Live end-to-end runs are gated behind ZSKILLS_TEST_LLM=1 and are
# exercised from SKILL.md prose, not this script.
#
# Run from repo root: bash tests/test-draft-tests-phase5.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_DIR="$REPO_ROOT/skills/draft-tests"
SKILL_MD="$SKILL_DIR/SKILL.md"
SCRIPTS="$SKILL_DIR/scripts"

PARSE_SCRIPT="$SCRIPTS/parse-plan.sh"
GAP_SCRIPT="$SCRIPTS/gap-detect.sh"
BACKFILL_SCRIPT="$SCRIPTS/append-backfill-phase.sh"
TSR_SCRIPT="$SCRIPTS/insert-test-spec-revisions.sh"
FLIP_SCRIPT="$SCRIPTS/flip-frontmatter-status.sh"
REINV_SCRIPT="$SCRIPTS/re-invocation-detect.sh"
VERIFY_SCRIPT="$SCRIPTS/verify-completed-checksums.sh"
PRECHECK_SCRIPT="$SCRIPTS/coverage-floor-precheck.sh"

FIXTURES="$REPO_ROOT/tests/fixtures/draft-tests"
P5="$FIXTURES/p5"

TEST_OUT="/tmp/zskills-tests/$(basename "$REPO_ROOT")/draft-tests-p5"
mkdir -p "$TEST_OUT"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

prepare_dir() {
  local slug="$1"
  local dir="$TEST_OUT/$slug"
  # Defensive cleanup using find -delete (safer than rm -rf with a
  # variable expansion, per CLAUDE.md hook policy).
  if [ -d "$dir" ]; then
    find "$dir" -mindepth 1 -delete 2>/dev/null || true
  fi
  mkdir -p "$dir"
  printf '%s' "$dir"
}

# ==========================================================================
# Pre-flight: scripts exist and are executable.
# ==========================================================================
echo ""
echo "=== Pre-flight ==="

for s in "$GAP_SCRIPT" "$BACKFILL_SCRIPT" "$TSR_SCRIPT" "$FLIP_SCRIPT" \
         "$REINV_SCRIPT" "$VERIFY_SCRIPT"; do
  if [ -f "$s" ] && [ -x "$s" ]; then
    pass "Script exists and is executable: $(basename "$s")"
  else
    fail "Script missing or not executable: $s"
  fi
done

# ==========================================================================
# AC-5.1 -- COVERED ACs do not produce MISSING flag, no backfill appended.
# ==========================================================================
echo ""
echo "=== AC-5.1 -- COVERED ACs do not produce backfill ==="

DIR=$(prepare_dir "ac-5-1-covered")
cp "$P5/covered.md" "$DIR/plan.md"
cp "$DIR/plan.md" "$DIR/orig.md"
bash "$PARSE_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" 2>/dev/null >/dev/null

# Construct a fake test file containing the AC-1.1 reference.
cat > "$DIR/fake-test.sh" <<'EOF'
# This test exercises AC-1.1
echo "AC-1.1 covered"
EOF
cat > "$DIR/detect.md" <<EOF
case: 2
test_files:
  bash:$DIR/fake-test.sh
EOF

bash "$GAP_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" "$DIR/detect.md" "$DIR/gaps.md" 2>"$DIR/gap.stderr"
rc=$?
if [ $rc -eq 0 ]; then
  pass "AC-5.1: gap-detect exits 0 on COVERED fixture"
else
  fail "AC-5.1: gap-detect exited rc=$rc -- stderr: $(cat "$DIR/gap.stderr")"
fi

# missing_phases must be empty.
missing_count=$(awk '/^missing_phases:$/ {a=1; next} a && /^  / {c++; next} a && /^[^ ]/ {a=0} END {print c+0}' "$DIR/gaps.md")
if [ "$missing_count" -eq 0 ]; then
  pass "AC-5.1: COVERED fixture produces 0 MISSING phases"
else
  fail "AC-5.1: COVERED fixture produced $missing_count MISSING phases"
fi

# Run backfill -- should be a no-op.
bash "$BACKFILL_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" "$DIR/gaps.md" "$DIR/backfill.md" 2>"$DIR/bf.err"
bf_rc=$?
if [ $bf_rc -eq 0 ]; then
  pass "AC-5.1: backfill no-op exits 0 on empty MISSING list"
else
  fail "AC-5.1: backfill no-op exited rc=$bf_rc (set -u trap on empty array?) -- stderr: $(cat "$DIR/bf.err")"
fi
backfill_count=$(awk '/^backfill_phases:$/ {a=1; next} a && /^  / {c++; next} a && /^[^ ]/ {a=0} END {print c+0}' "$DIR/backfill.md")
if [ "$backfill_count" -eq 0 ]; then
  pass "AC-5.1: COVERED fixture produces 0 backfill phases"
else
  fail "AC-5.1: COVERED fixture produced $backfill_count backfill phases"
fi

# Plan file must be byte-identical to original.
if diff -q "$DIR/plan.md" "$DIR/orig.md" >/dev/null 2>&1; then
  pass "AC-5.1: plan file byte-identical post-backfill no-op"
else
  fail "AC-5.1: plan file MUTATED on COVERED fixture (no-op expected)"
fi

# ==========================================================================
# AC-5.2 -- UNKNOWN (prose-only) ACs do not auto-append backfill;
# advisory emitted instead. Regression guard against prose-token
# false-positive bug.
# ==========================================================================
echo ""
echo "=== AC-5.2 -- prose-only ACs fall to UNKNOWN, not MISSING ==="

DIR=$(prepare_dir "ac-5-2-unknown")
cp "$P5/unknown-prose.md" "$DIR/plan.md"
cp "$DIR/plan.md" "$DIR/orig.md"
bash "$PARSE_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" 2>/dev/null >/dev/null
bash "$GAP_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" /dev/null "$DIR/gaps.md" 2>/dev/null

# missing_phases must be empty.
missing_count=$(awk '/^missing_phases:$/ {a=1; next} a && /^  / {c++; next} a && /^[^ ]/ {a=0} END {print c+0}' "$DIR/gaps.md")
if [ "$missing_count" -eq 0 ]; then
  pass "AC-5.2: prose-only ACs produce 0 MISSING (regression guard)"
else
  fail "AC-5.2: prose-only ACs produced $missing_count MISSING (false-positive bug)"
fi

# unknown_phases must contain Phase 1.
if grep -E -q "^  1:" "$DIR/gaps.md"; then
  pass "AC-5.2: prose-only ACs produce UNKNOWN entry for Phase 1"
else
  fail "AC-5.2: prose-only ACs missing UNKNOWN entry for Phase 1"
fi

# Advisory line emitted (final-output user-review path).
if grep -F -q "advisory: coverage could not be confirmed" "$DIR/gaps.md"; then
  pass "AC-5.2: advisory line 'coverage could not be confirmed' emitted"
else
  fail "AC-5.2: advisory line MISSING from gaps file"
fi
if grep -F -q "human review recommended" "$DIR/gaps.md"; then
  pass "AC-5.2: advisory line names 'human review recommended'"
else
  fail "AC-5.2: advisory line missing 'human review recommended'"
fi

# Backfill must be no-op.
bash "$BACKFILL_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" "$DIR/gaps.md" "$DIR/backfill.md" 2>/dev/null
if diff -q "$DIR/plan.md" "$DIR/orig.md" >/dev/null 2>&1; then
  pass "AC-5.2: plan byte-identical post no-op (UNKNOWN does NOT trigger backfill)"
else
  fail "AC-5.2: plan MUTATED on UNKNOWN-only fixture (regression bug)"
fi

# ==========================================================================
# AC-5.3 -- MISSING AC (backticked identifier absent from `git grep -F`)
# triggers backfill phase append at the correct position.
# ==========================================================================
echo ""
echo "=== AC-5.3 -- MISSING -> backfill appended ==="

DIR=$(prepare_dir "ac-5-3-missing")
cp "$P5/missing-backticked.md" "$DIR/plan.md"
bash "$PARSE_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" 2>/dev/null >/dev/null
bash "$GAP_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" /dev/null "$DIR/gaps.md" 2>/dev/null

# Phase 1 should be MISSING.
if grep -E -q "^  1:AC-1\.1" "$DIR/gaps.md"; then
  pass "AC-5.3: Phase 1 with backticked-absent token classified MISSING"
else
  fail "AC-5.3: Phase 1 NOT classified MISSING -- gaps:"; cat "$DIR/gaps.md"
fi

bash "$BACKFILL_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" "$DIR/gaps.md" "$DIR/backfill.md" 2>/dev/null

# A new backfill phase heading was inserted.
if grep -E -q '^## Phase 2 -- Backfill tests for completed phases 1' "$DIR/plan.md"; then
  pass "AC-5.3: backfill heading '## Phase 2 -- Backfill tests for completed phases 1' present"
else
  fail "AC-5.3: backfill heading MISSING -- plan:"; cat "$DIR/plan.md"
fi

# Insert position: BEFORE `## Plan Quality`.
backfill_line=$(grep -n '^## Phase 2 -- Backfill' "$DIR/plan.md" | head -1 | cut -d: -f1)
quality_line=$(grep -n '^## Plan Quality' "$DIR/plan.md" | head -1 | cut -d: -f1)
if [ -n "$backfill_line" ] && [ -n "$quality_line" ] && [ "$backfill_line" -lt "$quality_line" ]; then
  pass "AC-5.3: backfill heading appears BEFORE '## Plan Quality'"
else
  fail "AC-5.3: backfill heading NOT before Plan Quality (backfill_line=$backfill_line plan_quality_line=$quality_line)"
fi

# Progress Tracker has a row for the new phase.
if grep -F -q "| 2 -- Backfill" "$DIR/plan.md"; then
  pass "AC-5.3: Progress Tracker has row for backfill phase 2"
else
  fail "AC-5.3: Progress Tracker MISSING row for backfill phase 2"
fi

# parsed-state's non_delegate_pending_phases includes the backfill phase.
if awk '/^non_delegate_pending_phases:$/ {a=1; next} a && /^  2$/ {found=1; exit} a && /^[^ ]/ {a=0} END {exit found?0:1}' "$DIR/parsed.md"; then
  pass "AC-5.3 / AC-5.10: parsed-state non_delegate_pending_phases includes backfill phase 2"
else
  fail "AC-5.3 / AC-5.10: parsed-state non_delegate_pending_phases MISSING backfill phase 2"
fi

# Backfill phase has a well-formed AC alias.
if grep -F -q "AC-2.1 — backfill spec for AC-1.1" "$DIR/plan.md"; then
  pass "AC-5.3 / AC-5.4 alias: backfill AC-2.1 aliases AC-1.1"
else
  fail "AC-5.3 / AC-5.4 alias: backfill AC-2.1 alias missing"
fi

# ==========================================================================
# AC-5.4 -- 4+ MISSING Completed phases produce multiple backfill phases
# (cluster size 1-3, never one mega-phase).
# ==========================================================================
echo ""
echo "=== AC-5.4 -- multiple backfill phases for 4+ MISSING ==="

DIR=$(prepare_dir "ac-5-4-many")
cp "$P5/many-missing.md" "$DIR/plan.md"
bash "$PARSE_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" 2>/dev/null >/dev/null
bash "$GAP_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" /dev/null "$DIR/gaps.md" 2>/dev/null
bash "$BACKFILL_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" "$DIR/gaps.md" "$DIR/backfill.md" 2>/dev/null

# Count `## Phase N -- Backfill` headings inserted.
backfill_count=$(grep -c -E '^## Phase [0-9]+ -- Backfill' "$DIR/plan.md")
if [ "$backfill_count" -ge 2 ]; then
  pass "AC-5.4: 4+ MISSING produces $backfill_count backfill phases (>= 2)"
else
  fail "AC-5.4: only $backfill_count backfill phase(s) -- expected >= 2"
fi

# Verify no single backfill phase clusters more than 3 sources. We
# inspect the heading line; sources are listed comma-separated.
mega_violation=0
while IFS= read -r line; do
  # Extract the comma-separated sources tail.
  sources="${line#*completed phases }"
  # Count commas + 1.
  nc=$(printf '%s' "$sources" | tr -cd ',' | wc -c)
  cluster_size=$((nc + 1))
  if [ "$cluster_size" -gt 3 ]; then
    mega_violation=1
    break
  fi
done < <(grep -E '^## Phase [0-9]+ -- Backfill' "$DIR/plan.md")
if [ "$mega_violation" -eq 0 ]; then
  pass "AC-5.4: every backfill phase clusters 1-3 source phases (no mega-phase)"
else
  fail "AC-5.4: at least one backfill phase clusters > 3 sources (mega-phase)"
fi

# Backfill-out file lists multiple backfill phases.
backfill_phase_count=$(awk '/^backfill_phases:$/ {a=1; next} a && /^  / {c++; next} a && /^[^ ]/ {a=0} END {print c+0}' "$DIR/backfill.md")
if [ "$backfill_phase_count" -ge 2 ]; then
  pass "AC-5.4: backfill-out file records >= 2 backfill_phases entries"
else
  fail "AC-5.4: backfill-out file records only $backfill_phase_count entry"
fi

# ==========================================================================
# AC-5.5 -- re-invocation idempotency: plan with `### Tests` is detected
# as re-invocation; the orchestrator routes to refinement.
# ==========================================================================
echo ""
echo "=== AC-5.5 -- re-invocation detection ==="

DIR=$(prepare_dir "ac-5-5-reinv")
cp "$P5/already-tests.md" "$DIR/plan.md"
bash "$REINV_SCRIPT" "$DIR/plan.md" > "$DIR/reinv.out" 2>"$DIR/reinv.stderr"
rc=$?
out_clean=$(tr -d '\r\n' < "$DIR/reinv.out")
if [ "$rc" -eq 0 ] && [ "$out_clean" = "re-invocation" ]; then
  pass "AC-5.5: re-invocation-detect returns 're-invocation' rc=0 on plan with existing ### Tests"
else
  fail "AC-5.5: re-invocation-detect expected 're-invocation' rc=0, got '$out_clean' rc=$rc"
fi

DIR2=$(prepare_dir "ac-5-5-first")
cp "$P5/covered.md" "$DIR2/plan.md"
bash "$REINV_SCRIPT" "$DIR2/plan.md" > "$DIR2/reinv.out" 2>/dev/null
rc2=$?
out2_clean=$(tr -d '\r\n' < "$DIR2/reinv.out")
if [ "$rc2" -eq 1 ] && [ "$out2_clean" = "first" ]; then
  pass "AC-5.5: re-invocation-detect returns 'first' rc=1 on plan without ### Tests"
else
  fail "AC-5.5: re-invocation-detect expected 'first' rc=1, got '$out2_clean' rc=$rc2"
fi

# Idempotency: running append-tests-section.sh on a plan with existing
# ### Tests should be a byte-identical no-op (delegated to Phase 3 spec
# but exercised here as the re-invocation contract).
APPEND_TESTS="$SCRIPTS/append-tests-section.sh"
DIR3=$(prepare_dir "ac-5-5-idem")
cp "$P5/already-tests.md" "$DIR3/plan.md"
cp "$DIR3/plan.md" "$DIR3/orig.md"
echo "stub body" > "$DIR3/body.md"
bash "$APPEND_TESTS" "$DIR3/plan.md" "1" "$DIR3/body.md" 2>/dev/null || true
if diff -q "$DIR3/plan.md" "$DIR3/orig.md" >/dev/null 2>&1; then
  pass "AC-5.5: append-tests-section.sh on plan with ### Tests is byte-identical (idempotent)"
else
  fail "AC-5.5: append-tests-section.sh duplicated/modified ### Tests on re-invocation"
fi

# ==========================================================================
# AC-5.6 -- `## Test Spec Revisions` uses 2-column `| Date | Change |`
# format; never `/refine-plan`'s 4-column format.
# ==========================================================================
echo ""
echo "=== AC-5.6 -- 2-column format enforced ==="

DIR=$(prepare_dir "ac-5-6-format")
cp "$P5/covered.md" "$DIR/plan.md"
bash "$TSR_SCRIPT" "$DIR/plan.md" "2026-04-29" "Phase 1: stub change" 2>/dev/null

if grep -F -q "| Date | Change |" "$DIR/plan.md"; then
  pass "AC-5.6: ## Test Spec Revisions uses '| Date | Change |' header (2-column)"
else
  fail "AC-5.6: ## Test Spec Revisions missing 2-column header"
fi
# Negative: must NOT use refine-plan's 4-column form
# `| Phase | Planned | Actual | Delta |`.
if grep -F -q "| Phase | Planned | Actual | Delta |" "$DIR/plan.md"; then
  fail "AC-5.6: forbidden 4-column header (Phase|Planned|Actual|Delta) FOUND in plan"
else
  pass "AC-5.6: forbidden 4-column header NOT present"
fi
# Row must contain the date and change text.
if grep -F -q "| 2026-04-29 | Phase 1: stub change |" "$DIR/plan.md"; then
  pass "AC-5.6: row contains date and change text in 2-column form"
else
  fail "AC-5.6: row MISSING expected date+change content"
fi

# ==========================================================================
# AC-5.7 -- structural preservation of trailing sections;
# closed-enumeration regression guard;
# fenced-code-block regression guard.
# ==========================================================================
echo ""
echo "=== AC-5.7 -- trailing-section structural preservation ==="

# (a) Drift Log + Plan Quality preserved byte-identical post-backfill.
DIR=$(prepare_dir "ac-5-7-drift-quality")
cp "$P5/drift-log-and-review.md" "$DIR/plan.md"
bash "$PARSE_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" 2>/dev/null >/dev/null
bash "$GAP_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" /dev/null "$DIR/gaps.md" 2>/dev/null
# Save original Drift Log + Plan Review + Plan Quality bodies.
awk '/^## Drift Log/,/^## Plan Review/{print > "/tmp/draft-tests-p5-drift.txt"; next}
     /^## Plan Review/,/^## Plan Quality/{print > "/tmp/draft-tests-p5-review.txt"; next}
     /^## Plan Quality/,EOF{print > "/tmp/draft-tests-p5-quality.txt"; next}
     {next}' "$DIR/plan.md" 2>/dev/null || true
extract_section() {
  local plan="$1" name="$2"
  awk -v target="$name" '
    BEGIN { in_code=0; emit=0 }
    /^```/ { in_code = 1 - in_code; if (emit) print; next }
    !in_code && /^## / {
      header=$0
      sub(/^## /, "", header)
      if (header ~ ("^"target)) { emit=1; print; next }
      else if (emit) { exit }
    }
    emit { print }
  ' "$plan"
}
extract_section "$DIR/plan.md" "Drift Log" > "$DIR/drift-pre.txt"
extract_section "$DIR/plan.md" "Plan Review" > "$DIR/review-pre.txt"
extract_section "$DIR/plan.md" "Plan Quality" > "$DIR/quality-pre.txt"

bash "$BACKFILL_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" "$DIR/gaps.md" "$DIR/backfill.md" 2>/dev/null

extract_section "$DIR/plan.md" "Drift Log" > "$DIR/drift-post.txt"
extract_section "$DIR/plan.md" "Plan Review" > "$DIR/review-post.txt"
extract_section "$DIR/plan.md" "Plan Quality" > "$DIR/quality-post.txt"

if diff -q "$DIR/drift-pre.txt" "$DIR/drift-post.txt" >/dev/null 2>&1; then
  pass "AC-5.7: ## Drift Log section byte-identical pre/post backfill"
else
  fail "AC-5.7: ## Drift Log section CHANGED post-backfill"
fi
if diff -q "$DIR/review-pre.txt" "$DIR/review-post.txt" >/dev/null 2>&1; then
  pass "AC-5.7: ## Plan Review section byte-identical pre/post backfill"
else
  fail "AC-5.7: ## Plan Review section CHANGED post-backfill"
fi
if diff -q "$DIR/quality-pre.txt" "$DIR/quality-post.txt" >/dev/null 2>&1; then
  pass "AC-5.7: ## Plan Quality section byte-identical pre/post backfill"
else
  fail "AC-5.7: ## Plan Quality section CHANGED post-backfill"
fi

# Backfill insertion site precedes Drift Log (since Drift Log is the
# first trailing non-phase L2 in this fixture).
backfill_line=$(grep -n '^## Phase [0-9]\+ -- Backfill' "$DIR/plan.md" | head -1 | cut -d: -f1)
drift_line=$(grep -n '^## Drift Log' "$DIR/plan.md" | head -1 | cut -d: -f1)
if [ -n "$backfill_line" ] && [ -n "$drift_line" ] && [ "$backfill_line" -lt "$drift_line" ]; then
  pass "AC-5.7: backfill heading appears BEFORE first trailing non-phase L2 (## Drift Log)"
else
  fail "AC-5.7: backfill placement wrong (backfill_line=$backfill_line drift_line=$drift_line)"
fi

# (b) Closed-enumeration regression: non-canonical
# `## Anti-Patterns -- Hard Constraints` between last phase and
# `## Plan Quality`. Backfill MUST insert IMMEDIATELY BEFORE the
# non-canonical heading.
DIR=$(prepare_dir "ac-5-7-noncanon")
cp "$P5/non-canonical-trailing.md" "$DIR/plan.md"
bash "$PARSE_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" 2>/dev/null >/dev/null
bash "$GAP_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" /dev/null "$DIR/gaps.md" 2>/dev/null
ANTI_PRE_BYTES=$(extract_section "$DIR/plan.md" 'Anti-Patterns')
QUALITY_PRE_BYTES=$(extract_section "$DIR/plan.md" 'Plan Quality')
bash "$BACKFILL_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" "$DIR/gaps.md" "$DIR/backfill.md" 2>/dev/null

backfill_line=$(grep -n '^## Phase [0-9]\+ -- Backfill' "$DIR/plan.md" | head -1 | cut -d: -f1)
anti_line=$(grep -n '^## Anti-Patterns' "$DIR/plan.md" | head -1 | cut -d: -f1)
quality_line=$(grep -n '^## Plan Quality' "$DIR/plan.md" | head -1 | cut -d: -f1)

if [ -n "$backfill_line" ] && [ -n "$anti_line" ] && [ "$backfill_line" -lt "$anti_line" ]; then
  pass "AC-5.7 (closed-enum): backfill IMMEDIATELY BEFORE '## Anti-Patterns -- Hard Constraints'"
else
  fail "AC-5.7 (closed-enum): backfill NOT before Anti-Patterns (backfill=$backfill_line anti=$anti_line)"
fi
# Regression guard: backfill must NOT be sandwiched between Anti-Patterns
# and Plan Quality.
if [ -n "$anti_line" ] && [ -n "$backfill_line" ] && [ -n "$quality_line" ] \
   && [ "$backfill_line" -gt "$anti_line" ] && [ "$backfill_line" -lt "$quality_line" ]; then
  fail "AC-5.7 (closed-enum REGRESSION): backfill SANDWICHED between Anti-Patterns and Plan Quality"
else
  pass "AC-5.7 (closed-enum): backfill NOT sandwiched between Anti-Patterns and Plan Quality"
fi
ANTI_POST_BYTES=$(extract_section "$DIR/plan.md" 'Anti-Patterns')
QUALITY_POST_BYTES=$(extract_section "$DIR/plan.md" 'Plan Quality')
if [ "$ANTI_PRE_BYTES" = "$ANTI_POST_BYTES" ]; then
  pass "AC-5.7 (closed-enum): non-canonical Anti-Patterns section bytes preserved"
else
  fail "AC-5.7 (closed-enum): non-canonical Anti-Patterns section bytes MUTATED"
fi
if [ "$QUALITY_PRE_BYTES" = "$QUALITY_POST_BYTES" ]; then
  pass "AC-5.7 (closed-enum): Plan Quality section bytes preserved"
else
  fail "AC-5.7 (closed-enum): Plan Quality section bytes MUTATED"
fi

# (c) Fenced-code-block regression: `## Example` inside ```markdown```
# fence MUST not be treated as trailing heading. Backfill must skip it
# and insert before the first non-fenced trailing heading
# (## Plan Quality).
DIR=$(prepare_dir "ac-5-7-fenced")
cp "$P5/fenced-trailing.md" "$DIR/plan.md"
bash "$PARSE_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" 2>/dev/null >/dev/null
bash "$GAP_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" /dev/null "$DIR/gaps.md" 2>/dev/null
bash "$BACKFILL_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" "$DIR/gaps.md" "$DIR/backfill.md" 2>/dev/null

backfill_line=$(grep -n '^## Phase [0-9]\+ -- Backfill' "$DIR/plan.md" | head -1 | cut -d: -f1)
quality_line=$(grep -n '^## Plan Quality' "$DIR/plan.md" | head -1 | cut -d: -f1)
example_line=$(grep -n '^## Example' "$DIR/plan.md" | head -1 | cut -d: -f1)
# The `## Example` is INSIDE a fence; it should still appear in the
# file but should not be the insertion-anchor. Backfill must precede
# `## Plan Quality` (the first non-fenced trailing L2).
if [ -n "$backfill_line" ] && [ -n "$quality_line" ] && [ "$backfill_line" -lt "$quality_line" ]; then
  pass "AC-5.7 (fenced): backfill precedes ## Plan Quality (fenced ## Example skipped)"
else
  fail "AC-5.7 (fenced): backfill placement wrong (backfill=$backfill_line quality=$quality_line)"
fi
# Regression: backfill must NOT have been placed BEFORE `## Example`
# (which would mean the fenced heading was used as the anchor).
if [ -n "$example_line" ] && [ -n "$backfill_line" ] && [ "$backfill_line" -lt "$example_line" ]; then
  fail "AC-5.7 (fenced REGRESSION): backfill placed BEFORE the fenced ## Example heading"
else
  pass "AC-5.7 (fenced): backfill NOT placed before fenced ## Example"
fi

# ==========================================================================
# AC-5.8 -- frontmatter `status: complete` -> `active` flip when
# backfill appended; no change when no backfill.
# ==========================================================================
echo ""
echo "=== AC-5.8 -- frontmatter status flip ==="

# (a) Backfill appended -> status flipped to active; other fields
# byte-identical.
DIR=$(prepare_dir "ac-5-8-flip")
cp "$P5/frontmatter-complete.md" "$DIR/plan.md"
bash "$PARSE_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" 2>/dev/null >/dev/null
bash "$GAP_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" /dev/null "$DIR/gaps.md" 2>/dev/null
bash "$BACKFILL_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" "$DIR/gaps.md" "$DIR/backfill.md" 2>/dev/null
bash "$FLIP_SCRIPT" "$DIR/plan.md" 1 2>/dev/null

# Extract YAML frontmatter (between first two --- lines).
extract_fm() { awk 'NR==1 && /^---$/ {p=1; next} p && /^---$/ {exit} p {print}' "$1"; }
fm_post=$(extract_fm "$DIR/plan.md")
if printf '%s\n' "$fm_post" | grep -q '^status: active$'; then
  pass "AC-5.8 (positive): status flipped to 'active' after backfill"
else
  fail "AC-5.8 (positive): status NOT flipped to 'active' (frontmatter: $fm_post)"
fi
if printf '%s\n' "$fm_post" | grep -q '^title: Phase 5 frontmatter-complete fixture$'; then
  pass "AC-5.8 (positive): other frontmatter fields byte-identical (title preserved)"
else
  fail "AC-5.8 (positive): title field MUTATED"
fi
if printf '%s\n' "$fm_post" | grep -q '^owner: alice$'; then
  pass "AC-5.8 (positive): user-authored frontmatter field 'owner: alice' byte-identical"
else
  fail "AC-5.8 (positive): user field 'owner: alice' MUTATED or missing"
fi
# Negative: original status must NOT remain.
if printf '%s\n' "$fm_post" | grep -q '^status: complete$'; then
  fail "AC-5.8 (positive): old status: complete still present after flip"
else
  pass "AC-5.8 (positive): old status: complete is gone"
fi

# (b) No backfill appended -> frontmatter byte-identical including
# status.
DIR=$(prepare_dir "ac-5-8-noflip")
cp "$P5/frontmatter-complete-no-gap.md" "$DIR/plan.md"
cp "$DIR/plan.md" "$DIR/orig.md"
fm_orig=$(extract_fm "$DIR/orig.md")
bash "$PARSE_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" 2>/dev/null >/dev/null
bash "$GAP_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" /dev/null "$DIR/gaps.md" 2>/dev/null
bash "$BACKFILL_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" "$DIR/gaps.md" "$DIR/backfill.md" 2>/dev/null
# Backfill-out should be empty of phases (no backfill appended).
backfill_count=$(awk '/^backfill_phases:$/ {a=1; next} a && /^  / {c++; next} a && /^[^ ]/ {a=0} END {print c+0}' "$DIR/backfill.md")
if [ "$backfill_count" -eq 0 ]; then
  pass "AC-5.8 (negative): no backfill appended on UNKNOWN-only fixture"
else
  fail "AC-5.8 (negative): backfill appended unexpectedly ($backfill_count)"
fi
# Skill MUST NOT call flip-frontmatter-status when no backfill -- so
# frontmatter stays byte-identical.
fm_after=$(extract_fm "$DIR/plan.md")
if [ "$fm_orig" = "$fm_after" ]; then
  pass "AC-5.8 (negative): frontmatter byte-identical when no backfill (status: complete preserved)"
else
  fail "AC-5.8 (negative): frontmatter MUTATED on no-backfill path"
fi

# Defensive: even if flip-frontmatter-status is invoked with should-flip=0,
# it must be a no-op.
DIR=$(prepare_dir "ac-5-8-noflip-gate")
cp "$P5/frontmatter-complete.md" "$DIR/plan.md"
cp "$DIR/plan.md" "$DIR/orig.md"
bash "$FLIP_SCRIPT" "$DIR/plan.md" 0 2>/dev/null
if diff -q "$DIR/plan.md" "$DIR/orig.md" >/dev/null 2>&1; then
  pass "AC-5.8 (negative): flip script with gate=0 is byte-identical no-op"
else
  fail "AC-5.8 (negative): flip script with gate=0 mutated plan"
fi

# ==========================================================================
# AC-5.9 -- Completed-phase checksum drift -> STOP with error;
# plan file NOT written.
# ==========================================================================
echo ""
echo "=== AC-5.9 -- Completed-phase checksum drift detection ==="

# Positive case: clean plan -> verify exits 0.
DIR=$(prepare_dir "ac-5-9-clean")
cp "$P5/missing-backticked.md" "$DIR/plan.md"
bash "$PARSE_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" 2>/dev/null >/dev/null
bash "$VERIFY_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" 2>"$DIR/verify.stderr"
rc=$?
if [ $rc -eq 0 ]; then
  pass "AC-5.9: verify-completed-checksums exits 0 on clean plan"
else
  fail "AC-5.9: verify-completed-checksums exited rc=$rc on clean plan -- stderr: $(cat "$DIR/verify.stderr")"
fi

# Negative case: mutate the Completed phase body, then verify -> rc=1
# and error message names the drifted phase.
DIR=$(prepare_dir "ac-5-9-drifted")
cp "$P5/missing-backticked.md" "$DIR/plan.md"
bash "$PARSE_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" 2>/dev/null >/dev/null
# Mutate Completed phase 1's body (use python3 to avoid sed sanitizer
# pitfalls).
python3 -c "
with open('$DIR/plan.md','r') as f: d=f.read()
d = d.replace('AC-1.1 — function', 'AC-1.1 — DRIFTED function')
with open('$DIR/plan.md','w') as f: f.write(d)
"
bash "$VERIFY_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" 2>"$DIR/verify.stderr"
rc=$?
if [ $rc -eq 1 ]; then
  pass "AC-5.9: verify-completed-checksums returns rc=1 on Completed-phase drift"
else
  fail "AC-5.9: expected rc=1 on drift, got rc=$rc"
fi
if grep -F -q "checksum drift detected" "$DIR/verify.stderr"; then
  pass "AC-5.9: error message includes 'checksum drift detected'"
else
  fail "AC-5.9: error message missing 'checksum drift detected' -- stderr: $(cat "$DIR/verify.stderr")"
fi
if grep -F -q "Phase 1" "$DIR/verify.stderr"; then
  pass "AC-5.9: error message names drifted phase ('Phase 1')"
else
  fail "AC-5.9: error message MISSING 'Phase 1'"
fi
if grep -F -q "Refusing to write" "$DIR/verify.stderr"; then
  pass "AC-5.9: error message states 'Refusing to write the plan file'"
else
  fail "AC-5.9: error message MISSING 'Refusing to write'"
fi

# ==========================================================================
# AC-5.10 -- Backfill phase enrolled in coverage floor.
# Coverage-floor pre-check synthesises a finding for a backfill AC if
# the drafter omits a spec for it.
# ==========================================================================
echo ""
echo "=== AC-5.10 -- backfill phase enrolled in coverage floor ==="

DIR=$(prepare_dir "ac-5-10-floor")
cp "$P5/missing-backticked.md" "$DIR/plan.md"
bash "$PARSE_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" 2>/dev/null >/dev/null
bash "$GAP_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" /dev/null "$DIR/gaps.md" 2>/dev/null
bash "$BACKFILL_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" "$DIR/gaps.md" "$DIR/backfill.md" 2>/dev/null

# Parsed-state must include the new backfill phase id in
# non_delegate_pending_phases.
backfill_id=$(awk '/^backfill_phases:$/ {a=1; next} a && /^  / {sub(/^  /,""); split($0,parts,":"); print parts[1]; exit} a && /^[^ ]/ {a=0}' "$DIR/backfill.md")
if [ -n "$backfill_id" ]; then
  pass "AC-5.10: backfill_phases entry exists (id=$backfill_id)"
else
  fail "AC-5.10: no backfill_phases entry"
fi

if awk -v id="$backfill_id" '/^non_delegate_pending_phases:$/ {a=1; next} a && /^  / { sub(/^  /,""); if ($0==id) {found=1; exit}; next} a && /^[^ ]/ {a=0} END {exit found?0:1}' "$DIR/parsed.md"; then
  pass "AC-5.10: parsed-state non_delegate_pending_phases CONTAINS backfill phase $backfill_id"
else
  fail "AC-5.10: parsed-state non_delegate_pending_phases MISSING backfill phase $backfill_id"
fi

# Now run coverage-floor-precheck on the plan -- with NO drafter output
# (round-input=/dev/null), the merged candidate has no spec for the
# backfill phase's AC-N.M, so the floor must fire.
bash "$PRECHECK_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" /dev/null 0 \
     "ac-5-10" "$DIR/candidate.md" "$DIR/floor-findings.md" 2>"$DIR/pre.stderr"
rc=$?
if [ $rc -eq 0 ]; then
  pass "AC-5.10: precheck exits 0"
else
  fail "AC-5.10: precheck exited rc=$rc -- stderr: $(cat "$DIR/pre.stderr")"
fi
expected_ac="AC-${backfill_id}.1"
if grep -F -q "Coverage floor violated: $expected_ac" "$DIR/floor-findings.md"; then
  pass "AC-5.10: precheck synthesises 'Coverage floor violated: $expected_ac' for backfill phase AC"
else
  fail "AC-5.10: precheck did NOT fire on backfill AC '$expected_ac' -- findings: $(cat "$DIR/floor-findings.md")"
fi

# Sanity: the synthesised finding has the expected blast-radius major
# language (matches Phase 4 conventions).
if grep -F -q "Blast radius: major - coverage floor is the convergence precondition" "$DIR/floor-findings.md"; then
  pass "AC-5.10: synthesised finding carries 'Blast radius: major' language"
else
  fail "AC-5.10: synthesised finding missing 'Blast radius: major' language"
fi

# Counter-check: when a drafter output supplies the backfill spec, the
# floor must NOT fire. This is the symmetric "drafter omits a spec for
# one of the backfill ACs" scenario from the spec, inverted.
cat > "$DIR/drafter-out.md" <<EOF
plan_file: x
parsed_state: x
specs_file: x
round: 0
drafted_phases:
  $backfill_id
delegate_skipped_phases:
ac_less_skipped_phases:
idempotent_skipped_phases:
specs_begin
phase: $backfill_id
- [unit] [risk: $expected_ac] given input X, when called, expect literal Y.
specs_end
EOF
bash "$PRECHECK_SCRIPT" "$DIR/plan.md" "$DIR/parsed.md" "$DIR/drafter-out.md" 0 \
     "ac-5-10" "$DIR/candidate2.md" "$DIR/floor-findings2.md" 2>/dev/null
if [ ! -s "$DIR/floor-findings2.md" ]; then
  pass "AC-5.10: with backfill spec authored, floor does NOT fire (sanity)"
else
  fail "AC-5.10: floor fired despite spec being authored: $(cat "$DIR/floor-findings2.md")"
fi

# ==========================================================================
# AC-5.11 -- ## Test Spec Revisions placement order.
# Order must be: last `## Phase`, ## Drift Log, ## Plan Review,
# ## Test Spec Revisions, then user-authored trailing (## Plan Quality).
# ==========================================================================
echo ""
echo "=== AC-5.11 -- ## Test Spec Revisions placement order ==="

DIR=$(prepare_dir "ac-5-11-order")
cp "$P5/drift-log-and-review.md" "$DIR/plan.md"
bash "$TSR_SCRIPT" "$DIR/plan.md" "2026-04-29" "Phase 1: stub change" 2>/dev/null

# Capture line numbers of the four key headings.
last_phase_line=$(grep -n '^## Phase ' "$DIR/plan.md" | tail -1 | cut -d: -f1)
drift_line=$(grep -n '^## Drift Log' "$DIR/plan.md" | head -1 | cut -d: -f1)
review_line=$(grep -n '^## Plan Review' "$DIR/plan.md" | head -1 | cut -d: -f1)
tsr_line=$(grep -n '^## Test Spec Revisions' "$DIR/plan.md" | head -1 | cut -d: -f1)
quality_line=$(grep -n '^## Plan Quality' "$DIR/plan.md" | head -1 | cut -d: -f1)

# Verify each ordering pair separately for clear failure messages.
if [ -n "$last_phase_line" ] && [ -n "$drift_line" ] && [ "$last_phase_line" -lt "$drift_line" ]; then
  pass "AC-5.11: last ## Phase precedes ## Drift Log"
else
  fail "AC-5.11: last ## Phase does NOT precede ## Drift Log (phase=$last_phase_line drift=$drift_line)"
fi
if [ -n "$drift_line" ] && [ -n "$review_line" ] && [ "$drift_line" -lt "$review_line" ]; then
  pass "AC-5.11: ## Drift Log precedes ## Plan Review"
else
  fail "AC-5.11: ## Drift Log does NOT precede ## Plan Review (drift=$drift_line review=$review_line)"
fi
if [ -n "$review_line" ] && [ -n "$tsr_line" ] && [ "$review_line" -lt "$tsr_line" ]; then
  pass "AC-5.11: ## Plan Review precedes ## Test Spec Revisions"
else
  fail "AC-5.11: ## Plan Review does NOT precede ## Test Spec Revisions (review=$review_line tsr=$tsr_line)"
fi
if [ -n "$tsr_line" ] && [ -n "$quality_line" ] && [ "$tsr_line" -lt "$quality_line" ]; then
  pass "AC-5.11: ## Test Spec Revisions precedes user-authored trailing (## Plan Quality)"
else
  fail "AC-5.11: ## Test Spec Revisions does NOT precede ## Plan Quality (tsr=$tsr_line quality=$quality_line)"
fi

# Repeat insertion: appending a second row should NOT duplicate the
# section heading.
bash "$TSR_SCRIPT" "$DIR/plan.md" "2026-04-30" "Second row" 2>/dev/null
tsr_count=$(grep -c '^## Test Spec Revisions' "$DIR/plan.md")
if [ "$tsr_count" -eq 1 ]; then
  pass "AC-5.11: re-invocation appends row, does NOT duplicate heading"
else
  fail "AC-5.11: re-invocation duplicated ## Test Spec Revisions ($tsr_count headings)"
fi

# ==========================================================================
# Tier-1 hash registration -- ensure new scripts are registered.
# ==========================================================================
echo ""
echo "=== Tier-1 hash registration ==="

OWN_FILE="$REPO_ROOT/skills/update-zskills/references/script-ownership.md"
HASH_FILE="$REPO_ROOT/skills/update-zskills/references/tier1-shipped-hashes.txt"
STALE_FILE="$REPO_ROOT/skills/update-zskills/SKILL.md"

for script_name in gap-detect.sh append-backfill-phase.sh \
                   insert-test-spec-revisions.sh flip-frontmatter-status.sh \
                   re-invocation-detect.sh verify-completed-checksums.sh; do
  if grep -E -q "\| \`$script_name\`[[:space:]]+\|[[:space:]]*1[[:space:]]*\|[[:space:]]+\`draft-tests\`" "$OWN_FILE"; then
    pass "$script_name registered as Tier 1 owned by draft-tests"
  else
    fail "$script_name NOT registered as Tier 1 / draft-tests in script-ownership.md"
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
# SKILL.md prose checks for Phase 5 framing.
# ==========================================================================
echo ""
echo "=== Phase 5 SKILL.md prose ==="

for needle in \
  'COVERED' \
  'UNKNOWN' \
  'MISSING' \
  'backticked token' \
  'gap-detect.sh' \
  'append-backfill-phase.sh' \
  'insert-test-spec-revisions.sh' \
  'flip-frontmatter-status.sh' \
  're-invocation-detect.sh' \
  'verify-completed-checksums.sh' \
  'Backfill phase construction' \
  'Test Spec Revisions' \
  'Drift Log' \
  'Plan Review' \
  'broad form' \
  'Frontmatter flip is single-purpose' \
  '1–3 Completed phases' \
  'Co-skill ordering' \
  'Update parsed-state on backfill insertion' \
  'AC-5.10' \
  'AC-5.11'
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
