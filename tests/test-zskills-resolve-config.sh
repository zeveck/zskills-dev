#!/bin/bash
# Tests for skills/update-zskills/scripts/zskills-resolve-config.sh —
# the canonical config-resolution helper introduced in
# plans/SKILL_FILE_DRIFT_FIX.md Phase 1.
#
# Covers the 7 ACs from the phase doc + Phase 5a.2's 7th-var case
# (ZSKILLS_VERSION resolution from a top-level `zskills_version` field)
# + the INSTALL_REDESIGN Phase 5 config cascade (project > user >
# built-in defaults).
#   1. Synthetic-fixture: temp dir with a config containing timezone,
#      testing.full_cmd, commit.co_author. Source helper; assert
#      $TIMEZONE/$FULL_TEST_CMD/$COMMIT_CO_AUTHOR populated;
#      $UNIT_TEST_CMD/$DEV_SERVER_CMD/$ZSKILLS_VERSION empty;
#      $TEST_OUTPUT_FILE = built-in default (Phase 5 re-spec: defaults
#      fill still-empty keys after the cascade).
#   2. Idempotency: source twice; vars unchanged on second source.
#   3. Empty-config (Phase 5 RE-SPEC, intended assertion change): no
#      config at either tier → built-in defaults, NOT empty: TIMEZONE=UTC,
#      TEST_OUTPUT_FILE=.test-results.txt; cmd vars/co_author/version
#      stay empty (no sane built-in).
#   4. Malformed-config (Phase 5 RE-SPEC): broken JSON; no abort; same
#      defaults-filled result as Test 3.
#   5. CLAUDE_PROJECT_DIR-switching: tmp1 with London, tmp2 with Tokyo;
#      switching $CLAUDE_PROJECT_DIR in a fresh subshell yields the
#      correct timezone for each.
#   6. references/canonical-config-prelude.md exists with 7 sections.
#   7. Install integrity: helper script is present in the
#      .claude/skills/update-zskills/scripts/ mirror (the install
#      location consumers receive via /update-zskills's skill mirror).
#   8. ZSKILLS_VERSION from project config; 8d-8e: .zskills/init-done
#      `version:` line fallback (config-less consumers).
#   9. CLAUDE_PROJECT_DIR git-common-dir fallback.
#  10. Sibling-block scope collision (#395).
#  11. User tier alone (HOME-sandboxed ~/.claude/zskills-config.json)
#      supplies cascadable keys.
#  12. Precedence: project match wins per key; user fills project-absent
#      keys (partial per-key merge).
#  13. Malformed USER file → ignored; project + defaults result.
#  14. Present-but-EMPTY project value wins over user value (documented
#      two-pass semantics), then falls to the built-in default.
#  15. execution.* + zskills_version are PROJECT-TIER-ONLY (user-tier
#      values ignored).
#
# HOME is sandboxed ($EMPTY_HOME / $USER_HOME fixtures) in every case that
# asserts concrete values — the helper now reads the USER tier from
# $HOME/.claude/zskills-config.json, so inheriting the runner's real HOME
# would make assertions environment-sensitive.
#
# Run from repo root: bash tests/test-zskills-resolve-config.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$REPO_ROOT/skills/update-zskills/scripts/zskills-resolve-config.sh"
MIRROR_HELPER="$REPO_ROOT/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
PRELUDE_DOC="$REPO_ROOT/references/canonical-config-prelude.md"

PASS_COUNT=0
FAIL_COUNT=0

# TEST_OUT for stderr-capture fixtures (Test 9). Per-worktree path so
# parallel pipelines do not collide (matches the idiom from test-zskills-paths.sh).
TEST_OUT="/tmp/zskills-tests/$(basename "$REPO_ROOT")"
mkdir -p "$TEST_OUT"

