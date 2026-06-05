#!/bin/bash
# tests/test-normalize-tool-path.sh — unit tests for
# hooks/_lib/normalize-tool-path.sh's zskills_normalize_tool_path().
#
# The function normalises a tool `file_path` to a POSIX form so the
# PreToolUse/PostToolUse hooks that classify a path against the repo root
# (block-main-edits.sh, warn-config-drift.sh) work on a Windows (MSYS /
# Git-Bash) consumer, where Edit/Write passes a drive-letter / backslash path
# (e.g. `D:\proj\.zskills\x`). Without normalisation, `case in /*)` misreads
# such a path as relative → containment breaks → block-main-edits.sh
# FALSE-DENIES gitignored `.zskills/` writes and warn-config-drift.sh silently
# skips its staged-file gate.
#
# This suite runs on Linux/Mac CI, where `cygpath` is ABSENT — so it exercises
# the pure-bash fallback, which is exactly the Windows path-transform logic. It
# is therefore a genuine test of the Windows behaviour WITHOUT a Windows box.
# pass/fail inline (mirrors tests/test-hook-helper-drift.sh:22-25).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$REPO_ROOT/hooks/_lib/normalize-tool-path.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32mPASS\033[0m %s\n' "$*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31mFAIL\033[0m %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT+1)); }

if [ ! -f "$HELPER" ]; then
  fail "source-of-truth helper not found: $HELPER"
  echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
  exit "$FAIL_COUNT"
fi

# shellcheck source=/dev/null
source "$HELPER"

# Guard: this suite proves the pure-bash fallback. If cygpath is on PATH (i.e.
# we are on an actual MSYS/Cygwin host), the cygpath branch takes over and the
# expected POSIX strings below would not necessarily hold — note and skip the
# fallback assertions rather than fail spuriously.
if command -v cygpath >/dev/null 2>&1; then
  echo "NOTE: cygpath present — fallback assertions skipped (cygpath branch active on this host)." >&2
  echo "Results: 0 passed, 0 failed (of 0)"
  exit 0
fi

check() {
  local desc="$1" input="$2" want="$3" got
  got="$(zskills_normalize_tool_path "$input")"
  if [ "$got" = "$want" ]; then
    pass "$desc: [$input] -> [$got]"
  else
    fail "$desc: [$input] -> [$got] (expected [$want])"
  fi
}

# Drive-letter absolute, backslash separators (the canonical Windows form).
check "drive-letter + backslashes lowercases drive, slashes separators" \
  'D:\a\.zskills\x' '/d/a/.zskills/x'

# Drive-letter absolute, forward slashes (Git-Bash sometimes emits this).
check "drive-letter + forward slashes lowercases drive, keeps slashes" \
  'C:/Users/x/SKILL.md' '/c/Users/x/SKILL.md'

# Pure-POSIX absolute path — MUST pass through byte-for-byte (Linux/Mac no-op).
check "pure-POSIX absolute path is unchanged" \
  '/already/posix' '/already/posix'

# Backslash-relative path — convert separators, no drive prefix added.
check "backslash-relative path converts separators only" \
  'rel\path' 'rel/path'

# Empty input → empty output.
check "empty input yields empty output" \
  '' ''

# Pure-POSIX relative path — no backslash, no drive → unchanged.
check "pure-POSIX relative path is unchanged" \
  'relative/posix/path' 'relative/posix/path'

# The exact path from the issue report.
check "issue-report path normalises end-to-end" \
  'D:\LocalDev\proj\.zskills\run-dashboard-start.sh' \
  '/d/LocalDev/proj/.zskills/run-dashboard-start.sh'

# Lowercase drive letter stays lowercase (idempotent on already-lower drive).
check "already-lowercase drive letter stays lowercase" \
  'e:\Work\file.txt' '/e/Work/file.txt'

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
exit "$FAIL_COUNT"
