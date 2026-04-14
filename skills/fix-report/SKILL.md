---
name: fix-report
disable-model-invocation: true
description: >-
  Review ALL unreported sprint results: walk through manual verifications,
  land fixes to main, close GitHub issues, update trackers, and clean up
  worktrees. Covers the current SPRINT_REPORT.md AND any landed-but-unclosed
  issues from previous sprints.
---

# /fix-report — Sprint Report Review & Landing

Interactive companion to `/fix-issues`. Covers ALL unreported sprint results
— not just the latest SPRINT_REPORT.md. If sprints have been running on a
cron every 2 hours and the user hasn't checked in a day, `/fix-report`
should present everything from those 12 sprints.

This skill is always interactive — no `auto` flag. It's the human review
counterpart to `/fix-issues auto`.

**Every step ends with STOP AND WAIT.** Do not advance to the next step until
the user explicitly says to proceed. Present information, then stop. The user
drives the pace — not you.

## Step 1 — Present Summary

Read `SPRINT_REPORT.md` from the repo root. If it doesn't exist, tell the
user to run `/fix-issues` first.

The report contains multiple `## Sprint` sections — one per sprint run.
Find ALL sections marked `[UNFINALIZED]`. These are sprints whose results
haven't been reviewed yet. If sprints have been running every 2h on a cron
and the user hasn't checked in a day, there may be 12 unfinalized sections.

Present the COMBINED picture across all unfinalized sprints:

```
Sprint Report — N unfinalized sprints

  Sprint 2026-03-16 09:00: Fixed #100, #101
  Sprint 2026-03-16 11:00: Fixed #102. Skipped #103 (conflict)
  Sprint 2026-03-16 13:00: Fixed #104, skipped #105 (too vague)

  Fixed: 4 issues (3 already landed)
  Needs manual verification: 1
  Skipped: 2 issues
    - Too vague (no repro/spec): #105
    - Cherry-pick conflict: #103
  Not fixed (agent failed): 0
```

**Always break out skip reasons.** The user needs to know which skipped
issues need clarification (too vague → user adds repro steps), which need
a different approach (too complex → `/run-plan`), and which will self-heal
(cherry-pick conflict → next sprint picks them up). Lumping all skips
together as "not fixed" hides actionable information.

Then list each fix across all sprints with its status.

### If the report contains `## Sprint Failed`

The previous sprint failed partway through. Present the failure prominently:

```
⚠ Sprint Report — YYYY-MM-DD HH:MM — FAILED at Phase N

  Error: [reason from the failure section]
  Cherry-picks landed before failure: [list or "none"]
  Cron status: killed (was job ID XXXX)

  Fixes completed before failure:
    ✓ #123 — Solver crash (landed on main)
    ✓ #456 — Button misaligned (in worktree, NOT landed)

  What would you like to do?
    1. Finalize the fixes that succeeded (land + close)
    2. Revert the partially landed cherry-picks
    3. Abort — leave everything as-is
```

**STOP.** The user must choose how to handle the partial failure before
anything else happens. Do not assume option 1.

If the user chooses to finalize partial successes, proceed through the
remaining steps (2→3→4→5→6→7) as normal, skipping steps that don't apply
(e.g., skip Step 2 if no fixes need manual verification, skip Step 4 if
all successful fixes were already landed).

### Normal case (no failure section)

Present a compact summary:

```
Sprint Report — YYYY-MM-DD HH:MM
  Fixed: N issues (M already landed on main)
  Needs manual verification: N issues
  Skipped: N issues
    - Too vague: #NNN, #NNN (need repro steps or clearer spec)
    - Too complex: #NNN (need /run-plan)
    - Cherry-pick conflict: #NNN (will retry next sprint)
  Not fixed (agent attempted but failed): N issues
```

Omit skip categories with zero items. Then list each fix with its status
(landed/not landed, verified/needs check).

### PR-aware reporting