# HOME sandbox: an empty home (no user-tier config) for the cases that
# assert project-only / defaults-only results. Cascade cases create their
# own $USER_HOME fixtures.
EMPTY_HOME=$(mktemp -d /tmp/zskills-resolve-cfg-home-XXXXXX)

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
  HOME="$EMPTY_HOME" CLAUDE_PROJECT_DIR="$T1" \
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
# Phase 5 RE-SPEC (intended assertion change): output_file is absent from
# the fixture, so the built-in default now fills it (old expectation: empty).
[ "$T1_OUTFILE" = ".test-results.txt" ] \
  && pass "Test 1f: \$TEST_OUTPUT_FILE = '.test-results.txt' (built-in default fills absent key)" \
  || fail "Test 1f: \$TEST_OUTPUT_FILE" "got '$T1_OUTFILE', expected '.test-results.txt'"
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
  HOME="$EMPTY_HOME" CLAUDE_PROJECT_DIR="$T2" \
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
# Phase 5 RE-SPEC (intended assertion change, INSTALL_REDESIGN Phase 5):
# OLD: no config → all 7 vars empty. NEW: no config at EITHER tier → the
# built-in defaults fill TIMEZONE (UTC) and TEST_OUTPUT_FILE
# (.test-results.txt); the cmd vars / co_author / version stay empty (no
# sane built-in — consuming skills' three-case trees handle empty).
echo ""
echo "=== Test 3: empty-config — no config at either tier → built-in defaults ==="
T3=$(mktemp -d /tmp/zskills-resolve-cfg-t3-XXXXXX)
# Intentionally no .claude/zskills-config.json; HOME sandboxed empty.

RESULT3=$(
  HOME="$EMPTY_HOME" CLAUDE_PROJECT_DIR="$T3" \
  bash -c '. "'"$HELPER"'" && printf "%s\n" "$TIMEZONE" "$FULL_TEST_CMD" "$UNIT_TEST_CMD" "$DEV_SERVER_CMD" "$TEST_OUTPUT_FILE" "$COMMIT_CO_AUTHOR" "$ZSKILLS_VERSION"'
)
RC3=$?

if [ "$RC3" -eq 0 ]; then
  pass "Test 3a: source rc=0 even with no config file"
else
  fail "Test 3a: source rc" "got rc=$RC3"
fi

T3_TZ=$(printf '%s\n' "$RESULT3" | sed -n '1p')
T3_OUTFILE=$(printf '%s\n' "$RESULT3" | sed -n '5p')
[ "$T3_TZ" = "UTC" ] \
  && pass "Test 3b: \$TIMEZONE = 'UTC' (built-in default)" \
  || fail "Test 3b: \$TIMEZONE default" "got '$T3_TZ', expected 'UTC'"
[ "$T3_OUTFILE" = ".test-results.txt" ] \
  && pass "Test 3c: \$TEST_OUTPUT_FILE = '.test-results.txt' (built-in default)" \
  || fail "Test 3c: \$TEST_OUTPUT_FILE default" "got '$T3_OUTFILE', expected '.test-results.txt'"
T3_REST_EMPTY=1
for i in 2 3 4 6 7; do
  v=$(printf '%s\n' "$RESULT3" | sed -n "${i}p")
  if [ -n "$v" ]; then
    T3_REST_EMPTY=0
    break
  fi
done
if [ "$T3_REST_EMPTY" = 1 ]; then
  pass "Test 3d: cmd vars / co_author / version stay empty (no built-in)"
else
  fail "Test 3d: no-built-in vars empty" "got: $RESULT3"
fi

rm -rf "$T3"

