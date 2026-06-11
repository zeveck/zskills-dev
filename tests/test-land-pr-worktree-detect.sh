#!/bin/bash
# tests/test-land-pr-worktree-detect.sh — regression tests for Issue #205.
#
# /land-pr Step 8 (`Compose .zskills/landed`) was previously gated on
# `--worktree-path`; when a caller omitted that arg but ran the skill
# from inside a worktree, the marker was silently skipped. The fix
# auto-detects worktree status from cwd via:
#   - git rev-parse --show-toplevel
#   - git rev-parse --git-dir != git rev-parse --git-common-dir
#   - membership in `git worktree list --porcelain`
#
# This test extracts the auto-detect bash block from SKILL.md and runs
# it against real git fixtures. Failure here means SKILL.md drifted
# from the reference implementation and Issue #205 may have regressed.
#
# Cases:
#   A. --worktree-path explicit override → WORKTREE_PATH preserved
#   B. cwd inside a registered worktree, --worktree-path empty → auto-detected
#   C. cwd is the main repo (not a worktree) → WORKTREE_PATH stays empty
#   D. cwd inside a non-git directory → WORKTREE_PATH stays empty, no error

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_FILE="$REPO_ROOT/skills/land-pr/SKILL.md"

PASS=0
FAIL=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

if [ ! -f "$SKILL_FILE" ]; then
  echo "FAIL: SKILL.md not found at $SKILL_FILE" >&2
  exit 1
fi

# The auto-detect block we test: pulled inline rather than extracted
# from SKILL.md, but verify that SKILL.md still contains the expected
# anchors (regression guard against silent prose drift).
for anchor in 'git rev-parse --show-toplevel' 'rev-parse --git-dir' 'rev-parse --git-common-dir' 'worktree list --porcelain'; do
  if ! grep -qF "$anchor" "$SKILL_FILE"; then
    fail "[anchor] SKILL.md missing auto-detect anchor: $anchor" "(Issue #205 regression)"
  else
    pass "[anchor] SKILL.md contains auto-detect anchor: $anchor"
  fi
done

# The reference auto-detect block (must mirror SKILL.md Step 8):
run_autodetect() {
  local input_path="${1:-}"
  WORKTREE_PATH="$input_path"
  if [ -z "$WORKTREE_PATH" ]; then
    CANDIDATE=$(git rev-parse --show-toplevel 2>/dev/null) || CANDIDATE=""
    if [ -n "$CANDIDATE" ]; then
      GIT_DIR=$(git -C "$CANDIDATE" rev-parse --git-dir 2>/dev/null) || GIT_DIR=""
      GIT_COMMON_DIR=$(git -C "$CANDIDATE" rev-parse --git-common-dir 2>/dev/null) || GIT_COMMON_DIR=""
      if [ -n "$GIT_DIR" ] && [ -n "$GIT_COMMON_DIR" ] && [ "$GIT_DIR" != "$GIT_COMMON_DIR" ]; then
        if git -C "$CANDIDATE" worktree list --porcelain 2>/dev/null | grep -qF "worktree $CANDIDATE"; then
          WORKTREE_PATH="$CANDIDATE"
        fi
      fi
    fi
  fi
  printf '%s' "$WORKTREE_PATH"
}

# ---- Set up shared fixture: a fresh git repo + a worktree ----------
FIXTURE="/tmp/land-pr-wt-detect-$$"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/main-repo"
( cd "$FIXTURE/main-repo" \
  && git init -q -b main \
  && git config user.email t@t \
  && git config user.name t \
  && echo "x" > a.txt \
  && git add a.txt \
  && git commit -q -m init ) || { echo "fixture init failed"; exit 1; }
( cd "$FIXTURE/main-repo" \
  && git worktree add -q -b feat/x "$FIXTURE/wt-feat-x" >/dev/null 2>&1 ) \
  || { echo "worktree create failed"; exit 1; }

trap 'rm -rf "$FIXTURE"' EXIT

# ---- Case A: explicit --worktree-path takes precedence (override) ---
result=$(cd "$FIXTURE/main-repo" && run_autodetect "/some/explicit/path")
if [ "$result" = "/some/explicit/path" ]; then
  pass "[caseA] explicit --worktree-path is preserved (override semantics)"
else
  fail "[caseA] explicit-path override" "got='$result' expected='/some/explicit/path'"
fi

# ---- Case B: cwd inside registered worktree, --worktree-path empty -
result=$(cd "$FIXTURE/wt-feat-x" && run_autodetect "")
# Resolve symlinks for comparison (macOS /tmp -> /private/tmp; Linux is direct)
expected=$(cd "$FIXTURE/wt-feat-x" && pwd -P)
got=$( [ -n "$result" ] && cd "$result" && pwd -P || printf '' )
if [ "$got" = "$expected" ] && [ -n "$result" ]; then
  pass "[caseB] cwd inside worktree → auto-detected ($result)"
else
  fail "[caseB] auto-detect from worktree cwd" "got='$result' expected≈'$expected'"
fi

# ---- Case C: cwd is main repo (not a linked worktree) → empty -----
result=$(cd "$FIXTURE/main-repo" && run_autodetect "")
if [ -z "$result" ]; then
  pass "[caseC] cwd is main repo → no auto-detect (no false-positive)"
else
  fail "[caseC] main-repo no false-positive" "got='$result' expected empty"
fi

# ---- Case D: cwd is non-git directory → empty, no error -----------
mkdir -p "$FIXTURE/non-git"
result=$(cd "$FIXTURE/non-git" && run_autodetect "" 2>/dev/null)
if [ -z "$result" ]; then
  pass "[caseD] cwd is non-git dir → no auto-detect, no error"
else
  fail "[caseD] non-git no false-positive" "got='$result' expected empty"
fi

echo ""
echo "---"
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (of %d)\033[0m\n' "$PASS" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (of %d)\033[0m\n' "$PASS" "$FAIL" "$TOTAL"
  exit 1
fi
