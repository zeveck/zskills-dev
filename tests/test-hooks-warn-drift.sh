#!/bin/bash
# Tests for hooks (sub-suite, Test Suite Parallelization Phase 1b).
# PostToolUse warn-config-drift.sh: config drift warn + skill-file drift warn (owns WARN_HOOK and the #594 PID-scoped SKILL_DRIFT_FIXTURE).
# This file is a MOVE of sections out of the former tests/test-hooks.sh
# monolith — every assertion is preserved verbatim. Run from repo root or
# any cwd: bash tests/test-hooks-warn-drift.sh
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

# ─── Phase 3: PostToolUse drift-warn hook ─────────────────────────────
echo ""
echo "=== PostToolUse: config drift warn ==="

WARN_HOOK="$REPO_ROOT/hooks/warn-config-drift.sh"

# Helper: run warn hook, capture stderr (fd2) and rc. stdout is discarded
# — the hook only speaks on stderr.
_run_warn_hook() {
  local _input="$1"
  local _err_file
  _err_file=$(mktemp)
  printf '%s' "$_input" | bash "$WARN_HOOK" 2>"$_err_file" >/dev/null
  _WARN_RC=$?
  _WARN_ERR=$(cat "$_err_file")
  rm -f "$_err_file"
}

# Case 1: Edit on repo-relative .claude/zskills-config.json → warn fires.
_run_warn_hook '{"tool_name":"Edit","tool_input":{"file_path":".claude/zskills-config.json"}}'
if [[ "$_WARN_RC" -eq 0 ]] \
  && [[ "$_WARN_ERR" == *".claude/rules/zskills/managed.md"* ]] \
  && [[ "$_WARN_ERR" == *"/update-zskills --rerender"* ]]; then
  pass "warn-config-drift: Edit on .claude/zskills-config.json — stderr warns, rc=0"
else
  fail "warn-config-drift: Edit relative — rc=$_WARN_RC, stderr=$_WARN_ERR"
fi

# Case 2: Edit with absolute path → same warn (suffix matcher).
_run_warn_hook '{"tool_name":"Edit","tool_input":{"file_path":"/workspaces/zskills/.claude/zskills-config.json"}}'
if [[ "$_WARN_RC" -eq 0 ]] \
  && [[ "$_WARN_ERR" == *".claude/rules/zskills/managed.md"* ]] \
  && [[ "$_WARN_ERR" == *"/update-zskills --rerender"* ]]; then
  pass "warn-config-drift: Edit absolute path — suffix-match fires warn, rc=0"
else
  fail "warn-config-drift: Edit absolute — rc=$_WARN_RC, stderr=$_WARN_ERR"
fi

# Case 3: Edit on an unrelated file → stderr empty.
_run_warn_hook '{"tool_name":"Edit","tool_input":{"file_path":"package.json"}}'
if [[ "$_WARN_RC" -eq 0 ]] && [[ -z "$_WARN_ERR" ]]; then
  pass "warn-config-drift: Edit on package.json — no warn, rc=0"
else
  fail "warn-config-drift: Edit unrelated — rc=$_WARN_RC, stderr=$_WARN_ERR"
fi

# Case 4: Write on .claude/zskills-config.json → same warn.
_run_warn_hook '{"tool_name":"Write","tool_input":{"file_path":".claude/zskills-config.json"}}'
if [[ "$_WARN_RC" -eq 0 ]] \
  && [[ "$_WARN_ERR" == *".claude/rules/zskills/managed.md"* ]] \
  && [[ "$_WARN_ERR" == *"/update-zskills --rerender"* ]]; then
  pass "warn-config-drift: Write on .claude/zskills-config.json — stderr warns, rc=0"
else
  fail "warn-config-drift: Write — rc=$_WARN_RC, stderr=$_WARN_ERR"
fi

# Case 5: Malformed stdin → non-blocking exit, stderr empty.
_run_warn_hook 'not json garbage at all'
if [[ "$_WARN_RC" -eq 0 ]] && [[ -z "$_WARN_ERR" ]]; then
  pass "warn-config-drift: malformed stdin — rc=0, stderr empty (non-blocking)"
else
  fail "warn-config-drift: malformed — rc=$_WARN_RC, stderr=$_WARN_ERR"
fi

echo ""
echo "=== PostToolUse: skill-file drift warn ==="
# WI 4.2 / 4.5 — the warn hook also reads tests/fixtures/forbidden-literals.txt
# and emits a WARN when an Edit/Write on skills/<owner>/...md leaves a
# forbidden literal in the file without an <!-- allow-hardcoded ... -->
# marker on the same or previous line. The mirror tree
# (.claude/skills/...) is intentionally excluded.

# Fresh fixture directory laid out like a zskills repo so the hook's
# CLAUDE_PROJECT_DIR-based fixture lookup works.
SKILL_DRIFT_FIXTURE=/tmp/zskills-warn-skill-drift-test-$$
rm -rf "$SKILL_DRIFT_FIXTURE"
mkdir -p "$SKILL_DRIFT_FIXTURE/tests/fixtures"
mkdir -p "$SKILL_DRIFT_FIXTURE/skills/foo"
mkdir -p "$SKILL_DRIFT_FIXTURE/.claude/skills/foo"
cp "$REPO_ROOT/tests/fixtures/forbidden-literals.txt" \
   "$SKILL_DRIFT_FIXTURE/tests/fixtures/forbidden-literals.txt"

