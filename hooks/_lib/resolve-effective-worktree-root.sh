#!/bin/bash
# hooks/_lib/resolve-effective-worktree-root.sh — source-of-truth helper bodies
# for the cd-target + effective-worktree-root resolution pattern used by every
# PreToolUse Bash hook that needs to "act on the worktree the agent is in"
# rather than the hook's ambient main-repo CWD.
#
# Hooks run in a separate subprocess rooted at $CLAUDE_PROJECT_DIR (= the
# main repo). When an agent invokes a worktree-scoped command via
# `cd /tmp/wt && git commit` (or `git push`, `git cherry-pick`), the hook
# must resolve the worktree root, not its own ambient CWD, before reading
# `.zskills/tracked` (legacy root `.zskills-tracked` during the Phase 8
# dual-read window), running `git -C <root> diff --cached`, or invoking
# scripts/skill-version-stage-check.sh.
#
#   extract_cd_target              — sed-extracts a leading `cd <target>` from
#                                    the hook's JSON-wire $INPUT and echoes
#                                    the target if it exists on disk
#                                    (4 hook call sites).
#   resolve_effective_worktree_root — 3-way fallback (env_override → cd_target
#                                    → fallback) collapsing the inline if/else
#                                    that previously lived at each site.
#
# Both helpers are inlined verbatim into hook source files; the drift gate at
# tests/test-hook-helper-drift.sh enforces byte-equality at CI time:
#   - extract_cd_target               inlined into
#       hooks/block-unsafe-project.sh.template (3 use sites: commit/cherry-pick/push)
#       hooks/block-stale-skill-version.sh     (1 use site: stage-check subshell)
#   - resolve_effective_worktree_root inlined into the same 4 sites.
#
# Maintain HERE only.
set -u

# Extract the cd target from $INPUT (the PreToolUse JSON wire envelope).
# Returns:
#   - The cd target (echoed to stdout) iff:
#       (a) $INPUT's "command" field contains a `cd <target>` statement
#           after a possibly-empty preamble of inert / env-mutating shell
#           statements. Segment-walks over `;`, `&&`, `||`, `|`, and
#           newline separators and skips segments whose first token is
#           one of: env-var assignment (`KEY=val`), `set …`, `export …`,
#           `unset …`, `source …`/`. …`, the `:` builtin, the `env`
#           wrapper preamble. The first `cd <target>` segment encountered
#           wins. Issue #924: a preamble like
#           `set -e; export X=Y; . resolver.sh && cd $WT && git commit`
#           previously failed to extract because the regex required a
#           leading `cd`; agents commonly emit such preambles for
#           orchestrator-side worktree bookkeeping.
#       (b) <target> resolves to an existing directory on disk
#   - Empty stdout otherwise.
#
# JSON wire format escapes embedded newlines as the two-character sequence
# `\n`. Decode here so `cd /tmp/wt\ngit commit` captures `/tmp/wt`, not
# `/tmp/wt\ngit`. The `\"` escape is also decoded for symmetry with the
# canonical command extraction in block-unsafe-generic.sh.
#
# Reads $INPUT from the caller's scope (the hook's captured stdin JSON
# envelope). Callers MUST set $INPUT before invoking this function.
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

# Resolve the effective worktree root via 3-way fallback. The caller passes
# in the values it wants to consider at each tier; this helper just picks the
# first non-empty one. This factoring lets the 3 block-unsafe-project sites
# share precedence (LOCAL_ROOT env override → cd target → git-rev-parse
# fallback) while block-stale-skill-version uses a different fallback
# (CLAUDE_PROJECT_DIR) and skips the env-override tier.
#
# Args:
#   $1 — env_override (e.g., "${LOCAL_ROOT:-}" for test injection; empty to
#        skip the env-override tier entirely)
#   $2 — cd_target (e.g., "$(extract_cd_target)"; empty when the command has
#        no leading cd or the target doesn't exist)
#   $3 — fallback (e.g., "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
#        or "${CLAUDE_PROJECT_DIR:-$PWD}"; must be non-empty — this is the
#        final fallback and is always echoed if the first two tiers are empty)
#
# Echoes the resolved root to stdout. Always echoes something (the fallback
# is mandatory). Caller assigns into the var of its choice (LOCAL_ROOT,
# EFFECTIVE_REPO_ROOT, etc.).
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
