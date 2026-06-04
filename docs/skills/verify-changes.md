# /verify-changes

> Verify recent changes really work: review the diffs, check that tests cover them, run the suite, manually verify UI changes with playwright-cli, fix anything broken, re-verify until clean, then report with recommendations.

<details class="flow-cmd" open>
<summary>How it runs — full verification</summary>

<div class="flow">
<div class="flow-step"><p>A <strong>fresh verifier subagent</strong> reviews the diff and audits test coverage — fresh eyes on the actual code, not session memory</p></div>
<div class="flow-step"><p>The <strong>original agent</strong> runs the full test suite</p></div>
<div class="flow-step"><p>It dispatches <code>/manual-testing</code> for a real browser pass on UI changes</p></div>
<div class="flow-step"><p>It fixes what surfaces and re-verifies, looping until clean</p></div>
<div class="flow-step"><p>It reports findings and recommendations</p></div>
</div>

</details>

## What it does

`/verify-changes` confirms that the changes you just made actually work, before you commit or land them. It looks at the recent changes (by default everything uncommitted in your working tree), reads each changed file to understand what changed and whether it looks correct, checks that the tests cover the changes, runs the test suite, manually exercises any UI changes in a browser, fixes problems it finds, re-verifies, and then reports what passed and what still needs a human to sign off.

The reason to run it is independence. You may have just written the code being verified, and memory of "what I changed" is unreliable — context can be lost between sessions, and you tend to confirm what you expect. `/verify-changes` does the verification against the actual diffs and a real test run rather than from recall, so it catches things a quick self-review would miss. It never produces a verdict from memory: it reads the real diffs and runs the real tests every time.

Verification matches the kind of change. When the project has a configured test command, code changes run the full test suite; the skill reads that command from your project config rather than guessing or hardcoding one. A project with no tests and no configured command (a docs-only or greenfield repo) skips the test run and records that skip explicitly in the report, so a reviewer can see tests were not run by design. If the project has tests but no command is configured, `/verify-changes` refuses to claim it verified anything and tells you to fix the config first — it will not silently skip a suite that exists.

UI changes get a second, mandatory check: the skill drives the change in a real browser with playwright-cli, takes screenshots as evidence, and exercises the behavior with real clicks and keypresses. Some UI changes also need a human to judge them — animation quality, visual layout, UX feel — and the skill flags those for you to sign off on, since it cannot close them itself.

When it finds problems it fixes them rather than just listing them: missing tests get written, failing tests get fixed at the root cause (never weakened to pass), and broken behavior gets corrected and re-verified. It re-runs up to two fix-and-verify rounds; if the same error survives both, it stops and reports what it tried instead of guessing further.

The output is a report. It is always printed inline, and a report file is also written when there are items that need a human to sign off later. When everything is clean with nothing left to check, it says so inline and skips the file. The report covers what changed, how each item was verified, the test-suite result, and any next-step recommendations.

## Usage

```
/verify-changes [scope]
```

`scope` selects which changes to verify. Omit it to verify all uncommitted changes in your working tree (the common case).

## Typical usage

The common form is bare — verify everything in the working tree before committing:

```
/verify-changes
```

You can narrow or widen the scope:

```
/verify-changes worktree
/verify-changes branch
/verify-changes last 3
```

`worktree` checks the current worktree against its base branch, `branch` checks every commit on the current branch against `main`, and `last N` checks just the last N commits. `/verify-changes branch` is the right scope for a final, whole-feature pass at the end of a multi-commit branch.

## Companion skills

- **`/commit`** — `/verify-changes` is the gate you run before committing. Verify first, then `/commit` to stage and land the work once it is clean.
- **`/do`** — runs `/verify-changes` automatically on code changes before landing. For content-only changes (markdown, images), `/do` skips the full test suite and does a focused diff review instead.
- **`/run-plan`** and **`/research-and-go`** — call `/verify-changes` to confirm work is sound as plans and decomposed goals execute.
- **`/manual-testing`** — the UI-verification recipes (auth bypass, browser setup, selectors) that `/verify-changes` follows when exercising UI changes.
- **`/qe-audit`** — the contrast, not a substitute. `/verify-changes` checks *your recent changes* and gates a commit; `/qe-audit` hunts the repo at large for coverage gaps and bugs and files issues — it generates work rather than confirming a specific change.
- **`/fix-report`** — presents the items `/verify-changes` flagged as needing human sign-off so they can be reviewed before issues are closed.

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| (omit) | No | Verify all uncommitted changes in the working tree (default) |
| `worktree` | No | Verify changes in the current worktree against its base branch |
| `branch` | No | Verify all commits on the current branch against `main` |
| `last` | No | Verify only the last commit (same as `last 1`) |
| `last N` | No | Verify the last N commits |

The scope argument is optional; with nothing given, `/verify-changes` verifies the current working-tree changes.

## Examples

```
/verify-changes
/verify-changes worktree
/verify-changes branch
/verify-changes last 3
```

## Common Patterns

- **Pre-commit check:** `/verify-changes` — verify everything in the working tree before you commit.
- **Worktree review:** `/verify-changes worktree` — review all the changes in a worktree before landing it.
- **Whole-feature audit:** `/verify-changes branch` — verify every commit on the current feature branch as a final pass.

## Tips & Gotchas

- It never verifies from memory — it reads the actual diffs and runs the actual tests, even on code you just wrote.
- It fixes problems rather than just reporting them, then re-verifies; it stops after two fix-and-verify rounds if the same error keeps recurring.
- Code changes run the project's configured test command; a project with no tests and no configured command skips the suite and records the skip in the report. If tests exist but no command is set, it refuses to claim verification and tells you to fix the config.
- UI changes are verified in a real browser with playwright-cli, with screenshots as evidence. It starts a dev server itself if one isn't running — "no dev server" is not a reason to skip.
- Some UI changes need a human to sign off (visual layout, animation, UX feel); the skill flags these with instructions but cannot close them.
- It never commits, merges, or pushes without permission — except that when working inside a worktree it commits its fixes so they survive for cherry-pick.
