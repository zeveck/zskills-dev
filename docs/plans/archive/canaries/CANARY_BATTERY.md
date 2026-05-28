# CI Canary Battery — Phase 3b-iii Validation

End-to-end validation of PR mode + CI integration. Run canaries in order.
Each tests a distinct code path in the `/run-plan pr` flow.

**Goal:** prove that all five outcome paths in 3b-iii actually work against
a real GitHub repo with real CI.

---

## Prerequisites (one-time setup)

### 1. Push CI workflow to dev

```
! git push dev main
```

The workflow file is at `.github/workflows/test.yml`. Once on dev, GitHub
Actions starts running on every push to a feature branch.

### 2. Enable auto-merge on zskills-dev

GitHub repo settings → General → "Pull Requests" section → check
**"Allow auto-merge"**.

URL: https://github.com/zeveck/zskills-dev/settings

This is required for Canary 1 (auto-merge succeeds → status: landed).
Canary 2 deliberately disables it to test the fallback (PR open → status: pr-ready).

### 3. Verify CI fires

After step 1, push a small change to a throwaway branch and check that
GitHub Actions runs the workflow. Confirm it shows up at:
https://github.com/zeveck/zskills-dev/actions

### 4. Confirm clean state before starting

```
git worktree list                   # only main worktree
git status -s                       # clean
git remote -v                       # origin/dev=zskills-dev, prod=zskills
```

---

## Canary 1 — Happy path with auto-merge

**Validates:** clean PR → CI passes → auto-merge → `status: landed`

**Setup:** auto-merge enabled (from prereq 2).

### Plan file

Create `plans/CANARY1_HAPPY.md`:

```markdown
---
title: Canary 1 — Happy Path
created: 2026-04-14
status: active
---

# Plan: Canary 1 — Happy Path

## Overview
Trivial 1-phase plan to validate the full PR mode + CI flow.

## Progress Tracker
| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 -- Add canary file | ⬜ | | Trivial |

## Phase 1 -- Add canary file

### Goal
Create a single file.

### Work Items
- [ ] Create `canary/c1.txt` containing "canary 1 — happy path"

### Acceptance Criteria
- [ ] File exists with the expected content
- [ ] File committed in worktree

### Dependencies
None.
```

### Run

I'll set up the worktree and dispatch agents. After the impl + verify
complete, I'll do the rebase + push + PR creation. Then we wait for CI.

