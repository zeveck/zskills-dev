#!/usr/bin/env bash
# tests/test-switch-install-path.sh
#
# W5.6 / NEW (D25) — exercises scripts/switch-install-path.sh in BOTH
# directions on fixture projects, non-interactively
# (ZSKILLS_SWITCH_NONINTERACTIVE=1 skips the "type done" read-block), and
# asserts post-switch state:
#   - the lock file .claude/zskills-install-lane has the correct bare content
#     (`plugin\n` / `update-zskills\n`) and is written LAST;
#   - the right artifacts are stripped/materialised/preserved;
#   - basename-gated mirror removal does NOT touch consumer-authored skills;
#   - sentinel-gated plugin-artifact removal does NOT touch sentinel-less
#     (consumer / update-zskills-owned) files;
#   - .zskills/ runtime state is preserved across switches (lane-independent);
#   - no-op-with-INFO when already on the target lane;
#   - companion migrate-strip-settings.py strips .claude/hooks/ entries from
#     settings.json while preserving non-zskills entries.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

SWITCH="$REPO_ROOT/scripts/switch-install-path.sh"
STRIP="$REPO_ROOT/scripts/migrate-strip-settings.py"
PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
[ -f "$SWITCH" ] || { echo "ERROR: $SWITCH not found" >&2; exit 1; }
[ -n "$PYTHON" ] || { echo "ERROR: install Python 3" >&2; exit 1; }

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Pick a real zskills-owned skill basename + a consumer-authored one.
ZSKILLS_SKILL="run-plan"          # exists under skills/ → basename-gated removal
CONSUMER_SKILL="my-custom-skill"  # NOT zskills-owned → preserved
ZSKILLS_HOOK="block-stale-skill-version.sh"  # exists under hooks/

run_switch() {
  # $1 = mode flag; $2 = project dir; $3 = stderr/stdout capture file
  env ZSKILLS_SWITCH_NONINTERACTIVE=1 ZSKILLS_SWITCH_PROJECT_DIR="$2" \
    bash "$SWITCH" "$1" > "$3" 2>&1
}

write_settings_dual() {
  # settings.json with a zskills hook entry AND a non-zskills entry.
  local proj="$1"
  mkdir -p "$proj/.claude"
  cat > "$proj/.claude/settings.json" <<JSON
{
  "permissions": { "allow": ["Bash"] },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "bash \"\$CLAUDE_PROJECT_DIR/.claude/hooks/$ZSKILLS_HOOK\"", "timeout": 5 },
          { "type": "command", "command": "bash \"\$CLAUDE_PROJECT_DIR/scripts/my-own-hook.sh\"", "timeout": 5 }
        ]
      }
    ]
  }
}
JSON
}

# ── migrate-strip-settings.py unit checks ────────────────────────────────
echo "=== migrate-strip-settings.py ==="
PSET="$TMP/strip"
write_settings_dual "$PSET"
"$PYTHON" "$STRIP" "$PSET/.claude/settings.json" 2>/dev/null
# After strip: the .claude/hooks/ entry gone, the consumer scripts/ entry kept.
STRIP_CHECK="$("$PYTHON" - "$PSET/.claude/settings.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
hooks = d.get("hooks", {})
cmds = []
for ev in hooks.values():
    for m in ev:
        for h in m.get("hooks", []):
            cmds.append(h.get("command", ""))
has_zskills = any("/.claude/hooks/" in c for c in cmds)
has_consumer = any("my-own-hook.sh" in c for c in cmds)
has_perms = "permissions" in d
print(f"{has_zskills}\t{has_consumer}\t{has_perms}")
PY
)"
IFS=$'\t' read -r hz hc hp <<< "$STRIP_CHECK"
[ "$hz" = "False" ] && pass "strip: zskills .claude/hooks/ entry removed" || fail "strip: zskills entry survived"
[ "$hc" = "True" ] && pass "strip: non-zskills (consumer) hook entry preserved" || fail "strip: consumer entry lost"
[ "$hp" = "True" ] && pass "strip: unrelated settings keys (permissions) preserved" || fail "strip: permissions key lost"

# Idempotent re-run (no zskills entries left) → exit 0, no further removal.
"$PYTHON" "$STRIP" "$PSET/.claude/settings.json" 2>/dev/null && pass "strip: idempotent re-run exits 0" || fail "strip: re-run failed"

