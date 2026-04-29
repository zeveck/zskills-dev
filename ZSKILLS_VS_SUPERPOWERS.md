# Z Skills vs. Superpowers

**Date:** 2026-04-29  
**Scope:** Compare [`zeveck/zskills`](https://github.com/zeveck/zskills) with Claude's
[`obra/superpowers`](https://github.com/obra/superpowers) skill system.  
**Method:** Local repository inspection, public repository metadata, and two independent
review passes over the assessment.

## Executive Summary

| Verdict | Assessment |
|---|---|
| Best default for most agent-assisted coding | **Superpowers** |
| Best for autonomous repo operations | **Z Skills** |
| Best mental model | **Superpowers is a portable methodology layer. Z Skills is an opinionated repo-operations harness.** |
| Best combined use | Pick one orchestrator, then borrow selected skills or practices from the other. Do not install both wholesale without reconciling workflow conflicts. |

Superpowers is the better default when the goal is broadly applicable engineering
discipline with low setup: brainstorming, TDD, systematic debugging, planning,
worktrees, subagent review, and skill authoring.

Z Skills is stronger when the goal is to turn a repository into a controlled
agent execution environment: plan pipelines, tracking markers, hooks, scheduled
runs, issue-fixing sprints, landing modes, CI/PR handling, and explicit
verification gates.

## Evidence Snapshot

| Dimension | Z Skills | Superpowers |
|---|---:|---:|
| Repository inspected | [`zeveck/zskills`](https://github.com/zeveck/zskills) | [`obra/superpowers`](https://github.com/obra/superpowers) |
| Current distribution style | Manual repo install plus `/update-zskills` | Plugin distribution for Claude Code, Codex, Cursor, OpenCode, Gemini CLI, and Copilot-style environments |
| Core skill count inspected | 18 core skills plus 3 block-diagram add-ons | 14 core skills |
| Approximate `SKILL.md` line count inspected | 12,182 | 3,159 |
| Repo-local infrastructure | Hooks, helper scripts, config schema, CI workflow, tests, plans, reports, tracking conventions | Commands, hooks, agents, scripts, tests, and plugin packaging across supported agent environments |
| Public adoption signal | Small public footprint at inspection time | Very large public footprint and ecosystem adoption |
| Primary operating model | Plan-driven autonomous execution inside a prepared repo | Portable skill-triggered engineering discipline |

Line count is weak evidence by itself. In this case it is useful mainly because
it reflects the difference in shape: Z Skills encodes longer procedural
workflows and repo-specific machinery, while Superpowers keeps the active core
smaller and more portable.

## Capability Comparison

| Capability | Z Skills | Superpowers | Practical Difference |
|---|---|---|---|
| Planning | `/draft-plan`, `/research-and-plan`, `/research-and-go`, `/run-plan` | `brainstorming`, `writing-plans`, `executing-plans` | Z Skills can generate and execute plan phases through repo-local pipelines. Superpowers focuses on disciplined planning and controlled execution. |
| Worktree isolation | First-class in `/run-plan`, `/fix-issues`, `/do`, and landing modes | `using-git-worktrees` skill | Both value isolation. Z Skills automates more of the branch/worktree lifecycle. |
| Subagents | Implementation, review, issue-fixing, verification, adversarial planning | Subagent-driven development, code review, parallel agents | Both use subagents. Z Skills embeds them in larger workflows; Superpowers teaches when and how to dispatch them. |
| Verification | `/verify-changes`, final-verify markers, test capture, manual UI checks, hook fallbacks | `verification-before-completion`, code review, systematic test discipline | Z Skills has stronger mechanical guardrails. Superpowers has clearer general-purpose verification principles. |
| Debugging | `/investigate` | `systematic-debugging` | Superpowers is stronger as a reusable debugging methodology. Z Skills is more integrated into its project workflow. |
| Testing philosophy | Verification-heavy, project-specific test commands via config | Strong TDD skill with strict "test first" discipline | Superpowers is more explicit and reusable on TDD. |
| Git safety | `/commit`, landing modes, branch protection assumptions, hooks, tracking markers | Worktree and finishing-branch skills | Z Skills is more protective in a configured repo. Superpowers is easier to apply manually. |
| Long-running autonomy | `/run-plan finish auto`, scheduling, tracking, issue sprints | Batch execution and subagent-driven development | Z Skills clearly wins for sustained autonomous repo operations. |
| Skill creation and maintenance | `/update-zskills`, repo-local install/update conventions | `writing-skills`, `using-superpowers`, plugin packaging | Superpowers has stronger general guidance for writing durable skills. Z Skills has stronger repo-specific update plumbing. |

## Overlap

| Shared Concern | Z Skills Expression | Superpowers Expression |
|---|---|---|
| Avoid rushing into code | Plan and research pipelines | Brainstorming and writing-plans workflow |
| Preserve context quality | Fresh agents, chunked plan execution, reports | Fresh subagents, code review, explicit skill loading |
| Avoid unsafe git operations | Hooks, `/commit`, tracking markers, landing modes | Worktree and branch finishing workflows |
| Catch failures before completion | `/verify-changes`, manual testing, final verification markers | Verification-before-completion and code review |
| Encode reusable agent behavior | `.claude/skills` and portable skill files | Superpowers skills plus plugin runtime |

The important distinction is degree, not kind. Superpowers also orchestrates
work, and Z Skills also teaches process. Z Skills couples more of that process
to repository state, scripts, hooks, and branch workflows.

## Unique Strengths

### Z Skills

| Strength | Why It Matters |
|---|---|
| Autonomous plan execution | `/run-plan` can advance a plan phase by phase with verification and landing behavior. |
| Tracking markers | `.zskills/tracking` creates a persistent coordination layer that hooks and workflows can inspect. |
| Landing modes | Cherry-pick, PR, and direct modes support different repo governance models. |
| Batch issue fixing | `/fix-issues` is designed for sprint-style bug fixing across many issues. |
| Scheduled work | Recurring or one-shot scheduling allows long-running pipelines to preserve fresh context between phases. |
| Hook-backed safety | Git, branch, agent, and verification guardrails can block unsafe operations in prepared environments. |
| Operational reports | Plans, reports, and canaries make the system auditable after long runs. |

### Superpowers

| Strength | Why It Matters |
|---|---|
| Low-friction adoption | The plugin path makes it much easier to start using across projects. |
| Portable methodology | Skills are broadly useful without requiring a repo-local operating model. |
| Strong TDD discipline | The TDD skill is explicit about writing and observing a failing test before implementation. |
| Systematic debugging | The debugging workflow is clear, general, and useful outside any specific repo. |
| Skill discovery | `using-superpowers` makes skill lookup a mandatory part of the workflow. |
| Skill authoring guidance | `writing-skills` is a mature guide for creating durable, searchable skills. |
| Community surface | Larger public adoption makes it more likely that rough edges are found and fixed. |

## Quality, Usability, Usefulness, and Power

| Dimension | Z Skills | Superpowers | Winner |
|---|---|---|---|
| Quality of operational coverage | Very high. It encodes many real failure cases into explicit workflows, tests, hooks, and reports. | Medium-high. It has strong core practices and tests, but less repo-operation machinery. | Z Skills |
| Quality of general methodology | Medium-high. Good practices are present, but often embedded in long operational instructions. | High. TDD, debugging, review, planning, and skill-writing are direct and reusable. | Superpowers |
| Usability for a new user | Medium-low. Setup and mental model are heavier. | High. Plugin distribution and smaller skill surfaces are easier to start with. | Superpowers |
| Usefulness for normal feature work | High if the repo is configured. Medium if not. | High across most repos. | Superpowers |
| Usefulness for sustained autonomous work | Very high. This is the main design center. | Medium. It supports disciplined batches, but not the same repo-local automation. | Z Skills |
| Mechanical protection | High in supported environments. Hooks, markers, config, and landing modes matter. | Medium. Much of the discipline is prompt/process-level unless supported by runtime hooks. | Z Skills |
| Portability | Medium-low. It assumes more about GitHub, worktrees, hooks, cron-like scheduling, and project structure. | High. It is designed to travel across projects and agent environments. | Superpowers |
| Power ceiling | Very high. It can drive complex repo operations. | High. It improves agent behavior broadly but is less of an autonomous harness. | Z Skills |
| Failure surface | Higher. More machinery means more assumptions and more ways to misconfigure. | Lower. Smaller workflows are easier to reason about. | Superpowers |

## Risks and Tradeoffs

| Risk | Z Skills | Superpowers |
|---|---|---|
| Setup burden | Higher: skills, hooks, config, helper scripts, landing choices, project conventions. | Lower: plugin install and skill activation. |
| Context weight | Higher: many skills are long and procedural. | Lower: core skills are shorter and narrower. |
| Workflow rigidity | High in configured pipelines. | Medium-high because some skills mandate discovery, brainstorming, and TDD. |
| Misconfiguration impact | Higher because hooks, tracking, branch modes, and scheduling can interact. | Lower because more of the system is advisory/process-level. |
| Installing both | Risky unless one system is clearly primary. Duplicate planning, verification, worktree, and completion instructions can conflict. | Same risk from the other side. |

## Recommended Use

| Situation | Prefer | Reason |
|---|---|---|
| You want better everyday coding discipline | Superpowers | It improves planning, TDD, debugging, review, and completion with minimal repo ceremony. |
| You want an agent to work through multi-phase plans over time | Z Skills | Its plan execution, tracking, scheduling, and landing workflows are built for this. |
| You are onboarding a broad team or many repos | Superpowers | It is easier to distribute and explain. |
| You are operating one important repo with repeatable agent workflows | Z Skills | The setup cost can pay off through guardrails and automation. |
| You need strict TDD behavior | Superpowers | The TDD skill is sharper and more general-purpose. |
| You need batch issue-fixing or autonomous PR flow | Z Skills | Those are first-class workflows. |
| You want to create new reusable skills | Superpowers | Its skill-writing guidance is stronger and less project-specific. |
| You want repo-specific safety hooks and tracking | Z Skills | That is its core advantage. |

## Combined Strategy

Do not run both wholesale as equal authorities. That creates duplicated
instructions around planning, worktrees, verification, branch completion,
subagents, and testing.

The safer combined approach is:

| Step | Recommendation |
|---|---|
| 1 | Pick one primary orchestrator. |
| 2 | If Superpowers is primary, borrow Z Skills ideas for repo-specific hooks, tracking, or issue-sprint automation only where needed. |
| 3 | If Z Skills is primary, borrow Superpowers' TDD, systematic debugging, and skill-authoring standards as quality bars inside Z Skills workflows. |
| 4 | Document any precedence rules in the repo agent instructions so the model does not try to follow conflicting workflows. |

## Reviewer Corrections Applied

Two independent review agents checked the assessment. Their main corrections
are reflected above:

| Correction | Impact on This Document |
|---|---|
| Do not call Superpowers an "official framework." | This document describes it as a plugin-distributed methodology layer instead. |
| Do not overstate Superpowers enforcement. | Enforcement is described as mostly process-level unless supported by runtime hooks. |
| Do not make the distinction too binary. | Both systems teach and orchestrate; the difference is degree and repo coupling. |
| Treat line counts as weak evidence. | Counts are shown only as context for system shape. |
| Warn against combining both wholesale. | The combined strategy section requires choosing one primary orchestrator. |
| Emphasize Z Skills environment assumptions. | Risks and recommendations call out setup, GitHub, worktree, hook, scheduling, and tracking assumptions. |
| Emphasize Superpowers' own friction. | Risks call out mandatory discovery, brainstorming, and TDD discipline. |

## Final Take

Superpowers is a portable methodology layer. Z Skills is an opinionated
repo-operations harness.

Use Superpowers as the default process library. Use Z Skills when the repo
itself should become an automated execution environment. Combine them only by
choosing one orchestrator and borrowing selected practices from the other.
