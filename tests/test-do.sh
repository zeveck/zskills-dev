#!/bin/bash
# Tests for skills/do/SKILL.md — Phase 2a triage / inline plan / fresh-agent
# review additions (the cron-zombie regression fix).
#
# Phase 2b cases (1–13):
#   1.  argument-hint contains --force and --rounds N
#   2.  Phase 0a heading + rubric-table present AND comes BEFORE Phase 0c
#       (cron-zombie regression guard: triage MUST run before CronCreate)
#   3.  Phase 0b inline-plan + review prose present
#   4.  --force cron-persistence prose present
#   5.  Meta-command bypass anchored after meta-command bullet block
#   6.  VERDICT parser regex documented (APPROVE bare; REVISE/REJECT need --)
#   7.  --rounds 0 skip-review prose + stderr WARN string present
#   8.  Phase 1.5 Step 2 strips --force and --rounds N from TASK_DESCRIPTION
#   9.  --rounds notanumber → ROUNDS stays at default 1 (greedy fallthrough)
#   10. Phase 0b orthogonality with /verify-changes + PR-mode negation prose
#   11. Entry-point unset guard: harness env vars without harness flag get unset
#   12. Phase 1.5 re-validation does NOT exit 2 on non-numeric --rounds (R2)
#   13. Quoted-description protection in TASK_DESCRIPTION_FOR_CRON (DA3)
#
# Cron-zombie regression cases: Cases 2 (ordering) plus the seam-driven
# triage REDIRECT and review REJECT paths assert NO cron is registered when
# /do redirects/rejects in Phase 0a/0b. Phase 0c (cron registration) is
# textually placed AFTER 0a/0b in the skill, so a redirect/reject exits
# before any CronCreate call. The static ordering guard (Case 2) is the
# load-bearing structural assertion; the seam tests (covered upstream in
# /quickfix Cases 47/48 — /do is symmetric) verify dynamic behavior.
#
# Mirror house-style of tests/test-quickfix.sh: per-case fixture, capture
# stderr, pass/fail helpers, cleanup trap.
#
# Run from repo root: bash tests/test-do.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/skills/do/SKILL.md"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  printf '\033[32m  PASS\033[0m %s\n' "$1"
  PASS_COUNT=$((PASS_COUNT + 1))
}
fail() {
  printf '\033[31m  FAIL\033[0m %s\n' "$1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

# Per-run scratch dir under /tmp so any rm -rf passes is_safe_destruct.
TEST_TMPDIR="/tmp/zskills-do-test-$$"
mkdir -p "$TEST_TMPDIR"
FIXTURES=()
register_fixture() { FIXTURES+=("$1"); }
cleanup() {
  local f
  for f in "${FIXTURES[@]:-}"; do
    [ -z "$f" ] && continue
    if [ -d "$f" ] && [[ "$f" == /tmp/* ]]; then
      rm -rf -- "$f" 2>/dev/null || true
    fi
  done
  rm -rf -- "$TEST_TMPDIR" 2>/dev/null || true
}
trap cleanup EXIT

# ──────────────────────────────────────────────────────────────────────
# Fixture builder: minimal git repo for cases that need a $FIX directory
# (cron-zombie seam tests). /do has no preflight slice to drive end-to-end
# (most logic is model-layer prose), so most cases are static-grep against
# the SKILL source. The fixture is needed only for seam-driven Cases 11
# and the dynamic ordering check.
# ──────────────────────────────────────────────────────────────────────
make_fixture() {
  local name="$1"
  local fix
  fix=$(mktemp -d -t "zskills-do.$name.XXXXXX")
  register_fixture "$fix"
  git init --quiet -b main "$fix"
  git -C "$fix" config user.email "t@t"
  git -C "$fix" config user.name "t"
  echo "seed" > "$fix/README.md"
  git -C "$fix" add README.md
  git -C "$fix" commit --quiet -m "seed"
  printf '%s\n' "$fix"
}

# ──────────────────────────────────────────────────────────────────────
# AWK extractor for the leading pre-flight bash fence (WI 2a.0 / WI 2a.3
# unset guard). Cases 11 and 12 drive this fence in isolation.
#
# The pre-flight fence is the FIRST fenced bash block in the file, between
# the `## Pre-flight — Flag pre-parse ...` heading and the `## Phase 0a`
# heading.
# ──────────────────────────────────────────────────────────────────────
extract_preflight() {
  awk '
    /^## Pre-flight/      { in_section = 1; next }
    /^## Phase 0a/        { in_section = 0 }
    !in_section           { next }
    /^```bash$/           { infence = 1; next }
    infence && /^```$/    { infence = 0; print ""; next }
    infence               { print }
  ' "$SKILL"
}

# Phase 1.5 Step 2 extractor: the `TASK_DESCRIPTION=$(echo "$REMAINING" \`
# block (multi-line continuation chain). Captures from the line that
# starts `TASK_DESCRIPTION=$(echo` through the line ending with the
# `'^[[:space:]]+//;s/[[:space:]]+$//'` final pipe stage. Followed by the
# `if [ -z "$TASK_DESCRIPTION" ]` guard and its body — but we need only
# the assignment for Case 8. Use AWK to grab the contiguous block.
extract_task_description_block() {
  awk '
    /^TASK_DESCRIPTION=\$\(echo "\$REMAINING" \\$/  { collecting = 1 }
    collecting                                       { print; if ($0 ~ /\$\{[^}]+\}\)$/ || $0 ~ /\)$/) collecting = 0 }
  ' "$SKILL"
}

# Phase 1.5 Step 4 re-validation block (Case 12): the `FORCE=${FORCE:-0}`
# block + `--rounds [0-9]+` re-affirmation. Lives between
# `**Step 4: Re-affirm `FORCE` and `ROUNDS`**` and `## Phase 2`.
extract_step4_revalidation() {
  awk '
    /\*\*Step 4: Re-affirm/                    { in_section = 1; next }
    /^## Phase 2/                              { in_section = 0 }
    !in_section                                { next }
    /^```bash$/                                { infence = 1; next }
    infence && /^```$/                         { infence = 0; print ""; next }
    infence                                    { print }
  ' "$SKILL"
}

# Phase 0c WI 2a.6 cron-prompt construction block (Case 13): the
# `if [[ "$ARGUMENTS" =~ ^(...quoted-head...)`...$ ]]; then ... fi`
# fence under the "Construct `TASK_DESCRIPTION_FOR_CRON`" section. There
# are two ```bash fences in Phase 0c (the QUOTED_HEAD/STRIPPED_REST one
# AND the CRON_PROMPT one); we want the FIRST one in that section.
extract_task_description_for_cron_block() {
  awk '
    /^## Phase 0c/                                { in_section = 1; fence_idx = 0; next }
    /^## Phase 1 — Understand/                    { in_section = 0 }
    !in_section                                   { next }
    /^   ```bash$/                                { fence_idx++; if (fence_idx == 1) infence = 1; next }
    infence && /^   ```$/                         { infence = 0; print ""; next }
    infence                                       { print }
  ' "$SKILL"
}

echo "=== /do — Phase 2a structural and behavioral coverage ==="

# ────────────────────────────────────────────────────────────────────
# Case 1 — argument-hint contains --force and --rounds N (WI 2a.1)
# ────────────────────────────────────────────────────────────────────
if grep -qE '^argument-hint: ".*--force.*"' "$SKILL" \
   && grep -qE '^argument-hint: ".*--rounds N.*"' "$SKILL"; then
  pass "1  argument-hint: --force and --rounds N present"
else
  fail "1  argument-hint: missing --force or --rounds N"
  grep -n '^argument-hint:' "$SKILL" | sed 's/^/    /'
fi

# ────────────────────────────────────────────────────────────────────
# Case 2 — Phase 0a heading + rubric-table present AND ordering guard.
#
# Cron-zombie regression: Phase 0a (triage) MUST appear before Phase 0c
# (cron registration) so a REDIRECT exits before any CronCreate call.
# `grep -nE '^## Phase 0[ac]'` must list Phase 0a's line number first
# (ascending). Also asserts the rubric table is present (`| Signal |
# Verdict |` header).
# ────────────────────────────────────────────────────────────────────
LN_0A=$(grep -nE '^## Phase 0a' "$SKILL" | head -1 | cut -d: -f1)
LN_0C=$(grep -nE '^## Phase 0c' "$SKILL" | head -1 | cut -d: -f1)
RUBRIC_HEADER=$(grep -c '^| Signal | Verdict |' "$SKILL")

if [ -n "$LN_0A" ] && [ -n "$LN_0C" ] \
   && [ "$LN_0A" -lt "$LN_0C" ] \
   && [ "$RUBRIC_HEADER" -ge 1 ]; then
  pass "2  Phase 0a (line $LN_0A) precedes Phase 0c (line $LN_0C); rubric table present (cron-zombie regression guard)"
else
  fail "2  Phase 0a/0c ordering: 0a=$LN_0A 0c=$LN_0C rubric=$RUBRIC_HEADER"
fi

# ────────────────────────────────────────────────────────────────────
# Case 3 — Phase 0b inline-plan + review prose present.
#
# Asserts:
#   - `## Phase 0b` heading
#   - `### /do inline plan` template present
#   - "Fresh-agent plan review" prose present
#   - reviewer-agent prompt template (mentions REVIEWER agent for /do's
#     pre-execution plan review)
# ────────────────────────────────────────────────────────────────────
if grep -qE '^## Phase 0b' "$SKILL" \
   && grep -qE '^### /do inline plan' "$SKILL" \
   && grep -qE 'Fresh-agent plan review' "$SKILL" \
   && grep -qE 'REVIEWER agent for /do' "$SKILL"; then
  pass "3  Phase 0b inline plan + fresh-agent review prose present"
else
  fail "3  Phase 0b: one or more of (heading, inline-plan template, review prose, reviewer prompt) missing"
fi

# ────────────────────────────────────────────────────────────────────
# Case 4 — --force cron-persistence prose present.
#
# A `/do <task> --force every 4h` produces a cron prompt of
# `Run /do <task> --force every 4h now` — every cron fire bypasses
# triage/review. Asserts the prose explicitly documents this.
# ────────────────────────────────────────────────────────────────────
if grep -qE 'Persistence of `--force`' "$SKILL" \
   && grep -qE 'every cron fire bypasses triage and review' "$SKILL"; then
  pass "4  --force cron-persistence prose: 'Persistence of --force' + bypass docs present"
else
  fail "4  --force cron-persistence prose: missing"
fi

# ────────────────────────────────────────────────────────────────────
# Case 5 — Meta-command bypass anchored after meta-command bullet block
# (NOT in the trailing-flag parsing region).
#
# Per Phase 2b spec: `grep -B1 'bypass Phase 0a triage and Phase 0b review'`
# must return one of the meta-command bullet lines OR an empty separator
# (i.e., the "before-context" line is part of the meta-command block,
# not the trailing-flag parsing region).
# ────────────────────────────────────────────────────────────────────
PRECEDING_LINE=$(grep -B1 'bypass Phase 0a triage and Phase 0b review' "$SKILL" | head -1)
# The before-context can be:
#   - a meta-command bullet line (`- \`stop ...\` ...` etc.)
#   - an empty separator (blank line — the section paragraph break)
# What it MUST NOT be: a line in the trailing-flag region
# (e.g. `- \`push\` — recognized at the end`).
if [[ -z "$PRECEDING_LINE" ]] \
   || [[ "$PRECEDING_LINE" =~ ^-[[:space:]]*\`(stop|next|now)[[:space:]] ]]; then
  pass "5  meta-command bypass anchor: preceding-line='$PRECEDING_LINE' (in meta-command block)"
else
  fail "5  meta-command bypass anchor: preceding-line='$PRECEDING_LINE' (NOT in meta-command bullet block)"
fi

# ────────────────────────────────────────────────────────────────────
# Case 6 — VERDICT parser regex documented:
#   - APPROVE bare: `^VERDICT:[[:space:]]+APPROVE[[:space:]]*$`
#   - REVISE/REJECT require `--` + reason:
#     `^VERDICT:[[:space:]]+(REVISE|REJECT)[[:space:]]+--[[:space:]]+(.+)$`
# ────────────────────────────────────────────────────────────────────
if grep -qF '^VERDICT:[[:space:]]+APPROVE[[:space:]]*$' "$SKILL" \
   && grep -qF '^VERDICT:[[:space:]]+(REVISE|REJECT)[[:space:]]+--[[:space:]]+(.+)$' "$SKILL"; then
  pass "6  VERDICT parser regex: APPROVE bare + REVISE/REJECT (-- + reason) documented"
else
  fail "6  VERDICT parser regex: missing one or both regex forms"
fi

# ────────────────────────────────────────────────────────────────────
# Case 7 — --rounds 0 skip-review prose AND stderr WARN string present.
#
# Skip-review semantics: `If $ROUNDS -eq 0` → print to stderr
# `WARN: --rounds 0 skips fresh-agent plan review (legacy opt-in).` and
# skip review entirely.
# ────────────────────────────────────────────────────────────────────
SKIP_DOC=$(grep -c 'Skip when `--rounds 0`' "$SKILL")
WARN_DOC=$(grep -c 'WARN: --rounds 0 skips fresh-agent plan review' "$SKILL")

if [ "$SKIP_DOC" -ge 1 ] && [ "$WARN_DOC" -ge 1 ]; then
  pass "7  --rounds 0: skip prose ($SKIP_DOC) AND stderr WARN string ($WARN_DOC) present"
else
  fail "7  --rounds 0: skip-doc-count=$SKIP_DOC warn-doc-count=$WARN_DOC"
fi

# ────────────────────────────────────────────────────────────────────
# Case 8 — Phase 1.5 Step 2 strips --force and --rounds N from
# TASK_DESCRIPTION (bash plumbing).
#
# Extraction window pinned: extract Phase 1.5 Step 2's COMPLETE
# `TASK_DESCRIPTION=$(echo "$REMAINING" \ ...)` chain (which includes
# pr/worktree/direct strips PLUS WI 2a.4's --force / --rounds N strips).
# Run input `fix tooltip --force --rounds 3 pr` and assert output
# `fix tooltip`.
# ────────────────────────────────────────────────────────────────────
TASKDESC_BLOCK=$(extract_task_description_block)
TASKDESC_SCRIPT="$TEST_TMPDIR/taskdesc.sh"
{
  echo '#!/bin/bash'
  echo 'set -u'
  echo 'REMAINING="$1"'
  echo "$TASKDESC_BLOCK"
  echo 'printf "%s" "$TASK_DESCRIPTION"'
} > "$TASKDESC_SCRIPT"
chmod +x "$TASKDESC_SCRIPT"

GOT_C8=$(bash "$TASKDESC_SCRIPT" "fix tooltip --force --rounds 3 pr" 2>/dev/null)
if [ "$GOT_C8" = "fix tooltip" ]; then
  pass "8  Phase 1.5 Step 2 strip: 'fix tooltip --force --rounds 3 pr' → 'fix tooltip'"
else
  fail "8  Phase 1.5 Step 2 strip: expected='fix tooltip' got='$GOT_C8'"
fi

# ────────────────────────────────────────────────────────────────────
# Case 9 — `--rounds notanumber` → ROUNDS stays at default 1
# (greedy-fallthrough per WI 2a.0). Symmetric to /quickfix Case 45.
#
# Extracts the pre-flight pre-parse fence and runs it against the
# fixture input `fix the bug --rounds in production`. Asserts ROUNDS=1.
# ────────────────────────────────────────────────────────────────────
PREFLIGHT_BLOCK=$(extract_preflight)
PREFLIGHT_SCRIPT="$TEST_TMPDIR/preflight.sh"
{
  echo '#!/bin/bash'
  echo 'set -u'
  echo 'ARGUMENTS="$1"'
  echo "$PREFLIGHT_BLOCK"
  echo 'printf "ROUNDS=%s\n" "$ROUNDS"'
  echo 'printf "FORCE=%s\n" "$FORCE"'
} > "$PREFLIGHT_SCRIPT"
chmod +x "$PREFLIGHT_SCRIPT"

OUT_C9=$(bash "$PREFLIGHT_SCRIPT" "fix the bug --rounds in production" 2>&1)
RC_C9=$?
if [ "$RC_C9" -eq 0 ] \
   && echo "$OUT_C9" | grep -q '^ROUNDS=1$' \
   && echo "$OUT_C9" | grep -q '^FORCE=0$'; then
  pass "9  --rounds notanumber (greedy-fallthrough): ROUNDS stays at 1, no exit 2"
else
  fail "9  --rounds notanumber: rc=$RC_C9 out='$(echo "$OUT_C9" | tr '\n' '|')'"
fi

# ────────────────────────────────────────────────────────────────────
# Case 10 — Phase 0b documents orthogonality with /verify-changes
# (positive grep `pre-review judges PLAN`) AND PR-mode negation prose
# present (positive grep on `PR mode (Path A) handles its own push
# internally and does \*\*not\*\* invoke /verify-changes`). Closes R3.
# ────────────────────────────────────────────────────────────────────
ORTHO_DOC=$(grep -c 'pre-review judges PLAN' "$SKILL")
PR_NEG_DOC=$(grep -cE 'PR mode \(Path A\) handles its own push internally and does \*\*not\*\* invoke /verify-changes' "$SKILL")

if [ "$ORTHO_DOC" -ge 1 ] && [ "$PR_NEG_DOC" -ge 1 ]; then
  pass "10 Phase 0b orthogonality: pre-review-judges-PLAN ($ORTHO_DOC) + PR-mode-negation ($PR_NEG_DOC)"
else
  fail "10 Phase 0b orthogonality: ortho=$ORTHO_DOC pr-neg=$PR_NEG_DOC"
fi

# ────────────────────────────────────────────────────────────────────
# Case 11 — Entry-point unset guard regression: invoking /do with
# `_ZSKILLS_TEST_TRIAGE_VERDICT` (or `_ZSKILLS_TEST_REVIEW_VERDICT`) set
# in the environment but WITHOUT `_ZSKILLS_TEST_HARNESS=1` proceeds
# normally — the env vars are unset by the entry-point guard and ignored.
# Symmetric to /quickfix Case 47(e). Closes the round-2 follow-up
# flagged in known-concerns: the harness-companion test was previously
# only covered for /quickfix.
#
# Approach: extract the pre-flight fence (which contains the unset
# guard), wrap it as a script that echoes the var states AFTER the
# guard runs, then invoke with the seam vars set but harness flag
# absent. Both seam vars must be unset.
# ────────────────────────────────────────────────────────────────────
GUARD_SCRIPT="$TEST_TMPDIR/guard.sh"
{
  echo '#!/bin/bash'
  echo 'set -u'
  echo 'ARGUMENTS="$1"'
  echo "$PREFLIGHT_BLOCK"
  echo 'printf "TRIAGE_VAR_STATE=%s\n" "${_ZSKILLS_TEST_TRIAGE_VERDICT-UNSET}"'
  echo 'printf "REVIEW_VAR_STATE=%s\n" "${_ZSKILLS_TEST_REVIEW_VERDICT-UNSET}"'
} > "$GUARD_SCRIPT"
chmod +x "$GUARD_SCRIPT"

# Set seam vars but NOT harness flag.
GUARD_OUT=$(_ZSKILLS_TEST_TRIAGE_VERDICT="REDIRECT:/draft-plan:bogus" \
            _ZSKILLS_TEST_REVIEW_VERDICT="REJECT: bogus" \
            bash "$GUARD_SCRIPT" "fix typo" 2>&1)
TRIAGE_STATE=$(echo "$GUARD_OUT" | grep '^TRIAGE_VAR_STATE=' | cut -d= -f2)
REVIEW_STATE=$(echo "$GUARD_OUT" | grep '^REVIEW_VAR_STATE=' | cut -d= -f2)

if [ "$TRIAGE_STATE" = "UNSET" ] && [ "$REVIEW_STATE" = "UNSET" ]; then
  pass "11 entry-point unset guard: seam vars cleared when harness flag absent (triage=$TRIAGE_STATE review=$REVIEW_STATE)"
else
  fail "11 entry-point unset guard: triage='$TRIAGE_STATE' review='$REVIEW_STATE' (expected both UNSET)"
fi

# Companion: with harness flag set, vars survive (production-symmetric
# negation: the guard fires ONLY when the flag is absent).
GUARD_OUT2=$(_ZSKILLS_TEST_HARNESS=1 \
             _ZSKILLS_TEST_TRIAGE_VERDICT="PROCEED" \
             _ZSKILLS_TEST_REVIEW_VERDICT="APPROVE" \
             bash "$GUARD_SCRIPT" "fix typo" 2>&1)
T2=$(echo "$GUARD_OUT2" | grep '^TRIAGE_VAR_STATE=' | cut -d= -f2)
R2=$(echo "$GUARD_OUT2" | grep '^REVIEW_VAR_STATE=' | cut -d= -f2)
# Note: not asserted as a separate case; this is a sanity probe to make
# sure the guard isn't unconditionally clearing (would be a different bug).
if [ "$T2" != "PROCEED" ] || [ "$R2" != "APPROVE" ]; then
  echo "    (sanity probe) harness=1 path: triage='$T2' review='$R2' — guard is unconditionally clearing!"
fi

# ────────────────────────────────────────────────────────────────────
# Case 12 — Phase 1.5 re-validation does NOT exit 2 on non-numeric
# `--rounds` (closes R2). Extract WI 2a.4's defensive re-validation
# block (Phase 1.5 Step 4), run with input `fix the bug --rounds in
# production`, assert exit code is NOT 2 AND ROUNDS stays at default 1
# AND no `ERROR:` text on stderr. Symmetric guarantee to WI 2a.0.
# ────────────────────────────────────────────────────────────────────
STEP4_BLOCK=$(extract_step4_revalidation)
STEP4_SCRIPT="$TEST_TMPDIR/step4.sh"
{
  echo '#!/bin/bash'
  echo 'set -u'
  echo 'REMAINING="$1"'
  # Defaults from prior steps; these would be set by Phase 1.5 Step 1
  # in production. The Step 4 block re-affirms FORCE/ROUNDS only.
  echo 'FORCE=${FORCE:-0}'
  echo 'ROUNDS=${ROUNDS:-1}'
  echo "$STEP4_BLOCK"
  echo 'printf "ROUNDS=%s\n" "$ROUNDS"'
  echo 'printf "FORCE=%s\n" "$FORCE"'
} > "$STEP4_SCRIPT"
chmod +x "$STEP4_SCRIPT"

OUT_C12_STDOUT=$(bash "$STEP4_SCRIPT" "fix the bug --rounds in production" 2>"$TEST_TMPDIR/c12.err")
RC_C12=$?
ERR_C12=$(cat "$TEST_TMPDIR/c12.err")

# Acceptance: rc != 2, ROUNDS=1, no `ERROR:` on stderr.
if [ "$RC_C12" -ne 2 ] \
   && echo "$OUT_C12_STDOUT" | grep -q '^ROUNDS=1$' \
   && ! echo "$ERR_C12" | grep -q 'ERROR:'; then
  pass "12 Phase 1.5 re-validation: non-numeric --rounds → rc=$RC_C12 (not 2), ROUNDS=1, no ERROR on stderr"
else
  fail "12 Phase 1.5 re-validation: rc=$RC_C12 stdout='$(echo "$OUT_C12_STDOUT" | tr '\n' '|')' stderr='$ERR_C12'"
fi

# ────────────────────────────────────────────────────────────────────
# Case 13 — Quoted-description protection (closes DA3).
#
# Run TASK_DESCRIPTION_FOR_CRON construction (extract block from
# WI 2a.6 / Phase 0c step 3) with input
# `"fix --force usage in scripts" --force every 4h`. Assert output
# equals `"fix --force usage in scripts"` — the quoted-segment
# `--force` substring is preserved; the trailing flag `--force` is
# stripped.
# ────────────────────────────────────────────────────────────────────
TDFC_BLOCK=$(extract_task_description_for_cron_block)
TDFC_SCRIPT="$TEST_TMPDIR/tdfc.sh"
{
  echo '#!/bin/bash'
  echo 'set -u'
  echo 'ARGUMENTS="$1"'
  echo "$TDFC_BLOCK"
  echo 'printf "%s" "$TASK_DESCRIPTION_FOR_CRON"'
} > "$TDFC_SCRIPT"
chmod +x "$TDFC_SCRIPT"

GOT_C13=$(bash "$TDFC_SCRIPT" '"fix --force usage in scripts" --force every 4h' 2>/dev/null)
EXPECTED_C13='"fix --force usage in scripts"'
if [ "$GOT_C13" = "$EXPECTED_C13" ]; then
  pass "13 quoted-description protection: trailing --force stripped, in-quotes --force preserved"
else
  fail "13 quoted-description protection: expected='$EXPECTED_C13' got='$GOT_C13'"
fi

# ────────────────────────────────────────────────────────────────────
# Suite summary
# ────────────────────────────────────────────────────────────────────
TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo ""
echo "=============================="
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '\033[32mResults: %d passed, %d failed, 0 skipped (of %d)\033[0m\n' \
    "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed, 0 skipped (of %d)\033[0m\n' \
    "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit 1
fi
