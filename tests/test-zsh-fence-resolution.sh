#!/bin/bash
# Tests for SHELL-PORTABLE self-location in the sourceable config/path
# helpers (issue #1149).
#
# Claude Code's Bash tool executes skill fences under the user's SNAPSHOT
# shell — which is zsh on default macOS/dev setups, not bash. zsh leaves
# ${BASH_SOURCE[0]} unset, so the helpers' self-location must fall back to
# $0 (set to the sourced file's path by zsh's default FUNCTION_ARGZERO):
#   ${BASH_SOURCE[0]:-$0}
#
# The live failure this guards (issue #1149, sandbox-proven): on a
# mirror-less marketplace-install consumer, a /zs:do fence sourced
# zskills-resolve-config.sh under zsh; ${BASH_SOURCE[0]} expanded EMPTY, the
# sibling-source degenerated to `. ./zskills-paths.sh` (cwd-relative, absent
# in the consumer repo), $ZSKILLS_SKILLS_ROOT stayed empty, and the Layer-3
# validator invocation became `bash /update-zskills/scripts/
# verify-response-validate.sh` → 127 → the model self-waived the gate.
# zskills-paths.sh sourced DIRECTLY under zsh was worse — silently wrong
# (<cwd>/../.. as the skills root), and the ZSKILLS_VERSION init-done
# fallback was silently skipped ([ -f "/init-state.sh" ] never true).
#
# These cases exercise RESOLUTION under a real zsh (not fence text — the
# conformance pins already cover text). zsh-less environments skip the zsh
# arms with a notice; the bash-parity case always runs.
#
# Cases:
#   1. (bash parity) resolve-config sourced under bash from a mirror-less
#      consumer cwd → $ZSKILLS_SKILLS_ROOT = <plugin>/skills (baseline).
#   2. (zsh, live-repro shape) resolve-config sourced under zsh, cwd =
#      mirror-less consumer git repo, CLAUDE_PROJECT_DIR unset (git-common-dir
#      fallback, as live) → $ZSKILLS_SKILLS_ROOT = <plugin>/skills, NO
#      "no such file" on stderr, and the Layer-3 validator file EXISTS at
#      "$ZSKILLS_SKILLS_ROOT/update-zskills/scripts/verify-response-validate.sh".
#   3. (zsh) zskills-paths.sh sourced DIRECTLY under zsh → skills root is the
#      install location, NOT <cwd>/../.. (the silent wrong-root regression).
#   4. (zsh, end-to-end) a meaningful verifier response piped through the
#      validator at the zsh-resolved root exits 0 (the gate actually RUNS).
#   5. (zsh) ZSKILLS_VERSION init-done fallback: config-less consumer with
#      .zskills/init-done `version:` line → resolved under zsh (the
#      "$_ZSK_SELF_DIR/init-state.sh" site).
#   6. (zsh, #1154) resolve-config CASCADE extraction: the key-extraction
#      regexes COMPILE under zsh (0 "failed to compile regex" on stderr) AND
#      a NON-DEFAULT configured value (timezone/test cmds/max-worktrees) is
#      actually extracted, not silently defaulted. Guards the `\{`→`[{]` ERE
#      fix + the LOCAL_OPTIONS KSH_ARRAYS/BASH_REMATCH zsh indexing fix.
#   7. (zsh, #1154) zskills-paths.sh extraction: same compile + non-default
#      extraction assertion for the output.*_dir cascade keys.
#
# Run from repo root: bash tests/test-zsh-fence-resolution.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_SCRIPTS="$REPO_ROOT/skills/update-zskills/scripts"

TEST_OUT="/tmp/zskills-tests/$(basename "$REPO_ROOT")"
mkdir -p "$TEST_OUT"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

summary_and_exit() {
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
}

if [ ! -f "$SRC_SCRIPTS/zskills-resolve-config.sh" ] || [ ! -f "$SRC_SCRIPTS/zskills-paths.sh" ]; then
  fail "helpers exist at expected paths" "$SRC_SCRIPTS/{zskills-resolve-config.sh,zskills-paths.sh} missing"
  summary_and_exit
fi

# Sandbox: a synthetic mirror-less plugin-lane install. The plugin tree
# carries the FULL scripts/ dir (resolve-config sources its siblings
# zskills-paths.sh + init-state.sh); the consumer is a bare git repo with
# NO .claude/skills mirror. HOME is sandboxed (resolve-config reads the
# user-tier config from $HOME/.claude/zskills-config.json).
SANDBOX=$(mktemp -d /tmp/zskills-zsh-fence-XXXXXX)
PLUGIN="$SANDBOX/plugin"
CONSUMER="$SANDBOX/consumer"
EMPTY_HOME="$SANDBOX/home"
mkdir -p "$PLUGIN/skills/update-zskills" "$CONSUMER" "$EMPTY_HOME"
cp -a "$SRC_SCRIPTS" "$PLUGIN/skills/update-zskills/"
git -C "$CONSUMER" init -q

