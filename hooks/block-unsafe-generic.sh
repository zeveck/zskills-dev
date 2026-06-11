#!/bin/bash
# zskills-hook-version: 2026.06.4
# Block unsafe commands that agents should never use.
# GENERIC safety layer — works in any project with zero configuration.
# No external dependencies — bash only.
#
# Covers destructive operations (data loss) and discipline violations
# (blanket staging, hook bypass).
#
# Destructive: git stash drop/clear, git checkout --/restore (any file), git clean -f,
#              git reset --hard, kill -9/-KILL, killall, pkill, fuser -k, rm -rf
# Discipline:  git add ./git add -A (stage by name instead),
#              git commit --no-verify (fix the hook, don't bypass)
# Optional:    git push (agents should not push; the user pushes when ready)

# ─── Main-push block: sourced from config at runtime ───────────────
# Controls the "git push main/master" deny rule further down in this
# file. The decision is read at runtime from execution.main_protected in
# .claude/zskills-config.json (resolved below, just before the push rule),
# mirroring the COMMIT gate (block-unsafe-project.sh is_main_protected())
# and the EDIT gate (block-main-edits.sh main_protected check). This
# replaces the former static BLOCK_MAIN_PUSH=1 line that /update-zskills
# spliced per-preset: on the plugin lane the hook ships read-only and was
# never materialised, so the static value froze and a config edit only
# changed 2 of 3 gates. Reading config keeps all three coherent.
#   cherry-pick (default)  -> main_protected:false -> allow push
#   locked-main-pr         -> main_protected:true  -> block push
#   direct                 -> main_protected:false -> allow push
# FAIL CLOSED: when the config file is absent, unreadable, or unparseable
# we DEFAULT TO BLOCKING (BLOCK_MAIN_PUSH=1) — preserving the prior
# "zskills-shipped configs fail closed (safer)" posture.
#
# CONFIG-CASCADE CARVE-OUT (INSTALL_REDESIGN Phase 5, deliberate): this
# hook reads execution.main_protected from the PROJECT config ONLY — it
# does NOT participate in the project > user > built-ins cascade. This is
# a SAFETY setting: letting a user-level ~/.claude/zskills-config.json
# silently weaken a project's main_protected would invert the trust
# direction (a per-user file overriding a per-repo discipline). The
# fail-closed default above is unchanged.
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

# Extract the command field from the tool_input JSON. Without this, the
# hook's regex checks match against the whole JSON — including commit
# messages, echo/printf content, heredocs — any text that mentions a
# forbidden pattern. Extracting the command first scopes matching to the
# actual shell command. (Same pattern as block-unsafe-project.sh.)
COMMAND=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | sed 's/\\"/"/g')
# If extraction fails (malformed JSON), fall back to scanning $INPUT so the
# hook remains defensive; no false-allows.
[ -z "$COMMAND" ] && COMMAND="$INPUT"

