# Factsheet — docs/skills/fix-issues.md

Every factual claim in the rewritten `docs/skills/fix-issues.md` is paired
below with the source line that backs it. Line numbers are against
`skills/fix-issues/SKILL.md` unless a different file is named. Quotes are
verbatim from that line.

---

## Blockquote / What it does

- **Doc:** "Work through a backlog of GitHub issues in one sprint: pick the issues, fix each in isolation, run the tests…"
  - `skills/fix-issues/SKILL.md:16`: `Orchestrates large-scale bug fixing. Syncs trackers, prioritizes issues,`
  - `skills/fix-issues/SKILL.md:17`: `dispatches agent teams in worktrees, verifies fixes, writes a persistent`

- **Doc:** "…and (optionally) open and land a pull request per fix."
  - `skills/fix-issues/SKILL.md:18`: `report, and optionally auto-lands to main. Can self-schedule for recurring runs.`

- **Doc:** "Recurring via `every SCHEDULE`; `stop`/`next` manage the schedule."
  - `skills/fix-issues/SKILL.md:65`: `- **every SCHEDULE** (optional) — self-schedule recurring runs via cron:`
  - `skills/fix-issues/SKILL.md:87`: `- **stop** — cancel any existing `/fix-issues` cron and exit. **Takes`

- **Doc:** "`sync` refreshes issue trackers and closes already-fixed issues; `plan` drafts plans for issues too complex to fix in a sprint."
  - `skills/fix-issues/SKILL.md:79`: `- **sync** — update all issue tracker files from GitHub, research new`
  - `skills/fix-issues/SKILL.md:84`: `- **plan** — draft plans for issues previously skipped as "too complex."`

- **Doc:** "You give it a count `N`, and it prioritizes that many open issues…"
  - `skills/fix-issues/SKILL.md:31`: `- **N** (required for sprints) — number of issues to fix (e.g., `30`)`
  - `skills/fix-issues/SKILL.md:16`: `Orchestrates large-scale bug fixing. Syncs trackers, prioritizes issues,`

- **Doc:** "…fixes each one in its own isolated worktree…"
  - `skills/fix-issues/SKILL.md:367`: `- **Worktrees only** — all fixes happen in isolated worktrees, never in the`

- **Doc:** "…runs the test suite before anything is committed…"
  - `skills/fix-issues/SKILL.md:369`: `- **The verification agent commits after passing tests** — the implementation`
  - `skills/fix-issues/SKILL.md:381`: `- **`$FULL_TEST_CMD` before every commit** (resolve via the dual-lane prelude in`

- **Doc:** "…and writes a sprint report you can hand off to `/fix-report`."
  - `skills/fix-issues/SKILL.md:377`: `- **Always write `$ZSKILLS_REPORTS_DIR/SPRINT_REPORT.md`** — it's the handoff to `/fix-report`.`

- **Doc:** "With the `auto` flag it lands each fix for you (via `/land-pr` in PR mode); without it, it asks for approval at the key gates first."
  - `skills/fix-issues/SKILL.md:46`: `- **auto** (optional) — bypass confirmation gates for autonomous operation.`
  - `skills/fix-issues/SKILL.md:48`: `  - **Sprints:** skip Phase 2 issue list approval, auto-land per-issue`
  - `skills/fix-issues/SKILL.md:91`: `- **pr** (optional) — land each fixed issue via a per-issue PR on a named`

- **Doc:** "Each issue is fixed and committed separately, so the history stays clean…"
  - `skills/fix-issues/SKILL.md:380`: `- **One issue per commit** — clean git history in worktrees.`

- **Doc:** "…one bad fix never blocks the others."
  - `skills/fix-issues/SKILL.md:374`: `  skip all commits from that worktree (grouped issues depend on each`
  - (context: `skills/fix-issues/SKILL.md:373` `- **In `auto` mode, skip conflicting cherry-picks** — abort the conflict,` — a conflicting fix is skipped and the rest still land)

