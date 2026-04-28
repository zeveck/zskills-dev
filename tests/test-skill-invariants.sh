#!/bin/bash
# Regression invariants for features deleted by faab84b.
#
# Asserts every restored feature's load-bearing anchor text exists.
# Catches faab84b-class silent deletions in CI before they escape
# to a release. If any check fails, the offending feature is
# silently gone — fix the skill, not this test.
#
# Output format follows tests/run-all.sh convention:
#   "Results: N passed, M failed"
# so run-all.sh aggregates counts.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT" || exit 1

PASS=0
FAIL=0

check() {
  local desc="$1"
  local cmd="$2"
  if eval "$cmd"; then
    PASS=$((PASS+1))
  else
    echo "FAIL: $desc" >&2
    FAIL=$((FAIL+1))
  fi
}

# Phase A: chunked finish auto
check "chunked finish auto Step 0" \
  'grep -q "Idempotent re-entry check (chunked finish auto only)" skills/run-plan/SKILL.md'
check "chunked finish auto Phase 5c" \
  'grep -q "Phase 5c — Chunked finish auto transition" skills/run-plan/SKILL.md'

# Phase B: cross-branch final verify
check "final-verify marker in research-and-go" \
  'grep -q "requires.verify-changes.final" skills/research-and-go/SKILL.md'
check "final-verify fulfillment ref" \
  'grep -q "fulfilled.verify-changes.final" skills/research-and-go/SKILL.md'
check "research-and-go pre-decides meta-plan path" \
  'grep -q "META_PLAN_PATH=" skills/research-and-go/SKILL.md'
check "research-and-go drops every 4h" \
  '! grep -q "every 4h now" skills/research-and-go/SKILL.md'

# Phase C: tool-list-aware dispatch (4 skills)
for f in skills/run-plan/SKILL.md skills/fix-issues/SKILL.md \
         skills/verify-changes/SKILL.md \
         block-diagram/add-block/SKILL.md; do
  check "tool-list-aware dispatch in $f" \
    "grep -q 'Check your tool list' '$f'"
done

# Phase D: prohibition explanation (anchor phrases)
check "prohibition: subagents cannot dispatch" \
  'grep -q "Subagents in Claude Code cannot dispatch further subagents" skills/research-and-plan/SKILL.md'
check "prohibition: skill tool recursion mechanism" \
  'grep -q "Skill tool is the recursion mechanism" skills/research-and-plan/SKILL.md'
check "prohibition: docs URL" \
  'grep -q "code.claude.com/docs/en/sub-agents" skills/research-and-plan/SKILL.md'

# Phase E: early requires-lockdown
# The marker creation must appear in Phase 1 (before Phase 2).
# Heuristic: the first occurrence of `requires.verify-changes.$TRACKING_ID`
# in skills/run-plan/SKILL.md must appear on a line BEFORE the first
# `## Phase 2` heading. If the anchor is missing entirely, fail.
LOCKDOWN_LINE=$(grep -n 'requires.verify-changes.\$TRACKING_ID' skills/run-plan/SKILL.md | head -1 | cut -d: -f1)
PHASE2_LINE=$(grep -n '^## Phase 2' skills/run-plan/SKILL.md | head -1 | cut -d: -f1)
if [ -n "$LOCKDOWN_LINE" ] && [ -n "$PHASE2_LINE" ] && [ "$LOCKDOWN_LINE" -lt "$PHASE2_LINE" ]; then
  check "early requires-lockdown (Phase 1)" 'true'
else
  check "early requires-lockdown (Phase 1)" 'false'
fi

# Phase H: scope-vs-plan judgment in /verify-changes
check "verify-changes: scope assessment in review prompt" \
  'grep -q "Scope vs plan" skills/verify-changes/SKILL.md'
check "verify-changes: scope assessment in report format" \
  'grep -q "Scope Assessment" skills/verify-changes/SKILL.md'
check "verify-changes: argument parser" \
  'grep -q "Parsing \$ARGUMENTS" skills/verify-changes/SKILL.md'
check "verify-changes: branch-scope marker stem" \
  'grep -q "verify-changes.final" skills/verify-changes/SKILL.md'
check "/run-plan halts on scope-violation flag" \
  'grep -qr "Scope Assessment" skills/run-plan/'

# Phase A: Phase 5b idempotency + final-verify gate
check "Phase 5b: final-verify gate present" \
  'grep -q "Final-verify gate" skills/run-plan/SKILL.md'
check "Phase 5b: idempotent early-exit present" \
  'grep -q "frontmatter is already.*status: complete" skills/run-plan/SKILL.md'

# post-run-invariants.sh still invoked by /run-plan
check "post-run-invariants.sh invoked by /run-plan" \
  'grep -q "post-run-invariants.sh" skills/run-plan/SKILL.md'

# Mirror sync (catches restores that forget to mirror)
for f in run-plan research-and-go fix-issues verify-changes research-and-plan; do
  if [ -d ".claude/skills/$f" ]; then
    check "mirror sync: $f" \
      "diff -q 'skills/$f/SKILL.md' '.claude/skills/$f/SKILL.md' >/dev/null"
  fi
done

# /cleanup-merged worktree handling — each anchor must be present in the
# skill source. A missing anchor means the worktree-aware branch-delete
# path silently regressed to plain `git branch -D` (which fails on
# worktree-held branches). If any check fails, the desc names the
# missing piece.
CM_SRC="skills/cleanup-merged/SKILL.md"
check "cleanup-merged: worktree detection (git worktree list --porcelain)" \
  "grep -q 'git worktree list --porcelain' '$CM_SRC'"
check "cleanup-merged: worktree removal action (git worktree remove)" \
  "grep -q 'git worktree remove' '$CM_SRC'"
check "cleanup-merged: orphan cleanup (git worktree prune)" \
  "grep -q 'git worktree prune' '$CM_SRC'"
check "cleanup-merged: dirty-skip warning phrase" \
  "grep -q 'uncommitted changes — inspect and remove manually' '$CM_SRC'"
check "cleanup-merged: MAIN_ROOT comparison guard" \
  "grep -q 'MAIN_ROOT' '$CM_SRC'"
# Mirror the source too, so drift is caught immediately.
if [ -d ".claude/skills/cleanup-merged" ]; then
  check "mirror sync: cleanup-merged" \
    "diff -q 'skills/cleanup-merged/SKILL.md' '.claude/skills/cleanup-merged/SKILL.md' >/dev/null"
fi

# Cross-skill invariant: no skill statically prescribes `isolation: "worktree"`.
# All worktree work must go through skills/create-worktree/scripts/create-worktree.sh
# (manual creation) per plans/EXECUTION_MODES.md. Word-boundary on "with"
# distinguishes prescriptions ("Dispatch ... with `isolation: "worktree"`") from
# negative warnings ("WITHOUT `isolation: "worktree"`"), so existing migrated skills
# don't false-positive.
check 'no skill prescribes isolation: worktree (use skills/create-worktree/scripts/create-worktree.sh)' \
  '! grep -rEn '"'"'\bwith[[:space:]]+`?isolation: *"worktree"'"'"' skills/ block-diagram/ 2>/dev/null'

# Emit format expected by tests/run-all.sh
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
