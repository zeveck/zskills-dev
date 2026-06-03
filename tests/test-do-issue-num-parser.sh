#!/bin/bash
# Tests for /do's pre-flight `#N` issue-number parser (ISSUE_NUMS
# population), issue #1032. Drives the REAL parser by extracting the
# pre-flight bash fence from skills/do/SKILL.md and running it against
# fixture descriptions — extract-and-run, so the test can't drift from
# the shipped parser logic.
#
# Coverage:
#   (c) Strong separator (`/`, `+`, `&`) only EXTENDS a contiguous chain
#       anchored on an already-claimed leading ref. Slash/plus-separated
#       CITATIONS with no claim-positioned leading ref capture nothing.
#   (a) `--no-claim` forces ISSUE_NUMS empty (claim absolutely nothing),
#       even for claim-positioned refs like `Fix #5 / #6`.
#   Regression guards: bare-leading chain, weak-separator (`,`) discipline.
#
# Run from repo root: bash tests/test-do-issue-num-parser.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/skills/do/SKILL.md"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '  \033[32mPASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

TEST_TMPDIR=$(mktemp -d -t "zskills-do-parser-XXXXXX")
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# Extract the leading pre-flight bash fence — the SAME extractor test-do.sh
# uses (between `## Pre-flight` and `## Phase 0a`, the contiguous bash fence).
PREFLIGHT_BLOCK=$(awk '
  /^## Pre-flight/      { in_section = 1; next }
  /^## Phase 0a/        { in_section = 0 }
  !in_section           { next }
  /^```bash$/           { infence = 1; next }
  infence && /^```$/    { infence = 0; print ""; next }
  infence               { print }
' "$SKILL")

if [ -z "$PREFLIGHT_BLOCK" ]; then
  fail "extract pre-flight fence (block empty — SKILL.md structure changed?)"
  printf 'PASS=%d FAIL=%d\n' "$PASS_COUNT" "$FAIL_COUNT"
  exit 1
fi

# Build a runner that sets ARGUMENTS, runs the real parser, and emits the
# resulting ISSUE_NUMS as a space-joined string. The parser's stray-ref
# block touches the filesystem (.zskills/claims/...) only when NO_CLAIM != 1
# and ISSUE_NUMS leaves a stray ref unclaimed; for the fixtures here it is
# either short-circuited (NO_CLAIM) or has no stray refs, so running from a
# throwaway dir is safe.
PARSER_SCRIPT="$TEST_TMPDIR/parser.sh"
{
  echo '#!/bin/bash'
  echo 'set -u'
  echo 'ARGUMENTS="$1"'
  echo "$PREFLIGHT_BLOCK"
  echo 'printf "%s" "${ISSUE_NUMS[*]:-}"'
} > "$PARSER_SCRIPT"
chmod +x "$PARSER_SCRIPT"

# Run the parser against $1, return the space-joined ISSUE_NUMS on stdout.
run_parser() {
  ( cd "$TEST_TMPDIR" && bash "$PARSER_SCRIPT" "$1" 2>/dev/null )
}

# assert_parse <description> <expected-space-joined> <label>
assert_parse() {
  local desc="$1" expected="$2" label="$3" got
  got=$(run_parser "$desc")
  if [ "$got" = "$expected" ]; then
    pass "$label  ['$desc'] -> ISSUE_NUMS=[$got]"
  else
    fail "$label  ['$desc'] -> got ISSUE_NUMS=[$got], expected [$expected]"
  fi
}

echo "=== /do ISSUE_NUMS parser (#1032) ==="

# (c) Strong-separator chain anchored on a claimed leading ref.
assert_parse "Fix #5 / #6"              "5 6"      "c1 slash-chain extends claimed leading ref"
assert_parse "Fix #12 + #15 + #18"      "12 15 18" "c2 plus-chain extends claimed leading ref"

# (c) Citations: strong separator with NO claim-positioned leading ref
# captures NOTHING (the over-capture bug #1032 fixed).
assert_parse "Refactor X (supersedes #999/#1004)" "" "c3 slash citation, no leading claim -> empty"
assert_parse "Tweak Y, bare-cited #960/#967"      "" "c4 slash citation, no leading claim -> empty"

# (a) --no-claim forces ISSUE_NUMS empty even for claim-positioned chains.
assert_parse "Fix #5 / #6 --no-claim"   ""         "a1 --no-claim empties claim-positioned chain"
assert_parse "#5 --no-claim"            ""         "a2 --no-claim empties bare leading ref"

# Regression guards — behaviors that must be preserved.
assert_parse "#5/#6"                    "5 6"      "r1 bare-leading ref anchors strong chain"
assert_parse "Closes #832, Closes #833" "832 833"  "r2 weak-separator with keyword still captures"
assert_parse "Closes #832, see also #999" "832"    "r3 weak-separator without keyword does not over-capture"

echo
printf 'test-do-issue-num-parser.sh: %d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
