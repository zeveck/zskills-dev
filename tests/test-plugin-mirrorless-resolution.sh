#!/usr/bin/env bash
# tests/test-plugin-mirrorless-resolution.sh
#
# Phase 5 (W5.1) of "Plugin-lane script resolution + dual-install hardening".
#
# The dogfood that would have caught the whole class of bug this plan fixes:
# a REAL release-layout, MIRROR-LESS plugin consumer. Before the Phase 1-4
# migration, skill bash fences and bundled scripts hard-coded
# `$CLAUDE_PROJECT_DIR/.claude/skills/...` — which does NOT exist on the
# plugin lane, where skills live under `$CLAUDE_PLUGIN_ROOT/skills/...` and
# the consumer has NO `.claude/skills/` mirror at all.
#
# This test builds:
#   $REL  — a SHIPPED plugin tree (git archive HEAD + build-plugin-release.sh's
#           FULL strip set applied, so $REL == the prod tree, not a dev superset).
#   $PROJ — a mirror-LESS consumer: only `.claude/zskills-config.json`, NO
#           `.claude/skills/` mirror.
#
# It then proves resolution works on the plugin lane with CLAUDE_PLUGIN_ROOT
# and CLAUDE_PROJECT_DIR FULLY OVERRIDDEN per sub-invocation — deliberately
# NOT relying on run-all.sh's global `CLAUDE_PROJECT_DIR=$REPO_ROOT` export,
# which points at the LIVE repo mirror and would false-GREEN every case.
#
# Cases:
#   1. positive       — source zskills-resolve-config.sh DIRECTLY from $REL;
#                        ZSKILLS_SKILLS_ROOT == $REL/skills, FULL_TEST_CMD non-empty.
#   2. bundled-script  — $REL/skills/create-worktree/scripts/sanitize-pipeline-id.sh
#                        runs mirror-less (a real bundled script unresolvable before the fix).
#   3. family-3        — post-run-invariants.sh sources its sibling zskills-paths.sh
#                        via the BASH_SOURCE-relative path with NO `.claude/skills` mirror.
#   4. negative-control — $REL/scripts/zskills-resolve-config.sh does NOT exist
#                        (the OLD wrong path is genuinely absent in a real release tree).
#   5. legacy-control  — CLAUDE_PLUGIN_ROOT UNSET + a consumer WITH a
#                        .claude/skills/update-zskills/scripts/ mirror → same
#                        resolution succeeds via the legacy branch.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

REL="$(mktemp -d)"
PROJ="$(mktemp -d)"
LEGACY="$(mktemp -d)"
trap 'rm -rf "$REL" "$PROJ" "$LEGACY"' EXIT

# ── Build $REL: shipped plugin tree (git archive HEAD + FULL strip set) ─────
# git archive captures only COMMITTED state — so the migrated forms (Phases
# 1-4, all committed) ARE in $REL; the (possibly-uncommitted) Phase-5 test
# itself need not be.
echo "=== building shipped plugin tree (git archive HEAD + strip set) ==="
git -C "$REPO_ROOT" archive --format=tar HEAD | tar -x -C "$REL"

# Apply build-plugin-release.sh's FULL strip set to $REL. These steps mirror
# scripts/build-plugin-release.sh steps 1-5 EXACTLY (kept in sync by the
# strip-verification grep at the end of this block — the same grep the build
# script runs to gate its prod ref). If the build script's strip set grows,
# the verification grep below fails closed and forces this block to be updated.
#
# 1. README prod-strip blocks.
if [ -f "$REL/README.md" ] && grep -q 'prod-strip:start' "$REL/README.md"; then
  sed -i '/<!-- prod-strip:start -->/,/<!-- prod-strip:end -->/d' "$REL/README.md"
fi
# 2. dev-maintainer-only files (RELEASING.md + DEV-QUAL.md).
for f in RELEASING.md DEV-QUAL.md; do
  [ -f "$REL/$f" ] && rm -f "$REL/$f"
