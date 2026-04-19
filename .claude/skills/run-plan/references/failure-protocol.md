# /run-plan — Failure Protocol & Failed-Run Template

Crash handling, cron cleanup, working-tree restoration, and the Run Failed report template for auto and every runs.
## Failure Protocol

If **anything goes wrong** during an `auto` or `every` run — cherry-pick
conflict, test failures after landing, verification fails after 2 fix cycles,
all agents fail — execute these steps **in this exact order**:

### 1. Kill the cron FIRST

This is the most critical step. A broken run leaves state that a subsequent
cron run will stomp on.

```
CronList → find the /run-plan job ID → CronDelete
```

Do this BEFORE any cleanup or reporting. Even if you're about to fix the
problem, kill the cron. The user can restart it after reviewing.

### 2. Restore the working tree

If a cherry-pick is in a conflicted state:
```bash
git cherry-pick --abort
```

If a stash was created during Phase 6 auto-land:
```bash
git stash pop
```
If `git stash pop` conflicts, do **NOT** attempt to clean up. Do NOT
`git stash drop` (destroys untracked files). Do NOT `git checkout -- .`
(also destroys untracked files extracted during the failed pop). The
conflicted state preserves all data — leave it as-is and report to the user:
> Stash pop conflicts. Stash preserved (contains untracked files).
> Run `git stash show` to inspect, then `git stash pop` manually.

**Never destroy work to clean up.** It's always better to STOP with a messy
state than to lose files trying to clean up.

### 3. Write the failure to the plan report

Add a `## Run Failed` section at the top of the report:

```markdown
## Run Failed — YYYY-MM-DD HH:MM

**Plan:** plans/FEATURE_PLAN.md
**Phase:** 4b — Translational Mechanical Domain
**Failed at:** Phase N — [description]
**Error:** [what went wrong]
**State:**
- Cherry-picks landed before failure: [list or "none"]
- Stash restored: yes/no
- Worktree with changes: [path]
- Cron killed: yes (was job ID XXXX)

**To resume:** Review the state above, then either:
- Fix the issue in the worktree and re-run `/run-plan <plan-file> <phase>`
- Run `/run-plan <plan-file> auto every <interval>` to restart the cron
```

### 4. Alert the user

Output a clear, prominent message:

```
⚠ RUN-PLAN FAILED — cron stopped

Phase [N] failed: [one-line reason]
[specific error details]

What happened:
  - Implementation was in worktree [path]
  - [M] commits were cherry-picked to main before failure (or "none")
  - Stash was [restored / not needed]
  - Cron job [ID] has been CANCELLED

Working tree is clean. See reports/plan-{slug}.md for full details.
To restart: /run-plan <plan-file> auto every INTERVAL
To cancel: /run-plan stop
```

### When to trigger

Invoke this protocol for ANY of these:
- Cherry-pick conflict during Phase 6
- `npm run test:all` fails after cherry-picks are landed
- Verification fails after 2 fix+verify cycles (auto mode)
- Preflight checks detect stale state (conflict markers, orphaned stash)
- Any unrecoverable error that stops the run from completing normally

Do NOT invoke for:
- Individual test failures in the worktree during implementation (the
  implementer fixes those as part of their workflow)
- Warnings or non-blocking issues

