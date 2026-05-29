#!/usr/bin/env bash
# tests/test-plugin-hook-skip-on-double-register.sh
#
# W5.7 (D16(a)) — acceptance test for the conditional-skip shim
# hooks/_lib/plugin-hook-skip-if-mirrored.sh.
#
# The shim is sourced as the FIRST executable line of every plugin-registered
# hook. It prevents hook double-fire when BOTH install lanes are active: the
# plugin lane (hooks.json) AND the /update-zskills lane (settings.json). When
# a settings.json hook entry has the SAME BASENAME as the plugin hook, the
# plugin copy defers (exits 0) so only the settings.json copy runs.
#
# Three D16(a) scenarios (read the shim to assert ACTUAL behaviour):
#   (i)   basename match + EQUAL version            → silent skip (exit 0,
#                                                       no stderr, real work
#                                                       NOT done).
#   (ii)  basename match + plugin STRICTLY NEWER    → WARN-then-skip (exit 0,
#                                                       stderr WARN + a
#                                                       .zskills/hook-skew-
#                                                       warned-<basename>
#                                                       marker, real work NOT
#                                                       done).
#   (iii) NO basename match                         → calling hook CONTINUES
#                                                       (real work IS done).
#
# Mechanism: each scenario builds a fake plugin hook whose first executable
# line sources the shim and whose remaining body marks "REAL WORK" by
# touching a sentinel file. We run the hook with CLAUDE_PROJECT_DIR pointed
# at a fixture that pre-populates .claude/settings.json and (for the
# version-skew check) a consumer-side hook copy carrying a
# `# zskills-hook-version:` stamp. We assert exit code, stderr WARN
# presence/absence, marker presence, and whether REAL WORK ran.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

SHIM="$REPO_ROOT/hooks/_lib/plugin-hook-skip-if-mirrored.sh"
[ -f "$SHIM" ] || { echo "ERROR: shim not found: $SHIM" >&2; exit 1; }

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "=== plugin hook conditional-skip shim (D16(a)) ==="

# Build a fake plugin hook named <basename> that sources the shim as its first
# executable line, then (if it continues) touches $WORKMARK to prove REAL
# WORK ran. $1 = plugin hook path; $2 = plugin hook version stamp (or "" for
# none).
make_plugin_hook() {
  local path="$1" ver="$2"
  mkdir -p "$(dirname "$path")"
  {
    echo '#!/usr/bin/env bash'
    [ -n "$ver" ] && echo "# zskills-hook-version: $ver"
    # Source the shim FIRST. If it returns (no skip), the work line runs.
    echo "source \"$SHIM\""
    echo 'touch "$WORKMARK"'
  } > "$path"
  chmod +x "$path"
}

# Write a settings.json with one PreToolUse hook entry whose command path-token
# has basename $1 under .claude/hooks/. $2 = project dir (for the literal
# $CLAUDE_PROJECT_DIR form).
write_settings_with_hook() {
  local basename="$1" proj="$2"
  mkdir -p "$proj/.claude"
  cat > "$proj/.claude/settings.json" <<JSON
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "bash \"\$CLAUDE_PROJECT_DIR/.claude/hooks/$basename\"", "timeout": 5 }
        ]
      }
    ]
  }
}
JSON
}

# Write a consumer-side hook copy (the settings.json-registered one) with a
# version stamp. $1 = path; $2 = version.
write_consumer_hook() {
  local path="$1" ver="$2"
  mkdir -p "$(dirname "$path")"
  {
    echo '#!/usr/bin/env bash'
    echo "# zskills-hook-version: $ver"
    echo 'echo consumer'
  } > "$path"
  chmod +x "$path"
}

run_hook() {
  # $1 = plugin hook path; $2 = proj dir; $3 = workmark path; $4 = stderr file
  env CLAUDE_PROJECT_DIR="$2" WORKMARK="$3" bash "$1" 2>"$4"
}

# ── Scenario (i): basename match, EQUAL version → silent skip ─────────────
P1="$TMP/equal"
HOOKNAME="block-stale-skill-version.sh"
write_settings_with_hook "$HOOKNAME" "$P1"
write_consumer_hook "$P1/.claude/hooks/$HOOKNAME" "2026.05.0"
PLUGIN_HOOK1="$TMP/plugin1/$HOOKNAME"
make_plugin_hook "$PLUGIN_HOOK1" "2026.05.0"
WM1="$P1/.workmark"; ERR1="$P1/.err"
run_hook "$PLUGIN_HOOK1" "$P1" "$WM1" "$ERR1"; rc1=$?
[ "$rc1" -eq 0 ] && pass "(i) equal version: shim exits 0" || fail "(i) expected exit 0, got $rc1"
[ ! -e "$WM1" ] && pass "(i) equal version: REAL WORK skipped (no workmark)" || fail "(i) REAL WORK ran (should have skipped)"
[ ! -s "$ERR1" ] && pass "(i) equal version: SILENT (no stderr WARN)" || { fail "(i) unexpected stderr"; sed 's/^/      /' "$ERR1"; }
[ ! -e "$P1/.zskills/hook-skew-warned-$HOOKNAME" ] && pass "(i) equal version: no skew marker" || fail "(i) skew marker created (should not be)"

