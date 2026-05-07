#!/bin/bash
# tests/test-skill-version-enforcement.sh — Phase 4 enforcement tests.
#
# 12 hook test cases (hooks/warn-config-drift.sh Branch 3) +
# 8 stage-check test cases (scripts/skill-version-stage-check.sh).
# Each case creates a sandbox git repo under
# /tmp/zskills-tests/<basename>/skill-version-enforcement-cases/<N>/
# and asserts the expected stderr signal / exit code.
#
# Run from repo root:
#   bash tests/test-skill-version-enforcement.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/hooks/warn-config-drift.sh"
STAGE_CHECK="$REPO_ROOT/scripts/skill-version-stage-check.sh"
HASH_HELPER="$REPO_ROOT/scripts/skill-content-hash.sh"
SET_HELPER="$REPO_ROOT/scripts/frontmatter-set.sh"

WORK_BASE="/tmp/zskills-tests/$(basename "$REPO_ROOT")/skill-version-enforcement-cases"
rm -rf "$WORK_BASE"
mkdir -p "$WORK_BASE"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# ----------------------------------------------------------------------
# Sandbox factory.
# ----------------------------------------------------------------------
#
# Creates a sandbox git repo with one skill `skills/foo/SKILL.md` whose
# initial metadata.version reflects the actual content hash. Returns the
# sandbox root via stdout. Caller can then mutate files, stage, and
# invoke the hook or stage-check.
#
# The sandbox copies the helper scripts so $REPO_ROOT inside the sandbox
# resolves to the sandbox itself (CLAUDE_PROJECT_DIR is the sandbox).

make_sandbox() {
  local case_no="$1"
  local sandbox="$WORK_BASE/$case_no"
  mkdir -p "$sandbox/scripts" "$sandbox/skills/foo/modes" "$sandbox/.claude/skills/update-zskills/scripts"

  # Copy helpers — bare scripts/ + the resolver.
  cp "$REPO_ROOT/scripts/frontmatter-get.sh" "$sandbox/scripts/"
  cp "$REPO_ROOT/scripts/frontmatter-set.sh" "$sandbox/scripts/"
  cp "$REPO_ROOT/scripts/skill-content-hash.sh" "$sandbox/scripts/"
  cp "$REPO_ROOT/scripts/skill-version-stage-check.sh" "$sandbox/scripts/"
  chmod +x "$sandbox/scripts/"*.sh
  cp "$REPO_ROOT/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh" \
     "$sandbox/.claude/skills/update-zskills/scripts/"

  # Initial SKILL.md with placeholder version. We bump it to the real
  # hash after the first hash compute.
  cat > "$sandbox/skills/foo/SKILL.md" <<'EOF'
---
name: foo
description: A test skill
metadata:
  version: "2026.01.01+000000"
---

# foo

Body content of foo.
EOF

  cat > "$sandbox/skills/foo/modes/extra.md" <<'EOF'
# extra mode

Some text.
EOF

  # Compute true hash and update version.
  local h
  h=$(bash "$sandbox/scripts/skill-content-hash.sh" "$sandbox/skills/foo")
  bash "$sandbox/scripts/frontmatter-set.sh" \
    "$sandbox/skills/foo/SKILL.md" metadata.version "2026.05.02+$h"

  # Init git.
  (
    cd "$sandbox"
    git init -q
    git config user.email "test@test.test"
    git config user.name "test"
    git add -A
    git commit -q -m "initial"
  )

  printf '%s' "$sandbox"
}

# Run the hook with a synthetic Edit envelope, capturing stderr.
# Args: <sandbox> <file_path>
# Echoes captured stderr via stdout.
run_hook() {
  local sandbox="$1" fp="$2"
  local input
  input=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$fp")
  # Capture stderr (the WARN channel); discard stdout. Env var must
  # apply to `bash` (not just printf), so use a subshell.
  (
    export CLAUDE_PROJECT_DIR="$sandbox"
    printf '%s' "$input" | bash "$HOOK" 2>&1 >/dev/null
  )
}

