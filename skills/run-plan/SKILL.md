---
name: run-plan
disable-model-invocation: false
argument-hint: "<plan-file> [phase|finish|status] [auto] [every SCHEDULE] [now] | stop | next"
description: >-
  Execute the next phase of a plan document: parse phases and status, dispatch
  implementation in a worktree, verify with a separate agent, update progress
  tracking, write reports/plan-{slug}.md, and optionally auto-land to main. Can
  self-schedule recurring runs via cron. Use `next` to check schedule, `stop`
  to cancel.
---

# /run-plan \<plan-file> [phase|finish] [auto] [every SCHEDULE] [now] | stop | next — Plan Phase Executor

Orchestrates plan-driven development. Reads a plan document, identifies the
next incomplete phase, dispatches implementation in a worktree, verifies with a
separate agent, updates progress tracking, writes a persistent report, and
optionally auto-lands to main. Can self-schedule for recurring runs to work
through multi-phase plans autonomously.

**Ultrathink throughout.** Use careful, thorough reasoning at every step.

## Arguments

```
/run-plan <plan-file> [phase] [auto] [every SCHEDULE] [now]
/run-plan stop | next
```

- **plan-file** (required) — path to plan, e.g. `plans/FEATURE_PLAN.md`
- **phase** (optional) — specific phase, e.g. `4a`. If omitted, auto-detect
  next incomplete phase
- **finish** (optional) — run ALL remaining phases sequentially until the
  plan is complete. `finish` is approval to START — do not ask for
  confirmation before the first phase (the user already said "finish").
  Without `auto`: pauses BETWEEN phases to show results and ask "continue
  to next phase?" With `auto`: runs all phases without pausing (overnight).
  Each phase still gets full verification, testing, and all safety rails.
  If any phase fails verification or hits a conflict, stops there.
  **`finish` and `every` are mutually exclusive.** `finish` runs all phases
  in one session. `every` schedules one phase per cron fire. Combining them
  is meaningless — `finish` either completes (cron self-terminates) or fails
  (Failure Protocol kills the cron). Use one or the other.
- **auto** (optional) — bypass approval gates, auto-land to main via cherry-pick
- **every SCHEDULE** (optional) — self-schedule recurring runs via cron:
  - Accepts intervals: `4h`, `2h`, `30m`, `12h`
  - Accepts time-of-day: `day at 9am`, `day at 14:00`, `weekday at 9am`
  - Without `now`: schedules only, does NOT run immediately
  - With `now`: schedules AND runs immediately
  - Implies `auto` — scheduling only makes sense for autonomous runs
  - Cron prompt omits phase number so each invocation auto-detects the next
    incomplete phase
  - Each run re-registers the cron (self-perpetuating)
  - Cron is session-scoped — dies when the session dies
- **now** (optional) — run immediately. When combined with `every`, runs
  immediately AND schedules. Without `every`, `now` is the default behavior.
- **status** — show plan progress: all phases, their status, what's next,
  and what's blocked. Read-only — no agents dispatched, no approval gate.
- **stop** — cancel any existing `/run-plan` cron and exit. **Takes
  precedence over all other arguments.**
- **next** — check when the next scheduled run will fire. **Takes precedence
  over all other arguments except `stop`.**

**Detection:** scan `$ARGUMENTS` for:
- `stop` (case-insensitive) — cancel cron and exit (highest precedence)
- `next` (case-insensitive) — check schedule and exit
- `status` (case-insensitive) — show plan progress and exit
- `finish` (case-insensitive) — run all remaining phases sequentially
- `now` (case-insensitive) — run immediately
- `auto` (case-insensitive) — autonomous mode
- `every` followed by a schedule expression — scheduling mode

Examples:
- `/run-plan plans/FEATURE_PLAN.md` — interactive, next phase
- `/run-plan plans/FEATURE_PLAN.md 4b` — interactive, specific phase
- `/run-plan plans/FEATURE_PLAN.md finish` — interactive, all remaining phases (pauses between each)
- `/run-plan plans/FEATURE_PLAN.md finish auto` — autonomous, all remaining phases (no pausing)
- `/run-plan plans/FEATURE_PLAN.md auto every 4h` — schedule every 4h
- `/run-plan plans/FEATURE_PLAN.md auto every 4h now` — schedule + run now
- `/run-plan plans/FEATURE_PLAN.md status` — show plan progress
- `/run-plan now` — trigger the active cron early
- `/run-plan stop` — cancel scheduled runs
- `/run-plan next` — check when the next phase will run

## Status (if `status` is present)

If `$ARGUMENTS` contains `status` (case-insensitive):

1. Read the plan file specified in the arguments
2. Also read any companion progress document if referenced
3. Parse all phases and their status (same parsing logic as Phase 1
   steps 2-3: "Extract phases and status" and "Determine target phase."
   Do NOT run preflight checks — `status` is read-only)
4. Present a progress table:

   ```
   Plan: plans/FEATURE_PLAN.md

   | Phase | Status |
   |-------|--------|
   | 4a — Electrical | Done (abc1234) |
   | 4b — Mechanical | Done (def5678) |
   | 4c — Smooth Nonlinear | Next ← |
   | 4d — Solver Fixes | Blocked (needs 4c) |
   | 4e — UI Polish | Blocked (needs 4d) |

   Next phase: 4c — Smooth Nonlinear Components
   Dependencies: 4a ✓, 4b ✓
   ```

5. If a cron is active, also show the schedule:
   > Scheduled: every 4h (~8:15 PM ET next, cron XXXX)

6. **Exit.** Read-only — no agents dispatched, no work done.

## Now (standalone — no plan-file provided)

If `$ARGUMENTS` is just `now` (no plan-file, no phase, no every):

1. Use `CronList` to list all cron jobs
2. Find any whose prompt starts with `Run /run-plan`
3. If found: extract the cron's prompt to get the plan-file, auto, and
   schedule. **Run the phase immediately** — proceed to Phase 1. Do NOT
   ask for confirmation — `now` IS the confirmation. The cron stays active.
4. If none found: report `No active /run-plan cron to trigger. Use
   /run-plan <plan-file> to run manually.` and **exit.**

## Next (if `next` is present)

