---
title: Phase 4 Missing-Coverage Fixture
status: in-progress
---

# Phase 4 Missing-Coverage Fixture

A plan whose pending phase 1 has 2 ACs but only one spec referencing
either of them. Used to verify the orchestrator's coverage-floor
pre-check synthesises a finding even when reviewer/DA both return
"No findings" (AC-4.2).

## Progress Tracker

| Phase | Status |
|-------|--------|
| 1     | Pending |

## Phase 1 — Lonely phase

### Goal

A single pending phase with two ACs, only one spec.

### Work Items

- [ ] 1.1 — do thing A.
- [ ] 1.2 — do thing B.

### Acceptance Criteria

- [ ] AC-1.1 — first AC: behavior alpha.
- [ ] AC-1.2 — second AC: behavior beta.

### Tests

- [unit] [risk: AC-1.1] given input 0, when alpha() is called, expect 0.

### Dependencies

None.
