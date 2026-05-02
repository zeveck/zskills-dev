#!/bin/bash
# warn-config-drift.sh — PostToolUse hook, non-blocking warn.
#
# Two responsibilities:
#
#   1. Config-file drift: fires on Edit/Write of .claude/zskills-config.json
#      and reminds the user that .claude/rules/zskills/managed.md is a
#      render-time snapshot and may now be stale.
#
#   2. Skill-file drift: fires on Edit/Write of skills/<owner>/...md (the
#      source skills/ tree, NOT mirrored .claude/skills/...) and warns when
#      the edit leaves a forbidden literal from
#      tests/fixtures/forbidden-literals.txt unexempted. An
#      <!-- allow-hardcoded: <literal> reason: ... --> marker in the
#      block of marker/fence/blank lines above the hit exempts that hit;
#      this matches the deny-list test's fence-scoped semantics
#      (references/canonical-config-prelude.md §7). Single source of
#      truth: tests/test-skill-conformance.sh's deny-list scans the same
#      fixture file at CI time.
#
# Non-blocking by contract: always exits 0, even on malformed input.
# A PostToolUse warn hook must never halt the user.

set -u

INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

# Extract tool_name. Handles `"tool_name":"Edit"` and `"tool_name": "Edit"`.
TOOL_NAME=""
if [[ "$INPUT" =~ \"tool_name\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
  TOOL_NAME="${BASH_REMATCH[1]}"
fi

# Only Edit and Write are wired to this hook; bail on anything else.
if [[ "$TOOL_NAME" != "Edit" && "$TOOL_NAME" != "Write" ]]; then
  exit 0
fi

# Extract tool_input.file_path. Same whitespace-tolerant idiom.
FILE_PATH=""
if [[ "$INPUT" =~ \"file_path\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
  FILE_PATH="${BASH_REMATCH[1]}"
fi

# --- Branch 1: config-file drift ---------------------------------------------
# Suffix-match: handles absolute, repo-relative, cwd-relative paths.
if [[ "$FILE_PATH" == *".claude/zskills-config.json" ]]; then
  cat >&2 <<'WARN'
NOTE: You just edited `.claude/zskills-config.json`.

- Hooks and helper scripts read config at runtime — they are already current.
- `.claude/rules/zskills/managed.md` is a render-time snapshot — it may now be stale. Run `/update-zskills --rerender` to regenerate it (full-file rewrite; the file is zskills-owned, no user content lives there).
WARN
fi

# --- Branch 2: skill-file drift ---------------------------------------------
# Anchored: must match `skills/<owner>/...md` (or repo-relative
# `^skills/...`), but NOT `.claude/skills/...` mirrors. Editing the source
# skills/ file is the canonical path; the mirror gets cp-batched, so warning
# twice would spam every Edit→cp pair.
if [[ "$FILE_PATH" =~ (^|/)(skills|block-diagram)/[^/]+/.*\.md$ ]] && [[ "$FILE_PATH" != *.claude/skills/* ]] \
   && [ -n "${CLAUDE_PROJECT_DIR:-}" ] \
   && [ -r "$CLAUDE_PROJECT_DIR/tests/fixtures/forbidden-literals.txt" ] \
   && [ -r "$FILE_PATH" ]; then
  # Resolve fixture path. CLAUDE_PROJECT_DIR is set by Claude Code at
  # hook fire time. Graceful no-op when fixture absent — downstream
  # installs that bypass /update-zskills will hit this. The deny-list
  # test running in zskills CI is the load-bearing protection for
  # shipped skills; this hook is a zskills-CI-only nudge for in-repo
  # edits (see plans/SKILL_FILE_DRIFT_FIX.md Phase 4 Design &
  # Constraints "Downstream coverage scope").
  #
  # Pre-conditions are folded into the if-chain above (was a series of
  # `... || exit 0` lines pre-Phase-4) so a missing fixture skips Branch
  # 2 only, leaving Branch 3 (below) free to run. Previous form
  # short-circuited the entire hook.
  FIXTURE_PATH="$CLAUDE_PROJECT_DIR/tests/fixtures/forbidden-literals.txt"

  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    [[ "$entry" =~ ^# ]] && continue
    if [[ "$entry" =~ ^re: ]]; then
      pattern="${entry#re:}"
      grep_args=(-nE --)
      match_term="$pattern"
      allow_key="$pattern"
    else
      grep_args=(-nF --)
      match_term="$entry"
      allow_key="$entry"
    fi
    while IFS= read -r line_no_match; do
      [ -z "$line_no_match" ] && continue
      # `grep -n` output: "<line_no>:<content>". Extract line number.
      hit_line_no="${line_no_match%%:*}"
      hit_content="${line_no_match#*:}"
      # Skip hits that ARE on an allow-hardcoded marker line — the marker
      # text itself contains the literal it exempts, and warning on the
      # marker would defeat the purpose.
      if [[ "$hit_content" =~ ^[[:space:]]*\<!--[[:space:]]+allow-hardcoded: ]]; then
        continue
      fi
      # Marker scan: walk upward from the hit line. The deny-list test's
      # convention is "marker on the line(s) immediately above a
      # fence-opener exempts hits inside the fence". For the hook we
      # approximate that with: scan lines above the hit, stripping any
      # leading `>` blockquote-prefix; treat marker lines, fence-opener
      # lines (` ``` ` / ` ```bash` / ...), and blank lines as
      # transparent; stop at the first opaque non-marker non-fence
      # non-blank line. If a marker naming `$allow_key` is encountered
      # along the way, the hit is exempted.
      exempted=0
      scan_n=$((hit_line_no - 1))
      while [ "$scan_n" -ge 1 ]; do
        scan_line=$(sed -n "${scan_n}p" "$FILE_PATH" 2>/dev/null)
        # Strip leading blockquote prefix.
        if [[ "$scan_line" =~ ^[[:space:]]*\>[[:space:]]?(.*)$ ]]; then
          scan_line="${BASH_REMATCH[1]}"
        fi
        if [[ "$scan_line" == *"<!-- allow-hardcoded: $allow_key reason:"* ]]; then
          exempted=1
          break
        fi
        # Fence opener / closer / blank lines are transparent.
        if [[ "$scan_line" =~ ^[[:space:]]*\`\`\`[a-zA-Z0-9_+-]*[[:space:]]*$ ]] \
           || [ -z "${scan_line//[[:space:]]/}" ]; then
          scan_n=$((scan_n - 1))
          continue
        fi
        # Any other allow-hardcoded marker (different literal) is also
        # transparent — markers may stack above a single fence.
        if [[ "$scan_line" =~ ^[[:space:]]*\<!--[[:space:]]+allow-hardcoded: ]]; then
          scan_n=$((scan_n - 1))
          continue
        fi
        break
      done
      if [ "$exempted" -eq 1 ]; then
        continue
      fi
      printf 'WARN: %s:%s contains forbidden literal %s (no allow-hardcoded marker found). Replace with $VAR or add the marker; see references/canonical-config-prelude.md.\n' \
        "$FILE_PATH" "$hit_line_no" "$allow_key" >&2
    done < <(grep "${grep_args[@]}" "$match_term" "$FILE_PATH" 2>/dev/null || true)
  done < "$FIXTURE_PATH"
fi

# --- Branch 3: skill version not bumped --------------------------------------
# Fires on Edit/Write of any regular file under (skills|block-diagram)/<name>/
# (parent SKILL.md OR child files in modes/, references/, scripts/, fixtures/,
# stubs/, etc — every file in the §1.1 projection). Compares the parent
# skill's recomputed projection hash against HEAD's metadata.version hash; if
# the hash drifted but the version line is unchanged, emit an asymmetric
# WARN. If the version was bumped but the projection is unchanged, emit a
# symmetric WARN (revert / no-op edit).
#
# Trailing `[^/]+` requires a path segment AFTER the skill name — keeps
# top-level docs like `block-diagram/README.md` and asset-only paths like
# `block-diagram/screenshots/foo.png` from matching this branch unless
# their parent has a SKILL.md (the [ -f "$skill_md" ] || exit 0 check
# downstream is the load-bearing guard). refine-plan F-DA-9.
if [[ "$FILE_PATH" =~ (^|/)(skills|block-diagram)/([^/]+)/[^/]+ ]] \
   && [[ "$FILE_PATH" != *.claude/skills/* ]]; then
  REPO_ROOT="${CLAUDE_PROJECT_DIR:-}"
  if [ -n "$REPO_ROOT" ]; then
    HASH_HELPER="$REPO_ROOT/scripts/skill-content-hash.sh"
    GET_HELPER="$REPO_ROOT/scripts/frontmatter-get.sh"
    if [ -x "$HASH_HELPER" ] && [ -x "$GET_HELPER" ]; then
      skill_root_kind="${BASH_REMATCH[2]}"
      skill_name="${BASH_REMATCH[3]}"
      skill_dir="$REPO_ROOT/$skill_root_kind/$skill_name"
      skill_md="$skill_dir/SKILL.md"
      if [ -f "$skill_md" ]; then
        # Normalise $FILE_PATH to repo-relative form. Probe `realpath
        # --relative-to` by INVOCATION (BSD realpath exists at
        # /usr/bin/realpath but lacks the flag; the `command -v realpath`
        # probe alone misclassifies BSD as supported — refine-plan
        # F-DA-R2-1). On fallback failure, surface a WARN diagnostic so
        # the silent no-op is observable (refine-plan F-R2-1).
        FILE_PATH_REL=""
        if FILE_PATH_REL=$(realpath --relative-to="$REPO_ROOT" "$FILE_PATH" 2>/dev/null) \
             && [ -n "$FILE_PATH_REL" ]; then
          case "$FILE_PATH_REL" in
            /*) FILE_PATH_REL="" ;;
          esac
        fi
        skip_branch3=0
        if [ -z "$FILE_PATH_REL" ]; then
          # Fallback: textual prefix strip. Works when $FILE_PATH and
          # $REPO_ROOT share a literal prefix; fails on symlink
          # divergence (e.g., /var/folders/.../X vs /private/var/.../X
          # on macOS, where REPO_ROOT may be one form and FILE_PATH the
          # other after symlink resolution).
          FILE_PATH_REL="${FILE_PATH#$REPO_ROOT/}"
          case "$FILE_PATH_REL" in
            /*)
              printf 'WARN: warn-config-drift: could not normalize %s relative to %s — staged-file gate skipped\n' \
                "$FILE_PATH" "$REPO_ROOT" >&2
              skip_branch3=1
              ;;
          esac
        fi

        if [ "$skip_branch3" -eq 0 ]; then
          # Staged-file gate. `grep -Fqx` (fixed-string, full-line) — paths
          # may contain regex metacharacters (e.g., a skill named `a.b` or
          # `a+b`); plain `grep -qx` would treat them as a regex pattern
          # (refine-plan F-DA-R2-5). `git diff` uses 2>/dev/null because
          # "no git tree" is a legitimate signal "no staged set" — see the
          # plan §4.1 audit of the four operational sites that suppress
          # stderr.
          if git -C "$REPO_ROOT" diff --cached --name-only 2>/dev/null \
             | grep -Fqx "$FILE_PATH_REL"; then
            # Subject = parent SKILL.md (NOT the edited child file). The
            # body-diff check operates on the parent's projection.
            on_disk_ver=$(bash "$GET_HELPER" "$skill_md" metadata.version) || on_disk_ver=""

            # HEAD version line. `git show HEAD:<path>` failure (file not
            # yet in HEAD) is the legitimate "first migration commit"
            # signal — see §4.1 audit.
            head_blob=$(git -C "$REPO_ROOT" show "HEAD:${skill_md#$REPO_ROOT/}" 2>/dev/null) \
              || head_blob=""
            head_ver=""
            if [ -n "$head_blob" ]; then
              # `2>/dev/null` here is the legitimate "first migration"
              # signal — HEAD's SKILL.md may predate metadata.version
              # (frontmatter-get exits 1 with "key not found" stderr).
              # We do NOT suppress stderr on the on-disk get above
              # because that one signals a real bug if it fails.
              head_ver=$(printf '%s' "$head_blob" | bash "$GET_HELPER" - metadata.version 2>/dev/null) \
                || head_ver=""
            fi

            cur_hash=$(bash "$HASH_HELPER" "$skill_dir")
            stored_hash="${on_disk_ver##*+}"
            head_hash="${head_ver##*+}"

            # Asymmetric warn: hash drifted but version line unchanged.
            if [ -n "$on_disk_ver" ] && [ "$on_disk_ver" = "$head_ver" ] \
               && [ "$cur_hash" != "$stored_hash" ]; then
              today=$(TZ="${TIMEZONE:-America/New_York}" date +%Y.%m.%d)
              printf 'WARN: %s — skill content changed (hash %s → %s) but metadata.version unchanged. Bump to %s+%s before commit.\n' \
                "$skill_md" "$stored_hash" "$cur_hash" "$today" "$cur_hash" >&2
            fi

            # Symmetric warn: version bumped but content unchanged.
            if [ -n "$on_disk_ver" ] && [ "$on_disk_ver" != "$head_ver" ] \
               && [ "$cur_hash" = "$head_hash" ]; then
              printf 'WARN: %s — metadata.version bumped (%s → %s) but content unchanged. Revert version line or land a real edit.\n' \
                "$skill_md" "$head_ver" "$on_disk_ver" >&2
            fi
          fi
        fi
      fi
    fi
  fi
fi

exit 0
