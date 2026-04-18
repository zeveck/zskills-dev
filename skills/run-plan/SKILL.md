---
name: run-plan
disable-model-invocation: false
argument-hint: "<plan-file> [phase|finish|status] [auto] [pr|direct] [every SCHEDULE] [now] | stop | next"
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
/run-plan <plan-file> [phase] [auto] [pr|direct] [every SCHEDULE] [now]
/run-plan stop | next
```

- **plan-file** (required) — path to plan, e.g. `plans/FEATURE_PLAN.md`
- **phase** (optional) — specific phase, e.g. `4a`. If omitted, auto-detect
  next incomplete phase
- **finish** (optional) — run ALL remaining phases sequentially until the
  plan is complete. `finish` is approval to START — do not ask for
  confirmation before the first phase (the user already said "finish").
  Without `auto`: pauses BETWEEN phases to show results and ask "continue
  to next phase?" With `auto`: each phase runs as its own cron-fired
  top-level turn (~5 min between phases via one-shot crons scheduled by
  Phase 5c). The first phase runs immediately; each subsequent phase is
  scheduled after the prior phase lands. Preserves fresh context per
  phase — no late-phase fatigue.
  Each phase still gets full verification, testing, and all safety rails.
  If any phase fails verification or hits a conflict, stops there.
  **`finish` and `every` are mutually exclusive.** `finish auto` schedules
  its own ~5-min one-shot crons internally. `every N` schedules a recurring
  cron at user-set cadence. Combining them would produce two overlapping
  cron schedules. Use one or the other.
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
- `pr` (case-insensitive) — PR landing mode
- `direct` (case-insensitive) — direct landing mode
- Neither `pr` nor `direct` — read config default (`execution.landing`),
  or `cherry-pick` if no config

**Landing mode resolution:**
1. Explicit argument wins: `pr` or `direct` in $ARGUMENTS
2. Config default: read `.claude/zskills-config.json` `execution.landing` field
3. Fallback: `cherry-pick`

```bash
# Detect landing mode
LANDING_MODE="cherry-pick"  # default
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[pP][rR]($|[[:space:]]) ]]; then
  LANDING_MODE="pr"
elif [[ "$ARGUMENTS" =~ (^|[[:space:]])[dD][iI][rR][eE][cC][tT]($|[[:space:]]) ]]; then
  LANDING_MODE="direct"
