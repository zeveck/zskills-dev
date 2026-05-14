#!/bin/bash
# migrate-flat-tracking-markers.sh — relocate legacy flat fulfilled.* tracking
# markers into per-pipeline subdirectories under .zskills/tracking/, matching
# the Option B layout documented at docs/tracking/TRACKING_NAMING.md.
#
# Background: before the tracking-subdir migration, fulfilled.run-plan.<id>
# (and similar) markers were stored flat under .zskills/tracking/. The
# current scheme stores them under .zskills/tracking/<skill>.<id>/, which
# enables per-pipeline tracking of requires/step/fulfilled together. Older
# completion records still on disk as flat files render as "legacy"
# (location field) in the dashboard's activity feed and persist as data
# residue. This script is the one-shot migration to bring them forward.
#
# Algorithm (per flat fulfilled.<skill>.<id> file under .zskills/tracking/):
#   1. Derive subdir name = "<skill>.<id>" (the basename without "fulfilled.").
#   2. If the corresponding subdir/fulfilled.<skill>.<id> already exists:
#      - Compare via cmp -s. Identical → remove flat duplicate (no data
#        loss).
#      - Differs → log CONFLICT; do NOT touch either file.
#   3. Otherwise:
#      - mkdir -p .zskills/tracking/<skill>.<id>/
#      - mv flat → subdir/. (atomic on same filesystem; preserves mtime.)
#
# Usage:
#   bash scripts/migrate-flat-tracking-markers.sh [<main-root>]
#
# <main-root> defaults to the current working directory.
#
# Exit codes:
#   0 — migration applied (any combination of migrated/no-op/zero-files).
#   1 — mid-migration filesystem failure (e.g., mv refused).
#   2 — at least one conflict detected; manual review required.

set -u

MAIN_ROOT="${1:-$(pwd)}"
TRACKING="$MAIN_ROOT/.zskills/tracking"

if [ ! -d "$TRACKING" ]; then
  echo "no tracking dir at $TRACKING; nothing to migrate"
  exit 0
fi

migrated=0
no_op=0
conflicts=0

# Iterate flat fulfilled.* files at the top level of $TRACKING.
# Skip directories (which is where Option-B markers already live).
shopt -s nullglob
for flat in "$TRACKING"/fulfilled.*; do
  [ -f "$flat" ] || continue
  basename=$(basename "$flat")

  # basename pattern: fulfilled.<skill>.<id> where <id> may itself contain
  # dots. We strip the literal "fulfilled." prefix and trust the remainder
  # as the subdir name. (This matches the inverse of how the Option-B
  # marker writers compose paths: subdir = pipeline-id, file = full
  # basename including "fulfilled." prefix.)
  subdir_name="${basename#fulfilled.}"
  if [ "$subdir_name" = "$basename" ]; then
    # Basename did not actually start with "fulfilled." — unexpected match.
    # Skip it; do not invent a destination.
    echo "skip: $basename (does not match fulfilled.* prefix)" >&2
    continue
  fi

  subdir="$TRACKING/$subdir_name"
  target="$subdir/$basename"

  if [ -f "$target" ]; then
    if cmp -s "$flat" "$target"; then
      # Identical content. The flat file is a redundant duplicate of the
      # canonical subdir copy. Safe to remove.
      if rm -- "$flat"; then
        no_op=$((no_op + 1))
        echo "no-op: $basename (subdir copy identical; flat duplicate removed)"
      else
        echo "FAIL: could not remove redundant flat duplicate $flat" >&2
        exit 1
      fi
    else
      # Content differs — conflicting state. Refuse to overwrite either
      # file; the user must reconcile manually.
      conflicts=$((conflicts + 1))
      echo "CONFLICT: $basename differs between flat and subdir; flat preserved for review." >&2
      echo "  flat:   $flat" >&2
      echo "  subdir: $target" >&2
    fi
  else
    # No subdir copy yet. Promote the flat file into a freshly-created
    # subdir. mkdir -p is idempotent; mv is atomic on same filesystem
    # and preserves mtime.
    if ! mkdir -p "$subdir"; then
      echo "FAIL: could not mkdir $subdir" >&2
      exit 1
    fi
    if mv -- "$flat" "$target"; then
      migrated=$((migrated + 1))
      echo "migrated: $basename → $subdir_name/"
    else
      echo "FAIL: could not mv $flat → $target" >&2
      exit 1
    fi
  fi
done
shopt -u nullglob

echo
echo "Summary: $migrated migrated, $no_op duplicates removed, $conflicts conflicts."

if [ "$conflicts" -gt 0 ]; then
  exit 2
fi
exit 0