# Run stage-check; echo exit code; stderr forwarded to caller stderr.
run_stage_check() {
  local sandbox="$1"
  (
    cd "$sandbox"
    CLAUDE_PROJECT_DIR="$sandbox" bash "$STAGE_CHECK"
  )
}

# Recompute and bump version inline.
bump_version() {
  local sandbox="$1"
  local h
  h=$(bash "$sandbox/scripts/skill-content-hash.sh" "$sandbox/skills/foo")
  bash "$sandbox/scripts/frontmatter-set.sh" \
    "$sandbox/skills/foo/SKILL.md" metadata.version "2026.05.02+$h"
}

# ----------------------------------------------------------------------
# HOOK TESTS — Branch 3 of warn-config-drift.sh.
# ----------------------------------------------------------------------

echo "=== Hook tests (Branch 3) ==="

# Case 1: edit SKILL.md body, stage it, no version bump → asymmetric WARN.
case_no=1
sandbox=$(make_sandbox "$case_no")
echo "Edited body line." >> "$sandbox/skills/foo/SKILL.md"
(cd "$sandbox" && git add skills/foo/SKILL.md)
output=$(run_hook "$sandbox" "$sandbox/skills/foo/SKILL.md")
if [[ "$output" == *"WARN:"* ]] && [[ "$output" == *"content changed"* ]]; then
  pass "case 1: edit + stage without bump → asymmetric WARN"
else
  fail "case 1: expected WARN with 'content changed', got: $output"
fi

# Case 2: edit SKILL.md body, bump version, stage both → silent.
case_no=2
sandbox=$(make_sandbox "$case_no")
echo "Edited body line." >> "$sandbox/skills/foo/SKILL.md"
bump_version "$sandbox"
(cd "$sandbox" && git add skills/foo/SKILL.md)
output=$(run_hook "$sandbox" "$sandbox/skills/foo/SKILL.md")
if [[ -z "$output" ]]; then
  pass "case 2: edit + bump + stage → silent"
else
  fail "case 2: expected silent, got: $output"
fi

# Case 3: revert content but version-bumped only → symmetric WARN.
# Set up: commit a real edit + bump first to advance HEAD; then revert
# the body (back to HEAD's content) but leave a new bump. Hook should
# detect cur_hash == head_hash AND on_disk_ver != head_ver.
case_no=3
sandbox=$(make_sandbox "$case_no")
# First, commit a real edit so HEAD moves.
echo "Real edit." >> "$sandbox/skills/foo/SKILL.md"
bump_version "$sandbox"
real_ver_after=$(bash "$sandbox/scripts/frontmatter-get.sh" "$sandbox/skills/foo/SKILL.md" metadata.version)
(cd "$sandbox" && git add -A && git commit -q -m "real edit")
# Now: revert the body to HEAD's content via git checkout, then bump
# the version line only (synthetic no-op).
git -C "$sandbox" checkout HEAD -- skills/foo/SKILL.md
# Manually rewrite version to a fake new value (different from HEAD's).
bash "$sandbox/scripts/frontmatter-set.sh" \
  "$sandbox/skills/foo/SKILL.md" metadata.version "2026.05.02+deadbe"
(cd "$sandbox" && git add skills/foo/SKILL.md)
output=$(run_hook "$sandbox" "$sandbox/skills/foo/SKILL.md")
if [[ "$output" == *"WARN:"* ]] && [[ "$output" == *"content unchanged"* ]]; then
  pass "case 3: revert-with-bump-only → symmetric WARN"
else
  fail "case 3: expected symmetric WARN with 'content unchanged', got: $output"
fi

# Case 4: whitespace-only edit → silent (projection identical).
case_no=4
sandbox=$(make_sandbox "$case_no")
# Append trailing whitespace to a body line — the projection's per-file
# normalisation strips trailing whitespace, so hash is unchanged.
sed -i 's/Body content of foo./Body content of foo.   /' "$sandbox/skills/foo/SKILL.md"
(cd "$sandbox" && git add skills/foo/SKILL.md)
output=$(run_hook "$sandbox" "$sandbox/skills/foo/SKILL.md")
if [[ -z "$output" ]]; then
  pass "case 4: whitespace-only edit → silent"
