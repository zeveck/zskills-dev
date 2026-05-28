#!/bin/bash
# Behavioral smoke for /add-example's deterministic tracking surface
# (block-diagram/add-example/SKILL.md, the "Fulfillment Tracking" fence
# ≈ SKILL.md:69-90).
#
# Covers:
#   1. 3-tier PIPELINE_ID resolution: tier-1 $ZSKILLS_PIPELINE_ID env,
#      tier-2 `.zskills-tracked` file, tier-3 `add-example.${NAME}` fallback.
#   2. fulfilled-marker write: assert the marker lands at
#      $MAIN_ROOT/.zskills/tracking/<pid>/fulfilled.add-example.<slug>
#      with the ACTUAL fields the printf writes: `skill:`, `name:` (NOT
#      `id:`), `status:`, `date:`.
#
# The fence sources zskills-resolve-config.sh + calls
# sanitize-pipeline-id.sh, so we EMBED a faithful copy (config source
# replaced by direct env, sanitizer resolved via the install lane) AND add a
# `grep -qF` PARITY gate on the fingerprint lines so source drift fails.
#
# Fixtures in mktemp -d; no network; no real gh.
#
# Run from repo root: bash tests/test-add-example-smoke.sh

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/block-diagram/add-example/SKILL.md"
SANITIZER="$REPO_ROOT/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh"
PASS_COUNT=0; FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

echo "=== add-example behavioral smoke ==="

# ── Parity gate on the fulfillment fence fingerprints ───────────────
if grep -qF 'PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-}"' "$SKILL" \
   && grep -qF 'if [ -z "$PIPELINE_ID" ] && [ -f ".zskills-tracked" ]; then' "$SKILL" \
   && grep -qF ': "${PIPELINE_ID:=add-example.${NAME}}"' "$SKILL"; then
  pass "parity: 3-tier PIPELINE_ID resolution fingerprints present"
else
  fail "parity: 3-tier resolution drifted" "tier fingerprints mismatch"
fi
# The marker printf fields are `skill:`, `name:` (NOT id:), `status:`, `date:`.
if grep -qF "printf 'skill: add-example\nname: %s\nstatus: started\ndate: %s\n'" "$SKILL"; then
  pass "parity: fulfilled-marker printf uses skill:/name:/status:/date: (not id:)"
else
  fail "parity: fulfilled-marker printf drifted" "field set changed"
fi
if grep -qF 'fulfilled.add-example.${NAME_SLUG}' "$SKILL"; then
  pass "parity: marker basename is fulfilled.add-example.\${NAME_SLUG}"
else
  fail "parity: marker basename drifted" "basename fingerprint mismatch"
fi

# ── Behavioral: embedded faithful copy of the fulfillment fence ─────
# tier_env / tracked_file simulate the resolution inputs; the rest mirrors
# the SKILL.md fence exactly (sanitizer resolved via the real install-lane
# script, marker written with the same printf field set).
run_fulfillment() { # $1=NAME  $2=ZSKILLS_PIPELINE_ID(or empty)  $3=tracked-content(or empty)  $4=MAIN_ROOT
  local NAME="$1" ZSKILLS_PIPELINE_ID="$2" TRACKED="$3" MAIN_ROOT="$4"
  ( # subshell so cd doesn't leak; .zskills-tracked is read from cwd
    cd "$MAIN_ROOT" || exit 1
    if [ -n "$TRACKED" ]; then printf '%s\n' "$TRACKED" > .zskills-tracked; fi
    local PIPELINE_ID NAME_SLUG
    PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-}"
    if [ -z "$PIPELINE_ID" ] && [ -f ".zskills-tracked" ]; then
      PIPELINE_ID=$(tr -d '[:space:]' < ".zskills-tracked")
    fi
    : "${PIPELINE_ID:=add-example.${NAME}}"
    PIPELINE_ID=$(bash "$SANITIZER" "$PIPELINE_ID")
    NAME_SLUG=$(bash "$SANITIZER" "$NAME")
    mkdir -p "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
    printf 'skill: add-example\nname: %s\nstatus: started\ndate: %s\n' \
      "$NAME" "2026-05-28T00:00:00+00:00" \
      > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/fulfilled.add-example.${NAME_SLUG}"
    echo "PIPELINE_ID=$PIPELINE_ID"
    echo "NAME_SLUG=$NAME_SLUG"
  )
}

