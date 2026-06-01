#!/usr/bin/env bash
# tests/test-plugin-hooks-integrity.sh
#
# PLUGIN_LANE_VERIFICATION Phase 1 — three fail-closed static smokes closing
# gaps the inspection found in existing plugin-lane coverage:
#
#   Gap 1 — hooks.json registered-script existence/sibling gate.
#           Every script registered in hooks/hooks.json must EITHER exist
#           in-tree OR have a committed `<script>.template` sibling (the D4
#           release-generated suffixless pair). A dangling hooks.json entry
#           (no script, no template) FAILS. Nothing fails-closed on this today.
#
#   Gap 2 — shim-sourcing assertion. Every hooks.json-registered *.sh that
#           EXISTS in-tree must source hooks/_lib/plugin-hook-skip-if-mirrored.sh
#           (the D16(a) conditional-skip shim) — EXCEPT a NAMED exclusion list
#           built explicitly with rationale, so a FUTURE hook that forgets the
#           shim still FAILS. Conformance stamps the hook version but does NOT
#           check shim-sourcing; this closes that.
#
#   Gap 3 — D3 bundled-fallback branch in hooks/session-start-materialise.sh.
#           The consumer-PRESENT template branch is already covered by
#           test-sessionstart-materialise.sh. The genuine gap is the
#           consumer-ABSENT -> $PLUGIN bundled-fallback branch
#           (`elif [ -f "$PLUGIN/CLAUDE_TEMPLATE.md" ]`). Drive it in a tmpdir
#           with a fake $PLUGIN carrying a sentinel template and NO consumer
#           CLAUDE_TEMPLATE.md, and assert managed.md renders from the bundled
#           copy.
#
# All three are pure static/hermetic — no network, no real `claude`, no real
# $HOME. Each genuinely fails-closed when its invariant is violated (demonstrated
# below in dev via synthetic-violation copies).

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
if [ -z "$PYTHON" ]; then
  echo "ERROR: install Python 3 (or set ZSKILLS_PYTHON)" >&2
  exit 1
fi

HOOKS_JSON="$REPO_ROOT/hooks/hooks.json"
SHIM_REL="hooks/_lib/plugin-hook-skip-if-mirrored.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# ── Named allow-lists (Gap 1 + Gap 2), built explicitly with rationale ────────
#
# D4 .template-only pair: these two consumer-customizable hooks ship ONLY as
# `<name>.sh.template` in-tree; the suffixless `<name>.sh` is generated at
# release time. They are the ONLY hooks permitted to be `.template`-only
# (Gap 1) and the ONLY hooks whose shim-sourcing is asserted via their
# `.template` file instead of an in-tree `*.sh` (Gap 2). Naming them keeps a
# future genuinely-dangling entry failing-closed.
D4_TEMPLATE_ONLY="block-unsafe-project.sh block-agents.sh"

# Gap-2 shim-sourcing exclusion: SessionStart materialiser. It carries its OWN
# dual-install probe (detect-install-state.sh) and is NOT a double-fire-prone
# PreToolUse hook, so it legitimately does NOT source the conditional-skip shim.
SHIM_EXCLUDE="session-start-materialise.sh"

in_list() {
  # in_list <needle> <space-separated-list>
  local needle="$1" item
  for item in $2; do
    [ "$item" = "$needle" ] && return 0
  done
  return 1
}

# Extract every registered hook command's resolved script basename from
# hooks.json. Each command looks like:
#   bash "${CLAUDE_PLUGIN_ROOT}/hooks/<name>.sh"
# We pull the path token after `hooks/` and emit the basename (one per line,
# de-duplicated, sorted for stable output).
mapfile -t REGISTERED < <(
  "$PYTHON" - "$HOOKS_JSON" <<'PY'
import json, re, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
seen = []
hooks = data.get("hooks", {})
for event in hooks.values():
    if not isinstance(event, list):
        continue
    for matcher in event:
        if not isinstance(matcher, dict):
            continue
        for h in matcher.get("hooks", []):
            cmd = h.get("command", "")
            if not isinstance(cmd, str):
                continue
            # Find the path token that contains hooks/<name>.sh
            m = re.search(r'hooks/([A-Za-z0-9._-]+\.sh)', cmd)
            if m:
                name = m.group(1)
                if name not in seen:
                    seen.append(name)
for n in sorted(seen):
    print(n)
PY
)

if [ "${#REGISTERED[@]}" -eq 0 ]; then
  fail "0. parsed ZERO registered hook scripts from hooks.json (parse error?)"
fi

# ──────────────────────────────────────────────────────────────────────────
echo "=== Gap 1 — hooks.json registered-script existence/sibling gate ==="