else
  fail "case 4: expected silent (projection unchanged), got: $output"
fi

# Case 5: brand-new file under skills/foo (not present in HEAD originally
# — we add a brand-new skills/bar/SKILL.md) → silent (no HEAD blob, the
# version line equals what's on disk so on_disk_ver == head_ver == "" is
# false but stored_hash already equals cur_hash for this fresh skill).
# Specifically: a brand-new skill with valid version where HEAD has no
# entry — on_disk_ver is set, head_ver is "" → on_disk_ver != head_ver,
# so neither asymmetric (requires on_disk_ver == head_ver) nor symmetric
# (requires cur_hash == head_hash, but head_hash is "") fires unless
# cur_hash happens to equal "". → silent.
case_no=5
sandbox=$(make_sandbox "$case_no")
mkdir -p "$sandbox/skills/bar"
cat > "$sandbox/skills/bar/SKILL.md" <<'EOF'
---
name: bar
metadata:
  version: "2026.01.01+000000"
---

# bar
EOF
h=$(bash "$sandbox/scripts/skill-content-hash.sh" "$sandbox/skills/bar")
bash "$sandbox/scripts/frontmatter-set.sh" "$sandbox/skills/bar/SKILL.md" metadata.version "2026.05.02+$h"
(cd "$sandbox" && git add skills/bar/SKILL.md)
output=$(run_hook "$sandbox" "$sandbox/skills/bar/SKILL.md")
if [[ -z "$output" ]]; then
  pass "case 5: brand-new skill → silent (no HEAD)"
else
  fail "case 5: expected silent (no HEAD blob), got: $output"
fi

# Case 6: helper missing → silent (graceful no-op).
case_no=6
sandbox=$(make_sandbox "$case_no")
chmod -x "$sandbox/scripts/skill-content-hash.sh"
echo "Edited body line." >> "$sandbox/skills/foo/SKILL.md"
(cd "$sandbox" && git add skills/foo/SKILL.md)
output=$(run_hook "$sandbox" "$sandbox/skills/foo/SKILL.md")
chmod +x "$sandbox/scripts/skill-content-hash.sh"
if [[ -z "$output" ]]; then
  pass "case 6: helper missing → silent (graceful)"
else
  fail "case 6: expected silent (helper missing), got: $output"
fi

# Case 7: HEAD missing version (initial migration). We construct a HEAD
# state where SKILL.md exists but has no metadata.version, then add it
# in the worktree. Hook should NOT warn (head_ver == "", so the
# asymmetric "on_disk_ver == head_ver" branch evaluates to false unless
# on_disk_ver is also "" — it isn't).
case_no=7
sandbox=$(make_sandbox "$case_no")
# Rewrite HEAD's SKILL.md to remove metadata block, then commit.
cat > "$sandbox/skills/foo/SKILL.md" <<'EOF'
---
name: foo
description: A test skill
---

# foo

Body content of foo.
EOF
(cd "$sandbox" && git add -A && git commit -q -m "remove version")
# Now reintroduce metadata.version on disk.
cat > "$sandbox/skills/foo/SKILL.md" <<'EOF'
---
name: foo
description: A test skill
metadata:
  version: "2026.05.02+abcdef"
---

# foo

Body content of foo.
EOF
h=$(bash "$sandbox/scripts/skill-content-hash.sh" "$sandbox/skills/foo")
bash "$sandbox/scripts/frontmatter-set.sh" "$sandbox/skills/foo/SKILL.md" metadata.version "2026.05.02+$h"
(cd "$sandbox" && git add skills/foo/SKILL.md)
output=$(run_hook "$sandbox" "$sandbox/skills/foo/SKILL.md")
if [[ -z "$output" ]]; then
  pass "case 7: HEAD missing version → silent (first migration)"
else
  fail "case 7: expected silent, got: $output"
fi

