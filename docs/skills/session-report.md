# /session-report

> Audit what THIS session said it would do vs. what's actually shipped. Verifies session-mentioned items against ground truth (git, PRs, plans, worktrees), not conversation memory.

## Usage

```
/session-report
```

No arguments.

## Workflow

### Step 1 -- Enumerate session intent

List every concrete deliverable discussed in the current conversation:
- Features to add, bugs to fix, plans to draft
- PRs opened, fixed, or merged
- Skills, scripts, or hooks to write
- Queued actions

### Step 2 -- Verify against ground truth

For each intent item, verify against the filesystem and git:
- Does the commit exist?
- Is the PR merged?
- Is the file present?
- Did the plan land?

### Step 3 -- Report

Present a structured comparison of intent vs. actual state.

## Examples

```
/session-report
```

## Common Patterns

- **End-of-session audit:** `/session-report` -- check if everything discussed was actually shipped
- **After long sessions:** especially useful after sessions with context compaction, where items may have been lost

## Tips & Gotchas

- Scope is limited to THIS conversation -- not a repo-wide audit
- Verifies against filesystem and git, not conversation memory (memory is unreliable due to compaction)
- Items completed in a different session still show as "done" (verified against ground truth)
- Items never committed, reverted, or stuck in worktrees show as "not shipped"
