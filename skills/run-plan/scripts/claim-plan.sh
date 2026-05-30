#!/bin/bash
# claim-plan.sh — Filesystem-anchored claim primitive for /run-plan.
#
# Sibling of skills/fix-issues/scripts/claim-issue.sh — mirrors the ~91%
# generic structure (resolve_main_root, atomic mkdir, Python helpers,
# exit-code mapping).
#
# Provides exclusive per-plan claims via atomic mkdir + a JSON metadata
# file. Claims live under ${MAIN_ROOT}/.zskills/claims/plan-<slug>/ where
# MAIN_ROOT is resolved internally from `git rev-parse --git-common-dir`
# (NEVER $PWD — /run-plan PR-mode dispatches run from a worktree so $PWD
# points at the wrong root; DA4.1 / DA7 invariant).
#
# Subcommands:
#   acquire <slug> --pipeline-id <id>
#     Exit 0  — acquired-fresh OR self-re-entry (caller already owns this
#               claim — the stored pipeline_id matches --pipeline-id).
#     Exit 2  — usage error (bad slug, missing flags).
#     Exit 10 — foreign-held by another pipeline (OR claim already exists
#               but claim.json absent/malformed — never steal).
#     Exit 11 — non-EEXIST mkdir failure / fs error / atomic-write failure
#               (EACCES/ENOSPC/EDQUOT/EROFS/...).
#   release <slug> --require-pipeline <id>
#     Exit 0  — released (or already absent — idempotent).
#     Exit 2  — usage error.
#     Exit 12 — release pipeline-id mismatch (claim left intact).
#
# Self-re-entry: the EEXIST arm of acquire delegates to
# create-worktree/scripts/claim-self-reentry.sh (a bash subprocess). A
# pipeline re-acquiring its OWN claim (same pipeline_id) gets exit 0; a
# foreign claim, an absent claim.json, or a malformed claim.json gets exit
# 10 (never steal). This makes a chunked `finish auto` re-fire re-acquiring
# the same plan return 0 instead of self-colliding on rc=10. No
# TTL/heartbeat/sweep.
#   set-phase <slug> --require-pipeline <id> --current-phase "<str>"
#     Exit 0  — current_phase updated (atomic write).
#     Exit 2  — claim.json missing for slug.
#     Exit 12 — pipeline-id mismatch (refused; no mutation).
#   list
#     One TSV line per live claim:
#       <slug>\t<pipeline_id>\t<age_seconds>
#
# Schema (claim.json, D5):
#   {schema_version, kind, slug, pipeline_id, started_at, current_phase}
#   sorted-keys, schema_version=1.
#   current_phase is initialised to "Phase 0 — acquired" at acquire and
#   updated by the `set-phase` subcommand. age_seconds is derived from
#   started_at.
#
# Atomicity:
#   acquire: `mkdir <dir>` is the POSIX atomic primitive; then write
#     claim.json.tmp and `os.replace` -> claim.json. mkdir failure after
#     EEXIST mapping; atomic-write failure rmdir's the claim dir (no stub).
#
# Orphan handling: if a claim is known-orphaned (e.g., the owning
# pipeline crashed), the operator runs `claim-plan.sh release <slug>
# --require-pipeline <stored-id>` explicitly. No automated TTL-based
# reaper exists; the existence of a claim file is the sole signal that
# the slug is in-flight.
#
# Slug sanitisation (DA13): bare slug argument is piped through
# sanitize-pipeline-id.sh before validation. Slugs containing `+`,
# leading `-`, or `_` are normalised; truly pathological slugs exit 2.
#
# No jq — Python stdlib json for read/write.
# No 2>/dev/null on fallible ops — the mkdir stderr text is load-bearing
# for the EEXIST-vs-other distinction.

set -u

