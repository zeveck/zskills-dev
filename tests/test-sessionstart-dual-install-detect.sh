#!/usr/bin/env bash
# tests/test-sessionstart-dual-install-detect.sh
#
# Phase 2 (W2.8, D27, A12) — the dual-install detection probe
# detect_install_state() and the SessionStart materialiser's behaviour for
# each lane state.
#
# Exercises all 4 lane states + a 5th partial-cleanup fixture:
#   1. fresh          → detect_install_state == fresh; materialiser writes.
#   2. plugin         → detect == plugin; materialiser writes.
#   3. update-zskills → detect == update-zskills; materialiser EXITS EARLY
#      with WARN + dual-install-warned marker; does NOT materialise.
#   4. dual           → detect == dual; materialiser EXITS EARLY with the
#      dual WARN + marker; does NOT materialise.
#   5. partial-cleanup (orphan hook, deleted SKILL.md, no sentinels) →
#      classifies as update-zskills + early exit (F-R2-3 closure).

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

MAT="hooks/session-start-materialise.sh"
DETECT="hooks/_lib/detect-install-state.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=/dev/null
. "$REPO_ROOT/$DETECT"

base_fixture() {
  # A fresh project with config + template (no .claude artifacts).
  local p="$1"
  mkdir -p "$p/.claude"
  cp "$REPO_ROOT/.claude/zskills-config.json" "$p/.claude/"
  cp "$REPO_ROOT/CLAUDE_TEMPLATE.md" "$p/"
}
# Write a plugin-materialised (sentinelled) artifact.
write_sentinelled_hook() {
  mkdir -p "$(dirname "$1")"
  printf '%s\n' '#!/usr/bin/env bash' '# zskills-materialised: 2026.05.0' 'echo hi' > "$1"
}
write_sentinelled_managed() {
  mkdir -p "$(dirname "$1")"
  printf '%s\n' '<!-- zskills-materialised: 2026.05.0 -->' '# rules' > "$1"
}
# Write an update-zskills-installed (UN-sentinelled) artifact.
write_unsentinelled_skill() {
  mkdir -p "$(dirname "$1")"
  printf '%s\n' '---' 'name: x' '---' 'body' > "$1"
}
write_unsentinelled_hook() {
  mkdir -p "$(dirname "$1")"
  printf '%s\n' '#!/usr/bin/env bash' '# zskills-hook-version: 2026.05.0' 'echo hi' > "$1"
}
run_mat() {
  env CLAUDE_PROJECT_DIR="$1" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$REPO_ROOT/$MAT" 2>"$2"
}

echo "=== dual-install detection probe (D27) ==="

# ── 1. fresh ──────────────────────────────────────────────────────────────
P1="$TMP/fresh"
base_fixture "$P1"
got="$(detect_install_state "$P1")"
[ "$got" = fresh ] && pass "1a. lane=fresh detected" || fail "1a. expected fresh, got $got"
err1="$TMP/err1"; run_mat "$P1" "$err1"
if [ -f "$P1/.claude/rules/zskills/managed.md" ]; then
  pass "1b. fresh: materialiser writes the 5 artifacts"
else
  fail "1b. fresh: materialiser did not write"
fi

# ── 2. plugin (sentinelled artifacts only) ───────────────────────────────
P2="$TMP/plugin"
base_fixture "$P2"
write_sentinelled_hook "$P2/.claude/hooks/inject-bash-timeout.sh"
write_sentinelled_managed "$P2/.claude/rules/zskills/managed.md"
got="$(detect_install_state "$P2")"
[ "$got" = plugin ] && pass "2a. lane=plugin detected" || fail "2a. expected plugin, got $got"
err2="$TMP/err2"; run_mat "$P2" "$err2"
# Plugin lane → materialiser runs (writes verifier/implementer agents).
if [ -f "$P2/.claude/agents/verifier.md" ]; then
  pass "2b. plugin: materialiser runs (verifier.md materialised)"
else
  fail "2b. plugin: materialiser did not run"
fi