done
# 3. CANARY* plans/fixtures + canary*-bad.sh hooks.
find "$REL" -type f -name '*CANARY*' -delete 2>/dev/null || true
find "$REL/hooks" -maxdepth 1 -type f -name 'canary*-bad.sh' -delete 2>/dev/null || true
# 4. build-*.sh release tooling.
find "$REL/scripts" -maxdepth 1 -type f -name 'build-*.sh' -delete 2>/dev/null || true
# 5. dev_only:true skills (+ mirrors) and MW-EXAMPLE files. 0 dev_only today,
#    but stay robust to future ones (drive off the same frontmatter probe the
#    build script uses).
for skill_file in "$REL"/skills/*/SKILL.md "$REL"/block-diagram/*/SKILL.md; do
  [ -f "$skill_file" ] || continue
  if awk '
      BEGIN { in_fm = 0 }
      /^---[[:space:]]*$/ { in_fm++; if (in_fm >= 2) exit 1 }
      in_fm == 1 && /^dev_only:[[:space:]]*true[[:space:]]*$/ { exit 0 }
      END { exit 1 }
    ' "$skill_file"; then
    skill_dir="$(dirname "$skill_file")"
    rm -rf "$skill_dir"
    mirror_dir="$REL/.claude/skills/$(basename "$skill_dir")"
    [ -d "$mirror_dir" ] && rm -rf "$mirror_dir"
  fi
done
while IFS= read -r mwfile; do
  [ -n "$mwfile" ] || continue
  rm -f "$mwfile"
done < <(grep -rl 'MW-EXAMPLE' "$REL" 2>/dev/null || true)

# Strip-verification: the SAME grep build-plugin-release.sh runs to gate its
# prod ref (step 10). 0 forbidden survivors == $REL matches the shipped tree.
# NOTE (#1002): build-*.sh sub-pattern anchored to `scripts/build-…` to match
# what finalize_prod_tree actually strips (maxdepth 1 in $tree/scripts/). The
# old loose `build-.*\.sh` false-positived on shipped test files whose basename
# starts with `build-` (tests/test-build-rewrite-dev-urls.sh,
# tests/test-build-prod-strip-parity.sh).
STRIP_HITS="$(cd "$REL" && find . -type f \
  | sed 's|^\./||' \
  | grep -E 'CANARY|RELEASING|DEV-QUAL|dev_only|scripts/build-[^/]*\.sh|MW-EXAMPLE' || true)"
if [ -z "$STRIP_HITS" ]; then
  pass "0. strip set applied: 0 forbidden paths in \$REL (matches shipped tree)"
else
  fail "0. strip set incomplete — forbidden paths survived in \$REL:"
  printf '%s\n' "$STRIP_HITS" | sed 's/^/        /'
fi

# ── Build $PROJ: mirror-LESS consumer (config only, NO .claude/skills/) ─────
mkdir -p "$PROJ/.claude"
cat > "$PROJ/.claude/zskills-config.json" <<'JSON'
{
  "testing": {
    "full_cmd": "bash tests/run-all.sh"
  },
  "timezone": "America/New_York"
}
JSON
if [ ! -d "$PROJ/.claude/skills" ]; then
  pass "0b. consumer \$PROJ is mirror-less (no .claude/skills/)"
else
  fail "0b. consumer \$PROJ unexpectedly has a .claude/skills/ mirror"
fi

echo ""
echo "=== mirror-less plugin-lane resolution ==="

# ── 1. positive: source zskills-resolve-config.sh DIRECTLY from $REL ────────
# CRITICAL: fully override CLAUDE_PLUGIN_ROOT *and* CLAUDE_PROJECT_DIR for this
# sub-shell. run-all.sh exports CLAUDE_PROJECT_DIR=$REPO_ROOT globally; if we
# inherited that, resolution would find the LIVE repo mirror and false-GREEN.
pos_out="$(
  export CLAUDE_PLUGIN_ROOT="$REL"
  export CLAUDE_PROJECT_DIR="$PROJ"
  unset ZSKILLS_SKILLS_ROOT
  . "$REL/skills/update-zskills/scripts/zskills-resolve-config.sh"
  printf 'SSR=%s\n' "$ZSKILLS_SKILLS_ROOT"
  printf 'FTC=%s\n' "$FULL_TEST_CMD"
)"
got_ssr="$(printf '%s\n' "$pos_out" | sed -n 's/^SSR=//p')"
got_ftc="$(printf '%s\n' "$pos_out" | sed -n 's/^FTC=//p')"
if [ "$got_ssr" = "$REL/skills" ]; then
  pass "1a. plugin lane: ZSKILLS_SKILLS_ROOT == \$REL/skills"
else
  fail "1a. ZSKILLS_SKILLS_ROOT mismatch: got '$got_ssr', want '$REL/skills'"
