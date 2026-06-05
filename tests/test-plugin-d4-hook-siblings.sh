#!/usr/bin/env bash
# tests/test-plugin-d4-hook-siblings.sh
#
# D4 existence gate — assert the REAL PUBLISHER's built prod tree CONTAINS
# suffixless sibling copies of every hooks/*.sh.template, byte-equal to its
# .template.
#
# THE publisher is the "🚀 Ship to Prod" button:
#   .github/workflows/ship-to-prod.yml → scripts/build-prod.sh
# build-prod.sh's shared finalizer (scripts/_lib/finalize-prod-tree.sh)
# generates suffixless sibling copies of every hooks/*.sh.template in the
# prod tree (today block-agents.sh and block-unsafe-project.sh — the two
# safety hooks hooks/hooks.json registers on the plugin lane). Those siblings
# are BUILD-ONLY: they do not exist in the source/dev tree (only the
# .template forms are committed).
#
# Why this exists (complements tests/test-hook-template-sibling.sh):
# the sibling test only asserts "IF a suffixless sibling exists in the SOURCE
# tree it is byte-equal to the .template" — and since the siblings are absent
# in source, it VACUOUS-PASSES. NOTHING there asserts the BUILT prod tree
# actually CONTAINS those hooks. A regression that removes/breaks the D4 fold
# in build-prod.sh would ship a plugin missing 2 safety hooks whose
# hooks.json registrations silently never fire — completely uncaught.
#
# This test closes that hole by running the REAL publisher (build-prod.sh)
# end-to-end and inspecting its OUTPUT. It deliberately does NOT replicate
# the D4 copy loop — deriving the siblings only from the build's output is the
# whole point: breaking D4 in build-prod.sh (or its shared finalizer) makes
# THIS test fail red.
#
# Isolation: build-prod.sh modifies the working tree IN PLACE (it strips
# dev-only artifacts and generates the D4 siblings on disk; it does NOT
# commit). Running it in the live repo would mutate it, so we run it inside a
# throwaway local git CLONE; the EXIT trap removes the clone. (#844 lesson:
# the clone gets its own clone-scoped git identity even though build-prod.sh
# does not commit — kept for parity with the other plugin-build tests and to
# survive any future commit step.)

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

echo "=== D4: REAL publisher (build-prod.sh) prod tree contains suffixless hook siblings ==="

# ── Isolated throwaway clone (build-prod.sh mutates its working tree) ────────
TMP="$(mktemp -d)"
CLONE="$TMP/clone"
trap 'rm -rf "$TMP"' EXIT

# Concurrency-safe clone via a one-shot bundle SNAPSHOT (setup-robustness only;
# assertions unchanged). This is a linked worktree → its .git objects+refs are
# SHARED with the parent repo, and under parallel test fan-out sibling suites
# churn that store, racing every LIVE clone transport (default copy → tmp_obj
# `No such file`; upload-pack → `not our ref 000...0`). `git bundle create`
# takes one atomic consistent read; cloning the static file is immune to both.
REPO_SNAPSHOT="$TMP/repo-snapshot.bundle"
git -C "$REPO_ROOT" bundle create --quiet "$REPO_SNAPSHOT" HEAD
if ! git clone --quiet "$REPO_SNAPSHOT" "$CLONE"; then
  fail "0. git clone of \$REPO_ROOT failed"
  TOTAL=$((PASS_COUNT + FAIL_COUNT))
  printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit "$FAIL_COUNT"
fi

# Clone-scoped git identity (#844) — a fresh clone inherits no user.name/
# user.email and CI runners have no global identity.
git -C "$CLONE" config user.email "d4-gate-test@zskills.invalid"
git -C "$CLONE" config user.name  "zskills D4 gate test"

# ── Enumerate every .template hook in the clone's SOURCE tree BEFORE build ──
# (Capture before the build runs — build-prod.sh leaves the .template files in
# place, but we read the canonical source list up front to derive expected
# siblings independently of the build's chatter.)
shopt -s nullglob
TEMPLATES=( "$CLONE"/hooks/*.sh.template )
shopt -u nullglob

if [ "${#TEMPLATES[@]}" -eq 0 ]; then
  fail "1. no hooks/*.sh.template found in clone (expected at least block-agents.sh.template + block-unsafe-project.sh.template)"
  TOTAL=$((PASS_COUNT + FAIL_COUNT))
  printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit "$FAIL_COUNT"
fi

# ── Run the REAL publisher (build-prod.sh) inside the clone ──────────────────
BUILD_OUT="$TMP/build.out"
if ( cd "$CLONE" && bash scripts/build-prod.sh ) > "$BUILD_OUT" 2>&1; then
  pass "0. build-prod.sh ran in isolated clone (rc=0)"
else
  fail "0. build-prod.sh FAILED in isolated clone — output below:"
  sed 's/^/      /' "$BUILD_OUT"
  TOTAL=$((PASS_COUNT + FAIL_COUNT))
  printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit "$FAIL_COUNT"
fi

# ── For each template, assert the BUILT prod tree (on disk) has the sibling ──
for tmpl in "${TEMPLATES[@]}"; do
  bn="$(basename "$tmpl")"            # e.g. block-agents.sh.template
  sib="${bn%.template}"              # e.g. block-agents.sh
  tmpl_path="$CLONE/hooks/$bn"
  sib_path="$CLONE/hooks/$sib"

  if [ -f "$sib_path" ]; then
    if diff "$tmpl_path" "$sib_path" >/dev/null 2>&1; then
      pass "$sib: present in built prod tree and byte-equal to $bn"
    else
      fail "$sib: present in built prod tree but DIFFERS from $bn (D4 byte-equality broken)"
    fi
  else
    fail "$sib: MISSING from built prod tree (D4 generation in build-prod.sh did not produce it)"
  fi
done

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
