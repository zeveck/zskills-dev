#!/bin/bash
# Tests for /run-plan Step 0 Case 3's adaptive cron backoff decision rule.
#
# The backoff rule is specified in skills/run-plan/SKILL.md, Step 0
# Case 3 ("Next-target phase already In Progress"), with the
# sentinel-recovery prelude immediately above (the
# "cron-recovery-needed.<phase>" branch). The skill's bash is entangled
# with prose, so this test re-implements the decision rule inline as
# `defer_backoff_step()` — matching the skill's algorithm exactly —
# and exercises it against synthesized cron/marker state.
#
# Assertions target the rule's PUBLIC CONTRACT:
#   - per-phase counter advances on every fire (C → C+1)
#   - target cadence T = f(C+1):  <10 → */1,  10..15 → */10,
#     16..25 → */30,  ≥26 → */60
#   - cadence change requires CronDelete-all + single CronCreate at T
#   - 3-retry CronCreate-verify with sleep 2 between attempts (N1)
#   - retry exhaustion writes cron-recovery-needed.<phase> sentinel and
#     emits a user-visible WARN (high-severity race; N2)
#   - sentinel-recovery prelude tries CronCreate before normal flow,
#     with a cadence-sanity check (A1) that rejects out-of-set cadences
#   - Case 4 entry on a new phase rms in-progress-defers.* AND
#     cron-recovery-needed.* (per-phase counter scope; #110 R6)
#   - defer message printed only at boundary fires C+1 ∈ {1,10,16,26}
#
# If the real skill's rule diverges from this state machine, the
# skill is wrong OR this test is stale — read both, decide which.
# The invariants test (test-skill-invariants.sh) locks down anchors
# so the rule cannot be silently deleted.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  printf '\033[32m  PASS\033[0m %s\n' "$1"
  PASS_COUNT=$((PASS_COUNT+1))
}

fail() {
  printf '\033[31m  FAIL\033[0m %s\n' "$1"
  FAIL_COUNT=$((FAIL_COUNT+1))
}

# Reads globals: COUNTER_VALUE, CURRENT_CADENCE, CRONLIST_MATCH_COUNT,
# CRONCREATE_VERIFY_RESULT (ok|missing|missing-after-3-retries), PHASE,
# PLAN_FILE, TRACKING_ID, RECOVERY_MARKER_PRESENT (yes|no), CASE (3|4).
# Emits decision lines (vocab in header docstring + spec).
defer_backoff_step() {
  # ---- Sentinel-recovery prelude (#110 WI 1.2; A1 fix) -----------------
  if [ "$RECOVERY_MARKER_PRESENT" = "yes" ]; then
    echo "PRELUDE_RECOVERY_ATTEMPTED"
    if [ "${CRONLIST_MATCH_COUNT:-0}" -ge 1 ]; then
      # Cron exists — cadence-sanity check (A1). Sane set: */1, */10, */30, */60.
      case "$CURRENT_CADENCE" in
        '*/1'|'*/10'|'*/30'|'*/60')
          echo "PRELUDE_RECOVERY_OK"
          ;;
        *)
          # Bad cadence: force-delete, recreate at */1, hold counter.
          echo "WARN cron-recovery-bad-cadence $CURRENT_CADENCE"
          echo "DELETE_ALL_MATCHING_CRONS"
          echo "REPLACE_CRON */1"
          echo "PRELUDE_RECOVERY_OK"
          return 0
          ;;
      esac
    else
      # No cron; prelude attempts CronCreate at */1.
      if [ "$CRONCREATE_VERIFY_RESULT" = "ok" ]; then
        echo "REPLACE_CRON */1"
        echo "PRELUDE_RECOVERY_OK"
      else
        echo "PRELUDE_RECOVERY_FAILED"
      fi
    fi
  fi

  # ---- Case 4: new-phase entry (rm per-phase counters + sentinel) ------
  if [ "${CASE:-3}" = "4" ]; then
    echo "DELETE_COUNTER"
    return 0
  fi

  # ---- Case 3: adaptive backoff decision rule --------------------------
  # Step 1: counter C → NEXT = C+1.
  local C="${COUNTER_VALUE:-0}"
  local NEXT=$((C + 1))

  # Step 2: read R via CronList. No match → WARN + hold counter + exit.
  if [ "${CRONLIST_MATCH_COUNT:-1}" -eq 0 ]; then
    echo "WARN no-cron-match"
    return 0
  fi
  local R="$CURRENT_CADENCE"

  # Step 3: compute target cadence T from NEXT.
  local T
  if   [ "$NEXT" -lt 10 ]; then T='*/1'
  elif [ "$NEXT" -le 15 ]; then T='*/10'
  elif [ "$NEXT" -le 25 ]; then T='*/30'
  else                          T='*/60'
  fi

  # Step 4: if T != R, replace cron (delete-all + create + verify w/ 3
  # retries, sleep 2 between attempts — N1).
  if [ "$T" != "$R" ]; then
    echo "DELETE_ALL_MATCHING_CRONS"
    case "$CRONCREATE_VERIFY_RESULT" in
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
        return 0
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
  return 0
}

