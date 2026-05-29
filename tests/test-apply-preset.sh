#!/bin/bash
# Tests for skills/update-zskills/scripts/apply-preset.sh
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

# apply-preset.sh is now CONFIG-ONLY — it must NOT read, require, or edit
# the generic hook. This sentinel hook content lets us assert the hook is
# left byte-identical after every apply.
CURRENT_HOOK='#!/bin/bash
# Block unsafe commands
# GENERIC safety layer

INPUT=$(cat)
exit 0'

# make_project <dir> <config-content> [<hook-content>]
# The hook is optional — apply-preset no longer requires it. When provided,
# tests use it to assert the hook is left untouched.
make_project() {
  local dir="$1" cfg="$2" hook="${3:-}"
  mkdir -p "$dir/.claude"
  printf '%s' "$cfg" > "$dir/.claude/zskills-config.json"
  if [ -n "$hook" ]; then
    mkdir -p "$dir/.claude/hooks"
    printf '%s' "$hook" > "$dir/.claude/hooks/block-unsafe-generic.sh"
  fi
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

# Each test uses a unique literal /tmp/zskills-apply-test-<N>/ directory so
# the generic hook's "rm -r requires literal /tmp/<name>" rule lets us clean
# up without variable expansion.

# ────────────────────────────────────────────────────────────────────
echo "=== Happy path: each preset writes ONLY config (no hook edits) ==="

# Canonical state is cherry-pick/false. Applying a DIFFERENT preset must
# flip the config fields; the generic hook must be left byte-identical
# (config-only behavior — the hook reads main_protected at runtime now).
rm -rf /tmp/zskills-apply-test-1
make_project /tmp/zskills-apply-test-1 "$CANONICAL_CONFIG" "$CURRENT_HOOK"
hook_before_1=$(cat /tmp/zskills-apply-test-1/.claude/hooks/block-unsafe-generic.sh)
result=$(run_preset /tmp/zskills-apply-test-1 locked-main-pr)
rc="${result%%$'\n'*}"
hook_after_1=$(cat /tmp/zskills-apply-test-1/.claude/hooks/block-unsafe-generic.sh)
if [ "$rc" = "0" ] && \
   [ "$(get_landing /tmp/zskills-apply-test-1/.claude/zskills-config.json)" = "pr" ] && \
   [ "$(get_main_protected /tmp/zskills-apply-test-1/.claude/zskills-config.json)" = "true" ] && \
   [ "$hook_before_1" = "$hook_after_1" ]; then
  pass "locked-main-pr: config landing=pr/main_protected=true; hook left byte-identical"
else
  fail "locked-main-pr: rc=$rc, landing=$(get_landing /tmp/zskills-apply-test-1/.claude/zskills-config.json), main_protected=$(get_main_protected /tmp/zskills-apply-test-1/.claude/zskills-config.json), hook-changed=$([ "$hook_before_1" = "$hook_after_1" ] && echo no || echo YES)"
fi

rm -rf /tmp/zskills-apply-test-2
make_project /tmp/zskills-apply-test-2 "$CANONICAL_CONFIG" "$CURRENT_HOOK"
hook_before_2=$(cat /tmp/zskills-apply-test-2/.claude/hooks/block-unsafe-generic.sh)
result=$(run_preset /tmp/zskills-apply-test-2 direct)
rc="${result%%$'\n'*}"
hook_after_2=$(cat /tmp/zskills-apply-test-2/.claude/hooks/block-unsafe-generic.sh)
if [ "$rc" = "0" ] && \
   [ "$(get_landing /tmp/zskills-apply-test-2/.claude/zskills-config.json)" = "direct" ] && \
   [ "$(get_main_protected /tmp/zskills-apply-test-2/.claude/zskills-config.json)" = "false" ] && \
   [ "$hook_before_2" = "$hook_after_2" ]; then
  pass "direct: config landing=direct/main_protected=false; hook left byte-identical"
else
  fail "direct: rc=$rc"
fi

# Applying the SAME preset the config already carries → no-op rc=1 (config
# already matches; no hook splice exists to force a change anymore).
rm -rf /tmp/zskills-apply-test-3
make_project /tmp/zskills-apply-test-3 "$CANONICAL_CONFIG" "$CURRENT_HOOK"
result=$(run_preset /tmp/zskills-apply-test-3 cherry-pick)
rc="${result%%$'\n'*}"
if [ "$rc" = "1" ] && echo "${result#*$'\n'}" | grep -q "already applied"; then
  pass "cherry-pick on already-cherry-pick config: rc=1 'already applied' (config-only, no hook to flip)"
else
  fail "cherry-pick no-op: rc=$rc, out=${result#*$'\n'}"
fi

# apply-preset must succeed even when NO generic hook exists at all (the
# config-only contract — it no longer requires the hook file).
rm -rf /tmp/zskills-apply-test-3b
make_project /tmp/zskills-apply-test-3b "$CANONICAL_CONFIG"   # no hook arg
result=$(run_preset /tmp/zskills-apply-test-3b locked-main-pr)
rc="${result%%$'\n'*}"
if [ "$rc" = "0" ] && \
   [ "$(get_main_protected /tmp/zskills-apply-test-3b/.claude/zskills-config.json)" = "true" ] && \
   [ ! -e /tmp/zskills-apply-test-3b/.claude/hooks/block-unsafe-generic.sh ]; then
  pass "no hook present: apply still succeeds (config-only), no hook created"
else
  fail "no-hook config-only: rc=$rc, out=${result#*$'\n'}"
fi

echo ""
echo "=== Idempotency ==="

rm -rf /tmp/zskills-apply-test-4
make_project /tmp/zskills-apply-test-4 "$CANONICAL_CONFIG" "$CURRENT_HOOK"
# First apply of a DIFFERENT preset — should change config fields.
PROJECT_ROOT=/tmp/zskills-apply-test-4 bash "$SCRIPT" locked-main-pr >/dev/null 2>&1
# Second apply of the SAME preset — should report "already applied" and exit 1.
PROJECT_ROOT=/tmp/zskills-apply-test-4 bash "$SCRIPT" locked-main-pr >/tmp/zskills-apply-test-4-out 2>&1
rc=$?
if [ "$rc" = "1" ] && grep -q "already applied" /tmp/zskills-apply-test-4-out; then
  pass "second apply of same preset exits rc=1 with 'already applied' message"
else
  pass_result=$(cat /tmp/zskills-apply-test-4-out)
  fail "idempotency: rc=$rc, out=$pass_result"
fi
rm -f /tmp/zskills-apply-test-4-out

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
# Hook file missing (no .claude/hooks/ dir). Config-only contract: apply must
# NOT error on a missing hook (rc=3 is now reserved for a MISSING CONFIG).
# Applying a different preset succeeds (rc=0) and writes only config.
result=$(run_preset /tmp/zskills-apply-test-10 locked-main-pr)
rc="${result%%$'\n'*}"
if [ "$rc" = "0" ] && \
   [ "$(get_main_protected /tmp/zskills-apply-test-10/.claude/zskills-config.json)" = "true" ] && \
   [ ! -d /tmp/zskills-apply-test-10/.claude/hooks ]; then
  pass "missing hook file no longer errors: rc=0, config updated, no hook dir created"
else
  fail "missing hook file (config-only): expected rc=0 + config flip + no hook dir, got rc=$rc, out=${result#*$'\n'}"
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
echo "=== Sibling-collision: extra.landing must not poison read or write (#400) ==="

# Multi-line canonical JSON with a sibling object that has the SAME key
# names ("landing", "main_protected") at a different scope. The unscoped
# regex from the pre-#400 implementation would (a) read "WRONG" from
# extra.landing and "true" from extra.main_protected on the FIRST hit,
# and (b) overwrite extra.landing instead of (or in addition to)
# execution.landing on the write path.
SIBLING_CONFIG='{
  "$schema": "./zskills-config.schema.json",
  "project_name": "sibling",
  "extra": {
    "landing": "WRONG",
    "main_protected": true
  },
  "execution": {
    "landing": "cherry-pick",
    "main_protected": false,
    "branch_prefix": "feat/"
  },
  "testing": { "unit_cmd": "npm test" }
}'

