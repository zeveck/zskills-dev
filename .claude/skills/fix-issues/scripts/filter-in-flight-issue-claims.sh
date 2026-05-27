#!/bin/bash
# filter-in-flight-issue-claims.sh — Selection-aware filter for /fix-issues.
#
# Sibling of skills/work-on-plans/scripts/filter-in-flight-plan-claims.sh
# (PR #645 D4), adapted for integer issue numbers instead of kebab-case
# plan slugs. Closes #641 — the steady-state parallel-selection race the
# user originally reported in PR #645's plan but that was deferred there.
#
# Why selection-time (not acquire-time): the atomic-mkdir acquire inside
# Phase 3 fires AFTER /fix-issues has already burned the cost of building
# dispatch state for that issue number. Catching the in-flight pipeline at
# SELECTION time keeps a freshly-fired /fix-issues from spinning up
# redundant impl dispatches against an issue another pipeline is already
# working. The atomic acquire remains the final defense for the fresh-
# start race (both invocations observe an empty claims-dir before either
# acquires); that residual race is bounded by claim-issue.sh's
# acquire-EEXIST mkdir → exit 10 contract. Same DA2.7 framing as the
# /work-on-plans + /run-plan pair.
#
# Interface:
#   stdin   — bare integers, one per line; empty / blank lines tolerated.
#             (Differs from filter-in-flight-plan-claims.sh, which takes
#             TSV — /fix-issues Phase 2 uses a bash array of integers,
#             not TSV-row strings.)
#   stdout  — bare integers (filtered).
#   stderr  — "Skipped N issue(s) currently in-flight: <num1> <num2> ..."
#             (single line) if any were filtered. Permission-error claims
#             root → single diagnostic line, proceed with empty set.
#   exit    — 0 always (filter NEVER fails dispatch — graceful degradation).
#
# MAIN_ROOT resolution: `git rev-parse --git-common-dir` parent, mirroring
# claim-issue.sh's MAIN_ROOT resolution (DA4.1 / DA7 invariant). NEVER
# falls back to $PWD silently — outside a git tree, treats in-flight set
# as empty (filter is a no-op rather than a hard failure).
#
# Reading claims: best-effort. Malformed JSON, missing claim.json, non-
# issue-* dirs, non-integer claim names are skipped silently.
#
# No jq — Python stdlib json per CLAUDE.md "Python is required".

set -u

# ---------------------------------------------------------------------------
# Python interpreter resolution (CLAUDE.md "Python is required").
# ---------------------------------------------------------------------------
_FILTER_PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
if [ -z "$_FILTER_PYTHON" ]; then
  echo "fix-issues filter-in-flight-issue-claims.sh: install Python 3 (or set ZSKILLS_PYTHON)" >&2
  # Filter never fails dispatch — fall through with passthrough.
  cat
  exit 0
fi

