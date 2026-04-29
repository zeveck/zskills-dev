---
title: Ac-less-and-Normal Fixture
created: 2026-04-29
status: active
---

# Plan: Ac-less and Normal

## Overview

A fixture plan with one Pending non-delegate phase WITHOUT an
`### Acceptance Criteria` block (ac-less) and one normal Pending
non-delegate phase (with an AC block). Used to verify AC-1.7b: ac-less
phase is appended to `ac_less:` AND retains membership in
`non_delegate_pending_phases:`. The skill's final output emits exactly
one ac-less advisory line. Phase 3's M = N − K formula self-passes
(N = 2 non-delegate Pending; K = 1 ac-less; M = 1 → exactly one
`### Tests` subsection appended in Phase 3, to the normal phase only).

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Ac-less | ⬚ | | no AC block |
| 2 — Normal | ⬚ | | has AC block |

---

## Phase 1 — Ac-less

### Goal

A Pending phase with no `### Acceptance Criteria` block.

### Work Items

- [ ] 1.1 — placeholder.

### Dependencies

None.

---

## Phase 2 — Normal

### Goal

A Pending phase with a normal AC block.

### Work Items

- [ ] 2.1 — do something.

### Acceptance Criteria

- [ ] criterion (assign AC-2.1).

### Dependencies

Phase 1.
