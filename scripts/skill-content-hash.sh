#!/bin/bash
export LC_ALL=C
# skill-content-hash.sh — Compute the 6-char canonical-projection hash
# for a skill directory.
#
# Usage:
#   skill-content-hash.sh <skill-dir>
#
# Projection (per references/skill-versioning.md §1.1 / §1.3):
#   1. Redacted-frontmatter snapshot of `<skill-dir>/SKILL.md` — the
#      whole frontmatter block (between the first and second `---`),
#      with the `metadata.version` line replaced by
#      `<original-leading-whitespace>version: "<REDACTED>"`. Other keys
#      (including block scalars like `description: >-`) preserved
#      verbatim. The redactor uses block-scalar-aware indent traversal
#      so a `description-extra: >-` continuation line that LITERALLY
#      contains `version: "X"` text is left untouched.
#   2. SKILL.md body — everything below the closing `---`.
#   3. Every regular file under `<skill-dir>/` (recursive), excluding
#      SKILL.md, dotfiles (`.*`), `__pycache__/`, `node_modules/`.
#      Binary files are rejected (exit 1).
#
# Per-file normalisation: strip trailing whitespace per line; CRLF →
# LF; ensure single trailing newline.
#
# Concatenation: each component (and each file inside component 3) is
# preceded by `=== <relative-path> ===` (frontmatter and body use the
# pseudo-paths shown below). Components are joined with single LF.
#
# Output: `sha256sum | cut -d' ' -f1 | head -c 6` of the projection.
#
# Exit codes:
#   0  success — 6-char hex hash printed
#   1  error (missing SKILL.md, binary file, etc.) — message to stderr
#
# No external JSON tools. Pure bash + awk + coreutils, all under
# `LC_ALL=C` (script-wide export above; per-command prefixes are not needed).

set -eu