# Case 8: body diff with version line untouched → asymmetric WARN
# (same as case 1 phrased differently — edit body via different
# mechanism than 'echo append').
case_no=8
sandbox=$(make_sandbox "$case_no")
sed -i 's/Body content of foo./Body content of foo. EXTRA TEXT./' "$sandbox/skills/foo/SKILL.md"
(cd "$sandbox" && git add skills/foo/SKILL.md)
output=$(run_hook "$sandbox" "$sandbox/skills/foo/SKILL.md")
if [[ "$output" == *"WARN:"* ]] && [[ "$output" == *"content changed"* ]]; then
  pass "case 8: body-diff via sed without bump → asymmetric WARN"
else
  fail "case 8: expected WARN, got: $output"
fi

# Case 9: edit a child file under modes/ WITHOUT staging it → silent
# (staged-file gate).
case_no=9
sandbox=$(make_sandbox "$case_no")
echo "Modified modes content." >> "$sandbox/skills/foo/modes/extra.md"
# DO NOT stage.
output=$(run_hook "$sandbox" "$sandbox/skills/foo/modes/extra.md")
if [[ -z "$output" ]]; then
  pass "case 9: child file edited but not staged → silent (gate)"
else
  fail "case 9: expected silent, got: $output"
fi

# Case 10: edit a child file under modes/ AND stage it without bumping
# parent SKILL.md → WARN referencing parent SKILL.md.
case_no=10
sandbox=$(make_sandbox "$case_no")
echo "Modified modes content." >> "$sandbox/skills/foo/modes/extra.md"
(cd "$sandbox" && git add skills/foo/modes/extra.md)
output=$(run_hook "$sandbox" "$sandbox/skills/foo/modes/extra.md")
if [[ "$output" == *"WARN:"* ]] && [[ "$output" == *"skills/foo/SKILL.md"* ]] \
   && [[ "$output" == *"content changed"* ]]; then
  pass "case 10: child edit staged → WARN referencing parent SKILL.md"
else
  fail "case 10: expected WARN naming parent SKILL.md, got: $output"
fi

# Case 11: $FILE_PATH fed as ABSOLUTE path → same outcome as case 1.
case_no=11
sandbox=$(make_sandbox "$case_no")
echo "Edited body." >> "$sandbox/skills/foo/SKILL.md"
(cd "$sandbox" && git add skills/foo/SKILL.md)
abs_path="$sandbox/skills/foo/SKILL.md"
output=$(run_hook "$sandbox" "$abs_path")
if [[ "$output" == *"WARN:"* ]] && [[ "$output" == *"content changed"* ]]; then
  pass "case 11: absolute \$FILE_PATH normalises and warns"
else
  fail "case 11: expected WARN, got: $output"
fi

# Case 12: $FILE_PATH fed as REPO-RELATIVE → same outcome.
case_no=12
sandbox=$(make_sandbox "$case_no")
echo "Edited body." >> "$sandbox/skills/foo/SKILL.md"
(cd "$sandbox" && git add skills/foo/SKILL.md)
rel_path="skills/foo/SKILL.md"
output=$(run_hook "$sandbox" "$rel_path")
if [[ "$output" == *"WARN:"* ]] && [[ "$output" == *"content changed"* ]]; then
  pass "case 12: repo-relative \$FILE_PATH normalises and warns"
else
  fail "case 12: expected WARN, got: $output"
fi

# ----------------------------------------------------------------------
# STAGE-CHECK TESTS — scripts/skill-version-stage-check.sh.
# ----------------------------------------------------------------------

echo ""
echo "=== Stage-check tests ==="

# Case 13 (s1): body change staged without version bump → exit 1, STOP.
case_no=13
sandbox=$(make_sandbox "$case_no")
echo "Body edit." >> "$sandbox/skills/foo/SKILL.md"
(cd "$sandbox" && git add skills/foo/SKILL.md)
err=$(run_stage_check "$sandbox" 2>&1)
ec=$?
if [ "$ec" -ne 0 ] && [[ "$err" == *"STOP:"* ]]; then
  pass "case 13: body change without bump → exit 1 + STOP"
else
  fail "case 13: expected exit 1 + STOP, got exit=$ec err=$err"
fi