# ──────────────────────────────────────────────────────────────
# Interpreter-stdin re-injection (#772) — sibling of #399/#597
# ──────────────────────────────────────────────────────────────
# Pass-1 redaction below strips heredoc / here-string BODIES as inert
# text — correct when the body is DATA (`cat <<EOF`, `gh pr create
# --body-file=- <<EOF`, echo content, a commit message that mentions
# `git clean -f`). But when the heredoc / here-string is the STDIN of an
# INTERPRETER (`bash <<<"git clean -fdx"`, `sh <<EOF … EOF`,
# `zsh -s <<<"…"`), the body is EXECUTED as a script — so a destructive
# command smuggled that way must reach the deny scan. This is the
# here-string/heredoc analogue of the `bash -c` / `eval` / `sh -c`
# wrapper-bypass closed by #399 / #597.
#
# Discriminator (the make-or-break false-positive guard): we re-inject
# the body as code ONLY when the command HEAD of the segment is an
# interpreter (bash|sh|zsh|dash|ash|ksh) reading its stdin as a script —
# i.e. the only tokens between the interpreter and the `<<<` / `<<DELIM`
# operator are interpreter FLAGS (`-s`, `-`, `-x`, …), with NO script-file
# positional. `cat <<EOF`, `echo`, `tee f <<EOF`, `gh pr create
# --body-file=- <<EOF`, and `bash script.sh <<<data` (here-string is DATA
# for script.sh, not code) all FAIL this test and are left for Pass-1 to
# strip as inert — preserving the existing no-false-positive guarantee.
#
# Mechanism: when an interpreter-stdin body is detected, we APPEND it to
# $COMMAND as a new `;`-separated shell segment. The existing
# is_*_in_wrappers / is_*_in_chain scanners split on `;` (and the
# JSON-escaped `\n`), so the re-injected body is scanned as a first-class
# command. We append rather than replace so the original (now-redacted)
# text is untouched and any chained ops after the heredoc stay visible.
extract_interp_stdin_body() {
  # Echoes the executed body (one per line) for every interpreter-stdin
  # heredoc / here-string in $1. Empty output ⇒ nothing to re-inject.
  local cmd="$1"
  # The interpreter head must be a WHOLE-WORD token at a segment boundary:
  # preceded by start-of-string or one of space / ; / & / | / backtick /
  # `(` (the chars that delimit a fresh command position), and followed by
  # zero or more interpreter FLAG tokens (`-s`, `-`, `-x`, …) and then the
  # redirection operator with NO intervening non-flag positional.
  #
  # The left boundary is the make-or-break false-positive guard: it stops
  #   * `script.sh <<<data`  — the `sh` here is preceded by `.`, not a
  #     boundary, so the here-string is correctly treated as DATA, and
  #   * a stray `bash`/`sh` earlier in the buffer from matching a
  #     `cat <<EOF` heredoc that appears later.
  # The "flags only, no positional" rule stops `bash script.sh <<<data`
  # and `bash run.sh <<EOF` — there the body is stdin DATA for the script
  # file, not code, so Pass-1 should strip it as inert.
  #
  # #789 broadening (closure-incomplete on #772): the head must also match
  #   * an absolute/relative interpreter PATH — `/bin/bash <<<…`,
  #     `/usr/bin/bash <<<…`, `./bash <<<…` (agents invoke interpreters by
  #     full path routinely, so the bare-token-only head left this open),
  #     and
  #   * LONG flags — `bash --norc <<<…`, `bash --posix <<<…` (the prior
  #     `-[A-Za-z]+` flag clause matched single-dash short flags only, so a
  #     `--word` broke the run-up to the redirect), and
  #   * an OPTION-ARGUMENT word consumed by an arg-taking flag —
  #     `bash -eo pipefail <<<…` / `bash -o pipefail <<<…` /
  #     `bash --rcfile FILE <<<…` (the `pipefail` / FILE token is the
  #     argument to `-o` / `--rcfile`, NOT a script positional, so stdin is
  #     still the script → re-inject as code).
  #
  # The script-positional discriminator is PRESERVED: a free non-flag token
  # (one NOT consumed as an option-argument) before the redirect — e.g.
  # `bash script.sh <<<data`, `sh deploy.sh <<<data` — terminates the flag
  # run before the `<<<`/`<<`, so the head does not reach the operator and
  # the body is left for Pass-1 to strip as inert DATA. Only `-o`/`-*o`,
  # `--rcfile`, and `--init-file` consume a following word; every other
  # token that is not a flag stops the run.
  #
  # `pp` is an OPTIONAL path prefix: zero or more `dir/` segments. The
  # interpreter basename is matched as the final segment, so `/bin/bash`,
  # `/usr/bin/bash`, and `./bash` all resolve to the `bash` basename, while
  # `myscript.sh`, `run-bash.sh`, and `foo/sh.txt` do NOT (the basename
  # token must be exactly one of the interpreters, with no trailing word
  # chars before the flags/redirect).
  #
  # Capture-group budget: keep head_re at a STABLE group count so the
  # heredoc backrefs below (delim/body) stay correct. bnd(1) + pp(1) +
  # interp(1) + flagrun-outer(1) = 4 capture groups — flagrun is written
  # with a SINGLE capturing group (the outer `*` repeat); every alternative
  # inside it uses flat alternation / char classes, no nested capture. So
  # the heredoc delim = \5 and body = \6 (both single-digit, sed-safe).
  # Verified empirically with a per-group sed dump during the fix.
  local bnd='(^|[[:space:];&|`(])'
  local pp='(/?[A-Za-z0-9_.+-]+/)*'
  # Each `|`-alternative below is a complete `[[:space:]]+<flag-or-pair>`
  # element; the outer parens + `*` are the only capturing group.
  local flagrun='([[:space:]]+-[A-Za-z]*o[[:space:]]+[A-Za-z0-9_.+/-]+|[[:space:]]+--rcfile[[:space:]]+[A-Za-z0-9_.+/-]+|[[:space:]]+--init-file[[:space:]]+[A-Za-z0-9_.+/-]+|[[:space:]]+--[A-Za-z][-A-Za-z0-9]*=[^[:space:]]*|[[:space:]]+--[A-Za-z][-A-Za-z0-9]*|[[:space:]]+-[A-Za-z]+)*'
  local head_re="${bnd}${pp}(bash|sh|zsh|dash|ash|ksh)${flagrun}[[:space:]]*"

  # --- Here-strings: <interp> [flags] <<< "body" | '"'"'body'"'"' | body ---
  # Quoted forms first so the body capture stops at the closing quote;
  # bareword form last (body = run of non-space, non-redirect chars).
  printf '%s' "$cmd" | grep -oE "${head_re}<<<[[:space:]]*\"[^\"]*\"" \
    | sed -E "s/.*<<<[[:space:]]*\"([^\"]*)\".*/\1/"
  printf '%s' "$cmd" | grep -oE "${head_re}<<<[[:space:]]*'[^']*'" \
    | sed -E "s/.*<<<[[:space:]]*'([^']*)'.*/\1/"
  printf '%s' "$cmd" | grep -oE "${head_re}<<<[[:space:]]*[^[:space:]\"';&|]+" \
    | sed -E "s/.*<<<[[:space:]]*([^[:space:]\"';&|]+).*/\1/"

  # --- Heredocs: <interp> [flags] <<[-]?['\"]?DELIM['\"]? \n body \n DELIM ---
  # Body arrives with literal two-char `\n` separators (the extractor does
  # not JSON-decode). We rewrite the body's `\n` back to real newlines so
  # each re-injected line becomes its own scannable segment. The DELIM is
  # backref-pinned to the opener; quoted-delim alts tried first. With the
  # #789 head_re broadening the head now has 4 capture groups (boundary,
  # path-prefix, interp, flag-run), so the delim is \5 and the body is \6
  # (was \4/\5 pre-#789, when head_re had 3 groups). Group numbering was
  # confirmed empirically — see the per-group dump during the fix.
  # NOTE: the sed substitution delimiter is `#`, NOT `/` — the #789 head_re
  # broadening adds an optional path prefix (`pp`) that embeds literal `/`
  # characters into the pattern, which would otherwise be parsed as the
  # `s/.../.../`` delimiter and abort with "unknown option to `s'". `#` is
  # absent from head_re; it is only a delimiter for the sed SCRIPT, so a `#`
  # appearing in the matched heredoc BODY (a shell comment) is harmless.
  printf '%s' "$cmd" | sed -nE \
    "s#.*${head_re}<<-?[[:space:]]*\"([A-Za-z_][A-Za-z0-9_]*)\"\\\\n(.*)\\\\n\\5(\\\\n.*|\$)#\\6#p" \
    | sed -E 's/\\n/\n/g'
  printf '%s' "$cmd" | sed -nE \
    "s#.*${head_re}<<-?[[:space:]]*'([A-Za-z_][A-Za-z0-9_]*)'\\\\n(.*)\\\\n\\5(\\\\n.*|\$)#\\6#p" \
    | sed -E 's/\\n/\n/g'
  printf '%s' "$cmd" | sed -nE \
    "s#.*${head_re}<<-?[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)\\\\n(.*)\\\\n\\5(\\\\n.*|\$)#\\6#p" \
    | sed -E 's/\\n/\n/g'
}

