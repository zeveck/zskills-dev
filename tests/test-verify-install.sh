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
#   - good legacy + NO zskills_version     → 0 FAIL / 0 WARN  (#1004 — Step F.5
#       legitimately skips writing it on an untagged source clone)
#   - broken legacy (hook file gone)       → FAIL
#   - broken legacy (raw {{TOKEN}})        → FAIL  (renderer never ran)
#   - good plugin layout                   → no FAIL
#   - good plugin + NO zskills_version     → 0 FAIL / 0 WARN  (#1004)
#   - broken plugin (sentinel dropped)     → FAIL
#   - broken plugin (artifact dropped)     → FAIL
#   - dual install                         → FAIL
#   - none                                 → FAIL
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

# ── Result helpers ──────────────────────────────────────────────────────────
# Run vi_run_cheap in THIS shell (no subshell) so VI_PASS/WARN/FAIL accumulate,
# capturing the records to a file for content assertions.
run_cheap_capture() {
  local proj="$1" out="$2"
  vi_reset
  vi_run_cheap "$proj" > "$out"
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

# ── Synthetic PLUGIN install builder ────────────────────────────────────────
# Produces a consumer dir with the 5 materialised artifacts, each carrying a
# `zskills-materialised:` sentinel, and NO .claude/skills/ mirror (mirror-less).
make_plugin_good() {
  local c="$TMP/plugin-good-$1"
  rm -rf -- "$c"
  mkdir -p "$c/.claude/agents" "$c/.claude/hooks" "$c/.claude/rules/zskills"
  # frontmatter .md artifacts — sentinel as YAML-comment first line in ---.
  for ag in verifier implementer; do
    printf '%s\n' '---' '# zskills-materialised: 2026.06.0' "name: $ag" '---' "# $ag" \
      > "$c/.claude/agents/$ag.md"
  done
  # *.sh artifacts — sentinel as shell-comment on line 2.
  for h in inject-bash-timeout verify-response-validate; do
    printf '%s\n' '#!/usr/bin/env bash' '# zskills-materialised: 2026.06.0' 'exit 0' \
      > "$c/.claude/hooks/$h.sh"
  done
  # plain .md managed.md — sentinel as HTML-comment first line.
  printf '%s\n' '<!-- zskills-materialised: 2026.06.0 -->' '# rules' \
    > "$c/.claude/rules/zskills/managed.md"
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

# ── LEGACY valid + NO zskills_version (#1004): an untagged source clone ───────
# legitimately leaves zskills_version unset (Step F.5 skips writing it). This
# must produce 0 FAIL AND 0 WARN — absence of a version is NOT install
# breakage, and must not even alarm with a WARN.
LNV="$(make_legacy_good 4)"
cat > "$LNV/.claude/zskills-config.json" <<'JSON'
{ "project_name": "acme" }
JSON
OUT="$TMP/out-legacy-no-version.txt"
run_cheap_capture "$LNV" "$OUT"
if [ "$VI_FAIL" -eq 0 ] && [ "$VI_WARN" -eq 0 ]; then
  pass "3c. valid legacy install with NO zskills_version → 0 FAIL / 0 WARN (no version-recorded check)"
else
  fail "3c. valid legacy no-version" "expected 0 FAIL / 0 WARN; FAIL=$(grep '^FAIL' "$OUT") WARN=$(grep '^WARN' "$OUT")"
fi
if has_warn_id "$OUT" "legacy.version-recorded" || has_fail_id "$OUT" "legacy.version-recorded"; then
  fail "3d. legacy version-recorded removed" "legacy.version-recorded check still present — should be cut per #1004"
else
  pass "3d. legacy.version-recorded check removed (no false-positive WARN on untagged clone)"
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

# ── PLUGIN: good layout → no FAIL ───────────────────────────────────────────
# The plugin lane is keyed on CLAUDE_PLUGIN_ROOT being set. Set it (to any
# non-empty value) for these cases ONLY.
PG="$(make_plugin_good 1)"
OUT="$TMP/out-plugin-good.txt"
# The plugin lane keys on CLAUDE_PLUGIN_ROOT being set; export it (with a
# plugin.json AND hooks/hooks.json so the #1008 reachability check resolves)
# for all plugin cases.
CLAUDE_PLUGIN_ROOT="$TMP/fake-plugin-root"; export CLAUDE_PLUGIN_ROOT
mkdir -p "$CLAUDE_PLUGIN_ROOT/.claude-plugin" "$CLAUDE_PLUGIN_ROOT/hooks"
printf '{ "version": "2026.06.0" }\n' > "$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json"
printf '{ "hooks": {} }\n' > "$CLAUDE_PLUGIN_ROOT/hooks/hooks.json"
run_cheap_capture "$PG" "$OUT"
if [ "$VI_FAIL" -eq 0 ]; then
  pass "4. good plugin layout → 0 FAIL (5 sentinelled artifacts, mirror-less)"
else
  fail "4. good plugin layout" "expected 0 FAIL, got $(grep '^FAIL' "$OUT")"
fi
if grep -q '^PASS	lane.detect	detected lane: plugin' "$OUT"; then
  pass "4b. good plugin layout → lane detected as plugin"
else
  fail "4b. good plugin lane detect" "lane.detect not 'plugin': $(grep lane.detect "$OUT")"
fi

# ── PLUGIN valid + NO zskills_version (#1004): plugin seed config has no tag ──
# A valid mirror-less plugin install whose seed config carries no zskills_version
# must produce 0 FAIL AND 0 WARN — same zero-false-positive bar as legacy.
PNV="$(make_plugin_good 5)"
cat > "$PNV/.claude/zskills-config.json" <<'JSON'
{ "project_name": "acme" }
JSON
OUT="$TMP/out-plugin-no-version.txt"
run_cheap_capture "$PNV" "$OUT"
if [ "$VI_FAIL" -eq 0 ] && [ "$VI_WARN" -eq 0 ]; then
  pass "4c. valid plugin install with NO zskills_version → 0 FAIL / 0 WARN (no version-recorded check)"
else
  fail "4c. valid plugin no-version" "expected 0 FAIL / 0 WARN; FAIL=$(grep '^FAIL' "$OUT") WARN=$(grep '^WARN' "$OUT")"
fi
if has_warn_id "$OUT" "plugin.version-recorded" || has_fail_id "$OUT" "plugin.version-recorded"; then
  fail "4d. plugin version-recorded removed" "plugin.version-recorded check still present — should be cut per #1004"
else
  pass "4d. plugin.version-recorded check removed (no false-positive WARN on untagged seed config)"
fi

# ── PLUGIN broken (A): strip a sentinel from one artifact → FAIL ─────────────
PB="$(make_plugin_good 2)"
# Rewrite verifier.md WITHOUT the sentinel line.
printf '%s\n' '---' 'name: verifier' '---' '# verifier' > "$PB/.claude/agents/verifier.md"
OUT="$TMP/out-plugin-broken-sentinel.txt"
run_cheap_capture "$PB" "$OUT"
if [ "$VI_FAIL" -gt 0 ] && has_fail_id "$OUT" "plugin.artifact.agents/verifier.md"; then
  pass "5. broken plugin (sentinel stripped from verifier.md) → FAIL on plugin.artifact.agents/verifier.md"
else
  fail "5. broken plugin sentinel" "expected FAIL on plugin.artifact.agents/verifier.md; records=$(grep '^FAIL' "$OUT")"
fi

# ── PLUGIN broken (B): drop an artifact entirely → FAIL ──────────────────────
PB2="$(make_plugin_good 3)"
rm -f "$PB2/.claude/hooks/inject-bash-timeout.sh"
OUT="$TMP/out-plugin-broken-missing.txt"
run_cheap_capture "$PB2" "$OUT"
if [ "$VI_FAIL" -gt 0 ] && has_fail_id "$OUT" "plugin.artifact.hooks/inject-bash-timeout.sh"; then
  pass "6. broken plugin (inject-bash-timeout.sh dropped) → FAIL on plugin.artifact.hooks/inject-bash-timeout.sh"
else
  fail "6. broken plugin missing artifact" "expected FAIL on plugin.artifact.hooks/inject-bash-timeout.sh; records=$(grep '^FAIL' "$OUT")"
fi

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

# ── PLUGIN broken (D): CLAUDE_PLUGIN_ROOT pointing at an UNREACHABLE dir ──────
# (#1008 medium gap) The 5 materialised artifacts are present in the consumer's
# .claude/, but ${CLAUDE_PLUGIN_ROOT} points at a dir missing the plugin
# manifests — so the live skills/hooks resolve to NOTHING. MUST FAIL on
# plugin.root-reachable even though every artifact check PASSes.
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
# Artifact checks must still PASS — proving root-reachable is what catches it.
if has_fail_id "$OUT" "plugin.artifact.agents/verifier.md"; then
  fail "7c. unreachable-root artifacts" "artifact checks should PASS (artifacts present); records=$(grep '^FAIL' "$OUT")"
else
  pass "7c. plugin root unreachable → artifact checks still PASS (root-reachable is the catcher)"
fi
CLAUDE_PLUGIN_ROOT="$SAVED_PROOT"; export CLAUDE_PLUGIN_ROOT

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

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
