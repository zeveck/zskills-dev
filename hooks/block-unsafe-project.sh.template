#!/bin/bash
# zskills-hook-version: 2026.06.4
# Block unsafe commands — PROJECT-SPECIFIC enforcement layer.
# No external dependencies — bash and git only.
#
# This file is a template. Most behavior is now driven at runtime from
# .claude/zskills-config.json (unit_cmd, full_cmd, ui.file_patterns,
# main_protected, etc.). Remove sections that don't apply to your project.
#
# Register BOTH this file and block-unsafe-generic.sh in .claude/settings.json
# on the PreToolUse event, Bash matcher. The generic layer runs first.

# D16(a) plugin-lane conditional-skip shim. No-op on the /update-zskills
# lane (CLAUDE_PLUGIN_ROOT unset → guard below skips the source). On the
# plugin lane it defers to a settings.json-registered copy of this hook to
# prevent double-fire when both install lanes are active. Must be the first
# executable line; the shim controls its own exit/return.
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_lib/plugin-hook-skip-if-mirrored.sh" ] && source "${CLAUDE_PLUGIN_ROOT}/hooks/_lib/plugin-hook-skip-if-mirrored.sh"

INPUT=$(cat)

# Only filter Bash commands
if [[ "$INPUT" != *'"tool_name":"Bash"'* ]] && [[ "$INPUT" != *'"tool_name": "Bash"'* ]]; then
  exit 0
fi

# ──────────────────────────────────────────────────────────────
# Command extraction + data-region redaction
# ──────────────────────────────────────────────────────────────
# Lifted from block-unsafe-generic.sh so pattern rules below scan the
# actual shell command with commit-message / PR-body / heredoc prose
# stripped out. Without this, rules fire on commit messages that merely
# DISCUSS a pattern (e.g., `git commit -m "don't git push before tests"`
# would trip the push-tracking rule, or a commit message mentioning
# `.zskills/tracking` would trip the recursive-delete rule).
#
# Only the pattern-scanning rules use $COMMAND. Structured-field
# extraction (transcript_path, etc.) continues to read raw $INPUT.

# Extract the command field from tool_input JSON.
COMMAND=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | sed 's/\\"/"/g')
# Fallback: if extraction fails (malformed JSON), scan raw INPUT so the
# hook remains defensive — no false-allows.
[ -z "$COMMAND" ] && COMMAND="$INPUT"

# Pass 1 — heredoc bodies. Redact `<<[-]?['"]?DELIM['"]?\n BODY \nDELIM(\n|$)`
# with a sentinel. :h / t h loop handles sequential heredocs with different
# delimiters. GNU sed -E backrefs pin the closing delimiter to the opener.
COMMAND=$(printf '%s' "$COMMAND" | sed -E \
  -e ':h' \
  -e 's/<<-?[[:space:]]*"([A-Za-z_][A-Za-z0-9_]*)"\\n.*\\n\1(\\n|$)/HEREDOC_REDACTED\2/' \
  -e 's/<<-?[[:space:]]*'\''([A-Za-z_][A-Za-z0-9_]*)'\''\\n.*\\n\1(\\n|$)/HEREDOC_REDACTED\2/' \
  -e 's/<<-?[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)\\n.*\\n\1(\\n|$)/HEREDOC_REDACTED\2/' \
  -e 't h')

# Pass 2 — flag-scoped quoted arg values.
# - `git commit`                       : -m, --message (incl. -am/-Sm)
# - `gh pr|issue create|comment`       : --body, -b, --title, -t
# Intermediate args tolerated via [^|;&]* so chained ops after the
# arg stay visible. Replacement drops the quotes (bare `REDACTED`) so
# the :m / t m loop terminates on re-run.
COMMAND=$(printf '%s' "$COMMAND" | sed -E \
  -e ':m' \
  -e 's/(git[[:space:]]+commit[[:space:]]([^|;&]*[[:space:]])?(-[a-zA-Z]*m|--message)[[:space:]]+)("[^"]*"|'\''[^'\'']*'\'')/\1REDACTED/g' \
  -e 's/(gh[[:space:]]+(pr|issue)[[:space:]]+(create|comment)[[:space:]]([^|;&]*[[:space:]])?(--body|-b|--title|-t)[[:space:]]+)("[^"]*"|'\''[^'\'']*'\'')/\1REDACTED/g' \
  -e 't m')

# Block patterns -- each with a reason
block_with_reason() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$1"
  exit 0
}

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

# ── gate_with_reason (ENFORCEMENT_V2_PLAN Phase 3, #1159) ──────────────────
# Sibling of block_with_reason that routes a deny site through the enforcement
# predicate + per-check toggle. Sites pass BARE group/check/class args; the
# switch-naming tag (Settled decision 14) is appended HERE in exactly one place.
#   $1=group  $2=check  $3=class(hard|demotable)  $4=message
# Resolution → action:
#   silent | off  → return 0 (continue scanning; accumulate nothing). silent is
#                   the zero-config WATCHED default for demotable sites (owner
#                   amendment) — emits nothing, exactly like off.
#   warn          → accumulate the tagged message via zskills_enforcement_warn
#                   and return 0 (the opt-in coaching value). Must NOT exit the
#                   scan loop, or a single warned check would mask a later hard
#                   check in the same command; the hook's final allow path calls
#                   zskills_enforcement_flush_warnings.
#   block         → emit the deny envelope and exit 0, APPENDING any
#                   already-accumulated warnings to the deny's
#                   permissionDecisionReason (lib deny-path rule — nothing
#                   silently dropped). Uses the same inline 3-step JSON escape
#                   block_with_reason's callers rely on (backslash, quote,
#                   newline) so the tag + warnings serialize safely.
# ENF_ROOT (REUSES the hook's TRACKING_ROOT — same git-common-dir-parent CORE
# as config_root) and ENF_LOCAL (REUSES the hook's LOCAL_ROOT, the SAME root the
# Tier-1 TRACKED_MARKER read uses) are HOISTED above the first deny site so all
# 17 sites consume them.
gate_with_reason() {
  local _g="$1" _c="$2" _cl="$3" _msg="$4"
  local _pred _mode
  _pred=$(zskills_enforcement_predicate "$INPUT" "$ENF_ROOT" "$ENF_LOCAL")
  zskills_enforcement_load_toggles "$ENF_ROOT/.claude/zskills-config.json"
  _mode=$(zskills_enforcement_mode "$_g" "$_c" "$_cl" "$_pred")
  case "$_mode" in
    silent|off) return 0 ;;
  esac
  # Re-run WITHOUT command substitution so _ZSK_ENF_SOURCE is set in THIS shell
  # for the tag formatter (the $()-captured call above loses the side effect).
  zskills_enforcement_mode "$_g" "$_c" "$_cl" "$_pred" >/dev/null
  local _tagged="$_msg

