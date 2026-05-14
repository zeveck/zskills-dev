#!/bin/bash
# hooks/_lib/git-tokenwalk.sh — source-of-truth helper bodies for the
# tokenize-then-walk classifier family:
#
#   Base (first-token-anchored) helpers:
#     - is_git_subcommand    — tokenize-walk a `git $verb` invocation
#     - is_destruct_command  — tokenize-walk a `<verb>` invocation (kill, rm, …)
#     - is_gh_pr_subcommand  — tokenize-walk a `gh pr $verb` invocation,
#                              with optional flag-order-agnostic flag match
#
#   Hook-local segment-walking wrappers (call the base helper per shell segment):
#     - is_git_subcommand_in_chain   — segment-walk for cd-chained git commands
#                                      (`cd /tmp/wt && git commit -m foo`)
#     - is_destruct_command_in_chain — segment-walk for cd-chained destruct verbs
#                                      (`some_cmd && kill -9 1234`)
#     - is_gh_pr_subcommand_in_chain — segment-walk for cd-chained gh-pr verbs
#                                      (`cd /tmp/wt && gh pr create -B main`)
#
# All helpers are inlined verbatim into hook source files; the drift gate at
# tests/test-hook-helper-drift.sh enforces byte-equality at CI time:
#   - is_git_subcommand   inlined into block-unsafe-project.sh.template,
#                                       block-unsafe-generic.sh,
#                                       block-stale-skill-version.sh (Plan B, post-D6)
#   - is_destruct_command inlined into block-unsafe-generic.sh
#   - is_git_subcommand_in_chain   inlined into block-unsafe-project.sh.template
#                                              + block-unsafe-generic.sh
#   - is_destruct_command_in_chain inlined into block-unsafe-generic.sh only
#   - is_gh_pr_subcommand          inlined into block-bypassed-land-pr.sh
#   - is_gh_pr_subcommand_in_chain inlined into block-bypassed-land-pr.sh
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

# Returns 0 iff $cmd is a `gh pr $want_sub` invocation. On match, also sets:
#   GH_PR_SUB_INDEX = array index immediately after the matched subcommand
#     token (i.e., the first arg position).
#   GH_PR_SUB_REST  = post-subcommand args joined by single spaces, TRUNCATED
#     at the first shell-segment boundary token (`&&`, `||`, `;`, `|`).
# On no-match, GH_PR_SUB_INDEX=-1 and GH_PR_SUB_REST="".
#
# Tokenize-then-walk: skip env-var prefixes (KEY=VAL...), optional `env`,
# find literal `gh`, walk past gh-level flags:
#   -R val / --repo val      → consume 2 tokens
#   --repo=val               → consume 1 token (embedded value)
#   -h / --help / --version / --no-pager → consume 1 token
#   any other --foo=bar      → consume 1 token
# Then require next token == `pr` and next-next token == $want_sub.
#
# If $flag_regex is non-empty, ALSO require some subsequent token in the
# current shell segment to match it (flag-order-agnostic, e.g., both
# `gh pr merge --auto --squash` and `gh pr merge --squash --auto` match
# `is_gh_pr_subcommand cmd merge '^--auto$'`).
#
# Quoted-`gh` / quoted-`pr` / quoted-subcommand are unwrapped one quote
# layer to tolerate JSON-wire-format double-quote injection (mirrors
# is_git_subcommand's defense).
is_gh_pr_subcommand() {
  local cmd="$1"
  local want_sub="$2"
  local flag_regex="${3:-}"
  GH_PR_SUB_INDEX=-1
  GH_PR_SUB_REST=""
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
  # `nohup gh pr create`, `time gh pr create`, `timeout 30 gh pr create`,
  # etc. are operationally equivalent to `gh pr create`. Without this
  # skip an agent reaching for `timeout 30 gh pr create` (e.g., after a
  # previous PR-create hung) would bypass the gate.
  #
  # `timeout` consumes its DURATION arg as well (2 tokens); the others
  # consume just 1. List is small and curated; do NOT generalize to
  # "skip any unknown leading word" — that would whitelist user aliases.
  while [[ $i -lt $n ]]; do
    local _pref="${TOKENS[$i]}"
    case "$_pref" in
      */*) _pref="${_pref##*/}" ;;
    esac
    case "$_pref" in
      command|exec|nohup|nice|time)
        ((i++)) ;;
      timeout)
        ((i+=2)) ;;
      *)
        break ;;
    esac
  done
  local g="${TOKENS[$i]:-}"
  g="${g%\"}"; g="${g#\"}"
  g="${g%\'}"; g="${g#\'}"
  # Strip absolute/relative path prefix so `/usr/local/bin/gh pr create`
  # and `./gh pr create` are recognized as gh invocations. PR #250's
  # original walker compared the first token literally to "gh", which
  # let path-prefixed invocations slip through.
  case "$g" in
    */*) g="${g##*/}" ;;
  esac
  [[ "$g" != "gh" ]] && return 1
  ((i++))
  # Walk past gh-level flags. -R/--repo take a separate value (2 tokens);
  # --repo=value embeds the value (1 token); other --foo=bar / -h /
  # --help / --version / --no-pager all consume a single token.
  while [[ $i -lt $n && "${TOKENS[$i]:0:1}" == "-" ]]; do
    case "${TOKENS[$i]}" in
      -R|--repo) ((i+=2)) ;;
      *)         ((i+=1)) ;;
    esac
  done
  local pr_tok="${TOKENS[$i]:-}"
  pr_tok="${pr_tok%\"}"; pr_tok="${pr_tok#\"}"
  pr_tok="${pr_tok%\'}"; pr_tok="${pr_tok#\'}"
  [[ "$pr_tok" != "pr" ]] && return 1
  ((i++))
  local sub="${TOKENS[$i]:-}"
  sub="${sub%\"}"; sub="${sub#\"}"
  sub="${sub%\'}"; sub="${sub#\'}"
  [[ "$sub" != "$want_sub" ]] && return 1
  # Match (so far). Compute scoped rest first so the optional flag-regex
  # check is flag-order-agnostic AND segment-scoped.
  GH_PR_SUB_INDEX=$((i + 1))
  local j=$GH_PR_SUB_INDEX
  local rest=""
  local -a REST_TOKENS=()
  while [[ $j -lt $n ]]; do
    case "${TOKENS[$j]}" in
      '&&'|'||'|';'|'|') break ;;
    esac
    rest="$rest ${TOKENS[$j]}"
    REST_TOKENS+=( "${TOKENS[$j]}" )
    ((j++))
  done
  GH_PR_SUB_REST="${rest# }"
  if [[ -n "$flag_regex" ]]; then
    local found=0 tok
    for tok in "${REST_TOKENS[@]:-}"; do
      [[ -z "$tok" ]] && continue
      if [[ "$tok" =~ $flag_regex ]]; then
        found=1
        break
      fi
    done
    if [[ $found -eq 0 ]]; then
      GH_PR_SUB_INDEX=-1
      GH_PR_SUB_REST=""
      return 1
    fi
  fi
  return 0
}