# ---------------------------------------------------------------------------
# Python interpreter resolution (CLAUDE.md "Python is required").
# ---------------------------------------------------------------------------
_CLAIM_PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
if [ -z "$_CLAIM_PYTHON" ]; then
  echo "run-plan claim-plan.sh: install Python 3 (or set ZSKILLS_PYTHON)" >&2
  exit 127
fi

# ---------------------------------------------------------------------------
# Resolve script-bundle directory for sibling lookups (sanitize-pipeline-id.sh).
# ---------------------------------------------------------------------------
_CLAIM_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Locate sanitize-pipeline-id.sh — prefer sibling create-worktree skill
# layout, fall back to .claude/skills/ mirror, then to repo source tree.
_locate_sanitizer() {
  local candidates=(
    "$_CLAIM_SCRIPT_DIR/../../create-worktree/scripts/sanitize-pipeline-id.sh"
    "$_CLAIM_SCRIPT_DIR/../../../skills/create-worktree/scripts/sanitize-pipeline-id.sh"
  )
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    candidates+=(
      "${CLAUDE_PROJECT_DIR}/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh"
      "${CLAUDE_PROJECT_DIR}/skills/create-worktree/scripts/sanitize-pipeline-id.sh"
    )
  fi
  local c
  for c in "${candidates[@]}"; do
    if [ -f "$c" ]; then
      printf '%s' "$c"
      return 0
    fi
  done
  return 1
}

