#!/bin/bash
# zskills-hook-version: 2026.06.2
# Block Agent (subagent) dispatches that use a model below agents.min_model.
# Registered under the Agent PreToolUse matcher in .claude/settings.json.
#
# CONFIG-CASCADE RAISE-ONLY FLOOR (CASCADE v2, ENFORCEMENT_V2 Phase 4 —
# supersedes the INSTALL_REDESIGN Phase 5 PROJECT-ONLY carve-out): this hook
# now reads agents.min_model from BOTH tiers — the PROJECT config and the
# user ~/.claude/zskills-config.json — and merges RAISE-ONLY. Each tier's
# `auto`/`inherit` is resolved to the session model FIRST (the existing
# transcript machinery), then the effective floor = the HIGHER ordinal
# (haiku=1, sonnet=2, opus=3, unknown=0/no-constraint); on a TIE the PROJECT
# literal wins (its message names the project switch). The user tier can
# only RAISE a project's floor, NEVER lower it — preserving the original
# trust-direction guarantee (a per-user file overriding a per-repo discipline
# was the rejected inversion; a per-user file RAISING protection is safe).
# The existing fail-open defaults are unchanged; a malformed user file simply
# contributes no floor.
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

# D16(a) plugin-lane conditional-skip shim. No-op on the /update-zskills
# lane (CLAUDE_PLUGIN_ROOT unset → guard below skips the source). On the
# plugin lane it defers to a settings.json-registered copy of this hook to
# prevent double-fire when both install lanes are active. Must be the first
# executable line; the shim controls its own exit/return.
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_lib/plugin-hook-skip-if-mirrored.sh" ] && source "${CLAUDE_PLUGIN_ROOT}/hooks/_lib/plugin-hook-skip-if-mirrored.sh"

INPUT=$(cat)

# Only filter Agent tool calls
if [[ "$INPUT" != *'"tool_name":"Agent"'* ]] && [[ "$INPUT" != *'"tool_name": "Agent"'* ]]; then
  exit 0
fi

# Read agents.min_model from config — CASCADE v2 raise-only floor (Phase 4).
# Both the PROJECT config and the user ~/.claude/zskills-config.json are read;
# each tier's literal is resolved (auto/inherit → session model) and the
# effective floor is the HIGHER ordinal, tie→project. The user tier can RAISE
# the floor but never lower it. Read-root pin (R2-7): the project tier keeps
# its existing $REPO_ROOT-based read; the user tier is the additive arm.
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
CONFIG_FILE="$REPO_ROOT/.claude/zskills-config.json"
USER_CONFIG_FILE="${HOME:-}/.claude/zskills-config.json"

# Extract the raw min_model literal from a single config file (empty if
# absent/unreadable). Handles both compact and spaced JSON.
extract_min_model() {
  local file="$1"
  [ -f "$file" ] || { printf ''; return 0; }
  grep -o '"min_model"[[:space:]]*:[[:space:]]*"[^"]*"' "$file" 2>/dev/null \
    | head -1 | sed 's/.*"min_model"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/'
}

PROJECT_MIN_MODEL=$(extract_min_model "$CONFIG_FILE")
USER_MIN_MODEL=""
# Per-tier fail-closed: the user-tier read is purely additive. A malformed /
# unreadable / absent user file yields empty here, contributing no floor.
if [ -n "${HOME:-}" ]; then
  USER_MIN_MODEL=$(extract_min_model "$USER_CONFIG_FILE")
fi

# If NEITHER tier configures min_model, pass through — no enforcement.
if [ -z "$PROJECT_MIN_MODEL" ] && [ -z "$USER_MIN_MODEL" ]; then
  exit 0
fi

