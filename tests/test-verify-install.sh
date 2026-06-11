#!/usr/bin/env bash
# tests/test-verify-install.sh
#
# Issue #999 — dev test for the consumer post-install verifier
# (skills/update-zskills/verifiers/verify-install-lib.sh). SOURCES the shipped
# assertion library (the dev repo has skills/, so no copy step — the lib that
# ships IS the source of truth) and asserts it against SYNTHETIC installs built
# in a mktemp sandbox, reusing the synthetic-consumer oracle pattern from
# tests/test-synthetic-consumer-install.sh.
#
# Anti-hollow contract (the load-bearing requirement): the verifier must FAIL
# on a deliberately-broken install, not only PASS on a good one. This file
# asserts BOTH directions for BOTH lanes:
#   - good legacy install                  → verify_overall_rc == 0 (no FAIL)
#   - good legacy + UNSET optional config  → 0 FAIL  (#1004 — the renderer's
#       designed `<!-- TODO -->` placeholders for unset OPTIONAL config must
#       NOT be flagged; this is the recurrence-proof case PR #1003 missed)
#   - good legacy + NO zskills_version     → 0 FAIL + legacy.version-recorded
#       WARN  (#1124 — after the plugin.json fallback a missing version is
#       abnormal but not breakage; WARN, never FAIL)
#   - good legacy + zskills_version present → legacy.version-recorded PASS
#   - broken legacy (hook file gone)       → FAIL
#   - broken legacy (raw {{TOKEN}})        → FAIL  (renderer never ran)
#   - good plugin (init-era: markers + gitignore umbrella + valid config) → no FAIL
#   - good plugin + NO config              → no FAIL (zero-config by design)
#   - plugin version skew (init-done vs plugin.json) → WARN, never FAIL
#   - broken plugin (init-done missing / 0-byte)     → FAIL (plugin.init-done)
#   - broken plugin (OLD sentinel-era artifacts, no init-done) → FAIL
#       (the #1132 wrong-key case: the old key no longer satisfies)
#   - broken plugin (gitignore umbrella defeated)    → FAIL
#   - broken plugin (invalid config JSON)            → FAIL
#   - broken plugin (R-b rules delivery missing)     → FAIL
#   - dual install                         → FAIL
#   - none                                 → FAIL
#
# #1132 single-path-definition discipline: the plugin fixtures derive every
# marker path/write from init-state.sh (sourced BY the lib itself) and use
# its WRITER (zskills_write_init_markers) — never a re-typed literal.
#
# Sandbox-only: every consumer dir lives under $TMP; the real repo / $HOME are
# never written. The verifier is read-only (it only inspects files), so even
# the source-tree paths it might read are untouched.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

LIB="$REPO_ROOT/skills/update-zskills/verifiers/verify-install-lib.sh"
ENTRY="$REPO_ROOT/skills/update-zskills/verifiers/verify-install.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '  PASS %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '  FAIL %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The lib must exist and be sourceable.
if [ ! -f "$LIB" ]; then
  fail "0. lib present" "verify-install-lib.sh missing at $LIB"
  echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
  exit 1
fi
# shellcheck source=../skills/update-zskills/verifiers/verify-install-lib.sh
. "$LIB"
pass "0. verify-install-lib.sh sourceable"

# ── Congruence pin (INSTALL_REDESIGN Phase 6b, #1132): sourcing the lib must
# have transitively loaded init-state.sh (the SINGLE path definition the
# plugin-lane checks key on). The fixture builder below uses init-state.sh's
# OWN writer + path vars — congruence by construction, the fixture and the
# lib cannot drift. (Subject-removal note: the Phase-3 VI_PLUGIN_ARTIFACTS
# materialised-artifact set this pin used to lock was retired with the
# sentinel-keyed plugin checks — the artifact set is no longer a subject.)
if command -v zskills_init_done_present >/dev/null 2>&1 \
   && command -v zskills_write_init_markers >/dev/null 2>&1 \
   && [ -n "${ZSKILLS_INIT_DONE_REL:-}" ] && [ -n "${ZSKILLS_SETUP_CONFIRMED_REL:-}" ]; then
  pass "0b. lib transitively sources init-state.sh (predicate + writer + marker paths available to fixtures)"
else
  fail "0b. init-state congruence" "init-state.sh definitions not loaded by sourcing the lib"
fi

# ── Result helpers ──────────────────────────────────────────────────────────
# Run vi_run_cheap in THIS shell (no subshell) so VI_PASS/WARN/FAIL accumulate,
# capturing the records to a file for content assertions.
run_cheap_capture() {
  local proj="$1" out="$2"
  vi_reset
  vi_run_cheap "$proj" > "$out"
}

# git_init_fixture <dir> — make a synthetic fixture a real git repo so the
# lane-agnostic env check (vi_check_env, #1119) sees a work tree and emits the
# env.git-repo PASS instead of a WARN. A REAL zskills install always sits in a
# git repo; the synthetic $TMP fixtures are not repos by default, so the
# zero-WARN assertions (3c/4c) require this. We do NOT weaken those assertions —
# we make the fixture match reality.
git_init_fixture() {
  git -C "$1" init -q >/dev/null 2>&1
  git -C "$1" config user.email t@t >/dev/null 2>&1 || true
  git -C "$1" config user.name t >/dev/null 2>&1 || true
}

# Count FAIL records in a captured output file.
count_fail() { grep -c '^FAIL' "$1" 2>/dev/null || echo 0; }
# Does the captured output contain a FAIL whose id matches $2?
has_fail_id() { grep -q "^FAIL	$2	" "$1"; }
# Does the captured output contain a WARN whose id matches $2?
has_warn_id() { grep -q "^WARN	$2	" "$1"; }

# ── Synthetic LEGACY install builder ────────────────────────────────────────
# Produces a consumer dir with: a populated .claude/skills/, a settings.json
# registering a hook whose file EXISTS on disk, a rendered managed.md with NO
# placeholders, and a zskills-config.json. This is a "working" legacy install.
make_legacy_good() {
  local c="$TMP/legacy-good-$1"
  rm -rf -- "$c"
  mkdir -p "$c/.claude/skills/update-zskills" \
           "$c/.claude/hooks" \
           "$c/.claude/rules/zskills"
  printf '%s\n' '---' 'name: update-zskills' '---' '# Update Z Skills' \
    > "$c/.claude/skills/update-zskills/SKILL.md"
  # Real hook files the registration will point at. A HEALTHY legacy install
  # always registers the canonical safety-hook set (#1008 F1), and each shipped
  # zskills hook carries a line-2 `# zskills-hook-version:` stamp (the integrity
  # check the verifier now enforces, #1008 medium gaps). Seed all four canonical
  # hooks, version-stamped + non-empty.
  local h
  for h in block-unsafe-generic block-unsafe-project block-stale-skill-version block-agents; do
    printf '%s\n' '#!/usr/bin/env bash' "# zskills-hook-version: 2026.06.0" 'exit 0' \
      > "$c/.claude/hooks/$h.sh"
  done
  # settings.json registering the canonical set via the canonical command form.
  cat > "$c/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [
        { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/block-unsafe-generic.sh\"", "timeout": 5 },
        { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/block-unsafe-project.sh\"", "timeout": 5 },
        { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/block-stale-skill-version.sh\"", "timeout": 5 }
      ] },
      { "matcher": "Agent", "hooks": [
        { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/block-agents.sh\"", "timeout": 5 }
      ] }
    ]
  }
}
JSON
  # Rendered managed.md — no TODO placeholders.
  printf '%s\n' '# acme — Agent Reference' '' 'Rendered rules, no placeholders.' \
    > "$c/.claude/rules/zskills/managed.md"
  cat > "$c/.claude/zskills-config.json" <<'JSON'
{ "project_name": "acme", "zskills_version": "2026.06.0" }
JSON
  echo "$c"
}

