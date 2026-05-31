#!/bin/bash
# backfill-plan-completed.sh — One-shot historical backfill of the
# `completed:` YAML frontmatter field for plans with `status: complete`.
#
# Context: the dashboard's Completed window (D1 of
# plans/completed-backlog-sections.md) reads each plan's `completed:`
# frontmatter field. `/run-plan` Phase 5b writes the field on every new
# transition to `status: complete`, but historical plans transitioned
# before that mechanic existed. This script reconstructs the field for
# them from git history.
#
# Mechanism: a content-pickaxe over each plan's history. Specifically:
#
#   git log -G"^status:[[:space:]]*complete$" --follow --reverse \
#           --format=%cI -- "$PLAN_FILE" | tail -1
#
# This returns the COMMITTER-date (`%cI`) of the most-recent commit that
# introduced (or removed) the literal `status: complete` line. `--follow`
# survives renames. `tail -1` so an `active → complete → active →
# complete` re-upgrade picks the latest introduction.
#
# Empirically verified 2026-05-22: the file-creation-commit primitive
# (git log --diff-filter on add/modify) returns the initial commit (when
# frontmatter was `status: active`) — NOT the status-introduction commit.
# Pickaxe -G is the correct primitive.
#
# UTC normalization: `%cI` returns the committer's LOCAL TZ-offset (mixed
# `Z` and `-04:00` observed in this repo). We MUST normalize through
# `date -u -d "$raw_ts" +%Y-%m-%dT%H:%M:%SZ` before writing, so the
# on-disk format is uniform with the full-datetime form
# `/run-plan` Phase 5b emits and that GH `closedAt` uses.
#
# Idempotent: skips any plan whose `completed:` field is already set.
#
# Recovery from a buggy prior backfill (DA3.6): the idempotency guard
# prevents re-write. To force a re-run for a specific plan, first clear
# the existing value via:
#
#   bash scripts/frontmatter-set.sh <plan>.md completed ''
#
# (empty string clears the field's value), then re-run this script.
#
# Exit codes:
#   0  — backfill completed (summary printed even if some plans skipped)
#   1  — environment error (not in a zskills repo / required tool missing)

set -euo pipefail

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  cat <<'HELP'
Usage: bash skills/zskills-dashboard/scripts/backfill-plan-completed.sh

Backfill the `completed:` YAML frontmatter field on plans with
`status: complete` and no existing `completed:` field. Reads the
status-introduction commit's UTC committer-date via a content-pickaxe
(`git log -G"^status:[[:space:]]*complete$" --follow --reverse
--format=%cI -- <plan>` then `tail -1`) and writes it via
`scripts/frontmatter-set.sh`.

Idempotent: re-runs are no-ops once `completed:` is set.

To recover from a buggy prior backfill: first clear the bad value
with `bash scripts/frontmatter-set.sh <plan>.md completed ''`, then
re-run this script.
HELP
  exit 0
fi

# Hard-pin CWD to git toplevel (DA3.2). The pickaxe + path resolution
# below both assume a deterministic project root.
cd "$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "ERROR: not in a git repo" >&2
  exit 1
}

# Refuse to run outside a zskills-configured repo.
if [ ! -f .claude/zskills-config.json ]; then
  echo "ERROR: must run from a zskills-configured repo (no .claude/zskills-config.json at git toplevel)" >&2
  exit 1
fi

# Resolve $ZSKILLS_PLANS_DIR via the canonical shim. Hardcoding `plans/`
# is FORBIDDEN — this repo sets output.plans_dir: docs/plans.
# Lane-agnostic resolution: BASH_SOURCE-relative (works on a mirror-less
# plugin consumer — plugin tree + legacy mirror are both 1:1) first, then the
# consumer-mirror path under CLAUDE_PROJECT_DIR. ZSKILLS_PATHS_ROOT is provided
# up front (defaults to git-common-dir/cwd) so the shim resolves config dirs
# even when CLAUDE_PROJECT_DIR is unset; stderr from the probe is swallowed so
# a missing-env shim diagnostic doesn't leak (matching legacy behavior).
_self_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
: "${ZSKILLS_PATHS_ROOT:=${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}"
export ZSKILLS_PATHS_ROOT
if [ -f "$_self_dir/../../update-zskills/scripts/zskills-paths.sh" ] && \
   . "$_self_dir/../../update-zskills/scripts/zskills-paths.sh" 2>/dev/null; then
  :
elif . "${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/skills/update-zskills/scripts/zskills-paths.sh" 2>/dev/null; then
  :
else
  # Fallback: CLAUDE_PROJECT_DIR may not be set in this shell. The shim
  # itself falls back to git-common-dir; mirror that here.
  ZSKILLS_PATHS_ROOT="$(pwd)" \
    source "$(pwd)/.claude/skills/update-zskills/scripts/zskills-paths.sh"
fi
unset _self_dir