# gap1_check <repo-root> — returns 0 (all OK) / 1 (a dangling entry found).
# Re-usable so the synthetic-violation demo can call it against a tmpdir copy.
gap1_check() {
  local root="$1" name path tmpl ok=0
  local hooks_json="$root/hooks/hooks.json"
  local names
  names="$(
    "$PYTHON" - "$hooks_json" <<'PY'
import json, re, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
seen = []
for event in data.get("hooks", {}).values():
    if not isinstance(event, list):
        continue
    for matcher in event:
        if not isinstance(matcher, dict):
            continue
        for h in matcher.get("hooks", []):
            cmd = h.get("command", "")
            if not isinstance(cmd, str):
                continue
            m = re.search(r'hooks/([A-Za-z0-9._-]+\.sh)', cmd)
            if m and m.group(1) not in seen:
                seen.append(m.group(1))
for n in sorted(seen):
    print(n)
PY
  )"
  local rc=0
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    path="$root/hooks/$name"
    tmpl="$root/hooks/$name.template"
    if [ -f "$path" ]; then
      :  # (a) script exists in-tree
    elif [ -f "$tmpl" ]; then
      # (b) committed .template sibling — only allowed for the named D4 pair.
      if in_list "$name" "$D4_TEMPLATE_ONLY"; then
        :
      else
        echo "DANGLING(template-not-allowlisted): $name" >&2
        rc=1
      fi
    else
      echo "DANGLING(no-script-no-template): $name" >&2
      rc=1
    fi
  done <<EOF
$names
EOF
  return $rc
}

if gap1_check "$REPO_ROOT" 2>/tmp/.gap1.err; then
  pass "1. every hooks.json-registered script exists in-tree OR has an allow-listed .template sibling"
else
  fail "1. a hooks.json-registered script is neither present nor an allow-listed .template sibling"
  sed 's/^/      /' /tmp/.gap1.err
fi
rm -f /tmp/.gap1.err

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Gap 2 — shim-sourcing assertion ==="

# gap2_check <repo-root> — every registered *.sh that exists in-tree must
# source the conditional-skip shim, except the named SHIM_EXCLUDE. The D4
# .template-only pair is asserted via its .template file instead.
gap2_check() {
  local root="$1" name path tmpl
  local hooks_json="$root/hooks/hooks.json"
  local names
  names="$(
    "$PYTHON" - "$hooks_json" <<'PY'
import json, re, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
seen = []
for event in data.get("hooks", {}).values():
    if not isinstance(event, list):
        continue
    for matcher in event:
        if not isinstance(matcher, dict):
            continue
        for h in matcher.get("hooks", []):
            cmd = h.get("command", "")
            if not isinstance(cmd, str):
                continue
            m = re.search(r'hooks/([A-Za-z0-9._-]+\.sh)', cmd)
            if m and m.group(1) not in seen:
                seen.append(m.group(1))
for n in sorted(seen):
    print(n)
PY
  )"
  local rc=0
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    # Named shim exclusion (has its own dual-install probe).
    if in_list "$name" "$SHIM_EXCLUDE"; then
      continue
    fi
    path="$root/hooks/$name"
    tmpl="$root/hooks/$name.template"
    if [ -f "$path" ]; then
      # In-tree *.sh — must source the shim.
      if grep -q "$SHIM_REL" "$path"; then
        :
      else
        echo "MISSING-SHIM(in-tree): $name" >&2
        rc=1
      fi
    elif [ -f "$tmpl" ] && in_list "$name" "$D4_TEMPLATE_ONLY"; then
      # D4 .template-only pair — assert the .template sources the shim, so the
      # release-generated suffixless sibling will too.
      if grep -q "$SHIM_REL" "$tmpl"; then
        :
      else
        echo "MISSING-SHIM(template): $name.template" >&2
        rc=1
      fi
    fi
    # (Gap 1 already flags a name that is neither present nor an allow-listed
    # template; Gap 2 does not re-flag it.)
  done <<EOF
$names
EOF
  return $rc
}

if gap2_check "$REPO_ROOT" 2>/tmp/.gap2.err; then
  pass "2a. every in-tree registered *.sh (minus named exclusions) sources the conditional-skip shim; D4 .template pair asserted via .template"
else
  fail "2a. a registered hook is missing the conditional-skip shim source line"
  sed 's/^/      /' /tmp/.gap2.err
fi
rm -f /tmp/.gap2.err

# 2b — positive coverage: assert the EXPECTED in-tree set is actually being
# checked (anti-green-by-absence). The 7 in-tree block-*.sh + warn-config-drift
# must all be present, source the shim, and NOT be on any exclusion list.
EXPECTED_IN_TREE_SHIMMED="block-bad-cron.sh block-bypassed-land-pr.sh block-fix-issue-unclaimed.sh block-main-edits.sh block-run-plan-unclaimed.sh block-stale-skill-version.sh block-unsafe-generic.sh warn-config-drift.sh"
missing_expected=""
for name in $EXPECTED_IN_TREE_SHIMMED; do
  # Must be registered, exist in-tree, source the shim, and not be excluded.
  reg=0
  for r in "${REGISTERED[@]}"; do [ "$r" = "$name" ] && reg=1 && break; done
  if [ "$reg" -ne 1 ]; then missing_expected="$missing_expected $name(not-registered)"; continue; fi
  if [ ! -f "$REPO_ROOT/hooks/$name" ]; then missing_expected="$missing_expected $name(absent)"; continue; fi
  if ! grep -q "$SHIM_REL" "$REPO_ROOT/hooks/$name"; then missing_expected="$missing_expected $name(no-shim)"; continue; fi
  if in_list "$name" "$SHIM_EXCLUDE"; then missing_expected="$missing_expected $name(wrongly-excluded)"; continue; fi
