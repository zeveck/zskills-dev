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
#   call 3: rev-parse --abbrev-ref HEAD → stdout=<branch> (Issue #397 guard)
#   call 1: status --porcelain → stdout="" (Issue #481 dirty-tree guard;
#          empty = clean tree, proceed)
#   call 1: fetch origin <base> → exit 0
prep_rebase_preflight_ok() {
  local sd="$1"
  local branch="${2:-feat/x}"
  prep_git "$sd" rev-parse 1 exit 0
  prep_git "$sd" rev-parse 2 exit 0
  prep_git "$sd" rev-parse 3 stdout "$branch"
  prep_git "$sd" status    1 stdout ""
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
prep_git "$F/state-git" rev-parse 3 stdout 'feat/x'
prep_git "$F/state-git" status    1 stdout ""
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
# pr-push-and-create.sh sequence (post-Issue-#188 fix):
#   gh pr list --head ... --json --> empty array, exit 0
#   git push -u origin <branch> --> exit 1, stderr captured to sidecar
#   (no rev-parse/ls-remote verify — push fails first, error short-circuits)
prep_gh  "$F/state-gh"  pr_list   1 stdout '[]'
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
prep_git "$F/state-git" push      1 exit 0
# Post-push verification (Issue #188 fix): rev-parse local + ls-remote remote.
prep_git "$F/state-git" rev-parse 1 stdout 'abc123'
prep_git "$F/state-git" ls-remote 1 stdout 'abc123	refs/heads/feat/x'
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
prep_git "$F/state-git" push      1 exit 0
prep_git "$F/state-git" rev-parse 1 stdout 'abc123'
prep_git "$F/state-git" ls-remote 1 stdout 'abc123	refs/heads/feat/x'
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
prep_git "$F/state-git" push      1 exit 0
prep_git "$F/state-git" rev-parse 1 stdout 'abc123'
prep_git "$F/state-git" ls-remote 1 stdout 'abc123	refs/heads/feat/x'
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
# Issue #482 — post-force-push grace: first-poll rc=1 + second rc=0 →
# CI_STATUS=pass (NOT fail). After Step 6b's force-push, GitHub takes
# ~5s to register the new check run; pr-monitor.sh Step 5 retries once
# on rc=1 so the stale prior failed run doesn't surface as a false fail.
# PR_MONITOR_RECHECK_SLEEP=0 skips the wall-clock wait for testing.
#
# Sequence:
#   auth_status   → 0
#   pr_checks   1 → stdout=[{...}] (CHECK_COUNT=1, success)
#   pr_checks   2 → exit 0 (timeout-watch returns 0, not 124)
#   pr_checks   3 → exit 1 (first re-check: stale prior-run still fail)
#   pr_checks   4 → exit 0 (second re-check after grace: new run passes)
# ----------------------------------------------------------------------
F=$(new_fixture issue482_grace)
mkdir -p "$F/work"
prep_gh "$F/state-gh" auth_status 1 exit 0
prep_gh "$F/state-gh" pr_checks   1 stdout '[{"name":"build"}]'
prep_gh "$F/state-gh" pr_checks   2 exit 0
prep_gh "$F/state-gh" pr_checks   3 exit 1
prep_gh "$F/state-gh" pr_checks   4 exit 0
SUT_OUT_FILE="$F/sut.stdout"
SUT_ERR_FILE="$F/sut.stderr"
set +e
PATH="$F/bin:$PATH" \
  MOCK_GH_STATE_DIR="$F/state-gh" \
  MOCK_GIT_STATE_DIR="$F/state-git" \
  PR_MONITOR_RECHECK_SLEEP=0 \
  bash "$SCRIPTS_DIR/pr-monitor.sh" --pr 42 --timeout 1 --log-out "$F/work/ci.log" \
  >"$SUT_OUT_FILE" 2>"$SUT_ERR_FILE"
SUT_RC=$?
set -e
SUT_OUT=$(cat "$SUT_OUT_FILE")
SUT_ERR=$(cat "$SUT_ERR_FILE")
# Expect: CI_STATUS=pass (second poll wins), AND pr_checks was called 4
# times total (the retry happened).
if [ "$SUT_RC" -eq 0 ] \
   && [[ "$SUT_OUT" == *"CI_STATUS=pass"* ]] \
   && [ "$(counter "$F/state-gh" pr_checks)" = "4" ]; then
  pass "[issue482] monitor-post-force-push-grace: fail-then-pass → CI_STATUS=pass (4 pr_checks calls)"
else
  fail "[issue482] monitor-post-force-push-grace" "rc=$SUT_RC out=$SUT_OUT pr_checks_count=$(counter "$F/state-gh" pr_checks)"
fi
cleanup_fixture "$F"

# Companion: both polls return rc=1 → still CI_STATUS=fail (real failure,
# retry doesn't mask). Ensures the retry isn't a license to ignore
# persistent failures.
F=$(new_fixture issue482_persistent_fail)
mkdir -p "$F/work"
prep_gh "$F/state-gh" auth_status 1 exit 0
prep_gh "$F/state-gh" pr_checks   1 stdout '[{"name":"build"}]'
prep_gh "$F/state-gh" pr_checks   2 exit 0
prep_gh "$F/state-gh" pr_checks   3 exit 1
prep_gh "$F/state-gh" pr_checks   4 exit 1
# After CI_STATUS=fail, the script attempts to fetch run id for log capture
# (Step 6). It calls `gh pr checks --json link` once and `gh run view` once.
prep_gh "$F/state-gh" pr_checks   5 stdout '[]'
SUT_OUT_FILE="$F/sut.stdout"
SUT_ERR_FILE="$F/sut.stderr"
set +e
PATH="$F/bin:$PATH" \
  MOCK_GH_STATE_DIR="$F/state-gh" \
  MOCK_GIT_STATE_DIR="$F/state-git" \
  PR_MONITOR_RECHECK_SLEEP=0 \
  bash "$SCRIPTS_DIR/pr-monitor.sh" --pr 42 --timeout 1 --log-out "$F/work/ci.log" \
  >"$SUT_OUT_FILE" 2>"$SUT_ERR_FILE"
SUT_RC=$?
set -e
SUT_OUT=$(cat "$SUT_OUT_FILE")
if [ "$SUT_RC" -eq 0 ] \
   && [[ "$SUT_OUT" == *"CI_STATUS=fail"* ]] \
   && [ "$(counter "$F/state-gh" pr_checks)" = "5" ]; then
  pass "[issue482] monitor-persistent-fail: fail-then-fail → CI_STATUS=fail (retry attempted, both failed)"
else
  fail "[issue482] monitor-persistent-fail" "rc=$SUT_RC out=$SUT_OUT pr_checks_count=$(counter "$F/state-gh" pr_checks)"
fi
cleanup_fixture "$F"

# ----------------------------------------------------------------------
# Issue #1161 — registration grace window. pr-monitor.sh must NOT emit
# CI_STATUS=none when checks haven't REGISTERED yet but the base branch
# REQUIRES status checks (GitHub lag right after push). Mapping zero-
# checks-yet to `none` green-lit a premature merge (rows 6-10 treat `none`
# as mergeable). Required-checks-configured + zero-registered → `pending`.
#
# Sequence (PR_MONITOR_REGISTER_SLEEP=0 → no wall-clock wait):
#   auth_status                  → 0
#   pr_checks 1..6 (all attempts)→ stdout="[]" (empty array, never registers)
#   pr_view (baseRefName)        → stdout={"baseRefName":"main"}
#   api_..._required_status_checks → 200 with non-empty contexts
# Expect: CI_STATUS=pending (NOT none/pass).
# ----------------------------------------------------------------------
# The sanitized mock key for the branch-protection api call (mirrors
# mock-gh.sh's `/`,`{`,`}` → `_` transform).
api_key_for() {
  local key="api_repos/{owner}/{repo}/branches/$1/protection/required_status_checks"
  key="${key//\//_}"; key="${key//\{/_}"; key="${key//\}/_}"
  printf '%s' "$key"
}

F=$(new_fixture issue1161_required_lag)
mkdir -p "$F/work"
prep_gh "$F/state-gh" auth_status 1 exit 0
# All 6 registration attempts return an empty array → never registers.
for n in 1 2 3 4 5 6; do prep_gh "$F/state-gh" pr_checks "$n" stdout '[]'; done
prep_gh "$F/state-gh" pr_view 1 stdout '{"baseRefName":"main"}'
PROT_KEY=$(api_key_for main)
prep_gh "$F/state-gh" "$PROT_KEY" 1 stdout '{"contexts":["build"],"checks":[{"context":"build"}]}'
prep_gh "$F/state-gh" "$PROT_KEY" 1 exit 0
SUT_OUT_FILE="$F/sut.stdout"; SUT_ERR_FILE="$F/sut.stderr"
set +e
PATH="$F/bin:$PATH" \
  MOCK_GH_STATE_DIR="$F/state-gh" \
  MOCK_GIT_STATE_DIR="$F/state-git" \
  PR_MONITOR_REGISTER_SLEEP=0 \
  bash "$SCRIPTS_DIR/pr-monitor.sh" --pr 42 --timeout 1 --log-out "$F/work/ci.log" \
  >"$SUT_OUT_FILE" 2>"$SUT_ERR_FILE"
SUT_RC=$?
set -e
SUT_OUT=$(cat "$SUT_OUT_FILE")
if [ "$SUT_RC" -eq 0 ] \
   && [[ "$SUT_OUT" == *"CI_STATUS=pending"* ]] \
   && [[ "$SUT_OUT" != *"CI_STATUS=none"* ]]; then
  pass "[issue1161] required-checks-configured + zero-registered → CI_STATUS=pending (not none)"
else
  fail "[issue1161] required-checks lag → pending" "rc=$SUT_RC out=$SUT_OUT err=$SUT_ERR"
fi
cleanup_fixture "$F"

# Companion: genuinely no required checks configured (404 / empty
# contexts) → CI_STATUS=none is STILL correct (no behavior regression for
# real no-CI repos). The api call returns rc!=0 (404) OR empty contexts.
F=$(new_fixture issue1161_no_checks)
mkdir -p "$F/work"
prep_gh "$F/state-gh" auth_status 1 exit 0
for n in 1 2 3 4 5 6; do prep_gh "$F/state-gh" pr_checks "$n" stdout '[]'; done
prep_gh "$F/state-gh" pr_view 1 stdout '{"baseRefName":"main"}'
PROT_KEY=$(api_key_for main)
# 404: no branch protection → gh api exits non-zero with an error body.
prep_gh "$F/state-gh" "$PROT_KEY" 1 stderr 'gh: Branch not protected (HTTP 404)'
prep_gh "$F/state-gh" "$PROT_KEY" 1 exit 1
SUT_OUT_FILE="$F/sut.stdout"; SUT_ERR_FILE="$F/sut.stderr"
set +e
PATH="$F/bin:$PATH" \
  MOCK_GH_STATE_DIR="$F/state-gh" \
  MOCK_GIT_STATE_DIR="$F/state-git" \
  PR_MONITOR_REGISTER_SLEEP=0 \
  bash "$SCRIPTS_DIR/pr-monitor.sh" --pr 42 --timeout 1 --log-out "$F/work/ci.log" \
  >"$SUT_OUT_FILE" 2>"$SUT_ERR_FILE"
SUT_RC=$?
set -e
SUT_OUT=$(cat "$SUT_OUT_FILE")
if [ "$SUT_RC" -eq 0 ] \
   && [[ "$SUT_OUT" == *"CI_STATUS=none"* ]]; then
  pass "[issue1161] no required checks (404) → CI_STATUS=none (no regression)"
else
  fail "[issue1161] no-required-checks → none" "rc=$SUT_RC out=$SUT_OUT err=$SUT_ERR"
fi
cleanup_fixture "$F"

# Companion: base branch unresolvable (gh pr view fails) → fail SAFE to
# pending (never none on uncertainty — a stuck pending costs a manual
# nudge; a false none is the premature-merge bug).
F=$(new_fixture issue1161_base_unknown)
mkdir -p "$F/work"
prep_gh "$F/state-gh" auth_status 1 exit 0
for n in 1 2 3 4 5 6; do prep_gh "$F/state-gh" pr_checks "$n" stdout '[]'; done
prep_gh "$F/state-gh" pr_view 1 exit 1
prep_gh "$F/state-gh" pr_view 1 stderr 'gh: could not resolve PR'
SUT_OUT_FILE="$F/sut.stdout"; SUT_ERR_FILE="$F/sut.stderr"
set +e
PATH="$F/bin:$PATH" \
  MOCK_GH_STATE_DIR="$F/state-gh" \
  MOCK_GIT_STATE_DIR="$F/state-git" \
  PR_MONITOR_REGISTER_SLEEP=0 \
  bash "$SCRIPTS_DIR/pr-monitor.sh" --pr 42 --timeout 1 --log-out "$F/work/ci.log" \
  >"$SUT_OUT_FILE" 2>"$SUT_ERR_FILE"
SUT_RC=$?
set -e
SUT_OUT=$(cat "$SUT_OUT_FILE")
if [ "$SUT_RC" -eq 0 ] \
   && [[ "$SUT_OUT" == *"CI_STATUS=pending"* ]]; then
  pass "[issue1161] base-branch unresolvable → fail-safe CI_STATUS=pending"
else
  fail "[issue1161] base-unknown fail-safe pending" "rc=$SUT_RC out=$SUT_OUT err=$SUT_ERR"
fi
cleanup_fixture "$F"

# ----------------------------------------------------------------------
# Issue #1162 — gh-host.sh resolves GH_HOST from origin URL shapes.
# Direct unit test of the sourceable helper (no gh involved).
# ----------------------------------------------------------------------
ghhost_resolves() {
  local label="$1" url="$2" expect="$3"
  local F; F=$(new_fixture "ghhost-$label")
  # mock-git returns the canned origin URL for `git remote get-url origin`.
  prep_git "$F/state-git" remote 1 stdout "$url"
  local out
  out=$(PATH="$F/bin:$PATH" MOCK_GIT_STATE_DIR="$F/state-git" \
        bash -c '. "'"$SCRIPTS_DIR"'/gh-host.sh"; printf "%s" "${GH_HOST:-<unset>}"')
  if [ "$out" = "$expect" ]; then
    pass "[issue1162] gh-host $label ($url) → GH_HOST=$expect"
  else
    fail "[issue1162] gh-host $label" "url=$url got='$out' expected='$expect'"
  fi
  cleanup_fixture "$F"
}
ghhost_resolves scp-enterprise 'git@github.example.com:org/repo.git' 'github.example.com'
ghhost_resolves https-enterprise 'https://github.example.com/org/repo.git' 'github.example.com'
ghhost_resolves https-userinfo 'https://user@github.example.com/org/repo.git' 'github.example.com'
ghhost_resolves ssh-url 'ssh://git@github.example.com:22/org/repo.git' 'github.example.com'
ghhost_resolves dotcom-scp 'git@github.com:org/repo.git' 'github.com'
ghhost_resolves dotcom-https 'https://github.com/org/repo.git' 'github.com'

# Origin absent → GH_HOST stays unset (fail-open; gh keeps its default).
F=$(new_fixture ghhost-no-origin)
prep_git "$F/state-git" remote 1 exit 1
prep_git "$F/state-git" remote 1 stderr "error: No such remote 'origin'"
out=$(PATH="$F/bin:$PATH" MOCK_GIT_STATE_DIR="$F/state-git" \
      bash -c '. "'"$SCRIPTS_DIR"'/gh-host.sh"; printf "%s" "${GH_HOST:-<unset>}"')
if [ "$out" = "<unset>" ]; then
  pass "[issue1162] gh-host no-origin → GH_HOST unset (fail-open)"
else
  fail "[issue1162] gh-host no-origin" "got='$out' expected='<unset>'"
fi
cleanup_fixture "$F"

# Explicit caller-provided GH_HOST is respected (not clobbered).
F=$(new_fixture ghhost-respect-existing)
prep_git "$F/state-git" remote 1 stdout 'git@github.com:org/repo.git'
out=$(PATH="$F/bin:$PATH" MOCK_GIT_STATE_DIR="$F/state-git" GH_HOST='preset.example.com' \
      bash -c '. "'"$SCRIPTS_DIR"'/gh-host.sh"; printf "%s" "${GH_HOST:-<unset>}"')
if [ "$out" = "preset.example.com" ]; then
  pass "[issue1162] gh-host respects pre-set GH_HOST (no clobber)"
else
  fail "[issue1162] gh-host respects pre-set GH_HOST" "got='$out' expected='preset.example.com'"
fi
cleanup_fixture "$F"

# ----------------------------------------------------------------------
# Failure mode #9 — auto-merge-disabled-on-repo (benign, exit 0)
# ----------------------------------------------------------------------
F=$(new_fixture mode9)
prep_gh "$F/state-gh" pr_merge 1 exit 1
prep_gh "$F/state-gh" pr_merge 1 stderr 'pull request auto-merge is not allowed on this repository'
run_sut "$F" bash "$SCRIPTS_DIR/pr-merge.sh" --pr 42 --automerge-flag true --ci-status pass
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
run_sut "$F" bash "$SCRIPTS_DIR/pr-merge.sh" --pr 42 --automerge-flag true --ci-status pass
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
prep_git "$F/state-git" push      1 exit 0
prep_git "$F/state-git" rev-parse 1 stdout 'abc123'
prep_git "$F/state-git" ls-remote 1 stdout 'abc123	refs/heads/feat/x'
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
# Idempotency 3 — merge --automerge-flag=false → no gh call, MERGE_REQUESTED=false
# ----------------------------------------------------------------------
F=$(new_fixture idem3)
run_sut "$F" bash "$SCRIPTS_DIR/pr-merge.sh" --pr 42 --automerge-flag false --ci-status pass
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
run_sut "$F" bash "$SCRIPTS_DIR/pr-merge.sh" --pr 42 --automerge-flag true --ci-status pending
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
run_sut "$F" bash "$SCRIPTS_DIR/pr-merge.sh" --pr abc --automerge-flag true --ci-status pass
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
prep_rebase_preflight_ok "$F/state-git" 'smoke/foo'
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
# Issue #397 regression: pr-rebase.sh asserts CWD's HEAD == $BRANCH.
# Pre-fix code rebased whatever HEAD pointed to in the caller's CWD — if
# the caller forgot to `cd` into the worktree (HEAD on `main` or another
# branch), the rebase silently retargeted the wrong branch and exited 0.
# Symmetric defense to pr-push-and-create's Issue #188 fix.
# Assertion: when `git rev-parse --abbrev-ref HEAD` returns a branch
# different from --branch, pr-rebase.sh exits 14 with REASON=wrong-current-branch.
# ----------------------------------------------------------------------
F=$(new_fixture issue397_wrong_branch)
prep_git "$F/state-git" rev-parse 1 exit 0
prep_git "$F/state-git" rev-parse 2 exit 0
# HEAD reports a DIFFERENT branch — script must refuse.
prep_git "$F/state-git" rev-parse 3 stdout 'main'
run_sut "$F" bash "$SCRIPTS_DIR/pr-rebase.sh" --branch feat/x --base main
if [ "$SUT_RC" -eq 14 ] \
   && [[ "$SUT_OUT" == *"REASON=wrong-current-branch"* ]] \
   && [[ "$SUT_ERR" == *"expected 'feat/x'"* ]] \
   && [ "$(counter "$F/state-git" fetch)" = "0" ] \
   && [ "$(counter "$F/state-git" rebase)" = "0" ]; then
  pass "[issue397] pr-rebase refuses when CWD HEAD != \$BRANCH (exit 14, no fetch, no rebase)"
else
  fail "[issue397] pr-rebase wrong-branch guard" "rc=$SUT_RC out=$SUT_OUT err=$SUT_ERR fetch=$(counter "$F/state-git" fetch) rebase=$(counter "$F/state-git" rebase)"
fi
cleanup_fixture "$F"

# Companion: the HEAD-check happy-path uses `rev-parse --abbrev-ref HEAD`
# returning $BRANCH; rebase proceeds. Asserted via prep_rebase_preflight_ok
# in [mode1]/[mode2]/[idem1]/[slug] above — those tests would fail-loud
# (mock-git exit 99 "no canned response") if the script bypassed the
# HEAD call.

# ----------------------------------------------------------------------
# Issue #481 regression: pr-rebase.sh asserts a clean working tree
# BEFORE calling git rebase. Pre-fix code fell through to the generic
# line-130 failure terminus emitting REASON=rebase-failed exit 11 for
# ALL of: dirty working tree, network failure, abort failure, real
# rebase conflict — overloaded across 4 distinct failure modes.
# /land-pr Step 3 couldn't distinguish.
# Assertion: when `git status --porcelain` returns non-empty, pr-rebase.sh
# exits 16 with REASON=dirty-working-tree, no fetch, no rebase.
# ----------------------------------------------------------------------
F=$(new_fixture issue481_dirty_tree)
prep_git "$F/state-git" rev-parse 1 exit 0
prep_git "$F/state-git" rev-parse 2 exit 0
prep_git "$F/state-git" rev-parse 3 stdout 'feat/x'
# git status --porcelain returns non-empty → dirty tree.
prep_git "$F/state-git" status 1 stdout $' M src/foo.js\n?? new-untracked.txt'
run_sut "$F" bash "$SCRIPTS_DIR/pr-rebase.sh" --branch feat/x --base main
if [ "$SUT_RC" -eq 16 ] \
   && [[ "$SUT_OUT" == *"REASON=dirty-working-tree"* ]] \
   && [[ "$SUT_ERR" == *"uncommitted changes"* ]] \
   && [ "$(counter "$F/state-git" fetch)" = "0" ] \
   && [ "$(counter "$F/state-git" rebase)" = "0" ]; then
  pass "[issue481] pr-rebase refuses dirty working tree (exit 16, no fetch, no rebase)"
else
  fail "[issue481] pr-rebase dirty-tree guard" "rc=$SUT_RC out=$SUT_OUT err=$SUT_ERR fetch=$(counter "$F/state-git" fetch) rebase=$(counter "$F/state-git" rebase)"
fi
cleanup_fixture "$F"

# Companion: the dirty-tree-check happy-path uses `git status --porcelain`
# returning empty; rebase proceeds. The prep_rebase_preflight_ok helper
# below MUST be updated to prep the status call as exit 0 (empty stdout),
# else [mode1]/[mode2]/[idem1]/[slug]/[mode3..] would fail-loud (mock-git
# exit 99 "no canned response").

# ----------------------------------------------------------------------
# Issue #188 regression: pr-push-and-create.sh must push $BRANCH
# explicitly (not bare `git push`). Pre-fix code used CWD's current
# branch via @{u}, which silently no-opped when CWD != $BRANCH.
# Assertion: the recorded `git push` invocation log contains the
# explicit `-u origin <branch>` form.
# ----------------------------------------------------------------------
F=$(new_fixture issue188_explicit_push)
prep_gh  "$F/state-gh"  pr_list   1 stdout '[]'
prep_git "$F/state-git" push      1 exit 0
prep_git "$F/state-git" rev-parse 1 stdout 'abc123'
prep_git "$F/state-git" ls-remote 1 stdout 'abc123	refs/heads/feat/x'
prep_gh  "$F/state-gh"  pr_create 1 stdout 'https://github.com/o/r/pull/77'
mkdir -p "$F/work"; echo "PR body" > "$F/work/body.md"
run_sut "$F" bash "$SCRIPTS_DIR/pr-push-and-create.sh" \
  --branch feat/x --base main --title 'T' --body-file "$F/work/body.md"
INVOCATIONS_FILE="$F/state-git/_invocations.log"
PUSH_LINE=$(grep '^push ' "$INVOCATIONS_FILE" 2>/dev/null || echo "")
if [ "$SUT_RC" -eq 0 ] \
   && [[ "$PUSH_LINE" == *"-u"*"origin"*"feat/x"* ]]; then
  pass "[issue188] pr-push-and-create always pushes \$BRANCH explicitly (-u origin <branch>)"
else
  fail "[issue188] pr-push-and-create explicit-branch push" "rc=$SUT_RC push_line='$PUSH_LINE'"
fi
cleanup_fixture "$F"

# ----------------------------------------------------------------------
# Issue #188 defense-in-depth: post-push verification catches silent
# no-op pushes. Mock push exits 0 but ls-remote returns a different
# (or empty) SHA — assertion: script exits 12 with CALL_ERROR_FILE.
# ----------------------------------------------------------------------
F=$(new_fixture issue188_verify_mismatch)
prep_gh  "$F/state-gh"  pr_list   1 stdout '[]'
prep_git "$F/state-git" push      1 exit 0
prep_git "$F/state-git" rev-parse 1 stdout 'abc123'
# ls-remote returns a different SHA — silent no-op simulation
prep_git "$F/state-git" ls-remote 1 stdout 'deadbeef	refs/heads/feat/x'
mkdir -p "$F/work"; echo "PR body" > "$F/work/body.md"
run_sut "$F" bash "$SCRIPTS_DIR/pr-push-and-create.sh" \
  --branch feat/x --base main --title 'T' --body-file "$F/work/body.md"
if [ "$SUT_RC" -eq 12 ] \
   && [[ "$SUT_OUT" =~ CALL_ERROR_FILE=([^[:space:]]+) ]] \
   && [[ "$SUT_ERR" == *"post-push verification failed"* ]]; then
  pass "[issue188] post-push verification catches local/remote SHA mismatch (exit 12)"
else
  fail "[issue188] post-push verification mismatch" "rc=$SUT_RC out=$SUT_OUT err=$SUT_ERR"
fi
cleanup_fixture "$F"

# Companion: ls-remote returns empty (remote ref not present) — also exit 12.
F=$(new_fixture issue188_verify_empty)
prep_gh  "$F/state-gh"  pr_list   1 stdout '[]'
prep_git "$F/state-git" push      1 exit 0
prep_git "$F/state-git" rev-parse 1 stdout 'abc123'
prep_git "$F/state-git" ls-remote 1 stdout ''
mkdir -p "$F/work"; echo "PR body" > "$F/work/body.md"
run_sut "$F" bash "$SCRIPTS_DIR/pr-push-and-create.sh" \
  --branch feat/x --base main --title 'T' --body-file "$F/work/body.md"
if [ "$SUT_RC" -eq 12 ] \
   && [[ "$SUT_ERR" == *"post-push verification failed"* ]]; then
  pass "[issue188] post-push verification catches empty remote ref (exit 12)"
else
  fail "[issue188] post-push verification empty-remote" "rc=$SUT_RC err=$SUT_ERR"
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
