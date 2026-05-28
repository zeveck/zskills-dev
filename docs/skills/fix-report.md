# /fix-report

> Review ALL unreported sprint results: walk through manual verifications, land fixes to main, close GitHub issues, update trackers, clean up worktrees.

## Usage

```
/fix-report
```

No arguments -- the skill is always interactive and guides you through each step.

## Workflow

1. **Read sprint report** -- scan all entries from recent sprints
2. **Present findings** -- show each fix with its status, verification state, and worktree
3. **Manual verification** -- for each fix, verify it works correctly
4. **Land fixes** -- cherry-pick verified fixes to main
5. **Close issues** -- close GitHub issues for landed fixes
6. **Update trackers** -- mark issues as resolved in tracker files
7. **Clean up** -- remove worktrees for landed fixes

## Examples

```
/fix-report
```

## Common Patterns

- **After autonomous sprints:** if `/fix-issues auto` has been running on a cron, `/fix-report` presents everything from those runs
- **Interactive companion:** always interactive -- the human review counterpart to `/fix-issues auto`

## Tips & Gotchas

- Always interactive -- no `auto` flag. Every step ends with STOP AND WAIT for user approval
- Covers ALL unreported sprint results, not just the latest report
- If sprints have been running on a cron for hours, this skill presents everything accumulated
- Works in a pre-created worktree under `execution.main_protected: true`
- The final landing of changes is the user's call (typically `/commit pr` from the worktree)
