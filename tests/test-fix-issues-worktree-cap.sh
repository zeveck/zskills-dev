#!/bin/bash
# test-fix-issues-worktree-cap.sh — regression guards for issue #295.
#
# Issue #295: /fix-issues' 3-cap addresses 9p checkout I/O contention at
# dispatch time, but does NOT bound aggregate live-worktree count across
# the sprint. Mid-sprint, all N worktrees end up alive concurrently —
# each running tests + a verifier + a CI workflow — OOMing/stalling
# resource-constrained containers.
#
# Fix (Option 3): added `execution.max_concurrent_worktrees` (default 3)
# to the zskills-config schema and resolver, then added a "Live worktree
# count check" gate to /fix-issues Phase 3 that defers dispatch when live
# count >= cap.
#
# Tests:
#   1. Schema declares execution.max_concurrent_worktrees with default 3
#      and minimum 1.
#   2. Resolver default — absent field yields $ZSKILLS_MAX_CONCURRENT_WORKTREES=3.
#   3. Resolver override — execution.max_concurrent_worktrees=5 yields 5.
#   4. Resolver guards bogus values (string / 0 / negative regex-mismatch)
#      → falls back to default 3.
#   5. SKILL.md Phase 3 contains the "Live worktree count check" gate:
#      sources the resolver, computes LIVE_COUNT via worktree-porcelain,
#      defers via SPRINT_REPORT.md when at/over cap.
#   6. SKILL.md clarifies the two-cap distinction (per-message I/O cap
#      vs sprint-wide aggregate cap).
#   7. Behavioural — the porcelain grep regex matches BOTH PR-mode
#      (fix/issue-NNN) and cherry-pick-mode (fix-issue-NNN) branch shapes.
#   8. Mirror parity — source SKILL.md and resolver = mirror copies.
#
# Run from repo root: bash tests/test-fix-issues-worktree-cap.sh

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCHEMA="$REPO_ROOT/config/zskills-config.schema.json"
HELPER="$REPO_ROOT/skills/update-zskills/scripts/zskills-resolve-config.sh"
MIRROR_HELPER="$REPO_ROOT/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
SKILL="$REPO_ROOT/skills/fix-issues/SKILL.md"
MIRROR_SKILL="$REPO_ROOT/.claude/skills/fix-issues/SKILL.md"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# --- Test 1: schema declares the field ---------------------------------------

echo "=== Test 1: schema declares execution.max_concurrent_worktrees ==="
if python3 -c '
import json, sys
schema = json.load(open(sys.argv[1]))
exec_props = schema["properties"]["execution"]["properties"]
mcw = exec_props.get("max_concurrent_worktrees")
assert mcw is not None, "field missing"
t = mcw.get("type")
assert t == "integer", "type=" + repr(t)
d = mcw.get("default")
assert d == 3, "default=" + repr(d)
m = mcw.get("minimum")
assert m == 1, "minimum=" + repr(m)
desc = mcw.get("description") or ""
assert len(desc) > 50, "description missing/short (len=" + str(len(desc)) + ")"
' "$SCHEMA" 2>/tmp/test-295-schema.err; then
  pass "Test 1: schema field present (type=integer, default=3, minimum=1, description)"
else
  fail "Test 1: schema field declaration" "$(cat /tmp/test-295-schema.err)"
fi
rm -f /tmp/test-295-schema.err

# --- Test 2: resolver default (field absent) --------------------------------

echo ""
echo "=== Test 2: resolver default — field absent yields cap=3 ==="
T2=$(mktemp -d /tmp/zskills-cap-t2-XXXXXX)
mkdir -p "$T2/.claude"
cat > "$T2/.claude/zskills-config.json" <<'CFG'
{ "timezone": "UTC", "execution": { "landing": "pr" } }
CFG

T2_CAP=$(
  CLAUDE_PROJECT_DIR="$T2" \
  bash -c '. "'"$HELPER"'" && printf "%s" "$ZSKILLS_MAX_CONCURRENT_WORKTREES"'
)
if [ "$T2_CAP" = "3" ]; then
  pass "Test 2: \$ZSKILLS_MAX_CONCURRENT_WORKTREES = 3 when field absent"
else
  fail "Test 2: default when field absent" "got '$T2_CAP'"
fi
rm -rf "$T2"

# --- Test 3: resolver picks up explicit override ----------------------------

