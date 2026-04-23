# Plan Report — Drift-Arch Fix

## Phase — 1 Migrate CODE consumers to runtime config read

**Plan:** plans/DRIFT_ARCH_FIX.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-drift-arch-fix (feat/drift-arch-fix)
**Commit:** 3b3fc88

### Work Items
| # | Item | Status | Commit |
|---|------|--------|--------|
| 1.1 | Migrate `hooks/block-unsafe-project.sh.template` (runtime-read block, empty-pattern guard, dead-code cleanup) | Done | 3b3fc88 |
| 1.2 | Mirror into `.claude/hooks/block-unsafe-project.sh` (byte-identical) | Done | 3b3fc88 |
| 1.3 | Migrate `scripts/port.sh` (runtime read of `dev_server.main_repo_path`) | Done | 3b3fc88 |
| 1.4 | Migrate `scripts/test-all.sh` (runtime reads, keep E2E/BUILD placeholders) | Done | 3b3fc88 |
| 1.5 | 7 runtime-config-read tests in `tests/test-hooks.sh` | Done | 3b3fc88 |
| 1.6 | Drift-regression grep test (deny-list + allow-list + template cleanliness) | Done | 3b3fc88 |

### Verification
- Test suite: PASSED (747/747; baseline was 733/733; +14 new, zero regressions)
- Drift-regression grep: zero matches for migrated placeholders in installed hook / `scripts/port.sh` / `scripts/test-all.sh`; `{{E2E_TEST_CMD}}` and `{{BUILD_TEST_CMD}}` correctly preserved in `test-all.sh`
- Mirror parity: `diff -q` between source template and installed hook reports no differences
- `_zsk_regex_escape` correctness: traced `test(abc)` → `test\(abc\)`; implementer's fixes for `?`, `{`, `}`, `[`, `]` verified correct
- Acceptance criteria: all 5 present and passing

### Notes
- Plan text contained a genuine spec bug in the `_zsk_regex_escape` idiom: `${s//?/\\?}` used the `?` glob-wildcard (which matches every character, not the literal `?`), and `${s//\}/\\}}` closed the parameter expansion early. Implementer fixed with `${s//[?]/\\?}` and `${s//\}/\\\}}` (plus bracket-class escape fixes), inline-documented. Commit message flags this explicitly.
- Test-fixture setups in `test-hooks.sh` updated from sed-placeholder to config-file-write approach (since placeholders are now runtime-read). Uses `python3` merge for partial-config cases — python3 is already assumed available by other tests in the suite.

### Risks
None identified. Phase delivers architectural guarantee: drift is impossible for the migrated CODE consumers going forward.

### Next
Phase 2 — Update `/update-zskills` (drop migrated fills, add `--rerender`, fix settings.json clobber). Scheduled via one-shot cron after this phase's PR push.