# ── Synthetic PLUGIN install builder (init-era, Phase 6b) ───────────────────
# Produces a healthy POST-INIT mirror-less plugin consumer: a git repo whose
# .gitignore carries the .zskills/ umbrella, with the init markers written by
# init-state.sh's OWN writer (#1132 — never a re-typed path), and a valid
# config (the config is OPTIONAL; the zero-config case removes it). The lane
# keys on CLAUDE_PLUGIN_ROOT in env, exported around the plugin cases below.
make_plugin_good() {
  local c="$TMP/plugin-good-$1"
  rm -rf -- "$c"
  mkdir -p "$c/.claude"
  git_init_fixture "$c"
  printf '%s\n' '.zskills/' > "$c/.gitignore"
  zskills_write_init_markers "$c" "2026.06.0" \
    || fail "fixture plugin-good-$1" "init-state.sh writer failed"
  cat > "$c/.claude/zskills-config.json" <<'JSON'
{ "project_name": "acme", "zskills_version": "2026.06.0" }
JSON
  echo "$c"
}

echo "=== verify-install: synthetic good + broken installs ==="

# ── LEGACY: good install → no FAIL ──────────────────────────────────────────
LG="$(make_legacy_good 1)"
OUT="$TMP/out-legacy-good.txt"
run_cheap_capture "$LG" "$OUT"
if [ "$VI_FAIL" -eq 0 ]; then
  pass "1. good legacy install → 0 FAIL (lane detected, all cheap checks pass)"
else
  fail "1. good legacy install" "expected 0 FAIL, got $(grep '^FAIL' "$OUT")"
fi
# Sanity: the lane was actually detected as legacy (proves we ran the right tier).
if grep -q '^PASS	lane.detect	detected lane: legacy' "$OUT"; then
  pass "1b. good legacy install → lane detected as legacy"
else
  fail "1b. good legacy lane detect" "lane.detect record not 'legacy': $(grep lane.detect "$OUT")"
fi

# ── LEGACY broken (A): delete the registered hook FILE → hooks-resolve FAIL ──
LB="$(make_legacy_good 2)"
rm -f "$LB/.claude/hooks/block-unsafe-generic.sh"
OUT="$TMP/out-legacy-broken-hook.txt"
run_cheap_capture "$LB" "$OUT"
if [ "$VI_FAIL" -gt 0 ] && has_fail_id "$OUT" "legacy.hooks-resolve"; then
  pass "2. broken legacy (registered hook file deleted) → FAIL on legacy.hooks-resolve"
else
  fail "2. broken legacy hook-resolve" "expected FAIL on legacy.hooks-resolve; VI_FAIL=$VI_FAIL records=$(grep '^FAIL' "$OUT")"
fi

# ── LEGACY valid + UNSET optional config (#1004): managed.md carries the ─────
# renderer's DESIGNED `<!-- TODO -->` placeholders for unset OPTIONAL config
# (dev_server.cmd, ui.auth_bypass, testing.file_patterns, …). This is the
# common real-world case — and ALWAYS the case for projects with no dev server
# / no web-app auth gate. It is a VALID install and must PASS with 0 FAIL.
# This is the recurrence-proof case the original clean-managed.md fixture
# missed (the false-FAIL #1004 reported).
LV="$(make_legacy_good 3)"
cat > "$LV/.claude/rules/zskills/managed.md" <<'MD'
# acme — Agent Reference

## Dev Server
<!-- TODO: dev_server.cmd not set in .claude/zskills-config.json -->

**Auth gate:**
<!-- TODO: ui.auth_bypass not set in .claude/zskills-config.json -->

### Test files
<!-- TODO: testing.file_patterns is empty -->

## Architecture
<!-- TODO: SOURCE_LAYOUT has no config field; fill in project's architecture summary -->
MD
OUT="$TMP/out-legacy-valid-unset-optional.txt"
run_cheap_capture "$LV" "$OUT"
if [ "$VI_FAIL" -eq 0 ]; then
  pass "3. valid legacy install with UNSET optional config (<!-- TODO --> placeholders present) → 0 FAIL"
else
  fail "3. valid legacy unset-optional" "expected 0 FAIL on designed <!-- TODO --> placeholders, got $(grep '^FAIL' "$OUT")"
fi
# And it must PASS the managed-rendered check specifically (not merely avoid FAIL).
if has_fail_id "$OUT" "legacy.managed-rendered" || has_fail_id "$OUT" "legacy.managed-present"; then
  fail "3b. valid legacy unset-optional managed check" "managed.md check FAILed on designed placeholders: $(grep -E 'managed' "$OUT")"
else
  pass "3b. valid legacy unset-optional → managed.md check does not FAIL on <!-- TODO --> placeholders"
fi

# ── LEGACY valid + NO zskills_version (#1124): after the plugin.json fallback ─
# a complete clone almost always resolves a version (git tag → .claude-plugin/
# plugin.json), so a missing zskills_version is abnormal — surfaced as a WARN
# (never FAIL: it is not install breakage, only the version-skew nudge stays
# off). So this case must produce 0 FAIL but exactly the legacy.version-recorded
# WARN.
LNV="$(make_legacy_good 4)"
cat > "$LNV/.claude/zskills-config.json" <<'JSON'
{ "project_name": "acme" }
JSON
# A real legacy install lives in a git repo — init the fixture so the
# lane-agnostic env.git-repo check (#1119) PASSes, isolating the version WARN.
git_init_fixture "$LNV"
OUT="$TMP/out-legacy-no-version.txt"
run_cheap_capture "$LNV" "$OUT"
if [ "$VI_FAIL" -eq 0 ]; then
  pass "3c. valid legacy install with NO zskills_version → 0 FAIL (missing version is WARN, never FAIL)"
