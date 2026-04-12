---
name: do
disable-model-invocation: true
argument-hint: "<description> [worktree] [push] [every SCHEDULE] [now] | stop [query] | next [query] | now [query]"
description: >-
  Lightweight task dispatcher for ad-hoc work: documentation, examples,
  refactoring, content updates. Supports scheduling with every/now/next/stop.
  Usage: /do <description> [worktree] [push] [every SCHEDULE] [now] | stop | next.
---

# /do \<description> [worktree] [push] [every SCHEDULE] | stop [query] | next [query] | now [query] — Lightweight Task Dispatcher

Execute small, ad-hoc tasks with structured research, verification, and
optional isolation or auto-push. Can be scheduled for recurring maintenance
tasks. For work that doesn't warrant the full ceremony of `/run-plan` (plan
phases) or `/fix-issues` (batch bug fixing).

**Ultrathink throughout.**

## When to Use `/do`

| Task | Use |
|------|-----|
| Documentation, examples, presentations, screenshots | `/do` |
| Small refactors, one-off fixes, content updates | `/do` |
| Adding a new block type | `/add-block` (10-step workflow) |
| Newsletter entry | `/do` or `/doc newsletter` |
| Batch bug fixing (N issues) | `/fix-issues N` |
| Executing a plan phase | `/run-plan` |
| Multi-file feature work with dependencies | `/run-plan` |

**Rule of thumb:** if the task needs a worktree, separate verification agent,
and a persistent report file, it's too big for `/do`. Use `/run-plan` instead.

## Arguments

```
/do <description> [worktree] [push] [every SCHEDULE] [now]
/do stop | next
```

- **description** (required) — what to do, in natural language
- **worktree** (optional) — use `isolation: "worktree"` for riskier or
  larger tasks. Without this flag, work happens directly on main.
- **push** (optional) — auto-push to remote after verification passes.
  Upgrades verification to use a **separate verification agent** running
  `/verify-changes`. Push never happens without verification passing first.
- **every SCHEDULE** (optional) — self-schedule recurring runs via cron:
  - Accepts intervals: `4h`, `2h`, `30m`, `12h`
  - Accepts time-of-day: `day at 9am`, `day at 14:00`, `weekday at 9am`
  - Without `now`: schedules only, does NOT run immediately
  - With `now`: schedules AND runs immediately
  - Each run re-registers the cron (self-perpetuating)
  - Cron is session-scoped — dies when the session dies
- **now** (optional) — run immediately. When combined with `every`, runs
  immediately AND schedules. Without `every`, `now` is the default behavior.
- **stop** — cancel `/do` cron(s). Bare `/do stop` → all crons.
  With query `/do stop Check docs` → targets matching cron.
- **next** — check next fire time. Bare → all. With query → targeted.

**Detection:** If `$ARGUMENTS` starts with a quoted string (`"..."`),
the quoted text is the description — skip meta-command detection entirely.
This lets users escape edge cases like `/do "Now fix the tooltip bug"`.

Otherwise, check the **first word** of `$ARGUMENTS`:
- `stop [query]` — meta-command: cancel crons. Bare → all. With query → targeted.
- `next [query]` — meta-command: show fire times. Bare → all. With query → targeted.
- `now [query]` — meta-command: trigger immediately. Bare → all/ask. With query → targeted.

If the first word is NOT a meta-command, it's a regular task. Parse
trailing flags from the END backward:
- `push` — recognized at the end
- `worktree` — recognized at the end
- `every <schedule>` — recognized at the end (e.g., `every 4h`, `every day at 9am`)
- `now` — recognized at the end (only meaningful with `every`: run now AND schedule)

Everything before the trailing flags is the task description.

