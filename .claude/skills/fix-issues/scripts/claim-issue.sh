#!/bin/bash
# claim-issue.sh — Filesystem-anchored claim primitive for /fix-issues.
#
# Provides exclusive per-issue claims via atomic mkdir + a JSON metadata
# file. Claims live under ${MAIN_ROOT}/.zskills/claims/issue-<N>/ where
# MAIN_ROOT is resolved internally from `git rev-parse --git-common-dir`
# (NEVER $PWD — the per-issue dispatch fence in /fix-issues runs from a
# sprint worktree, so $PWD points at the wrong root at acquire time).
#
# Subcommands:
#   acquire <N> --pipeline-id <id> --sprint-id <id>
#     Exit 0  — acquired (claim.json atomically written).
#     Exit 10 — EEXIST: claim already held by another pipeline.
#     Exit 11 — non-EEXIST mkdir failure (EACCES/ENOSPC/EDQUOT/EROFS/...).
#   release <N> [--require-pipeline <id>]
#     Exit 0  — released (or already absent — idempotent).
#     Exit 12 — pipeline-id mismatch (refused; claim left intact).
#   is-stale <N>
#     Race-tolerance check ONLY: stale iff the claim dir exists without
#     claim.json and is older than 30s (mkdir-succeeded-then-crashed).
#     Exit 0  — stale (dir w/o claim.json > 30s old).
#     Exit 1  — fresh.
#     Exit 2  — no claim.
#   list
#     Pure read. Emits one TSV line per live claim:
#       <N>\t<pipeline_id>\t<age_seconds>
#
# Schema (claim.json):
#   {schema_version, pipeline_id, sprint_id, issue, started_at}
#   No worktree_path (DA8). No host_pid (DA2.1/DA2.2). Future fields
#   added with .get() defaults in readers; schema_version bumps if a
#   breaking change is ever needed.
#
# Atomicity: `mkdir <dir>` is the POSIX atomic primitive. On success,
# write claim.json.tmp then `os.replace` to claim.json. If the
# atomic-write step fails after mkdir succeeded, the script rmdir's the
# claim dir before returning non-zero (no stub leak).
#
# No jq — Python stdlib json for write/read.
# No 2>/dev/null on fallible ops — the mkdir stderr text is load-bearing
# for the EEXIST-vs-other distinction.

set -u

# ---------------------------------------------------------------------------
# Python interpreter resolution. Honours the project's documented
# ZSKILLS_PYTHON override (see CLAUDE.md "Python is required" section).
# ---------------------------------------------------------------------------
_CLAIM_PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
if [ -z "$_CLAIM_PYTHON" ]; then
  echo "fix-issues claim-issue.sh: install Python 3 (or set ZSKILLS_PYTHON)" >&2
  exit 127
fi

