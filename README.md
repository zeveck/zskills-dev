<!-- prod-strip:start -->
[![🚀 Ship to Prod](https://img.shields.io/badge/%F0%9F%9A%80%20Ship%20to%20Prod-click%20to%20release-ea580c?style=for-the-badge)](https://github.com/zeveck/zskills-dev/actions/workflows/ship-to-prod.yml)
[![Tests](https://github.com/zeveck/zskills-dev/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/zeveck/zskills-dev/actions/workflows/test.yml)

> ⚠️ **This is `zskills-dev`, the development repository.** End users should
> install from the public mirror at **[`github.com/zeveck/zskills`](https://github.com/zeveck/zskills)**.
> Content here is pre-release and may include experimental skills, canary
> plans, and in-progress work. The release workflow above strips dev-only
> artifacts and publishes to prod — maintainers only.

---

<!-- prod-strip:end -->
# Z Skills

**23 core skills that plan, build, test, fix, and ship** — so one
developer can run a full engineering team. (21 user-facing slash
commands, 2 internal helpers, and a battery of safety hooks.)

Z Skills encodes hard-won lessons from real agent failures into reusable
prompt files. Each skill is a `.claude/skills/<name>/SKILL.md` file that
teaches Claude Code how to drive a specific workflow with the discipline
that prevents the most common AI agent failure modes: skipping
verification, weakening tests, deferring hard parts, and shipping broken
code.

## Docs

Read the docs in the **[in-browser docs viewer](https://zeveck.github.io/zskills-dev/docs/#docs/README.md)** or here in the repo.

New users may want to explore **[Installing zskills](https://zeveck.github.io/zskills-dev/docs/#docs/guides/installing-zskills.md)**,
the **[Workflows guide](https://zeveck.github.io/zskills-dev/docs/#docs/guides/workflows.md)**, or the
**[Skill reference](https://zeveck.github.io/zskills-dev/docs/#docs/skills/README.md)**.

For a higher level view see **[the ZSkills presentation →](https://zeveck.github.io/zskills-dev/PRESENTATION.html)**.

## The Skills

![Plan and Build skills](screenshots/skills-plan-build.png)

![Quality and Fix skills](screenshots/skills-quality-fix.png)

![Utility and Reference skills](screenshots/skills-utility.png)

## Install

By default zskills installs as a Claude Code plugin.
From inside a Claude Code session in your project:

```
/plugin marketplace add zeveck/zskills
/plugin install zs@zskills
```

Then **restart Claude Code (or `/clear`) so the plugin loads**, and run the
one-time setup:

```
/zs:update-zskills
```

This init adds a `.zskills/` line to your `.gitignore`, offers an optional
project config, verifies the install, and checks your environment (it reports
whether git, Python, and gh are present). The plugin itself writes nothing
into your repo — until you run the init, a one-line greeting on startup
reminds you.

> **zskills needs git and bash.** Its worktree, commit, and cherry-pick
> machinery is built on `git`, and its hooks and helper scripts run under
> `bash`. `/update-zskills` reports whether git (and gh, for PR-mode landing)
> are present; bash is assumed by every shipped script.

This is **not** a pip/npm package — do not `pip install` or `npm install` it.
The repo contains prompt files and scripts.

### Plugin vs. direct install

There's a more flexible **direct install** alternative — instead of the plugin,
it copies the skill source straight into your repo's `.claude/`. Same skills,
same behavior; the visible differences are the slash prefix and where the source
lives. Pick **one** — running both at once isn't a supported end-state (to
switch, uninstall one and install the other; see the install guide).

| | Plugin | `/update-zskills` (direct) |
|---|---|---|
| Install | `/plugin marketplace add zeveck/zskills`<br>`/plugin install zs@zskills` | clone + copy skills, then `/update-zskills install` |
| Update | `/plugin marketplace update` | `/update-zskills install` |
| Slash prefix | `/zs:run-plan`, `/zs:do` | bare `/run-plan`, `/do` |
| Skill source in your repo | no (plugin-managed) | yes (copied into `.claude/`) |

For more details see
**[Installing zskills](https://zeveck.github.io/zskills-dev/docs/#docs/guides/installing-zskills.md)**.

### `/update-zskills` install

Tell your agent (copy-paste):

```
Install zskills from github.com/zeveck/zskills — see repo for directions
```

A capable agent will clone the repo, copy the skills into your
project, and run `/update-zskills` to complete setup. Full manual steps
are below if you prefer to drive it yourself.

#### Steps

1. **Clone the repo** (if not already cloned):
   ```bash
   git clone https://github.com/zeveck/zskills.git /tmp/zskills
   ```

2. **Copy skills** from the clone into your project:
   ```bash
   mkdir -p .claude/skills
   cp -r /tmp/zskills/skills/* .claude/skills/
   ```

3. **Run `/update-zskills`** to complete setup. This is the important
   step — it creates `CLAUDE.md` with auto-detected project settings,
   installs hooks and scripts, registers hooks in `settings.json`,
   writes `.claude/zskills-config.json`, verifies dependencies, and
   reports any gaps. On a greenfield project it will ask you a single
   question: which landing mode you want (see below).

That's it. `/update-zskills` handles everything beyond the initial skill
copy.

### First-run choice: landing mode

On a fresh project `/update-zskills` will prompt:

```
How should /run-plan land changes?
  (1) cherry-pick — each phase squash-lands directly to main (simple, solo)
  (2) locked-main-pr — plans become feature branches + PRs, CI, auto-merge
      (locked main, shared repo)
  (3) direct — work on main, no worktree isolation (minimal, risky)
```

You can also pass the preset directly — no prompt — when you already know
what you want:

```
/update-zskills cherry-pick
/update-zskills locked-main-pr
/update-zskills direct
```

Running `/update-zskills <preset>` on an already-configured project
**rewrites only three fields** (`execution.landing`,
`execution.main_protected`, and the `BLOCK_MAIN_PUSH` toggle in the
safety hook). Every other config field is preserved. See
[Landing modes](#landing-modes) for what each preset does.

### Updating

- **Plugin:** run `/plugin marketplace update`. Everything runs from the
  plugin's own tree, so there are no project files to refresh; an optional
  follow-up `/zs:update-zskills` re-verifies the install and updates the
  recorded version.
- **`/update-zskills` (direct):** run `/update-zskills` anytime — it pulls the
  latest from the repo, updates changed skills, and fills any new gaps. If
  you have a config already, it will not re-prompt.

See [`docs/guides/installing-zskills.md`](docs/guides/installing-zskills.md) for the full
update workflow and version-pinning idiom.

### Your first plan

Once installed:

```
/draft-plan quiz Let's make an HTML game like Asteroids but with cooler effects.
/run-plan docs/plans/<generated-file>.md
```

`/draft-plan` drafts a plan with adversarial review and writes it to
`docs/plans/` (configurable via `output.plans_dir` in
`.claude/zskills-config.json`). `/run-plan` reads that plan and executes it phase by phase
inside an isolated worktree, verifying each phase with a fresh reviewer
and landing results via your configured landing mode.

## Landing modes

Three modes control how agent work reaches `main`. The columns below
reference three install-time knobs:

- **`execution.landing`** — which strategy `/run-plan` uses
  (cherry-pick, PR, or direct commit).
- **`execution.main_protected`** — when `true`, the project-level hook
  blocks agent commits, cherry-picks, and pushes on `main`.
- **`BLOCK_MAIN_PUSH`** — a one-line toggle in
  `.claude/hooks/block-unsafe-generic.sh` that blocks `git push main`
  at the generic layer. Belt-and-suspenders with `main_protected`.

| Preset | `execution.landing` | `execution.main_protected` | `BLOCK_MAIN_PUSH` | Use when |
|---|---|---|---|---|
| `cherry-pick` | `cherry-pick` | `false` | `0` | Solo dev, local main, no CI gate |
| `locked-main-pr` | `pr` | `true` | `1` | Shared repo, PR workflow, branch protection / CI required |
| `direct` (default) | `direct` | `false` | `0` | Prototypes, single-developer throwaway work |

- **cherry-pick** — Each phase runs in an auto-named worktree. When it
  passes verification, its squashed commit is cherry-picked to `main`
  in the main repo. Fast, linear history, no PRs. Default.
- **locked-main-pr** — Each plan gets a named feature branch in a
  worktree. When all phases pass, the branch is pushed, a PR is
  created, CI runs, and (if `ci.auto_fix=true`) the agent watches for
  CI failures and pushes fix commits until CI is green, then auto-merges.
  The hook blocks any agent attempt to push to `main` directly.
- **direct** — Work happens on `main` itself, no worktree isolation.
  Minimal overhead, no review gate. Don't pick this for anything
  important.

You can override the config default on a single invocation:

```
/run-plan docs/plans/X.md finish auto pr
/fix-issues 10 pr
/do Add dark mode. pr
```

## Config file

`.claude/zskills-config.json` is the single source of truth. Full schema
at [`config/zskills-config.schema.json`](config/zskills-config.schema.json).

```json
{
  "$schema": "./zskills-config.schema.json",
  "project_name": "my-app",
  "timezone": "America/New_York",
  "execution": {
    "landing": "cherry-pick",
    "main_protected": false,
    "branch_prefix": "feat/"
  },
  "testing": {
    "unit_cmd": "npm test",
    "full_cmd": "npm run test:all",
    "output_file": ".test-results.txt",
    "file_patterns": ["tests/**/*.test.js"]
  },
  "dev_server": {
    "cmd": "npm start",
    "main_repo_path": "/home/you/projects/my-app"
  },
  "ui": {
    "file_patterns": "src/(components|ui)/.*\\.tsx?$",
    "auth_bypass": "localStorage.setItem('token', 'test')"
  },
  "ci": {
    "auto_fix": true,
    "max_fix_attempts": 2
  },
  "agents": {
    "min_model": "auto"
  }
}
```

Key fields:

- **`execution.landing`** — `cherry-pick` | `pr` | `direct`. Preset-owned.
- **`execution.main_protected`** — When `true`, skills refuse to commit,
  cherry-pick, or push to `main`. Preset-owned.
- **`execution.branch_prefix`** — Prefix for agent-created feature
  branches (e.g. `feat/`).
- **`testing.unit_cmd` / `testing.full_cmd`** — Test commands. Read by
  `/verify-changes`, `/run-plan`, the pre-commit hook, and others.
- **`testing.output_file`** — Where test output gets captured. Never
  pipe test output; always capture to this file.
- **`dev_server.cmd` / `main_repo_path`** — Lets
  worktree agents find the running dev server in the main repo.
  `main_repo_path` must be the absolute path to your repo's root
  (substitute your own — the example above is illustrative).
- **`ui.file_patterns`** — Regex identifying UI files. When these
  change, the pre-commit hook requires manual browser verification.
- **`ui.auth_bypass`** — JavaScript executed during
  `/manual-testing` to bypass login.
- **`ci.auto_fix`** — In PR mode, whether the agent polls CI and
  attempts to fix failures.
- **`ci.max_fix_attempts`** — Cap on fix-and-push cycles (default 2).
- **`agents.min_model`** — Minimum model for subagent dispatch.
  `auto` = "inherit from this session's model." Enforced by the
  `block-agents.sh` hook.
- **`dashboard.work_on_plans_trigger`** — Optional relative path to a
  consumer-authored script the `/zskills-dashboard` server invokes
  when the UI's Run button is clicked. The selected `/work-on-plans`
  invocation is passed as argv[1]. No default script is shipped (this
  is plumbing the consumer wires). When absent or empty, the Run
  button is hidden and `/api/trigger` returns 501. Example:
  ```bash
  #!/bin/bash
  # scripts/work-on-plans-trigger.sh
  exec >>".zskills/work-on-plans-trigger.log" 2>&1
  echo "[$(date -Iseconds)] trigger: $1"
  mkdir -p .zskills/triggers
  printf '%s\n' "$1" > ".zskills/triggers/$(date -u +%Y%m%dT%H%M%SZ).cmd"
  ```

## Tracking scheme

Long-running pipelines (`/run-plan`, `/fix-issues`, `/research-and-go`)
declare what they're about to do and what they've finished via **tracking
markers** under `.zskills/tracking/`. Hooks consult these markers before
allowing `git commit`, `git cherry-pick`, and `git push`.

**Layout** (per-pipeline subdir, Option B):

```
.zskills/tracking/<PIPELINE_ID>/
  requires.<step>       # this step MUST run before commit
  fulfilled.<step>      # this step completed
  step.<phase>.<kind>   # intra-phase substep (implement / verify / ...)
  meta.*                # pipeline metadata
```

Per-pipeline subdirs let multiple `/run-plan` sessions run concurrently
on the same repo without marker collisions — **parallel pipelines are a
core use case**, not a nice-to-have.

See [`docs/tracking/TRACKING_NAMING.md`](docs/tracking/TRACKING_NAMING.md)
for the authoritative naming scheme, delegation semantics, and hook
enforcement rules.

Two other file types sit alongside tracking markers:

- **`.zskills/tracked`** (in each pipeline's worktree and the main repo) —
  a single-line file containing the active pipeline ID. The orchestrator
  writes it before dispatching work, removes it after the pipeline
  completes. Hooks use it to scope marker matching (they also still read
  the legacy root `.zskills-tracked` for worktrees created before the
  path consolidation).
- **`.zskills/landed`** (in the worktree) — a YAML-ish marker written by
  `/commit land` (via the script bundled in the `commit` skill) when a
  worktree's work has been cherry-picked (or merged) to main. `status: full`
  = safe to remove the worktree. `status: partial` / `not-landed` = inspect
  first. (Older worktrees may carry the legacy worktree-root `.landed`
  instead — readers check both, new path first.)

## Hook policies

Z Skills ships two PreToolUse hooks that block specific unsafe patterns:

### `block-unsafe-generic.sh` (project-independent)

- **Destructive git ops:** `git stash drop/clear`, `git checkout --`,
  `git restore`, `git clean -f`, `git reset --hard`.
- **Destructive FS ops with scope policy:** `rm -r/-rf`, `find -delete`,
  `rsync --delete`, `xargs rm -r`. The hook **permits** literal,
  contained `/tmp/<name>` paths (e.g. `rm -rf /tmp/zskills-tests/foo`)
  but **blocks** wide scope or variable expansion (`rm -rf "$DIR"`,
  `rm -rf ~`, anything with `*`/`?`/backticks/`$(...)`).
- **Process kills:** `kill -9`, `killall`, `pkill`, `fuser -k` — these
  can kill container-critical processes or other sessions' dev servers.
- **Discipline violations:** `git add .` / `git add -A`,
  `git commit --no-verify`.
- **Main-push block** (preset-controlled): when `BLOCK_MAIN_PUSH=1`
  (set by `locked-main-pr`), the hook blocks `git push` to `main` /
  `master`. Feature-branch pushes are always allowed.

### `block-unsafe-project.sh` (project-specific)

- **No-pipe-on-tests:** blocks piping test output
  (`<cmd> | tail`, `| grep`, etc.) — test runs must capture to
  `testing.output_file` so nothing is lost.
- **UI verification gate:** when changed files match
  `ui.file_patterns`, blocks commit until a recent browser verification
  marker exists.
- **Tracking enforcement:** blocks `git commit` / `git cherry-pick` /
  `git push` when a pipeline's `requires.*` markers haven't been
  fulfilled, or when a `step.*` chain is incomplete
  (implement-without-verify, verified-without-report).
- **`main_protected` access control:** when
  `execution.main_protected=true`, blocks agent commits, cherry-picks,
  and pushes on `main`.
- **Tracking directory protection:** blocks recursive deletion of
  `.zskills/tracking/`.
- **`clear-tracking.sh` exec block:** agents cannot run
  `.claude/skills/update-zskills/scripts/clear-tracking.sh` — only the user can clear tracking state
  (it's an escape hatch, not an agent routine).

Both hooks fail closed: when a rule fires, the agent sees a permission
denial and must take a different path, not route around it.

## Canary suite

The canary plans under [`docs/plans/CANARY*.md`](docs/plans) are real regression
scaffolds — each one is a plan that was executed end-to-end to validate
a specific behavior.

Runnable test scripts (always green):

- `tests/test-hooks.sh` — block-unsafe hook rules, preset toggle.
- `tests/test-canary-failures.sh` — fixtures that exercise known failure
  shapes (weakening tests, stubbing, skipping verification).
- `tests/test-tracking-integration.sh` — tracking marker enforcement
  end-to-end.
- `tests/test-scope-halt.sh` — scope violation halts pipeline.
- `tests/test-skill-invariants.sh` — structural invariants every
  SKILL.md must hold.
- `tests/e2e-parallel-pipelines.sh` (opt-in, `RUN_E2E=1`) — two concurrent
  `/run-plan` sessions on the same repo without marker collisions.

Manually-run canary plans (markdown plans under `docs/plans/`):

| Canary | What it validates |
|---|---|
| `CANARY1_HAPPY` | Happy-path single-phase runs |
| `CANARY8_PARALLEL` | Concurrent pipelines on one repo (multi-pipeline invariant) |
| `CANARY11_SCOPE_VIOLATION` (+ `CANARY11_TEST_PLAN`) | Verifier catches scope-flag violations |
| `CANARY_LAND_PR` | Unified `/land-pr` dispatch end-to-end |
| `REBASE_CONFLICT_CANARY` | Two-session rebase conflict resolution |

Historical canaries from `/run-plan` validation (April 2026) have been
archived to [`docs/plans/archive/canaries/`](docs/plans/archive/canaries/);
their behavior is now covered by the shell tests above.

### Run the full test suite

```bash
bash tests/run-all.sh                    # unit + integration, ~30s
RUN_E2E=1 bash tests/run-all.sh          # + e2e-parallel-pipelines
```

## Skill catalog

### 21 User-Facing Skills (`skills/`)

These work on any software project — web app, CLI tool, API service, game,
data pipeline. All are slash-invocable by the user. Two additional
helper skills (`/land-pr`, `/manual-testing`) are marked
`user-invocable: false` (hidden from the `/` menu) and dispatched internally
by other skills — see Helpers below.

#### Plan

| Skill | Purpose |
|-------|---------|
| `/research-and-plan` | Decompose broad goals into focused sub-plans with dependency ordering |
| `/draft-plan` | Adversarial plan drafting: research, draft, devil's advocate review, refine until converged. Optional `brainstorm` flag runs an interactive design dialogue first; optional `quiz` flag runs an interactive requirements interview first |
| `/refine-plan` | Refine in-progress plans: review remaining phases against completed work, generate Drift Log |
| `/draft-tests` | Append a `### Tests` subsection to each pending phase of an existing plan via a senior-QE reviewer + devil's-advocate + refiner loop |
| `/plans` | Plan dashboard: index, status tracking, priority ranking |
| `/work-on-plans` | Batch-execute prioritized ready queue from the dashboard |
| `/research-and-go` | Full autonomous pipeline: decompose, plan, execute — one command, walk away |

#### Build

| Skill | Purpose |
|-------|---------|
| `/run-plan` | Phase-by-phase plan execution with worktree isolation, verification gates, and auto-landing |
| `/do` | Everyday workhorse for ad-hoc work (docs, fixes, refactors, content); optional worktree/push/scheduling |

#### Quality

| Skill | Purpose |
|-------|---------|
| `/verify-changes` | 7-phase verification: diff review, test coverage audit, test run, manual UI check, fix, re-verify |
| `/qe-audit` | Quality audit of recent commits — find test gaps, edge cases, file issues |

#### Fix

| Skill | Purpose |
|-------|---------|
| `/fix-issues` | Batch bug-fixing sprints: prioritize N issues, dispatch parallel agents, verify, land |
| `/fix-report` | Interactive sprint review — walk through results, gate landing on user approval |
| `/investigate` | Root-cause debugging: reproduce, trace, prove the cause with evidence, regression test, fix |

#### Utility & Reference

| Skill | Purpose |
|-------|---------|
| `/zskills-dashboard` | Local web dashboard for plans/issues/worktrees/branches/tracking: `start` launches a detached Python server, `stop` SIGTERMs it, `status` reports uptime |
| `/session-report` | Audit what THIS session said it would do vs. what's actually shipped — verifies session-mentioned items against git/PRs/plans, not conversation memory |
| `/briefing` | Project status dashboard: recent commits, worktree status, pending sign-offs |
| `/commit` | Safe commit: scope classification, import tracing, fresh review agent, dependency verification |
| `/cleanup-merged` | Post-PR-merge normalization: fetch+prune, checkout main, pull, delete local feature branches whose PRs have merged |
| `/update-zskills` | Install or update Z Skills infrastructure in any project |
| `/create-worktree` | Unified worktree creation. Primarily dispatched internally by `/run-plan`, `/fix-issues`, `/do` (which pass `--pipeline-id` verbatim — the script rejects invocations without the flag, rc 5); invocable directly but rarely needed. |

#### Helpers (`user-invocable: false` — hidden from the `/` menu, dispatched by other skills)

| Skill | Purpose |
|-------|---------|
| `/land-pr` | PR landing helper — rebase, push, create-or-detect PR, poll CI, optional auto-merge. Dispatched by `/run-plan`, `/commit pr`, `/do pr`, and `/fix-issues`. `user-invocable: false` hides it from the `/` menu. |
| `/manual-testing` | Playwright-cli UI-verification recipes (real mouse/keyboard events). `user-invocable: false`; dispatched by `/verify-changes`. |

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
8. **Always write the `.zskills/landed` marker** — so worktrees can be safely cleaned up
9. **Verify worktrees before removing** — never batch-remove
10. **Never defer hard parts** — finish the plan, don't stop after the easy phase
11. **Correctness over speed** — follow instructions exactly, never stub
12. **Enumerate before guessing** — ls/grep first, build from scratch second
13. **Never skip pre-commit hooks** — fix the issue, don't bypass with --no-verify

### Helper Scripts

- `test-all.sh` — failing-stub by default; consumer fills with their test orchestrator.
- `stop-dev.sh` — failing-stub by default; consumer fills with their dev-server stop logic.
- `start-dev.sh` — failing-stub by default; consumer fills with their dev-server start command (writes child PIDs to `.zskills/dev-server.pid`).

Skill machinery scripts moved into their owning skills under `.claude/skills/<owner>/scripts/` — see the `update-zskills` skill's `references/script-ownership.md` for the full table.

### Session Logging

Hooks that convert Claude Code JSONL transcripts to readable markdown
after every session and subagent run. Logs go to `.claude/logs/`.
Session logging is provided by a separate package:
[cc-session-logger](https://github.com/zeveck/cc-session-logger).

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

## License

MIT