_INTERP_BODY=$(extract_interp_stdin_body "$COMMAND")
if [ -n "$_INTERP_BODY" ]; then
  # Append each extracted body line as its own `;`-delimited segment so
  # the chain/wrapper scanners see it as a standalone command.
  while IFS= read -r _line; do
    [ -z "$_line" ] && continue
    COMMAND="$COMMAND ; $_line"
  done <<< "$_INTERP_BODY"
  unset _line
fi
unset _INTERP_BODY

# ──────────────────────────────────────────────────────────────
# Data-region redaction
# ──────────────────────────────────────────────────────────────
# Destructive-op regex checks below scan $COMMAND as a single string.
# Regions that legitimately describe destructive ops — commit messages,
# PR bodies, issue titles, heredoc content — must not trip the scans.
# We redact those regions before scanning. Redaction is per-argument
# and stops at the closing quote / heredoc delimiter, so chained
# commands AFTER a data-bearing arg (e.g. `git commit -m "msg" && rm
# -rf /etc`) stay visible to the rules.
#
# $COMMAND holds literal `\n` sequences (two chars: backslash + n),
# not real newlines — the JSON extractor above does not interpret
# escape sequences beyond `\"`. So the regex treats `\\n` as the
# in-string line separator (matching a literal backslash then n).

# Pass 1 — heredoc bodies
# Match `<<[-]?['"]?DELIM['"]?\n ... \nDELIM(\n|$)` and replace with a
# sentinel. :m / t m iterate so sequential heredocs with different
# delimiters all get redacted. GNU sed -E supports backrefs (\1) in
# the pattern, which lets us pin the closing delimiter to the opener.
# Quoted-delim forms are tried first so the unquoted alt doesn't eat
# the identifier before the quote.
COMMAND=$(printf '%s' "$COMMAND" | sed -E \
  -e ':h' \
  -e 's/<<-?[[:space:]]*"([A-Za-z_][A-Za-z0-9_]*)"\\n.*\\n\1(\\n|$)/HEREDOC_REDACTED\2/' \
  -e 's/<<-?[[:space:]]*'\''([A-Za-z_][A-Za-z0-9_]*)'\''\\n.*\\n\1(\\n|$)/HEREDOC_REDACTED\2/' \
  -e 's/<<-?[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)\\n.*\\n\1(\\n|$)/HEREDOC_REDACTED\2/' \
  -e 't h')

# Pass 2 — flag-scoped quoted arg values
# - `git commit`                       : -m, --message (incl. -am/-Sm)
# - `gh pr|issue create|comment`       : --body, -b, --title, -t
# Intermediate args tolerated via [^|;&]* so a chained dangerous op
# after the arg stays visible. The quoted value uses [^"]* / [^']* so
# the match does not cross quote boundaries. Replacement drops the
# quotes (plain `REDACTED`) to guarantee the :m / t m loop terminates
# — the re-run can no longer match the now-bare sentinel.
COMMAND=$(printf '%s' "$COMMAND" | sed -E \
  -e ':m' \
  -e 's/(git[[:space:]]+commit[[:space:]]([^|;&]*[[:space:]])?(-[a-zA-Z]*m|--message)[[:space:]]+)("[^"]*"|'\''[^'\'']*'\'')/\1REDACTED/g' \
  -e 's/(gh[[:space:]]+(pr|issue)[[:space:]]+(create|comment)[[:space:]]([^|;&]*[[:space:]])?(--body|-b|--title|-t)[[:space:]]+)("[^"]*"|'\''[^'\'']*'\'')/\1REDACTED/g' \
  -e 't m')

# Block patterns — each with a reason
block_with_reason() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$1"
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

# Inlined from hooks/_lib/git-tokenwalk.sh (source-of-truth). Drift gate: tests/test-hook-helper-drift.sh (Phase 5.4).
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
  # Skip transparent command-prefix wrappers. These execute the next
  # argv as a separate process (or in-place for `exec`), so
  # `nohup rm -rf /tmp/x`, `timeout 30 kill -9 1234`, etc. are
  # operationally equivalent to the bare destructive verb. Mirrors the
  # gh variant's prefix-skip (issue #279/PR #255), extended for destruct
  # verbs per issue #567.
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
  local first="${TOKENS[$i]:-}"
  first="${first%\"}"; first="${first#\"}"
  first="${first%\'}"; first="${first#\'}"
  # Strip absolute/relative path prefix so `/usr/bin/kill -9 1234`,
  # `/usr/bin/killall node`, `./pkill foo` are recognized as their
  # destructive bases. Mirrors is_git_subcommand's path-strip (issue
  # #528). Without this, path-prefixed destructive forms silently
  # bypassed every destruct-side hook gate (issue #572).
  case "$first" in
    */*) first="${first##*/}" ;;
  esac
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