else
  fail "3c. valid legacy no-version" "expected 0 FAIL; FAIL=$(grep '^FAIL' "$OUT")"
fi
if has_warn_id "$OUT" "legacy.version-recorded"; then
  pass "3d. legacy.version-recorded → WARN when zskills_version absent (#1124 plugin.json fallback makes absence abnormal)"
else
  fail "3d. legacy version-recorded WARN" "expected WARN on legacy.version-recorded; records=$(grep -E '^(WARN|FAIL)' "$OUT")"
fi

# ── LEGACY valid + zskills_version PRESENT (#1124): the recorded version is ───
# reported as a PASS on legacy.version-recorded, with NO WARN on that id. Uses
# the good-install fixture (its config carries zskills_version: 2026.06.0).
LVV="$(make_legacy_good 4b)"
git_init_fixture "$LVV"
OUT="$TMP/out-legacy-version-present.txt"
run_cheap_capture "$LVV" "$OUT"
if grep -q '^PASS	legacy.version-recorded	zskills_version recorded: 2026.06.0' "$OUT"; then
  pass "3d2. legacy.version-recorded → PASS reporting the recorded version when present"
else
  fail "3d2. legacy version-recorded PASS" "expected PASS reporting 2026.06.0; records=$(grep version-recorded "$OUT")"
fi
if has_warn_id "$OUT" "legacy.version-recorded"; then
  fail "3d3. legacy version-recorded no WARN when present" "unexpected WARN: $(grep version-recorded "$OUT")"
else
  pass "3d3. legacy.version-recorded → no WARN when zskills_version present"
fi

# ── LEGACY broken (B): a raw, UN-substituted {{TOKEN}} in managed.md → FAIL ───
# This is the ONLY managed.md content that means "the renderer never ran" — a
# copied-but-unrendered template. The renderer itself RAISES on a surviving
# {{...}}, so this can never appear in a real render; its presence is genuine
# breakage and MUST FAIL.
LB2="$(make_legacy_good 5)"
printf '%s\n' '# rules' 'Auth bypass: {{AUTH_BYPASS}}' \
  > "$LB2/.claude/rules/zskills/managed.md"
OUT="$TMP/out-legacy-broken-unrendered.txt"
run_cheap_capture "$LB2" "$OUT"
if [ "$VI_FAIL" -gt 0 ] && has_fail_id "$OUT" "legacy.managed-rendered"; then
  pass "3e. broken legacy (raw {{TOKEN}} in managed.md, renderer never ran) → FAIL on legacy.managed-rendered"
else
  fail "3e. broken legacy unrendered managed" "expected FAIL on legacy.managed-rendered; records=$(grep '^FAIL' "$OUT")"
fi

# ── LEGACY broken (C): a DE-HOOKED install — empty {"hooks":{}} (#1008 F1) ────
# Every zskills safety hook stripped from settings.json. This is the exact
# "install silently failed" case the verifier exists to catch; before the F1
# fix it false-PASSed with "all 0 registered hook commands resolve". MUST FAIL
# on legacy.hooks-resolve (zero registered hooks) AND legacy.canonical-hooks
# (canonical safety set absent).
LDH="$(make_legacy_good 6)"
printf '%s\n' '{"hooks":{}}' > "$LDH/.claude/settings.json"
OUT="$TMP/out-legacy-dehooked.txt"
run_cheap_capture "$LDH" "$OUT"
if [ "$VI_FAIL" -gt 0 ] && has_fail_id "$OUT" "legacy.hooks-resolve"; then
  pass "3f. de-hooked legacy (empty {\"hooks\":{}}) → FAIL on legacy.hooks-resolve (was a false-PASS pre-#1008)"
else
  fail "3f. de-hooked legacy hooks-resolve" "expected FAIL on legacy.hooks-resolve; records=$(grep '^FAIL' "$OUT")"
fi
if has_fail_id "$OUT" "legacy.canonical-hooks"; then
  pass "3g. de-hooked legacy → FAIL on legacy.canonical-hooks (canonical safety set absent)"
else
  fail "3g. de-hooked legacy canonical-hooks" "expected FAIL on legacy.canonical-hooks; records=$(grep '^FAIL' "$OUT")"
fi

# ── LEGACY broken (D): only NON-canonical hooks registered (#1008 F1) ─────────
# A non-zero hook count, but the canonical safety set is missing — the install
# registered only a foreign/non-safety hook. MUST FAIL on legacy.canonical-hooks
# even though legacy.hooks-resolve PASSes (the registered hook file exists).
LNC="$(make_legacy_good 7)"
printf '#!/usr/bin/env bash\nexit 0\n' > "$LNC/.claude/hooks/my-custom-hook.sh"
cat > "$LNC/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [
        { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/my-custom-hook.sh\"", "timeout": 5 }
      ] }
    ]
  }
}
JSON
OUT="$TMP/out-legacy-noncanonical.txt"
run_cheap_capture "$LNC" "$OUT"
if has_fail_id "$OUT" "legacy.canonical-hooks"; then
  pass "3h. only NON-canonical hook registered → FAIL on legacy.canonical-hooks"
else
  fail "3h. non-canonical-only canonical-hooks" "expected FAIL on legacy.canonical-hooks; records=$(grep '^FAIL' "$OUT")"
fi
# hooks-resolve must still PASS (the foreign hook file exists) — proving the
# canonical-hooks check is what catches it, not a resolve failure.
if has_fail_id "$OUT" "legacy.hooks-resolve"; then
  fail "3i. non-canonical-only hooks-resolve" "legacy.hooks-resolve should PASS (file exists); records=$(grep '^FAIL' "$OUT")"
else
  pass "3i. only NON-canonical hook registered → legacy.hooks-resolve still PASSes (resolve != canonical-set)"
fi

# ── LEGACY broken (E): a corrupt (0-byte) canonical hook (#1008 medium gap) ───
# A truncated `cp` leaves a registered zskills hook at 0 bytes. `[ -f ]` alone
# passed it; the integrity check (`[ -s ]`) must FAIL.
LEZ="$(make_legacy_good 12)"
: > "$LEZ/.claude/hooks/block-unsafe-generic.sh"   # truncate to 0 bytes
OUT="$TMP/out-legacy-empty-hook.txt"
run_cheap_capture "$LEZ" "$OUT"
if has_fail_id "$OUT" "legacy.hooks-integrity"; then
  pass "3j. corrupt 0-byte canonical hook → FAIL on legacy.hooks-integrity"
else
  fail "3j. empty-hook integrity" "expected FAIL on legacy.hooks-integrity; records=$(grep '^FAIL' "$OUT")"
fi

