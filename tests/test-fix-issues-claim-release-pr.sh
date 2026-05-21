#!/bin/bash
# tests/test-fix-issues-claim-release-pr.sh — T2.2 + T2.3 from
# plans/fix-issues-claims.md Phase 2.
#
# Exercises the W2.6a release/HOLD logic over the 10 reachable
# LAND_OUTCOME values plus the unknown fallback and the `monitored`
# negative-control case (DA3.1: monitored is a STATUS not LAND_OUTCOME).
#
# Per LAND_OUTCOME:
#   merged|pr-ready|pr-ci-failing|rebase-conflict|rebase-failed|
#   push-failed|create-failed|monitor-failed|merge-failed   →  RELEASE
#   created                                                  →  HOLD
#   *                                                        →  HOLD (default)
#
# DA3.1 guard: `monitored` must route to the default/HOLD arm because
# it is not in the explicit case list.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAIM_SH="$REPO_ROOT/skills/fix-issues/scripts/claim-issue.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SCRATCH_ROOT="/tmp/test-fix-issues-claim-release-pr-$$"
cleanup() {
  if [ -d "$SCRATCH_ROOT" ]; then
    find "$SCRATCH_ROOT" -type d -exec chmod 0755 {} + 2>/dev/null || true
    find "$SCRATCH_ROOT" -mindepth 1 -delete 2>/dev/null || true
    rmdir "$SCRATCH_ROOT" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM
mkdir -p "$SCRATCH_ROOT"

make_repo() {
  local repo="$1"
  mkdir -p "$repo"
  (cd "$repo" && git init -q && git config user.email "t@t" && git config user.name "t" \
    && git commit --allow-empty -q -m "init") || return 1
}

# Render the W2.6a release/HOLD case fragment as an executable script.
# Mirrors modes/pr.md verbatim modulo $ISSUE_NUM/$LAND_OUTCOME/$PIPELINE_ID
# being passed in.
render_release_fragment() {
  cat <<'FRAGMENT'
case "$LAND_OUTCOME" in
  merged|pr-ready|pr-ci-failing|rebase-conflict|rebase-failed|push-failed|create-failed|monitor-failed|merge-failed)
    bash "$CLAIM_HELPER" release "$ISSUE_NUM" --require-pipeline "$PIPELINE_ID" \
      || echo "fix-issues: claim release for #$ISSUE_NUM returned non-zero (continuing)" >&2 ;;
  created)
    echo "fix-issues: holding claim for #$ISSUE_NUM (LAND_OUTCOME=created — PR is in flight); TTL will sweep" >&2 ;;
  *)
    echo "fix-issues: unknown LAND_OUTCOME=$LAND_OUTCOME for #$ISSUE_NUM; defaulting to HOLD (TTL will sweep)" >&2 ;;
esac
FRAGMENT
}

# Run one case: pre-create a claim, drive the fragment, return RELEASED or HELD.
run_case() {
  local outcome="$1"
  local rootname="$2"
  local root="$SCRATCH_ROOT/$rootname"
  make_repo "$root" || { echo "make_repo failed for $root"; return 2; }
  # Pre-create the claim (this pipeline holds it).
  mkdir -p "$root/.zskills/claims/issue-42"
  cat > "$root/.zskills/claims/issue-42/claim.json" <<JSON
{"schema_version":1,"pipeline_id":"mine","sprint_id":"mine-s","issue":42,"started_at":"2026-05-21T00:00:00+00:00"}
JSON

  local script="$root/script.sh"
  {
    echo "ISSUE_NUM=42"
    echo "PIPELINE_ID=mine"
    echo "LAND_OUTCOME=$outcome"
    echo "CLAIM_HELPER=\"$CLAIM_SH\""
    render_release_fragment
  } > "$script"

  local stderr_file="$root/stderr.txt"
  (cd "$root" && bash "$script") 2> "$stderr_file" >/dev/null
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "fragment-rc=$rc (LAND_OUTCOME=$outcome)" >&2
    return 2
  fi

  if [ -d "$root/.zskills/claims/issue-42" ]; then
    echo "HELD"
  else
    echo "RELEASED"
  fi
  # Stderr file is at known path; callers read it directly via the same
  # root name (CASE_STDERR via subshell capture isn't preserved).
  return 0
}

# Read stderr captured by run_case for a given rootname.
case_stderr_for() {
  local rootname="$1"
  cat "$SCRATCH_ROOT/$rootname/stderr.txt" 2>/dev/null || true
}

echo "=== T2.2 + T2.3 PR-mode release case-arms ==="

# ── 10 reachable LAND_OUTCOMEs from modes/pr.md ──
# Per plan D3 + DA3.1: 9 release, 1 HOLD (created).
declare -A EXPECTED
EXPECTED[merged]=RELEASED
EXPECTED[pr-ready]=RELEASED
EXPECTED[pr-ci-failing]=RELEASED
EXPECTED[rebase-conflict]=RELEASED
EXPECTED[rebase-failed]=RELEASED
EXPECTED[push-failed]=RELEASED
EXPECTED[create-failed]=RELEASED
EXPECTED[monitor-failed]=RELEASED
EXPECTED[merge-failed]=RELEASED
EXPECTED[created]=HELD

i=0
for outcome in merged pr-ready pr-ci-failing rebase-conflict rebase-failed push-failed create-failed monitor-failed merge-failed created; do
  i=$((i+1))
  result=$(run_case "$outcome" "case-$i-$outcome")
  if [ "$result" = "${EXPECTED[$outcome]}" ]; then
    pass "T2.2 LAND_OUTCOME=$outcome -> ${EXPECTED[$outcome]}"
  else
    fail "T2.2 LAND_OUTCOME=$outcome" "expected=${EXPECTED[$outcome]} got=$result"
  fi
done

# ── T2.3 unknown-LAND_OUTCOME fallback: garbage → HOLD + stderr warning ──
i=$((i+1))
case_name="case-$i-garbage"
result=$(run_case "garbage" "$case_name")
warn_present=0
case_stderr_for "$case_name" | grep -q 'unknown LAND_OUTCOME=garbage' && warn_present=1
if [ "$result" = "HELD" ] && [ "$warn_present" -eq 1 ]; then
  pass "T2.3 unknown LAND_OUTCOME=garbage → HOLD + stderr warning"
else
  fail "T2.3 unknown LAND_OUTCOME=garbage" "result=$result warn_present=$warn_present"
fi

# ── DA3.1 guard: monitored is a STATUS, not LAND_OUTCOME ──
# If it ever reaches the case, it must fall to the HOLD default.
i=$((i+1))
case_name="case-$i-monitored"
result=$(run_case "monitored" "$case_name")
warn_present=0
case_stderr_for "$case_name" | grep -q 'unknown LAND_OUTCOME=monitored' && warn_present=1
if [ "$result" = "HELD" ] && [ "$warn_present" -eq 1 ]; then
  pass "T2.2 DA3.1 guard: monitored (unreachable) falls to HOLD default + stderr warning"
else
  fail "T2.2 DA3.1 guard monitored" "result=$result warn_present=$warn_present"
fi

# ───────────────────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────────────────
echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (%d total)\033[0m\n' "$PASS_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (%d total)\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit 1
fi
