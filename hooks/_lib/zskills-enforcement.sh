#!/bin/bash
# hooks/_lib/zskills-enforcement.sh — source-of-truth bodies for the
# enforcement-v2 watched/enforce predicate, lazy per-check toggle loading,
# mode resolution, the message-tag formatter, the warn accumulator, and the
# warn-channel flush emitter (ENFORCEMENT_V2_PLAN Phase 1, #1159).
#
# Every consuming hook INLINES these functions verbatim (the .claude/hooks/
# legacy mirrors and the plugin-served copies cannot reach _lib/ at runtime);
# tests/test-hook-helper-drift.sh enforces byte-equality at CI time. Maintain
# HERE only. No hook sources this file yet — Phases 2–3 do the integration.
#
# ── Teachable rule (ENFORCEMENT_V2_PLAN) ──────────────────────────────────
# Stay QUIET when watched (no nagging); BLOCK when no one's watching; coaching
# is OPT-IN; projects override per-check. The SHIPPED default for a demotable
# check when WATCHED is SILENT (owner amendment 2026-06-15, Settled decision
# 0) — it emits nothing and the command runs (the harness permission prompt
# still fires). Warn is the OPT-IN coaching value (`"warn"` per-check toggle).
# ONE named exception: config_hooks_tamper WARNS-when-watched by shipped
# default (Settled decision 13 / DA4) because disarming the protection system
# is durable + cross-session and must never happen invisibly. Autonomous /
# unwatched ALWAYS blocks a demotable check; hard checks block always.
#
# ── Fail-closed (Critical invariant 6) ────────────────────────────────────
# Missing config / parse error / Python-unavailable → shipped defaults (hard
# checks block; demotable checks follow the predicate). "silent" is reachable
# ONLY via the deliberate watched+demotable+unset path — NEVER via an error
# path.
#
# ── Performance contract ──────────────────────────────────────────────────
# The predicate is pure bash + file tests + at most one `find` over
# .zskills/inflight/ (only when that dir exists), NO Python. The toggle loader
# runs LAZILY — only when a gate is about to emit — and makes at most ONE
# Python invocation per hook fire (cached in _ZSK_ENF_TOGGLES_LOADED). Zero
# added cost on the no-violation path.
#
# ── Warn channel pin (PROVISIONAL — attended confirmation REQUIRED) ────────
# Form W-A (decision-less {"systemMessage":"…"} on stdout, exit 0) is the
# shipped form for the opt-in `"warn"` value. The silent default emits nothing;
# the deny arm is the status quo (neither needs the probe). flush_warnings ships
# Form W-A only (no W-B dead branch).
#
# PROVISIONAL PIN — the Phase 1 headless warn-channel probe
# (tests/manual/warn-channel-probe.sh, run against claude-cli 2.1.177 on
# 2026-06-15) established empirically that BOTH candidate forms FIRE (sentinel
# verified) but NEITHER surfaces in the HEADLESS `claude -p --output-format
# stream-json` stream: W-A's decision-less systemMessage produced no
# systemMessage record, and W-B's stderr did not propagate to the CLI stderr.
# The headless stream is a PROXY for interactive rendering (plan Settled
# decision 2 says so), so a headless non-surface does NOT prove the opt-in
# `"warn"` value is invisible in a real attended TTY session — that is exactly
# what the plan's step 4(b) one-time ATTENDED confirmation and the Phase 7 live
# check exist to decide. W-A is pinned provisionally (it is the cleaner
# decision-less channel and uses the same systemMessage field
# session-start-greeting.sh / session-rules-context.sh use on SessionStart).
# BEFORE the opt-in `"warn"` value is accepted as user-visible, the orchestrator
# MUST run the live attended confirmation (one watched command with a `"warn"`
# toggle set, confirm the warning renders). The silent shipped default and the
# deny arm are unaffected by this and ship now. Re-run the probe on CLI
# upgrades.
#
# This file is sourceable under zsh consumers: every function using
# BASH_REMATCH / arrays carries the #1169 LOCAL_OPTIONS guard so the option
# flip is scoped to the function and is a no-op under bash.

