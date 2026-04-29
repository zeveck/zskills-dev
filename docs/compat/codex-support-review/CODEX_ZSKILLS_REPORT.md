# Codex Z Skills Evaluation Report

## Summary

Z Skills installed successfully as a Codex skill library, with 21 skills under
`~/.codex/skills` and upstream helper assets vendored under
`~/.codex/zskills-portable`.

The result is useful, but it is not a fully native Codex automation stack. The
best-converted skills work as strong engineering playbooks for commits,
verification, debugging, planning, and manual testing. The weakest fit is the
autonomous orchestration layer, because upstream Z Skills relies heavily on
Claude Code features that are not available here: cron tools, Claude hooks,
Claude agent semantics, `.claude` logs, and `.claude/settings.json`.

Upstream validation looked healthy: the upstream test suite passed with
`504/504` tests passing from the cloned source repo.

## Executive Assessment

```text
┌───────────────────┬───────────────────┬────────────┬──────────────────────────────────┐
│ Tier              │ Skill             │ Fit        │ Note                             │
├───────────────────┼───────────────────┼────────────┼──────────────────────────────────┤
│ Best native fit   │ commit            │ High       │ Safe commit workflow             │
│                   │ verify-changes    │ High       │ Strong verification flow         │
│                   │ investigate       │ High       │ Root-cause debugging             │
│                   │ review-feedback   │ High       │ JSON and GitHub triage           │
│                   │ manual-testing    │ High       │ Browser testing recipes          │
│                   │ model-design      │ High       │ Reference guidance               │
├───────────────────┼───────────────────┼────────────┼──────────────────────────────────┤
│ Strong w/caveats  │ draft-plan        │ Med-High   │ Delegation caveat                │
│                   │ refine-plan       │ Med-High   │ Plan drift review                │
│                   │ doc               │ Med-High   │ Assumes docs structure           │
│                   │ add-example       │ Med-High   │ Domain-specific                  │
├───────────────────┼───────────────────┼────────────┼──────────────────────────────────┤
│ Supervised use    │ briefing          │ Medium     │ Assumes .claude paths            │
│                   │ plans             │ Medium     │ Z Skills plan format             │
│                   │ do                │ Medium     │ Scheduling not native            │
│                   │ qe-audit          │ Medium     │ Manual scheduled flows           │
│                   │ research-and-plan │ Medium     │ Claude agent language            │
│                   │ fix-report        │ Medium     │ Sprint artifacts required        │
│                   │ add-block         │ Medium     │ Domain/worktree heavy            │
├───────────────────┼───────────────────┼────────────┼──────────────────────────────────┤
│ Needs rewrite     │ run-plan          │ Low-Med    │ Cron/hooks/agents/.claude        │
│                   │ fix-issues        │ Low-Med    │ Claude orchestration heavy       │
│                   │ research-and-go   │ Low-Med    │ Depends on cron continuation     │
├───────────────────┼───────────────────┼────────────┼──────────────────────────────────┤
│ Weakest fit       │ update-zskills    │ Low        │ Claude installer                 │
└───────────────────┴───────────────────┴────────────┴──────────────────────────────────┘
```

## Detailed Skill Evaluation

