#!/bin/bash
# gap-detect.sh -- Phase 5 WI 5.1 gap detection for Completed phases.
#
# For every AC in every Completed phase listed in the parsed-state file,
# classify the AC into one of three confidence levels:
#
#   COVERED  -- (high confidence) the AC's ID (e.g. `AC-3.2`) appears
#               literally in any test file in the Phase-2 test-file map,
#               OR a backticked identifier (length >= 4) in the AC body
#               appears in exactly one test file (after stop-word
#               removal). For the "concrete identifier" heuristic, we
#               restrict to backticked tokens because plain prose nouns
#               can never be reliably attributed to a code identifier
#               (AC-5.2 regression guard against the prose-token
#               false-positive bug).
#
#   MISSING  -- (moderate confidence) NO AC-ID match in any test file,
#               AND the AC body contains at least one backticked token
#               (matched by `\`[^\`]+\``), AND that backticked token,
#               when treated as a literal string, is absent from EVERY
#               file in the repo (`git grep -F -- "<token>"` returns no
#               matches). Triggers backfill.
#
#   UNKNOWN  -- (low confidence) anything not classified COVERED or
#               MISSING. Specifically: ACs with no backticks in the
#               body, OR ACs whose backticked tokens are present
#               somewhere in the repo but not in a test file. Emits
#               advisory only; does NOT trigger backfill.
#
# A Completed phase is FLAGGED for backfill only when >= 1 of its ACs
# is classified MISSING.
#
# Usage:
#   bash gap-detect.sh <plan-file> <parsed-state> <detect-state> <gaps-out>
#
# Arguments:
#   <plan-file>     Path to the plan .md file.
#   <parsed-state>  Phase 1 parsed-state file (`/tmp/draft-tests-parsed-<slug>.md`).
#                   Read for `completed_phases:` (phase-id:sha256 entries).
#   <detect-state>  Phase 2 detection-state file
#                   (`/tmp/draft-tests-detect-<slug>.md`).
#                   Read for `test_files:` (lang:abs-path entries).
#                   May be `/dev/null` -- treated as empty test-file map.
#   <gaps-out>      Path to write the gap-detection output. Format:
#
#                     missing_phases:
#                       <phase-id>:<comma-separated AC-ids>
#                       ...
#                     unknown_phases:
#                       <phase-id>:<comma-separated AC-ids>
#                       ...
#                     advisories:
#                       <line>
#                       ...
#
# Exit codes:
#   0 -- gaps-out written (may be empty).
#   2 -- usage error.
#   3 -- input file missing.

set -eu

PLAN_FILE="${1:-}"
PARSED_STATE="${2:-}"
DETECT_STATE="${3:-}"
GAPS_OUT="${4:-}"

if [ -z "$PLAN_FILE" ] || [ -z "$PARSED_STATE" ] \
   || [ -z "$DETECT_STATE" ] || [ -z "$GAPS_OUT" ]; then
  echo "Usage: $0 <plan-file> <parsed-state> <detect-state> <gaps-out>" >&2
  exit 2
fi

if [ ! -f "$PLAN_FILE" ]; then
  echo "Error: plan file '$PLAN_FILE' not found." >&2
  exit 3
fi
if [ ! -f "$PARSED_STATE" ]; then
  echo "Error: parsed-state file '$PARSED_STATE' not found." >&2
  exit 3
fi
# DETECT_STATE may be /dev/null intentionally.
if [ "$DETECT_STATE" != "/dev/null" ] && [ ! -f "$DETECT_STATE" ]; then
  echo "Error: detect-state file '$DETECT_STATE' not found." >&2
  exit 3
fi

# ----------------------------------------------------------------------
# Read the parsed-state list of completed phases.
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

mapfile -t COMPLETED_ENTRIES < <(read_state_list "$PARSED_STATE" completed_phases)

# Read test-file paths from detect-state's `test_files:` list. Each entry
# is `<lang>:<absolute-path>`. We only need the path.
declare -a TEST_FILES
if [ "$DETECT_STATE" != "/dev/null" ]; then
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    # Strip the leading `lang:` prefix to get the path.
    path="${entry#*:}"
    [ -n "$path" ] && [ -f "$path" ] && TEST_FILES+=("$path")
  done < <(read_state_list "$DETECT_STATE" test_files)
fi

