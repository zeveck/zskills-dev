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
# (`plan-scale`, `bug-unclear-cause`, `needs-decision`) are also emitted
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

RESEARCHED=()
MISSING=()
SKIP_TAGGED=()

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
  found=0
  skip_code=""
  for f in "$ZSKILLS_ISSUES_DIR"/*.md; do
    [ -f "$f" ] || continue
    out=$(awk -v n="$N" '
      $0 ~ "^### #" n " " { in_sec=1; next }
      in_sec && /^### / { exit }
      in_sec && index($0, "**Action now:**") > 0 {
        print "HIT"
        if (match($0, /\*\*Action now:\*\*[[:space:]]*/)) {
          val = substr($0, RSTART + RLENGTH)
          # Lowercase for case-insensitive prefix matching.
          val_lc = tolower(val)
          # Priority: none → /draft-plan|/run-plan → /investigate.
          # POSIX-portable boundary: NOT [:alnum:]_- or end-of-string.
          if (val_lc ~ /^none([^[:alnum:]_-]|$)/) {
            print "SKIP=needs-decision"
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
  if [ "$found" -eq 1 ]; then
    RESEARCHED+=("$N")
    if [ -n "$skip_code" ]; then
      SKIP_TAGGED+=("$N:$skip_code")
    fi
  else
    MISSING+=("$N")
  fi
done

printf 'RESEARCHED="%s"\n' "${RESEARCHED[*]}"
printf 'MISSING="%s"\n' "${MISSING[*]}"
printf 'SKIP_TAGGED="%s"\n' "${SKIP_TAGGED[*]}"