# Locate claim-self-reentry.sh — same precedence as _locate_sanitizer,
# reusing the _CLAIM_SCRIPT_DIR anchor. SOURCED at script load; the
# resolved PATH is invoked as a bash subprocess from the EEXIST arm of
# cmd_acquire.
_locate_self_reentry() {
  local candidates=(
    "$_CLAIM_SCRIPT_DIR/../../create-worktree/scripts/claim-self-reentry.sh"
    "$_CLAIM_SCRIPT_DIR/../../../skills/create-worktree/scripts/claim-self-reentry.sh"
  )
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    candidates+=(
      "${CLAUDE_PROJECT_DIR}/.claude/skills/create-worktree/scripts/claim-self-reentry.sh"
      "${CLAUDE_PROJECT_DIR}/skills/create-worktree/scripts/claim-self-reentry.sh"
    )
  fi
  local c
  for c in "${candidates[@]}"; do
    if [ -f "$c" ]; then
      printf '%s' "$c"
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# MAIN_ROOT resolution (DA4.1 / DA7).
# Every subcommand entry calls this. NEVER fall back to $PWD silently —
# the claim file landing in a worktree's tree would let two pipelines
# both claim the same plan because each would see "no claim" in its own
# worktree tree.
# ---------------------------------------------------------------------------
resolve_main_root() {
  local common_dir
  if ! common_dir=$(git rev-parse --git-common-dir 2>/dev/null); then
    echo "run-plan claim-plan.sh: cannot resolve MAIN_ROOT (not in a git working tree); cd into a project worktree first" >&2
    return 1
  fi
  if ! MAIN_ROOT=$(cd "$common_dir/.." && pwd); then
    echo "run-plan claim-plan.sh: cannot resolve MAIN_ROOT (failed to cd into git common dir parent)" >&2
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Slug validation + sanitisation (DA13).
#   1. Pipe through sanitize-pipeline-id.sh (normalises arbitrary chars
#      to `_`, truncates to 128 chars).
#   2. Post-sanitisation kebab-case check: ^[a-z0-9][a-z0-9-]*$.
#   3. On failure, return exit 2.
# Sets $SLUG to the sanitised form on success.
# ---------------------------------------------------------------------------
sanitize_and_validate_slug() {
  local raw="${1:-}"
  if [ -z "$raw" ]; then
    echo "run-plan claim-plan.sh: slug required" >&2
    return 2
  fi
  local sanitizer
  if ! sanitizer=$(_locate_sanitizer); then
    echo "run-plan claim-plan.sh: cannot locate sanitize-pipeline-id.sh (looked in create-worktree skill bundle)" >&2
    return 2
  fi
  local sanitised
  if ! sanitised=$(bash "$sanitizer" "$raw" 2>/dev/null); then
    echo "run-plan claim-plan.sh: slug sanitisation failed for '$raw'" >&2
    return 2
  fi
  # Post-sanitise kebab-case validation. The sanitizer leaves `+`, `_`,
  # leading `-` as-is when they're already in [a-zA-Z0-9._-] — but those
  # are NOT valid for a plan slug. Apply the strict regex here.
  if [[ ! "$sanitised" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    echo "run-plan claim-plan.sh: invalid slug '$raw' (sanitised='$sanitised'; must match ^[a-z0-9][a-z0-9-]*$ — kebab-case)" >&2
    return 2
  fi
  SLUG="$sanitised"
  return 0
}

# ---------------------------------------------------------------------------
# acquire <slug> --pipeline-id <id>
# ---------------------------------------------------------------------------
cmd_acquire() {
  local raw_slug="" pipeline_id=""
  if [ "$#" -lt 1 ]; then
    echo "Usage: claim-plan.sh acquire <slug> --pipeline-id <id>" >&2
    return 2
  fi
  raw_slug="$1"; shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --pipeline-id) pipeline_id="${2:-}"; shift 2 ;;
      *) echo "run-plan claim-plan.sh acquire: unknown arg '$1'" >&2; return 2 ;;
    esac
  done
  sanitize_and_validate_slug "$raw_slug" || return 2
  if [ -z "$pipeline_id" ]; then
    echo "run-plan claim-plan.sh acquire: --pipeline-id is required" >&2
    return 2
  fi
  resolve_main_root || return 2

  local claims_root="${MAIN_ROOT}/.zskills/claims"
  local claim_dir="${claims_root}/plan-${SLUG}"
  local claim_file="${claim_dir}/claim.json"
  local claim_tmp="${claim_dir}/claim.json.tmp"

  if ! mkdir -p "$claims_root" 2>&1; then
    echo "run-plan claim-plan.sh acquire: failed to create $claims_root" >&2
    return 11
  fi

  # Atomic acquire: mkdir of the claim dir itself.
  local mkdir_err mkdir_status
  # LC_ALL=C forces mkdir's diagnostic to the English "File exists" the
  # case arm below greps for. Without it, a non-English LC_MESSAGES
  # localizes the diagnostic and the EEXIST branch silently misses,
  # returning rc=11 instead of routing to self-re-entry (issue #827).
  mkdir_err=$(LC_ALL=C mkdir "$claim_dir" 2>&1)
  mkdir_status=$?
  if [ "$mkdir_status" -ne 0 ]; then
    case "$mkdir_err" in
      *"File exists"*)
        # Ownership-aware self-re-entry: delegate to the shared helper as a
        # bash SUBPROCESS (its exit 10/0 contract would terminate a sourcing
        # caller). Helper exit 0 → self → return 0; exit 10 → foreign →
        # return 10. If the helper cannot be located, fail conservative
        # (return 10, never silently steal) with a one-line WARN.
        local sr_helper
        if ! sr_helper=$(_locate_self_reentry); then
          echo "run-plan claim-plan.sh acquire: cannot locate claim-self-reentry.sh (looked in create-worktree bundle); treating existing claim as foreign" >&2
          return 10
        fi
        bash "$sr_helper" "$claim_dir" "$pipeline_id"
        local sr_rc=$?
        if [ "$sr_rc" -eq 0 ]; then
          return 0
        fi
        return 10
        ;;
      *)
        echo "$mkdir_err" >&2
        echo "run-plan claim-plan.sh acquire: mkdir failed (non-EEXIST) for $claim_dir" >&2
        return 11
        ;;
    esac
  fi

  # Atomic write of claim.json. current_phase is initialised to
  # "Phase 0 — acquired" so the dashboard chip renders `phase 0/M`
  # immediately on acquire (not `phase ?/M`); subsequent updates flow
  # through the `set-phase` subcommand.
  if ! "$_CLAIM_PYTHON" - "$claim_tmp" "$claim_file" "$pipeline_id" "$SLUG" <<'PY'
import json, os, sys, datetime
tmp_path, final_path, pipeline_id, slug = sys.argv[1:5]
now = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
body = {
    "schema_version":     1,
    "kind":               "plan",
    "slug":               slug,
    "pipeline_id":        pipeline_id,
    "started_at":         now,
    "current_phase":      "Phase 0 — acquired",
}
with open(tmp_path, "w") as f:
    json.dump(body, f, sort_keys=True)
    f.write("\n")
os.replace(tmp_path, final_path)
PY
  then
    rm -f "$claim_tmp"
    rmdir "$claim_dir" 2>&1 || true
    echo "run-plan claim-plan.sh acquire: atomic write failed for $claim_file" >&2
    return 11
  fi

  return 0
}

