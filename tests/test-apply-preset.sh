#!/bin/bash
# Tests for scripts/apply-preset.sh
# Run from repo root: bash tests/test-apply-preset.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/skills/update-zskills/scripts/apply-preset.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  printf '\033[32m  PASS\033[0m %s\n' "$1"
  PASS_COUNT=$((PASS_COUNT + 1))
}
fail() {
  printf '\033[31m  FAIL\033[0m %s\n' "$1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

# --- Fixtures ---
# Canonical pre-state (what /update-zskills writes for cherry-pick preset):
CANONICAL_CONFIG='{
  "$schema": "./zskills-config.schema.json",
  "project_name": "test",
  "execution": {
    "landing": "cherry-pick",
    "main_protected": false,
    "branch_prefix": "feat/"
  },
  "testing": {
    "unit_cmd": "npm test",
    "output_file": ".test-results.txt"
  }
}'

CURRENT_HOOK='#!/bin/bash
# Block unsafe commands
# GENERIC safety layer

BLOCK_MAIN_PUSH=1

INPUT=$(cat)
exit 0'

LEGACY_HOOK='#!/bin/bash
# Block unsafe commands
# GENERIC safety layer (pre-preset-UX legacy hook)

INPUT=$(cat)
exit 0'

# make_project <dir> <config-content> <hook-content>
make_project() {
  local dir="$1" cfg="$2" hook="$3"
  mkdir -p "$dir/.claude/hooks"
  printf '%s' "$cfg" > "$dir/.claude/zskills-config.json"
  printf '%s' "$hook" > "$dir/.claude/hooks/block-unsafe-generic.sh"
}

# run_preset <dir> <preset> → prints "rc=<code>|<stdout>"
# Always sets PROJECT_ROOT explicitly so the script can never accidentally
# modify the host zskills repo even if a bug lets cwd drift.
run_preset() {
  local dir="$1" preset="$2"
  local out rc
  out=$(PROJECT_ROOT="$dir" bash "$SCRIPT" "$preset" 2>&1)
  rc=$?
  printf '%s\n%s' "$rc" "$out"
}

