#!/bin/bash
# Tests for skills/draft-tests/ -- Phase 1 (skeleton, ingestion, checksum
# gate, AC-ID assignment, ac-less detection, refuse-to-run checks).
#
# Phase 1 establishes the orchestration skeleton plus a parse-plan.sh
# helper script that performs the mechanical heavy lifting (parsing,
# classification, checksum, AC-ID assignment, ac-less detection). Tests
# in this file:
#
#   1. Grep SKILL.md for frontmatter shape, usage strings, and the
#      framing phrases that Phase 1's spec mandates.
#   2. Invoke parse-plan.sh against the fixture plans under
#      tests/fixtures/draft-tests/ and assert the parsed-state file's
#      classification, checksum behaviour, AC-ID assignment, and ac-less
#      listing match the spec.
#
# Run from repo root: bash tests/test-draft-tests.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_DIR="$REPO_ROOT/skills/draft-tests"
SKILL_MD="$SKILL_DIR/SKILL.md"
PARSE_SCRIPT="$SKILL_DIR/scripts/parse-plan.sh"
FIXTURES="$REPO_ROOT/tests/fixtures/draft-tests"

TEST_OUT="/tmp/zskills-tests/$(basename "$REPO_ROOT")/draft-tests"
mkdir -p "$TEST_OUT"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# ----------------------------------------------------------------------
# Helpers.
# ----------------------------------------------------------------------

# Grep the SKILL.md for a literal substring; pass if found, fail otherwise.
expect_skill_contains() {
  local label="$1" needle="$2"
  if grep -F -q -- "$needle" "$SKILL_MD"; then
    pass "$label"
  else
    fail "$label — SKILL.md missing literal: $needle"
  fi
}

# Grep the SKILL.md for an extended-regex pattern.
expect_skill_matches() {
  local label="$1" pattern="$2"
  if grep -E -q -- "$pattern" "$SKILL_MD"; then
    pass "$label"
  else
    fail "$label — SKILL.md missing pattern: $pattern"
  fi
}

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

# Assert that a state-file list exactly matches a newline-separated
# expected value (sorted). Empty expected matches an empty list.
expect_state_list_eq() {
  local label="$1" state_file="$2" key="$3" expected="$4"
  local actual
  actual="$(read_state_list "$state_file" "$key" | LC_ALL=C sort)"
  expected="$(printf '%s' "$expected" | LC_ALL=C sort)"
  if [ "$actual" = "$expected" ]; then
    pass "$label"
  else
    fail "$label — list '$key' mismatch
    expected:
$(printf '%s\n' "$expected" | sed 's/^/      /')
    actual:
$(printf '%s\n' "$actual" | sed 's/^/      /')"
  fi
}

# ----------------------------------------------------------------------
# AC-1.1 — SKILL.md exists with valid frontmatter, including the
# `[guidance...]` positional tail in argument-hint.
# ----------------------------------------------------------------------
echo ""
echo "=== AC-1.1 — SKILL.md frontmatter ==="

if [ -f "$SKILL_MD" ]; then
  pass "AC-1.1: skills/draft-tests/SKILL.md exists"
else
  fail "AC-1.1: skills/draft-tests/SKILL.md missing"
fi

expect_skill_matches "AC-1.1: frontmatter name"               '^name:[[:space:]]+draft-tests'
expect_skill_matches "AC-1.1: frontmatter disable-model-invocation" '^disable-model-invocation:[[:space:]]+false'
expect_skill_matches "AC-1.1: frontmatter argument-hint with [guidance...]" \
  '^argument-hint:[[:space:]]+"<plan-file>[[:space:]]+\[rounds N\][[:space:]]+\[guidance\.\.\.\]"'
expect_skill_matches "AC-1.1: frontmatter description"        '^description:'

# ----------------------------------------------------------------------
# AC-1.2 — Invoking with no plan-file produces an error mentioning the
# usage string. We can't easily exec the skill stand-alone (the skill is
# orchestration prose, not a single binary), so we assert SKILL.md
# documents the error path with the literal usage string.
# ----------------------------------------------------------------------
echo ""
echo "=== AC-1.2 — Usage / error string ==="

expect_skill_contains "AC-1.2: usage string verbatim" \
  'Usage: /draft-tests <plan-file> [rounds N] [guidance...]'

# ----------------------------------------------------------------------
# AC-1.2b — Reviewer + DA prompt prepend semantics for guidance.
# Empty guidance preserves byte-identical reviewer/DA prompt output.
# ----------------------------------------------------------------------
echo ""
echo "=== AC-1.2b — Guidance directive prepend semantics ==="

expect_skill_contains "AC-1.2b: User-driven scope/focus directive phrase" \
  'User-driven scope/focus directive'
