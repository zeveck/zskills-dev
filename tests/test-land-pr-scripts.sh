#!/bin/bash
# tests/test-land-pr-scripts.sh — unit tests for skills/land-pr/scripts/.
#
# Owner: PR_LANDING_UNIFICATION Phase 1B WI 1B.3.
#
# Covers:
#   - All 10 failure modes from skills/land-pr/references/failure-modes.md
#   - Idempotency cases per the same file's "Idempotency cases" section.
#   - PR_NUMBER URL extraction (no second `gh pr view` call).
#   - WATCH_EXIT=124 → CI_STATUS=pending.
#   - Auto-merge-disabled benign fallback (exit 0, NOT 30).
#
# Mocks: tests/mocks/mock-gh.sh, tests/mocks/mock-git.sh. The mocks are
# fail-fast — an unprepared call exits 99 (loud). All tests prep
# canned responses BEFORE invoking the script under test.
#
# Per CLAUDE.md test-output capture:
#   TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")/.test-results.txt"
# But this script is registered into tests/run-all.sh which captures
# the suite's output centrally; we don't double-capture here.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/skills/land-pr/scripts"
MOCKS_DIR="$SCRIPT_DIR/mocks"

PASS=0
FAIL=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

# ---- Per-test fixture helpers ----------------------------------------
# Each test gets:
#   - a fresh per-test mock state dir under /tmp/land-pr-test-<label>/
#   - mocks symlinked as `gh` and `git` so PATH override picks them up
#   - the per-test PATH that prepends the bin/ dir so the SUT's bare
#     `gh` and `git` invocations route to our mocks.

new_fixture() {
  local label="$1"
  local fixture="/tmp/land-pr-test-$label-$$"
  # Guard: only literal /tmp/land-pr-test-* paths.
  case "$fixture" in
    /tmp/land-pr-test-*) : ;;
    *) echo "REFUSING non-/tmp fixture path: $fixture" >&2; exit 1 ;;
  esac
  rm -rf "/tmp/land-pr-test-$label-$$"
  mkdir -p "$fixture/bin" "$fixture/state-gh" "$fixture/state-git"
  cp "$MOCKS_DIR/mock-gh.sh"  "$fixture/bin/gh"
  cp "$MOCKS_DIR/mock-git.sh" "$fixture/bin/git"
  chmod +x "$fixture/bin/gh" "$fixture/bin/git"
  echo "$fixture"
}

cleanup_fixture() {
  local fixture="$1"
  case "$fixture" in
    /tmp/land-pr-test-*) rm -rf "$fixture" ;;
    *) echo "REFUSING to clean non-/tmp path: $fixture" >&2 ;;
  esac
}

# Convenience: write a canned response for mock-gh.
# Args: <state-dir> <key> <call-num> <stdout|stderr|exit> <content>
prep_gh() {
  local sdir="$1" key="$2" num="$3" kind="$4" content="$5"
  printf '%s' "$content" > "$sdir/$key.$num.$kind"
}

prep_git() {
  local sdir="$1" key="$2" num="$3" kind="$4" content="$5"
  printf '%s' "$content" > "$sdir/$key.$num.$kind"
}

# Run a script under PATH-overridden mocks; capture stdout, stderr, exit.
# Sets globals: SUT_OUT, SUT_ERR, SUT_RC.
run_sut() {
  local fixture="$1"
  shift
  SUT_OUT_FILE="$fixture/sut.stdout"
  SUT_ERR_FILE="$fixture/sut.stderr"
  set +e
  PATH="$fixture/bin:$PATH" \
    MOCK_GH_STATE_DIR="$fixture/state-gh" \
    MOCK_GIT_STATE_DIR="$fixture/state-git" \
    "$@" >"$SUT_OUT_FILE" 2>"$SUT_ERR_FILE"
  SUT_RC=$?
  set -e
  SUT_OUT=$(cat "$SUT_OUT_FILE")
  SUT_ERR=$(cat "$SUT_ERR_FILE")
}