# ── KNOWN_CHECKS registry (Toggle-key registry table, Phase 1) ────────────
# One `group.check:class` token per line — exactly the 37 distinct toggle keys
# of the registry table. The unit suite and the Phase 3 lib↔schema tripwire
# both read this list. class = hard (unset default block-always; predicate
# never demotes) | demotable (unset default block-when-enforce /
# silent-when-watched, EXCEPT config_hooks_tamper which warns-when-watched).
_ZSK_ENF_KNOWN_CHECKS='git_destructive.stash_drop:hard
git_destructive.stash_write:hard
git_destructive.checkout_discard:hard
git_destructive.restore_discard:hard
git_destructive.switch_discard:hard
git_destructive.clean_force:hard
git_destructive.reset_hard:hard
process_kill.kill_9:hard
process_kill.fuser_k:hard
process_kill.xargs_kill:hard
process_kill.kill_substitution:hard
fs_destructive.rm_recursive:hard
fs_destructive.find_delete:hard
fs_destructive.rsync_delete:hard
fs_destructive.xargs_destructive:hard
fs_destructive.zskills_tree_delete:hard
fs_destructive.clear_tracking_agent:hard
git_discipline.git_add_all:demotable
git_discipline.no_verify:hard
git_discipline.logs_add_all:demotable
git_discipline.test_pipe:demotable
git_discipline.full_cmd_unset:demotable
git_discipline.tests_not_run:demotable
git_discipline.ui_unverified:demotable
git_discipline.stale_skill_version:hard
main_protection.push_to_main:demotable
main_protection.commit_on_main:demotable
main_protection.cherry_pick_on_main:demotable
main_protection.main_edit:demotable
main_protection.config_hooks_tamper:demotable
tracking.requires_unfulfilled:demotable
tracking.step_unverified:demotable
tracking.step_unreported:demotable
tracking.issue_unclaimed:demotable
tracking.plan_unclaimed:demotable
tracking.cron_invalid:hard
pr_discipline.direct_gh_pr:hard
'

# zskills_enforcement_config_root — no args. Echoes the MAIN repo root used as
# the toggle-file root and the main-root marker/sentinel root (Settled
# decision 13). Worktree-local config copies are NEVER consulted for toggles.
#   ${ZSKILLS_ENF_CONFIG_ROOT} when set (test override — this fn gets its OWN
#     env override, NOT REPO_ROOT, whose semantics are "the hook's session
#     root"); else
#   $(git rev-parse --git-common-dir) parent when inside a git checkout (the
#     MAIN root even from inside a linked worktree); else
#   ${CLAUDE_PROJECT_DIR}; else pwd.
zskills_enforcement_config_root() {
  if [ -n "${ZSKILLS_ENF_CONFIG_ROOT:-}" ]; then
    printf '%s\n' "${ZSKILLS_ENF_CONFIG_ROOT%/}"
    return 0
  fi
  local gcd
  gcd=$(git rev-parse --git-common-dir 2>/dev/null) || gcd=""
  if [ -n "$gcd" ]; then
    # git-common-dir is the MAIN .git dir even from a linked worktree; its
    # parent is the main checkout root. May be relative — resolve it.
    local parent
    parent=$(cd "$gcd/.." 2>/dev/null && pwd) || parent=""
    if [ -n "$parent" ]; then
      printf '%s\n' "${parent%/}"
      return 0
    fi
  fi
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    printf '%s\n' "${CLAUDE_PROJECT_DIR%/}"
    return 0
  fi
  printf '%s\n' "$(pwd)"
}

