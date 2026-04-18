#!/bin/bash
# End-to-end smoke: two concurrent pipelines writing tracking markers in
# disjoint per-pipeline subdirs, exercising the REAL hook to confirm
# enforcement after Phase 6's dual-read removal.
#
# This is NOT a unit test. It spins up two real git repos in /tmp/, writes
# real .zskills/tracking/$PIPELINE_ID/ subdirs concurrently (via `&` + wait),
# then invokes the rendered hook against each to confirm:
#
#   1. Markers written by pipeline A appear ONLY under repo-A's
#      $PIPELINE_ID_A subdir. No leakage into repo B, no leakage into a
#      flat path.
#   2. Pipeline A's unfulfilled markers do NOT block pipeline B (different
#      PIPELINE_ID, different subdir).
#   3. The hook reads ONLY the subdir — flat markers are IGNORED (the
#      subdir-only reader landed in Phase 6 after all writers migrated).
#
# Expected runtime: <30s. Invoked optionally from tests/run-all.sh when
# the RUN_E2E env var is set (it is skipped in the default suite to keep
# the unit-level feedback loop fast).
#
# Run manually:
#   RUN_E2E=1 bash tests/e2e-parallel-pipelines.sh
# or directly:
#   bash tests/e2e-parallel-pipelines.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZSKILLS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_TEMPLATE="$ZSKILLS_ROOT/hooks/block-unsafe-project.sh.template"

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

# ─── tempdir setup / cleanup ────────────────────────────────────────────
# Use one parent tempdir holding both repos so cleanup is a single
# `find -delete` + `rmdir`. rm -rf is blocked by block-unsafe-generic.sh,
# and we don't want to special-case this script.
TMPDIR=$(mktemp -d -t zskills-e2e-parallel-XXXXXX)

cleanup() {
  if [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ]; then
    # Any worktrees created inside these repos must be removed first so
    # git doesn't complain. We don't create worktrees here, but guard
    # anyway for future extension.
    for repo in "$TMPDIR"/repo-*; do
      [ -d "$repo" ] || continue
      (cd "$repo" 2>/dev/null && git worktree list --porcelain 2>/dev/null \
        | grep '^worktree ' | sed 's/^worktree //' \
        | while read -r wt; do
            [ "$wt" = "$repo" ] && continue
            git worktree remove --force "$wt" 2>/dev/null
          done)
    done
    # Delete file tree depth-first without rm -rf. find -delete walks
    # bottom-up so parents come out after children.
    find "$TMPDIR" -mindepth 1 -delete 2>/dev/null
    rmdir "$TMPDIR" 2>/dev/null
  fi
}
trap cleanup EXIT INT TERM

echo "=== E2E smoke: parallel pipelines under subdir-only reader ==="
echo "Tempdir: $TMPDIR"
echo "Hook template: $HOOK_TEMPLATE"
echo ""

# ─── render hook once, reuse in both repos ──────────────────────────────
RENDERED_HOOK="$TMPDIR/block-unsafe-project.sh"
cp "$HOOK_TEMPLATE" "$RENDERED_HOOK"
sed -i 's|{{UNIT_TEST_CMD}}|npm test|g' "$RENDERED_HOOK"
sed -i 's|{{FULL_TEST_CMD}}|npm run test:all|g' "$RENDERED_HOOK"
sed -i 's|{{UI_FILE_PATTERNS}}|src/ui/|g' "$RENDERED_HOOK"

# ─── bootstrap one git repo with the rendered hook + a transcript ──────
bootstrap_repo() {
  local repo="$1"
  mkdir -p "$repo"
  (
    cd "$repo"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    echo '{"scripts":{"test":"vitest","test:all":"vitest run"}}' > package.json
    git add package.json
    git commit -q -m "init"
  )
  mkdir -p "$repo/.claude/hooks"
  cp "$RENDERED_HOOK" "$repo/.claude/hooks/block-unsafe-project.sh"
  mkdir -p "$repo/.zskills/tracking"
  printf 'npm run test:all\n' > "$repo/.transcript"
}

