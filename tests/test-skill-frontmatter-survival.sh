#!/bin/bash
# tests/test-skill-frontmatter-survival.sh
#
# Phase 3 (PLUGIN_DISTRIBUTION) — F-DA2-6 STOP gate.
#
# Plugin-packaged skills MUST retain their invocation-control frontmatter
# (`user-invocable` and `disable-model-invocation`) after packaging. If a
# `disable-model-invocation: true` skill lost that key in the packaged
# plugin, it would silently become model-invocable on the plugin lane —
# breaking the cron-fire contract (every recurring skill sets
# `disable-model-invocation: true` so the Skill tool can't auto-dispatch it).
#
# Two failure modes are guarded:
#   1. A `prod-strip:start … prod-strip:end` block accidentally enclosing an
#      invocation-control frontmatter key — `scripts/build-prod.sh` would
#      delete it during the prod build.
#   2. A skill that declares an invocation-control key not being covered by
#      the plugin `skills` glob in `.claude-plugin/plugin.json` (zs) — so it
#      would not be packaged at all.
#
# The survival check is exercised by SIMULATING the build-prod prod-strip
# transformation on a fixture copy and re-reading the key with
# scripts/frontmatter-get.sh, asserting the value is preserved.
#
# Per the plan's Abort/Rollback: if this test fails, Phase 3 STOPS.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

GET="$REPO_ROOT/scripts/frontmatter-get.sh"
KEYS=(user-invocable disable-model-invocation)

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

WORK="/tmp/zskills-tests/$(basename "$REPO_ROOT")/frontmatter-survival"
rm -rf "$WORK"
mkdir -p "$WORK"

# --- Extract just the frontmatter block (between the first two `---`). ---
frontmatter_block() {
  awk '
    BEGIN { n = 0 }
    /^---[[:space:]]*$/ { n++; if (n == 2) exit; if (n == 1) next }
    n == 1 { print }
  ' "$1"
}

# --- Does the frontmatter declare KEY (top-level)? ---
fm_declares() {
  local file="$1" key="$2"
  frontmatter_block "$file" | grep -qE "^${key}:[[:space:]]"
}

# --- Simulate build-prod's prod-strip on a copy, return the copy path. ---
simulate_prod_strip() {
  local src="$1" dst="$2"
  cp "$src" "$dst"
  # Mirror scripts/build-prod.sh strip_markers exactly.
  if grep -q 'prod-strip:start' "$dst"; then
    sed -i '/<!-- prod-strip:start -->/,/<!-- prod-strip:end -->/d' "$dst"
  fi
}

# --- Plugin glob coverage. Mirrors plugin.json `skills` semantics:
#     zs covers ./skills/ ---
covered_by_plugin() {
  local file="$1"
  case "$file" in
    skills/*/SKILL.md) return 0 ;;  # zs ./skills/
    *)                 return 1 ;;
  esac
}

# Sanity: confirm the plugin manifest actually declares exactly the skills
# glob we assume (exact equality keeps the coverage assumption honest).
ZS_MANIFEST=".claude-plugin/plugin.json"
if grep -qF '"skills": ["./skills/"]' "$ZS_MANIFEST"; then
  pass "zs plugin.json declares skills == [\"./skills/\"]"
else
  fail "zs plugin.json must declare skills == [\"./skills/\"] (coverage assumption)"
fi

# Enumerate every source skill declaring an invocation-control key.
shopt -s nullglob
DECLARING=()
for f in skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  for key in "${KEYS[@]}"; do
    if fm_declares "$f" "$key"; then
      DECLARING+=("$f")
      break
    fi
  done
done
shopt -u nullglob

if [ "${#DECLARING[@]}" -eq 0 ]; then
  fail "expected at least one skill declaring user-invocable/disable-model-invocation — enumeration likely broken"
else
  pass "enumerated ${#DECLARING[@]} skill(s) declaring invocation-control frontmatter"
fi

i=0
for f in "${DECLARING[@]}"; do
  i=$((i+1))
  # 1. Coverage: the skill must be packaged by a plugin glob.
  if covered_by_plugin "$f"; then
    pass "coverage: $f is packaged by a plugin skills glob"
  else
    fail "coverage: $f declares invocation-control frontmatter but is NOT covered by any plugin skills glob"
  fi

  # 2/3. Survival across prod-strip for each declared key.
  copy="$WORK/copy-$i-SKILL.md"
  simulate_prod_strip "$f" "$copy"
  for key in "${KEYS[@]}"; do
    fm_declares "$f" "$key" || continue
    orig_val="$(bash "$GET" "$f" "$key" 2>/dev/null)"
    surv_val="$(bash "$GET" "$copy" "$key" 2>/dev/null)"
    if [ -n "$surv_val" ] && [ "$surv_val" = "$orig_val" ]; then
      pass "survival: $f key '$key' (=$orig_val) survives prod-strip"
    else
      fail "survival: $f key '$key' lost or changed after prod-strip (orig='$orig_val' survived='$surv_val')"
    fi
  done
done

# Negative-control: a synthetic skill whose invocation-control key is INSIDE
# a prod-strip block MUST be detected as not-surviving — proves the survival
# check has teeth.
NEG="$WORK/neg-SKILL.md"
cat > "$NEG" <<'NEG_FIXTURE'
---
name: neg
<!-- prod-strip:start -->
disable-model-invocation: true
<!-- prod-strip:end -->
description: synthetic negative control
---

body
NEG_FIXTURE
neg_copy="$WORK/neg-copy-SKILL.md"
simulate_prod_strip "$NEG" "$neg_copy"
neg_surv="$(bash "$GET" "$neg_copy" disable-model-invocation 2>/dev/null)"
if [ -z "$neg_surv" ]; then
  pass "negative-control: a key inside a prod-strip block is correctly detected as NOT surviving"
else
  fail "negative-control: prod-strip simulation should have removed the key (got '$neg_surv') — survival check lacks teeth"
fi

rm -rf "$WORK"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
exit $FAIL_COUNT
