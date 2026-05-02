#!/bin/bash
# frontmatter-set.sh — Set or insert a YAML frontmatter value, in-place.
#
# Usage:
#   frontmatter-set.sh <file> <dotted-key> <new-value>
#
# Behaviour:
#   * Locates the existing `<key>:` line and rewrites its value, OR
#   * If the key is missing, inserts it at the appropriate indentation.
#   * For a dotted key (e.g. `metadata.version`):
#       - if the parent block exists, inserts the child at the end of
#         that block (2-space indent);
#       - if the parent block is missing, inserts the parent + child
#         immediately before the closing `---`.
#   * Idempotent: if the existing value already equals `<new-value>`,
#     no write happens; exit 0 silently.
#   * Atomic: writes to a temp file then `mv`s into place.
#   * Preserves file mode.
#   * Wraps `<new-value>` in double quotes when writing.
#
# Block-scalar handling:
#   * READS pass through (frontmatter-get.sh).
#   * WRITES are NOT supported. If the target key already exists as a
#     block scalar (`description: >-` followed by indented continuation
#     lines), this helper exits 3 with an error. Phase 4/5 only writes
#     `metadata.version`, which is always single-line.
#
# Exit codes:
#   0  success (or idempotent no-op)
#   2  malformed frontmatter
#   3  attempt to overwrite a block-scalar key
#
# No external JSON tools. Pure bash + awk.

set -eu

