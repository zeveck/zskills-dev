#!/usr/bin/env bash
# dogfood-plugin-install.sh — autonomous, repeatable plugin-install dogfood.
#
# PURPOSE
#   Exercise a REAL `claude plugin install` of the `zs` plugin end-to-end,
#   from a throwaway marketplace pointing at the public dev repo, leaving
#   ZERO cruft in the real ~/.claude. The whole run is sandboxed under an
#   isolated HOME (= CLAUDE_CONFIG_DIR) in /tmp, which is recursively removed
#   on exit. This is the install-lane half of plugin dogfooding (issue #960).
#
# WHAT THIS PROVES (and what it does NOT)
#   PROVES — the marketplace-resolution + clone + cache layer:
#     • `claude plugin marketplace add` resolves the throwaway manifest;
#     • `claude plugin install zs@zskills` clones the dev repo at the chosen
#       ref and caches the FULL plugin tree under the config root's
#       plugins/cache/zskills/zs/<version>/ (the config root is the isolated
#       CLAUDE_CONFIG_DIR for this run);
#     • the cached tree contains the load-bearing artifacts (plugin.json,
#       hooks/hooks.json, the skills dir, the SessionStart materialiser, and
#       the lane-portable config resolver).
#   Also exercises the prod-stripped BUILD (scripts/build-plugin-release.sh)
#   inside a throwaway clone, so the strip/build half is validated too.
#
#   DOES NOT PROVE — RUNTIME resolution. "Installed" is necessary, not
#   sufficient. This script does NOT exercise skills resolving under
#   ${CLAUDE_PLUGIN_ROOT}, hooks actually firing, `/zs:` slash dispatch, or
#   the SessionStart materialiser writing the 5 consumer artifacts. Those need
#   a real AUTHED `claude` session (interactive / headless `claude -p` both
#   require login). The complementary BEHAVIOR test is
#   `claude --plugin-dir <built-tree>` run from a CLEAN, mirror-less consumer
#   dir (NOT the mirrored dev repo, which would reproduce the "dogfood-mask").
#   See RELEASING.md "## Dogfooding lanes" for that half.
#
# TEARDOWN
#   The isolated dir is a /tmp/zskills-dogfood-* path. On EXIT (success OR
#   error, unless --keep) the script performs a recursive-remove of it. That
#   is explicitly fence-permitted (block-unsafe-generic.sh allows contained
#   cleanup under a literal /tmp/<name> path). The fence matches raw command
#   TEXT, so this script deliberately NEVER prints/echoes the literal
#   recursive-remove command string — it would self-block the fence. The
#   teardown lives in code only; in prose we call it "recursive-remove".
#
# USAGE
#   scripts/dogfood-plugin-install.sh [--ref <branch>] [--keep] [-h|--help]
#
#   --ref <branch>   Public-remote branch the install pulls from. Default:
#                    `main` (env: ZSKILLS_DOGFOOD_REF). The install pulls from
#                    the PUBLIC https://github.com/zeveck/zskills-dev.git at
#                    this ref, so the branch MUST already be pushed there to
#                    reflect non-main work.
#   --keep           Skip teardown; leave the isolated /tmp dir for inspection
#                    and print its path (env: ZSKILLS_DOGFOOD_KEEP=1).
#   -h, --help       Show this usage and exit.
#
#   Env overrides:
#     ZSKILLS_DOGFOOD_REF   — same as --ref.
#     ZSKILLS_DOGFOOD_KEEP  — set to 1 for --keep.
#     ZSKILLS_DOGFOOD_REPO  — override the public dev repo URL.
#     ZSKILLS_PYTHON        — override the Python 3 interpreter.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
[ -n "$PYTHON" ] || { echo "ERROR: install Python 3 (or set ZSKILLS_PYTHON)" >&2; exit 1; }

BOLD='\033[1m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'; DIM='\033[2m'; RESET='\033[0m'
log()  { printf "${BOLD}▸${RESET} %s\n" "$1"; }
warn() { printf "${YELLOW}warn${RESET}: %s\n" "$1"; }
err()  { printf "${RED}✗${RESET} %s\n" "$1" >&2; }
done_() { printf "${GREEN}✓${RESET} %s\n" "$1"; }

# ── Parse args ─────────────────────────────────────────────────────────────
REF="${ZSKILLS_DOGFOOD_REF:-main}"
KEEP=0
[ "${ZSKILLS_DOGFOOD_KEEP:-0}" = "1" ] && KEEP=1
REPO_URL="${ZSKILLS_DOGFOOD_REPO:-https://github.com/zeveck/zskills-dev.git}"