# ---------------------------------------------------------------------------
# release <slug> --require-pipeline <id>
# ---------------------------------------------------------------------------
cmd_release() {
  local raw_slug="" require_pipeline=""
  if [ "$#" -lt 1 ]; then
    echo "Usage: claim-plan.sh release <slug> --require-pipeline <id>" >&2
    return 2
  fi
  raw_slug="$1"; shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --require-pipeline) require_pipeline="${2:-}"; shift 2 ;;
      *) echo "run-plan claim-plan.sh release: unknown arg '$1'" >&2; return 2 ;;
    esac
  done
  sanitize_and_validate_slug "$raw_slug" || return 2
  if [ -z "$require_pipeline" ]; then
    echo "run-plan claim-plan.sh release: --require-pipeline is required" >&2
    return 2
  fi
  resolve_main_root || return 2

  local claim_dir="${MAIN_ROOT}/.zskills/claims/plan-${SLUG}"
  local claim_file="${claim_dir}/claim.json"

  # Idempotent.
  if [ ! -d "$claim_dir" ]; then
    return 0
  fi

  if [ -f "$claim_file" ]; then
    local actual
    actual=$("$_CLAIM_PYTHON" -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        print(json.load(f).get('pipeline_id', ''))
except Exception:
    pass
" "$claim_file")
    if [ "$actual" != "$require_pipeline" ]; then
      echo "run-plan claim-plan.sh release: pipeline mismatch for plan ${SLUG} (require=${require_pipeline} actual=${actual}); refusing release" >&2
      return 12
    fi
  fi

  rm -f "$claim_file"
  rm -f "${claim_dir}/claim.json.tmp"
  rmdir "$claim_dir"
  return 0
}

# ---------------------------------------------------------------------------
# set-phase <slug> --require-pipeline <id> --current-phase "<str>"
# Thin UX-only mutator: read claim.json, gate on pipeline_id match,
# rewrite current_phase, atomic write. No TTL/state-machine/auto-acquire.
# ---------------------------------------------------------------------------
cmd_set_phase() {
  local raw_slug="" require_pipeline="" current_phase="" current_phase_set=0
  if [ "$#" -lt 1 ]; then
    echo "Usage: claim-plan.sh set-phase <slug> --require-pipeline <id> --current-phase \"<str>\"" >&2
    return 2
  fi
  raw_slug="$1"; shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --require-pipeline) require_pipeline="${2:-}"; shift 2 ;;
      --current-phase)    current_phase="${2:-}"; current_phase_set=1; shift 2 ;;
      *) echo "run-plan claim-plan.sh set-phase: unknown arg '$1'" >&2; return 2 ;;
    esac
  done
  sanitize_and_validate_slug "$raw_slug" || return 2
  if [ -z "$require_pipeline" ]; then
    echo "run-plan claim-plan.sh set-phase: --require-pipeline is required" >&2
    return 2
  fi
  if [ "$current_phase_set" -eq 0 ]; then
    echo "run-plan claim-plan.sh set-phase: --current-phase is required" >&2
    return 2
  fi
  resolve_main_root || return 2

  local claim_dir="${MAIN_ROOT}/.zskills/claims/plan-${SLUG}"
  local claim_file="${claim_dir}/claim.json"
  local claim_tmp="${claim_dir}/claim.json.tmp"

  if [ ! -f "$claim_file" ]; then
    echo "run-plan claim-plan.sh set-phase: claim.json missing for slug ${SLUG}" >&2
    return 2
  fi

  "$_CLAIM_PYTHON" - "$claim_file" "$claim_tmp" "$require_pipeline" "$current_phase" <<'PY'
