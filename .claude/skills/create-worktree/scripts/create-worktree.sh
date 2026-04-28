#!/bin/bash
# create-worktree.sh — Unified worktree creation helper.
#
# Owns: prefix-derived path, optional --branch-name override, optional
# pre-flight prune+fetch+ff-merge (suppressible), worktree-add-safe.sh
# invocation with TOCTOU-race remap, sanitized .zskills-tracked write,
# and optional .worktreepurpose write. Prints the final worktree path
# on stdout (exactly one line). All progress/errors go to stderr.
#
# Usage:
#   bash $(basename "$0") \
#     [--prefix P] [--branch-name REF] [--from B] [--root R] \
#     [--purpose TEXT] [--pipeline-id ID] [--allow-resume] [--no-preflight] \
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

# Print usage on --help (positive-pass invocation signal for Phase 3a AC).
case "${1:-}" in
  -h|--help)
    sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

set -eu

# Same-skill internal resolution — peers (worktree-add-safe.sh,
# sanitize-pipeline-id.sh) live in the same scripts/ directory as this
# script. Symlink invocation is not supported (D18).
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

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
# Same-skill peer (post-Phase-3a) — verifies the skill's mirror is intact.
if [ ! -x "$SCRIPT_DIR/sanitize-pipeline-id.sh" ]; then
  echo "create-worktree: $SCRIPT_DIR/sanitize-pipeline-id.sh missing or not executable (install-integrity)" >&2
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
FROM_BASE=""
ROOT_OVERRIDE=""
PURPOSE=""
PIPELINE_ID_OVERRIDE=""
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
    --pipeline-id)
      [ $# -ge 2 ] || { echo "create-worktree: --pipeline-id requires a value" >&2; exit 5; }
      PIPELINE_ID_OVERRIDE="$2"
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

if [ -z "$PIPELINE_ID_OVERRIDE" ]; then
  echo "create-worktree: --pipeline-id <id> is required" >&2
  echo "  Callers from other skills: pass your skill's canonical pipeline ID" >&2
  echo "    (e.g., run-plan.\$TRACKING_ID, do.\$TASK_SLUG, \$PIPELINE_ID)." >&2
  echo "  Standalone invocations via /create-worktree: the skill wrapper" >&2
  echo "    synthesises create-worktree.\$SLUG when user omits it." >&2
  exit 5
fi

# Slug sanity: reject whitespace or shell metacharacters; we use it verbatim
# in the branch name and path leaf. Allow typical slug characters:
# [A-Za-z0-9._-].
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
# CWD-invariance (Design): relative paths in --root/--prefix must resolve
# against MAIN_ROOT, not the caller's CWD — the same invocation must yield
# the same absolute path whether run from MAIN_ROOT, a subdirectory, or a
# nested worktree. Absolute paths are unaffected.
WT_PATH=$(cd "$MAIN_ROOT" && realpath -m "$RAW_PATH")

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
# WI 1a.7 — BASE resolution.
# Precedence:
#   1. Explicit --from <ref>      → use it.
#   2. --no-preflight && no --from → MAIN_ROOT's current branch (detached
#      HEAD falls back to the commit SHA). Closes the Gate A regression
#      where the flag's docstring promised "branch from user's HEAD"
#      but the implementation still hardcoded BASE=main.
#   3. Otherwise                   → "main" (PR-mode / integration default).
# ──────────────────────────────────────────────────────────────────
if [ -n "$FROM_BASE" ]; then
  BASE="$FROM_BASE"
elif [ "$NO_PREFLIGHT" -eq 1 ]; then
  BASE=$(git -C "$MAIN_ROOT" symbolic-ref --short HEAD 2>/dev/null \
         || git -C "$MAIN_ROOT" rev-parse HEAD 2>/dev/null || true)
  if [ -z "$BASE" ]; then
    echo "create-worktree: --no-preflight could not resolve MAIN_ROOT HEAD for base branch" >&2
    exit 5
  fi
else
  BASE="main"
fi

# Pre-flight (skipped iff --no-preflight).
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
    bash "$SCRIPT_DIR/worktree-add-safe.sh" "$BRANCH" "$WT_PATH" "$BASE" 1>&2 \
    || WAS_RC=$?
else
  bash "$SCRIPT_DIR/worktree-add-safe.sh" "$BRANCH" "$WT_PATH" "$BASE" 1>&2 \
    || WAS_RC=$?
fi

# ──────────────────────────────────────────────────────────────────
# WI 1a.9 — TOCTOU remap (R2-H3). Keeps worktree-add-safe.sh pristine.
# In the concurrent same-slug race (test case 18) the losing process
# may fail with a git "branch already exists / cannot lock ref" error
# (rc=128/255) BEFORE the winner has materialized $WT_PATH. Detect
# the race by the branch now being attached to some worktree — that
# is the definitive "another agent claimed this slug" signal.
# ──────────────────────────────────────────────────────────────────
if [ "$WAS_RC" -ne 0 ] && [ "$WAS_RC" -ne 2 ]; then
  # Path materialized: the winning process has (at least partially)
  # created the worktree directory. Definitive race signal.
  BRANCH_ATTACHED=0
  BRANCH_MATERIALIZED=0
  if git -C "$MAIN_ROOT" worktree list --porcelain 2>/dev/null \
       | grep -qE "^branch refs/heads/${BRANCH}$"; then
    BRANCH_ATTACHED=1
  fi
  # Narrow window: the winner has created the branch REF but not yet
  # registered its worktree. Detect via rev-parse on the local ref.
  # Only treat as race evidence when worktree-add-safe.sh had not
  # classified the existing branch (i.e., rc was NOT 3/4/5) — those
  # codes come from the pre-existing-branch classifier, not a race.
  case "$WAS_RC" in
    3|4|5) : ;;
    *)
      if git -C "$MAIN_ROOT" rev-parse --verify --quiet "refs/heads/${BRANCH}" >/dev/null 2>&1; then
        BRANCH_MATERIALIZED=1
      fi
      ;;
  esac
  if [ -d "$WT_PATH" ] || [ "$BRANCH_ATTACHED" -eq 1 ] || [ "$BRANCH_MATERIALIZED" -eq 1 ]; then
    echo "create-worktree: path/branch materialized mid-flight; remapping rc=$WAS_RC to rc=2" >&2
    WAS_RC=2
  fi
fi
if [ "$WAS_RC" -ne 0 ]; then exit "$WAS_RC"; fi

# ──────────────────────────────────────────────────────────────────
# WI 1a.10 — Post-create write: sanitise the explicit --pipeline-id value
# and write it to .zskills-tracked. The flag is validated required at
# argument-parse time (see top of script); we sanitise again here so an
# already-clean ID is a no-op but a caller passing a dirty string still
# produces a safe value.
# ──────────────────────────────────────────────────────────────────
PIPELINE_ID=$(bash "$SCRIPT_DIR/sanitize-pipeline-id.sh" "$PIPELINE_ID_OVERRIDE")

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
