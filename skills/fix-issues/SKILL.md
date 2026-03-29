---
name: fix-issues
disable-model-invocation: true
argument-hint: "N [focus] [auto] [every SCHEDULE] [now] | sync | plan [auto] | stop | next"
description: >-
  Orchestrate a batch bug-fixing sprint. Supports scheduling with
  every/now/next/stop. Use sync to update trackers and verify/close
  already-fixed issues. Use plan to draft plans for skipped issues.
  Usage: /fix-issues N [focus] [auto] [every SCHEDULE] [now] | sync | plan [auto] | stop | next.
---

# /fix-issues N [focus] [auto] [every SCHEDULE] [now] | sync | plan [auto] | stop | next — Batch Bug-Fixing Sprint

Orchestrates large-scale bug fixing. Syncs trackers, prioritizes issues,
dispatches agent teams in worktrees, verifies fixes, writes a persistent
report, and optionally auto-lands to main. Can self-schedule for recurring runs.

**Ultrathink throughout.** Use careful, thorough reasoning at every step.

## Arguments

```
/fix-issues N [focus] [auto] [every SCHEDULE] [now]
/fix-issues sync | plan [auto] | stop | next
```

- **N** (required for sprints) — number of issues to fix (e.g., `30`)
- **focus** (optional) — prioritize a specific domain. The agent scans
  `plans/*_ISSUES.md` and `plans/ISSUES_PLAN.md` to discover tracker files
  and their domains. Common focus values: `new`, `correctness`, `codegen`,
  `ui`, `tests` — but any domain found in your tracker files works.
  Omit for default priority order.
- **auto** (optional) — bypass confirmation gates for autonomous operation.
  Behavior depends on context:
  - **Sprints:** skip Phase 2 issue list approval, auto-land to main via
    cherry-pick. Does NOT close GH issues or remove worktrees — those are
    `/fix-report` actions.
  - **plan auto:** draft plans for all found issues without selection
    (see Plan section).
  - **Not applicable to sync.** `sync` is always interactive — closing
    issues on GitHub requires human approval.
- **every SCHEDULE** (optional) — self-schedule recurring runs via cron:
  - Accepts intervals: `4h`, `2h`, `30m`, `12h`
  - Accepts time-of-day: `day at 9am`, `day at 14:00`, `weekday at 9am`
  - Without `now`: schedules only, does NOT run immediately
  - With `now`: schedules AND runs immediately
  - Implies `auto` — scheduling only makes sense for autonomous runs
  - Each run re-registers the cron (self-perpetuating)
  - Cron is session-scoped — dies when the session dies
- **now** (optional) — run immediately. When combined with `every`, runs
  immediately AND schedules. Without `every`, `now` is the default behavior
  (bare invocation always runs immediately).
- **sync** — update all issue tracker files from GitHub, research new
  issues, AND verify/close issues that appear already fixed. Dispatches
  research agents that also check if open issues are already resolved in
  the codebase. Always interactive — presents findings and asks before
  closing. See Sync section for the full flow.
- **plan** — draft plans for issues previously skipped as "too complex."
  Scans `SPRINT_REPORT.md` for skipped items, dispatches `/draft-plan`
  for each. No fixing — just creates plans for `/run-plan` to execute later.
- **stop** — cancel any existing `/fix-issues` cron and exit. **Takes
  precedence over all other arguments.**
- **next** — check when the next scheduled run will fire. **Takes precedence
  over all other arguments except `stop`.**

**Detection:** scan `$ARGUMENTS` for:
- `stop` (case-insensitive) — cancel cron and exit (highest precedence)
- `next` (case-insensitive) — check schedule and exit
- `sync` (case-insensitive) — sync trackers, verify/close fixed issues, and exit
- `plan` (case-insensitive) — draft plans for skipped issues and exit
- `now` (case-insensitive) — run immediately
- `auto` (case-insensitive) — autonomous mode (behavior varies by context)
- `every` followed by a schedule expression — scheduling mode