# ── --to-plugin direction ────────────────────────────────────────────────
echo ""
echo "=== switch-install-path.sh --to-plugin ==="
P1="$TMP/to-plugin"
mkdir -p "$P1/.claude/skills/$ZSKILLS_SKILL" "$P1/.claude/skills/$CONSUMER_SKILL" "$P1/.claude/hooks" "$P1/.claude/rules/zskills" "$P1/.zskills/tracking/PIPE"
printf '%s\n' '---' "name: $ZSKILLS_SKILL" '---' 'body' > "$P1/.claude/skills/$ZSKILLS_SKILL/SKILL.md"
printf '%s\n' '---' "name: $CONSUMER_SKILL" '---' 'body' > "$P1/.claude/skills/$CONSUMER_SKILL/SKILL.md"
printf '%s\n' '#!/usr/bin/env bash' '# zskills-hook-version: 2026.05.0' 'echo hi' > "$P1/.claude/hooks/$ZSKILLS_HOOK"
printf '%s\n' '#!/usr/bin/env bash' 'echo consumer-hook' > "$P1/.claude/hooks/my-own-hook.sh"
printf '%s\n' '# rules' > "$P1/.claude/rules/zskills/managed.md"
touch "$P1/.zskills/tracking/PIPE/marker"
write_settings_dual "$P1"

OUT1="$TMP/out1"
run_switch --to-plugin "$P1" "$OUT1"; rc=$?
[ "$rc" -eq 0 ] && pass "--to-plugin: exits 0" || { fail "--to-plugin exit $rc"; sed 's/^/      /' "$OUT1"; }
# Lock written LAST with bare `plugin\n`.
if [ -f "$P1/.claude/zskills-install-lane" ] && [ "$(cat "$P1/.claude/zskills-install-lane")" = plugin ]; then
  pass "--to-plugin: lock file content == 'plugin'"
else
  fail "--to-plugin: lock content wrong: $(cat "$P1/.claude/zskills-install-lane" 2>/dev/null)"
fi
# Lock LAST ordering: the lock-write log line appears AFTER the mirror-removal
# log lines in stdout.
if grep -q 'lock written LAST' "$OUT1"; then
  last_lock=$(grep -n 'lock written LAST' "$OUT1" | tail -1 | cut -d: -f1)
  last_rm=$(grep -n 'removed mirror' "$OUT1" | tail -1 | cut -d: -f1)
  if [ -n "$last_rm" ] && [ "$last_lock" -gt "$last_rm" ]; then
    pass "--to-plugin: lock written AFTER mirror removals (lock-LAST)"
  else
    fail "--to-plugin: lock-LAST ordering not observed (lock@$last_lock rm@$last_rm)"
  fi
fi
# zskills-owned mirror skill removed; consumer skill preserved.
[ ! -d "$P1/.claude/skills/$ZSKILLS_SKILL" ] && pass "--to-plugin: zskills mirror skill removed" || fail "--to-plugin: zskills mirror skill survived"
[ -d "$P1/.claude/skills/$CONSUMER_SKILL" ] && pass "--to-plugin: consumer-authored skill PRESERVED" || fail "--to-plugin: consumer skill wrongly removed"
# zskills-owned hook removed; consumer hook preserved.
[ ! -f "$P1/.claude/hooks/$ZSKILLS_HOOK" ] && pass "--to-plugin: zskills mirror hook removed" || fail "--to-plugin: zskills hook survived"
[ -f "$P1/.claude/hooks/my-own-hook.sh" ] && pass "--to-plugin: consumer-authored hook PRESERVED" || fail "--to-plugin: consumer hook wrongly removed"
# managed.md removed.
[ ! -f "$P1/.claude/rules/zskills/managed.md" ] && pass "--to-plugin: managed.md removed" || fail "--to-plugin: managed.md survived"
# settings.json stripped of zskills hook, consumer entry preserved.
if [ -f "$P1/.claude/settings.json" ] \
   && ! grep -q '/.claude/hooks/' "$P1/.claude/settings.json" \
   && grep -q 'my-own-hook.sh' "$P1/.claude/settings.json"; then
  pass "--to-plugin: settings.json stripped (zskills gone, consumer kept)"
else
  fail "--to-plugin: settings.json strip incorrect"
fi
# .zskills/ runtime state preserved (lane-independent).
[ -f "$P1/.zskills/tracking/PIPE/marker" ] && pass "--to-plugin: .zskills/ runtime state preserved" || fail "--to-plugin: .zskills/ wrongly touched"

# No-op when already on plugin lane.
OUT1b="$TMP/out1b"
run_switch --to-plugin "$P1" "$OUT1b"
grep -q 'Already on the plugin lane' "$OUT1b" && pass "--to-plugin: no-op-with-INFO when already plugin" || { fail "--to-plugin: not detected as no-op"; sed 's/^/      /' "$OUT1b"; }

