#!/usr/bin/env bash
# ensure-worktree.sh — Gate worktree creation for file-writing skills.
#
# Single shared helper for the worktree preamble. Five consumer skills /
# six invocation sites (draft-plan, refine-plan, draft-tests, fix-report,
# fix-issues sprint+sync) dispatch this BEFORE
# writing any files, so that they uniformly:
#   - honour an explicit --worktree-override (resume-or-redirect),
#   - no-op when already running inside a worktree,
#   - no-op when execution.main_protected is not true,
#   - otherwise create a fresh worktree via the peer create-worktree.sh.
#
# Exit codes: 1-10 reserved for create-worktree.sh; 11-19 reserved for ensure-worktree.sh; 20+ reserved for future helpers.
#
# API contract:
#   stdin:  none
#   stdout: exactly one line — worktree path (non-empty) OR empty string (no-op)
#   stderr: progress/error messages
#   exit 0:  success (worktree created OR no-op)
#   exit 2:  --worktree-override validation failed
#   exit 5:  input validation (bad flag, missing required, not in git repo)
#   exit 11: install-integrity (peer create-worktree.sh missing/not exec)
#   exit N (N in {1, 3, 4, 6, 7, 8, 9, 10}): propagated verbatim from create-worktree.sh
#
# Usage:
#   bash ensure-worktree.sh \
#     --prefix P --pipeline-id ID \
#     [--worktree-override DIR] [--purpose TEXT] [--allow-resume] \
#     <slug>
#
#   Or use --slug <slug> instead of positional.

set -e

# ──────────────────────────────────────────────────────────────────
# Install-integrity check (WI 1.3). Resolve SCRIPT_DIR BEFORE any
# cd, and confirm the peer create-worktree.sh is present and
# executable. Exit 11 with an actionable message on miss.
# ──────────────────────────────────────────────────────────────────
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
if [ ! -x "$SCRIPT_DIR/create-worktree.sh" ]; then
  echo "ensure-worktree: $SCRIPT_DIR/create-worktree.sh missing or not executable (install-integrity); run /update-zskills to repair" >&2
  exit 11
fi

# ──────────────────────────────────────────────────────────────────
# WI 1.2 — Argument parser (bash regex flag loop, idiom from
# create-worktree.sh:87-145). --slug may be positional or via flag.
# ──────────────────────────────────────────────────────────────────
SLUG=""
PREFIX=""
PIPELINE_ID=""
WORKTREE_OVERRIDE=""
PURPOSE=""
ALLOW_RESUME=0

while [ $# -gt 0 ]; do
  case "$1" in
    --slug)
      [ $# -ge 2 ] || { echo "ensure-worktree: --slug requires a value" >&2; exit 5; }
      SLUG="$2"
      shift 2
      ;;
    --prefix)
      [ $# -ge 2 ] || { echo "ensure-worktree: --prefix requires a value" >&2; exit 5; }
      PREFIX="$2"
      shift 2
      ;;
    --pipeline-id)
      [ $# -ge 2 ] || { echo "ensure-worktree: --pipeline-id requires a value" >&2; exit 5; }
      PIPELINE_ID="$2"
      shift 2
      ;;
    --worktree-override)
      [ $# -ge 2 ] || { echo "ensure-worktree: --worktree-override requires a value" >&2; exit 5; }
      WORKTREE_OVERRIDE="$2"
      shift 2
      ;;
    --purpose)
      [ $# -ge 2 ] || { echo "ensure-worktree: --purpose requires a value" >&2; exit 5; }
      PURPOSE="$2"
      shift 2
      ;;
    --allow-resume)
      ALLOW_RESUME=1
      shift
      ;;
    --)
      shift
      while [ $# -gt 0 ]; do
        SLUG="$1"
        shift
      done
      ;;
    --*)
      echo "ensure-worktree: unknown flag '$1'" >&2
      exit 5
      ;;
    *)
      # Positional — last one wins (the slug)
      SLUG="$1"
      shift
      ;;
  esac
done

# ──────────────────────────────────────────────────────────────────
# Up-front validation (exit 5 on failure).
# ──────────────────────────────────────────────────────────────────
MAIN_GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null || true)
if [ -z "$MAIN_GIT_COMMON" ]; then
  echo "ensure-worktree: not inside a git repository (git rev-parse --git-common-dir failed)" >&2
  exit 5
fi

if [ -z "$PREFIX" ]; then
  echo "ensure-worktree: --prefix is required" >&2
  exit 5
fi
if [ -z "$PIPELINE_ID" ]; then
  echo "ensure-worktree: --pipeline-id is required" >&2
  exit 5
fi
if [ -z "$SLUG" ]; then
  echo "ensure-worktree: missing <slug> (provide --slug VALUE or as positional)" >&2
  exit 5
fi

# ──────────────────────────────────────────────────────────────────
# WI 1.5 — In-worktree detection. MAIN_ROOT is the main repo's
# top-level; TOPLEVEL is the current worktree's top-level. They
# differ iff caller is already inside a non-main worktree.
# ──────────────────────────────────────────────────────────────────
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
TOPLEVEL=$(git rev-parse --show-toplevel)

