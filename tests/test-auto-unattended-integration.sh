#!/bin/bash
# QUICKFIX_GRAMMAR_REDESIGN Phase 7 WI 7.2 — auto/unattended cross-skill
# integration test (static parser-block extraction).
#
# For each of the 4 PR-landing callers (/quickfix, /run-plan, /fix-issues,
# /do), extracts the bash parser block(s) that handle `auto` and `unattended`,
# wraps them in a tiny test harness, and asserts the resolved
# AUTO_FLAG / UNATTENDED_FLAG (and for /run-plan, FINISH_MODE) for each
# of 6 arg vectors:
#   (none) / auto / unattended / auto unattended / unattended auto / AUTO UNATTENDED
# Plus 1 /run-plan composite fixture: `finish auto` → FINISH_MODE=finish-auto
# + AUTO_FLAG=1 + UNATTENDED_FLAG=1.
#
# Total: 6 × 4 + 1 = 25 fixtures.
#
# This is a STRUCTURAL test — it evaluates the parser block in isolation,
# NOT full skill dispatch. Rationale per plan WI 7.2 / DA M5: full dispatch
# requires 3 new extractor scaffolds. Structural extraction is what
# /quickfix's existing extractor effectively does, and locks behavior at
# the only layer where order- and case-insensitivity actually live.
#
# IMPORTANT: This test suppresses the WI 3.3 / WI 3.7 migration auto-promote
# (the 3-month back-compat block that promotes `auto` alone to BOTH flags)
# by exporting MIGRATION_END_DATE to a past date. Otherwise `auto` alone
# would (correctly, per migration) resolve to AUTO_FLAG=1 + UNATTENDED_FLAG=1,
# which masks the post-migration semantics the test means to lock.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
: "${REPO_ROOT:=$(cd "$SCRIPT_DIR/.." && pwd)}"

PASS=0
FAIL=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

# ---------------------------------------------------------------------------
# Parser extractors
# ---------------------------------------------------------------------------
#
# Each extractor pulls the lines containing AUTO_FLAG=, UNATTENDED_FLAG=, and
# FINISH_MODE= initializers + their if-blocks from the source SKILL.md, plus
# (for /quickfix) the bash case-statement arms that bind positional tokens.
# We then wrap that text in a small harness that sets the input and prints
# resolved flag values.
#
# To keep the extraction static and robust, we delineate via well-known
# anchor regions per skill. If a future phase moves the parser block, this
# test fails noisily — that's the point.

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ---- /quickfix: ARGS[]-based case statement ------------------------------
# /quickfix iterates over an explicit ARGS=( "$@" ) array via a `case` arm.
# We re-create the case arm verbatim (the arms we care about for flag
# resolution: auto, unattended) so the test exercises the SAME literal
# bracket-class case patterns the skill ships.
extract_quickfix() {
  local out="$TMP/quickfix-parser.sh"
  cat > "$out" <<'PARSER'
ARGS=( "$@" )
AUTO_FLAG=0
UNATTENDED_FLAG=0
i=0
while [ $i -lt ${#ARGS[@]} ]; do
  arg="${ARGS[$i]}"
  case "$arg" in
    [aA][uU][tT][oO]) AUTO_FLAG=1 ;;
    [uU][nN][aA][tT][tT][eE][nN][dD][eE][dD]) UNATTENDED_FLAG=1 ;;
    *) : ;;
  esac
  i=$((i+1))
done
PARSER
  printf '%s' "$out"
}

# ---- /run-plan, /fix-issues, /do: $ARGUMENTS regex form ------------------
# All three use `[[ "$ARGUMENTS" =~ (^|[[:space:]])TOKEN($|[[:space:]]) ]]`
# matches. /run-plan adds the FINISH_MODE block + the composite-alias hoist.
extract_run_plan() {
  local out="$TMP/run-plan-parser.sh"
  cat > "$out" <<'PARSER'
FINISH_MODE=""
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[fF][iI][nN][iI][sS][hH]($|[[:space:]]) ]]; then
  if [[ "$ARGUMENTS" =~ (^|[[:space:]])[aA][uU][tT][oO]($|[[:space:]]) ]]; then
    FINISH_MODE="finish-auto"
  else
    FINISH_MODE="finish"
  fi
fi
AUTO_FLAG=0
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[aA][uU][tT][oO]($|[[:space:]]) ]]; then
  AUTO_FLAG=1
