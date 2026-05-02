#!/bin/bash
# Tests for skills/update-zskills/scripts/json-set-string-field.sh.
#
# Phase 5a.7 (plans/SKILL_VERSIONING.md). Every case validates the
# resulting file via python3 json.load() to catch malformed-JSON output
# that grep-based assertions would miss.
#
# Run from repo root: bash tests/test-json-set-string-field.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$REPO_ROOT/skills/update-zskills/scripts/json-set-string-field.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

if [ ! -f "$HELPER" ]; then
  fail "helper exists at expected path" "$HELPER missing"
  printf 'Results: %d passed, %d failed (of %d)\n' \
    "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"
  exit 1
fi

# JSON validator. Reads stdin; exit 0 = valid JSON.
validate_json() {
  python3 -c 'import sys, json; json.load(sys.stdin)' < "$1"
}

# Read a top-level string field via python3, for round-trip checks.
read_field() {
  local file="$1" key="$2"
  python3 -c "import sys, json; d = json.load(open(sys.argv[1])); v = d.get(sys.argv[2]); sys.stdout.write('' if v is None else v)" \
    "$file" "$key"
}

WORK=$(mktemp -d /tmp/zskills-jsf-XXXXXX)
trap 'rm -rf "$WORK"' EXIT

# --- Case 1: Insert into empty {} object (multi-line) ---------------------
echo "=== Case 1: insert into empty {} object → valid JSON, no trailing comma ==="
F1="$WORK/c1.json"
cat > "$F1" <<'JSON'
{
}
JSON
bash "$HELPER" "$F1" zskills_version "2026.05.02+abc123" \
  && validate_json "$F1" \
  && [ "$(read_field "$F1" zskills_version)" = "2026.05.02+abc123" ] \
  && pass "Case 1: insert into empty object" \
  || fail "Case 1" "got: $(cat "$F1")"

# --- Case 2: Insert into non-empty object ---------------------------------
echo "=== Case 2: insert into non-empty object → comma added, no trailing comma ==="
F2="$WORK/c2.json"
cat > "$F2" <<'JSON'
{
  "timezone": "UTC"
}
JSON
bash "$HELPER" "$F2" zskills_version "2026.05.02+abc123" \
  && validate_json "$F2" \
  && [ "$(read_field "$F2" zskills_version)" = "2026.05.02+abc123" ] \
  && [ "$(read_field "$F2" timezone)" = "UTC" ] \
  && pass "Case 2: insert into non-empty object" \
  || fail "Case 2" "got: $(cat "$F2")"

# --- Case 3: Update LAST field --------------------------------------------
echo "=== Case 3: update existing LAST field → valid JSON, no trailing comma ==="
F3="$WORK/c3.json"
cat > "$F3" <<'JSON'
{
  "timezone": "UTC",
  "zskills_version": "2026.04.01+xxxxxx"
}
JSON
bash "$HELPER" "$F3" zskills_version "2026.05.02+abc123" \
  && validate_json "$F3" \
  && [ "$(read_field "$F3" zskills_version)" = "2026.05.02+abc123" ] \
  && pass "Case 3: update last field" \
  || fail "Case 3" "got: $(cat "$F3")"

# --- Case 4: Update MIDDLE field (preserves trailing comma) --------------
echo "=== Case 4: update middle field with trailing comma → comma preserved ==="
F4="$WORK/c4.json"
cat > "$F4" <<'JSON'
{
  "timezone": "UTC",
  "zskills_version": "2026.04.01+xxxxxx",
  "project_name": "demo"
}
JSON
bash "$HELPER" "$F4" zskills_version "2026.05.02+abc123" \
  && validate_json "$F4" \
  && [ "$(read_field "$F4" zskills_version)" = "2026.05.02+abc123" ] \
  && [ "$(read_field "$F4" project_name)" = "demo" ] \
  && grep -q '"zskills_version": "2026.05.02+abc123",' "$F4" \
  && pass "Case 4: update middle field, trailing comma preserved" \
  || fail "Case 4" "got: $(cat "$F4")"

