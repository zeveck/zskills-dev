---
name: briefing
argument-hint: "[report [period]] | verify | current | worktrees | [summary] | stop | next"
description: >-
  Generate a project briefing: worktree status, open checkboxes, recent commits.
  Modes: summary (default), report, verify, current, worktrees. Period: 1h, 6h, 24h, 2d, 7d.
---

# /briefing — Project Status Briefing

Gather project state and present a structured briefing.

## Runtime Check

Before executing any mode, determine which runtime is available for the
briefing helper script:

1. Try `node scripts/briefing.cjs` first (preferred).
2. If `node` is not found, try `python3 scripts/briefing.py` (fallback).
3. If neither `node` nor `python3` is available, output a clear error and stop:

   > /briefing requires Node.js or Python 3. Install one and ensure it's on PATH.
   > - Node.js: https://nodejs.org/
   > - Python: https://python.org/

Use the detected runtime for all `node scripts/briefing.cjs` commands below.
If using the Python fallback, substitute `python3 scripts/briefing.py` wherever
the instructions say `node scripts/briefing.cjs`.

## Argument Parsing

Parse `$ARGUMENTS` to determine mode, options, and optional schedule:

```
$ARGUMENTS = ""              → mode: summary
$ARGUMENTS = "summary"       → mode: summary
$ARGUMENTS = "report"        → mode: report, period: 24h
$ARGUMENTS = "report 7d"     → mode: report, period: 7d
$ARGUMENTS = "verify"        → mode: verify
$ARGUMENTS = "current"       → mode: current
$ARGUMENTS = "worktrees"     → mode: worktrees
$ARGUMENTS = "stop"          → meta: cancel scheduled briefings
$ARGUMENTS = "next"          → meta: show next scheduled briefing
$ARGUMENTS = "report 24h every day at 9am" → mode: report, schedule
```

**Period shorthand:** `1h`, `6h`, `24h` (default), `1d`, `2d`, `7d`

**Schedule detection:** If `$ARGUMENTS` contains `every <SCHEDULE>`, strip the schedule
portion and handle scheduling separately (see Scheduling section below).

## Mode Dispatch

**CRITICAL: "Present verbatim" means OUTPUT EVERY LINE.** Do not summarize,
collapse, truncate, or rephrase script output. The script's formatting IS
the presentation — it was designed to be read directly. If the output is 50
lines, show 50 lines. The user wants to SEE the data, not hear about it.
Past failure: agent received 45 lines of worktree status and collapsed it
to a 4-line summary, hiding actionable details like which logs need
extraction and which commits are unlanded.

### `summary` (default — empty or unrecognized arguments)

Quick terminal-only triage view. The helper outputs pre-formatted text.

```bash
node scripts/briefing.cjs summary --since=<period>
```

Present the output **verbatim** — it is already formatted with three buckets:
- **NEEDS ATTENTION** — worktrees needing review, unchecked checkboxes, uncommitted files
- **LANDED SINCE LAST 24H** — recent commits grouped by conventional type
- **IN FLIGHT** — possibly-active worktrees, stash entries
- **QUIET** — count of landed/empty worktrees (no action needed)
- **WARNINGS** — staleness warnings if applicable

### `report`

Generate a detailed markdown report and write it to `reports/`.

```bash
node scripts/briefing.cjs report --since=<period>
```

The helper writes the file directly and prints its path. Report includes:
- Summary counts (commits, worktrees, checkboxes)
- Needs Attention section with review checklists
- Landed on Main table
- Worktree Status table
- In Progress section

Checkbox state from earlier same-day reports is preserved automatically.

Present: "Report written to: `<path>`" with a brief summary of key findings.

### `verify`

**Purpose:** show the user everything they need to verify, with links to
open the reports directly. This is a sign-off dashboard — the user reads
this, clicks through, checks items off, done.

**This mode is NOT about worktrees.** Do not mention worktrees, do not
suggest the user verify worktrees before landing, do not include worktree
counts or status. Worktrees are for `/briefing worktrees`. Verify is
exclusively about report checkboxes — `[ ]` items in verification reports,
fix reports, and plan reports that need human sign-off.

#### Step 1 — Gather data

```bash
node scripts/briefing.cjs verify
```

The script output includes both report sign-off data and worktree data.
Use both — report checkboxes are the primary output, worktrees needing
verification are secondary (see "Worktree verification items" below).

#### Step 2 — Read the actual report files

