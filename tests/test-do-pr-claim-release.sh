#!/bin/bash
# tests/test-do-pr-claim-release.sh — issue #864
#
# Asserts the /do pr explicit-finalize claim release/HOLD logic at
# skills/do/modes/pr.md mirrors the fix-issues/modes/pr.md pattern:
#
#   merged                → RELEASE (work is durably on main)
#   pr-ready | created    → HOLD (PR is OPEN; concurrent fix-issues must
#                           not re-claim and duplicate the fix)
#   pr-ci-failing,
#   rebase-conflict,
#   auto-rebase-conflict,
#   auto-rebase-blocked,
#   behind-thrash,
#   *-failed              → RELEASE (PR is dead-on-arrival)
#   <unknown>             → HOLD (default — safer than auto-release)
#
# Background: previously /do pr released the claim on
# merged|created|pr-ready uniformly, dropping the claim during the
# unbounded human-review window between PR open and merge. A concurrent
# /fix-issues cron could re-claim and duplicate the fix.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAIM_SH="$REPO_ROOT/skills/fix-issues/scripts/claim-issue.sh"
DO_PR_MD="$REPO_ROOT/skills/do/modes/pr.md"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SCRATCH_ROOT="/tmp/test-do-pr-claim-release-$$"
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

# Render the /do pr release/HOLD case fragment as an executable script.
# Mirrors the case-arm structure from skills/do/modes/pr.md verbatim
# (modulo $ISSUE_NUM/$LAND_OUTCOME/$PIPELINE_ID/$CLAIM_HELPER passed in).
render_release_fragment() {
  cat <<'FRAGMENT'
case "$LAND_OUTCOME" in
  merged)
    bash "$CLAIM_HELPER" release "$ISSUE_NUM" --require-pipeline "$PIPELINE_ID" \
      || echo "do: claim release for #$ISSUE_NUM returned non-zero (continuing)" >&2 ;;
  pr-ready|created)
    echo "do: holding claim for #$ISSUE_NUM (LAND_OUTCOME=$LAND_OUTCOME — PR is in flight awaiting human review/merge); /do is one-shot so the claim is reaped manually via 'bash $CLAIM_HELPER release $ISSUE_NUM' if the PR never lands" >&2 ;;
  pr-ci-failing|rebase-conflict|auto-rebase-conflict|auto-rebase-blocked|behind-thrash|rebase-failed|push-failed|create-failed|monitor-failed|merge-failed|unknown-status-*)
    bash "$CLAIM_HELPER" release "$ISSUE_NUM" --require-pipeline "$PIPELINE_ID" \
      || echo "do: claim release for #$ISSUE_NUM returned non-zero (continuing)" >&2 ;;
  *)
    echo "do: unknown LAND_OUTCOME=$LAND_OUTCOME for #$ISSUE_NUM; defaulting to HOLD" >&2 ;;
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
{"schema_version":1,"pipeline_id":"do.task-x","sprint_id":"do.task-x","issue":42,"started_at":"2026-05-21T00:00:00+00:00"}
JSON

  local script="$root/script.sh"
  {
    echo "ISSUE_NUM=42"
    echo "PIPELINE_ID=do.task-x"
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
  return 0
}

case_stderr_for() {
  local rootname="$1"
  cat "$SCRATCH_ROOT/$rootname/stderr.txt" 2>/dev/null || true
}

echo "=== /do pr LAND_OUTCOME → release/HOLD (issue #864) ==="

# Required behaviors per acceptance criteria:
declare -A EXPECTED
# Release group:
EXPECTED[merged]=RELEASED
# HOLD group (issue #864 fix — the bug being closed):
EXPECTED[pr-ready]=HELD
EXPECTED[created]=HELD
# Terminal-failure release group:
EXPECTED[pr-ci-failing]=RELEASED
EXPECTED[rebase-conflict]=RELEASED
EXPECTED[auto-rebase-conflict]=RELEASED
EXPECTED[auto-rebase-blocked]=RELEASED
EXPECTED[behind-thrash]=RELEASED
EXPECTED[rebase-failed]=RELEASED
EXPECTED[push-failed]=RELEASED
EXPECTED[create-failed]=RELEASED

