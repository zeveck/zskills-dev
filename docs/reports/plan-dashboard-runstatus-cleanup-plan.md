---
title: "Dashboard Run-Status Cleanup — /run-plan Report"
plan: docs/plans/DASHBOARD_RUNSTATUS_CLEANUP_PLAN.md
pipeline: run-plan.dashboard-runstatus-cleanup-plan
landing_mode: pr
branch: feat/dashboard-runstatus-cleanup-plan
worktree: /tmp/zskills-pr-dashboard-runstatus-cleanup-plan
issues: [1005, 1006]
updated: 2026-06-03
---

# Dashboard Run-Status Cleanup — Plan Execution Report

## Status by phase

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Rip run-status pill + trigger plumbing + queue POST preserve-by-default | ✅ Done | 9ecd939 | 18 files; +457 / −1997; 7397/7397 tests pass |
| 2 — Plans chip three-state + mode-conflict skip + SKIP chip × dismiss | ✅ Done | f6f134e | 25 files; +2571 / −67; 7464/7464 tests pass; 6/6 playwright |
| 3 — Issues × dismiss + activity-feed SKIP pill + wrap-up | ⬚ Pending | | Scheduled for next cron fire |

## Phase 1 — what landed

Commit `9ecd939` on `feat/dashboard-runstatus-cleanup-plan`:

