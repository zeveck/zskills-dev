#!/usr/bin/env bash
# tests/test-nudge-restart-to-materialise.sh
#
# #1080 — the UserPromptSubmit restart nudge. After `/plugin install
# zs@zskills` -> `/reload-plugins`, SessionStart does NOT fire (only `/clear`
# or restart fires it), so session-start-materialise.sh never runs and the
# consumer is stuck half-installed (lane==fresh) with nothing telling them to
# restart. This hook fires on the next prompt and prints a one-time nudge.
#
# #1088 — the nudge MUST reach the USER, not just the model. The hook now
# emits UserPromptSubmit JSON with a top-level `systemMessage` field (the
# user-visible, non-blocking channel — confirmed by a live Claude Code spike)
# plus hookSpecificOutput.additionalContext (model-facing). The prior
# implementation emitted bare stdout, which only reached the model. This test
# asserts the user-visible `systemMessage` field is emitted and that the output
# is valid JSON with a non-empty `systemMessage` — NOT merely "something on
# stdout".
#
# Hermetic: a tmpdir fixture $PROJ (consumer) + a fixture $PLUGIN carrying
# detect-install-state.sh. We feed a UserPromptSubmit JSON on stdin and drive
# the hook directly.
#
# Cases:
#   (a) fresh + plugin-root set + no marker  -> systemMessage JSON emitted +
#                                               valid JSON + marker created.
#   (b) marker already present               -> silent (no nudge).
#   (c) lane == plugin (sentinelled artifact)-> silent.
#   (d) lane == update-zskills (legacy)      -> silent.
#   (e) $CLAUDE_PLUGIN_ROOT unset            -> silent.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

HOOK="$REPO_ROOT/hooks/nudge-restart-to-materialise.sh"
# A stable substring of the nudge message (load-bearing assertion target). The
# hook now delivers this via the user-visible top-level `systemMessage` JSON
# field (#1088), not bare stdout.
NUDGE_MARK="the plugin is loaded but setup isn't finished"

# Resolve a working Python 3 for the JSON-shape assertions (#1088). The repo
# requires Python 3 (no jq); the suite runs in a Python-3 environment.
PY=""
for cand in "${ZSKILLS_PYTHON:-}" python3 python; do
  [ -n "$cand" ] || continue
  command -v "$cand" >/dev/null 2>&1 || continue
  if "$cand" -c 'import sys; sys.exit(0 if sys.version_info[0]==3 else 1)' >/dev/null 2>&1; then
    PY="$(command -v "$cand")"; break
  fi
done

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Fixture $PLUGIN: only needs detect-install-state.sh under hooks/_lib/.
PLUGIN="$TMP/plugin"
mkdir -p "$PLUGIN/hooks/_lib"
cp "$REPO_ROOT/hooks/_lib/detect-install-state.sh" "$PLUGIN/hooks/_lib/"

SID="sess-abcdef-1234"
UPS_JSON='{"session_id":"'"$SID"'","prompt":"hello","cwd":"/tmp/x"}'

# run_hook <project-dir> [extra-env...] — runs the hook with the given $PROJ,
# feeding the UserPromptSubmit JSON on stdin. Echoes stdout; rc captured by
# caller via the surrounding command substitution being non-fatal.
run_hook() {
  local proj="$1"; shift
  printf '%s' "$UPS_JSON" | env "$@" CLAUDE_PROJECT_DIR="$proj" CLAUDE_PLUGIN_ROOT="$PLUGIN" bash "$HOOK"
}

echo "=== nudge-restart-to-materialise.sh (#1080) ==="

# ── (a) fresh + plugin-root + no marker -> nudge + marker ─────────────────────
PROJ_A="$TMP/proj_a"
mkdir -p "$PROJ_A"   # truly empty .claude -> lane==fresh
OUT_A="$(run_hook "$PROJ_A")"
RC_A=$?

if [ "$RC_A" -eq 0 ]; then
  pass "a1. hook exits 0 (advisory, never blocks)"
else
  fail "a1. hook exited non-zero ($RC_A)"
fi

# #1088 — the nudge MUST be delivered via the user-visible top-level
# `systemMessage` JSON field, NOT bare stdout. Assert: (1) the output is valid
# JSON, (2) it has a non-empty top-level `systemMessage`, and (3) that
# systemMessage carries the nudge text. This tightens the contract from
# "something on stdout" to "the user-visible field is populated".
if [ -z "$PY" ]; then
  fail "a2. no Python 3 available to validate systemMessage JSON (#1088)"
else
  A2_RESULT="$(ZS_OUT="$OUT_A" NUDGE_MARK="$NUDGE_MARK" "$PY" - <<'PYCHK'
import os, json
raw = os.environ.get("ZS_OUT", "")
try:
    d = json.loads(raw)
except Exception as e:
    print("NOTJSON:%s" % e); raise SystemExit(0)