- **Doc:** "Before fixing anything, the agent reads each issue's full body — not just the title…"
  - `skills/fix-issues/SKILL.md:400`: `- **Read every issue body before acting** — `gh issue view <N>` is mandatory`
  - `skills/fix-issues/SKILL.md:401`: `  in Phase 1b. Titles are often vague or misleading. The body is the spec.`

- **Doc:** "…schedules itself to run again (`every SCHEDULE`)…"
  - `skills/fix-issues/SKILL.md:65`: `- **every SCHEDULE** (optional) — self-schedule recurring runs via cron:`

- **Doc:** "…keeps your issue trackers in sync with GitHub and closes issues that are already fixed (`sync`)…"
  - `skills/fix-issues/SKILL.md:79`: `- **sync** — update all issue tracker files from GitHub, research new`
  - `skills/fix-issues/SKILL.md:80`: `  issues, AND verify/close issues that appear already fixed. Dispatches`

- **Doc:** "…drafts plans for issues that are too big for a quick fix (`plan`)…"
  - `skills/fix-issues/SKILL.md:84`: `- **plan** — draft plans for issues previously skipped as "too complex."`

- **Doc:** "…and manages the dashboard queue that feeds the sprint (`add` / `remove` / `reconsider`)."
  - `skills/fix-issues/SKILL.md:111`: `- `add` followed by a positive integer — add issue to queue column and exit`
  - `skills/fix-issues/SKILL.md:112`: `- `remove` followed by a positive integer — remove issue from queue column and exit`

---

## Usage block

- **Doc:** entire usage block (`/fix-issues N [focus|dashboard] [auto] [every SCHEDULE] [now] [pr|direct]`, etc.)
  - `skills/fix-issues/SKILL.md:25`: `/fix-issues N [focus|dashboard] [auto] [every SCHEDULE] [now] [pr|direct]`
  - `skills/fix-issues/SKILL.md:26`: `/fix-issues sync | plan [auto] | stop | next`
  - `skills/fix-issues/SKILL.md:27`: `/fix-issues add <N> [column] [pos]`
  - `skills/fix-issues/SKILL.md:28`: `/fix-issues remove <N> [column]`
  - reconsider line: `skills/fix-issues/SKILL.md:344`: `- `/fix-issues reconsider 717` — flag #717 for re-evaluation on next sprint`

---

## Typical usage

- **Doc:** "The most common way to run `/fix-issues` is as a recurring, autonomous queue worker: a small count, `auto`, and a schedule." + `/fix-issues 1 every 30m dashboard auto`
  - `USAGE_MAP.md:93`: `- `Run /fix-issues N auto dashboard every Nm now` (979) — the dominant shape`
  - `skills/fix-issues/SKILL.md:44`: `  fall-through to default rubric). Designed for the queue-worker`
  - `skills/fix-issues/SKILL.md:45`: `  pattern: `/fix-issues 1 every 30m dashboard auto`.`

- **Doc:** "A one-time burst…fix several issues now, each as its own PR" + `/fix-issues 5 auto pr`
  - `skills/fix-issues/SKILL.md:332`: `- `/fix-issues 5 auto pr` — autonomous sprint, per-issue PR landing`

- **Doc:** "And a daily catch-up sprint that also runs once immediately" + `/fix-issues 10 auto every day at 9am now`
  - `skills/fix-issues/SKILL.md:326`: `- `/fix-issues 10 auto every weekday at 9am now` — schedule + run now`
  - `skills/fix-issues/SKILL.md:325`: `- `/fix-issues 10 auto every day at 9am` — schedule daily at 9am`

- **Doc:** "Running `/fix-issues` with no count and no subcommand doesn't start a sprint — it reports whether a recurring sprint is scheduled and prints a short usage hint."
  - `skills/fix-issues/SKILL.md:76`: `  runs immediately rather than only scheduling. (A *truly bare* `/fix-issues``
  - `skills/fix-issues/SKILL.md:77`: `  with no N and no subcommand does NOT start a sprint — it reports cron status`
  - `skills/fix-issues/SKILL.md:78`: `  + a usage hint and exits; see the Execution path bare row.)`