Examples:
- `/fix-issues 30` — interactive, 30 issues, run now
- `/fix-issues 10 correctness` — interactive, solver focus, run now
- `/fix-issues 5 auto` — autonomous, one-time, run now
- `/fix-issues 5 auto every 4h` — schedule every 4h (first run in ~4h)
- `/fix-issues 5 auto every 4h now` — schedule every 4h + run immediately
- `/fix-issues 10 auto every day at 9am` — schedule daily at 9am
- `/fix-issues 10 auto every weekday at 9am now` — schedule + run now
- `/fix-issues sync` — update trackers + verify/close fixed issues (always interactive)
- `/fix-issues plan` — draft plans for issues skipped as "too complex"
- `/fix-issues plan auto` — same, but plan all without selection
- `/fix-issues stop` — cancel the recurring cron
- `/fix-issues next` — check when the next sprint will run

## Now (standalone — no N provided)

If `$ARGUMENTS` is just `now` (no N, no focus, no every — just the word
`now` by itself):

1. Use `CronList` to list all cron jobs
2. Find any whose prompt starts with `Run /fix-issues`
3. If found: extract the cron's prompt to get N, focus, auto, and schedule.
   **Run the sprint immediately** using those parameters — proceed to
   Phase 1 with the cron's N, focus, and auto settings. Do NOT ask for
   confirmation — `now` IS the confirmation. The cron itself stays active.
4. If none found: report `No active /fix-issues cron to trigger. Use
   /fix-issues N to run manually.` and **exit.**

## Next (if `next` is present)

If `$ARGUMENTS` contains `next` (case-insensitive):

1. Use `CronList` to list all cron jobs
2. Find any whose prompt starts with `Run /fix-issues`
3. Report:
   - If found: parse the cron expression and compute the next fire time.
     Use `date +%Z` for the timezone. Show both relative and absolute:
     > Next fix-issues sprint in ~2h 15m (~8:30 PM ET, cron XXXX).
     > Prompt: Run /fix-issues 5 auto every 4h
   - If none found: `No active /fix-issues cron in this session.`
4. **Exit.** Do not proceed to any phase.

## Stop (if `stop` is present)

If `$ARGUMENTS` contains `stop` (case-insensitive):

1. Use `CronList` to list all cron jobs
2. Delete ALL whose prompt starts with `Run /fix-issues` using `CronDelete`
3. Report what was cancelled:
   - If one cron found: `Fix-issues cron stopped (was job ID XXXX, every INTERVAL).`
   - If multiple found: `Stopped N fix-issues crons (IDs: XXXX, YYYY).`
   - If none found: `No active /fix-issues cron found.`
4. **Exit.** Do not proceed to any phase. The `stop` command does nothing else.

## Sync (if `sync` is present)

Update all issue trackers from GitHub, research new issues, and verify/close
issues that appear already fixed. This is the single command for issue
hygiene — it both syncs state AND cleans up resolved issues in one pass.

**Always interactive.** Closing issues on GitHub requires human approval —
there is no `auto` mode for sync. The agent presents verified-fixed
candidates and waits for the user to select which to close.

### Step 1 — Fetch & update trackers

1. **Run Phase 1a** (Preflight & Sync) — fetch all open issues, run sync
   script, update all tracker files.

### Step 2 — Research & verify

Dispatch research agents for every open issue that lacks a research blurb
in its tracker file. Each agent does:

1. Read the full issue body and comments from GitHub
2. Grep the codebase for related files and code
3. Write a concise research blurb (what's wrong, where, suggested approach)
4. Add the blurb to the appropriate tracker file

**Additionally**, each agent checks whether the issue appears to already be
fixed in the codebase. This is the same pass — not a separate step. While
researching an issue, the agent naturally reads the relevant code and can
tell if the reported problem still exists. For each issue, the agent
produces a **verdict:**

- **FIXED** — code fix is present AND tests pass. Include: commit hash,
  what changed, which tests cover it.
- **LIKELY FIXED** — code fix appears present but no specific tests cover
  this exact issue. Include what was found and what's missing.
- **NOT FIXED** — the reported problem still exists in the code (normal —
  this is just a research blurb, the issue stays open).
- **UNCLEAR** — can't determine from code review alone (needs manual testing).

**Criteria for FIXED/LIKELY FIXED verdicts:**
- The specific code the issue reported as broken has been changed
- Tests exist that cover the reported behavior (FIXED) or not (LIKELY FIXED)
- The fix commit references the issue number or is clearly related
- Do NOT verdict as FIXED if: the issue is a feature request (not a bug),
  the fix is partial, or you're not confident

Also scan for additional close candidates from:
- **Tracker files** — `[x]` items that are still open on GitHub
- **Sprint reports** — entries in "Already Implemented" or "Already Fixed
  on Main" sections of `SPRINT_REPORT.md`

For these candidates, dispatch verification agents with the same checklist
above (read issue body, check code, check tests, produce verdict).

### Step 3 — Present findings

Show the sync summary and any close candidates:

```
Sync complete. N open issues, M newly researched, K tracker files updated.
Gaps: [any GH issues not in any tracker]

Issues that appear already fixed (N candidates):

| # | Title | Verdict | Evidence |
|---|-------|---------|----------|
| #126 | Fcn block mapping | FIXED | SlxImporter.js:85, commit abc1234, 2 tests |
| #191 | Block stubs | FIXED | All 4 blocks implemented, 12 tests pass |
| #393 | Fcn codegen u(N) | FIXED | codegen emitter step 8, commit def5678 |
| #200 | Some bug | LIKELY FIXED | Code changed but no regression test |

Close 3 FIXED issues? (all / comma-separated numbers / none)
```

- Wait for user selection. LIKELY FIXED and UNCLEAR items are shown for
  context but NOT offered for closing — they need human judgment.
- **If no close candidates found:** skip this step, just show the sync
  summary.

### Step 4 — Close approved issues on GitHub

For each approved issue:

1. **Close with a comment** explaining what fixed it:
   ```bash
   gh issue close <N> --comment "Fixed in commit <hash>. <brief description of fix>. Tests: <test file(s)>."
   ```

2. **Update tracker files** — mark the issue `[x]` in all relevant trackers.

3. **Update SPRINT_REPORT.md** — if the issue appears in an "Already
   Implemented" section, add a note: `Closed by /fix-issues sync`.

### Step 5 — Commit & report

1. **Commit** updated tracker files.

2. **Report:**
   ```
   Sync complete.
     Open issues: N
     Newly researched: M
     Tracker files updated: K
     Closed (verified fixed): J (#NNN, #NNN, ...)
     Likely fixed (needs human review): L (#NNN, #NNN)
     Gaps: [any GH issues not in any tracker]
   ```

3. **Exit.**

## Plan (if `plan` is present)

Draft plans for issues previously skipped as "too complex for batch fix."
Accepts optional `auto` — `/fix-issues plan auto` skips the selection gate
and drafts plans for all found issues.

1. **Run `node scripts/skipped-issues.cjs --check-gh`** — this scans the
   ENTIRE `SPRINT_REPORT.md` across all sprints, extracts skipped issue
   numbers (including ranges like #148-#168), deduplicates against existing
   executable plans in `plans/`, and checks GitHub issue state. Output is
   JSON with each issue classified as `needs-plan`, `has-plan`, or `closed`.

   Use the script output directly — do NOT manually grep SPRINT_REPORT.md.

2. **Deduplicate** — check `plans/` for existing plans that already cover
   each issue. Also check whether the issue is still open on GitHub
   (`gh issue view <N> --json state`). Remove issues that already have
   a plan or are closed.

3. **Present findings** (unless `auto`):
   > Found N issues needing plans:
   > | # | Title | Source |
   > |---|-------|--------|
   > | #142 | Drag into subsystem | Sprint 2026-03-17: Skipped — Too Complex |
   > | #363 | Algebraic loop detection | Sprint 2026-03-16: Remaining Open |
   > ...
   > Already have plans: #NNN, #NNN (skipped)
   > Already closed: #NNN (skipped)
   >
   > Which issues should I draft plans for? (all / comma-separated numbers / none)

   Wait for the user's selection before proceeding. If `auto`, skip this
   step and plan all of them.

4. **For each selected issue**, dispatch `/draft-plan` with:
   - The issue number and full body (`gh issue view <N> --json body`)
   - Any research blurb from the tracker files
   - Output path: `plans/{issue-slug}.md`

5. **Report:**
   > Plans drafted: N
   > - plans/foo-bar.md (#123) — [one-line summary]
   > - plans/baz-qux.md (#456) — [one-line summary]
   > Already had plans: M (skipped)
   > Closed issues: K (skipped)
   > User declined: J

6. **Exit.** Plans are ready for `/run-plan` execution.

## Phase 0 — Schedule (if `every` is present)

If `$ARGUMENTS` contains `every <schedule>`:

1. **Parse the schedule** — convert to a cron expression. The LLM interprets
   natural scheduling expressions.

   **For interval-based schedules** (`4h`, `2h`, `30m`): use the CURRENT
   minute as the offset so the first fire is a full interval from now, not
   aligned to midnight. Check the current minute with `date +%M`:
   - `4h` at minute 9 → `9 */4 * * *` (fires at :09 past every 4th hour)
   - `2h` at minute 15 → `15 */2 * * *`
   - `30m` → `*/30 * * * *` (no offset needed for sub-hour)
   - `1h` at minute 9 → `9 * * * *`

   **For time-of-day schedules** (`day at 9am`, `weekday at 2pm`): offset
   round minutes by a few to avoid API busy marks:
   - `day at 9am` → `3 9 * * *`
   - `day at 14:00` → `3 14 * * *`
   - `weekday at 9am` → `3 9 * * 1-5`

2. **Deduplicate** — use `CronList` to list existing cron jobs. Use
   `CronDelete` to remove any whose prompt starts with `Run /fix-issues`
   (prevents duplicate schedules from accumulating).

3. **Reconstruct the arguments** for the cron prompt. Always include `now`
   in the cron prompt so each cron fire runs immediately AND re-registers
   itself (self-perpetuating). Note: this `now` is for the CRON's invocation,
   not the current invocation — the user controls whether THIS run executes
   immediately via their own `now` flag:
   ```
   Run /fix-issues <N> [focus] auto every <schedule> now
   ```

4. **Create the cron** — use `CronCreate`:
   - `cron`: the cron expression from step 1
   - `recurring`: true
   - `prompt`: the reconstructed command from step 3

5. **Confirm** — tell the user, including the estimated wall-clock time of
   the next run. Compute from the cron expression. **Always show times in
   America/New_York (ET)** — use `TZ=America/New_York date` for conversion,
   not the system timezone (which may be UTC). Example:

   If `now` is present:
   > Fix-issues sprint scheduled every 4h. Running now.
   > Next auto-sprint after this one: ~8:15 PM ET (cron ID XXXX).

   If `now` is NOT present:
   > Fix-issues sprint scheduled every 4h.
   > First run: ~4:15 PM ET (cron ID XXXX).
   > Use `/fix-issues next` to check, `/fix-issues stop` to cancel.

6. **If `now` is present:** proceed to Phase 1 (run immediately).
   **If `now` is NOT present:** **Exit.** The cron will fire at the scheduled
   time. Do not run a sprint now.

**End-of-sprint scheduling note:** when a sprint finishes and a cron is
active, always include the estimated next run time with timezone in the
completion message. Example:
> Sprint complete. Next auto-sprint in ~3h 45m (~11:30 PM ET, cron XXXX).

If `every` is NOT present, skip this phase entirely and proceed to Phase 1
(bare invocation always runs immediately).

## Phase 1 — Preflight & Sync

**IMPORTANT: Complete ALL steps (1-6 + Phase 1b) before Phase 2.** Do NOT
skip tracker updates or research to "save time." Dispatching agents without
research blurbs causes misinterpretation — agents guess from titles and
implement the wrong fix. This has happened repeatedly.

### Preflight checks (before doing anything else)

Before starting the sprint, check for stale state from a previous failed run:

1. **In-progress git operation?**
   ```bash
   ls .git/CHERRY_PICK_HEAD .git/MERGE_HEAD .git/REBASE_HEAD 2>/dev/null
   git status --porcelain | grep '^UU\|^AA\|^DD'
   ```
   If either command produces output, the working tree has an unfinished
   cherry-pick, merge, or rebase — likely from a previous failed sprint.
   **STOP.** Invoke the Failure Protocol.

   Note: normal uncommitted changes (modified plan files, logs) are expected
   and are NOT a reason to stop. Phase 6 stashes those before cherry-picking.

2. **Stash stack?**
   ```bash
   git stash list
   ```
   If there is a stash with message containing "pre-cherry-pick", a previous
   sprint's stash was never restored. **STOP.** Alert the user — they need to
   `git stash pop` or `git stash drop` before a new sprint can start safely.

3. **Leftover sprint worktrees?**
   ```bash
   git worktree list
   ```
   If worktrees from a previous sprint exist, warn the user. They may contain
   unapplied fixes. Do not remove them — just note their presence and continue.

If any preflight check fails, invoke the **Failure Protocol** (kill cron,
alert user, write failure to report).

### Sync

1. **Fetch all open GitHub issues:**
   ```bash
   gh issue list --state open --limit 500 --json number,title,labels,createdAt
   ```

2. **Run the sync script** to find gaps between GitHub and plan files:
   ```bash
   node ${CLAUDE_SKILL_DIR}/scripts/sync-issues.js
   ```

3. **Run the stats script** to see current distribution:
   ```bash
   node ${CLAUDE_SKILL_DIR}/scripts/issue-stats.js
   ```

4. **Update ALL issue trackers** — scan `plans/` for tracker files:
   ```bash
   ls plans/*ISSUES*.md plans/ISSUES_PLAN.md 2>/dev/null
   ```
   Ensure each tracker reflects current GitHub state. Add new issues to
   the appropriate tracker based on domain.

5. **Identify gaps** — any GH issues not tracked in any plan file? Add them to
   the appropriate tracker.

6. **Research new issues** — for each issue added in step 5 (or any issue
   lacking a research blurb in its tracker entry), dispatch research agents
   using the same workflow as the standalone `sync` command:
   1. Read the full issue body (`gh issue view <N>`)
   2. Search the codebase for the affected code
   3. Write a concise research blurb (what's wrong, where, suggested approach)
   4. Add the blurb to the appropriate tracker file

   Without this step, Phase 2 prioritizes from bare titles and Phase 3
   dispatches agents with no context — leading to misinterpretation.
   Past failure: #387 "reset button" was interpreted as "clear canvas"
   instead of "reset mappings to defaults" because only the title was read.

   In `auto` mode, dispatch research agents in parallel (up to 3 at a time)
   and proceed after all complete. In interactive mode, present the research
   blurbs before moving to Phase 1b.

## Phase 1b — Read Full Issue Bodies & Plan Context

**Before prioritizing**, gather full context for every candidate issue:

1. **Fetch the issue body and comments from GitHub:**
   ```bash
   gh issue view <N> --json number,title,body,labels,comments
   ```

2. **Fetch the research blurb from plan files:**
   ```bash
   grep -A 30 '#<N>' plans/*ISSUES*.md 2>/dev/null
   ```
   Plan blurbs contain root cause analysis, affected files, suggested fixes,
   and effort estimates. This context was gathered when the issue was filed —
   don't waste time re-researching what's already documented.

Both steps are **mandatory**. Titles are often vague or misleading. The body
and plan blurb together are the spec. You cannot prioritize or write accurate
agent prompts without reading both.

For each candidate, note:
- What the user actually described (not what the title implies)
- Root cause and affected files (from plan blurb)
- Repro steps if provided
- Suggested fix approach (from plan blurb)
- Context metadata (model name, browser, screen size)

## Phase 2 — Prioritize

Present the next N issues to fix as a ranked table:

| Priority | # | Title | Severity | Domain | Effort | Tracker |
|----------|---|-------|----------|--------|--------|---------|

**If a focus argument is provided**, issues in that domain are boosted to the
top, then the remaining slots filled by default priority.

**Default ranking criteria (in order):**
1. New issues not yet attempted (user feedback, recently filed)
2. Correctness defects (from issue trackers tagged as correctness)
3. Critical/high severity bugs
4. Quick wins (15 min – 1 hour)
5. Issues with clear repro steps
6. Test gaps (from issue trackers tagged as test quality)

### Triage: vague, complex, or interrelated issues

While building the ranked list, classify each candidate:

- **Clear and doable** — repro steps, expected behavior, affected files
  identified. Include in the sprint.
- **Too vague** — no repro steps, no expected behavior, body is empty or
  just "it's broken." You don't know WHAT to fix.
  - Interactive: flag it and ask the user for clarification
  - Auto: skip it, report as "Skipped: insufficient context" in
    SPRINT_REPORT.md
- **Too complex** — clear spec but would require 500+ lines, major
  refactoring, or architectural changes. Not a batch-fix item.
  - Interactive: report "this needs `/run-plan`, not `/fix-issues`"
  - Auto: skip it, report as "Skipped: too complex for batch fix"
  - If `plans/PLAN_INDEX.md` exists, grep plan files for the issue number
    (e.g., `#NNN`). If a plan already covers this issue, note which plan
    in the skip reason. If no plan covers it, add to the skip note:
    "Consider `/draft-plan` for #NNN."

**"Too vague" means you don't know WHAT to do — not that you don't know
HOW.** If the issue clearly describes the problem but the fix is hard,
that's not vague — that's work. Never use "vague" as an excuse to skip
hard issues.

### Group by dependency and file overlap

Before dispatching agents, check for interrelated issues:

- **Same root cause** — if #100 and #101 are both caused by an off-by-one
  in Solver.js, group them for the same agent. One agent, one worktree,
  one fix closes both.
- **Same file** — if #200 and #201 both need changes to Parser.js, group
  them for the same agent. Separate worktrees would produce conflicting
  cherry-picks.
- **Prerequisite relationship** — if fixing #300 requires the fix from #299
  to be in place, give both to the same agent in order.

Tell the agent when issues are related: "Issues #100 and #101 share
root cause X in file Y — consider fixing them together with a single commit."

**Bundling beyond N.** When prioritizing, if additional open issues would
naturally be fixed in the same session (same component, same area of code)
or appear to have the same root cause, the orchestrator should include
them alongside the selected issue for the same agent. These don't count
toward N. In interactive mode, show bundled extras in the approval list
with the rationale so the user can adjust. This keeps `/fix-issues 1
every 1h` efficient — one agent, one worktree, but it picks up tightly
coupled neighbors instead of leaving them for the next sprint.

### Present the list

- **Without `auto`:** **Wait for user approval** of the list before proceeding.
  Include the grouping rationale so the user can adjust.
- **With `auto`:** Present the ranked table for the record, then proceed
  immediately using the ranking criteria above.

### If no actionable issues found

If ALL candidates are too vague, too complex, or already attempted:

1. **Auto-sync before giving up.** Run the full Sync workflow (Steps
   1-5). In auto mode, auto-close issues with FIXED verdict (commit
   hash + tests — the same bar as interactive sync, just without the
   approval gate). LIKELY FIXED and UNCLEAR still require human
   judgment and are skipped. Then re-run Phase 1b and Phase 2 to
   re-evaluate the candidate pool. If actionable issues are now
   available, proceed to Phase 3 normally.

   **Only sync once per sprint.** If still empty after, proceed to step 2.

2. **If still no actionable issues after refresh:**
   - Write a minimal sprint section to SPRINT_REPORT.md: `## Sprint —
     YYYY-MM-DD HH:MM [UNFINALIZED]` with "No actionable issues found
     (synced twice)" and the skip reasons.
   - **Do NOT kill the cron** — new issues may be filed before the next run.
   - After **3 consecutive empty runs**, add a note: "3 consecutive runs
     with no actionable issues. Run `/fix-issues stop` if no new issues
     are expected." Do NOT auto-stop — that's the user's call.
   - **Exit.** Skip Phases 3-6.

## Phase 3 — Execute (agent teams in worktrees)

**1 issue per agent, parallel dispatch.** Each issue gets its own agent
in its own worktree (`isolation: "worktree"`). **Dispatch at most 3
worktree agents per message.** If you have more than 3, dispatch the
first 3, wait for them to return, then dispatch the next batch. Five
concurrent `git checkout` operations cause I/O contention on 9p
filesystems — checkouts stall at ~72% and the Agent framework times
out, leaving orphaned worktree directories.

- **Interrelated issues** (same root cause or same files from Phase 2
  grouping) share one agent and one worktree. Tell the agent which
  issues are grouped and why.
- **Unrelated issues get separate agents.** Never batch unrelated hard
  issues into one agent — this caused a 4.5h bottleneck when one agent
  got 4 diverse issues sequentially.

**Agent timeout: 1 hour.** Note the dispatch time for each agent. If an
agent hasn't returned after 1 hour, declare it **failed**:
- Mark its issues as "Timed out" in SPRINT_REPORT.md
- Issues stay open for the next sprint
- The worktree is a cleanup artifact — do NOT auto-land late results
- If the agent eventually returns, ignore it. Timed out = failed, period.

**Agent dispatch prompts MUST include for each issue:**

1. **The verbatim issue body** from Phase 1b (`gh issue view`). Do NOT
   paraphrase or summarize — include the full text the user wrote. Titles are
   often vague; the body is the spec. If the body is empty, say so explicitly.
2. **The research blurb from issue tracker files** (`plans/*ISSUES*.md`).
   These contain root cause analysis, affected files, suggested fixes, and
   effort estimates written when the issue was filed. Grep the tracker files
   for the issue number and include any matching section verbatim.

The agent should have everything it needs to understand the problem without
re-researching from scratch. Missing context = wrong fix.

**For issue bodies or plan blurbs longer than ~100 lines:** write the
verbatim text to a temp file (e.g., `/tmp/issue-NNN.md`) and tell the agent
to `Read` the file. This avoids the natural LLM tendency to compress long
text when inlining it in a prompt. Shorter content can be inlined directly.

Each agent follows this fix workflow:

1. Read the issue body (included in prompt) and relevant code
2. Reproduce the bug (unit test or manual)
3. Implement the fix
4. Write regression tests (unit and/or E2E as appropriate)
5. Run `npm run test:all` — all suites must pass
6. **Agent verification** via `/manual-testing` if UI files changed —
   use playwright-cli with real events, take screenshots as evidence.
   The pre-commit hook will BLOCK your commit if UI files are staged
   but `playwright-cli` wasn't used in the session. This is not optional.
7. **Classify User Verify** — if any UI/editor/styles files changed
   (check your project's UI directories), mark `User Verify: NEEDED`
   in the sprint report. The user must see UI changes before the issue
   can be closed. This is in ADDITION to your agent verification.
8. Commit in the worktree (one issue per commit, clean history)
9. **Rebase onto current main before final commit:**
   ```bash
   git fetch origin main && git rebase origin/main
   ```
   This ensures the commit contains only the agent's changes, not stale
   copies of files other agents already fixed on main. If rebase conflicts,
   abort (`git rebase --abort`) and proceed — Phase 6 cherry-pick
   verification will catch stale files via selective extraction.

Agents commit freely in worktrees — that's the point of isolation. Worktree
commits are safe and expected. The approval gate is landing to main (Phase 6).

## Phase 4 — Review

After each agent completes, **dispatch a fresh agent** to run `/verify-changes
worktree` in its worktree. Do NOT run verification yourself — you wrote
the dispatch prompts, so you have implementer bias. The verification agent
must be a fresh agent with no memory of the implementation.

This delegates the full review workflow (diff review, test coverage audit,
test run, manual verification, fix & re-verify cycle) to a separate agent.

Report the review results to the user.

## Phase 5 — Write Sprint Report (BEFORE landing)

**APPEND** a new sprint section to `SPRINT_REPORT.md` BEFORE Phase 6
(landing). The report is a prerequisite for landing — if it's not written,
Phase 6 does not execute.

**APPEND, do not overwrite.** Multiple sprints may run between `/fix-report`
reviews (e.g., cron every 2h, user checks once a day). Each sprint adds a
new `## Sprint — YYYY-MM-DD HH:MM [UNFINALIZED]` section. `/fix-report`
processes all UNFINALIZED sections when the user reviews.

If the file doesn't exist, create it with a `# Sprint Report` heading.

Past failure: an agent skipped Phase 5 for 8 consecutive sprints to "keep
the hourly cadence fast." SPRINT_REPORT.md was stale for 8 sprints,
making `/fix-report` useless. Another failure: the file was overwritten
each sprint, losing results from earlier sprints that were never reviewed.

**Report format** — each sprint appends a section like this:

```markdown
## Sprint — YYYY-MM-DD HH:MM [UNFINALIZED]

**Mode:** auto | interactive | **Focus:** <focus> | default

### Fixed
| # | Title | Worktree | Commit | Tests | Agent Verify | User Verify |
|---|-------|----------|--------|-------|-------------|-------------|
| #123 | Solver crash | wt-123 | abc1234 | 2 unit | PASS (tests) | N/A |
| #456 | Button offset | wt-456 | def5678 | 1 E2E | PASS (screenshot) | NEEDED |

**Agent Verify:** Did the agent test it? PASS (with method) or SKIPPED.
The pre-commit hook blocks commits without test evidence.

**User Verify:** Does the user need to see this? Mechanically classified:
if any UI/editor/styles files changed → `NEEDED`. Otherwise → `N/A`.
`/fix-report` Step 2
presents all `NEEDED` items for user review before closing.

### Skipped — Too Vague (need repro steps or clearer spec)
| # | Title | What's Missing |
|---|-------|----------------|

### Skipped — Too Complex (need /run-plan)
| # | Title | Why |
|---|-------|-----|

### Skipped — Cherry-Pick Conflict (will retry next sprint)
| # | Title | Conflict Details |
|---|-------|-----------------|
| #789 | Parser error | cherry-pick conflict on commit abc1234 |

### Not Fixed (agent attempted but failed)
| # | Title | Reason |
|---|-------|--------|
```

The file starts with `# Sprint Report` (created once). Each sprint
appends a new `## Sprint` section. `/fix-report` marks sections
`[FINALIZED]` after review. **Use actual data** — real issue numbers,
commit hashes, worktree paths, and test counts.

## Phase 6 — Land

- **Without `auto`:** Sprint complete. Output:
  > Sprint complete. Report written to `SPRINT_REPORT.md`.
  > Run `/fix-report` to review fixes, land to main, and close issues.

  All interactive landing, closing, and cleanup moves to `/fix-report`.
  `/fix-issues` is DONE after writing the report.

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
        cat > "<worktree>/.landed.tmp" <<LANDED
        status: full
        date: $(TZ=America/New_York date -Iseconds)
        source: fix-issues
        commits:
          <list of cherry-picked commit hashes and messages>
        LANDED
        mv "<worktree>/.landed.tmp" "<worktree>/.landed"
        ```
     c. For tiers that were SKIPPED (conflict), write partial marker:
        ```bash
        cat > "<worktree>/.landed.tmp" <<LANDED
        status: partial
        date: $(TZ=America/New_York date -Iseconds)
        source: fix-issues
        landed: <hashes that did land, if any>
        skipped: <hashes that conflicted>
        reason: cherry-pick conflict
        LANDED
        mv "<worktree>/.landed.tmp" "<worktree>/.landed"
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
        rm -f "<worktree>/.landed" "<worktree>/.worktreepurpose" \
              "<worktree>/.test-results.txt"
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
cat > "<worktree>/.landed.tmp" <<LANDED
status: failed
date: $(TZ=America/New_York date -Iseconds)
source: fix-issues
issues: <issue numbers attempted>
reason: <agent returned no commits / agent crashed / tests failed>
LANDED
mv "<worktree>/.landed.tmp" "<worktree>/.landed"
```
This ensures `/fix-report` can distinguish failed worktrees from active
ones. The issues stay open for the next sprint.

## Key Rules

- **Worktrees only** — all fixes happen in isolated worktrees, never in the
  main working tree.
- **Agents commit freely in worktrees** — that's the point of isolation.
  Worktree commits are safe and expected.
- **Never cherry-pick to main without permission** — unless `auto` flag is set,
  in which case the user has pre-approved autonomous landing.
- **In `auto` mode, skip conflicting cherry-picks** — abort the conflict,
  skip all commits from that worktree (grouped issues depend on each
  other), mark as "Skipped: conflict" in the report, and continue
  landing from other worktrees. The skipped issues self-heal next sprint.
- **Always write `SPRINT_REPORT.md`** — it's the handoff to `/fix-report`.
- **Never close GH issues, update trackers, or remove worktrees** — that's
  `/fix-report`'s job.
- **One issue per commit** — clean git history in worktrees.
- **`npm run test:all` before every commit** — not just `npm test`.
- **Never weaken tests** — fix the code, not the test. Do not loosen
  tolerances, skip assertions, or remove test cases.
- **Never defer the hard parts** — finish all phases of the plan. Do not
  stop after the easy part and call remaining work "future phases."
- **Protect untracked files** — before stash/cherry-pick/merge, inventory
  untracked files (`git status -s | grep '^??'`). Use `git stash -u` or
  save them first.
- **`every` implies `auto`** — scheduling only makes sense for autonomous
  runs. If `every` is present but `auto` is not, treat it as if `auto` was set.
- **Deduplicate crons** — always remove existing `/fix-issues` crons before
  creating a new one. Never let duplicate schedules accumulate.
- **Crons are session-scoped** — they expire when the session dies. Tell the
  user to re-run `/fix-issues ... every` to restart scheduling.
- **Kill the cron on failure** — if anything in the sprint fails unrecoverably,
  the FIRST action is `CronDelete`. A broken sprint + live cron = the next run
  stomps on the bad state. See the Failure Protocol for the full sequence.
- **Read every issue body before acting** — `gh issue view <N>` is mandatory
  in Phase 1b. Titles are often vague or misleading. The body is the spec.
  Never paraphrase — include verbatim issue text in agent dispatch prompts.
  Past failure: #387 title "reset button" was interpreted as "clear canvas"
  instead of "reset mappings to defaults" because only the title was read.
- **Ultrathink** — use careful, thorough reasoning. Read code, understand
  what changed and why, verify correctness.