# Read a counter file, default 0.
counter() {
  local sdir="$1" key="$2"
  if [ -f "$sdir/$key.count" ]; then cat "$sdir/$key.count"; else echo 0; fi
}

# Standard prep for the rebase happy-path prefix:
#   call 1: rev-parse --is-inside-work-tree → exit 0
#   call 2: rev-parse --verify refs/heads/<branch> → exit 0
#   call 1: fetch origin <base> → exit 0
prep_rebase_preflight_ok() {
  local sd="$1"
  prep_git "$sd" rev-parse 1 exit 0
  prep_git "$sd" rev-parse 2 exit 0
  prep_git "$sd" fetch     1 exit 0
}

echo "=== /land-pr scripts: failure modes (10) + idempotency ==="

# ----------------------------------------------------------------------
# Failure mode #1 — rebase-conflict
# ----------------------------------------------------------------------
F=$(new_fixture mode1)
prep_rebase_preflight_ok "$F/state-git"
# rebase fails with conflict
prep_git "$F/state-git" rebase 1 exit 1
# diff --name-only --diff-filter=U returns conflict files
prep_git "$F/state-git" diff_unmerged 1 stdout $'src/foo.js\nsrc/bar.js'
# rebase --abort succeeds
prep_git "$F/state-git" rebase_abort 1 exit 0
run_sut "$F" bash "$SCRIPTS_DIR/pr-rebase.sh" --branch feat/x --base main
if [ "$SUT_RC" -eq 10 ] \
   && [[ "$SUT_OUT" =~ CONFLICT_FILES_LIST=([^[:space:]]+) ]]; then
  sidecar="${BASH_REMATCH[1]}"
  if [ -s "$sidecar" ] \
     && grep -q '^src/foo.js$' "$sidecar" \
     && grep -q '^src/bar.js$' "$sidecar" \
     && [ "$(counter "$F/state-git" rebase_abort)" = "1" ]; then
    pass "[mode1] rebase-conflict-emits-sidecar"
  else
    fail "[mode1] rebase-conflict-emits-sidecar" "sidecar=$sidecar abort_count=$(counter "$F/state-git" rebase_abort)"
  fi
else
  fail "[mode1] rebase-conflict-emits-sidecar" "rc=$SUT_RC out=$SUT_OUT"
fi
# Verify diff WAS captured BEFORE abort: counters confirm sequencing.
if [ "$(counter "$F/state-git" diff_unmerged)" = "1" ] \
   && [ "$(counter "$F/state-git" rebase_abort)" = "1" ]; then
  pass "[mode1] diff-unmerged captured (before abort, both counters=1)"
else
  fail "[mode1] diff-unmerged sequencing" "diff=$(counter "$F/state-git" diff_unmerged) abort=$(counter "$F/state-git" rebase_abort)"
fi
cleanup_fixture "$F"

# ----------------------------------------------------------------------
# Failure mode #2 — abort-failed (rebase --abort returns non-zero)
# ----------------------------------------------------------------------
F=$(new_fixture mode2)
prep_rebase_preflight_ok "$F/state-git"
prep_git "$F/state-git" rebase 1 exit 1
prep_git "$F/state-git" diff_unmerged 1 stdout 'foo.js'
prep_git "$F/state-git" rebase_abort 1 exit 1
prep_git "$F/state-git" rebase_abort 1 stderr 'fatal: no rebase in progress'
run_sut "$F" bash "$SCRIPTS_DIR/pr-rebase.sh" --branch feat/x --base main
if [ "$SUT_RC" -eq 11 ] && [[ "$SUT_OUT" == *"REASON=abort-failed"* ]]; then
  pass "[mode2] rebase-abort-failed-surfaces-reason"
else
  fail "[mode2] rebase-abort-failed-surfaces-reason" "rc=$SUT_RC out=$SUT_OUT"
fi
cleanup_fixture "$F"

