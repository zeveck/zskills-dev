#!/bin/bash
# Tests for hooks (sub-suite, Test Suite Parallelization Phase 1b).
# block-agents.sh.template — agents.min_model enforcement (model gate, transcript-aware, subagent-type Explore handling).
# This file is a MOVE of sections out of the former tests/test-hooks.sh
# monolith — every assertion is preserved verbatim. Run from repo root or
# any cwd: bash tests/test-hooks-agent.sh
#
# SOURCES tests/lib/hooks-harness.sh for all shared helpers and the
# absolutized hook-path globals (HOOK / PROJECT_HOOK / AGENTS_HOOK /
# WARN_HOOK), pass/fail counters, expect_* helpers, the project-hook
# fixture helpers, and setup_project_test_on_main. Emits exactly ONE
# canonical Results: line. Registered in run-all.sh as a run_suite; it
# carries no self-registration assertion (matches the former monolith).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/hooks/block-unsafe-generic.sh"

# shellcheck source=tests/lib/hooks-harness.sh
. "$SCRIPT_DIR/lib/hooks-harness.sh"

# ─── block-agents.sh.template tests ───
echo "=== block-agents.sh — agents.min_model enforcement ==="

AGENTS_HOOK="$REPO_ROOT/hooks/block-agents.sh.template"

# Helper: run agent hook with tool_name=Agent, optional model field
run_agent_hook() {
  local model_field="$1"    # e.g. '"model":"haiku"' or ""
  local config_json="$2"    # content of .claude/zskills-config.json or ""
  local tmp_repo
  tmp_repo=$(mktemp -d)
  mkdir -p "$tmp_repo/.claude"
  (cd "$tmp_repo" && git init -q 2>/dev/null)

  if [ -n "$config_json" ]; then
    printf '%s\n' "$config_json" > "$tmp_repo/.claude/zskills-config.json"
  fi

  local tool_input
  if [ -n "$model_field" ]; then
    tool_input="{\"tool_name\":\"Agent\",\"tool_input\":{${model_field},\"prompt\":\"Do something\"}}"
  else
    tool_input="{\"tool_name\":\"Agent\",\"tool_input\":{\"prompt\":\"Do something\"}}"
  fi

  local result
  result=$(echo "$tool_input" | REPO_ROOT="$tmp_repo" bash "$AGENTS_HOOK" 2>/dev/null)
  rm -rf "$tmp_repo"
  echo "$result"
}

# 1. No config → pass through (no enforcement)
result=$(run_agent_hook '"model":"haiku"' "")
if [[ -z "$result" ]]; then
  pass "no config → always allow"
else
  fail "no config → expected allow, got: $result"
fi

# 2. min_model=sonnet, dispatch model=haiku → deny
CONFIG_SONNET='{"agents":{"min_model":"claude-sonnet-4-6"}}'
result=$(run_agent_hook '"model":"claude-haiku-4-5"' "$CONFIG_SONNET")
if [[ "$result" == *"permissionDecision"*"deny"* ]]; then
  pass "min_model=sonnet, model=haiku → deny"
else
  fail "min_model=sonnet, model=haiku → expected deny, got: $result"
fi

# 3. min_model=sonnet, dispatch model=sonnet → allow
result=$(run_agent_hook '"model":"claude-sonnet-4-6"' "$CONFIG_SONNET")
if [[ -z "$result" ]]; then
  pass "min_model=sonnet, model=sonnet → allow"
else
  fail "min_model=sonnet, model=sonnet → expected allow, got: $result"
fi

# 4. min_model=sonnet, dispatch model=opus → allow
result=$(run_agent_hook '"model":"claude-opus-4-6"' "$CONFIG_SONNET")
if [[ -z "$result" ]]; then
  pass "min_model=sonnet, model=opus → allow"
else
  fail "min_model=sonnet, model=opus → expected allow, got: $result"
fi

# 5. min_model=sonnet, no model in tool_input → allow (unknown=0, pass-through)
result=$(run_agent_hook "" "$CONFIG_SONNET")
if [[ -z "$result" ]]; then
  pass "min_model=sonnet, no model field → allow (residual case)"
else
  fail "min_model=sonnet, no model field → expected allow, got: $result"
fi

# 6. Non-Agent tool_name → ignore entirely
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | bash "$AGENTS_HOOK" 2>/dev/null)
if [[ -z "$result" ]]; then
  pass "non-Agent tool_name → pass through (not our concern)"
