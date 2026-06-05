# Plan Report — Test Suite Parallelization & Isolation

## Phase — 2 Targeted isolation

**Plan:** docs/plans/TEST_SUITE_PARALLELIZATION_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-test-suite-parallelization-plan (branch feat/test-suite-parallelization-plan)
**Commits:** 3a2de15 (isolation), + tracker/report

### Work Items
| # | Item | Status | Commit |
|---|------|--------|--------|
| 1 | `test-apply-preset.sh` → per-suite `$(mktemp -d)` scratch + EXIT-trap | Done | 3a2de15 |
| 2 | `test-update-zskills-paths-migration.sh` → `TEST_OUT=$(mktemp -d)` + EXIT-trap | Done | 3a2de15 |
| 3 | Confirm per-suite TMPDIR injection is Phase-4's responsibility | Confirmed (not built) | — |

### Verification (independent verifier agent: VERDICT PASS)
- **Isolation-only:** assertion call-site counts byte-identical to HEAD per file (apply-preset pass 18/fail 17; migration pass 75/fail 103). No assertion added/removed/changed.
- **Counts unchanged:** apply-preset 18/0; paths-migration 74/0.
- **Concurrency AC:** two concurrent copies of EACH suite with distinct injected TMPDIR → all four runs 0-failed, no cross-collision (proves `mktemp -d` honors `$TMPDIR`).
- **No leftover collision paths:** `/tmp/zskills-apply-test` and `/tmp/zskills-tests/` literals gone; no `$$`-based scheme introduced.
- **Gate B — `bash tests/run-all.sh`:** **Overall 7576/7576, 0 failed** (unchanged from post-1b — isolation-only).

### Scope
2 files: `tests/test-apply-preset.sh`, `tests/test-update-zskills-paths-migration.sh`.

## Phase — 1b Relocate test-hooks sections into independent sub-suites

**Plan:** docs/plans/TEST_SUITE_PARALLELIZATION_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-test-suite-parallelization-plan (branch feat/test-suite-parallelization-plan)
**Commits:** 08d1f16 (split), 6c35ad6 (tracker)

### Work Items
| # | Item | Status | Commit |
|---|------|--------|--------|
| 1 | Split monolith into 8 sub-suites along `=== … ===` section markers | Done | 08d1f16 |
| 2 | Each sub-suite sources `hooks-harness.sh`, one canonical Results line | Done | 08d1f16 |
| 3 | run-all.sh: remove test-hooks.sh, register 8 sub-suites (literal registry) | Done | 08d1f16 |
| 4 | Repoint conformance rows A/B/C/E1/E2 (row D done in 1a) | Done | 08d1f16 |
| 5 | Self-registration choice (a): none → Σ stays exactly 2384 | Done | 08d1f16 |

### Verification (independent verifier agent: VERDICT PASS)
- **Gate A — per-sub-suite VECTOR:** block-unsafe=294, bypass-generic=700, bypass-project=1109, main-protected=48, worktree-cd=25, agent=21, warn-drift=10, misc=177 → **Σ = 2384, 0 failed**. Each count verified individually (no compensated ±1).
- **MOVE-not-rewrite:** 377 == 377 pass/fail call-statements; `expect_*` counts identical old-vs-new; 44 == 44 section markers; `run_main_protected_test` relocation byte-identical (47 lines).
- **Gate B — `bash tests/run-all.sh`:** **Overall 7576/7576, 0 failed.** = Phase 0 baseline 7569 **+ 7 documented delta** (`test-suite-registry.sh` 15→22: now asserts the registration of 8 sub-suites instead of 1 monolith — *more* coverage, localized by per-suite diff; not a compensated swap).
- **Conformance:** 713/713 (rows A/B/C summed ≥2 across both bypass files, not weakened; E1→misc, E2→warn-drift; row D untouched).
- **`test-suite-registry.sh`:** 22/0 (repointed to enumerate the 8 sub-suites).
- **Arbitrary-cwd smoke:** bypass-project from `/tmp` → 1109/0 (PROJECT_HOOK absolutization holds).

