# /run-plan — Delegate Landing Mode

Delegate mode verified the sub-skill already landed to main: verify commits, check report, update tracker, skip cherry-pick.

If this phase used delegate execution mode, the delegated skill already
landed its own work to main. Phase 6 in delegate mode:

1. **Verify commits on main** — check `git log --oneline -10` for the
   delegate's commits. If missing, the delegate failed to land — invoke
   Failure Protocol.
2. Verify the report exists (Phase 5 ran)
3. Update the progress tracker (mark phase done)
4. Skip cherry-picking — work is already on main
5. Done. Proceed to next phase or exit.

### Worktree mode landing