# Fixture setup
setup_fixture() {
  FIXTURE_DIR=$(mktemp -d)
  COUNTER_VALUE=0
  CURRENT_CADENCE='*/1'
  CRONLIST_MATCH_COUNT=1
  CRONCREATE_VERIFY_RESULT=ok
  PHASE=3
  PLAN_FILE="plans/demo.md"
  TRACKING_ID="demo"
  RECOVERY_MARKER_PRESENT=no
  CASE=3
}

teardown_fixture() {
  [ -n "$FIXTURE_DIR" ] && rm -rf "$FIXTURE_DIR"
  FIXTURE_DIR=""
  unset COUNTER_VALUE CURRENT_CADENCE CRONLIST_MATCH_COUNT \
        CRONCREATE_VERIFY_RESULT PHASE PLAN_FILE TRACKING_ID \
        RECOVERY_MARKER_PRESENT CASE
}

# Case 1: cold start — counter=0, cadence */1, single match. NEXT=1
# is a boundary fire; T=*/1 equals R, so no REPLACE_CRON; counter
# advances to 1 with the defer message printed.
setup_fixture
COUNTER_VALUE=0
CURRENT_CADENCE='*/1'
CRONLIST_MATCH_COUNT=1
RECOVERY_MARKER_PRESENT=no
OUT=$(defer_backoff_step)
teardown_fixture
if [[ "$OUT" == *"WRITE_COUNTER 1"* ]] \
   && [[ "$OUT" == *"PROCEED defer-message-printed"* ]] \
   && [[ "$OUT" != *"REPLACE_CRON"* ]]; then
  pass "case 1: cold-start C=0 → WRITE_COUNTER 1, no REPLACE_CRON, defer printed"
else
  fail "case 1: cold-start — got: $OUT"
fi

# Case 2: counter=9, cadence */1 → NEXT=10, boundary, target */10.
# Cadence change required: delete-all + replace + write counter + print.
setup_fixture
COUNTER_VALUE=9
CURRENT_CADENCE='*/1'
CRONCREATE_VERIFY_RESULT=ok
OUT=$(defer_backoff_step)
teardown_fixture
if [[ "$OUT" == *"DELETE_ALL_MATCHING_CRONS"* ]] \
   && [[ "$OUT" == *"REPLACE_CRON */10"* ]] \
   && [[ "$OUT" == *"WRITE_COUNTER 10"* ]] \
   && [[ "$OUT" == *"PROCEED defer-message-printed"* ]]; then
  pass "case 2: C=9 */1 → step down to */10 at boundary, counter=10"
else
  fail "case 2: step-down to */10 — got: $OUT"
fi

