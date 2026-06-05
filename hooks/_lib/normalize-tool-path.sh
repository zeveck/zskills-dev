#!/bin/bash
# hooks/_lib/normalize-tool-path.sh — source-of-truth body for the
# Windows-native-path normaliser shared by the PreToolUse/PostToolUse hooks
# that classify a tool `file_path` against the repo root.
#
# Why this exists: on a Windows (MSYS / Git-Bash) consumer the Edit / Write
# tool passes a drive-letter / backslash path (e.g.
# `D:\LocalDev\proj\.zskills\run-dashboard-start.sh`). Hooks that test
# `case "$FILE_PATH" in /*)` to tell absolute from relative misclassify a
# `D:\...` path as RELATIVE (it does not start with `/`), so the repo-relative
# path they derive never matches the carve-out globs:
#   - block-main-edits.sh then FALSE-DENIES legitimate gitignored `.zskills/`
#     writes (issue #308's carve-out is dead on Windows), and
#   - warn-config-drift.sh silently fails its staged-file gate.
# Normalising the path to a POSIX form FIRST makes the existing `/`-rooted
# containment + carve-out logic match on Windows exactly as on Linux/Mac.
#
# The function is inlined VERBATIM into each shipped consumer (the
# legacy-mirror hooks under .claude/hooks/ cannot reach this _lib file at
# runtime — .claude/hooks/_lib/ is not mirrored — so the body must be pasted
# in, mirroring the zskills_resolve_python convention); the drift gate at
# tests/test-hook-helper-drift.sh enforces byte-equality at CI time.
#
# Maintain HERE only.

# zskills_normalize_tool_path — echo a POSIX form of "$1".
#   - cygpath available  → `cygpath -u "$1"` (authoritative on MSYS/Cygwin).
#   - else pure-bash fallback:
#       * `^[A-Za-z]:[\\/]` (drive letter + sep) → `/<lowercased-drive>/<rest>`
#         with every `\` turned into `/` (e.g. `D:\a\b` → `/d/a/b`;
#         `C:/x` → `/c/x`).
#       * any stray `\` in a backslash-relative path → `/` (`rel\path` →
#         `rel/path`).
#   - A pure-POSIX path (no drive letter, no backslash) passes through
#     UNCHANGED — guaranteed no-op on Linux/Mac.
#   - Empty input → empty output.
# Side-effect free (no globals mutated); safe to call in a command
# substitution.
zskills_normalize_tool_path() {
  local p="$1"
  [ -n "$p" ] || { printf '%s' ""; return 0; }
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -u "$p"
    return 0
  fi
  # Pure-bash fallback (also the code path exercised on Linux/Mac, where
  # cygpath is absent — so this is what the unit test verifies).
  case "$p" in
    [A-Za-z]:[\\/]*)
      # Drive-letter absolute: `D:\a\b` or `C:/x`.
      local drive="${p:0:1}"
      local rest="${p:2}"
      drive="$(printf '%s' "$drive" | tr '[:upper:]' '[:lower:]')"
      rest="${rest//\\//}"
      printf '%s' "/$drive$rest"
      ;;
    *)
      # No drive letter: convert any stray backslash to forward slash. A
      # pure-POSIX path (no backslash) is returned byte-for-byte unchanged.
      printf '%s' "${p//\\//}"
      ;;
  esac
  return 0
}
