#!/usr/bin/env bash
# verify-install-lib.sh — consumer post-install verifier (assertion library).
#
# Issue #999. A one-shot "did my zskills install actually work in THIS
# environment?" check, bundled in the update-zskills skill so it ships on
# BOTH lanes (legacy mirror → .claude/skills/update-zskills/verifiers/,
# plugin → ${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/verifiers/) and
# auto-run at the end of a successful /update-zskills.
#
# This file is a SOURCEABLE library of pure-bash assertion functions. It is
# the single source of truth for the check logic; the thin entry
# (verify-install.sh) sources it, and the dev test (tests/test-verify-install.sh)
# sources it and exercises it against synthetic installs.
#
# SELF-CONTAINED — deliberately depends on NOTHING outside this file. In
# particular it does NOT source hooks/_lib/detect-install-state.sh: that lib
# is NOT mirrored to a legacy consumer (.claude/hooks/_lib/ is absent), so a
# verifier that sourced it would be broken on the very lane it ships to.
# Lane detection is reimplemented here from the consumer-visible signals.
#
# Checks are the CHEAP STRUCTURAL TIER — fast file/config checks, no live
# `claude`. The heavy live-probe tier is opt-in (vi_run_heavy) and is NOT on
# the auto-run-at-success path.
#
# Result model: each check emits one record to stdout via vi_emit, of the
# form "<status>\t<id>\t<detail>" where status ∈ {PASS,WARN,FAIL}. The
# caller (entry or test) renders/aggregates. Functions also accumulate into
# VI_PASS / VI_WARN / VI_FAIL counters so a caller can branch on totals
# without re-parsing.
#
# No external JSON tools (no jq) — Python stdlib json per project convention.

# Guard against double-source clobbering counters mid-run; callers reset
# explicitly via vi_reset.
VI_PASS=${VI_PASS:-0}
VI_WARN=${VI_WARN:-0}
VI_FAIL=${VI_FAIL:-0}

# Resolve the Python interpreter once. Used for JSON round-tripping.
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
VI_PY="$(zskills_resolve_python || true)"

# vi_reset — zero the counters. Call at the start of a verification run.
vi_reset() {
  VI_PASS=0
  VI_WARN=0
  VI_FAIL=0
}

# vi_emit <status> <id> [detail] — record one check result. Increments the
# matching counter and prints a tab-separated record to stdout.
vi_emit() {
  local status="$1" id="$2" detail="${3:-}"
  case "$status" in
    PASS) VI_PASS=$((VI_PASS + 1)) ;;
    WARN) VI_WARN=$((VI_WARN + 1)) ;;
    FAIL) VI_FAIL=$((VI_FAIL + 1)) ;;
  esac
  printf '%s\t%s\t%s\n' "$status" "$id" "$detail"
}

# ───────────────────────────────────────────────────────────────────────────
# Init-state definitions (#1132 single-path-definition rule — INSTALL_REDESIGN
# Phase 6b). The plugin-lane checks key on the explicit-init markers
# (`.zskills/init-done`, `.zskills/setup-confirmed`), whose paths, presence
# predicate, and writer are defined in exactly ONE place:
# skills/update-zskills/scripts/init-state.sh. This lib SOURCES it from its
# sibling scripts/ dir — present on BOTH lanes (the verifiers/ and scripts/
# dirs ship together in the legacy mirror and the plugin tree), so the lib
# stays lane-portable. Tolerant load: a missing init-state.sh is itself a
# broken install, surfaced as a FAIL inside vi_check_plugin.
# ───────────────────────────────────────────────────────────────────────────
VI_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
if [ -n "$VI_LIB_DIR" ] && [ -f "$VI_LIB_DIR/../scripts/init-state.sh" ]; then
  # shellcheck source=../scripts/init-state.sh
  . "$VI_LIB_DIR/../scripts/init-state.sh"
fi