usage() {
  sed -n '2,/^set -euo pipefail/p' "${BASH_SOURCE[0]}" | sed '$d;s/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --ref) REF="${2:-}"; shift 2 ;;
    --ref=*) REF="${1#--ref=}"; shift ;;
    --keep) KEEP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[ -n "$REF" ] || { echo "ERROR: --ref requires a value" >&2; exit 2; }

# ── claude CLI detection (CI runners lack it → SKIP, not fail) ──────────────
if ! command -v claude >/dev/null 2>&1; then
  warn "claude CLI not on PATH — SKIPPING plugin-install dogfood (CI-runner safe)."
  echo "SKIP: install the claude CLI to exercise the install dogfood."
  exit 0
fi

# ── Isolated HOME / CLAUDE_CONFIG_DIR under /tmp ───────────────────────────
ISO_DIR="$(mktemp -d /tmp/zskills-dogfood-XXXXXX)"
export HOME="$ISO_DIR"
export CLAUDE_CONFIG_DIR="$ISO_DIR"
LOG_DIR="$ISO_DIR/logs"
mkdir -p "$LOG_DIR"

# shellcheck disable=SC2317  # invoked indirectly via the EXIT trap
teardown() {
  local rc=$?
  if [ "$KEEP" = "1" ]; then
    printf "${DIM}--keep: leaving isolated dir for inspection: %s${RESET}\n" "$ISO_DIR"
    return "$rc"
  fi
  # Defensive guard: only ever remove a path under /tmp/zskills-dogfood-*.
  case "$ISO_DIR" in
    /tmp/zskills-dogfood-*)
      rm -rf "$ISO_DIR"
      ;;
    *)
      err "refusing to remove unexpected path: $ISO_DIR"
      ;;
  esac
  return "$rc"
}
trap teardown EXIT

log "Isolated HOME / CLAUDE_CONFIG_DIR: $ISO_DIR"
log "Install ref (public dev repo): $REPO_URL @ $REF"

# ── BUILD: prod-strip build inside a throwaway clone (#844 lesson) ──────────
# build-plugin-release.sh creates LOCAL prod refs via `git commit-tree`, which
# needs a git identity. A fresh clone has none, so we set a CLONE-SCOPED
# identity (never touches the live repo's config). The clone lives under
# ISO_DIR so it is torn down too.
CLONE_DIR="$ISO_DIR/clone"
log "Cloning this repo into the sandbox: $CLONE_DIR"
git clone --quiet "$PROJECT_ROOT" "$CLONE_DIR"
git -C "$CLONE_DIR" config user.email "dogfood@zskills.local"
git -C "$CLONE_DIR" config user.name "zskills dogfood"

log "Running build-plugin-release.sh inside the clone (no --push)"
BUILD_LOG="$LOG_DIR/build.log"
if ( cd "$CLONE_DIR" && bash scripts/build-plugin-release.sh ) >"$BUILD_LOG" 2>&1; then
  done_ "prod-stripped build produced local prod refs in the clone"
else
  err "build-plugin-release.sh failed inside the clone — see log"
  sed 's/^/    /' "$BUILD_LOG" >&2 || true
  exit 1
fi

# ── INSTALL: throwaway marketplace → marketplace add → plugin install ──────
MARKET_DIR="$ISO_DIR/market"
mkdir -p "$MARKET_DIR/.claude-plugin"
log "Building throwaway marketplace.json (single zs url-source entry)"
REF="$REF" REPO_URL="$REPO_URL" "$PYTHON" - "$MARKET_DIR/.claude-plugin/marketplace.json" <<'PY'
import json, os, sys
out = sys.argv[1]
# url source (NOT the `github` shorthand: it clones via git@ SSH and fails in
# a keyless sandbox). Drop the zsbd entry — its relative `./block-diagram`
# source won't resolve from a throwaway dir; install just `zs`. Keep the
# marketplace name `zskills` so `zs@zskills` resolves.
doc = {
    "$schema": "https://anthropic.com/schemas/claude-plugin-marketplace.json",
    "name": "zskills",
    "owner": {"name": "Rich Conlan", "url": "https://github.com/zeveck"},
    "description": "Z Skills — throwaway dogfood marketplace (install-lane only)",
    "version": "1",
    "plugins": [
        {
            "name": "zs",
            "source": {
                "source": "url",
                "url": os.environ["REPO_URL"],
                "ref": os.environ["REF"],
            },
        }
    ],
}
with open(out, "w") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
PY
done_ "throwaway marketplace at $MARKET_DIR"

