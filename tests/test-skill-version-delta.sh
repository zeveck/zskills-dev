#!/bin/bash
# Tests for skills/update-zskills/scripts/skill-version-delta.sh.
#
# Phase 5a.8 (plans/SKILL_VERSIONING.md). Builds synthetic source/install
# fixtures and exercises the status branches:
#   - bumped (source > installed)
#   - bumped (source < installed; downstream decides) — script still emits "bumped"
#   - new (installed missing)
#   - malformed (source SKILL.md present but no metadata.version)
#   - unchanged (both equal)
#
# Run from repo root: bash tests/test-skill-version-delta.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$REPO_ROOT/skills/update-zskills/scripts/skill-version-delta.sh"
GET_HELPER="$REPO_ROOT/scripts/frontmatter-get.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

if [ ! -f "$HELPER" ]; then
  fail "helper exists" "$HELPER missing"
  printf 'Results: %d passed, %d failed (of %d)\n' \
    "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"
  exit 1
fi

# Build a synthetic two-tree workspace: $FIXT/skills/<name>/SKILL.md (source)
# and $FIXT/.claude/skills/<name>/SKILL.md (installed).
FIXT=$(mktemp -d /tmp/zskills-svd-XXXXXX)
trap 'rm -rf "$FIXT"' EXIT

mkdir -p "$FIXT/skills" "$FIXT/.claude/skills" "$FIXT/scripts"

# Provide frontmatter-get.sh in the fixture so the helper finds it via
# the fallback ($ZSKILLS_PATH/scripts/frontmatter-get.sh).
cp "$GET_HELPER" "$FIXT/scripts/frontmatter-get.sh"
chmod +x "$FIXT/scripts/frontmatter-get.sh"

# Helper: write a SKILL.md with a given metadata.version.
write_skill() {
  local dir="$1" name="$2" ver="$3"
  mkdir -p "$dir"
  if [ -n "$ver" ]; then
    cat > "$dir/SKILL.md" <<EOF
---
name: $name
description: synthetic
metadata:
  version: "$ver"
---
body
EOF
  else
    cat > "$dir/SKILL.md" <<EOF
---
name: $name
description: synthetic
---
body
EOF
  fi
}

# Fixture skills:
# - bumped-newer: source 2026.05.02, installed 2026.04.01 (status=bumped)
write_skill "$FIXT/skills/bumped-newer" bumped-newer "2026.05.02+aaaaaa"
write_skill "$FIXT/.claude/skills/bumped-newer" bumped-newer "2026.04.01+bbbbbb"

# - bumped-older: source 2026.04.01, installed 2026.05.02 (status=bumped — downstream decides)
write_skill "$FIXT/skills/bumped-older" bumped-older "2026.04.01+aaaaaa"
write_skill "$FIXT/.claude/skills/bumped-older" bumped-older "2026.05.02+bbbbbb"

# - newcomer: source present, installed missing (status=new)
write_skill "$FIXT/skills/newcomer" newcomer "2026.05.02+cccccc"

# - malformed: source has no metadata.version, installed has one
write_skill "$FIXT/skills/malformed" malformed ""
write_skill "$FIXT/.claude/skills/malformed" malformed "2026.04.01+ddddddd"

# - same-version: both equal (status=unchanged)
write_skill "$FIXT/skills/same-version" same-version "2026.05.02+eeeeee"
write_skill "$FIXT/.claude/skills/same-version" same-version "2026.05.02+eeeeee"

CLAUDE_PROJECT_DIR="$FIXT" bash "$HELPER" "$FIXT" > "$FIXT/out.tsv" 2>"$FIXT/err.txt"
RC=$?
if [ "$RC" -eq 0 ]; then
  pass "helper exit code 0"
else
  fail "helper exit code 0" "rc=$RC stderr=$(cat "$FIXT/err.txt")"
fi

# Helper: assert one row matches the given fields. Format:
#   <name>\t<src>\t<inst>\t<status>
assert_row() {
  local name="$1" src="$2" inst="$3" status="$4"
  local label="row name=$name"
  local needle
  needle=$(printf '%s\t%s\t%s\t%s' "$name" "$src" "$inst" "$status")
  if grep -qFx "$needle" "$FIXT/out.tsv"; then
    pass "$label → $status"
  else
    fail "$label" "expected '$needle' not found; got: $(grep "$name" "$FIXT/out.tsv" || echo NONE)"
  fi
}

assert_row bumped-newer       "2026.05.02+aaaaaa"  "2026.04.01+bbbbbb"  bumped
assert_row bumped-older       "2026.04.01+aaaaaa"  "2026.05.02+bbbbbb"  bumped
assert_row newcomer           "2026.05.02+cccccc"  ""                   new
assert_row malformed          ""                   "2026.04.01+ddddddd" malformed
assert_row same-version       "2026.05.02+eeeeee"  "2026.05.02+eeeeee"  unchanged

# Total row count = 5 core
LINE_COUNT=$(wc -l < "$FIXT/out.tsv")
if [ "$LINE_COUNT" = "5" ]; then
  pass "row count = 5 (5 core)"
else
  fail "row count" "expected 5 got $LINE_COUNT; full output:
$(cat "$FIXT/out.tsv")"
fi

# Tab-delimited 4-field invariant.
NON4=$(awk -F'\t' 'NF != 4' "$FIXT/out.tsv" | wc -l)
if [ "$NON4" = "0" ]; then
  pass "every row is exactly 4 tab-delimited fields"
else
  fail "field count invariant" "$NON4 rows have NF != 4"
fi

# Real-repo smoke check: run against the actual REPO_ROOT and assert the
# row count is at least 23 core.
CLAUDE_PROJECT_DIR="$REPO_ROOT" bash "$HELPER" "$REPO_ROOT" > "$FIXT/real.tsv" 2>"$FIXT/real-err.txt"
REAL_RC=$?
if [ "$REAL_RC" -ne 0 ]; then
  fail "real-repo smoke: helper exit code 0" "rc=$REAL_RC stderr=$(cat "$FIXT/real-err.txt")"
else
  REAL_LINES=$(wc -l < "$FIXT/real.tsv")
  if [ "$REAL_LINES" -ge 23 ]; then
    pass "real-repo smoke: $REAL_LINES rows (≥ 23 core)"
  else
    fail "real-repo smoke row count" "expected ≥23 got $REAL_LINES"
  fi
fi

# --- Summary ---------------------------------------------------------------
echo ""
echo "---"
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (of %d)\033[0m\n' "$PASS_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (of %d)\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit 1
fi
