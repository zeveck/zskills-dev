#!/bin/bash
# pr-preflight.sh — open-PR file-path conflict gate for /run-plan PR-mode
# pipelines.
#
# Purpose: when a plan touches a path prefix (e.g. `skills/update-zskills/`)
# across multiple phases, every phase needs a coordination preflight that
# answers "is anyone else's open PR touching this path?" The gate must
# self-filter the pipeline's OWN PR (issue #177) — without --exclude-pr,
# the pipeline trips on its own feature branch starting at Phase 2.
#
# This helper replaces the inlined `gh pr list --state open --limit 100
# --json number,title,files | grep -F '<prefix>'` pattern that previously
# appeared in plan files. Plans cite this script instead.
#
# Usage:
#   bash skills/run-plan/scripts/pr-preflight.sh \
#     --path-prefix skills/update-zskills/ \
#     [--exclude-pr 175] \
#     [--limit 100]
#
# Output discipline:
#   - stdout: matching PR numbers, one per line. Empty when clean.
#   - stderr: progress, warnings, errors.
#
# Exit codes:
#   0  — no conflict (zero matching PRs after exclusion)
#   1  — at least one matching PR (hard-abort gate trips)
#   2  — argument or environment error (bad flags, gh failure, etc.)
#
# Plans use this as: `bash <script> --path-prefix X --exclude-pr "$PR" || abort`
#
# Test hook:
#   GH_PR_LIST_JSON_OVERRIDE — when set, the helper uses this string as the
#   raw `gh pr list` JSON output instead of invoking `gh`. Only consumed by
#   tests/test-pr-preflight.sh.
#
# No jq. JSON parsing is pure bash regex (BASH_REMATCH). Pattern follows
# .claude/skills/update-zskills/scripts/zskills-resolve-config.sh.

set -euo pipefail

PATH_PREFIX=""
EXCLUDE_PR=""
LIMIT="100"

while [ $# -gt 0 ]; do
  case "$1" in
    --path-prefix) PATH_PREFIX="${2:-}"; shift 2 ;;
    --exclude-pr)  EXCLUDE_PR="${2:-}";  shift 2 ;;
    --limit)       LIMIT="${2:-}";        shift 2 ;;
    -h|--help)
      sed -n '2,30p' "$0" >&2
      exit 0
      ;;
    *)
      echo "ERROR: unknown arg '$1'" >&2
      exit 2
      ;;
  esac
done

if [ -z "$PATH_PREFIX" ]; then
  echo "ERROR: --path-prefix is required" >&2
  exit 2
fi

# Validate --exclude-pr (when provided) is a positive integer. Empty is
# allowed and means "no exclusion" — the script is safe to call before the
# orchestrator knows the pipeline's PR number.
if [ -n "$EXCLUDE_PR" ]; then
  if ! [[ "$EXCLUDE_PR" =~ ^[0-9]+$ ]]; then
    echo "ERROR: --exclude-pr must be a positive integer; got '$EXCLUDE_PR'" >&2
    exit 2
  fi
fi

if ! [[ "$LIMIT" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --limit must be a positive integer; got '$LIMIT'" >&2
  exit 2
fi

# Acquire raw gh output (or test override).
if [ -n "${GH_PR_LIST_JSON_OVERRIDE:-}" ]; then
  RAW="$GH_PR_LIST_JSON_OVERRIDE"
else
  if ! RAW=$(gh pr list --state open --limit "$LIMIT" --json number,title,files 2>&1); then
    echo "ERROR: 'gh pr list' failed: $RAW" >&2
    exit 2
  fi
fi

# Soft-cap warning: if the JSON contains as many `"number":` occurrences as
# the limit, the next page may exist. (refine-plan F-R2-9 in
# plans/SKILL_VERSIONING.md.)
RAW_COUNT=$(printf '%s' "$RAW" | grep -c '"number":' || true)
if [ "$RAW_COUNT" -ge "$LIMIT" ]; then
  echo "WARN: gh pr list returned $RAW_COUNT PRs (limit=$LIMIT); re-run with --limit higher to verify no missed entries." >&2
fi

# Split the JSON array into per-PR object chunks. The shape from
# `gh pr list --json number,title,files` is:
#   [{"number":N,"title":"T","files":[{"path":"P",...},...]},...]
#
# We split on the boundary between consecutive PR objects ('},{' at the
# top level) and check each chunk independently. This avoids cross-PR
# false matches that the un-split `grep -F` form silently produced.
#
# Pure bash: replace '},{' with a record separator (newline + sentinel),
# then iterate.

# Strip outer brackets `[` and `]` if present, then split.
STRIPPED="${RAW#\[}"
STRIPPED="${STRIPPED%\]}"

# Empty result → no PRs.
if [ -z "$STRIPPED" ]; then
  exit 0
fi

# Replace '},{' with '}\n{' so each PR object lives on its own line.
# Use bash parameter expansion.
SPLIT="${STRIPPED//\},\{/$'}\n{'}"

MATCHES=()
while IFS= read -r CHUNK; do
  [ -z "$CHUNK" ] && continue

  # Extract PR number (first occurrence of "number":N at the top of chunk).
  if [[ "$CHUNK" =~ \"number\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
    PR_NUM="${BASH_REMATCH[1]}"
  else
    # Malformed chunk — skip silently (defensive; shouldn't happen with
    # well-formed gh output).
    continue
  fi

  # Self-filter: skip the pipeline's own PR.
  if [ -n "$EXCLUDE_PR" ] && [ "$PR_NUM" = "$EXCLUDE_PR" ]; then
    continue
  fi

  # Check if this chunk's files contain the path prefix. Use grep -F over
  # the chunk: matches against the JSON-encoded `"path":"<prefix>..."`
  # strings.
  if printf '%s' "$CHUNK" | grep -qF "\"path\":\"$PATH_PREFIX"; then
    MATCHES+=("$PR_NUM")
  fi
done <<< "$SPLIT"

if [ "${#MATCHES[@]}" -eq 0 ]; then
  exit 0
fi

# Emit matches one per line on stdout.
for PR in "${MATCHES[@]}"; do
  echo "$PR"
done

# Stderr summary so plans/users see a human-readable abort line.
echo "FAIL: ${#MATCHES[@]} open PR(s) touch '$PATH_PREFIX' (excluding ${EXCLUDE_PR:-<none>}): ${MATCHES[*]}" >&2

exit 1
