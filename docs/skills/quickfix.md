# /quickfix

> Ship an in-flight edit (or short agent-authored fix) from main as a one-commit PR without a worktree. Lifecycle: triage, review, commit, verify, push, PR, CI poll, fix cycle (dispatched via `/land-pr`).

## Usage

```
/quickfix [<description>] [auto] [from-here] [skip-tests] [--force] [--branch <name>] [--rounds N]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `description` | Conditional | Required when tree is clean (agent-dispatched mode); describes what to fix |
| `auto` | No | Auto-merge the resulting PR via `/land-pr` |
| `from-here` | No | Override the "must run on main/master" check |
| `skip-tests` | No | Skip the test gate (warn-only; for emergency hotfixes) |
| `--force` | No | Bypass triage REDIRECT and review REJECT (safety-gate override; dashed for consistency with `/do`, `/work-on-plans`, `/cleanup-merged`) |
| `--branch <name>` | No | Override the auto-generated branch name |
| `--rounds N` | No | Max review/refine cycles (default 1; `0` skips review) |

## Modes (auto-detected)

| Dirty tree? | Description? | Mode | Behavior |
|-------------|-------------|------|----------|
| Yes | Yes | **user-edited** | Pick up dirty tree edits, commit under description |
| Yes | No | -- | Exit 2 (description required in user-edited mode) |
| No | Yes | **agent-dispatched** | Dispatch an agent to implement, then commit |
| No | No | -- | Exit 2 (need edits or description) |

## Examples

```
/quickfix Fix README typo
/quickfix Fix README typo auto
/quickfix Fix the broken link in docs/intro.md
/quickfix Update CHANGELOG with v0.5 release notes --force
/quickfix Add comment to canary-marker.txt --branch fix/canary-comment
/quickfix Fix parser edge case skip-tests
/quickfix Refactor the test helper --rounds 2
```

## Common Patterns

- **Ship an in-flight edit:** make your edit on main, then `/quickfix Fix README typo auto` -- creates a branch, commits, pushes, opens a PR, and auto-merges
- **Agent-authored fix:** on a clean main, `/quickfix Fix the broken link in docs/intro.md` -- dispatches an agent to implement, then runs the full PR lifecycle
- **Emergency hotfix:** `/quickfix Fix critical auth bug skip-tests --force auto` -- bypass all gates and ship fast
- **Custom branch name:** `/quickfix Update changelog --branch release/v1.0-changelog` -- override the auto-generated branch name

## Tips & Gotchas

- `/quickfix` is PR-shaped end-to-end -- when `execution.landing` is `worktree` or `direct`, it soft-redirects to `/do worktree` or `/commit` respectively
- The skill runs on main and creates a feature branch via `git checkout -b` -- dirty edits carry across
- Triage gate may redirect to `/draft-plan`, `/fix-issues`, or `/run-plan` if the task scope is too large -- use `--force` to bypass
- A fresh-agent plan review runs by default -- `--rounds 0` skips it
- Verification (`/verify-changes`) runs before push unless `--force` or `skip-tests` is set
- No `.landed` marker is written -- `/quickfix` does not use worktrees
- Branch naming: `<branch_prefix><slug>` where prefix defaults to `quickfix/` (configurable via `execution.branch_prefix`)
- The `auto` token enables auto-merge AND skips the WI 1.5.5 dirty-tree confirmation prompt
- On test failure: edits stay in the working tree, but the branch is deleted and you return to the base branch
