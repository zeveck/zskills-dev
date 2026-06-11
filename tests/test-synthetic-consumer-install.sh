#!/usr/bin/env bash
# tests/test-synthetic-consumer-install.sh
#
# PLUGIN_LANE_VERIFICATION Phase 3 — Synthetic-consumer legacy-installer
# end-to-end.
#
# Net-new END-TO-END coverage: bootstrap a throwaway consumer repo in a
# mktemp sandbox and run the legacy `/update-zskills` install flow into it
# end-to-end — skill mirror (skills/<name> → .claude/skills/<name>), hook
# registration in a synthesized .claude/settings.json, and managed.md render
# — then assert the consumer ends up with a WORKING legacy install.
#
# WHY a net-new file (placement rationale):
#   The existing tests/test-update-zskills-*.sh each cover a SLICE of the
#   install flow and do NOT do the full end-to-end into one consumer dir:
#     - test-update-zskills-agent-install.sh : agent + 2 frontmatter hooks
#       only; explicitly does NOT touch settings.json (its oracle comment
#       says so).
#     - test-update-zskills-rerender.sh      : managed.md render + root
#       CLAUDE.md migration only; no skill mirror, no settings.json.
#     - test-update-zskills-migration.sh / -paths-migration.sh : path
#       migrations, not a fresh install.
#   None exercises mirror + settings.json hook registration + managed.md
#   render together. This file is that genuinely net-new combination. It
#   REUSES the oracle-function scaffold pattern (sandbox-bootstrap, oracle
#   functions transcribed from SKILL.md prose) rather than inventing an
#   install.sh — no standalone installer exists; the legacy flow is SKILL.md
#   prose.
#
# SCOPE: this file scopes to the legacy installer run end-to-end. (The D27
#   dual-install detection probe, the SessionStart materialiser, and their
#   WARN-site assertions were deleted in INSTALL_REDESIGN Phase 7 —
#   subject-removal; lane handling now lives in detect-install-state.sh's
#   surviving callers and the explicit /zs:update-zskills init.)
#
# Sandbox-only: never runs the installer against the real repo or real $HOME.
# A throwaway consumer + settings.json are synthesized inside $TMP.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PY="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
if [ -z "$PY" ]; then
  echo "ERROR: install Python 3 (or set ZSKILLS_PYTHON)" >&2
  exit 1
fi