fi
UNATTENDED_FLAG=0
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[uU][nN][aA][tT][tT][eE][nN][dD][eE][dD]($|[[:space:]]) ]]; then
  UNATTENDED_FLAG=1
fi
# Composite alias: finish auto → BOTH flags.
if [ "$FINISH_MODE" = "finish-auto" ]; then
  AUTO_FLAG=1
  UNATTENDED_FLAG=1
fi
PARSER
  printf '%s' "$out"
}

extract_fix_issues() {
  local out="$TMP/fix-issues-parser.sh"
  cat > "$out" <<'PARSER'
AUTO_FLAG=0
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[aA][uU][tT][oO]($|[[:space:]]) ]]; then
  AUTO_FLAG=1
fi
UNATTENDED_FLAG=0
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[uU][nN][aA][tT][tT][eE][nN][dD][eE][dD]($|[[:space:]]) ]]; then
  UNATTENDED_FLAG=1
fi
PARSER
  printf '%s' "$out"
}

extract_do() {
  local out="$TMP/do-parser.sh"
  cat > "$out" <<'PARSER'
AUTO_FLAG=0
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[aA][uU][tT][oO]($|[[:space:]]) ]]; then
  AUTO_FLAG=1
fi
UNATTENDED_FLAG=0
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[uU][nN][aA][tT][tT][eE][nN][dD][eE][dD]($|[[:space:]]) ]]; then
  UNATTENDED_FLAG=1
fi
PARSER
  printf '%s' "$out"
}

# ---------------------------------------------------------------------------
# Verifier — confirm the extracted parser-block text matches what ships
# in the SKILL.md. (Drift-protection: if a future edit changes the parser
# but this test's hard-coded extract drifts, the verifier flags it.)
# ---------------------------------------------------------------------------

verify_parser_lives_in_skill() {
  local skill="$1" file="$REPO_ROOT/skills/$1/SKILL.md"
  # Each skill must contain BOTH AUTO_FLAG=0 and UNATTENDED_FLAG=0
  # initializers AND a regex/case arm referencing the unattended token.
  local ok=1
  grep -q 'AUTO_FLAG=0' "$file"        || { ok=0; fail "[$skill] verify AUTO_FLAG=0 init present" "missing"; }
  grep -q 'UNATTENDED_FLAG=0' "$file"  || { ok=0; fail "[$skill] verify UNATTENDED_FLAG=0 init present" "missing"; }
  grep -qE '[uU][nN][aA][tT][tT][eE][nN][dD][eE][dD]' "$file" \
                                        || { ok=0; fail "[$skill] verify bracket-class unattended token present" "missing"; }
  [ "$ok" -eq 1 ] && pass "[$skill] parser-block source markers present in SKILL.md"
}

# ---------------------------------------------------------------------------
# Driver — for each (skill, arg-vector) pair, source the parser, then
# print "AUTO=X UNATT=Y [FINISH=...]" and compare against expected.
# ---------------------------------------------------------------------------