The script gives file paths and counts. That's not enough — the user needs
to see the actual checkbox text. For each report file with unchecked items,
READ the file and extract every `[ ]` line with its surrounding context
(the heading it's under, any verification instructions).

#### Step 3 — Build the output with links

Get the dev server port:
```bash
bash scripts/port.sh
```

For each report file, construct a viewer URL:
`http://localhost:<port>/viewer/?file=<path>`

Present the output in this format:

```
Pending sign-offs: N items across M reports

FIX_REPORT.md — 33 items
  http://localhost:8080/viewer/?file=FIX_REPORT.md

  UI / UX Fixes:
    [ ] Block Rotation — right-click, select Rotate, check ports
    [ ] Tooltip positioning — hover near canvas edge, verify no clipping

  Simulation Fixes:
    [ ] Solver tolerance — run voltage-divider, verify output within 1e-6

reports/plan-block-expansion.md — 9 items
  http://localhost:8080/viewer/?file=reports/plan-block-expansion.md

  Phase 1:
    [ ] IfBlock visible in Block Explorer
    [ ] If/IfAction wiring works on canvas

VERIFICATION_REPORT.md — 2 items
  http://localhost:8080/viewer/?file=VERIFICATION_REPORT.md

  [ ] Variable viewer panel sign-off
  [ ] Toolstrip button sign-off
```

**Key formatting rules:**
- The terminal output is a DIRECTORY, not a replica. Show the report name,
  item count, viewer URL, and section summaries — not every checkbox line.
  The user clicks through to the report to do the actual sign-off work.
- Group by report file, with section summaries (e.g., "UI / UX Fixes: 5
  items", "Simulation: 3 items")
- The viewer URL is the actionable part — make it prominent

#### Worktree verification items

If the script's output includes worktrees needing verification before
landing, include them — they ARE verification items. But flag them as
unusual: a worktree needing user verification at `/briefing verify` time
means `/run-plan` or `/fix-issues` didn't complete its verification phase.

```
⚠ Worktree needing verification (suggests incomplete skill run):
  agent-a5217dbd (SLX Export Phase 1) — 6 commits, not yet verified/landed
```

This surfaces the problem rather than hiding it.

Empty state: `ALL CLEAR — no pending sign-off items.`

### `current`

Show what's actively in flight right now.

```bash
node scripts/briefing.cjs current
```

Present the output **verbatim**. Sections:
- **POSSIBLY ACTIVE** — worktrees modified in last 2 hours
- **FINISHED, NOT LANDED** — worktrees with commits, inactive > 2h
- **EMPTY WORKTREES** — zero commits, safe to remove
- **UNCOMMITTED ON MAIN** — modified/deleted/untracked file counts
- **STASH** — git stash entries or "(empty)"
- **LONG-RUNNING BRANCHES** — named worktrees with commits ahead of main

### `worktrees`

Detailed worktree analysis with cleanup readiness. Read-only — shows what's
safe to remove but does not remove anything.

```bash
node scripts/briefing.cjs worktrees-status
```

Present the output **verbatim**. Sections:
- **SAFE TO REMOVE** — empty worktrees or all commits verified on main, no unextracted logs. Includes copy-pasteable `git worktree remove` commands.
- **NEEDS LOG EXTRACTION FIRST** — commits are on main but `.claude/logs/` has modified files. Shows which logs need extraction and how.
- **NOT SAFE** — has commits not found on main. Shows unlanded commit list.
- **NAMED / LONG-RUNNING** — named worktrees (physics module, etc.), never auto-remove.
- **ORPHANED** — directories on disk but not registered with `git worktree list`.

**Important:** Always extract logs before removing any worktree. Logs document how work was done — they are part of the project, not disposable artifacts.

## Data Gathering

The agent runs `node scripts/briefing.cjs <subcommand>` and captures stdout.

| Subcommand   | Output   | Description                              |
|-------------|----------|------------------------------------------|
| `worktrees` | JSON     | All worktrees with classification        |
| `checkboxes`| JSON     | Unchecked `[ ]` items from report files  |
| `commits`   | JSON     | Categorized commits on main              |
| `summary`   | Text     | Pre-formatted three-bucket triage view   |
| `report`    | File     | Writes markdown report, prints path      |
| `verify`    | Text     | Pre-formatted verification checklist     |
| `current`   | Text     | Pre-formatted in-flight status           |
| `worktrees-status` | Text | Cleanup readiness report             |

## Worktree Categories

Each worktree is classified into exactly one category:

- **`landed-full`** — `.landed` file with `status: full` (fix-issues cherry-pick, all commits on main) or `status: landed` (run-plan cherry-pick or merged PR)
- **`landed-partial`** — `.landed` file with `status: partial` (some commits skipped, needs review)
- **`landed-pr-ready`** — `.landed` file with `status: pr-ready` (PR is open; worktree is safe to remove, remote branch must NOT be deleted — it supports the open PR)
- **`landed-pr-needs-attention`** — `.landed` file with `status: pr-ci-failing`, `status: pr-failed`, or `status: conflict` (PR-mode errors that need manual action)
- **`done-needs-review`** — No `.landed`, has commits, inactive > 2 hours
- **`possibly-active`** — No `.landed`, modified within last 2 hours
- **`empty`** — No `.landed`, zero commits ahead of main
- **`named`** — Not an `agent-*` worktree (e.g., physics module)
- **`orphaned`** — Directory exists on disk but not in `git worktree list`

## Scheduling

The `/briefing` skill supports recurring execution via cron.

### Setting a Schedule

If `$ARGUMENTS` contains `every <SCHEDULE>`:

1. Strip the schedule portion from arguments to get the base mode
2. Create a cron using CronCreate:
   - `install_command`: `/briefing <base-mode-args>`
   - `schedule`: parsed from `<SCHEDULE>` (e.g., "day at 9am" → `0 9 * * *`)
3. Present confirmation with session-scope warning:

```
Scheduled: /briefing <mode> runs every <schedule>

WARNING: This schedule is tied to this session. If the session ends, the schedule is lost.
```

### `stop` — Cancel Scheduled Briefings

1. List crons with CronList
2. Filter for briefing-related crons (install_command starts with `/briefing`)
3. Delete each with CronDelete
4. Confirm: "Cancelled N briefing schedule(s)."

### `next` — Show Next Fire Times

1. List crons with CronList
2. Filter for briefing-related crons
3. Show each with its next fire time
4. If none: "No briefing schedules active."

### Common Schedules

| Input | Cron | Description |
|-------|------|-------------|
| `every hour` | `0 * * * *` | Top of every hour |
| `every 2h` | `0 */2 * * *` | Every 2 hours |
| `every day at 9am` | `0 9 * * *` | Daily at 9 AM |
| `every weekday at 9am` | `0 9 * * 1-5` | Weekdays at 9 AM |

## Report Template Reference

The `report` subcommand writes this markdown structure:

```markdown
# Briefing Report — YYYY-MM-DD HH:MM ET
Period: <since> -> now

## Summary
- N commits landed on main
- N worktrees: X need review, Y in flight, Z landed
- N unchecked sign-off items across M reports

## Needs Attention

### [ ] Review: <worktree-name> (N commits)
Commits:
- `hash` subject
Last modified: <relative time>

### [ ] Sign-off: <report-file> (N unchecked items)
- [ ] item text (line NN)

## Landed on Main
| Type | Hash | Subject | Date |
|------|------|---------|------|

## Worktree Status
| Worktree | Category | Commits | Last Modified | Notes |
|----------|----------|---------|---------------|-------|

## In Progress
| Worktree | Commits | Last Modified | Summary |
|----------|---------|---------------|---------|
```

Checkboxes marked `[x]` in earlier same-day reports are preserved in new reports.

## Staleness Warnings

The `summary` subcommand appends warnings when:
- No briefing report has ever been generated
- The most recent briefing report is older than 48 hours
- A `done-needs-review` worktree is older than 7 days (stale)

## Z Skills Update Check

If a Z Skills repo clone exists (`zskills/` in project root, or
`/tmp/zskills`), the `summary` and `report` modes should check for
upstream updates:

```bash
ZSKILLS_DIR=""
[ -d zskills/.git ] && ZSKILLS_DIR=zskills
[ -d /tmp/zskills/.git ] && ZSKILLS_DIR=/tmp/zskills
if [ -n "$ZSKILLS_DIR" ]; then
  git -C "$ZSKILLS_DIR" fetch --dry-run 2>&1 | grep -qE '^\s+[a-f0-9]+\.\.[a-f0-9]+' && echo "updates available"
fi
```

If updates are available, append to the output:
> Z Skills: updates available (`/update-zskills`)

## Edge Cases

- **Orphaned worktrees** — directories in `.claude/worktrees/` or `worktrees/` not
  registered with `git worktree list`. Shown with `orphaned` category.
- **Missing `reports/` directory** — created automatically when writing a report.
- **Recency filter** — checkbox scanning only checks files modified in last 30 days
  (or top 10 most recent briefing files) to avoid scanning stale history.
