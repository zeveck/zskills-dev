#!/bin/bash
# build-prod.sh — THE prod publisher. The "🚀 Ship to Prod" button
# (.github/workflows/ship-to-prod.yml) runs THIS script against a fresh
# zskills-dev checkout, then pushes the resulting tree to prod `main` +
# a bare `<version>` tag. This is the SINGLE publish path for BOTH the
# legacy `/update-zskills` lane and the plugin lane — the published prod
# tree is a complete, plugin-installable tree (it keeps the plugin
# manifests AND, via the shared finalizer below, the D4 suffixless hook
# siblings the plugin's hooks.json registers). It modifies the working
# tree but does NOT commit; the workflow writes the tree into prod after.
#
# (scripts/build-plugin-release.sh is NOT the publish path — it is a local
# dogfood / prod-tree builder and the source of the D4/strip test fixtures.)
#
# What it strips:
#   1. `<!-- prod-strip:start --> … <!-- prod-strip:end -->` blocks from
#      README.md — the dev-repo warning banner and ship-to-prod badge.
#      (Same marker pattern can be added to any other markdown file later.)
#   1b. Rewrite dev-only URLs (zeveck.github.io/zskills-dev →
#      zskills.synapticnoise.com) in README.md so the dev README points at
#      the dev Pages site while the prod README ships with the prod URL.
#      (Same per-file pattern can be added to any other markdown file later.)
#   2. `plans/CANARY_*.md` and any top-level `CANARY_*.md` — canaries are
#      regression guards for zskills-dev internals; prod consumers don't
#      need them.
#   3. RELEASING.md + DEV-QUAL.md — dev-maintainer-only.
#   4. Any skill directory whose `SKILL.md` front-matter contains
#      `dev_only: true` — skills we keep in dev but don't distribute.
#      Strips both `skills/<name>/` and any mirrored `.claude/skills/<name>/`.
#   5. The SHARED plugin-completion + dev-only strip set (via
#      scripts/_lib/finalize-prod-tree.sh, also called by
#      build-plugin-release.sh so the two builders can never diverge):
#        - D4 suffixless hook siblings (block-agents.sh,
#          block-unsafe-project.sh) GENERATED so the plugin's safety hooks
#          actually exist for consumers;
#        - build-*.sh release/dogfood tooling STRIPPED;
#        - hooks/canary*-bad.sh fixtures STRIPPED;
#        - MW-EXAMPLE-marked files STRIPPED.
#
# Running against an already-stripped tree should be a no-op (idempotent).
# Intended to grow: add transforms here as the dev/prod split widens.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# Source the path-config helper so canary glob uses $ZSKILLS_PLANS_DIR
# instead of a hardcoded `plans/` literal. The helper itself fails loud
# on missing project root.
ZSKILLS_PATHS_ROOT="$PROJECT_ROOT"
source "$PROJECT_ROOT/.claude/skills/update-zskills/scripts/zskills-paths.sh"

# Shared prod-tree finalizer (D4 hook siblings + dev-only strip set). The
# SAME helper is sourced by build-plugin-release.sh, so the two builders
# cannot diverge on what makes the prod tree a complete plugin.
source "$SCRIPT_DIR/_lib/finalize-prod-tree.sh"

BOLD='\033[1m'
GREEN='\033[32m'
YELLOW='\033[33m'
DIM='\033[2m'
RESET='\033[0m'

log()  { printf "${BOLD}▸${RESET} %s\n" "$1"; }
warn() { printf "${YELLOW}warn${RESET}: %s\n" "$1"; }
done_() { printf "${GREEN}✓${RESET} %s\n" "$1"; }

# ─── 1. Strip prod-strip blocks from markdown ──────────────────────────
strip_markers() {
  local file="$1"
  [ -f "$file" ] || return 0
  if grep -q 'prod-strip:start' "$file"; then
    log "stripping prod-strip block from $file"
    sed -i '/<!-- prod-strip:start -->/,/<!-- prod-strip:end -->/d' "$file"
  else
    printf "  ${DIM}(no markers in $file)${RESET}\n"
  fi
}