# ───────────────────────────────────────────────────────────────────────────
# Lane detection (self-contained — no dependency on detect-install-state.sh).
#
# vi_detect_lane <project_dir> → prints one of: plugin | legacy | dual | none
#
#   CLAUDE_PLUGIN_ROOT set in env OR init-done marker present → plugin signal
#   zskills mirror / zskills settings.json hook               → legacy signal
#   both signals                         → dual (UNSUPPORTED — flagged)
#   neither                              → none (no install detected)
#
# Phase 6b re-key: the OLD plugin signal (the D20 materialiser-sentinel
# prefix on artifacts in $proj/.claude — the F2/#1026 fix) dies with the
# materialiser.
# The NEW plugin evidence is the env context (CLAUDE_PLUGIN_ROOT — set when
# the verifier is invoked from a plugin-lane skill fence, which exports it)
# plus the on-disk init-done marker (plugin-lane-ONLY by definition: the
# legacy lane writes only setup-confirmed, never init-done — see
# init-state.sh). The marker arm keeps the #1026 lesson honored: a post-init
# consumer whose script env lacks the var still classifies as plugin. We
# still deliberately do NOT key on the lib's own BASH_SOURCE — that would
# false-classify legacy/none as plugin whenever the lib is sourced from the
# dev tree.
# ───────────────────────────────────────────────────────────────────────────
vi_detect_lane() {
  local proj="$1"
  local plugin_sig=0 legacy_sig=0

  # Plugin signal (Phase 6b): env context, or the plugin-lane init lock
  # (path + predicate from init-state.sh — never re-typed).
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    plugin_sig=1
  elif command -v zskills_init_done_present >/dev/null 2>&1 \
       && zskills_init_done_present "$proj"; then
    plugin_sig=1
  fi

  # Legacy signal: ZSKILLS-OWNED evidence only (matches detect-install-state.sh,
  # #1064/#1067). Either a zskills-named .claude/skills/<name>/SKILL.md mirror
  # OR a settings.json registering a hook under .claude/hooks/ is sufficient.
  # We key on zskills-OWNED content (not bare file existence) so a plugin
  # consumer's OWN non-zskills skills/settings never false-classify the install
  # as legacy/dual (the bug this fix closes).
  if vi_has_zskills_mirror "$proj" \
     || vi_settings_has_zskills_hook "$proj/.claude/settings.json"; then
    legacy_sig=1
  fi

  if [ "$plugin_sig" -eq 1 ] && [ "$legacy_sig" -eq 1 ]; then
    echo dual
  elif [ "$plugin_sig" -eq 1 ]; then
    echo plugin
  elif [ "$legacy_sig" -eq 1 ]; then
    echo legacy
  else
    echo none
  fi
}

# ───────────────────────────────────────────────────────────────────────────
# Small helpers.
# ───────────────────────────────────────────────────────────────────────────

# vi_config_version <config_path> → prints zskills_version field (empty if
# absent/unreadable). Pure Python JSON read (no jq).
vi_config_version() {
  local cfg="$1"
  [ -f "$cfg" ] || { echo ""; return 0; }
  [ -n "$VI_PY" ] || { echo ""; return 0; }
  "$VI_PY" - "$cfg" <<'PY' 2>/dev/null || echo ""
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print(d.get("zskills_version", "") or "")
except Exception:
    print("")
PY
}

# vi_settings_hook_commands <settings_json> → prints each registered hook
# command (one per line) across PreToolUse/PostToolUse/SessionStart/Stop/etc.
# Pure Python JSON read.
vi_settings_hook_commands() {
  local settings="$1"
  [ -f "$settings" ] || return 0
  [ -n "$VI_PY" ] || return 0
  "$VI_PY" - "$settings" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
for event, blocks in d.get("hooks", {}).items():
    if not isinstance(blocks, list):
        continue
    for block in blocks:
        for h in block.get("hooks", []):
            cmd = h.get("command", "")
            if cmd:
                print(cmd)
PY
}

# vi_resolve_hook_path <project_dir> <command> → prints the on-disk path the
# command references, or empty if the command shape is unrecognised. Handles
# the canonical form  bash "$CLAUDE_PROJECT_DIR/.claude/hooks/<base>"  and the
# plugin form  bash "${CLAUDE_PLUGIN_ROOT}/hooks/<base>" .  Only the file path
# is extracted (the last quoted token, or the last whitespace token).
vi_resolve_hook_path() {
  local proj="$1" cmd="$2" path=""
  # Extract the path token: prefer a quoted "...path..." substring.
  if [[ "$cmd" =~ \"([^\"]+)\" ]]; then
    path="${BASH_REMATCH[1]}"
  else
    # Fall back to the last whitespace-separated token.
    path="${cmd##* }"
  fi
  # Expand the two env vars the registration uses.
  path="${path//\$\{CLAUDE_PROJECT_DIR\}/$proj}"
  path="${path//\$CLAUDE_PROJECT_DIR/$proj}"
  path="${path//\$\{CLAUDE_PLUGIN_ROOT\}/${CLAUDE_PLUGIN_ROOT:-}}"
  path="${path//\$CLAUDE_PLUGIN_ROOT/${CLAUDE_PLUGIN_ROOT:-}}"
  printf '%s\n' "$path"
}

# vi_is_zskills_hook <basename> → 0 if <basename> is a zskills-OWNED hook
# (one of the canonical settings.json-owned triples in update-zskills/SKILL.md,
# plus the non-registered-but-shipped inject-bash-timeout.sh). Used to scope the integrity
# checks (non-empty + line-2 version stamp) to zskills' OWN hooks — a foreign
# (consumer-supplied) hook registered alongside zskills ones legitimately does
# NOT carry the `# zskills-hook-version:` stamp, so blanket-checking every
# registered hook would false-FAIL a valid install with foreign hooks.
vi_is_zskills_hook() {
  case "$1" in
    block-unsafe-generic.sh|block-unsafe-project.sh|block-stale-skill-version.sh|\
    block-bypassed-land-pr.sh|block-fix-issue-unclaimed.sh|block-run-plan-unclaimed.sh|\
    block-agents.sh|block-bad-cron.sh|block-main-edits.sh|warn-config-drift.sh|\
    inject-bash-timeout.sh)
      return 0 ;;
    *) return 1 ;;
  esac
}

