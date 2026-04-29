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
- **pr** (optional) — land each fixed issue via a per-issue PR on a named
  branch (`fix/issue-NNN`) in a dedicated worktree. Overrides the config
  default `execution.landing`.
- **direct** (optional) — land each fixed issue by fast-forward-merging
  its per-issue worktree branch (`fix-issue-NNN`) into main (no PR, no
  cherry-pick extraction). Overrides the config default. Incompatible
  with `execution.main_protected: true`.

**Detection:** scan `$ARGUMENTS` for:
- `stop` (case-insensitive) — cancel cron and exit (highest precedence)
- `next` (case-insensitive) — check schedule and exit
- `sync` (case-insensitive) — sync trackers, verify/close fixed issues, and exit
- `plan` (case-insensitive) — draft plans for skipped issues and exit
- `now` (case-insensitive) — run immediately
- `auto` (case-insensitive) — autonomous mode (behavior varies by context)
- `every` followed by a schedule expression — scheduling mode
- `pr` (case-insensitive) — PR landing mode (per-issue branches + PRs)
- `direct` (case-insensitive) — direct landing mode (commit on main)

**Landing mode resolution** (same pattern as `/run-plan`):
1. Explicit argument wins: `pr` or `direct` in `$ARGUMENTS`
2. Config default: read `.claude/zskills-config.json` `execution.landing` field
3. Fallback: `cherry-pick`

```bash
# Detect landing mode (same logic as /run-plan)
LANDING_MODE="cherry-pick"
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[pP][rR]($|[[:space:]]) ]]; then
  LANDING_MODE="pr"
elif [[ "$ARGUMENTS" =~ (^|[[:space:]])[dD][iI][rR][eE][cC][tT]($|[[:space:]]) ]]; then
  LANDING_MODE="direct"
else
  CONFIG_FILE="$PROJECT_ROOT/.claude/zskills-config.json"
  if [ -f "$CONFIG_FILE" ]; then
    CONFIG_CONTENT=$(cat "$CONFIG_FILE")
    if [[ "$CONFIG_CONTENT" =~ \"landing\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
      CFG_LANDING="${BASH_REMATCH[1]}"
      [ -n "$CFG_LANDING" ] && LANDING_MODE="$CFG_LANDING"
    fi
  fi
fi

# Validation: direct + main_protected -> error
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

**Strip `pr`/`direct` from arguments** before parsing issue numbers, focus,
or other tokens (same pattern as stripping `auto`, `now`, etc.). The
downstream N/focus parser must not see `pr` or `direct` as an issue count
or domain name.

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
- `/fix-issues 5 auto pr` — autonomous sprint, per-issue PR landing
- `/fix-issues 3 auto direct` — autonomous sprint, land commits on main directly

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

**Before dispatching any Agent:** check `agents.min_model` in `.claude/zskills-config.json`.
If set, use that model or higher (ordinal: haiku=1 < sonnet=2 < opus=3). Never dispatch
with a lower-ordinal model than the configured minimum.

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

1. **Find skipped issues from `plans/SPRINT_REPORT.md`.** Scan the entire
   sprint report for issue numbers under "Skipped" / "Too Complex" /
   "Remaining Open" headings. Use grep to extract candidate numbers
   (handles bare `#NNN`, ranges like `#148-#168`, and `#NNN, #MMM` lists):

   ```bash
   grep -nE '#[0-9]+' plans/SPRINT_REPORT.md | grep -iE 'skip|complex|remain'
   ```

   Then for each candidate `#N`:
   - Check `plans/` for an existing executable plan covering it:
     `grep -l "#$N\b" plans/*.md` (existing plan = skip)
   - Check GitHub state: `gh issue view "$N" --json state -q .state`
     (`OPEN` = candidate; `CLOSED` = skip)

   Build the working list of `needs-plan` issues from candidates that
   have NO existing plan AND are still `OPEN`. Skip the rest.

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

