#!/bin/bash
# tests/test-skill-version-canary-missed-bump.sh — Phase 6.1 canary.
#
# Closes the "missed bump" failure mode of plans/SKILL_VERSIONING.md:
# a developer edits a SKILL.md body and stages it but forgets to bump
# metadata.version. All three enforcement points must fire:
#   1. Edit-time: warn-config-drift.sh emits WARN with "content changed".
#   2. Commit-time: skill-version-stage-check.sh exits 1 with "STOP:".
#   3. CI gate: stale-hash conformance check fails (regex passes; hash
#      check fails).
#
# Plus the F-DA-14 cleanliness-loop honest-clone case: an untracked
# __pycache__/ artifact in a sandbox skill dir does NOT trip the
# `git ls-files`-scoped cleanliness loop; once `git add`-ed, it MUST
# fail. The contrast assertion guards against future agents quietly
# loosening the cleanliness scope.
#
# Defensive sandbox guard: every git operation is rooted in a sandbox
# under $(mktemp -d). The canary aborts if cwd ever resolves inside the
# live $REPO_ROOT.
#
# Run from repo root:
#   bash tests/test-skill-version-canary-missed-bump.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/hooks/warn-config-drift.sh"
STAGE_CHECK="$REPO_ROOT/scripts/skill-version-stage-check.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# Defensive sandbox guard. Refuse to operate inside the live repo.
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

SANDBOX_ROOT=$(mktemp -d -t zskills-canary-missed-bump-XXXXXX)
trap 'rm -rf "$SANDBOX_ROOT"' EXIT

SANDBOX="$SANDBOX_ROOT/clone"
git clone --quiet "$REPO_ROOT" "$SANDBOX"
cd "$SANDBOX"
assert_outside_repo
git config user.email "canary@test.test"
git config user.name "canary"

echo "=== Phase 6.1 canary: missed bump ==="

# Pick a real source skill under skills/ for realistic body editing.
TARGET_SKILL_DIR="$SANDBOX/skills/run-plan"
TARGET_SKILL_MD="$TARGET_SKILL_DIR/SKILL.md"
if [ ! -f "$TARGET_SKILL_MD" ]; then
  echo "FAIL: expected $TARGET_SKILL_MD to exist in sandbox clone" >&2
  exit 1
fi

# Snapshot pre-edit state and confirm version is well-formed (the
# Phase 3 migration has landed in the worktree).
PRE_VER=$(bash "$SANDBOX/scripts/frontmatter-get.sh" "$TARGET_SKILL_MD" metadata.version)
if [[ ! "$PRE_VER" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}\+[0-9a-f]{6}$ ]]; then
  echo "FAIL: pre-edit version '$PRE_VER' not in expected format" >&2
  exit 1
fi

# --- Action: edit body, stage, do NOT bump version. ---
echo "" >> "$TARGET_SKILL_MD"
echo "Body edit added by canary-missed-bump." >> "$TARGET_SKILL_MD"
git add skills/run-plan/SKILL.md

# --- Assertion 1: hook (Edit-time) emits WARN content changed. ---
SYNTH_INPUT=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$TARGET_SKILL_MD")
HOOK_ERR=$(printf '%s' "$SYNTH_INPUT" | CLAUDE_PROJECT_DIR="$SANDBOX" bash "$HOOK" 2>&1 >/dev/null)
if [[ "$HOOK_ERR" == *"WARN:"* ]] && [[ "$HOOK_ERR" == *"content changed"* ]]; then
  pass "edit-time hook emits WARN content-changed"
else
  fail "edit-time hook expected WARN content-changed; got: $HOOK_ERR"
fi

# --- Assertion 2: stage-check exits 1 with STOP. ---
STAGE_ERR=$(CLAUDE_PROJECT_DIR="$SANDBOX" bash "$STAGE_CHECK" 2>&1)
STAGE_EC=$?
if [ "$STAGE_EC" -eq 1 ] && [[ "$STAGE_ERR" == *"STOP:"* ]] && [[ "$STAGE_ERR" == *"skills/run-plan"* ]]; then
  pass "commit-time stage-check exits 1 with STOP naming skills/run-plan"