# vi_hook_has_version_stamp <path> → 0 if line 2 of the hook carries the
# `# zskills-hook-version:` sentinel (the convention CLAUDE.md documents and
# tests/test-skill-conformance.sh gates). 1 otherwise.
vi_hook_has_version_stamp() {
  local f="$1"
  [ -f "$f" ] || return 1
  sed -n '2p' "$f" 2>/dev/null | grep -Eq '^#[[:space:]]*zskills-hook-version:[[:space:]]'
}

# vi_has_zskills_mirror <project_dir> → 0 if .claude/skills/<name>/SKILL.md
# exists for at least one ZSKILLS-OWNED <name>. This scopes the "legacy mirror
# present" signal to ZSKILLS' OWN skills, so a plugin consumer who ships their
# OWN, non-zskills skills (e.g. playwright-cli, social-seo) is NOT misclassified
# as carrying a legacy mirror (the #1064 bug class, fixed in
# hooks/_lib/detect-install-state.sh by #1067 — that fix never reached this
# self-contained lib).
#
# The anchor set below is kept BYTE-IDENTICAL to detect-install-state.sh's
# `_dis_zskills_skills` list (#1067). It is staleness-tolerant: a real legacy
# mirror ALWAYS carries `update-zskills` (the installer) plus the stable core,
# so a future new skill not yet in this list never breaks lane detection — the
# mirror still carries the anchors. Derived from the repo's `skills/` directory
# names. Kept INLINE: this lib must stay
# standalone (it deliberately does NOT source detect-install-state.sh, which is
# not mirrored to a legacy consumer).
vi_has_zskills_mirror() {
  local proj="$1"
  local zskills_skills="briefing cleanup-merged commit create-worktree do draft-plan draft-tests fix-issues fix-report investigate land-pr manual-testing plans qe-audit refine-plan research-and-go research-and-plan run-plan session-report update-zskills verify-changes work-on-plans zskills-dashboard"
  local name
  for name in $zskills_skills; do
    if [ -f "$proj/.claude/skills/$name/SKILL.md" ]; then
      return 0
    fi
  done
  return 1
}

