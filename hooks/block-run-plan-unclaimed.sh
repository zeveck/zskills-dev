#!/bin/bash
# zskills-hook-version: 2026.06.1
# block-run-plan-unclaimed.sh — PreToolUse hook on Bash.
#
# Backstops the /run-plan claim-acquire prose discipline (Phase 2 of
# plans/plans-claim-chip-parity.md). Denies any Bash invocation of
# create-worktree.sh / ensure-worktree.sh whose RESOLVED branch matches
# one of the THREE /run-plan branch shapes (D7):
#   - cp-<slug>                  (finish-mode cherry-pick)
#   - cp-<slug>-phase-<N>        (single-phase cherry-pick, multi-digit)
#   - ${BRANCH_PREFIX}<slug>     (PR mode; BRANCH_PREFIX from config)
# ... and lacks a matching ${MAIN_ROOT}/.zskills/claims/plan-<slug>/.
#
# All three cp-shapes resolve to the SAME plan-scoped claim dir
# (plan-<slug>/, NOT plan-<slug>-phase-N/) — the regex captures slug
# non-greedily so the optional -phase-<N> tail is discarded.
#
# Hook contract:
#   - Reads PreToolUse JSON envelope from stdin (tool_name, tool_input.command).
#   - Filters: only Bash tool calls; only commands invoking
#     (create-worktree|ensure-worktree)\.sh.
#   - Argv tokenisation is Python shlex (NOT regex over the command string).
#   - Computes branch name via create-worktree.sh's documented precedence:
#       --branch-name <v>  OVERRIDES  --prefix-<slug>  OVERRIDES  wt-<slug>
#   - Reads BRANCH_PREFIX from ${CLAUDE_PROJECT_DIR}/.claude/zskills-config.json
#     execution.branch_prefix (default "feat/") via inline Python json.
#   - Tries TWO regexes:
#       cp-variant:  ^(cp-)([a-z0-9][a-z0-9-]*?)(-phase-[0-9]+)?$
#       pr-variant:  ^(<escaped-branch-prefix>)([a-z0-9][a-z0-9-]*)$
#   - Sources zskills-paths.sh inline (via env passthrough) to resolve
#     ZSKILLS_PLANS_DIR for the slug-is-real-plan-file pass-through.
#   - Plan-file pass-through: if no ${ZSKILLS_PLANS_DIR}/<slug>.md exists,
#     the branch is a non-plan feature branch — pass through silently.
#   - On claim-absent: emits a PreToolUse deny envelope with recovery
#     instructions citing the exact `claim-plan.sh acquire` command.
#   - Pass-through: branch doesn't match the patterns, OR slug isn't a
#     real plan file, OR sanitisation rejects the slug.
#
# Subagent composition: once registered in .claude/settings.json, this
# hook fires on EVERY Bash tool call from BOTH the orchestrator AND
# implementer/verifier subagents. The hook is filter-scoped to the two
# script names; subagent Bash calls that don't invoke them are pass-through.
#
# NOTE: Per plan R2.5, the [0-9]+ validator pattern from the issue-side
# hook is NOT applicable — plan slugs are kebab-case, not integers. The
# slug validation here is a kebab-case regex match, not numeric.

# D16(a) plugin-lane conditional-skip shim. No-op on the /update-zskills
# lane (CLAUDE_PLUGIN_ROOT unset → guard below skips the source). On the
# plugin lane it defers to a settings.json-registered copy of this hook to
# prevent double-fire when both install lanes are active. Must be the first
# executable line; the shim controls its own exit/return.
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_lib/plugin-hook-skip-if-mirrored.sh" ] && source "${CLAUDE_PLUGIN_ROOT}/hooks/_lib/plugin-hook-skip-if-mirrored.sh"

# ── Worktree-root resolvers (inlined from
# hooks/_lib/resolve-effective-worktree-root.sh, #401). Drift gate:
# tests/test-hook-helper-drift.sh. Used to resolve ENF_LOCAL (the
# tracked-marker read root) for the enforcement predicate below.
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

INPUT=$(cat) || exit 0
[ -z "$INPUT" ] && exit 0

# ── Tool-name gate ────────────────────────────────────────────────────────
TOOL_NAME=""
if [[ "$INPUT" =~ \"tool_name\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
  TOOL_NAME="${BASH_REMATCH[1]}"
fi
[ "$TOOL_NAME" = "Bash" ] || exit 0

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
  echo "block-run-plan-unclaimed.sh: WARN no working Python 3 found; hook is no-op — set ZSKILLS_PYTHON" >&2
  exit 0
fi

CMD=$("$PYTHON" - <<'PY' "$INPUT"
import json, sys
try:
    env = json.loads(sys.argv[1])
    cmd = (env.get("tool_input") or {}).get("command") or ""
    sys.stdout.write(cmd)
except Exception:
    pass
PY
)
[ -z "$CMD" ] && exit 0

# ── Filter: only create-worktree.sh / ensure-worktree.sh invocations ─────
case "$CMD" in
  *create-worktree.sh*|*ensure-worktree.sh*) ;;
  *) exit 0 ;;
