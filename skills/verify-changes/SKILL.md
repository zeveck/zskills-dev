---
name: verify-changes
disable-model-invocation: false
argument-hint: "[scope: worktree | branch | last [N]]"
description: >-
  Verify all recent changes: review diffs, check that appropriate unit/e2e tests
  exist and correctly test the changes, run all tests, manually verify UI changes
  with playwright-cli, fix any problems found, re-verify until clean, then report
  results with recommendations.
---

# /verify-changes [scope] — Verify, Test & Fix Changes

Thoroughly verify all recent changes in the working tree (or a specified scope).
Reviews diffs, checks test coverage, runs tests, manually verifies UI changes,
fixes any problems found, re-verifies recursively until clean, then reports
results with next-step recommendations.

**Ultrathink throughout.** Use careful, thorough reasoning at every step. Read the
code, understand what changed and why, verify correctness — don't just skim.

**NEVER verify from memory. Dispatch fresh agents.** You may have just written
the code being verified — that's exactly why YOU should not be the verifier.
Dispatch agents to do the actual verification work. Fresh agents have no
memory of the implementation and will catch things you'd miss because you
"know" what the code does.

At minimum, dispatch an agent for Phase 1-2 (read diffs, audit coverage)
and run tests yourself (Phase 3). For complex changes, dispatch separate
agents for different verification concerns (diff review, test coverage,
manual testing).

Do not produce a verification report based on what you remember doing.
Context compaction means your memory of what you changed may be incomplete
or wrong. The ENTIRE POINT of `/verify-changes` is fresh eyes on the actual
state of the code, not a rubber stamp of what you think you did.

Past failure: a verification was done entirely from memory without reading
a single diff or dispatching any agents — it just confirmed "looks good"
based on session recall.

## Arguments

```
/verify-changes [scope]
```

- **scope** (optional) — what changes to verify:
  - (omit) — all uncommitted changes in the working tree (default)
  - `worktree` — changes in the current worktree vs its base branch
  - `branch` — all commits on the current branch vs main
  - `last` — only the last commit (same as `last 1`)
  - `last N` — the last N commits

Examples: `/verify-changes`, `/verify-changes worktree`, `/verify-changes last 3`

## Phase 1 — Inventory Changes

1. **Determine the diff scope** based on the argument:
   - Default: `git diff` + `git diff --cached` + `git status -s`
   - `worktree`: `git diff $(git merge-base HEAD main)..HEAD` + `git diff` + `git diff --cached`
   - `branch`: `git log main..HEAD --oneline` + `git diff main...HEAD`
   - `last`: `git diff HEAD~1..HEAD`
   - `last N`: `git diff HEAD~N..HEAD`

2. **List all changed files** with their change type (added/modified/deleted):
   ```bash
   git diff --name-status [scope]
   ```

3. **Read and understand every changed file.** For each file:
   - What was the change? (new feature, bug fix, refactor, test, config)
   - What is the intent? (read commit messages, issue references, comments)
   - Does the change look correct? (logic errors, edge cases, off-by-ones)
   - Any security concerns? (XSS, injection, unsanitized input)
   - Any CLAUDE.md rule violations? (weakened tests, external deps, etc.)

4. **Produce a change inventory table:**

   | File | Change Type | Description | Tests Needed |
   |------|-------------|-------------|--------------|

## Phase 2 — Test Coverage Audit

For each changed file, verify appropriate tests exist:

1. **Source code changes** (`src/**`):
   - Find the corresponding test file(s) in `tests/`
   - Verify test cases exist that exercise the changed code paths
   - Check that tests are meaningful — not just smoke tests, but actually
     testing the specific behavior that changed
   - If a bug fix: does a regression test exist that would have caught the bug?
   - If a new feature: do tests cover the happy path AND edge cases?

2. **Component/module changes** — find corresponding test files and verify
   output computation, parameter handling, edge cases are tested.

3. **Engine/solver changes** — check analytical verification tests where
   applicable. Verify numerical accuracy assertions (tolerances, convergence).

