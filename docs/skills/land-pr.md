# `/land-pr` (internal helper)

> **Not for direct user invocation.** `/land-pr` carries `user-invocable: false`
> in its skill frontmatter. It's the shared PR-landing engine that other skills
> dispatch internally — it's not designed to be typed at the slash prompt.
>
> **If you want to ship a feature branch, use [`/commit pr`](commit.md) instead.**
> `/commit pr` constructs the title/body/result-file the helper needs, then
> dispatches `/land-pr` under the hood with the right arguments.

## What it does

`/land-pr` owns the entire **rebase → push → create-or-detect → monitor CI → merge** sequence for a feature branch that's already in a presentable state:

1. **Rebase** the branch onto the configured base (`main` by default) — idempotent; a no-op if already up-to-date.
2. **Push** the branch and **create or detect** the PR. If a PR already exists for the branch, the helper picks up the existing PR rather than failing.
3. **Monitor CI** by polling until checks complete or a configurable timeout fires (default 600s).
4. **Auto-rebase on BEHIND** — if `origin/main` advances during CI, transparently rebase + force-push-with-lease + re-monitor, up to 3 iterations.
5. **Request merge** (only with `--auto`) via `gh pr merge --auto`. Then drive the queued auto-merge to a terminal state, handling post-request BEHIND if it occurs.
6. **Update tracking** — fast-forward local `main`, copy worktree tracking markers to main, write the canonical `.landed` schema (`landed` / `pr-ready` / `pr-ci-failing` / `conflict` / etc.), and write the parent skill's `fulfilled.land-pr.<id>` marker on success.

The helper hands results back to its caller via a result file (`--result-file`), parsed by an allow-list line-by-line parser. Status codes cover every terminal: `merged`, `created`, `monitored`, `push-failed`, `rebase-conflict`, `create-failed`, `monitor-failed`, `merge-failed`, `rebase-failed`, `behind-thrash`, `auto-rebase-conflict`, `auto-rebase-blocked`.

## Eight caller skills

Five **implementation** callers dispatch `/land-pr` for code changes:

- [`/run-plan`](run-plan.md) — multi-phase plan execution (PR mode)
- [`/commit pr`](commit.md) — the canonical user-facing way to ship a branch
- [`/do pr`](do.md) — single-task lightweight dispatcher (PR mode)
- [`/fix-issues pr`](fix-issues.md) — batch issue resolution
- [`/quickfix`](quickfix.md) — minimal-ceremony one-commit PRs

Three **drafting** callers dispatch `/land-pr` for plan/test specs:

- [`/draft-plan`](draft-plan.md) — initial plan with adversarial review
- [`/refine-plan`](refine-plan.md) — refinement of an in-progress plan
- [`/draft-tests`](draft-tests.md) — test specifications into a plan

## What happens if a user types `/land-pr`?

The slash runtime will not dispatch `user-invocable: false` skills in any useful way. In practice:

- If `/land-pr` somehow gets dispatched anyway, the helper's strict argument validation requires `--branch`, `--title`, `--body-file`, and `--result-file` (with `--body-file` non-empty and `--result-file`'s parent directory existing). A human typing the slash command at the prompt has none of those — the helper exits with `ERROR: /land-pr requires --branch` (or whichever is missing first).
- The agent context is expected to recommend `/commit pr` instead when the user reaches for `/land-pr` directly. See [issue #976](https://github.com/zeveck/zskills/issues/976) for the cross-cutting hook that enforces this in agent-facing reports.

## Configuration

`/land-pr` reads `execution.branch_prefix` and `execution.landing` from `.claude/zskills-config.json` indirectly via its caller skills. The helper itself takes no `landing` arg — the caller already resolved that before dispatching.

## See also

- [`/commit`](commit.md) — the user-facing skill that wraps `/land-pr` correctly
- [Workflows](../guides/WORKFLOWS.md) — when each landing skill is the right pick
