#!/bin/bash
# claim-fence-helpers.sh — sourceable helpers for /run-plan claim fences
# in SKILL.md.
#
# Phase 1 scope: exposes ONE function — sweep_stale_plan_claims — a thin
# wrapper around `claim-plan.sh sweep`. The function exists so the
# /run-plan Phase 1 preflight sweep fence can be a single line
# (`sweep_stale_plan_claims || true`) and so Phase 1 tests can source
# and verify the preflight semantics in isolation.
#
# Mirror of skills/fix-issues/scripts/claim-fence-helpers.sh.
#
# Usage:
#   . "$CLAUDE_PROJECT_DIR/.claude/skills/run-plan/scripts/claim-fence-helpers.sh"
#   sweep_stale_plan_claims || true

_CLAIM_FENCE_HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_CLAIM_PLAN_SH="${_CLAIM_FENCE_HELPERS_DIR}/claim-plan.sh"

sweep_stale_plan_claims() {
  if [ ! -x "$_CLAIM_PLAN_SH" ] && [ ! -f "$_CLAIM_PLAN_SH" ]; then
    echo "claim-fence-helpers.sh: cannot locate claim-plan.sh at $_CLAIM_PLAN_SH" >&2
    return 1
  fi
  bash "$_CLAIM_PLAN_SH" sweep
}