```text
┌───────────────────┬──────────────┬────────────┬────────────────────────────────────────────────────────────────────────────────┐
│ Skill             │ Agentic Use  │ Codex Fit  │ Evaluation                                                                     │
├───────────────────┼──────────────┼────────────┼────────────────────────────────────────────────────────────────────────────────┤
│ commit            │ High         │ High       │ Excellent agentic guardrail for turning messy working-tree state into a clean  │
│                   │              │            │ commit. It forces inventory, dependency tracing, unrelated-change protection,  │
│                   │              │            │ and review before commit.                                                      │
├───────────────────┼──────────────┼────────────┼────────────────────────────────────────────────────────────────────────────────┤
│ verify-changes    │ High         │ High       │ Strong verification operator. It pushes the agent to inspect diffs, assess     │
│                   │              │            │ test coverage, run tests, manually verify UI when needed, and fix issues       │
│                   │              │            │ recursively.                                                                   │
├───────────────────┼──────────────┼────────────┼────────────────────────────────────────────────────────────────────────────────┤
│ investigate       │ High         │ High       │ Strong debugging skill. It requires reproduction, trace-based root cause,      │
│                   │              │            │ proof before patching, and verification after the fix, which maps well to      │
│                   │              │            │ autonomous coding.                                                             │
├───────────────────┼──────────────┼────────────┼────────────────────────────────────────────────────────────────────────────────┤
│ review-feedback   │ Medium       │ High       │ Good triage workflow for feedback exports. Agentic value is bounded because    │
│                   │              │            │ filing issues needs judgment and sometimes user approval, but the steps are    │
│                   │              │            │ concrete.                                                                      │
├───────────────────┼──────────────┼────────────┼────────────────────────────────────────────────────────────────────────────────┤
│ manual-testing    │ Medium       │ High       │ Useful operational checklist for browser verification. It improves agent       │
│                   │              │            │ behavior by requiring real mouse and keyboard events instead of synthetic      │
│                   │              │            │ shortcuts.                                                                     │
├───────────────────┼──────────────┼────────────┼────────────────────────────────────────────────────────────────────────────────┤
│ model-design      │ Low          │ High       │ Mostly reference guidance rather than an autonomous workflow. Very reliable    │
│                   │              │            │ because it has few runtime dependencies and gives clear layout heuristics.     │
├───────────────────┼──────────────┼────────────┼────────────────────────────────────────────────────────────────────────────────┤
│ draft-plan        │ High         │ Med-High   │ High-value planning workflow. It is agentically strong when delegation is      │
│                   │              │            │ allowed, but in Codex the adversarial multi-agent loop often has to be run     │
│                   │              │            │ inline.                                                                        │
├───────────────────┼──────────────┼────────────┼────────────────────────────────────────────────────────────────────────────────┤
│ refine-plan       │ High         │ Med-High   │ Good for long-running work where plans drift. It focuses the agent on          │
│                   │              │            │ completed-vs-remaining scope and prevents stale assumptions from leaking       │
│                   │              │            │ forward.                                                                       │
├───────────────────┼──────────────┼────────────┼────────────────────────────────────────────────────────────────────────────────┤
│ doc               │ Medium       │ Med-High   │ Good documentation audit workflow, especially in the source project. General   │
│                   │              │            │ usefulness drops when the repo does not match its assumed docs and block-      │
│                   │              │            │ library structure.                                                             │
├───────────────────┼──────────────┼────────────┼────────────────────────────────────────────────────────────────────────────────┤
│ add-example       │ Medium       │ Med-High   │ Good domain workflow for adding examples with tests and screenshots. Agentic   │
│                   │              │            │ quality is strong inside block-diagram projects, weaker outside them.          │
├───────────────────┼──────────────┼────────────┼────────────────────────────────────────────────────────────────────────────────┤
│ briefing          │ Medium       │ Medium     │ Useful status-gathering skill, especially with helper scripts. Codex efficacy  │
│                   │              │            │ is reduced by assumptions about .claude worktrees, logs, and scheduled         │
│                   │              │            │ briefings.                                                                     │
├───────────────────┼──────────────┼────────────┼────────────────────────────────────────────────────────────────────────────────┤
│ plans             │ Medium       │ Medium     │ Good plan dashboard concept. It helps agents choose next work, but only if the │
│                   │              │            │ repo follows Z Skills plan formatting and progress conventions.                │
├───────────────────┼──────────────┼────────────┼────────────────────────────────────────────────────────────────────────────────┤
│ do                │ High         │ Medium     │ Good lightweight task dispatcher in concept. Codex can use the direct          │
│                   │              │            │ workflow, but scheduled runs, PR automation, and some delegation behavior need │
│                   │              │            │ manual adaptation.                                                             │
├───────────────────┼──────────────┼────────────┼────────────────────────────────────────────────────────────────────────────────┤
│ qe-audit          │ High         │ Medium     │ Strong quality-engineering mindset: coverage gaps, stress paths, and recent-   │
│                   │              │            │ change audits. Scheduled and parallel audit pieces are not native in Codex.    │
├───────────────────┼──────────────┼────────────┼────────────────────────────────────────────────────────────────────────────────┤
│ research-and-plan │ High         │ Medium     │ Good decomposition workflow for broad goals. The core thinking ports well, but │
│                   │              │            │ the skill still contains Claude-specific Skill-vs-Agent orchestration          │
│                   │              │            │ guidance.                                                                      │
├───────────────────┼──────────────┼────────────┼────────────────────────────────────────────────────────────────────────────────┤
│ fix-report        │ Medium       │ Medium     │ Useful for reviewing sprint outputs and deciding what to land or close.        │
│                   │              │            │ Depends heavily on Z Skills reports, worktrees, and landing markers.           │
├───────────────────┼──────────────┼────────────┼────────────────────────────────────────────────────────────────────────────────┤
│ add-block         │ High         │ Medium     │ Detailed, disciplined workflow for adding block types. Good agentic checklist, │
│                   │              │            │ but domain-specific and still tied to Claude worktree/verification             │
│                   │              │            │ assumptions.                                                                   │
├───────────────────┼──────────────┼────────────┼────────────────────────────────────────────────────────────────────────────────┤
│ run-plan          │ Very High    │ Low-Med    │ The strongest upstream orchestration skill, but the least clean Codex fit. It  │
│                   │              │            │ depends on Claude agents, cron continuation, hooks, .claude logs, and Z Skills │
│                   │              │            │ markers.                                                                       │
├───────────────────┼──────────────┼────────────┼────────────────────────────────────────────────────────────────────────────────┤
│ fix-issues        │ Very High    │ Low-Med    │ Powerful bug-sprint orchestrator. Agentic design is strong, but native Codex   │
│                   │              │            │ use is limited by scheduling, GitHub orchestration, hooks, and multi-agent     │
│                   │              │            │ assumptions.                                                                   │
├───────────────────┼──────────────┼────────────┼────────────────────────────────────────────────────────────────────────────────┤
│ research-and-go   │ Very High    │ Low-Med    │ Ambitious end-to-end autonomous pipeline. Most value is architectural; Codex   │
│                   │              │            │ cannot currently reproduce the unattended cron-driven continuation model.      │
├───────────────────┼──────────────┼────────────┼────────────────────────────────────────────────────────────────────────────────┤
│ update-zskills    │ Medium       │ Low        │ Important upstream maintenance skill, but mostly installs Claude               │
│                   │              │            │ infrastructure. For Codex it is reference material until rewritten for .codex  │
│                   │              │            │ paths and semantics.                                                           │
└───────────────────┴──────────────┴────────────┴────────────────────────────────────────────────────────────────────────────────┘
```

