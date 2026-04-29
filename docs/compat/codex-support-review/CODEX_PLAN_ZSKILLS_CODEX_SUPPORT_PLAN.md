# Z Skills Claude/Codex Support Plan

## Summary

Add first-class Codex support to Z Skills without regressing Claude Code support.
The implementation target is the active development repository,
`github.com/zeveck/zskills-dev`, not the currently published mirror at
`github.com/zeveck/zskills`.

This plan is intentionally pattern-level. The public mirror is behind the dev
repo, and a newer polished Z Skills release may land before this work is
applied. Implementers must refresh against latest `zskills-dev` before editing
and preserve the compatibility patterns here rather than hardcoding today’s
exact file list or skill count.

Core decision: keep one canonical source of skill intent, then use
provider-specific progressive disclosure modules for Claude and Codex behavior.
Do not maintain separate hand-edited Claude and Codex forks.

## Current State

- Public `zskills` was inspected at commit `14dea81da487`.
- `zskills-dev` was inspected at commit `15642f8eeef`.
- `zskills-dev` is ahead of public `zskills` and currently includes newer skills
  such as `cleanup-merged`, `create-worktree`, and `quickfix`.
- Existing Codex installation used a shallow `Codex Port Notes` adapter in each
  installed skill. That makes many skills usable as playbooks, but it does not
  fully convert orchestration behavior.
- The strongest Codex fits are procedural/review skills such as `commit`,
  `verify-changes`, `investigate`, `review-feedback`, `manual-testing`, and
  `model-design`.
- The weakest Codex fits are orchestration and installer skills such as
  `run-plan`, `fix-issues`, `research-and-go`, and `update-zskills`, because
  they depend on Claude cron tools, hooks, agent semantics, `.claude` state, and
  release/install conventions.

## Design Principles

1. **Shared intent, provider-specific runtime.** Keep workflow intent in a
   canonical skill source, but isolate runtime-specific behavior into provider
   modules.
2. **Provider support is a contract, not prose.** Do not rely on general adapter
   notes to override contradictory instructions later in the file.
3. **Progressive disclosure must be deterministic.** Every skill must load
   provider behavior before mode behavior.
4. **Generate and test outputs.** Claude and Codex rendered skill trees should be
   generated from shared source and validated in CI.
5. **Prefer neutral shared state.** Cross-provider pipeline state should live
   under `.zskills/` where possible; provider runtime files should live under
   `.claude/` or `.codex/` only when the provider requires it.
6. **Do not weaken Claude behavior.** Existing Claude tests and safety contracts
   remain authoritative for Claude output.

## Architecture

### Provider Model

Add a provider layer with at least these providers:

- `claude`
- `codex`

Each provider defines capabilities for:

- scheduler
- delegation
- hook/enforcement model
- config paths
- install target
- log/session state
- command surface
- rules/instructions output

The provider contract should be represented in a manifest file, not inferred
from prose. A suggested shape:

```yaml
providers:
  claude:
    skills_dir: ".claude/skills"
    rules_dir: ".claude/rules/zskills"
    config_path: ".claude/zskills-config.json"
    scheduler: "claude-cron"
    delegation: "claude-agent"
    hooks: "claude-pretooluse"
  codex:
    skills_dir: "~/.codex/skills"
    rules_dir: ".codex/zskills"
    config_path: ".codex/zskills-config.json"
    scheduler: "external-queue"
    delegation: "codex-spawn-agent-or-inline"
    hooks: "explicit-checks"
```

Exact format can be JSON, YAML, or TOML, but it must be machine-readable and
validated by tests.

### Progressive Disclosure Load Order

Every skill entrypoint must use the same load order:

```text
SKILL.md bootstrap
  -> provider/<provider>.md
  -> modes/<mode>.md
  -> references/*.md as needed
```

Rules:

- `SKILL.md` owns frontmatter, trigger summary, argument parsing overview, and
  the instruction to load the provider module first.
- Provider modules define runtime/tool behavior and provider-specific
  substitutions.
- Mode modules define workflow-specific steps.
- Reference modules contain large examples, templates, schemas, or repeated
  checklists.
- Mode files must not silently assume Claude-only or Codex-only capabilities
  unless they explicitly load a provider-specific submodule.

This avoids brittle “load a mode, then override it later” behavior.

### Provider Modules

Add provider modules at a consistent path, for example:

```text
skills/<skill>/providers/claude.md
skills/<skill>/providers/codex.md
```

For common behavior, use shared provider references:

```text
providers/claude/common.md
providers/codex/common.md
providers/codex/scheduler.md
providers/codex/delegation.md
providers/codex/git-safety.md
```

