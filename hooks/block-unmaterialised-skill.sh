#!/bin/bash
# zskills-hook-version: 2026.06.10
# block-unmaterialised-skill.sh — UserPromptExpansion init-gate
# (#1128, re-keyed by INSTALL_REDESIGN Phase 6b).
#
# PLUGIN-LANE-ONLY. Registered solely in hooks/hooks.json under the
# UserPromptExpansion event (NO matcher — fires for the whole event and
# self-filters on command_name). There is intentionally NO .claude/hooks/
# mirror and NO .claude/settings.json sibling: the half-set-up problem this
# closes is plugin-lane-only (the /update-zskills lane installs everything at
# install time, so a /update-zskills consumer is never half-set-up).
#
# The faceplant this closes: a plugin consumer loads zskills but has not run
# the ONE-TIME explicit setup (`/zs:update-zskills` — the Phase 6a init that
# verifies the `.zskills/` gitignore umbrella and writes the init markers
# lock-LAST). State-WRITING skills would then scatter `.zskills/` runtime
# state into an unprepared repo. UserPromptExpansion fires on EVERY `/zs:`
# slash command BEFORE the skill runs and can deterministically block it —
# unlike the superseded PreToolUse init-gate (#1121), which leaked when a
# skill short-circuited past the resolver (confirmed live:
# /zs:session-report).
#
# Decision tree (#1121→#1128: deterministic per-invocation; cure exempt):
#   command_name !~ ^zs:            -> allow (not a zskills plugin command)
#   command_name == zs:update-zskills -> allow (the CURE; never block it)
#   skill in the ALLOW-LIST below    -> allow (read-only; safe pre-init)
#   legacy mirror present            -> allow (detect-install-state.sh lane
#                                       update-zskills/dual — a mirrored repo
#                                       is initialised by definition; keeps
#                                       dogfood + dual-load working with no
#                                       magic init-done marker)
#   init-done present                -> allow (zskills_init_done_present(),
#                                       sourced from init-state.sh — the
#                                       #1132 single path definition)
#   else                             -> BLOCK with the one-time-setup pointer
#
# The allow/block categorization is the settled Phase 6b shape: ONLY the
# allow-list gates (everything unlisted is blocked pre-init — a NEW skill
# fails safe to blocked). The block-acknowledged list below is NOT read by
# the gate logic; it exists so the conformance tripwire
# (tests/test-skill-conformance.sh "Gate allow/block-list tripwire") can
# assert every shipped skill was CONSCIOUSLY categorized — a read-only new
# skill silently blocking pre-init would otherwise ship with no signal.
#
# On block: emit a single-line ASCII reason (no quotes or newlines — they
# break the JSON envelope), exit 0. Else exit 0 with no output.

# ── Gate categorization (conformance tripwire reads BOTH lists) ────────────
# ALLOW: read-only skills — they write no project state (no markers, no
# branches, no audit files) and are safe before the one-time setup.
# update-zskills is the cure (also exempted explicitly above the list check).
ZSKILLS_GATE_ALLOW="briefing manual-testing plans session-report update-zskills"
# BLOCK-ACKNOWLEDGED: every other shipped skill, each consciously
# categorized as state-writing (markers, worktrees/branches, commits, audit
# files, monitor state). NOT consumed by the gate logic — unlisted skills
# are blocked anyway (fails safe); this list only feeds the CI tripwire.
ZSKILLS_GATE_BLOCK_ACK="cleanup-merged commit create-worktree do draft-plan draft-tests fix-issues fix-report investigate land-pr qe-audit refine-plan research-and-go research-and-plan run-plan verify-changes work-on-plans zskills-dashboard"

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

# Allow-list: read-only skills pass pre-init.
SKILL_NAME="${CMD_NAME#zs:}"
case " $ZSKILLS_GATE_ALLOW " in
  *" $SKILL_NAME "*) exit 0 ;;
esac

# Resolve the project dir the standard way (CLAUDE_PROJECT_DIR is set in
# hook subprocesses; fall back to pwd defensively). Windows-portable: no
# /tmp, paths via $CLAUDE_PROJECT_DIR.
PROJ="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Plugin root via BASH_SOURCE self-location (#1046–48): this hook lives at
# <plugin-root>/hooks/, so the root is the parent dir. Fall back to the
# harness env var defensively.
PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"
[ -n "$PLUGIN" ] || PLUGIN="${CLAUDE_PLUGIN_ROOT:-}"

# ── Legacy-mirror allow ─────────────────────────────────────────────────────
# When the legacy /update-zskills mirror is present, the repo is initialised
# by definition (mirror install IS the legacy setup). Call the canonical
# detector (its 23-name zskills-skill anchor evidence) — never re-implement
# it. Lanes update-zskills and dual both mean "mirror present" -> allow.
# This is what keeps the dogfood repo (--plugin-dir + mirror) working with
# no .zskills/init-done. If the detect lib is missing the plugin tree is
# broken — fall through to the marker check rather than allow blindly.
if [ -n "$PLUGIN" ] && [ -f "$PLUGIN/hooks/_lib/detect-install-state.sh" ]; then
  . "$PLUGIN/hooks/_lib/detect-install-state.sh"
  case "$(detect_install_state "$PROJ")" in
    update-zskills|dual) exit 0 ;;
  esac
fi

# ── Init-done predicate (#1132 single path definition) ──────────────────────
# Source init-state.sh — THE one definition of the marker path + presence
# predicate (the same file the Step 0.7 init writer and every fixture
# source). Plugin-root env form first, BASH_SOURCE self-location fallback.
if [ -f "${CLAUDE_PLUGIN_ROOT:-}/skills/update-zskills/scripts/init-state.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/init-state.sh"
elif [ -n "$PLUGIN" ] && [ -f "$PLUGIN/skills/update-zskills/scripts/init-state.sh" ]; then
  . "$PLUGIN/skills/update-zskills/scripts/init-state.sh"
fi

if command -v zskills_init_done_present >/dev/null 2>&1 \
   && zskills_init_done_present "$PROJ"; then
  # Initialised -> allow.
  exit 0
fi

# NOT initialised (or init-state.sh unresolvable = broken tree) -> block.
# The cure command is named verbatim; the message is one ASCII line.
printf '{"decision":"block","reason":"%s"}' \
  "zskills needs one-time setup -- run /zs:update-zskills, then re-run your command."
exit 0
