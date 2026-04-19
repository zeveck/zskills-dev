# /run-plan — Direct Landing Mode

No-op landing: direct mode committed to main during implementation, so only the progress tracker needs updating.

If `LANDING_MODE` is `direct`, Phase 6 is a **no-op**. Work was committed
directly on main — there is nothing to cherry-pick, no worktree to land,
and no `.landed` marker to write. Update the progress tracker to Done and
proceed to the next phase or exit.

### Delegate mode landing
