#!/bin/bash
# filter-in-flight-plan-claims.sh — Selection-aware filter for /work-on-plans.
#
# Phase 2b W2b.1 of `plans/plans-claim-chip-parity.md` D4 — the user-steering
# anchor. Drops slugs from the dispatch queue whose plan-* claim files
# indicate an in-flight pipeline.
#
# Why selection-time (not acquire-time): the atomic-mkdir acquire inside
# /run-plan's Phase 0 fires AFTER /work-on-plans has already burned the
# cost of building dispatch state for that slug. Catching the in-flight
# pipeline at SELECTION time keeps the user-typed `/work-on-plans` from
# spinning up redundant /run-plan dispatches. The atomic acquire remains
# the final defense for the fresh-start race (both invocations observe an
# empty claims-dir before either acquires); that residual race is bounded
# by Phase 1's mkdir → exit 10 contract.
#
# Interface:
#   stdin   — TSV rows (first column = slug); empty / blank lines tolerated.
#   stdout  — TSV rows (filtered).
#   stderr  — "Skipped N plan(s) currently in-flight: <slug1> <slug2> ..."
#             (single line) if any were filtered. Permission-error claims
#             root → single diagnostic line, proceed with empty set.
#   exit    — 0 always (filter NEVER fails dispatch — graceful degradation).
#
# MAIN_ROOT resolution: `git rev-parse --git-common-dir` parent, mirroring
# claim-plan.sh's resolve_main_root() (DA4.1 / DA7 invariant). NEVER falls
# back to $PWD silently — outside a git tree, treats in-flight set as
# empty (filter is a no-op rather than a hard failure).
#
# Reading claims: best-effort. Malformed JSON, missing claim.json, non-
# plan-* dirs are skipped silently (symmetric to the dashboard collector
# per Phase 3 W3.1).
#
# No jq — Python stdlib json per CLAUDE.md "Python is required".

set -u

# ---------------------------------------------------------------------------
# Python interpreter resolution (CLAUDE.md "Python is required").
# ---------------------------------------------------------------------------
_FILTER_PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
if [ -z "$_FILTER_PYTHON" ]; then
  echo "work-on-plans filter-in-flight-plan-claims.sh: install Python 3 (or set ZSKILLS_PYTHON)" >&2
  # Filter never fails dispatch — fall through with passthrough.
  cat
  exit 0
fi

# ---------------------------------------------------------------------------
# Resolve MAIN_ROOT — sibling of claim-plan.sh's resolve_main_root().
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
# Build the in-flight slug set from .zskills/claims/plan-*/claim.json.
# Emits one slug per line on stdout.
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
  # and return empty. `ls -ld` is the read-permission probe; we do not
  # care about the listing itself.
  if ! ls "$claims_root" >/dev/null 2>&1; then
    echo "work-on-plans filter: cannot read $claims_root (permission denied?); proceeding with empty in-flight set" >&2
    return 0
  fi

  "$_FILTER_PYTHON" - "$claims_root" <<'PY'
import json, os, re, sys

claims_root = sys.argv[1]
slug_re = re.compile(r"^[a-z0-9][a-z0-9-]*$")

try:
    entries = sorted(os.listdir(claims_root))
except OSError:
    sys.exit(0)

for name in entries:
    if not name.startswith("plan-"):
        continue
    slug = name[len("plan-"):]
    if not slug or not slug_re.match(slug):
        continue
    claim_dir = os.path.join(claims_root, name)
    if not os.path.isdir(claim_dir):
        continue
    claim_file = os.path.join(claim_dir, "claim.json")
    if not os.path.isfile(claim_file):
        # Missing claim.json — mid-acquire window or orphan dir; skip
        # (sweep will reap if truly stale). Conservative: do NOT treat
        # as in-flight here, because we cannot confirm a live pipeline.
        continue
    try:
        with open(claim_file) as fh:
            body = json.load(fh)
    except Exception:
        # Malformed JSON — skip silently (dashboard collector does the
        # same per Phase 3 W3.1).
        continue
    # Slug from claim.json (preferred) falls back to dir-derived slug.
    body_slug = body.get("slug") or slug
    if not isinstance(body_slug, str) or not slug_re.match(body_slug):
        body_slug = slug
    print(body_slug)
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

  # Build in-flight slug set (one slug per line on stdout of the helper).
  local in_flight
  in_flight=$(_build_in_flight_set "$claims_root")

  # Read all input rows first so we can iterate and also report.
  # `|| [ -n "$row" ]` clause catches the final line when stdin has no
  # trailing newline (callers pipe `printf '%s\n' "${arr[@]}"` which DOES
  # newline-terminate, but a stray `printf '%s' ...` does not — be safe).
  local -a INPUT_ROWS=()
  local row
  while IFS= read -r row || [ -n "$row" ]; do
    INPUT_ROWS+=("$row")
  done

  if [ -z "$in_flight" ]; then
    # Fast path — no claims; emit input verbatim.
    if [ "${#INPUT_ROWS[@]}" -gt 0 ]; then
      printf '%s\n' "${INPUT_ROWS[@]}"
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
  local r slug
  for r in "${INPUT_ROWS[@]}"; do
    # Skip wholly empty input lines (preserve nothing).
    if [ -z "$r" ]; then
      continue
    fi
    # First TSV column. `awk` is safe for tab-delimited with no expansion;
    # bash IFS=$'\t' read would also work but awk avoids subshell quoting.
    slug=$(printf '%s' "$r" | awk -F'\t' '{print $1}')
    if [ -n "${IN_FLIGHT_SET[$slug]:-}" ]; then
      SKIPPED+=("$slug")
    else
      FILTERED+=("$r")
    fi
  done

  if [ "${#SKIPPED[@]}" -gt 0 ]; then
    printf 'Skipped %d plan(s) currently in-flight: %s\n' \
      "${#SKIPPED[@]}" "${SKIPPED[*]}" >&2
  fi

  if [ "${#FILTERED[@]}" -gt 0 ]; then
    printf '%s\n' "${FILTERED[@]}"
  fi
  return 0
}

main "$@"