# ── Scenario (ii): basename match, plugin STRICTLY NEWER → WARN+skip ──────
P2="$TMP/newer"
write_settings_with_hook "$HOOKNAME" "$P2"
write_consumer_hook "$P2/.claude/hooks/$HOOKNAME" "2026.05.0"   # consumer OLDER
PLUGIN_HOOK2="$TMP/plugin2/$HOOKNAME"
make_plugin_hook "$PLUGIN_HOOK2" "2026.06.0"                    # plugin NEWER
WM2="$P2/.workmark"; ERR2="$P2/.err"
run_hook "$PLUGIN_HOOK2" "$P2" "$WM2" "$ERR2"; rc2=$?
[ "$rc2" -eq 0 ] && pass "(ii) plugin newer: shim exits 0" || fail "(ii) expected exit 0, got $rc2"
[ ! -e "$WM2" ] && pass "(ii) plugin newer: REAL WORK skipped (no workmark)" || fail "(ii) REAL WORK ran (should have skipped)"
if grep -q "settings.json hook $HOOKNAME is version 2026.05.0 but plugin ships 2026.06.0" "$ERR2" \
   && grep -q 'deferring to settings.json copy' "$ERR2"; then
  pass "(ii) plugin newer: documented WARN emitted"
else
  fail "(ii) WARN text missing/incorrect"; sed 's/^/      /' "$ERR2"
fi
[ -f "$P2/.zskills/hook-skew-warned-$HOOKNAME" ] && pass "(ii) plugin newer: skew marker created" || fail "(ii) skew marker NOT created"
# Once-per-session gating: a second run does NOT re-emit the WARN.
ERR2b="$P2/.err2"
run_hook "$PLUGIN_HOOK2" "$P2" "$WM2" "$ERR2b"
[ ! -s "$ERR2b" ] && pass "(ii) plugin newer: WARN gated once-per-session (marker suppresses)" || { fail "(ii) WARN re-emitted despite marker"; sed 's/^/      /' "$ERR2b"; }

# ── Scenario (iii): NO basename match → calling hook continues ────────────
P3="$TMP/nomatch"
# settings.json registers a DIFFERENT hook basename.
write_settings_with_hook "some-other-hook.sh" "$P3"
PLUGIN_HOOK3="$TMP/plugin3/$HOOKNAME"
make_plugin_hook "$PLUGIN_HOOK3" "2026.05.0"
WM3="$P3/.workmark"; ERR3="$P3/.err"
run_hook "$PLUGIN_HOOK3" "$P3" "$WM3" "$ERR3"; rc3=$?
[ "$rc3" -eq 0 ] && pass "(iii) no match: hook completes normally (exit 0)" || fail "(iii) expected exit 0, got $rc3"
[ -e "$WM3" ] && pass "(iii) no match: REAL WORK ran (calling hook continued)" || fail "(iii) REAL WORK did NOT run (shim should have returned)"

# ── Scenario (iv): basename match but consumer copy MISSING version stamp →
#    silent defer (Step 6: either stamp absent → settings.json wins). ───────
P4="$TMP/nostamp"
write_settings_with_hook "$HOOKNAME" "$P4"
mkdir -p "$P4/.claude/hooks"
printf '%s\n' '#!/usr/bin/env bash' 'echo no-stamp' > "$P4/.claude/hooks/$HOOKNAME"
PLUGIN_HOOK4="$TMP/plugin4/$HOOKNAME"
make_plugin_hook "$PLUGIN_HOOK4" "2026.06.0"
WM4="$P4/.workmark"; ERR4="$P4/.err"
run_hook "$PLUGIN_HOOK4" "$P4" "$WM4" "$ERR4"; rc4=$?
[ "$rc4" -eq 0 ] && pass "(iv) consumer stamp absent: shim exits 0 (defer)" || fail "(iv) expected exit 0, got $rc4"
[ ! -e "$WM4" ] && pass "(iv) consumer stamp absent: REAL WORK skipped" || fail "(iv) REAL WORK ran (should defer)"
[ ! -s "$ERR4" ] && pass "(iv) consumer stamp absent: silent (no WARN)" || { fail "(iv) unexpected stderr"; sed 's/^/      /' "$ERR4"; }

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
