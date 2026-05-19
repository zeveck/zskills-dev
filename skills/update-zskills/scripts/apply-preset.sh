#!/bin/bash
# Apply a zskills preset to .claude/zskills-config.json and
# .claude/hooks/block-unsafe-generic.sh.
#
# Usage: bash $(basename "$0") <cherry-pick|locked-main-pr|direct>
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

# Scope-aware in-place replacement of a JSON field's value within the
# enclosing "execution" object. Substitutes ONLY inside the execution
# block, leaving same-named sibling fields elsewhere in the config
# untouched. Handles both compact single-line and canonical multi-line
# JSON. `field` is the JSON key (e.g. landing). `value_pattern` is the
# extended-regex matching the old value; `new_value` is the replacement
# (substituted verbatim into the output).
#
# Algorithm: read whole file into awk, track brace depth, and substitute
# only the FIRST match of "<field>"<ws>:<ws><value_pattern> that occurs
# while we are inside the execution object (depth >= the depth at which
# we entered execution).
exec_field_replace() {
  local file="$1" field="$2" value_pattern="$3" new_value="$4"
  local tmp
  tmp=$(mktemp)
  awk -v field="$field" -v vpat="$value_pattern" -v newval="$new_value" '
    BEGIN { RS = "\x00" }   # slurp whole file as one record
    {
      out = ""
      buf = $0
      n = length(buf)
      i = 1
      in_exec = 0
      exec_depth = 0
      depth = 0
      done = 0
      while (i <= n) {
        ch = substr(buf, i, 1)
        if (!in_exec) {
          # Find next "execution" key. Use simple substring search; then
          # confirm it is followed by <ws>:<ws>{ to be a real object.
          rest = substr(buf, i)
          pos = index(rest, "\"execution\"")
          if (pos == 0) {
            out = out rest
            break
          }
          # Emit everything up to and including the "execution" token.
          tok_end = i + pos - 1 + length("\"execution\"") - 1
          out = out substr(buf, i, tok_end - i + 1)
          i = tok_end + 1
          # Check that next is <ws>*:<ws>*{
          rest2 = substr(buf, i)
          if (match(rest2, /^[[:space:]]*:[[:space:]]*\{/)) {
            out = out substr(buf, i, RLENGTH)
            i = i + RLENGTH
            in_exec = 1
            exec_depth = 1
            depth = 1
          }
          continue
        }
        # in_exec: track depth and look for the field substitution.
        if (ch == "{") { depth++; out = out ch; i++; continue }
        if (ch == "}") {
          depth--
          out = out ch
          i++
          if (depth < exec_depth) { in_exec = 0 }
          continue
        }
        if (!done && ch == "\"") {
          rest = substr(buf, i)
          pat = "^\"" field "\"[[:space:]]*:[[:space:]]*"
          if (match(rest, pat)) {
            head_len = RLENGTH
            # Now check the value matches the supplied pattern.
            tail = substr(rest, head_len + 1)
            vpat_anchored = "^(" vpat ")"
            if (match(tail, vpat_anchored)) {
              val_len = RLENGTH
              # Emit head (key + colon + ws), then new_value; skip val_len.
              out = out substr(buf, i, head_len) newval
              i = i + head_len + val_len
              done = 1
              continue
            }
          }
        }
        out = out ch
        i++
      }
      printf "%s", out
    }
  ' "$file" > "$tmp" && cat "$tmp" > "$file"
  rm -f "$tmp"
}

# ─── Config: execution.landing + execution.main_protected ───────────
# Existing-value probes. Scope under the enclosing "execution" object so
# a future sibling field (e.g. an unrelated "landing" elsewhere in the
# config) cannot poison the read. Mirrors dev_server.cmd scoping in
# zskills-resolve-config.sh:88. The bash =~ engine is single-line but
# [^}] matches newlines, so this works on both compact and canonical
# multi-line JSON.
CONFIG_BODY=$(cat "$CONFIG")
CURRENT_LANDING=""
CURRENT_PROTECTED=""
if [[ "$CONFIG_BODY" =~ \"execution\"[[:space:]]*:[[:space:]]*\{[^}]*\"landing\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
  CURRENT_LANDING="${BASH_REMATCH[1]}"
fi
if [[ "$CONFIG_BODY" =~ \"execution\"[[:space:]]*:[[:space:]]*\{[^}]*\"main_protected\"[[:space:]]*:[[:space:]]*(true|false) ]]; then
  CURRENT_PROTECTED="${BASH_REMATCH[1]}"
fi

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
    exec_field_replace "$CONFIG" "landing" '"[^"]*"' "\"$LANDING\""
    CHANGED+=("execution.landing=$LANDING")
  fi
  if [ "$CURRENT_PROTECTED" != "$MAIN_PROTECTED" ]; then
    exec_field_replace "$CONFIG" "main_protected" "(true|false)" "$MAIN_PROTECTED"
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
      print "# Preset toggle — set by apply-preset.sh. Do not edit manually."
      print "BLOCK_MAIN_PUSH=" val
      print ""
      inserted=1
    }
    { print }
    END {
      # Safety net: if the file had no code lines at all, append.
      if (!inserted) {
        print "# Preset toggle — set by apply-preset.sh. Do not edit manually."
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