# Inlined from hooks/_lib/git-tokenwalk.sh (source-of-truth). Drift gate: tests/test-hook-helper-drift.sh.
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

# Inlined from hooks/_lib/git-tokenwalk.sh (source-of-truth). Drift gate: tests/test-hook-helper-drift.sh.
is_destruct_command_in_wrappers() {
  local cmd="$1"
  local want_first="$2"
  local flag_match="${3:-}"
  local depth="${4:-3}"

  # First, check the direct + chain case via existing helper.
  if is_destruct_command_in_chain "$cmd" "$want_first" "$flag_match"; then
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
          # like 'kill -9 1234' became three tokens: "'kill" "-9" "1234'".
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
      if is_destruct_command_in_wrappers "$wrapper_inner" "$want_first" "$flag_match" $((depth - 1)); then
        return 0
      fi
    fi
  done <<< "$normalized"

  return 1
}

# git stash — wrapper-aware gate via is_git_subcommand_in_wrappers (#426,
# completes #399). The prior regex-based STASH_BOUNDARY anchored
# `git[[:space:]]+stash` to `^`, `;`, `&`, `&&`, `||`, `|`, backtick, or
# `$(` — none of which precede the inner `git` inside wrapper forms like
# `bash -c 'git stash drop'` / `eval 'git stash drop'` / `sh -c 'git
# stash drop'`. Tokenize-then-walk via is_git_subcommand_in_wrappers
# matches all those forms (and the existing chain/multi-segment cases)
# and sets GIT_SUB_REST to the rest of the matching segment for flag
# inspection — same idiom as the converted `add` / `commit` / `push`
# gates further down.
#
# Allowed subcommands: apply, list, show, pop, create, store, branch (read
# and recovery — never modify the working tree).
# Destructive: drop, clear — block.
# Create-stash: push, save, -u, bare — block (CLAUDE.md rule).
#
# Quoted-prose protection (overmatching on `echo "git stash drop"` etc.)
# is preserved by the data-region redaction passes at the top of the
# file (heredoc + -m/--message/--body/--title quoted-arg redaction). The
# wrapper-aware gate runs AFTER redaction, so prose in commit messages
# and gh body text no longer reaches the tokenizer.
#
# Past failure: a /commit pre-commit reviewer ran `stash -u && test && stash
# pop`; the pop silently unstaged the caller's staged files.
if is_git_subcommand_in_wrappers "$COMMAND" stash; then
  # First token of GIT_SUB_REST is the stash subcommand (apply, drop, etc.)
  # or absent (bare `git stash` = create-stash). Strip surrounding quotes
  # that wrapper-unwrapped forms may leave (e.g. `bash -c 'git stash drop'`
  # → GIT_SUB_REST="drop'" without the strip).
  _stash_sub="${GIT_SUB_REST%% *}"
  _stash_sub="${_stash_sub%\'}"; _stash_sub="${_stash_sub#\'}"
  _stash_sub="${_stash_sub%\"}"; _stash_sub="${_stash_sub#\"}"
  case "$_stash_sub" in
    drop|clear)
      block_with_reason "BLOCKED: git stash drop/clear destroys stashed work permanently (including untracked files saved with -u). If you need to drop a stash, ask the user to do it manually."
      ;;
    apply|list|show|pop|create|store|branch)
      : # allowed read/recovery subcommands — no action
      ;;
    *)
      # Includes: bare `git stash`, `git stash push`, `git stash save`,
      # `git stash -u`, and any unknown form. All are create-stash or
      # unrecognized — block.
      block_with_reason "BLOCKED: git-stash write subcommand forbidden (modifies working tree). Allowed read/recovery: apply, list, show, pop. For cherry-pick protection, let git refuse on overlap."
      ;;
  esac
  unset _stash_sub
