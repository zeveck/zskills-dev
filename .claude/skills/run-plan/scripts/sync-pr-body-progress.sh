#!/bin/bash
# sync-pr-body-progress.sh — Splice an updated progress section into the
# GitHub PR body for a /run-plan PR-mode pipeline.
#
# Purpose: /run-plan PR mode Phase 4 step 5 used to be ~80 lines of inline
# bash prose that the orchestrator could (and did, e.g., PR #211) skip
# without any mechanical signal. This helper converts that prose into a
# single invocation with a conformance assertion, so skipping it breaks a
# test instead of silently freezing the PR body.
#
# Behaviour:
#   1. Read the plan file's progress tracker rows (lines matching
#      `^\| .* \| ✅`) — same regex modes/pr.md uses at PR-open time.
#   2. Build a `**Phases completed:**` markdown block from those rows.
#   3. Read the current PR body via `gh pr view --json body --jq '.body'`.
#   4. Splice the new block between
#      `<!-- run-plan:progress:start -->` and `<!-- run-plan:progress:end -->`
#      using pure bash regex (BASH_REMATCH). NO jq, NO python.
#   5. Write the updated body back via `gh pr edit --body-file`.
#
# Idempotency: re-running with no tracker change produces a byte-identical
# body (the regenerated block is byte-identical, and the splice only touches
# the marker-enclosed region).
#
# Graceful failure modes — each emits a discriminator line to stderr:
#   - PR doesn't exist (`gh pr view` fails)          → NOTICE → exit 0
#   - Markers absent in PR body                       → NOTICE → exit 0
#   - `gh pr edit` fails (auth / network / etc.)      → WARNING → exit 0
#   - Plan file missing or unreadable                 → ERROR → exit 1
#   - `gh` binary missing                             → ERROR → exit 1
#   - Required arg missing                            → ERROR → exit 2
#
# The PR body is a convenience surface; the worktree's tracker commit is
# the source of truth. Never block Phase 4 on a sync failure.
#
# Hygiene (per CLAUDE.md "Never suppress errors on operations you need to
# verify"):
#   - Never `2>/dev/null` on a fallible op whose success matters.
#   - Capture stderr to a sidecar file before reporting, so the discriminator
#     line carries the actual failure text.
#   - Test hooks override the `gh` binary via $GH_BIN_OVERRIDE so unit tests
#     can simulate view/edit failures without networking.
#
# Usage:
#   bash sync-pr-body-progress.sh \
#     --pr <num> \
#     --plan-file <path> \
#     [--branch <name>]
#
# Test hook:
#   GH_BIN_OVERRIDE — when set, replaces `gh` for the duration of the run.
#   Pointed at a mock script in tests/test-run-plan-sync-pr-body-progress.sh.

set -u

PR_NUMBER=""
PLAN_FILE=""
BRANCH_NAME=""

while [ $# -gt 0 ]; do
  case "$1" in
    --pr)        PR_NUMBER="${2:-}";   shift 2 ;;
    --plan-file) PLAN_FILE="${2:-}";   shift 2 ;;
    --branch)    BRANCH_NAME="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '2,55p' "$0" >&2
      exit 0
      ;;
    *)
      echo "ERROR: unknown arg '$1'" >&2
      exit 2
      ;;
  esac
done

if [ -z "$PR_NUMBER" ]; then
  echo "ERROR: --pr is required" >&2
  exit 2
fi
if [ -z "$PLAN_FILE" ]; then
  echo "ERROR: --plan-file is required" >&2
  exit 2
fi

# Plan file must exist and be readable.
if [ ! -f "$PLAN_FILE" ]; then
  echo "ERROR: plan file not found: $PLAN_FILE" >&2
  exit 1
fi
if [ ! -r "$PLAN_FILE" ]; then
  echo "ERROR: plan file not readable: $PLAN_FILE" >&2
  exit 1
fi

# Resolve gh binary (allow test override). When unset, locate `gh` in PATH.
GH="${GH_BIN_OVERRIDE:-gh}"
if ! command -v "$GH" >/dev/null 2>&1; then
  echo "ERROR: gh binary not found (looked for '$GH')" >&2
  exit 1
fi

