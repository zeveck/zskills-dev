#!/usr/bin/env bash
# tests/test-session-rules-context.sh
#
# INSTALL_REDESIGN Phase 4 (branch R-b) — structural test for the
# SessionStart rules-delivery hook hooks/session-rules-context.sh.
#
# The hook renders the de-parameterized CLAUDE_TEMPLATE.md via the canonical
# renderer (no-config mode when no project config exists) and emits the
# result as `additionalContext` in the SessionStart JSON envelope
# (#1088/#1089: additionalContext = MODEL channel). It must write NOTHING
# into the project, and must emit EMPTY output when either guard fires:
#   guard 1 — legacy mirror present (detect-style), or
#   guard 2 — a project .claude/rules/zskills/managed.md already exists
#             (legacy render / R-c render / stale materialiser-era copy).
#
# All cases run against a synthetic plugin tree in $TMP (hermetic — no real
# $HOME, no `claude`).

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
[ -n "$PYTHON" ] || { echo "ERROR: install Python 3 (or set ZSKILLS_PYTHON)" >&2; exit 1; }

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "=== session-rules-context.sh — R-b SessionStart rules delivery ==="

# ── Synthetic plugin tree (only what the hook reaches) ─────────────────────
PLUG="$TMP/plugin"
mkdir -p "$PLUG/hooks/_lib" "$PLUG/scripts" "$PLUG/skills/update-zskills/scripts"
cp "$REPO_ROOT/hooks/session-rules-context.sh"        "$PLUG/hooks/"
cp "$REPO_ROOT/hooks/_lib/detect-install-state.sh"    "$PLUG/hooks/_lib/"
cp "$REPO_ROOT/scripts/render-managed-rules.py"       "$PLUG/scripts/"
cp "$REPO_ROOT/scripts/managed_rules_substitution.py" "$PLUG/scripts/"
cp "$REPO_ROOT/skills/update-zskills/scripts/zskills-defaults.json" \
   "$PLUG/skills/update-zskills/scripts/"
cp "$REPO_ROOT/CLAUDE_TEMPLATE.md"                    "$PLUG/"

# run_hook <project-dir> — runs the hook with CLAUDE_PLUGIN_ROOT UNSET so the
# BASH_SOURCE self-location path (#1046–48) is what resolves the plugin root.
run_hook() {
  env -u CLAUDE_PLUGIN_ROOT CLAUDE_PROJECT_DIR="$1" \
    bash "$PLUG/hooks/session-rules-context.sh" 2>"$TMP/hook.stderr"
}

# ── Case 1 — fresh mirror-less project, NO config: envelope + landmark ─────
PROJ1="$TMP/proj1"
mkdir -p "$PROJ1"
OUT1="$(run_hook "$PROJ1")"
rc=$?

if [ "$rc" -eq 0 ] && [ -n "$OUT1" ]; then
  pass "1a. fresh no-config project: hook exits 0 with non-empty stdout"
else
  fail "1a. fresh no-config project emitted nothing (rc=$rc)"
  sed 's/^/      stderr: /' "$TMP/hook.stderr"
fi

# 1b — well-formed SessionStart envelope whose additionalContext carries the
# de-parameterized template landmarks and no leftover {{TOKEN}}.
ENV_CHECK="$(printf '%s' "$OUT1" | "$PYTHON" -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception as e:
    print(f"BAD-JSON {e}"); sys.exit(0)
h = d.get("hookSpecificOutput", {})
ctx = h.get("additionalContext", "")
checks = [
    h.get("hookEventName") == "SessionStart",
    "## Cron-fired prompts" in ctx,
    "Memory anchors are agent-local notes" in ctx,
    "{{" not in ctx,
    len(ctx) > 1000,
]
print("OK" if all(checks) else f"BAD {checks}")
')"
if [ "$ENV_CHECK" = "OK" ]; then
  pass "1b. envelope is SessionStart/additionalContext, carries template landmarks, no {{TOKEN}}"
else
  fail "1b. envelope malformed or landmark missing: $ENV_CHECK"
fi

# 1c — ZERO writes into the project (R-b's whole point).
PROJ1_FILES="$(find "$PROJ1" -type f | wc -l | tr -d ' ')"
if [ "$PROJ1_FILES" = "0" ]; then
  pass "1c. zero files written into the project"
else
  fail "1c. hook wrote into the project: $(find "$PROJ1" -type f)"
fi

# ── Case 2 — project managed.md present (guard 2): EMPTY output ────────────
# The guard keys on file EXISTENCE (any disk-delivered rules copy — legacy
# render, or a stale copy from the retired pre-redesign installer). The
# stale-copy fixture derives the legacy sentinel prefix by sourcing
# init-state.sh's frozen constant (#1132 — never a re-typed literal).
# shellcheck source=skills/update-zskills/scripts/init-state.sh
. "$REPO_ROOT/skills/update-zskills/scripts/init-state.sh"
PROJ2="$TMP/proj2"
mkdir -p "$PROJ2/.claude/rules/zskills"
printf '%s\n' "<!-- $ZSKILLS_LEGACY_SENTINEL_PREFIX 2026.06.0 -->" '# stale rules' \
  > "$PROJ2/.claude/rules/zskills/managed.md"
OUT2="$(run_hook "$PROJ2")"
if [ -z "$OUT2" ]; then
  pass "2. project managed.md present (stale legacy-installer copy) → empty output (guard 2)"