Scan every worktree's `.landed` marker for `method: pr`. These come from
`/fix-issues <N> auto pr` runs — each fixed issue has its own
`fix/issue-NNN` branch and a dedicated PR. The marker fields include:

- `issue: NNN` — the GitHub issue the PR resolves
- `pr: <URL>` — the PR URL
- `status: landed | pr-ready | pr-ci-failing | pr-failed | conflict`
- `ci: pass | fail | pending | none | skipped`
- `pr_state: OPEN | MERGED`

Present PR-linked fixes with their URLs alongside the issue numbers:

```
PR-landed fixes (sprint YYYY-MM-DD HH:MM):
  #123 — Solver crash — PR merged (landed): https://github.com/org/repo/pull/456
  #456 — Button offset — PR open, CI passing (pr-ready): https://github.com/org/repo/pull/457
  #789 — Parser error — PR open, CI FAILING (pr-ci-failing): https://github.com/org/repo/pull/458
  #321 — Config bug — rebase conflict — see worktree /tmp/proj-fix-issue-321
```

**When listing PR URLs**, use the `status` field to categorize:
- `landed` — PR merged, auto-closed the issue via `Fixes #NNN`
- `pr-ready` — PR open, CI passing, awaiting review/merge
- `pr-ci-failing` — PR open but CI failed after max fix attempts
- `pr-failed` — push succeeded but PR creation failed; show branch name
- `conflict` — rebase conflict; worktree left clean for the user to resume

Include PR URLs in the final `FIX_REPORT.md` domain sections so the user
can click through to review each fix.

**STOP.** Wait for the user. They may want to discuss, ask questions about
specific fixes, review diffs, or reject fixes before proceeding. Do not move
to Step 2 until the user says to continue.

## Step 2 — User Verification

The sprint report has two verification columns:

- **Agent Verify:** Did the agent test it? (PASS/SKIPPED — enforced by
  pre-commit hook, should always be PASS for landed code)
- **User Verify:** Does the user need to see this? (NEEDED/N/A —
  mechanically classified from file paths)

Skip this step if no items have `User Verify: NEEDED`.

For each issue with `User Verify: NEEDED`:

1. Show the issue number, title, which UI files changed, and the agent's
   verification screenshots (if any)
2. **Provide concrete verification instructions:**
   - What to look at (specific UI element, panel, interaction)
   - Steps to reproduce (open app → navigate → interact → observe)
   - What "correct" looks like (expected appearance or behavior)
   - URL: `http://localhost:$(bash scripts/port.sh)/`
   - The user may be verifying hours later — "check the UI" is useless.
     Be specific: "Open the toolstrip, click the lightning icon, verify
     the Physical Variables panel opens with a table showing V, I, P
     columns."
3. Run the verification via `/manual-testing` or guide the user through
   manual steps — show the result in the browser
4. Ask the user: **Pass or Fail?**
5. Update `SPRINT_REPORT.md` — change `NEEDED` to `PASS (user verified)`
   or `FAIL (reason)`

If an issue fails user verification, move it to a "Failed Verification"
section and note what went wrong. That fix will NOT be finalized — it
stays open for the next sprint.

Also check: any items with `Agent Verify: SKIPPED`? These should not have
been committed (the hook blocks this), but if they slipped through, flag
them for investigation.

**STOP** after all verifications are resolved. Present the updated picture:
which fixes passed, which failed. Wait for the user before proceeding.

## Step 3 — Sprint Approval Gate

This is the "clear the sprint" moment. Present the **complete finalization
plan** — everything that will happen if approved:

```
Ready to finalize:
  ✓ #123 — Solver crash (landed in abc1234)
      → Close GH issue, update issue trackers
  ✓ #456 — Button misaligned (landed in def5678)
      → Close GH issue, update issue trackers

Not finalizing:
  ✗ #789 — Parser error (failed verification)
  ⊘ #321 — Not fixed

Approve sprint finalization?
```

