---
title: Phase 4 Base Plan Fixture
status: in-progress
---

# Phase 4 Base Plan Fixture

Two pending non-delegate phases, each with two ACs. Used as the input
plan for Phase 4 review-loop tests.

## Progress Tracker

| Phase | Status |
|-------|--------|
| 1     | Pending |
| 2     | Pending |

## Phase 1 — First feature

### Goal

Implement the first feature.

### Work Items

- [ ] 1.1 — first thing.

### Acceptance Criteria

- [ ] AC-1.1 — first AC describes behavior X.
- [ ] AC-1.2 — second AC describes behavior Y.

### Tests

- [unit] [risk: AC-1.1] given input 0, when first() is called, expect 0.
- [unit] [risk: AC-1.2] given input "a", when first("a") is called, expect "A".

### Dependencies

None.

## Phase 2 — Second feature

### Goal

Implement the second feature.

### Work Items

- [ ] 2.1 — second thing.

### Acceptance Criteria

- [ ] AC-2.1 — first AC of phase 2.
- [ ] AC-2.2 — second AC of phase 2.

### Tests

- [unit] [risk: AC-2.1] given empty input, when second() is called, expect raises ValueError("empty input").
- [unit] [risk: AC-2.2] given input [1,2,3], when second([1,2,3]) is called, expect [2,3,4].

### Dependencies

Phase 1.