expect_skill_contains "AC-1.2b: empty-guidance regression note" \
  'Empty guidance preserves byte-identical'

# ----------------------------------------------------------------------
# AC-1.3 — Tracking marker write idiom is documented in SKILL.md.
# We assert the file contains the canonical fulfilled.draft-tests basename
# pattern and the per-pipeline subdir layout. We also actually invoke the
# parse-plan.sh script and confirm it doesn't error -- the marker write
# is in the SKILL.md prose (the orchestrator runs it before invoking the
# parser), so we test the mechanical pieces independently.
# ----------------------------------------------------------------------
echo ""
echo "=== AC-1.3 — Tracking marker idiom ==="

expect_skill_contains "AC-1.3: fulfilled marker basename" \
  'fulfilled.draft-tests.$TRACKING_ID'
expect_skill_contains "AC-1.3: per-pipeline subdir layout" \
  '$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID'
expect_skill_contains "AC-1.3: status: started literal" \
  'status: started'
expect_skill_contains "AC-1.3: cross-skill sanitize-pipeline-id form" \
  '"$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh"'
# The bare-relative form is FORBIDDEN. Assert SKILL.md does not contain
# the legacy `bash scripts/sanitize-pipeline-id.sh` invocation.
if grep -F -q -- 'bash scripts/sanitize-pipeline-id.sh' "$SKILL_MD"; then
  fail "AC-1.3: SKILL.md must not use forbidden bare-relative sanitize-pipeline-id.sh path"
else
  pass "AC-1.3: no forbidden bare-relative sanitize-pipeline-id.sh path"
fi

# ----------------------------------------------------------------------
# AC-1.4 — Mixed-status classification.
# ----------------------------------------------------------------------
echo ""
echo "=== AC-1.4 — Mixed-status phase classification ==="

WORK_INPUT="$TEST_OUT/mixed-status-input.md"
WORK_STATE="$TEST_OUT/mixed-status-state.md"
cp "$FIXTURES/mixed-status.md" "$WORK_INPUT"
bash "$PARSE_SCRIPT" "$WORK_INPUT" "$WORK_STATE" 2>"$TEST_OUT/mixed-status-stderr.log"
parse_rc=$?
if [ $parse_rc -eq 0 ]; then
  pass "AC-1.4: parse-plan.sh exits 0 on mixed-status fixture"
else
  fail "AC-1.4: parse-plan.sh exited rc=$parse_rc on mixed-status fixture"
fi

# Phases 1, 2, 3 are Completed (Done / ✅ / [x]); 4, 5, 6 are Pending.
EXPECTED_COMPLETED_PHASES="1
2
3"
EXPECTED_PENDING_PHASES="4
5
6"
EXPECTED_NONDELEGATE="4
5
6"
EXPECTED_DELEGATE=""
EXPECTED_AC_LESS=""

# completed_phases lines look like "<phase>:<sha256>". Extract the leading
# phase ids only for comparison.
ACTUAL_COMPLETED_PHASES="$(read_state_list "$WORK_STATE" 'completed_phases' | awk -F: '{print $1}')"
EXP_SORTED="$(printf '%s' "$EXPECTED_COMPLETED_PHASES" | LC_ALL=C sort)"
ACT_SORTED="$(printf '%s' "$ACTUAL_COMPLETED_PHASES" | LC_ALL=C sort)"
if [ "$EXP_SORTED" = "$ACT_SORTED" ]; then
  pass "AC-1.4: completed_phases = {1, 2, 3}"
else
  fail "AC-1.4: completed_phases mismatch (expected: $EXP_SORTED, got: $ACT_SORTED)"
fi

expect_state_list_eq "AC-1.4: pending_phases = {4, 5, 6}"            "$WORK_STATE" pending_phases            "$EXPECTED_PENDING_PHASES"
expect_state_list_eq "AC-1.4: non_delegate_pending_phases = {4,5,6}" "$WORK_STATE" non_delegate_pending_phases "$EXPECTED_NONDELEGATE"
expect_state_list_eq "AC-1.4: delegate_phases = {}"                  "$WORK_STATE" delegate_phases            "$EXPECTED_DELEGATE"
expect_state_list_eq "AC-1.4: ac_less = {}"                          "$WORK_STATE" ac_less                    "$EXPECTED_AC_LESS"

