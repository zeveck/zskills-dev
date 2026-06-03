# Z Skills Reference

Per-skill reference for the **23 user-facing Z Skills**, plus the **2 internal
helpers** they dispatch (`/land-pr` and `/manual-testing` — not for direct use;
in the docs viewer they appear under their own **Internal Skills** section).
Looking for how to *combine* these skills into end-to-end workflows? See
[Workflows](../guides/workflows.md).

<details>
<summary><strong>Quick reference table</strong> — alphabetical jump list (click to expand)</summary>

| Skill | Description |
|-------|-------------|
| [`/briefing`](briefing.md) | Generate a project briefing with status, commits, worktrees |
| [`/cleanup-merged`](cleanup-merged.md) | Post-PR-merge local normalization |
| [`/commit`](commit.md) | Safe commit workflow with optional push, land, or PR |
| [`/create-worktree`](create-worktree.md) | Create an isolated git worktree for agent work |
| [`/do`](do.md) | Lightweight task dispatcher for ad-hoc work |
| [`/doc`](doc.md) | Audit and fix documentation gaps |
| [`/draft-plan`](draft-plan.md) | Draft plans through iterative adversarial review |
| [`/draft-tests`](draft-tests.md) | Draft test specifications into existing plans |
| [`/fix-issues`](fix-issues.md) | Orchestrate batch bug-fixing sprints |
| [`/fix-report`](fix-report.md) | Review sprint results, land fixes, close issues |
| [`/investigate`](investigate.md) | Deep debugging for complex bugs |
| [`/plans`](plans.md) | Plan dashboard: view status, find next ready plan |
| [`/qe-audit`](qe-audit.md) | Quality engineering audit for test coverage gaps |
| [`/quickfix`](quickfix.md) | Ship an in-flight edit as a one-commit PR |
| [`/refine-plan`](refine-plan.md) | Refine in-progress plans against completed work |
| [`/research-and-go`](research-and-go.md) | Full pipeline: decompose, plan, and execute autonomously |
| [`/research-and-plan`](research-and-plan.md) | Decompose broad goals into executable sub-plans |
| [`/run-plan`](run-plan.md) | Execute plan phases with verification and landing |
| [`/session-report`](session-report.md) | Audit session intent vs. actual shipped state |
| [`/update-zskills`](update-zskills.md) | Install or update Z Skills infrastructure |
| [`/verify-changes`](verify-changes.md) | Verify recent changes: diffs, tests, manual checks |
| [`/work-on-plans`](work-on-plans.md) | Batch-execute prioritized plan queue from dashboard |
| [`/zskills-dashboard`](zskills-dashboard.md) | Local web dashboard for plans, issues, and tracking |

#### Internal helpers

Dispatched by other skills — not designed for direct user invocation (both carry
`user-invocable: false`). In the docs viewer they appear under their own
**Internal Skills** section. Listed here for reference only.

| Skill | Description |
|-------|-------------|
| [`/land-pr`](land-pr.md) | PR landing helper (rebase, push, create-or-detect, monitor CI, optional auto-merge) |
| [`/manual-testing`](manual-testing.md) | Browser-based manual testing recipes (uses the `playwright-cli` tool) |

</details>

## Categories

### Execution & Orchestration

Core skills for running plans and fixing issues at scale.

- [/run-plan](run-plan.md) -- Execute plan phases with implementation, verification, and landing
- [/fix-issues](fix-issues.md) -- Batch bug-fixing sprints with per-issue worktrees
- [/work-on-plans](work-on-plans.md) -- Batch-execute the prioritized ready queue from the dashboard
- [/do](do.md) -- Lightweight task dispatcher for ad-hoc work
- [/quickfix](quickfix.md) -- Ship an in-flight edit as a one-commit PR from main
- [/research-and-go](research-and-go.md) -- Full autonomous pipeline: decompose, plan, execute

### Planning & Design

Skills for creating, refining, and decomposing plans before execution.

- [/draft-plan](draft-plan.md) -- Draft plans through iterative adversarial review
- [/draft-tests](draft-tests.md) -- Draft test specifications into existing plan phases
- [/refine-plan](refine-plan.md) -- Refine in-progress plans against completed work
- [/research-and-plan](research-and-plan.md) -- Decompose broad goals into executable sub-plans
- [/plans](plans.md) -- Plan dashboard: view status, find the next ready plan

### Verification & Quality

Skills for testing, auditing, and verifying changes.

- [/verify-changes](verify-changes.md) -- Full verification: diffs, test coverage, test runs, manual checks
- [/qe-audit](qe-audit.md) -- Quality engineering audit for test coverage gaps and bugs
- [/investigate](investigate.md) -- Deep root-cause debugging for complex bugs
- [/manual-testing](manual-testing.md) -- Browser-based manual testing recipes (uses the `playwright-cli` tool) *(internal helper)*

### Git & Landing

Skills for committing, landing, and cleaning up branches.

- [/commit](commit.md) -- Safe commit workflow with push, land, or PR modes
- [/cleanup-merged](cleanup-merged.md) -- Post-PR-merge local normalization and branch cleanup
- [/create-worktree](create-worktree.md) -- Create isolated git worktrees for agent work

### Content & Documentation

Skills for managing documentation across the project.

- [/doc](doc.md) -- Audit and fix documentation gaps across the project

### Reporting & Status

Skills for generating reports and reviewing project state.

- [/briefing](briefing.md) -- Generate a project briefing with worktrees, commits, checkboxes
- [/session-report](session-report.md) -- Audit what this session shipped vs. what was planned
- [/fix-report](fix-report.md) -- Review sprint results, land fixes, close issues

### Infrastructure & Configuration

Skills for managing the Z Skills framework itself.

- [/update-zskills](update-zskills.md) -- Install or update Z Skills infrastructure
- [/zskills-dashboard](zskills-dashboard.md) -- Local web dashboard for plans, issues, and tracking
