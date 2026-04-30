#!/bin/bash
# append-backfill-phase.sh -- Phase 5 WI 5.2 + 5.3 + 5.3b backfill phase
# inserter for /draft-tests.
#
# Reads a gap-detection output file (from gap-detect.sh) and the parsed-
# state file (from parse-plan.sh), then:
#
#   1. Clusters Completed phases flagged MISSING into groups of 1-3 (per
#      WI 5.2 / AC-5.4 -- multiple backfill phases for >= 4 MISSING
#      Completed phases, never one mega-phase).
#   2. For each cluster, appends a NEW level-2 phase
#      `## Phase N -- Backfill tests for completed phases X[, Y][, Z]`
#      at the structurally correct position -- IMMEDIATELY BEFORE the
#      first trailing non-phase level-2 heading after the last
#      `## Phase` (broad form: ANY `## <name>` outside fenced code blocks
#      terminates the scan, NOT a closed enumeration). The
#      Progress Tracker also gains a new row per backfill phase.
#   3. Authors each backfill phase's body: Goal, Work Items (one per AC
#      gap), Design & Constraints, Acceptance Criteria, Dependencies.
#      The new ACs use a backfill-local ID `AC-<backfill-phase>.<n>`
#      that aliases the original.
#   4. Updates the parsed-state file: appends each backfill phase id to
#      `non_delegate_pending_phases:` and `pending_phases:` (per WI
#      5.3b / AC-5.10 -- backfill phases enrolled in coverage floor).
#
# Heading form (verbatim):
#   ## Phase N -- Backfill tests for completed phases X[, Y][, Z]
#   (where N is one greater than the current max phase number, including
#   sub-letters)
#
# Section-boundary scanning is fenced-code-block-aware (mirrors
# parse-plan.sh's invariant): `\`\`\`` toggles in_code; heading
# detection runs only when in_code == 0.
#
# Usage:
#   bash append-backfill-phase.sh \
#       <plan-file> <parsed-state> <gaps-file> <backfill-out>
#
# Arguments:
#   <plan-file>     Path to the plan .md file. Mutated in place: backfill
#                   phase headings are inserted before trailing
#                   non-phase level-2 sections; Progress Tracker rows are
#                   appended.
#   <parsed-state>  Phase 1 parsed-state file. Mutated in place: backfill
#                   phase ids are appended to `non_delegate_pending_phases:`
#                   and `pending_phases:`.
#   <gaps-file>     Phase 5 gap-detect output file with `missing_phases:`
#                   list.
#   <backfill-out>  Output file describing the backfill action. Format:
#                     backfill_phases:
#                       <new-phase-id>:<comma-separated-source-phase-ids>
#                       ...
#                     missing_acs:
#                       <new-phase-id>:<comma-separated-AC-ids>
#                       ...
#
# Exit codes:
#   0 -- backfill phases appended (or no MISSING phases, in which case
#        the plan and parsed-state are untouched and backfill-out is
#        empty).
#   2 -- usage error.
#   3 -- input file missing.

set -eu

PLAN_FILE="${1:-}"
PARSED_STATE="${2:-}"
GAPS_FILE="${3:-}"
BACKFILL_OUT="${4:-}"

if [ -z "$PLAN_FILE" ] || [ -z "$PARSED_STATE" ] \
   || [ -z "$GAPS_FILE" ] || [ -z "$BACKFILL_OUT" ]; then
  echo "Usage: $0 <plan-file> <parsed-state> <gaps-file> <backfill-out>" >&2
  exit 2
fi

for f in "$PLAN_FILE" "$PARSED_STATE" "$GAPS_FILE"; do
  if [ ! -f "$f" ]; then
    echo "Error: input file '$f' not found." >&2
    exit 3
  fi
done

# ----------------------------------------------------------------------
# Read missing_phases from gaps-file. Each entry is `pid:ac1,ac2,...`.
# ----------------------------------------------------------------------
read_state_list() {
  local state_file="$1"
  local key="$2"
  awk -v k="$key:" '
    $0 == k { active=1; next }
    active && /^  / { sub(/^  /, ""); print; next }
    active && /^[^ ]/ { active=0 }
  ' "$state_file"
}

