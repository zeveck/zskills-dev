#!/bin/bash
# tests/test-canary-failures.sh — regression suite for silent-failure catches.
#
# Each section asserts loud-failure behavior for one enforcing layer
# (hook / script / skill prompt). Run standalone or via tests/run-all.sh.

set -u

# Derive REPO_ROOT from the script's own location, not from CWD. This
# makes the suite robust to any invocation directory (aggregator runs
# from the repo root, but ad-hoc invocations from elsewhere should still
# find the committed fixture files under tests/fixtures/canary/).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
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

section "write-landed.sh: rc-checked atomic marker writes (3 cases)"
# Locks in the rc-check behavior introduced with scripts/write-landed.sh.
# The ad-hoc cat+mv pattern this helper replaces silently wrote empty/
# partial markers on disk-full / read-only failures; the helper catches
# those via `if ! cat ...` and `if ! mv ...` with loud stderr + rc=1.

WRITE_LANDED="$REPO_ROOT/scripts/write-landed.sh"

# Case 1: happy path — cat body into helper, .landed ends up with correct content.
wl_primary=$(setup_fixture_repo)
wl_worktree=$(mktemp -u)
FIXTURE_DIRS+=("$wl_worktree")
git -C "$wl_primary" worktree add -q "$wl_worktree" -b canary/wl-happy
if printf 'status: landed\ndate: now\n' | bash "$WRITE_LANDED" "$wl_worktree" \
   && [ -f "$wl_worktree/.landed" ] \
   && grep -qxF 'status: landed' "$wl_worktree/.landed" \
   && [ ! -f "$wl_worktree/.landed.tmp" ]; then
  pass "write-landed.sh happy path: .landed written, .tmp cleaned"
else
  fail "write-landed.sh happy path — .landed content or .tmp-cleanup wrong"
fi

# Case 2: missing/bad worktree arg — exit 1 with specific error.
wl_bad_out=$(printf 'status: landed\n' | bash "$WRITE_LANDED" 2>&1); wl_bad_rc=$?
if [ "$wl_bad_rc" -eq 1 ] && [[ "$wl_bad_out" == *"requires a worktree-path arg"* ]]; then
  pass "write-landed.sh missing arg: rc=1 with usage error"
else
  fail "write-landed.sh missing arg — rc=$wl_bad_rc; out: $wl_bad_out"
fi

# Case 3: worktree path doesn't exist — exit 1 with specific error.
wl_nx_out=$(printf 'status: landed\n' | bash "$WRITE_LANDED" /tmp/write-landed-nx-$$-canary 2>&1); wl_nx_rc=$?
if [ "$wl_nx_rc" -eq 1 ] && [[ "$wl_nx_out" == *"worktree path does not exist"* ]]; then
  pass "write-landed.sh nonexistent path: rc=1 with path error"
else
  fail "write-landed.sh nonexistent path — rc=$wl_nx_rc; out: $wl_nx_out"
fi

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

section "worktree-add-safe.sh: poisoned-branch discrimination (6 cases)"
# Locks in the classification taxonomy introduced with the helper script:
# fresh / equivalent-to-main / behind-only / ahead-no-optin /
# ahead-with-optin / path-already-exists. Each fixture renames its default
# branch to 'main' so the helper's default BASE argument works.

# Case 1 — fresh branch: no local, no remote → rc=0, helper creates via -b.
ws1_primary=$(setup_fixture_repo)
git -C "$ws1_primary" branch -M main
ws1_wt=$(mktemp -u)
FIXTURE_DIRS+=("$ws1_wt")
expect_script_exit \
  "worktree-add-safe Case 1 (fresh): rc=0, new worktree via -b" \
  0 \
  "Preparing worktree" \
  bash -c "cd \"$ws1_primary\" && bash \"$REPO_ROOT/scripts/worktree-add-safe.sh\" canary/ws-fresh \"$ws1_wt\" main"

# Case 2 — equivalent-to-main: branch points at main tip (0 ahead, 0 behind)
# → rc=0, helper deletes stale ref and creates fresh.
ws2_primary=$(setup_fixture_repo)
git -C "$ws2_primary" branch -M main
# Force-create the stale ref at main tip so rev-list counts are both 0.
git -C "$ws2_primary" branch -f canary/ws-equiv main
# Sanity-check the fixture: both counts must be 0 before invoking the helper.
ws2_ahead=$(git -C "$ws2_primary" rev-list --count main..canary/ws-equiv)
ws2_behind=$(git -C "$ws2_primary" rev-list --count canary/ws-equiv..main)
if [ "$ws2_ahead" != "0" ] || [ "$ws2_behind" != "0" ]; then
  fail "Case 2 fixture bad: ahead=$ws2_ahead behind=$ws2_behind (want 0/0)"
fi
ws2_wt=$(mktemp -u)
FIXTURE_DIRS+=("$ws2_wt")
expect_script_exit \
  "worktree-add-safe Case 2 (equivalent-to-main): rc=0, stale ref deleted" \
  0 \
  "equivalent to main — deleting stale ref" \
  bash -c "cd \"$ws2_primary\" && bash \"$REPO_ROOT/scripts/worktree-add-safe.sh\" canary/ws-equiv \"$ws2_wt\" main"

# Case 3 — behind-only (poisoned): branch from old main, main advances →
# rc=3 with "poisoned stale branch" stderr.
ws3_primary=$(setup_fixture_repo)
git -C "$ws3_primary" branch -M main
# Create branch at current main tip, then advance main past it.
git -C "$ws3_primary" branch canary/ws-behind main
git -C "$ws3_primary" commit --allow-empty -q -m "main advance 1"
git -C "$ws3_primary" commit --allow-empty -q -m "main advance 2"
ws3_wt=$(mktemp -u)
FIXTURE_DIRS+=("$ws3_wt")
expect_script_exit \
  "worktree-add-safe Case 3 (behind-only poisoned): rc=3 with poisoning message" \
  3 \
  "poisoned stale branch" \
  bash -c "cd \"$ws3_primary\" && bash \"$REPO_ROOT/scripts/worktree-add-safe.sh\" canary/ws-behind \"$ws3_wt\" main"

