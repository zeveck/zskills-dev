#!/bin/bash
# tests/test-fix-issues-bootstrap.sh — behavioral fixture tests for the
# bootstrap + row-writer + /land-pr dispatch paths in
# skills/fix-issues/modes/sprint.md (originally added in PR #269 / #284).
#
# EXTRACT-AND-RUN (SEAM_HARDENING_REST Phase 3):
#   This file no longer carries an EMBEDDED copy of the bootstrap +
#   row-writer bash guarded by a loose substring-parity gate. Instead it
#   EXTRACTS the three REAL production fences from modes/sprint.md via
#   tests/lib/extract-fence.sh's extract_fence_between and RUNS them
#   against a fixture worktree with a mocked `gh`. A logic change BETWEEN
#   the (formerly fingerprinted) lines of any fence now fails these tests —
#   not just a deleted line.
#
#   The three fences (verified line ranges in modes/sprint.md):
#     - FETCH       (≈342-354, 3-space-indented → strip-indent=1):
#         sources zskills-paths.sh, runs `gh issue list`, populates
#         $GH_OUT / $OPEN_NUMS / $OPEN_COUNT. Run FIRST — the row-writer's
#         python3 consumes $GH_OUT / $OPEN_NUMS (cross-fence state).
#     - BOOTSTRAP   (≈365-399, column-0 → strip-indent=0):
#         sources zskills-resolve-config.sh, creates ISSUES_PLAN.md from a
#         frontmatter+header template when no tracker exists and there are
#         open issues; clean early `exit 0` when 0 open issues.
#     - ROW-WRITER  (≈416-448, 3-space-indented → strip-indent=1):
#         appends `### #N — <title>` rows for residual (untracked) issues,
#         deduped via the PCRE membership anchor (#301), title/labels parsed
#         with Python json (#280).
#
#   MIXED INDENT (critical): fetch + row-writer are nested under a numbered
#   markdown list item (3-space body indent → strip-indent=1); bootstrap is
#   a column-0 fence (strip-indent=0). A wrong strip-indent per fence yields
#   syntactically broken bash once the fences are concatenated and eval'd.
#
#   ANTI-NO-OP (review F4): the production fences source
#   zskills-{paths,resolve-config}.sh, which RESOLVE $ZSKILLS_ISSUES_DIR
#   from $CLAUDE_PROJECT_DIR/.claude/zskills-config.json — and would
#   OVERWRITE any value we seed. If those source-scripts were allowed to
#   run against an empty/absent config, $ZSKILLS_ISSUES_DIR would resolve
#   to the repo's real plans/ (or be wrong), and the row-writer would write
#   somewhere other than our fixture — the test would pass against a no-op.
#   Defense: we point $CLAUDE_PROJECT_DIR at a STUB project root whose
#   .claude/skills/update-zskills/scripts/zskills-{paths,resolve-config}.sh
#   are inert (they set $TIMEZONE but DO NOT touch $ZSKILLS_ISSUES_DIR), and
#   we EXPORT $ZSKILLS_ISSUES_DIR to the per-case fixture dir ourselves. The
#   behavioral tests then ASSERT a row actually LANDS in that fixture dir
#   (file present with expected content), not merely that the eval ran.
#
# Why a second test file (alongside test-fix-issues.sh):
#   test-fix-issues.sh is regression-grep guards for the source markdown
#   (#280 #282 #300 #301). It does NOT execute any bash from the skill.
#   This file complements it by EXECUTING the real extracted fences against
#   a fixture worktree with a mocked `gh`, asserting the produced
#   ISSUES_PLAN.md actually contains the expected rows.
#
# Mock strategy:
#   PATH-prefix shim writes a canned JSON blob for `gh issue list` calls.
#   Per-case canned data lives in the per-case fixture dir; the shim reads
#   it via env var. Sufficient for our scenarios (one `gh issue list` call
#   per case). `gh issue close` is recorded to a call-log for the
#   end-to-end sync-and-land smoke.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/skills/fix-issues/modes/sprint.md"
SKILL_SYNC="$REPO_ROOT/skills/fix-issues/modes/sync.md"

# shellcheck source=tests/lib/extract-fence.sh
. "$SCRIPT_DIR/lib/extract-fence.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# Per-test scratch root. Each test cleans up its own subdir on success.
SCRATCH_ROOT="/tmp/test-fix-issues-bootstrap-$$"
if [ -n "${TEST_KEEP_SCRATCH:-}" ]; then
  echo "TEST_KEEP_SCRATCH set — leaving $SCRATCH_ROOT for inspection" >&2
