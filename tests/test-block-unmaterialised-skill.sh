#!/bin/bash
# tests/test-block-unmaterialised-skill.sh — gate-LOGIC tests for the
# UserPromptExpansion init-gate (#1128, re-keyed by INSTALL_REDESIGN Phase
# 6b), hooks/block-unmaterialised-skill.sh.
#
# The hook blocks a `/zs:<skill>` slash command BEFORE the skill runs when
# the plugin consumer has not run the one-time explicit setup
# (`/zs:update-zskills` — the Phase 6a init that writes `.zskills/init-done`
# lock-LAST). It self-filters on `command_name` (^zs: only), exempts the
# cure (zs:update-zskills), allows the read-only ALLOW-LIST skills pre-init,
# allows unconditionally when a legacy mirror is present, allows when
# init-done is present, and never matches non-zskills commands.
#
# #1132 single-path-definition discipline: fixtures create the init-done
# marker by SOURCING skills/update-zskills/scripts/init-state.sh and calling
# its WRITER (zskills_write_init_markers) — never a re-typed path. The
# wrong-key regression fixture derives the OLD materialiser sentinel from
# init-state.sh's frozen legacy-residue constant, never a re-typed literal.
#
# The shared tests/lib/hooks-harness.sh expect_deny/expect_allow helpers
# hardcode a Bash `tool_input` payload and CANNOT feed a UserPromptExpansion
# JSON, so this suite carries its OWN inline stdin helpers (as #1121's
# removed init-gate tests did with their ig_* helpers).
#
# Run from repo root or any cwd: bash tests/test-block-unmaterialised-skill.sh
#
# NOTE: plugin-scope (hooks.json) FIRING of UserPromptExpansion is verified
# LIVE (both branches — #1132) by the Phase 6b live gate validation. This
# suite covers the gate LOGIC only.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/hooks/block-unmaterialised-skill.sh"
INIT_STATE="$REPO_ROOT/skills/update-zskills/scripts/init-state.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS $*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo "FAIL $*"; FAIL_COUNT=$((FAIL_COUNT+1)); }

echo "=== block-unmaterialised-skill.sh (#1128/Phase 6b): UserPromptExpansion init-gate ==="

# Single path definition (#1132): the marker paths, the WRITER the
# initialised fixture uses, and the frozen legacy sentinel constant the
# wrong-key regression fixture derives from.
# shellcheck source=../skills/update-zskills/scripts/init-state.sh
. "$INIT_STATE"

# Make a temp project dir; if $1=="initialised", write the init markers via
# the REAL writer (the same function the Step 0.7 init arm calls) — never a
# re-typed path (#1132).
bm_make_proj() {
  local kind="$1" dir
  dir=$(mktemp -d)
  if [ "$kind" = "initialised" ]; then
    zskills_write_init_markers "$dir" "2026.06.0" || echo "FIXTURE-BROKEN: writer failed" >&2
  fi
  echo "$dir"
}

# Craft a UserPromptExpansion stdin payload for $command_name and run the
# hook with CLAUDE_PROJECT_DIR pointed at $proj. CLAUDE_PLUGIN_ROOT is
# explicitly unset so the hook exercises its BASH_SOURCE self-location path
# (the repo tree IS the plugin tree here).
bm_run() {
  local proj="$1" cmd_name="$2"
  printf '{"hook_event_name":"UserPromptExpansion","expansion_type":"slash_command","command_name":"%s","command_source":"plugin","command_args":"","prompt":"","cwd":"%s"}' \
    "$cmd_name" "$proj" \
    | env -u CLAUDE_PLUGIN_ROOT CLAUDE_PROJECT_DIR="$proj" bash "$HOOK"
}