- **Dashboard rip:** deleted the top-level `#run-status` div in `index.html`; deleted JS surface (`TRIGGER_URL`, `WORK_STATE_RESET_URL`, `renderRunStatus`, `postTrigger`, `postWorkStateReset`, `fetchWorkState`, `pollWorkOnce`, `scheduleWorkPoll`, `applyWorkState`, `workPollTimer`, `workPollAbort`, `lastFingerprint.workState`, and the three click-delegator arms `run-top-n`, `run-stop`, `clear-stale-sprint`); deleted CSS (`.run-status` block, `.run-btn`/`.run-stop-btn`/`.clear-stale-btn`/`.run-n-input` rules); KEPT `.copy-btn` and `.add-mini-btn` (surgical drop).
- **Server endpoints removed:** `POST /api/trigger` and `POST /api/work-state/reset` with their handlers (`_handle_trigger_post`, `_handle_work_state_reset`); the `TRIGGER_TIMEOUT_SECS` constant; `TRIGGER_CMD_RE` regex; `validate_trigger_config`; the `trigger_configured` field injection inside `_handle_work_state_get` (the GET endpoint itself stays — per-plan chip resolution chain depends on it).
- **Queue POST preserve-by-default refactor:** `_handle_queue_post` in `server.py` now deep-copies the existing monitor-state dict as its base, then overlays only writer-owned column allow-lists. This preserves `plans.skipped`, `issues.skipped`, `issues.reconsider` across drag-drops. Reader-call-site comment documents the full-shape-read invariant. Side benefit: closes a pre-existing latent bug for `issues.skipped` (#813/#733).
- **Outbound payload hardening:** `app.js` strips `plans.skipped` from the outbound queue payload via `stripServerOwnedPlanKeys` (server owns that key).
- **Config schema:** deleted the `dashboard` block in `config/zskills-config.schema.json`.
- **/update-zskills:** deleted Step 3.6 backfill prose + the `"dashboard": { "work_on_plans_trigger": "" }` block in the JSON sample.
- **zskills-dashboard SKILL.md:** deleted the trigger-script Configuration section.
- **Tests:** DELETED `tests/test-dashboard-run-status-locks.sh` (~280 lines) + its registration in `tests/run-all.sh`; pruned `tests/test_zskills_monitor_dashboard_ui.sh` (130-line delta, target grep now 0) + `tests/test_zskills_monitor_server.sh` (208-line delta); ADDED `tests/test-monitor-state-queue-post-preservation.sh` (21/21 cases: 3 keys × 7 assertions) + its registration.
- **Skill bumps:** `zskills-dashboard` → `2026.06.02+65dd5d`, `update-zskills` → `2026.06.02+a5b844`. Mirror parity verified (`diff -rq` empty for both).

## Test tally
```
Overall: 7397/7397 passed, 0 failed
```
Baseline file was 30 bytes (truncated — a concurrent session was running tests during capture); fell back to absolute pass tally per the verifier protocol.

## Verifier verdict
PASS on all ACs + invariants. Commit landed cleanly (no skill-version hook deny).

## Issues claimed
`#1005` (`run-plan.dashboard-runstatus-cleanup-plan`) — held for plan lifetime.
`#1006` (`run-plan.dashboard-runstatus-cleanup-plan`) — held for plan lifetime.

## Phase 2 — what landed

Commit `f6f134e` on `feat/dashboard-runstatus-cleanup-plan`:

- **Plans chip three-state INHERIT / PHASE / FINISH** with explicit `"inherit"` label rendered (no more collapse to literal `"finish"`).
- **FINISH-claim chip lock anchored on `claim.dispatch_mode`** (NOT `batch_mode` — the #930 trap explicitly avoided). PHASE claims stay togglable; FINISH claims render `aria-disabled=true` + `state=running-finish`.
- **`/work-on-plans` mode-conflict skip filter** via `skills/work-on-plans/scripts/filter-mode-mismatch-plans.sh` — writes `plans.skipped[slug] = {code:"mode-mismatch", reason:"<batch>≠<pin>", sprint_id, at}` via atomic-write (NamedTemporaryFile + os.replace under flock).
- **SKIP chip × dismiss button** rendered on plan cards in `plans.skipped` state, with new `/api/plan-skip-dismiss` endpoint → `_handle_plan_skip_dismiss_post`.
- **Three clear paths** converging on `monitor-state.json:plans.skipped[slug]`:
  - (a) **claim-acquire** — `clear_plan_skip_if_present` in `claim-plan.sh` (inline hot-path bash, idempotent, NON-ABORTING — confirmed by smoking corrupt monitor-state.json against acquire and getting exit 0).
  - (b) **pin-toggle** — server-side `_flatten_modes` diff in `_handle_queue_post` pops only on pin change OR slug disappearance, layered ADDITIVELY on Phase 1's deep-copy base.
  - (c) **× click** — `/api/plan-skip-dismiss` endpoint atomic-writes the pop.
- **Direct `/run-plan <slug> finish` bypasses the pin** — `cmd_acquire` does NOT consult `monitor-state.json:plans.ready[].mode`; only batch-dispatched `/work-on-plans` honors the pin via the new filter.
- **Tests:** `test-mode-chip-three-state.sh` extended (66 cases); new `test-plans-skip-chip.sh` (25 cases) + `test-plan-skip-clear-paths.sh` (17 cases); `test-work-on-plans-dispatch-seam.sh` +6 mm-cases (37 total).
- **Skill bumps:** `zskills-dashboard`, `work-on-plans`, `run-plan`. Mirror parity verified.

## Test tally
```
Overall: 7464/7464 passed, 0 failed
```

## Playwright verification (Phase 2)
6/6 dashboard render checks executed end-to-end on a worktree-spawned dashboard server (port 8092):
1. INHERIT chip — text=inherit, state=queued, source=inherit
2. Explicit `phase` pin — text=phase, source=explicit
3. FINISH-claim lock — innerHTML-finish=true, state=running-finish, disabled=disabled, aria-disabled=true
4. PHASE-claim (not locked) — text=phase, state=running-phase, clickable
5. SKIP chip with × button — chip + `<button aria-label="Dismiss skip for …">` rendered
6. × click clears via next poll — DOM `.skip-chip` count 1→0; server state `plans.skipped == {}`

## Next
Phase 3 (Issues × dismiss + activity-feed SKIP pill + CHANGELOG + final mirror sync) — scheduled via one-shot cron.