# Read-path test: after applying cherry-pick to a config whose
# execution.landing is already cherry-pick AND main_protected is already
# false, there is NO state change at all (config-only: no hook splice to
# force a change). The result is rc=1 "already applied". If the read regex
# were unscoped it would see extra.landing="WRONG" and
# extra.main_protected=true and report spurious execution field changes
# (rc=0).
rm -rf /tmp/zskills-apply-test-15
make_project /tmp/zskills-apply-test-15 "$SIBLING_CONFIG" "$CURRENT_HOOK"
out=$(PROJECT_ROOT=/tmp/zskills-apply-test-15 bash "$SCRIPT" cherry-pick 2>&1)
rc=$?
# Expectation: rc=1 (no change — config already matches cherry-pick), and
# no execution.* changes reported.
if [ "$rc" = "1" ] && \
   echo "$out" | grep -q "already applied" && \
   ! echo "$out" | grep -q "execution.landing=" && \
   ! echo "$out" | grep -q "execution.main_protected="; then
  pass "sibling-collision read: CURRENT_LANDING / CURRENT_PROTECTED scoped to execution (no spurious flip reports)"
else
  fail "sibling-collision read: rc=$rc, out=$out"
fi

# Write-path test: flip cherry-pick → locked-main-pr. execution.landing
# should change to "pr"; execution.main_protected should change to
# "true"; extra.landing MUST remain "WRONG"; extra.main_protected MUST
# remain "true" (was already true — but key insight is that the unscoped
# write would clobber it to whatever the new value was, including in
# this case leaving the right value via coincidence; the landing test is
# the clean disambiguator).
rm -rf /tmp/zskills-apply-test-16
make_project /tmp/zskills-apply-test-16 "$SIBLING_CONFIG" "$CURRENT_HOOK"
PROJECT_ROOT=/tmp/zskills-apply-test-16 bash "$SCRIPT" locked-main-pr >/dev/null 2>&1
after=/tmp/zskills-apply-test-16/.claude/zskills-config.json
# Use python to read both scopes unambiguously (zskills allows Python).
PYTHON=${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}
read_exec_landing=$("$PYTHON" -c "import json,sys;d=json.load(open(sys.argv[1]));print(d['execution']['landing'])" "$after")
read_extra_landing=$("$PYTHON" -c "import json,sys;d=json.load(open(sys.argv[1]));print(d['extra']['landing'])" "$after")
read_exec_protected=$("$PYTHON" -c "import json,sys;d=json.load(open(sys.argv[1]));print(d['execution']['main_protected'])" "$after")
read_extra_protected=$("$PYTHON" -c "import json,sys;d=json.load(open(sys.argv[1]));print(d['extra']['main_protected'])" "$after")
if [ "$read_exec_landing" = "pr" ] && \
   [ "$read_extra_landing" = "WRONG" ] && \
   [ "$read_exec_protected" = "True" ] && \
   [ "$read_extra_protected" = "True" ]; then
  pass "sibling-collision write: only execution.* updated; extra.landing/extra.main_protected preserved verbatim"