# get_field <file> <bash-regex-group> — extracts a JSON field value via bash regex
get_landing() {
  local out
  out=$(grep -m1 '"landing"' "$1" | sed 's/.*"landing"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  echo "$out"
}
get_main_protected() {
  grep -m1 '"main_protected"' "$1" | sed 's/.*"main_protected"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/'
}
get_block_main_push() {
  grep -m1 '^BLOCK_MAIN_PUSH=' "$1" | sed 's/^BLOCK_MAIN_PUSH=\([01]\).*/\1/'
}

# Each test uses a unique literal /tmp/zskills-apply-test-<N>/ directory so
# the generic hook's "rm -r requires literal /tmp/<name>" rule lets us clean
# up without variable expansion.

# ────────────────────────────────────────────────────────────────────
echo "=== Happy path: each preset from canonical state ==="

rm -rf /tmp/zskills-apply-test-1
make_project /tmp/zskills-apply-test-1 "$CANONICAL_CONFIG" "$CURRENT_HOOK"
result=$(run_preset /tmp/zskills-apply-test-1 cherry-pick)
rc="${result%%$'\n'*}"
if [ "$rc" = "0" ] && \
   [ "$(get_landing /tmp/zskills-apply-test-1/.claude/zskills-config.json)" = "cherry-pick" ] && \
   [ "$(get_main_protected /tmp/zskills-apply-test-1/.claude/zskills-config.json)" = "false" ] && \
   [ "$(get_block_main_push /tmp/zskills-apply-test-1/.claude/hooks/block-unsafe-generic.sh)" = "0" ]; then
  pass "cherry-pick on canonical state: landing/main_protected correct, BLOCK_MAIN_PUSH flipped to 0"
else
  fail "cherry-pick on canonical state: rc=$rc, landing=$(get_landing /tmp/zskills-apply-test-1/.claude/zskills-config.json), main_protected=$(get_main_protected /tmp/zskills-apply-test-1/.claude/zskills-config.json), BLOCK_MAIN_PUSH=$(get_block_main_push /tmp/zskills-apply-test-1/.claude/hooks/block-unsafe-generic.sh)"
fi

rm -rf /tmp/zskills-apply-test-2
make_project /tmp/zskills-apply-test-2 "$CANONICAL_CONFIG" "$CURRENT_HOOK"
result=$(run_preset /tmp/zskills-apply-test-2 locked-main-pr)
rc="${result%%$'\n'*}"
if [ "$rc" = "0" ] && \
   [ "$(get_landing /tmp/zskills-apply-test-2/.claude/zskills-config.json)" = "pr" ] && \
   [ "$(get_main_protected /tmp/zskills-apply-test-2/.claude/zskills-config.json)" = "true" ] && \
   [ "$(get_block_main_push /tmp/zskills-apply-test-2/.claude/hooks/block-unsafe-generic.sh)" = "1" ]; then
  pass "locked-main-pr on canonical state: all three fields land correctly"
else
  fail "locked-main-pr on canonical state: rc=$rc"
fi

rm -rf /tmp/zskills-apply-test-3
make_project /tmp/zskills-apply-test-3 "$CANONICAL_CONFIG" "$CURRENT_HOOK"
result=$(run_preset /tmp/zskills-apply-test-3 direct)
rc="${result%%$'\n'*}"
if [ "$rc" = "0" ] && \
   [ "$(get_landing /tmp/zskills-apply-test-3/.claude/zskills-config.json)" = "direct" ] && \
   [ "$(get_main_protected /tmp/zskills-apply-test-3/.claude/zskills-config.json)" = "false" ] && \
   [ "$(get_block_main_push /tmp/zskills-apply-test-3/.claude/hooks/block-unsafe-generic.sh)" = "0" ]; then
  pass "direct on canonical state: all three fields land correctly"
else
  fail "direct on canonical state: rc=$rc"
fi

echo ""
echo "=== Idempotency ==="

rm -rf /tmp/zskills-apply-test-4
make_project /tmp/zskills-apply-test-4 "$CANONICAL_CONFIG" "$CURRENT_HOOK"
# First apply — should change something (BLOCK_MAIN_PUSH 1→0 for cherry-pick).
PROJECT_ROOT=/tmp/zskills-apply-test-4 bash "$SCRIPT" cherry-pick >/dev/null 2>&1
# Second apply — should report "already applied" and exit 1.
PROJECT_ROOT=/tmp/zskills-apply-test-4 bash "$SCRIPT" cherry-pick >/tmp/zskills-apply-test-4-out 2>&1
rc=$?
if [ "$rc" = "1" ] && grep -q "already applied" /tmp/zskills-apply-test-4-out; then
  pass "second apply of same preset exits rc=1 with 'already applied' message"
else
  pass_result=$(cat /tmp/zskills-apply-test-4-out)
  fail "idempotency: rc=$rc, out=$pass_result"
fi
rm -f /tmp/zskills-apply-test-4-out

echo ""
echo "=== Legacy hook splice ==="

rm -rf /tmp/zskills-apply-test-5
make_project /tmp/zskills-apply-test-5 "$CANONICAL_CONFIG" "$LEGACY_HOOK"
result=$(run_preset /tmp/zskills-apply-test-5 cherry-pick)
rc="${result%%$'\n'*}"
hook_after=/tmp/zskills-apply-test-5/.claude/hooks/block-unsafe-generic.sh
if [ "$rc" = "0" ] && \
   grep -q "^BLOCK_MAIN_PUSH=0" "$hook_after" && \
   grep -q "^# Preset toggle" "$hook_after" && \
   grep -q "^INPUT=" "$hook_after"; then
  pass "legacy hook: BLOCK_MAIN_PUSH= spliced in; original code preserved"
else
  fail "legacy hook splice: rc=$rc; hook after:
$(cat "$hook_after")"
fi

# Re-apply — should be no-op now that the splice has set the target value
rm -rf /tmp/zskills-apply-test-6
make_project /tmp/zskills-apply-test-6 "$CANONICAL_CONFIG" "$LEGACY_HOOK"
PROJECT_ROOT=/tmp/zskills-apply-test-6 bash "$SCRIPT" cherry-pick >/dev/null 2>&1
PROJECT_ROOT=/tmp/zskills-apply-test-6 bash "$SCRIPT" cherry-pick >/tmp/zskills-apply-test-6-out 2>&1
rc=$?
if [ "$rc" = "1" ]; then
  pass "legacy hook post-splice: second apply is idempotent"
else
  fail "legacy hook post-splice idempotency: rc=$rc, out=$(cat /tmp/zskills-apply-test-6-out)"
fi
rm -f /tmp/zskills-apply-test-6-out

echo ""
echo "=== Missing execution key insert ==="

NO_EXEC_CONFIG='{
  "project_name": "noex",
  "testing": { "unit_cmd": "npm test" }
}'

