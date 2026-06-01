#!/bin/bash
# tests/test-commit-parsing.sh — extract-and-run the REAL /commit arg-parser.
#
# SEAM_HARDENING_HIGH Phase 3. Supersedes the static-grep coverage that used
# to live in tests/test-commit.sh (Cases 1–3, the top-level arg-parser
# presence-greps): instead of grepping the SKILL.md source for the AUTO_FLAG
# default / `[aA][uU][tT][oO]` regex / strip-sed occurrences, this suite
# EXTRACTS the two real ```bash fences from skills/commit/SKILL.md via
# tests/lib/extract-fence.sh and RUNS them with synthesized `$ARGUMENTS` +
# config, then asserts the parser's BEHAVIOR. Mutating either production
# fence (e.g. deleting the AUTO_FLAG regex, the SCOPE_HINT strip, or the
# first-token-only `pr` guard) makes assertions here FAIL — a hollow-green
# guard the old presence-greps could not provide.
#
# The two extracted fences (both COLUMN-0 in commit/SKILL.md — see DRIFT note
# below; the plan said 3-space-indent → strip-indent=1, but the actual fences
# are at column 0 so strip-indent=0):
#   Fence 1 (between `**Parsing:**` and `**Config-driven default mode`):
#     FIRST_TOKEN, AUTO_FLAG default+regex, explicit-`pr` SCOPE_HINT branch.
#   Fence 2 (between `**Config-driven default mode` and `Disambiguation:`):
#     HAS_EXPLICIT_MODE detection + config.execution.landing default-mode case
#     (pr / direct / "" / cherry-pick→exit 1 / unknown→commit).
#
# Behavioral cases (migrated from test-commit.sh static greps + new):
#   1. `pr`                         → FIRST_TOKEN=pr (PR mode), AUTO_FLAG=0
#   2. `fix pr format`              → commit (mid-string `pr` MUST NOT trigger)
#   3. `pr auto` (config=pr)        → AUTO_FLAG=1 + `auto` stripped from SCOPE_HINT
#   4. `auto` (config=pr)           → PR mode via config + AUTO_FLAG=1, auto stripped
#   5. `push` (config=pr)           → explicit push wins (not coerced to pr)
#   6. config=cherry-pick           → exit 1 with the documented error text
#   7. missing config               → commit-only default
#   8. unknown config value         → commit-only default
#   9. config=direct                → commit-only default
#  10. `pr fix pr comments`         → PR mode, SCOPE_HINT="fix pr comments"
#  11. `auto` w/ config=direct      → AUTO_FLAG=1 set but mode stays commit
#                                      (AUTO_FLAG outside PR mode is a no-op)

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/skills/commit/SKILL.md"

# shellcheck source=tests/lib/extract-fence.sh
. "$SCRIPT_DIR/lib/extract-fence.sh"

PASS=0
FAIL=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

if [ ! -f "$SKILL" ]; then
  echo "FAIL: commit SKILL.md not found at $SKILL" >&2
  exit 1
fi

echo "=== /commit arg-parser — extract-and-run (Phase 3) ==="

# ── Migrated from test-commit.sh Case 1 (frontmatter contract) ──────────
# argument-hint advertises the positional [auto] token (issue #236). Kept as
# a presence-grep because it asserts a frontmatter UX contract, not parser
# behavior — but the behavioral AUTO_FLAG cases below are the real guard.
if grep -qE '^argument-hint: ".*\[auto\].*"' "$SKILL"; then
  pass "0  argument-hint advertises positional [auto] (issue #236, migrated)"
else
  fail "0  argument-hint [auto]" "missing — issue #236"
fi