else
  fail "non-Agent tool_name → expected silent pass, got: $result"
fi

# 7. min_model=haiku, dispatch model=haiku → allow (haiku meets haiku)
CONFIG_HAIKU='{"agents":{"min_model":"claude-haiku-4-5"}}'
result=$(run_agent_hook '"model":"claude-haiku-4-5"' "$CONFIG_HAIKU")
if [[ -z "$result" ]]; then
  pass "min_model=haiku, model=haiku → allow"
else
  fail "min_model=haiku, model=haiku → expected allow, got: $result"
fi

# 8. Unknown model family → always allow (future-proofing)
result=$(run_agent_hook '"model":"claude-nova-4-6"' "$CONFIG_SONNET")
if [[ -z "$result" ]]; then
  pass "unknown model family (claude-nova) → allow (ordinal=0 passes)"
else
  fail "unknown model family → expected allow, got: $result"
fi

# ─── auto/inherit resolution tests ───
# Helper: run agent hook with transcript_path in the hook input payload.
run_agent_hook_with_transcript() {
  local model_field="$1"       # e.g. '"model":"haiku"' or ""
  local config_json="$2"       # config content
  local transcript_content="$3" # JSONL lines for the transcript
  local tmp_repo tmp_transcript
  tmp_repo=$(mktemp -d)
  tmp_transcript=$(mktemp)
  mkdir -p "$tmp_repo/.claude"
  (cd "$tmp_repo" && git init -q 2>/dev/null)

  if [ -n "$config_json" ]; then
    printf '%s\n' "$config_json" > "$tmp_repo/.claude/zskills-config.json"
  fi
  printf '%s\n' "$transcript_content" > "$tmp_transcript"

  local tool_input
  if [ -n "$model_field" ]; then
    tool_input="{\"tool_name\":\"Agent\",\"transcript_path\":\"$tmp_transcript\",\"tool_input\":{${model_field},\"prompt\":\"Do something\"}}"
  else
    tool_input="{\"tool_name\":\"Agent\",\"transcript_path\":\"$tmp_transcript\",\"tool_input\":{\"prompt\":\"Do something\"}}"
  fi

  local result
  result=$(echo "$tool_input" | REPO_ROOT="$tmp_repo" bash "$AGENTS_HOOK" 2>/dev/null)
  rm -rf "$tmp_repo" "$tmp_transcript"
  echo "$result"
}

# 9. min_model=auto + transcript says opus + dispatch=sonnet → deny
CONFIG_AUTO='{"agents":{"min_model":"auto"}}'
TRANSCRIPT_OPUS='{"role":"assistant","model":"claude-opus-4-6","content":"hi"}'
result=$(run_agent_hook_with_transcript '"model":"claude-sonnet-4-6"' "$CONFIG_AUTO" "$TRANSCRIPT_OPUS")
if [[ "$result" == *"permissionDecision"*"deny"* ]]; then
  pass "min_model=auto (resolves to opus), model=sonnet → deny"
else
  fail "min_model=auto resolved to opus, sonnet dispatch → expected deny, got: $result"
fi

# 10. min_model=auto + transcript says opus + dispatch=opus → allow
result=$(run_agent_hook_with_transcript '"model":"claude-opus-4-6"' "$CONFIG_AUTO" "$TRANSCRIPT_OPUS")
if [[ -z "$result" ]]; then
  pass "min_model=auto (resolves to opus), model=opus → allow"
else
  fail "min_model=auto resolved to opus, opus dispatch → expected allow, got: $result"
fi

# 11. min_model=inherit alias works the same as auto
CONFIG_INHERIT='{"agents":{"min_model":"inherit"}}'
result=$(run_agent_hook_with_transcript '"model":"claude-sonnet-4-6"' "$CONFIG_INHERIT" "$TRANSCRIPT_OPUS")
if [[ "$result" == *"permissionDecision"*"deny"* ]]; then
  pass "min_model=inherit (alias of auto) → resolves same"
else
  fail "min_model=inherit → expected same resolution as auto, got: $result"
fi

# 12. min_model=auto + transcript unreadable → falls back to sonnet floor (blocks haiku, allows sonnet)
# Simulate an unresolvable auto by omitting transcript_path entirely
tmp_repo=$(mktemp -d)
mkdir -p "$tmp_repo/.claude"
(cd "$tmp_repo" && git init -q 2>/dev/null)
printf '%s\n' "$CONFIG_AUTO" > "$tmp_repo/.claude/zskills-config.json"
result=$(echo '{"tool_name":"Agent","tool_input":{"model":"claude-haiku-4-5","prompt":"x"}}' \
  | REPO_ROOT="$tmp_repo" bash "$AGENTS_HOOK" 2>/dev/null)