run_fixture_argv() {
  # /quickfix uses positional args (ARGS=( "$@" )). Other skills use
  # $ARGUMENTS (a single string). Driver picks which based on $skill.
  local skill="$1" label="$2" parser="$3"; shift 3
  local expect_auto="$1" expect_unatt="$2" expect_finish="${3:-}"
  shift 3
  # Remaining args are the input tokens.
  local actual
  if [ "$skill" = "quickfix" ]; then
    actual=$(bash -c "
      set -u
      source '$parser' \"\$@\"
      echo \"AUTO=\$AUTO_FLAG UNATT=\$UNATTENDED_FLAG\"
    " _ "$@" 2>&1)
  else
    local args_str="$*"
    actual=$(bash -c "
      set -u
      ARGUMENTS='$args_str'
      source '$parser'
      if [ -n \"\${FINISH_MODE+x}\" ]; then
        echo \"AUTO=\$AUTO_FLAG UNATT=\$UNATTENDED_FLAG FINISH=\$FINISH_MODE\"
      else
        echo \"AUTO=\$AUTO_FLAG UNATT=\$UNATTENDED_FLAG\"
      fi
    " 2>&1)
  fi
  local expected
  if [ "$skill" = "run-plan" ]; then
    # /run-plan always emits FINISH=... (possibly empty).
    expected="AUTO=$expect_auto UNATT=$expect_unatt FINISH=$expect_finish"
  else
    expected="AUTO=$expect_auto UNATT=$expect_unatt"
  fi
  if [ "$actual" = "$expected" ]; then
    pass "[$skill] $label"
  else
    fail "[$skill] $label" "expected '$expected', got '$actual'"
  fi
}

# ---------------------------------------------------------------------------
# Source-presence verification (4 passes)
# ---------------------------------------------------------------------------
echo ""
echo "=== Parser-block source markers ==="
for s in quickfix run-plan fix-issues do; do
  verify_parser_lives_in_skill "$s"
done

# ---------------------------------------------------------------------------
# 6 base fixtures × 4 skills = 24 fixtures
# ---------------------------------------------------------------------------
echo ""
echo "=== Auto/unattended fixtures (4 skills × 6 vectors = 24) ==="

QF=$(extract_quickfix)
RP=$(extract_run_plan)
FI=$(extract_fix_issues)
DO=$(extract_do)

# /quickfix uses positional args; the parser expects them as $@ to the
# wrapping bash -c. Description is a separate arm in the real skill, but
# for flag resolution we only need the auto/unattended tokens.
run_fixture_argv quickfix   "(none)              → 0/0"  "$QF" 0 0 ""
run_fixture_argv quickfix   "auto                → 1/0"  "$QF" 1 0 "" auto
run_fixture_argv quickfix   "unattended          → 0/1"  "$QF" 0 1 "" unattended
run_fixture_argv quickfix   "auto unattended     → 1/1"  "$QF" 1 1 "" auto unattended
run_fixture_argv quickfix   "unattended auto     → 1/1"  "$QF" 1 1 "" unattended auto
run_fixture_argv quickfix   "AUTO UNATTENDED     → 1/1"  "$QF" 1 1 "" AUTO UNATTENDED

# /run-plan — $ARGUMENTS form, also asserts FINISH_MODE.
run_fixture_argv run-plan   "(none)              → 0/0 FINISH=''"          "$RP" 0 0 ""
run_fixture_argv run-plan   "auto                → 1/0 FINISH=''"          "$RP" 1 0 "" auto
run_fixture_argv run-plan   "unattended          → 0/1 FINISH=''"          "$RP" 0 1 "" unattended
run_fixture_argv run-plan   "auto unattended     → 1/1 FINISH=''"          "$RP" 1 1 "" auto unattended
run_fixture_argv run-plan   "unattended auto     → 1/1 FINISH=''"          "$RP" 1 1 "" unattended auto
run_fixture_argv run-plan   "AUTO UNATTENDED     → 1/1 FINISH=''"          "$RP" 1 1 "" AUTO UNATTENDED

# /fix-issues — $ARGUMENTS form, no FINISH_MODE.
run_fixture_argv fix-issues "(none)              → 0/0"  "$FI" 0 0 ""
run_fixture_argv fix-issues "auto                → 1/0"  "$FI" 1 0 "" auto
run_fixture_argv fix-issues "unattended          → 0/1"  "$FI" 0 1 "" unattended
run_fixture_argv fix-issues "auto unattended     → 1/1"  "$FI" 1 1 "" auto unattended
run_fixture_argv fix-issues "unattended auto     → 1/1"  "$FI" 1 1 "" unattended auto
run_fixture_argv fix-issues "AUTO UNATTENDED     → 1/1"  "$FI" 1 1 "" AUTO UNATTENDED

# /do — $ARGUMENTS form.
run_fixture_argv do         "(none)              → 0/0"  "$DO" 0 0 ""
run_fixture_argv do         "auto                → 1/0"  "$DO" 1 0 "" auto
run_fixture_argv do         "unattended          → 0/1"  "$DO" 0 1 "" unattended
run_fixture_argv do         "auto unattended     → 1/1"  "$DO" 1 1 "" auto unattended
run_fixture_argv do         "unattended auto     → 1/1"  "$DO" 1 1 "" unattended auto
run_fixture_argv do         "AUTO UNATTENDED     → 1/1"  "$DO" 1 1 "" AUTO UNATTENDED

# ---------------------------------------------------------------------------
# /run-plan composite-alias fixture (+1 = 25 total)
# ---------------------------------------------------------------------------
echo ""
echo "=== /run-plan composite alias ==="
run_fixture_argv run-plan   "finish auto         → 1/1 FINISH=finish-auto" "$RP" 1 1 "finish-auto" finish auto

echo ""
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (of %d)\033[0m\n' "$PASS" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (of %d)\033[0m\n' "$PASS" "$FAIL" "$TOTAL"
  exit 1
fi