fi

# git checkout -- (any file or blanket) — discards uncommitted changes permanently.
# Anchor `--` as the file-list separator: require it to be followed by
# whitespace or end-of-command. Otherwise benign long flags like --quiet,
# --force, --orphan, --theirs, --ours would false-positive because their
# leading `--` matched the bare regex.
# Use is_git_subcommand_in_wrappers (#426, completes #399) so wrapper forms
# like `bash -c 'git checkout -- file'` / `eval 'git checkout -- file'` /
# `sh -c 'git checkout -- file'` cannot bypass. The wrappers helper falls
# back to _in_chain on the outer command, then sets GIT_SUB_REST on match
# (whether via the chain or the recursive unwrap path) so the flag-regex
# check below still functions.
if is_git_subcommand_in_wrappers "$COMMAND" checkout && [[ "$GIT_SUB_REST" =~ (^|[[:space:]])(.*[[:space:]])?--([[:space:]]|$) ]]; then
  block_with_reason "BLOCKED: git checkout -- discards uncommitted changes permanently. This may destroy other sessions' work. If you need to undo your own change, use git diff to see what changed and edit it back manually."
fi

# git restore (any file or blanket) — modern equivalent of checkout --
# Wrapper-recursion via is_git_subcommand_in_wrappers (#426).
if is_git_subcommand_in_wrappers "$COMMAND" restore; then
  block_with_reason "BLOCKED: git restore discards uncommitted changes permanently. If you need to undo your own change, use git diff to see what changed and edit it back manually."
fi

# git switch with destructive flags — modern analog of `git checkout --`.
# `git switch --discard-changes` and `git switch -f` / `git switch --force`
# all destroy unstaged working-tree changes (per `git help switch`). Plain
# `git switch <branch>` and `git switch -c new-branch` are allowed; git
# itself refuses on dirty trees without the destructive opt-in flag.
# `git rebase` is intentionally NOT blocked here — reflog + `--abort` make
# rebases recoverable, and a blanket block would false-positive on the
# `-X theirs` rescue patterns CLAUDE.md teaches. Wrapper-recursion via
# is_git_subcommand_in_wrappers (#478, completes #426).
if is_git_subcommand_in_wrappers "$COMMAND" switch && [[ "$GIT_SUB_REST" =~ (^|[[:space:]])(--discard-changes|--force|-f)([[:space:]]|$) ]]; then
  block_with_reason "BLOCKED: git switch --discard-changes / -f / --force discards uncommitted changes permanently (modern analog of git checkout --). If you need to switch branches with dirty state, commit or stash first; if you genuinely want to discard, ask the user."
fi

# git clean -f (permanent file deletion)
# Wrapper-recursion via is_git_subcommand_in_wrappers (#426).
if is_git_subcommand_in_wrappers "$COMMAND" clean && [[ "$GIT_SUB_REST" =~ (^|[[:space:]])-[a-zA-Z]*f[a-zA-Z]*([[:space:]]|$) ]]; then
  block_with_reason "BLOCKED: git clean -f permanently deletes untracked files. These cannot be recovered from git."
fi

# git reset --hard (discards everything)
# Wrapper-recursion via is_git_subcommand_in_wrappers (#426).
if is_git_subcommand_in_wrappers "$COMMAND" reset && [[ "$GIT_SUB_REST" =~ (^|[[:space:]])--hard([[:space:]]|$) ]]; then
  block_with_reason "BLOCKED: git reset --hard discards all uncommitted changes and staged work. Use git reset (soft) or ask the user."
fi

# kill -9 / kill -KILL / kill -SIGKILL / kill -s 9 / kill -s KILL / kill -s SIGKILL / killall / pkill
# Wrapper-aware match via is_destruct_command_in_wrappers (#586, sister of
# #399's git-side closure). Falls back to is_destruct_command_in_chain for
# non-wrapper forms, preserving coverage of `git commit -m "msg" && kill -9
# 1234` (pre-existing test). Without the wrappers helper, `bash -c
# 'kill -9 1234'`, `eval 'killall node'`, `sh -c 'pkill foo'` and the
# path-prefixed `bash -c '/usr/bin/kill -9 1234'` variants silently
# bypassed the destruct gate even after #572 added path-strip to the
# base helper.
if is_destruct_command_in_wrappers "$COMMAND" kill '^-(9|KILL|SIGKILL)$' \
   || is_destruct_command_in_wrappers "$COMMAND" kill '^-s$:next:^(9|KILL|SIGKILL)$' \
   || is_destruct_command_in_wrappers "$COMMAND" killall '' \
   || is_destruct_command_in_wrappers "$COMMAND" pkill ''; then
  block_with_reason "BLOCKED: kill -9/killall/pkill can kill container-critical processes. Ask the user to stop the process manually."
fi

