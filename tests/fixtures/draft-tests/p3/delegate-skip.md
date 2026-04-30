---
title: Delegate-Skip Fixture
created: 2026-04-29
status: active
---

# Plan: Delegate-Skip

## Overview

Three Pending phases: one normal non-delegate, one delegate (contains
`### Execution: delegate ...`), one normal non-delegate. Phase 3 of
/draft-tests must skip the delegate phase — its phase id must appear in
BOTH the parsed-state `delegate_phases:` list AND the drafter output's
`delegate_skipped_phases:` list (set-equality, AC-3.6).

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Normal | ⬚ | | pending |
| 2 — Delegate | ⬚ | | delegated |
| 3 — Normal-Two | ⬚ | | pending |

---

## Phase 1 — Normal

### Goal

A normal non-delegate Pending phase.

### Work Items

- [ ] 1.1 — do thing A.

### Acceptance Criteria

- [ ] criterion (assign AC-1.1).

### Dependencies

None.

---

## Phase 2 — Delegate

### Goal

A delegate Pending phase. Test coverage is the delegated skill's
responsibility.

### Work Items

- [ ] 2.1 — delegated work.

### Execution: delegate /add-block to scaffold the new sub-skill

Delegate to `/add-block` with appropriate arguments.

### Acceptance Criteria

- [ ] AC-2.1 — outputs are produced by the sub-skill.

### Dependencies

Phase 1.

---

## Phase 3 — Normal-Two

### Goal

Another normal non-delegate Pending phase.

### Work Items

- [ ] 3.1 — do thing C.

### Acceptance Criteria

- [ ] criterion (assign AC-3.1).

### Dependencies

Phase 2.