RC_HELPER="$PLUGIN/skills/update-zskills/scripts/zskills-resolve-config.sh"
PATHS_HELPER="$PLUGIN/skills/update-zskills/scripts/zskills-paths.sh"

# A verifier response that clears the validator's 200-byte minimum and
# matches no stalled-string pattern.
GOOD_RESPONSE="Findings: docs/HELLO.md exists, contains exactly one sentence, and accurately describes the project. No unrelated files were touched and formatting is correct. All assertions verified by reading the file and checking git status. PASS"

# The fence body each case runs (mirrors the live /zs:do Layer-3 fence
# shape: cd into the consumer, export the plugin root, source the prelude).
FENCE_PRINT_ROOT='cd "$CONSUMER_DIR"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR"
. "$PLUGIN_DIR/skills/update-zskills/scripts/zskills-resolve-config.sh"
printf "ROOT=%s\n" "$ZSKILLS_SKILLS_ROOT"
if [ -f "$ZSKILLS_SKILLS_ROOT/update-zskills/scripts/verify-response-validate.sh" ]; then
  printf "VALIDATOR=present\n"
else
  printf "VALIDATOR=absent\n"
fi'

# --- Case 1: bash parity (baseline — must hold before and after #1149) ------
echo "=== Case 1: bash — resolve-config from mirror-less consumer cwd → skills root = <plugin>/skills ==="
OUT1=$(
  env -i PATH="$PATH" HOME="$EMPTY_HOME" \
    CONSUMER_DIR="$CONSUMER" PLUGIN_DIR="$PLUGIN" \
    bash -c "$FENCE_PRINT_ROOT" 2>"$TEST_OUT/.zsh-fence-c1-err.txt"
)
if printf '%s\n' "$OUT1" | grep -qx "ROOT=$PLUGIN/skills" \
  && printf '%s\n' "$OUT1" | grep -qx "VALIDATOR=present"; then
  pass "Case 1: bash baseline — skills root + validator resolve"
else
  fail "Case 1: bash baseline" "out='$OUT1' err='$(cat "$TEST_OUT/.zsh-fence-c1-err.txt")'"
fi

# --- zsh gate -----------------------------------------------------------------
if ! command -v zsh >/dev/null 2>&1; then
  echo ""
  echo "  SKIP: zsh not installed — zsh resolution arms (Cases 2-5) skipped."
  echo "  The #1149 regression surface is zsh-snapshot-shell consumers; install"
  echo "  zsh to exercise it (GitHub ubuntu runners and the devcontainer have it)."
  rm -rf "$SANDBOX"
  summary_and_exit
fi

# --- Case 2: zsh, live-repro shape -------------------------------------------
# CLAUDE_PROJECT_DIR deliberately UNSET (the live session relied on the
# git-common-dir fallback — keep that fidelity); cwd = consumer repo.
echo ""
echo "=== Case 2: zsh — resolve-config from mirror-less consumer cwd (live #1149 shape) ==="
OUT2=$(
  env -i PATH="$PATH" HOME="$EMPTY_HOME" \
    CONSUMER_DIR="$CONSUMER" PLUGIN_DIR="$PLUGIN" \
    zsh -c "$FENCE_PRINT_ROOT" 2>"$TEST_OUT/.zsh-fence-c2-err.txt"
)
ERR2=$(cat "$TEST_OUT/.zsh-fence-c2-err.txt")
if printf '%s\n' "$OUT2" | grep -qx "ROOT=$PLUGIN/skills" \
  && printf '%s\n' "$OUT2" | grep -qx "VALIDATOR=present" \
  && ! printf '%s\n' "$ERR2" | grep -qi "no such file"; then
  pass "Case 2: zsh live-repro shape — skills root correct, validator present, no source error"
else
  fail "Case 2: zsh live-repro shape" "out='$OUT2' err='$ERR2'"
fi