4. **For each selected issue**, create a delegation requirement marker and
   then dispatch `/draft-plan`. The marker goes under fix-issues' own
   per-sprint subdir ($PIPELINE_ID) — the parent reconciles child
   fulfillment in its own scope:
   ```bash
   . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
   MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
   mkdir -p "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
   printf 'skill: draft-plan\nparent: fix-issues\nissue: %s\ndate: %s\n' \
     "$ISSUE_NUMBER" "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
     > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/requires.draft-plan.$ISSUE_NUMBER"
   ```
   Then dispatch `/draft-plan` with:
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

### Sprint tracking sentinel

When mode is sprint (N provided), construct the per-sprint unique
`$SPRINT_ID` and `$PIPELINE_ID` FIRST (before any other tracking write),
then create the pipeline sentinel:

```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
mkdir -p "$MAIN_ROOT/.zskills/tracking"

# Per-sprint unique ID (per Phase 1 design doc OQ3). Prevents concurrent
# fix-issues sessions from colliding on the literal "sprint" suffix. The
# ISSUE_TITLE slug is a human-readable tag; the UTC timestamp guarantees
# uniqueness across concurrent sprints on the same host.
ISSUE_TITLE_SLUG=$(printf '%s' "${ISSUE_TITLE:-sprint}" | tr -cd 'a-z0-9' | head -c 8)
[ -z "$ISSUE_TITLE_SLUG" ] && ISSUE_TITLE_SLUG="sprint"
SPRINT_ID="sprint-$(date -u +%Y%m%d-%H%M%S)-$ISSUE_TITLE_SLUG"
PIPELINE_ID="fix-issues.$SPRINT_ID"
PIPELINE_ID=$(bash "$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh" "$PIPELINE_ID")
# Recover SPRINT_ID after sanitization (strip the "fix-issues." prefix).
SPRINT_ID="${PIPELINE_ID#fix-issues.}"
mkdir -p "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"

if [ ! -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/pipeline.fix-issues.$SPRINT_ID" ]; then
  printf 'skill: fix-issues\nmode: sprint\ncount: %s\nfocus: %s\nstartedAt: %s\n' \
    "$N" "${FOCUS:-default}" "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
    > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/pipeline.fix-issues.$SPRINT_ID"
fi
```

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

2. **Find gaps** between GitHub open issues and plan tracker files. List
   the trackers, then for each open GH issue number check whether it
   appears in any tracker:

   ```bash
   ls plans/*ISSUES*.md plans/ISSUES_PLAN.md 2>/dev/null

   gh issue list --state open --limit 500 --json number -q '.[].number' \
     | while read -r N; do
         if ! grep -q "#$N\b" plans/*ISSUES*.md plans/ISSUES_PLAN.md 2>/dev/null; then
           echo "GAP: #$N not in any tracker"
         fi
       done
   ```

3. **Tally label distribution** to see current spread:

   ```bash
   gh issue list --state open --limit 500 --json labels \
     -q '.[].labels[].name' | sort | uniq -c | sort -rn
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

### Post-preflight tracking

After Phase 1 (preflight + sync + research) is complete:
```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
printf 'completed: %s\n' "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.fix-issues.$SPRINT_ID.preflight"
```

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

### Post-prioritize tracking

After Phase 2 (prioritize) is complete:
```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
printf 'completed: %s\nissueCount: %d\n' "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" "$ISSUE_COUNT" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.fix-issues.$SPRINT_ID.prioritize"
```

## Phase 3 — Execute (agent teams in worktrees)

**All modes create a per-issue worktree via `.claude/skills/create-worktree/scripts/create-worktree.sh`
BEFORE dispatching the fix agent, and dispatch agents WITHOUT
`isolation: "worktree"`.** The distinction between modes is not *how* the
worktree is created — it is *what happens at landing*: `cherry-pick`
extracts commits from the worktree branch onto main, `direct` fast-forwards
the worktree branch into main (Phase 6 detail), and `pr` opens a PR per
issue. See the "Worktree setup (cherry-pick and direct modes)" subsection
below for the baseline `create-worktree.sh` invocation, and the "PR mode
(Phase 3)" subsection for PR-mode-specific branch naming.

**Before dispatching any fix Agent:** check `agents.min_model` in `.claude/zskills-config.json`.
If set, use that model or higher (ordinal: haiku=1 < sonnet=2 < opus=3). Never dispatch
with a lower-ordinal model than the configured minimum.

**1 issue per agent, parallel dispatch.** Each issue gets its own agent
in its own pre-created worktree (materialised via `create-worktree.sh`
before dispatch for all modes — see "Worktree setup" below). **Dispatch at
most 3 worktree agents per message.** If you have more than 3, dispatch the
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

**Declare pipeline ID** early in execution (before any git operation).
`$PIPELINE_ID` was constructed at the top of Phase 1 ("Sprint tracking
sentinel") as `fix-issues.$SPRINT_ID`:
```bash
echo "ZSKILLS_PIPELINE_ID=$PIPELINE_ID"
```

The echo associates the orchestrator session with this pipeline (read by hook
from transcript). Each worktree's `.zskills-tracked` file is written
atomically by `create-worktree.sh --pipeline-id` during worktree
materialisation (see "Worktree setup" below).

Each agent follows this fix workflow:

1. Read the issue body (included in prompt) and relevant code
2. Reproduce the bug (unit test or manual)
3. Implement the fix
4. Write regression tests (unit and/or E2E as appropriate)
5. Run `$FULL_TEST_CMD` (resolve via
   `. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"`
   if you don't already have it in your environment) — all suites must pass
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