# zskills_enforcement_predicate — args: $1=hook stdin JSON, $2=main root,
#   $3=effective LOCAL root. Echoes ONE of:
#   "enforce-autonomous" | "enforce-pipeline" | "watched".
#   Pure bash + file tests, NO Python.
zskills_enforcement_predicate() {
  if [ -n "${ZSH_VERSION:-}" ]; then
    setopt LOCAL_OPTIONS KSH_ARRAYS BASH_REMATCH 2>/dev/null
  fi
  local _json="$1" _main="${2%/}" _local="${3%/}"
  local PERM=""
  # SPOOF-PROOF BY CONSTRUCTION: in valid JSON, any quote inside a string
  # value (tool_input.command, new_string, …) is escaped as \" — so a
  # counterfeit "permission_mode" literal embedded in command content can
  # only appear with a backslash before its opening quote, which (^|[^\\])
  # rejects. Only the real top-level key (whose quote follows `{`, `,`, or
  # whitespace) can match, regardless of field order. The value class
  # [a-zA-Z]+ cannot span an escape. No tool_input stripping or field-order
  # assumption needed.
  if [[ "$_json" =~ (^|[^\\])\"permission_mode\"[[:space:]]*:[[:space:]]*\"([a-zA-Z]+)\" ]]; then
    PERM="${BASH_REMATCH[2]}"
  fi
  # enforce-autonomous iff bypassPermissions OR not a recognized attended
  # mode (absent/unrecognized — fail-safe TOWARD enforcement).
  case "$PERM" in
    default|acceptEdits|plan)
      : # attended modes — fall through to the pipeline-live check
      ;;
    *)
      printf '%s\n' "enforce-autonomous"
      return 0
      ;;
  esac
  # enforce-pipeline iff a zskills pipeline is LIVE. The LOCAL-root tracked
  # arm is load-bearing: worktree pipeline agents inherit "default" mode, so
  # only the worktree's own .zskills/tracked keeps them enforced (subagent
  # permission_mode VALUE is unpinned by Probe B — it verified PRESENCE only).
  if [ -f "$_local/.zskills/tracked" ] || [ -f "$_local/.zskills-tracked" ]; then
    printf '%s\n' "enforce-pipeline"; return 0
  fi
  # Main-root OR-arm (CLAUDE.md Tracking Enforcement prose — orchestrator
  # writes both roots; kept even though no skill implements the main-root
  # write today). Legacy dual-read; drop the .zskills-tracked arm when #1146
  # lands.
  if [ -f "$_main/.zskills/tracked" ] || [ -f "$_main/.zskills-tracked" ]; then
    printf '%s\n' "enforce-pipeline"; return 0
  fi
  # Inflight sentinel younger than the TTL (120 min = 7200 s, the
  # check-inflight-batch.sh default). Supplementary signal — ages by file
  # MTIME (check-inflight-batch ages by the started_at JSON field; congruent
  # because sentinels are only ever written/rewritten whole). Only the
  # cron-shaped workers write sentinels; runs >2h age out mid-run, falling
  # back to the tracked-marker arm.
  if [ -d "$_main/.zskills/inflight" ]; then
    if [ -n "$(find "$_main/.zskills/inflight" -name '*.json' -mmin -120 2>/dev/null | head -1)" ]; then
      printf '%s\n' "enforce-pipeline"; return 0
    fi
  fi
  # NOTE: bare [ -d "$_main/.zskills/tracking" ] is deliberately NOT tested —
  # finished pipelines leave subdirs there indefinitely (20+ stale dirs in
  # the dogfood repo), which would make enforce permanent in every repo that
  # ever ran a pipeline.
  printf '%s\n' "watched"
}

