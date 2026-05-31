#!/bin/bash
# check-inflight-batch.sh — session-scoped in-flight run detector for the
# cron-overlap guard (issue #877 queue-pickup; sibling #883 same-work
# re-entry).
#
# Answers one question: "does THIS session already have a fresh,
# un-finalized run sentinel matching the given skill (and optionally a
# work-id)?" Used by the recurring queue-worker skills (/fix-issues,
# /work-on-plans, /qe-audit — #877) and, with --work-id, by the same-work
# re-entry skills (/run-plan, /do — #883) to skip a redundant cron
# pickup-fire that lands mid-run.
#
# WHY this is needed: a recurring `every`-cron fires as a `Run /<skill> …`
# turn into the SAME active session as the run that is still executing —
# CronCreate idle is turn-level (between token generation), NOT task-level,
# so it cannot see "mid-batch." A long sprint/batch/audit spans many turns
# over wall-clock that can exceed the fire interval, so the next fire lands
# in a turn-gap while the prior run is still going. The in-flight run's
# sentinel and the new fire therefore share CLAUDE_CODE_SESSION_ID. We gate
# ONLY same-session sentinels — a parallel pipeline in a DIFFERENT session
# has a different id and is NEVER blocked. That single rule delivers both
# robustness traps the design requires: it preserves legitimate parallel
# pipelines AND it cannot deadlock a dead session (a dead session's cron is
# also dead, so nothing fires to be blocked).
#
# Guard sentinels are uniform `key: value` files written by each worker at
# run entry, e.g. under
#   .zskills/tracking/<pipeline>/pipeline.<skill>.<runid>
# carrying at least:
#     skill:     <skill>
#     session:   <CLAUDE_CODE_SESSION_ID captured at write time>
#     workId:    <work id, e.g. plan/task slug>   (optional; #883 key)
#     startedAt: <ISO-8601 or epoch seconds>
#
# Usage:
#   check-inflight-batch.sh --glob '<glob>' --session '<id>' \
#       [--work-id '<id>'] [--max-age-seconds N] [--root <dir>]
#
#   --glob    (required) shell glob of sentinel files, relative to --root.
#                        e.g. '.zskills/tracking/*/pipeline.fix-issues.*'
#   --session (required) caller's CLAUDE_CODE_SESSION_ID. Empty → proceed
#                        (cannot prove ownership; fail-open).
#   --work-id (optional) when set, additionally require the sentinel's
#                        `workId:` to equal this (the #883 same-work key).
#                        When unset, ANY same-session sentinel matches (the
#                        #877 queue-pickup key).
#   --max-age-seconds    staleness bound (default 21600 = 6h). A MY-SESSION
#                        sentinel older than this is treated as a crashed
#                        run: removed (single-file `rm -f`) and ignored, so
#                        a partial-failure that skipped its own cleanup
#                        never deadlocks the cron. Generous by design — a
#                        legitimately-long run must not be declared stale.
#   --root    (optional) repo root holding .zskills/ (default: git
#                        common-dir parent, else $PWD).
#
# Exit status — THE CALLER CONTRACT:
#   0  IN-FLIGHT — a fresh same-session (+ optional work-id) sentinel
#      exists. stdout is its run-id (the sentinel basename). The caller
#      SHOULD print its skip message and `exit 0` (skip the redundant
#      pickup; the in-flight run finishes on its own turns; the next fire
#      picks up fresh).
#   1  PROCEED  — no matching fresh sentinel, OR any error / ambiguity /
#      empty session. FAIL-OPEN: every failure path returns 1 so the worst
#      case is one redundant run, NEVER a deadlock or a disrupted parallel
#      pipeline. (Skipping a redundant pickup at worst delays the queue one
#      interval; falsely gating a run could silently stop all work — so the
#      safe direction is to proceed.)
#
# Caller idiom (note: exit 0 = in-flight ⇒ the `then` branch skips):
#   SID="${CLAUDE_CODE_SESSION_ID:-}"
#   if RUN_ID=$(bash "$HELPER" --glob '.zskills/tracking/*/pipeline.fix-issues.*' \
#                --session "$SID" --root "$MAIN_ROOT"); then
#     echo "fix-issues run $RUN_ID in flight; skipping redundant cron pickup" >&2
#     exit 0
#   fi
#   # ... proceed with the run ...

