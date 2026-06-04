#!/usr/bin/env bash
# zskills-hook-version: 2026.06.1
# nudge-restart-to-materialise.sh — UserPromptSubmit restart nudge (#1080).
#
# THE GAP: after `/plugin install zs@zskills` -> `/reload-plugins`, the
# skills and hooks load, but the SessionStart hook does NOT fire on
# `/reload-plugins` (only `/clear` or a full restart fires it). So
# session-start-materialise.sh never runs — the 5 consumer-side artifacts
# (verifier.md, implementer.md, inject-bash-timeout.sh,
# verify-response-validate.sh, the rendered managed.md) and the seeded
# .claude/zskills-config.json are NOT written. The consumer is stuck
# half-installed with nothing telling them to restart.
#
# THE FIX: this UserPromptSubmit hook fires on the user's NEXT prompt after
# `/reload-plugins` and prints a one-time advisory nudge telling them to
# `/clear` (or restart) to fire SessionStart and finish setup.
#
# It is a COMMITTED .sh (fixed logic, like block-unsafe-generic.sh — NOT a
# D4 .template/sibling pair), registered ONLY in hooks/hooks.json under a
# UserPromptSubmit event. It has NO .claude/settings.json sibling (it is a
# plugin-lane-only concern: the /update-zskills lane materialises at install
# time and never reaches the half-installed state this nudges about). So it
# does NOT source the D16(a) conditional-skip shim — there is no
# same-basename sibling to double-fire against.
#
# TRIGGER PREDICATE — print the nudge ONLY when ALL of:
#   * $CLAUDE_PLUGIN_ROOT set AND $CLAUDE_PROJECT_DIR set.
#   * detect_install_state "$CLAUDE_PROJECT_DIR" == fresh. This is the
#     half-installed state (plugin loaded, artifacts not yet materialised —
#     fresh = neither lane's on-disk evidence present). It SELF-EXTINGUISHES:
#     once SessionStart materialises, the 5 artifacts carry the materialiser
#     sentinel -> lane==plugin -> predicate false. And it NEVER fires on the
#     legacy (update-zskills) or dev (dual) lanes, which are never `fresh`.
#   * No once-per-session marker yet (.zskills/restart-nudge-shown-<sid>).
#
# It is ADVISORY: it MUST `exit 0` always and never block the prompt. Any
# error fails open (exit 0, no nudge).

set -u

# Without both env vars we are not a plugin-lane hook in a project — exit
# silently (fail-open).
PLUGIN="${CLAUDE_PLUGIN_ROOT:-}"
PROJ="${CLAUDE_PROJECT_DIR:-}"
[ -n "$PLUGIN" ] || exit 0
[ -n "$PROJ" ] || exit 0

# Read the UserPromptSubmit JSON from stdin once. Never fail on a read error.
INPUT="$(cat 2>/dev/null)" || exit 0

# Extract session_id with a TOLERANT grep/sed so a missing python can never
# break the nudge. The hook JSON shape is `{"session_id":"abc",...}`. We
# accept whitespace around the colon and a quoted value. A missing/empty
# session_id is tolerated — we fall back to a fixed token so the marker still
# de-dupes within the session (one nudge max either way).
SESSION_ID="$(printf '%s' "$INPUT" \
  | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | head -n1 \
  | sed -E 's/.*"session_id"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')"
[ -n "$SESSION_ID" ] || SESSION_ID="nosid"

# Locate detect-install-state.sh under the plugin root. If unreachable, we
# cannot classify the lane — exit silently (fail-open).
DIS="${PLUGIN}/hooks/_lib/detect-install-state.sh"
[ -f "$DIS" ] || exit 0

# Source the lane-detection helper and classify. Any error -> fail-open.
# shellcheck disable=SC1090
. "$DIS" 2>/dev/null || exit 0
LANE="$(detect_install_state "$PROJ" 2>/dev/null || true)"

# Fire ONLY in the half-installed (fresh) state.
[ "$LANE" = fresh ] || exit 0

# Once-per-session gate. The marker lives under $CLAUDE_PROJECT_DIR/.zskills/
# (gitignored). If it already exists, we have nudged this session -> silent.
MARKER_DIR="$PROJ/.zskills"
MARKER="$MARKER_DIR/restart-nudge-shown-$SESSION_ID"
[ -f "$MARKER" ] && exit 0

# Create the marker BEFORE printing so a concurrent/duplicate fire in the
# same session does not double-nudge. Marker-dir creation failure is
# non-fatal (we still nudge once — better an extra nudge than none).
mkdir -p "$MARKER_DIR" 2>/dev/null || true
: > "$MARKER" 2>/dev/null || true

# Emit the nudge as UserPromptSubmit JSON on stdout. We use TWO channels:
#
#   * top-level `systemMessage` — the USER-VISIBLE channel. A live Claude Code
#     spike (#1088) confirmed a UserPromptSubmit hook returning `systemMessage`
#     renders to the user as a NON-BLOCKING notice (CLI-prefixed with
#     "UserPromptSubmit says:") while the prompt STILL reaches the model. Bare
#     stdout (the prior implementation) only reached the model — the bug #1088
#     fixes. NOTE: the "UserPromptSubmit says:" prefix is CLI-applied and not
#     controllable here, so the message is worded to read well after it (it does
#     NOT begin with "UserPromptSubmit").
#   * hookSpecificOutput.additionalContext (UserPromptSubmit) — the MODEL-FACING
#     channel, so the agent is also aware and can reinforce the nudge.
#
# The text is essentially static. Build the JSON with Python (json.dumps -> safe
# escaping) via the shared resolver sourced from detect-install-state.sh; if no
# Python is reachable, fall back to a carefully hand-escaped printf with the same
# fixed strings (the message has no shell/JSON metacharacters, so this is safe).
SYSMSG="zskills: the plugin is loaded but setup isn't finished. /reload-plugins does not run the one-time materialisation step, so the verifier/implementer agents, two hooks, the rendered rules file, and your .claude/zskills-config.json have NOT been written yet. Run /clear (or exit and restart Claude Code) to fire the SessionStart hook and finish setup. This only needs to happen once."
CTXMSG="zskills setup is incomplete: the plugin is loaded but the SessionStart materialiser has not run (/reload-plugins does not fire it), so the 5 consumer-side artifacts and .claude/zskills-config.json are not written yet. Tell the user to run /clear (or restart Claude Code) to finish setup — this only needs to happen once."

PY="$(zskills_resolve_python 2>/dev/null || true)"
if [ -n "$PY" ]; then
  ZS_SYSMSG="$SYSMSG" ZS_CTXMSG="$CTXMSG" "$PY" - <<'PYJSON' 2>/dev/null || printf '%s\n' "{\"systemMessage\":\"$SYSMSG\",\"hookSpecificOutput\":{\"hookEventName\":\"UserPromptSubmit\",\"additionalContext\":\"$CTXMSG\"}}"
import json, os
print(json.dumps({
    "systemMessage": os.environ["ZS_SYSMSG"],
    "hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit",
        "additionalContext": os.environ["ZS_CTXMSG"],
    },
}))
PYJSON
else
  # No Python. The two messages contain no JSON metacharacters (no quotes,
  # backslashes, or control chars), so direct interpolation is safe.
  printf '%s\n' "{\"systemMessage\":\"$SYSMSG\",\"hookSpecificOutput\":{\"hookEventName\":\"UserPromptSubmit\",\"additionalContext\":\"$CTXMSG\"}}"
fi

# Advisory hook — always succeed, never block.
exit 0