# --- Case 3: zsh, zskills-paths.sh sourced directly ---------------------------
# Pre-fix this was the SILENT failure: ZSKILLS_SKILLS_ROOT=<cwd>/../.. .
echo ""
echo "=== Case 3: zsh — zskills-paths.sh sourced directly → install location, never <cwd>/../.. ==="
OUT3=$(
  env -i PATH="$PATH" HOME="$EMPTY_HOME" CLAUDE_PROJECT_DIR="$CONSUMER" \
    PATHS_HELPER="$PATHS_HELPER" \
    zsh -c 'cd "$CLAUDE_PROJECT_DIR" && . "$PATHS_HELPER" && printf "%s\n" "$ZSKILLS_SKILLS_ROOT"' \
    2>"$TEST_OUT/.zsh-fence-c3-err.txt"
)
WRONG_ROOT="$(cd "$CONSUMER/../.." && pwd)"
if [ "$OUT3" = "$PLUGIN/skills" ]; then
  pass "Case 3: zsh direct-source — self-located skills root (not the cwd-derived '$WRONG_ROOT')"
else
  fail "Case 3: zsh direct-source" "got '$OUT3', expected '$PLUGIN/skills' (cwd-derived wrong-root would be '$WRONG_ROOT')"
fi

# --- Case 4: zsh, end-to-end Layer-3 validator run -----------------------------
# The gate must actually RUN (exit 0 on a meaningful response) — pre-fix it
# exited 127 (script path /update-zskills/... from the empty root).
echo ""
echo "=== Case 4: zsh — Layer-3 validator runs at the zsh-resolved root (exit 0, not 127) ==="
env -i PATH="$PATH" HOME="$EMPTY_HOME" \
  CONSUMER_DIR="$CONSUMER" PLUGIN_DIR="$PLUGIN" GOOD_RESPONSE="$GOOD_RESPONSE" \
  zsh -c 'cd "$CONSUMER_DIR"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR"
. "$PLUGIN_DIR/skills/update-zskills/scripts/zskills-resolve-config.sh"
printf "%s" "$GOOD_RESPONSE" | bash "$ZSKILLS_SKILLS_ROOT/update-zskills/scripts/verify-response-validate.sh"' \
  >"$TEST_OUT/.zsh-fence-c4-out.txt" 2>&1
RC4=$?
if [ "$RC4" -eq 0 ]; then
  pass "Case 4: zsh end-to-end — validator ran and passed (exit 0)"
else
  fail "Case 4: zsh end-to-end validator" "exit=$RC4 (127 = the #1149 empty-root regression) out='$(cat "$TEST_OUT/.zsh-fence-c4-out.txt")'"
fi

# --- Case 5: zsh, ZSKILLS_VERSION init-done fallback ---------------------------
# Pre-fix the "${BASH_SOURCE[0]%/*}/init-state.sh" presence test was
# [ -f "/init-state.sh" ] under zsh → fallback silently skipped.
echo ""
echo "=== Case 5: zsh — ZSKILLS_VERSION resolves from .zskills/init-done (init-state.sh sibling-source) ==="
mkdir -p "$CONSUMER/.zskills"
printf 'version: 2026.06.0-test\ndate: 2026-06-11\n' > "$CONSUMER/.zskills/init-done"
OUT5=$(
  env -i PATH="$PATH" HOME="$EMPTY_HOME" \
    CONSUMER_DIR="$CONSUMER" PLUGIN_DIR="$PLUGIN" \
    zsh -c 'cd "$CONSUMER_DIR"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR"
. "$PLUGIN_DIR/skills/update-zskills/scripts/zskills-resolve-config.sh"
printf "%s\n" "$ZSKILLS_VERSION"' 2>"$TEST_OUT/.zsh-fence-c5-err.txt"
)
if [ "$OUT5" = "2026.06.0-test" ]; then
  pass "Case 5: zsh init-done fallback — ZSKILLS_VERSION='$OUT5'"
else
  fail "Case 5: zsh init-done fallback" "got '$OUT5', expected '2026.06.0-test' err='$(cat "$TEST_OUT/.zsh-fence-c5-err.txt")'"
fi
rm -f "$CONSUMER/.zskills/init-done"