$(zskills_enforcement_tag "$_g" "$_c")"
  if [ "$_mode" = "warn" ]; then
    zskills_enforcement_warn "$_tagged"
    return 0
  fi
  # block — append any already-accumulated warnings, then deny + exit.
  if [ -n "${_ZSK_ENF_WARNINGS:-}" ]; then
    _tagged="$_tagged

$_ZSK_ENF_WARNINGS"
  fi
  local _esc="${_tagged//\\/\\\\}"
  _esc="${_esc//\"/\\\"}"
  _esc="${_esc//$'\n'/\\n}"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$_esc"
  exit 0
}

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

# ─── Tracking enforcement helpers ───
# Shared between the commit / cherry-pick / push reader blocks. Each helper
# takes a marker path + the action-verb context ("committing", "landing",
# "pushing") and calls block_with_reason on violation. TRACKING_DIR is read
# from the caller's scope (the calling block already sets it).
#
# Usage:
#   enforce_requires_marker "$req_path" "committing"
#   enforce_step_implement_marker "$impl_path" "committing"
#   enforce_step_verify_marker "$verify_path" "committing"

enforce_requires_marker() {
  local req="$1"
  local action="$2"
  local base
  base=$(basename "$req")
  local fulfilled="${TRACKING_DIR}/${base/requires./fulfilled.}"
  # Also check inside the same subdir as the requires marker, if it's in one.
  local req_dir
  req_dir=$(dirname "$req")
  local subdir_fulfilled="${req_dir}/${base/requires./fulfilled.}"
  if [ ! -f "$fulfilled" ] && [ ! -f "$subdir_fulfilled" ]; then
    if [ "$action" = "pushing" ]; then
      gate_with_reason tracking requires_unfulfilled demotable "BLOCKED: Required skill invocation '${base#requires.}' not yet fulfilled before pushing. To clear stale tracking: ! bash .claude/skills/update-zskills/scripts/clear-tracking.sh"
    else
      gate_with_reason tracking requires_unfulfilled demotable "BLOCKED: Required skill invocation '${base#requires.}' not yet fulfilled. Invoke the required skill via the Skill tool. To clear stale tracking: ! bash .claude/skills/update-zskills/scripts/clear-tracking.sh"
    fi
  fi
}

enforce_step_implement_marker() {
  local impl="$1"
  local action="$2"
  local base
  base=$(basename "$impl" .implement)
  local verify="${impl/\.implement/.verify}"
  if [ ! -f "$verify" ]; then
    gate_with_reason tracking step_unverified demotable "BLOCKED: ${base#step.} has implementation but no verification. Run verification before ${action}. To clear: ! bash .claude/skills/update-zskills/scripts/clear-tracking.sh"
  fi
}

enforce_step_verify_marker() {
  local verif="$1"
  local action="$2"
  local base
  base=$(basename "$verif" .verify)
  local report="${verif/\.verify/.report}"
  if [ ! -f "$report" ]; then
    gate_with_reason tracking step_unreported demotable "BLOCKED: ${base#step.} verified but no report written. Write report before ${action}. To clear: ! bash .claude/skills/update-zskills/scripts/clear-tracking.sh"
  fi
}

