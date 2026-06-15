#!/bin/bash
# test-fix-issues-phase2-source-filter.sh — behavioral coverage for the
# Phase 2 source-filter introduced for issue #408.
#
# Issue #408: Phase 1's research dispatch (step 5 + step 6) is prose-only
# and was skipped routinely across ~50 sprints. Phase 2 then triaged
# from bare titles + body previews — bypassing #402's independent-sizing
# discipline (which requires a tracker blurb to read against).
#
# The fix is structural: at Phase 2 entry, source-filter candidates by
# whether they have a tracker blurb with an `**Action now:**` line.
# Auto mode dispatches research agents in parallel and re-filters;
# interactive mode aborts with a diagnostic.
#
# This suite covers:
#   1. Filter script: mixed researched/un-researched candidates split
#      correctly into RESEARCHED / MISSING.
#   2. Filter script: Action-now is the signal, NOT Verdict — a row with
#      `**Verdict:** NOT YET RESEARCHED` and no `**Action now:**` is
#      treated as MISSING; a row with `**Verdict:** LIKELY FIXED` AND a
#      `**Action now:**` line is treated as RESEARCHED.
#   3. Filter script: hash-number disambiguation — `### #38` does NOT
#      match candidate `380`.
#   4. Filter script: empty candidate list yields empty arrays.
#   5. SKILL.md: the dashboard branch and default-rubric branch both
#      reference the filter script after candidate construction.
#   6. SKILL.md: auto-mode prose calls out parallel general-purpose
#      research dispatch and a re-filter after dispatch.
#   7. SKILL.md: interactive-mode prose emits a `/fix-issues sync`
#      diagnostic and exits non-zero before triage proceeds.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FILTER="$REPO_ROOT/skills/fix-issues/scripts/filter-unresearched-candidates.sh"
SKILL="$REPO_ROOT/skills/fix-issues/modes/sprint.md"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# Sandbox.
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# --- Sanity: filter script exists and is executable ----------------------
test_filter_script_exists() {
  if [ -f "$FILTER" ] && [ -x "$FILTER" ]; then
    pass "filter-unresearched-candidates.sh exists and is executable"
  else
    fail "filter-unresearched-candidates.sh exists and is executable" \
         "not found or not executable: $FILTER"
  fi
}

# --- Fixture builder -----------------------------------------------------
# Build a tracker dir with a single ISSUES.md file containing mixed rows.
build_fixture() {
  local dir="$1"
  mkdir -p "$dir"
  cat > "$dir/ISSUES.md" <<'EOF'
# fixture ISSUES.md

---

### #100 — researched issue with Action now

**Labels:** bug | **Verdict:** NOT FIXED — etc.

**Problem.** ...

**Fix outline.** ...

**Complexity:** S. **Action now:** /do pr — bounded.

---

### #101 — stub row with NOT YET RESEARCHED verdict and no Action now

**Labels:** bug | **Verdict:** NOT YET RESEARCHED

**Problem.** placeholder.

---

### #102 — researched but verdict says LIKELY FIXED

**Labels:** bug | **Verdict:** LIKELY FIXED — fix in 1234abc.

**Problem.** observed.

**Fix outline.** verify and close.

**Complexity:** XS. **Action now:** /do pr — close after verification.

---

### #38 — old short-numbered issue with Action now

**Labels:** (none) | **Verdict:** NOT FIXED.

**Complexity:** S. **Action now:** /do pr.

---
EOF
}

# Run filter; capture stdout, eval into local RESEARCHED / MISSING.
run_filter() {
  local issues_dir="$1"; shift
  ZSKILLS_ISSUES_DIR="$issues_dir" bash "$FILTER" "$@"
}

# --- 1. Mixed: 100 researched, 101 un-researched, 102 researched --------
test_mixed_split() {
  local dir="$TMP_ROOT/mixed"
  build_fixture "$dir"
  local out
  out=$(run_filter "$dir" 100 101 102)
  local researched missing
  researched=$(echo "$out" | grep '^RESEARCHED=' | sed -e 's/^RESEARCHED=//' -e 's/^"//' -e 's/"$//')
  missing=$(echo "$out" | grep '^MISSING=' | sed -e 's/^MISSING=//' -e 's/^"//' -e 's/"$//')
  if [ "$researched" = "100 102" ] && [ "$missing" = "101" ]; then
    pass "mixed candidates split: 100,102 researched, 101 missing"
  else
    fail "mixed candidates split" "got RESEARCHED=[$researched] MISSING=[$missing]"
  fi
}

