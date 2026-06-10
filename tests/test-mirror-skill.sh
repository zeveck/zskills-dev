#!/bin/bash
# Tests for scripts/mirror-skill.sh
# Run from repo root: bash tests/test-mirror-skill.sh
#
# Each test builds a synthetic fixture under /tmp/zskills-mirror-test-<n>/
# with its own `skills/<name>/` and `.claude/skills/<name>/` trees, then
# runs the helper inside the fixture (via a `cd` + isolated git init so
# `git rev-parse --show-toplevel` picks up the fixture root, not the
# real zskills repo).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$REPO_ROOT/scripts/mirror-skill.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  printf '\033[32m  PASS\033[0m %s\n' "$1"
  ((PASS_COUNT++))
}

fail() {
  printf '\033[31m  FAIL\033[0m %s\n' "$1"
  ((FAIL_COUNT++))
}

# Build a fresh fixture root: a /tmp dir containing a `skills/<name>/`
# tree, an empty `.claude/skills/` parent, and an isolated git repo so
# the helper resolves repo root to the fixture (not the real zskills
# checkout). Echoes the fixture path on stdout.
make_fixture() {
  local label="$1"
  local fixture="/tmp/zskills-mirror-test-$label-$$"
  rm -rf -- "$fixture" 2>/dev/null
  mkdir -p "$fixture/skills" "$fixture/.claude/skills"
  ( cd "$fixture" && git init -q && git config user.email t@t && git config user.name t )
  echo "$fixture"
}

cleanup_fixture() {
  local fixture="$1"
  # Per CLAUDE.md: only `rm -rf` literal /tmp/<name> paths.
  case "$fixture" in
    /tmp/zskills-mirror-test-*)
      rm -rf -- "$fixture"
      ;;
    *)
      echo "REFUSING to clean non-/tmp path: $fixture" >&2
      ;;
  esac
}

echo "=== mirror-skill.sh tests ==="

# --- Test 1: single-file source, fresh mirror -------------------------
F=$(make_fixture t1)
mkdir -p "$F/skills/alpha"
echo "alpha content" > "$F/skills/alpha/SKILL.md"
out=$( cd "$F" && bash "$HELPER" alpha 2>&1 )
ec=$?
if [ "$ec" -eq 0 ] \
   && [ -f "$F/.claude/skills/alpha/SKILL.md" ] \
   && [ "$(cat "$F/.claude/skills/alpha/SKILL.md")" = "alpha content" ] \
   && diff -rq "$F/skills/alpha/" "$F/.claude/skills/alpha/" >/dev/null 2>&1; then
  pass "single-file source -> fresh mirror"
else
  fail "single-file fresh mirror (exit=$ec, out=$out)"
fi
cleanup_fixture "$F"

# --- Test 2: multi-file source, fresh mirror --------------------------
F=$(make_fixture t2)
mkdir -p "$F/skills/beta/references" "$F/skills/beta/modes"
echo "main"  > "$F/skills/beta/SKILL.md"
echo "ref-x" > "$F/skills/beta/references/x.md"
echo "pr"    > "$F/skills/beta/modes/pr.md"
out=$( cd "$F" && bash "$HELPER" beta 2>&1 )
ec=$?
if [ "$ec" -eq 0 ] \
   && [ -f "$F/.claude/skills/beta/SKILL.md" ] \
   && [ -f "$F/.claude/skills/beta/references/x.md" ] \
   && [ -f "$F/.claude/skills/beta/modes/pr.md" ] \
   && diff -rq "$F/skills/beta/" "$F/.claude/skills/beta/" >/dev/null 2>&1; then
  pass "multi-file source -> fresh mirror"
else
  fail "multi-file fresh mirror (exit=$ec, out=$out)"
fi
cleanup_fixture "$F"

# --- Test 3: existing mirror with orphan ------------------------------
F=$(make_fixture t3)
mkdir -p "$F/skills/gamma"
echo "new content" > "$F/skills/gamma/SKILL.md"
mkdir -p "$F/.claude/skills/gamma"
echo "stale content" > "$F/.claude/skills/gamma/SKILL.md"
echo "orphan"        > "$F/.claude/skills/gamma/OLD_FILE.md"
out=$( cd "$F" && bash "$HELPER" gamma 2>&1 )
ec=$?
if [ "$ec" -eq 0 ] \
   && [ "$(cat "$F/.claude/skills/gamma/SKILL.md")" = "new content" ] \
   && [ ! -e "$F/.claude/skills/gamma/OLD_FILE.md" ] \
   && diff -rq "$F/skills/gamma/" "$F/.claude/skills/gamma/" >/dev/null 2>&1; then
  pass "existing mirror with orphan: orphan removed, content updated"
