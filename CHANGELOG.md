# Changelog

## 2026-05-02

### Added — per-skill versioning

Every source skill under `skills/` and `block-diagram/` now carries
`metadata.version: "YYYY.MM.DD+HHHHHH"` in its SKILL.md frontmatter,
seeded to today's date and each skill's content hash. Edits to a
skill body must bump this field; see `references/skill-versioning.md`
and CLAUDE.md "Skill versioning" rule. Enforcement lands in subsequent
commits (Phase 4).

## 2026-05-01

### Added — `/land-pr` skill (PR_LANDING_UNIFICATION complete)

`/land-pr` extracts the PR-landing pipeline (rebase → push → create →
CI poll → fix-cycle → auto-merge) from 5 duplicating skills into one
canonical implementation. Callers — `/run-plan`, `/commit pr`, `/do
pr`, `/fix-issues pr`, `/quickfix` — now dispatch `/land-pr` via the
Skill tool with a file-based result contract instead of each carrying
inline copies of `gh pr create` / `gh pr checks --watch` / `gh pr
merge`. Eliminates 5x duplication and the drift bugs (`87af82a`,
`1de3049`, `175e4aa`, `b904cef`) it caused.

The skill ships 4 scripts under `skills/land-pr/scripts/`:
`pr-rebase.sh`, `pr-push-and-create.sh`, `pr-monitor.sh`, `pr-merge.sh`.
A canonical caller-loop pattern lives at
`skills/land-pr/references/caller-loop-pattern.md` (allow-list parser,
never `source`-the-result-file). Subagent boundary contract: callers
dispatch `/land-pr` at orchestrator level only — never inside an
Agent-dispatched subagent.

Phase 6 adds drift-prevention infrastructure:

- **8 cross-skill conformance tripwires** in
  `tests/test-skill-conformance.sh` (start-of-line-anchored grep
  patterns for `gh pr create` / `gh pr checks --watch` / `gh pr
  merge` outside `/land-pr`, plus a 5-caller dispatch presence check
  and an orchestrator-level dispatch heuristic). Static drift
  prevention; complements the per-skill `check_not` assertions added
  in Phases 2–5.

- **`plans/CANARY_LAND_PR.md`** — manual end-to-end canary that
  exercises the unified flow with a deliberate skill-mirror drift on
  attempt 1, forcing one fix-cycle iteration before CI passes on
  attempt 2 and auto-merge fires. Behavioral validation layer.

PRs that landed each phase:

- 1A — `/land-pr` skill foundation: PR #159
- 1B — validation layer (failure-modes + mocks + tests + conformance): PR #160
- 2 — `/run-plan` caller migration: PR #161
- 3 — `/commit pr` + `/do pr` caller migration: PR #162
- 4 — `/fix-issues pr` caller migration: PR #163
- 5 — `/quickfix` caller migration: PR #164
- 6 — drift-prevention conformance + canary: this PR

Plan: `plans/PR_LANDING_UNIFICATION.md` (now Complete in PLAN_INDEX).

## 2026-04-29

### Added — `/zskills-dashboard` skill

`/zskills-dashboard [start|stop|status]` exposes the Phase 5 monitor
server as a first-class skill. `start` launches the server detached
(`nohup … & disown`) so it survives the parent shell, writes
`.zskills/dashboard-server.pid` (`.env`-style: `pid=…`, `port=…`,
`started_at=…`), and verifies via `/api/health`. `stop` sends SIGTERM
only (never `kill -9`), polls for exit up to 5s, and verifies the port
is released. `status` reads the PID file, runs `kill -0`, and prints
URL/PID/uptime/log path.

Both `start` and `stop` use a **two-factor process-identity check**
(command name match `python3.*zskills_monitor.server` AND cwd match
`MAIN_ROOT` via `/proc/$PID/cwd` with `lsof -p $PID -d cwd` fallback)
so stale or PID-reused entries — and PIDs belonging to a different
worktree's monitor — never get killed by accident. State-changing
modes write a `fulfilled.zskills-dashboard.<id>` tracking marker; the
read-only `status` does not.

New config field: `dashboard.work_on_plans_trigger` (string,
optional) — relative path to a consumer-authored trigger script. When
set, the dashboard "Run" button posts to `/api/trigger` and the server
spawns the script with the selected `/work-on-plans` command as
argv[1]. **No default script is shipped** — this is plumbing the
consumer wires. When absent, the Run button is hidden and
`/api/trigger` returns 501.

Example consumer trigger script:

```bash
#!/bin/bash
# scripts/work-on-plans-trigger.sh
exec >>".zskills/work-on-plans-trigger.log" 2>&1
echo "[$(date -Iseconds)] trigger: $1"
mkdir -p .zskills/triggers
printf '%s\n' "$1" > ".zskills/triggers/$(date -u +%Y%m%dT%H%M%SZ).cmd"
```

