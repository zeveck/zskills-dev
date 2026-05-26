#!/bin/bash
# tests/test-plan-claim-main-root-anchor.sh — Phase 1 W1.10.
#
# Asserts the DA7 / D5 invariant: claim writes anchor to MAIN_ROOT
# (resolved via `git rev-parse --git-common-dir` parent), NOT $PWD. This
# is the structural defense that makes /run-plan PR-mode dispatches safe:
# acquire called from a worktree CWD must still land the claim file in
# main's .zskills/claims/.
#
# Procedure:
#   1. Init a main repo at $MAIN.
#   2. Create a worktree (via `git worktree add`) at $WT for a feature branch.
#   3. Invoke `claim-plan.sh acquire foo` with cwd = $WT.
#   4. Assert claim.json appears at $MAIN/.zskills/claims/plan-foo/,
#      NOT at $WT/.zskills/claims/plan-foo/.
#   5. release from inside $WT — assert it removes the claim from $MAIN.
#
# This tests the symmetric invariant for release as well via the explicit
# `git rev-parse --git-common-dir parent` lookup.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAIM_SH="$REPO_ROOT/skills/run-plan/scripts/claim-plan.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SCRATCH_ROOT="/tmp/test-plan-claim-main-root-anchor-$$"
cleanup() {
  if [ -n "${TEST_KEEP_SCRATCH:-}" ]; then
    echo "TEST_KEEP_SCRATCH set — leaving $SCRATCH_ROOT" >&2
    return
  fi
  if [ -d "$SCRATCH_ROOT" ]; then
    # Worktree dirs need careful removal — git track them. Try git
    # worktree remove first; otherwise force-delete.
    if [ -d "$SCRATCH_ROOT/main" ]; then
      (cd "$SCRATCH_ROOT/main" && git worktree remove --force "$SCRATCH_ROOT/wt" >/dev/null 2>&1 || true)
    fi
    find "$SCRATCH_ROOT" -mindepth 1 -delete 2>/dev/null || true
    rmdir "$SCRATCH_ROOT" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM
mkdir -p "$SCRATCH_ROOT"

if [ ! -f "$CLAIM_SH" ]; then
  echo "FATAL: $CLAIM_SH missing" >&2; exit 1
fi

# claim-plan.sh's _locate_sanitizer falls back to CLAUDE_PROJECT_DIR for
# the sanitize-pipeline-id.sh lookup. Point it at REPO_ROOT.
export CLAUDE_PROJECT_DIR="$REPO_ROOT"

echo "=== claim-plan.sh MAIN_ROOT anchor invariant (DA7) ==="

MAIN="$SCRATCH_ROOT/main"
WT="$SCRATCH_ROOT/wt"

mkdir -p "$MAIN"
(cd "$MAIN" && git init -q && git config user.email "t@t" && git config user.name "t" \
  && git commit --allow-empty -q -m "init" \
  && git checkout -q -b mainbr 2>/dev/null || true) \
  || { echo "FATAL main init failed" >&2; exit 1; }

# Create a worktree off main.
(cd "$MAIN" && git worktree add -q -b feature-anchor-test "$WT") \
  || { echo "FATAL git worktree add failed" >&2; exit 1; }

# ───────────────────────────────────────────────────────────────────────
# Acquire from inside the worktree CWD.
# ───────────────────────────────────────────────────────────────────────
(
  cd "$WT"
  bash "$CLAIM_SH" acquire foo --pipeline-id "run-plan.foo"
)
rc=$?

if [ "$rc" -ne 0 ]; then
  fail "acquire from worktree" "rc=$rc"
else
  if [ -f "$MAIN/.zskills/claims/plan-foo/claim.json" ]; then
    pass "acquire from worktree writes claim.json under MAIN's .zskills/claims/ (DA7 invariant)"
  else
    fail "acquire MAIN anchor" "claim.json NOT at $MAIN/.zskills/claims/plan-foo/claim.json"
  fi
  if [ -f "$WT/.zskills/claims/plan-foo/claim.json" ]; then
    fail "acquire worktree-leak" "claim.json INCORRECTLY landed at worktree path $WT/.zskills/claims/plan-foo/claim.json"
  else
    pass "acquire does NOT write claim.json under the worktree's tree"
  fi
fi

# ───────────────────────────────────────────────────────────────────────
# Release from inside the worktree — assert it removes the MAIN claim dir.
# ───────────────────────────────────────────────────────────────────────
(
  cd "$WT"
  bash "$CLAIM_SH" release foo --require-pipeline "run-plan.foo"
)
rc=$?
if [ "$rc" -ne 0 ]; then
  fail "release from worktree" "rc=$rc"
elif [ -d "$MAIN/.zskills/claims/plan-foo" ]; then
  fail "release MAIN dir removed" "directory still present at MAIN path"
else
  pass "release from worktree removes MAIN's plan-foo dir"
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
