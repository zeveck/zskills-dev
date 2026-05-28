---
title: Canary 4 — Fix Exhaustion
created: 2026-04-14
status: active
---

# Plan: Canary 4 — Fix Exhaustion

## Overview
Validates `status: pr-ci-failing` when fix attempts exhaust.

CI has a deliberate failure step gated on branch name "canary4". The plan
creates a trivial file. CI fails because of the workflow step, not the
plan's file. The fix agent should recognize this is infrastructure, not
a code bug, and report inability to fix.

`ci.max_fix_attempts: 1` keeps the canary short.

## Progress Tracker
| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 -- Add canary file | ⬜ | | Plan file is fine; CI step is the bug |

## Phase 1 -- Add canary file

### Work Items
- [ ] Create `canary/c4.txt` with content: `canary 4 — fix exhaustion — <timestamp>`

### Acceptance Criteria
- [ ] File exists
- [ ] Committed in worktree
- [ ] Expected outcome: CI fails due to workflow step, fix cycle exhausts, `status: pr-ci-failing`

### Dependencies
None.
