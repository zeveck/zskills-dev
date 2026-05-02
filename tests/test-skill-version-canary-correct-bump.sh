#!/bin/bash
# tests/test-skill-version-canary-correct-bump.sh — Phase 6.2 canary.
#
# Closes the "correct bump" path of plans/SKILL_VERSIONING.md: when a
# developer edits a SKILL.md body AND bumps metadata.version to
# `today+freshhash` before staging, ALL three enforcement points must
# remain silent / pass:
#   1. Edit-time: warn-config-drift.sh emits NO version-bump-missing
#      WARN.
#   2. Commit-time: skill-version-stage-check.sh exits 0 silent.
#   3. CI gate: per-skill version frontmatter check passes (regex +
#      hash freshness).
#
# Defensive sandbox guard: see canary-missed-bump.
#
# Run from repo root:
#   bash tests/test-skill-version-canary-correct-bump.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/hooks/warn-config-drift.sh"
STAGE_CHECK="$REPO_ROOT/scripts/skill-version-stage-check.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

assert_outside_repo() {
  local pwd_real repo_real
  pwd_real=$(realpath "$PWD")
  repo_real=$(realpath "$REPO_ROOT")
  case "$pwd_real" in
    "$repo_real"|"$repo_real"/*)
      echo "FAIL: canary refusing to operate inside live repo: $pwd_real" >&2
      exit 1
      ;;
  esac
}

SANDBOX_ROOT=$(mktemp -d -t zskills-canary-correct-bump-XXXXXX)
trap 'rm -rf "$SANDBOX_ROOT"' EXIT

SANDBOX="$SANDBOX_ROOT/clone"
git clone --quiet "$REPO_ROOT" "$SANDBOX"
cd "$SANDBOX"
assert_outside_repo
git config user.email "canary@test.test"
git config user.name "canary"

echo "=== Phase 6.2 canary: correct bump ==="

TARGET_SKILL_DIR="$SANDBOX/skills/run-plan"
TARGET_SKILL_MD="$TARGET_SKILL_DIR/SKILL.md"
[ -f "$TARGET_SKILL_MD" ] || { echo "FAIL: missing $TARGET_SKILL_MD" >&2; exit 1; }

# --- Action: edit body AND bump version. ---
echo "" >> "$TARGET_SKILL_MD"
echo "Body edit added by canary-correct-bump." >> "$TARGET_SKILL_MD"

TODAY=$(TZ=America/New_York date +%Y.%m.%d)
FRESH_HASH=$(bash "$SANDBOX/scripts/skill-content-hash.sh" "$TARGET_SKILL_DIR")
NEW_VER="$TODAY+$FRESH_HASH"
bash "$SANDBOX/scripts/frontmatter-set.sh" "$TARGET_SKILL_MD" metadata.version "$NEW_VER"

# Sanity-check the bump landed.
ON_DISK=$(bash "$SANDBOX/scripts/frontmatter-get.sh" "$TARGET_SKILL_MD" metadata.version)
if [ "$ON_DISK" != "$NEW_VER" ]; then
  fail "bump did not land on disk; expected $NEW_VER got $ON_DISK"
fi

git add skills/run-plan/SKILL.md

# --- Assertion 1: edit-time hook silent on version-bump-missing. ---
SYNTH_INPUT=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$TARGET_SKILL_MD")
HOOK_ERR=$(printf '%s' "$SYNTH_INPUT" | CLAUDE_PROJECT_DIR="$SANDBOX" bash "$HOOK" 2>&1 >/dev/null)
# The hook may legitimately emit OTHER WARNs (forbidden-literal scans,
# etc.) on a real skill; the canary's contract is the absence of the
# version-bump-missing pattern. Match on the precise predicate.
if [[ "$HOOK_ERR" != *"content changed"*"metadata.version unchanged"* ]] \
   && [[ "$HOOK_ERR" != *"content unchanged"* ]]; then
  pass "edit-time hook: no version-bump-missing/symmetric WARN"
else
  fail "edit-time hook unexpectedly emitted version drift WARN; got: $HOOK_ERR"
fi

# --- Assertion 2: commit-time stage-check silent + exit 0. ---
STAGE_ERR=$(CLAUDE_PROJECT_DIR="$SANDBOX" bash "$STAGE_CHECK" 2>&1)
STAGE_EC=$?
if [ "$STAGE_EC" -eq 0 ] && [[ -z "$STAGE_ERR" ]]; then
  pass "commit-time stage-check: exit 0 silent"
else
  fail "stage-check expected exit 0 silent; got exit=$STAGE_EC err=$STAGE_ERR"
fi

# --- Assertion 3: CI gate — regex + freshness both pass. ---
if [[ "$ON_DISK" =~ ^[0-9]{4}\.(0[1-9]|1[0-2])\.(0[1-9]|[12][0-9]|3[01])\+[0-9a-f]{6}$ ]]; then
  pass "CI gate: regex passes ($ON_DISK)"
else
  fail "CI gate: regex failed for $ON_DISK"
fi
stored_hash="${ON_DISK##*+}"
fresh_recheck=$(bash "$SANDBOX/scripts/skill-content-hash.sh" "$TARGET_SKILL_DIR")
if [ "$stored_hash" = "$fresh_recheck" ]; then
  pass "CI gate: freshness passes (stored=$stored_hash matches recomputed)"
else
  fail "CI gate: freshness should pass; stored=$stored_hash recomputed=$fresh_recheck"
fi

# Cleanup.
git -C "$SANDBOX" reset --hard HEAD --quiet

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo ""
echo "---"
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (of %d)\033[0m\n' "$PASS_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (of %d)\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit 1
fi
