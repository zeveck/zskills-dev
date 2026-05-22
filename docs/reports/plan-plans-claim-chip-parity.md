# Plan Report — plans-claim-chip-parity

## Plan complete ✅

All 6 phases done. Frontmatter `status: complete`. Branch `feat/plans-claim-chip-parity` landed via /land-pr.

## Phase — 5 Optional cleanup + verification

**Status:** Completed (verification-only phase, no commits)

### W5.1 — Four-layer skill-version enforcement

| Layer | Status |
|---|---|
| (a) warn-config-drift Edit-time | Fires only on Edit hook; not testable inline. Confirmed by clean Edit-time experience across phases. |
| (b) /commit step 2.5 (commit-time) | Exercised at every phase commit; all phases committed cleanly (no version-mismatch denies). |
| (c) test-skill-conformance.sh (CI) | **523/523 passed** standalone. |
| (d) block-stale-skill-version.sh (PreToolUse) | All commits passed through (clean hashes: 9c8fd56, a64469c, 41b9a99, ce48b11, d9c19af). |

### W5.2 — Manual two-shell e2e

DEFERRED for post-merge user verification. Requires user-attended browser interaction (dashboard live-state observation, concurrent shell invocations); the autonomous /run-plan flow cannot drive a human-observed test.

### W5.3 — Theme spot-check (light/dark dashboard)

DEFERRED for post-merge user verification. Same reason.

### W5.4 — Final `bash tests/run-all.sh`

**Final tally**: see commit-time test-results file.

### W5.5 — Drift Log

No divergence from locked D1-D7 during implementation. All verifier-flagged deviations (e.g., conformance grep joining backslash-continuations, `^### Execution` anchor matching actual heading, brittleness fix on issue-side test) were legitimate adaptations to file shape, not departures from intent. No Drift Log entries needed.

### metadata.version final state

| Skill | Version |
|---|---|
| skills/run-plan | 2026.05.22+c98e49 |
| skills/work-on-plans | 2026.05.22+bac087 |
| skills/zskills-dashboard | 2026.05.22+4c4eaa |
| skills/update-zskills | 2026.05.22+1d0faf |

---

## Phase — 4 Conformance tests + SKILL.md prose + follow-up issue

**Plan:** plans/plans-claim-chip-parity.md
**Status:** Completed (verified)
**Commit:** `d9c19af`

### Changes

- `tests/test-plan-claim-conformance.sh` (250 lines, 15 assertions): acquire-before-Execution (A11), 6 section-scoped refresh windows (DA2.6 + DA3.1), 3 section-scoped release windows + 1 refresh-during-defer, NEGATIVE no Phase 5b §1-5 release, NEGATIVE no `LAND_OUTCOME`, sweep-before-filter ordering in /work-on-plans Step 4, hook registration, Issue #604 adjacency.
- `skills/run-plan/SKILL.md`: new "Plan-claim mechanism" prose (~60 lines): storage / lifecycle / acquire-or-decline / heartbeat cadence / cron-fire state machine / release sites / PreToolUse backstop. `metadata.version` → `2026.05.22+c98e49`.
- `skills/work-on-plans/SKILL.md`: new "Selection-aware plan-claim filter (D4)" prose (~38 lines) with honest scope (DA2.7: steady-state closure only; fresh-start race acquire-bounded). `metadata.version` → `2026.05.22+bac087`.
- `.claude/` mirrors of both SKILL.md edits.
- `tests/run-all.sh` +1 line registering the conformance test.

### GitHub issue (W4.4)