# Sentinel resolution: "auto" / "inherit" → match the session's current model.
# The PreToolUse hook's stdin JSON typically includes "transcript_path" pointing
# at the session JSONL; each assistant message record there carries a "model"
# field. We take the most recent, which is the current session model. Each tier
# is resolved INDEPENDENTLY and BEFORE comparison, so a user's explicit floor
# can never be silently lowered by a project "auto" in a low-model session.
resolve_sentinel() {
  local mm="$1"
  if [[ "$mm" != "auto" && "$mm" != "inherit" ]]; then
    printf '%s' "$mm"
    return 0
  fi
  local transcript_path=""
  if [[ "$INPUT" =~ \"transcript_path\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    transcript_path="${BASH_REMATCH[1]}"
  fi
  local resolved=""
  if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    # Walk model entries; filter to ONLY known Claude families (haiku/sonnet/
    # opus); take the most recent. This rejects real-transcript artifacts
    # like `"model":"<synthetic>"` that appear in Claude Code transcripts and
    # would otherwise map to ordinal=0 (unknown), silently disabling the
    # floor for any `auto`-configured project.
    resolved=$(grep -o '"model"[[:space:]]*:[[:space:]]*"[^"]*"' "$transcript_path" \
      | sed 's/.*"model"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' \
      | grep -Ei '(haiku|sonnet|opus)' \
      | tail -1)
  fi
  if [ -n "$resolved" ]; then
    printf '%s' "$resolved"
  else
    # Resolution failed (transcript missing, unreadable, no model field). Fall
    # back to "sonnet" as a conservative floor: still blocks Haiku (per the
    # "never Haiku" rule), allows sonnet+opus. Print a diagnostic to stderr so
    # the failure is visible — not silent.
    echo "block-agents.sh: could not resolve 'auto' from transcript (${transcript_path:-<missing>}); falling back to sonnet floor" >&2
    printf 'claude-sonnet-4-6'
  fi
}

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

# Resolve each tier's effective model (auto/inherit dynamic), then merge
# raise-only: effective floor = higher ordinal; tie → project literal (its
# message names the project switch). An absent tier contributes ordinal 0.
PROJECT_RESOLVED=""
USER_RESOLVED=""
[ -n "$PROJECT_MIN_MODEL" ] && PROJECT_RESOLVED=$(resolve_sentinel "$PROJECT_MIN_MODEL")
[ -n "$USER_MIN_MODEL" ] && USER_RESOLVED=$(resolve_sentinel "$USER_MIN_MODEL")
PROJECT_ORD=$(model_ordinal "$PROJECT_RESOLVED")
USER_ORD=$(model_ordinal "$USER_RESOLVED")

if [ "$USER_ORD" -gt "$PROJECT_ORD" ]; then
  MIN_MODEL="$USER_RESOLVED"
  MIN_ORDINAL="$USER_ORD"
else
  # Includes the TIE case → project literal wins.
  MIN_MODEL="$PROJECT_RESOLVED"
  MIN_ORDINAL="$PROJECT_ORD"
fi

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
# If DISPATCH_MODEL is empty, ordinal=0 (unknown) → ALMOST always pass.
# Defensive layered fix (issue #479): if the unresolved subagent_type is on
# the known-Haiku-pinned list (built-in subagent types that the Claude Code
# environment ships pinned to Haiku), deny instead of allowing. This fails
# closed against future built-in pinned types being added before this repo
# ships a corresponding `.claude/agents/<type>.md` override. The primary
# defense is the override file itself (Step 2 lookup); this is a backstop.
KNOWN_HAIKU_PINNED_SUBAGENTS=" Explore "
if [ -z "$DISPATCH_MODEL" ]; then
  if [ -n "$SUBAGENT_TYPE" ] && [[ "$KNOWN_HAIKU_PINNED_SUBAGENTS" == *" $SUBAGENT_TYPE "* ]]; then
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"subagent_type %s is pinned to Haiku in the host environment but has no .claude/agents/%s.md override resolving it to a higher model. Either pass an explicit model: argument (e.g., model: \"opus\") or add an agent definition file. See CLAUDE.md `## Subagent Dispatch`. [agents.min_model — set in .claude/zskills-config.json; raise-only across config tiers]"}}\n' \
      "$SUBAGENT_TYPE" "$SUBAGENT_TYPE"
    exit 0
  fi
  exit 0
fi

DISPATCH_ORDINAL=$(model_ordinal "$DISPATCH_MODEL")

# Ordinal 0 (unknown family) always passes — future Claude model families
if [ "$DISPATCH_ORDINAL" -eq 0 ]; then
  exit 0
fi

# Block if dispatch model is below the configured minimum
if [ "$DISPATCH_ORDINAL" -lt "$MIN_ORDINAL" ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"agents.min_model requires %s or higher (ordinal %d); got %s (ordinal %d). Update your Agent dispatch to use a higher model. [agents.min_model — set in .claude/zskills-config.json; raise-only across config tiers]"}}\n' \
    "$MIN_MODEL" "$MIN_ORDINAL" "$DISPATCH_MODEL" "$DISPATCH_ORDINAL"
  exit 0
fi

# Model meets or exceeds minimum — allow
exit 0
