#!/usr/bin/env bash
# tests/test-sessionstart-materialise-overwrite-guard.sh
#
# Phase 2 (W2.1, D20(a)) — the materialiser's overwrite guard. Detect-by-
# prefix `^(#|<!--) zskills-materialised: `:
#
#   - A destination that is ABSENT is written.
#   - A destination carrying a zskills sentinel is REWRITTEN when its
#     content changed (zskills-owned).
#   - A destination that exists WITHOUT a sentinel is consumer-authored and
#     is NEVER clobbered.
#
# Because an un-sentinelled consumer artifact ALSO counts as
# /update-zskills-lane evidence (D27), a lone consumer-authored artifact
# alongside sentinelled ones produces lane=dual and the materialiser exits
# early — which ALSO leaves the consumer file untouched. This test asserts
# the consumer file survives in both the fresh-plus-consumer-file ordering
# and the post-materialise hand-edit ordering.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

MAT="hooks/session-start-materialise.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

make_fixture() {
  local p="$1"
  mkdir -p "$p/.claude"
  cp "$REPO_ROOT/.claude/zskills-config.json" "$p/.claude/"
  cp "$REPO_ROOT/CLAUDE_TEMPLATE.md" "$p/"
}
run_mat() {
  env CLAUDE_PROJECT_DIR="$1" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$REPO_ROOT/$MAT" 2>/dev/null
}

echo "=== materialiser overwrite guard ==="

# ── Scenario A: consumer-authored agents/verifier.md present BEFORE first
#    materialise (no sentinel). lane=update-zskills (the consumer artifact is
#    a uz-lane hit; nothing is sentinelled yet) → materialiser exits early,
#    consumer file untouched. ───────────────────────────────────────────────
PA="$TMP/a"
make_fixture "$PA"
mkdir -p "$PA/.claude/agents"
printf '%s\n' '---' 'name: my-own-verifier' '---' 'consumer body' > "$PA/.claude/agents/verifier.md"
run_mat "$PA"
if grep -q '^name: my-own-verifier' "$PA/.claude/agents/verifier.md" \
   && ! head -n 3 "$PA/.claude/agents/verifier.md" | grep -q 'zskills-materialised:'; then
  pass "A. consumer-authored verifier.md is never clobbered (no sentinel injected)"
else
  fail "A. consumer-authored verifier.md was overwritten"
  head -4 "$PA/.claude/agents/verifier.md" | sed 's/^/      /'
fi

# ── Scenario B: fresh materialise, then consumer hand-edits ONE artifact
#    (removing its sentinel). A re-run must NOT clobber the hand-edited file.
PB="$TMP/b"
make_fixture "$PB"
run_mat "$PB"
# Sanity: sentinel present after fresh materialise.
if head -n 3 "$PB/.claude/agents/implementer.md" | grep -q 'zskills-materialised:'; then
  pass "B1. fresh materialise injects sentinel into implementer.md"
else
  fail "B1. fresh materialise did NOT inject sentinel"
fi
# Consumer replaces implementer.md with their own (no sentinel).
printf '%s\n' '---' 'name: implementer' '---' 'CONSUMER OVERRIDE' > "$PB/.claude/agents/implementer.md"
run_mat "$PB"
if grep -q 'CONSUMER OVERRIDE' "$PB/.claude/agents/implementer.md"; then
  pass "B2. hand-edited (de-sentinelled) implementer.md survives re-run"
else
  fail "B2. hand-edited implementer.md was clobbered"
  sed 's/^/      /' "$PB/.claude/agents/implementer.md"
fi

# ── Scenario C: absent destination IS written on a fresh project. ─────────
PC="$TMP/c"
make_fixture "$PC"
[ ! -e "$PC/.claude/rules/zskills/managed.md" ] || fail "C0. fixture not fresh"
run_mat "$PC"
if [ -f "$PC/.claude/rules/zskills/managed.md" ] \
   && head -n 1 "$PC/.claude/rules/zskills/managed.md" | grep -q 'zskills-materialised:'; then
  pass "C. absent managed.md is written WITH sentinel on a fresh project"
else
  fail "C. absent managed.md not written / no sentinel"
fi

# ── Scenario D: a zskills-sentinelled file whose body matches canonical is
#    left mtime-stable (idempotent, no needless rewrite). ───────────────────
PD="$TMP/d"
make_fixture "$PD"
run_mat "$PD"
before="$(stat -c %Y "$PD/.claude/hooks/verify-response-validate.sh")"
sleep 1
run_mat "$PD"
after="$(stat -c %Y "$PD/.claude/hooks/verify-response-validate.sh")"
if [ "$before" = "$after" ]; then
  pass "D. unchanged sentinelled artifact keeps its mtime (idempotent)"
else
  fail "D. mtime advanced on unchanged sentinelled artifact"
fi

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