# --- 2a. NOT YET RESEARCHED stub (no Action now) is MISSING -------------
test_stub_verdict_is_missing() {
  local dir="$TMP_ROOT/stub"
  build_fixture "$dir"
  local out missing
  out=$(run_filter "$dir" 101)
  missing=$(echo "$out" | grep '^MISSING=' | sed -e 's/^MISSING=//' -e 's/^"//' -e 's/"$//')
  if [ "$missing" = "101" ]; then
    pass "row with NOT YET RESEARCHED verdict + no Action now is MISSING"
  else
    fail "stub-verdict is MISSING" "got MISSING=[$missing]"
  fi
}

# --- 2b. LIKELY FIXED verdict + Action now is RESEARCHED ----------------
test_likely_fixed_with_action_is_researched() {
  local dir="$TMP_ROOT/lf"
  build_fixture "$dir"
  local out researched
  out=$(run_filter "$dir" 102)
  researched=$(echo "$out" | grep '^RESEARCHED=' | sed -e 's/^RESEARCHED=//' -e 's/^"//' -e 's/"$//')
  if [ "$researched" = "102" ]; then
    pass "LIKELY FIXED + Action now is RESEARCHED (Verdict is not the signal)"
  else
    fail "LIKELY FIXED + Action now is RESEARCHED" "got RESEARCHED=[$researched]"
  fi
}

# --- 3. Hash-number disambiguation — #38 must not match candidate 380 ---
test_hash_disambiguation() {
  local dir="$TMP_ROOT/disambig"
  build_fixture "$dir"
  # Candidate 380 does NOT appear in fixture; the only `### #38 ` line
  # is for issue #38. Naive `grep "^### #38"` would match.
  local out researched missing
  out=$(run_filter "$dir" 380)
  researched=$(echo "$out" | grep '^RESEARCHED=' | sed -e 's/^RESEARCHED=//' -e 's/^"//' -e 's/"$//')
  missing=$(echo "$out" | grep '^MISSING=' | sed -e 's/^MISSING=//' -e 's/^"//' -e 's/"$//')
  if [ -z "$researched" ] && [ "$missing" = "380" ]; then
    pass "hash disambiguation: candidate 380 does not match '### #38 ' row"
  else
    fail "hash disambiguation" "got RESEARCHED=[$researched] MISSING=[$missing]"
  fi
}

# --- 3b. Issue #38 itself IS researched (positive control) --------------
test_issue_38_itself_researched() {
  local dir="$TMP_ROOT/38ctrl"
  build_fixture "$dir"
  local out researched
  out=$(run_filter "$dir" 38)
  researched=$(echo "$out" | grep '^RESEARCHED=' | sed -e 's/^RESEARCHED=//' -e 's/^"//' -e 's/"$//')
  if [ "$researched" = "38" ]; then
    pass "issue 38 itself matches its own row (positive control)"
  else
    fail "issue 38 positive control" "got RESEARCHED=[$researched]"
  fi
}

# --- 4. Empty candidate list yields empty arrays ------------------------
test_empty_candidates() {
  local dir="$TMP_ROOT/empty"
  build_fixture "$dir"
  local out researched missing
  out=$(run_filter "$dir")
  researched=$(echo "$out" | grep '^RESEARCHED=' | sed -e 's/^RESEARCHED=//' -e 's/^"//' -e 's/"$//')
  missing=$(echo "$out" | grep '^MISSING=' | sed -e 's/^MISSING=//' -e 's/^"//' -e 's/"$//')
  if [ -z "$researched" ] && [ -z "$missing" ]; then
    pass "empty candidate list -> empty RESEARCHED + empty MISSING"
  else
    fail "empty candidate list" "got RESEARCHED=[$researched] MISSING=[$missing]"
  fi
}

