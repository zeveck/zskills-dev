#!/bin/bash
# zskills-hook-version: 2026.06.4
# block-main-edits.sh — PreToolUse hook on Edit / Write.
#
# Honors execution.main_protected from .claude/zskills-config.json. When
# main_protected is true, denies Edit/Write calls whose target
# file_path lives inside the main repo working tree (NOT a linked worktree),
# unless the path falls under a narrow allowlist of agent-managed surfaces
# (everything under .zskills/, and gitignored worktree-state markers).
#
# Issue #308 — closes the surface that allowed an orchestrator running on
# main to write directly to skill files, plan files, hooks, configs, and
# audit reports without the worktree discipline the worktree rule (and
# main_protected) is supposed to enforce.
#
# Non-blocking guarantees:
#   - main_protected: false in config → exit 0 (no-op).
#   - The hook's $CLAUDE_PROJECT_DIR is itself a linked worktree (rare;
#     happens when a Claude Code session was started inside a worktree)
#     → exit 0 (no-op). We block edits to MAIN, not edits inside any worktree.
#   - file_path lives outside $MAIN_ROOT → exit 0 (allow).
#   - file_path is under $MAIN_ROOT but matches the allowlist → exit 0.
#   - Otherwise → emit a PreToolUse deny envelope with a STOP message.
#
# Decision envelope follows the same shape as block-unsafe-project.sh:
#   {"hookSpecificOutput":{"hookEventName":"PreToolUse",
#                          "permissionDecision":"deny",
#                          "permissionDecisionReason":"<STOP message>"}}
#
# Test surface: tests/test-block-main-edits.sh

# D16(a) plugin-lane conditional-skip shim. No-op on the /update-zskills
# lane (CLAUDE_PLUGIN_ROOT unset → guard below skips the source). On the
# plugin lane it defers to a settings.json-registered copy of this hook to
# prevent double-fire when both install lanes are active. Must be the first
# executable line; the shim controls its own exit/return.
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_lib/plugin-hook-skip-if-mirrored.sh" ] && source "${CLAUDE_PLUGIN_ROOT}/hooks/_lib/plugin-hook-skip-if-mirrored.sh"

# Inlined from hooks/_lib/normalize-tool-path.sh (source-of-truth). Drift gate:
# tests/test-hook-helper-drift.sh. The legacy-mirror copy under .claude/hooks/
# cannot reach _lib at runtime (.claude/hooks/_lib/ is not mirrored), so the
# body is pasted in verbatim — mirroring the zskills_resolve_python convention.
# zskills_normalize_tool_path — echo a POSIX form of "$1".
#   - cygpath available  → `cygpath -u "$1"` (authoritative on MSYS/Cygwin).
#   - else pure-bash fallback:
#       * `^[A-Za-z]:[\\/]` (drive letter + sep) → `/<lowercased-drive>/<rest>`
#         with every `\` turned into `/` (e.g. `D:\a\b` → `/d/a/b`;
#         `C:/x` → `/c/x`).
#       * any stray `\` in a backslash-relative path → `/` (`rel\path` →
#         `rel/path`).
#   - A pure-POSIX path (no drive letter, no backslash) passes through
#     UNCHANGED — guaranteed no-op on Linux/Mac.
#   - Empty input → empty output.
# Side-effect free (no globals mutated); safe to call in a command
# substitution.
zskills_normalize_tool_path() {
  local p="$1"
  [ -n "$p" ] || { printf '%s' ""; return 0; }
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -u "$p"
    return 0
  fi
  # Pure-bash fallback (also the code path exercised on Linux/Mac, where
  # cygpath is absent — so this is what the unit test verifies).
  case "$p" in
    [A-Za-z]:[\\/]*)
      # Drive-letter absolute: `D:\a\b` or `C:/x`.
      local drive="${p:0:1}"
      local rest="${p:2}"
      drive="$(printf '%s' "$drive" | tr '[:upper:]' '[:lower:]')"
      rest="${rest//\\//}"
      printf '%s' "/$drive$rest"
      ;;
    *)
      # No drive letter: convert any stray backslash to forward slash. A
      # pure-POSIX path (no backslash) is returned byte-for-byte unchanged.
      printf '%s' "${p//\\//}"
      ;;
  esac
  return 0
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

