---
title: Codex Support for Z Skills Shared Source
created: 2026-04-26
status: active
---

# Plan: Codex Support for Z Skills Shared Source

## Overview

Update Z Skills so the same upstream source can support both Claude Code and
Codex without maintaining a hand-edited Codex fork. The plan targets
`github.com/zeveck/zskills-dev` as the implementation repo, but it is
deliberately pattern-driven because upstream is active and a newer, more
polished version with additional skills may land before execution.

The intended end state is a shared-source distribution model:

- Canonical skill content stays in upstream `skills/` and helper assets stay in
  upstream `scripts/`, `hooks/`, `config/`, and templates.
- Agent-specific behavior is expressed through a small compatibility contract,
  adapter snippets, generated install targets, and conformance tests.
- Claude remains supported through `.claude/skills`, `.claude/settings.json`,
  Claude hooks, Claude `Agent`/`Task`, and Claude `Cron*` tools.
- Codex is supported through `.codex/skills`, `AGENTS.md` or Codex-oriented
  project guidance, explicit in-turn checks, Codex delegation only when the
  runtime exposes a delegation tool and the user permits delegation, and an
  external scheduler bridge for unattended continuation.

Research inputs:

- `CODEX_ZSKILLS_REPORT.md` found 21 installed Codex skills and identified the
  strongest fits as prompt/checklist workflows such as `commit`,
  `verify-changes`, `investigate`, `draft-plan`, and `refine-plan`.
- The same report identified weak Codex fit around native scheduling, Claude
  hook enforcement, Claude `Agent`/`Task` semantics, `.claude` logs/state, and
  `update-zskills`.
- Local installed Codex skills currently rely on repeated "Codex Port Notes"
  headers instead of a native shared-source generation path.
- As of the upstream snapshot inspected on 2026-04-26, `zskills-dev` had 21
  core skills and newer additions such as `create-worktree`, `cleanup-merged`,
  and `quickfix`; its README still describes Claude-first installation into
  `.claude/skills` and `.claude/zskills-config.json`.

Out of scope:

- Do not rewrite every skill line-by-line against today's upstream text.
- Do not remove Claude behavior or weaken Claude hook/session assumptions.
- Do not implement a Codex-native hidden scheduler inside Codex. Codex
  scheduled/autonomous workflows use an external scheduler bridge.
- Do not make product-specific changes to downstream repos consuming Z Skills.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 -- Compatibility Contract and Inventory | ⬚ | | |
| 2 -- Shared Source Markers and Generator | ⬚ | | |
| 3 -- Runtime Paths, Config, and Scheduler Bridge | ⬚ | | |
| 4 -- Convert Orchestration Guidance by Capability | ⬚ | | |
| 5 -- Installer and Distribution Flow | ⬚ | | |
| 6 -- Cross-Agent Test Matrix and Documentation | ⬚ | | |

## Phase 1 -- Compatibility Contract and Inventory

### Goal

Define the Claude/Codex compatibility contract and build an inventory that
drives later conversion work from patterns rather than brittle per-skill edits.

### Work Items

- [ ] Create `docs/compat/agent-capabilities.md` documenting the supported
  capability matrix for Claude and Codex.
- [ ] Create `docs/compat/codex-porting-patterns.md` with canonical rules for
  paths, config lookup, instruction files, agents, scheduling, hooks, logs,
  reports, and destructive-operation safeguards.
- [ ] Add a script such as `scripts/audit-agent-specifics.sh` that scans
  `skills/`, `scripts/`, `hooks/`, templates, and README docs for agent-specific
  anchors: `.claude`, `CLAUDE.md`, `settings.json`, `Agent`, `Task`, `CronList`,
  `CronCreate`, `CronDelete`, `.claude/logs`, hook enforcement claims, and
  hardcoded install paths.
- [ ] Classify every finding into one of four actions:
  `shared` (valid for both agents), `claude-only`, `codex-adapted`, or
  `unsupported-with-external-bridge`.
- [ ] Add a generated report path, for example
  `reports/agent-compat-inventory.md`, summarizing findings by skill and
  helper asset.
- [ ] Record the upstream commit hash used for the inventory and run the
  upstream test suite available at that commit. If tests are too expensive or
  environment-specific, record the exact skipped command and reason.
- [ ] Add the inventory script to the upstream test runner if the repo already
  has a script aggregation point, or document it as a required manual check if
  the current runner structure changes before execution.

### Design & Constraints

The compatibility contract must treat this as a shared-source project, not as
two forks. The inventory should produce guidance like:

| Upstream concept | Claude target | Codex target |
|---|---|---|
| Skill install path | `.claude/skills/<name>/SKILL.md` | `.codex/skills/<name>/SKILL.md` or user-level `$CODEX_HOME/skills/<name>/SKILL.md` |
| Project instructions | `CLAUDE.md` | `AGENTS.md` plus active Codex developer/user instructions |
| Config lookup | target-aware: explicit override, then `.claude/zskills-config.json`, then compatibility fallback | target-aware: explicit override, then `.codex/zskills-config.json`, then `.claude/zskills-config.json` fallback |
| Hooks | Claude PreToolUse hooks in `.claude/settings.json` | explicit checks in skills; optional Git hooks or wrappers only when installed by user choice |
| Agents | Claude `Agent`/`Task` | Codex delegation tool if available and explicitly authorized; otherwise inline freshness mode |
| Scheduling | Claude `Cron*` tools | external scheduler bridge invoking top-level Codex requests |
| Logs | `.claude/logs` | no required Codex session-log commit path |

The inventory should avoid asserting exact line numbers as durable facts. It
may include current anchors as evidence, but the durable output is the
classification and conversion rule.

### Acceptance Criteria

- [ ] `docs/compat/agent-capabilities.md` explicitly covers config, skill
  install paths, instruction files, hooks, scheduling, delegation, logs,
  reports, worktrees, and tests.
- [ ] `docs/compat/codex-porting-patterns.md` says Codex scheduled/autonomous
  behavior requires an external scheduler bridge.
- [ ] `scripts/audit-agent-specifics.sh` exits nonzero when it finds an
  unclassified Claude-only anchor in shared content.
- [ ] `reports/agent-compat-inventory.md` is generated from the script and
  covers all current `skills/*/SKILL.md` files, including any newer skills that
  landed before implementation.
- [ ] The report records the upstream commit hash and the result of the
  upstream test command used as the baseline.
- [ ] New skills or helper assets fail inventory until classified.
- [ ] The inventory distinguishes weak-fit orchestration skills from high-fit
  prompt/checklist skills using the categories from `CODEX_ZSKILLS_REPORT.md`
  without freezing the exact local installed skill count.

### Dependencies

None.

## Phase 2 -- Shared Source Markers and Generator

### Goal

Create a small generation layer that emits Claude and Codex install artifacts
from the same upstream skill source.

### Work Items

- [ ] Add a source convention for agent-specific fragments. Prefer progressive
  disclosure blocks that are easy for humans to maintain, for example:
  `<!-- zskills:agent claude -->...<!-- /zskills:agent -->`,
  `<!-- zskills:agent codex -->...<!-- /zskills:agent -->`, and
  `<!-- zskills:agent shared -->...<!-- /zskills:agent -->`.
- [ ] Define the rule that shared prose is the default; agent-specific blocks
  are used only where capability semantics differ.
- [ ] Implement `scripts/render-skills.sh` or extend the existing release/build
  script to render two outputs:
  `dist/claude/skills/<name>/SKILL.md` and
  `dist/codex/skills/<name>/SKILL.md`.
- [ ] Ensure the Codex renderer removes or rewrites Claude-only frontmatter
  fields that Codex does not use, while preserving `name` and `description`.
- [ ] Replace the repeated installed "Codex Port Notes" header with generated
  Codex adaptation sections sourced from the compatibility contract.
- [ ] Add renderer tests with fixture skills covering shared-only content,
  Claude-only blocks, Codex-only blocks, nested-looking text that must not be
  parsed as a block, and malformed block boundaries.
- [ ] Add a nonblocking inventory warning mode for unconverted upstream skills,
  so Phase 2 can prove rendering mechanics before Phase 4 has converted all
  Claude-only operational sections.

### Design & Constraints

Progressive disclosure should make the common path readable. A skill should
not become a maze of conditionals. Use agent-specific blocks around narrow
sections such as scheduling commands, hook installation, and delegation
instructions.

Renderer behavior should be deterministic:

```text
Input:  skills/<skill>/SKILL.md
Output: dist/claude/skills/<skill>/SKILL.md
        dist/codex/skills/<skill>/SKILL.md
Rule:   shared content included in both; target block included only in target;
        other target blocks omitted; malformed markers fail the build.
```

Do not use ad hoc global substitutions for semantics like replacing every
`CLAUDE.md` with `AGENTS.md`. Some mentions are historical or Claude-specific
and should stay in Claude output only. The renderer should apply explicit block
selection and small frontmatter transforms, not broad text mutation.

### Acceptance Criteria