import json, os, sys
claim_file, tmp_path, required, new_phase = sys.argv[1:5]
with open(claim_file) as f:
    body = json.load(f)
stored = body.get("pipeline_id", "")
if stored != required:
    sys.stderr.write(
        "pipeline-mismatch: stored={} required={}; refusing set-phase\n".format(stored, required)
    )
    sys.exit(12)
body["current_phase"] = new_phase
with open(tmp_path, "w") as f:
    json.dump(body, f, sort_keys=True)
    f.write("\n")
os.replace(tmp_path, claim_file)
PY
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    rm -f "$claim_tmp"
    return "$rc"
  fi
  return 0
}

# Internal helper: age in seconds, or -1 on error. Derived from
# started_at (no last_heartbeat_at fallback — clean cut post-#684).
_age_for_claim() {
  local claim_file="$1"
  "$_CLAIM_PYTHON" -c "
import json, sys, datetime
try:
    with open(sys.argv[1]) as f:
        body = json.load(f)
    started = datetime.datetime.fromisoformat(body['started_at'])
    if started.tzinfo is None:
        started = started.replace(tzinfo=datetime.timezone.utc)
    now = datetime.datetime.now(datetime.timezone.utc)
    print(int((now - started).total_seconds()))
except Exception:
    print(-1)
" "$claim_file"
}

_pipeline_for_claim() {
  local claim_file="$1"
  "$_CLAIM_PYTHON" -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        print(json.load(f).get('pipeline_id', ''))
except Exception:
    pass
" "$claim_file"
}

# ---------------------------------------------------------------------------
# list — TSV: <slug>\t<pipeline_id>\t<age_seconds>
# ---------------------------------------------------------------------------
cmd_list() {
  resolve_main_root || return 2

  local claims_root="${MAIN_ROOT}/.zskills/claims"
  if [ ! -d "$claims_root" ]; then
    return 0
  fi

  local d
  for d in "$claims_root"/plan-*; do
    [ -d "$d" ] || continue
    local slug
    slug=$(basename "$d" | sed 's/^plan-//')
    case "$slug" in
      '') continue ;;
    esac
    if [[ ! "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
      continue
    fi
    local claim_file="${d}/claim.json"
    [ -f "$claim_file" ] || continue
    local pipeline_id
    pipeline_id=$(_pipeline_for_claim "$claim_file")
    local age
    age=$(_age_for_claim "$claim_file")
    printf '%s\t%s\t%s\n' "$slug" "$pipeline_id" "$age"
  done
  return 0
}

# ---------------------------------------------------------------------------
# Dispatch.
# ---------------------------------------------------------------------------
main() {
  local sub="${1:-}"
  if [ -z "$sub" ]; then
    echo "Usage: claim-plan.sh {acquire|release|set-phase|list} [args...]" >&2
    return 2
  fi
  shift
  case "$sub" in
    acquire)    cmd_acquire "$@" ;;
    release)    cmd_release "$@" ;;
    set-phase)  cmd_set_phase "$@" ;;
    list)       cmd_list "$@" ;;
    *)
      echo "run-plan claim-plan.sh: unknown subcommand '$sub'" >&2
      echo "Usage: claim-plan.sh {acquire|release|set-phase|list} [args...]" >&2
      return 2
      ;;
  esac
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  main "$@"
  exit $?
fi