rm -rf "$tmp_repo"
if [[ "$result" == *"permissionDecision"*"deny"* ]]; then
  pass "min_model=auto, no transcript_path → falls back to sonnet floor (blocks haiku)"
else
  fail "min_model=auto, no transcript_path → expected fallback deny, got: $result"
fi

# 13. min_model=auto + transcript says sonnet + dispatch=sonnet → allow (session matches)
TRANSCRIPT_SONNET='{"role":"assistant","model":"claude-sonnet-4-6","content":"hi"}'
result=$(run_agent_hook_with_transcript '"model":"claude-sonnet-4-6"' "$CONFIG_AUTO" "$TRANSCRIPT_SONNET")
if [[ -z "$result" ]]; then
  pass "min_model=auto (resolves to sonnet), model=sonnet → allow"
else
  fail "min_model=auto resolved to sonnet, sonnet dispatch → expected allow, got: $result"
fi

# 14. min_model=auto + transcript says sonnet + dispatch=haiku → deny
result=$(run_agent_hook_with_transcript '"model":"claude-haiku-4-5"' "$CONFIG_AUTO" "$TRANSCRIPT_SONNET")
if [[ "$result" == *"permissionDecision"*"deny"* ]]; then
  pass "min_model=auto (resolves to sonnet), model=haiku → deny"
else
  fail "min_model=auto resolved to sonnet, haiku dispatch → expected deny, got: $result"
fi

# 15. CRITICAL regression test: transcript ends with "<synthetic>" — the auto
# resolver must IGNORE this entry (real Claude Code transcripts end this way)
# and pick the last valid family-keyword model. Without the filter, ordinal=0
# means the haiku floor silently disappears.
TRANSCRIPT_WITH_SYNTHETIC='{"type":"assistant","message":{"model":"claude-opus-4-6","role":"assistant"}}
{"type":"assistant","message":{"model":"claude-opus-4-6","role":"assistant"}}
{"type":"assistant","message":{"model":"<synthetic>","role":"assistant"}}'
result=$(run_agent_hook_with_transcript '"model":"claude-haiku-4-5"' "$CONFIG_AUTO" "$TRANSCRIPT_WITH_SYNTHETIC")
if [[ "$result" == *"permissionDecision"*"deny"* ]]; then
  pass "min_model=auto, transcript trailing <synthetic> → resolves to last valid family (opus), haiku denied"
else
  fail "min_model=auto, <synthetic> regression: expected deny (Haiku under Opus floor), got: $result"
fi

# 16. min_model=auto + transcript ONLY has <synthetic> (no valid family) →
# fallback to sonnet floor
TRANSCRIPT_ONLY_SYNTHETIC='{"type":"assistant","message":{"model":"<synthetic>","role":"assistant"}}'
result=$(run_agent_hook_with_transcript '"model":"claude-haiku-4-5"' "$CONFIG_AUTO" "$TRANSCRIPT_ONLY_SYNTHETIC")
if [[ "$result" == *"permissionDecision"*"deny"* ]]; then
  pass "min_model=auto, transcript only has <synthetic> → fallback sonnet floor denies haiku"
else
  fail "min_model=auto, only <synthetic> → expected fallback deny, got: $result"
fi

# ─── issue #479: subagent_type Explore Haiku-prevention bypass ───
# The prior hook resolved DISPATCH_MODEL via (a) tool_input.model then
# (b) .claude/agents/<subagent_type>.md frontmatter. Built-in subagent
# types like "Explore" (Haiku-pinned per CLAUDE.md `## Subagent Dispatch`)
# had no .md file in the repo → DISPATCH_MODEL stayed empty → empty-allow
# bypass let a Haiku-pinned dispatch through. Fix has two layers:
#   1. Primary: .claude/agents/Explore.md with `model: opus` → Step 2
#      lookup now resolves Explore to opus.
#   2. Defensive: known-Haiku-pinned-list deny in Step 3 → if the lookup
#      file is missing AND subagent_type is on the list, fail closed.
# Tests below exercise both layers via run_agent_hook_with_subagent (which
# accepts an agent_def_content argument so we can simulate missing-file
# vs override-present cases independently).

