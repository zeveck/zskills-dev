# /run-plan — Cherry-pick (Worktree) Landing Mode

Default worktree landing: pre-landing checklist, cherry-pick with dirty-tree LLM-assisted merge, landed marker, cleanup, tracker update.

### Pre-landing checklist (worktree mode only)

Before ANY cherry-pick to main, verify ALL of these. If any fails, STOP.

1. `ls reports/plan-{slug}.md` — report file exists (Phase 5 ran)
2. Report has a `## Phase` section for every completed phase
3. In `finish` mode: cross-phase `/verify-changes worktree` returned clean
4. If UI-touching phases: playwright-cli agent ran and produced screenshots
5. If UI-touching phases: report has `### User Verification` with `[ ]` items
6. `/verify-changes` Scope Assessment — grep the verify report for the
   scope-violation flag. If found, STOP.

   ```bash
   VERIFY_REPORT="reports/verify-worktree-$(basename "$WORKTREE_PATH").md"
   if [ -f "$VERIFY_REPORT" ] && grep -q "⚠️ Flag" "$VERIFY_REPORT"; then
     echo "HALTED: /verify-changes flagged scope violations in $VERIFY_REPORT." >&2
     echo "Review the Scope Assessment section, fix the diff, re-verify, and re-run." >&2
     # Invoke Failure Protocol — kill cron, restore working tree, write
     # failure to plan report, alert user. See "Failure Protocol" section
     # for exact steps.
     exit 1
   fi
   ```

   For delegate-mode verification (runs on main), the dispatched
   `/verify-changes` invocation may have used a different scope
   (`branch` or `worktree`). Record the report path in a variable when
   dispatching and reuse that variable here for the halt check.

- **Without `auto`:** Phase complete. Output:
  > Phase complete. Report written to `reports/plan-{slug}.md`.
  > Review the worktree and cherry-pick when ready, or use `/commit land`.

  All interactive landing and cleanup is the user's decision.
  `/run-plan` is DONE after writing the report.

- **With `auto` but User Verify items exist:** Check the report you just
  wrote in Phase 5 — if it has a `### User Verification` section with
  unchecked `[ ]` items, UI changes need human sign-off before landing.
  Output:
  > Phase complete. Report written to `reports/plan-{slug}.md`.
  > **User verification needed before landing** — review the report,
  > sign off on UI changes, then run `/commit land` from the worktree.
  >
  > Items needing sign-off: [list from the User Verification section]

  Do NOT auto-land. The worktree is ready; the user reviews and lands
  when satisfied. This is the landing gate for UI changes — `auto`
  automates everything EXCEPT human judgment.

  **In `finish` mode:** all phases share one worktree. Do NOT land
  individual phases as they complete — wait until ALL phases are done,
  then land everything together. Even non-UI phases should wait, because
  if a later phase has UI that the user rejects, the earlier phases may
  need to be revised too. The worktree accumulates all commits; landing
  is one atomic cherry-pick sequence at the end after all sign-offs.

- **With `auto` and NO User Verify items:** Auto-land verified phase
  commits to main. **Exception for `finish` mode:** do NOT auto-land
  per-phase — a later phase may have UI that needs sign-off. In finish
  mode, wait until all phases complete, then land everything together
  (same as the User Verify gate above). Only auto-land per-phase when
  running a single phase (no `finish` flag).

  Auto-land steps (single phase, or after all finish-mode phases complete):
  1. **Try cherry-picking WITHOUT stashing first.** Git allows cherry-picks
     on a dirty working tree as long as the cherry-picked files don't
     overlap with uncommitted changes. Other sessions may have uncommitted
     work in the tree — stashing captures THEIR changes too, and the pop
     can silently merge or lose them.

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
        uncommitted changes is still present AND the cherry-pick's changes
        landed correctly. If the merge dropped changes, restore them.
     8. After verification, drop the stash: `git stash drop`
     9. If you genuinely can't reconcile, STOP and report to the user.
  2. **Verify main is clean before cherry-picking:**
     ```bash
     npm run test:all
     ```
     If main's tests are already failing, **STOP.** Invoke the Failure
     Protocol — do not cherry-pick on top of broken code.
  3. **Cherry-pick sequentially** — one commit at a time. Try without stash
     first (step 1). Only stash if git refuses due to file overlap.
  4. **If a cherry-pick conflicts:** unlike `/fix-issues` (which can skip
     individual issues), a plan phase is one logical unit — partial landing
     is not useful. Abort all cherry-picks and invoke the **Failure Protocol**.
     ```bash
     git cherry-pick --abort
     ```
     Re-run the phase after the conflicting code is resolved on main.

  5. **Mark worktree as landed:**
     Write `.landed` marker (atomic: `.tmp` → `mv`):
     ```bash
     cat <<LANDED | bash scripts/write-landed.sh "<worktree-path>"
     status: landed
     date: $(TZ=America/New_York date -Iseconds)
     source: run-plan
     phase: <phase name>
     commits: <list of cherry-picked hashes>
     LANDED
     ```
  6. **Run `scripts/land-phase.sh`** — atomic post-landing cleanup:
     ```bash
     bash scripts/land-phase.sh "$WORKTREE_PATH"
     ```
     This script handles everything: verifies `.landed` marker, extracts
     logs to main's `.claude/logs/` (MUST succeed — exits 1 on failure),
     removes the worktree, and deletes the branch. Idempotent — safe to
     re-run if interrupted.
  7. **Restore stash** if one was created:
     ```bash
     git stash pop
     ```
  8. **Run tests** after all cherry-picks land:
     ```bash
     npm run test:all
     ```
     If tests fail, invoke the **Failure Protocol**.
  9. **Update tracker to Done** — now that landing succeeded, update the
     plan file's progress tracker from 🟡 In Progress to ✅ Done:
     ```bash
     git add <plan-file>
     git commit -m "chore: mark phase <name> done (landed)"
     ```
  10. **Update the plan report** (`reports/plan-{slug}.md`) — mark the
      phase section as landed. Regenerate `PLAN_REPORT.md` index.

### PR mode landing
