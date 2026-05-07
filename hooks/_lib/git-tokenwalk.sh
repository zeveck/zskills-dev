#!/bin/bash
# hooks/_lib/git-tokenwalk.sh — source-of-truth helper bodies for the
# tokenize-then-walk classifier family:
#
#   Base (first-token-anchored) helpers:
#     - is_git_subcommand    — tokenize-walk a `git $verb` invocation
#     - is_destruct_command  — tokenize-walk a `<verb>` invocation (kill, rm, …)
#
#   Hook-local segment-walking wrappers (call the base helper per shell segment):
#     - is_git_subcommand_in_chain   — segment-walk for cd-chained git commands
#                                      (`cd /tmp/wt && git commit -m foo`)
#     - is_destruct_command_in_chain — segment-walk for cd-chained destruct verbs
#                                      (`some_cmd && kill -9 1234`)
#
# All four are inlined verbatim into hook source files; the drift gate at
# tests/test-hook-helper-drift.sh enforces byte-equality at CI time:
#   - is_git_subcommand   inlined into block-unsafe-project.sh.template,
#                                       block-unsafe-generic.sh,
#                                       block-stale-skill-version.sh (Plan B, post-D6)
#   - is_destruct_command inlined into block-unsafe-generic.sh
#   - is_git_subcommand_in_chain   inlined into block-unsafe-project.sh.template
#                                              + block-unsafe-generic.sh
#   - is_destruct_command_in_chain inlined into block-unsafe-generic.sh only
#
# Maintain HERE only.
set -u

# Returns 0 iff $cmd is a git invocation whose subcommand is $want_sub.
# On match, also sets:
#   GIT_SUB_INDEX = array index immediately after the matched subcommand
#     token (i.e., the first arg position).
#   GIT_SUB_REST  = post-subcommand args joined by single spaces, TRUNCATED
#     at the first shell-segment boundary token (`&&`, `||`, `;`, `|`).
#     Provides a properly scoped buffer for downstream regex checks.
# On no-match, GIT_SUB_INDEX=-1 and GIT_SUB_REST="" (callers may rely on
# this reset to avoid stale data leaking from a prior call).
#
# Tokenize-then-walk: skip env-var prefixes (KEY=VAL...), optional `env`,
# find literal `git`, walk past top-level flags (-C/-c consume next token,
# other -X / --foo / --foo=bar consume single token), check next token == $want_sub.
# Quoted-`git` ("git"/'git') and quoted-subcommand ("commit"/'commit') are
# both unwrapped one quote layer to tolerate JSON-wire-format double-quote
# injection (round-1 DA-H-1 fix).
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
  local g="${TOKENS[$i]:-}"
  g="${g%\"}"; g="${g#\"}"
  g="${g%\'}"; g="${g#\'}"
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

# Returns 0 iff $cmd is a destructive invocation whose FIRST token (after
# env-var-prefix skip) is $want_first AND (if $flag_match is non-empty)
# one of the subsequent flag tokens matches the $flag_match regex.
#
# FIRST-TOKEN-ANCHORED ONLY. Pipeline-fed forms (e.g., `cat foo | xargs rm`,
# `pgrep node | xargs kill`) and combined-flag forms (e.g., `fuser -mk`)
# are NOT covered by this helper — they are handled by the EXISTING
# well-bounded regexes in block-unsafe-generic.sh (XARGS_KILL at line 157,
# RM_RECURSIVE at line 217, fuser combined-flag at line 146). Phase 4
# leaves those existing regexes UNCHANGED. See round-1 DA-C-2.
#
# Pass $flag_match="" for "first token == verb" only (e.g., killall,
# pkill — single-token verbs whose presence at position 0 is itself the
# destructive signal).
#
# Positional-pair semantics for kill -s <SIGNAL>: if $flag_match contains
# the literal `:next:<regex>` suffix, the helper also requires the NEXT
# token after the matched flag to satisfy <regex>. Used for `kill -s 9`
# vs. `kill -s USR1` (round-1 R-H-5). Example: flag_match='^-s$:next:^(9|KILL|SIGKILL)$'.
is_destruct_command() {
  local cmd="$1"
  local want_first="$2"
  local flag_match="${3:-}"
  local next_match=""
  if [[ "$flag_match" == *":next:"* ]]; then
    next_match="${flag_match##*:next:}"
    flag_match="${flag_match%:next:*}"
  fi
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
  first="${first%\"}"; first="${first#\"}"
  first="${first%\'}"; first="${first#\'}"
  [[ "$first" != "$want_first" ]] && return 1
  [[ -z "$flag_match" ]] && return 0
  ((i++))
  while [[ $i -lt $n ]]; do
    if [[ "${TOKENS[$i]}" =~ $flag_match ]]; then
      if [[ -n "$next_match" ]]; then
        local next_tok="${TOKENS[$((i+1))]:-}"
        [[ "$next_tok" =~ $next_match ]] && return 0
      else
        return 0
      fi
    fi
    ((i++))
  done
  return 1
}

# Returns 0 iff ANY shell segment of $cmd is a `git $want_sub` invocation.
# Segments are split on `&&`, `||`, `;`, `|`, real newline, AND the JSON-
# escaped two-char `\n` literal that arrives via the hook's sed-extracted
# COMMAND value (the hook does not JSON-decode). Restores the cd-chain
# semantics the OLD bare-substring whole-buffer regex provided
# (e.g., `cd /tmp/wt && git commit -m foo` matches) on top of the
# first-token-anchored is_git_subcommand core.
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

# Returns 0 iff ANY shell segment of $cmd is a destructive invocation matching
# `is_destruct_command "$seg" "$want_first" "$flag_match"`. Same segment-split
# rules as is_git_subcommand_in_chain. Restores cd-chain semantics for
# destructive verbs (e.g., `some_cmd && kill -9 1234` matches) on top of the
# first-token-anchored is_destruct_command core.
is_destruct_command_in_chain() {
  local cmd="$1"
  local want_first="$2"
  local flag_match="${3:-}"
  local normalized
  normalized=$(printf '%s' "$cmd" \
    | sed -E 's/[[:space:]]*(\&\&|\|\||;|\|)[[:space:]]*/\n/g' \
    | sed -E 's/\\n/\n/g')
  local seg
  while IFS= read -r seg; do
    [ -z "$seg" ] && continue
    if is_destruct_command "$seg" "$want_first" "$flag_match"; then
      return 0
    fi
  done <<< "$normalized"
  return 1
}