# ── --to-update-zskills direction ────────────────────────────────────────
echo ""
echo "=== switch-install-path.sh --to-update-zskills ==="
P2="$TMP/to-uz"
mkdir -p "$P2/.claude/agents" "$P2/.claude/hooks" "$P2/.claude/rules/zskills" "$P2/.zskills"
# Sentinelled plugin-materialised artifacts (should be removed).
printf '%s\n' '---' '# zskills-materialised: 2026.05.0' 'name: verifier' '---' 'body' > "$P2/.claude/agents/verifier.md"
printf '%s\n' '#!/usr/bin/env bash' '# zskills-materialised: 2026.05.0' 'echo hi' > "$P2/.claude/hooks/inject-bash-timeout.sh"
printf '%s\n' '<!-- zskills-materialised: 2026.05.0 -->' '# rules' > "$P2/.claude/rules/zskills/managed.md"
# A sentinel-LESS implementer.md (consumer/update-zskills-owned) — must be kept.
printf '%s\n' '---' 'name: implementer' '---' 'body' > "$P2/.claude/agents/implementer.md"
touch "$P2/.zskills/keepme"

OUT2="$TMP/out2"
run_switch --to-update-zskills "$P2" "$OUT2"; rc=$?
[ "$rc" -eq 0 ] && pass "--to-update-zskills: exits 0" || { fail "--to-update-zskills exit $rc"; sed 's/^/      /' "$OUT2"; }
if [ -f "$P2/.claude/zskills-install-lane" ] && [ "$(cat "$P2/.claude/zskills-install-lane")" = update-zskills ]; then
  pass "--to-update-zskills: lock file content == 'update-zskills'"
else
  fail "--to-update-zskills: lock content wrong: $(cat "$P2/.claude/zskills-install-lane" 2>/dev/null)"
fi
# Lock LAST ordering vs sentinelled-removal log lines.
if grep -q 'lock written LAST' "$OUT2"; then
  last_lock=$(grep -n 'lock written LAST' "$OUT2" | tail -1 | cut -d: -f1)
  last_rm=$(grep -n 'removed sentinelled leftover' "$OUT2" | tail -1 | cut -d: -f1)
  if [ -n "$last_rm" ] && [ "$last_lock" -gt "$last_rm" ]; then
    pass "--to-update-zskills: lock written AFTER sentinelled removals (lock-LAST)"
  else
    fail "--to-update-zskills: lock-LAST ordering not observed (lock@$last_lock rm@$last_rm)"
  fi
fi
# Sentinelled artifacts removed.
[ ! -f "$P2/.claude/agents/verifier.md" ] && pass "--to-update-zskills: sentinelled verifier.md removed" || fail "--to-update-zskills: sentinelled verifier.md survived"
[ ! -f "$P2/.claude/hooks/inject-bash-timeout.sh" ] && pass "--to-update-zskills: sentinelled hook removed" || fail "--to-update-zskills: sentinelled hook survived"
[ ! -f "$P2/.claude/rules/zskills/managed.md" ] && pass "--to-update-zskills: sentinelled managed.md removed" || fail "--to-update-zskills: sentinelled managed.md survived"
# Sentinel-less implementer.md PRESERVED.
[ -f "$P2/.claude/agents/implementer.md" ] && pass "--to-update-zskills: sentinel-less implementer.md PRESERVED" || fail "--to-update-zskills: sentinel-less file wrongly removed"
# .zskills/ preserved.
[ -f "$P2/.zskills/keepme" ] && pass "--to-update-zskills: .zskills/ runtime state preserved" || fail "--to-update-zskills: .zskills/ wrongly touched"

# No-op when already on update-zskills lane.
OUT2b="$TMP/out2b"
run_switch --to-update-zskills "$P2" "$OUT2b"
grep -q 'Already on the /update-zskills lane' "$OUT2b" && pass "--to-update-zskills: no-op-with-INFO when already uz" || { fail "--to-update-zskills: not detected as no-op"; sed 's/^/      /' "$OUT2b"; }

# ── round-trip: --to-plugin then --to-update-zskills back ─────────────────
echo ""
echo "=== round-trip ==="
OUT3="$TMP/out3"
run_switch --to-update-zskills "$P1" "$OUT3"; rc=$?
[ "$rc" -eq 0 ] && [ "$(cat "$P1/.claude/zskills-install-lane")" = update-zskills ] \
  && pass "round-trip: plugin → update-zskills lock flips back" \
  || { fail "round-trip flip failed (rc=$rc, lock=$(cat "$P1/.claude/zskills-install-lane" 2>/dev/null))"; sed 's/^/      /' "$OUT3"; }

# ── bad usage ─────────────────────────────────────────────────────────────
echo ""
echo "=== usage ==="
OUT4="$TMP/out4"
env ZSKILLS_SWITCH_PROJECT_DIR="$TMP/x" bash "$SWITCH" --bogus > "$OUT4" 2>&1
rc=$?
[ "$rc" -eq 2 ] && grep -q 'usage:' "$OUT4" && pass "bad mode → usage + exit 2" || { fail "bad mode handling (rc=$rc)"; sed 's/^/      /' "$OUT4"; }

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