rm -rf /tmp/zskills-apply-test-7
make_project /tmp/zskills-apply-test-7 "$NO_EXEC_CONFIG" "$CURRENT_HOOK"
result=$(run_preset /tmp/zskills-apply-test-7 locked-main-pr)
rc="${result%%$'\n'*}"
if [ "$rc" = "0" ] && \
   [ "$(get_landing /tmp/zskills-apply-test-7/.claude/zskills-config.json)" = "pr" ] && \
   [ "$(get_main_protected /tmp/zskills-apply-test-7/.claude/zskills-config.json)" = "true" ]; then
  pass "missing 'execution' key: block inserted with preset values"
else
  fail "missing execution insert: rc=$rc, config:
$(cat /tmp/zskills-apply-test-7/.claude/zskills-config.json)"
fi

# Verify unrelated keys preserved
if grep -q '"project_name": "noex"' /tmp/zskills-apply-test-7/.claude/zskills-config.json && \
   grep -q '"unit_cmd": "npm test"' /tmp/zskills-apply-test-7/.claude/zskills-config.json; then
  pass "missing execution insert: project_name and testing.unit_cmd preserved"
else
  fail "missing execution insert: unrelated keys NOT preserved"
fi

echo ""
echo "=== Preserves unrelated config fields on normal flip ==="

RICH_CONFIG='{
  "$schema": "./zskills-config.schema.json",
  "project_name": "rich",
  "timezone": "Europe/London",
  "execution": {
    "landing": "cherry-pick",
    "main_protected": false,
    "branch_prefix": "custom/"
  },
  "testing": { "unit_cmd": "pytest", "full_cmd": "pytest -v" },
  "ci": { "auto_fix": false, "max_fix_attempts": 3 }
}'

rm -rf /tmp/zskills-apply-test-8
make_project /tmp/zskills-apply-test-8 "$RICH_CONFIG" "$CURRENT_HOOK"
result=$(run_preset /tmp/zskills-apply-test-8 locked-main-pr)
rc="${result%%$'\n'*}"
after=/tmp/zskills-apply-test-8/.claude/zskills-config.json
if [ "$rc" = "0" ] && \
   grep -q '"timezone": "Europe/London"' "$after" && \
   grep -q '"branch_prefix": "custom/"' "$after" && \
   grep -q '"unit_cmd": "pytest"' "$after" && \
   grep -q '"auto_fix": false' "$after" && \
   grep -q '"max_fix_attempts": 3' "$after"; then
  pass "non-preset fields preserved: timezone, branch_prefix, testing.*, ci.*"
else
  fail "non-preset field preservation: rc=$rc, config:
$(cat "$after")"
fi

echo ""
echo "=== Error paths ==="

