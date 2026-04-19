#!/bin/bash
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

# ─── Preset toggle: main-push block ────────────────────────────────
# Controls the "git push main/master" deny rule further down in this
# file. Flipped by /update-zskills when a preset is applied:
#   cherry-pick (default)  -> BLOCK_MAIN_PUSH=0
#   locked-main-pr         -> BLOCK_MAIN_PUSH=1
#   direct                 -> BLOCK_MAIN_PUSH=0
# Default here is 1 so zskills-shipped configs fail closed (safer).
# Installer flips this single line via Edit; do not inline-expand further below.
BLOCK_MAIN_PUSH=1

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

# Block patterns — each with a reason
block_with_reason() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$1"
  exit 0
}

# git stash — command-boundary matching only. A bare `git[[:space:]]+stash`
# match (anywhere in the command) overmatches on quoted strings (commit
# messages, echo/printf/grep args that mention stash) and on the hook's own
# error messages when they're ever echo'd. Gating on command-start or shell
# separator (;, &, &&, ||, |, newline, backtick, $()) keeps the match scoped
# to ACTUAL stash invocations.
#
# Allowed subcommands: apply, list, show, pop, create, store, branch (read
# and recovery — never modify the working tree).
# Destructive: drop, clear — block (prior behavior).
# Create-stash: push, save, -u, bare — block (CLAUDE.md rule).
#
# Past failure: a /commit pre-commit reviewer ran `stash -u && test && stash
# pop`; the pop silently unstaged the caller's staged files.
STASH_BOUNDARY='(^|[;&|`(]|&&|\|\||\$\()[[:space:]]*git[[:space:]]+stash'
STASH_ALLOW_SUB="${STASH_BOUNDARY}[[:space:]]+(apply|list|show|pop|create|store|branch)([[:space:]]|\\\"|'|\\\\|\||;|\$)"
STASH_DESTRUCTIVE="${STASH_BOUNDARY}[[:space:]]+(drop|clear)"
if [[ "$COMMAND" =~ $STASH_DESTRUCTIVE ]]; then
  block_with_reason "BLOCKED: git stash drop/clear destroys stashed work permanently (including untracked files saved with -u). If you need to drop a stash, ask the user to do it manually."
elif [[ "$COMMAND" =~ $STASH_BOUNDARY ]] && [[ ! "$COMMAND" =~ $STASH_ALLOW_SUB ]]; then
  block_with_reason "BLOCKED: git-stash write subcommand forbidden (modifies working tree). Allowed read/recovery: apply, list, show, pop. For cherry-pick protection, let git refuse on overlap."
fi

# git checkout -- (any file or blanket) — discards uncommitted changes permanently
if [[ "$INPUT" =~ git[[:space:]]+checkout[[:space:]]+-- ]]; then
  block_with_reason "BLOCKED: git checkout -- discards uncommitted changes permanently. This may destroy other sessions' work. If you need to undo your own change, use git diff to see what changed and edit it back manually."
fi

# git restore (any file or blanket) — modern equivalent of checkout --
if [[ "$INPUT" =~ git[[:space:]]+restore[[:space:]] ]]; then
  block_with_reason "BLOCKED: git restore discards uncommitted changes permanently. If you need to undo your own change, use git diff to see what changed and edit it back manually."
fi

# git clean -f (permanent file deletion)
if [[ "$INPUT" =~ git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*f ]]; then
  block_with_reason "BLOCKED: git clean -f permanently deletes untracked files. These cannot be recovered from git."
fi

# git reset --hard (discards everything)
if [[ "$INPUT" =~ git[[:space:]]+reset[[:space:]]+--hard ]]; then
  block_with_reason "BLOCKED: git reset --hard discards all uncommitted changes and staged work. Use git reset (soft) or ask the user."
fi

# kill -9 / kill -KILL / kill -SIGKILL / kill -s 9 / kill -s KILL / kill -s SIGKILL / killall / pkill
if [[ "$INPUT" =~ kill[[:space:]]+(-9|-KILL|-SIGKILL|-s[[:space:]]+(9|KILL|SIGKILL)) ]] || [[ "$INPUT" =~ killall[[:space:]] ]] || [[ "$INPUT" =~ pkill[[:space:]] ]]; then
  block_with_reason "BLOCKED: kill -9/killall/pkill can kill container-critical processes. Ask the user to stop the process manually."
fi

# fuser -k (kills whatever process holds a port — disrupts other sessions' dev servers and E2E tests)
# Catch -k alone, bundled flags (-km, -mk), and --kill
if [[ "$INPUT" =~ fuser[[:space:]]+(.*-[a-z]*k[a-z]*|--kill) ]]; then
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
  block_with_reason "BLOCKED: 'xargs … kill' identifies PIDs from stdin (usually lsof/pgrep/pidof output) and kills whatever matches — same hazard as fuser -k. Use bash scripts/stop-dev.sh for your own dev server, or target a known PID with 'kill PID' directly."
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
  block_with_reason "BLOCKED: 'kill \$(lsof…)' / 'kill \`pgrep…\`' / kill with pidof|netstat-substitution identifies PIDs by port/name and kills them — same hazard as fuser -k. Use bash scripts/stop-dev.sh for your own dev server, or target a known PID with 'kill PID' directly."
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
# Note: in raw JSON, "git add ." appears as ...git add ."... so we also match \."
if [[ "$INPUT" =~ git[[:space:]]+add[[:space:]]+(-A|--all|\.([[:space:]]|\"|\|)) ]] || [[ "$INPUT" =~ git[[:space:]]+add[[:space:]]+\.$ ]]; then
  block_with_reason "BLOCKED: git add . / git add -A sweeps in ALL changes, including other sessions' work. Stage files by name: git add file1 file2."
fi

# git commit --no-verify (skips pre-commit hooks)
if [[ "$INPUT" =~ git[[:space:]]+commit[[:space:]]+.*--no-verify ]]; then
  block_with_reason "BLOCKED: --no-verify skips pre-commit hooks. Hooks exist for safety — fix the hook failure, don't bypass it."
fi

# ─── git push: block main/master, allow feature branches ───────────
# Agents can push feature branches (needed for PR workflow) but not main.
# The user pushes main when ready: ! git push
#
# Detection: parse the push target from the command itself, not from
# git branch --show-current (which returns the MAIN repo's branch even
# when the agent is working in a worktree via cd).
if [[ "$INPUT" =~ git[[:space:]]+push ]]; then
  PUSH_TARGET=""
  # Extract the command string from JSON input
  PUSH_CMD=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | sed 's/\\"/"/g')
  if [ -z "$PUSH_CMD" ]; then
    PUSH_CMD=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  fi

  # Strip everything before "git push" (e.g., "cd /tmp/path &&")
  PUSH_CMD="${PUSH_CMD##*git push}"

  # Parse positional args after "git push": [-u] [remote] [refspec]
  # Strip flags (-u, --set-upstream, -f, --force, etc.) and find positional args
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

  # Strip remote-side of refspec if present (e.g., local:remote)
  PUSH_TARGET="${PUSH_TARGET%%:*}"

  if [ "$BLOCK_MAIN_PUSH" = "1" ] && { [ "$PUSH_TARGET" = "main" ] || [ "$PUSH_TARGET" = "master" ]; }; then
    block_with_reason "BLOCKED: Agents must not push to main/master. Push feature branches instead, or the user can run: ! git push"
  fi
fi

# No match — allow
exit 0
