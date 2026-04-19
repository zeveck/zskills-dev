#!/bin/bash
# Apply a zskills preset to .claude/zskills-config.json and
# .claude/hooks/block-unsafe-generic.sh.
#
# Usage: bash scripts/apply-preset.sh <cherry-pick|locked-main-pr|direct>
# Env:   PROJECT_ROOT — override root (default: $(pwd))
# Exits: 0 = applied (at least one field changed)
#        1 = no changes (preset already applied)
#        2 = usage error (unknown/missing preset)
#        3 = missing file (config or hook not found)
#        4 = cannot edit config (e.g. no outer-object closing brace)
#
# Preset → field mapping:
#   cherry-pick    landing=cherry-pick  main_protected=false  BLOCK_MAIN_PUSH=0
#   locked-main-pr landing=pr           main_protected=true   BLOCK_MAIN_PUSH=1
#   direct         landing=direct       main_protected=false  BLOCK_MAIN_PUSH=0
#
# Idempotent: repeat invocations with the same preset exit rc=1 with no
# writes. Preserves every config field not owned by the preset
# (branch_prefix, testing.*, dev_server.*, ui.*, ci.*, timezone,
# agents.min_model, $schema, project_name).
#
# Bash-only (no python/jq). Uses sed for in-place field updates and awk
# to splice a missing `execution` block.
#
# Hook behavior:
#   - If the BLOCK_MAIN_PUSH= line is missing (legacy hook), splice
#     BLOCK_MAIN_PUSH=<target> before the first non-comment, non-blank
#     line of code. Non-destructive fill — other hook content preserved
#     byte-for-byte.
#   - If the line exists with a different value, rewrite it.
#   - Otherwise no-op.

set -e

PRESET="${1:-}"
case "$PRESET" in
  cherry-pick)    LANDING=cherry-pick; MAIN_PROTECTED=false; BLOCK_MAIN_PUSH=0 ;;
  locked-main-pr) LANDING=pr;          MAIN_PROTECTED=true;  BLOCK_MAIN_PUSH=1 ;;
  direct)         LANDING=direct;      MAIN_PROTECTED=false; BLOCK_MAIN_PUSH=0 ;;
  "")  echo "usage: apply-preset.sh <cherry-pick|locked-main-pr|direct>" >&2; exit 2 ;;
  *)   echo "apply-preset: unknown preset '$PRESET' (valid: cherry-pick, locked-main-pr, direct)" >&2; exit 2 ;;
esac

PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
CONFIG="$PROJECT_ROOT/.claude/zskills-config.json"
HOOK="$PROJECT_ROOT/.claude/hooks/block-unsafe-generic.sh"

if [ ! -f "$CONFIG" ]; then
  echo "apply-preset: $CONFIG not found. Run /update-zskills first to create the config." >&2
  exit 3
fi
if [ ! -f "$HOOK" ]; then
  echo "apply-preset: $HOOK not found. Install hooks via /update-zskills install first." >&2
  exit 3
fi

CHANGED=()

# Portable sed-in-place (BSD sed lacks GNU's `sed -i` syntax; stage to
# tempfile then overwrite).
sed_inplace() {
  local expr="$1" file="$2"
  local tmp
  tmp=$(mktemp)
  sed -E "$expr" "$file" > "$tmp" && cat "$tmp" > "$file"
  rm -f "$tmp"
}

# ─── Config: execution.landing + execution.main_protected ───────────
# Existing-value probes. These regexes are permissive across formatting
# (compact, canonical, mixed whitespace, tabs).
CURRENT_LANDING=$(sed -n -E 's/.*"landing"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' "$CONFIG" | head -1)
CURRENT_PROTECTED=$(sed -n -E 's/.*"main_protected"[[:space:]]*:[[:space:]]*(true|false).*/\1/p' "$CONFIG" | head -1)

# Is there an execution block at all?
EXEC_EXISTS=0
if grep -q '"execution"' "$CONFIG"; then
  EXEC_EXISTS=1
fi

