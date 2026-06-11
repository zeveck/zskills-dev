#!/usr/bin/env bash
# zskills-hook-version: 2026.06.11
# session-rules-context.sh — R-b SessionStart rules delivery (INSTALL_REDESIGN
# Phase 4, branch R-b per the Phase 1 Findings: Claim 3 PASS in both install
# shapes).
#
# PLUGIN-LANE-ONLY. Registered solely in hooks/hooks.json under SessionStart
# (alongside session-start-greeting.sh — multiple SessionStart hooks are
# legal). There is intentionally NO .claude/hooks/ mirror and NO
# .claude/settings.json sibling: the legacy /update-zskills lane delivers the
# managed rules from disk (.claude/rules/zskills/managed.md, auto-loaded at
# session start), so it needs no SessionStart delivery.
#
# What it does: renders the DE-PARAMETERIZED CLAUDE_TEMPLATE.md (install-level
# rules, no per-project tokens) via the canonical renderer
# (scripts/render-managed-rules.py — D24, one renderer both lanes) and emits
# the result as `additionalContext` in the documented SessionStart JSON
# envelope. Per #1088/#1089 SessionStart channel semantics:
# `additionalContext` is the MODEL channel — exactly what rules want.
# `systemMessage` (the USER channel) is deliberately NOT co-emitted here:
# combined-envelope co-delivery is ATTENDED-PENDING from Phase 1's Claim-3
# sub-probe, so Phase 7 kept the greeting as its own SessionStart hook
# (session-start-greeting.sh) instead of folding it in here.
#
# ZERO WRITES: the render goes to a mktemp file outside the project; nothing
# is ever written into $CLAUDE_PROJECT_DIR. This is the R-b replacement for
# the retired materialiser's managed.md write (deleted in Phase 7).
#
# Guards (skip = exit 0 with NO output):
#   1. Legacy mirror present (detect-style: detect_install_state returns
#      update-zskills or dual) — the rules already arrive from the mirror's
#      disk render; delivering them again would duplicate ~40KB of rules in
#      context every session.
#   2. A project .claude/rules/zskills/managed.md exists — a rules copy
#      already delivered from disk (legacy render, R-c render, or a STALE
#      materialiser-era sentinelled copy on an upgraded consumer that the
#      Phase 6a A1.5 cleanup hasn't removed yet). After A1.5 removes a
#      sentinelled stale copy, this guard naturally opens and the hook takes
#      over.
#
# Scope acceptance (Phase 1 Claim-3 enablement-scope sub-probe, recorded
# fact): a USER-scope plugin install (the CLI default) fires SessionStart
# hooks in EVERY project, including non-zskills ones — so under a user-scope
# install this hook delivers the zskills rules context (~40KB) in unrelated
# projects too. The plan ACCEPTS this: it is strictly less invasive than the
# status quo (the materialiser WRITES 5 files into every such project; this
# hook writes nothing), and the cure is project-scope enablement — Phase 9's
# install guide documents project-scoped installation as the recommended
# shape and states this trade.

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

# ── Guard 1 — legacy mirror present (detect-style mirror check) ───────────
# Fail-safe: if the detect lib is missing the tree is broken — deliver
# nothing rather than risk double-delivery.
[ -f "$PLUGIN/hooks/_lib/detect-install-state.sh" ] || exit 0
. "$PLUGIN/hooks/_lib/detect-install-state.sh"
LANE="$(detect_install_state "$PROJ")"
case "$LANE" in
  update-zskills|dual) exit 0 ;;
esac

# ── Guard 2 — a project rules copy already delivered from disk ────────────
[ -f "$PROJ/.claude/rules/zskills/managed.md" ] && exit 0

# zskills_resolve_python — print path to a working Python 3 interpreter, or
# empty if none. Probe-RUNS each candidate (existence is NOT enough: on Windows
# `command -v python3` finds the MS Store App-Execution-Alias stub, which exits
# non-zero when run). Honors ZSKILLS_PYTHON. Rejects python2.
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
if [ -z "$PYTHON" ]; then
  echo "zskills: no working Python 3 found; rules context skipped — set ZSKILLS_PYTHON" >&2
  exit 0
fi

TEMPLATE="$PLUGIN/CLAUDE_TEMPLATE.md"
[ -f "$TEMPLATE" ] || exit 0

# emit_render_fail_nudge — one-line USER-channel signal when the render
# fails (#1150 item 2). The old pure-silent `|| exit 0` meant a broken
# project config killed rules delivery EVERY session with no symptom until
# verify-install was run. On failure we emit `systemMessage` ONLY — no
# `additionalContext` is ever fabricated (rules delivery stays fail-closed
# on the MODEL channel), and the SUCCESS path below stays
# additionalContext-only (the two-channel design is unchanged). Fail-open:
# always exit 0.
emit_render_fail_nudge() {
  "$PYTHON" -c 'import json; print(json.dumps({"systemMessage": "zskills rules unavailable: managed-rules render failed — run /zs:update-zskills to diagnose"}))' 2>/dev/null
  exit 0
}

# ── Render (zero project writes — mktemp outside the project) ─────────────
RULES_TMP="$(mktemp)" || exit 0
trap 'rm -f "$RULES_TMP"' EXIT

CONFIG="$PROJ/.claude/zskills-config.json"
if [ -f "$CONFIG" ]; then
  "$PYTHON" "$PLUGIN/scripts/render-managed-rules.py" \
    --config "$CONFIG" --template "$TEMPLATE" --out "$RULES_TMP" >&2 || emit_render_fail_nudge
else
  # No-config mode: the renderer loads the canonical built-in defaults
  # (skills/update-zskills/scripts/zskills-defaults.json) itself.
  "$PYTHON" "$PLUGIN/scripts/render-managed-rules.py" \
    --template "$TEMPLATE" --out "$RULES_TMP" >&2 || emit_render_fail_nudge
fi
[ -s "$RULES_TMP" ] || emit_render_fail_nudge

# ── Emit the SessionStart envelope: additionalContext (MODEL channel) ──────
"$PYTHON" - "$RULES_TMP" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    rules = f.read()
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": rules,
    }
}))
PY
exit 0
