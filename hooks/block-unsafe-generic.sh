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

INPUT=$(cat)

# Only filter Bash commands
if [[ "$INPUT" != *'"tool_name":"Bash"'* ]] && [[ "$INPUT" != *'"tool_name": "Bash"'* ]]; then
  exit 0
fi

# Block patterns — each with a reason
block_with_reason() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$1"
  exit 0
}

# git stash drop / git stash clear — destroys stashed work permanently
if [[ "$INPUT" =~ git[[:space:]]+stash[[:space:]]+(drop|clear) ]]; then
  block_with_reason "BLOCKED: git stash drop/clear destroys stashed work permanently (including untracked files saved with -u). If you need to drop a stash, ask the user to do it manually."
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

# rm -rf / rm -r -f (mass deletion, with separate or combined flags)
if [[ "$INPUT" =~ rm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*f|(-r[[:space:]]+-f|-f[[:space:]]+-r)|--recursive[[:space:]]+--force|--force[[:space:]]+--recursive) ]]; then
  block_with_reason "BLOCKED: rm -rf performs mass file deletion. Delete specific files by name, or ask the user."
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

  if [ "$PUSH_TARGET" = "main" ] || [ "$PUSH_TARGET" = "master" ]; then
    block_with_reason "BLOCKED: Agents must not push to main/master. Push feature branches instead, or the user can run: ! git push"
  fi
fi

# No match — allow
exit 0