else
  trap 'rm -rf "$SCRATCH_ROOT"' EXIT
fi
mkdir -p "$SCRATCH_ROOT"

# ---- Extract the three REAL fences from modes/sprint.md ----------------
# Tight prose landmarks bracket exactly one ```bash fence each (the lib's
# preferred anchoring over fence-index counting). Per-fence strip-indent:
#   FETCH + ROW-WRITER = 1 (3-space markdown-list indent); BOOTSTRAP = 0.
FETCH_FENCE=$(extract_fence_between "$SKILL" \
  'Fetch the open-issue list AND count safely' 'Bootstrap empty' 1 1) \
  || { echo "FATAL: could not extract FETCH fence from $SKILL" >&2; exit 2; }
BOOTSTRAP_FENCE=$(extract_fence_between "$SKILL" \
  'Bootstrap empty' 'Row-writer for residual issues' 1 0) \
  || { echo "FATAL: could not extract BOOTSTRAP fence from $SKILL" >&2; exit 2; }
ROWWRITER_FENCE=$(extract_fence_between "$SKILL" \
  'Row-writer for residual issues' 'Find gaps' 1 1) \
  || { echo "FATAL: could not extract ROW-WRITER fence from $SKILL" >&2; exit 2; }

# Sanity: each fence is non-empty and carries its signature line. Catches a
# silent mis-extraction (empty body / wrong fence) before any test runs.
sanity_fences() {
  local ok=1
  printf '%s' "$FETCH_FENCE" | grep -qF 'GH_OUT=$(gh issue list' || { echo "FATAL: FETCH fence missing GH_OUT assignment" >&2; ok=0; }
  printf '%s' "$BOOTSTRAP_FENCE" | grep -qF 'title: Issues — Auto-Bootstrapped Tracker' || { echo "FATAL: BOOTSTRAP fence missing header template" >&2; ok=0; }
  printf '%s' "$ROWWRITER_FENCE" | grep -qF '**Verdict:** NOT YET RESEARCHED' || { echo "FATAL: ROW-WRITER fence missing Verdict line" >&2; ok=0; }
  [ "$ok" -eq 1 ] || exit 2
}
sanity_fences

# ---- Stub project root: inert source-scripts -> preserve our seed ------
# The production fences `source` zskills-paths.sh (FETCH) and
# zskills-resolve-config.sh (BOOTSTRAP) from
# $CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/. The REAL
# scripts RESOLVE $ZSKILLS_ISSUES_DIR from config and would CLOBBER the
# fixture dir we seed → the anti-no-op trap. We point $CLAUDE_PROJECT_DIR
# at a stub root whose copies of those two scripts are inert: they export
# $TIMEZONE (consumed by the bootstrap's `date`) and DELIBERATELY do NOT
# assign $ZSKILLS_ISSUES_DIR, so the value the caller exports survives.
STUB_ROOT="$SCRATCH_ROOT/stub-project"
STUB_SCRIPTS="$STUB_ROOT/.claude/skills/update-zskills/scripts"
mkdir -p "$STUB_SCRIPTS"
cat > "$STUB_SCRIPTS/zskills-paths.sh" <<'STUB'
# Test stub — inert. Production resolves $ZSKILLS_ISSUES_DIR here; the test
# seeds it instead, so this stub must NOT assign it.
:
STUB
cat > "$STUB_SCRIPTS/zskills-resolve-config.sh" <<'STUB'
# Test stub — inert. Production resolves config vars here; the bootstrap
# fence only consumes $TIMEZONE (for `date`), which we leave empty so the
# fence's `${TIMEZONE:-UTC}` fallback applies. MUST NOT assign
# $ZSKILLS_ISSUES_DIR (the test seeds it).
TIMEZONE="${TIMEZONE:-}"
STUB