i=0
for outcome in merged pr-ready created pr-ci-failing rebase-conflict auto-rebase-conflict auto-rebase-blocked behind-thrash rebase-failed push-failed create-failed; do
  i=$((i+1))
  result=$(run_case "$outcome" "case-$i-$outcome")
  if [ "$result" = "${EXPECTED[$outcome]}" ]; then
    pass "LAND_OUTCOME=$outcome -> ${EXPECTED[$outcome]}"
  else
    fail "LAND_OUTCOME=$outcome" "expected=${EXPECTED[$outcome]} got=$result"
  fi
done

# HOLD-arm log-line shape: pr-ready and created emit an in-flight message
# naming the manual-reap recovery command (mirrors fix-issues/modes/pr.md
# created-arm convention).
i=$((i+1))
case_name="case-$i-pr-ready-log"
_=$(run_case "pr-ready" "$case_name")
stderr=$(case_stderr_for "$case_name")
if echo "$stderr" | grep -q "holding claim for #42" \
   && echo "$stderr" | grep -q "in flight" \
   && echo "$stderr" | grep -q "claim-issue.sh release"; then
  pass "pr-ready HOLD log line shape (in-flight + manual-reap command)"
else
  fail "pr-ready HOLD log line shape" "stderr=$stderr"
fi

# Unknown-LAND_OUTCOME fallback: garbage → HOLD + stderr warning
# (matches fix-issues T2.3 — safer default than silent release).
i=$((i+1))
case_name="case-$i-garbage"
result=$(run_case "garbage" "$case_name")
warn_present=0
case_stderr_for "$case_name" | grep -q 'unknown LAND_OUTCOME=garbage' && warn_present=1
if [ "$result" = "HELD" ] && [ "$warn_present" -eq 1 ]; then
  pass "unknown LAND_OUTCOME=garbage → HOLD + stderr warning"
else
  fail "unknown LAND_OUTCOME=garbage" "result=$result warn_present=$warn_present"
fi

# unknown-status-* glob match (the unknown-STATUS fall-through from
# modes/pr.md:399 sets LAND_OUTCOME=unknown-status-$STATUS).
i=$((i+1))
case_name="case-$i-unknown-status"
result=$(run_case "unknown-status-foo" "$case_name")
if [ "$result" = "RELEASED" ]; then
  pass "LAND_OUTCOME=unknown-status-foo -> RELEASED (terminal-failure glob)"
else
  fail "LAND_OUTCOME=unknown-status-foo" "expected=RELEASED got=$result"
fi

# Source check: the fragment under test must actually appear in the
# shipped skill (prevents test/source drift).
if grep -q 'pr-ready|created)' "$DO_PR_MD" \
   && grep -q 'holding claim for #' "$DO_PR_MD" \
   && grep -q 'merged)$' "$DO_PR_MD"; then
  pass "skills/do/modes/pr.md contains the split case arms"
else
  fail "skills/do/modes/pr.md split case arms" "expected three-group case missing from source"
fi

# Dual-lane path discipline (issue #893): the HOLD-arm stderr manual-reap
# instruction must reference the resolved $CLAIM_HELPER, never the legacy
# single-lane literal `skills/fix-issues/scripts/claim-issue.sh` (which does
# not exist on the plugin lane). Same defect class as #832, in stderr prose.
if grep -q "reaped manually via 'bash \$CLAIM_HELPER release" "$DO_PR_MD" \
   && ! grep -q 'skills/fix-issues/scripts/claim-issue.sh' "$DO_PR_MD"; then
  pass "skills/do/modes/pr.md HOLD-arm stderr uses \$CLAIM_HELPER (no hardcoded single-lane path, #893)"
else
  fail "skills/do/modes/pr.md HOLD-arm dual-lane path" "expected \$CLAIM_HELPER in HOLD-arm stderr and no hardcoded skills/fix-issues/scripts/claim-issue.sh literal"
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