# vi_settings_has_zskills_hook <settings_json> → 0 if settings.json registers at
# least one hook command whose resolved path-token lives UNDER .claude/hooks/.
# This scopes the "legacy settings.json" signal to ZSKILLS-owned hook
# registrations: a consumer's OWN, non-zskills hook (or an empty `{}`) does NOT
# count, so a plugin consumer's own settings.json no longer false-classifies the
# install as legacy/dual. Mere file existence must NOT count — only a registered
# command resolving under .claude/hooks/. Mirrors the supplementary settings.json
# cross-check in detect-install-state.sh (#1067).
vi_settings_has_zskills_hook() {
  local settings="$1"
  [ -f "$settings" ] || return 1
  local cmd token
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    # Last whitespace-separated token, stripped of surrounding quotes.
    token="${cmd##* }"
    token="${token%\"}"; token="${token#\"}"
    token="${token%\'}"; token="${token#\'}"
    case "$token" in
      */.claude/hooks/*|.claude/hooks/*) return 0 ;;
    esac
  done < <(vi_settings_hook_commands "$settings")
  return 1
}

# ───────────────────────────────────────────────────────────────────────────
# LEGACY-lane cheap structural checks.
#
# vi_check_legacy <project_dir>
#   - .claude/skills/ populated
#   - every hook registered in .claude/settings.json resolves to a real file
#   - AT LEAST ONE hook is registered (zero registered hooks == de-hooked
#     install == broken; #1008 F1)
#   - the canonical safety-hook set is registered in settings.json (#1008 F1)
#   - .claude/rules/zskills/managed.md present AND rendered (no raw,
#     un-substituted {{TOKEN}} template placeholders)
#   - .claude/zskills-config.json present
#
# ZERO-FALSE-POSITIVE BAR (#1004): every FAIL here means "your install is
# genuinely broken." We do NOT flag the renderer's designed `<!-- TODO ... -->`
# comments — those are the deliberate output for UNSET OPTIONAL config
# (dev_server.cmd, ui.auth_bypass, testing.file_patterns, …; see
# scripts/managed_rules_substitution.py's `_empty_or(..., "<!-- TODO -->")`).
# Their presence PROVES managed.md rendered. We also do NOT check for a
# recorded zskills_version: /update-zskills Step F.5 SKIPS writing it when the
# source clone is untagged, so a valid install can legitimately lack it.
# ───────────────────────────────────────────────────────────────────────────
vi_check_legacy() {
  local proj="$1"
  local claude="$proj/.claude"

  # (1) .claude/skills/ populated AND each skill dir carries a SKILL.md.
  #
  # #1008 medium gap (partial mirror): a half-finished `cp -r` can leave a skill
  # DIRECTORY behind with no SKILL.md (e.g. only references/ copied). The bare
  # `ls -A >= 1` check passed such a corrupt mirror. We now require every
  # immediate subdirectory of .claude/skills/ to contain a SKILL.md — a skill
  # dir without one is genuinely broken. (We do NOT compare subdir trees against
  # a source: the verifier is self-contained and has no source to diff against,
  # and many valid skills have no subdirs at all — so SKILL.md presence is the
  # tightest assertion that can never false-FAIL a healthy install.)
  if [ ! -d "$claude/skills" ] || [ -z "$(ls -A "$claude/skills" 2>/dev/null)" ]; then
    vi_emit FAIL "legacy.skills-populated" ".claude/skills/ missing or empty"
  else
    local skilldir skill_missing="" skill_count=0
    for skilldir in "$claude/skills"/*/; do
      [ -d "$skilldir" ] || continue
      skill_count=$((skill_count + 1))
      if [ ! -f "${skilldir}SKILL.md" ]; then
        skill_missing="$skill_missing $(basename "$skilldir")"
      fi
    done
    if [ -n "$skill_missing" ]; then
      vi_emit FAIL "legacy.skills-populated" "skill dir(s) missing SKILL.md (partial mirror?):$skill_missing"
    else
      vi_emit PASS "legacy.skills-populated" ".claude/skills/ has $skill_count skill(s), each with a SKILL.md"
    fi
  fi

  # (2) settings.json present + valid JSON + every registered hook resolves.
  local settings="$claude/settings.json"
  if [ ! -f "$settings" ]; then
    vi_emit FAIL "legacy.settings-present" ".claude/settings.json missing"
  elif [ -n "$VI_PY" ] && ! "$VI_PY" -c 'import json,sys; json.load(open(sys.argv[1]))' "$settings" 2>/dev/null; then
    vi_emit FAIL "legacy.settings-valid-json" ".claude/settings.json is not valid JSON"
  else
    vi_emit PASS "legacy.settings-present" ".claude/settings.json present and valid JSON"
    local missing="" total=0 cmd hp base registered="" empty_hooks="" unstamped=""
    while IFS= read -r cmd; do
      [ -n "$cmd" ] || continue
      total=$((total + 1))
      hp="$(vi_resolve_hook_path "$proj" "$cmd")"
      if [ -z "$hp" ] || [ ! -f "$hp" ]; then
        missing="$missing ${cmd##*/}"
        continue
      fi
      # Record the resolved-path basename for the canonical-set cross-check.
      base="${hp##*/}"
      [ -n "$base" ] && registered="$registered $base "
      # #1008 medium gaps — hook INTEGRITY, scoped to zskills-owned hooks so a
      # foreign consumer hook never false-FAILs:
      #   (a) corrupted/empty (0-byte) hook — `[ -f ]` alone passes a truncated
      #       `cp`; require `[ -s ]`.
      #   (b) drifted mirror — a consumer hook predating source carries a stale
      #       (or absent) line-2 `# zskills-hook-version:` stamp.
      if vi_is_zskills_hook "$base"; then
        [ -s "$hp" ] || empty_hooks="$empty_hooks $base"
        vi_hook_has_version_stamp "$hp" || unstamped="$unstamped $base"
      fi
    done < <(vi_settings_hook_commands "$settings")

    # (2a) ZERO registered hooks → a de-hooked install (#1008 F1). Every zskills
    # safety hook (block-unsafe-*, block-stale-skill-version, block-agents, …)
    # has been stripped from settings.json — the verifier exists to catch exactly
    # this "install silently failed" case, so a count of 0 is a FAIL, not a PASS.
    if [ "$total" -eq 0 ]; then
      vi_emit FAIL "legacy.hooks-resolve" "no hooks registered in settings.json — a de-hooked install (every zskills safety hook stripped) is broken"
    elif [ -n "$missing" ]; then
      vi_emit FAIL "legacy.hooks-resolve" "unresolved hook script(s):$missing"
    else
      vi_emit PASS "legacy.hooks-resolve" "all $total registered hook commands resolve to existing files"
    fi

    # (2b) Canonical safety-hook set (#1008 F1). Even with a NON-zero hook count,
    # an install missing the core safety hooks is broken. We require the minimal
    # set of settings.json-registered safety hooks that a HEALTHY legacy install
    # ALWAYS registers (per the canonical zskills-owned triples table in
    # update-zskills/SKILL.md). We deliberately do NOT require inject-bash-timeout.sh
    # here: SKILL.md states it has NO settings.json entry (loaded via
    # verifier.md frontmatter), so requiring it would false-FAIL every valid
    # legacy install. (verify-response-validate.sh is skill-bundled as of the
    # install redesign Phase 3 — not a hook at all, delivered via the mirror.)
    local canon canon_missing=""
    for canon in block-unsafe-generic.sh block-unsafe-project.sh block-stale-skill-version.sh block-agents.sh; do
      case "$registered" in
        *" $canon "*) : ;;
        *) canon_missing="$canon_missing $canon" ;;
      esac
    done
    if [ -n "$canon_missing" ]; then
      vi_emit FAIL "legacy.canonical-hooks" "canonical safety hook(s) not registered in settings.json:$canon_missing"
    else
      vi_emit PASS "legacy.canonical-hooks" "canonical safety hooks registered (block-unsafe-generic/project, block-stale-skill-version, block-agents)"
    fi

    # (2c) Hook integrity (#1008 medium gaps) — scoped to zskills-owned hooks.
    # Only meaningful when at least one zskills hook resolved (skipped on the
    # zero/all-unresolved case, already FAILed above).
    if [ -n "$empty_hooks" ]; then
      vi_emit FAIL "legacy.hooks-integrity" "zskills hook(s) are 0-byte/truncated (corrupt mirror):$empty_hooks"
    elif [ -n "$unstamped" ]; then
      vi_emit FAIL "legacy.hooks-integrity" "zskills hook(s) missing line-2 # zskills-hook-version: stamp (drifted/corrupt mirror):$unstamped"
    elif [ -n "$registered" ]; then
      vi_emit PASS "legacy.hooks-integrity" "all registered zskills hooks are non-empty and version-stamped"
    fi
  fi

  # (3) managed.md present AND rendered.
  #
  # A MISSING file is a real failure. But its mere presence does NOT prove it
  # rendered: a copied-but-never-rendered CLAUDE_TEMPLATE.md would still carry
  # raw `{{TOKEN}}` placeholders. So we flag ONLY raw, un-substituted template
  # tokens — the unambiguous signature of "the renderer never ran." We do NOT
  # flag `<!-- TODO ... -->` comments: those are the renderer's DESIGNED output
  # for unset OPTIONAL config and their presence proves the render happened
  # (scripts/render-managed-rules.py / managed_rules_substitution.py.apply()
  # even RAISES if any `{{...}}` survives, so a real render can never leave one
  # — making a surviving token a definitive "not rendered" signal).
  local mm="$claude/rules/zskills/managed.md"
  if [ ! -f "$mm" ]; then
    vi_emit FAIL "legacy.managed-present" ".claude/rules/zskills/managed.md missing"
  elif grep -qE '\{\{[A-Z_]+\}\}' "$mm"; then
    vi_emit FAIL "legacy.managed-rendered" "managed.md contains un-substituted {{TOKEN}} template placeholder(s) — renderer did not run"
  else
    vi_emit PASS "legacy.managed-rendered" "managed.md present and rendered (no un-substituted {{TOKEN}} placeholders)"
  fi

  # (4) zskills-config.json present.
  local cfg="$claude/zskills-config.json"
  if [ -f "$cfg" ]; then
    vi_emit PASS "legacy.config-present" ".claude/zskills-config.json present"
  else
    vi_emit FAIL "legacy.config-present" ".claude/zskills-config.json missing"
  fi

  # (5) zskills_version recorded (#1124 — WARN, never FAIL). After #1124
  # resolve-repo-version.sh falls back to .claude-plugin/plugin.json, so a
  # complete clone almost always yields a version and /update-zskills writes
  # zskills_version. Its absence is therefore abnormal — but a missing version
  # is still NOT install breakage (the skills/hooks all work without it; only
  # the version-skew nudge is affected). So we WARN (the carve-out rationale
  # from #1004 — "an untagged source clone legitimately lacks one" — no longer
  # holds now that the plugin.json fallback exists), and report the value when
  # present. WARN keeps the zero-false-positive bar on FAILs intact.
  local cver
  cver="$(vi_config_version "$cfg")"
  if [ -n "$cver" ]; then
    vi_emit PASS "legacy.version-recorded" "zskills_version recorded: $cver"
  else
    vi_emit WARN "legacy.version-recorded" "zskills_version absent in .claude/zskills-config.json — after #1124 a complete clone resolves a version (git tag → .claude-plugin/plugin.json); re-run /update-zskills to record it (version-skew nudge stays disabled until then)"
  fi
}