log "claude plugin marketplace add"
MKT_LOG="$LOG_DIR/marketplace-add.log"
if claude plugin marketplace add "$MARKET_DIR" >"$MKT_LOG" 2>&1; then
  done_ "marketplace registered (isolated)"
else
  err "claude plugin marketplace add failed — see log"
  sed 's/^/    /' "$MKT_LOG" >&2 || true
  exit 1
fi

log "claude plugin install zs@zskills"
INST_LOG="$LOG_DIR/plugin-install.log"
if claude plugin install zs@zskills >"$INST_LOG" 2>&1; then
  done_ "plugin install reported success"
else
  err "claude plugin install zs@zskills failed — see log"
  sed 's/^/    /' "$INST_LOG" >&2 || true
  exit 1
fi

# ── ASSERT: the full tree landed in the ISOLATED cache ─────────────────────
# With CLAUDE_CONFIG_DIR set, the config root IS $ISO_DIR (not $ISO_DIR/.claude),
# so the plugin cache lands under $CLAUDE_CONFIG_DIR/plugins/cache/... — still
# entirely under ISO_DIR in /tmp, never real ~/.claude (verified CLI v2.1.x).
CACHE_BASE="$ISO_DIR/plugins/cache/zskills/zs"
if [ ! -d "$CACHE_BASE" ]; then
  err "expected plugin cache not found under: $CACHE_BASE"
  err "(this is the isolated cache path — real ~/.claude was NOT used)"
  exit 1
fi
# Glob the version dir (there should be exactly one).
VERSION_DIR=""
for d in "$CACHE_BASE"/*/; do
  [ -d "$d" ] || continue
  VERSION_DIR="${d%/}"
  break
done
[ -n "$VERSION_DIR" ] || { err "no version dir under $CACHE_BASE"; exit 1; }
INSTALLED_VERSION="$(basename "$VERSION_DIR")"
log "Installed plugin version: $INSTALLED_VERSION"
log "Cached tree: $VERSION_DIR"

# Required artifacts (relative to the cached plugin tree root). plugin.json
# lives under .claude-plugin/ (the plugin manifest dir), not the tree root.
REQUIRED=(
  ".claude-plugin/plugin.json"
  "hooks/hooks.json"
  "hooks/session-start-materialise.sh"
  "skills/update-zskills/scripts/zskills-resolve-config.sh"
)
MISSING=0
for rel in "${REQUIRED[@]}"; do
  if [ -e "$VERSION_DIR/$rel" ]; then
    done_ "artifact present: $rel"
  else
    err "artifact MISSING: $rel"
    MISSING=$((MISSING + 1))
  fi
done
# skills dir must exist and be non-empty.
if [ -d "$VERSION_DIR/skills" ] && [ -n "$(ls -A "$VERSION_DIR/skills" 2>/dev/null)" ]; then
  done_ "artifact present: skills/ (non-empty)"
else
  err "artifact MISSING or empty: skills/"
  MISSING=$((MISSING + 1))
fi

if [ "$MISSING" -ne 0 ]; then
  err "$MISSING required artifact(s) missing from the cached plugin tree"
  exit 1
fi

# ── VERIFY ISOLATION ───────────────────────────────────────────────────────
# The cache landed under ISO_DIR (asserted above), i.e. under the isolated
# CLAUDE_CONFIG_DIR in /tmp — NOT real ~/.claude. We do NOT diff real
# ~/.claude; per the recipe we confirm isolation by confirming the isolated
# cache exists.
done_ "isolation: cache landed under $ISO_DIR/plugins (real ~/.claude not written by this run)"

# ── PASS summary ───────────────────────────────────────────────────────────
echo ""
printf "${GREEN}${BOLD}PASS${RESET} plugin-install dogfood — version %s installed from %s@%s\n" \
  "$INSTALLED_VERSION" "$REPO_URL" "$REF"
printf "  proved: clone + marketplace-resolution + cache (full tree present)\n"
printf "  ${DIM}NOT proved: runtime \${CLAUDE_PLUGIN_ROOT} resolution / hooks / /zs: dispatch / materialiser${RESET}\n"
printf "  ${DIM}(those need an authed claude session; see RELEASING.md \"Dogfooding lanes\")${RESET}\n"
if [ "$KEEP" = "1" ]; then
  printf "  --keep: isolated dir retained at %s\n" "$ISO_DIR"
fi
exit 0