**STOP.** Nothing happens until the user explicitly approves. The user may:
- Approve all
- Approve selectively ("finalize #123 but skip #456")
- Ask to review diffs first
- Reject the sprint entirely

Do NOT update any plan files, close any issues, or clean up any worktrees
until this gate is passed.

## Step 4 — Land Fixes (if needed)

Skip this step if all fixes were already auto-landed by `/fix-issues auto`.

**PR mode fixes are landed via merge, not cherry-pick.** If a worktree's
`.landed` marker has `method: pr`:
- `status: landed` — the PR was auto-merged; the fix is already on main
  via the merge commit. No cherry-pick needed.
- `status: pr-ready` — the PR is open; direct the user to review and
  merge it on GitHub. Do NOT cherry-pick — that would duplicate the
  commits when the PR merges.
- `status: pr-ci-failing` / `pr-failed` / `conflict` — show the user
  the PR URL (if any) and the worktree path; let them decide how to
  resume. Do NOT auto-cherry-pick.

For cherry-pick mode fixes that haven't been landed yet, continue with
the steps below.

For each approved fix that has NOT been landed:

1. Show the issue number, title, worktree, and commit hash
2. Show the diff: `git diff <commit>^..<commit> --stat` (summary) and offer
   full diff if requested
3. Ask: **"Land this fix? (cherry-pick to main)"**
4. If approved:
   a. Protect uncommitted work:
      ```bash
      if [ -n "$(git status --porcelain)" ]; then
        git stash -u -m "pre-cherry-pick stash"
      fi
      ```
   b. Cherry-pick:
      ```bash
      git cherry-pick <commit-hash>
      ```
   c. If conflict: **STOP.** Report the conflict files and let the user decide
      how to resolve. Do not force-resolve or skip.
   d. Restore stash if one was created:
      ```bash
      git stash pop
      ```
   e. Update `SPRINT_REPORT.md` — mark the fix as landed
5. If declined: skip and move to the next fix

Process fixes **one at a time** — sequential cherry-picks avoid conflicts.

## Step 5 — Finalize (Close Issues + Update Trackers)

For each approved issue, **in lockstep**: close the GitHub issue AND update
the plan file entry together. These are one logical action — "this fix is
done" — not two separate steps.

Present the batch and get confirmation:

```
Closing and updating trackers for N issues:
  #123 — close GH + mark done in issue trackers
  #456 — close GH + mark done in issue trackers

Proceed?
```

**STOP.** Wait for user approval before executing. Do not proceed to close
issues or update trackers until the user says to.

Then for each approved issue:

1. Close the GitHub issue:
   ```bash
   gh issue close <number> --comment "Fixed in <commit-hash>"
   ```

2. Update ALL relevant issue tracker files — scan `plans/*ISSUES*.md`
   for the issue number and mark it done (`[x]`, ~~FIXED~~, RESOLVED,
   etc. — match the convention used in each file).

   Only update files that actually reference the issue number.

3. Update `SPRINT_REPORT.md` — mark as finalized

## Step 6 — Worktree Cleanup

Check all worktrees for `.landed` markers:

```bash
for wt in $(git worktree list | awk '{print $1}' | tail -n +2); do
  if [ -f "$wt/.landed" ] && grep -q "^status: full" "$wt/.landed"; then
    echo "SAFE: $wt ($(head -1 $wt/.landed))"
  elif [ -f "$wt/.landed" ]; then
    echo "PARTIAL: $wt — has unlanded work"
  else
    echo "ACTIVE: $wt — no .landed marker"
  fi
done
```

Present the results:
```
Worktrees:
  wt-123 — SAFE (status: full, landed 2026-03-16) ✓
  wt-456 — SAFE (status: full, landed 2026-03-16) ✓
  wt-789 — PARTIAL — skipped commits, needs review ⚠
  physics module-phase4 — ACTIVE — no .landed marker (long-running dev) ⚠

Remove SAFE worktrees? (wt-123, wt-456)
```

**Wait for user approval** before removing anything.