# ───────────────────────────────────────────────────────────────────────────
# PLUGIN-lane cheap structural checks (INSTALL_REDESIGN Phase 6b — re-keyed
# from the dying materialiser sentinels onto the explicit-init state; this is
# the redesign's own acceptance vehicle AND init's A6 hard gate).
#
# vi_check_plugin <project_dir>
#   - plugin root reachable (manifests + skills tree resolvable)
#   - `.zskills/init-done` + `.zskills/setup-confirmed` present (paths +
#     predicate via init-state.sh — #1132 single path definition)
#   - `.gitignore` umbrella covers `.zskills/` (git check-ignore)
#   - `.claude/zskills-config.json` VALID-if-present (absent is OK BY DESIGN
#     — zero-config consumers run on built-in defaults)
#   - rules delivered per the selected R-b branch (the SessionStart
#     `session-rules-context.sh` hook registered in the plugin's hooks.json,
#     its script present, and the render inputs — CLAUDE_TEMPLATE.md + the
#     D24 renderer — present, i.e. renderable)
#   - version-currency WARN (m-class staleness cure): init-done's `version:`
#     line vs the plugin manifest's `version`; a config-less consumer's
#     version record is otherwise permanently stale after marketplace
#     updates — the cure is a bare /zs:update-zskills (the A1 update arm
#     refreshes the line)
#   - branch-dependent artifacts: NONE on the landed 1A + T-A branches
#     (agents dispatch from the plugin's root agents/; Layer-0 ships via
#     hooks.json — no project-side artifact to check; the unselected 1B/T-C
#     checks live in the plan, not in shipped code)
#
# ZERO-FALSE-POSITIVE BAR (#1004): every FAIL means "your install is
# genuinely broken / not initialised". Config absence, version skew, and a
# residual mirror are PASS/WARN — never FAIL.
# ───────────────────────────────────────────────────────────────────────────
vi_check_plugin() {
  local proj="$1"
  local claude="$proj/.claude"

  # (0) init-state.sh loaded (the #1132 single path definition). Without it
  # the init-keyed checks below cannot run — that is itself a broken tree
  # (the scripts/ dir ships beside this verifiers/ dir on both lanes).
  if ! command -v zskills_init_done_present >/dev/null 2>&1; then
    vi_emit FAIL "plugin.init-state-lib" "init-state.sh not loadable from the skill's scripts/ dir — broken zskills tree"
    return 0
  fi

  # (1) Plugin root reachable (#1008 medium gap). The live skills/hooks
  # resolve under the plugin root; a root pointing at a deleted/empty dir
  # means ZERO functional skills no matter how healthy the project side is.
  # Prefer ${CLAUDE_PLUGIN_ROOT}; fall back to env-independent self-location
  # from this lib's own BASH_SOURCE (this lib ships at
  # <plugin-root>/skills/update-zskills/verifiers/, so dirname/../../.. ==
  # <plugin-root>). F2 (#1026): the env var is ABSENT from a launched/sourced
  # script's env on a real mirror-less plugin consumer, so an "empty → FAIL"
  # path would false-FAIL a healthy install.
  local proot="${CLAUDE_PLUGIN_ROOT:-}"
  if [ -z "$proot" ]; then
    proot="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../.." 2>/dev/null && pwd)"
  fi
  local pmissing=""
  if [ -z "$proot" ]; then
    vi_emit FAIL "plugin.root-reachable" "\${CLAUDE_PLUGIN_ROOT} unset and plugin root unresolvable from BASH_SOURCE"
  else
    [ -f "$proot/.claude-plugin/plugin.json" ]         || pmissing="$pmissing .claude-plugin/plugin.json"
    [ -f "$proot/hooks/hooks.json" ]                   || pmissing="$pmissing hooks/hooks.json"
    [ -f "$proot/skills/update-zskills/SKILL.md" ]     || pmissing="$pmissing skills/update-zskills/SKILL.md"
    if [ -n "$pmissing" ]; then
      vi_emit FAIL "plugin.root-reachable" "plugin root $proot missing required file(s):$pmissing"
    else
      vi_emit PASS "plugin.root-reachable" "plugin root resolves (manifests + skills tree present)"
    fi
  fi

  # (2) Init markers (lock-LAST pair). init-done is THE initialised signal —
  # absent (or 0-byte partial, per the predicate) means the one-time setup
  # has not completed; the gate blocks state-writing skills until it has.
  #
  # PRE-LOCK allowance (ZSKILLS_VI_PRE_LOCK=1 — Phase 6b A6 hard gate): when
  # the init flow itself invokes this verifier at step A6, the markers are
  # EXPECTED to be absent BY DESIGN (A7 writes them LAST, after A6 passes —
  # the #394 lock-LAST contract). The init fence sets the env knob so these
  # two checks report the expected-absent state as PASS-pending instead of
  # FAIL; every OTHER check still gates at full strength (the knob suppresses
  # NOTHING else — asserted by the dev suite's anti-hollow cases). Outside
  # init (the knob unset), absent markers are a genuine FAIL.
  if zskills_init_done_present "$proj"; then
    vi_emit PASS "plugin.init-done" "$ZSKILLS_INIT_DONE_REL present (explicit init completed)"
  elif [ "${ZSKILLS_VI_PRE_LOCK:-0}" = 1 ]; then
    vi_emit PASS "plugin.init-done" "pre-lock invocation (init A6): $ZSKILLS_INIT_DONE_REL expected absent — written at A7 (lock-LAST)"
  else
    vi_emit FAIL "plugin.init-done" "$ZSKILLS_INIT_DONE_REL missing — one-time setup has not run; run /zs:update-zskills"
  fi
  if [ -s "$proj/$ZSKILLS_SETUP_CONFIRMED_REL" ]; then
    vi_emit PASS "plugin.setup-confirmed" "$ZSKILLS_SETUP_CONFIRMED_REL present"
  elif [ "${ZSKILLS_VI_PRE_LOCK:-0}" = 1 ]; then
    vi_emit PASS "plugin.setup-confirmed" "pre-lock invocation (init A6): $ZSKILLS_SETUP_CONFIRMED_REL expected absent — written at A7 (lock-LAST)"
  else
    vi_emit FAIL "plugin.setup-confirmed" "$ZSKILLS_SETUP_CONFIRMED_REL missing — run /zs:update-zskills"
  fi

  # (3) Gitignore umbrella effectiveness — the gitignore-first init step's
  # standing guarantee. check-ignore needs only a PATHNAME, not a file, and
  # also fails (rc!=0) outside a git work tree — which init itself STOPs on.
  if git -C "$proj" check-ignore -q .zskills/probe 2>/dev/null; then
    vi_emit PASS "plugin.gitignore-umbrella" ".zskills/ paths are git-ignored (umbrella entry effective)"
  else
    vi_emit FAIL "plugin.gitignore-umbrella" ".zskills/ is NOT effectively git-ignored (missing umbrella entry, a negative override, or not a git repo) — re-run /zs:update-zskills after fixing .gitignore"
  fi

  # (4) Config VALID-if-present. Zero-config is the designed default (the
  # cascade supplies built-ins), so ABSENT is a PASS. Present-but-unparsable
  # (or not a JSON object) silently breaks every config reader → FAIL.
  local cfg="$claude/zskills-config.json"
  if [ ! -f "$cfg" ]; then
    vi_emit PASS "plugin.config-valid" "no .claude/zskills-config.json — zero-config by design (built-in defaults apply)"
  elif [ -n "$VI_PY" ] \
       && "$VI_PY" -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if isinstance(d, dict) else 1)' "$cfg" 2>/dev/null; then
    vi_emit PASS "plugin.config-valid" ".claude/zskills-config.json present and valid JSON"
  elif [ -z "$VI_PY" ]; then
    vi_emit WARN "plugin.config-valid" "config present but no Python 3 to validate it (env.python already FAILed)"
  else
    vi_emit FAIL "plugin.config-valid" ".claude/zskills-config.json is not a valid JSON object — fix or remove it (absent = built-in defaults)"
  fi

  # (5) Rules delivery (selected branch R-b): the SessionStart
  # session-rules-context.sh hook must be registered in the plugin's
  # hooks.json, its script present, and the render inputs present (the D24
  # renderer + the de-parameterized template) — i.e. the rules are
  # deliverable/renderable every session. Only meaningful when the root
  # resolved; otherwise (1) already FAILed.
  if [ -n "$proot" ]; then
    local rmissing=""
    if [ -f "$proot/hooks/hooks.json" ] \
       && grep -q 'session-rules-context\.sh' "$proot/hooks/hooks.json" 2>/dev/null; then
      :
    else
      rmissing="$rmissing hooks.json-registration"
    fi
    [ -s "$proot/hooks/session-rules-context.sh" ]   || rmissing="$rmissing hooks/session-rules-context.sh"
    [ -f "$proot/CLAUDE_TEMPLATE.md" ]               || rmissing="$rmissing CLAUDE_TEMPLATE.md"
    [ -f "$proot/scripts/render-managed-rules.py" ]  || rmissing="$rmissing scripts/render-managed-rules.py"
    if [ -n "$rmissing" ]; then
      vi_emit FAIL "plugin.rules-delivery" "R-b rules delivery broken — missing:$rmissing"
    else
      vi_emit PASS "plugin.rules-delivery" "R-b rules delivery in place (SessionStart hook registered + renderable)"
    fi
  fi

  # (6) Version currency (WARN, never FAIL — m-class staleness cure). The
  # init-done `version:` line is the version record for config-less
  # consumers; nothing re-runs init after a marketplace update, so it goes
  # stale silently. Compare against the loaded plugin manifest's version.
  if [ -n "$proot" ] && [ -f "$proot/.claude-plugin/plugin.json" ] \
     && zskills_init_done_present "$proj"; then
    local rec_ver plug_ver
    rec_ver="$(sed -n 's/^version:[[:space:]]*//p' "$proj/$ZSKILLS_INIT_DONE_REL" | head -1)"
    plug_ver=""
    if [ -n "$VI_PY" ]; then
      plug_ver="$("$VI_PY" -c 'import json,sys; print(json.load(open(sys.argv[1])).get("version","") or "")' "$proot/.claude-plugin/plugin.json" 2>/dev/null)"
    fi
    if [ -z "$rec_ver" ] || [ -z "$plug_ver" ]; then
      vi_emit WARN "plugin.version-currency" "version record incomparable (init-done: '${rec_ver:-none}', plugin.json: '${plug_ver:-none}') — run a bare /zs:update-zskills to refresh"
    elif [ "$rec_ver" = "$plug_ver" ]; then
      vi_emit PASS "plugin.version-currency" "init-done version matches the loaded plugin ($rec_ver)"
    else
      vi_emit WARN "plugin.version-currency" "init-done records $rec_ver but the loaded plugin is $plug_ver — run a bare /zs:update-zskills to refresh the record"
    fi
  fi

  # (7) Residual zskills mirror (WARN). A zskills-owned mirror beside the
  # plugin lane normally collapses to `dual` upstream in vi_detect_lane; this
  # WARN is the defensive direct-call surface. The cure under the redesign is
  # uninstall-one-install-the-other: keep the plugin lane by deleting the
  # .claude/skills/ zskills mirror (+ its settings.json hook registrations),
  # or keep the legacy lane by uninstalling the plugin. (The retired
  # lane-switch script must NOT be recommended.)
  if vi_has_zskills_mirror "$proj"; then
    vi_emit WARN "plugin.mirror-less" "zskills mirror present under .claude/skills/ on the plugin lane — uninstall one lane (remove the mirror, or uninstall the plugin); dual install is unsupported"
  else
    vi_emit PASS "plugin.mirror-less" "no zskills mirror under .claude/skills/ (mirror-less plugin install)"
  fi
}

