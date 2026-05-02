#!/bin/bash
# skill-version-delta.sh — Per-skill version delta.
# Stdout: <name>\t<kind>\t<source-ver>\t<installed-ver>\t<status>
# `<kind>` is `core` for skills/<name>/ or `addon` for block-diagram/<name>/.
# Iterating BOTH source roots so block-diagram add-ons surface in install /
# update / audit reports. (refine-plan F-R13 / F-DA-10: prior loop ranged only
# over `skills/*/`, silently dropping the 3 add-ons even though §1.7 promised
# parity.)
#
# Render-time filter (consumed by Phase 5b.1 Site C): the renderer applies the
# `--with-block-diagram-addons` heuristic — include `kind=addon` rows ONLY
# when the flag was passed OR when at least one `block-diagram/*` skill is
# currently installed under `.claude/skills/`. Filtering happens at the
# renderer, not the enumerator — so the data plumbing is symmetric and
# downstream callers can render either subset.
#
# Status codes:
#   new        — installed version unknown (skill not yet installed)
#   malformed  — installed present but source missing/empty
#   unchanged  — source == installed
#   bumped     — source != installed (both non-empty)
set -u
ZSKILLS_PATH="${1:?usage: skill-version-delta.sh <zskills-source-path>}"
# CLAUDE_PROJECT_DIR may be unset when called outside the harness/test
# wrapper (smoke checks, manual invocation). Default to ZSKILLS_PATH so
# `set -u` doesn't error and the helper resolution falls through to the
# source-side `frontmatter-get.sh`. (Plan-text drift from line 1071/1082:
# original spec referenced `$CLAUDE_PROJECT_DIR` unguarded.)
: "${CLAUDE_PROJECT_DIR:=$ZSKILLS_PATH}"
GET="$CLAUDE_PROJECT_DIR/scripts/frontmatter-get.sh"
[ -x "$GET" ] || GET="$ZSKILLS_PATH/scripts/frontmatter-get.sh"
for src_skill in "$ZSKILLS_PATH/skills"/*/ "$ZSKILLS_PATH/block-diagram"/*/; do
  [ -f "${src_skill}SKILL.md" ] || continue
  name=$(basename "$src_skill")
  case "$src_skill" in
    "$ZSKILLS_PATH/skills"/*) kind="core" ;;
    "$ZSKILLS_PATH/block-diagram"/*) kind="addon" ;;
    *) kind="unknown" ;;
  esac
  src_ver=$(bash "$GET" "${src_skill}SKILL.md" metadata.version) || src_ver=""
  inst_skill="$CLAUDE_PROJECT_DIR/.claude/skills/$name"
  inst_ver=""
  if [ -f "$inst_skill/SKILL.md" ]; then
    inst_ver=$(bash "$GET" "$inst_skill/SKILL.md" metadata.version) || inst_ver=""
  fi
  if [ -z "$inst_ver" ]; then
    status="new"
  elif [ -z "$src_ver" ]; then
    status="malformed"
  elif [ "$src_ver" = "$inst_ver" ]; then
    status="unchanged"
  else
    status="bumped"
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$kind" "$src_ver" "$inst_ver" "$status"
done