# ----------------------------------------------------------------------
# AC-1.5 — Checksum semantics.
#   (1) Reruns against an unchanged plan produce identical checksums.
#   (2) Trailing-section append (## Drift Log etc.) does NOT change the
#       last Completed phase's checksum.
#   (3) Non-canonical level-2 heading ## Non-Goals between phases
#       terminates the prior Completed phase's checksum correctly; later
#       edits to ## Non-Goals do not flag drift.
#   (4) Fenced-code-block ## heading inside a Completed phase is
#       INCLUDED in the checksum (not falsely terminated).
# ----------------------------------------------------------------------
echo ""
echo "=== AC-1.5 — Checksum boundary semantics ==="

# Helper: extract the SHA-256 for a given phase from the parsed-state.
get_phase_sha() {
  local state_file="$1" phase_id="$2"
  awk -v want="$phase_id" '
    /^completed_phases:/ { active=1; next }
    active && /^  / {
      line=$0
      sub(/^  /, "", line)
      n = index(line, ":")
      if (n > 0) {
        pid = substr(line, 1, n-1)
        sha = substr(line, n+1)
        if (pid == want) { print sha; exit }
      }
      next
    }
    active && /^[^ ]/ { active=0 }
  ' "$state_file"
}

# Case 1+2+3 — trailing-sections fixture.
TR_INPUT="$TEST_OUT/trailing-sections-input.md"
TR_STATE_A="$TEST_OUT/trailing-sections-state-A.md"
TR_STATE_B="$TEST_OUT/trailing-sections-state-B.md"
TR_STATE_C="$TEST_OUT/trailing-sections-state-C.md"

cp "$FIXTURES/trailing-sections.md" "$TR_INPUT"
bash "$PARSE_SCRIPT" "$TR_INPUT" "$TR_STATE_A" 2>/dev/null

P1_SHA_A="$(get_phase_sha "$TR_STATE_A" 1)"
P2_SHA_A="$(get_phase_sha "$TR_STATE_A" 2)"
if [ -n "$P1_SHA_A" ] && [ -n "$P2_SHA_A" ]; then
  pass "AC-1.5: every Completed phase has a checksum (run A)"
else
  fail "AC-1.5: missing checksums (P1='$P1_SHA_A' P2='$P2_SHA_A')"
fi

# Rerun -- identical checksums.
cp "$FIXTURES/trailing-sections.md" "$TR_INPUT"
bash "$PARSE_SCRIPT" "$TR_INPUT" "$TR_STATE_B" 2>/dev/null
P1_SHA_B="$(get_phase_sha "$TR_STATE_B" 1)"
P2_SHA_B="$(get_phase_sha "$TR_STATE_B" 2)"
if [ "$P1_SHA_A" = "$P1_SHA_B" ] && [ "$P2_SHA_A" = "$P2_SHA_B" ]; then
  pass "AC-1.5: rerun against unchanged plan produces identical checksums"
else
  fail "AC-1.5: rerun checksums drifted"
fi

# Append text to the trailing ## Drift Log + ## Plan Quality + ## Non-Goals
# sections; rerun; assert P2 (the last Completed phase) checksum did NOT
# change. P1 also unchanged.
{
  echo ""
  echo "Appended advisory to Plan Quality."
} >> "$TR_INPUT"
# Also surgically tweak ## Non-Goals to ensure the non-canonical heading's
# bytes don't sweep into Phase 2's checksum.
TR_INPUT_NG="$TEST_OUT/trailing-sections-input-NG.md"
sed 's/non-canonical level-2 heading/non-canonical level-two heading/' \
  "$TR_INPUT" > "$TR_INPUT_NG"
bash "$PARSE_SCRIPT" "$TR_INPUT_NG" "$TR_STATE_C" 2>/dev/null
P1_SHA_C="$(get_phase_sha "$TR_STATE_C" 1)"
P2_SHA_C="$(get_phase_sha "$TR_STATE_C" 2)"
if [ "$P1_SHA_A" = "$P1_SHA_C" ]; then
  pass "AC-1.5: P1 checksum unchanged after trailing-section append + Non-Goals edit"
else
  fail "AC-1.5: P1 checksum drifted after trailing-section append (A=$P1_SHA_A C=$P1_SHA_C)"
fi
if [ "$P2_SHA_A" = "$P2_SHA_C" ]; then
  pass "AC-1.5: P2 (last Completed) checksum unchanged after trailing-section append + Non-Goals edit"
else
  fail "AC-1.5: P2 checksum drifted after trailing-section append (A=$P2_SHA_A C=$P2_SHA_C)"
fi

# Case 4 — fenced-code-block ## heading inside Phase 1 (Completed).
FH_INPUT="$TEST_OUT/fenced-headings-input.md"
FH_STATE_A="$TEST_OUT/fenced-headings-state-A.md"
FH_STATE_B="$TEST_OUT/fenced-headings-state-B.md"
cp "$FIXTURES/fenced-headings.md" "$FH_INPUT"
bash "$PARSE_SCRIPT" "$FH_INPUT" "$FH_STATE_A" 2>/dev/null
FH_P1_SHA="$(get_phase_sha "$FH_STATE_A" 1)"
if [ -n "$FH_P1_SHA" ]; then
  pass "AC-1.5: fenced-headings fixture P1 has a checksum"
