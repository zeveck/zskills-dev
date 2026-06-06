#!/bin/bash
# tests/test-block-unmaterialised-skill.sh — gate-LOGIC tests for the
# UserPromptExpansion init-gate (#1128), hooks/block-unmaterialised-skill.sh.
#
# The hook blocks a `/zs:<skill>` slash command BEFORE the skill runs when the
# plugin is half-installed (the SessionStart materialiser has not written the
# 5 consumer artifacts yet). It self-filters on `command_name` (^zs: only),
# exempts the cure (zs:update-zskills), allows when materialized, and never
# matches non-zskills commands.
#
# The shared tests/lib/hooks-harness.sh expect_deny/expect_allow helpers
# hardcode a Bash `tool_input` payload and CANNOT feed a UserPromptExpansion
# JSON, so this suite carries its OWN inline stdin helpers (as #1121's removed
# init-gate tests did with their ig_* helpers). Materialisation is controlled
# by pointing CLAUDE_PROJECT_DIR at a temp project that either carries
# (materialized) or omits (not-materialized) a sentinel-stamped verifier.md.
#
# Run from repo root or any cwd: bash tests/test-block-unmaterialised-skill.sh
#
# NOTE (#1128 acceptance): plugin-scope (hooks.json) FIRING of
# UserPromptExpansion is verified MANUALLY by the author post-merge. This
# suite covers the gate LOGIC only.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/hooks/block-unmaterialised-skill.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS $*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo "FAIL $*"; FAIL_COUNT=$((FAIL_COUNT+1)); }

echo "=== block-unmaterialised-skill.sh (#1128): UserPromptExpansion init-gate ==="

# Make a temp project dir; if $1=="materialized", stamp a sentinel verifier.md
# carrying the D20(a) `zskills-materialised:` prefix in its first 3 lines.
# The sentinel MUST be written to the CANONICAL path the materialiser uses
# (.claude/agents/verifier.md, session-start-materialise.sh:296) — the path the
# gate reads. Writing the bare .claude/verifier.md here is what masked #1132:
# both fixture and (buggy) gate agreed on a path nothing real ever writes, so
# the suite passed while every real install stayed permanently blocked.
bm_make_proj() {
  local kind="$1" dir
  dir=$(mktemp -d)
  mkdir -p "$dir/.claude/agents"
  if [ "$kind" = "materialized" ]; then
    printf '# zskills-materialised: 2026.06.0\n# verifier.md\n\nbody\n' > "$dir/.claude/agents/verifier.md"
  fi
  echo "$dir"
}

# Craft a UserPromptExpansion stdin payload for $command_name and run the hook
# with CLAUDE_PROJECT_DIR pointed at $proj.
bm_run() {
  local proj="$1" cmd_name="$2"
  printf '{"hook_event_name":"UserPromptExpansion","expansion_type":"slash_command","command_name":"%s","command_source":"plugin","command_args":"","prompt":"","cwd":"%s"}' \
    "$cmd_name" "$proj" \
    | CLAUDE_PROJECT_DIR="$proj" bash "$HOOK"
}

bm_expect_deny() {
  local proj="$1" cmd_name="$2" label="$3" result
  result=$(bm_run "$proj" "$cmd_name")
  if [[ "$result" == *'"decision":"block"'* ]] && [[ "$result" == *"finished installing"* ]]; then
    pass "deny: $label"
  else
    fail "deny: $label — expected block, got: $result"
  fi
}

bm_expect_allow() {
  local proj="$1" cmd_name="$2" label="$3" result
  result=$(bm_run "$proj" "$cmd_name")
  if [[ -z "$result" ]]; then
    pass "allow: $label"
  else
    fail "allow: $label — got unexpected output: $result"
  fi
}

BM_PROJ_NOTMAT="$(bm_make_proj not-materialized)"
BM_PROJ_MAT="$(bm_make_proj materialized)"

# DENY: a zs:<skill> command when artifacts ABSENT (not materialized).
bm_expect_deny "$BM_PROJ_NOTMAT" "zs:do" "zs:do, not materialized"
bm_expect_deny "$BM_PROJ_NOTMAT" "zs:fix-issues" "zs:fix-issues, not materialized"

# ALLOW: zs:update-zskills is the CURE — never blocked, even when NOT materialized.
bm_expect_allow "$BM_PROJ_NOTMAT" "zs:update-zskills" "zs:update-zskills (the cure), not materialized"

# ALLOW: a zs:<skill> command when artifacts PRESENT (materialized).
bm_expect_allow "$BM_PROJ_MAT" "zs:do" "zs:do, materialized"

# DENY (#1132 regression): a sentinel written ONLY at the bare
# .claude/verifier.md (the path the buggy gate read) with the canonical
# .claude/agents/verifier.md ABSENT must STILL be treated as NOT materialized.
# The materialiser only ever writes .claude/agents/verifier.md, so honoring the
# bare path would let the broken pre-#1132 gate's masking fixture pass while
# real installs stay blocked. If this case ALLOWs, the path regressed.
BM_PROJ_WRONGPATH="$(mktemp -d)"
mkdir -p "$BM_PROJ_WRONGPATH/.claude"
printf '# zskills-materialised: 2026.06.0\n# verifier.md\n\nbody\n' > "$BM_PROJ_WRONGPATH/.claude/verifier.md"
bm_expect_deny "$BM_PROJ_WRONGPATH" "zs:do" "zs:do, sentinel at WRONG bare path only (#1132)"
rm -rf "$BM_PROJ_WRONGPATH"

# ALLOW: a non-zskills command never matches (no ^zs: prefix), even when NOT
# materialized.
bm_expect_allow "$BM_PROJ_NOTMAT" "help" "help (non-zskills command)"
bm_expect_allow "$BM_PROJ_NOTMAT" "review" "bare slash command (non-zskills)"

rm -rf "$BM_PROJ_NOTMAT"
rm -rf "$BM_PROJ_MAT"

echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