# --- Test 4: malformed-config (AC4) -----------------------------------------
# Phase 5 RE-SPEC (intended assertion change): OLD: malformed JSON → all
# vars empty. NEW: malformed JSON fails every extraction regex (fail-open),
# then the built-in defaults fill TIMEZONE/TEST_OUTPUT_FILE — same result
# as Test 3's no-config case.
echo ""
echo "=== Test 4: malformed JSON — no abort, defaults-filled result ==="
T4=$(mktemp -d /tmp/zskills-resolve-cfg-t4-XXXXXX)
mkdir -p "$T4/.claude"
cat > "$T4/.claude/zskills-config.json" <<'BROKEN'
{ "testing": broken-not-quoted, "timezone":
BROKEN

RESULT4=$(
  HOME="$EMPTY_HOME" CLAUDE_PROJECT_DIR="$T4" \
  bash -c '. "'"$HELPER"'" && printf "%s\n" "$TIMEZONE" "$FULL_TEST_CMD" "$UNIT_TEST_CMD" "$DEV_SERVER_CMD" "$TEST_OUTPUT_FILE" "$COMMIT_CO_AUTHOR" "$ZSKILLS_VERSION"'
)
RC4=$?

if [ "$RC4" -eq 0 ]; then
  pass "Test 4a: source rc=0 even with malformed JSON"
else
  fail "Test 4a: source rc on malformed JSON" "got rc=$RC4"
fi

T4_TZ=$(printf '%s\n' "$RESULT4" | sed -n '1p')
T4_OUTFILE=$(printf '%s\n' "$RESULT4" | sed -n '5p')
[ "$T4_TZ" = "UTC" ] && [ "$T4_OUTFILE" = ".test-results.txt" ] \
  && pass "Test 4b: malformed JSON → built-in defaults (TIMEZONE=UTC, output_file=.test-results.txt)" \
  || fail "Test 4b: malformed → defaults" "tz='$T4_TZ' outfile='$T4_OUTFILE'"
T4_REST_EMPTY=1
for i in 2 3 4 6 7; do
  v=$(printf '%s\n' "$RESULT4" | sed -n "${i}p")
  if [ -n "$v" ]; then
    T4_REST_EMPTY=0
    break
  fi
done
if [ "$T4_REST_EMPTY" = 1 ]; then
  pass "Test 4c: cmd vars / co_author / version stay empty on malformed JSON"
else
  fail "Test 4c: no-built-in vars empty" "got: $RESULT4"
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
TZ_A=$(HOME="$EMPTY_HOME" CLAUDE_PROJECT_DIR="$T5A" bash -c '. "'"$HELPER"'" && printf "%s" "$TIMEZONE"')
TZ_B=$(HOME="$EMPTY_HOME" CLAUDE_PROJECT_DIR="$T5B" bash -c '. "'"$HELPER"'" && printf "%s" "$TIMEZONE"')

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
  HOME="$EMPTY_HOME" CLAUDE_PROJECT_DIR="$T8" \
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
  HOME="$EMPTY_HOME" CLAUDE_PROJECT_DIR="$T8B" \
  bash -c '. "'"$HELPER"'" && printf "%s" "$ZSKILLS_VERSION"'
)
[ -z "$T8B_VER" ] \
  && pass "Test 8c: \$ZSKILLS_VERSION empty when zskills_version field absent" \
  || fail "Test 8c: \$ZSKILLS_VERSION empty when absent" "got '$T8B_VER'"

# Subtest 8d (Phase 5): config-less consumer with a .zskills/init-done
# marker → ZSKILLS_VERSION falls back to its `version:` line. (The
# init-done literal in the helper is the documented Phase 5 temporary
# re-type; Phase 6a A0 retargets it to init-state.sh.)
T8D=$(mktemp -d /tmp/zskills-resolve-cfg-t8d-XXXXXX)
mkdir -p "$T8D/.zskills"
printf 'version: 2026.06.1\ndate: 2026-06-10T00:00:00-04:00\n' > "$T8D/.zskills/init-done"
T8D_VER=$(
  HOME="$EMPTY_HOME" CLAUDE_PROJECT_DIR="$T8D" \
  bash -c '. "'"$HELPER"'" && printf "%s" "$ZSKILLS_VERSION"'
)
[ "$T8D_VER" = "2026.06.1" ] \
  && pass "Test 8d: \$ZSKILLS_VERSION = '2026.06.1' from .zskills/init-done version: line (no config)" \
  || fail "Test 8d: init-done fallback" "got '$T8D_VER', expected '2026.06.1'"

# Subtest 8e: project config stamp WINS over the init-done fallback.
mkdir -p "$T8D/.claude"
echo '{ "zskills_version": "2026.06.2+abcdef" }' > "$T8D/.claude/zskills-config.json"
T8E_VER=$(
  HOME="$EMPTY_HOME" CLAUDE_PROJECT_DIR="$T8D" \
  bash -c '. "'"$HELPER"'" && printf "%s" "$ZSKILLS_VERSION"'
)
[ "$T8E_VER" = "2026.06.2+abcdef" ] \
  && pass "Test 8e: project config stamp wins over init-done fallback" \
  || fail "Test 8e: config stamp precedence" "got '$T8E_VER', expected '2026.06.2+abcdef'"
rm -rf "$T8" "$T8B" "$T8D"

# --- Test 9: CLAUDE_PROJECT_DIR fallback via git-common-dir -----------------
#
# When the harness doesn't inject $CLAUDE_PROJECT_DIR (e.g. orchestrator-side
# Bash from inside a skill — Anthropic only documents the var as set for
# hook subprocesses), the helper falls back to the canonical "find main
# repo from anywhere" idiom (`git rev-parse --git-common-dir | dirname`)
# and emits a one-time stderr WARN. Outside any git repo, no clean fallback
# exists and the helper fails loud.

