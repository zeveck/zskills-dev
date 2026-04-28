# /fix-issues — Failure Protocol

Execute these steps in order when a sprint crashes: kill the cron, restore the working tree, write the failure report, alert the user.
## Failure Protocol

If **anything goes wrong** during an `auto` or `every` sprint — cherry-pick
conflict, test failures after landing, agent crash, API errors that block
progress — execute these steps **in this exact order**:

### 1. Kill the cron FIRST

This is the most critical step. A broken sprint leaves state that a subsequent
cron run will stomp on — partially landed cherry-picks, active stashes,
conflicted working trees, dangling worktrees. The next run doesn't know about
any of this and will blindly stash, cherry-pick, and overwrite.

```
CronList → find the /fix-issues job ID → CronDelete
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

### 3. Write the failure to SPRINT_REPORT.md

Create the file if it doesn't exist (preflight failures happen before Phase 5
creates it). If it already exists, add the failure section immediately after
the `# Sprint Report` heading.

Add a `## Sprint Failed` section at the top of the report:

```markdown
## Sprint Failed — YYYY-MM-DD HH:MM

**Phase:** [which phase failed]
**Error:** [what went wrong]
**State:**
- Cherry-picks landed before failure: [list or "none"]
- Stash restored: yes/no
- Worktrees with changes: [list]
- Cron killed: yes (was job ID XXXX)

**To resume:** Review the state above, then either:
- Run `/fix-report` to finalize what succeeded
- Run `/fix-issues ... every` to restart the cron after resolving
```

### 4. Alert the user

Output a clear, prominent message:

```
⚠ SPRINT FAILED — cron stopped

Phase N failed: [one-line reason]
[specific error details]

What happened:
  - [N] fixes were in worktrees, [M] were cherry-picked to main before failure
  - Stash was [restored / not needed]
  - Cron job [ID] has been CANCELLED — no more auto-runs until you restart

Working tree is clean. See SPRINT_REPORT.md for full details.
To restart: /fix-issues N auto every SCHEDULE now
To cancel: /fix-issues stop
```

Do not bury the failure in normal output. The user needs to see immediately
that something broke, the cron is stopped, and what state was left behind.

### When to trigger

Invoke this protocol for ANY of these:
- `npm run test:all` fails after cherry-picks are landed (Phase 6 step 8)
  Note: cherry-pick CONFLICTS are handled by skip-and-continue (Phase 6
  step 4), NOT the Failure Protocol. The protocol is only for test failures
  and unrecoverable errors.
- The sprint globally produces 0 fixes (every agent failed or returned no
  commits) — note: this means ALL agents, not a single agent failing
- GitHub API errors that prevent issue fetching
- Preflight checks detect stale state (conflict markers, orphaned stash)
- Any unrecoverable error that stops the sprint from completing normally

Do NOT invoke for:
- Individual agent test failures in worktrees (those are reported in the sprint
  report as "Not Fixed" — the sprint continues with remaining fixes)
- Warnings or non-blocking issues
- Pre-existing test failures unrelated to the sprint

**For failed/abandoned worktrees:** when an agent returns no commits,
crashes, or times out, the ORCHESTRATOR (not the failed agent) writes a
failure marker on the worktree:
```bash
cat <<LANDED | bash "$CLAUDE_PROJECT_DIR/.claude/skills/commit/scripts/write-landed.sh" "<worktree>"
status: failed
date: $(TZ=America/New_York date -Iseconds)
source: fix-issues
issues: <issue numbers attempted>
reason: <agent returned no commits / agent crashed / tests failed>
LANDED
```
This ensures `/fix-report` can distinguish failed worktrees from active
ones. The issues stay open for the next sprint.