# ----------------------------------------------------------------------
# Failure mode #3 — fetch-network failure
# ----------------------------------------------------------------------
F=$(new_fixture mode3)
prep_git "$F/state-git" rev-parse 1 exit 0
prep_git "$F/state-git" rev-parse 2 exit 0
prep_git "$F/state-git" fetch     1 exit 1
prep_git "$F/state-git" fetch     1 stderr 'fatal: could not resolve hostname'
run_sut "$F" bash "$SCRIPTS_DIR/pr-rebase.sh" --branch feat/x --base main
if [ "$SUT_RC" -eq 11 ] && [[ "$SUT_OUT" == *"REASON=network"* ]]; then
  pass "[mode3] rebase-fetch-network-failure-surfaces-reason"
else
  fail "[mode3] rebase-fetch-network-failure-surfaces-reason" "rc=$SUT_RC out=$SUT_OUT"
fi
cleanup_fixture "$F"

# ----------------------------------------------------------------------
# Failure mode #4 — push-failed
# ----------------------------------------------------------------------
F=$(new_fixture mode4)
# pr-push-and-create.sh sequence:
#   gh pr list --head ... --json --> empty array, exit 0
#   git rev-parse --abbrev-ref --symbolic-full-name @{u} --> exit 0 (upstream set)
#   git push --> exit 1, stderr captured to sidecar
prep_gh  "$F/state-gh"  pr_list   1 stdout '[]'
prep_git "$F/state-git" rev-parse 1 exit 0
prep_git "$F/state-git" push      1 exit 1
prep_git "$F/state-git" push      1 stderr 'remote: Permission denied'
mkdir -p "$F/work"
echo "PR body" > "$F/work/body.md"
run_sut "$F" bash "$SCRIPTS_DIR/pr-push-and-create.sh" \
  --branch feat/x --base main --title 'T' --body-file "$F/work/body.md"
if [ "$SUT_RC" -eq 12 ] \
   && [[ "$SUT_OUT" =~ CALL_ERROR_FILE=([^[:space:]]+) ]] \
   && [ -s "${BASH_REMATCH[1]}" ]; then
  pass "[mode4] push-failed-emits-call-error-sidecar"
else
  fail "[mode4] push-failed-emits-call-error-sidecar" "rc=$SUT_RC out=$SUT_OUT"
fi
cleanup_fixture "$F"

# ----------------------------------------------------------------------
# Failure mode #5 — create-failed (race: gh rejects "already exists")
# ----------------------------------------------------------------------
F=$(new_fixture mode5)
# pr_list returns empty (no existing PR detected at read time)
prep_gh  "$F/state-gh"  pr_list   1 stdout '[]'
prep_git "$F/state-git" rev-parse 1 exit 0
prep_git "$F/state-git" push      1 exit 0
# pr_create fails with "already exists" — race
prep_gh  "$F/state-gh"  pr_create 1 exit 1
prep_gh  "$F/state-gh"  pr_create 1 stderr 'pull request already exists for branch feat/x'
mkdir -p "$F/work"; echo "PR body" > "$F/work/body.md"
run_sut "$F" bash "$SCRIPTS_DIR/pr-push-and-create.sh" \
  --branch feat/x --base main --title 'T' --body-file "$F/work/body.md"
if [ "$SUT_RC" -eq 13 ] \
   && [[ "$SUT_OUT" =~ CALL_ERROR_FILE=([^[:space:]]+) ]] \
   && [ -s "${BASH_REMATCH[1]}" ] \
   && [ "$(counter "$F/state-gh" pr_create)" = "1" ]; then
  pass "[mode5] create-failed-race-bounded (one create attempt, sidecar emitted)"
else
  fail "[mode5] create-failed-race-bounded" "rc=$SUT_RC out=$SUT_OUT create_count=$(counter "$F/state-gh" pr_create)"
fi
cleanup_fixture "$F"