else
  fail "AC-1.5: fenced-headings fixture P1 missing checksum (boundary may have falsely terminated)"
fi

# Verify the checksum INCLUDES the post-fence prose. Compute the same
# checksum independently using the boundary rule: P1 spans from
# `## Phase 1 — Embedded` to (but not including) `## Phase 2 — Pending`,
# OUTSIDE fenced code blocks. We reproduce by extracting via awk that
# tracks in_code identically and computing sha256 on the slice.
EXPECTED_FH_P1_SHA="$(awk '
  BEGIN { in_code=0; in_phase=0 }
  /^```/ { in_code = 1 - in_code; if (in_phase) print; next }
  /^## / && in_code==0 {
    if ($0 ~ /^## Phase 1 / ) { in_phase=1; print; next }
    if (in_phase) { exit }
  }
  in_phase { print }
' "$FH_INPUT" | sha256sum | awk '{print $1}')"
if [ "$FH_P1_SHA" = "$EXPECTED_FH_P1_SHA" ]; then
  pass "AC-1.5: fenced-headings P1 checksum matches independently-computed boundary"
else
  fail "AC-1.5: fenced-headings P1 checksum drift (got $FH_P1_SHA, expected $EXPECTED_FH_P1_SHA)"
fi

# Sanity: the fence-only naive `^## ` boundary scan SHOULD give a
# DIFFERENT checksum (because it would terminate at `## Example Section`).
NAIVE_FH_P1_SHA="$(awk '
  BEGIN { in_phase=0 }
  /^## / {
    if ($0 ~ /^## Phase 1 / ) { in_phase=1; print; next }
    if (in_phase) { exit }
  }
  in_phase { print }
' "$FH_INPUT" | sha256sum | awk '{print $1}')"
if [ "$FH_P1_SHA" != "$NAIVE_FH_P1_SHA" ]; then
  pass "AC-1.5: fenced-headings P1 checksum differs from a naive (non-fence-aware) boundary scan"
else
  fail "AC-1.5: fenced-headings P1 checksum matches the naive scan -- fence awareness may be missing"
fi

# Now mutate post-fence prose; rerun; checksum MUST drift (proves the
# bytes are part of P1).
sed -i.bak 's/After the fenced block,/After the fenced block (mutated),/' "$FH_INPUT" && rm -f "$FH_INPUT.bak"
bash "$PARSE_SCRIPT" "$FH_INPUT" "$FH_STATE_B" 2>/dev/null
FH_P1_SHA_B="$(get_phase_sha "$FH_STATE_B" 1)"
if [ "$FH_P1_SHA_B" != "$FH_P1_SHA" ]; then
  pass "AC-1.5: editing post-fence prose in P1 changes its checksum (the fenced + post-fence bytes are inside P1)"
else
  fail "AC-1.5: editing post-fence prose in P1 did NOT change checksum (boundary may have falsely terminated at the in-code heading)"
fi

# ----------------------------------------------------------------------
# AC-1.6 — AC-ID assignment in Pending phases (mixed-status fixture).
# Plain bullets get prefixed; Completed-phase ACs unchanged; bullets
# outside `### Acceptance Criteria` blocks unchanged.
# ----------------------------------------------------------------------
echo ""
echo "=== AC-1.6 — AC-ID assignment ==="

# After the AC-1.4 invocation, $WORK_INPUT has been mutated in place
# (parse-plan.sh edits the plan file). Read it back and assert.
P4_AC_LINE="$(grep -n '^- \[ \] AC-4.1 — gain a canonical' "$WORK_INPUT" | head -1)"
if [ -n "$P4_AC_LINE" ]; then
  pass "AC-1.6: Phase 4's first plain bullet is now AC-4.1"
else
  fail "AC-1.6: Phase 4's first plain bullet did not receive AC-4.1 prefix"
fi
P4_AC_LINE2="$(grep -n '^- \[ \] AC-4.2 — another plain bullet' "$WORK_INPUT" | head -1)"
if [ -n "$P4_AC_LINE2" ]; then
  pass "AC-1.6: Phase 4's second plain bullet is now AC-4.2 (per-phase counter)"
else
  fail "AC-1.6: Phase 4's second plain bullet did not receive AC-4.2 prefix"