echo ""
echo "=== Test 9a: \$CLAUDE_PROJECT_DIR unset, IN a git repo → fallback succeeds ==="
( unset CLAUDE_PROJECT_DIR _ZSK_FALLBACK_WARNED
  source "$HELPER"
) 2> "$TEST_OUT/test9a.stderr"
T9A_RC=$?
if [ "$T9A_RC" = "0" ]; then
  pass "Test 9a: helper rc=0 via git-common-dir fallback"
else
  fail "Test 9a: helper rc=0 via fallback" \
    "expected 0, got $T9A_RC; stderr: $(cat "$TEST_OUT/test9a.stderr")"
fi
if grep -qE "WARN.*fell back.*git-common-dir" "$TEST_OUT/test9a.stderr"; then
  pass "Test 9a: stderr contains 'WARN ... fell back ... git-common-dir'"
else
  fail "Test 9a: stderr fallback WARN" \
    "got: $(cat "$TEST_OUT/test9a.stderr")"
fi

echo ""
echo "=== Test 9b: \$CLAUDE_PROJECT_DIR unset, NOT in a git repo → fail loud ==="
T9B=$(mktemp -d /tmp/zskills-resolve-cfg-t9b-XXXXXX)
( cd "$T9B"
  unset CLAUDE_PROJECT_DIR _ZSK_FALLBACK_WARNED GIT_DIR GIT_WORK_TREE
  source "$HELPER"
) 2> "$TEST_OUT/test9b.stderr"
T9B_RC=$?
if [ "$T9B_RC" != "0" ]; then
  pass "Test 9b: helper exits non-zero outside git repo (rc=$T9B_RC)"
else
  fail "Test 9b: helper exit code" \
    "expected non-zero, got $T9B_RC; stderr: $(cat "$TEST_OUT/test9b.stderr")"
fi
if grep -q "CLAUDE_PROJECT_DIR" "$TEST_OUT/test9b.stderr"; then
  pass "Test 9b: stderr names CLAUDE_PROJECT_DIR"
else
  fail "Test 9b: stderr CLAUDE_PROJECT_DIR mention" \
    "got: $(cat "$TEST_OUT/test9b.stderr")"
fi
if grep -qiE "not in a git repo|not.*git" "$TEST_OUT/test9b.stderr"; then
  pass "Test 9b: stderr explains 'not in a git repo'"
else
  fail "Test 9b: stderr git-repo mention" \
    "got: $(cat "$TEST_OUT/test9b.stderr")"
fi
rm -rf "$T9B"

echo ""
echo "=== Test 9c: WARN suppressed on second source via _ZSK_FALLBACK_WARNED sentinel ==="
# Both sources run in the SAME subshell so the sentinel set by the first
# source persists into the second. Expect exactly one WARN line emitted.
T9C_STDERR=$(
  unset CLAUDE_PROJECT_DIR _ZSK_FALLBACK_WARNED
  { source "$HELPER"; source "$HELPER"; } 2>&1 >/dev/null
)
T9C_WARN_COUNT=$(printf '%s\n' "$T9C_STDERR" | grep -cE "WARN.*fell back.*git-common-dir" || true)
if [ "$T9C_WARN_COUNT" = "1" ]; then
  pass "Test 9c: WARN emitted exactly once across two sources (sentinel works)"
else
  fail "Test 9c: WARN once-per-shell" \
    "expected 1 occurrence, got $T9C_WARN_COUNT; stderr: $T9C_STDERR"
fi

# --- Test 10: sibling-block scope collision (issue #395) -------------------
#
# Regression guard for the unscoped-regex class of bug. Prior to #395, the
# UNIT_TEST_CMD/FULL_TEST_CMD/TEST_OUTPUT_FILE extractions matched the FIRST
# occurrence of "unit_cmd"/"full_cmd"/"output_file" anywhere in the config,
# so a sibling block (e.g. "ui": { ... }) appearing BEFORE "testing" could
# shadow the testing values. Fix: scope each regex to the enclosing
# "testing" object, mirroring the dev_server.cmd scoping.

