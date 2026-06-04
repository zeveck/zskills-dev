#!/bin/bash
# filter-mode-mismatch-plans.sh — Selection-time mode-mismatch skip filter
# for /work-on-plans.
#
# Phase 2 of plans/DASHBOARD_RUNSTATUS_CLEANUP_PLAN.md — sibling to
# filter-in-flight-plan-claims.sh. Drops slugs whose per-plan mode pin
# conflicts with the explicit sprint batch mode (`phase` vs `finish`).
#
# Single-responsibility: this filter does ONE thing — detect explicit-
# CLI-mode vs per-plan-pin conflict and write a `plans.skipped[<slug>]`
# marker. Do NOT extend filter-in-flight-plan-claims.sh to also do this
# work (the D4 seam keeps each filter narrow).
#
# Selection-time discipline: runs AFTER filter-in-flight-plan-claims.sh
# but BEFORE dispatch. The acceptance rule is:
#   accepts(plan, sprint) =
#       (sprint.batch_mode is null)
#       OR (plan.mode is INHERIT)
#       OR (plan.mode === sprint.batch_mode)
#
# The skip-check arm runs ONLY when `MODE_OVERRIDE` is non-empty. A bare
# `/work-on-plans 3` (no explicit mode) must NEVER skip any plan — the
# default-to-`finish` fall-through is NOT "explicit." This is the user-
# pinning contract: a user only loses dispatch if THEY typed two
# conflicting intents.
#
# A directly typed `/run-plan <slug> finish` against a `phase`-pinned plan
# is an explicit one-shot CLI override and bypasses the pin — that path
# does NOT route through this filter (the constraint is scoped to the
# `/work-on-plans` SELECTION BOUNDARY only).
#
# Interface:
#   stdin   — TSV rows `slug<TAB>mode` (one per line; blank tolerated).
#             `mode` empty = INHERIT pin; "phase" / "finish" = explicit.
#   stdout  — TSV rows (filtered — passthrough for INHERIT and matching;
#             dropped for mode-mismatch).
#   stderr  — informational counter line "Mode-mismatch skipped: N plan(s)"
#             when N > 0.
#   exit    — 0 always (filter NEVER fails dispatch — graceful degradation).
#
# Env (REQUIRED when used by execute.md; the script tolerates absence):
#   MODE_OVERRIDE  — "" | "phase" | "finish" (the explicit CLI token).
#                    Empty → passthrough (no skip-check at all).
#   SPRINT_ID      — sprint identifier (from execute.md Step 0).
#   PIPELINE_ID    — full pipeline id `work-on-plans.$SPRINT_ID`. Used to
#                    write the activity-feed step marker.
#   MAIN_ROOT      — repo root. State file at $MAIN_ROOT/.zskills/
#                    monitor-state.json; lock at .zskills/monitor-state.json.lock.
#
# Stderr counter convention: the line is exactly
#   "Mode-mismatch skipped: N plan(s)"
# (singular/plural correct via plain "plan(s)"). The bash caller in
# execute.md captures via a sentinel marker file (`$PIPELINE_DIR/
# .mode-mismatch-count`) rather than stderr — the marker file is the
# source of truth (stderr is informational only).
#
# Locking model: reimplements `flock -x` inline against
# `$MAIN_ROOT/.zskills/monitor-state.json.lock` (smaller scope than
# extracting a `with_monitor_lock` helper; see Phase 2 Design &
# Constraints in DASHBOARD_RUNSTATUS_CLEANUP_PLAN.md).
#
# Idempotency: the Python embed checks for an existing skip record with
# the same `(code, reason)` tuple and short-circuits the step-marker
# write if present. The state file's `at` value is PRESERVED across
# re-fires; `sprint_id` is REFRESHED to the most-recent triggering
# sprint; `updated_at` is bumped unconditionally (drives dashboard
# re-poll fingerprint refresh).

set -u

