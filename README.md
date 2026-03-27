# Z Skills

**20 skills that plan, build, test, fix, and ship** — so one developer
can run a full engineering team.

Z Skills encode hard-won lessons from real agent failures into reusable
prompt files. Each skill is a `.claude/skills/SKILL.md` file that teaches
Claude Code how to perform a specific workflow with the discipline that
prevents the most common AI agent failure modes: skipping verification,
weakening tests, deferring hard parts, and shipping broken code.

**[View the full presentation](PRESENTATION.html)** for the architecture,
workflow stages, enforcement model, and war stories.

## The Skills

![Plan and Build skills](screenshots/skills-plan-build.png)

![Quality and Fix skills](screenshots/skills-quality-fix.png)

![Utility, Reference, and Domain Extension skills](screenshots/skills-utility-domain.png)

## Quick Install

```bash
# Clone into your project
git clone https://github.com/zeveck/zskills.git zskills

# Tell Claude Code to set up
/setup-zskills install
```

`/setup-zskills` copies skills to `.claude/skills/`, installs safety hooks,
configures helper scripts, and creates CLAUDE.md guardrail rules. It prompts
for project-specific values (test commands, dev server, source paths).

To update later: `/setup-zskills update` (pulls latest and syncs).

## Skill Catalog

### 15 Core Skills (`skills/`)

These work on any software project — web app, CLI tool, API service, game,
data pipeline.

#### Plan

| Skill | Purpose |
|-------|---------|
| `/draft-plan` | Adversarial plan drafting: research, draft, devil's advocate review, refine until converged |
| `/research-and-plan` | Decompose broad goals into focused sub-plans with dependency ordering |
| `/research-and-go` | Full autonomous pipeline: decompose, plan, execute — one command, walk away |
| `/plans` | Plan dashboard: index, status tracking, priority ranking, batch execution |

#### Build

| Skill | Purpose |
|-------|---------|
| `/run-plan` | Phase-by-phase plan execution with worktree isolation, verification gates, and auto-landing |
| `/do` | Lightweight task dispatcher for ad-hoc work with optional worktree/push/scheduling |

#### Verify

| Skill | Purpose |
|-------|---------|
| `/verify-changes` | 7-phase verification: diff review, test coverage audit, test run, manual UI check, fix, re-verify |
| `/qe-audit` | Quality audit of recent commits — find test gaps, edge cases, file issues |
| `/investigate` | Root-cause debugging: reproduce, trace, prove the cause with evidence, regression test, fix |

#### Fix

| Skill | Purpose |
|-------|---------|
| `/fix-issues` | Batch bug-fixing sprints: prioritize N issues, dispatch parallel agents, verify, land |
| `/fix-report` | Interactive sprint review — walk through results, gate landing on user approval |

#### Ship

| Skill | Purpose |
|-------|---------|
| `/commit` | Safe commit: scope classification, import tracing, fresh review agent, dependency verification |
| `/briefing` | Project status dashboard: recent commits, worktree status, pending sign-offs |

#### Support

| Skill | Purpose |
|-------|---------|
| `/doc` | Documentation audit, gap-filling, and changelog/newsletter entries |
| `/setup-zskills` | Install, audit, or update Z Skills infrastructure in any project |

### 5 Domain Skills (`block-diagram/`)

These are for block-diagram editors and visual modeling projects. Use them
directly or as templates for your own domain-specific skills.
See [`block-diagram/README.md`](block-diagram/README.md).

| Skill | Purpose |
|-------|---------|
| `/add-block` | Full lifecycle for new block types: plan, implement, register, test, example, codegen |
| `/add-example` | Example model creation: research, design, build, register, test, screenshot |
| `/manual-testing` | Playwright recipes with exact selectors for block-diagram UI testing |
| `/model-design` | Layout guidelines for block diagrams and state charts (MAAB/NASA standards) |
| `/review-feedback` | Triage in-app user feedback, deduplicate, file GitHub issues |

## What Gets Installed

### 13 CLAUDE.md Rules

Agent guardrails that prevent the most common failure modes:

1. **Never weaken tests** — fix the code, not the test
2. **Capture test output to file** — never pipe through grep/tail
3. **Max 2 fix attempts** — stop and report, don't thrash
4. **Pre-existing failure protocol** — verify with git log, skip + file issue
5. **Never discard others' changes** — ask before touching uncommitted work
6. **Protect untracked files** — `git stash -u`, not `git stash`
7. **Feature-complete commits** — trace imports, verify before staging
8. **Always write `.landed` marker** — so worktrees can be safely cleaned up
9. **Verify worktrees before removing** — never batch-remove
10. **Never defer hard parts** — finish the plan, don't stop after the easy phase
11. **Correctness over speed** — follow instructions exactly, never stub
12. **Enumerate before guessing** — ls/grep first, build from scratch second
13. **Never skip pre-commit hooks** — fix the issue, don't bypass with --no-verify

### Safety Hooks

`block-unsafe-generic.sh` blocks destructive operations for all agents:
- `git stash drop/clear`, `git checkout --`, `git restore`, `git clean -f`
- `git reset --hard`, `kill -9`/`killall`/`pkill`, `fuser -k`
- `git push` (all forms — user pushes manually)
- `rm -rf`, `git add .`/`git add -A`, `git commit --no-verify`

`block-unsafe-project.sh.template` adds project-specific enforcement
(configure during install): test-before-commit, UI file verification.

### Session Logging

Hooks that convert Claude Code JSONL transcripts to readable markdown
after every session and subagent run. Logs go to `.claude/logs/`.

### Helper Scripts

- `port.js` — deterministic dev server port per worktree
- `test-all.js` — meta test runner (unit + E2E + build tests)
- `briefing.cjs` — project status data gathering for `/briefing`

## Extending Z Skills

Add your own skills by creating `.claude/skills/<name>/SKILL.md` files.
A skill is just a markdown file with YAML frontmatter:

```yaml
---
name: my-skill
description: What this skill does (used for discovery)
disable-model-invocation: true  # only user can invoke
---

# /my-skill — Title

Instructions for the agent...
```

See any skill in `skills/` for the full pattern.

## Session Logging

The hooks include a session logging system that converts Claude Code
JSONL transcripts to readable markdown after every session. Available
as a standalone package: [cc-session-logger](https://github.com/zeveck/cc-session-logger).

## License

MIT
