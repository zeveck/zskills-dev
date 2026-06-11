#!/usr/bin/env bash
# zskills-hook-version: 2026.06.10
# session-start-greeting.sh — slim SessionStart setup greeting
# (INSTALL_REDESIGN Phase 7; replaces the retired SessionStart materialiser's
# greeting tail — the materialiser itself is deleted, setup is the explicit
# /zs:update-zskills init).
#
# PLUGIN-LANE-ONLY. Registered solely in hooks/hooks.json under SessionStart
# (alongside session-rules-context.sh — TWO SessionStart entries by design:
# Phase 1's Claim-3 combined-envelope sub-probe is ATTENDED-PENDING, so the
# R-b greeting fold is NOT taken; each hook emits its own single-channel
# envelope). There is intentionally NO .claude/hooks/ mirror and NO
# .claude/settings.json sibling: the legacy /update-zskills lane installs
# everything at install time, so a legacy consumer is never un-initialised.
#
# READ-ONLY, ZERO WRITES. When the project has neither a legacy mirror nor
# the .zskills/init-done marker, emit a `systemMessage` greeting (the USER
# channel — #1088/#1089) pointing at the one-time `/zs:update-zskills` init;
# silent otherwise. W6.3 lesson: the greeting fires EVERY pre-init session by
# design — it is curable (one init run silences it permanently), not a
# nag-loop, so no once-per-session gate.

# D16(a) plugin-lane conditional-skip shim. No settings.json same-basename
# sibling exists for this hook (plugin-lane-only), so the shim no-ops on
# dual installs — sourcing it satisfies the test-plugin-hooks-integrity.sh
# Gap-2 "every hooks.json hook sources the shim" assertion.
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_lib/plugin-hook-skip-if-mirrored.sh" ] && source "${CLAUDE_PLUGIN_ROOT}/hooks/_lib/plugin-hook-skip-if-mirrored.sh"

set -u

PROJ="${CLAUDE_PROJECT_DIR:-}"
[ -n "$PROJ" ] || exit 0

# Plugin root via BASH_SOURCE self-location (#1046–48): this hook lives at
# <plugin-root>/hooks/, so the root is the parent dir. Fall back to the
# harness env var defensively.
PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"
[ -n "$PLUGIN" ] || PLUGIN="${CLAUDE_PLUGIN_ROOT:-}"
[ -n "$PLUGIN" ] || exit 0

# ── Guard 1 — legacy mirror present → silent ───────────────────────────────
# A mirrored repo is initialised by definition (the mirror install IS the
# legacy setup); lanes update-zskills and dual both mean "mirror present".
# Fail-safe: if the detect lib is missing the plugin tree is broken — stay
# silent rather than nag wrongly.
[ -f "$PLUGIN/hooks/_lib/detect-install-state.sh" ] || exit 0
. "$PLUGIN/hooks/_lib/detect-install-state.sh"
case "$(detect_install_state "$PROJ")" in
  update-zskills|dual) exit 0 ;;
esac

# ── Guard 2 — initialised → silent permanently ─────────────────────────────
# #1132 single path definition: source init-state.sh (the same file the
# Step 0.7 init writer, the gate, verify-install, and every fixture source)
# — never a re-typed marker path. Unreachable init-state.sh = broken plugin
# tree → stay silent.
[ -f "$PLUGIN/skills/update-zskills/scripts/init-state.sh" ] || exit 0
. "$PLUGIN/skills/update-zskills/scripts/init-state.sh"
zskills_init_done_present "$PROJ" && exit 0

# ── Greet (USER channel — systemMessage on stdout; #1088/#1089) ────────────
# One ASCII line, fixed text (printf-safe JSON — no Python dependency).
# stdout carries ONLY this JSON; the cure command is named verbatim.
printf '{"systemMessage":"zskills is loaded but needs one-time setup -- run /zs:update-zskills to finish (gitignore entry + init markers, optional config). State-writing zskills skills are blocked until then."}\n'
exit 0
