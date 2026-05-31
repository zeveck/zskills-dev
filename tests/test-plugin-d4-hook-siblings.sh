#!/usr/bin/env bash
# tests/test-plugin-d4-hook-siblings.sh
#
# D4 existence gate — assert the BUILT plugin prod tree CONTAINS suffixless
# sibling copies of every hooks/*.sh.template, byte-equal to its .template.
#
# Why this exists (complements tests/test-hook-template-sibling.sh):
# build-plugin-release.sh step 8 (D4) generates suffixless sibling copies of
# every hooks/*.sh.template in the staged plugin tree (today block-agents.sh
# and block-unsafe-project.sh — the two safety hooks hooks/hooks.json
# registers on the plugin lane). Those siblings are BUILD-ONLY: they do not
# exist in the source/dev tree (only the .template forms are committed).
#
# The sibling test only asserts "IF a suffixless sibling exists in the SOURCE
# tree it is byte-equal to the .template" — and since the siblings are absent
# in source, it VACUOUS-PASSES. NOTHING there asserts the BUILT plugin tree
# actually CONTAINS those hooks. A regression that removes/breaks the D4 loop
# in build-plugin-release.sh would ship a plugin missing 2 safety hooks,
# completely uncaught.
#
# This test closes that hole by running the REAL build end-to-end and
# inspecting its OUTPUT (the prod ref). It deliberately does NOT replicate the
# D4 copy loop — deriving the siblings only from the build's output is the
# whole point: breaking D4 in build-plugin-release.sh makes THIS test fail red.
#
# Isolation: build-plugin-release.sh writes refs/heads/prod/main AND
# refs/tags/prod/<version> into the repo's .git via `git update-ref` even
# without --push (step 9). Running it in the live repo would pollute it, so we
# run it inside a throwaway local git CLONE; the EXIT trap removes the clone,
# fully un-polluting (the prod refs live inside the clone's .git, not the live
# repo).

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

echo "=== D4: built prod tree contains suffixless hook siblings ==="

# ── Isolated throwaway clone (refs from the build land in the clone's .git) ──
TMP="$(mktemp -d)"
CLONE="$TMP/clone"
trap 'rm -rf "$TMP"' EXIT

# Local-path clone — works on BOTH a full dev checkout AND a shallow CI
# checkout (actions/checkout@v4 fetch-depth:1). The build only `git archive
# HEAD`s the tree and creates a PARENTLESS prod/main when none pre-exists
# (always the case in a fresh clone), so no history walk is needed.
if ! git clone --quiet "$REPO_ROOT" "$CLONE"; then
  fail "0. git clone of \$REPO_ROOT failed"
  TOTAL=$((PASS_COUNT + FAIL_COUNT))
  printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit "$FAIL_COUNT"
fi

# A fresh `git clone` writes a new .git/config that does NOT inherit the source
# repo's local user.name/user.email, and CI runners have no global identity, so
# the clone has NO git author/committer. build-plugin-release.sh step 9
# (commit-tree, which builds the prod commit) then fails with "empty ident name".
# Give the throwaway clone a local identity so that step succeeds on CI.
git -C "$CLONE" config user.email "d4-gate-test@zskills.invalid"
git -C "$CLONE" config user.name  "zskills D4 gate test"

# ── Run the REAL build (no --push, default version) inside the clone ─────────
BUILD_OUT="$TMP/build.out"
if ( cd "$CLONE" && bash scripts/build-plugin-release.sh ) > "$BUILD_OUT" 2>&1; then
  pass "0. build-plugin-release.sh ran in isolated clone (rc=0)"
else
  fail "0. build-plugin-release.sh FAILED in isolated clone — output below:"
  sed 's/^/      /' "$BUILD_OUT"
  TOTAL=$((PASS_COUNT + FAIL_COUNT))
  printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit "$FAIL_COUNT"
fi

# ── Enumerate every .template hook in the clone's HEAD working tree ──────────
shopt -s nullglob
TEMPLATES=( "$CLONE"/hooks/*.sh.template )
shopt -u nullglob

# Guard against the empty-glob silent pass — D4 names at least
# block-agents.sh.template and block-unsafe-project.sh.template today.
if [ "${#TEMPLATES[@]}" -eq 0 ]; then
  fail "1. no hooks/*.sh.template found in clone (expected at least block-agents.sh.template + block-unsafe-project.sh.template)"
  TOTAL=$((PASS_COUNT + FAIL_COUNT))
  printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit "$FAIL_COUNT"
fi

# ── For each template, assert the built prod tree has the byte-equal sibling ─
for tmpl in "${TEMPLATES[@]}"; do
  bn="$(basename "$tmpl")"            # e.g. block-agents.sh.template
  sib="${bn%.template}"              # e.g. block-agents.sh
  tmpl_path="hooks/$bn"
  sib_path="hooks/$sib"

  # presence: the suffixless sibling exists in the committed prod tree.
  if git -C "$CLONE" ls-tree -r --name-only refs/heads/prod/main -- hooks/ \
       | grep -qx "$sib_path"; then
    # byte-equality: sibling == its .template in the prod tree.
    if diff <(git -C "$CLONE" show "refs/heads/prod/main:$tmpl_path") \
            <(git -C "$CLONE" show "refs/heads/prod/main:$sib_path") >/dev/null 2>&1; then
      pass "$sib: present in built prod tree and byte-equal to $bn"
    else
      fail "$sib: present in built prod tree but DIFFERS from $bn (D4 byte-equality broken)"
    fi
  else
    fail "$sib: MISSING from built prod tree (D4 generation loop did not produce it)"
  fi
done

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
