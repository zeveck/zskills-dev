# Changelog

## 2026-05-07

### Changed — hooks/_lib/git-tokenwalk.sh: chain wrappers added to source-of-truth + drift gate extended (4→7 asserts)

Follow-up to BLOCK_UNSAFE_HARDENING `/verify-changes` finding F2. The two emergent segment-walking wrappers introduced during Phase 3 + Phase 4 (`is_git_subcommand_in_chain` and `is_destruct_command_in_chain`) lived in the hook source files only — byte-identical between the project and generic hooks but not covered by the D7 drift gate. Future divergence between the two project/generic copies of `is_git_subcommand_in_chain` would have been undetected.

Moves both wrappers into `hooks/_lib/git-tokenwalk.sh` (canonical source-of-truth alongside `is_git_subcommand` and `is_destruct_command`). The wrapper bodies inlined into `hooks/block-unsafe-project.sh.template` and `hooks/block-unsafe-generic.sh` are now byte-identical to the source-of-truth; the explanatory headers above each wrapper in the hooks are replaced with the canonical "Inlined from hooks/_lib/git-tokenwalk.sh" one-liner.

Extends `tests/test-hook-helper-drift.sh` from 4 to 7 byte-identity assertions covering the full hook-helper coverage matrix:

| Hook | is_git_subcommand | is_destruct_command | is_git_subcommand_in_chain | is_destruct_command_in_chain |
|---|:---:|:---:|:---:|:---:|
| block-unsafe-project.sh.template | ✓ | — | ✓ | — |
| block-unsafe-generic.sh | ✓ | ✓ | ✓ | ✓ |
| block-stale-skill-version.sh | ✓ | — | — | — |

No behavior change — same wrapper bodies in the same hooks; test surface +3 cases (drift gate goes from 4 to 7 PASS). Mirrors to `.claude/hooks/` byte-equal.

## 2026-05-06

### Added — block-stale-skill-version PreToolUse hook (#193)

Add `hooks/block-stale-skill-version.sh`: PreToolUse Bash hook denying `git commit` when staged skill files have a stale `metadata.version` hash. Wraps `scripts/skill-version-stage-check.sh` and emits a JSON deny envelope (pure-bash escape — no `jq`, no Python). Wired in zskills `.claude/settings.json` and shipped to consumers via `/update-zskills` (canonical extension table extended; 4 helper scripts — `skill-version-stage-check.sh`, `skill-content-hash.sh`, `frontmatter-get.sh`, `frontmatter-set.sh` — now copied via the new shared `scripts/install-helpers-into.sh` driver invoked from `/update-zskills` Step D). Closes the lock-step gap: bare `git commit` (bypassing `/commit`) is now blocked locally; CI's `test-skill-conformance.sh` is no longer the only mechanical safety net. Decisions: flat hook (no `.template`); commit-only gating (push gating dropped per F2 design analysis); `/commit` Phase 5 step 2.5 retained for defense-in-depth; tokenize-then-walk `git commit` matcher (regex form was empirically bypassable per Round-2 N1). Block-unsafe-project.sh:404 over-match follow-up: see `plans/BLOCK_UNSAFE_HARDENING.md` (drafted 2026-05-06, PR #192) — recommend `/run-plan plans/BLOCK_UNSAFE_HARDENING.md finish auto` after this PR lands. See `references/skill-version-pretooluse-hook.md`. Closes lock-step gap from PR #175 (skill-versioning).

### Added — Hooks: tokenize-then-walk source-of-truth + class-pinned matrices (BLOCK_UNSAFE_HARDENING)

