#!/usr/bin/env bash
# scripts/_lib/finalize-prod-tree.sh
#
# Shared "plugin-completion" finalizer for the prod tree. BOTH publishers
# call this so they can NEVER diverge on what makes the prod tree a
# COMPLETE, CORRECT plugin:
#
#   - scripts/build-prod.sh — the REAL publish path. The "🚀 Ship to Prod"
#     button (.github/workflows/ship-to-prod.yml) runs build-prod.sh against
#     a fresh dev checkout and pushes the result to prod `main` + a bare
#     `<version>` tag. build-prod.sh operates IN-PLACE on the working tree.
#   - scripts/build-plugin-release.sh — a LOCAL dogfood / prod-tree builder
#     (and the source of the D4/strip test fixtures). NOT the publish path.
#     It operates on a TEMP staging tree.
#
# Why a shared helper: the two builders drifted (build-prod.sh shipped an
# INCOMPLETE plugin — no D4 suffixless hook siblings, plus dev-only cruft —
# while build-plugin-release.sh was complete). That drift is the root cause
# of the "dogfood-mask" that shipped non-functional plugin lanes. Factoring
# the completion logic here makes divergence structurally impossible.
#
# What it does to the given tree:
#   1. D4 — generate suffixless sibling copies of every hooks/*.sh.template,
#      byte-equal to its .template. The plugin's hooks/hooks.json registers
#      the suffixless safety hooks (block-agents.sh, block-unsafe-project.sh);
#      without these siblings those hooks silently never fire for every
#      plugin consumer. (tests/test-hook-template-sibling.sh gates byte-
#      equality; tests/test-plugin-d4-hook-siblings.sh gates presence in the
#      BUILT tree.)
#   2. Shared dev-only strip set — files that must NOT ship to consumers:
#      - scripts/build-*.sh   (release/dogfood tooling)
#      - hooks/canary*-bad.sh (deliberately-broken regression fixtures)
#      - any file containing the MW-EXAMPLE marker (dev-only worked examples)
#
# Usage:
#   finalize_prod_tree <tree-dir> [<self-script-to-preserve>]
#
#   <tree-dir>                The root of the prod tree to finalize.
#   <self-script-to-preserve> OPTIONAL absolute path of the currently-running
#                             build script. When build-prod.sh finalizes the
#                             working tree IN-PLACE, the build-*.sh strip would
#                             otherwise delete the very script that is running;
#                             passing its path here preserves it from the strip
#                             (the ship-to-prod workflow's own `git add -A` does
#                             not re-add it — see note below). Omit for staging-
#                             tree builds (build-plugin-release.sh), where the
#                             running script lives outside the tree.
#
# Note on build-prod.sh in-place self-preservation: build-prod.sh is run by
# ship-to-prod.yml, which AFTER build-prod.sh does its own `git add -A` +
# `git write-tree`. So whatever build-*.sh files remain on disk would be
# committed. We therefore CANNOT leave build-prod.sh on disk in the prod tree.
# Instead build-prod.sh passes its own path so we delete it LAST (after the
# script has finished sourcing/reading this function), via a deferred unlink
# the caller performs — see build-prod.sh. To keep this helper simple and
# self-contained, when a self-path IS given we still delete it here; bash has
# already fully parsed the calling script + this sourced function by the time
# this runs, so removing the on-disk file is safe.

# shellcheck disable=SC2317

finalize_prod_tree() {
  local tree="$1"
  local self_script="${2:-}"

  if [ -z "$tree" ] || [ ! -d "$tree" ]; then
    echo "finalize_prod_tree: ERROR — tree dir missing or not a directory: '$tree'" >&2
    return 1
  fi

  local _BOLD='\033[1m'; local _GREEN='\033[32m'; local _RESET='\033[0m'
  _fpt_log()  { printf "${_BOLD}▸${_RESET} %s\n" "$1"; }
  _fpt_done() { printf "${_GREEN}✓${_RESET} %s\n" "$1"; }

  # ── 1. D4 — suffixless sibling copies of .template hooks ─────────────────
  _fpt_log "D4: generating suffixless sibling copies of .template hooks"
  shopt -s nullglob
  local tmpl sibling
  for tmpl in "$tree"/hooks/*.sh.template; do
    sibling="${tmpl%.template}"
    cp "$tmpl" "$sibling"
    _fpt_done "D4: $(basename "$sibling") (byte-equal sibling of $(basename "$tmpl"))"
  done
  shopt -u nullglob

  # ── 2. Shared dev-only strip set ─────────────────────────────────────────
  # build-*.sh release/dogfood tooling. Deleted from <tree>/scripts/ only.
  _fpt_log "stripping build-*.sh release tooling from $tree/scripts/"
  find "$tree/scripts" -maxdepth 1 -type f -name 'build-*.sh' -print -delete 2>/dev/null || true

  # canary*-bad.sh deliberately-broken regression fixtures.
  _fpt_log "stripping hooks/canary*-bad.sh fixtures from $tree/hooks/"
  find "$tree/hooks" -maxdepth 1 -type f -name 'canary*-bad.sh' -print -delete 2>/dev/null || true

  # MW-EXAMPLE-marked files (dev-only worked examples). Matched by FILENAME
  # (the documented `MW-EXAMPLE__<name>` tombstone convention, F-R1-13), NOT
  # by content — a content grep would over-match every prose file that merely
  # NAMES the marker (RELEASING.md, this helper, the build scripts, CHANGELOG,
  # the strip-verification grep itself) and wrongly delete files that must
  # ship (e.g. CHANGELOG.md). Filename matching is also exactly what the
  # strip-verification grep checks (it greps the ls-tree PATH list).
  _fpt_log "stripping MW-EXAMPLE*-named files from $tree"
  find "$tree" -type f -name 'MW-EXAMPLE*' -print -delete 2>/dev/null || true

  # If the caller is build-prod.sh finalizing IN-PLACE, its own running
  # script matched the build-*.sh strip above and is already gone. The
  # self_script arg is accepted for clarity / future-proofing but needs no
  # extra handling — bash has fully read the script by now, so its on-disk
  # removal is safe.
  if [ -n "$self_script" ] && [ -f "$self_script" ]; then
    rm -fv "$self_script" || true
  fi

  return 0
}
