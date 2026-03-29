---
name: qe-audit
disable-model-invocation: true
argument-hint: "[bash [area]] [every SCHEDULE] [now] | stop | next"
description: >-
  QE audit: check recent commits for test coverage gaps, or bash/stress-test
  features to find bugs. Supports scheduling with every/now/next/stop.
  Usage: /qe-audit [bash [area]] [every SCHEDULE] [now] | stop | next.
---

# /qe-audit [bash [area]] [every SCHEDULE] [now] | stop | next — Quality Engineering Audit

Two modes of quality assurance:

- **Commit audit** (default) — review recent commits for test coverage gaps,
  missing tests, and bugs. Files GitHub issues for findings.
- **Bash** — adversarial stress-testing of features. Pick a specific area
  or let the agent choose under-tested areas. Try to break things with edge
  cases, unusual inputs, and unexpected workflows.

Both modes file GitHub issues and update `the QE issues tracker (e.g., `plans/QE_ISSUES.md`)`. Both are
schedulable. Together they form the quality feedback loop: audit finds gaps →
`/fix-issues` fixes them → audit validates the fixes.

**Ultrathink throughout.**

## Arguments

```
/qe-audit [bash [area]] [every SCHEDULE] [now]
/qe-audit stop | next
```

- **bash** (optional) — switch to bash/stress-test mode instead of commit audit
- **area** (optional, with bash) — specific feature or area to bash. If
  omitted, the agent picks under-tested areas based on coverage data and
  recent changes. Examples: `"undo/redo"`, `"state machine editor"`, `"solver"`,
  `"codegen"`, `"block parameters"`
- **every SCHEDULE** (optional) — self-schedule recurring runs via cron:
  - Accepts intervals: `4h`, `2h`, `30m`, `12h`
  - Accepts time-of-day: `day at 9am`, `day at 14:00`, `weekday at 9am`
  - Without `now`: schedules only, does NOT run immediately
  - With `now`: schedules AND runs immediately
  - Each run re-registers the cron (self-perpetuating)
  - Cron is session-scoped — dies when the session dies
- **now** (optional) — run immediately. When combined with `every`, runs
  immediately AND schedules. Without `every`, `now` is the default behavior
  (bare invocation always runs immediately).
- **stop** — cancel any existing `/qe-audit` cron and exit. **Takes
  precedence over all other arguments.**
- **next** — check when the next scheduled run will fire. **Takes precedence
  over all other arguments except `stop`.**

**Detection:** scan `$ARGUMENTS` for:
- `stop` (case-insensitive) — cancel cron and exit (highest precedence)
- `next` (case-insensitive) — check schedule and exit
- `bash` (case-insensitive) — bash mode (everything after `bash` until
  `every`/`now`/`stop`/`next` is the area description)
- `now` (case-insensitive) — run immediately
- `every` followed by a schedule expression — scheduling mode

Examples:
- `/qe-audit` — audit recent commits now
- `/qe-audit bash` — bash random under-tested features now
- `/qe-audit bash "undo/redo"` — bash a specific feature now
- `/qe-audit bash "solver" every 6h` — schedule solver bashing every 6h
- `/qe-audit every day at 9am` — schedule daily commit audit (first run at 9am)
- `/qe-audit every day at 9am now` — schedule daily + run now
- `/qe-audit every weekday at 9am` — weekday mornings only
- `/qe-audit bash every 12h now` — bash random features every 12h, start now
- `/qe-audit next` — when's the next audit?
- `/qe-audit stop` — cancel scheduled audits

## Now (standalone — just `now` with no mode or schedule)

If `$ARGUMENTS` is just `now` (no `bash`, no `every`, no area):

1. Use `CronList` to list all cron jobs
2. Find any whose prompt starts with `Run /qe-audit`
3. If found: extract the cron's prompt to get mode, area, and schedule.
   **Run immediately** — do NOT ask for confirmation. The cron stays active.
4. If none found: report `No active /qe-audit cron to trigger. Use
   /qe-audit to run a commit audit manually.` and **exit.**

## Next (if `next` is present)

If `$ARGUMENTS` contains `next` (case-insensitive):

1. Use `CronList` to list all cron jobs
2. Find any whose prompt starts with `Run /qe-audit`
3. Report:
   - If found: parse the cron expression and compute the next fire time.
     Use `date +%Z` for the timezone. Show both relative and absolute:
     > Next QE audit in ~14h 47m (~9:03 AM ET tomorrow, cron XXXX).
     > Mode: commit audit
     > Prompt: Run /qe-audit every day at 9am now
   - If none found: `No active /qe-audit cron in this session.`
4. **Exit.** Do not run anything.