# Extract transcript_path from JSON input using bash only
extract_transcript() {
  if [[ "$INPUT" =~ \"transcript_path\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    echo "${BASH_REMATCH[1]}"
  fi
}

# Extract the cd target from the command (e.g., "cd /tmp/worktree && git push")
# Hooks run in the main repo CWD, not the agent's cd target. This helper
# lets us find the .zskills/tracked pipeline marker (legacy .zskills-tracked
# during the dual-read window) in the correct directory for worktree agents.
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

# --- main_protected access control ---
# Reads config at runtime (not baked in during /update-zskills).
# Changing the config takes effect immediately.
is_main_protected() {
  local config_file
  local repo_root="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  config_file="$repo_root/.claude/zskills-config.json"
  if [ -f "$config_file" ]; then
    local content
    content=$(cat "$config_file" 2>/dev/null) || return 1
    if [[ "$content" =~ \"main_protected\"[[:space:]]*:[[:space:]]*true ]]; then
      return 0
    fi
  fi
  return 1
}

is_on_main() {
  # Answer "is the agent operating on main?" — must reflect the WORKTREE the
  # agent is in, not the hook's ambient cwd. Hooks run in a separate process
  # rooted at $CLAUDE_PROJECT_DIR (the main repo); when the agent runs
  # `cd /tmp/wt && git commit ...` from a feature-branch worktree, the hook's
  # own `git rev-parse` would report "main" and wrongly block the commit.
  # Precedence: $REPO_ROOT env (test override) → cd target extracted from the
  # command (worktree-cd case) → ambient cwd (main-repo invocation).
  local branch
  local repo_root="${REPO_ROOT:-}"
  if [ -z "$repo_root" ]; then
    local cd_target
    cd_target=$(extract_cd_target)
    if [ -n "$cd_target" ]; then
      repo_root="$cd_target"
    else
      repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    fi
  fi
  branch=$(git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null)
  [[ "$branch" == "main" || "$branch" == "master" ]]
}

# ── Enforcement roots (ENFORCEMENT_V2_PLAN Phase 3, #1159) ─────────────────
# Hoisted ABOVE the first deny site (the recursive-.zskills-delete block below)
# so all 17 gate_with_reason sites resolve the same two predicate/toggle roots.
# Both computations keep their `${VAR:-…}` env-override guards, so the later
# per-section TRACKING_ROOT / LOCAL_ROOT recomputations (in the commit /
# cherry-pick / push blocks) no-op idempotently.
#   ENF_ROOT  = TRACKING_ROOT — the MAIN root (git-common-dir parent), the
#               toggle-file root + the predicate's main-root marker/sentinel arm
#               (same git-common-dir-parent CORE as config_root; an empty value
#               in a non-git context makes the toggle path unresolvable → the lib
#               serves shipped defaults, fail-closed). Env-overridable for tests.
#   ENF_LOCAL = LOCAL_ROOT — the effective local root (env override → cd-target →
#               git toplevel/pwd), the SAME root the Tier-1 TRACKED_MARKER read
#               uses, so the predicate's tracked-marker arm aligns: a live
#               pipeline's worktree agents stay enforced.
TRACKING_ROOT="${TRACKING_ROOT:-$(cd "$(git rev-parse --git-common-dir 2>/dev/null || echo .git)/.." && pwd)}"
LOCAL_ROOT=$(resolve_effective_worktree_root "${LOCAL_ROOT:-}" "$(extract_cd_target)" "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
ENF_ROOT="$TRACKING_ROOT"
ENF_LOCAL="$LOCAL_ROOT"

# ─── Tracking file protection ───
# Block recursive deletion of tracking directory.
# The `-r` / `-R` / `--recursive` flag must be a standalone token (preceded
# by whitespace, not mid-word), AND both the flag and `.zskills/tracking`
# must live in the same shell command (no ; & | crossing). The earlier
# unanchored pattern matched ANY `-word-with-r` substring in the rm's
# buffer (incl. `-tracked` inside `.zskills-tracked` pathnames and unrelated
# long flags like `--worktree` / `--branch` later in the same multi-line
# bash blob). Past failure: `rm -f X; bash ... --worktree ... .zskills/tracking/...`
# false-positived because `--worktree`'s `-r-letters` satisfied the flag
# slot mid-regex.
if [[ "$COMMAND" =~ rm[[:space:]]+([^\;\&\|]*[[:space:]])?(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)([[:space:]]|$)[^\;\&\|]*\.zskills ]]; then
  gate_with_reason fs_destructive zskills_tree_delete hard "BLOCKED: Cannot recursively delete inside .zskills/. The tree holds tracking markers, audit history, issues, monitor state, and dashboard runtime. To clear tracking specifically: ! bash .claude/skills/update-zskills/scripts/clear-tracking.sh"
fi

# Block agent execution of clear-tracking script (reading is OK).
# Matches bash|sh only at a command-verb boundary:
#   - start of the JSON command field (`"command":"`)
#   - command separator (`;`, `&`, `|`, `(`, backtick)
#   - start of input
# Bare whitespace is NOT a boundary (that's what caused echo-string false
# positives: `echo "Run: bash scripts/clear-tracking.sh"` has a space before
# `bash` but the `bash` there is data, not a command verb).
_CT_EXEC_CMD='(^|[;&|(`]|"command":")[[:space:]]*(bash|sh)[[:space:]][^;&|"]*clear-tracking'
_CT_EXEC_DIR='(^|[;&|(`]|"command":")[[:space:]]*\./[^[:space:]"]*clear-tracking'
if [[ "$COMMAND" =~ $_CT_EXEC_CMD ]] || [[ "$COMMAND" =~ $_CT_EXEC_DIR ]]; then
  gate_with_reason fs_destructive clear_tracking_agent hard "BLOCKED: Only the user can run the clear-tracking script. Run: ! bash .claude/skills/update-zskills/scripts/clear-tracking.sh"
fi

# ─── Config file ───
# Config lives at .claude/zskills-config.json. It is user-managed; no custom
# hook protects it. Writes to .claude/ may or may not prompt depending on the
# user's permission mode — no file-specific rule exists. Agents that own the
# config (e.g. /update-zskills) may write it directly.

# ─── CONFIGURE: remove this section if you don't use session logging ───
# git add .claude/logs/ (sweeps in all sessions' logs -- stage specific files)
if [[ "$COMMAND" =~ git[[:space:]]+add[[:space:]]+\.claude/logs/?([[:space:]]|$) ]]; then
  gate_with_reason git_discipline logs_add_all demotable "BLOCKED: git add .claude/logs/ sweeps in ALL sessions' logs. Stage your session's logs by name: git add .claude/logs/*-<session-id>*.md"
fi

# ─── CONFIGURE: set your test command patterns ────────────────────────
# Piping test output (loses failures, forces re-runs -- capture to file instead)
#
# ─── Runtime config read (eliminates install-time drift) ───
# Config location: .claude/zskills-config.json in the checked-out tree.
# --show-toplevel matches the existing is_main_protected() pattern at
# line 146; in a worktree, this returns the worktree root, which is
# correct — the config is git-tracked, so each worktree reads its own
# branch-current version.
_ZSK_REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
_ZSK_CFG="$_ZSK_REPO_ROOT/.claude/zskills-config.json"
UNIT_TEST_CMD=""
FULL_TEST_CMD=""
UI_FILE_PATTERNS=""
TEST_OUTPUT_FILE=""
if [ -f "$_ZSK_CFG" ]; then
  _ZSK_CFG_BODY=$(cat "$_ZSK_CFG" 2>/dev/null) || _ZSK_CFG_BODY=""
  if [[ "$_ZSK_CFG_BODY" =~ \"unit_cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    UNIT_TEST_CMD="${BASH_REMATCH[1]}"
  fi
  if [[ "$_ZSK_CFG_BODY" =~ \"full_cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    FULL_TEST_CMD="${BASH_REMATCH[1]}"
  fi
  # ui.file_patterns: scope via enclosing "ui" object to disambiguate
  # from testing.file_patterns (array, doesn't match the string regex
  # anyway, but prefix scoping is defensive against future schema change).
  if [[ "$_ZSK_CFG_BODY" =~ \"ui\"[[:space:]]*:[[:space:]]*\{[^}]*\"file_patterns\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    UI_FILE_PATTERNS="${BASH_REMATCH[1]}"
  fi
  # testing.output_file: per-project test-output filename (default
  # ".test-results.txt" applied at use-site, NOT here — this var stays
  # empty when unset so the suggestion-message text knows whether to
  # show the configured value or the doc default).
  if [[ "$_ZSK_CFG_BODY" =~ \"output_file\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    TEST_OUTPUT_FILE="${BASH_REMATCH[1]}"
  fi
  unset _ZSK_CFG_BODY
fi

# Test-infra detection — same list as skills/verify-changes/SKILL.md
# (test-infra-patterns.txt is the canonical source enforced by the sync
# test in tests/test-hooks.sh + tests/test-skill-conformance.sh).
# Patterns: package.json with a "test" script, vitest.config.*,
# jest.config.*, pytest.ini, .mocharc.*, Makefile, tests/*.sh, tests/*.py,
# tests/*.js. Used by the three-case test-pipe gate below to distinguish
# "no test infra" (legitimate skip) from "infra exists but no full_cmd"
# (misconfiguration → deny pointing at /update-zskills).
TEST_INFRA_DETECTED=0
if [ -f "$_ZSK_REPO_ROOT/package.json" ] && \
   grep -q '"test"[[:space:]]*:' "$_ZSK_REPO_ROOT/package.json" 2>/dev/null; then
  TEST_INFRA_DETECTED=1
fi
if [ "$TEST_INFRA_DETECTED" -eq 0 ]; then
  for _zsk_pat in \
      "$_ZSK_REPO_ROOT"/vitest.config.* \
      "$_ZSK_REPO_ROOT"/jest.config.* \
      "$_ZSK_REPO_ROOT"/pytest.ini \
      "$_ZSK_REPO_ROOT"/.mocharc.* \
      "$_ZSK_REPO_ROOT"/Makefile \
      "$_ZSK_REPO_ROOT"/tests/*.sh \
      "$_ZSK_REPO_ROOT"/tests/*.py \
      "$_ZSK_REPO_ROOT"/tests/*.js; do
    if [ -e "$_zsk_pat" ]; then
      TEST_INFRA_DETECTED=1
      break
    fi
  done
  unset _zsk_pat
fi
unset _ZSK_REPO_ROOT _ZSK_CFG

# Escape every bash-regex metacharacter that might appear in a config
# test-command string (parens, brackets, pipe, asterisk, plus, etc.).
# Then re-space spaces to [[:space:]]+ so "bash  tests/run-all.sh"
# (multiple spaces) still matches.
#
# Bash parameter-expansion quoting note: inside ${var//pat/replace}, `pat`
# is a glob pattern. `?` matches any single char, `[...]` is a class,
# `}` closes the expansion early. We use `[?]` (literal-? class) for the
# `?` rule and `\\\}` (escaped closer) for the `}` rule to work around these.
_zsk_regex_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//./\\.}"
  s="${s//\(/\\(}"
  s="${s//\)/\\)}"
  s="${s//\[/\\[}"
  s="${s//\]/\\]}"
  s="${s//|/\\|}"
  s="${s//\*/\\*}"
  s="${s//+/\\+}"
  s="${s//[?]/\\?}"
  s="${s//\$/\\\$}"
  s="${s//^/\\^}"
  s="${s//\{/\\{}"
  s="${s//\}/\\\}}"
  s="${s// /[[:space:]]+}"
  printf '%s' "$s"
}

# Three-case test-pipe gate (mirrors skills/verify-changes/SKILL.md
# test-command resolution). The opinionated npm-specific fallback that
# previously sat in the suggestion-message text was removed in Phase 3
# of SKILL_FILE_DRIFT_FIX: empty FULL_TEST_CMD is now classified by the
# three-case tree below, not silently defaulted to a hardcoded command.
#
#   Case A — FULL_TEST_CMD set: gate operates as today (existing pattern check).
#   Case B — FULL_TEST_CMD empty AND no test infra detected: skip the gate
#            entirely (legitimate state for docs-only / greenfield projects).
#            Logs to stderr once so an operator sees the reason.
#   Case C — FULL_TEST_CMD empty BUT test infra detected: misconfiguration.
#            Deny the bash invocation with an explicit message pointing at
#            /update-zskills. Forces the user to configure testing.full_cmd
#            so the test-pipe gate (and downstream commit-transcript gate)
#            can function.
if [ -n "$FULL_TEST_CMD" ]; then
  # Case A — gate operates as today.
  ESCAPED_UNIT=""
  ESCAPED_FULL=""
  [ -n "$UNIT_TEST_CMD" ] && ESCAPED_UNIT="$(_zsk_regex_escape "$UNIT_TEST_CMD")"
  [ -n "$FULL_TEST_CMD" ] && ESCAPED_FULL="$(_zsk_regex_escape "$FULL_TEST_CMD")"
  # Only alternate non-empty vars to avoid "(|cmd)" degenerate case.
  if [ -n "$ESCAPED_UNIT" ] && [ -n "$ESCAPED_FULL" ]; then
    TEST_PIPE_PATTERN="(${ESCAPED_UNIT}|${ESCAPED_FULL})"
  elif [ -n "$ESCAPED_UNIT" ]; then
    TEST_PIPE_PATTERN="${ESCAPED_UNIT}"
  else
    TEST_PIPE_PATTERN="${ESCAPED_FULL}"
  fi

  # Split on &&, ||, ; so the pipe check only fires when the pipe is in
  # the SAME segment as the test command (otherwise an unrelated `ls | head`
  # earlier in the command falsely trips the block).
  _TEST_SEP=$'\x01'
  _TEST_NORM="${INPUT//&&/$_TEST_SEP}"
  _TEST_NORM="${_TEST_NORM//||/$_TEST_SEP}"
  _TEST_NORM="${_TEST_NORM//;/$_TEST_SEP}"
  IFS=$'\x01' read -ra _TEST_SEGMENTS <<< "$_TEST_NORM"
  for _seg in "${_TEST_SEGMENTS[@]}"; do
    if [[ "$_seg" =~ $TEST_PIPE_PATTERN ]] && [[ "$_seg" == *'|'* ]]; then
      gate_with_reason git_discipline test_pipe demotable "Don't pipe test output -- it loses failure details. Instead: TEST_OUT=\"/tmp/zskills-tests/\$(basename \"\$(pwd)\")\"; mkdir -p \"\$TEST_OUT\"; ${FULL_TEST_CMD} > \"\$TEST_OUT/${TEST_OUTPUT_FILE:-.test-results.txt}\" 2>&1 then read \"\$TEST_OUT/${TEST_OUTPUT_FILE:-.test-results.txt}\" to inspect failures."
    fi
  done
  unset _TEST_SEP _TEST_NORM _TEST_SEGMENTS _seg
elif [ "$TEST_INFRA_DETECTED" -eq 1 ]; then
  # Case C — test infra exists but FULL_TEST_CMD is empty. The
  # pattern-based gate can't function. Refuse only on commands that
  # LOOK like piped test invocations (heuristic on common test verbs)
  # so the user is told to fix the config without locking them out of
  # unrelated bash. Heuristic spans: npm test/run test, pytest, vitest,
  # jest, mocha, make test, bash|sh tests/ — same surface as the
  # test-infra detection list above.
  _TEST_SEP=$'\x01'
  _TEST_NORM="${INPUT//&&/$_TEST_SEP}"
  _TEST_NORM="${_TEST_NORM//||/$_TEST_SEP}"
  _TEST_NORM="${_TEST_NORM//;/$_TEST_SEP}"
  IFS=$'\x01' read -ra _TEST_SEGMENTS <<< "$_TEST_NORM"
  for _seg in "${_TEST_SEGMENTS[@]}"; do
    if [[ "$_seg" == *'|'* ]] && \
       [[ "$_seg" =~ (npm[[:space:]]+(run[[:space:]]+)?test|pytest|vitest|jest|mocha|make[[:space:]]+test|(bash|sh)[[:space:]]+tests/) ]]; then
      gate_with_reason git_discipline full_cmd_unset demotable "BLOCKED: project has test infrastructure (package.json test script, vitest/jest/pytest config, Makefile, or tests/*.sh|*.py|*.js files) but testing.full_cmd is empty in .claude/zskills-config.json. The test-pipe gate cannot function without it. Run /update-zskills to configure testing.full_cmd, or edit .claude/zskills-config.json directly."
    fi
  done
  unset _TEST_SEP _TEST_NORM _TEST_SEGMENTS _seg
else
  # Case B — no test infra and no configured command. Legitimate state
  # for docs-only / greenfield / all-manual-testing projects. Skip the
  # gate. Log once to stderr so an operator can see why no test enforcement
  # is happening on this project.
  echo "# /verify-changes: no test infra detected; test-pipe gate disabled" >&2
fi

# --- main_protected: block git commit on main ---
# Wrapper-recursion via is_git_subcommand_in_wrappers (#399) closes
# `bash -c 'git commit'` / `eval 'git commit'` bypass.
if is_git_subcommand_in_wrappers "$COMMAND" commit && is_main_protected && is_on_main; then
  gate_with_reason main_protection commit_on_main demotable "BLOCKED: main branch is protected (main_protected: true in .claude/zskills-config.json). Create a feature branch or use PR mode. To change: edit .claude/zskills-config.json"
fi

# ─── CONFIGURE: set your full test command ────────────────────────────
# Safety net: transcript-based verification on git commit
# Ensures tests were run before committing code files. Wrapper-recursion
# via is_git_subcommand_in_wrappers (#399) catches wrapper-bypass forms.
if is_git_subcommand_in_wrappers "$COMMAND" commit; then
  TRANSCRIPT=$(extract_transcript)
  if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    FULL_TEST_CHECK="${FULL_TEST_CMD}"
    # Check if full test command was run in this session
    TRANSCRIPT_CONTENT=$(cat "$TRANSCRIPT" 2>/dev/null) || TRANSCRIPT_CONTENT=""
    if [[ "$TRANSCRIPT_CONTENT" != *"$FULL_TEST_CHECK"* ]]; then
      # Check if any code files are being committed (skip check for content-only)
      DIFF_OUTPUT=$(git diff --cached --name-only 2>/dev/null)
      CODE_FILES=""
      while IFS= read -r line; do
        if [[ "$line" =~ \.(js|ts|json|css|html|rs|py|go|rb)$ ]]; then
          CODE_FILES+="$line"$'\n'
        fi
      done <<< "$DIFF_OUTPUT"
      if [ -n "$CODE_FILES" ]; then
        gate_with_reason git_discipline tests_not_run demotable "BLOCKED: Committing code but '${FULL_TEST_CHECK}' was not found in the session transcript. Run tests before committing. (Content-only commits are exempt.)"
      fi
    fi

    # ─── CONFIGURE: set your UI source paths, or remove this section if not applicable ───
    # Check if UI files changed but no playwright-cli verification.
    # UI_FILE_PATTERNS is initialized at the top from .claude/zskills-config.json (ui.file_patterns).
    if [ -n "$UI_FILE_PATTERNS" ]; then
      UI_DIFF_OUTPUT=$(git diff --cached --name-only 2>/dev/null)
      UI_FILES=""
      while IFS= read -r line; do
        if [[ "$line" =~ $UI_FILE_PATTERNS ]]; then
          UI_FILES+="$line"$'\n'
        fi
      done <<< "$UI_DIFF_OUTPUT"
      if [ -n "$UI_FILES" ]; then
        TRANSCRIPT_CONTENT="${TRANSCRIPT_CONTENT:-$(cat "$TRANSCRIPT" 2>/dev/null)}" || TRANSCRIPT_CONTENT=""
        if [[ "$TRANSCRIPT_CONTENT" != *'playwright-cli'* ]]; then
          gate_with_reason git_discipline ui_unverified demotable "BLOCKED: UI files changed but no playwright-cli verification found in session transcript. Verify UI changes before committing. Changed files: $(echo $UI_FILES | tr '\n' ', ')"
        fi
      fi
    fi
  fi

  # ─── Tracking enforcement (delegation + step verification) ───
  # Hook uses git-common-dir to find tracking markers from worktrees.
  # TRACKING_ROOT resolves to main repo root in both main repo and worktrees.
  # Overridable via env var for testing.
  TRACKING_ROOT="${TRACKING_ROOT:-$(cd "$(git rev-parse --git-common-dir 2>/dev/null || echo .git)/.." && pwd)}"
  TRACKING_DIR="$TRACKING_ROOT/.zskills/tracking"

  # Pipeline association guard: determine if this session belongs to a tracked
  # pipeline and extract its pipeline ID for scoping.
  #
  # Tier 1: pipeline-id marker file in LOCAL repo root (worktree agents).
  #   Written by orchestrator before dispatching — cannot be skipped by agent.
  #   Dual-read (INSTALL_REDESIGN Phase 8): .zskills/tracked is the live
  #   path; the legacy root .zskills-tracked is read as fallback for
  #   worktrees created before the consolidation. New path wins when both.
  #
  # Tier 2: ZSKILLS_PIPELINE_ID=<id> in transcript (orchestrators on main).
  #   Orchestrator echoes this early in execution. The transcript is a stable
  #   append-only JSONL file (survives context compaction). Uses LAST match
  #   so sequential /run-plan invocations in the same session work correctly.
  #
  # Neither → unrelated session → skip enforcement → parallel work unblocked.
  # Resolve LOCAL_ROOT via shared helper (#401): env-override (test hook) →
  # cd target (worktree agents invoking `cd /tmp/wt && git commit`) →
  # git-rev-parse fallback (hook's ambient main-repo CWD).
  LOCAL_ROOT=$(resolve_effective_worktree_root "${LOCAL_ROOT:-}" "$(extract_cd_target)" "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
  PIPELINE_ID=""
  TRACKING_SESSION_HAS_PIPELINE=false

  # Tier 1: pipeline-id marker in LOCAL root (worktree agents) — dual-read
  TRACKED_MARKER="$LOCAL_ROOT/.zskills/tracked"
  [ -f "$TRACKED_MARKER" ] || TRACKED_MARKER="$LOCAL_ROOT/.zskills-tracked"
  if [ -f "$TRACKED_MARKER" ]; then
    PIPELINE_ID=$(cat "$TRACKED_MARKER" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$PIPELINE_ID" ]; then
      TRACKING_SESSION_HAS_PIPELINE=true
    fi
  fi

  # Tier 2: ZSKILLS_PIPELINE_ID in transcript (orchestrators on main)
  if ! $TRACKING_SESSION_HAS_PIPELINE && [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    PIPELINE_ID=$(grep -o 'ZSKILLS_PIPELINE_ID=[^[:space:]"]*' "$TRANSCRIPT" 2>/dev/null | tail -1 | cut -d= -f2)
    if [ -n "$PIPELINE_ID" ]; then
      TRACKING_SESSION_HAS_PIPELINE=true
    fi
  fi

  # Skip if tracking dir doesn't exist (backward compatible)
  # OR if this session is not associated with any pipeline
  if [ -d "$TRACKING_DIR" ] && $TRACKING_SESSION_HAS_PIPELINE; then

    # Check if any code files are being committed (skip check for content-only)
    if [ -z "$CODE_FILES" ]; then
      DIFF_OUTPUT=$(git -C "$LOCAL_ROOT" diff --cached --name-only 2>/dev/null)
      CODE_FILES=""
      while IFS= read -r line; do
        if [[ "$line" =~ \.(js|ts|json|css|html|rs|py|go|rb)$ ]]; then
          CODE_FILES+="$line"$'\n'
        fi
      done <<< "$DIFF_OUTPUT"
    fi

    if [ -n "$CODE_FILES" ]; then

      PIPELINE_SUBDIR="$TRACKING_DIR/$PIPELINE_ID"

      # Delegation check at commit-time.
      #
      # The carve-out below applies ONLY to `requires.land-pr.*` markers,
      # not the whole `requires.*` family. `requires.land-pr.<id>` can only
      # be fulfilled AFTER the PR merge happens, so blocking a feature-branch
      # commit on it would deadlock — that's the original #547 reason.
      # `requires.verify-changes.<id>` is fundamentally different: the verifier
      # CAN and SHOULD run BEFORE any commit lands, on the feature branch
      # itself. Blanket-skipping all `requires.*` on feature branches let
      # PR #980 land with `requires.verify-changes.doc-viewer` unfulfilled
      # (issue #986).
      #
      # Decision tree (per marker, evaluated inside the loop):
      #   requires.land-pr.*  + feature branch → defer (would deadlock)
      #   requires.land-pr.*  + main           → enforce (PR #211 intent)
      #   requires.<other>.*  + any branch     → enforce (the #986 fix)
      if [ -n "$PIPELINE_ID" ] && [ -d "$PIPELINE_SUBDIR" ]; then
        for req in "$PIPELINE_SUBDIR"/requires.*; do
          [ -e "$req" ] || continue
          # Defer requires.land-pr.* on feature branches (deadlock avoidance).
          if [[ "$(basename "$req")" =~ ^requires\.land-pr\. ]] && ! is_on_main; then
            continue
          fi
          enforce_requires_marker "$req" "committing"
        done
      fi

      # Step enforcement: implement needs verify
      # Subdir-only reader (Phase 6: dual-read fallback removed; all writers migrated).
      if [ -n "$PIPELINE_ID" ] && [ -d "$PIPELINE_SUBDIR" ]; then
        for impl in "$PIPELINE_SUBDIR"/step.*.implement; do
          [ -e "$impl" ] || continue
          enforce_step_implement_marker "$impl" "committing"
        done
      fi

      # Step enforcement: verify needs report
      # Subdir-only reader (Phase 6: dual-read fallback removed; all writers migrated).
      if [ -n "$PIPELINE_ID" ] && [ -d "$PIPELINE_SUBDIR" ]; then
        for verif in "$PIPELINE_SUBDIR"/step.*.verify; do
          [ -e "$verif" ] || continue
          enforce_step_verify_marker "$verif" "committing"
        done
      fi
    fi
  fi
fi

# --- main_protected: block git cherry-pick on main ---
# Wrapper-recursion via is_git_subcommand_in_wrappers (#399) closes
# `bash -c 'git cherry-pick'` / `eval 'git cherry-pick'` bypass.
if is_git_subcommand_in_wrappers "$COMMAND" cherry-pick && is_main_protected && is_on_main; then
  gate_with_reason main_protection cherry_pick_on_main demotable "BLOCKED: main branch is protected (main_protected: true in .claude/zskills-config.json). Cherry-pick to a feature branch instead. To change: edit .claude/zskills-config.json"
fi

# Safety net: transcript-based verification on git cherry-pick
# Cherry-picks replay existing commits and bypass the commit hook above.
# Wrapper-recursion via is_git_subcommand_in_wrappers (#399).
if is_git_subcommand_in_wrappers "$COMMAND" cherry-pick; then
  TRANSCRIPT=$(extract_transcript)
  if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    FULL_TEST_CHECK="${FULL_TEST_CMD}"
    TRANSCRIPT_CONTENT=$(cat "$TRANSCRIPT" 2>/dev/null) || TRANSCRIPT_CONTENT=""
    if [[ "$TRANSCRIPT_CONTENT" != *"$FULL_TEST_CHECK"* ]]; then
      gate_with_reason git_discipline tests_not_run demotable "BLOCKED: git cherry-pick but '${FULL_TEST_CHECK}' was not found in the session transcript. Run tests before landing code on main."
    fi
  fi

  # ─── Tracking enforcement (delegation + step verification) ───
  TRACKING_ROOT="${TRACKING_ROOT:-$(cd "$(git rev-parse --git-common-dir 2>/dev/null || echo .git)/.." && pwd)}"
  TRACKING_DIR="$TRACKING_ROOT/.zskills/tracking"

  # Pipeline association guard (same two-tier logic as commit block).
  # Resolve LOCAL_ROOT via shared helper (#401): env-override (test hook) →
  # cd target (worktree agents invoking `cd /tmp/wt && git cherry-pick`) →
  # git-rev-parse fallback (hook's ambient main-repo CWD).
  LOCAL_ROOT=$(resolve_effective_worktree_root "${LOCAL_ROOT:-}" "$(extract_cd_target)" "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
  PIPELINE_ID=""
  TRACKING_SESSION_HAS_PIPELINE=false

  # Tier 1: pipeline-id marker in LOCAL root (worktree agents) — dual-read
  TRACKED_MARKER="$LOCAL_ROOT/.zskills/tracked"
  [ -f "$TRACKED_MARKER" ] || TRACKED_MARKER="$LOCAL_ROOT/.zskills-tracked"
  if [ -f "$TRACKED_MARKER" ]; then
    PIPELINE_ID=$(cat "$TRACKED_MARKER" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$PIPELINE_ID" ]; then
      TRACKING_SESSION_HAS_PIPELINE=true
    fi
  fi

  # Tier 2: ZSKILLS_PIPELINE_ID in transcript (orchestrators on main)
  if ! $TRACKING_SESSION_HAS_PIPELINE && [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    PIPELINE_ID=$(grep -o 'ZSKILLS_PIPELINE_ID=[^[:space:]"]*' "$TRANSCRIPT" 2>/dev/null | tail -1 | cut -d= -f2)
    if [ -n "$PIPELINE_ID" ]; then
      TRACKING_SESSION_HAS_PIPELINE=true
    fi
  fi

  if [ -d "$TRACKING_DIR" ] && $TRACKING_SESSION_HAS_PIPELINE; then

    PIPELINE_SUBDIR="$TRACKING_DIR/$PIPELINE_ID"

    # Delegation check: requires.* must have matching fulfilled.*
    # Subdir-only reader (Phase 6: dual-read fallback removed; all writers migrated).
    if [ -n "$PIPELINE_ID" ] && [ -d "$PIPELINE_SUBDIR" ]; then
      for req in "$PIPELINE_SUBDIR"/requires.*; do
        [ -e "$req" ] || continue
        enforce_requires_marker "$req" "landing"
      done
    fi

    # Step enforcement: implement needs verify
    # Subdir-only reader (Phase 6: dual-read fallback removed; all writers migrated).
    if [ -n "$PIPELINE_ID" ] && [ -d "$PIPELINE_SUBDIR" ]; then
      for impl in "$PIPELINE_SUBDIR"/step.*.implement; do
        [ -e "$impl" ] || continue
        enforce_step_implement_marker "$impl" "landing"
      done
    fi

    # Step enforcement: verify needs report
    # Subdir-only reader (Phase 6: dual-read fallback removed; all writers migrated).
    if [ -n "$PIPELINE_ID" ] && [ -d "$PIPELINE_SUBDIR" ]; then
      for verif in "$PIPELINE_SUBDIR"/step.*.verify; do
        [ -e "$verif" ] || continue
        enforce_step_verify_marker "$verif" "landing"
      done
    fi
  fi
fi

# Safety net: tracking enforcement on git push
# Push is the landing gate for PR mode — same tracking checks as commit/cherry-pick.
# Wrapper-recursion via is_git_subcommand_in_wrappers (#399).
if is_git_subcommand_in_wrappers "$COMMAND" push; then
  TRACKING_ROOT="${TRACKING_ROOT:-$(cd "$(git rev-parse --git-common-dir 2>/dev/null || echo .git)/.." && pwd)}"
  TRACKING_DIR="$TRACKING_ROOT/.zskills/tracking"

  # Pipeline association guard (same two-tier logic as commit/cherry-pick blocks).
  # Resolve LOCAL_ROOT via shared helper (#401): env-override (test hook) →
  # cd target (worktree agents invoking `cd /tmp/wt && git push`) →
  # git-rev-parse fallback (hook's ambient main-repo CWD).
  LOCAL_ROOT=$(resolve_effective_worktree_root "${LOCAL_ROOT:-}" "$(extract_cd_target)" "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
  PIPELINE_ID=""
  TRACKING_SESSION_HAS_PIPELINE=false

  # Tier 1: pipeline-id marker in LOCAL root (worktree agents) — dual-read
  TRACKED_MARKER="$LOCAL_ROOT/.zskills/tracked"
  [ -f "$TRACKED_MARKER" ] || TRACKED_MARKER="$LOCAL_ROOT/.zskills-tracked"
  if [ -f "$TRACKED_MARKER" ]; then
    PIPELINE_ID=$(cat "$TRACKED_MARKER" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$PIPELINE_ID" ]; then
      TRACKING_SESSION_HAS_PIPELINE=true
    fi
  fi

  # Tier 2: ZSKILLS_PIPELINE_ID in transcript (orchestrators on main)
  if ! $TRACKING_SESSION_HAS_PIPELINE; then
    TRANSCRIPT=$(extract_transcript)
    if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
      PIPELINE_ID=$(grep -o 'ZSKILLS_PIPELINE_ID=[^[:space:]"]*' "$TRANSCRIPT" 2>/dev/null | tail -1 | cut -d= -f2)
      if [ -n "$PIPELINE_ID" ]; then
        TRACKING_SESSION_HAS_PIPELINE=true
      fi
    fi
  fi

  if [ -d "$TRACKING_DIR" ] && $TRACKING_SESSION_HAS_PIPELINE; then

    # Check if any code files are in the push (compare local branch to remote tracking)
    # Use -C to run git in the cd target dir (worktree), not main repo CWD
    GIT_ARGS=""
    if [ -n "$CD_TARGET" ]; then
      GIT_ARGS="-C $CD_TARGET"
    fi
    CODE_FILES=""
    # Compute "is there code in this push" as the pipeline's OWN changes
    # (merge-base..HEAD), NOT @{u}..HEAD (#921). Rationale: /land-pr's
    # legitimate BEHIND-clear rebases onto a moved origin/main and
    # force-pushes BEFORE merge — but requires.land-pr.<id> is only
    # fulfilled AFTER merge (Step 8b). With @{u}..HEAD, @{u} is the OLD
    # pushed commit, so the range picks up MAIN's intervening commits'
    # code (other PRs that landed), making CODE_FILES non-empty and
    # firing the still-unfulfilled requires.land-pr.<id> gate —
    # chicken-and-egg (can't push to clear BEHIND). The merge-base form
    # counts ONLY this pipeline's own changes, so a rebase-and-force-push
    # of an unchanged patch presents no NEW code and the gate doesn't
    # fire; it still fires on a genuine un-landed-code push. Mirrors the
    # verifier's documented merge-base diff convention
    # (.claude/agents/verifier.md). origin/main is the base ref: this
    # repo is main-based and there is no existing base-branch variable in
    # this hook to reuse.
    MERGE_BASE=$(git $GIT_ARGS merge-base origin/main HEAD 2>/dev/null)
    if [ -n "$MERGE_BASE" ]; then
      PUSH_DIFF=$(git $GIT_ARGS diff --name-only "$MERGE_BASE"..HEAD 2>/dev/null)
    else
      # Fallback: origin/main not fetched / merge-base unavailable in this
      # hook context. Fall back to the prior @{u}..HEAD behavior (then
      # main..HEAD) rather than passing everything — fail toward the SAFE
      # (old, enforcing) behavior, not toward open.
      PUSH_DIFF=$(git $GIT_ARGS diff --name-only @{u}..HEAD 2>/dev/null)
      if [ -z "$PUSH_DIFF" ]; then
        # Compare against main (works before first push -u)
        PUSH_DIFF=$(git $GIT_ARGS diff --name-only main..HEAD 2>/dev/null)
      fi
    fi
    if [ -n "$PUSH_DIFF" ]; then
      while IFS= read -r line; do
        if [[ "$line" =~ \.(js|jsx|mjs|cjs|ts|tsx|json|css|scss|html|vue|svelte|rs|py|go|rb|java|kt|swift|c|cc|cpp|h|hpp|sh|php)$ ]]; then
          CODE_FILES+="$line"$'\n'
        fi
      done <<< "$PUSH_DIFF"
    fi

    if [ -n "$CODE_FILES" ]; then

      PIPELINE_SUBDIR="$TRACKING_DIR/$PIPELINE_ID"

      # Delegation check: requires.* must have matching fulfilled.*
      # Subdir-only reader (Phase 6: dual-read fallback removed; all writers migrated).
      if [ -n "$PIPELINE_ID" ] && [ -d "$PIPELINE_SUBDIR" ]; then
        for req in "$PIPELINE_SUBDIR"/requires.*; do
          [ -e "$req" ] || continue
          enforce_requires_marker "$req" "pushing"
        done
      fi

      # Step enforcement: implement needs verify
      # Subdir-only reader (Phase 6: dual-read fallback removed; all writers migrated).
      if [ -n "$PIPELINE_ID" ] && [ -d "$PIPELINE_SUBDIR" ]; then
        for impl in "$PIPELINE_SUBDIR"/step.*.implement; do
          [ -e "$impl" ] || continue
          enforce_step_implement_marker "$impl" "pushing"
        done
      fi

      # Step enforcement: verify needs report
      # Subdir-only reader (Phase 6: dual-read fallback removed; all writers migrated).
      if [ -n "$PIPELINE_ID" ] && [ -d "$PIPELINE_SUBDIR" ]; then
        for verif in "$PIPELINE_SUBDIR"/step.*.verify; do
          [ -e "$verif" ] || continue
          enforce_step_verify_marker "$verif" "pushing"
        done
      fi
    fi
  fi
fi

# --- main_protected: block git push to main ---
# Trade-off: this rule trusts variable-bearing push targets (e.g.,
# origin "$BRANCH"). If a skill or agent sets a push-target variable to
# "main" and pushes, this rule allows it. Acceptable because
# (1) skills derive their branch names from config + slug with default
# "feat/" prefix, so reaching branch="main" requires a buggy skill or
# adversarial description; (2) a compromised agent that controls the
# bash has easier paths (eval, concatenation, obfuscation) the hook
# cannot defend against anyway; (3) the strict alternative (block all
# variable-bearing push-target forms) produces false-positives on
# legitimate worktree-scoped pushes without closing a realistic attack
# vector.
if is_git_subcommand_in_wrappers "$COMMAND" push && is_main_protected; then
  # Scope rules (a) and (b) to JUST the `git push` command segment, not the
  # whole $COMMAND buffer. Without this, multi-statement commands like
  # `git fetch origin main && git push -u origin feat/foo` false-positive
  # because "origin main" appears in the fetch portion. Mirrors the bounded
  # extraction in block-unsafe-generic.sh:266-280.
  PUSH_CMD="$COMMAND"
  PUSH_CMD="${PUSH_CMD##*git push}"
  PUSH_ARGS=""
  for word in $PUSH_CMD; do
    case "$word" in
      "&&"*|";"*|"|"*) break ;;  # stop at command chaining
      -*) continue ;;            # skip flags (-u, --force, etc.)
      *) PUSH_ARGS="$PUSH_ARGS $word" ;;
    esac
  done
  # Resolve a bare `HEAD` refspec to the current local branch before
  # running rule (a)/(b)/(c). Git resolves `origin HEAD` server-side to the
  # current branch — from a `main` checkout this targets remote `main` and
  # defeats the main-protection regime (#515). Same family as #470 (the ref
  # spelling enumerations) but `HEAD` is special because resolution happens
  # SERVER-SIDE, not in the local parser. Substitute standalone `HEAD` /
  # `+HEAD` / `refs/heads/HEAD` tokens (and their refspec-RHS forms like
  # `feat:HEAD`) with the resolved branch so rule (a) and rule (b) match
  # against the actual target.
  _ZSK_CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)
  if [ -n "$_ZSK_CURRENT_BRANCH" ]; then
    _ZSK_NEW_ARGS=""
    for word in $PUSH_ARGS; do
      # Strip a trailing single/double quote that wrapper-unwrapped forms can
      # leave behind. `bash -c 'git push origin HEAD'` → word=HEAD' — without
      # this strip, the case-match below sees `HEAD'` (not `HEAD`), the
      # rewrite is skipped, and rules (a)/(b) downstream don't see the
      # resolved branch (#561). Strip one layer each side so quoted bash-c /
      # eval inner strings classify. Mirrors the per-word quote-strip done
      # post-extraction in block-unsafe-generic.sh:625-626.
      case "$word" in
        \'*\') word="${word#\'}"; word="${word%\'}" ;;
        \"*\") word="${word#\"}"; word="${word%\"}" ;;
      esac
      word="${word%\'}"; word="${word%\"}"
      case "$word" in
        HEAD|+HEAD|refs/heads/HEAD|+refs/heads/HEAD)
          word="$_ZSK_CURRENT_BRANCH" ;;
        *:HEAD|*:+HEAD|*:refs/heads/HEAD|*:+refs/heads/HEAD)
          word="${word%:*}:$_ZSK_CURRENT_BRANCH" ;;
      esac
      _ZSK_NEW_ARGS="$_ZSK_NEW_ARGS $word"
    done
    PUSH_ARGS="$_ZSK_NEW_ARGS"
    unset _ZSK_NEW_ARGS
  fi
  unset _ZSK_CURRENT_BRANCH
  # (a) Explicit origin main/master (optionally prefixed with + for
  # force-push or : for delete-refspec, and optionally fully-qualified as
  # refs/heads/main). Trailing class includes `'` and `"` so
  # wrapper-unwrapped forms like `bash -c 'git push origin main'` →
  # PUSH_ARGS containing trailing `main'` still match (#399). The optional
  # `refs/heads/` prefix closes the fully-qualified-ref bypass (#470).
  if [[ "$PUSH_ARGS" =~ origin[[:space:]]+[+:]?(refs/heads/)?(main|master)([[:space:]]|$|\"|\') ]]; then
    gate_with_reason main_protection push_to_main demotable "BLOCKED: Cannot push to main (main_protected: true in .claude/zskills-config.json). Push a feature branch instead. To change: edit .claude/zskills-config.json"
  fi
  # (b) Any <localref>:main or <localref>:master refspec — covers HEAD:main,
  # feat:main, abc123:main, HEAD~3:main, and the deletion form :main.
  # Past bug (#392): the old regex required `HEAD:` literal prefix, so
  # `git push origin feat:main` evaded this rule and rule (a) (which
  # requires `main` immediately after `origin`). Match any token ending
  # in `:main` or `:master` (including the empty-local deletion form).
  # Trailing class also includes `'` for wrapper-unwrapped forms (#399).
  # `[+]?` allows the force-prefix `:+main` form (#470 — pre-fix
  # `feat:+main` slipped this rule because `+` was not optional after `:`).
  # `(refs/heads/)?` allows the fully-qualified form `feat:refs/heads/main`
  # (#470).
  if [[ "$PUSH_ARGS" =~ (^|[[:space:]])[^[:space:]]*:[+]?(refs/heads/)?(main|master)([[:space:]]|$|\"|\') ]]; then
    gate_with_reason main_protection push_to_main demotable "BLOCKED: Cannot push to main (main_protected: true in .claude/zskills-config.json). Push a feature branch instead. To change: edit .claude/zskills-config.json"
  fi
  # (c) Naked push (no origin arg) while on main — based on PUSH_ARGS,
  # not full $COMMAND. An empty PUSH_ARGS means we extracted no
  # positional args from the push segment, which matches a naked
  # `git push`. Quoted-argument false-positives (e.g. grep "git push"
  # in some-file) no longer trip because the extraction loop only
  # sees tokens after the actual `git push` invocation.
  if [ -z "${PUSH_ARGS// /}" ] && is_on_main; then
    gate_with_reason main_protection push_to_main demotable "BLOCKED: Cannot push to main (main_protected: true in .claude/zskills-config.json). Push a feature branch instead. To change: edit .claude/zskills-config.json"
  fi
fi

# Legacy .claude/tracking push enforcement block removed — superseded by
# .zskills/tracking push enforcement at line 377 (with pipeline scoping,
# worktree support, and no staleness bypass).

# No match — allow. Flush any accumulated opt-in "warn" coaching messages on
# the decision-less warn channel (Settled decision 2 — never a permissionDecision)
# before allowing. Empty accumulator → emits nothing (the zero-config silent path).
zskills_enforcement_flush_warnings
exit 0
