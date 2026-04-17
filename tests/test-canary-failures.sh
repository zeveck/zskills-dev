#!/bin/bash
# tests/test-canary-failures.sh — regression suite for silent-failure catches.
#
# Each section asserts loud-failure behavior for one enforcing layer
# (hook / script / skill prompt). Run standalone or via tests/run-all.sh.

set -u

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
FIXTURES="$REPO_ROOT/tests/fixtures/canary"
PASS_COUNT=0
FAIL_COUNT=0
FIXTURE_DIRS=()

cleanup_fixtures() {
  if [ "${#FIXTURE_DIRS[@]}" -eq 0 ]; then return; fi
  local d
  for d in "${FIXTURE_DIRS[@]}"; do
    [ -n "$d" ] && [ -d "$d" ] && chmod -R u+w "$d" 2>/dev/null
    [ -n "$d" ] && [ -d "$d" ] && rm -rf "$d"
  done
}
trap cleanup_fixtures EXIT

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }
section() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# Hook helper: construct JSON on stdin, assert deny + substring
expect_deny_substring() {
  local label="$1" cmd="$2" want="$3" hook="$4"
  local json result
  json=$(printf '{"tool_name":"Bash","tool_input":{"command":%s}}' \
    "$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')")
  result=$(printf '%s' "$json" | bash "$hook" 2>/dev/null) || true
  if [[ "$result" == *'"permissionDecision":"deny"'* && "$result" == *"$want"* ]]; then
    pass "$label"
  else
    fail "$label — want deny with '$want', got: $result"
  fi
}

expect_allow() {
  local label="$1" cmd="$2" hook="$3"
  local json result
  json=$(printf '{"tool_name":"Bash","tool_input":{"command":%s}}' \
    "$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')")
  result=$(printf '%s' "$json" | bash "$hook" 2>/dev/null) || true
  if [[ -z "$result" ]]; then
    pass "$label"
  else
    fail "$label — expected empty stdout, got: $result"
  fi
}

# Script helper: run a command, assert rc + stderr substring
expect_script_exit() {
  local label="$1" want_rc="$2" want_stderr="$3"
  shift 3
  local out rc
  out=$("$@" 2>&1) || rc=$?
  rc=${rc:-0}
  if [ "$rc" -eq "$want_rc" ] && [[ "$out" == *"$want_stderr"* ]]; then
    pass "$label"
  else
    fail "$label — rc=$rc want=$want_rc; '$want_stderr' substring? $out"
  fi
}

# Fixture helper: throwaway git repo, auto-cleanup
setup_fixture_repo() {
  local tmp
  tmp=$(mktemp -d)
  FIXTURE_DIRS+=("$tmp")
  git -C "$tmp" init -q
  git -C "$tmp" config user.email "canary@test.local"
  git -C "$tmp" config user.name "canary"
  git -C "$tmp" commit --allow-empty -q -m "init"
  echo "$tmp"
}

setup_bare_origin() {
  local tmp
  tmp=$(mktemp -d)
  FIXTURE_DIRS+=("$tmp")
  git init -q --bare "$tmp"
  echo "$tmp"
}

mkdir -p "$FIXTURES"

# --- test sections appended by each phase ---

# (Phase 1 adds: stash)
# (Phase 2 adds: land-phase)
# (Phase 3 adds: invariants)
# (Phase 4 adds: block-agents)
# (Phase 5 adds: commit-reviewer)

HOOK="$REPO_ROOT/hooks/block-unsafe-generic.sh"

section "Stash writes denied (6 cases)"
STASH_WRITE_DENY="BLOCKED: git-stash write subcommand forbidden"
STASH_DESTRUCTIVE_DENY="BLOCKED: git stash drop/clear destroys stashed work permanently"
expect_deny_substring "git stash"              "git stash"              "$STASH_WRITE_DENY"       "$HOOK"
expect_deny_substring "git stash -u"           "git stash -u"           "$STASH_WRITE_DENY"       "$HOOK"
expect_deny_substring 'git stash save "msg"'   'git stash save "msg"'   "$STASH_WRITE_DENY"       "$HOOK"
expect_deny_substring 'git stash push -m "msg"' 'git stash push -m "msg"' "$STASH_WRITE_DENY"     "$HOOK"
expect_deny_substring "git stash drop"         "git stash drop"         "$STASH_DESTRUCTIVE_DENY" "$HOOK"
expect_deny_substring "git stash clear"        "git stash clear"        "$STASH_DESTRUCTIVE_DENY" "$HOOK"

