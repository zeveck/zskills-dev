#!/bin/bash
# test-fix-issues.sh — regression guards for skills/fix-issues/SKILL.md
# sync-mode fixes landed as a bundle (closes #280 #282 #300 #301).
#
# Each test is a tightly-scoped regression check:
#   - #301: the grep regex used by the row-writer + gap-listing loop must
#     match `**#NNN**` (markdown bold) and `### #NNN —` (heading). The
#     OLD ERE alternation `(^|[^0-9A-Za-z_])#$N($|[^0-9])` did NOT —
#     reproducible via a tiny fixture.
#   - #282: the close-on-success case statement in Step 5 sub-step 3 must
#     only fire on `merged)`. `created)` / `monitored)` reappearing would
#     re-introduce the AC-P.3 divergence that PR #271 fixed.
#   - #300: sync must (a) echo ZSKILLS_PIPELINE_ID=$PIPELINE_ID for
#     transcript propagation before the /land-pr dispatch (matches
#     /do pr's tier-2 idiom), AND (b) write its own
#     `fulfilled.land-pr.<id>` marker on /land-pr STATUS=merged, since
#     the conformance test forbids `export ZSKILLS_PIPELINE_ID`.
#     The marker write closes the original hole (#300) without using
#     the prohibited env-export side channel.
#   - #280: the per-issue `gh issue view` N+1 loop is gone; the row-writer
#     looks up title+labels in the cached `$GH_OUT` blob via Python json
#     so JSON-escaped quotes don't truncate titles.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/skills/fix-issues/SKILL.md"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# --- #301: regex behavior fixture ---------------------------------------
# Build a tiny tracker fragment with the two markdown shapes that the
# membership-check regex must recognize: bold `**#NNN**` and heading
# `### #NNN —`. The post-fix regex is `grep -qP "(?<![0-9])#N(?![0-9])"`;
# this test asserts the NEW pattern matches both shapes. (The OLD ERE
# alternation `(^|[^0-9A-Za-z_])#N($|[^0-9])` is grep-version-sensitive
# — on some GNU grep builds it matches, on the reporter's environment it
# did not — so we don't gate on its non-match. Source-grep below catches
# the substantive regression: the new -qP pattern must be wired in.)

test_301_regex_matches_markdown_bold_and_heading() {
  local fixture
  fixture=$(mktemp)
  cat > "$fixture" <<'TRACKER'
## Open issues

- **#279** — block-bypassed-land-pr
### #288 — ZSKILLS_PYTHON env override
TRACKER

  # NEW: PCRE lookarounds (what the skill uses post-fix)
  if grep -qP "(?<![0-9])#279(?![0-9])" "$fixture"; then
    pass "#301 new -qP regex matches **#279** markdown bold"
  else
    fail "#301 new -qP regex matches **#279** markdown bold" "no match"
  fi
  if grep -qP "(?<![0-9])#288(?![0-9])" "$fixture"; then
    pass "#301 new -qP regex matches '### #288' heading"
  else
    fail "#301 new -qP regex matches '### #288' heading" "no match"
  fi

  # Anchor-correctness: the new pattern still rejects `bug#23` (substring
  # match of `#239` would be wrong; the `(?<![0-9])` and `(?![0-9])`
  # boundaries protect both ends).
  if grep -qP "(?<![0-9])#23(?![0-9])" <(echo "bug#239 unrelated"); then
    fail "#301 new -qP regex must NOT match #23 inside #239" "matched"
  else
    pass "#301 new -qP regex correctly rejects #23 inside #239"
  fi

  rm -f "$fixture"
}

# --- #301: source-grep — both sites use -qP -----------------------------

test_301_source_uses_qP_lookarounds() {
  # The replacement pattern appears at both sites: the row-writer
  # membership check AND the gap-listing while loop. Both must use
  # grep -qP with `(?<![0-9])#...(?![0-9])`. Source-grep:
  local hits
  hits=$(grep -cF 'grep -qP "(?<![0-9])#' "$SKILL")
  if [ "$hits" -ge 2 ]; then
    pass "#301 SKILL.md uses grep -qP lookarounds at >=2 sites ($hits)"
  else
    fail "#301 SKILL.md uses grep -qP lookarounds at >=2 sites" "only $hits site(s) found"
  fi

  # The OLD ERE alternation must not survive in any EXECUTABLE bash
  # block. A grep_F count of <=1 is OK because the post-fix prose
  # comment cites the old pattern once for context. Two or more
  # occurrences means at least one site still has the executable form.
  local old_hits
  old_hits=$(grep -cF '(^|[^0-9A-Za-z_])#' "$SKILL")
  if [ "$old_hits" -le 1 ]; then
    pass "#301 OLD ERE alternation only present in explanatory prose ($old_hits occurrence)"
  else
    fail "#301 OLD ERE alternation only present in explanatory prose" "$old_hits occurrences — at least one executable site still uses it"
  fi
}