# --- 4b. Missing ZSKILLS_ISSUES_DIR triggers usage error ----------------
test_usage_error_no_env() {
  local rc=0
  (ZSKILLS_ISSUES_DIR= bash "$FILTER" 100) >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 1 ]; then
    pass "missing ZSKILLS_ISSUES_DIR -> exit 1"
  else
    fail "missing ZSKILLS_ISSUES_DIR -> exit 1" "got rc=$rc"
  fi
}

# --- 4c. Tracker dir with no matching files yields all MISSING ----------
test_empty_tracker_dir() {
  local dir="$TMP_ROOT/no-md"
  mkdir -p "$dir"
  # No *.md files at all.
  local out researched missing
  out=$(run_filter "$dir" 100 200)
  researched=$(echo "$out" | grep '^RESEARCHED=' | sed -e 's/^RESEARCHED=//' -e 's/^"//' -e 's/"$//')
  missing=$(echo "$out" | grep '^MISSING=' | sed -e 's/^MISSING=//' -e 's/^"//' -e 's/"$//')
  if [ -z "$researched" ] && [ "$missing" = "100 200" ]; then
    pass "tracker dir with no *.md -> all candidates MISSING"
  else
    fail "empty tracker dir" "got RESEARCHED=[$researched] MISSING=[$missing]"
  fi
}

# --- 4d. Multi-candidate eval round-trip (regression: PR #415 unquoted RHS)
# The script's documented consumer pattern is:
#   eval "$(... filter-unresearched-candidates.sh "${CANDIDATE_ISSUES[@]}")"
# Before this fix the script emitted `RESEARCHED=A B C` unquoted; eval
# parsed that as an env-prefixed simple command (RESEARCHED=A is the
# assignment, `B C` is the command), printed `B: command not found`,
# and left RESEARCHED/MISSING empty in the caller. The fix quotes the
# printf RHS so eval sees one assignment. Single-candidate (N=1)
# always worked because there was no embedded space — assert that
# boundary stays correct, AND that the N>=2 case now round-trips.
test_eval_roundtrip_multi_candidate() {
  local dir="$TMP_ROOT/eval"
  build_fixture "$dir"
  local RESEARCHED="" MISSING=""
  eval "$(ZSKILLS_ISSUES_DIR="$dir" bash "$FILTER" 100 102 38)"
  local -a RESEARCHED_ARR=() MISSING_ARR=()
  while IFS= read -r _tok || [ -n "$_tok" ]; do
    [ -n "$_tok" ] && RESEARCHED_ARR+=("$_tok")
  done < <(printf '%s' "${RESEARCHED:-}" | head -n 1 | tr ' \t' '\n\n')
  while IFS= read -r _tok || [ -n "$_tok" ]; do
    [ -n "$_tok" ] && MISSING_ARR+=("$_tok")
  done < <(printf '%s' "${MISSING:-}" | head -n 1 | tr ' \t' '\n\n')
  if [ "${#RESEARCHED_ARR[@]}" -eq 3 ] \
     && [ "${RESEARCHED_ARR[0]}" = "100" ] \
     && [ "${RESEARCHED_ARR[1]}" = "102" ] \
     && [ "${RESEARCHED_ARR[2]}" = "38" ] \
     && [ "${#MISSING_ARR[@]}" -eq 0 ]; then
    pass "multi-candidate eval round-trip: 3 researched into array, 0 missing (PR #415 regression boundary)"
  else
    fail "multi-candidate eval round-trip" \
         "RESEARCHED_ARR=(${RESEARCHED_ARR[*]}) count=${#RESEARCHED_ARR[@]}; MISSING_ARR=(${MISSING_ARR[*]}) count=${#MISSING_ARR[@]}"
  fi
}

# --- 4e. Single-candidate eval round-trip (regression boundary: N=1) ----
# N=1 has no embedded space and ALWAYS worked, even with the buggy
# unquoted printf. Pin the boundary so a future "simplification" that
# drops the quoting doesn't silently regress only multi-candidate.
test_eval_roundtrip_single_candidate() {
  local dir="$TMP_ROOT/eval1"
  build_fixture "$dir"
  local RESEARCHED="" MISSING=""
  eval "$(ZSKILLS_ISSUES_DIR="$dir" bash "$FILTER" 100)"
  local -a RESEARCHED_ARR=()
  while IFS= read -r _tok || [ -n "$_tok" ]; do
    [ -n "$_tok" ] && RESEARCHED_ARR+=("$_tok")
  done < <(printf '%s' "${RESEARCHED:-}" | head -n 1 | tr ' \t' '\n\n')
  if [ "${#RESEARCHED_ARR[@]}" -eq 1 ] && [ "${RESEARCHED_ARR[0]}" = "100" ]; then
    pass "single-candidate eval round-trip: 1 researched into array (N=1 boundary)"
  else
    fail "single-candidate eval round-trip" \
         "RESEARCHED_ARR=(${RESEARCHED_ARR[*]}) count=${#RESEARCHED_ARR[@]}"
  fi
}

