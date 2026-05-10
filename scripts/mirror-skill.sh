#!/bin/bash
# scripts/mirror-skill.sh — Regenerate .claude/skills/<name>/ mirror from
# skills/<name>/ OR block-diagram/<name>/. Hook-compatible: uses per-file
# rm (no -r flag) for orphan removal instead of `rm -rf`, avoiding
# block-unsafe-generic.sh's recursive-rm gate.
#
# Usage:
#   bash scripts/mirror-skill.sh <skill-name>
#     Mirrors skills/<skill-name>/ -> .claude/skills/<skill-name>/
#   bash scripts/mirror-skill.sh block-diagram/<skill-name>
#     Mirrors block-diagram/<skill-name>/ -> .claude/skills/<skill-name>/
#     (the .claude/skills destination uses the BASENAME — no
#     `.claude/skills/block-diagram/` parent is created).
#
# Hook-safety invariant (Phase 1b §1b.1): this script MUST continue to
# use per-file `rm` (no `-r`/`-R` flag) and `find ... -type f` walks for
# orphan removal. The Phase-1 broadened block-unsafe-project.sh fence
# blocks any recursive delete inside `.zskills/`; the same discipline
# applied here keeps `mirror-skill.sh` hook-safe even before consumer
# repos re-render. Future edits MUST NOT introduce `rm -r`, `rm -rf`,
# or `find -delete` against the mirror destinations.
#
# Exit:
#   0 — mirror updated, diff -rq clean.
#   1 — usage error, source path missing, or post-regen diff non-clean.

set -u

NAME="${1:-}"
if [ -z "$NAME" ]; then
  echo "Usage: bash scripts/mirror-skill.sh <skill-name>|block-diagram/<skill-name>" >&2
  exit 1
fi

# Resolve repo root (allow caller to be in any subdir).
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# Two-tree resolution: if NAME contains "/" and matches block-diagram/X,
# use that as SRC; otherwise default to skills/<NAME>. The destination
# always lives at .claude/skills/<basename> — no block-diagram parent
# directory is materialised under .claude/skills/.
case "$NAME" in
  block-diagram/*)
    SRC="$REPO_ROOT/$NAME"
    DST="$REPO_ROOT/.claude/skills/${NAME#block-diagram/}"
    ;;
  *)
    SRC="$REPO_ROOT/skills/$NAME"
    DST="$REPO_ROOT/.claude/skills/$NAME"
    ;;
esac

if [ ! -d "$SRC" ]; then
  echo "ERROR: source dir not found: $SRC" >&2
  exit 1
fi

mkdir -p "$DST"

# Copy source contents over destination — handles file updates and adds.
# `cp -a src/. dst/` is the dot-source idiom that copies CONTENTS into
# dst (not src as a subdir of dst).
cp -a "$SRC/." "$DST/"

# Find files in mirror that don't exist in source, remove them per-file.
# `diff -rq` output line for orphans: "Only in <dir>[/<subdir>]: <basename>"
# We pass `dst` to awk as a variable to handle paths with regex metachars.
diff -rq "$SRC/" "$DST/" 2>/dev/null | awk -v dst="$DST" '
  index($0, "Only in " dst) == 1 {
    # Strip the leading "Only in " prefix.
    line = substr($0, length("Only in ") + 1)
    # Split on ": " — left side is the directory, right is the basename.
    sep = index(line, ": ")
    if (sep == 0) next
    dir = substr(line, 1, sep - 1)
    base = substr(line, sep + 2)
    print dir "/" base
  }
' | while IFS= read -r orphan; do
  if [ -f "$orphan" ]; then
    rm -- "$orphan"
  elif [ -d "$orphan" ]; then
    # Empty directory: rmdir (no -r). If non-empty, recurse via find +
    # per-file rm so we never invoke `rm -r`.
    find "$orphan" -type f -print0 | while IFS= read -r -d '' f; do
      rm -- "$f"
    done
    # Now remove now-empty subdirs depth-first.
    find "$orphan" -depth -type d -empty -exec rmdir {} \;
  fi
done

# Verify clean.
DIFF_OUT=$(diff -rq "$SRC/" "$DST/" 2>&1)
if [ -n "$DIFF_OUT" ]; then
  echo "ERROR: mirror not clean after regen:" >&2
  echo "$DIFF_OUT" >&2
  exit 1
fi

echo "Mirror clean: $SRC/ -> $DST/"
exit 0