fi
P5_AC_LINE="$(grep -n '^- \[ \] AC-5.1 — still pending criterion' "$WORK_INPUT" | head -1)"
if [ -n "$P5_AC_LINE" ]; then
  pass "AC-1.6: Phase 5's plain bullet is now AC-5.1 (per-phase counter resets)"
else
  fail "AC-1.6: Phase 5's plain bullet did not receive AC-5.1 prefix"
fi
P6_AC_LINE="$(grep -n '^- \[ \] AC-6.1 — empty-status pending bullet' "$WORK_INPUT" | head -1)"
if [ -n "$P6_AC_LINE" ]; then
  pass "AC-1.6: Phase 6's plain bullet is now AC-6.1"
else
  fail "AC-1.6: Phase 6's plain bullet did not receive AC-6.1 prefix"
fi

# Completed phases' ACs MUST be byte-identical. Compare lines against the
# fixture original.
FIXTURE_LINE_COMPLETED_AC="$(grep -F -- '- [ ] AC-1.1 — already-prefixed canonical' "$FIXTURES/mixed-status.md")"
WORK_LINE_COMPLETED_AC="$(grep -F -- '- [ ] AC-1.1 — already-prefixed canonical' "$WORK_INPUT")"
if [ "$FIXTURE_LINE_COMPLETED_AC" = "$WORK_LINE_COMPLETED_AC" ] && [ -n "$FIXTURE_LINE_COMPLETED_AC" ]; then
  pass "AC-1.6: Completed phase 1's AC bullet is byte-identical post-run"
else
  fail "AC-1.6: Completed phase 1's AC bullet was modified"
fi
FIXTURE_LINE_COMPLETED2="$(grep -F -- '- [x] AC-2.1 — completed canonical' "$FIXTURES/mixed-status.md")"
WORK_LINE_COMPLETED2="$(grep -F -- '- [x] AC-2.1 — completed canonical' "$WORK_INPUT")"
if [ "$FIXTURE_LINE_COMPLETED2" = "$WORK_LINE_COMPLETED2" ] && [ -n "$FIXTURE_LINE_COMPLETED2" ]; then
  pass "AC-1.6: Completed phase 2's AC bullet (with [x]) is byte-identical post-run"
else
  fail "AC-1.6: Completed phase 2's AC bullet (with [x]) was modified"
fi

# Bullet OUTSIDE an AC block (Phase 1 has `- [ ] 1.1 — sample work item`
# under `### Work Items`). The fixture's Phase 1 is Completed and the
# bullet is not inside `### Acceptance Criteria` -- regardless of status,
# work-item bullets are NEVER touched. Assert byte-identical.
FIXTURE_WI_BULLET="$(grep -nF -- '- [ ] 1.1 — sample work item (ambiguous-prefix' "$FIXTURES/mixed-status.md")"
WORK_WI_BULLET="$(grep -nF -- '- [ ] 1.1 — sample work item (ambiguous-prefix' "$WORK_INPUT")"
if [ "$FIXTURE_WI_BULLET" = "$WORK_WI_BULLET" ] && [ -n "$FIXTURE_WI_BULLET" ]; then
  pass "AC-1.6: bullet outside AC block (Work Items) is byte-identical post-run"
else
  fail "AC-1.6: bullet outside AC block was modified (or vanished)"
fi

# Phase 4's Work Items bullet `- [ ] 4.1 — sample work item` is in a
# Pending phase but outside the AC block -- MUST also be byte-identical.
FIXTURE_WI4="$(grep -nF -- '- [ ] 4.1 — sample work item' "$FIXTURES/mixed-status.md")"
WORK_WI4="$(grep -nF -- '- [ ] 4.1 — sample work item' "$WORK_INPUT")"
if [ "$FIXTURE_WI4" = "$WORK_WI4" ] && [ -n "$FIXTURE_WI4" ]; then
  pass "AC-1.6: Pending-phase Work Items bullet outside AC block is byte-identical"
else
  fail "AC-1.6: Pending-phase Work Items bullet outside AC block was modified"
fi

# ----------------------------------------------------------------------
# AC-1.6b — Re-running after AC-IDs are assigned does not double-prefix.
# ----------------------------------------------------------------------
echo ""
echo "=== AC-1.6b — Idempotent re-run ==="

# $WORK_INPUT was already mutated by AC-1.4's run. Save its current
# contents and re-run.
WORK_INPUT_SNAP="$TEST_OUT/mixed-status-input-snap.md"
cp "$WORK_INPUT" "$WORK_INPUT_SNAP"
WORK_STATE2="$TEST_OUT/mixed-status-state-2.md"
bash "$PARSE_SCRIPT" "$WORK_INPUT" "$WORK_STATE2" 2>/dev/null
if cmp -s "$WORK_INPUT" "$WORK_INPUT_SNAP"; then
  pass "AC-1.6b: re-run produces byte-identical plan file (no double-prefix)"
