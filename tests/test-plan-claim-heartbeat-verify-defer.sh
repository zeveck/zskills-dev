#!/bin/bash
# tests/test-plan-claim-heartbeat-verify-defer.sh — Phase 2a W2a.14 / AC2a.4 site R.
#
# Final-verify defer scenario: at the cron-defer site (Phase 5b §0b
# branch-1 "Marker exists AND fulfilled missing"), the heartbeat refresh
# (NOT release) keeps the claim alive during the defer window so sweep
# does not reap it mid-defer.
#
# Assertions:
#   (1) SKILL.md conformance: §0b contains exactly one claim-plan.sh
#       refresh call (NOT release).
#   (2) The refresh appears IMMEDIATELY BEFORE the "Then exit this turn"
#       line.
#   (3) The refresh's --current-phase references the defer state
#       ("Final-verify defer (attempt $ATTEMPT, backoff ${BACKOFF_MIN}m)").
#   (4) End-to-end: acquire claim, simulate a defer-refresh, advance
#       claim's last_heartbeat_at; then with a long TTL synthesise a
#       sweep at NOW-TTL+1s after refresh and assert the refreshed
#       claim is NOT swept.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_MD="$REPO_ROOT/skills/run-plan/SKILL.md"
CLAIM_SH="$REPO_ROOT/skills/run-plan/scripts/claim-plan.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SCRATCH_ROOT="/tmp/test-plan-claim-defer-$$"
cleanup() {
  if [ -n "${TEST_KEEP_SCRATCH:-}" ]; then return; fi
  if [ -d "$SCRATCH_ROOT" ]; then
    find "$SCRATCH_ROOT" -mindepth 1 -delete 2>/dev/null || true
    rmdir "$SCRATCH_ROOT" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM
mkdir -p "$SCRATCH_ROOT"

export CLAUDE_PROJECT_DIR="$REPO_ROOT"

echo "=== plan-claim refresh at §0b Final-verify gate cron-defer (site R) ==="

# ─────────────────────────────────────────────────────────────────────
# Part 1: SKILL.md conformance
# ─────────────────────────────────────────────────────────────────────
section_0b=$(awk '
  /^### 0b\. Final-verify gate$/ { p = 1; next }
  p && /^(### |## )/ { p = 0 }
  p { print }
' "$SKILL_MD")

# (1) Exactly one refresh in §0b
refresh_count=$(printf '%s\n' "$section_0b" | grep -cE '^[[:space:]]*refresh "\$PLAN_SLUG"' || true)
if [ "$refresh_count" = "1" ]; then
  pass "§0b contains exactly one claim-plan.sh refresh call"
else
  fail "§0b refresh count" "expected 1, got $refresh_count"
fi

# Must NOT contain a release (release would be wrong here — plan is in flight)
release_count=$(printf '%s\n' "$section_0b" | grep -cE '^[[:space:]]*release "\$PLAN_SLUG"' || true)
if [ "$release_count" = "0" ]; then
  pass "§0b contains NO claim-plan.sh release (defer refreshes, never releases)"
else
  fail "§0b release present" "found $release_count release calls; defer must refresh, not release"
fi

# (2) refresh appears BEFORE the `# Then exit this turn.` line
exit_line=$(grep -n 'Then exit this turn' "$SKILL_MD" | head -1 | cut -d: -f1)
refresh_line=$(grep -nE '^[[:space:]]*refresh "\$PLAN_SLUG"' "$SKILL_MD" | while IFS= read -r line; do
  ln=${line%%:*}
  hdr=$(awk -v n="$ln" 'NR<=n && /^(### |## )/ { last=$0 } END { print last }' "$SKILL_MD")
  if [ "$hdr" = "### 0b. Final-verify gate" ]; then echo "$ln"; fi
done | head -1)
if [ -n "$refresh_line" ] && [ -n "$exit_line" ] && [ "$refresh_line" -lt "$exit_line" ]; then
  pass "§0b refresh (line $refresh_line) appears before 'Then exit this turn' (line $exit_line)"
else
  fail "§0b refresh ordering" "refresh_line=$refresh_line exit_line=$exit_line"
fi

# (3) --current-phase references defer state
if printf '%s\n' "$section_0b" | grep -q -- '--current-phase "Final-verify defer'; then
  pass "§0b refresh --current-phase names defer state"
else
  fail "§0b --current-phase" "expected 'Final-verify defer (attempt ...)' phase string"
fi

# ─────────────────────────────────────────────────────────────────────
# Part 2: end-to-end defer-refresh keeps claim alive vs TTL-sweep
# ─────────────────────────────────────────────────────────────────────
FIXTURE="$SCRATCH_ROOT/fixture"
mkdir -p "$FIXTURE"
( cd "$FIXTURE" && git init -q && git config user.email "t@t" && git config user.name "t" \
  && git commit --allow-empty -q -m "init" ) \
  || { echo "FATAL: fixture init failed" >&2; exit 1; }

PLAN_SLUG="defer-refresh"
PIPELINE="run-plan.$PLAN_SLUG"

# Acquire claim.
( cd "$FIXTURE" && bash "$CLAIM_SH" acquire "$PLAN_SLUG" --pipeline-id "$PIPELINE" >/dev/null 2>&1 ) \
  || { fail "fixture acquire" "could not acquire"; exit 1; }

claim_file="$FIXTURE/.zskills/claims/plan-$PLAN_SLUG/claim.json"
hb_before=$(python3 -c "
import json, sys
print(json.load(open(sys.argv[1])).get('last_heartbeat_at',''))
" "$claim_file")

# Backdate claim's heartbeat to "stale" — half a TTL ago at TTL=120.
export ZSKILLS_PLAN_CLAIM_TTL_SECONDS=120
python3 -c "
import json, sys, datetime
p = sys.argv[1]
with open(p) as f: body = json.load(f)
old = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=60)
body['last_heartbeat_at'] = old.isoformat(timespec='seconds')
with open(p, 'w') as f: json.dump(body, f, sort_keys=True)
" "$claim_file"

# Sleep a moment so the resulting refresh is strictly later than the
# backdated value.
sleep 1

# Run the defer refresh (verbatim from §0b).
( cd "$FIXTURE" && bash "$CLAIM_SH" refresh "$PLAN_SLUG" \
    --require-pipeline "$PIPELINE" \
    --current-phase "Final-verify defer (attempt 1, backoff 10m)" >/dev/null 2>&1 ) \
  || { fail "defer-refresh" "refresh returned non-zero"; exit 1; }

hb_after=$(python3 -c "
import json, sys
print(json.load(open(sys.argv[1])).get('last_heartbeat_at',''))
" "$claim_file")
current_phase_after=$(python3 -c "
import json, sys
print(json.load(open(sys.argv[1])).get('current_phase',''))
" "$claim_file")

if [ "$hb_after" != "$hb_before" ]; then
  pass "defer-refresh advances last_heartbeat_at"
else
  fail "defer-refresh heartbeat" "before=$hb_before after=$hb_after (unchanged)"
fi
case "$current_phase_after" in
  "Final-verify defer (attempt 1, backoff 10m)")
    pass "defer-refresh records current_phase verbatim"
    ;;
  *)
    fail "defer-refresh current_phase" "got '$current_phase_after'"
    ;;
esac

# Now run sweep with TTL=120; the just-refreshed claim must NOT be swept.
( cd "$FIXTURE" && bash "$CLAIM_SH" sweep >/dev/null 2>&1 ) || true
if [ -d "$FIXTURE/.zskills/claims/plan-$PLAN_SLUG" ]; then
  pass "sweep at TTL-near-boundary does NOT reap freshly-refreshed claim"
else
  fail "sweep vs refresh" "claim was swept despite recent refresh"
fi

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (%d total)\033[0m\n' "$PASS_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (%d total)\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit 1
fi