# Case 4 — ahead without opt-in: branch ahead of main, no env var → rc=4
# with ZSKILLS_ALLOW_BRANCH_RESUME guidance.
ws4_primary=$(setup_fixture_repo)
git -C "$ws4_primary" branch -M main
# Create a branch with one commit ahead of main.
git -C "$ws4_primary" checkout -q -b canary/ws-ahead-no
git -C "$ws4_primary" commit --allow-empty -q -m "branch work"
git -C "$ws4_primary" checkout -q main
ws4_wt=$(mktemp -u)
FIXTURE_DIRS+=("$ws4_wt")
expect_script_exit \
  "worktree-add-safe Case 4 (ahead, no opt-in): rc=4 with opt-in guidance" \
  4 \
  "set ZSKILLS_ALLOW_BRANCH_RESUME=1" \
  bash -c "cd \"$ws4_primary\" && unset ZSKILLS_ALLOW_BRANCH_RESUME; bash \"$REPO_ROOT/scripts/worktree-add-safe.sh\" canary/ws-ahead-no \"$ws4_wt\" main"

# Case 5 — ahead WITH opt-in: same setup as Case 4, env var set → rc=0,
# helper attaches worktree to existing branch (no -b flag).
ws5_primary=$(setup_fixture_repo)
git -C "$ws5_primary" branch -M main
git -C "$ws5_primary" checkout -q -b canary/ws-ahead-yes
git -C "$ws5_primary" commit --allow-empty -q -m "branch work"
git -C "$ws5_primary" checkout -q main
ws5_wt=$(mktemp -u)
FIXTURE_DIRS+=("$ws5_wt")
expect_script_exit \
  "worktree-add-safe Case 5 (ahead + opt-in): rc=0, attaches to existing branch" \
  0 \
  "resuming on existing branch canary/ws-ahead-yes" \
  bash -c "cd \"$ws5_primary\" && ZSKILLS_ALLOW_BRANCH_RESUME=1 bash \"$REPO_ROOT/scripts/worktree-add-safe.sh\" canary/ws-ahead-yes \"$ws5_wt\" main"

# Case 6 — worktree path already exists (caller bug): dir pre-created →
# rc=2 with "caller must handle" error, no worktree registered.
ws6_primary=$(setup_fixture_repo)
git -C "$ws6_primary" branch -M main
ws6_wt=$(mktemp -d)
FIXTURE_DIRS+=("$ws6_wt")
expect_script_exit \
  "worktree-add-safe Case 6 (path exists, caller bug): rc=2 with caller-must-handle" \
  2 \
  "caller must handle resume before invoking this helper" \
  bash -c "cd \"$ws6_primary\" && bash \"$REPO_ROOT/scripts/worktree-add-safe.sh\" canary/ws-exists \"$ws6_wt\" main"

# ---------------------------------------------------------------------------
# Phase 3 — post-run-invariants.sh reproducers
# ---------------------------------------------------------------------------
# Script takes 5 required flags: --worktree, --branch, --landed-status,
# --plan-slug, --plan-file. Pass empty string for flags not relevant to
# a given invariant. MAIN_ROOT is resolved via `git rev-parse
# --git-common-dir`, so every invocation subshell-cd's into the fixture's
# primary repo first.
INVARIANTS_SCRIPT="$REPO_ROOT/scripts/post-run-invariants.sh"

section "Invariant #1: worktree on disk (1 case)"
i1_primary=$(setup_fixture_repo)
i1_stray=$(mktemp -d)
FIXTURE_DIRS+=("$i1_stray")
expect_script_exit \
  "invariant #1: worktree directory still on disk" \
  1 \
  "INVARIANT-FAIL (#1): worktree still on disk at $i1_stray" \
  bash -c "cd \"$i1_primary\" && bash \"$INVARIANTS_SCRIPT\" --worktree \"$i1_stray\" --branch \"\" --landed-status \"\" --plan-slug \"\" --plan-file \"\""

section "Invariant #2: worktree in registry (1 case)"
i2_primary=$(setup_fixture_repo)
i2_worktree=$(mktemp -u)
FIXTURE_DIRS+=("$i2_worktree")
# Don't name a base commit — setup_fixture_repo uses git's default branch
# (may be master), so let git pick HEAD.
git -C "$i2_primary" worktree add -q "$i2_worktree" -b canary/test-2
# Wipe directory off disk but leave registry entry so only #2 fires.
rm -rf "$i2_worktree"
expect_script_exit \
  "invariant #2: worktree still in git registry" \
  1 \
  "INVARIANT-FAIL (#2): $i2_worktree still in git worktree registry" \
  bash -c "cd \"$i2_primary\" && bash \"$INVARIANTS_SCRIPT\" --worktree \"$i2_worktree\" --branch \"\" --landed-status \"\" --plan-slug \"\" --plan-file \"\""

section "Invariant #3: local branch after landed (2 cases)"
# Fire case: branch still present under landed status.
i3a_primary=$(setup_fixture_repo)
git -C "$i3a_primary" branch canary/test-3
expect_script_exit \
  "invariant #3 fire: local branch present + landed" \
  1 \
  "INVARIANT-FAIL (#3): local branch canary/test-3 still exists after landed" \
  bash -c "cd \"$i3a_primary\" && bash \"$INVARIANTS_SCRIPT\" --worktree \"\" --branch canary/test-3 --landed-status landed --plan-slug \"\" --plan-file \"\""

# Negative case: pr-ready intentionally keeps the branch — must NOT fail.
i3b_primary=$(setup_fixture_repo)
git -C "$i3b_primary" branch canary/test-3
i3b_out=$(cd "$i3b_primary" && bash "$INVARIANTS_SCRIPT" \
  --worktree "" --branch canary/test-3 --landed-status pr-ready \
  --plan-slug "" --plan-file "" 2>&1); i3b_rc=$?
if [ "$i3b_rc" -eq 0 ] && [[ "$i3b_out" != *"INVARIANT-FAIL (#3):"* ]]; then
  pass "invariant #3 negative: pr-ready keeps branch, no #3 failure"
else
  fail "invariant #3 negative — rc=$i3b_rc (want 0); '#3' absent? out: $i3b_out"