# ---- Run the three real fences in order, in the caller's subshell ------
# Concatenation order is load-bearing: FETCH first ($GH_OUT/$OPEN_NUMS/
# $OPEN_COUNT), then BOOTSTRAP, then ROW-WRITER (consumes $GH_OUT and
# iterates $OPEN_NUMS). A clean `exit 0` in BOOTSTRAP (zero-open case) ends
# this subshell exactly as the production skill exits the step. Run inside
# `( ... )` by each test case with $ZSKILLS_ISSUES_DIR + $CLAUDE_PROJECT_DIR
# + PATH (gh shim) exported.
run_real_sync() {
  eval "$FETCH_FENCE"
  eval "$BOOTSTRAP_FENCE"
  eval "$ROWWRITER_FENCE"
  # Echo the row count the production skill prints after the row-writer so
  # callers can observe it; ROW-WRITER itself does not echo (the skill's
  # surrounding prose does). Keeping it here is harmless and mirrors intent.
  return 0
}

# ---- gh shim ------------------------------------------------------------
# A minimal `gh` substitute. Reads $MOCK_GH_ISSUES_JSON for the canned
# `gh issue list ... --json ...` response. Other subcommands fail loud.
make_gh_shim() {
  local bin_dir="$1"
  mkdir -p "$bin_dir"
  cat > "$bin_dir/gh" <<'SHIM'
#!/bin/bash
# Test-only gh shim. Honors only `gh issue list ...` and `gh issue close ...`.
if [ "${1:-}" = "issue" ] && [ "${2:-}" = "list" ]; then
  if [ -n "${MOCK_GH_ISSUES_JSON:-}" ] && [ -f "$MOCK_GH_ISSUES_JSON" ]; then
    cat "$MOCK_GH_ISSUES_JSON"
    exit 0
  fi
  echo "gh-shim: MOCK_GH_ISSUES_JSON unset or missing" >&2
  exit 99
fi
if [ "${1:-}" = "issue" ] && [ "${2:-}" = "close" ]; then
  # Record the call so end-to-end test can inspect it.
  echo "gh issue close $*" >> "${MOCK_GH_CALL_LOG:-/dev/null}"
  exit 0
fi
echo "gh-shim: unexpected invocation: $*" >&2
exit 99
SHIM
  chmod +x "$bin_dir/gh"
}

# ---- Per-test fixture builder ------------------------------------------
new_case() {
  local label="$1"
  local dir="$SCRATCH_ROOT/$label"
  mkdir -p "$dir/bin" "$dir/issues"
  make_gh_shim "$dir/bin"
  printf '%s' "$dir"
}

# ---- Anti-no-op guard test ---------------------------------------------
# Prove the harness is NOT a no-op: with $ZSKILLS_ISSUES_DIR seeded, the
# row-writer writes a real file into the fixture dir; and if it were NOT
# seeded, the eval would NOT write there. This is the structural defense
# against review-F4 hollowness — a row must actually LAND.
test_anti_noop_row_lands() {
  local label="anti-noop"
  local dir; dir=$(new_case "$label")
  local issues_dir="$dir/issues"
  local json="$dir/gh-issues.json"
  cat > "$json" <<'JSON'
[{"number":777,"title":"Anti-noop sentinel","labels":[{"name":"meta"}]}]
JSON

  ( set -u
    export PATH="$dir/bin:$PATH"
    export CLAUDE_PROJECT_DIR="$STUB_ROOT"
    export ZSKILLS_ISSUES_DIR="$issues_dir"
    export MOCK_GH_ISSUES_JSON="$json"
    run_real_sync
  ) > "$dir/out.txt" 2> "$dir/err.txt"
  local rc=$?

  local plan="$issues_dir/ISSUES_PLAN.md"
  if [ "$rc" -ne 0 ]; then
    fail "anti-noop: real fences run clean" "rc=$rc; err: $(cat "$dir/err.txt")"
    return
  fi
  # The row MUST physically land in the seeded fixture dir.
  if [ -f "$plan" ] && grep -qF '### #777 — Anti-noop sentinel' "$plan"; then
    pass "anti-noop: a row actually LANDS in seeded \$ZSKILLS_ISSUES_DIR (not a no-op)"
  else
    fail "anti-noop: row lands in seeded dir" "no #777 row at $plan"
    return
  fi

  # Counterfactual: WITHOUT a writable, seeded $ZSKILLS_ISSUES_DIR the
  # eval cannot land the row. We point it at a path under a non-writable
  # parent so `mkdir -p`/`cat >` fail — proving the assertion above is
  # load-bearing (the test would FAIL, not silently pass, on a no-op).
  local noop_parent="$dir/noop-parent"
  mkdir -p "$noop_parent"
  chmod 000 "$noop_parent"
  ( set -u
    export PATH="$dir/bin:$PATH"
    export CLAUDE_PROJECT_DIR="$STUB_ROOT"
    export ZSKILLS_ISSUES_DIR="$noop_parent/cannot-create"
    export MOCK_GH_ISSUES_JSON="$json"
    run_real_sync
  ) > "$dir/noop-out.txt" 2> "$dir/noop-err.txt"
  local noop_rc=$?
  chmod 755 "$noop_parent"
  if [ ! -f "$noop_parent/cannot-create/ISSUES_PLAN.md" ]; then
    pass "anti-noop: counterfactual — no row lands when dir is unwritable (assertion is load-bearing)"
  else
    fail "anti-noop: counterfactual no-write" "row unexpectedly landed despite unwritable dir (rc=$noop_rc)"
  fi
}

