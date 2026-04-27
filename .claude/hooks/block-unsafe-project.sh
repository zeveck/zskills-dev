#!/bin/bash
# Block unsafe commands — PROJECT-SPECIFIC enforcement layer.
# No external dependencies — bash and git only.
#
# This file is a template. Most behavior is now driven at runtime from
# .claude/zskills-config.json (unit_cmd, full_cmd, ui.file_patterns,
# main_protected, etc.). Remove sections that don't apply to your project.
#
# Register BOTH this file and block-unsafe-generic.sh in .claude/settings.json
# on the PreToolUse event, Bash matcher. The generic layer runs first.

INPUT=$(cat)

# Only filter Bash commands
if [[ "$INPUT" != *'"tool_name":"Bash"'* ]] && [[ "$INPUT" != *'"tool_name": "Bash"'* ]]; then
  exit 0
fi

# ──────────────────────────────────────────────────────────────
# Command extraction + data-region redaction
# ──────────────────────────────────────────────────────────────
# Lifted from block-unsafe-generic.sh so pattern rules below scan the
# actual shell command with commit-message / PR-body / heredoc prose
# stripped out. Without this, rules fire on commit messages that merely
# DISCUSS a pattern (e.g., `git commit -m "don't git push before tests"`
# would trip the push-tracking rule, or a commit message mentioning
# `.zskills/tracking` would trip the recursive-delete rule).
#
# Only the pattern-scanning rules use $COMMAND. Structured-field
# extraction (transcript_path, etc.) continues to read raw $INPUT.

# Extract the command field from tool_input JSON.
COMMAND=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | sed 's/\\"/"/g')
# Fallback: if extraction fails (malformed JSON), scan raw INPUT so the
# hook remains defensive — no false-allows.
[ -z "$COMMAND" ] && COMMAND="$INPUT"

# Pass 1 — heredoc bodies. Redact `<<[-]?['"]?DELIM['"]?\n BODY \nDELIM(\n|$)`
# with a sentinel. :h / t h loop handles sequential heredocs with different
# delimiters. GNU sed -E backrefs pin the closing delimiter to the opener.
COMMAND=$(printf '%s' "$COMMAND" | sed -E \
  -e ':h' \
  -e 's/<<-?[[:space:]]*"([A-Za-z_][A-Za-z0-9_]*)"\\n.*\\n\1(\\n|$)/HEREDOC_REDACTED\2/' \
  -e 's/<<-?[[:space:]]*'\''([A-Za-z_][A-Za-z0-9_]*)'\''\\n.*\\n\1(\\n|$)/HEREDOC_REDACTED\2/' \
  -e 's/<<-?[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)\\n.*\\n\1(\\n|$)/HEREDOC_REDACTED\2/' \
  -e 't h')

# Pass 2 — flag-scoped quoted arg values.
# - `git commit`                       : -m, --message (incl. -am/-Sm)
# - `gh pr|issue create|comment`       : --body, -b, --title, -t
# Intermediate args tolerated via [^|;&]* so chained ops after the
# arg stay visible. Replacement drops the quotes (bare `REDACTED`) so
# the :m / t m loop terminates on re-run.
COMMAND=$(printf '%s' "$COMMAND" | sed -E \
  -e ':m' \
  -e 's/(git[[:space:]]+commit[[:space:]]([^|;&]*[[:space:]])?(-[a-zA-Z]*m|--message)[[:space:]]+)("[^"]*"|'\''[^'\'']*'\'')/\1REDACTED/g' \
  -e 's/(gh[[:space:]]+(pr|issue)[[:space:]]+(create|comment)[[:space:]]([^|;&]*[[:space:]])?(--body|-b|--title|-t)[[:space:]]+)("[^"]*"|'\''[^'\'']*'\'')/\1REDACTED/g' \
  -e 't m')

# Block patterns -- each with a reason
block_with_reason() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$1"
  exit 0
}

# ─── Tracking enforcement helpers ───
# Shared between the commit / cherry-pick / push reader blocks. Each helper
# takes a marker path + the action-verb context ("committing", "landing",
# "pushing") and calls block_with_reason on violation. TRACKING_DIR is read
# from the caller's scope (the calling block already sets it).
#
# Usage:
#   enforce_requires_marker "$req_path" "committing"
#   enforce_step_implement_marker "$impl_path" "committing"
#   enforce_step_verify_marker "$verify_path" "committing"

