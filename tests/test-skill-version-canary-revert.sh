#!/bin/bash
# tests/test-skill-version-canary-revert.sh — Phase 6.4 canary.
#
# Closes two failure modes from plans/SKILL_VERSIONING.md:
#
#   §1.1 multi-edit-day (was F-DA1):
#     Two distinct edits on the same calendar day, each correctly
#     bumping `metadata.version`. Because the hash suffix differs, the
#     hook predicates `on_disk_ver != head_ver` (asymmetric warn
#     skipped) AND `cur_hash != head_hash` (symmetric warn skipped)
#     both fall through. Hook is silent; stage-check exits 0. Pure
#     CalVer would emit a false positive on the second same-day edit
#     because `on_disk_ver == head_ver` despite content drift.
#
#   §1.3 revert / no-op:
#     Edit body, bump version, then revert body change leaving the
#     bump in place. Hook emits `WARN: ... metadata.version bumped ...
#     but content unchanged`. Stage-check exits 1.
#
# Defensive sandbox guard: see canary-missed-bump.
#
# Run from repo root:
#   bash tests/test-skill-version-canary-revert.sh

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

run_hook() {
  local sandbox="$1" fp="$2"
  local input
  input=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$fp")
  printf '%s' "$input" | CLAUDE_PROJECT_DIR="$sandbox" bash "$HOOK" 2>&1 >/dev/null
}

run_stage_check() {
  local sandbox="$1"
  CLAUDE_PROJECT_DIR="$sandbox" bash "$STAGE_CHECK"
}

SANDBOX_ROOT=$(mktemp -d -t zskills-canary-revert-XXXXXX)
trap 'rm -rf "$SANDBOX_ROOT"' EXIT

# Sub-case A and Sub-case B each get an independent sandbox to keep
# state distinct.
SANDBOX_A="$SANDBOX_ROOT/multi-edit-day"
SANDBOX_B="$SANDBOX_ROOT/revert-noop"
git clone --quiet "$REPO_ROOT" "$SANDBOX_A"
git clone --quiet "$REPO_ROOT" "$SANDBOX_B"

echo "=== Phase 6.4 canary: revert + multi-edit-day ==="

# ---------------------------------------------------------------
# Sub-case A: multi-edit-day (silent path).
# ---------------------------------------------------------------
echo ""
echo "--- Sub-case A: multi-edit-day (F-DA1 closure) ---"

cd "$SANDBOX_A"
assert_outside_repo
git config user.email "canary@test.test"
git config user.name "canary"

REL_DIR="skills/run-plan"
REL_MD="$REL_DIR/SKILL.md"
[ -f "$REL_MD" ] || { echo "FAIL: missing $REL_MD" >&2; exit 1; }

TODAY=$(TZ=America/New_York date +%Y.%m.%d)

# Edit #1 on date D — make body change AAA + bump correctly.
echo "" >> "$REL_MD"
echo "AAA first same-day edit." >> "$REL_MD"
HASH_AAA=$(bash "$SANDBOX_A/scripts/skill-content-hash.sh" "$SANDBOX_A/$REL_DIR")
VER_AAA="$TODAY+$HASH_AAA"
bash "$SANDBOX_A/scripts/frontmatter-set.sh" "$REL_MD" metadata.version "$VER_AAA"
git add "$REL_MD"
git commit -q -m "first same-day edit"
HEAD_AFTER_FIRST=$(bash "$SANDBOX_A/scripts/frontmatter-get.sh" "$REL_MD" metadata.version)

# Edit #2 on SAME date D — make a DIFFERENT body change BBB + bump
# correctly to a new hash.
echo "" >> "$REL_MD"
echo "BBB second same-day edit." >> "$REL_MD"
HASH_BBB=$(bash "$SANDBOX_A/scripts/skill-content-hash.sh" "$SANDBOX_A/$REL_DIR")
VER_BBB="$TODAY+$HASH_BBB"
bash "$SANDBOX_A/scripts/frontmatter-set.sh" "$REL_MD" metadata.version "$VER_BBB"
git add "$REL_MD"

# Sanity: same date prefix, different hashes.
if [ "${VER_AAA%+*}" = "${VER_BBB%+*}" ] && [ "$HASH_AAA" != "$HASH_BBB" ]; then
  pass "A: two same-day edits produced same-date / different-hash versions"
else
  fail "A: expected same date and different hashes; AAA=$VER_AAA BBB=$VER_BBB"
fi

