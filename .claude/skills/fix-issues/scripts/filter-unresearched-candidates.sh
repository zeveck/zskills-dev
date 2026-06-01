#!/bin/bash
# filter-unresearched-candidates.sh — Phase 2 source-filter for /fix-issues.
#
# Issue #408: Phase 1 step-5/step-6 are prose-only "should run." Across
# ~50 sprints they were skipped routinely; Phase 2 then triaged from bare
# titles + body previews, bypassing the just-landed #402 independent-
# sizing discipline (which requires a tracker blurb to read against).
#
# This script source-filters candidates rather than gating the sprint.
# Candidates that have an "**Action now:**" line within their
# `### #<N> ` section in any tracker file under $ZSKILLS_ISSUES_DIR are
# RESEARCHED; the rest are MISSING. Additionally, candidates whose
# Action-now value resolves to a canonical dashboard skip-code
# (`plan-scale`, `bug-unclear-cause`, `needs-decision`, `deferred`) are also emitted
# in a third SKIP_TAGGED line so Phase 2 A can drop them from
# CANDIDATE_ISSUES before triage (PR 2 / #606 tax fix).
#
# Output is three `key="val val val"` lines on stdout (RHS quoted so
# multi-token values survive `eval`):
#
#   RESEARCHED="11 12 13"
#   MISSING="14 15"
#   SKIP_TAGGED="11:plan-scale 13:bug-unclear-cause"
#
# SKIP_TAGGED tokens have the shape `<issue-num>:<skip-code>`; the line
# is always emitted (empty when no skip-class rows are found) so legacy
# consumers that only read RESEARCHED/MISSING keep working.
#
# Signal choice: `**Action now:**` (the Phase-2-consumed tier field), NOT
# `**Verdict:**`. Reasons:
#   - Old QE_ISSUES.md rows have no Verdict line at all.
#   - `**Verdict:** LIKELY FIXED` / `UNCLEAR` / `FIXED` are real verdicts
#     that mean "uncertain/closed-leaning," not "ready to fix."
#   - Row-writer creates stubs with `**Verdict:** NOT YET RESEARCHED`; a
#     Verdict-presence check would no-op the gate.
#
# Skip-code derivation mirrors `_parse_action_now` priority order in
# `skills/zskills-dashboard/scripts/zskills_monitor/collect.py` (none →
# /draft-plan|/run-plan → /investigate). POSIX-portable boundary class
# `[^[:alnum:]_-]` is used in place of awk `\b` (non-portable).
#
# Usage:
#   ZSKILLS_ISSUES_DIR=/path/to/issues bash filter-unresearched-candidates.sh 380 390 392 ...
#   eval "$(ZSKILLS_ISSUES_DIR=... bash filter-unresearched-candidates.sh "${CANDIDATE_ISSUES[@]}")"
#
# Exit:
#   0 — always (an empty candidate list also exits 0 with all arrays empty).
#   1 — usage error (ZSKILLS_ISSUES_DIR unset, etc.).

set -u

if [ -z "${ZSKILLS_ISSUES_DIR:-}" ]; then
  echo "ERROR: ZSKILLS_ISSUES_DIR not set" >&2
  exit 1
fi

# Read the reconsider list and the skipped map from monitor-state.json.
#
# `issues.reconsider` is a one-shot signal: issues here have their skip-
# code suppressed so Phase 2 re-evaluates them. After emitting them as
# candidates, we remove them from the list so the signal doesn't persist
# across sprints. The same cleanup also removes any matching entries from
# `issues.skipped` (reconsider and skipped are duals: reconsidering an
# issue means "un-skip and re-triage").
#
# `issues.skipped` is the persistent skip-state added for issue #808: when
# triage declines an issue as plan-scale / bug-unclear-cause /
# needs-decision / deferred, the orchestrator records it here so the next
# fire's filter drops it BEFORE re-triage — even when the issue has no
# tracker row (raw dashboard-drag case). The map value is EITHER a bare
# code string `"<skip-code>"` (legacy / no-reason) OR a dict
# `{"code": "<skip-code>", "reason": "<free-text>"}` (#862, when a
# free-text reason was recorded). The filter only consumes the CODE; the
# reason flows to the dashboard chip via collect.py. This is symmetric
# with `issues.reconsider`: monitor-state.json is gitignored, so the
# skip-record never lands as a tracker-row commit on main.
#
# Effective-skip-reason precedence (#862) — MUST match
# collect.py:_resolve_effective_skip_code precedence exactly, otherwise
# the dashboard chip and this drop-decision split-brain again: the live
# `issues.skipped[N]` override WINS when present; only when it is absent
# does the tracker-row `Action now:` blurb-derived code apply.
MAIN_ROOT="${ZSKILLS_MAIN_ROOT:-$(cd "$(git rev-parse --git-common-dir 2>/dev/null)/.." 2>/dev/null && pwd)}"
STATE_FILE="${MAIN_ROOT:+$MAIN_ROOT/.zskills/monitor-state.json}"
RECONSIDER_NUMS=""
declare -A MONITOR_SKIPPED_MAP=()
if [ -n "$STATE_FILE" ] && [ -f "$STATE_FILE" ]; then
  RECONSIDER_NUMS=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    nums = data.get('issues', {}).get('reconsider', [])
    print(' '.join(str(n) for n in nums))