# Tier 1: env wins over .zskills-tracked and fallback.
TMP1=$(mktemp -d); trap 'rm -rf "$TMP1" "$TMP2" "$TMP3"' EXIT
git -C "$TMP1" init -q
R=$(run_fulfillment "Gain" "env-pipeline.123" "tracked-pipeline.999" "$TMP1")
PID=$(echo "$R" | sed -n 's/^PIPELINE_ID=//p')
if [ "$PID" = "env-pipeline.123" ]; then
  pass "tier-1: \$ZSKILLS_PIPELINE_ID env wins"
else
  fail "tier-1: env did not win" "PIPELINE_ID=$PID"
fi

# Tier 2: .zskills-tracked wins when env empty.
TMP2=$(mktemp -d); git -C "$TMP2" init -q
R=$(run_fulfillment "Gain" "" "tracked-pipeline.999" "$TMP2")
PID=$(echo "$R" | sed -n 's/^PIPELINE_ID=//p')
if [ "$PID" = "tracked-pipeline.999" ]; then
  pass "tier-2: .zskills-tracked file wins when env empty"
else
  fail "tier-2: tracked file did not win" "PIPELINE_ID=$PID"
fi

# Tier 3: synthesized add-example.<NAME> fallback when env+file absent.
TMP3=$(mktemp -d); git -C "$TMP3" init -q
R=$(run_fulfillment "math-batch" "" "" "$TMP3")
PID=$(echo "$R" | sed -n 's/^PIPELINE_ID=//p')
NSLUG=$(echo "$R" | sed -n 's/^NAME_SLUG=//p')
if [ "$PID" = "add-example.math-batch" ]; then
  pass "tier-3: synthesized add-example.<NAME> fallback"
else
  fail "tier-3: fallback wrong" "PIPELINE_ID=$PID"
fi

# Marker assertions (use the tier-3 run's marker).
MARKER="$TMP3/.zskills/tracking/$PID/fulfilled.add-example.$NSLUG"
if [ -f "$MARKER" ]; then
  pass "marker: fulfilled.add-example.<slug> written under \$MAIN_ROOT/.zskills/tracking/<pid>/"
else
  fail "marker: file not written" "expected $MARKER"
fi
if grep -qx 'skill: add-example' "$MARKER" 2>/dev/null; then
  pass "marker: has 'skill: add-example' field"
else
  fail "marker: missing skill: field" "$(cat "$MARKER" 2>/dev/null)"
fi
if grep -qx 'name: math-batch' "$MARKER" 2>/dev/null; then
  pass "marker: has 'name:' field (NOT 'id:')"
else
  fail "marker: missing name: field" "$(cat "$MARKER" 2>/dev/null)"
fi
if ! grep -qE '^id:' "$MARKER" 2>/dev/null; then
  pass "marker: does NOT use 'id:' field"
else
  fail "marker: unexpected id: field present" "$(cat "$MARKER" 2>/dev/null)"
fi
if grep -qx 'status: started' "$MARKER" 2>/dev/null; then
  pass "marker: has 'status:' field"
else
  fail "marker: missing status: field" "$(cat "$MARKER" 2>/dev/null)"
fi
if grep -qE '^date: ' "$MARKER" 2>/dev/null; then
  pass "marker: has 'date:' field"
else
  fail "marker: missing date: field" "$(cat "$MARKER" 2>/dev/null)"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] && exit 0 || exit 1
