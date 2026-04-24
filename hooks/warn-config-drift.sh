#!/bin/bash
# warn-config-drift.sh — PostToolUse hook, non-blocking warn.
#
# Fires after an Edit or Write tool whose target path ends with
# .claude/zskills-config.json. Emits a note on stderr reminding the
# user that .claude/rules/zskills/managed.md is a render-time snapshot
# and may now be stale; `/update-zskills --rerender` regenerates it.
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

# Suffix-match: handles absolute, repo-relative, cwd-relative paths.
if [[ "$FILE_PATH" == *".claude/zskills-config.json" ]]; then
  cat >&2 <<'WARN'
NOTE: You just edited `.claude/zskills-config.json`.

- Hooks and helper scripts read config at runtime — they are already current.
- `.claude/rules/zskills/managed.md` is a render-time snapshot — it may now be stale. Run `/update-zskills --rerender` to regenerate it (full-file rewrite; the file is zskills-owned, no user content lives there).
WARN
fi

exit 0
