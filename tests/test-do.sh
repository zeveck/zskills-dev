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
#   14. Phase 1.5 Step 2 strips positional `auto` from TASK_DESCRIPTION (#297)
#   15. Pre-flight pre-parse sets AUTO_FLAG=1 on positional `auto` (#297)
#   16. modes/pr.md conditionally injects --auto into LAND_ARGS when AUTO_FLAG=1 (#297)
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
# Case 14 — Phase 1.5 Step 2 strips positional `auto` from
# TASK_DESCRIPTION (issue #297; symmetric to /quickfix's `auto` strip).
#
# Run input `fix tooltip auto pr` and assert output `fix tooltip` —
# both `auto` and `pr` are stripped to leave the bare description.
# Also assert case-insensitivity (`AUTO` → stripped).
# ────────────────────────────────────────────────────────────────────
GOT_C14a=$(bash "$TASKDESC_SCRIPT" "fix tooltip auto pr" 2>/dev/null)
GOT_C14b=$(bash "$TASKDESC_SCRIPT" "fix tooltip AUTO pr" 2>/dev/null)
GOT_C14c=$(bash "$TASKDESC_SCRIPT" "auto fix tooltip pr" 2>/dev/null)
if [ "$GOT_C14a" = "fix tooltip" ] \
   && [ "$GOT_C14b" = "fix tooltip" ] \
   && [ "$GOT_C14c" = "fix tooltip" ]; then
  pass "14 Phase 1.5 Step 2 strip: positional 'auto' (case-insensitive, any position) removed from TASK_DESCRIPTION (#297)"
else
  fail "14 'auto' strip: trailing='$GOT_C14a' upper='$GOT_C14b' leading='$GOT_C14c' (expected all 'fix tooltip')"
fi

# ────────────────────────────────────────────────────────────────────
# Case 15 — Pre-flight pre-parse sets AUTO_FLAG=1 when positional
# `auto` is in $ARGUMENTS (issue #297). Symmetric to /quickfix's
# WI 1.2 AUTO_FLAG. Run pre-flight against `fix tooltip auto pr`
# and assert AUTO_FLAG=1. Also negative case: no `auto` → AUTO_FLAG=0.
# ────────────────────────────────────────────────────────────────────
AUTOFLAG_SCRIPT="$TEST_TMPDIR/autoflag.sh"
{
  echo '#!/bin/bash'
  echo 'set -u'
  echo 'ARGUMENTS="$1"'
  echo "$PREFLIGHT_BLOCK"
  echo 'printf "AUTO_FLAG=%s\n" "$AUTO_FLAG"'
} > "$AUTOFLAG_SCRIPT"
chmod +x "$AUTOFLAG_SCRIPT"

OUT_C15a=$(bash "$AUTOFLAG_SCRIPT" "fix tooltip auto pr" 2>/dev/null)
OUT_C15b=$(bash "$AUTOFLAG_SCRIPT" "fix tooltip pr" 2>/dev/null)
OUT_C15c=$(bash "$AUTOFLAG_SCRIPT" "fix tooltip AUTO pr" 2>/dev/null)
if echo "$OUT_C15a" | grep -q '^AUTO_FLAG=1$' \
   && echo "$OUT_C15b" | grep -q '^AUTO_FLAG=0$' \
   && echo "$OUT_C15c" | grep -q '^AUTO_FLAG=1$'; then
  pass "15 Pre-flight pre-parse: AUTO_FLAG=1 with 'auto'/'AUTO', AUTO_FLAG=0 without (#297)"
else
  fail "15 AUTO_FLAG: with-auto='$OUT_C15a' without='$OUT_C15b' upper='$OUT_C15c'"
fi

