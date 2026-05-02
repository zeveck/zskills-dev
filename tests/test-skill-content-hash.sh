#!/bin/bash
# Tests for scripts/skill-content-hash.sh.
# Run from repo root: bash tests/test-skill-content-hash.sh
#
# Coverage targets the spec list (Phase 2.5 in plans/SKILL_VERSIONING.md):
#   1. hash matches ^[0-9a-f]{6}$
#   2. determinism — twice in a row produces same hash
#   3. whitespace-only edit produces same hash (normalisation)
#   4. body edit produces a different hash
#   5. file addition (mode-bearing helper) produces a different hash
#   6. missing SKILL.md exits 1
#   7. dotfile invariance — adding `.DS_Store` does NOT change hash
#   8. block-scalar continuation safety — a `description-extra: >-`
#      continuation containing literal `version: "..."` text is NOT
#      redacted (different content → different hash from a fixture
#      where the same text sits OUTSIDE the block scalar)

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HASH="$REPO_ROOT/scripts/skill-content-hash.sh"
FIX="$REPO_ROOT/tests/fixtures/skill-versioning"

WORK="/tmp/zskills-tests/$(basename "$REPO_ROOT")/skill-versioning"
rm -rf "$WORK"
mkdir -p "$WORK"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

echo "=== skill-content-hash.sh tests ==="

# 1. Hash format on the basic fixture.
h1=$(bash "$HASH" "$FIX/basic")
if [[ "$h1" =~ ^[0-9a-f]{6}$ ]]; then
  pass "hash format ^[0-9a-f]{6}$ ($h1)"
else
  fail "hash format — expected 6 hex chars, got '$h1'"
fi

# 2. Determinism.
h2=$(bash "$HASH" "$FIX/basic")
if [ "$h1" = "$h2" ]; then
  pass "determinism (basic) — $h1 == $h2"
else
  fail "determinism (basic) — $h1 != $h2"
fi

# 3. Whitespace-only edit on body produces SAME hash.
cp -r "$FIX/with-files" "$WORK/whitespace"
hwa=$(bash "$HASH" "$WORK/whitespace")
# Add trailing whitespace to body lines.
sed -i 's/Body content./Body content.   /' "$WORK/whitespace/SKILL.md"
sed -i 's/$/   /' "$WORK/whitespace/scripts/helper.sh"
hwb=$(bash "$HASH" "$WORK/whitespace")
if [ "$hwa" = "$hwb" ]; then
  pass "whitespace-only edit — same hash ($hwa)"
else
  fail "whitespace-only edit — hashes differ ($hwa vs $hwb)"
fi

# 4. Body edit produces DIFFERENT hash.
cp -r "$FIX/with-files" "$WORK/body-edit"
hba=$(bash "$HASH" "$WORK/body-edit")
sed -i 's/Body content./Different body content./' "$WORK/body-edit/SKILL.md"
hbb=$(bash "$HASH" "$WORK/body-edit")
if [ "$hba" != "$hbb" ]; then
  pass "body edit — different hash ($hba → $hbb)"
else
  fail "body edit — hash unchanged ($hba)"
fi

# 5. File addition produces DIFFERENT hash.
cp -r "$FIX/basic" "$WORK/add-file"
hfa=$(bash "$HASH" "$WORK/add-file")
mkdir -p "$WORK/add-file/scripts"
echo "echo new" > "$WORK/add-file/scripts/new.sh"
hfb=$(bash "$HASH" "$WORK/add-file")
if [ "$hfa" != "$hfb" ]; then
  pass "file addition — different hash ($hfa → $hfb)"
else
  fail "file addition — hash unchanged ($hfa)"
fi

# 6. Missing SKILL.md exits 1.
bash "$HASH" "$FIX/no-skill-md" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 1 ]; then
  pass "missing SKILL.md exits 1"
else
  fail "missing SKILL.md — expected exit 1, got $rc"
fi

# 7. Dotfile invariance — adding .DS_Store / .landed does NOT change hash.
cp -r "$FIX/with-dotfile" "$WORK/dotfile"
hda=$(bash "$HASH" "$WORK/dotfile")
echo "junk" > "$WORK/dotfile/.DS_Store"
echo "junk" > "$WORK/dotfile/.landed"
mkdir -p "$WORK/dotfile/scripts"
echo "junk" > "$WORK/dotfile/.zskills-tracked"
hdb=$(bash "$HASH" "$WORK/dotfile")
if [ "$hda" = "$hdb" ]; then
  pass "dotfile invariance — same hash with/without .DS_Store ($hda)"
else
  fail "dotfile invariance — hashes differ ($hda vs $hdb)"
fi

# 8. Block-scalar continuation safety. The fixture's frontmatter
#    contains `description-extra: >-` whose continuation lines include
#    a literal `version: "should-not-be-redacted"` text. The redactor
#    must NOT touch it. We assert this two ways:
#      (a) hash is deterministic on this fixture,
#      (b) tweaking the continuation `version:` text DOES change the
#          hash (proving the redactor preserved it byte-for-byte rather
#          than rewriting it to `<REDACTED>`).
hba1=$(bash "$HASH" "$FIX/block-scalar-trap")
hba2=$(bash "$HASH" "$FIX/block-scalar-trap")
if [ "$hba1" != "$hba2" ]; then
  fail "block-scalar fixture — non-deterministic ($hba1 vs $hba2)"
fi
cp -r "$FIX/block-scalar-trap" "$WORK/bst-mutated"
sed -i 's/should-not-be-redacted/different-value/' "$WORK/bst-mutated/SKILL.md"
hba3=$(bash "$HASH" "$WORK/bst-mutated")
if [ "$hba1" != "$hba3" ]; then
  pass "block-scalar continuation NOT redacted — text change shows up ($hba1 → $hba3)"
else
  fail "block-scalar continuation appears redacted — text change had no effect ($hba1)"
fi

echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"
if [ "$FAIL_COUNT" -gt 0 ]; then exit 1; fi
exit 0
