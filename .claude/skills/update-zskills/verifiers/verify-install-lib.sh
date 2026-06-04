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

# Resolve the Python interpreter once (project convention: python3, fall back
# to python; ZSKILLS_PYTHON overrides). Used for JSON round-tripping.
VI_PY="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python || true)}"

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
# Lane detection (self-contained — no dependency on detect-install-state.sh).
#
# vi_detect_lane <project_dir> → prints one of: plugin | legacy | dual | none
#
#   materialised sentinels present in $proj/.claude → plugin signal present
#   .claude/skills/ AND .claude/settings.json present → legacy signal present
#   both signals                         → dual (UNSUPPORTED — flagged)
#   neither                              → none (no install detected)
#
# F2 (#1026): the plugin signal is keyed on the CONSUMER project dir's on-disk
# MATERIALISED SENTINELS — the 5 artifacts the plugin SessionStart materialiser
# writes into $proj/.claude (each carrying a `zskills-materialised:` sentinel) —
# NOT on the ${CLAUDE_PLUGIN_ROOT} environment variable. On a real mirror-less
# plugin consumer the verifier runs as a launched/sourced script whose env does
# NOT carry CLAUDE_PLUGIN_ROOT (the harness substitutes only the bare token in
# markdown; it is absent from the script env), so keying on it false-classified
# a working plugin install as `none` (the #1026 `lane=none` false-FAIL). Lane is
# a property of the CONSUMER dir, not of the env var and NOT of where this lib
# happens to live (we deliberately do NOT key on the lib's own BASH_SOURCE —
# that would false-classify legacy/none as plugin whenever the lib is sourced
# from the dev tree / an env-unset run, breaking the legacy regression cases).
# ───────────────────────────────────────────────────────────────────────────
vi_detect_lane() {
  local proj="$1"
  local plugin_sig=0 legacy_sig=0

  # Plugin signal: at least one of the 5 materialised artifacts present in the
  # consumer dir carrying a `zskills-materialised:` sentinel. Reuses the exact
  # sentinel detection (vi_has_materialiser_sentinel) the plugin-lane checks use.
  local art
  for art in \
    "agents/verifier.md" \
    "agents/implementer.md" \
    "hooks/inject-bash-timeout.sh" \
    "hooks/verify-response-validate.sh" \
    "rules/zskills/managed.md"; do
    if vi_has_materialiser_sentinel "$proj/.claude/$art"; then
      plugin_sig=1
      break
    fi
  done

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

# vi_has_materialiser_sentinel <file> → 0 if the file carries a
# `zskills-materialised:` sentinel in its first 3 lines (the exact detection
# session-start-materialise.sh uses for its overwrite guard). 1 otherwise.
vi_has_materialiser_sentinel() {
  local f="$1"
  [ -f "$f" ] || return 1
  head -n 3 "$f" 2>/dev/null \
    | grep -Eq "^(#|<!--)[[:space:]]+zskills-materialised:[[:space:]]"
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
# plus the two non-registered-but-shipped hooks). Used to scope the integrity
# checks (non-empty + line-2 version stamp) to zskills' OWN hooks — a foreign
# (consumer-supplied) hook registered alongside zskills ones legitimately does
# NOT carry the `# zskills-hook-version:` stamp, so blanket-checking every
# registered hook would false-FAIL a valid install with foreign hooks.
vi_is_zskills_hook() {
  case "$1" in
    block-unsafe-generic.sh|block-unsafe-project.sh|block-stale-skill-version.sh|\
    block-bypassed-land-pr.sh|block-fix-issue-unclaimed.sh|block-run-plan-unclaimed.sh|\
    block-agents.sh|block-bad-cron.sh|block-main-edits.sh|warn-config-drift.sh|\
    inject-bash-timeout.sh|verify-response-validate.sh)
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
# names (excludes block-diagram add-ons). Kept INLINE: this lib must stay
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
    # or verify-response-validate.sh here: SKILL.md states those have NO
    # settings.json entry (loaded via verifier.md frontmatter / direct skill
    # invocation), so requiring them would false-FAIL every valid legacy install.
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

  # NOTE (#1004): no `legacy.version-recorded` check. A missing zskills_version
  # is NOT install breakage — /update-zskills Step F.5 deliberately skips
  # writing it when the source clone is untagged, so a valid install can
  # legitimately lack it. Flagging it (even as a WARN) violated the
  # zero-false-positive bar.
}

# ───────────────────────────────────────────────────────────────────────────
# PLUGIN-lane cheap structural checks.
#
# vi_check_plugin <project_dir>
#   - the 5 materialised artifacts present, each carrying a
#     `zskills-materialised:` sentinel:
#       .claude/agents/verifier.md
#       .claude/agents/implementer.md
#       .claude/hooks/inject-bash-timeout.sh
#       .claude/hooks/verify-response-validate.sh
#       .claude/rules/zskills/managed.md
#   - mirror-less (.claude/skills/ ABSENT in the consumer project)
#
# ZERO-FALSE-POSITIVE BAR (#1004): no `plugin.version-recorded` check — the
# plugin seed config can legitimately have no tag on a valid install, so its
# absence is not breakage (mirrors the legacy-lane decision above).
# ───────────────────────────────────────────────────────────────────────────
vi_check_plugin() {
  local proj="$1"
  local claude="$proj/.claude"

  # (1) The 5 materialised artifacts, each with a materialiser sentinel.
  local -a artifacts=(
    "agents/verifier.md"
    "agents/implementer.md"
    "hooks/inject-bash-timeout.sh"
    "hooks/verify-response-validate.sh"
    "rules/zskills/managed.md"
  )
  local a dest
  for a in "${artifacts[@]}"; do
    dest="$claude/$a"
    if [ ! -f "$dest" ]; then
      vi_emit FAIL "plugin.artifact.$a" "materialised artifact missing: .claude/$a"
    elif ! vi_has_materialiser_sentinel "$dest"; then
      vi_emit FAIL "plugin.artifact.$a" ".claude/$a present but missing zskills-materialised: sentinel"
    else
      vi_emit PASS "plugin.artifact.$a" ".claude/$a present with materialiser sentinel"
    fi
  done

  # (2) Mirror-less: NO ZSKILLS mirror under .claude/skills/ in a clean plugin
  # consumer. We key on a ZSKILLS-OWNED mirror (vi_has_zskills_mirror), NOT on
  # the bare presence of .claude/skills/: a plugin consumer who ships their OWN,
  # non-zskills skills (playwright-cli, social-seo, …) is a perfectly healthy
  # mirror-less install and must PASS, not WARN (the #1064 bug class). A genuine
  # zskills mirror present alongside the plugin lane is the `dual` lane upstream
  # (vi_detect_lane); this WARN is reached only when a zskills mirror exists but
  # the plugin-sig also fired in a way that did not collapse to dual — a real
  # residue worth surfacing.
  if vi_has_zskills_mirror "$proj"; then
    vi_emit WARN "plugin.mirror-less" "zskills mirror present under .claude/skills/ on the plugin lane (dual-install? run scripts/switch-install-path.sh)"
  else
    vi_emit PASS "plugin.mirror-less" "no zskills mirror under .claude/skills/ (mirror-less plugin install)"
  fi

  # (3) ${CLAUDE_PLUGIN_ROOT} reachability (#1008 medium gap). The materialised
  # artifacts above live in the CONSUMER's .claude/, but the live skills/hooks
  # resolve under ${CLAUDE_PLUGIN_ROOT}. A CLAUDE_PLUGIN_ROOT pointing at a
  # deleted/empty dir → the plugin "passes" the artifact checks yet has ZERO
  # functional skills. Assert the two manifests a loaded plugin always carries.
  # Reached only on the plugin lane (vi_detect_lane returned `plugin`, which
  # requires CLAUDE_PLUGIN_ROOT set), so a healthy plugin install always has
  # these — never a false positive.
  # Resolve the plugin root. Prefer ${CLAUDE_PLUGIN_ROOT} when the env carries
  # it; otherwise fall back to env-independent self-location from this lib's own
  # BASH_SOURCE (this lib ships at <plugin-root>/skills/update-zskills/verifiers/,
  # so dirname/../../.. == <plugin-root>). F2 (#1026): the env var is ABSENT from
  # a launched/sourced script's env on a real mirror-less plugin consumer, so the
  # old "empty → FAIL" path false-FAILed a healthy install. This BASH_SOURCE
  # fallback is consumed ONLY here, and vi_check_plugin is dispatched ONLY after
  # vi_detect_lane established lane==plugin from the consumer's materialised
  # sentinels — so it is never reached off the plugin lane.
  local proot="${CLAUDE_PLUGIN_ROOT:-}"
  if [ -z "$proot" ]; then
    proot="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../.." 2>/dev/null && pwd)"
  fi
  local pmissing=""
  if [ -z "$proot" ]; then
    # Defensive: lane==plugin is established AND a BASH_SOURCE fallback exists,
    # so an empty value here means neither resolved — genuinely broken.
    vi_emit FAIL "plugin.root-reachable" "\${CLAUDE_PLUGIN_ROOT} unset and plugin root unresolvable from BASH_SOURCE"
  else
    [ -f "$proot/.claude-plugin/plugin.json" ] || pmissing="$pmissing .claude-plugin/plugin.json"
    [ -f "$proot/hooks/hooks.json" ]           || pmissing="$pmissing hooks/hooks.json"
    if [ -n "$pmissing" ]; then
      vi_emit FAIL "plugin.root-reachable" "\${CLAUDE_PLUGIN_ROOT}=$proot missing required plugin file(s):$pmissing"
    else
      vi_emit PASS "plugin.root-reachable" "\${CLAUDE_PLUGIN_ROOT} resolves (.claude-plugin/plugin.json + hooks/hooks.json present)"
    fi
  fi

  # NOTE (#1004): no `plugin.version-recorded` check — same rationale as the
  # legacy lane: a missing zskills_version is not install breakage.
}

# ───────────────────────────────────────────────────────────────────────────
# Dispatch by detected lane.
#
# vi_run_cheap <project_dir> — detect the lane and run the cheap structural
# tier for it. Emits per-check records and leaves VI_PASS/WARN/FAIL populated.
# A `dual` lane is flagged FAIL (unsupported client state) but still runs the
# legacy checks so the consumer sees the full picture. `none` is a FAIL.
# ───────────────────────────────────────────────────────────────────────────
vi_run_cheap() {
  local proj="$1"
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
      vi_emit FAIL "lane.none" "no zskills install detected (no materialised plugin artifacts, no zskills mirror + no zskills settings.json hooks)"
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