except Exception:
    pass
" "$STATE_FILE" 2>/dev/null) || RECONSIDER_NUMS=""

  # Read issues.skipped as `<num> <code>` pairs (newline-separated).
  while IFS=$'\t' read -r _n _c; do
    [ -n "$_n" ] && MONITOR_SKIPPED_MAP["$_n"]="$_c"
  done < <(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    skipped = data.get('issues', {}).get('skipped', {}) or {}
    # The map value is EITHER a bare code string (legacy / no-reason) OR a
    # dict {'code': ..., 'reason': ...} (#862). The filter only consumes
    # the CODE; reason is for the dashboard chip. Extract the code from
    # whichever shape is present.
    if isinstance(skipped, dict):
        for k, v in skipped.items():
            if isinstance(v, dict):
                code = v.get('code')
            else:
                code = v
            if code:
                print(f'{k}\t{code}')
except Exception:
    pass
" "$STATE_FILE" 2>/dev/null)
  unset _n _c
fi

RESEARCHED=()
MISSING=()
SKIP_TAGGED=()
RECONSIDERED_PROCESSED=()

for N in "$@"; do
  # Skip non-numeric tokens defensively.
  case "$N" in
    ''|*[!0-9]*) continue ;;
  esac
  # Match the Action-now substring within the `### #<N> ` section of
  # any tracker. The trailing space after #<N> is intentional — it
  # prevents `#38` from matching `#380`. `**Action now:**` is NOT
  # line-anchored: real tracker rows place it mid-line after
  # `**Complexity:** ... .` (see existing rows in docs/issues/ISSUES_PLAN.md).
  #
  # Section bounding: awk reads from the `### #<N> ` line until the NEXT
  # `### ` heading (any). A naive `grep -A 50` would bleed into the
  # following section and yield false positives when a later researched
  # row sits within 50 lines.
  #
  # Awk also extracts the Action-now value (substring after the bold
  # marker) and prints `SKIP=<code>` if it resolves to one of the three
  # canonical dashboard skip-codes via POSIX-portable boundary matching.
  # Check if this issue is in the reconsider list (monitor-state.json).
  is_reconsidered=0
  case " $RECONSIDER_NUMS " in
    *" $N "*) is_reconsidered=1 ;;
  esac

  found=0
  skip_code=""
  for f in "$ZSKILLS_ISSUES_DIR"/*.md; do
    [ -f "$f" ] || continue
    out=$(awk -v n="$N" -v recon="$is_reconsidered" '
      $0 ~ "^### #" n " " { in_sec=1; next }
      in_sec && /^### / { exit }
      in_sec && index($0, "**Action now:**") > 0 {
        print "HIT"
        if (recon) { exit }
        if (match($0, /\*\*Action now:\*\*[[:space:]]*/)) {
          val = substr($0, RSTART + RLENGTH)
          # Lowercase for case-insensitive prefix matching.
          val_lc = tolower(val)
          # Priority: none → /draft-plan|/run-plan → /investigate.
          # POSIX-portable boundary: NOT [:alnum:]_- or end-of-string.
          # `none` splits into needs-decision (human input required:
          # "author decision" or "decide") vs deferred (agent-parked).
          if (val_lc ~ /^none([^[:alnum:]_-]|$)/) {
            if (val_lc ~ /author decision/ || val_lc ~ /[^[:alnum:]_-]decide([^[:alnum:]_-]|$)/) {
              print "SKIP=needs-decision"
            } else {
              print "SKIP=deferred"
            }
          } else if (val_lc ~ /^\/draft-plan([^[:alnum:]_-]|$)/ || val_lc ~ /^\/run-plan([^[:alnum:]_-]|$)/) {
            print "SKIP=plan-scale"
          } else if (val_lc ~ /^\/investigate([^[:alnum:]_-]|$)/) {
            print "SKIP=bug-unclear-cause"
          }
        }
        exit
      }
    ' "$f" 2>/dev/null)
    if printf '%s\n' "$out" | grep -q '^HIT$'; then
      found=1
      # Extract skip code if any (first-match-wins across files).
      sk=$(printf '%s\n' "$out" | grep '^SKIP=' | head -1 | sed 's/^SKIP=//')
      if [ -n "$sk" ]; then
        skip_code="$sk"
      fi
      break
    fi
  done
  # Monitor-state skip override (#808): if monitor-state.json's
  # `issues.skipped` map has this issue, emit SKIP_TAGGED with the
  # recorded code EVEN WHEN no tracker row exists. This is the raw
  # dashboard-drag case — the orchestrator declined plan-scale before
  # any research blurb was written. The reconsider list still suppresses
  # this (one-shot un-skip + re-triage).
  monitor_skip_code="${MONITOR_SKIPPED_MAP[$N]:-}"
  if [ "$is_reconsidered" -eq 1 ]; then
    monitor_skip_code=""
    # Track even an unresearched reconsidered issue so the one-shot
    # cleanup below removes the monitor-state entries on this fire.
    RECONSIDERED_PROCESSED+=("$N")
  fi

  if [ "$found" -eq 1 ]; then
    RESEARCHED+=("$N")
    # Effective-skip-reason precedence (#862): the live monitor-state
    # override WINS over the tracker-row blurb-derived code. This mirrors
    # collect.py:_resolve_effective_skip_code so the dashboard chip and
    # this drop-decision never diverge (an orchestrator that re-triages an
    # issue and records a new classification in monitor-state must move
    # BOTH the chip and the filter, not just the filter). When no
    # monitor-state override is present, fall back to the tracker-derived
    # code.
    if [ -n "$monitor_skip_code" ]; then
      SKIP_TAGGED+=("$N:$monitor_skip_code")
    elif [ -n "$skip_code" ]; then
      SKIP_TAGGED+=("$N:$skip_code")
    fi
    if [ "$is_reconsidered" -eq 1 ]; then
      # already appended above when we cleared monitor_skip_code
      :
    fi
  else
    if [ -n "$monitor_skip_code" ]; then
      # No tracker row, but monitor-state.json has a persisted skip.
      # Count as RESEARCHED-for-filtering-purposes AND emit SKIP_TAGGED
      # so Phase 2 drops the candidate without dispatching research.
      # Treating it as MISSING would route through research-on-demand
      # and re-litigate the same skip decision every fire — the bug
      # this commit fixes.
      RESEARCHED+=("$N")
      SKIP_TAGGED+=("$N:$monitor_skip_code")
    else
      MISSING+=("$N")
    fi
  fi
