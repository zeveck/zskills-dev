---
title: Trailing-Sections Fixture
created: 2026-04-29
status: active
---

# Plan: Trailing Sections

## Overview

A fixture plan with trailing `## Drift Log` and `## Plan Quality`
sections AND a non-canonical `## Non-Goals` section between phases.
Used to verify that the broad-form, fenced-code-block-aware
section-boundary rule terminates the last Completed phase's checksum
correctly at the non-canonical heading and that later edits to trailing
sections do not flag drift on the Completed phase.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Setup | Done | aaa1111 | done |
| 2 — Wire | Done | bbb2222 | done |
| 3 — Polish | ⬚ | | pending |

---

## Phase 1 — Setup

### Goal

Setup phase.

### Work Items

- [ ] 1.1 — set up the thing.

### Acceptance Criteria

- [ ] AC-1.1 — thing is set up.

### Dependencies

None.

---

## Phase 2 — Wire

### Goal

Wire it up.

### Work Items

- [ ] 2.1 — wire it.

### Acceptance Criteria

- [ ] AC-2.1 — it is wired.

### Dependencies

Phase 1.

---

## Non-Goals

This is a non-canonical level-2 heading that the broad-form boundary
rule MUST terminate the prior Completed phase's checksum at. A closed
enumeration would silently sweep these bytes into Phase 2's checksum
and produce false drift errors when this section is later edited.

---

## Phase 3 — Polish

### Goal

Polish.

### Work Items

- [ ] 3.1 — polish it.

### Acceptance Criteria

- [ ] criterion to be ID-prefixed (assign AC-3.1).

### Dependencies

Phase 2.

---

## Drift Log

Existing trailing section. Must NOT be swept into Phase 3's bytes.

| Phase | Planned | Actual | Delta |
|-------|---------|--------|-------|
| 1 | x | x | none |

## Plan Quality

Existing trailing section. Must remain byte-identical.
