#!/bin/bash
# tests/test-skills-mirror-parity.sh
#
# Asserts byte-equality between every source skill and its installed mirror
# under `.claude/skills/`. The analog of `test-hooks-mirror-parity.sh` (which
# closed issue #390 for hooks) for the skill-source -> skill-install layer.
# Closes issue #538.
#
# Source-of-truth is multi-rooted:
#   skills/<X>/            -> .claude/skills/<X>/         (required, byte-equal)
#   block-diagram/<X>/     -> .claude/skills/<X>/         (optional install per
#                                                          --with-addons /
#                                                          --with-block-diagram-addons;
#                                                          if mirror exists it MUST
#                                                          be byte-equal)
#
# Exclusions (per `feedback_claude_skills_permissions` and mirror semantics):
#   __pycache__/*.pyc — Python bytecode, not source-tracked.
#
# Whitelist for `.claude/skills/` entries with no source root match
# (consumer-installed third-party skills, not part of zskills source):
#   playwright-cli — installed by user/devcontainer; not under zskills
#                    source control.
#   social-seo     — same class (historic; checked at write-time, kept in
#                    list to match the issue-538 spec even if not present
#                    today).
#
# To update the whitelist, run:
#   diff -rq skills/ .claude/skills/ --exclude=__pycache__ --exclude='*.pyc' \
#     | grep '^Only in .claude/skills/'
# Anything not in skills/, not in block-diagram/, and not whitelisted is
# treated as drift.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS $*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo "FAIL $*"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# Consumer-installed skills allowed to live only under `.claude/skills/`.
WHITELIST_ONLY_MIRROR=(
  "playwright-cli"
  "social-seo"
)

is_whitelisted() {
  local bn="$1"
  for x in "${WHITELIST_ONLY_MIRROR[@]}"; do
    [[ "$bn" == "$x" ]] && return 0
  done
  return 1
}

DIFF_EXCLUDES=( --exclude=__pycache__ --exclude='*.pyc' )

# --- Forward check: every skills/<X>/ MUST have a byte-equal mirror. ---
shopt -s nullglob
SKILL_DIRS=( skills/*/ )
shopt -u nullglob

if [[ ${#SKILL_DIRS[@]} -eq 0 ]]; then
  fail "no skill sources matched skills/*/ — glob likely broken"
fi

for SRC in "${SKILL_DIRS[@]}"; do
  bn="$(basename "$SRC")"
  MIRROR=".claude/skills/$bn"

  if [[ ! -d "$MIRROR" ]]; then
    fail "mirror missing: $SRC has no mirror at $MIRROR/"
    continue
  fi

  if diff -rq "${DIFF_EXCLUDES[@]}" "$SRC" "$MIRROR/" >/dev/null 2>&1; then
    pass "mirror parity: $SRC == $MIRROR/"
  else
    drift="$(diff -rq "${DIFF_EXCLUDES[@]}" "$SRC" "$MIRROR/" 2>&1)"
    fail "mirror drift: $SRC vs $MIRROR/"
    while IFS= read -r line; do
      [[ -n "$line" ]] && echo "       $line"
    done <<< "$drift"
  fi
done

# --- Forward check: every block-diagram/<X>/ that IS installed must match. ---
# block-diagram add-ons are installed opt-in (`--with-addons` /
# `--with-block-diagram-addons`); missing mirror is NOT a failure, but a
# present-but-divergent mirror IS.
shopt -s nullglob
ADDON_DIRS=( block-diagram/*/ )
shopt -u nullglob

for SRC in "${ADDON_DIRS[@]}"; do
  bn="$(basename "$SRC")"
  # Only consider entries that look like skills (have SKILL.md). Non-skill
  # directories under block-diagram/ (e.g., `screenshots/`) are
  # documentation/assets, not installable skills.
  if [[ ! -f "$SRC/SKILL.md" ]]; then
    pass "skip (not a skill, no SKILL.md): $SRC"
    continue
  fi

  MIRROR=".claude/skills/$bn"
  if [[ ! -d "$MIRROR" ]]; then
    pass "addon $SRC not installed (no mirror at $MIRROR/) — opt-in, ok"
    continue
  fi

  if diff -rq "${DIFF_EXCLUDES[@]}" "$SRC" "$MIRROR/" >/dev/null 2>&1; then
    pass "addon parity: $SRC == $MIRROR/"
  else
    drift="$(diff -rq "${DIFF_EXCLUDES[@]}" "$SRC" "$MIRROR/" 2>&1)"
    fail "addon drift: $SRC vs $MIRROR/"
    while IFS= read -r line; do
      [[ -n "$line" ]] && echo "       $line"
    done <<< "$drift"
  fi
done

# --- Reverse check: every .claude/skills/<X>/ must trace to a source root
# OR be whitelisted. ---
shopt -s nullglob
MIRROR_DIRS=( .claude/skills/*/ )
shopt -u nullglob

for MIR in "${MIRROR_DIRS[@]}"; do
  bn="$(basename "$MIR")"
  if [[ -d "skills/$bn" || -d "block-diagram/$bn" ]]; then
    pass "reverse: mirror $MIR traces to a source root"
  elif is_whitelisted "$bn"; then
    pass "reverse: mirror $MIR is whitelisted (consumer-installed)"
  else
    fail "reverse: mirror $MIR has no source under skills/ or block-diagram/ and is not whitelisted"
  fi
done

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
exit $FAIL_COUNT
