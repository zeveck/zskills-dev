# Plan Report — Seam Hardening (HIGH-priority skills)

## Phase 6b — work-on-plans: dispatch-loop seam + sandbox harness  ✅ Done (2026-06-01T11:16:18-04:00)

**Commit:** `9f8a3d1` on `feat/seam-hardening-high`
**Tests:** Overall 7017/7017 passed, 0 failed (baseline 6993 → +24).

- Added a strictly-gated `_ZSKILLS_TEST_HARNESS` seam on the Step-5 `/run-plan` dispatch directive in `work-on-plans/modes/execute.md` (+ entry unset-guard mirroring `do/SKILL.md`). **Production-safety verified independently:** flag-unset → seam inert, the `Skill: {…}` directive is unchanged (additive gate, not a replacement).
- Added `test-work-on-plans-dispatch-seam.sh` (24 tests) extracting the real dispatch loop: marker lifecycle, mode precedence (CLI>per-entry>default>phase), failure-arm stop + report, `continue`, sprint-completion + work-state→idle + exit code, arg-router rules 1-7 + exit-2. Mutation-proven (gate-inversion swallows injected failure).
- Version bump `2026.06.01+7a11d3` → `2026.06.01+a67fc0` + byte-identical mirror. (Drift: plan recipe's `skill-content-hash.sh <file>` is wrong — script takes a directory; impl corrected.)

**Verification:** independent verifier PASS — own flag-unset prod-safety test, recomputed hash matches, conformance/version-delta/mirror-parity green, scope clean (6 paths), Layer-3 exit 0. NOTE: 6 transient `test_zskills_monitor_dashboard_ui.sh` live-server flakes on first run (pass 239/239 isolated; cleared on re-run; unrelated to change set) — watch at PR-CI landing.


## Phase 6a — work-on-plans: de-hollow mutator tests (test-only)  ✅ Done (2026-06-01T10:15:53-04:00)

**Commit:** `ae98c7d` on `feat/seam-hardening-high`
**Tests:** Overall 6993/6993 passed, 0 failed (baseline 6992 → +1).

- Converted `test-work-on-plans.sh` from re-defined `skill_*` copies → extract-and-run the real `do_add`/`do_rank`/`do_remove`/`do_default` + `ensure_monitor_state` + `schedule_under_1h` heredocs from `subcommands/add-rank-remove.md` (via `extract_fence_between`; thin `do_*_at` adapters set $MONITOR_STATE + delegate).
- All 30 prior assertions preserved (append/insert/idempotent/digit-reject, rank, remove, default, #546 schedule_under_1h boundary, flock, mirror-parity); 0 re-defined `skill_*` remain.

**Verification:** independent verifier PASS — adapters confirmed thin delegators, mutation-proof (breaking real do_add append → 10 failures), scope clean (1 path), Layer-3 exit 0.


## Phase 5 — draft-plan + refine-plan: Phase-6/5 fence harnesses  ✅ Done (2026-06-01T09:34:37-04:00)

**Commit:** `5539a31` on `feat/seam-hardening-high`
**Tests:** Overall 6992/6992 passed, 0 failed (baseline 6962 → +30).

- Added `test-draft-plan-phase6-fences.sh` (extracts draft-plan Phase-6 commit fence [strip-indent=1] + land-pr-result-parse fence; OUTPUT_FILE remap, FILE_REL, ../* → exit 1, two-file-staged → exit 1, allow-list parse).
- Added `test-refine-plan.sh` (NEW — none existed) over refine-plan Phase-5 fences (commit FLUSH-LEFT strip-indent=0; shared `case "$SKILL"` subject; marker lifecycle) + the new arg-parser fence.
- **refine-plan SKILL.md edit:** isolated an extractable `## Argument parser` fence (behavior-preserving — verified vs all 6 Arguments Examples); version bumped `2026.05.31+65e420` → `2026.06.01+827d06`, byte-identical mirror.

**Verification:** independent verifier PASS — behavior-preservation analysis, recomputed version hash matches, conformance 2370/2370 + version-delta 12/12 + mirror-parity 57/57 green, mutation-proof, scope clean (5 paths), Layer-3 exit 0. (Drift: draft-plan plan-cited line ranges stale; tests grep landmarks.)


## Phase 4 — do/quickfix: real mechanics extract + de-hollow message asserts  ✅ Done (2026-06-01T08:39:07-04:00)

**Commit:** `b111d63` on `feat/seam-hardening-high`
**Tests:** Overall 6962/6962 passed, 0 failed (cases converted in place).

- Converted `test-do.sh` Case 6 (grep-only verdict-regex strings) → extract-and-run the real `/do` verdict parser (APPROVE / REVISE -- r / REJECT -- r / malformed).
- Deleted the hollow `*_SIM` heredocs (`test-quickfix.sh` Cases 47/48); replaced with the real WI 1.2 parser unset-guard + extract-and-run verdict regex + **per-skill divergent-string anchors**.
- Re-anchored message drift on genuinely-divergent strings (quickfix landing-config soft-redirect; ask-user self-name `/do` vs `/quickfix`; no-marker prose) — NOT the dead `--force`/`force` pair (retired #822). Message emission documented as model-layer.
- No circular table-harness; no SKILL.md edits (test-only / technique-A).

**Verification:** independent verifier PASS — all 6 anchors verified present-in-own/absent-in-sibling, mutation-proof on Case 6 + anchors, scope clean (2 paths), Layer-3 exit 0.


## Phase 3 — commit: arg-parser extract + caller-loop harness  ✅ Done (2026-06-01T07:52:13-04:00)

**Commit:** `a53e252` on `feat/seam-hardening-high`
**Tests:** Overall 6962/6962 passed, 0 failed (baseline 6935 → +27 net; removed static-grep test-commit.sh).

- Replaced 100%-static-grep `test-commit.sh` with `test-commit-parsing.sh` (extracts the real `commit/SKILL.md` arg-parser; pr/mid-string-pr/auto-strip/explicit-wins/cherry-pick-exit-1) + `test-commit-pr-caller-loop.sh` (`extract_sentinel_block` the `commit/modes/pr.md` BEGIN/END loop; drives STATUS×CI_STATUS → LAND_OUTCOME, fulfilled/requires lifecycle, --auto gate).
- Coverage-preservation audited: all 5 old test-commit.sh cases migrated/strengthened; `.landed` still covered by test-landed-schema.sh.
- **Drift recorded:** the arg-parser fences are column-0, not 3-space-indented as the plan said — test uses strip-indent=0 (correct). Non-numeric drift; plan text left as-is.

**Verification:** independent verifier PASS — mutation-proof, coverage audit, scope clean (4 paths), no SKILL.md edits, Layer-3 exit 0.


## Phase 2 — land-pr: extract Steps 6b/7b/7c fences  ✅ Done (2026-06-01T07:01:39-04:00)

**Commit:** `b4ad4c0` on `feat/seam-hardening-high`
**Tests:** Overall 6935/6935 passed, 0 failed (baseline 6903 → +32).

- Converted `test-land-pr-auto-rebase-behind.sh` to extract-and-run the real **Step 6b** fence; preserved 10 cases + added the **#875 UNKNOWN-re-poll case** (closing the live `UNKNOWN→blocked` hollow-green).
- Converted `test-land-pr-post-merge-ff.sh` to extract-and-run the real **Step 7b** fence (real git fixtures; cases a–d).
- Added `test-land-pr-drive-automerge.sh` (NEW) extracting the real **Step 7d** fence (#871) — 5 terminal arms (MERGED / BEHIND-post-request→rebase / UNKNOWN re-poll / BLOCKED|CONFLICTING / wait-timeout→pr-ready).
- Registered new suite in `run-all.sh`.

**Verification:** independent verifier PASS — mutation-proof on 6b case-11 (UNKNOWN_POLL_MAX=0 breaks it) + 7d case-1, scope clean (4 test-only paths, merge-base diff), no SKILL.md/hook edits, Layer-3 validation exit 0.


## Phase 1 — Shared tests/lib/ extract + landpr harness (+ pilot)  ✅ Done (2026-06-01T06:11:36-04:00)

**Commit:** `259bfe3` on `feat/seam-hardening-high`
**Tests:** Overall 6903/6903 passed, 0 failed (baseline 6890 → +13).

- Built `tests/lib/extract-fence.sh` (`extract_fence_between`, `extract_sentinel_block`; 3-space-indent strip + sentinel slicing; **public contract frozen** for sibling plan SEAM_HARDENING_REST).
- Built `tests/lib/landpr-harness.sh` (`mkshim`, `prepare_result_file`/`patch_caller_loop`, `seed_caller_loop_inputs` incl. Step-6b/7d inputs REBASE_STDERR_FILE/UNKNOWN_POLL_MAX/PR_STATE/TW_ITER/REASON).
- Added `tests/test-extract-fence-lib.sh` (12-test self-test; fails if extraction breaks — verified).
- Converted `tests/test-land-pr-tracking-copy.sh` to extract-and-run the REAL land-pr Step 7c fence (cases a–g preserved; fails under production-fence mutation — independently verified).
- Registered new suite in `run-all.sh`; libs intentionally not registered as suites.

**Verification:** independent verifier PASS — mutation-proof (no-op'd production `cp -af` → both suites fail), scope clean (5 test-only paths), no SKILL.md/hook/config edits, Layer-3 response validation exit 0.
