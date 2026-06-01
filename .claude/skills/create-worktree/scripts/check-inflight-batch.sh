#!/bin/bash
# check-inflight-batch.sh — Shared session-scoped in-flight guard for
# queue-pickup workers (/fix-issues sprint, /work-on-plans batch,
# /qe-audit audit; closes the cron-pickup concurrency hole in #877)
# AND for same-work re-entry workers (/run-plan, /do; closes the
# cron-reentry concurrency hole in #883).
#
# Why this is shared (not five per-skill scripts): all five workers
# share the same SHAPE — a recurring cron fire that can land while a
# previous run is still mid-flight. They differ only on the skip-key.
# The two queue-pickup workers (#877) re-fire FRESH work (any batch
# matters), so the skip-key is "my session already has an in-flight
# run of this skill." The two same-work workers (#883) re-fire the
# SAME plan/task each time, so the skip-key is "my session already
# has an in-flight run of THIS specific pipeline_id." Both forms
# share the same session-scoping + staleness-escape robustness traps,
# so the helper carries one Python pass parameterised by an optional
# --pipeline-id filter on the `check` subcommand. Without the filter
# (the #877 shape) any same-session sentinel for the skill matches;
# with the filter (the #883 shape) only a sentinel whose pipeline_id
# equals the filter value matches.
#
# Sentinel layout:
#   $MAIN_ROOT/.zskills/inflight/<skill>/<pipeline-id>.json
#   {
#     "skill":       "<skill>",
#     "pipeline_id": "<pipeline-id>",
#     "session_id":  "<session>",      # see resolve_session_id() below
#     "started_at":  "<ISO-8601 UTC>"
#   }
#
# Subcommands:
#   check <skill> [--max-age-seconds N] [--session-id <id>] [--pipeline-id <id>]
#     Returns 0 (in-flight; SKIP) iff a sentinel exists for <skill>
#     whose session_id matches THIS session AND whose started_at age
#     is less than max-age-seconds (default 7200 = 2h). When
#     --pipeline-id is also passed (issue #883), the sentinel's
#     pipeline_id must additionally equal that value — the "same work"
#     skip-key for /run-plan + /do where the cron re-fires the SAME
#     plan/task. Without --pipeline-id (the #877 queue-pickup shape),
#     any same-session sentinel counts.
#     Returns 1 (no in-flight; PROCEED) otherwise. Stale sentinels
#     (older than max-age) are removed in-line and treated as absent
#     (graceful escape from a dead-session sentinel).
#
#   write <skill> --pipeline-id <id> [--session-id <id>]
#     Create the sentinel for this skill+pipeline. Idempotent: if a
#     sentinel for the same pipeline_id already exists it is rewritten
#     (refresh started_at).
#
#   clear <skill> --pipeline-id <id>
#     Remove the sentinel for this skill+pipeline. Idempotent: missing
#     sentinel returns 0. Mismatched pipeline_id sentinels (different
#     run) are left intact.
#
#   list <skill>
#     Pure read. Emits one TSV line per live sentinel:
#       <pipeline_id>\t<session_id>\t<age_seconds>
#
#   resolve-session-id
#     Print the current session_id to stdout (for callers that want to
#     inspect or pass it through).
#
# Session-scoping (the FIRST robustness trap from #877):
#   resolve_session_id() walks $$'s ancestor PID chain until it hits
#   PID 1's first descendant — typically the Claude Code main process
#   for the current REPL session. Combines that PID with /proc/<pid>/
#   stat's start_time field (jiffies-since-boot of process start) to
#   produce a stable identifier that:
#     * is constant across turns of the same Claude Code session,
#     * differs between sessions (different process trees),
#     * survives the bash subshell's own restart between turns.
#   On non-Linux or when /proc is unreadable, falls back to the
#   $MAIN_ROOT/.zskills/session-id file (lazily stamped on first call,
#   refreshed if older than 24h). Callers can always pass an explicit
#   --session-id to override resolution (used by tests).
#
# Staleness escape (the SECOND robustness trap from #877):
#   max-age-seconds defaults to 7200 (2 hours) — a generous bound that
#   exceeds any plausible single sprint/batch/audit. A sentinel older
#   than max-age is treated as orphaned (crashed run) and removed
#   in-line; the caller proceeds. Skipping a redundant pickup at worst
#   delays the queue one interval, so the escape is non-destructive.
#   Override via ZSKILLS_INFLIGHT_MAX_AGE_SECONDS env var or per-call
#   --max-age-seconds flag.
#
# Carve-out: this helper is invoked ONLY at the pickup-path entry of
# each consumer skill, AFTER the subcommand router has decided this
# fire is a real run dispatch. The subcommand carve-out (stop / next /
# sync / add / rank / remove / default / etc. must always proceed) is
# enforced by callers placing the check call AFTER those detections
# but BEFORE the main run-dispatch body.
#
# No jq — Python stdlib json for write/read.

