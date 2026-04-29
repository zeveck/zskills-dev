---
title: Mixed-Status Fixture Plan
created: 2026-04-29
status: active
---

# Plan: Mixed-Status Fixture

## Overview

A fixture plan exercising every Progress Tracker status glyph that
`/draft-tests` Phase 1 must classify: `Done`, `✅`, `[x]`, `⬚`, `⬜`,
and an empty cell.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Done text | Done | abc1234 | finished |
| 2 — Checkmark | ✅ | def5678 | shipped |
| 3 — Bracket-x | [x] | 9012345 | merged |
| 4 — Empty box | ⬚ | | not started |
| 5 — Light box | ⬜ | | not started |
| 6 — Empty cell |  | | unclear |

---

## Phase 1 — Done text

### Goal

Test classification of a `Done` status row.

### Work Items

- [ ] 1.1 — sample work item (ambiguous-prefix; a real numbered work item).

### Acceptance Criteria

- [ ] AC-1.1 — already-prefixed canonical (must NOT be modified — Completed).

### Dependencies

None.

---

## Phase 2 — Checkmark

### Goal

Test classification of a `✅` status row.

### Work Items

- [x] 2.1 — completed work item.

### Acceptance Criteria

- [x] AC-2.1 — completed canonical (must NOT be modified — Completed).

### Dependencies

Phase 1.

---

## Phase 3 — Bracket-x

### Goal

Test classification of an `[x]` status row.

### Work Items

- [ ] 3.1 — sample work item.

### Acceptance Criteria

- [ ] AC-3.1 — completed canonical, must remain byte-identical (Completed).

### Dependencies

Phase 2.

---

## Phase 4 — Empty box

### Goal

Test classification of an `⬚` status row (Pending).

### Work Items

- [ ] 4.1 — sample work item.

### Acceptance Criteria

- [ ] gain a canonical AC-ID prefix (this is plain — assign AC-4.1).
- [ ] another plain bullet (assign AC-4.2).

### Dependencies

Phase 3.

---

## Phase 5 — Light box

### Goal

Test classification of an `⬜` status row (Pending).

### Work Items

- [ ] 5.1 — sample work item.

### Acceptance Criteria

- [ ] still pending criterion (assign AC-5.1).

### Dependencies

Phase 4.

---

## Phase 6 — Empty cell

### Goal

Test classification of an empty status cell (Pending — everything else).

### Work Items

- [ ] 6.1 — sample work item.

### Acceptance Criteria

- [ ] empty-status pending bullet (assign AC-6.1).

### Dependencies

Phase 5.