## Stop (if `stop` is present)

If `$ARGUMENTS` contains `stop` (case-insensitive):

1. Use `CronList` to list all cron jobs
2. Delete ALL whose prompt starts with `Run /qe-audit` using `CronDelete`
3. Report what was cancelled:
   - If one found: `QE audit cron stopped (was job ID XXXX).`
   - If multiple found: `Stopped N QE audit crons (IDs: XXXX, YYYY).`
   - If none found: `No active /qe-audit cron found.`
4. **Exit.** Do not run anything.

## Phase 0 — Schedule (if `every` is present)

If `$ARGUMENTS` contains `every <schedule>`:

1. **Parse the schedule** — convert to a cron expression.

   **For interval-based schedules** (`4h`, `2h`, `30m`): use the CURRENT
   minute as the offset so the first fire is a full interval from now.
   Check the current minute with `date +%M`:
   - `4h` at minute 9 → `9 */4 * * *`
   - `12h` at minute 9 → `9 */12 * * *`
   - `30m` → `*/30 * * * *` (no offset needed for sub-hour)

   **For time-of-day schedules**: offset round minutes by a few:
   - `day at 9am` → `3 9 * * *`
   - `day at 14:00` → `3 14 * * *`
   - `weekday at 9am` → `3 9 * * 1-5`

2. **Deduplicate** — use `CronList` + `CronDelete` to remove any whose
   prompt starts with `Run /qe-audit`.

3. **Construct the cron prompt.** Always include `now` in the cron prompt
   so each cron fire runs immediately AND re-registers itself. Note: this
   `now` is for the CRON's invocation, not the current invocation:
   ```
   Run /qe-audit [bash [area]] every <schedule> now
   ```

4. **Create the cron** — use `CronCreate`:
   - `cron`: the cron expression from step 1
   - `recurring`: true
   - `prompt`: the constructed command from step 3

5. **Confirm** with wall-clock time. **Always show times in America/New_York
   (ET)** — use `TZ=America/New_York date` for conversion:

   If `now` is present:
   > QE audit scheduled every day at 9am. Running now.
   > Next audit after this one: ~9:03 AM ET tomorrow (cron ID XXXX).

   If `now` is NOT present:
   > QE audit scheduled every day at 9am.
   > First run: ~9:03 AM ET tomorrow (cron ID XXXX).
   > Use `/qe-audit next` to check, `/qe-audit stop` to cancel.

6. **If `now` is present:** proceed to the audit/bash.
   **If `now` is NOT present:** **Exit.** The cron fires later.

If `every` is NOT present, skip this phase and proceed to the audit/bash
(bare invocation always runs immediately).

## Mode: Commit Audit (default)

Run when `bash` is NOT present in arguments.

1. **Find the last audit checkpoint** — read the bottom of `the QE issues tracker (e.g., `plans/QE_ISSUES.md`)`
   for the last audited commit range and date (format: `*Last audited:
   YYYY-MM-DD — commits <hash> through <hash>*`). If the file doesn't exist
   or has no checkpoint, fall back to `git log --oneline -20`.

2. **List new commits** — `git log --oneline <last_commit>..HEAD`. Skip
   QE-generated commits (messages matching `fix: N QE issues`, `fix: QE batch`,
   `docs: QE audit`, or `test: QE batch`).

3. **If no new commits** — report "no new commits since last audit" and stop.

4. **Audit each commit** — For each commit with code changes, **dispatch
   parallel Explore agents** using the Agent tool (group 4-5 commits per
   agent). Do not audit all commits yourself — dispatch agents for fresh
   eyes on each batch:
   - Read the diff (`git show <hash>`)
   - Read related test files
   - Assess: Are tests good (testing real behavior, not no-ops)? Are there
     coverage gaps? Are there bugs?
   - Rate severity: Critical / High / Medium / Low / Very Low

5. **Create GitHub issues** — For actionable findings (Medium+ severity, or
   Low with clear fix), create issues via `gh issue create`. Include: summary,
   root cause, suggested fix/test, severity, and which commit introduced it.

6. **Update tracker** — Edit `the QE issues tracker (e.g., `plans/QE_ISSUES.md`)`:
   - Add new issues to "Open Issues" section
   - Move any resolved issues to "Resolved Issues"
   - Update the audit date and commit range at the bottom

7. **Report** — Summarize findings: issues filed, notable positives, and
   overall assessment. If a cron is active, include the next run time:
   > Audit complete. Filed N issues. Next audit in ~23h 55m (~9:03 AM ET
   > tomorrow, cron XXXX).

