#!/bin/bash
# Tests for skills/update-zskills/scripts/zskills-resolve-config.sh —
# the canonical config-resolution helper introduced in
# plans/SKILL_FILE_DRIFT_FIX.md Phase 1.
#
# Covers the 7 ACs from the phase doc + Phase 5a.2's 7th-var case
# (ZSKILLS_VERSION resolution from a top-level `zskills_version` field).
#   1. Synthetic-fixture: temp dir with a config containing timezone,
#      testing.full_cmd, commit.co_author. Source helper; assert
#      $TIMEZONE/$FULL_TEST_CMD/$COMMIT_CO_AUTHOR populated;
#      $UNIT_TEST_CMD/$DEV_SERVER_CMD/$TEST_OUTPUT_FILE/$ZSKILLS_VERSION empty.
#   2. Idempotency: source twice; vars unchanged on second source.
#   3. Empty-config: temp dir without config; all 6 vars empty.
#   4. Malformed-config: broken JSON; no abort, vars stay empty.
#   5. CLAUDE_PROJECT_DIR-switching: tmp1 with London, tmp2 with Tokyo;
#      switching $CLAUDE_PROJECT_DIR in a fresh subshell yields the
#      correct timezone for each.
#   6. references/canonical-config-prelude.md exists with 7 sections.
#   7. Install integrity: helper script is present in the
#      .claude/skills/update-zskills/scripts/ mirror (the install
#      location consumers receive via /update-zskills's skill mirror).
#
# Run from repo root: bash tests/test-zskills-resolve-config.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$REPO_ROOT/skills/update-zskills/scripts/zskills-resolve-config.sh"
MIRROR_HELPER="$REPO_ROOT/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
PRELUDE_DOC="$REPO_ROOT/references/canonical-config-prelude.md"

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

# --- Test 1: synthetic-fixture (AC1) ----------------------------------------
echo "=== Test 1: synthetic fixture — populated and empty vars correctly resolved ==="
T1=$(mktemp -d /tmp/zskills-resolve-cfg-t1-XXXXXX)
mkdir -p "$T1/.claude"
cat > "$T1/.claude/zskills-config.json" <<'CONFIG'
{
  "timezone": "Europe/London",
  "testing": {
    "full_cmd": "FIXTURE_CMD"
  },
  "commit": {
    "co_author": "Test Author <test@example.com>"
  }
}
CONFIG

# Source in a subshell so var pollution from the outer test process
# (and any previous test files) doesn't leak in or out.
RESULT=$(
  CLAUDE_PROJECT_DIR="$T1" \
  bash -c '. "'"$HELPER"'" && printf "%s\n" "$TIMEZONE" "$FULL_TEST_CMD" "$COMMIT_CO_AUTHOR" "$UNIT_TEST_CMD" "$DEV_SERVER_CMD" "$TEST_OUTPUT_FILE" "$ZSKILLS_VERSION"'
)
T1_TIMEZONE=$(printf '%s\n' "$RESULT" | sed -n '1p')
T1_FULL=$(printf '%s\n' "$RESULT" | sed -n '2p')
T1_COAUTHOR=$(printf '%s\n' "$RESULT" | sed -n '3p')
T1_UNIT=$(printf '%s\n' "$RESULT" | sed -n '4p')
T1_DEV=$(printf '%s\n' "$RESULT" | sed -n '5p')
T1_OUTFILE=$(printf '%s\n' "$RESULT" | sed -n '6p')
T1_ZVER=$(printf '%s\n' "$RESULT" | sed -n '7p')

[ "$T1_TIMEZONE" = "Europe/London" ] \
  && pass "Test 1a: \$TIMEZONE = 'Europe/London'" \
  || fail "Test 1a: \$TIMEZONE" "got '$T1_TIMEZONE'"
[ "$T1_FULL" = "FIXTURE_CMD" ] \
  && pass "Test 1b: \$FULL_TEST_CMD = 'FIXTURE_CMD'" \
  || fail "Test 1b: \$FULL_TEST_CMD" "got '$T1_FULL'"
[ "$T1_COAUTHOR" = "Test Author <test@example.com>" ] \
  && pass "Test 1c: \$COMMIT_CO_AUTHOR = 'Test Author <test@example.com>'" \
  || fail "Test 1c: \$COMMIT_CO_AUTHOR" "got '$T1_COAUTHOR'"
[ -z "$T1_UNIT" ] \
  && pass "Test 1d: \$UNIT_TEST_CMD empty (not in fixture)" \
  || fail "Test 1d: \$UNIT_TEST_CMD" "got '$T1_UNIT'"