---

## Companion skills (per COMPANIONS.md:83)

`COMPANIONS.md:83`: `| `fix-issues` | `fix-report`, `draft-plan`, `run-plan`, `land-pr` | Drives an issue backlog; `fix-report` summarizes a sprint; redirects big items to `/draft-plan`/`/run-plan`. |`

- **Doc:** "`/fix-report` — the reporting companion…closes the resolved issues…updates trackers…cleans up worktrees. `/fix-issues` deliberately leaves those wrap-up actions to `/fix-report`."
  - `skills/fix-issues/SKILL.md:377`: `- **Always write `$ZSKILLS_REPORTS_DIR/SPRINT_REPORT.md`** — it's the handoff to `/fix-report`.`
  - `skills/fix-issues/SKILL.md:378`: `- **Never close GH issues, update trackers, or remove worktrees** — that's`
  - `skills/fix-issues/SKILL.md:379`: `  `/fix-report`'s job.`

- **Doc:** "`/investigate` — when an issue's root cause isn't clear enough…proves the cause first; its fix can then be handled by `/fix-issues` or one of the one-commit skills."
  - `COMPANIONS.md:85`: `| `investigate` | `fix-issues`, `create-worktree`, `update-zskills` | Proves a root cause; its fix then routes to `/quickfix` or `/do` (per CLAUDE.md). |`
  - `COMPANIONS.md:58`: `- **`/investigate` vs `/quickfix`**: `/quickfix` assumes the fix is known;`

- **Doc:** "`/draft-plan` — issues too large for a sprint are routed here. `/fix-issues plan` drafts a plan for each skipped issue so `/run-plan` can execute it later."
  - `skills/fix-issues/SKILL.md:84`: `- **plan** — draft plans for issues previously skipped as "too complex."`
  - `skills/fix-issues/SKILL.md:85`: `  Scans `$ZSKILLS_REPORTS_DIR/SPRINT_REPORT.md` for skipped items, dispatches `/draft-plan``
  - `skills/fix-issues/SKILL.md:86`: `  for each. No fixing — just creates plans for `/run-plan` to execute later.`

- **Doc:** "`/land-pr` — dispatched automatically in PR mode to push the branch, open the PR, watch CI, and merge. You never call it yourself."
  - `skills/fix-issues/SKILL.md:91`: `- **pr** (optional) — land each fixed issue via a per-issue PR on a named`
  - `COMPANIONS.md:86`: `| `land-pr` | … | **Internal** (`user-invocable: false`). Dispatched BY its callers; never typed directly. |`

---

## Arguments table

- **`N`** — `skills/fix-issues/SKILL.md:31`: `- **N** (required for sprints) — number of issues to fix (e.g., `30`)`
- **`focus`** — `skills/fix-issues/SKILL.md:32`: `- **focus** (optional) — prioritize a specific domain. The agent scans`
  - domain values: `skills/fix-issues/SKILL.md:34`: `  and their domains. Common focus values: `new`, `correctness`, `codegen`,`
- **`dashboard`** — `skills/fix-issues/SKILL.md:37`: `- **dashboard** (optional) — source candidate issues from the dashboard's`
  - "default priority order": `skills/fix-issues/SKILL.md:36`: `  Omit for default priority order.`
- **`auto`** — `skills/fix-issues/SKILL.md:46`: `- **auto** (optional) — bypass confirmation gates for autonomous operation.`
  - "skip the issue-list approval, land each fix, and merge the sprint-report PR": `skills/fix-issues/SKILL.md:48`: `  - **Sprints:** skip Phase 2 issue list approval, auto-land per-issue`
  - `skills/fix-issues/SKILL.md:49`: `    fix PRs, AND auto-merge the Phase 6 sprint-report PR (its content`
