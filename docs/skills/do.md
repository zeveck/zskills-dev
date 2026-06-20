# /do

> Lightweight task dispatcher for ad-hoc work: documentation, examples, refactoring, content updates. Worktree/direct/pr landing modes via flag or config. Recurring via `every SCHEDULE`; `stop`/`next` manage the schedule.

<details class="flow-cmd" open>
<summary>How it runs — worktree → PR</summary>

<div class="flow">
<div class="flow-step"><p><strong>You</strong> describe the task</p></div>
<div class="flow-step"><p>The <strong>original agent</strong> turns your task into a plan</p></div>
<div class="flow-step"><p>A <strong>reviewer subagent</strong> checks the plan and loops until it approves<br>(you can raise the round count with <code>--rounds</code> (default 1))</p></div>
<div class="flow-step"><p>An <strong>implementer subagent</strong> builds it in a worktree</p></div>
<div class="flow-step"><p>A <strong>verifier subagent</strong> verifies the change</p></div>
<div class="flow-step"><p>The <strong>original agent</strong> lands it via a PR and monitors CI (up to 2 fix attempts)</p></div>
<div class="flow-step optional"><p>If you pass <strong>automerge</strong>, it requests merge — GitHub merges once required checks pass</p></div>
</div>

</details>

## What it does

`/do` is the everyday workhorse: it takes a single self-contained task and runs it end to end — researching the change, making it, verifying it, and (when you ask) landing it. "Lightweight" here is relative to `/draft-plan`, not a size limit: it means no multi-phase plan and no open design to work out, *not* "small." Documentation, examples, refactors, a new UI element, plumbing new UI, one-off fixes, and content updates all fit. What sends a task elsewhere is unresolved design or work that needs staging into ordered phases (`/draft-plan`), or an issue backlog to clear (`/fix-issues`) — never the number of files touched.

Given a plain-English description, `/do` first checks that the task is actually a good fit for it. If the description spans several unrelated areas, names many files, or asks for a feature-scale change, `/do` redirects you to a better skill (`/draft-plan` for plan-scale work, `/run-plan` when you point at an existing plan file) instead of attempting it. If the description is too vague to act on, it asks you to make it concrete. You can override a redirect with `--force`.

Once it decides to proceed, `/do` dispatches a fresh review agent to sanity-check its plan before any code is written, then does the work, then verifies it. Verification matches the kind of change: code changes run the full test suite and a separate `/verify-changes` pass, while content-only changes (markdown, images, presentations) skip the test suite and instead get a focused review of the diff. The `auto` flag controls whether the result lands autonomously — it does not control whether verification runs; code changes are always verified.

How the result reaches `main` depends on the landing mode (see Arguments). The common shape in a protected-`main` repo is a pull request: `/do` opens a worktree, makes the change there, runs the verification gate locally, opens a PR, and watches CI. Output is brief and inline — `/do` writes no persistent report file; the commit (or PR) is the artifact.

## Usage

```
/do <description> [worktree|direct|pr] [auto] [every SCHEDULE] [now] [--force] [--rounds N]
/do stop [query]
/do next [query]
/do now [query]
```

## Typical usage

The most common form is a free-text description, optionally autonomous, optionally on a schedule:

```
/do Make sure docs are up to date
/do Sort the screenshots in session-sequence-snapshots
/do Update the presentation auto
/do Add dark mode to editor pr
/do Check for broken links in examples every 12h now
```

A description alone runs the task immediately. Add a landing flag (`pr`, `worktree`, `direct`) to override the configured default. Add `auto` to run without stopping for approval; add `automerge` to also auto-merge the PR. Add `every SCHEDULE` (with `now` to also run straight away) to turn the task into recurring maintenance.

## Companion skills

