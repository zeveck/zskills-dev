---
title: General Claude→Codex porting capability — porting guide + repo-agnostic toolkit + first real port
created: 2026-07-07
status: in-progress
---

# Plan: General Claude→Codex porting capability

## Overview

zskills is Claude-Code-native: 23 skills, ~10k lines of hook bash, a cron-driven
autonomous execution engine, and a verifier/implementer subagent architecture, all
wired to Claude Code's harness primitives. This plan builds a **general porting
capability** — a porting guide (`docs/porting/`) plus a repo-agnostic toolkit
(`scripts/porting/`) — runnable at release time from **any zskills-descendant Claude
repo, including forks that have diverged in unknown ways**, producing a matched-version
Codex CLI distribution. It includes executing the **first real port** (to the private
repo `zeveck/zskills-codex-f`) as the guide's acceptance test.

Two prior attempts failed for known, opposite reasons and this plan is designed
against both post-mortems:

- **zskills-codex** (wrapper port, 2026-04): Codex loaded 41–133-line précis wrappers
  (91% of skill prose cut) with the full procedures archived behind "load only when
  the concise workflow below is insufficient" — an unresolvable self-assessment.
  Shallow following was structural. Its one reliably-working component, the external
  `zskills-runner.sh`, works precisely because it enforces from OUTSIDE the model.
- **zskills-cc** (single-source dual-compat, 2026-05): right architecture principle
  (upstream canonical, per-client generated output, Claude output byte-identical,
  divergence declared in a checksummed manifest), wrong transfer mechanism:
  context-anchored diff patches + exact-string Python surgery pinned to an upstream
  SHA. Two of three mutation mechanisms fail SILENTLY on upstream rewording; the pin
  went 840 commits stale; the repo went dormant in 5 days.

The synthesis this plan executes: **full skill bodies (never wrappers), transferred by
an agent with judgment following per-construct-class recipes (never string surgery),
enforced mechanically from outside the model (runner + fail-closed scanner + gate
scripts), verified honestly (curated ported-tree test runs + a real-Codex canary
matrix including failure-path canaries — the thing both prior forks skipped).**

What ships in the Claude repo: the guide (`docs/porting/**`), the toolkit
(`scripts/porting/**`), and their test suites — inert assets only. No skill edits, no
hook edits, no per-edit Codex tax on future Claude work. The ported tree itself is
out-of-repo output pushed to a separate target repo with a provenance manifest.

Teachable rule: **when a model must follow a procedure on a harness that cannot
mechanically enforce it, move the enforcement outside the model (runner, scanner,
gates) and put the full procedure in the text the model actually receives — précis and
patch-surgery both rot, in opposite directions.**

## Settled decisions (do not relitigate)

These are owner decisions from the 2026-07-07 design conversation. Adversarial review
pressure-tests the *implementation*, not these calls.

1. **Fork-generality is a day-one requirement.** Everything is discovery-driven and
   construct-class-based. Nothing enumerates today's file list, assumes 23 skills, or
   hardcodes repo names. The scanner discovers Claude-only constructs; the guide gives
   per-CLASS recipes; unknown instances of known classes port mechanically; unknown
   classes go to agent judgment and the ruling is APPENDED TO THE GUIDE
   (self-amending).
2. **The Claude repo stays clean.** No markers in skills, no Codex twins in source, no
   upstream CI gate, no per-edit tax — agents planning in the Claude repo never think
   about Codex. The Claude repo gains only inert assets: the guide (docs) + standalone
   toolkit scripts (+ their tests).
3. **Decisions accumulate in two layers:** general conventions in the guide (inherited
   by every fork); port-specific judgments in each PORTED repo (provenance manifest
   recording the ported-from Claude SHA + per-skill notes). Delta ports use a
   three-way diff (Claude@prior, Claude@now, Codex@prior) with **byte-verbatim
   carry-forward of unchanged skills**; only changed/new files get agent judgment. The
   agent-with-judgment transfer mechanism is what avoids zskills-cc's silent patch rot.
4. **Ported skills are FULL BODIES, never wrappers or précis.** No "when available…
   otherwise inline" escape hatches; degradations are explicit, named, and recorded in
   the degradation table — never left to the model's discretion at runtime.
5. **One scheduling story: the foreground runner IS the scheduler.** Two modes:
   (a) `finish auto` = loop-until-plan-done, one fresh `codex exec` child per phase,
   durable-evidence gates (plan/report content hashes + tracking-marker deltas)
   between chunks, output streamed to the attached terminal;
   (b) `every SCHEDULE` = sleep-loop firing `codex exec resume` children into ONE
   durable named session (full history readable via `codex resume`), streamed live;
   `stop`/`next` grammar preserved. NO Codex-app Automations (macOS/Windows app only),
   NO OS cron in v1 (a detached mode is a documented possible later add-on, not
   built). Never fire-and-forget invisible prompts — that pattern is the original sin
   this design exists to kill.
6. **Enforcement is mechanical, not prose.** Hooks port nearly directly (same
   envelope). The runner enforces chunk progress. The scanner fails the build closed.
   Where Claude had structural guarantees Codex lacks (tools allowlist,
   `user-invocable: false`), the degradation is documented, not papered over with
   instructions the model can skip.
7. **Verification is part of the product:** fail-closed scanner over ported output
   (zero surviving Claude-only constructs); ported-tree conformance checks; the
   harness-agnostic test suites run against the ported tree; a canary matrix on a REAL
   Codex install with honest per-skill coverage classification, INCLUDING failure-path
   canaries (an intentionally-failing phase must halt, not land).
8. **Salvage from the forks:** zskills-codex's `zskills-runner.sh` + fake-codex test
   harness + gate scripts + canary-matrix discipline; zskills-cc's
   quarantine/manifest/regenerate-and-diff verification discipline and its
   runtime-affordance/fallback-label taxonomy. Do not salvage: wrappers,
   context-anchored patches, string surgery, prose escape hatches, crontab management.
9. **First-port target repo exists:** private `zeveck/zskills-codex-f` (created
   2026-07-07). The guide itself must not hardcode this name (fork-generality); this
   PLAN may name it — and may enumerate today's skills in its slice tables — because
   the plan is a one-time execution artifact, not the reusable guide.
10. **Environment facts:** no Codex CLI in the dev container — the real-Codex probe
    (Phase 0) and real-Codex canaries (Phase 14) require the owner's machine and are
    explicitly owner-gated attended steps; all other phases run here. Local clones of
    both prior forks MAY be available for salvage reference at
    `/tmp/claude-1000/-workspaces-zskills/18f95c18-785a-43b1-afad-0407566c6f13/scratchpad/zskills-codex`
    and `…/scratchpad/zskills-cc`; the runner spec in this plan is complete enough to
    implement without them (see Phase 1 Design & Constraints).

## Design-history dispositions

Named REJECTED alternatives, so they are not re-proposed:

| Alternative | Disposition | Why |
|---|---|---|
| Wrapper/précis skill bodies with archived full text | **REJECTED** | zskills-codex post-mortem: the model executes the outline it receives; "load only when insufficient" is an unresolvable self-assessment. 91% prose cut ⇒ structurally guaranteed shallow following. |
| Context-anchored diff patches + exact-string surgery (generation pipeline pinned to upstream SHA) | **REJECTED** | zskills-cc post-mortem: two of three mutation mechanisms fail silently on upstream rewording; 840-commit-stale pin; re-anchoring 833 patch lines per release is a recurring porting project, not maintenance. |
| Codex-app Automations as the scheduling substrate | **REJECTED** | App-bound (macOS/Windows desktop app), adds a platform variant for a niche; the bare CLI — the actual port target — has no scheduler. |
| OS cron / crontab management in v1 | **REJECTED** | Fire-and-forget invisible prompts are the original-sin pattern (user sees nothing); zskills-cc's `zskills-scheduler.sh`/`zskills-run-due.sh` crontab machinery is explicitly not salvaged (except its ~30-line `parse_schedule`). A detached mode is a documented possible later add-on. |
| Codex as a third co-installable lane in ONE project | **REJECTED** | INSTALL_REDESIGN doctrine: "a consumer picks exactly ONE lane" was superseded-into-place twice; dual-install detection machinery was the most-deleted part of that redesign. Codex is a separate product tree in a separate repo. |
| Per-edit upstream CI gate (Codex-compat check on every zskills PR) | **REJECTED** | Violates settled decision 2 (Claude repo stays clean, no per-edit tax). Cadence is release-time only. |
| Continuous sync / one hand-maintained dual-harness skill body | **REJECTED** | zskills-cc's own Design Principle 1 rejects the mixed body; its post-mortem shows even the generated-dual-output variant rots. Release-time delta ports with three-way diff instead. |

## Reference — verified Codex CLI capability map (July 2026, probe-checked in Phase 0)

Condensed from research verified against official docs on 2026-07-07
(`developers.openai.com/codex/*`). Phase 0 re-verifies every load-bearing row
hands-on; **where probe results and this table disagree, probe results win** and the
guide's assumptions manifest records the observed behavior.

| Claude Code feature | Codex equivalent | Fidelity |
|---|---|---|
| SKILL.md skills | Native Agent Skills at `.agents/skills` (repo/parent/root), `~/.agents/skills`, `/etc/codex/skills`; `[[skills.config]]` extra paths (can point at `.claude/skills`); unknown frontmatter silently ignored | Exact-ish |
| Skill slash invocation | `$skillname` mention, `@` menu, `/skills` TUI; implicit auto-trigger by description | Partial |
| `disable-model-invocation: true` | per-skill `agents/openai.yaml` → `policy.allow_implicit_invocation: false` | Partial |
| `user-invocable: false` | **none** — documented degradation | None |
| CLAUDE.md / managed rules | AGENTS.md chain (root→cwd concat, **32 KiB default cap** via `project_doc_max_bytes`) AND/OR SessionStart hook `additionalContext` (exact analog of the plugin lane's `session-rules-context.sh`) | Exact-ish |
| PreToolUse deny envelope / exit-2+stderr / `updatedInput` / SessionStart `additionalContext` | Byte-for-byte the Claude contract; stdin carries `permission_mode`, `tool_name`, `tool_input` | **Exact** |
| hooks.json registration | `~/.codex/hooks.json`, `<repo>/.codex/hooks.json`, or `[hooks]` in config.toml; **non-managed hooks require explicit user trust-review before first run** | Partial (trust friction) |
| Agent tool / named subagents | Native subagents; project defs `.codex/agents/*.toml` (`name`, `description`, `developer_instructions`, `model`, `sandbox_mode`); `max_depth` default 1; NO per-agent frontmatter hooks, NO `tools:` allowlist enforcement | Partial-to-exact |
| CronCreate / scheduled tasks | **Nothing in the bare CLI** (app Automations rejected) → the foreground runner IS the scheduler | None (replaced) |
| `claude -p` headless | `codex exec` + `--json` JSONL (`thread.started` → thread_id, `turn.completed`) + `-o/--output-last-message` + `--output-schema` | Exact |
| Session continuity | `codex resume`, `codex exec resume <ID>/--last`, `codex fork` | Exact |
| Plugins / marketplace | `.codex-plugin/plugin.json`; marketplace reads **legacy `.claude-plugin/marketplace.json`**; hook scripts get `PLUGIN_ROOT` + **compat alias `CLAUDE_PLUGIN_ROOT`** | Exact-ish |
| Permission modes / bypassPermissions | `approval_policy` (`untrusted/on-request/never`) × `sandbox_mode` (`read-only/workspace-write/danger-full-access`); execpolicy `.rules`; `requirements.toml` admin-managed | Partial-different |

Real gaps the port designs around: no CLI cron; hook trust-review friction; no
`allowed-tools` enforcement; no `user-invocable: false` analog; AGENTS.md 32 KiB
default cap (`CLAUDE_TEMPLATE.md` is 44,935 bytes today — over the cap; see the
AGENTS.md dual-delivery recipe, Phases 3/4).

## Reference — the unified runner spec (Phase 1 implements this verbatim)

This section is the implementer's complete spec. The two prior-fork runners were read
in full; **base = the zskills-codex chassis** (1,080-line state machine: forensic
logging with per-chunk `argv.json`/`before-state`/`after-state`/`events.jsonl`/
`summary.json`, `--dry-run`, refusal preflight, documented exit-code taxonomy, and a
947-line/27-case test harness with a reusable 13-mode fake-codex) **plus fifteen named
changes**:

1. **STREAM** — adopt zskills-cc's pumper tee: every child stdout line is written to
   the parent terminal live AND to `chunk-NNN.stdout.txt` + `events.jsonl`. A running
   plan must never look hung from the invoking shell.
2. **STOP-IN-LOOP** — check the stop marker before EVERY chunk/fire (per-plan path
   `.zskills/runner/$plan_key.stop`); new exit reason `stopped` (31). Fixes the codex
   fork's write-only stop-marker bug (its `stop` subcommand wrote a marker the chunk
   loop never read).
3. **STRICT-SHELL** — `set -euo pipefail` from the top of the script (the codex fork
   ran all preflight without `-e`).
4. **STABLE-TRACKING-ID** — `TRACKING_ID=$(basename "$PLAN_FILE" .md | tr '[:upper:]_' '[:lower:]-')`
   (matches current `skills/run-plan/SKILL.md` ≈L504 — verify by content), pinned in
   the prompt AND exported as `ZSKILLS_PIPELINE_ID`/`ZSKILLS_TRACKING_ID` env to the
   child; `pipeline_id = run-plan.$TRACKING_ID` (sanitized via the same rules as
   `skills/create-worktree/scripts/sanitize-pipeline-id.sh`). Drop the codex fork's
   per-chunk timestamp ids and its "reuse the newest handoff suffix" child judgment.
   Because the id is stable, adopt cc's `marker_changed` content-hash staleness check:
   a chunk must re-touch every required marker with new content, so a pre-seeded stale
   complete-marker set cannot ride through. Keep `plan_key = <slug>-<short-hash of
   repo-relative path>` only for locks/logs (same-basename plan disambiguation).
5. **LANDING-POSITIONAL** — accept upstream grammar `run-plan <plan> finish auto
   [direct|cherry-pick|pr]`.
6. **PR-DUAL-ROOT** — cc's artifact-root/tracking-root split: plan/report are
   validated at the artifact root (PR worktree when it exists, else repo root);
   tracking always at the repo root. Stale-PR-root triage (path exists but not a
   worktree → die; worktree of a different repo → die; worktree missing the plan →
   die). Replace the codex fork's hardcoded `--add-dir /tmp` with `--add-dir
   <worktree-parent-dir>` derived from config.
7. **SANDBOX-TRIAGE** — cc's `explain_child_failure`: on child rc≠0, grep child output
   for `bwrap|bubblewrap|user namespace|Operation not permitted` and emit
   `runner_stop_reason=sandbox-unavailable` with explicit remediation ("rerun
   explicitly with: --sandbox danger-full-access …"); NEVER auto-escalate.
8. **CURRENT-FORMAT-VALIDATORS** — the forks validated April-2026 formats; validate
   CURRENT ones:
   - plan-complete: frontmatter `status: complete` FIRST (authoritative terminal
     signal); else tracker-format detection across the four current formats (structural
     `| Phase … |` table-row parse for `✅ Done`, checkbox count, numbered-section
     markers); **narrative-only plans with no tracker → refuse `finish auto`** with a
     documented message (never guess).
   - report: config-resolved path (`$ZSKILLS_REPORTS_DIR/plan-<slug>.md`, resolved the
     way `zskills-paths.sh` resolves it — project config > user > built-in default —
     NOT hardcoded `reports/`); sections are PREPENDED newest-first; required
     patterns are the current Phase-5 format: `^## Phase`, `\*\*Status:\*\*`,
     `### Verification`. Do NOT require a "Scope Assessment" section in the plan
     report (that lives in the verify-changes report; the fork gates validated a
     runner-invented contract).
   - verifier evidence: full set INCLUDING `step.verify-changes.<tid>.tests-run`
     (prompted-but-unvalidated in the codex fork) and tolerance of
     `step.verify-changes.<tid>.manual-verified` (UI phases).
   - final-verify pair at plan completion: `requires.verify-changes.final.<tid>` →
     `fulfilled.verify-changes.final.<tid>` (current Phase 5b gate; missing from both
     forks).
   - `.zskills/landed` consumption (new path first, legacy root `.landed` fallback —
     drop the fallback if #1146 lands first): `landed` → proceed/complete; `pr-ready`/
     `pr-ci-failing` → schedule re-entry; `conflict`/`pr-failed` → hard stop.
9. **PHASE-5C-CONTRACT** — `handoff.run-plan.<tid>` does not exist in current
   zskills; it is a fork invention worth keeping, but as a PORTED-SKILL contract, not
   just prompt text: the ported run-plan's rewritten Phase 5c natively writes
   `handoff.run-plan.$TID` (another phase remains) or the final markers (plan
   complete) where the Claude version calls CronCreate; the Claude version's
   idempotent Step-0 re-entry (next phase already Done/In Progress → exit cleanly) is
   preserved VERBATIM — it is what makes runner re-entry after interruption safe.
   This is a guide recipe (Phase 4) with the runner prompt keeping the contract block
   as reinforcement.
10. **CLAIMS** — the runner INLINES minimal claim semantics; it does NOT depend on a
    skill-bundled `claim-plan.sh` (that script moves per-lane and does not exist in a
    ported tree at Phase-1 time). Mechanism: atomic `mkdir` of
    `<main-root>/.zskills/claims/plan-<slug>/` + an atomically-written JSON metadata
    file storing the pipeline id — mirroring the SEMANTICS (not the code) of
    `skills/run-plan/scripts/claim-plan.sh`: acquire → rc 0 for fresh acquire OR
    ownership-aware self-re-entry (stored pipeline id matches the runner's); rc 10
    for foreign-held OR existing-claim-with-absent/malformed-metadata (never steal);
    release at terminal stop is idempotent and refuses on pipeline-id mismatch.
    Main root is resolved via `git rev-parse --git-common-dir` (never `$PWD`). Test
    fixture contract: the foreign-held refusal case pre-creates the claim dir with a
    metadata file naming a DIFFERENT pipeline id; the self-re-entry case pre-creates
    it with the runner's own id. Neither fork touched claims; without this the
    runner reintroduces the cross-session collision class the claim system prevents.
11. **EVERY-MODE** — `run-plan <plan> every <SCHEDULE> [auto]`: lift zskills-cc
    scheduler's ~30-line `parse_schedule` Python (`\d+[mhd]`, `every hour`,
    `weekday at H[:MM][am|pm]`); sleep-loop parent; FIRST fire = `codex exec --json …`
    capturing `thread_id` from the `thread.started` JSONL event, persisted to
    `.zskills/runner/$plan_key.session`; subsequent fires = `codex exec resume
    <SESSION_ID> --json "<per-fire prompt>"` into that ONE durable session. `stop` =
    per-plan stop marker honored by the sleep loop and before each fire; `next` =
    print next fire time + session id + last validation verdict. **Session-loss is a
    hard stop (exit 32, `session-lost`) — never a silent fallback to fresh `exec`**,
    which would invisibly break the one-durable-session contract. Validation between
    fires is IDENTICAL to finish-auto's (durable evidence is the only
    freshness-independent protection once contexts are resumed, not fresh).
    **`auto` semantics:** the optional `auto` token in every-mode carries the same
    meaning as finish-auto's positional `auto` — it pre-authorizes autonomous landing
    (the per-fire prompt instructs land-without-prompting); without it each fire's
    prompt instructs land-with-confirmation. It changes ONLY the per-fire prompt
    text, never the validation ladder.
12. **JSON+SCHEMA** — keep `--json` and `-o <last-message>` from the codex fork;
    parse `thread_id` + `turn.completed` usage into `summary.json`; optional
    `--output-schema` self-report (`{phase_executed, status, landing_status,
    tracking_id, remaining_phases}`) cross-checked against durable evidence —
    discrepancy = new failure class `claim-evidence-mismatch`. Claims never substitute
    for evidence; they add a lie-detection layer.
13. **GATE-UNIFY** — one `zskills-gate.sh`: the codex fork's four modes
    (`pre-land|post-land|pre-push|pre-continue`) + its `fix-issues.*` pipeline arm
    (cheap, future-proofs a `/fix-issues N` runner mode) + cc's tracking-root split,
    in-gate premature-final detection, and `tests-run` requirement + current report
    patterns/config-resolved path. Gates stay READ-ONLY (never mutate — surface, don't
    patch).
14. **INVARIANTS-REFORK** — re-fork `post-run-invariants.sh` from CURRENT upstream
    `skills/run-plan/scripts/post-run-invariants.sh` (235 lines — worktree-aware
    PROJECT_ROOT resolution, `.zskills/landed` dual-read) and re-apply the fork's
    `--base-branch/--remote/--report` parametrization. Do NOT carry the April fork
    copy (it greps the legacy `.landed` path only).
15. **CONFIG** — discovery order per the ported-tree layout decided in the guide
    (`.agents/zskills-config.json` → `zskills-config.json` → `.codex/…` → legacy
    `.claude/…`); keep cc's cross-lane conflict check (both present + disagree on
    `execution.landing`/`execution.main_protected` → die); minutes-based timeouts with
    the codex fork's realistic defaults (`chunk_timeout_minutes=90`,
    `idle_timeout_minutes=15` — NOT cc's test-tuned 900s/180s); keep
    `ZSKILLS_RUNNER_TIMEOUT_SECONDS`/`ZSKILLS_RUNNER_IDLE_TIMEOUT_SECONDS` test
    overrides. JSON via Python 3 heredoc (no jq — repo convention).

### Runner child-prompt contract (verbatim template; the fake-codex parses `- Label: value` lines, so keep the line format machine-parsable)

```
run-plan $REL_PLAN finish auto $LANDING

RUNNER-MANAGED CHUNK: You are running under zskills-runner.sh. Do not invoke
zskills-runner.sh again. Execute exactly one incomplete phase, then stop after
writing the required report, tracking markers, and landing evidence.

External ZSkills runner contract for this chunk:
- Repository root: $REPO_ROOT
- Active artifact root: $ARTIFACT_ROOT
- Plan path: $ACTIVE_PLAN_PATH
- Report path: $REPORT_PATH
- PR worktree path: $PR_WORKTREE_PATH
- Pipeline id: $PIPELINE_ID
- Tracking directory: $TRACKING_DIR
- Tracking id: use exactly $TRACKING_ID for every marker written by this chunk.
- Environment: ZSKILLS_PIPELINE_ID=$PIPELINE_ID and ZSKILLS_TRACKING_ID=$TRACKING_ID
  are exported to this child process.
- Resolved landing mode: $LANDING
- Base branch: $BASE_BRANCH
- Remote: $REMOTE
- Write run-plan markers: step.run-plan.<tid>.implement, step.run-plan.<tid>.verify,
  step.run-plan.<tid>.report.
- Write verifier markers: requires.verify-changes.<tid>,
  step.verify-changes.<tid>.tests-run, step.verify-changes.<tid>.complete,
  fulfilled.verify-changes.<tid>.
- If another phase remains: write handoff.run-plan.<tid>; do not write final
  run-plan markers.
- If the plan is complete: complete the final verify
  (requires.verify-changes.final.<tid> then fulfilled.verify-changes.final.<tid>),
  write step.run-plan.<tid>.land and fulfilled.run-plan.<tid>, and remove any stale
  handoff.run-plan.<tid>.
- Record landing state in .zskills/landed
  (status: landed|pr-ready|pr-ci-failing|conflict|pr-failed|partial|not-landed).
- The report must include a "## Phase" heading, a "**Status:**" line, and a
  "### Verification" section.
- Mark completed progress-tracker rows with exactly "✅ Done".
- Do not claim in the report that work was committed, cherry-picked, pushed, or
  landed until that git operation has actually succeeded.
- Leave no dirty project artifacts outside ignored .zskills state before exiting.
```