echo ""
echo "=== Test 10: sibling-block scope collision — testing values win over earlier siblings (#395) ==="
T10=$(mktemp -d /tmp/zskills-resolve-cfg-t10-XXXXXX)
mkdir -p "$T10/.claude"
cat > "$T10/.claude/zskills-config.json" <<'CFG_SIB'
{
  "ui": {
    "unit_cmd": "UI_WRONG_UNIT",
    "full_cmd": "UI_WRONG_FULL",
    "output_file": "ui-wrong.txt"
  },
  "testing": {
    "unit_cmd": "TESTING_UNIT",
    "full_cmd": "TESTING_FULL",
    "output_file": "testing-correct.txt"
  }
}
CFG_SIB

T10_OUT=$(
  HOME="$EMPTY_HOME" CLAUDE_PROJECT_DIR="$T10" \
  bash -c '. "'"$HELPER"'" && printf "%s\n" "$UNIT_TEST_CMD" "$FULL_TEST_CMD" "$TEST_OUTPUT_FILE"'
)
T10_UNIT=$(printf '%s\n' "$T10_OUT" | sed -n '1p')
T10_FULL=$(printf '%s\n' "$T10_OUT" | sed -n '2p')
T10_OUTFILE=$(printf '%s\n' "$T10_OUT" | sed -n '3p')

[ "$T10_UNIT" = "TESTING_UNIT" ] \
  && pass "Test 10a: \$UNIT_TEST_CMD = 'TESTING_UNIT' (sibling 'ui.unit_cmd' not shadowing)" \
  || fail "Test 10a: \$UNIT_TEST_CMD sibling-scope" "got '$T10_UNIT', expected 'TESTING_UNIT'"
[ "$T10_FULL" = "TESTING_FULL" ] \
  && pass "Test 10b: \$FULL_TEST_CMD = 'TESTING_FULL' (sibling 'ui.full_cmd' not shadowing)" \
  || fail "Test 10b: \$FULL_TEST_CMD sibling-scope" "got '$T10_FULL', expected 'TESTING_FULL'"
[ "$T10_OUTFILE" = "testing-correct.txt" ] \
  && pass "Test 10c: \$TEST_OUTPUT_FILE = 'testing-correct.txt' (sibling 'ui.output_file' not shadowing)" \
  || fail "Test 10c: \$TEST_OUTPUT_FILE sibling-scope" "got '$T10_OUTFILE', expected 'testing-correct.txt'"

rm -rf "$T10"

# --- Test 11: user tier alone supplies cascadable keys (Phase 5) ------------
echo ""
echo "=== Test 11: HOME-sandboxed user tier — user config alone supplies values ==="
T11=$(mktemp -d /tmp/zskills-resolve-cfg-t11-XXXXXX)
U11=$(mktemp -d /tmp/zskills-resolve-cfg-u11-XXXXXX)
mkdir -p "$U11/.claude"
cat > "$U11/.claude/zskills-config.json" <<'UCFG'
{
  "timezone": "Asia/Tokyo",
  "testing": { "unit_cmd": "USER_UNIT" },
  "commit": { "co_author": "User Tier <user@example.com>" }
}
UCFG
# No project config at all.
T11_OUT=$(
  HOME="$U11" CLAUDE_PROJECT_DIR="$T11" \
  bash -c '. "'"$HELPER"'" && printf "%s\n" "$TIMEZONE" "$UNIT_TEST_CMD" "$COMMIT_CO_AUTHOR" "$TEST_OUTPUT_FILE"'
)
T11_TZ=$(printf '%s\n' "$T11_OUT" | sed -n '1p')
T11_UNIT=$(printf '%s\n' "$T11_OUT" | sed -n '2p')
T11_CO=$(printf '%s\n' "$T11_OUT" | sed -n '3p')
T11_OUTFILE=$(printf '%s\n' "$T11_OUT" | sed -n '4p')
[ "$T11_TZ" = "Asia/Tokyo" ] \
  && pass "Test 11a: \$TIMEZONE = 'Asia/Tokyo' from user tier" \
  || fail "Test 11a: user-tier timezone" "got '$T11_TZ'"
[ "$T11_UNIT" = "USER_UNIT" ] \
  && pass "Test 11b: \$UNIT_TEST_CMD = 'USER_UNIT' from user tier" \
  || fail "Test 11b: user-tier unit_cmd" "got '$T11_UNIT'"
[ "$T11_CO" = "User Tier <user@example.com>" ] \
  && pass "Test 11c: \$COMMIT_CO_AUTHOR from user tier" \
  || fail "Test 11c: user-tier co_author" "got '$T11_CO'"