bm_expect_deny() {
  local proj="$1" cmd_name="$2" label="$3" result
  result=$(bm_run "$proj" "$cmd_name")
  if [[ "$result" == *'"decision":"block"'* ]] \
     && [[ "$result" == *"one-time setup"* ]] \
     && [[ "$result" == *"/zs:update-zskills"* ]]; then
    pass "deny: $label"
  else
    fail "deny: $label — expected block naming the cure, got: $result"
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

BM_PROJ_FRESH="$(bm_make_proj fresh)"
BM_PROJ_INIT="$(bm_make_proj initialised)"

# DENY: state-writing zs:<skill> commands when init-done ABSENT (pre-init).
bm_expect_deny "$BM_PROJ_FRESH" "zs:do" "zs:do, pre-init (state-writing)"
bm_expect_deny "$BM_PROJ_FRESH" "zs:fix-issues" "zs:fix-issues, pre-init (state-writing)"
bm_expect_deny "$BM_PROJ_FRESH" "zs:run-plan" "zs:run-plan, pre-init (state-writing)"

# DENY (fails safe): an UNLISTED (hypothetical future) skill is blocked
# pre-init — the allow-list is the only gate-opening list.
bm_expect_deny "$BM_PROJ_FRESH" "zs:some-future-skill" "zs:some-future-skill, pre-init (unlisted -> fails safe to blocked)"

# ALLOW: zs:update-zskills is the CURE — never blocked, even pre-init.
bm_expect_allow "$BM_PROJ_FRESH" "zs:update-zskills" "zs:update-zskills (the cure), pre-init"

# ALLOW: read-only allow-list members pass pre-init.
bm_expect_allow "$BM_PROJ_FRESH" "zs:briefing" "zs:briefing (allow-list), pre-init"
bm_expect_allow "$BM_PROJ_FRESH" "zs:session-report" "zs:session-report (allow-list), pre-init"
bm_expect_allow "$BM_PROJ_FRESH" "zs:plans" "zs:plans (allow-list), pre-init"
bm_expect_allow "$BM_PROJ_FRESH" "zs:manual-testing" "zs:manual-testing (allow-list), pre-init"

# ALLOW: a state-writing zs:<skill> command when init-done PRESENT
# (marker written by init-state.sh's OWN writer — #1132).
bm_expect_allow "$BM_PROJ_INIT" "zs:do" "zs:do, initialised (init-done present)"
bm_expect_allow "$BM_PROJ_INIT" "zs:fix-issues" "zs:fix-issues, initialised"

# DENY (#1079 family): a 0-byte init-done is a partial leftover, NOT
# initialised — the presence predicate requires non-empty.
BM_PROJ_0BYTE="$(bm_make_proj fresh)"
mkdir -p "$BM_PROJ_0BYTE/$(dirname "$ZSKILLS_INIT_DONE_REL")"
: > "$BM_PROJ_0BYTE/$ZSKILLS_INIT_DONE_REL"
bm_expect_deny "$BM_PROJ_0BYTE" "zs:do" "zs:do, 0-byte init-done (partial leftover, #1079)"
rm -rf "$BM_PROJ_0BYTE"

# ALLOW: legacy mirror present -> allow unconditionally, NO init-done needed
# (a mirrored repo is initialised by definition; detect-install-state.sh's
# zskills-skill anchor evidence — this is the dogfood/dual-load case).
BM_PROJ_MIRROR="$(bm_make_proj fresh)"
mkdir -p "$BM_PROJ_MIRROR/.claude/skills/update-zskills"
printf '%s\n' '---' 'name: update-zskills' '---' '# Update Z Skills' \
  > "$BM_PROJ_MIRROR/.claude/skills/update-zskills/SKILL.md"
bm_expect_allow "$BM_PROJ_MIRROR" "zs:do" "zs:do, legacy mirror present (no init-done)"
rm -rf "$BM_PROJ_MIRROR"

# DENY (wrong-key regression — #1132): the OLD materialiser sentinel at the
# OLD key (.claude/agents/verifier.md) must NOT satisfy the new gate. A
# materialiser-era consumer who upgrades mid-window carries exactly this
# state and must be BLOCKED until they run /zs:update-zskills once (the
# documented self-curing mid-window behavior). The sentinel prefix is
# DERIVED from init-state.sh's frozen legacy-residue constant.
BM_PROJ_OLDKEY="$(bm_make_proj fresh)"
mkdir -p "$BM_PROJ_OLDKEY/.claude/agents"
printf '%s\n' "# $ZSKILLS_LEGACY_SENTINEL_PREFIX 2026.06.0" '# verifier.md' '' 'body' \
  > "$BM_PROJ_OLDKEY/.claude/agents/verifier.md"
bm_expect_deny "$BM_PROJ_OLDKEY" "zs:do" "zs:do, OLD materialiser sentinel only (wrong key no longer unlocks, #1132)"
rm -rf "$BM_PROJ_OLDKEY"

# ALLOW: a non-zskills command never matches (no ^zs: prefix), even pre-init.
bm_expect_allow "$BM_PROJ_FRESH" "help" "help (non-zskills command)"
bm_expect_allow "$BM_PROJ_FRESH" "review" "bare slash command (non-zskills)"

rm -rf "$BM_PROJ_FRESH"
rm -rf "$BM_PROJ_INIT"

echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
