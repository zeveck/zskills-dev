---
title: Canary Tracking Test
created: 2026-04-12
status: active
---

# Plan: Canary Tracking Test

## Overview

Trivial one-phase plan to verify the tracking system works end-to-end.
Creates a single file, exercises the full flow: markers, .zskills-tracked,
ZSKILLS_PIPELINE_ID, verification-before-commit, and cherry-pick landing.

Delete the canary file after the test: `git rm tests/canary-timestamp.txt`

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Canary | ⬚ | | Single file creation + verification |

## Phase 1 — Canary

### Goal

Create a timestamp file to exercise the tracking enforcement pipeline.

### Work Items

- [ ] Create `tests/canary-timestamp.txt` containing the current date and the text "Canary tracking test"
- [ ] Run `bash tests/test-hooks.sh` to verify tests still pass

### Acceptance Criteria

- [ ] `tests/canary-timestamp.txt` exists with a date in it
- [ ] All hook tests pass (62+ tests)
