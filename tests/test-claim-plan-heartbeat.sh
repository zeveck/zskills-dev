#!/bin/bash
# tests/test-claim-plan-heartbeat.sh — Issue #1029.
#
# Plan-claim staleness now keys on `last_progress_at` (heartbeat) instead
# of `started_at` (acquire age). This file pins:
#   1. acquire writes claim.json with last_progress_at == started_at.
#   2. set-phase bumps last_progress_at to a strictly-later ISO timestamp.
#   3. The collector's `_read_plan_claims` returns stale=False when
#      last_progress_at is fresh even if started_at is >6h old.
#   4. Backward-compat: claims missing last_progress_at fall back to
#      started_at; old-shape with old started_at → stale; old-shape with
#      fresh started_at → not stale.
#   5. Both-fields-missing → not stale (fail-toward-not-stale).
#
# Path: /tmp/zskills-tests/$(basename $(pwd))/.test-results.txt capture
# is handled by run-all.sh — this script just emits pass/fail lines.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAIM_SH="$REPO_ROOT/skills/run-plan/scripts/claim-plan.sh"
COLLECT_PY="$REPO_ROOT/skills/zskills-dashboard/scripts/zskills_monitor/collect.py"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
if [ -z "$PYTHON" ]; then
  echo "FATAL: no Python interpreter available" >&2
  exit 1
fi

