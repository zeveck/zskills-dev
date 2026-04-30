#!/bin/bash
# review-loop.sh -- Phase 4 round driver for /draft-tests.
#
# Orchestrates the senior-QE review loop:
#   - Coverage-floor pre-check (BEFORE agent dispatch each round, per
#     AC-4.8).
#   - Reviewer + DA dispatched in parallel (mocked in tests via
#     ZSKILLS_DRAFT_TESTS_REVIEWER_STUB / ..._DA_STUB env vars).
#   - Refiner dispatched serially after reviewer/DA (mocked via
#     ZSKILLS_DRAFT_TESTS_REFINER_STUB).
#   - Convergence determined by the orchestrator -- mechanically, on
#     the refiner's disposition table -- NEVER by the refiner's prose
#     "CONVERGED" claim (AC-4.9 negative-case guard).
#   - Per-round artifacts written to /tmp:
#       /tmp/draft-tests-candidate-round-<N>-<slug>.md
#       /tmp/draft-tests-review-round-<N>-<slug>.md
#       /tmp/draft-tests-refined-round-<N>-<slug>.md
#   - On max rounds with coverage floor unmet, exits with return code 2
#     (partial-success) AND writes a "Remaining concerns" note (AC-4.6,
#     AC-4.7).
#
# Live LLM dispatch is gated behind ZSKILLS_TEST_LLM=1. Without that env
# var set AND without stub env vars set, the script errors out instead
# of making live model calls (per AC-4.5).
#
# Usage:
#   bash review-loop.sh \
#       <plan-file> <parsed-state> <draft-round-out> <slug> <max-rounds>
#
# Arguments:
#   <plan-file>          Plan .md (already mutated by Phase 3 with
#                        per-phase `### Tests` subsections).
#   <parsed-state>       `/tmp/draft-tests-parsed-<slug>.md`.
#   <draft-round-out>    `/tmp/draft-tests-draft-round-0-<slug>.md`
#                        from Phase 3.
#   <slug>               Plan slug.
#   <max-rounds>         Maximum review rounds (default 3 -- see Phase 4
#                        Design & Constraints).
#
# Stub env vars (tests):
#   ZSKILLS_DRAFT_TESTS_REVIEWER_STUB_<N>  -- file containing pre-authored
#                        reviewer findings for round <N> (1-indexed).
#                        Example: ZSKILLS_DRAFT_TESTS_REVIEWER_STUB_1.
#   ZSKILLS_DRAFT_TESTS_DA_STUB_<N>        -- DA findings for round <N>.
#   ZSKILLS_DRAFT_TESTS_REFINER_STUB_<N>   -- refined draft + disposition
#                        table for round <N>.
#
# Live mode: ZSKILLS_TEST_LLM=1 (placeholder; live dispatch is invoked
# from SKILL.md prose, not this script -- this script handles the
# mechanical orchestration around it).
#
# Exit codes:
#   0 -- converged within max rounds.
#   2 -- max rounds reached AND coverage floor unmet (partial-success
#        per AC-4.6 / AC-4.7).
#   3 -- max rounds reached, coverage floor met, but convergence not
#        achieved on other criteria. Plan is still written; downstream
#        automation may treat as soft failure.
#   4 -- usage error.
#   5 -- input file missing.
#   6 -- live LLM mode requested but stubs not provided AND live
#        dispatch is not configured. (Live dispatch is the SKILL.md
#        prose's responsibility; this script is mechanical only.)

set -u

PLAN_FILE="${1:-}"
PARSED_STATE="${2:-}"
DRAFT_ROUND_OUT="${3:-}"
SLUG="${4:-}"
MAX_ROUNDS="${5:-3}"

if [ -z "$PLAN_FILE" ] || [ -z "$PARSED_STATE" ] || [ -z "$DRAFT_ROUND_OUT" ] \
   || [ -z "$SLUG" ]; then
  echo "Usage: $0 <plan-file> <parsed-state> <draft-round-out> <slug> [<max-rounds>]" >&2
  exit 4
fi

for f in "$PLAN_FILE" "$PARSED_STATE" "$DRAFT_ROUND_OUT"; do
  if [ ! -f "$f" ]; then
    echo "Error: input file '$f' not found." >&2
    exit 5
  fi
done