# ---------------------------------------------------------------------------
# MAIN_ROOT resolution (DA4.1 — round 4b).
# Every subcommand entry calls this. NEVER fall back to $PWD silently —
# a silent fallback would re-introduce the bug DA4.1 documents (claims
# landing inside a sprint worktree, hook false-denying every valid
# create-worktree.sh call, dashboard chip never appearing).
# ---------------------------------------------------------------------------
resolve_main_root() {
  local common_dir
  if ! common_dir=$(git rev-parse --git-common-dir 2>/dev/null); then
    echo "fix-issues claim-issue.sh: cannot resolve MAIN_ROOT (not in a git working tree); cd into a project worktree first" >&2
    return 1
  fi
  # git rev-parse --git-common-dir is relative to $PWD; resolve absolutely.
  if ! MAIN_ROOT=$(cd "$common_dir/.." && pwd); then
    echo "fix-issues claim-issue.sh: cannot resolve MAIN_ROOT (failed to cd into git common dir parent)" >&2
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Validate $N as a positive integer (rejects 0, empty, non-numeric).
# ---------------------------------------------------------------------------
validate_issue_number() {
  local n="${1:-}"
  if [ -z "$n" ]; then
    echo "fix-issues claim-issue.sh: issue number required" >&2
    return 1
  fi
  case "$n" in
    ''|*[!0-9]*)
      echo "fix-issues claim-issue.sh: invalid issue number '$n' (must be positive integer)" >&2
      return 1
      ;;
  esac
  if [ "$n" -le 0 ]; then
    echo "fix-issues claim-issue.sh: invalid issue number '$n' (must be > 0)" >&2
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# acquire <N> --pipeline-id <id> --sprint-id <id>
# ---------------------------------------------------------------------------
cmd_acquire() {
  local n="" pipeline_id="" sprint_id=""
  if [ "$#" -lt 1 ]; then
    echo "Usage: claim-issue.sh acquire <N> --pipeline-id <id> --sprint-id <id>" >&2
    return 2
  fi
  n="$1"; shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --pipeline-id) pipeline_id="${2:-}"; shift 2 ;;
      --sprint-id)   sprint_id="${2:-}"; shift 2 ;;
      *) echo "fix-issues claim-issue.sh acquire: unknown arg '$1'" >&2; return 2 ;;
    esac
  done
  validate_issue_number "$n" || return 2
  if [ -z "$pipeline_id" ] || [ -z "$sprint_id" ]; then
    echo "fix-issues claim-issue.sh acquire: --pipeline-id and --sprint-id are required" >&2
    return 2
  fi
  resolve_main_root || return 2

  local claims_root="${MAIN_ROOT}/.zskills/claims"
  local claim_dir="${claims_root}/issue-${n}"
  local claim_file="${claim_dir}/claim.json"
  local claim_tmp="${claim_dir}/claim.json.tmp"

  # Ensure parent (.zskills/claims/) exists. NOT atomic; this is the
  # ancestor dir, not the claim dir.
  if ! mkdir -p "$claims_root" 2>&1; then
    echo "fix-issues claim-issue.sh acquire: failed to create $claims_root" >&2
    return 11
  fi

  # Atomic acquire: mkdir of the claim dir itself. NO 2>/dev/null — the
  # stderr text distinguishes EEXIST from other failures.
  local mkdir_err
  mkdir_err=$(mkdir "$claim_dir" 2>&1)
  local mkdir_status=$?
  if [ "$mkdir_status" -ne 0 ]; then
    # Map "File exists" -> 10; anything else -> 11.
    case "$mkdir_err" in
      *"File exists"*)
        return 10
        ;;
      *)
        echo "$mkdir_err" >&2
        echo "fix-issues claim-issue.sh acquire: mkdir failed (non-EEXIST) for $claim_dir" >&2
        return 11
        ;;
    esac
  fi

  # Atomic write of claim.json via Python: write claim.json.tmp then
  # os.replace -> claim.json. ISO-8601 UTC for started_at.
  if ! "$_CLAIM_PYTHON" - "$claim_tmp" "$claim_file" "$pipeline_id" "$sprint_id" "$n" <<'PY'
import json, os, sys, datetime
tmp_path, final_path, pipeline_id, sprint_id, issue_s = sys.argv[1:6]
body = {
    "schema_version": 1,
    "pipeline_id": pipeline_id,
    "sprint_id":   sprint_id,
    "issue":       int(issue_s),
    "started_at":  datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
}
with open(tmp_path, "w") as f:
    json.dump(body, f, sort_keys=True)
    f.write("\n")
os.replace(tmp_path, final_path)
PY
  then
    # Atomic-write failed after mkdir succeeded — rmdir the claim dir to
    # avoid stub leak. Also remove any half-written tmp if present.
    rm -f "$claim_tmp"
    rmdir "$claim_dir" 2>&1 || true
    echo "fix-issues claim-issue.sh acquire: atomic write failed for $claim_file" >&2
    return 11
  fi

  return 0
}