This means:
- `/do stop` — stop all `/do` crons
- `/do stop Check docs` — stop the "Check docs" cron
- `/do next` — show all fire times
- `/do next Check docs` — show fire time for "Check docs"
- `/do now` — trigger (if one) or ask (if multiple)
- `/do now Check docs` — trigger the "Check docs" cron
- `/do Push the latest changes` — description only, no flags
- `/do Update the presentation push` — description + push flag
- `/do Fix the tooltip bug worktree push` — description + both flags
- `/do Check docs every day at 9am` — schedule "Check docs" daily

Examples:
- `/do Add example models for Integrator and Derivative blocks`
- `/do Sort the screenshots in session-sequence-snapshots`
- `/do Refactor color constants in main.css worktree`
- `/do Update the presentation with Phase 3 results push`
- `/do Make sure docs are up to date every day at 9am`
- `/do Check for broken links in examples every 12h now`
- `/do next` — all scheduled tasks
- `/do next Check docs` — specific task
- `/do stop` — cancel all
- `/do stop Check docs` — cancel specific task

## Meta-Commands: stop / next / now

These commands query or control `/do` crons. They work in two modes:

- **Bare** (`/do stop`, `/do next`, `/do now`) — applies to ALL `/do` crons
- **Targeted** (`/do stop Check docs`, `/do next Check docs`) — applies to the matching cron

### Cron Matching (for targeted commands)

When a description is present with `stop`/`next`/`now`, find the matching
cron by comparing the description against all `/do` cron prompts:

1. `CronList` → find all whose prompt starts with `Run /do`
2. Extract each cron's task description (strip `Run /do ` prefix and
   trailing flags)
3. **Fuzzy match:** check if the user's description words appear in the
   cron's description (case-insensitive, order-independent). E.g.,
   "Check docs" matches "Make sure docs are up to date" because both
   key words overlap. The user won't have tons of similar `/do` crons,
   so loose matching is fine.
4. **One match** → act on it. **Multiple matches** → list them, ask
   which one. **No matches** → report "no matching /do cron found."

### Now

1. `CronList` → find `/do` crons (all, or matching if description given)
2. **One cron:** extract prompt, **run immediately.** Cron stays active.
3. **Multiple (bare only):** list them, ask which to trigger.
4. **None:** report `No active /do cron to trigger.` and **exit.**

### Next

1. `CronList` → find `/do` crons (all, or matching if description given)
2. For each, parse the cron expression and compute the next fire time.
   Use `TZ=America/New_York date` for the timezone. Show both relative
   and absolute:
   > Active /do crons:
   > 1. ~14h 47m (~9:03 AM ET tomorrow, cron XXXX)
   >    Prompt: Run /do Make sure docs are up to date every day at 9am now
   > 2. ~3h 12m (~8:15 PM ET, cron YYYY)
   >    Prompt: Run /do Check broken links every 4h now
3. **None:** `No active /do cron in this session.`
4. **Exit.**

### Stop

1. `CronList` → find `/do` crons (all, or matching if description given)
2. **Bare with one cron:** delete it. Report what was cancelled.
3. **Bare with multiple:** list them, ask which to cancel (or "all").
4. **Targeted:** delete the matched cron. Report what was cancelled.
5. **None:** report "no active /do cron found."
6. **Exit.**

## Phase 0 — Schedule (if `every` is present)

If `$ARGUMENTS` contains `every <schedule>`:

1. **Parse the schedule** — convert to a cron expression.

   **For interval-based schedules** (`4h`, `12h`): use the CURRENT minute
   as the offset so the first fire is a full interval from now. Check with
   `date +%M`:
   - `4h` at minute 9 → `9 */4 * * *`

   **For time-of-day schedules**: offset round minutes by a few:
   - `day at 9am` → `3 9 * * *`
   - `weekday at 9am` → `3 9 * * 1-5`