done
if [ -z "$missing_expected" ]; then
  pass "2b. all 7 in-tree block-*.sh + warn-config-drift.sh are registered, in-tree, shim-sourcing, and asserted (not excluded)"
else
  fail "2b. expected shim-sourcing set incomplete:$missing_expected"
fi

# 2c — assert the D4 .template pair's templates source the shim (so the
# release-generated siblings will).
d4_ok=1
for name in $D4_TEMPLATE_ONLY; do
  if [ ! -f "$REPO_ROOT/hooks/$name.template" ] || ! grep -q "$SHIM_REL" "$REPO_ROOT/hooks/$name.template"; then
    d4_ok=0
  fi
done
if [ "$d4_ok" -eq 1 ]; then
  pass "2c. D4 .template pair (block-unsafe-project, block-agents) source the shim in their .template files"
else
  fail "2c. a D4 .template hook does not source the shim"
fi

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Gap 3 — D3 bundled-fallback branch (materialiser, consumer-ABSENT) ==="

# Drive the materialiser's `elif [ -f "$PLUGIN/CLAUDE_TEMPLATE.md" ]` fallback:
# a tmpdir $PROJ with NO consumer CLAUDE_TEMPLATE.md, and a fake $PLUGIN whose
# bundled CLAUDE_TEMPLATE.md carries a UNIQUE sentinel line. If managed.md
# contains that sentinel, the bundled-fallback branch fired (the consumer-
# present branch — already covered elsewhere — could NOT have produced it,
# because $PROJ has no template).
MAT="$REPO_ROOT/hooks/session-start-materialise.sh"
TMP3="$(mktemp -d)"
trap 'rm -rf "$TMP3"' EXIT

PLUG="$TMP3/plugin"
PROJ3="$TMP3/proj"
mkdir -p "$PLUG/hooks/_lib" "$PLUG/scripts" "$PLUG/.claude-plugin" "$PROJ3"

# Fake plugin wiring: copy only what the materialiser reaches.
cp "$REPO_ROOT/hooks/_lib/detect-install-state.sh" "$PLUG/hooks/_lib/"
cp "$REPO_ROOT/scripts/render-managed-rules.py" "$PLUG/scripts/"
cp "$REPO_ROOT/scripts/managed_rules_substitution.py" "$PLUG/scripts/"
cp "$REPO_ROOT/.claude-plugin/plugin.json" "$PLUG/.claude-plugin/"

# Bundled template = the real template + a unique sentinel marker line. The
# marker is plain prose (no {{...}}), so render-managed-rules.py passes it
# through verbatim.
BUNDLED_SENTINEL="ZSKILLS-BUNDLED-FALLBACK-SENTINEL-Phase1"
{
  printf '%s\n' "<!-- $BUNDLED_SENTINEL -->"
  cat "$REPO_ROOT/CLAUDE_TEMPLATE.md"
} > "$PLUG/CLAUDE_TEMPLATE.md"

# Sanity: $PROJ3 must have NO consumer CLAUDE_TEMPLATE.md (so the present-branch
# cannot fire). Assert it explicitly.
if [ ! -f "$PROJ3/CLAUDE_TEMPLATE.md" ]; then
  pass "3a. fixture: consumer \$PROJ has NO CLAUDE_TEMPLATE.md (forces the bundled-fallback branch)"
else
  fail "3a. fixture invalid: consumer CLAUDE_TEMPLATE.md present"
fi

# Run the materialiser against the fake plugin + consumer-absent project.
MAT_ERR="$TMP3/mat.stderr"
env CLAUDE_PROJECT_DIR="$PROJ3" CLAUDE_PLUGIN_ROOT="$PLUG" bash "$MAT" 2>"$MAT_ERR" || true

MANAGED="$PROJ3/.claude/rules/zskills/managed.md"

# 3b — managed.md was rendered at all.
if [ -f "$MANAGED" ]; then
  pass "3b. managed.md rendered in the consumer-absent case (config seeded + bundled template chosen)"
else
  fail "3b. managed.md NOT rendered in the consumer-absent case"
  sed 's/^/      stderr: /' "$MAT_ERR"
fi

# 3c — managed.md carries the BUNDLED sentinel => the $PLUGIN/CLAUDE_TEMPLATE.md
# fallback branch fired (the load-bearing assertion).
if [ -f "$MANAGED" ] && grep -qF "$BUNDLED_SENTINEL" "$MANAGED"; then
  pass "3c. managed.md rendered from the BUNDLED \$PLUGIN/CLAUDE_TEMPLATE.md (fallback branch fired)"
else
  fail "3c. managed.md did NOT come from the bundled template (fallback branch not exercised)"
  [ -f "$MANAGED" ] && head -3 "$MANAGED" | sed 's/^/      /'
fi

# ──────────────────────────────────────────────────────────────────────────
echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