# zskills_enforcement_load_toggles — arg: $1=config file path
#   ($1 = "$(zskills_enforcement_config_root)/.claude/zskills-config.json")
#   Lazy + cached: first call populates _ZSK_ENF_TOGGLES (newline-separated
#   "group.check=value" + "group.enabled=bool" lines) via ONE Python call;
#   subsequent calls are no-ops. Python unavailable / file missing /
#   json.load error → _ZSK_ENF_TOGGLES="" + _ZSK_ENF_TOGGLES_LOADED=1
#   (shipped defaults; never errors — fail-closed, NEVER silent).
zskills_enforcement_load_toggles() {
  [ "${_ZSK_ENF_TOGGLES_LOADED:-0}" = "1" ] && return 0
  _ZSK_ENF_TOGGLES=""
  _ZSK_ENF_TOGGLES_LOADED=1
  local _cfg="$1"
  [ -n "$_cfg" ] && [ -f "$_cfg" ] || return 0
  # Resolve a working Python 3 interpreter (probe-run; honors ZSKILLS_PYTHON).
  local _py="" _cand
  for _cand in "${ZSKILLS_PYTHON:-}" python3 python; do
    [ -n "$_cand" ] || continue
    command -v "$_cand" >/dev/null 2>&1 || continue
    if "$_cand" -c 'import sys; sys.exit(0 if sys.version_info[0]==3 else 1)' >/dev/null 2>&1; then
      _py=$(command -v "$_cand"); break
    fi
  done
  [ -n "$_py" ] || return 0   # Python unavailable → shipped defaults
  local _dump
  _dump=$("$_py" - "$_cfg" <<'PYEOF' 2>/dev/null
import json, sys
try:
    with open(sys.argv[1]) as fh:
        data = json.load(fh)
except Exception:
    sys.exit(0)   # parse error → empty dump → shipped defaults
hooks = data.get("hooks")
if not isinstance(hooks, dict):
    sys.exit(0)
out = []
for group, body in hooks.items():
    if not isinstance(body, dict):
        continue
    for key, val in body.items():
        if key == "enabled":
            if isinstance(val, bool):
                out.append("%s.enabled=%s" % (group, "true" if val else "false"))
        elif isinstance(val, str):
            out.append("%s.%s=%s" % (group, key, val))
print("\n".join(out))
PYEOF
)
  # A non-zero exit or empty dump leaves _ZSK_ENF_TOGGLES="" (defaults).
  [ -n "$_dump" ] && _ZSK_ENF_TOGGLES="$_dump"
  return 0
}

# zskills_enforcement_mode — args: $1=group $2=check $3=class(hard|demotable)
#   $4=predicate-result (enforce-autonomous|enforce-pipeline|watched).
#   Echoes "block" | "warn" | "silent" | "off" and sets _ZSK_ENF_SOURCE.
#   Requires _ZSK_ENF_TOGGLES to be loaded (caller invokes load_toggles first
#   on the emitting path). See the file header for the teachable rule.
zskills_enforcement_mode() {
  local _group="$1" _check="$2" _class="$3" _pred="$4"
  local _explicit="" _group_enabled="" _line
  # Read the cached toggles. Linear scan — the list is tiny (<=37 lines).
  if [ -n "${_ZSK_ENF_TOGGLES:-}" ]; then
    while IFS= read -r _line; do
      case "$_line" in
        "$_group.$_check="*) _explicit="${_line#*=}" ;;
        "$_group.enabled="*) _group_enabled="${_line#*=}" ;;
      esac
    done <<EOF
$_ZSK_ENF_TOGGLES
EOF
  fi

  # Group ceiling: enabled:false turns the whole group off — EXCEPT
  # config_hooks_tamper, which is ceiling-EXEMPT (Settled decision 13
  # self-protection: a group ceiling write must not take the tamper gate down
  # with it; only its own explicit per-check value can turn it off).
  if [ "$_group_enabled" = "false" ] && [ "$_check" != "config_hooks_tamper" ]; then
    _ZSK_ENF_SOURCE="group disabled in project config"
    printf '%s\n' "off"; return 0
  fi

  # Explicit per-check value always wins (Settled decision 6) — for hard AND
  # demotable checks alike. Only block|warn|off are honored values.
  case "$_explicit" in
    block|warn|off)
      _ZSK_ENF_SOURCE="project config: $_explicit"
      printf '%s\n' "$_explicit"; return 0
      ;;
  esac

  # Unset → class-derived default.
  if [ "$_class" = "hard" ]; then
    # A hard check is never silent, even watched.
    case "$_pred" in
      enforce-autonomous) _ZSK_ENF_SOURCE="autonomous default" ;;
      enforce-pipeline)   _ZSK_ENF_SOURCE="pipeline-active default" ;;
      *)                  _ZSK_ENF_SOURCE="hard default" ;;
    esac
    printf '%s\n' "block"; return 0
  fi

  # Demotable, unset.
  case "$_pred" in
    enforce-autonomous)
      _ZSK_ENF_SOURCE="autonomous default"
      printf '%s\n' "block"; return 0
      ;;
    enforce-pipeline)
      _ZSK_ENF_SOURCE="pipeline-active default"
      printf '%s\n' "block"; return 0
      ;;
    *)
      # watched + demotable + unset.
      if [ "$_check" = "config_hooks_tamper" ]; then
        # NAMED EXCEPTION (DA4): the tamper gate's effect is durable +
        # cross-session, so a config-disarm must be VISIBLE at write time —
        # warn, NOT silent.
        _ZSK_ENF_SOURCE="attended default (warn — tamper exception)"
        printf '%s\n' "warn"; return 0
      fi
      # OWNER-AMENDMENT zero-config quiet default (was "warn"): emit NOTHING.
      _ZSK_ENF_SOURCE="attended default (silent)"
      printf '%s\n' "silent"; return 0
      ;;
  esac
}