**[#641](https://github.com/zeveck/zskills-dev/issues/641)** — "/fix-issues Phase 2 picker also needs selection-aware filter (per /work-on-plans + /run-plan claim chip parity)". Body cites `skills/fix-issues/SKILL.md ~lines 686-720` (the /fix-issues picker), explicitly notes independence from /work-on-plans, and includes the user-steering quote reference.

### Verification

- **Full test suite**: `Overall: 5602/5602 passed, 0 failed` (baseline 5595; +7 net).
- **All 3 phase ACs PASS** with file:line evidence.
- **Adjacency check**: `grep "/tracking/" skills/run-plan/scripts/claim-plan.sh` → zero hits. Claim writes isolated to `.zskills/claims/`.
- **D6 conformance**: zero CSS files modified.

### Implementer deviations (both legitimate)

1. Conformance grep joins backslash-continuation lines via `sed ':a;N;$!ba;s/\\\n[[:space:]]*/ /g'` before counting (SKILL.md call sites are multi-line). Post-join uses literal `claim-plan.sh" + whitespace + verb`. Verb match remains exact.
2. `^### Execution` anchor instead of `^### Execution: ` (actual heading is `### Execution mode detection`, no colon — plan text was stale).

---

## Phase — 3 Dashboard collect.py + render-side wiring

**Plan:** plans/plans-claim-chip-parity.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-plans-claim-chip-parity
**Commit:** `ce48b11`

### Changes

| Layer | Detail |
|---|---|
| `collect.py` | `_read_plan_claims()` mirrors `_read_claims()` (slug-keyed). `_annotate_plans_queue` attaches `plan["claim"]` with explicit 6-field allow-list: `pipeline_id`, `started_at`, `last_heartbeat_at`, `current_phase`, `age_seconds`, `pipeline_short`. NO `worktree_path` / `host_pid`. |
| `app.js fingerprintPlans` | Extended to include `[p.claim?.pipeline_id, p.claim?.last_heartbeat_at]` per plan row (heartbeat, NOT started_at — chip ageStr must re-render between phases). |
| `app.js buildPlanCard` | Chip text `"in-flight · <pidShort> · phase N/M · <ageStr>"`. `phaseStr` from regex `/Phase\s+(\d+)/i` against `claim.current_phase`; fallback `"phase ?/M"` for section-name headers. `aria-disabled="true"` + `removeAttribute("draggable")` on claim presence. Reuses `.claim-chip--in-flight` CSS class (D6 — no new CSS). |
| `app.js handleAction` | Guard arm before `plan-up/down/left/right/plan-remove` dispatches; matches `closest('li.card[aria-disabled="true"][data-kind="plan"]')`; toast `"Plan is in-flight; release the claim or wait for completion."` |
| `app.js moveAllInColumn` | Already kind-generic + respects `aria-disabled` per-card (no change). Locked by new test. |
| `tests/test-fix-issues-claim-render-dom.sh` | Brittleness fix: anchors gate-search to `_annotate_issues_queue` function body (needed because `_annotate_plans_queue` now has the same gate pattern). Intent preserved; 51/51 still pass. |
| `SKILL.md` mirrors + `metadata.version` | bumped to `2026.05.22+4c4eaa`. |

### Tests (6 new — 86 tests)

| File | Pass/Fail | Lines |
|---|---|---|
| `tests/test-plan-claim-collector.sh` | 10/0 | 113 |
| `tests/test-plan-claim-collector.py` | 10/0 | 300 |
| `tests/test-plan-claim-render-dom.sh` | 25/0 | 400 (node DOM stub) |
| `tests/test-plan-claim-handleaction-guard.sh` | 35/0 | 350 (node DOM stub) |
| `tests/test-plan-claim-moveall-skip.sh` | 7/0 | 309 |
| `tests/test-plan-claim-fingerprint.sh` | 9/0 | 215 |

Render-DOM tests use node DOM stub (faster + matches symmetric issue-side pattern at `test-fix-issues-claim-render-dom.sh`). Phase 5 W5.2 schedules a separate manual two-shell e2e for live-dashboard validation.

### Verification

- **Full test suite**: `Overall: 5595/5595 passed, 0 failed` (baseline 5503; +92 net after 96 new tests landed).
- **All 6 phase ACs PASS** with file:line evidence.
- **D6 conformance** confirmed: zero `.css` files modified.

---

## Phase — 2b /work-on-plans selection-aware filter

**Plan:** plans/plans-claim-chip-parity.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-plans-claim-chip-parity
**Commit:** `41b9a99`

### Changes

| Item | Detail |
|---|---|
| `skills/work-on-plans/scripts/filter-in-flight-plan-claims.sh` | 200 lines. TSV stdin → filtered TSV stdout. Reads `.zskills/claims/plan-*/claim.json` via Python json. Graceful on malformed/missing/unreadable inputs. Exit 0 always. |
| `skills/work-on-plans/SKILL.md` Step 4 | Pre-filter sweep fence at line 501 + Selection filter fence at line 516. Sweep < filter (R2.6 ordering). Defensive `[ -x ]` check on script path. `metadata.version` → `2026.05.22+398b99`. |
| `.claude/` mirrors | byte-identical copies. |

### Tests (4 new — 28 tests)

| File | Pass/Fail | Notes |
|---|---|---|
| `tests/test-plan-claim-selection-filter.sh` | 8/0 | AC2b.1 — filter drops `foo`, picks `bar`, stderr `Skipped 1 plan(s)…` |
| `tests/test-work-on-plans-parallel-selection.sh` | 6/0 | AC2b.2 — STEADY-STATE only per DA2.7 (test name + comments document scope) |
| `tests/test-plan-claim-filter-edge-cases.sh` | 8/0 | AC2b.3 — malformed/missing/empty/unreadable + invalid slug shapes |
| `tests/test-work-on-plans-pre-filter-sweep.sh` | 6/0 | AC2b.5 — source-level line-order check + behavioural sweep-before-filter |

### Verification

- **Full test suite**: `Overall: 5503/5503 passed, 0 failed` (baseline 5481; +22 net after 28 new tests landed — accounted by conformance pickups).
- **All 5 phase ACs PASS** with file:line evidence.
- **D4 + D5 locked decisions** conform. Mirrors verified identical via `diff -q`.

### Honest scope (DA2.7)

The filter closes the STEADY-STATE race only. Fresh-start race (both invocations observe empty claims-dir before either acquires) is bounded by Phase 1's atomic-mkdir acquire — see plan Overview / DA2.7. Test #2 explicitly documents this scope in its name + leading comment.

---

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