done

printf 'RESEARCHED="%s"\n' "${RESEARCHED[*]}"
printf 'MISSING="%s"\n' "${MISSING[*]}"
printf 'SKIP_TAGGED="%s"\n' "${SKIP_TAGGED[*]}"

# One-shot cleanup: remove processed reconsider entries from
# monitor-state.json so the signal doesn't persist across sprints. Also
# remove any matching entries from `issues.skipped` — reconsider and
# skipped are duals (see #808: reconsidering an issue un-skips it so
# Phase 2 re-triages it cleanly on this fire).
if [ "${#RECONSIDERED_PROCESSED[@]}" -gt 0 ] && [ -n "$STATE_FILE" ] && [ -f "$STATE_FILE" ]; then
  REMOVE_LIST=$(printf '%s\n' "${RECONSIDERED_PROCESSED[@]}" | tr '\n' ' ' | sed 's/ $//')
  python3 -c "
import json, sys, os, tempfile

path = sys.argv[1]
remove_ints = set(int(x) for x in sys.argv[2:])
remove_strs = set(str(x) for x in sys.argv[2:])

with open(path) as f:
    data = json.load(f)

issues = data.get('issues', {}) or {}
changed = False

# reconsider: list of ints
cur = issues.get('reconsider', [])
after = [n for n in cur if n not in remove_ints]
if len(after) != len(cur):
    if after:
        issues['reconsider'] = after
    else:
        issues.pop('reconsider', None)
    changed = True

# skipped: dict keyed by stringified issue num
skipped = issues.get('skipped', {}) or {}
if isinstance(skipped, dict):
    new_skipped = {k: v for k, v in skipped.items() if k not in remove_strs}
    if len(new_skipped) != len(skipped):
        if new_skipped:
            issues['skipped'] = new_skipped
        else:
            issues.pop('skipped', None)
        changed = True

if not changed:
    sys.exit(0)

data['issues'] = issues

tmp = tempfile.NamedTemporaryFile('w', delete=False,
    dir=os.path.dirname(path), prefix='.monitor-state.', suffix='.tmp')
json.dump(data, tmp, indent=2)
tmp.write('\n')
tmp.close()
os.replace(tmp.name, path)
" "$STATE_FILE" ${RECONSIDERED_PROCESSED[*]} 2>/dev/null || true
fi
