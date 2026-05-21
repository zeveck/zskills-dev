#!/bin/bash
# Tests for skills/cleanup-merged/SKILL.md --review flag (issue #355).
#
# Coverage:
#   Static (skill-source assertions):
#     1.  argument-hint contains --review
#     2.  --review flag accepted by Phase 1.2 case statement
#     3.  --dry-run + --review mutual-exclusion check present
#     4.  Phase 7 heading present
#     5.  All 10 rule numbers (1–10) appear in the rule table
#     6.  Long-running-patterns loaded from cleanup.long_running_patterns
#     7.  Interactive picker recognizes all-suggested / none / <letter>:<verb>
#     8.  Mirror sync: skills/cleanup-merged/ == .claude/skills/cleanup-merged/
#     9.  Existing --dry-run semantics still intact (Phase 5 loop preserved)
#    10.  Schema: cleanup.long_running_patterns array field present
#
#   Dynamic (classifier behaviour via extracted function):
#    R1. locked worktree → KEEP rule 1
#    R2. branch matching pattern → KEEP rule 2
#    R3. PR=MERGED + clean → REMOVE rule 3
#    R4. PR=MERGED + dirty → DECIDE rule 4
#    R5. commits ahead + PR=OPEN → KEEP rule 5
#    R6. commits ahead + no PR + clean → MAYBE rule 6
#    R7. 0 ahead + no PR + clean + .landed=partial → DECIDE rule 7
#    R8. 0 ahead + no PR + clean + no .landed → REMOVE rule 8
#    R9. 0 ahead + no PR + dirty → DECIDE rule 9
#    R10. commits ahead + dirty → DECIDE rule 10
#
# Run from repo root: bash tests/test-cleanup-merged-review.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/skills/cleanup-merged/SKILL.md"
SCHEMA="$REPO_ROOT/config/zskills-config.schema.json"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

echo "=== cleanup-merged --review tests ==="

# ── Static checks ────────────────────────────────────────────────────

# 1. argument-hint contains --review
if grep -qE '^argument-hint:.*--review' "$SKILL"; then
  pass "argument-hint advertises --review"
else
  fail "argument-hint missing --review"
fi

# 2. --review accepted in arg parse
if grep -q -- '--review) REVIEW=1' "$SKILL"; then
  pass "Phase 1.2: --review case branch present"
else
  fail "Phase 1.2: --review case branch missing"
fi

# 3. --dry-run + --review mutual exclusion
if grep -q 'mutually exclusive' "$SKILL"; then
  pass "mutual-exclusion check between --dry-run and --review"
else
  fail "mutual-exclusion check missing"
fi

# 4. Phase 7 heading present
if grep -qE '^## Phase 7 — Review mode' "$SKILL"; then
  pass "Phase 7 heading present"
else
  fail "Phase 7 heading missing"
fi

# 5. All rules present in rule table (1–10 plus rule 11 added for issue #516)
for n in 1 2 3 4 5 6 7 8 9 10 11; do
  if grep -qE "^\| $n \|" "$SKILL"; then
    pass "rule table row $n present"
  else
    fail "rule table row $n missing"
  fi
done

# 6. long_running_patterns config consumed
if grep -q 'cleanup.long_running_patterns' "$SKILL" \
   && grep -q 'LONG_RUNNING_PATTERNS' "$SKILL"; then
  pass "cleanup.long_running_patterns wired into classifier"
else
  fail "cleanup.long_running_patterns not wired"
fi

# 7. Picker recognizes all-suggested / none / letter:verb
if grep -q 'all-suggested' "$SKILL" \
   && grep -q '"none"' "$SKILL" \
   && grep -q '\[A-Za-z\]+):(\[a-z\]+)' "$SKILL"; then
  pass "picker accepts all-suggested, none, and <letter>:<verb>"
else
  fail "picker forms incomplete"
fi

# 8. Mirror sync
MIRROR="$REPO_ROOT/.claude/skills/cleanup-merged"
if [ -d "$MIRROR" ]; then
  if diff -q "$SKILL" "$MIRROR/SKILL.md" >/dev/null; then
    pass "mirror sync: skills/cleanup-merged/SKILL.md == .claude mirror"
  else
    fail "mirror drift: skills/ vs .claude/skills/ differ"
  fi
else
  fail "mirror directory .claude/skills/cleanup-merged absent"
fi

# 9. --dry-run path preserved (Phase 5 unchanged for non-review)
if grep -q 'WOULD-DELETE' "$SKILL" && grep -q 'WOULD-REMOVE-WORKTREE' "$SKILL"; then
  pass "Phase 5 dry-run output strings preserved"
