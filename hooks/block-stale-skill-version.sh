#!/bin/bash
# zskills-hook-version: 2026.06.2
# block-stale-skill-version.sh — PreToolUse Bash hook.
#
# Denies `git commit` when a staged skill's content hash no longer matches
# its `metadata.version` field. This is the structural backstop for the
# skill-versioning discipline (see plans/SKILL_VERSION_PRETOOLUSE_HOOK.md
# and references/skill-version-pretooluse-hook.md).
#
# Behavior:
#   1. Filter: only Bash tool invocations are inspected (early exit 0).
#   2. Extract the `command` field from stdin via the canonical
#      block-unsafe-generic.sh sed pattern (with $INPUT fallback on extract
#      failure for defensive scanning).
#   3. Tokenize-then-walk match for `git commit` (handles env-var prefixes,
#      optional `env`, all top-level git flags including -C/-c which take
#      a separate arg, --git-dir=/x / --work-tree=/y / --no-pager / -P).
#   4. On match: invoke scripts/skill-version-stage-check.sh.
#       - rc=0  → emit nothing, exit 0 (allow).
#       - rc!=0 → JSON-escape stderr via pure-bash json_escape and emit a
#                 PreToolUse deny envelope (verbatim shape from
#                 block-unsafe-generic.sh).
#   5. If the script is missing or not executable → fail-open (exit 0
#      silently). Rationale: a consumer that has the hook but not yet the
#      script (pre-/update-zskills install) must not have every git commit
#      bricked. CI's test-skill-conformance.sh is the backstop.
#
# Wrapper recursion (#399): `bash -c '<git commit ...>'` / `sh -c '...'` /
# `eval '...'` are MATCHED via is_git_subcommand_in_wrappers, which
# recursively unwraps the inline-string argument of bash/sh/dash/ksh/zsh
# -c and eval (bounded depth=3). The base is_git_subcommand helper
# remains first-token-anchored (does not recurse on its own); the
# wrapper-recursion is layered on top via the inlined wrappers helper
# below. Test cases C10i+ in tests/test-block-stale-skill-version.sh
# lock the wrapper-positive behavior; C10e/C10h (first-token /
# chain-walker) retain their negative assertions because those helpers
# are intentionally first-token-anchored.
#
#   Note: cd-chained forms like `cd /tmp/wt && git commit` ARE matched as
#   of #393's fix — `is_git_subcommand_in_chain` (inlined from
#   hooks/_lib/git-tokenwalk.sh) walks every shell segment, and the
#   stage-check script is invoked in a subshell `cd`'d to the resolved
#   effective worktree root so its `git -C "$REPO_ROOT" diff --cached`
#   inspects the worktree's index, not the hook's ambient (main-repo)
#   CWD.
#
# Pure bash at runtime (D4 in the reference doc) — no external JSON
# parsers, no scripting-language interpreters. The unit-test harness MAY
# use a separate JSON validator for assertions; the hook itself does not.

# D16(a) plugin-lane conditional-skip shim. No-op on the /update-zskills
# lane (CLAUDE_PLUGIN_ROOT unset → guard below skips the source). On the
# plugin lane it defers to a settings.json-registered copy of this hook to
# prevent double-fire when both install lanes are active. Must be the first
# executable line; the shim controls its own exit/return.
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_lib/plugin-hook-skip-if-mirrored.sh" ] && source "${CLAUDE_PLUGIN_ROOT}/hooks/_lib/plugin-hook-skip-if-mirrored.sh"

