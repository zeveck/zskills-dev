#!/bin/bash
# zskills-hook-version: 2026.05.0
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
  if [[ "$cmd" =~ ^cd[[:space:]]+([^[:space:]\&\;\|]+) ]]; then
    local target="${BASH_REMATCH[1]}"
    # Remove surrounding quotes if present
    target="${target%\"}"
    target="${target#\"}"
    if [ -d "$target" ]; then
      echo "$target"
    fi
  fi
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
      -C|-c) ((i+=2)) ;;
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

json_escape() {
  # Pure-bash JSON string escape. Argument → stdout, no surrounding quotes.
  # Order: \ first, then ", then named control-char escapes.
  # `LC_ALL=C` makes ${var//pat/repl} byte-deterministic (no UTF-8 char
  # boundary surprises). Rare control bytes (0x00-0x1F) outside the
  # named escapes are STRIPPED rather than \u00XX-escaped: stage-check
  # stderr is ASCII text by inspection of skill-version-stage-check.sh,
  # so the strip path never triggers in practice but is a defense-in-
  # depth backstop against malformed input. See D4 in
  # references/skill-version-pretooluse-hook.md.
  local LC_ALL=C
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\b'/\\b}"
  s="${s//$'\f'/\\f}"
  # Strip remaining control bytes (0x00-0x1F).
  # POSIX char class works correctly under LC_ALL=C; the bash range
  # form `[$'\x00'-$'\x1f']` only matches the upper bound byte (0x1F),
  # NOT the range — verified empirically in Round 2 finding N2 (bytes
  # 0x01-0x1E pass through verbatim, producing invalid JSON with raw
  # control bytes → harness silently rejects → silent allow).
  s="${s//[[:cntrl:]]/}"
  printf '%s' "$s"
}

REASON=$(json_escape "$STDERR")
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$REASON"
exit 0