- [ ] Rendering all current upstream skills succeeds for both Claude and Codex.
- [ ] Fixture-rendered Codex output omits Claude-only fixture blocks and keeps
  Codex/shared blocks.
- [ ] Fixture-rendered Claude output omits Codex-only fixture blocks and keeps
  Claude/shared blocks.
- [ ] Generated upstream output may still contain unconverted findings from the
  Phase 1 inventory, but they are reported as classified warnings rather than
  hidden or silently rewritten.
- [ ] Claude output preserves existing Claude visible content except for
  documented stripping of marker comments and frontmatter normalization.
- [ ] Renderer fixture tests cover success and failure paths.
- [ ] Golden fixture tests prove marker comments are stripped from generated
  target output.

### Dependencies

Phase 1.

## Phase 3 -- Runtime Paths, Config, and Scheduler Bridge

### Goal

Make helper scripts and config resolution work under both `.claude` and
`.codex`, and introduce a Codex-compatible external scheduler bridge for
skills that currently rely on Claude `Cron*` tools.

### Work Items

- [ ] Add a target-aware config resolver script or documented shell snippet,
  for example `scripts/zskills-config-path.sh`, that accepts a target
  (`claude`, `codex`, or `auto`) and resolves config in this order: explicit
  env override, target-native config, then compatibility fallback.
- [ ] Update scripts that read config directly, such as `port.sh`,
  `apply-preset.sh`, `briefing.cjs`, `briefing.py`, and worktree/landing
  helpers, to use the resolver or the same tested lookup contract.
- [ ] Extend `config/zskills-config.schema.json` with agent-neutral fields
  where needed, such as `agent.target`, `scheduler.backend`,
  `scheduler.command_template`, and any existing `execution.*` fields required
  by newer upstream skills.
- [ ] Add `scripts/zskills-scheduler.sh` as an external bridge. It should
  manage a repo-local queue file such as `.zskills/scheduler/jobs.json` or
  `.codex/zskills-jobs.json`, and support at least `add`, `list`, `run-due`,
  `run-now`, and `remove`.
- [ ] Add `docs/compat/codex-scheduler-contract.md` specifying the bridge
  contract: job schema, prompt payload, working directory, environment, runner
  command template, lock file, retry policy, job state transitions, last exit
  status, and dry-run behavior.
- [ ] Add a fake-runner test harness so `run-due` can prove exact request
  rendering, locking, status updates, and retry behavior without invoking
  Codex itself.
- [ ] Define how Codex skills report scheduled work: emit the exact next
  top-level request for the external runner rather than claiming native Codex
  cron support.
- [ ] Add tests for config precedence, missing config fallback, malformed config
  handling, scheduler job creation, deduplication, cancellation, and due-job
  selection.

### Design & Constraints

External scheduler means the skill writes enough durable state for a separate
process to invoke Codex later. It does not mean Codex silently schedules itself.
Codex output should say what was registered and how to run it, for example:

```text
bash scripts/zskills-scheduler.sh run-due
```

The bridge should be useful from cron, systemd timers, GitHub Actions, or a
manual shell loop. It should not depend on a proprietary Codex cron tool.

Config lookup must not break either target. Claude runs prefer `.claude` when
both config files exist. Codex runs prefer `.codex` when both exist. Each target
may fall back to the other only for compatibility and only when its native file
is absent.

### Acceptance Criteria

- [ ] Helper scripts that read Z Skills config use the shared resolver or have
  tests proving equivalent target-aware behavior.
- [ ] Resolver tests cover both-config-present cases: Claude reads `.claude`;
  Codex reads `.codex`.
- [ ] Codex-rendered scheduling sections for `run-plan`, `fix-issues`,
  `research-and-go`, `do`, `qe-audit`, and `briefing` describe the external
  bridge and contain no direct Claude `Cron*` calls.
- [ ] Claude-rendered scheduling sections still describe Claude cron behavior
  if upstream retains it.
- [ ] Scheduler tests pass without network access and without invoking Codex by
  using a fake runner.
- [ ] `run-due --dry-run` prints the exact command/request that would be sent
  to the configured Codex runner.
- [ ] Scheduler locking prevents two `run-due` processes from executing the
  same job concurrently.
- [ ] Queue files and tracking markers are documented as durable state, not
  session logs.

### Dependencies

Phases 1 and 2.

## Phase 4 -- Convert Orchestration Guidance by Capability

### Goal

Update skill workflows so agent-specific behavior is selected by capability:
inline, delegated, scheduled, hook-enforced, or explicitly checked.

### Work Items