# ──────────────────────────────────────────────────────────────────────────
# Oracle: render managed.md (transcribes SKILL.md Step B render — the same
# substitution the canonical render-managed-rules.py performs, scoped to the
# placeholders the fixture template uses).
# ──────────────────────────────────────────────────────────────────────────
render_managed() {
  local dir="$1"
  local template="$dir/CLAUDE_TEMPLATE.md"
  local config="$dir/.claude/zskills-config.json"
  local rules_dir="$dir/.claude/rules/zskills"
  local rules_file="$rules_dir/managed.md"
  [ -f "$template" ] || { echo "CLAUDE_TEMPLATE.md missing" >&2; return 1; }

  local cfg project_name dev_cmd timezone
  cfg=$(cat "$config" 2>/dev/null || echo "")
  project_name=""; dev_cmd=""; timezone=""
  if [[ "$cfg" =~ \"project_name\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    project_name="${BASH_REMATCH[1]}"
  fi
  if [[ "$cfg" =~ \"cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    dev_cmd="${BASH_REMATCH[1]}"
  fi
  if [[ "$cfg" =~ \"timezone\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    timezone="${BASH_REMATCH[1]}"
  fi

  local out
  out=$(cat "$template")
  out="${out//\{\{PROJECT_NAME\}\}/$project_name}"
  out="${out//\{\{DEV_SERVER_CMD\}\}/$dev_cmd}"
  out="${out//\{\{TIMEZONE\}\}/$timezone}"

  mkdir -p "$rules_dir"
  printf '%s' "$out" > "$rules_file"
  return 0
}

# ──────────────────────────────────────────────────────────────────────────
# Oracle: mirror a source skill tree (skills/<name> → .claude/skills/<name>).
# Transcribes the legacy-lane mirror behaviour (cp -a per SKILL.md prose:
# "mirrored .claude/skills/<zskills>/"). mirror-skill.sh is the release-time
# tool; the consumer-facing effect is a recursive copy preserving mode bits.
# ──────────────────────────────────────────────────────────────────────────
mirror_skill() {
  local portable="$1" project_dir="$2" name="$3"
  local src="$portable/skills/$name"
  local dst="$project_dir/.claude/skills/$name"
  [ -d "$src" ] || { echo "source skill $name missing in portable" >&2; return 1; }
  mkdir -p "$project_dir/.claude/skills"
  rm -rf -- "$dst"
  cp -a "$src" "$dst"
  echo "Mirrored skill: $name"
  return 0
}

# ──────────────────────────────────────────────────────────────────────────
# Oracle: register the canonical zskills-owned hook triples in
# .claude/settings.json (transcribes SKILL.md Step C algorithm steps 1-4:
# fresh file → Write minimal hooks block; surgical idempotent append; skip
# if command already present anywhere). Uses Python for JSON round-trip per
# the "no jq / Python is required" project convention.
#
# We register the subset of canonical triples whose hook scripts actually
# ship in the portable hooks/ dir (PreToolUse Bash block-* + PreToolUse
# Edit|Write block-main-edits.sh + PostToolUse Edit/Write warn-config-drift.sh).
# ──────────────────────────────────────────────────────────────────────────
register_hooks() {
  local portable="$1" project_dir="$2"
  local settings="$project_dir/.claude/settings.json"
  mkdir -p "$project_dir/.claude"

  # (event, matcher, hook-basename) canonical triples — only those whose
  # script exists in $portable/hooks/.
  local -a triples=(
    "PreToolUse:Bash:block-unsafe-generic.sh"
    "PreToolUse:Bash:block-stale-skill-version.sh"
    "PreToolUse:Edit|Write:block-main-edits.sh"
    "PostToolUse:Edit:warn-config-drift.sh"
    "PostToolUse:Write:warn-config-drift.sh"
  )

  # Build the JSON list of present triples as command literals.
  local present_args=()
  local t event matcher base
  for t in "${triples[@]}"; do
    IFS=':' read -r event matcher base <<<"$t"
    [ -f "$portable/hooks/$base" ] || continue
    present_args+=("$event" "$matcher" \
      "bash \"\$CLAUDE_PROJECT_DIR/.claude/hooks/$base\"")
  done

  # Surgical merge via Python: preserve existing top-level keys + foreign
  # hook entries; idempotent (skip if command present anywhere in the event
  # array); append under the matching matcher block, creating it if absent.
  SETTINGS="$settings" "$PY" - "$@" "${present_args[@]}" <<'PYEOF'
import json, os, sys
settings = os.environ["SETTINGS"]
# argv: portable, project_dir, then flat (event, matcher, command) triples
rest = sys.argv[3:]
triples = [tuple(rest[i:i+3]) for i in range(0, len(rest), 3)]

if os.path.exists(settings):
    with open(settings) as f:
        data = json.load(f)
else:
    data = {}

hooks = data.setdefault("hooks", {})
for event, matcher, command in triples:
    arr = hooks.setdefault(event, [])
    # already present anywhere in this event array?
    found = False
    for block in arr:
        for h in block.get("hooks", []):
            if h.get("command") == command:
                found = True
                break
        if found:
            break
    if found:
        continue
    entry = {"type": "command", "command": command, "timeout": 5}
    # locate matcher block
    blk = next((b for b in arr if b.get("matcher") == matcher), None)
    if blk is None:
        arr.append({"matcher": matcher, "hooks": [entry]})
    else:
        blk.setdefault("hooks", []).append(entry)

with open(settings, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF
  return 0
}

# ──────────────────────────────────────────────────────────────────────────
# Oracle: copy the registered hook scripts into the consumer's .claude/hooks/
# (the legacy lane mirrors hooks/*.sh → .claude/hooks/). Only copy the
# scripts the settings.json registration references, so a "working" install
# means every registered hook command resolves to a real file.
# ──────────────────────────────────────────────────────────────────────────
copy_hooks() {
  local portable="$1" project_dir="$2"
  mkdir -p "$project_dir/.claude/hooks"
  local base
  for base in block-unsafe-generic.sh block-stale-skill-version.sh \
              block-main-edits.sh warn-config-drift.sh; do
    [ -f "$portable/hooks/$base" ] || continue
    cp -a "$portable/hooks/$base" "$project_dir/.claude/hooks/$base"
  done
  return 0
}

# ──────────────────────────────────────────────────────────────────────────
# Build a throwaway PORTABLE source from the REAL repo (read-only copies).
# ──────────────────────────────────────────────────────────────────────────
make_portable() {
  local portable="$TMP/portable"
  mkdir -p "$portable/skills" "$portable/hooks"
  # A couple of real source skills (small, present) to mirror.
  cp -a "$REPO_ROOT/skills/update-zskills" "$portable/skills/update-zskills"
  cp -a "$REPO_ROOT/skills/commit"         "$portable/skills/commit"
  # The hook scripts the registration references.
  local base
  for base in block-unsafe-generic.sh block-stale-skill-version.sh \
              block-main-edits.sh warn-config-drift.sh; do
    [ -f "$REPO_ROOT/hooks/$base" ] && cp -a "$REPO_ROOT/hooks/$base" "$portable/hooks/"
  done
  # Template for managed.md render.
  cp -a "$REPO_ROOT/CLAUDE_TEMPLATE.md" "$portable/CLAUDE_TEMPLATE.md"
  echo "$portable"
}

# Build a fresh throwaway consumer repo (config + template, no .claude
# artifacts beyond the bare dir).
make_consumer() {
  local consumer="$TMP/consumer"
  rm -rf -- "$consumer"
  mkdir -p "$consumer/.claude"
  cat > "$consumer/CLAUDE_TEMPLATE.md" <<'TEMPLATE'
# {{PROJECT_NAME}} — Agent Reference

## Dev Server

```bash
{{DEV_SERVER_CMD}}
```

## Agent Rules

Generic rules rendered by zskills. Timezone: {{TIMEZONE}}.
TEMPLATE
  cat > "$consumer/.claude/zskills-config.json" <<'CONFIG'
{
  "project_name": "acme-consumer",
  "timezone": "America/New_York",
  "dev_server": {
    "cmd": "npm run dev"
  }
}
CONFIG
  echo "$consumer"
}

echo "=== synthetic-consumer legacy install (end-to-end) ==="

# (The former case 0 — a static cross-reference into
# test-sessionstart-dual-install-detect.sh — was deleted in INSTALL_REDESIGN
# Phase 7 together with that suite: D27 subject-removal.)

# ── Build sandbox portable + consumer ──────────────────────────────────────
PORTABLE="$(make_portable)"
CONSUMER="$(make_consumer)"

# Snapshot the pre-install state to prove the oracle is not a no-op.
[ ! -e "$CONSUMER/.claude/skills/update-zskills/SKILL.md" ] \
  && [ ! -e "$CONSUMER/.claude/settings.json" ] \
  && [ ! -e "$CONSUMER/.claude/rules/zskills/managed.md" ] \
  && pass "1. pre-install: consumer has NO mirror / settings.json / managed.md (clean slate)" \
  || fail "1. pre-install clean slate" "consumer already had install artifacts"

# ── Run the legacy install oracle end-to-end ───────────────────────────────
mirror_skill "$PORTABLE" "$CONSUMER" update-zskills >/dev/null
mirror_skill "$PORTABLE" "$CONSUMER" commit          >/dev/null
copy_hooks       "$PORTABLE" "$CONSUMER"
register_hooks   "$PORTABLE" "$CONSUMER"
render_managed   "$CONSUMER"

# ── Assert a WORKING legacy install resulted ───────────────────────────────

# (a) Skills mirrored.
if [ -f "$CONSUMER/.claude/skills/update-zskills/SKILL.md" ] \
   && [ -f "$CONSUMER/.claude/skills/commit/SKILL.md" ]; then
  pass "2. skills mirrored: .claude/skills/{update-zskills,commit}/SKILL.md present"
else
  fail "2. skills mirrored" "expected SKILL.md under .claude/skills/{update-zskills,commit}/"
fi

# (b) settings.json exists, is valid JSON, and every registered hook command
#     resolves to a real .claude/hooks/ file (a "working" registration).
if [ -f "$CONSUMER/.claude/settings.json" ] \
   && "$PY" -c 'import json,sys; json.load(open(sys.argv[1]))' "$CONSUMER/.claude/settings.json" 2>/dev/null; then
  pass "3a. settings.json written and is valid JSON"
else
  fail "3a. settings.json valid JSON" "missing or unparseable"
fi

# Extract every registered command and confirm the referenced script exists.
missing_hook=""
while IFS= read -r cmd; do
  # cmd looks like: bash "$CLAUDE_PROJECT_DIR/.claude/hooks/<base>"
  base="${cmd##*/}"; base="${base%\"}"
  [ -f "$CONSUMER/.claude/hooks/$base" ] || missing_hook="$missing_hook $base"
done < <("$PY" - "$CONSUMER/.claude/settings.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
for event in ("PreToolUse", "PostToolUse"):
    for block in d.get("hooks", {}).get(event, []):
        for h in block.get("hooks", []):
            print(h.get("command", ""))
PYEOF
)
if [ -z "$missing_hook" ]; then
  pass "3b. every registered hook command resolves to a real .claude/hooks/ script"
else
  fail "3b. registered hooks resolve" "missing scripts:$missing_hook"
fi

# (c) Specific canonical triple landed under the right matcher.
if "$PY" - "$CONSUMER/.claude/settings.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
pre = d.get("hooks", {}).get("PreToolUse", [])
bash_cmds = [h["command"] for b in pre if b.get("matcher") == "Bash" for h in b.get("hooks", [])]
ew_cmds = [h["command"] for b in pre if b.get("matcher") == "Edit|Write" for h in b.get("hooks", [])]
ok = any("block-unsafe-generic.sh" in c for c in bash_cmds) \
     and any("block-main-edits.sh" in c for c in ew_cmds)
sys.exit(0 if ok else 1)
PYEOF
then
  pass "4. canonical triples registered under correct matchers (Bash→block-unsafe-generic, Edit|Write→block-main-edits)"
else
  fail "4. canonical triples under correct matchers" "expected block-unsafe-generic under Bash + block-main-edits under Edit|Write"
fi

# (d) managed.md rendered with consumer's config values and no leftover
#     placeholders.
MM="$CONSUMER/.claude/rules/zskills/managed.md"
if [ -f "$MM" ] \
   && grep -q '^# acme-consumer — Agent Reference' "$MM" \
   && grep -q 'npm run dev' "$MM" \
   && grep -q 'America/New_York' "$MM" \
   && ! grep -q '{{PROJECT_NAME}}' "$MM" \
   && ! grep -q '{{DEV_SERVER_CMD}}' "$MM"; then
  pass "5. managed.md rendered with consumer config values, no leftover placeholders"
else
  fail "5. managed.md render" "$([ -f "$MM" ] && head -3 "$MM" || echo 'file missing')"
fi

# (e) Idempotency: re-running registration does NOT duplicate the hook
#     entries (surgical merge skips already-present commands).
before_count=$("$PY" - "$CONSUMER/.claude/settings.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
n = 0
for event in ("PreToolUse", "PostToolUse"):
    for b in d.get("hooks", {}).get(event, []):
        n += len(b.get("hooks", []))
print(n)
PYEOF
)
register_hooks "$PORTABLE" "$CONSUMER"
after_count=$("$PY" - "$CONSUMER/.claude/settings.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
n = 0
for event in ("PreToolUse", "PostToolUse"):
    for b in d.get("hooks", {}).get(event, []):
        n += len(b.get("hooks", []))
print(n)
PYEOF
)
if [ "$before_count" = "$after_count" ]; then
  pass "6. hook registration idempotent (re-run did not duplicate: $before_count == $after_count)"
else
  fail "6. registration idempotent" "count grew $before_count → $after_count on re-run"
fi

# ── Foreign-key preservation: a pre-existing settings.json with user keys +
#    a foreign hook survives the surgical merge. ────────────────────────────
CONSUMER2="$TMP/consumer2"
mkdir -p "$CONSUMER2/.claude"
cp -a "$CONSUMER/CLAUDE_TEMPLATE.md" "$CONSUMER2/CLAUDE_TEMPLATE.md" 2>/dev/null || \
  cp -a "$CONSUMER/.claude/rules/zskills/managed.md" /dev/null 2>/dev/null || true
cat > "$CONSUMER2/.claude/settings.json" <<'PRESET'
{
  "permissions": { "allow": ["Read"] },
  "model": "opus",
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [
        { "type": "command", "command": "bash /custom/user-hook.sh", "timeout": 5 }
      ] }
    ]
  }
}
PRESET
copy_hooks     "$PORTABLE" "$CONSUMER2"
register_hooks "$PORTABLE" "$CONSUMER2"
if "$PY" - "$CONSUMER2/.claude/settings.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
top_ok = d.get("permissions", {}).get("allow") == ["Read"] and d.get("model") == "opus"
pre = d.get("hooks", {}).get("PreToolUse", [])
bash_cmds = [h["command"] for b in pre if b.get("matcher") == "Bash" for h in b.get("hooks", [])]
foreign_ok = any("/custom/user-hook.sh" in c for c in bash_cmds)
zskills_ok = any("block-unsafe-generic.sh" in c for c in bash_cmds)
sys.exit(0 if (top_ok and foreign_ok and zskills_ok) else 1)
PYEOF
then
  pass "7. surgical merge preserves foreign top-level keys + foreign hook, adds zskills hooks"
else
  fail "7. surgical merge preservation" "foreign keys/hook lost OR zskills hooks not added"
fi

# (The former cases 8a–8c — the materialiser dual-install WARN-site
# consistency regression — were deleted in INSTALL_REDESIGN Phase 7:
# subject-removal; both the materialiser and switch-install-path.sh are
# gone, so the WARN sites they pinned no longer exist.)

# ── Sandbox-isolation self-check: the real repo's settings.json (if any) and
#    the real ~/.claude were never touched by this run. ──────────────────────
echo ""
echo "=== sandbox isolation self-check ==="
# Everything we wrote lives under $TMP. Confirm we did not create artifacts
# under the real repo's .claude/skills/{commit,update-zskills} mirror from
# THIS test (those exist in the dev repo already, so we can't assert absence
# — instead assert our consumer dirs are wholly under $TMP).
if [[ "$CONSUMER" == "$TMP/"* ]] && [[ "$CONSUMER2" == "$TMP/"* ]] && [[ "$PORTABLE" == "$TMP/"* ]]; then
  pass "9. all install targets are under the mktemp sandbox ($TMP)"
else
  fail "9. sandbox containment" "a target escaped \$TMP: CONSUMER=$CONSUMER CONSUMER2=$CONSUMER2 PORTABLE=$PORTABLE"
fi

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