fi
if [ -n "$got_ftc" ]; then
  pass "1b. plugin lane: FULL_TEST_CMD resolved non-empty ('$got_ftc')"
else
  fail "1b. FULL_TEST_CMD empty — config not resolved on plugin lane"
fi

# ── 2. bundled-script smoke: sanitize-pipeline-id.sh runs mirror-less ───────
san_out="$(
  export CLAUDE_PLUGIN_ROOT="$REL"
  export CLAUDE_PROJECT_DIR="$PROJ"
  bash "$REL/skills/create-worktree/scripts/sanitize-pipeline-id.sh" "foo bar/baz"
)"
san_rc=$?
if [ "$san_rc" -eq 0 ] && [ "$san_out" = "foo_bar_baz" ]; then
  pass "2. bundled script: sanitize-pipeline-id.sh runs mirror-less (rc=0, '$san_out')"
else
  fail "2. sanitize-pipeline-id.sh mirror-less smoke failed (rc=$san_rc, out='$san_out')"
fi

# ── 3. family-3: post-run-invariants.sh sources sibling zskills-paths.sh ────
# via its BASH_SOURCE-relative path with NO .claude/skills mirror present.
# Reproduce the exact resolution snippet from the script (lines 88-92) anchored
# at the SHIPPED script's location, then confirm the sibling helper resolves
# AND, when sourced, sets ZSKILLS_SKILLS_ROOT to the plugin tree.
PRI="$REL/skills/run-plan/scripts/post-run-invariants.sh"
if [ -f "$PRI" ]; then
  fam3_out="$(
    export CLAUDE_PLUGIN_ROOT="$REL"
    export CLAUDE_PROJECT_DIR="$PROJ"
    unset ZSKILLS_SKILLS_ROOT
    # Verify the script's own BASH_SOURCE-relative source line points at a real
    # file in the mirror-less layout (../../update-zskills/scripts/).
    _self_dir="$(cd "$(dirname "$PRI")" && pwd)"
    _cand="$_self_dir/../../update-zskills/scripts/zskills-paths.sh"
    if [ -f "$_cand" ]; then
      . "$_cand"
      printf 'RESOLVED=%s\n' "$ZSKILLS_SKILLS_ROOT"
    else
      printf 'UNRESOLVED=%s\n' "$_cand"
    fi
  )"
  fam3_ssr="$(printf '%s\n' "$fam3_out" | sed -n 's/^RESOLVED=//p')"
  if [ "$fam3_ssr" = "$REL/skills" ]; then
    pass "3. family-3: post-run-invariants sources sibling zskills-paths.sh mirror-less (SSR=\$REL/skills)"
  else
    fail "3. family-3 mirror-less source failed: $fam3_out"
  fi
else
  fail "3. expected $PRI in shipped tree (not found)"
fi

# ── 4. negative control: the OLD wrong path is genuinely absent ─────────────
# Proves the test targets the real failure mode — a real release tree has NO
# $REL/scripts/zskills-resolve-config.sh (it lives ONLY under
# skills/update-zskills/scripts/).
if [ ! -e "$REL/scripts/zskills-resolve-config.sh" ]; then
  pass "4. negative control: \$REL/scripts/zskills-resolve-config.sh absent (real failure mode)"
else
  fail "4. negative control broken: \$REL/scripts/zskills-resolve-config.sh exists"
fi

# ── 5. legacy-unchanged control: CLAUDE_PLUGIN_ROOT UNSET + mirror present ──
# Build a tiny mirror fixture under $LEGACY with the helper scripts, then
# confirm the SAME resolution succeeds via the legacy `else` branch.
mkdir -p "$LEGACY/.claude/skills/update-zskills/scripts"
cp "$REPO_ROOT/skills/update-zskills/scripts/zskills-resolve-config.sh" \
   "$LEGACY/.claude/skills/update-zskills/scripts/"
cp "$REPO_ROOT/skills/update-zskills/scripts/zskills-paths.sh" \
   "$LEGACY/.claude/skills/update-zskills/scripts/"
