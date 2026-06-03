#!/usr/bin/env bash
# tests/test-update-zskills-lane-aware.sh
#
# Phase 1 (UPDATE_ZSKILLS_LANE_AWARE) — the lane-aware plugin-context
# branch (Step 0.7) in skills/update-zskills/SKILL.md.
#
# SKILL.md is a prose+bash procedure executed by an LLM orchestrator, not
# a runnable script. The load-bearing primitives the branch keys on ARE
# testable here:
#   - detect_install_state() classification per lane fixture (the signal),
#   - the dual-locate + fail-soft sourcing logic (LANE defaults to
#     update-zskills when detect-install-state.sh is unreachable),
#   - apply-preset.sh's config-only behavior on a pure-plugin fixture
#     (no mirror written; exit code reflects apply-preset),
#   - structural pins that the branch prose + plugin-lane explanation are
#     present in BOTH the source SKILL.md and its byte-equal mirror.
#
# Acceptance cases:
#   AC1 — pure-plugin (sentinelled artifacts, NO .claude/skills mirror) →
#         detect == plugin; no mirror present; SKILL.md prints the
#         plugin-lane explanation on a bare call.
#   AC2 — plugin lane + <preset> → apply-preset.sh edits config only
#         (execution.landing/main_protected); NO mirror created; exit code
#         reflects apply-preset's code.
#   AC3 — dogfooding/legacy NOT intercepted: a fixture with a legacy mirror
#         (update-zskills) and the dev-repo-shaped case both classify as
#         NON-plugin → branch does not fire.
#   AC4 — fail-soft: detect-install-state.sh unreachable → LANE defaults to
#         update-zskills → legacy behavior; no crash.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

SKILL="skills/update-zskills/SKILL.md"
MIRROR=".claude/skills/update-zskills/SKILL.md"
DETECT="hooks/_lib/detect-install-state.sh"
APPLY="skills/update-zskills/scripts/apply-preset.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=/dev/null
. "$REPO_ROOT/$DETECT"