# Case 3: counter=15, cadence */10 → NEXT=16, boundary, target */30.
setup_fixture
COUNTER_VALUE=15
CURRENT_CADENCE='*/10'
CRONCREATE_VERIFY_RESULT=ok
OUT=$(defer_backoff_step)
teardown_fixture
if [[ "$OUT" == *"REPLACE_CRON */30"* ]] \
   && [[ "$OUT" == *"WRITE_COUNTER 16"* ]] \
   && [[ "$OUT" == *"PROCEED defer-message-printed"* ]]; then
  pass "case 3: C=15 */10 → step down to */30 at boundary, counter=16"
else
  fail "case 3: step-down to */30 — got: $OUT"
fi

# Case 4: counter=25, cadence */30 → NEXT=26, boundary, target */60.
setup_fixture
COUNTER_VALUE=25
CURRENT_CADENCE='*/30'
CRONCREATE_VERIFY_RESULT=ok
OUT=$(defer_backoff_step)
teardown_fixture
if [[ "$OUT" == *"REPLACE_CRON */60"* ]] \
   && [[ "$OUT" == *"WRITE_COUNTER 26"* ]] \
   && [[ "$OUT" == *"PROCEED defer-message-printed"* ]]; then
  pass "case 4: C=25 */30 → step down to */60 at boundary, counter=26"
else
  fail "case 4: step-down to */60 — got: $OUT"
fi

# Case 5: counter=30, cadence */60 → NEXT=31, NOT a boundary, target
# */60 (cap held). No REPLACE_CRON, silent advance.
setup_fixture
COUNTER_VALUE=30
CURRENT_CADENCE='*/60'
OUT=$(defer_backoff_step)
teardown_fixture
if [[ "$OUT" == *"WRITE_COUNTER 31"* ]] \
   && [[ "$OUT" != *"REPLACE_CRON"* ]] \
   && [[ "$OUT" == *"PROCEED defer-message-silent"* ]]; then
  pass "case 5: C=30 */60 → cap held, silent advance to 31"
else
  fail "case 5: cap-held silent advance — got: $OUT"
fi

# Case 6: CronList returned 0 matches → emit WARN no-cron-match,
# do NOT increment counter.
setup_fixture
COUNTER_VALUE=5
CRONLIST_MATCH_COUNT=0
OUT=$(defer_backoff_step)
teardown_fixture
if [[ "$OUT" == *"WARN no-cron-match"* ]] \
   && [[ "$OUT" != *"WRITE_COUNTER"* ]]; then
  pass "case 6: 0-match → WARN no-cron-match, counter held"
else
  fail "case 6: no-cron-match — got: $OUT"
fi

# Case 7: idempotent re-run after partial crash — counter=9, cadence
# already advanced to */10 by a previous turn that crashed before the
# counter write. NEXT=10 → target */10 == current */10, so no
# REPLACE_CRON; counter just advances to 10, defer printed.
setup_fixture
COUNTER_VALUE=9
CURRENT_CADENCE='*/10'
OUT=$(defer_backoff_step)
teardown_fixture
if [[ "$OUT" != *"REPLACE_CRON"* ]] \
   && [[ "$OUT" == *"WRITE_COUNTER 10"* ]] \
   && [[ "$OUT" == *"PROCEED defer-message-printed"* ]]; then
  pass "case 7: idempotent re-run T==R → no replace, counter catches up"
else
  fail "case 7: idempotent re-run — got: $OUT"
fi

# Case 8: Case 4 entry (Otherwise: new phase, normal preflight) — must
# emit DELETE_COUNTER (rms in-progress-defers.* AND cron-recovery-needed.*
# per #110 R6 fix).
setup_fixture
CASE=4
OUT=$(defer_backoff_step)
teardown_fixture
if [[ "$OUT" == *"DELETE_COUNTER"* ]]; then
  pass "case 8: Case 4 new-phase entry → DELETE_COUNTER"
else
  fail "case 8: Case 4 entry — got: $OUT"
fi

