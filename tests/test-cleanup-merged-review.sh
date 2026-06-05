#!/bin/bash
# Tests for skills/cleanup-merged/SKILL.md redesign (issue #716).
#
# Coverage:
#   Static (skill-source assertions):
#     1.  argument-hint contains new tokens (apply, remote, all)
#     2.  Positional token parsing: apply, remote, all accepted
#     3.  Migration aliases: --dry-run/-n and --review accepted with deprecation
#     4.  Phase 5 heading present (local branch scan)
#     5.  Phase 6 heading present (remote branch scan)
#     6.  Phase 7 heading present (summary)
#     7.  Protected branches loaded from cleanup.protected_branches config
#     8.  is_protected() function present
#     9.  Mirror sync: skills/cleanup-merged/ == .claude/skills/cleanup-merged/
#    10.  Preview/apply output strings preserved (WOULD-DELETE, WOULD-REMOVE-WORKTREE)
#    11.  Schema: cleanup.protected_branches array field present
#    12.  Remote cleanup: git push origin --delete present
#    13.  gh pr view gating for remote branches
#    14.  PROTECTED (config) label in output
#    15.  Apply command hint in preview summary
#
# Run from repo root: bash tests/test-cleanup-merged-review.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/skills/cleanup-merged/SKILL.md"
SCHEMA="$REPO_ROOT/config/zskills-config.schema.json"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

echo "=== cleanup-merged redesign tests (issue #716) ==="

# -- Static checks --

# 1. argument-hint contains new tokens
if grep -qE '^argument-hint:.*apply.*remote.*all' "$SKILL"; then
  pass "argument-hint advertises apply/remote/all"
else
  fail "argument-hint missing new tokens"
fi

# 2. Positional token parsing
if grep -q 'apply)  APPLY=1' "$SKILL" \
   && grep -q 'remote) SCOPE="remote"' "$SKILL" \
   && grep -q 'all)    SCOPE="all"' "$SKILL"; then
  pass "Phase 1.2: positional tokens apply/remote/all accepted"
else
  fail "Phase 1.2: positional token parsing incomplete"
fi

# 3. Migration aliases: --dry-run and --review emit deprecation notice
if grep -q 'DEPRECATED.*--dry-run' "$SKILL" \
   && grep -q 'DEPRECATED.*--review' "$SKILL"; then
  pass "migration aliases --dry-run/--review present with deprecation"
else
  fail "migration aliases missing deprecation notices"
fi

# 4. Phase 5 heading (local branch scan)
if grep -qE '^## Phase 5 — Local branch scan' "$SKILL"; then
  pass "Phase 5 heading present (local branch scan)"
else
  fail "Phase 5 heading missing"
fi

# 5. Phase 6 heading (remote branch scan)
if grep -qE '^## Phase 6 — Remote branch scan' "$SKILL"; then
  pass "Phase 6 heading present (remote branch scan)"
else
  fail "Phase 6 heading missing"
fi

# 6. Phase 7 heading (summary)
if grep -qE '^## Phase 7 — Summary' "$SKILL"; then
  pass "Phase 7 heading present (summary)"
else
  fail "Phase 7 heading missing"
fi

# 7. Protected branches loaded from cleanup.protected_branches
if grep -q 'cleanup.*protected_branches' "$SKILL" \
   && grep -q 'PROTECTED_BRANCHES' "$SKILL"; then
  pass "cleanup.protected_branches wired into preflight"
else
  fail "cleanup.protected_branches not wired"
fi

# 8. is_protected function present
if grep -q 'is_protected()' "$SKILL"; then
  pass "is_protected() function present"
else
  fail "is_protected() function missing"
fi

# 9. Mirror sync
MIRROR="$REPO_ROOT/.claude/skills/cleanup-merged"
if [ -d "$MIRROR" ]; then
  if diff -q "$SKILL" "$MIRROR/SKILL.md" >/dev/null; then
    pass "mirror sync: skills/cleanup-merged/SKILL.md == .claude mirror"
  else
    fail "mirror drift: skills/ vs .claude/skills/ differ"
  fi
else
  fail "mirror directory .claude/skills/cleanup-merged absent"
fi

# 10. Preview output (#1113 redesign): grouped headers + suffix tokens
# replace the legacy per-line WOULD-DELETE / WOULD-REMOVE-WORKTREE prints.
# Verify the new shape is present (header pattern + at least one suffix).
if grep -q ' to delete (PR merged):' "$SKILL" \
   && grep -q 'and worktree' "$SKILL" \
   && grep -q 'has worktree' "$SKILL"; then
  pass "preview output: #1113 grouped headers + worktree suffix tokens present"
else
  fail "preview output: #1113 grouped output regressed"
fi

# 11. Schema: cleanup.protected_branches field
if grep -q '"protected_branches"' "$SCHEMA" \
   && grep -q '"cleanup"' "$SCHEMA"; then
  pass "schema: cleanup.protected_branches defined"
else
  fail "schema: cleanup.protected_branches missing"
fi

# 12. Remote cleanup via git push origin --delete
if grep -q 'git push origin --delete' "$SKILL"; then
  pass "remote cleanup: git push origin --delete present"
else
  fail "remote cleanup: git push origin --delete missing"
fi

# 13. gh pr view gating for remote branches
if grep -q 'gh pr view' "$SKILL" \
   && grep -q 'PR_STATE.*OPEN' "$SKILL"; then
  pass "gh pr view gating for remote branches"
else
  fail "gh pr view gating missing for remote branches"
fi

# 14. PROTECTED (config) label in output
if grep -q 'PROTECTED (config)' "$SKILL"; then
  pass "PROTECTED (config) label in output"
else
  fail "PROTECTED (config) label missing"
fi

# 15. Apply command hint in preview summary
if grep -q 'APPLY_CMD' "$SKILL" \
   && grep -q 'to execute' "$SKILL"; then
  pass "apply command hint in preview summary"
else
  fail "apply command hint missing in preview summary"
fi

# 16. Remote preview (#1113 redesign): grouped "Remote — N to delete
# (PR merged):" header replaces the legacy per-line WOULD-DELETE-REMOTE.
if grep -q 'Remote — ' "$SKILL" \
   && grep -q ' to delete (PR merged):' "$SKILL"; then
  pass "remote preview: #1113 grouped header present"
else
  fail "remote preview: #1113 grouped header missing"
fi

# 17. DELETED-REMOTE for remote apply
if grep -q 'DELETED-REMOTE' "$SKILL"; then
  pass "DELETED-REMOTE output string present"
else
  fail "DELETED-REMOTE output string missing"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] && exit 0 || exit 1
