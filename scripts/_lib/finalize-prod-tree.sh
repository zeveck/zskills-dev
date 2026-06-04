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
#      - CANARY-named plans / fixtures ANYWHERE in the tree (recursive) — the
#        prod consumer doesn't need zskills-dev's regression guards. Unified
#        HERE (#1002) so build-prod.sh and build-plugin-release.sh strip the
#        IDENTICAL set; previously build-prod.sh stripped only top-level
#        $PLANS/CANARY_*.md + CANARY_*.md while build-plugin-release.sh used a
#        recursive find, so docs/plans/archive/canaries/*.md shipped via one
#        builder but not the other.
#   3. Dev→prod URL rewrite (#1002) — a TREE WALK over docs/skills/README.md/
#      CHANGELOG.md (.md/.html/.js/.json), run AFTER all strip steps, that
#      swaps zeveck.github.io/zskills-dev → zskills.synapticnoise.com via an
#      idempotent (grep-guarded) sed. Previously each builder carried its OWN
#      copy of rewrite_dev_urls and invoked it on README.md ALONE, so a live
#      dashboard href, skill issue-filing prose, and a demo URL all shipped to
#      prod pointing at the dev Pages site. Sharing the definition + walking
#      the tree closes that (the rewrite_dev_urls helper is also exported for
#      the function unit test, tests/test-build-rewrite-dev-urls.sh).
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

# rewrite_dev_urls <file>
#
# Idempotently swap the dev-only URLs for their prod equivalents in a SINGLE
# file. Two distinct dev→prod mappings (#1002), applied in this order:
#
#   1. Dev Pages site  zeveck.github.io/zskills-dev → zskills.synapticnoise.com
#   2. Dev GitHub repo github.com/zeveck/zskills-dev → github.com/zeveck/zskills
#
# Mapping #1 runs FIRST because both share the `zeveck` / `zskills-dev` tokens;
# the Pages host is the more specific pattern and is rewritten before the repo
# pattern so neither double-fires on the other's output. The grep-q guard makes
# the whole call a no-op (NO sed -i write) for files carrying NEITHER form, so
# it is safe to walk over the whole tree and re-run on an already-rewritten
# tree. Defined at file scope (not nested) so the function unit test
# (tests/test-build-rewrite-dev-urls.sh) can source this lib and call it
# directly. The two build scripts no longer define their own copies — they
# call THIS one, so the rewrite set can never diverge (#1002).
rewrite_dev_urls() {
  local file="$1"
  [ -f "$file" ] || return 0
  # Allow-list escape hatch: a file that intentionally NAMES the dev URL in a
  # genuinely prose-only context (e.g. CHANGELOG.md describing this very
  # rewrite, where mechanically swapping the literal would mangle the entry to
  # "X → X") carries a `zskills-dev-url-allow` marker and is left untouched.
  # The coverage test (tests/test-prod-tree-no-dev-urls.sh) honors the same
  # marker, so an allow-listed file is excused from BOTH the rewrite and the
  # 0-hit assertion.
  if grep -q 'zskills-dev-url-allow' "$file"; then
    return 0
  fi
  if grep -qE 'zeveck\.github\.io/zskills-dev|github\.com/zeveck/zskills-dev' "$file"; then
    sed -i \
      -e 's|zeveck\.github\.io/zskills-dev|zskills.synapticnoise.com|g' \
      -e 's|github\.com/zeveck/zskills-dev|github.com/zeveck/zskills|g' \
      "$file"
  fi
}