fi

section "Invariant #4: remote branch after landed (2 cases)"
# Fire case: branch pushed to origin + landed status.
i4a_primary=$(setup_fixture_repo)
i4a_origin=$(setup_bare_origin)
git -C "$i4a_primary" remote add origin "$i4a_origin"
git -C "$i4a_primary" push -q origin HEAD:refs/heads/main
# Push HEAD directly (no local branch named canary/test-4 is ever created),
# so #3 cannot co-fire and pollute the #4 assertion.
git -C "$i4a_primary" push -q origin HEAD:refs/heads/canary/test-4
expect_script_exit \
  "invariant #4 fire: remote branch present + landed" \
  1 \
  "INVARIANT-FAIL (#4): remote branch origin/canary/test-4 still exists after landed" \
  bash -c "cd \"$i4a_primary\" && bash \"$INVARIANTS_SCRIPT\" --worktree \"\" --branch canary/test-4 --landed-status landed --plan-slug \"\" --plan-file \"\""

# Negative case: same fixture shape but landed-status=pr-ready — #4 must not fire.
i4b_primary=$(setup_fixture_repo)
i4b_origin=$(setup_bare_origin)
git -C "$i4b_primary" remote add origin "$i4b_origin"
git -C "$i4b_primary" push -q origin HEAD:refs/heads/main
git -C "$i4b_primary" push -q origin HEAD:refs/heads/canary/test-4
i4b_out=$(cd "$i4b_primary" && bash "$INVARIANTS_SCRIPT" \
  --worktree "" --branch canary/test-4 --landed-status pr-ready \
  --plan-slug "" --plan-file "" 2>&1); i4b_rc=$?
if [ "$i4b_rc" -eq 0 ] && [[ "$i4b_out" != *"INVARIANT-FAIL (#4):"* ]]; then
  pass "invariant #4 negative: pr-ready keeps remote branch, no #4 failure"
else
  fail "invariant #4 negative — rc=$i4b_rc (want 0); '#4' absent? out: $i4b_out"
fi

section "Invariant #5: plan report missing (2 cases)"
# Fire case: fresh fixture repo with no reports/ dir.
i5a_primary=$(setup_fixture_repo)
expect_script_exit \
  "invariant #5 fire: missing plan report" \
  1 \
  "INVARIANT-FAIL (#5): plan report missing at" \
  bash -c "cd \"$i5a_primary\" && bash \"$INVARIANTS_SCRIPT\" --worktree \"\" --branch \"\" --landed-status \"\" --plan-slug canary-5 --plan-file \"\""

# Negative case: create the report, assert rc=0.
i5b_primary=$(setup_fixture_repo)
mkdir -p "$i5b_primary/reports"
touch "$i5b_primary/reports/plan-canary-5.md"
i5b_out=$(cd "$i5b_primary" && bash "$INVARIANTS_SCRIPT" \
  --worktree "" --branch "" --landed-status "" \
  --plan-slug canary-5 --plan-file "" 2>&1); i5b_rc=$?
if [ "$i5b_rc" -eq 0 ] && [[ "$i5b_out" != *"INVARIANT-FAIL (#5):"* ]]; then
  pass "invariant #5 negative: report present, no #5 failure"
else
  fail "invariant #5 negative — rc=$i5b_rc (want 0); '#5' absent? out: $i5b_out"
fi

section "Invariant #6: in-progress sentinel in plan (3 cases)"
# Fixture files are committed to the repo (tests/fixtures/canary/). Pass
# the path through --plan-file; invariant #6 reads only that file.
i6_fire_plan="$REPO_ROOT/tests/fixtures/canary/plan-with-sentinel.md"
i6_negative_plan="$REPO_ROOT/tests/fixtures/canary/plan-without-sentinel.md"
i6_prose_plan="$REPO_ROOT/tests/fixtures/canary/plan-prose-sentinel.md"

# Fire case: fixture has 🟡 in a markdown table row.
i6a_primary=$(setup_fixture_repo)
expect_script_exit \
  "invariant #6 fire: plan has sentinel in a table row" \
  1 \
  "INVARIANT-FAIL (#6):" \
  bash -c "cd \"$i6a_primary\" && bash \"$INVARIANTS_SCRIPT\" --worktree \"\" --branch \"\" --landed-status \"\" --plan-slug \"\" --plan-file \"$i6_fire_plan\""

# Negative case A: clean plan (no sentinel anywhere) — must not fire #6.
i6b_primary=$(setup_fixture_repo)
i6b_out=$(cd "$i6b_primary" && bash "$INVARIANTS_SCRIPT" \
  --worktree "" --branch "" --landed-status "" --plan-slug "" \
  --plan-file "$i6_negative_plan" 2>&1); i6b_rc=$?
if [ "$i6b_rc" -eq 0 ] && [[ "$i6b_out" != *"INVARIANT-FAIL (#6):"* ]]; then
  pass "invariant #6 negative: clean plan, no #6 failure"
else
  fail "invariant #6 negative — rc=$i6b_rc (want 0); '#6' absent? out: $i6b_out"
fi

# Negative case B (regression guard for row-scoped grep): plan mentions
# the sentinel in PROSE only — table rows are all ✅/⬚. Must NOT fire
# #6. If invariant #6 ever regresses to whole-file grep, this test
# fails loudly.
i6c_primary=$(setup_fixture_repo)
i6c_out=$(cd "$i6c_primary" && bash "$INVARIANTS_SCRIPT" \
  --worktree "" --branch "" --landed-status "" --plan-slug "" \
  --plan-file "$i6_prose_plan" 2>&1); i6c_rc=$?
if [ "$i6c_rc" -eq 0 ] && [[ "$i6c_out" != *"INVARIANT-FAIL (#6):"* ]]; then
  pass "invariant #6 prose-regression: sentinel in prose only, no #6 failure"
else
  fail "invariant #6 prose-regression — rc=$i6c_rc (want 0); '#6' absent? out: $i6c_out"
fi

