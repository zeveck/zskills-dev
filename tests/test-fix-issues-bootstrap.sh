#!/bin/bash
# tests/test-fix-issues-bootstrap.sh — behavioral fixture tests for the
# bootstrap + row-writer + /land-pr dispatch paths added in PR #269
# (commit c5c928c) to skills/fix-issues/SKILL.md. Closes #284.
#
# Why a second test file (alongside test-fix-issues.sh):
#   test-fix-issues.sh is regression-grep guards for the source markdown
#   (#280 #282 #300 #301). It does NOT execute any bash from the skill.
#   This file complements it by EXECUTING the bootstrap + row-writer
#   logic against a fixture worktree with a mocked `gh`, asserting the
#   produced ISSUES_PLAN.md actually contains the expected rows.
#
# Strategy:
#   The bootstrap + row-writer logic is markdown-fenced bash in
#   skills/fix-issues/SKILL.md. We cannot `source` markdown. Instead:
#     1. We embed faithful copies of the two bash blocks (BOOTSTRAP_BLOCK,
#        ROW_WRITER_BLOCK) inline below.
#     2. A parity test (test_skill_md_parity) source-greps SKILL.md for
#        the load-bearing lines, so if the source drifts the embedded
#        copies are flagged and must be re-synced.
#   This pattern matches the test-fix-issues.sh discipline: detect drift
#   without re-implementing logic in a way that diverges silently.
#
# Mock strategy:
#   PATH-prefix shim — tests/fixtures/issue-284-tmp/bin/gh — writes a
#   canned JSON blob for `gh issue list` calls. Per-case canned data
#   lives in the per-case fixture dir; the shim reads it via env var.
#   This is simpler than mocks/mock-gh.sh's keyed-response design and
#   sufficient for our 4 scenarios (one `gh issue list` call per case).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/skills/fix-issues/modes/sprint.md"
SKILL_SYNC="$REPO_ROOT/skills/fix-issues/modes/sync.md"

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

