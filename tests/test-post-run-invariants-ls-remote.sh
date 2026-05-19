#!/bin/bash
# tests/test-post-run-invariants-ls-remote.sh — regression tests for
# Issue #396: post-run-invariants.sh:119 silently passed Invariant #4
# when `ls-remote` returned 128 (origin unreachable / auth / config).
#
# The pre-fix `if git ... ls-remote ... 2>&1; then ... fi` form treated
# rc=2 (absent — invariant satisfied) AND rc=128 (couldn't check at all)
# as identical "pass." A stuck remote branch + broken origin silently
# passed forever. Fix mirrors land-phase.sh's case-block discrimination:
#   rc=0   → branch present → INVARIANT FAIL
#   rc=2   → branch absent  → invariant satisfied
#   rc=128 → cannot verify  → INVARIANT FAIL (loud, not silent)
#
# Same diagnostic-loss antipattern (`2>/dev/null`) appeared on the
# Invariant #7 `git fetch origin main` call at line 180. Fix captures
# git stderr so the WARN line surfaces the underlying reason.
#
# Test strategy: build a real git repo + a real fake "origin" repo, then
# invoke post-run-invariants.sh directly with crafted args. To simulate
# rc=128, point origin at a path that doesn't exist; the real `git
# ls-remote --exit-code` returns 128 with "fatal:" on stderr.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INVARIANTS_SCRIPT="$REPO_ROOT/skills/run-plan/scripts/post-run-invariants.sh"

PASS=0
FAIL=0

pass() { printf '  PASS %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '  FAIL %s — %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

# Create a fresh main repo + bare "origin" repo, with optional branch
# pre-pushed to origin. Sets globals MAIN_DIR, ORIGIN_DIR.
new_repo() {
  local label="$1"
  local fixture="/tmp/post-run-inv-test-$label-$$"
  case "$fixture" in
    /tmp/post-run-inv-test-*) : ;;
    *) echo "REFUSING non-/tmp fixture path: $fixture" >&2; exit 1 ;;
  esac
  rm -rf "$fixture"
  mkdir -p "$fixture"
  MAIN_DIR="$fixture/main"
  ORIGIN_DIR="$fixture/origin.git"
  FIXTURE_DIR="$fixture"

  git init --quiet --initial-branch=main "$MAIN_DIR"
  git -C "$MAIN_DIR" config user.email "test@example.com"
  git -C "$MAIN_DIR" config user.name "Test"

  # bare origin
  git init --quiet --bare --initial-branch=main "$ORIGIN_DIR"

  # initial commit so main has a HEAD
  echo "x" > "$MAIN_DIR/README"
  git -C "$MAIN_DIR" add README
  git -C "$MAIN_DIR" commit --quiet -m "init"
  git -C "$MAIN_DIR" remote add origin "$ORIGIN_DIR"
  git -C "$MAIN_DIR" push --quiet origin main 2>/dev/null
}

cleanup_repo() {
  case "$FIXTURE_DIR" in
    /tmp/post-run-inv-test-*) rm -rf "$FIXTURE_DIR" ;;
    *) echo "REFUSING to clean non-/tmp path: $FIXTURE_DIR" >&2 ;;
  esac
}

# Run the invariants script. Sets RC, OUT, ERR.
run_invariants() {
  local branch="$1"
  local landed_status="$2"
  # Note: We must invoke from inside MAIN_DIR so the script's
  # `git rev-parse --git-common-dir` finds the repo. We DON'T pass
  # --worktree (irrelevant here — we're testing Invariant #4/#7 only).
  # We also DON'T pass --plan-slug/--plan-file so Invariants #5/#6
  # auto-skip. We require the script's `source .../zskills-paths.sh`
  # to work — but the test repo doesn't have that file. To avoid
  # that, we just check stderr/stdout strings and exit code; we
  # ALSO copy the helper into the fixture.
  mkdir -p "$MAIN_DIR/.claude/skills/update-zskills/scripts"
  cp "$REPO_ROOT/skills/update-zskills/scripts/zskills-paths.sh" \
     "$MAIN_DIR/.claude/skills/update-zskills/scripts/zskills-paths.sh"
  local out_file="$FIXTURE_DIR/out.txt"
  local err_file="$FIXTURE_DIR/err.txt"
  (
    cd "$MAIN_DIR"
    bash "$INVARIANTS_SCRIPT" \
      --worktree "" \
      --branch "$branch" \
      --landed-status "$landed_status" \
      --plan-slug "" \
      --plan-file ""
  ) > "$out_file" 2> "$err_file"
  RC=$?
  OUT=$(cat "$out_file")
  ERR=$(cat "$err_file")
}