echo ""
echo "=== Test 3: resolver picks up execution.max_concurrent_worktrees override ==="
T3=$(mktemp -d /tmp/zskills-cap-t3-XXXXXX)
mkdir -p "$T3/.claude"
cat > "$T3/.claude/zskills-config.json" <<'CFG'
{
  "execution": {
    "landing": "pr",
    "max_concurrent_worktrees": 5
  }
}
CFG

T3_CAP=$(
  CLAUDE_PROJECT_DIR="$T3" \
  bash -c '. "'"$HELPER"'" && printf "%s" "$ZSKILLS_MAX_CONCURRENT_WORKTREES"'
)
if [ "$T3_CAP" = "5" ]; then
  pass "Test 3: \$ZSKILLS_MAX_CONCURRENT_WORKTREES = 5 (override applied)"
else
  fail "Test 3: override applied" "got '$T3_CAP'"
fi

# Test 3b: cap=1 (lower-edge valid value).
cat > "$T3/.claude/zskills-config.json" <<'CFG'
{ "execution": { "max_concurrent_worktrees": 1 } }
CFG
T3B_CAP=$(
  CLAUDE_PROJECT_DIR="$T3" \
  bash -c '. "'"$HELPER"'" && printf "%s" "$ZSKILLS_MAX_CONCURRENT_WORKTREES"'
)
if [ "$T3B_CAP" = "1" ]; then
  pass "Test 3b: \$ZSKILLS_MAX_CONCURRENT_WORKTREES = 1 (lower-edge valid value)"
else
  fail "Test 3b: cap=1" "got '$T3B_CAP'"
fi
rm -rf "$T3"

# --- Test 4: resolver guards bogus values -----------------------------------

echo ""
echo "=== Test 4: resolver guards bogus values — falls back to default 3 ==="
T4=$(mktemp -d /tmp/zskills-cap-t4-XXXXXX)
mkdir -p "$T4/.claude"

# 4a: string value — regex requires [0-9]+, so doesn't match → default.
cat > "$T4/.claude/zskills-config.json" <<'CFG'
{ "execution": { "max_concurrent_worktrees": "five" } }
CFG
T4A_CAP=$(
  CLAUDE_PROJECT_DIR="$T4" \
  bash -c '. "'"$HELPER"'" && printf "%s" "$ZSKILLS_MAX_CONCURRENT_WORKTREES"'
)
if [ "$T4A_CAP" = "3" ]; then
  pass "Test 4a: string value 'five' → fallback default 3"
else
  fail "Test 4a: string value fallback" "got '$T4A_CAP'"
fi

# 4b: value 0 — matched by [0-9]+ but rejected by ">=1" check → default.
cat > "$T4/.claude/zskills-config.json" <<'CFG'
{ "execution": { "max_concurrent_worktrees": 0 } }
CFG
T4B_CAP=$(
  CLAUDE_PROJECT_DIR="$T4" \
  bash -c '. "'"$HELPER"'" && printf "%s" "$ZSKILLS_MAX_CONCURRENT_WORKTREES"'
)
if [ "$T4B_CAP" = "3" ]; then
  pass "Test 4b: value 0 → guarded, default 3"
else
  fail "Test 4b: value 0 guarded" "got '$T4B_CAP'"
fi

