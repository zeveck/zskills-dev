#!/usr/bin/env bash
# tests/test-hook-template-sibling.sh
#
# Phase 2 (W2.4, D4) — the .template hook strategy. On the /update-zskills
# lane, block-agents.sh.template and block-unsafe-project.sh.template keep
# the .template suffix (it signals install-time substitution). On the plugin
# lane, build-plugin-release.sh (W5.5, release-time) generates a sibling
# suffixless copy in the plugin tree. The plugin's hooks.json registers the
# suffixless form.
#
# This test asserts: for each .template hook, IF a suffixless sibling exists
# in the same directory, the two are byte-equal. The suffixless generation
# is release-time work (W5.5), so the sibling is ABSENT in the source tree —
# the test TOLERATES that (it asserts presence-implies-equality, not
# presence). When release tooling lands, the same assertion gates drift.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

echo "=== .template hook / suffixless sibling byte-equality (D4) ==="

# Enumerate every .template hook in hooks/ (do NOT pin a frozen list — D4
# names block-agents + block-unsafe-project today but the set may grow).
shopt -s nullglob
TEMPLATES=( hooks/*.sh.template )
shopt -u nullglob

if [ "${#TEMPLATES[@]}" -eq 0 ]; then
  fail "0. no hooks/*.sh.template found (expected at least block-agents.sh.template)"
fi

for tmpl in "${TEMPLATES[@]}"; do
  sibling="${tmpl%.template}"   # strip the .template suffix
  bn="$(basename "$tmpl")"
  if [ -f "$sibling" ]; then
    if diff -q "$tmpl" "$sibling" >/dev/null 2>&1; then
      pass "$bn: suffixless sibling present and byte-equal"
    else
      fail "$bn: suffixless sibling DIFFERS from .template (drift)"
      diff "$tmpl" "$sibling" | head -20 | sed 's/^/      /'
    fi
  else
    # Sibling absent in the source tree — release-time generation (W5.5).
    pass "$bn: suffixless sibling absent in source tree (generated at release time — tolerated)"
  fi
done

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
