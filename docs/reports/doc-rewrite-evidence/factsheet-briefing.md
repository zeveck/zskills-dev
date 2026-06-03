# Factsheet — docs/skills/briefing.md

Every factual claim in the rewritten doc, paired with the verbatim source
line that backs it. Source = `skills/briefing/SKILL.md`; companion edges from
`docs/reports/doc-rewrite-evidence/COMPANIONS.md`.

Citation format: `<file>:LINE: "<verbatim quote>"`.

PLAN-TEXT-DRIFT note: the `argument-hint` (line 3) lists the period set as
`1h, 6h, 24h, 2d, 7d` (omits `1d`), while the body (line 41) lists
`1h, 6h, 24h (default), 1d, 2d, 7d`. Per the rubric R-template item 4
("the body wins"), the doc includes `1d`. The blockquote/summary line in the
doc mirrors the body's period set, not the argument-hint's.

---

## Blockquote / summary

**Doc:** "Generate a project briefing: worktree status, open checkboxes, recent commits. Modes: summary (default), report, verify, current, worktrees. Period: 1h, 6h, 24h, 1d, 2d, 7d."

- `skills/briefing/SKILL.md:5: "Generate a project briefing: worktree status, open checkboxes, recent commits."`
- `skills/briefing/SKILL.md:6: "Modes: summary (default), report, verify, current, worktrees. Period: 1h, 6h, 24h, 2d, 7d."` (modes)
- `skills/briefing/SKILL.md:41: "**Period shorthand:** \`1h\`, \`6h\`, \`24h\` (default), \`1d\`, \`2d\`, \`7d\`"` (period set — body wins over argument-hint, which omits `1d`)

---

## What it does

**Doc:** "`/briefing` gathers the current state of your project and presents it as a structured briefing."

- `skills/briefing/SKILL.md:13: "Gather project state and present a structured briefing."`

**Doc:** "It looks at three things: the status of your worktrees, the open sign-off checkboxes (`[ ]` items) sitting in report files, and the recent commits that have landed on `main`."

- `skills/briefing/SKILL.md:5: "Generate a project briefing: worktree status, open checkboxes, recent commits."`
- `skills/briefing/SKILL.md:279: "| \`commits\`   | JSON     | Categorized commits on main              |"` (commits are on main)
- `skills/briefing/SKILL.md:278: "| \`checkboxes\`| JSON     | Unchecked \`[ ]\` items from report files  |"` (checkboxes = `[ ]` items in report files)

**Doc:** "By default it prints a short triage view to the terminal, grouped into buckets: what needs attention ... what has landed recently, what is still in flight, and what is quiet and needs no action."

- `skills/briefing/SKILL.md:57: "### \`summary\` (default — empty or unrecognized arguments)"`
- `skills/briefing/SKILL.md:58: "Quick terminal-only triage view. The helper outputs pre-formatted text."`
- `skills/briefing/SKILL.md:70-74: "- **NEEDS ATTENTION** — worktrees needing review, unchecked checkboxes, uncommitted files / - **LANDED SINCE LAST 24H** — recent commits grouped by conventional type / - **IN FLIGHT** — possibly-active worktrees, stash entries / - **QUIET** — count of landed/empty worktrees (no action needed)"`

**Doc:** "The output is shown to you exactly as the helper produces it — it is not summarized or rephrased."

- `skills/briefing/SKILL.md:48: "**CRITICAL: \"Present verbatim\" means OUTPUT EVERY LINE.** Do not summarize,"`
- `skills/briefing/SKILL.md:49: "collapse, truncate, or rephrase script output."`
- `skills/briefing/SKILL.md:69: "Present the output **verbatim** — it is already formatted with three buckets:"`

**Doc:** "summary (the default) — the short, terminal-only triage view described above."

- `skills/briefing/SKILL.md:57: "### \`summary\` (default — empty or unrecognized arguments)"`
- `skills/briefing/SKILL.md:58: "Quick terminal-only triage view."`

**Doc:** "report — a detailed Markdown report written to a file. The helper prints the path; checkboxes you already ticked off in an earlier same-day report are carried forward automatically."

- `skills/briefing/SKILL.md:78: "Generate a detailed markdown report and write it to \`$ZSKILLS_AUDIT_DIR/\`."`
- `skills/briefing/SKILL.md:89: "The helper writes the file directly and prints its path."`
- `skills/briefing/SKILL.md:96: "Checkbox state from earlier same-day reports is preserved automatically."`

