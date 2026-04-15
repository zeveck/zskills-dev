#!/bin/bash
# Block Agent (subagent) dispatches that use a model below agents.min_model.
# Registered under the Agent PreToolUse matcher in .claude/settings.json.
#
# Ordinal: haiku=1, sonnet=2, opus=3, unknown=0 (always pass — future model families)
#
# Model field lookup order:
#   1. tool_input.model (present when Agent tool explicitly sets a model)
#   2. .claude/agents/<subagent_type>.md YAML frontmatter model: field
#   3. Not found → ordinal=0 (unknown, always passes)
#
# This script enforces the hard floor. Skill-side reminders (at each Agent
# dispatch site in run-plan, fix-issues, do) cover the residual case where
# neither tool input nor agent definition specifies a model (subagent inherits
# from parent session, which is typically Opus or Sonnet).

INPUT=$(cat)

# Only filter Agent tool calls
if [[ "$INPUT" != *'"tool_name":"Agent"'* ]] && [[ "$INPUT" != *'"tool_name": "Agent"'* ]]; then
  exit 0
fi

# Read agents.min_model from config
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
CONFIG_FILE="$REPO_ROOT/.claude/zskills-config.json"

MIN_MODEL=""
if [ -f "$CONFIG_FILE" ]; then
  # Extract agents.min_model — handles both compact and spaced JSON
  MIN_MODEL=$(grep -o '"min_model"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" 2>/dev/null \
    | head -1 | sed 's/.*"min_model"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
fi

# If min_model not configured, pass through — no enforcement
if [ -z "$MIN_MODEL" ]; then
  exit 0
fi

# Sentinel resolution: "auto" / "inherit" → match the session's current model.
# The PreToolUse hook's stdin JSON typically includes "transcript_path" pointing
# at the session JSONL; each assistant message record there carries a "model"
# field. We take the most recent, which is the current session model.
if [[ "$MIN_MODEL" == "auto" || "$MIN_MODEL" == "inherit" ]]; then
  TRANSCRIPT_PATH=""
  if [[ "$INPUT" =~ \"transcript_path\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    TRANSCRIPT_PATH="${BASH_REMATCH[1]}"
  fi
  RESOLVED=""
  if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    # Walk model entries; filter to ONLY known Claude families (haiku/sonnet/
    # opus); take the most recent. This rejects real-transcript artifacts
    # like `"model":"<synthetic>"` that appear in Claude Code transcripts and
    # would otherwise map to ordinal=0 (unknown), silently disabling the
    # floor for any `auto`-configured project.
    RESOLVED=$(grep -o '"model"[[:space:]]*:[[:space:]]*"[^"]*"' "$TRANSCRIPT_PATH" \
      | sed 's/.*"model"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' \
      | grep -Ei '(haiku|sonnet|opus)' \
      | tail -1)
  fi
  if [ -n "$RESOLVED" ]; then
    MIN_MODEL="$RESOLVED"
  else
    # Resolution failed (transcript missing, unreadable, no model field). Fall
    # back to "sonnet" as a conservative floor: still blocks Haiku (per the
    # "never Haiku" rule), allows sonnet+opus. Print a diagnostic to stderr so
    # the failure is visible — not silent.
    echo "block-agents.sh: could not resolve 'auto' from transcript (${TRANSCRIPT_PATH:-<missing>}); falling back to sonnet floor" >&2
    MIN_MODEL="claude-sonnet-4-6"
  fi
fi

# Convert model string to ordinal
# Ordinal: haiku=1, sonnet=2, opus=3, unknown=0 (always allow)
model_ordinal() {
  local model="$1"
  # Normalize: lowercase, extract family name
  local lower
  lower=$(echo "$model" | tr '[:upper:]' '[:lower:]')
  if [[ "$lower" == *"haiku"* ]]; then
    echo 1
  elif [[ "$lower" == *"sonnet"* ]]; then
    echo 2
  elif [[ "$lower" == *"opus"* ]]; then
    echo 3
  else
    echo 0  # Unknown family — always allow (pass-through for new Claude models)
  fi
}

MIN_ORDINAL=$(model_ordinal "$MIN_MODEL")

# Step 1: Try to extract model from tool_input JSON
# The Agent tool input may include an optional "model" field
DISPATCH_MODEL=""
if [[ "$INPUT" =~ \"tool_input\"[[:space:]]*:\{[^}]*\"model\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
  DISPATCH_MODEL="${BASH_REMATCH[1]}"
fi
# Also try without the tool_input wrapper (simpler JSON structures)
if [ -z "$DISPATCH_MODEL" ]; then
  if [[ "$INPUT" =~ \"model\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    DISPATCH_MODEL="${BASH_REMATCH[1]}"
  fi
fi

# Step 2: If model not in tool_input, try reading agent definition frontmatter
if [ -z "$DISPATCH_MODEL" ]; then
  # Extract subagent_type from tool_input (e.g., "subagent_type": "general-purpose")
  SUBAGENT_TYPE=""
  if [[ "$INPUT" =~ \"subagent_type\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    SUBAGENT_TYPE="${BASH_REMATCH[1]}"
  fi

  if [ -n "$SUBAGENT_TYPE" ]; then
    AGENT_DEF="$REPO_ROOT/.claude/agents/${SUBAGENT_TYPE}.md"
    if [ -f "$AGENT_DEF" ]; then
      # Parse YAML frontmatter (between --- delimiters) for model: field
      IN_FRONTMATTER=false
      while IFS= read -r line; do
        if [ "$line" = "---" ]; then
          if $IN_FRONTMATTER; then
            break  # End of frontmatter
          else
            IN_FRONTMATTER=true
            continue
          fi
        fi
        if $IN_FRONTMATTER && [[ "$line" =~ ^model:[[:space:]]*(.+)$ ]]; then
          DISPATCH_MODEL="${BASH_REMATCH[1]}"
          # Strip surrounding quotes if present
          DISPATCH_MODEL="${DISPATCH_MODEL#\"}"
          DISPATCH_MODEL="${DISPATCH_MODEL%\"}"
          DISPATCH_MODEL=$(echo "$DISPATCH_MODEL" | tr -d '[:space:]')
          break
        fi
      done < "$AGENT_DEF"
    fi
  fi
fi

# Step 3: Apply ordinal check
# If DISPATCH_MODEL is empty, ordinal=0 (unknown) → always pass
if [ -z "$DISPATCH_MODEL" ]; then
  exit 0
fi

DISPATCH_ORDINAL=$(model_ordinal "$DISPATCH_MODEL")

# Ordinal 0 (unknown family) always passes — future Claude model families
if [ "$DISPATCH_ORDINAL" -eq 0 ]; then
  exit 0
fi

# Block if dispatch model is below the configured minimum
if [ "$DISPATCH_ORDINAL" -lt "$MIN_ORDINAL" ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"agents.min_model requires %s or higher (ordinal %d); got %s (ordinal %d). Update your Agent dispatch to use a higher model."}}\n' \
    "$MIN_MODEL" "$MIN_ORDINAL" "$DISPATCH_MODEL" "$DISPATCH_ORDINAL"
  exit 0
fi

# Model meets or exceeds minimum — allow
exit 0
