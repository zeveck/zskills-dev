#!/bin/bash
# Tests for the post-create-worktree.sh consumer stub callout wired
# into skills/create-worktree/scripts/create-worktree.sh.
#
# Run from repo root: bash tests/test-post-create-worktree.sh
#
# 3 cases (per CONSUMER_STUB_CALLOUTS_PLAN.md WI 3.4):
#   1. stub-absent          -> create-worktree exits 0, no stub-notes marker
#   2. stub-present-success -> stub touches $WT_PATH/POST_RAN, exit 0
#   3. stub-present-fail    -> stub `exit 7`s, create-worktree exits 9,
#                              worktree dir still exists, stderr names rc 7
#
# Each case runs in an isolated /tmp fixture (FIX_NN-style) so the
# real repo's worktree state is untouched. The fixture installs the
# stub-lib at <fixture>/.claude/skills/update-zskills/scripts/
# zskills-stub-lib.sh; create-worktree resolves it via the
# ${CLAUDE_PROJECT_DIR:-$MAIN_ROOT} fallback (CLAUDE_PROJECT_DIR is
# unset for each invocation so MAIN_ROOT-fallback is exercised).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Prefer the worktree copy of the script (in-flight edits) over the
# main-repo mirror.
SCRIPT="$REPO_ROOT/skills/create-worktree/scripts/create-worktree.sh"
if [ ! -x "$SCRIPT" ]; then
  echo "FATAL: $SCRIPT missing or not executable" >&2
  exit 2
