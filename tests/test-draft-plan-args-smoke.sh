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
# Extract the self-contained AUTOMERGE_FLAG + AUTO_FLAG fence and run it
# verbatim. The AUTO_FLAG condition references $AUTOMERGE_FLAG (automerge
# implies auto), so the extracted unit MUST begin at the AUTOMERGE_FLAG=0
# init — otherwise the eval below hits an unbound $AUTOMERGE_FLAG under
# `set -u`. Capture from AUTOMERGE_FLAG=0 through the first `fi` that
# follows AUTO_FLAG=0.
AUTO_BLOCK=$(awk '
  /^AUTOMERGE_FLAG=0$/{capture=1}
  capture {print}
  /^AUTO_FLAG=0$/{seen_auto=1}
  capture && seen_auto && /^fi$/{exit}
' "$SKILL")

if [ -z "$AUTO_BLOCK" ]; then
  fail "auto-flag: could not extract AUTOMERGE_FLAG/AUTO_FLAG fence" "awk extract empty"
else
  pass "auto-flag: AUTOMERGE_FLAG/AUTO_FLAG fence extracted from SKILL.md"
  check_auto() { # $1=ARGUMENTS $2=expected(0/1) $3=label
    local ARGUMENTS="$1"
    local AUTO_FLAG AUTOMERGE_FLAG
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
  check_auto "automerge Build the thing" 1 "'automerge' implies auto (AUTO_FLAG=1)"
fi

# ── Surface 3: STEERING_MODE leading-cluster selector (extract-and-run) ──
# #944: brainstorm and quiz are a SINGLE mutually-exclusive selector
# `STEERING_MODE ∈ {"", brainstorm, quiz}` detected by ONE leading-cluster
# scan (the `set_steering` helper + the `for tok in $ARGUMENTS` case). The
# fence is self-contained (no external deps), so EXTRACT-AND-RUN it. The
# fence runs from `STEERING_MODE=""` through its closing `done`, so capture
# from the assignment to the first standalone `done`. A conflicting second
# steering token makes `set_steering` `exit 2`, so we run the fence in a
# subshell and capture both STEERING_MODE and the exit code.
STEERING_BLOCK=$(awk '
  /^STEERING_MODE=""/{capture=1}
  capture {print}
  capture && /^done$/{exit}
' "$SKILL")

if [ -z "$STEERING_BLOCK" ]; then
  fail "steering-mode: could not extract STEERING_MODE fence" "awk extract empty"
else
  pass "steering-mode: STEERING_MODE leading-cluster fence extracted from SKILL.md"

  # Tokenizer-arm parity: both steering arms route through set_steering (#944).
  if grep -qF 'brainstorm) set_steering brainstorm ;;' "$SKILL" \
     && grep -qF 'quiz)       set_steering quiz ;;' "$SKILL"; then
    pass "steering-mode: both case arms route through set_steering (#944)"
  else
    fail "steering-mode: set_steering case arms drifted" "missing 'brainstorm) set_steering brainstorm' / 'quiz) set_steering quiz'"
  fi

  # Run the real fence against $ARGUMENTS in a subshell; STEERING_MODE is
  # written to a dedicated file (NOT stderr) so set_steering's own stderr
  # error message does not contaminate the capture; the `exit 2` becomes the
  # subshell rc.
  steer_for() { # $1=ARGUMENTS $2=modefile  -> exit code = set_steering rc
    (
      ARGUMENTS="$1"
      STEERING_MODE=""
      eval "$STEERING_BLOCK"
      printf 'MODE=%s\n' "$STEERING_MODE" > "$2"
    ) 2>/dev/null
  }
  check_steer() { # $1=ARGUMENTS $2=expected_mode $3=expected_rc $4=label
    local rc md mf="/tmp/.draftplan-steering-mode-$$" want
    steer_for "$1" "$mf"; rc=$?
    md=$(cat "$mf" 2>/dev/null); rm -f "$mf"
    # In the conflict path, set_steering's `exit 2` aborts the subshell BEFORE
    # the MODE printf runs, so the modefile is never written and $md is empty.
    # The exit code is the load-bearing assertion there. In the success path
    # (rc 0) the modefile carries 'MODE=<mode>'.
    if [ "$3" = "0" ]; then want="MODE=$2"; else want=""; fi
    if [ "$md" = "$want" ] && [ "$rc" = "$3" ]; then
      pass "steering-mode: $4 -> '${md:-<no-write>}', exit $rc"
    else
      fail "steering-mode: $4" "expected mode-capture '$want' exit $3, got '$md' exit $rc"
    fi
  }

  # Positives — leading flag, case-insensitive.
  check_steer "brainstorm Add dark mode" brainstorm 0 "leading 'brainstorm' engages"
  check_steer "BRAINSTORM Add dark mode" brainstorm 0 "leading uppercase 'BRAINSTORM' engages"
  check_steer "Brainstorm a new editor" brainstorm 0 "leading mixed-case 'Brainstorm' engages"
  check_steer "quiz Add dark mode" quiz 0 "leading 'quiz' engages"
  # Composability parity (#944): brainstorm in the leading cluster (not token[0]).
  check_steer "output p.md brainstorm Add dark mode" brainstorm 0 "'output p.md brainstorm' engages brainstorm (composability parity)"
  check_steer "output p.md quiz rounds 5 Add dark mode" quiz 0 "'output p.md quiz rounds 5' engages quiz (leading cluster, any order)"
  # Repeated SAME token is a harmless no-op (no error).
  check_steer "brainstorm brainstorm Add dark mode" brainstorm 0 "repeated 'brainstorm' -> no-op, no error"
  # Mutual exclusion (#936, #944) — order-independent: BOTH orders exit 2.
  # set_steering's `exit 2` aborts the fence BEFORE the MODE printf runs, so
  # the captured MODE is empty in BOTH error paths; the exit code is the
  # load-bearing assertion (the order-independence proof).
  check_steer "brainstorm quiz Add dark mode" "" 2 "'brainstorm quiz X' -> mutual-exclusion error (exit 2)"
  check_steer "quiz brainstorm Add dark mode" "" 2 "'quiz brainstorm X' -> mutual-exclusion error (exit 2), ORDER-INDEPENDENT (#944)"
  # Negatives — token anywhere but the leading cluster must NOT engage (#914).
  check_steer "Add dark mode brainstorm" "" 0 "trailing 'brainstorm' does NOT engage (#914)"
  check_steer "add dark mode quiz" "" 0 "trailing 'quiz' does NOT engage (#914)"
  check_steer "Build a brainstorm app for kids" "" 0 "'brainstorm' inside description does NOT engage (#914)"
  check_steer "build a quiz app" "" 0 "'quiz' inside description does NOT engage (#914)"
  check_steer "Add a brainstorm feature to the editor" "" 0 "'brainstorm' inside description does NOT engage (#914)"
  check_steer "auto brainstorm Add dark mode" brainstorm 0 "'auto brainstorm X' -> brainstorm (leading cluster, composes with auto; #944)"
  # Negatives — substring/inflection forms must NOT trip the selector (exact-match arms).
  check_steer "brainstorming the design" "" 0 "'brainstorming' (exact-match arm) does NOT engage"
  check_steer "brainstormed yesterday" "" 0 "'brainstormed' (exact-match arm) does NOT engage"
  check_steer "brainstorms" "" 0 "'brainstorms' (exact-match arm) does NOT engage"
  check_steer "quizzes for the class" "" 0 "'quizzes' (exact-match arm) does NOT engage"
fi

# ── Surface 4: brainstorm-mode wiring parity greps (externally-sourced) ──
# These fences are NOT self-contained (they live in prose / depend on the
# Read-tool dispatch and $TRACKING_ID), so assert by fingerprint grep that
# the wiring stays present, mirroring the Surface-1 `grep -qF` parity style.

# Conditional-load parity: references/brainstorm.md is gated on STEERING_MODE,
# i.e. the Read is NOT unconditional. The "## Brainstorm mode" section opens
# with the `If STEERING_MODE = brainstorm, **Read [references/brainstorm.md]...` gate.
if grep -qF 'If `STEERING_MODE = brainstorm`, **Read [references/brainstorm.md](references/brainstorm.md)**' "$SKILL"; then
  pass "conditional-load: brainstorm.md Read is gated on STEERING_MODE = brainstorm"
else
  fail "conditional-load: brainstorm.md gate drifted" "missing STEERING_MODE = brainstorm Read gate"
fi
# Regression guard: the gate must NOT re-introduce the inert ZSKILLS_PIPELINE_ID
# check. Scope the assertion to the "## Brainstorm mode" section so unrelated
# PIPELINE_ID uses elsewhere in SKILL.md (tracking fences) don't false-positive.
BRAINSTORM_SECTION=$(awk '
  /^## Brainstorm mode/{capture=1; next}
  /^## /{if (capture) exit}
  capture {print}
' "$SKILL")
if printf '%s' "$BRAINSTORM_SECTION" | grep -qF 'ZSKILLS_PIPELINE_ID'; then
  fail "conditional-load: brainstorm gate references ZSKILLS_PIPELINE_ID" "inert check re-added"
else
  pass "conditional-load: brainstorm gate does NOT reference ZSKILLS_PIPELINE_ID"
fi

# Resume-contract: the brainstorm-mode prose wires the resume state machine
# on the notes-file status markers (status: ready / status: in-progress).
if printf '%s' "$BRAINSTORM_SECTION" | grep -qF 'status: ready' \
   && printf '%s' "$BRAINSTORM_SECTION" | grep -qF 'status: in-progress'; then
  pass "resume-contract: brainstorm prose references status: ready / status: in-progress"
else
  fail "resume-contract: brainstorm resume states drifted" "missing status: ready / status: in-progress"
fi

# Feed-forward: the brainstorm-mode research dispatch injects the notes-file
# path /tmp/draft-plan-brainstorm-<id>.md into each research agent prompt.
if grep -qF '/tmp/draft-plan-brainstorm-' "$SKILL"; then
  pass "feed-forward: research dispatch references /tmp/draft-plan-brainstorm- notes path"
else
  fail "feed-forward: notes-file path drifted" "missing /tmp/draft-plan-brainstorm-"
fi

# Checkpoint-skip: the post-research steering checkpoint is gated on
# STEERING_MODE = brainstorm (skipped because the user already steered in dialogue).
if grep -qF 'Skip this steering checkpoint when `STEERING_MODE = brainstorm`' "$SKILL"; then
  pass "checkpoint-skip: post-research checkpoint gated on STEERING_MODE = brainstorm"
else
  fail "checkpoint-skip: checkpoint gate drifted" "missing 'Skip this steering checkpoint when STEERING_MODE = brainstorm'"
fi

# ── Surface 5: references/brainstorm.md idiom parity greps ───────────
# Round-2 regression guards: the verified playwright / serve-wait idioms in
# references/brainstorm.md must not regress to the buggy forms.
BRAINSTORM_REF="$REPO_ROOT/skills/draft-plan/references/brainstorm.md"
if [ ! -f "$BRAINSTORM_REF" ]; then
  fail "brainstorm.md idioms: reference file missing" "$BRAINSTORM_REF not found"
else
  # playwright-cli open MUST precede screenshot (bare screenshot file://… errors
  # "browser 'default' is not open"). Anchor on the FENCED command lines (start
  # of line, no leading backtick) so inline prose like `playwright-cli screenshot`
  # — which legitimately appears earlier when documenting the gotcha — is ignored.
  OPEN_LINE=$(grep -nE '^playwright-cli open' "$BRAINSTORM_REF" | head -1 | cut -d: -f1)
  SHOT_LINE=$(grep -nE '^playwright-cli screenshot' "$BRAINSTORM_REF" | head -1 | cut -d: -f1)
  if [ -n "$OPEN_LINE" ] && [ -n "$SHOT_LINE" ] && [ "$OPEN_LINE" -lt "$SHOT_LINE" ]; then
    pass "brainstorm.md idioms: 'playwright-cli open' precedes 'screenshot'"
  else
    fail "brainstorm.md idioms: open/screenshot order" "open=$OPEN_LINE screenshot=$SHOT_LINE (open must precede)"
  fi
  # Pidfile write must have NO trailing space after the redirect target
  # (`echo "$!" > "$DEMO_DIR/.serve.pid"` — a trailing space breaks `ps -p`).
  if grep -qF 'echo "$!" > "$DEMO_DIR/.serve.pid"' "$BRAINSTORM_REF"; then
    pass "brainstorm.md idioms: pidfile write has no trailing space"
  else
    fail "brainstorm.md idioms: pidfile write drifted" "missing exact 'echo \"\$!\" > \"\$DEMO_DIR/.serve.pid\"'"
  fi
  # The serve-wait must contain NO bare foreground `sleep` (harness-blocked);
  # the timeout-bounded busy-wait is the sleep-free substitute. Assert no
  # fenced bash line invokes `sleep` as a command.
  if grep -nE '(^|[^[:alnum:]_])sleep[[:space:]]+[0-9]' "$BRAINSTORM_REF" | grep -vq '`sleep`'; then
    fail "brainstorm.md idioms: bare 'sleep' present in serve-wait" "$(grep -nE '(^|[^[:alnum:]_])sleep[[:space:]]+[0-9]' "$BRAINSTORM_REF" | grep -v '`sleep`')"
  else
    pass "brainstorm.md idioms: no bare foreground 'sleep' in serve-wait"
  fi
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] && exit 0 || exit 1
