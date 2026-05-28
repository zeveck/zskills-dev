#!/bin/bash
# zskills-hook-version: 2026.05.0
# block-main-edits.sh — PreToolUse hook on Edit / Write.
#
# Honors execution.main_protected from .claude/zskills-config.json. When
# main_protected is true, denies Edit/Write calls whose target
# file_path lives inside the main repo working tree (NOT a linked worktree),
# unless the path falls under a narrow allowlist of agent-managed surfaces
# (everything under .zskills/, and gitignored worktree-state markers).
#
# Issue #308 — closes the surface that allowed an orchestrator running on
# main to write directly to skill files, plan files, hooks, configs, and
# audit reports without the worktree discipline the worktree rule (and
# main_protected) is supposed to enforce.
#
# Non-blocking guarantees:
#   - main_protected: false in config → exit 0 (no-op).
#   - The hook's $CLAUDE_PROJECT_DIR is itself a linked worktree (rare;
#     happens when a Claude Code session was started inside a worktree)
#     → exit 0 (no-op). We block edits to MAIN, not edits inside any worktree.
#   - file_path lives outside $MAIN_ROOT → exit 0 (allow).
#   - file_path is under $MAIN_ROOT but matches the allowlist → exit 0.
#   - Otherwise → emit a PreToolUse deny envelope with a STOP message.
#
# Decision envelope follows the same shape as block-unsafe-project.sh:
#   {"hookSpecificOutput":{"hookEventName":"PreToolUse",
#                          "permissionDecision":"deny",
#                          "permissionDecisionReason":"<STOP message>"}}
#
# Test surface: tests/test-block-main-edits.sh

# D16(a) plugin-lane conditional-skip shim. No-op on the /update-zskills
# lane (CLAUDE_PLUGIN_ROOT unset → guard below skips the source). On the
# plugin lane it defers to a settings.json-registered copy of this hook to
# prevent double-fire when both install lanes are active. Must be the first
# executable line; the shim controls its own exit/return.
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_lib/plugin-hook-skip-if-mirrored.sh" ] && source "${CLAUDE_PLUGIN_ROOT}/hooks/_lib/plugin-hook-skip-if-mirrored.sh"

INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

# ── Tool-name gate ────────────────────────────────────────────────────────
# Only fire on Edit / Write. The matcher in settings.json
# scopes the registration; this guard is defense-in-depth in case the hook
# is invoked from a broader matcher.
TOOL_NAME=""
if [[ "$INPUT" =~ \"tool_name\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
  TOOL_NAME="${BASH_REMATCH[1]}"
fi
case "$TOOL_NAME" in
  Edit|Write) ;;
  *) exit 0 ;;
esac