# --- #282: close-on-success case is `merged)` only ----------------------

test_282_success_set_is_merged_only() {
  # Extract the close-on-success case block from sub-step 3 and assert
  # only `merged)` is the success arm. `created|monitored|merged)`
  # reappearing — even partially — would re-introduce the bug.
  if grep -qE '^\s*merged\)' "$SKILL"; then
    pass "#282 close-on-success case has 'merged)' arm"
  else
    fail "#282 close-on-success case has 'merged)' arm" "not found"
  fi

  # The composite arm MUST NOT exist.
  if grep -qE 'created\|monitored\|merged\)' "$SKILL"; then
    fail "#282 'created|monitored|merged)' arm removed" "still present"
  else
    pass "#282 'created|monitored|merged)' arm removed"
  fi

  # Defense in depth: no `created)` or `monitored)` arm before `merged)`
  # that would re-enable closing on unmerged PRs.
  if grep -qE '^\s*created\)' "$SKILL"; then
    fail "#282 no 'created)' arm in success path" "found"
  else
    pass "#282 no 'created)' arm in success path"
  fi
  if grep -qE '^\s*monitored\)' "$SKILL"; then
    fail "#282 no 'monitored)' arm in success path" "found"
  else
    pass "#282 no 'monitored)' arm in success path"
  fi
}

# --- #300: transcript echo precedes /land-pr; marker written on merge ---

test_300_echo_precedes_land_pr_and_marker_on_merge() {
  # The transcript echo must precede the Skill dispatch line.
  local echo_line skill_line
  echo_line=$(grep -nF 'echo "ZSKILLS_PIPELINE_ID=$PIPELINE_ID"' "$SKILL" | head -1 | cut -d: -f1)
  skill_line=$(grep -nF 'Skill: { skill: "land-pr"' "$SKILL" | head -1 | cut -d: -f1)
  if [ -z "$echo_line" ]; then
    fail "#300 transcript echo ZSKILLS_PIPELINE_ID=... present" "not found"
    return
  fi
  if [ -z "$skill_line" ]; then
    fail "#300 /land-pr dispatch comment present" "no Skill: land-pr comment found"
    return
  fi
  if [ "$echo_line" -lt "$skill_line" ]; then
    pass "#300 transcript echo precedes /land-pr dispatch (lines $echo_line < $skill_line)"
  else
    fail "#300 transcript echo precedes /land-pr dispatch" "echo at line $echo_line, dispatch at $skill_line"
  fi

  # Sync must NOT use the prohibited `export ZSKILLS_PIPELINE_ID` form
  # (mirrors the conformance-test discipline).
  if grep -qE 'export[[:space:]]+ZSKILLS_PIPELINE_ID' "$SKILL"; then
    fail "#300 SKILL.md does NOT 'export ZSKILLS_PIPELINE_ID'" "side-channel re-introduced"
  else
    pass "#300 SKILL.md does NOT 'export ZSKILLS_PIPELINE_ID' (conformance preserved)"
  fi

  # The fulfilled.land-pr marker write must live inside the merged) arm
  # so sync closes the issue #300 hole itself when /land-pr returns
  # merged. We look for the marker filename literal and its `$SYNC_ID`
  # interpolation.
  if grep -qF 'fulfilled.land-pr.$SYNC_ID' "$SKILL"; then
    pass "#300 sync writes fulfilled.land-pr.\$SYNC_ID marker on merge"
  else
    fail "#300 sync writes fulfilled.land-pr.\$SYNC_ID marker on merge" "marker write not found"
  fi
}

# --- #280: no N+1 gh issue view loop; row-writer uses Python json -------