rm -rf /tmp/zskills-apply-test-9
mkdir -p /tmp/zskills-apply-test-9
result=$(run_preset /tmp/zskills-apply-test-9 cherry-pick)
rc="${result%%$'\n'*}"
if [ "$rc" = "3" ]; then
  pass "missing config file: rc=3"
else
  fail "missing config file: expected rc=3, got rc=$rc"
fi

rm -rf /tmp/zskills-apply-test-10
mkdir -p /tmp/zskills-apply-test-10/.claude
printf '%s' "$CANONICAL_CONFIG" > /tmp/zskills-apply-test-10/.claude/zskills-config.json
# Hook file missing (no .claude/hooks/ dir)
result=$(run_preset /tmp/zskills-apply-test-10 cherry-pick)
rc="${result%%$'\n'*}"
if [ "$rc" = "3" ]; then
  pass "missing hook file: rc=3"
else
  fail "missing hook file: expected rc=3, got rc=$rc"
fi

rm -rf /tmp/zskills-apply-test-11
make_project /tmp/zskills-apply-test-11 "$CANONICAL_CONFIG" "$CURRENT_HOOK"
result=$(run_preset /tmp/zskills-apply-test-11 bogus-preset)
rc="${result%%$'\n'*}"
if [ "$rc" = "2" ]; then
  pass "unknown preset: rc=2"
else
  fail "unknown preset: expected rc=2, got rc=$rc"
fi

rm -rf /tmp/zskills-apply-test-12
make_project /tmp/zskills-apply-test-12 "$CANONICAL_CONFIG" "$CURRENT_HOOK"
out=$(PROJECT_ROOT=/tmp/zskills-apply-test-12 bash "$SCRIPT" 2>&1)
rc=$?
if [ "$rc" = "2" ] && echo "$out" | grep -q "usage:"; then
  pass "no preset arg: rc=2 and usage message"
else
  fail "no preset arg: rc=$rc, out=$out"
fi

rm -rf /tmp/zskills-apply-test-13
make_project /tmp/zskills-apply-test-13 '{"$schema": "./zskills-config.schema.json", "broken"' "$CURRENT_HOOK"
out=$(PROJECT_ROOT=/tmp/zskills-apply-test-13 bash "$SCRIPT" cherry-pick 2>&1)
rc=$?
if [ "$rc" = "4" ]; then
  pass "malformed JSON config: rc=4"
else
  fail "malformed JSON: expected rc=4, got rc=$rc"
fi

echo ""
echo "=== Compact JSON formatting (no spaces, single-line) ==="

COMPACT_CONFIG='{"execution":{"landing":"cherry-pick","main_protected":false,"branch_prefix":"feat/"},"testing":{"unit_cmd":"npm test"}}'

rm -rf /tmp/zskills-apply-test-14
make_project /tmp/zskills-apply-test-14 "$COMPACT_CONFIG" "$CURRENT_HOOK"
result=$(run_preset /tmp/zskills-apply-test-14 locked-main-pr)
rc="${result%%$'\n'*}"
if [ "$rc" = "0" ] && \
   [ "$(get_landing /tmp/zskills-apply-test-14/.claude/zskills-config.json)" = "pr" ] && \
   [ "$(get_main_protected /tmp/zskills-apply-test-14/.claude/zskills-config.json)" = "true" ]; then
  pass "compact JSON input: permissive sed regex handles it; fields rewrite correctly"
else
  fail "compact JSON: rc=$rc"
fi

echo ""
echo "=== Cleanup ==="
for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do
  rm -rf "/tmp/zskills-apply-test-$n"
done
pass "temp dirs cleaned"

echo ""
echo "---"
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ $FAIL_COUNT -eq 0 ]; then
  echo -e "\033[32mResults: $PASS_COUNT passed, 0 failed (of $TOTAL)\033[0m"
  exit 0
else
  echo -e "\033[31mResults: $PASS_COUNT passed, $FAIL_COUNT failed (of $TOTAL)\033[0m"
  exit 1
fi