- [ ] Convert high-fit skills first: `commit`, `verify-changes`,
  `investigate`, `review-feedback`, `manual-testing`, `model-design`,
  `draft-plan`, and `refine-plan`.
- [ ] Convert medium-fit dispatcher and status skills next: `do`, `plans`,
  `briefing`, `doc`, `qe-audit`, `fix-report`, plus any newer upstream utility
  skills such as `cleanup-merged`, `quickfix`, or `create-worktree` if present.
- [ ] Convert low-fit orchestration skills last: `run-plan`, `fix-issues`, and
  `research-and-go`.
- [ ] For every place a skill asks for Claude `Agent` or `Task`, add a Codex
  branch that states:
  "Use a Codex delegation tool only when the runtime exposes one and the user
  explicitly requested delegation or parallel agent work; otherwise run inline
  and record the freshness mode."
- [ ] For every place a skill relies on Claude hooks, add a Codex branch that
  performs the check explicitly in the current turn or labels the check as an
  optional external enforcement mechanism.
- [ ] Remove Codex requirements to commit `.claude/logs`; preserve any
  user-facing reports and durable Z Skills tracking markers that are still
  meaningful.
- [ ] Update plan/report templates so they can say "Verification freshness:
  delegated", "inline", or "external/manual" rather than assuming a fresh
  Claude subagent exists.

### Design & Constraints

The conversion should be capability-based, not brand-string-based whenever
possible. For example, the plan should not say "Codex cannot verify"; it should
say "when no delegated reviewer is permitted, run inline verification and label
the freshness mode as inline."

Use progressive disclosure to keep skill bodies readable:

- Common workflow steps remain shared.
- Claude-only automation details live in Claude blocks.
- Codex-specific fallback and external scheduler details live in Codex blocks.
- Long examples or mode-specific mechanics move into `skills/<name>/modes/` or
  `skills/<name>/references/` when the upstream skill already uses that style.

### Acceptance Criteria

- [ ] No Codex-rendered skill claims Claude hooks or `.claude/settings.json`
  will enforce safety.
- [ ] No Codex-rendered skill names a concrete delegation tool as universally
  available; delegation is described as capability-detected and explicitly
  user-authorized.
- [ ] Verification/report templates include a freshness mode field where
  relevant.
- [ ] `run-plan`, `fix-issues`, and `research-and-go` have supervised Codex
  paths and external-scheduler paths, with clear stop/next/status behavior.
- [ ] Existing Claude tests and canaries that are not inherently
  Claude-environment-only still pass.

### Dependencies

Phases 1 through 3.

## Phase 5 -- Installer and Distribution Flow

### Goal

Make `/update-zskills` the maintainable entry point for both Claude and Codex
without turning it into a Claude-only installer.

### Work Items

- [ ] Split installer responsibilities into shared discovery, Claude target
  installation, Codex target installation, and validation.
- [ ] Add a concrete script surface, for example
  `scripts/install-zskills.sh --target <claude|codex|both>`, and keep
  `/update-zskills` as the skill/documentation wrapper that invokes or explains
  the script.
- [ ] Add an install target argument or auto-detection contract, for example
  `--target claude`, `--target codex`, and `--target both`.
- [ ] For Claude target, preserve `.claude/skills`, `.claude/settings.json`,
  hook registration, and `.claude/zskills-config.json` behavior.
- [ ] For Codex target, install generated skills to a defined location:
  project-local `.codex/skills/<name>/SKILL.md` for repo installs, or
  `$CODEX_HOME/skills/<name>/SKILL.md` only when a global install flag is
  explicitly selected.
- [ ] For Codex target, write or update `.codex/zskills-config.json`, and
  create or update Codex-compatible project guidance without claiming hook
  enforcement.
- [ ] Ensure add-on flags work for both targets and discover add-ons from the
  current upstream tree rather than from a hardcoded list.
- [ ] Update release/build docs so `zskills-dev` can render and test both
  targets before publishing to the public mirror.
- [ ] Add dry-run output that shows which files would be installed or changed
  for each target.

### Design & Constraints

The installer should preserve project-specific config fields when applying
presets. Existing upstream behavior says preset application owns only landing
mode, main protection, and the generic hook's main-push toggle. Codex target
support should keep that preservation principle, even if the Codex target does
not use the hook toggle directly.

Codex installation should not write `.claude/settings.json` unless the user
also selected the Claude target. Claude installation should not require
`.codex` files. Tests should exercise the script surface, not only the skill
prose.

### Acceptance Criteria

- [ ] `scripts/install-zskills.sh --target claude` preserves current Claude
  install/update behavior.