# ─── invoke the hook to simulate a Claude Code PreToolUse commit check ─
# Returns 0 if allowed, 1 if denied. HOOK_OUTPUT holds the raw output.
HOOK_OUTPUT=""
try_commit() {
  local repo="$1"
  local transcript="$repo/.transcript"
  local json="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m test\"},\"transcript_path\":\"$transcript\"}"
  HOOK_OUTPUT=$(echo "$json" \
    | REPO_ROOT="$repo" TRACKING_ROOT="$repo" \
      bash -c "cd '$repo' && bash '$repo/.claude/hooks/block-unsafe-project.sh'" 2>/dev/null)
  if [[ "$HOOK_OUTPUT" == *"permissionDecision"*"deny"* ]]; then
    return 1
  fi
  return 0
}

# ─── phase 1: bootstrap both repos in parallel ──────────────────────────
REPO_A="$TMPDIR/repo-A"
REPO_B="$TMPDIR/repo-B"
PID_A="run-plan.smoke-alpha"
PID_B="fix-issues.smoke-beta"

bootstrap_repo "$REPO_A" &
bootstrap_repo "$REPO_B" &
wait

if [ ! -d "$REPO_A/.git" ] || [ ! -d "$REPO_B/.git" ]; then
  fail "bootstrap: both repos should have .git dirs"
  exit 1
fi
pass "bootstrap: two independent git repos created in parallel"

# ─── phase 2: write per-pipeline markers concurrently ───────────────────
# Simulates /run-plan in repo A and /fix-issues-like workflow in repo B
# both persisting tracking state at the same time. If the subdir scheme
# is correct, no marker from A ever touches B's paths (or vice-versa),
# and neither writes into the flat .zskills/tracking/ root.

write_pipeline_A_markers() {
  local dir="$REPO_A/.zskills/tracking/$PID_A"
  mkdir -p "$dir"
  touch "$dir/requires.verify-changes.smoke-alpha"
  touch "$dir/step.run-plan.smoke-alpha.implement"
  touch "$dir/step.run-plan.smoke-alpha.verify"
  touch "$dir/step.run-plan.smoke-alpha.report"
  printf '%s\n' "$PID_A" > "$REPO_A/.zskills-tracked"
}

write_pipeline_B_markers() {
  local dir="$REPO_B/.zskills/tracking/$PID_B"
  mkdir -p "$dir"
  touch "$dir/requires.verify-changes.smoke-beta"
  touch "$dir/step.fix-issues.smoke-beta.implement"
  touch "$dir/step.fix-issues.smoke-beta.verify"
  touch "$dir/step.fix-issues.smoke-beta.report"
  printf '%s\n' "$PID_B" > "$REPO_B/.zskills-tracked"
}

write_pipeline_A_markers &
write_pipeline_B_markers &
wait

# ─── phase 3: assert marker isolation ───────────────────────────────────
# A's markers must ONLY appear under repo-A/.zskills/tracking/$PID_A/ and
# nowhere else. Same for B.

a_markers_in_a=$(find "$REPO_A/.zskills/tracking/$PID_A" -mindepth 1 -maxdepth 1 -type f | wc -l)
a_markers_in_flat=$(find "$REPO_A/.zskills/tracking" -mindepth 1 -maxdepth 1 -type f | wc -l)
b_markers_in_b=$(find "$REPO_B/.zskills/tracking/$PID_B" -mindepth 1 -maxdepth 1 -type f | wc -l)
b_markers_in_flat=$(find "$REPO_B/.zskills/tracking" -mindepth 1 -maxdepth 1 -type f | wc -l)
cross_a_in_b=$(find "$REPO_B" -path "*/tracking/*smoke-alpha*" 2>/dev/null | wc -l)
cross_b_in_a=$(find "$REPO_A" -path "*/tracking/*smoke-beta*" 2>/dev/null | wc -l)

if [ "$a_markers_in_a" -eq 4 ]; then
  pass "isolation: all 4 pipeline-A markers land in repo-A's $PID_A subdir"
else
  fail "isolation: expected 4 markers in repo-A/$PID_A, got $a_markers_in_a"
fi

if [ "$b_markers_in_b" -eq 4 ]; then
  pass "isolation: all 4 pipeline-B markers land in repo-B's $PID_B subdir"
else
  fail "isolation: expected 4 markers in repo-B/$PID_B, got $b_markers_in_b"
fi

if [ "$a_markers_in_flat" -eq 0 ]; then
  pass "isolation: zero markers leaked into repo-A's flat tracking dir"