[ "$T11_OUTFILE" = ".test-results.txt" ] \
  && pass "Test 11d: \$TEST_OUTPUT_FILE = built-in default (key absent at both tiers)" \
  || fail "Test 11d: default under user tier" "got '$T11_OUTFILE'"
rm -rf "$T11" "$U11"

# --- Test 12: precedence — project match wins; user fills absent keys -------
echo ""
echo "=== Test 12: precedence — project>user per key; partial per-key merge ==="
T12=$(mktemp -d /tmp/zskills-resolve-cfg-t12-XXXXXX)
U12=$(mktemp -d /tmp/zskills-resolve-cfg-u12-XXXXXX)
mkdir -p "$T12/.claude" "$U12/.claude"
cat > "$U12/.claude/zskills-config.json" <<'UCFG'
{
  "timezone": "Asia/Tokyo",
  "commit": { "co_author": "User Tier <user@example.com>" }
}
UCFG
cat > "$T12/.claude/zskills-config.json" <<'PCFG'
{
  "timezone": "Europe/London",
  "testing": { "unit_cmd": "PROJ_UNIT" }
}
PCFG
T12_OUT=$(
  HOME="$U12" CLAUDE_PROJECT_DIR="$T12" \
  bash -c '. "'"$HELPER"'" && printf "%s\n" "$TIMEZONE" "$UNIT_TEST_CMD" "$COMMIT_CO_AUTHOR"'
)
T12_TZ=$(printf '%s\n' "$T12_OUT" | sed -n '1p')
T12_UNIT=$(printf '%s\n' "$T12_OUT" | sed -n '2p')
T12_CO=$(printf '%s\n' "$T12_OUT" | sed -n '3p')
[ "$T12_TZ" = "Europe/London" ] \
  && pass "Test 12a: \$TIMEZONE = 'Europe/London' (project wins over user)" \
  || fail "Test 12a: project precedence" "got '$T12_TZ'"
[ "$T12_UNIT" = "PROJ_UNIT" ] \
  && pass "Test 12b: \$UNIT_TEST_CMD = 'PROJ_UNIT' (project-only key effective)" \
  || fail "Test 12b: project unit_cmd" "got '$T12_UNIT'"
[ "$T12_CO" = "User Tier <user@example.com>" ] \
  && pass "Test 12c: \$COMMIT_CO_AUTHOR from user tier fills project-absent key (partial merge)" \
  || fail "Test 12c: user fills absent key" "got '$T12_CO'"
rm -rf "$T12" "$U12"