rewrite_dev_urls() {
  local file="$1"
  [ -f "$file" ] || return 0
  if grep -q 'zeveck\.github\.io/zskills-dev' "$file"; then
    log "rewriting dev→prod URLs in $file"
    sed -i 's|zeveck\.github\.io/zskills-dev|zskills.synapticnoise.com|g' "$file"
  else
    printf "  ${DIM}(no dev urls in $file)${RESET}\n"
  fi
}

strip_markers README.md
rewrite_dev_urls README.md

# ─── 1b. Remove dev-maintainer-only files wholesale ────────────────────
# RELEASING.md and DEV-QUAL.md are entirely dev-maintainer-only (PAT setup,
# workflow internals; the manual-acceptance dev-quality checklist); shipping
# them to prod would publish empty files (their whole content is inside
# prod-strip markers) and clutter the prod tree.
log "removing dev-maintainer-only files"
for f in RELEASING.md DEV-QUAL.md; do
  if [ -f "$f" ]; then
    rm -v "$f"
  else
    printf "  ${DIM}(no $f)${RESET}\n"
  fi
done

# ─── 2. Remove canary plans ────────────────────────────────────────────
log "removing CANARY_* plans"
shopt -s nullglob
canaries=( "$ZSKILLS_PLANS_DIR"/CANARY_*.md CANARY_*.md )
if [ "${#canaries[@]}" -eq 0 ]; then
  printf "  ${DIM}(none found)${RESET}\n"
else
  for f in "${canaries[@]}"; do
    rm -v "$f"
  done
fi
shopt -u nullglob

# ─── 3. Remove dev-only skills (front-matter `dev_only: true`) ─────────
log "scanning for dev_only skills"
dev_only_count=0
for skill_file in skills/*/SKILL.md block-diagram/*/SKILL.md; do
  [ -f "$skill_file" ] || continue
  # Check the front-matter (top of file between the first two `---` lines)
  # for an exact `dev_only: true` key. awk is sufficient and dependency-free.
  if awk '
      BEGIN { in_fm = 0 }
      /^---[[:space:]]*$/ { in_fm++; if (in_fm >= 2) exit 1 }
      in_fm == 1 && /^dev_only:[[:space:]]*true[[:space:]]*$/ { exit 0 }
      END { exit 1 }
    ' "$skill_file"; then
    skill_dir=$(dirname "$skill_file")
    log "removing dev-only skill: $skill_dir"
    rm -rf "$skill_dir"
    # Mirror cleanup: any installed copy under .claude/skills/ with the same name
    mirror_dir=".claude/skills/$(basename "$skill_dir")"
    if [ -d "$mirror_dir" ]; then
      rm -rf "$mirror_dir"
      printf "  also removed mirror: %s\n" "$mirror_dir"
    fi
    dev_only_count=$((dev_only_count + 1))
  fi
done
if [ "$dev_only_count" -eq 0 ]; then
  printf "  ${DIM}(no dev_only: true skills found)${RESET}\n"
fi

# ─── 4. Shared plugin-completion + dev-only strip set ──────────────────────
# Generate the D4 suffixless hook siblings (so the plugin's safety hooks
# actually exist for consumers) and strip the shared dev-only set
# (build-*.sh, hooks/canary*-bad.sh, MW-EXAMPLE files). Operates IN-PLACE on
# the working tree ($PROJECT_ROOT). NOTE: this deletes build-*.sh — INCLUDING
# this running script — from the prod tree; that is intentional (release
# tooling must not ship to consumers, and the ship-to-prod workflow's
# `git add -A` would otherwise re-commit it). bash has already fully read
# this script by now, so its on-disk removal mid-run is safe.
finalize_prod_tree "$PROJECT_ROOT"

done_ "prod tree built"