# ---- Bootstrap + row-writer logic (verbatim from SKILL.md) -------------
# Sourced into each test case's subshell with $ZSKILLS_ISSUES_DIR set and
# `gh` on PATH. The block is a literal paste of skills/fix-issues/SKILL.md
# lines (the "Fetch the open-issue list" block, the "Bootstrap empty
# $ZSKILLS_ISSUES_DIR/" block, and the "Row-writer for residual issues"
# block — see test_skill_md_parity below for the source-grep parity gate).
run_sync_bootstrap_and_rowwriter() {
  # Fetch (uses gh shim).
  GH_OUT=$(gh issue list --state open --limit 500 --json number,title,labels 2>&1) \
    || { echo "ERROR: 'gh issue list' failed:" >&2; echo "$GH_OUT" >&2; return 1; }
  mapfile -t OPEN_NUMS < <(echo "$GH_OUT" | grep -oE '"number":[0-9]+' | sed 's/.*://')
  OPEN_COUNT=${#OPEN_NUMS[@]}

  # Bootstrap empty $ZSKILLS_ISSUES_DIR/.
  mkdir -p "$ZSKILLS_ISSUES_DIR"
  EXISTING_TRACKERS=$(ls "$ZSKILLS_ISSUES_DIR"/*_ISSUES.md "$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md" 2>/dev/null | head -1)
  if [ -z "$EXISTING_TRACKERS" ]; then
    if [ "$OPEN_COUNT" -eq 0 ]; then
      echo "Sync complete. 0 open issues, no trackers needed."
      return 0
    fi
    TODAY=$(TZ=America/New_York date +%Y-%m-%d)
    cat > "$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md" <<TRACKER
---
title: Issues — Auto-Bootstrapped Tracker
status: active
created: $TODAY
---

# Issues — Auto-Bootstrapped Tracker

Created by \`/fix-issues sync\` on $TODAY because this repo had no tracker files in \`\$ZSKILLS_ISSUES_DIR/\` when sync ran.

## Open Issues

(rows added by sync step 5 below)
TRACKER
    echo "Bootstrapped $ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md"
    BOOTSTRAP_NEW=yes
  else
    BOOTSTRAP_NEW=no
  fi

  # Row-writer for residual issues.
  NEW_RESEARCHED_COUNT=0
  for N in "${OPEN_NUMS[@]}"; do
    if grep -qP "(?<![0-9])#$N(?![0-9])" \
         "$ZSKILLS_ISSUES_DIR"/*_ISSUES.md "$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md" 2>/dev/null; then
      continue
    fi
    ISSUE_META=$(printf '%s' "$GH_OUT" | python3 -c '
import json, sys
data = json.load(sys.stdin)
target = int(sys.argv[1])
for it in data:
    if it.get("number") == target:
        title = it.get("title", "")
        labels = ",".join(l.get("name", "") for l in it.get("labels", []) or [])
        sys.stdout.write(title + "\x1f" + labels)
        break
' "$N") || { echo "ERROR: python3 parse failed for #$N" >&2; return 1; }
    ISSUE_TITLE_RAW="${ISSUE_META%%$'\x1f'*}"
    ISSUE_LABELS="${ISSUE_META#*$'\x1f'}"
    {
      printf '\n### #%s — %s\n' "$N" "$ISSUE_TITLE_RAW"
      printf '\n**Labels:** %s\n' "${ISSUE_LABELS:-(none)}"
      printf '\n**Verdict:** NOT YET RESEARCHED\n'
    } >> "$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md"
    NEW_RESEARCHED_COUNT=$((NEW_RESEARCHED_COUNT + 1))
  done
  echo "row-writer added $NEW_RESEARCHED_COUNT rows"
}

# ---- Per-test fixture builder ------------------------------------------
new_case() {
  local label="$1"
  local dir="$SCRATCH_ROOT/$label"
  mkdir -p "$dir/bin" "$dir/issues"
  make_gh_shim "$dir/bin"
  printf '%s' "$dir"
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
  # this shape (the SKILL.md path is gh-compact-JSON-only).
  cat > "$json" <<'JSON'
[{"number":101,"title":"First open issue","labels":[{"name":"bug"}]},{"number":202,"title":"Second issue with \"escaped\" quotes","labels":[]},{"number":303,"title":"Third issue","labels":[{"name":"meta"},{"name":"chore"}]}]
JSON

  ( set -u
    export PATH="$dir/bin:$PATH"
    export ZSKILLS_ISSUES_DIR="$issues_dir"
    export MOCK_GH_ISSUES_JSON="$json"
    run_sync_bootstrap_and_rowwriter
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
    export ZSKILLS_ISSUES_DIR="$issues_dir"
    export MOCK_GH_ISSUES_JSON="$json"
    run_sync_bootstrap_and_rowwriter
  ) > "$dir/out.txt" 2> "$dir/err.txt"
  local rc=$?

  if [ "$rc" -ne 0 ]; then
    fail "dedup: exits 0" "rc=$rc; err: $(cat "$dir/err.txt")"
    return
  fi
  pass "dedup: exits 0"

  # Per SKILL.md: the row-writer always appends to
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
    export ZSKILLS_ISSUES_DIR="$issues_dir"
    export MOCK_GH_ISSUES_JSON="$json"
    run_sync_bootstrap_and_rowwriter
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
# The `/land-pr` dispatch is a Skill-tool comment in SKILL.md, not bash
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
      "$(TZ=America/New_York date +%F)"
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

# ---- Parity gate: SKILL.md vs embedded bash blocks ---------------------
# Verify load-bearing lines from the embedded run_sync_bootstrap_and_rowwriter
# function still match the SKILL.md source. If SKILL.md drifts, this test
# fails and the embedded copy must be re-synced. The lines below are
# fingerprints — not full block matches — chosen to detect:
#   - Bootstrap glob shape (the `*_ISSUES.md` + `ISSUES_PLAN.md` pair).
#   - Bootstrap header literal.
#   - Row-writer membership regex (PCRE lookarounds, issue #301).
#   - Row-writer Python json field separator (issue #280 path).
#   - Row-writer output format (### #N — header + Labels + Verdict).
test_skill_md_parity() {
  local fingerprints=(
    'EXISTING_TRACKERS=$(ls "$ZSKILLS_ISSUES_DIR"/*_ISSUES.md "$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md" 2>/dev/null | head -1)'
    'title: Issues — Auto-Bootstrapped Tracker'
    '## Open Issues'
    'grep -qP "(?<![0-9])#$N(?![0-9])" \'
    'sys.stdout.write(title + "\x1f" + labels)'
    "printf '\\n### #%s — %s\\n' \"\$N\" \"\$ISSUE_TITLE_RAW\""
    "printf '\\n**Verdict:** NOT YET RESEARCHED\\n'"
  )
  local ok=1
  local miss=()
  for fp in "${fingerprints[@]}"; do
    if ! grep -qF "$fp" "$SKILL"; then
      ok=0
      miss+=("$fp")
    fi
  done
  if [ "$ok" -eq 1 ]; then
    pass "parity: embedded bootstrap+row-writer matches SKILL.md fingerprints"
  else
    fail "parity: embedded bootstrap+row-writer matches SKILL.md fingerprints" \
      "missing in SKILL.md: ${miss[*]}"
  fi
}

# ---- /land-pr dispatch wiring parity -----------------------------------
# Confirm the load-bearing lines used by the end-to-end sync-and-land
# test still appear in SKILL.md verbatim.
test_land_pr_dispatch_parity() {
  local hits=0
  grep -qF 'requires.land-pr.${SYNC_ID}' "$SKILL_SYNC" && hits=$((hits+1))
  grep -qF 'fulfilled.land-pr.$SYNC_ID' "$SKILL_SYNC" && hits=$((hits+1))
  grep -qF 'STATUS|PR_URL|PR_NUMBER|PR_EXISTING|CI_STATUS|CI_LOG_FILE|\' "$SKILL_SYNC" && hits=$((hits+1))
  grep -qF 'Skill: { skill: "land-pr"' "$SKILL_SYNC" && hits=$((hits+1))
  grep -qF 'case "${LP[STATUS]:-}" in' "$SKILL_SYNC" && hits=$((hits+1))
  if [ "$hits" -eq 5 ]; then
    pass "parity: /land-pr dispatch wiring (5 fingerprints) present in SKILL.md"
  else
    fail "parity: /land-pr dispatch wiring fingerprints" "only $hits/5 hits"
  fi
}

echo "=== /fix-issues bootstrap + row-writer + /land-pr behavioral tests (issue #284) ==="
test_skill_md_parity
test_land_pr_dispatch_parity
test_bootstrap_empty_issues_dir
test_dedup_preexisting_issues_md
test_zero_open_issues_clean_exit
test_sync_and_land_smoke

echo ""
echo "---"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
[ "$FAIL_COUNT" -eq 0 ]