# ── Enforcement library (ENFORCEMENT_V2_PLAN #1159) ───────────────────────
# Inlined VERBATIM from hooks/_lib/zskills-enforcement.sh (source-of-truth).
# The .claude/hooks/ legacy mirrors and plugin-served copies cannot reach
# _lib/ at runtime, so the bodies are pasted in; tests/test-hook-helper-drift.sh
# enforces byte-equality. Maintain in _lib only.
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
zskills_enforcement_tag() {
  printf '[hooks.%s.%s — block|warn|off in .claude/zskills-config.json; currently: %s]' \
    "$1" "$2" "${_ZSK_ENF_SOURCE:-unknown}"
}
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
zskills_enforcement_warn() {
  local _w="WARNING (not blocked by this check): $1"
  if [ -z "${_ZSK_ENF_WARNINGS:-}" ]; then
    _ZSK_ENF_WARNINGS="$_w"
  else
    _ZSK_ENF_WARNINGS="$_ZSK_ENF_WARNINGS
$_w"
  fi
}
zskills_enforcement_flush_warnings() {
  [ -n "${_ZSK_ENF_WARNINGS:-}" ] || return 0
  local _esc
  _esc=$(zskills_enforcement_json_escape "$_ZSK_ENF_WARNINGS")
  printf '{"systemMessage":"%s"}' "$_esc"
}

set -u

INPUT=$(cat)

# Filter non-Bash invocations (cheap early exit).
if [[ "$INPUT" != *'"tool_name":"Bash"'* ]] && [[ "$INPUT" != *'"tool_name": "Bash"'* ]]; then
  exit 0
fi

# Canonical command extraction (verbatim from block-unsafe-generic.sh:37).
COMMAND=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | sed 's/\\"/"/g')
# If extraction fails (malformed JSON), fall back to scanning $INPUT so the
# hook remains defensive; no false-allows on the ALLOW path.
[ -z "$COMMAND" ] && COMMAND="$INPUT"

