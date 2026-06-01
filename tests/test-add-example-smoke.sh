#!/bin/bash
# Behavioral smoke for /add-example's deterministic tracking surface
# (block-diagram/add-example/SKILL.md, the "PIPELINE_ID / NAME_SLUG +
# fulfilled-marker" fence ≈ SKILL.md:74-100).
#
# Covers:
#   1. 3-tier PIPELINE_ID resolution: tier-1 $ZSKILLS_PIPELINE_ID env,
#      tier-2 `.zskills-tracked` file, tier-3 `add-example.${NAME}` fallback.
#   2. fulfilled-marker write: assert the marker lands at
#      $MAIN_ROOT/.zskills/tracking/<pid>/fulfilled.add-example.<slug>
#      with the ACTUAL fields the printf writes: `skill:`, `name:` (NOT
#      `id:`), `status:`, `date:`.
#
# EXTRACT-AND-RUN: this suite extract_fence_between's the REAL production
# fence out of block-diagram/add-example/SKILL.md and EXECUTES it (no
# embedded copy that can drift). The fence sources zskills-resolve-config.sh
# (sets $ZSKILLS_SKILLS_ROOT + $TIMEZONE, reaches the real
# sanitize-pipeline-id.sh) and derives $MAIN_ROOT from git-common-dir, so we
# run it with CLAUDE_PROJECT_DIR pinned at the real repo (config + sanitizer
# resolution) while cwd is a throwaway git sandbox (markers land in-sandbox).
#
# Fixtures in mktemp -d; no network; no real gh.
#
# Run from repo root: bash tests/test-add-example-smoke.sh

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/block-diagram/add-example/SKILL.md"
# shellcheck source=tests/lib/extract-fence.sh
. "$SCRIPT_DIR/lib/extract-fence.sh"
PASS_COUNT=0; FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

echo "=== add-example behavioral smoke (extract-and-run) ==="

# ── Extract the REAL fulfillment fence ──────────────────────────────
# Bracket on the prose "On entry, resolve `PIPELINE_ID`" intro and the
# post-fence "Where `$NAME` is derived" sentence so exactly one ```bash
# block (the fulfillment fence) extracts.
FENCE="$(extract_fence_between "$SKILL" \
  'On entry, resolve' \
  'Where ..NAME.. is derived' 1 0)" || {
  echo "could not extract add-example fulfillment fence" >&2
  echo "Results: 0 passed, 1 failed"; exit 1
}
if printf '%s\n' "$FENCE" | grep -qF ': "${PIPELINE_ID:=add-example.${NAME}}"' \
   && printf '%s\n' "$FENCE" | grep -qF "printf 'skill: add-example\nname: %s\nstatus: started\ndate: %s\n'" \
   && printf '%s\n' "$FENCE" | grep -qF 'fulfilled.add-example.${NAME_SLUG}'; then
  pass "extract: real fence carries 3-tier resolution + fulfilled-marker printf"
else
  fail "extract: fence missing load-bearing lines" "extraction drifted"
fi

# run_fulfillment — write inputs, then EXECUTE the extracted production fence.
# $1=NAME  $2=ZSKILLS_PIPELINE_ID(or empty)  $3=tracked-content(or empty)  $4=MAIN_ROOT(sandbox)
run_fulfillment() {
  local NAME="$1" ZPID="$2" TRACKED="$3" SANDBOX="$4"
  ( cd "$SANDBOX" || exit 1
    if [ -n "$TRACKED" ]; then printf '%s\n' "$TRACKED" > .zskills-tracked; fi
    export NAME
    export CLAUDE_PROJECT_DIR="$REPO_ROOT"   # config + sanitizer resolution
    if [ -n "$ZPID" ]; then export ZSKILLS_PIPELINE_ID="$ZPID"; else unset ZSKILLS_PIPELINE_ID; fi
    eval "$FENCE" >/dev/null 2>&1 || { echo "FENCE_FAILED"; exit 1; }
    echo "PIPELINE_ID=$PIPELINE_ID"
    echo "NAME_SLUG=$NAME_SLUG"
  )
}

TMP1=$(mktemp -d); TMP2=$(mktemp -d); TMP3=$(mktemp -d)
trap 'rm -rf "$TMP1" "$TMP2" "$TMP3"' EXIT
git -C "$TMP1" init -q
git -C "$TMP2" init -q
git -C "$TMP3" init -q

# Tier 1: env wins over .zskills-tracked and fallback.
R=$(run_fulfillment "Gain" "env-pipeline.123" "tracked-pipeline.999" "$TMP1")
PID=$(echo "$R" | sed -n 's/^PIPELINE_ID=//p')
if [ "$PID" = "env-pipeline.123" ]; then
  pass "tier-1: \$ZSKILLS_PIPELINE_ID env wins"
else
  fail "tier-1: env did not win" "PIPELINE_ID=$PID (out: $R)"
fi

# Tier 2: .zskills-tracked wins when env empty.
R=$(run_fulfillment "Gain" "" "tracked-pipeline.999" "$TMP2")
PID=$(echo "$R" | sed -n 's/^PIPELINE_ID=//p')
if [ "$PID" = "tracked-pipeline.999" ]; then
  pass "tier-2: .zskills-tracked file wins when env empty"
else
  fail "tier-2: tracked file did not win" "PIPELINE_ID=$PID (out: $R)"
fi

# Tier 3: synthesized add-example.<NAME> fallback when env+file absent.
R=$(run_fulfillment "math-batch" "" "" "$TMP3")
PID=$(echo "$R" | sed -n 's/^PIPELINE_ID=//p')
NSLUG=$(echo "$R" | sed -n 's/^NAME_SLUG=//p')
if [ "$PID" = "add-example.math-batch" ]; then
  pass "tier-3: synthesized add-example.<NAME> fallback"
else
  fail "tier-3: fallback wrong" "PIPELINE_ID=$PID (out: $R)"
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
