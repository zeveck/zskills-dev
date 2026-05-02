#!/bin/bash
# frontmatter-get.sh — Extract a YAML frontmatter value from a markdown file.
#
# Usage:
#   frontmatter-get.sh <file-or-dash> <dotted-key>
#
# Args:
#   <file-or-dash>  Path to a markdown file with YAML frontmatter, or `-`
#                   to read frontmatter from stdin.
#   <dotted-key>    A top-level key (e.g. `name`) or a dotted path
#                   (e.g. `metadata.version`) referring to a 2-space-
#                   indented child under the parent.
#
# Behaviour:
#   * Frontmatter is the block between the first `---` line and the next
#     `---` line.
#   * Block-scalar values (`>`, `>-`, `|`, `|-`) are READ-supported and
#     returned with continuation lines joined by single spaces.
#   * Single-line scalars are returned without surrounding double or
#     single quotes.
#
# Exit codes:
#   0  success — value printed to stdout
#   1  key missing (no stdout output, error to stderr)
#   2  malformed frontmatter (no opening `---`, no closing `---`, etc.)
#
# No external JSON tools. Pure bash + awk.

set -eu

if [ $# -ne 2 ]; then
  echo "ERROR: usage: $(basename "$0") <file-or-dash> <dotted-key>" >&2
  exit 2
fi

SRC="$1"
KEY="$2"

# Read source into an array of lines.
if [ "$SRC" = "-" ]; then
  mapfile -t LINES
else
  if [ ! -f "$SRC" ]; then
    echo "ERROR: file not found: $SRC" >&2
    exit 2
  fi
  mapfile -t LINES < "$SRC"
fi

N=${#LINES[@]}
if [ "$N" -eq 0 ]; then
  echo "ERROR: empty input — no frontmatter" >&2
  exit 2
fi

# Locate frontmatter open/close.
if [ "${LINES[0]}" != "---" ]; then
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

# Split the dotted key.
PARENT=""
CHILD=""
if [[ "$KEY" == *.* ]]; then
  PARENT="${KEY%%.*}"
  CHILD="${KEY#*.}"
  # We only support one level of nesting (metadata.version style).
  if [[ "$CHILD" == *.* ]]; then
    echo "ERROR: only single-level dotted keys are supported (got: $KEY)" >&2
    exit 2
  fi
fi

# Strip surrounding quotes from a single-line scalar value.
strip_quotes() {
  local v="$1"
  # Strip leading/trailing whitespace.
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

# Compute leading-whitespace length of a line.
indent_of() {
  local line="$1"
  local stripped="${line#"${line%%[![:space:]]*}"}"
  echo $(( ${#line} - ${#stripped} ))
}

# Detect a block-scalar indicator at end of a key line. Returns 0 if found.
is_block_scalar_intro() {
  local line="$1"
  # Match: key: <maybe ws> > | >- | |-  optionally followed by trailing ws.
  if [[ "$line" =~ :[[:space:]]*(\>|\>-|\|\|-|\|)[[:space:]]*$ ]]; then
    return 0
  fi
  # The grouping above accidentally allowed `||-`; rewrite cleanly.
  if [[ "$line" =~ :[[:space:]]*\>[[:space:]]*$ ]] \
    || [[ "$line" =~ :[[:space:]]*\>-[[:space:]]*$ ]] \
    || [[ "$line" =~ :[[:space:]]*\|[[:space:]]*$ ]] \
    || [[ "$line" =~ :[[:space:]]*\|-[[:space:]]*$ ]]; then
    return 0
  fi
  return 1
}

# Read a block scalar starting at index `start` whose key indent is
# `key_indent`. Continuation lines have indent > key_indent. Joins them
# with single spaces, trimming each line. Echoes the joined value. Sets
# global LAST_BLOCK_END to the index of the last continuation line (so
# callers can advance i past it).
LAST_BLOCK_END=0
read_block_scalar() {
  local start="$1"
  local key_indent="$2"
  local j parts="" part_indent line stripped
  LAST_BLOCK_END=$((start - 1))
  for ((j=start; j<FM_END; j++)); do
    line="${LINES[$j]}"
    # Treat blank lines as continuations.
    if [ -z "$line" ] || [[ "$line" =~ ^[[:space:]]*$ ]]; then
      LAST_BLOCK_END=$j
      continue
    fi
    part_indent=$(indent_of "$line")
    if [ "$part_indent" -le "$key_indent" ]; then
      break
    fi
    stripped="${line#"${line%%[![:space:]]*}"}"
    stripped="${stripped%"${stripped##*[![:space:]]}"}"
    if [ -z "$parts" ]; then
      parts="$stripped"
    else
      parts="$parts $stripped"
    fi
    LAST_BLOCK_END=$j
  done
  printf '%s' "$parts"
}

# Walk the frontmatter, tracking parent context.
i=1
while [ "$i" -lt "$FM_END" ]; do
  line="${LINES[$i]}"

  # Blank line — skip.
  if [ -z "$line" ] || [[ "$line" =~ ^[[:space:]]*$ ]]; then
    i=$((i+1))
    continue
  fi

  # Compute indent.
  ind=$(indent_of "$line")

  # Top-level (indent 0) lines are candidate keys / parents.
  if [ "$ind" -eq 0 ]; then
    # Match `key:` (maybe with trailing value).
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_-]*):[[:space:]]*(.*)$ ]]; then
      lk="${BASH_REMATCH[1]}"
      lv="${BASH_REMATCH[2]}"

      # Top-level match (no dot in KEY).
      if [ -z "$PARENT" ] && [ "$lk" = "$KEY" ]; then
        if is_block_scalar_intro "$line"; then
          val=$(read_block_scalar $((i+1)) 0)
          printf '%s\n' "$val"
          exit 0
        fi
        printf '%s\n' "$(strip_quotes "$lv")"
        exit 0
      fi

      # Parent match — descend.
      if [ -n "$PARENT" ] && [ "$lk" = "$PARENT" ]; then
        # Parent is expected to be a mapping with no inline value (or
        # an empty value). We scan forward for child keys at indent > 0.
        j=$((i+1))
        while [ "$j" -lt "$FM_END" ]; do
          cline="${LINES[$j]}"
          if [ -z "$cline" ] || [[ "$cline" =~ ^[[:space:]]*$ ]]; then
            j=$((j+1))
            continue
          fi
          cind=$(indent_of "$cline")
          if [ "$cind" -eq 0 ]; then
            # Left the parent block.
            break
          fi
          # Child-key match.
          if [[ "$cline" =~ ^[[:space:]]+([A-Za-z_][A-Za-z0-9_-]*):[[:space:]]*(.*)$ ]]; then
            ck="${BASH_REMATCH[1]}"
            cv="${BASH_REMATCH[2]}"
            if [ "$ck" = "$CHILD" ]; then
              if is_block_scalar_intro "$cline"; then
                val=$(read_block_scalar $((j+1)) "$cind")
                printf '%s\n' "$val"
                exit 0
              fi
              printf '%s\n' "$(strip_quotes "$cv")"
              exit 0
            fi
            # Skip child's own block scalar continuation if present.
            if is_block_scalar_intro "$cline"; then
              read_block_scalar $((j+1)) "$cind" >/dev/null
              j=$((LAST_BLOCK_END+1))
              continue
            fi
          fi
          j=$((j+1))
        done
        # Parent was matched but child not found — key missing.
        echo "ERROR: key not found: $KEY" >&2
        exit 1
      fi

      # Top-level key that we didn't want — but if it's a block scalar,
      # skip its continuation lines so we don't accidentally interpret
      # them as new keys.
      if is_block_scalar_intro "$line"; then
        read_block_scalar $((i+1)) 0 >/dev/null
        i=$((LAST_BLOCK_END+1))
        continue
      fi
    fi
  fi

  i=$((i+1))
done

echo "ERROR: key not found: $KEY" >&2
exit 1