2. **Deduplicate** — `CronList` and check for existing `/do` crons.
   Extract the task description from each cron's prompt by stripping
   `Run /do ` prefix and trailing flags (`every`, `now`, `worktree`, `push`).
   - If an existing cron's extracted description **exactly matches** (case-
     insensitive) the new task's description, replace it (`CronDelete` +
     recreate). This is a re-registration of the same task.
   - Otherwise, keep it — the user has multiple crons for different tasks.
   - During an **unattended cron fire** (the invocation itself came from a
     cron), never ask the user — default to keeping both. During an
     **interactive invocation**, if descriptions are similar but not exact,
     list existing crons and ask: "Replace this one, or keep both?"

3. **Construct the cron prompt.** Always include `now` in the cron prompt
   so each cron fire runs immediately AND re-registers itself. Note: this
   `now` is for the CRON's invocation, not the current invocation:
   ```
   Run /do <description> [worktree] [push] every <schedule> now
   ```

4. **Create the cron** — `CronCreate` with `recurring: true`.

5. **Confirm** with wall-clock time.

6. **If `now` is present:** proceed to Phase 1.
   **If `now` is NOT present:** **Exit.** The cron fires later.

If `every` is NOT present, skip this phase (bare invocation runs immediately).

## Phase 1 — Understand & Research

Before touching anything:

1. **Parse the task description** — what is being asked? What files are
   involved? What's the expected outcome?

2. **Identify relevant files and current state:**
   - Search for files related to the task (Glob, Grep)
   - Read existing content that will be modified
   - Check for related skills, conventions, or guidelines (e.g., model
     design rules for example models, newsletter format for entries)

3. **Classify the change type** — this determines verification intensity
   in Phase 3:
   - **Content only** — markdown, images, presentations, documentation.
     No tests needed.
   - **Code** — JavaScript, CSS, HTML, model files. Tests needed.
   - **Mixed** — both content and code. Tests needed for code portion.

4. **Plan the work** — no formal document, just mental clarity on what
   to do and in what order. If the task is bigger than expected (would
   take 1000+ lines of changes, has complex dependencies), suggest
   `/run-plan` instead and ask the user.

## Phase 2 — Execute

1. **Do the work.** By default, work directly on main. If `worktree` flag
   is present, dispatch with `isolation: "worktree"`.

2. **Follow existing conventions:**
   - Example models → `/model-design` skill guidelines
   - Newsletter entries → existing NEWSLETTER.md format
   - Documentation → existing doc style in the repo
   - Code → existing patterns in the codebase

3. **Commit discipline:**
   - **On main:** commit when the work is complete. Clean, descriptive
     message. `npm run test:all` before committing if code was touched.
     If tests fail after two fix attempts on the same error, STOP — report
     what you tried and let the user decide.
   - **In worktree:** the verification agent commits after tests pass.
     One logical unit per commit.

## Phase 3 — Verify

Verification intensity matches the change type (from Phase 1):

### Content-only changes (md, jpg, png, presentations)

- **Spot-check:** formatting, links, file organization, image references
- **Do NOT run tests** — running 4,000+ tests for a markdown edit is
  wasteful, and pre-existing failures would block the task unnecessarily
- **If `push` is present:** dispatch a separate verification agent. Tell
  the agent explicitly: "These are content-only changes (no code). Review
  the diff for correctness and completeness — do NOT run `npm test` or
  `npm run test:all`. Your job is: do these changes make sense? Are the
  right files included? Anything accidentally staged? Formatting correct?"
  Do NOT invoke `/verify-changes` for content-only pushes — it will run
  the full test suite regardless. Instead, dispatch a plain review agent.

### Code changes (js, css, html)

- **Run `npm run test:all`** — all suites must pass, not just unit tests.
- **If tests fail: fix them.** Do not check if failures are pre-existing.
  Do not stash, checkout old commits, or create comparison worktrees.
  If you touched code and tests fail, they're yours to fix. (See
  CLAUDE.md: "NEVER modify the working tree to check if a failure is
  pre-existing.")
- **If `push` is present:** dispatch a **separate verification agent**
  running `/verify-changes`. This is the full 7-phase verification:
  diff review, test coverage audit, `npm run test:all`, manual
  verification if UI, fix problems, re-verify until clean. Push only
  happens if this agent reports clean.