# ---------------------------------------------------------------------------
# Resolve MAIN_ROOT — sibling of claim-issue.sh's resolution.
# Outside a git tree we cannot find the claims root, so the in-flight set
# is empty and we pass through (graceful degradation).
# ---------------------------------------------------------------------------
_resolve_main_root() {
  local common_dir
  if ! common_dir=$(git rev-parse --git-common-dir 2>/dev/null); then
    return 1
  fi
  if ! MAIN_ROOT=$(cd "$common_dir/.." && pwd); then
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Build the in-flight issue-number set from .zskills/claims/issue-*/claim.json.
# Emits one integer per line on stdout.
#
# Permission errors on the claims root itself → single stderr diagnostic
# and treat as empty. Missing claims root (the common case before any
# claim has been acquired) → silent empty.
# ---------------------------------------------------------------------------
_build_in_flight_set() {
  local claims_root="$1"

  if [ ! -d "$claims_root" ]; then
    return 0
  fi

  # Permission probe — if we cannot list the dir, surface ONE diagnostic
  # and return empty. `ls` is the read-permission probe; we do not
  # care about the listing itself.
  if ! ls "$claims_root" >/dev/null 2>&1; then
    echo "fix-issues filter: cannot read $claims_root (permission denied?); proceeding with empty in-flight set" >&2
    return 0
  fi

  "$_FILTER_PYTHON" - "$claims_root" <<'PY'
import json, os, re, sys

claims_root = sys.argv[1]
num_re = re.compile(r"^[0-9]+$")

try:
    entries = sorted(os.listdir(claims_root))
except OSError:
    sys.exit(0)

for name in entries:
    if not name.startswith("issue-"):
        continue
    num = name[len("issue-"):]
    if not num or not num_re.match(num):
        continue
    claim_dir = os.path.join(claims_root, name)
    if not os.path.isdir(claim_dir):
        continue
    claim_file = os.path.join(claim_dir, "claim.json")
    if not os.path.isfile(claim_file):
        # Missing claim.json — mid-acquire window or orphan dir; skip.
        # Conservative: do NOT treat as in-flight here, because we
        # cannot confirm a live pipeline (sweep reaps truly stale).
        continue
    try:
        with open(claim_file) as fh:
            body = json.load(fh)
    except Exception:
        # Malformed JSON — skip silently (symmetric to the plan-side
        # filter and to the dashboard collector).
        continue
    # Issue number from claim.json (preferred) falls back to dir-derived.
    body_num = body.get("issue") or body.get("number") or num
    if isinstance(body_num, int):
        body_num = str(body_num)
    if not isinstance(body_num, str) or not num_re.match(body_num):
        body_num = num
    print(body_num)
PY
}

# ---------------------------------------------------------------------------
# Main.
# ---------------------------------------------------------------------------
main() {
  local MAIN_ROOT=""
  if ! _resolve_main_root; then
    # Outside a git tree — passthrough.
    cat
    return 0
  fi

  local claims_root="${MAIN_ROOT}/.zskills/claims"

  # Build in-flight integer set (one per line on stdout of the helper).
  local in_flight
  in_flight=$(_build_in_flight_set "$claims_root")

  # Read all input rows first so we can iterate and also report.
  # `|| [ -n "$row" ]` clause catches the final line when stdin has no
  # trailing newline.
  local -a INPUT_ROWS=()
  local row
  while IFS= read -r row || [ -n "$row" ]; do
    INPUT_ROWS+=("$row")
  done

  if [ -z "$in_flight" ]; then
    # Fast path — no claims; emit input verbatim (preserving non-empty rows).
    if [ "${#INPUT_ROWS[@]}" -gt 0 ]; then
      local r
      for r in "${INPUT_ROWS[@]}"; do
        [ -z "$r" ] && continue
        printf '%s\n' "$r"
      done
    fi
    return 0
  fi

  # Build associative set for O(1) lookup.
  declare -A IN_FLIGHT_SET=()
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    IN_FLIGHT_SET["$s"]=1
  done <<<"$in_flight"

  local -a FILTERED=()
  local -a SKIPPED=()
  local r
  for r in "${INPUT_ROWS[@]}"; do
    # Skip wholly empty input lines.
    if [ -z "$r" ]; then
      continue
    fi
    # Match on the literal line (input is bare integers — no TSV split).
    # Non-integer lines pass through unchanged (most defensive — mirrors
    # plan-side malformed-slug treatment).
    if [ -n "${IN_FLIGHT_SET[$r]:-}" ]; then
      SKIPPED+=("$r")
    else
      FILTERED+=("$r")
    fi
  done

  if [ "${#SKIPPED[@]}" -gt 0 ]; then
    printf 'Skipped %d issue(s) currently in-flight: %s\n' \
      "${#SKIPPED[@]}" "${SKIPPED[*]}" >&2
  fi

  if [ "${#FILTERED[@]}" -gt 0 ]; then
    printf '%s\n' "${FILTERED[@]}"
  fi
  return 0
}

main "$@"