set -u

# ---------------------------------------------------------------------------
# Python interpreter resolution.
# ---------------------------------------------------------------------------
_INFLIGHT_PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
if [ -z "$_INFLIGHT_PYTHON" ]; then
  echo "check-inflight-batch.sh: install Python 3 (or set ZSKILLS_PYTHON)" >&2
  exit 127
fi

# ---------------------------------------------------------------------------
# Defaults.
# ---------------------------------------------------------------------------
_DEFAULT_MAX_AGE="${ZSKILLS_INFLIGHT_MAX_AGE_SECONDS:-7200}"

# ---------------------------------------------------------------------------
# MAIN_ROOT resolution. Same pattern as claim-issue.sh / claim-plan.sh.
# ---------------------------------------------------------------------------
resolve_main_root() {
  local common_dir
  if ! common_dir=$(git rev-parse --git-common-dir 2>/dev/null); then
    echo "check-inflight-batch.sh: cannot resolve MAIN_ROOT (not in a git working tree); cd into a project worktree first" >&2
    return 1
  fi
  if ! MAIN_ROOT=$(cd "$common_dir/.." && pwd); then
    echo "check-inflight-batch.sh: cannot resolve MAIN_ROOT (failed to cd into git common dir parent)" >&2
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Session-id resolution.
#
# Strategy A (Linux /proc): walk $$ up the PPID chain until we land on
# PID 1's first descendant — this is typically the Claude Code main
# process. Combine that PID with /proc/<pid>/stat field 22 (start_time
# in clock ticks since boot) to form a stable identifier. Field 2 of
# /proc/<pid>/stat is the comm in parens, so we use awk's special
# tokenization: skip past `)` then count from there.
#
# Strategy B (fallback): lazily stamp $MAIN_ROOT/.zskills/session-id
# if absent or if older than 24h. Stale-refresh is safe because the
# refresh window is much longer than any plausible cron-pickup cycle.
# ---------------------------------------------------------------------------
_session_id_from_proc() {
  if [ ! -r /proc/$$/stat ]; then
    return 1
  fi
  local pid=$$
  local ppid
  # Walk up; stop when ppid<=1 (we hit init's child).
  while :; do
    if [ ! -r "/proc/$pid/stat" ]; then
      return 1
    fi
    # /proc/<pid>/stat: pid (comm) state ppid ...
    # The comm field can contain spaces and parens; strip from first `(`
    # to last `)` to make the rest unambiguously space-delimited.
    ppid=$(sed -n 's/.*) [A-Z] \([0-9]*\) .*/\1/p' "/proc/$pid/stat" 2>/dev/null)
    if [ -z "$ppid" ] || ! [ "$ppid" -ge 0 ] 2>/dev/null; then
      return 1
    fi
    # Stop when ppid drops to PID 1 (init) or 0 (container/kernel root)
    # — the current `pid` is the highest stable non-init ancestor.
    if [ "$ppid" -le 1 ]; then
      break
    fi
    pid=$ppid
  done
  # pid now == the first descendant of PID 1. Get its start_time
  # (/proc/<pid>/stat field 22, counted AFTER the comm-paren strip).
  local rest start_time
  rest=$(sed -n 's/.*) [A-Z] //p' "/proc/$pid/stat" 2>/dev/null)
  if [ -z "$rest" ]; then
    return 1
  fi
  # Field 22 of original = position (22 - 3) = 19 after the strip
  # (we removed pid, (comm), state — 3 fields; ppid is now field 1
  # of `rest`, so start_time is field 19 of `rest`).
  start_time=$(printf '%s\n' "$rest" | awk '{print $19}')
  if [ -z "$start_time" ] || ! [ "$start_time" -ge 0 ] 2>/dev/null; then
    return 1
  fi
  printf 'pid-%s.%s' "$pid" "$start_time"
  return 0
}

_session_id_from_file() {
  local main_root="$1"
  local session_file="${main_root}/.zskills/session-id"
  local now age limit=86400  # 24h
  now=$(date -u +%s)
  if [ -f "$session_file" ]; then
    local mtime
    mtime=$(stat -c %Y "$session_file" 2>/dev/null || stat -f %m "$session_file" 2>/dev/null || echo 0)
    age=$(( now - mtime ))
    if [ "$age" -lt "$limit" ]; then
      cat "$session_file"
      return 0
    fi
  fi
  # Stamp a fresh session-id.
  mkdir -p "$(dirname "$session_file")"
  local new_id
  new_id="file-$(date -u +%Y%m%d%H%M%S)-$$"
  printf '%s' "$new_id" > "$session_file"
  printf '%s' "$new_id"
  return 0
}

resolve_session_id() {
  local sid
  if sid=$(_session_id_from_proc); then
    printf '%s' "$sid"
    return 0
  fi
  if [ -z "${MAIN_ROOT:-}" ]; then
    resolve_main_root || return 1
  fi
  _session_id_from_file "$MAIN_ROOT"
}

# ---------------------------------------------------------------------------
# Validate skill name — must be a simple slug (a-z0-9- only). Prevents
# path-traversal via crafted skill arg.
# ---------------------------------------------------------------------------
_validate_skill() {
  local s="${1:-}"
  if [ -z "$s" ]; then
    echo "check-inflight-batch.sh: skill name required" >&2
    return 1
  fi
  case "$s" in
    ''|*[!a-z0-9-]*)
      echo "check-inflight-batch.sh: invalid skill name '$s' (must match [a-z0-9-]+)" >&2
      return 1
      ;;
  esac
  return 0
}