else
  fail "AC-1.6b: re-run mutated the plan file (double-prefix or other drift)"
fi
# Also assert no `AC-4.1 — AC-4.1` or similar double-numeral pattern.
if grep -qE 'AC-[0-9]+[a-z]?\.[0-9]+ — AC-' "$WORK_INPUT"; then
  fail "AC-1.6b: double-numeral pattern detected"
else
  pass "AC-1.6b: no double-numeral pattern detected"
fi

# ----------------------------------------------------------------------
# AC-1.6c — Ambiguous prefix refuse path.
# ----------------------------------------------------------------------
echo ""
echo "=== AC-1.6c — Ambiguous-prefix refuse path ==="

AMB_INPUT="$TEST_OUT/ambiguous-prefixes-input.md"
AMB_STATE="$TEST_OUT/ambiguous-prefixes-state.md"
AMB_STDERR="$TEST_OUT/ambiguous-prefixes-stderr.log"
cp "$FIXTURES/ambiguous-prefixes.md" "$AMB_INPUT"
bash "$PARSE_SCRIPT" "$AMB_INPUT" "$AMB_STATE" 2>"$AMB_STDERR"

# All three ambiguous bullets must be byte-identical.
for needle in \
  '- [ ] 1.1 — work-item-style prefix' \
  '- [ ] AC-3.2 covered when X happens' \
  '- [ ] [scope] given input'
do
  if grep -F -q -- "$needle" "$AMB_INPUT"; then
    pass "AC-1.6c: ambiguous bullet preserved byte-identical: $needle"
  else
    fail "AC-1.6c: ambiguous bullet MUTATED or removed: $needle"
  fi
done

# The plain bullet should have been assigned (ambiguous bullets DON'T
# advance the per-phase counter, so the plain bullet gets AC-1.1 -- but
# wait, the canonical bullet `AC-1.4` already exists and seeds highest=4,
# so the plain bullet becomes AC-1.5).
if grep -F -q -- '- [ ] AC-1.5 — plain bullet that should get an AC ID assigned' "$AMB_INPUT"; then
  pass "AC-1.6c: plain bullet assigned AC-1.5 (counter seeded by canonical AC-1.4)"
else
  fail "AC-1.6c: plain bullet did not receive expected AC-1.5 prefix"
  echo "        AC-1.* bullets in mutated plan:" >&2
  grep -nE '^- \[[ xX]\] AC-1\.' "$AMB_INPUT" >&2 || true
fi

# Canonical bullet untouched.
if grep -F -q -- '- [ ] AC-1.4 — already canonical, must remain byte-identical' "$AMB_INPUT"; then
  pass "AC-1.6c: canonical bullet preserved byte-identical (idempotent skip)"
else
  fail "AC-1.6c: canonical bullet was modified"
fi

# Work-items bullet `- [ ] 1.1 — work-item-style numbered bullet` outside
# the AC block must be byte-identical (it's a non-AC ambiguous-shape
# bullet that the parser should never touch).
WI_NEEDLE='- [ ] 1.1 — work-item-style numbered bullet (NOT inside an AC block'
if grep -F -q -- "$WI_NEEDLE" "$AMB_INPUT"; then
  pass "AC-1.6c: Work Items bullet outside AC block is byte-identical"
else
  fail "AC-1.6c: Work Items bullet outside AC block was modified"
fi

# Advisory lines: one per refused bullet, mentioning file:line.
ADV_COUNT="$(grep -c -F 'Refused AC-ID assignment for' "$AMB_STDERR" || true)"
if [ "$ADV_COUNT" = "3" ]; then
  pass "AC-1.6c: exactly 3 advisory lines emitted (one per ambiguous bullet)"
else
  fail "AC-1.6c: expected 3 advisory lines, got $ADV_COUNT"
  cat "$AMB_STDERR" >&2 || true
fi
# Each advisory must include the file path and a line number.
if grep -E -q 'Refused AC-ID assignment for ".*ambiguous-prefixes-input\.md:[0-9]+"' "$AMB_STDERR"; then
  pass "AC-1.6c: advisory lines include <file>:<lineno>"
else
  fail "AC-1.6c: advisory lines do not include <file>:<lineno> shape"
fi

# Advisories also persisted to the parsed-state file.
if grep -F -q 'Refused AC-ID assignment for' "$AMB_STATE"; then
  pass "AC-1.6c: advisories also persisted to parsed-state"
else
  fail "AC-1.6c: advisories absent from parsed-state"
fi

