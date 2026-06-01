---
title: /fix-issues Sprint Report
status: complete
---

# /fix-issues sprint — sprint-20260601-035736-dq30m6

**Mode:** N=2, dashboard, auto, every 30m
**Picks:** #883 only (only Ready∩Open candidate not claimed by parallel session)

## Landed (1)

### #883 — In-flight guard for /run-plan + /do (cron re-entry on same work)
- **PR:** https://github.com/zeveck/zskills-dev/pull/911 — merged after a HARD recovery (see "Scary recovery" below)
- **Files (17, +726/-50):** `check-inflight-batch.sh` got new optional `--pipeline-id` filter (backward-compatible) for per-work-item gating; integrated at `/run-plan` SKILL.md, `/run-plan/modes/execute-phase.md`, `/do/SKILL.md`, `/do/modes/{pr,worktree,direct}.md`; mirrors; new 35-test suite `tests/test-inflight-reentry-guard.sh`.
- **Skip-keys (chosen carefully per skill mode):**
  - `/run-plan` → `$PIPELINE_ID = run-plan.$TRACKING_ID` (plan-file basename slug). Same plan = same key.
  - `/do` PR → `do.${TASK_SLUG}` **before** Step A2.5 collision suffix.
  - `/do` worktree → `do.${TASK_SLUG}`.
  - `/do` direct → `do.${ISSUE_NUMS[0]}` (issue-anchored only).
- **/research-and-go:** correctly NOT guarded — one-shot kickoff; downstream protected by /run-plan's new guard.
- **Tests:** 6759/6759 suite-wide; new suite 35/35; existing batch-guard 32/32 back-compat.

## Scary recovery — `commit --amend` during paused rebase

PR #911 entered a broken state during rebase conflict resolution. Conflict was on `skills/do/SKILL.md`'s version line (PR #910 had also bumped it). I edited the conflict, ran `git add`, then ran `frontmatter-set.sh` + `mirror-skill.sh do` + `git add` + `git commit --amend --no-edit` **before** `git rebase --continue`. The amend operated on HEAD's position during the pause — which was the LAST APPLIED COMMIT, i.e. the UPSTREAM `b720f60` (PR #910 squash). The amend silently overwrote #910's commit content with my partial diff (just the version bump). `git rebase --continue` then had nothing to apply because my commit had been "consumed" into the upstream slot. I force-pushed the broken state.

**Recovery:** `git reset --keep 5057e2a` (original #883 commit from reflog) → redo rebase carefully (resolve conflict, `git add`, `git rebase --continue` FIRST, only THEN amend with re-bumped version) → force-push correct state. PR #911 merged cleanly on the second attempt.

**Memory anchor saved:** `feedback_amend_during_rebase_pause_danger` — never run `commit --amend` during a paused rebase; resolve + continue FIRST, amend after.

## Sprint metadata

- Sprint pipeline ID: fix-issues.sprint-20260601-035736-dq30m6
- Sprint worktree: /tmp/zskills-fix-issues-sprint-20260601-035736-dq30m6
- Issue claim for #883 released cleanly post-merge.
- Cron: `*/30 * * * *` — next fire ~30 min.