cat > "$LEGACY/.claude/zskills-config.json" <<'JSON'
{
  "testing": {
    "full_cmd": "bash tests/run-all.sh"
  },
  "timezone": "America/New_York"
}
JSON
leg_out="$(
  unset CLAUDE_PLUGIN_ROOT
  export CLAUDE_PROJECT_DIR="$LEGACY"
  unset ZSKILLS_SKILLS_ROOT
  . "$LEGACY/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
  printf 'SSR=%s\n' "$ZSKILLS_SKILLS_ROOT"
  printf 'FTC=%s\n' "$FULL_TEST_CMD"
)"
leg_ssr="$(printf '%s\n' "$leg_out" | sed -n 's/^SSR=//p')"
leg_ftc="$(printf '%s\n' "$leg_out" | sed -n 's/^FTC=//p')"
if [ "$leg_ssr" = "$LEGACY/.claude/skills" ]; then
  pass "5a. legacy lane: ZSKILLS_SKILLS_ROOT == \$CLAUDE_PROJECT_DIR/.claude/skills"
else
  fail "5a. legacy ZSKILLS_SKILLS_ROOT mismatch: got '$leg_ssr', want '$LEGACY/.claude/skills'"
fi
if [ -n "$leg_ftc" ]; then
  pass "5b. legacy lane: FULL_TEST_CMD resolved non-empty via legacy branch"
else
  fail "5b. legacy FULL_TEST_CMD empty — legacy branch resolution failed"
fi

# ── 6. synthetic-FENCE mirror-less PASS (Phase-1 acceptance #1) ──────────────
# Cases 1/3 source the helper DIRECTLY with CLAUDE_PLUGIN_ROOT PRE-EXPORTED —
# they prove the SCRIPTS resolve, but they do NOT exercise the lane-selection
# FENCE the harness actually renders. The Phase-1 root-cause fix is the fence
# migration (a self-locating script is useless if the fence can't source it),
# so this case exercises a REAL fence guard rendered exactly as the harness
# would on a mirror-less plugin consumer:
#   - the BARE ${CLAUDE_PLUGIN_ROOT} token is substituted to the shipped tree's
#     ABSOLUTE path (a string literal — NOT an env-var read);
#   - the ${CLAUDE_PLUGIN_ROOT:-} form is ABSENT (the new idiom drops it);
#   - the script runs with `env -u CLAUDE_PLUGIN_ROOT` (EMPTY plugin env, the
#     real mirror-less reality) and NO pre-export.
# Pre-fix this fence's `[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] &&` first conjunct was
# empty/false in the script env → short-circuited the working `-f` test → fell
# to the absent legacy mirror → resolution FAILED. Post-fix the bare-token `-f`
# test substitutes to a real path → plugin branch → ZSKILLS_SKILLS_ROOT resolves.
FENCE_SCRIPT="$REL/_synthetic-fence-$$.sh"
# Render the harness substitution: bare ${CLAUDE_PLUGIN_ROOT} → the $REL literal.
# Single-quoted heredoc keeps the file literal; we splice $REL in by hand so the
# rendered fence carries the ABSOLUTE path, NOT a live shell expansion.
cat > "$FENCE_SCRIPT" <<FENCE
#!/usr/bin/env bash
# Synthetic plugin-skill fence as the harness renders it (bare token → abs path).
if [ -f "$REL/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="$REL"
  . "$REL/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "\$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
printf 'SSR=%s\n' "\$ZSKILLS_SKILLS_ROOT"
printf 'FTC=%s\n' "\$FULL_TEST_CMD"
FENCE
fence_out="$(env -u CLAUDE_PLUGIN_ROOT -u ZSKILLS_SKILLS_ROOT \
  CLAUDE_PROJECT_DIR="$PROJ" bash "$FENCE_SCRIPT")"
rm -f "$FENCE_SCRIPT"
fence_ssr="$(printf '%s\n' "$fence_out" | sed -n 's/^SSR=//p')"
fence_ftc="$(printf '%s\n' "$fence_out" | sed -n 's/^FTC=//p')"
if [ -n "$fence_ssr" ] && [ -d "$fence_ssr" ]; then
  pass "6a. synthetic fence (bare-token, EMPTY env, NO pre-export) → ZSKILLS_SKILLS_ROOT resolves to a real dir ('$fence_ssr')"
else
  fail "6a. synthetic-fence ZSKILLS_SKILLS_ROOT not a real dir: got '$fence_ssr'"
fi
if [ -n "$fence_ftc" ]; then
  pass "6b. synthetic fence: FULL_TEST_CMD resolved non-empty mirror-less ('$fence_ftc')"
else
  fail "6b. synthetic-fence FULL_TEST_CMD empty — fence did not resolve config mirror-less"
fi

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