esac

# ── Argv-walk via Python shlex (same shape as block-fix-issue-unclaimed.sh) ──
WALK=$("$PYTHON" - <<'PY' "$CMD"
import shlex, sys
cmd_str = sys.argv[1]
try:
    argv = shlex.split(cmd_str)
except ValueError:
    print("BRANCH=")
    print("SLUG=")
    sys.exit(0)

prefix = None
branch_name = None
positionals = []

i = 0
n = len(argv)
while i < n and not argv[i].endswith(("create-worktree.sh", "ensure-worktree.sh")):
    i += 1
i += 1  # skip past the script path itself

while i < n:
    tok = argv[i]
    if tok == "--branch-name" and i + 1 < n:
        branch_name = argv[i + 1]
        i += 2
        continue
    if tok == "--prefix" and i + 1 < n:
        prefix = argv[i + 1]
        i += 2
        continue
    if tok.startswith("--"):
        if i + 1 < n and not argv[i + 1].startswith("--"):
            i += 2
            continue
        i += 1
        continue
    positionals.append(tok)
    i += 1

slug = positionals[-1] if positionals else None

if branch_name:
    branch = branch_name
elif prefix and slug:
    branch = "{}-{}".format(prefix, slug)
elif slug:
    branch = "wt-{}".format(slug)
else:
    branch = ""

print("BRANCH=" + (branch or ""))
print("SLUG=" + (slug or ""))
PY
)

BRANCH=""
while IFS= read -r line; do
  case "$line" in
    BRANCH=*) BRANCH="${line#BRANCH=}" ;;
  esac
done <<< "$WALK"

[ -z "$BRANCH" ] && exit 0

# ── Resolve MAIN_ROOT (DA4.1 / DA7 symmetry with claim-plan.sh) ──────────
MAIN_ROOT=""
if COMMON_DIR=$(git rev-parse --git-common-dir 2>&1) && [ -n "$COMMON_DIR" ]; then
  if RESOLVED=$(cd "$COMMON_DIR/.." 2>&1 && pwd); then
    MAIN_ROOT="$RESOLVED"
  fi
fi
if [ -z "$MAIN_ROOT" ]; then
  MAIN_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
fi

# ── Read branch_prefix from config (D7 R2.1 option (b)) ──────────────────
# Default "feat/" matches the canonical preset. Inline Python json keeps
# the hook's "no jq" discipline.
CONFIG_FILE="${CLAUDE_PROJECT_DIR:-$MAIN_ROOT}/.claude/zskills-config.json"
BRANCH_PREFIX=$("$PYTHON" - <<PY "$CONFIG_FILE"
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f).get("execution", {})
    bp = d.get("branch_prefix")
    print(bp if bp else "feat/")
except Exception:
    print("feat/")
PY
)
[ -z "$BRANCH_PREFIX" ] && BRANCH_PREFIX="feat/"

# ── Match against the THREE branch shapes ────────────────────────────────
# Use Python regex for non-greedy capture + re.escape on prefix.
MATCH=$("$PYTHON" - <<PY "$BRANCH" "$BRANCH_PREFIX"
import re, sys
branch, branch_prefix = sys.argv[1], sys.argv[2]
# cp-variant (covers cp-<slug> AND cp-<slug>-phase-<N>):
m = re.match(r'^(cp-)([a-z0-9][a-z0-9-]*?)(-phase-[0-9]+)?$', branch)
if m:
    print("SLUG=" + m.group(2))
    sys.exit(0)
# pr-variant: ${BRANCH_PREFIX}<slug>
m = re.match(r'^(' + re.escape(branch_prefix) + r')([a-z0-9][a-z0-9-]*)$', branch)
if m:
    print("SLUG=" + m.group(2))
    sys.exit(0)
print("SLUG=")
PY
)

SLUG=""
case "$MATCH" in
  SLUG=*) SLUG="${MATCH#SLUG=}" ;;
esac

# No regex match -> not a /run-plan branch shape -> pass through.
[ -z "$SLUG" ] && exit 0

