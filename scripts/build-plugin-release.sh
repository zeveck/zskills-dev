#!/usr/bin/env bash
# build-plugin-release.sh — W5.5 (D1/D3/D4). Build the prod-stripped plugin
# release tree from the current dev HEAD and materialise it as a LOCAL
# `prod/main` branch + a parallel `prod/<version>` tag. Push is GATED behind
# an explicit `--push` flag (NOT passed during plan runs / dry runs).
#
# Modelled on scripts/build-prod.sh, with these differences:
#   - Builds into a TEMP staging tree (git archive | tar -x), never the dev
#     working tree. The dev commit is NOT modified (per Phase 5 Design &
#     Constraints "Does NOT modify the dev commit").
#   - NO SELF-DELETION BUG: the `find … -name 'build-*.sh' -delete` strip runs
#     against the STAGING tree, not against scripts/ where THIS running script
#     lives. The running script's own path is never a deletion target.
#   - Version-bump-before-branch ordering: the plugin.json `version` is set in
#     the staging tree to <version> BEFORE the prod commit is built, so the
#     marketplace version-resolution (research §11) sees the bumped value and
#     never falls back to the commit SHA.
#   - D3: copies repo-root CLAUDE_TEMPLATE.md → ${PLUGIN_TREE}/CLAUDE_TEMPLATE.md
#     (the fallback template path for installed-plugin consumers; the plugin
#     CANNOT load a plugin-root CLAUDE.md as context — research §12 — so the
#     SessionStart materialiser renders managed.md from this copy).
#   - D4: generates suffixless sibling copies of block-agents.sh.template and
#     block-unsafe-project.sh.template in the staging plugin tree, byte-equal
#     to the .template originals (tests/test-hook-template-sibling.sh gates
#     byte-equality).
#
# Strip set (verified by `git ls-tree -r <prod-ref> | grep -E
# 'CANARY|RELEASING|DEV-QUAL|dev_only|build-.*\.sh|MW-EXAMPLE'` returning 0 hits):
#   - hooks/canary*-bad.sh and CANARY_* plans / top-level CANARY_*.md
#   - RELEASING.md + DEV-QUAL.md (dev-maintainer-only)
#   - build-*.sh scripts (release tooling, not shipped to consumers)
#   - any skill with `dev_only: true` frontmatter (+ its mirror)
#   - any file containing the MW-EXAMPLE marker (dev-only worked examples)
#   - README prod-strip:start…end blocks
#
# Usage:
#   build-plugin-release.sh [--version YYYY.MM.N] [--push]
#
#   --version   Release version. Default: the `version` field already in
#               .claude-plugin/plugin.json (set in lockstep by W5.2).
#   --push      Push prod/main + prod/<version> to the `prod` remote. WITHOUT
#               this flag the script only creates LOCAL refs (dry run). The
#               plan run NEVER passes --push — the actual publish is a
#               separate human-gated step.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
[ -n "$PYTHON" ] || { echo "ERROR: install Python 3 (or set ZSKILLS_PYTHON)" >&2; exit 1; }

BOLD='\033[1m'; GREEN='\033[32m'; YELLOW='\033[33m'; DIM='\033[2m'; RESET='\033[0m'
log()  { printf "${BOLD}▸${RESET} %s\n" "$1"; }
warn() { printf "${YELLOW}warn${RESET}: %s\n" "$1"; }
done_() { printf "${GREEN}✓${RESET} %s\n" "$1"; }

# ── Parse args ─────────────────────────────────────────────────────────────
VERSION=""
DO_PUSH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="${2:-}"; shift 2 ;;
    --version=*) VERSION="${1#--version=}"; shift ;;
    --push) DO_PUSH=1; shift ;;
    *) echo "ERROR: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$VERSION" ]; then
  VERSION="$("$PYTHON" -c 'import json;print(json.load(open(".claude-plugin/plugin.json"))["version"])')"
fi
[ -n "$VERSION" ] || { echo "ERROR: could not resolve release version" >&2; exit 1; }
log "Release version: $VERSION (push=$DO_PUSH)"

# ── Dirty-tree precheck ────────────────────────────────────────────────────
if [ -n "$(git status --porcelain)" ]; then
  warn "working tree is dirty — building from the CURRENT HEAD commit (git archive)."
  warn "uncommitted changes are NOT included in the release tree."
fi
HEAD_SHA="$(git rev-parse HEAD)"
log "Building from dev HEAD: $HEAD_SHA"

# ── Staging tree (temp) + trap cleanup ─────────────────────────────────────
STAGE="$(mktemp -d)"
PROD_REF_CREATED=0
cleanup() {
  rm -rf "$STAGE"
}
trap cleanup EXIT

log "Exporting HEAD tree to staging: $STAGE"
git archive --format=tar HEAD | tar -x -C "$STAGE"

# ── 1. Strip README prod-strip blocks ──────────────────────────────────────
strip_markers() {
  local file="$1"
  [ -f "$file" ] || return 0
  if grep -q 'prod-strip:start' "$file"; then
    log "stripping prod-strip block from $(basename "$file")"
    sed -i '/<!-- prod-strip:start -->/,/<!-- prod-strip:end -->/d' "$file"
  fi
}