# fuser -k (kills whatever process holds a port — disrupts other sessions' dev servers and E2E tests)
# Catch -k alone, bundled flags (-km, -mk), and --kill
if [[ "$COMMAND" =~ fuser[[:space:]]+(.*-[a-z]*k[a-z]*|--kill) ]]; then
  block_with_reason "BLOCKED: fuser -k kills whatever process holds a port. Other sessions may need that dev server for E2E tests. Ask the user to stop the process manually."
fi

# xargs ... kill — the "identify PIDs by port/name, then kill them" pipeline.
# Spelled `lsof -ti :PORT | xargs kill`, `pgrep -f NAME | xargs kill`, `pidof X | xargs kill`,
# or `ps aux | grep ... | awk '{print $2}' | xargs kill`. All are the same anti-pattern as
# fuser -k: the PID source is unverified, so you kill whatever happened to match — which in
# the originating incident was the docker container. Matches any signal (bare, -9, -TERM).
# Allowed: kill with an explicit PID (`kill 1234`, `kill -TERM 1234`), the sanctioned
# helper `bash scripts/stop-dev.sh`, and `kill $(cat pidfile)` (below).
XARGS_KILL='xargs[[:space:]]+([^;&|]*[[:space:]]+)?kill([[:space:]]|[;&|]|$)'
if [[ "$COMMAND" =~ $XARGS_KILL ]]; then
  block_with_reason "BLOCKED: 'xargs … kill' identifies PIDs from stdin (usually lsof/pgrep/pidof output) and kills whatever matches — same hazard as fuser -k. Use bash scripts/stop-dev.sh (failing stub by default — edit it with your stop logic) to stop your dev server, or target a known PID with 'kill PID' directly."
fi

# kill $(lsof|pgrep|pidof|netstat …) / backtick equivalents — command-substitution variant
# of the same anti-pattern. Deliberately allows `kill $(cat pidfile)` since reading a known
# pid file is the canonical supervised-stop pattern.
#
# Known gaps (intentionally not regex-matched, to keep false-positive rate low):
#   * `ss` (2-char name, high FP surface: grep patterns, filenames, etc.)
#   * `ps` (2-char name, common file-extension suffix, high FP surface)
#   * Two-step variable capture: `pids=$(lsof -ti :P); kill $pids` — the `kill` command
#     sees only `$pids`, not the lsof substitution; hook is per-command, not cross-command.
#   * For-loops, readarray / process substitution, eval-wrapped: same root cause.
# These gaps are covered by the CLAUDE.md normative rule (and the fact that the `xargs …
# kill` family IS fully caught — agents reaching for `ss -ltnp | xargs kill` still hit the
# deny). The affirmative helper `bash scripts/stop-dev.sh` is the sanctioned path.
KILL_SUBST='kill[[:space:]]+([^[:space:];&|]+[[:space:]]+)*(\$\([^)]*|`[^`]*)(lsof|pgrep|pidof|netstat)([[:space:]]|[;&|]|\)|`|$)'
if [[ "$COMMAND" =~ $KILL_SUBST ]]; then
  block_with_reason "BLOCKED: 'kill \$(lsof…)' / 'kill \`pgrep…\`' / kill with pidof|netstat-substitution identifies PIDs by port/name and kills them — same hazard as fuser -k. Use bash scripts/stop-dev.sh (failing stub by default — edit it with your stop logic) to stop your dev server, or target a known PID with 'kill PID' directly."
fi

# ──────────────────────────────────────────────────────────────
# Destructive-op scope policy
# ──────────────────────────────────────────────────────────────
# Goal: permit contained cleanup under /tmp/, block anything else.
# The danger is destruction of unintended files via typos, unset
# variables (rm -rf "$UNSET" ≡ rm -rf ""), unsafe globs, or wrong cwd.
#
# Policy: a destructive command is permitted iff:
#   1. The command text contains `/tmp/<name>` as a literal path
#      (not just `/tmp` bare — must have a subdir), AND
#   2. The command has no shell metachars that could expand to an
#      unintended path: `$` (variable/substitution), backtick,
#      `*` / `?` (globs), or a leading `~` (HOME).
#
# Agents should use literal paths for destructive ops. Inside a
# script the agent invokes, the script body is NOT subject to this
# rule — the hook only sees the agent's own shell commands.
#
# Covered destructive ops: `rm -r` / `rm -rf` / `--recursive`,
# `find ... -delete`, `rsync ... --delete`, `xargs rm` / `xargs ... -delete`.

is_safe_destruct() {
  local cmd="$1"
  # Must include a literal /tmp/<identifier> path
  [[ "$cmd" =~ /tmp/[a-zA-Z0-9._-] ]] || return 1
  # Reject variable expansion or command substitution
  [[ "$cmd" == *'$'* ]] && return 1
  [[ "$cmd" == *'`'* ]] && return 1
  # Reject glob wildcards
  [[ "$cmd" == *'*'* ]] && return 1
  [[ "$cmd" == *'?'* ]] && return 1
  # Reject leading tilde (HOME expansion)
  [[ "$cmd" =~ (^|[[:space:]])~ ]] && return 1
  return 0
}

