# /do

> Lightweight task dispatcher for ad-hoc work: documentation, examples, refactoring, content updates. Worktree/direct/pr landing modes via flag or config. Recurring via `every SCHEDULE`; `stop`/`next` manage the schedule.

## Usage

```
/do <description> [worktree|direct|pr] [auto] [every SCHEDULE] [now] [--force] [--rounds N]
/do stop [query]
/do next [query]
/do now [query]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `description` | Yes | What to do, in natural language |
| `worktree` | No | Isolate work in a worktree, cherry-pick back to main |
| `direct` | No | Work on main in place, no landing step |
| `pr` | No | Named worktree + feature branch, push, create PR |
| `auto` | No | Land autonomously (PR: auto-merge; worktree: cherry-pick+push; direct: push) |
| `every SCHEDULE` | No | Self-schedule recurring runs (`4h`, `day at 9am`, `weekday at 9am`) |
| `now` | No | Run immediately (with `every`: run now AND schedule) |
| `--force` | No | Bypass triage redirect and review reject |
| `--rounds N` | No | Max review/refine cycles (default 1; `0` skips review) |

## Subcommands

### `stop [query]`

Cancel `/do` cron(s). Bare `/do stop` cancels all. With a query (`/do stop Check docs`), targets the matching cron via fuzzy description matching.

### `next [query]`

Check next fire time(s). Bare `/do next` shows all. With a query, shows the matching cron's schedule.

### `now [query]`

Trigger a cron immediately. Bare `/do now` triggers the single cron (or asks if multiple). With a query, triggers the matching cron.

## Examples

```
/do Add example models for Integrator and Derivative blocks
/do Sort the screenshots in session-sequence-snapshots
/do Refactor color constants in main.css worktree
/do Update the presentation with Phase 3 results auto
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

- **Quick content task:** `/do Sort the screenshots` -- direct mode, no ceremony
- **Isolated refactor:** `/do Refactor color constants worktree` -- work in a worktree, verify, no auto-land
- **PR with auto-merge:** `/do Add dark mode pr auto` -- create a PR and request auto-merge
- **Recurring maintenance:** `/do Check for broken links every 12h now` -- schedule and run immediately
- **Bypass gates:** `/do Fix the tooltip bug --force` -- skip triage and review for a known-simple fix

## Tips & Gotchas

- `/do` runs a triage gate (Phase 0a) that may redirect to `/draft-plan`, `/run-plan`, or `/fix-issues` if the task is too large or references issues/plans -- use `--force` to bypass
- A fresh-agent review (Phase 0b) checks the inline plan before execution -- `--rounds 0` skips this
- When no landing flag is given, the mode comes from `execution.landing` in config (`cherry-pick` maps to `worktree`, `pr` maps to `pr`, `direct` maps to `direct`)
- `direct` mode is incompatible with `execution.main_protected: true`
- Verification (`/verify-changes`) runs on all code changes regardless of the `auto` flag -- `auto` controls landing, not whether to verify
- PR mode dispatches `/land-pr` for the full PR lifecycle (push, CI poll, fix cycle)
- Quoted descriptions (`/do "Now fix the tooltip bug"`) bypass meta-command detection
- `--force` and `--rounds N` persist into cron prompts verbatim when used with `every`