# --- Case 5: Idempotent no-change ----------------------------------------
echo "=== Case 5: set field to same value twice → file unchanged ==="
F5="$WORK/c5.json"
cat > "$F5" <<'JSON'
{
  "zskills_version": "2026.05.02+abc123"
}
JSON
bash "$HELPER" "$F5" zskills_version "2026.05.02+abc123"
SNAP1=$(cat "$F5")
bash "$HELPER" "$F5" zskills_version "2026.05.02+abc123"
SNAP2=$(cat "$F5")
if validate_json "$F5" && [ "$SNAP1" = "$SNAP2" ]; then
  pass "Case 5: idempotent — same content after second invocation"
else
  fail "Case 5" "snap1='$SNAP1' snap2='$SNAP2'"
fi

# --- Case 6: Value with `&` and `\1` -------------------------------------
# Plan AC line 1229 calls for "Value-with-&-and-\1 round-trip — verifies
# awk-replacement doesn't expand metacharacters." The intent: confirm
# awk treats `&` and `\1` as literal bytes (NOT sub()/gsub() back-references
# nor `-v` escape sequences). We split the case in two:
#
#   6a. `&` round-trip via JSON parse — valid JSON content.
#   6b. `\1` byte-preservation via grep — `\1` written to file is valid
#       sequence of bytes but NOT a valid JSON escape, so json.load() can't
#       roundtrip it. Bytes-on-disk check still proves no expansion.
echo "=== Case 6a: value containing & → metacharacter-clean round-trip via JSON ==="
F6="$WORK/c6.json"
cat > "$F6" <<'JSON'
{
  "tag": "old"
}
JSON
AMP_VAL='2026.05.02+abc&def&xyz'
bash "$HELPER" "$F6" tag "$AMP_VAL"
ROUNDTRIP=$(read_field "$F6" tag)
if validate_json "$F6" && [ "$ROUNDTRIP" = "$AMP_VAL" ]; then
  pass "Case 6a: & metacharacter preserved literally (sub() back-ref untriggered)"
else
  fail "Case 6a" "expected '$AMP_VAL' got '$ROUNDTRIP' file=$(cat "$F6")"
fi

echo "=== Case 6b: value containing \\1 → bytes preserved (no -v escape expansion) ==="
F6B="$WORK/c6b.json"
cat > "$F6B" <<'JSON'
{
  "tag": "old"
}
JSON
BSLASH_VAL='abc\1xyz'
bash "$HELPER" "$F6B" tag "$BSLASH_VAL"
# Bytes-on-disk check. We expect the literal sequence `\1` to appear after
# `tag": "`. If `-v` escape processing fired, the byte would be missing.
# This is the canonical regression check from refine-plan F-R2-3.
if grep -F 'abc\1xyz' "$F6B" >/dev/null; then
  pass "Case 6b: \\1 bytes preserved verbatim (no -v escape expansion)"
else
  fail "Case 6b: \\1 escape expansion" "file=$(cat "$F6B")"
fi

# --- Case 7: Value with `|` (embedded quotes are out-of-scope per Non-Goals) ---
echo "=== Case 7: value with | → preserved (embedded \" is out-of-scope) ==="
F7="$WORK/c7.json"
cat > "$F7" <<'JSON'
{
  "pipe": "x"
}
JSON
PIPE_VAL='2026|05|02+abc'
bash "$HELPER" "$F7" pipe "$PIPE_VAL"
ROUNDTRIP=$(read_field "$F7" pipe)
if validate_json "$F7" && [ "$ROUNDTRIP" = "$PIPE_VAL" ]; then
  pass "Case 7: | preserved"
else
  fail "Case 7: | preserved" "expected '$PIPE_VAL' got '$ROUNDTRIP' file=$(cat "$F7")"
fi

