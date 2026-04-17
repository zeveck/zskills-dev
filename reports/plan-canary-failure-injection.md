# Plan Report — Canary Failure Injection

## Phase — 2 land-phase.sh reproducers

**Plan:** `plans/CANARY_FAILURE_INJECTION.md`
**Status:** Completed (verified), pending PR landing
**Worktree:** `/tmp/zskills-pr-canary-failure-injection`
**Branch:** `feat/canary-failure-injection`
**Commits:** `e78a224` (impl + tests), `527c301` (tracker 🟡)

### Work Items

| # | Item | Status | Commit |
|---|------|--------|--------|
| 1 | Section `land-phase.sh: dirty worktree refused (1 case)` | Done | `e78a224` |
| 2 | Section `land-phase.sh: tracked ephemeral rejected (4 cases)` + array-drift guard | Done | `e78a224` |
| 3 | Section `land-phase.sh: ls-remote exit code handling (3 cases)` — rc=0/2/128 | Done | `e78a224` |
| 4 | Section `land-phase.sh: /tmp test-output dir cleanup (1 case)` — locks in 66d9138 | Done | `e78a224` |

### Verification

- `/verify-changes worktree` — **PASS**. Scope Assessment clean, all cells "Yes".
- Canary suite: `Canary failure-injection: 28 passed, 0 failed` (up from 18 post-Phase-1).
- Full aggregator: `Overall: 263/263 passed, 0 failed` (baseline 253 + 10 new).
- No regressions vs baseline.
- Hygiene: `.worktreepurpose`/`.zskills-tracked`/`.landed` untracked; `/tmp/zskills-tests/...` outside worktree; only `tests/test-canary-failures.sh` modified.

### Acceptance Criteria

- [x] Section "dirty worktree" passes 1 test.
- [x] Section "tracked ephemeral" passes 4 tests + array-drift guard.
- [x] Section "ls-remote" passes 3 tests (rc=0/2/128 distinction).
- [x] Section "/tmp cleanup" passes 1 test.
- [x] `bash tests/test-canary-failures.sh` → `28 passed, 0 failed`.
- [x] `bash tests/run-all.sh` → `Overall: 263/263 passed, 0 failed`.

### Deviations from Plan

Minor +1 count: the plan's headline count is "9 tests" but the AC wording
also lists the array-drift guard as a distinct assertion ("...AND the
array-drift guard passes"). The impl agent implemented the guard as its
own `pass` call so drift is visible in test output. Net: 10 new passing
assertions instead of 9. Total canary count: 28.

Cumulative plan-wide count adjustment:
- Phase 2 internal: 9 → 10
- Final expected (installed-copy present): 78 → 79
- Final expected (installed-copy skipped): 68 → 69

---

## Phase — 1 Scaffold + block-unsafe-generic.sh stash reproducers

**Plan:** `plans/CANARY_FAILURE_INJECTION.md`
**Status:** Completed (verified), pending PR landing
**Worktree:** `/tmp/zskills-pr-canary-failure-injection`
**Branch:** `feat/canary-failure-injection`
**Commits:** `cace895` (impl + tests), `5da8705` (tracker 🟡)

### Work Items

| # | Item | Status | Commit |
|---|------|--------|--------|
| 1 | `tests/test-canary-failures.sh` scaffold (shebang, helpers, trap cleanup, summary footer, executable) | Done | `cace895` |
| 2 | `tests/fixtures/canary/.gitkeep` (empty dir tracked) | Done | `cace895` |
| 3 | `tests/run-all.sh` integration — 1 new `run_suite` line after `test-scope-halt.sh` | Done | `cace895` |
| 4 | `section "Stash writes denied (6 cases)"` — bare / -u / save / push / drop / clear | Done | `cace895` |
| 5 | `section "Stash reads allowed (7 cases)"` — apply / list / show / pop / create / store / branch | Done | `cace895` |
| 6 | `section "Stash overmatch prevention (5 cases)"` — commit msg / echo / grep / printf / heredoc | Done | `cace895` |

### Verification

- `/verify-changes worktree` — **PASS** (fresh subagent, independent context from impl).
- Scope Assessment — all rows `Yes`, no violations.
- Worktree test suite: `Canary failure-injection: 18 passed, 0 failed` (exit 0).
- Full aggregator: `Overall: 253/253 passed, 0 failed` (baseline was 235; +18 from this phase as expected).
- Hygiene: `.worktreepurpose`, `.zskills-tracked`, `.landed` all untracked and not staged. Only the three in-scope paths in the commit.
- No regressions vs `.test-baseline.txt`.

### Acceptance Criteria

- [x] `tests/test-canary-failures.sh` exists and is executable.
- [x] `tests/fixtures/canary/` directory exists with `.gitkeep`.
- [x] `tests/run-all.sh` diff shows exactly one new `run_suite` line.
- [x] `bash tests/test-canary-failures.sh` reports `18 passed, 0 failed`.
- [x] `bash tests/run-all.sh` exits 0 and includes the new suite in its output.

### Deviations from Plan

None. Scaffold copied verbatim (`set -u` not `set -eo pipefail`, Python JSON escape, trap-based `FIXTURE_DIRS` cleanup with unset-array guard). 6+7+5 = 18 tests match the plan tables exactly. All tests passed on first run; no retries needed.