# Hook conditions on this state:
#   on_disk_ver = $VER_BBB, head_ver = $VER_AAA → on_disk_ver != head_ver
#   cur_hash    = $HASH_BBB, head_hash = $HASH_AAA → cur_hash != head_hash
# So neither asymmetric ("==" + "!=") nor symmetric ("!=" + "==")
# branch fires. Hook MUST be silent.
HOOK_OUT_A=$(run_hook "$SANDBOX_A" "$SANDBOX_A/$REL_MD")
# As with canary-correct-bump, allow unrelated WARNs (forbidden-literal
# scans on a real skill) and only assert version-drift WARNs are absent.
if [[ "$HOOK_OUT_A" != *"content changed"*"metadata.version unchanged"* ]] \
   && [[ "$HOOK_OUT_A" != *"content unchanged"* ]]; then
  pass "A: edit-time hook silent on version drift (multi-edit-day)"
else
  fail "A: hook unexpectedly emitted version-drift WARN; got: $HOOK_OUT_A"
fi

STAGE_OUT_A=$(run_stage_check "$SANDBOX_A" 2>&1)
STAGE_EC_A=$?
if [ "$STAGE_EC_A" -eq 0 ] && [[ -z "$STAGE_OUT_A" ]]; then
  pass "A: stage-check exits 0 silent (multi-edit-day)"
else
  fail "A: stage-check expected exit 0 silent; got exit=$STAGE_EC_A err=$STAGE_OUT_A"
fi

# ---------------------------------------------------------------
# Sub-case B: revert / no-op (symmetric WARN + STOP).
# ---------------------------------------------------------------
echo ""
echo "--- Sub-case B: revert / no-op (§1.3) ---"

cd "$SANDBOX_B"
assert_outside_repo
git config user.email "canary@test.test"
git config user.name "canary"

[ -f "$REL_MD" ] || { echo "FAIL: missing $REL_MD" >&2; exit 1; }
HEAD_VER_B=$(bash "$SANDBOX_B/scripts/frontmatter-get.sh" "$REL_MD" metadata.version)
HEAD_HASH_B="${HEAD_VER_B##*+}"

# Action: edit body, bump version, then revert body change leaving the
# version-line bump.
echo "" >> "$REL_MD"
echo "Body edit that will be reverted." >> "$REL_MD"
TODAY=$(TZ=America/New_York date +%Y.%m.%d)
H_INTERIM=$(bash "$SANDBOX_B/scripts/skill-content-hash.sh" "$SANDBOX_B/$REL_DIR")
VER_INTERIM="$TODAY+$H_INTERIM"
bash "$SANDBOX_B/scripts/frontmatter-set.sh" "$REL_MD" metadata.version "$VER_INTERIM"

# Now revert ONLY the body line (keep version bumped). Easiest: take
# HEAD's blob and overwrite, then re-apply the version bump.
git -C "$SANDBOX_B" show "HEAD:$REL_MD" > "$REL_MD"
bash "$SANDBOX_B/scripts/frontmatter-set.sh" "$REL_MD" metadata.version "$VER_INTERIM"

# Confirm: cur_hash == head_hash AND on_disk_ver != head_ver.
CUR_HASH_B=$(bash "$SANDBOX_B/scripts/skill-content-hash.sh" "$SANDBOX_B/$REL_DIR")
ON_DISK_B=$(bash "$SANDBOX_B/scripts/frontmatter-get.sh" "$REL_MD" metadata.version)
if [ "$CUR_HASH_B" = "$HEAD_HASH_B" ] && [ "$ON_DISK_B" != "$HEAD_VER_B" ]; then
  pass "B: state set up correctly (cur_hash==head_hash, on_disk_ver!=head_ver)"
else
  fail "B: setup state wrong; cur=$CUR_HASH_B head_hash=$HEAD_HASH_B on_disk=$ON_DISK_B head_ver=$HEAD_VER_B"
fi

git -C "$SANDBOX_B" add "$REL_MD"

# Hook MUST emit symmetric WARN.
HOOK_OUT_B=$(run_hook "$SANDBOX_B" "$SANDBOX_B/$REL_MD")
if [[ "$HOOK_OUT_B" == *"WARN:"* ]] && [[ "$HOOK_OUT_B" == *"content unchanged"* ]]; then
  pass "B: edit-time hook emits symmetric WARN (content unchanged)"
else
  fail "B: expected symmetric WARN with 'content unchanged'; got: $HOOK_OUT_B"
fi

# Stage-check MUST exit 1 with STOP.
STAGE_OUT_B=$(run_stage_check "$SANDBOX_B" 2>&1)
STAGE_EC_B=$?
if [ "$STAGE_EC_B" -eq 1 ] && [[ "$STAGE_OUT_B" == *"STOP:"* ]] && [[ "$STAGE_OUT_B" == *"content unchanged"* ]]; then
  pass "B: stage-check exits 1 with STOP + 'content unchanged'"
else
  fail "B: expected exit 1 + STOP + content-unchanged; got exit=$STAGE_EC_B err=$STAGE_OUT_B"
fi

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
