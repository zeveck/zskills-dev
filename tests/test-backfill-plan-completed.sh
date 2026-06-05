#!/bin/bash
# Tests for backfill-plan-completed.sh
#
# Covers:
#   T672.1                      Script does not fail with "unbound variable"
#                               when CLAUDE_PROJECT_DIR is unset (#672).
#   T-sandbox-no-live-mutation  Running the test does NOT mutate the LIVE
#                               repo's docs/plans/ (the regression fixed here).
#
# Isolation: backfill-plan-completed.sh cd's to the git toplevel and stamps a
# `completed:` YAML frontmatter field into EVERY plan under docs/plans/ that
# has `status: complete` and lacks `completed:`. Running it against the LIVE
# repo therefore DIRTIES real plan files (e.g. docs/plans/SKILL_VERIFICATION_
# SMOKES.md), which then blocks rebases mid-pipeline. So we run the real
# backfill end-to-end inside a throwaway local CLONE of the repo — a clone is
# guaranteed-complete (backfill needs the full working layout + the
# BASH_SOURCE-relative helper chain) and the EXIT trap removes it, leaving the
# live tree untouched.
#
# Run from repo root: bash tests/test-backfill-plan-completed.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BACKFILL_SCRIPT="skills/zskills-dashboard/scripts/backfill-plan-completed.sh"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
skip() { printf '\033[33m  SKIP\033[0m %s\n' "$1"; SKIP_COUNT=$((SKIP_COUNT + 1)); }

print_summary_and_exit() {
  echo ""
  echo "---"
  local total=$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))
  if [ "$FAIL_COUNT" -eq 0 ]; then
    printf '\033[32mResults: %d passed, %d failed, %d skipped (of %d)\033[0m\n' \
      "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$total"
    exit 0
  else
    printf '\033[31mResults: %d passed, %d failed, %d skipped (of %d)\033[0m\n' \
      "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$total"
    exit 1
  fi
}

if [ ! -f "$REPO_ROOT/$BACKFILL_SCRIPT" ]; then
  fail "backfill script exists at expected path"
  print_summary_and_exit
fi

# ── Throwaway clone — backfill EDITS plans in place; never touch $REPO_ROOT ──
#
# A local-path clone works on BOTH a full dev checkout AND a shallow CI
# checkout (actions/checkout@v4 fetch-depth:1). Backfill only edits files in
# place (frontmatter-set.sh) — it never `git commit`s — so the clone needs NO
# git identity. On a shallow clone the content-pickaxe finds no history and
# backfill legitimately skips every plan with a WARN; that is fine and must
# not fail the test (see T-sandbox-no-live-mutation tolerance note).
TMP="$(mktemp -d)"
SANDBOX="$TMP/sandbox"
trap 'rm -rf "$TMP"' EXIT

# Concurrency-safe clone via a one-shot bundle SNAPSHOT (setup-robustness only;
# assertions unchanged). This is a linked worktree → its .git objects+refs are
# SHARED with the parent repo, and under parallel test fan-out sibling suites
# churn that store, racing every LIVE clone transport (default copy → tmp_obj
# `No such file`; upload-pack → `not our ref 000...0`). `git bundle create`
# takes one atomic consistent read; cloning the static file is immune to both.
REPO_SNAPSHOT="$TMP/repo-snapshot.bundle"
git -C "$REPO_ROOT" bundle create --quiet "$REPO_SNAPSHOT" HEAD
if ! git clone --quiet "$REPO_SNAPSHOT" "$SANDBOX"; then
  fail "0. git clone of \$REPO_ROOT into sandbox failed"
  print_summary_and_exit
fi

# Snapshot the LIVE repo's docs/plans/ state BEFORE the backfill run. We
# compare BEFORE vs AFTER (delta), so a pre-existing unrelated dirty tree
# does NOT make this test fail — only a NEW modification introduced by the
# backfill run does.
live_plans_before="$(git -C "$REPO_ROOT" status --porcelain -- docs/plans/)"

# ── T672.1 — no "unbound variable" crash when CLAUDE_PROJECT_DIR unset ──
#
# Run the real backfill from INSIDE the sandbox with CLAUDE_PROJECT_DIR
# explicitly unset (preserving the EXACT T672.1 condition), via the sandbox's
# OWN repo-relative script path so its BASH_SOURCE-relative helper resolution
# points at the sandbox tree (not the live repo). The script should NOT crash
# with "unbound variable". It should either succeed (exit 0) or fail
# gracefully for other reasons (e.g., no plans to backfill), but never with
# the specific "unbound variable" error message on stderr.
output="$(cd "$SANDBOX" && env -u CLAUDE_PROJECT_DIR bash "$BACKFILL_SCRIPT" 2>&1)" || true
rc=$?

if echo "$output" | grep -q "unbound variable"; then
  fail "T672.1 — script crashes with 'unbound variable' when CLAUDE_PROJECT_DIR is unset"
  echo "    stderr/stdout contained: $(echo "$output" | grep 'unbound variable')"
else
  pass "T672.1 — no 'unbound variable' error when CLAUDE_PROJECT_DIR is unset (exit $rc)"
fi

# ── T-sandbox-no-live-mutation — the LIVE repo's docs/plans/ is delta-unchanged ──
#
# The whole point of running backfill inside the sandbox clone: the live
# repo's docs/plans/ must be byte-identical before and after. We compare the
# porcelain DELTA (before vs after) so an already-dirty live tree (for some
# unrelated reason) does not produce a false failure — only a NEW
# docs/plans/ modification introduced by this test does.
live_plans_after="$(git -C "$REPO_ROOT" status --porcelain -- docs/plans/)"

if [ "$live_plans_before" = "$live_plans_after" ]; then
  pass "T-sandbox-no-live-mutation — live docs/plans/ unchanged by backfill run"
else
  fail "T-sandbox-no-live-mutation — backfill mutated the LIVE repo's docs/plans/"
  echo "    NEW changes introduced by the backfill run (after minus before):"
  # Print porcelain lines present AFTER but not BEFORE.
  comm -13 <(printf '%s\n' "$live_plans_before" | sort) \
           <(printf '%s\n' "$live_plans_after"  | sort) \
    | sed 's/^/      /'
fi

print_summary_and_exit