section "Invariant #7: main divergence WARN (3 cases)"
# Case A — no divergence: primary and bare origin on the same main commit.
# Expect rc=0 AND stderr does NOT contain 'INVARIANT-WARN (#7):'.
# setup_fixture_repo uses the git default branch (often 'master'); invariant
# #7 explicitly reads local 'main', so rename before the push.
i7a_primary=$(setup_fixture_repo)
git -C "$i7a_primary" branch -M main
i7a_origin=$(setup_bare_origin)
git -C "$i7a_primary" remote add origin "$i7a_origin"
git -C "$i7a_primary" push -q origin main
i7a_out=$(cd "$i7a_primary" && bash "$INVARIANTS_SCRIPT" \
  --worktree "" --branch "" --landed-status "" \
  --plan-slug "" --plan-file "" 2>&1); i7a_rc=$?
if [ "$i7a_rc" -eq 0 ] && [[ "$i7a_out" != *"INVARIANT-WARN (#7):"* ]]; then
  pass "invariant #7 Case A (no divergence): rc=0 and no #7 WARN"
else
  fail "invariant #7 Case A — rc=$i7a_rc (want 0); '#7' absent? out: $i7a_out"
fi

# Case B — fetch fails: origin URL points at a nonexistent path.
i7b_primary=$(setup_fixture_repo)
git -C "$i7b_primary" remote add origin "file:///nonexistent/canary-origin-b"
i7b_out=$(cd "$i7b_primary" && bash "$INVARIANTS_SCRIPT" \
  --worktree "" --branch "" --landed-status "" \
  --plan-slug "" --plan-file "" 2>&1); i7b_rc=$?
if [ "$i7b_rc" -eq 0 ] && [[ "$i7b_out" == *"INVARIANT-WARN (#7): 'git fetch origin main' failed"* ]]; then
  pass "invariant #7 Case B (fetch fails): rc=0 with fetch-fail WARN"
else
  fail "invariant #7 Case B — rc=$i7b_rc (want 0); fetch-fail WARN present? out: $i7b_out"
fi

# Case C — squash-merge divergence: local main has a commit origin/main
# lacks, but the trees are identical (different commit metadata only).
i7c_primary=$(setup_fixture_repo)
git -C "$i7c_primary" branch -M main
i7c_origin=$(setup_bare_origin)
git -C "$i7c_primary" remote add origin "$i7c_origin"
git -C "$i7c_primary" commit --allow-empty -q -m "B"
git -C "$i7c_primary" push -q origin main
I7C_TREE=$(git -C "$i7c_primary" rev-parse main^{tree})
I7C_PARENT=$(git -C "$i7c_primary" rev-parse main^)
I7C_BPRIME=$(git -C "$i7c_origin" commit-tree "$I7C_TREE" -p "$I7C_PARENT" -m "squash-like")
git -C "$i7c_origin" update-ref refs/heads/main "$I7C_BPRIME"
git -C "$i7c_primary" fetch -q origin main
i7c_out=$(cd "$i7c_primary" && bash "$INVARIANTS_SCRIPT" \
  --worktree "" --branch "" --landed-status "" \
  --plan-slug "" --plan-file "" 2>&1); i7c_rc=$?
I7C_WANT="INVARIANT-WARN (#7): local main has commits absent from origin/main but tree is identical (squash-merge divergence)"
if [ "$i7c_rc" -eq 0 ] && [[ "$i7c_out" == *"$I7C_WANT"* ]]; then
  pass "invariant #7 Case C (squash-merge divergence): rc=0 with tree-identical WARN"
else
  fail "invariant #7 Case C — rc=$i7c_rc (want 0); squash-divergence WARN present? out: $i7c_out"
fi

section "post-run-invariants.sh: #8 pr-state-unknown (3 cases)"
# Invariant #8 fires when a worktree's .landed recorded an UNKNOWN PR state
# (gh pr view rate-limited during land-phase). Contract string with Phase 1's
# writer: anchored '^status: pr-state-unknown$'. The guard
# [ -f "$WORKTREE_PATH/.landed" ] short-circuits when no marker exists.
#
# Isolation note: invariant #1 fires whenever WORKTREE_PATH points at an
# existing directory. #8's tests necessarily set WORKTREE_PATH to a dir
# that contains (or could contain) a .landed file, so #1 co-fires in
# Cases 1 & 2. We assert ONLY the #8 substring presence/absence — not
# overall rc — because #1 is out-of-scope for this section and has its
# own dedicated canary above.

# Case 1 — fire: .landed with status: pr-state-unknown → #8 in stderr, rc=1.
# #1 also fires (worktree dir exists); rc=1 either way, substring check is
# the load-bearing assertion.
i8a_primary=$(setup_fixture_repo)
i8a_worktree=$(mktemp -d /tmp/canary-phase2-inv8-1.XXXXXX)
FIXTURE_DIRS+=("$i8a_worktree")
printf 'status: pr-state-unknown\n' > "$i8a_worktree/.landed"
expect_script_exit \
  "invariant #8 fire: .landed has status: pr-state-unknown" \
  1 \
  "INVARIANT-FAIL (#8): $i8a_worktree/.landed has status: pr-state-unknown" \
  bash -c "cd \"$i8a_primary\" && bash \"$INVARIANTS_SCRIPT\" --worktree \"$i8a_worktree\" --branch \"\" --landed-status \"\" --plan-slug \"\" --plan-file \"\""

# Case 2 — silent on pr-ready: .landed present but status differs → no #8
# (assert absence of #8 substring regardless of overall rc; #1 fires and
# is expected to, being out-of-scope here).
i8b_primary=$(setup_fixture_repo)
i8b_worktree=$(mktemp -d /tmp/canary-phase2-inv8-2.XXXXXX)
FIXTURE_DIRS+=("$i8b_worktree")
printf 'status: pr-ready\n' > "$i8b_worktree/.landed"
i8b_out=$(cd "$i8b_primary" && bash "$INVARIANTS_SCRIPT" \
  --worktree "$i8b_worktree" --branch "" --landed-status pr-ready \
  --plan-slug "" --plan-file "" 2>&1) || true
if [[ "$i8b_out" != *"INVARIANT-FAIL (#8):"* ]]; then
  pass "invariant #8 negative: pr-ready .landed does not fire #8"
