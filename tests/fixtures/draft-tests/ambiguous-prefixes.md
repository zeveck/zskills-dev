---
title: Ambiguous-Prefixes Fixture
created: 2026-04-29
status: active
---

# Plan: Ambiguous Prefixes

## Overview

A fixture plan with a Pending phase whose AC block contains bullets
with three distinct ambiguous-prefix forms. The skill must leave all
three bullets byte-identical AND emit one advisory line per refused
bullet.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Ambiguous | ⬚ | | pending |

---

## Phase 1 — Ambiguous

### Goal

Test the three-predicate AC-ID classifier's refuse path.

### Work Items

- [ ] 1.1 — work-item-style numbered bullet (NOT inside an AC block — must be byte-identical regardless).

### Acceptance Criteria

- [ ] 1.1 — work-item-style prefix
- [ ] AC-3.2 covered when X happens
- [ ] [scope] given input
- [ ] plain bullet that should get an AC ID assigned (predicate 3).
- [ ] AC-1.4 — already canonical, must remain byte-identical (predicate 1).

### Dependencies

None.
