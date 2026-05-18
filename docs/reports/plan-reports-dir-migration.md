# Plan Report — REPORTS_DIR_MIGRATION

## Phase — 2 Writer + reader path swap across affected skills [UNFINALIZED]

**Plan:** docs/plans/REPORTS_DIR_MIGRATION.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-reports-dir-migration (PR mode, branch `feat/reports-dir-migration`)
**Commits:** 9 commits (3b942cb, 6bb4d58, 3b8a3c1, 8a9e5ec, f911856, 7f4a07f, 9ee5256, fcd745d, 547a182) + tracker (02f01de)

### Work Items (all PASS)
- WI 2.1: run-plan plan-* writes swapped (5 files, 19 sites)
- WI 2.2: verify-changes verify-* writes swapped (1 file, 13 sites)
- WI 2.3: fix-issues SPRINT_REPORT writes swapped (3 files, 18 SPRINT_REPORT sites + 8 non-SPRINT preserved)
- WI 2.4: briefing reads split (helper extended; 11 reports_dir + 28 audit_dir hits with renamed locals)
- WI 2.5: fix-report SPRINT_REPORT reads swapped (9 hits)
- WI 2.6: dashboard `_resolve_paths()` extended with reports_dir key; collect.py line 587 swap
- WI 2.7-2.10: per-skill version bumps + mirror byte-equal
- WI 2.11: stage-check pre-flight before each commit

### Verification
- Test suite: 3316/3316 PASSED (vs 3313 prior; +3 from new conformance gate; 0 regressions)
- Mirror byte-equality: PASS (all 7 skill pairs)
- Cohabitation re-test after every per-skill commit: PASS (2 Tier-1 drifts caught + fixed in-flight)
- Scope-purity: PASS (32 files all in expected paths)

### Drifts (logged, not auto-corrected)
- WI 2.1 line refs were stale (file drifted since plan drafting); hit count of 17 correct, line numbers approximate.
- WI 2.3 said "26 hits" but only 18 are SPRINT_REPORT swaps (8 are FIX_REPORT/PLAN_INDEX/tracker preserved).
- WI 2.10 planned 7 commits; actual landing required 9 (2 extra Tier-1 hash registry cohabitation fix-ups, per issue #380 lesson learned and applied in-flight).

### Notable
- Tier-1 cohabitation discipline (issue #380): verifier re-ran `test-update-zskills-migration.sh` after EACH per-skill commit, caught 2 violations (post-run-invariants.sh + briefing.py touched without registry update), fixed in same-branch follow-up commits. Closed the gap that bit Phase 1.
- Audit-vs-reports triage rigor: 30 legitimate `$ZSKILLS_AUDIT_DIR` references preserved (PLAN_REPORT, PLAN_INDEX, tracking markers, debug dumps); only `plan-*`, `verify-*`, `SPRINT_REPORT.md` writers swapped.

### Next
Phase 3: migration commit (44 `git mv` + 13 `git rm --cached` + `.zskills/` empty assertion). Cron-scheduled.