else
  # Read config default
  CONFIG_FILE="$PROJECT_ROOT/.claude/zskills-config.json"
  if [ -f "$CONFIG_FILE" ]; then
    CONFIG_CONTENT=$(cat "$CONFIG_FILE")
    if [[ "$CONFIG_CONTENT" =~ \"landing\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
      CFG_LANDING="${BASH_REMATCH[1]}"
      if [ -n "$CFG_LANDING" ]; then
        LANDING_MODE="$CFG_LANDING"
      fi
    fi
  fi
fi
```

**Validation:**

```bash
# direct + main_protected -> error
if [[ "$LANDING_MODE" == "direct" ]]; then
  CONFIG_FILE="$PROJECT_ROOT/.claude/zskills-config.json"
  if [ -f "$CONFIG_FILE" ]; then
    CONFIG_CONTENT=$(cat "$CONFIG_FILE")
    if [[ "$CONFIG_CONTENT" =~ \"main_protected\"[[:space:]]*:[[:space:]]*true ]]; then
      echo "ERROR: direct mode is incompatible with main_protected: true. Use pr mode or change config."
      exit 1
    fi
  fi
fi
```

**Reading branch_prefix from config:**

```bash
# Read branch prefix from config (default: feat/)
BRANCH_PREFIX="feat/"
if [ -f "$PROJECT_ROOT/.claude/zskills-config.json" ]; then
  CONFIG_CONTENT=$(cat "$PROJECT_ROOT/.claude/zskills-config.json")
  # ([^\"]*) allows empty string match -- empty prefix means no prefix
  if [[ "$CONFIG_CONTENT" =~ \"branch_prefix\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    BRANCH_PREFIX="${BASH_REMATCH[1]}"
  fi
fi
```

**Strip `pr`/`direct` from arguments** before passing to downstream processing
(same pattern as stripping `auto`, `finish`, etc.).

Examples:
- `/run-plan plans/FEATURE_PLAN.md` — interactive, next phase
- `/run-plan plans/FEATURE_PLAN.md 4b` — interactive, specific phase
- `/run-plan plans/FEATURE_PLAN.md finish` — interactive, all remaining phases (pauses between each)
- `/run-plan plans/FEATURE_PLAN.md finish auto` — autonomous, all remaining phases (chunked, one phase per cron turn)
- `/run-plan plans/FEATURE_PLAN.md auto every 4h` — schedule every 4h
- `/run-plan plans/FEATURE_PLAN.md auto every 4h now` — schedule + run now
- `/run-plan plans/FEATURE_PLAN.md finish auto pr` — autonomous, all phases, PR landing
- `/run-plan plans/FEATURE_PLAN.md direct` — direct mode, work on main
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
   a previous turn. Re-emit the pipeline ID first (cron-fired turns are
   fresh sessions):
   ```bash
   TRACKING_ID=$(basename "$PLAN_FILE" .md | tr '[:upper:]_' '[:lower:]-')
   echo "ZSKILLS_PIPELINE_ID=run-plan.$TRACKING_ID"
   ```

   Then read the plan frontmatter (`status` field) and the plan tracker
   (phase statuses). Four cases:

   1. **Frontmatter `status: complete`**: plan truly done. Exit with
      "Plan complete (already)." No more work, no more crons.
   2. **All phases Done + frontmatter NOT complete**: Phase 5b needs to
      run (it owns the final-verify gate logic via its new first
      sub-step). Skip Phase 1 sub-steps 1–9 and Phases 2–5; **route
      directly to Phase 5b**. Phase 5b's gate handles the
      verify-pending vs verify-fulfilled vs no-marker cases — single
      source of truth, no duplicated logic in Step 0.
   3. **Next-target phase already In Progress** (per tracker): output
      "Phase X already in progress, deferring." Exit cleanly.
   4. **Otherwise**: proceed with normal preflight (steps 1–9) then
      Phase 2.

   Stale crons are harmless — duplicate fires exit cleanly via this
   check. Re-entry routes to Phase 5b which owns verify-pending state
   and self-rescheduling.

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
   This gate is an **early-exit mirror** of the hook's own commit-block:
   when `FULL_TEST_CMD` has unreplaced placeholders AND test infrastructure
   exists, the hook will block the eventual `git commit` with *"Test
   infrastructure detected but FULL_TEST_CMD not configured"* — so
   catching it at preflight just prevents wasted work. Its job is to
   notice when a project *has* test infrastructure but the hook doesn't
   yet know about it.

   Three cases, report each explicitly so the reasoning is legible:

   - **Placeholders found AND test infra exists** — where test infra means
     any of: `package.json` with a `"test"` script, `vitest.config.*`,
     `jest.config.*`, `pytest.ini`, `.mocharc.*`, or `Makefile` (this list
     must match `block-unsafe-project.sh:134-147` exactly, otherwise
     preflight under-reports and the hook still blocks at commit time):
     **STOP.** Hook placeholders have not been configured — run
     `/update-zskills` first, or (if this plan's purpose is to configure
     them) have the plan land those changes in an early phase before real
     enforcement matters. Report: *"hook-placeholder gate tripped:
     placeholders present AND test infra detected — stopping."*
   - **Placeholders found, no test infra**: gate silent, proceed. This is
     either a fresh/bootstrap project or one with no tests by design. If
     the plan establishes tests, **it should also fill the hook
     placeholders** (`UNIT_TEST_CMD`, `FULL_TEST_CMD`, and
     `UI_FILE_PATTERNS` in `.claude/hooks/block-unsafe-project.sh`) in the
     same phase, so subsequent runs have real enforcement. Report: *"gate
     silent: placeholders present but no test infra yet — bootstrap or
     tests-by-design; if this plan adds tests, also fill the hook
     placeholders."*
   - **No placeholders**: hook is configured, nothing to do. Report:
     *"hook configured; gate n/a."*

5. **Clean up landed worktrees from previous phases**
   ```bash
   for wt_line in $(git worktree list --porcelain | grep '^worktree ' | sed 's/^worktree //'); do
     if [ -f "$wt_line/.landed" ] && grep -q 'status: landed' "$wt_line/.landed"; then
       echo "Cleaning up landed worktree: $wt_line"
       bash scripts/land-phase.sh "$wt_line"
     fi
   done
   ```
   This catches stragglers from crashed agents, container restarts, or any
   remaining edge cases. Defense in depth — `scripts/land-phase.sh` is the
   primary fix (called after each phase landing), the preflight is the safety net.

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
   - If ALL phases complete:
     - If frontmatter `status: complete`: report "Plan complete" → stop.
       If `every`, delete the cron via `CronList` + `CronDelete`.
     - If frontmatter NOT complete: route to Phase 5b directly (Phase 5b's
       gate handles final-verify deferral; if final-verify is satisfied or
       not required, Phase 5b completes the plan).
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

8. **Create tracking fulfillment marker.** Determine the tracking ID: use
   the ID passed by the parent skill if this is a delegated invocation, or
   derive from the plan file slug if standalone (e.g., `FEATURE_PLAN.md` →
   `feature-plan`). Then create the fulfillment file in the MAIN repo:
   ```bash
   MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
   PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
   mkdir -p "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
   printf 'skill: run-plan\nid: %s\nplan: %s\nphase: %s\nstatus: started\ndate: %s\n' \
     "$TRACKING_ID" "$PLAN_FILE" "$PHASE" "$(TZ=America/New_York date -Iseconds)" \
     > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/fulfilled.run-plan.$TRACKING_ID"

   # Lock down verification requirement IMMEDIATELY (was Phase 2,
   # now skill entry — ensures hook blocks landing even if Phase
   # 2/3 are skipped via error path). Delegation: verify-changes is
   # a child of run-plan in this pipeline, so its `requires.*` marker
   # lives in run-plan's OWN subdir (parent reconciles fulfillment).
   printf 'skill: verify-changes\nparent: run-plan\nid: %s\ndate: %s\n' \
     "$TRACKING_ID" "$(TZ=America/New_York date -Iseconds)" \
     > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/requires.verify-changes.$TRACKING_ID"
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
- **`### Execution: worktree`** or **no directive** — default worktree mode.
  See "Worktree mode" below.
- **`### Execution: direct`** — direct mode. No worktree — agent works
  directly on main. Phase 6 is a no-op (work is already on main). Only
  valid when `LANDING_MODE` is `direct` (validated in argument detection).
  See "Direct mode" below.

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

### Direct mode

When `LANDING_MODE` is `direct`:
- Do NOT create a worktree
- Agent works directly on main (current working directory)
- `### Execution: direct` in phase text is the recognized directive
- Phase 6: no-op (work is already on main, nothing to land)
- `.landed` marker: not written (no worktree to mark)

**Validation (already checked in argument detection):** `direct` + `main_protected: true` -> error before dispatch.

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

1. **Create worktree manually at `/tmp/` path** (do NOT use `isolation: "worktree"`):
   ```bash
   PLAN_SLUG=$(basename "$PLAN_FILE" .md | tr '[:upper:]' '[:lower:]' | tr '_' '-')
   PROJECT_NAME=$(basename "$PROJECT_ROOT")
   WORKTREE_PATH="/tmp/${PROJECT_NAME}-cp-${PLAN_SLUG}-phase-${PHASE}"

   git worktree prune
   # Ensure local main is current with origin/main before branching from it.
   # Fast-forward if behind. Legitimate local-ahead commits (cherry-pick
   # landings, unpushed user commits) are preserved. Divergent state leaves
   # local main as-is with a warning.
   git fetch origin main 2>/dev/null || echo "WARNING: git fetch origin main failed — worktree will use cached origin/main (may be stale)"
   git merge --ff-only origin/main 2>/dev/null || echo "WARNING: local main not fast-forwarded (may be divergent) — worktree uses local main as-is"
   FEATURE_BRANCH="cp-${PLAN_SLUG}-${PHASE}"  # unified across modes — used by post-run-invariants.sh
   if [ -d "$WORKTREE_PATH" ]; then
     echo "Resuming existing worktree at $WORKTREE_PATH"
   else
     git worktree add "$WORKTREE_PATH" -b "$FEATURE_BRANCH" main
   fi

   # Pipeline association
   echo "$PIPELINE_ID" > "$WORKTREE_PATH/.zskills-tracked"
   ```

   Cherry-pick mode: one worktree per phase, auto-named branch, `/tmp/` path.
   After landing (cherry-pick to main), worktree is removed.

2. **Dispatch implementation agent WITHOUT `isolation: "worktree"`.** The
   prompt tells the agent the worktree path and requires absolute paths:

   **Before dispatching any Agent:** check `agents.min_model` in
   `.claude/zskills-config.json`. If set, use that model or higher
   (ordinal: haiku=1 < sonnet=2 < opus=3). Never dispatch with a
   lower-ordinal model than the configured minimum.

   ```
   You are working in worktree: $WORKTREE_PATH

   IMPORTANT: Use ABSOLUTE PATHS for all file operations.
   - Bash: run `cd $WORKTREE_PATH` before commands
   - Read/Edit/Write/Grep: use $WORKTREE_PATH/... paths
   Do not work in any other directory.
   ```

   Tell the agent to write a `.worktreepurpose` file as its first action:
   ```
   echo "<session-name or plan-name>: <phase name>" > $WORKTREE_PATH/.worktreepurpose
   ```
   Example: `echo "SKILLZ: briefing Phase 1" > $WORKTREE_PATH/.worktreepurpose`
   This metadata helps `/briefing worktrees` and `/briefing verify` show
   what each worktree is for, instead of just an opaque agent ID.

   **Hygiene constraint — NEVER commit ephemeral pipeline files.** The
   files `.worktreepurpose`, `.zskills-tracked`, and `.landed` are worktree
   lifecycle markers and must stay UNTRACKED throughout the run.

   Test output lives OUTSIDE the worktree, at `/tmp/zskills-tests/<worktree-
   basename>/` (see CLAUDE.md). The filenames `.test-results.txt` and
   `.test-baseline.txt` should NEVER appear in the worktree at all; if they
   do, a stale writer leaked them, and `scripts/land-phase.sh` treats any
   git-tracked version as a landing-time error (a canary for contract
   violations — not a normal-path cleanup).

   Do NOT include any of these files in `git add` when dispatching
   implementation or verification agents. When staging for a commit, name
   specific source files explicitly (`git add skills/X.md tests/Y.sh ...`)
   rather than patterns that could sweep ephemerals in. `scripts/land-phase.sh`
   expects the lifecycle markers to be untracked and will refuse to clean up a
   worktree that has any of them tracked — a staged-delete left over
   from a commit would block `git worktree remove` and leak zombies.

   **Failed-run cleanup:** If a phase fails terminally, write `.landed` with
   `status: failed` in the worktree before invoking the Failure Protocol. The
   cron preamble runs `git worktree prune` to clean up stale entries from
   container restarts or crashed runs.

3. **Agent prompt MUST include the verbatim plan text.** The implementing
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

4. **If dispatching sub-agents for parallel work items**, each sub-agent gets:
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

5. **Within-phase parallelism is the agent's judgment call** — if items are
   independent (e.g., Mass, Spring, Damper components), the agent may dispatch
   sub-agents. If there's shared infrastructure to build first, it works
   sequentially then parallelizes. The skill does NOT force parallelism.

6. **Commit discipline:**
   - One logical unit per commit — clean git history
   - `npm run test:all` before every commit — not just `npm test`
   - Tests alongside implementation, not deferred to later
   - The implementation agent does NOT commit. The verification agent runs the full test suite and commits if verification passes. This ensures the hook's test gate is satisfied (the committing agent's transcript contains the test command).
   - **Declare pipeline ID** early in execution (before any git operation):
     ```bash
     echo "ZSKILLS_PIPELINE_ID=run-plan.$TRACKING_ID"
     ```
     This echo is read by the tracking hook from the session transcript to
     scope marker checks to this pipeline. Uses last-match so re-invocations
     in the same session work correctly.
   - **Before dispatching any worktree agent**, write `.zskills-tracked` in the worktree:
     ```bash
     printf '%s\n' "run-plan.$TRACKING_ID" > "<worktree-path>/.zskills-tracked"
     ```
     Where `$TRACKING_ID` is the plan slug (e.g., `thermal-domain`). This file associates the worktree agent with this pipeline for hook enforcement.
   - **Rebase onto current main before final commit:**
     ```bash
     git fetch origin main && git rebase origin/main
     ```
     This ensures the commit contains only the agent's changes, not stale
     copies of files other agents already fixed on main. If rebase
     conflicts, abort (`git rebase --abort`) and proceed — the cherry-pick
     verification will catch stale files via selective extraction.

7. **Running tests in worktrees — CRITICAL.** Agents waste hours getting
   tests working in worktrees without these instructions. Include this
   VERBATIM in every implementation and verification agent prompt:

   > **Worktree test recipe:**
   > 1. Start a dev server FIRST: `npm start &`
   > 2. Wait for it: `sleep 3`
   > 3. Run tests with output captured to a file:
   >    ```bash
   >    TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
   >    mkdir -p "$TEST_OUT"
   >    npm run test:all > "$TEST_OUT/.test-results.txt" 2>&1
   >    ```
   >    **Never pipe** through `| tail`, `| head`, `| grep` — it loses
   >    output and forces re-runs. Capture once, read the file.
   > 4. The dev server must stay running for E2E tests. If source files
   >    changed (they will have — you're implementing), E2E tests FAIL
   >    (not skip) without a dev server.
   > 5. If tests fail, **read `"$TEST_OUT/.test-results.txt"`** to find the failures.
   >    Then run ONLY the failing test file to iterate on the fix:
   >    `node --test tests/the-failing-file.test.js`
   >    Do NOT re-run `npm run test:all` to diagnose — that wastes 5
   >    minutes when the single file takes 30 seconds.
   > 6. After fixing, run the single file again to confirm. Then run
   >    ```bash
   >    TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
   >    mkdir -p "$TEST_OUT"
   >    npm run test:all > "$TEST_OUT/.test-results.txt" 2>&1
   >    ```
   >    ONE more time as the final gate before committing.
   > 7. Max 2 fix attempts at the same error — do not thrash.
   > 8. If a test fails in code you didn't touch, it may be pre-existing.
   >    See `/verify-changes` Phase 3 for the pre-existing failure protocol.

8. **No steps skipped or deferred.** If the plan says "implement 7 components,"
   implement 7 components. If it says "write tests for free vibration," write
   those exact tests. Do not stop after the easy items and declare the hard
   ones "future work."

### PR mode (Phase 2)

When `LANDING_MODE == pr`, the orchestrator creates a persistent worktree with
a named feature branch. All phases accumulate on the same branch (one PR per
plan). The worktree persists across cron turns for chunked execution.

**Mixed mode validation:** When `LANDING_MODE` is `pr`, scan the current phase text:
- `### Execution: direct` → ERROR: "Mixed execution modes not allowed in PR
  plans. All phases must use worktree or delegate mode."
- `### Execution: delegate ...` → OK (delegate manages its own isolation)
- `### Execution: worktree` or no directive → OK (default)

**Branch naming:** `{branch_prefix}{plan-slug}`
- `branch_prefix` from config (`execution.branch_prefix`), default `"feat/"`
- `plan-slug` derived from plan file path: lowercase, hyphens, no extension
  - `plans/THERMAL_DOMAIN.md` → `thermal-domain`
  - `plans/ADD_FILTER_BLOCK.md` → `add-filter-block`

```bash
# Derive plan slug
PLAN_FILE="plans/THERMAL_DOMAIN.md"
PLAN_SLUG=$(basename "$PLAN_FILE" .md | tr '[:upper:]' '[:lower:]' | tr '_' '-')

BRANCH_NAME="${BRANCH_PREFIX}${PLAN_SLUG}"
FEATURE_BRANCH="$BRANCH_NAME"  # unified across modes — used by post-run-invariants.sh
PROJECT_NAME=$(basename "$PROJECT_ROOT")
WORKTREE_PATH="/tmp/${PROJECT_NAME}-pr-${PLAN_SLUG}"
```

**PR-mode bookkeeping rule:** in PR mode, orchestrator bookkeeping (tracker updates, plan reports, `PLAN_REPORT.md` regen, plan-frontmatter completion, mark-Done) commits **inside the worktree on the feature branch**, not on `main`. The feature branch is the single source of truth; the squash merge lands everything atomically on `origin/main`, keeping local `main` in lockstep. In cherry-pick/direct mode these commits stay on `main` as before. Every "commit on main" instruction below for bookkeeping must be read through this lens.

**Worktree creation — orchestrator creates manually, NOT via `isolation: "worktree"`:**

```bash
# Prune stale worktree entries. If /tmp was cleared (container restart,
# codespace rebuild), git still has the old worktree registered in
# .git/worktrees/. `git worktree prune` cleans up entries whose directories
# no longer exist, so `git worktree add` won't fail with "already registered."
git worktree prune

# Ensure local main is current with origin/main before branching from it.
# Fast-forward if behind. Legitimate local-ahead commits (cherry-pick
# landings, unpushed user commits) are preserved — they flow through the
# PR with feature work. Divergent state (ahead AND behind) leaves local
# main as-is with a warning so the user knows to investigate.
git fetch origin main 2>/dev/null || echo "WARNING: git fetch origin main failed — worktree will use cached origin/main (may be stale)"
git merge --ff-only origin/main 2>/dev/null || echo "WARNING: local main not fast-forwarded (may be divergent) — worktree uses local main as-is"

# Check if worktree already exists (resuming a previous run)
if [ -d "$WORKTREE_PATH" ]; then
  echo "Resuming existing PR worktree at $WORKTREE_PATH"
else
  # Legitimate multi-phase PR-mode resume — opt into branch resume.
  ZSKILLS_ALLOW_BRANCH_RESUME=1 \
    bash scripts/worktree-add-safe.sh "$BRANCH_NAME" "$WORKTREE_PATH" main
fi
```

**One branch per plan.** All phases accumulate on the same branch. The worktree
persists across cron turns for chunked execution. Do NOT create a new worktree
per phase.

**Dispatching agents to the worktree:** Dispatch agents WITHOUT
`isolation: "worktree"`. The agent's prompt tells it to work in the worktree:

```
Agent tool prompt:
  "You are implementing Phase N of plan X.
   FIRST: cd /tmp/myproject-pr-thermal-domain
   All work happens in that directory. Do not work in any other directory.

   <phase work items here>

   Commit rules:
   - Do NOT commit. The verification agent commits after review.
   - Stage specific files by name (not git add .)
   ..."
```

The key line is `FIRST: cd $WORKTREE_PATH` — the agent treats this as a
mandatory first action. Without `isolation: "worktree"`, the agent starts in
the main repo directory, so the `cd` instruction is essential.

**Pipeline association:** Write `.zskills-tracked` in the worktree:

```bash
echo "$PIPELINE_ID" > "$WORKTREE_PATH/.zskills-tracked"
```

**Test baseline capture (orchestrator practice):** Before dispatching the
implementation agent, the orchestrator captures a test baseline in the worktree:

```bash
# Orchestrator captures baseline BEFORE impl agent starts
cd "$WORKTREE_PATH"
if [ -n "$FULL_TEST_CMD" ]; then
  TEST_OUT="/tmp/zskills-tests/$(basename "$WORKTREE_PATH")"
  mkdir -p "$TEST_OUT"
  $FULL_TEST_CMD > "$TEST_OUT/.test-baseline.txt" 2>&1 || true
fi
```

### Post-implementation tracking

After the implementation agent finishes (whether worktree or delegate mode),
create the implementation step marker:
```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
printf 'phase: %s\ncompleted: %s\n' "$PHASE" "$(TZ=America/New_York date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.run-plan.$TRACKING_ID.implement"
```

### Pre-verification tracking

The `requires.verify-changes.$TRACKING_ID` marker was created at skill
entry (Phase 1 step 8). The hook is enforcing it. Pass the tracking ID to
the verification agent so it can create its own fulfillment marker.

> **Note:** The per-pipeline verification requirement
> (`requires.verify-changes.$TRACKING_ID`) is **distinct** from
> `requires.verify-changes.final.<META_PLAN_SLUG>` which is a cross-branch
> final verification marker with a different lifecycle — created by
> `/research-and-go` Step 0, fulfilled after ALL sub-plans complete. Phase A
> does not modify or consolidate this marker; the two coexist independently.

Pass the tracking ID to the verification agent in the dispatch prompt so it
can create its own fulfillment marker:
> Your tracking ID is `$TRACKING_ID`. On entry, create
> `fulfilled.verify-changes.$TRACKING_ID` in the main repo's
> `.zskills/tracking/` directory.

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
context. This fallback is mostly defensive since /run-plan typically runs
at top level.

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
   to an existing one.

   **Before dispatching:** check `agents.min_model` in `.claude/zskills-config.json`.
   If set, use that model or higher (ordinal: haiku=1 < sonnet=2 < opus=3). Never
   dispatch with a lower-ordinal model than the configured minimum.

   Give the verification agent:
   - The **worktree path** from Phase 2 (so it can read files and run tests
     there). The verifier must run tests via:

     ```bash
     cd <worktree-path>
     TEST_OUT="/tmp/zskills-tests/$(basename "<worktree-path>")"
     mkdir -p "$TEST_OUT"
     npm run test:all > "$TEST_OUT/.test-results.txt" 2>&1
     ```

     Note: compute `$TEST_OUT` from the worktree-path LITERAL you were handed,
     NOT from `$(pwd)` at prompt-entry time — the orchestrator dispatches you
     without `isolation`, so your initial cwd is the orchestrator's (typically
     main), and a pre-cd `$(pwd)` would yield the wrong basename and miss the
     baseline.

     Orchestrator-runtime note: when the orchestrator constructs the verifier
     prompt, it substitutes the literal string `<worktree-path>` with the
     actual worktree path BEFORE dispatching. The verifier sees a fully-
     substituted prompt — no placeholder parsing on its side. Both orchestrator
     baseline capture (line 811) and verifier `$TEST_OUT` derivation MUST use
     `basename` of the SAME path literal, so the baseline and the results land
     in the same `/tmp/zskills-tests/<name>/` bucket.

   - The **worktree branch name** (so it can diff against main:
     `git diff main...<branch>`)
   - The **verbatim phase text** from the plan (same text the implementer got)
   - Instruction to run `/verify-changes worktree` — the verification agent
     runs this, NOT you. Do NOT run verification yourself — you are the
     orchestrator with implementer bias.
   - The **work items checklist** — verify each item was actually implemented,
     not stubbed or skipped
   - The **`"$TEST_OUT/.test-baseline.txt"` file** captured before implementation
     started (if `FULL_TEST_CMD` is configured). The verification agent should:
     - Read `"$TEST_OUT/.test-baseline.txt"` (baseline captured before implementation)
     - Compare against `"$TEST_OUT/.test-results.txt"` (results after running tests now)
     - **New failures** (in results but not in baseline) → regressions, must
       be fixed before the phase can commit
     - **Pre-existing failures** (in both baseline and results) → note in report,
       do not fix (these predate this phase)
     - **Resolved failures** (in baseline but not in results) → note positively
       as improvements
     - If `"$TEST_OUT/.test-baseline.txt"` is absent (`FULL_TEST_CMD` not configured),
       treat all failures as potentially new — report all of them

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
PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
printf 'phase: %s\nresult: pass\ncompleted: %s\n' "$PHASE" "$(TZ=America/New_York date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.run-plan.$TRACKING_ID.verify"
```

## Phase 4 — Update Progress Tracking

After verification passes. The plan file tracks progress across phases — an
orchestrator concern, not an implementation artifact. Update it promptly so
the next cron invocation sees the correct phase status and advances
(preventing infinite loops).

**Commit location depends on `LANDING_MODE`** (see PR-mode bookkeeping rule):
cherry-pick/direct commits on main; PR mode `cd "$WORKTREE_PATH"` first and
commits on the feature branch.

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

4. **Mark the phase as 🟡 In Progress and commit** (mode-conditional location):
   ```bash
   # PR mode only: cd "$WORKTREE_PATH" first (cherry-pick/direct: stay on main)
   git add <plan-file> [companion-doc]
   git commit -m "chore: mark phase <name> in progress"
   ```
   Not ✅ Done yet — Phase 6 updates to Done after landing succeeds (in
   cherry-pick/direct via a main commit, in PR mode via a commit on the
   feature branch *before* push so it's captured in the squash). If
   landing fails in either mode, tracker correctly reads In Progress.

## Phase 5 — Write Report

**PREPEND** new phase sections after the H1 in `reports/plan-{slug}.md`
(`{slug}` from plan filename, e.g., `FEATURE_PLAN.md` → `plan-physics module`).
Newest phase at the top — the reader's question is "what needs my
attention?" and that's always the newest phase.

If the file doesn't exist, create it with a `# Plan Report — {plan name}`
heading. Never overwrite the file — each phase adds a section.

**File location and commit follow the PR-mode bookkeeping rule**: in PR
mode, write to `$WORKTREE_PATH/reports/plan-{slug}.md`, regenerate
`$WORKTREE_PATH/PLAN_REPORT.md`, and commit on the feature branch.
Cherry-pick/direct: write/regen/commit on main (unchanged).

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

- [ ] **P4b-1** — Variable viewer panel
  1. Open the app, load a physics module model (e.g., voltage-divider example)
  2. Run the simulation
  3. Click the lightning icon in the toolstrip
  4. Verify the Physical Variables panel opens with columns for V, I, P
  5. Check that values update after simulation completes
  ![viewer panel](.playwright/output/phase4b-variable-viewer.png)

- [ ] **P4b-2** — Toolstrip button
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
PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
printf 'phase: %s\ncompleted: %s\n' "$PHASE" "$(TZ=America/New_York date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.run-plan.$TRACKING_ID.report"
```

## Phase 5b — Plan Completion

Triggers when ALL phases are done: either the last phase just finished
(single-phase run where it was the only remaining phase), or in `finish`
mode after all phases complete. Run this BEFORE Phase 6 (Land).

### 0a. Idempotent early-exit

If frontmatter is already `status: complete`: this is a no-op re-entry.
Exit cleanly without re-committing. Output "Plan already complete (no-op)."

### 0b. Final-verify gate

**Only applies if a final-verify marker exists.** Check for the cross-branch
final-verify marker:

```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
# The final-verify marker is written by /research-and-go into ITS pipeline
# subdir (research-and-go.$META_PLAN_SLUG/), not into this /run-plan's own
# subdir. Use glob-dual-lookup: prefer any research-and-go.*/ subdir whose
# marker basename matches this TRACKING_ID; fall back to the legacy flat
# path during the Phase 2-6 transitional window.
MARKER=$(ls "$MAIN_ROOT/.zskills/tracking/"research-and-go.*/requires.verify-changes.final."$TRACKING_ID" 2>/dev/null | head -1)
[ -z "$MARKER" ] && MARKER="$MAIN_ROOT/.zskills/tracking/requires.verify-changes.final.$TRACKING_ID"
FULFILLED=$(ls "$MAIN_ROOT/.zskills/tracking/"research-and-go.*/fulfilled.verify-changes.final."$TRACKING_ID" 2>/dev/null | head -1)
[ -z "$FULFILLED" ] && FULFILLED="$MAIN_ROOT/.zskills/tracking/fulfilled.verify-changes.final.$TRACKING_ID"
```

Three branches:

1. **Marker exists AND fulfilled missing**: defer pipeline completion until
   `/verify-changes branch` runs at top level. Use self-rescheduling pattern
   with exponential backoff.

   Rationale: `/verify-changes branch` can take 5–60 min depending on
   cumulative diff size; a fixed-time second cron risks firing before
   fulfillment exists, causing visible "still pending" turns.

   Read attempt counter file:
   `$MAIN_ROOT/.zskills/tracking/verify-pending-attempts.$TRACKING_ID`
   (numeric content; absent = 0). On each invocation:

   - Increment attempt counter, write back to file.
   - Compute backoff: `attempt 1: 10min, 2: 20min, 3: 40min, 4+: 60min`
     (capped at 60min).
   - On attempt 1 only: schedule the verify cron itself —
     `Run /verify-changes branch tracking-id=$TRACKING_ID` one-shot,
     ~5 min from now.
   - On every attempt: schedule re-entry cron —
     `Run /run-plan <plan-file> finish auto` one-shot, `<backoff>` from now.
   - Exit with message:
     > Final cross-branch verify pending (attempt <N>). Re-entry scheduled
     > in <backoff>. Verify cron: <id-if-attempt-1>. Re-entry cron: <id>.

   Do NOT run Phase 5b sub-steps 1–4. Do NOT run Phase 5c. Do NOT run
   Phase 6.

   ```bash
   # Self-rescheduling with exponential backoff
   PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
   ATTEMPTS_FILE="$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/verify-pending-attempts.$TRACKING_ID"
   if [ -f "$ATTEMPTS_FILE" ]; then
     ATTEMPT=$(( $(cat "$ATTEMPTS_FILE") + 1 ))
   else
     ATTEMPT=1
   fi
   echo "$ATTEMPT" > "$ATTEMPTS_FILE"

   # Compute backoff minutes: 10, 20, 40, 60 (capped)
   case "$ATTEMPT" in
     1) BACKOFF_MIN=10 ;;
     2) BACKOFF_MIN=20 ;;
     3) BACKOFF_MIN=40 ;;
     *) BACKOFF_MIN=60 ;;
   esac
   ```

   On attempt 1, schedule the verify cron (~5 min from now). TZ note: the
   `date +%M` calls below use SYSTEM-local TZ, which is what CronCreate
   expects. Do NOT override with `TZ=America/New_York` — see the warning
   in "How to schedule the next cron" below for why this breaks the cron.
   Margin note: +5 (not +1) gives the scheduler enough slack that
   sub-minute timing jitter doesn't push a pinned-date one-shot past its
   fire window. See "How to schedule the next cron" below for the
   pinned-date / miss-by-365-days failure mode.
   ```bash
   NOW_MIN=$(date +%M); NOW_HOUR=$(date +%H)
   NOW_DAY=$(date +%d); NOW_MONTH=$(date +%m)
   TARGET_MIN=$(( (10#$NOW_MIN + 5) % 60 ))
   if [ "$TARGET_MIN" -eq 0 ] || [ "$TARGET_MIN" -eq 30 ]; then
     TARGET_MIN=$(( TARGET_MIN + 1 ))
   fi
   TARGET_HOUR=$NOW_HOUR
   if [ "$TARGET_MIN" -lt "$NOW_MIN" ]; then
     TARGET_HOUR=$(( (10#$NOW_HOUR + 1) % 24 ))
   fi
   ```
   Then call `CronCreate` with:
   - `cron`: `"$TARGET_MIN $TARGET_HOUR $NOW_DAY $NOW_MONTH *"`
   - `recurring`: false
   - `prompt`: `"Run /verify-changes branch tracking-id=$TRACKING_ID"`

   On every attempt, schedule re-entry cron (`<backoff>` from now):
   ```bash
   REENTRY_MIN=$(( (10#$NOW_MIN + BACKOFF_MIN) % 60 ))
   REENTRY_HOUR=$NOW_HOUR
   if [ "$REENTRY_MIN" -lt "$NOW_MIN" ]; then
     REENTRY_HOUR=$(( (10#$NOW_HOUR + 1) % 24 ))
   fi
   ```
   Then call `CronCreate` with:
   - `cron`: `"$REENTRY_MIN $REENTRY_HOUR $NOW_DAY $NOW_MONTH *"`
   - `recurring`: false
   - `prompt`: `"Run /run-plan <plan-file> finish auto"`

   Then exit this turn.

2. **Marker exists AND fulfilled exists**: verify completed. Delete the
   attempt counter file (cleanup):
   ```bash
   PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
   rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/verify-pending-attempts.$TRACKING_ID"
   ```
   Proceed to sub-step 1.

3. **No marker** (standalone plan, not via /research-and-go): proceed to
   sub-step 1.

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
add one: `status: complete`. Commit (mode-conditional per PR-mode rule):
```bash
# PR mode only: cd "$WORKTREE_PATH" first (cherry-pick/direct: stay on main)
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

### 5. Remind about stale tracking markers

After plan completion, the `fulfilled.run-plan.<id>` marker stays on disk
as the canonical completion record, but the pipeline's `requires.*`,
`step.*`, `verify-pending-attempts.*`, and `fulfilled.verify-changes.*`
markers (which are bookkeeping, not history) persist in
`.zskills/tracking/` indefinitely. Over many plan runs these accumulate
and can cause subtle drift (e.g., a test that invokes the hook's push
path from a zskills-tracked worktree may trip tracking enforcement
against a leftover `requires.*` from a prior pipeline).

Count remaining non-completion markers across all pipelines and surface
a one-line reminder. Do NOT auto-clean — this skill's job is
to run plans, not manage long-term tracking state. The user runs
`bash scripts/clear-tracking.sh` when they're ready.

```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
# Count markers from both layouts during the Phase 2-6 transitional window:
# (1) per-pipeline subdirs (.zskills/tracking/*/…) — Option B primary, and
# (2) legacy flat basenames directly under .zskills/tracking/ — flat fallback.
MARKER_COUNT=$(ls "$MAIN_ROOT/.zskills/tracking/"*/requires.* \
                    "$MAIN_ROOT/.zskills/tracking/"*/step.* \
                    "$MAIN_ROOT/.zskills/tracking/"*/verify-pending-attempts.* \
                    "$MAIN_ROOT/.zskills/tracking/"*/fulfilled.verify-changes.* \
                    "$MAIN_ROOT/.zskills/tracking/"requires.* \
                    "$MAIN_ROOT/.zskills/tracking/"step.* \
                    "$MAIN_ROOT/.zskills/tracking/"verify-pending-attempts.* \
                    "$MAIN_ROOT/.zskills/tracking/"fulfilled.verify-changes.* 2>/dev/null \
                | wc -l)
if [ "$MARKER_COUNT" -ge 10 ]; then
  echo "NOTE: $MARKER_COUNT bookkeeping tracking markers on disk across completed pipelines."
  echo "      Run: bash scripts/clear-tracking.sh   (preserves fulfilled.run-plan.* completion records)"
fi
```

Threshold `10` is a judgment call — below that the accumulation is not
yet disruptive. Adjust if it proves noisy or too quiet in practice.

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

Cross-reference: Step 0 in Phase 1 preflight. At the very start of every
`/run-plan` invocation in `finish auto` mode, read the plan tracker and
check the next-target phase. If it's already marked Done OR In Progress,
**exit cleanly** with a "no work to do" message. This handles two cases:

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

After Phase 6 (land) succeeds for the current phase AND
`scripts/post-run-invariants.sh` passes:

> **`post-run-invariants.sh` ordering**: Phase 5c's next-phase cron
> schedule runs AFTER `post-run-invariants.sh` passes. If invariants
> fail, do NOT schedule the next cron; invoke Failure Protocol.

1. **NEXT incomplete phase exists in this plan**: schedule a one-shot cron
   (`recurring: false`) for `/run-plan <plan-file> finish auto` ~5 min
   from now. The next cron-fired turn will pick up the next phase. Then
   exit this turn.

2. **This plan is a sub-plan delegate** (detected via `tracking-index=N`
   arg from research-and-go Step 1b — see `skills/research-and-go/SKILL.md:135`):
   after the last phase of this sub-plan lands, recover the meta-plan path
   from `requires.run-plan.N` marker content (or
   `pipeline.research-and-go.*` sentinel — see Step 1b). Schedule a
   one-shot cron for `/run-plan <META_PLAN_PATH> finish auto` ~5 min
   from now. The next cron-fired turn will resume the meta-plan from its
   next incomplete delegate phase. Then exit.

3. **All phases done (meta or standalone)**: do NOT schedule a next-phase
   cron. Phase 5b has already run (or will run on the next `/run-plan`
   invocation/re-entry — see Phase 1 step 3 amendment). Exit cleanly. The
   final-verify gate lives in Phase 5b's first sub-step (see Phase 5b
   0b. Final-verify gate); Phase 5c does not handle final-verify directly.

### PR-mode branching for next-phase cron

Do NOT poll `gh pr view --json state` inside the cron turn. Instead,
Phase 5c reads the just-written `.landed` status file (written at landing
time):

- `status: landed` → schedule next-phase cron, exit.
- `status: pr-ready` or `pr-ci-failing` → schedule a SHORT re-entry cron
  (~5 min) whose prompt re-fires `/run-plan <plan> finish auto`. Step 0's
  idempotent check will see the current phase is still In Progress and
  re-attempt the PR-state poll via Phase 6.
- `status: conflict` or `pr-failed` → invoke Failure Protocol. Do not
  schedule next cron.
- In cherry-pick / direct mode, the land event is synchronous (`.landed`
  written immediately) and next-phase cron schedules directly.

### User Verify items in chunked mode

In chunked mode, landing happens per-phase. If the just-landed phase has
User Verify items, schedule the next-phase cron AND output the User Verify
items in this turn's completion message. Per-phase landing IS the chunked
model — do NOT hold landing until all phases complete.

### How to schedule the next cron

```bash
# Compute target minute: +5 from now, avoiding :00 and :30 marks.
# CRITICAL: `date +%M` uses SYSTEM-local TZ, and CronCreate reads the cron
# expression in SYSTEM-local TZ. Do NOT "fix" these to `TZ=America/New_York
# date +%M` — that encodes ET into the expression while CronCreate expects
# system-local, producing a cron pinned to a date/time that's already
# passed (next fire ~365 days out). The user-facing message uses ET for
# readability; the cron expression itself MUST stay system-local.
#
# WHY +5 (not +1): one-shot crons pin day-of-month + month. If scheduler
# jitter (sub-minute clock drift, TZ-conversion rounding, tick skew) makes
# the fire window appear "already passed" at evaluation time, the next
# matching slot is day-of-month+month NEXT YEAR — the cron sits in
# CronList forever but won't fire this session. 1-minute margin is
# borderline; 5 minutes is comfortable slack. Observed in the wild: a
# chunked finish-auto pipeline's 5th consecutive +1 cron missed its
# window and stalled the entire run.
NOW_MIN=$(date +%M)
NOW_HOUR=$(date +%H)
NOW_DAY=$(date +%d)
NOW_MONTH=$(date +%m)
TARGET_MIN=$(( (10#$NOW_MIN + 5) % 60 ))
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
- `prompt`: the next-step prompt — typically `"Run /run-plan <plan-file> finish auto"`, or `"Run /run-plan <meta-plan-path> finish auto"`, or `"Run /verify-changes branch tracking-id=$TRACKING_ID"`

After scheduling, output the chunking message:
> Phase <N> of `<plan>` complete (commit `<hash>`).
> Phase <N+1> will fire automatically in ~5 minutes (cron `<job-id>`).
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

### Direct mode landing

If `LANDING_MODE` is `direct`, Phase 6 is a **no-op**. Work was committed
directly on main — there is nothing to cherry-pick, no worktree to land,
and no `.landed` marker to write. Update the progress tracker to Done and
proceed to the next phase or exit.

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

When `LANDING_MODE == pr`, landing replaces cherry-pick with push + PR creation.

**Rebase strategy:** Rebase onto latest main only when the tree is clean.
NEVER stash + rebase. NEVER `git merge origin/main`.

**Rebase point 1: between phases (finish mode only)**

After the verification agent commits Phase N, BEFORE dispatching Phase N+1's
impl agent:

```bash
cd "$WORKTREE_PATH"
git fetch origin main
PRE_REBASE=$(git rev-parse HEAD)
git rebase origin/main
# Tree is clean (verification agent just committed). No stash needed.
if [ $? -ne 0 ]; then
  echo "REBASE CONFLICT: Phase $N changes conflict with main."

  # --- Agent-assisted conflict resolution ---
  # LLM agents can read both sides of a conflict and resolve intelligently.
  # Only bail if the conflict is genuinely too complex or resolution fails.
  #
  # 1. Check scope: how many files are conflicted?
  CONFLICT_FILES=$(git diff --name-only --diff-filter=U)
  CONFLICT_COUNT=$(echo "$CONFLICT_FILES" | grep -c .)
  echo "Conflicted files ($CONFLICT_COUNT): $CONFLICT_FILES"

  # 2. If manageable (≤5 files), attempt resolution
  if [ "$CONFLICT_COUNT" -le 5 ]; then
    echo "Attempting agent-assisted resolution..."
    # The agent reads each conflicted file, understands both sides' intent,
    # and produces a merged version. For each file:
    #   - Read the file (contains <<<<<<< / ======= / >>>>>>> markers)
    #   - Understand what "ours" (the phase work) and "theirs" (main) intended
    #   - Write a clean merged version that preserves both changes
    #   - git add <file>
    #
    # After resolving all files: git rebase --continue
    # Then run tests to verify the resolution is correct.
    #
    # If tests pass: resolution succeeded, continue normally.
    # If tests fail: the resolution was wrong. Abort and bail.
    #   git rebase --abort  (if still rebasing)
    #   Fall through to the bail block below.
    #
    # If the agent genuinely can't understand the conflict (ambiguous intent,
    # too intertwined, or not confident): don't guess. Abort immediately.
    # A wrong silent resolution is worse than bailing clearly.
  fi

  # 3. If resolution wasn't attempted (too many files) or failed:
  #    Abort the rebase and write a clear conflict marker.
  #    Check if we're still in a rebase state before aborting.
  if [ -d "$(git rev-parse --git-dir)/rebase-merge" ] || [ -d "$(git rev-parse --git-dir)/rebase-apply" ]; then
    git rebase --abort
  fi

  cat <<LANDED | bash scripts/write-landed.sh "$WORKTREE_PATH"
status: conflict
date: $(TZ=America/New_York date -Iseconds)
source: run-plan
method: pr
branch: $BRANCH_NAME
phase: $N
reason: rebase-conflict-between-phases
conflict_files: $CONFLICT_FILES
commits: $(git log main.."$BRANCH_NAME" --format='%h' | tr '\n' ' ')
LANDED

  # CLEAR communication: tell the user exactly what happened and how to resume.
  echo ""
  echo "=========================================="
  echo "REBASE CONFLICT — could not auto-resolve"
  echo "=========================================="
  echo "Phase: $N"
  echo "Conflicted files: $CONFLICT_FILES"
  echo "Worktree: $WORKTREE_PATH (clean — rebase aborted)"
  echo "Branch: $BRANCH_NAME (all phase commits intact)"
  echo ""
  echo "To resume:"
  echo "  1. cd $WORKTREE_PATH"
  echo "  2. git rebase origin/main"
  echo "  3. Resolve conflicts, git add, git rebase --continue"
  echo "  4. rm .landed"
  echo "  5. Re-run /run-plan"
  echo "=========================================="
  exit 1
fi
if [ "$(git rev-parse HEAD)" != "$PRE_REBASE" ]; then
  echo "Main moved -- re-verifying before Phase $((N+1))..."
  # Dispatch /verify-changes worktree for full re-verification.
  # The verification agent is dispatched the same way as implementation
  # agents -- prompt includes "FIRST: cd $WORKTREE_PATH".
  # Re-verification has its OWN fix cycle (max 2 attempts), INDEPENDENT
  # of the CI fix budget. If re-verification fails after its own max
  # attempts, STOP -- same as any verification failure (write report,
  # mark phase as failed).
fi
```

**Rebase point 2: before push (all PR mode runs)**

After the LAST phase's verification agent commits, before pushing:

```bash
cd "$WORKTREE_PATH"
git fetch origin main
PRE_REBASE=$(git rev-parse HEAD)
git rebase origin/main
if [ $? -ne 0 ]; then
  echo "REBASE CONFLICT: Branch conflicts with main before push."

  # --- Agent-assisted conflict resolution (same as between-phases) ---
  CONFLICT_FILES=$(git diff --name-only --diff-filter=U)
  CONFLICT_COUNT=$(echo "$CONFLICT_FILES" | grep -c .)
  echo "Conflicted files ($CONFLICT_COUNT): $CONFLICT_FILES"

  if [ "$CONFLICT_COUNT" -le 5 ]; then
    echo "Attempting agent-assisted resolution..."
    # Read each conflicted file, understand both sides, merge intelligently.
    # After resolving: git add <file>, git rebase --continue, run tests.
    # If tests pass → continue to push. If tests fail → abort and bail.
    # If not confident about the resolution → don't guess, abort immediately.
  fi

  # If resolution wasn't attempted or failed: abort and bail clearly.
  if [ -d "$(git rev-parse --git-dir)/rebase-merge" ] || [ -d "$(git rev-parse --git-dir)/rebase-apply" ]; then
    git rebase --abort
  fi

  cat <<LANDED | bash scripts/write-landed.sh "$WORKTREE_PATH"
status: conflict
date: $(TZ=America/New_York date -Iseconds)
source: run-plan
method: pr
branch: $BRANCH_NAME
reason: rebase-conflict-before-push
conflict_files: $CONFLICT_FILES
commits: $(git log main.."$BRANCH_NAME" --format='%h' | tr '\n' ' ')
LANDED

  echo ""
  echo "=========================================="
  echo "REBASE CONFLICT — could not auto-resolve"
  echo "=========================================="
  echo "Conflicted files: $CONFLICT_FILES"
  echo "Worktree: $WORKTREE_PATH (clean — rebase aborted)"
  echo "Branch: $BRANCH_NAME (all phase commits intact)"
  echo ""
  echo "To resume:"
  echo "  1. cd $WORKTREE_PATH"
  echo "  2. git rebase origin/main"
  echo "  3. Resolve conflicts, git add, git rebase --continue"
  echo "  4. rm .landed"
  echo "  5. Re-run /run-plan"
  echo "=========================================="
  exit 1
fi
if [ "$(git rev-parse HEAD)" != "$PRE_REBASE" ]; then
  echo "Main moved since last verification -- re-verifying..."
  # Dispatch /verify-changes worktree for full re-verification.
  # The verification agent's prompt includes "FIRST: cd $WORKTREE_PATH".
  # This includes tests, code review, and manual testing if UI files changed.
  # Re-verification has its OWN fix cycle (max 2 attempts), INDEPENDENT
  # of the CI fix budget. If re-verification fails after its own max
  # attempts, STOP -- same as any verification failure.
  # If re-verification passes, proceed to push.
fi
```

**Mark tracker ✅ Done on feature branch (PR mode, before push):**

PR mode has no post-landing window the orchestrator controls — auto-merge
is asynchronous. So the Done update must be made on the feature branch
**before push**, captured in the squash. Also regen `reports/plan-{slug}.md`
and `PLAN_REPORT.md` here if they need post-landing updates (strip
`[UNFINALIZED]`, add merge note).

```bash
cd "$WORKTREE_PATH"
# Edit plan file: change tracker row 🟡 → ✅ with commit hash
git add <plan-file> [reports/plan-{slug}.md PLAN_REPORT.md]
git commit -m "chore: mark phase <name> done (landed)"
```

If push/CI/auto-merge fails, the branch has optimistic Done state — fine
because it's on feature branch, not main. Main only gets Done on successful
squash-merge. Retry reuses the existing Done commit.

**Push + PR creation:**

```bash
cd "$WORKTREE_PATH"

# --- Construct PR title and body ---
# $PLAN_SLUG, $PLAN_TITLE, $CURRENT_PHASE_NUM, $CURRENT_PHASE_TITLE come from
# the plan parser (Phase 1 of /run-plan's execution).
# $FINISH_MODE is true when running in finish mode (all remaining phases).

if [ "$FINISH_MODE" = "true" ]; then
  PR_TITLE="[${PLAN_SLUG}] ${PLAN_TITLE}"
else
  PR_TITLE="[${PLAN_SLUG}] Phase ${CURRENT_PHASE_NUM}: ${CURRENT_PHASE_TITLE}"
fi

# Collect completed phases for the body
COMPLETED_PHASES=$(grep -E '^\| .* \| ✅' "$PLAN_FILE" | sed 's/|//g' | awk '{$1=$1};1' || echo "See plan file")

PR_BODY="## Plan: ${PLAN_TITLE}

**Phases completed:**
${COMPLETED_PHASES}

**Report:** See \`reports/plan-${PLAN_SLUG}.md\` for details.

---
Generated by \`/run-plan\`"

# --- Push (error-check each branch; a silent push failure would make
#     downstream polling watch stale CI or hang on a branch that
#     doesn't exist on origin yet) ---
if git ls-remote --heads origin "$BRANCH_NAME" | grep -q "$BRANCH_NAME"; then
  echo "Remote branch $BRANCH_NAME already exists. Pushing updates."
  if ! git push origin "$BRANCH_NAME"; then
    echo "ERROR: git push to existing $BRANCH_NAME failed. Aborting before PR creation." >&2
    cat <<LANDED | bash scripts/write-landed.sh "$WORKTREE_PATH"
status: pr-failed
date: $(TZ=America/New_York date -Iseconds)
source: run-plan
method: pr
branch: $BRANCH_NAME
reason: push-failed-to-existing-remote
commits: $(git log main.."$BRANCH_NAME" --format='%h' | tr '\n' ' ')
LANDED
    exit 1
  fi
else
  if ! git push -u origin "$BRANCH_NAME"; then
    echo "ERROR: git push -u (first-time) failed for $BRANCH_NAME. Aborting before PR creation." >&2
    cat <<LANDED | bash scripts/write-landed.sh "$WORKTREE_PATH"
status: pr-failed
date: $(TZ=America/New_York date -Iseconds)
source: run-plan
method: pr
branch: $BRANCH_NAME
reason: push-failed-first-time
commits: $(git log main.."$BRANCH_NAME" --format='%h' | tr '\n' ' ')
LANDED
    exit 1
  fi
fi

# --- PR creation ---
EXISTING_PR=$(gh pr list --head "$BRANCH_NAME" --json number --jq '.[0].number' 2>/dev/null)
if [ -n "$EXISTING_PR" ]; then
  echo "PR #$EXISTING_PR already exists for $BRANCH_NAME. Updated with latest push."
  # Query URL defensively — a transient `gh pr view` failure here used to
  # leave PR_URL empty, which the downstream "Verify PR was created"
  # block misinterprets as "PR creation failed" and writes pr-failed
  # even though the PR really exists.
  if ! PR_URL=$(gh pr view "$EXISTING_PR" --json url --jq '.url' 2>&1); then
    echo "ERROR: could not query existing PR #$EXISTING_PR URL (gh pr view failed): $PR_URL" >&2
    echo "Branch is pushed; investigate manually. Writing .landed with pr-failed." >&2
    PR_URL=""
  fi
  PR_NUMBER="$EXISTING_PR"
else
  PR_URL=$(gh pr create \
    --title "$PR_TITLE" \
    --body "$PR_BODY" \
    --base main \
    --head "$BRANCH_NAME")
  if [ -n "$PR_URL" ]; then
    # Extract PR_NUMBER from PR_URL directly — avoids a second `gh pr view`
    # call that can independently fail and leave PR_NUMBER unset (whereas
    # PR_URL here is known-good).
    # PR_URL format: https://github.com/<owner>/<repo>/pull/<N>
    PR_NUMBER="${PR_URL##*/}"
    # Sanity-check: PR_NUMBER should be all digits.
    if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
      echo "ERROR: extracted PR_NUMBER='$PR_NUMBER' from PR_URL='$PR_URL' is not numeric." >&2
      # Fall back to gh pr view, with error capture this time.
      if ! PR_NUMBER=$(gh pr view --json number --jq '.number' 2>&1); then
        echo "ERROR: fallback gh pr view also failed: $PR_NUMBER" >&2
        PR_NUMBER=""
      fi
    fi
  fi
fi

# --- Verify PR was created ---
if [ -z "$PR_URL" ]; then
  echo "WARNING: PR creation failed. Branch pushed but PR not created."
  echo "Manual fallback: gh pr create --base main --head $BRANCH_NAME"
  cat <<LANDED | bash scripts/write-landed.sh "$WORKTREE_PATH"
status: pr-failed
date: $(TZ=America/New_York date -Iseconds)
source: run-plan
method: pr
branch: $BRANCH_NAME
pr:
commits: $(git log main.."$BRANCH_NAME" --format='%h' | tr '\n' ' ')
LANDED
  # Report and stop -- PR creation failed
fi
```

**`.landed` marker for PR mode:**

After successful push + PR creation, re-read CI config, poll CI checks, run the
fix cycle if needed, request auto-merge, and write the `.landed` marker with the
final status based on CI results.

```bash
# --- Re-read config at point of use ---
# Do NOT rely on $CONFIG_CONTENT from earlier -- context compaction may
# have lost it. Re-read the config file now.
CI_AUTO_FIX=true
CI_MAX_ATTEMPTS=2
FULL_TEST_CMD=""
CONFIG_FILE="$PROJECT_ROOT/.claude/zskills-config.json"
if [ -f "$CONFIG_FILE" ]; then
  CI_CONFIG=$(cat "$CONFIG_FILE" 2>/dev/null)
  if [[ "$CI_CONFIG" =~ \"auto_fix\"[[:space:]]*:[[:space:]]*(true|false) ]]; then
    CI_AUTO_FIX="${BASH_REMATCH[1]}"
  fi
  if [[ "$CI_CONFIG" =~ \"max_fix_attempts\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
    CI_MAX_ATTEMPTS="${BASH_REMATCH[1]}"
  fi
  if [[ "$CI_CONFIG" =~ \"full_cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    FULL_TEST_CMD="${BASH_REMATCH[1]}"
  fi
fi
```

**Skip CI when disabled:**

```bash
if [ "$CI_AUTO_FIX" = "false" ]; then
  echo "CI auto-fix disabled (ci.auto_fix: false). PR created -- CI results are the user's responsibility."
  CI_STATUS="skipped"
fi
```

**CI pre-check (avoid hang on repos with no CI):**

`gh pr checks --watch` hangs indefinitely if no checks are configured. GitHub
Actions has a registration delay (5-30s after push), so retry before concluding
there are no checks:

```bash
CHECK_COUNT=0
for _i in 1 2 3; do
  CHECK_COUNT=$(gh pr checks "$PR_NUMBER" --json name --jq 'length' 2>/dev/null || echo "0")
  [ "$CHECK_COUNT" != "0" ] && break
  sleep 10
done
if [ "$CHECK_COUNT" = "0" ]; then
  echo "No CI checks configured for this repo. Skipping CI polling."
  CI_STATUS="none"
fi
```

**CI polling:**

```bash
echo "Waiting for $CHECK_COUNT CI check(s) on PR #$PR_NUMBER..."
CI_LOG="/tmp/ci-failure-${PR_NUMBER}.txt"

# Timeout: 10 minutes. In cron mode, a hung --watch blocks the entire turn.
# Exit code 124 from timeout means "timed out" -- treat as "checks still pending".
timeout 600 gh pr checks "$PR_NUMBER" --watch 2>"$CI_LOG.stderr"
WATCH_EXIT=$?

# `gh pr checks --watch` exit code is UNRELIABLE across gh versions —
# some (observed in the CI_FIX_CYCLE_CANARY run, 2026-04-18) return 0
# even when a check concluded `fail`, making --watch useless as a
# pass/fail signal. Only trust exit 124 from `timeout(1)` to mean
# "still running, give up waiting." For every other outcome, re-check
# explicitly with `gh pr checks $PR_NUMBER` (no --watch), which DOES
# signal via exit code: 0=all pass, 1=any failure, 8=some still pending.
if [ "$WATCH_EXIT" -eq 124 ]; then
  echo "CI checks timed out after 10 minutes. Treating as pending."
  CI_STATUS="pending"
  # Write .landed with pr-ready so the next cron turn re-checks.
  # Do NOT enter the fix cycle -- checks are still running, not failing.
else
  if gh pr checks "$PR_NUMBER" >/dev/null 2>&1; then
    echo "CI checks passed."
    CI_STATUS="pass"
  else
    CHECK_RC=$?
    echo "CI checks did not pass (gh pr checks rc=$CHECK_RC). Reading failure logs..."
    CI_STATUS="fail"
    FAILED_RUN_ID=$(gh run list --branch "$BRANCH_NAME" --status failure --limit 1 \
      --json databaseId --jq '.[0].databaseId' 2>/dev/null)
    if [ -n "$FAILED_RUN_ID" ]; then
      gh run view "$FAILED_RUN_ID" --log-failed 2>&1 | head -500 > "$CI_LOG"
    fi
  fi
fi
```

Note: `gh pr checks --watch` is used WITHOUT `--fail-fast` (that flag may
not exist in all gh versions). The re-check AFTER the watch is what
actually determines pass/fail — do not rely on the watch's exit code alone.

**Timeout handling:** If `CI_STATUS` is `"pending"` (timeout exit 124), skip the
fix cycle entirely and write `.landed` with `status: pr-ready`. The next cron
turn will re-enter Phase 6, see the existing PR, and re-poll CI.

**CI failure fix cycle:**

```bash
if [ "$CI_STATUS" = "fail" ] && [ "$CI_MAX_ATTEMPTS" -gt 0 ]; then
  # Post initial CI status comment using gh api (returns comment ID).
  # gh pr comment does NOT return comment URL/ID, so we use the API directly.
  # The `|| true` preserves the assignment on gh api failure (network/auth);
  # downstream `[ -n "$COMMENT_ID" ]` guards the PATCH calls. We warn to
  # stderr so the failure is visible instead of silently losing the PR-side
  # commentary of the fix cycle.
  COMMENT_ID=$(gh api "repos/{owner}/{repo}/issues/$PR_NUMBER/comments" \
    -f body="**CI Status:** Investigating failure..." --jq '.id' 2>/dev/null || true)
  if [ -z "$COMMENT_ID" ]; then
    echo "WARNING: failed to create CI-status PR comment on #$PR_NUMBER (auth/network?) — fix cycle will not post updates" >&2
  fi

  for ATTEMPT in $(seq 1 "$CI_MAX_ATTEMPTS"); do
    echo "CI fix attempt $ATTEMPT/$CI_MAX_ATTEMPTS..."

    # Update the single status comment (edit, not append spam)
    COMMENT_BODY="**CI Fix -- Attempt $ATTEMPT/$CI_MAX_ATTEMPTS**

Failure from \`gh run view --log-failed\`:
\`\`\`
$(tail -50 "$CI_LOG" 2>/dev/null || echo "No failure log available")
\`\`\`

Attempting fix..."
    if [ -n "$COMMENT_ID" ]; then
      gh api -X PATCH "repos/{owner}/{repo}/issues/comments/$COMMENT_ID" \
        -f body="$COMMENT_BODY" 2>/dev/null \
        || echo "WARNING: failed to update CI-status PR comment on attempt $ATTEMPT (auth/network?)" >&2
    fi

    # --- Dispatch CI fix agent ---
    # Before dispatching: check agents.min_model in .claude/zskills-config.json.
    # If set, use that model or higher (ordinal: haiku=1 < sonnet=2 < opus=3).
    # Never dispatch with a lower-ordinal model than the configured minimum.
    #
    # The /run-plan ORCHESTRATOR dispatches this agent via the Agent tool.
    # The agent does NOT use isolation: "worktree" -- the worktree already
    # exists. Instead, the agent's prompt tells it to work in $WORKTREE_PATH.
    #
    # Tracking: The worktree has .zskills-tracked (written by the orchestrator
    # in 3b.1), so the tracking hooks allow commits. The fix agent's
    # transcript will contain test commands (it runs tests before committing),
    # satisfying the test gate.
    #
    # Agent prompt (inline, not a skill):
    #
    #   CI checks failed on PR #$PR_NUMBER for branch $BRANCH_NAME.
    #   The failure log is at $CI_LOG -- read it to understand what failed.
    #
    #   FIRST: cd $WORKTREE_PATH
    #   All work happens in that directory. Do not work in any other directory.
    #
    #   Steps:
    #   1. Read $CI_LOG. Identify the failure type:
    #      - Test failure -> find the failing test, read the source, fix the code
    #      - Build error -> fix the compilation/bundling issue
    #      - Lint error -> fix the style violation
    #      - Environment issue -> may not be fixable, report and stop
    #   2. Make the minimal fix. Do not refactor or improve unrelated code.
    #   3. Run tests locally to verify the fix:
    #      - If FULL_TEST_CMD is set:
    #        TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
    #        mkdir -p "$TEST_OUT"
    #        "$FULL_TEST_CMD > "$TEST_OUT/.test-results.txt" 2>&1"
    #      - If FULL_TEST_CMD is empty: look for package.json scripts (npm test),
    #        or test files matching common patterns. If no test command can be
    #        determined, skip local testing and note it in the commit message.
    #      Read "$TEST_OUT/.test-results.txt" to check for failures.
    #   4. If tests pass, commit with message:
    #      "fix: address CI failure -- <short description of what was fixed>"
    #   5. If tests fail on the same error after one fix attempt, STOP.
    #      Do not thrash. Report what you tried and what failed.
    #
    #   Do NOT:
    #   - Weaken tests to make them pass
    #   - Skip the local test run
    #   - Touch code unrelated to the CI failure
    #   - Use git add . (stage specific files by name)

    # After fix agent completes, push to branch (auto-updates PR, re-triggers CI).
    # Error-check: if push fails (auth timeout, rate-limit, network), the
    # subsequent poll would wait on stale CI for 10 min and then falsely
    # conclude a failure. Bail loudly instead.
    cd "$WORKTREE_PATH"
    if ! git push origin "$BRANCH_NAME"; then
      echo "ERROR: fix-cycle push failed on attempt $ATTEMPT — aborting CI fix cycle." >&2
      CI_STATUS="fail"
      break
    fi

    # CI registration delay: GitHub needs 5-30s to register new check runs
    # after a push. Run the same pre-check retry loop before --watch to avoid
    # watching stale checks from the previous push.
    echo "Waiting for CI to register new checks after push..."
    for _j in 1 2 3; do
      NEW_CHECK_COUNT=$(gh pr checks "$PR_NUMBER" --json name --jq 'length' 2>/dev/null || echo "0")
      [ "$NEW_CHECK_COUNT" != "0" ] && break
      sleep 10
    done

    echo "Waiting for CI re-check..."
    timeout 600 gh pr checks "$PR_NUMBER" --watch 2>"$CI_LOG.stderr"
    WATCH_EXIT=$?
    # See the pass/fail-determination block above: `--watch`'s exit
    # code is unreliable; re-check explicitly with `gh pr checks`.
    if [ "$WATCH_EXIT" -eq 124 ]; then
      echo "CI checks timed out after fix attempt $ATTEMPT. Treating as pending."
      CI_STATUS="pending"
      break
    fi
    if gh pr checks "$PR_NUMBER" >/dev/null 2>&1; then
      echo "CI checks passed after fix attempt $ATTEMPT."
      CI_STATUS="pass"
      break
    fi
    # Re-read failure logs for next attempt
    FAILED_RUN_ID=$(gh run list --branch "$BRANCH_NAME" --status failure --limit 1 \
      --json databaseId --jq '.[0].databaseId' 2>/dev/null)
    if [ -n "$FAILED_RUN_ID" ]; then
      gh run view "$FAILED_RUN_ID" --log-failed 2>&1 | head -500 > "$CI_LOG"
    fi
  done

  # Final comment update
  if [ "$CI_STATUS" = "pass" ]; then
    FINAL_BODY="**CI Passed** after fix attempt $ATTEMPT. Ready for review."
  else
    FINAL_BODY="**CI Fix Exhausted** ($CI_MAX_ATTEMPTS attempts)

CI is still failing. Manual intervention needed.

Last failure:
\`\`\`
$(tail -50 "$CI_LOG" 2>/dev/null || echo "No failure log available")
\`\`\`"
  fi
  if [ -n "$COMMENT_ID" ]; then
    gh api -X PATCH "repos/{owner}/{repo}/issues/comments/$COMMENT_ID" \
      -f body="$FINAL_BODY" 2>/dev/null \
      || echo "WARNING: failed to post final CI-status PR comment (auth/network?)" >&2
  fi
fi
```

**Auto-merge and `.landed` upgrade:**

After CI resolution, request auto-merge and upgrade the `.landed` marker:

```bash
# --- Auto-merge: request merge when CI passes ---
# gh pr merge --auto --squash requires that auto-merge is enabled in the
# GitHub repo settings (Settings > General > Allow auto-merge). It is OFF
# by default. If not enabled, `--auto` exits non-zero with
# "Auto merge is not allowed for this repository". That's an EXPECTED
# fallback (PR stays open, agent writes status: pr-ready, user merges
# manually). Any OTHER non-zero stderr — auth, network, rate-limit, PR
# already merged, etc. — is an unexpected failure we want visible.
# So: capture stderr, inspect it, suppress only the documented expected
# error, warn loudly on anything else.
if [ "$CI_STATUS" = "pass" ] || [ "$CI_STATUS" = "none" ] || [ "$CI_STATUS" = "skipped" ]; then
  MERGE_ERR=$(gh pr merge "$PR_NUMBER" --auto --squash 2>&1 >/dev/null) || true
  if [ -n "$MERGE_ERR" ]; then
    if echo "$MERGE_ERR" | grep -qiE "auto[- ]merge is not allowed"; then
      : # expected — repo doesn't have auto-merge enabled; fall through to pr-ready
    else
      echo "WARNING: gh pr merge --auto failed with unexpected error: $MERGE_ERR" >&2
    fi
  fi
  # Give GitHub a moment to process the merge
  sleep 5
  # Distinguish "call failed" from "PR is OPEN". If the API call fails
  # (network / auth / rate-limit), retry up to 3 times with 2s/4s backoff
  # (6s max). On total failure, record UNKNOWN and propagate
  # pr-state-unknown into .landed so the state-loss is visible and
  # actionable — downstream tooling can detect the literal string.
  PR_STATE="UNKNOWN"
  for attempt in 1 2 3; do
    if STATE_OUT=$(gh pr view "$PR_NUMBER" --json state --jq '.state' 2>&1); then
      PR_STATE="$STATE_OUT"
      break
    fi
    echo "WARN: gh pr view attempt $attempt failed: $STATE_OUT" >&2
    [ $attempt -lt 3 ] && sleep $((attempt * 2))
  done
  if [ "$PR_STATE" = "UNKNOWN" ]; then
    echo "ERROR: gh pr view failed 3 times for PR #$PR_NUMBER. Recording pr-state-unknown." >&2
    LANDED_STATUS="pr-state-unknown"
  fi
else
  PR_STATE="OPEN"
fi

# --- Determine .landed status ---
# Preserve pr-state-unknown from the retry loop above — it takes
# precedence over CI/PR-state derived statuses because the underlying
# PR state is unknown and must not be silently reclassified.
if [ "${LANDED_STATUS:-}" = "pr-state-unknown" ]; then
  : # keep LANDED_STATUS=pr-state-unknown
elif [ "$CI_STATUS" = "pending" ]; then
  # Timeout: checks still running. Write pr-ready so next cron turn re-checks.
  LANDED_STATUS="pr-ready"
elif [ "$CI_STATUS" = "fail" ]; then
  LANDED_STATUS="pr-ci-failing"
elif [ "$PR_STATE" = "MERGED" ]; then
  LANDED_STATUS="landed"
else
  # PR is open -- either awaiting required reviews, or auto-merge
  # not supported. Agent's work is done either way.
  LANDED_STATUS="pr-ready"
fi

# --- Upgrade .landed marker ---
cat <<LANDED | bash scripts/write-landed.sh "$WORKTREE_PATH"
status: $LANDED_STATUS
date: $(TZ=America/New_York date -Iseconds)
source: run-plan
method: pr
branch: $BRANCH_NAME
pr: $PR_URL
ci: $CI_STATUS
pr_state: $PR_STATE
commits: $(git log main.."$BRANCH_NAME" --format='%h' | tr '\n' ' ')
LANDED

# --- Cleanup on merge ---
# When PR was merged (status: landed), call land-phase.sh to remove the worktree.
# The work is on main via the merge -- the worktree is no longer needed.
if [ "$LANDED_STATUS" = "landed" ]; then
  bash scripts/land-phase.sh "$WORKTREE_PATH"
fi
```

**`.landed` status values for PR mode:**

| Scenario | status | method | ci | pr_state |
|----------|--------|--------|----|----------|
| PR merged (auto-merge) | `landed` | `pr` | `pass`/`none`/`skipped` | `MERGED` |
| PR open, CI passed, awaiting review | `pr-ready` | `pr` | `pass`/`none`/`skipped` | `OPEN` |
| PR open, CI timed out (still running) | `pr-ready` | `pr` | `pending` | `OPEN` |
| PR open, CI failing after max attempts | `pr-ci-failing` | `pr` | `fail` | `OPEN` |
| Branch pushed, PR creation failed | `pr-failed` | `pr` | _(not set)_ | _(not set)_ |
| Rebase conflict | `conflict` | `pr` | _(not set)_ | _(not set)_ |

### Post-landing tracking

After successful landing (cherry-pick + tests pass), create the land step
marker and update the fulfillment file:
```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
printf 'phase: %s\ncompleted: %s\n' "$PHASE" "$(TZ=America/New_York date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.run-plan.$TRACKING_ID.land"

printf 'skill: run-plan\nid: %s\nplan: %s\nphase: %s\nstatus: complete\ndate: %s\n' \
  "$TRACKING_ID" "$PLAN_FILE" "$PHASE" "$(TZ=America/New_York date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/fulfilled.run-plan.$TRACKING_ID"
```

Remove the worktree's `.zskills-tracked` to avoid associating future agents with a dead pipeline:
```bash
rm -f "<worktree-path>/.zskills-tracked"
```

In `finish` mode, per-phase markers use the `phasestep` prefix (the hook
ignores these — they are informational only):
```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
printf 'phase: %s\ncompleted: %s\n' "$PHASE" "$(TZ=America/New_York date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/phasestep.run-plan.$TRACKING_ID.$PHASE.implement"
```
After the cross-phase verification in `finish` mode completes, aggregate
with `step.*` markers:
```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
for stage in implement verify report land; do
  printf 'phases: all\ncompleted: %s\n' "$(TZ=America/New_York date -Iseconds)" \
    > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.run-plan.$TRACKING_ID.$stage"
done
```

### Post-run invariants check (mandatory — mechanical gate)

Before declaring the run complete, the orchestrator MUST invoke
`scripts/post-run-invariants.sh` to assert end-state correctness. This
catches silent failures in `land-phase.sh` (e.g., a branch delete that
was accepted but didn't take effect) that would otherwise accumulate
zombies across runs. The script is an enforced gate — NOT prose the
orchestrator might "satisfy conceptually" and skip.

Invoke it with named args, unified across modes (cherry-pick and PR use
the same `FEATURE_BRANCH` variable; direct mode passes empty for both
worktree and branch):

```bash
# FEATURE_BRANCH unified across modes — both cherry-pick and PR set this
# at worktree creation time (cherry-pick uses cp-${PLAN_SLUG}-${PHASE},
# PR uses ${BRANCH_PREFIX}${PLAN_SLUG}).
bash scripts/post-run-invariants.sh \
  --worktree      "$WORKTREE_PATH" \
  --branch        "$FEATURE_BRANCH" \
  --landed-status "$LANDED_STATUS" \
  --plan-slug     "$PLAN_SLUG" \
  --plan-file     "$PLAN_FILE"
```

The script asserts 7 invariants:
1. Worktree directory gone from disk
2. Worktree removed from git's worktree registry
3. Local feature branch deleted (when `--landed-status landed`)
4. Remote feature branch deleted (when `--landed-status landed`)
5. Plan report exists at `reports/plan-<slug>.md`
6. No 🟡 In Progress rows linger in the tracker
7. Local main reconcilable with origin/main (WARN-level; user may have
   legitimate unpushed local commits)

Non-zero exit from the script means one or more invariants failed. When
that happens: STOP. Do not self-reschedule the cron. Do not advance to
the next phase. Report the specific failures to the user; they need to
investigate and fix before another run.

For direct mode (no worktree, no feature branch), pass empty strings
for `--worktree` and `--branch`; the script skips those checks.

**Unified FEATURE_BRANCH convention:** at worktree creation (Phase 2),
both cherry-pick and PR modes export a single `FEATURE_BRANCH` variable
that the invariants check reads. Cherry-pick sets it to the
auto-generated `cp-${PLAN_SLUG}-${PHASE}`; PR mode sets it to
`${BRANCH_PREFIX}${PLAN_SLUG}`. Do not use different variable names per
mode — that's how invariant #3 silently skips in cherry-pick mode.

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
