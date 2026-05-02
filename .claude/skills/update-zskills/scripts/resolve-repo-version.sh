#!/bin/bash
# resolve-repo-version.sh — extract latest YYYY.MM.N tag from zskills source.
# Tag scheme is defined by RELEASING.md:44-46 (zero-indexed YYYY.MM.N).
# If the tag scheme changes (suffixes like `-rc`, prefixes like `v`, etc.),
# update this regex AND tests/test-skill-version-delta.sh together.
# (refine-plan F-R15: surface the cross-file dependency.)
#
# Usage: bash resolve-repo-version.sh <zskills-source-path>
# Stdout: latest matching tag (e.g. "2026.04.0"), or empty if none / not a git repo.
# Exit:   0 in both cases (empty stdout signals "no version").
set -u
ZSKILLS_PATH="${1:-}"
[ -d "$ZSKILLS_PATH/.git" ] || { echo ""; exit 0; }
git -C "$ZSKILLS_PATH" tag --list \
  | grep -E '^[0-9]{4}\.(0[1-9]|1[0-2])\.[0-9]+$' \
  | sort -V | tail -1