[ -z "$T1_DEV" ] \
  && pass "Test 1e: \$DEV_SERVER_CMD empty (not in fixture)" \
  || fail "Test 1e: \$DEV_SERVER_CMD" "got '$T1_DEV'"
[ -z "$T1_OUTFILE" ] \
  && pass "Test 1f: \$TEST_OUTPUT_FILE empty (not in fixture)" \
  || fail "Test 1f: \$TEST_OUTPUT_FILE" "got '$T1_OUTFILE'"
[ -z "$T1_ZVER" ] \
  && pass "Test 1g: \$ZSKILLS_VERSION empty (not in fixture)" \
  || fail "Test 1g: \$ZSKILLS_VERSION" "got '$T1_ZVER'"

rm -rf "$T1"

# --- Test 2: idempotency (AC2) ----------------------------------------------
echo ""
echo "=== Test 2: idempotency — second source yields the same vars ==="
T2=$(mktemp -d /tmp/zskills-resolve-cfg-t2-XXXXXX)
mkdir -p "$T2/.claude"
cat > "$T2/.claude/zskills-config.json" <<'CONFIG'
{
  "timezone": "Europe/London",
  "testing": {
    "unit_cmd": "U",
    "full_cmd": "F",
    "output_file": "out.txt"
  },
  "dev_server": {
    "cmd": "DEV"
  },
  "commit": {
    "co_author": "X <x@x>"
  }
}
CONFIG

RESULT2=$(
  CLAUDE_PROJECT_DIR="$T2" \
  bash -c '
    . "'"$HELPER"'"
    A_TIMEZONE="$TIMEZONE" A_FULL="$FULL_TEST_CMD" A_UNIT="$UNIT_TEST_CMD"
    A_DEV="$DEV_SERVER_CMD" A_OUTFILE="$TEST_OUTPUT_FILE" A_CO="$COMMIT_CO_AUTHOR"
    . "'"$HELPER"'"
    B_TIMEZONE="$TIMEZONE" B_FULL="$FULL_TEST_CMD" B_UNIT="$UNIT_TEST_CMD"
    B_DEV="$DEV_SERVER_CMD" B_OUTFILE="$TEST_OUTPUT_FILE" B_CO="$COMMIT_CO_AUTHOR"
    if [ "$A_TIMEZONE" = "$B_TIMEZONE" ] && [ "$A_FULL" = "$B_FULL" ] \
      && [ "$A_UNIT" = "$B_UNIT" ] && [ "$A_DEV" = "$B_DEV" ] \
      && [ "$A_OUTFILE" = "$B_OUTFILE" ] && [ "$A_CO" = "$B_CO" ]; then
      echo "EQUAL"
    else
      echo "DIFF: A($A_TIMEZONE,$A_FULL,$A_UNIT,$A_DEV,$A_OUTFILE,$A_CO) vs B($B_TIMEZONE,$B_FULL,$B_UNIT,$B_DEV,$B_OUTFILE,$B_CO)"
    fi
  '
)
[ "$RESULT2" = "EQUAL" ] \
  && pass "Test 2: vars unchanged on second source" \
  || fail "Test 2: idempotency" "$RESULT2"

rm -rf "$T2"

# --- Test 3: empty-config (AC3) ---------------------------------------------
echo ""
echo "=== Test 3: empty-config — no config file, all 7 vars empty strings ==="
T3=$(mktemp -d /tmp/zskills-resolve-cfg-t3-XXXXXX)
# Intentionally no .claude/zskills-config.json.

RESULT3=$(
  CLAUDE_PROJECT_DIR="$T3" \
  bash -c '. "'"$HELPER"'" && printf "%s\n" "$TIMEZONE" "$FULL_TEST_CMD" "$UNIT_TEST_CMD" "$DEV_SERVER_CMD" "$TEST_OUTPUT_FILE" "$COMMIT_CO_AUTHOR" "$ZSKILLS_VERSION"'
)
RC3=$?

if [ "$RC3" -eq 0 ]; then
  pass "Test 3a: source rc=0 even with no config file"
else
  fail "Test 3a: source rc" "got rc=$RC3"
fi

ALL_EMPTY=1
i=1
while [ $i -le 7 ]; do
  v=$(printf '%s\n' "$RESULT3" | sed -n "${i}p")
  if [ -n "$v" ]; then
    ALL_EMPTY=0
    break
  fi
  i=$((i + 1))
done
if [ "$ALL_EMPTY" = 1 ]; then
  pass "Test 3b: all 7 vars are empty strings"
else
  fail "Test 3b: all vars empty" "got: $RESULT3"
fi

rm -rf "$T3"

