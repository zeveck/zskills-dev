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
#   ${CLAUDE_PLUGIN_ROOT} set            → plugin signal present
#   .claude/skills/ AND .claude/settings.json present → legacy signal present
#   both signals                         → dual (UNSUPPORTED — flagged)
#   neither                              → none (no install detected)
#
# The plugin signal is the environment variable (a loaded plugin always sets
# CLAUDE_PLUGIN_ROOT); the legacy signal is the on-disk mirror + settings.
# This is exactly the consumer-visible state, matching the issue spec.
# ───────────────────────────────────────────────────────────────────────────
vi_detect_lane() {
  local proj="$1"
  local plugin_sig=0 legacy_sig=0

  [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && plugin_sig=1

  if [ -d "$proj/.claude/skills" ] \
     && [ -n "$(ls -A "$proj/.claude/skills" 2>/dev/null)" ] \
     && [ -f "$proj/.claude/settings.json" ]; then
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

# ───────────────────────────────────────────────────────────────────────────
# LEGACY-lane cheap structural checks.
#
# vi_check_legacy <project_dir>
#   - .claude/skills/ populated
#   - every hook registered in .claude/settings.json resolves to a real file
#   - .claude/rules/zskills/managed.md rendered with NO leftover
#     <!-- TODO ... --> placeholders
#   - .claude/zskills-config.json present
#   - zskills version present (WARN if absent — informative, not fatal)
# ───────────────────────────────────────────────────────────────────────────
vi_check_legacy() {
  local proj="$1"
  local claude="$proj/.claude"

  # (1) .claude/skills/ populated.
  if [ -d "$claude/skills" ] && [ -n "$(ls -A "$claude/skills" 2>/dev/null)" ]; then
    vi_emit PASS "legacy.skills-populated" ".claude/skills/ has $(ls -1 "$claude/skills" | wc -l | tr -d ' ') entries"
  else
    vi_emit FAIL "legacy.skills-populated" ".claude/skills/ missing or empty"
  fi

  # (2) settings.json present + valid JSON + every registered hook resolves.
  local settings="$claude/settings.json"
  if [ ! -f "$settings" ]; then
    vi_emit FAIL "legacy.settings-present" ".claude/settings.json missing"
  elif [ -n "$VI_PY" ] && ! "$VI_PY" -c 'import json,sys; json.load(open(sys.argv[1]))' "$settings" 2>/dev/null; then
    vi_emit FAIL "legacy.settings-valid-json" ".claude/settings.json is not valid JSON"
  else
    vi_emit PASS "legacy.settings-present" ".claude/settings.json present and valid JSON"
    local missing="" total=0 cmd hp
    while IFS= read -r cmd; do
      [ -n "$cmd" ] || continue
      total=$((total + 1))
      hp="$(vi_resolve_hook_path "$proj" "$cmd")"
      if [ -z "$hp" ] || [ ! -f "$hp" ]; then
        missing="$missing ${cmd##*/}"
      fi
    done < <(vi_settings_hook_commands "$settings")
    if [ -z "$missing" ]; then
      vi_emit PASS "legacy.hooks-resolve" "all $total registered hook commands resolve to existing files"
    else
      vi_emit FAIL "legacy.hooks-resolve" "unresolved hook script(s):$missing"
    fi
  fi

  # (3) managed.md rendered with no leftover <!-- TODO ... --> placeholders.
  local mm="$claude/rules/zskills/managed.md"
  if [ ! -f "$mm" ]; then
    vi_emit FAIL "legacy.managed-present" ".claude/rules/zskills/managed.md missing"
  elif grep -qE '<!--[[:space:]]*TODO' "$mm"; then
    vi_emit FAIL "legacy.managed-no-placeholders" "managed.md still contains <!-- TODO ... --> placeholder(s)"
  else
    vi_emit PASS "legacy.managed-no-placeholders" "managed.md rendered with no leftover TODO placeholders"
  fi

  # (4) zskills-config.json present.
  local cfg="$claude/zskills-config.json"
  if [ -f "$cfg" ]; then
    vi_emit PASS "legacy.config-present" ".claude/zskills-config.json present"
  else
    vi_emit FAIL "legacy.config-present" ".claude/zskills-config.json missing"
  fi

  # (5) zskills version recorded (informative — WARN if absent).
  local ver
  ver="$(vi_config_version "$cfg")"
  if [ -n "$ver" ]; then
    vi_emit PASS "legacy.version-recorded" "zskills_version = $ver"
  else
    vi_emit WARN "legacy.version-recorded" "zskills_version absent from config (source clone may be untagged)"
  fi
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
#   - zskills version present (WARN if absent)
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

  # (2) Mirror-less: .claude/skills/ must be ABSENT in a clean plugin consumer.
  if [ -d "$claude/skills" ] && [ -n "$(ls -A "$claude/skills" 2>/dev/null)" ]; then
    vi_emit WARN "plugin.mirror-less" ".claude/skills/ present on the plugin lane (dual-install? run scripts/switch-install-path.sh)"
  else
    vi_emit PASS "plugin.mirror-less" ".claude/skills/ absent (mirror-less plugin install)"
  fi

  # (3) zskills version recorded (informative — WARN if absent).
  local cfg="$claude/zskills-config.json" ver
  ver="$(vi_config_version "$cfg")"
  if [ -n "$ver" ]; then
    vi_emit PASS "plugin.version-recorded" "zskills_version = $ver"
  else
    vi_emit WARN "plugin.version-recorded" "zskills_version absent from config (plugin seed config has no tag)"
  fi
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
      vi_emit FAIL "lane.none" "no zskills install detected (no \${CLAUDE_PLUGIN_ROOT}, no .claude/skills + settings.json)"
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
