# /quickfix — Exit codes and Key Rules

> Reference for the `/quickfix` lifecycle. Loaded on demand; see `SKILL.md`
> for the router and `modes/execute.md` + `modes/land.md` for the phases.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success (PR created), user-cancelled confirmation, or soft-redirect on non-PR landing modes (`worktree` → `/do worktree`, `direct` → `/commit`) |
| 1 | Config / environment error (gh, not-on-main, fetch failed, unit_cmd unset, full_cmd mismatch, parallel in progress, ls-remote network) |
| 2 | Input error (no edits + no description; user-edited no description; branch exists local/remote; slug empty or contains slash) |
| 4 | Test failure (`unit_cmd` non-zero) |
| 5 | Commit / push / PR-create / agent failure |
| 6 | Cleanup failure — manual intervention needed (a rollback step returned non-zero; repo in intermediate state) |

## Key Rules

- **PR-lifecycle (soft-redirect on non-PR landing).** `/quickfix` runs the PR lifecycle (push → PR creation → CI poll, all via `/land-pr`). When `execution.landing == "worktree"` it prints a two-line redirect to `/do worktree` and exits 0; when `== "direct"` it redirects to `/commit` and exits 0. `pr` (or unset) falls through. Hard-error replaced with redirect per issue #293 / PR #290 review.
- **Aligned test-cmd.** `unit_cmd` set and (if `full_cmd` set) `unit_cmd == full_cmd`; otherwise the project pre-commit hook will block our commit.
- **Dirty tree is input.** Show diff, optionally confirm, carry across via `git checkout -b`. Never stash.
- **Never bypass the pre-commit hook.** Hooks exist for safety; fix the root cause.
- **No error suppression on fallible operations.** Distinguish network failure from branch-exists; check each cleanup step.
- **Bare-branch push only.** `git push -u origin "$BRANCH"` — never a refspec pointed at a protected ref.
- **No `.landed` marker.** `/quickfix` has no worktree; PR state is authoritative via `gh pr view`.
- **Full lifecycle.** triage → review → commit → push → PR → CI poll → fix cycle. PR creation, CI monitoring, and the fix cycle are dispatched via `/land-pr`; on `CI_STATUS=fail`, a fix-cycle agent runs at orchestrator level (up to `CI_MAX_ATTEMPTS`, default 2). Auto-merge stays OFF. The success path returns the user to `$BASE_BRANCH`.