# ---------------------------------------------------------------------------
# Python interpreter resolution (CLAUDE.md "Python is required").
# ---------------------------------------------------------------------------
# zskills_resolve_python — print path to a working Python 3 interpreter, or
# empty if none. Probe-RUNS each candidate (existence is NOT enough: on Windows
# `command -v python3` finds the MS Store App-Execution-Alias stub, which exits
# non-zero when run). Honors ZSKILLS_PYTHON. Rejects python2.
zskills_resolve_python() {
  local cand
  for cand in "${ZSKILLS_PYTHON:-}" python3 python; do
    [ -n "$cand" ] || continue
    command -v "$cand" >/dev/null 2>&1 || continue
    if "$cand" -c 'import sys; sys.exit(0 if sys.version_info[0]==3 else 1)' >/dev/null 2>&1; then
      command -v "$cand"; return 0
    fi
  done
  return 1
}
_FILTER_PYTHON="$(zskills_resolve_python || true)"
if [ -z "$_FILTER_PYTHON" ]; then
  echo "work-on-plans filter-mode-mismatch-plans.sh: install Python 3 (or set ZSKILLS_PYTHON)" >&2
  cat
  exit 0
fi

# ---------------------------------------------------------------------------
# Main: read all input rows first; if MODE_OVERRIDE is empty, passthrough.
# Otherwise iterate, filter, and write skip markers under flock.
# ---------------------------------------------------------------------------
main() {
  local -a INPUT_ROWS=()
  local row
  while IFS= read -r row || [ -n "$row" ]; do
    INPUT_ROWS+=("$row")
  done

  # Passthrough when no explicit mode override (bare /work-on-plans).
  if [ -z "${MODE_OVERRIDE:-}" ]; then
    if [ "${#INPUT_ROWS[@]}" -gt 0 ]; then
      printf '%s\n' "${INPUT_ROWS[@]}"
    fi
    return 0
  fi

  # Validate inputs we'll actually use. Missing MAIN_ROOT/SPRINT_ID/
  # PIPELINE_ID is a programming error from the caller; degrade
  # gracefully (passthrough — never fail dispatch).
  if [ -z "${MAIN_ROOT:-}" ] || [ -z "${SPRINT_ID:-}" ] || [ -z "${PIPELINE_ID:-}" ]; then
    echo "work-on-plans filter-mode-mismatch-plans.sh: WARN — missing MAIN_ROOT/SPRINT_ID/PIPELINE_ID env (passthrough)" >&2
    if [ "${#INPUT_ROWS[@]}" -gt 0 ]; then
      printf '%s\n' "${INPUT_ROWS[@]}"
    fi
    return 0
  fi

  local PIPELINE_DIR="$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
  mkdir -p "$PIPELINE_DIR" 2>/dev/null || true
  local COUNT_MARKER="$PIPELINE_DIR/.mode-mismatch-count"

  local -a FILTERED=()
  local -a SKIPPED=()
  local r slug pin
  for r in "${INPUT_ROWS[@]}"; do
    if [ -z "$r" ]; then
      continue
    fi
    slug=$(printf '%s' "$r" | awk -F'\t' '{print $1}')
    pin=$(printf '%s' "$r"  | awk -F'\t' '{print $2}')
    # Empty pin = INHERIT — accepts any batch mode.
    if [ -z "$pin" ]; then
      FILTERED+=("$r")
      continue
    fi
    # Matching pin — pass through.
    if [ "$pin" = "$MODE_OVERRIDE" ]; then
      FILTERED+=("$r")
      continue
    fi
    # Mismatch: drop and write skip marker.
    SKIPPED+=("$slug")
    _write_skip_marker "$slug" "$pin" || true
  done

  if [ "${#SKIPPED[@]}" -gt 0 ]; then
    printf 'Mode-mismatch skipped: %d plan(s)\n' "${#SKIPPED[@]}" >&2
    # Counter sentinel for execute.md status-line render.
    printf '%d\n' "${#SKIPPED[@]}" > "$COUNT_MARKER" 2>/dev/null || true
  else
    # Ensure stale counter from a previous fire doesn't leak.
    rm -f "$COUNT_MARKER" 2>/dev/null || true
  fi

  if [ "${#FILTERED[@]}" -gt 0 ]; then
    printf '%s\n' "${FILTERED[@]}"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Write the plans.skipped[<slug>] state record + the per-sprint
# step.work-on-plans.${SPRINT_ID}.${SLUG} marker for the activity feed.
# All under flock against monitor-state.json.lock.
#
# Args: $1 = slug, $2 = pin (the per-plan mode that conflicted).
# Globals (env): MAIN_ROOT, MODE_OVERRIDE, SPRINT_ID, PIPELINE_ID.
# ---------------------------------------------------------------------------
_write_skip_marker() {
  local SLUG="$1"
  local PIN="$2"
  local MONITOR_STATE="$MAIN_ROOT/.zskills/monitor-state.json"
  local MONITOR_LOCK="$MAIN_ROOT/.zskills/monitor-state.json.lock"
  mkdir -p "$(dirname "$MONITOR_LOCK")" 2>/dev/null || true

  local IS_FRESH
  IS_FRESH=$(
    flock -x 9 2>/dev/null
    "$_FILTER_PYTHON" - "$MONITOR_STATE" "$SLUG" "$MODE_OVERRIDE" "$PIN" "$SPRINT_ID" <<'PY'
import json, os, sys, tempfile, datetime

state_path, slug, batch, pin, sprint_id = sys.argv[1:6]

now_iso = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")

# Tolerate missing / malformed state file.
try:
    with open(state_path) as fh:
        data = json.load(fh)
    if not isinstance(data, dict):
        data = {}
except (FileNotFoundError, json.JSONDecodeError, ValueError):
    data = {}

plans = data.setdefault("plans", {})
if not isinstance(plans, dict):
    plans = {}
    data["plans"] = plans
skipped = plans.setdefault("skipped", {})
if not isinstance(skipped, dict):
    skipped = {}
    plans["skipped"] = skipped

reason = f"{batch}≠{pin}"  # "finish≠phase"
prev = skipped.get(slug)
fresh = True
preserved_at = now_iso
if isinstance(prev, dict):
    prev_code = prev.get("code")
    prev_reason = prev.get("reason")
    if prev_code == "mode-mismatch" and prev_reason == reason:
        # Stale: preserve original `at`, refresh sprint_id + updated_at.
        fresh = False
        if isinstance(prev.get("at"), str) and prev["at"]:
            preserved_at = prev["at"]

skipped[slug] = {
    "code": "mode-mismatch",
    "reason": reason,
    "sprint_id": sprint_id,
    "at": preserved_at,
}
data["updated_at"] = now_iso

# Atomic write.
parent = os.path.dirname(state_path) or "."
try:
    os.makedirs(parent, exist_ok=True)
except OSError:
    print("STALE")  # degrade gracefully
    sys.exit(0)

try:
    tmp = tempfile.NamedTemporaryFile(
        "w", delete=False, dir=parent,
        prefix=".monitor-state.", suffix=".tmp",
    )
    json.dump(data, tmp, indent=2)
    tmp.write("\n")
    tmp.close()
    os.replace(tmp.name, state_path)
except OSError as exc:
    sys.stderr.write(f"filter-mode-mismatch-plans.sh: state write failed: {exc}\n")
    print("STALE")
    sys.exit(0)

print("FRESH" if fresh else "STALE")
PY
  ) 9> "$MONITOR_LOCK"

  # Only write the activity-feed step marker on FRESH (idempotency
  # contract — re-fires must NOT produce a second step marker).
  if [ "$IS_FRESH" = "FRESH" ]; then
    local PIPELINE_DIR="$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
    mkdir -p "$PIPELINE_DIR" 2>/dev/null || true
    local MARKER="$PIPELINE_DIR/step.work-on-plans.${SPRINT_ID}.${SLUG}"
    local ISO
    ISO=$(${TZ:+TZ="$TZ"} date -Iseconds 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
    cat > "$MARKER" <<MARKER_EOF
skill: work-on-plans
parent: work-on-plans.${SPRINT_ID}
slug: ${SLUG}
mode: ${MODE_OVERRIDE}
pin: ${PIN}
status: skip
output: mode_mismatch: ${MODE_OVERRIDE}!=${PIN}
date: ${ISO}
MARKER_EOF
  fi
  return 0
}

main "$@"
