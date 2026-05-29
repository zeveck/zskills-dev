#!/bin/bash
# Behavioral smoke for /add-block's deterministic tracking-setup surface
# (block-diagram/add-block/SKILL.md, the "Tracking setup" fence
# ≈ SKILL.md:88-102).
#
# Covers:
#   1. 3-tier PIPELINE_ID resolution: tier-1 $ZSKILLS_PIPELINE_ID env,
#      tier-2 `.zskills-tracked` file, tier-3 `add-block.${BLOCK_NAME}`
#      fallback.
#   2. BLOCK_SLUG sanitization is deterministic (same $BLOCK_NAME -> same
#      slug, collapsed to [a-zA-Z0-9._-]).
#   3. The per-pipeline tracking dir is created under $MAIN_ROOT.
#
# The fence calls sanitize-pipeline-id.sh, so we EMBED a faithful copy
# (sanitizer resolved via the install lane) AND add a `grep -qF` PARITY gate
# on the fingerprint lines so source drift fails.
#
# Fixtures in mktemp -d; no network; no real gh.
#
# Run from repo root: bash tests/test-add-block-smoke.sh

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/block-diagram/add-block/SKILL.md"
SANITIZER="$REPO_ROOT/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh"
PASS_COUNT=0; FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

echo "=== add-block behavioral smoke ==="

# ── Parity gate on the tracking-setup fence fingerprints ────────────
if grep -qF 'PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-}"' "$SKILL" \
   && grep -qF 'if [ -z "$PIPELINE_ID" ] && [ -f ".zskills-tracked" ]; then' "$SKILL" \
   && grep -qF ': "${PIPELINE_ID:=add-block.${BLOCK_NAME}}"' "$SKILL"; then
  pass "parity: 3-tier PIPELINE_ID resolution fingerprints present"
else
  fail "parity: 3-tier resolution drifted" "tier fingerprints mismatch"
fi
if grep -qF 'BLOCK_SLUG=$(bash "$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh" "$BLOCK_NAME")' "$SKILL"; then
  pass "parity: BLOCK_SLUG routed through sanitize-pipeline-id.sh"
else
  fail "parity: BLOCK_SLUG sanitization drifted" "sanitizer fingerprint mismatch"
fi
if grep -qF 'mkdir -p "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"' "$SKILL"; then
  pass "parity: tracking mkdir under \$MAIN_ROOT present"
else
  fail "parity: tracking mkdir drifted" "mkdir fingerprint mismatch"
fi

# ── Behavioral: embedded faithful copy of the tracking-setup fence ──
run_setup() { # $1=BLOCK_NAME  $2=ZSKILLS_PIPELINE_ID  $3=tracked-content  $4=MAIN_ROOT
  local BLOCK_NAME="$1" ZSKILLS_PIPELINE_ID="$2" TRACKED="$3" MAIN_ROOT="$4"
  ( cd "$MAIN_ROOT" || exit 1
    if [ -n "$TRACKED" ]; then printf '%s\n' "$TRACKED" > .zskills-tracked; fi
    local PIPELINE_ID BLOCK_SLUG
    PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-}"
    if [ -z "$PIPELINE_ID" ] && [ -f ".zskills-tracked" ]; then
      PIPELINE_ID=$(tr -d '[:space:]' < ".zskills-tracked")
    fi
    : "${PIPELINE_ID:=add-block.${BLOCK_NAME}}"
    PIPELINE_ID=$(bash "$SANITIZER" "$PIPELINE_ID")
    BLOCK_SLUG=$(bash "$SANITIZER" "$BLOCK_NAME")
    mkdir -p "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
    echo "PIPELINE_ID=$PIPELINE_ID"
    echo "BLOCK_SLUG=$BLOCK_SLUG"
  )
}

TMP1=$(mktemp -d); trap 'rm -rf "$TMP1" "$TMP2" "$TMP3"' EXIT
git -C "$TMP1" init -q
R=$(run_setup "MyBlock" "env-pipeline.123" "tracked.999" "$TMP1")
PID=$(echo "$R" | sed -n 's/^PIPELINE_ID=//p')
if [ "$PID" = "env-pipeline.123" ]; then
  pass "tier-1: \$ZSKILLS_PIPELINE_ID env wins"
else
  fail "tier-1: env did not win" "PIPELINE_ID=$PID"
fi

TMP2=$(mktemp -d); git -C "$TMP2" init -q
R=$(run_setup "MyBlock" "" "tracked.999" "$TMP2")
PID=$(echo "$R" | sed -n 's/^PIPELINE_ID=//p')
if [ "$PID" = "tracked.999" ]; then
  pass "tier-2: .zskills-tracked file wins when env empty"
else
  fail "tier-2: tracked file did not win" "PIPELINE_ID=$PID"
fi

TMP3=$(mktemp -d); git -C "$TMP3" init -q
# BLOCK_NAME with dirty chars to exercise deterministic slug sanitization.
R=$(run_setup "My Block/v2" "" "" "$TMP3")
PID=$(echo "$R" | sed -n 's/^PIPELINE_ID=//p')
SLUG=$(echo "$R" | sed -n 's/^BLOCK_SLUG=//p')
if [ "$PID" = "add-block.My_Block_v2" ]; then
  pass "tier-3: synthesized add-block.<sanitized BLOCK_NAME> fallback"
else
  fail "tier-3: fallback wrong" "PIPELINE_ID=$PID"
fi
if echo "$SLUG" | grep -qE '^[a-zA-Z0-9._-]+$' && [ "$SLUG" = "My_Block_v2" ]; then
  pass "slug: BLOCK_SLUG sanitized + deterministic ($SLUG)"
else
  fail "slug: BLOCK_SLUG not sanitized as expected" "got: $SLUG"
fi
# Determinism: same BLOCK_NAME -> same slug on a re-run.
R2=$(run_setup "My Block/v2" "" "" "$TMP3")
SLUG2=$(echo "$R2" | sed -n 's/^BLOCK_SLUG=//p')
if [ "$SLUG" = "$SLUG2" ]; then
  pass "slug: deterministic across runs"
else
  fail "slug: non-deterministic" "$SLUG vs $SLUG2"
fi
if [ -d "$TMP3/.zskills/tracking/$PID" ]; then
  pass "mkdir: tracking dir created under \$MAIN_ROOT/.zskills/tracking/<pid>/"
else
  fail "mkdir: tracking dir not created" "expected $TMP3/.zskills/tracking/$PID"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] && exit 0 || exit 1