# Embedded-quote subcase: per Non-Goals (refine-plan F-DA-R2-3), v1's
# contract is "no embedded quotes". The helper must NOT silently corrupt;
# either round-trip or non-zero exit is acceptable.
F7b="$WORK/c7b.json"
cat > "$F7b" <<'JSON'
{
  "x": "old"
}
JSON
QUOTED_VAL='has"quote'
bash "$HELPER" "$F7b" x "$QUOTED_VAL"
RC7B=$?
if [ "$RC7B" -ne 0 ] || validate_json "$F7b"; then
  pass "Case 7b: embedded-quote either errors or stays valid (no silent corruption)"
else
  fail "Case 7b: embedded-quote silent corruption" "rc=$RC7B file=$(cat "$F7b")"
fi

# --- Case 8: File-mode preservation --------------------------------------
echo "=== Case 8: file perms preserved (0644 in, 0644 out) ==="
F8="$WORK/c8.json"
cat > "$F8" <<'JSON'
{
  "timezone": "UTC"
}
JSON
chmod 0644 "$F8"
bash "$HELPER" "$F8" timezone "America/New_York"
PERMS_AFTER=$(stat -c '%a' "$F8" 2>/dev/null || stat -f '%Lp' "$F8")
if validate_json "$F8" && [ "$PERMS_AFTER" = "644" ]; then
  pass "Case 8: 0644 perms preserved"
else
  fail "Case 8: perms" "after=$PERMS_AFTER, file=$(cat "$F8")"
fi

# --- Case 9: Malformed JSON (no closing brace) → exit non-zero, file unchanged ---
echo "=== Case 9: malformed JSON (no closing brace) → exit non-zero, file unchanged ==="
F9="$WORK/c9.json"
cat > "$F9" <<'JSON'
{
  "timezone": "UTC"
JSON
SNAP_BEFORE=$(cat "$F9")
bash "$HELPER" "$F9" zskills_version "2026.05.02+abc123" 2>/dev/null
RC9=$?
SNAP_AFTER=$(cat "$F9")
if [ "$RC9" -ne 0 ] && [ "$SNAP_BEFORE" = "$SNAP_AFTER" ]; then
  pass "Case 9: malformed JSON → non-zero exit, file untouched"
else
  fail "Case 9: malformed handling" "rc=$RC9 before='$SNAP_BEFORE' after='$SNAP_AFTER'"
fi

# --- Case 10: Single-line `{}` (out of scope per v1 limitation) ----------
echo "=== Case 10: single-line {} → out-of-scope per v1 (helper exits non-zero) ==="
F10="$WORK/c10.json"
echo '{}' > "$F10"
SNAP_BEFORE=$(cat "$F10")
bash "$HELPER" "$F10" zskills_version "2026.05.02+abc123" 2>/dev/null
RC10=$?
SNAP_AFTER=$(cat "$F10")
# Documented v1 limitation: single-line `{}` lacks a standalone closing-brace
# line, so the awk regex `^[[:space:]]*\}[[:space:]]*$` finds no match.
# Helper must either exit non-zero OR leave the file as still-valid JSON; it
# must NOT silently corrupt.
if [ "$RC10" -ne 0 ] || validate_json "$F10"; then
  pass "Case 10: single-line {} either errors or stays valid (no silent corruption)"
else
  fail "Case 10: single-line {} silent corruption" \
    "rc=$RC10 before='$SNAP_BEFORE' after='$SNAP_AFTER'"
fi

# --- Case 11: Update where value contains the key name as substring ------
echo "=== Case 11: value contains key as substring → regex anchors to value, not substring ==="
F11="$WORK/c11.json"
cat > "$F11" <<'JSON'
{
  "version": "this-version-string"
}
JSON
bash "$HELPER" "$F11" version "2026.05.02+abc123" \
  && validate_json "$F11" \
  && [ "$(read_field "$F11" version)" = "2026.05.02+abc123" ] \
  && pass "Case 11: regex anchors correctly when value contains key substring" \
  || fail "Case 11" "got: $(cat "$F11")"

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