# Rewrite dev-only URLs (zeveck.github.io/zskills-dev → zskills.synapticnoise.com)
# in the staging markdown so plugin consumers don't get a README pointing at the
# dev Pages site. Mirrors scripts/build-prod.sh's rewrite_dev_urls exactly.
rewrite_dev_urls() {
  local file="$1"
  [ -f "$file" ] || return 0
  if grep -q 'zeveck\.github\.io/zskills-dev' "$file"; then
    log "rewriting dev→prod URLs in $(basename "$file")"
    sed -i 's|zeveck\.github\.io/zskills-dev|zskills.synapticnoise.com|g' "$file"
  fi
}
strip_markers "$STAGE/README.md"
rewrite_dev_urls "$STAGE/README.md"

# ── 2. Remove dev-maintainer-only files (RELEASING.md + DEV-QUAL.md) ────────
log "removing dev-maintainer-only files"
for f in RELEASING.md DEV-QUAL.md; do
  [ -f "$STAGE/$f" ] && { rm -v "$STAGE/$f"; }
done

# ── 3. Remove canary plans + canary fixtures + canary hooks ────────────────
# Canary artifacts are dev-only regression guards (plans, monitor fixtures,
# deliberately-broken hooks). Strip every path whose basename contains
# `CANARY` (matches CANARY_*.md, CANARYNN_*.md, *_CANARY.md, *CANARYA.md, and
# the monitor fixture CANARY42.md) so the strip-verification grep (which
# matches `CANARY` anywhere in the path) sees 0 survivors. The
# canary*-bad.sh hooks use a lowercase `canary` basename, so they get an
# explicit pass below.
log "removing CANARY* plans / fixtures and canary*-bad hooks"
find "$STAGE" -type f -name '*CANARY*' -print -delete || true
# Canary hooks (hooks/canary*-bad.sh — deliberately-broken regression
# fixtures; lowercase basename, not matched by the *CANARY* glob above).
find "$STAGE/hooks" -maxdepth 1 -type f -name 'canary*-bad.sh' -print -delete 2>/dev/null || true

# ── 4. Remove build-*.sh release tooling (SELF-DELETION-SAFE) ───────────────
# This strips build-*.sh from the STAGING tree only. The running script lives
# in $SCRIPT_DIR (the dev scripts/ dir), which is NOT under $STAGE — so this
# can never delete the script that is currently executing.
log "removing build-*.sh release tooling from staging scripts/"
find "$STAGE/scripts" -maxdepth 1 -type f -name 'build-*.sh' -print -delete 2>/dev/null || true

# ── 5. Remove dev_only skills (+ mirrors) and MW-EXAMPLE files ─────────────
log "scanning for dev_only skills"
dev_only_count=0
for skill_file in "$STAGE"/skills/*/SKILL.md "$STAGE"/block-diagram/*/SKILL.md; do
  [ -f "$skill_file" ] || continue
  if awk '
      BEGIN { in_fm = 0 }
      /^---[[:space:]]*$/ { in_fm++; if (in_fm >= 2) exit 1 }
      in_fm == 1 && /^dev_only:[[:space:]]*true[[:space:]]*$/ { exit 0 }
      END { exit 1 }
    ' "$skill_file"; then
    skill_dir="$(dirname "$skill_file")"
    log "removing dev-only skill: ${skill_dir#$STAGE/}"
    rm -rf "$skill_dir"
    mirror_dir="$STAGE/.claude/skills/$(basename "$skill_dir")"
    [ -d "$mirror_dir" ] && rm -rf "$mirror_dir"
    dev_only_count=$((dev_only_count + 1))
  fi
done
[ "$dev_only_count" -eq 0 ] && printf "  ${DIM}(no dev_only: true skills)${RESET}\n"

log "removing MW-EXAMPLE-marked files"
mw_count=0
while IFS= read -r mwfile; do
  [ -n "$mwfile" ] || continue
  rm -f "$mwfile" && mw_count=$((mw_count + 1))
done < <(grep -rl 'MW-EXAMPLE' "$STAGE" 2>/dev/null || true)
[ "$mw_count" -eq 0 ] && printf "  ${DIM}(no MW-EXAMPLE files)${RESET}\n"

# ── 6. Version-bump-before-branch (D1/D10) ─────────────────────────────────
# Set BOTH plugin.json versions in the staging tree to $VERSION before the
# prod commit is built, so marketplace version-resolution sees the bumped
# value (never the commit-SHA fallback, research §11).
log "setting plugin.json version → $VERSION in staging tree (both zs + zsbd)"
for pj in "$STAGE/.claude-plugin/plugin.json" "$STAGE/block-diagram/.claude-plugin/plugin.json"; do
  [ -f "$pj" ] || continue
  VERSION="$VERSION" "$PYTHON" - "$pj" <<'PY'