# Resolve sibling scripts.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRECHECK_SCRIPT="$SCRIPT_DIR/coverage-floor-precheck.sh"
CONVERGENCE_SCRIPT="$SCRIPT_DIR/convergence-check.sh"
for s in "$PRECHECK_SCRIPT" "$CONVERGENCE_SCRIPT"; do
  if [ ! -f "$s" ]; then
    echo "Error: sibling script '$s' not found." >&2
    exit 5
  fi
done

TMP_BASE="${TMPDIR:-/tmp}"

# Round 0 input is the drafter output. Round N>0 input is the prior
# refiner output (round N-1).
prev_input="$DRAFT_ROUND_OUT"
exit_status=0
final_round=0

# Track whether convergence was reached and the final coverage findings
# for the "Remaining concerns" note.
converged=0
final_floor_findings=""
final_refiner_out=""

# Helper: resolve a stub-env-var-pointed file for a given role/round, or
# emit an error if the stub is required but missing.
resolve_stub() {
  local role="$1"   # REVIEWER / DA / REFINER
  local round="$2"
  local var_name="ZSKILLS_DRAFT_TESTS_${role}_STUB_${round}"
  local file_path="${!var_name:-}"
  if [ -z "$file_path" ]; then
    echo ""
    return 0
  fi
  if [ ! -f "$file_path" ]; then
    echo "Error: stub var $var_name points at missing file '$file_path'." >&2
    return 1
  fi
  echo "$file_path"
}

for ((round=1; round<=MAX_ROUNDS; round++)); do
  CANDIDATE_OUT="$TMP_BASE/draft-tests-candidate-round-${round}-${SLUG}.md"
  FLOOR_FINDINGS="$TMP_BASE/draft-tests-floor-findings-round-${round}-${SLUG}.md"
  REVIEW_OUT="$TMP_BASE/draft-tests-review-round-${round}-${SLUG}.md"
  REFINED_OUT="$TMP_BASE/draft-tests-refined-round-${round}-${SLUG}.md"

  # ------------------------------------------------------------------
  # Step 1: coverage-floor pre-check on the merged candidate (AC-4.8).
  # The pre-check runs BEFORE agent dispatch this round.
  # ------------------------------------------------------------------
  if ! bash "$PRECHECK_SCRIPT" "$PLAN_FILE" "$PARSED_STATE" "$prev_input" \
        "$round" "$SLUG" "$CANDIDATE_OUT" "$FLOOR_FINDINGS"; then
    echo "Error: coverage-floor-precheck failed at round $round." >&2
    exit 5
  fi

  # ------------------------------------------------------------------
  # Step 2: dispatch reviewer + DA (in parallel, conceptually). In test
  # mode, the stubs ARE the agent output. In live mode (when
  # ZSKILLS_TEST_LLM=1 and no stubs), the SKILL.md prose dispatches the
  # agents; this script is reused after the agents return their files.
  # ------------------------------------------------------------------
  reviewer_file="$(resolve_stub REVIEWER "$round")" || exit 5
  da_file="$(resolve_stub DA "$round")" || exit 5

  if [ -z "$reviewer_file" ] || [ -z "$da_file" ]; then
    if [ "${ZSKILLS_TEST_LLM:-}" = "1" ]; then
      echo "Error: live LLM mode (ZSKILLS_TEST_LLM=1) but no agent dispatch wired into this script. Use SKILL.md prose to dispatch agents and pass stub files via ZSKILLS_DRAFT_TESTS_REVIEWER_STUB_${round} / ..._DA_STUB_${round}." >&2
      exit 6
    fi
    echo "Error: round $round has no reviewer/DA stub. Set ZSKILLS_DRAFT_TESTS_REVIEWER_STUB_${round} and ZSKILLS_DRAFT_TESTS_DA_STUB_${round}, or run with ZSKILLS_TEST_LLM=1 via SKILL.md." >&2
    exit 6
  fi

  # Combine reviewer + DA + synthesised coverage-floor findings into
  # the round's review artifact (per WI 4.10).
  {
    printf '# Review round %s -- combined reviewer + DA + coverage-floor findings\n\n' "$round"
    printf '## Reviewer\n\n'
    cat "$reviewer_file"
    printf '\n## Devil''\''s Advocate\n\n'
    cat "$da_file"
    printf '\n## Synthesised coverage-floor findings (orchestrator pre-check)\n\n'
    if [ -s "$FLOOR_FINDINGS" ]; then
      cat "$FLOOR_FINDINGS"
    else
      printf 'No coverage-floor violations.\n'
    fi
  } > "$REVIEW_OUT"

  # ------------------------------------------------------------------
  # Step 3: dispatch refiner (verify-before-fix; produces a disposition
  # table). Stub for tests.
  # ------------------------------------------------------------------
  refiner_file="$(resolve_stub REFINER "$round")" || exit 5
  if [ -z "$refiner_file" ]; then
    if [ "${ZSKILLS_TEST_LLM:-}" = "1" ]; then
      echo "Error: live LLM mode (ZSKILLS_TEST_LLM=1) but no refiner dispatch wired into this script. Pass ZSKILLS_DRAFT_TESTS_REFINER_STUB_${round}." >&2
      exit 6
    fi
    echo "Error: round $round has no refiner stub. Set ZSKILLS_DRAFT_TESTS_REFINER_STUB_${round}, or run with ZSKILLS_TEST_LLM=1 via SKILL.md." >&2
    exit 6
  fi
  cp "$refiner_file" "$REFINED_OUT"

  # ------------------------------------------------------------------
  # Step 4: orchestrator's mechanical convergence check. Per AC-4.9, we
  # NEVER trust the refiner's prose claim of "CONVERGED" -- the script
  # only inspects the disposition table.
  # ------------------------------------------------------------------
  conv_out="$(bash "$CONVERGENCE_SCRIPT" "$REFINED_OUT" "$FLOOR_FINDINGS" 2>/dev/null)"
  conv_rc=$?
  echo "$conv_out"

  final_round=$round
  final_floor_findings="$FLOOR_FINDINGS"
  final_refiner_out="$REFINED_OUT"

  if [ $conv_rc -eq 0 ]; then
    converged=1
    break
  fi

  # Carry the refined output forward as the next round's pre-check
  # input.
  prev_input="$REFINED_OUT"