# Defensive: post-match validation (kebab-case). Should always pass given
# the regex, but guard against shlex pathology / future regex edits.
if ! [[ "$SLUG" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "block-run-plan-unclaimed.sh: WARN malformed slug '$SLUG' on branch '$BRANCH' — allowing" >&2
  exit 0
fi

# ── Resolve plans_dir + slug-is-real-plan-file pass-through ──────────────
# Source zskills-paths.sh to honour custom ZSKILLS_PLANS_DIR. Sourcing in
# a subshell so the hook's environment stays clean.
PLANS_DIR_RESOLVED=$(
  # Lane-portable resolution (W1.4 pattern 2): plugin lane resolves
  # zskills-paths.sh under ${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/...;
  # /update-zskills lane resolves it under the mirror
  # (.claude/skills/update-zskills/...), then the zskills source-tree
  # (skills/update-zskills/...).
  ZSK_PATHS=""
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh" ]; then
    ZSK_PATHS="${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh"
  fi
  if [ -z "$ZSK_PATHS" ]; then
    ZSK_PATHS="${MAIN_ROOT}/.claude/skills/update-zskills/scripts/zskills-paths.sh"
  fi
  if [ ! -f "$ZSK_PATHS" ]; then
    ZSK_PATHS="${MAIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh"
  fi
  if [ -f "$ZSK_PATHS" ]; then
    CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$MAIN_ROOT}" ZSKILLS_PATHS_ROOT="$MAIN_ROOT" \
      bash -c ". '$ZSK_PATHS' >/dev/null 2>&1; echo \"\$ZSKILLS_PLANS_DIR\""
  else
    echo "${MAIN_ROOT}/plans"
  fi
)
[ -z "$PLANS_DIR_RESOLVED" ] && PLANS_DIR_RESOLVED="${MAIN_ROOT}/plans"

PLAN_FILE="${PLANS_DIR_RESOLVED}/${SLUG}.md"
if [ ! -f "$PLAN_FILE" ]; then
  # Branch matched a /run-plan-like shape but there's no plan file. This
  # is a feature branch for non-plan work — pass through silently.
  exit 0
fi

# ── Claim-presence check ─────────────────────────────────────────────────
CLAIM_DIR="${MAIN_ROOT}/.zskills/claims/plan-${SLUG}"
if [ -d "$CLAIM_DIR" ]; then
  exit 0
fi

# ── Enforcement mode resolution (ENFORCEMENT_V2_PLAN Phase 2, #1159) ───────
# plan_unclaimed is a demotable tracking-discipline check: autonomous/unwatched
# → BLOCK; watched → SILENT by shipped default (or opt-in warn). ENF_ROOT (the
# MAIN root, config_root) drives the toggle loader + the predicate's main-root
# arm; ENF_LOCAL (effective local root) drives the predicate's tracked-marker
# arm. The toggle loader is invoked LAZILY only on this emitting path.
ENF_ROOT=$(zskills_enforcement_config_root)
ENF_LOCAL=$(resolve_effective_worktree_root "" "$(extract_cd_target)" "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
PRED=$(zskills_enforcement_predicate "$INPUT" "$ENF_ROOT" "$ENF_LOCAL")
zskills_enforcement_load_toggles "$ENF_ROOT/.claude/zskills-config.json"
MODE=$(zskills_enforcement_mode tracking plan_unclaimed demotable "$PRED")
case "$MODE" in
  silent|off) exit 0 ;;
esac
# Re-run WITHOUT command substitution so _ZSK_ENF_SOURCE is set in THIS shell
# (the tag formatter reads it; a $()-captured call would lose the side effect).
zskills_enforcement_mode tracking plan_unclaimed demotable "$PRED" >/dev/null

# ── Deny envelope ────────────────────────────────────────────────────────
# Lane-portable recovery-command path (W1.4 pattern 2 / F-DA1-7): on the
# plugin lane the recovery command must cite
# ${CLAUDE_PLUGIN_ROOT}/skills/run-plan/scripts/claim-plan.sh; on the
# /update-zskills lane it cites ${MAIN_ROOT}/.claude/skills/run-plan/...
# (the mirror). Resolve to whichever exists so the agent is told a command
# that actually resolves on its install lane.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/run-plan/scripts/claim-plan.sh" ]; then
  CLAIM_PLAN_PATH="${CLAUDE_PLUGIN_ROOT}/skills/run-plan/scripts/claim-plan.sh"
else
  CLAIM_PLAN_PATH="${MAIN_ROOT}/.claude/skills/run-plan/scripts/claim-plan.sh"
fi
STOP_MSG=$(cat <<EOF
STOP: create-worktree.sh for /run-plan branch '${BRANCH}' (plan slug '${SLUG}') denied — no claim found at ${MAIN_ROOT}/.zskills/claims/plan-${SLUG}/.

The /run-plan dispatch fence MUST call:

  bash ${CLAIM_PLAN_PATH} acquire ${SLUG} --pipeline-id "run-plan.${SLUG}"

immediately above the create-worktree.sh invocation. If this hook fired during a /run-plan invocation, the SKILL.md prose has drifted — STOP, do not retry, file an issue.

If acquire returns exit 10 (race lost — plan held by a concurrent pipeline), the plan is already in flight; do not double-dispatch. If exit 11 (filesystem error), abort the run.

$(zskills_enforcement_tag tracking plan_unclaimed)
EOF
)

# ── Route on resolved mode (Settled decision 14: message names its toggle) ─
# warn → DECISION-LESS systemMessage on the warn channel, command still runs;
# block → the existing deny envelope, message now ending in its toggle tag.
if [ "$MODE" = "warn" ]; then
  zskills_enforcement_warn "$STOP_MSG"
  zskills_enforcement_flush_warnings
  exit 0
fi

ESC="${STOP_MSG//\\/\\\\}"
ESC="${ESC//\"/\\\"}"
ESC="${ESC//$'\n'/\\n}"
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$ESC"
exit 0