# ── LEGACY broken (F): a zskills hook missing its line-2 version stamp ────────
# A drifted/corrupt mirror whose zskills hook lacks the `# zskills-hook-version:`
# line-2 sentinel. MUST FAIL on legacy.hooks-integrity.
LNS="$(make_legacy_good 13)"
printf '%s\n' '#!/usr/bin/env bash' '# no version stamp here' 'exit 0' \
  > "$LNS/.claude/hooks/block-agents.sh"
OUT="$TMP/out-legacy-unstamped-hook.txt"
run_cheap_capture "$LNS" "$OUT"
if has_fail_id "$OUT" "legacy.hooks-integrity"; then
  pass "3k. zskills hook missing line-2 version stamp → FAIL on legacy.hooks-integrity"
else
  fail "3k. unstamped-hook integrity" "expected FAIL on legacy.hooks-integrity; records=$(grep '^FAIL' "$OUT")"
fi

# ── LEGACY valid + a FOREIGN hook registered alongside canonical (no FP) ──────
# A healthy install may register a consumer's OWN hook that legitimately carries
# NO `# zskills-hook-version:` stamp. The integrity check is scoped to zskills
# hooks, so the foreign hook must NOT trigger a FAIL — zero-false-positive bar.
LFH="$(make_legacy_good 14)"
printf '#!/usr/bin/env bash\necho hi\n' > "$LFH/.claude/hooks/consumer-own.sh"
cat > "$LFH/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [
        { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/block-unsafe-generic.sh\"", "timeout": 5 },
        { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/block-unsafe-project.sh\"", "timeout": 5 },
        { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/block-stale-skill-version.sh\"", "timeout": 5 },
        { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/consumer-own.sh\"", "timeout": 5 }
      ] },
      { "matcher": "Agent", "hooks": [
        { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/block-agents.sh\"", "timeout": 5 }
      ] }
    ]
  }
}
JSON
OUT="$TMP/out-legacy-foreign-hook.txt"
run_cheap_capture "$LFH" "$OUT"
if [ "$VI_FAIL" -eq 0 ]; then
  pass "3l. valid legacy + FOREIGN (unstamped) hook alongside canonical → 0 FAIL (integrity scoped to zskills hooks)"
else
  fail "3l. foreign-hook no-false-positive" "expected 0 FAIL; foreign unstamped hook should not trip integrity: $(grep '^FAIL' "$OUT")"
fi

# ── PLUGIN: good init-era layout → no FAIL ──────────────────────────────────
# The plugin lane keys on CLAUDE_PLUGIN_ROOT in env; export it for all plugin
# cases, with a fake plugin root carrying everything the reworked checks
# resolve: the two manifests, the skills tree anchor, and the R-b rules
# delivery surfaces (SessionStart hook registered + renderable).
PG="$(make_plugin_good 1)"
OUT="$TMP/out-plugin-good.txt"
CLAUDE_PLUGIN_ROOT="$TMP/fake-plugin-root"; export CLAUDE_PLUGIN_ROOT
mkdir -p "$CLAUDE_PLUGIN_ROOT/.claude-plugin" "$CLAUDE_PLUGIN_ROOT/hooks" \
         "$CLAUDE_PLUGIN_ROOT/skills/update-zskills" "$CLAUDE_PLUGIN_ROOT/scripts"
printf '{ "version": "2026.06.0" }\n' > "$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json"
cat > "$CLAUDE_PLUGIN_ROOT/hooks/hooks.json" <<'JSON'
{ "hooks": { "SessionStart": [ { "hooks": [
  { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/session-rules-context.sh\"", "timeout": 30 }
] } ] } }
JSON
printf '%s\n' '#!/usr/bin/env bash' '# zskills-hook-version: 2026.06.0' 'exit 0' \
  > "$CLAUDE_PLUGIN_ROOT/hooks/session-rules-context.sh"
printf '%s\n' '# rules template' > "$CLAUDE_PLUGIN_ROOT/CLAUDE_TEMPLATE.md"
printf '%s\n' '# renderer' > "$CLAUDE_PLUGIN_ROOT/scripts/render-managed-rules.py"
printf '%s\n' '---' 'name: update-zskills' '---' '# uz' \
  > "$CLAUDE_PLUGIN_ROOT/skills/update-zskills/SKILL.md"
run_cheap_capture "$PG" "$OUT"
if [ "$VI_FAIL" -eq 0 ]; then
  pass "4. good init-era plugin install → 0 FAIL (markers + gitignore umbrella + valid config, mirror-less)"
else
  fail "4. good plugin layout" "expected 0 FAIL, got $(grep '^FAIL' "$OUT")"
fi
if grep -q '^PASS	lane.detect	detected lane: plugin' "$OUT"; then
  pass "4b. good plugin layout → lane detected as plugin"
else
  fail "4b. good plugin lane detect" "lane.detect not 'plugin': $(grep lane.detect "$OUT")"
fi
# Version currency: fixture init-done records 2026.06.0 == plugin.json → PASS.
if grep -q '^PASS	plugin.version-currency	' "$OUT" && ! has_warn_id "$OUT" "plugin.version-currency"; then
  pass "4b2. matching init-done/plugin.json versions → plugin.version-currency PASS (no WARN)"
else
  fail "4b2. version-currency match" "expected PASS, no WARN; records=$(grep version-currency "$OUT")"
fi

# ── PLUGIN valid + NO config: zero-config is the DESIGNED default ───────────
# A post-init consumer who declined the config interview has no
# .claude/zskills-config.json at all — built-in defaults apply. MUST be
# 0 FAIL with plugin.config-valid PASSing on the absent-is-OK arm.
PNC="$(make_plugin_good 5)"
rm -f "$PNC/.claude/zskills-config.json"
OUT="$TMP/out-plugin-no-config.txt"
run_cheap_capture "$PNC" "$OUT"
if [ "$VI_FAIL" -eq 0 ] && grep -q '^PASS	plugin.config-valid	' "$OUT"; then
  pass "4c. zero-config plugin install (no config file) → 0 FAIL, plugin.config-valid PASS (absent is OK by design)"
else
  fail "4c. zero-config plugin" "expected 0 FAIL + config-valid PASS; records=$(grep -E '^(FAIL|.*config-valid)' "$OUT")"
fi

# ── PLUGIN version skew: init-done records an older version → WARN, never FAIL
# (the m-class staleness cure: nothing re-runs init after a marketplace
# update, so the record goes stale silently; the WARN names the bare
# /zs:update-zskills refresh). Marker re-written via the WRITER (#1132).
PVS="$(make_plugin_good 5b)"
zskills_write_init_markers "$PVS" "2020.01.0"
OUT="$TMP/out-plugin-version-skew.txt"
run_cheap_capture "$PVS" "$OUT"
if [ "$VI_FAIL" -eq 0 ]; then
  pass "4d. version-skewed plugin install → 0 FAIL (staleness is WARN, never FAIL)"