# Extract the cd target from the command (e.g., "cd /tmp/worktree && git commit").
# Hooks run in the main repo CWD, not the agent's cd target. This helper lets
# us run the stage-check script in a subshell `cd`'d to the worktree so its
# `git -C "$REPO_ROOT" diff --cached` reflects the worktree's index, not the
# hook's ambient (main-repo) CWD. Reads $INPUT (the stdin JSON envelope) —
# safe because INPUT is captured at line 43 above.
#
# Inlined from hooks/_lib/resolve-effective-worktree-root.sh (source-of-truth, #401).
# Drift gate: tests/test-hook-helper-drift.sh.
extract_cd_target() {
  local cmd
  # JSON wire format escapes embedded newlines as the two-character
  # sequence `\n`. The regex below uses [[:space:]] as a stop-class —
  # without decoding `\n` to a real newline, multi-line bash commands
  # like `cd /tmp/wt\ngit commit` would capture `/tmp/wt\ngit` (literal
  # backslash-n) into the path and fail the [ -d ] check, causing
  # is_on_main to fall back to the ambient cwd. Decode `\n` here in the
  # same spirit as the existing `\"` decoding. `\n` is the only escape
  # we currently see in practice from Claude Code's wire format.
  cmd=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | sed 's/\\"/"/g; s/\\n/\n/g')
  # Wrapper unwrap (#427): if the command's first non-env-prefix token is
  # a shell wrapper (bash/sh/dash/ash/ksh/zsh -c '<inner>') or `eval
  # '<inner>'`, peel one layer and re-inspect the inner string. Mirrors
  # is_git_subcommand_in_wrappers's recursion: PR #417 made the classify
  # check wrapper-aware but left this resolver one-level, so wrapped
  # commits like `bash -c 'cd /tmp/wt && git commit'` fired the hook on
  # the OUTER command (starts with `bash`, not `cd`) → empty extraction
  # → fallback to $CLAUDE_PROJECT_DIR (main repo) → stage-check and
  # tracking-marker enforcement silently passed against MAIN's empty
  # index. Bounded depth (3) matches the wrapper-helper convention.
  local depth=3
  while [ "$depth" -gt 0 ]; do
    local -a TOKENS
    # shellcheck disable=SC2206
    read -ra TOKENS <<< "$cmd"
    local i=0 n=${#TOKENS[@]}
    while [[ $i -lt $n && "${TOKENS[$i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
      ((i++))
    done
    [[ $i -lt $n && "${TOKENS[$i]}" == "env" ]] && ((i++))
    while [[ $i -lt $n && "${TOKENS[$i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
      ((i++))
    done
    local first="${TOKENS[$i]:-}"
    case "$first" in
      */*) first="${first##*/}" ;;
    esac
    local inner=""
    case "$first" in
      bash|sh|dash|ash|ksh|zsh)
        local j=$((i+1))
        local found_c=0
        while [[ $j -lt $n ]]; do
          local t="${TOKENS[$j]}"
          case "$t" in
            -c) found_c=1; ((j++)); break ;;
            -[lir]c|-c[lir]|-[lir][lir]c|-c[lir][lir]) found_c=1; ((j++)); break ;;
            --) ((j++)); break ;;
            -*) ((j++)) ;;
            *) break ;;
          esac
        done
        if [[ $found_c -eq 1 && $j -lt $n ]]; then
          local k=$j
          while [[ $k -lt $n ]]; do
            if [ -z "$inner" ]; then
              inner="${TOKENS[$k]}"
            else
              inner="$inner ${TOKENS[$k]}"
            fi
            ((k++))
          done
          inner="${inner#\'}"; inner="${inner%\'}"
          inner="${inner#\"}"; inner="${inner%\"}"
        fi
        ;;
      eval)
        local k=$((i+1))
        while [[ $k -lt $n ]]; do
          if [ -z "$inner" ]; then
            inner="${TOKENS[$k]}"
          else
            inner="$inner ${TOKENS[$k]}"
          fi
          ((k++))
        done
        inner="${inner#\'}"; inner="${inner%\'}"
        inner="${inner#\"}"; inner="${inner%\"}"
        ;;
    esac
    if [ -n "$inner" ]; then
      cmd="$inner"
      ((depth--))
      continue
    fi
    break
  done
  # Segment-walk: split $cmd on statement separators (`;`, `&&`, `||`, `|`,
  # newline) and look for the first `cd <target>` whose preamble in the
  # segment is purely env-mutating / inert shell statements. Issue #924:
  # the previous `^cd[[:space:]]+` regex against the whole command missed
  # `set -e; cd /tmp/wt && …`, `export X=Y; cd …`, `. resolver.sh && cd …`,
  # `VAR=val cd …`, all common in orchestrator-side worktree bookkeeping.
  # Segment separators we split on are exactly those that terminate the
  # previous statement in bash; they cannot appear inside `cd`'s target
  # token (it's stop-classed on the same chars).
  local SEG_IFS=$'\n'
  # Replace each `&&`, `||`, `|`, `;` with a newline so we can read -a.
  local segs="${cmd//&&/$'\n'}"
  segs="${segs//||/$'\n'}"
  segs="${segs//|/$'\n'}"
  segs="${segs//;/$'\n'}"
  local IFS_OLD="$IFS"
  IFS="$SEG_IFS"
  local -a SEGMENTS
  # shellcheck disable=SC2206
  SEGMENTS=( $segs )
  IFS="$IFS_OLD"
  local seg
  for seg in "${SEGMENTS[@]}"; do
    # Trim leading/trailing whitespace.
    seg="${seg#"${seg%%[![:space:]]*}"}"
    seg="${seg%"${seg##*[![:space:]]}"}"
    [ -z "$seg" ] && continue
    local -a STOKENS
    # shellcheck disable=SC2206
    read -ra STOKENS <<< "$seg"
    local si=0 sn=${#STOKENS[@]}
    # Skip env-var assignment prefixes (KEY=val ...).
    while [[ $si -lt $sn && "${STOKENS[$si]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
      ((si++))
    done
    # Skip `env` wrapper (and its KEY=val args).
    [[ $si -lt $sn && "${STOKENS[$si]}" == "env" ]] && ((si++))
    while [[ $si -lt $sn && "${STOKENS[$si]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
      ((si++))
    done
    local stok="${STOKENS[$si]:-}"
    case "$stok" in
      */*) stok="${stok##*/}" ;;
    esac
    case "$stok" in
      set|export|unset|source|.|:|true|false|alias|unalias|shopt|declare|local|readonly|typeset)
        # Inert / env-mutating preamble statement — skip this segment.
        continue
        ;;
      cd)
        local stgt="${STOKENS[$((si+1))]:-}"
        [ -z "$stgt" ] && continue
        # Strip surrounding quotes if present.
        stgt="${stgt%\"}"; stgt="${stgt#\"}"
        stgt="${stgt%\'}"; stgt="${stgt#\'}"
        if [ -d "$stgt" ]; then
          echo "$stgt"
          return 0
        fi
        # cd target didn't resolve — stop walking; downstream segments
        # operate on a different cwd we can't reason about.
        return 0
        ;;
      *)
        # First "real" statement is not a cd — no preamble-cd in this
        # command. Stop walking; per design, only a leading preamble of
        # env-mutating statements is allowed before the cd.
        return 0
        ;;
    esac
  done
}

# Inlined from hooks/_lib/resolve-effective-worktree-root.sh (source-of-truth, #401).
# Drift gate: tests/test-hook-helper-drift.sh.
resolve_effective_worktree_root() {
  local env_override="$1"
  local cd_target="$2"
  local fallback="$3"
  if [ -n "$env_override" ]; then
    printf '%s\n' "$env_override"
  elif [ -n "$cd_target" ]; then
    printf '%s\n' "$cd_target"
  else
    printf '%s\n' "$fallback"
  fi
}

# Match `git commit` via two-stage tokenize-then-walk. Rationale: a single
# regex that allows arbitrary git top-level flags (--no-pager, --git-dir=/x,
# -P, -C path, -c k=v, --work-tree=/y, …) becomes a combinatorial mess and
# was empirically shown bypassable in Round 2 finding N1 (e.g.,
# `git --no-pager commit` slipped past the narrow `(-C …|-c …)?` form).
# Tokenize on whitespace, skip env-var prefixes, find literal `git`, then
# walk past every `-…`/`--…` flag (consuming an extra token only for `-C`
# and `-c`, which take a separate arg — all other top-level flags either
# embed their value with `=` or take none) and check if the next token is
# `commit`. `is_git_subcommand_in_chain` segment-walks the command so
# cd-chained forms (`cd /tmp/wt && git commit`) match — required for
# correct worktree behavior (#393).
#
# Wrapper recursion (#399): the call site below uses
# is_git_subcommand_in_wrappers (which layers on top of _in_chain) so
# `bash -c 'git commit ...'` / `eval 'git commit ...'` are also matched.
# Inlined from hooks/_lib/git-tokenwalk.sh (source-of-truth). Drift gate: tests/test-hook-helper-drift.sh (Phase 5.4).
is_git_subcommand() {
  local cmd="$1"
  local want_sub="$2"
  GIT_SUB_INDEX=-1
  GIT_SUB_REST=""
  local -a TOKENS
  # shellcheck disable=SC2206
  read -ra TOKENS <<< "$cmd"
  local i=0 n=${#TOKENS[@]}
  while [[ $i -lt $n && "${TOKENS[$i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
    ((i++))
  done
  [[ $i -lt $n && "${TOKENS[$i]}" == "env" ]] && ((i++))
  while [[ $i -lt $n && "${TOKENS[$i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
    ((i++))
  done
  # Skip transparent command-prefix wrappers. These execute the next
  # argv as a separate process (or in-place for `exec`), so
  # `nohup git push origin main`, `timeout 30 git push origin main`,
  # `command git commit --no-verify`, etc. are operationally equivalent
  # to the bare form. Without this skip an agent reaching for
  # `timeout 30 git push` (e.g., after a previous push hung) would
  # bypass every git-side gate. Mirrors the gh variant's prefix-skip
  # (issue #279/PR #255), extended for `git` per issue #567.
  while [[ $i -lt $n ]]; do
    local _pref="${TOKENS[$i]}"
    case "$_pref" in
      */*) _pref="${_pref##*/}" ;;
    esac
    local _need_duration=0
    case "$_pref" in
      command|exec|nohup|nice|time)
        ((i++)) ;;
      timeout)
        ((i++)); _need_duration=1 ;;
      *)
        break ;;
    esac
    # Consume zero-or-more leading flag tokens. `--` is a one-shot
    # end-of-options marker (consume it, stop the flag run).
    while [[ $i -lt $n ]]; do
      if [[ "${TOKENS[$i]}" == "--" ]]; then
        ((i++)); break
      fi
      [[ "${TOKENS[$i]:0:1}" != "-" ]] && break
      ((i++))
    done
    # `timeout` requires a DURATION positional after any leading flags.
    if [[ $_need_duration -eq 1 && $i -lt $n ]]; then
      ((i++))
    fi
  done
  local g="${TOKENS[$i]:-}"
  g="${g%\"}"; g="${g#\"}"
  g="${g%\'}"; g="${g#\'}"
  # Strip absolute/relative path prefix so `/usr/bin/git push origin main`
  # and `./git commit` are recognized as git invocations. Mirrors the gh
  # variant's path-strip (issue #528). Without this, path-prefixed forms
  # silently bypassed every git-side hook gate.
  case "$g" in
    */*) g="${g##*/}" ;;
  esac
  [[ "$g" != "git" ]] && return 1
  ((i++))
  while [[ $i -lt $n && "${TOKENS[$i]:0:1}" == "-" ]]; do
    case "${TOKENS[$i]}" in
      # Multi-arg git GLOBAL flags taking a SEPARATE-token value: skip flag +
      # value (2 tokens) so the subcommand isn't misread as the flag's value —
      # the push/commit gate bypass closed by #1133 (extends the -C-only #1037).
      # `=`-fused forms (--git-dir=DIR) are one `-`-token -> `*)` 1-token arm.
      -C|-c|--git-dir|--work-tree|--namespace|--exec-path|--super-prefix) ((i+=2)) ;;
      *)     ((i+=1)) ;;
    esac
  done
  local sub="${TOKENS[$i]:-}"
  sub="${sub%\"}"; sub="${sub#\"}"
  sub="${sub%\'}"; sub="${sub#\'}"
  [[ "$sub" != "$want_sub" ]] && return 1
  # Match. Set GIT_SUB_INDEX and build GIT_SUB_REST scoped to the
  # current shell segment (truncate at first &&/||/;/|).
  GIT_SUB_INDEX=$((i + 1))
  local j=$GIT_SUB_INDEX
  local rest=""
  while [[ $j -lt $n ]]; do
    case "${TOKENS[$j]}" in
      '&&'|'||'|';'|'|') break ;;
    esac
    rest="$rest ${TOKENS[$j]}"
    ((j++))
  done
  # Strip the leading space introduced by the loop.
  GIT_SUB_REST="${rest# }"
  return 0
}