set -u

PROCEED=1     # exit code: caller proceeds
INFLIGHT=0    # exit code: caller skips

GLOB=""
SESSION=""
WORK_ID=""
MAX_AGE=21600
ROOT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --glob)            GLOB="${2:-}"; shift 2 ;;
    --session)         SESSION="${2:-}"; shift 2 ;;
    --work-id)         WORK_ID="${2:-}"; shift 2 ;;
    --max-age-seconds) MAX_AGE="${2:-}"; shift 2 ;;
    --root)            ROOT="${2:-}"; shift 2 ;;
    *) echo "check-inflight-batch: unknown arg '$1' — proceeding (fail-open)" >&2; exit "$PROCEED" ;;
  esac
done

# Missing --glob is a wiring bug; fail-open anyway so a mis-wired call site
# never deadlocks a worker.
[ -n "$GLOB" ] || { echo "check-inflight-batch: missing --glob — proceeding (fail-open)" >&2; exit "$PROCEED"; }
# Empty session: cannot session-scope. Proceed (no guard) rather than risk
# gating a parallel pipeline or deadlocking on an unknowable owner.
[ -n "$SESSION" ] || { echo "check-inflight-batch: empty --session (CLAUDE_CODE_SESSION_ID unset?) — proceeding (fail-open)" >&2; exit "$PROCEED"; }
# max-age must be a positive integer; otherwise fall back to the default.
case "$MAX_AGE" in ''|*[!0-9]*) MAX_AGE=21600 ;; esac

# Resolve root (repo dir holding .zskills/).
if [ -z "$ROOT" ]; then
  if ROOT=$(git rev-parse --git-common-dir 2>/dev/null); then
    ROOT=$(cd "$ROOT/.." 2>/dev/null && pwd) || ROOT="$PWD"
  else
    ROOT="$PWD"
  fi
fi

NOW=$(date +%s 2>/dev/null) || exit "$PROCEED"

# Read a `key: value` field from a sentinel file; echo the trimmed value.
_field() {
  # $1 = file, $2 = key
  local line
  line=$(grep -m1 -E "^$2:[[:space:]]*" "$1" 2>/dev/null) || return 1
  printf '%s' "${line#*:}" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

# Iterate matched sentinels. nullglob so a no-match glob yields no
# iterations; the `[ -f ]` guard covers the no-nullglob fallback too.
shopt -s nullglob 2>/dev/null || true
for f in $ROOT/$GLOB; do
  [ -f "$f" ] || continue

  # Session scope: only THIS session's sentinels are candidates. A
  # different session's sentinel (parallel pipeline) is never gated.
  s=$(_field "$f" session) || continue
  [ "$s" = "$SESSION" ] || continue

  # Staleness escape: a crashed/partial run leaves an un-finalized
  # sentinel. Age it via startedAt (epoch or ISO-8601). Unparseable →
  # treat as fresh (conservative: never delete what we cannot age — a
  # spurious skip is cheaper than deleting a live run's sentinel).
  started=$(_field "$f" startedAt) || started=""
  age=""
  if [ -n "$started" ]; then
    if [[ "$started" =~ ^[0-9]+$ ]]; then
      age=$(( NOW - started ))
    else
      st=$(date -d "$started" +%s 2>/dev/null) && age=$(( NOW - st )) || age=""
    fi
  fi
  if [ -n "$age" ] && [ "$age" -gt "$MAX_AGE" ]; then
    # Stale MY-SESSION sentinel → crashed run. Remove this one file and
    # ignore it (proceed past it). Narrow blast radius: only this matched
    # file, only my own session — a live OTHER session's sentinel is never
    # touched.
    rm -f "$f"
    continue
  fi

  # Work-id scope (#883 same-work re-entry): when requested, additionally
  # require the sentinel's workId to match.
  if [ -n "$WORK_ID" ]; then
    w=$(_field "$f" workId) || w=""
    [ "$w" = "$WORK_ID" ] || continue
  fi

  # Match: a fresh, same-session (+ optional work-id) sentinel. IN-FLIGHT.
  printf '%s\n' "$(basename "$f")"
  exit "$INFLIGHT"
done

exit "$PROCEED"