else
  fail "Phase 5 dry-run output regressed"
fi

# 10. Schema field
if grep -q '"long_running_patterns"' "$SCHEMA" \
   && grep -q '"cleanup"' "$SCHEMA"; then
  pass "schema: cleanup.long_running_patterns defined"
else
  fail "schema: cleanup.long_running_patterns missing"
fi

# ── Dynamic checks (extract classify() and exercise each rule) ───────
#
# The classify() function is embedded inside the Phase 7 WI 7.2 bash
# fence. Extract it into a temporary shim script, source it, and call
# it with synthetic signal values for each of the 10 rules.

WORK="/tmp/zskills-tests/$(basename "$REPO_ROOT")/cleanup-merged-review"
rm -rf "$WORK"
mkdir -p "$WORK"

CLASSIFIER_SHIM="$WORK/classifier-shim.sh"

# AWK extracts everything from the `# Classifier — given branch ...`
# comment line through the closing `}` of the function.
awk '
  /^  # Classifier — given branch/ { capturing = 1 }
  capturing { print }
  capturing && /^  \}$/ { exit }
' "$SKILL" > "$WORK/classify-fn-body.txt"

# matches_long_running helper is also needed — extract it the same way.
awk '
  /^  matches_long_running\(\) \{/ { capturing = 1 }
  capturing { print }
  capturing && /^  \}$/ { count++; if (count >= 1) exit }
' "$SKILL" > "$WORK/matches-fn-body.txt"

{
  echo "#!/bin/bash"
  echo "set -u"
  echo "LONG_RUNNING_PATTERNS=(\"\${@:1}\")"
  # Source the matches_long_running fn body.
  cat "$WORK/matches-fn-body.txt"
  # Source the classify fn body.
  cat "$WORK/classify-fn-body.txt"
  echo ""
  # Reset positional args before invoking classify (re-used via env).
  echo "VERDICT=\"\"; RULE_NUM=\"\"; RULE_DESC=\"\""
  echo "classify \"\$BR\" \"\$WT\" \"\$LK\" \"\$AH\" \"\$UG\" \"\$PR\" \"\$DT\" \"\$LS\""
  echo "echo \"VERDICT=\$VERDICT RULE_NUM=\$RULE_NUM\""
} > "$CLASSIFIER_SHIM"
chmod +x "$CLASSIFIER_SHIM"

# Sanity: the extracted classify body must contain `VERDICT=` assignments.
if ! grep -q 'VERDICT="KEEP"' "$WORK/classify-fn-body.txt"; then
  fail "extracted classify() body looks empty/malformed — aborting dynamic checks"
  echo ""
  echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
  [ "$FAIL_COUNT" -eq 0 ] && exit 0 || exit 1
fi

# Helper to call the shim with named signal vars.
run_classify() {
  local desc="$1" want_v="$2" want_n="$3"
  shift 3
  local out
  out=$("$@" bash "$CLASSIFIER_SHIM" 2>&1)
  if echo "$out" | grep -q "VERDICT=$want_v RULE_NUM=$want_n"; then
    pass "rule $want_n: $desc → $want_v"
  else
    fail "rule $want_n: $desc → expected $want_v/$want_n, got: $out"
  fi
}

# Rule 1: locked worktree → KEEP rule 1
run_classify "locked worktree" "KEEP" "1" \
  env BR="feat/x" WT="/tmp/x" LK="1" AH="0" UG="0" PR="" DT="" LS=""

# Rule 2: branch matches long_running pattern (docs/run-order-guide)
LRP=("docs/run-order-guide" "release/*")
out=$(env BR="docs/run-order-guide" WT="/tmp/x" LK="0" AH="5" UG="0" PR="" DT="" LS="" \
  bash "$CLASSIFIER_SHIM" "${LRP[@]}" 2>&1)
if echo "$out" | grep -q "VERDICT=KEEP RULE_NUM=2"; then
  pass "rule 2: long_running_patterns exact match → KEEP"
else
  fail "rule 2: expected KEEP/2, got: $out"
fi
out=$(env BR="release/1.2" WT="/tmp/x" LK="0" AH="5" UG="0" PR="" DT="" LS="" \
  bash "$CLASSIFIER_SHIM" "${LRP[@]}" 2>&1)
if echo "$out" | grep -q "VERDICT=KEEP RULE_NUM=2"; then
  pass "rule 2: long_running_patterns glob match (release/*) → KEEP"
