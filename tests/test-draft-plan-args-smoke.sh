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

# ── Surface 3: BRAINSTORM_FLAG regex (extract-and-run) ───────────────
# The BRAINSTORM_FLAG fence is self-contained (pure `[[ =~ ]]`) and lives
# in its OWN block (kept separate from AUTO_FLAG so the AUTO extractor that
# stops at the first `^fi$` is not perturbed). Extract it verbatim and run.
BRAINSTORM_BLOCK=$(awk '
  /^BRAINSTORM_FLAG=0$/{capture=1}
  capture {print}
  capture && /^fi$/{exit}
' "$SKILL")

if [ -z "$BRAINSTORM_BLOCK" ]; then
  fail "brainstorm-flag: could not extract BRAINSTORM_FLAG fence" "awk extract empty"
else
  pass "brainstorm-flag: BRAINSTORM_FLAG fence extracted from SKILL.md"
  check_brainstorm() { # $1=ARGUMENTS $2=expected(0/1) $3=label
    local ARGUMENTS="$1"
    local BRAINSTORM_FLAG
    eval "$BRAINSTORM_BLOCK"
    if [ "$BRAINSTORM_FLAG" = "$2" ]; then
      pass "brainstorm-flag: $3 -> BRAINSTORM_FLAG=$2"
    else
      fail "brainstorm-flag: $3" "expected $2 got $BRAINSTORM_FLAG"
    fi
  }
  # Positives — first token only, case-insensitive (#914).
  check_brainstorm "brainstorm Add dark mode" 1 "first-position 'brainstorm' engages"
  check_brainstorm "BRAINSTORM Add dark mode" 1 "first-position uppercase 'BRAINSTORM' engages"
  check_brainstorm "Brainstorm a new editor" 1 "first-position mixed-case 'Brainstorm' engages"
  # Negatives — 'brainstorm' anywhere but first token must NOT engage (#914).
  check_brainstorm "Add dark mode brainstorm" 0 "trailing 'brainstorm' does NOT engage (#914)"
  check_brainstorm "output X.md brainstorm rounds 3 Add dark mode" 0 "mid 'brainstorm' does NOT engage (#914)"
  check_brainstorm "Build a brainstorm app for kids" 0 "'brainstorm' inside description does NOT engage (#914)"
  check_brainstorm "Add a brainstorm feature to the editor" 0 "'brainstorm' inside description does NOT engage (#914)"
  check_brainstorm "Document our brainstorm process" 0 "'brainstorm' inside description does NOT engage (#914)"
  check_brainstorm "auto brainstorm Add dark mode" 0 "'brainstorm' after 'auto' does NOT engage (not first token, #914)"
  # Negatives — substring/inflection forms must NOT trip the flag (flag stays 0).
  check_brainstorm "brainstorming the design" 0 "'brainstorming' (no boundary) rejected"
  check_brainstorm "brainstormed yesterday" 0 "'brainstormed' (no boundary) rejected"
  check_brainstorm "brainstorms" 0 "'brainstorms' (no boundary) rejected"
fi

# ── Surface 4: brainstorm-mode wiring parity greps (externally-sourced) ──
# These fences are NOT self-contained (they live in prose / depend on the
# Read-tool dispatch and $TRACKING_ID), so assert by fingerprint grep that
# the wiring stays present, mirroring the Surface-1 `grep -qF` parity style.

# Conditional-load parity: references/brainstorm.md is gated on BRAINSTORM_FLAG,
# i.e. the Read is NOT unconditional. The "## Brainstorm mode" section opens
# with the `If BRAINSTORM_FLAG=1, **Read [references/brainstorm.md]...` gate.
if grep -qF 'If `BRAINSTORM_FLAG=1`, **Read [references/brainstorm.md](references/brainstorm.md)**' "$SKILL"; then
  pass "conditional-load: brainstorm.md Read is gated on BRAINSTORM_FLAG=1"
else
  fail "conditional-load: brainstorm.md gate drifted" "missing BRAINSTORM_FLAG=1 Read gate"
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
# BRAINSTORM_FLAG=1 (skipped because the user already steered in dialogue).
if grep -qF 'Skip this steering checkpoint when `BRAINSTORM_FLAG=1`' "$SKILL"; then
  pass "checkpoint-skip: post-research checkpoint gated on BRAINSTORM_FLAG=1"
else
  fail "checkpoint-skip: checkpoint gate drifted" "missing 'Skip this steering checkpoint when BRAINSTORM_FLAG=1'"
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

# ── Surface 6: QUIZ_FLAG leading-cluster scan + brainstorm/quiz mutual
#    exclusion (extract-and-run) ───────────────────────────────────────
# #936: the leading-cluster tokenizer must recognize `brainstorm` (walk
# past it) so a leading `brainstorm` does not break the scan before `quiz`
# is reached. Combined with the first-token-anchored BRAINSTORM_FLAG fence,
# this makes `brainstorm quiz X` set BOTH flags, which the mutual-exclusion
# guard converts into a fail-loud exit 2 instead of a silent mode drop.
# The guard must NOT regress #914 (brainstorm is still first-token-only for
# BRAINSTORM_FLAG; the tokenizer arm only lets the quiz scan walk past it).

# Extract the QUIZ_FLAG leading-scan fence (QUIZ_FLAG=0 … done — a for-loop,
# not an `if … fi`, so stop at the first standalone `done`).
QUIZ_BLOCK=$(awk '
  /^QUIZ_FLAG=0$/{capture=1}
  capture {print}
  capture && /^done$/{exit}
' "$SKILL")

# Extract the mutual-exclusion guard fence (the `if [ "${BRAINSTORM_FLAG...`
# block that emits the error and `exit 2`). Stop at its closing `fi`.
MUTEX_BLOCK=$(awk '
  /^if \[ "\$\{BRAINSTORM_FLAG/{capture=1}
  capture {print}
  capture && /^fi$/{exit}
' "$SKILL")

if [ -z "$QUIZ_BLOCK" ]; then
  fail "quiz-flag: could not extract QUIZ_FLAG fence" "awk extract empty"
elif [ -z "$MUTEX_BLOCK" ]; then
  fail "mutex: could not extract brainstorm/quiz mutual-exclusion fence" "awk extract empty"
else
  pass "quiz-flag: QUIZ_FLAG leading-scan fence extracted from SKILL.md"
  pass "mutex: brainstorm/quiz mutual-exclusion fence extracted from SKILL.md"

  # Tokenizer-arm parity: the brainstorm) ;; arm must be present (#936).
  if grep -qF 'brainstorm) ;;' "$SKILL"; then
    pass "mutex: leading-cluster tokenizer has 'brainstorm) ;;' arm (#936)"
  else
    fail "mutex: 'brainstorm) ;;' tokenizer arm missing" "leading scan would break at brainstorm"
  fi

  # Run BOTH the BRAINSTORM_FLAG and QUIZ_FLAG fences against $ARGUMENTS,
  # then run the mutual-exclusion guard in a subshell so its `exit 2` is
  # captured as a subshell exit code rather than killing the test. Echo the
  # resolved flags so we can also assert the flag values directly.
  # Run the real fences in a subshell. The flag values are written to a
  # dedicated file (NOT stderr) so the guard's own stderr error message does
  # not contaminate the capture; the guard's `exit 2` becomes the subshell rc.
  flags_for() { # $1=ARGUMENTS $2=flagfile  -> exit code = guard rc
    (
      ARGUMENTS="$1"
      BRAINSTORM_FLAG=
      QUIZ_FLAG=
      eval "$BRAINSTORM_BLOCK"
      eval "$QUIZ_BLOCK"
      printf 'B=%s Q=%s\n' "$BRAINSTORM_FLAG" "$QUIZ_FLAG" > "$2"
      eval "$MUTEX_BLOCK"
    ) 2>/dev/null
  }
  check_combo() { # $1=ARGUMENTS $2=expected_B $3=expected_Q $4=expected_rc $5=label
    local rc fl ff="/tmp/.draftplan-mutex-flags-$$"
    flags_for "$1" "$ff"; rc=$?
    fl=$(cat "$ff" 2>/dev/null); rm -f "$ff"
    if [ "$fl" = "B=$2 Q=$3" ] && [ "$rc" = "$4" ]; then
      pass "mutex: $5 -> $fl, exit $rc"
    else
      fail "mutex: $5" "expected B=$2 Q=$3 exit $4, got '$fl' exit $rc"
    fi
  }

  # The core #936 assertion: requesting BOTH modes (brainstorm first, quiz in
  # the leading cluster) sets both flags and fails loud (exit 2) — NOT a
  # silent drop of whichever mode wasn't first.
  check_combo "brainstorm quiz Add dark mode" 1 1 2 "'brainstorm quiz X' -> both flags, mutual-exclusion error"
  # Reverse order: per #914, a non-first 'brainstorm' is DESCRIPTION text, not
  # the flag. So this is unambiguously single-mode quiz (no silent drop, no
  # error). Order is no longer SILENTLY ambiguous: 'brainstorm quiz' errors
  # loud; 'quiz brainstorm' is the defined #914 single-mode case.
  check_combo "quiz brainstorm Add dark mode" 0 1 0 "'quiz brainstorm X' -> quiz-only (brainstorm is description per #914), no error"
  # Single-mode cases must NOT error.
  check_combo "brainstorm Add dark mode" 1 0 0 "'brainstorm X' -> brainstorm-only, no error"
  check_combo "quiz Add dark mode" 0 1 0 "'quiz X' -> quiz-only, no error"
  # #914 non-regression: 'auto brainstorm' must NOT set BRAINSTORM_FLAG, and
  # the brainstorm) ;; tokenizer arm must not turn it into a both-modes case.
  check_combo "auto brainstorm Add dark mode" 0 0 0 "'auto brainstorm X' -> neither flag (#914 preserved), no error"
  # #914 non-regression: brainstorm embedded in description stays inert.
  check_combo "Build a brainstorm app for kids" 0 0 0 "'Build a brainstorm app' -> neither flag (#914 preserved), no error"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] && exit 0 || exit 1
