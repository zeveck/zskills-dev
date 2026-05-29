#!/bin/bash
# Behavioral smoke for /draft-plan's deterministic argument-parsing surface.
#
# Covers two executable surfaces of skills/draft-plan/SKILL.md:
#   1. OUTPUT_FILE / TRACKING_ID resolution (the `for tok in $ARGUMENTS`
#      loop + `case` + timestamped fallback + TRACKING_ID kebab derivation,
#      ≈ SKILL.md:69-81). This block's first line SOURCES zskills-paths.sh
#      and depends on $CLAUDE_PROJECT_DIR / $ARGUMENTS / $ZSKILLS_PLANS_DIR,
#      so it is NOT self-contained -> EMBED a faithful copy + a `grep -qF`
#      PARITY gate on the fingerprint lines so source drift fails the test.
#   2. AUTO_FLAG regex (the whitespace-anchored, case-insensitive
#      `[aA][uU][tT][oO]` match, ≈ SKILL.md:144-148). This block IS
#      self-contained (pure `[[ =~ ]]`) -> EXTRACT-AND-RUN the real fence.
#
# All fixtures synthesized; no network; no real gh.
#
# Run from repo root: bash tests/test-draft-plan-args-smoke.sh

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/skills/draft-plan/SKILL.md"
PASS_COUNT=0; FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

echo "=== draft-plan args behavioral smoke ==="

# ── Surface 1: OUTPUT_FILE / TRACKING_ID resolution (embed + parity) ──
# PARITY GATE: assert the embedded copy's fingerprint lines still match the
# SKILL.md source. If the source loop changes, these fail and force a sync.
# Fingerprints: the arg loop header + the two case arms + the kebab derive.
if grep -qF 'for tok in $ARGUMENTS; do' "$SKILL"; then
  pass "parity: 'for tok in \$ARGUMENTS; do' present in SKILL.md"
else
  fail "parity: arg-loop header drifted" "missing 'for tok in \$ARGUMENTS; do'"
fi
if grep -qF '*/*.md) OUTPUT_FILE="$tok"; break ;;' "$SKILL" \
   && grep -qF '*.md)   OUTPUT_FILE="$ZSKILLS_PLANS_DIR/$tok"; break ;;' "$SKILL"; then
  pass "parity: OUTPUT_FILE case arms present in SKILL.md"
else
  fail "parity: OUTPUT_FILE case arms drifted" "case arm fingerprint mismatch"
fi
if grep -qF "TRACKING_ID=\$(basename \"\$OUTPUT_FILE\" .md | tr '[:upper:]' '[:lower:]' | tr '_' '-')" "$SKILL"; then
  pass "parity: TRACKING_ID kebab-derivation present in SKILL.md"
else
  fail "parity: TRACKING_ID derivation drifted" "kebab fingerprint mismatch"
fi

# Embedded faithful copy of the resolution logic (zskills-paths.sh source
# replaced by a stubbed $ZSKILLS_PLANS_DIR, the only external dependency).
resolve() { # $1 = ARGUMENTS string
  local ARGUMENTS="$1"
  local OUTPUT_FILE=""
  local ZSKILLS_PLANS_DIR="/plans"
  if [ -z "${OUTPUT_FILE:-}" ]; then
    for tok in $ARGUMENTS; do
      case "$tok" in
        */*.md) OUTPUT_FILE="$tok"; break ;;
        *.md)   OUTPUT_FILE="$ZSKILLS_PLANS_DIR/$tok"; break ;;
      esac
    done
    : "${OUTPUT_FILE:=$ZSKILLS_PLANS_DIR/FALLBACK_PLAN.md}"
  fi
  local TRACKING_ID
  TRACKING_ID=$(basename "$OUTPUT_FILE" .md | tr '[:upper:]' '[:lower:]' | tr '_' '-')
  echo "OUTPUT_FILE=$OUTPUT_FILE"
  echo "TRACKING_ID=$TRACKING_ID"
}

# Case A: path token (contains /) used as-is.
R=$(resolve "plans/THERMAL_PLAN.md Implement thermal domain")
if echo "$R" | grep -qx 'OUTPUT_FILE=plans/THERMAL_PLAN.md' \
   && echo "$R" | grep -qx 'TRACKING_ID=thermal-plan'; then
  pass "resolve: path token -> used as-is + kebab TRACKING_ID"
else
  fail "resolve: path token" "got: $R"
fi

# Case B: bare .md name -> $ZSKILLS_PLANS_DIR/<name>.
R=$(resolve "THERMAL_PLAN.md Implement thermal domain")
if echo "$R" | grep -qx 'OUTPUT_FILE=/plans/THERMAL_PLAN.md' \
   && echo "$R" | grep -qx 'TRACKING_ID=thermal-plan'; then
  pass "resolve: bare .md -> \$ZSKILLS_PLANS_DIR/<name>"
else
  fail "resolve: bare .md name" "got: $R"
fi

# Case C: no .md token -> timestamped/fallback default under plans dir.
R=$(resolve "Add dark mode to the editor")
if echo "$R" | grep -qE '^OUTPUT_FILE=/plans/.*\.md$'; then
  pass "resolve: no .md token -> fallback default under \$ZSKILLS_PLANS_DIR"
else
  fail "resolve: no .md fallback" "got: $R"
fi

# ── Surface 2: AUTO_FLAG regex (extract-and-run) ────────────────────
# Extract the self-contained AUTO_FLAG fence and run it verbatim.
AUTO_BLOCK=$(awk '
  /^AUTO_FLAG=0$/{capture=1}
  capture {print}
  capture && /^fi$/{exit}
' "$SKILL")

if [ -z "$AUTO_BLOCK" ]; then
  fail "auto-flag: could not extract AUTO_FLAG fence" "awk extract empty"
else
  pass "auto-flag: AUTO_FLAG fence extracted from SKILL.md"
  check_auto() { # $1=ARGUMENTS $2=expected(0/1) $3=label
    local ARGUMENTS="$1"
    local AUTO_FLAG
    eval "$AUTO_BLOCK"
    if [ "$AUTO_FLAG" = "$2" ]; then
      pass "auto-flag: $3 -> AUTO_FLAG=$2"
    else
      fail "auto-flag: $3" "expected $2 got $AUTO_FLAG"
    fi
  }
  check_auto "auto Build the thing" 1 "leading 'auto' (lowercase)"
  check_auto "Build the thing AUTO" 1 "trailing 'AUTO' (uppercase)"
  check_auto "Build it auto now" 1 "mid 'auto' word-bounded"
  check_auto "automatic dark mode" 0 "'automatic' (no boundary) rejected"
  check_auto "engage autopilot" 0 "'autopilot' (no boundary) rejected"
  check_auto "use auto-land mode" 0 "'auto-land' (no whitespace boundary) rejected"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] && exit 0 || exit 1