- **`/draft-plan`** — where `/do` redirects you when a task is too big for a single pass. `/draft-plan` researches and decomposes plan-scale work.
- **`/run-plan`** — where `/do` redirects you when the description references an existing plan file; `/run-plan` executes plans.
- **`/fix-issues`** — for working a backlog of issues rather than a single ad-hoc task; `/do` redirects issue-batch work here.
- **`/verify-changes`** — the verification gate `/do` runs on code changes before landing.
- **`/land-pr`** — dispatched by `/do` in PR mode to handle the full PR lifecycle (push, CI polling, fix-cycle on failure). You never type it directly.
- **`/cleanup-merged`** — run after a `/do` PR merges to catch your local clone up.

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `description` | Yes | What to do, in natural language |
| `worktree` | No | Isolate work in a worktree, cherry-pick back to `main` after verification |
| `direct` | No | Work on `main` in place, no landing step |
| `pr` | No | Named worktree + feature branch, push, open a PR, poll CI |
| `auto` | No | Land autonomously (unattended mode). In PR mode the PR is created but NOT auto-merged; see `automerge` |
| `automerge` | No | Unattended + auto-merge the PR (PR mode). Implies `auto`. |
| `every SCHEDULE` | No | Self-schedule recurring runs (`4h`, `12h`, `day at 9am`, `weekday at 9am`) |
| `now` | No | Run immediately (with `every`: run now AND schedule) |
| `--force` | No | Bypass a triage redirect and a review rejection |
| `--rounds N` | No | Maximum review/refine cycles (default 1; `0` skips review with a warning) |
| `--no-claim` | No | Treat any `#N` in the description as a mere mention, not an issue to claim |

The three landing flags (`worktree`, `direct`, `pr`) are mutually exclusive and override the `execution.landing` default in `.claude/zskills-config.json`. When no flag is given, the mode comes from that config (`cherry-pick` maps to `worktree`, `pr` to `pr`, `direct` to `direct`); with no config, the default is `direct`. `direct` mode is rejected when `execution.main_protected` is `true` — use `pr` or `worktree` instead.

If the description references an issue in claim position (a leading `#N`, or `Fix #N …`), `/do` claims that issue so a parallel run won't duplicate the work. A bare `#N` elsewhere in the description triggers a warning (or, if that issue is currently being worked by another run, a stop) — pass `--no-claim` when the reference is deliberate and you are not working that issue.

## Subcommands

### `stop [query]`

Cancel `/do` cron(s). Bare `/do stop` cancels all. With a query (`/do stop Check docs`), targets the matching cron via fuzzy description matching.

### `next [query]`

Show next fire time(s). Bare `/do next` shows all. With a query, shows the matching cron's schedule.

### `now [query]`

Trigger a cron immediately. Bare `/do now` triggers the single cron (or asks if there are several). With a query, triggers the matching cron.

## Examples

```
/do Add example models for Integrator and Derivative blocks
/do Sort the screenshots in session-sequence-snapshots
/do Refactor color constants in main.css worktree
/do Update the presentation auto
/do Make sure docs are up to date every day at 9am
/do Check for broken links in examples every 12h now
/do Add dark mode to editor pr
/do Add dark mode pr auto
/do next
/do next Check docs
/do stop
/do stop Check docs
```

## Common Patterns

- **Quick content task:** `/do Sort the screenshots` — direct mode, no ceremony
- **Isolated refactor:** `/do Refactor color constants worktree` — work in a worktree, verify, no auto-land
- **PR with auto-merge:** `/do Add dark mode pr automerge` — open a PR and request auto-merge
- **Recurring maintenance:** `/do Check for broken links every 12h now` — schedule and run immediately
- **Bypass gates:** `/do Fix the tooltip bug --force` — skip the triage and review checks for a known-simple fix

## Tips & Gotchas

- `/do` may redirect a task that's too large (to `/draft-plan`), references a plan file (to `/run-plan`), or is issue-batch work (to `/fix-issues`) — pass `--force` to proceed anyway.
- A fresh review agent checks `/do`'s plan before any work begins — `--rounds 0` skips this with a warning.
- Verification runs on all code changes regardless of `auto`; content-only changes skip the test suite and get a focused diff review instead.
- PR mode runs the same local verification gate as the other modes before opening the PR, then dispatches `/land-pr` for the PR lifecycle (push, CI poll, fix cycle on failure).
- Quoted descriptions (`/do "Now fix the tooltip bug"`) are taken verbatim and bypass the `stop`/`next`/`now` subcommand detection.
- `auto` runs unattended but does not merge; use `automerge` for unattended + auto-merge.
- `--force` and `--rounds N` persist into the cron prompt verbatim when used with `every`, so every scheduled fire keeps the same behavior.
