#!/bin/bash
# scripts/sanitize-pipeline-id.sh — sanitizes PIPELINE_ID input to [a-zA-Z0-9._-]+
# Used by writers before persisting PIPELINE_ID to disk / .zskills-tracked / transcript.
# Usage:   sanitized=$(bash scripts/sanitize-pipeline-id.sh "<raw>")
# OR source and call the function:
#   source scripts/sanitize-pipeline-id.sh
#   sanitized=$(sanitize_pipeline_id "$raw")
set -eu
sanitize_pipeline_id() {
  printf '%s' "$1" | tr -c 'a-zA-Z0-9._-' '_' | head -c 128
}
# If sourced, just define the function. If executed, dispatch on $1.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  sanitize_pipeline_id "${1:-}"
fi