# --- 5. SKILL.md anchors filter at dashboard + default-rubric branches --
test_skill_dashboard_invokes_filter() {
  # The dashboard branch must reference the filter script after
  # CANDIDATE_ISSUES is built.
  if grep -qF 'filter-unresearched-candidates.sh' "$SKILL"; then
    local count
    count=$(grep -cF 'filter-unresearched-candidates.sh' "$SKILL")
    # Expect at least 4 invocations: dashboard initial + dashboard re-filter
    # + default-rubric initial + default-rubric re-filter.
    if [ "$count" -ge 4 ]; then
      pass "SKILL.md invokes filter script $count times (dashboard + default-rubric, each with initial + re-filter)"
    else
      fail "SKILL.md filter invocation count" "expected >=4, got $count"
    fi
  else
    fail "SKILL.md references filter script" "filter-unresearched-candidates.sh not found"
  fi
}

# --- 5b. B-proper: Phase 2 PRESERVES CANDIDATE_ISSUES + exports
# RESEARCHED_SET as a parallel index. Inversion of the old assertion
# (which pinned `CANDIDATE_ISSUES=("${RESEARCHED_ARR[@]}")` — the very
# overwrite that B-proper removes so Phase 3's loop can reach the
# unresearched tail via synchronous research-on-demand).
test_skill_dashboard_rebuild_candidates() {
  # After the filter eval, the dashboard + default-rubric branches must
  # NOT discard CANDIDATE_ISSUES, and MUST build a `RESEARCHED_SET`
  # associative-array index keyed by issue number.
  if grep -qF 'CANDIDATE_ISSUES=("${RESEARCHED_ARR[@]}")' "$SKILL"; then
    fail "SKILL.md preserves CANDIDATE_ISSUES (B-proper)" \
         "found legacy overwrite \`CANDIDATE_ISSUES=(\"\${RESEARCHED_ARR[@]}\")\` — Phase 3 loop needs full uncapped Ready∩Open list to reach unresearched tail"
    return
  fi
  if grep -qF 'declare -A RESEARCHED_SET' "$SKILL" \
     && grep -qE 'RESEARCHED_SET\[(\"\$?__r\"|\$ISSUE_NUM)' "$SKILL"; then
    pass "SKILL.md preserves CANDIDATE_ISSUES + exports RESEARCHED_SET parallel index (B-proper)"
  else
    fail "SKILL.md RESEARCHED_SET index" \
         "expected \`declare -A RESEARCHED_SET\` + per-element population — B-proper structural change missing"
  fi
}

# --- 6. Auto-mode prose calls out parallel dispatch + re-filter ---------
test_skill_auto_dispatch_prose() {
  if grep -qF 'general-purpose' "$SKILL" \
     && grep -qE 'up to 3 (at a time|concurrent)' "$SKILL" \
     && grep -qE 'parallel|in parallel' "$SKILL"; then
    pass "SKILL.md auto-mode prose: general-purpose + up-to-3 + parallel"
  else
    fail "SKILL.md auto-mode prose" "missing one of: general-purpose / up to 3 / parallel"
  fi
}

# --- 6b. Scratchpad path appears in 3+ locations (PR 1 stage-and-decide)
# Research-agent prompt + Phase 2 union (dashboard+rubric branches) +
# Phase 3 unions (cherry-pick+PR loops) + race-loss rm-f + acquire-success
# promote in both modes. At minimum, expect >=3 references to the
# `research-staging/$PIPELINE_ID/issue-` substring.
test_skill_scratchpad_path_prose() {
  local count
  count=$(grep -cF 'research-staging/$PIPELINE_ID/issue-' "$SKILL")
  if [ "$count" -ge 3 ]; then
    pass "SKILL.md references scratchpad path \`research-staging/\$PIPELINE_ID/issue-\` $count times (>=3)"
  else
    fail "SKILL.md scratchpad path count" "expected >=3, got $count"
  fi
}