# rewrite_marketplace_repo <marketplace-json-path>
#
# Translate the DEV marketplace manifest to its PROD form on publish. The dev
# repo's .claude-plugin/marketplace.json self-references the dev repo so that
# pre-publish plugin qual uses the genuine consumer flow
# (`/plugin marketplace add zeveck/zskills-dev` + `/plugin install zs@zskills`).
# On publish the prod tree must instead point consumers at the prod repo, so
# this function rewrites ONLY the `zs` plugin's `source.repo` field from
# `zeveck/zskills-dev` back to `zeveck/zskills`. This is the bare-SLUG analog of
# rewrite_dev_urls (which only matches URL forms `github.com/...`); the
# marketplace manifest carries the bare slug `"repo": "zeveck/zskills-dev"`,
# which the URL-anchored regex would never touch.
#
# A field-scoped Python json load/mutate/dump is used (NOT a blanket sed across
# the file) so `ref`, `source.source`, the `zsbd` `./block-diagram` source, the
# marketplace `name`/`version`/`$schema`, and key ordering survive intact — a
# clean round-trip that changes ONLY that one value. Idempotent: a no-op when
# the file is already prod-pointing (or has no `zs` github source). Defined at
# file scope so the function unit test
# (tests/test-build-rewrite-marketplace-repo.sh) can source this lib and call
# it directly, exactly as tests/test-build-rewrite-dev-urls.sh does with
# rewrite_dev_urls.
rewrite_marketplace_repo() {
  local file="$1"
  [ -f "$file" ] || return 0
  local PYTHON
  PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
  [ -n "$PYTHON" ] || { echo "ERROR: install Python 3 (or set ZSKILLS_PYTHON)" >&2; return 1; }
  "$PYTHON" - "$file" <<'PY'
import json, sys

path = sys.argv[1]
DEV = "zeveck/zskills-dev"
PROD = "zeveck/zskills"

with open(path) as f:
    mp = json.load(f)

changed = False
for p in mp.get("plugins", []):
    if not isinstance(p, dict) or p.get("name") != "zs":
        continue
    src = p.get("source")
    if isinstance(src, dict) and src.get("source") == "github" and src.get("repo") == DEV:
        src["repo"] = PROD
        changed = True

if changed:
    with open(path, "w") as f:
        json.dump(mp, f, indent=2, ensure_ascii=False)
        f.write("\n")
PY
}

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

  # CANARY-named plans / fixtures, ANYWHERE in the tree (recursive). Unified
  # here (#1002) so both publishers strip the IDENTICAL set — build-prod.sh
  # previously stripped only top-level $PLANS/CANARY_*.md + CANARY_*.md, so
  # docs/plans/archive/canaries/*.md shipped via build-prod but were stripped
  # by build-plugin-release.sh. Matches any path whose basename contains
  # `CANARY` (CANARY_*.md, CANARYNN_*.md, *_CANARY.md, the monitor fixture
  # CANARY42.md, …). The deliberately-broken canary*-bad.sh hooks use a
  # lowercase basename and are stripped by the explicit rule above.
  _fpt_log "stripping CANARY*-named plans / fixtures from $tree (recursive)"
  find "$tree" -type f -name '*CANARY*' -print -delete 2>/dev/null || true

  # ── 3. Dev→prod URL rewrite (#1002) — TREE WALK, run AFTER all strips ─────
  # Walk docs/, skills/, README.md, CHANGELOG.md AND the .claude/ legacy-lane
  # mirror (.md/.html/.js/.json) and rewrite every dev Pages/repo URL to the
  # prod equivalent. The .claude/ mirror is included because the prod tree
  # ships it for the /update-zskills lane, so its copies of run-plan/SKILL.md
  # and the dashboard index.html would otherwise carry the dev URLs even after
  # the source copies are rewritten. Run LAST so files about to be deleted by
  # the strip steps above are never processed. rewrite_dev_urls is idempotent
  # (grep-guarded) and honors the `zskills-dev-url-allow` marker, so files
  # without a dev URL — or allow-listed prose like CHANGELOG.md — are untouched.
  _fpt_log "rewriting dev→prod URLs across $tree (docs, skills, .claude mirror, README, CHANGELOG)"
  local _f
  while IFS= read -r -d '' _f; do
    rewrite_dev_urls "$_f"
  done < <(cd "$tree" && find docs skills .claude README.md CHANGELOG.md \
                \( -name '*.md' -o -name '*.html' -o -name '*.js' -o -name '*.json' \) \
                -type f -print0 2>/dev/null | while IFS= read -r -d '' rel; do printf '%s\0' "$tree/$rel"; done)

  # ── 4. Marketplace dev→prod repo rewrite (self-reference translation) ─────
  # The dev manifest's `zs` source.repo self-references zeveck/zskills-dev so
  # pre-publish plugin qual uses the genuine consumer flow. On publish the prod
  # tree must point consumers at zeveck/zskills. .claude-plugin/ is NOT in the
  # tree-walk above (find docs skills .claude README.md CHANGELOG.md), so invoke
  # the field-scoped rewrite explicitly on the manifest (guard for existence).
  local _mp="$tree/.claude-plugin/marketplace.json"
  if [ -f "$_mp" ]; then
    _fpt_log "rewriting marketplace zs source.repo dev→prod in $_mp"
    rewrite_marketplace_repo "$_mp"
    # Residue invariant (safety guard): the published marketplace manifest must
    # carry ZERO `zskills-dev` — a BARE substring match (NOT the URL-anchored
    # regex the dev-URL checks use; the bare slug would slip past a
    # `github.com/...` regex). build-prod.sh runs `set -euo pipefail`, so this
    # non-zero return aborts the publish before any push.
    if grep -q 'zskills-dev' "$_mp"; then
      echo "finalize_prod_tree: ERROR — prod marketplace manifest still contains 'zskills-dev': $_mp" >&2
      return 1
    fi
    _fpt_done "marketplace zs source.repo is prod-pointing (0 zskills-dev residue)"
  fi

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
