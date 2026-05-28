#!/usr/bin/env bash
# zskills-hook-version: 2026.05.0
# block-bad-cron.sh — PreToolUse hook for the CronCreate tool.
#
# Closes a class of "the cron never fired" bugs caused by structurally-wrong
# cron expressions on the CronCreate tool. The recurring trap, observed on
# 2026-05-19: an orchestrator typed `3 16 19 5 *` for CronCreate thinking
# 4:03 PM ET. Container TZ is UTC, so the scheduler read it as 16:03 UTC =
# 12:03 PM EDT — already past at scheduling. With no year field, the next
# match is May 19 *2027*. One-shot crons whose match is far in the future
# never fire within a single Claude Code session lifetime.
#
# Reject rules (deny with explanatory STOP message):
#   - recurring=false AND no match in next 8 days  → today's past-time bug
#   - recurring=false AND next-fire > 7 days from now → session-lifetime
#   - delta < 0                                    → defensive past-time
#
# Allow with stderr WARN:
#   - Cron expression fails to parse — let scheduler surface its own error.
#
# Allow (no warn):
#   - recurring=true regardless (legitimate edge cases like Feb-31 exist).
#   - Anything that passes the reject rules.
#
# Tool-name gate: filter early on `tool_name=CronCreate`. Anything else
# exits 0. Pattern follows hooks/inject-bash-timeout.sh's `tool_name`
# pre-filter (idiom: cheap startup cost on every Bash/PreToolUse call).
#
# TZ resolution ladder (display-TZ used in deny messages — container TZ is
# always reported separately):
#   1. top-level "timezone" field in .claude/zskills-config.json
#   2. $TIMEZONE env var
#   3. $TZ env var
#   4. /etc/timezone
#   5. UTC
# NO hardcoded "America/New_York" anywhere — the deny-list scan in
# tests/test-skill-conformance.sh enforces this.
#
# ── Session-reload caveat (#460) ───────────────────────────────────
# .claude/settings.json is loaded ONCE at session start. The in-memory
# hook table is fixed at session-init time; mid-session edits to
# settings.json — including newly landing this hook in a PR — are NOT
# re-read by the running session. Consequence: the session whose
# lifetime predates the merge that adds this hook will keep accepting
# bad crons silently, even though the registration is correctly on
# disk. Past failure: PR #456 landed at 06:18 UTC 2026-05-20; the
# orchestrator session running since before then made a bad CronCreate
# call at 07:16 UTC and the hook did not fire. Issue #460 author
# confirmed via post-restart live-fire that the hook DOES fire on
# built-in CronCreate calls once the session sees the registration.
# Verification path after landing this hook (or after editing it): run
# `/clear` (or restart Claude Code) and re-test with an intentionally
# bad cron, e.g., a one-shot whose next fire is more than 7 days out.
# The deny envelope's STOP message confirms the hook is wired.

# D16(a) plugin-lane conditional-skip shim. No-op on the /update-zskills
# lane (CLAUDE_PLUGIN_ROOT unset → guard below skips the source). On the
# plugin lane it defers to a settings.json-registered copy of this hook to
# prevent double-fire when both install lanes are active. Must be the first
# executable line; the shim controls its own exit/return.
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_lib/plugin-hook-skip-if-mirrored.sh" ] && source "${CLAUDE_PLUGIN_ROOT}/hooks/_lib/plugin-hook-skip-if-mirrored.sh"

set -u

INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

# ── Tool-name gate ─────────────────────────────────────────────────
# Exit 0 for anything except CronCreate. Cheapest possible filter so
# the hook adds near-zero cost to other PreToolUse paths.
if [[ "$INPUT" != *'"tool_name":"CronCreate"'* ]] && [[ "$INPUT" != *'"tool_name": "CronCreate"'* ]]; then
  exit 0
fi

# ── Resolve Python interpreter ─────────────────────────────────────
# Same precedence as hooks/inject-bash-timeout.sh.
PYTHON=${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}
[ -n "$PYTHON" ] || { echo "ERROR: install Python 3 (or set ZSKILLS_PYTHON)" >&2; exit 1; }