The implementation agent does NOT commit. The verification agent runs the full
test suite and commits if verification passes. This ensures the hook's test
gate is satisfied. The approval gate is landing to main (Phase 6).

### Worktree setup (cherry-pick and direct modes)

For `LANDING_MODE == cherry-pick` (default) and `LANDING_MODE == direct`,
create the per-issue worktree via `create-worktree.sh` BEFORE dispatching
the fix agent. The default branch name is `fix-issue-NNN` (derived from
`--prefix fix-issue` + the issue slug); the worktree lives at
`${WORKTREE_ROOT:-/tmp}/<project-name>-fix-issue-NNN`. PR mode overrides
the branch name to `fix/issue-NNN` via `--branch-name` — see that
subsection below.

```bash
ISSUE_NUM=42
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
# Resume detection stays directory-based: an existing fix worktree means
# we're resuming the same issue across cron turns.
WORKTREE_PATH="/tmp/$(basename "$MAIN_ROOT")-fix-issue-${ISSUE_NUM}"
if [ -d "$WORKTREE_PATH" ]; then
  echo "Resuming existing fix worktree at $WORKTREE_PATH"
else
  WORKTREE_PATH=$(bash "$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/create-worktree.sh" \
    --prefix fix-issue \
    --purpose "fix-issues; issue=${ISSUE_NUM}" \
    --pipeline-id "$PIPELINE_ID" \
    "${ISSUE_NUM}")
  RC=$?
  if [ "$RC" -ne 0 ]; then
    echo "create-worktree failed (rc=$RC) for /fix-issues cherry-pick/direct mode" >&2
    exit "$RC"
  fi
fi
# create-worktree.sh owns pre-flight prune+fetch+ff-merge, the underlying
# safe add, .zskills-tracked (from --pipeline-id), and .worktreepurpose
# writes. The orchestrator does NOT separately write the tracking marker
# — the worktree directory does not exist until create-worktree.sh
# materialises it, so any pre-dispatch write would fail.
```

For grouped interrelated issues (same root cause or same files from
Phase 2 grouping), pass the **lowest issue number** as the slug — all
grouped issues share that one worktree. Mirrors the PR-mode convention.

**Dispatching fix agents in cherry-pick/direct mode:** Dispatch agents
WITHOUT `isolation: "worktree"` — the worktree already exists. The agent
prompt must include `FIRST: cd $WORKTREE_PATH` as the mandatory first
action. Without this instruction, the agent starts in the main repo.

### PR mode (Phase 3)

When `LANDING_MODE == pr`, each issue gets its **own named branch and
worktree** (one PR per issue, unlike `/run-plan` PR mode where all phases
share one branch).

**Differences from `/run-plan` PR mode:**
- Branch prefix is hardcoded `fix/` (not config `branch_prefix`)
- Branch name uses the issue number, not a plan slug
- Worktree path uses `fix-issue-NNN`, not `pr-<plan-slug>`
- One worktree per issue (not one per plan)