SCRATCH_ROOT="/tmp/test-claim-plan-heartbeat-$$"
cleanup() {
  if [ -n "${TEST_KEEP_SCRATCH:-}" ]; then
    echo "TEST_KEEP_SCRATCH set — leaving $SCRATCH_ROOT" >&2
    return
  fi
  if [ -d "$SCRATCH_ROOT" ]; then
    find "$SCRATCH_ROOT" -type d -exec chmod 0755 {} + 2>/dev/null || true
    find "$SCRATCH_ROOT" -mindepth 1 -delete 2>/dev/null || true
    rmdir "$SCRATCH_ROOT" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM
mkdir -p "$SCRATCH_ROOT"

make_repo() {
  local repo="$1"
  mkdir -p "$repo"
  (cd "$repo" && git init -q && git config user.email "t@t" && git config user.name "t" \
    && git commit --allow-empty -q -m "init") || return 1
}

# Sanitizer + self-reentry helper lookup: claim-plan.sh resolves them
# via CLAUDE_PROJECT_DIR fallback when not bundled into a sibling layout.
export CLAUDE_PROJECT_DIR="$REPO_ROOT"

echo "=== claim-plan.sh heartbeat (#1029) tests ==="

# ---------------------------------------------------------------------
# 1. acquire writes last_progress_at == started_at (same instant).
# ---------------------------------------------------------------------
REPO1="$SCRATCH_ROOT/r1"
make_repo "$REPO1" || { echo "FATAL repo init"; exit 1; }
(
  cd "$REPO1"
  bash "$CLAIM_SH" acquire heartbeat-acquire --pipeline-id "run-plan.heartbeat-acquire"
) >/dev/null
rc=$?
CLAIM1="$REPO1/.zskills/claims/plan-heartbeat-acquire/claim.json"
if [ "$rc" -ne 0 ]; then
  fail "acquire heartbeat-acquire exit 0" "rc=$rc"
elif [ ! -f "$CLAIM1" ]; then
  fail "acquire heartbeat-acquire claim.json exists" "missing $CLAIM1"
else
  STARTED=$("$PYTHON" -c "import json; print(json.load(open('$CLAIM1'))['started_at'])")
  PROGRESS=$("$PYTHON" -c "import json; print(json.load(open('$CLAIM1')).get('last_progress_at','<absent>'))")
  if [ "$PROGRESS" = "$STARTED" ] && [ -n "$PROGRESS" ] && [ "$PROGRESS" != "<absent>" ]; then
    pass "acquire writes last_progress_at == started_at (#1029)"
  else
    fail "acquire last_progress_at == started_at" "started=$STARTED progress=$PROGRESS"
  fi
fi

# ---------------------------------------------------------------------
# 2. set-phase bumps last_progress_at to a strictly-later ISO timestamp.
# ---------------------------------------------------------------------
sleep 1
(
  cd "$REPO1"
  bash "$CLAIM_SH" set-phase heartbeat-acquire \
    --require-pipeline "run-plan.heartbeat-acquire" \
    --current-phase "Phase 2 — implement"
) >/dev/null
rc=$?
NEW_PROGRESS=$("$PYTHON" -c "import json; print(json.load(open('$CLAIM1')).get('last_progress_at','<absent>'))")
NEW_STARTED=$("$PYTHON" -c "import json; print(json.load(open('$CLAIM1'))['started_at'])")

# Compare with Python to avoid bash-side ISO arithmetic.
COMPARE=$("$PYTHON" -c "
import datetime
s = datetime.datetime.fromisoformat('$STARTED')
p = datetime.datetime.fromisoformat('$NEW_PROGRESS')
print('later' if p > s else ('same' if p == s else 'earlier'))
")

if [ "$rc" -eq 0 ] && [ "$COMPARE" = "later" ]; then
  pass "set-phase bumps last_progress_at to a strictly-later timestamp (#1029)"
else
  fail "set-phase bumps last_progress_at" "rc=$rc compare=$COMPARE started=$STARTED new_progress=$NEW_PROGRESS"
fi

# Verify started_at was NOT touched (only last_progress_at moved).
if [ "$NEW_STARTED" = "$STARTED" ]; then
  pass "set-phase preserves started_at (only last_progress_at moves)"
else
  fail "set-phase preserves started_at" "before=$STARTED after=$NEW_STARTED"
fi

# ---------------------------------------------------------------------
# 3. Collector staleness: fresh last_progress_at + old started_at → NOT stale.
# ---------------------------------------------------------------------
REPO2="$SCRATCH_ROOT/r2"
make_repo "$REPO2" || { echo "FATAL repo init r2"; exit 1; }
mkdir -p "$REPO2/.zskills/claims/plan-longrun"
FRESH_PROGRESS=$("$PYTHON" -c "
import datetime
now = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=5)
print(now.isoformat(timespec='seconds'))
")
OLD_STARTED=$("$PYTHON" -c "
import datetime
old = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=10)
print(old.isoformat(timespec='seconds'))
")
cat > "$REPO2/.zskills/claims/plan-longrun/claim.json" <<EOF
{"current_phase":"Phase 3","kind":"plan","last_progress_at":"$FRESH_PROGRESS","pipeline_id":"run-plan.longrun","schema_version":1,"slug":"longrun","started_at":"$OLD_STARTED"}
EOF

STALE_OUT=$(cd "$REPO2" && "$PYTHON" -c "
import sys, pathlib, json
sys.path.insert(0, '$REPO_ROOT/skills/zskills-dashboard/scripts')
from zskills_monitor import collect
out = collect._read_plan_claims(pathlib.Path('$REPO2'))
c = out['longrun']
print('stale={} last_progress_at={} started_at={} age_seconds={}'.format(
    c.get('stale'), c.get('last_progress_at'), c.get('started_at'),
    c.get('age_seconds')))
")

case "$STALE_OUT" in
  *stale=False*)
    pass "collector: fresh last_progress_at + old started_at → not stale (#1029)"
    ;;
  *)
    fail "collector longrun not-stale" "got: $STALE_OUT"
    ;;
esac

# ---------------------------------------------------------------------
# 4. Collector staleness: both fields old → stale.
# ---------------------------------------------------------------------
mkdir -p "$REPO2/.zskills/claims/plan-bothold"
OLD_PROGRESS=$("$PYTHON" -c "
import datetime
old = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=8)
print(old.isoformat(timespec='seconds'))
")
cat > "$REPO2/.zskills/claims/plan-bothold/claim.json" <<EOF
{"current_phase":"Phase 1","kind":"plan","last_progress_at":"$OLD_PROGRESS","pipeline_id":"run-plan.bothold","schema_version":1,"slug":"bothold","started_at":"$OLD_STARTED"}
EOF
BOTHOLD_OUT=$(cd "$REPO2" && "$PYTHON" -c "
import sys, pathlib
sys.path.insert(0, '$REPO_ROOT/skills/zskills-dashboard/scripts')
from zskills_monitor import collect
print(collect._read_plan_claims(pathlib.Path('$REPO2'))['bothold']['stale'])
")
if [ "$BOTHOLD_OUT" = "True" ]; then
  pass "collector: both-old fields → stale=True (dead-pipeline case still caught)"
else
  fail "collector bothold stale" "got: $BOTHOLD_OUT"
fi

# ---------------------------------------------------------------------
# 5. Back-compat: claim.json with only started_at (no last_progress_at).
#    Old started_at >6h → stale.
# ---------------------------------------------------------------------
mkdir -p "$REPO2/.zskills/claims/plan-precompatold"
cat > "$REPO2/.zskills/claims/plan-precompatold/claim.json" <<EOF
{"current_phase":"Phase 2","kind":"plan","pipeline_id":"run-plan.precompatold","schema_version":1,"slug":"precompatold","started_at":"$OLD_STARTED"}
EOF
PRECOMPAT_OUT=$(cd "$REPO2" && "$PYTHON" -c "
import sys, pathlib
sys.path.insert(0, '$REPO_ROOT/skills/zskills-dashboard/scripts')
from zskills_monitor import collect
c = collect._read_plan_claims(pathlib.Path('$REPO2'))['precompatold']
print('stale={} last_progress_at={}'.format(c.get('stale'), c.get('last_progress_at')))
")
case "$PRECOMPAT_OUT" in
  *stale=True*last_progress_at=None*)
    pass "back-compat: pre-#1029 claim with old started_at → stale (fallback works)"
    ;;
  *)
    fail "back-compat pre-#1029 old started_at" "got: $PRECOMPAT_OUT"
    ;;
esac

# ---------------------------------------------------------------------
# 6. Back-compat: claim.json with only fresh started_at (no last_progress_at)
#    → not stale.
# ---------------------------------------------------------------------
mkdir -p "$REPO2/.zskills/claims/plan-precompatfresh"
FRESH_STARTED=$("$PYTHON" -c "
import datetime
now = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=30)
print(now.isoformat(timespec='seconds'))
")
cat > "$REPO2/.zskills/claims/plan-precompatfresh/claim.json" <<EOF
{"current_phase":"Phase 1","kind":"plan","pipeline_id":"run-plan.precompatfresh","schema_version":1,"slug":"precompatfresh","started_at":"$FRESH_STARTED"}
EOF
PCF_OUT=$(cd "$REPO2" && "$PYTHON" -c "
import sys, pathlib
sys.path.insert(0, '$REPO_ROOT/skills/zskills-dashboard/scripts')
from zskills_monitor import collect
print(collect._read_plan_claims(pathlib.Path('$REPO2'))['precompatfresh']['stale'])
")
if [ "$PCF_OUT" = "False" ]; then
  pass "back-compat: pre-#1029 claim with fresh started_at → not stale"
else
  fail "back-compat pre-#1029 fresh started_at" "got: $PCF_OUT"
fi

# ---------------------------------------------------------------------
# 7. Both fields missing → not stale (fail-toward-not-stale).
# ---------------------------------------------------------------------
mkdir -p "$REPO2/.zskills/claims/plan-bothmiss"
cat > "$REPO2/.zskills/claims/plan-bothmiss/claim.json" <<EOF
{"current_phase":"Phase 1","kind":"plan","pipeline_id":"run-plan.bothmiss","schema_version":1,"slug":"bothmiss"}
EOF
BM_OUT=$(cd "$REPO2" && "$PYTHON" -c "
import sys, pathlib
sys.path.insert(0, '$REPO_ROOT/skills/zskills-dashboard/scripts')
from zskills_monitor import collect
c = collect._read_plan_claims(pathlib.Path('$REPO2'))['bothmiss']
print('stale={} last_progress_at={} started_at={}'.format(
    c.get('stale'), c.get('last_progress_at'), c.get('started_at')))
")
case "$BM_OUT" in
  *stale=False*)
    pass "fail-toward-not-stale: both fields missing → not stale (no false-positive)"
    ;;
  *)
    fail "fail-toward-not-stale both fields missing" "got: $BM_OUT"
    ;;
esac

# ---------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------
echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (%d total)\033[0m\n' "$PASS_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (%d total)\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit 1
fi
