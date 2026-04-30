---
title: Example plan — illustrating /draft-tests
status: active
---

# Example plan — illustrating /draft-tests

A small, purpose-built plan demonstrating what `/draft-tests` does.
Two phases: Phase 1 already Completed (with shipped tests), Phase 2
Pending (no `### Tests` subsection yet).

## Progress Tracker

| Phase | Name              | Status |
|-------|-------------------|--------|
| 1     | Compute the sum   | Done   |
| 2     | Compute the mean  | ⬚      |

## Phase 1 — Compute the sum

### Goal

Sum a list of numbers.

### Work Items

- [ ] 1.1 — Implement `sum(values)` accepting a list of numbers.
- [ ] 1.2 — Return zero on an empty list.

### Acceptance Criteria

- [ ] AC-1.1 — `sum([1, 2, 3])` returns `6`.
- [ ] AC-1.2 — `sum([])` returns `0`.

### Tests

- AC-1.1 — Unit test in `tests/test-sum.py`. Input `[1, 2, 3]`. Expect
  return value `6`.
- AC-1.2 — Unit test in `tests/test-sum.py`. Input `[]`. Expect return
  value `0`.

## Phase 2 — Compute the mean

### Goal

Compute the arithmetic mean of a list of numbers.

### Work Items

- [ ] 2.1 — Implement `mean(values)` returning the arithmetic mean.
- [ ] 2.2 — Raise `ValueError` on an empty list.

### Acceptance Criteria

- [ ] AC-2.1 — `mean([1, 2, 3])` returns `2.0`.
- [ ] AC-2.2 — `mean([])` raises `ValueError`.

### Tests

- AC-2.1 — Unit test in `tests/test-mean.py`. Input `[1, 2, 3]`. Expect
  return value `2.0`.
- AC-2.2 — Unit test in `tests/test-mean.py`. Input `[]`. Expect
  `ValueError` raised with message containing `empty`.
