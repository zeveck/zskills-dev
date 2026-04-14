---
title: Canary 5 — Autonomous End-to-End
created: 2026-04-14
status: complete
---

# Plan: Canary 5 — Autonomous End-to-End

## Overview
Validates full autonomous `/run-plan pr auto` orchestration with multiple
phases sharing one PR. Each phase builds on the previous.

## Progress Tracker
| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 -- Hello script | ✅ Done | `4a6075d` | hello() function |
| 2 -- Hello self-test | ✅ Done | `72d8a13` | BASH_SOURCE-guarded self-test |

## Phase 1 -- Hello script

### Goal
Create a shell script with a `hello` function.

### Work Items
- [ ] Create `canary/hello.sh` with:
  ```bash
  #!/bin/bash
  hello() { echo "Hello, $1!"; }
  ```
- [ ] Make it executable: `chmod +x canary/hello.sh`
- [ ] Source and test manually: `source canary/hello.sh && [ "$(hello World)" = "Hello, World!" ] && echo OK`

### Acceptance Criteria
- [ ] `canary/hello.sh` exists, is executable
- [ ] `hello "Name"` returns `Hello, Name!`
- [ ] Committed in worktree

### Dependencies
None.

## Phase 2 -- Hello self-test

### Goal
Extend `canary/hello.sh` with a self-test block.

### Work Items
- [ ] Append a self-test block to `canary/hello.sh` guarded by `BASH_SOURCE`:
  ```bash

  # Self-test (runs only when executed directly)
  if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    [ "$(hello World)" = "Hello, World!" ] && echo "PASS" || { echo "FAIL"; exit 1; }
  fi
  ```
- [ ] Run `bash canary/hello.sh` — must print `PASS`
- [ ] Source and verify no test fires: `source canary/hello.sh` should produce no output

### Acceptance Criteria
- [ ] `bash canary/hello.sh` prints `PASS`
- [ ] `source canary/hello.sh` produces no test output (self-test guarded)
- [ ] Committed in worktree

### Dependencies
Phase 1.