# Inlined from hooks/_lib/git-tokenwalk.sh (source-of-truth). Drift gate: tests/test-hook-helper-drift.sh.
is_git_subcommand_in_chain() {
  local cmd="$1"
  local want_sub="$2"
  # Replace shell-segment boundaries with newlines, then iterate.
  # Handles: && || ; | (real boundaries), literal newline (multi-line
  # commands), AND the JSON-escaped literal two-char `\n` (which arrives
  # this way because the hook does not JSON-decode — sed-extracted
  # values preserve the backslash-n).
  local normalized
  normalized=$(printf '%s' "$cmd" \
    | sed -E 's/[[:space:]]*(\&\&|\|\||;|\|)[[:space:]]*/\n/g' \
    | sed -E 's/\\n/\n/g')
  local seg
  while IFS= read -r seg; do
    [ -z "$seg" ] && continue
    if is_git_subcommand "$seg" "$want_sub"; then
      return 0
    fi
  done <<< "$normalized"
  return 1
}

# Inlined from hooks/_lib/git-tokenwalk.sh (source-of-truth). Drift gate: tests/test-hook-helper-drift.sh.
# Closes the bash -c / eval / sh -c wrapper-bypass hole (#399).
is_git_subcommand_in_wrappers() {
  local cmd="$1"
  local want_sub="$2"
  local depth="${3:-3}"

  # First, check the direct + chain case via existing helper.
  if is_git_subcommand_in_chain "$cmd" "$want_sub"; then
    return 0
  fi

  # Bounded recursion depth.
  [ "$depth" -le 0 ] && return 1

  # Split on chain operators (same as _in_chain) and inspect each
  # segment for a wrapper pattern.
  local normalized
  normalized=$(printf '%s' "$cmd" \
    | sed -E 's/[[:space:]]*(\&\&|\|\||;|\|)[[:space:]]*/\n/g' \
    | sed -E 's/\\n/\n/g')

  local seg
  while IFS= read -r seg; do
    [ -z "$seg" ] && continue

    # Look for an inline-string wrapper. Use bash regex to capture the
    # inner string after a `-c` flag or after an `eval`. The captured
    # group is the rest of the segment starting at the inner-arg
    # boundary; we then strip outer quotes (single or double).
    local wrapper_inner=""

    # Tokenize the segment to find the wrapper command and its -c arg.
    local -a TOKENS
    # shellcheck disable=SC2206
    read -ra TOKENS <<< "$seg"
    local i=0 n=${#TOKENS[@]}

    # Skip env-var prefixes (KEY=val ... cmd ...).
    while [[ $i -lt $n && "${TOKENS[$i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
      ((i++))
    done
    [[ $i -lt $n && "${TOKENS[$i]}" == "env" ]] && ((i++))
    while [[ $i -lt $n && "${TOKENS[$i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
      ((i++))
    done

    local first="${TOKENS[$i]:-}"
    # Allow a possible absolute path: /bin/bash → match the basename.
    case "$first" in
      */*) first="${first##*/}" ;;
    esac

    case "$first" in
      bash|sh|dash|ash|ksh|zsh)
        # Walk shell-level flags to find -c (or -lc/-ic/-cx combined
        # short-flag forms). All of these put the next token as the
        # inline string to execute.
        local j=$((i+1))
        local found_c=0
        while [[ $j -lt $n ]]; do
          local t="${TOKENS[$j]}"
          case "$t" in
            -c) found_c=1; ((j++)); break ;;
            -[lir]c|-c[lir]|-[lir][lir]c|-c[lir][lir]) found_c=1; ((j++)); break ;;
            --) ((j++)); break ;;
            -*) ((j++)) ;;
            *) break ;;
          esac
        done
        if [[ $found_c -eq 1 && $j -lt $n ]]; then
          # Reconstruct the inner string from token j to end of segment.
          # read -ra split on whitespace, so a quoted multi-word string
          # like 'git commit -m foo' became three tokens: "'git" "commit"
          # "-m" "foo'". Rejoin with spaces.
          local inner=""
          local k=$j
          while [[ $k -lt $n ]]; do
            if [ -z "$inner" ]; then
              inner="${TOKENS[$k]}"
            else
              inner="$inner ${TOKENS[$k]}"
            fi
            ((k++))
          done
          # Strip one layer of outer quotes (single or double).
          inner="${inner#\'}"; inner="${inner%\'}"
          inner="${inner#\"}"; inner="${inner%\"}"
          wrapper_inner="$inner"
        fi
        ;;
      eval)
        # All args to eval are the string to execute. Rejoin and strip
        # outer quotes.
        local inner=""
        local k=$((i+1))
        while [[ $k -lt $n ]]; do
          if [ -z "$inner" ]; then
            inner="${TOKENS[$k]}"
          else
            inner="$inner ${TOKENS[$k]}"
          fi
          ((k++))
        done
        inner="${inner#\'}"; inner="${inner%\'}"
        inner="${inner#\"}"; inner="${inner%\"}"
        wrapper_inner="$inner"
        ;;
    esac

    if [ -n "$wrapper_inner" ]; then
      if is_git_subcommand_in_wrappers "$wrapper_inner" "$want_sub" $((depth - 1)); then
        return 0
      fi
    fi
  done <<< "$normalized"

  return 1
}
is_git_subcommand_in_wrappers "$COMMAND" commit || exit 0