**Branch naming:** `fix/issue-NNN` where `NNN` is the GitHub issue number.

**Worktree path:** `/tmp/<project-name>-fix-issue-NNN`

```bash
ISSUE_NUM=42
BRANCH_NAME="fix/issue-${ISSUE_NUM}"
PROJECT_NAME=$(basename "$PROJECT_ROOT")
WORKTREE_PATH="/tmp/${PROJECT_NAME}-fix-issue-${ISSUE_NUM}"

MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
# Resume detection stays directory-based (R2-M1): an existing fix worktree
# means we're resuming the same issue across cron turns.
if [ -d "$WORKTREE_PATH" ]; then
  echo "Resuming existing fix worktree at $WORKTREE_PATH"
else
  WORKTREE_PATH=$(bash "$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/create-worktree.sh" \
    --prefix fix-issue \
    --branch-name "fix/issue-${ISSUE_NUM}" \
    --allow-resume \
    --purpose "fix-issues; issue=${ISSUE_NUM}" \
    --pipeline-id "$PIPELINE_ID" \
    "${ISSUE_NUM}")
  RC=$?
  if [ "$RC" -ne 0 ]; then
    echo "create-worktree failed (rc=$RC) for /fix-issues PR mode" >&2
    exit "$RC"
  fi
fi
# create-worktree.sh owns pre-flight prune+fetch+ff-merge, the
# underlying safe add (with ZSKILLS_ALLOW_BRANCH_RESUME=1 set via
# --allow-resume), .zskills-tracked (from --pipeline-id), and
# .worktreepurpose writes.
```

**Dispatching fix agents in PR mode:** Dispatch agents WITHOUT
`isolation: "worktree"` — the worktree already exists. The agent prompt
must include `FIRST: cd $WORKTREE_PATH` as the mandatory first action.
Without this instruction, the agent starts in the main repo.

For grouped interrelated issues (same root cause or same files from
Phase 2 grouping), pick the LOWEST issue number as the branch identifier
(`fix/issue-NNN`) and include all grouped issues in that one worktree.
The `.landed` marker's `issue:` field records the primary issue; group
members are listed separately in the sprint report.

### Post-execute tracking

After Phase 3 (execute) is complete — all agents have returned:
```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
printf 'completed: %s\n' "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.fix-issues.$SPRINT_ID.execute"
```

## Phase 4 — Review

### Pre-verification tracking

Before dispatching verification agents, create a delegation requirement
marker so the hook can enforce that verification actually runs. The
marker lives in fix-issues' own per-sprint subdir (same pattern as
run-plan's delegation lock in Phase 3 of the tracking plan):
```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
mkdir -p "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
printf 'skill: verify-changes\nparent: fix-issues\nmode: sprint\ndate: %s\n' \
  "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/requires.verify-changes.$SPRINT_ID"
```

### Dispatch protocol

**Check your tool list.** If `Agent` (or `Task`) is in your tool list,
you are at top level — dispatch fresh verification subagents per the
protocol below. The implementation subagents (in their per-issue
worktrees) and the verification subagent are sibling subagents of you,
the top-level orchestrator. The verifier has no memory of what the
implementer did because they're separate contexts.

