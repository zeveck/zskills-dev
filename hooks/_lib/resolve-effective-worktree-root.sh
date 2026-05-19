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
# `.zskills-tracked`, running `git -C <root> diff --cached`, or invoking
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
#       (a) $INPUT's "command" field begins with `cd <target>`
#           (env-var prefixes are NOT skipped — KEY=VAL cd /tmp/wt is not
#           recognized as a worktree-cd; this is intentional, agents do
#           not prefix `cd` with env-vars in practice)
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