# Lane-portable resolution (W1.4 pattern 1): the plugin lane resolves the
# stage-check script under ${CLAUDE_PLUGIN_ROOT}/scripts/; the
# /update-zskills lane resolves it under ${CLAUDE_PROJECT_DIR}/scripts/
# (repo-root scripts/ — consumer-customizable utility that stays at
# scripts/, NOT under .claude/skills/update-zskills). Guard against `set -u`
# + unset `$CLAUDE_PROJECT_DIR` (rare but documented harness edge case):
# `${X:-$PWD}` falls back to cwd on the legacy arm; if the script is absent
# under the resolved path, `[ -x ]` trips the fail-open below. Per Round 2
# N5: without the guard, `set -u` would crash the hook → nonzero exit +
# empty stdout → silent failure mode worse than fail-open.
SCRIPT="${CLAUDE_PLUGIN_ROOT:-${CLAUDE_PROJECT_DIR:-$PWD}}/scripts/skill-version-stage-check.sh"
[ -x "$SCRIPT" ] || exit 0  # fail-open: script absent (consumer pre-/update-zskills)

# Resolve effective worktree root for the stage-check subshell.
# Hooks run with the main repo as CWD (= $CLAUDE_PROJECT_DIR); when an
# agent invokes `cd /tmp/wt && git commit` from a worktree, the script's
# CWD must be the worktree, not main, so `git rev-parse --show-toplevel`
# inside stage-check resolves to the worktree's index. Precedence:
# extracted cd target → $CLAUDE_PROJECT_DIR → $PWD. No env-override tier
# (the stage-check subshell is not parameterized by test harnesses).
EFFECTIVE_REPO_ROOT=$(resolve_effective_worktree_root "" "$(extract_cd_target)" "${CLAUDE_PROJECT_DIR:-$PWD}")

