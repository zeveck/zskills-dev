#!/bin/bash
# scripts/create-worktree.sh — Unified worktree creation helper.
#
# Owns: prefix-derived path, optional --branch-name override, optional
# pre-flight prune+fetch+ff-merge (suppressible), worktree-add-safe.sh
# invocation with TOCTOU-race remap, sanitized .zskills-tracked write,
# and optional .worktreepurpose write. Prints the final worktree path
# on stdout (exactly one line). All progress/errors go to stderr.
#
# Usage:
#   bash "$MAIN_ROOT/scripts/create-worktree.sh" \
#     [--prefix P] [--branch-name REF] [--from B] [--root R] \
#     [--purpose TEXT] [--allow-resume] [--no-preflight] \
#     <slug>
#
# Exit codes (see plans/CREATE_WORKTREE_SKILL.md §Design & Constraints):
#   0  Worktree created (fresh, recreated, or resumed)
#   2  Path exists (incl. TOCTOU remap per WI 1a.9)
#   3  Poisoned branch (behind base, 0 ahead)
#   4  Branch ahead of base without --allow-resume
#   5  Input validation (bad slug, slash in --prefix, unknown flag, not in git, install-integrity)
#   6  Pre-flight fetch failed (retryable)
#   7  Pre-flight ff-merge not possible (divergent main)
#   8  Post-create write failed (rolled back)

set -eu

# ──────────────────────────────────────────────────────────────────
# WI 1a.3 — Compute MAIN_ROOT BEFORE any cd. All path resolution
# anchors on MAIN_ROOT. --git-common-dir returns the main repo's
# .git even when invoked from within a nested worktree.
# ──────────────────────────────────────────────────────────────────
MAIN_ROOT_GIT_DIR=$(git rev-parse --git-common-dir 2>/dev/null || true)
if [ -z "$MAIN_ROOT_GIT_DIR" ]; then
  echo "create-worktree: not inside a git repository (git rev-parse --git-common-dir failed)" >&2
  exit 5
fi
MAIN_ROOT=$(cd "$MAIN_ROOT_GIT_DIR/.." && pwd)
if [ -z "$MAIN_ROOT" ] || [ "$MAIN_ROOT" = "/" ]; then
  echo "create-worktree: MAIN_ROOT resolved to empty or '/' — refusing to continue" >&2
  exit 5
fi

# Install-integrity: sanitize-pipeline-id.sh MUST be present and executable (R2-L4).
if [ ! -x "$MAIN_ROOT/scripts/sanitize-pipeline-id.sh" ]; then
  echo "create-worktree: $MAIN_ROOT/scripts/sanitize-pipeline-id.sh missing or not executable (install-integrity)" >&2
  exit 5
fi

PROJECT_NAME=$(basename "$MAIN_ROOT")
if [ -z "$PROJECT_NAME" ]; then
  echo "create-worktree: PROJECT_NAME resolved empty from MAIN_ROOT='$MAIN_ROOT'" >&2
  exit 5
fi

# ──────────────────────────────────────────────────────────────────
# WI 1a.2 — Argument parser (bash-regex flag loop, idiom from
# skills/do/SKILL.md). Flags come in any order; positional <slug>
# is the last non-flag token.
# ──────────────────────────────────────────────────────────────────
PREFIX=""
BRANCH_NAME_OVERRIDE=""
FROM_BASE="main"
ROOT_OVERRIDE=""
PURPOSE=""
ALLOW_RESUME=0
NO_PREFLIGHT=0
SLUG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix)
      [ $# -ge 2 ] || { echo "create-worktree: --prefix requires a value" >&2; exit 5; }
      PREFIX="$2"
      shift 2
      ;;
    --branch-name)
      [ $# -ge 2 ] || { echo "create-worktree: --branch-name requires a value" >&2; exit 5; }
      BRANCH_NAME_OVERRIDE="$2"
      shift 2
      ;;
    --from)
      [ $# -ge 2 ] || { echo "create-worktree: --from requires a value" >&2; exit 5; }
      FROM_BASE="$2"
      shift 2
      ;;
    --root)
      [ $# -ge 2 ] || { echo "create-worktree: --root requires a value" >&2; exit 5; }
      ROOT_OVERRIDE="$2"
      shift 2
      ;;
    --purpose)
      [ $# -ge 2 ] || { echo "create-worktree: --purpose requires a value" >&2; exit 5; }
      PURPOSE="$2"
      shift 2
      ;;
    --allow-resume)
      ALLOW_RESUME=1
      shift
      ;;
    --no-preflight)
      NO_PREFLIGHT=1
      shift
      ;;
    --)
      shift
      # Remaining args are positional
      while [ $# -gt 0 ]; do
        SLUG="$1"
        shift
      done
      ;;
    --*)
      echo "create-worktree: unknown flag '$1'" >&2
      exit 5
      ;;
    *)
      # Positional — last one wins (the slug)
      SLUG="$1"
      shift
      ;;
  esac