# Case 9 (NEW, high-severity race, retry exhaustion):
# counter=9, cadence */1, CRONCREATE_VERIFY_RESULT=missing-after-3-retries.
# Expect: DELETE_ALL_MATCHING_CRONS, WARN cron-replace-failed,
# WRITE_RECOVERY_MARKER 4, EMIT_USER_WARN cron-stalled, NO WRITE_COUNTER.
setup_fixture
COUNTER_VALUE=9
CURRENT_CADENCE='*/1'
CRONCREATE_VERIFY_RESULT=missing-after-3-retries
PHASE=4
OUT=$(defer_backoff_step)
teardown_fixture
if [[ "$OUT" == *"DELETE_ALL_MATCHING_CRONS"* ]] \
   && [[ "$OUT" == *"WARN cron-replace-failed"* ]] \
   && [[ "$OUT" == *"WRITE_RECOVERY_MARKER 4"* ]] \
   && [[ "$OUT" == *"EMIT_USER_WARN cron-stalled"* ]] \
   && [[ "$OUT" != *"WRITE_COUNTER"* ]]; then
  pass "case 9: 3-retry exhaustion → recovery marker + user WARN, counter held"
else
  fail "case 9: retry exhaustion — got: $OUT"
fi

# Case 10 (NEW, concurrency, multi-match): two crons with same prompt
# (duplicate CronCreate race), counter=9 → step down to */10. Expect
# DELETE_ALL_MATCHING_CRONS (both deleted, then ONE created at */10),
# REPLACE_CRON */10, WRITE_COUNTER 10.
setup_fixture
COUNTER_VALUE=9
CURRENT_CADENCE='*/1'
CRONLIST_MATCH_COUNT=2
CRONCREATE_VERIFY_RESULT=ok
OUT=$(defer_backoff_step)
teardown_fixture
if [[ "$OUT" == *"DELETE_ALL_MATCHING_CRONS"* ]] \
   && [[ "$OUT" == *"REPLACE_CRON */10"* ]] \
   && [[ "$OUT" == *"WRITE_COUNTER 10"* ]]; then
  pass "case 10: multi-match → delete-all collapses duplicates, single replace"
else
  fail "case 10: multi-match — got: $OUT"
fi

# Case 11 (NEW, prelude — marker, cron missing, prelude CronCreate ok).
# Expect PRELUDE_RECOVERY_ATTEMPTED + PRELUDE_RECOVERY_OK. (Normal
# dispatch then hits WARN no-cron-match because the test's static
# CRONLIST_MATCH_COUNT=0 doesn't reflect the prelude's new cron — fine;
# assertion is on the prelude lines.)
setup_fixture
RECOVERY_MARKER_PRESENT=yes
CRONLIST_MATCH_COUNT=0
CRONCREATE_VERIFY_RESULT=ok
COUNTER_VALUE=2
OUT=$(defer_backoff_step)
teardown_fixture
if [[ "$OUT" == *"PRELUDE_RECOVERY_ATTEMPTED"* ]] \
   && [[ "$OUT" == *"PRELUDE_RECOVERY_OK"* ]]; then
  pass "case 11: prelude marker + cron missing + create ok → ATTEMPTED + OK"
else
  fail "case 11: prelude success — got: $OUT"
fi

# Case 12 (NEW, prelude — marker, cron exists @ sane cadence, no-op).
# Expect ATTEMPTED + OK (marker rm'd), no REPLACE_CRON. (Normal dispatch
# at NEXT=4, T=*/1=R also emits no REPLACE_CRON, so the assertion is
# meaningful.)
setup_fixture
RECOVERY_MARKER_PRESENT=yes
CRONLIST_MATCH_COUNT=1
CURRENT_CADENCE='*/1'
COUNTER_VALUE=3
OUT=$(defer_backoff_step)
teardown_fixture
if [[ "$OUT" == *"PRELUDE_RECOVERY_ATTEMPTED"* ]] \
   && [[ "$OUT" == *"PRELUDE_RECOVERY_OK"* ]] \
   && [[ "$OUT" != *"REPLACE_CRON"* ]]; then
  pass "case 12: prelude marker + cron exists @sane → OK no-op, no replace"
else
  fail "case 12: prelude no-op — got: $OUT"