section "Stash reads allowed (7 cases)"
expect_allow "git stash apply"         "git stash apply"         "$HOOK"
expect_allow "git stash list"          "git stash list"          "$HOOK"
expect_allow "git stash show"          "git stash show"          "$HOOK"
expect_allow "git stash pop"           "git stash pop"           "$HOOK"
expect_allow "git stash create"        "git stash create"        "$HOOK"
expect_allow "git stash store abc123"  "git stash store abc123"  "$HOOK"
expect_allow "git stash branch foo"    "git stash branch foo"    "$HOOK"

section "Stash overmatch prevention (5 cases)"
expect_allow 'commit message mentions git stash' 'git commit -m "refactor: remove old git stash logic"' "$HOOK"
expect_allow 'echo "git stash push"'   'echo "git stash push"'   "$HOOK"
expect_allow 'grep "git stash" file'   'grep "git stash" somefile.txt' "$HOOK"
expect_allow "printf 'git stash save\\n'" "printf 'git stash save\\n'" "$HOOK"
expect_allow 'heredoc containing git stash -u' "$(printf 'cat <<EOF\ngit stash -u\nEOF')" "$HOOK"

# ---------------------------------------------------------------------------
# Phase 2 — land-phase.sh reproducers
# ---------------------------------------------------------------------------
# Script signature is ONE arg: `bash scripts/land-phase.sh <worktree-path>`.
# MAIN_ROOT resolution uses `git rev-parse --git-common-dir` from CWD, so
# every invocation subshell-cd's into the fixture's primary repo first.
SCRIPT="$REPO_ROOT/scripts/land-phase.sh"

section "land-phase.sh: dirty worktree refused (1 case)"
dirty_primary=$(setup_fixture_repo)
dirty_worktree=$(mktemp -u)
FIXTURE_DIRS+=("$dirty_worktree")
git -C "$dirty_primary" worktree add -q "$dirty_worktree" -b canary/test
printf 'status: landed\n' > "$dirty_worktree/.landed"
printf 'dirty\n' > "$dirty_worktree/untracked.txt"
expect_script_exit \
  "dirty worktree: rc=1 with cleanliness error" \
  1 \
  "ERROR: Worktree $dirty_worktree is not clean — cannot safely remove." \
  bash -c "cd \"$dirty_primary\" && bash \"$SCRIPT\" \"$dirty_worktree\""

section "land-phase.sh: tracked ephemeral rejected (4 cases)"
# Array-drift guard: confirm scripts/land-phase.sh still lists exactly the
# four ephemeral names we cover below. If the script's list drifts from
# this plan's list, fail loudly so test authors update this phase rather
# than silently passing against a changed list.
EXPECTED_EPHEMERAL='EPHEMERAL_FILES=(".test-results.txt" ".test-baseline.txt" ".worktreepurpose" ".zskills-tracked")'
if grep -qxF "$EXPECTED_EPHEMERAL" "$REPO_ROOT/scripts/land-phase.sh"; then
  pass "array-drift guard: scripts/land-phase.sh EPHEMERAL_FILES matches plan"
else
  fail "array-drift guard: scripts/land-phase.sh EPHEMERAL_FILES does NOT match plan list — update this phase"
fi

for eph in ".test-results.txt" ".test-baseline.txt" ".worktreepurpose" ".zskills-tracked"; do
  eph_primary=$(setup_fixture_repo)
  eph_worktree=$(mktemp -u)
  FIXTURE_DIRS+=("$eph_worktree")
  git -C "$eph_primary" worktree add -q "$eph_worktree" -b "canary/eph"
  # Commit the ephemeral file into the feature branch so it is tracked in
  # the worktree when land-phase.sh runs.
  printf 'tracked ephemeral\n' > "$eph_worktree/$eph"
  git -C "$eph_worktree" add -- "$eph"
  git -C "$eph_worktree" commit -q -m "add tracked ephemeral $eph"
  printf 'status: landed\n' > "$eph_worktree/.landed"
  expect_script_exit \
    "tracked ephemeral $eph: rc=1 with rejection error" \
    1 \
    "ERROR: $eph is git-tracked in $eph_worktree but should be untracked." \
    bash -c "cd \"$eph_primary\" && bash \"$SCRIPT\" \"$eph_worktree\""
done

section "land-phase.sh: ls-remote exit code handling (3 cases)"

# Case A — origin has the branch, ls-remote rc=0 → delete path taken,
# script succeeds and emits `Worktree removed:`.
ca_primary=$(setup_fixture_repo)
ca_origin=$(setup_bare_origin)
git -C "$ca_primary" remote add origin "$ca_origin"
git -C "$ca_primary" push -q origin HEAD:refs/heads/main
ca_worktree=$(mktemp -u)
FIXTURE_DIRS+=("$ca_worktree")
git -C "$ca_primary" worktree add -q "$ca_worktree" -b "canary/ls-a"
git -C "$ca_worktree" push -q origin canary/ls-a
printf 'status: landed\n' > "$ca_worktree/.landed"
expect_script_exit \
  "ls-remote Case A (rc=0 → delete): success, worktree removed" \
  0 \
  "Worktree removed:" \
  bash -c "cd \"$ca_primary\" && bash \"$SCRIPT\" \"$ca_worktree\""

