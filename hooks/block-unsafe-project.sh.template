#!/bin/bash
# Block unsafe commands — PROJECT-SPECIFIC enforcement layer.
# No external dependencies — bash and git only.
#
# This file is a template. Replace {{PLACEHOLDER}} values and remove
# sections that don't apply to your project.
#
# Register BOTH this file and block-unsafe-generic.sh in .claude/settings.json
# on the PreToolUse event, Bash matcher. The generic layer runs first.

INPUT=$(cat)

# Only filter Bash commands
if [[ "$INPUT" != *'"tool_name":"Bash"'* ]] && [[ "$INPUT" != *'"tool_name": "Bash"'* ]]; then
  exit 0
fi

# Block patterns -- each with a reason
block_with_reason() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$1"
  exit 0
}

# Extract transcript_path from JSON input using bash only
extract_transcript() {
  if [[ "$INPUT" =~ \"transcript_path\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    echo "${BASH_REMATCH[1]}"
  fi
}

# Extract the cd target from the command (e.g., "cd /tmp/worktree && git push")
# Hooks run in the main repo CWD, not the agent's cd target. This helper
# lets us find .zskills-tracked in the correct directory for worktree agents.
extract_cd_target() {
  local cmd
  cmd=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | sed 's/\\"/"/g')
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

# --- main_protected access control ---
# Reads config at runtime (not baked in during /update-zskills).
# Changing the config takes effect immediately.
is_main_protected() {
  local config_file
  local repo_root="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  config_file="$repo_root/.claude/zskills-config.json"
  if [ -f "$config_file" ]; then
    local content
    content=$(cat "$config_file" 2>/dev/null) || return 1
    if [[ "$content" =~ \"main_protected\"[[:space:]]*:[[:space:]]*true ]]; then
      return 0
    fi
  fi
  return 1
}

is_on_main() {
  local branch
  local repo_root="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  branch=$(git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null)
  [[ "$branch" == "main" || "$branch" == "master" ]]
}

# ─── Tracking file protection ───
# Block recursive deletion of tracking directory
if [[ "$INPUT" =~ rm[[:space:]].*-[a-zA-Z]*r[a-zA-Z]*.*\.zskills/tracking ]]; then
  block_with_reason "BLOCKED: Cannot recursively delete tracking directory. To clear tracking state: ! bash scripts/clear-tracking.sh"
fi

# Block agent execution of clear-tracking script (reading is OK)
if [[ "$INPUT" =~ (bash[[:space:]]|[^a-zA-Z]sh[[:space:]]|\.\/).*clear-tracking ]]; then
  block_with_reason "BLOCKED: Only the user can run the clear-tracking script. Run: ! bash scripts/clear-tracking.sh"
fi

# ─── Config file protection ───
# Config lives at .claude/zskills-config.json — protected by Claude Code's
# built-in permission system on ALL tools (Bash, Write, Edit). No custom
# hook needed. Agent writes trigger a permission prompt automatically.

# ─── CONFIGURE: remove this section if you don't use session logging ───
# git add .claude/logs/ (sweeps in all sessions' logs -- stage specific files)
if [[ "$INPUT" =~ git[[:space:]]+add[[:space:]]+\.claude/logs/?([[:space:]]|$) ]]; then
  block_with_reason "BLOCKED: git add .claude/logs/ sweeps in ALL sessions' logs. Stage your session's logs by name: git add .claude/logs/*-<session-id>*.md"
fi

# ─── CONFIGURE: set your test command patterns ────────────────────────
# Piping test output (loses failures, forces re-runs -- capture to file instead)
# Replace the placeholder values with your actual test command patterns.
UNIT_TEST_CMD="{{UNIT_TEST_CMD}}"
FULL_TEST_CMD="{{FULL_TEST_CMD}}"

# Build regex pattern from configured test commands (fall back to generic if unconfigured)
if [[ "$UNIT_TEST_CMD" == *'{{'* ]] || [[ "$FULL_TEST_CMD" == *'{{'* ]]; then
  # Placeholders not replaced -- use a generic pattern that catches common test runners
  TEST_PIPE_PATTERN='npm[[:space:]]+test([[:space:]]|$)|npm[[:space:]]+run[[:space:]]+test(:[^[:space:]]+)?([[:space:]]|$)|node[[:space:]]+--test[[:space:]]'
else
  # Escape dots and special chars for bash regex
  ESCAPED_UNIT="${UNIT_TEST_CMD//./\\.}"
  ESCAPED_FULL="${FULL_TEST_CMD//./\\.}"
  # Replace spaces with flexible whitespace
  ESCAPED_UNIT="${ESCAPED_UNIT// /[[:space:]]+}"
  ESCAPED_FULL="${ESCAPED_FULL// /[[:space:]]+}"
  TEST_PIPE_PATTERN="(${ESCAPED_UNIT}|${ESCAPED_FULL})"
fi

if [[ "$INPUT" =~ $TEST_PIPE_PATTERN ]] && [[ "$INPUT" == *'|'* ]]; then
  block_with_reason "Don't pipe test output -- it loses failure details. Instead: ${FULL_TEST_CMD:-npm run test:all} > .test-results.txt 2>&1 then read the file. To inspect results, grep the captured file."
fi

# --- main_protected: block git commit on main ---
if [[ "$INPUT" =~ git[[:space:]]+commit ]] && is_main_protected && is_on_main; then
  block_with_reason "BLOCKED: main branch is protected (main_protected: true in .claude/zskills-config.json). Create a feature branch or use PR mode. To change: edit .claude/zskills-config.json"
fi

# ─── CONFIGURE: set your full test command ────────────────────────────
# Safety net: transcript-based verification on git commit
# Ensures tests were run before committing code files.
if [[ "$INPUT" =~ git[[:space:]]+commit ]]; then
  TRANSCRIPT=$(extract_transcript)
  if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    FULL_TEST_CHECK="${FULL_TEST_CMD}"
    if [[ "$FULL_TEST_CHECK" == *'{{'* ]]; then
      # Placeholder not replaced -- warn only if project has test infrastructure
      REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
      HAS_TESTS=false
      if [ -f "$REPO_ROOT/package.json" ]; then
        PACKAGE_CONTENT=$(<"$REPO_ROOT/package.json")
        if [[ "$PACKAGE_CONTENT" == *'"test"'* ]]; then
          HAS_TESTS=true
        fi
      fi
      if ! $HAS_TESTS; then
        for f in "$REPO_ROOT"/pytest.ini "$REPO_ROOT"/jest.config.* "$REPO_ROOT"/vitest.config.* "$REPO_ROOT"/.mocharc.* "$REPO_ROOT"/Makefile; do
          if [[ -f "$f" ]]; then
            HAS_TESTS=true
            break
          fi
        done
      fi
      if $HAS_TESTS; then
        block_with_reason "BLOCKED: Test infrastructure detected but FULL_TEST_CMD not configured in block-unsafe-project.sh. Configure it so the pre-commit test check works."
      fi
    else
      # Check if full test command was run in this session
      TRANSCRIPT_CONTENT=$(cat "$TRANSCRIPT" 2>/dev/null) || TRANSCRIPT_CONTENT=""
      if [[ "$TRANSCRIPT_CONTENT" != *"$FULL_TEST_CHECK"* ]]; then
        # Check if any code files are being committed (skip check for content-only)
        DIFF_OUTPUT=$(git diff --cached --name-only 2>/dev/null)
        CODE_FILES=""
        while IFS= read -r line; do
          if [[ "$line" =~ \.(js|ts|json|css|html|rs|py|go|rb)$ ]]; then
            CODE_FILES+="$line"$'\n'
          fi
        done <<< "$DIFF_OUTPUT"
        if [ -n "$CODE_FILES" ]; then
          block_with_reason "BLOCKED: Committing code but '${FULL_TEST_CHECK}' was not found in the session transcript. Run tests before committing. (Content-only commits are exempt.)"
        fi
      fi
    fi

    # ─── CONFIGURE: set your UI source paths, or remove this section if not applicable ───
    # Check if UI files changed but no playwright-cli verification
    UI_FILE_PATTERNS="{{UI_FILE_PATTERNS}}"
    if [[ "$UI_FILE_PATTERNS" != '{{UI_FILE_PATTERNS}}' ]]; then
      UI_DIFF_OUTPUT=$(git diff --cached --name-only 2>/dev/null)
      UI_FILES=""
      while IFS= read -r line; do
        if [[ "$line" =~ $UI_FILE_PATTERNS ]]; then
          UI_FILES+="$line"$'\n'
        fi
      done <<< "$UI_DIFF_OUTPUT"
      if [ -n "$UI_FILES" ]; then
        TRANSCRIPT_CONTENT="${TRANSCRIPT_CONTENT:-$(cat "$TRANSCRIPT" 2>/dev/null)}" || TRANSCRIPT_CONTENT=""
        if [[ "$TRANSCRIPT_CONTENT" != *'playwright-cli'* ]]; then
          block_with_reason "BLOCKED: UI files changed but no playwright-cli verification found in session transcript. Verify UI changes before committing. Changed files: $(echo $UI_FILES | tr '\n' ', ')"
        fi
      fi
    fi
  fi

  # ─── Tracking enforcement (delegation + step verification) ───
  # Hook uses git-common-dir to find tracking markers from worktrees.
  # TRACKING_ROOT resolves to main repo root in both main repo and worktrees.
  # Overridable via env var for testing.
  TRACKING_ROOT="${TRACKING_ROOT:-$(cd "$(git rev-parse --git-common-dir 2>/dev/null || echo .git)/.." && pwd)}"
  TRACKING_DIR="$TRACKING_ROOT/.zskills/tracking"

  # Pipeline association guard: determine if this session belongs to a tracked
  # pipeline and extract its pipeline ID for scoping.
  #
  # Tier 1: .zskills-tracked file in LOCAL repo root (worktree agents).
  #   Written by orchestrator before dispatching — cannot be skipped by agent.
  #
  # Tier 2: ZSKILLS_PIPELINE_ID=<id> in transcript (orchestrators on main).
  #   Orchestrator echoes this early in execution. The transcript is a stable
  #   append-only JSONL file (survives context compaction). Uses LAST match
  #   so sequential /run-plan invocations in the same session work correctly.
  #
  # Neither → unrelated session → skip enforcement → parallel work unblocked.
  LOCAL_ROOT="${LOCAL_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  PIPELINE_ID=""
  TRACKING_SESSION_HAS_PIPELINE=false

  # Tier 1: .zskills-tracked file in LOCAL repo root (worktree agents)
  if [ -f "$LOCAL_ROOT/.zskills-tracked" ]; then
    PIPELINE_ID=$(cat "$LOCAL_ROOT/.zskills-tracked" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$PIPELINE_ID" ]; then
      TRACKING_SESSION_HAS_PIPELINE=true
    fi
  fi

  # Tier 2: ZSKILLS_PIPELINE_ID in transcript (orchestrators on main)
  if ! $TRACKING_SESSION_HAS_PIPELINE && [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    PIPELINE_ID=$(grep -o 'ZSKILLS_PIPELINE_ID=[^[:space:]"]*' "$TRANSCRIPT" 2>/dev/null | tail -1 | cut -d= -f2)
    if [ -n "$PIPELINE_ID" ]; then
      TRACKING_SESSION_HAS_PIPELINE=true
    fi
  fi

  # Skip if tracking dir doesn't exist (backward compatible)
  # OR if this session is not associated with any pipeline
  if [ -d "$TRACKING_DIR" ] && $TRACKING_SESSION_HAS_PIPELINE; then

    # Check if any code files are being committed (skip check for content-only)
    if [ -z "$CODE_FILES" ]; then
      DIFF_OUTPUT=$(git -C "$REPO_ROOT" diff --cached --name-only 2>/dev/null)
      CODE_FILES=""
      while IFS= read -r line; do
        if [[ "$line" =~ \.(js|ts|json|css|html|rs|py|go|rb)$ ]]; then
          CODE_FILES+="$line"$'\n'
        fi
      done <<< "$DIFF_OUTPUT"
    fi

    if [ -n "$CODE_FILES" ]; then

      # Delegation check: requires.* must have matching fulfilled.*
      for req in "$TRACKING_DIR"/requires.*; do
        [ -f "$req" ] || continue
        base=$(basename "$req")
        # Pipeline scoping: if PIPELINE_ID is set, only check markers ending with .$PIPELINE_ID
        if [ -n "$PIPELINE_ID" ] && [[ "$base" != *".${PIPELINE_ID#*.}" ]]; then
          continue
        fi
        fulfilled="${TRACKING_DIR}/${base/requires./fulfilled.}"
        if [ ! -f "$fulfilled" ]; then
          block_with_reason "BLOCKED: Required skill invocation '${base#requires.}' not yet fulfilled. Invoke the required skill via the Skill tool. To clear stale tracking: ! bash scripts/clear-tracking.sh"
        fi
      done

      # Step enforcement: implement needs verify, verify needs report
      for impl in "$TRACKING_DIR"/step.*.implement; do
        [ -f "$impl" ] || continue
        base=$(basename "$impl" .implement)
        if [ -n "$PIPELINE_ID" ] && [[ "$base" != *".${PIPELINE_ID#*.}" ]]; then
          continue
        fi
        verify="${impl/\.implement/.verify}"
        if [ ! -f "$verify" ]; then
          block_with_reason "BLOCKED: ${base#step.} has implementation but no verification. Run verification before committing. To clear: ! bash scripts/clear-tracking.sh"
        fi
      done

      for verif in "$TRACKING_DIR"/step.*.verify; do
        [ -f "$verif" ] || continue
        base=$(basename "$verif" .verify)
        if [ -n "$PIPELINE_ID" ] && [[ "$base" != *".${PIPELINE_ID#*.}" ]]; then
          continue
        fi
        report="${verif/\.verify/.report}"
        if [ ! -f "$report" ]; then
          block_with_reason "BLOCKED: ${base#step.} verified but no report written. Write report before committing. To clear: ! bash scripts/clear-tracking.sh"
        fi
      done
    fi
  fi
fi

# --- main_protected: block git cherry-pick on main ---
if [[ "$INPUT" =~ git[[:space:]]+cherry-pick ]] && is_main_protected && is_on_main; then
  block_with_reason "BLOCKED: main branch is protected (main_protected: true in .claude/zskills-config.json). Cherry-pick to a feature branch instead. To change: edit .claude/zskills-config.json"
fi

# Safety net: transcript-based verification on git cherry-pick
# Cherry-picks replay existing commits and bypass the commit hook above.
if [[ "$INPUT" =~ git[[:space:]]+cherry-pick ]]; then
  TRANSCRIPT=$(extract_transcript)
  if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    FULL_TEST_CHECK="${FULL_TEST_CMD}"
    if [[ "$FULL_TEST_CHECK" == *'{{'* ]]; then
      # Placeholder not replaced -- warn only if project has test infrastructure
      REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
      HAS_TESTS=false
      if [ -f "$REPO_ROOT/package.json" ]; then
        PACKAGE_CONTENT=$(<"$REPO_ROOT/package.json")
        if [[ "$PACKAGE_CONTENT" == *'"test"'* ]]; then
          HAS_TESTS=true
        fi
      fi
      if ! $HAS_TESTS; then
        for f in "$REPO_ROOT"/pytest.ini "$REPO_ROOT"/jest.config.* "$REPO_ROOT"/vitest.config.* "$REPO_ROOT"/.mocharc.* "$REPO_ROOT"/Makefile; do
          if [[ -f "$f" ]]; then
            HAS_TESTS=true
            break
          fi
        done
      fi
      if $HAS_TESTS; then
        block_with_reason "BLOCKED: Test infrastructure detected but FULL_TEST_CMD not configured in block-unsafe-project.sh. Configure it so the pre-commit test check works."
      fi
    else
      TRANSCRIPT_CONTENT=$(cat "$TRANSCRIPT" 2>/dev/null) || TRANSCRIPT_CONTENT=""
      if [[ "$TRANSCRIPT_CONTENT" != *"$FULL_TEST_CHECK"* ]]; then
        block_with_reason "BLOCKED: git cherry-pick but '${FULL_TEST_CHECK}' was not found in the session transcript. Run tests before landing code on main."
      fi
    fi
  fi

  # ─── Tracking enforcement (delegation + step verification) ───
  TRACKING_ROOT="${TRACKING_ROOT:-$(cd "$(git rev-parse --git-common-dir 2>/dev/null || echo .git)/.." && pwd)}"
  TRACKING_DIR="$TRACKING_ROOT/.zskills/tracking"

  # Pipeline association guard (same two-tier logic as commit block)
  LOCAL_ROOT="${LOCAL_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  PIPELINE_ID=""
  TRACKING_SESSION_HAS_PIPELINE=false

  # Tier 1: .zskills-tracked in LOCAL root (worktree agents)
  if [ -f "$LOCAL_ROOT/.zskills-tracked" ]; then
    PIPELINE_ID=$(cat "$LOCAL_ROOT/.zskills-tracked" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$PIPELINE_ID" ]; then
      TRACKING_SESSION_HAS_PIPELINE=true
    fi
  fi

  # Tier 2: ZSKILLS_PIPELINE_ID in transcript (orchestrators on main)
  if ! $TRACKING_SESSION_HAS_PIPELINE && [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    PIPELINE_ID=$(grep -o 'ZSKILLS_PIPELINE_ID=[^[:space:]"]*' "$TRANSCRIPT" 2>/dev/null | tail -1 | cut -d= -f2)
    if [ -n "$PIPELINE_ID" ]; then
      TRACKING_SESSION_HAS_PIPELINE=true
    fi
  fi

  if [ -d "$TRACKING_DIR" ] && $TRACKING_SESSION_HAS_PIPELINE; then

    # Delegation check: requires.* must have matching fulfilled.*
    for req in "$TRACKING_DIR"/requires.*; do
      [ -f "$req" ] || continue
      base=$(basename "$req")
      if [ -n "$PIPELINE_ID" ] && [[ "$base" != *".${PIPELINE_ID#*.}" ]]; then
        continue
      fi
      fulfilled="${TRACKING_DIR}/${base/requires./fulfilled.}"
      if [ ! -f "$fulfilled" ]; then
        block_with_reason "BLOCKED: Required skill invocation '${base#requires.}' not yet fulfilled. Invoke the required skill via the Skill tool. To clear stale tracking: ! bash scripts/clear-tracking.sh"
      fi
    done

    # Step enforcement: implement needs verify, verify needs report
    for impl in "$TRACKING_DIR"/step.*.implement; do
      [ -f "$impl" ] || continue
      base=$(basename "$impl" .implement)
      if [ -n "$PIPELINE_ID" ] && [[ "$base" != *".${PIPELINE_ID#*.}" ]]; then
        continue
      fi
      verify="${impl/\.implement/.verify}"
      if [ ! -f "$verify" ]; then
        block_with_reason "BLOCKED: ${base#step.} has implementation but no verification. Run verification before landing. To clear: ! bash scripts/clear-tracking.sh"
      fi
    done

    for verif in "$TRACKING_DIR"/step.*.verify; do
      [ -f "$verif" ] || continue
      base=$(basename "$verif" .verify)
      if [ -n "$PIPELINE_ID" ] && [[ "$base" != *".${PIPELINE_ID#*.}" ]]; then
        continue
      fi
      report="${verif/\.verify/.report}"
      if [ ! -f "$report" ]; then
        block_with_reason "BLOCKED: ${base#step.} verified but no report written. Write report before landing. To clear: ! bash scripts/clear-tracking.sh"
      fi
    done
  fi
fi

# Safety net: tracking enforcement on git push
# Push is the landing gate for PR mode — same tracking checks as commit/cherry-pick.
if [[ "$INPUT" =~ git[[:space:]]+push([[:space:]]|\") ]]; then
  TRACKING_ROOT="${TRACKING_ROOT:-$(cd "$(git rev-parse --git-common-dir 2>/dev/null || echo .git)/.." && pwd)}"
  TRACKING_DIR="$TRACKING_ROOT/.zskills/tracking"

  # Pipeline association guard (same two-tier logic as commit/cherry-pick blocks)
  # Resolve LOCAL_ROOT: prefer cd target (worktree agents use "cd /tmp/wt && git push")
  # because the hook runs in the main repo CWD, not the agent's cd target.
  CD_TARGET=$(extract_cd_target)
  if [ -n "$CD_TARGET" ]; then
    LOCAL_ROOT="${LOCAL_ROOT:-$CD_TARGET}"
  else
    LOCAL_ROOT="${LOCAL_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  fi
  PIPELINE_ID=""
  TRACKING_SESSION_HAS_PIPELINE=false

  # Tier 1: .zskills-tracked in LOCAL root (worktree agents)
  if [ -f "$LOCAL_ROOT/.zskills-tracked" ]; then
    PIPELINE_ID=$(cat "$LOCAL_ROOT/.zskills-tracked" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$PIPELINE_ID" ]; then
      TRACKING_SESSION_HAS_PIPELINE=true
    fi
  fi

  # Tier 2: ZSKILLS_PIPELINE_ID in transcript (orchestrators on main)
  if ! $TRACKING_SESSION_HAS_PIPELINE; then
    TRANSCRIPT=$(extract_transcript)
    if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
      PIPELINE_ID=$(grep -o 'ZSKILLS_PIPELINE_ID=[^[:space:]"]*' "$TRANSCRIPT" 2>/dev/null | tail -1 | cut -d= -f2)
      if [ -n "$PIPELINE_ID" ]; then
        TRACKING_SESSION_HAS_PIPELINE=true
      fi
    fi
  fi

  if [ -d "$TRACKING_DIR" ] && $TRACKING_SESSION_HAS_PIPELINE; then

    # Check if any code files are in the push (compare local branch to remote tracking)
    # Use -C to run git in the cd target dir (worktree), not main repo CWD
    GIT_ARGS=""
    if [ -n "$CD_TARGET" ]; then
      GIT_ARGS="-C $CD_TARGET"
    fi
    CODE_FILES=""
    PUSH_DIFF=$(git $GIT_ARGS diff --name-only @{u}..HEAD 2>/dev/null)
    if [ -z "$PUSH_DIFF" ]; then
      # Fallback: compare against main (works before first push -u)
      PUSH_DIFF=$(git $GIT_ARGS diff --name-only main..HEAD 2>/dev/null)
    fi
    if [ -n "$PUSH_DIFF" ]; then
      while IFS= read -r line; do
        if [[ "$line" =~ \.(js|jsx|mjs|cjs|ts|tsx|json|css|scss|html|vue|svelte|rs|py|go|rb|java|kt|swift|c|cc|cpp|h|hpp|sh|php)$ ]]; then
          CODE_FILES+="$line"$'\n'
        fi
      done <<< "$PUSH_DIFF"
    fi

    if [ -n "$CODE_FILES" ]; then

      # Delegation check: requires.* must have matching fulfilled.*
      for req in "$TRACKING_DIR"/requires.*; do
        [ -f "$req" ] || continue
        base=$(basename "$req")
        if [ -n "$PIPELINE_ID" ] && [[ "$base" != *".${PIPELINE_ID#*.}" ]]; then
          continue
        fi
        fulfilled="${TRACKING_DIR}/${base/requires./fulfilled.}"
        if [ ! -f "$fulfilled" ]; then
          block_with_reason "BLOCKED: Required skill invocation '${base#requires.}' not yet fulfilled before pushing. To clear stale tracking: ! bash scripts/clear-tracking.sh"
        fi
      done

      # Step enforcement: implement needs verify, verify needs report
      for impl in "$TRACKING_DIR"/step.*.implement; do
        [ -f "$impl" ] || continue
        base=$(basename "$impl" .implement)
        if [ -n "$PIPELINE_ID" ] && [[ "$base" != *".${PIPELINE_ID#*.}" ]]; then
          continue
        fi
        verify="${impl/\.implement/.verify}"
        if [ ! -f "$verify" ]; then
          block_with_reason "BLOCKED: ${base#step.} has implementation but no verification. Run verification before pushing. To clear: ! bash scripts/clear-tracking.sh"
        fi
      done

      for verif in "$TRACKING_DIR"/step.*.verify; do
        [ -f "$verif" ] || continue
        base=$(basename "$verif" .verify)
        if [ -n "$PIPELINE_ID" ] && [[ "$base" != *".${PIPELINE_ID#*.}" ]]; then
          continue
        fi
        report="${verif/\.verify/.report}"
        if [ ! -f "$report" ]; then
          block_with_reason "BLOCKED: ${base#step.} verified but no report written. Write report before pushing. To clear: ! bash scripts/clear-tracking.sh"
        fi
      done
    fi
  fi
fi

# --- main_protected: block git push to main ---
if [[ "$INPUT" =~ git[[:space:]]+push([[:space:]]|\") ]] && is_main_protected; then
  # Check if pushing to main/master (explicit refspec or default branch)
  if is_on_main; then
    # On main branch, default push targets main
    if [[ ! "$INPUT" =~ origin[[:space:]]+[a-zA-Z] ]] || [[ "$INPUT" =~ origin[[:space:]]+(main|master) ]]; then
      block_with_reason "BLOCKED: Cannot push to main (main_protected: true in .claude/zskills-config.json). Push a feature branch instead. To change: edit .claude/zskills-config.json"
    fi
  fi
fi

# Legacy .claude/tracking push enforcement block removed — superseded by
# .zskills/tracking push enforcement at line 377 (with pipeline scoping,
# worktree support, and no staleness bypass).

# No match — allow
exit 0
