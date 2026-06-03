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
| 2 — Plans chip three-state + mode-conflict skip + SKIP chip × dismiss | ⬚ Pending | | Scheduled for next cron fire |
| 3 — Issues × dismiss + activity-feed SKIP pill + wrap-up | ⬚ Pending | | After Phase 2 |

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

## Next
Phase 2 (Plans chip three-state + mode-conflict skip + SKIP chip × dismiss with three clear paths) — scheduled via one-shot cron, ~5 min after Phase 1's landing checkpoint.