# A fresh project with config (no .claude artifacts).
base_fixture() {
  local p="$1"
  mkdir -p "$p/.claude"
  cp "$REPO_ROOT/.claude/zskills-config.json" "$p/.claude/zskills-config.json"
}
# Write a plugin-materialised (sentinelled) artifact.
write_sentinelled_hook() {
  mkdir -p "$(dirname "$1")"
  printf '%s\n' '#!/usr/bin/env bash' '# zskills-materialised: 2026.05.0' 'echo hi' > "$1"
}
write_sentinelled_managed() {
  mkdir -p "$(dirname "$1")"
  printf '%s\n' '<!-- zskills-materialised: 2026.05.0 -->' '# rules' > "$1"
}
# Write an update-zskills-installed (UN-sentinelled) SKILL.md mirror.
write_unsentinelled_skill() {
  mkdir -p "$(dirname "$1")"
  printf '%s\n' '---' 'name: x' '---' 'body' > "$1"
}
# Count .claude/skills/*/SKILL.md mirror files under a project.
mirror_skill_count() {
  local p="$1" n=0 f
  for f in "$p"/.claude/skills/*/SKILL.md; do
    [ -f "$f" ] && n=$((n+1))
  done
  echo "$n"
}

echo "=== lane-aware /update-zskills branch (Step 0.7) ==="

# ── Structural pins: the branch + explanation are present in BOTH copies ──
for f in "$SKILL" "$MIRROR"; do
  if grep -q '## Step 0.7 — Lane check' "$REPO_ROOT/$f"; then
    pass "branch section 'Step 0.7 — Lane check' present in $f"
  else
    fail "branch section 'Step 0.7 — Lane check' MISSING from $f"
  fi
done

# The signal is detect_install_state == plugin, NOT $CLAUDE_PLUGIN_ROOT keying.
if grep -q 'detect_install_state' "$REPO_ROOT/$SKILL" \
   && grep -qE 'LANE[[:space:]]*==[[:space:]]*plugin|LANE.*plugin' "$REPO_ROOT/$SKILL"; then
  pass "branch keys on detect_install_state == plugin (signal correct)"
else
  fail "branch does not reference detect_install_state / LANE==plugin"
fi

# Fail-soft default LANE=update-zskills is present in the dual-locate snippet.
if grep -q 'LANE="update-zskills"' "$REPO_ROOT/$SKILL"; then
  pass "dual-locate snippet sets fail-soft default LANE=update-zskills"
else
  fail "fail-soft default LANE=update-zskills missing"
fi

# The plugin-lane explanation text is present (reuse existing phrasing).
if grep -q "plugin-managed" "$REPO_ROOT/$SKILL" \
   && grep -q "plugin marketplace update" "$REPO_ROOT/$SKILL"; then
  pass "plugin-lane explanation text present in branch"
else
  fail "plugin-lane explanation text missing"
fi

# The bare-call plugin arm now ALSO runs the post-install verifier (the
# plugin-lane analog of Step G.5). Scope the assertion to the Step 0.7
# region (from its header to the next top-level '## ' header) so it does not
# spuriously match Step G.5's own verify-install.sh reference further down.
STEP07_REGION="$(awk '/^## Step 0\.7 — Lane check/{f=1} f{print} f&&/^## Bare-preset config-only short-circuit/{exit}' "$REPO_ROOT/$SKILL")"
if printf '%s\n' "$STEP07_REGION" | grep -q "verify-install.sh"; then
  pass "Step 0.7 plugin branch references verify-install.sh (runs post-install verifier)"
else
  fail "Step 0.7 plugin branch does NOT reference verify-install.sh (verifier not wired into bare-call arm)"
fi

# ── AC1 — pure-plugin not flipped ─────────────────────────────────────────
P1="$TMP/plugin"
base_fixture "$P1"
write_sentinelled_hook "$P1/.claude/hooks/inject-bash-timeout.sh"
write_sentinelled_managed "$P1/.claude/rules/zskills/managed.md"
got="$(detect_install_state "$P1")"
[ "$got" = plugin ] && pass "AC1a. pure-plugin fixture → detect_install_state == plugin" \
  || fail "AC1a. expected plugin, got $got"
# No legacy skills mirror exists on the plugin fixture (the branch must
# skip the gap-fill rather than create one).
[ "$(mirror_skill_count "$P1")" -eq 0 ] \
  && pass "AC1b. pure-plugin fixture has NO .claude/skills mirror (gap-fill would flip it)" \
  || fail "AC1b. .claude/skills mirror unexpectedly present on plugin fixture"

# ── AC2 — preset config-only on plugin lane ───────────────────────────────
P2="$TMP/plugin-preset"
base_fixture "$P2"
write_sentinelled_hook "$P2/.claude/hooks/inject-bash-timeout.sh"
write_sentinelled_managed "$P2/.claude/rules/zskills/managed.md"
got="$(detect_install_state "$P2")"
[ "$got" = plugin ] && pass "AC2a. plugin+preset fixture → detect == plugin" \
  || fail "AC2a. expected plugin, got $got"
# Run the SAME apply-preset.sh the branch calls. It must edit ONLY config.
out2=$(PROJECT_ROOT="$P2" bash "$REPO_ROOT/$APPLY" direct 2>&1); rc2=$?
if [ "$rc2" -eq 0 ]; then
  pass "AC2b. apply-preset.sh direct exits 0 (applied) on plugin fixture"
else
  fail "AC2b. apply-preset.sh direct exit=$rc2, output: $out2"
fi
if grep -q '"landing"[[:space:]]*:[[:space:]]*"direct"' "$P2/.claude/zskills-config.json" \
   && grep -q '"main_protected"[[:space:]]*:[[:space:]]*false' "$P2/.claude/zskills-config.json"; then
  pass "AC2c. config updated to landing=direct, main_protected=false (config-only)"
else
  fail "AC2c. config not updated as expected: $(grep -E 'landing|main_protected' "$P2/.claude/zskills-config.json")"
fi
# NO mirror was created by applying the preset (config-only invariant).
[ "$(mirror_skill_count "$P2")" -eq 0 ] \
  && pass "AC2d. applying preset created NO .claude/skills mirror" \
  || fail "AC2d. preset apply created a skills mirror (should be config-only)"
# Idempotent re-apply returns rc=1 (no change), still no mirror.
out2b=$(PROJECT_ROOT="$P2" bash "$REPO_ROOT/$APPLY" direct 2>&1); rc2b=$?
[ "$rc2b" -eq 1 ] \
  && pass "AC2e. re-apply same preset exits 1 (no-change, idempotent)" \
  || fail "AC2e. re-apply exit=$rc2b (expected 1), output: $out2b"

# ── AC3 — dogfooding/legacy NOT intercepted ───────────────────────────────
# (a) legacy-mirror fixture classifies update-zskills.
P3="$TMP/uz"
base_fixture "$P3"
write_unsentinelled_skill "$P3/.claude/skills/update-zskills/SKILL.md"
got="$(detect_install_state "$P3")"
[ "$got" = update-zskills ] && pass "AC3a. legacy-mirror fixture → update-zskills (branch does NOT fire)" \
  || fail "AC3a. expected update-zskills, got $got"
[ "$got" != plugin ] && pass "AC3b. legacy fixture is NOT classified plugin" \
  || fail "AC3b. legacy fixture wrongly classified plugin"

# (b) dual fixture (sentinelled + un-sentinelled evidence) classifies dual,
#     which is also NON-plugin → branch does not fire.
P3d="$TMP/dual"
base_fixture "$P3d"
write_sentinelled_hook "$P3d/.claude/hooks/inject-bash-timeout.sh"
write_unsentinelled_skill "$P3d/.claude/skills/run-plan/SKILL.md"
got="$(detect_install_state "$P3d")"
[ "$got" = dual ] && pass "AC3c. dual fixture → dual (NON-plugin, branch does NOT fire)" \
  || fail "AC3c. expected dual, got $got"

# (c) dev-repo-shaped case: the zskills dev repo dogfoods BOTH lanes but the
#     legacy mirror is present, so it MUST classify NON-plugin (update-zskills
#     or dual) — never plugin. Assert against the real repo root.
got="$(detect_install_state "$REPO_ROOT")"
if [ "$got" != plugin ]; then
  pass "AC3d. dev-repo-shaped (real REPO_ROOT) classifies $got (NON-plugin) — never intercepted"
else
  fail "AC3d. dev repo wrongly classified plugin (would break dogfooding)"
fi

# ── AC4 — fail-soft when detect-install-state.sh unreachable ──────────────
# Replicate the branch's dual-locate + fail-soft snippet with BOTH
# $CLAUDE_PLUGIN_ROOT and $PORTABLE unset → DIS stays empty → LANE defaults
# to update-zskills (legacy behavior), no crash.
LANE_OUT=$(
  env -u CLAUDE_PLUGIN_ROOT -u PORTABLE bash -c '
    set -u
    MAIN_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
    DIS=""
    if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_lib/detect-install-state.sh" ]; then
      DIS="${CLAUDE_PLUGIN_ROOT}/hooks/_lib/detect-install-state.sh"
    elif [ -n "${PORTABLE:-}" ] && [ -f "${PORTABLE}/hooks/_lib/detect-install-state.sh" ]; then
      DIS="${PORTABLE}/hooks/_lib/detect-install-state.sh"
    fi
    LANE="update-zskills"
    if [ -n "$DIS" ]; then . "$DIS"; LANE="$(detect_install_state "$MAIN_ROOT")"; fi
    echo "$LANE"
  '
); rc4=$?
if [ "$rc4" -eq 0 ] && [ "$LANE_OUT" = "update-zskills" ]; then
  pass "AC4. detect unreachable → LANE fail-soft to update-zskills (legacy), no crash"
else
  fail "AC4. fail-soft failed: rc=$rc4 LANE=$LANE_OUT"
fi

# ── AC5 (W6.1/W6.2) — hard-refuse explicit install on the plugin lane ─────
# SKILL.md Step 0.7's W6.1 arm is prose+bash. Structural pins assert the
# refuse prose + the load-bearing condition are present in BOTH copies, and
# the refuse fence is executed directly to prove the gate logic.
SWITCH="scripts/switch-install-path.sh"

# (a) Structural: the hard-refuse prose is present in SKILL.md + mirror and
#     points at switch-install-path.sh (keyed on detect==plugin, NOT
#     $CLAUDE_PLUGIN_ROOT).
for f in "$SKILL" "$MIRROR"; do
  if grep -q 'hard-refuse' "$REPO_ROOT/$f" \
     && grep -q 'switch-install-path.sh --to-update-zskills' "$REPO_ROOT/$f" \
     && grep -q 'switch-in-progress' "$REPO_ROOT/$f"; then
    pass "AC5a. W6.1 hard-refuse prose + switch-in-progress carve-out present in $f"
  else
    fail "AC5a. W6.1 hard-refuse prose MISSING from $f"
  fi
done

# (b) Execute the refuse fence's gate logic directly. The fence refuses when
#     ($MODE==install || $ADDON_FLAG non-empty) AND no switch-in-progress
#     marker. Model the exact condition the branch uses.
refuse_gate() {
  # args: MODE ADDON_FLAG PROJ
  local MODE="$1" ADDON_FLAG="$2" PROJ="$3"
  if { [ "$MODE" = install ] || [ -n "$ADDON_FLAG" ]; } \
     && [ ! -f "$PROJ/.zskills/switch-in-progress" ]; then
    return 1   # refused
  fi
  return 0     # allowed
}
PR="$TMP/refuse"; mkdir -p "$PR/.zskills"
# explicit install, no switch marker → REFUSE
if ! refuse_gate install "" "$PR"; then
  pass "AC5b. explicit 'install' on plugin lane → refused (no switch marker)"
else
  fail "AC5b. explicit install should have been refused"
fi
# --with-addons, no switch marker → REFUSE
if ! refuse_gate "" "--with-addons" "$PR"; then
  pass "AC5c. '--with-addons' on plugin lane → refused"
else
  fail "AC5c. --with-addons should have been refused"
fi
# bare call (no install/addons) → ALLOWED (not refused)
if refuse_gate "" "" "$PR"; then
  pass "AC5d. bare call (no install/addons) → not refused"
else
  fail "AC5d. bare call wrongly refused"
fi
# explicit install WITH switch-in-progress marker → ALLOWED (carve-out)
: > "$PR/.zskills/switch-in-progress"
if refuse_gate install "" "$PR"; then
  pass "AC5e. install + switch-in-progress marker → refuse SKIPPED (W6.2 carve-out)"
else
  fail "AC5e. switch-in-progress carve-out failed to skip the refuse"
fi

# (c) The refuse is keyed on detect==plugin, so it must NOT fire for
#     update-zskills/dual/fresh. detect_install_state classification is
#     already covered by test-sessionstart-dual-install-detect.sh; here we
#     confirm the dev-repo-shaped case classifies NON-plugin (so the refuse
#     never engages there even with an explicit install arg).
got="$(detect_install_state "$REPO_ROOT")"
if [ "$got" != plugin ]; then
  pass "AC5f. dev-repo-shaped classifies $got (NON-plugin) → install never refused there"
else
  fail "AC5f. dev repo wrongly classified plugin (install would be refused — breaks dogfooding)"
fi

# ── AC6 (W6.2) — switch-install-path.sh --to-update-zskills marker lifecycle
# The script WRITES .zskills/switch-in-progress at START and REMOVES it only
# after the lane-lock is written LAST. Drive the full non-interactive switch
# against a plugin fixture and assert: lock written == update-zskills AND the
# marker is GONE at completion (so it cannot trip the refuse in steady state).
P6="$TMP/switch-uz"
base_fixture "$P6"
write_sentinelled_hook "$P6/.claude/hooks/inject-bash-timeout.sh"
write_sentinelled_managed "$P6/.claude/rules/zskills/managed.md"
mkdir -p "$P6/.claude/agents"
printf '%s\n' '---' '# zskills-materialised: 2026.05.0' 'name: v' '---' 'x' > "$P6/.claude/agents/verifier.md"
out6=$(ZSKILLS_SWITCH_NONINTERACTIVE=1 ZSKILLS_SWITCH_PROJECT_DIR="$P6" \
       bash "$REPO_ROOT/$SWITCH" --to-update-zskills 2>&1); rc6=$?
if [ "$rc6" -eq 0 ]; then
  pass "AC6a. switch-install-path.sh --to-update-zskills completed (rc=0)"
else
  fail "AC6a. switch exited rc=$rc6, output: $out6"
fi
if [ "$(cat "$P6/.claude/zskills-install-lane" 2>/dev/null)" = update-zskills ]; then
  pass "AC6b. lane-lock written LAST = update-zskills"
else
  fail "AC6b. lane-lock not update-zskills: $(cat "$P6/.claude/zskills-install-lane" 2>/dev/null)"
fi
if [ ! -e "$P6/.zskills/switch-in-progress" ]; then
  pass "AC6c. switch-in-progress marker removed after lock-write (no steady-state deadlock)"
else
  fail "AC6c. switch-in-progress marker leaked after completion"
fi

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
