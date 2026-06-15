#!/bin/bash
# tests/test-plan-claim-hook-deny.sh — Phase 1 W1.9.
#
# Asserts hooks/block-run-plan-unclaimed.sh denies create-worktree.sh
# invocations targeting any of the THREE /run-plan branch shapes (per
# Acceptance Criteria A9) when no claim is present, and passes through
# when a claim is present.
#
# Cases (each: claim absent -> deny; claim present -> allow):
#   1. cp-<slug>            (finish-mode cherry-pick; via --prefix cp <slug>)
#   2. cp-<slug>-phase-1    (single-phase cherry-pick, one-digit phase;
#                            via --branch-name)
#   3. cp-<slug>-phase-12   (single-phase cherry-pick, two-digit phase;
#                            via --branch-name — confirms multi-digit)
#   4. feat/<slug>          (PR mode; via --branch-name)
#
# All four cases resolve to the SAME plan-scoped claim dir (plan-<slug>/),
# exercising the non-greedy slug capture in the hook's regex.
#
# Per the implementer-task spec, a synthetic plan file
# ${ZSKILLS_PLANS_DIR}/<slug>.md must exist for the hook to reach the
# claim-check stage (otherwise the plan-file pass-through fires). Each
# fixture writes that file under a per-test CLAUDE_PROJECT_DIR.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/hooks/block-run-plan-unclaimed.sh"
CLAIM_SH="$REPO_ROOT/skills/run-plan/scripts/claim-plan.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SCRATCH_ROOT="/tmp/test-plan-claim-hook-deny-$$"
cleanup() {
  if [ -n "${TEST_KEEP_SCRATCH:-}" ]; then
    echo "TEST_KEEP_SCRATCH set — leaving $SCRATCH_ROOT" >&2
    return
  fi
  if [ -d "$SCRATCH_ROOT" ]; then
    find "$SCRATCH_ROOT" -mindepth 1 -delete 2>/dev/null || true
    rmdir "$SCRATCH_ROOT" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM
mkdir -p "$SCRATCH_ROOT"

if [ ! -f "$HOOK" ]; then
  echo "FATAL: $HOOK missing" >&2; exit 1
fi
if [ ! -f "$CLAIM_SH" ]; then
  echo "FATAL: $CLAIM_SH missing" >&2; exit 1
fi

PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
if [ -z "$PYTHON" ]; then
  echo "FATAL: no Python interpreter available" >&2; exit 1
fi

# Build a JSON PreToolUse envelope for a given Bash command string.
make_payload() {
  local cmd="$1"
  "$PYTHON" -c "
import json, sys
print(json.dumps({
    'tool_name': 'Bash',
    'tool_input': {'command': sys.argv[1]},
}))
" "$cmd"
}

# Run the hook against a payload. Echoes 'DENY' or 'ALLOW' on stdout.
run_hook_decision() {
  local payload="$1"
  local fixture_root="$2"
  local stdout
  stdout=$(cd "$fixture_root" && CLAUDE_PROJECT_DIR="$fixture_root" \
    bash -c "echo '$payload' | bash '$HOOK'" 2>&1)
  if echo "$stdout" | grep -q '"permissionDecision":"deny"'; then
    echo "DENY"
  else
    echo "ALLOW"
  fi
}

# Set up a fixture with a synthetic plan file and a configured
# branch_prefix (matches what the hook reads from config).
setup_fixture() {
  local label="$1"
  local slug="$2"
  local root="$SCRATCH_ROOT/$label"
  mkdir -p "$root/.claude"
  mkdir -p "$root/plans"
  # Synthetic plan file so the slug-is-real-plan-file gate passes.
  printf '%s\n' "# Synthetic plan for $slug" > "$root/plans/$slug.md"
  # Config with branch_prefix=feat/ (default) + output.plans_dir pinned to
  # this fixture's plans/ layout (INSTALL_REDESIGN Phase 5: the no-config
  # built-in default is now docs/plans, which would miss the plan file and
  # turn every DENY case into a pass-through ALLOW).
  printf '%s\n' '{"execution":{"branch_prefix":"feat/"},"output":{"plans_dir":"plans"}}' > "$root/.claude/zskills-config.json"
  # Init git so MAIN_ROOT resolves.
  (cd "$root" && git init -q && git config user.email "t@t" && git config user.name "t" \
    && git commit --allow-empty -q -m "init") || return 1
  # The hook sources zskills-paths.sh — ensure a copy is present at the
  # expected sibling location. We symlink to the repo's source so we don't
  # have to maintain a copy.
  mkdir -p "$root/skills/update-zskills/scripts"
  cp "$REPO_ROOT/skills/update-zskills/scripts/zskills-paths.sh" \
    "$root/skills/update-zskills/scripts/zskills-paths.sh"
  printf '%s' "$root"
}

echo "=== block-run-plan-unclaimed.sh hook deny/allow ==="

# Cases: label, slug, command-shape (substituted with $SLUG and $REPO_ROOT
# and $FIXTURE), branch-name human-readable.
SLUG="myplan"

run_case() {
  local label="$1"
  local cmd_template="$2"
  local description="$3"

  local fixture
  fixture=$(setup_fixture "$label" "$SLUG") || { fail "$label setup" "fixture init"; return; }

  # Substitute placeholders.
  local cmd="${cmd_template//\{SLUG\}/$SLUG}"
  cmd="${cmd//\{REPO_ROOT\}/$REPO_ROOT}"

  local payload
  payload=$(make_payload "$cmd")

  # 1. Claim absent -> expect DENY.
  local d1
  d1=$(run_hook_decision "$payload" "$fixture")
  if [ "$d1" = "DENY" ]; then
    pass "$description : claim absent -> hook denies"
  else
    fail "$description claim-absent" "expected DENY, got $d1"
  fi

  # 2. Create claim, expect ALLOW.
  (
    cd "$fixture" || exit 1
    CLAUDE_PROJECT_DIR="$fixture" bash "$CLAIM_SH" acquire "$SLUG" --pipeline-id "run-plan.$SLUG"
  ) >/dev/null 2>&1
  if [ ! -d "$fixture/.zskills/claims/plan-$SLUG" ]; then
    fail "$description claim-acquire-setup" "failed to create plan-$SLUG dir"
    return
  fi
  local d2
  d2=$(run_hook_decision "$payload" "$fixture")
  if [ "$d2" = "ALLOW" ]; then
    pass "$description : claim present (plan-$SLUG) -> hook allows"
  else
    fail "$description claim-present" "expected ALLOW, got $d2"
  fi
}

# ───────────────────────────────────────────────────────────────────────
# Case 1: cp-<slug> via --prefix cp <slug>.
# create-worktree.sh --prefix cp <slug>  =>  branch = cp-<slug>
# ───────────────────────────────────────────────────────────────────────
run_case "case1_cp_slug" \
  "bash {REPO_ROOT}/skills/create-worktree/scripts/create-worktree.sh --prefix cp {SLUG}" \
  "Case 1 (cp-<slug>)"

# ───────────────────────────────────────────────────────────────────────
# Case 2: cp-<slug>-phase-1 via --branch-name.
# Non-greedy slug capture: slug=<slug>, phase=-phase-1 (discarded; same
# claim dir).
# ───────────────────────────────────────────────────────────────────────
run_case "case2_cp_slug_phase_1" \
  "bash {REPO_ROOT}/skills/create-worktree/scripts/create-worktree.sh --branch-name cp-{SLUG}-phase-1 {SLUG}" \
  "Case 2 (cp-<slug>-phase-1)"

# ───────────────────────────────────────────────────────────────────────
# Case 3: cp-<slug>-phase-12 (two-digit phase).
# ───────────────────────────────────────────────────────────────────────
run_case "case3_cp_slug_phase_12" \
  "bash {REPO_ROOT}/skills/create-worktree/scripts/create-worktree.sh --branch-name cp-{SLUG}-phase-12 {SLUG}" \
  "Case 3 (cp-<slug>-phase-12, two-digit phase)"

# ───────────────────────────────────────────────────────────────────────
# Case 4: feat/<slug> PR-mode branch.
# ───────────────────────────────────────────────────────────────────────
run_case "case4_feat_slug" \
  "bash {REPO_ROOT}/skills/create-worktree/scripts/create-worktree.sh --branch-name feat/{SLUG} {SLUG}" \
  "Case 4 (feat/<slug>)"

# ───────────────────────────────────────────────────────────────────────
# Negative control: branch matches cp-<slug> shape BUT no plan file exists
# at $ZSKILLS_PLANS_DIR/<slug>.md -> hook MUST pass through (no deny),
# regardless of claim state.
# ───────────────────────────────────────────────────────────────────────
neg_root="$SCRATCH_ROOT/case5_nonplan_branch"
mkdir -p "$neg_root/.claude"
mkdir -p "$neg_root/plans"  # empty plans dir — no <slug>.md
mkdir -p "$neg_root/skills/update-zskills/scripts"
cp "$REPO_ROOT/skills/update-zskills/scripts/zskills-paths.sh" \
  "$neg_root/skills/update-zskills/scripts/zskills-paths.sh"
# output.plans_dir pinned to the fixture layout (Phase 5 cascade default
# is docs/plans) so the negative control exercises "empty plans dir", not
# "wrong dir".
printf '%s\n' '{"execution":{"branch_prefix":"feat/"},"output":{"plans_dir":"plans"}}' > "$neg_root/.claude/zskills-config.json"
(cd "$neg_root" && git init -q && git config user.email "t@t" && git config user.name "t" \
  && git commit --allow-empty -q -m "init") >/dev/null 2>&1 || true

cmd5="bash $REPO_ROOT/skills/create-worktree/scripts/create-worktree.sh --prefix cp not-a-plan-slug"
payload5=$(make_payload "$cmd5")
d5=$(run_hook_decision "$payload5" "$neg_root")
if [ "$d5" = "ALLOW" ]; then
  pass "Negative control: cp-<not-a-plan> with no plan file at plans/not-a-plan-slug.md -> hook passes through"
else
  fail "negative control nonplan branch" "expected ALLOW (pass-through), got $d5"
fi

# ═══════════════════════════════════════════════════════════════════════════
# ENFORCEMENT_V2_PLAN Phase 2 (#1159) — plan_unclaimed demotion + bypass parity.
# plan_unclaimed is DEMOTABLE: autonomous/unwatched → BLOCK; watched → SILENT
# by shipped default; opt-in "warn".
# ═══════════════════════════════════════════════════════════════════════════

# Build a payload carrying a top-level permission_mode field.
make_payload_pm() {
  local cmd="$1" pm="$2"
  "$PYTHON" -c "
import json, sys
print(json.dumps({
    'tool_name': 'Bash',
    'tool_input': {'command': sys.argv[1]},
    'permission_mode': sys.argv[2],
}))
" "$cmd" "$pm"
}

# Run hook and capture rc + stdout for the enforcement-mode assertions.
run_hook_capture() {
  local payload="$1" fixture_root="$2"
  PLAN_STDOUT=$(cd "$fixture_root" && CLAUDE_PROJECT_DIR="$fixture_root" \
    bash -c "echo '$payload' | bash '$HOOK'" 2>/dev/null)
  PLAN_RC=$?
}

ENF_SLUG="enfplan"
ENF_CMD="bash $REPO_ROOT/skills/create-worktree/scripts/create-worktree.sh --prefix cp $ENF_SLUG"

# ── EP1: bypass-parity — no-claim + bypassPermissions → DENY + names toggle ─
ep1_fixture=$(setup_fixture "enf_p1" "$ENF_SLUG")
ep1_payload=$(make_payload_pm "$ENF_CMD" "bypassPermissions")
run_hook_capture "$ep1_payload" "$ep1_fixture"
if echo "$PLAN_STDOUT" | grep -q '"permissionDecision":"deny"' \
   && echo "$PLAN_STDOUT" | grep -q '\[hooks.tracking.plan_unclaimed'; then
  pass "EP1: no-claim deny under bypassPermissions (bypass parity 5/5) + names toggle"
else
  fail "EP1: no-claim deny under bypass" "rc=$PLAN_RC stdout=$PLAN_STDOUT"
fi

# ── EP2: watched (default) + no toggle → SILENT allow ──────────────────────
ep2_fixture=$(setup_fixture "enf_p2" "$ENF_SLUG")
ep2_payload=$(make_payload_pm "$ENF_CMD" "default")
run_hook_capture "$ep2_payload" "$ep2_fixture"
if [ "$PLAN_RC" -eq 0 ] && [ -z "$PLAN_STDOUT" ]; then
  pass "EP2: watched no-claim, no toggle → SILENT allow (demotable shipped default)"
else
  fail "EP2: watched no-toggle → SILENT" "rc=$PLAN_RC stdout=$PLAN_STDOUT"
fi

# ── EP3: toggle "warn" + watched → ALLOW + decision-less warn naming toggle ─
ep3_fixture=$(setup_fixture "enf_p3" "$ENF_SLUG")
# Re-write the fixture config to add the warn toggle (preserve plans_dir).
printf '%s\n' '{"execution":{"branch_prefix":"feat/"},"output":{"plans_dir":"plans"},"hooks":{"tracking":{"plan_unclaimed":"warn"}}}' > "$ep3_fixture/.claude/zskills-config.json"
ep3_payload=$(make_payload_pm "$ENF_CMD" "default")
run_hook_capture "$ep3_payload" "$ep3_fixture"
if [ "$PLAN_RC" -eq 0 ] \
   && echo "$PLAN_STDOUT" | grep -q '"systemMessage"' \
   && echo "$PLAN_STDOUT" | grep -q '\[hooks.tracking.plan_unclaimed' \
   && ! echo "$PLAN_STDOUT" | grep -q 'permissionDecision'; then
  pass "EP3: toggle warn + watched → ALLOW + decision-less warn naming the toggle"
else
  fail "EP3: toggle warn + watched → warn" "rc=$PLAN_RC stdout=$PLAN_STDOUT"
fi

# ───────────────────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────────────────
echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (%d total)\033[0m\n' "$PASS_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (%d total)\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit 1
fi