_validate_pipeline_id() {
  local p="${1:-}"
  if [ -z "$p" ]; then
    echo "check-inflight-batch.sh: --pipeline-id required" >&2
    return 1
  fi
  # Re-sanitize defensively — pipeline_ids are already sanitized by
  # callers via sanitize-pipeline-id.sh, but accept the same shape here.
  case "$p" in
    ''|*[!a-zA-Z0-9._-]*)
      echo "check-inflight-batch.sh: invalid pipeline-id '$p' (must match [a-zA-Z0-9._-]+)" >&2
      return 1
      ;;
  esac
  return 0
}

# ---------------------------------------------------------------------------
# check <skill> [--max-age-seconds N] [--session-id <id>] [--pipeline-id <id>]
#
# Exit 0  — in-flight, SKIP (caller should exit 0 cleanly).
# Exit 1  — no in-flight sentinel for this session, PROCEED.
# Exit 2  — usage error.
#
# `--pipeline-id` (issue #883): when present, only a sentinel whose
# pipeline_id matches THIS value counts as in-flight. This is the
# "same-work" skip-key used by /run-plan and /do, where the cron re-fires
# the SAME plan/task and must skip iff that specific plan/task is mid-
# flight. Two concurrent /run-plan invocations for DIFFERENT plans each
# write sentinels under inflight/run-plan/; without the pipeline-id
# filter the per-skill check would over-match. When `--pipeline-id` is
# absent, behavior is unchanged from #877: any same-session sentinel
# under the skill dir counts as in-flight (the queue-pickup skip-key).
# ---------------------------------------------------------------------------
cmd_check() {
  local skill="" max_age="$_DEFAULT_MAX_AGE" explicit_sid="" filter_pid=""
  if [ "$#" -lt 1 ]; then
    echo "Usage: check-inflight-batch.sh check <skill> [--max-age-seconds N] [--session-id <id>] [--pipeline-id <id>]" >&2
    return 2
  fi
  skill="$1"; shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --max-age-seconds) max_age="${2:-}"; shift 2 ;;
      --session-id)      explicit_sid="${2:-}"; shift 2 ;;
      --pipeline-id)     filter_pid="${2:-}"; shift 2 ;;
      *) echo "check-inflight-batch.sh check: unknown arg '$1'" >&2; return 2 ;;
    esac
  done
  _validate_skill "$skill" || return 2
  case "$max_age" in
    ''|*[!0-9]*) echo "check-inflight-batch.sh check: --max-age-seconds must be non-negative integer" >&2; return 2 ;;
  esac
  if [ -n "$filter_pid" ]; then
    _validate_pipeline_id "$filter_pid" || return 2
  fi
  resolve_main_root || return 2

  local sid
  if [ -n "$explicit_sid" ]; then
    sid="$explicit_sid"
  else
    sid=$(resolve_session_id) || { echo "check-inflight-batch.sh: cannot resolve session-id" >&2; return 2; }
  fi

  local skill_dir="${MAIN_ROOT}/.zskills/inflight/${skill}"
  if [ ! -d "$skill_dir" ]; then
    return 1  # proceed — no sentinels at all for this skill
  fi

  # Python pass: find any sentinel matching session_id AND not stale.
  # Stale sentinels (age > max_age) are removed inline. When filter_pid
  # is non-empty (issue #883), additionally require the sentinel's
  # pipeline_id to equal filter_pid — this is the "same work in flight"
  # skip-key used by /run-plan and /do. When filter_pid is empty, any
  # same-session sentinel counts (the #877 queue-pickup skip-key).
  local result
  result=$("$_INFLIGHT_PYTHON" - "$skill_dir" "$sid" "$max_age" "$filter_pid" <<'PY'
import json, os, sys, time, datetime
skill_dir, want_sid, max_age, want_pid = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
now = datetime.datetime.now(datetime.timezone.utc)
match = None
try:
    entries = os.listdir(skill_dir)
except OSError:
    print("none")
    sys.exit(0)
for name in entries:
    if not name.endswith(".json"):
        continue
    path = os.path.join(skill_dir, name)
    if not os.path.isfile(path):
        continue
    try:
        with open(path) as fh:
            body = json.load(fh)
    except Exception:
        # Malformed sentinel — treat as orphan, remove.
        try:
            os.unlink(path)
        except OSError:
            pass
        continue
    started_at = body.get("started_at", "")
    age = None
    if started_at:
        try:
            t = datetime.datetime.fromisoformat(started_at)
            if t.tzinfo is None:
                t = t.replace(tzinfo=datetime.timezone.utc)
            age = (now - t).total_seconds()
        except Exception:
            age = None
    if age is None or age > max_age:
        # Stale or unparseable timestamp — orphan; remove and continue.
        try:
            os.unlink(path)
        except OSError:
            pass
        continue
    # Fresh sentinel. Check session-id.
    if body.get("session_id", "") != want_sid:
        continue
    # Optional per-work-identity filter (issue #883).
    if want_pid and body.get("pipeline_id", "") != want_pid:
        continue
    match = (body.get("pipeline_id", "?"), int(age))
    break
if match is None:
    print("none")
else:
    print(f"match\t{match[0]}\t{match[1]}")
PY
)
  case "$result" in
    match*)
      # Emit a short diagnostic so the caller's "skipping redundant
      # cron pickup" message has the matching pipeline_id available.
      local pipeline_id age
      pipeline_id=$(printf '%s' "$result" | awk -F'\t' '{print $2}')
      age=$(printf '%s' "$result" | awk -F'\t' '{print $3}')
      printf 'in-flight\t%s\t%s\n' "$pipeline_id" "$age"
      return 0
      ;;
    none|*)
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# write <skill> --pipeline-id <id> [--session-id <id>]
# ---------------------------------------------------------------------------
cmd_write() {
  local skill="" pipeline_id="" explicit_sid=""
  if [ "$#" -lt 1 ]; then
    echo "Usage: check-inflight-batch.sh write <skill> --pipeline-id <id> [--session-id <id>]" >&2
    return 2
  fi
  skill="$1"; shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --pipeline-id) pipeline_id="${2:-}"; shift 2 ;;
      --session-id)  explicit_sid="${2:-}"; shift 2 ;;
      *) echo "check-inflight-batch.sh write: unknown arg '$1'" >&2; return 2 ;;
    esac
  done
  _validate_skill "$skill" || return 2
  _validate_pipeline_id "$pipeline_id" || return 2
  resolve_main_root || return 2

  local sid
  if [ -n "$explicit_sid" ]; then
    sid="$explicit_sid"
  else
    sid=$(resolve_session_id) || { echo "check-inflight-batch.sh: cannot resolve session-id" >&2; return 2; }
  fi

  local skill_dir="${MAIN_ROOT}/.zskills/inflight/${skill}"
  local sentinel="${skill_dir}/${pipeline_id}.json"
  local sentinel_tmp="${sentinel}.tmp"

  if ! mkdir -p "$skill_dir"; then
    echo "check-inflight-batch.sh write: failed to create $skill_dir" >&2
    return 11
  fi

  if ! "$_INFLIGHT_PYTHON" - "$sentinel_tmp" "$sentinel" "$skill" "$pipeline_id" "$sid" <<'PY'
