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
# Assertion 6: cap-check defer-all gate runs BEFORE the sprint
# worktree gate (issue #329 follow-up — co-located bugs from #320).
# If the cap-check ran AFTER the worktree gate, the defer-path's
# `cat >> SPRINT_REPORT.md` would strand in a worktree that never
# ships (Phase 6's sprint-level /land-pr is past the `exit 0`).
# ─────────────────────────────────────────────────────────────────
echo ""
echo "=== fix-issues cap-check ordering + predicate (issue #329 follow-up) ==="

CAP_DEFER_LINE=$(grep -n '^### Live worktree count check (defer-all gate)' "$FI_SKILL" | head -1 | cut -d: -f1)
CAP_PARTIAL_LINE=$(grep -n '^### Live worktree count check (partial-dispatch trim)' "$FI_SKILL" | head -1 | cut -d: -f1)
if [ -z "$CAP_DEFER_LINE" ]; then
  fail "fix-issues: '### Live worktree count check (defer-all gate)' missing (cap-check must run before worktree gate)"
elif [ -z "$SPRINT_GATE_LINE" ]; then
  fail "fix-issues: '### Sprint worktree gate' missing (cannot verify ordering)"
elif [ "$CAP_DEFER_LINE" -ge "$SPRINT_GATE_LINE" ]; then
  fail "fix-issues: defer-all gate at line $CAP_DEFER_LINE must precede sprint worktree gate at line $SPRINT_GATE_LINE (defer-path would strand SPRINT_REPORT.md write otherwise)"
else
  pass "fix-issues: defer-all gate (line $CAP_DEFER_LINE) precedes sprint worktree gate (line $SPRINT_GATE_LINE)"
fi

if [ -z "$CAP_PARTIAL_LINE" ]; then
  fail "fix-issues: '### Live worktree count check (partial-dispatch trim)' missing (partial-batch trim needs its own block in Phase 3)"
elif [ -z "$SPRINT_GATE_LINE" ]; then
  : # already failed above
elif [ "$CAP_PARTIAL_LINE" -le "$SPRINT_GATE_LINE" ]; then
  fail "fix-issues: partial-dispatch trim at line $CAP_PARTIAL_LINE must FOLLOW sprint worktree gate at line $SPRINT_GATE_LINE (it needs TO_DISPATCH from Phase 2)"
else
  pass "fix-issues: partial-dispatch trim (line $CAP_PARTIAL_LINE) follows sprint worktree gate (line $SPRINT_GATE_LINE)"
fi

# ─────────────────────────────────────────────────────────────────
# Assertion 7: behavioural — the cap-check predicate must SKIP
# worktrees whose `.landed` marker reads `status: landed`. We
# extract the predicate code block from the SKILL.md, build a
# fake `git worktree list --porcelain` fixture with three entries
# (one landed, one un-landed, one not-fix-issue), eval the
# predicate against it, and assert LIVE_COUNT == 1.
#
# This locks the EXACT predicate behaviour, not just structural
# presence — the reviewer-flagged gap from the bug report.
# ─────────────────────────────────────────────────────────────────
echo ""
echo "=== predicate behaviour: skip .landed status: landed ==="

# Extract the awk/while predicate block from the SKILL.md (defer-all
# gate). Pull the lines between `LIVE_COUNT=$(` and the matching `)`.
PRED_START=$(awk '/^### Live worktree count check \(defer-all gate\)/{found=1} found && /^LIVE_COUNT=\$\($/{print NR; exit}' "$FI_SKILL")
if [ -z "$PRED_START" ]; then
  fail "could not locate LIVE_COUNT=( in defer-all gate (cannot run predicate behaviour test)"
else
  # Capture lines from PRED_START through the next standalone `)` line.
  PRED_END=$(awk -v start="$PRED_START" 'NR>=start && /^\)$/{print NR; exit}' "$FI_SKILL")
  if [ -z "$PRED_END" ]; then
    fail "could not locate closing ) of LIVE_COUNT predicate"
  else
    PRED_BODY=$(sed -n "${PRED_START},${PRED_END}p" "$FI_SKILL")

    # Build a temp dir with three fake worktrees:
    #   wt-landed   — fix-issue-1, .landed says `status: landed` (SKIP)
    #   wt-active   — fix-issue-2, no .landed                    (COUNT)
    #   wt-other    — feature/foo, not a fix branch              (SKIP)
    TMP_PRED=$(mktemp -d /tmp/cap-predicate-test.XXXXXX)
    trap 'rm -rf "$TMP_PRED"' EXIT

    mkdir -p "$TMP_PRED/wt-landed" "$TMP_PRED/wt-active" "$TMP_PRED/wt-other"
    printf 'status: landed\ndate: 2026-05-17\n' > "$TMP_PRED/wt-landed/.landed"
    # wt-active has no .landed file
    # wt-other has no .landed file

    # Stub `git worktree list --porcelain` to print our fixture.
    cat > "$TMP_PRED/git" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "worktree" ] && [ "\$2" = "list" ] && [ "\$3" = "--porcelain" ]; then
  cat <<PORC
