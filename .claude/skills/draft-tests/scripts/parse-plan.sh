#!/bin/bash
# parse-plan.sh -- Phase 1 plan parser for /draft-tests.
#
# Reads a plan file, classifies phases (Completed vs Pending), detects
# delegate vs non-delegate Pending phases, computes SHA-256 checksums of
# Completed phase sections (with fenced-code-block-aware boundaries),
# detects ac-less Pending phases, assigns AC IDs to Pending phases that
# lack them, mutates the plan file in place to add AC-ID prefixes, and
# writes a parsed-state file persisting all of the above.
#
# Usage:
#   bash parse-plan.sh <plan-file> <state-out>
#
# Arguments:
#   <plan-file>  Path to the plan .md file. Mutated in place when AC-ID
#                assignment finds Pending-phase ACs without canonical IDs.
#                Completed-phase sections are NEVER mutated.
#   <state-out>  Path to write the parsed-state file
#                (e.g., /tmp/draft-tests-parsed-<slug>.md).
#
# The parsed-state file contains, line by line:
#   plan_file: <path>
#   frontmatter_title: <title-or-empty>
#   frontmatter_status: <status-or-empty>
#   completed_phases:
#     <phase-id>:<sha256>
#     ...
#   pending_phases:
#     <phase-id>
#     ...
#   non_delegate_pending_phases:
#     <phase-id>
#     ...
#   delegate_phases:
#     <phase-id>
#     ...
#   ac_less:
#     <phase-id>
#     ...
#   advisories:
#     <line>
#     ...
#
# Section-boundary rule (broad form, fenced-code-block-aware): a section
# spans from `## Phase N` through the byte just before the next line that
# starts with `## ` at column 0 AND is NOT inside a fenced ``` block, OR
# end of file, whichever comes first. ANY level-2 heading outside fences
# terminates -- not a closed list of named sections.
#
# AC-ID assignment (per WI 1.6): three predicates evaluated in order:
#   1. Already-prefixed canonical: ^- \[[ xX]\] AC-[0-9]+[a-z]?\.[0-9]+[a-z]?  -- skip (idempotent).
#   2. Ambiguous prefix: ^- \[[ xX]\] (?:[0-9A-Z]|\[) but not (1) -- refuse, advisory.
#   3. Plain (lowercase / backtick / non-digit-non-uppercase head) -- assign AC-<phase>.<n>.
#
# Refuses to mutate Completed phases. Refuses to mutate bullets outside
# `### Acceptance Criteria` blocks.

set -eu

PLAN_FILE="${1:-}"
STATE_OUT="${2:-}"

if [ -z "$PLAN_FILE" ] || [ -z "$STATE_OUT" ]; then
  echo "Usage: $0 <plan-file> <state-out>" >&2
  exit 2
fi

if [ ! -f "$PLAN_FILE" ]; then
  echo "Error: plan file '$PLAN_FILE' not found." >&2
  exit 3
fi

# Ensure the state file is created fresh.
: > "$STATE_OUT"