# Case 14 (s2): body change WITH bump staged → exit 0.
case_no=14
sandbox=$(make_sandbox "$case_no")
echo "Body edit." >> "$sandbox/skills/foo/SKILL.md"
bump_version "$sandbox"
(cd "$sandbox" && git add skills/foo/SKILL.md)
err=$(run_stage_check "$sandbox" 2>&1)
ec=$?
if [ "$ec" -eq 0 ] && [[ -z "$err" ]]; then
  pass "case 14: body change with bump → exit 0 silent"
else
  fail "case 14: expected exit 0 silent, got exit=$ec err=$err"
fi

# Case 15 (s3): only version line changed but content unchanged →
# symmetric STOP.
case_no=15
sandbox=$(make_sandbox "$case_no")
bash "$sandbox/scripts/frontmatter-set.sh" \
  "$sandbox/skills/foo/SKILL.md" metadata.version "2026.05.02+deadbe"
(cd "$sandbox" && git add skills/foo/SKILL.md)
err=$(run_stage_check "$sandbox" 2>&1)
ec=$?
if [ "$ec" -ne 0 ] && [[ "$err" == *"STOP:"* ]] && [[ "$err" == *"content unchanged"* ]]; then
  pass "case 15: bump-only without content change → exit 1 + symmetric STOP"
else
  fail "case 15: expected exit 1 + symmetric STOP, got exit=$ec err=$err"
fi

# Case 16 (s4): no skill files staged → exit 0.
case_no=16
sandbox=$(make_sandbox "$case_no")
mkdir -p "$sandbox/other"
echo "unrelated" > "$sandbox/other/file.txt"
(cd "$sandbox" && git add other/file.txt)
err=$(run_stage_check "$sandbox" 2>&1)
ec=$?
if [ "$ec" -eq 0 ] && [[ -z "$err" ]]; then
  pass "case 16: no skill files staged → exit 0 silent"
else
  fail "case 16: expected exit 0, got exit=$ec err=$err"
fi

# Case 17 (s5): child file under modes/ staged without parent bump → exit 1.
case_no=17
sandbox=$(make_sandbox "$case_no")
echo "child mode edit" >> "$sandbox/skills/foo/modes/extra.md"
(cd "$sandbox" && git add skills/foo/modes/extra.md)
err=$(run_stage_check "$sandbox" 2>&1)
ec=$?
if [ "$ec" -ne 0 ] && [[ "$err" == *"STOP:"* ]] && [[ "$err" == *"skills/foo"* ]]; then
  pass "case 17: child file staged without parent bump → exit 1 + STOP"
else
  fail "case 17: expected exit 1 + STOP naming skills/foo, got exit=$ec err=$err"
fi

# Case 18 (s6): child file staged WITH parent SKILL.md bump → exit 0.
case_no=18
sandbox=$(make_sandbox "$case_no")
echo "child mode edit" >> "$sandbox/skills/foo/modes/extra.md"
bump_version "$sandbox"
(cd "$sandbox" && git add skills/foo/modes/extra.md skills/foo/SKILL.md)
err=$(run_stage_check "$sandbox" 2>&1)
ec=$?
if [ "$ec" -eq 0 ] && [[ -z "$err" ]]; then
  pass "case 18: child + parent bump staged → exit 0"
else
  fail "case 18: expected exit 0, got exit=$ec err=$err"
fi

# Case 19 (s7): block-diagram skill body change without bump → exit 1.
case_no=19
sandbox=$(make_sandbox "$case_no")
mkdir -p "$sandbox/block-diagram/baz"
cat > "$sandbox/block-diagram/baz/SKILL.md" <<'EOF'
---
name: baz
metadata:
  version: "2026.01.01+000000"
---

# baz body
EOF
h=$(bash "$sandbox/scripts/skill-content-hash.sh" "$sandbox/block-diagram/baz")
bash "$sandbox/scripts/frontmatter-set.sh" \
  "$sandbox/block-diagram/baz/SKILL.md" metadata.version "2026.05.02+$h"