- [ ] `scripts/install-zskills.sh --target codex` installs generated Codex
  skills and config without writing Claude hook settings.
- [ ] `scripts/install-zskills.sh --target both` installs both generated
  targets and reports both validation results.
- [ ] `/update-zskills` documents or delegates to the script surface for the
  same three target modes.
- [ ] Re-running the installer is idempotent for unchanged generated output.
- [ ] Dry-run tests prove target-specific file lists are correct.
- [ ] Codex project-local and explicit global install locations are both
  covered by tests.
- [ ] Add-on installation tests cover at least core-only and block-diagram or
  equivalent current upstream add-on packs.

### Dependencies

Phases 1 through 4.

## Phase 6 -- Cross-Agent Test Matrix and Documentation

### Goal

Lock in the shared-source support model with tests, generated docs, and an
upgrade checklist that can handle a newer upstream landing before execution.

### Work Items

- [ ] Add a cross-agent conformance test that renders both targets and greps
  for forbidden unguarded target-specific anchors in the opposite output.
- [ ] Add smoke tests that install Claude target into a temporary project and
  Codex target into a temporary project.
- [ ] Add scheduler bridge tests to the main test runner.
- [ ] Add a "moving upstream" checklist to the plan or docs: refresh from
  `zskills-dev`, rerun inventory, classify new skills/assets, render both
  targets, run conformance, then update docs.
- [ ] Update README installation docs with separate Claude, Codex, and both
  target instructions.
- [ ] Update release docs so public mirror publication includes generated
  artifacts or a documented generation step.
- [ ] Add a short maintainer guide explaining when to use agent-specific blocks
  and when to keep prose shared.

### Design & Constraints

Tests should protect behavior contracts, not incidental wording. Current
upstream already has conformance-style tests that grep for critical invariants
across skill directories. Extend that pattern for cross-agent rendering rather
than asserting exact prose.

The moving-upstream checklist is required because this plan intentionally does
not freeze today's exact skill list. If upstream adds or removes skills before
execution, the implementer must update the inventory first and then apply the
same compatibility categories.

### Acceptance Criteria

- [ ] Cross-agent conformance fails when Claude-only operational requirements
  leak into Codex output.
- [ ] Cross-agent conformance fails when Codex-only warnings or external
  scheduler instructions leak into Claude output.
- [ ] Temporary-project install tests pass for Claude target, Codex target, and
  both target where environment prerequisites are available.
- [ ] README clearly says `zskills-dev` is pre-release and public users install
  from the public mirror, while maintainers implement this plan in
  `zskills-dev`.
- [ ] Release docs include a required render/test step before publishing.
- [ ] The final verification report includes the current upstream commit hash
  used for implementation, so reviewers can distinguish durable patterns from
  snapshot-specific facts.

### Dependencies

Phases 1 through 5.

## Plan Quality

**Drafting process:** `/draft-plan` with 1 planned adversarial review round

**Convergence:** Converged after round 1

**Remaining concerns:** The biggest residual risk is upstream drift. This plan
mitigates it by requiring an inventory refresh and classification before
implementation, and by specifying behavior contracts rather than exact edits
against today's skill text.

### Round History

| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1 | 8 findings | 0 separate DA findings | 8/8 |

### Round 1 Disposition

| Finding | Evidence | Disposition |
|---|---|---|
| Phase 2 acceptance required full Codex cleanup before conversion | Verified | Fixed: Phase 2 now validates renderer mechanics and classified warnings; forbidden-anchor checks moved to Phases 4/6. |
| Scheduler bridge lacked executable runner contract | Verified | Fixed: Phase 3 now requires a scheduler contract doc, fake runner, dry-run output, locking, state, and retries. |
| Codex delegation named `spawn_agent` too concretely | Verified | Fixed: plan now uses capability-detected Codex delegation instead of assuming one tool name. |
| `.codex`-first lookup would break Claude in both-target installs | Verified | Fixed: config lookup is target-aware with explicit Claude and Codex precedence tests. |
| Marker/generator diff acceptance conflicted with marked source | Verified | Fixed: Phase 2 now relies on golden fixtures and documented marker stripping. |
| Upstream drift gate was too late | Verified | Fixed: Phase 1 now records upstream commit/test baseline and fails unclassified new assets. |
| Installer target surface was only slash-command prose | Verified | Fixed: Phase 5 now requires a concrete installer script plus `/update-zskills` wrapper. |
| Codex install location was vague | Verified | Fixed: Phase 5 defines project-local and explicit global install targets with tests. |