else
  fail "4d. version skew no-fail" "expected 0 FAIL; FAIL=$(grep '^FAIL' "$OUT")"
fi
if has_warn_id "$OUT" "plugin.version-currency" \
   && grep '^WARN	plugin.version-currency	' "$OUT" | grep -q 'update-zskills'; then
  pass "4d2. plugin.version-currency → WARN naming the bare /zs:update-zskills refresh on mismatch"
else
  fail "4d2. version-currency WARN" "expected WARN naming update-zskills; records=$(grep version-currency "$OUT")"
fi

# ── PLUGIN broken (A): init-done missing → FAIL (the not-initialised case) ───
PB="$(make_plugin_good 2)"
rm -f "$PB/$ZSKILLS_INIT_DONE_REL"
OUT="$TMP/out-plugin-broken-noinit.txt"
run_cheap_capture "$PB" "$OUT"
if [ "$VI_FAIL" -gt 0 ] && has_fail_id "$OUT" "plugin.init-done" \
   && grep '^FAIL	plugin.init-done	' "$OUT" | grep -q 'update-zskills'; then
  pass "5. broken plugin (init-done missing) → FAIL on plugin.init-done, naming the /zs:update-zskills cure"
else
  fail "5. broken plugin no-init" "expected FAIL on plugin.init-done naming the cure; records=$(grep '^FAIL' "$OUT")"
fi

# (A2) 0-byte init-done is a partial leftover (#1079) → same FAIL.
PB0="$(make_plugin_good 2b)"
: > "$PB0/$ZSKILLS_INIT_DONE_REL"
OUT="$TMP/out-plugin-broken-0byte.txt"
run_cheap_capture "$PB0" "$OUT"
if has_fail_id "$OUT" "plugin.init-done"; then
  pass "5b. broken plugin (0-byte init-done, partial leftover) → FAIL on plugin.init-done (#1079 predicate)"
else
  fail "5b. broken plugin 0-byte" "expected FAIL on plugin.init-done; records=$(grep '^FAIL' "$OUT")"
fi

# (A3) setup-confirmed missing → FAIL on its own check id.
PBS="$(make_plugin_good 2c)"
rm -f "$PBS/$ZSKILLS_SETUP_CONFIRMED_REL"
OUT="$TMP/out-plugin-broken-nosetup.txt"
run_cheap_capture "$PBS" "$OUT"
if has_fail_id "$OUT" "plugin.setup-confirmed"; then
  pass "5c. broken plugin (setup-confirmed missing) → FAIL on plugin.setup-confirmed"
else
  fail "5c. broken plugin no-setup-confirmed" "expected FAIL on plugin.setup-confirmed; records=$(grep '^FAIL' "$OUT")"
fi

# (A4 — the #1132 wrong-key case) OLD sentinel-era materialised artifacts
# present but NO init markers: a materialiser-era consumer who upgraded
# mid-window. The OLD key must NOT satisfy the reworked checks — still FAIL
# on plugin.init-done (self-curing: the message names /zs:update-zskills).
# The sentinel prefix + paths derive from init-state.sh's frozen
# legacy-residue constants — never re-typed.
PWK="$TMP/plugin-wrongkey"
rm -rf -- "$PWK"
mkdir -p "$PWK/.claude"
git_init_fixture "$PWK"
printf '%s\n' '.zskills/' > "$PWK/.gitignore"
for wk_rel in "${ZSKILLS_LEGACY_MATERIALISED_PATHS[@]}"; do
  mkdir -p "$PWK/$(dirname "$wk_rel")"
  case "$wk_rel" in
    *.sh) printf '%s\n' '#!/usr/bin/env bash' "# $ZSKILLS_LEGACY_SENTINEL_PREFIX 2026.06.0" 'exit 0' > "$PWK/$wk_rel" ;;
    *agents*) printf '%s\n' '---' "# $ZSKILLS_LEGACY_SENTINEL_PREFIX 2026.06.0" 'name: x' '---' 'body' > "$PWK/$wk_rel" ;;
    *) printf '%s\n' "<!-- $ZSKILLS_LEGACY_SENTINEL_PREFIX 2026.06.0 -->" '# rules' > "$PWK/$wk_rel" ;;
  esac
done
OUT="$TMP/out-plugin-wrongkey.txt"
run_cheap_capture "$PWK" "$OUT"
if has_fail_id "$OUT" "plugin.init-done"; then
  pass "5d. OLD sentinel-era artifacts WITHOUT init markers → still FAIL on plugin.init-done (wrong key no longer satisfies, #1132)"
else
  fail "5d. wrong-key regression" "expected FAIL on plugin.init-done; records=$(grep -E '^(PASS|FAIL)' "$OUT" | head -5)"
fi

# ── PRE-LOCK allowance (ZSKILLS_VI_PRE_LOCK=1 — the A6 hard-gate invocation) ──
# Inside init, A6 runs BEFORE A7 writes the markers (lock-LAST), so the init
# fence sets the knob: expected-absent markers report PASS-pending and a
# healthy mid-init consumer gates 0 FAIL...
PPL="$(make_plugin_good 2d)"
rm -f "$PPL/$ZSKILLS_INIT_DONE_REL" "$PPL/$ZSKILLS_SETUP_CONFIRMED_REL"
OUT="$TMP/out-plugin-prelock-good.txt"
vi_reset
ZSKILLS_VI_PRE_LOCK=1 vi_run_cheap "$PPL" > "$OUT"
if [ "$VI_FAIL" -eq 0 ]; then
  pass "5e. pre-lock invocation (knob=1, markers absent by design) → 0 FAIL (healthy mid-init consumer passes A6)"
else
  fail "5e. pre-lock good" "expected 0 FAIL; records=$(grep '^FAIL' "$OUT")"
fi
# ...but the knob suppresses NOTHING else (anti-hollow): a broken gitignore
# still FAILs under the knob — exactly what the A6 hard gate must catch.
PPB="$(make_plugin_good 2e)"
rm -f "$PPB/$ZSKILLS_INIT_DONE_REL" "$PPB/$ZSKILLS_SETUP_CONFIRMED_REL"
printf '%s\n' '!.zskills/' >> "$PPB/.gitignore"
OUT="$TMP/out-plugin-prelock-broken.txt"
vi_reset
ZSKILLS_VI_PRE_LOCK=1 vi_run_cheap "$PPB" > "$OUT"
if [ "$VI_FAIL" -gt 0 ] && has_fail_id "$OUT" "plugin.gitignore-umbrella"; then
  pass "5f. pre-lock knob does NOT suppress other checks — broken gitignore still FAILs under ZSKILLS_VI_PRE_LOCK=1"
else
  fail "5f. pre-lock anti-hollow" "expected gitignore FAIL under the knob; records=$(grep '^FAIL' "$OUT")"