# --- 6c. Research-agent prompt instructs NO commit (PR 1 stage-and-decide)
# The new shape: research agents write a scratchpad and return WITHOUT
# committing. Lock the prompt change so a regression to "Commit the row
# in the active worktree before returning." is caught.
test_skill_research_agent_no_commit() {
  if grep -qF 'Commit the row in the active worktree before returning' "$SKILL"; then
    fail "SKILL.md research-agent prompt no-commit" \
         "found legacy substring 'Commit the row in the active worktree before returning' — stage-and-decide forbids agent commits"
    return
  fi
  if grep -qF 'Do NOT `git add` or' "$SKILL" \
     || grep -qE 'Do NOT .{0,20}git commit' "$SKILL"; then
    pass "SKILL.md research-agent prompt: explicit Do-NOT-commit + no legacy 'Commit the row' string"
  else
    fail "SKILL.md research-agent no-commit instruction" \
         "expected 'Do NOT git commit' (or equivalent) in research-agent prompt block"
  fi
}

# --- PR-2 / A+F: filter emits SKIP_TAGGED line -------------------------
# Mixed fixture with /draft-plan, /do pr rows. SKIP_TAGGED must contain
# the /draft-plan issue tagged `:plan-scale` and must NOT contain the
# /do pr issue.
build_skip_tagged_fixture() {
  local dir="$1"
  mkdir -p "$dir"
  cat > "$dir/ISSUES.md" <<'EOF'
### #700 — plan-scale issue

**Labels:** bug | **Verdict:** NOT FIXED.

**Complexity:** L. **Action now:** /draft-plan — needs design review.

### #701 — actionable

**Labels:** bug | **Verdict:** NOT FIXED.

**Complexity:** S. **Action now:** /do pr — bounded.

### #702 — investigate

**Labels:** bug | **Verdict:** UNCLEAR.

**Complexity:** M. **Action now:** /investigate — root cause unclear.

### #703 — needs decision

**Labels:** bug | **Verdict:** NOT FIXED.

**Complexity:** S. **Action now:** none — author decision needed.

### #704 — false-positive boundary (must NOT match `none`)

**Complexity:** S. **Action now:** none-of-the-above — placeholder.

### #705 — /run-plan should map to plan-scale

**Complexity:** S. **Action now:** /run-plan — execute existing plan.

### #706 — deferred (none + leave open)

**Complexity:** L. **Action now:** none — leave open as architectural memo.

### #707 — deferred (none + waiting)

**Action now:** none — waiting on prerequisite plans.
EOF
}

test_filter_emits_skip_tagged() {
  local dir="$TMP_ROOT/skip-tagged"
  build_skip_tagged_fixture "$dir"
  local out skip_tagged
  out=$(run_filter "$dir" 700 701)
  skip_tagged=$(echo "$out" | grep '^SKIP_TAGGED=' | sed -e 's/^SKIP_TAGGED=//' -e 's/^"//' -e 's/"$//')
  if [ "$skip_tagged" = "700:plan-scale" ]; then
    pass "SKIP_TAGGED emitted for /draft-plan row; /do pr row excluded"
  else
    fail "SKIP_TAGGED emission" "expected '700:plan-scale', got [$skip_tagged]"
  fi
}

test_filter_skip_tagged_codes() {
  local dir="$TMP_ROOT/codes"
  build_skip_tagged_fixture "$dir"
  local out skip_tagged
  out=$(run_filter "$dir" 700 701 702 703 704 705 706 707)
  skip_tagged=$(echo "$out" | grep '^SKIP_TAGGED=' | sed -e 's/^SKIP_TAGGED=//' -e 's/^"//' -e 's/"$//')
  # Expected: 700:plan-scale (draft-plan), 702:bug-unclear-cause (investigate),
  # 703:needs-decision (none + "author decision"), 705:plan-scale (run-plan),
  # 706:deferred (none + "leave open"), 707:deferred (none + "waiting").
  # 701 (/do pr) and 704 (none-of-the-above boundary) must NOT appear.
  local expected="700:plan-scale 702:bug-unclear-cause 703:needs-decision 705:plan-scale 706:deferred 707:deferred"
  if [ "$skip_tagged" = "$expected" ]; then
    pass "SKIP_TAGGED per-code coverage: /draft-plan→plan-scale, /investigate→bug-unclear-cause, none+author-decision→needs-decision, none+leave-open→deferred, /run-plan→plan-scale; boundaries excluded"
  else
    fail "SKIP_TAGGED per-code coverage" "expected '$expected', got [$skip_tagged]"
  fi
}

