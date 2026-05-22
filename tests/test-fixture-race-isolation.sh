#!/bin/bash
# Regression test for issue #594: parallel-process race on hardcoded
# /tmp/ synthetic-fixture paths in tests/test-hooks.sh.
#
# Background:
#   tests/test-hooks.sh's "fixture-extension" assertion sets up a
#   synthetic skills/ tree (with `__TEST_LITERAL__` appended to a copy
#   of forbidden-literals.txt and a SKILL.md containing that literal in
#   a bash fence), then runs tests/test-skill-conformance.sh against it
#   and asserts the literal appears in the conformance output.
#
#   When that fixture lived at a HARDCODED `/tmp/...` path (no PID
#   suffix), two parallel worktrees running `bash tests/run-all.sh`
#   concurrently both `rm -rf`'d and recreated the SAME path. One
#   process's mid-test `rm -rf` could wipe another's fixture between
#   setup and the conformance read, making the literal vanish from the
#   output. Empirical reproduction: 10/10 misses against a manual racer.
#
# This test:
#   Phase 1 — proves the race exists (run conformance against a SHARED
#     path while a background racer wipes it; assert >=1 miss).
#   Phase 2 — proves $$-isolation defeats the race (run conformance
#     against an ISOLATED path while the racer still hammers the shared
#     path; assert 0 misses).
#
# Both phases use $$-scoped paths so parallel CI invocations of THIS
# test don't collide with each other (or with the real test-hooks.sh
# fixtures).
#
# This test exercises only the conformance-reads-fixture half of the
# system. The fix itself (PID-scoping the paths in test-hooks.sh) is
# pinned structurally in tests/test-skill-conformance.sh (the
# "fixture-extension-test path is PID-scoped" assertions).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Capture the real repo root BEFORE overriding REPO_ROOT later. The
# conformance script lookup must always resolve via $REAL_REPO; using
# the loop-overridden $REPO_ROOT would point at the synthetic fixture
# and fail to find tests/test-skill-conformance.sh.
REAL_REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFORMANCE="$REAL_REPO/tests/test-skill-conformance.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SHARED="/tmp/zskills-race-test-shared-$$"
ISOLATED="/tmp/zskills-race-test-isolated-$$"

# Belt-and-suspenders: clean up our own $$-scoped paths up front in case
# a prior run with the same PID lingered (it shouldn't, but harmless).
rm -rf "$SHARED" "$ISOLATED"

# Setup helper: lays out a synthetic zskills-like fixture at $1 with the
# `__TEST_LITERAL__` literal appended to forbidden-literals.txt and a
# synthetic SKILL.md containing the literal in a bash fence. Mirrors
# tests/test-hooks.sh:4544-4555.
#
# In Phase 1 the racer is concurrently `rm -rf`-ing $dir/fixture, so
# any of these calls may fail mid-write — that's the point of the
# phase. Silence the expected noise to keep the test output readable;
# the assertion below (PHASE1_MISSES >= 1) is what proves the race.
setup_fixture() {
  local dir="$1"
  # Subshell + redirect-stderr-of-the-whole-block: bash prints
  # redirection-failure diagnostics for builtins (printf, cat) BEFORE
  # the per-command 2>/dev/null takes effect, so we need to redirect
  # the enclosing scope. Block-level redirect also catches mkdir/cp
  # uniformly so the visible test output stays clean.
  {
    rm -rf "$dir/fixture"
    mkdir -p "$dir/fixture/tests/fixtures"
    mkdir -p "$dir/fixture/skills/synthetic"
    cp "$REAL_REPO/tests/fixtures/forbidden-literals.txt" \
       "$dir/fixture/tests/fixtures/forbidden-literals.txt"
    printf '__TEST_LITERAL__\n' >> "$dir/fixture/tests/fixtures/forbidden-literals.txt"
    cat > "$dir/fixture/skills/synthetic/SKILL.md" <<'SKILL'
# Synthetic

```bash
echo __TEST_LITERAL__
```
SKILL
  } 2>/dev/null
}

# Background racer: wipes only $SHARED/fixture in a tight loop, gated on
# a $SHARED/racer.on flag file so we can stop it cleanly without
# kill -9 (banned by CLAUDE.md). Small jitter sleep so the race window
# overlaps with the conformance read rather than starving its CPU.
mkdir -p "$SHARED"
: > "$SHARED/racer.on"
(
  while [ -f "$SHARED/racer.on" ]; do
    rm -rf "$SHARED/fixture" 2>/dev/null
    sleep 0.01
  done
) &
RACER_PID=$!

# Phase 1: prove the race exists.
echo "=== Phase 1: race exists on shared (un-PID-scoped) path ==="
PHASE1_MISSES=0
PHASE1_ITERS=20
for i in $(seq 1 "$PHASE1_ITERS"); do
  setup_fixture "$SHARED"
  # Capture conformance output. The synthetic fixture will produce many
  # other failures (no real skills tree); we only care whether the
  # literal `__TEST_LITERAL__` appears.
  out=$(REPO_ROOT="$SHARED/fixture" bash "$CONFORMANCE" 2>&1 || true)
  if ! printf '%s' "$out" | grep -q '__TEST_LITERAL__'; then
    PHASE1_MISSES=$((PHASE1_MISSES + 1))
  fi
done
echo "  Phase 1: $PHASE1_MISSES miss(es) of $PHASE1_ITERS iterations against shared path"
if [ "$PHASE1_MISSES" -ge 1 ]; then
  pass "Phase 1: race reproducible on shared path ($PHASE1_MISSES/$PHASE1_ITERS misses)"
else
  fail "Phase 1: expected >=1 miss on shared path, got 0/$PHASE1_ITERS" \
    "racer may not be hot enough; test design needs review"
fi

# Phase 2: prove $$-isolation defeats the race.
echo ""
echo "=== Phase 2: $\$-isolation defeats the race ==="
setup_fixture "$ISOLATED"
PHASE2_MISSES=0
PHASE2_ITERS=5
for i in $(seq 1 "$PHASE2_ITERS"); do
  out=$(REPO_ROOT="$ISOLATED/fixture" bash "$CONFORMANCE" 2>&1 || true)
  if ! printf '%s' "$out" | grep -q '__TEST_LITERAL__'; then
    PHASE2_MISSES=$((PHASE2_MISSES + 1))
  fi
done
echo "  Phase 2: $PHASE2_MISSES miss(es) of $PHASE2_ITERS iterations against isolated path"
if [ "$PHASE2_MISSES" -eq 0 ]; then
  pass "Phase 2: isolated path immune to racer (0/$PHASE2_ITERS misses)"
else
  fail "Phase 2: expected 0 misses on isolated path, got $PHASE2_MISSES/$PHASE2_ITERS" \
    "PID-scoped path should not be visible to racer hitting the shared path"
fi

# Stop the racer cleanly via the flag file (NO kill -9 / killall / pkill,
# CLAUDE.md rule). Then wait on the specific PID, not bare `wait`.
rm -f "$SHARED/racer.on"
wait "$RACER_PID" 2>/dev/null || true

# Cleanup the $$-scoped fixture trees. These literal prefixes are
# script-body and thus exempt from block-unsafe-generic.sh's agent-shell
# gate (per hooks/block-unsafe-generic.sh:710-712).
rm -rf "/tmp/zskills-race-test-shared-$$"
rm -rf "/tmp/zskills-race-test-isolated-$$"

echo ""
echo "---"
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (of %d)\033[0m\n' "$PASS_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (of %d)\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit 1
fi