fi
# And WITHOUT the knob, absent markers are a genuine FAIL (5/5b/5c above
# already pin this; this re-run on the same fixture isolates the knob).
OUT="$TMP/out-plugin-noknob.txt"
run_cheap_capture "$PPL" "$OUT"
if has_fail_id "$OUT" "plugin.init-done" && has_fail_id "$OUT" "plugin.setup-confirmed"; then
  pass "5g. same fixture WITHOUT the knob → marker absences FAIL (the allowance is opt-in, init-fence-only)"
else
  fail "5g. knob isolation" "expected marker FAILs without the knob; records=$(grep '^FAIL' "$OUT")"
fi

# ── PLUGIN broken (B): gitignore umbrella defeated → FAIL ────────────────────
# A negative override after the umbrella entry (last match wins) leaves
# .zskills/ paths un-ignored — exactly what init's gitignore-first step
# guards against; the standing check must catch later regressions too.
PB2="$(make_plugin_good 3)"
printf '%s\n' '!.zskills/' >> "$PB2/.gitignore"
OUT="$TMP/out-plugin-broken-gitignore.txt"
run_cheap_capture "$PB2" "$OUT"
if [ "$VI_FAIL" -gt 0 ] && has_fail_id "$OUT" "plugin.gitignore-umbrella"; then
  pass "6. broken plugin (gitignore umbrella overridden) → FAIL on plugin.gitignore-umbrella"
else
  fail "6. broken plugin gitignore" "expected FAIL on plugin.gitignore-umbrella; records=$(grep '^FAIL' "$OUT")"
fi

# ── PLUGIN broken (C): config present but INVALID JSON → FAIL ────────────────
# (valid-if-present: absence is fine — case 4c — but a present, unparsable
# config silently breaks every reader and must FAIL.)
PB5="$(make_plugin_good 3b)"
printf '%s\n' '{ not json' > "$PB5/.claude/zskills-config.json"
OUT="$TMP/out-plugin-broken-config.txt"
run_cheap_capture "$PB5" "$OUT"
if has_fail_id "$OUT" "plugin.config-valid"; then
  pass "6b. broken plugin (config present but invalid JSON) → FAIL on plugin.config-valid"
else
  fail "6b. broken plugin config" "expected FAIL on plugin.config-valid; records=$(grep '^FAIL' "$OUT")"
fi

# ── PLUGIN broken (D): R-b rules delivery missing → FAIL ─────────────────────
# Point CLAUDE_PLUGIN_ROOT at a root whose hooks.json does NOT register
# session-rules-context.sh (manifests/skills otherwise fine) — rules would
# silently never arrive. Restore the good root afterwards.
PB6="$(make_plugin_good 3c)"
SAVED_PROOT="$CLAUDE_PLUGIN_ROOT"
CLAUDE_PLUGIN_ROOT="$TMP/fake-plugin-root-norules"; export CLAUDE_PLUGIN_ROOT
mkdir -p "$CLAUDE_PLUGIN_ROOT/.claude-plugin" "$CLAUDE_PLUGIN_ROOT/hooks" \
         "$CLAUDE_PLUGIN_ROOT/skills/update-zskills" "$CLAUDE_PLUGIN_ROOT/scripts"
printf '{ "version": "2026.06.0" }\n' > "$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json"
printf '{ "hooks": {} }\n' > "$CLAUDE_PLUGIN_ROOT/hooks/hooks.json"
printf '%s\n' '# rules template' > "$CLAUDE_PLUGIN_ROOT/CLAUDE_TEMPLATE.md"
printf '%s\n' '# renderer' > "$CLAUDE_PLUGIN_ROOT/scripts/render-managed-rules.py"
printf '%s\n' '---' 'name: update-zskills' '---' '# uz' \
  > "$CLAUDE_PLUGIN_ROOT/skills/update-zskills/SKILL.md"
OUT="$TMP/out-plugin-broken-rules.txt"
run_cheap_capture "$PB6" "$OUT"
if has_fail_id "$OUT" "plugin.rules-delivery"; then
  pass "6c. broken plugin (session-rules-context.sh not registered/present) → FAIL on plugin.rules-delivery"
else
  fail "6c. broken plugin rules" "expected FAIL on plugin.rules-delivery; records=$(grep '^FAIL' "$OUT")"
fi
CLAUDE_PLUGIN_ROOT="$SAVED_PROOT"; export CLAUDE_PLUGIN_ROOT

# ── PLUGIN broken (C): a .claude/skills/ mirror present → dual-install FAIL ──
# With CLAUDE_PLUGIN_ROOT set AND a legacy mirror, lane detection returns dual.
PB3="$(make_plugin_good 4)"
mkdir -p "$PB3/.claude/skills/update-zskills"
printf '%s\n' '---' 'name: update-zskills' '---' > "$PB3/.claude/skills/update-zskills/SKILL.md"
printf '{}\n' > "$PB3/.claude/settings.json"
OUT="$TMP/out-dual.txt"
run_cheap_capture "$PB3" "$OUT"
if [ "$VI_FAIL" -gt 0 ] && has_fail_id "$OUT" "lane.dual-unsupported"; then
  pass "7. dual install (plugin + legacy mirror) → FAIL on lane.dual-unsupported"
else
  fail "7. dual install" "expected FAIL on lane.dual-unsupported; records=$(grep '^FAIL' "$OUT")"
fi

# ── PLUGIN + consumer's OWN non-zskills skills → still plugin, mirror-less PASS
# (#1071) A healthy mirror-less plugin consumer may ship their OWN, non-zskills
# skills under .claude/skills/ (playwright-cli, social-seo, …). The lane-detect
# legacy signal and the plugin.mirror-less check key on a ZSKILLS-OWNED mirror,
# NOT on bare .claude/skills/ presence — so these MUST classify as `plugin`,
# PASS plugin.mirror-less (not WARN), and produce 0 FAIL. CLAUDE_PLUGIN_ROOT is
# still the good fake-plugin-root from case 4 (so plugin.root-reachable PASSes).
POS="$(make_plugin_good 7)"
mkdir -p "$POS/.claude/skills/playwright-cli" "$POS/.claude/skills/social-seo"
printf '%s\n' '---' 'name: playwright-cli' '---' '# pw' > "$POS/.claude/skills/playwright-cli/SKILL.md"
printf '%s\n' '---' 'name: social-seo' '---' '# seo' > "$POS/.claude/skills/social-seo/SKILL.md"
OUT="$TMP/out-plugin-own-skills.txt"
run_cheap_capture "$POS" "$OUT"
if grep -q '^PASS	lane.detect	detected lane: plugin' "$OUT"; then
  pass "7d. plugin + consumer's OWN non-zskills skills → lane detected as plugin (not dual/legacy)"
else
  fail "7d. plugin own-skills lane detect" "lane.detect not 'plugin': $(grep lane.detect "$OUT")"