- **`every SCHEDULE`** — `skills/fix-issues/SKILL.md:65`: `- **every SCHEDULE** (optional) — self-schedule recurring runs via cron:`
  - schedule forms: `skills/fix-issues/SKILL.md:66`: `  - Accepts intervals: `4h`, `2h`, `30m`, `12h`` and `:67`: `  - Accepts time-of-day: `day at 9am`, `day at 14:00`, `weekday at 9am``
- **`now`** — `skills/fix-issues/SKILL.md:73`: `- **now** (optional) — run immediately. When combined with `every`, runs`
  - `skills/fix-issues/SKILL.md:74`: `  immediately AND schedules. Without `every`, `now` needs no `every` to take`
- **`pr`** — `skills/fix-issues/SKILL.md:91`: `- **pr** (optional) — land each fixed issue via a per-issue PR on a named`
- **`direct`** — `skills/fix-issues/SKILL.md:94`: `- **direct** (optional) — land each fixed issue by fast-forward-merging`
  - "requires an unprotected main": `skills/fix-issues/SKILL.md:97`: `  with `execution.main_protected: true`.`

---

## Subcommands

### sync

- **Doc:** "Refresh every issue tracker from GitHub, research new issues, and verify-then-close issues that already appear fixed."
  - `skills/fix-issues/SKILL.md:79`: `- **sync** — update all issue tracker files from GitHub, research new`
  - `skills/fix-issues/SKILL.md:80`: `  issues, AND verify/close issues that appear already fixed. Dispatches`

- **Doc:** "Always interactive — it presents what it found and asks before closing anything."
  - `skills/fix-issues/SKILL.md:82`: `  the codebase. Always interactive — presents findings and asks before`
  - `skills/fix-issues/SKILL.md:83`: `  closing. See Sync section for the full flow.`

- **Doc:** step 1 "Fetch the latest issues from GitHub and update the local trackers."
  - `skills/fix-issues/modes/sync.md:55`: `1. **Run Phase 1a** (Preflight & Sync) — fetch all open issues, run sync`

- **Doc:** step 2 "Research any issues that haven't been looked at yet, checking whether each is already resolved in the code."
  - `skills/fix-issues/SKILL.md:81`: `  research agents that also check if open issues are already resolved in`

- **Doc:** step 3 "Present its findings with a verdict per issue (fixed, likely fixed, not fixed, or unclear)."
  - `skills/fix-issues/modes/sync.md:78`: `- **FIXED** — code fix is present AND tests pass. Include: commit hash,`
  - `skills/fix-issues/modes/sync.md:84`: `- **UNCLEAR** — can't determine from code review alone (needs manual testing).`

- **Doc:** step 5 "…close the approved issues on GitHub only after that PR merges."
  - `skills/fix-issues/modes/sync.md:135`: `The `gh issue close` calls are deferred to Step 5 sub-step 3, AFTER`

### plan [auto]

- **Doc:** "Draft plans for issues a previous sprint skipped as too complex. It reads the skipped items from the sprint report and dispatches `/draft-plan` for each — no fixing, just plans for `/run-plan` to execute later. With `auto`, it plans every found issue without asking you to pick."
  - `skills/fix-issues/SKILL.md:84`: `- **plan** — draft plans for issues previously skipped as "too complex."`
  - `skills/fix-issues/SKILL.md:85`: `  Scans `$ZSKILLS_REPORTS_DIR/SPRINT_REPORT.md` for skipped items, dispatches `/draft-plan``
  - `skills/fix-issues/SKILL.md:86`: `  for each. No fixing — just creates plans for `/run-plan` to execute later.`
  - auto: `skills/fix-issues/SKILL.md:59`: `  - **plan auto:** draft plans for all found issues without selection`

### stop

- **Doc:** "Cancel any recurring `/fix-issues` sprint and exit. Takes precedence over every other argument."
  - `skills/fix-issues/SKILL.md:87`: `- **stop** — cancel any existing `/fix-issues` cron and exit. **Takes`
  - `skills/fix-issues/SKILL.md:88`: `  precedence over all other arguments.**`

