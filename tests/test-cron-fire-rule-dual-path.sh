#!/bin/bash
# tests/test-cron-fire-rule-dual-path.sh
#
# Phase 3 (PLUGIN_DISTRIBUTION) — decision D12-prose / F-DA1-2: the cron-fire
# recognition rule must teach Claude to resolve the target SKILL.md path
# under BOTH install layouts:
#   - plugin: ${CLAUDE_PLUGIN_ROOT}/skills/<skill-name>/SKILL.md
#   - legacy: .claude/skills/<skill-name>/SKILL.md
#
# Asserts both path forms appear in the rendered managed.md cron-fire-rule
# section. If this test fails after a rewrite — STOP and review the regex
# (per the plan's Abort/Rollback for Phase 3).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

MANAGED=".claude/rules/zskills/managed.md"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

if [ ! -f "$MANAGED" ]; then
  fail "rendered managed.md present at $MANAGED"
  echo ""
  echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
  exit $FAIL_COUNT
fi

# Scope to the cron-fire recognition section (heading to next "## ").
SECTION="$(awk '
  /^## Cron-fired prompts[[:space:]]*$/ { grab=1; next }
  grab && /^## / { exit }
  grab { print }
' "$MANAGED")"

if [ -z "$SECTION" ]; then
  fail "managed.md contains a '## Cron-fired prompts' section"
  echo ""
  echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
  exit $FAIL_COUNT
else
  pass "managed.md contains a '## Cron-fired prompts' section"
fi

# 1. Plugin-layout SKILL.md path form present.
if grep -qF '${CLAUDE_PLUGIN_ROOT}/skills/<skill-name>/SKILL.md' <<<"$SECTION"; then
  pass "cron-fire rule references the plugin SKILL.md path \${CLAUDE_PLUGIN_ROOT}/skills/<skill-name>/SKILL.md"
else
  fail "cron-fire rule must reference the plugin SKILL.md path \${CLAUDE_PLUGIN_ROOT}/skills/<skill-name>/SKILL.md"
fi

# 2. Legacy-layout SKILL.md path form present.
if grep -qF '.claude/skills/<skill-name>/SKILL.md' <<<"$SECTION"; then
  pass "cron-fire rule references the legacy SKILL.md path .claude/skills/<skill-name>/SKILL.md"
else
  fail "cron-fire rule must reference the legacy SKILL.md path .claude/skills/<skill-name>/SKILL.md"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
exit $FAIL_COUNT