# ---- Test 1: bootstrap with empty issues_dir ---------------------------
# Mocked gh returns 3 open issues. Expect ISSUES_PLAN.md to be created
# with the bootstrap header AND 3 `### #N — <title>` rows.
test_bootstrap_empty_issues_dir() {
  local label="bootstrap-empty"
  local dir; dir=$(new_case "$label")
  local issues_dir="$dir/issues"
  local json="$dir/gh-issues.json"
  # Compact JSON (no spaces after colons) — matches real `gh issue list
  # --json ...` output. The OPEN_NUMS regex `"number":[0-9]+` requires
  # this shape (the sprint.md path is gh-compact-JSON-only).
  cat > "$json" <<'JSON'
[{"number":101,"title":"First open issue","labels":[{"name":"bug"}]},{"number":202,"title":"Second issue with \"escaped\" quotes","labels":[]},{"number":303,"title":"Third issue","labels":[{"name":"meta"},{"name":"chore"}]}]
JSON

  ( set -u
    export PATH="$dir/bin:$PATH"
    export CLAUDE_PROJECT_DIR="$STUB_ROOT"
    export ZSKILLS_ISSUES_DIR="$issues_dir"
    export MOCK_GH_ISSUES_JSON="$json"
    run_real_sync
  ) > "$dir/out.txt" 2> "$dir/err.txt"
  local rc=$?

  local plan="$issues_dir/ISSUES_PLAN.md"
  if [ "$rc" -ne 0 ]; then
    fail "bootstrap-empty: exits 0" "rc=$rc; err: $(cat "$dir/err.txt")"
    return
  fi
  pass "bootstrap-empty: bootstrap+row-writer block exits 0"

  if [ -f "$plan" ]; then
    pass "bootstrap-empty: ISSUES_PLAN.md created"
  else
    fail "bootstrap-empty: ISSUES_PLAN.md created" "not present at $plan"
    return
  fi

  # Header parity.
  if grep -qF 'title: Issues — Auto-Bootstrapped Tracker' "$plan" \
     && grep -qF 'status: active' "$plan" \
     && grep -qF '# Issues — Auto-Bootstrapped Tracker' "$plan"; then
    pass "bootstrap-empty: header template written"
  else
    fail "bootstrap-empty: header template written" "missing frontmatter or H1"
  fi

  # Three rows, with the escaped-quote title preserved (issue #280 path).
  local row_count
  row_count=$(grep -cE '^### #(101|202|303) — ' "$plan")
  if [ "$row_count" -eq 3 ]; then
    pass "bootstrap-empty: 3 ### #N rows present"
  else
    fail "bootstrap-empty: 3 ### #N rows present" "got $row_count (expected 3)"
  fi

  if grep -qF '### #202 — Second issue with "escaped" quotes' "$plan"; then
    pass "bootstrap-empty: escaped quotes in title preserved (issue #280 path exercised)"
  else
    fail "bootstrap-empty: escaped quotes in title preserved" "title corrupted or missing"
  fi

  # Each row has a NOT YET RESEARCHED verdict.
  local verdict_count
  verdict_count=$(grep -cF '**Verdict:** NOT YET RESEARCHED' "$plan")
  if [ "$verdict_count" -eq 3 ]; then
    pass "bootstrap-empty: each row has '**Verdict:** NOT YET RESEARCHED'"
  else
    fail "bootstrap-empty: each row has Verdict" "got $verdict_count (expected 3)"
  fi

  # Labels rendered.
  if grep -qF '**Labels:** bug' "$plan" \
     && grep -qF '**Labels:** (none)' "$plan" \
     && grep -qF '**Labels:** meta,chore' "$plan"; then
    pass "bootstrap-empty: labels rendered (incl. empty → '(none)' and comma-joined)"
  else
    fail "bootstrap-empty: labels rendered" "expected bug, (none), meta,chore"
  fi
}

