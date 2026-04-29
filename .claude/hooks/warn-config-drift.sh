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
if [[ "$FILE_PATH" =~ (^|/)skills/[^/]+/.*\.md$ ]] && [[ "$FILE_PATH" != *.claude/skills/* ]]; then
  # Resolve fixture path. CLAUDE_PROJECT_DIR is set by Claude Code at
  # hook fire time. Graceful no-op when fixture absent — downstream
  # installs that bypass /update-zskills will hit this. The deny-list
  # test running in zskills CI is the load-bearing protection for
  # shipped skills; this hook is a zskills-CI-only nudge for in-repo
  # edits (see plans/SKILL_FILE_DRIFT_FIX.md Phase 4 Design &
  # Constraints "Downstream coverage scope").
  [ -n "${CLAUDE_PROJECT_DIR:-}" ] || exit 0
  FIXTURE_PATH="$CLAUDE_PROJECT_DIR/tests/fixtures/forbidden-literals.txt"
  [ -r "$FIXTURE_PATH" ] || exit 0
  [ -r "$FILE_PATH" ] || exit 0

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

exit 0
