#!/bin/bash
# Tests for scripts/frontmatter-get.sh and scripts/frontmatter-set.sh.
# Run from repo root: bash tests/test-frontmatter-helpers.sh
#
# Coverage targets the spec list (Phase 2.4 in plans/SKILL_VERSIONING.md):
#   - get top-level / dotted / missing key / malformed / no frontmatter
#   - value-with-spaces / value-with-quotes / empty value
#   - stdin via `-` (4 cases)
#   - block-scalar read
#   - set insert into existing parent / new parent / update existing
#     / idempotent no-op / value-with-special-chars / malformed
#   - block-scalar write attempt exits 3
#   - round-trip get→set→get (5 cases)
#   - in-place atomicity (mode preservation)

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GET="$REPO_ROOT/scripts/frontmatter-get.sh"
SET="$REPO_ROOT/scripts/frontmatter-set.sh"
FIX="$REPO_ROOT/tests/fixtures/frontmatter"

WORK="/tmp/zskills-tests/$(basename "$REPO_ROOT")/frontmatter"
rm -rf "$WORK"
mkdir -p "$WORK"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

assert_eq() {
  # $1 = label, $2 = expected, $3 = actual
  if [ "$2" = "$3" ]; then
    pass "$1"
  else
    fail "$1 — expected '$2' got '$3'"
  fi
}

assert_exit() {
  # $1 = label, $2 = expected exit, $3 = actual exit
  if [ "$2" -eq "$3" ]; then
    pass "$1 (exit=$3)"
  else
    fail "$1 — expected exit $2, got $3"
  fi
}

echo "=== frontmatter-get / frontmatter-set tests ==="

# --- frontmatter-get: top-level ---
out=$(bash "$GET" "$FIX/simple.md" name)
assert_eq "get top-level (name)" "simple" "$out"

out=$(bash "$GET" "$FIX/simple.md" description)
assert_eq "get top-level (description)" "A short description." "$out"

# --- frontmatter-get: dotted ---
out=$(bash "$GET" "$FIX/dotted.md" metadata.version)
assert_eq "get dotted (metadata.version)" "2026.04.30+abc123" "$out"

out=$(bash "$GET" "$FIX/dotted.md" metadata.author)
assert_eq "get dotted (metadata.author)" "Z" "$out"

# --- frontmatter-get: missing key (exit 1) ---
out=$(bash "$GET" "$FIX/simple.md" nope 2>/dev/null); rc=$?
assert_exit "get missing key exits 1" 1 "$rc"

out=$(bash "$GET" "$FIX/dotted.md" metadata.absent 2>/dev/null); rc=$?
assert_exit "get missing dotted child exits 1" 1 "$rc"

# --- frontmatter-get: malformed (exit 2) ---
out=$(bash "$GET" "$FIX/no-frontmatter.md" name 2>/dev/null); rc=$?
assert_exit "get on no-frontmatter exits 2" 2 "$rc"

out=$(bash "$GET" "$FIX/unclosed.md" name 2>/dev/null); rc=$?
assert_exit "get on unclosed frontmatter exits 2" 2 "$rc"

# --- frontmatter-get: value-with-spaces ---
out=$(bash "$GET" "$FIX/quoted-spaces.md" name)
assert_eq "get value with spaces" "value with spaces" "$out"

# --- frontmatter-get: value-with-quotes (single inside double) ---
out=$(bash "$GET" "$FIX/quoted-spaces.md" quoted)
assert_eq "get value containing single quotes" "contains 'single' inside" "$out"

# --- frontmatter-get: empty value ---
out=$(bash "$GET" "$FIX/simple.md" empty_value)
assert_eq "get empty quoted value" "" "$out"

# --- frontmatter-get: stdin (4 cases) ---
out=$(cat "$FIX/simple.md" | bash "$GET" - name)
assert_eq "stdin top-level key" "simple" "$out"

out=$(cat "$FIX/dotted.md" | bash "$GET" - metadata.version)
assert_eq "stdin dotted key" "2026.04.30+abc123" "$out"

out=$(cat "$FIX/simple.md" | bash "$GET" - missing 2>/dev/null); rc=$?
assert_exit "stdin missing key exits 1" 1 "$rc"

out=$(cat "$FIX/no-frontmatter.md" | bash "$GET" - name 2>/dev/null); rc=$?
assert_exit "stdin malformed exits 2" 2 "$rc"

