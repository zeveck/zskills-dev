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
# RESEARCHED; the rest are MISSING. Output is two `key="val val val"`
# lines on stdout (RHS quoted so multi-token values survive `eval`):
#
#   RESEARCHED="11 12 13"
#   MISSING="14 15"
#
# Signal choice: `**Action now:**` (the Phase-2-consumed tier field), NOT
# `**Verdict:**`. Reasons:
#   - Old QE_ISSUES.md rows have no Verdict line at all.
#   - `**Verdict:** LIKELY FIXED` / `UNCLEAR` / `FIXED` are real verdicts
#     that mean "uncertain/closed-leaning," not "ready to fix."
#   - Row-writer creates stubs with `**Verdict:** NOT YET RESEARCHED`; a
#     Verdict-presence check would no-op the gate.
#
# Usage:
#   ZSKILLS_ISSUES_DIR=/path/to/issues bash filter-unresearched-candidates.sh 380 390 392 ...
#   eval "$(ZSKILLS_ISSUES_DIR=... bash filter-unresearched-candidates.sh "${CANDIDATE_ISSUES[@]}")"
#
# Exit:
#   0 — always (an empty candidate list also exits 0 with both arrays empty).
#   1 — usage error (ZSKILLS_ISSUES_DIR unset, etc.).

set -u

if [ -z "${ZSKILLS_ISSUES_DIR:-}" ]; then
  echo "ERROR: ZSKILLS_ISSUES_DIR not set" >&2
  exit 1
fi

RESEARCHED=()
MISSING=()

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
  found=0
  for f in "$ZSKILLS_ISSUES_DIR"/*.md; do
    [ -f "$f" ] || continue
    if awk -v n="$N" '
      $0 ~ "^### #" n " " { in_sec=1; next }
      in_sec && /^### / { exit }
      in_sec && index($0, "**Action now:**") > 0 { print "HIT"; exit }
    ' "$f" 2>/dev/null | grep -q '^HIT$'; then
      found=1
      break
    fi
  done
  if [ "$found" -eq 1 ]; then
    RESEARCHED+=("$N")
  else
    MISSING+=("$N")
  fi
done

printf 'RESEARCHED="%s"\n' "${RESEARCHED[*]}"
printf 'MISSING="%s"\n' "${MISSING[*]}"