### Expected sequence
1. Worktree created at `/tmp/zskills-pr-canary1-happy`
2. Branch `feat/canary1-happy`
3. 1 commit on branch
4. Push to dev
5. PR created (PR #N on zskills-dev)
6. CI starts (test.yml runs)
7. CI passes (~30s)
8. `gh pr merge --auto --squash` requested
9. Auto-merge fires → PR merges into main
10. `.landed` marker upgraded to `status: landed`
11. `land-phase.sh` removes the worktree

### Success criteria
- [ ] PR shown as MERGED on GitHub
- [ ] `.landed` shows `status: landed`, `ci: pass`, `pr_state: MERGED`
- [ ] Worktree removed
- [ ] Local main updated when you `git pull dev main`

### Cleanup
None — auto-merged.

---

## Canary 2 — Auto-merge disabled (fallback to pr-ready)

**Validates:** auto-merge unavailable → `status: pr-ready` (PR stays open)

**Setup:** disable auto-merge in dev settings before this canary, re-enable after.

### Plan
Same trivial structure as Canary 1, file is `canary/c2.txt`.

### Expected sequence
Same as Canary 1 through step 8, then:
8. `gh pr merge --auto --squash` returns error (suppressed with `|| true`)
9. PR stays OPEN
10. `.landed` marker shows `status: pr-ready`, `pr_state: OPEN`

### Success criteria
- [ ] PR shown as OPEN on GitHub
- [ ] `.landed` shows `status: pr-ready`, `ci: pass`, `pr_state: OPEN`
- [ ] Worktree NOT removed (pr-ready is terminal but not landed)

### Cleanup
- Close PR with comment
- Delete remote branch
- `git worktree remove --force` the worktree
- Re-enable auto-merge in dev settings

---

## Canary 3 — CI fails, fix cycle catches it

**Validates:** CI fails → fix agent reads logs → fixes → re-push → CI passes

**Setup:** auto-merge enabled. `ci.max_fix_attempts: 2` (default).

### Plan
Plan creates `canary/c3-test.sh` with a deliberate test failure.
The test will fail in CI but local /run-plan verification doesn't run it
(it's not part of `tests/test-hooks.sh`).

To make CI fail: append a step to `.github/workflows/test.yml` that runs
`canary/c3-test.sh` if it exists. Or — simpler — make the canary test
modify a hook file in a way that breaks an existing test.

**Easier approach:** the plan creates a file that FAILS bash syntax check,
which the CI workflow already runs (`bash -n hooks/*.sh`). Specifically:
the plan creates `hooks/canary-bad.sh` with broken syntax. The CI's
"Bash syntax check" step will fail.

The fix agent reads the CI log, sees the syntax error, fixes the file,
pushes. CI re-runs and passes.

### Plan file

```markdown
---
title: Canary 3 — Fix Cycle
---

# Plan: Canary 3 — Fix Cycle

## Phase 1 — Create file with fixable bug
- [ ] Create `hooks/canary-bad.sh` with: `#!/bin/bash\nif then echo "bad"\n`
- [ ] (Deliberate syntax error — missing condition between `if` and `then`)
- [ ] Note: CI's bash -n check will catch this. Fix agent should fix to:
      `#!/bin/bash\necho "fixed"\n`
```

### Expected sequence
1-7. Same as Canary 1
8. CI fails on bash syntax check
9. Fix cycle triggered: `gh api comments` posts initial comment
10. Fix agent reads `gh run view --log-failed`
11. Fix agent rewrites `hooks/canary-bad.sh` to valid bash
12. Push (auto-updates PR, re-triggers CI)
13. CI re-runs (~30s)
14. CI passes
15. Comment updated to "CI Passed after fix attempt 1"
16. Auto-merge → `status: landed`

### Success criteria
- [ ] PR shows 2+ commits (original + fix)
- [ ] PR has comment showing fix attempt + final status
- [ ] PR shown as MERGED
- [ ] `.landed` shows `status: landed`, `ci: pass`

### Cleanup
None — auto-merged.

---

## Canary 4 — CI fails permanently, exhaust attempts

**Validates:** fix cycle exhausts → `status: pr-ci-failing`

**Setup:** auto-merge enabled. Set `ci.max_fix_attempts: 1` in config to
keep the canary fast (only 1 fix attempt instead of 2).

### Plan
Plan creates a test that's deliberately impossible to fix without weakening
it. The fix agent's instructions say "do not weaken tests" — so it should
report inability to fix.

```markdown
## Phase 1 — Create unfixable test
- [ ] Create `tests/canary-unfixable.sh` with content:
      ```
      #!/bin/bash
      echo "FAIL: impossible assertion"
      [ "PASS" = "FAIL" ] || exit 1
      ```
- [ ] Add a CI step that runs this script (or modify CI workflow)
```

Actually — simpler. Use an environment-dependent failure. The plan creates
a test that requires a tool that exists locally but not in CI's ubuntu image.

Even simpler: plan deliberately appends to `tests/test-hooks.sh` something
that always fails AND can't be fixed without weakening:

```bash
# In test-hooks.sh, append:
fail "Canary 4 assertion that cannot be fixed without weakening"
```

The fix agent's only options are:
- Weaken the test (forbidden)
- Remove the test (forbidden — same as weakening)
- → It should report inability to fix and stop.

After fix attempt fails, /run-plan exhausts attempts, writes `pr-ci-failing`.

### Expected sequence
1-8. Same through CI failure
9. Fix attempt 1: agent reads logs, reports cannot fix without weakening
10. Push (no fix, but loop continues per skill text)
11. CI fails again (same error)
12. Attempts exhausted (1 max)
13. Final comment: "CI Fix Exhausted"
14. `.landed` marker shows `status: pr-ci-failing`
15. PR stays open

### Success criteria
- [ ] PR open with failing CI checks
- [ ] PR has "CI Fix Exhausted" comment
- [ ] `.landed` shows `status: pr-ci-failing`, `ci: fail`
- [ ] Worktree NOT removed (failed state is terminal but not landed)

### Cleanup
- Close PR with "canary complete" comment
- Delete remote branch
- Force-remove worktree
- Restore `ci.max_fix_attempts` to default (2)

---

## Canary 5 — ci.auto_fix: false (skip CI entirely)

**Validates:** `ci.auto_fix: false` → CI polling skipped → `status: pr-ready`

**Setup:** Set `ci.auto_fix: false` in `.claude/zskills-config.json` before
this canary. Restore after.

### Plan
Trivial 1-phase plan, file is `canary/c5.txt`.

### Expected sequence
1-5. Same through PR creation
6. CI re-read shows `auto_fix: false`
7. Polling skipped: `CI_STATUS="skipped"`
8. Auto-merge requested (it's a CI-skipped PR, auto-merge still applies)
9. If auto-merge succeeds: `status: landed`
   Otherwise: `status: pr-ready`

### Success criteria
- [ ] `.landed` shows `ci: skipped`
- [ ] Final status reflects auto-merge availability

### Cleanup
- Restore `ci.auto_fix: true` in config
- Close PR if not merged
- Clean up worktree

---

## Summary Table

| # | Tests | Auto-merge | Expected status |
|---|-------|------------|-----------------|
| 1 | Happy path with CI | ON | `landed` |
| 2 | Happy path no auto-merge | OFF | `pr-ready` |
| 3 | Fix cycle (CI fails, fixable) | ON | `landed` |
| 4 | Fix exhausted (CI fails, unfixable) | ON | `pr-ci-failing` |
| 5 | Skip CI (auto_fix: false) | ON | `landed` or `pr-ready` |

After all 5 pass, Phase 3b-iii is fully validated and we move to Phase 4.
