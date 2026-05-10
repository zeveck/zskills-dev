# Pre-RESTRUCTURE baseline — 2026-04-19T04:48:23-04:00

Purpose: freeze the current state of the four skills targeted by the
RESTRUCTURE plan (run-plan, commit, do, fix-issues). After the
restructure extracts modes/*.md and references/*.md, the post-state can
be diffed against this snapshot to verify byte-preservation and detect
drift. This is the static half of safety-net task C; the dynamic half
(running canary plans) requires user-driven PR creation and is deferred.

## Git state
```
HEAD: 64ee65b28260caa00be260ffd8b26a936f993065
HEAD subject: refactor(run-plan): delegate cron math to compute-cron-fire.sh
prod/main: 14dea81da487b2904ea7d69a27295f1869206cdf
dev/main:  14dea81da487b2904ea7d69a27295f1869206cdf
tag 2026.04.0 → 14dea81da487b2904ea7d69a27295f1869206cdf
```

## Test suite baseline
```
[1mTests: test-hooks.sh[0m
[1mTests: test-port.sh[0m
[1mTests: test-apply-preset.sh[0m
[1mTests: test-compute-cron-fire.sh[0m
[1mTests: test-skill-conformance.sh[0m
[1mTests: test-briefing-parity.sh[0m
[1mTests: test-skill-invariants.sh[0m
[1mTests: test-phase-5b-gate.sh[0m
[1mTests: test-scope-halt.sh[0m
[1mTests: test-canary-failures.sh[0m
[1mTests: test-tracking-integration.sh[0m
[32mOverall: 531/531 passed, 0 failed[0m
```

## Skill file sizes and hashes

| Skill | Files | Total lines | SKILL.md hash |
|---|---|---|---|
| /run-plan | 1 | 2589 | 5a9d13ea59ec |
| /commit | 1 | 417 | 97787dd461f5 |
| /do | 1 | 669 | cfe8d9923144 |
| /fix-issues | 1 | 1460 | 4413714ba0ec |
| /verify-changes | 1 | 623 | 6a6e71d6247b |

## Current structural landmarks (H2 + H3 headers) per skill

### /run-plan
```
## Arguments
## Status (if `status` is present)
## Now (standalone — no plan-file provided)
## Next (if `next` is present)
## Stop (if `stop` is present)
## Phase 0 — Schedule (if `every` is present)
## Phase 1 — Parse Plan & Extract Verbatim Phase Text
### Preflight checks
### Parse plan
### `finish` mode: overall verification after all phases
## Phase 2 — Implement
### Execution mode detection
### Delegate mode
### Direct mode
### Worktree mode (default)
### PR mode (Phase 2)
### Post-implementation tracking
### Pre-verification tracking
## Phase 3 — Verify (separate agent)
### Dispatch protocol
### Delegate mode verification
### Worktree mode verification
### Post-verification tracking
## Phase 4 — Update Progress Tracking
## Phase 5 — Write Report
## Phase — 4b Translational Mechanical Domain [UNFINALIZED]
### Work Items
### Verification
### User Sign-off
### Post-report tracking
## Phase 5b — Plan Completion
### 0a. Idempotent early-exit
### 0b. Final-verify gate
### 1. Audit phase compliance
### 2. Close linked issue (if any)
### 3. Update plan frontmatter
### 4. Update SPRINT_REPORT.md
### 5. Remind about stale tracking markers
## Phase 5c — Chunked finish auto transition (CRITICAL for finish auto mode)
### Why chunked execution
### Idempotent re-entry (every cron-fired turn does this first)
### When this turn schedules the next cron
### PR-mode branching for next-phase cron
### User Verify items in chunked mode
### How to schedule the next cron
### Cron-scheduling rule (avoid confusion)
### Single-phase mode (no chunking)
## Phase 6 — Land
### Direct mode landing
### Delegate mode landing
### Worktree mode landing
### Pre-landing checklist (worktree mode only)
### PR mode landing
### Post-landing tracking
### Post-run invariants check (mandatory — mechanical gate)
## Failure Protocol
### 1. Kill the cron FIRST
### 2. Restore the working tree
### 3. Write the failure to the plan report
## Run Failed — YYYY-MM-DD HH:MM
### 4. Alert the user
### When to trigger
## Key Rules
## Edge Cases
```

### /commit
```
## Phase 1 — Inventory
## Phase 2 — Classify Changes
### If a scope hint was provided
### If no scope hint was provided
### Always
## Phase 3 — Trace Dependencies
## Phase 4 — Stage & Review
## Phase 5 — Commit
## Phase 6 — Push (if `push` argument)
## Phase 6 (PR subcommand) — PR Mode (if `pr` is the first token)
## Phase 7 — Land (if `land` argument)
## Key Rules
```

### /do
```
## When to Use `/do`
## Arguments
## Meta-Commands: stop / next / now
### Cron Matching (for targeted commands)
### Now
### Next
### Stop
## Phase 0 — Schedule (if `every` is present)
## Phase 1 — Understand & Research
## Phase 1.5 — Argument Parsing (always before Phase 1 research)
## Phase 2 — Execute
### Path A: PR mode (`pr` flag)
### Path B: Worktree mode (`worktree` flag, no `pr`)
### Path C: Direct (default, no `pr`, no `worktree`)
## Phase 3 — Verify
### Content-only changes (md, jpg, png, presentations)
### Code changes (js, css, html)
### Mixed changes
## Phase 4 — Push (if `push` flag present, Path C/B only)
## Phase 5 — Report
## Error Handling
## Key Rules
```

### /fix-issues
```
## Arguments
## Now (standalone — no N provided)
## Next (if `next` is present)
## Stop (if `stop` is present)
## Sync (if `sync` is present)
### Step 1 — Fetch & update trackers
### Step 2 — Research & verify
### Step 3 — Present findings
### Step 4 — Close approved issues on GitHub
### Step 5 — Commit & report
## Plan (if `plan` is present)
## Phase 0 — Schedule (if `every` is present)
## Phase 1 — Preflight & Sync
### Sprint tracking sentinel
### Preflight checks (before doing anything else)
### Sync
## Phase 1b — Read Full Issue Bodies & Plan Context
### Post-preflight tracking
## Phase 2 — Prioritize
### Triage: vague, complex, or interrelated issues
### Group by dependency and file overlap
### Present the list
### If no actionable issues found
### Post-prioritize tracking
## Phase 3 — Execute (agent teams in worktrees)
### PR mode (Phase 3)
### Post-execute tracking
## Phase 4 — Review
### Pre-verification tracking
### Dispatch protocol
### Post-verify tracking
## Phase 5 — Write Sprint Report (BEFORE landing)
## Sprint — YYYY-MM-DD HH:MM [UNFINALIZED]
### Fixed
### Skipped — Too Vague (need repro steps or clearer spec)
### Skipped — Too Complex (need /run-plan)
### Skipped — Cherry-Pick Conflict (will retry next sprint)
### Not Fixed (agent attempted but failed)
### Post-report tracking
## Phase 6 — Land
### PR mode landing
## Changes
## Test plan
### Post-land tracking
## Failure Protocol
### 1. Kill the cron FIRST
### 2. Restore the working tree
### 3. Write the failure to SPRINT_REPORT.md
## Sprint Failed — YYYY-MM-DD HH:MM
### 4. Alert the user
### When to trigger
## Key Rules
```

## Scripts shipped (current)

```
apply-preset.sh
briefing.cjs
briefing.py
clear-tracking.sh
compute-cron-fire.sh
land-phase.sh
port.sh
post-run-invariants.sh
sanitize-pipeline-id.sh
statusline.sh
test-all.sh
worktree-add-safe.sh
write-landed.sh
```

## Canary plans in repo (awaiting user-driven execution)

Running these autonomously was deferred — they dispatch sub-agent
pipelines, create PRs, and take hours of wall time. The RESTRUCTURE
plan's Phase 5 runs them post-restructure; to get a true before/after
diff, the user can run a subset BEFORE starting RESTRUCTURE and
capture the output.

```
CANARY10_PR_MODE.md
CANARY11_SCOPE_VIOLATION.md
CANARY11_TEST_PLAN.md
CANARY1_HAPPY.md
CANARY2_NOAUTO.md
CANARY3_FIXCYCLE.md
CANARY4_EXHAUST.md
CANARY5_AUTONOMOUS.md
CANARY6_MULTI_PR.md
CANARY7_CHUNKED_FINISH.md
CANARY8_PARALLEL.md
CANARY9_FINAL_VERIFY.md
CANARY_FAILURE_INJECTION.md
CI_FIX_CYCLE_CANARY.md
CHUNKED_CRON_CANARY.md
PARALLEL_CANARYA.md
PARALLEL_CANARYB.md
REBASE_CONFLICT_CANARY.md
```

## Coverage summary

**Static coverage — strong:**
- Skill conformance test (tests/test-skill-conformance.sh) greps 86 critical patterns across the four RESTRUCTURE target skills + /verify-changes. Drops would fire CI before the user sees them.
- Deterministic scripts (apply-preset, compute-cron-fire, port, etc.) have full unit coverage (16 + 29 cases respectively in this iteration).
- Hook behavior (destructive-op policy, tracking enforcement, BLOCK_MAIN_PUSH toggle) covered by test-hooks.sh.
- Mirror parity (`skills/` ↔ `.claude/skills/`, `hooks/` ↔ `.claude/hooks/`) enforced by test-skill-invariants.sh.

**Dynamic coverage — moderate:**
- test-tracking-integration.sh exercises real pipeline marker flow.
- e2e-parallel-pipelines.sh (opt-in via RUN_E2E=1) runs two concurrent pipelines against real git worktrees.

**Dynamic coverage — requires user execution:**
- CANARY1/5 (happy path single-phase)
- CANARY2 (auto-merge disabled fallback)
- CANARY3 (CI failure → fix-cycle → auto-merge)
- CANARY4 (fix exhaustion)
- CANARY6 (multi-PR sequential)
- CANARY7 (chunked finish-auto with cron spacing)
- CANARY8 + PARALLEL_CANARY A/B (concurrent pipelines)
- CANARY9 (final-verify gate)
- CANARY10 (PR-mode tracker bookkeeping)
- CANARY11 (scope-violation halt)
- CI_FIX_CYCLE_CANARY
- CHUNKED_CRON_CANARY

These would ideally run once before RESTRUCTURE to capture the "pre" shape, then again after (Phase 5 of RESTRUCTURE already runs them post) to verify behavioral parity. They were not run in this pass because autonomous execution creates PRs and costs hours of wall time.

**What the RESTRUCTURE should NOT break (summary):**
- The 86 conformance patterns above — if any drop, the test fails CI.
- compute-cron-fire.sh's 29 tests — any regression in cron math surfaces immediately.
- apply-preset.sh's 16 tests — same for preset UX.
- Mirror parity — source ↔ `.claude/` pairs must stay in sync.
- Install audit correctness — verified via fresh-clone smoke tests.