# ----------------------------------------------------------------------
# AC-1.7 — Refuse-to-run checks. The "all-Completed + no gaps" exit
# message and the route-to-backfill semantics are documented in
# SKILL.md; Phase 5 backfill detection is a later-phase build-out. Test
# the Phase-1 part: missing plan file + no Progress Tracker.
# ----------------------------------------------------------------------
echo ""
echo "=== AC-1.7 — Refuse-to-run checks ==="

# (i) Missing plan file.
MISSING_OUT="$TEST_OUT/missing-state.md"
if bash "$PARSE_SCRIPT" "$TEST_OUT/does-not-exist.md" "$MISSING_OUT" 2>"$TEST_OUT/missing-stderr.log"; then
  fail "AC-1.7: parse-plan.sh did NOT exit non-zero on missing plan file"
else
  pass "AC-1.7: parse-plan.sh exits non-zero on missing plan file"
fi
if grep -q 'not found' "$TEST_OUT/missing-stderr.log"; then
  pass "AC-1.7: missing-plan-file error mentions 'not found'"
else
  fail "AC-1.7: missing-plan-file error does not mention 'not found'"
fi

# (ii) No Progress Tracker.
NT_INPUT="$TEST_OUT/no-tracker-input.md"
NT_STATE="$TEST_OUT/no-tracker-state.md"
NT_STDERR="$TEST_OUT/no-tracker-stderr.log"
cp "$FIXTURES/no-tracker.md" "$NT_INPUT"
if bash "$PARSE_SCRIPT" "$NT_INPUT" "$NT_STATE" 2>"$NT_STDERR"; then
  fail "AC-1.7: parse-plan.sh did NOT exit non-zero on plan with no Progress Tracker"
else
  pass "AC-1.7: parse-plan.sh exits non-zero on plan with no Progress Tracker"
fi
if grep -q 'no Progress Tracker' "$NT_STDERR" || grep -q 'Progress Tracker' "$NT_STDERR"; then
  pass "AC-1.7: no-Progress-Tracker error mentions 'Progress Tracker'"
else
  fail "AC-1.7: no-Progress-Tracker error does not mention 'Progress Tracker'"
fi

# (iii) The "all complete + no gaps -- nothing to draft or backfill"
# message is documented in SKILL.md as the orchestrator's exit text.
expect_skill_contains "AC-1.7: 'nothing to draft or backfill' message documented in SKILL.md" \
  'nothing to draft or backfill'

# (iv) Plan with all phases Completed but Phase 1 itself does NOT exit
# uncleanly -- it routes to Phase 5 backfill (when implemented). For the
# parse-plan.sh script (Phase 1 mechanics), the plan parses cleanly: no
# Pending phases, all Completed phases checksummed.
ALL_INPUT="$TEST_OUT/all-completed-input.md"
ALL_STATE="$TEST_OUT/all-completed-state.md"
cp "$FIXTURES/all-completed.md" "$ALL_INPUT"
bash "$PARSE_SCRIPT" "$ALL_INPUT" "$ALL_STATE" 2>/dev/null
all_rc=$?
if [ $all_rc -eq 0 ]; then
  pass "AC-1.7: all-Completed plan parses successfully (does NOT abort)"
else
  fail "AC-1.7: all-Completed plan caused parse-plan.sh to exit rc=$all_rc"
fi
ALL_PENDING="$(read_state_list "$ALL_STATE" pending_phases)"
ALL_COMPLETED="$(read_state_list "$ALL_STATE" completed_phases | awk -F: '{print $1}')"
if [ -z "$ALL_PENDING" ]; then
  pass "AC-1.7: all-Completed plan -> pending_phases is empty"
else
  fail "AC-1.7: all-Completed plan -> pending_phases unexpectedly non-empty: $ALL_PENDING"
fi
if [ "$(printf '%s' "$ALL_COMPLETED" | LC_ALL=C sort)" = "$(printf '1\n2' | LC_ALL=C sort)" ]; then
  pass "AC-1.7: all-Completed plan -> completed_phases = {1, 2}"
else
  fail "AC-1.7: all-Completed plan -> unexpected completed_phases: $ALL_COMPLETED"
fi

# ----------------------------------------------------------------------
# AC-1.7b — Ac-less Pending non-delegate phase.
#
# Fixture has 2 Pending non-delegate phases: Phase 1 (no AC block,
# ac-less) and Phase 2 (normal AC block). After parsing:
#   - ac_less:                     [1]
#   - non_delegate_pending_phases: [1, 2]   (both retained per spec)
#   - exactly one ac-less advisory line emitted to stderr
#   - Phase 2's plain AC bullet receives AC-2.1
# Phase 3's M = N − K formula (N=2 non-delegate Pending; K=1 ac-less;
# M=1) self-passes when Phase 3 lands -- AC-1.7b's self-pass is the
# fixture shape, which we verify.
# ----------------------------------------------------------------------
echo ""
echo "=== AC-1.7b — Ac-less Pending phase ==="