Skill-local provider modules may be short and link to common provider
references. This keeps behavior centralized while still allowing skill-specific
exceptions.

### Rendered Outputs

Support two generated outputs:

- Claude output: current `.claude/skills` behavior plus existing Claude rules,
  hooks, and `.claude/rules/zskills/managed.md`.
- Codex output: Codex-compatible skills with no raw Claude cron/hook/log
  assumptions, installed to `~/.codex/skills` or a configured Codex skill
  destination.

Generated outputs should include metadata recording:

- source repo URL
- source commit
- provider
- render timestamp
- skill manifest version
- generator version

Do not rely on the shallow “Codex Port Notes” header as the long-term porting
strategy.

## Codex Runtime Contract

### Delegation

Codex delegation must follow Codex rules:

- Use `spawn_agent` only when the user explicitly requests delegation or
  parallel agent work.
- Otherwise run inline and report the reduced freshness/isolation guarantee.
- Verification reports must state which mode was achieved:
  - `multi-agent`
  - `inline`
  - `external reviewer unavailable`

Codex provider modules must not instruct the agent to inspect for Claude
`Agent` or `Task` tools.

### Scheduler

Implement Codex autonomy through an external queue and runner, not through
Claude `CronCreate`, `CronList`, or `CronDelete`.

Suggested files:

```text
.codex/zskills/jobs.jsonl
.codex/zskills/locks/
.codex/zskills/runs/
```

Each queued job must be structured data, not raw shell:

```json
{
  "id": "run-plan.FEATURE.phase-3",
  "provider": "codex",
  "skill": "run-plan",
  "mode": "phase",
  "args": {
    "plan": "plans/FEATURE.md",
    "phase": "3",
    "landing": "cherry-pick"
  },
  "status": "queued",
  "attempt": 0,
  "max_attempts": 3,
  "not_before": "2026-04-26T13:00:00Z",
  "created_at": "2026-04-26T12:55:00Z"
}
```

Required scheduler semantics:

- idempotency key prevents duplicate queued work
- lock file prevents concurrent execution of the same job
- runner refuses dirty working trees unless the job explicitly allows them
- runner records `queued`, `running`, `succeeded`, `failed`, `retrying`, and
  `cancelled`
- retry policy is explicit and bounded
- interrupted jobs can be recovered
- only allow known skill/mode pairs and structured arguments
- every autonomous phase also prints a human-runnable continuation command

### Hooks And Enforcement

Codex does not automatically enforce Claude PreToolUse hooks.

Codex provider behavior should:

- perform explicit preflight checks in the current turn
- optionally provide a Git hook or wrapper script for teams that want local
  enforcement
- not claim `.claude/settings.json` hook enforcement exists in Codex
- keep `.zskills/tracking` marker semantics where they are provider-neutral

### Paths And State

Use this lookup order for config:

1. `.codex/zskills-config.json`
2. `.claude/zskills-config.json` as compatibility fallback

Use `.zskills/` for shared pipeline state where practical:

```text
.zskills/tracking/
.zskills/manifests/
.zskills/reports/
```

Use `.codex/zskills/` only for Codex runtime details:

```text
.codex/zskills/jobs.jsonl
.codex/zskills/locks/
.codex/zskills/managed.md
```

Codex output must not require `.claude/logs`.

## Claude Runtime Contract

Claude output must preserve existing behavior:

- `.claude/skills`
- `.claude/rules/zskills/managed.md`
- `.claude/zskills-config.json`
- Claude hook installation and settings merge
- Claude cron tools where currently used
- Claude `Agent`/`Task` semantics where the skill relies on them

Provider work must not weaken existing Claude tests. If a provider abstraction
forces a behavior change in Claude, add an explicit compatibility test and make
the change intentional.

## Skill Migration Strategy

### Phase 1 — Framework And Tests

Start with infrastructure rather than rewriting every skill.

Implement:

- provider manifest
- provider common modules
- renderer scaffolding
- leakage tests
- load-graph tests
- Codex scheduler schema tests
- generated-output manifest

No skill should be considered migrated until its provider behavior is covered by
tests.

### Phase 2 — Installer And Renderer

Migrate `update-zskills` first.

Required behavior:

- preserve current Claude install/update/rerender behavior
- add Codex install/update/rerender behavior
- install or update provider modules
- render Claude and Codex outputs
- write provider-specific managed rules/instructions
- verify generated output matches committed/generated artifacts
- report source commit and provider compatibility status

`update-zskills --rerender` should become the release gate for provider output.

### Phase 3 — Core Orchestration

Migrate `run-plan` next.

Required behavior:

- shared plan parsing and phase selection
- provider-specific delegation
- provider-specific scheduling
- provider-specific hook/enforcement assumptions
- provider-neutral `.zskills/tracking` semantics where possible
- Codex continuation queue support for `finish auto`
- human-runnable continuation output after each phase

Then migrate:

- `fix-issues`
- `research-and-go`
- `do`
- `qe-audit`
- `briefing`

### Phase 4 — Lower-Risk Skills

Migrate low-runtime-dependency skills after the framework is stable:

- `commit`
- `verify-changes`
- `investigate`
- `draft-plan`
- `refine-plan`
- `review-feedback`
- `manual-testing`
- `model-design`
- `doc`
- block-diagram add-ons

These mostly need provider path/config/delegation cleanup, not new architecture.

## Testing Plan

### Provider Leakage Tests

Codex-rendered output must not contain active instructions to use:

- `CronCreate`
- `CronList`
- `CronDelete`
- `.claude/settings.json`
- `.claude/logs`
- Claude `Agent`/`Task` tool checks
- claims that Claude hooks enforce Codex actions

Claude-rendered output must not contain active instructions requiring:

- `.codex/zskills-config.json`
- `.codex/zskills/jobs.jsonl`
- Codex `spawn_agent`
- Codex-only scheduler commands

Cross-provider explanatory documentation is allowed only in designated
architecture docs, not active skill instructions.

### Progressive Disclosure Tests

Add load-graph tests:

- every `SKILL.md` references exactly one provider-loading step
- provider module resolves before mode module
- all referenced files exist
- no cycles
- no provider conflicts
- mode files do not bypass provider contract for scheduler/delegation/hooks

### Scheduler Tests

Add Codex scheduler tests for:

- duplicate job prevention
- lock acquisition and release
- stale lock recovery
- interrupted job recovery
- dirty tree refusal
- structured argument validation
- allowed skill/mode whitelist
- bounded retries
- cancelled job handling
- human continuation command generation

### Release And Drift Tests

Add release tests for:

- manifest skill count equals actual skills
- add-on manifest equals actual add-ons
- dev-only skills are stripped from prod when marked
- generated Claude artifacts match committed output
- generated Codex artifacts match committed output
- public mirror drift is detected before release
- changelog/release metadata includes provider compatibility status

Existing recursive conformance tests should continue to grep whole skill
directories, not only `SKILL.md`, so contracts can live in provider/mode files.

## Documentation Updates

Update Z Skills docs to explain:

- Claude remains the default/primary supported provider until Codex output is
  fully validated.
- Codex support uses generated provider-specific output.
- Autonomous Codex continuation requires an external queue runner.
- Scheduled behavior differs by provider.
- Provider compatibility is tracked per skill.
- A future public mirror may lag behind dev, so issue reports should include
  source commit and provider.

Add a short compatibility table:

```text
Skill              Claude  Codex  Notes
commit             full    full   low provider dependency
verify-changes     full    full   delegation differs
run-plan           full    beta   scheduler/delegation differs
fix-issues         full    beta   scheduler/GitHub orchestration differs
update-zskills     full    beta   provider renderer required
```

The exact table should be generated from the manifest once the manifest exists.

## Agent Review Notes

A review agent evaluated the plan direction and found the approach sound with
these conditions:

- Provider behavior must be isolated as a real contract, not a prose patch.
- Load order must be deterministic: `SKILL.md` bootstrap, provider module, mode
  module, references.
- Codex scheduler support must define a queue API with schema, locking,
  idempotency, status transitions, recovery, retry policy, and command
  validation.
- Release drift between `zskills-dev` and public `zskills` must be tested, not
  left as documentation.
- Provider modules, progressive disclosure, scheduler state, and release
  rendering should all be treated as testable interfaces.

## Acceptance Criteria

The implementation is complete when:

- Claude behavior still passes all existing upstream tests.
- Codex-rendered skills install cleanly into a Codex skill directory.
- Provider leakage tests pass for Claude and Codex output.
- Load-graph tests pass for all skills.
- Codex scheduler tests pass.
- `update-zskills --rerender` or its provider-aware replacement validates both
  Claude and Codex outputs.
- Release workflow detects manifest/public mirror drift before publishing.
- At least `update-zskills` and `run-plan` have provider-aware implementations.
- Documentation clearly states provider support status and scheduler differences.

## Implementation Defaults

- Target latest `zskills-dev` at implementation time.
- Use shared canonical source with generated provider-specific outputs.
- Prefer `.zskills/` for provider-neutral state.
- Prefer `.codex/zskills/` for Codex runtime state.
- Keep `.claude/rules/zskills/managed.md` for Claude rules.
- Treat public `zskills` as a release artifact, not the development source.
- Do not hand-maintain separate Claude and Codex skill forks.