if [ $# -ne 3 ]; then
  echo "ERROR: usage: $(basename "$0") <file> <dotted-key> <new-value>" >&2
  exit 2
fi

FILE="$1"
KEY="$2"
NEW_VAL="$3"

if [ ! -f "$FILE" ]; then
  echo "ERROR: file not found: $FILE" >&2
  exit 2
fi

mapfile -t LINES < "$FILE"
N=${#LINES[@]}

if [ "$N" -eq 0 ] || [ "${LINES[0]}" != "---" ]; then
  echo "ERROR: malformed frontmatter — first line is not '---'" >&2
  exit 2
fi

FM_END=-1
for ((i=1; i<N; i++)); do
  if [ "${LINES[$i]}" = "---" ]; then
    FM_END=$i
    break
  fi
done
if [ "$FM_END" -eq -1 ]; then
  echo "ERROR: malformed frontmatter — no closing '---'" >&2
  exit 2
fi

PARENT=""
CHILD=""
if [[ "$KEY" == *.* ]]; then
  PARENT="${KEY%%.*}"
  CHILD="${KEY#*.}"
  if [[ "$CHILD" == *.* ]]; then
    echo "ERROR: only single-level dotted keys are supported (got: $KEY)" >&2
    exit 2
  fi
fi

indent_of() {
  local line="$1"
  local stripped="${line#"${line%%[![:space:]]*}"}"
  echo $(( ${#line} - ${#stripped} ))
}

is_block_scalar_intro() {
  local line="$1"
  if [[ "$line" =~ :[[:space:]]*\>[[:space:]]*$ ]] \
    || [[ "$line" =~ :[[:space:]]*\>-[[:space:]]*$ ]] \
    || [[ "$line" =~ :[[:space:]]*\|[[:space:]]*$ ]] \
    || [[ "$line" =~ :[[:space:]]*\|-[[:space:]]*$ ]]; then
    return 0
  fi
  return 1
}

strip_quotes() {
  local v="$1"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  if [[ "$v" =~ ^\"(.*)\"$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  elif [[ "$v" =~ ^\'(.*)\'$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  else
    printf '%s' "$v"
  fi
}

# Find the line index of an existing top-level key. Returns -1 if not present.
# Skips block-scalar continuations.
find_top_level_key() {
  local target="$1"
  local i=1
  while [ "$i" -lt "$FM_END" ]; do
    local line="${LINES[$i]}"
    if [ -z "$line" ] || [[ "$line" =~ ^[[:space:]]*$ ]]; then
      i=$((i+1)); continue
    fi
    local ind
    ind=$(indent_of "$line")
    if [ "$ind" -eq 0 ] && [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_-]*):[[:space:]]*(.*)$ ]]; then
      local lk="${BASH_REMATCH[1]}"
      if [ "$lk" = "$target" ]; then
        echo "$i"; return 0
      fi
      if is_block_scalar_intro "$line"; then
        # Skip continuation.
        local j=$((i+1))
        while [ "$j" -lt "$FM_END" ]; do
          local cline="${LINES[$j]}"
          if [ -z "$cline" ] || [[ "$cline" =~ ^[[:space:]]*$ ]]; then
            j=$((j+1)); continue
          fi
          local cind
          cind=$(indent_of "$cline")
          if [ "$cind" -le 0 ]; then break; fi
          j=$((j+1))
        done
        i="$j"; continue
      fi
    fi
    i=$((i+1))
  done
  echo "-1"
}

# Find the END index (exclusive) of a parent block — first line at indent
# 0 that is not part of the parent's children. Caller passes the parent's
# line index. Returns FM_END if no further top-level key exists.
parent_block_end() {
  local pidx="$1"
  local j=$((pidx+1))
  while [ "$j" -lt "$FM_END" ]; do
    local line="${LINES[$j]}"
    if [ -z "$line" ] || [[ "$line" =~ ^[[:space:]]*$ ]]; then
      j=$((j+1)); continue
    fi
    local ind
    ind=$(indent_of "$line")
    if [ "$ind" -eq 0 ]; then
      echo "$j"; return 0
    fi
    j=$((j+1))
  done
  echo "$FM_END"
}

# Find a child key inside a parent block. Returns line index, or -1.
find_child_key() {
  local pidx="$1"
  local target="$2"
  local pend
  pend=$(parent_block_end "$pidx")
  local j=$((pidx+1))
  while [ "$j" -lt "$pend" ]; do
    local line="${LINES[$j]}"
    if [ -z "$line" ] || [[ "$line" =~ ^[[:space:]]*$ ]]; then
      j=$((j+1)); continue
    fi
    if [[ "$line" =~ ^[[:space:]]+([A-Za-z_][A-Za-z0-9_-]*):[[:space:]]*(.*)$ ]]; then
      local ck="${BASH_REMATCH[1]}"
      if [ "$ck" = "$target" ]; then
        echo "$j"; return 0
      fi
    fi
    j=$((j+1))
  done
  echo "-1"
}

# Write LINES back to FILE atomically, preserving mode.
write_back() {
  local tmp
  tmp=$(mktemp "${FILE}.XXXXXX")
  local mode
  mode=$(stat -c '%a' "$FILE" 2>/dev/null || stat -f '%Lp' "$FILE")
  local out_n=${#LINES[@]}
  for ((k=0; k<out_n; k++)); do
    printf '%s\n' "${LINES[$k]}" >> "$tmp"
  done
  chmod "$mode" "$tmp"
  mv "$tmp" "$FILE"
}

# ----- Main -----

QUOTED="\"${NEW_VAL}\""

if [ -z "$PARENT" ]; then
  # Top-level key.
  idx=$(find_top_level_key "$KEY")
  if [ "$idx" -ge 0 ]; then
    line="${LINES[$idx]}"
    if is_block_scalar_intro "$line"; then
      echo "ERROR: cannot rewrite block scalar key '$KEY'; use single-line scalar form" >&2
      exit 3
    fi
    # Compare existing value (idempotency).
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_-]*):[[:space:]]*(.*)$ ]]; then
      existing=$(strip_quotes "${BASH_REMATCH[2]}")
      if [ "$existing" = "$NEW_VAL" ]; then
        exit 0
      fi
    fi
    LINES[$idx]="${KEY}: ${QUOTED}"
    write_back
    exit 0
  fi
  # Insert before closing `---`.
  new_lines=()
  for ((k=0; k<N; k++)); do
    if [ "$k" -eq "$FM_END" ]; then
      new_lines+=("${KEY}: ${QUOTED}")
    fi
    new_lines+=("${LINES[$k]}")
  done
  LINES=("${new_lines[@]}")
  write_back
  exit 0
fi

# Dotted key.
pidx=$(find_top_level_key "$PARENT")

if [ "$pidx" -ge 0 ]; then
  pline="${LINES[$pidx]}"
  if is_block_scalar_intro "$pline"; then
    echo "ERROR: parent '$PARENT' is a block scalar; cannot have child '$CHILD'" >&2
    exit 2
  fi
  cidx=$(find_child_key "$pidx" "$CHILD")
  if [ "$cidx" -ge 0 ]; then
    cline="${LINES[$cidx]}"
    if is_block_scalar_intro "$cline"; then
      echo "ERROR: cannot rewrite block scalar key '$KEY'; use single-line scalar form" >&2
      exit 3
    fi
    if [[ "$cline" =~ ^[[:space:]]+([A-Za-z_][A-Za-z0-9_-]*):[[:space:]]*(.*)$ ]]; then
      existing=$(strip_quotes "${BASH_REMATCH[2]}")
      if [ "$existing" = "$NEW_VAL" ]; then
        exit 0
      fi
    fi
    # Preserve original indent.
    cind=$(indent_of "$cline")
    pad=""
    for ((p=0; p<cind; p++)); do pad="$pad "; done
    LINES[$cidx]="${pad}${CHILD}: ${QUOTED}"
    write_back
    exit 0
  fi
  # Insert child at end of parent block.
  pend=$(parent_block_end "$pidx")
  new_lines=()
  for ((k=0; k<N; k++)); do
    if [ "$k" -eq "$pend" ]; then
      new_lines+=("  ${CHILD}: ${QUOTED}")
    fi
    new_lines+=("${LINES[$k]}")
  done
  LINES=("${new_lines[@]}")
  write_back
  exit 0
fi

# Parent missing — insert parent + child before closing `---`.
new_lines=()
for ((k=0; k<N; k++)); do
  if [ "$k" -eq "$FM_END" ]; then
    new_lines+=("${PARENT}:")
    new_lines+=("  ${CHILD}: ${QUOTED}")
  fi
  new_lines+=("${LINES[$k]}")
done
LINES=("${new_lines[@]}")
write_back
exit 0
