# Plan Report — Skill-File Drift Fix

## Phase — 2 Migrate Hardcoded Literals

**Plan:** plans/SKILL_FILE_DRIFT_FIX.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-skill-file-drift-fix
**Branch:** feat/skill-file-drift-fix
**Commit:** ec6ec71

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 2.1 | Pre-migration enumeration | Done | 23 source skill files identified across 6 categories; INJECTED-BLOCKQUOTE singled out at run-plan/SKILL.md:898-930 |
| 2.2 | Per-fence migration | Done | Helper-source preamble added per fence; 5 fixture literals + INJECTED-BLOCKQUOTE migrated; co_author hardcoded defaults dropped at commit/SKILL.md, quickfix/SKILL.md |
| 2.3 | Mirror sync | Done | `find skills -name '*.md'` diff loop empty (byte-identical) |
| 2.4 | Categorized re-audit | Done | Zero EXEC-FENCE drift remains; 17 hits remain (all PROHIBITION/MIGRATION-TOOL/PROSE-DESCRIPTIVE/fallback) |
| 2.5 | End-to-end fixture test | Done | tests/test-skill-file-drift.sh (12 cases) exercises migrated fence with timezone:Europe/London + testing.full_cmd:FIXTURE_FULL; resolved values flow through |

### Verification

- **Test suite:** PASSED (1237 baseline → 1249 after Phase 2, +12 fixture cases, 0 failures)
- **Audit grep classifications:** TZ 0/EXEC + 5/PROSE-DESCRIPTIVE; test:all 0/EXEC + 9/PROHIBITION-MIGRATION-TOOL-PROSE-DESCRIPTIVE; npm start 0/EXEC + 3/PROHIBITION-MIGRATION-TOOL; .test-results.txt all in `${TEST_OUTPUT_FILE:-.test-results.txt}` form or out-of-scope contexts
- **INJECTED-BLOCKQUOTE structural AC:** PASS (no raw `npm start`/`npm run test:all`/`.test-results.txt`; `$DEV_SERVER_CMD`/`$TEST_OUTPUT_FILE`/`$FULL_TEST_CMD` all present)
- **Mirror parity:** clean
- **Substitution discipline strengthening:** `skills/run-plan/SKILL.md:181` now enumerates all 3 vars (`$FULL_TEST_CMD`, `$DEV_SERVER_CMD`, `$TEST_OUTPUT_FILE`)

### Test-harness collateral changes (verified contractually equivalent)

- `tests/test-skill-conformance.sh` "run-plan test capture redirect" — literal-match for `.test-results.txt"` updated to regex matching the migrated `${TEST_OUTPUT_FILE:-.test-results.txt}` pattern. Same intent (capture-not-pipe contract).
- `tests/test-quickfix.sh` case 10 — was asserting `$CO_AUTHOR` + `BASH_REMATCH` in skill body; now asserts `$COMMIT_CO_AUTHOR` + helper-source line. The CO_AUTHOR resolution logic moved to the helper by design; the assertion follows.
- `tests/test-quickfix.sh` extracted-script harness — added `: "${CLAUDE_PROJECT_DIR:=$(pwd)}"` so the helper's mandatory env var is satisfied inside the synthetic fixture (which `cd`s into `$FIX` before running the extracted script).

### Acceptance Criteria — all met

| AC | Verdict |
|----|---------|
| Zero EXEC-FENCE for `TZ=America/New_York` | PASS |
| Zero EXEC-FENCE for `npm run test:all` | PASS |
| Zero EXEC-FENCE for `npm start` | PASS |
| Mirror parity (skills ↔ .claude/skills) | PASS |
| Full test suite | PASS (1249/1249) |
| Synthetic-fixture test (London config flows through) | PASS |
| INJECTED-BLOCKQUOTE structural AC | PASS |

### Plan-Text Drift

- `bullet=Categories field=tz-count plan=60 actual=60` — matches once you separate EXEC vs PROSE-DESCRIPTIVE
- `bullet=Categories field=test-results-count plan=16 actual=13-in-scope` — plan undercount of in-scope migrations vs total raw-audit hits; informational
- `bullet=Categories field=npm-start-count plan=2-EXEC+1-PROSE actual=3-EXEC+1-PROSE+1-injected` — `manual-testing/SKILL.md:19` was a third EXEC-FENCE site not enumerated in plan; informational

### User Sign-off

Phase 2 produces no UI changes — no sign-off needed.

## Phase — 1 Canonical Config-Resolution Helper Script

**Plan:** plans/SKILL_FILE_DRIFT_FIX.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-skill-file-drift-fix
**Branch:** feat/skill-file-drift-fix
**Commit:** d2b05c3

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1.1 | Author `zskills-resolve-config.sh` (source + mirror) | Done | 64 lines; resolves UNIT_TEST_CMD, FULL_TEST_CMD, TIMEZONE, DEV_SERVER_CMD, TEST_OUTPUT_FILE, COMMIT_CO_AUTHOR via BASH_REMATCH; CLAUDE_PROJECT_DIR fail-loud; idempotent; no jq; _ZSK_ internals unset; coexists w/ zskills-stub-lib.sh |
| 1.2 | commit.co_author schema + install (verification-only) | Done | Schema default at config/zskills-config.schema.json:52; backfill at skills/update-zskills/SKILL.md:220-235 — both pre-exist (refine-1 R1.7). Phase 1 added 5 backfill regression tests in test-update-zskills-rerender.sh. |
| 1.3 | Author `references/canonical-config-prelude.md` | Done | 216 lines; 7 sections (sourcing pattern, fallback semantics, mode files, subagent dispatch, shell-state scope, heredoc-form, allowlist marker) |

### Verification

- **Test suite:** PASSED (1213 baseline → 1237 after Phase 1, +24 new tests, 0 failures)
- **Hard rules:** zero `jq` invocations; all 6 vars empty-init-guarded; CLAUDE_PROJECT_DIR fail-loud; mirror byte-identical
- **Coexistence with `zskills-stub-lib.sh`:** confirmed (zero shared variable assignments; domain-disjoint)
- **PLAN-TEXT-DRIFT detected:** baseline test count was 1212 in plan; current main is 1213 (+1 = 0.08% drift; within Phase 3.5 auto-correct band). Implementer self-flagged.

### Acceptance Criteria — all 7 met

| AC | Test | Verdict |
|----|------|---------|
| Synthetic-fixture (London/FIXTURE_CMD/Test Author + 3 empties) | test-zskills-resolve-config.sh Test 1a-f | PASS |
| Idempotency | Test 2 | PASS |
| Empty-config | Test 3a-b | PASS |
| Malformed-config | Test 4a-b | PASS |
| CLAUDE_PROJECT_DIR-switching (London ↔ Tokyo) | Test 5a-b | PASS |
| Prelude doc + 7 sections | Test 6a-c | PASS |
| Install integrity (mirror-skill.sh + byte-identical) | Test 7a-c | PASS |

### Plan-Text Drift

- `bullet=AC8 field=baseline-test-count plan=1212 actual=1213` — Phase 3.5 auto-correct candidate (small drift; informational). Plan AC at line ~244 says "Refine-1 verified count is **1212**"; current main `59cbb2c` (post-PR-#119/#120/#121) is 1213. Worth updating in a follow-up but non-blocking.

### User Sign-off

Phase 1 produces no UI changes — no sign-off needed.

### Notes

Phase 0 (staleness gate) was run inline as orchestrator preflight; all 5 checks passed against main `59cbb2c`. No code changes for Phase 0; tracker mark only (commit `5b84112`).