else
  fail "invariant #8 negative (pr-ready) — '#8' unexpectedly present in: $i8b_out"
fi

# Case 3 — silent on no .landed: guard [ -f ... ] short-circuits → no #8.
# Use mktemp -u so the worktree dir does NOT exist — then #1 also stays
# quiet and we can additionally assert rc=0 to prove the guard, not some
# unrelated fire, caused the silence.
i8c_primary=$(setup_fixture_repo)
i8c_worktree=$(mktemp -u /tmp/canary-phase2-inv8-3.XXXXXX)
# No FIXTURE_DIRS entry — nothing was created. No .landed either.
i8c_out=$(cd "$i8c_primary" && bash "$INVARIANTS_SCRIPT" \
  --worktree "$i8c_worktree" --branch "" --landed-status "" \
  --plan-slug "" --plan-file "" 2>&1); i8c_rc=$?
if [ "$i8c_rc" -eq 0 ] && [[ "$i8c_out" != *"INVARIANT-FAIL (#8):"* ]]; then
  pass "invariant #8 negative: no .landed, guard short-circuits, no #8"
else
  fail "invariant #8 negative (no .landed) — rc=$i8c_rc (want 0); '#8' absent? out: $i8c_out"
fi

# ---------------------------------------------------------------------------
# Phase 4 — block-agents.sh.template reproducers
# ---------------------------------------------------------------------------
# The hook reads $REPO_ROOT/.claude/zskills-config.json; each test overrides
# REPO_ROOT to a per-test fixture dir so it reads the fixture config rather
# than the live one. AGENTS_HOOK is set once (from the enclosing script's
# $REPO_ROOT) to keep the two REPO_ROOTs visually distinct.
AGENTS_HOOK="$REPO_ROOT/hooks/block-agents.sh.template"

expect_agent_deny_substring() {
  local label="$1" input_json="$2" want="$3" repo_root="$4"
  local result
  result=$(REPO_ROOT="$repo_root" bash "$AGENTS_HOOK" <<<"$input_json" 2>/dev/null) || true
  if [[ "$result" == *'"permissionDecision":"deny"'* && "$result" == *"$want"* ]]; then
    pass "$label"
  else
    fail "$label — want deny with '$want', got: $result"
  fi
}

expect_agent_allow() {
  local label="$1" input_json="$2" repo_root="$3"
  local result
  result=$(REPO_ROOT="$repo_root" bash "$AGENTS_HOOK" <<<"$input_json" 2>/dev/null) || true
  if [[ -z "$result" ]]; then
    pass "$label"
  else
    fail "$label — expected empty stdout, got: $result"
  fi
}

setup_agent_config() {
  # $1 = json string (config body); $2 = tmp repo_root
  local json="$1" root="$2"
  mkdir -p "$root/.claude"
  printf '%s' "$json" > "$root/.claude/zskills-config.json"
}

build_agent_input() {
  # $1 model, $2 transcript_path (may be empty string)
  MODEL="$1" TPATH="$2" python3 -c '
import json, os
d = {"tool_name": "Agent",
     "tool_input": {"subagent_type": "Explore", "model": os.environ["MODEL"]},
     "transcript_path": os.environ.get("TPATH", "")}
print(json.dumps(d))'
}

section "block-agents: family filter rejects synthetic (1 case)"
# Transcript contains Opus then <synthetic>; the hook filters to
# haiku/sonnet/opus only, so the effective floor resolves to Opus. A Sonnet
# dispatch must be denied.
a1_root=$(mktemp -d)
FIXTURE_DIRS+=("$a1_root")
setup_agent_config '{"agents":{"min_model":"auto"}}' "$a1_root"
a1_input=$(build_agent_input "claude-sonnet-4-6" "$FIXTURES/transcript-synthetic.jsonl")
expect_agent_deny_substring \
  "family filter: <synthetic> skipped, Opus floor enforced against Sonnet dispatch" \
  "$a1_input" \
  "agents.min_model requires claude-opus-4-6 or higher" \
  "$a1_root"

section "block-agents: ordinal comparison (6 cases)"
# Each case: fresh tmp REPO_ROOT with explicit min_model (not auto), no
# transcript needed. Matrix covers haiku/sonnet/opus × allow/deny.
for pair in \
  "claude-haiku-4-5|claude-haiku-4-5-20251001|allow|" \
  "claude-haiku-4-5|claude-sonnet-4-6|allow|" \
  "claude-sonnet-4-6|claude-haiku-4-5-20251001|deny|agents.min_model requires" \
  "claude-sonnet-4-6|claude-sonnet-4-6|allow|" \
  "claude-opus-4-6|claude-sonnet-4-6|deny|agents.min_model requires" \
  "claude-opus-4-6|claude-opus-4-6|allow|"; do
  IFS='|' read -r min_model dispatch expected want <<<"$pair"
  o_root=$(mktemp -d)
  FIXTURE_DIRS+=("$o_root")
  setup_agent_config "{\"agents\":{\"min_model\":\"$min_model\"}}" "$o_root"
  o_input=$(build_agent_input "$dispatch" "")
  if [ "$expected" = "allow" ]; then
    expect_agent_allow "ordinal: min=$min_model dispatch=$dispatch → allow" "$o_input" "$o_root"
  else
    expect_agent_deny_substring \
      "ordinal: min=$min_model dispatch=$dispatch → deny" \
      "$o_input" "$want" "$o_root"
  fi
done

section "block-agents: unknown family passes through (1 case)"
# claude-foo-99 has no haiku/sonnet/opus substring → ordinal=0 → always allow.
# Locks in the intentional "future-model escape valve".
a3_root=$(mktemp -d)
FIXTURE_DIRS+=("$a3_root")
setup_agent_config '{"agents":{"min_model":"claude-sonnet-4-6"}}' "$a3_root"
a3_input=$(build_agent_input "claude-foo-99" "")
expect_agent_allow \
  "unknown family: claude-foo-99 passes through (future-model escape valve)" \
  "$a3_input" \
  "$a3_root"