ACL_INPUT="$TEST_OUT/ac-less-and-normal-input.md"
ACL_STATE="$TEST_OUT/ac-less-and-normal-state.md"
ACL_STDERR="$TEST_OUT/ac-less-and-normal-stderr.log"
cp "$FIXTURES/ac-less-and-normal.md" "$ACL_INPUT"
bash "$PARSE_SCRIPT" "$ACL_INPUT" "$ACL_STATE" 2>"$ACL_STDERR"

# (i) ac_less: [1].
expect_state_list_eq "AC-1.7b: ac_less = {1}" "$ACL_STATE" ac_less "1"

# (ii) non_delegate_pending_phases retains the ac-less phase.
expect_state_list_eq "AC-1.7b: non_delegate_pending_phases retains ac-less phase ({1, 2})" \
  "$ACL_STATE" non_delegate_pending_phases "$(printf '1\n2')"

# (iii) Exactly one ac-less advisory line.
ACL_ADVISORY_COUNT="$(grep -c -F 'has no `### Acceptance Criteria` block' "$ACL_STDERR" || true)"
if [ "$ACL_ADVISORY_COUNT" = "1" ]; then
  pass "AC-1.7b: exactly one ac-less advisory line emitted"
else
  fail "AC-1.7b: expected 1 ac-less advisory, got $ACL_ADVISORY_COUNT"
  cat "$ACL_STDERR" >&2 || true
fi

# (iv) The advisory mentions Phase 1.
if grep -E -q 'Phase 1 has no `### Acceptance Criteria` block' "$ACL_STDERR"; then
  pass "AC-1.7b: advisory line names Phase 1 specifically"
else
  fail "AC-1.7b: advisory line does not name Phase 1"
fi

# (v) Phase 2's plain AC bullet got an AC-2.1 prefix.
if grep -F -q -- '- [ ] AC-2.1 — criterion' "$ACL_INPUT"; then
  pass "AC-1.7b: normal Pending phase 2's bullet received AC-2.1"
else
  fail "AC-1.7b: normal Pending phase 2's bullet did not receive AC-2.1"
fi

# (vi) M = N − K self-pass: N (non-delegate Pending) = 2; K (ac-less) =
# 1; M = 1 -> exactly one Pending phase eligible for `### Tests` append
# in Phase 3 (i.e., {1, 2} \ {1} = {2}). We verify the set arithmetic
# here so a future Phase-3 implementation has a green AC-1.7b base case.
NDPP="$(read_state_list "$ACL_STATE" non_delegate_pending_phases | LC_ALL=C sort -u)"
ACL="$(read_state_list "$ACL_STATE" ac_less | LC_ALL=C sort -u)"
ELIGIBLE_FOR_TESTS_APPEND="$(comm -23 <(printf '%s' "$NDPP") <(printf '%s' "$ACL"))"
ELIGIBLE_COUNT="$(printf '%s' "$ELIGIBLE_FOR_TESTS_APPEND" | grep -c . || true)"
if [ "$ELIGIBLE_COUNT" = "1" ] && [ "$ELIGIBLE_FOR_TESTS_APPEND" = "2" ]; then
  pass "AC-1.7b: M = N − K self-pass (N=2, K=1, M=1; eligible-for-tests = {2})"
else
  fail "AC-1.7b: M = N − K self-pass failed (eligible='$ELIGIBLE_FOR_TESTS_APPEND', count=$ELIGIBLE_COUNT)"
fi

# ----------------------------------------------------------------------
# Helper-script registration check: parse-plan.sh has owner row in
# script-ownership.md.
# ----------------------------------------------------------------------
echo ""
echo "=== Script ownership registry ==="

OWN_FILE="$REPO_ROOT/skills/update-zskills/references/script-ownership.md"
if grep -F -q '`parse-plan.sh`' "$OWN_FILE"; then
  pass "script-ownership.md registers parse-plan.sh"
else
  fail "script-ownership.md does NOT register parse-plan.sh"
fi
if grep -E -q '\| `parse-plan\.sh`[[:space:]]+\|[[:space:]]*1[[:space:]]*\|[[:space:]]+`draft-tests`' "$OWN_FILE"; then
  pass "parse-plan.sh registered as Tier 1 owned by draft-tests"
else
  fail "parse-plan.sh NOT registered as Tier 1 / draft-tests owner"
fi

# ----------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------
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
