---
title: Phase 5 unknown-prose fixture
status: in-progress
---

# Phase 5 unknown-prose fixture

A Completed phase whose ACs contain only prose nouns -- no backticked
tokens. Even if some of those nouns are absent from the repo, the
classifier MUST fall to UNKNOWN, never MISSING. Regression guard
against the prose-token false-positive bug (AC-5.2).

## Progress Tracker

| Phase | Status |
|-------|--------|
| 1     | Done    |

## Phase 1 — Prose-only ACs

### Goal

Shipped, but ACs are prose-only.

### Acceptance Criteria

- [x] AC-1.1 — when the system encounters a frobnicator widget, it gracefully degrades to fallback mode.
- [x] AC-1.2 — when the user provides an unusual zorgborg input, the framework should normalize it.

## Plan Quality

Reviewed once.