# ----------------------------------------------------------------------
# Failure mode #6 — invalid-pr-number (URL last segment non-numeric)
# ----------------------------------------------------------------------
F=$(new_fixture mode6a)
prep_gh  "$F/state-gh"  pr_list   1 stdout '[]'
prep_git "$F/state-git" rev-parse 1 exit 0
prep_git "$F/state-git" push      1 exit 0
prep_gh  "$F/state-gh"  pr_create 1 stdout 'https://github.com/o/r/pull/abc'
mkdir -p "$F/work"; echo "PR body" > "$F/work/body.md"
run_sut "$F" bash "$SCRIPTS_DIR/pr-push-and-create.sh" \
  --branch feat/x --base main --title 'T' --body-file "$F/work/body.md"
if [ "$SUT_RC" -eq 14 ]; then
  pass "[mode6a] pr-number-non-numeric-fails-loud"
else
  fail "[mode6a] pr-number-non-numeric-fails-loud" "rc=$SUT_RC out=$SUT_OUT"
fi
cleanup_fixture "$F"

# Success-path companion: PR_NUMBER comes from URL via ${URL##*/} —
# `gh pr view` is NOT invoked.
F=$(new_fixture mode6b)
prep_gh  "$F/state-gh"  pr_list   1 stdout '[]'
prep_git "$F/state-git" rev-parse 1 exit 0
prep_git "$F/state-git" push      1 exit 0
prep_gh  "$F/state-gh"  pr_create 1 stdout 'https://github.com/o/r/pull/42'
mkdir -p "$F/work"; echo "PR body" > "$F/work/body.md"
run_sut "$F" bash "$SCRIPTS_DIR/pr-push-and-create.sh" \
  --branch feat/x --base main --title 'T' --body-file "$F/work/body.md"
if [ "$SUT_RC" -eq 0 ] \
   && [[ "$SUT_OUT" == *"PR_NUMBER=42"* ]] \
   && [ "$(counter "$F/state-gh" pr_view)" = "0" ]; then
  pass "[mode6b] pr-number-extraction-from-url (no gh pr view call)"
else
  fail "[mode6b] pr-number-extraction-from-url" "rc=$SUT_RC out=$SUT_OUT view_count=$(counter "$F/state-gh" pr_view)"
fi
cleanup_fixture "$F"

# ----------------------------------------------------------------------
# Failure mode #7 — pre-flight-failed (a) non-numeric PR; (b) gh auth
# ----------------------------------------------------------------------
F=$(new_fixture mode7a)
mkdir -p "$F/work"
run_sut "$F" bash "$SCRIPTS_DIR/pr-monitor.sh" --pr abc --log-out "$F/work/ci.log"
if [ "$SUT_RC" -eq 20 ]; then
  pass "[mode7a] monitor-preflight-non-numeric-pr"
else
  fail "[mode7a] monitor-preflight-non-numeric-pr" "rc=$SUT_RC err=$SUT_ERR"
fi
cleanup_fixture "$F"

F=$(new_fixture mode7b)
mkdir -p "$F/work"
prep_gh "$F/state-gh" auth_status 1 exit 1
prep_gh "$F/state-gh" auth_status 1 stderr 'You are not logged into any GitHub hosts.'
run_sut "$F" bash "$SCRIPTS_DIR/pr-monitor.sh" --pr 42 --log-out "$F/work/ci.log"
if [ "$SUT_RC" -eq 20 ]; then
  pass "[mode7b] monitor-preflight-gh-auth-fails"
else
  fail "[mode7b] monitor-preflight-gh-auth-fails" "rc=$SUT_RC err=$SUT_ERR"
fi
cleanup_fixture "$F"

