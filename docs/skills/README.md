# Z Skills Reference

Comprehensive documentation for all 28 user-invocable skills.

## Quick Reference

| Skill | Description | Docs |
|-------|-------------|------|
| [`/add-block`](add-block.md) | Step-by-step guide for adding new block types | [Details](add-block.md) |
| [`/add-example`](add-example.md) | Create example models for block types | [Details](add-example.md) |
| [`/briefing`](briefing.md) | Generate a project briefing with status, commits, worktrees | [Details](briefing.md) |
| [`/cleanup-merged`](cleanup-merged.md) | Post-PR-merge local normalization | [Details](cleanup-merged.md) |
| [`/commit`](commit.md) | Safe commit workflow with optional push, land, or PR | [Details](commit.md) |
| [`/create-worktree`](create-worktree.md) | Create a git worktree for agent work | [Details](create-worktree.md) |
| [`/do`](do.md) | Lightweight task dispatcher for ad-hoc work | [Details](do.md) |
| [`/doc`](doc.md) | Audit and fix documentation gaps | [Details](doc.md) |
| [`/draft-plan`](draft-plan.md) | Draft plans through iterative adversarial review | [Details](draft-plan.md) |
| [`/draft-tests`](draft-tests.md) | Draft test specifications into existing plans | [Details](draft-tests.md) |
| [`/fix-issues`](fix-issues.md) | Orchestrate batch bug-fixing sprints | [Details](fix-issues.md) |
| [`/fix-report`](fix-report.md) | Review sprint results, land fixes, close issues | [Details](fix-report.md) |
| [`/investigate`](investigate.md) | Deep debugging for complex bugs | [Details](investigate.md) |
| [`/manual-testing`](manual-testing.md) | Browser-based manual testing recipes | [Details](manual-testing.md) |
| [`/plans`](plans.md) | Plan dashboard: view status, find next ready plan | [Details](plans.md) |
| [`/playwright-cli`](playwright-cli.md) | Browser automation with playwright-cli | [Details](playwright-cli.md) |
| [`/qe-audit`](qe-audit.md) | Quality engineering audit for test coverage gaps | [Details](qe-audit.md) |
| [`/quickfix`](quickfix.md) | Ship an in-flight edit as a one-commit PR | [Details](quickfix.md) |
| [`/refine-plan`](refine-plan.md) | Refine in-progress plans against completed work | [Details](refine-plan.md) |
| [`/research-and-go`](research-and-go.md) | Full pipeline: decompose, plan, and execute autonomously | [Details](research-and-go.md) |
| [`/research-and-plan`](research-and-plan.md) | Decompose broad goals into executable sub-plans | [Details](research-and-plan.md) |
| [`/review-feedback`](review-feedback.md) | Review exported feedback JSON and file GitHub issues | [Details](review-feedback.md) |
| [`/run-plan`](run-plan.md) | Execute plan phases with verification and landing | [Details](run-plan.md) |
| [`/session-report`](session-report.md) | Audit session intent vs. actual shipped state | [Details](session-report.md) |
| [`/update-zskills`](update-zskills.md) | Install or update Z Skills infrastructure | [Details](update-zskills.md) |
| [`/verify-changes`](verify-changes.md) | Verify recent changes: diffs, tests, manual checks | [Details](verify-changes.md) |
| [`/work-on-plans`](work-on-plans.md) | Batch-execute prioritized plan queue from dashboard | [Details](work-on-plans.md) |
| [`/zskills-dashboard`](zskills-dashboard.md) | Local web dashboard for plans, issues, and tracking | [Details](zskills-dashboard.md) |

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
- [/manual-testing](manual-testing.md) -- Browser-based manual testing recipes with playwright-cli
- [/playwright-cli](playwright-cli.md) -- Low-level browser automation commands

### Git & Landing

Skills for committing, landing, and cleaning up branches.

- [/commit](commit.md) -- Safe commit workflow with push, land, or PR modes
- [/cleanup-merged](cleanup-merged.md) -- Post-PR-merge local normalization and branch cleanup
- [/create-worktree](create-worktree.md) -- Create isolated git worktrees for agent work

### Content & Documentation

Skills for managing documentation, examples, and block types.

- [/doc](doc.md) -- Audit and fix documentation gaps across the project
- [/add-block](add-block.md) -- Step-by-step guide for adding new block types
- [/add-example](add-example.md) -- Create example models for block types

### Reporting & Status

Skills for generating reports and reviewing project state.

- [/briefing](briefing.md) -- Generate a project briefing with worktrees, commits, checkboxes
- [/session-report](session-report.md) -- Audit what this session shipped vs. what was planned
- [/fix-report](fix-report.md) -- Review sprint results, land fixes, close issues
- [/review-feedback](review-feedback.md) -- Review exported feedback JSON and file issues

### Infrastructure & Configuration

Skills for managing the Z Skills framework itself.

- [/update-zskills](update-zskills.md) -- Install or update Z Skills infrastructure
- [/zskills-dashboard](zskills-dashboard.md) -- Local web dashboard for plans, issues, and tracking