# Case B — origin does NOT have the branch, ls-remote rc=2 → skip-delete
# path taken, script succeeds and emits `already absent — skipping delete.`
cb_primary=$(setup_fixture_repo)
cb_origin=$(setup_bare_origin)
git -C "$cb_primary" remote add origin "$cb_origin"
git -C "$cb_primary" push -q origin HEAD:refs/heads/main
cb_worktree=$(mktemp -u)
FIXTURE_DIRS+=("$cb_worktree")
git -C "$cb_primary" worktree add -q "$cb_worktree" -b "canary/ls-b"
# Intentionally do NOT push canary/ls-b to origin.
printf 'status: landed\n' > "$cb_worktree/.landed"
expect_script_exit \
  "ls-remote Case B (rc=2 → absent): success, skipping delete" \
  0 \
  "Remote branch canary/ls-b already absent — skipping delete." \
  bash -c "cd \"$cb_primary\" && bash \"$SCRIPT\" \"$cb_worktree\""

# Case C — origin URL points at a path that does not exist, ls-remote
# rc=128 → loud failure. Confirm sentinel path genuinely absent before we
# rely on it for the rc=128 repro.
cc_sentinel="/nonexistent/bare-repo-canary"
if [ -e "$cc_sentinel" ]; then
  fail "ls-remote Case C precondition: $cc_sentinel unexpectedly exists — rc=128 repro unreliable"
else
  cc_primary=$(setup_fixture_repo)
  cc_origin=$(setup_bare_origin)
  git -C "$cc_primary" remote add origin "$cc_origin"
  git -C "$cc_primary" push -q origin HEAD:refs/heads/main
  cc_worktree=$(mktemp -u)
  FIXTURE_DIRS+=("$cc_worktree")
  git -C "$cc_primary" worktree add -q "$cc_worktree" -b "canary/ls-c"
  printf 'status: landed\n' > "$cc_worktree/.landed"
  # Overwrite origin URL to nonexistent path AFTER all setup so the
  # push to main above still worked. Now ls-remote will fail with 128.
  git -C "$cc_primary" remote set-url origin "file://$cc_sentinel"
  expect_script_exit \
    "ls-remote Case C (rc=128 → unreachable): loud failure" \
    1 \
    "ERROR: git ls-remote for canary/ls-c failed with exit 128 — origin unreachable, misconfigured, or auth failure" \
    bash -c "cd \"$cc_primary\" && bash \"$SCRIPT\" \"$cc_worktree\""
fi

section "land-phase.sh: /tmp test-output dir cleanup (1 case)"
# Rationale: commit 66d9138 extended land-phase.sh to remove
# /tmp/zskills-tests/<basename-of-worktree>/ on successful landing. Lock
# this in so a future edit can't silently regress it.
tc_primary=$(setup_fixture_repo)
tc_origin=$(setup_bare_origin)
git -C "$tc_primary" remote add origin "$tc_origin"
git -C "$tc_primary" push -q origin HEAD:refs/heads/main
tc_worktree=$(mktemp -u)
FIXTURE_DIRS+=("$tc_worktree")
git -C "$tc_primary" worktree add -q "$tc_worktree" -b "canary/tmp-clean"
git -C "$tc_worktree" push -q origin canary/tmp-clean
printf 'status: landed\n' > "$tc_worktree/.landed"
tc_tmpdir="/tmp/zskills-tests/$(basename "$tc_worktree")"
mkdir -p "$tc_tmpdir"
touch "$tc_tmpdir/.canary-sentinel"
tc_out=$(cd "$tc_primary" && bash "$SCRIPT" "$tc_worktree" 2>&1); tc_rc=$?
if [ "$tc_rc" -eq 0 ] && [ ! -d "$tc_tmpdir" ]; then
  pass "/tmp test-output dir cleanup: rc=0 and $tc_tmpdir removed"
else
  fail "/tmp test-output dir cleanup — rc=$tc_rc (want 0); dir still present? [ -d \"$tc_tmpdir\" ]=$([ -d "$tc_tmpdir" ] && echo yes || echo no); output: $tc_out"
fi

echo
echo "Canary failure-injection: $PASS_COUNT passed, $FAIL_COUNT failed"
exit $((FAIL_COUNT > 0))