# ── Target-path normalization (hoisted, ENFORCEMENT_V2_PLAN Phase 2) ───────
# Resolve a (possibly relative) Edit/Write target to an absolute, symlink-/
# dotdot-resolved path. ONE code path used by BOTH the config_hooks_tamper arm
# and the main_edit arm so the two arms normalize identically.
#   $1 = the (already POSIX-normalized) file_path
#   $2 = the base root a relative path is resolved against (MAIN_ROOT)
# Echoes the resolved absolute path. The dirname is `cd … && pwd -P`-resolved
# (the file itself may not exist yet for Write); the basename is re-attached.
normalize_target_path() {
  local _fp="$1" _base="$2" _abs _dir _bn _rdir
  case "$_fp" in
    /*) _abs="$_fp" ;;
    *)  _abs="$_base/$_fp" ;;
  esac
  _dir=$(dirname "$_abs")
  _bn=$(basename "$_abs")
  _rdir=$(cd "$_dir" 2>/dev/null && pwd -P) || _rdir="$_dir"
  printf '%s' "${_rdir%/}/$_bn"
}

INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

# ── Tool-name gate ────────────────────────────────────────────────────────
# Only fire on Edit / Write. The matcher in settings.json
# scopes the registration; this guard is defense-in-depth in case the hook
# is invoked from a broader matcher.
TOOL_NAME=""
if [[ "$INPUT" =~ \"tool_name\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
  TOOL_NAME="${BASH_REMATCH[1]}"
fi
case "$TOOL_NAME" in
  Edit|Write) ;;
  *) exit 0 ;;
esac

# ── Extract target path ───────────────────────────────────────────────────
# Edit and Write both use tool_input.file_path.
FILE_PATH=""
if [[ "$INPUT" =~ \"file_path\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
  FILE_PATH="${BASH_REMATCH[1]}"
fi
# No path extracted → can't decide → allow (defensive; never false-deny).
[ -z "$FILE_PATH" ] && exit 0

# ── Windows-native-path normalisation ─────────────────────────────────────
# On a Windows (MSYS / Git-Bash) consumer the Edit/Write tool passes a
# drive-letter / backslash path (e.g. `D:\proj\.zskills\x`). The
# `case "$FILE_PATH" in /*)` classifier below would misread it as RELATIVE
# (no leading `/`), break containment, and FALSE-DENY legitimate gitignored
# `.zskills/` writes (issue #308's carve-out is dead on Windows). Normalise to
# a POSIX form FIRST so containment (line ~127) and the `.zskills/*` carve-out
# (line ~141) match — $MAIN_ROOT is already POSIX via `pwd -P`. No-op on
# Linux/Mac (a pure-POSIX path passes through unchanged). Keep the ORIGINAL
# for the user-facing deny message.
ORIG_FILE_PATH="$FILE_PATH"
FILE_PATH="$(zskills_normalize_tool_path "$FILE_PATH")"

# ── Resolve $MAIN_ROOT ────────────────────────────────────────────────────
# $CLAUDE_PROJECT_DIR is set by Claude Code at hook fire time to the project
# root the session was started in. Fall back to git toplevel, then pwd.
# REPO_ROOT env override exists for tests.
MAIN_ROOT="${REPO_ROOT:-${CLAUDE_PROJECT_DIR:-}}"
if [ -z "$MAIN_ROOT" ]; then
  MAIN_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi
# Canonicalize MAIN_ROOT (resolve symlinks, drop trailing slash). On systems
# without readlink -f / realpath, fall back to the literal path.
RESOLVED_MAIN=$(cd "$MAIN_ROOT" 2>/dev/null && pwd -P) || RESOLVED_MAIN="$MAIN_ROOT"
MAIN_ROOT="${RESOLVED_MAIN%/}"

# ── config_hooks_tamper arm (registry row 49; Settled decision 13) ─────────
# Placed ABOVE the worktree-self early-exit and ABOVE the main_protected gate
# DELIBERATELY: this arm protects the MAIN ROOT's .claude/zskills-config.json
# (where the toggle loader reads), so a worktree-rooted session editing that
# file by absolute path must STILL be gated (DA3), and it must fire regardless
# of main_protected's value (the protection-system surface, not main content).
# The target is compared against config_root()'s config path — NOT MAIN_ROOT's
# — because in a worktree session MAIN_ROOT is the worktree while the protected
# file is the main root's (the divergence is load-bearing here).
ENF_ROOT=$(zskills_enforcement_config_root)
TAMPER_TARGET=$(normalize_target_path "$FILE_PATH" "$MAIN_ROOT")
if [ "$TAMPER_TARGET" = "$ENF_ROOT/.claude/zskills-config.json" ]; then
  # Trigger only when the edited region intersects the hooks block. For Edit
  # that is new_string OR old_string containing the `hooks` token; for Write
  # the content field. The envelope's only non-content keys (tool_name,
  # tool_input, file_path, permission_mode, transcript_path, cwd, session_id)
  # never contain `hooks`, and file_path here is the config path (…-config.json,
  # no `hooks`), so a whole-envelope substring test is an accurate proxy for
  # "the write touches a hooks-containing region" — a full-file Write of a
  # config carrying a hooks block is IN scope by design (anti-casual threat
  # model, Settled decision 13).
  if [[ "$INPUT" == *hooks* ]]; then
    PRED=$(zskills_enforcement_predicate "$INPUT" "$ENF_ROOT" "$MAIN_ROOT")
    zskills_enforcement_load_toggles "$ENF_ROOT/.claude/zskills-config.json"
    TAMPER_MODE=$(zskills_enforcement_mode main_protection config_hooks_tamper demotable "$PRED")
    if [ "$TAMPER_MODE" != "silent" ] && [ "$TAMPER_MODE" != "off" ]; then
      # Re-run WITHOUT command substitution so _ZSK_ENF_SOURCE is set in THIS
      # shell for the tag formatter (the $()-captured call above loses it).
      zskills_enforcement_mode main_protection config_hooks_tamper demotable "$PRED" >/dev/null
      TAMPER_MSG=$(cat <<EOF
STOP: Edit/Write to the project's hooks-enforcement config is gated (config_hooks_tamper).

Target: $ORIG_FILE_PATH

This write touches the \\\`hooks\\\` block of the main root's
\\\`.claude/zskills-config.json\\\` — the surface that arms/disarms the
enforcement system itself. A config-disarm is durable and cross-session, so it
must never happen invisibly.

Recovery: config changes to the \\\`hooks\\\` block need a human-reviewed edit
or a committed project review — re-enable a check by deleting its key or
setting \\\`"block"\\\` in \\\`.claude/zskills-config.json\\\` via a
human-reviewed change.

$(zskills_enforcement_tag main_protection config_hooks_tamper)
EOF
)
      if [ "$TAMPER_MODE" = "warn" ]; then
        zskills_enforcement_warn "$TAMPER_MSG"
        zskills_enforcement_flush_warnings
        exit 0
      fi
      # block
      ESC="${TAMPER_MSG//\\/\\\\}"
      ESC="${ESC//\"/\\\"}"
      ESC="${ESC//$'\n'/\\n}"
      printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$ESC"
      exit 0
    fi
  fi
fi

# ── Worktree-self check ──────────────────────────────────────────────────
# If $MAIN_ROOT itself is a linked worktree (session started in a worktree),
# this hook is a no-op — we only protect main, not whichever checkout we
# happen to live in. Divergence detection: in a linked worktree,
# `git rev-parse --git-dir` points at .git/worktrees/<name>, while
# --git-common-dir points at the main .git. They differ.
GIT_DIR=$(git -C "$MAIN_ROOT" rev-parse --git-dir 2>/dev/null)
GIT_COMMON=$(git -C "$MAIN_ROOT" rev-parse --git-common-dir 2>/dev/null)
if [ -n "$GIT_DIR" ] && [ -n "$GIT_COMMON" ]; then
  # Resolve both to absolute paths for a robust string compare. `git
  # rev-parse` returns paths relative to the cwd when it can, so they
  # need normalization before comparison.
  ABS_GIT_DIR=$(cd "$MAIN_ROOT" && cd "$GIT_DIR" 2>/dev/null && pwd -P) || ABS_GIT_DIR="$GIT_DIR"
  ABS_GIT_COMMON=$(cd "$MAIN_ROOT" && cd "$GIT_COMMON" 2>/dev/null && pwd -P) || ABS_GIT_COMMON="$GIT_COMMON"
  if [ "$ABS_GIT_DIR" != "$ABS_GIT_COMMON" ]; then
    # We are inside a linked worktree — not main. Allow.
    exit 0
  fi
fi

# ── main_protected gate ──────────────────────────────────────────────────
# Load-bearing config check (issue #308 §1). Defaults to OFF — only blocks
# when the literal `"main_protected": true` is present.
# CASCADE v2 (ENFORCEMENT_V2 Phase 4): RAISE-ONLY two-tier read — protected
# iff the project literal is true OR the user ~/.claude/zskills-config.json
# literal is true (OR-merge). The user tier can RAISE protection but never
# lower it; the fail-OPEN direction is preserved (both absent → allow).
# Read-root pin (R2-7): the project tier keeps its existing $MAIN_ROOT read;
# the user tier is the additive arm. Per-tier fail-closed: a malformed user
# file matches nothing and contributes no floor.
CONFIG_FILE="$MAIN_ROOT/.claude/zskills-config.json"
USER_CONFIG_FILE="${HOME:-}/.claude/zskills-config.json"
MAIN_PROTECTED=0
if [ -f "$CONFIG_FILE" ]; then
  CFG_CONTENT=$(cat "$CONFIG_FILE" 2>/dev/null) || CFG_CONTENT=""
  if [[ "$CFG_CONTENT" =~ \"main_protected\"[[:space:]]*:[[:space:]]*true ]]; then
    MAIN_PROTECTED=1
  fi
fi
if [ "$MAIN_PROTECTED" -ne 1 ] && [ -n "${HOME:-}" ] && [ -f "$USER_CONFIG_FILE" ]; then
  USER_CFG_CONTENT=$(cat "$USER_CONFIG_FILE" 2>/dev/null) || USER_CFG_CONTENT=""
  if [[ "$USER_CFG_CONTENT" =~ \"main_protected\"[[:space:]]*:[[:space:]]*true ]]; then
    MAIN_PROTECTED=1
  fi
fi
[ "$MAIN_PROTECTED" -eq 1 ] || exit 0

# ── Resolve target path & check containment ──────────────────────────────
# Normalize the target via the hoisted normalize_target_path (the SAME code
# path the config_hooks_tamper arm uses). If it's relative, treat it as
# relative to $MAIN_ROOT (matches what `Edit` accepts, although Edit/Write
# require absolute paths per Claude Code conventions — we still defend).
RESOLVED_FILE=$(normalize_target_path "$FILE_PATH" "$MAIN_ROOT")

# Containment check: is the resolved file under $MAIN_ROOT?
case "$RESOLVED_FILE" in
  "$MAIN_ROOT"/*) ;;  # under main — fall through to allowlist
  *) exit 0 ;;         # outside main (worktree, /tmp, etc.) — allow
esac

# Path relative to MAIN_ROOT for allowlist matching.
REL="${RESOLVED_FILE#$MAIN_ROOT/}"

# ── Allowlist ────────────────────────────────────────────────────────────
# Agent-managed gitignored surfaces. These are NOT part of the main repo's
# tracked content (gitignore'd), so writes here don't pollute main's working
# tree from git's perspective and don't cause the `git checkout` /
# `git stash` cascades that motivated this hook. Keep this list narrow.
# Phase 8 root-turd consolidation: the live marker paths (.zskills/tracked,
# .zskills/landed, .zskills/worktreepurpose) are covered by the .zskills/*
# arm. The three legacy root arms stay for the dual-read transition window
# (pre-move worktrees / orchestrator flows may still touch them).
case "$REL" in
  .zskills/*)        exit 0 ;;  # tracking, audit, issues, dev-server state, monitor runtime, worktree markers
  .zskills-tracked)  exit 0 ;;  # legacy worktree pipeline-id marker (transition window)
  .landed)           exit 0 ;;  # legacy worktree landed marker (transition window)
  .worktreepurpose)  exit 0 ;;  # legacy worktree purpose marker (transition window)
esac

# ── main_edit mode resolution (registry row 36; #1165 headline) ────────────
# main_edit is now DEMOTABLE (Settled decision 7, REVISED): autonomous/
# unwatched Edit/Write to main → BLOCK; WATCHED → SILENT by shipped default
# (the zero-config quiet headline — do NOT reintroduce a watched warning), or
# opt-in `"warn"`. An explicit `"block"` toggle restores hard-deny-even-watched.
# ENF_ROOT (config_root) was computed in the tamper arm above; MAIN_ROOT
# doubles as ENF_LOCAL for this Edit/Write hook (no cd-target in the input).
PRED=$(zskills_enforcement_predicate "$INPUT" "$ENF_ROOT" "$MAIN_ROOT")
zskills_enforcement_load_toggles "$ENF_ROOT/.claude/zskills-config.json"
MODE=$(zskills_enforcement_mode main_protection main_edit demotable "$PRED")
case "$MODE" in
  silent|off) exit 0 ;;  # zero-config watched default (silent) / explicit off
esac
# Re-run WITHOUT command substitution so _ZSK_ENF_SOURCE is set in THIS shell
# (the tag formatter reads it; a $()-captured call would lose the side effect).
zskills_enforcement_mode main_protection main_edit demotable "$PRED" >/dev/null

# ── Deny / Warn ───────────────────────────────────────────────────────────
# ONE tag call line for main_edit (Settled decision 14 — one tag-emission form
# per check); the resolved tag is reused in both the warn and block arms. The
# agent-directed worktree-routing advice (the /do pr · /run-plan ·
# /create-worktree recommendations) stays DENY-arm-only (Settled decision 2 —
# the warn audience is the watching human, not the model). The warn arm softens
# "is blocked" → "is normally blocked".
MAIN_EDIT_TAG=$(zskills_enforcement_tag main_protection main_edit)

if [ "$MODE" = "warn" ]; then
  STOP_MSG=$(cat <<EOF
STOP: Edit/Write to main is normally blocked (main_protected: true in .claude/zskills-config.json).

Target: $ORIG_FILE_PATH ($REL)

$MAIN_EDIT_TAG
EOF
)
  zskills_enforcement_warn "$STOP_MSG"
  zskills_enforcement_flush_warnings
  exit 0
fi

# block — the factual body + the agent-directed worktree-routing advice.
STOP_MSG=$(cat <<EOF
STOP: Edit/Write to main is blocked (main_protected: true in .claude/zskills-config.json).

Target: $ORIG_FILE_PATH ($REL)

Edits to the main repo working tree bypass the worktree discipline. Move
this change into a worktree:

  - Standard task with review: \\\`/do pr\\\` (worktree → PR)
  - Plan-driven work: \\\`/run-plan\\\` (worktree per phase)
  - Manual: \\\`/create-worktree\\\` then operate inside the returned path

Allowed on main (not blocked): paths under \\\`.zskills/\\\` (tracking,
audit, issues, dev-server state, and the worktree-state markers
\\\`.zskills/tracked\\\`, \\\`.zskills/landed\\\`, \\\`.zskills/worktreepurpose\\\`),
plus the legacy gitignored root markers \\\`.zskills-tracked\\\`,
\\\`.landed\\\`, \\\`.worktreepurpose\\\` (dual-read transition window).

To disable this gate project-wide, set \\\`execution.main_protected: false\\\`
in \\\`.claude/zskills-config.json\\\`.

$MAIN_EDIT_TAG
EOF
)

# Emit deny envelope. Escape for JSON: backslashes first, then quotes, then
# newlines. Mirrors block-unsafe-project.sh's block_with_reason pattern.
ESC="${STOP_MSG//\\/\\\\}"
ESC="${ESC//\"/\\\"}"
ESC="${ESC//$'\n'/\\n}"
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$ESC"
exit 0