done

if [ -z "$SLUG" ]; then
  echo "create-worktree: missing positional <slug>" >&2
  exit 5
fi

# Slug sanity: reject whitespace or shell metacharacters; we use it verbatim
# in the branch name, the path leaf, and the fallback pipeline ID. Allow
# typical slug characters: [A-Za-z0-9._-].
if [[ ! "$SLUG" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "create-worktree: invalid slug '$SLUG' — must match [A-Za-z0-9._-]+" >&2
  exit 5
fi

# Prefix rejects slashes — leaf must be a single directory entry so
# `basename "$WT_PATH"` callers are safe.
if [[ "$PREFIX" == */* ]]; then
  echo "create-worktree: prefix may not contain '/'; use --branch-name to set a slash-bearing branch name independently" >&2
  exit 5
fi

# ──────────────────────────────────────────────────────────────────
# WI 1a.4 — Config reader for execution.worktree_root (bash regex; no jq).
# ──────────────────────────────────────────────────────────────────
CONFIG_FILE="$MAIN_ROOT/.claude/zskills-config.json"
WORKTREE_ROOT="/tmp"
if [ -f "$CONFIG_FILE" ]; then
  # Extract "worktree_root": "VALUE" — permissive of whitespace.
  CFG_LINE=$(grep -m1 '"worktree_root"' "$CONFIG_FILE" 2>/dev/null || true)
  if [ -n "$CFG_LINE" ] && [[ "$CFG_LINE" =~ \"worktree_root\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    WORKTREE_ROOT="${BASH_REMATCH[1]}"
  fi
fi

# ──────────────────────────────────────────────────────────────────
# WI 1a.5 — Apply path template.
#   <slug>                         → ${WORKTREE_ROOT}/${PROJECT_NAME}-${SLUG}
#   --prefix P <slug>              → ${WORKTREE_ROOT}/${PROJECT_NAME}-${P}-${SLUG}
#   --root R <slug>                → ${R}/${SLUG}                (PROJECT_NAME stem skipped)
#   --root R --prefix P <slug>     → ${R}/${P}-${SLUG}           (prefix stays in leaf)
# ──────────────────────────────────────────────────────────────────
if [ -n "$ROOT_OVERRIDE" ]; then
  if [ -n "$PREFIX" ]; then
    RAW_PATH="${ROOT_OVERRIDE}/${PREFIX}-${SLUG}"
  else
    RAW_PATH="${ROOT_OVERRIDE}/${SLUG}"
  fi
else
  if [ -n "$PREFIX" ]; then
    RAW_PATH="${WORKTREE_ROOT}/${PROJECT_NAME}-${PREFIX}-${SLUG}"
  else
    RAW_PATH="${WORKTREE_ROOT}/${PROJECT_NAME}-${SLUG}"
  fi
fi

# Resolve to absolute/canonical form (realpath -m doesn't require existence).
WT_PATH=$(realpath -m "$RAW_PATH")

# ──────────────────────────────────────────────────────────────────
# WI 1a.6 — Branch resolution.
# ──────────────────────────────────────────────────────────────────
if [ -n "$BRANCH_NAME_OVERRIDE" ]; then
  BRANCH="$BRANCH_NAME_OVERRIDE"
elif [ -n "$PREFIX" ]; then
  BRANCH="${PREFIX}-${SLUG}"
else
  BRANCH="wt-${SLUG}"
fi

# Collision guard against literal 'main' (or empty).
if [ -z "$BRANCH" ] || [ "$BRANCH" = "main" ]; then
  echo "create-worktree: refusing to use branch name '$BRANCH' (collides with base); supply --branch-name or a different slug/prefix" >&2
  exit 5
fi

# ──────────────────────────────────────────────────────────────────
# WI 1a.7 — Pre-flight (skipped iff --no-preflight).
# BASE defaults to 'main', overridable via --from.
# ──────────────────────────────────────────────────────────────────
BASE="$FROM_BASE"
if [ "$NO_PREFLIGHT" -eq 0 ]; then
  # git worktree prune — tidy any stale registrations before attempting a fresh add.
  if ! git -C "$MAIN_ROOT" worktree prune 1>&2; then
    echo "create-worktree: 'git worktree prune' failed" >&2
    # Prune failure is unusual but not fatal; treat as install/env issue.
    exit 5
  fi

  # git fetch origin <BASE> — retryable (network). rc!=0 → exit 6.
  if ! git -C "$MAIN_ROOT" fetch origin "$BASE" 1>&2; then
    echo "create-worktree: 'git fetch origin $BASE' failed (retryable)" >&2
    exit 6
  fi

  # git merge --ff-only origin/<BASE> — divergent main → exit 7.
  if ! git -C "$MAIN_ROOT" merge --ff-only "origin/$BASE" 1>&2; then
    echo "create-worktree: 'git merge --ff-only origin/$BASE' failed — divergent base (resolve before creating worktree)" >&2
    exit 7
  fi
fi

# ──────────────────────────────────────────────────────────────────
# WI 1a.8 — Invoke worktree-add-safe.sh. Do NOT exit yet.
# ──────────────────────────────────────────────────────────────────
WAS_RC=0
if [ "$ALLOW_RESUME" -eq 1 ]; then
  ZSKILLS_ALLOW_BRANCH_RESUME=1 \
    bash "$MAIN_ROOT/scripts/worktree-add-safe.sh" "$BRANCH" "$WT_PATH" "$BASE" 1>&2 \
    || WAS_RC=$?
else
  bash "$MAIN_ROOT/scripts/worktree-add-safe.sh" "$BRANCH" "$WT_PATH" "$BASE" 1>&2 \
    || WAS_RC=$?
fi

# ──────────────────────────────────────────────────────────────────
# WI 1a.9 — TOCTOU remap (R2-H3). Keeps worktree-add-safe.sh pristine.
# ──────────────────────────────────────────────────────────────────
if [ "$WAS_RC" -ne 0 ] && [ "$WAS_RC" -ne 2 ] && [ -d "$WT_PATH" ]; then
  echo "create-worktree: path materialized mid-flight; remapping rc=$WAS_RC to rc=2" >&2
  WAS_RC=2
fi
if [ "$WAS_RC" -ne 0 ]; then exit "$WAS_RC"; fi

# ──────────────────────────────────────────────────────────────────
# WI 1a.10 — Post-create writes. Sanitize PIPELINE_ID first; fallback
# includes prefix (R2-L3).
# ──────────────────────────────────────────────────────────────────
FALLBACK_ID="create-worktree"
[ -n "${PREFIX:-}" ] && FALLBACK_ID="${FALLBACK_ID}.${PREFIX}"
FALLBACK_ID="${FALLBACK_ID}.${SLUG}"
RAW_PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-$FALLBACK_ID}"
PIPELINE_ID=$(bash "$MAIN_ROOT/scripts/sanitize-pipeline-id.sh" "$RAW_PIPELINE_ID")

# WI 1a.11 — Rollback on .zskills-tracked write failure.
if ! printf '%s\n' "$PIPELINE_ID" > "$WT_PATH/.zskills-tracked"; then
  echo "create-worktree: post-create write failed — worktree rolled back" >&2
  git -C "$MAIN_ROOT" worktree remove --force "$WT_PATH" 1>&2 || true
  exit 8
fi

if [ -n "$PURPOSE" ]; then
  if ! printf '%s\n' "$PURPOSE" > "$WT_PATH/.worktreepurpose"; then
    echo "create-worktree: post-create write failed — worktree rolled back" >&2
    git -C "$MAIN_ROOT" worktree remove --force "$WT_PATH" 1>&2 || true
    exit 8
  fi
fi

# ──────────────────────────────────────────────────────────────────
# WI 1a.12 — Final stdout: exactly one line with the path.
# ──────────────────────────────────────────────────────────────────
printf '%s\n' "$WT_PATH"
exit 0