test_filter_skip_tagged_empty_when_no_skip_rows() {
  local dir="$TMP_ROOT/no-skip"
  mkdir -p "$dir"
  cat > "$dir/ISSUES.md" <<'EOF'
### #800 — actionable only

**Complexity:** S. **Action now:** /do pr — bounded.
EOF
  local out skip_tagged
  out=$(run_filter "$dir" 800)
  # The SKIP_TAGGED line MUST still be emitted (backward-compat) but empty.
  if ! echo "$out" | grep -q '^SKIP_TAGGED='; then
    fail "SKIP_TAGGED always emitted" "no SKIP_TAGGED line found in output: $out"
    return
  fi
  skip_tagged=$(echo "$out" | grep '^SKIP_TAGGED=' | sed -e 's/^SKIP_TAGGED=//' -e 's/^"//' -e 's/"$//')
  if [ -z "$skip_tagged" ]; then
    pass "SKIP_TAGGED line present but empty when no skip-class rows"
  else
    fail "SKIP_TAGGED empty when no skip rows" "got [$skip_tagged]"
  fi
}

# --- PR-2 / A+F: SKILL.md Phase 2 drop logic in both branches ----------
test_skill_phase2_drops_skip_tagged() {
  # Expect the SKIP_TAGGED_SET array population AND the _FILTERED
  # reduction loop AND the `dropping skip-tagged` log line to appear
  # in BOTH dashboard branch and default-rubric branch (2 hits each).
  local set_count filtered_count drop_log_count
  set_count=$(grep -c 'declare -A SKIP_TAGGED_SET' "$SKILL")
  filtered_count=$(grep -c 'declare -a _FILTERED=()' "$SKILL")
  drop_log_count=$(grep -c 'dropping skip-tagged' "$SKILL")
  if [ "$set_count" -eq 2 ] && [ "$filtered_count" -eq 2 ] && [ "$drop_log_count" -eq 2 ]; then
    pass "SKILL.md Phase 2 drop block present in BOTH branches (SKIP_TAGGED_SET=2, _FILTERED=2, drop-log=2)"
  else
    fail "SKILL.md Phase 2 drop block coverage" \
         "expected 2 each — got SKIP_TAGGED_SET=$set_count _FILTERED=$filtered_count drop-log=$drop_log_count"
  fi
}

# --- PR-2 / A+F: write-back rewrites scratchpad in BOTH mode arms ------
test_skill_writeback_rewrites_scratchpad() {
  # Each mode (cherry-pick/direct + PR-mode) must contain a case branch
  # mapping plan-scale / bug-unclear-cause / needs-decision /
  # deferred / author-decision to canonical NEW_ACTION_NOW values.
  # Expect >=10 NEW_ACTION_NOW= assignments total (5 cases × 2 modes).
  local nan_count
  nan_count=$(grep -c '^[[:space:]]*NEW_ACTION_NOW=' "$SKILL")
  if [ "$nan_count" -lt 10 ]; then
    fail "SKILL.md NEW_ACTION_NOW count" "expected >=10 (5 cases × 2 modes), got $nan_count"
    return
  fi
  # Load-bearing: the actual `sed -i` rewrite MUST appear EXACTLY 2 times
  # (once per mode). Without this assertion the impl could declare the
  # mapping vars but skip the sed call.
  local sed_count
  sed_count=$(grep -c 'sed -i.*Action now' "$SKILL")
  if [ "$sed_count" -eq 2 ]; then
    pass "SKILL.md write-back: NEW_ACTION_NOW assigned $nan_count times (>=8) AND sed -i rewrite present exactly 2 times (cherry-pick + PR-mode)"
  else
    fail "SKILL.md write-back sed -i count" "expected exactly 2 sed-i Action-now rewrites, got $sed_count"
  fi
}

