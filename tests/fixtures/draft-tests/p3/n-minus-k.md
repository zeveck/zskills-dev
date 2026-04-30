---
title: N-Minus-K Fixture
created: 2026-04-29
status: active
---

# Plan: N − K Coverage

## Overview

Four Pending non-delegate phases (N=4); one is ac-less (K=1).
After Phase 3 runs, the plan must contain exactly N − K = 3 `### Tests`
subsections — one per Pending non-delegate non-ac-less phase. The
ac-less phase MUST NOT receive a `### Tests` subsection (per WI 3.5).

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — First | ⬚ | | pending |
| 2 — Second | ⬚ | | pending |
| 3 — Ac-less | ⬚ | | no AC block |
| 4 — Fourth | ⬚ | | pending |

---

## Phase 1 — First

### Goal

The first Pending phase.

### Work Items

- [ ] 1.1 — do thing A.

### Acceptance Criteria

- [ ] criterion (assign AC-1.1).

### Dependencies

None.

---

## Phase 2 — Second

### Goal

The second Pending phase.

### Work Items

- [ ] 2.1 — do thing B.

### Acceptance Criteria

- [ ] criterion (assign AC-2.1).

### Dependencies

Phase 1.

---

## Phase 3 — Ac-less

### Goal

A Pending non-delegate phase with no `### Acceptance Criteria` block.
Phase 3 of /draft-tests must NOT append `### Tests` here (per WI 3.5).

### Work Items

- [ ] 3.1 — placeholder.

### Dependencies

Phase 2.

---

## Phase 4 — Fourth

### Goal

The fourth Pending phase.

### Work Items

- [ ] 4.1 — do thing D.

### Acceptance Criteria

- [ ] criterion (assign AC-4.1).

### Dependencies

Phase 3.
