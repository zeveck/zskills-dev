#!/usr/bin/env bash
# scripts/mark-plan-complete.sh <plan-file>
#
# Atomically marks a plan as complete by writing BOTH the status:complete
# AND completed:<ISO-8601-UTC> fields to the YAML frontmatter via
# frontmatter-set.sh. Prevents the half-write bug (#957) where a /run-plan
# agent writes status:complete via manual frontmatter Edit and skips the
# completed: timestamp, breaking the dashboard's Completed-column auto-route
# (collect.py inference requires BOTH fields).
#
# Usage: bash scripts/mark-plan-complete.sh <plan-file>
#
# Always use this helper. Do NOT call frontmatter-set.sh for status:complete
# directly — the both-or-nothing invariant is the whole point.
set -u

PLAN_FILE="${1:-}"
if [ -z "$PLAN_FILE" ]; then
  echo "ERROR: mark-plan-complete.sh: plan file path required" >&2
  exit 2
fi
if [ ! -f "$PLAN_FILE" ]; then
  echo "ERROR: mark-plan-complete.sh: plan file does not exist: $PLAN_FILE" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SET_SH="$SCRIPT_DIR/frontmatter-set.sh"
if [ ! -x "$SET_SH" ] && [ ! -r "$SET_SH" ]; then
  echo "ERROR: mark-plan-complete.sh: frontmatter-set.sh not found at $SET_SH" >&2
  exit 2
fi

# ISO-8601 UTC full datetime (matches GH closedAt format for uniform
# cross-source date comparison in the dashboard). NOT date -I — that's
# date-only and mixes poorly with the full-datetime form the historical
# backfill emits.
COMPLETED_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

bash "$SET_SH" "$PLAN_FILE" status complete || {
  echo "ERROR: mark-plan-complete.sh: frontmatter-set.sh status complete failed" >&2
  exit 3
}
bash "$SET_SH" "$PLAN_FILE" completed "$COMPLETED_TS" || {
  echo "ERROR: mark-plan-complete.sh: frontmatter-set.sh completed $COMPLETED_TS failed — plan is now in a HALF-WRITE state (status:complete but no completed:); re-run this script to recover" >&2
  exit 4
}

echo "INFO: mark-plan-complete.sh: $PLAN_FILE marked complete (completed: $COMPLETED_TS)" >&2
