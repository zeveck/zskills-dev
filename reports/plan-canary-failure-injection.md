# Plan Report — Canary Failure Injection

## Phase — 4 block-agents.sh reproducers

**Plan:** `plans/CANARY_FAILURE_INJECTION.md`
**Status:** Completed (verified), pending PR landing
**Worktree:** `/tmp/zskills-pr-canary-failure-injection`
**Branch:** `feat/canary-failure-injection`
**Commits:** `2eba026` (impl + tests + fixtures), `dc566ce` (tracker 🟡)

### Work Items

| # | Item | Status | Commit |
|---|------|--------|--------|
| 1 | `section "block-agents: family filter rejects synthetic (1 case)"` | Done | `2eba026` |
| 2 | `section "block-agents: ordinal comparison (6 cases)"` — haiku/sonnet/opus × min/dispatch | Done | `2eba026` |
| 3 | `section "block-agents: unknown family passes through (1 case)"` | Done | `2eba026` |
| 4 | `section "block-agents: auto fallback to Sonnet (1 case)"` — locks in CURRENT behavior | Done | `2eba026` |
| 5 | `section "block-agents: auto success path (2 cases)"` | Done | `2eba026` |
| 6 | `section "block-agents: min_model not configured (1 case)"` | Done | `2eba026` |
| 7 | `tests/fixtures/canary/transcript-synthetic.jsonl` (Opus + `<synthetic>`) | Done | `2eba026` |
| 8 | `tests/fixtures/canary/transcript-opus.jsonl` (Opus only) | Done | `2eba026` |

### Verification

- `/verify-changes worktree` — **PASS**. Scope Assessment clean.
- Canary suite: `Canary failure-injection: 53 passed, 0 failed` (baseline 41 + 12 new).
- Full aggregator: `Overall: 288/288 passed, 0 failed` (baseline 276 + 12 new).
- CWD-robust (scaffold fix from Phase 3 confirmed working).
- Hygiene: `.worktreepurpose` / `.zskills-tracked` untracked; only the 3 in-scope paths staged.

### Acceptance Criteria

- [x] 6 sections present, 12 tests total.
- [x] Each test overrides `REPO_ROOT` per-test — never reads live canary config.
- [x] 2 transcript fixtures committed with correct content.
- [x] Auto Sonnet-fallback test locks in CURRENT behavior (not a prescription).
- [x] `bash tests/test-canary-failures.sh` → 53 passed, 0 failed.
- [x] `bash tests/run-all.sh` → 288/288.

### Deviations from Plan

Verifier noted: plan's inline AC prose at line 370 of the verbatim phase text says "52 tests passing (40 + 12)". The actual pre-Phase-4 canary count was 41 (Phase 2 added a +1 guard test). 41 + 12 = 53, which matches the parent's primary AC and the suite output. Plan prose drift, not a Phase 4 defect; noted for downstream phases that cite cumulative counts.

Cumulative plan-wide count adjustment (running total):
- Phase 1: 18
- Phase 2: 27 (9 + array-drift guard pass)
- Phase 3: 40
- Phase 4: 52 → **53**
- Final expected after Phase 5: plan says 78/68; actual will be 79/69 (+1 from Phase 2's guard, still tracking).

---

## Phase — 3 post-run-invariants.sh reproducers

**Plan:** `plans/CANARY_FAILURE_INJECTION.md`
**Status:** Completed (verified), pending PR landing
**Worktree:** `/tmp/zskills-pr-canary-failure-injection`
**Branch:** `feat/canary-failure-injection`
**Commits:** `a922e27` (impl + tests + scaffold fix), `f9164f1` (tracker 🟡)

### Work Items

| # | Item | Status | Commit |
|---|------|--------|--------|
| 1 | Section `Invariant #1: worktree on disk (1 case)` | Done | `a922e27` |
| 2 | Section `Invariant #2: worktree in registry (1 case)` | Done | `a922e27` |
| 3 | Section `Invariant #3: local branch after landed (2 cases)` — fire + pr-ready negative | Done | `a922e27` |
| 4 | Section `Invariant #4: remote branch after landed (2 cases)` | Done | `a922e27` |
| 5 | Section `Invariant #5: plan report missing (2 cases)` | Done | `a922e27` |
| 6 | Section `Invariant #6: in-progress sentinel in plan (2 cases)` — uses committed fixtures | Done | `a922e27` |
| 7 | Section `Invariant #7: main divergence WARN (3 cases)` — no-div / fetch-fail / squash-merge-div | Done | `a922e27` |
| 8 | `tests/fixtures/canary/plan-with-sentinel.md` (contains 🟡 in a tracker row) | Done | `a922e27` |
| 9 | `tests/fixtures/canary/plan-without-sentinel.md` (clean plan, no sentinel) | Done | `a922e27` |
| 10 | Scaffold robustness fix: `REPO_ROOT` derives from script path, not CWD | Done | `a922e27` |

### Verification

- `/verify-changes worktree` — **PASS**. Scope Assessment clean.
- Canary suite: `Canary failure-injection: 41 passed, 0 failed` (baseline 28 + 13 new).
- Full aggregator: `Overall: 276/276 passed, 0 failed` (baseline 263 + 13 new).
- Verified suite passes via BOTH `(cd worktree && bash tests/run-all.sh)` AND `bash /abs/worktree/tests/run-all.sh` from an arbitrary CWD.
- Hygiene: `.worktreepurpose` / `.zskills-tracked` untracked; only the three in-scope paths staged.

### Drive-by fixes surfaced during review

1. **Scaffold CWD-sensitivity bug (orchestrator-caught during spot-check):** the Phase 1 scaffold derived `REPO_ROOT` via `git rev-parse --show-toplevel`, which follows CWD rather than the script's own location. When the aggregator was invoked with the test script's absolute path from a different repo's CWD, `REPO_ROOT` resolved to the wrong place and Phase 3's fixture paths failed to resolve. Fixed by switching to script-path derivation (mirrors `tests/run-all.sh`'s own pattern).
2. **Verifier-caught `|| true` + `2>/dev/null` pair** in the impl agent's Invariant #4 fixture (a dead branch-delete whose rc was ignored and stderr suppressed — violates CLAUDE.md). Verifier replaced with a comment explaining the setup intent. Canary count unchanged.

### Acceptance Criteria

- [x] 7 invariant sections present, 13 tests total.
- [x] #1-#6 assert rc=1 (FAIL); #7 cases assert rc=0 (WARN).
- [x] Two fixture files committed with descriptive header comments.
- [x] No literal 🟡 character in `tests/test-canary-failures.sh` (only in `plan-with-sentinel.md`).
- [x] `bash tests/test-canary-failures.sh` → 41 passed, 0 failed.
- [x] `bash tests/run-all.sh` → 276/276 passed, 0 failed.
- [x] Suite CWD-robust.

### Deviations from Plan

None on the primary scope. The two drive-by fixes (scaffold CWD, impl `|| true`) are documented above — both strictly improve code quality without altering test behavior or expectations.

---

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