# ────────────────────────────────────────────────────────────────────
# Case 16 — modes/pr.md conditionally injects --auto into LAND_ARGS
# when AUTO_FLAG=1 (issue #297; mirrors /quickfix's
# `[ "${AUTO_FLAG:-0}" = "1" ] && LAND_ARGS="$LAND_ARGS --auto"`).
#
# Static-grep against skills/do/modes/pr.md for the conditional. This
# is a source-level assertion — the bash block is too tightly coupled
# to /land-pr's surrounding context to run in isolation.
# ────────────────────────────────────────────────────────────────────
PR_MODE="$REPO_ROOT/skills/do/modes/pr.md"
if grep -qE '\[\s*"\$\{AUTO_FLAG:-0\}"\s*=\s*"1"\s*\]\s*&&\s*LAND_ARGS="\$LAND_ARGS --auto"' "$PR_MODE"; then
  pass "16 modes/pr.md: conditional --auto injection present (AUTO_FLAG-gated; #297)"
else
  fail "16 modes/pr.md: AUTO_FLAG-gated --auto injection missing"
  grep -nE "AUTO_FLAG|--auto" "$PR_MODE" | sed 's/^/    /' | head -10
fi

# Companion: ensure the stale "No --auto" comment is removed and the
# "(none for /do pr)" parenthetical at the CI-status break is gone.
if grep -qE 'No `?--auto`?.*auto-merge stays OFF for `?/do pr`?' "$PR_MODE" \
   || grep -qE 'none for /do pr' "$PR_MODE"; then
  fail "16b modes/pr.md: stale 'No --auto' / 'none for /do pr' prose still present"
  grep -nE 'No `?--auto`?|none for /do pr' "$PR_MODE" | sed 's/^/    /'
else
  pass "16b modes/pr.md: stale 'No --auto' / 'none for /do pr' prose removed"
fi

# ────────────────────────────────────────────────────────────────────
# Case 17 — Phase 4 (Land) is gated on AUTO_FLAG=1 for direct + worktree
# modes specifically (#376). Phase 4 was symmetric with the positional
# `auto` consolidation in PR #354 (commit 42ef042), but had no positive
# test — a refactor breaking the gate (wrong variable, wrong condition,
# wrong scope) would slip past Cases 15 + 16.
#
# Three assertions against the Phase 4 block (heading line + body
# between `## Phase 4` and `## Phase 5`):
#   17a. Heading scopes the gate to "Path C/B only" (direct + worktree),
#        NOT PR mode (Path A).
#   17b. Body explicitly references AUTO_FLAG=1 as the gate condition.
#   17c. Body acknowledges PR mode is out of scope ("Not applicable to
#        PR mode") so a future refactor can't quietly extend Phase 4
#        to Path A without flipping this assertion.
# ────────────────────────────────────────────────────────────────────
extract_phase4_block() {
  awk '
    /^## Phase 4/         { in_section = 1; print; next }
    /^## Phase 5/         { in_section = 0 }
    in_section            { print }
  ' "$SKILL"
}
PHASE4_BLOCK=$(extract_phase4_block)
PHASE4_HEADING=$(printf '%s\n' "$PHASE4_BLOCK" | head -1)

C17a=0; C17b=0; C17c=0
echo "$PHASE4_HEADING" | grep -qE 'Path C/B only|Path B/C only' && C17a=1
printf '%s\n' "$PHASE4_BLOCK" | grep -qE 'AUTO_FLAG[[:space:]]*=[[:space:]]*"?1"?' && C17b=1
printf '%s\n' "$PHASE4_BLOCK" | grep -qE 'Not applicable to PR mode' && C17c=1

if [ "$C17a" = "1" ] && [ "$C17b" = "1" ] && [ "$C17c" = "1" ]; then
  pass "17 Phase 4 gate: heading scopes to Path C/B (direct+worktree), body references AUTO_FLAG=1, PR mode explicitly excluded (#376)"
else
  fail "17 Phase 4 gate: heading-path-scope=$C17a auto_flag_ref=$C17b pr_mode_excluded=$C17c"
  echo "    Phase 4 heading: $PHASE4_HEADING"
  printf '%s\n' "$PHASE4_BLOCK" | grep -nE 'AUTO_FLAG|Path [ABC]|Not applicable' | sed 's/^/    /'