# Marker sentinels — keep in sync with skills/run-plan/modes/pr.md.
START_MARKER='<!-- run-plan:progress:start -->'
END_MARKER='<!-- run-plan:progress:end -->'

# Per-run scratch directory (per-PR so concurrent pipelines don't collide).
SCRATCH="/tmp/sync-pr-body-progress-${PR_NUMBER}-$$"
mkdir -p "$SCRATCH"
trap 'rm -rf "$SCRATCH"' EXIT

PR_BODY_FILE="$SCRATCH/pr-body.md"
PR_VIEW_ERR="$SCRATCH/pr-view.err"
PR_EDIT_ERR="$SCRATCH/pr-edit.err"
NEW_BODY_FILE="$SCRATCH/new-body.md"

# --- 1. Fetch current PR body ---
# Capture stderr so a NOTICE can carry the gh failure text. Do NOT use
# `2>/dev/null` — we need to know *why* the view failed.
if ! "$GH" pr view "$PR_NUMBER" --json body --jq '.body' > "$PR_BODY_FILE" 2> "$PR_VIEW_ERR"; then
  err=$(cat "$PR_VIEW_ERR" 2>/dev/null || true)
  printf 'NOTICE: skipping PR body sync — gh pr view #%s failed: %s\n' \
    "$PR_NUMBER" "${err:-<empty stderr>}" >&2
  exit 0
fi

CURRENT_BODY=$(cat "$PR_BODY_FILE")

# --- 2. Build the new progress block from the plan tracker ---
# Same regex modes/pr.md uses at PR-open time — keep aligned.
# grep returns non-zero on no-match; fall back to a placeholder so the
# block still renders.
COMPLETED_PHASES=$(grep -E '^\| .* \| ✅' "$PLAN_FILE" | sed 's/|//g' | awk '{$1=$1};1') || true
if [ -z "$COMPLETED_PHASES" ]; then
  COMPLETED_PHASES="See plan file"
fi

NEW_PROGRESS="**Phases completed:**
$COMPLETED_PHASES"

# --- 3. Splice between markers ---
# Bash regex with BASH_REMATCH. Pattern captures:
#   group 1: everything up to and including the start marker
#   group 2: the previous progress content (replaced)
#   group 3: the end marker and everything after
#
# Graceful on missing markers — print NOTICE and exit 0 (PR was opened by
# something other than /run-plan PR mode, e.g., a hotfix or external PR).
if [[ "$CURRENT_BODY" =~ (.*$START_MARKER)(.*)($END_MARKER.*) ]]; then
  PREFIX="${BASH_REMATCH[1]}"
  SUFFIX="${BASH_REMATCH[3]}"
  UPDATED_BODY="${PREFIX}
${NEW_PROGRESS}
${SUFFIX}"
else
  printf 'NOTICE: skipping PR body sync — markers not found; this is expected for PRs not opened by /run-plan PR mode (PR #%s, branch %s)\n' \
    "$PR_NUMBER" "${BRANCH_NAME:-<unknown>}" >&2
  exit 0
fi

# --- 4. Idempotency early-exit ---
# If the spliced body is byte-identical to the current body, skip the
# gh pr edit call. Avoids spurious "edited" notifications on GitHub when
# the tracker hasn't changed phase-to-phase.
if [ "$UPDATED_BODY" = "$CURRENT_BODY" ]; then
  printf 'PR #%s body already in sync — no edit needed.\n' "$PR_NUMBER"
  exit 0
fi

# --- 5. Write back via gh pr edit --body-file ---
# Use --body-file (not --body) for safety with multi-line content. Capture
# stderr for the WARNING discriminator.
printf '%s' "$UPDATED_BODY" > "$NEW_BODY_FILE"

if ! "$GH" pr edit "$PR_NUMBER" --body-file "$NEW_BODY_FILE" > /dev/null 2> "$PR_EDIT_ERR"; then
  err=$(cat "$PR_EDIT_ERR" 2>/dev/null || true)
  printf 'WARNING: gh pr edit #%s failed — PR body not synced (auth/network?): %s\n' \
    "$PR_NUMBER" "${err:-<empty stderr>}" >&2
  exit 0
fi

printf 'Synced PR #%s body progress section.\n' "$PR_NUMBER"
exit 0