# Returns 0 iff ANY shell segment of $cmd is a `gh pr $want_sub` invocation
# (with optional $flag_regex match). Same segment-split rules as
# is_git_subcommand_in_chain: `&&`, `||`, `;`, `|`, real newline, JSON-
# escaped two-char `\n`. Restores cd-chain semantics
# (e.g., `cd /tmp/wt && gh pr create -B main` matches) on top of the
# first-token-anchored is_gh_pr_subcommand core.
is_gh_pr_subcommand_in_chain() {
  local cmd="$1"
  local want_sub="$2"
  local flag_regex="${3:-}"
  local normalized
  normalized=$(printf '%s' "$cmd" \
    | sed -E 's/[[:space:]]*(\&\&|\|\||;|\|)[[:space:]]*/\n/g' \
    | sed -E 's/\\n/\n/g')
  local seg
  while IFS= read -r seg; do
    [ -z "$seg" ] && continue
    if is_gh_pr_subcommand "$seg" "$want_sub" "$flag_regex"; then
      return 0
    fi
  done <<< "$normalized"
  return 1
}

# Returns 0 iff $cmd contains a `gh pr $want_sub` invocation either
# directly, in any chain segment, OR inside an inline-string wrapper
# (bash -c '<inner>', sh -c '<inner>', dash -c '<inner>', or
# eval '<inner>'). The inner string is extracted and the matcher is
# re-applied recursively (bounded depth, default 3).
#
# This is the proper closure of the "documented hole" in PR #250: the
# tokenize-walker correctly handles direct gh, walk-past flags, segment
# chains (&&, ||, ;, |, real newline, JSON-escaped \n), and quote
# elision around verb tokens. The one thing it didn't handle was an
# agent wrapping its gh call in `bash -c '...'`, which presents `bash`
# as the first token. This helper extracts the wrapped inner string and
# matches it through the same chain-walker, closing that hole.
#
# Out of scope (deliberate evasion, not racing-to-done):
#   - Variable indirection: `cmd='gh pr create'; bash -c "$cmd"` — we
#     cannot resolve $cmd at hook time.
#   - Process substitution: `bash <(echo gh pr create)` — gh runs in a
#     separate fork the hook never sees and isn't accurately matched by
#     parsing the outer command.
#   - String concatenation across tokens: `c='gh pr cr'; c="${c}eate";
#     bash -c "$c"` — same issue as variable indirection.
#   - Base64-encoded payloads, scripts fetched from URLs.
# These shapes require a behavioral defense (PostToolUse transcript
# scan), not syntactic gating, and are out of scope here.
is_gh_pr_subcommand_in_wrappers() {
  local cmd="$1"
  local want_sub="$2"
  local flag_regex="${3:-}"
  local depth="${4:-3}"

  # First, check the direct + chain case via existing helper.
  if is_gh_pr_subcommand_in_chain "$cmd" "$want_sub" "$flag_regex"; then
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
          # like 'gh pr create' became three tokens: "'gh" "pr" "create'".
          # Rejoin with spaces.
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
      if is_gh_pr_subcommand_in_wrappers "$wrapper_inner" "$want_sub" "$flag_regex" $((depth - 1)); then
        return 0
      fi
    fi
  done <<< "$normalized"

  return 1
}