# ───────────────────────────────────────────────────────────────────────────
# Environment checks (lane-agnostic — #1119).
#
# vi_check_env <project_dir> — REPORT (never gate) the host tooling a zskills
# consumer needs. Runs unconditionally at the top of vi_run_cheap, regardless
# of detected lane, so a fresh casual plugin consumer learns their environment
# is missing git/gh BEFORE the lane-specific structural checks.
#
#   git binary present  → FAIL if absent (zskills' worktree/commit/cherry-pick
#                         machinery is unusable without git).
#   git repo            → WARN (+ "run git init") if $proj is not a git work
#                         tree. Reported with `git -C "$proj" rev-parse` so the
#                         check is anchored to the project dir, not cwd.
#   gh present          → WARN if absent (PR-mode landing + /fix-issues need it,
#                         but cherry-pick/direct lanes work without it).
#   python              → already covered (VI_PY / the resolver). A missing
#                         interpreter would have FAILed earlier checks; we
#                         report it here too for a complete env picture.
# ───────────────────────────────────────────────────────────────────────────
vi_check_env() {
  local proj="$1"

  # git binary.
  if command -v git >/dev/null 2>&1; then
    vi_emit PASS "env.git-binary" "git is installed"
  else
    vi_emit FAIL "env.git-binary" "git not found on PATH — zskills needs git (worktrees, commits, cherry-picks). Install git."
  fi

  # git repo (project dir is a work tree). Only meaningful when git exists;
  # use git -C "$proj" so the check is anchored to the project, not cwd.
  if command -v git >/dev/null 2>&1; then
    if git -C "$proj" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      vi_emit PASS "env.git-repo" "$proj is a git repository"
    else
      vi_emit WARN "env.git-repo" "$proj is not a git repository — run 'git init' here so zskills' commit/worktree machinery works"
    fi
  fi

  # gh CLI.
  if command -v gh >/dev/null 2>&1; then
    vi_emit PASS "env.gh" "gh (GitHub CLI) is installed"
  else
    vi_emit WARN "env.gh" "gh (GitHub CLI) not found — PR-mode landing and /fix-issues need it; cherry-pick/direct lanes do not"
  fi

  # python (already resolved into VI_PY by the resolver at load time).
  if [ -n "$VI_PY" ]; then
    vi_emit PASS "env.python" "Python 3 resolved ($VI_PY)"
  else
    vi_emit FAIL "env.python" "no working Python 3 found — zskills hooks/scripts need it (set ZSKILLS_PYTHON)"
  fi
}

