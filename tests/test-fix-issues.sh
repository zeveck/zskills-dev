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
SKILL_DIR="$REPO_ROOT/skills/fix-issues"
SKILL="$SKILL_DIR/SKILL.md"
SKILL_SPRINT="$SKILL_DIR/modes/sprint.md"
SKILL_SYNC="$SKILL_DIR/modes/sync.md"

# skill_grep: recursive grep across all .md files in the skill directory.
# Replaces single-file $SKILL grep for content that may live in any mode file.
skill_grep() { grep "$@" "$SKILL_DIR"/*.md "$SKILL_DIR"/modes/*.md "$SKILL_DIR"/subcommands/*.md 2>/dev/null; }

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
  hits=$(grep -cF 'grep -qP "(?<![0-9])#' "$SKILL_SPRINT")
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
  old_hits=$(grep -cF '(^|[^0-9A-Za-z_])#' "$SKILL_SPRINT")
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
  if grep -qE '^\s*merged\)' "$SKILL_SYNC"; then
    pass "#282 close-on-success case has 'merged)' arm"
  else
    fail "#282 close-on-success case has 'merged)' arm" "not found"
  fi

  # The composite arm MUST NOT exist.
  if grep -qE 'created\|monitored\|merged\)' "$SKILL_SYNC"; then
    fail "#282 'created|monitored|merged)' arm removed" "still present"
  else
    pass "#282 'created|monitored|merged)' arm removed"
  fi

  # Defense in depth: no `created)` or `monitored)` arm before `merged)`
  # that would re-enable closing on unmerged PRs.
  if grep -qE '^\s*created\)' "$SKILL_SYNC"; then
    fail "#282 no 'created)' arm in success path" "found"
  else
    pass "#282 no 'created)' arm in success path"
  fi
  if grep -qE '^\s*monitored\)' "$SKILL_SYNC"; then
    fail "#282 no 'monitored)' arm in success path" "found"
  else
    pass "#282 no 'monitored)' arm in success path"
  fi
}

# --- #300: transcript echo precedes /land-pr; marker written on merge ---

test_300_echo_precedes_land_pr_and_marker_on_merge() {
  # The transcript echo must precede the Skill dispatch line.
  local echo_line skill_line
  echo_line=$(grep -nF 'echo "ZSKILLS_PIPELINE_ID=$PIPELINE_ID"' "$SKILL_SYNC" | head -1 | cut -d: -f1)
  skill_line=$(grep -nF 'Skill: { skill: "land-pr"' "$SKILL_SYNC" | head -1 | cut -d: -f1)
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
  if skill_grep -qE 'export[[:space:]]+ZSKILLS_PIPELINE_ID'; then
    fail "#300 SKILL.md does NOT 'export ZSKILLS_PIPELINE_ID'" "side-channel re-introduced"
  else
    pass "#300 SKILL.md does NOT 'export ZSKILLS_PIPELINE_ID' (conformance preserved)"
  fi

  # The fulfilled.land-pr marker write must live inside the merged) arm
  # so sync closes the issue #300 hole itself when /land-pr returns
  # merged. We look for the marker filename literal and its `$SYNC_ID`
  # interpolation.
  if grep -qF 'fulfilled.land-pr.$SYNC_ID' "$SKILL_SYNC"; then
    pass "#300 sync writes fulfilled.land-pr.\$SYNC_ID marker on merge"
  else
    fail "#300 sync writes fulfilled.land-pr.\$SYNC_ID marker on merge" "marker write not found"
  fi
}

# --- #280: no N+1 gh issue view loop; row-writer uses Python json -------

test_280_no_n_plus_one_loop_uses_python_json() {
  # The old code did `gh issue view "$N" --json title,labels` inside the
  # row-writer loop. That call must be gone from SKILL.md.
  if grep -qE 'gh issue view "\$N" --json title,labels' "$SKILL_SPRINT"; then
    fail "#280 N+1 'gh issue view \$N --json title,labels' removed" "still present"
  else
    pass "#280 N+1 'gh issue view \$N --json title,labels' removed"
  fi

  # And the cached batched fetch must request title+labels so the lookup
  # has data to find. (Bootstrap call used to be `--json number` only.)
  if grep -qF 'gh issue list --state open --limit 500 --json number,title,labels' "$SKILL_SPRINT"; then
    pass "#280 cached batched fetch requests number,title,labels"
  else
    fail "#280 cached batched fetch requests number,title,labels" "not found"
  fi

  # And the row-writer parses via Python json. The literal token
  # `python3 -c` must appear inside the residual-row block. We look for
  # the import line as a high-signal marker.
  if grep -qF 'import json, sys' "$SKILL_SPRINT"; then
    pass "#280 row-writer parses via Python json"
  else
    fail "#280 row-writer parses via Python json" "no python3 json import found"
  fi

  # The old grep-oE title parser must not survive as an EXECUTABLE call.
  # The post-fix prose cites the broken pattern once for context, so a
  # count <=1 is acceptable; >=2 means an executable site still has it.
  local old_hits
  old_hits=$(grep -cF "'\"title\":\"[^\"]*\"'" "$SKILL_SPRINT")
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
  phase2_line=$(grep -nE '^## Phase 2' "$SKILL_SPRINT" | head -1 | cut -d: -f1)
  if [ -z "$phase2_line" ]; then
    fail "dashboard Phase 2 branch present" "no '## Phase 2' header found"
    return
  fi
  # Count $DASHBOARD_MODE references at or after the Phase 2 header.
  dashboard_hits=$(awk -v start="$phase2_line" 'NR>=start && /DASHBOARD_MODE/ { c++ } END { print c+0 }' "$SKILL_SPRINT")
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
  if skill_grep -qF 'monitor-state.json'; then
    pass "dashboard reads monitor-state.json"
  else
    fail "dashboard reads monitor-state.json" "no reference to monitor-state.json"
  fi
  # Post-#1083 the interpreter is resolved via $PYTHON (Windows MS-Store-stub
  # guard) instead of a bare python3 — accept either the resolved "$PYTHON" -c
  # form or a legacy bare python3 -c.
  if grep -qE '("\$PYTHON"|python3) -c' "$SKILL_SPRINT"; then
    pass "dashboard uses \"\$PYTHON\" -c to parse JSON"
  else
    fail "dashboard uses \"\$PYTHON\" -c to parse JSON" "no \"\$PYTHON\" -c / python3 -c invocation"
  fi

  # Negative assertion: the prohibited bash-regex shape MUST NOT appear
  # anywhere in the skill. The pattern `\[[0-9,[:space:]]+\]` is exactly
  # what someone would write if they tried to bash-regex an integer JSON
  # array — banned per /fix-issues' Python-json discipline (issue #280
  # established this rule).
  if skill_grep -qE '\[\[0-9,\[\:space\:\]\]\+\]'; then
    fail "dashboard does NOT bash-regex issues.ready array" "found prohibited bash-regex JSON-array pattern"
  else
    pass "dashboard does NOT bash-regex issues.ready array"
  fi
}

# --- dashboard + landing-mode tokens propagate to cron prompt (#362) ----
#
# Phase 0c step 3 builds CRON_TOKENS for the self-perpetuating cron prompt.
# Issue #362: the original block only appended `auto`, silently dropping
# `dashboard` and explicit landing-mode tokens (`pr`/`direct`). Cron fire
# #2+ then lost the dashboard-Ready source-of-truth and fell back to the
# model-layer priority rubric.
#
# This test guards two propagation lines in skills/fix-issues/SKILL.md:
#   (1) A DASHBOARD_MODE conditional appending `dashboard` to CRON_TOKENS.
#   (2) A LANDING_MODE case statement appending `pr` or `direct`.

test_dashboard_token_propagates_to_cron_prompt() {
  # (1) DASHBOARD_MODE → CRON_TOKENS dashboard propagation.
  if grep -qE 'DASHBOARD_MODE.*=.*"?1"?.*CRON_TOKENS.*dashboard' "$SKILL_SPRINT"; then
    pass "CRON_TOKENS propagates dashboard when DASHBOARD_MODE=1 (#362)"
  else
    fail "CRON_TOKENS propagates dashboard when DASHBOARD_MODE=1 (#362)" \
      "no DASHBOARD_MODE-guarded 'CRON_TOKENS=...dashboard' line found in Phase 0c"
  fi

  # (2) LANDING_MODE case statement assigning pr/direct to CRON_TOKENS.
  # We look for the `case "$LANDING_MODE"` header plus both arm tokens
  # near a CRON_TOKENS append.
  if grep -qE 'case[[:space:]]+"\$LANDING_MODE"' "$SKILL_SPRINT" \
     && grep -qE 'pr\)[[:space:]]*CRON_TOKENS=.*pr' "$SKILL_SPRINT" \
     && grep -qE 'direct\)[[:space:]]*CRON_TOKENS=.*direct' "$SKILL_SPRINT"; then
    pass "CRON_TOKENS propagates pr/direct via LANDING_MODE case (#362)"
  else
    fail "CRON_TOKENS propagates pr/direct via LANDING_MODE case (#362)" \
      "LANDING_MODE case statement assigning pr/direct to CRON_TOKENS not found"
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

# --- tracker-PR auto-merge content-stream semantics (post-PR #357 revert) -
#
# Four dispatch sites in /fix-issues open tracker-style PRs via /land-pr.
# Their `--auto` semantics follow what each PR commits, NOT what the user
# said:
#   Site 1 (Phase 6 sprint-land):     fix-work content → follows user's `auto`
#   Site 2 (standalone sync Phase 5): sync-only content → unconditional --auto
#   Site 3 (sprint no-actionable):    sync-only content → unconditional --auto
#   Site 4 (dashboard-empty exits):   route through ship-or-cleanup (sync-only
#                                      content → unconditional --auto)
#
# The PR #356 attempt over-corrected and dropped the `auto` honor on the
# Phase 6 sprint-land PR too — content-stream-blind. PR #357 reverted it;
# this regression bundle pins the corrected asymmetry.

test_site2_sync_phase5_unconditional_auto() {
  # The standalone sync Phase 5 LAND_ARGS line must end with `--auto`.
  # Identified by --landed-source=fix-issues-sync (site 2 only).
  local line
  line=$(grep -nF 'landed-source=fix-issues-sync ' "$SKILL_SYNC" \
         | grep -F 'LAND_ARGS=' | head -1 | cut -d: -f1)
  if [ -z "$line" ]; then
    fail "site 2: standalone sync LAND_ARGS line found" "no LAND_ARGS line with landed-source=fix-issues-sync"
    return
  fi
  local content
  content=$(awk -v n="$line" 'NR==n { print }' "$SKILL_SYNC")
  if echo "$content" | grep -qE -- '--auto --automerge"?$'; then
    pass "site 2: standalone sync LAND_ARGS ends with --auto --automerge (unconditional)"
  else
    fail "site 2: standalone sync LAND_ARGS ends with --auto --automerge" "line $line does not end --auto --automerge: [$content]"
  fi
}

test_site3_no_actionable_unconditional_auto() {
  # The sprint no-actionable LAND_ARGS line must end with `--auto`.
  # Identified by --landed-source=fix-issues-no-actionable (site 3 only).
  local line
  line=$(grep -nF 'landed-source=fix-issues-no-actionable ' "$SKILL_SPRINT" \
         | grep -F 'LAND_ARGS=' | head -1 | cut -d: -f1)
  if [ -z "$line" ]; then
    fail "site 3: no-actionable LAND_ARGS line found" "no LAND_ARGS line with landed-source=fix-issues-no-actionable"
    return
  fi
  local content
  content=$(awk -v n="$line" 'NR==n { print }' "$SKILL_SPRINT")
  if echo "$content" | grep -qE -- '--auto --automerge"?$'; then
    pass "site 3: no-actionable LAND_ARGS ends with --auto --automerge (unconditional)"
  else
    fail "site 3: no-actionable LAND_ARGS ends with --auto --automerge" "line $line does not end --auto --automerge: [$content]"
  fi

  # And the AUTO-conditional must NOT appear immediately after the
  # no-actionable LAND_ARGS line (would re-introduce content-stream
  # confusion).
  local next
  next=$(awk -v n="$line" 'NR==n+1 { print }' "$SKILL_SPRINT")
  if echo "$next" | grep -qE '\[\s*"\$\{AUTO_FLAG:-0\}"\s*=\s*"1"\s*\]\s*&&\s*LAND_ARGS='; then
    fail "site 3: no AUTO-conditional after no-actionable LAND_ARGS" "found on line $((line+1)): [$next]"
  else
    pass "site 3: no AUTO-conditional immediately after no-actionable LAND_ARGS"
  fi
}

test_site1_sprint_land_honors_auto() {
  # CRITICAL INVARIANT from PR #357 revert: the Phase 6 sprint-land
  # LAND_ARGS must NOT have unconditional --auto, and the AUTO-conditional
  # MUST be present immediately after it. Identified by
  # --landed-source=fix-issues-sprint (site 1 only).
  local line
  line=$(grep -nF 'landed-source=fix-issues-sprint ' "$SKILL_SPRINT" \
         | grep -F 'LAND_ARGS=' | head -1 | cut -d: -f1)
  if [ -z "$line" ]; then
    fail "site 1: Phase 6 sprint-land LAND_ARGS line found" "no LAND_ARGS line with landed-source=fix-issues-sprint"
    return
  fi
  local content
  content=$(awk -v n="$line" 'NR==n { print }' "$SKILL_SPRINT")
  if echo "$content" | grep -qE -- '--auto"?$'; then
    fail "site 1: Phase 6 sprint-land LAND_ARGS must NOT end --auto" "PR #356 regression: line $line ends --auto unconditionally: [$content]"
  else
    pass "site 1: Phase 6 sprint-land LAND_ARGS does NOT end --auto (honors user's auto)"
  fi

  # The AUTO-conditional MUST be on the very next line.
  local next
  next=$(awk -v n="$line" 'NR==n+1 { print }' "$SKILL_SPRINT")
  if echo "$next" | grep -qE '\[\s*"\$\{AUTO_FLAG:-0\}"\s*=\s*"1"\s*\]\s*&&\s*LAND_ARGS='; then
    pass "site 1: AUTO-conditional present immediately after sprint-land LAND_ARGS"
  else
    fail "site 1: AUTO-conditional present immediately after sprint-land LAND_ARGS" \
         "PR #356 regression — line $((line+1)) is not the AUTO-conditional: [$next]"
  fi
}

test_site4_dashboard_empty_exits_route_through_ship_or_cleanup() {
  # The two dashboard-empty exits must route through ship-or-cleanup
  # (Option A: function call) instead of bare `exit 0` immediately after
  # the "Dashboard Ready is empty" echo. Phase 1a sync may have written
  # tracker updates to the worktree; bare `exit 0` would strand them.
  #
  # Locate both echo lines and assert the line BEFORE `exit 0` is the
  # ship_sync_only_or_cleanup call (Option A) — not a bare echo + exit.
  local echo_lines
  echo_lines=$(grep -nF 'Dashboard Ready is empty — nothing to do' "$SKILL_SPRINT" | cut -d: -f1)
  local n_lines
  n_lines=$(printf '%s\n' "$echo_lines" | wc -l)
  if [ "$n_lines" -lt 2 ]; then
    fail "site 4: both dashboard-empty echo lines present" "found $n_lines, expected 2"
    return
  fi

  local missing=0
  for el in $echo_lines; do
    # The line immediately after the echo should be the ship_sync_only_or_cleanup
    # call (not exit 0 directly).
    local next_line
    next_line=$(awk -v n="$el" 'NR==n+1 { print }' "$SKILL_SPRINT")
    if ! echo "$next_line" | grep -qE 'ship_sync_only_or_cleanup'; then
      fail "site 4: dashboard-empty echo at line $el routes through ship-or-cleanup" \
           "next line is not ship_sync_only_or_cleanup: [$next_line]"
      missing=1
    fi
  done
  if [ "$missing" -eq 0 ]; then
    pass "site 4: both dashboard-empty exits route through ship_sync_only_or_cleanup ($n_lines sites)"
  fi

  # And ship_sync_only_or_cleanup must be defined somewhere in the file.
  if grep -qE '^\s*ship_sync_only_or_cleanup\s*\(\s*\)\s*\{' "$SKILL_SPRINT"; then
    pass "site 4: ship_sync_only_or_cleanup() helper defined"
  else
    fail "site 4: ship_sync_only_or_cleanup() helper defined" "function definition not found"
  fi
}

test_no_intentionally_omitted_rationale() {
  # The deprecated "intentionally omitted" rationale was tied to the old
  # claim that sync is always interactive at the PR level. With unconditional
  # --auto on site 2, that prose is wrong and must be removed.
  if skill_grep -qF 'intentionally omitted'; then
    fail "deprecated 'intentionally omitted' rationale removed" "still present"
  else
    pass "deprecated 'intentionally omitted' rationale removed"
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

echo "=== /fix-issues sync-mode bundle (#280 #282 #300 #301) regression guards ==="
test_301_regex_matches_markdown_bold_and_heading
test_301_source_uses_qP_lookarounds
test_282_success_set_is_merged_only
test_300_echo_precedes_land_pr_and_marker_on_merge
test_280_no_n_plus_one_loop_uses_python_json
test_280_python_json_handles_escaped_quotes
test_dashboard_token_recognized_in_phase0
test_dashboard_phase2_branch_present
test_dashboard_uses_python_json_not_bash_regex
test_dashboard_token_propagates_to_cron_prompt
test_dashboard_mutex_error_strings_present
test_site2_sync_phase5_unconditional_auto
test_site3_no_actionable_unconditional_auto
test_site1_sprint_land_honors_auto
test_site4_dashboard_empty_exits_route_through_ship_or_cleanup
test_no_intentionally_omitted_rationale
test_mirror_in_sync

echo ""
echo "---"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
[ "$FAIL_COUNT" -eq 0 ]