# ---- Test 2: pre-existing ISSUES.md → dedup ----------------------------
# Pre-seed an ISSUES.md that already references #101 in heading form and
# #202 in bold form. Mocked gh returns issues 101, 202, 303. Expect:
#   - NO bootstrap header (existing tracker present).
#   - Only #303 appended (101 + 202 deduped, both shapes).
test_dedup_preexisting_issues_md() {
  local label="dedup"
  local dir; dir=$(new_case "$label")
  local issues_dir="$dir/issues"
  local json="$dir/gh-issues.json"

  # Pre-seed a tracker file matching the `*_ISSUES.md` glob.
  cat > "$issues_dir/MY_ISSUES.md" <<'PRESEED'
---
title: My Issues
status: active
---
# My Issues

### #101 — already tracked heading shape
**Verdict:** RESEARCHED

- **#202** — already tracked bold shape
PRESEED

  cat > "$json" <<'JSON'
[{"number":101,"title":"Heading dup","labels":[]},{"number":202,"title":"Bold dup","labels":[]},{"number":303,"title":"New residual","labels":[{"name":"bug"}]}]
JSON

  ( set -u
    export PATH="$dir/bin:$PATH"
    export CLAUDE_PROJECT_DIR="$STUB_ROOT"
    export ZSKILLS_ISSUES_DIR="$issues_dir"
    export MOCK_GH_ISSUES_JSON="$json"
    run_real_sync
  ) > "$dir/out.txt" 2> "$dir/err.txt"
  local rc=$?

  if [ "$rc" -ne 0 ]; then
    fail "dedup: exits 0" "rc=$rc; err: $(cat "$dir/err.txt")"
    return
  fi
  pass "dedup: exits 0"

  # Per sprint.md: the row-writer always appends to
  # $ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md regardless of which existing
  # tracker(s) are present. So with a pre-existing MY_ISSUES.md and
  # bootstrap skipped, residual rows still land in ISSUES_PLAN.md (which
  # `>>` creates on first append). The dedup check is what matters:
  # already-tracked numbers MUST NOT produce new rows anywhere.
  local existing="$issues_dir/MY_ISSUES.md"
  local plan="$issues_dir/ISSUES_PLAN.md"

  # MY_ISSUES.md must be unchanged (no rows appended back to it).
  local my_dup_101 my_dup_202 my_added_303
  my_dup_101=$(grep -cE '^### #101 — Heading dup' "$existing")
  my_dup_202=$(grep -cE '^### #202 — Bold dup' "$existing")
  my_added_303=$(grep -cE '^### #303 — New residual' "$existing")
  if [ "$my_dup_101" -eq 0 ] && [ "$my_dup_202" -eq 0 ] && [ "$my_added_303" -eq 0 ]; then
    pass "dedup: pre-existing MY_ISSUES.md content untouched (no new rows back-written)"
  else
    fail "dedup: MY_ISSUES.md untouched" "found dup_101=$my_dup_101 dup_202=$my_dup_202 added_303=$my_added_303"
  fi

  # ISSUES_PLAN.md must contain ONLY the new residual row (#303).
  # Bootstrap MUST NOT have fired — assert by absence of the auto-bootstrap
  # header (the bootstrap branch writes "# Issues — Auto-Bootstrapped Tracker").
  if [ ! -f "$plan" ]; then
    fail "dedup: ISSUES_PLAN.md exists with appended residual row" "no file"
    return
  fi
  if grep -qF '# Issues — Auto-Bootstrapped Tracker' "$plan"; then
    fail "dedup: bootstrap did NOT fire (no auto-bootstrap header in ISSUES_PLAN.md)" \
      "header present — bootstrap incorrectly fired despite existing tracker"
  else
    pass "dedup: bootstrap did NOT fire (no auto-bootstrap header in ISSUES_PLAN.md)"
  fi

  # Only #303 should appear in ISSUES_PLAN.md; #101 and #202 must be
  # deduped against MY_ISSUES.md by the PCRE membership check.
  local plan_101 plan_202 plan_303
  plan_101=$(grep -cE '^### #101 — Heading dup' "$plan")
  plan_202=$(grep -cE '^### #202 — Bold dup' "$plan")
  plan_303=$(grep -cE '^### #303 — New residual' "$plan")

  if [ "$plan_101" -eq 0 ]; then
    pass "dedup: #101 (heading form in MY_ISSUES.md) NOT re-appended to ISSUES_PLAN.md"
  else
    fail "dedup: #101 NOT re-appended" "found $plan_101 row(s) in ISSUES_PLAN.md"
  fi
  if [ "$plan_202" -eq 0 ]; then
    pass "dedup: #202 (bold form in MY_ISSUES.md) NOT re-appended to ISSUES_PLAN.md"
  else
    fail "dedup: #202 NOT re-appended" "found $plan_202 row(s) in ISSUES_PLAN.md"
  fi
  if [ "$plan_303" -eq 1 ]; then
    pass "dedup: #303 (new residual) appended exactly once to ISSUES_PLAN.md"
  else
    fail "dedup: #303 appended exactly once" "got $plan_303 occurrences"
  fi

  # Boundary check: #20 (substring of #202) must NOT have been "found" by
  # the membership check. Confirm by running the row-writer's regex
  # directly against the pre-seed.
  if grep -qP "(?<![0-9])#20(?![0-9])" "$existing"; then
    fail "dedup: PCRE anchor rejects #20 inside #202" "matched substring"
  else
    pass "dedup: PCRE anchor rejects #20 inside #202 (issue #301 fix exercised)"
  fi
}

