#!/bin/bash
# sanitize-pipeline-id.sh — sanitizes PIPELINE_ID input to [a-zA-Z0-9._-]+
# Used by writers before persisting PIPELINE_ID to disk / .zskills/tracked / transcript.
# Usage:   sanitized=$(bash $(basename "$0") "<raw>")
# OR source and call the function:
#   source $(basename "$0")
#   sanitized=$(sanitize_pipeline_id "$raw")
set -eu
sanitize_pipeline_id() {
  # Empty input is never valid: callers use the result as PIPELINE_ID, and
  # downstream `mkdir -p ".zskills/tracking/$PIPELINE_ID"` + marker writes
  # would silently produce flat markers under `.zskills/tracking/` — which
  # violates the per-pipeline-subdir invariant from CLAUDE.md's
  # `## Tracking markers` rule ("never flat under `.zskills/tracking/`
  # directly"). Fail loud instead of emitting empty stdout + exit 0. See
  # issue #468.
  if [ -z "${1:-}" ]; then
    echo "sanitize-pipeline-id: empty input — refusing to produce empty PIPELINE_ID (would silently create flat tracking markers; see issue #468)" >&2
    exit 2
  fi
  printf '%s' "$1" | tr -c 'a-zA-Z0-9._-' '_' | head -c 128
}
# If sourced, just define the function. If executed, dispatch on $1.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  sanitize_pipeline_id "${1:-}"
fi
