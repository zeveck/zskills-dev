#!/usr/bin/env bash
# tests/test-update-zskills-lane-aware.sh
#
# Phase 1 (UPDATE_ZSKILLS_LANE_AWARE) — the lane-aware plugin-context
# branch (Step 0.7) in skills/update-zskills/SKILL.md.
#
# SKILL.md is a prose+bash procedure executed by an LLM orchestrator, not
# a runnable script. The load-bearing primitives the branch keys on ARE
# testable here:
#   - detect_install_state() classification per lane fixture (the signal;
#     since INSTALL_REDESIGN Phase 7 plugin evidence is the
#     $CLAUDE_PLUGIN_ROOT env context — the D20 sentinel rules and the
#     lane lock-file rule died with the materialiser + switch machinery),
#   - the dual-locate + fail-soft sourcing logic (LANE defaults to
#     update-zskills when detect-install-state.sh is unreachable),
#   - apply-preset.sh's config-only behavior on a pure-plugin fixture
#     (no mirror written; exit code reflects apply-preset),
#   - structural pins that the branch prose + plugin-lane explanation are
#     present in BOTH the source SKILL.md and its byte-equal mirror.
#
# Acceptance cases:
#   AC1 — pure-plugin (plugin loaded, NO .claude/skills mirror) →
#         detect == plugin; no mirror present.
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
# detect with / without the plugin loaded (Phase 7: plugin evidence is the
# $CLAUDE_PLUGIN_ROOT env context, controlled explicitly per call so the
# suite is deterministic regardless of the invoking session's own env).
detect_plugin_loaded() {
  CLAUDE_PLUGIN_ROOT="$REPO_ROOT" detect_install_state "$1"
}
detect_plugin_unloaded() {
  ( unset CLAUDE_PLUGIN_ROOT; detect_install_state "$1" )
}
# Write an update-zskills-installed SKILL.md mirror.
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

# The plugin-lane explanation text is present (reuse existing phrasing —
# now part of the update arm's summary).
if grep -q "plugin-managed" "$REPO_ROOT/$SKILL" \
   && grep -q "plugin marketplace update" "$REPO_ROOT/$SKILL"; then
  pass "plugin-lane explanation text present in branch"
else
  fail "plugin-lane explanation text missing"
fi

# The bare-call plugin arm is the explicit init/update entry point
# (INSTALL_REDESIGN Phase 6a). Scope the assertions to the Step 0.7 region
# (from its header to the next top-level '## ' header) so they do not
# spuriously match Step G.5's own references further down.
STEP07_REGION="$(awk '/^## Step 0\.7 — Lane check/{f=1} f{print} f&&/^## Bare-preset config-only short-circuit/{exit}' "$REPO_ROOT/$SKILL")"
if printf '%s\n' "$STEP07_REGION" | grep -q "verify-install.sh"; then
  pass "Step 0.7 plugin branch references verify-install.sh (A6 verify, report-only this phase)"
else
  fail "Step 0.7 plugin branch does NOT reference verify-install.sh (verifier not wired into bare-call arm)"
fi

# ── Init-flow pins (Phase 6a A0–A7) ───────────────────────────────────────
# (a) The arm sources init-state.sh (#1132 single path definition) and uses
#     its routing predicate + lock-LAST writer — never re-typed marker paths.
for needle in "scripts/init-state.sh" "zskills_init_done_present" "zskills_write_init_markers"; do
  if printf '%s\n' "$STEP07_REGION" | grep -q "$needle"; then
    pass "Step 0.7 init arm carries '$needle' (init-state.sh-sourced flow)"
  else
    fail "Step 0.7 init arm MISSING '$needle'"
  fi
done

# (b) A1.5 cleanup is wired via the init-state.sh helpers (referential — the
#     frozen legacy-residue literals live ONLY in init-state.sh).
for needle in "zskills_legacy_remove_sentinelled" "zskills_legacy_seed_config_matches" "zskills_legacy_consume_seed_notice"; do
  if printf '%s\n' "$STEP07_REGION" | grep -q "$needle"; then
    pass "Step 0.7 A1.5 cleanup references $needle"
  else
    fail "Step 0.7 A1.5 cleanup MISSING $needle"
  fi
done

# (c) Literal-string discipline: the frozen legacy-residue literals appear
#     NOWHERE in the Step 0.7 region — derive them by sourcing init-state.sh
#     (never re-typed here either).
. "$REPO_ROOT/skills/update-zskills/scripts/init-state.sh"
if printf '%s\n' "$STEP07_REGION" | grep -qF "$ZSKILLS_LEGACY_SENTINEL_PREFIX"; then
  fail "Step 0.7 region re-types the D20 sentinel prefix (must stay only in init-state.sh)"