# Helper: run agent hook with subagent_type field + optional agent definition file.
run_agent_hook_with_subagent() {
  local model_field="$1"       # e.g. '"model":"haiku"' or ""
  local subagent_type="$2"     # e.g. "Explore" or "general-purpose"
  local config_json="$3"       # content of .claude/zskills-config.json or ""
  local agent_def_content="$4" # if non-empty, write to .claude/agents/<subagent_type>.md
  local tmp_repo
  tmp_repo=$(mktemp -d)
  mkdir -p "$tmp_repo/.claude/agents"
  (cd "$tmp_repo" && git init -q 2>/dev/null)

  if [ -n "$config_json" ]; then
    printf '%s\n' "$config_json" > "$tmp_repo/.claude/zskills-config.json"
  fi
  if [ -n "$agent_def_content" ]; then
    printf '%s\n' "$agent_def_content" > "$tmp_repo/.claude/agents/${subagent_type}.md"
  fi

  local tool_input_fields
  tool_input_fields="\"subagent_type\":\"$subagent_type\",\"prompt\":\"Do something\""
  if [ -n "$model_field" ]; then
    tool_input_fields="${model_field},$tool_input_fields"
  fi
  local tool_input="{\"tool_name\":\"Agent\",\"tool_input\":{${tool_input_fields}}}"

  local result
  result=$(echo "$tool_input" | REPO_ROOT="$tmp_repo" bash "$AGENTS_HOOK" 2>/dev/null)
  rm -rf "$tmp_repo"
  echo "$result"
}

# 17. Issue #479 primary: subagent_type=Explore, no model, no agent file →
# known-Haiku-pinned-list deny fires (defensive layer 2). This is the bypass
# being closed: without the fix, DISPATCH_MODEL would be empty → exit 0.
result=$(run_agent_hook_with_subagent "" "Explore" "$CONFIG_SONNET" "")
if [[ "$result" == *"permissionDecision"*"deny"* ]]; then
  pass "#479: subagent_type=Explore, no model, no override file → deny (known-Haiku-pinned-list)"
else
  fail "#479: subagent_type=Explore unresolved → expected deny, got: $result"
fi

# 18. Issue #479: subagent_type=Explore with explicit model=haiku → deny via
# normal min_model gate (Step 1 catches it before Step 3).
result=$(run_agent_hook_with_subagent '"model":"claude-haiku-4-5"' "Explore" "$CONFIG_SONNET" "")
if [[ "$result" == *"permissionDecision"*"deny"* ]]; then
  pass "#479: subagent_type=Explore, model=haiku → deny (min_model gate)"
else
  fail "#479: Explore+haiku → expected deny, got: $result"
fi

# 19. Issue #479: subagent_type=Explore with explicit model=opus → allow
# (explicit override beats the Haiku-pinned default).
result=$(run_agent_hook_with_subagent '"model":"claude-opus-4-6"' "Explore" "$CONFIG_SONNET" "")
if [[ -z "$result" ]]; then
  pass "#479: subagent_type=Explore, model=opus → allow"
else
  fail "#479: Explore+opus → expected allow, got: $result"
fi

# 20. Issue #479 baseline: subagent_type=general-purpose, no model, no agent
# file → ALLOW (general-purpose inherits parent; empty-allow is correct
# here; it is NOT on the known-Haiku-pinned list).
result=$(run_agent_hook_with_subagent "" "general-purpose" "$CONFIG_SONNET" "")
if [[ -z "$result" ]]; then
  pass "#479: subagent_type=general-purpose, no model → allow (inherit-parent, not on Haiku-pinned list)"
else
  fail "#479: general-purpose no-model → expected allow, got: $result"
fi

# 21. Issue #479 primary-layer validation: subagent_type=Explore, no
# tool_input.model, .claude/agents/Explore.md present with `model: opus` →
# Step 2 lookup resolves DISPATCH_MODEL=opus → allow. Confirms the override
# file shipped in this PR satisfies the hook's existing lookup path.
EXPLORE_OVERRIDE_MD='---
name: Explore
model: opus
---
body'
result=$(run_agent_hook_with_subagent "" "Explore" "$CONFIG_SONNET" "$EXPLORE_OVERRIDE_MD")
if [[ -z "$result" ]]; then
  pass "#479: subagent_type=Explore, override .md resolves model: opus → allow"
else
  fail "#479: Explore+override-file → expected allow, got: $result"
fi

echo ""


echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