# ── Extract target path ───────────────────────────────────────────────────
# Edit and Write both use tool_input.file_path.
FILE_PATH=""
if [[ "$INPUT" =~ \"file_path\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
  FILE_PATH="${BASH_REMATCH[1]}"
fi
# No path extracted → can't decide → allow (defensive; never false-deny).
[ -z "$FILE_PATH" ] && exit 0

# ── Resolve $MAIN_ROOT ────────────────────────────────────────────────────
# $CLAUDE_PROJECT_DIR is set by Claude Code at hook fire time to the project
# root the session was started in. Fall back to git toplevel, then pwd.
# REPO_ROOT env override exists for tests.
MAIN_ROOT="${REPO_ROOT:-${CLAUDE_PROJECT_DIR:-}}"
if [ -z "$MAIN_ROOT" ]; then
  MAIN_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi
# Canonicalize MAIN_ROOT (resolve symlinks, drop trailing slash). On systems
# without readlink -f / realpath, fall back to the literal path.
RESOLVED_MAIN=$(cd "$MAIN_ROOT" 2>/dev/null && pwd -P) || RESOLVED_MAIN="$MAIN_ROOT"
MAIN_ROOT="${RESOLVED_MAIN%/}"

# ── Worktree-self check ──────────────────────────────────────────────────
# If $MAIN_ROOT itself is a linked worktree (session started in a worktree),
# this hook is a no-op — we only protect main, not whichever checkout we
# happen to live in. Divergence detection: in a linked worktree,
# `git rev-parse --git-dir` points at .git/worktrees/<name>, while
# --git-common-dir points at the main .git. They differ.
GIT_DIR=$(git -C "$MAIN_ROOT" rev-parse --git-dir 2>/dev/null)
GIT_COMMON=$(git -C "$MAIN_ROOT" rev-parse --git-common-dir 2>/dev/null)
if [ -n "$GIT_DIR" ] && [ -n "$GIT_COMMON" ]; then
  # Resolve both to absolute paths for a robust string compare. `git
  # rev-parse` returns paths relative to the cwd when it can, so they
  # need normalization before comparison.
  ABS_GIT_DIR=$(cd "$MAIN_ROOT" && cd "$GIT_DIR" 2>/dev/null && pwd -P) || ABS_GIT_DIR="$GIT_DIR"
  ABS_GIT_COMMON=$(cd "$MAIN_ROOT" && cd "$GIT_COMMON" 2>/dev/null && pwd -P) || ABS_GIT_COMMON="$GIT_COMMON"
  if [ "$ABS_GIT_DIR" != "$ABS_GIT_COMMON" ]; then
    # We are inside a linked worktree — not main. Allow.
    exit 0
  fi
fi

# ── main_protected gate ──────────────────────────────────────────────────
# Load-bearing config check (issue #308 §1). Defaults to OFF — only blocks
# when the literal `"main_protected": true` is present in the config.
CONFIG_FILE="$MAIN_ROOT/.claude/zskills-config.json"
MAIN_PROTECTED=0
if [ -f "$CONFIG_FILE" ]; then
  CFG_CONTENT=$(cat "$CONFIG_FILE" 2>/dev/null) || CFG_CONTENT=""
  if [[ "$CFG_CONTENT" =~ \"main_protected\"[[:space:]]*:[[:space:]]*true ]]; then
    MAIN_PROTECTED=1
  fi
fi
[ "$MAIN_PROTECTED" -eq 1 ] || exit 0

# ── Resolve target path & check containment ──────────────────────────────
# Normalize the target. If it's relative, treat it as relative to $MAIN_ROOT
# (matches what `Edit` accepts, although Edit/Write require absolute paths
# per Claude Code conventions — we still defend).
case "$FILE_PATH" in
  /*) ABS_FILE_PATH="$FILE_PATH" ;;
  *)  ABS_FILE_PATH="$MAIN_ROOT/$FILE_PATH" ;;
esac

# Resolve the dirname (file may not exist yet for Write) and re-attach the
# basename. This handles `..` segments and symlinks in the dirname.
TARGET_DIR=$(dirname "$ABS_FILE_PATH")
TARGET_BASE=$(basename "$ABS_FILE_PATH")
RESOLVED_DIR=$(cd "$TARGET_DIR" 2>/dev/null && pwd -P) || RESOLVED_DIR="$TARGET_DIR"
RESOLVED_FILE="${RESOLVED_DIR%/}/$TARGET_BASE"

# Containment check: is the resolved file under $MAIN_ROOT?
case "$RESOLVED_FILE" in
  "$MAIN_ROOT"/*) ;;  # under main — fall through to allowlist
  *) exit 0 ;;         # outside main (worktree, /tmp, etc.) — allow
esac

# Path relative to MAIN_ROOT for allowlist matching.
REL="${RESOLVED_FILE#$MAIN_ROOT/}"

# ── Allowlist ────────────────────────────────────────────────────────────
# Agent-managed gitignored surfaces. These are NOT part of the main repo's
# tracked content (gitignore'd), so writes here don't pollute main's working
# tree from git's perspective and don't cause the `git checkout` /
# `git stash` cascades that motivated this hook. Keep this list narrow.
case "$REL" in
  .zskills/*)        exit 0 ;;  # tracking, audit, issues, dev-server state, monitor runtime
  .zskills-tracked)  exit 0 ;;  # worktree pipeline-id marker
  .landed)           exit 0 ;;  # worktree landed marker
  .worktreepurpose)  exit 0 ;;  # worktree purpose marker
esac

# ── Deny ─────────────────────────────────────────────────────────────────
STOP_MSG=$(cat <<EOF
STOP: Edit/Write to main is blocked (main_protected: true in .claude/zskills-config.json).

Target: $REL

Edits to the main repo working tree bypass the worktree discipline. Move
this change into a worktree:

  - Standard task with review: \\\`/do pr\\\` (worktree → PR)
  - Plan-driven work: \\\`/run-plan\\\` (worktree per phase)
  - Manual: \\\`/create-worktree\\\` then operate inside the returned path

\\\`/quickfix\\\` is NOT a valid alternative here: it is no-worktree by
design (operates on main via \\\`git checkout -b\\\`), so an agent-dispatched
\\\`/quickfix\\\` invocation would hit this same hook on its first Edit/Write.
Humans driving \\\`/quickfix\\\` interactively can still use it — their dirty
edits exist on disk before \\\`/quickfix\\\` runs and are not subject to this
gate — but agents must route through a worktree.

Allowed on main (not blocked): paths under \\\`.zskills/\\\` (tracking,
audit, issues, dev-server state), and the gitignored worktree-state markers
\\\`.zskills-tracked\\\`, \\\`.landed\\\`, \\\`.worktreepurpose\\\`.

To disable this gate project-wide, set \\\`execution.main_protected: false\\\`
in \\\`.claude/zskills-config.json\\\`.
EOF
)

# Emit deny envelope. Escape for JSON: backslashes first, then quotes, then
# newlines. Mirrors block-unsafe-project.sh's block_with_reason pattern.
ESC="${STOP_MSG//\\/\\\\}"
ESC="${ESC//\"/\\\"}"
ESC="${ESC//$'\n'/\\n}"
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$ESC"
exit 0
