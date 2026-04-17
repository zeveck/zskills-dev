#!/bin/bash
# scripts/write-landed.sh — atomic .landed marker write with rc checks.
#
# Replaces the ad-hoc `cat > .landed.tmp <<EOF ... EOF ; mv .landed.tmp .landed`
# pattern that appeared at 12 sites across skills/. The ad-hoc pattern silently
# wrote empty / partial markers when `cat` failed (disk full, permission
# denied, heredoc parse error) — and the follow-on `mv` succeeded moving the
# broken file, so downstream readers got a corrupt or empty .landed.
#
# Usage:
#   cat <<LANDED | bash scripts/write-landed.sh <worktree-path>
#   status: landed
#   date: ...
#   ...
#   LANDED
#
# Arg: <worktree-path>   — must be an existing directory
# Stdin:                 — the marker body (any content)
# Writes: <worktree-path>/.landed (atomic via .tmp + mv)
# Exits:
#   0  — wrote both .tmp and renamed .landed successfully
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

TMP="$WORKTREE/.landed.tmp"
FINAL="$WORKTREE/.landed"

# Read stdin into .tmp. If cat fails (disk full, permission denied,
# read-only FS), rm the partial .tmp and exit loudly.
if ! cat > "$TMP"; then
  echo "ERROR: write-landed.sh: failed to write $TMP (disk full? read-only FS? permissions?)" >&2
  rm -f "$TMP"
  exit 1
fi

# Atomic rename. If mv fails (cross-device, permission, etc.), the stale
# .landed at $FINAL remains whatever it was — the caller sees a loud
# error and can decide whether to retry, inspect, or escalate.
if ! mv "$TMP" "$FINAL"; then
  echo "ERROR: write-landed.sh: failed to rename $TMP to $FINAL" >&2
  echo "  If $FINAL exists, it is NOT the new marker — retry or inspect manually." >&2
  rm -f "$TMP"
  exit 1
fi

exit 0