else
  fail "isolation: $a_markers_in_flat markers leaked to flat path in repo-A"
fi

if [ "$b_markers_in_flat" -eq 0 ]; then
  pass "isolation: zero markers leaked into repo-B's flat tracking dir"
else
  fail "isolation: $b_markers_in_flat markers leaked to flat path in repo-B"
fi

if [ "$cross_a_in_b" -eq 0 ] && [ "$cross_b_in_a" -eq 0 ]; then
  pass "isolation: no cross-pollination between repo-A and repo-B"
else
  fail "isolation: found cross-pollinated files ($cross_a_in_b A-in-B, $cross_b_in_a B-in-A)"
fi

# ─── phase 4: hook enforcement — requires blocks, fulfilled unblocks ──
# Pipeline A has an unfulfilled requires.* + an implement without verify's
# sibling removed. Stage a code file and commit — hook must deny.

(cd "$REPO_A" && echo "var a = 1;" > app.js && git add app.js)
if try_commit "$REPO_A"; then
  fail "enforcement (repo-A): unfulfilled requires + steps should BLOCK commit"
else
  if [[ "$HOOK_OUTPUT" == *"smoke-alpha"* ]]; then
    pass "enforcement (repo-A): commit blocked, message references pipeline-A marker"
  else
    pass "enforcement (repo-A): commit blocked (generic denial)"
  fi
fi

# Fulfill pipeline A. Step chain already complete (implement+verify+report).
touch "$REPO_A/.zskills/tracking/$PID_A/fulfilled.verify-changes.smoke-alpha"

if try_commit "$REPO_A"; then
  pass "enforcement (repo-A): commit allowed after fulfilled marker written in same subdir"
else
  fail "enforcement (repo-A): should allow after fulfillment, got: $HOOK_OUTPUT"
fi

# ─── phase 5: hook enforcement — cross-pipeline non-interference ───────
# Repo B has its own unfulfilled requires in its own subdir. Repo A's
# fulfilled markers in A's repo must NOT satisfy B's requires.

(cd "$REPO_B" && echo "var b = 2;" > app.js && git add app.js)
if try_commit "$REPO_B"; then
  fail "enforcement (repo-B): unfulfilled requires should BLOCK commit"
else
  if [[ "$HOOK_OUTPUT" == *"smoke-beta"* ]]; then
    pass "enforcement (repo-B): commit blocked, message references pipeline-B marker"
  else
    pass "enforcement (repo-B): commit blocked (generic denial)"
  fi
fi

# Fulfill pipeline B. Hook must now allow.
touch "$REPO_B/.zskills/tracking/$PID_B/fulfilled.verify-changes.smoke-beta"
if try_commit "$REPO_B"; then
  pass "enforcement (repo-B): commit allowed after fulfilled marker written in same subdir"
else
  fail "enforcement (repo-B): should allow after fulfillment, got: $HOOK_OUTPUT"
fi

# ─── phase 6: legacy flat marker must be IGNORED by the new reader ─────
# Write a flat-path marker (pre-unify style) in repo-A. With dual-read
# removed, the hook must NOT pick it up. A commit with a fresh PIPELINE_ID
# whose subdir is empty must be ALLOWED even though a flat requires.*
# exists from an older scheme.

FLAT_REPO="$TMPDIR/repo-flat"
bootstrap_repo "$FLAT_REPO"
PID_FLAT="run-plan.legacy-holdout"
printf '%s\n' "$PID_FLAT" > "$FLAT_REPO/.zskills-tracked"
# Legacy flat marker — intentionally NOT inside a $PID_FLAT subdir.
touch "$FLAT_REPO/.zskills/tracking/requires.verify-changes.legacy-holdout"
# No subdir created for $PID_FLAT → subdir-only reader finds nothing.

(cd "$FLAT_REPO" && echo "var c = 3;" > app.js && git add app.js)
if try_commit "$FLAT_REPO"; then
  pass "dual-read removed: flat-path legacy marker is ignored (commit allowed)"
else
  fail "dual-read removed: legacy flat marker still blocks commit — hook fallback not removed? got: $HOOK_OUTPUT"
fi

# ─── summary ────────────────────────────────────────────────────────────
echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' \
  "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