# --- Test 4: malformed-config (AC4) -----------------------------------------
echo ""
echo "=== Test 4: malformed JSON — no abort, vars stay empty ==="
T4=$(mktemp -d /tmp/zskills-resolve-cfg-t4-XXXXXX)
mkdir -p "$T4/.claude"
cat > "$T4/.claude/zskills-config.json" <<'BROKEN'
{ "testing": broken-not-quoted, "timezone":
BROKEN

RESULT4=$(
  CLAUDE_PROJECT_DIR="$T4" \
  bash -c '. "'"$HELPER"'" && printf "%s\n" "$TIMEZONE" "$FULL_TEST_CMD" "$UNIT_TEST_CMD" "$DEV_SERVER_CMD" "$TEST_OUTPUT_FILE" "$COMMIT_CO_AUTHOR" "$ZSKILLS_VERSION"'
)
RC4=$?

if [ "$RC4" -eq 0 ]; then
  pass "Test 4a: source rc=0 even with malformed JSON"
else
  fail "Test 4a: source rc on malformed JSON" "got rc=$RC4"
fi

ALL_EMPTY4=1
i=1
while [ $i -le 7 ]; do
  v=$(printf '%s\n' "$RESULT4" | sed -n "${i}p")
  if [ -n "$v" ]; then
    ALL_EMPTY4=0
    break
  fi
  i=$((i + 1))
done
if [ "$ALL_EMPTY4" = 1 ]; then
  pass "Test 4b: all 7 vars empty on malformed JSON"
else
  fail "Test 4b: all vars empty" "got: $RESULT4"
fi

rm -rf "$T4"

# --- Test 5: CLAUDE_PROJECT_DIR-switching (AC5) -----------------------------
echo ""
echo "=== Test 5: CLAUDE_PROJECT_DIR-switching — different config per project ==="
T5A=$(mktemp -d /tmp/zskills-resolve-cfg-t5a-XXXXXX)
T5B=$(mktemp -d /tmp/zskills-resolve-cfg-t5b-XXXXXX)
mkdir -p "$T5A/.claude" "$T5B/.claude"
cat > "$T5A/.claude/zskills-config.json" <<'CFG_A'
{ "timezone": "Europe/London" }
CFG_A
cat > "$T5B/.claude/zskills-config.json" <<'CFG_B'
{ "timezone": "Asia/Tokyo" }
CFG_B

# Each subshell is fresh — no var-cache from idempotency carries over.
TZ_A=$(CLAUDE_PROJECT_DIR="$T5A" bash -c '. "'"$HELPER"'" && printf "%s" "$TIMEZONE"')
TZ_B=$(CLAUDE_PROJECT_DIR="$T5B" bash -c '. "'"$HELPER"'" && printf "%s" "$TIMEZONE"')

[ "$TZ_A" = "Europe/London" ] \
  && pass "Test 5a: tmp1 (CLAUDE_PROJECT_DIR=A) → \$TIMEZONE = 'Europe/London'" \
  || fail "Test 5a: tmp1 timezone" "got '$TZ_A'"
[ "$TZ_B" = "Asia/Tokyo" ] \
  && pass "Test 5b: tmp2 (CLAUDE_PROJECT_DIR=B, fresh subshell) → \$TIMEZONE = 'Asia/Tokyo'" \
  || fail "Test 5b: tmp2 timezone" "got '$TZ_B'"

rm -rf "$T5A" "$T5B"

# --- Test 6: references/canonical-config-prelude.md exists with 7 sections (AC6) ---
echo ""
echo "=== Test 6: references/canonical-config-prelude.md exists with 7 sections ==="

if [ -f "$PRELUDE_DOC" ]; then
  pass "Test 6a: references/canonical-config-prelude.md exists"
else
  fail "Test 6a: prelude doc exists" "$PRELUDE_DOC missing"
fi

SECTION_COUNT=$(grep -cE '^## ' "$PRELUDE_DOC" 2>/dev/null || echo 0)
if [ "$SECTION_COUNT" = "7" ]; then
  pass "Test 6b: prelude doc has exactly 7 ## sections"
else
  fail "Test 6b: 7 sections" "got $SECTION_COUNT ## sections"
fi

# Spot-check that each of the 7 expected topic keywords appears in the doc
# (heading text + body content combined). Loose match — confirms each
# section was written, not the exact heading title.
TOPICS=("Sourcing pattern" "Fallback semantics" "Mode files" "Subagent" "Shell-state" "Heredoc" "Allowlist marker")
MISSING=""
for topic in "${TOPICS[@]}"; do
  if ! grep -qF "$topic" "$PRELUDE_DOC"; then
    MISSING="$MISSING [$topic]"
  fi
done
if [ -z "$MISSING" ]; then
  pass "Test 6c: all 7 expected section topics present in prelude doc"
else
  fail "Test 6c: 7 topics" "missing:$MISSING"
fi

# --- Test 7: install integrity (AC7) ----------------------------------------
echo ""
echo "=== Test 7: install integrity — helper present in .claude/skills/ mirror ==="

# Per the SKILL.md "Tier-1 scripts ship via the skill mirror at
# .claude/skills/<owner>/scripts/" rule, the install location for the
# helper IS the skill mirror. Verify the source and mirror are both
# present and byte-identical (this is the install-rendered output that
# /update-zskills propagates downstream via mirror copy).

if [ -f "$MIRROR_HELPER" ]; then
  pass "Test 7a: .claude/skills/update-zskills/scripts/zskills-resolve-config.sh exists"
else
  fail "Test 7a: mirror helper exists" "$MIRROR_HELPER missing"
fi

if diff -q "$HELPER" "$MIRROR_HELPER" >/dev/null 2>&1; then
  pass "Test 7b: source and mirror are byte-identical"
else
  fail "Test 7b: source/mirror byte-identical" "diff -q returned non-zero"
fi

# Synthetic /update-zskills install fixture: emulate the skill-mirror copy
# step by running scripts/mirror-skill.sh against a fresh fixture that has
# only the source skill (no .claude/ mirror), and asserting the helper
# lands at the expected path. This mirrors how /update-zskills installs
# Tier-1 scripts to a downstream consumer.
T7=$(mktemp -d /tmp/zskills-resolve-cfg-t7-XXXXXX)
mkdir -p "$T7/skills/update-zskills/scripts" "$T7/.claude/skills" "$T7/scripts"
cp "$REPO_ROOT/scripts/mirror-skill.sh" "$T7/scripts/mirror-skill.sh"
cp "$HELPER" "$T7/skills/update-zskills/scripts/zskills-resolve-config.sh"
echo "stub" > "$T7/skills/update-zskills/SKILL.md"
( cd "$T7" && git init -q && git config user.email t@t && git config user.name t )

RENDER_OUT=$( cd "$T7" && bash scripts/mirror-skill.sh update-zskills 2>&1 )
RENDER_RC=$?

if [ "$RENDER_RC" -eq 0 ] \
  && [ -f "$T7/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  pass "Test 7c: clean-fixture install → helper present in rendered output"
else
  fail "Test 7c: clean-fixture install" "rc=$RENDER_RC, out=$RENDER_OUT"
fi

rm -rf "$T7"

# --- Test 8: ZSKILLS_VERSION resolution (Phase 5a.2) -----------------------
echo ""
echo "=== Test 8: ZSKILLS_VERSION resolution from top-level zskills_version field ==="
T8=$(mktemp -d /tmp/zskills-resolve-cfg-t8-XXXXXX)
mkdir -p "$T8/.claude"
cat > "$T8/.claude/zskills-config.json" <<'CFG_VER'
{
  "zskills_version": "2026.05.01+abc123",
  "timezone": "UTC"
}
CFG_VER

T8_OUT=$(
  CLAUDE_PROJECT_DIR="$T8" \
  bash -c '. "'"$HELPER"'" && printf "%s\n" "$ZSKILLS_VERSION" "$TIMEZONE"'
)
T8_VER=$(printf '%s\n' "$T8_OUT" | sed -n '1p')
T8_TZ=$(printf '%s\n' "$T8_OUT" | sed -n '2p')

[ "$T8_VER" = "2026.05.01+abc123" ] \
  && pass "Test 8a: \$ZSKILLS_VERSION = '2026.05.01+abc123' (Phase 5a.2 7th-var case)" \
  || fail "Test 8a: \$ZSKILLS_VERSION" "got '$T8_VER'"
[ "$T8_TZ" = "UTC" ] \
  && pass "Test 8b: other vars still resolved when zskills_version present" \
  || fail "Test 8b: \$TIMEZONE alongside zskills_version" "got '$T8_TZ'"

# Subtest 8c: zskills_version absent → ZSKILLS_VERSION stays empty (already
# covered by Test 1g but reasserting in the dedicated test for clarity).
T8B=$(mktemp -d /tmp/zskills-resolve-cfg-t8b-XXXXXX)
mkdir -p "$T8B/.claude"
echo '{ "timezone": "UTC" }' > "$T8B/.claude/zskills-config.json"
T8B_VER=$(
  CLAUDE_PROJECT_DIR="$T8B" \
  bash -c '. "'"$HELPER"'" && printf "%s" "$ZSKILLS_VERSION"'
)
[ -z "$T8B_VER" ] \
  && pass "Test 8c: \$ZSKILLS_VERSION empty when zskills_version field absent" \
  || fail "Test 8c: \$ZSKILLS_VERSION empty when absent" "got '$T8B_VER'"

rm -rf "$T8" "$T8B"

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
