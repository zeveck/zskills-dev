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
#   - addon enumeration (block-diagram/<name>/SKILL.md surfaces with kind=addon)
#   - addon row STILL emitted when not installed (renderer hides; script doesn't)
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
# and $FIXT/.claude/skills/<name>/SKILL.md (installed). Plus block-diagram/.
FIXT=$(mktemp -d /tmp/zskills-svd-XXXXXX)
trap 'rm -rf "$FIXT"' EXIT

mkdir -p "$FIXT/skills" "$FIXT/.claude/skills" "$FIXT/block-diagram" "$FIXT/scripts"

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

# - addon-installed: addon source present AND installed (kind=addon, unchanged)
write_skill "$FIXT/block-diagram/addon-installed" addon-installed "2026.05.02+ff1111"
write_skill "$FIXT/.claude/skills/addon-installed" addon-installed "2026.05.02+ff1111"

# - addon-not-installed: addon source present, NOT installed
#   (kind=addon, status=new — script still emits the row; renderer hides)
write_skill "$FIXT/block-diagram/addon-not-installed" addon-not-installed "2026.05.02+ff2222"

CLAUDE_PROJECT_DIR="$FIXT" bash "$HELPER" "$FIXT" > "$FIXT/out.tsv" 2>"$FIXT/err.txt"
RC=$?
if [ "$RC" -eq 0 ]; then
  pass "helper exit code 0"
else
  fail "helper exit code 0" "rc=$RC stderr=$(cat "$FIXT/err.txt")"
fi

# Helper: assert one row matches the given fields. Format:
#   <name>\t<kind>\t<src>\t<inst>\t<status>
assert_row() {
  local name="$1" kind="$2" src="$3" inst="$4" status="$5"
  local label="row name=$name kind=$kind"
  local needle
  needle=$(printf '%s\t%s\t%s\t%s\t%s' "$name" "$kind" "$src" "$inst" "$status")
  if grep -qFx "$needle" "$FIXT/out.tsv"; then
    pass "$label → $status"
  else
    fail "$label" "expected '$needle' not found; got: $(grep "$name" "$FIXT/out.tsv" || echo NONE)"
  fi
}

assert_row bumped-newer       core  "2026.05.02+aaaaaa"  "2026.04.01+bbbbbb"  bumped
assert_row bumped-older       core  "2026.04.01+aaaaaa"  "2026.05.02+bbbbbb"  bumped
assert_row newcomer           core  "2026.05.02+cccccc"  ""                   new
assert_row malformed          core  ""                   "2026.04.01+ddddddd" malformed
assert_row same-version       core  "2026.05.02+eeeeee"  "2026.05.02+eeeeee"  unchanged
assert_row addon-installed    addon "2026.05.02+ff1111"  "2026.05.02+ff1111"  unchanged
assert_row addon-not-installed addon "2026.05.02+ff2222"  ""                   new

# Total row count = 5 core + 2 addon = 7
LINE_COUNT=$(wc -l < "$FIXT/out.tsv")
if [ "$LINE_COUNT" = "7" ]; then
  pass "row count = 7 (5 core + 2 addon)"
else
  fail "row count" "expected 7 got $LINE_COUNT; full output:
$(cat "$FIXT/out.tsv")"
fi

# Tab-delimited 5-field invariant.
NON5=$(awk -F'\t' 'NF != 5' "$FIXT/out.tsv" | wc -l)
if [ "$NON5" = "0" ]; then
  pass "every row is exactly 5 tab-delimited fields"
else
  fail "field count invariant" "$NON5 rows have NF != 5"
fi

# Real-repo smoke check: run against the actual REPO_ROOT and assert the
# row count is at least 26 core + 3 addon = 29.
CLAUDE_PROJECT_DIR="$REPO_ROOT" bash "$HELPER" "$REPO_ROOT" > "$FIXT/real.tsv" 2>"$FIXT/real-err.txt"
REAL_RC=$?
if [ "$REAL_RC" -ne 0 ]; then
  fail "real-repo smoke: helper exit code 0" "rc=$REAL_RC stderr=$(cat "$FIXT/real-err.txt")"
else
  REAL_LINES=$(wc -l < "$FIXT/real.tsv")
  if [ "$REAL_LINES" -ge 29 ]; then
    pass "real-repo smoke: $REAL_LINES rows (≥ 26 core + 3 addon = 29)"
  else
    fail "real-repo smoke row count" "expected ≥29 got $REAL_LINES"
  fi
  CORE_COUNT=$(awk -F'\t' '$2 == "core"' "$FIXT/real.tsv" | wc -l)
  ADDON_COUNT=$(awk -F'\t' '$2 == "addon"' "$FIXT/real.tsv" | wc -l)
  if [ "$CORE_COUNT" -ge 26 ] && [ "$ADDON_COUNT" -ge 3 ]; then
    pass "real-repo smoke: core=$CORE_COUNT (≥26) addon=$ADDON_COUNT (≥3)"
  else
    fail "real-repo smoke: kind split" "core=$CORE_COUNT addon=$ADDON_COUNT"
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