enforce_requires_marker() {
  local req="$1"
  local action="$2"
  local base
  base=$(basename "$req")
  local fulfilled="${TRACKING_DIR}/${base/requires./fulfilled.}"
  # Also check inside the same subdir as the requires marker, if it's in one.
  local req_dir
  req_dir=$(dirname "$req")
  local subdir_fulfilled="${req_dir}/${base/requires./fulfilled.}"
  if [ ! -f "$fulfilled" ] && [ ! -f "$subdir_fulfilled" ]; then
    if [ "$action" = "pushing" ]; then
      block_with_reason "BLOCKED: Required skill invocation '${base#requires.}' not yet fulfilled before pushing. To clear stale tracking: ! bash scripts/clear-tracking.sh"
    else
      block_with_reason "BLOCKED: Required skill invocation '${base#requires.}' not yet fulfilled. Invoke the required skill via the Skill tool. To clear stale tracking: ! bash scripts/clear-tracking.sh"
    fi
  fi
}

enforce_step_implement_marker() {
  local impl="$1"
  local action="$2"
  local base
  base=$(basename "$impl" .implement)
  local verify="${impl/\.implement/.verify}"
  if [ ! -f "$verify" ]; then
    block_with_reason "BLOCKED: ${base#step.} has implementation but no verification. Run verification before ${action}. To clear: ! bash scripts/clear-tracking.sh"
  fi
}

enforce_step_verify_marker() {
  local verif="$1"
  local action="$2"
  local base
  base=$(basename "$verif" .verify)
  local report="${verif/\.verify/.report}"
  if [ ! -f "$report" ]; then
    block_with_reason "BLOCKED: ${base#step.} verified but no report written. Write report before ${action}. To clear: ! bash scripts/clear-tracking.sh"
  fi
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
  # Answer "is the agent operating on main?" — must reflect the WORKTREE the
  # agent is in, not the hook's ambient cwd. Hooks run in a separate process
  # rooted at $CLAUDE_PROJECT_DIR (the main repo); when the agent runs
  # `cd /tmp/wt && git commit ...` from a feature-branch worktree, the hook's
  # own `git rev-parse` would report "main" and wrongly block the commit.
  # Precedence: $REPO_ROOT env (test override) → cd target extracted from the
  # command (worktree-cd case) → ambient cwd (main-repo invocation).
  local branch
  local repo_root="${REPO_ROOT:-}"
  if [ -z "$repo_root" ]; then
    local cd_target
    cd_target=$(extract_cd_target)
    if [ -n "$cd_target" ]; then
      repo_root="$cd_target"
    else
      repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    fi
  fi
  branch=$(git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null)
  [[ "$branch" == "main" || "$branch" == "master" ]]
}

# ─── Tracking file protection ───
# Block recursive deletion of tracking directory.
# The `-r` / `-R` / `--recursive` flag must be a standalone token (preceded
# by whitespace, not mid-word), AND both the flag and `.zskills/tracking`
# must live in the same shell command (no ; & | crossing). The earlier
# unanchored pattern matched ANY `-word-with-r` substring in the rm's
# buffer (incl. `-tracked` inside `.zskills-tracked` pathnames and unrelated
# long flags like `--worktree` / `--branch` later in the same multi-line
# bash blob). Past failure: `rm -f X; bash ... --worktree ... .zskills/tracking/...`
# false-positived because `--worktree`'s `-r-letters` satisfied the flag
# slot mid-regex.
if [[ "$COMMAND" =~ rm[[:space:]]+([^\;\&\|]*[[:space:]])?(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)([[:space:]]|$)[^\;\&\|]*\.zskills/tracking ]]; then
  block_with_reason "BLOCKED: Cannot recursively delete tracking directory. To clear tracking state: ! bash scripts/clear-tracking.sh"
fi

