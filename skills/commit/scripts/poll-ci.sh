#!/bin/bash
# poll-ci.sh — Block until a PR's CI checks complete, then report pass/fail.
#
# Extracted from /commit pr Step 6 (skills/commit/modes/pr.md). Lives as a
# script — not inline prose — so the agent can't paraphrase or skip it.
# Past failure (2026-04-30): on PR #131, the orchestrator read Step 6 as
# suggestion-prose, did one snapshot `gh pr checks 131` showing `pending`,
# reported "CI: pending (poll with `gh pr checks 131`)" in its summary, and
# exited. User discovered the midnight CI flake 20+ minutes later by manual
# polling. See issue #133.
#
# Behavior is identical to the previous inline block: poll up to 3×10s for
# checks to register, then `timeout 600 gh pr checks --watch` to block, then
# re-check via `gh pr checks` (no --watch, exit code is reliable) and emit
# "CI checks passed." or "CI checks failed. Run /verify-changes to diagnose."
#
# Usage: bash poll-ci.sh <PR_NUMBER>
# Exit:
#   0 — checks passed (or no checks ever registered → no-op)
#   1 — checks failed
#   2 — usage error

set -u

PR_NUMBER="${1:-}"
if [ -z "$PR_NUMBER" ]; then
  echo "Usage: bash $(basename "$0") <PR_NUMBER>" >&2
  exit 2
fi

# Step 1: poll up to 30s for checks to register on the PR.
CHECK_COUNT=0
for _i in 1 2 3; do
  CHECK_COUNT=$(gh pr checks "$PR_NUMBER" --json name --jq 'length' 2>/dev/null || echo "0")
  [ "$CHECK_COUNT" != "0" ] && break
  sleep 10
done

# No checks ever registered — nothing to poll. Exit 0 (matches the previous
# inline behavior of falling out of the if-block silently).
if [ "$CHECK_COUNT" = "0" ]; then
  exit 0
fi

# Step 2: block until checks complete.
# `gh pr checks --watch` exit code is unreliable across gh versions (can
# return 0 even when a check failed), so use --watch only to block; then
# re-check with `gh pr checks` (no --watch), whose exit code IS reliable.
timeout 600 gh pr checks "$PR_NUMBER" --watch 2>/dev/null

if gh pr checks "$PR_NUMBER" >/dev/null 2>&1; then
  echo "CI checks passed."
  exit 0
else
  echo "CI checks failed. Run /verify-changes to diagnose."
  exit 1
fi