TMP=$(mktemp -d "/tmp/commit-parsing-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

# ── Extract the two production fences ───────────────────────────────────
FENCE1="$TMP/fence1.sh"   # FIRST_TOKEN / AUTO_FLAG / explicit-pr SCOPE_HINT
FENCE2="$TMP/fence2.sh"   # config-default-mode block

# strip-indent=0: the fences are COLUMN-0 in commit/SKILL.md (drift below).
if ! extract_fence_between "$SKILL" \
      '[*][*]Parsing:[*][*]' \
      '[*][*]Config-driven default mode' 1 0 > "$FENCE1"; then
  echo "FAIL: could not extract arg-parser fence 1 from $SKILL" >&2
  exit 1
fi
if ! extract_fence_between "$SKILL" \
      '[*][*]Config-driven default mode' \
      '^Disambiguation:' 1 0 > "$FENCE2"; then
  echo "FAIL: could not extract config-default fence 2 from $SKILL" >&2
  exit 1
fi

# Sanity: extracted fences carry their production landmarks (so a future
# re-anchoring that grabs the wrong fence fails loud here, not silently).
if grep -qF 'AUTO_FLAG=0' "$FENCE1" \
   && grep -qF 'FIRST_TOKEN=$(echo "$ARGUMENTS"' "$FENCE1" \
   && grep -qF '[aA][uU][tT][oO]' "$FENCE1"; then
  pass "[extract] fence 1 carries FIRST_TOKEN / AUTO_FLAG / auto-regex landmarks"
else
  fail "[extract] fence 1 landmarks" "missing one of FIRST_TOKEN/AUTO_FLAG/auto-regex"
fi
if grep -qF 'HAS_EXPLICIT_MODE=0' "$FENCE2" \
   && grep -qF 'landing' "$FENCE2" \
   && grep -qF 'cherry-pick)' "$FENCE2"; then
  pass "[extract] fence 2 carries HAS_EXPLICIT_MODE / landing / cherry-pick landmarks"
else
  fail "[extract] fence 2 landmarks" "missing one of HAS_EXPLICIT_MODE/landing/cherry-pick"
fi

# Assemble a runnable driver: the two fences concatenated, then an echo of
# the resulting parser state. The fences read CONFIG_FILE relative to CWD
# (".claude/zskills-config.json"), so the driver runs from a per-case sandbox.
DRIVER="$TMP/driver.sh"
{
  cat "$FENCE1"
  printf '\n'
  cat "$FENCE2"
  # Emit the resolved parser state for the test harness to read. Use the
  # `${VAR+set}` form so a var set to the EMPTY string (e.g. SCOPE_HINT="" —
  # the correct result of stripping a lone `auto` token) is distinguished
  # from a truly-unset var (printed as the literal <unset>).
  cat <<'TAIL'

printf 'FIRST_TOKEN=%s\n'   "${FIRST_TOKEN-<unset>}"
printf 'AUTO_FLAG=%s\n'     "${AUTO_FLAG-<unset>}"
printf 'SCOPE_HINT=%s\n'    "${SCOPE_HINT-<unset>}"
printf 'DEFAULT_MODE=%s\n'  "${DEFAULT_MODE-<unset>}"
TAIL
} > "$DRIVER"

# run_parser <ARGUMENTS> <config-landing-or-empty> <write-config 0|1>
#   Creates a sandbox dir with .claude/zskills-config.json (when requested),
#   runs the extracted driver under `set -u` with the given $ARGUMENTS, and
#   sets three GLOBALS the caller reads (NOT a command-substitution result —
#   so the driver's exit code propagates):
#     RUN_OUT  — the parser-state key=value blob (driver stdout)
#     RUN_ERR  — path to the captured driver stderr
#     RUN_RC   — the driver's exit code
run_parser() {
  local args="$1" landing="$2" write_cfg="$3"
  local box; box=$(mktemp -d "$TMP/box.XXXXXX")
  mkdir -p "$box/.claude"
  if [ "$write_cfg" = "1" ]; then
    cat > "$box/.claude/zskills-config.json" <<JSON
{
  "execution": {
    "landing": "$landing"
  }
}
JSON
  fi
  RUN_ERR="$box/.stderr"
  RUN_OUT=$(
    cd "$box" || exit 99
    set +e
    set -u
    export ARGUMENTS="$args"
    bash "$DRIVER" 2>"$RUN_ERR"
  )
  RUN_RC=$?
}

# val <key> <blob> — extract the value of key=… from a parser-state blob.
val() {
  printf '%s\n' "$2" | sed -n "s/^$1=//p" | head -1
}

# ── Case 1: `pr` → PR mode, AUTO_FLAG=0 ────────────────────────────────
run_parser "pr" "" 0; OUT=$RUN_OUT
if [ "$(val FIRST_TOKEN "$OUT")" = "pr" ] && [ "$(val AUTO_FLAG "$OUT")" = "0" ]; then
  pass "1  '/commit pr' → FIRST_TOKEN=pr (PR mode), AUTO_FLAG=0"
else
  fail "1  '/commit pr'" "FIRST_TOKEN='$(val FIRST_TOKEN "$OUT")' AUTO_FLAG='$(val AUTO_FLAG "$OUT")'"
fi

# ── Case 2: `fix pr format` → commit (mid-string `pr` MUST NOT trigger) ─
run_parser "fix pr format" "" 0; OUT=$RUN_OUT
if [ "$(val FIRST_TOKEN "$OUT")" = "fix" ] && [ "$(val DEFAULT_MODE "$OUT")" = "commit" ]; then
  pass "2  '/commit fix pr format' → commit (mid-string 'pr' does NOT trigger PR mode)"
else
  fail "2  mid-string pr" "FIRST_TOKEN='$(val FIRST_TOKEN "$OUT")' DEFAULT_MODE='$(val DEFAULT_MODE "$OUT")'"
fi

# ── Case 3: `pr auto` (config=pr) → AUTO_FLAG=1 + auto stripped ─────────
run_parser "pr auto" "pr" 1; OUT=$RUN_OUT
if [ "$(val FIRST_TOKEN "$OUT")" = "pr" ] \
   && [ "$(val AUTO_FLAG "$OUT")" = "1" ] \
   && [ "$(val SCOPE_HINT "$OUT")" = "" ]; then
  pass "3  '/commit pr auto' → AUTO_FLAG=1, 'auto' stripped from SCOPE_HINT (now empty)"
else
  fail "3  pr auto" "FIRST_TOKEN='$(val FIRST_TOKEN "$OUT")' AUTO_FLAG='$(val AUTO_FLAG "$OUT")' SCOPE_HINT='$(val SCOPE_HINT "$OUT")'"
fi

# ── Case 4: `auto` (config=pr) → PR via config + AUTO_FLAG=1, auto stripped
run_parser "auto" "pr" 1; OUT=$RUN_OUT
if [ "$(val FIRST_TOKEN "$OUT")" = "pr" ] \
   && [ "$(val AUTO_FLAG "$OUT")" = "1" ] \
   && [ "$(val DEFAULT_MODE "$OUT")" = "pr" ] \
   && [ "$(val SCOPE_HINT "$OUT")" = "" ]; then
  pass "4  '/commit auto' (config=pr) → config-default PR mode, AUTO_FLAG=1, auto stripped"
else
  fail "4  auto+config=pr" "FIRST_TOKEN='$(val FIRST_TOKEN "$OUT")' AUTO_FLAG='$(val AUTO_FLAG "$OUT")' DEFAULT_MODE='$(val DEFAULT_MODE "$OUT")' SCOPE_HINT='$(val SCOPE_HINT "$OUT")'"
fi

# ── Case 5: `push` (config=pr) → explicit push wins (NOT coerced to pr) ─
run_parser "push" "pr" 1; OUT=$RUN_OUT
# Explicit `push` sets HAS_EXPLICIT_MODE=1, so the config block is skipped
# and FIRST_TOKEN stays "push" (DEFAULT_MODE never assigned → <unset>).
if [ "$(val FIRST_TOKEN "$OUT")" = "push" ] && [ "$(val DEFAULT_MODE "$OUT")" = "<unset>" ]; then
  pass "5  '/commit push' (config=pr) → explicit push wins (FIRST_TOKEN=push, config skipped)"
else
  fail "5  push explicit-wins" "FIRST_TOKEN='$(val FIRST_TOKEN "$OUT")' DEFAULT_MODE='$(val DEFAULT_MODE "$OUT")'"
fi

# ── Case 6: config=cherry-pick → exit 1 with the documented error text ──
run_parser "" "cherry-pick" 1; OUT=$RUN_OUT
if [ "$RUN_RC" -eq 1 ] \
   && grep -qF 'execution.landing="cherry-pick" is not a valid default for /commit' "$RUN_ERR"; then
  pass "6  config=cherry-pick → exit 1 with documented error text"
else
  fail "6  cherry-pick misconfig" "rc='$RUN_RC' err='$(cat "$RUN_ERR")'"
fi

# ── Case 7: missing config → commit-only default ───────────────────────
run_parser "" "" 0; OUT=$RUN_OUT
if [ "$(val DEFAULT_MODE "$OUT")" = "commit" ] && [ "$RUN_RC" -eq 0 ]; then
  pass "7  no config file → commit-only default (DEFAULT_MODE=commit)"
else
  fail "7  missing config" "DEFAULT_MODE='$(val DEFAULT_MODE "$OUT")' rc='$RUN_RC'"
fi

# ── Case 8: unknown config value → commit-only default ─────────────────
run_parser "" "banana" 1; OUT=$RUN_OUT
if [ "$(val DEFAULT_MODE "$OUT")" = "commit" ] && [ "$RUN_RC" -eq 0 ]; then
  pass "8  config=banana (unknown) → commit-only default"
else
  fail "8  unknown config" "DEFAULT_MODE='$(val DEFAULT_MODE "$OUT")' rc='$RUN_RC'"
fi

# ── Case 9: config=direct → commit-only default ────────────────────────
run_parser "" "direct" 1; OUT=$RUN_OUT
if [ "$(val DEFAULT_MODE "$OUT")" = "commit" ] && [ "$RUN_RC" -eq 0 ]; then
  pass "9  config=direct → commit-only default"
else
  fail "9  config=direct" "DEFAULT_MODE='$(val DEFAULT_MODE "$OUT")' rc='$RUN_RC'"
fi

# ── Case 10: `pr fix pr comments` → PR mode, SCOPE_HINT preserved ───────
run_parser "pr fix pr comments" "" 0; OUT=$RUN_OUT
if [ "$(val FIRST_TOKEN "$OUT")" = "pr" ] \
   && [ "$(val SCOPE_HINT "$OUT")" = "fix pr comments" ]; then
  pass "10 '/commit pr fix pr comments' → PR mode, SCOPE_HINT='fix pr comments'"
else
  fail "10 pr scope-hint" "FIRST_TOKEN='$(val FIRST_TOKEN "$OUT")' SCOPE_HINT='$(val SCOPE_HINT "$OUT")'"
fi

# ── Case 11: `auto` w/ config=direct → AUTO_FLAG=1 but mode stays commit ─
# AUTO_FLAG is set unconditionally by fence 1; outside PR mode it is a no-op.
run_parser "auto" "direct" 1; OUT=$RUN_OUT
if [ "$(val AUTO_FLAG "$OUT")" = "1" ] && [ "$(val DEFAULT_MODE "$OUT")" = "commit" ]; then
  pass "11 '/commit auto' (config=direct) → AUTO_FLAG=1 set but mode stays commit (no-op)"
else
  fail "11 auto+config=direct" "AUTO_FLAG='$(val AUTO_FLAG "$OUT")' DEFAULT_MODE='$(val DEFAULT_MODE "$OUT")'"
fi

echo ""
echo "---"
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (of %d)\033[0m\n' "$PASS" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (of %d)\033[0m\n' "$PASS" "$FAIL" "$TOTAL"
  exit 1
fi
