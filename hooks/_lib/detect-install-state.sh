# detect-install-state.sh — install-lane detection probe.
#
# Defines `detect_install_state <project-dir>` which echoes exactly one of:
#   fresh | plugin | update-zskills | dual
#
# Sourced (not exec'd) by:
#   - hooks/block-unmaterialised-skill.sh (the init gate's legacy-mirror
#     allow),
#   - hooks/session-start-greeting.sh + hooks/session-rules-context.sh
#     (mirror-present → stay silent / skip),
#   - skills/update-zskills/SKILL.md Step 0.7 (the lane check that routes
#     the bare-call init/update arm and the W6.1 install refuse).
#
# Detection is CONSERVATIVE: evidence is collected for both lanes and ANY
# hit fires the corresponding lane; both → `dual`.
#
# Evidence rules (INSTALL_REDESIGN Phase 7 — the subtractive rework; the
# retired D20 materialiser-sentinel rules and the lane lock-file rule were
# deleted with the materialiser + lane-switch machinery):
#   (1) plugin-lane evidence: the plugin is LOADED in this context —
#       `$CLAUDE_PLUGIN_ROOT` is set (hook subprocesses get it from the
#       harness; Step 0.7's skill fences get it via render-time
#       substitution, Phase 1 Claim 5).
#   (2) update-zskills-lane evidence: a `.claude/skills/<name>/SKILL.md`
#       mirror for a zskills-owned <name> (the anchor set below), OR a
#       settings.json hook entry whose path-token lives under
#       `.claude/hooks/`.
#
# Resolution: fresh = neither; plugin = plugin only; update-zskills =
# update-zskills only; dual = both (the dogfood repo in a plugin session,
# or a mid-consolidation consumer).

# Resolve Python (per `## Python is required`).
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
_dis_python="$(zskills_resolve_python || true)"

detect_install_state() {
  local proj="${1:-${CLAUDE_PROJECT_DIR:-.}}"
  local claude="$proj/.claude"

  local plugin_hit=0
  local uz_hit=0

  # ── (1) Plugin-lane evidence: env context ───────────────────────────────
  # The plugin is loaded in this session (hook subprocess env, or the
  # render-time-substituted fence export in Step 0.7).
  [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && plugin_hit=1

  # ── (2) update-zskills-lane evidence ────────────────────────────────────
  # A `.claude/skills/<name>/SKILL.md` exists for a ZSKILLS-OWNED <name>.
  #
  # This was a bare `.claude/skills/*/SKILL.md` wildcard (F-DA3-1 closure),
  # but that mis-classified a PLUGIN consumer who ships their OWN, non-zskills
  # skills (e.g. playwright-cli, social-seo) as the /update-zskills lane
  # (#1064).
  #
  # The fix scopes the loop to the zskills-owned anchor set below. It is
  # staleness-tolerant: a legacy mirror ALWAYS includes `update-zskills` (the
  # installer) plus the stable core skills, so a future new skill not yet in
  # this list never breaks lane detection — the mirror still carries the
  # anchors. A consumer's own non-zskills skill does not count as evidence.
  # (Derived from the repo's `skills/` directory names.)
  local _dis_zskills_skills="briefing cleanup-merged commit create-worktree do draft-plan draft-tests fix-issues fix-report investigate land-pr manual-testing plans qe-audit refine-plan research-and-go research-and-plan run-plan session-report update-zskills verify-changes work-on-plans zskills-dashboard"
  local _sk_name
  for _sk_name in $_dis_zskills_skills; do
    if [ -f "$claude/skills/$_sk_name/SKILL.md" ]; then
      uz_hit=1
      break
    fi
  done

  # settings.json hook entry whose path-token lives UNDER .claude/hooks/
  # (supplementary cross-check — useful when a consumer manually deleted
  # .claude/skills/ content but left the settings.json registrations).
  if [ "$uz_hit" -eq 0 ] && [ -f "$claude/settings.json" ] && [ -n "$_dis_python" ]; then
    if "$_dis_python" - "$claude/settings.json" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
except Exception:
    sys.exit(1)
hooks = data.get("hooks", {})
if not isinstance(hooks, dict):
    sys.exit(1)
for event in hooks.values():
    if not isinstance(event, list):
        continue
    for matcher in event:
        if not isinstance(matcher, dict):
            continue
        for h in matcher.get("hooks", []):
            if not isinstance(h, dict):
                continue
            cmd = h.get("command", "")
            if not isinstance(cmd, str) or not cmd.strip():
                continue
            token = cmd.split()[-1].strip('"').strip("'")
            # The substituted form is $CLAUDE_PROJECT_DIR/.claude/hooks/... or
            # ${CLAUDE_PROJECT_DIR}/.claude/hooks/...; match on the literal
            # `.claude/hooks/` segment regardless of upstream variable.
            if "/.claude/hooks/" in token or token.startswith(".claude/hooks/"):
                sys.exit(0)
sys.exit(1)
PY
    then
      uz_hit=1
    fi
  fi

  # ── Lane resolution ─────────────────────────────────────────────────────
  if [ "$plugin_hit" -eq 1 ] && [ "$uz_hit" -eq 1 ]; then
    echo dual
  elif [ "$plugin_hit" -eq 1 ]; then
    echo plugin
  elif [ "$uz_hit" -eq 1 ]; then
    echo update-zskills
  else
    echo fresh
  fi
}