# ──────────────────────────────────────────────────────────────────
# WI 1.6 — --worktree-override validation (4-check pattern,
# symlink-resolved per DA-7). Wins over all other gates if provided.
# ──────────────────────────────────────────────────────────────────
if [ -n "$WORKTREE_OVERRIDE" ]; then
  [ -d "$WORKTREE_OVERRIDE" ] || { echo "ensure-worktree: --worktree-override path does not exist or is not a directory: $WORKTREE_OVERRIDE" >&2; exit 2; }
  OVERRIDE_ABS=$(cd "$WORKTREE_OVERRIDE" && pwd)  # symlink-resolve
  OVERRIDE_COMMON=$(git -C "$OVERRIDE_ABS" rev-parse --git-common-dir 2>/dev/null) || { echo "ensure-worktree: --worktree-override is not a git repo: $WORKTREE_OVERRIDE" >&2; exit 2; }
  # `--git-common-dir` returns a RELATIVE path (".git") when the caller
  # is inside the main repo, but an ABSOLUTE path
  # ("/abs/main/.git") when the caller is inside a linked worktree —
  # which is the common case for a valid `--worktree-override` (a
  # sibling worktree of the same repo). Bash `cd "$prefix/$absolute"`
  # does NOT collapse to `cd "$absolute"`; it tries the literal joined
  # path and fails (Phase 5 canary E/I surfaced this). Branch on
  # leading "/" to handle both forms.
  case "$OVERRIDE_COMMON" in
    /*) OVERRIDE_COMMON_ABS=$(cd "$OVERRIDE_COMMON" && pwd) ;;
    *)  OVERRIDE_COMMON_ABS=$(cd "$OVERRIDE_ABS/$OVERRIDE_COMMON" && pwd) ;;
  esac
  MAIN_COMMON_ABS=$(cd "$(git rev-parse --git-common-dir)" && pwd)
  [ "$OVERRIDE_COMMON_ABS" = "$MAIN_COMMON_ABS" ] || { echo "ensure-worktree: --worktree-override belongs to a different repo" >&2; exit 2; }
  [ "$OVERRIDE_ABS" != "$MAIN_ROOT" ] || { echo "ensure-worktree: --worktree-override cannot be MAIN_ROOT itself" >&2; exit 2; }
  printf '%s\n' "$OVERRIDE_ABS"
  exit 0
fi

# ──────────────────────────────────────────────────────────────────
# WI 1.4 — Config reader. CASCADE v2 (ENFORCEMENT_V2 Phase 4): landing and
# main_protected are now resolved through the canonical lane-portable resolver
# (project > user, with main_protected a RAISE-ONLY floor) instead of an inline
# BASH_REMATCH read. The resolver exports $ZSKILLS_CFG_LANDING (empty when
# unset in both tiers — this helper keeps its own `cherry-pick` default) and
# $ZSKILLS_MAIN_PROTECTED ("true" iff either tier sets it true — giving this
# helper the user-tier floor for free). NO behavior change for project-only
# configs; the only added effect is the user-tier read (per #1159 scope).
# ──────────────────────────────────────────────────────────────────
PROJECT_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
LANDING="cherry-pick"  # default if unset (resolver carries no landing default)
MAIN_PROTECTED="false"
# Resolver source — SIBLING-RELATIVE to this script's own location, which is
# lane-portable by construction: on BOTH lanes the resolver lives at
# <skills-root>/update-zskills/scripts/ and this helper at
# <skills-root>/create-worktree/scripts/, so $SCRIPT_DIR/../../update-zskills/
# resolves to the resolver regardless of lane or of where the consumer's
# checkout lives (CLAUDE_PROJECT_DIR / CLAUDE_PLUGIN_ROOT need not be set — the
# canary fixtures exercise exactly that). Guard with `set +e` so a resolver
# edge-case return cannot abort this `set -e` script before its own gates run;
# PROJECT_ROOT above already established a git repo.
RESOLVER_SIBLING="$SCRIPT_DIR/../../update-zskills/scripts/zskills-resolve-config.sh"
set +e
if [ -f "$RESOLVER_SIBLING" ]; then
  . "$RESOLVER_SIBLING"
fi
set -e
[ -n "${ZSKILLS_CFG_LANDING:-}" ] && LANDING="$ZSKILLS_CFG_LANDING"
[ "${ZSKILLS_MAIN_PROTECTED:-}" = "true" ] && MAIN_PROTECTED="true"

# ──────────────────────────────────────────────────────────────────
# WI 1.7 — Gate logic precedence (after override returned above):
#   (1) In-worktree no-op — caller is already isolated.
#   (2) main_protected gate — if not "true", helper is a no-op.
#       Aligned with block-unsafe-project.sh.template:476.
#   (3) Otherwise: dispatch to create-worktree.sh.
# ──────────────────────────────────────────────────────────────────

# (1) In-worktree no-op.
if [ "$MAIN_ROOT" != "$TOPLEVEL" ]; then
  echo "ensure-worktree: caller already in worktree at $TOPLEVEL; proceeding" >&2
  printf '\n'
  exit 0
fi

# (2) main_protected gate (R-F8 + DA-17 fix). No `landing != "pr"`
# check — the hook this preamble front-runs gates purely on
# main_protected, so the helper aligns with the hook.
if [ "$MAIN_PROTECTED" != "true" ]; then
  printf '\n'
  exit 0
fi

# ──────────────────────────────────────────────────────────────────
# WI 1.8 — Dispatch to create-worktree.sh. Propagate exit code
# verbatim (no remap; preserves surface-bugs discipline).
# --allow-resume only when caller opted in (R-F7).
# ──────────────────────────────────────────────────────────────────
RESUME_ARG=()
[ "$ALLOW_RESUME" = "1" ] && RESUME_ARG=(--allow-resume)
set +e
WT=$(bash "$SCRIPT_DIR/create-worktree.sh" \
  --prefix "$PREFIX" \
  --pipeline-id "$PIPELINE_ID" \
  ${PURPOSE:+--purpose "$PURPOSE"} \
  "${RESUME_ARG[@]}" \
  "$SLUG")
RC=$?
set -e
if [ "$RC" -ne 0 ]; then
  exit "$RC"
fi
printf '%s\n' "$WT"