# ───────────────────────────────────────────────────────────────────────────
# Dispatch by detected lane.
#
# vi_run_cheap <project_dir> — detect the lane and run the cheap structural
# tier for it. Emits per-check records and leaves VI_PASS/WARN/FAIL populated.
# A `dual` lane is flagged FAIL (unsupported client state) but still runs the
# legacy checks so the consumer sees the full picture. `none` is a FAIL.
#
# vi_check_env runs FIRST, unconditionally (lane-agnostic), so the host-tooling
# report (git/gh/python) is always present regardless of detected lane (#1119).
# ───────────────────────────────────────────────────────────────────────────
vi_run_cheap() {
  local proj="$1"

  # Lane-agnostic environment report (#1119) — always runs first.
  vi_check_env "$proj"

  local lane
  lane="$(vi_detect_lane "$proj")"
  vi_emit "$([ "$lane" = none ] && echo FAIL || echo PASS)" "lane.detect" "detected lane: $lane"

  case "$lane" in
    plugin)
      vi_check_plugin "$proj"
      ;;
    legacy)
      vi_check_legacy "$proj"
      ;;
    dual)
      vi_emit FAIL "lane.dual-unsupported" "dual install (plugin + legacy mirror) is NOT a supported client state — run scripts/switch-install-path.sh"
      vi_check_legacy "$proj"
      ;;
    none)
      vi_emit FAIL "lane.none" "no zskills install detected (no plugin env/init-done marker, no zskills mirror + no zskills settings.json hooks)"
      ;;
  esac
}

# ───────────────────────────────────────────────────────────────────────────
# Heavy tier (opt-in — NOT on the auto-run-at-success path).
#
# vi_run_heavy <project_dir> — a live `claude` hook-fire / `/zs:` dispatch
# probe. Intentionally a stub: it must NEVER run as part of /update-zskills
# success. Implemented minimally so the opt-in path exists and is testable
# without spawning a real `claude`. When `claude` is unavailable it WARNs
# rather than FAILs (the live probe is informative, never a gate).
# ───────────────────────────────────────────────────────────────────────────
vi_run_heavy() {
  local proj="$1"
  if ! command -v claude >/dev/null 2>&1; then
    vi_emit WARN "heavy.claude-available" "claude CLI not found — skipping live probe (heavy tier is opt-in only)"
    return 0
  fi
  # A real live probe would dispatch a no-op /zs: command or trigger a hook
  # fire and assert the expected sentinel/output. Kept minimal here; the
  # important contract is that this is OPT-IN and never runs at success.
  vi_emit WARN "heavy.live-probe" "live probe stub — implement a /zs: dispatch or hook-fire assertion as needed"
  return 0
}