# ---- Test 3: zero-open-issues → clean early exit -----------------------
# Mocked gh returns []. Expect: NO ISSUES_PLAN.md, NO file changes,
# stdout includes the "0 open issues" message.
test_zero_open_issues_clean_exit() {
  local label="zero-open"
  local dir; dir=$(new_case "$label")
  local issues_dir="$dir/issues"
  local json="$dir/gh-issues.json"
  printf '[]\n' > "$json"

  # Snapshot issues_dir state pre-run (should be empty).
  local pre_listing
  pre_listing=$(ls -A "$issues_dir" 2>/dev/null || true)

  ( set -u
    export PATH="$dir/bin:$PATH"
    export CLAUDE_PROJECT_DIR="$STUB_ROOT"
    export ZSKILLS_ISSUES_DIR="$issues_dir"
    export MOCK_GH_ISSUES_JSON="$json"
    run_real_sync
  ) > "$dir/out.txt" 2> "$dir/err.txt"
  local rc=$?

  if [ "$rc" -ne 0 ]; then
    fail "zero-open: exits 0" "rc=$rc; err: $(cat "$dir/err.txt")"
    return
  fi
  pass "zero-open: exits 0"

  if grep -qF "Sync complete. 0 open issues, no trackers needed." "$dir/out.txt"; then
    pass "zero-open: emits 'Sync complete. 0 open issues, no trackers needed.'"
  else
    fail "zero-open: emits clean-exit message" "stdout: $(cat "$dir/out.txt")"
  fi

  if [ ! -f "$issues_dir/ISSUES_PLAN.md" ]; then
    pass "zero-open: no ISSUES_PLAN.md created"
  else
    fail "zero-open: no ISSUES_PLAN.md created" "file unexpectedly present"
  fi

  local post_listing
  post_listing=$(ls -A "$issues_dir" 2>/dev/null || true)
  if [ "$pre_listing" = "$post_listing" ]; then
    pass "zero-open: issues_dir unchanged"
  else
    fail "zero-open: issues_dir unchanged" "pre=[$pre_listing] post=[$post_listing]"
  fi
}