# Run script in a subshell `cd`'d to the effective root (subshell preserves
# the hook's own CWD); capture stderr (the STOP message); discard stdout.
STDERR=$(cd "$EFFECTIVE_REPO_ROOT" && bash "$SCRIPT" 2>&1 >/dev/null) && exit 0  # rc=0 means clean
# Script exited non-zero — deny.

# ── Enforcement mode resolution (ENFORCEMENT_V2_PLAN Phase 2, #1159) ───────
# stale_skill_version is a KEEP-HARD check: the UNSET default is block-always
# (a stale metadata.version slipping through defeats the skill-versioning
# discipline). An explicit project toggle (warn/off) is still honored (Settled
# decision 6). ENF_ROOT (config_root) drives the toggle loader + the
# predicate's main-root arm; EFFECTIVE_REPO_ROOT (already resolved above)
# doubles as ENF_LOCAL for the predicate's tracked-marker arm.
ENF_ROOT=$(zskills_enforcement_config_root)
PRED=$(zskills_enforcement_predicate "$INPUT" "$ENF_ROOT" "$EFFECTIVE_REPO_ROOT")
zskills_enforcement_load_toggles "$ENF_ROOT/.claude/zskills-config.json"
MODE=$(zskills_enforcement_mode git_discipline stale_skill_version hard "$PRED")
[ "$MODE" = "off" ] && exit 0
# Re-run WITHOUT command substitution so _ZSK_ENF_SOURCE is set in THIS shell
# (the tag formatter reads it; a $()-captured call would lose the side effect).
zskills_enforcement_mode git_discipline stale_skill_version hard "$PRED" >/dev/null

# Append the toggle tag (Settled decision 14: message names its toggle).
STDERR="$STDERR

$(zskills_enforcement_tag git_discipline stale_skill_version)"

# Route on resolved mode. warn → DECISION-LESS systemMessage on the warn
# channel (command still runs); block → the existing deny envelope. The
# local json_escape twin is RETARGETED to the lib's
# zskills_enforcement_json_escape (byte-identical contract — the lib function
# was specced FROM this twin; drift-gated, one source).
if [ "$MODE" = "warn" ]; then
  zskills_enforcement_warn "$STDERR"
  zskills_enforcement_flush_warnings
  exit 0
fi

REASON=$(zskills_enforcement_json_escape "$STDERR")
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$REASON"
exit 0