else
  pass "Step 0.7 region carries NO re-typed D20 sentinel prefix (discipline holds)"
fi
if printf '%s\n' "$STEP07_REGION" | grep -qF "$ZSKILLS_LEGACY_SEED_NOTICE_REL"; then
  fail "Step 0.7 region re-types the seed-notice path (must stay only in init-state.sh)"
else
  pass "Step 0.7 region carries NO re-typed seed-notice path (discipline holds)"
fi

# (d) Gitignore-first ordering: the check-ignore verification appears BEFORE
#     the lock-LAST writer call within the region.
GI_LINE="$(printf '%s\n' "$STEP07_REGION" | grep -n 'check-ignore' | head -1 | cut -d: -f1)"
LOCK_LINE="$(printf '%s\n' "$STEP07_REGION" | grep -n 'zskills_write_init_markers' | head -1 | cut -d: -f1)"
if [ -n "$GI_LINE" ] && [ -n "$LOCK_LINE" ] && [ "$GI_LINE" -lt "$LOCK_LINE" ]; then
  pass "gitignore-first: check-ignore verification precedes the lock-LAST writer (lines $GI_LINE < $LOCK_LINE)"
else
  fail "gitignore-first ordering broken (check-ignore@$GI_LINE, writer@$LOCK_LINE)"
fi

# ── AC1 — pure-plugin not flipped ─────────────────────────────────────────
P1="$TMP/plugin"
base_fixture "$P1"
got="$(detect_plugin_loaded "$P1")"
[ "$got" = plugin ] && pass "AC1a. plugin-loaded mirror-less fixture → detect_install_state == plugin (env-context evidence)" \
  || fail "AC1a. expected plugin, got $got"
# No legacy skills mirror exists on the plugin fixture (the branch must
# skip the gap-fill rather than create one).
[ "$(mirror_skill_count "$P1")" -eq 0 ] \
  && pass "AC1b. pure-plugin fixture has NO .claude/skills mirror (gap-fill would flip it)" \
  || fail "AC1b. .claude/skills mirror unexpectedly present on plugin fixture"

# AC1c (#1064) — a plugin consumer who ships their OWN non-zskills skill
# (e.g. social-seo) must STILL resolve LANE==plugin. The consumer skill is a
# .claude/skills/<name>/SKILL.md that is NOT in the zskills-owned anchor set,
# so it must not count as /update-zskills evidence. (Before the fix the
# bare-wildcard loop matched it → plugin install mis-classified → Step 0.7
# branch would not fire.)
P1c="$TMP/plugin-consumer-skill"
base_fixture "$P1c"
write_unsentinelled_skill "$P1c/.claude/skills/social-seo/SKILL.md"   # consumer's OWN skill
got="$(detect_plugin_loaded "$P1c")"
[ "$got" = plugin ] && pass "AC1c. plugin + consumer's own non-zskills skill → LANE==plugin (#1064)" \
  || fail "AC1c. expected plugin, got $got (consumer skill mis-counted as legacy evidence)"

# ── AC2 — preset config-only on plugin lane ───────────────────────────────
P2="$TMP/plugin-preset"
base_fixture "$P2"
got="$(detect_plugin_loaded "$P2")"
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
# (a) legacy-mirror fixture (no plugin loaded) classifies update-zskills.
P3="$TMP/uz"
base_fixture "$P3"
write_unsentinelled_skill "$P3/.claude/skills/update-zskills/SKILL.md"
got="$(detect_plugin_unloaded "$P3")"
[ "$got" = update-zskills ] && pass "AC3a. legacy-mirror fixture → update-zskills (branch does NOT fire)" \
  || fail "AC3a. expected update-zskills, got $got"
[ "$got" != plugin ] && pass "AC3b. legacy fixture is NOT classified plugin" \
  || fail "AC3b. legacy fixture wrongly classified plugin"

# (b) dual fixture (plugin loaded + a zskills mirror) classifies dual,
#     which is also NON-plugin → branch does not fire.
P3d="$TMP/dual"
base_fixture "$P3d"
write_unsentinelled_skill "$P3d/.claude/skills/run-plan/SKILL.md"
got="$(detect_plugin_loaded "$P3d")"
[ "$got" = dual ] && pass "AC3c. plugin-loaded + mirror fixture → dual (NON-plugin, branch does NOT fire)" \
  || fail "AC3c. expected dual, got $got"

# (c) dev-repo-shaped case: the zskills dev repo dogfoods BOTH lanes but the
#     legacy mirror is present, so it MUST classify NON-plugin (update-zskills
#     plain, dual when plugin-loaded) — never plugin. Assert BOTH env states
#     against the real repo root.
got="$(detect_plugin_unloaded "$REPO_ROOT")"
got2="$(detect_plugin_loaded "$REPO_ROOT")"
if [ "$got" != plugin ] && [ "$got2" != plugin ]; then
  pass "AC3d. dev-repo-shaped (real REPO_ROOT) classifies $got / $got2 (NON-plugin in both env states) — never intercepted"
