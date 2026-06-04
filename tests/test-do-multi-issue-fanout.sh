#!/bin/bash
# Tests for the multi-issue claim acquire/release fan-out introduced in
# PR #863 (skills/do). Exercises:
#
#   1. Multi-issue acquire fans out N independent claim acquires via
#      claim-issue.sh — each issue gets its own claim dir.
#   2. Partial-acquire rollback: when the K-th acquire returns rc=10
#      (foreign-held), the loop releases issues 1..K-1 acquired earlier
#      so this pipeline leaves no orphaned partial claims.
#   3. Multi-issue release fans out N independent releases, each
#      idempotent (re-running release on an already-released claim is a
#      no-op per claim-issue.sh).
#
# These tests drive claim-issue.sh directly rather than running the full
# /do lifecycle — the loop semantics under test are pure
# bash that the SKILL.md fences inline verbatim.
#
# Run from repo root: bash tests/test-do-multi-issue-fanout.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAIM_HELPER="$REPO_ROOT/skills/fix-issues/scripts/claim-issue.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '  \033[32mPASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# Each test runs in an isolated temp git repo so claim-issue.sh's
# MAIN_ROOT resolution (via git rev-parse --git-common-dir) lands somewhere
# we can clean up.
make_repo() {
  local d
  d=$(mktemp -d -t "zskills-multi-issue-fanout-XXXXXX")
  (
    cd "$d" || exit 1
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test"
  )
  printf '%s' "$d"
}

cleanup_dirs=()
trap 'for d in "${cleanup_dirs[@]:-}"; do [ -d "$d" ] && rm -rf "$d"; done' EXIT

echo "=== Multi-issue acquire fan-out ==="

REPO_A=$(make_repo)
cleanup_dirs+=("$REPO_A")
cd "$REPO_A" || exit 1

ISSUE_NUMS=(832 833 834)
PIPELINE_ID="do.test-multi-832"
_ACQUIRED=()
ACQ_RC=0
for ISSUE_NUM in "${ISSUE_NUMS[@]}"; do
  bash "$CLAIM_HELPER" acquire "$ISSUE_NUM" --pipeline-id "$PIPELINE_ID" --sprint-id "$PIPELINE_ID" 2>/dev/null
  ACQ_RC=$?
  if [ "$ACQ_RC" -eq 0 ]; then
    _ACQUIRED+=("$ISSUE_NUM")
  else
    break
  fi
done

if [ "${#_ACQUIRED[@]}" -eq 3 ]; then
  pass "1a fan-out acquire: all 3 issues acquired"
else
  fail "1a fan-out acquire: expected 3 acquired, got ${#_ACQUIRED[@]}"
fi

# Verify each claim dir exists.
expected_count=0
for N in 832 833 834; do
  if [ -d "$REPO_A/.zskills/claims/issue-$N" ] && [ -f "$REPO_A/.zskills/claims/issue-$N/claim.json" ]; then
    expected_count=$((expected_count + 1))
  fi
done
if [ "$expected_count" -eq 3 ]; then
  pass "1b fan-out acquire: 3 claim dirs+claim.json created on disk"
else
  fail "1b fan-out acquire: expected 3 claim files, got $expected_count"
fi

echo ""
echo "=== Partial-acquire rollback on rc=10 (foreign-held) ==="

REPO_B=$(make_repo)
cleanup_dirs+=("$REPO_B")
cd "$REPO_B" || exit 1

# Foreign pipeline holds issue 901.
bash "$CLAIM_HELPER" acquire 901 --pipeline-id "foreign.pipeline" --sprint-id "foreign.pipeline" 2>/dev/null
foreign_rc=$?
if [ "$foreign_rc" -ne 0 ]; then
  fail "2pre foreign holder setup: expected rc=0 on fresh acquire, got $foreign_rc"
fi

# Our pipeline tries to claim 900, 901, 902 — 901 is foreign-held so we
# should acquire 900, fail on 901 with rc=10, then roll back 900.
ISSUE_NUMS=(900 901 902)
PIPELINE_ID="do.test-rollback"
_ACQUIRED=()
ACQ_RC=0
FAILED_AT=""
for ISSUE_NUM in "${ISSUE_NUMS[@]}"; do
  bash "$CLAIM_HELPER" acquire "$ISSUE_NUM" --pipeline-id "$PIPELINE_ID" --sprint-id "$PIPELINE_ID" 2>/dev/null
  ACQ_RC=$?
  case "$ACQ_RC" in
    0) _ACQUIRED+=("$ISSUE_NUM") ;;
    *)
      FAILED_AT="$ISSUE_NUM"
      # Rollback: release everything this pipeline grabbed earlier.
      for _RB in "${_ACQUIRED[@]}"; do
        bash "$CLAIM_HELPER" release "$_RB" --require-pipeline "$PIPELINE_ID" 2>/dev/null || true
      done
      break ;;
  esac
done

if [ "$ACQ_RC" -eq 10 ] && [ "$FAILED_AT" = "901" ]; then
  pass "2a rollback: hit rc=10 on foreign-held issue 901 (as expected)"
else
  fail "2a rollback: expected rc=10 on #901, got rc=$ACQ_RC failed_at='$FAILED_AT'"
fi

# Verify 900 was acquired then rolled back (no claim dir remains for our
# pipeline). Foreign 901 still intact.
if [ -d "$REPO_B/.zskills/claims/issue-900" ]; then
  fail "2b rollback: issue-900 claim dir still exists — rollback didn't release"