# rm -r / rm -rf (any flag combo that implies recursion)
RM_RECURSIVE='rm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*|--recursive)'
if [[ "$COMMAND" =~ $RM_RECURSIVE ]]; then
  if ! is_safe_destruct "$COMMAND"; then
    block_with_reason "BLOCKED: recursive rm requires a literal /tmp/<name> path. Variables (empty-expansion = rm -rf \\\"\\\"), wildcards, or paths outside /tmp/ are unsafe. Delete specific files by name, use a literal /tmp/ path, or ask the user."
  fi
fi

# find ... -delete
if [[ "$COMMAND" =~ find[[:space:]]+.*-delete ]]; then
  if ! is_safe_destruct "$COMMAND"; then
    block_with_reason "BLOCKED: find ... -delete requires a literal /tmp/<name> path. Variables or paths outside /tmp/ can sweep unintended files."
  fi
fi

# rsync ... --delete (mirror-sync that removes extras)
if [[ "$COMMAND" =~ rsync[[:space:]]+.*--delete ]]; then
  if ! is_safe_destruct "$COMMAND"; then
    block_with_reason "BLOCKED: rsync --delete requires a literal /tmp/<name> destination. Outside /tmp/ or with variables, an unintended expansion can clobber real work."
  fi
fi

# xargs rm / xargs find -delete (pipeline-driven destruction)
if [[ "$COMMAND" =~ xargs[[:space:]]+.*(rm|-delete) ]]; then
  if ! is_safe_destruct "$COMMAND"; then
    block_with_reason "BLOCKED: xargs rm / xargs -delete requires a literal /tmp/<name> path."
  fi
fi

# git add . / git add -A / git add --all (sweeps in unrelated changes)
# Use is_git_subcommand_in_wrappers (#399) so `bash -c 'git add -A'` /
# `eval 'git add .'` cannot bypass. The wrappers helper falls back to
# _in_chain on the outer command, then sets GIT_SUB_REST on match
# (whether via the chain or the recursive unwrap path) so the flag-regex
# check below still functions.
if is_git_subcommand_in_wrappers "$COMMAND" add && [[ "$GIT_SUB_REST" =~ (^|[[:space:]])(-A|--all|\.)([[:space:]]|$) ]]; then
  block_with_reason "BLOCKED: git add . / git add -A sweeps in ALL changes, including other sessions' work. Stage files by name: git add file1 file2."
fi

# git commit --no-verify (skips pre-commit hooks). Wrapper-recursion via
# is_git_subcommand_in_wrappers (#399) catches `bash -c "git commit
# --no-verify"` / `eval 'git commit --no-verify'`.
if is_git_subcommand_in_wrappers "$COMMAND" commit && [[ "$GIT_SUB_REST" =~ (^|[[:space:]])--no-verify([[:space:]]|$) ]]; then
  block_with_reason "BLOCKED: --no-verify skips pre-commit hooks. Hooks exist for safety — fix the hook failure, don't bypass it."
fi

