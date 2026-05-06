#!/bin/bash
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
# Known carve-outs (documented in references/skill-version-pretooluse-hook.md
# §D5 and Phase 2 D&C):
#   - `bash -c '<git commit ...>'` / `sh -c '...'` / `eval '...'` are NOT
#     matched. The tokenize-then-walk requires the FIRST non-env-prefix
#     token to be literal `git`; we deliberately do not recurse into the
#     argument string of bash -c / sh -c / eval (re-introducing a
#     regex-fragility class). This is a minor local-development hole;
#     CI's conformance gate is the structural backstop. Test C10e in
#     tests/test-block-stale-skill-version.sh locks this behavior.
#
# Pure bash at runtime (D4 in the reference doc) — no external JSON
# parsers, no scripting-language interpreters. The unit-test harness MAY
# use a separate JSON validator for assertions; the hook itself does not.

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

# Match `git commit` via two-stage tokenize-then-walk. Rationale: a single
# regex that allows arbitrary git top-level flags (--no-pager, --git-dir=/x,
# -P, -C path, -c k=v, --work-tree=/y, …) becomes a combinatorial mess and
# was empirically shown bypassable in Round 2 finding N1 (e.g.,
# `git --no-pager commit` slipped past the narrow `(-C …|-c …)?` form).
# Tokenize on whitespace, skip env-var prefixes, find literal `git`, then
# walk past every `-…`/`--…` flag (consuming an extra token only for `-C`
# and `-c`, which take a separate arg — all other top-level flags either
# embed their value with `=` or take none) and check if the next token is
# `commit`.
#
# Carve-out: this matcher does NOT recurse into `bash -c '...'` /
# `sh -c '...'` / `eval '...'` argument strings — see header docstring
# and test C10e.
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
is_git_subcommand "$COMMAND" commit || exit 0

# Guard against `set -u` + unset `$CLAUDE_PROJECT_DIR` (rare but documented
# harness edge case). `${X:-$PWD}` falls back to cwd; if the script is
# absent under the fallback path, `[ -x ]` trips the fail-open below. Per
# Round 2 N5: without the guard, `set -u` would crash the hook → nonzero
# exit + empty stdout → silent failure mode worse than fail-open.
SCRIPT="${CLAUDE_PROJECT_DIR:-$PWD}/scripts/skill-version-stage-check.sh"
[ -x "$SCRIPT" ] || exit 0  # fail-open: script absent (consumer pre-/update-zskills)

# Run script; capture stderr (the STOP message); discard stdout.
STDERR=$(bash "$SCRIPT" 2>&1 >/dev/null) && exit 0  # rc=0 means clean
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