else
  pass "2b rollback: issue-900 claim released (no leak)"
fi

if [ -d "$REPO_B/.zskills/claims/issue-901" ]; then
  pass "2c rollback: foreign issue-901 claim intact (not stolen)"
else
  fail "2c rollback: foreign issue-901 claim missing — rollback overreached"
fi

# Verify our pipeline-id is not stamped on 901's claim.json.
if grep -q '"pipeline_id": "foreign.pipeline"' "$REPO_B/.zskills/claims/issue-901/claim.json" 2>/dev/null; then
  pass "2d rollback: issue-901 claim.json still owned by foreign pipeline"
else
  fail "2d rollback: issue-901 claim.json missing or pipeline_id wrong"
fi

# Issue 902 was never attempted (loop broke at 901).
if [ -d "$REPO_B/.zskills/claims/issue-902" ]; then
  fail "2e rollback: issue-902 claim dir exists — loop did not break at 901"
else
  pass "2e rollback: issue-902 never acquired (loop broke at 901)"
fi

echo ""
echo "=== Multi-issue release fan-out (idempotent) ==="

REPO_C=$(make_repo)
cleanup_dirs+=("$REPO_C")
cd "$REPO_C" || exit 1

ISSUE_NUMS=(700 701 702)
PIPELINE_ID="do.test-release"
# Acquire all three.
for ISSUE_NUM in "${ISSUE_NUMS[@]}"; do
  bash "$CLAIM_HELPER" acquire "$ISSUE_NUM" --pipeline-id "$PIPELINE_ID" --sprint-id "$PIPELINE_ID" 2>/dev/null
done

# Release fan-out (1st pass).
release_failures=0
for _ISSUE_N in "${ISSUE_NUMS[@]}"; do
  bash "$CLAIM_HELPER" release "$_ISSUE_N" --require-pipeline "$PIPELINE_ID" 2>/dev/null
  rc=$?
  if [ "$rc" -ne 0 ]; then
    release_failures=$((release_failures + 1))
  fi
done

if [ "$release_failures" -eq 0 ]; then
  pass "3a release fan-out: all 3 releases succeeded (rc=0)"
else
  fail "3a release fan-out: $release_failures release(s) failed on 1st pass"
fi

# Verify all claim dirs are gone.
for N in 700 701 702; do
  if [ -d "$REPO_C/.zskills/claims/issue-$N" ]; then
    fail "3b release fan-out: issue-$N claim dir still exists after release"
  else
    pass "3b release fan-out: issue-$N claim dir removed"
  fi
done

# Release fan-out (2nd pass) — should be idempotent no-ops.
release_failures=0
for _ISSUE_N in "${ISSUE_NUMS[@]}"; do
  bash "$CLAIM_HELPER" release "$_ISSUE_N" --require-pipeline "$PIPELINE_ID" 2>/dev/null
  rc=$?
  if [ "$rc" -ne 0 ]; then
    release_failures=$((release_failures + 1))
  fi
done

if [ "$release_failures" -eq 0 ]; then
  pass "3c release fan-out: 2nd pass (already-released) idempotent rc=0"
else
  fail "3c release fan-out: $release_failures release(s) failed on 2nd pass (not idempotent)"
fi

echo ""
echo "=== Single-issue case still works through the fan-out loop ==="

REPO_D=$(make_repo)
cleanup_dirs+=("$REPO_D")
cd "$REPO_D" || exit 1

ISSUE_NUMS=(500)
PIPELINE_ID="do.test-single"
_ACQUIRED=()
for ISSUE_NUM in "${ISSUE_NUMS[@]}"; do
  bash "$CLAIM_HELPER" acquire "$ISSUE_NUM" --pipeline-id "$PIPELINE_ID" --sprint-id "$PIPELINE_ID" 2>/dev/null
  if [ "$?" -eq 0 ]; then _ACQUIRED+=("$ISSUE_NUM"); fi
done

if [ "${#_ACQUIRED[@]}" -eq 1 ] && [ "${_ACQUIRED[0]}" = "500" ]; then
  pass "4a single-issue: fan-out loop with N=1 acquires issue 500"
else
  fail "4a single-issue: expected [500], got [${_ACQUIRED[*]:-}]"
fi

for _ISSUE_N in "${ISSUE_NUMS[@]}"; do
  bash "$CLAIM_HELPER" release "$_ISSUE_N" --require-pipeline "$PIPELINE_ID" 2>/dev/null
done

if [ -d "$REPO_D/.zskills/claims/issue-500" ]; then
  fail "4b single-issue: claim dir survived release"
else
  pass "4b single-issue: claim released cleanly"
fi

echo ""
echo "=== Empty array → skip fan-out ==="

REPO_E=$(make_repo)
cleanup_dirs+=("$REPO_E")
cd "$REPO_E" || exit 1

ISSUE_NUMS=()
PIPELINE_ID="do.test-empty"
guard_fired=0
if [ "${#ISSUE_NUMS[@]}" -gt 0 ]; then
  guard_fired=1
fi
if [ "$guard_fired" -eq 0 ]; then
  pass "5a empty array: guard skips fan-out (no claim attempt)"
else
  fail "5a empty array: guard fired (would have attempted claims)"
fi

if [ ! -d "$REPO_E/.zskills/claims" ]; then
  pass "5b empty array: no .zskills/claims dir created"
else
  fail "5b empty array: .zskills/claims dir exists (claims were attempted)"
fi

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
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