worktree $TMP_PRED/wt-landed
branch refs/heads/fix/issue-1

worktree $TMP_PRED/wt-active
branch refs/heads/fix-issue-2

worktree $TMP_PRED/wt-other
branch refs/heads/feature/foo

PORC
  exit 0
fi
exec /usr/bin/git "\$@"
EOF
    chmod +x "$TMP_PRED/git"

    # Run the predicate with our stub git on PATH.
    ACTUAL=$(PATH="$TMP_PRED:$PATH" bash -c "$PRED_BODY"$'\necho "$LIVE_COUNT"' 2>&1 | tail -1)

    if [ "$ACTUAL" = "1" ]; then
      pass "predicate excludes .landed status: landed (LIVE_COUNT=1 from fixture: 1 landed + 1 active + 1 non-fix)"
    else
      fail "predicate behaviour wrong: expected LIVE_COUNT=1, got '$ACTUAL' (fixture: 1 landed fix-issue + 1 active fix-issue + 1 non-fix branch)"
    fi
  fi
fi

# ─────────────────────────────────────────────────────────────────
# Assertion 8: defer-all gate does NOT `cat >> SPRINT_REPORT.md`.
# The strand bug was: defer-all wrote audit content into the
# sprint-level worktree's SPRINT_REPORT.md, then `exit 0` skipped
# Phase 6's /land-pr. Even after moving the gate earlier (so no
# worktree exists yet), keep the predicate negative — any future
# refactor that re-introduces a `cat >>` here re-opens the strand
# if someone moves the gate back.
# ─────────────────────────────────────────────────────────────────
echo ""
echo "=== defer-all gate does not append to SPRINT_REPORT.md ==="

