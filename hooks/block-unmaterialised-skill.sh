#!/bin/bash
# zskills-hook-version: 2026.06.1
# block-unmaterialised-skill.sh — UserPromptExpansion gate (#1128).
#
# PLUGIN-LANE-ONLY. Registered solely in hooks/hooks.json under the
# UserPromptExpansion event (NO matcher — fires for the whole event and
# self-filters on command_name). There is intentionally NO .claude/hooks/
# mirror and NO .claude/settings.json sibling: the half-installed problem
# this closes is plugin-lane-only (the /update-zskills lane materialises at
# install time, so a /update-zskills consumer is never half-installed).
#
# The faceplant this closes: a user does `/plugin install zs@zskills` ->
# `/reload-plugins` and the skills + hooks load, but the SessionStart
# materialiser has NOT run yet (it only fires on `/clear` or a full restart),
# so the 5 consumer-side artifacts are not on disk. Skills "largely work" in
# a broken, unreliable way. UserPromptExpansion fires on EVERY `/zs:` slash
# command BEFORE the skill runs and can deterministically block it — unlike
# the superseded PreToolUse init-gate (#1121), which keyed on a Bash command
# sourcing zskills-resolve-config.sh and leaked when a skill short-circuited
# past the resolver (confirmed live: /zs:session-report).
#
# Block condition:
#   command_name matches ^zs:               (a zskills plugin slash command)
#   AND command_name != zs:update-zskills   (update-zskills is the CURE; never block it)
#   AND the materialiser sentinel is ABSENT (NOT materialized — see below)
# `^zs:` only — block-diagram skills ride INSIDE the zs plugin (they expand
# as zs:add-block, NOT zsbd:); the zsbd marketplace plugin is delisted, so
# zsbd: never matches a real consumer.
#
# NOT materialized iff $CLAUDE_PROJECT_DIR/.claude/agents/verifier.md is absent
# OR its first 3 lines lack the D20(a) materialiser sentinel prefix
# `zskills-materialised:` — the SAME signal the removed PreToolUse gate used /
# detect-install-state.sh reads. The materialiser writes the sentinel to
# .claude/agents/verifier.md (session-start-materialise.sh:296), so this gate
# MUST read that same path; reading the bare .claude/verifier.md made the
# "materialised -> allow" branch unreachable on a real install (#1132).
#
# On block: emit a single-line ASCII reason (no quotes or newlines — they
# break the JSON envelope), exit 0. Else exit 0 with no output.

INPUT=$(cat)

# Extract command_name from the UserPromptExpansion JSON. Prefer python3
# (repo convention; robust against escaping); fall back to bash regex when no
# Python 3 is available so the gate still functions.
zskills_resolve_python() {
  local cand
  for cand in "${ZSKILLS_PYTHON:-}" python3 python; do
    [ -n "$cand" ] || continue
    command -v "$cand" >/dev/null 2>&1 || continue
    if "$cand" -c 'import sys; sys.exit(0 if sys.version_info[0]==3 else 1)' >/dev/null 2>&1; then
      command -v "$cand"; return 0
    fi
  done
  return 1
}
PYTHON="$(zskills_resolve_python || true)"

CMD_NAME=""
if [ -n "$PYTHON" ]; then
  CMD_NAME=$("$PYTHON" -c '
import sys, json
try:
    d = json.load(sys.stdin)
    sys.stdout.write(str(d.get("command_name", "")))
except Exception:
    pass
' <<<"$INPUT")
else
  CMD_NAME=$(echo "$INPUT" | sed -n 's/.*"command_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi

# Only zskills plugin slash commands (^zs:). Everything else (help, other
# plugins, bare prompts) -> allow.
case "$CMD_NAME" in
  zs:*) ;;
  *) exit 0 ;;
esac

# update-zskills is the CURE — never block it.
[ "$CMD_NAME" = "zs:update-zskills" ] && exit 0

# Materialised iff verifier.md carries the materialiser sentinel in its first
# 3 lines. Resolve the project dir the standard way (CLAUDE_PROJECT_DIR is set
# in hook subprocesses; fall back to pwd defensively). Windows-portable: no
# /tmp, paths via $CLAUDE_PROJECT_DIR.
PROJ="${CLAUDE_PROJECT_DIR:-$(pwd)}"
# Canonical materialiser sentinel path — MUST match the dest the materialiser
# writes (session-start-materialise.sh:296 -> .claude/agents/verifier.md) and
# the path detect-install-state.sh reads. See #1132.
ARTIFACT="$PROJ/.claude/agents/verifier.md"
if [ -f "$ARTIFACT" ] && head -n 3 "$ARTIFACT" 2>/dev/null | grep -Eq '^(#|<!--)[[:space:]]+zskills-materialised:[[:space:]]'; then
  # Materialized -> allow.
  exit 0
fi

# NOT materialized -> block.
printf '{"decision":"block","reason":"%s"}' \
  "zskills isn't finished installing -- restart Claude Code (or /clear) to finish setup, then run /update-zskills."
exit 0