# ----------------------------------------------------------------------
# Phase-section locator. Returns the line range for a phase id in the
# plan file. Mirrors parse-plan.sh's broad-form, fenced-code-block-aware
# scan.
# ----------------------------------------------------------------------
mapfile -t PLAN_LINES < "$PLAN_FILE"
NLINES=${#PLAN_LINES[@]}

declare -a PHASE_ID_BODY
declare -a PHASE_LINE_START
declare -a L2_INDICES
in_code=0
for ((i=0; i<NLINES; i++)); do
  line="${PLAN_LINES[$i]}"
  if [[ "$line" =~ ^\`\`\` ]]; then
    in_code=$((1 - in_code))
    continue
  fi
  if [ $in_code -ne 0 ]; then continue; fi
  if [[ "$line" =~ ^##[[:space:]] ]]; then
    L2_INDICES+=("$i")
    if [[ "$line" =~ ^##[[:space:]]+Phase[[:space:]]+([^[:space:]:]+) ]]; then
      pid="${BASH_REMATCH[1]}"
      pid="${pid%:}"
      PHASE_ID_BODY+=("$pid")
      PHASE_LINE_START+=("$i")
    fi
  fi
done

NUM_PHASES=${#PHASE_ID_BODY[@]}
NUM_L2=${#L2_INDICES[@]}

declare -a PHASE_LINE_END
for ((k=0; k<NUM_PHASES; k++)); do
  start_line=${PHASE_LINE_START[$k]}
  end_line=$((NLINES - 1))
  for ((m=0; m<NUM_L2; m++)); do
    li=${L2_INDICES[$m]}
    if [ $li -gt $start_line ]; then
      end_line=$((li - 1))
      break
    fi
  done
  PHASE_LINE_END+=("$end_line")
done

# Map phase-id -> [start, end] for O(1) lookup.
declare -A PHASE_START_BY_ID
declare -A PHASE_END_BY_ID
for ((k=0; k<NUM_PHASES; k++)); do
  PHASE_START_BY_ID["${PHASE_ID_BODY[$k]}"]="${PHASE_LINE_START[$k]}"
  PHASE_END_BY_ID["${PHASE_ID_BODY[$k]}"]="${PHASE_LINE_END[$k]}"
done

# ----------------------------------------------------------------------
# AC enumeration within a phase: returns lines like
#   <ac-id>\t<ac-body-text>
# For each `- [ ] AC-N.M -- text` bullet inside the phase's
# `### Acceptance Criteria` block.
# ----------------------------------------------------------------------
emit_acs_for_phase() {
  local pid="$1"
  local start_line="${PHASE_START_BY_ID[$pid]:-}"
  local end_line="${PHASE_END_BY_ID[$pid]:-}"
  if [ -z "$start_line" ] || [ -z "$end_line" ]; then
    return 0
  fi
  local ac_start=-1
  local ac_end=-1
  for ((j=start_line; j<=end_line; j++)); do
    if [[ "${PLAN_LINES[$j]}" =~ ^###[[:space:]]+Acceptance[[:space:]]+Criteria ]]; then
      ac_start=$j
      break
    fi
  done
  if [ $ac_start -eq -1 ]; then return 0; fi
  for ((j=ac_start+1; j<=end_line; j++)); do
    if [[ "${PLAN_LINES[$j]}" =~ ^###[[:space:]] ]] || [[ "${PLAN_LINES[$j]}" =~ ^##[[:space:]] ]]; then
      ac_end=$((j-1))
      break
    fi
  done
  if [ $ac_end -eq -1 ]; then ac_end=$end_line; fi

  for ((j=ac_start+1; j<=ac_end; j++)); do
    line="${PLAN_LINES[$j]}"
    if [[ "$line" =~ ^-[[:space:]]\[[\ xX]\][[:space:]]AC-([0-9]+[a-z]?\.[0-9]+[a-z]?)[[:space:]]—[[:space:]](.*)$ ]]; then
      ac_id="AC-${BASH_REMATCH[1]}"
      ac_body="${BASH_REMATCH[2]}"
      printf '%s\t%s\n' "$ac_id" "$ac_body"
    fi
  done
}

# ----------------------------------------------------------------------
# Resolve REPO_ROOT for git grep. We use git grep -F so we operate on
# tracked content; backticked tokens may include slashes, dots etc., so
# -F (literal) is mandatory. If git grep is unavailable, we fall back
# to plain `grep -rF`.
# ----------------------------------------------------------------------
REPO_ROOT=""
if git rev-parse --show-toplevel >/dev/null 2>&1; then
  REPO_ROOT=$(git rev-parse --show-toplevel)
fi

repo_has_token() {
  local token="$1"
  if [ -z "$token" ]; then return 1; fi
  if [ -n "$REPO_ROOT" ]; then
    if (cd "$REPO_ROOT" && git grep -F -q -- "$token" 2>/dev/null); then
      return 0
    fi
    return 1
  fi
  # Fallback: scan PWD recursively for the literal token. Bounded to
  # avoid runaway output on huge trees.
  if grep -rFq -- "$token" . 2>/dev/null; then
    return 0
  fi
  return 1
}

# Emit unique-token list from an AC body.
emit_backticks_in() {
  local body="$1"
  # Match `[^`]+` -- the backticked-token form.
  # bash regex doesn't support repeated capture; use a loop with sed-like
  # progressive matching via parameter expansion.
  local rest="$body"
  local out=()
  while [[ "$rest" =~ \`([^\`]+)\` ]]; do
    local tok="${BASH_REMATCH[1]}"
    out+=("$tok")
    # Advance past this match.
    rest="${rest#*\`${tok}\`}"
  done
  printf '%s\n' "${out[@]:-}"
}

# ----------------------------------------------------------------------
# Iterate Completed phases. For each AC in each Completed phase:
#   1. Check AC-ID literal in any test file -> COVERED (skip).
#   2. Else: extract backticked tokens from AC body. For each token:
#        - If token absent from `git grep -F` -> AC is MISSING.
#      If no backticked token at all OR all tokens are present in repo
#      somewhere -> AC is UNKNOWN.
# ----------------------------------------------------------------------
declare -A MISSING_BY_PHASE
declare -A UNKNOWN_BY_PHASE
declare -a ADVISORIES

for entry in "${COMPLETED_ENTRIES[@]:-}"; do
  [ -z "$entry" ] && continue
  pid="${entry%%:*}"

  while IFS=$'\t' read -r ac_id ac_body; do
    [ -z "$ac_id" ] && continue

    # COVERED predicate (1): AC-ID literal in any test file.
    covered=0
    for tf in "${TEST_FILES[@]:-}"; do
      [ -z "$tf" ] && continue
      if grep -F -q -- "$ac_id" "$tf" 2>/dev/null; then
        covered=1
        break
      fi
    done
    if [ $covered -eq 1 ]; then
      continue
    fi

    # Extract backticked tokens.
    mapfile -t TOKENS < <(emit_backticks_in "$ac_body")
    real_tokens=()
    for t in "${TOKENS[@]:-}"; do
      [ -z "$t" ] && continue
      # Length floor.
      if [ "${#t}" -lt 4 ]; then continue; fi
      real_tokens+=("$t")
    done

    if [ "${#real_tokens[@]}" -eq 0 ]; then
      # No backticked tokens -- UNKNOWN. Regression guard against
      # prose-only false-positive (AC-5.2).
      UNKNOWN_BY_PHASE["$pid"]="${UNKNOWN_BY_PHASE[$pid]:-}${ac_id},"
      continue
    fi

    # MISSING predicate (3): >= 1 backticked token absent from repo.
    found_missing=0
    for t in "${real_tokens[@]}"; do
      if ! repo_has_token "$t"; then
        found_missing=1
        break
      fi
    done

    if [ $found_missing -eq 1 ]; then
      MISSING_BY_PHASE["$pid"]="${MISSING_BY_PHASE[$pid]:-}${ac_id},"
    else
      UNKNOWN_BY_PHASE["$pid"]="${UNKNOWN_BY_PHASE[$pid]:-}${ac_id},"
    fi
  done < <(emit_acs_for_phase "$pid")
done

# Build advisory list for UNKNOWN phases (per WI 5.1 / AC-5.2).
for pid in "${!UNKNOWN_BY_PHASE[@]}"; do
  acs="${UNKNOWN_BY_PHASE[$pid]%,}"
  ADVISORIES+=("advisory: coverage could not be confirmed -- human review recommended for Phase $pid (ACs: $acs)")
done

# ----------------------------------------------------------------------
# Write the gaps-out file.
# ----------------------------------------------------------------------
{
  printf 'missing_phases:\n'
  # Iterate Completed phase order (preserve plan-file order rather than
  # associative array order).
  for entry in "${COMPLETED_ENTRIES[@]:-}"; do
    [ -z "$entry" ] && continue
    pid="${entry%%:*}"
    if [ -n "${MISSING_BY_PHASE[$pid]:-}" ]; then
      acs="${MISSING_BY_PHASE[$pid]%,}"
      printf '  %s:%s\n' "$pid" "$acs"
    fi
  done
  printf 'unknown_phases:\n'
  for entry in "${COMPLETED_ENTRIES[@]:-}"; do
    [ -z "$entry" ] && continue
    pid="${entry%%:*}"
    if [ -n "${UNKNOWN_BY_PHASE[$pid]:-}" ]; then
      acs="${UNKNOWN_BY_PHASE[$pid]%,}"
      printf '  %s:%s\n' "$pid" "$acs"
    fi
  done
  printf 'advisories:\n'
  for adv in "${ADVISORIES[@]:-}"; do
    [ -z "$adv" ] && continue
    printf '  %s\n' "$adv"
  done
} > "$GAPS_OUT"

exit 0
