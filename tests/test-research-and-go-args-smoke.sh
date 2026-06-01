#!/bin/bash
# Behavioral smoke for /research-and-go's landing-mode detection regex
# (skills/research-and-go/SKILL.md, the "Landing mode detection" fence
# ≈ SKILL.md:282-294), PLUS a labeled presence-anchor for the model-layer
# decompose→dispatch core.
#
# TWO layers, deliberately distinct:
#
#   1. EXTRACT-AND-RUN (behavioral): the landing-mode regex is pure shell —
#      `[[ "$GOAL" =~ (^|[[:space:]])[pP][rR]($|[[:space:]]|[.!?]) ]]`. We
#      extract the REAL production fence and run it against seeded $GOAL
#      strings: `pr`/`PR` positives, `direct` positive, and word-boundary
#      NEGATIVES that must NOT match (`reproduce the bug` must not match
#      `pr`; `approve` must not match anything). This catches a regex that
#      drops the word-boundary anchors and starts substring-matching.
#
#   2. ANCHOR-GREP (presence, NOT behavior — model-layer): the
#      decompose→dispatch core (Agent-tool preflight + dispatched
#      /draft-plan + /run-plan cron construction) is JUDGMENT-class model
#      behavior, not deterministic shell. We do NOT build a harness for it
#      (there is nothing to execute deterministically). We assert only that
#      the dispatch lines + the Agent-tool preflight are PRESENT, so a future
#      edit that deletes them trips a failure. This is presence, not
#      behavior, by design.
#
# Fixtures: none needed (the regex fence touches no filesystem). No network.
#
# Run from repo root: bash tests/test-research-and-go-args-smoke.sh

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/skills/research-and-go/SKILL.md"
# shellcheck source=tests/lib/extract-fence.sh
. "$SCRIPT_DIR/lib/extract-fence.sh"
PASS_COUNT=0; FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

echo "=== research-and-go landing-mode regex (extract-and-run) ==="

# ── Layer 1: extract the REAL landing-mode regex fence ──────────────
# Bracket on the "### Landing mode detection" heading and the post-fence
# "Where `$GOAL` is the original description" sentence so exactly one
# ```bash block (the regex fence) extracts.
FENCE="$(extract_fence_between "$SKILL" \
  '^### Landing mode detection' \
  '^Where ..GOAL.. is the original description' 1 0)" || {
  echo "could not extract research-and-go landing-mode fence" >&2
  echo "Results: 0 passed, 1 failed"; exit 1
}
if printf '%s\n' "$FENCE" | grep -qF 'if [[ "$GOAL" =~ (^|[[:space:]])[pP][rR]($|[[:space:]]|[.!?]) ]]; then' \
   && printf '%s\n' "$FENCE" | grep -qF 'LANDING_ARG="pr"' \
   && printf '%s\n' "$FENCE" | grep -qF 'LANDING_ARG="direct"'; then
  pass "extract: real fence carries the word-boundary pr/PR/direct regex"
else
  fail "extract: landing-mode fence missing load-bearing lines" "extraction drifted"
fi

# detect_landing — seed $GOAL, run the EXTRACTED production fence, echo result.
detect_landing() {
  local GOAL="$1"
  # The fence reads $GOAL/$DESCRIPTION/$ARGUMENTS; seed the others empty so
  # the `GOAL="${GOAL:-${DESCRIPTION:-$ARGUMENTS}}"` line keeps our $GOAL.
  local DESCRIPTION="" ARGUMENTS="" LANDING_ARG
  eval "$FENCE"
  printf '%s' "$LANDING_ARG"
}

# Positives.
R=$(detect_landing "Add thermal domain pr"); [ "$R" = "pr" ] \
  && pass "positive: trailing 'pr' -> pr" \
  || fail "positive: 'pr' not detected" "got '$R'"
R=$(detect_landing "Add thermal domain PR"); [ "$R" = "pr" ] \
  && pass "positive: uppercase 'PR' -> pr" \
  || fail "positive: 'PR' not detected" "got '$R'"
R=$(detect_landing "Add thermal domain. PR."); [ "$R" = "pr" ] \
  && pass "positive: 'PR' bounded by sentence punctuation -> pr" \
  || fail "positive: punctuation-bounded 'PR' not detected" "got '$R'"
R=$(detect_landing "pr first then the rest"); [ "$R" = "pr" ] \
  && pass "positive: leading 'pr' (start anchor) -> pr" \
  || fail "positive: leading 'pr' not detected" "got '$R'"
R=$(detect_landing "Refactor logs direct"); [ "$R" = "direct" ] \
  && pass "positive: trailing 'direct' -> direct" \
  || fail "positive: 'direct' not detected" "got '$R'"

# Word-boundary NEGATIVES — the whole point of the (^|space)…(space|end|punct)
# anchors. A substring matcher would WRONGLY fire on these.
R=$(detect_landing "reproduce the bug"); [ -z "$R" ] \
  && pass "negative: 'reproduce' does NOT match 'pr' (word-boundary)" \
  || fail "negative: 'reproduce' wrongly matched" "got '$R'"
R=$(detect_landing "approve the change"); [ -z "$R" ] \
  && pass "negative: 'approve' does NOT match 'pr' (word-boundary)" \
  || fail "negative: 'approve' wrongly matched" "got '$R'"
R=$(detect_landing "improve the prose"); [ -z "$R" ] \
  && pass "negative: 'improve'/'prose' do NOT match 'pr'" \
  || fail "negative: 'improve'/'prose' wrongly matched" "got '$R'"
R=$(detect_landing "indirect dependency redirect"); [ -z "$R" ] \
  && pass "negative: 'indirect'/'redirect' do NOT match 'direct'" \
  || fail "negative: 'direct' substring wrongly matched" "got '$R'"
R=$(detect_landing "Add a plain feature"); [ -z "$R" ] \
  && pass "negative: no keyword -> empty LANDING_ARG (config default)" \
  || fail "negative: spurious landing arg on neutral goal" "got '$R'"

echo ""
echo "=== research-and-go decompose→dispatch core (presence, NOT behavior — model-layer) ==="
# These are JUDGMENT-class model dispatches, not deterministic shell — there
# is nothing to execute. We anchor-grep that the dispatch surface is PRESENT
# so a future edit deleting it trips this suite. Presence, not behavior.

if grep -qF 'requires top-level Agent dispatch capability' "$SKILL"; then
  pass "presence (model-layer): Agent-tool preflight refusal line present"
else
  fail "presence: Agent-tool preflight refusal line missing" "decompose core not gated"
fi
if grep -qF 'Drafts each sub-plan via dispatched `/draft-plan` agents' "$SKILL"; then
  pass "presence (model-layer): dispatched /draft-plan decomposition line present"
else
  fail "presence: dispatched /draft-plan line missing" "decompose core drifted"
fi
if grep -qF 'RUN_PROMPT="Run /run-plan $META_PLAN_PATH finish auto $LANDING_ARG"'  "$SKILL" \
   && grep -qF 'RUN_PROMPT="Run /run-plan $META_PLAN_PATH finish auto"' "$SKILL"; then
  pass "presence (model-layer): /run-plan dispatch prompt construction present (with + without LANDING_ARG)"
else
  fail "presence: /run-plan dispatch prompt construction missing" "dispatch core drifted"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] && exit 0 || exit 1
