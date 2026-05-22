#!/bin/bash
# claim-plan.sh — Filesystem-anchored claim primitive for /run-plan.
#
# Sibling of skills/fix-issues/scripts/claim-issue.sh — mirrors the ~91%
# generic structure (resolve_main_root, atomic mkdir, Python helpers,
# exit-code mapping). Adds the `refresh` subcommand which has no
# claim-issue.sh analogue (it's read-modify-write, not atomic-mkdir).
#
# Provides exclusive per-plan claims via atomic mkdir + a JSON metadata
# file. Claims live under ${MAIN_ROOT}/.zskills/claims/plan-<slug>/ where
# MAIN_ROOT is resolved internally from `git rev-parse --git-common-dir`
# (NEVER $PWD — /run-plan PR-mode dispatches run from a worktree so $PWD
# points at the wrong root; DA4.1 / DA7 invariant).
#
# Subcommands:
#   acquire <slug> --pipeline-id <id>
#     Exit 0  — acquired (claim.json atomically written).
#     Exit 2  — usage error (bad slug, missing flags).
#     Exit 10 — EEXIST: claim already held by another pipeline.
#     Exit 11 — non-EEXIST mkdir failure (EACCES/ENOSPC/EDQUOT/EROFS/...).
#   refresh <slug> --require-pipeline <id> --current-phase "Phase <N>"
#     Exit 0  — refreshed.
#     Exit 2  — usage error or claim.json missing (caller should re-acquire).
#     Exit 12 — pipeline-id mismatch (refused; claim left intact).
#   release <slug> --require-pipeline <id>
#     Exit 0  — released (or already absent — idempotent).
#     Exit 12 — pipeline-id mismatch (refused; claim left intact).
#   is-stale <slug>
#     Exit 0  — stale (older than TTL, or dir w/o claim.json > 30s old).
#     Exit 1  — fresh.
#     Exit 2  — no claim.
#   sweep
#     Iterates all plan-* claims; releases stale ones. Always exits 0.
#   list
#     One TSV line per live claim:
#       <slug>\t<pipeline_id>\t<age_seconds>
#
# Schema (claim.json, D5):
#   {schema_version, kind, slug, pipeline_id, started_at,
#    last_heartbeat_at, current_phase}
#   sorted-keys, schema_version=1.
#
# Atomicity:
#   acquire: `mkdir <dir>` is the POSIX atomic primitive; then write
#     claim.json.tmp and `os.replace` -> claim.json. mkdir failure after
#     EEXIST mapping; atomic-write failure rmdir's the claim dir (no stub).
#   refresh: NO mkdir step (claim dir must already exist). Pure Python
#     read-modify-write via os.replace. The os.replace is POSIX-atomic so
#     readers either see pre-replace or post-replace, never partial JSON.
#
# TTL resolution: 5-level chain (env-plan > config-plan > env-shared >
#   config-shared > built-in 7200). Implemented inline (D7 option (b)) so
#   the resolver itself stays untouched; the precedence test fixtures the
#   env + config inputs together and asserts each level.
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
# TTL resolution (5-level chain — D7 R2.2):
#   1. env  ZSKILLS_PLAN_CLAIM_TTL_SECONDS    (plan-specific override)
#   2. config execution.plan_claim_ttl_seconds (plan-specific)
#   3. env  ZSKILLS_CLAIM_TTL_SECONDS         (shared fallback)
#   4. config execution.claim_ttl_seconds      (shared fallback)
#   5. built-in 7200
# Resolution implemented inline (D7 option (b)) — the resolver itself is
# unchanged; this script reads the config directly via Python json.
# ---------------------------------------------------------------------------
resolve_ttl() {
  local _ZSK_CFG="${CLAUDE_PROJECT_DIR:-${MAIN_ROOT:-$PWD}}/.claude/zskills-config.json"
  local ttl=""

  # Level 1: env plan-specific.
  ttl="${ZSKILLS_PLAN_CLAIM_TTL_SECONDS:-}"

  # Level 2: config plan-specific.
  if [ -z "$ttl" ] && [ -f "$_ZSK_CFG" ]; then
    ttl=$("$_CLAIM_PYTHON" -c "import json
try:
  d=json.load(open('$_ZSK_CFG')).get('execution',{})
  v=d.get('plan_claim_ttl_seconds')
  print(v if v is not None else '')
except Exception:
  print('')" 2>/dev/null) || ttl=""
  fi

  # Level 3: env shared.
  [ -z "$ttl" ] && ttl="${ZSKILLS_CLAIM_TTL_SECONDS:-}"

  # Level 4: config shared.
  if [ -z "$ttl" ] && [ -f "$_ZSK_CFG" ]; then
    ttl=$("$_CLAIM_PYTHON" -c "import json
try:
  d=json.load(open('$_ZSK_CFG')).get('execution',{})
  v=d.get('claim_ttl_seconds')
  print(v if v is not None else '')
except Exception:
  print('')" 2>/dev/null) || ttl=""
  fi

  # Level 5: built-in.
  [ -z "$ttl" ] && ttl=7200

  # Sanity: integer + floor 60.
  case "$ttl" in
    ''|*[!0-9]*) ttl=7200 ;;
  esac
  if [ "$ttl" -lt 60 ] 2>/dev/null; then
    ttl=7200
  fi
  echo "$ttl"
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
  mkdir_err=$(mkdir "$claim_dir" 2>&1)
  mkdir_status=$?
  if [ "$mkdir_status" -ne 0 ]; then
    case "$mkdir_err" in
      *"File exists"*)
        return 10
        ;;
      *)
        echo "$mkdir_err" >&2
        echo "run-plan claim-plan.sh acquire: mkdir failed (non-EEXIST) for $claim_dir" >&2
        return 11
        ;;
    esac
  fi

  # Atomic write of claim.json. Initial last_heartbeat_at = started_at.
  # current_phase defaults to empty string until first refresh.
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
    "last_heartbeat_at":  now,
    "current_phase":      "",
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
# refresh <slug> --require-pipeline <id> --current-phase "Phase <N>"
# Read-modify-write — no mkdir, no EEXIST mapping.
# ---------------------------------------------------------------------------
cmd_refresh() {
  local raw_slug="" require_pipeline="" current_phase=""
  local current_phase_set=0
  if [ "$#" -lt 1 ]; then
    echo "Usage: claim-plan.sh refresh <slug> --require-pipeline <id> --current-phase \"Phase <N>\"" >&2
    return 2
  fi
  raw_slug="$1"; shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --require-pipeline) require_pipeline="${2:-}"; shift 2 ;;
      --current-phase)    current_phase="${2:-}"; current_phase_set=1; shift 2 ;;
      *) echo "run-plan claim-plan.sh refresh: unknown arg '$1'" >&2; return 2 ;;
    esac
  done
  sanitize_and_validate_slug "$raw_slug" || return 2
  if [ -z "$require_pipeline" ]; then
    echo "run-plan claim-plan.sh refresh: --require-pipeline is required" >&2
    return 2
  fi
  if [ "$current_phase_set" -eq 0 ]; then
    echo "run-plan claim-plan.sh refresh: --current-phase is required" >&2
    return 2
  fi
  resolve_main_root || return 2

  local claim_dir="${MAIN_ROOT}/.zskills/claims/plan-${SLUG}"
  local claim_file="${claim_dir}/claim.json"
  local claim_tmp="${claim_dir}/claim.json.tmp"

  if [ ! -f "$claim_file" ]; then
    echo "claim.json missing for slug ${SLUG}; use acquire to create." >&2
    return 2
  fi

  # Read-modify-write with mismatch check. Python returns a structured
  # status line: "OK", "MISMATCH stored=<X>", or "ERR <reason>".
  local result
  result=$("$_CLAIM_PYTHON" - "$claim_file" "$claim_tmp" "$require_pipeline" "$current_phase" <<'PY'
import json, os, sys, datetime
claim_file, tmp_path, require_pipeline, current_phase = sys.argv[1:5]
try:
    with open(claim_file) as f:
        body = json.load(f)
except Exception as e:
    print("ERR read:" + str(e))
    sys.exit(0)
stored = body.get("pipeline_id", "")
if stored != require_pipeline:
    print("MISMATCH stored=" + stored)
    sys.exit(0)
body["last_heartbeat_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
body["current_phase"] = current_phase
try:
    with open(tmp_path, "w") as f:
        json.dump(body, f, sort_keys=True)
        f.write("\n")
    os.replace(tmp_path, claim_file)
except Exception as e:
    # Best-effort tmp cleanup on write failure.
    try:
        os.unlink(tmp_path)
    except Exception:
        pass
    print("ERR write:" + str(e))
    sys.exit(0)
print("OK")
PY
)
  case "$result" in
    OK)
      return 0
      ;;
    MISMATCH*)
      local stored="${result#MISMATCH stored=}"
      echo "run-plan claim-plan.sh refresh: pipeline-mismatch: stored=${stored} required=${require_pipeline}; refusing refresh." >&2
      return 12
      ;;
    ERR*)
      echo "run-plan claim-plan.sh refresh: ${result}" >&2
      return 11
      ;;
    *)
      echo "run-plan claim-plan.sh refresh: unexpected helper output: ${result}" >&2
      return 11
      ;;
  esac
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
# is-stale <slug>
#   exit 0 = stale, 1 = fresh, 2 = no claim / unparseable
#
# Crash-window protection: if claim.json missing inside an existing claim
# dir and dir mtime > 30s ago, treat as stale (acquire crashed between
# mkdir and write). Otherwise treat as fresh (in-flight write window).
# ---------------------------------------------------------------------------
cmd_is_stale() {
  local raw_slug="${1:-}"
  sanitize_and_validate_slug "$raw_slug" || return 2
  resolve_main_root || return 2

  local claim_dir="${MAIN_ROOT}/.zskills/claims/plan-${SLUG}"
  local claim_file="${claim_dir}/claim.json"
  local ttl
  ttl=$(resolve_ttl)

  if [ ! -d "$claim_dir" ]; then
    return 2
  fi

  if [ ! -f "$claim_file" ]; then
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

  # claim.json present — parse last_heartbeat_at (NOT started_at) and
  # compare to NOW - TTL. The heartbeat is the freshness signal; refresh
  # advances it each phase, so a wedged pipeline stops bumping it and
  # the TTL fires.
  local age
  age=$("$_CLAIM_PYTHON" -c "
import json, sys, datetime
try:
    with open(sys.argv[1]) as f:
        body = json.load(f)
    hb = body.get('last_heartbeat_at') or body.get('started_at')
    started = datetime.datetime.fromisoformat(hb)
    if started.tzinfo is None:
        started = started.replace(tzinfo=datetime.timezone.utc)
    now = datetime.datetime.now(datetime.timezone.utc)
    print(int((now - started).total_seconds()))
except Exception:
    print(-1)
" "$claim_file")

  if [ "$age" -lt 0 ] 2>/dev/null; then
    return 0
  fi
  if [ "$age" -ge "$ttl" ] 2>/dev/null; then
    return 0
  fi
  return 1
}

# Internal helper: age in seconds, or -1 on error.
_age_for_claim() {
  local claim_file="$1"
  "$_CLAIM_PYTHON" -c "
import json, sys, datetime
try:
    with open(sys.argv[1]) as f:
        body = json.load(f)
    hb = body.get('last_heartbeat_at') or body.get('started_at')
    started = datetime.datetime.fromisoformat(hb)
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
# sweep — iterate claims, release stale ones.
# ---------------------------------------------------------------------------
cmd_sweep() {
  resolve_main_root || return 2

  local claims_root="${MAIN_ROOT}/.zskills/claims"
  if [ ! -d "$claims_root" ]; then
    return 0
  fi

  local ttl
  ttl=$(resolve_ttl)

  local d
  for d in "$claims_root"/plan-*; do
    [ -d "$d" ] || continue
    local slug
    slug=$(basename "$d" | sed 's/^plan-//')
    # Skip directories that don't match the kebab-case plan-slug shape.
    case "$slug" in
      '') continue ;;
    esac
    if [[ ! "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
      continue
    fi

    local claim_file="${d}/claim.json"
    local reason="" age=""
    local pipeline_id=""

    if [ ! -f "$claim_file" ]; then
      age=$("$_CLAIM_PYTHON" -c "
import os, sys, time
try:
    print(int(time.time() - os.stat(sys.argv[1]).st_mtime))
except Exception:
    print(-1)
" "$d")
      if [ "$age" -ge 30 ] 2>/dev/null; then
        reason="metadata"
        pipeline_id=""
      else
        continue
      fi
    else
      age=$(_age_for_claim "$claim_file")
      pipeline_id=$(_pipeline_for_claim "$claim_file")
      if [ "$age" -lt 0 ] 2>/dev/null; then
        reason="metadata"
      elif [ "$age" -ge "$ttl" ] 2>/dev/null; then
        reason="ttl"
      else
        continue
      fi
    fi

    rm -f "$claim_file"
    rm -f "${d}/claim.json.tmp"
    rmdir "$d" 2>&1 || true

    echo "run-plan claims: swept stale claim plan-${slug} pipeline=${pipeline_id} age=${age}s reason=${reason}" >&2
  done
  return 0
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
    echo "Usage: claim-plan.sh {acquire|refresh|release|is-stale|sweep|list} [args...]" >&2
    return 2
  fi
  shift
  case "$sub" in
    acquire)  cmd_acquire "$@" ;;
    refresh)  cmd_refresh "$@" ;;
    release)  cmd_release "$@" ;;
    is-stale) cmd_is_stale "$@" ;;
    sweep)    cmd_sweep "$@" ;;
    list)     cmd_list "$@" ;;
    *)
      echo "run-plan claim-plan.sh: unknown subcommand '$sub'" >&2
      echo "Usage: claim-plan.sh {acquire|refresh|release|is-stale|sweep|list} [args...]" >&2
      return 2
      ;;
  esac
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  main "$@"
  exit $?
fi