### Exit-code taxonomy (documented in `--help` and pinned by tests)

| Code | Meaning |
|---|---|
| 2 | refusal / preflight die (incl. dangerous-bypass flag, lock contention, git residue, narrative-plan refusal, claim foreign-held) |
| 20 | no durable progress detected |
| 21 | handoff marker missing after progress / premature final markers mid-plan |
| 22 | report invalid or missing / stale required marker (content hash unchanged) |
| 23 | tracking-id underivable / verifier marker evidence missing |
| 24 | gate script failed |
| 25 | dirty non-`.zskills` artifacts |
| 26 | child-failed (child nonzero exit — raw child rc + last stderr recorded in `chunk-NNN.summary.json`) |
| 30 | max-chunks exhausted |
| 31 | stopped (stop marker honored) |
| 32 | session-lost (`exec resume` failed — every-mode hard stop) |
| 124 | chunk wall timeout |
| 125 | chunk idle timeout |

Code 26 is a deliberate DEVIATION from both forks' raw-child-rc passthrough (adopted
in review round 1): a child that itself exits 2, 20–25, 31, or 124 must not
masquerade as a runner verdict, and machine consumers (the release procedure, a
future `/fix-issues` arm) branch on rc. The raw child rc and its last stderr lines
are forensics, recorded in `chunk-NNN.summary.json`. **`runner_stop_reason` in the
final chunk summary — echoed as the runner's last stderr line — is the AUTHORITATIVE
stop classification; exit codes are a convenience for shell callers.** Tests assert
the stderr reason line accompanies every mapped code.

### Per-chunk validation ladder (runs after every child, both modes)

A child nonzero exit short-circuits the ladder: run the sandbox-triage grep (change
7) for the stop-reason detail, record the raw child rc + last stderr in the summary,
exit 26. Otherwise:

1. Snapshot before/after: plan content hash, report content hash, sorted marker-name
   CSV, per-marker content-hash CSV.
2. Empty signal set (nothing durable changed) → rc 20.
3. Not-complete AND no new/changed `handoff.run-plan.<tid>` → rc 21. Not-complete AND
   `step.run-plan.<tid>.land` or `fulfilled.run-plan.<tid>` present → rc 21.
4. Report missing, or missing any current-format pattern → rc 22. Any REQUIRED marker
   whose content hash is unchanged vs the before-snapshot → rc 22 (`stale marker was
   not updated: <marker>`).
5. Verifier marker set incomplete (incl. `tests-run`) → rc 23.
6. `zskills-gate.sh --mode pre-continue` (non-final) / `post-land` (final) fails → rc 24.
7. Dirty non-`.zskills` artifacts → rc 25.
8. Final chunk only: final-verify pair present; `post-run-invariants` run;
   `.zskills/landed` read for PR terminal decisions (`conflict`/`pr-failed` → hard
   stop; `pr-ready` → re-entry).
9. Everything written into `chunk-NNN.summary.json` (`validation_result`,
   `validation_reason`, `validated_tracking_id`, `gate_result`, `progress_signals`,
   `runner_stop_reason`).

### Current tracking-marker vocabulary (what the validators key on)

Pipeline dir `.zskills/tracking/run-plan.$TRACKING_ID/` containing:
`step.run-plan.$TID.{implement,verify,report,land}`, `fulfilled.run-plan.$TID`,
`requires.verify-changes.$TID`, `fulfilled.verify-changes.$TID`,
`requires.verify-changes.final.$TID`, `fulfilled.verify-changes.final.$TID`,
`step.verify-changes.$TID.{tests-run,complete,manual-verified}`, plus the runner-era
addition `handoff.run-plan.$TID` (change 9). The Claude-side cron machinery markers
(`in-progress-defers.<phase>`, `cron-recovery-needed.<phase>`, the `.zskills/inflight/`
sentinel) are SUPERSEDED by the runner loop and are not part of the ported contract.
`.zskills/landed` is a separate worktree-state artifact (not a tracking marker).

### fake-codex simulation requirements (Phase 1 test harness)

Keep the codex fork's architecture: standalone `fake-codex.sh`, `FAKE_CODEX_MODE` env
dispatch, contract-value parsing out of the prompt's `- Label: value` lines, fail-fast
on unprepared calls (exit 99, like `tests/mocks/mock-gh.sh`). Add:

1. `--json` JSONL emission: `thread.started` (generated `thread_id`),
   `item.completed`, `turn.completed`.
2. `exec resume <ID>` acceptance: first call issues an id; subsequent `resume` calls
   must present the SAME id (mismatch → distinct error mode `resume-mismatch`); a
   `session-lost` mode where resume fails; fresh-mode (`finish auto`) calls must NEVER
   contain `resume` in argv (assert via argv log `.zskills/fake-codex/argv.log`).
3. `-o/--output-last-message` and `--output-schema` (conforming and violating JSON per
   mode).
4. Mutations in CURRENT artifact formats: table tracker AND checkbox AND frontmatter
   `status:` flip; report prepend-format with `## Phase`/`**Status:**`/
   `### Verification`; `.zskills/landed` writes with each status value.