4. **Codegen/build changes** — verify compile tests exist. Check behavioral
   parity between source and generated code.

5. **UI/editor changes** — check for E2E tests. Flag for manual verification
   in Phase 4.

6. **Produce a coverage assessment:**

   | File | Test File(s) | Coverage | Gaps |
   |------|-------------|----------|------|

   Coverage ratings: **Good** (meaningful tests exist), **Partial** (some paths
   untested), **Missing** (no tests), **N/A** (config, docs, etc.)

## Phase 3 — Run Tests

1. **Run the full test suite with output captured to a file:**
   ```bash
   npm run test:all > .test-results.txt 2>&1
   ```
   **Never pipe** through `| tail`, `| head`, `| grep` — it loses output
   and forces re-runs. Capture once, then read `.test-results.txt` to find
   failures. This runs unit tests (~4,000), then auto-detects whether the
   dev server and cargo are available for E2E and codegen tests.

2. **If tests fail, diagnose with targeted runs.** Read `.test-results.txt`
   to identify the failing test file, then run ONLY that file:
   ```bash
   node --test tests/the-failing-file.test.js
   ```
   Do NOT re-run `npm run test:all` to diagnose — that wastes 5 minutes
   when the single file takes 30 seconds. Use `test:all` only as the final
   gate after fixes.

3. **Pre-existing failure protocol.** If a test fails in code you didn't
   touch, it may be pre-existing — not caused by the changes you're verifying.
   This also applies when you've hit the max 2 fix attempts on a failure
   and suspect the root cause predates your changes.

   a. **Verify it's pre-existing:** check `git log --oneline -5 -- <test-file>`
      and `git log --oneline -5 -- <source-file>`. If neither was modified
      by the changes under review, the failure predates your work.

   b. **Research and file a GitHub issue** (`gh issue create`) with:
      - Title: `Test failure: <test name>`
      - Verbatim error output from `.test-results.txt`
      - The exact `assert.*` line from the test source (read the test code)
      - Reproduction command: `node --test tests/<file>.test.js`
      - `git log` evidence that the failure predates current changes
      - Label: `test-restore`

   c. **Mark the test skipped** referencing the issue:
      - Change `it('name',` to `it.skip('name // #NNN',`
      - Commit the skip and the issue number together

   d. **Re-run the failing test file** to confirm the skip works, then
      run `npm run test:all > .test-results.txt 2>&1` as the final gate.

   e. **Guardrails:**
      - Never skip a test in a file you modified or that tests code you modified
      - Never skip a test you wrote
      - If you're about to skip a 3rd test in one session, STOP and report
        to the user — 3+ pre-existing failures suggests a systemic problem

4. **Record results:**

   | Suite | Result | Failures |
   |-------|--------|----------|

## Phase 4 — Agent Verification + User Verification Classification

Two types of verification — both are mandatory for UI changes:

**Agent verification (MANUAL):** The agent tests the change via playwright-cli.
This is YOUR job. You MUST do this for any change that touches UI files.
The pre-commit hook will block commits if `playwright-cli` wasn't used in
the session when UI files are staged. This is not optional.

**User verification (USER):** Some changes need the HUMAN to see them —
judgment calls about animation quality, visual layout, UX feel. The agent
flags these but cannot close them. Mechanically classified: if
UI/editor/styles files changed → `User Verify: NEEDED`. `/fix-report`
Step 2 presents these to
the user before closing.

### Agent verification steps

Use the `/manual-testing` skill for recipes, selectors, and setup instructions.

**"No dev server" is not an excuse to skip.** If UI files changed and no
dev server is running, START ONE:
```bash
npm start &
```
Wait a few seconds, then proceed. The dev server is a static file server —
it takes 2 seconds to start. Reporting "N/A (no dev server)" when you could
have started one is skipping, not verifying.

1. **For each UI/interaction change:**
   - Start a dev server if one isn't running
   - Follow `/manual-testing` setup (auth bypass, browser open)
   - Reproduce the scenario that exercises the change using real events
   - Take screenshots as evidence
   - Verify the expected behavior occurs
   - Test edge cases (undo/redo, rapid clicks, empty inputs, etc.)