else
  fail "2. guard 2 did not fire (got ${#OUT2} bytes)"
fi

# ── Case 3 — legacy mirror present (guard 1, detect-style): EMPTY output ───
PROJ3="$TMP/proj3"
mkdir -p "$PROJ3/.claude/skills/update-zskills"
printf '%s\n' '# legacy mirror SKILL' > "$PROJ3/.claude/skills/update-zskills/SKILL.md"
OUT3="$(run_hook "$PROJ3")"
if [ -z "$OUT3" ]; then
  pass "3. legacy mirror present → empty output (guard 1, detect-style)"
else
  fail "3. guard 1 did not fire (got ${#OUT3} bytes)"
fi

# ── Case 4 — project config present: renders WITH --config, same envelope ──
PROJ4="$TMP/proj4"
mkdir -p "$PROJ4/.claude"
printf '%s\n' '{"timezone":"UTC","testing":{"unit_cmd":"make t","full_cmd":"make ta"}}' \
  > "$PROJ4/.claude/zskills-config.json"
OUT4="$(run_hook "$PROJ4")"
ENV4="$(printf '%s' "$OUT4" | "$PYTHON" -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("BAD"); sys.exit(0)
h = d.get("hookSpecificOutput", {})
print("OK" if h.get("hookEventName") == "SessionStart"
      and "## Cron-fired prompts" in h.get("additionalContext", "") else "BAD")
')"
if [ "$ENV4" = "OK" ]; then
  pass "4. project config present → renders via --config, same envelope shape"
else
  fail "4. config-present render failed or malformed"
fi
# A config file is project state the hook READS, not a write — assert the
# hook added nothing beyond the fixture's own file.
PROJ4_FILES="$(find "$PROJ4" -type f | wc -l | tr -d ' ')"
if [ "$PROJ4_FILES" = "1" ]; then
  pass "4b. config-present run wrote nothing (only the fixture config remains)"
else
  fail "4b. unexpected project writes: $(find "$PROJ4" -type f)"
fi

# check_render_fail_nudge <hook-output> — asserts the #1150 render-failure
# contract: a systemMessage nudge naming the failure + the diagnose command,
# and NO additionalContext (rules delivery stays fail-closed on the MODEL
# channel — failure must never fabricate rules).
check_render_fail_nudge() {
  printf '%s' "$1" | "$PYTHON" -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception as e:
    print(f"BAD-JSON {e}"); sys.exit(0)
msg = d.get("systemMessage", "")
ctx = d.get("hookSpecificOutput", {}).get("additionalContext", "")
checks = [
    "zskills rules unavailable" in msg,
    "/zs:update-zskills" in msg,
    ctx == "",
]
print("OK" if all(checks) else f"BAD {checks}")
'
}

# ── Case 5 — defaults artifact missing → render fails CLOSED + USER nudge ──
# Pins that no-config mode genuinely loads the canonical zskills-defaults.json
# (not a second in-renderer copy): without it the render errors and the hook
# fabricates NO rules context — but (#1150 item 2) it must no longer be
# silent: a one-line systemMessage nudge signals the failure to the user.
PLUG5="$TMP/plugin-nodefaults"
cp -a "$PLUG" "$PLUG5"
rm -f "$PLUG5/skills/update-zskills/scripts/zskills-defaults.json"
PROJ5="$TMP/proj5"
mkdir -p "$PROJ5"
OUT5="$(env -u CLAUDE_PLUGIN_ROOT CLAUDE_PROJECT_DIR="$PROJ5" \
  bash "$PLUG5/hooks/session-rules-context.sh" 2>/dev/null)"
rc5=$?
NUDGE5="$(check_render_fail_nudge "$OUT5")"
if [ "$rc5" -eq 0 ] && [ "$NUDGE5" = "OK" ]; then
  pass "5. defaults artifact missing → no additionalContext (fails closed) + systemMessage nudge, exit 0"
else
  fail "5. render-failure contract broken (rc=$rc5, check=$NUDGE5, out=${OUT5:0:120})"
fi

# ── Case 6 — broken project config → render fails → nudge, zero writes ─────
# The M3 scenario the nudge exists for: a corrupt .claude/zskills-config.json
# silently killed rules delivery every session. The hook must exit 0
# (fail-open), emit the nudge, fabricate no rules, and write nothing.
PROJ6="$TMP/proj6"
mkdir -p "$PROJ6/.claude"
printf '%s\n' '{ this is not json' > "$PROJ6/.claude/zskills-config.json"
OUT6="$(run_hook "$PROJ6")"
rc6=$?
NUDGE6="$(check_render_fail_nudge "$OUT6")"
if [ "$rc6" -eq 0 ] && [ "$NUDGE6" = "OK" ]; then
  pass "6. broken config → render failure signalled via systemMessage nudge, no additionalContext, exit 0"
else
  fail "6. broken-config failure contract broken (rc=$rc6, check=$NUDGE6, out=${OUT6:0:120})"
fi
PROJ6_FILES="$(find "$PROJ6" -type f | wc -l | tr -d ' ')"
if [ "$PROJ6_FILES" = "1" ]; then
  pass "6b. broken-config run wrote nothing (only the fixture config remains)"
else
  fail "6b. unexpected project writes: $(find "$PROJ6" -type f)"
fi

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
