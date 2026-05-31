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
#      with an imperative nag EVERY session (W6.3 — no once-per-session
#      marker gate); does NOT materialise.
#   4. dual           → detect == dual; materialiser EXITS EARLY with the
#      dual nag EVERY session (W6.3); does NOT materialise.
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
   && grep -q 'not a supported client state' "$err3" \
   && grep -q 'switch-install-path.sh' "$err3"; then
  pass "3c. update-zskills: imperative nag emitted (W6.3)"
else
  fail "3c. update-zskills nag text missing"
  sed 's/^/      /' "$err3"
fi
# W6.3 — the once-per-session marker gate is removed; the materialiser must
# NOT write a .zskills/dual-install-warned marker any more.
if [ ! -e "$P3/.zskills/dual-install-warned" ]; then
  pass "3d. update-zskills: no once-per-session marker (W6.3 gate dropped)"
else
  fail "3d. dual-install-warned marker unexpectedly created (W6.3 should have dropped it)"
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
   && grep -q 'not a supported client state' "$err4" \
   && grep -q 'switch-install-path.sh' "$err4"; then
  pass "4c. dual: imperative nag emitted (W6.3)"
else
  fail "4c. dual nag text missing"
  sed 's/^/      /' "$err4"
fi
# W6.3 — no once-per-session marker any more.
if [ ! -e "$P4/.zskills/dual-install-warned" ]; then
  pass "4d. dual: no once-per-session marker (W6.3 gate dropped)"
else
  fail "4d. dual-install-warned marker unexpectedly created (W6.3 should have dropped it)"
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

# ── 6. W6.3 — the nag fires EVERY session (no once-per-session gate): a
#    second materialise run on the uz fixture RE-EMITS the nag. ──────────────
err3b="$TMP/err3b"; run_mat "$P3" "$err3b"
if grep -q 'not a supported client state' "$err3b"; then
  pass "6. nag re-emitted every session (W6.3 — no once-per-session gate)"
else
  fail "6. nag NOT re-emitted on second run (W6.3 requires every-session nag)"
  sed 's/^/      /' "$err3b"
fi

# ── 7. W6.2 — switch-in-progress marker skips re-materialise on the plugin
#    fixture: a session during an in-flight --to-update-zskills switch must
#    NOT re-arm detect==plugin (no agents written) even though detect==plugin.
P7="$TMP/switching"
base_fixture "$P7"
write_sentinelled_hook "$P7/.claude/hooks/inject-bash-timeout.sh"
write_sentinelled_managed "$P7/.claude/rules/zskills/managed.md"
got="$(detect_install_state "$P7")"
[ "$got" = plugin ] && pass "7a. switching fixture still classifies plugin" || fail "7a. expected plugin, got $got"
mkdir -p "$P7/.zskills"; : > "$P7/.zskills/switch-in-progress"
err7="$TMP/err7"; run_mat "$P7" "$err7"
if [ ! -e "$P7/.claude/agents/verifier.md" ]; then
  pass "7b. switch-in-progress: materialiser skips re-materialise (no re-arm)"
else
  fail "7b. switch-in-progress: materialiser re-armed detect==plugin (should skip)"
fi

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
