#!/bin/bash
# skill-version-stage-check.sh — commit-time hard stop on skill metadata.version drift.
#
# Used by /commit Phase 5 step 2.5. Iterates the staging set, gathers
# unique parent skills under (skills|block-diagram)/<name>/..., and for
# each compares:
#   - the skill's CURRENT (worktree) projection hash, vs.
#   - the staged metadata.version's hash, vs.
#   - HEAD's metadata.version's hash.
#
# Failure modes (each adds an entry to FAIL_LIST):
#   1. Asymmetric: content changed (cur_hash != head_hash) but the staged
#      version line did NOT bump (staged_ver == head_ver). → Bump required.
#   2. Symmetric: staged version bumped (staged_ver != head_ver, non-empty)
#      but content unchanged (cur_hash == head_hash). → Revert version line
#      or land a real edit.
#
# Exit:
#   0  no drift — caller proceeds.
#   1  drift detected — caller halts with the printed STOP message.
#
# References:
#   plans/SKILL_VERSIONING.md Phase 4.3
#   references/skill-versioning.md §1.4 (point 2)
#
# Pure bash + helpers — no external JSON parser (per zskills convention).

set -u

REPO_ROOT="${CLAUDE_PROJECT_DIR:?CLAUDE_PROJECT_DIR required}"
GET="$REPO_ROOT/scripts/frontmatter-get.sh"
HASH="$REPO_ROOT/scripts/skill-content-hash.sh"

# Pull $TIMEZONE from the canonical config resolver. The mirror lives at
# .claude/skills/update-zskills/scripts/zskills-resolve-config.sh — same
# path used by every other skill that needs $TIMEZONE / $FULL_TEST_CMD.
RESOLVER="$REPO_ROOT/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
if [ -r "$RESOLVER" ]; then
  # shellcheck source=/dev/null
  . "$RESOLVER"
fi
: "${TIMEZONE:=America/New_York}"

declare -A SKILLS_TO_CHECK
while IFS= read -r f; do
  [[ "$f" =~ ^(skills|block-diagram)/([^/]+)/ ]] || continue
  SKILLS_TO_CHECK["${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"]=1
done < <(git -C "$REPO_ROOT" diff --cached --name-only)

FAIL_LIST=()
for sk in "${!SKILLS_TO_CHECK[@]}"; do
  skill_md="$REPO_ROOT/$sk/SKILL.md"
  [ -f "$skill_md" ] || continue

  # Staged blob — empty when skill files are staged but SKILL.md itself
  # isn't (e.g., only modes/foo.md staged). `2>/dev/null` here is the
  # legitimate "not staged" signal — see plan §4.1 audit of operational
  # 2>/dev/null sites.
  staged_blob=$(git -C "$REPO_ROOT" show ":$sk/SKILL.md" 2>/dev/null) || staged_blob=""
  staged_ver=""
  if [ -n "$staged_blob" ]; then
    # 2>/dev/null: same first-migration class as the head_ver block
    # below — staged blob may predate metadata.version.
    staged_ver=$(printf '%s' "$staged_blob" | bash "$GET" - metadata.version 2>/dev/null) || staged_ver=""
  fi

  # HEAD blob — empty during the very first migration commit. Same audit class.
  head_blob=$(git -C "$REPO_ROOT" show "HEAD:$sk/SKILL.md" 2>/dev/null) || head_blob=""
  head_ver=""
  if [ -n "$head_blob" ]; then
    # `2>/dev/null` here is legitimate first-migration signal — HEAD's
    # SKILL.md may predate metadata.version (frontmatter-get exits 1
    # with "key not found" stderr). On-disk get below uses no
    # suppression because failure there indicates a real bug.
    head_ver=$(printf '%s' "$head_blob" | bash "$GET" - metadata.version 2>/dev/null) || head_ver=""
  fi

  cur_hash=$(bash "$HASH" "$REPO_ROOT/$sk")
  staged_hash="${staged_ver##*+}"
  head_hash="${head_ver##*+}"

  # On-disk version is always read — used both as the staged-ver fallback
  # when SKILL.md isn't staged, and as a discriminator below for the
  # "bumped on disk but not staged" hint in the asymmetric STOP message.
  on_disk_ver=$(bash "$GET" "$skill_md" metadata.version) || on_disk_ver=""

  # When SKILL.md isn't staged but child files are, the on-disk version
  # IS the comparison target — fall through to staged_ver == on_disk_ver.
  if [ -z "$staged_ver" ]; then
    staged_ver="$on_disk_ver"
    staged_hash="${staged_ver##*+}"
  fi

  # Asymmetric: content changed, version unchanged.
  if [ "$cur_hash" != "$head_hash" ] && [ "$staged_ver" = "$head_ver" ]; then
    # Hint: did the user bump on disk but forget to `git add`? If
    # on_disk_ver differs from staged_ver (and is non-empty / non-head),
    # the bump exists in the working tree but isn't staged.
    hint=""
    if [ -n "$on_disk_ver" ] && [ "$on_disk_ver" != "$staged_ver" ] \
       && [ "$on_disk_ver" != "$head_ver" ]; then
      hint=" (SKILL.md not staged — git add it)"
    fi
    FAIL_LIST+=("$sk: content changed (hash $head_hash → $cur_hash) but staged metadata.version still $staged_ver$hint")
  fi
  # Symmetric: version bumped, content unchanged.
  if [ "$cur_hash" = "$head_hash" ] && [ -n "$staged_ver" ] && [ "$staged_ver" != "$head_ver" ]; then
    FAIL_LIST+=("$sk: metadata.version bumped ($head_ver → $staged_ver) but content unchanged")
  fi
done

if [ ${#FAIL_LIST[@]} -gt 0 ]; then
  today=$(TZ="$TIMEZONE" date +%Y.%m.%d)
  echo "STOP: skill version mismatch in staged commit:" >&2
  for msg in "${FAIL_LIST[@]}"; do
    echo "  $msg" >&2
  done
  echo "" >&2
  echo "To fix, for each affected skill <S>:" >&2
  echo "  hash=\$(bash $REPO_ROOT/scripts/skill-content-hash.sh <S>)" >&2
  echo "  bash $REPO_ROOT/scripts/frontmatter-set.sh <S>/SKILL.md metadata.version \"$today+\$hash\"" >&2
  echo "Then re-stage and re-run /commit." >&2
  exit 1
fi

exit 0
