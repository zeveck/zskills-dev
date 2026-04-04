#!/bin/bash
# Block unsafe commands — PROJECT-SPECIFIC enforcement layer.
# No external dependencies — bash and git only.
#
# This file is a template. Replace {{PLACEHOLDER}} values and remove
# sections that don't apply to your project.
#
# Register BOTH this file and block-unsafe-generic.sh in .claude/settings.json
# on the PreToolUse event, Bash matcher. The generic layer runs first.

INPUT=$(</dev/stdin)

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
if [[ "$UNIT_TEST_CMD" == '{{UNIT_TEST_CMD}}' ]] || [[ "$FULL_TEST_CMD" == '{{FULL_TEST_CMD}}' ]]; then
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

# ─── CONFIGURE: set your full test command ────────────────────────────
# Safety net: transcript-based verification on git commit
# Ensures tests were run before committing code files.
if [[ "$INPUT" =~ git[[:space:]]+commit ]]; then
  TRANSCRIPT=$(extract_transcript)
  if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    FULL_TEST_CHECK="${FULL_TEST_CMD}"
    if [[ "$FULL_TEST_CHECK" == '{{FULL_TEST_CMD}}' ]]; then
      # Placeholder not replaced -- warn only if project has test infrastructure
      REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
      HAS_TESTS=false
      if [ -f "$REPO_ROOT/package.json" ]; then
        PACKAGE_CONTENT=$(<"$REPO_ROOT/package.json")
        if [[ "$PACKAGE_CONTENT" == *'"test"'* ]]; then
          HAS_TESTS=true
        fi
      fi
      if ! $HAS_TESTS; then
        for f in "$REPO_ROOT"/pytest.ini "$REPO_ROOT"/jest.config.* "$REPO_ROOT"/.mocharc.* "$REPO_ROOT"/Makefile; do
          if [[ -f "$f" ]]; then
            HAS_TESTS=true
            break
          fi
        done
      fi
      if $HAS_TESTS; then
        echo "WARNING: Test infrastructure detected but FULL_TEST_CMD not configured in block-unsafe-project.sh. Configure it so the pre-commit test check works." >&2
      fi
    else
      # Check if full test command was run in this session
      TRANSCRIPT_CONTENT=$(<"$TRANSCRIPT" 2>/dev/null) || TRANSCRIPT_CONTENT=""
      if [[ "$TRANSCRIPT_CONTENT" != *"$FULL_TEST_CHECK"* ]]; then
        # Check if any code files are being committed (skip check for content-only)
        DIFF_OUTPUT=$(git diff --cached --name-only 2>/dev/null)
        CODE_FILES=""
        while IFS= read -r line; do
          if [[ "$line" =~ \.(js|ts|css|html|rs|py|go|rb)$ ]]; then
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
        TRANSCRIPT_CONTENT="${TRANSCRIPT_CONTENT:-$(<"$TRANSCRIPT" 2>/dev/null)}" || TRANSCRIPT_CONTENT=""
        if [[ "$TRANSCRIPT_CONTENT" != *'playwright-cli'* ]]; then
          block_with_reason "BLOCKED: UI files changed but no playwright-cli verification found in session transcript. Verify UI changes before committing. Changed files: $(echo $UI_FILES | tr '\n' ', ')"
        fi
      fi
    fi
  fi
fi

# Safety net: transcript-based verification on git cherry-pick
# Cherry-picks replay existing commits and bypass the commit hook above.
if [[ "$INPUT" =~ git[[:space:]]+cherry-pick ]]; then
  TRANSCRIPT=$(extract_transcript)
  if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    FULL_TEST_CHECK="${FULL_TEST_CMD}"
    if [[ "$FULL_TEST_CHECK" == '{{FULL_TEST_CMD}}' ]]; then
      # Placeholder not replaced -- warn only if project has test infrastructure
      REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
      HAS_TESTS=false
      if [ -f "$REPO_ROOT/package.json" ]; then
        PACKAGE_CONTENT=$(<"$REPO_ROOT/package.json")
        if [[ "$PACKAGE_CONTENT" == *'"test"'* ]]; then
          HAS_TESTS=true
        fi
      fi
      if ! $HAS_TESTS; then
        for f in "$REPO_ROOT"/pytest.ini "$REPO_ROOT"/jest.config.* "$REPO_ROOT"/.mocharc.* "$REPO_ROOT"/Makefile; do
          if [[ -f "$f" ]]; then
            HAS_TESTS=true
            break
          fi
        done
      fi
      if $HAS_TESTS; then
        echo "WARNING: Test infrastructure detected but FULL_TEST_CMD not configured in block-unsafe-project.sh. Configure it so the pre-commit test check works." >&2
      fi
    else
      TRANSCRIPT_CONTENT=$(<"$TRANSCRIPT" 2>/dev/null) || TRANSCRIPT_CONTENT=""
      if [[ "$TRANSCRIPT_CONTENT" != *"$FULL_TEST_CHECK"* ]]; then
        block_with_reason "BLOCKED: git cherry-pick but '${FULL_TEST_CHECK}' was not found in the session transcript. Run tests before landing code on main."
      fi
    fi
  fi
fi

# No match — allow
exit 0