sm = d.get("systemMessage")
if not isinstance(sm, str) or not sm.strip():
    print("NOSYSMSG"); raise SystemExit(0)
if os.environ["NUDGE_MARK"] not in sm:
    print("MARKMISSING"); raise SystemExit(0)
hso = d.get("hookSpecificOutput", {})
if hso.get("hookEventName") != "UserPromptSubmit" or not (hso.get("additionalContext") or "").strip():
    print("BADCTX"); raise SystemExit(0)
print("OK")
PYCHK
)"
  case "$A2_RESULT" in
    OK)
      pass "a2. fresh+plugin-root+no-marker: valid JSON with non-empty user-visible systemMessage carrying the nudge + UserPromptSubmit additionalContext (#1088)" ;;
    NOTJSON:*)
      fail "a2. emitted output is not valid JSON ($A2_RESULT)"
      printf '      stdout: %s\n' "$OUT_A" ;;
    NOSYSMSG)
      fail "a2. emitted JSON has no non-empty top-level systemMessage (#1088: nudge must reach the user, not bare stdout)"
      printf '      stdout: %s\n' "$OUT_A" ;;
    MARKMISSING)
      fail "a2. systemMessage present but missing the nudge text (\"$NUDGE_MARK\")"
      printf '      stdout: %s\n' "$OUT_A" ;;
    BADCTX)
      fail "a2. hookSpecificOutput.additionalContext (UserPromptSubmit) missing/empty"
      printf '      stdout: %s\n' "$OUT_A" ;;
    *)
      fail "a2. unexpected JSON-check result: $A2_RESULT"
      printf '      stdout: %s\n' "$OUT_A" ;;
  esac
fi

MARKER_A="$PROJ_A/.zskills/restart-nudge-shown-$SID"
if [ -f "$MARKER_A" ]; then
  pass "a3. once-per-session marker created (.zskills/restart-nudge-shown-<sid>)"
else
  fail "a3. marker NOT created at $MARKER_A"
fi

# ── (b) marker already present -> silent ──────────────────────────────────────
# Re-run against the SAME $PROJ_A (marker now exists from case a).
OUT_B="$(run_hook "$PROJ_A")"
if [ -z "$OUT_B" ]; then
  pass "b. marker present (2nd run, same session): silent (no nudge)"
else
  fail "b. marker present: hook still emitted output"
  printf '      stdout: %s\n' "$OUT_B"
fi

# ── (c) lane == plugin (sentinelled artifact) -> silent ───────────────────────
# Stage a materialiser-sentinelled artifact so detect_install_state -> plugin.
PROJ_C="$TMP/proj_c"
mkdir -p "$PROJ_C/.claude/hooks"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' '# zskills-materialised: 1.2.3'
  printf '%s\n' 'exit 0'
} > "$PROJ_C/.claude/hooks/inject-bash-timeout.sh"
OUT_C="$(run_hook "$PROJ_C")"
if [ -z "$OUT_C" ]; then
  pass "c. lane==plugin (sentinelled artifact present): silent (self-extinguishes)"
else
  fail "c. lane==plugin: hook still emitted output"
  printf '      stdout: %s\n' "$OUT_C"
fi
# And no marker should have been written in the plugin-lane case.
if [ ! -f "$PROJ_C/.zskills/restart-nudge-shown-$SID" ]; then
  pass "c2. lane==plugin: no marker written"
else
  fail "c2. lane==plugin: marker unexpectedly written"
fi

# ── (d) lane == update-zskills (legacy fixture) -> silent ─────────────────────
# A non-sentinelled zskills-owned skill mirror -> detect_install_state ->
# update-zskills.
PROJ_D="$TMP/proj_d"
mkdir -p "$PROJ_D/.claude/skills/update-zskills"
printf '%s\n' '# update-zskills SKILL (legacy mirror, no sentinel)' \
  > "$PROJ_D/.claude/skills/update-zskills/SKILL.md"
OUT_D="$(run_hook "$PROJ_D")"
if [ -z "$OUT_D" ]; then
  pass "d. lane==update-zskills (legacy mirror): silent (never fresh)"
else
  fail "d. lane==update-zskills: hook still emitted output"
  printf '      stdout: %s\n' "$OUT_D"
fi

# ── (e) $CLAUDE_PLUGIN_ROOT unset -> silent ───────────────────────────────────
PROJ_E="$TMP/proj_e"
mkdir -p "$PROJ_E"
OUT_E="$(printf '%s' "$UPS_JSON" | env -u CLAUDE_PLUGIN_ROOT CLAUDE_PROJECT_DIR="$PROJ_E" bash "$HOOK")"
RC_E=$?
if [ -z "$OUT_E" ] && [ "$RC_E" -eq 0 ]; then
  pass "e. \$CLAUDE_PLUGIN_ROOT unset: silent + exit 0 (fail-open)"
else
  fail "e. plugin-root unset: output='$OUT_E' rc=$RC_E"
fi

# ──────────────────────────────────────────────────────────────────────────
echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