`.zskills/dashboard-server.log` added to `.gitignore`.

## 2026-04-28

### Migration — /plans work removed

The `/plans work`, `/plans stop`, and `/plans next-run` modes are
retired. Batch execution of ready plans now lives in the dedicated
`/work-on-plans` skill (shipped earlier in this dashboard cycle).
`/plans` keeps only the read-only index-maintenance modes: bare,
`rebuild`, `next`, `details`. Affected files: `skills/plans/SKILL.md`,
`README.md`, `PRESENTATION.html` (cron-scheduling example row),
`CHANGELOG.md`.

Migrate `/plans work N [auto] [every SCHEDULE]` invocations to
`/work-on-plans N [auto] [every SCHEDULE]`. The argument shape is
preserved.

**Cron-cleanup scope.** `CronList` and `CronDelete` are session-scoped
(see `project_scheduling_primitives`). Cleanup of old `/plans work …
every SCHEDULE` crons run from this phase only sees the running
session's cron table — it cannot reach crons registered in your main
session, other sprints, or worktree sessions you've left open. If you
ever ran `/plans work … every SCHEDULE` in another session, you must
run `CronList` + manual `CronDelete` from each affected session OR
wait for those sessions to terminate (in-session crons die with the
session, so any session you've already closed needs no cleanup).

### Added
- feat(stubs): formalize consumer stub-callout convention; add post-create-worktree.sh, dev-port.sh, start-dev.sh stubs; convert stop-dev.sh, test-all.sh to failing stubs. Existing consumers: your old stop-dev.sh / test-all.sh stay (skip-if-exists); to adopt the new start-dev.sh / stop-dev.sh pairing (start-dev writes var/dev.pid; stop-dev reads it), `rm scripts/start-dev.sh scripts/stop-dev.sh && /update-zskills` for the new templates, then customize.
- refactor(scripts): move Tier-1 scripts into owning skills; /update-zskills migrates stale copies
  — 14 skill-machinery scripts relocated from `scripts/` into
  `.claude/skills/<owner>/scripts/<name>`. Cross-skill callers updated
  to invoke via `$CLAUDE_PROJECT_DIR/.claude/skills/<owner>/scripts/<name>`.
  `/update-zskills` now ships scripts via the skill mirror only and
  detects leftover Tier-1 copies in consumer `scripts/`: exact-hash
  matches against `tier1-shipped-hashes.txt` are removed automatically;
  user-modified copies are flagged and tracked via
  `.zskills/tier1-migration-deferred`. Tier-2 release/consumer-facing
  scripts (e.g. `build-prod.sh`) remain at top-level `scripts/`. See
  `RELEASING.md` Migration section and
  `plans/SCRIPTS_INTO_SKILLS_PLAN.md`.
- feat(config): drop dev_server.port_script (port.sh now lives in update-zskills skill); add dev_server.default_port for main-repo port override
  — `port.sh` is now bundled with the `update-zskills` skill at one
  canonical location; the `port_script` config field that pointed at
  it is removed. `dev_server.default_port` (integer, default 8080)
  added so the main-repo port is configurable. `/update-zskills`
  writes `default_port` on greenfield install. Existing configs
  without the field will receive a fail-loud diagnostic from port.sh
  (run `/update-zskills` to add the field manually for now; automatic
  backfill is tracked as future work).
- feat(run-plan): add `PLAN-TEXT-DRIFT:` structured token for
  acceptance-band drift flags; see `skills/run-plan/SKILL.md` Key Rules
  and `scripts/plan-drift-correct.sh`. Implementation and verification
  agents emit one token per stale numeric acceptance criterion;
  `scripts/plan-drift-correct.sh` provides `--parse` / `--drift` /
  `--correct` modes consumed by `/run-plan` Phase 3.5
  (`plans/IMPROVE_STALENESS_DETECTION.md`).
- feat(run-plan): Phase 3.5 post-implement auto-correct + Phase 1
  pre-dispatch arithmetic staleness gate landed. See
  `plans/IMPROVE_STALENESS_DETECTION.md` for design.

## 2026-04-21

### Major
- `/create-worktree` skill + `scripts/create-worktree.sh` — unifies the five
  worktree-creation sites across `/run-plan` (cherry-pick + PR modes),
  `/fix-issues` (PR mode), and `/do` (PR + worktree modes) behind one
  well-tested script. Owns prefix-derived path, optional `--branch-name`
  override, optional pre-flight prune+fetch+ff-merge, `worktree-add-safe.sh`
  call with TOCTOU-race remap, sanitised `.zskills-tracked` write, and
  `.worktreepurpose` write. `--pipeline-id <id>` is required — silent
  env-var fallback removed (caught latent bug where callers' canonical
  pipeline IDs weren't reaching tracking).
- `/quickfix` skill — low-ceremony PR from main without a worktree. Auto-
  detects user-edited mode (dirty tree + description → carry edits to a
  branch and commit) vs agent-dispatched mode (clean tree + description →
  model dispatches an agent to implement, then commits). PR-only; requires
  `execution.landing == "pr"`. Runs the project's unit tests before commit
  to satisfy the pre-commit hook. Fire-and-forget: commit, push, open PR,
  print URL, exit.
- `/cleanup-merged` skill — post-PR-merge local normalization. Fetches
  origin with `--prune`, switches off a feature branch whose PR has merged
  (or whose upstream is gone), pulls the main branch, and deletes local
  feature branches whose upstreams were removed or whose PRs were merged.
  Bails on a dirty tree; skips branches with unpushed commits; `--dry-run`
  previews without modifying. Closes the async cleanup gap that PR-mode
  flows inherit from git's design.
- `/do`: honors `execution.landing` in zskills-config (same pattern as
  `/run-plan` and `/fix-issues`). `LANDING_MODE` now resolves via explicit
  flag (`pr`/`direct`/`worktree`) → config → fallback `direct`. Config
  `cherry-pick` maps to worktree-mode.

### Minor
- Hook `block-unsafe-generic.sh`: redacts heredoc bodies and
  `git commit -m|--message` / `gh pr|issue create|comment --body|--title`
  arg values before destructive-op scans. Stops false-positives on prose
  that mentions banned patterns (commit messages, PR bodies).
- Hook `block-unsafe-project.sh`: same data-region redaction lifted in for
  parity with the generic hook. Tracking-dir deletion rule anchors `-r`/
  `-R`/`--recursive` as a flag token scoped to the single command, so
  plain `rm -f` or multi-command lines mentioning `.zskills/tracking` in a
  neighboring context no longer false-positive.
- Hook `git checkout --` rule: anchors `--` as the file-separator token,
  tolerating intermediate args like `HEAD~1` while continuing to reject
  long flags (`--quiet`, `--force`, etc.).
- `scripts/create-worktree.sh` `--no-preflight`: when `--from` is not
  passed, BASE now defaults to the main-repo's current branch (was:
  hardcoded `main`). Restores `/do` worktree-mode's pre-migration base-
  branch semantic.
- `scripts/clear-tracking.sh`: recurses into per-pipeline subdirs; runs
  post-clear residual assertion.
- `/run-plan`, `/verify-changes`: resolve `testing.full_cmd` from config
  via three-case decision tree (config → use; test-infra-exists → fail;
  no-infra → skipped + explicit report note). No more hardcoded
  `npm run test:all`.

## 2026-03-29

### Major
- `/research-and-plan`: mechanical verification gate ensures `/draft-plan` is
  actually used — 3 layers: explicit prohibition, grep for Plan Quality section,
  verification agent audit. Past failure: agents skipped `/draft-plan` 3 times,
  producing plans with 10+ CRITICAL issues each time.
- `/research-and-plan`: max 3 concurrent `/draft-plan` agents with
  dependency-ordered batching. Prevents container overload.
- `/update-zskills` (renamed from `/setup-zskills`): auto-clone from GitHub when portable assets not found
  locally. Auto-detect project settings (test commands, dev server, project
  name) from package.json, Cargo.toml, Makefile, CI configs — no blocking
  prompts. Sensible defaults for new/early-stage projects.
- Report format across `/run-plan`, `/verify-changes`, `/fix-report`: single
  checkbox per item with verification instructions underneath. Replaces the
  dual table + detail card pattern that caused double-counting in viewers.
- `/run-plan`: newest phases prepended at top of reports (not appended at
  bottom). The reader's question is always "what needs my attention?" —
  that's the newest phase.
- `/briefing verify`: sign-off dashboard with viewer URLs, not ASCII checkbox
  replicas. Groups by report with section summaries. Worktrees needing
  verification flagged as unusual (suggests incomplete skill run).

### Minor
- `/research-and-plan`: `auto` flag skips decomposition confirmation checkpoint
- `/research-and-go`: explicitly passes `auto` to `/research-and-plan`
- `/fix-issues`: orchestrator may bundle related issues (same component, same
  root cause) into one worktree beyond N count.
- `/fix-issues`: Phase 1 enforcement — complete ALL sync steps before Phase 2
- `/briefing`: Z Skills update check in summary/report modes
- `/briefing`: "present verbatim" enforcement with past-failure reference
- `/draft-plan`: skip user research checkpoint when running as subagent
- `/update-zskills`: no AskUserQuestion — ask naturally in conversation
- `/run-plan`: phase-prefixed IDs (P4b-1 not #1) to avoid collisions
- `/run-plan`: one item per verifiable thing, avoid literal `[ ]` in
  description text (renders as phantom checkbox in viewers)

## 2026-03-27

Initial public release. 20 skills (17 core + 3 block-diagram add-on),
13 CLAUDE.md guardrail rules, safety hooks, session logging, helper scripts.
