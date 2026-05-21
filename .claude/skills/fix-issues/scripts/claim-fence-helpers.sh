#!/bin/bash
# claim-fence-helpers.sh — sourceable helpers for /fix-issues claim
# fences in SKILL.md.
#
# Phase 1 (round 4): exposes ONE function — sweep_stale_claims — a thin
# wrapper around `claim-issue.sh sweep`. The function exists so the
# preflight sweep fence in SKILL.md can be a single line
# (`sweep_stale_claims || true`), and so Phase 4 tests can source and
# verify the preflight semantics in isolation.
#
# Round 4 scope-down: `acquire_for_dispatch_list` is intentionally NOT
# defined here. Option C (the chosen architecture) eliminates the
# dispatch-list-loop entirely — acquire is inline at each per-issue
# dispatch site, so the bulk shape is unused.
#
# Usage:
#   . "$CLAUDE_PROJECT_DIR/.claude/skills/fix-issues/scripts/claim-fence-helpers.sh"
#   sweep_stale_claims || true

# Resolve the absolute path to the bundled claim-issue.sh next to this
# file. Works when sourced from any cwd.
_CLAIM_FENCE_HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_CLAIM_ISSUE_SH="${_CLAIM_FENCE_HELPERS_DIR}/claim-issue.sh"

sweep_stale_claims() {
  if [ ! -x "$_CLAIM_ISSUE_SH" ] && [ ! -f "$_CLAIM_ISSUE_SH" ]; then
    echo "claim-fence-helpers.sh: cannot locate claim-issue.sh at $_CLAIM_ISSUE_SH" >&2
    return 1
  fi
  bash "$_CLAIM_ISSUE_SH" sweep
}