section "block-agents: auto fallback to Sonnet (1 case)"
# Locks in CURRENT behavior at hooks/block-agents.sh.template:68-69: when
# 'auto' resolution fails (no transcript), the hook falls back to a Sonnet
# floor. If the fallback is ever intentionally changed (e.g. fail-closed to
# Opus), this test MUST be updated in the same PR — treat as a design
# decision with its own review.
a4_root=$(mktemp -d)
FIXTURE_DIRS+=("$a4_root")
setup_agent_config '{"agents":{"min_model":"auto"}}' "$a4_root"
a4_input=$(build_agent_input "claude-haiku-4-5-20251001" "")
expect_agent_deny_substring \
  "auto fallback: no transcript → Sonnet floor denies Haiku dispatch" \
  "$a4_input" \
  "agents.min_model requires claude-sonnet-4-6 or higher" \
  "$a4_root"

section "block-agents: auto success path (2 cases)"
# Transcript has Opus — resolution succeeds to Opus floor.
a5_root=$(mktemp -d)
FIXTURE_DIRS+=("$a5_root")
setup_agent_config '{"agents":{"min_model":"auto"}}' "$a5_root"
a5a_input=$(build_agent_input "claude-opus-4-6" "$FIXTURES/transcript-opus.jsonl")
expect_agent_allow \
  "auto success: Opus transcript, Opus dispatch → allow" \
  "$a5a_input" \
  "$a5_root"

a5b_root=$(mktemp -d)
FIXTURE_DIRS+=("$a5b_root")
setup_agent_config '{"agents":{"min_model":"auto"}}' "$a5b_root"
a5b_input=$(build_agent_input "claude-sonnet-4-6" "$FIXTURES/transcript-opus.jsonl")
expect_agent_deny_substring \
  "auto success: Opus transcript, Sonnet dispatch → deny" \
  "$a5b_input" \
  "agents.min_model requires claude-opus-4-6 or higher" \
  "$a5b_root"

section "block-agents: min_model not configured (1 case)"
# Config file present but 'agents' object has no min_model key → pass-through
# per hooks/block-agents.sh.template:36-38.
a6_root=$(mktemp -d)
FIXTURE_DIRS+=("$a6_root")
setup_agent_config '{"agents":{}}' "$a6_root"
a6_input=$(build_agent_input "claude-haiku-4-5-20251001" "")
expect_agent_allow \
  "min_model unset: pass-through regardless of dispatch model" \
  "$a6_input" \
  "$a6_root"

# ---------------------------------------------------------------------------
# Phase 5 (UNIFY_TRACKING_NAMES) — Tracking marker naming (Option B subdir)
# ---------------------------------------------------------------------------
# Locks in the per-pipeline-subdir layout introduced by Phases 2-4:
# markers live in .zskills/tracking/$PIPELINE_ID/{fulfilled,requires,step}.*
# and the hook reads subdir-first with a flat-glob fallback. Each case
# below constructs a fixture tracking tree, pipes a synthesized commit
# JSON into the project hook, and asserts deny/allow accordingly.

PROJECT_HOOK_TMPL="$REPO_ROOT/hooks/block-unsafe-project.sh.template"

# Spin up a throwaway repo with the project hook installed + configured,
# a package.json with a test script, and a transcript containing the full
# test command so the test-gate check doesn't interfere with tracking
# enforcement. Echoes the repo root.
setup_tracking_fixture() {
  local tmp
  tmp=$(mktemp -d)
  FIXTURE_DIRS+=("$tmp")
  mkdir -p "$tmp/.claude/hooks" "$tmp/.zskills/tracking"
  cp "$PROJECT_HOOK_TMPL" "$tmp/.claude/hooks/block-unsafe-project.sh"
  sed -i 's|{{UNIT_TEST_CMD}}|npm test|g'           "$tmp/.claude/hooks/block-unsafe-project.sh"
  sed -i 's|{{FULL_TEST_CMD}}|npm run test:all|g'   "$tmp/.claude/hooks/block-unsafe-project.sh"
  sed -i 's|{{UI_FILE_PATTERNS}}|src/ui/|g'         "$tmp/.claude/hooks/block-unsafe-project.sh"
  printf '{"scripts":{"test":"vitest","test:all":"vitest run"}}\n' > "$tmp/package.json"
  printf 'npm run test:all\n' > "$tmp/.transcript"
  ( cd "$tmp" && git init -q && git config user.email c@t && git config user.name c \
      && git add -A && git commit -q -m init )
  echo "$tmp"
}

# Run the hook against a synthesized `git commit` input for the given repo
# root. Echoes the hook's stdout. Stages a .js file FIRST so the tracking
# enforcement code path (gated on CODE_FILES) actually fires.
run_tracking_hook() {
  local repo="$1"
  ( cd "$repo" && printf 'var x=1;\n' > app.js && git add app.js )
  local json="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m test\"},\"transcript_path\":\"$repo/.transcript\"}"
  echo "$json" | REPO_ROOT="$repo" TRACKING_ROOT="$repo" bash -c \
    "cd '$repo' && bash '$repo/.claude/hooks/block-unsafe-project.sh'" 2>/dev/null
}

# Assertion helpers for the tracking section: check deny/allow by the
# presence of `"permissionDecision":"deny"` in hook output.
assert_tracking_deny() {
  local label="$1" out="$2" want_substr="$3"
  if [[ "$out" == *'"permissionDecision":"deny"'* ]] && [[ "$out" == *"$want_substr"* ]]; then
    pass "$label"
  else
    fail "$label — want deny containing '$want_substr', got: $out"
  fi
}
assert_tracking_allow() {
  local label="$1" out="$2"
  if [[ "$out" != *'"permissionDecision":"deny"'* ]]; then
    pass "$label"
  else
    fail "$label — expected allow, got deny: $out"
  fi
}

section "Tracking marker naming (subdir scope) (8 cases)"