if [ $# -ne 1 ]; then
  echo "ERROR: usage: $(basename "$0") <skill-dir>" >&2
  exit 1
fi

SKILL_DIR="$1"
SKILL_DIR="${SKILL_DIR%/}"

if [ ! -d "$SKILL_DIR" ]; then
  echo "ERROR: not a directory: $SKILL_DIR" >&2
  exit 1
fi

SKILL_MD="$SKILL_DIR/SKILL.md"
if [ ! -f "$SKILL_MD" ]; then
  echo "ERROR: missing SKILL.md: $SKILL_MD" >&2
  exit 1
fi

# ----------------------------------------------------------------------
# Helpers.
# ----------------------------------------------------------------------

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

# Normalise a file's content: CRLF→LF, strip trailing whitespace per
# line, ensure single trailing newline. Reads from $1, writes to stdout.
normalise_file() {
  local f="$1"
  awk '
    {
      sub(/\r$/, "")           # strip CR (CRLF→LF)
      sub(/[ \t]+$/, "")        # strip trailing whitespace
      print
    }
  ' "$f"
}

# Verify a file is text (not binary). Exit 1 with error if binary.
# Empty files are treated as text per spec.
guard_text() {
  local f="$1"
  if [ ! -s "$f" ]; then
    return 0
  fi
  if file --mime "$f" | grep -qi 'charset=binary'; then
    echo "ERROR: binary file in skill projection: $f" >&2
    exit 1
  fi
}

# ----------------------------------------------------------------------
# Build projection in a temp file.
# ----------------------------------------------------------------------

PROJ=$(mktemp)
trap 'rm -f "$PROJ"' EXIT

# Read SKILL.md into an array.
mapfile -t SLINES < "$SKILL_MD"
SN=${#SLINES[@]}

if [ "$SN" -eq 0 ] || [ "${SLINES[0]}" != "---" ]; then
  echo "ERROR: SKILL.md missing frontmatter: $SKILL_MD" >&2
  exit 1
fi

FM_END=-1
for ((i=1; i<SN; i++)); do
  if [ "${SLINES[$i]}" = "---" ]; then
    FM_END=$i
    break
  fi
done
if [ "$FM_END" -eq -1 ]; then
  echo "ERROR: SKILL.md frontmatter has no closing '---': $SKILL_MD" >&2
  exit 1
fi

# ----- Component 1: redacted frontmatter snapshot -----
{
  printf '=== <frontmatter> ===\n'
  printf '%s\n' "${SLINES[0]}"
  i=1
  in_metadata=0
  metadata_indent=-1
  while [ "$i" -lt "$FM_END" ]; do
    line="${SLINES[$i]}"

    if [ -z "$line" ] || [[ "$line" =~ ^[[:space:]]*$ ]]; then
      printf '%s\n' "$line"
      i=$((i+1)); continue
    fi

    ind=$(indent_of "$line")

    # Track entering / leaving the `metadata:` parent.
    if [ "$ind" -eq 0 ]; then
      if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_-]*):[[:space:]]*(.*)$ ]]; then
        lk="${BASH_REMATCH[1]}"
        if [ "$lk" = "metadata" ]; then
          in_metadata=1
          metadata_indent=0
          printf '%s\n' "$line"
          i=$((i+1)); continue
        else
          in_metadata=0
          # Block-scalar passthrough: write key line + skip continuation
          # lines verbatim WITHOUT scanning them for `version:` matches.
          if is_block_scalar_intro "$line"; then
            printf '%s\n' "$line"
            j=$((i+1))
            while [ "$j" -lt "$FM_END" ]; do
              cline="${SLINES[$j]}"
              if [ -z "$cline" ] || [[ "$cline" =~ ^[[:space:]]*$ ]]; then
                printf '%s\n' "$cline"
                j=$((j+1)); continue
              fi
              cind=$(indent_of "$cline")
              if [ "$cind" -le 0 ]; then
                break
              fi
              # Verbatim — do NOT inspect for `version:`.
              printf '%s\n' "$cline"
              j=$((j+1))
            done
            i=$j
            continue
          fi
          printf '%s\n' "$line"
          i=$((i+1)); continue
        fi
      fi
      printf '%s\n' "$line"
      i=$((i+1)); continue
    fi

    # Indented (child) line.
    if [ "$in_metadata" -eq 1 ]; then
      stripped="${line#"${line%%[![:space:]]*}"}"
      stripped_trim="${stripped%"${stripped##*[![:space:]]}"}"
      # Match exactly `version: "..."` after stripping leading ws.
      if [[ "$stripped_trim" =~ ^version:[[:space:]]*\".*\"[[:space:]]*$ ]]; then
        # Preserve leading whitespace exactly.
        pad=""
        for ((p=0; p<ind; p++)); do pad="$pad "; done
        printf '%s\n' "${pad}version: \"<REDACTED>\""
        i=$((i+1)); continue
      fi
      # Skip block scalars under metadata (verbatim).
      if is_block_scalar_intro "$line"; then
        printf '%s\n' "$line"
        j=$((i+1))
        while [ "$j" -lt "$FM_END" ]; do
          cline="${SLINES[$j]}"
          if [ -z "$cline" ] || [[ "$cline" =~ ^[[:space:]]*$ ]]; then
            printf '%s\n' "$cline"
            j=$((j+1)); continue
          fi
          cind=$(indent_of "$cline")
          if [ "$cind" -le "$ind" ]; then
            break
          fi
          printf '%s\n' "$cline"
          j=$((j+1))
        done
        i=$j
        continue
      fi
    fi

    printf '%s\n' "$line"
    i=$((i+1))
  done
  printf '%s\n' "${SLINES[$FM_END]}"
} >> "$PROJ"

# Component separator.
printf '\n' >> "$PROJ"

# ----- Component 2: SKILL.md body -----
{
  printf '=== <body> ===\n'
  # Body = lines after FM_END. Write to a temp file, normalise.
  body_tmp=$(mktemp)
  for ((i=FM_END+1; i<SN; i++)); do
    printf '%s\n' "${SLINES[$i]}"
  done > "$body_tmp"
  normalise_file "$body_tmp"
  rm -f "$body_tmp"
} >> "$PROJ"

# Component separator.
printf '\n' >> "$PROJ"

# ----- Component 3: every regular file under skill-dir -----
# Enumerate via find … -print0 | sort -z, then iterate.
files_tmp=$(mktemp)
find "$SKILL_DIR" -type f \
  ! -name SKILL.md \
  ! -name '.*' \
  ! -path '*/__pycache__/*' \
  ! -path '*/node_modules/*' \
  -print0 | sort -z > "$files_tmp"

# Iterate using a NUL delimiter.
while IFS= read -r -d '' f; do
  guard_text "$f"
  rel="${f#"$SKILL_DIR"/}"
  {
    printf '=== %s ===\n' "$rel"
    normalise_file "$f"
  } >> "$PROJ"
  # Single LF separator between files.
  printf '\n' >> "$PROJ"
done < "$files_tmp"
rm -f "$files_tmp"

# ----- Hash -----
sha256sum "$PROJ" | cut -d' ' -f1 | head -c 6
echo