else
  fail "rule 2 glob: expected KEEP/2, got: $out"
fi

# Rule 3: PR=MERGED + clean + ahead=0 (issue #516 — ahead>0 is gated by rule 11)
run_classify "PR=MERGED + clean + ahead=0" "REMOVE" "3" \
  env BR="feat/x" WT="/tmp/x" LK="0" AH="0" UG="0" PR="MERGED" DT="" LS=""
# Rule 3 via upstream-gone (squash-merge is fine; unpushed guard handles
# the un-squashed leak path in Phase 5)
run_classify "upstream-gone + clean" "REMOVE" "3" \
  env BR="feat/x" WT="/tmp/x" LK="0" AH="3" UG="1" PR="" DT="" LS=""

# Rule 11 (issue #516): PR=MERGED + ahead>0 → DECIDE (was previously
# silently classified REMOVE — the silent-commit-loss bug)
run_classify "PR=MERGED + ahead>0 (diverged)" "DECIDE" "11" \
  env BR="feat/x" WT="/tmp/x" LK="0" AH="3" UG="0" PR="MERGED" DT="" LS=""

# Rule 4: merged + dirty (Rule 11 short-circuits if ahead>0, so use ahead=0)
run_classify "PR=MERGED + dirty + ahead=0" "DECIDE" "4" \
  env BR="feat/x" WT="/tmp/x" LK="0" AH="0" UG="0" PR="MERGED" DT="M f.txt" LS=""

# Rule 5: commits ahead + PR=OPEN
run_classify "commits ahead + PR=OPEN" "KEEP" "5" \
  env BR="feat/x" WT="/tmp/x" LK="0" AH="2" UG="0" PR="OPEN" DT="" LS=""

# Rule 6: commits ahead + no PR + clean
run_classify "ahead + no PR + clean" "MAYBE" "6" \
  env BR="feat/x" WT="/tmp/x" LK="0" AH="2" UG="0" PR="" DT="" LS=""

# Rule 7: 0 ahead + no PR + clean + .landed=partial
run_classify "0 ahead + .landed=partial" "DECIDE" "7" \
  env BR="feat/x" WT="/tmp/x" LK="0" AH="0" UG="0" PR="" DT="" LS="partial"

# Rule 8: 0 ahead + no PR + clean + no .landed
run_classify "0 ahead + no PR + clean + no .landed" "REMOVE" "8" \
  env BR="feat/x" WT="/tmp/x" LK="0" AH="0" UG="0" PR="" DT="" LS=""

# Rule 9: 0 ahead + no PR + dirty
run_classify "0 ahead + dirty" "DECIDE" "9" \
  env BR="feat/x" WT="/tmp/x" LK="0" AH="0" UG="0" PR="" DT="M f.txt" LS=""

# Rule 10: commits ahead + dirty (no OPEN PR — rule 5 takes priority otherwise)
run_classify "ahead + dirty" "DECIDE" "10" \
  env BR="feat/x" WT="/tmp/x" LK="0" AH="2" UG="0" PR="" DT="M f.txt" LS=""
# Wait — rule 6 (ahead + no PR + clean) is "MAYBE", but ahead + no PR + dirty
# falls through 6 (dirty), 7 (ahead>0), 8 (ahead>0), 9 (ahead>0), to 10. Good.

# Bonus: rule 5 + dirty should still hit rule 5 (PR=OPEN beats dirty).
run_classify "rule 5 wins over dirty (PR=OPEN + dirty)" "KEEP" "5" \
  env BR="feat/x" WT="/tmp/x" LK="0" AH="2" UG="0" PR="OPEN" DT="M f.txt" LS=""

# .landed=landed: rule 7 doesn't fire (condition is `!= landed`); rule 8
# requires absence of .landed → so this falls through to DECIDE/0.
# This is safe-by-design: an unrecognised .landed value is surfaced for
# manual review rather than silently removed.
run_classify ".landed=landed → fallthrough DECIDE" "DECIDE" "0" \
  env BR="feat/x" WT="/tmp/x" LK="0" AH="0" UG="0" PR="" DT="" LS="landed"

# .landed=full: similar — rule 7 skips (we treat 'full' like 'landed' as
# a success marker), rule 8 needs empty .landed, so this also DECIDEs.
run_classify ".landed=full → fallthrough DECIDE" "DECIDE" "0" \
  env BR="feat/x" WT="/tmp/x" LK="0" AH="0" UG="0" PR="" DT="" LS="full"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] && exit 0 || exit 1