## What Converted Well

- Prompt-only workflows converted well.
- Engineering discipline skills converted best: `commit`, `verify-changes`,
  `investigate`, `draft-plan`, and `refine-plan`.
- Reference and checklist-style skills converted cleanly: `manual-testing`,
  `model-design`, and `review-feedback`.
- The installed skill frontmatter is Codex-compatible. Claude-only fields such
  as `disable-model-invocation` and `argument-hint` were removed.
- Upstream helper scripts were preserved for reference and optional manual use.

## What Does Not Quite Work

### Native Scheduling

Upstream Z Skills depends on `CronList`, `CronCreate`, and `CronDelete` for
commands such as:

- `/run-plan ... every ...`
- `/run-plan ... finish auto`
- `/fix-issues ... every ...`
- `/qe-audit ... every ...`
- `/briefing ... every ...`

Those tools are not available in this Codex environment. The installed adapter
marks scheduled continuation as unsupported unless an external scheduler is
provided.

Potential improvement:

- Add a Codex-native scheduler shim that writes continuation jobs to a local
  queue file such as `.codex/zskills-jobs.json`.
- Provide a small shell runner that can be called by `cron`, `systemd`, or a
  user-triggered command.
- Rewrite scheduled skill sections to emit explicit next-step commands instead
  of calling unavailable Claude cron tools.

