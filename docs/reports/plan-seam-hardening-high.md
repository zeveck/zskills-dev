# Plan Report — Seam Hardening (HIGH-priority skills)

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