test_280_no_n_plus_one_loop_uses_python_json() {
  # The old code did `gh issue view "$N" --json title,labels` inside the
  # row-writer loop. That call must be gone from SKILL.md.
  if grep -qE 'gh issue view "\$N" --json title,labels' "$SKILL"; then
    fail "#280 N+1 'gh issue view \$N --json title,labels' removed" "still present"
  else
    pass "#280 N+1 'gh issue view \$N --json title,labels' removed"
  fi

  # And the cached batched fetch must request title+labels so the lookup
  # has data to find. (Bootstrap call used to be `--json number` only.)
  if grep -qF 'gh issue list --state open --limit 500 --json number,title,labels' "$SKILL"; then
    pass "#280 cached batched fetch requests number,title,labels"
  else
    fail "#280 cached batched fetch requests number,title,labels" "not found"
  fi

  # And the row-writer parses via Python json. The literal token
  # `python3 -c` must appear inside the residual-row block. We look for
  # the import line as a high-signal marker.
  if grep -qF 'import json, sys' "$SKILL"; then
    pass "#280 row-writer parses via Python json"
  else
    fail "#280 row-writer parses via Python json" "no python3 json import found"
  fi

  # The old grep-oE title parser must not survive as an EXECUTABLE call.
  # The post-fix prose cites the broken pattern once for context, so a
  # count <=1 is acceptable; >=2 means an executable site still has it.
  local old_hits
  old_hits=$(grep -cF "'\"title\":\"[^\"]*\"'" "$SKILL")
  if [ "$old_hits" -le 1 ]; then
    pass "#280 old grep -oE '\"title\":\"[^\"]*\"' parser only present in prose ($old_hits)"
  else
    fail "#280 old grep -oE '\"title\":\"[^\"]*\"' parser only present in prose" "$old_hits occurrences"
  fi
}

# --- #280: behavior — Python json correctly extracts escaped-quote title -