fi

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  printf '\033[32m  PASS\033[0m %s\n' "$1"
  PASS_COUNT=$((PASS_COUNT + 1))
}
fail() {
  printf '\033[31m  FAIL\033[0m %s\n' "$1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

# ────────────────────────────────────────────────────────────────────
# make_fixture <case-num>
#   Creates an isolated git repo under /tmp with all helper scripts
#   copied into <fix>/scripts/ and the stub-lib installed at
#   <fix>/.claude/skills/update-zskills/scripts/zskills-stub-lib.sh.
#   Echoes the fixture path on stdout.
# ────────────────────────────────────────────────────────────────────
make_fixture() {
  local n=$1
  local fix="/tmp/pcw-fixture-$n-$$"
  rm -rf "$fix"
  mkdir -p "$fix/scripts"
  mkdir -p "$fix/.claude/skills/update-zskills/scripts"

  git init --quiet -b main "$fix"
  git -C "$fix" config user.email "t@t"
  git -C "$fix" config user.name "t"

  cp "$REPO_ROOT/skills/create-worktree/scripts/sanitize-pipeline-id.sh" "$fix/scripts/"
  cp "$REPO_ROOT/skills/create-worktree/scripts/worktree-add-safe.sh" "$fix/scripts/"
  chmod +x "$fix/scripts/sanitize-pipeline-id.sh" "$fix/scripts/worktree-add-safe.sh"

  cp "$REPO_ROOT/skills/update-zskills/scripts/zskills-stub-lib.sh" \
     "$fix/.claude/skills/update-zskills/scripts/zskills-stub-lib.sh"

  echo "init" > "$fix/README.md"
  git -C "$fix" add README.md
  git -C "$fix" commit --quiet -m "init"

  printf '%s' "$fix"
}

cleanup_fixture() {
  local fix=$1
  local wt=$2
  if [ -n "$wt" ] && [ -d "$wt" ]; then
    git -C "$fix" worktree remove --force "$wt" 2>/dev/null || true
  fi
  rm -rf "$fix" "$wt"
}

# ────────────────────────────────────────────────────────────────────
# Case 1 — stub-absent: create-worktree succeeds, lib runs but finds
# no consumer stub at <fix>/scripts/post-create-worktree.sh; no
# stub-notes marker is written.
# ────────────────────────────────────────────────────────────────────
FIX_1=$(make_fixture 1)
SLUG_1="pcw1"
EXPECTED_WT_1="/tmp/$(basename "$FIX_1")-$SLUG_1"
ERR_1=$(mktemp)
STDOUT_1=$(cd "$FIX_1" && env -u CLAUDE_PROJECT_DIR \
  bash "$SCRIPT" --pipeline-id "test.pcw1.$$" --no-preflight "$SLUG_1" 2>"$ERR_1")
RC_1=$?

NOTE_MARKER_1="$FIX_1/.zskills/stub-notes/post-create-worktree.sh.noted"
if [ "$RC_1" -eq 0 ] \
   && [ "$STDOUT_1" = "$EXPECTED_WT_1" ] \
   && [ -d "$STDOUT_1" ] \
   && [ ! -e "$NOTE_MARKER_1" ]; then
  pass "1  stub-absent: create-worktree rc=0, no stub-notes marker"
else
  fail "1  stub-absent: rc=$RC_1 stdout='$STDOUT_1' expected='$EXPECTED_WT_1' marker-exists=$([ -e "$NOTE_MARKER_1" ] && echo y || echo n)"
  echo "  --- stderr ---"; cat "$ERR_1"
fi
rm -f -- "$ERR_1"
cleanup_fixture "$FIX_1" "$EXPECTED_WT_1"

# ────────────────────────────────────────────────────────────────────
# Case 2 — stub-present-success: install a stub that touches
# $WT_PATH/POST_RAN. create-worktree exits 0; POST_RAN exists; stub
# received the expected positional args.
# ────────────────────────────────────────────────────────────────────
FIX_2=$(make_fixture 2)
cat > "$FIX_2/scripts/post-create-worktree.sh" <<'STUB'
#!/bin/bash
# Args: WT_PATH BRANCH SLUG PREFIX PIPELINE_ID MAIN_ROOT
WT_PATH=$1
BRANCH=$2
SLUG=$3
# Touch the marker file inside the worktree to prove we ran AND
# received WT_PATH correctly.
touch "$WT_PATH/POST_RAN"
# Sanity: SLUG should be non-empty and match the path tail.
[ -n "$SLUG" ] || exit 50
[ -n "$BRANCH" ] || exit 51
exit 0
STUB
chmod +x "$FIX_2/scripts/post-create-worktree.sh"

SLUG_2="pcw2"
EXPECTED_WT_2="/tmp/$(basename "$FIX_2")-$SLUG_2"
ERR_2=$(mktemp)
STDOUT_2=$(cd "$FIX_2" && env -u CLAUDE_PROJECT_DIR \
  bash "$SCRIPT" --pipeline-id "test.pcw2.$$" --no-preflight "$SLUG_2" 2>"$ERR_2")
RC_2=$?

if [ "$RC_2" -eq 0 ] \
   && [ "$STDOUT_2" = "$EXPECTED_WT_2" ] \
   && [ -f "$EXPECTED_WT_2/POST_RAN" ]; then
  pass "2  stub-present-success: rc=0, stub ran, POST_RAN exists"
else
  fail "2  stub-present-success: rc=$RC_2 stdout='$STDOUT_2' POST_RAN-exists=$([ -f "$EXPECTED_WT_2/POST_RAN" ] && echo y || echo n)"
  echo "  --- stderr ---"; cat "$ERR_2"
fi
rm -f -- "$ERR_2"
cleanup_fixture "$FIX_2" "$EXPECTED_WT_2"

# ────────────────────────────────────────────────────────────────────
# Case 3 — stub-present-fail: stub exits 7. create-worktree exits 9
# (the propagation rc), worktree directory STILL exists (left for
# inspection per the no-rollback policy), stderr matches
# `post-create-worktree.sh exited 7`.
# ────────────────────────────────────────────────────────────────────
FIX_3=$(make_fixture 3)
cat > "$FIX_3/scripts/post-create-worktree.sh" <<'STUB'
#!/bin/bash
echo "stub-failing-deliberately" >&2
exit 7
STUB
chmod +x "$FIX_3/scripts/post-create-worktree.sh"

SLUG_3="pcw3"
EXPECTED_WT_3="/tmp/$(basename "$FIX_3")-$SLUG_3"
ERR_3=$(mktemp)
STDOUT_3=$(cd "$FIX_3" && env -u CLAUDE_PROJECT_DIR \
  bash "$SCRIPT" --pipeline-id "test.pcw3.$$" --no-preflight "$SLUG_3" 2>"$ERR_3")
RC_3=$?

STDERR_3=$(cat "$ERR_3")
if [ "$RC_3" -eq 9 ] \
   && [ -d "$EXPECTED_WT_3" ] \
   && echo "$STDERR_3" | grep -q "post-create-worktree.sh exited 7"; then
  pass "3  stub-present-fail: rc=9, worktree preserved, stderr names rc 7"
else
  fail "3  stub-present-fail: rc=$RC_3 wt-exists=$([ -d "$EXPECTED_WT_3" ] && echo y || echo n) stderr-match=$(echo "$STDERR_3" | grep -q 'post-create-worktree.sh exited 7' && echo y || echo n)"
  echo "  --- stderr ---"; echo "$STDERR_3"
fi
rm -f -- "$ERR_3"
cleanup_fixture "$FIX_3" "$EXPECTED_WT_3"

echo ""
echo "---"
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (of %d)\033[0m\n' "$PASS_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (of %d)\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit 1
fi