### next

- **Doc:** "Report when the next scheduled sprint will run, in both relative and absolute time, and how many issues are waiting in the queue."
  - `skills/fix-issues/SKILL.md:89`-`90`: `- **next** — check when the next scheduled run will fire. **Takes precedence` / `  over all other arguments except `stop`.**`
  - relative+absolute: `skills/fix-issues/subcommands/stop-next.md:54`: `   - If found: parse the cron expression and compute the next fire time.`
  - queue count: `skills/fix-issues/subcommands/stop-next.md:59`: `4. Peek at the Ready queue in `.zskills/monitor-state.json`:`

### add <N> [column] [pos]

- **Doc:** "Add an issue to a queue column on the dashboard, then exit without running a sprint." + arg list
  - `skills/fix-issues/subcommands/add-remove.md:1`: `## Add (if `add` is present)`
  - `skills/fix-issues/subcommands/add-remove.md:8`: `- `<N>` — positive integer (GitHub issue number). REQUIRED.`
  - `skills/fix-issues/subcommands/add-remove.md:9`: `- `[column]` — one of `triage`, `ready`, `backlog`. Default: `ready`.`
  - `skills/fix-issues/subcommands/add-remove.md:10`: `- `[pos]` — 1-based insertion position. Default: append.`

### remove <N> [column]

- **Doc:** "Remove an issue from a queue column." + arg list
  - `skills/fix-issues/subcommands/add-remove.md:99`: `- `<N>` — positive integer (GitHub issue number). REQUIRED.`
  - `skills/fix-issues/subcommands/add-remove.md:100`: `- `[column]` — one of `triage`, `ready`, `backlog`. Default: `ready`.`

### reconsider <N>

- **Doc:** "Flag a previously-skipped issue so the next sprint re-evaluates it from scratch instead of skipping it again. It's a one-shot signal: the issue is re-triaged once on the next run, then the flag clears."
  - `skills/fix-issues/subcommands/reconsider.md:17`: `The reconsider list is a one-shot signal. On the next `/fix-issues` fire,`
  - `skills/fix-issues/subcommands/reconsider.md:21`: `  removes it from the list (one-shot: flag once, re-evaluate once, clear).`

---

## Examples block

All example lines copied verbatim from the source examples block:
- `skills/fix-issues/SKILL.md:320`-`344` (the `## Arguments` "Examples:" list) — every example in the doc's Examples fence appears there, e.g.:
  - `:320`: `- `/fix-issues 30` — interactive, 30 issues, run now`
  - `:332`: `- `/fix-issues 5 auto pr` — autonomous sprint, per-issue PR landing`
  - `:334`-`335`: `- `/fix-issues 1 every 30m dashboard auto` …`
  - `:339`-`343`: the `add`/`remove` examples
  - `:344`: `- `/fix-issues reconsider 717` — flag #717 for re-evaluation on next sprint`

---

## Common Patterns

- **Queue-worker** `/fix-issues 1 every 30m dashboard auto` — `skills/fix-issues/SKILL.md:45`: `  pattern: `/fix-issues 1 every 30m dashboard auto`.`
- **Daily sprint** — `skills/fix-issues/SKILL.md:326`: `- `/fix-issues 10 auto every weekday at 9am now` — schedule + run now`
- **One-time burst** `/fix-issues 5 auto pr` — `skills/fix-issues/SKILL.md:332`: `- `/fix-issues 5 auto pr` — autonomous sprint, per-issue PR landing`
- **Sync hygiene** — `skills/fix-issues/SKILL.md:79`: `- **sync** — update all issue tracker files from GitHub, research new`
- **Plan the hard ones** — `skills/fix-issues/SKILL.md:84`: `- **plan** — draft plans for issues previously skipped as "too complex."`

---

