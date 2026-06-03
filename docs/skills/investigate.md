# /investigate

> Deep debugging for one complex bug at a time. A disciplined workflow — reproduce, trace, state the root cause, fix, verify — that makes the agent prove it understands the bug before it writes a fix.

## What it does

`/investigate` takes one bug whose cause is unclear and works it end to end: it reproduces the bug, traces the failure back to its source, states the root cause in writing, applies a minimal fix, and verifies that fix. The defining discipline is that no fix may be written until the root cause has been proven — the skill exists precisely because the natural instinct is to skip straight to "try a fix," and every step here is built to prevent that.

It is for a single bug, not a backlog. If you want to work through several issues, that is `/fix-issues`, not `/investigate` — the skill will redirect you. `/investigate` is the right tool when the cause is genuinely unclear and guessing has already failed or would waste time.

The work moves through five stages, in order:

- **Reproduce.** See the bug with your own eyes — observe it, don't just read about it. Depending on the kind of bug, that means driving the UI with `playwright-cli` and taking a screenshot, writing a minimal failing test, capturing a stack trace, or running the specific failing test. The reproduction (screenshot, test output, or error message) is recorded as evidence. If the bug genuinely can't be reproduced (for example, a non-deterministic race, or something that needs a specific browser or OS), the investigation may continue with an explicit note that it is lower-confidence — but "I can see it in the code" or "reproducing would take too long" are not acceptable reasons to skip.
- **Trace.** Follow the code from the symptom backward — which function produced the wrong value, what called it, where its arguments came from — until you reach the first place something actually goes wrong. The skill uses `Grep` to find call sites and `Read` to inspect the real code rather than working from memory, and consults git history (`git show`, never `git checkout`, so the working tree is left untouched) when a regression is suspected. The output is a stated causal chain: A calls B with X, B passes X to C, C breaks on X because of Y.
- **Root cause.** Write the diagnosis down before touching any code: what's broken and where, the observed evidence that proves it (not a guess — specific output, a test result, an error), the causal chain, why existing tests didn't catch it, and what the fix will change. When you run `/investigate` yourself, it pauses here to show you the root-cause statement and wait for your confirmation before going further, in case you have context that changes the analysis.
- **Fix.** Write the regression test first and confirm it fails — a test that passes without the fix proves nothing. Then change the minimum code needed to address the root cause, with no refactoring of nearby code and no fixing of other bugs noticed along the way (those get filed as separate issues). Run the test again; it must now pass. If the fix fails twice, the skill stops and reports what it tried rather than guessing a third time.
- **Verify.** Confirm the regression test passes, re-run the original reproduction to confirm the bug is gone, and run the full test suite. If the fix touched shared code, it checks other callers for side effects. A test that fails in code the fix didn't touch follows the project's pre-existing-failure protocol rather than being silently absorbed.

The deliverables are the fix, the regression test, and an inline report — `/investigate` writes no persistent report file. The report lays out the reproduction, the root cause, what changed, and the verification results. If the investigation is abandoned (couldn't reproduce, couldn't find the cause, or the fix failed twice), it reports what was learned and what remains unknown instead.

## Usage

```
/investigate <description or #issue>
```

## Typical usage

Point `/investigate` at one bug — either a GitHub issue number or a plain description of the symptom:

```
/investigate #387
/investigate Scope block shows NaN after 10 seconds of simulation
/investigate test failure in tests/blocks/pid.test.js "derivative term"
```

When you give it an issue number, `/investigate` fetches that issue with `gh issue view` and reads the full body and comments — not just the title — as its starting point. (Reading only the title has burned past investigations: issue #387's "reset button" was misread as "clear the canvas" when the body said "reset mappings to defaults.") A plain description starts from the symptom you describe: an error message, a wrong-output behavior, or a specific failing test.

When the input is an issue number, `/investigate` also claims that issue first, so a parallel `/fix-issues` run (or another `/investigate`) won't work the same issue at the same time. If the issue is already claimed by another run, `/investigate` declines and stops. A plain-text description claims nothing, since there's no issue to claim.

## Companion skills

- **`/fix-issues`** — the batch counterpart. `/investigate` is for one bug at a time; for working through several issues, use `/fix-issues`, which will redirect you here when a single bug needs deeper digging. When `/fix-issues` can't diagnose a bug within its normal flow (two failed attempts), it skips that issue with a note that it needs deeper investigation, and you then run `/investigate` on it. There is no automatic escalation — the hand-off is your decision.
- **`/quickfix`** and **`/do`** — where the fix goes once the root cause is known. `/quickfix` assumes the fix is already understood; `/investigate` is what you run first when it isn't. Once `/investigate` has proven the cause, the fix itself can be carried by `/quickfix` (edit in place on `main`, valid only when `main` is unprotected) or `/do` (isolated in a worktree). Choose between those two by project policy.

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<description or #issue>` | Yes | The bug to investigate — either a plain-text symptom description, or a GitHub issue reference like `#387` |

`/investigate` takes a single argument. Two forms are accepted (`skills/investigate/SKILL.md:40-43`):

- **`#N`** — a GitHub issue number. The issue is fetched with `gh issue view`, and its title, body, and comments become the starting point. This form also triggers the issue claim described under Typical usage.
- **Free text** — a description of the bug: an error message, an observed behavior, or a failing test name.

## Examples

```
/investigate #387
/investigate Scope block shows NaN after 10 seconds of simulation
/investigate test failure in tests/blocks/pid.test.js "derivative term"
```

## Tips & Gotchas

- One bug at a time — this is not `/fix-issues`. For batch fixing, use `/fix-issues`.
- No fix before reproducing, and no fix before the root cause is stated. Writing code earlier means guessing, which is the exact thing `/investigate` exists to prevent.
- The regression test must fail before the fix is applied. A test that passes without the fix doesn't capture the bug.
- The fix is minimal. Other bugs noticed while tracing are filed as separate issues, not folded into this fix.
- Two attempts is the maximum. If the same test fails after two fix attempts, `/investigate` stops and reports rather than guessing again.
- When stuck — flaky reproduction, unclear cause, or a fix with unexpected consequences — `/investigate` reports its findings and asks rather than fabricating an explanation. "I don't know" is a valid answer.