# Slice from "### Live worktree count check (defer-all gate)" up to
# the next "### " heading.
DEFER_BLOCK=$(awk '
  /^### Live worktree count check \(defer-all gate\)/{capture=1; next}
  capture && /^### /{exit}
  capture {print}
' "$FI_SKILL")

# Match an actual shell heredoc: `cat >> "...SPRINT_REPORT.md" <<TAG`,
# not prose commentary like `# No 'cat >> SPRINT_REPORT.md' here`. The
# leading `# ` in a code-comment line is the disambiguator.
if echo "$DEFER_BLOCK" | grep -E '^[[:space:]]*cat[[:space:]]+>>.*SPRINT_REPORT\.md.*<<' >/dev/null; then
  fail "defer-all gate contains 'cat >> ...SPRINT_REPORT.md <<TAG' heredoc — re-opens the strand bug from #329"
else
  pass "defer-all gate has no 'cat >> SPRINT_REPORT.md <<' heredoc (strand bug from #329 stays closed)"
fi

# Same check for the partial-dispatch trim — kept symmetric per the
# bug report's lean: defer events shouldn't go in SPRINT_REPORT.md.
PARTIAL_BLOCK=$(awk '
  /^### Live worktree count check \(partial-dispatch trim\)/{capture=1; next}
  capture && /^### /{exit}
  capture && /^## /{exit}
  capture {print}
' "$FI_SKILL")

if echo "$PARTIAL_BLOCK" | grep -E '^[[:space:]]*cat[[:space:]]+>>.*SPRINT_REPORT\.md.*<<' >/dev/null; then
  fail "partial-dispatch trim contains 'cat >> ...SPRINT_REPORT.md <<TAG' heredoc — should stay stderr-only for symmetry with defer-all"
else
  pass "partial-dispatch trim has no 'cat >> SPRINT_REPORT.md <<' heredoc (symmetric with defer-all)"
fi

# ─────────────────────────────────────────────────────────────────
# Assertion 9: no-actionable arm does NOT `cat >> SPRINT_REPORT.md`.
# Sibling strand bug to the defer-all arm (Assertion 8): the
# no-actionable branch under `### If no actionable issues found`
# previously wrote a `## Sprint — ... [UNFINALIZED]` section to
# SPRINT_REPORT.md and `exit 0`. After PR #329's sprint worktree
# gate, that write strands inside the sprint-level worktree and
# never ships (Phase 6's sprint-level /land-pr is past the exit).
# Pin the predicate negative so a future refactor cannot re-open
# the strand. Also pins the "no nag counter" decision: any
# `consecutive` / `empty run` references in the block would
# indicate the dropped nag mechanism crept back in.
# ─────────────────────────────────────────────────────────────────
echo ""
echo "=== no-actionable arm does not append to SPRINT_REPORT.md (and no nag counter) ==="

NO_ACT_BLOCK=$(awk '
  /^### If no actionable issues found/{capture=1; next}
  capture && /^### /{exit}
  capture && /^## /{exit}
  capture {print}
' "$FI_SKILL")

if echo "$NO_ACT_BLOCK" | grep -E '^[[:space:]]*cat[[:space:]]+>>.*SPRINT_REPORT\.md.*<<' >/dev/null; then
  fail "no-actionable arm contains 'cat >> ...SPRINT_REPORT.md <<TAG' heredoc — re-opens the strand bug sibling to #331"
else
  pass "no-actionable arm has no 'cat >> SPRINT_REPORT.md <<' heredoc (strand bug sibling to #331 stays closed)"
fi

if echo "$NO_ACT_BLOCK" | grep -iE 'consecutive|empty run' >/dev/null; then
  fail "no-actionable arm contains 'consecutive' / 'empty run' — the dropped 3-empty-runs nag mechanism crept back in"
else
  pass "no-actionable arm has no nag counter / 'consecutive empty runs' logic (per-user-judgment: commit noise)"
fi

# ─────────────────────────────────────────────────────────────────
# Assertion 10: no-actionable arm handles the sprint worktree the
# Phase 1 gate created. Two branches, both ending in exit 0:
#   • SHIP — dirty tree (sync wrote tracker updates): commit +
#     dispatch sprint-level /land-pr (mirror of the Phase 6
#     sprint-level land — see Assertion 5).
#   • CLEANUP — clean tree: `git worktree remove --force "$WT_PATH"`
#     so /tmp does not accumulate empty worktrees across exhausted-
#     queue cron fires.
# Without BOTH paths, either sync's discoveries strand (no ship) or
# empty worktrees pile up (no cleanup). Pin both presence + the
# trailing exit 0.
# ─────────────────────────────────────────────────────────────────
echo ""
echo "=== no-actionable arm ships sync OR cleans worktree (#341 follow-up) ==="

# CLEANUP path — must call git worktree remove on $WT_PATH.
if echo "$NO_ACT_BLOCK" | grep -E 'git worktree remove .*"\$WT_PATH"' >/dev/null; then
  pass "no-actionable arm has 'git worktree remove ... \"\$WT_PATH\"' cleanup path"
else
  fail "no-actionable arm missing 'git worktree remove ... \"\$WT_PATH\"' — empty worktrees will accumulate in /tmp"
fi

# SHIP path — must dispatch /land-pr (mirror Assertion 5's check
# shape: skill: "land-pr"). Pin the tracking-id namespace so the
# Phase 6 sprint-report land's SPRINT_LAND_ID does not collide.
if echo "$NO_ACT_BLOCK" | grep -E 'Skill:.*"land-pr"' >/dev/null; then
  pass "no-actionable arm has /land-pr dispatch (ship path)"
else
  fail "no-actionable arm missing /land-pr dispatch — sync's tracker discoveries would strand"
fi

if echo "$NO_ACT_BLOCK" | grep -E 'SPRINT_LAND_ID="fix-issues\.sync\.' >/dev/null; then
  pass "no-actionable arm uses distinct SPRINT_LAND_ID namespace (fix-issues.sync.*)"
else
  fail "no-actionable arm SPRINT_LAND_ID must use fix-issues.sync.* namespace to avoid colliding with Phase 6 fix-issues.sprint.*"
fi

# Trailing exit 0 — the arm must still terminate (cron retries next
# fire). Check for `exit 0` somewhere in the block.
if echo "$NO_ACT_BLOCK" | grep -E '^[[:space:]]*exit 0' >/dev/null; then
  pass "no-actionable arm ends with 'exit 0' (cron retries next fire)"
else
  fail "no-actionable arm missing 'exit 0' — pipeline would fall through into Post-prioritize tracking"
fi

# ─────────────────────────────────────────────────────────────────
# Assertion 11: sync Step 5 `git add -A "$ISSUES_REL"` must fail
# loud (issue #335). The original pattern
#   `git -C "$TOPLEVEL" add -A "$ISSUES_REL" 2>/dev/null || true`
# suppressed both stderr AND the exit status, so a real failure
# (permissions, repo corruption, race) silently desynced the
# tracker from the working tree while sync proceeded as if nothing
# happened — direct violation of CLAUDE.md's "never suppress
# errors on operations you need to verify" rule.
# Pin: the literal suppression pattern is GONE, and the line is
# now guarded by an `if ! git ... add -A "$ISSUES_REL"; then ...
# exit 1; fi` block.
# ─────────────────────────────────────────────────────────────────
echo ""
echo "=== sync Step 5 git add -A fails loud (issue #335) ==="

if grep -E 'git -C "\$TOPLEVEL" add -A "\$ISSUES_REL" 2>/dev/null \|\| true' "$FI_SKILL" >/dev/null; then
  fail "sync Step 5 still uses suppressed 'git add -A ... 2>/dev/null || true' pattern (#335 regression)"
else
  pass "sync Step 5 no longer suppresses 'git add -A \$ISSUES_REL' errors"
fi

if grep -E 'if ! git -C "\$TOPLEVEL" add -A "\$ISSUES_REL"; then' "$FI_SKILL" >/dev/null; then
  pass "sync Step 5 guards 'git add -A \$ISSUES_REL' with 'if ! ...; then exit 1; fi'"
else
  fail "sync Step 5 missing 'if ! git ... add -A \$ISSUES_REL; then ... fi' fail-loud guard"
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