(cd "$sandbox" && git add -A && git commit -q -m "add baz")
echo "edit baz body" >> "$sandbox/block-diagram/baz/SKILL.md"
(cd "$sandbox" && git add block-diagram/baz/SKILL.md)
err=$(run_stage_check "$sandbox" 2>&1)
ec=$?
if [ "$ec" -ne 0 ] && [[ "$err" == *"STOP:"* ]] && [[ "$err" == *"block-diagram/baz"* ]]; then
  pass "case 19: block-diagram skill body change → exit 1 + STOP"
else
  fail "case 19: expected exit 1 naming block-diagram/baz, got exit=$ec err=$err"
fi

# Case 20 (s8): two affected skills, ONE bumped ONE not → exit 1
# listing the unbumped one only.
case_no=20
sandbox=$(make_sandbox "$case_no")
mkdir -p "$sandbox/skills/bar"
cat > "$sandbox/skills/bar/SKILL.md" <<'EOF'
---
name: bar
metadata:
  version: "2026.01.01+000000"
---

# bar body
EOF
h=$(bash "$sandbox/scripts/skill-content-hash.sh" "$sandbox/skills/bar")
bash "$sandbox/scripts/frontmatter-set.sh" "$sandbox/skills/bar/SKILL.md" metadata.version "2026.05.02+$h"
(cd "$sandbox" && git add -A && git commit -q -m "add bar")
# Edit foo + bump foo. Edit bar but DO NOT bump bar.
echo "foo body edit" >> "$sandbox/skills/foo/SKILL.md"
bump_version "$sandbox"
echo "bar body edit" >> "$sandbox/skills/bar/SKILL.md"
(cd "$sandbox" && git add skills/foo/SKILL.md skills/bar/SKILL.md)
err=$(run_stage_check "$sandbox" 2>&1)
ec=$?
if [ "$ec" -ne 0 ] && [[ "$err" == *"STOP:"* ]] && [[ "$err" == *"skills/bar"* ]] \
   && [[ "$err" != *"skills/foo:"* ]]; then
  pass "case 20: mixed bumps → exit 1 listing only unbumped skill"
else
  fail "case 20: expected exit 1 with skills/bar but not skills/foo, got exit=$ec err=$err"
fi

# Case 21 (s9): body edited and STAGED without bump (case (a) from
# issue #194) → STOP without "(SKILL.md not staged — git add it)" hint.
case_no=21
sandbox=$(make_sandbox "$case_no")
echo "Body edit." >> "$sandbox/skills/foo/SKILL.md"
(cd "$sandbox" && git add skills/foo/SKILL.md)
err=$(run_stage_check "$sandbox" 2>&1)
ec=$?
if [ "$ec" -ne 0 ] && [[ "$err" == *"STOP:"* ]] && [[ "$err" != *"not staged"* ]]; then
  pass "case 21: edited+staged without bump → STOP without 'not staged' hint"
else
  fail "case 21: expected STOP without 'not staged' hint, got exit=$ec err=$err"
fi

# Case 22 (s10): body edited AND staged, SKILL.md bumped on disk but
# bump NOT re-staged (case (b) from issue #194) → STOP WITH
# "(SKILL.md not staged — git add it)" hint.
#
# Repro: stage the body edit (with old version), then bump version on
# disk WITHOUT re-staging. staged_blob carries old version; on_disk_ver
# carries new version. Asymmetric branch fires; hint should appear.
case_no=22
sandbox=$(make_sandbox "$case_no")
# Step 1: edit body and stage it (with old version still in place).
echo "Body edit." >> "$sandbox/skills/foo/SKILL.md"
(cd "$sandbox" && git add skills/foo/SKILL.md)
# Step 2: bump version on disk only — DO NOT re-stage.
bump_version "$sandbox"
err=$(run_stage_check "$sandbox" 2>&1)
ec=$?
if [ "$ec" -ne 0 ] && [[ "$err" == *"STOP:"* ]] \
   && [[ "$err" == *"SKILL.md not staged — git add it"* ]]; then
  pass "case 22: bump on disk but not re-staged → STOP with 'not staged' hint"
else
  fail "case 22: expected STOP with 'not staged' hint, got exit=$ec err=$err"
fi

# ----------------------------------------------------------------------
# Summary.
# ----------------------------------------------------------------------

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