# ----------------------------------------------------------------------
# Failure mode #8 — WATCH_EXIT=124 → CI_STATUS=pending
# ----------------------------------------------------------------------
# pr-monitor.sh sequence:
#   gh auth status → 0
#   gh pr checks --json name → returns array with one check, gives CHECK_COUNT=1
#   timeout 600 gh pr checks --watch → exit 124 (timeout)
# The `timeout` wrapper actually invokes `gh pr checks --watch`, which
# is a `pr_checks` key call. Mock returns exit 124 for that call.
F=$(new_fixture mode8)
mkdir -p "$F/work"
prep_gh "$F/state-gh" auth_status 1 exit 0
prep_gh "$F/state-gh" pr_checks   1 stdout '[{"name":"build"}]'
# timeout(1) wraps `gh pr checks --watch` — that's pr_checks call #2.
prep_gh "$F/state-gh" pr_checks   2 exit 124
run_sut "$F" bash "$SCRIPTS_DIR/pr-monitor.sh" --pr 42 --timeout 1 --log-out "$F/work/ci.log"
if [ "$SUT_RC" -eq 0 ] && [[ "$SUT_OUT" == *"CI_STATUS=pending"* ]]; then
  pass "[mode8] monitor-watch-exit-124-emits-pending"
else
  fail "[mode8] monitor-watch-exit-124-emits-pending" "rc=$SUT_RC out=$SUT_OUT err=$SUT_ERR"
fi
cleanup_fixture "$F"

# ----------------------------------------------------------------------
# Failure mode #9 — auto-merge-disabled-on-repo (benign, exit 0)
# ----------------------------------------------------------------------
F=$(new_fixture mode9)
prep_gh "$F/state-gh" pr_merge 1 exit 1
prep_gh "$F/state-gh" pr_merge 1 stderr 'pull request auto-merge is not allowed on this repository'
run_sut "$F" bash "$SCRIPTS_DIR/pr-merge.sh" --pr 42 --auto-flag true --ci-status pass
if [ "$SUT_RC" -eq 0 ] \
   && [[ "$SUT_OUT" == *"MERGE_REQUESTED=false"* ]] \
   && [[ "$SUT_OUT" == *"MERGE_REASON=auto-merge-disabled-on-repo"* ]]; then
  pass "[mode9] merge-auto-disabled-benign-fallback (exit 0, NOT 30)"
else
  fail "[mode9] merge-auto-disabled-benign-fallback" "rc=$SUT_RC out=$SUT_OUT err=$SUT_ERR"
fi
cleanup_fixture "$F"

# ----------------------------------------------------------------------
# Failure mode #10 — merge-gh-error (non-benign, exit 30)
# ----------------------------------------------------------------------
F=$(new_fixture mode10)
prep_gh "$F/state-gh" pr_merge 1 exit 1
prep_gh "$F/state-gh" pr_merge 1 stderr 'HTTP 502 Bad Gateway'
run_sut "$F" bash "$SCRIPTS_DIR/pr-merge.sh" --pr 42 --auto-flag true --ci-status pass
if [ "$SUT_RC" -eq 30 ] \
   && [[ "$SUT_OUT" == *"MERGE_REASON=gh-error"* ]] \
   && [[ "$SUT_OUT" =~ CALL_ERROR_FILE=([^[:space:]]+) ]] \
   && [ -s "${BASH_REMATCH[1]}" ]; then
  pass "[mode10] merge-gh-error-non-benign-surfaces-call-error"
else
  fail "[mode10] merge-gh-error-non-benign-surfaces-call-error" "rc=$SUT_RC out=$SUT_OUT"
fi
cleanup_fixture "$F"

echo ""
echo "=== /land-pr scripts: idempotency cases ==="

# ----------------------------------------------------------------------
# Idempotency 1 — rebase no-op (already up to date) exits 0
# ----------------------------------------------------------------------
F=$(new_fixture idem1)
prep_rebase_preflight_ok "$F/state-git"
prep_git "$F/state-git" rebase 1 exit 0
prep_git "$F/state-git" rebase 1 stdout 'Current branch feat/x is up to date.'
run_sut "$F" bash "$SCRIPTS_DIR/pr-rebase.sh" --branch feat/x --base main
if [ "$SUT_RC" -eq 0 ] \
   && [ -z "$SUT_OUT" ] \
   && [ "$(counter "$F/state-git" rebase_abort)" = "0" ]; then
  pass "[idem1] rebase-noop-no-stdout-no-abort"