else
  fail "orphan removal (exit=$ec, out=$out, orphan-exists=$( [ -e "$F/.claude/skills/gamma/OLD_FILE.md" ] && echo yes || echo no ))"
fi
cleanup_fixture "$F"

# --- Test 4: source doesn't exist -> exit 1 ---------------------------
F=$(make_fixture t4)
out=$( cd "$F" && bash "$HELPER" does-not-exist 2>&1 )
ec=$?
if [ "$ec" -eq 1 ] && echo "$out" | grep -qi "source dir not found"; then
  pass "missing source: exit 1 with clear error"
else
  fail "missing source (exit=$ec, out=$out)"
fi
cleanup_fixture "$F"

# --- Test 5: no arg -> exit 1 with usage -----------------------------
F=$(make_fixture t5)
out=$( cd "$F" && bash "$HELPER" 2>&1 )
ec=$?
if [ "$ec" -eq 1 ] && echo "$out" | grep -qi "usage"; then
  pass "no arg: exit 1 with usage message"
else
  fail "no-arg usage (exit=$ec, out=$out)"
fi
cleanup_fixture "$F"

# --- Test 6: update-only (no orphans, no adds) ------------------------
F=$(make_fixture t6)
mkdir -p "$F/skills/delta"
echo "v2 content" > "$F/skills/delta/SKILL.md"
mkdir -p "$F/.claude/skills/delta"
echo "v1 content" > "$F/.claude/skills/delta/SKILL.md"
out=$( cd "$F" && bash "$HELPER" delta 2>&1 )
ec=$?
if [ "$ec" -eq 0 ] \
   && [ "$(cat "$F/.claude/skills/delta/SKILL.md")" = "v2 content" ] \
   && diff -rq "$F/skills/delta/" "$F/.claude/skills/delta/" >/dev/null 2>&1; then
  pass "update-only: stale mirror file is refreshed to source content"
else
  fail "update-only (exit=$ec, out=$out)"
fi
cleanup_fixture "$F"

# --- Test 7: orphan-dir empty ----------------------------------------
# Source has SKILL.md only; mirror has SKILL.md + an empty references/.
# Helper's `elif [ -d "$orphan" ]` branch should rmdir the empty
# references/ directory, leaving diff -rq clean.
F=$(make_fixture orphan-dir-empty)
mkdir -p "$F/skills/epsilon"
echo "epsilon content" > "$F/skills/epsilon/SKILL.md"
mkdir -p "$F/.claude/skills/epsilon/references"
echo "epsilon content" > "$F/.claude/skills/epsilon/SKILL.md"
out=$( cd "$F" && bash "$HELPER" epsilon 2>&1 )
ec=$?
if [ "$ec" -eq 0 ] \
   && [ ! -e "$F/.claude/skills/epsilon/references" ] \
   && diff -rq "$F/skills/epsilon/" "$F/.claude/skills/epsilon/" >/dev/null 2>&1; then
  pass "orphan-dir empty: empty mirror subdir is removed"
else
  fail "orphan-dir empty (exit=$ec, out=$out, dir-exists=$( [ -e "$F/.claude/skills/epsilon/references" ] && echo yes || echo no ))"
fi
cleanup_fixture "$F"

# --- Test 8: orphan-dir non-empty ------------------------------------
# Source has SKILL.md only; mirror has SKILL.md + references/notes.md.
# Helper's `elif [ -d "$orphan" ]` branch should walk the dir with
# `find -type f` to rm the file, then rmdir the now-empty parent.
F=$(make_fixture orphan-dir-nonempty)
mkdir -p "$F/skills/zeta"
echo "zeta content" > "$F/skills/zeta/SKILL.md"
mkdir -p "$F/.claude/skills/zeta/references"
echo "zeta content"  > "$F/.claude/skills/zeta/SKILL.md"
echo "stale notes"   > "$F/.claude/skills/zeta/references/notes.md"
out=$( cd "$F" && bash "$HELPER" zeta 2>&1 )
ec=$?
if [ "$ec" -eq 0 ] \
   && [ ! -e "$F/.claude/skills/zeta/references/notes.md" ] \
   && [ ! -e "$F/.claude/skills/zeta/references" ] \
   && diff -rq "$F/skills/zeta/" "$F/.claude/skills/zeta/" >/dev/null 2>&1; then
  pass "orphan-dir non-empty: file removed then empty parent rmdir'd"
else
  fail "orphan-dir non-empty (exit=$ec, out=$out, file-exists=$( [ -e "$F/.claude/skills/zeta/references/notes.md" ] && echo yes || echo no ), dir-exists=$( [ -e "$F/.claude/skills/zeta/references" ] && echo yes || echo no ))"
fi
cleanup_fixture "$F"

echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' \
  "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