### Tips for commit audit
- Skip docs-only, config-only, and log-only commits
- For physics/solver commits, pay extra attention to numerical correctness
- The registration test count in `tests/blocks/registration.test.js` needs
  updating when blocks are added

## Mode: Bash (stress-test)

Run when `bash` IS present in arguments.

1. **Select target area:**
   - If area specified (e.g., `bash "undo/redo"`): use that area
   - If no area specified: pick under-tested areas based on:
     - Files with low test-to-code ratio
     - Features with recent bug fixes (fragile areas)
     - Complex code paths (solver, codegen, state machine engine)
     - Areas not recently audited

2. **Research the target area:**
   - Read the source code for the selected feature
   - Read existing tests — what's already covered?
   - Identify edge cases, boundary conditions, unusual inputs
   - Think adversarially: what could break? What assumptions are fragile?
   - Identify what types of testing apply (see step 3)

3. **Test the area thoroughly** — use ALL applicable methods, not just
   unit tests. The goal is to exercise the feature the way a user would,
   plus adversarial edge cases:

   **a. Manual UI testing** (for editor, UI, interaction features):
   - Use `/manual-testing` recipes with playwright-cli
   - Exercise real workflows: add blocks, connect ports, run simulations,
     edit parameters, undo/redo, drag, resize, delete
   - Test edge cases manually: rapid clicks, empty inputs, overlapping
     elements, browser resize during interaction
   - Take screenshots as evidence of bugs found

   **b. Codegen & deployment testing** (for codegen, solver, block changes):
   - Pick relevant example models from `examples/`
   - Deploy: generate Rust → `cargo build` → run binary
   - Compare Rust output against JS simulation (same model, same params)
   - Test with multiple example models, not just one
   - For bulk sweeps, dispatch parallel agents (~10 models per agent)

   **c. Adversarial unit tests** (for all areas):
   - Edge cases (empty inputs, zero values, NaN, Infinity, negative numbers)
   - Boundary conditions (max array size, deeply nested structures)
   - Race conditions (rapid undo/redo, concurrent operations)
   - Invalid state (corrupted model data, missing references)
   - Unusual workflows (delete while editing, paste into readonly)

   **d. Integration testing** (for cross-cutting features):
   - Full workflows end-to-end: create model → configure → simulate →
     export → deploy → verify output
   - Cross-feature interactions: state machine chart inside subsystem,
     physics module with controlled sources, etc.

4. **Run automated tests:**
   ```bash
   npm run test:all
   ```
   - Tests that PASS: the feature handles the edge case correctly. Good.
   - Tests that FAIL: found a bug. File a GitHub issue.
   - Tests that CRASH: found a serious bug. File a high-severity issue.

5. **File GitHub issues** for each failure (from any testing method):
   - Include: what was tested, expected vs actual behavior, test code,
     severity rating, suggested fix
   - Tag with appropriate labels

6. **Update `the QE issues tracker (e.g., `plans/QE_ISSUES.md`)`** with new findings.

7. **Clean up test files:**
   - Keep passing adversarial tests (they're valuable regression tests)
   - Keep failing tests too — do NOT remove or comment them out. CLAUDE.md
     says "NEVER weaken tests." A failing bash test is evidence of a real
     bug. Mark them with `{ todo: 'Bug found by QE bash — see #NNN' }` so
     they're skipped but preserved, and file a GitHub issue for each.
   - **ONLY use `todo` for bugs you just DISCOVERED during this bash
     session.** NEVER use `todo` to skip a test that was passing before
     and now fails due to your changes — that's weakening, not discovery.
   - Run `npm run test:all` before committing — all suites must pass
     (todo-skipped tests are acceptable)
   - Commit all tests (passing + skipped) with descriptive message

8. **Report** — Summarize:
   - Area bashed
   - Testing methods used (manual UI, codegen deployment, adversarial
     unit tests, integration)
   - Scenarios tested (count per method)
   - Bugs found (count, severity, method that found them)
   - Issues filed (numbers)
   - Passing tests committed
   - Example models deployed and verified (if applicable)
   - Screenshots taken (if manual testing)
   - If a cron is active, include the next run time

## Key Rules

- **Never weaken tests** — if a bash test reveals a real bug, file an issue.
  Don't make the test pass by loosening assertions.
- **`every` implies autonomous operation** — scheduled audits run without
  user approval.
- **Deduplicate crons** — always remove existing `/qe-audit` crons before
  creating a new one.
- **Crons are session-scoped** — they expire when the session dies.
- **File issues, don't fix inline** — QE audit finds problems. `/fix-issues`
  fixes them. Keep the separation clean.
- **Ultrathink** — use careful, thorough reasoning. Read code, understand
  what changed and why, verify correctness.