2. **For non-UI changes**, verify manually where possible:
   - Solver changes: build a small test model, run simulation, check output
   - Block changes: place the block, configure params, run sim, verify scope output
   - Import/export: load a test file, verify round-trip

3. **Record verification results with both columns:**

   | Change | Agent Verify | User Verify |
   |--------|-------------|-------------|
   | Button offset fix | PASS (screenshot) | NEEDED |
   | Solver tolerance | PASS (tests) | N/A |

   Skip agent verification ONLY if no changes are UI-related or manually
   verifiable. User Verify is always classified (NEEDED or N/A) based on
   file paths.

4. **For each `User Verify: NEEDED` item, include verification instructions:**
   - What to look at (specific UI element, interaction, visual behavior)
   - How to reproduce (steps: open app, navigate to X, click Y, observe Z)
   - What "correct" looks like (expected appearance, behavior, output)
   - URL: `http://localhost:$(node scripts/port.js)/`

   The user may be verifying hours later in a different context. "NEEDED"
   without instructions is useless — the user won't know what to check.

## Phase 5 — Fix Problems

If any issues were found in Phases 2-4:

1. **Test gaps** — write the missing tests:
   - Unit tests for uncovered code paths
   - Regression tests for bug fixes
   - E2E tests for UI changes (if appropriate)

2. **Test failures** — fix the root cause:
   - **Never weaken tests to make them pass.** Fix the code, not the test.
   - If the test itself is genuinely wrong (testing the wrong expected value),
     fix the test and document why.
   - **Never modify the working tree to check if a failure is pre-existing.**
     No `git stash && npm test && git stash pop`, no checkout of old commits,
     no comparison worktrees. If you touched code and tests fail, assume your
     changes caused it and fix them. See CLAUDE.md for the full rule and the
     past failure that motivated it.

3. **Code issues** — fix logic errors, edge cases, security concerns found in
   Phase 1.

4. **Manual verification failures** — fix the behavior, then re-verify.

5. **If working in a worktree**, commit fixes so they are preserved for
   cherry-pick. Use descriptive commit messages referencing what was fixed.

## Phase 6 — Re-verify (max 2 rounds)

After fixing any issues in Phase 5:

1. **Run `npm run test:all` again** — all suites must pass, including new tests
2. **Re-check manual verifications** if fixes touched UI code
3. **If new problems are found**, go back to Phase 5

**Maximum 2 fix+verify rounds.** If the same error recurs after two fix
attempts, **STOP.** Report what was tried, what failed both times, and why
you think it's failing. Do not keep guessing — let the user decide. (See
CLAUDE.md: "NEVER thrash on a failing fix.")

## Phase 7 — Report

**Always output the report inline.** Additionally, write the report FILE
to `reports/verify-{scope-slug}.md` and regenerate the index — but ONLY
if there are `User Verify: NEEDED` items that require human sign-off. If
all items are clean (no `[ ]` checkboxes), say so inline and skip the file:

> Verification clean — no user sign-off needed. [summary of what passed]

The report file exists for the user to review LATER. If there's nothing
to review later, the inline output is sufficient.

**Worktree write path:** Reports are ALWAYS written to the **main repo's**
`reports/` directory, not the worktree's. When running inside a worktree,
resolve the main repo root first:
```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
```
Then write to `$MAIN_ROOT/reports/` and `$MAIN_ROOT/VERIFICATION_REPORT.md`.
This prevents reports from being lost when the worktree is cleaned up.

### Scope slug derivation

| Scope argument | Report file |
|----------------|-------------|
| (default/omit) | `reports/verify-working-tree.md` |
| `worktree` | `reports/verify-worktree-{name}.md` (name = `basename` of worktree path) |
| `branch` | `reports/verify-branch-{branch-name}.md` |
| `last N` | `reports/verify-last-{N}.md` |
| `last` | `reports/verify-last-1.md` |