import json, os, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
data["version"] = os.environ["VERSION"]
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.replace(tmp, path)
PY
done

# ── 7. D3 — copy CLAUDE_TEMPLATE.md into the plugin tree ───────────────────
# The plugin tree root IS $STAGE (the marketplace/plugin repo root). The
# repo-root CLAUDE_TEMPLATE.md is already present in the archive; D3 makes
# explicit that it must survive into the release tree as the fallback the
# SessionStart materialiser renders from. (No-op if already present; the
# explicit copy guards against a future strip rule removing it.)
PLUGIN_TREE="$STAGE"
if [ -f "$PROJECT_ROOT/CLAUDE_TEMPLATE.md" ]; then
  cp "$PROJECT_ROOT/CLAUDE_TEMPLATE.md" "$PLUGIN_TREE/CLAUDE_TEMPLATE.md"
  done_ "D3: CLAUDE_TEMPLATE.md present in plugin tree"
else
  warn "D3: repo-root CLAUDE_TEMPLATE.md not found — skipping copy"
fi

# ── 8. D4 — generate suffixless sibling copies of .template hooks ──────────
log "D4: generating suffixless sibling copies of .template hooks"
shopt -s nullglob
for tmpl in "$PLUGIN_TREE"/hooks/*.sh.template; do
  sibling="${tmpl%.template}"
  cp "$tmpl" "$sibling"
  done_ "D4: $(basename "$sibling") (byte-equal sibling of $(basename "$tmpl"))"
done
shopt -u nullglob

# ── 9. Build the prod commit + LOCAL prod/main + prod/<version> tag ────────
# Use a TEMPORARY git index so the dev working tree / index is never touched.
PROD_INDEX="$(mktemp)"
rm -f "$PROD_INDEX"   # git wants a non-existent path to create a fresh index
export GIT_INDEX_FILE="$PROD_INDEX"
log "staging prod tree into a temporary git index"
git --work-tree="$STAGE" add -A
TRANSFORMED_TREE="$(git write-tree)"
unset GIT_INDEX_FILE
rm -f "$PROD_INDEX"

# Parent: an existing local prod/main if present, else parentless (first cut).
PARENT_ARGS=()
if git rev-parse --verify --quiet refs/heads/prod/main >/dev/null; then
  PARENT_ARGS=(-p "$(git rev-parse refs/heads/prod/main)")
fi
MSG="$(printf 'release: %s\n\nShipped from dev@%s\n' "$VERSION" "$HEAD_SHA")"
PROD_COMMIT="$(printf '%s' "$MSG" | git commit-tree "$TRANSFORMED_TREE" "${PARENT_ARGS[@]}" -F -)"
git update-ref refs/heads/prod/main "$PROD_COMMIT"
git update-ref "refs/tags/prod/$VERSION" "$PROD_COMMIT"
PROD_REF_CREATED=1
done_ "LOCAL prod/main → $PROD_COMMIT"
done_ "LOCAL tag prod/$VERSION → $PROD_COMMIT"

# ── 10. Verify the strip set on the LOCAL prod ref ─────────────────────────
log "verifying strip set on local prod/main"
HITS="$(git ls-tree -r --name-only refs/heads/prod/main | grep -E 'CANARY|RELEASING|DEV-QUAL|dev_only|build-.*\.sh|MW-EXAMPLE' || true)"
if [ -n "$HITS" ]; then
  warn "strip verification FAILED — these forbidden paths survived:"
  printf '%s\n' "$HITS" | sed 's/^/    /'
  exit 1
fi
done_ "strip verification: 0 forbidden paths in prod/main"

# ── 11. Push (GATED behind --push) ─────────────────────────────────────────
if [ "$DO_PUSH" -eq 1 ]; then
  log "pushing prod/main + prod/$VERSION to the prod remote"
  # Push to the SAME refs everything else resolves: marketplace.json's `zs`
  # source.ref is `prod/main`, and the pin-by-version idiom (docs/guides/
  # PLUGIN_INSTALL.md) is `prod/<version>`. The dest refs MUST be `prod/main`
  # (branch) and `prod/$VERSION` (tag), NOT bare `main` / `$VERSION` — pushing
  # to bare refs would leave the marketplace/docs references unresolvable.
  # (tests/test-plugin-ref-consistency.sh guards this consistency.)
  git push prod "refs/heads/prod/main:refs/heads/prod/main"
  git push prod "refs/tags/prod/$VERSION:refs/tags/prod/$VERSION"
  done_ "pushed to prod"
else
  log "--push NOT passed: prod refs are LOCAL only (dry run). Nothing pushed."
  info_local_refs() {
    printf "  local branch: refs/heads/prod/main\n"
    printf "  local tag:    refs/tags/prod/%s\n" "$VERSION"
    printf "  inspect with: git ls-tree -r refs/heads/prod/main\n"
    printf "  clean up with: git update-ref -d refs/heads/prod/main && git update-ref -d refs/tags/prod/%s\n" "$VERSION"
  }
  info_local_refs
fi

done_ "plugin release tree built ($VERSION)"
