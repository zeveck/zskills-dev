---
title: Canary — /fix-issues sync bootstrap + main_protected end-to-end
created: 2026-05-12
status: draft
parent: FIX_ISSUES_SYNC_HARDENING.md
---

# Canary: /fix-issues Sync — Bootstrap + main_protected End-to-End

## Overview

This is a **draft follow-up plan stub** spun off from `docs/plans/FIX_ISSUES_SYNC_HARDENING.md` (which closed #231 and #233). The parent plan ships structural ACs and a smoke test (`tests/test-fix-issues-sync-smoke.sh`) but cannot autonomously exercise `/fix-issues sync` end-to-end because sync is human-review-only at step 3 (the user approves which issues to close).

This canary plan, when drafted and run, exercises the full sync flow against a scratch repo with `main_protected: true` and a synthetic open issue, and verifies the PR is opened correctly. It is **not** a hard AC of the parent plan; it lands later, on its own schedule.

## Canary Recipe (verbatim from parent plan)

```bash
# In a freshly-created scratch repo:
mkdir -p /tmp/fix-issues-sync-canary && cd /tmp/fix-issues-sync-canary
git init -q && git commit --allow-empty -m "init" -q
gh repo create --private --source=. --remote=origin --push
cat > .claude/zskills-config.json <<JSON
{"execution":{"main_protected":true}}
JSON
mkdir -p .zskills/issues
gh issue create --title "canary: bootstrap+protected sync" --body "synthetic"
# Now run /fix-issues sync interactively and verify:
#  1. Bootstrap creates .zskills/issues/ISSUES_PLAN.md with frontmatter at col 0
#  2. Net-diff detector fires, routes to Protected path
#  3. Worktree created at /tmp/fix-issues-sync-canary-sync-YYYYMMDD-HHMMSS
#  4. PR opened with `sync: trackers <date>` title, no `Closes #N` in body
#  5. /land-pr canonical monitor flow runs; CI_STATUS is observed
#  6. After human-approves the merge on GitHub, gh issue close fires
```

## Status

`status: draft` — this plan is a stub. To turn it into an executable plan:

1. Run `/draft-plan docs/plans/FIX_ISSUES_SYNC_CANARY.md` to flesh out phases, acceptance criteria, and verification.
2. Then `/run-plan docs/plans/FIX_ISSUES_SYNC_CANARY.md` to execute (interactively — sync requires step-3 approval).

## Why a Stub Instead of an Inline AC

`/run-plan auto` cannot autonomously execute `/fix-issues sync` against a scratch repo — sync is interactive and requires the user's step-3 approval response. Making canary success a hard AC of the parent plan would deadlock the auto-mode pipeline. Spinning this out as a follow-up plan keeps the parent landable while preserving the end-to-end verification as a tracked next step.

## Relationship to Parent Plan

- Parent plan: `docs/plans/FIX_ISSUES_SYNC_HARDENING.md` (closes #231, #233).
- Parent ACs covered: structural (smoke test, grep-anchored).
- This canary covers: end-to-end runtime behavior (bootstrap → routing → worktree → /land-pr → CI → merge → gh issue close).
