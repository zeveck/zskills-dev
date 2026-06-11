#!/bin/bash
# write-landed.sh — atomic landed-marker write with rc checks.
#
# Replaces the ad-hoc `cat > marker.tmp <<EOF ... EOF ; mv marker.tmp marker`
# pattern that appeared at 12 sites across skills/. The ad-hoc pattern silently
# wrote empty / partial markers when `cat` failed (disk full, permission
# denied, heredoc parse error) — and the follow-on `mv` succeeded moving the
# broken file, so downstream readers got a corrupt or empty marker.
#
# Root-turd consolidation (INSTALL_REDESIGN Phase 8): the marker now lives at
# <worktree-path>/.zskills/landed (was <worktree-path>/.landed). This script
# is THE sole writer and writes the NEW path only; readers dual-read
# (new path first, then the old root path) for the transition window.
#
# Usage:
#   cat <<LANDED | bash $(basename "$0") <worktree-path>
#   status: landed
#   date: ...
#   ...
#   LANDED
#
# Arg: <worktree-path>   — must be an existing directory
# Stdin:                 — the marker body (any content)
# Writes: <worktree-path>/.zskills/landed (atomic via .tmp + mv)
# Exits:
#   0  — wrote both .tmp and renamed the marker successfully
#   1  — missing/empty arg, worktree doesn't exist, cat failed, or mv failed
#
# On any failure, the .tmp is removed (best-effort) and the error is written
# to stderr — callers get loud exit-1 instead of silent success with broken
# marker.

set -u

WORKTREE="${1:-}"

if [ -z "$WORKTREE" ]; then
  echo "ERROR: write-landed.sh requires a worktree-path arg" >&2
  echo "  Usage: cat <body> | bash write-landed.sh <worktree-path>" >&2
  exit 1
fi

if [ ! -d "$WORKTREE" ]; then
  echo "ERROR: write-landed.sh: worktree path does not exist: $WORKTREE" >&2
  exit 1
fi

MARKER_DIR="$WORKTREE/.zskills"
if ! mkdir -p "$MARKER_DIR"; then
  echo "ERROR: write-landed.sh: failed to create $MARKER_DIR" >&2
  exit 1
fi

# Belt-and-braces with init's gitignore-first A2 umbrella: ensure .zskills/
# is ignored in this checkout. NEVER append to the tracked .gitignore here
# (that would dirty the worktree and break landing's clean-tree check) —
# the shared $GIT_COMMON_DIR/info/exclude covers every worktree without
# touching tracked content. Best-effort: a failure here never blocks the
# marker write (land-phase.sh removes the markers before worktree removal
# regardless).
if ! git -C "$WORKTREE" check-ignore -q .zskills/probe 2>/dev/null; then
  _common_dir=$(git -C "$WORKTREE" rev-parse --git-common-dir 2>/dev/null)
  if [ -n "$_common_dir" ]; then
    case "$_common_dir" in
      /*) : ;;
      *) _common_dir="$WORKTREE/$_common_dir" ;;
    esac
    mkdir -p "$_common_dir/info" 2>/dev/null \
      && echo ".zskills/" >> "$_common_dir/info/exclude" 2>/dev/null \
      || echo "WARN: write-landed.sh: could not ensure .zskills/ git-exclusion (non-fatal)" >&2
  fi
fi
unset _common_dir

TMP="$MARKER_DIR/landed.tmp"
FINAL="$MARKER_DIR/landed"

# Read stdin into .tmp. If cat fails (disk full, permission denied,
# read-only FS), rm the partial .tmp and exit loudly.
if ! cat > "$TMP"; then
  echo "ERROR: write-landed.sh: failed to write $TMP (disk full? read-only FS? permissions?)" >&2
  rm -f "$TMP"
  exit 1
fi

# Atomic rename. If mv fails (cross-device, permission, etc.), the stale
# marker at $FINAL remains whatever it was — the caller sees a loud
# error and can decide whether to retry, inspect, or escalate.
if ! mv "$TMP" "$FINAL"; then
  echo "ERROR: write-landed.sh: failed to rename $TMP to $FINAL" >&2
  echo "  If $FINAL exists, it is NOT the new marker — retry or inspect manually." >&2
  rm -f "$TMP"
  exit 1
fi

exit 0