if [ -z "${ZSKILLS_PLANS_DIR:-}" ] || [ ! -d "$ZSKILLS_PLANS_DIR" ]; then
  echo "ERROR: ZSKILLS_PLANS_DIR not resolved or not a directory: ${ZSKILLS_PLANS_DIR:-<unset>}" >&2
  exit 1
fi

FRONTMATTER_GET="scripts/frontmatter-get.sh"
FRONTMATTER_SET="scripts/frontmatter-set.sh"

if [ ! -x "$FRONTMATTER_GET" ] && [ ! -f "$FRONTMATTER_GET" ]; then
  echo "ERROR: $FRONTMATTER_GET not present at git toplevel" >&2
  exit 1
fi

backfilled=0
skipped_already_set=0
skipped_empty_pickaxe=0
skipped_block_scalar=0
skipped_no_status_complete=0

shopt -s nullglob
for plan_file in "$ZSKILLS_PLANS_DIR"/*.md; do
  slug="$(basename "$plan_file" .md)"

  # Only process plans whose status is `complete` (or `landed`).
  status_val="$(bash "$FRONTMATTER_GET" "$plan_file" status 2>/dev/null || echo "")"
  case "$status_val" in
    complete|landed) ;;
    *)
      skipped_no_status_complete=$((skipped_no_status_complete + 1))
      continue
      ;;
  esac

  # Idempotency: skip if `completed:` already set (non-empty).
  existing="$(bash "$FRONTMATTER_GET" "$plan_file" completed 2>/dev/null || echo "")"
  if [ -n "$existing" ]; then
    skipped_already_set=$((skipped_already_set + 1))
    continue
  fi

  # Content-pickaxe for the status-introduction commit. `--follow`
  # handles renames; `--reverse` + `tail -1` picks the MOST-RECENT
  # introduction (re-upgrade case).
  #
  # Primary invocation per AC1.9 (the form documented in the plan):
  raw_ts="$(git log -G"^status:[[:space:]]*complete$" --follow --reverse \
                --format=%cI -- "$plan_file" 2>/dev/null | tail -1)"
  #
  # Empirical caveat (git 2.x): `-G` combined with `--follow` is
  # documented to silently drop pre-rename history matches in some
  # environments. When the primary invocation returns nothing, we
  # compensate by enumerating the file's historical paths via
  # `git log --follow --name-only` and pickaxing across the UNION of
  # those paths (current + every historical name). Identical result
  # when no renames occurred.
  if [ -z "$raw_ts" ]; then
    mapfile -t hist_paths < <(
      git log --follow --name-only --format= -- "$plan_file" 2>/dev/null \
        | awk 'NF' | sort -u
    )
    if [ "${#hist_paths[@]}" -gt 0 ]; then
      raw_ts="$(git log -G"^status:[[:space:]]*complete$" --reverse \
                    --format=%cI -- "${hist_paths[@]}" 2>/dev/null | tail -1)"
    fi
  fi

  if [ -z "$raw_ts" ]; then
    echo "WARN: pickaxe returned no commits for $slug: completed-field cannot be backfilled; please set manually via 'bash scripts/frontmatter-set.sh $plan_file completed <ISO-UTC>'" >&2
    skipped_empty_pickaxe=$((skipped_empty_pickaxe + 1))
    continue
  fi

  # Normalize to UTC `Z` (DA3.1). `%cI` returns committer-local-TZ
  # (mixed Z and -04:00 in this repo).
  iso_utc="$(date -u -d "$raw_ts" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")"
  if [ -z "$iso_utc" ]; then
    echo "WARN: failed to normalize '$raw_ts' to UTC for $slug; skipping" >&2
    skipped_empty_pickaxe=$((skipped_empty_pickaxe + 1))
    continue
  fi

  # Write the field. Exit 3 means block-scalar refusal — log + continue.
  set +e
  bash "$FRONTMATTER_SET" "$plan_file" completed "$iso_utc"
  rc=$?
  set -e
  if [ "$rc" -eq 3 ]; then
    echo "WARN: skipping $slug: frontmatter-set.sh refused block-scalar overwrite (exit 3)" >&2
    skipped_block_scalar=$((skipped_block_scalar + 1))
    continue
  fi
  if [ "$rc" -ne 0 ]; then
    echo "WARN: skipping $slug: frontmatter-set.sh exited $rc" >&2
    continue
  fi

  echo "BACKFILL $slug: completed=$iso_utc"
  backfilled=$((backfilled + 1))
done

echo ""
echo "Summary:"
echo "  backfilled:                            $backfilled"
echo "  skipped (completed: already set):      $skipped_already_set"
echo "  skipped (no status: complete):         $skipped_no_status_complete"
echo "  $skipped_empty_pickaxe plans skipped due to empty pickaxe (manual fix required)"
echo "  $skipped_block_scalar plans skipped due to block-scalar refusals (manual fix required)"

exit 0