done

# ----------------------------------------------------------------------
# Post-loop: write the "Remaining concerns" note alongside the final
# refined output if convergence was not reached. Reconcile AC-4.6 (note
# + plan written) with AC-4.7 (exit 2 if floor unmet).
# ----------------------------------------------------------------------
REMAINING_NOTE="$TMP_BASE/draft-tests-remaining-concerns-${SLUG}.md"

if [ "$converged" = "1" ]; then
  : > "$REMAINING_NOTE"
  exit_status=0
else
  # Build the Remaining concerns note.
  {
    printf '## Remaining concerns (max rounds reached)\n\n'
    printf 'Loop hit max rounds (%s) without orchestrator-judgment convergence.\n\n' "$MAX_ROUNDS"
    if [ -s "$final_floor_findings" ]; then
      printf '### Coverage-floor violations still unresolved\n\n'
      cat "$final_floor_findings"
      printf '\n'
    fi
    printf '### Final-round refiner disposition\n\n'
    cat "$final_refiner_out"
  } > "$REMAINING_NOTE"

  # Determine exit code: AC-4.7 says "max rounds AND coverage floor
  # unmet -> exit 2". If the floor IS met but other convergence
  # conditions aren't, exit 3 (soft failure -- plan still written).
  if [ -s "$final_floor_findings" ]; then
    # The floor finding is still outstanding (precheck found a synthetic
    # finding this round). But it COULD be marked Fixed in the refiner's
    # disposition. Re-check by running convergence-check with the
    # condition-1-only logic: if that still fails, exit 2.
    floor_remaining=0
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      if [[ "$line" =~ Coverage[[:space:]]floor[[:space:]]violated:[[:space:]]+(AC-[0-9]+[a-z]?\.[0-9]+[a-z]?) ]]; then
        ac_id="${BASH_REMATCH[1]}"
        if ! grep -E -q "\\|.*${ac_id}.*\\|.*\\|[[:space:]]*[Ff]ixed" "$final_refiner_out"; then
          floor_remaining=1
          break
        fi
      fi
    done < "$final_floor_findings"
    if [ "$floor_remaining" = "1" ]; then
      exit_status=2
    else
      exit_status=3
    fi
  else
    exit_status=3
  fi
fi

echo "review-loop: rounds=$final_round converged=$converged exit=$exit_status"
exit $exit_status