### Mixed changes

- Run tests for the code portion
- Spot-check the content portion
- If `push`: full `/verify-changes` via separate agent

## Phase 4 — Push (if `push` flag present)

Only reached if Phase 3 verification passed.

1. **If on main:**
   ```bash
   git push
   ```

2. **If in worktree:** cherry-pick to main first, then push:
   - Protect uncommitted work on main (`git stash -u` if needed)
   - Cherry-pick worktree commits to main sequentially
   - If any cherry-pick conflicts: **abort and clean up:**
     ```bash
     git cherry-pick --abort
     ```
     Restore stash if one was created (`git stash pop`). If `/do` has an
     active cron, kill it (`CronList` + `CronDelete` any whose prompt
     starts with `Run /do`). Report the conflict to the user. Do NOT
     force-push or resolve automatically.
   - Restore stash if one was created
   - Push main
   - Report what was pushed (commit hashes, branch)

3. **If verification failed:** do NOT push. Report the verification
   findings and stop.

## Phase 5 — Report

Brief inline output. No persistent report file.

**On main (no worktree, no push):**
```
Done. [1-2 sentence summary of what was done]
Changed: file1.js, file2.md (+N lines)
Committed: abc1234 — "commit message"
```

**On main with push:**
```
Done and pushed. [1-2 sentence summary]
Changed: file1.js, file2.md (+N lines)
Committed: abc1234 — "commit message"
Pushed to: origin/main
Verification: clean (npm run test:all passed, /verify-changes clean)
```

**In worktree (no push):**
```
Done. [1-2 sentence summary]
Worktree: ../do-<slug>/
Branch: do/<slug>
Commits: abc1234, def5678
To land: git cherry-pick abc1234 def5678
To discard: git worktree remove ../do-<slug>/
```

**In worktree with push:**
```
Done and pushed. [1-2 sentence summary]
Cherry-picked to main: abc1234, def5678
Pushed to: origin/main
Verification: clean (/verify-changes clean)
Worktree: ../do-<slug>/ (can be removed)
```

## Error Handling

- **Test failures (code changes):** stop, fix the code, re-test. Never
  weaken tests. Never check if failures are pre-existing.
- **Content issues:** stop, fix formatting/links/references, re-check.
- **Cherry-pick conflict (worktree + push):** stop, report the conflict.
  Do not resolve automatically — conflicts need human judgment.
- **Push failure (auth, remote, etc.):** stop, report the error.
- **Task is bigger than expected:** stop, suggest `/run-plan` instead.
  Ask the user before continuing.
- **If stuck on anything:** report the state and ask the user for
  guidance. Do not retry the same approach in a loop.

## Key Rules

- **Match verification to change type** — content-only tasks skip tests.
  Code tasks run tests. Push upgrades to full `/verify-changes`.
- **Never weaken tests** — fix the code, not the test.
- **Never modify the working tree to check pre-existing failures** — if
  you touched code and tests fail, fix them. No stash-and-compare, no
  checkout-old-commit, no comparison worktrees.
- **Protect other agents' work** — do not commit unrelated changes that
  happen to be in the working tree. Stage only files related to the task.
- **Worktree naming** — use `../do-<slug>/` where `<slug>` is a short
  kebab-case description derived from the task (e.g., `do-sort-screenshots`,
  `do-integrator-examples`). Include a timestamp suffix if a worktree
  with that name already exists.
- **No persistent report files** — `/do` outputs results inline. It does
  NOT write SPRINT_REPORT.md, PLAN_REPORT.md, or any other report file.
  The commit is the artifact.
- **Push requires verification** — `push` always dispatches a separate
  verification agent before pushing. No exceptions.
- **Respect CLAUDE.md** — all standard rules apply (no external deps, no
  bundlers, no weakened tests, etc.)
