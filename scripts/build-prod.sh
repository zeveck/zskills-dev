#!/bin/bash
# build-prod.sh — Strip dev-only artifacts from the working tree in
# preparation for shipping to zskills-prod. Runs in CI against a fresh
# zskills-dev checkout; modifies the working tree but does NOT commit.
# The caller (the ship-to-prod workflow) is responsible for writing the
# tree into prod afterwards.
#
# What it strips:
#   1. `<!-- prod-strip:start --> … <!-- prod-strip:end -->` blocks from
#      README.md — the dev-repo warning banner and ship-to-prod badge.
#      (Same marker pattern can be added to any other markdown file later.)
#   2. `plans/CANARY_*.md` and any top-level `CANARY_*.md` — canaries are
#      regression guards for zskills-dev internals; prod consumers don't
#      need them.
#   3. Any skill directory whose `SKILL.md` front-matter contains
#      `dev_only: true` — skills we keep in dev but don't distribute.
#      Strips both `skills/<name>/` and any mirrored `.claude/skills/<name>/`.
#
# Running against an already-stripped tree should be a no-op (idempotent).
# Intended to grow: add transforms here as the dev/prod split widens.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

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

strip_markers README.md

# ─── 1b. Remove dev-maintainer-only files wholesale ────────────────────
# RELEASING.md is entirely dev-maintainer-only (PAT setup, workflow
# internals); shipping it to prod would publish an empty file (since its
# whole content is inside prod-strip markers) and clutter the prod tree.
log "removing dev-maintainer-only files"
for f in RELEASING.md; do
  if [ -f "$f" ]; then
    rm -v "$f"
  else
    printf "  ${DIM}(no $f)${RESET}\n"
  fi
done

# ─── 2. Remove canary plans ────────────────────────────────────────────
log "removing CANARY_* plans"
shopt -s nullglob
canaries=( plans/CANARY_*.md CANARY_*.md )
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
for skill_file in skills/*/SKILL.md block-diagram/skills/*/SKILL.md; do
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

done_ "prod tree built"