# ─── git push: block main/master, allow feature branches ───────────
# Agents can push feature branches (needed for PR workflow) but not main.
# The user pushes main when ready: ! git push
#
# Detection: parse the push target from the command itself, not from
# git branch --show-current (which returns the MAIN repo's branch even
# when the agent is working in a worktree via cd).
if is_git_subcommand_in_wrappers "$COMMAND" push; then
  PUSH_TARGET=""
  # COMMAND is already the parsed shell command (with -m bodies redacted),
  # so no need to re-extract from the JSON.
  # Wrapper-recursion via is_git_subcommand_in_wrappers (#399) catches
  # `bash -c 'git push origin main'` / `eval 'git push'`.
  #
  # Use the tokens AFTER `push` that is_git_subcommand already extracted into
  # GIT_SUB_REST. That tokenizer is `-C`-aware (it skips `-C <dir>` / `-c <kv>`
  # before matching the subcommand, lines ~310-315) and segment-scoped (it
  # truncates at the first &&/||/;/| boundary). The previous ad-hoc
  # `${COMMAND##*git push}` string strip assumed `git` and `push` were
  # ADJACENT tokens, so the worktree form `git -C /tmp/wt push ...` — where the
  # literal substring "git push" never appears — was returned UNCHANGED and the
  # positional loop below misread `-C`'s directory argument as the remote and
  # `push` as a refspec, producing a garbage PUSH_REMOTE/PUSH_TARGET (#1037).
  # Reusing GIT_SUB_REST makes extraction consume the same `-C`-aware
  # tokenization the detection helper already uses, so
  # `git -C /tmp/wt push --force-with-lease origin feat/x` parses identically
  # to `cd /tmp/wt && git push --force-with-lease origin feat/x`.
  PUSH_CMD="$GIT_SUB_REST"

  # Parse positional args after "git push": [-u] [remote] [refspec]
  # Strip flags (-u, --set-upstream, -f, --force, etc.) and find positional args.
  # GIT_SUB_REST is already segment-scoped (chaining stripped), but keep the
  # chain-boundary guard for defense-in-depth.
  PUSH_ARGS=""
  for word in $PUSH_CMD; do
    case "$word" in
      "&&"*|";"*|"|"*) break ;;  # stop at command chaining
      -*) continue ;;  # skip flags
      *) PUSH_ARGS="$PUSH_ARGS $word" ;;
    esac
  done
  # PUSH_ARGS is now "remote refspec" or "remote" or ""
  PUSH_REMOTE=$(echo "$PUSH_ARGS" | awk '{print $1}')
  PUSH_TARGET=$(echo "$PUSH_ARGS" | awk '{print $2}')

  # If no explicit refspec, fall back to current branch
  if [ -z "$PUSH_TARGET" ]; then
    PUSH_TARGET=$(git branch --show-current 2>/dev/null)
  fi

  # Strip local-side of refspec if present (e.g., local:remote). The
  # destination/remote-side after the colon is what determines whether the
  # push targets main/master. Past bug (#392): ${X%%:*} kept the LEFT side
  # (local), so `git push origin feat:main` resolved PUSH_TARGET=feat and
  # the rule below let the push through, force-shipping local feat to
  # remote main. ${X##*:} keeps the RIGHT side (remote). For non-refspec
  # values (no colon), both expansions return the input unchanged.
  PUSH_TARGET="${PUSH_TARGET##*:}"
  # Strip trailing single/double quote that wrapper-unwrapped forms can
  # leave behind. `bash -c 'git push origin main'` → PUSH_TARGET=main' →
  # without strip, equality check against literal "main" fails and the
  # bypass succeeds even though _in_wrappers caught it (#399). Strip one
  # layer each side so quoted bash-c / eval inner strings still classify.
  PUSH_TARGET="${PUSH_TARGET%\'}"; PUSH_TARGET="${PUSH_TARGET#\'}"
  PUSH_TARGET="${PUSH_TARGET%\"}"; PUSH_TARGET="${PUSH_TARGET#\"}"
  # Strip leading '+' from force-prefix refspec form. `git push origin +main`
  # is the no-colon force-push spelling; without this strip, PUSH_TARGET=+main
  # falls through the equality check against literal "main" and the rule
  # doesn't fire (#457). Strip after the colon-RHS normalization so forms
  # like `+HEAD:main` (already reduced to "main") and `+main` (reduced to
  # "+main") both classify correctly.
  PUSH_TARGET="${PUSH_TARGET#+}"
  # Strip leading 'refs/heads/' prefix. `git push origin refs/heads/main` is
  # the fully-qualified branch ref spelling that Git accepts as equivalent
  # to `main`; without this strip, PUSH_TARGET="refs/heads/main" falls
  # through the equality check against literal "main" and the rule doesn't
  # fire (#470). Strip after the '+' strip so `+refs/heads/main` also
  # normalizes to "main".
  PUSH_TARGET="${PUSH_TARGET#refs/heads/}"
  # If PUSH_TARGET is "HEAD", resolve to current local branch — Git pushes
  # `origin HEAD` as the current-branch's remote-tracking ref (server-side
  # resolution), defeating literal main/master string compare. Without this,
  # `git push origin HEAD` from a `main` checkout silently bypassed the
  # main-protection regime (#515). Apply AFTER colon-RHS / + / refs/heads/
  # normalizations so all `HEAD`-bearing spellings (`+HEAD`, `refs/heads/HEAD`)
  # also resolve.
  if [ "$PUSH_TARGET" = "HEAD" ]; then
    PUSH_TARGET=$(git branch --show-current 2>/dev/null)
  fi

  # ── Resolve main-push block from config (runtime, fail-closed) ──────
  # Mirror block-main-edits.sh's pattern: resolve the config root the same
  # way (REPO_ROOT override → CLAUDE_PROJECT_DIR → git toplevel → pwd), then
  # read execution.main_protected from .claude/zskills-config.json.
  #
  # FAIL CLOSED: BLOCK_MAIN_PUSH defaults to 1. We only flip it to 0 (allow)
  # when the config file EXISTS, is readable, AND explicitly carries
  # `"main_protected": false`. An absent / unreadable / unparseable config
  # leaves it at 1 (block) — the safer posture for zskills-shipped configs.
  PUSH_CONFIG_ROOT="${REPO_ROOT:-${CLAUDE_PROJECT_DIR:-}}"
  if [ -z "$PUSH_CONFIG_ROOT" ]; then
    PUSH_CONFIG_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  fi
  PUSH_CONFIG_FILE="$PUSH_CONFIG_ROOT/.claude/zskills-config.json"
  BLOCK_MAIN_PUSH=1
  if [ -f "$PUSH_CONFIG_FILE" ]; then
    PUSH_CFG_CONTENT=$(cat "$PUSH_CONFIG_FILE" 2>/dev/null) || PUSH_CFG_CONTENT=""
    # Explicit `false` → allow. Anything else (including missing key, true,
    # or unparseable garbage) → stay blocked (fail closed).
    if [[ "$PUSH_CFG_CONTENT" =~ \"main_protected\"[[:space:]]*:[[:space:]]*false ]]; then
      BLOCK_MAIN_PUSH=0
    fi
  fi

  if [ "$BLOCK_MAIN_PUSH" = "1" ] && { [ "$PUSH_TARGET" = "main" ] || [ "$PUSH_TARGET" = "master" ]; }; then
    block_with_reason "BLOCKED: Agents must not push to main/master. Push feature branches instead, or the user can run: ! git push"
  fi
fi

# No match — allow
exit 0
