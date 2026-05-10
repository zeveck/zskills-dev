---
title: Canary 3 — Fix Cycle
created: 2026-04-14
status: active
---

# Plan: Canary 3 — Fix Cycle

## Overview
Validates CI failure → fix cycle → re-push → CI passes → auto-merge.

The plan deliberately creates a file with a bash syntax error that CI's
`bash -n hooks/*.sh` step will catch. Local verification doesn't run
syntax checks, so the bug commits successfully. CI fails, and the fix
cycle should read the log, dispatch a fix agent, and correct the file.

## Progress Tracker
| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 -- Create file with deliberate syntax error | ⬜ | | Intentional bug |

## Phase 1 -- Create file with deliberate syntax error

### Goal
Create `hooks/canary3-bad.sh` with a bash syntax error.

**THE BUG IS INTENTIONAL.** Do NOT fix it. This canary tests that CI
catches it and the fix cycle handles the correction.

### Work Items
- [ ] Create `hooks/canary3-bad.sh` with EXACTLY this content (preserve the bug):
  ```bash
  #!/bin/bash
  # canary 3 — deliberate syntax error
  if then
    echo "bad"
  fi
  ```
- [ ] Do NOT fix `if then` — that's the bug. `if` requires a condition
  between it and `then`. CI's `bash -n` will fail on this.

### Acceptance Criteria
- [ ] File `hooks/canary3-bad.sh` exists with the bug intact
- [ ] File committed in worktree
- [ ] Local tests still pass (the bug only affects bash syntax check, not unit tests)

### Dependencies
None.