# --- Test 13: malformed USER file → ignored (fail-open) ---------------------
echo ""
echo "=== Test 13: malformed user config — ignored; project + defaults result ==="
T13=$(mktemp -d /tmp/zskills-resolve-cfg-t13-XXXXXX)
U13=$(mktemp -d /tmp/zskills-resolve-cfg-u13-XXXXXX)
mkdir -p "$T13/.claude" "$U13/.claude"
cat > "$U13/.claude/zskills-config.json" <<'UBROKEN'
{ not json at all, "timezone":
UBROKEN
echo '{ "timezone": "Europe/London" }' > "$T13/.claude/zskills-config.json"
T13_OUT=$(
  HOME="$U13" CLAUDE_PROJECT_DIR="$T13" \
  bash -c '. "'"$HELPER"'" && printf "%s\n" "$TIMEZONE" "$TEST_OUTPUT_FILE" "$UNIT_TEST_CMD"'
)
T13_RC=$?
T13_TZ=$(printf '%s\n' "$T13_OUT" | sed -n '1p')
T13_OUTFILE=$(printf '%s\n' "$T13_OUT" | sed -n '2p')
T13_UNIT=$(printf '%s\n' "$T13_OUT" | sed -n '3p')
if [ "$T13_RC" -eq 0 ] && [ "$T13_TZ" = "Europe/London" ] \
  && [ "$T13_OUTFILE" = ".test-results.txt" ] && [ -z "$T13_UNIT" ]; then
  pass "Test 13: malformed user file ignored → project + defaults result (rc=0)"
else
  fail "Test 13: malformed-user fallback" "rc=$T13_RC tz='$T13_TZ' outfile='$T13_OUTFILE' unit='$T13_UNIT'"
fi
rm -rf "$T13" "$U13"

# --- Test 14: present-but-empty project value wins over user ----------------
# Documented two-pass semantics: match-success = presence, so a project
# `"timezone": ""` MATCHES (capturing empty), overwriting the user value;
# the still-empty key then falls to the built-in default (UTC), NOT to the
# user's value.
echo ""
echo "=== Test 14: present-but-EMPTY project value wins over user value ==="
T14=$(mktemp -d /tmp/zskills-resolve-cfg-t14-XXXXXX)
U14=$(mktemp -d /tmp/zskills-resolve-cfg-u14-XXXXXX)
mkdir -p "$T14/.claude" "$U14/.claude"
echo '{ "timezone": "Asia/Tokyo" }' > "$U14/.claude/zskills-config.json"
echo '{ "timezone": "" }' > "$T14/.claude/zskills-config.json"
T14_TZ=$(
  HOME="$U14" CLAUDE_PROJECT_DIR="$T14" \
  bash -c '. "'"$HELPER"'" && printf "%s" "$TIMEZONE"'
)
[ "$T14_TZ" = "UTC" ] \
  && pass "Test 14: project '\"timezone\": \"\"' overrides user value → built-in default 'UTC'" \
  || fail "Test 14: empty-project-value precedence" "got '$T14_TZ', expected 'UTC'"
rm -rf "$T14" "$U14"

# --- Test 15: execution.* + zskills_version are PROJECT-TIER-ONLY -----------
echo ""
echo "=== Test 15: execution.* and zskills_version never read from the user tier ==="
T15=$(mktemp -d /tmp/zskills-resolve-cfg-t15-XXXXXX)
U15=$(mktemp -d /tmp/zskills-resolve-cfg-u15-XXXXXX)
mkdir -p "$U15/.claude"
cat > "$U15/.claude/zskills-config.json" <<'UCFG'
{
  "zskills_version": "9999.99.9+ffffff",
  "execution": {
    "max_concurrent_worktrees": 9,
    "dashboard_completed_days": 99,
    "dashboard_completed_limit": 9999
  }
}
UCFG
# No project config: user-tier execution.* + zskills_version must be ignored.
T15_OUT=$(
  HOME="$U15" CLAUDE_PROJECT_DIR="$T15" \
  bash -c '. "'"$HELPER"'" && printf "%s\n" "$ZSKILLS_MAX_CONCURRENT_WORKTREES" "$ZSKILLS_DASHBOARD_COMPLETED_DAYS" "$ZSKILLS_DASHBOARD_COMPLETED_LIMIT" "$ZSKILLS_VERSION"'
)
T15_MCW=$(printf '%s\n' "$T15_OUT" | sed -n '1p')
T15_DCD=$(printf '%s\n' "$T15_OUT" | sed -n '2p')
T15_DCL=$(printf '%s\n' "$T15_OUT" | sed -n '3p')
T15_VER=$(printf '%s\n' "$T15_OUT" | sed -n '4p')
if [ "$T15_MCW" = "3" ] && [ "$T15_DCD" = "14" ] && [ "$T15_DCL" = "500" ]; then
  pass "Test 15a: user-tier execution.* ignored (defaults 3/14/500 hold)"
else
  fail "Test 15a: execution.* project-tier-only" "mcw='$T15_MCW' dcd='$T15_DCD' dcl='$T15_DCL'"
fi
[ -z "$T15_VER" ] \
  && pass "Test 15b: user-tier zskills_version ignored (\$ZSKILLS_VERSION empty)" \
  || fail "Test 15b: zskills_version project-tier-only" "got '$T15_VER'"
# Project tier still sets them (control arm).
mkdir -p "$T15/.claude"
echo '{ "execution": { "max_concurrent_worktrees": 5 } }' > "$T15/.claude/zskills-config.json"
T15_MCW2=$(
  HOME="$U15" CLAUDE_PROJECT_DIR="$T15" \
  bash -c '. "'"$HELPER"'" && printf "%s" "$ZSKILLS_MAX_CONCURRENT_WORKTREES"'
)
[ "$T15_MCW2" = "5" ] \
  && pass "Test 15c: PROJECT-tier execution.max_concurrent_worktrees=5 still effective" \
  || fail "Test 15c: project execution control arm" "got '$T15_MCW2', expected '5'"
rm -rf "$T15" "$U15"

rm -rf "$EMPTY_HOME"

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