# zskills_enforcement_tag — args: $1=group $2=check. Echoes the switch-naming
#   tag. MUST match the pinned literal regex (unit-suite case):
#     ^\[hooks\.[a-z_]+\.[a-z0-9_]+ — block\|warn\|off in \.claude/zskills-config\.json; currently: .+\]$
zskills_enforcement_tag() {
  printf '[hooks.%s.%s — block|warn|off in .claude/zskills-config.json; currently: %s]' \
    "$1" "$2" "${_ZSK_ENF_SOURCE:-unknown}"
}

# zskills_enforcement_json_escape — arg: $1=raw text; echoes the JSON-escaped
#   string (no surrounding quotes). PURE BASH — byte-for-byte the json_escape
#   contract proven in block-stale-skill-version.sh ≈L541–568: LC_ALL=C;
#   backslash first, then quote, then named control escapes (\n \r \t \b \f),
#   then [[:cntrl:]] strip as defense-in-depth (the bash $'\x00'-$'\x1f' range
#   form is a verified trap — see that hook's comment). Needed so flush W-A
#   can serialize arbitrary multi-line STOP prose with zero Python.
zskills_enforcement_json_escape() {
  local LC_ALL=C
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\b'/\\b}"
  s="${s//$'\f'/\\f}"
  s="${s//[[:cntrl:]]/}"
  printf '%s' "$s"
}

# zskills_enforcement_warn — arg: $1=full message (already tagged). Accumulates
#   $1 into _ZSK_ENF_WARNINGS (newline-joined), prefixed "WARNING (not blocked
#   by this check): " — non-committal because a SIBLING hook on the same
#   matcher may still deny the same call. Emits nothing itself.
zskills_enforcement_warn() {
  local _w="WARNING (not blocked by this check): $1"
  if [ -z "${_ZSK_ENF_WARNINGS:-}" ]; then
    _ZSK_ENF_WARNINGS="$_w"
  else
    _ZSK_ENF_WARNINGS="$_ZSK_ENF_WARNINGS
$_w"
  fi
}

# zskills_enforcement_flush_warnings — no args; called once on the hook's final
#   allow path. Empty _ZSK_ENF_WARNINGS → emits nothing. Otherwise emits the
#   accumulated warnings on the PINNED warn channel (Form W-A — decision-less
#   {"systemMessage":"…"} on stdout, exit-0 path).
#   HARD INVARIANT (Settled decision 2): the warn-path output contains NO
#   permissionDecision — the warn channel must never auto-approve (or otherwise
#   touch) the permission flow for the very commands it warns about.
zskills_enforcement_flush_warnings() {
  [ -n "${_ZSK_ENF_WARNINGS:-}" ] || return 0
  local _esc
  _esc=$(zskills_enforcement_json_escape "$_ZSK_ENF_WARNINGS")
  printf '{"systemMessage":"%s"}' "$_esc"
}