# ── 3. update-zskills (un-sentinelled SKILL.md mirror) ────────────────────
P3="$TMP/uz"
base_fixture "$P3"
write_unsentinelled_skill "$P3/.claude/skills/update-zskills/SKILL.md"
got="$(detect_install_state "$P3")"
[ "$got" = update-zskills ] && pass "3a. lane=update-zskills detected" || fail "3a. expected update-zskills, got $got"
err3="$TMP/err3"; run_mat "$P3" "$err3"
# Materialiser must EXIT EARLY — no agents materialised.
if [ ! -e "$P3/.claude/agents/verifier.md" ]; then
  pass "3b. update-zskills: materialiser exits early (no clobber)"
else
  fail "3b. update-zskills: materialiser wrote artifacts (should have skipped)"
fi
if grep -q 'install lane is /update-zskills' "$err3" \
   && grep -q -- '--switch-install-path=to-plugin' "$err3"; then
  pass "3c. update-zskills: documented WARN emitted"
else
  fail "3c. update-zskills WARN text missing"
  sed 's/^/      /' "$err3"
fi
if [ -f "$P3/.zskills/dual-install-warned" ]; then
  pass "3d. update-zskills: dual-install-warned marker created"
else
  fail "3d. dual-install-warned marker NOT created"
fi

# ── 4. dual (both sentinelled AND un-sentinelled evidence) ────────────────
P4="$TMP/dual"
base_fixture "$P4"
write_sentinelled_hook "$P4/.claude/hooks/inject-bash-timeout.sh"   # plugin evidence
write_unsentinelled_skill "$P4/.claude/skills/run-plan/SKILL.md"     # uz evidence
got="$(detect_install_state "$P4")"
[ "$got" = dual ] && pass "4a. lane=dual detected" || fail "4a. expected dual, got $got"
err4="$TMP/err4"; run_mat "$P4" "$err4"
if [ ! -e "$P4/.claude/agents/verifier.md" ]; then
  pass "4b. dual: materialiser exits early (no clobber)"
else
  fail "4b. dual: materialiser wrote artifacts (should have skipped)"
fi
if grep -q 'dual install detected' "$err4" \
   && grep -q 'switch-install-path.sh --to-plugin' "$err4"; then
  pass "4c. dual: documented WARN emitted"
else
  fail "4c. dual WARN text missing"
  sed 's/^/      /' "$err4"
fi
if [ -f "$P4/.zskills/dual-install-warned" ]; then
  pass "4d. dual: dual-install-warned marker created"
else
  fail "4d. dual-install-warned marker NOT created"
fi

# ── 5. partial-cleanup: orphan hook, deleted SKILL.md, no sentinels ───────
#    (F-R2-3) — consumer manually deleted .claude/skills/.../SKILL.md to
#    "clean up" but orphaned an un-sentinelled .claude/hooks/*.sh +
#    managed.md. Must classify as update-zskills and early-exit.
P5="$TMP/partial"
base_fixture "$P5"
write_unsentinelled_hook "$P5/.claude/hooks/block-stale-skill-version.sh"
mkdir -p "$P5/.claude/rules/zskills"
printf '%s\n' '# zskills rules (unsentinelled, /update-zskills-written)' > "$P5/.claude/rules/zskills/managed.md"
got="$(detect_install_state "$P5")"
[ "$got" = update-zskills ] && pass "5a. partial-cleanup classifies as update-zskills" || fail "5a. expected update-zskills, got $got"
err5="$TMP/err5"; run_mat "$P5" "$err5"
if [ ! -e "$P5/.claude/agents/verifier.md" ] \
   && grep -q 'install lane is /update-zskills' "$err5"; then
  pass "5b. partial-cleanup: materialiser exits early with WARN (no clobber)"
else
  fail "5b. partial-cleanup early-exit failed"
  sed 's/^/      /' "$err5"
fi

# ── 6. once-per-session gating: a second materialise run on the uz fixture
#    does NOT re-emit the WARN (marker already present). ─────────────────────
err3b="$TMP/err3b"; run_mat "$P3" "$err3b"
if [ ! -s "$err3b" ]; then
  pass "6. WARN is gated once-per-session (marker suppresses repeat)"
else
  fail "6. WARN re-emitted despite existing marker"
  sed 's/^/      /' "$err3b"
fi

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