If `$ARGUMENTS` contains `next` (case-insensitive):

1. Use `CronList` to list all cron jobs
2. Find any whose prompt starts with `Run /run-plan`
3. Report:
   - If found: parse the cron expression and compute the next fire time.
     Use `date +%Z` for the timezone. Show both relative and absolute:
     > Next run-plan phase in ~2h 15m (~8:30 PM ET, cron XXXX).
     > Prompt: Run /run-plan plans/FEATURE_PLAN.md auto every 4h
   - If none found: `No active /run-plan cron in this session.`
4. **Exit.** Do not proceed to any phase.

## Stop (if `stop` is present)

If `$ARGUMENTS` contains `stop` (case-insensitive):

1. Use `CronList` to list all cron jobs
2. Delete ALL whose prompt starts with `Run /run-plan` using `CronDelete`
3. Report what was cancelled:
   - If one cron found: `Run-plan cron stopped (was job ID XXXX, every INTERVAL).`
   - If multiple found: `Stopped N run-plan crons (IDs: XXXX, YYYY).`
   - If none found: `No active /run-plan cron found.`
4. **Exit.** Do not proceed to any phase. The `stop` command does nothing else.

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

2. **Deduplicate** — use `CronList` + `CronDelete` to remove any whose
   prompt starts with `Run /run-plan`.

3. **Construct the cron prompt.** Strip the phase number (so each invocation
   auto-detects the next incomplete phase). Always include `now` in the cron
   prompt so each cron fire runs immediately AND re-registers itself. Note:
   this `now` is for the CRON's invocation, not the current invocation:
   ```
   Run /run-plan <plan-file> auto every <schedule> now
   ```
   Note: the phase number is intentionally omitted so the cron auto-advances.

4. **Create the cron** — use `CronCreate`:
   - `cron`: the cron expression from step 1
   - `recurring`: true
   - `prompt`: the constructed command from step 3

5. **Confirm** with wall-clock time. **Always show times in America/New_York
   (ET)** — use `TZ=America/New_York date` for conversion, not the system
   timezone (which may be UTC):

   If `now` is present:
   > Run-plan scheduled every 4h. Running now.
   > Next phase run after this one: ~8:15 PM ET (cron ID XXXX).

   If `now` is NOT present:
   > Run-plan scheduled every 4h.
   > First run: ~4:15 PM ET (cron ID XXXX).
   > Use `/run-plan next` to check, `/run-plan stop` to cancel.

6. **If `now` is present:** proceed to Phase 1 (run immediately).
   **If `now` is NOT present:** **Exit.** The cron fires later.

**End-of-phase scheduling note:** when a phase finishes and a cron is
active, always include the estimated next run time with timezone in the
completion message. Example:
> Phase complete. Next phase run in ~3h 45m (~11:30 PM ET, cron XXXX).

If `every` is NOT present, skip this phase and proceed to Phase 1
(bare invocation always runs immediately).

## Phase 1 — Parse Plan & Extract Verbatim Phase Text

The key differentiator. Plans have varied formats, so the agent uses LLM
comprehension rather than rigid parsing.

### Preflight checks

Before parsing, check for stale state from a previous failed run:

0. **Idempotent re-entry check (chunked finish auto only).** If running
   with `finish auto`, this turn may have been triggered by a cron from
   a previous turn. Read the plan tracker BEFORE doing anything else and
   determine the next-target phase:
   - If the next-target phase is already marked Done, the plan is
     complete. Output "Plan complete (already)" and exit cleanly. No
     more work to do, no more crons to schedule.
   - If the next-target phase is already marked In Progress, another
     agent (or a duplicate cron fire) is already working on it. Exit
     cleanly with "Phase X already in progress, deferring." Do NOT
     compete or duplicate work.
   - Otherwise, proceed with the rest of the preflight and process the
     next phase normally.

   This idempotent check makes stale crons harmless. A cron that fires
   after the user has manually advanced past its target phase simply
   exits.

1. **In-progress git operation?**
   ```bash
   ls .git/CHERRY_PICK_HEAD .git/MERGE_HEAD .git/REBASE_HEAD 2>/dev/null
   git status --porcelain | grep '^UU\|^AA\|^DD'
   ```
   If either command produces output, **STOP.** Invoke the Failure Protocol.

2. **Stash stack?**
   ```bash
   git stash list
   ```
   If there is a stash with message containing "pre-cherry-pick", a previous
   run's stash was never restored. **STOP.** Invoke the Failure Protocol —
   the user needs to `git stash pop` or `git stash drop` before a new phase
   can start safely.

3. **Leftover plan worktrees?**
   ```bash
   git worktree list
   ```
   If worktrees from a previous run exist (paths containing `plan-`), warn
   the user. Do not remove them — note their presence and continue.

4. **Unconfigured hook placeholders?**
   ```bash
   grep -q '{{' .claude/hooks/block-unsafe-project.sh 2>/dev/null
   ```
   If found AND test infrastructure exists (`package.json` with a `"test"`
   script, or `vitest.config.*` / `jest.config.*` exists), **STOP.** Hook
   placeholders have not been configured — run `/update-zskills` first.

### Parse plan

1. **Read the plan file** in full. Also read any companion progress document
   if referenced (e.g., `FEATURE_PROGRESS_AND_NEXT_STEPS.md`).

2. **Extract phases and status** — handle four formats:
   - **Progress tracker table** (FEATURE_PLAN style): rows with `✅ Done`,
     `⬚` (not started), `🟡` (in progress), etc.
   - **Numbered phase sections** (`## Phase 4a — Title`): look for completion
     markers in the section body or companion doc
   - **Checklist** (`- [x]` / `- [ ]`): checked = done, unchecked = not done
   - **Narrative**: infer status from codebase evidence (files exist, tests
     pass, etc.)

3. **Determine target phase:**
   - If phase arg given: use it. If already complete, warn (or skip in auto)
   - If no phase arg: first incomplete phase
   - If ALL phases complete: report "Plan complete" → stop. If `every`,
     delete the cron via `CronList` + `CronDelete`
   - If multiple phases share the same number (e.g., 4a, 4b, 4c), treat
     each sub-phase as a separate phase