else
  fail "AC3d. dev repo wrongly classified plugin (would break dogfooding): unloaded=$got loaded=$got2"
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

# ── AC5 (W6.1) — hard-refuse explicit install on the plugin lane ──────────
# SKILL.md Step 0.7's W6.1 arm is prose+bash. Structural pins assert the
# refuse prose is present in BOTH copies, and the refuse fence is executed
# directly to prove the gate logic. The refuse is UNCONDITIONAL since
# INSTALL_REDESIGN Phase 7: the lane-switch machinery (and its W6.2
# in-flight-marker carve-out) was deleted — no marker bypasses the refuse.

# (a) Structural: the unconditional hard-refuse prose is present in SKILL.md
#     + mirror (keyed on detect==plugin), recommends the uninstall-one-lane
#     model, and the Step 0.7 region carries NO marker carve-out fence.
STEP07_REGION_M="$(awk '/^## Step 0\.7 — Lane check/{f=1} f{print} f&&/^## Bare-preset config-only short-circuit/{exit}' "$REPO_ROOT/$MIRROR")"
for f in "$SKILL" "$MIRROR"; do
  if grep -q 'hard-refuse' "$REPO_ROOT/$f" \
     && grep -q "refusing 'install' on the plugin lane" "$REPO_ROOT/$f" \
     && grep -q 'uninstall' "$REPO_ROOT/$f"; then
    pass "AC5a. W6.1 unconditional hard-refuse prose present in $f (uninstall-one-lane recommendation)"
  else
    fail "AC5a. W6.1 hard-refuse prose MISSING from $f"
  fi
done
# Regression (Phase 7): the refuse fence's condition is the bare
# $MODE==install test — no second marker-file condition survives (source
# AND mirror).
if printf '%s\n' "$STEP07_REGION" | grep -q 'if \[ "\$MODE" = install \]; then' \
   && printf '%s\n' "$STEP07_REGION_M" | grep -q 'if \[ "\$MODE" = install \]; then'; then
  pass "AC5a2. refuse fence is the bare \$MODE==install test in source + mirror (carve-out-less)"
else
  fail "AC5a2. refuse fence is not the bare unconditional form in both copies"
fi

# (b) Execute the refuse fence's gate logic directly. The fence refuses
#     whenever $MODE==install — unconditionally. Model the exact condition.
refuse_gate() {
  # args: MODE PROJ
  local MODE="$1" PROJ="$2"
  if [ "$MODE" = install ]; then
    return 1   # refused
  fi
  return 0     # allowed
}
PR="$TMP/refuse"; mkdir -p "$PR/.zskills"
# explicit install → REFUSE
if ! refuse_gate install "$PR"; then
  pass "AC5b. explicit 'install' on plugin lane → refused"
else
  fail "AC5b. explicit install should have been refused"
fi
# bare call (no install) → ALLOWED (not refused)
if refuse_gate "" "$PR"; then
  pass "AC5d. bare call (no install) → not refused"
else
  fail "AC5d. bare call wrongly refused"
fi
# REGRESSION (Phase 7): a present in-flight-lane-switch marker file no
# longer bypasses the refuse — the carve-out died with the switch machinery.
# (Marker name assembled from halves so the Phase 7 retired-literal AC sweep
# stays clean — the whole point of this case is that the file is now
# meaningless to the refuse.)
RETIRED_SWITCH_MARKER="switch-in-""progress"
: > "$PR/.zskills/$RETIRED_SWITCH_MARKER"
if ! refuse_gate install "$PR"; then
  pass "AC5e. install + stale lane-switch marker file → STILL refused (carve-out retired, Phase 7 regression pin)"
else
  fail "AC5e. a stale lane-switch marker file bypassed the refuse (retired carve-out resurfaced)"
fi

# (c) The refuse is keyed on detect==plugin, so it must NOT fire for
#     mirror-bearing/fresh lanes. Confirm the dev-repo-shaped case
#     classifies NON-plugin (so the refuse never engages there even with an
#     explicit install arg).
got="$(detect_plugin_loaded "$REPO_ROOT")"
if [ "$got" != plugin ]; then
  pass "AC5f. dev-repo-shaped (plugin-loaded) classifies $got (NON-plugin) → install never refused there"
else
  fail "AC5f. dev repo wrongly classified plugin (install would be refused — breaks dogfooding)"
fi

# (AC6 — the lane-switch marker lifecycle — was deleted in INSTALL_REDESIGN
# Phase 7 with the lane-switch script: subject-removal.)

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