# 4c: malformed config (broken JSON) → resolver still defaults to 3, no abort.
cat > "$T4/.claude/zskills-config.json" <<'BROKEN'
{ "execution": broken
BROKEN
T4C_CAP=$(
  CLAUDE_PROJECT_DIR="$T4" \
  bash -c '. "'"$HELPER"'" && printf "%s" "$ZSKILLS_MAX_CONCURRENT_WORKTREES"'
)
T4C_RC=$?
if [ "$T4C_CAP" = "3" ] && [ "$T4C_RC" = "0" ]; then
  pass "Test 4c: malformed config → default 3, no abort"
else
  fail "Test 4c: malformed config" "cap=$T4C_CAP rc=$T4C_RC"
fi
rm -rf "$T4"

# --- Test 5: SKILL.md Phase 3 has the gate ----------------------------------

echo ""
echo "=== Test 5: SKILL.md Phase 3 contains 'Live worktree count check' gate ==="

if grep -qF 'Live worktree count check' "$SKILL"; then
  pass "Test 5a: 'Live worktree count check' subsection present"
else
  fail "Test 5a: 'Live worktree count check' subsection present" "not found"
fi

# The gate must source the resolver, compute LIVE_COUNT, and reference the
# cap env var. Three regression-grep guards (loose substring matches —
# stable against prose tweaks but anchored to the load-bearing literals).
if grep -qF 'ZSKILLS_MAX_CONCURRENT_WORKTREES' "$SKILL"; then
  pass "Test 5b: gate references \$ZSKILLS_MAX_CONCURRENT_WORKTREES"
else
  fail "Test 5b: gate references env var" "not found"
fi
if grep -qF 'git worktree list --porcelain' "$SKILL"; then
  pass "Test 5c: gate uses git worktree list --porcelain for live count"
else
  fail "Test 5c: gate uses worktree porcelain" "not found"
fi
if grep -qF 'branch refs/heads/fix[/-]issue-' "$SKILL"; then
  pass "Test 5d: gate regex matches both fix/issue-NNN and fix-issue-NNN"
else
  fail "Test 5d: gate regex" "not found"
fi

# Deferral path must append to SPRINT_REPORT.md (auditable) — match the
# section heading literal.
if grep -qF 'Sprint deferred — at live-worktree cap' "$SKILL"; then
  pass "Test 5e: defer-all path writes auditable section to SPRINT_REPORT.md"
else
  fail "Test 5e: defer-all SPRINT_REPORT.md write" "not found"
fi
if grep -qF 'Sprint partially deferred — at live-worktree cap' "$SKILL"; then
  pass "Test 5f: partial-defer path writes auditable section to SPRINT_REPORT.md"
else
  fail "Test 5f: partial-defer SPRINT_REPORT.md write" "not found"
fi

# --- Test 6: two-cap distinction documented ---------------------------------

echo ""
echo "=== Test 6: two-cap distinction clarified ==="

if grep -qiF 'per-message dispatch i/o contention cap' "$SKILL"; then
  pass "Test 6a: 'per-message dispatch I/O contention cap' label present"
else
  fail "Test 6a: per-message I/O cap label" "not found"
fi
if grep -qiF 'aggregate live-worktree cap' "$SKILL"; then
  pass "Test 6b: 'aggregate live-worktree cap' label present"
else
  fail "Test 6b: aggregate cap label" "not found"
fi

# --- Test 7: behavioural — live-count regex matches both branch shapes ------

echo ""
echo "=== Test 7: live-count regex matches both fix/issue-NNN and fix-issue-NNN ==="
# We synthesize a `git worktree list --porcelain` blob containing both
# shapes and assert the regex used in SKILL.md counts both. This catches
# any future "simplification" that breaks one of the shapes.

PORCELAIN_FIXTURE=$(cat <<'EOF'
worktree /tmp/proj
HEAD aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
branch refs/heads/main

worktree /tmp/proj-fix-issue-42
HEAD bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
branch refs/heads/fix-issue-42

worktree /tmp/proj-fix-issue-43
HEAD cccccccccccccccccccccccccccccccccccccccc
branch refs/heads/fix/issue-43

worktree /tmp/unrelated
HEAD dddddddddddddddddddddddddddddddddddddddd
branch refs/heads/feat/something
EOF
)

LIVE=$(printf '%s\n' "$PORCELAIN_FIXTURE" | grep -cE '^branch refs/heads/fix[/-]issue-')
if [ "$LIVE" = "2" ]; then
  pass "Test 7: regex counts BOTH fix/issue-43 AND fix-issue-42, excludes main+feat (count=2)"
else
  fail "Test 7: regex counts" "expected 2, got $LIVE"
fi

# --- Test 8: Mirror parity --------------------------------------------------

echo ""
echo "=== Test 8: mirror parity ==="

if diff -q "$SKILL" "$MIRROR_SKILL" > /dev/null 2>&1; then
  pass "Test 8a: skills/fix-issues/SKILL.md matches .claude/ mirror"
else
  fail "Test 8a: SKILL.md mirror parity" "diff between source and .claude/ mirror"
fi
if diff -q "$HELPER" "$MIRROR_HELPER" > /dev/null 2>&1; then
  pass "Test 8b: zskills-resolve-config.sh matches .claude/ mirror"
else
  fail "Test 8b: resolver mirror parity" "diff between source and .claude/ mirror"
fi

# --- Summary ---------------------------------------------------------------
echo ""
echo "---"
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (of %d)\033[0m\n' "$PASS_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (of %d)\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit 1
fi