4. **Check dependencies** — if a prerequisite phase isn't Done, **STOP.**
   Report which dependency is missing. If `every`, the cron retries later.

5. **Check for conflicts** — if the target phase is "In Progress" (🟡 or
   equivalent), another agent may be working on it. **STOP.** Do not compete.

6. **Check for staleness notes** — if the plan's Dependencies section
   contains language like "drafted before," "may need refresh," or "APIs
   and data structures referenced here are based on [another plan's]
   design, not actual code," the plan may be stale:
   - Without `auto`: tell the user "this plan was drafted before its
     dependency was implemented. Want me to refresh it with `/draft-plan`?"
   - With `auto`: dispatch `/draft-plan` on the plan file to update it.
     `/draft-plan` handles existing files as modernizations. After the
     refresh, re-read the plan and continue.
   - Skip this check if the plan file was modified more recently than
     the dependency's completion (it may already be up to date).

7. **Save the VERBATIM phase text** — copy the entire section from the plan
   file exactly as written. Every sentence, every bullet, every formula, every
   constraint. This text will be passed to agents in Phase 2 and Phase 3.

   **Do NOT summarize, paraphrase, or reinterpret.** The plan is the spec.

   Lesson from `/fix-issues` #387: summarized descriptions caused agents to
   implement the wrong thing. "Reset button" was interpreted as "clear canvas"
   instead of "reset mappings to defaults" because only the title was read.
   The same will happen with plan phases if the orchestrator summarizes
   "implement translational mechanical domain" without the formulas, state
   equations, and design constraints.

8. **Create tracking fulfillment marker AND lock down verification
   requirement.** Determine the tracking ID: use the ID passed by the
   parent skill if this is a delegated invocation, or derive from the
   plan file slug if standalone (e.g., `FEATURE_PLAN.md` →
   `feature-plan`). Then create the fulfillment file AND the verification
   requirement in the MAIN repo. **The verification requirement must be
   created at entry (here), NOT at Phase 3** — if the agent skips Phase 3
   entirely, the requirement file must already exist so the hook blocks
   any landing until verification is fulfilled.
   ```bash
   MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
   mkdir -p "$MAIN_ROOT/.claude/tracking"
   printf 'skill: run-plan\nid: %s\nplan: %s\nphase: %s\nstatus: started\ndate: %s\n' \
     "$TRACKING_ID" "$PLAN_FILE" "$PHASE" "$(TZ=America/New_York date -Iseconds)" \
     > "$MAIN_ROOT/.claude/tracking/fulfilled.run-plan.$TRACKING_ID"
   # Lock down verification requirement IMMEDIATELY (was Phase 3, now entry)
   printf 'skill: verify-changes\nparent: run-plan\nid: %s\ncreatedAt: %s\n' \
     "$TRACKING_ID" "$(TZ=America/New_York date -Iseconds)" \
     > "$MAIN_ROOT/.claude/tracking/requires.verify-changes.$TRACKING_ID"
   ```

9. **Classify UI impact from the plan text.** Scan the phase description
   for UI indicators: mentions of editor, toolbar, canvas, panel, dialog,
   CSS, button, menu, viewport, renderer, dark mode, layout, or any
   reference to UI/editor/styles directories in the project.
   Flag the phase as **UI-touching** if any are found.

   In `finish` mode, classify ALL phases upfront and report:
   > Running 5 phases. Phases 3 and 5 touch UI — landing will wait for
   > your sign-off at the end.

   This tells the user immediately whether the run will be fully automatic
   or will need their review before landing. No surprises at Phase 6.

9. **Present the phase plan:**
   - Without `auto`: display the phase summary (name, status, dependencies,
     work items, UI classification) and **wait for user approval**
   - With `auto`: proceed immediately

### `finish` mode: overall verification after all phases

In `finish` mode, after ALL phases complete their per-phase implement →
verify loops, run a **final overall verification** before writing the
report and landing:

1. **Dispatch an overall verification agent.** In worktree mode, run
   `/verify-changes worktree` on the full worktree diff. In delegate mode
   (or mixed), run `/verify-changes` on main against the commits from all
   phases combined. This catches cross-phase integration issues: regressions
   from later phases breaking earlier work, conflicting imports, duplicated code.

2. **If ANY phase was classified as UI-touching** (step 7), dispatch a
   **dedicated manual testing agent** that exercises ALL UI changes together
   via playwright-cli. This agent:
   - Tests the combined UI state (not each change in isolation)
   - Takes comprehensive screenshots showing everything working together
   - Prepares the sign-off report so the user can review efficiently
   - Uses `/manual-testing` recipes for selectors and setup

   The goal: instead of "3 items need sign-off, go check yourself," the
   user gets "3 items need sign-off, here are screenshots of all of them
   working together."

3. Proceed to Phase 5 (write report) with the combined verification results.

## Phase 2 — Implement

### Execution mode detection

Check the phase text for an execution mode directive:

- **`### Execution: delegate <skill> [args]`** — delegate mode. The phase
  runs a skill (e.g., `/add-block`, `/run-plan`) that manages its own
  isolation. The orchestrating agent runs on **main**, not in a worktree.
  See "Delegate mode" below.
- **`### Execution: main`** — main mode. The implementation agent runs
  directly on main (no `isolation: "worktree"`). Commits go to main
  immediately. Phase 6 (landing) is skipped because work is already on
  main. Use when the plan or user specifies "work directly on main" or
  "no worktrees" — common for single-user projects, prototyping, or
  when worktree isolation adds complexity without benefit. The plan's
  Design & Constraints section or the user's goal description should
  indicate when this mode is appropriate.
- **`### Execution: worktree`** or **no directive** — default worktree mode.
  See "Worktree mode" below.

### Main mode

The implementation agent runs directly on main. No worktree, no
cherry-pick.

1. **Dispatch agent on main** (no `isolation: "worktree"`). Give the agent
   the verbatim phase text and instruction to commit directly to main.
2. After implementation, proceed to Phase 3 (verify) as normal. The
   verification agent checks the commits on main directly.
3. **Phase 6 (landing) is a no-op** — work is already on main. Skip
   cherry-picking. Still write the report (Phase 5) and update the
   tracker (Phase 4).
4. The chunked transition (Phase 5c) still applies — schedule cron for
   the next phase and exit.

### Delegate mode

The orchestrating agent runs on main and calls the specified skill. The
skill manages its own worktree, verification, and landing.

1. **Dispatch agent on main** (no `isolation: "worktree"`). Give the agent:
   - The verbatim phase text (same rule as worktree mode)
   - Instruction to run the specified skill with the given arguments
   - Instruction to wait for the skill to finish and report the result

2. **Agent timeout: 2 hours.** Same as worktree mode.

3. **After the delegate skill finishes**, /run-plan proceeds to Phase 3
   (verification) which runs on main — checking that the delegated work
   actually landed correctly.

4. **In `finish` mode:** each delegate phase runs independently (no shared
   worktree — the delegate skill creates and destroys its own).

Use cases:
- `### Execution: delegate /add-block DiscreteFilter` — block expansion
- `### Execution: delegate /run-plan plans/SUB_PLAN.md finish auto` — meta-plans
- `### Execution: delegate /draft-plan plans/FOO.md <description>` — plan generation

### Worktree mode (default)

One worktree for the entire phase (not per-item like `/fix-issues`).
**In `finish` mode, reuse the SAME worktree across all phases** — create
it once before the first phase, pass the same path to every phase's agent:

**Agent timeout: 2 hours.** Note the dispatch time. If the implementation
agent hasn't returned after 2 hours, declare it **failed**:
- Mark the phase as "Timed out" in `reports/plan-{slug}.md`
- The phase stays incomplete for the next run
- The worktree is a cleanup artifact — do NOT auto-land late results
- If the agent eventually returns, ignore it. Timed out = failed, period.
- If the plan was drafted with `/draft-plan`, the phase may be too large —
  consider splitting it (each phase should be ~3-5 components, ~500 lines).

1. **Dispatch implementation agent** with `isolation: "worktree"`.
   Tell the agent to write a `.worktreepurpose` file as its first action:
   ```
   echo "<session-name or plan-name>: <phase name>" > .worktreepurpose
   ```
   Example: `echo "SKILLZ: briefing Phase 1" > .worktreepurpose`
   This metadata helps `/briefing worktrees` and `/briefing verify` show
   what each worktree is for, instead of just an opaque agent ID.

2. **Agent prompt MUST include the verbatim plan text.** The implementing
   agent receives the EXACT text of the phase from the plan file — not a
   summary, not bullet points extracted from it, not "implement the mechanical
   domain." The full section with every requirement, formula, constraint,
   design note, and acceptance criterion.

   **The plan is the spec.** If the agent doesn't have the verbatim text,
   it will guess, and it will guess wrong.

   **For plan sections longer than ~100 lines:** write the verbatim text to
   a temp file (e.g., `/tmp/phase-text.md`) and tell the agent to `Read`
   the file. This avoids the natural LLM tendency to compress long text
   when inlining it in a prompt. Shorter sections can be inlined directly.

3. **If dispatching sub-agents for parallel work items**, each sub-agent gets:
   - The **full phase context** (verbatim) — so they understand the big picture
   - Their **specific scope** clearly delineated — e.g., "you are implementing
     Mass, Spring, Damper. Another agent is implementing sensors and force
     source."
   - **What parallel agents are doing** — enough to avoid conflicts (shared
     files, shared infrastructure) but not so much detail that it confuses
     their scope. Format: "Another agent is handling: [list of items]. You
     should not modify [shared files] until that work lands."
   - **Shared infrastructure dependencies** — if a base class or domain
     definition must exist first, that must be built sequentially before
     dispatching parallel agents. Never dispatch parallel agents that both
     need to create the same file.

4. **Within-phase parallelism is the agent's judgment call** — if items are
   independent (e.g., Mass, Spring, Damper components), the agent may dispatch
   sub-agents. If there's shared infrastructure to build first, it works
   sequentially then parallelizes. The skill does NOT force parallelism.

5. **Commit discipline:**
   - One logical unit per commit — clean git history
   - `npm run test:all` before every commit — not just `npm test`
   - Tests alongside implementation, not deferred to later
   - Agents commit freely in worktrees — that's the point of isolation
   - **Rebase onto current main before final commit:**
     ```bash
     git fetch origin main && git rebase origin/main
     ```
     This ensures the commit contains only the agent's changes, not stale
     copies of files other agents already fixed on main. If rebase
     conflicts, abort (`git rebase --abort`) and proceed — the cherry-pick
     verification will catch stale files via selective extraction.

6. **Running tests in worktrees — CRITICAL.** Agents waste hours getting
   tests working in worktrees without these instructions. Include this
   VERBATIM in every implementation and verification agent prompt:

   > **Worktree test recipe:**
   > 1. Start a dev server FIRST: `npm start &`
   > 2. Wait for it: `sleep 3`
   > 3. Run tests with output captured to a file:
   >    `npm run test:all > .test-results.txt 2>&1`
   >    **Never pipe** through `| tail`, `| head`, `| grep` — it loses
   >    output and forces re-runs. Capture once, read the file.
   > 4. The dev server must stay running for E2E tests. If source files
   >    changed (they will have — you're implementing), E2E tests FAIL
   >    (not skip) without a dev server.
   > 5. If tests fail, **read `.test-results.txt`** to find the failures.
   >    Then run ONLY the failing test file to iterate on the fix:
   >    `node --test tests/the-failing-file.test.js`
   >    Do NOT re-run `npm run test:all` to diagnose — that wastes 5
   >    minutes when the single file takes 30 seconds.
   > 6. After fixing, run the single file again to confirm. Then run
   >    `npm run test:all > .test-results.txt 2>&1` ONE more time as
   >    the final gate before committing.
   > 7. Max 2 fix attempts at the same error — do not thrash.
   > 8. If a test fails in code you didn't touch, it may be pre-existing.
   >    See `/verify-changes` Phase 3 for the pre-existing failure protocol.

7. **No steps skipped or deferred.** If the plan says "implement 7 components,"
   implement 7 components. If it says "write tests for free vibration," write
   those exact tests. Do not stop after the easy items and declare the hard
   ones "future work."

### Post-implementation tracking

After the implementation agent finishes (whether worktree or delegate mode),
create the implementation step marker:
```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
printf 'phase: %s\ncompleted: %s\n' "$PHASE" "$(TZ=America/New_York date -Iseconds)" \
  > "$MAIN_ROOT/.claude/tracking/step.run-plan.$TRACKING_ID.implement"
```

### Pre-verification (requirement already created at entry)

The `requires.verify-changes.$TRACKING_ID` marker was already created in
Phase 1 step 8 (Create tracking fulfillment marker AND lock down
verification requirement). The hook is enforcing that this requirement
must be fulfilled before any landing. You don't need to re-create it
here.

Pass the tracking ID to the verification agent in the dispatch prompt so
it can create its own fulfillment marker:
> Your tracking ID is `$TRACKING_ID`. On entry, create
> `fulfilled.verify-changes.$TRACKING_ID` in the main repo's
> `.claude/tracking/` directory.

## Phase 3 — Verify (separate agent)

Critical: the verification agent is NOT the implementing agent. Fresh eyes
catch implementer blindspots — deferred hard parts, missing tests, stubs,
shortcuts.

### Dispatch protocol

**Check your tool list.** If `Agent` (or `Task`) is in your tool list,
you are at top level — dispatch a fresh verification subagent per the
protocol below. The implementation subagent (in its worktree) and the
verification subagent are sibling subagents of you, the top-level
orchestrator. The verifier has independent context from the implementer.

**If you do NOT have the `Agent` tool**, you are running as a subagent
yourself (Claude Code subagents have no Agent tool, by Anthropic's
design at https://code.claude.com/docs/en/sub-agents). Run `/verify-changes
worktree` inline in your current context — the verifier subagent (you)
is fresh relative to the implementer subagent that ran in a separate
context. After Change 1's chunking is in place, /run-plan runs as
cron-fired top-level turns and Phase 3 is at top level, so this fallback
is mostly defensive.

**Agent timeout: 45 minutes.** Verification should take 15-30 minutes —
reading diffs, running tests, checking acceptance criteria. If a verification
agent hasn't returned after 45 minutes, it is thrashing (likely on test
setup or repeated test failures). Declare it **failed** and invoke the
Failure Protocol. Do NOT let verification agents run indefinitely — they
are the most common source of time waste.

### Delegate mode verification

If this phase used delegate execution, verification runs on **main**:

1. **Verify commits landed** — check `git log --oneline -10` for the
   delegate's commits. If expected commits are missing, the delegate
   failed to land — invoke Failure Protocol.
2. **Run `npm run test:all` on main** — the delegate already tested, but
   /run-plan verifies against the plan's acceptance criteria.
3. **Check acceptance criteria** from the verbatim plan text — the delegate
   skill doesn't know the plan's criteria, only /run-plan does.
4. Dispatch a verification agent if needed (same rules as worktree mode
   below, but targeting main instead of a worktree path).

### Worktree mode verification

1. **Dispatch verification agent** targeting the worktree's changes. The
   verification agent is dispatched **without** `isolation: "worktree"` — the
   Agent tool's `isolation` parameter creates a NEW worktree, it cannot attach
   to an existing one. Instead, give the verification agent:
   - The **worktree path** from Phase 2 (so it can read files and run tests
     there via `cd <worktree-path> && npm run test:all`)
   - The **worktree branch name** (so it can diff against main:
     `git diff main...<branch>`)
   - The **verbatim phase text** from the plan (same text the implementer got)
   - Instruction to run `/verify-changes worktree` — the verification agent
     runs this, NOT you. Do NOT run verification yourself — you are the
     orchestrator with implementer bias.
   - The **work items checklist** — verify each item was actually implemented,
     not stubbed or skipped

2. **Additional plan-specific checks** (the verifier checks these against the
   verbatim plan text — not against a summary):
   - Do commits cover ALL work items listed in the plan? Any missing?
   - Does implementation follow the plan's stated approach? (e.g., "use
     internal displacement state for Spring" — did it actually do that?)
   - Are constraints respected? (no external solvers, etc.)
   - Any deferred hard parts, stubs, TODOs, or placeholder implementations?
   - Do acceptance criteria match? (e.g., "test free vibration x(t) = A cos(wt)"
     — does that exact test exist with that exact formula?)

   **"Noted as gap" is a verification FAILURE.** If any work item, acceptance
   criterion, or checklist item was skipped and merely noted — that is not a
   pass. It is a fail. The verifier must not rationalize skipped steps as
   "not blockers" or "gaps for future work." If the plan says to do it and
   it wasn't done, verification fails. Period.

   Past failure: Block Expansion Plan Phase 1 — the implementer skipped the
   example model (Step 7 of `/add-block`) and runtime entry (Step 10). The
   verifier saw both skips but wrote "gaps noted" instead of invoking the
   Failure Protocol. The phase was reported as complete with missing work.

3. **If verification fails:**
   - Without `auto`: present findings, ask user what to do
   - With `auto`: dispatch a **fresh fix agent** for the missing items.
     The fix agent receives: the worktree path, the verbatim plan text,
     the specific items that failed verification, and instructions to
     complete them — not summarize them, not note them, COMPLETE them.
     If the missing item is an example model, the fix agent calls
     `/add-example`. If it's a runtime entry, the fix agent adds it.
     The fix agent is NOT the implementer — it's a fresh agent with no
     bias toward "this is good enough."

     After the fix agent finishes, re-verify (max 2 rounds). If still
     failing after 2 fix+verify cycles, **STOP** — needs human judgment.
     Invoke the Failure Protocol.

### Post-verification tracking

After verification passes, create the verification step marker:
```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
printf 'phase: %s\nresult: pass\ncompleted: %s\n' "$PHASE" "$(TZ=America/New_York date -Iseconds)" \
  > "$MAIN_ROOT/.claude/tracking/step.run-plan.$TRACKING_ID.verify"
```

## Phase 4 — Update Progress Tracking

After verification passes. **These updates happen on MAIN, not in the
worktree.** The plan file tracks progress across all phases — it's an
orchestrator concern, not an implementation artifact. Updating it on main
ensures the next cron invocation sees the correct phase status and advances
to the next incomplete phase (preventing infinite loops).

1. **Update the plan file's progress tracker on main** — change the phase
   status to Done with the commit hash (from worktree branch or delegate's
   landed commits) and notes. Examples
   by format:
   - Table: `| **4b: Mechanical** | ✅ Done | \`abc1234\` | 7 components, 45 tests |`
   - Checklist: `- [x] Phase 4b — Mechanical Domain (abc1234, 7 components)`
   - Section: add `**Status:** ✅ Done (abc1234)` to the section header

2. **Update companion progress doc on main** if one exists — add
   implementation details, architecture notes, lessons learned

3. **If no tracker exists:**
   - Interactive mode: suggest adding one to the plan file, ask user
   - Auto mode: note in the report that no tracker was updated

4. **Mark the phase as "In Progress" and commit:**
   ```bash
   git add <plan-file> [companion-doc]
   git commit -m "chore: mark phase <name> in progress"
   ```
   Mark as 🟡 In Progress (not ✅ Done yet). Committing immediately
   ensures the next cron invocation sees the phase is being worked on
   (preventing re-runs). Phase 6 updates the tracker to ✅ Done AFTER
   landing succeeds. If landing fails, the tracker correctly says
   "In Progress" — the phase was attempted but not landed.

## Phase 5 — Write Report

**PREPEND** new phase sections after the H1 in `reports/plan-{slug}.md`
(`{slug}` from plan filename, e.g., `FEATURE_PLAN.md` → `plan-physics module`).
Newest phase at the top — the reader's question is "what needs my
attention?" and that's always the newest phase.

If the file doesn't exist, create it with a `# Plan Report — {plan name}`
heading. Never overwrite the file — each phase adds a section.

After writing, regenerate `PLAN_REPORT.md` in the repo root as an **index**
of all plan reports:
1. Scan `reports/plan-*.md` files
2. For each: extract plan name, phase count, overall status, unchecked `[ ]`
3. Write index with Needs Sign-off section (linked items) + Plans table
4. Staleness rule: items >7 days flagged STALE

**Report format** — each phase gets one `## Phase` section:

```markdown
## Phase — 4b Translational Mechanical Domain [UNFINALIZED]

**Plan:** plans/FEATURE_PLAN.md
**Status:** Completed (verified)
**Worktree:** ../plan-physics module-4b
**Commits:** abc1234, def5678

### Work Items
| # | Item | Status | Commit |
|---|------|--------|--------|
| 1 | Mass component | Done | abc1234 |
| 2 | Spring component | Done | def5678 |

### Verification
- Test suite: PASSED (4342 tests)
- Acceptance criteria: all met

### User Sign-off
{Only if UI files changed. Omit entirely for non-UI phases.}

**Dev server URL:** `http://localhost:PORT/` — The agent MUST start a dev
server (if one isn't running) and include the URL with the actual port
number. Use `bash scripts/port.sh` to get the deterministic port for the
current worktree or main repo. If working in a worktree, the port differs
from main — include the worktree-specific port. The user needs to be able
to click this URL and immediately see the running app.

- [ ] **P4b-1** — Variable viewer panel
  **URL:** http://localhost:30815/
  1. Open the app at the URL above
  2. Load a physics module model (e.g., voltage-divider example)
  3. Run the simulation
  4. Click the lightning icon in the toolstrip
  5. Verify the Physical Variables panel opens with columns for V, I, P
  6. Check that values update after simulation completes
  ![viewer panel](.playwright/output/phase4b-variable-viewer.png)

- [ ] **P4b-2** — Toolstrip button
  **URL:** http://localhost:30815/
  1. Verify the lightning icon appears in the toolstrip
  2. Click it — panel should toggle open/closed
```

**Report format rules:**
- **One checkbox per item.** Do NOT use a summary table with `[ ]` AND a
  detail section with `[ ]` — the viewer counts both as separate checkboxes.
  Use only the checklist format above.
- **Phase-prefixed IDs** — `P4b-1`, `P2-3`, not `#1`, `#2` (which reset
  per phase and collide).
- **Include verification instructions** under each checkbox — numbered
  steps, screenshots. The reviewer needs to know what to do, not just
  what to check off.
- **One item per verifiable thing** — "3 check blocks in Block Explorer"
  is wrong. Each block gets its own checkbox.
- **Avoid literal `[ ]` in description text** — the viewer renders it as
  a phantom checkbox. Describe instead: "bracket pair" or use backtick
  escaping.

### Post-report tracking

After writing the report and regenerating the index, create the report step marker:
```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
printf 'phase: %s\ncompleted: %s\n' "$PHASE" "$(TZ=America/New_York date -Iseconds)" \
  > "$MAIN_ROOT/.claude/tracking/step.run-plan.$TRACKING_ID.report"
```

## Phase 5b — Plan Completion

Triggers when ALL phases are done: either the last phase just finished
(single-phase run where it was the only remaining phase), or in `finish`
mode after all phases complete. Run this BEFORE Phase 6 (Land).

### 1. Audit phase compliance

Before declaring the plan complete, verify every phase has a clean status:

1. **Check completion indicators** — every phase must have one of: Done,
   a commit hash, ✅, `[x]`. If any phase lacks a completion indicator,
   WARN (do not hard-block):
   > Phase 3 has no completion indicator — review before closing.

2. **Scan for unresolved gaps** — check each phase's status line AND its
   corresponding section in `reports/plan-{slug}.md` for any of these
   phrases (case-insensitive): "noted as gap", "deferred", "skipped",
   "future work". If found, WARN (do not hard-block):
   > Phase 3 has unresolved gaps — review before closing.

   List all flagged phases together so the user can review in one pass.

3. If running with `auto` and warnings were emitted, log them in the
   report but continue — these are advisory, not blocking.

### 2. Close linked issue (if any)

If the plan file has YAML frontmatter with an `issue:` field (e.g.,
`issue: 42` or `issue: "#42"`):

1. **Check issue state:**
   ```bash
   gh issue view <N> --json state --jq '.state'
   ```

2. **If open:** close it with a summary comment listing key commits and
   what was accomplished:
   ```bash
   gh issue close <N> --comment "Resolved via plan execution.

   Plan: <plan-file>
   Key commits: <comma-separated list of commit hashes from all phases>
   Phases completed: <count>

   All phases passed verification. See reports/plan-{slug}.md for details."
   ```

3. **If already closed:** no action needed — log "Issue #N already closed."

4. **If no `issue:` field:** skip this step entirely.

### 3. Update plan frontmatter

Change `status: active` (or `status: in-progress`) to `status: complete`
in the plan file's YAML frontmatter. If the plan has no `status:` field,
add one: `status: complete`. Commit the change:
```bash
git add <plan-file>
git commit -m "chore: mark plan complete — <plan-name>"
```

### 4. Update SPRINT_REPORT.md

Check if `SPRINT_REPORT.md` exists in the repo root. If it does:

1. Search for the closed issue number (from step 2) or the plan filename
   in a "Skipped" section (look for headers or list items containing
   "Skipped", "Too Complex", "Deferred", or "Punted").

2. If found, append a note to that entry:
   > Resolved via /run-plan (plan: <plan-file>)

3. If `SPRINT_REPORT.md` does not exist, or the issue/plan is not
   mentioned in a skipped section, skip this step.

## Phase 5c — Chunked finish auto transition (CRITICAL for finish auto mode)

**This section applies when running `/run-plan <plan> finish auto`.**

In chunked finish auto mode, each plan phase runs as a separate top-level
cron-fired turn. The current turn does NOT loop back to process the next
phase — instead, it lands the current phase, schedules a one-shot cron for
the next phase (or the next meta-plan phase, or the final cross-branch
verification, depending on context), and exits cleanly.

### Why chunked execution

The original failure mode was: a single long-running session built up
late-phase fatigue and rationalized skipping verification on the last few
phases. Chunked execution breaks the run into a sequence of fresh
top-level turns, each handling exactly one plan phase. Each fresh turn
re-reads the plan, the tracking state, and its own instructions. There
is no momentum to skip steps because each turn starts clean.

A secondary benefit: cron-fired turns run at top level (in the user's
main session, with full `Agent`/`Task` tool access). This means
implementation, verification, and reporting subagent dispatches all work
correctly. Sub-sub-agent dispatch is not needed because there is no
nesting — every cron fire is a fresh top-level turn.

### Idempotent re-entry (every cron-fired turn does this first)

At the very start of every `/run-plan` invocation in `finish auto` mode,
read the plan tracker and check the next-target phase. If it's already
marked Done OR In Progress, **exit cleanly** with a "no work to do"
message. This handles two cases:

1. A stale cron from a previous run fires after the user manually
   re-invoked the next phase. The cron sees the work is already done
   and exits without duplication.
2. A previous turn already started this phase (e.g., is mid-cherry-pick).
   The new turn defers and exits.

Output for the no-work-to-do case:
> /run-plan plans/X.md: phase N is already Done/In Progress. Skipping
> this cron fire (likely a stale cron). The pipeline is still proceeding
> via its actual current phase.

### When this turn schedules the next cron

After Phase 6 (land) succeeds for the current phase:

1. Check if there is a NEXT incomplete phase in this plan:
   - If YES: schedule a cron to fire `/run-plan <plan-file> finish auto`
     ~1 minute from now. The next cron-fired turn will pick up the next
     phase. Then exit this turn.
   - If NO (this was the last phase): check if this plan is part of a
     larger meta-plan or research-and-go pipeline (see below).

2. **If this plan is being executed as a delegate phase of a meta-plan**
   (you can detect this by the existence of a parent meta-plan that
   references this sub-plan): after the last phase of this sub-plan
   lands, schedule a cron to fire `/run-plan <META_PLAN_PATH> finish auto`
   ~1 minute from now. The next cron-fired turn will resume the meta-plan
   from its next incomplete delegate phase. Then exit.

3. **If this is the meta-plan itself** and all sub-plans are done:
   check for the existence of `requires.verify-changes.final` in the
   tracking dir (this marker is created by `/research-and-go` Step 0).
   - If it exists: this is part of a `/research-and-go` pipeline. Schedule
     a cron to fire `/verify-changes branch` ~1 minute from now. The
     final cross-branch verification will run at top level (full Agent
     tool) and create `fulfilled.verify-changes.final`. Then exit.
   - If it does not exist: this is a standalone meta-plan run. The
     pipeline is complete. Update plan frontmatter `status: complete`,
     report success, exit. No more crons.

4. **If this is a standalone leaf plan** (not part of a meta-plan, not
   part of research-and-go) and the last phase landed: update plan
   frontmatter `status: complete`, report success, exit. No more crons.

### How to schedule the next cron

```bash
# Compute target minute that's NOT :00 or :30 (to avoid scheduler jitter)
NOW_MIN=$(date +%M)
NOW_HOUR=$(date +%H)
NOW_DAY=$(date +%d)
NOW_MONTH=$(date +%m)
TARGET_MIN=$(( (10#$NOW_MIN + 1) % 60 ))
if [ "$TARGET_MIN" -eq 0 ] || [ "$TARGET_MIN" -eq 30 ]; then
  TARGET_MIN=$(( TARGET_MIN + 1 ))
fi
TARGET_HOUR=$NOW_HOUR
if [ "$TARGET_MIN" -lt "$NOW_MIN" ]; then
  TARGET_HOUR=$(( (10#$NOW_HOUR + 1) % 24 ))
fi
```

Then call `CronCreate`:
- `cron`: `"$TARGET_MIN $TARGET_HOUR $NOW_DAY $NOW_MONTH *"`
- `recurring`: false
- `prompt`: the next-step prompt — typically `"Run /run-plan <plan-file> finish auto"`, or `"Run /run-plan <meta-plan-path> finish auto"`, or `"Run /verify-changes branch"`

After scheduling, output the chunking message:
> Phase <N> of `<plan>` complete (commit `<hash>`).
> Phase <N+1> will fire automatically in ~1-2 minutes (cron `<job-id>`).
> To stop the pipeline: `/run-plan stop`
> To check status: `/run-plan <plan> status`

Then **exit this turn**. Do NOT do any other work. Do NOT loop back to
process the next phase inline. The cron handles it.

### Cron-scheduling rule (avoid confusion)

**Only top-level orchestrators (this `/run-plan` running as a cron-fired
top-level turn) call `CronCreate`.** Sub-agents (the implementer in the
worktree, the verifier subagent dispatched by Phase 3) do NOT schedule
crons. They do their work synchronously and return control to this top-
level orchestrator. This ensures at most one pending chunking cron per
pipeline at any time.

### Single-phase mode (no chunking)

When invoked WITHOUT `finish auto` (e.g., `/run-plan plans/X.md` or
`/run-plan plans/X.md 4b`), do NOT chunk. Run the single specified phase
to completion in this turn, then exit normally. Chunking is exclusively
for `finish auto` mode.

## Phase 6 — Land

### Delegate mode landing

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

### Pre-landing checklist (worktree mode only)

Before ANY cherry-pick to main, verify ALL of these. If any fails, STOP.

1. `ls reports/plan-{slug}.md` — report file exists (Phase 5 ran)
2. Report has a `## Phase` section for every completed phase
3. In `finish` mode: cross-phase `/verify-changes worktree` returned clean
4. If UI-touching phases: playwright-cli agent ran and produced screenshots
5. If UI-touching phases: report has `### User Verification` with `[ ]` items

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

  **In `finish auto` mode (chunked):** each phase runs as a separate
  cron-fired turn (see Phase 5c). When a phase has User Verify items,
  schedule the next-phase cron BUT also output the User Verify items in
  the report. The user reviews them between cron fires and runs
  `/run-plan stop` if they want to halt. Landing happens per-phase as
  each phase's cron-fired turn completes — the worktree accumulates
  changes only within a single phase, not across phases.

- **With `auto` and NO User Verify items:** Auto-land verified phase
  commits to main. **In chunked finish auto mode**, this is per-phase
  landing — each cron-fired turn lands its own phase before scheduling
  the next chunking cron. There is no "wait until all phases done" gate
  in chunked mode; per-phase landing IS the new model.

  Auto-land steps:
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

  5. **Extract logs and mark worktree as landed:**
     a. Copy unique session logs from worktree to main's `.claude/logs/`
     b. Write `.landed` marker (atomic: `.tmp` → `mv`):
        ```bash
        cat > "<worktree-path>/.landed.tmp" <<LANDED
        status: full
        date: $(TZ=America/New_York date -Iseconds)
        source: run-plan
        phase: <phase name>
        commits: <list of cherry-picked hashes>
        LANDED
        mv "<worktree-path>/.landed.tmp" "<worktree-path>/.landed"
        ```
  6. **Commit extracted logs:**
     ```bash
     git add .claude/logs/
     git commit -m "chore: session logs from run-plan phase"
     ```
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
  11. **Auto-remove worktree** after successful landing:
      ```bash
      # Extract any remaining logs
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
        echo "Worktree not auto-removed: uncommitted work found"
      fi
      ```
      If removal fails for any reason, leave the worktree — it has
      `.landed` and `/briefing worktrees` will classify it as safe.

### Post-landing tracking

After successful landing (cherry-pick + tests pass), create the land step
marker and update the fulfillment file:
```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
printf 'phase: %s\ncompleted: %s\n' "$PHASE" "$(TZ=America/New_York date -Iseconds)" \
  > "$MAIN_ROOT/.claude/tracking/step.run-plan.$TRACKING_ID.land"

printf 'skill: run-plan\nid: %s\nplan: %s\nphase: %s\nstatus: complete\ndate: %s\n' \
  "$TRACKING_ID" "$PLAN_FILE" "$PHASE" "$(TZ=America/New_York date -Iseconds)" \
  > "$MAIN_ROOT/.claude/tracking/fulfilled.run-plan.$TRACKING_ID"
```

In `finish` mode, per-phase markers use the `phasestep` prefix (the hook
ignores these — they are informational only):
```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
printf 'phase: %s\ncompleted: %s\n' "$PHASE" "$(TZ=America/New_York date -Iseconds)" \
  > "$MAIN_ROOT/.claude/tracking/phasestep.run-plan.$TRACKING_ID.$PHASE.implement"
```
After the cross-phase verification in `finish` mode completes, aggregate
with `step.*` markers:
```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
for stage in implement verify report land; do
  printf 'phases: all\ncompleted: %s\n' "$(TZ=America/New_York date -Iseconds)" \
    > "$MAIN_ROOT/.claude/tracking/step.run-plan.$TRACKING_ID.$stage"
done
```

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

## Key Rules

- **"Noted as gap" is a FAILURE, not a pass.** If the implementer skips
  a work item and the verifier writes "gaps noted" or "not a blocker" —
  that is a verification failure. Dispatch a fix agent for the missing
  items. Do not advance to Phase 4. Do not write "gaps noted" in reports.
  Past failure: Block Expansion Phase 1 skipped example model + runtime
  entry; verifier accepted both skips instead of invoking Failure Protocol.
- **Never weaken tests** — fix the code, not the test. Do not loosen
  tolerances, skip assertions, or remove test cases.
- **Honest status reporting** — if the user asks "are you stuck?", answer
  with DATA: (1) current phase and when it started, (2) agent duration and
  tool call count, (3) errors or retries. Do not say "everything is fine"
  if an agent has been running >30 minutes or retried 2+ times.

## Edge Cases

- **No progress tracker:** LLM reads plan sections + checks codebase for
  evidence of completion (files exist, tests pass, git log mentions the phase)
- **Phase fails verification:** auto mode tries one fix cycle (dispatch fix
  agent + re-verify), then stops after 2 total cycles
- **All phases complete:** report "Plan complete", delete cron if scheduled
- **Dependency not met:** stop cleanly, report which dependency. If `every`,
  the cron retries on next invocation (the dependency may be completed by then)
- **Phase "In Progress":** another agent may be working — stop, don't compete.
  Report the conflict.
- **Existing worktree for phase:** previous incomplete run — ask user
  (interactive) or try to resume from the existing worktree (auto)
- **Implementation produces no commits:** the agent worked but committed
  nothing. Report in `reports/plan-{slug}.md` as "No commits produced — investigate
  worktree." Do not attempt to cherry-pick nothing. In auto mode, invoke
  the Failure Protocol (this is an unrecoverable state for cron)
- **Plan file not found:** stop immediately, report the error
- **Phase arg doesn't match any phase:** stop, list available phases