else
  fail "stage-check expected exit=1 + STOP naming skills/run-plan; got exit=$STAGE_EC err=$STAGE_ERR"
fi

# --- Assertion 3: CI gate — stale-hash check fails. ---
# Replicate the conformance test's stale-hash check directly so we
# don't have to run the full conformance suite. Regex passes (version
# is well-formed); hash freshness check fails (stored != fresh).
on_disk_ver=$(bash "$SANDBOX/scripts/frontmatter-get.sh" "$TARGET_SKILL_MD" metadata.version)
if [[ "$on_disk_ver" =~ ^[0-9]{4}\.(0[1-9]|1[0-2])\.(0[1-9]|[12][0-9]|3[01])\+[0-9a-f]{6}$ ]]; then
  pass "CI gate: regex still passes (well-formed version)"
else
  fail "CI gate: regex unexpectedly failed; version=$on_disk_ver"
fi
stored_hash="${on_disk_ver##*+}"
fresh_hash=$(bash "$SANDBOX/scripts/skill-content-hash.sh" "$TARGET_SKILL_DIR")
if [ "$stored_hash" != "$fresh_hash" ]; then
  pass "CI gate: stale-hash check fails (stored=$stored_hash fresh=$fresh_hash)"
else
  fail "CI gate: stale-hash check should fail; stored=$stored_hash fresh=$fresh_hash"
fi

# Reset for cleanliness sub-case (don't carry the staged edit forward).
git reset --hard HEAD --quiet

# --- Cleanliness-loop honest-clone case (F-DA-14). ---
# Create an untracked __pycache__ artifact under a real skill dir.
# The cleanliness loop scoped to `git ls-files` MUST still pass.
CLEAN_TARGET_DIR="$SANDBOX/skills/briefing"
mkdir -p "$CLEAN_TARGET_DIR/__pycache__"
echo "synthetic" > "$CLEAN_TARGET_DIR/__pycache__/canary.pyc"

# Simulate the conformance test's per-skill cleanliness check on
# this dir.
run_cleanliness_check() {
  local target_dir="$1"
  local skill_rel="${target_dir#$SANDBOX/}"
  local tracked dotfile_hits artifact_hits
  tracked=$(git -C "$SANDBOX" ls-files -- "$skill_rel")
  dotfile_hits=$(printf '%s\n' "$tracked" | awk -F/ '
    { name=$NF }
    name ~ /^\./ && name != ".gitkeep" { print }
  ')
  artifact_hits=$(printf '%s\n' "$tracked" | grep -E '(^|/)(__pycache__|node_modules)(/|$)') \
    || [ "$?" -eq 1 ]
  if [ -n "$dotfile_hits" ] || [ -n "$artifact_hits" ]; then
    return 1
  fi
  return 0
}

if run_cleanliness_check "$CLEAN_TARGET_DIR"; then
  pass "cleanliness loop PASSES with untracked __pycache__ (honest clone)"
else
  fail "cleanliness loop should PASS untracked __pycache__; instead failed"
fi

# Now stage the __pycache__ — cleanliness MUST fail. Force-add
# because the live repo's .gitignore covers __pycache__; the contrast
# assertion is "if a future agent forces this in, the gate catches it."
git -C "$SANDBOX" add -f skills/briefing/__pycache__/

if run_cleanliness_check "$CLEAN_TARGET_DIR"; then
  fail "cleanliness loop should FAIL once __pycache__ is tracked; instead passed"
else
  pass "cleanliness loop FAILS once __pycache__ is git-tracked (contrast assertion)"
fi

# Cleanup: reset stage to keep the sandbox tidy (sandbox itself is
# rm -rf'd by the trap on exit).
git -C "$SANDBOX" reset --hard HEAD --quiet

# --- Summary. ---
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