**Doc:** "verify — a sign-off dashboard of the open `[ ]` items across your report files, with the file paths so you can open each one, check the items, and be done. This mode is about report sign-offs, not worktrees."

- `skills/briefing/SKILL.md:102-104: "**Purpose:** show the user everything they need to verify, with links to / open the reports directly. This is a sign-off dashboard — the user reads / this, clicks through, checks items off, done."`
- `skills/briefing/SKILL.md:109-110: "**This mode is NOT about worktrees.** Do not mention worktrees ... Verify is / exclusively about report checkboxes — \`[ ]\` items in verification reports,"`
- `skills/briefing/SKILL.md:136: "For each report file, include the file path so the user can open it."`

**Doc:** "current — what is actively in flight right now: worktrees touched in the last couple of hours, worktrees that are finished but not yet landed, empty worktrees, uncommitted changes on `main`, and any stashes."

- `skills/briefing/SKILL.md:195: "Show what's actively in flight right now."`
- `skills/briefing/SKILL.md:207-212: "- **POSSIBLY ACTIVE** — worktrees modified in last 2 hours / - **FINISHED, NOT LANDED** — worktrees with commits, inactive > 2h / - **EMPTY WORKTREES** — zero commits, safe to remove / - **UNCOMMITTED ON MAIN** — modified/deleted/untracked file counts / - **STASH** — git stash entries or \"(empty)\""`

**Doc:** "worktrees — a detailed worktree inventory with cleanup readiness: which worktrees are safe to remove (with copy-pasteable removal commands), which still need their logs extracted first, and which still hold unlanded commits. It only reports — it never removes anything."

- `skills/briefing/SKILL.md:216-217: "Detailed worktree analysis with cleanup readiness. Read-only — shows what's / safe to remove but does not remove anything."`
- `skills/briefing/SKILL.md:229: "- **SAFE TO REMOVE** — empty worktrees or all commits verified on main, no unextracted logs. Includes copy-pasteable \`git worktree remove\` commands."`
- `skills/briefing/SKILL.md:230: "- **NEEDS LOG EXTRACTION FIRST** — commits are on main but \`.claude/logs/\` has modified files."`
- `skills/briefing/SKILL.md:231: "- **NOT SAFE** — has commits not found on main. Shows unlanded commit list."`

**Doc:** "All modes are read-only: `/briefing` tells you the state of the project, it does not change it."