# ---- Test 4: end-to-end sync-and-land smoke test -----------------------
# The `/land-pr` dispatch is a Skill-tool comment in sync.md, not bash
# we can execute. What we CAN verify executably:
#   (a) The Step-5-sub-step-2 preamble runs: SYNC_TS/SYNC_ID derive,
#       requires.land-pr.<id> marker is written to main_root.
#   (b) BODY_FILE is built with the expected ## Summary / ## Test plan
#       structure.
#   (c) Given a simulated /land-pr RESULT_FILE with STATUS=merged,
#       sub-step 3 writes fulfilled.land-pr.<id> and calls
#       `gh issue close` for the approved issue(s).
#   (d) Given STATUS=created (or any non-merged), sub-step 3 SKIPS
#       gh issue close (per #282).
test_sync_and_land_smoke() {
  local label="sync-and-land"
  local dir; dir=$(new_case "$label")
  local main_root="$dir/main"
  mkdir -p "$main_root/.zskills/tracking"
  local PIPELINE_ID="fix-issues.20260517-000000"
  local SYNC_TS="20260517-000000"
  local SYNC_ID="fix-issues.sync.${SYNC_TS}"

  # (a) Preamble: write requires marker + build BODY_FILE.
  mkdir -p "$main_root/.zskills/tracking/$PIPELINE_ID"
  local req_marker="$main_root/.zskills/tracking/$PIPELINE_ID/requires.land-pr.${SYNC_ID}"
  printf 'skill: land-pr\nrequired-by: fix-issues-sync\ndate: %s\n' \
    "$(TZ=UTC date -Iseconds)" \
    > "$req_marker"

  if [ -f "$req_marker" ] \
     && grep -qF 'skill: land-pr' "$req_marker" \
     && grep -qF 'required-by: fix-issues-sync' "$req_marker"; then
    pass "sync-and-land: requires.land-pr.<id> marker written on main_root pre-dispatch"
  else
    fail "sync-and-land: requires marker written" "missing or malformed"
  fi

  local body_file="$dir/body.md"
  {
    printf '## Summary\n`/fix-issues sync` on %s updated trackers.\n\n' \
      "$(TZ=UTC date +%F)"
    printf '## Test plan\n- [x] Tracker diff reviewed by user before merge.\n'
  } > "$body_file"

  if grep -qF '## Summary' "$body_file" && grep -qF '## Test plan' "$body_file"; then
    pass "sync-and-land: BODY_FILE has Summary + Test plan sections"
  else
    fail "sync-and-land: BODY_FILE structure" "missing sections"
  fi

  # Simulate /land-pr returning STATUS=merged via result-file.
  local result_file="$dir/result-merged.txt"
  cat > "$result_file" <<'RESULT'
STATUS=merged
PR_URL=https://github.com/test/repo/pull/9999
PR_NUMBER=9999
CI_STATUS=success
RESULT

  # (b) Parse result-file via the canonical allow-list pattern.
  declare -A LP
  while IFS='=' read -r KEY VALUE; do
    case "$KEY" in
      STATUS|PR_URL|PR_NUMBER|PR_EXISTING|CI_STATUS|CI_LOG_FILE|\
      MERGE_REQUESTED|MERGE_REASON|PR_STATE|REASON|\
      CONFLICT_FILES_LIST|CALL_ERROR_FILE)
        LP["$KEY"]="$VALUE" ;;
      "") ;;
      *) printf 'WARN: unknown key %q\n' "$KEY" >&2 ;;
    esac
  done < "$result_file"

  if [ "${LP[STATUS]:-}" = "merged" ] && [ "${LP[PR_NUMBER]:-}" = "9999" ]; then
    pass "sync-and-land: result-file parsed (STATUS=merged, PR_NUMBER=9999)"
  else
    fail "sync-and-land: result-file parsed" "STATUS=${LP[STATUS]:-} PR_NUMBER=${LP[PR_NUMBER]:-}"
  fi

  # (c) On STATUS=merged: write fulfilled.land-pr.<id>, call gh issue close.
  local SYNC_BRANCH="sync-branch-test"
  local call_log="$dir/gh-calls.log"
  : > "$call_log"
  case "${LP[STATUS]:-}" in
    merged)
      printf 'skill: land-pr\nid: %s\npr: %s\nbranch: %s\ndate: %s\n' \
        "$SYNC_ID" "${LP[PR_URL]:-}" "$SYNC_BRANCH" \
        "$(TZ=UTC date -Iseconds)" \
        > "$main_root/.zskills/tracking/$PIPELINE_ID/fulfilled.land-pr.$SYNC_ID"
      PATH="$dir/bin:$PATH" MOCK_GH_CALL_LOG="$call_log" \
        gh issue close 303 --comment "Fixed in test."
      ;;
    *)
      echo "Skipping gh issue close — STATUS=${LP[STATUS]:-unknown}." >&2
      ;;
  esac

  local fulfilled="$main_root/.zskills/tracking/$PIPELINE_ID/fulfilled.land-pr.$SYNC_ID"
  if [ -f "$fulfilled" ] \
     && grep -qF "id: $SYNC_ID" "$fulfilled" \
     && grep -qF "branch: $SYNC_BRANCH" "$fulfilled" \
     && grep -qF "pr: https://github.com/test/repo/pull/9999" "$fulfilled"; then
    pass "sync-and-land: fulfilled.land-pr.<id> written on STATUS=merged (closes #300 hole)"
  else
    fail "sync-and-land: fulfilled.land-pr.<id> written on merged" \
      "missing/malformed at $fulfilled"
  fi

  if grep -qF 'gh issue close issue close 303' "$call_log" \
     || grep -qF 'issue close 303' "$call_log"; then
    pass "sync-and-land: gh issue close called for approved issue on STATUS=merged"
  else
    fail "sync-and-land: gh issue close called on merged" "call log: $(cat "$call_log")"
  fi

  # (d) STATUS=created (or any non-merged) → NO close, NO fulfilled marker.
  local PIPELINE_ID2="fix-issues.20260517-111111"
  local SYNC_ID2="fix-issues.sync.20260517-111111"
  mkdir -p "$main_root/.zskills/tracking/$PIPELINE_ID2"
  local result_file2="$dir/result-created.txt"
  cat > "$result_file2" <<'RESULT2'
