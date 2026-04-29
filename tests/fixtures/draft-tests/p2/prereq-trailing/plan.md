---
title: Prereq-Trailing Fixture Plan
created: 2026-04-29
status: active
---

# Plan: Prereq-Trailing Fixture

## Overview

A fixture plan with several non-canonical trailing level-2 sections.
Used by AC-2.10: when /draft-tests inserts `## Prerequisites` between
`## Overview` and `## Progress Tracker`, every other level-2 section
(canonical AND non-canonical) MUST be byte-identical before/after.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Stub | ⬚ | | pending |

---

## Phase 1 — Stub

### Goal

Stub.

### Work Items

- [ ] 1.1 — stub.

### Acceptance Criteria

- [ ] criterion (will receive AC-1.1).

### Dependencies

None.

---

## Anti-Patterns -- Hard Constraints

These are non-canonical trailing sections that AC-2.10 explicitly tests
against the closed-enumeration regression. Their bytes MUST be
byte-identical before/after the Prerequisites insertion.

- Do not weaken tests.
- Do not bypass hooks.

## Non-Goals

Another non-canonical trailing section.

- We will not migrate the database.
- We will not add a UI.

## Risks and Mitigations

Yet another non-canonical trailing heading.

| Risk | Mitigation |
|------|------------|
| Stub | None — out of scope |
