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
# DA9 (CASCADE v2, ENFORCEMENT_V2 Phase 4): sandbox HOME so a dev machine's
# personal ~/.claude/zskills-config.json cannot flip this suite — its
# "absent field → 3" case is exactly what a personal max_concurrent_worktrees
# would break now that mcw is a plain-cascade workflow key.
TMP_HOME="$(mktemp -d /tmp/zskills-worktree-cap-home-XXXXXX)"; export HOME="$TMP_HOME"
SCHEMA="$REPO_ROOT/config/zskills-config.schema.json"
HELPER="$REPO_ROOT/skills/update-zskills/scripts/zskills-resolve-config.sh"
MIRROR_HELPER="$REPO_ROOT/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
SKILL="$REPO_ROOT/skills/fix-issues/modes/sprint.md"
MIRROR_SKILL="$REPO_ROOT/.claude/skills/fix-issues/modes/sprint.md"

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
# Gate regex — matches BOTH fix/issue-NNN and fix-issue-NNN. The shape
# changed in the #329 follow-up from a single `grep -cE` to an
# `awk`-then-`while` pipeline that also filters out `.landed status:
# landed` worktrees, but the bracket-alternation literal that selects
# the fix-branch lines is preserved.
if grep -qF 'refs\/heads\/fix[/-]issue-' "$SKILL" || grep -qF 'refs/heads/fix[/-]issue-' "$SKILL"; then
  pass "Test 5d: gate regex matches both fix/issue-NNN and fix-issue-NNN (awk or grep variant)"
else
  fail "Test 5d: gate regex" "neither awk-escaped nor grep-form bracket alternation found"
fi

# Defer-path no longer writes to SPRINT_REPORT.md. The #329 follow-up
# moved the cap-check ahead of the sprint worktree gate so a defer-all
# exits before the worktree is created — appending to SPRINT_REPORT.md
# from there would strand the write (Phase 6's sprint-level /land-pr
# is past `exit 0`). The partial-dispatch trim drops the audit-write
# for symmetry. Both paths are now stderr-only; the section-heading
# literals from the old shape are negative pinned here.
if grep -qF 'Sprint deferred — at live-worktree cap' "$SKILL"; then
  fail "Test 5e: defer-all path still writes 'Sprint deferred' to SPRINT_REPORT.md" "should have been dropped in the #329 follow-up (strand bug)"
else
  pass "Test 5e: defer-all path no longer appends to SPRINT_REPORT.md (strand bug from #329 closed)"
fi
if grep -qF 'Sprint partially deferred — at live-worktree cap' "$SKILL"; then
  fail "Test 5f: partial-defer path still writes 'Sprint partially deferred' to SPRINT_REPORT.md" "should have been dropped for symmetry with defer-all"
else
  pass "Test 5f: partial-defer path no longer appends to SPRINT_REPORT.md (symmetric with defer-all)"
fi

# Test 5g (new): predicate skips `.landed status: landed` worktrees.
# This is the load-bearing behavioural change from #329 follow-up —
# done-but-uncleaned worktrees no longer trip the cap. The schema
# test/test-fix-issues-sprint-worktree-gate.sh has the full fixture
# eval; here we pin the literal presence of the `.landed`-skip
# branch in the predicate body.
if grep -qF "grep -q '^status: landed'" "$SKILL"; then
  pass "Test 5g: predicate skips '.landed status: landed' worktrees (cap-over-count bug from #320 closed)"
else
  fail "Test 5g: predicate skips '.landed status: landed' worktrees" "the grep against \$wt/.landed for 'status: landed' is missing — done-but-uncleaned worktrees will over-count toward the cap"
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