# Helper: same shape as _run_warn_hook but passes CLAUDE_PROJECT_DIR so
# the hook can resolve the fixture file.
_run_skill_warn() {
  local _input="$1"
  local _err_file
  _err_file=$(mktemp)
  printf '%s' "$_input" \
    | CLAUDE_PROJECT_DIR="$SKILL_DRIFT_FIXTURE" bash "$WARN_HOOK" \
        2>"$_err_file" >/dev/null
  _WARN_RC=$?
  _WARN_ERR=$(cat "$_err_file")
  rm -f "$_err_file"
}

# Case 6: Edit on skills/foo/SKILL.md adding a forbidden literal inside
# a bash fence → WARN to stderr, rc=0.
cat > "$SKILL_DRIFT_FIXTURE/skills/foo/SKILL.md" <<'SKILL'
# Foo

```bash
TZ=America/New_York date -Iseconds
```
SKILL
_run_skill_warn '{"tool_name":"Edit","tool_input":{"file_path":"'"$SKILL_DRIFT_FIXTURE"'/skills/foo/SKILL.md"}}'
if [[ "$_WARN_RC" -eq 0 ]] \
  && [[ "$_WARN_ERR" == *"WARN:"* ]] \
  && [[ "$_WARN_ERR" == *"TZ=America/New_York"* ]] \
  && [[ "$_WARN_ERR" == *"skills/foo/SKILL.md:4"* ]]; then
  pass "warn-config-drift: skill-file forbidden literal — WARN emitted, rc=0"
else
  fail "warn-config-drift: skill-file literal — rc=$_WARN_RC, stderr=$_WARN_ERR"
fi

# Case 7: Same content but with an <!-- allow-hardcoded ... --> marker on
# the line immediately above the fence-opener → no WARN.
cat > "$SKILL_DRIFT_FIXTURE/skills/foo/SKILL.md" <<'SKILL'
# Foo

<!-- allow-hardcoded: TZ=America/New_York reason: example demonstrating timezone literal in synthetic fixture -->
```bash
TZ=America/New_York date -Iseconds
```
SKILL
_run_skill_warn '{"tool_name":"Edit","tool_input":{"file_path":"'"$SKILL_DRIFT_FIXTURE"'/skills/foo/SKILL.md"}}'
if [[ "$_WARN_RC" -eq 0 ]] && [[ -z "$_WARN_ERR" ]]; then
  pass "warn-config-drift: skill-file with allow-hardcoded marker above fence — no WARN, rc=0"
else
  fail "warn-config-drift: skill-file marker — rc=$_WARN_RC, stderr=$_WARN_ERR"
fi

# Case 8: Edit on the .claude/skills mirror path → mirror branch is
# excluded (the source skills/ Edit fires the hook; warning twice would
# spam the cp-batched mirror update). Stderr empty, rc=0.
cat > "$SKILL_DRIFT_FIXTURE/.claude/skills/foo/SKILL.md" <<'SKILL'
# Foo

```bash
TZ=America/New_York date -Iseconds
```
SKILL
_run_skill_warn '{"tool_name":"Edit","tool_input":{"file_path":"'"$SKILL_DRIFT_FIXTURE"'/.claude/skills/foo/SKILL.md"}}'
if [[ "$_WARN_RC" -eq 0 ]] && [[ -z "$_WARN_ERR" ]]; then
  pass "warn-config-drift: .claude/skills mirror path — no WARN (mirror exclusion), rc=0"
else
  fail "warn-config-drift: mirror path — rc=$_WARN_RC, stderr=$_WARN_ERR"
fi

# Case 9: Regex deny-list entry exemption — the fixture has
# `re:\$TEST_OUT/\.test-results\.txt`. The allowlist marker references the
# pattern WITHOUT the `re:` prefix.
cat > "$SKILL_DRIFT_FIXTURE/skills/foo/SKILL.md" <<'SKILL'
# Foo

<!-- allow-hardcoded: \$TEST_OUT/\.test-results\.txt reason: demonstrating regex-entry exemption in synthetic fixture -->
```bash
echo $TEST_OUT/.test-results.txt
```
SKILL
_run_skill_warn '{"tool_name":"Edit","tool_input":{"file_path":"'"$SKILL_DRIFT_FIXTURE"'/skills/foo/SKILL.md"}}'
if [[ "$_WARN_RC" -eq 0 ]] && [[ -z "$_WARN_ERR" ]]; then
  pass "warn-config-drift: regex-entry allow-hardcoded marker exempts hit — no WARN, rc=0"
else
  fail "warn-config-drift: regex-entry marker — rc=$_WARN_RC, stderr=$_WARN_ERR"
fi

# Case 10: Fixture missing → graceful no-op.
rm -f "$SKILL_DRIFT_FIXTURE/tests/fixtures/forbidden-literals.txt"
cat > "$SKILL_DRIFT_FIXTURE/skills/foo/SKILL.md" <<'SKILL'
# Foo

```bash
TZ=America/New_York date -Iseconds
```
SKILL
_run_skill_warn '{"tool_name":"Edit","tool_input":{"file_path":"'"$SKILL_DRIFT_FIXTURE"'/skills/foo/SKILL.md"}}'
if [[ "$_WARN_RC" -eq 0 ]] && [[ -z "$_WARN_ERR" ]]; then
  pass "warn-config-drift: missing fixture — graceful no-op, rc=0, stderr empty"
else
  fail "warn-config-drift: missing fixture — rc=$_WARN_RC, stderr=$_WARN_ERR"
fi

# Cleanup the synthetic fixture tree.
rm -rf "$SKILL_DRIFT_FIXTURE"

echo ""


echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