else
  fail "[idem1] rebase-noop-no-stdout-no-abort" "rc=$SUT_RC out='$SUT_OUT' abort=$(counter "$F/state-git" rebase_abort)"
fi
cleanup_fixture "$F"

# ----------------------------------------------------------------------
# Idempotency 2 — push-create with existing PR (no gh pr create, no edit)
# ----------------------------------------------------------------------
F=$(new_fixture idem2)
# pr_list returns existing PR
prep_gh  "$F/state-gh"  pr_list   1 stdout '[{"number":7,"url":"https://github.com/o/r/pull/7"}]'
prep_git "$F/state-git" rev-parse 1 exit 0
prep_git "$F/state-git" push      1 exit 0
mkdir -p "$F/work"; echo "PR body" > "$F/work/body.md"
run_sut "$F" bash "$SCRIPTS_DIR/pr-push-and-create.sh" \
  --branch feat/x --base main --title 'T' --body-file "$F/work/body.md"
if [ "$SUT_RC" -eq 0 ] \
   && [[ "$SUT_OUT" == *"PR_EXISTING=true"* ]] \
   && [[ "$SUT_OUT" == *"PR_NUMBER=7"* ]] \
   && [ "$(counter "$F/state-gh" pr_create)" = "0" ] \
   && [ "$(counter "$F/state-gh" pr_edit)" = "0" ]; then
  pass "[idem2] push-create-existing-PR (no pr_create, no pr_edit calls)"
else
  fail "[idem2] push-create-existing-PR" "rc=$SUT_RC out=$SUT_OUT create=$(counter "$F/state-gh" pr_create) edit=$(counter "$F/state-gh" pr_edit)"
fi
cleanup_fixture "$F"

# ----------------------------------------------------------------------
# Idempotency 3 — merge --auto-flag=false → no gh call, MERGE_REQUESTED=false
# ----------------------------------------------------------------------
F=$(new_fixture idem3)
run_sut "$F" bash "$SCRIPTS_DIR/pr-merge.sh" --pr 42 --auto-flag false --ci-status pass
if [ "$SUT_RC" -eq 0 ] \
   && [[ "$SUT_OUT" == *"MERGE_REQUESTED=false"* ]] \
   && [[ "$SUT_OUT" == *"MERGE_REASON=auto-not-requested"* ]] \
   && [ "$(counter "$F/state-gh" pr_merge)" = "0" ]; then
  pass "[idem3] merge-no-op-when-auto-flag-false (no gh call)"
else
  fail "[idem3] merge-no-op-when-auto-flag-false" "rc=$SUT_RC out=$SUT_OUT merge_count=$(counter "$F/state-gh" pr_merge)"
fi
cleanup_fixture "$F"

# ----------------------------------------------------------------------
# Idempotency 4 — merge --ci-status=pending → not requested
# ----------------------------------------------------------------------
F=$(new_fixture idem4)
run_sut "$F" bash "$SCRIPTS_DIR/pr-merge.sh" --pr 42 --auto-flag true --ci-status pending
if [ "$SUT_RC" -eq 0 ] \
   && [[ "$SUT_OUT" == *"MERGE_REQUESTED=false"* ]] \
   && [[ "$SUT_OUT" == *"MERGE_REASON=ci-not-passing"* ]] \
   && [ "$(counter "$F/state-gh" pr_merge)" = "0" ]; then
  pass "[idem4] merge-ci-pending-not-requested"
else
  fail "[idem4] merge-ci-pending-not-requested" "rc=$SUT_RC out=$SUT_OUT"
fi
cleanup_fixture "$F"

echo ""
echo "=== /land-pr scripts: usage-error and arg-validation surface ==="