else
  fail "sibling-collision write: execution.landing=$read_exec_landing (want pr), extra.landing=$read_extra_landing (want WRONG), execution.main_protected=$read_exec_protected (want True), extra.main_protected=$read_extra_protected (want True)
config after:
$(cat "$after")"
fi

# Sharper write-path probe: pre-state where extra.landing differs from
# execution.landing AND extra.main_protected is the OPPOSITE of the
# target. The pre-#400 unscoped sed would clobber extra.* alongside
# execution.* (or instead of, depending on which match wins). With the
# scope-aware exec_field_replace, extra.* must remain identical to the
# input.
SIBLING_OPPOSITE_CONFIG='{
  "project_name": "sibling-opp",
  "extra": {
    "landing": "BOGUS",
    "main_protected": false
  },
  "execution": {
    "landing": "cherry-pick",
    "main_protected": false,
    "branch_prefix": "feat/"
  }
}'
rm -rf /tmp/zskills-apply-test-17
make_project /tmp/zskills-apply-test-17 "$SIBLING_OPPOSITE_CONFIG" "$CURRENT_HOOK"
PROJECT_ROOT=/tmp/zskills-apply-test-17 bash "$SCRIPT" locked-main-pr >/dev/null 2>&1
after=/tmp/zskills-apply-test-17/.claude/zskills-config.json
read_exec_landing=$("$PYTHON" -c "import json,sys;d=json.load(open(sys.argv[1]));print(d['execution']['landing'])" "$after")
read_extra_landing=$("$PYTHON" -c "import json,sys;d=json.load(open(sys.argv[1]));print(d['extra']['landing'])" "$after")
read_exec_protected=$("$PYTHON" -c "import json,sys;d=json.load(open(sys.argv[1]));print(d['execution']['main_protected'])" "$after")
read_extra_protected=$("$PYTHON" -c "import json,sys;d=json.load(open(sys.argv[1]));print(d['extra']['main_protected'])" "$after")
if [ "$read_exec_landing" = "pr" ] && \
   [ "$read_extra_landing" = "BOGUS" ] && \
   [ "$read_exec_protected" = "True" ] && \
   [ "$read_extra_protected" = "False" ]; then
  pass "sibling-collision write (opposite values): execution.* flipped, extra.* preserved (landing=BOGUS, main_protected=False)"
else
  fail "sibling-collision write (opposite): execution.landing=$read_exec_landing (want pr), extra.landing=$read_extra_landing (want BOGUS), execution.main_protected=$read_exec_protected (want True), extra.main_protected=$read_extra_protected (want False)
config after:
$(cat "$after")"
fi

echo ""
echo "=== Cleanup ==="
for n in 1 2 3 3b 4 5 6 7 8 9 10 11 12 13 14 15 16 17; do
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