# Case 1 — Concurrent-same-slug isolation: two pipelines with the same
# TRACKING_ID (foo) under different orchestrator prefixes (run-plan.foo vs
# draft-plan.foo). Each writes fulfillment only in its own subdir; the
# other pipeline must NOT see it and must block.
tn1_repo=$(setup_tracking_fixture)
mkdir -p "$tn1_repo/.zskills/tracking/run-plan.foo"
mkdir -p "$tn1_repo/.zskills/tracking/draft-plan.foo"
# run-plan.foo has an unfulfilled requires; draft-plan.foo has its fulfillment.
touch "$tn1_repo/.zskills/tracking/run-plan.foo/requires.verify-changes.foo"
touch "$tn1_repo/.zskills/tracking/draft-plan.foo/requires.verify-changes.foo"
touch "$tn1_repo/.zskills/tracking/draft-plan.foo/fulfilled.verify-changes.foo"
printf 'run-plan.foo\n' > "$tn1_repo/.zskills-tracked"
tn1_out=$(run_tracking_hook "$tn1_repo")
assert_tracking_deny \
  "concurrent-same-slug: run-plan.foo cannot see draft-plan.foo fulfillment" \
  "$tn1_out" "verify-changes.foo"

# Case 2 — Glob-special chars sanitized by scripts/sanitize-pipeline-id.sh
# BEFORE they reach disk. Verify the sanitizer collapses *, ?, [, ], and
# spaces into '_' so writers never persist glob-special basenames.
tn2_raw='has space*?[abc]'
tn2_sanitized=$(bash "$REPO_ROOT/scripts/sanitize-pipeline-id.sh" "$tn2_raw")
# Expected: space→_, *→_, ?→_, [→_, a→a, b→b, c→c, ]→_
tn2_want='has_space___abc_'
if [ "$tn2_sanitized" = "$tn2_want" ]; then
  pass "sanitize-pipeline-id: glob-special chars + space → '_' (got '$tn2_sanitized')"
else
  fail "sanitize-pipeline-id: expected '$tn2_want', got '$tn2_sanitized'"
fi

# Case 3 — Dots in TRACKING_ID: PIPELINE_ID = "run-plan.a.b.c". The subdir
# is literally that flat basename, not a nested a/b/c tree. Hook finds
# markers under the single subdir and enforces correctly.
tn3_repo=$(setup_tracking_fixture)
mkdir -p "$tn3_repo/.zskills/tracking/run-plan.a.b.c"
# Confirm layout is flat (no nested dirs created by writer semantics).
if [ -d "$tn3_repo/.zskills/tracking/run-plan.a.b.c" ] \
   && [ ! -d "$tn3_repo/.zskills/tracking/run-plan.a" ] \
   && [ ! -d "$tn3_repo/.zskills/tracking/run-plan.a/b" ]; then
  pass "dots-in-tracking-id: subdir 'run-plan.a.b.c' is flat, no nested a/b/c"
else
  fail "dots-in-tracking-id: unexpected nested structure under run-plan.a.b.c"
fi
# And hook enforcement finds an unfulfilled requires under the dotted subdir.
touch "$tn3_repo/.zskills/tracking/run-plan.a.b.c/requires.verify-changes.a.b.c"
printf 'run-plan.a.b.c\n' > "$tn3_repo/.zskills-tracked"
tn3_out=$(run_tracking_hook "$tn3_repo")
assert_tracking_deny \
  "dots-in-tracking-id: hook finds marker under flat dotted subdir" \
  "$tn3_out" "verify-changes.a.b.c"

# Case 4 — Empty PIPELINE_ID: session has no .zskills-tracked AND no
# ZSKILLS_PIPELINE_ID in transcript. The hook's pipeline-association guard
# skips enforcement entirely (TRACKING_SESSION_HAS_PIPELINE=false). Even
# with unfulfilled markers in a subdir, commit is allowed.
tn4_repo=$(setup_tracking_fixture)
mkdir -p "$tn4_repo/.zskills/tracking/run-plan.orphan"
touch "$tn4_repo/.zskills/tracking/run-plan.orphan/requires.verify-changes.orphan"
# Transcript has test command but NO ZSKILLS_PIPELINE_ID line.
printf 'npm run test:all\n' > "$tn4_repo/.transcript"
# No .zskills-tracked either.
tn4_out=$(run_tracking_hook "$tn4_repo")
assert_tracking_allow \
  "empty-PIPELINE_ID: no .zskills-tracked + no transcript id → enforcement skipped" \
  "$tn4_out"

# Case 5 — Missing subdir: PIPELINE_ID set but the subdir doesn't exist
# (fresh pipeline, no markers written yet). The `[ -d $PIPELINE_SUBDIR ]`
# guard skips the subdir loop. No flat markers either → allow.
tn5_repo=$(setup_tracking_fixture)
printf 'run-plan.nosubdir\n' > "$tn5_repo/.zskills-tracked"
# Intentionally do NOT mkdir .zskills/tracking/run-plan.nosubdir/
tn5_out=$(run_tracking_hook "$tn5_repo")
assert_tracking_allow \
  "missing-subdir: no subdir, no flat markers → allow (no error)" \
  "$tn5_out"

# Case 6 — Glob no-match inside empty subdir: subdir exists but contains
# no markers. The inner `for req in …/requires.*; do [ -e "$req" ] ||
# continue` handles the unexpanded literal pattern safely.
tn6_repo=$(setup_tracking_fixture)
mkdir -p "$tn6_repo/.zskills/tracking/run-plan.empty"
printf 'run-plan.empty\n' > "$tn6_repo/.zskills-tracked"
tn6_out=$(run_tracking_hook "$tn6_repo")
assert_tracking_allow \
  "glob-no-match: empty subdir, glob unexpanded, [ -e ] continues, hook allows" \
  "$tn6_out"

# Case 7 — fix-issues sprint isolation: two sprints with distinct SPRINT_IDs
# each get their own subdir. Sprint A has an unfulfilled requires; Sprint B
# is the active pipeline. B must NOT see A's unfulfilled marker.
tn7_repo=$(setup_tracking_fixture)
mkdir -p "$tn7_repo/.zskills/tracking/fix-issues.sprint-20260417-120000-issuea"
mkdir -p "$tn7_repo/.zskills/tracking/fix-issues.sprint-20260417-130000-issueb"
touch "$tn7_repo/.zskills/tracking/fix-issues.sprint-20260417-120000-issuea/requires.run-plan.123"
printf 'fix-issues.sprint-20260417-130000-issueb\n' > "$tn7_repo/.zskills-tracked"
tn7_out=$(run_tracking_hook "$tn7_repo")
assert_tracking_allow \
  "fix-issues sprint isolation: sprint B not blocked by sprint A's unfulfilled requires" \
  "$tn7_out"