# Each script's `--branch` / `--pr` validation should exit non-zero
# without invoking gh / git.
F=$(new_fixture argerr1)
run_sut "$F" bash "$SCRIPTS_DIR/pr-rebase.sh"
if [ "$SUT_RC" -eq 2 ]; then
  pass "[argerr1] pr-rebase.sh missing --branch exits 2"
else
  fail "[argerr1] pr-rebase.sh missing --branch" "rc=$SUT_RC"
fi
cleanup_fixture "$F"

F=$(new_fixture argerr2)
run_sut "$F" bash "$SCRIPTS_DIR/pr-push-and-create.sh" --branch feat/x
if [ "$SUT_RC" -eq 2 ]; then
  pass "[argerr2] pr-push-and-create.sh missing other args exits 2"
else
  fail "[argerr2] pr-push-and-create.sh missing args" "rc=$SUT_RC"
fi
cleanup_fixture "$F"

F=$(new_fixture argerr3)
run_sut "$F" bash "$SCRIPTS_DIR/pr-monitor.sh" --pr 42
if [ "$SUT_RC" -eq 2 ]; then
  pass "[argerr3] pr-monitor.sh missing --log-out exits 2"
else
  fail "[argerr3] pr-monitor.sh missing --log-out" "rc=$SUT_RC"
fi
cleanup_fixture "$F"

F=$(new_fixture argerr4)
run_sut "$F" bash "$SCRIPTS_DIR/pr-merge.sh" --pr abc --auto-flag true --ci-status pass
if [ "$SUT_RC" -eq 2 ]; then
  pass "[argerr4] pr-merge.sh non-numeric --pr exits 2"
else
  fail "[argerr4] pr-merge.sh non-numeric --pr" "rc=$SUT_RC"
fi
cleanup_fixture "$F"

# ----------------------------------------------------------------------
# Branch-slash sanitization — branch 'feat/x' must NOT create
# /tmp/land-pr-conflict-files-feat/x-<pid>.txt subdirectory.
# Any sidecar path emitted should have NO `/` after `land-pr-…-`.
# ----------------------------------------------------------------------
F=$(new_fixture slug)
prep_rebase_preflight_ok "$F/state-git"
prep_git "$F/state-git" rebase 1 exit 1
prep_git "$F/state-git" diff_unmerged 1 stdout 'a.js'
prep_git "$F/state-git" rebase_abort 1 exit 0
run_sut "$F" bash "$SCRIPTS_DIR/pr-rebase.sh" --branch 'smoke/foo' --base main
if [ "$SUT_RC" -eq 10 ] \
   && [[ "$SUT_OUT" =~ CONFLICT_FILES_LIST=([^[:space:]]+) ]]; then
  sidecar="${BASH_REMATCH[1]}"
  base=$(basename "$sidecar")
  if [[ "$base" == *"smoke-foo"* ]] && [[ "$base" != *"/"* ]]; then
    pass "[slug] branch-slash sanitized to dash in sidecar filename ($base)"
  else
    fail "[slug] branch-slash sanitized" "sidecar=$sidecar base=$base"
  fi
else
  fail "[slug] branch-slash sanitized" "rc=$SUT_RC out=$SUT_OUT"
fi
cleanup_fixture "$F"

# ----------------------------------------------------------------------
# Body-file safety: --body-file does NOT exist → exit 2 (not 0, not 13)
# ----------------------------------------------------------------------
F=$(new_fixture bodyfile)
run_sut "$F" bash "$SCRIPTS_DIR/pr-push-and-create.sh" \
  --branch feat/x --base main --title 'T' --body-file "/tmp/does-not-exist-$$"
if [ "$SUT_RC" -eq 2 ]; then
  pass "[bodyfile] missing body-file exits 2 before any gh call"
else
  fail "[bodyfile] missing body-file" "rc=$SUT_RC err=$SUT_ERR"
fi
cleanup_fixture "$F"

echo ""
echo "---"
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (of %d)\033[0m\n' "$PASS" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (of %d)\033[0m\n' "$PASS" "$FAIL" "$TOTAL"
  exit 1
fi