### Scope
13 files: 8 new `tests/test-hooks-*.sh`; `tests/test-hooks.sh` deleted; `tests/run-all.sh`, `tests/lib/hooks-harness.sh`, `tests/test-skill-conformance.sh`, `tests/test-suite-registry.sh` modified.

### Notes
- A pre-existing `test-demo-sim.sh` ±1 count flake (47↔48) was observed across the two full-suite runs — unrelated to the hooks split, net-zero, not introduced here.
- `test-hooks-misc.sh` shows 4 land-phase.sh failures only when invoked from a non-repo-root cwd (pre-existing cwd-coupling in land-phase.sh itself, identical to the monolith's behavior); passes 177/177 from repo root, which is how run-all invokes it.

## Phase — 1a Extract the hooks-harness lib

**Plan:** docs/plans/TEST_SUITE_PARALLELIZATION_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-test-suite-parallelization-plan (branch feat/test-suite-parallelization-plan)
**Commits:** 88e83cf (extraction), d685466 (tracker)

### Work Items
| # | Item | Status | Commit |
|---|------|--------|--------|
| 1 | Account for external helper `tests/test-hooks-helpers.sh` (own it; ordering) | Done | 88e83cf |
| 2 | Factor shared preamble + project helpers into `tests/lib/hooks-harness.sh` | Done | 88e83cf |
| 3 | Own hook-path globals; **absolutize `PROJECT_HOOK`** to `$REPO_ROOT/...` | Done | 88e83cf |
| 4 | Verify against unchanged monolith: test-hooks.sh sources lib, 2384/0 | Done | 88e83cf |

### Verification
- **`bash tests/test-hooks.sh`:** `Results: 2384 passed, 0 failed (of 2384)`, rc=0 (== Phase 0 Gate A baseline). Independently re-run by the verifier agent.
- **`bash tests/run-all.sh` (attended gate OFF):** `Overall: 7569/7569 passed, 0 failed` (== Phase 0 Gate B baseline). Orchestrator-run count-conservation gate.
- **`bash tests/test-skill-conformance.sh`:** `Results: 713 passed, 0 failed (of 713)`.
- **Acceptance criteria:** all met. It is a pure helper-extraction MOVE — no test section relocated, every assertion preserved (verifier confirmed byte-identical `expect_*` call-site counts). New lib carries no self-registration and is not registered in run-all.sh. Single `setup_project_test_on_main` definition; correct `setup_project_test`-before-`_on_main` ordering.

### Scope
3 files: `tests/lib/hooks-harness.sh` (new, 228 lines), `tests/test-hooks.sh` (−180/+21), `tests/test-skill-conformance.sh` (assertion-D repoint).

### Plan drift noted (non-blocking — for Phase 1b awareness)
The plan filed the `make_branch_repo` conformance-grep repoint as **Phase 1b row D**, but `make_branch_repo` is one of the helpers that **moves in Phase 1a**. Moving it broke `test-skill-conformance.sh` assertion D (`^make_branch_repo()` in test-hooks.sh → found 0 → `Overall 7568/7569`), making Phase 1a's own "run-all Overall unchanged" AC unreachable. The orchestrator's full-suite gate caught it; a fix agent applied the plan's documented row-D fix (repoint assertion D to grep `tests/lib/hooks-harness.sh`) within Phase 1a. **Phase 1b's repoint table row D is therefore already satisfied** — Phase 1b should handle only rows A/B/C (bypass sections) + E1/E2 (fixtures), which move in 1b. Recommend `/refine-plan` move row D's note from 1b→1a at close-out (structural drift, beyond Phase 3.5's numeric auto-correct scope).

### Notes
- `origin/main` advanced to 5b63b82 (#1095 session-logging) during the implementer run; the branch is intentionally NOT rebased yet (per-phase count compared against the b567aba baseline). Rebase onto current origin/main happens at the final-phase landing.