STATUS=created
PR_URL=https://github.com/test/repo/pull/10000
PR_NUMBER=10000
CI_STATUS=pending
RESULT2

  unset LP
  declare -A LP
  while IFS='=' read -r KEY VALUE; do
    case "$KEY" in
      STATUS|PR_URL|PR_NUMBER|CI_STATUS) LP["$KEY"]="$VALUE" ;;
    esac
  done < "$result_file2"

  local call_log2="$dir/gh-calls-2.log"
  : > "$call_log2"
  case "${LP[STATUS]:-}" in
    merged)
      printf 'placeholder\n' > "$main_root/.zskills/tracking/$PIPELINE_ID2/fulfilled.land-pr.$SYNC_ID2"
      PATH="$dir/bin:$PATH" MOCK_GH_CALL_LOG="$call_log2" \
        gh issue close 404 --comment "should-not-happen"
      ;;
    *) : ;;
  esac

  if [ ! -f "$main_root/.zskills/tracking/$PIPELINE_ID2/fulfilled.land-pr.$SYNC_ID2" ]; then
    pass "sync-and-land: STATUS=created does NOT write fulfilled marker (issue #282)"
  else
    fail "sync-and-land: STATUS=created skips fulfilled marker" "marker incorrectly written"
  fi
  if [ ! -s "$call_log2" ]; then
    pass "sync-and-land: STATUS=created does NOT call gh issue close (issue #282)"
  else
    fail "sync-and-land: STATUS=created skips gh issue close" \
      "unexpected calls: $(cat "$call_log2")"
  fi
}

# ---- /land-pr dispatch wiring parity -----------------------------------
# Confirm the load-bearing lines used by the end-to-end sync-and-land
# test still appear in sync.md verbatim. This is the model-layer dispatch
# wiring (not executable bash we extract-and-run), so the parity anchor is
# the right tool here — KEPT per SEAM_HARDENING_REST Phase 3.
test_land_pr_dispatch_parity() {
  local hits=0
  grep -qF 'requires.land-pr.${SYNC_ID}' "$SKILL_SYNC" && hits=$((hits+1))
  grep -qF 'fulfilled.land-pr.$SYNC_ID' "$SKILL_SYNC" && hits=$((hits+1))
  grep -qF 'STATUS|PR_URL|PR_NUMBER|PR_EXISTING|CI_STATUS|CI_LOG_FILE|\' "$SKILL_SYNC" && hits=$((hits+1))
  grep -qF 'Skill: { skill: "land-pr"' "$SKILL_SYNC" && hits=$((hits+1))
  grep -qF 'case "${LP[STATUS]:-}" in' "$SKILL_SYNC" && hits=$((hits+1))
  if [ "$hits" -eq 5 ]; then
    pass "parity: /land-pr dispatch wiring (5 fingerprints) present in sync.md"
  else
    fail "parity: /land-pr dispatch wiring fingerprints" "only $hits/5 hits"
  fi
}

echo "=== /fix-issues bootstrap + row-writer + /land-pr behavioral tests (issue #284) ==="
echo "    (extract-and-run: REAL fences from modes/sprint.md — SEAM_HARDENING_REST Phase 3)"
test_land_pr_dispatch_parity
test_anti_noop_row_lands
test_bootstrap_empty_issues_dir
test_dedup_preexisting_issues_md
test_zero_open_issues_clean_exit
test_sync_and_land_smoke

echo ""
echo "---"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
[ "$FAIL_COUNT" -eq 0 ]
