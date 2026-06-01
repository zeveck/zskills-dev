#!/bin/bash
# defer-backoff-decide.sh — Pure decision rule for /run-plan Step 0 Case 3's
# adaptive cron-backoff state machine (issue #110) plus its sentinel-recovery
# prelude (#110 WI 1.2; A1 fix).
#
# Purpose: /run-plan Step 0 Case 3 ("Next-target phase already In Progress")
# carries a numbered prose recipe over Cron* tools. The bug-prone part is the
# DECISION — given the per-phase defer counter, the current cron cadence, the
# CronList match count, the CronCreate-verify outcome, the case (3 vs 4), and
# whether a recovery sentinel is present, decide WHICH actions to take. That
# decision is arithmetic + branching with no I/O and no Cron* calls, so it is
# fully testable in isolation. This script owns ONLY the decision; the Cron*
# orchestration (CronList / CronDelete / CronCreate, the sentinel writes, the
# counter file writes, the sleeps, the user-visible WARN message) STAYS in
# SKILL.md prose, which interprets the directives emitted here.
#
# This is behaviour-preserving: the emitted directive set for every input is
# identical to the rule previously inlined in SKILL.md prose (and previously
# re-implemented inline by tests/test-runplan-defer-backoff.sh, which now
# sources this script instead of duplicating the logic).
#
# Directive vocabulary (stdout, one directive per line) — the SKILL.md prose
# maps each to its Cron* / filesystem action:
#   PRELUDE_RECOVERY_ATTEMPTED            sentinel-recovery prelude ran
#   PRELUDE_RECOVERY_OK                   prelude resolved → rm sentinel
#   PRELUDE_RECOVERY_FAILED              prelude could not recreate cron → hold sentinel
#   WARN <reason ...>                     emit a stdout WARN (non-fatal)
#   DELETE_ALL_MATCHING_CRONS             CronList + CronDelete every matching id
#   REPLACE_CRON <cadence>                CronCreate ONE cron at <cadence>
#   DELETE_COUNTER                        rm in-progress-defers.* + cron-recovery-needed.*
#   SLEEP_BETWEEN_RETRIES                 sleep 2 between CronCreate retry attempts (N1)
#   WRITE_RECOVERY_MARKER <phase>         write cron-recovery-needed.<phase> sentinel (N2)
#   EMIT_USER_WARN <reason>               surface a user-visible WARN in the turn message (N2)
#   WRITE_COUNTER <n>                     write n to in-progress-defers.<phase>
#   PROCEED <message-mode>                advance; message-mode ∈
#                                         {defer-message-printed, defer-message-silent}
#
# Usage:
#   bash defer-backoff-decide.sh \
#     --counter <C> \
#     --cadence <R> \
#     --cronlist-match <N> \
#     --create-result <ok|missing|missing-after-3-retries> \
#     --case <3|4> \
#     --recovery-marker <yes|no> \
#     [--phase <P>]
#
# Defaults mirror a cold-start Case 3 fire: counter 0, cadence */1, one match,
# create ok, case 3, no recovery marker, phase 3.
#
# Exit 0 always on a well-formed invocation (the decision itself never fails;
# downstream prose handles the action outcomes). Exit 2 on a usage error.

set -u

COUNTER=0
CADENCE='*/1'
CRONLIST_MATCH=1
CREATE_RESULT=ok
CASE=3
RECOVERY_MARKER=no
PHASE=3

while [ "$#" -gt 0 ]; do
  case "$1" in
    --counter)         COUNTER="${2:-}";         shift 2 ;;
    --cadence)         CADENCE="${2:-}";         shift 2 ;;
    --cronlist-match)  CRONLIST_MATCH="${2:-}";  shift 2 ;;
    --create-result)   CREATE_RESULT="${2:-}";   shift 2 ;;
    --case)            CASE="${2:-}";            shift 2 ;;
    --recovery-marker) RECOVERY_MARKER="${2:-}"; shift 2 ;;
    --phase)           PHASE="${2:-}";           shift 2 ;;
    -h|--help)
      sed -n '/^# Usage/,/^# Exit 0/p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      echo "defer-backoff-decide: unknown arg '$1'" >&2
      exit 2
      ;;
  esac
done

# ---- Sentinel-recovery prelude (#110 WI 1.2; A1 fix) -------------------
if [ "$RECOVERY_MARKER" = "yes" ]; then
  echo "PRELUDE_RECOVERY_ATTEMPTED"
  if [ "${CRONLIST_MATCH:-0}" -ge 1 ]; then
    # Cron exists — cadence-sanity check (A1). Sane set: */1, */10, */30, */60.
    case "$CADENCE" in
      '*/1'|'*/10'|'*/30'|'*/60')
        echo "PRELUDE_RECOVERY_OK"
        ;;
      *)
        # Bad cadence: force-delete, recreate at */1, hold counter.
        echo "WARN cron-recovery-bad-cadence $CADENCE"
        echo "DELETE_ALL_MATCHING_CRONS"
        echo "REPLACE_CRON */1"
        echo "PRELUDE_RECOVERY_OK"
        exit 0
        ;;
    esac
  else
    # No cron; prelude attempts CronCreate at */1.
    if [ "$CREATE_RESULT" = "ok" ]; then
      echo "REPLACE_CRON */1"
      echo "PRELUDE_RECOVERY_OK"
    else
      echo "PRELUDE_RECOVERY_FAILED"
    fi
  fi
fi

# ---- Case 4: new-phase entry (rm per-phase counters + sentinel) --------
if [ "${CASE:-3}" = "4" ]; then
  echo "DELETE_COUNTER"
  exit 0
fi

# ---- Case 3: adaptive backoff decision rule ----------------------------
# Step 1: counter C → NEXT = C+1.
C="${COUNTER:-0}"
NEXT=$((C + 1))

# Step 2: read R via CronList. No match → WARN + hold counter + exit.
if [ "${CRONLIST_MATCH:-1}" -eq 0 ]; then
  echo "WARN no-cron-match"
  exit 0
fi
R="$CADENCE"

# Step 3: compute target cadence T from NEXT.
if   [ "$NEXT" -lt 10 ]; then T='*/1'
elif [ "$NEXT" -le 15 ]; then T='*/10'
elif [ "$NEXT" -le 25 ]; then T='*/30'
else                          T='*/60'
fi

# Step 4: if T != R, replace cron (delete-all + create + verify w/ 3
# retries, sleep 2 between attempts — N1).
if [ "$T" != "$R" ]; then
  echo "DELETE_ALL_MATCHING_CRONS"
  case "$CREATE_RESULT" in
    ok)
      echo "REPLACE_CRON $T"
      ;;
    missing)
      echo "SLEEP_BETWEEN_RETRIES"
      echo "WARN cron-replace-failed (1 retry, will continue)"
      echo "REPLACE_CRON $T"
      ;;
    missing-after-3-retries)
      # High-severity race: hold counter, sentinel + user WARN (N2).
      echo "SLEEP_BETWEEN_RETRIES"
      echo "WARN cron-replace-failed (3 retries exhausted)"
      echo "WRITE_RECOVERY_MARKER $PHASE"
      echo "EMIT_USER_WARN cron-stalled"
      exit 0
      ;;
  esac
fi
# Step 5: T == R → no cron action.

# Step 6: advance counter; defer message only at boundary fires.
echo "WRITE_COUNTER $NEXT"
case "$NEXT" in
  1|10|16|26) echo "PROCEED defer-message-printed" ;;
  *)          echo "PROCEED defer-message-silent" ;;
esac
exit 0
