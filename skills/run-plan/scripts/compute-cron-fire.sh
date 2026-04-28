#!/bin/bash
# Compute a one-shot cron expression that fires N minutes from now.
# Used by /run-plan (Phase 5c chunked finish-auto, verify-pending retry,
# re-entry), and anywhere else the zskills tooling schedules a
# cron-fired follow-up turn.
#
# Usage:
#   bash $(basename "$0") [--offset N] [--allow-marks]
# Env:
#   FAKE_NOW_EPOCH=<seconds>  — override "now" for tests (otherwise system time)
# Output (stdout, one line):
#   <min> <hour> <day> <month> *
#
# Exits:
#   0 success
#   2 usage error
#
# Flags:
#   --offset N       Minutes from now (default: 5). Must be >= 1.
#   --allow-marks    Disable :00/:30 avoidance (default: avoidance ON).
#
# Why +5 default (not +1): one-shot crons pin day-of-month AND month.
# If scheduler jitter (sub-minute clock drift, TZ conversion, tick skew)
# makes the fire window appear "already passed" at evaluation time, the
# next matching slot becomes day-of-month+month NEXT YEAR — the cron sits
# in CronList forever but never fires this session. 1 minute is
# borderline; 5 minutes is comfortable slack.
#
# Why :00/:30 avoidance: API busy marks — many schedulers see disproportionate
# load at :00 and :30 within each hour. Bumping by 1 minute avoids the
# worst of it with a negligible delay cost.
#
# Why this is a script (not inlined bash): the day/month/year rollover
# math is easy to get wrong. Previous inline versions in /run-plan handled
# minute and hour rollover but NOT day/month/year — at 23:58, the computed
# cron pinned to "03 00 19 04 *" which is earlier-today, and cron would
# fire ~365 days later. Using `date -d "+N minutes"` here delegates all
# rollover handling to the date library, which gets it right.

set -e

OFFSET=5
AVOID_MARKS=1

while [ "$#" -gt 0 ]; do
  case "$1" in
    --offset)
      shift
      OFFSET="${1:-}"
      if ! [[ "$OFFSET" =~ ^[0-9]+$ ]] || [ "$OFFSET" -lt 1 ]; then
        echo "compute-cron-fire: --offset requires a positive integer, got '${OFFSET}'" >&2
        exit 2
      fi
      shift
      ;;
    --allow-marks)
      AVOID_MARKS=0
      shift
      ;;
    -h|--help)
      sed -n '/^# Usage/,/^# Why this is/p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      echo "compute-cron-fire: unknown arg '$1'" >&2
      exit 2
      ;;
  esac
done

# Compute baseline "now" (as epoch seconds). Allow tests to pin the
# clock via FAKE_NOW_EPOCH so behavior at e.g. 23:58 / Dec 31 is
# reproducible.
if [ -n "${FAKE_NOW_EPOCH:-}" ]; then
  if ! [[ "$FAKE_NOW_EPOCH" =~ ^[0-9]+$ ]]; then
    echo "compute-cron-fire: FAKE_NOW_EPOCH must be an integer epoch-seconds, got '${FAKE_NOW_EPOCH}'" >&2
    exit 2
  fi
  NOW_EPOCH="$FAKE_NOW_EPOCH"
else
  NOW_EPOCH=$(date +%s)
fi

# Target epoch = now + OFFSET minutes.
TARGET_EPOCH=$(( NOW_EPOCH + OFFSET * 60 ))
TARGET=$(date -d "@$TARGET_EPOCH" +"%M %H %d %m")
read -r MIN HOUR DAY MONTH <<<"$TARGET"

# :00/:30 avoidance — if enabled and we landed on one of those, bump +1
# minute. The bump may cascade into hour/day/month/year rollover; re-
# compute via epoch arithmetic so rollover stays correct.
if [ "$AVOID_MARKS" = "1" ] && { [ "$MIN" = "00" ] || [ "$MIN" = "30" ]; }; then
  TARGET_EPOCH=$(( TARGET_EPOCH + 60 ))
  TARGET=$(date -d "@$TARGET_EPOCH" +"%M %H %d %m")
  read -r MIN HOUR DAY MONTH <<<"$TARGET"
fi

# Strip leading zeros that cron tolerates but some downstream tools
# prefer without (e.g. "03" vs "3"). Cron accepts both; we emit with
# leading zeros to match the existing inline output format.
echo "$MIN $HOUR $DAY $MONTH *"