# Case 8 — Metadata meta.* prefix is NOT enforced: a meta.run-plan.1 file
# in research-and-go's subdir is ignored by the hook's enforcement globs
# (requires.*, step.*.implement, step.*.verify, fulfilled.*). Orchestrator
# subdir with meta.* entries never blocks.
tn8_repo=$(setup_tracking_fixture)
mkdir -p "$tn8_repo/.zskills/tracking/research-and-go.cooling"
touch "$tn8_repo/.zskills/tracking/research-and-go.cooling/meta.run-plan.1"
touch "$tn8_repo/.zskills/tracking/research-and-go.cooling/meta.draft-plan.1"
printf 'research-and-go.cooling\n' > "$tn8_repo/.zskills-tracked"
tn8_out=$(run_tracking_hook "$tn8_repo")
assert_tracking_allow \
  "meta.* prefix: metadata files do not match requires.* glob, no enforcement fires" \
  "$tn8_out"

# --- Phase 5: /commit reviewer prompt + Phase 7 anti-stash discipline ---

expect_grep_F_hit() {
  # $1 label, $2 file, $3 literal string
  local label="$1" file="$2" want="$3"
  if grep -qF -- "$want" "$file"; then
    pass "$label"
  else
    fail "$label — not found in $file"
  fi
}
expect_grep_count_at_least() {
  # $1 label, $2 file, $3 literal string, $4 min count
  local label="$1" file="$2" want="$3" min="$4"
  local n
  n=$(grep -cF -- "$want" "$file")
  if [ "$n" -ge "$min" ]; then
    pass "$label (count: $n >= $min)"
  else
    fail "$label (count: $n < $min) in $file"
  fi
}

section "/commit reviewer prompt: load-bearing substrings (canonical)"
COMMIT_SKILL="$REPO_ROOT/skills/commit/SKILL.md"
expect_grep_F_hit "canonical: 'You are read-only.'"              "$COMMIT_SKILL" 'You are read-only.'
expect_grep_F_hit "canonical: 'FORBIDDEN:'"                      "$COMMIT_SKILL" 'FORBIDDEN:'
expect_grep_F_hit "canonical: backticked git-stash reference"    "$COMMIT_SKILL" '`git stash`'
expect_grep_F_hit "canonical: 'push/-u/save/bare'"               "$COMMIT_SKILL" 'push/-u/save/bare'
expect_grep_F_hit "canonical: 'checkout'"                        "$COMMIT_SKILL" 'checkout'
expect_grep_F_hit "canonical: 'restore'"                         "$COMMIT_SKILL" 'restore'
expect_grep_F_hit "canonical: 'reset'"                           "$COMMIT_SKILL" 'reset'
expect_grep_F_hit "canonical: 'editing files'"                   "$COMMIT_SKILL" 'editing files'
expect_grep_F_hit "canonical: 'creating worktrees'"              "$COMMIT_SKILL" 'creating worktrees'
expect_grep_F_hit "canonical: 'git show <commit>:<file>' ref"    "$COMMIT_SKILL" '`git show <commit>:<file>`'
expect_grep_F_hit "canonical: 'Past failure: reviewer ran'"      "$COMMIT_SKILL" 'Past failure: reviewer ran'

section "/commit reviewer prompt: load-bearing substrings (installed copy)"
COMMIT_SKILL_INSTALLED="$REPO_ROOT/.claude/skills/commit/SKILL.md"
if [ ! -f "$COMMIT_SKILL_INSTALLED" ]; then
  pass "installed copy: SKIPPED (run update-zskills to enable)"
else
  expect_grep_F_hit "installed: 'You are read-only.'"              "$COMMIT_SKILL_INSTALLED" 'You are read-only.'
  expect_grep_F_hit "installed: 'FORBIDDEN:'"                      "$COMMIT_SKILL_INSTALLED" 'FORBIDDEN:'
  expect_grep_F_hit "installed: backticked git-stash reference"    "$COMMIT_SKILL_INSTALLED" '`git stash`'
  expect_grep_F_hit "installed: 'push/-u/save/bare'"               "$COMMIT_SKILL_INSTALLED" 'push/-u/save/bare'
  expect_grep_F_hit "installed: 'checkout'"                        "$COMMIT_SKILL_INSTALLED" 'checkout'
  expect_grep_F_hit "installed: 'restore'"                         "$COMMIT_SKILL_INSTALLED" 'restore'
  expect_grep_F_hit "installed: 'reset'"                           "$COMMIT_SKILL_INSTALLED" 'reset'
  expect_grep_F_hit "installed: 'editing files'"                   "$COMMIT_SKILL_INSTALLED" 'editing files'
  expect_grep_F_hit "installed: 'creating worktrees'"              "$COMMIT_SKILL_INSTALLED" 'creating worktrees'
  expect_grep_F_hit "installed: 'git show <commit>:<file>' ref"    "$COMMIT_SKILL_INSTALLED" '`git show <commit>:<file>`'
  expect_grep_F_hit "installed: 'Past failure: reviewer ran'"      "$COMMIT_SKILL_INSTALLED" 'Past failure: reviewer ran'
fi

section "/commit Phase 7: anti-stash discipline (2 cases)"
expect_grep_F_hit "phase-7: 'Do NOT stash' present"              "$COMMIT_SKILL" 'Do NOT stash'
expect_grep_F_hit "phase-7: 'try-without-stash' present"         "$COMMIT_SKILL" 'try-without-stash'

section "/commit Key Rules: stash prohibition (2 cases)"
expect_grep_count_at_least "key-rules: 'Do NOT stash' appears >= 2" "$COMMIT_SKILL" 'Do NOT stash' 2
expect_grep_count_at_least "key-rules: 'hook blocks' appears >= 1"  "$COMMIT_SKILL" 'hook blocks'  1

echo
echo "Canary failure-injection: $PASS_COUNT passed, $FAIL_COUNT failed"
exit $((FAIL_COUNT > 0))
