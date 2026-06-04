# Z Skills Reference

Per-skill reference for the **21 user-facing Z Skills**, plus the **2 internal
helpers** they dispatch (`/land-pr` and `/manual-testing` — not for direct use).
Grouped and ordered the same as the docs-viewer nav sidebar. Looking for how to
*combine* these skills into end-to-end workflows? See
[Workflows](../guides/workflows.md).

The **Arguments** column is the real `argument-hint` from each skill's
frontmatter (alternatives shown with `│`; `—` = no arguments).

## Execution

Make one change, end to end.

| Skill | Arguments | What it does |
|-------|-----------|--------------|
| [`/do`](do.md) | `<description> [worktree] [pr] [auto] [every SCHEDULE] [now] [--rounds N] │ stop │ next │ now` | The everyday workhorse for ad-hoc work |
| [`/run-plan`](run-plan.md) | `<plan-file> [phase│finish│status] [auto] [pr│direct] [every SCHEDULE] [now] │ stop │ next` | Execute plan phases with verify + land |
| [`/investigate`](investigate.md) | `<description or #issue>` | Deep root-cause debugging |

## Planning & Design

Create, refine, and decompose plans before execution.

| Skill | Arguments | What it does |
|-------|-----------|--------------|
| [`/draft-plan`](draft-plan.md) | `[output FILE] [rounds N] [auto] [brainstorm│quiz] <description...>` | Adversarial plan drafting |
| [`/refine-plan`](refine-plan.md) | `<plan-file> [rounds N] [auto] [guidance...]` | Refine in-progress plans against reality |
| [`/draft-tests`](draft-tests.md) | `<plan-file> [rounds N] [auto] [guidance...]` | Draft test specs into a plan's phases |
| [`/research-and-plan`](research-and-plan.md) | `[output FILE] <broad goal description>` | Decompose broad goals into sub-plans |
| [`/plans`](plans.md) | `[rebuild │ next │ details]` | Plan dashboard / index |

## Quality Assurance

Test, audit, and verify changes.

| Skill | Arguments | What it does |
|-------|-----------|--------------|
| [`/verify-changes`](verify-changes.md) | `[scope: worktree │ branch │ last [N]]` | Verify recent changes end to end |
| [`/qe-audit`](qe-audit.md) | `[bash [area]] [every SCHEDULE] [now] │ stop │ next` | Quality audit for test-coverage gaps |

## Automation

Batch, queue, and scheduled drivers that run unattended.

| Skill | Arguments | What it does |
|-------|-----------|--------------|
| [`/fix-issues`](fix-issues.md) | `N [focus│dashboard] [auto] [every SCHEDULE] [now] [pr│direct] │ sync │ plan │ stop │ next` | Batch bug-fixing sprints |
| [`/work-on-plans`](work-on-plans.md) | `N│all [phase│finish] [every SCHEDULE] [now] [continue] │ stop │ next` | Batch-run the ready plan queue |
| [`/zskills-dashboard`](zskills-dashboard.md) | `[start│stop│status│restart]` | Local web dashboard |
| [`/research-and-go`](research-and-go.md) | `<broad goal description>` | Full autonomous decompose → plan → execute |

## Reporting

Generate reports and review project state.

| Skill | Arguments | What it does |
|-------|-----------|--------------|
| [`/session-report`](session-report.md) | `[handoff]` | Audit session intent vs. shipped |
| [`/briefing`](briefing.md) | `[report [period]] │ verify │ current │ worktrees │ [summary] │ stop │ next` | Project briefing: status, commits, worktrees |
| [`/fix-report`](fix-report.md) | — | Review sprint results, land fixes, close issues |

## Utilities

Supporting tools — committing, cleanup, docs, and framework setup.

| Skill | Arguments | What it does |
|-------|-----------|--------------|
| [`/commit`](commit.md) | `[pr] [scope] [push│land] [auto]` | Safe commit with optional push / land / PR |
| [`/cleanup-merged`](cleanup-merged.md) | `[apply] [local │ remote │ all] [<branch>...]` | Post-PR-merge local normalization |
| [`/update-zskills`](update-zskills.md) | `[install] [cherry-pick│locked-main-pr│direct]` | Install / update zskills infrastructure |
| [`/create-worktree`](create-worktree.md) | `<slug> [--prefix P] [--branch-name REF] [--from B] [--purpose TEXT] [--pipeline-id ID] …` | Create an isolated worktree (mostly dispatched internally) |

## Internal helpers

Dispatched by other skills — not designed for direct user invocation (both carry
`user-invocable: false`). In the docs viewer they appear under their own
**Internal** nav section.

| Skill | Arguments | What it does |
|-------|-----------|--------------|
| [`/land-pr`](land-pr.md) | `--branch <name> --title <t> --body-file <p> --result-file <p> [--auto] [--worktree-path <p>] …` | PR landing helper (rebase, push, create-or-detect, monitor CI, optional auto-merge) |
| [`/manual-testing`](manual-testing.md) | — | Browser-based UI-verification recipes (uses the `playwright-cli` tool) |