if [ "$EXEC_EXISTS" = "0" ]; then
  # Insert a fresh execution block before the outer object's closing brace.
  TMP=$(mktemp)
  awk -v landing="$LANDING" -v prot="$MAIN_PROTECTED" '
    { buf[NR] = $0 }
    END {
      # Find the last standalone closing brace of the outer object.
      last_close = 0
      for (i = NR; i >= 1; i--) {
        if (buf[i] ~ /^[[:space:]]*\}[[:space:]]*$/) { last_close = i; break }
      }
      if (last_close == 0) {
        # Malformed — no outer closing brace. Leave file untouched and
        # signal the caller via a non-zero exit from awk.
        for (i = 1; i <= NR; i++) print buf[i]
        exit 2
      }
      # Last non-blank line before the closing brace (needs a trailing
      # comma to keep JSON valid after we append our block).
      preceding = 0
      for (i = last_close - 1; i >= 1; i--) {
        if (buf[i] !~ /^[[:space:]]*$/) { preceding = i; break }
      }
      # Print everything up to (but not including) the preceding line.
      for (i = 1; i < preceding; i++) print buf[i]
      # Print the preceding line, ensuring it ends with a comma.
      if (preceding > 0) {
        if (buf[preceding] ~ /,[[:space:]]*$/) {
          print buf[preceding]
        } else {
          line = buf[preceding]
          sub(/[[:space:]]*$/, "", line)
          print line ","
        }
      }
      # Inject the execution block (canonical two-space indent).
      print "  \"execution\": {"
      print "    \"landing\": \"" landing "\","
      print "    \"main_protected\": " prot ","
      print "    \"branch_prefix\": \"feat/\""
      print "  }"
      # Preserve any blank lines between preceding and last_close.
      for (i = preceding + 1; i < last_close; i++) print buf[i]
      # Print the closing brace and anything after.
      for (i = last_close; i <= NR; i++) print buf[i]
    }
  ' "$CONFIG" > "$TMP" || {
    rm -f "$TMP"
    echo "apply-preset: cannot locate outer closing brace in $CONFIG; file may be malformed." >&2
    exit 4
  }
  cat "$TMP" > "$CONFIG"
  rm -f "$TMP"
  CHANGED+=("execution (inserted)")
else
  if [ "$CURRENT_LANDING" != "$LANDING" ]; then
    sed_inplace "s/(\"landing\"[[:space:]]*:[[:space:]]*)\"[^\"]*\"/\\1\"$LANDING\"/" "$CONFIG"
    CHANGED+=("execution.landing=$LANDING")
  fi
  if [ "$CURRENT_PROTECTED" != "$MAIN_PROTECTED" ]; then
    sed_inplace "s/(\"main_protected\"[[:space:]]*:[[:space:]]*)(true|false)/\\1$MAIN_PROTECTED/" "$CONFIG"
    CHANGED+=("execution.main_protected=$MAIN_PROTECTED")
  fi
fi

# ─── Hook: ensure BLOCK_MAIN_PUSH= exists and matches target ────────
CURRENT_LINE=$(grep -m1 '^BLOCK_MAIN_PUSH=' "$HOOK" || true)

if [ -z "$CURRENT_LINE" ]; then
  # Legacy hook — no BLOCK_MAIN_PUSH line. Splice default before the
  # first non-comment non-blank code line.
  TMP=$(mktemp)
  awk -v val="$BLOCK_MAIN_PUSH" '
    BEGIN { inserted=0 }
    !inserted && NR>1 && !/^#/ && !/^[[:space:]]*$/ {
      print "# Preset toggle — set by scripts/apply-preset.sh. Do not edit manually."
      print "BLOCK_MAIN_PUSH=" val
      print ""
      inserted=1
    }
    { print }
    END {
      # Safety net: if the file had no code lines at all, append.
      if (!inserted) {
        print "# Preset toggle — set by scripts/apply-preset.sh. Do not edit manually."
        print "BLOCK_MAIN_PUSH=" val
      }
    }
  ' "$HOOK" > "$TMP"
  cat "$TMP" > "$HOOK"
  rm -f "$TMP"
  CHANGED+=("BLOCK_MAIN_PUSH=$BLOCK_MAIN_PUSH (spliced into legacy hook)")
else
  CURRENT_VAL="${CURRENT_LINE#BLOCK_MAIN_PUSH=}"
  CURRENT_VAL="${CURRENT_VAL%%[[:space:]#]*}"
  if [ "$CURRENT_VAL" != "$BLOCK_MAIN_PUSH" ]; then
    sed_inplace "s/^BLOCK_MAIN_PUSH=[01]/BLOCK_MAIN_PUSH=$BLOCK_MAIN_PUSH/" "$HOOK"
    CHANGED+=("BLOCK_MAIN_PUSH: $CURRENT_VAL → $BLOCK_MAIN_PUSH")
  fi
fi

# ─── Report ─────────────────────────────────────────────────────────
if [ ${#CHANGED[@]} -eq 0 ]; then
  echo "Preset '$PRESET' already applied — no changes needed."
  exit 1
fi

echo "Applied preset '$PRESET':"
for c in "${CHANGED[@]}"; do echo "  - $c"; done
exit 0
