#!/bin/bash
# zskills-stub-lib.sh -- sourceable dispatcher for consumer
# stub-callouts. See
# .claude/skills/update-zskills/references/stub-callouts.md.
#
# Usage:
#   source "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-stub-lib.sh"
#   zskills_dispatch_stub <stub-name> <repo-root> -- arg1 arg2 ...
#
# Sets:
#   ZSKILLS_STUB_RC          - exit code from stub (or 0 if absent)
#   ZSKILLS_STUB_STDOUT      - captured stdout (or "" if absent)
#   ZSKILLS_STUB_INVOKED     - "1" iff the stub ran
zskills_dispatch_stub() {
  local name=$1
  local repo_root=$2
  shift 2
  [ "$1" = "--" ] && shift
  local stub="$repo_root/scripts/$name"
  ZSKILLS_STUB_RC=0
  ZSKILLS_STUB_STDOUT=""
  ZSKILLS_STUB_INVOKED=0
  if [ ! -e "$stub" ]; then
    return 0
  fi
  if [ ! -x "$stub" ]; then
    echo "zskills: scripts/$name present but not executable; ignoring (chmod +x to enable)" >&2
    return 0
  fi
  local notes_dir="$repo_root/.zskills/stub-notes"
  local marker="$notes_dir/$name.noted"
  if [ ! -f "$marker" ]; then
    # Suppress the note when marker write fails (e.g. read-only fs)
    # to avoid per-invocation noise on systems that can't persist.
    if mkdir -p "$notes_dir" 2>/dev/null && touch "$marker" 2>/dev/null; then
      echo "zskills: invoking consumer stub scripts/$name (one-time note; see .claude/skills/update-zskills/references/stub-callouts.md)" >&2
    fi
  fi
  ZSKILLS_STUB_INVOKED=1
  # `|| ZSKILLS_STUB_RC=$?` makes the assignment safe under callers'
  # `set -e`; without the `||`, a non-zero stub aborts the caller
  # before line 41 runs, so RC stays at 0 and the caller never sees
  # the failure. Discovered when wiring Phase 3 callout into
  # create-worktree.sh (which uses `set -eu`).
  ZSKILLS_STUB_STDOUT=$(bash "$stub" "$@") || ZSKILLS_STUB_RC=$?
  if [ "$ZSKILLS_STUB_RC" -ne 0 ]; then
    echo "zskills: scripts/$name exited $ZSKILLS_STUB_RC" >&2
  fi
  return 0
}
