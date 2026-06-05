# Plan Report — Test Suite Parallelization & Isolation

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