## Tips & Gotchas

- **Doc:** "The `sync` command always asks before closing an issue on GitHub — there is no autonomous mode for it…"
  - `skills/fix-issues/SKILL.md:61`: `  - **Sync `gh issue close` step is still interactive.** `auto` does NOT`
  - `skills/fix-issues/SKILL.md:62`: `    bypass the human-approval gate on the irreversible `gh issue close``

- **Doc:** "`dashboard` can't be combined with `focus`, `sync`, `plan`, `stop`, `next`, `add`, `remove`, or `reconsider`…"
  - `skills/fix-issues/SKILL.md:42`: `  silently. Capped to N. Mutually exclusive with `focus`, `sync`,`
  - `skills/fix-issues/SKILL.md:43`: `  `plan`, `stop`, and `next`. Empty queue → exit 0 cleanly (no`
  - add/remove/reconsider exclusion: `skills/fix-issues/SKILL.md:304`-`315` (the `dashboard is incompatible with add/remove/reconsider mode` checks), e.g. `:304`: `  if [[ "$ARGUMENTS" =~ (^|[[:space:]])[aA][dD][dD]($|[[:space:]]) ]]; then`

- **Doc:** "`direct` mode lands fixes straight onto main, so it only works when main isn't protected…"
  - `skills/fix-issues/SKILL.md:96`: `  cherry-pick extraction). Overrides the config default. Incompatible`
  - `skills/fix-issues/SKILL.md:97`: `  with `execution.main_protected: true`.`

- **Doc:** "A scheduled sprint lasts only as long as the session that created it — re-run `/fix-issues ... every ...` to restart it after the session ends"
  - `skills/fix-issues/SKILL.md:72`: `  - Cron is session-scoped — dies when the session dies`
  - `skills/fix-issues/SKILL.md:396`: `  user to re-run `/fix-issues ... every` to restart scheduling.`

- **Doc:** "`every SCHEDULE` always runs autonomously, so adding it implies `auto`…"
  - `skills/fix-issues/SKILL.md:391`: `- **`every` implies `auto`** — scheduling only makes sense for autonomous`
  - `skills/fix-issues/SKILL.md:392`: `  runs. If `every` is present but `auto` is not, treat it as if `auto` was set.`

- **Doc:** "When you don't specify `pr` or `direct`, the landing style falls back to your project's configured default, or to cherry-picking the fix back to main if nothing is configured"
  - `skills/fix-issues/SKILL.md:129`: `**Landing mode resolution** (same pattern as `/run-plan`):`
  - `skills/fix-issues/SKILL.md:130`: `1. Explicit argument wins: `pr` or `direct` in `$ARGUMENTS``
  - `skills/fix-issues/SKILL.md:131`: `2. Config default: read `.claude/zskills-config.json` `execution.landing` field`
  - `skills/fix-issues/SKILL.md:132`: `3. Fallback: `cherry-pick``

- **Doc:** "The sprint always runs the full test suite before any fix is committed, and never weakens a test to make it pass"
  - `skills/fix-issues/SKILL.md:381`: `- **`$FULL_TEST_CMD` before every commit** (resolve via the dual-lane prelude in`
  - `skills/fix-issues/SKILL.md:384`: `- **Never weaken tests** — fix the code, not the test. Do not loosen`

---

## Internals deliberately stripped (R5)

These appeared in the prior doc or the source and were removed from user prose:
phase numbers (`Phase 2`, `Phase 6`, `Phase 1a/1b`), `monitor-state.json`,
`ISSUES_PLAN.md`, `SPRINT_REPORT.md` path, `execution.landing` /
`execution.main_protected` field names (replaced with "configured default" /
"protected main"), `claim-issue.sh` / claim markers, `CronList`/`CronDelete`
tool names, `filter-unresearched-candidates.sh`, and bare `#NNNN` issue refs
(the prior doc's reconsider paragraph cited `ISSUES_PLAN.md` + `Phase 2` — both
gone).
