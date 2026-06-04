# detect-install-state.sh — D27 dual-install detection probe.
#
# Defines `detect_install_state <project-dir>` which echoes exactly one of:
#   fresh | plugin | update-zskills | dual
#
# Sourced (not exec'd) by:
#   - hooks/session-start-materialise.sh (W2.1) — runs the probe FIRST,
#     before any write, so a `lane=update-zskills` state is never silently
#     overwritten.
#   - scripts/switch-install-path.sh (W5.6).
#
# Detection is CONSERVATIVE (D27): evidence is collected for both lanes and
# ANY hit fires the corresponding lane; ambiguous combinations collapse to
# `dual`. The round-3 KNOWN_SKILLS / KNOWN_HOOKS fixture lists are RETIRED —
# D27 replaced them with wildcards (`.claude/skills/*/SKILL.md`,
# `.claude/hooks/*.sh`). The materialiser-sentinel distinguishes
# plugin-materialised artifacts from /update-zskills-installed ones.
#
# The materialiser-authorship sentinel is detected by the D20(a) prefix
# regex `^(#|<!--) zskills-materialised: ` on the FIRST line of an artifact
# (HTML-comment for plain .md, YAML-comment inside `---` for frontmatter .md,
# shell-comment on line 2 for *.sh). For sentinel detection across all
# artifact kinds we scan the first 3 lines for the prefix.
#
# Lane-resolution order (D27):
#   (1) plugin-lane evidence (lock=plugin, OR any of the 5 materialised
#       artifacts present WITH the materialiser sentinel) — checked FIRST so
#       the wildcard `.claude/hooks/*.sh` rule (which the materialiser ALSO
#       writes to) does not misclassify plugin-materialised hooks.
#   (2) update-zskills-lane evidence (lock=update-zskills, OR any
#       non-sentinelled `.claude/skills/*/SKILL.md` / `.claude/hooks/*.sh`,
#       OR a non-sentinelled agents/managed.md artifact, OR a settings.json
#       hook entry whose path-token lives under `.claude/hooks/`).
#
# Resolution: fresh = neither; plugin = plugin only; update-zskills =
# update-zskills only; dual = both.

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

# Does $1 (a file) carry a materialiser sentinel in its first 3 lines?
# Sentinel prefix per D20(a): a line matching `^(#|<!--) zskills-materialised: `.
_dis_has_sentinel() {
  local f="$1"
  [ -f "$f" ] || return 1
  head -n 3 "$f" 2>/dev/null | grep -Eq '^(#|<!--)[[:space:]]+zskills-materialised:[[:space:]]'
}

detect_install_state() {
  local proj="${1:-${CLAUDE_PROJECT_DIR:-.}}"
  local claude="$proj/.claude"
  local lock="$claude/zskills-install-lane"
  local lock_val=""
  [ -f "$lock" ] && lock_val="$(cat "$lock" 2>/dev/null)"

  local plugin_hit=0
  local uz_hit=0

  # ── (1) Plugin-lane evidence (checked FIRST) ────────────────────────────
  # Lock file content is `plugin` (lock-LAST winner per D25).
  [ "$lock_val" = plugin ] && plugin_hit=1

  # Any of the 5 materialised artifacts present AND sentinelled.
  local mat
  for mat in \
    "$claude/agents/verifier.md" \
    "$claude/agents/implementer.md" \
    "$claude/hooks/inject-bash-timeout.sh" \
    "$claude/hooks/verify-response-validate.sh" \
    "$claude/rules/zskills/managed.md"; do
    if _dis_has_sentinel "$mat"; then
      plugin_hit=1
      break
    fi
  done

  # ── (2) update-zskills-lane evidence ────────────────────────────────────
  # Lock file content is `update-zskills`.
  [ "$lock_val" = update-zskills ] && uz_hit=1

  # A `.claude/skills/<name>/SKILL.md` exists for a ZSKILLS-OWNED <name>.
  #
  # This was a bare `.claude/skills/*/SKILL.md` wildcard (F-DA3-1 closure),
  # but that mis-classified a PLUGIN consumer who ships their OWN, non-zskills
  # skills (e.g. playwright-cli, social-seo) as the /update-zskills lane —
  # which made the SessionStart materialiser's D27 probe refuse to write the
  # 5 plugin artifacts, breaking the install (#1064).
  #
  # The fix scopes the loop to the zskills-owned anchor set below. It is
  # staleness-tolerant: a legacy mirror ALWAYS includes `update-zskills` (the
  # installer) plus the stable core skills, so a future new skill not yet in
  # this list never breaks lane detection — the mirror still carries the
  # anchors. A consumer's own non-zskills skill no longer counts as evidence.
  # (Derived from the repo's `skills/` directory names.)
  if [ "$uz_hit" -eq 0 ]; then
    local _dis_zskills_skills="briefing cleanup-merged commit create-worktree do draft-plan draft-tests fix-issues fix-report investigate land-pr manual-testing plans qe-audit refine-plan research-and-go research-and-plan run-plan session-report update-zskills verify-changes work-on-plans zskills-dashboard"
    local _sk_name
    for _sk_name in $_dis_zskills_skills; do
      if [ -f "$claude/skills/$_sk_name/SKILL.md" ]; then
        uz_hit=1
        break
      fi
    done
  fi

  # Any NON-sentinelled `.claude/hooks/*.sh` exists. The materialiser writes
  # to .claude/hooks/ too (Layer 0 + Layer 3), so a hook is only
  # update-zskills evidence if it is NOT sentinelled.
  if [ "$uz_hit" -eq 0 ]; then
    local hk
    for hk in "$claude"/hooks/*.sh; do
      [ -f "$hk" ] || continue
      if ! _dis_has_sentinel "$hk"; then
        uz_hit=1
        break
      fi
    done
  fi

  # Agent / managed.md artifact present WITHOUT a materialiser sentinel
  # (/update-zskills writes these WITHOUT sentinels).
  if [ "$uz_hit" -eq 0 ]; then
    local art
    for art in \
      "$claude/agents/verifier.md" \
      "$claude/agents/implementer.md" \
      "$claude/rules/zskills/managed.md"; do
      if [ -f "$art" ] && ! _dis_has_sentinel "$art"; then
        uz_hit=1
        break
      fi
    done
  fi

  # settings.json hook entry whose path-token lives UNDER .claude/hooks/
  # (supplementary cross-check — useful when a consumer manually deleted
  # .claude/hooks/ content but left the settings.json registrations).
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