- `skills/briefing/SKILL.md:216-217: "Detailed worktree analysis with cleanup readiness. Read-only — shows what's / safe to remove but does not remove anything."` (worktrees is read-only)
- `skills/briefing/SKILL.md:13: "Gather project state and present a structured briefing."` (the skill gathers + presents; no mode in SKILL.md performs a mutating action — summary/report/verify/current/worktrees all only read and present; report's only write is its own report file)

**Doc:** "The report mode takes an optional time period that bounds how far back it looks: `1h`, `6h`, `24h` (the default), `1d`, `2d`, or `7d`."

- `skills/briefing/SKILL.md:41: "**Period shorthand:** \`1h\`, \`6h\`, \`24h\` (default), \`1d\`, \`2d\`, \`7d\`"`
- `skills/briefing/SKILL.md:38: "$ARGUMENTS = \"report 7d\"     → mode: report, period: 7d"` (period attaches to `report` in the documented argument grammar)
- `skills/briefing/SKILL.md:86: "python3 \"$ZSKILLS_SKILLS_ROOT/briefing/scripts/briefing.py\" report --since=<period>"` (report passes --since=<period>)

  Scope note: the documented argument grammar (lines 29-39) attaches a period
  only to `report`. The doc was corrected to scope period to `report` mode
  alone; an earlier draft overstated it across verify/current/worktrees, which
  take no `--since` flag (lines 120, 203, 225). See PLAN-TEXT-DRIFT #2.

**Doc:** "`/briefing` can also run on a schedule — append `every SCHEDULE` to any mode to have it run recurrently (the schedule is tied to the current session)."

- `skills/briefing/SKILL.md:302: "The \`/briefing\` skill supports recurring execution via cron."`
- `skills/briefing/SKILL.md:43-44: "**Schedule detection:** If \`$ARGUMENTS\` contains \`every <SCHEDULE>\`, strip the schedule / portion and handle scheduling separately"`
- `skills/briefing/SKILL.md:319: "WARNING: This schedule is tied to this session. If the session ends, the schedule is lost."`

**Doc:** "The `stop` and `next` subcommands cancel a scheduled briefing and show when the next one will fire."

- `skills/briefing/SKILL.md:322: "### \`stop\` — Cancel Scheduled Briefings"`
- `skills/briefing/SKILL.md:329: "### \`next\` — Show Next Fire Times"`
- `skills/briefing/SKILL.md:36-37: "$ARGUMENTS = \"stop\"          → meta: cancel scheduled briefings / $ARGUMENTS = \"next\"          → meta: show next scheduled briefing"`

---

## Typical usage

**Doc:** "The common case is a bare `/briefing` for a quick status read, or `report` with a period for something you want to keep:" (examples `/briefing`, `/briefing report 7d`, `/briefing report 24h every day at 9am`, `/briefing worktrees`, `/briefing verify`)

- `skills/briefing/SKILL.md:29-30: "$ARGUMENTS = \"\"              → mode: summary / $ARGUMENTS = \"summary\"       → mode: summary"` (bare = summary)
- `skills/briefing/SKILL.md:38: "$ARGUMENTS = \"report 24h every day at 9am\" → mode: report, schedule"` (report + period + schedule shape)
- USAGE_MAP.md:130-134: `/briefing` has "too few cron fires to derive a stable argument shape from this sample — pull their 'typical usage' examples from the skill's own `argument-hint` + body and `COMPANIONS.md`" — so examples are drawn from SKILL.md's own argument-parsing table (lines 29-39) and not from the biased usage sample. (R7 compliance.)

---

## Companion skills (R6 — from COMPANIONS.md, not invented)

**Doc:** "`/fix-issues` — one of the long-running orchestration skills `/briefing` reports on."

- `COMPANIONS.md:75: "| \`briefing\` | \`fix-issues\`, \`run-plan\`, \`update-zskills\` | Reports on the activity of long-running orchestration skills; \`update-zskills\` configures it. |"`

**Doc:** "`/run-plan` — likewise a long-running skill whose worktrees, landed commits, and report sign-offs show up in a briefing. Run `/briefing verify` after a plan run to pick up any open sign-off items."

- `COMPANIONS.md:75: "| \`briefing\` | \`fix-issues\`, \`run-plan\`, \`update-zskills\` | Reports on the activity of long-running orchestration skills"`
- `skills/briefing/SKILL.md:181-182: "a worktree needing user verification at \`/briefing verify\` time / means \`/run-plan\` or \`/fix-issues\` didn't complete its verification phase."` (run-plan/fix-issues output is what verify surfaces)

**Doc:** "`/update-zskills` — the install and configuration skill. It sets up the configuration `/briefing` reads (audit and report directories, the source-clone path it checks for zskills updates)."

- `COMPANIONS.md:75: "...\`update-zskills\` configures it."`
- `COMPANIONS.md:96: "| \`update-zskills\` | ... \`briefing\` ... | The install/config skill; configures and is referenced by nearly every skill. |"`
- `skills/briefing/SKILL.md:396-398: "the \`summary\` and \`report\` modes should compare the / installed version (resolved from \`.claude/zskills-config.json\` ... against the source repo's latest / release tag"` (briefing reads config that update-zskills sets)

---

## Arguments

**Doc (table rows):** no-args → summary; `summary`; `report [period]`; `verify`; `current`; `worktrees`; `stop`; `next`.

- `skills/briefing/SKILL.md:3: argument-hint: "[report [period]] | verify | current | worktrees | [summary] | stop | next"` (the declared argument set)
- `skills/briefing/SKILL.md:29-37: "$ARGUMENTS = \"\"              → mode: summary / ... = \"summary\" ... / ... = \"report\" ... / ... = \"report 7d\" ... / ... = \"verify\" ... / ... = \"current\" ... / ... = \"worktrees\" ... / ... = \"stop\" ... → meta: cancel scheduled briefings / ... = \"next\" ... → meta: show next scheduled briefing"` (the authoritative arg→mode mapping)

**Doc (Period):** "Used with the `report` mode to bound how far back it looks: `1h`, `6h`, `24h` (the default), `1d`, `2d`, or `7d`."

- `skills/briefing/SKILL.md:41: "**Period shorthand:** \`1h\`, \`6h\`, \`24h\` (default), \`1d\`, \`2d\`, \`7d\`"` (body — includes `1d`, beating the argument-hint which omits it)
- `skills/briefing/SKILL.md:26: "Used with \`report\` mode: \`1h\`, \`6h\`, \`24h\` (default)..."` — actually the period example in argument parsing is `report 7d` (line 38). Period is documented as a `report`-mode token.

**Doc (Scheduling):** "Append `every SCHEDULE` to any mode ... The schedule lives with the current session; if the session ends, the schedule is lost. Use `stop` to cancel it and `next` to see when it will next fire."

- `skills/briefing/SKILL.md:43-44: "**Schedule detection:** If \`$ARGUMENTS\` contains \`every <SCHEDULE>\`, strip the schedule / portion and handle scheduling separately"`
- `skills/briefing/SKILL.md:336-345: "### Common Schedules ... | \`every hour\` ... | \`every 2h\` ... | \`every day at 9am\` ... | \`every weekday at 9am\` ..."` (schedule examples)
- `skills/briefing/SKILL.md:319: "WARNING: This schedule is tied to this session. If the session ends, the schedule is lost."`

---

## Tips & Gotchas

**Doc:** "`/briefing` requires Python 3; if it is not on your PATH, the skill prints a clear error and stops."

- `skills/briefing/SKILL.md:18-22: "Python 3 is required (per CLAUDE.md \"Python is required\"). If \`python3\` / is not on PATH, output a clear error and stop: / > /briefing requires Python 3. Install it and ensure it's on PATH."`

**Doc:** "The script's output is shown to you verbatim — it is formatted to be read directly, not summarized."

- `skills/briefing/SKILL.md:49-51: "collapse, truncate, or rephrase script output. The script's formatting IS / the presentation — it was designed to be read directly."`

**Doc:** "Every mode is read-only. `worktrees` shows you removal commands but never runs them; always extract a worktree's logs before removing it."

- `skills/briefing/SKILL.md:216-217: "Read-only — shows what's / safe to remove but does not remove anything."`
- `skills/briefing/SKILL.md:235: "**Important:** Always extract logs before removing any worktree."`

**Doc:** "The `report` mode preserves checkboxes you ticked in an earlier same-day report, so re-running it the same day does not lose your progress."

- `skills/briefing/SKILL.md:96: "Checkbox state from earlier same-day reports is preserved automatically."`
- `skills/briefing/SKILL.md:383: "Checkboxes marked \`[x]\` in earlier same-day reports are preserved in new reports."`

**Doc:** "The `summary` and `report` modes also note whether your installed zskills version is behind the source clone, when one is found."

- `skills/briefing/SKILL.md:392-398: "## Z Skills Update Check / If a Z Skills repo clone exists ... the \`summary\` and \`report\` modes should compare the / installed version ... against the source repo's latest / release tag"`
- `skills/briefing/SKILL.md:411-415: "if [ -n \"$source_ver\" ] && [ \"$source_ver\" != \"$ZSKILLS_VERSION\" ]; then / echo \"  zskills: $ZSKILLS_VERSION → $source_ver (run /update-zskills)\" / else / echo \"  zskills: ${ZSKILLS_VERSION:-(unknown)} (current)\""`

---

## PLAN-TEXT-DRIFT

1. **`argument-hint` omits `1d`.** Line 3 lists periods as `1h, 6h, 24h, 2d, 7d`;
   the body (line 41) lists `1h, 6h, 24h (default), 1d, 2d, 7d`. Per rubric item 4,
   the body wins — the doc includes `1d`. (Pre-flagged in the task prompt.)

2. **Period attaches to `report` only — corrected in the final doc.** The
   SKILL.md argument-parsing grammar (lines 29-39) attaches a period only to
   `report` (`report 7d`, line 38). Only the `summary`/`report`/`dogfooding`
   helper invocations pass `--since=<period>` (lines 66, 86, 250); the
   `verify`/`current`/`worktrees` helper calls (lines 120, 203, 225) take NO
   `--since` flag, and the documented user grammar exposes a period token only
   on `report`. An intermediate draft of this rewrite said the period bounds
   "report, verify, current, and worktrees" — that overstated the source and
   was corrected: both the "What it does" prose and the Arguments "Period"
   subsection now scope the period to `report` mode alone. Not a source bug —
   a draft-side overstatement, caught and fixed during factsheet construction.
