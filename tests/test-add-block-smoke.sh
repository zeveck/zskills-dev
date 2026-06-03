#!/bin/bash
# Behavioral smoke for /add-block's deterministic tracking-setup surface
# (block-diagram/add-block/SKILL.md, the "PIPELINE_ID / BLOCK_SLUG
# resolution" fence ≈ SKILL.md:93-113).
#
# Covers:
#   1. 3-tier PIPELINE_ID resolution: tier-1 $ZSKILLS_PIPELINE_ID env,
#      tier-2 `.zskills-tracked` file, tier-3 `add-block.${BLOCK_NAME}`
#      fallback.
#   2. BLOCK_SLUG sanitization is deterministic (same $BLOCK_NAME -> same
#      slug, collapsed to [a-zA-Z0-9._-]).
#   3. The per-pipeline tracking dir is created under $MAIN_ROOT.
#
# EXTRACT-AND-RUN: this suite extract_fence_between's the REAL production
# fence out of block-diagram/add-block/SKILL.md and EXECUTES it (no embedded
# copy that can silently drift). The fence sources zskills-resolve-config.sh
# (which sets $ZSKILLS_SKILLS_ROOT and thus reaches the real
# sanitize-pipeline-id.sh) and derives $MAIN_ROOT from git-common-dir, so we
# run it with CLAUDE_PROJECT_DIR pinned at the real repo (config + sanitizer
# resolution) while cwd is a throwaway git sandbox (so $MAIN_ROOT and every
# marker land inside the sandbox, never the real tree).
#
# Fixtures in mktemp -d; no network; no real gh.
#
# Run from repo root: bash tests/test-add-block-smoke.sh

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/block-diagram/add-block/SKILL.md"
# shellcheck source=tests/lib/extract-fence.sh
. "$SCRIPT_DIR/lib/extract-fence.sh"
PASS_COUNT=0; FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

echo "=== add-block behavioral smoke (extract-and-run) ==="

# ── Extract the REAL tracking-setup fence ───────────────────────────
# Tight landmarks: the prose "resolve `PIPELINE_ID`" intro precedes the
# only fence that sets BLOCK_SLUG; bracket on that and the post-fence
# "Tier-1 (env) covers" sentence so exactly one ```bash block extracts.
FENCE="$(extract_fence_between "$SKILL" \
  'Before any tracking-marker writes' \
  'Tier-1 [(]env[)] covers' 1 0)" || {
  echo "could not extract add-block tracking fence" >&2
  echo "Results: 0 passed, 1 failed"; exit 1
}
# Sanity: the extracted fence must contain the load-bearing lines.
if printf '%s\n' "$FENCE" | grep -qF ': "${PIPELINE_ID:=add-block.${BLOCK_NAME}}"' \
   && printf '%s\n' "$FENCE" | grep -qF 'BLOCK_SLUG=$(bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/sanitize-pipeline-id.sh" "$BLOCK_NAME")' \
   && printf '%s\n' "$FENCE" | grep -qF 'mkdir -p "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"'; then
  pass "extract: real fence carries 3-tier resolution + BLOCK_SLUG + mkdir"
else
  fail "extract: fence missing load-bearing lines" "extraction drifted"
fi

# run_setup — write inputs, then EXECUTE the extracted production fence.
# $1=BLOCK_NAME  $2=ZSKILLS_PIPELINE_ID(or empty)  $3=tracked-content(or empty)  $4=MAIN_ROOT(sandbox)
run_setup() {
  local BLOCK_NAME="$1" ZPID="$2" TRACKED="$3" SANDBOX="$4"
  ( cd "$SANDBOX" || exit 1
    if [ -n "$TRACKED" ]; then printf '%s\n' "$TRACKED" > .zskills-tracked; fi
    export BLOCK_NAME
    export CLAUDE_PROJECT_DIR="$REPO_ROOT"   # config + sanitizer resolution
    if [ -n "$ZPID" ]; then export ZSKILLS_PIPELINE_ID="$ZPID"; else unset ZSKILLS_PIPELINE_ID; fi
    # Legacy-lane faithful: production fences run WITHOUT `set -u`, so the new
    # idiom's bare ${CLAUDE_PLUGIN_ROOT} token expands empty → else/legacy
    # branch. This harness wraps the extracted fence in the file-level `set -u`;
    # bind the token to empty so the SAME legacy else-branch is exercised
    # without an unbound-variable abort (binding empty, NOT a real path).
    export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
    eval "$FENCE" >/dev/null 2>&1 || { echo "FENCE_FAILED"; exit 1; }
    echo "PIPELINE_ID=$PIPELINE_ID"
    echo "BLOCK_SLUG=$BLOCK_SLUG"
  )
}

TMP1=$(mktemp -d); TMP2=$(mktemp -d); TMP3=$(mktemp -d)
trap 'rm -rf "$TMP1" "$TMP2" "$TMP3"' EXIT
git -C "$TMP1" init -q
git -C "$TMP2" init -q
git -C "$TMP3" init -q

# Tier 1: env wins over .zskills-tracked and fallback.
R=$(run_setup "MyBlock" "env-pipeline.123" "tracked.999" "$TMP1")
PID=$(echo "$R" | sed -n 's/^PIPELINE_ID=//p')
if [ "$PID" = "env-pipeline.123" ]; then
  pass "tier-1: \$ZSKILLS_PIPELINE_ID env wins"
else
  fail "tier-1: env did not win" "PIPELINE_ID=$PID (out: $R)"
fi

# Tier 2: .zskills-tracked wins when env empty.
R=$(run_setup "MyBlock" "" "tracked.999" "$TMP2")
PID=$(echo "$R" | sed -n 's/^PIPELINE_ID=//p')
if [ "$PID" = "tracked.999" ]; then
  pass "tier-2: .zskills-tracked file wins when env empty"
else
  fail "tier-2: tracked file did not win" "PIPELINE_ID=$PID (out: $R)"
fi

# Tier 3: synthesized add-block.<sanitized BLOCK_NAME> fallback.
R=$(run_setup "My Block/v2" "" "" "$TMP3")
PID=$(echo "$R" | sed -n 's/^PIPELINE_ID=//p')
SLUG=$(echo "$R" | sed -n 's/^BLOCK_SLUG=//p')
if [ "$PID" = "add-block.My_Block_v2" ]; then
  pass "tier-3: synthesized add-block.<sanitized BLOCK_NAME> fallback"
else
  fail "tier-3: fallback wrong" "PIPELINE_ID=$PID (out: $R)"
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
