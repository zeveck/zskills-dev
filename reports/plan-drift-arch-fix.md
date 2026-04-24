# Plan Report — Drift-Arch Fix

## Phase — 2 Update /update-zskills: drop migrated fills, add --rerender, fix settings.json clobber

**Plan:** plans/DRIFT_ARCH_FIX.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-drift-arch-fix (feat/drift-arch-fix)
**Commit:** 8ce91de

### Work Items
| # | Item | Status | Commit |
|---|------|--------|--------|
| 2.1 | Remove placeholder-fill for migrated keys in Step C; keep E2E/BUILD fills | Done | 8ce91de |
| 2.2 | Update placeholder-mapping table (remove migrated rows, annotate runtime-read fields) | Done | 8ce91de |
| 2.3 | Add `### Step D — --rerender` with boundary algorithm + exit codes | Done | 8ce91de |
| 2.4 | Integration tests for `--rerender` (6 blocks, 16 assertions) | Done | 8ce91de |
| 2.5 | Rewrite Step C as agent-driven Read+Edit merge with canonical triples table | Done | 8ce91de |
| 2.6 | `### Step C.9 — Hook renames` subsection with initially-empty migration table | Done | 8ce91de |
| 2.7 | 32 structural conformance assertions for Step C / C.9 / D contracts | Done | 8ce91de |

### Verification
- Test suite: PASSED (801/801; baseline 747/747; +54 new assertions, zero regressions).
- Byte-identical mirror: `diff -q skills/update-zskills/SKILL.md .claude/skills/update-zskills/SKILL.md` clean.
- Canonical triples table: 5 rows (3 PreToolUse Bash/Bash/Agent + 2 PostToolUse Edit/Write) verified.
- Step D boundary algorithm: 6 concrete steps with exit codes 0/1/2 + verbatim stderr prompt + idempotency via byte-compare-skip-write.
- Step C.9 migration table: initially empty, row format documented, runs before main merge loop.
- All Phase 2 acceptance criteria met.

### Notes
- **Plan-prose inconsistency flagged (non-blocking)**: WI 2.4 Test 1 says "Happy path: stale CLAUDE.md + updated config → new CLAUDE.md contains current config values (rc=0)", but the Design & Constraints' simplified byte-compare algorithm (intentional round-2 change removing the hand-wavy "normalize" step) makes rc=2 + `CLAUDE.md.new` the correct behavior on any drift. Tests correctly follow the algorithm; plan prose worth a small doc-only tidy — filed as non-blocking.
- **`## Agent Rules` anchor absent from `CLAUDE_TEMPLATE.md`**: it's added by Step B's rules-append path when merging rules into an existing CLAUDE.md. Users who never went through that path get rc=2 "missing demarcation" on first `--rerender` invocation — correct per spec (user must add the heading or re-run `/update-zskills` non-`--rerender` first).

### Risks
None identified. Phase closes the `/update-zskills` Step C full-overwrite bug that was silently clobbering user-added PreToolUse entries on every install.

### Next
Phase 3 — PostToolUse drift-warn hook (`warn-config-drift.sh`) + wire via Phase 2's Step C merge (which already knows the two new triples from Phase 2's canonical table).

---

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