# --- PR-2 / A+F: PR-mode end-of-loop tracker rollup --------------------
test_skill_pr_mode_tracker_rollup() {
  # Assertions:
  #   - branch name `fix-issues-tracker/$SPRINT_ID` referenced.
  #   - create-worktree.sh invoked with --prefix tracker.
  #   - Skill: { skill: "land-pr" comment line for the tracker dispatch.
  #   - --landed-source=fix-issues-pr-mode-tracker-rollup tag used.
  local missing=""
  grep -qF 'fix-issues-tracker/$SPRINT_ID' "$SKILL" || missing="$missing fix-issues-tracker/\$SPRINT_ID"
  grep -qF -- '--prefix tracker' "$SKILL" || missing="$missing --prefix-tracker"
  grep -qF 'Skill: { skill: "land-pr"' "$SKILL" || missing="$missing land-pr-skill-comment"
  grep -qF -- '--landed-source=fix-issues-pr-mode-tracker-rollup' "$SKILL" || missing="$missing landed-source-tag"
  if [ -z "$missing" ]; then
    pass "SKILL.md PR-mode tracker rollup: branch + create-worktree --prefix tracker + land-pr skill comment + landed-source tag"
  else
    fail "SKILL.md PR-mode tracker rollup" "missing:$missing"
  fi
}

# --- 7. Interactive-mode prose emits /fix-issues sync diagnostic --------
test_skill_interactive_abort_prose() {
  # The interactive branch must (a) emit a diagnostic pointing at
  # `/fix-issues sync` and (b) exit 1 before triage proceeds.
  if grep -qF '/fix-issues sync' "$SKILL" \
     && grep -qF 'lack research blurbs' "$SKILL"; then
    pass "SKILL.md interactive-mode diagnostic: /fix-issues sync + 'lack research blurbs'"
  else
    fail "SKILL.md interactive-mode diagnostic" "missing diagnostic substrings"
  fi
}

test_skill_interactive_exit_1() {
  # Confirm an `exit 1` follows the interactive diagnostic. We use
  # grep -n + awk to confirm `exit 1` appears within 3 lines after the
  # /fix-issues sync diagnostic. Expect both dashboard + default-rubric
  # interactive branches to have this shape (2 occurrences).
  local diag_lines exit_lines hits=0
  diag_lines=$(grep -nF 'first to populate tracker rows' "$SKILL" | cut -d: -f1)
  exit_lines=$(grep -nE '^    exit 1$' "$SKILL" | cut -d: -f1)
  for d in $diag_lines; do
    for e in $exit_lines; do
      local delta=$((e - d))
      if [ "$delta" -ge 1 ] && [ "$delta" -le 3 ]; then
        hits=$((hits + 1))
        break
      fi
    done
  done
  if [ "$hits" -ge 2 ]; then
    pass "SKILL.md interactive-mode exits 1 within 3 lines of diagnostic (both branches: $hits hits)"
  else
    fail "SKILL.md interactive-mode exit 1" "expected >=2 (dashboard + default-rubric); got $hits"
  fi
}

# --- Run all -------------------------------------------------------------
test_filter_script_exists
test_mixed_split
test_stub_verdict_is_missing
test_likely_fixed_with_action_is_researched
test_hash_disambiguation
test_issue_38_itself_researched
test_empty_candidates
test_usage_error_no_env
test_empty_tracker_dir
test_eval_roundtrip_multi_candidate
test_eval_roundtrip_single_candidate
test_skill_dashboard_invokes_filter
test_skill_dashboard_rebuild_candidates
test_skill_auto_dispatch_prose
test_skill_scratchpad_path_prose
test_skill_research_agent_no_commit
test_skill_interactive_abort_prose
test_skill_interactive_exit_1
test_filter_emits_skip_tagged
test_filter_skip_tagged_codes
test_filter_skip_tagged_empty_when_no_skip_rows
test_skill_phase2_drops_skip_tagged
test_skill_writeback_rewrites_scratchpad
test_skill_pr_mode_tracker_rollup

echo ""
echo "---"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
[ "$FAIL_COUNT" -eq 0 ]
