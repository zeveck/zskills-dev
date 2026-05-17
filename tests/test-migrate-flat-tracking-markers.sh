#!/bin/bash
# Tests for scripts/migrate-flat-tracking-markers.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/migrate-flat-tracking-markers.sh"

# Per-worktree+per-PID scratch namespace so concurrent suite runs in
# different worktrees don't race on shared fixture paths (issue #322).
FIXTURE_NS="$(basename "$REPO_ROOT")-$$"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# Each test runs in a fresh fixture directory under /tmp, namespaced by
# worktree + PID to keep parallel suite runs isolated.
fixture() {
  local name="$1"
  local dir="/tmp/zskills-migration-test-${FIXTURE_NS}-${name}"
  rm -rf "$dir"
  mkdir -p "$dir/.zskills/tracking"
  printf '%s' "$dir"
}

cleanup() {
  local dir="$1"
  case "$dir" in
    /tmp/zskills-migration-test-*) rm -rf "$dir" ;;
    *) echo "REFUSED: cleanup target outside /tmp/zskills-migration-test-*: $dir" >&2 ;;
  esac
}

echo "=== Case 1 — empty tracking dir is a no-op ==="
DIR=$(fixture empty)
out=$(bash "$SCRIPT" "$DIR" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [[ "$out" =~ "Summary: 0 migrated, 0 duplicates removed, 0 conflicts." ]]; then
  pass "empty dir — exit 0, zero counts"
else
  fail "empty dir — rc=$rc, out=$out"
fi
cleanup "$DIR"

echo
echo "=== Case 2 — missing tracking dir is a no-op ==="
DIR="/tmp/zskills-migration-test-${FIXTURE_NS}-missing"
rm -rf "$DIR"
mkdir -p "$DIR"
out=$(bash "$SCRIPT" "$DIR" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [[ "$out" =~ "nothing to migrate" ]]; then
  pass "missing .zskills/tracking — exit 0, friendly message"
else
  fail "missing tracking — rc=$rc, out=$out"
fi
cleanup "$DIR"

echo
echo "=== Case 3 — pure migration (flat with no subdir) ==="
DIR=$(fixture pure)
echo 'date: 2026-01-01' > "$DIR/.zskills/tracking/fulfilled.run-plan.alpha"
out=$(bash "$SCRIPT" "$DIR" 2>&1); rc=$?
if [ "$rc" -eq 0 ] \
   && [ ! -f "$DIR/.zskills/tracking/fulfilled.run-plan.alpha" ] \
   && [ -f "$DIR/.zskills/tracking/run-plan.alpha/fulfilled.run-plan.alpha" ] \
   && [[ "$out" =~ "1 migrated" ]]; then
  pass "pure migration — file moved into subdir, flat gone"
else
  fail "pure migration — rc=$rc, out=$out"
fi
cleanup "$DIR"

echo
echo "=== Case 4 — content preserved across move ==="
DIR=$(fixture content)
printf 'skill: run-plan\nid: beta\nstatus: complete\ndate: 2026-02-15T10:00:00-04:00\n' \
  > "$DIR/.zskills/tracking/fulfilled.run-plan.beta"
bash "$SCRIPT" "$DIR" >/dev/null 2>&1
moved="$DIR/.zskills/tracking/run-plan.beta/fulfilled.run-plan.beta"
if [ -f "$moved" ] && grep -q 'date: 2026-02-15T10:00:00-04:00' "$moved" \
   && grep -q 'status: complete' "$moved"; then
  pass "content preserved — date + status fields intact post-migration"
else
  fail "content preserved — moved file content lost or absent at $moved"
fi
cleanup "$DIR"

echo
echo "=== Case 5 — identical duplicate (flat AND subdir, same content) ==="
DIR=$(fixture dup)
mkdir -p "$DIR/.zskills/tracking/run-plan.gamma"
echo 'date: 2026-03-03' > "$DIR/.zskills/tracking/fulfilled.run-plan.gamma"
echo 'date: 2026-03-03' > "$DIR/.zskills/tracking/run-plan.gamma/fulfilled.run-plan.gamma"
out=$(bash "$SCRIPT" "$DIR" 2>&1); rc=$?
if [ "$rc" -eq 0 ] \
   && [ ! -f "$DIR/.zskills/tracking/fulfilled.run-plan.gamma" ] \
   && [ -f "$DIR/.zskills/tracking/run-plan.gamma/fulfilled.run-plan.gamma" ] \
   && [[ "$out" =~ "1 duplicates removed" ]]; then
  pass "identical duplicate — flat removed, subdir preserved"
else
  fail "identical duplicate — rc=$rc, out=$out"
fi
cleanup "$DIR"

echo
echo "=== Case 6 — conflicting copies (different content; flat preserved) ==="
DIR=$(fixture conflict)
mkdir -p "$DIR/.zskills/tracking/run-plan.delta"
echo 'date: 2026-04-04-flat'   > "$DIR/.zskills/tracking/fulfilled.run-plan.delta"
echo 'date: 2026-04-04-subdir' > "$DIR/.zskills/tracking/run-plan.delta/fulfilled.run-plan.delta"
out=$(bash "$SCRIPT" "$DIR" 2>&1); rc=$?
if [ "$rc" -eq 2 ] \
   && [ -f "$DIR/.zskills/tracking/fulfilled.run-plan.delta" ] \
   && [ -f "$DIR/.zskills/tracking/run-plan.delta/fulfilled.run-plan.delta" ] \
   && grep -q '2026-04-04-flat' "$DIR/.zskills/tracking/fulfilled.run-plan.delta" \
   && grep -q '2026-04-04-subdir' "$DIR/.zskills/tracking/run-plan.delta/fulfilled.run-plan.delta" \
   && [[ "$out" =~ "1 conflicts" ]] \
   && [[ "$out" =~ "CONFLICT: fulfilled.run-plan.delta" ]]; then
  pass "conflict — both files preserved, exit 2, CONFLICT logged"
else
  fail "conflict — rc=$rc, out=$out"
fi
cleanup "$DIR"

echo
echo "=== Case 7 — idempotency (rerun on already-migrated state is a no-op) ==="
DIR=$(fixture idempotent)
echo 'date: 2026-05-05' > "$DIR/.zskills/tracking/fulfilled.run-plan.epsilon"
bash "$SCRIPT" "$DIR" >/dev/null 2>&1
# Re-run
out2=$(bash "$SCRIPT" "$DIR" 2>&1); rc2=$?
if [ "$rc2" -eq 0 ] && [[ "$out2" =~ "Summary: 0 migrated, 0 duplicates removed, 0 conflicts." ]]; then
  pass "idempotent — second run reports zero changes"
else
  fail "idempotent — rc=$rc2, out=$out2"
fi
cleanup "$DIR"

echo
echo "=== Case 8 — multiple files, mixed cases in one run ==="
DIR=$(fixture mixed)
echo 'a' > "$DIR/.zskills/tracking/fulfilled.run-plan.one"
mkdir -p "$DIR/.zskills/tracking/run-plan.two"
echo 'b' > "$DIR/.zskills/tracking/fulfilled.run-plan.two"
echo 'b' > "$DIR/.zskills/tracking/run-plan.two/fulfilled.run-plan.two"
mkdir -p "$DIR/.zskills/tracking/run-plan.three"
echo 'flat'   > "$DIR/.zskills/tracking/fulfilled.run-plan.three"
echo 'subdir' > "$DIR/.zskills/tracking/run-plan.three/fulfilled.run-plan.three"
out=$(bash "$SCRIPT" "$DIR" 2>&1); rc=$?
if [ "$rc" -eq 2 ] \
   && [[ "$out" =~ "1 migrated, 1 duplicates removed, 1 conflicts" ]] \
   && [ -f "$DIR/.zskills/tracking/run-plan.one/fulfilled.run-plan.one" ] \
   && [ ! -f "$DIR/.zskills/tracking/fulfilled.run-plan.two" ] \
   && [ -f "$DIR/.zskills/tracking/fulfilled.run-plan.three" ]; then
  pass "mixed batch — one migrated, one deduped, one conflict; counts and file presence correct"
else
  fail "mixed batch — rc=$rc, out=$out"
fi
cleanup "$DIR"

echo
echo "=== Case 9 — non-fulfilled.* files are NOT touched ==="
DIR=$(fixture noise)
echo 'noise' > "$DIR/.zskills/tracking/some-random-file.txt"
echo 'noise' > "$DIR/.zskills/tracking/.gitignore"
bash "$SCRIPT" "$DIR" >/dev/null 2>&1
if [ -f "$DIR/.zskills/tracking/some-random-file.txt" ] \
   && [ -f "$DIR/.zskills/tracking/.gitignore" ]; then
  pass "non-fulfilled files left alone"
else
  fail "non-fulfilled files modified"
fi
cleanup "$DIR"

echo
echo "---"
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (of %d)\033[0m\n' "$PASS_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (of %d)\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit 1
fi