**If you do NOT have the `Agent` tool**, you are running as a subagent
yourself (Claude Code subagents have no Agent tool, by Anthropic's
design at https://code.claude.com/docs/en/sub-agents). Run `/verify-changes
worktree` inline in your current context, once per worktree. This is
single-context inline verification — flag in the report whether you
were fresh relative to the implementer or not. This fallback is mostly
defensive since /fix-issues typically runs at top level.

**Before dispatching any verification Agent:** check `agents.min_model` in
`.claude/zskills-config.json`. If set, use that model or higher (ordinal:
haiku=1 < sonnet=2 < opus=3). Never dispatch with a lower-ordinal model than
the configured minimum.

After each agent completes, **dispatch a fresh agent** to run `/verify-changes
worktree` in its worktree. Do NOT run verification yourself — you wrote
the dispatch prompts, so you have implementer bias. The verification agent
must be a fresh agent with no memory of the implementation.

This delegates the full review workflow (diff review, test coverage audit,
test run, manual verification, fix & re-verify cycle) to a separate agent.

Report the review results to the user.

### Post-verify tracking

After Phase 4 (verify) is complete — all verification agents have returned:
```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
printf 'completed: %s\n' "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.fix-issues.$SPRINT_ID.verify"
```

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

### Post-report tracking

After Phase 5 (report) is complete:
```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
printf 'completed: %s\n' "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.fix-issues.$SPRINT_ID.report"
```

## Phase 6 — Land

**Landing mode dispatch:**
- `LANDING_MODE == cherry-pick` — default path (below).
- `LANDING_MODE == pr` — see "PR mode landing" subsection. One PR per
  fixed issue, with `Fixes #NNN` linking.
- `LANDING_MODE == direct` — see "Direct mode landing" in
  [modes/direct.md](modes/direct.md). Per-issue rebase + FF-merge of
  `fix-issue-NNN` into main, then push. Requires
  `execution.main_protected: false` (enforced at Phase 1 argument parse).

**Auto-flag gating depends on landing mode.** Without `auto`:

- **`LANDING_MODE == pr`:** run [modes/pr.md](modes/pr.md) end-to-end
  except for the final auto-merge call. Rebase, push, PR creation,
  CI polling, and the fix cycle ALL run regardless of `auto` — they
  either surface review (PR creation) or are reversible (the fix cycle
  pushes commits back to the feature branch, which the user can revert).
  This matches the canonical pattern that `/commit pr`, `/do pr`, and
  `/run-plan` PR mode already follow: hand the user the cleanest possible
  PR to review. **Only `gh pr merge --auto --squash` is gated on `auto`**;
  without it, the PR sits at status `pr-ready` (or `pr-ci-failing` if
  fix-cycle was exhausted) awaiting human review and merge on GitHub.
- **`LANDING_MODE == cherry-pick`:** Sprint complete. Output:
  > Sprint complete. Report written to `SPRINT_REPORT.md`.
  > Run `/fix-report` to review fixes, land to main, and close issues.

  Cherry-picks land via `/fix-report`'s interactive walk-through.
- **`LANDING_MODE == direct`:** Sprint complete (same handoff as
  cherry-pick). Direct mode FF-merges into main; never run that without
  explicit `auto` consent.

With `auto`, all three modes run their full landing procedure end-to-end
including the merge call (modes/pr.md auto-merge, modes/cherry-pick.md
cherry-pick to main, modes/direct.md FF-merge into main).

Landing is per-issue. Select the mode based on the landing-mode
detection from the Arguments section, then **read the corresponding
mode file in full and follow its procedure end-to-end** per-issue.
Do not proceed until you have read the file.

- **cherry-pick** (default) → [modes/cherry-pick.md](modes/cherry-pick.md)
- **direct** → [modes/direct.md](modes/direct.md)
- **PR mode** → [modes/pr.md](modes/pr.md)

All mode files assume Phase 5 (Sprint Report) has written the
persistent report and Phase 4 (Review) has populated the
before-landing summary.

### Post-land tracking

After Phase 6 (land) is complete:
```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
printf 'completed: %s\n' "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.fix-issues.$SPRINT_ID.land"
```

After the sprint completes (whether all issues landed or the sprint ended),
clean up the sentinel:

```bash
rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/pipeline.fix-issues.$SPRINT_ID"
```

Also remove `.zskills-tracked` from each worktree that was used.

## Failure Protocol

**Read [references/failure-protocol.md](references/failure-protocol.md)**
for crash handling, cron cleanup, worktree restoration, and sprint
failure reporting.

## Key Rules

- **Worktrees only** — all fixes happen in isolated worktrees, never in the
  main working tree.
- **The verification agent commits after passing tests** — the implementation
  agent does not commit. This satisfies the hook's test gate.
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
- **`$FULL_TEST_CMD` before every commit** (resolve via
  `. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"`
  if you don't already have it in your environment) — not just `npm test`.
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