# Block agent execution of clear-tracking script (reading is OK).
# Matches bash|sh only at a command-verb boundary:
#   - start of the JSON command field (`"command":"`)
#   - command separator (`;`, `&`, `|`, `(`, backtick)
#   - start of input
# Bare whitespace is NOT a boundary (that's what caused echo-string false
# positives: `echo "Run: bash scripts/clear-tracking.sh"` has a space before
# `bash` but the `bash` there is data, not a command verb).
_CT_EXEC_CMD='(^|[;&|(`]|"command":")[[:space:]]*(bash|sh)[[:space:]][^;&|"]*clear-tracking'
_CT_EXEC_DIR='(^|[;&|(`]|"command":")[[:space:]]*\./[^[:space:]"]*clear-tracking'
if [[ "$COMMAND" =~ $_CT_EXEC_CMD ]] || [[ "$COMMAND" =~ $_CT_EXEC_DIR ]]; then
  block_with_reason "BLOCKED: Only the user can run the clear-tracking script. Run: ! bash scripts/clear-tracking.sh"
fi

# ─── Config file ───
# Config lives at .claude/zskills-config.json. It is user-managed; no custom
# hook protects it. Writes to .claude/ may or may not prompt depending on the
# user's permission mode — no file-specific rule exists. Agents that own the
# config (e.g. /update-zskills) may write it directly.

# ─── CONFIGURE: remove this section if you don't use session logging ───
# git add .claude/logs/ (sweeps in all sessions' logs -- stage specific files)
if [[ "$COMMAND" =~ git[[:space:]]+add[[:space:]]+\.claude/logs/?([[:space:]]|$) ]]; then
  block_with_reason "BLOCKED: git add .claude/logs/ sweeps in ALL sessions' logs. Stage your session's logs by name: git add .claude/logs/*-<session-id>*.md"
fi

