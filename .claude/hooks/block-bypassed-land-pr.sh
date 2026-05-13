#!/bin/bash
# block-bypassed-land-pr.sh — PreToolUse Bash hook.
#
# Unconditionally denies direct `gh pr create` and `gh pr merge --auto`
# invocations from agent Bash. These are the two ways an agent can
# bypass /land-pr's discipline (rebase → push → PR create → CI poll →
# fix-cycle on failure → auto-merge handling) and ship a PR without the
# guarantees the caller skills enforce.
#
# Behavior:
#   1. Filter: only Bash tool invocations are inspected (early exit 0).
#   2. Extract the `command` field from stdin via the canonical
#      block-unsafe-generic.sh sed pattern (with $INPUT fallback on
#      extract failure for defensive scanning).
#   3. Bash-only short-circuit on absence of `"gh pr "` substring —
#      avoids invoking the helper for every `ls`, `cat`, `git commit`
#      (DA-1-9 perf guard).
#   4. Tokenize-then-walk match for `gh pr create` and `gh pr merge
#      --auto` via the inlined is_gh_pr_subcommand_in_chain helper. The
#      chain wrapper handles cd-chained forms
#      (`cd /tmp/wt && gh pr create`).
#   5. On match: invoke scripts/land-pr-bypass-message.sh to read the
#      tracking tree and emit the diagnostic STOP message (Pattern 1
#      "no caller mid-flight, true bypass" vs Pattern 2 "caller
#      mid-flight, /land-pr errored — recovery hint"). Capture stderr.
#   6. Sentinel-anchored fallback (DA-5-5): if captured stderr does NOT
#      contain the canonical anchor `STOP: direct gh pr`, substitute
#      the static fallback STOP message text. This guards against the
#      script being missing/broken AND against the script crashing
#      partway with a bash error trace as stderr — both of which would
#      leak internal state to the agent and risk a misinterpreted
#      "the hook itself is broken — try a bash -c bypass" reaction.
#   7. Emit deny envelope (verbatim shape from
#      block-stale-skill-version.sh) via inlined pure-bash json_escape.
#
# Differs from block-stale-skill-version.sh in one key way: there,
# fail-open on missing script means ALLOW (consumer may not have
# /update-zskills'd yet — a stale stage-check is not worth bricking
# every commit). Here, the deny decision is UNCONDITIONAL — only the
# message-enrichment fails-open to the static fallback. The hook still
# denies even if scripts/land-pr-bypass-message.sh is absent or
# crashing; the only thing the script controls is which STOP wording
# the agent sees.
#
# Carve-out: /land-pr's own `gh pr create` lives inside
# pr-push-and-create.sh (a script /land-pr invokes via
# `bash $script_path`). PreToolUse Bash hooks see the outer
# `bash scripts/pr-push-and-create.sh ...` invocation, not the inner
# `gh pr create` inside that script — so the hook NEVER fires on
# /land-pr's own gh invocation. No allowlist needed.

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

# Bash-only early-exit short-circuit (DA-1-9). The substring filter is a
# fast O(strlen) check that avoids tokenize-walk on commands that can't
# possibly match. Require BOTH `gh ` (somewhere) AND `pr ` (somewhere) —
# adjacent-form `gh pr create` and walk-past-form
# `gh --repo=foo/bar pr create` (AC1.11) both satisfy this, while `ls`,
# `cat`, `git commit`, etc. exit early. The trailing spaces rule out
# `pre` / `program` style false-prefix substrings.
case "$COMMAND" in
  *"gh "*"pr "*) ;;  # fall through to tokenize-walk
  *) exit 0 ;;
esac

# Inlined from hooks/_lib/git-tokenwalk.sh (source-of-truth).
# Drift gate: tests/test-hook-helper-drift.sh.
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

# Inlined from hooks/_lib/git-tokenwalk.sh (source-of-truth).
# Drift gate: tests/test-hook-helper-drift.sh.
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

# Inlined from hooks/_lib/git-tokenwalk.sh (source-of-truth).
# Drift gate: tests/test-hook-helper-drift.sh.
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


# Match via inlined helpers. Two independent checks (create / merge --auto)
# combined disjunctively into a single deny signal.
deny=0
is_gh_pr_subcommand_in_wrappers "$COMMAND" "create" && deny=1
is_gh_pr_subcommand_in_wrappers "$COMMAND" "merge" '^--auto$' && deny=1
[ "${deny:-0}" -eq 0 ] && exit 0

# Resolve message-enrichment script. Same `${X:-$PWD}` fallback pattern as
# block-stale-skill-version.sh (guards against `set -u` + unset
# CLAUDE_PROJECT_DIR).
SCRIPT="${CLAUDE_PROJECT_DIR:-$PWD}/scripts/land-pr-bypass-message.sh"

# Static fallback STOP message — ASCII-only, 3 lines. Used when the
# message-enrichment script is missing/broken (see sentinel check
# below). The hook STILL DENIES — only the wording falls back.
STATIC_FALLBACK='STOP: direct gh pr (create|merge --auto) from agent Bash bypasses /land-pr.
Use /commit pr / /quickfix / /do pr / /fix-issues pr, or dispatch Skill { skill: "land-pr" }.
Open a SEPARATE terminal for legitimate one-off manual operations.'

USE_STATIC_FALLBACK=0
STDERR=""
if [ -x "$SCRIPT" ]; then
  # Run the message-enrichment script. Capture stderr (the STOP message);
  # discard stdout. The script exits 1 on success-with-deny-message;
  # rc itself is informational here — the sentinel-anchor check below
  # is what determines whether the captured body is usable.
  STDERR=$(bash "$SCRIPT" 2>&1 >/dev/null)
else
  # Fail-open scope narrows to message-enrichment ONLY: deny decision
  # is unconditional. Deliberate divergence from
  # block-stale-skill-version.sh:126 (which fails-open on missing
  # script meaning allow).
  USE_STATIC_FALLBACK=1
fi

# Sentinel-anchored fallback (DA-3-6 + R-4-4 + DA-5-5). The canonical
# anchor `STOP: direct gh pr` proves the script ran to completion and
# emitted real STOP content. Its absence — empty stderr, partial
# stderr, OR a bash error trace like
# `bash: scripts/land-pr-bypass-message.sh: line 47: foo: command not found`
# — falls back to the static body. This avoids leaking internal stack
# traces as `permissionDecisionReason` and avoids confusing the
# Pattern 1 / Pattern 2 distinction.
if ! printf '%s' "$STDERR" | grep -qF 'STOP: direct gh pr'; then
  USE_STATIC_FALLBACK=1
fi

if [ "$USE_STATIC_FALLBACK" -eq 1 ]; then
  STDERR="$STATIC_FALLBACK"
fi

# Pure-bash JSON string escape (verbatim from
# block-stale-skill-version.sh:132-159). LC_ALL=C makes ${var//pat/repl}
# byte-deterministic; [[:cntrl:]] strips remaining control bytes (the
# bash range form $'\x00'-$'\x1f' silently matches only the upper-bound
# byte — verified empirically in block-stale-skill-version.sh's Round 2
# finding N2).
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
