#!/bin/bash
# Regression test for issue #380: tests checking committed state (via
# `git ls-tree HEAD` and `git log -1 --pretty=format:%H`) must fail
# loudly when their target paths have uncommitted working-tree changes.
#
# Two tests were affected:
#   1. tests/test-skill-invariants.sh — Tier-1 drift block (`git ls-tree HEAD`)
#   2. tests/test-update-zskills-migration.sh — case 6c commit-cohabitation
#      (`git log -1 --pretty=format:%H`)
#
# Both silently reported PASS when an agent had modified a Tier-1 script in
# the working tree pre-commit, because the committed-state lookups still
# returned the OLD (registered) state. Once the agent committed, the lookups
# advanced and the tests flipped to FAIL — too late, the verifier had already
# moved on.
#
# Fix (approach A from issue body): each test now diffs the working tree
# against HEAD for the paths it inspects, and ERRORs loudly if any path is
# dirty, forcing commit-then-test discipline.
#
# This regression test locks in the fix by asserting:
#   1. The fix anchors are present in both test files (text-level).
#   2. The fix logic works against a synthetic git repo: a fake Tier-1 script
#      is dirtied in the working tree and the pre-flight `git diff --quiet
#      HEAD --` primitive correctly detects it.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# --- Anchor checks: fix prose is present in both test files ---

if grep -q 'git diff --quiet HEAD --' "$REPO_ROOT/tests/test-skill-invariants.sh" \
   && grep -q 'Issue #380 fix' "$REPO_ROOT/tests/test-skill-invariants.sh" \
   && grep -q 'pre-flight working-tree-vs-HEAD clean' "$REPO_ROOT/tests/test-skill-invariants.sh"; then
  pass "anchor: test-skill-invariants.sh has working-tree-vs-HEAD pre-flight"
else
  fail "anchor: test-skill-invariants.sh has working-tree-vs-HEAD pre-flight" \
       "missing one of: 'git diff --quiet HEAD --', 'Issue #380 fix', 'pre-flight working-tree-vs-HEAD clean'"
fi

if grep -q 'git -C "\$REPO_ROOT" diff --quiet HEAD --' "$REPO_ROOT/tests/test-update-zskills-migration.sh" \
   && grep -q 'Issue #380 fix' "$REPO_ROOT/tests/test-update-zskills-migration.sh" \
   && grep -q 'case 6c: uncommitted changes' "$REPO_ROOT/tests/test-update-zskills-migration.sh"; then
  pass "anchor: test-update-zskills-migration.sh case 6c has working-tree-vs-HEAD pre-flight"
else
  fail "anchor: test-update-zskills-migration.sh case 6c has working-tree-vs-HEAD pre-flight" \
       "missing one of: 'git -C \$REPO_ROOT diff --quiet HEAD --', 'Issue #380 fix', 'case 6c: uncommitted changes'"
fi

# --- Synthetic fixture: verify the dirty-detection primitive ---
#
# Build a tiny git repo with one tracked file. Confirm:
#   (a) clean tree: `git diff --quiet HEAD -- <path>` returns 0 (no dirty).
#   (b) modify the file in the working tree: `git diff --quiet HEAD -- <path>`
#       now returns non-zero, matching the new pre-flight check's trigger.
#   (c) revert: returns 0 again.
# This is the primitive both production tests now lean on; locking it in
# documents the contract and guards against future git-behavior surprises.

SANDBOX="${TMPDIR:-/tmp}/zskills-issue-380-fixture.$$"
trap 'rm -rf "$SANDBOX"' EXIT
rm -rf "$SANDBOX"
mkdir -p "$SANDBOX"

(
  cd "$SANDBOX"
  git init --quiet
  git config user.email test@example.com
  git config user.name test
  printf '#!/bin/bash\necho original\n' > fake-tier1.sh
  git add fake-tier1.sh
  git commit --quiet -m "seed"
) || {
  fail "synthetic fixture: init" "git init / commit failed"
  echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
  [ "$FAIL_COUNT" -eq 0 ]
  exit
}

# (a) Clean tree.
if git -C "$SANDBOX" diff --quiet HEAD -- fake-tier1.sh; then
  pass "primitive (a): clean tree → git diff --quiet HEAD returns 0"
else
  fail "primitive (a): clean tree → git diff --quiet HEAD returns 0" \
       "got non-zero exit on a clean tree"
fi

# (b) Modify in working tree only.
printf 'echo modified\n' >> "$SANDBOX/fake-tier1.sh"
if ! git -C "$SANDBOX" diff --quiet HEAD -- fake-tier1.sh; then
  pass "primitive (b): dirty working tree → git diff --quiet HEAD returns non-zero (dirty detected)"
else
  fail "primitive (b): dirty working tree → git diff --quiet HEAD returns non-zero (dirty detected)" \
       "got zero exit on a dirty tree (false-PASS bug not detected)"
fi

# (c) Revert.
git -C "$SANDBOX" checkout -- fake-tier1.sh
if git -C "$SANDBOX" diff --quiet HEAD -- fake-tier1.sh; then
  pass "primitive (c): after revert → git diff --quiet HEAD returns 0"
else
  fail "primitive (c): after revert → git diff --quiet HEAD returns 0" \
       "got non-zero exit after checkout --"
fi

# (d) Also verify the staged-only case: `git add` a change, but DON'T commit.
# `git ls-tree HEAD` would still return the OLD blob, so the staged-only case
# is ALSO a false-PASS scenario. `git diff --quiet HEAD` (no `--cached`)
# compares working tree against HEAD, which detects both staged and unstaged
# changes. Lock this in.
printf 'echo modified again\n' >> "$SANDBOX/fake-tier1.sh"
git -C "$SANDBOX" add fake-tier1.sh
if ! git -C "$SANDBOX" diff --quiet HEAD -- fake-tier1.sh; then
  pass "primitive (d): staged-but-not-committed → git diff --quiet HEAD still detects dirty"
else
  fail "primitive (d): staged-but-not-committed → git diff --quiet HEAD still detects dirty" \
       "got zero exit on a staged change (staged-only false-PASS bug not detected)"
fi

echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