fi
if has_warn_id "$OUT" "plugin.mirror-less"; then
  fail "7e. plugin own-skills mirror-less" "plugin.mirror-less WARNed on a non-zskills mirror (should PASS): $(grep mirror-less "$OUT")"
else
  pass "7e. plugin + own non-zskills skills → plugin.mirror-less PASS (not WARN on consumer's own skills)"
fi
if [ "$VI_FAIL" -eq 0 ]; then
  pass "7f. plugin + own non-zskills skills → 0 FAIL"
else
  fail "7f. plugin own-skills no-fail" "expected 0 FAIL, got $(grep '^FAIL' "$OUT")"
fi

# ── PLUGIN + consumer's OWN settings.json (non-zskills hook) → still plugin ───
# (#1071, the exact dual FALSE-FAIL) The consumer's own settings.json registers
# only a NON-zskills hook AND they ship their own skills. Before the fix this
# false-classified as `dual` → lane.dual-unsupported FAIL. The legacy signal now
# keys on a zskills-owned mirror OR a settings.json hook under .claude/hooks/,
# so a foreign hook outside .claude/hooks/ (or an empty {}) does NOT count. MUST
# classify as `plugin` (NOT dual), with 0 FAIL.
PCS="$(make_plugin_good 8)"
mkdir -p "$PCS/.claude/skills/playwright-cli"
printf '%s\n' '---' 'name: playwright-cli' '---' '# pw' > "$PCS/.claude/skills/playwright-cli/SKILL.md"
# A consumer's own settings.json registering only a NON-zskills hook whose path
# does NOT resolve under .claude/hooks/ (lives in their own .config/ tree).
cat > "$PCS/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [
        { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.config/my-own-hook.sh\"", "timeout": 5 }
      ] }
    ]
  }
}
JSON
OUT="$TMP/out-plugin-own-settings.txt"
run_cheap_capture "$PCS" "$OUT"
if grep -q '^PASS	lane.detect	detected lane: plugin' "$OUT"; then
  pass "7g. plugin + consumer's OWN settings.json (non-zskills hook) → lane plugin (not dual — the dual FALSE-FAIL)"
else
  fail "7g. plugin own-settings lane detect" "lane.detect not 'plugin': $(grep lane.detect "$OUT")"
fi
if has_fail_id "$OUT" "lane.dual-unsupported"; then
  fail "7h. plugin own-settings dual-false-fail" "lane.dual-unsupported FAILed on a consumer's own settings.json: $(grep '^FAIL' "$OUT")"
else
  pass "7h. plugin + own settings.json → NO lane.dual-unsupported FAIL (dual FALSE-FAIL closed)"
fi
if [ "$VI_FAIL" -eq 0 ]; then
  pass "7i. plugin + own settings.json (empty/non-zskills hook) → 0 FAIL"
else
  fail "7i. plugin own-settings no-fail" "expected 0 FAIL, got $(grep '^FAIL' "$OUT")"
fi

# ── GENUINE dual: zskills-named mirror + settings.json with a REAL zskills ────
# .claude/hooks/ entry → must STILL be `dual` (proves the fix does not blind the
# verifier to a real dual install). Both legacy signals fire: a zskills-owned
# mirror (update-zskills) AND a settings.json hook resolving under .claude/hooks/.
PGD="$(make_plugin_good 9)"
mkdir -p "$PGD/.claude/skills/update-zskills" "$PGD/.claude/hooks"
printf '%s\n' '---' 'name: update-zskills' '---' '# uz' > "$PGD/.claude/skills/update-zskills/SKILL.md"
printf '%s\n' '#!/usr/bin/env bash' '# zskills-hook-version: 2026.06.0' 'exit 0' \
  > "$PGD/.claude/hooks/block-unsafe-generic.sh"
cat > "$PGD/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [
        { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/block-unsafe-generic.sh\"", "timeout": 5 }
      ] }
    ]
  }
}
JSON
OUT="$TMP/out-genuine-dual.txt"
run_cheap_capture "$PGD" "$OUT"
if grep -q '^PASS	lane.detect	detected lane: dual' "$OUT" \
   || grep -q '^FAIL	lane.detect	detected lane: dual' "$OUT"; then
  pass "7j. genuine dual (zskills mirror + real .claude/hooks/ settings entry) → lane detected as dual"
else
  fail "7j. genuine dual lane detect" "lane.detect not 'dual': $(grep lane.detect "$OUT")"
fi
if has_fail_id "$OUT" "lane.dual-unsupported"; then
  pass "7k. genuine dual → FAIL on lane.dual-unsupported (fix does not blind the verifier to a real dual install)"
else
  fail "7k. genuine dual unsupported" "expected FAIL on lane.dual-unsupported; records=$(grep '^FAIL' "$OUT")"
fi

# ── PLUGIN broken (E): CLAUDE_PLUGIN_ROOT pointing at an UNREACHABLE dir ──────
# (#1008 medium gap) The consumer side is healthy (init markers present), but
# ${CLAUDE_PLUGIN_ROOT} points at a dir missing the plugin manifests — so the
# live skills/hooks resolve to NOTHING. MUST FAIL on plugin.root-reachable
# even though the init-marker checks PASS.
PB4="$(make_plugin_good 6)"
SAVED_PROOT="$CLAUDE_PLUGIN_ROOT"
CLAUDE_PLUGIN_ROOT="$TMP/empty-plugin-root"; export CLAUDE_PLUGIN_ROOT
mkdir -p "$CLAUDE_PLUGIN_ROOT"   # exists but has no .claude-plugin/ or hooks/
OUT="$TMP/out-plugin-unreachable.txt"
run_cheap_capture "$PB4" "$OUT"
if [ "$VI_FAIL" -gt 0 ] && has_fail_id "$OUT" "plugin.root-reachable"; then
  pass "7b. plugin root unreachable (no plugin.json/hooks.json) → FAIL on plugin.root-reachable"
else
  fail "7b. plugin root unreachable" "expected FAIL on plugin.root-reachable; records=$(grep '^FAIL' "$OUT")"
fi
# The init-marker checks must still PASS — proving root-reachable is what
# catches it, not a consumer-side breakage.
if grep -q '^PASS	plugin.init-done	' "$OUT"; then
  pass "7c. plugin root unreachable → plugin.init-done still PASSes (root-reachable is the catcher)"
else
  fail "7c. unreachable-root init checks" "plugin.init-done should PASS (markers present); records=$(grep init-done "$OUT")"
fi
CLAUDE_PLUGIN_ROOT="$SAVED_PROOT"; export CLAUDE_PLUGIN_ROOT