# ---- Test 1: rc=0 — branch present on origin → Invariant #4 fails ----
test_invariant4_present() {
  new_repo "inv4-present"
  # Push a feature branch to origin so ls-remote returns 0
  git -C "$MAIN_DIR" checkout --quiet -b feat/stuck
  echo "y" > "$MAIN_DIR/y"
  git -C "$MAIN_DIR" add y
  git -C "$MAIN_DIR" commit --quiet -m "feat"
  git -C "$MAIN_DIR" push --quiet origin feat/stuck 2>/dev/null
  git -C "$MAIN_DIR" checkout --quiet main

  run_invariants "feat/stuck" "landed"

  if [ "$RC" -ne 0 ] && echo "$ERR" | grep -q "INVARIANT-FAIL (#4)" \
     && echo "$ERR" | grep -q "still exists after landed"; then
    pass "Invariant #4 fails when remote branch still present (rc=0)"
  else
    fail "Invariant #4 fails when remote branch still present (rc=0)" \
         "RC=$RC; ERR=$ERR"
  fi
  cleanup_repo
}

# ---- Test 2: rc=2 — branch absent → Invariant #4 passes ----
test_invariant4_absent() {
  new_repo "inv4-absent"
  # Don't push feat/clean — origin doesn't have it
  run_invariants "feat/clean" "landed"

  if [ "$RC" -eq 0 ] && ! echo "$ERR" | grep -q "INVARIANT-FAIL (#4)"; then
    pass "Invariant #4 passes when remote branch absent (rc=2)"
  else
    fail "Invariant #4 passes when remote branch absent (rc=2)" \
         "RC=$RC; ERR=$ERR"
  fi
  cleanup_repo
}

# ---- Test 3: rc=128 — origin unreachable → Invariant #4 fails LOUD ----
# This is the regression case. Pre-fix: silently passed.
test_invariant4_rc128_fails_loud() {
  new_repo "inv4-rc128"
  # Break origin so ls-remote returns 128.
  git -C "$MAIN_DIR" remote set-url origin /nonexistent/path/to/nowhere.git
  run_invariants "feat/anything" "landed"

  if [ "$RC" -ne 0 ] \
     && echo "$ERR" | grep -q "INVARIANT-FAIL (#4)" \
     && echo "$ERR" | grep -qE "ls-remote.*failed with exit [0-9]+"; then
    pass "Invariant #4 fails LOUD on rc=128 (was silent pass pre-fix)"
  else
    fail "Invariant #4 fails LOUD on rc=128 (was silent pass pre-fix)" \
         "RC=$RC; ERR=$ERR"
  fi
  cleanup_repo
}

# ---- Test 4: Invariant #4 surfaces git stderr on rc!=0,2 ----
test_invariant4_rc128_surfaces_stderr() {
  new_repo "inv4-stderr"
  git -C "$MAIN_DIR" remote set-url origin /nonexistent/path/to/nowhere.git
  run_invariants "feat/anything" "landed"

  if echo "$ERR" | grep -q "git stderr:"; then
    pass "Invariant #4 rc=128 surfaces underlying git stderr"
  else
    fail "Invariant #4 rc=128 surfaces underlying git stderr" \
         "ERR=$ERR"
  fi
  cleanup_repo
}

# ---- Test 5: Invariant #7 fetch failure surfaces git stderr ----
# This is the same antipattern at line 180 (2>/dev/null). Pre-fix:
# WARN line existed but no diagnostic detail.
test_invariant7_fetch_failure_surfaces_stderr() {
  new_repo "inv7-fetch-fail"
  # Break origin so `git fetch origin main` fails non-zero.
  git -C "$MAIN_DIR" remote set-url origin /nonexistent/path/to/nowhere.git
  run_invariants "" ""

  if echo "$ERR" | grep -q "INVARIANT-WARN (#7).*fetch.*failed" \
     && echo "$ERR" | grep -q "git stderr:"; then
    pass "Invariant #7 fetch failure surfaces git stderr"
  else
    fail "Invariant #7 fetch failure surfaces git stderr" \
         "ERR=$ERR"
  fi
  cleanup_repo
}

# ---- Test 6: Invariant #7 WARN does not fail the script ----
test_invariant7_fetch_warn_does_not_fail() {
  new_repo "inv7-fetch-warn-nofail"
  git -C "$MAIN_DIR" remote set-url origin /nonexistent/path/to/nowhere.git
  run_invariants "" ""

  # No Invariant #4 triggers (LANDED_STATUS="" gates it off). Only #7
  # fires, which is WARN not FAIL → exit 0.
  if [ "$RC" -eq 0 ]; then
    pass "Invariant #7 fetch failure is WARN (rc=0)"
  else
    fail "Invariant #7 fetch failure is WARN (rc=0)" \
         "RC=$RC; ERR=$ERR"
  fi
  cleanup_repo
}

# ---- Run all ----
test_invariant4_present
test_invariant4_absent
test_invariant4_rc128_fails_loud
test_invariant4_rc128_surfaces_stderr
test_invariant7_fetch_failure_surfaces_stderr
test_invariant7_fetch_warn_does_not_fail

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
