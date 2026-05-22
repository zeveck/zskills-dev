---
title: Plan-claim chip + selection-aware /work-on-plans
created: 2026-05-22
status: active
---

# Plan: Plan-claim chip + selection-aware /work-on-plans

> **Landing mode: PR** — This plan targets PR-based landing. All phases use worktree isolation with a named feature branch.
> (`.claude/zskills-config.json` has `main_protected: true`; PR mode is the only legal landing path.)

## Overview

`/fix-issues` already has a concurrency-safe claim mechanism with a dashboard chip (PR #600, `plans/fix-issues-claims.md`). `/run-plan` does not — two parallel invocations on the same plan today can both pick it up, both dispatch agents, and only race at the `create-worktree` step (or not at all, if the second instance picks a different phase). This plan ports the claim primitive to `/run-plan`, gives plan cards an in-flight chip on the dashboard, adds a structural PreToolUse backstop, and — critically per user mid-draft steering — makes plan SELECTION-aware: the `/work-on-plans` dispatch queue is filtered against existing claims BEFORE any `/run-plan` invocation, closing the STEADY-STATE early-cost race that bit `/fix-issues` even with its acquire-time atomic mkdir.

**Selection-filter placement:** `/run-plan` takes a single `<plan-file>` argument (`skills/run-plan/SKILL.md:4`) — there is no `plans.ready` queue inside `/run-plan` to filter (`grep "plans.ready" skills/run-plan/` returns 0). The picker that reads `plans.ready` and dispatches `/run-plan` lives in `/work-on-plans` (`skills/work-on-plans/SKILL.md:7,594-640`), so the selection-aware filter belongs in `/work-on-plans` Step 4 (just before the dispatch list is finalised, before Step 5's dispatch loop). `/fix-issues` has its OWN candidate-pick in its Phase 2 (independent of /work-on-plans), so the same lesson must propagate there as a follow-up — handled in W4.4.

**Honest race-window accounting (DA2.7).** The orchestrator-level filter closes the STEADY-STATE race (a plan that's been in-flight long enough for its claim file to land on disk before either /work-on-plans invocation runs). It does NOT eliminate the FRESH-START race where two simultaneous /work-on-plans invocations both observe an empty claims-dir at filter time and both pass the same slug through to `/run-plan` dispatch; that residual race is bounded by the acquire-time atomic-mkdir at /run-plan Phase 1 entry (D5/W2a.1). This is acceptable because the cost in the fresh-start case is wasted dispatch overhead (one /run-plan declines with exit 10 acquire-loss), NOT duplicate work. The structural fix for that residual window would require a cross-invocation lock outside the scope of this plan; the two-layer design (filter + acquire-EEXIST) matches the issue-side architecture exactly, with the same residual fresh-start race left uncovered there too.

The mechanism is a SIBLING-CLONE of `claim-issue.sh` (not a generalisation) because plans have an asymmetric schema (string slug, last_heartbeat_at, current_phase) AND introduce a new `refresh` subcommand that has no analogue in claim-issue.sh. Lifecycle is a HYBRID heartbeat: per-plan claim with per-phase heartbeat refresh so multi-day plans don't get auto-swept, and a crashed agent doesn't leak the claim for days.

## Locked Decisions

- **D1 — Claim primitive: SIBLING-CLONE not generalize.** Create `skills/run-plan/scripts/claim-plan.sh` mirroring `skills/fix-issues/scripts/claim-issue.sh`'s atomic-mkdir + Python `os.replace` primitive. Generalising into a `claim-resource.sh <kind> <key>` was rejected because the plan schema adds `last_heartbeat_at`, `current_phase`, and replaces the integer `issue` key with a string `slug` — the per-call payload divergence dominates any code-reuse win, and parallel evolution risk is acceptable for two scripts (issue + plan) with stable contracts. **Cost acknowledgement:** ~430/470 lines (~91%) of `claim-issue.sh` is generic (TTL resolve, MAIN_ROOT resolve, atomic mkdir wrapper, Python json helpers, exit-code mapping); ~9% is schema-specific (`validate_issue_number`, the integer `issue` field, the absence of `refresh`/`last_heartbeat_at`). Acceptable because (a) only two consumers exist, (b) `refresh` is genuinely new code with no analogue to clone, (c) sibling clone keeps each script readable as a single file. Alternative not chosen: extract `claim-resource-common.sh` to be sourced by both siblings — rejected on the grounds that the duplication isn't paying off enough rounds-of-refactor right now and a future third consumer would be the right trigger. **Verification:** read `skills/fix-issues/scripts/claim-issue.sh:117-196` (acquire primitive) and the schema at research summary §1 / §7 — schema fields are NOT a superset relationship. Verified `grep "^cmd_" claim-issue.sh` returns acquire/release/is-stale/sweep/list — `refresh` does NOT exist and must be specified from scratch (see W1.1 micro-spec).

- **D2 — Claim lifecycle: HYBRID heartbeat.** Per-plan claim acquired at `/run-plan` Phase 1 entry, refreshed at every per-phase PIPELINE_ID re-emit fence (the canonical insertion sites — see W2.3 enumerated list), AND additionally refreshed at every cron-fire entry (cron-fire dormant-window protection per DA5), released at `/run-plan stop` OR Phase 6 landing complete. TTL default = 7200s applied to `NOW - last_heartbeat_at` (NOT `NOW - started_at`). Per-PHASE claims rejected (chip flashes 5-10× over a multi-day plan, information-poor); naive per-PLAN rejected (first-phase crash leaks claim for days because there's no liveness signal). **Cron-fire dormant-window state machine (DA5):** when a cron-fired phase Step 0 runs, try `refresh --require-pipeline $PIPELINE_ID`: exit 12 (mismatch) → STOP with `Claim was taken over by another pipeline; aborting.`; exit 0 → proceed; claim dir / claim.json absent → re-acquire (prior turn crashed cleanly between release-and-commit, or claim was never written). **Verification:** research summary §6 D1; staleness comparison done against last-heartbeat means a 7200s TTL sweeps a truly abandoned plan within 2h of its last phase activity, not 2h after its initial start. Cron `*/5` or `*/10` cadences (the recommended /run-plan tempos) refresh ≥1× per TTL window even on long-running phases.

- **D3 — Concurrent /run-plan: acquire-or-report.** Second invocation while a cron-fired one is in-flight reports `Plan X is in-flight (pipeline <short>, started <ago>, phase <N>) — this invocation declined.` and exits 0. Plans are not fungible (re-invocation isn't asking for a different one), so "drop and try next" (issue-claim's behaviour) does not transfer. **Verification:** research summary §6 D2.

- **D4 — Selection-aware filter (CRITICAL — per user mid-draft steering) LIVES IN /work-on-plans.** `/work-on-plans` reads `monitor-state.json`'s `plans.ready` queue and dispatches `/run-plan` from Step 5's loop (`skills/work-on-plans/SKILL.md:594-640`). The filter is inserted in **Step 4** (`skills/work-on-plans/SKILL.md:490-510`) — between `READY_LINES` being built from the TSV (~line 497) and `DISPATCH_COUNT` being capped (~line 503). The filter reads `.zskills/claims/plan-*/claim.json` at the orchestrator level via a small script (W2b.1 — `skills/work-on-plans/scripts/filter-in-flight-plan-claims.sh`), drops any matching slugs from `READY_LINES`, and emits `Skipped N plan(s) currently in-flight: <slugs>` on stderr if any were filtered. This is the failure mode that bit `/fix-issues` in real-world use — atomic acquire at the END of selection is too late; both invocations have already burned cost. The filter is code (a sourced shell function calling the helper script), not prose; Phase 2b's tests include a parallel-invocation steady-state race test that synthesises two work-on-plans dispatch attempts (one writes a claim, then the second filter-passes against the on-disk claim) and asserts the second drops the slug. **Race-window scope (per Overview):** the filter closes the steady-state race (claim already on disk when both invocations run). It does NOT close the fresh-start race (both invocations observe an empty claims-dir before either acquires); that residual window is bounded by Phase 1's atomic-mkdir acquire (W2a.1) — exit 10 returns from the loser is the final defense. Tests honour this scope: `test-work-on-plans-parallel-selection.sh` asserts the STEADY-STATE closure (sequential filter passes after the first invocation's claim landed); it does NOT assert structural elimination of the fresh-start race. **Verification:** user direct quote in research summary's "User steering" section; D5 in research §6. Confirmed `/work-on-plans` is the picker via `grep -n "plans.ready" skills/work-on-plans/SKILL.md` (returns 7,17,33,77,165,298,321,408,596,etc.). **Pre-filter sweep (R2.6):** Step 4 invokes `claim-plan.sh sweep` BEFORE the filter runs, so a stale claim left by a crashed pipeline doesn't permanently block a slug (cleaner than embedding the sweep in the filter itself; symmetric to /fix-issues' Phase 1 sweep).

- **D5 — Storage: `.zskills/claims/plan-<slug>/claim.json`.** Symmetric with `.zskills/claims/issue-<N>/`. Lives under `.zskills/claims/` NOT `.zskills/tracking/` (different hook semantics — `hooks/block-unsafe-project.sh.template` already fence-protects every `.zskills/<subtree>/` against recursive deletion at line 531, but tracking-fence sibling-check would mis-fire on claim files). Schema (sorted-keys JSON, schema_version=1):
  ```json
  {
    "schema_version": 1,
    "kind": "plan",
    "slug": "<plan-file-basename>",
    "pipeline_id": "run-plan.<slug>",
    "started_at": "<ISO-8601 UTC>",
    "last_heartbeat_at": "<ISO-8601 UTC>",
    "current_phase": "Phase <N>"
  }
  ```
  **Verification:** research §7 schema; `claim-issue.sh:171-185` for the atomic-write Python block to clone. Hook-fence file confirmed: `grep ".zskills" hooks/block-unsafe-generic.sh` shows no fence; `grep -n ".zskills" hooks/block-unsafe-project.sh.template` shows the rm-rf fence at line 531.

- **D6 — Visual identity: REUSE `.claim-chip--in-flight` CSS class.** Same yellow chip; chip TEXT differs (`in-flight · <pidShort> · phase N/M · <ageStr>` for plans vs. `in-flight · <pidShort> · <ageStr>` for issues). Card kind is already encoded via `data-kind="plan"|"issue"`. The `ageStr` is computed once at render time (snapshot-driven, not 1s tick) and may go stale between heartbeats; this matches issue-chip behavior exactly and is not a regression. A 60s re-render tick for aria-disabled cards is out of scope (known limitation; documented in Phase 3). **Verification:** `static/app.js:951-976` shows issue chip; `app.css` `.claim-chip--in-flight` rule is class-only, not selector-scoped to issue cards.

- **D7 — PreToolUse backstop: SIBLING-CLONE hook.** Create `hooks/block-run-plan-unclaimed.sh` from `hooks/block-fix-issue-unclaimed.sh` (229 lines).

  **Branch-name regex (DA2.1-fixed — phase-suffix shape):** the hook must match THREE concrete branch shapes:
  1. Cherry-pick finish-mode plan-scoped branch: `cp-<slug>` (`skills/run-plan/SKILL.md:1074-1078`).
  2. Cherry-pick single-phase scoped branch: `cp-<slug>-phase-<N>` (same site, the `else` arm — verified by `grep -n 'cp-\${PLAN_SLUG}-phase' skills/run-plan/SKILL.md` → lines 1077, 1116-1117).
  3. PR-mode branch: `${BRANCH_PREFIX}<slug>` (`skills/run-plan/SKILL.md:1326`). PR mode has NO per-phase shape — verified by `grep -n 'feat/.*-phase-\|BRANCH_PREFIX.*phase' skills/run-plan/SKILL.md` → 0 hits (the PR mode bookkeeping at line 926 uses `${BRANCH_PREFIX}${PLAN_SLUG}` only). Only the cherry-pick path has a phase-scoped variant.

  Hook regex (Python, applied to extracted branch name): `^(cp-)([a-z0-9][a-z0-9-]*?)(-phase-[0-9]+)?$` OR `^(<escaped-branch-prefix>)([a-z0-9][a-z0-9-]*)$`. Try both in sequence; on the cp-prefix match, capture group 2 is the slug and group 3 is the (optional) phase suffix (used only for diagnostic/decline logging — the claim is per-plan, not per-phase). The non-greedy `*?` quantifier on the slug ensures `cp-foo-phase-2` is parsed as slug=`foo`, phase=`-phase-2` (NOT slug=`foo-phase-2`). On the PR-prefix match, capture group 2 is the slug. **Do not copy the `[0-9]+` validator from the issue-side hook (R2.5)** — plan slugs are kebab-case strings, not integers.

  **Config-read pattern (R2.1/DA2.2 — option (b), Python config-read):** `BRANCH_PREFIX` is NOT exported by `zskills-resolve-config.sh` (verified: `grep -n 'BRANCH_PREFIX\|branch_prefix' skills/update-zskills/scripts/zskills-resolve-config.sh` → 0 hits; resolver exposes UNIT_TEST_CMD, FULL_TEST_CMD, TIMEZONE, etc. at lines 71-83 plus claim_ttl_seconds at 138-148 via Python json, but no branch_prefix line). Rather than extend the resolver for this one-off hook read, the hook parses `${CLAUDE_PROJECT_DIR}/.claude/zskills-config.json` directly via Python json (mirroring the resolver's existing claim_ttl pattern at lines 138-148):

  ```python
  # In the hook (Python block)
  import json, os, re
  cfg_path = os.path.join(os.environ.get("CLAUDE_PROJECT_DIR", ""), ".claude", "zskills-config.json")
  branch_prefix = "feat/"
  try:
      with open(cfg_path) as f:
          d = json.load(f)
      branch_prefix = d.get("execution", {}).get("branch_prefix", "feat/")
  except Exception:
      pass  # default 'feat/' is fine
  prefix_re = re.escape(branch_prefix)
  ```

  Rationale: avoids resolver bloat for a single read at PreToolUse time, and the resolver pattern already establishes Python-json as the supported parser for execution-block fields. If a future consumer also needs `BRANCH_PREFIX` at fence-resolve time (not just hook-time), `R2.1 alternative (a)` — extending the resolver to export `ZSKILLS_BRANCH_PREFIX` — can be added then with a corresponding resolver-test. For now, the hook is the sole consumer.

  **Direct-mode gap acknowledged (DA8):** direct mode does not create a worktree, so `create-worktree.sh` is never invoked and the hook does not fire.

  **Delegate-mode gap acknowledged (DA2.5):** delegate mode (`skills/run-plan/SKILL.md:995-1017`) runs the delegated skill on main without invoking `create-worktree.sh` directly — the delegate skill manages its own worktree if any. The PreToolUse hook therefore does not fire on delegate-mode entry. The protection in both direct and delegate modes is W2a.1's inline acquire call at Phase 1 entry — which runs BEFORE the mode-detection branch — so every entry path (worktree / PR / cherry-pick / direct / delegate) hits the acquire fence. There is no structural PreToolUse backstop for direct or delegate modes; documented as known scope limits.

  **Plans-dir resolution (DA12):** the "slug-must-be-a-real-plan-file" check sources `skills/update-zskills/scripts/zskills-paths.sh` to resolve `$ZSKILLS_PLANS_DIR` (NOT hardcoded `plans/`), so consumers with custom `output.plans_dir` are correctly handled.

  **Slug character-set (DA13):** the hook passes the captured slug through `skills/create-worktree/scripts/sanitize-pipeline-id.sh` before checking the claim-dir existence; a slug with `+`, leading `-`, or other pathological chars is rejected (pass-through) rather than risking a missed match.

  **Verification:** read `hooks/block-fix-issue-unclaimed.sh:1-80` for the template; `skills/run-plan/SKILL.md:1326` for the PR-mode `BRANCH_NAME=` line; `skills/run-plan/SKILL.md:1074-1078` for both cherry-pick shapes; `.claude/zskills-config.json` for the `branch_prefix` default; `skills/update-zskills/scripts/zskills-resolve-config.sh:138-148` for the Python-json claim_ttl pattern this hook mirrors.

## What this plan does NOT do

- Does NOT redesign or modify `/fix-issues`'s claim mechanism (issue claims keep `claim-issue.sh`; this plan adds a sibling, not a refactor).
- Does NOT change the visual identity of the claim-chip — same CSS class, only chip text varies.
- Does NOT introduce a new top-level skill (no `/claim` or `/plan-claim` slash command — claim machinery is internal to `/run-plan` and `/work-on-plans`).
- Does NOT generalise `claim-issue.sh` into a polymorphic `claim-resource.sh` (see D1).
- Does NOT add cross-host or network-shared claims; same single-host POSIX-mkdir bound as `/fix-issues`.
- Does NOT change `monitor-state.json` schema; collector reads `.zskills/claims/` on each snapshot and attaches `plan["claim"]` to the GET response (mirror of issue side).
- Does NOT retroactively claim plans that are already mid-execution when this lands; the first `/run-plan` invocation after this PR ships starts using claims.
- Does NOT investigate the `/fix-issues` real-world double-pick failure beyond porting its lesson into `/work-on-plans`'s structural filter — that investigation is a separate follow-up issue (see Phase 4 W4.4), which points specifically at `/fix-issues` Phase 2 candidate-pick (NOT /work-on-plans, since /fix-issues has its own picker independent of work-on-plans).
- Does NOT add a 60s re-render tick to keep `ageStr` fresh between heartbeats. Matches issue-chip behavior; known scope limit (DA11).
- Does NOT cover direct mode with a PreToolUse hook (no worktree creation hook trigger). Inline acquire in /run-plan Phase 1 is the only protection in direct mode (DA8).

## Acceptance Criteria (plan-level)

- **A1.** `.zskills/claims/plan-<slug>/claim.json` is written on `/run-plan` Phase 1 entry and removed at Phase 6 landing-complete OR `/run-plan stop`. **Verification:** grep `claim-plan.sh acquire` and `claim-plan.sh release` calls in `skills/run-plan/SKILL.md`; manual e2e: invoke `/run-plan plans/sample.md`, verify file present after Phase 1 dispatch, absent after Phase 6 land-complete.

- **A2.** Two parallel `/run-plan plans/X.md` invocations on the same plan: exactly one acquires the claim; the other reports `Plan X is in-flight (pipeline <short>, started <ago>) — this invocation declined.` and exits 0. **Verification:** `tests/test-plan-claim-race-e2e.sh` backgrounds two `claim-plan.sh acquire` calls; assert exactly one returns 0 and the other returns 10.

- **A3.** `/work-on-plans` selection FILTERS in-flight plans from the candidate queue BEFORE dispatching any `/run-plan`. **Verification:** `tests/test-plan-claim-selection-filter.sh` writes a synthetic `.zskills/claims/plan-foo/claim.json` with a valid pipeline + non-stale heartbeat, sets up a monitor-state with `plans.ready = [foo, bar]`, invokes `/work-on-plans` Step 4 selection code path, asserts: (a) `foo` is filtered out of `READY_LINES`, (b) stderr contains `Skipped 1 plan(s) currently in-flight: foo`, (c) `bar` is the picked plan.

- **A4.** Claim chip renders on plan cards with `aria-disabled=true` set; `moveAllInColumn` (PR #617) and per-card move/remove handlers skip claimed plans. **Verification:** `tests/test-plan-claim-render-dom.sh` asserts chip presence + aria-disabled on synthetic-claim plan card; asserts move-all bulk operation skips the card; asserts handleAction guard refuses `plan-up/down/left/right/plan-remove` on aria-disabled card.

- **A5.** Heartbeat refresh updates `last_heartbeat_at` each phase AND at each cron-fire entry; TTL applies to last-heartbeat (not started_at). **Verification:** `tests/test-plan-claim-script.sh` invokes `acquire`, sleeps 2s, invokes `refresh`, reads claim.json, asserts `last_heartbeat_at > started_at`. `tests/test-plan-claim-ttl-config-resolver.sh` invokes `is-stale` with TTL=1, last-heartbeat=NOW-2 → stale; TTL=1, started_at=NOW-2 AND last-heartbeat=NOW → fresh. `tests/test-plan-claim-cron-fire-state-machine.sh` covers the DA5 state machine (refresh exit 0 / exit 12 / no-claim re-acquire).

- **A6.** `/run-plan stop` releases the claim. **Verification:** `tests/test-plan-claim-release-stop.sh` asserts `claim.json` is removed when the `/run-plan stop` code path runs (around `skills/run-plan/SKILL.md:357`, just before the report-block), regardless of phase progress.

- **A7.** All touched SKILL.md `metadata.version` fields are bumped per layer-4 enforcement; `test-skill-conformance.sh` passes. **Verification:** CI gate (`tests/test-skill-conformance.sh`); local run before each phase commit via the four enforcement layers (warn-config-drift Edit-time, `/commit` step 2.5, conformance CI, block-stale-skill-version PreToolUse hook).

- **A8.** Pipeline-mismatched refresh is refused. **Verification:** `tests/test-plan-claim-script.sh` invokes `acquire` with pipeline=A, then `refresh` with `--require-pipeline B` → exit 12, claim.json unchanged.

- **A9.** Hook regex matches THREE branch shapes: `cp-<slug>` (finish-mode cherry-pick), `cp-<slug>-phase-<N>` (single-phase cherry-pick), AND `${BRANCH_PREFIX}<slug>` (PR mode). **Verification:** `tests/test-plan-claim-hook-deny.sh` includes all three branch-name cases including `cp-<slug>-phase-1` AND `cp-<slug>-phase-12` (two-digit phase) and asserts the same plan-scoped claim dir is consulted in all three cases.

- **A10.** Claim writes anchor to MAIN_ROOT (`git rev-parse --git-common-dir` parent) even when acquire is called from a worktree. **Verification:** `tests/test-plan-claim-main-root-anchor.sh` runs acquire from a worktree, asserts the claim file lands in main's `.zskills/claims/`, not the worktree's.

- **A11.** Phase 1 acquire fence precedes the mode-detection branch (so the inline acquire reaches every mode: worktree / PR / cherry-pick / direct / delegate). **Verification:** `tests/test-plan-claim-conformance.sh` asserts the acquire fence appears BEFORE the first `### Execution: ...` mode line.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| Phase 1 — Claim primitive + on-disk schema + PreToolUse hook | ✅ | `9c8fd56` | 6 new artifacts (claim-plan.sh, claim-fence-helpers.sh, block-run-plan-unclaimed.sh + .claude mirrors) + Step 3.7.1 + 5 test files (42 new tests). 5415/5415 pass. |
| Phase 2a — /run-plan acquire/heartbeat/release wiring | ✅ | `a64469c` | 11 fence sites wired in /run-plan SKILL.md + 8 new tests (66 new + 2 conformance picks). 5481/5481 pass. |
| Phase 2b — /work-on-plans selection-aware filter | ✅ | `41b9a99` | filter-in-flight-plan-claims.sh (200 lines) + Step 4 sweep+filter fences + 4 new tests (28 pass). 5503/5503 pass. |
| Phase 3 — Dashboard collect.py + render-side wiring | ⬚ | — | — |
| Phase 4 — Conformance tests + integration + SKILL.md prose | ⬚ | — | — |
| Phase 5 — Optional cleanup + verification | ⬚ | — | — |

---

## Phase 1 — Claim primitive + on-disk schema + PreToolUse hook

### Goal

Create the `claim-plan.sh` sibling script (with the new `refresh` subcommand spec'd from scratch) and the `block-run-plan-unclaimed.sh` PreToolUse hook; ship TTL + resolver tests during this phase (NOT as follow-up, per the PR #607 lesson).

### Work Items

- [ ] **W1.1** — Create `skills/run-plan/scripts/claim-plan.sh` with subcommands `acquire`, `refresh`, `release`, `is-stale`, `sweep`, `list`. Mirror the structure of `skills/fix-issues/scripts/claim-issue.sh` for the ~91% generic parts (resolve_ttl, resolve_main_root, atomic mkdir, Python helpers, exit-code mapping). The `refresh` subcommand has NO analogue in claim-issue.sh and must be implemented from scratch per the micro-spec below. **Slug sanitisation (DA13):** the `acquire`/`refresh`/`release` entry points pipe the bare `<slug>` argument through `skills/create-worktree/scripts/sanitize-pipeline-id.sh` (NOT just the PIPELINE_ID); a slug containing `+`, leading `-`, or `_` is normalised or rejected with exit 2.
- [ ] **W1.2** — Add a sourceable wrapper `skills/run-plan/scripts/claim-fence-helpers.sh` exposing `sweep_stale_plan_claims()` for `/run-plan` Phase 1 preflight (mirror of `skills/fix-issues/scripts/claim-fence-helpers.sh`).
- [ ] **W1.3** — Create `hooks/block-run-plan-unclaimed.sh` from `hooks/block-fix-issue-unclaimed.sh`, retargeted to the THREE branch shapes documented in D7: `cp-<slug>` (finish-mode cherry-pick), `cp-<slug>-phase-<N>` (single-phase cherry-pick — captured by the optional `(-phase-[0-9]+)?` group in the cp-prefix regex), AND `${BRANCH_PREFIX}<slug>` (PR mode, where `$branch_prefix` is read from `execution.branch_prefix` in `${CLAUDE_PROJECT_DIR}/.claude/zskills-config.json` via inline Python json — per D7's R2.1 option (b)). Sources `zskills-paths.sh` to resolve `$ZSKILLS_PLANS_DIR` for the slug-is-real-plan-file check. **Do not clone the `[0-9]+` validator from the issue-side hook (R2.5)** — plan slugs are kebab-case `[a-z0-9][a-z0-9-]*`, not integers; the issue-side validator must be replaced wholesale, not adapted. Register in `.claude/settings.json` under `hooks.PreToolUse` for `Bash`.
- [ ] **W1.4** — Document `execution.plan_claim_ttl_seconds` in `skills/update-zskills/SKILL.md` Step 3.7 (the existing `claim_ttl_seconds` backfill section, lines 538-552) — add a sub-step 3.7.1 covering `plan_claim_ttl_seconds` with identical idempotency + sed detection-regex pattern. **Resolver extension OPTIONAL (per R2.1/DA2.2 option (b) in D7):** the resolver itself does NOT need an export for `ZSKILLS_PLAN_CLAIM_TTL_SECONDS`; `claim-plan.sh` reads the config field inline via Python json (mirroring resolver lines 138-148's pattern for `claim_ttl_seconds`). If a future caller needs the resolved value at fence-resolve time outside `claim-plan.sh`, add the resolver export then with a paired resolver-test — the cost is a single-line Python json read + a four-level env/config fallback echo, matching the existing pattern. Note: the existing resolver already exports `ZSKILLS_CLAIM_TTL_SECONDS` (line 138-148 region), so the shared/fallback level is reachable from any sourced fence; only the plan-specific level needs to be added if/when resolver-side exposure becomes desired.
- [ ] **W1.5** — Write `tests/test-plan-claim-script.sh` (unit tests: acquire/refresh/release/is-stale/sweep/list + pipeline-mismatch refusal + crash-window 30s protection + concurrent-refresh-no-partial-JSON assertion).
- [ ] **W1.6** — Write `tests/test-plan-claim-race-baseline.sh` (parallel-acquire baseline race, mirror of `test-fix-issues-claim-race-baseline.sh`).
- [ ] **W1.7** — Write `tests/test-plan-claim-ttl-config-resolver.sh` (TTL resolution precedence — 5 levels, one test per fallback step):

  | Level | Source | Test fixture |
  |---|---|---|
  | 1 | env `ZSKILLS_PLAN_CLAIM_TTL_SECONDS` | export=1234; config absent; assert resolver returns 1234 |
  | 2 | config `execution.plan_claim_ttl_seconds` | env unset; config `{plan_claim_ttl_seconds: 1234}`; resolver=1234 |
  | 3 | env `ZSKILLS_CLAIM_TTL_SECONDS` (shared issue/plan fallback) | env unset for plan-specific; export `ZSKILLS_CLAIM_TTL_SECONDS=1234`; resolver=1234 |
  | 4 | config `execution.claim_ttl_seconds` (shared fallback) | all envs unset; config `{claim_ttl_seconds: 1234}` (NO plan-specific key); resolver=1234 |
  | 5 | built-in 7200 | all envs unset; config missing both keys; resolver=7200 |

  Resolution is implemented inline in `claim-plan.sh resolve_ttl()` (matches option (b) of D7's config-read pattern — `claim-plan.sh` reads `${CLAUDE_PROJECT_DIR}/.claude/zskills-config.json` via inline Python json, walking the chain: try env `ZSKILLS_PLAN_CLAIM_TTL_SECONDS` first, fall through to config plan key, then env shared, then config shared, then built-in 7200). This keeps the resolver itself unchanged (R2.1/DA2.2 option (b)); if W1.4 lands the resolver-side env-var population in a follow-up, the env-var precedence levels 1 and 3 will fire from the resolver-exported values, but the test fixtures stay identical because env vars dominate config reads regardless of who populated them.
- [ ] **W1.8** — Bump `skills/run-plan/SKILL.md` `metadata.version` field per layer-4 enforcement (warn-config-drift, /commit step 2.5, CI conformance, block-stale-skill-version PreToolUse).
- [ ] **W1.9** — Write `tests/test-plan-claim-hook-deny.sh` covering THREE branch forms (per A9):
  - `create-worktree.sh --prefix cp <slug>` (cherry-pick finish-mode, branch `cp-<slug>`)
  - `create-worktree.sh --branch-name cp-<slug>-phase-1` (single-phase cherry-pick, one-digit phase)
  - `create-worktree.sh --branch-name cp-<slug>-phase-12` (single-phase cherry-pick, two-digit phase — confirms the `[0-9]+` quantifier handles multi-digit)
  - `create-worktree.sh --branch-name feat/<slug>` (PR mode)

  Each case: with claim absent → deny envelope; with claim present (`.zskills/claims/plan-<slug>/` created) → pass-through. All three cp-shapes consult the SAME plan-scoped claim dir (`plan-<slug>/`, NOT `plan-<slug>-phase-N/`) — the assertion exercises the non-greedy slug capture in the D7 regex.
- [ ] **W1.10** — Write `tests/test-plan-claim-main-root-anchor.sh` exercising the DA7 invariant: acquire from a worktree CWD, assert claim file lands in main's `.zskills/claims/`, not the worktree's.

### Design & Constraints

**`claim-plan.sh acquire` signature:**

    claim-plan.sh acquire <slug> --pipeline-id <id>

`<slug>` is first passed through `sanitize-pipeline-id.sh` then must match `^[a-z0-9][a-z0-9-]*$` after sanitisation (DA13). Pre-sanitisation slugs with `+`, leading `-`, or `_` are normalised; truly pathological slugs return exit 2.

**Exit codes (mirror `claim-issue.sh`):**

| Code | Meaning |
|------|---------|
| 0 | success |
| 2 | usage error |
| 10 | EEXIST (race lost) |
| 11 | other infrastructure failure |
| 12 | pipeline-mismatch on release/refresh |

**`refresh` signature (DA10 — new subcommand, spec'd from scratch, no claim-issue.sh analogue):**

    claim-plan.sh refresh <slug> --require-pipeline <id> --current-phase "Phase <N>"

Implementation pattern (NOT cloneable from acquire — it's read-modify-write, not atomic mkdir):

1. Resolve MAIN_ROOT and claim path identically to acquire.
2. Read existing `claim.json` via Python. If file missing → return exit 2 with stderr `claim.json missing for slug <slug>; use acquire to create.` (the caller's cron-fire state machine — DA5 — interprets exit 2 here as "re-acquire").
3. If stored `pipeline_id` ≠ `--require-pipeline`: return exit 12 (NO mutation). Stderr: `pipeline-mismatch: stored=<A> required=<B>; refusing refresh.`
4. Mutate the in-memory dict: `last_heartbeat_at = now_iso8601_utc`, `current_phase = <value>` (verbatim quoted string).
5. Atomic write via temp file + `os.replace` (the same Python primitive as acquire's write step).
6. Return exit 0.

This is a distinct shape from acquire's mkdir-then-replace (refresh has no mkdir step and no EEXIST mapping). Concurrent-refresh atomicity: the `os.replace` is POSIX-atomic; reading a partial JSON is impossible because the reader either sees the pre-replace file or the post-replace file.

**`release` signature:**

    claim-plan.sh release <slug> --require-pipeline <id>

Removes `claim.json`, then `rmdir` of the claim dir. Refuses (exit 12) if pipeline mismatch.

**`is-stale` signature:**

    claim-plan.sh is-stale <slug>

Reads `last_heartbeat_at` from `claim.json`, compares against `NOW - TTL`. Exit 0 = stale; exit 1 = fresh; exit 2 = no claim / unparseable. **Crash-window protection:** if `claim.json` is missing inside an existing claim dir AND dir mtime > 30s ago, treat as stale (matches `claim-issue.sh` D4 R7).

**`sweep` signature:**

    claim-plan.sh sweep

Iterates `.zskills/claims/plan-*/`, calls `is-stale` per entry, removes stale ones.

**TTL resolution (5-level chain — R2.2, mirror `claim-issue.sh:100-112` shape but with the plan-specific key inserted at the head):**

    resolve_ttl() {
      # Level 1: env ZSKILLS_PLAN_CLAIM_TTL_SECONDS (plan-specific override)
      local ttl="${ZSKILLS_PLAN_CLAIM_TTL_SECONDS:-}"
      if [ -z "$ttl" ] && [ -n "$ZSKILLS_PYTHON" ] && [ -f "$_ZSK_CFG" ]; then
        # Level 2: config execution.plan_claim_ttl_seconds (plan-specific)
        ttl=$("$ZSKILLS_PYTHON" -c "import json
try:
  d=json.load(open('$_ZSK_CFG')).get('execution',{})
  v=d.get('plan_claim_ttl_seconds')
  print(v if v is not None else '')
except Exception:
  print('')" 2>/dev/null) || ttl=""
      fi
      # Level 3: env ZSKILLS_CLAIM_TTL_SECONDS (shared fallback — issue + plan)
      [ -z "$ttl" ] && ttl="${ZSKILLS_CLAIM_TTL_SECONDS:-}"
      if [ -z "$ttl" ] && [ -n "$ZSKILLS_PYTHON" ] && [ -f "$_ZSK_CFG" ]; then
        # Level 4: config execution.claim_ttl_seconds (shared fallback)
        ttl=$("$ZSKILLS_PYTHON" -c "import json
try:
  d=json.load(open('$_ZSK_CFG')).get('execution',{})
  v=d.get('claim_ttl_seconds')
  print(v if v is not None else '')
except Exception:
  print('')" 2>/dev/null) || ttl=""
      fi
      # Level 5: built-in
      [ -z "$ttl" ] && ttl=7200
      case "$ttl" in
        ''|*[!0-9]*) ttl=7200 ;;
      esac
      if [ "$ttl" -lt 60 ] 2>/dev/null; then ttl=7200; fi
      echo "$ttl"
    }

Per R2.1/DA2.2 option (b), the resolver itself does NOT need to be extended — `claim-plan.sh` reads `${CLAUDE_PROJECT_DIR}/.claude/zskills-config.json` directly via inline Python json. The 5-level chain is enforced inside the script (not split between resolver + script), making the precedence test (`test-plan-claim-ttl-config-resolver.sh` W1.7) able to assert all 5 levels by fixturing the env + config inputs together.

**MAIN_ROOT resolution:** `git rev-parse --git-common-dir` parent — NEVER `$PWD`. This is the structural anchor that makes claim writes immune to Issue #604 (PR-mode marker propagation): regardless of whether acquire/refresh/release is called from main or a worktree, the claim file lands in main's `.zskills/claims/`. Tested explicitly via `test-plan-claim-main-root-anchor.sh`.

**Hook (`block-run-plan-unclaimed.sh`):**

- Trigger: Bash tool calls matching `(create-worktree|ensure-worktree)\.sh`.
- Branch-name resolution: clone `claim-issue.sh` Python shlex tokenisation (NOT regex over the command string). Extract `--branch-name` or `--prefix cp` form.
- Sources `zskills-resolve-config.sh` → reads `$BRANCH_PREFIX` (default `feat/`). Escapes regex meta-chars via inline Python `re.escape`.
- Match pattern (Python regex — unified with D7 line 55, R3.4): try TWO regexes in sequence:
  - Cherry-pick variant: `^(cp-)([a-z0-9][a-z0-9-]*?)(-phase-[0-9]+)?$` — captures slug in group 2 (non-greedy so `cp-foo-phase-2` → slug=`foo`); group 3 is the optional `-phase-<N>` suffix used only for diagnostic logging.
  - PR-mode variant: `^(<escaped-branch-prefix>)([a-z0-9][a-z0-9-]*)$` — captures slug in group 2. PR mode has no per-phase variant (verified D7 §1).
- Sources `zskills-paths.sh` → reads `$ZSKILLS_PLANS_DIR` (default `plans`).
- Pass-through if (a) branch does not match the pattern, OR (b) slug does not correspond to any `${ZSKILLS_PLANS_DIR}/<slug>.md` file (defensive: feature branches for non-plan work are untouched), OR (c) slug fails post-sanitise validation.
- Deny envelope (mirror `block-fix-issue-unclaimed.sh`) when no `${MAIN_ROOT}/.zskills/claims/plan-${SLUG}/` exists. Recovery instructions in `permissionDecisionReason` cite `bash skills/run-plan/scripts/claim-plan.sh acquire <slug> --pipeline-id "run-plan.<slug>"`.
- **Direct-mode gap (DA8):** hook is gated on create-worktree.sh / ensure-worktree.sh invocations. Direct mode does not invoke those, so the hook does not fire there. Inline acquire (W2a.2) is the only protection in direct mode; this is a known and accepted scope limit.

### Tests

- `tests/test-plan-claim-script.sh` — unit: acquire/refresh/release/is-stale/sweep/list; pipeline-mismatch refusal; crash-window 30s protection; concurrent-refresh-no-partial-JSON.
- `tests/test-plan-claim-race-baseline.sh` — two backgrounded `acquire` invocations from a clean state; exactly one exit 0, exactly one exit 10.
- `tests/test-plan-claim-ttl-config-resolver.sh` — resolution precedence (5-level: env-plan > config-plan > env-shared > config-shared > built-in).
- `tests/test-plan-claim-hook-deny.sh` — BOTH branch forms (`cp-<slug>` and `feat/<slug>`); claim absent → deny; claim present → pass-through.
- `tests/test-plan-claim-main-root-anchor.sh` — acquire from worktree CWD, assert claim lands in main's tree.

### Acceptance Criteria (phase-level)

- **AC1.1** — `bash skills/run-plan/scripts/claim-plan.sh acquire foo --pipeline-id run-plan.foo` writes `.zskills/claims/plan-foo/claim.json` with all 7 D5 schema fields. **Verification:** unit test reads the file with Python json and asserts the field set.
- **AC1.2** — Two parallel acquires from a clean state: one exit 0, one exit 10. **Verification:** `tests/test-plan-claim-race-baseline.sh`.
- **AC1.3** — `refresh --require-pipeline <wrong>` returns exit 12 and does not mutate `claim.json`. **Verification:** unit test reads claim before and after the refused refresh.
- **AC1.4** — PreToolUse hook denies an unclaimed worktree creation for all THREE branch shapes: `cp-<slug>`, `cp-<slug>-phase-<N>` (one-digit AND two-digit N), and `${BRANCH_PREFIX}<slug>`. All three resolve to the SAME plan-scoped claim dir (`plan-<slug>/`). **Verification:** `tests/test-plan-claim-hook-deny.sh` (W1.9 — covers all four cases including phase-1 and phase-12).
- **AC1.5** — `skills/run-plan/SKILL.md metadata.version` matches today + content hash (no stale-version deny). **Verification:** `bash tests/run-all.sh` includes `test-skill-conformance.sh`.
- **AC1.6** — Claim writes anchor to MAIN_ROOT even when acquire is called from a worktree. **Verification:** `tests/test-plan-claim-main-root-anchor.sh`.

### Dependencies

None — Phase 1 is foundational.

---

## Phase 2a — /run-plan acquire / heartbeat / release wiring

### Goal

Wire `claim-plan.sh` into `/run-plan`'s acquire, heartbeat, and release sites — using the empirically-identified per-phase PIPELINE_ID re-emit blocks as canonical heartbeat anchors (NOT a "Step 0 boilerplate" that doesn't exist).

### Work Items

- [ ] **W2a.1** — **Acquire site:** in `skills/run-plan/SKILL.md` Phase 1 entry (after preflight idempotent-re-entry check, before any worktree dispatch), insert a bash fence calling `bash "$CLAUDE_PROJECT_DIR/.claude/skills/run-plan/scripts/claim-plan.sh" acquire "$PLAN_SLUG" --pipeline-id "$PIPELINE_ID"`. Exit 10 → report `Plan $PLAN_SLUG is in-flight by pipeline <short>; this invocation declined.` and exit 0. Exit 11 → STOP (Failure Protocol).
- [ ] **W2a.2** — **Heartbeat sites — section-header anchors (DA2.6 — line-number-resistant).** Insert a `claim-plan.sh refresh` call immediately after each of the per-phase PIPELINE_ID re-emit blocks. To avoid line-number drift the moment Phase 1's acquire fence lands, implementer locates each canonical site by SECTION HEADER name, then finds the nearest following `PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"` re-emit fence within that section, and inserts the refresh call immediately after that fence's closing `\`\`\``.

  The canonical insertion sites and their owning section headers (each section verified to contain a PIPELINE_ID re-emit by `grep -n 'ZSKILLS_PIPELINE_ID' skills/run-plan/SKILL.md`):

  | Section header (locate by name) | Phase |
  |---|---|
  | `### Parse plan` | Phase 1 (within Phase 1, Phase 2 entry has its own re-emit) |
  | `### Post-implementation tracking` | Phase 2 exit |
  | `### Post-verification tracking` | Phase 3 exit |
  | `### 5. Marker ordering and failure handling` | Phase 3.5 |
  | `### Post-report tracking` | Phase 5 exit |
  | `### 0a. Idempotent early-exit` | Phase 5b (handled by W2a.4 §0a release, NOT a refresh site) |
  | `### 0b. Final-verify gate` | Phase 5b — TWO PIPELINE_ID re-emits exist within this section (one near the attempts-file path computation, one at the branch-1 cron-defer; W2a.4 §0b uses ONE of them as the refresh site) |
  | ~~`### Post-landing tracking`~~ | Phase 6 — handled by W2a.4 release site 3, NOT a refresh site (DA3.2 — struck to prevent dual-action collision in the same section) |

  Use the fence pattern:

      bash "$CLAUDE_PROJECT_DIR/.claude/skills/run-plan/scripts/claim-plan.sh" \
        refresh "$PLAN_SLUG" \
        --require-pipeline "$PIPELINE_ID" \
        --current-phase "<section-name-verbatim>"

  Exit 12 → STOP with `Claim was taken over by another pipeline; aborting.` Exit 2 (claim.json missing) → cron-fire state machine: re-acquire (see W2a.3). Post-phase blocks (Post-implementation, Post-verification, Post-report, Post-landing) ARE valid anchors — the heartbeat refresh confirms liveness at phase exit, complementing the phase-entry anchors. R2.4 clarified.

  The `--current-phase` argument is the section header verbatim (e.g., `"Parse plan"`, `"Post-implementation tracking"`, `"Post-landing tracking"`); dashboard render side parses it for the chip's `phase N/M` text (Phase 3 W3.7).

- [ ] **W2a.3** — **Cron-fire dormant-window state machine (DA5).** At the cron-fired phase entry (the same PIPELINE_ID re-emit blocks that are dispatched by cron, primarily line 898 for Phase 2 entry), wrap the heartbeat refresh in a state-machine fence. **Scope (R3.3):** apply the state-machine wrap to the W2a.2 refresh calls at every PHASE-ENTRY anchor reached via cron-defer (`### Parse plan`, `### Post-implementation tracking`, `### Post-verification tracking`, `### 5. Marker ordering and failure handling`, `### Post-report tracking`, `### 0b. Final-verify gate` cron-defer site). All current W2a.2 anchors are phase-entry-class (post-DA3.2 strike of `### Post-landing tracking`); if a future plan adds a phase-EXIT-only anchor that is NOT reached via cron-defer, a plain refresh without the state-machine fence is acceptable there.
  - Try `claim-plan.sh refresh ... --require-pipeline "$PIPELINE_ID"`.
  - exit 0 → proceed.
  - exit 12 → STOP with mismatch message.
  - exit 2 (claim absent) → re-acquire via `claim-plan.sh acquire`. If re-acquire returns 0, proceed; if 10 (someone else claimed in the meantime), STOP with `Claim was acquired by another pipeline during the cron-fire dormant window; aborting.`; if 11, STOP via Failure Protocol.
- [ ] **W2a.4** — **Release + refresh sites (DA2.3-fixed): THREE release sites + ONE refresh site.**

  **Release site 1 — /run-plan stop handler** (`skills/run-plan/SKILL.md`, locate by `^## Stop` section header; insert at step 3.5, after step 3's bash fence (~line 358, ends with the `rm -f .../cron-recovery-needed.*` line) and BEFORE step 4 begins (the report-what-was-cancelled block) — R2.3-tightened anchor). The handler uses the Option A walk: iterate `.zskills/claims/plan-*/` and call `claim-plan.sh release <slug> --require-pipeline run-plan.<slug>` for every claim whose `pipeline_id` starts with `run-plan.`. Mismatched pipeline IDs are skipped (exit 12 is ignored — those claims belong to other in-flight runs and must not be clobbered). The handler counts both releases and skips, and emits to stderr `Stop released N claim(s); skipped M claim(s) (pipeline mismatch).` (DA2.9). **Stop semantics — session-wide halt by design, not per-plan (DA2.8):** the stop handler ALREADY deletes ALL crons whose prompt starts with `Run /run-plan` (line 343), so the all-plans claim walk is symmetric. This is intentional and surfaces in the Stop section's documentation; not a per-plan-only contract.

  **Release site 2 — Phase 5b §0a "Plan already complete" (DA2.3 — NEW SITE).** Section header `### 0a. Idempotent early-exit` (`skills/run-plan/SKILL.md:2096-2099`). On no-op re-entry, Phase 1 has already acquired the claim for this pipeline; without an explicit release the claim leaks until either /run-plan stop or a sweep TTL fires. Insert a release call IMMEDIATELY BEFORE the no-op exit:

      bash "$CLAUDE_PROJECT_DIR/.claude/skills/run-plan/scripts/claim-plan.sh" \
        release "$PLAN_SLUG" --require-pipeline "$PIPELINE_ID" 2>/dev/null || true

  Suppress release-on-no-op errors (the claim may already be absent from a prior partial cleanup; we want exit-clean semantics on the §0a no-op branch, not a Failure Protocol invocation). Exit 12 (pipeline mismatch) is acceptable here — it means another pipeline owns the claim and our session shouldn't touch it.

  **Release site 3 — Phase 6 landing complete (DA2.4 / DA3.3-fixed signal).** Section header `### Post-landing tracking` (`skills/run-plan/SKILL.md:2418-2466`). Insert the release call within this section, IMMEDIATELY AFTER /run-plan's own `fulfilled.run-plan.$TRACKING_ID` marker write (line 2436 region — the canonical write site:
  `> "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/fulfilled.run-plan.$TRACKING_ID"`).

  **Anchor-marker clarification (DA3.3):** by the time /run-plan's Post-landing tracking executes, /land-pr has already written `fulfilled.land-pr.<id>` upstream (`skills/land-pr/SKILL.md:782`) — but /run-plan READS that marker, it does NOT write it (verified: `grep -rn "fulfilled.land-pr" skills/run-plan/` returns ONLY the line 920 comment, no write). The canonical /run-plan-internal signal that we are at terminal-merge is therefore /run-plan's OWN `fulfilled.run-plan.$TRACKING_ID` write at line 2436 (which the run-plan flow reaches only after observing the upstream `fulfilled.land-pr` AND a successful Post-landing reconciliation). This is the orchestrator-visible signal we anchor the release on.

  DO NOT anchor on `LAND_OUTCOME=merged` — that variable does NOT exist in /run-plan; it lives in `skills/commit/modes/pr.md` only (verified: `grep -rn "LAND_OUTCOME" skills/run-plan/` returns 0 hits, `grep -rn "LAND_OUTCOME" skills/commit/modes/pr.md` returns 13 hits).

  Single-slug release for the current `$PLAN_SLUG` with `--require-pipeline "$PIPELINE_ID"`; exit 12 here SHOULD invoke Failure Protocol (a pipeline-mismatch at terminal merge is unexpected and indicates a stomped claim).

  **Refresh site (NOT release) — Phase 5b §0b branch-1 cron-defer (DA2.3 — NEW SITE).** Section header `### 0b. Final-verify gate` (`skills/run-plan/SKILL.md:2123-2196`), branch 1 ("Marker exists AND fulfilled missing"). The cron-defer schedules re-entry up to 60 min from now and exits this turn. Without intervention, the heartbeat goes stale during the defer window; sweep can reap the claim. Insert a REFRESH (not release — the plan is still in-flight, just deferred) IMMEDIATELY BEFORE the `# Then exit this turn.` line at the bottom of the §0b branch-1 cron-defer code block:

      bash "$CLAUDE_PROJECT_DIR/.claude/skills/run-plan/scripts/claim-plan.sh" \
        refresh "$PLAN_SLUG" \
        --require-pipeline "$PIPELINE_ID" \
        --current-phase "Final-verify defer (attempt $ATTEMPT, backoff ${BACKOFF_MIN}m)"

  Exit 12 → STOP via Failure Protocol (claim stomped during defer is unexpected). Exit 2 (claim.json missing) → re-acquire via the W2a.3 state machine (the cron-defer is a legitimate dormant window).

  **Phase 5b §0a (plan-already-complete) DOES release; Phase 5b §0b (defer) does NOT release — it refreshes.** The Phase 5b §1-5 frontmatter-flip path does NOT release: /land-pr can take 10+ minutes in CI poll between Phase 5b's frontmatter-flip commit and Phase 6's land-complete; releasing at Phase 5b would leave the plan unclaimed during that window, allowing a second /work-on-plans dispatch to re-pick the plan and run a duplicate /land-pr. The release-at-§0a is fine because §0a is the explicit "this plan is already complete — exit clean" branch; the release-at-Phase-6 is fine because it's the terminal merge — confirmed via /land-pr's upstream `fulfilled.land-pr` marker (read by /run-plan) and anchored on /run-plan's own downstream `fulfilled.run-plan` write at line 2436.

  **Summary table (release vs refresh):**

  | Site | Section header | Action | --require-pipeline behaviour on exit 12 |
  |---|---|---|---|
  | 1 | `^## Stop` (step 3.5) | release walk over all `plan-*` claims | skip (multi-pipeline session) |
  | 2 | `### 0a. Idempotent early-exit` | release current slug | tolerate (`\|\| true`) |
  | 3 | `### Post-landing tracking` (after /run-plan's own `fulfilled.run-plan.$TRACKING_ID` write at line 2436 — /run-plan reads but does NOT write `fulfilled.land-pr`) | release current slug | Failure Protocol |
  | R | `### 0b. Final-verify gate` (branch-1 cron-defer) | refresh current slug | Failure Protocol; exit 2 → re-acquire per W2a.3 |
- [ ] **W2a.5** — Add Phase 1 preflight sweep: source `claim-fence-helpers.sh` and call `sweep_stale_plan_claims` before the live-worktree defer-all gate (symmetric to `/fix-issues` D5).
- [ ] **W2a.6** — Bump `skills/run-plan/SKILL.md metadata.version`.

### Design & Constraints

**Acquire-site error mapping (W2a.1):**

| Acquire exit | /run-plan response |
|---|---|
| 0 | Proceed to Phase 1 work-items normally |
| 10 (EEXIST) | Print decline message, exit 0 (NOT a Failure Protocol case — graceful concurrent-invocation handling per D3) |
| 11 (infra) | STOP via Failure Protocol — surface to user |
| 2 (usage) | STOP — caller bug |

**Heartbeat-site invariant (W2a.2):** the `--current-phase` argument is a free-form quoted string taken from the surrounding `### Phase N — ...` heading (e.g., `"Parse plan"`, `"Post-implementation tracking"`, `"Post-landing tracking"`); the claim file stores it verbatim. The dashboard read side parses it for the `phase N/M` chip render (Phase 3 W3.7 below).

**Cron-fire state-machine fence pattern (W2a.3):**

    set +e
    bash "$CLAIM_PLAN" refresh "$PLAN_SLUG" --require-pipeline "$PIPELINE_ID" \
      --current-phase "<section>"
    rc=$?
    set -e
    case "$rc" in
      0) : ;;
      12) echo "Claim was taken over by another pipeline; aborting." >&2; exit 1 ;;
      2)  # cron-fire dormant: re-acquire
          bash "$CLAIM_PLAN" acquire "$PLAN_SLUG" --pipeline-id "$PIPELINE_ID"
          rc2=$?
          if [ "$rc2" -eq 10 ]; then
            echo "Claim was acquired by another pipeline during the cron-fire dormant window; aborting." >&2
            exit 1
          fi
          [ "$rc2" -eq 0 ] || { echo "Re-acquire failed (rc=$rc2)" >&2; exit 1; }
          ;;
      *) echo "Refresh failed (rc=$rc)" >&2; exit 1 ;;
    esac

**Release-sites order (W2a.4):** the Phase 6 release MUST be anchored on /run-plan's own `fulfilled.run-plan.$TRACKING_ID` marker write at `skills/run-plan/SKILL.md:2436` — the canonical /run-plan-internal terminal-merge signal (the run-plan flow reaches this write only after observing /land-pr's upstream `fulfilled.land-pr.<id>` marker AND a successful Post-landing reconciliation). DO NOT anchor on `fulfilled.land-pr.$TRACKING_ID` as if /run-plan wrote it: that marker is written by /land-pr (`skills/land-pr/SKILL.md:782`); /run-plan only READS it. DO NOT anchor on `LAND_OUTCOME=merged` — that variable is internal to `skills/commit/modes/pr.md` (the `/land-pr` skill's own bookkeeping) and is not exposed back to /run-plan. Releasing the claim before the terminal merge would create a window where the plan looks unclaimed but its terminal action hasn't landed; a second `/work-on-plans` dispatch could re-pick it and double-fire `/land-pr`.

The Phase 5b §0a release is safe because §0a is the explicit "frontmatter is already `status: complete`" exit branch — the plan is already terminal-state from a prior run, and the current pipeline is a redundant no-op re-entry. The Phase 5b §0b refresh (not release) keeps the claim alive during the verify-cron defer window so sweep doesn't reap the claim mid-defer.

**PR-mode vs cherry-pick-mode release-site anchoring:** the bookkeeping commit rule (PR-mode commits happen INSIDE the worktree on the feature branch) applies to the frontmatter-flip commit; the release/refresh calls themselves run in the orchestrator's session (main checkout), since they manipulate `${MAIN_ROOT}/.zskills/claims/`. No conflict with Issue #604 (PR-mode marker propagation) because claim writes go to `.zskills/claims/`, not `.zskills/tracking/` — **and structurally, the MAIN_ROOT anchor (`git rev-parse --git-common-dir` parent) means claim writes always land in main regardless of caller CWD.** This is the immunity invariant tested by `test-plan-claim-main-root-anchor.sh` (D5/AC1.6).

- [ ] **W2a.7** — Write `tests/test-plan-claim-race-e2e.sh` (DA2.11 — explicit W-item for Phase 2a tests).
- [ ] **W2a.8** — Write `tests/test-plan-claim-heartbeat.sh`.
- [ ] **W2a.9** — Write `tests/test-plan-claim-cron-fire-state-machine.sh`.
- [ ] **W2a.10** — Write `tests/test-plan-claim-release-phase6.sh`.
- [ ] **W2a.11** — Write `tests/test-plan-claim-release-stop.sh`.
- [ ] **W2a.12** — Write `tests/test-plan-claim-release-window.sh`.
- [ ] **W2a.13** — Write `tests/test-plan-claim-release-already-complete.sh` (NEW per DA2.3 — Phase 5b §0a release).
- [ ] **W2a.14** — Write `tests/test-plan-claim-heartbeat-verify-defer.sh` (NEW per DA2.3 — Phase 5b §0b refresh during cron-defer window).

### Tests

- `tests/test-plan-claim-race-e2e.sh` — TWO parallel `/run-plan plans/sample.md` invocations on the same plan via the orchestrator-level prose path (test harness simulates the bash fence). Assert exactly one acquires + the other reports decline.
- `tests/test-plan-claim-heartbeat.sh` — multi-phase run; assert `last_heartbeat_at` is updated at each section-header-anchored heartbeat fence (W2a.2).
- `tests/test-plan-claim-cron-fire-state-machine.sh` — covers all three branches of the DA5 state machine: refresh exit 0 (proceed), exit 12 (STOP), exit 2 → re-acquire (proceed or STOP-on-rc10).
- `tests/test-plan-claim-release-phase6.sh` — Phase 6 end-to-end: assert claim is removed only after /run-plan's own `fulfilled.run-plan.$TRACKING_ID` marker is written at the Post-landing tracking site (NOT after Phase 5b commit, NOT on LAND_OUTCOME which is /land-pr-internal, NOT on `fulfilled.land-pr` since /run-plan only reads that marker).
- `tests/test-plan-claim-release-stop.sh` — `/run-plan stop` releases the claim regardless of phase progress, using the Option A walk; asserts stderr contains `Stop released N claim(s); skipped M claim(s) (pipeline mismatch).` with N and M counted accurately (DA2.9).
- `tests/test-plan-claim-release-window.sh` — explicit regression: simulate Phase 5b §1-5 frontmatter-flip commit landing + a 30s CI-poll wait; assert the claim is STILL present during the wait (proving the Phase 5b §1-5 release was correctly NOT introduced).
- `tests/test-plan-claim-release-already-complete.sh` (DA2.3 NEW) — synthesise a plan with frontmatter `status: complete` already set; invoke /run-plan; assert Phase 1 acquires the claim, Phase 5b §0a releases it BEFORE the no-op exit, and post-exit `.zskills/claims/plan-<slug>/` is gone. Also test exit 12 path: acquire as pipeline A, then invoke §0a as pipeline B; assert the release is tolerated (no Failure Protocol) and the claim remains owned by pipeline A.
- `tests/test-plan-claim-heartbeat-verify-defer.sh` (DA2.3 NEW) — synthesise a final-verify defer scenario (requires.verify-changes.final marker present, fulfilled missing); invoke /run-plan; assert `last_heartbeat_at` is updated BEFORE the cron-defer exit. Then synthesise a sweep at TTL-1 seconds; assert the refreshed claim is NOT swept.

### Acceptance Criteria (phase-level)

- **AC2a.1** — `tests/test-plan-claim-race-e2e.sh` passes: two parallel invocations, one acquires, one reports decline. **Verification:** test backgrounds two invocations, captures both exit codes and stderr, asserts the decline message contains the winning pipeline's short id.
- **AC2a.2** — Heartbeat is refreshed at every section-header-anchored W2a.2 site (NOT line-number-anchored — DA2.6). **Verification:** `tests/test-plan-claim-heartbeat.sh` reads `last_heartbeat_at` between phases AND asserts conformance by section header (W4.1).
- **AC2a.3** — Cron-fire state machine handles all three branches. **Verification:** `tests/test-plan-claim-cron-fire-state-machine.sh`.
- **AC2a.4** — All THREE release sites release + the ONE refresh site refreshes. **Verification:** `test-plan-claim-release-phase6.sh` (site 3) + `test-plan-claim-release-stop.sh` (site 1, asserts stderr count format) + `test-plan-claim-release-already-complete.sh` (site 2) + `test-plan-claim-heartbeat-verify-defer.sh` (refresh site R).
- **AC2a.5** — Phase 5b §1-5 → Phase 6 CI-poll window keeps the claim present. **Verification:** `test-plan-claim-release-window.sh`.
- **AC2a.6** — Phase 1 preflight sweep removes stale plan claims. **Verification:** create a synthetic stale claim (last-heartbeat=NOW-3h), invoke Phase 1 preflight, assert the claim dir is gone.
- **AC2a.7** — Phase 1 acquire fence precedes the mode-detection branch (so it is reachable from worktree / PR / cherry-pick / direct / delegate paths — A11). **Verification:** `test-plan-claim-conformance.sh` asserts the acquire-fence line number is less than every `### Execution: ...` line number in `skills/run-plan/SKILL.md`.

### Dependencies

Phase 1 (claim-plan.sh + hook + resolver must exist).

---

## Phase 2b — /work-on-plans selection-aware filter

### Goal

Wire the selection-aware filter into `/work-on-plans` Step 4 — the actual picker that reads `plans.ready` and dispatches `/run-plan`. This is the user-steering anchor: skip in-flight plans BEFORE any `/run-plan` dispatch.

### Work Items

- [ ] **W2b.1** — Create `skills/work-on-plans/scripts/filter-in-flight-plan-claims.sh`. Input: stdin `READY_LINES` (TSV, one per line); output: stdout filtered TSV; stderr: `Skipped N plan(s) currently in-flight: <slugs>` if any were filtered. Reads `.zskills/claims/plan-*/claim.json` via Python (no jq); builds an in-flight slug set; drops any input row whose first TSV column matches. Sources `zskills-resolve-config.sh` for `MAIN_ROOT` resolution.
- [ ] **W2b.2** — In `skills/work-on-plans/SKILL.md` Step 4 (locate by section header `## Step 4 — Execute mode setup`), insert TWO fences between the `mapfile -t READY_LINES` line and the `TOTAL_READY=` line:
  1. **Pre-filter sweep (R2.6 — NEW):** call `bash "$CLAUDE_PROJECT_DIR/.claude/skills/run-plan/scripts/claim-plan.sh" sweep` to reap stale plan claims before the filter runs. This prevents a crashed-pipeline stale claim from permanently blocking a slug.
  2. **Filter fence:** pipe `READY_LINES` through `filter-in-flight-plan-claims.sh`, rebuild `READY_LINES` from the filtered output, then proceed with the existing `TOTAL_READY` computation.

  Both fences source `zskills-resolve-config.sh` per fence-local discipline. The sweep-then-filter order (rather than embedding sweep in the filter) keeps the filter script single-purpose and matches /fix-issues' Phase 1 sweep pattern (sweep is a separate step, not bundled with selection).
- [ ] **W2b.3** — Bump `skills/work-on-plans/SKILL.md metadata.version`.
- [ ] **W2b.4** — Write `tests/test-plan-claim-selection-filter.sh` (DA2.11 explicit W-item).
- [ ] **W2b.5** — Write `tests/test-work-on-plans-parallel-selection.sh` (DA2.11 + DA2.7 — STEADY-STATE race only, NOT structural elimination).
- [ ] **W2b.6** — Write `tests/test-plan-claim-filter-edge-cases.sh`.
- [ ] **W2b.7** — Write `tests/test-work-on-plans-pre-filter-sweep.sh` (R2.6 NEW — assert Step 4 sweep reaps stale claims before filter runs).

### Design & Constraints

**`filter-in-flight-plan-claims.sh` interface:**

    # Input: TSV rows on stdin (first column = slug)
    # Output: TSV rows on stdout (filtered)
    # Stderr: "Skipped N plan(s) currently in-flight: <slug1> <slug2> ..." if N>0
    # Exit: 0 always (the filter never fails the dispatch; an unreadable claims dir
    #       falls through as empty in-flight set, preserving the legacy behavior)

Reading claims is best-effort: malformed JSON, missing claim.json, non-plan-* dirs are skipped silently (the dashboard collector does the same — see Phase 3 W3.1). Exception: if the claims-root is unreadable due to permission errors (not just non-existence), emit a single stderr line and proceed with empty in-flight set.

**SKILL.md fence pattern (W2b.2 — illustrative; references the script):**

    # SELECTION FILTER (D4) — drop in-flight plan claims before dispatch.
    # See plans/plans-claim-chip-parity.md D4 + W2b.1.
    . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
    FILTER="$CLAUDE_PROJECT_DIR/.claude/skills/work-on-plans/scripts/filter-in-flight-plan-claims.sh"
    if [ -x "$FILTER" ]; then
      FILTERED=$(printf '%s\n' "${READY_LINES[@]}" | bash "$FILTER")
      mapfile -t READY_LINES <<< "$FILTERED"
    fi

(Defensive `[ -x ]` check so older installations without the script don't break.)

### Tests

- `tests/test-plan-claim-selection-filter.sh` — **the user-steering acceptance gate.** Synthetic claim + `plans.ready=[foo, bar]` candidate queue → asserts `foo` filtered, `bar` picked, stderr contains the Skipped-N line. Test invokes the actual `filter-in-flight-plan-claims.sh` script (NOT a re-implementation of the logic inside the test). **Test-fixture synthesis (DA2.12):** the test sources `skills/run-plan/scripts/claim-plan.sh` to write the synthetic claim (preferred — exercises the real schema), OR writes the raw JSON directly per the D5 schema; both are acceptable.
- `tests/test-work-on-plans-parallel-selection.sh` — STEADY-STATE filter test. Pre-creates a `.zskills/claims/plan-foo/claim.json` via `claim-plan.sh acquire` from a synthetic pipeline ID, THEN runs `/work-on-plans` Step 4 against `plans.ready=[foo]`; asserts the filter drops `foo` and dispatch list is empty. **This test does NOT assert structural closure of the fresh-start race (per D4 / Overview / DA2.7 honest framing):** two simultaneous /work-on-plans invocations against an EMPTY claims-dir CAN both pass the filter; that residual race is bounded by /run-plan Phase 1's atomic-mkdir acquire (one returns exit 10 acquire-loss). The test asserts the steady-state closure only — and the test name + comment document the scope honestly.
- `tests/test-plan-claim-filter-edge-cases.sh` — malformed JSON, missing claim.json, non-plan-* dir, empty claims root, unreadable claims root.
- `tests/test-work-on-plans-pre-filter-sweep.sh` (R2.6) — create a stale claim (`last_heartbeat_at` = NOW - 2×TTL), populate `plans.ready=[foo]`, invoke Step 4 sweep-then-filter; assert the stale claim dir is gone after the sweep, and `foo` is preserved in the filtered dispatch list (NOT dropped — the stale claim has been reaped).

### Acceptance Criteria (phase-level)

- **AC2b.1** — `tests/test-plan-claim-selection-filter.sh` passes (the user-steering acceptance gate).
- **AC2b.2** — `tests/test-work-on-plans-parallel-selection.sh` passes: STEADY-STATE filter is the gate (fresh-start race is acquire-bounded, not structurally eliminated — DA2.7).
- **AC2b.3** — Filter edge cases handled gracefully (no failure on malformed inputs).
- **AC2b.4** — `skills/work-on-plans/SKILL.md metadata.version` bumped per layer-4 enforcement.
- **AC2b.5** — Step 4 invokes `claim-plan.sh sweep` BEFORE the filter (R2.6). **Verification:** `test-work-on-plans-pre-filter-sweep.sh` + `test-plan-claim-conformance.sh` asserts the sweep fence appears before the filter fence in Step 4.

### Dependencies

Phase 1 (claim files on disk, claim-plan.sh available for tests to synthesise claims).

---

## Phase 3 — Dashboard collect.py + render-side wiring

### Goal

Make the dashboard READ plan claims and RENDER an in-flight chip on plan cards, with full symmetry to the issue-side chip including the aria-disabled / move-all-skip guards.

### Work Items

- [ ] **W3.1** — In `skills/zskills-dashboard/scripts/zskills_monitor/collect.py`, add `_read_plan_claims()` mirroring `_read_claims()` (lines 1677-1745), keyed by slug (string), tolerant of malformed JSON and missing `claim.json` (surfaces a null-metadata claim per the issue-side D2.6 lesson).
- [ ] **W3.2** — In `_annotate_plans_queue` (~line 1345), attach `plan["claim"] = {pipeline_id, started_at, last_heartbeat_at, current_phase, age_seconds, pipeline_short}` when a matching claim exists. Use explicit field allow-list (NOT `**claim_dict`), symmetric to the issue side.
- [ ] **W3.3** — In `static/app.js`, extend `fingerprintPlans` (~line 459) to include `[p.claim?.pipeline_id, p.claim?.last_heartbeat_at]` per plan row. **last_heartbeat_at**, not started_at, because heartbeat changes every phase and the chip should re-render to reflect that.
- [ ] **W3.4** — In `static/app.js` `buildPlanCard` (~lines 561-657), add a claim-chip block mirroring `buildIssueCard` lines 951-976 with the plan-context chip text (`in-flight · <pidShort> · phase N/M · <ageStr>`). On claim presence: `setAttribute("aria-disabled", "true")` + `removeAttribute("draggable")`.
- [ ] **W3.5** — In `static/app.js` `handleAction` (~lines 2020-2032), add a symmetric arm for `plan-up`, `plan-down`, `plan-left`, `plan-right`, `plan-remove` that refuses the action when the closest `li.card[aria-disabled="true"][data-kind="plan"]` is matched (toast: "Plan is in-flight; release the claim or wait for completion.").
- [ ] **W3.6** — Verify `moveAllInColumn` (PR #617, ~line 1939) already respects `aria-disabled` per-card; if not, ensure plan cards with the attribute are skipped (research says it's already generic — confirm).
- [ ] **W3.7** — Add `current_phase` rendering math: `buildPlanCard` already has `plan.phases_done` and `plan.phase_count`; compute the chip's `phase N/M` from `claim.current_phase` (parsed) and `plan.phase_count`. Falls back to `phase ?/M` if `current_phase` is unparseable. Note: `ageStr` may go stale between heartbeats (matches issue-chip behavior; known limitation per DA11; not a regression).
- [ ] **W3.8** — Bump `skills/zskills-dashboard/SKILL.md metadata.version`.
- [ ] **W3.9** — Write `tests/test-plan-claim-collector.sh` (DA2.11 explicit W-item).
- [ ] **W3.10** — Write `tests/test-plan-claim-collector.py`.
- [ ] **W3.11** — Write `tests/test-plan-claim-render-dom.sh`.
- [ ] **W3.12** — Write `tests/test-plan-claim-handleaction-guard.sh`.
- [ ] **W3.13** — Write `tests/test-plan-claim-moveall-skip.sh`.
- [ ] **W3.14** — Write `tests/test-plan-claim-fingerprint.sh`.

### Design & Constraints

**`_read_plan_claims()` signature (mirror `_read_claims`):**

    def _read_plan_claims(main_root: pathlib.Path) -> Dict[str, Dict[str, Any]]:
        """Read run-plan claim files under `${main_root}/.zskills/claims/plan-*/`.

        Returns `{slug: claim_dict}` keyed by string slug. Tolerant of
        malformed JSON (single stderr line, skip) and of claim dirs missing
        `claim.json` (surfaces null-metadata so chip renders).
        """

**`plan["claim"]` field allow-list:**

    plan["claim"] = {
        "pipeline_id":       c.get("pipeline_id"),
        "started_at":        c.get("started_at"),
        "last_heartbeat_at": c.get("last_heartbeat_at"),
        "current_phase":     c.get("current_phase"),
        "age_seconds":       <computed>,
        "pipeline_short":    <computed: last 6 chars of pipeline_id hash>,
    }

NO `worktree_path`, NO `host_pid` — same scope discipline as issue side.

**Chip text:**

    "in-flight · " + pidShort + " · " + phaseStr + " · " + ageStr

where `phaseStr` = `"phase " + curN + "/" + total` (e.g., `phase 3/5`), parsed from `claim.current_phase` ("Phase 3" → `3`; section names like "Parse plan" or "Post-landing tracking" → fallback `"phase ?/M"`), falling back to `"phase ?/" + total` if unparseable.

**Fingerprint discipline:** include `last_heartbeat_at`, not `started_at`. Rationale: chip text contains `ageStr` derived from heartbeat; if fingerprint only tracks `started_at`, the chip's age text goes stale because applySnapshot skips renderPlans between phase heartbeats.

### Tests

- `tests/test-plan-claim-collector.sh` — bash + python wrappers: synthesize `.zskills/claims/plan-foo/claim.json` + `monitor-state.json` with `plans.ready=[foo]`; invoke `collect.py`; assert GET response `plans[0].claim` contains all 6 allow-list fields with correct values.
- `tests/test-plan-claim-collector.py` — python-direct unit test for `_read_plan_claims()` edge cases (malformed JSON, missing claim.json, non-plan-* dir-name, age_seconds math).
- `tests/test-plan-claim-render-dom.sh` — playwright-cli: render the page with a synthetic claim, assert `<span class="claim-chip claim-chip--in-flight">` present on the plan card, text matches the format spec, card has `aria-disabled="true"`, card has no `draggable` attribute.
- `tests/test-plan-claim-handleaction-guard.sh` — playwright-cli: click `plan-up` / `plan-remove` on a claimed plan card; assert toast appears, queue is unchanged.
- `tests/test-plan-claim-moveall-skip.sh` — synthetic queue with 3 plans, one claimed; invoke move-all-right column header; assert the claimed plan stays in place.
- `tests/test-plan-claim-fingerprint.sh` — unit test on `fingerprintPlans`: with claim absent vs present vs heartbeat-updated, fingerprints all differ.

### Acceptance Criteria (phase-level)

- **AC3.1** — Dashboard GET response carries `plan["claim"]` with the 6-field allow-list when a claim exists. **Verification:** `tests/test-plan-claim-collector.{sh,py}`.
- **AC3.2** — Plan card renders the in-flight chip with the format-spec text. **Verification:** `tests/test-plan-claim-render-dom.sh`.
- **AC3.3** — Claimed plan card has `aria-disabled=true` and no `draggable` attribute. **Verification:** same DOM test.
- **AC3.4** — `plan-up/down/left/right/plan-remove` actions refuse on claimed cards with toast. **Verification:** `tests/test-plan-claim-handleaction-guard.sh`.
- **AC3.5** — Move-all-in-column skips claimed plan cards. **Verification:** `tests/test-plan-claim-moveall-skip.sh`.
- **AC3.6** — Fingerprint changes between heartbeats; chip age re-renders. **Verification:** `tests/test-plan-claim-fingerprint.sh`.

### Dependencies

Phase 1 (claim files on disk) and Phase 2a (heartbeat keeps `last_heartbeat_at` current).

---

## Phase 4 — Conformance tests + integration + SKILL.md prose

### Goal

Lock the discipline with conformance grep-asserts; update `/run-plan` and `/work-on-plans` SKILL.md prose to document the claim mechanism; verify adjacency with Issue #604 (PR-mode marker propagation) and PR #617 (move-all); file the follow-up issue pointing at `/fix-issues` Phase 2 picker (NOT /work-on-plans).

### Work Items

- [ ] **W4.1** — Write `tests/test-plan-claim-conformance.sh`. **Section-header-anchored grep-asserts (DA2.6 + DA2.10 location-pinned, with section-scoped windows per DA3.1):**
  - `skills/run-plan/SKILL.md` contains the acquire call BEFORE the first `### Execution: ` mode line (regex anchor on `claim-plan.sh.*acquire`; A11 — must reach worktree/PR/cherry-pick/direct/delegate paths).
  - **Section-scoped refresh windows (DA3.1 — per-section bound, NOT a flat distance):** for each section header below, locate the header by literal grep, then assert exactly one `claim-plan.sh.*refresh` call appears between that header and the NEXT header at the same-or-shallower depth (the next `^### ` or `^## ` line). A flat 30-line distance is mathematically impossible here — the Parse-plan section spans 138 lines to its first PIPELINE_ID re-emit (lines 760 → 898 in current /run-plan), and §0b's `# Then exit this turn.` anchor is 95 lines after its header (2101 → 2196). The section-scoped window is line-number-resistant AND mathematically achievable. Sections to assert:
    - `### Parse plan` (next header bounds: `### Architecture detection`-ish or the next `^### `)
    - `### Post-implementation tracking`
    - `### Post-verification tracking`
    - `### 5. Marker ordering and failure handling`
    - `### Post-report tracking`
    - `### 0b. Final-verify gate` (branch-1 cron-defer site — the refresh site R)
  - Implementation: `awk '/^### Parse plan$/{p=1; next} p && /^(###|## )/{p=0} p' skills/run-plan/SKILL.md | grep -c 'claim-plan\.sh.*refresh'` must return 1 for each enumerated section.
  - `skills/run-plan/SKILL.md` contains release calls at (DA2.10 location-pinned; section-scoped per DA3.1):
    - Exactly one `claim-plan\.sh.*release` between `^## Stop` and the next `^## ` (release walk; step 3.5 anchor).
    - Exactly one `claim-plan\.sh.*release` between `^### 0a. Idempotent early-exit` and the next `^### ` or `^## ` (single-slug release before no-op exit).
    - Exactly one `claim-plan\.sh.*release` between `^### Post-landing tracking` and the next `^### ` or `^## ` (single-slug release after the `fulfilled.run-plan.$TRACKING_ID` marker write — see W2a.4 site 3 for the actual anchor; the upstream `fulfilled.land-pr` write happens in /land-pr, not /run-plan).
  - `skills/run-plan/SKILL.md` does NOT contain a release call within Phase 5b §1-5 (regex: between `^### 1\. Audit phase compliance` and `^### Post-report tracking`-or-`^## Phase 5c`): explicit regression assertion for the unclaimed-during-CI-poll window fix.
  - `skills/run-plan/SKILL.md` does NOT contain the string `LAND_OUTCOME` anywhere (DA2.4 — the Phase 6 release MUST anchor on /run-plan's own `fulfilled.run-plan.$TRACKING_ID` marker write at line 2436, NOT on `LAND_OUTCOME` which is /land-pr-internal — see W2a.4 site 3 for the full marker rationale per DA3.3).
  - `skills/work-on-plans/SKILL.md` Step 4 contains the pre-filter sweep fence (regex anchor on `claim-plan.sh.*sweep`) BEFORE the selection filter fence (regex anchor on `filter-in-flight-plan-claims.sh`) — line-number ordering check.
  - `.claude/settings.json` registers `block-run-plan-unclaimed.sh` as a PreToolUse Bash hook.
  - The W4.1 `release`-anchored asserts use the literal substring `claim-plan.sh release`; the refresh asserts use the literal `claim-plan.sh refresh` (so adjacent refresh calls in the post-phase sections don't trip the release-count regex — R2.4 clarified).
- [ ] **W4.2** — Add a section to `skills/run-plan/SKILL.md` documenting the claim mechanism: storage, lifecycle, acquire-or-decline semantics, heartbeat cadence, the cron-fire state machine, release sites, and the PreToolUse backstop. Add a parallel section to `skills/work-on-plans/SKILL.md` documenting the selection-aware filter and pointing at `filter-in-flight-plan-claims.sh`. Reference this plan file for full design.
- [ ] **W4.3** — Verify Issue #604 (run-plan PR-mode marker propagation) does NOT bite the release path: release writes to `.zskills/claims/`, NOT `.zskills/tracking/`, and MAIN_ROOT anchors via `git rev-parse --git-common-dir` parent (so worktree-CWD callers still write to main). Add a regression assertion in `test-plan-claim-conformance.sh` that grep does not find a release-path write under `.zskills/tracking/`, AND the W1.10 `test-plan-claim-main-root-anchor.sh` runs as part of the suite.
- [ ] **W4.4** — File a follow-up GitHub issue titled `/fix-issues Phase 2 picker also needs selection-aware filter (per /work-on-plans + /run-plan claim chip parity)`. Body content: "Two parallel `/fix-issues` agents both selected the same issue despite the per-issue claim system. Atomic acquire at `create-worktree` is too late — both pipelines have already burned setup cost. The lesson has been ported to `/work-on-plans` via the D4 selection-aware filter at `skills/work-on-plans/SKILL.md` Step 4 (see `plans/plans-claim-chip-parity.md` Phase 2b). `/fix-issues` has its own Phase 2 candidate-selection code path (`skills/fix-issues/SKILL.md` ~lines 686-720 — independent of /work-on-plans) which needs the same fix: read `.zskills/claims/issue-*/claim.json` BEFORE building the working list of needs-plan issues, drop any matching issue numbers. Mirror of `filter-in-flight-plan-claims.sh` for issue numbers." Include the verbatim user quote from research summary's "User steering" section. This is the "surface, don't patch" follow-up per CLAUDE.md.
- [ ] **W4.5** — Run `bash tests/run-all.sh` end-to-end; gate on `Overall: N/M passed, 0 failed`.
- [ ] **W4.6** — Bump `skills/run-plan/SKILL.md metadata.version` and `skills/zskills-dashboard/SKILL.md metadata.version` and `skills/work-on-plans/SKILL.md metadata.version` if any were further touched in this phase.

### Design & Constraints

**Conformance test grep anchors (W4.1) — section-header-anchored regexes (DA2.6 + DA2.10):**

| Anchor | Regex | File / location-pin |
|---|---|---|
| Acquire | `claim-plan\.sh"? acquire` | `skills/run-plan/SKILL.md`, must appear BEFORE the first `^### Execution: ` line (A11) |
| Heartbeat (refresh) | `claim-plan\.sh"? refresh` | `skills/run-plan/SKILL.md`, exactly 1 match within each of the 6 section-scoped windows enumerated in W4.1 (awk-bracketed by next `^### `/`^## ` header — DA3.1) |
| Release | `claim-plan\.sh"? release` | `skills/run-plan/SKILL.md`, exactly 3 matches: one each within section-scoped windows after `^## Stop`, `^### 0a. Idempotent early-exit`, and `^### Post-landing tracking` (DA3.1) |
| No 5b §1-5 release | NEGATIVE: no `claim-plan\.sh.*release` between `^### 1\. Audit phase compliance` and (`^### Post-report tracking` OR `^## Phase 5c`) | `skills/run-plan/SKILL.md` |
| No LAND_OUTCOME | NEGATIVE: zero hits for `LAND_OUTCOME` (DA2.4 — that var is /land-pr-internal) | `skills/run-plan/SKILL.md` |
| Pre-filter sweep | `claim-plan\.sh"? sweep` precedes filter fence by line number | `skills/work-on-plans/SKILL.md` Step 4 |
| Selection filter | `filter-in-flight-plan-claims\.sh` | `skills/work-on-plans/SKILL.md` Step 4 |
| Hook registration | `block-run-plan-unclaimed\.sh` | `.claude/settings.json` |

**Issue #604 adjacency check (W4.3):** grep `skills/run-plan/SKILL.md` for `.zskills/claims/plan-` AND for `.zskills/tracking/` in proximity to any claim-plan.sh call site. Assert: claim writes go to `.zskills/claims/`, tracking writes go to `.zskills/tracking/`, and no skill-prose line mixes the two paths.

**Follow-up issue body (W4.4):** must include the user's verbatim quote and cite the structural fix landed in this plan as evidence the pattern transfers, AND point specifically at `/fix-issues` Phase 2 (NOT /work-on-plans) since `/fix-issues` has its own picker.

### Tests

- `tests/test-plan-claim-conformance.sh` — as designed above.
- `bash tests/run-all.sh` — full suite gate.

### Acceptance Criteria (phase-level)

- **AC4.1** — `test-plan-claim-conformance.sh` passes including: (a) acquire-before-mode-detection positional check (A11), (b) section-header-anchored refresh asserts (DA2.6), (c) THREE release sites + ONE refresh site location-pinned within 50 lines of named section headers (DA2.10), (d) NEGATIVE assertion no release call within Phase 5b §1-5, (e) NEGATIVE assertion no `LAND_OUTCOME` literal anywhere in `skills/run-plan/SKILL.md` (DA2.4), (f) sweep-before-filter ordering check in `/work-on-plans` Step 4 (R2.6). **Verification:** local + CI run.
- **AC4.2** — `bash tests/run-all.sh` ends with `Overall: N/M passed, 0 failed`. **Verification:** `cat "$TEST_OUT/.test-results.txt"`.
- **AC4.3** — Follow-up issue is filed and linked, body cites /fix-issues Phase 2 picker (not /work-on-plans). **Verification:** `gh issue view <N>` shows the body with the user's quote and the cross-reference to this plan.

### Dependencies

Phase 1, Phase 2a, Phase 2b, Phase 3 (all wiring must be in place before conformance grep can pass).

---

## Phase 5 — Optional cleanup + verification

### Goal

Final integration check; confirm all four layers of skill-version enforcement pass; land via `/run-plan auto pr --auto` (the plan-execution side will dispatch `/land-pr` per PR-mode discipline). Labeled "optional" because Phase 4's run-all.sh gate already covers correctness; Phase 5 adds a manual two-shell e2e and theme spot-check that are nice-to-have rather than strictly required.

### Work Items

- [ ] **W5.1** — Confirm all four layers of skill-version enforcement pass for every touched skill subtree: `skills/run-plan/`, `skills/work-on-plans/`, `skills/zskills-dashboard/`, and any helper script directories. Layers: warn-config-drift (Edit-time), `/commit` step 2.5 (commit-time), `test-skill-conformance.sh` (CI), `block-stale-skill-version.sh` (PreToolUse).
- [ ] **W5.2** — Run a manual e2e: dispatch two `/run-plan plans/<some-ready-plan>.md` invocations concurrently from two shells; assert the second reports decline; assert the dashboard chip appears on the plan card mid-run; assert the chip disappears after Phase 6 land-complete (NOT after Phase 5b — that's the DA6 fix that this manual check also exercises).
- [ ] **W5.3** — Verify the dashboard claim chip renders correctly under both light and dark themes (the `.claim-chip--in-flight` CSS class should be theme-agnostic since it's reused from the issue side).
- [ ] **W5.4** — Run `bash tests/run-all.sh` one final time as a release gate.
- [ ] **W5.5** — If any divergence from the locked D1-D7 was needed during implementation, document it in the plan's `## Drift Log` section (appended via `/refine-plan` if necessary).

### Tests

No new tests in this phase — all tests were written during Phases 1-4 per the PR #607 lesson.

### Acceptance Criteria (phase-level)

- **AC5.1** — All four layers of skill-version enforcement pass. **Verification:** `bash tests/run-all.sh` includes `test-skill-conformance.sh`; no warn-config-drift warnings on any touched file.
- **AC5.2** — Manual e2e passes: two-shell concurrent dispatch, chip render-and-clear (clear at Phase 6, NOT 5b), declination behaviour. **Verification:** orchestrator's session report.
- **AC5.3** — `bash tests/run-all.sh` final run: `Overall: N/M passed, 0 failed`. **Verification:** test-results file.

### Dependencies

Phase 1, 2a, 2b, 3, 4 — this phase is the integration gate.

---

## Constraints (verbatim into plan)

- **Skill versioning:** bump `metadata.version` on EVERY skill subtree edit (4-layer enforcement: warn-config-drift Edit-time, `/commit` step 2.5, `test-skill-conformance.sh` CI, `block-stale-skill-version.sh` PreToolUse).
- **Tracking markers vs claims:** NEVER mix `.zskills/claims/` and `.zskills/tracking/` — different hook semantics. Plan claims live under `.zskills/claims/plan-<slug>/`.
- **No `2>/dev/null` on fallible operations.** Errors should be visible. No inline `rm -r .zskills/...` (`hooks/block-unsafe-project.sh.template` fences this at line 531). Per-file `rm` + `rmdir` only.
- **Use `&& echo done`, not `; echo done`** after fallible commands so failure is visible.
- **Python is required.** Use `${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}`. No jq. Python stdlib `json` is the JSON parser.
- **Source `zskills-resolve-config.sh`** in every bash fence that references resolved-config variables (e.g., `$BRANCH_PREFIX`, `$ZSKILLS_PYTHON`, TTL env vars).
- **Source `zskills-paths.sh`** for `$ZSKILLS_PLANS_DIR` resolution; never hardcode `plans/` in scripts.
- **PR mode is forced** by `main_protected: true` — plan execution branches via `/land-pr`, NEVER direct push to main.
- **Surface bugs, don't patch.** If implementation reveals a `/fix-issues` parallel-selection failure beyond what's structurally addressed by the D4 selection-aware filter for `/work-on-plans`, file a follow-up issue (W4.4) rather than silently fixing `/fix-issues` in this plan.
- **No follow-up TTL tests.** PR #607's TTL test-coverage gap is the cautionary tale: write TTL + resolver tests DURING Phase 1 (W1.7), not after merge.
- **Pre-existing-failure discipline.** If `bash tests/run-all.sh` shows a failure in code this plan didn't touch, verify with `git log` that the test/source predates the plan's commits; document via skip-with-issue, never weaken the test.

## Execution: worktree

This plan executes in the standard PR-mode worktree (`/tmp/zskills-pr-plans-claim-chip-parity`, branch `feat/plans-claim-chip-parity` — derived from `execution.branch_prefix` in `.claude/zskills-config.json`). Cherry-pick mode is structurally available but PR mode is forced by `main_protected: true`.

## Plan Quality

**Drafting process:** /draft-plan with 3 rounds of adversarial review (default budget)
**Convergence:** Converged at round 3
**Remaining concerns:** None

### Round History

| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1     | 12 (3 Block, 2 Major, 5 Minor, 2 Affirm)  | 13 (3 Block, 5 Major, 5 Minor)   | 25/25 (23 Fixed, 2 Affirm) |
| 2     | 12 (2 Major, 3 Minor, 7 Affirm)           | 12 (2 Block, 5 Major, 5 Minor)   | 18/18 (all Fixed, 7 Affirm-no-op)  |
| 3     | 4 (2 Major, 2 Minor)                      | 3 (1 Block, 2 Major) + 3 Minor   | 7/7 Fixed |

### User steering mid-draft (round 1)

User reported real-world failure in /fix-issues: two parallel agents both selected the same issue despite the claim system. This shaped D4 (orchestrator-level selection-aware filter) and the honest scope re-framing in round 2 / 3 (filter closes steady-state race; acquire-time atomic mkdir is the final defense for the fresh-start race).