# --- Case 6: zsh — cascade key extraction compiles AND matches (#1154) ---------
# Pre-fix: the cascade-extract regexes used `\{[^}]*` / `[^}]*\}` (a literal
# `\{`/`\}` that bash's ERE engine tolerates but zsh's REJECTS), so sourcing
# under zsh emitted `failed to compile regex: Invalid content of \{\}` and —
# compounded by zsh's bash-incompatible $BASH_REMATCH indexing without
# KSH_ARRAYS+BASH_REMATCH — every configured cascade value silently extracted
# EMPTY and fell to the built-in defaults. This case configures NON-DEFAULT
# values and asserts (a) ZERO "failed to compile regex" lines on stderr, and
# (b) the configured values come back (NOT the built-in defaults).
echo ""
echo "=== Case 6: zsh — resolve-config cascade extraction compiles + extracts configured values (#1154) ==="
mkdir -p "$CONSUMER/.claude"
cat > "$CONSUMER/.claude/zskills-config.json" <<'CFG6'
{
  "timezone": "America/Chicago",
  "testing": { "unit_cmd": "make unit", "full_cmd": "make full" },
  "execution": { "max_concurrent_worktrees": 7 }
}
CFG6
OUT6=$(
  env -i PATH="$PATH" HOME="$EMPTY_HOME" \
    CONSUMER_DIR="$CONSUMER" PLUGIN_DIR="$PLUGIN" \
    zsh -c 'cd "$CONSUMER_DIR"
export CLAUDE_PROJECT_DIR="$CONSUMER_DIR"
. "$PLUGIN_DIR/skills/update-zskills/scripts/zskills-resolve-config.sh"
printf "TZ=%s\n" "$TIMEZONE"
printf "UNIT=%s\n" "$UNIT_TEST_CMD"
printf "FULL=%s\n" "$FULL_TEST_CMD"
printf "MCW=%s\n" "$ZSKILLS_MAX_CONCURRENT_WORKTREES"' 2>"$TEST_OUT/.zsh-fence-c6-err.txt"
)
ERR6=$(cat "$TEST_OUT/.zsh-fence-c6-err.txt")
REGEX_ERRS6=$(printf '%s\n' "$ERR6" | grep -c "failed to compile regex")
if [ "$REGEX_ERRS6" -eq 0 ] \
  && printf '%s\n' "$OUT6" | grep -qx "TZ=America/Chicago" \
  && printf '%s\n' "$OUT6" | grep -qx "UNIT=make unit" \
  && printf '%s\n' "$OUT6" | grep -qx "FULL=make full" \
  && printf '%s\n' "$OUT6" | grep -qx "MCW=7"; then
  pass "Case 6: zsh cascade extraction — 0 regex-compile errors, configured (non-default) values extracted"
else
  fail "Case 6: zsh cascade extraction" "regex-compile-errs=$REGEX_ERRS6 (want 0; TZ should be America/Chicago not the UTC default) out='$OUT6' err='$ERR6'"
fi
rm -f "$CONSUMER/.claude/zskills-config.json"

# --- Case 7: zsh — paths key extraction compiles AND matches (#1154) -----------
# Same `\{`/`\}` regex-compile failure + $BASH_REMATCH indexing trap in
# zskills-paths.sh's _zsk_paths_extract_keys. Configure NON-DEFAULT output
# dirs and assert 0 compile errors + the configured dirs resolve (not the
# built-in docs/ defaults).
echo ""
echo "=== Case 7: zsh — zskills-paths.sh extraction compiles + extracts configured output dirs (#1154) ==="
mkdir -p "$CONSUMER/.claude"
cat > "$CONSUMER/.claude/zskills-config.json" <<'CFG7'
{
  "output": { "plans_dir": "myplans", "issues_dir": "myissues", "reports_dir": "myreports" }
}
CFG7
OUT7=$(
  env -i PATH="$PATH" HOME="$EMPTY_HOME" CLAUDE_PROJECT_DIR="$CONSUMER" \
    PATHS_HELPER="$PATHS_HELPER" \
    zsh -c 'cd "$CLAUDE_PROJECT_DIR" && . "$PATHS_HELPER"
printf "PLANS=%s\n" "$ZSKILLS_PLANS_DIR"
printf "ISSUES=%s\n" "$ZSKILLS_ISSUES_DIR"
printf "REPORTS=%s\n" "$ZSKILLS_REPORTS_DIR"' 2>"$TEST_OUT/.zsh-fence-c7-err.txt"
)
ERR7=$(cat "$TEST_OUT/.zsh-fence-c7-err.txt")
REGEX_ERRS7=$(printf '%s\n' "$ERR7" | grep -c "failed to compile regex")
if [ "$REGEX_ERRS7" -eq 0 ] \
  && printf '%s\n' "$OUT7" | grep -qx "PLANS=$CONSUMER/myplans" \
  && printf '%s\n' "$OUT7" | grep -qx "ISSUES=$CONSUMER/myissues" \
  && printf '%s\n' "$OUT7" | grep -qx "REPORTS=$CONSUMER/myreports"; then
  pass "Case 7: zsh paths extraction — 0 regex-compile errors, configured (non-default) output dirs extracted"
else
  fail "Case 7: zsh paths extraction" "regex-compile-errs=$REGEX_ERRS7 (want 0; dirs should be the configured myplans/myissues/myreports, not the docs/ defaults) out='$OUT7' err='$ERR7'"
fi
rm -f "$CONSUMER/.claude/zskills-config.json"

rm -rf "$SANDBOX"
summary_and_exit
