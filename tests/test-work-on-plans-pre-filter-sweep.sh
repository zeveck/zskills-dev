#!/bin/bash
# test-work-on-plans-pre-filter-sweep.sh — AC2b.5 (R2.6).
#
# Step 4 must invoke `claim-plan.sh sweep` BEFORE the selection filter
# runs so a crashed-pipeline stale claim doesn't permanently block a
# slug. Two checks:
#
#   1. Source-level ordering — in skills/work-on-plans/SKILL.md, the
#      first occurrence of `claim-plan.sh sweep` appears BEFORE the first
#      occurrence of `filter-in-flight-plan-claims.sh`. Section bound:
#      both occur inside Step 4's window (between `## Step 4` and the
#      next `## ` header).
#
#   2. Behavioural — pre-create a stale claim (last_heartbeat_at = NOW
#      - 2×TTL), run sweep + filter in sequence against READY_LINES=[foo],
#      assert: (a) the stale claim dir is reaped after sweep, (b) `foo`
#      survives the filter (NOT dropped — there is no live claim).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_MD="$REPO_ROOT/skills/work-on-plans/SKILL.md"
FILTER="$REPO_ROOT/skills/work-on-plans/scripts/filter-in-flight-plan-claims.sh"
CLAIM_SH="$REPO_ROOT/skills/run-plan/scripts/claim-plan.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SCRATCH="/tmp/test-work-on-plans-pre-filter-sweep-$$"
cleanup() {
  [ -n "${TEST_KEEP_SCRATCH:-}" ] && return
  [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
}
trap cleanup EXIT INT TERM
mkdir -p "$SCRATCH"

echo "=== work-on-plans pre-filter sweep (AC2b.5 / R2.6) ==="

# ---------------------------------------------------------------------
# Part 1: source-level sweep-BEFORE-filter ordering inside Step 4.
# ---------------------------------------------------------------------
# Extract the Step 4 section (header to next ## header).
STEP4_BLOCK=$(awk '
  /^## Step 4 / { p = 1 }
  p { print }
  p && NR > 1 && /^## / && !/^## Step 4/ {
    # Already printed this line above; stop after.
    exit
  }
' "$SKILL_MD")

# Find line numbers within the Step 4 block.
# The sweep fence assigns SWEEP="...claim-plan.sh" then invokes
# `bash "$SWEEP" sweep` on a separate line; anchor on that bash-sweep
# invocation, which is the load-bearing call. Also accept the section
# header so a stylistic refactor (e.g., one-liner) still passes.
SWEEP_LN=$(echo "$STEP4_BLOCK" | grep -nE 'bash[[:space:]]+"\$SWEEP"[[:space:]]+sweep|Pre-filter sweep' | head -1 | cut -d: -f1)
FILT_LN=$(echo "$STEP4_BLOCK" | grep -nF 'filter-in-flight-plan-claims.sh' | head -1 | cut -d: -f1)

if [ -n "$SWEEP_LN" ] && [ -n "$FILT_LN" ]; then
  pass "Step 4 references both claim-plan.sh sweep AND filter-in-flight-plan-claims.sh"
else
  fail "Step 4 contains sweep + filter references" \
       "sweep_ln='$SWEEP_LN' filter_ln='$FILT_LN'"
fi

if [ -n "$SWEEP_LN" ] && [ -n "$FILT_LN" ] && [ "$SWEEP_LN" -lt "$FILT_LN" ]; then
  pass "Step 4 ordering: sweep fence appears BEFORE filter fence (R2.6)"
else
  fail "Step 4 sweep-before-filter ordering" \
       "sweep_ln=$SWEEP_LN filter_ln=$FILT_LN (sweep must precede filter)"
fi

# ---------------------------------------------------------------------
# Part 2: behavioural — stale claim is reaped by sweep, foo survives filter.
# ---------------------------------------------------------------------
FIXTURE="$SCRATCH/fixture"
mkdir -p "$FIXTURE"
(
  cd "$FIXTURE"
  git init -q
  git config user.email "t@t"
  git config user.name "t"
  git commit --allow-empty -q -m "init"
) >/dev/null 2>&1

# Acquire a real claim for plan-foo.
(
  cd "$FIXTURE"
  bash "$CLAIM_SH" acquire foo --pipeline-id "run-plan.foo.stale"
) >/dev/null 2>&1
if [ ! -f "$FIXTURE/.zskills/claims/plan-foo/claim.json" ]; then
  fail "acquire stale claim" "claim.json not created"
  echo "Results: $PASS_COUNT passed, $((FAIL_COUNT + 1)) failed"
  exit 1
fi
pass "acquired plan-foo claim (will be aged into stale state)"

# Age the claim to past 2×TTL. Built-in TTL is 7200s; set
# last_heartbeat_at to NOW - 14400s + a margin so it's solidly stale.
# Use Python to rewrite claim.json with a heartbeat far in the past.
python3 - "$FIXTURE/.zskills/claims/plan-foo/claim.json" <<'PY'
import json, sys, datetime
p = sys.argv[1]
with open(p) as f:
    body = json.load(f)
# 2 × default TTL (7200s) = 14400s; pad with another 60s to be safe.
old = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=14460)
body["last_heartbeat_at"] = old.isoformat(timespec="seconds")
body["started_at"] = old.isoformat(timespec="seconds")
with open(p, "w") as f:
    json.dump(body, f, sort_keys=True)
    f.write("\n")
PY

# Confirm is-stale agrees (sanity check on the fixture).
(
  cd "$FIXTURE"
  bash "$CLAIM_SH" is-stale foo
) >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "claim-plan.sh is-stale agrees: plan-foo is stale"
else
  fail "is-stale agreement" "expected rc=0 (stale), got rc=$rc"
fi

# Step 4 sequence: sweep THEN filter.
(
  cd "$FIXTURE"
  bash "$CLAIM_SH" sweep
) >/dev/null 2>"$SCRATCH/sweep.stderr"

# Assertion: stale claim dir is gone after sweep.
if [ ! -d "$FIXTURE/.zskills/claims/plan-foo" ]; then
  pass "sweep reaped stale plan-foo claim dir"
else
  fail "sweep reaped stale claim" "$FIXTURE/.zskills/claims/plan-foo still exists"
fi

# Run filter against READY_LINES=[foo]. After sweep there is no live
# claim, so foo MUST be preserved (not dropped).
STDOUT="$SCRATCH/filter.stdout"
STDERR="$SCRATCH/filter.stderr"
(
  cd "$FIXTURE"
  printf 'foo\n' | bash "$FILTER"
) >"$STDOUT" 2>"$STDERR"
rc=$?

if [ "$rc" -eq 0 ] && grep -qE '^foo$' "$STDOUT"; then
  pass "after sweep, filter preserves foo (no live claim — stale was reaped)"
else
  fail "filter preserves foo after sweep" \
       "rc=$rc stdout=$(cat "$STDOUT") stderr=$(cat "$STDERR")"
fi

echo ""
echo "---"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
[ "$FAIL_COUNT" -eq 0 ]