# ----------------------------------------------------------------------
# Pass 1 -- read the file into an array, strip CR if any.
# ----------------------------------------------------------------------
mapfile -t LINES < "$PLAN_FILE"
N=${#LINES[@]}

# ----------------------------------------------------------------------
# Pass 2 -- frontmatter extraction (between the first two `---` lines).
# ----------------------------------------------------------------------
fm_title=""
fm_status=""
in_fm=0
fm_seen_open=0
fm_end=-1
for ((i=0; i<N; i++)); do
  line="${LINES[$i]}"
  if [ $i -eq 0 ] && [ "$line" = "---" ]; then
    in_fm=1
    fm_seen_open=1
    continue
  fi
  if [ $in_fm -eq 1 ] && [ "$line" = "---" ]; then
    fm_end=$i
    in_fm=0
    break
  fi
  if [ $in_fm -eq 1 ]; then
    if [[ "$line" =~ ^title:[[:space:]]*(.*)$ ]]; then
      fm_title="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^status:[[:space:]]*(.*)$ ]]; then
      fm_status="${BASH_REMATCH[1]}"
    fi
  fi
done

# If frontmatter never closed, treat as no frontmatter. fm_end = -1.

# ----------------------------------------------------------------------
# Pass 3 -- detect Progress Tracker presence.
# Refuse to run if no Progress Tracker.
# ----------------------------------------------------------------------
have_tracker=0
tracker_start=-1
tracker_end=-1
for ((i=0; i<N; i++)); do
  if [[ "${LINES[$i]}" =~ ^##[[:space:]]+Progress[[:space:]]+Tracker ]]; then
    have_tracker=1
    tracker_start=$i
    break
  fi
done
if [ $have_tracker -eq 1 ]; then
  # Tracker ends at the next blank-line followed by non-table content,
  # or at the next `## ` heading. We bound by the next `## ` heading.
  for ((j=tracker_start+1; j<N; j++)); do
    if [[ "${LINES[$j]}" =~ ^##[[:space:]] ]]; then
      tracker_end=$((j-1))
      break
    fi
  done
  if [ $tracker_end -eq -1 ]; then
    tracker_end=$((N-1))
  fi
fi

if [ $have_tracker -eq 0 ]; then
  echo "Error: no Progress Tracker section in '$PLAN_FILE'." >&2
  exit 4
fi

# ----------------------------------------------------------------------
# Pass 4 -- parse the Progress Tracker rows to learn each phase's status.
# Row format: | <phase-id-and-name> | <status> | ... | ... |
# Phase-id form: "1", "1a", "3b-i". We extract whatever leads the name
# before " — " or " -- ".
# ----------------------------------------------------------------------
declare -A PHASE_STATUS  # phase-id -> raw status string
declare -a TRACKER_PHASE_IDS
for ((i=tracker_start; i<=tracker_end; i++)); do
  line="${LINES[$i]}"
  # Skip header / separator / non-table lines.
  if [[ ! "$line" =~ ^\| ]]; then continue; fi
  if [[ "$line" =~ ^\|[[:space:]]*Phase[[:space:]]*\| ]]; then continue; fi
  if [[ "$line" =~ ^\|[[:space:]]*-+ ]]; then continue; fi
  # Tokenize on '|'. With leading and trailing pipes, fields are
  # 0:empty, 1:phase, 2:status, 3:commit, 4:notes, 5:empty.
  IFS='|' read -ra FIELDS <<< "$line"
  if [ ${#FIELDS[@]} -lt 3 ]; then continue; fi
  raw_phase="${FIELDS[1]}"
  raw_status="${FIELDS[2]}"
  # Trim leading/trailing whitespace.
  phase_trim="$(printf '%s' "$raw_phase" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  status_trim="$(printf '%s' "$raw_status" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  # Phase id is the leading token before any " — " or " -- ".
  # Use awk-style POSIX: split on em-dash or double-dash.
  if [[ "$phase_trim" =~ ^([^[:space:]]+)([[:space:]]+(—|--).*)?$ ]]; then
    phase_id="${BASH_REMATCH[1]}"
  else
    phase_id="$phase_trim"
  fi
  PHASE_STATUS["$phase_id"]="$status_trim"
  TRACKER_PHASE_IDS+=("$phase_id")
done

# Classify status (Completed vs Pending). `/refine-plan`'s rules:
# Completed: contains "Done" (case-insensitive, as a word) / `✅` /
# `[x]` (case-insensitive on the bracketed form). Everything else ->
# Pending — including `⬚`, `⬜`, `In Progress`, `Blocked`, empty cells,
# or any other glyph.
is_completed_status() {
  local s="$1"
  local lc
  lc="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')"
  if [[ "$s" == *"✅"* ]]; then return 0; fi
  if [[ "$lc" == *"[x]"* ]]; then return 0; fi
  # Match "done" as a token (boundaries: start/end-of-string or non-letter).
  if [[ "$lc" =~ (^|[^a-z])done([^a-z]|$) ]]; then
    return 0
  fi
  return 1
}

# ----------------------------------------------------------------------
# Pass 5 -- locate phase sections in the plan body and compute their
# extents. A "phase" heading is `## Phase <id>` at column 0 outside a
# fenced code block.
# ----------------------------------------------------------------------
declare -a PHASE_LINE_START
declare -a PHASE_LINE_END
declare -a PHASE_IDS_BODY  # phase ids in order they appear in body
in_code=0
# Track every level-2 heading (any `## ` at col 0 outside fences) so the
# section-boundary scan terminates correctly on non-canonical headings.
declare -a L2_INDICES
declare -a L2_IS_PHASE
for ((i=0; i<N; i++)); do
  line="${LINES[$i]}"
  # Detect fenced code block toggle. ATX rule: a line starting with ```
  # (any number of backticks) toggles in_code. We anchor to col 0.
  if [[ "$line" =~ ^\`\`\` ]]; then
    in_code=$((1 - in_code))
    continue
  fi
  if [ $in_code -ne 0 ]; then continue; fi
  if [[ "$line" =~ ^##[[:space:]] ]]; then
    L2_INDICES+=("$i")
    if [[ "$line" =~ ^##[[:space:]]+Phase[[:space:]]+([^[:space:]]+) ]]; then
      phase_id="${BASH_REMATCH[1]}"
      # Strip a trailing colon if any.
      phase_id="${phase_id%:}"
      PHASE_IDS_BODY+=("$phase_id")
      PHASE_LINE_START+=("$i")
      L2_IS_PHASE+=("1")
    else
      L2_IS_PHASE+=("0")
    fi
  fi
done

# Compute end line for each Phase: one less than the next L2 heading,
# or N-1 if last.
NUM_PHASES=${#PHASE_IDS_BODY[@]}
NUM_L2=${#L2_INDICES[@]}
for ((k=0; k<NUM_PHASES; k++)); do
  start_line=${PHASE_LINE_START[$k]}
  end_line=$((N-1))
  # Find the next L2 heading after start_line.
  for ((m=0; m<NUM_L2; m++)); do
    li=${L2_INDICES[$m]}
    if [ $li -gt $start_line ]; then
      end_line=$((li - 1))
      break
    fi
  done
  PHASE_LINE_END+=("$end_line")
done

# ----------------------------------------------------------------------
# Pass 6 -- for each phase, classify and (if Completed) compute checksum.
# Build the lists in classification order.
# ----------------------------------------------------------------------
declare -a COMPLETED_LIST   # "phase_id:sha256"
declare -a PENDING_LIST     # phase_id
declare -a DELEGATE_LIST    # phase_id (subset of PENDING_LIST)
declare -a NONDELEGATE_LIST # phase_id (subset of PENDING_LIST)
declare -a AC_LESS_LIST     # phase_id (subset of NONDELEGATE_LIST that lacks an AC block)
declare -a ADVISORIES

for ((k=0; k<NUM_PHASES; k++)); do
  pid="${PHASE_IDS_BODY[$k]}"
  start_line=${PHASE_LINE_START[$k]}
  end_line=${PHASE_LINE_END[$k]}
  # Classify via Progress Tracker status. If the Progress Tracker has no
  # row for this phase id, treat as Pending (everything-else default).
  raw_status="${PHASE_STATUS[$pid]:-}"
  if is_completed_status "$raw_status"; then
    # Compute SHA-256 of section bytes (lines start..end) preserving
    # newlines exactly as in the source. Use printf so we don't double a
    # trailing newline; output mapfile-stripped trailing newline of the
    # source via read -- we reconstruct by joining with \n and adding a
    # trailing \n iff the original file had one (mapfile strips it from
    # the last element only).
    tmp_section="$(mktemp)"
    {
      for ((j=start_line; j<=end_line; j++)); do
        printf '%s\n' "${LINES[$j]}"
      done
    } > "$tmp_section"
    sha=$(sha256sum "$tmp_section" | awk '{print $1}')
    rm -f "$tmp_section"
    COMPLETED_LIST+=("${pid}:${sha}")
    continue
  fi
  # Pending.
  PENDING_LIST+=("$pid")
  # Detect delegate via `### Execution: delegate` predicate within phase body.
  is_delegate=0
  for ((j=start_line; j<=end_line; j++)); do
    if [[ "${LINES[$j]}" =~ ^###[[:space:]]+Execution:[[:space:]]+delegate ]]; then
      is_delegate=1
      break
    fi
  done
  if [ $is_delegate -eq 1 ]; then
    DELEGATE_LIST+=("$pid")
  else
    NONDELEGATE_LIST+=("$pid")
  fi
done

# ----------------------------------------------------------------------
# Pass 7 -- AC-ID assignment for every Pending phase that has an
# `### Acceptance Criteria` block. Mutates LINES in memory; we'll write
# back to the plan file at the end.
#
# For Pending phases lacking an AC block: append phase id to AC_LESS_LIST
# AND emit an advisory line.
#
# Three predicates per bullet:
#   (1) canonical pre-existing -- skip
#   (2) ambiguous prefix -- refuse, advisory
#   (3) plain -- assign
# ----------------------------------------------------------------------

# Canonical pre-existing AC bullet:
RE_CANONICAL='^- \[[ xX]\] AC-[0-9]+[a-z]?\.[0-9]+[a-z]? — '
# Ambiguous prefix detection (POST `- [ ] ` head):
# Begins with a digit, capital letter, or literal `[`.
# We must NOT match the canonical (which starts with capital A in "AC-").
# Implementation: test canonical first; if not canonical, test ambiguous.
RE_AMBIG_HEAD='^- \[[ xX]\] (\[|[0-9]|[A-Z])'

declare -a MUTATED_LINES
mutated_any=0

# Iterate all phases in body order; mutate AC bullets only inside
# Pending phases' AC blocks.
for ((k=0; k<NUM_PHASES; k++)); do
  pid="${PHASE_IDS_BODY[$k]}"
  start_line=${PHASE_LINE_START[$k]}
  end_line=${PHASE_LINE_END[$k]}

  # Skip Completed phases.
  raw_status="${PHASE_STATUS[$pid]:-}"
  if is_completed_status "$raw_status"; then
    continue
  fi

  # Find the `### Acceptance Criteria` block inside this phase. The block
  # extends from `### Acceptance Criteria` heading to the next `### ` or
  # `## ` heading.
  ac_start=-1
  ac_end=-1
  for ((j=start_line; j<=end_line; j++)); do
    if [[ "${LINES[$j]}" =~ ^###[[:space:]]+Acceptance[[:space:]]+Criteria ]]; then
      ac_start=$j
      break
    fi
  done
  if [ $ac_start -eq -1 ]; then
    # Pending phase with no AC block -- ac-less.
    AC_LESS_LIST+=("$pid")
    ADVISORIES+=("Phase $pid has no \`### Acceptance Criteria\` block — \`### Tests\` not appended; consider adding ACs and re-running.")
    continue
  fi
  # Find AC block end: next ### or ## heading after ac_start.
  for ((j=ac_start+1; j<=end_line; j++)); do
    if [[ "${LINES[$j]}" =~ ^###[[:space:]] ]] || [[ "${LINES[$j]}" =~ ^##[[:space:]] ]]; then
      ac_end=$((j-1))
      break
    fi
  done
  if [ $ac_end -eq -1 ]; then
    ac_end=$end_line
  fi

  # Walk bullets inside the AC block. Track increment counter PER PHASE.
  bullet_counter=0
  # First pass: count existing canonical bullets to set bullet_counter
  # baseline so newly-assigned IDs don't collide. We use the running max
  # of the trailing `<n>` in the canonical AC-<phase>.<n> form (only for
  # bullets matching this phase's own id).
  highest=0
  for ((j=ac_start+1; j<=ac_end; j++)); do
    line="${LINES[$j]}"
    if [[ "$line" =~ ^-[[:space:]]\[[\ xX]\][[:space:]]AC-([0-9]+[a-z]?)\.([0-9]+)[a-z]?[[:space:]]—[[:space:]] ]]; then
      m_phase="${BASH_REMATCH[1]}"
      m_n="${BASH_REMATCH[2]}"
      if [ "$m_phase" = "$pid" ] && [ "$m_n" -gt "$highest" ]; then
        highest="$m_n"
      fi
    fi
  done
  bullet_counter=$highest

  # Second pass: assign / refuse / skip.
  for ((j=ac_start+1; j<=ac_end; j++)); do
    line="${LINES[$j]}"
    # Predicate 1: already canonical -> skip (idempotent).
    if [[ "$line" =~ $RE_CANONICAL ]]; then
      continue
    fi
    # Bullet detection: must start with `- [ ]`, `- [x]`, or `- [X]`.
    if [[ ! "$line" =~ ^-[[:space:]]\[[\ xX]\][[:space:]] ]]; then
      continue
    fi
    # Predicate 2: ambiguous prefix -> refuse, emit advisory.
    if [[ "$line" =~ $RE_AMBIG_HEAD ]]; then
      lineno=$((j+1))
      # Plan path is reported as-given to the script (caller's choice of relative/abs).
      ADVISORIES+=("Refused AC-ID assignment for \"$PLAN_FILE:$lineno\" — ambiguous prefix; rewrite to canonical \"AC-N.M — text\" form to enable assignment.")
      continue
    fi
    # Predicate 3: plain -> assign.
    bullet_counter=$((bullet_counter + 1))
    # Capture the head: `- [<x>] ` and the rest.
    # Use a regex with three groups: prefix, checkbox, text.
    if [[ "$line" =~ ^(-[[:space:]]\[[\ xX]\][[:space:]])(.*)$ ]]; then
      head="${BASH_REMATCH[1]}"
      rest="${BASH_REMATCH[2]}"
      LINES[$j]="${head}AC-${pid}.${bullet_counter} — ${rest}"
      mutated_any=1
    fi
  done
done

# ----------------------------------------------------------------------
# Pass 8 -- write the mutated lines back to the plan file (only if
# mutations were made). Preserve trailing newline behaviour.
# ----------------------------------------------------------------------
if [ "$mutated_any" -eq 1 ]; then
  tmp_out="$(mktemp)"
  {
    for ((i=0; i<N; i++)); do
      printf '%s\n' "${LINES[$i]}"
    done
  } > "$tmp_out"
  # Preserve original trailing-newline state. mapfile strips a single
  # trailing newline from the final element if present, so the rebuild
  # by-default re-adds one. Detect the original state and adjust.
  if [ "$(tail -c1 "$PLAN_FILE" | od -An -c | tr -d ' ')" != '\n' ]; then
    # Original had no trailing newline -- truncate the extra one we added.
    truncate -s -1 "$tmp_out"
  fi
  mv "$tmp_out" "$PLAN_FILE"
fi

# ----------------------------------------------------------------------
# Pass 9 -- write the parsed-state file.
# ----------------------------------------------------------------------
{
  printf 'plan_file: %s\n' "$PLAN_FILE"
  printf 'frontmatter_title: %s\n' "$fm_title"
  printf 'frontmatter_status: %s\n' "$fm_status"
  printf 'completed_phases:\n'
  for entry in "${COMPLETED_LIST[@]:-}"; do
    [ -z "$entry" ] && continue
    printf '  %s\n' "$entry"
  done
  printf 'pending_phases:\n'
  for pid in "${PENDING_LIST[@]:-}"; do
    [ -z "$pid" ] && continue
    printf '  %s\n' "$pid"
  done
  printf 'non_delegate_pending_phases:\n'
  for pid in "${NONDELEGATE_LIST[@]:-}"; do
    [ -z "$pid" ] && continue
    printf '  %s\n' "$pid"
  done
  printf 'delegate_phases:\n'
  for pid in "${DELEGATE_LIST[@]:-}"; do
    [ -z "$pid" ] && continue
    printf '  %s\n' "$pid"
  done
  printf 'ac_less:\n'
  for pid in "${AC_LESS_LIST[@]:-}"; do
    [ -z "$pid" ] && continue
    printf '  %s\n' "$pid"
  done
  printf 'advisories:\n'
  for adv in "${ADVISORIES[@]:-}"; do
    [ -z "$adv" ] && continue
    printf '  %s\n' "$adv"
  done
} > "$STATE_OUT"

# ----------------------------------------------------------------------
# Pass 10 -- emit advisories to stderr so the orchestrator (SKILL.md)
# can include them in its final output.
# ----------------------------------------------------------------------
for adv in "${ADVISORIES[@]:-}"; do
  [ -z "$adv" ] && continue
  printf '%s\n' "$adv" >&2
done

# ----------------------------------------------------------------------
# Pass 11 -- the "nothing to draft or backfill" exit-clean check is the
# orchestrator's call (it knows whether Phase 5's gap detection found
# anything). This script just reports the parsed state. The SKILL.md body
# inspects pending_phases + completed_phases + (Phase-5-gap-detection)
# and decides exit cleanliness.
exit 0
