#!/bin/bash
# resolve-repo-version.sh — resolve the zskills repo version from a source clone.
# Resolution order: latest YYYY.MM.N git tag → else the top-level `version`
# field in <path>/.claude-plugin/plugin.json (the `zs` plugin manifest, same
# YYYY.MM.N scheme) → else empty.
#
# Tag scheme is defined by RELEASING.md:44-46 (zero-indexed YYYY.MM.N).
# If the tag scheme changes (suffixes like `-rc`, prefixes like `v`, etc.),
# update this regex AND tests/test-update-zskills-version-surface.sh together
# (that suite exercises resolve-repo-version.sh, incl. the #1124 plugin.json
# fallback). (refine-plan F-R15: surface the cross-file dependency.)
#
# The plugin.json fallback (#1124) covers tagless-but-complete clones —
# shallow clones, never-tagged working copies, plugin-cloned trees without
# tags fetched — where the latest-tag pipeline yields empty even though the
# repo's version IS available in .claude-plugin/plugin.json. Format already
# matches (YYYY.MM.N) so no normalization is needed. Dependency-free: a
# bash-regex extract of the manifest's TOP-LEVEL "version" key (no jq, per
# the repo standard) — anchored to the first match in the manifest head so a
# nested "version" key is never grabbed.
#
# Usage: bash resolve-repo-version.sh <zskills-source-path>
# Stdout: latest matching tag, else plugin.json version (e.g. "2026.06.0"),
#         else empty if neither is available / not a git repo.
# Exit:   0 in all cases (empty stdout signals "no version").
set -u
ZSKILLS_PATH="${1:-}"

# 1) git tag — latest YYYY.MM.N tag in the source clone.
tag=""
if [ -d "$ZSKILLS_PATH/.git" ]; then
  tag=$(git -C "$ZSKILLS_PATH" tag --list \
    | grep -E '^[0-9]{4}\.(0[1-9]|1[0-2])\.[0-9]+$' \
    | sort -V | tail -1)
fi
if [ -n "$tag" ]; then
  echo "$tag"
  exit 0
fi

# 2) plugin.json fallback — top-level `version` from the `zs` plugin manifest
#    at <path>/.claude-plugin/plugin.json. Read only the manifest head so the
#    FIRST "version": "..." match is the top-level key, never a nested one.
manifest="$ZSKILLS_PATH/.claude-plugin/plugin.json"
if [ -f "$manifest" ]; then
  while IFS= read -r line; do
    if [[ "$line" =~ \"version\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
      echo "${BASH_REMATCH[1]}"
      exit 0
    fi
  done < <(head -n 20 "$manifest")
fi

# 3) neither — empty signals "no version".
echo ""
exit 0
