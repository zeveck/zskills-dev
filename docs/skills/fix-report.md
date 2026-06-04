# /fix-report

> The interactive review companion to `/fix-issues`. Walks you through every sprint result you haven't signed off yet — confirming fixes, landing them, closing the matching GitHub issues, updating trackers, and cleaning up. Always interactive; no arguments.

<details class="flow-cmd" open>
<summary>How it runs — interactive sign-off</summary>

<div class="flow">
<div class="flow-step"><p>The <strong>agent</strong> gathers every unreviewed sprint result</p></div>
<div class="flow-step"><p>It walks you through each fix — UI changes get a browser pass/fail check</p></div>
<div class="flow-step"><p><strong>You</strong> approve each step</p></div>
<div class="flow-step"><p>It lands the fixes, closes the issues, and removes the worktrees</p></div>
<div class="flow-step"><p>It writes the final sign-off report</p></div>
</div>

</details>

## What it does

`/fix-issues` does the fixing; `/fix-report` clears the results. When `/fix-issues` runs a backlog — often unattended on a schedule — its results pile up unreviewed. `/fix-report` gathers all of that unreviewed work into one picture and walks you through clearing it. It covers everything outstanding, not just the most recent run: if `/fix-issues` has been working on a cron for a day, `/fix-report` presents all of it at once.

It is always interactive. There is no `auto` flag — it shows you what happened, stops, and waits for your go-ahead before doing anything. Nothing lands, closes, or gets deleted without your say-so.

It starts with a combined summary across every sprint you haven't signed off: what was fixed, what's already on `main`, what still needs you to look at it, and what was skipped — broken out by reason, since the reason tells you what to do next (too vague means it needs a clearer description from you; too complex means it should go to `/run-plan`; a merge conflict will be retried by a later run on its own).

For any fix that touched the UI, `/fix-report` gives you concrete steps to check it in the browser — what to open, what to click, what "correct" looks like — and asks you to mark it pass or fail. A fix that fails this check is held back and not finalized.

Then it asks you to approve the sprint. Once you do, it lands the fixes that aren't on `main` yet, closes the GitHub issues they resolve, marks them done in your issue trackers, removes the worktrees that are safe to remove, and writes a final report you can sign off against later. Fixes that `/fix-issues` already opened as pull requests are recognized as such — `/fix-report` shows you the PR link and its CI status instead of trying to re-land them.

Every one of those actions waits for your explicit approval first. `/fix-report` never advances on its own.

## Usage

```
/fix-report
```

## Typical usage

There is nothing to configure and nothing to pass — you run it bare:

```
/fix-report
```

The usual moment to run it is after `/fix-issues` has been working a backlog (especially on a schedule) and you want to catch up on everything it did, review the fixes, and finalize the ones you're happy with.

## Companion skills

- **`/fix-issues`** — the skill `/fix-report` reviews. `/fix-issues` fixes a backlog of issues; `/fix-report` is how you confirm and clear the results afterward.
- **`/commit`** — how you land the report and tracker changes when you're done, typically `/commit pr`.
- **`/manual-testing`** — drives the in-browser checks for UI fixes during the verification step.
- **`/run-plan`** — where a fix skipped as too complex should go; `/fix-report` flags those for you.

## Arguments

`/fix-report` takes no arguments. It is always interactive and has no `auto` flag — it guides you one step at a time and waits for your approval at each one.

## Common Patterns

- **After a run of autonomous sprints:** `/fix-report` — surfaces everything `/fix-issues auto` accumulated since you last checked, all at once.
- **Routine sign-off:** `/fix-report` — review the latest results, approve the good fixes, finalize.

## Tips & Gotchas

- It is the human-review counterpart to `/fix-issues auto`. If you never run `/fix-report`, autonomous fixes stay reviewed-but-not-finalized.
- It pauses for your approval at every step. Read what it shows you and tell it to continue — it will not move on by itself.
- Skipped issues are broken out by reason. A "too vague" skip is waiting on a clearer description from you; a merge-conflict skip will be retried automatically by a later `/fix-issues` run.
- A UI fix that fails your in-browser check is held back, not finalized, and stays open for the next run.
- Pull-request fixes are shown with their PR link and CI status rather than re-landed — review and merge those on GitHub.