fi

# Case 13 (NEW, prelude — marker, cron missing, prelude CronCreate fails).
# Expect ATTEMPTED + FAILED (marker held). Falls through to normal
# dispatch (which here hits WARN no-cron-match and exits — fine; the
# assertion is on prelude lines).
setup_fixture
RECOVERY_MARKER_PRESENT=yes
CRONLIST_MATCH_COUNT=0
CRONCREATE_VERIFY_RESULT=missing
COUNTER_VALUE=2
OUT=$(defer_backoff_step)
teardown_fixture
if [[ "$OUT" == *"PRELUDE_RECOVERY_ATTEMPTED"* ]] \
   && [[ "$OUT" == *"PRELUDE_RECOVERY_FAILED"* ]]; then
  pass "case 13: prelude marker + cron missing + create fails → ATTEMPTED + FAILED"
else
  fail "case 13: prelude failure — got: $OUT"
fi

# Case 14 (NEW, A1 fix — prelude cadence-sanity rejects unknown cadence):
# RECOVERY_MARKER_PRESENT=yes, CRONLIST_MATCH_COUNT=1,
# CURRENT_CADENCE=*/15 (third-party cron at out-of-set cadence).
# Expect: PRELUDE_RECOVERY_ATTEMPTED,
#         WARN cron-recovery-bad-cadence */15,
#         DELETE_ALL_MATCHING_CRONS,
#         REPLACE_CRON */1,
#         PRELUDE_RECOVERY_OK.
setup_fixture
RECOVERY_MARKER_PRESENT=yes
CRONLIST_MATCH_COUNT=1
CURRENT_CADENCE='*/15'
COUNTER_VALUE=2
OUT=$(defer_backoff_step)
teardown_fixture
if [[ "$OUT" == *"PRELUDE_RECOVERY_ATTEMPTED"* ]] \
   && [[ "$OUT" == *"WARN cron-recovery-bad-cadence */15"* ]] \
   && [[ "$OUT" == *"DELETE_ALL_MATCHING_CRONS"* ]] \
   && [[ "$OUT" == *"REPLACE_CRON */1"* ]] \
   && [[ "$OUT" == *"PRELUDE_RECOVERY_OK"* ]]; then
  pass "case 14: prelude bad-cadence → WARN + delete-all + recreate at */1"
else
  fail "case 14: prelude bad-cadence — got: $OUT"
fi

# ---- Anchor-grep cases (lock the source-of-truth in place) -----------

# Anchor A: Phase 1's per-phase counter refs in SKILL.md (>= 5).
A_COUNT=$(grep -c -F 'in-progress-defers' "$REPO_ROOT/skills/run-plan/SKILL.md")
if [ "$A_COUNT" -ge 5 ]; then
  pass "anchor A: SKILL.md references 'in-progress-defers' ($A_COUNT >= 5)"
else
  fail "anchor A: SKILL.md 'in-progress-defers' count = $A_COUNT (< 5)"
fi

# Anchor B: Phase 2's backoff cadences in finish-mode.md (DA8: 3x grep -F,
# no BRE alternation).
B_COUNT_10=$(grep -c -F '*/10' "$REPO_ROOT/skills/run-plan/references/finish-mode.md")
B_COUNT_30=$(grep -c -F '*/30' "$REPO_ROOT/skills/run-plan/references/finish-mode.md")
B_COUNT_60=$(grep -c -F '*/60' "$REPO_ROOT/skills/run-plan/references/finish-mode.md")
if [ "$B_COUNT_10" -ge 1 ] && [ "$B_COUNT_30" -ge 1 ] && [ "$B_COUNT_60" -ge 1 ]; then
  pass "anchor B: finish-mode.md references */10 ($B_COUNT_10), */30 ($B_COUNT_30), */60 ($B_COUNT_60)"
else
  fail "anchor B: finish-mode.md cadence refs */10=$B_COUNT_10 */30=$B_COUNT_30 */60=$B_COUNT_60"
fi

echo ""
echo "---"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
