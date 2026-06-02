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
#   - good legacy install            → verify_overall_rc == 0 (no FAIL)
#   - broken legacy (hook file gone) → FAIL
#   - broken legacy (managed.md TODO)→ FAIL
#   - good plugin layout             → no FAIL
#   - broken plugin (sentinel dropped)→ FAIL
#   - broken plugin (artifact dropped)→ FAIL
#   - dual install                   → FAIL
#   - none                           → FAIL
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
  # A real hook file the registration will point at.
  printf '#!/usr/bin/env bash\nexit 0\n' > "$c/.claude/hooks/block-unsafe-generic.sh"
  # settings.json registering that hook via the canonical command form.
  cat > "$c/.claude/settings.json" <<'JSON'
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

# ── LEGACY broken (B): leave a TODO placeholder in managed.md → FAIL ─────────
LB2="$(make_legacy_good 3)"
printf '%s\n' '# rules' '<!-- TODO: dev_server.cmd not set -->' \
  > "$LB2/.claude/rules/zskills/managed.md"
OUT="$TMP/out-legacy-broken-managed.txt"
run_cheap_capture "$LB2" "$OUT"
if [ "$VI_FAIL" -gt 0 ] && has_fail_id "$OUT" "legacy.managed-no-placeholders"; then
  pass "3. broken legacy (managed.md TODO placeholder) → FAIL on legacy.managed-no-placeholders"
else
  fail "3. broken legacy managed placeholder" "expected FAIL on legacy.managed-no-placeholders; records=$(grep '^FAIL' "$OUT")"
fi

# ── PLUGIN: good layout → no FAIL ───────────────────────────────────────────
# The plugin lane is keyed on CLAUDE_PLUGIN_ROOT being set. Set it (to any
# non-empty value) for these cases ONLY.
PG="$(make_plugin_good 1)"
OUT="$TMP/out-plugin-good.txt"
# The plugin lane keys on CLAUDE_PLUGIN_ROOT being set; export it (with a
# plugin.json so the version cross-check resolves) for all plugin cases.
CLAUDE_PLUGIN_ROOT="$TMP/fake-plugin-root"; export CLAUDE_PLUGIN_ROOT
mkdir -p "$CLAUDE_PLUGIN_ROOT/.claude-plugin"
printf '{ "version": "2026.06.0" }\n' > "$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json"
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
