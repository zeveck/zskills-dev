---
title: Phase 5 fenced-trailing fixture
status: in-progress
---

# Phase 5 fenced-trailing fixture

Contains a fenced markdown block with `## Example` at column 0 INSIDE
the fence. The backfill insertion site MUST be determined by the first
non-fenced trailing heading -- NOT the in-code one. AC-5.7
fenced-code-block regression guard.

## Progress Tracker

| Phase | Status |
|-------|--------|
| 1     | Done    |

## Phase 1 — Shipped, with fenced example

### Goal

Shipped without coverage. Body contains a fenced markdown block
with a `## Example` heading inside the fence.

```markdown
## Example

This `## Example` heading is INSIDE a fence and must NOT be treated
as a real trailing section. The backfill insertion point MUST step
past it and use the first NON-FENCED trailing heading.
```

### Acceptance Criteria

- [x] AC-1.1 — function `qrxzthopGapFenced000` returns the canonical token.

## Plan Quality

Plan reviewed.