import json, os, sys, datetime
tmp, final, skill, pipeline_id, sid = sys.argv[1:6]
body = {
    "schema_version": 1,
    "skill":          skill,
    "pipeline_id":    pipeline_id,
    "session_id":     sid,
    "started_at":     datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
}
with open(tmp, "w") as f:
    json.dump(body, f, sort_keys=True)
    f.write("\n")
os.replace(tmp, final)
PY
  then
    rm -f "$sentinel_tmp"
    echo "check-inflight-batch.sh write: atomic write failed for $sentinel" >&2
    return 11
  fi

  return 0
}

# ---------------------------------------------------------------------------
# clear <skill> --pipeline-id <id>
# ---------------------------------------------------------------------------
cmd_clear() {
  local skill="" pipeline_id=""
  if [ "$#" -lt 1 ]; then
    echo "Usage: check-inflight-batch.sh clear <skill> --pipeline-id <id>" >&2
    return 2
  fi
  skill="$1"; shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --pipeline-id) pipeline_id="${2:-}"; shift 2 ;;
      *) echo "check-inflight-batch.sh clear: unknown arg '$1'" >&2; return 2 ;;
    esac
  done
  _validate_skill "$skill" || return 2
  _validate_pipeline_id "$pipeline_id" || return 2
  resolve_main_root || return 2

  local sentinel="${MAIN_ROOT}/.zskills/inflight/${skill}/${pipeline_id}.json"
  rm -f "$sentinel"
  rm -f "${sentinel}.tmp"

  # rmdir the parent if empty (best-effort cleanup; harmless if non-empty).
  rmdir "${MAIN_ROOT}/.zskills/inflight/${skill}" 2>/dev/null || true
  rmdir "${MAIN_ROOT}/.zskills/inflight" 2>/dev/null || true
  return 0
}