# ---------------------------------------------------------------------------
# release <N> [--require-pipeline <id>]
# ---------------------------------------------------------------------------
cmd_release() {
  local n="" require_pipeline=""
  if [ "$#" -lt 1 ]; then
    echo "Usage: claim-issue.sh release <N> [--require-pipeline <id>]" >&2
    return 2
  fi
  n="$1"; shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --require-pipeline) require_pipeline="${2:-}"; shift 2 ;;
      *) echo "fix-issues claim-issue.sh release: unknown arg '$1'" >&2; return 2 ;;
    esac
  done
  validate_issue_number "$n" || return 2
  resolve_main_root || return 2

  local claim_dir="${MAIN_ROOT}/.zskills/claims/issue-${n}"
  local claim_file="${claim_dir}/claim.json"

  # Idempotent: absent claim is a no-op success.
  if [ ! -d "$claim_dir" ]; then
    return 0
  fi

  # Pipeline-id check (when --require-pipeline supplied).
  if [ -n "$require_pipeline" ] && [ -f "$claim_file" ]; then
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
      echo "fix-issues claim-issue.sh release: pipeline mismatch for issue $n (require=$require_pipeline actual=$actual); refusing release" >&2
      return 12
    fi
  fi

  # Per-file removal (R2/DA3). NEVER `rm -rf` — even though the hook
  # cannot see script-internal commands, the per-file shape is simpler,
  # safer, and equally atomic for this two-file structure.
  rm -f "$claim_file"
  # claim.json.tmp may exist if a prior acquire crashed between mkdir
  # and replace; clean it up too so rmdir succeeds.
  rm -f "${claim_dir}/claim.json.tmp"
  rmdir "$claim_dir"
  return 0
}

# ---------------------------------------------------------------------------
# is-stale <N>
#   Race-tolerance check ONLY. A claim is "stale" iff the claim dir exists
#   without claim.json and is older than 30s — the
#   mkdir-succeeded-then-crashed window. A live claim (claim.json present)
#   is NEVER stale; claims are released at land-or-abandon, not aged out.
#   exit 0 = stale, 1 = fresh, 2 = no claim
# ---------------------------------------------------------------------------
cmd_is_stale() {
  local n="${1:-}"
  validate_issue_number "$n" || return 2
  resolve_main_root || return 2

  local claim_dir="${MAIN_ROOT}/.zskills/claims/issue-${n}"
  local claim_file="${claim_dir}/claim.json"

  if [ ! -d "$claim_dir" ]; then
    return 2
  fi

  if [ ! -f "$claim_file" ]; then
    # Crash window: dir exists but claim.json is missing. If dir mtime
    # is older than 30s, treat as stale (mkdir-succeeded-then-crashed).
    # Otherwise treat as fresh (in-flight write window).
    local age
    age=$("$_CLAIM_PYTHON" -c "
import os, sys, time
try:
    print(int(time.time() - os.stat(sys.argv[1]).st_mtime))
except Exception:
    print(-1)
" "$claim_dir")
    if [ "$age" -ge 30 ] 2>/dev/null; then
      return 0
    fi
    return 1
  fi

  # claim.json present — a live claim is never stale. Lifecycle is
  # acquire-at-pick, release-at-land-or-abandon (no TTL aging).
  return 1
}

# Internal helper: returns age in seconds, or -1 on error. Used by list.
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
# list — TSV: <N>\t<pipeline_id>\t<age_seconds>
# ---------------------------------------------------------------------------
cmd_list() {
  resolve_main_root || return 2

  local claims_root="${MAIN_ROOT}/.zskills/claims"
  if [ ! -d "$claims_root" ]; then
    return 0
  fi

  local d
  for d in "$claims_root"/issue-*; do
    [ -d "$d" ] || continue
    local n
    n=$(basename "$d" | sed 's/^issue-//')
    case "$n" in
      ''|*[!0-9]*) continue ;;
    esac
    local claim_file="${d}/claim.json"
    [ -f "$claim_file" ] || continue
    local pipeline_id
    pipeline_id=$(_pipeline_for_claim "$claim_file")
    local age
    age=$(_age_for_claim "$claim_file")
    printf '%s\t%s\t%s\n' "$n" "$pipeline_id" "$age"
  done
  return 0
}

# ---------------------------------------------------------------------------
# Dispatch.
# ---------------------------------------------------------------------------
main() {
  local sub="${1:-}"
  if [ -z "$sub" ]; then
    echo "Usage: claim-issue.sh {acquire|release|is-stale|list} [args...]" >&2
    return 2
  fi
  shift
  case "$sub" in
    acquire)  cmd_acquire "$@" ;;
    release)  cmd_release "$@" ;;
    is-stale) cmd_is_stale "$@" ;;
    list)     cmd_list "$@" ;;
    *)
      echo "fix-issues claim-issue.sh: unknown subcommand '$sub'" >&2
      echo "Usage: claim-issue.sh {acquire|release|is-stale|list} [args...]" >&2
      return 2
      ;;
  esac
}

# Execute only when invoked directly (allow sourcing for tests).
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  main "$@"
  exit $?
fi