test_280_python_json_handles_escaped_quotes() {
  # Repro the original bug — but with the fixed code path. Construct a
  # JSON blob with an escaped-quote title and confirm Python json
  # extracts it cleanly. This isn't a SKILL.md grep; it's a behavioral
  # sanity check that the fix's pattern actually works.
  local got
  got=$(printf '%s' '[{"number":42,"title":"Fix \"foo\" handling","labels":[]}]' | python3 -c '
import json, sys
data = json.load(sys.stdin)
for it in data:
    if it.get("number") == 42:
        sys.stdout.write(it["title"])
        break
')
  if [ "$got" = 'Fix "foo" handling' ]; then
    pass "#280 Python json extracts title with escaped quotes intact"
  else
    fail "#280 Python json extracts title with escaped quotes intact" "got: [$got]"
  fi
}

# --- dashboard token: detection + Phase 2 branch + Python-not-regex -----
#
# Three regression-grep guards mirroring the existing pattern above:
#   Case A: Phase 0 detection — the case-insensitive bash-regex for
#           `dashboard` (matches the `auto`/`pr`/`direct`/`now` idiom).
#   Case B: Phase 2 contains a `$DASHBOARD_MODE` branch that gates the
#           dashboard-Ready source path.
#   Case C: The state-file read uses `python3 -c` against
#           `monitor-state.json`, NOT bash regex on the JSON array shape.

test_dashboard_token_recognized_in_phase0() {
  # Case A: the case-insensitive bash-regex token-match pattern for
  # `dashboard` must appear in the Phase 0 detection block.
  if grep -qF '[dD][aA][sS][hH][bB][oO][aA][rR][dD]' "$SKILL"; then
    pass "dashboard Phase 0 detection regex present"
  else
    fail "dashboard Phase 0 detection regex present" "case-insensitive bash-regex pattern for 'dashboard' not found"
  fi

  # And DASHBOARD_MODE must be assigned (the canonical sentinel).
  if grep -qE 'DASHBOARD_MODE=0' "$SKILL"; then
    pass "dashboard DASHBOARD_MODE sentinel assigned"
  else
    fail "dashboard DASHBOARD_MODE sentinel assigned" "DASHBOARD_MODE=0 init not found"
  fi
}

test_dashboard_phase2_branch_present() {
  # Case B: Phase 2 must reference $DASHBOARD_MODE so the dashboard
  # source branch gates the model-layer rubric. We assert >=1 such
  # reference appears AFTER the "## Phase 2" header line.
  local phase2_line dashboard_hits
  phase2_line=$(grep -nE '^## Phase 2' "$SKILL" | head -1 | cut -d: -f1)
  if [ -z "$phase2_line" ]; then
    fail "dashboard Phase 2 branch present" "no '## Phase 2' header found"
    return
  fi
  # Count $DASHBOARD_MODE references at or after the Phase 2 header.
  dashboard_hits=$(awk -v start="$phase2_line" 'NR>=start && /DASHBOARD_MODE/ { c++ } END { print c+0 }' "$SKILL")
  if [ "$dashboard_hits" -ge 1 ]; then
    pass "dashboard Phase 2 has DASHBOARD_MODE branch ($dashboard_hits references)"
  else
    fail "dashboard Phase 2 has DASHBOARD_MODE branch" "no DASHBOARD_MODE references at/after line $phase2_line"
  fi
}

test_dashboard_uses_python_json_not_bash_regex() {
  # Case C: the state-file read must use python3 reading
  # monitor-state.json, AND must NOT parse issues.ready via bash regex
  # on a JSON-array shape like `\[[0-9,[:space:]]+\]`.
  #
  # We look for the python3 invocation referencing the state file.
  if grep -qF 'monitor-state.json' "$SKILL"; then
    pass "dashboard reads monitor-state.json"
  else
    fail "dashboard reads monitor-state.json" "no reference to monitor-state.json"
  fi
  if grep -qE 'python3 -c' "$SKILL"; then
    pass "dashboard uses python3 -c to parse JSON"
  else
    fail "dashboard uses python3 -c to parse JSON" "no python3 -c invocation"
  fi

  # Negative assertion: the prohibited bash-regex shape MUST NOT appear
  # anywhere in the skill. The pattern `\[[0-9,[:space:]]+\]` is exactly
  # what someone would write if they tried to bash-regex an integer JSON
  # array — banned per /fix-issues' Python-json discipline (issue #280
  # established this rule).
  if grep -qE '\[\[0-9,\[\:space\:\]\]\+\]' "$SKILL"; then
    fail "dashboard does NOT bash-regex issues.ready array" "found prohibited bash-regex JSON-array pattern"
  else
    pass "dashboard does NOT bash-regex issues.ready array"
  fi
}

# --- dashboard mutex: 5 verbatim ERROR strings present ------------------
#
# PR #313 added mutual-exclusion guards between `dashboard` and each of
# focus/sync/plan/stop/next modes. Each guard emits a specific
# user-facing ERROR string. This test asserts all 5 strings exist
# verbatim in SKILL.md so a future edit can't silently drop or rename
# one of them without tripping a regression.

test_dashboard_mutex_error_strings_present() {
  local EXPECTED_MUTEX_ERRORS=(
    "ERROR: dashboard is incompatible with focus mode"
    "ERROR: dashboard is incompatible with sync mode"
    "ERROR: dashboard is incompatible with plan mode"
    "ERROR: dashboard is incompatible with stop mode"
    "ERROR: dashboard is incompatible with next mode"
  )
  local missing=()
  local s
  for s in "${EXPECTED_MUTEX_ERRORS[@]}"; do
    if ! grep -qF "$s" "$SKILL"; then
      missing+=("$s")
    fi
  done
  if [ "${#missing[@]}" -eq 0 ]; then
    pass "dashboard mutex: all 5 verbatim ERROR strings present (focus/sync/plan/stop/next)"
  else
    fail "dashboard mutex: all 5 verbatim ERROR strings present" "missing: ${missing[*]}"
  fi
}

# --- #325: sprint-mode worktree gate (Phase 1 preamble + Phase 5 land) ---
#
# Sprint mode previously wrote ISSUES_PLAN.md (Phase 1 row-writer) and
# SPRINT_REPORT.md (Phase 5 append) directly to main's working tree when
# main_protected: true. PR #252 fixed standalone `## Sync` with an
# ensure-worktree.sh preamble; sprint mode was missed. These tests guard
# the parity fix shipped for #325.

test_325_sprint_phase1_has_ensure_worktree_preamble() {
  # Locate the Phase 1 header. The preamble lives under "## Phase 1 —
  # Preflight & Sync" inside the "### Sprint tracking sentinel" block.
  local phase1_line phase1b_line preamble_line
  phase1_line=$(grep -nE '^## Phase 1 — Preflight & Sync' "$SKILL" | head -1 | cut -d: -f1)
  phase1b_line=$(grep -nE '^## Phase 1b' "$SKILL" | head -1 | cut -d: -f1)
  if [ -z "$phase1_line" ] || [ -z "$phase1b_line" ]; then
    fail "#325 Phase 1 has ensure-worktree.sh preamble" "Phase 1 / Phase 1b header not found"
    return
  fi
  # The preamble's distinguishing signature: the helper-path assignment
  # to the create-worktree ensure-worktree.sh script.
  preamble_line=$(awk -v start="$phase1_line" -v end="$phase1b_line" \
    'NR>=start && NR<end && /create-worktree\/scripts\/ensure-worktree\.sh/ { print NR; exit }' "$SKILL")
  if [ -n "$preamble_line" ]; then
    pass "#325 Phase 1 has ensure-worktree.sh preamble (line $preamble_line)"
  else
    fail "#325 Phase 1 has ensure-worktree.sh preamble" "ensure-worktree.sh not invoked between Phase 1 and Phase 1b"
  fi

  # The preamble must also pass --pipeline-id "$PIPELINE_ID" so the
  # worktree's purpose tag is bound to the per-sprint scope. Look for
  # the flag AFTER the helper line (so we don't accept a prose comment
  # mentioning the flag as proof that the preamble passes it).
  local pid_line
  pid_line=$(awk -v start="$preamble_line" -v end="$phase1b_line" \
    'NR>start && NR<end && /--pipeline-id "\$PIPELINE_ID"/ { print NR; exit }' "$SKILL")
  if [ -n "$pid_line" ]; then
    pass "#325 Phase 1 preamble passes --pipeline-id \"\$PIPELINE_ID\" (line $pid_line)"
  else
    fail "#325 Phase 1 preamble passes --pipeline-id \"\$PIPELINE_ID\"" "flag not found in preamble body (after helper line $preamble_line)"
  fi
}

test_325_sprint_id_lifted_above_preamble() {
  # The plan's correctness condition: SPRINT_ID/PIPELINE_ID must be
  # constructed BEFORE the ensure-worktree.sh helper is invoked, because
  # the helper consumes --pipeline-id "$PIPELINE_ID". A prior version
  # of the sentinel block had the construction AFTER the (non-existent)
  # preamble; lifting it above is the structural fix.
  local sprint_id_line preamble_line
  # Find the SPRINT_ID assignment line within Phase 1 (first occurrence
  # of the canonical assignment idiom; sentinel block lifts it).
  local phase1_line phase1b_line
  phase1_line=$(grep -nE '^## Phase 1 — Preflight & Sync' "$SKILL" | head -1 | cut -d: -f1)
  phase1b_line=$(grep -nE '^## Phase 1b' "$SKILL" | head -1 | cut -d: -f1)
  if [ -z "$phase1_line" ] || [ -z "$phase1b_line" ]; then
    fail "#325 SPRINT_ID lifted above preamble" "Phase 1 / Phase 1b header not found"
    return
  fi
  sprint_id_line=$(awk -v start="$phase1_line" -v end="$phase1b_line" \
    'NR>=start && NR<end && /^SPRINT_ID="sprint-\$\(date -u/ { print NR; exit }' "$SKILL")
  preamble_line=$(awk -v start="$phase1_line" -v end="$phase1b_line" \
    'NR>=start && NR<end && /create-worktree\/scripts\/ensure-worktree\.sh/ { print NR; exit }' "$SKILL")
  if [ -z "$sprint_id_line" ]; then
    fail "#325 SPRINT_ID lifted above preamble" "SPRINT_ID construction line not found in Phase 1"
    return
  fi
  if [ -z "$preamble_line" ]; then
    fail "#325 SPRINT_ID lifted above preamble" "ensure-worktree.sh preamble not found in Phase 1"
    return
  fi
  if [ "$sprint_id_line" -lt "$preamble_line" ]; then
    pass "#325 SPRINT_ID construction precedes preamble (lines $sprint_id_line < $preamble_line)"
  else
    fail "#325 SPRINT_ID construction precedes preamble" "SPRINT_ID at $sprint_id_line, preamble at $preamble_line — must be lifted above"
  fi
}

test_325_phase5_has_commit_and_landpr_dispatch() {
  # The Phase 5 commit + /land-pr dispatch block lives between the Phase 5
  # header and the Phase 6 header. Two distinguishing signatures:
  #  (a) a `docs(sprint): tracker rows + sprint report` commit message
  #  (b) a `Skill: { skill: "land-pr"` dispatch comment with --landed-source=fix-issues-sprint
  local phase5_line phase6_line commit_line dispatch_line
  phase5_line=$(grep -nE '^## Phase 5 — Write Sprint Report' "$SKILL" | head -1 | cut -d: -f1)
  phase6_line=$(grep -nE '^## Phase 6 — Land' "$SKILL" | head -1 | cut -d: -f1)
  if [ -z "$phase5_line" ] || [ -z "$phase6_line" ]; then
    fail "#325 Phase 5 has commit + /land-pr dispatch" "Phase 5 / Phase 6 header not found"
    return
  fi
  commit_line=$(awk -v start="$phase5_line" -v end="$phase6_line" \
    'NR>=start && NR<end && /docs\(sprint\): tracker rows \+ sprint report/ { print NR; exit }' "$SKILL")
  dispatch_line=$(awk -v start="$phase5_line" -v end="$phase6_line" \
    'NR>=start && NR<end && /Skill: \{ skill: "land-pr"/ && /\$LAND_ARGS/ { print NR; exit }' "$SKILL")
  if [ -n "$commit_line" ]; then
    pass "#325 Phase 5 has 'docs(sprint): tracker rows + sprint report' commit (line $commit_line)"
  else
    fail "#325 Phase 5 has 'docs(sprint): tracker rows + sprint report' commit" "commit message not found between Phase 5 and Phase 6"
  fi
  if [ -n "$dispatch_line" ]; then
    pass "#325 Phase 5 has /land-pr Skill dispatch (line $dispatch_line)"
  else
    fail "#325 Phase 5 has /land-pr Skill dispatch" "Skill: { skill: \"land-pr\" ... \$LAND_ARGS } not found between Phase 5 and Phase 6"
  fi

  # The Phase 5 dispatch must NOT pass an auto-merge flag — sprint
  # landing is interactive (matches standalone sync convention).
  local auto_in_args
  auto_in_args=$(awk -v start="$phase5_line" -v end="$phase6_line" \
    'NR>=start && NR<end && /LAND_ARGS=/ && /--auto/ { print NR }' "$SKILL")
  if [ -z "$auto_in_args" ]; then
    pass "#325 Phase 5 /land-pr dispatch is interactive (no --auto)"
  else
    fail "#325 Phase 5 /land-pr dispatch is interactive (no --auto)" "found --auto in LAND_ARGS at line(s): $auto_in_args"
  fi
}

# --- Mirror parity -------------------------------------------------------

test_mirror_in_sync() {
  local src="$REPO_ROOT/skills/fix-issues/SKILL.md"
  local mirror="$REPO_ROOT/.claude/skills/fix-issues/SKILL.md"
  if diff -q "$src" "$mirror" > /dev/null 2>&1; then
    pass "skills/fix-issues/SKILL.md mirror matches source"
  else
    fail "skills/fix-issues/SKILL.md mirror matches source" "diff between source and .claude/ mirror"
  fi
}

echo "=== /fix-issues sync-mode + sprint-mode (#280 #282 #300 #301 #325) regression guards ==="
test_301_regex_matches_markdown_bold_and_heading
test_301_source_uses_qP_lookarounds
test_282_success_set_is_merged_only
test_300_echo_precedes_land_pr_and_marker_on_merge
test_280_no_n_plus_one_loop_uses_python_json
test_280_python_json_handles_escaped_quotes
test_dashboard_token_recognized_in_phase0
test_dashboard_phase2_branch_present
test_dashboard_uses_python_json_not_bash_regex
test_dashboard_mutex_error_strings_present
test_325_sprint_phase1_has_ensure_worktree_preamble
test_325_sprint_id_lifted_above_preamble
test_325_phase5_has_commit_and_landpr_dispatch
test_mirror_in_sync

echo ""
echo "---"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
[ "$FAIL_COUNT" -eq 0 ]