# ── plugin.mirror-less WARN wording (defensive direct-call surface) ──────────
# Via vi_run_cheap a zskills mirror + plugin env collapses to `dual`
# upstream, so drive vi_check_plugin DIRECTLY on a mirror-carrying consumer
# and pin the WARN's cure wording: it must recommend the
# uninstall-one-install-the-other model and NEVER the retired lane-switch
# script (Phase 6b kills the old switch-script recommendation in this
# region; the sibling lane.dual-unsupported mention is Phase 7's lockstep).
PMW="$(make_plugin_good 10)"
mkdir -p "$PMW/.claude/skills/update-zskills"
printf '%s\n' '---' 'name: update-zskills' '---' '# uz' > "$PMW/.claude/skills/update-zskills/SKILL.md"
OUT="$TMP/out-plugin-mirror-warn.txt"
vi_reset; vi_check_plugin "$PMW" > "$OUT"
if has_warn_id "$OUT" "plugin.mirror-less" \
   && grep '^WARN	plugin.mirror-less	' "$OUT" | grep -q 'uninstall' \
   && ! grep '^WARN	plugin.mirror-less	' "$OUT" | grep -qi 'switch'; then
  pass "7l. plugin.mirror-less WARN recommends uninstall-one-lane, never the retired switch script"
else
  fail "7l. mirror-less WARN wording" "records=$(grep mirror-less "$OUT")"
fi

unset CLAUDE_PLUGIN_ROOT

# ── NONE: empty consumer, no plugin env → FAIL ──────────────────────────────
NC="$TMP/none-consumer"
mkdir -p "$NC/.claude"
OUT="$TMP/out-none.txt"
run_cheap_capture "$NC" "$OUT"
if [ "$VI_FAIL" -gt 0 ] && has_fail_id "$OUT" "lane.none"; then
  pass "8. no install (empty consumer, no plugin env) → FAIL on lane.none"
else
  fail "8. no install" "expected FAIL on lane.none; records=$(grep '^FAIL' "$OUT")"
fi

# ── Entry script end-to-end: good legacy → exit 0; broken → exit 1 ──────────
LG2="$(make_legacy_good 9)"
if bash "$ENTRY" --project-dir "$LG2" >/dev/null 2>&1; then
  pass "9a. entry script: good legacy install → exit 0"
else
  fail "9a. entry good legacy exit" "expected exit 0"
fi
LB3="$(make_legacy_good 10)"
rm -f "$LB3/.claude/hooks/block-unsafe-generic.sh"
if bash "$ENTRY" --project-dir "$LB3" >/dev/null 2>&1; then
  fail "9b. entry broken legacy exit" "expected exit 1 (FAIL), got exit 0"
else
  pass "9b. entry script: broken legacy install → exit 1"
fi

# ── Heavy tier is opt-in and inert: --deep WARNs, never FAILs on a good install
LG3="$(make_legacy_good 11)"
DEEP_OUT="$(bash "$ENTRY" --project-dir "$LG3" --deep 2>&1)"
if printf '%s\n' "$DEEP_OUT" | grep -q 'heavy tier' \
   && printf '%s\n' "$DEEP_OUT" | grep -qE 'Overall: PASS'; then
  pass "10. --deep runs the heavy tier (opt-in) and does not turn a good install into FAIL"
else
  fail "10. --deep opt-in" "expected heavy-tier section + Overall: PASS on a good install"
fi

# ── vi_check_env (#1119): lane-agnostic environment report ───────────────────
# Positive coverage for the new env checks. They run unconditionally in
# vi_run_cheap; here we drive vi_check_env directly with a controlled PATH to
# assert each branch: git-binary FAIL when git is absent, git-repo WARN on a
# non-repo dir, gh WARN when gh is absent. Each runs in a `( ... )` subshell so
# the manipulated PATH and the lib's vi_emit counter mutations are scoped.

# (11a) git binary absent → env.git-binary FAIL. Build a PATH stub dir that
# carries everything EXCEPT git (so `command -v git` misses but the rest of the
# check function still works), then re-source the lib so VI_PY re-resolves under
# the stubbed PATH.
ENVTMP="$TMP/envcheck"
mkdir -p "$ENVTMP/proj"
git_init_fixture "$ENVTMP/proj"
# 11a — git absent.
( STUB="$TMP/nogit-bin"; mkdir -p "$STUB"
  for t in bash sed grep head printf cat dirname basename env python3 gh; do
    p="$(command -v "$t" 2>/dev/null)"; [ -n "$p" ] && ln -sf "$p" "$STUB/$t"
  done
  PATH="$STUB"
  out11a="$TMP/env-nogit.txt"
  vi_reset; vi_check_env "$ENVTMP/proj" > "$out11a" 2>/dev/null
  if grep -q '^FAIL	env.git-binary	' "$out11a"; then
    pass "11a. vi_check_env: git binary absent → env.git-binary FAIL"
  else
    fail "11a. env git absent" "expected env.git-binary FAIL; got $(cat "$out11a")"
  fi
)

# (11b) project dir is NOT a git repo → env.git-repo WARN (with git present).
out11b="$TMP/env-nonrepo.txt"
NONREPO="$TMP/env-nonrepo-dir"; mkdir -p "$NONREPO"
vi_reset; vi_check_env "$NONREPO" > "$out11b" 2>/dev/null
if grep -q '^WARN	env.git-repo	' "$out11b"; then
  pass "11b. vi_check_env: non-repo project dir → env.git-repo WARN"
else
  fail "11b. env non-repo" "expected env.git-repo WARN; got $(cat "$out11b")"
fi
# And a real git repo PASSes env.git-repo (the inverse — proves the WARN is
# conditional, not unconditional).
out11b2="$TMP/env-repo.txt"
vi_reset; vi_check_env "$ENVTMP/proj" > "$out11b2" 2>/dev/null
if grep -q '^PASS	env.git-repo	' "$out11b2"; then
  pass "11b2. vi_check_env: git-repo project dir → env.git-repo PASS"
else
  fail "11b2. env repo" "expected env.git-repo PASS; got $(cat "$out11b2")"
fi

# (11c) gh absent → env.gh WARN (git still present, so no git FAIL).
( STUB="$TMP/nogh-bin"; mkdir -p "$STUB"
  for t in bash sed grep head printf cat dirname basename env python3 git; do
    p="$(command -v "$t" 2>/dev/null)"; [ -n "$p" ] && ln -sf "$p" "$STUB/$t"
  done
  PATH="$STUB"
  out11c="$TMP/env-nogh.txt"
  vi_reset; vi_check_env "$ENVTMP/proj" > "$out11c" 2>/dev/null
  if grep -q '^WARN	env.gh	' "$out11c" && ! grep -q '^FAIL	env.git-binary	' "$out11c"; then
    pass "11c. vi_check_env: gh absent → env.gh WARN (git still PASSes)"
  else
    fail "11c. env gh absent" "expected env.gh WARN + no git-binary FAIL; got $(cat "$out11c")"
  fi
)

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