5. Failure-mode matrix (union of both forks' modes + new): success, multi-progress,
   no-progress, missing-handoff, missing-verifier, missing-tests-run,
   missing/malformed report, premature-final, dirty, stale-markers, sleep (wall
   timeout), idle, nonzero-exit, sandbox-fail (bwrap stderr), pr-wrong-tracking,
   mid-run-stop (writes the stop marker during a chunk so the loop must honor it
   before the NEXT chunk), resume-mismatch, session-lost, schema-conforming,
   claim-evidence-mismatch.
6. **Probe-id anchoring (anti-circularity):** every Codex semantic fake-codex
   simulates carries a source comment citing the probe id that validates it
   (`exec.json.thread-id` for the JSONL shape; `exec.resume.same-session` /
   `exec.resume.prompt-and-json` / `exec.resume.session-loss` for resume behavior;
   `exec.output-last-message` / `exec.output-schema` for the output flags). fake-codex
   simulates only probe-covered behavior — it is DOWNSTREAM of the probe contract,
   never an independent oracle. When an owner probe result deviates from a simulated
   semantic, the Phase-4 probe triage (WI 4.0b) names fake-codex and its suites as
   rework targets for that id.

## Reference — repo mechanics the toolkit must respect

All verified against this worktree (main @ e3ff496d) at draft time; verify by content,
not blind line number.

1. **The prod strip.** `scripts/_lib/finalize-prod-tree.sh` deletes
   `find "$tree/scripts" -maxdepth 1 -type f -name 'build-*.sh'` (≈L259), all of
   `.github/`, all `*CANARY*`-basename files RECURSIVELY, and `MW-EXAMPLE*` files from
   every shipped tree; `build-plugin-release.sh`'s strip-verify grep (≈L260) forbids
   `scripts/build-[^/]*\.sh` in the built tree. **Therefore the toolkit lives at
   `scripts/porting/`** — a subdirectory survives the maxdepth-1 strip, so
   prod-descendant forks inherit it (fork-generality requires this). Toolkit file
   basenames must never contain uppercase `CANARY` or `MW-EXAMPLE` (lowercase
   `canary` is safe — the strip find is case-sensitive; `hooks/canary*-bad.sh` is a
   separate hooks-only rule).
2. **Extended-scope forbidden-literals scan.** `tests/test-skill-conformance.sh`
   (≈L2808-2810) scans `hooks/*.sh(.template)`, `scripts/*.sh` at **maxdepth 1**, and
   `skills/**/scripts/*.py`. `scripts/porting/` currently ESCAPES it. This plan widens
   the scan to cover `scripts/porting/*.sh` and `scripts/porting/*.py` (Phase 0 work
   item) — deliberately, not dodging. Genuine literals in toolkit scripts (e.g. a
   default `reports/` fallback) carry `# allow-hardcoded: <literal> reason: …`
   markers per the existing format.
3. **Test-suite contract.** Every new `tests/test-*.sh` MUST be registered with a
   `run_suite` line in `tests/run-all.sh` (the #1186 gate
   `tests/test-suite-registration-complete.sh` fails otherwise); must emit the
   canonical `Results: N passed, M failed` line; must exit non-zero on failure;
   must tolerate the parallel worker env (only `CLAUDE_PROJECT_DIR` exported, private
   `TMPDIR`, hard `timeout 600` per suite); must never hardcode `/tmp/<artifact>`
   where `$TMPDIR` should be honored (`tests/test-tmpdir-hardcode-guard.sh`).
4. **Python resolution.** No jq anywhere. Any toolkit script needing JSON inlines the
   canonical `zskills_resolve_python` block VERBATIM from
   `hooks/_lib/resolve-python.sh` (probe-RUN each candidate; `$ZSKILLS_PYTHON` →
   `python3` → `python`; rejects python2/MS-Store stub) and is added to
   `RESOLVE_PYTHON_CONSUMERS` in `tests/test-hook-helper-drift.sh` so byte-drift is
   gated.
5. **BSD/macOS portability discipline (#1156).** No GNU-only `date -d`, no bare
   `realpath -m`, no bash-4-isms in new toolkit scripts; follow the fallback shims
   already landed in PR #1168.
6. **AGENTS.md renderer.** `scripts/render-managed-rules.py` is the ONE canonical
   renderer (D24 — extend, never fork): `--template <tmpl.md> --out <path>
   [--config <cfg.json>] [--defaults <defaults.json>]`; the substitution map is empty
   post-de-parameterization (pass-through + fail-loud `{{TOKEN}}` guard); output
   written atomically. Retargeting to AGENTS.md is a `--out` change; the REAL
   constraint is content size (44,935-byte template vs 32 KiB cap).
7. **Scanner ancestor.** `tests/lib/zsh-fence-scan.py` (305 lines) is the
   architectural model for the Codex-construct scanner: data-driven construct
   classes, fence state machine, per-class remedy text, one machine-readable
   `…-SUMMARY:` line, pure reporter (exit 0 always) with a fail-closed bash caller,
   and anti-vacuous census floors in the caller
   (`tests/test-skill-conformance.sh` ≈L3154-3245).
8. **Suite provenance.** `tests/run-all.sh` emits a content-sensitive fingerprint
   header (HEAD + `git diff HEAD` + untracked rollup); `tests/lib/suite-result-valid.sh`
   validates same-tree + <30 min. A ported tree running its own `tests/run-all.sh`
   produces its own fingerprint; the port's provenance manifest binds ported-tree ↔
   Claude-source-SHA (the validator cannot and should not).

## Reference — scanner construct classes v1

The initial data-driven deny-list for `scripts/porting/codex-scan.py`. Each class
carries: match patterns (prose + fence), a remedy string naming its guide recipe, and
an anti-vacuous census floor (see Phase 3 for floor derivation). Approximate live-tree
counts from the draft-time inventory are context, NOT frozen expectations:

| Class id | Matches | Live-tree scale | Recipe (Phase 4) |
|---|---|---|---|
| `cron` | `CronCreate`, `CronList`, `CronDelete`, `compute-cron-fire` | ~97 + script refs | Runner replaces scheduling; Phase-5c handoff-marker rewrite |
| `agent-dispatch` | `Agent tool`, `subagent_type`, `isolation: "worktree"` | ~68 | `codex exec` child / native `.codex/agents/*.toml`; fresh-context preservation |
| `bg-monitor` | `Monitor`, `TaskOutput`, `BashOutput`, `run_in_background` | ~23 (mostly prohibitions) | Delete/rewrite — Layer-0 timeout apparatus is Claude-specific |
| `skill-tool` | `Skill tool` dispatch | ~29 | Read-SKILL.md-and-execute-inline (the validated cron-fire fallback) + push logic into bundled scripts |
| `arguments` | `$ARGUMENTS` | ~162 | Codex skill invocation text semantics |
| `ask-user` | `AskUserQuestion` | ~9 | Plain-prose questioning degradation |
| `plugin-root` | `${CLAUDE_PLUGIN_ROOT}` / `CLAUDE_PLUGIN_ROOT` | ~799 | Verify Codex alias (probe) or rewrite to resolved root |
| `project-dir` | `CLAUDE_PROJECT_DIR` | ~360 | git-fallback becomes primary (already exists in `zskills-paths.sh`) |
| `frontmatter-flags` | `disable-model-invocation`, `user-invocable`, `allowed-tools`, agent-frontmatter `hooks:` | ~20 | `openai.yaml` `allow_implicit_invocation` / documented degradation |
| `claude-model-dispatch` | `model: "opus"` / `model: "sonnet"` literals AND the pinned prose patterns `haiku=1 < sonnet=2 < opus=3` and `[Nn]ever dispatch.*[Hh]aiku`; co-author trailer lines (`Claude Opus … <noreply@anthropic.com>`) are EXCLUDED by pattern (they are commit metadata, not dispatch) | ~4 prose hits in `skills/` (the `model:` literals live in the rules template / root `*.md`, inside the default `--scope` but outside `skills/`) | Rewrite to Codex `model`/`model_reasoning_effort` config or delete |

Unknown classes (constructs the scanner cannot classify but that match the
Claude-construct heuristics recorded in the guide) are reported as `unknown-class` for
agent judgment; the ruling is appended to the guide AND to the scanner's class data
(the self-amendment rule).

## Why these phases, in this order

- **Phase 0 first (probe kit + owner-gated probe):** empirical-verification-first
  phasing (INSTALL_REDESIGN precedent) — the capability table above is
  research-verified but not hands-on-verified; the probe converts it into the guide's
  assumptions manifest, and its results can reshape recipes (e.g. `CLAUDE_PLUGIN_ROOT`
  alias fidelity, AGENTS.md cap behavior). Building the kit is autonomous; running it
  is the owner's one attended step before Phase 4. It also creates `scripts/porting/`
  and widens the literal scan (the location decision is load-bearing for everything
  after).
- **Phases 1–2 (runner, split) before the guide:** the runner is the largest, riskiest
  artifact and is independent of probe results (built against documented API shapes,
  validated by fake-codex, re-checked by the Phase-4 probe triage). It is split —
  Phase 1 lands the four co-evolving scripts (runner + gate + invariants + fake-codex)
  with the preflight suite; Phase 2 lands the behavioral matrix (happy / failures /
  every) that pins the validation ladder. One phase for all of it was ~3,900 lines in
  a single implementer dispatch — over any honest single-context budget. The split
  honors the riskiest-artifact norm without stubbing: Phase 1's scripts are
  preflight-tested and dry-run-pure at commit time; nothing downstream consumes the
  runner before Phase 2's matrix is green.
- **Phase 3 (scanner + converters) after runner, before guide:** the guide's recipes
  are keyed one-to-one to scanner classes; the scanner must exist first so
  recipe↔class parity is mechanically checkable.
- **Phase 4 (probe triage + guide) gates on probe results:** the assumptions manifest
  ingests the owner's probe file, and the NEW triage step (WI 4.0b) is where a failed
  or deviant probe result flows into named rework of Phase 1–3 artifacts — before the
  guide bakes an unverified capability into the reusable artifact.
- **Phases 5–13 (the first port) are the guide's acceptance test, sliced:** under
  /run-plan, one phase = one implementer dispatch, and subagents cannot dispatch
  subagents — so the port cannot be "one phase that dispatches a porting agent."
  Instead the phase implementer IS the porting agent, and the port is decomposed into
  six guide-only slices (Phases 6–11) sized from draft-time volume measurement
  (~32k lines of skill markdown; the slice budget is MARKDOWN-ONLY — see WI 5.3),
  bracketed by a setup phase (5: durable port root, pinned source snapshot, target
  clone on a dedicated port branch, slice worklist) and TWO assembly phases split by
  workload shape: Phase 12 (assembly VERIFICATION — bounded, mechanical: whole-tree
  gate, manifest/disposition parity, hit-site parity, fidelity, composition) and
  Phase 13 (gap-fold + bounded refold + push — the judgment-work phase, with an
  explicit volume bound and a STOP for systemic failure; folding gaps and verifying
  the tree in one 2-hour dispatch was the round-1 "weeks of judgment in one dispatch"
  shape reborn). Slice phase texts are deliberately procedure-free: the porting
  knowledge comes ONLY from the guide, so the acceptance-test property ("agents
  following only the guide") is preserved per-slice. Every gap fixes the GUIDE (the
  product), not just the port (the instance) — folded once, at Phase 13, so mid-port
  guide edits never steer later slices.
- **Phase 14 (verification) after the port exists:** curated ported-tree suite runs,
  runner-against-ported-tree integration, canary kit + owner-gated real-Codex matrix
  incl. failure-path canaries.
- **Phase 15 last (release procedure + fork-robustness + docs sweep):** release
  machinery needs the whole pipeline proven once; fork-robustness (divergent-tree
  discovery + delta classification) is the headline requirement's acceptance test and
  depends on scanner + guide + delta tooling all existing.

Sixteen phases is over the 5–7 house norm; the count is deliberate. The port itself
is six phases because each slice must be a FRESH single-context guide-only agent (the
whole point of the acceptance test), the runner is two phases because its one
honest alternative was a single 3,900-line dispatch, and assembly is two phases
because verification is bounded while gap-folding is not. Each phase remains one
small, verifiable commit.

## Execution context

- Implementation dispatches use `subagent_type: "implementer"`; verification uses the
  verifier subagent. Verifier-cannot-run = verification FAIL ⇒ Failure Protocol.
  Two-attempt limit on all fix cycles. Capture test output with the canonical idiom
  (`TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"`, computed AFTER cd-ing into
  the worktree root); never pipe.
- **Dispatch topology (how the port executes under /run-plan).** Each phase is
  executed by ONE implementer subagent that receives the verbatim phase text, with a
  2-hour agent timeout (`skills/run-plan/modes/execute-phase.md`), and subagents
  cannot dispatch subagents. Therefore the slice phases (6–11) are written so that
  run-plan's own implementer dispatch IS the porting-agent dispatch: their phase text
  contains slice assignment, paths, and hygiene rules but NO porting procedure — the
  procedure lives exclusively in `docs/porting/CODEX_PORTING.md`. If a slice agent
  cannot make a porting decision from the guide alone, that is a GAP entry (a guide
  defect recorded in the ported tree's `GAPS.md`), never a license to consult this
  plan or the research files. Setup (Phase 5) and assembly (Phases 12–13) agents are
  NOT porting agents and may read the plan freely.
- **Two-attempt discipline for the port is per SLICE, not per port.** A slice agent
  that runs out of context commits its completed units to the target clone, updates
  the worklist cursor, and reports the phase incomplete; the re-dispatch (attempt 2,
  fresh agent) resumes from the cursor instead of redoing finished units. **The
  target clone's `port:` commit subjects are the AUTHORITATIVE cursor** — the
  committed worklist can lag it (a container restart destroys the /tmp phase
  worktree holding uncommitted worklist updates), so every slice attempt begins by
  reconciling: any unit with a `port: <unit>` commit in
  `git -C "$PORT_ROOT/target" log --oneline` is `done`; update the worklist to
  match, then resume from the first remaining `pending`. A unit left half-edited by
  a dead attempt is redone idempotently: re-copy it verbatim from the source
  snapshot over the target dir and re-apply the recipes (copy-first makes redo safe;
  `git restore`/`git reset --hard`/`git clean -f` are hard-denied by this repo's
  hooks and are never needed). A slice still incomplete after attempt 2 ⇒ STOP and
  surface (the fix is rebalancing the worklist via `/refine-plan`, a human-visible
  decision — not a third attempt).
- **Target-clone git discipline (the port-branch rule — binding on every phase that
  touches `$PORT_ROOT/target`).** This repo's safety hooks fire on every Bash call
  in every session of this pipeline, including cd-chained git operations inside the
  target clone, and several of them evaluate MIXED roots: `is_main_protected` reads
  THIS repo's config (`main_protected: true`) from the ambient root while
  `is_on_main` and the stale-skill-version stage-check resolve from the extracted
  `cd` target (verified against `hooks/block-unsafe-project.sh`,
  `hooks/block-unsafe-generic.sh`, `hooks/block-stale-skill-version.sh` at draft
  time). The plan works WITH those gates, never around them:
  1. **All target-clone work happens on the dedicated branch `port/first-port`**
     (created in Phase 5, recorded in the worklist as `port_branch`), never on the
     target's `main`. Every gate arm that would block — `commit_on_main`, all three
     `push_to_main` refspec rules in both hooks — keys on `main`/`master`
     specifically, so commits and pushes on the port branch pass every arm honestly
     (verified against the hook regexes). Phase 13 pushes `port/first-port`;
     **promotion to the target repo's `main` is an OWNER step by design** (one
     command from any machine, e.g. `git push origin port/first-port:main` or a
     GitHub UI merge) — consistent with the "agents must not push to main" doctrine,
     which these hooks enforce for ANY repo they can see. No hook carve-out is added
     anywhere: editing safety hooks so an agent can bypass them was considered and
     rejected (surface-bugs-don't-patch; the config-tamper gate exists precisely to
     make disarming protection visible).
  2. **ONE pinned invocation form for every target-clone git WRITE** (add / rm /
     checkout / commit / push — anything that mutates index, branch, or remote
     state): a SINGLE compound command with a LITERAL absolute `cd` —
     `cd /abs/literal/path/to/target && git …`. The rule, spelled out: resolve
     `PORT_ROOT` ONCE (WI 5.1) and write the RESOLVED ABSOLUTE path into the
     worklist as `port_root`; every later phase copies that literal string out of
     the worklist into its commands. NEVER a variable cd
     (`cd "$PORT_ROOT/target"`), NEVER a bare `git commit` relying on a previous
     Bash call's persisted cwd, NEVER `git -C` for commits. Reason (verified
     against hook source, and live-fired during review): the hooks'
     `extract_cd_target` accepts a cd target only when the RAW UNEXPANDED token is
     an existing directory (`[ -d "$stgt" ]` — a `$VAR` token or an absent cd
     extracts EMPTY), and `is_on_main` then falls back to the hook's AMBIENT root
     — THIS repo, on `main` — so `commit_on_main` denies a perfectly-correct
     port-branch commit purely because of its SPELLING. The literal-cd compound is
     the one form under which every gate evaluates the TARGET clone truthfully.
     Read-only queries (`log`, `rev-parse`, `status`, `ls-remote`) may use
     `git -C "$PORT_ROOT/target" …` — the hooks gate only writes. Ecosystem
     precedent: run-plan's execute-phase substitutes LITERAL worktree paths into
     agent prompts for exactly this reason. The guide's per-slice step carries
     this same rule (WI 4.1) so guide-only slice agents inherit it.
  3. **`metadata.version` is re-stamped at port time** (guide recipe, WI 4.2): a
     ported skill is NEW content and carries a fresh
     `YYYY.MM.DD+<hash>` stamp computed by the SOURCE tree's
     `scripts/skill-content-hash.sh` + `scripts/frontmatter-set.sh`. This makes
     `block-stale-skill-version.sh` (which runs its stage-check `cd`'d into the
     target clone on literal-cd commits — a KEEP-HARD gate) pass honestly on every
     target commit, including attempt-2 re-ports and fix-cycle edits. Precision on
     "honestly": the stage-check resolves its helper scripts from the cd-TARGET
     root, so until the `scripts-core` unit lands in the target tree (slice F,
     WI 11.1) the check passes VACUOUSLY (missing helpers yield empty values and
     no failure branch can fire — traced against
     `scripts/skill-version-stage-check.sh`); from slice F onward the check is
     LIVE and the re-stamp is genuinely load-bearing. The re-stamp is mandatory
     from the first slice regardless — for content honesty and because commit
     ORDER within slice F is not pinned. Never dodge the hook via `git -C` forms —
     that bypasses only because `extract_cd_target` misses the form (a blind spot,
     not a contract); use the pinned literal-cd compound (item 2) and let the
     gates evaluate truthfully.
  4. **run-plan overlay reconciliation.** run-plan's dispatch overlay
     ("the implementation agent does NOT commit"; "`$FULL_TEST_CMD` before every
     commit", `skills/run-plan/modes/execute-phase.md` §Commit discipline) governs
     THIS repo's git tree only. Commits into `$PORT_ROOT/target` are out-of-repo
     ARTIFACT WRITES expressly authorized by the slice/assembly phase texts — the
     implementer makes them, per-unit, and no zskills test suite gates them. The
     zskills-side commit (worklist/notes under `docs/porting/notes/first-port/**`)
     stays with the VERIFIER after the phase's full-suite run, exactly per the
     overlay. Each slice phase's text restates this reconciliation because the
     implementer receives both texts.
  5. **A hook deny envelope is a signal to CLASSIFY, never an auth failure.** If a
     target-clone git operation is denied, read the `permissionDecisionReason`:
     `main_protection`/`push_to_main` ⇒ FIRST check the SPELLING, not the branch —
     the overwhelmingly likely cause is an invocation-form fallback (a variable
     cd, a bare git after a prior cd, or a `git -C` commit made the hook evaluate
     the AMBIENT repo on `main`, not the target clone; item 2). Re-issue ONCE as a
     single compound with the literal absolute cd. Only if the literal-cd form is
     ALSO denied, check the branch state
     (`git -C <literal-target> rev-parse --abbrev-ref HEAD` == the worklist's
     `port_branch`; restore it if wrong) and retry once. Do NOT loop retries on
     the same spelling — the deny is deterministic for a given spelling, so an
     unchanged re-issue is a wasted attempt. `stale_skill_version` ⇒ a re-stamp
     was missed (the deny message carries the exact bump command — run it, restage,
     retry); `tracking`/`git_discipline` ⇒ report verbatim in the phase report.
     NEVER take Phase 13's bundle fallback (reserved for genuine auth/network
     failure) in response to a hook deny, and never thrash past the two-attempt
     limit.
- **Durable port root.** All first-port state lives at
  `PORT_ROOT="$MAIN_ROOT/.zskills/porting/first-port"` where
  `MAIN_ROOT="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"` — the MAIN repo
  root, resolved identically from any phase worktree. `.zskills/` is gitignored
  (umbrella entry) and fence-protected (`block-unsafe-project.sh` guards every
  `.zskills/<subtree>/`), and it survives across finish-auto sessions — unlike
  `${TMPDIR:-/tmp}`, which this plan does NOT use for anything a later phase depends
  on. PORT_ROOT holds the pinned source snapshot, the local target-repo clone, and
  (fallback only) the push bundle.
- Each phase is one commit unless the phase says otherwise. All phases except the
  attended items below run in this container.
- **Attended steps (ENFORCEMENT_V2 encoding).** This plan has exactly TWO planned
  owner-machine attended items (no Codex CLI in the container — settled decision
  10), plus one planned any-machine owner step, plus one CONTINGENT item:
  1. **Phase 0 ATTENDED item (probe run):** the owner runs the probe kit on a
     real-Codex machine and commits `docs/porting/probe-results.json` per WI 0.7's
     branch protocol. The item is NON-GATING for Phase 0 itself (Phase 0's gating
     content is the kit). If not run when Phase 0 lands, record **ATTENDED-PENDING**
     in the tracker Notes AND file a follow-up issue so it isn't silently dropped.
  2. **Phase 14 ATTENDED item (real-Codex canary matrix):** the owner runs the canary
     kit against the ported repo on a real-Codex machine and commits
     `docs/porting/canary-results.json`. Same encoding: non-gating,
     ATTENDED-PENDING + follow-up issue when deferred. The final phase's completion
     message must surface any pending attended items as User Verify residue —
     including, verbatim, the line "**the runner is unverified against real Codex**"
     whenever the canary results are still pending (the fake-codex matrix validates
     internal consistency, not Codex; only the probe + canaries touch the real
     binary).
  3. **Planned owner step (any machine): promote the port branch.** After Phase 13's
     push, the target repo's `main` is promoted from `port/first-port` by the OWNER
     (one command — see the port-branch rule above). Recorded at Phase 13 as a named
     owner action and surfaced in the completion message while pending.
  4. **CONTINGENT item (target-repo push/remote wiring):** becomes attended only
     when clone/push auth is unavailable (WIs 5.2/13.4 produce the named
     ATTENDED-PENDING entry + follow-up issue).
- **Downstream gating is on the artifact, not the ceremony — and the gate is the
  ORCHESTRATOR'S, executed BEFORE dispatching Phase 4.** Phase 4 requires the
  owner-produced `docs/porting/probe-results.json`. The check is pinned in Phase 4's
  WI 4.0/Dependencies: bring the phase worktree current first (`git fetch`, then
  rebase onto the plan's integration branch — `origin/main` in cherry-pick/direct
  landing, the plan-scoped PR branch in PR landing; the owner commits the results
  file to that same integration branch per WI 0.7), then `test -f`. Present ⇒
  validate, TRIAGE (WI 4.0b), then ingest. **Absent ⇒ Failure-Protocol STOP — the
  orchestrator (which alone holds CronList/CronDelete; the implementer's toolset
  cannot kill a cron) deletes the armed cron and surfaces the WI 0.7 instruction.
  This is explicitly NOT run-plan Step 4's recoverable dependency-not-met case:**
  that branch deliberately leaves the cron alive to retry, which against a file only
  the owner can produce means a `*/1` cron spinning forever. Phase 4's Dependencies
  section restates this classification verbatim at the exact decision point a
  fresh cron-fired orchestrator reads. If a dispatched Phase-4 implementer finds the
  file absent anyway (belt-and-braces), it reports `FAILED-OWNER-GATED: probe
  results absent` and stops; the orchestrator MUST translate that report into the
  Failure Protocol (cron deleted, surfaced), never into "retry next fire."
- **Probe results are rework triggers, not just documentation.** A `fail` (or a
  pass-with-deviant-observed-value) on a load-bearing probe id does not merely get
  recorded in the assumptions manifest — WI 4.0b maps every such id to the concrete
  Phase 1–3 artifacts built on it and either executes the rework (in-phase, edits to
  `scripts/porting/**` + `tests/**` are authorized when probe-triggered) or STOPs via
  the Failure Protocol when the failed capability is substrate-level (resume
  semantics, hook deny envelope, skill discovery). "Probe-falsified runner/scanner
  semantics = a rework item in the phase that ingests the results, never a docs
  note."
- **Where finish auto is suspended:** arming `finish auto` across Phases 0→3 is
  expected and safe. The Phase 3→4 boundary is the owner-gated seam: if the probe
  results file is not yet on the integration branch when Phase 4 is selected, the
  orchestrator STOPs via the Failure Protocol and DELETES the cron per the gating
  rule above (Phase 4's Dependencies carry the non-recoverable classification at
  the point of decision). Recommended drive pattern: arm finish auto; when it stops
  at Phase 4, run the probe, commit the results per WI 0.7, re-arm. Phases 4→15
  then run under finish auto normally (the Phase 14 canary item is non-gating by
  construction).
- **Outward actions authorized by this plan:** Phase 5 clones the private repo
  `zeveck/zskills-codex-f` (settled decision 9); Phases 6–11 commit to the LOCAL
  target clone under PORT_ROOT (no network); Phase 13 pushes the port branch
  `port/first-port` to `zeveck/zskills-codex-f` (NEVER the target's `main` —
  promotion is the owner's; bundle fallback when push auth is unavailable);
  Phase 14 fix cycles commit AND push ported-tree fixes to the same port branch;
  Phases 0, 13, and 14 may file follow-up issues in this repo for ATTENDED-PENDING
  items; Phase 15's release procedure documents (but does not execute) future pushes.
- **Coordination hazards during the execution window:**
  - A prod release is PENDING (ships everything since 2026-06-15). If it fires
    mid-plan, `YYYY.MM.N` tag arithmetic moves; it is also the natural first
    matched-version pair for the release procedure. No file conflicts expected.
  - #1183 (marketplace.json `github`-shorthand fix) touches the exact file Codex's
    marketplace compat reads — if it lands, re-verify the plugin-compat recipe.
  - #1146 (dual-read retirement): the runner and invariants target NEW marker paths
    (`.zskills/landed`, `.zskills/tracked`) with the legacy fallback retained only
    while upstream retains it — mirror upstream's state at implementation time.
  - #1156 (BSD/macOS) discipline applies to every new toolkit script.
  - Windows Bundle-3 upstreaming may churn hook/script bodies the scanner reads —
    scanner classes are content-pattern-based, not line-anchored, so this is
    tolerable; do not pin line numbers anywhere in the toolkit.
- `metadata.version` hazard: NONE in this repo by design — this plan touches no
  `skills/**` files here. If an implementer finds itself editing a skill in THIS
  repo, that is scope drift; stop and surface. (The SLICE phases read `skills/**`
  from the pinned snapshot and write to the out-of-repo target clone — they never
  edit this repo's skills either. TARGET-clone skill files DO interact with the
  version hook: see the port-branch rule item 3 — re-stamp at port time.)

## Critical invariants every phase must honor

1. **Fork-generality:** no toolkit script or guide page enumerates today's skill
   list, assumes a skill count, or hardcodes a repo/target name. All counts in ACs
   are re-derivation commands, never frozen integers (census FLOORS are permitted as
   anti-vacuous minimums, per the zsh-scan precedent). This PLAN's slice tables DO
   enumerate today's skills — permitted because the plan is a one-time execution
   artifact (settled decision 9); the GUIDE's slicing procedure is enumeration-free.
2. **The Claude repo stays clean:** phases add only `docs/porting/**` (including the
   `notes/` instance records), `scripts/porting/**`, `tests/**` (incl. `tests/mocks/`,
   `tests/fixtures/porting/`), the one deliberate widening edit to
   `tests/test-skill-conformance.sh` + registration lines in `tests/run-all.sh` +
   drift-gate consumer registrations, and — in Phase 15's docs sweep ONLY —
   `CHANGELOG.md` and `RELEASING.md`. NO edits to `skills/**`, `hooks/**`,
   `agents/**`, `CLAUDE_TEMPLATE.md`, or `.claude/**` (bugs found there are surfaced
   as issues, not patched in this plan).
3. **Full bodies, never wrappers:** any porting output containing "load only when
   insufficient", "otherwise run inline", or equivalent hedge-prose is a defect; the
   scanner + slice/assembly greps enforce the hedge, and the per-skill FIDELITY FLOOR
   (ported markdown bytes ≥ 0.6 × source markdown bytes unless a manifest
   disposition explains the shrink — the pinned command lives in Phase 6's AC and
   Phases 7–12 inherit it) plus the assembly-phase verifier spot-check and the
   per-hit-site disposition parity check (Phase 12) enforce the fullness — a
   scanner-clean 60-line condensation fails the floor, and a full-length paraphrase
   that files the construct nouns off fails hit parity. (Basis for 0.6: the
   wrapper post-mortem — zskills-codex's précis wrappers ran roughly 0.09–0.5×
   source bytes, while a legitimately construct-heavy skill loses well under 40%
   to recipe deletions; a judgment constant, tunable via `/refine-plan` with a
   stated basis — the floor's job is catching wrapper-shaped shrinkage, not the
   exact value.)
4. **Never fire-and-forget:** every runner mode streams child output to the attached
   terminal; every background-ish behavior is a documented later add-on, not built.
5. **Fail-closed everywhere:** the scanner gate fails on any unclassified or
   unremedied construct; the probe kit refuses (non-zero, no partial results file)
   when `codex` is absent; the runner refuses rather than guesses (narrative plans,
   dangerous flags, foreign claims, session loss).
6. **Test discipline:** every new suite registered in `tests/run-all.sh` (#1186
   gate); canonical `Results:` line; parallel-env tolerant; `$TMPDIR`-honoring; the
   FULL local suite runs before every zskills commit in the phases that touch
   `tests/`, `scripts/`, or shared infra (0–4, 12–15), reported with per-suite
   results and the exact command. The slice phases' zskills commits (5–11) are
   notes-markdown only (`docs/porting/notes/first-port/**` — their ACs enforce
   exactly that) and are committed by the VERIFIER after its full-suite run per the
   run-plan overlay; target-clone commits are out-of-repo artifact writes outside
   this invariant (Execution-context port-branch rule item 4).
7. **Portability discipline:** BSD/macOS-safe bash; Python via the inlined verbatim
   resolver + drift-gate registration; no jq; no uppercase-`CANARY`/`MW-EXAMPLE`
   basenames in shipped toolkit/fixture files. The two OWNER-RUN kits (probe,
   canary) must additionally run under Git-Bash/MSYS on Windows — the owner's
   real-Codex machine is plausibly Windows: probe-RUN binary resolution (accept
   `codex`/`codex.cmd`, validate via `codex --version` exit 0 — same doctrine as the
   python resolver), no GNU-only `date -d`/`readlink -f`/`mktemp --suffix`, prompts
   that survive mintty.
8. **The ported tree never lands in this repo:** it is out-of-repo output (built in
   the gitignored PORT_ROOT, pushed to the target repo). zskills commits carry only
   guide/toolkit/test changes plus the `docs/porting/notes/` instance records.
9. **Surface bugs, don't patch:** any canary failure, scanner false-positive, or gate
   misbehavior found while building is a signal to fix at source (in the toolkit or
   guide) or file an issue — never route around quietly.
10. **Two-attempt limit** on any fix→test→same-failure loop; STOP and report. For the
    port slices the unit of the limit is the SLICE (with cursor resume), per the
    Execution-context rule.

## Progress Tracker

| Phase | Status | Commit | Notes |
|---|---|---|---|
| 0 — Probe kit + scan widening (+ owner probe, attended) | ✅ Done | `222c0d15` | 25-probe kit + suite (27 checks); 8324/8324; WI 0.7 ATTENDED-PENDING #1189 |
| 1 — Runner + gate + invariants + fake-codex + preflight suite | ✅ Done | `9c3e3893` | 15/15 spec changes audited; preflight 27/27; 8353/8353; template verbatim-match |
| 2 — Runner behavioral matrix (happy / failures / every suites) | ✅ Done | `e11492a2` | 36 cases (8/20/8); 8 matrix-found Phase-1 fixes all spec-consistent; 8389/8389 |
| 3 — Scanner + converters + AGENTS.md renderer wrapper + tests | ⬚ | | |
| 4 — Probe triage + the porting guide (gates on probe results) | ⬚ | | |
| 5 — First-port setup: port root, source snapshot, target clone, worklist | ⬚ | | |
| 6 — Port slice A: run-plan, create-worktree, plans (guide-only) | ⬚ | | |
| 7 — Port slice B: fix-issues, investigate, session-report, briefing (guide-only) | ⬚ | | |
| 8 — Port slice C: update-zskills, do, manual-testing (guide-only) | ⬚ | | |
| 9 — Port slice D: draft-plan, draft-tests, refine-plan, research-and-plan, research-and-go, qe-audit (guide-only) | ⬚ | | |
| 10 — Port slice E: work-on-plans, land-pr, commit, cleanup-merged, verify-changes, zskills-dashboard, fix-report (guide-only) | ⬚ | | |
| 11 — Port slice F: hooks, agents, rules/AGENTS.md, config, toolkit install, scripts helpers, plugin compat, test registry, manifest skeleton (guide-only) | ⬚ | | |
| 12 — Port assembly verification: gate, manifest/disposition parity, hit parity, fidelity, composition | ⬚ | | |
| 13 — Gap-fold into guide/toolkit, bounded refold, push port branch | ⬚ | | |
| 14 — Port verification (+ owner canaries, attended) | ⬚ | | |
| 15 — Release procedure + fork-robustness + docs sweep | ⬚ | | |

## Phase 0 — Real-Codex probe kit, `scripts/porting/` bootstrap, literal-scan widening

### Goal

Create `scripts/porting/` with a self-contained, owner-runnable probe kit that
verifies every load-bearing Codex capability claim hands-on and emits a
machine-readable results file (the seed of the guide's assumptions manifest); widen
the extended-scope forbidden-literals scan to cover the new directory; declare the
owner's probe run as the plan's first attended item.

### Work Items

- [ ] **0.1 — `scripts/porting/codex-probe.sh`.** Self-contained bash (BSD-safe AND
  Git-Bash/MSYS-safe — see D&C, `set -euo pipefail`, inlined
  `zskills_resolve_python` verbatim), ZERO zskills install prerequisites — runnable
  from a bare clone on the owner's machine. CLI:
  - `--list` — enumerate the probe registry: exactly one probe id per line on
    STDOUT; a header line carrying the registry count goes to STDERR (so
    `--list 2>/dev/null | wc -l` equals the registry size exactly). Exit 0, works
    WITHOUT a codex binary.
  - `--out <path>` — run all probes against the real `codex` CLI, write results JSON
    atomically (`.tmp` + move) ONLY on completion; the codex binary is resolved by
    PROBE-RUNNING candidates (`--codex-bin` override, then `codex`, then
    `codex.cmd`), accepting only one where `<candidate> --version` exits 0 — never
    bare `command -v` (the npm `.cmd` shim / stub problem, same doctrine as the
    python resolver). If none resolves, print `ERROR: codex CLI not found — this kit
    must run on a machine with Codex installed` to stderr, exit non-zero, write
    NOTHING.
  - `--only <id>[,<id>…]` — run a subset (for re-verification at release time).
  - `--validate <file>` — schema-check an existing results file (used by tests and
    by Phase 4's gate), exit 0/1.
  - Final stdout line: `CODEX-PROBE-SUMMARY: probes=<N> pass=<P> fail=<F> skip=<S>`.
- [ ] **0.2 — Probe registry.** One entry per load-bearing capability claim from the
  capability map, each with a scripted check and expected/observed capture. Minimum
  set (ids are the contract; Phase 4 keys the assumptions manifest AND the triage
  table on them):
  `skills.discovery.agents-dir`, `skills.discovery.claude-skills-path-config`,
  `skills.frontmatter.unknown-ignored`, `skills.invocation.dollar-name`,
  `skills.invocation.implicit`, `skills.openai-yaml.implicit-invocation-off`,
  `hooks.pretooluse.deny-envelope`, `hooks.pretooluse.exit2-stderr`,
  `hooks.pretooluse.updated-input`, `hooks.sessionstart.additional-context`,
  `hooks.stdin.permission-mode`, `hooks.trust.non-managed-friction`,
  `agents.toml.project-dispatch`, `agents.limits.max-depth`,
  `exec.json.thread-id`, `exec.output-last-message`, `exec.output-schema`,
  `exec.resume.same-session`, `exec.resume.prompt-and-json`,
  `exec.resume.session-loss`,
  `agentsmd.cap-32k`, `agentsmd.project-doc-max-bytes-raise`,
  `plugins.marketplace.claude-compat`, `plugins.env.claude-plugin-root-alias`,
  `sandbox.workspace-write.add-dir` — 25 ids.
  Each probe sets up a disposable fixture (temp project dir with a test skill /
  hook / agent TOML), invokes `codex` non-interactively where possible, and records
  `{"status": "pass|fail|skip", "expected": …, "observed": …, "notes": …}`. Probes
  that require interactive TUI confirmation (e.g. `hooks.trust.non-managed-friction`)
  print numbered manual steps and prompt the owner for the observed outcome —
  interactivity is acceptable; this kit is attended by definition.
  **Per-id assertions.** "Ran without error" is never a pass — every probe asserts a
  specific observable behavior. The registry carries a one-line `asserts` field per
  id; the load-bearing ones are pinned HERE (the implementer does not invent them):
  - `exec.resume.same-session` — resume with an explicit `<ID>` reaches the SAME
    durable session: a nonce planted in turn 1 is visible to the resumed turn.
  - `exec.resume.prompt-and-json` — `codex exec resume <ID> --json "<new prompt>"`
    accepts the positional prompt NON-interactively and emits JSONL for the resumed
    turn. This is every-mode's exact invocation shape (spec change 11).
  - `exec.resume.session-loss` — resume of a bogus/deleted id fails with a non-zero,
    distinguishable error — NOT a silent fresh session.
  - `exec.json.thread-id` — the `thread.started` JSONL event carries a thread id
    that a subsequent `exec resume <ID>` accepts.
  - `exec.output-last-message` / `exec.output-schema` — the `-o` file contains the
    final message; a schema-violating self-report is surfaced (observed behavior
    recorded either way).
  - `hooks.pretooluse.deny-envelope` — a deny envelope actually BLOCKS the tool call
    (the gated command's side effect does NOT occur).
  - `hooks.pretooluse.updated-input` — the MUTATED input is what executes (the side
    effect matches the mutated value, not the original).
  - `hooks.pretooluse.exit2-stderr` — exit-2 + stderr blocks and the stderr text is
    surfaced to the model.
  - `hooks.sessionstart.additional-context` — injected context is visible to the
    model (the probe asks the model to echo a planted nonce).
  - `hooks.stdin.permission-mode` — the hook's stdin JSON carries `permission_mode`,
    `tool_name`, `tool_input`.
  - `skills.discovery.agents-dir` — a fixture skill under `.agents/skills` is
    discovered AND invocable by `$name`.
  - `plugins.env.claude-plugin-root-alias` — a hook script observes a non-empty
    `CLAUDE_PLUGIN_ROOT` equal to `PLUGIN_ROOT`.
  - `agentsmd.cap-32k` — a nonce placed PAST the 32 KiB boundary is NOT visible to
    the model; `agentsmd.project-doc-max-bytes-raise` — after the raise, it IS.
  - `sandbox.workspace-write.add-dir` — a write OUTSIDE the workspace at the added
    dir SUCCEEDS, and the same write WITHOUT `--add-dir` fails.
  Registry entries carry a boolean `load_bearing` flag (true for every id named in
  Phase 4's triage table, WI 4.0b) so the triage step is mechanical.
  **Trust-establishment ordering (fixture validity):** Codex requires explicit user
  trust-review before non-managed hooks first run (capability map). Hook-probe
  fixtures MUST establish trust for the fixture hooks (interactive step if
  required, per the trust probe) BEFORE running the hook-behavior probes
  (`hooks.pretooluse.*`, `hooks.sessionstart.*`, `hooks.stdin.*`), and MUST
  exercise them under `codex exec` (the runner's actual substrate). A no-fire
  result observed with trust unestablished is recorded `skip` with reason —
  never `fail` (an ordering artifact must not flow into WI 4.0b's STOP rows).
- [ ] **0.3 — Results schema.** `{"schema": "zskills-codex-probe/v1", "probed_at":
  <ISO8601>, "codex_version": <string from codex --version>, "platform": <uname>,
  "results": {<probe-id>: {…}}}`. `--validate` enforces: schema tag, non-empty
  `codex_version`, every registry id present, every status in the enum. Ship a
  valid sample at `tests/fixtures/porting/probe-results-sample.json` (all-pass
  values marked clearly as SAMPLE, not real observations).
- [ ] **0.4 — Widen the extended-scope forbidden-literals scan.** In
  `tests/test-skill-conformance.sh`, extend the `EXT_FILES` build (the find block
  ≈L2806-2811 — locate by the `find "$REPO_ROOT/scripts" -maxdepth 1` line, verify by
  content) with `find "$REPO_ROOT/scripts/porting" -maxdepth 1 -type f -name '*.sh'`
  and `-name '*.py'` entries. Any genuine literal in toolkit files gets an
  `# allow-hardcoded: <literal> reason: …` marker.
- [ ] **0.5 — `tests/test-porting-probe-kit.sh`.** Container-runnable suite (no codex
  binary): `--list` stdout purity (stdout line count equals registry size; header on
  stderr carries the same count); absent-codex refusal (non-zero exit, correct
  stderr, no output file written — assert the file does NOT exist after);
  `--validate` passes the sample fixture and fails a mutated copy (missing probe id;
  bad status enum; missing codex_version); summary-line format check; a static
  portability self-check — `grep -En 'readlink -f|mktemp .*--suffix|date -d|realpath -m' scripts/porting/codex-probe.sh`
  → zero hits (Git-Bash/BSD discipline, mechanically pinned). Emits the canonical
  `Results:` line. Register via `run_suite` in `tests/run-all.sh`.
- [ ] **0.6 — Register `codex-probe.sh` in `RESOLVE_PYTHON_CONSUMERS`** in
  `tests/test-hook-helper-drift.sh` (it inlines the resolver).
- [ ] **0.7 — ATTENDED (owner, non-gating): run the probe.** On a real-Codex
  machine, **check out the plan's integration branch first** — until the plan's PR
  merges, the kit is not on `main`: in PR landing mode `gh pr checkout <plan-PR>`
  (or `git fetch origin <plan-branch> && git checkout <plan-branch>`); in
  cherry-pick/direct landing, `main` already has it. Then
  `bash scripts/porting/codex-probe.sh --out docs/porting/probe-results.json`,
  review failures, and **commit + push the results file to that SAME integration
  branch** (the branch Phase 4's worktree rebases onto — WI 4.0's gate looks
  there). If not run this session, record **ATTENDED-PENDING** in the Progress
  Tracker Notes AND file a follow-up issue titled "Run Codex probe kit and commit
  docs/porting/probe-results.json (gates CODEX_PORT_PLAN Phase 4)" that includes
  this branch protocol.

### Design & Constraints

- The kit is attended-by-definition; it may prompt. But it must never FAKE a result:
  a probe that cannot run records `skip` with a reason, never `pass`.
- No hardcoded `/tmp` (use `${TMPDIR:-/tmp}`); no GNU-only date/realpath forms.
- **Git-Bash/MSYS is a first-class target for this kit** (the owner's real-Codex
  machine is plausibly Windows — this repo just ran a multi-PR Windows-portability
  campaign for exactly that reason): probe-RUN binary resolution per WI 0.1;
  interactive prompts must work under mintty (plain `read -r` from the controlling
  terminal, no `/dev/tty` bashisms that MSYS lacks); `--out` paths are used as given
  (no path munging that fights MSYS's automatic conversion). **The kit never tries
  to DRIVE the Codex TUI from its own terminal** — TUI-dependent probes (e.g. the
  trust-review step) print numbered manual steps and read back the observed
  outcome, and WI 0.1's instructions state: if the Codex TUI misbehaves under
  mintty (a known winpty-class problem), run the manual step in Windows Terminal /
  PowerShell — or run the whole kit inside WSL2, the likely zero-friction path on
  the owner's Windows-host setup — and enter the observed result at the prompt.
- `docs/porting/` is conformance-inert (catalog whitelist covers only
  `docs/README.md`, `docs/guides/*.md`, `docs/skills/*.md`) except the tree-wide
  conflict-marker test and the release-time dev→prod URL walk — keep any dev-repo
  URLs out of committed porting docs or mark them `zskills-dev-url-allow`.
- Do NOT create `docs/porting/probe-results.json` with placeholder content — its
  absence is the honest gate signal for Phase 4.

### Acceptance Criteria

- [ ] `bash scripts/porting/codex-probe.sh --list 2>/dev/null | wc -l` → count equals
  the registry size and is ≥ 25 (the minimum set in WI 0.2); the stderr header line
  carries the same count (re-derivation, no frozen integer elsewhere).
- [ ] In the container: `bash scripts/porting/codex-probe.sh --out "${TMPDIR:-/tmp}/pr.json"; echo rc=$?`
  → stderr contains `codex CLI not found`, prints `rc=` non-zero, and
  `test ! -e "${TMPDIR:-/tmp}/pr.json" && echo absent` → `absent`.
- [ ] `bash scripts/porting/codex-probe.sh --validate tests/fixtures/porting/probe-results-sample.json && echo OK`
  → `OK`; validating a copy with one probe id deleted exits non-zero naming the
  missing id.
- [ ] `grep -n 'scripts/porting' tests/test-skill-conformance.sh` → shows the widened
  find lines inside the extended-scope scan block.
- [ ] `grep -n 'test-porting-probe-kit' tests/run-all.sh` → one `run_suite` line.
- [ ] `grep -n 'codex-probe' tests/test-hook-helper-drift.sh` → consumer registered.
- [ ] Full suite: `bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1` (capture
  idiom) → aggregate `Results:` line shows 0 failed; report per-suite counts and the
  exact command.
- [ ] ATTENDED (non-gating): `docs/porting/probe-results.json` committed with
  `CODEX-PROBE-SUMMARY: … fail=0` (or failures triaged in the commit message) — OR
  tracker Notes carry `ATTENDED-PENDING` and the follow-up issue number.

### Dependencies

None.

## Phase 1 — Unified runner + gate + invariants + fake-codex + preflight suite

### Goal

Implement the four co-evolving scripts — the unified `zskills-runner.sh` (both
modes), `zskills-gate.sh`, the re-forked post-run invariants, and the fake-codex
test harness — exactly per the "unified runner spec" reference section above (base =
zskills-codex chassis + the 15 named changes + the code-26 child-failure mapping),
with the refusal/preflight suite and dry-run purity green in the container. The
behavioral matrix (happy/failures/every) lands in Phase 2 before anything downstream
consumes the runner.

### Work Items

- [ ] **1.1 — `scripts/porting/zskills-runner.sh`.** Implement per the spec reference
  (§"unified runner spec"): CLI `status|stop|next|run-plan <plan> (finish auto
  [direct|cherry-pick|pr] | every <SCHEDULE> [auto])` + options (`--repo`, `--dry-run`,
  `--max-chunks`, `--chunk-timeout-min`, `--idle-timeout-min`, `--log-dir`,
  `--sandbox`, `--approval-policy`, `--codex-bin`, `--codex-arg` with
  dangerous-arg scan, `--allow-direct-unattended`); hard-refuse
  `--dangerously-bypass-approvals-and-sandbox` as flag AND smuggled via `--codex-arg`;
  preflight (git residue incl. stash + stale worktree-registry, tracking-gitignored,
  direct-unattended refusal, direct-runner-residue, PR stale-root triage, cross-lane
  config conflict); mkdir-lock + owner file + EXIT trap; per-chunk snapshot → child
  (Python pumper with wall/idle timeouts, STREAMING tee) → validation ladder →
  summary.json; child nonzero → exit 26 with raw rc + last stderr in the summary
  (never raw passthrough); the child prompt template VERBATIM from the reference
  (values substituted); INLINED claim semantics per spec change 10; every-mode
  session persistence + `parse_schedule`; exit-code taxonomy (incl. 26) in `--help`;
  the `runner_stop_reason` stderr line on every terminal exit. All 15 named changes
  present.
- [ ] **1.2 — `scripts/porting/zskills-gate.sh`.** GATE-UNIFY per spec: four modes,
  fix-issues arm, tracking-root split, premature-final in-gate, `tests-run` required,
  `manual-verified` tolerated, current report patterns at the config-resolved path,
  final-verify pair at `post-land`, dirty-tree scan, read-only.
- [ ] **1.3 — `scripts/porting/post-run-invariants-codex.sh`.** Re-fork from current
  `skills/run-plan/scripts/post-run-invariants.sh` (235 lines at draft time — copy,
  then parametrize `--base-branch/--remote/--report`); `.zskills/landed`
  new-path-first dual-read.
- [ ] **1.4 — `tests/mocks/fake-codex.sh`.** Per the fake-codex reference: mode
  dispatch, prompt `- Label: value` parsing, argv log, exit-99 fail-fast, `--json`
  JSONL, resume semantics (same-id, mismatch, session-lost), `-o`/`--output-schema`,
  current-format artifact mutations, full failure-mode matrix (incl. `mid-run-stop`
  and `pr-wrong-tracking`), and the probe-id anchoring comments (reference item 6).
- [ ] **1.5 — `tests/test-porting-runner-preflight.sh`** — refusals: non-git repo;
  missing codex; dangerous bypass as flag AND via `--codex-arg`; lock contention
  (owner-file contents in the error); merge/rebase/cherry-pick residue; unresolved
  conflicts; stash residue; stale worktree-registry residue; tracking-not-ignored;
  direct refusal / direct-dirty / direct-runner-residue; PR stale-root ×3
  (not-a-worktree, foreign-repo, missing-plan); config precedence + cross-lane
  conflict; same-basename plan disambiguation; narrative-plan refusal; claim
  foreign-held refusal (fixture per spec change 10) + self-re-entry acquire success;
  dry-run purity (argv printed incl. `RUNNER-MANAGED CHUNK` prompt, zero tree
  mutation). Emits `Results:`; registered.
- [ ] **1.6 — Registrations:** one `run_suite` line in `tests/run-all.sh` (this
  phase's suite); runner + gate scripts (they inline the Python resolver) added to
  `RESOLVE_PYTHON_CONSUMERS` in `tests/test-hook-helper-drift.sh`.

### Design & Constraints

- **Salvage handling:** if the fork clones exist at the scratchpad paths named in
  settled decision 10 (`test -d` first), use them as reference/starting code; if
  absent, implement from this plan's spec — it is complete. Do NOT block on
  re-cloning private fork repos.
- The runner never invokes real `codex` in tests (`--codex-bin` points at
  fake-codex); the runner must not require zskills to be "installed" in the target
  repo beyond the `.zskills/` state contract (repo-agnostic).
- Report-path resolution: read `paths.reports` (or the current config key used by
  `zskills-paths.sh` — verify at implementation time) from the discovered config,
  falling back to the built-in default with an `# allow-hardcoded:` marker on the
  fallback literal.
- Scale expectation (not a gate): runner ~1,150–1,350 lines, gate ~200, invariants
  ~260, fake-codex ~500, preflight suite ~350–450. One commit.
- The runner's deep behavioral coverage arrives in Phase 2 — nothing downstream
  consumes the runner before Phase 2 completes (the scanner does not invoke it; the
  guide only CITES it). Do not treat Phase 1's preflight green as full validation.

### Acceptance Criteria

- [ ] `bash scripts/porting/zskills-runner.sh --help` → prints usage including both
  mode grammars and the full exit-code table (2, 20–26, 30, 31, 32, 124, 125).
- [ ] Dry-run purity: on a fixture repo,
  `bash scripts/porting/zskills-runner.sh run-plan <plan> finish auto --dry-run --repo <fixture>`
  → prints resolved child argv containing `exec` and the prompt containing
  `RUNNER-MANAGED CHUNK`; `git -C <fixture> status --porcelain | wc -l` → `0`.
- [ ] `bash scripts/porting/zskills-runner.sh run-plan <plan> finish auto --codex-arg --dangerously-bypass-approvals-and-sandbox --repo <fixture>; echo rc=$?`
  → `rc=2`, stderr names the refused flag.
- [ ] `bash tests/test-porting-runner-preflight.sh` → `Results: N passed, 0 failed`,
  where N equals the suite's own enumerated case count (the suite prints its case
  list; no external frozen integer).
- [ ] `grep -c 'run_suite "test-porting-runner' tests/run-all.sh` → `1`.
- [ ] fake-codex fail-fast: an unprepared invocation exits 99 (covered by a named
  case; quote the case name in the verifier report).
- [ ] Full suite via the capture idiom → 0 failed; per-suite counts reported.

### Dependencies

Phase 0 (the `scripts/porting/` scan widening must precede new scripts there).

## Phase 2 — Runner behavioral matrix: happy / failures / every suites

### Goal

Land the three behavioral suites that pin the validation ladder, the failure
taxonomy, and every-mode session semantics — the full matrix from the spec reference
(union of both forks' cases + the novel classes) passing in the container.

### Work Items

- [ ] **2.1 — `tests/test-porting-runner-happy.sh`** — single-chunk success
  (summary.json fields; argv assertions incl. "Do not invoke zskills-runner.sh
  again"); multi-chunk to completion (fresh child per chunk; argv-log count; NO
  `resume` token in finish-auto argv); re-entry after interruption (durable state,
  idempotent Step-0 semantics); **finish-auto mid-run stop** (fake-codex
  `mid-run-stop` mode writes the stop marker DURING chunk 1 → runner exits 31 before
  chunk 2 — the codex fork's original write-only stop-marker bug, pinned);
  streaming assertion (child progress text appears on parent stdout); frontmatter
  `status: complete` short-circuit; checkbox-format plan; stable tracking id across
  chunks + env export visible to child.
- [ ] **2.2 — `tests/test-porting-runner-failures.sh`** — no-progress (rc 20);
  missing-handoff (21); premature-final (21); missing verifier markers (23); missing
  `tests-run` (23); missing/malformed report (22); stale-marker replay (22); dirty
  artifacts (25); **child nonzero → rc 26** with the raw child rc + last stderr
  visible in `chunk-NNN.summary.json` (quote the summary fields); wall timeout
  (124); idle timeout (125); sandbox-triage output; max-chunks (30);
  **pr-wrong-tracking** (child writes tracking markers into the PR worktree instead
  of the repo root → validation catches the split-state, quoting the reason);
  `.zskills/landed` `conflict`/`pr-failed` hard-stop and `pr-ready` re-entry;
  claim-evidence-mismatch (schema mode); **stderr-reason discipline** — for EVERY
  mapped exit code exercised above, assert the final stderr line carries the
  matching `runner_stop_reason`.
- [ ] **2.3 — `tests/test-porting-runner-every.sh`** — stop marker pre-seeded → 31
  before fire 1; stop honored between fires; `parse_schedule` matrix (`30m`, `4h`,
  `every hour`, `weekday at 9am`, invalid → refusal); `next` output (fire time +
  session id + last verdict); session created once then N resumes with SAME id;
  resume-mismatch error; **session-lost hard stop exit 32 with no silent fresh-exec
  fallback** (assert argv-log contains no fresh `exec` after the loss); `auto` vs
  no-`auto` per-fire prompt difference (land-without-prompting vs
  land-with-confirmation text).
- [ ] **2.4 — Registrations:** three more `run_suite` lines in `tests/run-all.sh`
  (total four `test-porting-runner-*` suites).

### Design & Constraints

- Timeouts in tests use the `ZSKILLS_RUNNER_*` env overrides — never real 90-minute
  waits; fake-codex `sleep` mode + tiny overrides exercise 124/125.
- Four suites total (with Phase 1's preflight) to stay under the 600s parallel
  per-suite timeout.
- Fixes to the Phase-1 scripts discovered by the matrix are in-scope for this phase
  (same-plan, pre-consumption — not scope drift); note each in the commit message.
- Scale expectation (not a gate): ~1,000–1,200 suite lines total.

### Acceptance Criteria

- [ ] Each of the three suites: `bash tests/test-porting-runner-<name>.sh` →
  `Results: N passed, 0 failed`, where each suite's N equals its own enumerated case
  count (the suite prints its case list; no external frozen integer).
- [ ] `grep -c 'run_suite "test-porting-runner' tests/run-all.sh` → `4`.
- [ ] `grep -n 'session-lost\|stale-marker\|claim-evidence-mismatch\|mid-run-stop\|pr-wrong-tracking' tests/test-porting-runner-*.sh`
  → hits for all five named classes (the novel failure classes are tested).
- [ ] The rc-26 case output quotes `summary.json`'s recorded raw child rc (verifier
  report cites it).
- [ ] Full suite via the capture idiom → 0 failed; per-suite counts reported.

### Dependencies

Phase 1 (the scripts under test).

## Phase 3 — Construct scanner, converters, AGENTS.md renderer wrapper

### Goal

Build the discovery/gate scanner (`codex-scan.py`) on the zsh-fence-scan
architecture with the v1 construct classes; the agents→TOML and hooks.json
translators; and the AGENTS.md renderer wrapper with the 32 KiB dual-delivery check —
all repo-agnostic, all tested.

### Work Items

- [ ] **3.1 — `scripts/porting/codex-scan.py`.** Python 3 stdlib only. Architecture
  per `tests/lib/zsh-fence-scan.py`: data-driven class table (id, prose patterns,
  fence patterns, remedy string naming the guide recipe id), markdown fence state
  machine PLUS prose scanning (Claude constructs appear in prose, unlike zsh-isms),
  per-finding output lines (`<file>:<line>: [<class>] <match> → <remedy>`), one final
  machine-readable line
  `CODEX-SCAN-SUMMARY: files=<n> hits=<n> violations=<n> unknown=<n> per-class=<id>:<n>,…`,
  pure reporter (exit 0 always). Two modes:
  - `--mode discover <root>` — full report over a Claude tree (the porting worklist).
  - `--mode gate <root>` — reporter for a PORTED tree: any hit not covered by an
    inline allow-marker (line immediately above, stacking, same semantics as
    `allow-hardcoded`) counts as a violation. **Marker syntax dispatches on file
    extension, mirroring `allow-hardcoded`:** HTML-comment form
    (`<!-- codex-port-allow: <class> reason: … -->`) for `.md`; `#`-comment form
    (`# codex-port-allow: <class> reason: …`) for `.sh`/`.py`/`.toml` (an HTML
    comment is a syntax error in those files).
  - `--list-classes` — one class id per line (recipe-parity checks key on this).
  - Scan scope: `skills/**/*.md`, `agents/*.md`, `hooks/**`, `*.md` at root,
    `scripts/**` — configurable via `--scope`, defaulting to the porting-relevant
    set; skips `.git`, `docs/plans`, `docs/porting`, **`tests/**`**, **and the
    port meta-records** (both skip sets live in the scanner's data-driven
    default-skip list, next to the class table, with the rationale in a header
    comment — same treatment as WI 4.3's exemption note). The two exemptions:
    - `tests/**`: a Claude construct inside a test suite is the curated-registry
      recipe's jurisdiction (keep/drop/split rulings — a suite ASSERTING on a
      Claude-lane pin is test content, not shipped prose; see Phase 4's registry
      recipe), never a scanner violation. This keeps the scanner gate and the
      ported-tree suite triage from contradicting each other.
    - **Port meta-records, by exact ROOT-relative path:** `GAPS.md`,
      `DEGRADATIONS.md`, `PORT_MANIFEST.json`, `PORTING-NOTES.md` (path
      exclusion, NOT allow-markers — mechanical, no per-line marking of freeform
      prose). These files are the record OF the port (settled decision 3's
      port-instance layer) and MUST name Claude constructs to do their job:
      WI 12.1 REQUIRES `DEGRADATIONS.md` to contain `user-invocable` /
      `allowed-tools` / frontmatter-`hooks:` rows (verbatim `frontmatter-flags`
      match patterns), and `GAPS.md` is freeform gap prose that naturally names
      the constructs at issue. Scanning them would make Phase 12's whole-tree
      gate fail on artifacts Phases 11–12 themselves require — the same
      two-layer-store logic as the `tests/**` carve-out. The exclusion matches
      ONLY at the scanned root (`<root>/GAPS.md`, not `skills/*/GAPS.md`), so a
      hedge or construct smuggled into shipped prose cannot hide behind the
      basename.
- [ ] **3.2 — `scripts/porting/codex-scan-gate.sh`.** Fail-closed bash caller (the
  zsh-tripwire pattern). **Pinned CLI (later phases invoke it exactly this way):**
  `codex-scan-gate.sh <root> [--mode gate|discover] [--scope <path>…]` — default
  mode `gate`; `--scope` (repeatable, paths relative to `<root>`) passes through
  verbatim to `codex-scan.py --scope`, restricting the scan to the named subtrees
  (the slice phases' scoped-gate ACs depend on this). Behavior: runs gate mode,
  parses the summary line, exits 1 on `violations>0` OR `unknown>0` OR an
  unparseable summary; in discover mode enforces **anti-vacuous census floors** —
  fails if any class's hit count is below its floor. **Floor scope pin:** floors
  are derived from, and the census check runs over, the SAME scope — `skills/` of
  the tree under test (the scope Phase 3's AC and WI 3.6's census case actually
  run; deriving floors over the full default scope while checking over `skills/`
  would let a class concentrated outside `skills/`, e.g. `plugin-root`, set an
  unclearable floor). Floors are set at implementation time to ≤50% of the observed
  count from a `skills/`-scoped discovery run over THIS repo, and must be >0 for
  every class in the v1 table (satisfiable for `claude-model-dispatch` via its
  pinned ordinal-prose patterns, which have live hits under `skills/` — the class
  table's patterns are normative). Re-derivation, no frozen expectation of exact
  counts.
- [ ] **3.3 — `scripts/porting/agents-to-toml.py`.** Convert `agents/*.md` (Claude
  frontmatter + body) → `.codex/agents/<name>.toml`: `name`, `description`,
  `developer_instructions` = body; `model: inherit` → omit `model`; frontmatter
  `tools:` allowlist and `hooks:` blocks are NOT translatable — emit them to a
  degradations report (stdout section the porting agent pastes into the parity
  table). Output parseable by `tomllib`.
- [ ] **3.4 — `scripts/porting/hooks-translate.py`.** Translate `hooks/hooks.json` →
  `.codex/hooks.json`: same event/matcher/command structure (Codex's format is
  Claude-shaped); path rewrite `${CLAUDE_PLUGIN_ROOT}` → `--plugin-root-style
  {alias|native}` (alias keeps `CLAUDE_PLUGIN_ROOT` if the probe confirmed the
  compat alias; native rewrites to `${PLUGIN_ROOT}`); DROP entries whose event/tool
  has no Codex substrate (e.g. `PreToolUse:CronCreate` — no cron) listing each drop
  in a degradations section; emit a trust-review note (non-managed hooks are dead
  until the user trusts them — the install recipe must say so).
- [ ] **3.5 — `scripts/porting/render-agents-md.sh`.** Thin wrapper invoking the
  canonical `scripts/render-managed-rules.py --template <ported-template> --out
  <target>/AGENTS.md` (D24: extend, never fork — pass `--defaults`/`--config`
  through). After render: `wc -c` the output; if > 32768 bytes, exit 1 with the
  dual-delivery instruction ("split: short AGENTS.md + SessionStart-hook
  `additionalContext` delivery — see the guide's AGENTS.md recipe — or raise
  `project_doc_max_bytes`"). The wrapper does NOT transform content — content
  transformation is porting-agent work per the guide recipe.
- [ ] **3.6 — Test suites**, registered:
  - `tests/test-porting-scanner.sh` — fixture trees under
    `tests/fixtures/porting/`: per-class known-hit fixtures (every v1 class fires at
    least once); a clean fixture (gate exit 0); allow-marked fixtures in BOTH
    comment syntaxes (`.md` HTML form AND `.sh` `#` form — each suppresses its
    violation); an unknown-construct fixture (reported as `unknown` and gate exit
    1); a `--scope` case (gate over a fixture tree with a violation OUTSIDE the
    scoped path exits 0, and the same gate unscoped exits 1 — pins the WI 3.2
    pass-through the slice ACs depend on); a **meta-record exemption case** (gate
    over a fixture tree whose root `GAPS.md` + `DEGRADATIONS.md` contain
    class-matching text exits 0 with those files unscanned, AND the same text in
    a root `NOTES.md` — not on the exempt list — exits 1: pins the WI 3.1 path
    exclusion Phase 12's whole-tree gate depends on); census-floor check against
    the LIVE repo tree (discovery scoped to `skills/` must clear every floor —
    same scope the floors were derived from, per WI 3.2); summary-line format
    parse.
  - `tests/test-porting-converters.sh` — agents-to-toml: convert the real
    `agents/verifier.md`, `tomllib`-parse output, assert
    name/description/developer_instructions non-empty and degradations report names
    `tools:`; hooks-translate: translate the real `hooks/hooks.json` in both
    plugin-root styles, `json.load` output, assert zero `${CLAUDE_PLUGIN_ROOT}`
    residue in native style and dropped-entry listing; render-agents-md: render a
    small fixture template (success) and an oversize fixture (exit 1 with
    dual-delivery message).
- [ ] **3.7 — Register the new `.py`/`.sh` consumers** in
  `RESOLVE_PYTHON_CONSUMERS` where the resolver is inlined (the `.sh` wrapper);
  confirm the widened literal scan covers the new files (it does, from Phase 0.4 —
  add `# allow-hardcoded:` markers where the scanner's own class-table strings
  collide with fixture entries).

### Design & Constraints

- The scanner's class table is DATA (a list of dicts at the top of the file, or a
  sibling JSON) so the self-amendment rule (Phase 4) can append classes without
  restructuring code.
- The scanner is a REPORTER; policy lives in the bash caller — mirrors the
  zsh-scan/tripwire split exactly.
- `plugin-root` class subtlety: Codex ALIASES `CLAUDE_PLUGIN_ROOT` (probe
  `plugins.env.claude-plugin-root-alias`) — the class remedy is "verify alias per
  assumptions manifest, else rewrite", not unconditional rewrite. The GATE therefore
  accepts `CLAUDE_PLUGIN_ROOT` in ported HOOK files when the manifest says the alias
  passed AND the file carries the allow-marker citing it (`#` form — hooks are
  bash); skill prose still rewrites (skills are read by the model, not the hook
  runtime).
- Do not scan `docs/plans/**` or `docs/porting/**` (worked examples there
  legitimately contain Claude-isms) or `tests/**` (curated-registry jurisdiction,
  per WI 3.1).
- No edits to `tests/lib/zsh-fence-scan.py` (shared infra; model it, don't couple to
  it).

### Acceptance Criteria

- [ ] `python3 scripts/porting/codex-scan.py --list-classes | wc -l` → equals the
  class-table length and is ≥ 10 (v1 table).
- [ ] `python3 scripts/porting/codex-scan.py --mode discover skills/ | tail -1` →
  `CODEX-SCAN-SUMMARY:` line with `per-class` counts; every v1 class count > 0 on
  the live tree (quote the actual line in the verifier report; for
  `claude-model-dispatch` the hits come from the pinned ordinal-prose patterns).
- [ ] `bash scripts/porting/codex-scan-gate.sh tests/fixtures/porting/clean-tree && echo PASS`
  → `PASS`; same command against the unknown-construct fixture → non-zero, output
  names the file, line, and `unknown`.
- [ ] Both allow-marker fixtures (`.md` and `.sh` forms) gate clean; removing the
  marker from either makes the gate exit non-zero (quote both case names).
- [ ] `python3 scripts/porting/agents-to-toml.py agents/verifier.md --out "${TMPDIR:-/tmp}/v.toml" && python3 -c "import tomllib;d=tomllib.load(open('${TMPDIR:-/tmp}/v.toml','rb'));print(sorted(d))"`
  → prints keys including `description`, `developer_instructions`, `name`; stdout
  degradations section names `tools`.
- [ ] `python3 scripts/porting/hooks-translate.py hooks/hooks.json --plugin-root-style native --out "${TMPDIR:-/tmp}/h.json" && grep -c 'CLAUDE_PLUGIN_ROOT' "${TMPDIR:-/tmp}/h.json"`
  → `0`; the run's stdout lists each dropped entry with its reason.
- [ ] `bash scripts/porting/render-agents-md.sh --template tests/fixtures/porting/oversize-template.md --out "${TMPDIR:-/tmp}/AGENTS.md"; echo rc=$?`
  → non-zero rc; output contains `project_doc_max_bytes` and the dual-delivery
  instruction.
- [ ] `grep -c 'run_suite "test-porting-scanner\|run_suite "test-porting-converters' tests/run-all.sh` → `2`
  (open-ended prefixes — the registry's name argument carries `.sh`, so a closing
  quote after `scanner`/`converters` would never match).
- [ ] Both suites → `Results: N passed, 0 failed`; full suite via capture idiom → 0
  failed.

### Dependencies

Phases 0–2 (scan widening; the scanner's `cron` remedy cites the runner).

## Phase 4 — Probe triage + the porting guide (`docs/porting/`)

### Goal

Ingest the owner's probe results with a TRIAGE step that converts failed or deviant
load-bearing probes into named rework (or a STOP) before anything is baked into the
reusable artifact; then write the primary deliverable: a porting guide an agent can
follow, with zero other context, in ANY zskills-descendant repo — principles, one
recipe per scanner class with worked before/after examples, the sliced first-port
procedure, degradation policy + parity-table template, the assumptions manifest,
delta-port procedure, and the self-amendment rule.

### Work Items

- [ ] **4.0 — Gate on the probe artifact (ORCHESTRATOR pre-dispatch step — the
  implementer has no Cron tools and cannot execute the Failure Protocol).** Before
  dispatching this phase, the orchestrator: (1) brings the phase worktree current —
  `git fetch origin`, then rebase the worktree branch onto the plan's integration
  branch (`origin/main` in cherry-pick/direct landing; the plan-scoped PR branch in
  PR landing — the branch WI 0.7 told the owner to commit to; the finish-mode
  worktree is REUSED across fires and otherwise predates the owner's commit); a
  rebase conflict here is a STOP-and-surface. (2) `test -f
  docs/porting/probe-results.json`. Absent ⇒ invoke the **Failure Protocol** (halt
  the pipeline, DELETE the armed cron via CronList/CronDelete, surface: "Phase 4
  requires the owner-produced probe results at docs/porting/probe-results.json —
  run Phase 0 WI 0.7") — explicitly NOT run-plan Step 4's recoverable
  dependency-retry (see Execution context; the Dependencies section below restates
  this). Present ⇒ dispatch; the implementer's own first action re-checks and runs
  `bash scripts/porting/codex-probe.sh --validate docs/porting/probe-results.json`,
  then WI 4.0b. If the implementer nonetheless finds the file absent, it reports
  `FAILED-OWNER-GATED: probe results absent` and stops — the orchestrator MUST
  translate that report into the Failure Protocol, never into a retry.
- [ ] **4.0b — Probe triage (results-ingestion with rework triggers).** For every
  probe id whose status is `fail` or `skip`, or whose `observed` deviates from
  `expected`, consult the triage table below and take the named action. The table is
  the plan's contract — the implementer does not invent routings:

  | Probe id(s) | Dependent artifacts | On fail/deviation |
  |---|---|---|
  | `exec.resume.same-session`, `exec.resume.prompt-and-json`, `exec.json.thread-id` | Runner every-mode (spec changes 11–12), fake-codex resume/JSONL modes, `test-porting-runner-every.sh` | **STOP (Failure Protocol)** — the every-mode substrate is broken; surfacing options (redesign every-mode, drop it from v1) is an owner decision, not an in-phase rework |
  | `exec.resume.session-loss` | Runner exit-32 semantics, fake-codex `session-lost` mode | Rework in-phase: align runner/mock/suite to the observed loss signature |
  | `exec.output-last-message`, `exec.output-schema` | Runner JSON+SCHEMA change 12, fake-codex output modes | Rework in-phase: adjust or drop the schema self-report layer (evidence layer is unaffected) |
  | `hooks.pretooluse.deny-envelope`, `hooks.pretooluse.exit2-stderr`, `hooks.stdin.permission-mode` | Hook recipe, hooks-translate, capability map | **STOP (Failure Protocol)** — mechanical enforcement (settled decision 6) has no substrate |
  | `hooks.pretooluse.updated-input` | Hook recipe (timeout-injection analog) | Rework in-phase: mark the construct a named degradation in the recipe |
  | `hooks.sessionstart.additional-context` | AGENTS.md dual-delivery recipe | Rework in-phase: recipe falls back to `project_doc_max_bytes` raise as primary; **if `agentsmd.project-doc-max-bytes-raise` ALSO failed ⇒ STOP (Failure Protocol)** — no delivery path exists for an over-cap rules template (same both-fail shape as the discovery row below) |
  | ONE of `skills.discovery.agents-dir` / `skills.discovery.claude-skills-path-config` failing (the other passing) | Install recipe | Rework in-phase: the install recipe pins the SURVIVING mechanism as primary and records the failed one as a named degradation |
  | `skills.discovery.agents-dir` AND `skills.discovery.claude-skills-path-config` BOTH failing | Install recipe | **STOP (Failure Protocol)** — no skill-discovery substrate |
  | `skills.invocation.*`, `skills.openai-yaml.*`, `skills.frontmatter.unknown-ignored` | Install + frontmatter-flags recipes | Rework in-phase: adjust the recipe to the observed invocation surface |
  | `plugins.env.claude-plugin-root-alias`, `plugins.marketplace.claude-compat` | hooks-translate default style, scanner `plugin-root` remedy + gate acceptance rule | Rework in-phase: flip the default to `native` rewrite; update recipe + gate rule |
  | `agents.toml.*`, `agents.limits.max-depth` | agents-to-toml, agent-dispatch recipe | Rework in-phase: adjust converter/recipe; new degradation entries as needed |
  | `agentsmd.cap-32k`, `agentsmd.project-doc-max-bytes-raise` | AGENTS.md recipe parameters | Rework in-phase: recipe records the observed cap/raise behavior |
  | `sandbox.workspace-write.add-dir` | Runner PR-DUAL-ROOT `--add-dir` (change 6) | Rework in-phase: adjust the runner's worktree-parent add-dir mechanism |
  | `hooks.trust.non-managed-friction` | Install recipe trust note | Doc-only: record observed friction verbatim |

  Rework mechanics: probe-triggered edits to `scripts/porting/**` and `tests/**` are
  authorized WITHIN this phase (they are the ingestion, not scope drift), obey the
  two-attempt limit, and annotate the affected earlier phase's tracker Notes with
  `probe-rework: <ids>`. EVERY deviation — reworked or not — is recorded in the
  assumptions manifest with the observed value. A `skip` on a load-bearing id is
  triaged as a fail (the capability is unverified; proceeding would rebuild the
  fake-codex circularity this step exists to break).
- [ ] **4.1 — `docs/porting/CODEX_PORTING.md`** (the guide root). Sections:
  - **Principles** (from the settled decisions, restated for a fresh agent): full
    bodies never wrappers; mechanical enforcement over prose; explicit named
    degradations; discovery-driven, construct-class-based, fork-general; the
    two-layer decision store (general conventions HERE; port-specific judgments in
    the ported repo's provenance manifest + notes).
  - **Assumptions manifest**: the probe-result capabilities the recipes depend on,
    keyed by probe id, each with its observed value from
    `docs/porting/probe-results.json` and a re-verify instruction
    (`codex-probe.sh --only <id>`) to run when Codex versions move.
  - **Tree-scope table** (port scope is defined at the TREE level, not guessed
    per-file): for every top-level path in a zskills-descendant repo, a default
    disposition — `skills/` port; `hooks/` port; `agents/` port (convert);
    `scripts/` port — the top-level helper scripts (versioning helpers, renderer,
    `_lib/`; the recipes DEPEND on them — the frontmatter-flags recipe's
    pre-commit hook and the AGENTS.md renderer both call ported `scripts/` files)
    with the porting-toolkit subdirs (`scripts/porting/`) n/a (the toolkit stays
    upstream; the toolkit-install unit re-installs the runner/gate/invariants);
    `tests/` curated (see registry recipe);
    `CLAUDE_TEMPLATE.md` port (rules template); `.claude-plugin/` adapt
    (marketplace compat — Codex reads the legacy `marketplace.json` per the
    assumptions manifest); `docs/plans/`, `docs/porting/`, `.claude/`, `.github/`,
    `PRESENTATION.html`/`index.html`, repo-meta files → drop or n/a, each with one
    line of reasoning. The provenance manifest carries per-file rows ONLY for
    ported paths plus ONE summary row per dropped subtree (not 1,000 rows of
    noise). Discovery re-derives the actual top-level set (`ls -d */`) and routes
    unknown paths to agent judgment + a manifest row.
  - **First-port procedure** (numbered, agent-executable, SLICED): the procedure is
    designed for execution by MULTIPLE sequential fresh agents, each given only
    this guide plus a slice assignment — no single agent can hold the whole port:
    1. *Worklist build* (setup agent): run `codex-scan.py --mode discover` over the
       source tree and persist its per-file hit list as the scan baseline; measure
       per-skill volume — **volume = markdown lines only:
       `find <unit> -name '*.md' -type f | xargs wc -l`** (scripts pass through
       mostly verbatim; porting effort tracks prose + scanner hits, so md-only is
       the budget basis — state this basis in the worklist); balance skills into
       slices under a stated line budget (default ≤ ~7,000 markdown lines per
       slice; non-skill units — hooks / agents / rules / config / toolkit-install
       / top-level scripts helpers / plugin-manifest compat / test-registry /
       manifest-skeleton — are converter-, translator-, or copy-driven and exempt
       from the markdown budget); emit a
       worklist file recording source SHA, the RESOLVED ABSOLUTE port-root path
       (the literal string later git commands embed — see the per-slice step's
       invocation-form rule), the port branch name, slice
       assignments, and per-unit records (see the schema the procedure names:
       `status` `pending|done|failed`, per-file `dispositions`, `degradations`,
       per-hit `hits` — the assembly phase consumes these fields MECHANICALLY).
       **Baseline↔unit reconciliation (mechanical, before any slice runs):**
       every file in the scan baseline must map to exactly ONE worklist unit or
       ONE dropped-subtree row of the tree-scope table; an unmapped baseline file
       is a worklist-build ERROR to fix before slices start — it means a path the
       tree-scope table promises to port has no executor, and the assembly
       phase's hit-parity check would otherwise fail (or silently skip) on it.
    2. *Per-slice execution* (one fresh agent per slice): **invocation-form rule
       for every target-clone git WRITE** (add/rm/checkout/commit/push): a SINGLE
       compound command with a LITERAL absolute cd — copy the worklist's recorded
       absolute port-root string into the command:
       `cd /abs/literal/path/to/target && git …`. Never a variable cd
       (`cd "$VAR"`), never a bare `git` relying on a previous command's cwd,
       never `git -C` for commits — the host repo's safety hooks resolve the repo
       they gate from the LITERAL cd token and fall back to the AMBIENT repo
       otherwise, denying correct port-branch commits on spelling alone.
       Read-only queries (`log`, `rev-parse`, `status`) may use `git -C`.
       **Resume preamble first** — line 0: re-assert the branch —
       `git -C <target> rev-parse --abbrev-ref HEAD` must equal the worklist's
       `port_branch`; if not, restore it
       (`cd /abs/literal/path/to/target && git checkout <port_branch>`) before
       anything else. Then reconcile the worklist against the target clone's log
       (`git -C <target> log --oneline`): any unit with a `port: <unit>` commit is
       `done`; a unit left half-edited by a dead prior attempt is redone from
       scratch (re-copy verbatim from source over the target dir — copy-first
       makes redo idempotent; never use history-rewriting cleanup); any
       UNCOMMITTED `GAPS.md` content surviving from a dead attempt is salvaged
       now — commit it (`port: gaps (resume salvage)`) before starting new units,
       so recorded gaps are never silently lost. Then, for each
       remaining unit — COPY the unit verbatim into the ported tree first
       (`cp -r`; full bodies are preserved by construction), then walk the scan
       baseline's per-file hit list for that unit, applying the per-class recipe
       at each hit site (hit-driven editing keeps the agent's context on the
       constructs, not the prose bulk) and recording, per hit site, the
       disposition taken (`hit → recipe → replacement construct or degradation
       id`) in the unit's worklist record; convert agents (`agents-to-toml.py`) /
       translate hooks (`hooks-translate.py`) / render AGENTS.md
       (`render-agents-md.sh`) where the slice includes them; re-stamp
       `metadata.version` on every recipe-edited skill (fresh date + content hash
       via the SOURCE tree's `scripts/skill-content-hash.sh` +
       `scripts/frontmatter-set.sh` — ported content is new content); commit each
       completed unit to the target clone **on the worklist's port branch, never
       the target's default branch** (`port: <unit>`, in the pinned literal-cd
       compound form above); update the unit's worklist
       record (status, per-file dispositions, degradation entries); record every
       judgment call in the porting notes and every guide ambiguity in `GAPS.md`.
       **GAPS.md durability contract:** gap entries recorded while porting a unit
       are STAGED INTO that unit's `port: <unit>` commit (add `GAPS.md` alongside
       the unit's paths — the commit is the durable cursor for gaps exactly as it
       is for content); at slice end `GAPS.md` must be CLEAN in the target
       clone's `git status`. A gap entry that only ever lives in the working tree
       is lost undetectably on a crash — a lost gap looks identical to "no gap".
    3. *Assembly* (final agent): build/verify the provenance manifest + degradation
       table from the accumulated dispositions; run the scanner gate
       (`codex-scan-gate.sh`) over the whole tree; run the ported tree's own
       suite; hand back the gap list (every gap = a guide defect to fix upstream).
    Also: install the runner + gate + invariants from `scripts/porting/`; port
    the repo's top-level `scripts/` helpers per the tree-scope row (the
    versioning + renderer helpers the recipes depend on); adapt `.claude-plugin/`
    per its tree-scope row; build the
    curated test registry (registry recipe); the trust-review note for hooks.
  - **Delta-port procedure**: three-way diff (Claude@prior-SHA from the provenance
    manifest, Claude@now, Codex@prior); unchanged-at-source files →
    **byte-verbatim carry-forward** (`cmp`-verified); changed/new → agent judgment
    per recipes; deleted → remove; re-run scanner gate + suite; update manifest.
  - **Self-amendment rule**: an unknown construct class ⇒ agent makes a ruling ⇒ the
    ruling is APPENDED to this guide as a new recipe AND added to the scanner's
    class table in the same change; unknown instances of known classes port
    mechanically by recipe without amendment.
  - **Degradation policy**: every capability Claude had and Codex lacks gets a named
    entry in the parity table (template included: construct | Claude behavior |
    Codex behavior | degradation class `exact|adapted|degraded|absent` | mitigation);
    NEVER a runtime hedge ("if available… otherwise") in ported prose.
  - **Version pairing**: a RELEASE-procedure port carries the SAME `YYYY.MM.N`
    version as the Claude release it ports, recorded in the provenance manifest.
    A port whose source is NOT a release tag (the first port ports a dev
    snapshot) records `ported_from_version: "dev@<sha12>"` (the first 12 chars of
    `ported_from_sha`) — never an invented or approximated `YYYY.MM.N`; only
    release-procedure ports carry the paired form.
- [ ] **4.2 — `docs/porting/recipes/<class-id>.md`** — one file per scanner class
  (filenames exactly matching `codex-scan.py --list-classes` output). Each recipe:
  the construct, why it can't survive, the Codex-side answer, at least one worked
  **Before** (Claude form) / **After** (Codex form) fenced example, edge cases, and
  the degradation-table entry it produces (if any). Load-bearing recipe content
  settled by this plan:
  - `cron` → the runner IS the scheduler; the ported run-plan's Phase 5c writes
    `handoff.run-plan.$TID`/final markers instead of CronCreate (PHASE-5C-CONTRACT,
    spec §change 9), preserving the idempotent Step-0 re-entry verbatim; `every`
    grammar maps to runner every-mode; skills whose recurring mode is peripheral
    (`/briefing`, `/qe-audit`, `/do`) document manual re-invocation.
  - `agent-dispatch` → **one mechanism per construct class, pinned — never
    "and/or" left to the porting agent** (three slices exercise this recipe
    independently and their outputs must compose): (a) verifier/implementer
    dispatch = `codex exec` child processes ALWAYS (fresh context preserved — the
    POINT of the verifier; also immune to the `max_depth: 1` subagent-nesting
    limit); (b) conversational review roles (reviewer / devil's-advocate /
    refiner and other single-conversation subagents) = native
    `.codex/agents/*.toml` referenced by the TOML `name` that `agents-to-toml.py`
    emits (the recipe states the converter's naming rule so prose references
    written in early slices resolve against TOMLs converted in a later slice);
    `tools:` allowlist and per-agent hooks are named degradations;
    `isolation: "worktree"` → explicit `git worktree` via the already-portable
    `create-worktree` scripts. The recipe also states the composition constraint:
    a skill ported as a native-subagent orchestration cannot itself be dispatched
    as a subagent under `max_depth: 1` — such skills stay `codex exec`-driven at
    the top level.
  - `skill-tool` → read-the-SKILL.md-and-execute-inline (zskills' own validated
    cron-fire fallback), plus guidance to push mechanical logic into bundled
    scripts to protect caller context.
  - `arguments` → Codex skill invocation text ("Treat everything after the skill
    name as `$ARGUMENTS`"); keep `$ARGUMENTS` parse fences (they are plain bash once
    the variable is bound).
  - `plugin-root`/`project-dir` → per assumptions manifest: hooks may keep the
    `CLAUDE_PLUGIN_ROOT` alias if probed-pass; skill prose resolves via the ported
    root-resolution helper (git-fallback primary).
  - `frontmatter-flags` → `disable-model-invocation` → `agents/openai.yaml`
    `policy.allow_implicit_invocation: false`; `user-invocable: false` → named
    ABSENT degradation + prose convention; `metadata.version` → **LIVE, re-stamped
    at port time**: a recipe-edited skill is new content and gets a fresh
    `YYYY.MM.DD+<hash>` via the SOURCE tree's `scripts/skill-content-hash.sh` +
    `scripts/frontmatter-set.sh` (both harness-neutral bash that also port with
    `scripts/` — the tree-scope `scripts/` row, executed as its own non-skill
    worklist unit in the first-port procedure, so the ported tree actually
    carries them); the ported repo keeps the versioning discipline — every
    subsequent skill edit bumps the stamp — enforced by the git pre-commit hook
    the recipe includes (the Claude-side PreToolUse stage-check has no Codex
    analog; the pre-commit hook is its ported enforcement point, and it calls
    the PORTED tree's own `scripts/` helpers).
  - `bg-monitor` → delete prohibitions that guard Claude-only reflexes; the runner's
    timeout model replaces Layer-0.
  - `ask-user` → plain-prose questioning.
  - `claude-model-dispatch` → Codex `model`/`model_reasoning_effort` config or
    delete.
  - AGENTS.md delivery (part of the rules recipe): **dual delivery** — a short
    AGENTS.md (pointer + always-on essentials) + full rules via SessionStart-hook
    `additionalContext` (byte-parallel to the current plugin lane's
    `session-rules-context.sh`), with `project_doc_max_bytes` raise documented as
    the single-file alternative; rendered through `render-agents-md.sh`.
  - Install recipe: ported repo keeps `skills/` as source with an installer copying
    to `.agents/skills/` (the legacy-lane model — its installer logic is the part
    that ports), `[[skills.config]]` pointing at `.claude/skills` documented as the
    probe-dependent alternative; hooks installed to `.codex/hooks.json` with the
    trust-review step called out; config discovery order matching the runner's
    (spec §change 15).
  - Ported-tree test registry recipe (**keep / drop / SPLIT — three dispositions,
    drop-by-default**): the port ships its own `tests/` with a CURATED `run-all.sh`
    registry. Default disposition for a source suite is DROP (recorded as one
    summary line in the porting notes + a reasoned allowlist entry where the
    registration-completeness gate needs one). The named KEEPER FLOOR (kept and
    expected green in the port): the registration-completeness gate (regenerated
    registry), the tmpdir-hardcode guard, the provenance-header machinery, and the
    harness-neutral half of `test-skill-conformance.sh`. SPLIT is the third
    disposition, and `test-skill-conformance.sh` is the worked example the recipe
    walks: its forbidden-literals scan, `Results:`-line discipline, fence checks,
    and version-stamp checks are harness-neutral (keep, retargeted); its
    impl-dispatch pins (`subagent_type: "implementer"` in six named files),
    plugin-manifest/marketplace assertions, mirror-parity, managed-md, and
    agents-parity sections assert Claude-harness surfaces the port drops or
    rewrites (drop, or rewrite to assert the ported dispatch construct). Keep
    decisions are enumerated by the criterion "asserts harness-neutral behavior",
    never by frozen list. **Reconciliation with settled decision 7's
    "harness-agnostic test suites run against the ported tree":** drop-by-default
    applies to harness-COUPLED suites — a suite matching the harness-neutral
    criterion is a KEEP, and the constraint is honored through the keeper floor
    plus every suite the SPLIT recipe retargets. Stated honestly: because a
    keep-by-keep triage of the full source registry is out of scope for the
    first port, the first port's kept set is expected to be MATERIALLY SMALLER
    than the source tree's ~130 harness-agnostic suites — the floor plus the
    suites whose harness-neutrality is evident without deep per-suite
    evaluation. That narrowing is deliberate and is surfaced to the owner as
    named residue (widening the kept set is a follow-up registry re-triage, not
    a first-port gate); it is recorded in the porting notes, never silently.
  - Provenance manifest format: `PORT_MANIFEST.json` — `ported_from_sha`,
    `ported_from_version`, `toolkit_sha`, `probe_results_fingerprint`, `ported_at`,
    per-file dispositions (`verbatim|adapted|degraded|dropped|new`) for PORTED
    paths + one summary row per dropped subtree (per the tree-scope table),
    degradation table pointer, per-skill notes pointer.
- [ ] **4.3 — `tests/test-porting-guide.sh`** (registered): recipe↔class parity
  (`codex-scan.py --list-classes` vs `ls docs/porting/recipes/*.md` basenames —
  exact set match); every recipe contains both a `Before` and an `After` fence;
  fork-generality tripwires — `grep -rn` over **the REUSABLE artifacts only:
  `docs/porting/CODEX_PORTING.md` + `docs/porting/recipes/`** — for the target repo
  name (`zskills-codex-f`), for `\b23 skills\b`, and for hedge-prose
  (`only when.*insufficient`, `otherwise run inline`) → all zero.
  **`docs/porting/notes/**` and `docs/porting/*-results.json` are exempt BY
  DESIGN** — they are the port-specific instance-record layer (settled decision 3's
  two-layer store) and legitimately name the target repo (the porting notes' most
  important fact is where the port went; the results JSONs record observed paths).
  State the exemption in the suite's header comment so a future editor doesn't
  re-tighten it. Also: guide names the self-amendment rule; assumptions manifest
  cites every probe id present in `codex-probe.sh --list`.

### Design & Constraints

- **The guide is the porting agent's ONLY context** (Phases 6–11 enforce this) —
  every recipe must be self-sufficient: no references to this plan, to research
  files, or to fork clones. Toolkit invocations are given as exact commands.
- Fork-general: no repo names, no skill enumerations, no frozen counts — re-derivation
  commands only (e.g. "for every dir under `skills/`…"). The sliced procedure's
  worklist builder derives slices from measurement, never from a skill list.
- `docs/porting/` is catalog-inert (no doc-viewer registration needed); keep dev-repo
  URLs out (release-time URL walk rewrites docs/ — anything intentionally dev-pointing
  needs `zskills-dev-url-allow`).
- Worked examples SHOULD quote real current zskills constructs (verified against the
  tree at write time), marked as illustrative snapshots, not normative inventories.
- This phase's commit may touch `scripts/porting/**` and `tests/**` ONLY via WI
  4.0b probe-rework (annotated as such in the commit message).
- **Scope acceptance (eyes open):** this is one of the two largest single
  dispatches left in the plan (triage + guide root + ≥10 worked recipes + parity
  suite — plausibly 2,000+ authored lines, in one 2-hour implementer). Accepted
  deliberately, with cursor-style partial completion PRE-AUTHORIZED for the recipe
  files: they are independently committable, so an attempt that runs out of
  context commits the finished recipes + guide root, reports the phase INCOMPLETE
  naming the missing recipe files, and attempt 2 writes ONLY the remainder (the
  recipe↔class parity AC is the completeness gate). Incomplete after attempt 2 ⇒
  STOP per the two-attempt rule.

### Acceptance Criteria

- [ ] `test -f docs/porting/probe-results.json && bash scripts/porting/codex-probe.sh --validate docs/porting/probe-results.json && echo GATED-OK`
  → `GATED-OK` (if this fails the phase must have STOPped via the Failure Protocol,
  not completed).
- [ ] Probe triage evidence: the verifier report lists every probe id with
  fail/skip/deviant status and, for each, the triage-table action taken (rework
  commit ref, STOP, or doc-only manifest entry). Zero such ids ⇒ state that
  explicitly.
- [ ] `diff <(python3 scripts/porting/codex-scan.py --list-classes | sort) <(ls docs/porting/recipes/ | sed 's/\.md$//' | sort) && echo PARITY`
  → `PARITY`.
- [ ] `grep -rEn 'zskills-codex-f|only when .{0,40}insufficient|otherwise run inline' docs/porting/CODEX_PORTING.md docs/porting/recipes/ | wc -l`
  → `0`.
- [ ] `grep -c 'Before' docs/porting/recipes/*.md | grep -c ':0$'` → `0` (every recipe
  has a worked example; same check for `After`).
- [ ] `grep -n 'self-amend' docs/porting/CODEX_PORTING.md` → at least one hit in the
  procedure text.
- [ ] `grep -n 'keep / drop / SPLIT\|keep/drop/split' docs/porting/recipes/*.md` → the
  registry recipe carries the three-disposition rule (case-insensitive match
  acceptable; quote the line).
- [ ] `bash tests/test-porting-guide.sh` → `Results: N passed, 0 failed`;
  `grep -n 'test-porting-guide' tests/run-all.sh` → registered.
- [ ] Full suite via capture idiom → 0 failed.

### Dependencies

Phases 0–3, **plus the owner-produced `docs/porting/probe-results.json` reachable
on the plan's integration branch** (WI 4.0 pins the fetch+rebase+`test -f` check).
**ORCHESTRATOR NOTE — read this before classifying a missing file:** an absent
probe-results file is NOT the recoverable dependency-not-met STOP of run-plan
Step 4 (which leaves the cron alive to retry). Only the owner can produce this
file; retrying is an unbounded `*/1` spin. Absent ⇒ Failure Protocol: DELETE the
armed cron (CronList/CronDelete), halt the pipeline, and surface the WI 0.7
instruction. See WI 4.0 and Execution context ("Downstream gating").

## Phase 5 — First-port setup: port root, source snapshot, target clone, slice worklist

### Goal

Materialize the durable state every port phase depends on: the gitignored PORT_ROOT,
a source snapshot pinned at the recorded SHA (so the port is immune to main moving
between slice phases), the target-repo clone with auth triage, and the slice
worklist that Phases 6–11 execute.

### Work Items

- [ ] **5.1 — PORT_ROOT + pinned MAIN-REACHABLE source snapshot.** Resolve
  `MAIN_ROOT="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"`;
  `PORT_ROOT="$MAIN_ROOT/.zskills/porting/first-port"`;
  `mkdir -p "$PORT_ROOT/source"` (tar's `-C` does not create the directory).
  **The recorded SHA must be reachable from `origin/main` in a fresh clone
  forever** — it anchors every future delta port; the phase worktree's HEAD is a
  PR-branch tip that a squash-merge landing makes unreachable. So:
  `git fetch origin main; SNAP_SHA=$(git rev-parse origin/main)`, record
  `$SNAP_SHA`, and materialize
  `git archive "$SNAP_SHA" | tar -x -C "$PORT_ROOT/source"` (a plain tree — no
  worktree registry entry, no checkout in the main tree). Porting origin/main's
  content is correct by construction: this plan touches no `skills/**`, `hooks/**`,
  `agents/**`, or `CLAUDE_TEMPLATE.md` (invariant 2), so the branch tip and
  origin/main agree on every PORTED path — and the snapshot stays free of the
  branch's mid-plan toolkit/doc churn. Record a snapshot immutability fingerprint:
  `git archive "$SNAP_SHA" | sha256sum` → `source_snapshot_sha256` in the
  worklist. The TOOLKIT actually used (worktree copy) is recorded separately as
  `toolkit_sha` (worktree HEAD) in the manifest — advisory provenance, not a delta
  anchor. All slice phases read from `$PORT_ROOT/source`, never from the live
  checkout. **Record the RESOLVED ABSOLUTE `PORT_ROOT` value** (the expanded
  literal path, not the `$PORT_ROOT` spelling) in the worklist as `port_root` —
  it is the literal string every later target-clone git WRITE embeds in its
  pinned `cd /abs/literal/path && git …` compound (Execution-context port-branch
  rule item 2).
- [ ] **5.2 — Target clone, PORT BRANCH, auth triage.** Clone the target into
  `$PORT_ROOT/target`: `gh repo clone zeveck/zskills-codex-f "$PORT_ROOT/target"`.
  - Clone fails for auth (private-repo READ unavailable) ⇒ `git init
    "$PORT_ROOT/target"` and record "remote wiring + push" as a named
    ATTENDED-PENDING item (tracker Notes + follow-up issue) — do not improvise.
  - Clone succeeds ⇒ verify push access with `git -C "$PORT_ROOT/target" push
    --dry-run origin`; if push auth is unavailable, note now that Phase 13's push
    will take the bundle fallback (WI 13.4) — the phase still proceeds.
  - **Either way, create and check out the dedicated port branch** — in the
    pinned invocation form (port-branch rule item 2), with the resolved literal
    path: `cd <resolved-absolute-port-root>/target && git checkout -b
    port/first-port` (one compound; the literal path is the value WI 5.1 just
    recorded as `port_root`). ALL later
    target-clone commits happen on this branch (Execution-context port-branch
    rule); the branch name is recorded in the worklist as `port_branch`.
  - **Never write `.zskills/tracked` (or any zskills tracking state) into the
    target clone.** The target clone is not a zskills pipeline root; a tracked
    marker there would newly associate the hooks' tracking tier with the clone
    and arm marker enforcement against commits this plan authorizes.
- [ ] **5.2b — Smoke-test one commit into the target clone, in the EXACT pinned
  invocation form** (Execution-context port-branch rule item 2 — the same form
  the guide's per-slice step prescribes): ONE compound command whose `cd` target
  is the LITERAL absolute path copied from the worklist's `port_root` —
  `cd <resolved-absolute-port-root>/target && git add … && git commit -m
  "port: seed (setup)"` — never a `$VAR` cd, never a bare `git commit` in a
  later Bash call, never `git -C` (a variable/ambient spelling makes the hooks
  evaluate THIS repo on `main` and deny; a smoke that passed on a different
  spelling would prove nothing about the slice agents' pinned form). The seed is
  TWO files: a one-line `README.md` naming the port branch and provenance, AND a
  one-line `seed.json` (e.g. `{"port_seed": "<SNAP_SHA>"}`) — the `.json` file
  is load-bearing: the hooks' tracking block only evaluates when the staged diff
  contains code-classed files (`js|ts|json|css|html|rs|py|go|rb`), and every
  real slice commit stages such files, so a markdown-only smoke would skip the
  very gate arm this smoke exists to exercise. The commit must SUCCEED. This
  phase's agent may read the plan, so the commit-gating interaction
  (main-protection, stale-skill-version, tracking) is discovered HERE by a
  plan-aware setup agent, never mid-slice by a guide-only agent. A deny
  envelope ⇒ classify per the port-branch rule item 5 (spelling FIRST — re-issue
  once as the literal-cd compound; only then check the branch state), retry
  once; still denied ⇒ STOP and surface with the verbatim deny reason.
- [ ] **5.3 — Slice worklist + scan baseline.** Run `python3
  scripts/porting/codex-scan.py --mode discover "$PORT_ROOT/source"`, persist the
  FULL per-file hit list as `docs/porting/notes/first-port/scan-baseline.txt`
  (committed — Phase 12's hit-parity check reads it), and build
  `docs/porting/notes/first-port/worklist.json` per the guide's worklist-builder
  procedure:
  `{"source_sha": …, "source_snapshot_sha256": …,
  "port_root": <RESOLVED ABSOLUTE literal path — WI 5.1>,
  "port_branch": "port/first-port", "volume_basis": "md-lines",
  "slices": {A|B|C|D|E|F: [units…]},
  "units": {<unit>: {"status": "pending", "files": N, "md_lines": N,
  "dispositions": {}, "degradations": [], "hits": {}}}}` — `dispositions`
  (per-file `verbatim|adapted|degraded|dropped|new`), `degradations` (named
  degradation-table entry ids), and `hits` (per hit site
  `"<file>:<line>": {"class": …, "resolution": …}`) start EMPTY and are filled
  per-unit by the slice agents at port time; slice F and Phase 12 consume them
  MECHANICALLY (manifest rows, DEGRADATIONS.md, hit-parity) — never reconstructed
  from freeform prose. **Volume measurement is MARKDOWN-ONLY** (the budget basis
  the guide pins: `find <unit> -name '*.md' -type f | xargs wc -l`); whole-dir
  `wc -l` is NOT the basis (it would put every declared slice over threshold on
  day one — slice E alone is ~20k whole-dir lines vs 7,933 md lines). Slice
  assignments MUST match the Progress Tracker's declared slices (Phases 6–11).
  Non-skill units (slice F) are converter/translator/copy-driven and exempt from
  the md-line budget; slice F carries the NINE non-skill units named in WI 11.1
  (hooks, agents, rules, config, toolkit-install, scripts-core, plugin-compat,
  test-registry, manifest-skeleton). **Baseline↔unit reconciliation (guide
  worklist-builder rule, executed here):** every file in the scan baseline maps
  to exactly ONE worklist unit or ONE dropped-subtree row of the tree-scope
  table; run the mapping check and fix any unmapped file BEFORE declaring the
  worklist built — an unmapped baseline file is a promised-but-executor-less
  path that Phase 12's hit parity would otherwise fail on (or silently miss).
  A skill present in the live tree but absent from the declared
  slices (added since draft time) is assigned to the smallest slice and the
  reconciliation recorded in the worklist + tracker Notes; if any SKILL slice's
  measured md-line volume exceeds ~8,500 after reconciliation, STOP and surface
  (rebalancing the phases is a `/refine-plan` decision, not an improvisation).
  **Known accepted overage:** slice E measures 7,933 md lines at draft time —
  above the ~7,000 budget, below the 8,500 STOP; accepted deliberately (lowest
  construct density), not a STOP condition.
- [ ] **5.4 — Hand off for commit**: the worklist + scan baseline + a notes
  scaffold (`docs/porting/notes/first-port/README.md` recording SNAP_SHA,
  PORT_ROOT, port branch, auth-triage + smoke-commit outcomes) are committed by
  the phase verifier per the run-plan overlay. Instance records — exempt from the
  fork-generality tripwire by design (WI 4.3).

### Design & Constraints

- This phase's agent is NOT a porting agent — it may read this plan freely; it
  writes no ported content.
- PORT_ROOT is durable, gitignored `.zskills/` state at the MAIN repo root (see
  Execution context) — protected by the `block-unsafe-project.sh` fence, surviving
  finish-auto session boundaries. Nothing this plan depends on later lives under
  `${TMPDIR:-/tmp}`.
- `docs/porting/notes/first-port/worklist.json` is committed (durable, reviewable);
  slice phases update unit statuses in it as they complete.

### Acceptance Criteria

- [ ] `test -d "$PORT_ROOT/source/skills" && echo SNAP` → `SNAP`; `git -C
  "$PORT_ROOT/target" rev-parse --is-inside-work-tree` → `true` (clone or init);
  the recorded `source_sha` is an ancestor of origin/main
  (`git merge-base --is-ancestor <source_sha> origin/main && echo REACHABLE` →
  `REACHABLE`).
- [ ] Port branch + smoke commit:
  `git -C "$PORT_ROOT/target" rev-parse --abbrev-ref HEAD` → `port/first-port`;
  `git -C "$PORT_ROOT/target" log --oneline | grep -c 'port: seed'` → `1`.
- [ ] `python3 -c "import json;w=json.load(open('docs/porting/notes/first-port/worklist.json'));print(len(w['units']))"`
  → equals `ls "$PORT_ROOT/source/skills" | wc -l` plus the NINE non-skill units
  (hooks, agents, rules, config, toolkit-install, scripts-core, plugin-compat,
  test-registry, manifest-skeleton) — every `skills/*/` dir appears exactly once
  across slices
  (re-derivation loop; quote it); every unit record carries the
  `dispositions`/`degradations`/`hits` fields (empty at this phase);
  the worklist's `port_root` is an absolute literal path (`test -d` it — no `$`
  in the stored value);
  `test -f docs/porting/notes/first-port/scan-baseline.txt` → present.
- [ ] Baseline↔unit reconciliation: a scripted mapping pass (quote it) shows
  every scan-baseline file owned by exactly one worklist unit or one
  dropped-subtree row — zero unmapped files (the WI 5.3 check ran and passed).
- [ ] Auth triage outcome recorded (clone-ok/init-fallback; push-ok/bundle-planned)
  in the notes scaffold AND tracker Notes.
- [ ] The zskills commit touches only `docs/porting/notes/first-port/**`.
- [ ] Full suite via capture idiom → 0 failed.

### Dependencies

Phase 4 (the guide, including the worklist-builder procedure).

## Phase 6 — Port slice A: run-plan, create-worktree, plans (guide-only)

### Goal

A porting agent, given ONLY the guide and this slice assignment, ports the slice-A
units into the target clone.

### Work Items

- [ ] **6.1 — Execute the port for slice A.** Read `docs/porting/CODEX_PORTING.md`
  and the recipe files it references; execute the first-port procedure's per-slice
  step (INCLUDING its resume preamble — reconcile the worklist against the target
  clone's `port:` commit log before starting) for slice A of
  `docs/porting/notes/first-port/worklist.json` — units: `skills/run-plan`,
  `skills/create-worktree`, `skills/plans` (each unit = the full skill dir
  including bundled scripts). Source: `$PORT_ROOT/source` at the worklist's
  `source_sha`. Output: the ported tree in `$PORT_ROOT/target`, ALL commits on the
  worklist's `port_branch`. Commit each completed unit to the target clone as
  `port: <unit> (slice A)`; set the unit's worklist status to `done` and fill its
  `dispositions`/`degradations`/`hits` records per the guide's per-slice step;
  record every judgment call in the porting notes and every guide ambiguity or
  silence as a `GAPS.md` entry in the target tree, staged into the unit's
  `port: <unit>` commit per the guide's GAPS.md durability contract (an
  uncommitted gap entry is lost undetectably on a crash) — do not improvise
  silently, and do NOT edit the guide.
- [ ] **6.2 — Hygiene (binding on the dispatched agent).** Do not read
  `docs/plans/CODEX_PORT_PLAN.md`, any research file, or any prior-fork clone. This
  phase text deliberately contains NO porting procedure; if a porting decision
  cannot be made from the guide alone, that is a GAPS.md entry (a guide defect),
  never a reason to look elsewhere. Where a fix belongs in the guide or toolkit,
  record the gap — Phase 13 folds it back; do not patch either mid-slice.
  Deletions inside the target clone use `git rm` in the pinned literal-cd
  compound form (`cd <literal-target> && git rm …` — the guide's per-slice
  invocation-form rule; never
  bare `rm -rf`); if a filesystem-level deletion is denied by the project's
  `.zskills/` fence, record it in GAPS.md and continue — the fence is repo
  machinery, not a porting error. If any target-clone git operation is denied by
  a hook envelope, classify it per this phase's commit-discipline block below —
  never treat it as an auth failure, never retry past two attempts.
- [ ] **6.3 — Hand off the zskills-side changes**: update the worklist + slice
  notes (`docs/porting/notes/first-port/slice-A.md`) in the phase worktree and
  leave them for the VERIFIER to commit after its full-suite run — the
  implementer commits ONLY into the target clone (see below).

### Design & Constraints

- **Commit discipline for this phase (read carefully — two instruction sets meet
  here).** run-plan's dispatch overlay says "the implementation agent does NOT
  commit" and "`$FULL_TEST_CMD` before every commit" — those rules govern THIS
  repo's git tree (the phase worktree), where they stand unchanged: the verifier
  commits the notes/worklist changes after the full suite. Commits inside
  `$PORT_ROOT/target` are OUT-OF-REPO ARTIFACT WRITES into a scratch clone of a
  different repository, expressly authorized by this phase: the implementer makes
  them per-unit (they are the durable cursor), on the worklist's `port_branch`,
  in the guide's pinned invocation form (ONE compound with the LITERAL absolute
  cd copied from the worklist's `port_root` — never a `$VAR` cd, never a bare
  `git commit` in a later call, never `git -C` for commits),
  with no zskills test suite gating them. The guide's per-slice step is the
  procedure; this block only resolves whose commit rules apply where. A hook deny
  on a target-clone operation names its reason: `main_protection` ⇒ check the
  SPELLING first — a variable-cd / bare-git / `git -C` form makes the hook
  evaluate the AMBIENT repo on `main`, so re-issue ONCE as the pinned literal-cd
  compound; only if the literal form is also denied, check and restore
  `port_branch`, then retry once (never loop the same spelling — the deny is
  deterministic per spelling); `stale_skill_version` ⇒ a `metadata.version`
  re-stamp was missed (the deny message carries the exact bump command; run it,
  restage, retry); anything else ⇒ record verbatim and report. Never use
  `git -C` spellings to avoid a hook, and never take a "push/auth fallback" in
  response to a deny.
- If context pressure forces an early stop: commit completed units to the target
  clone, update the worklist records, report the phase INCOMPLETE. The
  re-dispatch (attempt 2, fresh agent) starts with the resume preamble — the
  target clone's `port:` commit subjects are the authoritative cursor (worklist
  reconciled to match); a half-edited unit is redone by re-copying it verbatim
  from source (idempotent by copy-first design; `git restore`/`reset --hard` are
  hard-denied and never needed). Incomplete after attempt 2 ⇒ STOP and surface
  (per Execution context).
- The guide is FROZEN during Phases 6–11 (editing it mid-port would invalidate the
  acceptance test and steer later slices); all guide fixes happen in Phase 13.
- The zskills-side commit touches only `docs/porting/notes/first-port/**`.

### Acceptance Criteria

- [ ] `git -C "$PORT_ROOT/target" log --oneline | grep -c '^.* port: skills/'` ≥ the
  slice's unit count; every slice-A unit named in a commit subject (quote them);
  `git -C "$PORT_ROOT/target" rev-parse --abbrev-ref HEAD` → `port/first-port`
  (all commits on the port branch).
- [ ] Scoped gate: `bash scripts/porting/codex-scan-gate.sh "$PORT_ROOT/target"
  --scope <slice-A ported paths>` → exit 0, `violations=0 unknown=0` (quote the
  `CODEX-SCAN-SUMMARY:` line).
- [ ] `grep -rEn 'only when .{0,40}insufficient|otherwise run inline' <slice-A ported paths> | wc -l` → `0`.
- [ ] Fidelity floor (pinned command — the verifier computes it exactly so, per
  skill; Phases 7–12 inherit this definition):
  ```bash
  src=$(find "$PORT_ROOT/source/skills/$s" -name '*.md' -type f -exec cat {} + | wc -c)
  dst=$(find "$PORT_ROOT/target/skills/$s" -name '*.md' -type f -exec cat {} + | wc -c)
  ```
  `dst ≥ 0.6 × src` for each slice-A skill (markdown bytes on both sides — prose
  is what the floor protects), OR a worklist disposition explains the shrink
  (constructs deleted per recipe legitimately shrink files) — quote the per-skill
  ratios.
- [ ] Worklist: every slice-A unit status `done`, with non-empty `dispositions`
  and a `hits` record for every scan-baseline hit in that unit's files (quote the
  per-unit hit counts vs the baseline).
- [ ] GAPS.md durability: `git -C "$PORT_ROOT/target" status --porcelain --
  GAPS.md` → empty (every gap entry recorded this slice is committed — the
  guide's per-unit staging contract held).
- [ ] The zskills commit touches only `docs/porting/notes/first-port/**`; full suite
  via capture idiom → 0 failed.

### Dependencies

Phase 5 (worklist + snapshot + target clone).

## Phase 7 — Port slice B: fix-issues, investigate, session-report, briefing (guide-only)

### Goal

Same contract as Phase 6, for slice B.

### Work Items

- [ ] **7.1 — Execute the port for slice B.** Identical contract to WI 6.1 with
  slice B — units: `skills/fix-issues`, `skills/investigate`,
  `skills/session-report`, `skills/briefing`; commits `port: <unit> (slice B)`.
- [ ] **7.2 — Hygiene.** Identical to WI 6.2 (guide-only; no plan/research/fork
  reads; GAPS.md for every ambiguity; guide frozen).
- [ ] **7.3 — Commit** worklist updates + `docs/porting/notes/first-port/slice-B.md`.

### Design & Constraints

Identical to Phase 6's (context-pressure cursor resume; attempt-2 from first
`pending` unit; STOP after attempt 2; zskills commit = notes only).

### Acceptance Criteria

Same checks as Phase 6 (per-unit commits on the port branch in the pinned
invocation form, scoped gate clean with
quoted summary, hedge grep 0, pinned per-skill fidelity floor with quoted ratios,
worklist `done` with filled dispositions/hits, GAPS.md clean in target status)
over the slice-B paths; zskills
commit scope; full suite → 0 failed.

### Dependencies

Phase 6 (serial worklist-file updates; slices are content-independent but share the
worklist and notes files — serial execution avoids merge conflicts).

## Phase 8 — Port slice C: update-zskills, do, manual-testing (guide-only)

### Goal

Same contract as Phase 6, for slice C (includes the install-machinery skill —
expect install-recipe GAPS here if anywhere).

### Work Items

- [ ] **8.1 — Execute the port for slice C.** Identical contract to WI 6.1 with
  slice C — units: `skills/update-zskills`, `skills/do`, `skills/manual-testing`;
  commits `port: <unit> (slice C)`.
- [ ] **8.2 — Hygiene.** Identical to WI 6.2.
- [ ] **8.3 — Commit** worklist updates + `docs/porting/notes/first-port/slice-C.md`.

### Design & Constraints

Identical to Phase 6's.

### Acceptance Criteria

Same checks as Phase 6 over the slice-C paths; zskills commit scope; full suite → 0
failed.

### Dependencies

Phase 7 (serial worklist).

## Phase 9 — Port slice D: draft-plan, draft-tests, refine-plan, research-and-plan, research-and-go, qe-audit (guide-only)

### Goal

Same contract as Phase 6, for slice D (the multi-agent planning skills — the
`agent-dispatch` recipe's heaviest exercise).

### Work Items

- [ ] **9.1 — Execute the port for slice D.** Identical contract to WI 6.1 with
  slice D — units: `skills/draft-plan`, `skills/draft-tests`,
  `skills/refine-plan`, `skills/research-and-plan`, `skills/research-and-go`,
  `skills/qe-audit`; commits `port: <unit> (slice D)`.
- [ ] **9.2 — Hygiene.** Identical to WI 6.2.
- [ ] **9.3 — Commit** worklist updates + `docs/porting/notes/first-port/slice-D.md`.

### Design & Constraints

Identical to Phase 6's.

### Acceptance Criteria

Same checks as Phase 6 over the slice-D paths; zskills commit scope; full suite → 0
failed.

### Dependencies

Phase 8 (serial worklist).

## Phase 10 — Port slice E: work-on-plans, land-pr, commit, cleanup-merged, verify-changes, zskills-dashboard, fix-report (guide-only)

### Goal

Same contract as Phase 6, for slice E (the landing/verification skills; largest
slice by raw lines, lowest construct density).

### Work Items

- [ ] **10.1 — Execute the port for slice E.** Identical contract to WI 6.1 with
  slice E — units: `skills/work-on-plans`, `skills/land-pr`, `skills/commit`,
  `skills/cleanup-merged`, `skills/verify-changes`, `skills/zskills-dashboard`,
  `skills/fix-report`; commits `port: <unit> (slice E)`.
- [ ] **10.2 — Hygiene.** Identical to WI 6.2.
- [ ] **10.3 — Commit** worklist updates + `docs/porting/notes/first-port/slice-E.md`.

### Design & Constraints

Identical to Phase 6's.

### Acceptance Criteria

Same checks as Phase 6 over the slice-E paths; zskills commit scope; full suite → 0
failed.

### Dependencies

Phase 9 (serial worklist).

## Phase 11 — Port slice F: hooks, agents, rules/AGENTS.md, config, toolkit install, scripts helpers, plugin compat, test registry, manifest skeleton (guide-only)

### Goal

Same guide-only contract, for the non-skill units: the hook tree (near-direct port —
same envelope), agents (converter), the rules template → AGENTS.md dual delivery,
config discovery, installing the runner/gate/invariants into the ported tree, the
top-level `scripts/` helpers the recipes depend on, the `.claude-plugin/`
marketplace-compat adaptation, the
curated test registry, and the manifest skeleton the assembly phase verifies.

### Work Items

- [ ] **11.1 — Execute the port for slice F.** Identical contract to WI 6.1 with
  slice F — NINE units (each a worklist row, each cursor-visible): `hooks/`
  (translate `hooks/hooks.json` via `hooks-translate.py`; port hook scripts per
  the recipes), `agents/` (`agents-to-toml.py` + degradations report), the rules
  template (`CLAUDE_TEMPLATE.md` → AGENTS.md dual delivery via
  `render-agents-md.sh`), config discovery layout, toolkit install (runner + gate +
  invariants from `scripts/porting/` into the ported tree), **`scripts-core`** —
  the top-level `scripts/` helpers per the tree-scope `scripts/` row
  (copy-first + hit-driven like skills; at draft time: `frontmatter-get.sh`,
  `frontmatter-set.sh`, `skill-content-hash.sh`, `skill-version-stage-check.sh`,
  `render-managed-rules.py`, `scripts/_lib/`, plus the remaining top-level
  helpers the tree-scope walk discovers — plan-level enumeration permitted,
  invariant 1; this unit is what makes the frontmatter-flags recipe's pre-commit
  hook and the AGENTS.md renderer dependency REAL in the ported tree — its
  `port:` commit also flips the target-side stale-skill-version stage-check from
  vacuous to live, see port-branch rule item 3), **`plugin-compat`** — adapt
  `.claude-plugin/` per its tree-scope row (marketplace compat: Codex reads the
  legacy `marketplace.json` per the assumptions manifest / probe
  `plugins.marketplace.claude-compat`; emit the `.codex-plugin/` sibling the
  recipe directs), the curated test
  registry (per the guide's keep/drop/SPLIT recipe — including the
  `test-skill-conformance.sh` split), and `manifest-skeleton` — the
  `PORT_MANIFEST.json` skeleton (tree-scope defaults + per-file dispositions read
  MECHANICALLY from every unit's worklist `dispositions` records) +
  `DEGRADATIONS.md` generated from the accumulated worklist `degradations`
  entries (never reconstructed from freeform notes prose).
  Commits `port: <unit> (slice F)`.
- [ ] **11.2 — Hygiene.** Identical to WI 6.2.
- [ ] **11.3 — Commit** worklist updates + `docs/porting/notes/first-port/slice-F.md`.

### Design & Constraints

Identical to Phase 6's, plus: the hooks unit is copy-first + hit-driven like skills
(the envelope is byte-compatible per the capability map; the scanner's
`plugin-root`/`project-dir` hits are the main edit sites); the registry unit follows
the drop-by-default recipe — a 215-suite keep-by-keep triage is NOT the job.
Drop-by-default targets harness-COUPLED suites; suites matching the recipe's
harness-neutral keep criterion are KEPT (the recipe's reconciliation with settled
decision 7) — but the kept set is expected to be materially smaller than the
source tree's ~130 harness-agnostic suites on the first port, a deliberate
narrowing recorded in the porting notes and surfaced to the owner as residue.

### Acceptance Criteria

- [ ] Same base checks as Phase 6 (per-unit commits, scoped gate clean over ported
  `hooks/`+`agents/`+root docs, hedge grep 0, worklist `done`, notes-only zskills
  commit, full suite → 0 failed).
- [ ] `python3 -c "import tomllib,glob;[tomllib.load(open(f,'rb')) for f in glob.glob('$PORT_ROOT/target/.codex/agents/*.toml')];print('TOML-OK')"`
  → `TOML-OK` (≥ 2 files — verifier/implementer).
- [ ] `test -f "$PORT_ROOT/target/PORT_MANIFEST.json" && test -f "$PORT_ROOT/target/DEGRADATIONS.md" && echo PRESENT` → `PRESENT`.
- [ ] `scripts-core` landed: `test -f "$PORT_ROOT/target/scripts/skill-content-hash.sh" && test -f "$PORT_ROOT/target/scripts/frontmatter-set.sh" && test -f "$PORT_ROOT/target/scripts/render-managed-rules.py" && echo SCRIPTS` → `SCRIPTS`
  (the versioning pre-commit hook and the AGENTS.md re-render path have their
  callees); `plugin-compat` landed: the adapted marketplace-compat files are
  present per the recipe (quote the paths).
- [ ] The ported tree's `tests/run-all.sh` registry exists and its suite set matches
  the keeper-floor + kept per-skill suites (quote the registry's `run_suite` count).

### Dependencies

Phase 10 (serial worklist; manifest skeleton needs all skill slices' dispositions).

## Phase 12 — Port assembly verification: gate, manifest/disposition parity, hit parity, fidelity, composition

### Goal

Verify the assembled ported tree end-to-end with MECHANICAL checks (whole-tree
scanner gate, manifest completeness validated against the worklist's per-file
dispositions, per-hit-site disposition parity against the scan baseline, full-body
fidelity, cross-slice dispatch composition), and produce the classified gap
inventory Phase 13 consumes. No guide edits, no push — verification only, so the
dispatch is bounded.

### Work Items

- [ ] **12.1 — Whole-tree verification** (fresh verifier dispatch — this is
  run-plan's own Phase-3 verification step for this phase, pointed at the ported
  tree): scanner gate clean (`codex-scan-gate.sh "$PORT_ROOT/target"` — the
  port meta-records `GAPS.md`/`DEGRADATIONS.md`/`PORT_MANIFEST.json`/
  `PORTING-NOTES.md` are path-excluded by the scanner's default-skip list, WI
  3.1, so the gate never fails on the record-of-the-port artifacts this phase
  itself requires); full-body
  check (no hedge-prose; every `skills/<name>/` in the source snapshot is present
  in the port or named in `DEGRADATIONS.md` with a reason); `PORT_MANIFEST.json`
  valid (`ported_from_sha` == the worklist's recorded SHA — a main-reachable
  commit per WI 5.1; `ported_from_version` == `dev@<sha12>` per the version-pairing
  rule; **every per-file disposition row EQUALS the worklist's recorded
  disposition for that file** — the manifest is validated against the data the
  slice agents wrote at port time, not against mere row existence; every dropped
  subtree has its summary row per the tree-scope table); `DEGRADATIONS.md` rows
  match the union of the worklist's `degradations` entries, including the named
  ABSENT entries (at minimum `user-invocable`, `allowed-tools` enforcement,
  per-agent frontmatter hooks); curated `tests/` registry present; **hit-site
  parity:** every scan-baseline hit (WI 5.3) in a ported (non-dropped) file has a
  recorded `hits` disposition in the worklist — counts match per unit, over ALL
  units, skill AND non-skill (the baseline's `scripts/**` hits belong to
  `scripts-core`, `hooks/**` to the hooks unit, and so on; WI 5.3's
  baseline↔unit reconciliation guarantees every baseline file has exactly one
  owner, so this check has no unowned-hit blind spot) — and the
  verifier samples ≥ 10 hit SITES across ≥ 5 skills, reading each replacement in
  the ported file and attesting it is EXECUTABLE on the Codex substrate (names a
  concrete mechanism — a runner invocation, a TOML agent, a hook — not a
  paraphrase with the construct nouns filed off); **composition check:** every
  agent-name reference in ported prose resolves against the `.codex/agents/*.toml`
  set, and verifier/implementer dispatch sites use the `codex exec` construct per
  the pinned recipe (grep-driven, quote the commands); **fidelity floor re-check
  over the whole tree** (per-skill markdown-byte ratio ≥ 0.6, the Phase-6 pinned
  command, or a manifest disposition) AND a **spot-check: read the 3 largest
  ported skills — largest by SOURCE markdown bytes — side-by-side with source and
  attest procedure-step parity** (steps present, ordered, no silent summarization)
  in the verifier report.
- [ ] **12.2 — Classified gap inventory.** Collate every `GAPS.md` entry and
  slice-notes judgment into `docs/porting/notes/first-port/gap-inventory.md`,
  each row classified: `guide-text` (recipe wording defect), `toolkit-bug`
  (scanner/converter/renderer defect), `port-instance` (a ported file needs
  re-work because the guide was ambiguous — names the affected unit(s) and hit
  sites), or `no-action` (judgment call recorded, nothing to fix). This inventory
  is Phase 13's input contract; Phase 13 does not re-read the raw notes.
- [ ] **12.3 — Scope check** before the zskills commit: `git show --stat HEAD`
  (after commit) contains ONLY `docs/porting/notes/first-port/**` paths.

### Design & Constraints

- **The port ports the snapshot at the recorded SHA** (the guide-acceptance run);
  the guide itself documents that release-time ports port the SHIPPED tree (Phase
  15). The manifest records which tree was ported — no ambiguity.
- **Systemic failure is a STOP, not a loop:** if the whole-tree gate, hit parity,
  or composition check reveals a SYSTEMIC recipe failure (the same defect class
  across multiple slices — not per-slice gaps), STOP and surface with the named
  human action: re-planning the affected slices is a `/refine-plan` decision
  (flipping ✅ Done tracker rows is a human intervention; run-plan selects the
  first incomplete phase and cannot re-open Done phases, and the pipeline must
  not pretend otherwise).
- The ported tree is NOT required to pass its full curated suite in this phase
  (that is Phase 14's job with fix cycles); it IS required to pass the scanner
  gate and manifest/parity checks — the guide's procedure ends with the gate, so
  a gate failure is a guide/agent failure by definition.
- This phase's agent may read the plan (it is not a porting agent). No guide or
  toolkit edits in this phase — Phase 13 owns those.

### Acceptance Criteria

- [ ] `bash scripts/porting/codex-scan-gate.sh "$PORT_ROOT/target" && echo CLEAN` →
  `CLEAN` (quote the `CODEX-SCAN-SUMMARY:` line — `violations=0 unknown=0`).
- [ ] `python3 -c "import json;m=json.load(open('$PORT_ROOT/target/PORT_MANIFEST.json'));print(m['ported_from_sha'],m['ported_from_version'])"`
  → prints exactly the worklist's `source_sha` and `dev@<its first 12 chars>`.
- [ ] Manifest↔worklist disposition parity: a scripted comparison (quote it) shows
  every manifest per-file row equal to the worklist record; mismatches → phase
  FAIL naming the files.
- [ ] Hit parity: per-unit baseline-hit count == recorded `hits` count (quote the
  per-unit table); the ≥10-site executability sample is in the verifier report
  with file:line and the replacement construct named per site.
- [ ] Composition: the agent-name resolution grep and the verifier/implementer
  `codex exec` pin both quoted, zero unresolved references.
- [ ] Source-skill coverage re-derivation:
  `for d in "$PORT_ROOT/source/skills"/*/; do n=$(basename "$d"); test -d "$PORT_ROOT/target/skills/$n" || grep -q "$n" "$PORT_ROOT/target/DEGRADATIONS.md" || echo "MISSING $n"; done`
  → no output.
- [ ] `grep -rEn 'only when .{0,40}insufficient|otherwise run inline' "$PORT_ROOT/target/skills/" | wc -l` → `0`.
- [ ] Fidelity: the verifier report quotes the per-skill markdown-byte ratios (all
  ≥ 0.6 or manifest-explained) AND the 3-skill spot-check attestation.
- [ ] `test -f docs/porting/notes/first-port/gap-inventory.md` with every row
  classified into the four named classes (quote the per-class counts).
- [ ] `git show --stat HEAD` (the zskills commit) → only
  `docs/porting/notes/first-port/**` paths; full suite via capture idiom → 0 failed.

### Dependencies

Phases 5–11 (all slices done).

## Phase 13 — Gap-fold into guide/toolkit, bounded refold, push port branch

### Goal

Fold the classified gap inventory back into the guide/recipes/toolkit (the product
fix), re-work the affected ported files through a bounded, repeatable refold
mechanism (the instance fix — never by re-opening Done phases), and push the port
branch to the target repo with a durable bundle fallback.

### Work Items

- [ ] **13.1 — Fold gaps into the guide/toolkit.** For every `guide-text` and
  `toolkit-bug` row in `docs/porting/notes/first-port/gap-inventory.md`: fix the
  guide/recipes (re-running `tests/test-porting-guide.sh` after edits) or fix the
  toolkit bug WITH its test in the same commit (surface-bugs discipline: the fix
  belongs at source). **Bound:** if the inventory contains a SYSTEMIC gap (one
  defect class spanning 3+ slices) or more than ~15 actionable rows, STOP and
  surface — that volume is a plan-shape problem for `/refine-plan`, not a single
  dispatch's judgment work. (Basis for ~15: roughly what one 2-hour dispatch can
  adjudicate honestly; a judgment constant, tunable via `/refine-plan` with a
  stated basis — the STOP semantics do not depend on the exact number.)
- [ ] **13.2 — Bounded refold of affected ported files.** For every
  `port-instance` row: append a NEW worklist unit `refold:<unit>` (cursor-visible,
  same schema) scoped to the named files/hit-sites; process each refold unit with
  the AMENDED recipe at the recorded hit sites; re-stamp `metadata.version` on
  edited skills; commit `refold: <unit>` on the port branch, in the pinned
  invocation form (port-branch rule item 2 — literal-cd compound); re-run the
  SCOPED
  gate + the Phase-6 pinned fidelity command over the refolded paths. **Bound:
  more than 6 refold units (≈ one slice-phase's worth of units — beyond that the
  "bounded repair" framing is false and the honest shape is a re-sliced phase;
  tunable via `/refine-plan` with a stated basis), or any refold that would
  rewrite a unit wholesale, ⇒
  STOP and surface with the named human action (re-slicing via `/refine-plan`).
  Done slice phases are NEVER re-opened — refold units are new work items in THIS
  phase, executed by this phase's (plan-aware) agent.**
- [ ] **13.3 — Porting-notes summary** at `docs/porting/notes/first-port-<date>.md`
  (source SHA, per-slice gap counts, refold-unit list, dispositions, push
  outcome, the pending owner promotion).
- [ ] **13.4 — Push the port branch** `port/first-port` to `zeveck/zskills-codex-f`
  in the pinned invocation form (port-branch rule item 2):
  `cd <literal-target> && git push origin port/first-port` as one compound.
  (A `git -C … push origin port/first-port` also passes every push arm —
  verified against both hooks' refspec rules — but the plan pins ONE form for
  every target-clone write so no agent exercises spelling judgment.) The
  provenance manifest must be committed in-tree. Verify:
  `git ls-remote https://github.com/zeveck/zskills-codex-f.git refs/heads/port/first-port`
  non-empty and the pushed HEAD tree contains `PORT_MANIFEST.json`. **NEVER push
  to the target's `main`** — record the named OWNER action "promote
  port/first-port to main (one command: `git push origin port/first-port:main`
  or a GitHub merge)" in tracker Notes + the notes summary; it stays pending
  until the owner runs it (Execution-context attended item 3). **Failure triage
  is mandatory:** a HOOK DENY envelope (reason names `main_protection`/
  `push_to_main`/`stale_skill_version`) is NOT the auth case — triage per
  port-branch rule item 5 (spelling first, then branch/stamp state) and retry
  (max 2); only a genuine auth/network failure takes the
  fallback: **push unavailable (auth) ⇒ durable fallback, then ATTENDED-PENDING:**
  write `git -C "$PORT_ROOT/target" bundle create "$PORT_ROOT/first-port.bundle" --all`,
  verify the bundle (`git bundle verify`), record the bundle path + HEAD SHA in
  tracker Notes AND the notes summary, and file the follow-up issue "Push
  first-port branch to zskills-codex-f (bundle at <path>)". The phase completes on
  the verified bundle — the tree is never left only in a session-scoped location.
- [ ] **13.5 — Scope check** before the zskills commit: `git show --stat HEAD`
  (after commit) contains ONLY `docs/porting/**`, `scripts/porting/**`, `tests/**`
  paths — no ported-tree files, no skill edits.

### Design & Constraints

- Gap-folding happens HERE, once, after all slices — never mid-port (WI 6.2).
- This phase's agent may read the plan (it is not a porting agent); refold work
  uses the AMENDED guide plus the recorded hit sites — it is targeted repair, not
  a fresh guide-only acceptance run (that property was measured in Phases 6–11).
- After any refold, WI 13.2's scoped re-checks must pass before the push; a
  refold that fails its re-check twice is a STOP (two-attempt rule).

### Acceptance Criteria

- [ ] Every `gap-inventory.md` row shows a resolution: guide/toolkit commit ref,
  `refold:<unit>` commit ref, `no-action`, or the STOP that ended the phase
  (quote the per-class tallies).
- [ ] `bash tests/test-porting-guide.sh` → `Results: N passed, 0 failed` after
  guide amendments.
- [ ] Refold evidence (when any occurred): scoped gate + pinned fidelity re-check
  quoted per refolded unit; refold-unit count ≤ 6.
- [ ] `git ls-remote https://github.com/zeveck/zskills-codex-f.git refs/heads/port/first-port`
  → non-empty — OR the verified bundle exists (`git bundle verify
  "$PORT_ROOT/first-port.bundle"` → OK) with the ATTENDED-PENDING push recorded in
  tracker Notes + issue, per WI 13.4.
- [ ] The owner-promotion action is recorded in tracker Notes + notes summary
  (pending until the owner runs it).
- [ ] `git show --stat HEAD` (the zskills commit) → only
  `docs/porting/`, `scripts/porting/`, `tests/` paths; porting-notes summary present.
- [ ] Full suite via capture idiom → 0 failed.

### Dependencies

Phase 12 (the verified tree + classified gap inventory).

## Phase 14 — Port verification: ported-tree suites, runner integration, canary kit (+ owner canaries)

### Goal

Prove the ported tree works: its own curated suite passes; the runner drives a real
plan lifecycle against the ported tree's state contract (fake-codex children); a
canary kit with honest per-skill coverage classification — including failure-path
canaries — is built and runnable; the owner's real-Codex canary run is the phase's
attended item.

### Work Items

- [ ] **14.0 — Gate on the ported-tree artifact.** First action, resolve the tree in
  order: (1) `git ls-remote https://github.com/zeveck/zskills-codex-f.git
  refs/heads/port/first-port` non-empty ⇒ fresh clone of that branch
  (`git clone -b port/first-port …` — the tree lives on the PORT branch until the
  owner promotes it); (2) else the local clone at
  `$PORT_ROOT/target` with commits present; (3) else restore from the Phase-13
  bundle with branch AND destination pinned:
  `git clone -b port/first-port "$PORT_ROOT/first-port.bundle"
  "$PORT_ROOT/target-restored"` — the explicit `-b` never relies on the bundle's
  HEAD, and the destination sits under the durable PORT_ROOT (never
  `${TMPDIR:-/tmp}`) so any WI 14.1 fix commits made while push auth is
  unavailable survive the session, per Phase 13's never-session-scoped rule.
  **None available ⇒
  Failure-Protocol STOP** naming the pending-push issue — not improvisation against
  an empty repo.
- [ ] **14.1 — Ported-tree suite run.** In the resolved tree (fresh clone preferred):
  `bash tests/run-all.sh` (the port's own curated registry — self-anchoring makes
  this Just Work). Fix cycles: failures in ported SUITES or ported SCRIPTS are
  ported-tree fixes (committed + pushed to the target repo's PORT BRANCH — never
  its `main` — in the pinned invocation form, port-branch rule item 2: one
  literal-cd compound per write, the literal path being the resolved clone
  location 14.0 chose; skill edits re-stamp `metadata.version` per the recipe —
  authorized,
  see Execution context; when operating from the bundle/local clone, commits go
  there and the pending-push issue inherits them); failures revealing GUIDE defects (a
  recipe produced a broken artifact) are guide fixes in THIS repo. A failure
  traceable to a suite that should have been dropped/split per the registry recipe
  is a REGISTRY fix (re-triage that one suite per the recipe), recorded in the
  porting notes — not an excuse to weaken a kept suite. Both sides of each fix are
  recorded in the porting notes. Registration-completeness must pass INSIDE the
  ported tree (curated registry is complete or carries reasoned allowlist entries).
- [ ] **14.2 — Runner↔ported-tree integration.** Add integration cases (extending
  `tests/test-porting-runner-happy.sh` or a new registered
  `tests/test-porting-integration.sh`): run `scripts/porting/zskills-runner.sh`
  with fake-codex against a fixture PLAN inside a minimal ported-tree-shaped fixture
  (`.zskills/` state contract, config discovery order, ported report path) — chunk
  lifecycle completes; markers land in the ported layout; `.zskills/landed`
  branching honored. **Failure-path integration:** a fixture plan whose fake-codex
  child "fails verification" (missing `tests-run`) must HALT the runner (rc 23) with
  the plan NOT marked complete — the intentionally-failing-phase-must-halt-not-land
  canary, runnable in the container.
- [ ] **14.3 — `scripts/porting/codex-canary.sh` + matrix doc.** Owner-runnable canary
  kit against a real Codex install + the ported repo: `--list` prints the canary
  matrix (per-skill: canary id, what it exercises, coverage class
  `full|partial|smoke|none`); each canary is a scripted setup + an exact
  `codex exec`/interactive instruction + a machine-checkable expected outcome
  (marker/file/exit assertions — not vibes). REQUIRED canaries: run-plan finish-auto
  multi-phase to completion (cherry-pick AND pr landing); **failure-path: a plan
  with an intentionally-failing phase must halt, not land** (both prior forks
  skipped this — it is non-negotiable); every-mode fire + resume + stop; hook
  deny-envelope firing on a gated command in a live Codex session; skill implicit +
  `$name` invocation of a ported skill; AGENTS.md/SessionStart rules delivery
  visible in-session. Results written to a `--out` JSON
  (`zskills-codex-canary/v1`, per-canary pass/fail/skip + observed), `--validate`
  mode, `CODEX-CANARY-SUMMARY:` line. Honest classification: skills not exercised
  are listed `none` — never omitted. Same owner-machine portability constraints as
  the probe kit (invariant 7: Git-Bash/MSYS-safe, probe-RUN codex resolution).
- [ ] **14.4 — `tests/test-porting-canary-kit.sh`** (registered, container-runnable):
  `--list` matrix includes the failure-path canary and every ported skill appears
  with a coverage class; absent-codex refusal; `--validate` sample + mutations;
  the same static portability self-check as the probe-kit suite (mirror of WI 0.5).
- [ ] **14.5 — ATTENDED (owner, non-gating): run the canary matrix** on a real-Codex
  machine against the ported repo (clone the PORT branch, or `main` if the owner
  has already promoted it):
  `bash scripts/porting/codex-canary.sh --out docs/porting/canary-results.json`,
  triage failures (ported-tree fixes and/or guide fixes), commit the results file
  here. If not run this session: **ATTENDED-PENDING** in tracker Notes + follow-up
  issue "Run real-Codex canary matrix against zskills-codex-f and commit
  docs/porting/canary-results.json".

### Design & Constraints

- Phase 14's GATING content is autonomous: 14.0–14.4. Only 14.5 is attended. While
  14.5 is pending, the runner's real-Codex behavior remains UNVERIFIED — the
  completion-message residue rule (Execution context) states this verbatim; the
  probe (Phase 0/4) validated the runner's invocation SHAPES, the canaries validate
  its end-to-end behavior.
- Fix cycles here obey the two-attempt limit per failure; a systemic failure (guide
  recipe fundamentally wrong) is a STOP-and-surface, not an endless loop.
- The canary kit must not embed the target repo name (fork-generality — it takes
  `--repo <path>`); this PLAN's attended instruction names the target, the kit does
  not.
- Ported-tree commits (14.1 fixes) go to the target repo's port branch with clear
  messages; this repo's commit for the phase = integration tests + canary kit +
  notes updates.

### Acceptance Criteria

- [ ] Tree-resolution evidence: the verifier report states which source (remote
  clone / local clone / bundle) was used, or that the phase STOPped.
- [ ] Ported-tree suite: `bash <resolved-tree>/tests/run-all.sh > "$TEST_OUT/ported-results.txt" 2>&1`
  → aggregate `Results:` line with 0 failed; quote the per-suite tally and confirm
  the provenance header names the ported tree's HEAD.
- [ ] Failure-path integration: the named case in the integration suite shows the
  runner exiting rc 23 with the fixture plan's tracker NOT `✅ Done` (quote the case
  output).
- [ ] `bash scripts/porting/codex-canary.sh --list` → matrix lines; piping through
  `grep -c 'failure-path'` → ≥ 1; every `skills/*/` dir name from the ported tree
  appears (re-derivation loop, same shape as Phase 12's coverage AC). The
  verifier report also names which tree source (remote port branch / local clone
  / bundle) the run used.
- [ ] `bash tests/test-porting-canary-kit.sh` → `Results: N passed, 0 failed`;
  `grep -n 'test-porting-canary-kit\|test-porting-integration' tests/run-all.sh` →
  registered.
- [ ] Full suite via capture idiom → 0 failed.
- [ ] ATTENDED (non-gating): `docs/porting/canary-results.json` committed with
  `CODEX-CANARY-SUMMARY: … fail=0` — OR tracker Notes carry `ATTENDED-PENDING` + the
  follow-up issue number.

### Dependencies

Phase 13 (an assembled, gate-clean, gap-folded ported tree — durable via remote
port branch, local clone, or bundle).

## Phase 15 — Release procedure, delta-port machinery, fork-robustness acceptance, docs sweep

### Goal

Make the capability release-grade: a documented owner-run release-time procedure
producing the matched-version Codex release; the three-way delta-port tool with
byte-verbatim carry-forward; the fork-robustness acceptance test (discovery +
classification against a deliberately divergent tree); CHANGELOG/RELEASING
cross-references; residue cleanup.

### Work Items

- [ ] **15.1 — `scripts/porting/delta-port.sh`.** Inputs: `--source <claude-repo>`
  `--ported <codex-repo>` (reads `PORT_MANIFEST.json` for `ported_from_sha`).
  Computes the three-way classification over source files: `carry` (unchanged
  Claude@prior→Claude@now AND disposition `verbatim` → byte-copy, `cmp`-verified),
  `re-port` (changed at source → agent worklist with per-file recipe hints from a
  scanner run over the diff), `new` (added at source → full recipe treatment),
  `delete` (removed at source), `conflict` (changed at source AND hand-modified in
  the port since the last port → agent judgment, never auto-overwrite). Emits a
  machine-readable worklist (`CODEX-DELTA-SUMMARY:` line + per-file lines) and
  MUTATES NOTHING without `--apply-carry` (which performs only the `carry` class).
- [ ] **15.2 — Release procedure doc** `docs/porting/RELEASE_PORT.md`, referenced from
  the guide: an **owner-run procedure AFTER the Ship-to-Prod button** (settled: not a
  `ship-to-prod.yml` sibling step — workflow edits require validated dry-runs and
  have burned twice; the Claude release path is untouched). Steps: confirm the prod
  tag (`YYYY.MM.N`) → re-verify assumptions (`codex-probe.sh --only <manifest ids>`,
  attended) → run `delta-port.sh` against the shipped tree → apply carries →
  dispatch a porting agent for the `re-port|new|conflict` worklist (guide recipes)
  → scanner gate + curated suite + canary smoke → update `PORT_MANIFEST.json`
  (new `ported_from_sha`/`ported_from_version`) → tag the ported repo with the SAME
  version → push. Include the failure posture: any gate failure stops the release
  of the PORT only (the Claude release is independent and already shipped).
- [ ] **15.3 — Fork-robustness acceptance test**, two parts:
  - **Fixture-based CI suite** `tests/test-porting-fork-robustness.sh` (registered):
    a committed divergent mini-tree at `tests/fixtures/porting/divergent-tree/`
    containing (a) a skill using known classes in novel files/names (unknown
    INSTANCE of known class → classified mechanically, correct recipe named), (b) a
    skill using a construct in NO class (unknown CLASS → reported `unknown`, gate
    exit 1, remedy text points at the self-amendment rule), (c) a renamed/moved
    skill layout (discovery does not assume today's layout). Plus delta-port
    classification fixtures: carry byte-verbatim (`cmp` equal), re-port, new,
    delete, conflict — each exercised.
  - **Local acceptance run (verifier-executed AC, not CI):** run discovery against
    the genuinely divergent April-era tree from THIS repo's history:
    `git worktree add "${TMPDIR:-/tmp}/zskills-aprilfork" 2026.04.0` then
    `python3 scripts/porting/codex-scan.py --mode discover "${TMPDIR:-/tmp}/zskills-aprilfork/skills"`
    → completes, produces a summary with hits > 0, and classifies constructs from a
    tree with a different skill set (contains `doc`/`fix-report`/`review-feedback`;
    lacks `land-pr`/`create-worktree`) without error. Remove the worktree after
    (verify removal). This is AC-only because CI clones may lack tags.
- [ ] **15.4 — Docs sweep.** CHANGELOG.md entry (one line, existing style);
  RELEASING.md gains a short "Codex port (matched release)" section pointing at
  `docs/porting/RELEASE_PORT.md` (RELEASING.md is dev-only/prod-stripped — safe;
  both files are the invariant-2 Phase-15 exception); the guide root gains a
  "Maintaining this capability" section (self-amendment recap + toolkit test
  suites list by re-derivation: `grep 'run_suite "test-porting-' tests/run-all.sh`).
  PRESENTATION.html: **N/A by convention** — this plan adds no skill (per-skill
  cards are the convention; state this here so the question is pre-empted, no edit
  made).
- [ ] **15.5 — Prod-strip survival check (disposable clone — never mutate this
  repo's refs).** `scripts/build-plugin-release.sh` runs `git update-ref
  refs/heads/prod/main` and `refs/tags/prod/<version>` — branch/tag refs are
  REPO-GLOBAL, shared across worktrees; running it here would repoint the dev
  clone's local prod refs at mid-plan feature content (and silently overwrite a
  `prod/<version>` tag — with a prod release pending, that leftover ref could be
  mistaken for release evidence). So: `git clone --no-hardlinks .
  "${TMPDIR:-/tmp}/zskills-stagebuild"`, run
  `bash scripts/build-plugin-release.sh` (WITHOUT `--push`) INSIDE the clone,
  assert via `git -C "${TMPDIR:-/tmp}/zskills-stagebuild" ls-tree -r --name-only
  refs/heads/prod/main` that `scripts/porting/` files are present in the built tree
  and no `*CANARY*`/`build-*.sh`-named toolkit file was introduced; then remove the
  clone (verify removal). This repo's `prod/*` refs are never touched.
- [ ] **15.6 — Residue cleanup + completion message.** PORT_ROOT
  (`.zskills/porting/first-port/`) disposition: recursive deletion inside
  `.zskills/` is a HARD gate in `block-unsafe-project.sh` (`zskills_tree_delete`
  — blocks always, attended or not, and its suggested alternative is itself
  agent-execution-blocked), so the AGENT never removes it. If Phase 13's push was
  verified (remote port branch non-empty): surface the removal to the owner as a
  one-line manual step with the exact path (`rm -rf <abs-path>/.zskills/porting/first-port` typed by the
  human) — that IS this work item's deliverable for the happy path. If the push
  is still ATTENDED-PENDING: PORT_ROOT is RETAINED (it holds the only durable
  local tree + bundle); record the retention + reason in tracker Notes. The
  completion message lists every still-pending ATTENDED item (probe / canary /
  push / port-branch promotion to target main) as User Verify residue with
  follow-up issue numbers, including the verbatim "the runner is unverified
  against real Codex" line while the canary results are pending (Execution
  context rule).

### Design & Constraints

- `delta-port.sh` must fail closed on a missing/invalid `PORT_MANIFEST.json` (exit
  non-zero, no classification output) — a port without provenance cannot be
  delta-ported, only re-first-ported.
- The April-tag AC is read-only history access (`git worktree add` + removal) — no
  checkout in the main tree, no working-tree mutation.
- Fixture tree filenames: no uppercase `CANARY`, no `MW-EXAMPLE`, no `build-*.sh`.
- The pending prod release may land before this phase: if the tag set moved,
  re-derive the example tag in RELEASE_PORT.md prose (it is illustrative, not
  parsed).
- **Scope acceptance (eyes open):** with Phase 4, this is the other largest
  single dispatch left (tool + fork-robustness suite + divergent fixture tree +
  release doc + docs sweep + staging check + residue). Accepted deliberately —
  the work items are independently committable in spirit but the phase is one
  commit; if the 2-hour timeout or context pressure bites, report INCOMPLETE
  naming the finished WIs and let attempt 2 do the remainder (the ACs are the
  completeness gate). Incomplete after attempt 2 ⇒ STOP per the two-attempt rule.

### Acceptance Criteria

- [ ] `bash tests/test-porting-fork-robustness.sh` → `Results: N passed, 0 failed`;
  `grep -n 'test-porting-fork-robustness' tests/run-all.sh` → registered.
- [ ] Delta byte-verbatim: the suite's carry case output shows `cmp` silence
  (byte-equal) for a carried file (quote the case).
- [ ] `bash scripts/porting/delta-port.sh --source . --ported <dir-without-manifest>; echo rc=$?`
  → non-zero, stderr names the missing manifest.
- [ ] April-tree local run (verifier executes):
  `git worktree add "${TMPDIR:-/tmp}/zskills-aprilfork" 2026.04.0 && python3 scripts/porting/codex-scan.py --mode discover "${TMPDIR:-/tmp}/zskills-aprilfork/skills" | tail -1`
  → a `CODEX-SCAN-SUMMARY:` line with `hits=` > 0; then
  `git worktree remove "${TMPDIR:-/tmp}/zskills-aprilfork" && git worktree list | grep -c aprilfork`
  → `0`.
- [ ] `grep -n 'RELEASE_PORT' RELEASING.md` → cross-reference present;
  `grep -n 'Codex' CHANGELOG.md | head -1` → entry present.
- [ ] Prod-strip survival (in the disposable clone):
  `git -C "${TMPDIR:-/tmp}/zskills-stagebuild" ls-tree -r --name-only refs/heads/prod/main | grep -c '^scripts/porting/'`
  → ≥ the count of committed toolkit files
  (`git ls-files 'scripts/porting/*' | wc -l` — re-derivation), the build's
  strip-verify passes, and afterwards
  `git rev-parse --verify --quiet refs/heads/prod/main; echo rc=$?` IN THIS REPO
  shows the ref unchanged from before the phase (absent stays absent; present
  stays at its prior SHA — quote both readings); the clone directory is removed
  (`test ! -d … && echo gone` → `gone`).
- [ ] Residue: PORT_ROOT removal surfaced as a one-line manual owner step with the
  exact path (push verified) OR retained-with-reason in tracker Notes (push
  pending) — the removed-by-agent arm does not exist (the `.zskills/` delete
  fence is a hard gate).
- [ ] Full suite via capture idiom → 0 failed; any still-pending ATTENDED items
  (probe/canary/push/promotion) surfaced in the completion message as User Verify
  residue with their follow-up issue numbers, including the runner-unverified
  line when applicable.

### Dependencies

Phases 1–14.

## Plan Quality

**Drafting process.** Drafted via `/draft-plan` with three rounds of adversarial
review — each round a fresh reviewer agent plus a fresh devil's-advocate agent
(both re-verifying claims against hook/script/tree source, the DA live-firing the
central round-3 finding in a scratch repo), followed by a refiner applying the
adjudicated findings with verify-before-fix. Owner constraints (dossier
`00-synthesis-and-settled-constraints.md`) were held FIXED throughout; review
pressure-tested the implementation, never the settled decisions.

**Convergence.** Converged at round 3. All BLOCKING findings across all rounds
are resolved; the architecture (probe-gated guide, runner-first toolkit, six
guide-only port slices bracketed by setup/assembly, port-branch + re-stamp +
overlay-carve-out execution model) has been stable since round 2 — round 3
produced only local plan-text fixes, no restructuring.

**Round History.**

| Round | Reviewer findings | DA findings | Resolved |
|---|---|---|---|
| 1 | 14 | 16 | 30/30 |
| 2 | 13 | 13 | 26/26 |
| 3 | 8 (1 BLOCKING) | 4 (3 BLOCKING) | 12/12 |

**Remaining concerns (honest residue — accepted, not hidden).**

1. **Prose-not-mechanism at the owner-gated probe seam (Phases 3→4).** The
   orchestrator's "absent probe file ⇒ Failure Protocol, delete the cron — NOT
   run-plan's recoverable dependency-retry" classification is enforced by a
   pinned unique trigger string (`FAILED-OWNER-GATED: probe results absent`) and
   a verbatim restatement in Phase 4's Dependencies (the section a cron-fired
   orchestrator demonstrably reads) — but it is still instruction, not a hook.
   Worst case is the pre-fix failure mode (a visibly spinning `*/1` cron), with
   materially better odds. No further mechanism exists without safety-hook edits
   the plan rightly refuses.
2. **Judgment constants.** The 0.6 fidelity floor, the ~7,000/8,500 md-line
   slice budget, and Phase 13's 6-refold-unit / ~15-gap-row bounds now carry
   in-plan rationale and are marked tunable via `/refine-plan` with a stated
   basis — but they remain judgment constants, not derived values.
3. **fake-codex fidelity is pending the owner's probe run.** Every Codex
   semantic fake-codex simulates is probe-id-anchored and DOWNSTREAM of the
   probe contract, but until the owner runs the probe kit (Phase 0 WI 0.7) the
   fake validates internal consistency, not Codex.
4. **The runner is unverified against real Codex until the canaries.** The
   owner-run real-Codex canary matrix (Phase 14.5) is attended and non-gating;
   the completion-message rule keeps the verbatim "the runner is unverified
   against real Codex" line visible while it is pending.
5. **The pinned literal-cd invocation form is instruction-enforced.** A slice
   agent could still misspell a target-clone write; mitigations are layered
   (the form is pinned in the guide's per-slice step, the plan's port-branch
   rule, and the worklist's literal `port_root`; the 5.2b smoke exercises the
   exact form including the code-classed tracking arm; the corrected deny
   triage turns a misspelling into a one-retry recovery instead of a
   misdiagnosed 2-attempt STOP), but no hook can enforce a spelling.
6. **Phase 12 hit-parity can false-STOP on bookkeeping.** A worklist `hits`
   under-recording fails parity even when the port content is sound — a
   visible, named, per-unit FAIL (never silent), accepted in preference to
   weakening the paraphrase defense.
7. **Registry narrowing vs owner constraint 7.** The first port's kept suite
   set is expected to be materially smaller than the ~130 harness-agnostic
   suites the constraint names — a deliberate, recorded narrowing (keeper floor
   + SPLIT retargets + evident-neutral keeps), surfaced to the owner as named
   residue; widening the kept set is a follow-up registry re-triage, not a
   first-port gate.
