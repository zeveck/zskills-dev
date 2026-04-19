# /fix-issues — Cherry-pick Mode (Per-Issue)

Auto-land each verified fix by cherry-picking its worktree commits onto main with LLM-assisted merge for dirty-tree conflicts.
- **With `auto`:** Auto-land verified fixes to main:
  1. **Try cherry-picking WITHOUT stashing first.** Git allows cherry-picks
     on a dirty working tree as long as the cherry-picked files don't
     overlap with uncommitted changes. Other sessions may have uncommitted
     work in the tree — stashing captures THEIR changes too, and the pop
     can silently merge or lose them. Past failure: stash/pop cycle during
     cherry-pick wiped out another session's skill changes.

     **If git refuses** with "your local changes would be overwritten,"
     the cherry-pick touches files with uncommitted changes. Handle with
     LLM-assisted merge:
     1. Note which files overlap
     2. **Capture the pre-stash state** of each overlapping file:
        `git diff <file>` — save/remember this output. It's your evidence
        of what the uncommitted changes were (possibly from another session).
     3. `git stash -u -m "pre-cherry-pick stash"`
     4. `git cherry-pick <commit-hash>`
     5. `git stash apply` (NOT `pop` — keep the stash as a recovery path)
     6. If `stash apply` produces conflict markers (`<<<<<<<`), resolve
        them — read both sides and combine. This is expected for overlaps.
     7. **For every overlapping file**, READ the result and compare against
        the pre-stash diff from step 2. Verify every changed line from the
        uncommitted changes is still present AND the cherry-pick's fix
        landed correctly. If the merge dropped changes, restore them.
     8. After verification, drop the stash: `git stash drop`
     9. If you genuinely can't reconcile (same lines, conflicting
        purposes), STOP and report to the user.
  2. **Verify main is clean before cherry-picking:**
     ```bash
     npm run test:all
     ```
     If main's tests are already failing, **STOP.** Invoke the Failure
     Protocol — do not cherry-pick on top of broken code. Report: "main
     is broken before cherry-pick. Fix main first."
  3. **Cherry-pick sequentially** — one commit at a time, verify each succeeds
     before the next. Try without stash first (step 1). Only stash if git
     refuses due to file overlap.
  4. **If a cherry-pick conflicts:** abort and skip that worktree's
     commits. If the worktree has multiple commits (grouped interrelated
     issues), skip ALL of them — they likely depend on each other.
     ```bash
     git cherry-pick --abort
     ```
     Mark the issues as "Skipped: cherry-pick conflict" in
     `SPRINT_REPORT.md`. Continue cherry-picking from other worktrees.
     Do NOT invoke the Failure Protocol for skipped worktrees.

     The skipped issues stay open and will be picked up in the next sprint
     — by then the conflicting fix is on main, so the conflict resolves
     itself.

  5. **Extract logs and mark worktrees as landed** — for each worktree
     whose commits were successfully cherry-picked:
     a. Copy unique session logs to main:
        ```bash
        if [ -d "<worktree>/.claude/logs" ]; then
          for log in <worktree>/.claude/logs/*.md; do
            [ -f ".claude/logs/$(basename $log)" ] || cp "$log" .claude/logs/
          done
        fi
        ```
     b. Write `.landed` marker (atomic):
        ```bash
        cat <<LANDED | bash scripts/write-landed.sh "<worktree>"
        status: full
        date: $(TZ=America/New_York date -Iseconds)
        source: fix-issues
        commits:
          <list of cherry-picked commit hashes and messages>
        LANDED
        ```
     c. For tiers that were SKIPPED (conflict), write partial marker:
        ```bash
        cat <<LANDED | bash scripts/write-landed.sh "<worktree>"
        status: partial
        date: $(TZ=America/New_York date -Iseconds)
        source: fix-issues
        landed: <hashes that did land, if any>
        skipped: <hashes that conflicted>
        reason: cherry-pick conflict
        LANDED
        ```
  6. **Commit extracted logs:**
     ```bash
     git add .claude/logs/
     git commit -m "chore: session logs from fix-issues sprint"
     ```
  7. **Restore stash** if one was created:
     ```bash
     git stash pop
     ```
  8. **Run tests** after all cherry-picks land:
     ```bash
     npm run test:all
     ```
     If tests fail, invoke the **Failure Protocol** — do not leave broken
     code on main with the cron still running.
  9. **Update `SPRINT_REPORT.md`** — mark which fixes were landed (add a
     `Landed` column or update status).
  10. **Auto-remove fully landed worktrees** — for each worktree with
      `status: full` in `.landed`:
      ```bash
      # Logs already extracted in step 5a. Double-check for stragglers:
      if [ -d "<worktree>/.claude/logs" ]; then
        for log in <worktree>/.claude/logs/*.md; do
          [ -f ".claude/logs/$(basename "$log")" ] || cp "$log" .claude/logs/
        done
      fi

      # Check for real uncommitted work (not artifacts)
      DIRTY=$(git -C "<worktree>" diff --name-only HEAD)
      UNTRACKED=$(git -C "<worktree>" status --porcelain | \
        grep -v '\.landed\|\.worktreepurpose\|\.test-results\|\.playwright\|node_modules')

      if [ -z "$DIRTY" ] && [ -z "$UNTRACKED" ]; then
        rm -f "<worktree>/.landed" "<worktree>/.worktreepurpose"
        git worktree remove "<worktree>"
        git branch -d "<branch>" 2>/dev/null
      else
        echo "Worktree <name> not auto-removed: uncommitted work found"
      fi
      ```
      Skip removal for worktrees with `status: partial` — those have
      unapplied commits that need attention.

  11. Done. Closing GH issues and updating trackers are still `/fix-report`
      actions — even in auto mode.