### Report structure

**Header:**
```markdown
# Verification Report — YYYY-MM-DD HH:MM
Scope: [default | worktree | branch | last N]
{One-line summary.} **Check the User column and sign off.**
Legend: ✅ verified, ⚠️ partial, ❌ failed, ➖ not applicable, [ ] not yet checked
```

**Changes Reviewed** — inventory table at the top:
```markdown
## Changes Reviewed
| File | Change | Verdict |
|------|--------|---------|
```

**Domain-grouped sections** — group by concern (UI/UX, Codegen, etc.),
NOT by workflow state. Each section uses a single-checkbox checklist
(no summary table + detail card dual-checkbox pattern):

```markdown
## UI / UX Changes

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
screenshots directly under each checkbox. One item per distinct thing
to verify — not "3 blocks in explorer" but one per block.

**Outcome sections** (include only non-empty):
- **Skipped Verification** — per-item reason
- **Pre-existing Bugs Discovered** — found during verification
- **Test Suite Status** — command + per-suite counts

**Recommendations:**
- Next steps (commit, push, review)
- Open concerns needing human judgment

### Index regeneration

After writing the scope-specific report, regenerate `VERIFICATION_REPORT.md`
in the repo root as an **index** of all verification reports:

1. **Scan** `reports/verify-*.md` files
2. **For each file:** extract the H1 line (date, scope) and count `[ ]`
   checkboxes (action items remaining)
3. **Write** `VERIFICATION_REPORT.md` with this structure:

```markdown
# Verification Reports Index

Legend: ✅ all signed off, [ ] action items remain

## Needs Sign-off

{Extract ALL `[ ]` items from all reports. For each, show the checkbox,
the item title, and link to the source report file.}

- [ ] Block Rotation sign-off — [verify-working-tree.md](reports/verify-working-tree.md)
- [ ] Solver tolerance sign-off — [verify-last-3.md](reports/verify-last-3.md)

{If no `[ ]` items remain across any report, write: "All items signed off."}

**Staleness rule:** Reports older than 7 days with unchecked `[ ]` items are
flagged as **STALE** in the index (append ` ⚠️ STALE` to the action items
column). Stale items are never auto-removed — the user decides whether to
re-verify or dismiss them.

---

## Reports

| Report | Date | Scope | Action Items |
|--------|------|-------|:------------:|
| [verify-working-tree.md](reports/verify-working-tree.md) | 2026-03-18 14:30 | working tree | 2 [ ] |
| [verify-last-3.md](reports/verify-last-3.md) | 2026-03-17 09:15 | last 3 | ✅ |
```

If there are no `reports/verify-*.md` files (e.g., all were cleaned up),
write just the header and "No verification reports found."

## Key Rules

- **Never commit, merge, or push without explicit user permission** — unless
  working in a worktree where committing fixes is part of the workflow (Phase 5).
  Even then, never merge the worktree into main or push.
- **Never weaken tests.** Fix the code, not the test. Do not loosen tolerances,
  skip assertions, or remove test cases.
- **Ultrathink.** Use careful, thorough reasoning throughout. Read code carefully.
  Understand what changed and why before judging correctness.
- **Never verify from memory.** Read actual diffs, actual files, run actual
  tests. Even if you just wrote the code — read it again. Memory is not
  verification.
- **Real events for manual testing.** Never use `eval` or `page.evaluate()` to
  simulate user actions. Use real click/drag/type/press events.
- **Fix, don't just report.** When problems are found, fix them — then re-verify.
  The goal is a clean verification, not a list of issues left for the user.
- **Start a dev server if needed.** "No dev server" is not an excuse to
  skip manual verification. Run `npm start &`
  — it takes 2 seconds. Only report "cannot verify" for genuinely
  unavailable tooling (e.g., no cargo for codegen).
- **Be thorough but honest.** If something genuinely can't be verified,
  say so explicitly. Don't skip silently.
- **Respect existing changes.** Never discard, revert, or overwrite uncommitted
  work that isn't part of the verification scope.