**Only remove worktrees with `status: full` in `.landed`.** Never remove
PARTIAL or ACTIVE worktrees. After removing, also clean up the branch:
```bash
git worktree remove <path>
git branch -d <branch-name>
```

## Step 7 — Write FIX_REPORT.md

Write `FIX_REPORT.md` to the repo root. Viewable in the browser:
`http://localhost:$(bash scripts/port.sh)/viewer/?file=FIX_REPORT.md`

### Report structure

**Header:**
```markdown
# Fix Report — YYYY-MM-DD
{Count} issues landed. **Check the User column and sign off.**
Legend: ✅ verified, ⚠️ partial, ❌ failed, ➖ not applicable, [ ] not yet checked
```

**Domain-grouped sections** — group by concern (UI/UX, Codegen,
Simulation, state machine module, etc.), NOT by workflow state. Use a single-checkbox
checklist (no summary table + detail card dual-checkbox pattern):

```markdown
## UI / UX Fixes

- [ ] **#358** — Block Rotation
  1. Right-click a block and select Rotate
  2. Ports should move to the correct sides
  3. Block label should stay horizontal
  ![rotation](.playwright/output/358-rotation-90deg.png)

- [ ] **#401** — Tooltip positioning
  1. Hover near canvas edge
  2. Verify tooltip doesn't clip off-screen
```

**One checkbox per verifiable item.** Include verification steps and
screenshots directly under each checkbox. One item per distinct thing —
not "3 fixes in category" but one per fix.

**Outcome sections** (after all domain sections, include only non-empty):
- **Not Fixed** — issues referenced in commits but not actually fixed
- **Not Attempted** — sub-grouped by reason (Too Complex Architectural,
  Too Complex Codegen, Feature Enhancements, Test Gap Not Yet Filled)
  with "Why Skipped" column
- **Skipped Verification** — per-item reason (macOS-only, transient UI,
  synthetic event limitations)
- **Pre-existing Bugs Discovered** — bugs found during verification,
  not related to sprint fixes (Bug, Found During, Location, Severity)
- **Test Suite Status** — `Command: npm run test:all` + per-suite counts

**Append, don't overwrite** — new items go at the top of each domain
section. Already-verified items stay as `✅`. Returning from a fix
tangent shows unchecked `[ ]` items first.

## Step 8 — Final Status

Mark all processed sprint sections as `[FINALIZED]` in `SPRINT_REPORT.md`:
- Change `[UNFINALIZED]` → `[FINALIZED YYYY-MM-DD]` for each section
  that was reviewed and approved

Output a final summary:

```
Fix-report complete:
  Sprints reviewed: N
  Issues finalized: N (closed + trackers updated)
  Skipped by user: N
  Failed verification: N
  Worktrees removed: N
  Report: FIX_REPORT.md (view at /viewer/?file=FIX_REPORT.md)
```

## Key Rules

- **STOP AND WAIT between every step.** This is the most important rule. Do
  not advance to the next step until the user says to proceed. Present
  information and stop. The user drives the pace.
- **Sprint approval gate is mandatory** — Step 3 must happen before any plan
  files are updated or GH issues are closed. Do not skip this gate.
- **Close + tracker update are one action** — never update plan files without
  also closing the issue, and vice versa. They happen together in Step 5.
- **Do not touch plan files before Step 5** — plan file updates are part of
  finalization, not part of review. Updating trackers before the user approves
  creates work that may need to be undone.
- **Always interactive** — every landing, closing, and cleanup action requires
  explicit user approval.
- **One cherry-pick at a time** — sequential to avoid conflicts.
- **Stop on conflicts** — report and let the user decide.
- **Protect untracked files** — before stash/cherry-pick, inventory untracked
  files (`git status -s | grep '^??'`). Use `git stash -u`.
- **Never remove worktrees with unapplied changes** — the user may want to
  review them later.
- **Update the report as you go** — `SPRINT_REPORT.md` should reflect the
  current state at all times.