### Claude Hooks

The upstream safety model relies on `.claude/settings.json` and hook scripts.
The hook scripts themselves test well, but Codex does not automatically enforce
Claude hooks.

Potential improvement:

- Port the hook configuration to a Codex-compatible project policy document.
- Add optional Git hooks under `.git/hooks` or a repo-local `scripts/safe-git`
  wrapper for teams that want enforcement.
- Rewrite safety-critical skill sections so they perform explicit checks in the
  current turn instead of assuming hooks will block unsafe operations.

### Agent And Worktree Semantics

Many upstream skills refer to Claude `Agent` or `Task` tools, `isolation:
"worktree"`, and Claude-specific subagent behavior. Codex has `spawn_agent`,
but the active Codex instructions only allow spawning agents when the user
explicitly requests delegation or parallel agent work.

Potential improvement:

- Replace Claude agent instructions with Codex delegation rules.
- Add two execution modes to orchestration skills:
  - `inline`: no subagents; lower independence, simpler operation.
  - `delegated`: uses Codex `spawn_agent` only when explicitly authorized.
- Rewrite verification sections to state the achieved freshness mode rather
  than assuming sibling subagents are always available.

### `.claude` State And Logs

Several skills assume `.claude/worktrees`, `.claude/logs`, and
`.claude/zskills-config.json`. Codex does not maintain `.claude/logs`, and
Codex-native configuration should prefer `.codex/zskills-config.json`.

Potential improvement:

- Normalize all config lookup examples to:
  1. `.codex/zskills-config.json`
  2. `.claude/zskills-config.json` as a compatibility fallback
- Remove `.claude/logs` commit requirements from Codex-specific copies.
- Update helper scripts such as `briefing.cjs` and `briefing.py` to detect
  both `.codex` and `.claude` layouts.

### `update-zskills`

`update-zskills` is the weakest Codex fit because it mostly installs Claude
Code infrastructure.

Potential improvement:

- Split it into two skills:
  - `update-zskills-upstream`: update the upstream vendored source.
  - `update-zskills-codex`: regenerate Codex-converted skills and validate them.
- Make the Codex updater idempotently install to `~/.codex/skills`.
- Add a conversion script that patches known Claude-only sections rather than
  relying on a general adapter header.

### Autonomous Pipelines

`research-and-go`, `run-plan finish auto`, and `fix-issues auto` are valuable
designs, but they are not fully autonomous in Codex as installed. They assume
cron-fired continuation, automatic hook enforcement, and flexible subagent
dispatch.

Potential improvement:

- Treat these as supervised workflows for now.
- Rebuild autonomy around explicit resumable state files in `.codex/zskills/`.
- Make each phase executable as a single top-level Codex request.
- Produce a final command at the end of each phase, such as:
  `Continue run-plan for plans/FEATURE.md phase 3`.

## Recommended Next Steps

1. Keep using the high-fit skills immediately: `commit`, `verify-changes`,
   `investigate`, `draft-plan`, `refine-plan`, `review-feedback`,
   `manual-testing`, and `model-design`.
2. Treat `run-plan`, `fix-issues`, and `research-and-go` as supervised
   playbooks until rewritten.
3. Build a small conversion script so the Codex port can be regenerated from
   upstream Z Skills without manual patch drift.
4. Rewrite `update-zskills` first, because it should become the maintainable
   entry point for future Codex-native updates.
5. Rewrite `run-plan` second, because it is the core orchestration engine and
   the highest-value target for a real Codex-native port.