fi

# ────────────────────────────────────────────────────────────────────
# Case 18 — Pre-flight ISSUE_NUM regex is anchored to start-of-description
# (with optional close-keyword + optional leading double-quote, case-
# insensitive). A `#NNN` literal appearing later in prose — quoted
# example, line ref, follow-up "see also #N" — must NOT capture an
# issue number, otherwise the mode file's claim-issue.sh acquire claims
# an unrelated issue.
#
# Replicates the regex from skills/do/SKILL.md Pre-flight and exercises
# it directly. The regex source-of-truth is the SKILL.md; this test
# re-implements it as a behavioral fixture so a future edit that breaks
# one of these cases fails closed.
# ────────────────────────────────────────────────────────────────────
# do_parse_issue_nums replicates the SKILL.md parser. Sets the
# ISSUE_NUMS array (and back-compat ISSUE_NUM = first) for the caller.
# Strong separators (`/`, `+`, `&`) accept bare `#N`; weak separators
# (`,`, `;`, ` and `, ` or `) require a close-keyword before `#N`.
do_parse_issue_nums() {
  local input="$1"
  ISSUE_NUMS=()
  local _KW='([cC][lL][oO][sS][eE][sSdD]?|[fF][iI][xX]([eE][sSdD])?|[rR][eE][sS][oO][lL][vV][eE][sSdD]?)'
  # #920: optional `issue[s]?:?` filler tolerated between kw and `#N`.
  local _FILLER='([iI][sS][sS][uU][eE][sS]?:?[[:space:]]+)?'
  if [[ "$input" =~ ^[[:space:]]*\"?${_KW}[[:space:]]+${_FILLER}#([0-9]+) ]]; then
    ISSUE_NUMS+=("${BASH_REMATCH[4]}")
  elif [[ "$input" =~ ^[[:space:]]*\"?#([0-9]+) ]]; then
    ISSUE_NUMS+=("${BASH_REMATCH[1]}")
  fi
  # Strong separators: bare #N OK; kw+filler optional.
  local _REM="$input"
  while [[ "$_REM" =~ [[:space:]]*[/+\&][[:space:]]*(${_KW}[[:space:]]+${_FILLER})?#([0-9]+) ]]; do
    ISSUE_NUMS+=("${BASH_REMATCH[5]}")
    _REM="${_REM#*"${BASH_REMATCH[0]}"}"
  done
  # Weak separators: close-keyword required; filler optional.
  _REM="$input"
  while [[ "$_REM" =~ ([[:space:]]*[,\;][[:space:]]*|[[:space:]](and|or|AND|OR|And|Or)[[:space:]]+)${_KW}[[:space:]]+${_FILLER}#([0-9]+) ]]; do
    ISSUE_NUMS+=("${BASH_REMATCH[6]}")
    _REM="${_REM#*"${BASH_REMATCH[0]}"}"
  done
  declare -A _SEEN=()
  local _UNIQUE=()
  local _n
  for _n in "${ISSUE_NUMS[@]:-}"; do
    [ -z "$_n" ] && continue
    if [ -z "${_SEEN[$_n]:-}" ]; then _UNIQUE+=("$_n"); _SEEN[$_n]=1; fi
  done
  ISSUE_NUMS=("${_UNIQUE[@]}")
  ISSUE_NUM="${ISSUE_NUMS[0]:-}"
}

# test_issue_num_do — back-compat scalar (= ISSUE_NUMS[0]) check.
test_issue_num_do() {
  local input="$1"
  local expected="$2"
  local label="$3"
  do_parse_issue_nums "$input"
  if [ "${ISSUE_NUM:-}" = "$expected" ]; then
    pass "18 ISSUE_NUM: $label (got '${ISSUE_NUM:-}')"
  else
    fail "18 ISSUE_NUM: $label (expected '$expected', got '${ISSUE_NUM:-}')"
  fi
}

# test_issue_nums_do — multi-issue array check. `expected_csv` is the
# comma-joined expected array (e.g., "832,833"); empty string asserts the
# array is empty.
test_issue_nums_do() {
  local input="$1"
  local expected_csv="$2"
  local label="$3"
  do_parse_issue_nums "$input"
  local got_csv=""
  if [ "${#ISSUE_NUMS[@]}" -gt 0 ]; then
    got_csv=$(IFS=','; echo "${ISSUE_NUMS[*]}")
  fi
  if [ "$got_csv" = "$expected_csv" ]; then
    pass "18m ISSUE_NUMS: $label (got '$got_csv')"
  else
    fail "18m ISSUE_NUMS: $label (expected '$expected_csv', got '$got_csv')"
  fi
}

# Positive — should capture issue number(s)
test_issue_num_do "Fix #853 — auto-route completed plans" "853" "Fix #N at start (capital F)"
test_issue_num_do "fix #853 — lowercase" "853" "fix #N at start (lowercase)"
test_issue_num_do "Fixes #853 typo" "853" "Fixes #N at start"
test_issue_num_do "Fixed #853" "853" "Fixed #N at start"
test_issue_num_do "Closes #853 follow-up work" "853" "Closes #N at start"
test_issue_num_do "closed #853" "853" "closed #N at start"
test_issue_num_do "Resolves #853" "853" "Resolves #N at start"
test_issue_num_do "#853 work item" "853" "bare #N at start"
test_issue_num_do "   Fix #853 leading whitespace" "853" "leading whitespace + Fix #N"
test_issue_num_do "\"Fix #853 quoted-head\"" "853" "leading quote + Fix #N (quoted-head carve-out)"
test_issue_num_do "\"#853 bare-quoted\"" "853" "leading quote + bare #N"

# Negative — should NOT capture
test_issue_num_do "Remove the example 'fix #142' from prose" "" "fix #N in mid-prose quote → no capture"
test_issue_num_do "Update file X, see also #853 for context" "" "#N after see-also → no capture"
test_issue_num_do "Edit collect.py:#142 line reference" "" "#N as path/line reference → no capture"
test_issue_num_do "Some text fix #142 mid prose" "" "fix #N in middle of prose → no capture"
test_issue_num_do "Just a regular description" "" "no # at all → no capture"
test_issue_num_do "Description mentioning #N letter" "" "#N where N is a letter → no capture"
test_issue_num_do "address #853 work" "" "non-recognized keyword (address) → no capture"
test_issue_num_do "work on #853" "" "non-recognized verb (work) → no capture"

# ────────────────────────────────────────────────────────────────────
# Case 18i — #920: optional `issue[s]?:?` filler token tolerated between
# the close-keyword and `#N`. Natural phrasings ("Fix issue #N", "fixes
# issues #N", "Resolves issue: #N") now capture. The filler MUST be
# adjacent to `#N` — a word between `issue` and `#N` breaks adjacency
# and no capture occurs (preserves #863's strong-vs-weak separator
# discipline).
# ────────────────────────────────────────────────────────────────────
# Positive — kw + filler + #N captures
test_issue_num_do "Fix issue #906: bring /work-on-plans into spec" "906" "Fix issue #N (live #920 regression case)"
test_issue_num_do "fixes issue #906" "906" "fixes issue #N"
test_issue_num_do "Fixed issue #906" "906" "Fixed issue #N"
test_issue_num_do "Closes issue #906" "906" "Closes issue #N"
test_issue_num_do "closed issue #906" "906" "closed issue #N"
test_issue_num_do "Resolves issue #906" "906" "Resolves issue #N"
test_issue_num_do "fixes issues #906" "906" "fixes issues #N (plural)"
test_issue_num_do "Closes issues #906" "906" "Closes issues #N (plural)"
test_issue_num_do "Resolves issue: #906" "906" "Resolves issue: #N (colon variant)"
test_issue_num_do "Fix issue #906 the bug" "906" "Fix issue #N followed by prose"
test_issue_num_do "\"Fix issue #906 quoted-head\"" "906" "leading quote + Fix issue #N (quoted-head carve-out)"
# Negative — filler word but NOT adjacent to #N → no capture
test_issue_num_do "Fix issue ticketing for #906" "" "word between 'issue' and #N → no capture (adjacency required)"
test_issue_num_do "Fix issue with #906" "" "'with' between 'issue' and #N → no capture"
# Existing forms still work — keyword without filler is unchanged
test_issue_num_do "Closes #906" "906" "Closes #N (no filler) still works"

# ────────────────────────────────────────────────────────────────────
# Case 18m — Multi-issue parser (#863). Description references multiple
# `#N` issues separated by /, ,, ;, +, &, or " and "/" or " — all
# captured into ISSUE_NUMS array; back-compat ISSUE_NUM stays as first.
# ────────────────────────────────────────────────────────────────────
test_issue_nums_do "Closes #832 / Closes #833"           "832,833"     "slash-separated double Closes (the canonical multi-issue pattern)"
test_issue_nums_do "fix #832 + #833"                     "832,833"     "plus-separated bare #N (strong sep)"
test_issue_nums_do "Closes #832 & #833"                  "832,833"     "ampersand-separated bare #N (strong sep)"
test_issue_nums_do "fix #832 and fix #833"               "832,833"     "and-separated keyword + #N (weak sep + kw OK)"
test_issue_nums_do "Closes #832; Resolves #833"          "832,833"     "semicolon-separated different keywords (weak sep + kw OK)"
test_issue_nums_do "Fix #832, Closes #833"               "832,833"     "comma-separated keyword + #N (weak sep + kw OK)"
test_issue_nums_do "Closes #832 / Closes #833 + #834"    "832,833,834" "triple-fanout slash + plus (mixed strong seps)"
test_issue_nums_do "Fix #853"                            "853"         "single-issue case still works"
test_issue_nums_do "Just a regular description"          ""            "zero-issue case → empty array"
# Weak separators without a close-keyword don't fan out (over-capture guard):
test_issue_nums_do "Closes #832, see also #999"          "832"         "see-also after comma → only #832 (weak sep, no kw before #999)"
test_issue_nums_do "Closes #832, #833"                   "832"         "bare #N after comma (weak sep) → only #832"
test_issue_nums_do "fix #832 and #833"                   "832"         "bare #N after 'and' (weak sep) → only #832"
test_issue_nums_do "fix #832 and fix #832"               "832"         "dedupe: duplicate #N captured once"
# #920: filler token across separator passes
test_issue_nums_do "Closes issue #832 / Closes issue #833"        "832,833"     "slash-separated double Closes-issue (kw+filler, strong sep)"
test_issue_nums_do "Fixes issues #832 + #833"                     "832,833"     "Fixes issues (plural) + bare #N (strong sep, kw absent on RHS)"
test_issue_nums_do "Fix issue #832 and Closes issue #833"         "832,833"     "and-separated kw+filler on both sides (weak sep)"
test_issue_nums_do "Fix issue #832, Closes #833"                  "832,833"     "comma-separated: kw+filler then bare-kw (weak sep)"
# #920 negative — filler-without-adjacency in weak-sep position
test_issue_nums_do "Fix issue #832, see also issue #999"          "832"         "see-also after comma → only #832 even though 'issue' near #999 (no kw before #999)"
test_issue_nums_do "fixes issues #906 and #907"                   "906"         "plural 'issues' in leading does NOT loosen weak-sep guard (no kw before #907)"

# ────────────────────────────────────────────────────────────────────
# Case 18w — Unclaimed-reference WARNING (#907). When the description
# carries a `#N` token that the claim-position rules did NOT capture into
# ISSUE_NUMS, /do warns (non-fatal) that no claim was acquired for it —
# the footgun that let `/do Build … for #877` run unclaimed and duplicate
# a parallel /fix-issues sprint (closed PR #888). Replicates the SKILL.md
# warning loop (source-of-truth is SKILL.md; anchored by 18w-src below).
# ────────────────────────────────────────────────────────────────────
# do_warn_unclaimed echoes "WARN #N" per unclaimed reference (the real
# skill writes the full sentence to stderr). Assumes do_parse_issue_nums
# already populated ISSUE_NUMS.
do_warn_unclaimed() {
  local input="$1" _REM="$1" _REF _CLAIMED _n out=""
  while [[ "$_REM" =~ \#([0-9]+) ]]; do
    _REF="${BASH_REMATCH[1]}"
    _REM="${_REM#*"${BASH_REMATCH[0]}"}"
    _CLAIMED=0
    for _n in "${ISSUE_NUMS[@]:-}"; do
      [ "$_n" = "$_REF" ] && { _CLAIMED=1; break; }
    done
    [ "$_CLAIMED" -eq 0 ] && out+="WARN #$_REF"$'\n'
  done
  printf '%s' "$out"
}
test_do_warn() {
  local input="$1" expected_csv="$2" label="$3"
  do_parse_issue_nums "$input"
  local got_csv
  got_csv=$(do_warn_unclaimed "$input" | grep -oE '#[0-9]+' | tr -d '#' | paste -sd, -)
  if [ "$got_csv" = "$expected_csv" ]; then
    pass "18w warn: $label (got '${got_csv:-none}')"
  else
    fail "18w warn: $label (expected '$expected_csv', got '$got_csv')"
  fi
}
test_do_warn "Build the guard for #877"        "877" "bare mid-prose #N → WARN (the #888 footgun)"
test_do_warn "Fix #853 — auto-route"           ""    "claim-positioned #N → NO warn"
test_do_warn "Closes #832 / Closes #833"       ""    "both claimed (multi) → NO warn"
test_do_warn "Closes #832, see also #999"      "999" "claimed #832 + unclaimed #999 → warn only #999"
test_do_warn "Just a regular description"      ""    "no #N → NO warn"
test_do_warn "Edit collect.py:#142 line ref"   "142" "stray #N → WARN (accepted non-fatal false-positive)"
# 18w-src — anchor the replication to the SKILL.md source so a future edit
# that removes the warning fails closed.
if grep -qF 'is not in claim position — NO claim was acquired' "$SKILL"; then
  pass "18w-src SKILL.md carries the unclaimed-reference WARN (#907)"
else
  fail "18w-src SKILL.md missing the unclaimed-reference WARN (#907)"
fi

# ────────────────────────────────────────────────────────────────────
# Case 19 — Phase 0a triage rubric NO LONGER contains the
# "References a GitHub issue number → /fix-issues" REDIRECT row.
# After PR 825 wired ISSUE_NUM + claim-issue.sh into the mode files,
# the redirect made the claim machinery unreachable on the default
# path. The row, its worked example, the per-target message template
# row, and the test-stub-verdict entry are all expected to be absent.
# ────────────────────────────────────────────────────────────────────
if grep -qE 'References a GitHub issue number.*REDIRECT.*/fix-issues' "$SKILL"; then
  fail "19a Phase 0a rubric still contains the issue-number REDIRECT row"
else
  pass "19a Phase 0a rubric: issue-number REDIRECT row removed"
fi
if grep -qE '/do fix #142.*REDIRECT.*/fix-issues' "$SKILL"; then
  fail "19b Worked-example row '/do fix #142 → REDIRECT → /fix-issues' still present"
else
  pass "19b Worked-example row removed"
fi
if grep -qE '^\| `/fix-issues` \| `Triage: redirecting to /fix-issues' "$SKILL"; then
  fail "19c Per-target redirect-message-template row for /fix-issues still present"
else
  pass "19c /fix-issues message-template row removed"
fi
if grep -qE 'REDIRECT:/fix-issues:reason' "$SKILL"; then
  fail "19d Recognized test-stub verdict list still includes REDIRECT:/fix-issues:reason"
else
  pass "19d Test-stub verdict list pruned"
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