# ── Extract tool_input fields via bash regex ───────────────────────
# tool_input.cron — 5-field cron expression
CRON_EXPR=""
if [[ "$INPUT" =~ \"cron\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
  CRON_EXPR="${BASH_REMATCH[1]}"
fi

# If no cron in the envelope, allow (scheduler will reject; not our job).
if [ -z "$CRON_EXPR" ]; then
  exit 0
fi

# tool_input.recurring — bool, default true
RECURRING="true"
if [[ "$INPUT" =~ \"recurring\"[[:space:]]*:[[:space:]]*(true|false) ]]; then
  RECURRING="${BASH_REMATCH[1]}"
fi

# ── Resolve display TZ ─────────────────────────────────────────────
REPO_ROOT="${CLAUDE_PROJECT_DIR:-${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}"
CONFIG_FILE="$REPO_ROOT/.claude/zskills-config.json"

DISPLAY_TZ=""
if [ -f "$CONFIG_FILE" ]; then
  # Top-level "timezone" field — bash regex extraction.
  if [[ "$(cat "$CONFIG_FILE")" =~ \"timezone\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    DISPLAY_TZ="${BASH_REMATCH[1]}"
  fi
fi
if [ -z "$DISPLAY_TZ" ] && [ -n "${TIMEZONE:-}" ]; then
  DISPLAY_TZ="$TIMEZONE"
fi
if [ -z "$DISPLAY_TZ" ] && [ -n "${TZ:-}" ]; then
  DISPLAY_TZ="$TZ"
fi
if [ -z "$DISPLAY_TZ" ] && [ -f /etc/timezone ]; then
  DISPLAY_TZ=$(tr -d '[:space:]' < /etc/timezone 2>/dev/null || true)
fi
if [ -z "$DISPLAY_TZ" ]; then
  DISPLAY_TZ="UTC"
fi

# Container-local TZ — what the scheduler actually uses to evaluate
# the cron expression. Read from /etc/timezone OR $TZ env. We DO NOT
# fold this with DISPLAY_TZ — they may differ and the deny message
# needs both to explain the most common bug (typing for the wrong TZ).
CONTAINER_TZ=""
if [ -n "${TZ:-}" ]; then
  CONTAINER_TZ="$TZ"
elif [ -f /etc/timezone ]; then
  CONTAINER_TZ=$(tr -d '[:space:]' < /etc/timezone 2>/dev/null || true)
fi
if [ -z "$CONTAINER_TZ" ]; then
  CONTAINER_TZ="UTC"
fi

# ── Compute next fire time (inline Python) ─────────────────────────
# Python iterates minute-by-minute up to 8 days from NOW_EPOCH.
# Returns:
#   exit 0, stdout "<epoch> <iso-in-display-tz>" — found a match
#   exit 1, stdout empty — no match in 8 days
#   exit 2, stdout empty — parse error in cron expression
#
# Supports field forms: `*`, `*/N`, `A-B`, `A,B,C`, single integer.
# Field order: minute(0-59) hour(0-23) day(1-31) month(1-12) dow(0-6).
PY_OUT=$(
  CRON_EXPR="$CRON_EXPR" \
  DISPLAY_TZ="$DISPLAY_TZ" \
  FAKE_NOW_EPOCH="${FAKE_NOW_EPOCH:-}" \
  "$PYTHON" -c '
import os, sys, time, datetime

cron = os.environ["CRON_EXPR"].strip()
display_tz = os.environ.get("DISPLAY_TZ", "UTC")
fake_now = os.environ.get("FAKE_NOW_EPOCH", "").strip()

def parse_field(spec, lo, hi):
    """Return set of valid ints for one cron field."""
    out = set()
    for part in spec.split(","):
        part = part.strip()
        step = 1
        if "/" in part:
            base, step_s = part.split("/", 1)
            step = int(step_s)
            if step <= 0:
                raise ValueError("step must be positive")
        else:
            base = part
        if base == "*":
            start, end = lo, hi
        elif "-" in base:
            a, b = base.split("-", 1)
            start, end = int(a), int(b)
        else:
            start = end = int(base)
        if start < lo or end > hi or start > end:
            raise ValueError("field out of range")
        for v in range(start, end + 1, step):
            out.add(v)
    if not out:
        raise ValueError("empty field")
    return out

fields = cron.split()
if len(fields) != 5:
    sys.exit(2)

try:
    minutes = parse_field(fields[0], 0, 59)
    hours   = parse_field(fields[1], 0, 23)
    days    = parse_field(fields[2], 1, 31)
    months  = parse_field(fields[3], 1, 12)
    dows    = parse_field(fields[4], 0, 6)
except Exception:
    sys.exit(2)

if fake_now:
    now_epoch = int(fake_now)
else:
    now_epoch = int(time.time())

# Iterate minute-by-minute in CONTAINER (system) TZ — this is what the
# scheduler does. We start at the next whole minute >= now.
# Use time.localtime to convert; the container TZ is honored implicitly.
start = (now_epoch // 60) * 60
if start < now_epoch:
    start += 60

# 8 days = 8 * 24 * 60 minutes
limit = start + 8 * 24 * 60 * 60
t = start
found = None
while t < limit:
    lt = time.localtime(t)
    if (lt.tm_min in minutes
        and lt.tm_hour in hours
        and lt.tm_mday in days
        and lt.tm_mon in months
        # cron dow: 0-6 Sun-Sat; Python tm_wday: 0-6 Mon-Sun
        # Convert: cron_dow = (tm_wday + 1) % 7
        and ((lt.tm_wday + 1) % 7) in dows):
        found = t
        break
    t += 60

if found is None:
    sys.exit(1)

# Format the found time in display TZ. Use ZoneInfo if available
# (Python 3.9+); fall back to UTC label if not.
try:
    from zoneinfo import ZoneInfo
    tz = ZoneInfo(display_tz)
    dt = datetime.datetime.fromtimestamp(found, tz=tz)
    iso = dt.strftime("%Y-%m-%d %H:%M:%S %Z")
except Exception:
    # Best-effort fall back: format as UTC.
    dt = datetime.datetime.utcfromtimestamp(found)
    iso = dt.strftime("%Y-%m-%d %H:%M:%S UTC")

sys.stdout.write("%d %s" % (found, iso))
sys.exit(0)
' 2>/dev/null
)
PY_RC=$?

# ── Decide ─────────────────────────────────────────────────────────
emit_deny() {
  local reason="$1"
  # JSON-escape: backslashes first, then quotes, then newlines.
  local esc="${reason//\\/\\\\}"
  esc="${esc//\"/\\\"}"
  esc="${esc//$'\n'/\\n}"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$esc"
  exit 0
}

# Helper: humanize a delta in seconds.
human_delta() {
  local delta="$1"
  local sign=""
  if [ "$delta" -lt 0 ]; then
    sign="-"
    delta=$(( -delta ))
  fi
  local days hours minutes
  days=$(( delta / 86400 ))
  hours=$(( (delta % 86400) / 3600 ))
  minutes=$(( (delta % 3600) / 60 ))
  if [ "$days" -gt 0 ]; then
    printf '%s%dd %dh %dm' "$sign" "$days" "$hours" "$minutes"
  elif [ "$hours" -gt 0 ]; then
    printf '%s%dh %dm' "$sign" "$hours" "$minutes"
  else
    printf '%s%dm' "$sign" "$minutes"
  fi
}

# Recovery hint shared across deny messages.
RECOVERY_HINT='Recovery: container TZ is what the scheduler reads. If you wanted a different display TZ (e.g., ET), rebuild the cron expression with UTC offsets in mind, OR set top-level "timezone" in .claude/zskills-config.json to match the container.'

case "$PY_RC" in
  2)
    # Parse error — allow, but WARN to stderr so the scheduler's
    # own error path takes the surface.
    echo "block-bad-cron: cron expression '$CRON_EXPR' failed to parse — allowing through; scheduler will surface its own parse error" >&2
    exit 0
    ;;
  1)
    # No match in 8 days. If recurring, allow (legitimate edge cases:
    # 0 0 31 2 *, 0 0 29 2 * on non-leap years, etc).
    if [ "$RECURRING" = "true" ]; then
      exit 0
    fi
    # recurring=false → DENY.
    NOW_EPOCH_FOR_MSG="${FAKE_NOW_EPOCH:-$(date +%s)}"
    NOW_DISP=$(TZ="$DISPLAY_TZ" date -d "@$NOW_EPOCH_FOR_MSG" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || echo "(now)")
    REASON="STOP: CronCreate refused.

  cron expression: $CRON_EXPR
  recurring:       $RECURRING
  container TZ:    $CONTAINER_TZ
  display TZ:      $DISPLAY_TZ
  now (display):   $NOW_DISP

No match found within 8 days from now. For a one-shot cron (recurring=false), this means the next fire is so far away the Claude Code session will not survive to see it. Most common cause: the expression pins a day-of-month and month that have already passed for this year — cron with no year field rolls over to next year, so the cron sits in CronList for ~365 days and never fires.

$RECOVERY_HINT"
    emit_deny "$REASON"
    ;;
  0)
    # Got a fire time. Read epoch + iso from PY_OUT.
    FIRE_EPOCH=$(printf '%s' "$PY_OUT" | awk '{print $1}')
    FIRE_ISO=$(printf '%s' "$PY_OUT" | cut -d' ' -f2-)
    NOW_EPOCH_FOR_MSG="${FAKE_NOW_EPOCH:-$(date +%s)}"
    DELTA=$(( FIRE_EPOCH - NOW_EPOCH_FOR_MSG ))
    HUMAN=$(human_delta "$DELTA")
    NOW_DISP=$(TZ="$DISPLAY_TZ" date -d "@$NOW_EPOCH_FOR_MSG" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || echo "(now)")

    # Defensive: delta < 0 (shouldn't be reachable with a forward iter,
    # but guard anyway). Always deny.
    if [ "$DELTA" -lt 0 ]; then
      REASON="STOP: CronCreate refused.

  cron expression: $CRON_EXPR
  recurring:       $RECURRING
  container TZ:    $CONTAINER_TZ
  display TZ:      $DISPLAY_TZ
  now (display):   $NOW_DISP
  next fire:       $FIRE_ISO ($HUMAN from now)

Computed next-fire time is in the past. This is a defensive guard against an iterator bug — should not be reachable. Re-check the expression and the system clock.

$RECOVERY_HINT"
      emit_deny "$REASON"
    fi

    # recurring=false AND fire > 7 days out → session-lifetime deny.
    if [ "$RECURRING" = "false" ]; then
      SEVEN_DAYS=$(( 7 * 24 * 60 * 60 ))
      if [ "$DELTA" -gt "$SEVEN_DAYS" ]; then
        REASON="STOP: CronCreate refused.

  cron expression: $CRON_EXPR
  recurring:       $RECURRING
  container TZ:    $CONTAINER_TZ
  display TZ:      $DISPLAY_TZ
  now (display):   $NOW_DISP
  next fire:       $FIRE_ISO ($HUMAN from now)

For a one-shot cron (recurring=false), the next fire is more than 7 days from now. Claude Code session lifetime will not reach it. If you intended this fire time, switch to recurring=true. Otherwise, rebuild the cron expression to fire within 7 days.

$RECOVERY_HINT"
        emit_deny "$REASON"
      fi
    fi

    # All checks passed → allow.
    exit 0
    ;;
  *)
    # Python died for an unexpected reason. Fail-open with a WARN.
    echo "block-bad-cron: unexpected Python exit code $PY_RC — allowing through" >&2
    exit 0
    ;;
esac