# ---------------------------------------------------------------------------
# list <skill>
# ---------------------------------------------------------------------------
cmd_list() {
  local skill="${1:-}"
  _validate_skill "$skill" || return 2
  resolve_main_root || return 2

  local skill_dir="${MAIN_ROOT}/.zskills/inflight/${skill}"
  [ -d "$skill_dir" ] || return 0

  "$_INFLIGHT_PYTHON" - "$skill_dir" <<'PY'
import json, os, sys, datetime
skill_dir = sys.argv[1]
now = datetime.datetime.now(datetime.timezone.utc)
try:
    entries = sorted(os.listdir(skill_dir))
except OSError:
    sys.exit(0)
for name in entries:
    if not name.endswith(".json"):
        continue
    path = os.path.join(skill_dir, name)
    try:
        with open(path) as fh:
            body = json.load(fh)
    except Exception:
        continue
    started_at = body.get("started_at", "")
    age = "?"
    if started_at:
        try:
            t = datetime.datetime.fromisoformat(started_at)
            if t.tzinfo is None:
                t = t.replace(tzinfo=datetime.timezone.utc)
            age = str(int((now - t).total_seconds()))
        except Exception:
            pass
    print(f"{body.get('pipeline_id','?')}\t{body.get('session_id','?')}\t{age}")
PY
  return 0
}

# ---------------------------------------------------------------------------
# resolve-session-id  (debug aid)
# ---------------------------------------------------------------------------
cmd_resolve_session_id() {
  resolve_main_root || return 2
  local sid
  sid=$(resolve_session_id) || return 2
  printf '%s\n' "$sid"
  return 0
}

# ---------------------------------------------------------------------------
# Dispatch.
# ---------------------------------------------------------------------------
main() {
  local sub="${1:-}"
  if [ -z "$sub" ]; then
    echo "Usage: check-inflight-batch.sh {check|write|clear|list|resolve-session-id} [args...]" >&2
    return 2
  fi
  shift
  case "$sub" in
    check)              cmd_check "$@" ;;
    write)              cmd_write "$@" ;;
    clear)              cmd_clear "$@" ;;
    list)               cmd_list "$@" ;;
    resolve-session-id) cmd_resolve_session_id "$@" ;;
    *)
      echo "check-inflight-batch.sh: unknown subcommand '$sub'" >&2
      echo "Usage: check-inflight-batch.sh {check|write|clear|list|resolve-session-id} [args...]" >&2
      return 2
      ;;
  esac
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  main "$@"
  exit $?
fi