# ─── CONFIGURE: set your test command patterns ────────────────────────
# Piping test output (loses failures, forces re-runs -- capture to file instead)
#
# ─── Runtime config read (eliminates install-time drift) ───
# Config location: .claude/zskills-config.json in the checked-out tree.
# --show-toplevel matches the existing is_main_protected() pattern at
# line 146; in a worktree, this returns the worktree root, which is
# correct — the config is git-tracked, so each worktree reads its own
# branch-current version.
_ZSK_REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
_ZSK_CFG="$_ZSK_REPO_ROOT/.claude/zskills-config.json"
UNIT_TEST_CMD=""
FULL_TEST_CMD=""
UI_FILE_PATTERNS=""
if [ -f "$_ZSK_CFG" ]; then
  _ZSK_CFG_BODY=$(cat "$_ZSK_CFG" 2>/dev/null) || _ZSK_CFG_BODY=""
  if [[ "$_ZSK_CFG_BODY" =~ \"unit_cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    UNIT_TEST_CMD="${BASH_REMATCH[1]}"
  fi
  if [[ "$_ZSK_CFG_BODY" =~ \"full_cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    FULL_TEST_CMD="${BASH_REMATCH[1]}"
  fi
  # ui.file_patterns: scope via enclosing "ui" object to disambiguate
  # from testing.file_patterns (array, doesn't match the string regex
  # anyway, but prefix scoping is defensive against future schema change).
  if [[ "$_ZSK_CFG_BODY" =~ \"ui\"[[:space:]]*:[[:space:]]*\{[^}]*\"file_patterns\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    UI_FILE_PATTERNS="${BASH_REMATCH[1]}"
  fi
  unset _ZSK_CFG_BODY
fi
unset _ZSK_REPO_ROOT _ZSK_CFG

# Escape every bash-regex metacharacter that might appear in a config
# test-command string (parens, brackets, pipe, asterisk, plus, etc.).
# Then re-space spaces to [[:space:]]+ so "bash  tests/run-all.sh"
# (multiple spaces) still matches.
#
# Bash parameter-expansion quoting note: inside ${var//pat/replace}, `pat`
# is a glob pattern. `?` matches any single char, `[...]` is a class,
# `}` closes the expansion early. We use `[?]` (literal-? class) for the
# `?` rule and `\\\}` (escaped closer) for the `}` rule to work around these.
_zsk_regex_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//./\\.}"
  s="${s//\(/\\(}"
  s="${s//\)/\\)}"
  s="${s//\[/\\[}"
  s="${s//\]/\\]}"
  s="${s//|/\\|}"
  s="${s//\*/\\*}"
  s="${s//+/\\+}"
  s="${s//[?]/\\?}"
  s="${s//\$/\\\$}"
  s="${s//^/\\^}"
  s="${s//\{/\\{}"
  s="${s//\}/\\\}}"
  s="${s// /[[:space:]]+}"
  printf '%s' "$s"
}

# Guard: without both vars set, TEST_PIPE_PATTERN="(|)" matches empty
# string and blocks every piped command. Skip the pipe check entirely
# if both are empty (config missing or test fields unset).
if [ -n "$UNIT_TEST_CMD" ] || [ -n "$FULL_TEST_CMD" ]; then
  ESCAPED_UNIT=""
  ESCAPED_FULL=""
  [ -n "$UNIT_TEST_CMD" ] && ESCAPED_UNIT="$(_zsk_regex_escape "$UNIT_TEST_CMD")"
  [ -n "$FULL_TEST_CMD" ] && ESCAPED_FULL="$(_zsk_regex_escape "$FULL_TEST_CMD")"
  # Only alternate non-empty vars to avoid "(|cmd)" degenerate case.
  if [ -n "$ESCAPED_UNIT" ] && [ -n "$ESCAPED_FULL" ]; then
    TEST_PIPE_PATTERN="(${ESCAPED_UNIT}|${ESCAPED_FULL})"
  elif [ -n "$ESCAPED_UNIT" ]; then
    TEST_PIPE_PATTERN="${ESCAPED_UNIT}"
  else
    TEST_PIPE_PATTERN="${ESCAPED_FULL}"
  fi

  # Split on &&, ||, ; so the pipe check only fires when the pipe is in
  # the SAME segment as the test command (otherwise an unrelated `ls | head`
  # earlier in the command falsely trips the block).
  _TEST_SEP=$'\x01'
  _TEST_NORM="${INPUT//&&/$_TEST_SEP}"
  _TEST_NORM="${_TEST_NORM//||/$_TEST_SEP}"
  _TEST_NORM="${_TEST_NORM//;/$_TEST_SEP}"
  IFS=$'\x01' read -ra _TEST_SEGMENTS <<< "$_TEST_NORM"
  for _seg in "${_TEST_SEGMENTS[@]}"; do
    if [[ "$_seg" =~ $TEST_PIPE_PATTERN ]] && [[ "$_seg" == *'|'* ]]; then
      block_with_reason "Don't pipe test output -- it loses failure details. Instead: TEST_OUT=\"/tmp/zskills-tests/\$(basename \"\$(pwd)\")\"; mkdir -p \"\$TEST_OUT\"; ${FULL_TEST_CMD:-npm run test:all} > \"\$TEST_OUT/.test-results.txt\" 2>&1 then read \"\$TEST_OUT/.test-results.txt\" to inspect failures."
    fi
  done
  unset _TEST_SEP _TEST_NORM _TEST_SEGMENTS _seg
fi

# --- main_protected: block git commit on main ---
if [[ "$COMMAND" =~ git[[:space:]]+commit ]] && is_main_protected && is_on_main; then
  block_with_reason "BLOCKED: main branch is protected (main_protected: true in .claude/zskills-config.json). Create a feature branch or use PR mode. To change: edit .claude/zskills-config.json"
fi

# ─── CONFIGURE: set your full test command ────────────────────────────
# Safety net: transcript-based verification on git commit
# Ensures tests were run before committing code files.
if [[ "$COMMAND" =~ git[[:space:]]+commit ]]; then
  TRANSCRIPT=$(extract_transcript)
  if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    FULL_TEST_CHECK="${FULL_TEST_CMD}"
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

    # ─── CONFIGURE: set your UI source paths, or remove this section if not applicable ───
    # Check if UI files changed but no playwright-cli verification.
    # UI_FILE_PATTERNS is initialized at the top from .claude/zskills-config.json (ui.file_patterns).
    if [ -n "$UI_FILE_PATTERNS" ]; then
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

      PIPELINE_SUBDIR="$TRACKING_DIR/$PIPELINE_ID"

      # Delegation check: requires.* must have matching fulfilled.*
      # Subdir-only reader (Phase 6: dual-read fallback removed; all writers migrated).
      if [ -n "$PIPELINE_ID" ] && [ -d "$PIPELINE_SUBDIR" ]; then
        for req in "$PIPELINE_SUBDIR"/requires.*; do
          [ -e "$req" ] || continue
          enforce_requires_marker "$req" "committing"
        done
      fi

      # Step enforcement: implement needs verify
      # Subdir-only reader (Phase 6: dual-read fallback removed; all writers migrated).
      if [ -n "$PIPELINE_ID" ] && [ -d "$PIPELINE_SUBDIR" ]; then
        for impl in "$PIPELINE_SUBDIR"/step.*.implement; do
          [ -e "$impl" ] || continue
          enforce_step_implement_marker "$impl" "committing"
        done
      fi

      # Step enforcement: verify needs report
      # Subdir-only reader (Phase 6: dual-read fallback removed; all writers migrated).
      if [ -n "$PIPELINE_ID" ] && [ -d "$PIPELINE_SUBDIR" ]; then
        for verif in "$PIPELINE_SUBDIR"/step.*.verify; do
          [ -e "$verif" ] || continue
          enforce_step_verify_marker "$verif" "committing"
        done
      fi
    fi
  fi
fi

# --- main_protected: block git cherry-pick on main ---
if [[ "$COMMAND" =~ git[[:space:]]+cherry-pick ]] && is_main_protected && is_on_main; then
  block_with_reason "BLOCKED: main branch is protected (main_protected: true in .claude/zskills-config.json). Cherry-pick to a feature branch instead. To change: edit .claude/zskills-config.json"
fi

# Safety net: transcript-based verification on git cherry-pick
# Cherry-picks replay existing commits and bypass the commit hook above.
if [[ "$COMMAND" =~ git[[:space:]]+cherry-pick ]]; then
  TRANSCRIPT=$(extract_transcript)
  if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    FULL_TEST_CHECK="${FULL_TEST_CMD}"
    TRANSCRIPT_CONTENT=$(cat "$TRANSCRIPT" 2>/dev/null) || TRANSCRIPT_CONTENT=""
    if [[ "$TRANSCRIPT_CONTENT" != *"$FULL_TEST_CHECK"* ]]; then
      block_with_reason "BLOCKED: git cherry-pick but '${FULL_TEST_CHECK}' was not found in the session transcript. Run tests before landing code on main."
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

    PIPELINE_SUBDIR="$TRACKING_DIR/$PIPELINE_ID"

    # Delegation check: requires.* must have matching fulfilled.*
    # Subdir-only reader (Phase 6: dual-read fallback removed; all writers migrated).
    if [ -n "$PIPELINE_ID" ] && [ -d "$PIPELINE_SUBDIR" ]; then
      for req in "$PIPELINE_SUBDIR"/requires.*; do
        [ -e "$req" ] || continue
        enforce_requires_marker "$req" "landing"
      done
    fi

    # Step enforcement: implement needs verify
    # Subdir-only reader (Phase 6: dual-read fallback removed; all writers migrated).
    if [ -n "$PIPELINE_ID" ] && [ -d "$PIPELINE_SUBDIR" ]; then
      for impl in "$PIPELINE_SUBDIR"/step.*.implement; do
        [ -e "$impl" ] || continue
        enforce_step_implement_marker "$impl" "landing"
      done
    fi

    # Step enforcement: verify needs report
    # Subdir-only reader (Phase 6: dual-read fallback removed; all writers migrated).
    if [ -n "$PIPELINE_ID" ] && [ -d "$PIPELINE_SUBDIR" ]; then
      for verif in "$PIPELINE_SUBDIR"/step.*.verify; do
        [ -e "$verif" ] || continue
        enforce_step_verify_marker "$verif" "landing"
      done
    fi
  fi
fi

# Safety net: tracking enforcement on git push
# Push is the landing gate for PR mode — same tracking checks as commit/cherry-pick.
if [[ "$COMMAND" =~ git[[:space:]]+push([[:space:]]|\") ]]; then
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

      PIPELINE_SUBDIR="$TRACKING_DIR/$PIPELINE_ID"

      # Delegation check: requires.* must have matching fulfilled.*
      # Subdir-only reader (Phase 6: dual-read fallback removed; all writers migrated).
      if [ -n "$PIPELINE_ID" ] && [ -d "$PIPELINE_SUBDIR" ]; then
        for req in "$PIPELINE_SUBDIR"/requires.*; do
          [ -e "$req" ] || continue
          enforce_requires_marker "$req" "pushing"
        done
      fi

      # Step enforcement: implement needs verify
      # Subdir-only reader (Phase 6: dual-read fallback removed; all writers migrated).
      if [ -n "$PIPELINE_ID" ] && [ -d "$PIPELINE_SUBDIR" ]; then
        for impl in "$PIPELINE_SUBDIR"/step.*.implement; do
          [ -e "$impl" ] || continue
          enforce_step_implement_marker "$impl" "pushing"
        done
      fi

      # Step enforcement: verify needs report
      # Subdir-only reader (Phase 6: dual-read fallback removed; all writers migrated).
      if [ -n "$PIPELINE_ID" ] && [ -d "$PIPELINE_SUBDIR" ]; then
        for verif in "$PIPELINE_SUBDIR"/step.*.verify; do
          [ -e "$verif" ] || continue
          enforce_step_verify_marker "$verif" "pushing"
        done
      fi
    fi
  fi
fi

# --- main_protected: block git push to main ---
# Trade-off: this rule trusts variable-bearing push targets (e.g.,
# origin "$BRANCH"). If a skill or agent sets a push-target variable to
# "main" and pushes, this rule allows it. Acceptable because
# (1) skills derive their branch names from config + slug with default
# "feat/" prefix, so reaching branch="main" requires a buggy skill or
# adversarial description; (2) a compromised agent that controls the
# bash has easier paths (eval, concatenation, obfuscation) the hook
# cannot defend against anyway; (3) the strict alternative (block all
# variable-bearing push-target forms) produces false-positives on
# legitimate worktree-scoped pushes without closing a realistic attack
# vector.
if [[ "$COMMAND" =~ git[[:space:]]+push([[:space:]]|\") ]] && is_main_protected; then
  # Scope rules (a) and (b) to JUST the `git push` command segment, not the
  # whole $COMMAND buffer. Without this, multi-statement commands like
  # `git fetch origin main && git push -u origin feat/foo` false-positive
  # because "origin main" appears in the fetch portion. Mirrors the bounded
  # extraction in block-unsafe-generic.sh:266-280.
  PUSH_CMD="$COMMAND"
  PUSH_CMD="${PUSH_CMD##*git push}"
  PUSH_ARGS=""
  for word in $PUSH_CMD; do
    case "$word" in
      "&&"*|";"*|"|"*) break ;;  # stop at command chaining
      -*) continue ;;            # skip flags (-u, --force, etc.)
      *) PUSH_ARGS="$PUSH_ARGS $word" ;;
    esac
  done
  # (a) Explicit origin main/master (optionally prefixed with + for
  # force-push or : for delete-refspec):
  if [[ "$PUSH_ARGS" =~ origin[[:space:]]+[+:]?(main|master)([[:space:]]|$|\") ]]; then
    block_with_reason "BLOCKED: Cannot push to main (main_protected: true in .claude/zskills-config.json). Push a feature branch instead. To change: edit .claude/zskills-config.json"
  fi
  # (b) HEAD:main or HEAD:master refspec:
  if [[ "$PUSH_ARGS" =~ HEAD:(main|master)([[:space:]]|$|\") ]]; then
    block_with_reason "BLOCKED: Cannot push to main (main_protected: true in .claude/zskills-config.json). Push a feature branch instead. To change: edit .claude/zskills-config.json"
  fi
  # (c) Naked push (no origin arg) while on main — defaults to pushing
  # the current branch, which is main. Tested against full $COMMAND
  # because seeing `origin` ANYWHERE means a non-naked push is present.
  if ! [[ "$COMMAND" =~ origin[[:space:]] ]] && is_on_main; then
    block_with_reason "BLOCKED: Cannot push to main (main_protected: true in .claude/zskills-config.json). Push a feature branch instead. To change: edit .claude/zskills-config.json"
  fi
fi

# Legacy .claude/tracking push enforcement block removed — superseded by
# .zskills/tracking push enforcement at line 377 (with pipeline scoping,
# worktree support, and no staleness bypass).

# No match — allow
exit 0