mapfile -t MISSING_ENTRIES < <(read_state_list "$GAPS_FILE" missing_phases)

# Filter out empty entries.
declare -a MISSING_PIDS=()
declare -A MISSING_ACS_BY_PID=()
for e in "${MISSING_ENTRIES[@]:-}"; do
  [ -z "$e" ] && continue
  pid="${e%%:*}"
  acs="${e#*:}"
  MISSING_PIDS+=("$pid")
  MISSING_ACS_BY_PID["$pid"]="$acs"
done

# Empty backfill-out file by default.
: > "$BACKFILL_OUT"

if [ "${#MISSING_PIDS[@]}" -eq 0 ]; then
  # No MISSING phases -- write empty headers and exit clean. Note:
  # `declare -a FOO=()` initialises an empty array so `${#FOO[@]}` is
  # 0 under `set -u`. Without `=()`, the variable would be unset and
  # the length probe would trip the unbound-variable trap.
  {
    printf 'backfill_phases:\n'
    printf 'missing_acs:\n'
  } > "$BACKFILL_OUT"
  exit 0
fi

# ----------------------------------------------------------------------
# Determine the next phase number. We need to find the maximum existing
# phase number (numeric leading part) across the plan body. Sub-letter
# forms like "5b" still have leading numeric "5" -- the next backfill
# starts at max+1.
# ----------------------------------------------------------------------
mapfile -t PLAN_LINES < "$PLAN_FILE"
NLINES=${#PLAN_LINES[@]}

max_phase_num=0
in_code=0
declare -a EXISTING_PHASE_LINES
for ((i=0; i<NLINES; i++)); do
  line="${PLAN_LINES[$i]}"
  if [[ "$line" =~ ^\`\`\` ]]; then
    in_code=$((1 - in_code))
    continue
  fi
  if [ $in_code -ne 0 ]; then continue; fi
  if [[ "$line" =~ ^##[[:space:]]+Phase[[:space:]]+([0-9]+)([a-z]?)([^[:space:]:]*) ]]; then
    n="${BASH_REMATCH[1]}"
    EXISTING_PHASE_LINES+=("$i")
    if [ "$n" -gt "$max_phase_num" ]; then
      max_phase_num=$n
    fi
  fi
done

# ----------------------------------------------------------------------
# Cluster MISSING_PIDS into groups of 1-3. Plan-order preserved.
# Cluster size = 3 by default; if total %3 == 0, split evenly; else
# the last cluster may be 1 or 2.
# ----------------------------------------------------------------------
declare -a CLUSTERS  # Each element: comma-separated phase ids.
total=${#MISSING_PIDS[@]}
i=0
while [ $i -lt $total ]; do
  remaining=$((total - i))
  if [ $remaining -ge 3 ]; then
    csize=3
  else
    csize=$remaining
  fi
  cluster=""
  for ((j=0; j<csize; j++)); do
    pid="${MISSING_PIDS[$((i + j))]}"
    if [ -z "$cluster" ]; then
      cluster="$pid"
    else
      cluster="$cluster,$pid"
    fi
  done
  CLUSTERS+=("$cluster")
  i=$((i + csize))
done

# ----------------------------------------------------------------------
# Build per-cluster backfill phase records: phase id, source-phase list,
# and the AC list aggregated from MISSING_ACS_BY_PID.
# ----------------------------------------------------------------------
declare -a BACKFILL_NEW_IDS
declare -A BACKFILL_SOURCES_BY_NEW
declare -A BACKFILL_NEWACS_BY_NEW
declare -A BACKFILL_OLDACS_BY_NEW

next_num=$((max_phase_num + 1))
for c in "${CLUSTERS[@]}"; do
  new_id="$next_num"
  BACKFILL_NEW_IDS+=("$new_id")
  BACKFILL_SOURCES_BY_NEW["$new_id"]="$c"

  # Aggregate ACs from each source phase.
  IFS=',' read -ra src_pids <<< "$c"
  agg_old_acs=""
  agg_new_acs=""
  ac_count=0
  for sp in "${src_pids[@]}"; do
    sp_trim="$(printf '%s' "$sp" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -z "$sp_trim" ] && continue
    src_acs="${MISSING_ACS_BY_PID[$sp_trim]:-}"
    [ -z "$src_acs" ] && continue
    IFS=',' read -ra ac_arr <<< "$src_acs"
    for old_ac in "${ac_arr[@]}"; do
      old_ac_trim="$(printf '%s' "$old_ac" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
      [ -z "$old_ac_trim" ] && continue
      ac_count=$((ac_count + 1))
      new_ac="AC-${new_id}.${ac_count}"
      if [ -z "$agg_old_acs" ]; then
        agg_old_acs="$old_ac_trim"
        agg_new_acs="$new_ac"
      else
        agg_old_acs="${agg_old_acs},${old_ac_trim}"
        agg_new_acs="${agg_new_acs},${new_ac}"
      fi
    done
  done
  BACKFILL_OLDACS_BY_NEW["$new_id"]="$agg_old_acs"
  BACKFILL_NEWACS_BY_NEW["$new_id"]="$agg_new_acs"

  next_num=$((next_num + 1))
done

# ----------------------------------------------------------------------
# Compute the insertion line in the plan: IMMEDIATELY BEFORE the first
# trailing non-phase level-2 heading at column 0 outside fenced code
# blocks AFTER the last `## Phase`. If no trailing non-phase L2 exists,
# insertion is at end of file.
# ----------------------------------------------------------------------
last_phase_line=-1
for li in "${EXISTING_PHASE_LINES[@]}"; do
  last_phase_line=$li
done

insert_line=$NLINES   # default = append at EOF
in_code=0
for ((i=0; i<NLINES; i++)); do
  line="${PLAN_LINES[$i]}"
  if [[ "$line" =~ ^\`\`\` ]]; then
    in_code=$((1 - in_code))
    continue
  fi
  if [ $in_code -ne 0 ]; then continue; fi
  if [ $i -le $last_phase_line ]; then continue; fi
  # First trailing non-phase L2 heading after the last `## Phase`.
  if [[ "$line" =~ ^##[[:space:]] ]]; then
    if ! [[ "$line" =~ ^##[[:space:]]+Phase[[:space:]] ]]; then
      insert_line=$i
      break
    fi
  fi
done

# ----------------------------------------------------------------------
# Locate the Progress Tracker -- we need to append a row for each new
# backfill phase. We bound the tracker by the next `## ` heading (any
# level-2) outside fences after the tracker heading.
# ----------------------------------------------------------------------
tracker_start=-1
tracker_end=-1
in_code=0
for ((i=0; i<NLINES; i++)); do
  line="${PLAN_LINES[$i]}"
  if [[ "$line" =~ ^\`\`\` ]]; then
    in_code=$((1 - in_code))
    continue
  fi
  if [ $in_code -ne 0 ]; then continue; fi
  if [[ "$line" =~ ^##[[:space:]]+Progress[[:space:]]+Tracker ]]; then
    tracker_start=$i
    continue
  fi
  if [ $tracker_start -ge 0 ] && [[ "$line" =~ ^##[[:space:]] ]] && [ $i -gt $tracker_start ]; then
    tracker_end=$((i - 1))
    break
  fi
done
if [ $tracker_start -ge 0 ] && [ $tracker_end -lt 0 ]; then
  tracker_end=$((NLINES - 1))
fi

# Find the LAST non-blank tracker row line index (so we can insert after).
tracker_last_row=-1
if [ $tracker_start -ge 0 ]; then
  for ((j=tracker_start+1; j<=tracker_end; j++)); do
    if [[ "${PLAN_LINES[$j]}" =~ ^\| ]]; then
      tracker_last_row=$j
    fi
  done
fi

# ----------------------------------------------------------------------
# Build the inserted backfill blocks. For each backfill phase:
#   ## Phase N -- Backfill tests for completed phases X[, Y][, Z]
#
#   ### Goal
#
#   Add missing test coverage for AC-X.1, AC-X.2, ... that were flagged
#   as MISSING by `/draft-tests` gap detection.
#
#   ### Work Items
#
#   - [ ] N.1 -- backfill spec authorship for AC-X.1 (originally Phase X).
#   ...
#
#   ### Design & Constraints
#
#   - Tests must verify the current state of shipped work, not the
#     original AC text where reality diverged.
#   - Backfill phase ACs use `AC-<backfill-phase>.<n>` IDs that alias
#     the original Completed-phase AC IDs.
#
#   ### Acceptance Criteria
#
#   - [ ] AC-N.1 -- backfill spec for AC-X.1 (alias).
#   ...
#
#   ### Dependencies
#
#   Completed phases X, Y, Z (read-only; not modified).
# ----------------------------------------------------------------------
build_backfill_block() {
  local new_id="$1"
  local sources="$2"
  local agg_old="$3"
  local agg_new="$4"
  local heading="## Phase $new_id -- Backfill tests for completed phases $sources"
  local goal="Add missing test coverage for ${agg_old//,/, } that were flagged as MISSING by gap detection."
  printf '%s\n\n' "$heading"
  printf '### Goal\n\n%s\n\n' "$goal"
  printf '### Work Items\n\n'
  IFS=',' read -ra OLD_ARR <<< "$agg_old"
  local n=0
  for oac in "${OLD_ARR[@]}"; do
    n=$((n + 1))
    printf -- '- [ ] %s.%s -- backfill spec authorship for %s.\n' "$new_id" "$n" "$oac"
  done
  printf '\n### Design & Constraints\n\n'
  printf -- '- Tests must verify the current state of shipped work, not the original AC text where reality diverged.\n'
  printf -- '- Backfill phase ACs use `AC-<backfill-phase>.<n>` IDs that alias the original Completed-phase AC IDs.\n'
  printf '\n### Acceptance Criteria\n\n'
  IFS=',' read -ra NEW_ARR <<< "$agg_new"
  local n=0
  for nac in "${NEW_ARR[@]}"; do
    n=$((n + 1))
    local oac="${OLD_ARR[$((n - 1))]}"
    printf -- '- [ ] %s — backfill spec for %s (alias).\n' "$nac" "$oac"
  done
  printf '\n### Dependencies\n\nCompleted phases %s (read-only; not modified).\n' "$sources"
}

# ----------------------------------------------------------------------
# Compose the new plan content: lines 0..insert_line-1, then per-cluster
# blocks (each followed by a blank line), then lines insert_line..end.
#
# Progress Tracker rows are inserted at tracker_last_row + 1 (after the
# last existing row but before any blank lines / next section).
# ----------------------------------------------------------------------
TMP_PLAN="$(mktemp)"
{
  # If we have a tracker, we need to compose the file with two insertions:
  # tracker rows AND backfill phases. We do this by emitting the file
  # line-by-line and injecting rows at the right line indices.
  for ((i=0; i<NLINES; i++)); do
    printf '%s\n' "${PLAN_LINES[$i]}"
    # After the last tracker row, append our backfill rows.
    if [ "$i" -eq "$tracker_last_row" ] && [ "$tracker_last_row" -ge 0 ]; then
      for new_id in "${BACKFILL_NEW_IDS[@]}"; do
        sources="${BACKFILL_SOURCES_BY_NEW[$new_id]}"
        # Tracker columns: | Phase | Status | Commit | Notes |
        # We emit the form `| N -- Backfill X | ⬚ | | |`.
        printf '| %s -- Backfill X | ⬚ | | backfill of completed phases %s |\n' "$new_id" "$sources"
      done
    fi
    # Just before the insertion line, emit the backfill phase blocks.
    if [ "$((i + 1))" -eq "$insert_line" ]; then
      # Ensure a blank line before the inserted block (if the line we
      # just emitted is non-blank).
      if [ -n "${PLAN_LINES[$i]}" ]; then
        printf '\n'
      fi
      for new_id in "${BACKFILL_NEW_IDS[@]}"; do
        sources="${BACKFILL_SOURCES_BY_NEW[$new_id]}"
        agg_old="${BACKFILL_OLDACS_BY_NEW[$new_id]}"
        agg_new="${BACKFILL_NEWACS_BY_NEW[$new_id]}"
        build_backfill_block "$new_id" "$sources" "$agg_old" "$agg_new"
        printf '\n'
      done
    fi
  done
  # Append-at-EOF case: insert_line == NLINES (no trailing non-phase L2).
  if [ "$insert_line" -eq "$NLINES" ]; then
    if [ "$NLINES" -gt 0 ] && [ -n "${PLAN_LINES[$((NLINES - 1))]}" ]; then
      printf '\n'
    fi
    for new_id in "${BACKFILL_NEW_IDS[@]}"; do
      sources="${BACKFILL_SOURCES_BY_NEW[$new_id]}"
      agg_old="${BACKFILL_OLDACS_BY_NEW[$new_id]}"
      agg_new="${BACKFILL_NEWACS_BY_NEW[$new_id]}"
      build_backfill_block "$new_id" "$sources" "$agg_old" "$agg_new"
      printf '\n'
    done
  fi
} > "$TMP_PLAN"

# Preserve original trailing-newline state. mapfile strips a single
# trailing newline from the final element if the file had one.
if [ "$(tail -c1 "$PLAN_FILE" | od -An -c | tr -d ' ')" != '\n' ]; then
  truncate -s -1 "$TMP_PLAN"
fi
mv "$TMP_PLAN" "$PLAN_FILE"

# ----------------------------------------------------------------------
# Update parsed-state: append each backfill phase id to
# `non_delegate_pending_phases:` AND `pending_phases:`. Also append a
# dummy completed_phases entry? No -- backfill phases are Pending by
# construction. Per WI 5.3b / AC-5.10: load-bearing for Phase 4's
# coverage-floor pre-check.
# ----------------------------------------------------------------------
TMP_STATE="$(mktemp)"
awk -v ids="$(IFS=','; echo "${BACKFILL_NEW_IDS[*]}")" '
  function flush_lists(   i) {
    for (i=1; i<=n; i++) {
      if (idarr[i] != "") printf "  %s\n", idarr[i]
    }
  }
  BEGIN {
    n = split(ids, idarr, ",")
    in_ndp = 0
    in_p = 0
  }
  # When we see a non-indented line, that closes any list we were in.
  # Flush any pending list BEFORE printing the new heading.
  /^[^ ]/ {
    if (in_ndp) {
      flush_lists()
      in_ndp = 0
    }
    if (in_p) {
      flush_lists()
      in_p = 0
    }
    print
    if ($0 == "non_delegate_pending_phases:") in_ndp = 1
    else if ($0 == "pending_phases:") in_p = 1
    next
  }
  # Indented line inside a list -- just print verbatim.
  { print }
  END {
    # If the file ended while still inside one of the lists, flush.
    if (in_ndp) flush_lists()
    if (in_p) flush_lists()
  }
' "$PARSED_STATE" > "$TMP_STATE"
mv "$TMP_STATE" "$PARSED_STATE"

# ----------------------------------------------------------------------
# Write the backfill-out file describing the action.
# ----------------------------------------------------------------------
{
  printf 'backfill_phases:\n'
  for new_id in "${BACKFILL_NEW_IDS[@]}"; do
    sources="${BACKFILL_SOURCES_BY_NEW[$new_id]}"
    printf '  %s:%s\n' "$new_id" "$sources"
  done
  printf 'missing_acs:\n'
  for new_id in "${BACKFILL_NEW_IDS[@]}"; do
    agg_old="${BACKFILL_OLDACS_BY_NEW[$new_id]}"
    printf '  %s:%s\n' "$new_id" "$agg_old"
  done
} > "$BACKFILL_OUT"

exit 0
