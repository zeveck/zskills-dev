# Plan Report — plans-claim-chip-parity

## Phase — 2a /run-plan acquire / heartbeat / release wiring

**Plan:** plans/plans-claim-chip-parity.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-plans-claim-chip-parity
**Commit:** `a64469c`

### Fence sites added to `skills/run-plan/SKILL.md` (+ `.claude/` mirror)

| Site | Section header | Action | Lines |
|---|---|---|---|
| Stop §3.5 | `^## Stop` step 3.5 | release walk (Option A, all plan-* claims) | ~371-419 |
| Preflight sweep | `### Preflight checks` | source claim-fence-helpers + `sweep_stale_plan_claims` | ~709-720 |
| Acquire | preflight (before mode-detection) | `acquire $PLAN_SLUG` w/ exit-10 decline, exit-0 | ~723-744 |
| Heartbeat 1 | `### Parse plan` | refresh + state machine | ~1034-1060 |
| Heartbeat 2 | `### Post-implementation tracking` | refresh + state machine | ~1550-1576 |
| Heartbeat 3 | `### Post-verification tracking` | refresh + state machine | ~1943-1969 |
| Heartbeat 4 | `### 5. Marker ordering and failure handling` | refresh + state machine | ~2038-2064 |
| Heartbeat 5 | `### Post-report tracking` | refresh + state machine | ~2302-2328 |
| Release §0a | `### 0a. Idempotent early-exit` | release w/ `\|\| true` | ~2338-2349 |
| Refresh §0b | `### 0b. Final-verify gate` (cron-defer site) | refresh w/ attempt+backoff in `--current-phase` | ~2448-2474 |
| Release Phase 6 | `### Post-landing tracking` | release at terminal merge | ~2720-2740 |

### Tests (8 new + supporting edits)

| File | Lines | Result |
|---|---|---|
| `tests/test-plan-claim-race-e2e.sh` | 158 | 1/1 |
| `tests/test-plan-claim-heartbeat.sh` | 138 | 18/18 |
| `tests/test-plan-claim-cron-fire-state-machine.sh` | 200 | 8/8 |
| `tests/test-plan-claim-release-phase6.sh` | 162 | 9/9 |
| `tests/test-plan-claim-release-stop.sh` | 192 | 9/9 |
| `tests/test-plan-claim-release-window.sh` | 129 | 8/8 |
| `tests/test-plan-claim-release-already-complete.sh` | 138 | 6/6 |
| `tests/test-plan-claim-heartbeat-verify-defer.sh` | 175 | 7/7 |

`tests/run-all.sh` +8 `run_suite` lines. `tests/test-skill-conformance.sh` sanitize-wrap literal 14→16 (2 new construct sites: W2a.1 acquire fence, W2a.4 Stop site 1).

### Verification

- **Full test suite**: `Overall: 5481/5481 passed, 0 failed` (baseline 5371; +110).
- **All 7 phase ACs PASS** (verifier-confirmed with line citations + standalone test runs):
  - AC2a.1 race e2e / AC2a.2 heartbeats at all 6 sections / AC2a.3 cron-fire state machine (4 branches) / AC2a.4 3 releases + 1 refresh / AC2a.5 no §1-5 release (regression locked) / AC2a.6 preflight sweep / AC2a.7 acquire (line 734) precedes mode-detection (line 1109)
- **Locked decisions**: D2 (HYBRID heartbeat) and D3 (acquire-or-report exit 0) both confirmed.

`metadata.version` → `2026.05.22+21f33b`.

---

## Phase — 1 Claim primitive + on-disk schema + PreToolUse hook

**Plan:** plans/plans-claim-chip-parity.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-plans-claim-chip-parity (branch `feat/plans-claim-chip-parity`)
**Commit:** `9c8fd56`

### Work Items
| # | Item | Status | Notes |
|---|------|--------|-------|
| W1.1 | claim-plan.sh primitive (acquire/refresh/release/is-stale/sweep/list) | Done | 663 lines; 7-field D5 schema; sibling-clone of claim-issue.sh + new `refresh` subcommand |
| W1.2 | claim-fence-helpers.sh (`sweep_stale_plan_claims`) | Done | 26 lines |
| W1.3 | block-run-plan-unclaimed.sh PreToolUse hook | Done | 256 lines; cp- + feat/ branch regex (non-greedy slug capture); reads `branch_prefix` via inline Python json |
| W1.4 | update-zskills SKILL.md Step 3.7.1 (plan_claim_ttl_seconds backfill) | Done | Idempotent sed detection regex mirrors 3.7 |
| W1.5 | tests/test-plan-claim-script.sh | Done | 19 tests pass |
| W1.6 | tests/test-plan-claim-race-baseline.sh | Done | 2 tests pass |
| W1.7 | tests/test-plan-claim-ttl-config-resolver.sh | Done | 8 tests pass (5 levels + 2 floor + no-config-file) |
| W1.8 | skills/run-plan/SKILL.md metadata.version bump | Done | 2026.05.22+7ae04d |
| W1.9 | tests/test-plan-claim-hook-deny.sh | Done | 9 tests pass — 4 branch shapes (cp-, cp-…-phase-1, cp-…-phase-12, feat/) × claim absent/present + negative control |
| W1.10 | tests/test-plan-claim-main-root-anchor.sh | Done | 4 tests pass — acquire/refresh/release from worktree anchor to MAIN |

### Verification
- **Full test suite**: `Overall: 5415/5415 passed, 0 failed` (baseline 5371; +44 from new Phase 1 tests + 2 conformance picks).
- **Acceptance criteria** (verifier-confirmed with file:line citations):
  - AC1.1 PASS — 7 D5 schema fields written
  - AC1.2 PASS — race baseline: 1 exit 0 + 1 exit 10
  - AC1.3 PASS — pipeline-mismatch refresh exits 12 without mutation
  - AC1.4 PASS — hook denies all 4 branch shapes, all consult same plan-scoped dir
  - AC1.5 PASS — SKILL.md metadata.version matches today + content hash
  - AC1.6 PASS — claim writes anchor to MAIN_ROOT from worktree CWD (DA7)
- **Locked decisions**: D1 (sibling-clone) / D5 (storage+schema) / D7 (hook regex+config-read pattern) / DA13 (slug sanitisation) / TTL 5-level chain — all conform.

### Notes
- Verifier added 5 `run_suite` lines to `tests/run-all.sh` to register the new test files. Without registration the suite would have skipped them entirely. In-scope addition.
- No prose changes to `skills/run-plan/SKILL.md` (only metadata.version) — Phase 2a owns that prose.
- Test output: `/tmp/zskills-tests/zskills-pr-plans-claim-chip-parity/.test-results.txt`.