- **Added — `hooks/_lib/git-tokenwalk.sh`** — source-of-truth file holding `is_git_subcommand` and `is_destruct_command` (tokenize-then-walk classification helpers). Inlined byte-identical into `hooks/block-unsafe-project.sh.template` (6 call sites: lines 489, 496, 625, 631, 701, 804) and `hooks/block-unsafe-generic.sh` (7 git-verb call sites — round-2 reinstated checkout per DA2-H-1: checkout, restore, clean, reset, add, commit-no-verify, push; plus 4 destructive-verb call sites: kill bare-flag, kill `-s` positional-pair, killall, pkill).
- **Closes the over-match patch trail** of Issues #58/#73, #81/#87 by killing the bug CLASS (regex-based whole-buffer scan) at the migrated subset, not the specific shape. The class-pinned acceptance matrices (144 project-hook + 192 generic-hook negative cases over the migrated verbs) catch future incidents in NEW shapes that prior shape-pinned tests missed. **Class is partially open for the unmigrated subset** (next bullet).
- **Removed — bare-substring `[[ "$COMMAND" =~ git[[:space:]]+verb ]]` patterns** at the migrated sites (replaced by `is_git_subcommand "$COMMAND" verb`). NOT removed at line 56 (project) / line 82 (generic) redaction sed (D3 — load-bearing). **Round-2 line-246 boundary narrowing (intentional):** the migrated `git add` regex's `\.` boundary alternatives `[[:space:]]|$` drop the original's `\"` (close-quote) and `\|` (pipe) cases. So `git add .|cat` (pipe-glued, no space) currently TRIPS the bare regex but does NOT trip the migrated regex. Pathological form; no positive regression test exists in `tests/test-hooks.sh`. Documented for forensics.
- **Documented tradeoff (DA-C-2):** lines 146 (`fuser -k`), 217 (`RM_RECURSIVE`), 225 (`find -delete`), 232 (`rsync --delete`), 239 (`xargs ... rm`) in `block-unsafe-generic.sh` REMAIN bare-substring whole-buffer regex. First-token-anchoring would silently weaken coverage of pipeline-fed destruction (`cat foo | xargs rm`, `pgrep | xargs kill`) and combined-flag forms (`fuser -mk`) — both canonical anti-patterns. Future hardening of THESE sites needs a segment-aware tokenizer that handles pipe semantics; out of scope for this plan.
- **Documented carve-outs (round-2 D5 expansion):** the helpers are quote-blind (`read -ra` is whitespace-only; flag-discriminator inside quoted args still trips), space-elided shell-control bypasses segment-truncation (`git clean foo;rm -f bar` → `-f` leaks from post-`;` `rm`), `env -i`/`sudo`/`doas`/`su` prefixes bypass first-token-anchoring, and multi-line commands are read up to first newline only. Each is a NEGATIVE assertion in the unit test surface (XCC30-34, XKL11-12) so a future close-the-carve-out pass MUST update the named tests.
- **Pre-existing carve-out (round-2 DA2-O-2 — not introduced by this plan):** PUSH_ARGS extraction at `block-unsafe-generic.sh:270-280` and the parallel block in project hook iterate over `$COMMAND` (segment-blind), not `$GIT_SUB_REST`. For `git push && rm -rf foo`, PUSH_ARGS may include tokens from the post-`&&` segment. Future refactor should change PUSH_ARGS to iterate `$GIT_SUB_REST`; out of scope for this plan (the bare gate was the over-match site addressed here; PUSH_ARGS is a separate inner-loop refactor).
- **Test surface — class-pinned matrices** of 144 + 192 negative cases (migrated subset) plus 4 traced reproducer cases (R1, R2, R4, R5; R3 untraced and not promoted to AC) in `tests/test-hooks.sh`. NEW `tests/test-hook-helper-drift.sh` per D7 enforces inlined-helper byte-equality at CI time.
- **`hooks/_lib/` install boundary (round-2 R2-L-2 / DA2-M-1 — Phase 2.6):** added a one-line comment to `skills/update-zskills/SKILL.md` Step C to document that `hooks/_lib/git-tokenwalk.sh` is the source-of-truth for inlined helpers and MUST NOT be added to the per-name install loop. Skill `metadata.version` bumped accordingly.
- **Coordination with Plan B** (`SKILL_VERSION_PRETOOLUSE_HOOK.md`) per D6: this plan owns `hooks/_lib/git-tokenwalk.sh` as the source-of-truth. Phase 6 of this plan is the canonical consolidation path (round-2 DA2-C-2: round-1's "/refine-plan it before" branch was aspirational and has been demoted to optional orchestrator action). The drift gate in `tests/test-hook-helper-drift.sh` enforces single-version semantics across all consumers.
- **Emergent — `is_destruct_command_in_chain` wrapper inlined in `hooks/block-unsafe-generic.sh`.** Pre-existing chain tests (`tests/test-hooks.sh:165-167`) exercise `cmd && kill -9 …` forms that first-token-anchored `is_destruct_command` would not match; mirrors `is_git_subcommand_in_chain` from Phase 3.
- **Emergent — `is_git_subcommand_in_chain` wrapper inlined in BOTH project + generic hooks.** Phase 2's source-of-truth helper is first-token-anchored (correct for its unit-test surface); cd-chain semantics (`cd /tmp/wt && git commit`) require segment-walking that is a hook-level concern. Wrapper splits on `&&`/`||`/`;`/`|`/real-newline/JSON-escaped `\n` and applies the helper per segment.
- **Emergent fix — `expect_project_deny`/`expect_project_allow` JSON envelope shape:** command field moved to LAST position so the hook's greedy sed extraction does not bleed `transcript_path` into the extracted COMMAND. Mirrors the existing `run_main_protected_test` pattern and rationale.
- **Emergent fix — `git clean` regex extended from `-[a-zA-Z]*f` to `-[a-zA-Z]*f[a-zA-Z]*`** to preserve `git clean -fd`/`-df`/`-fdq` coverage from existing tests.

## 2026-05-03

### Added — Verifier subagent — D'' structural defense

Replaced the prose-only `run_in_background: true` warning (PR #148) with a Claude Code custom-subagent definition at `.claude/agents/verifier.md` plus two new hook scripts. **Layer 0 (root-cause fix):** `hooks/inject-bash-timeout.sh` is a frontmatter PreToolUse hook on Bash that auto-extends every Bash call's `timeout` to 600000 ms (10 min) via the `updatedInput` envelope field — the 120s default that triggered the bg+Monitor recovery reflex no longer applies to verifier dispatches. **Layer 3 (universal failure-protocol primitive):** `hooks/verify-response-validate.sh` is a script that any verifier-dispatching skill pipes the verifier's response through (7-phrase stalled-string whitelist anchored to last 10 lines + 200-byte minimum-length signal). Five dispatch sites migrated to explicit `subagent_type: "verifier"` parameters AND the Layer 3 invocation: `/run-plan` Phase 3, `/commit` Phase 5 step 3, `/fix-issues` per-issue verification, `/do` Phase 3 (code + content paths), `/verify-changes` self-dispatch. `/update-zskills` Step C extended to install `.claude/agents/verifier.md` and the two hook scripts. CLAUDE.md gains "Verifier-cannot-run is a verification FAIL" rule. Closes #176, #180.

## 2026-05-02

### Added — `/update-zskills` UI surface for per-skill + repo-level version delta (Phase 5b)

Phase 5b of plans/SKILL_VERSIONING.md wires the Phase 5a data plumbing
into `skills/update-zskills/SKILL.md`'s three user-facing reports.
**Site A** (audit gap report): appends a `Versions: zskills <inst>→<cur>;
<N> skills changed` summary after the `Overall: ...` line, reading
installed `zskills_version` via inline `BASH_REMATCH` on
`.claude/zskills-config.json` (NOT `frontmatter-get.sh` — that helper
is YAML-only) and the source clone's latest tag via
`resolve-repo-version.sh`. **Site B** (install final report): adds a
`Repo version:` line and a `Per-skill versions:` block listing each
skill's `metadata.version` with `(new)` status; addon rows hidden by
default, shown with `--with-block-diagram-addons`. **Site C** (update
final report): replaces the single-line `Updated: N skills (list)`
with a structured table — `Repo version: <old> → <new>`, then
per-skill rows showing `<old> → <new>` for bumped skills and
`<ver> (unchanged)` for the rest, plus a `New:` section. **Step F.5 /
Pull Latest 5.7**: new mirror-the-tag-into-config step writes the
source clone's latest tag into `.claude/zskills-config.json` as
`zskills_version` via `json-set-string-field.sh` after install/update
completes — surfacing the consumer-side version on subsequent audits.
`--rerender` mode is unchanged and verified version-data-free by
CONTRAST assertion in the new test (rerender silent /
install+update populated). Tests:
`tests/test-update-zskills-version-surface.sh` (23 cases) covers all
three sites end-to-end against fixture state, the rerender CONTRAST,
and the `json-set-string-field` round-trip; registered in
`tests/run-all.sh`.

### Added — `/update-zskills` data plumbing for per-skill + repo-level version delta (Phase 5a)

Phase 5a of plans/SKILL_VERSIONING.md ships the plumbing layer for
version-data UI. `zskills-resolve-config.sh` resolves a 7th var
`ZSKILLS_VERSION` from a top-level `zskills_version` field in
`.claude/zskills-config.json`. Two new helper scripts under
`skills/update-zskills/scripts/`: `resolve-repo-version.sh` (extracts the
latest `YYYY.MM.N` tag from the zskills source clone) and
`skill-version-delta.sh` (iterates BOTH `skills/*/` and
`block-diagram/*/`, emits tab-delimited `<name> <kind> <src> <inst>
<status>` rows). A third helper, `json-set-string-field.sh`, performs
no-jq, no-sed JSON top-level string-field writes (awk-based,
metacharacter-clean). The `/briefing` "Z Skills Update Check" now reads
the installed version from the canonical config helper and compares it
against the source repo's latest tag, replacing the prior `git fetch
--dry-run` heuristic. Schema gains an optional top-level
`zskills_version` string field; existing `dashboard`/`commit`/
`execution`/`testing`/`dev_server`/`ui`/`ci` blocks unchanged. Phase 5b
will consume these helpers in `/update-zskills`'s SKILL.md UI sites.

### Added — skill-version enforcement (commit: 2026.05.02+fe9135)

Three-point gate on metadata.version: warn-config-drift hook
(Edit-time, fires only on staged files), /commit Phase 5 step 2.5
hard stop, test-skill-conformance.sh CI gate (now also validates
hash freshness).

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