# --- frontmatter-get: block-scalar read ---
out=$(bash "$GET" "$FIX/block-scalar.md" description)
expected="This is a long block-scalar description that spans multiple lines and should be joined with single spaces on read."
assert_eq "block-scalar read joins continuation lines" "$expected" "$out"

# --- frontmatter-set: insert into existing parent ---
cp "$FIX/dotted.md" "$WORK/insert-existing.md"
bash "$SET" "$WORK/insert-existing.md" metadata.notes "first-note"
out=$(bash "$GET" "$WORK/insert-existing.md" metadata.notes)
assert_eq "set insert child into existing parent" "first-note" "$out"
# Sanity: existing siblings preserved.
out=$(bash "$GET" "$WORK/insert-existing.md" metadata.version)
assert_eq "  …existing sibling preserved (version)" "2026.04.30+abc123" "$out"

# --- frontmatter-set: insert with new parent ---
cp "$FIX/no-parent.md" "$WORK/insert-newparent.md"
bash "$SET" "$WORK/insert-newparent.md" metadata.version "2026.04.30+ffffff"
out=$(bash "$GET" "$WORK/insert-newparent.md" metadata.version)
assert_eq "set creates new parent block + child" "2026.04.30+ffffff" "$out"

# --- frontmatter-set: update existing ---
cp "$FIX/dotted.md" "$WORK/update.md"
bash "$SET" "$WORK/update.md" metadata.version "2026.05.01+999999"
out=$(bash "$GET" "$WORK/update.md" metadata.version)
assert_eq "set updates existing dotted value" "2026.05.01+999999" "$out"

# --- frontmatter-set: idempotent no-op ---
cp "$FIX/dotted.md" "$WORK/idempotent.md"
checksum_before=$(sha256sum "$WORK/idempotent.md" | cut -d' ' -f1)
bash "$SET" "$WORK/idempotent.md" metadata.version "2026.04.30+abc123"
checksum_after=$(sha256sum "$WORK/idempotent.md" | cut -d' ' -f1)
assert_eq "set idempotent no-op (file unchanged)" "$checksum_before" "$checksum_after"

# --- frontmatter-set: value-with-special-chars ---
cp "$FIX/dotted.md" "$WORK/special.md"
bash "$SET" "$WORK/special.md" metadata.version "2026.04.30+aB3.+- "
out=$(bash "$GET" "$WORK/special.md" metadata.version)
assert_eq "set value with special chars (round-trip)" "2026.04.30+aB3.+- " "$out"

# --- frontmatter-set: malformed (exit 2) ---
cp "$FIX/no-frontmatter.md" "$WORK/malformed.md"
bash "$SET" "$WORK/malformed.md" name "x" 2>/dev/null; rc=$?
assert_exit "set on no-frontmatter exits 2" 2 "$rc"

# --- frontmatter-set: block-scalar write attempt (exit 3) ---
cp "$FIX/block-scalar.md" "$WORK/blockscalar-write.md"
bash "$SET" "$WORK/blockscalar-write.md" description "single-line replacement" 2>/dev/null; rc=$?
assert_exit "set on block-scalar key exits 3" 3 "$rc"

# --- Round-trip property: 5 cases (set+get returns the value exactly) ---
for triplet in "name:rt-1:simple-value" "name:rt-2:value with spaces" \
               "metadata.version:rt-3:2026.04.30+abc123" \
               "metadata.version:rt-4:2026.05.01+ZZZZ12" \
               "name:rt-5:plain"; do
  IFS=":" read -r key label val <<<"$triplet"
  cp "$FIX/dotted.md" "$WORK/$label.md"
  bash "$SET" "$WORK/$label.md" "$key" "$val"
  out=$(bash "$GET" "$WORK/$label.md" "$key")
  assert_eq "round-trip ($label) — $key" "$val" "$out"
done

# --- In-place atomicity / mode preservation ---
cp "$FIX/dotted.md" "$WORK/mode.md"
chmod 600 "$WORK/mode.md"
mode_before=$(stat -c '%a' "$WORK/mode.md")
bash "$SET" "$WORK/mode.md" metadata.version "2026.05.02+mode01"
mode_after=$(stat -c '%a' "$WORK/mode.md")
assert_eq "in-place set preserves file mode" "$mode_before" "$mode_after"

echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"
if [ "$FAIL_COUNT" -gt 0 ]; then exit 1; fi
exit 0
