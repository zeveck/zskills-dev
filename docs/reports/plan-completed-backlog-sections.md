# Plan Report — Completed + Backlog dashboard sections

## Phase — 1 Backend (`collect.py` + state schema v1.2) [UNFINALIZED]

**Plan:** plans/completed-backlog-sections.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-completed-backlog-sections (branch `feat/completed-backlog-sections`)
**Commits:** `3b6a5cb`

### Work Items

| #     | Item                                                              | Status | Notes                                                                                                                         |
| ----- | ----------------------------------------------------------------- | ------ | ----------------------------------------------------------------------------------------------------------------------------- |
| W1.1  | `list_closed_issues_in_window` (bounded closed-issue fetch)       | Done   | `collect.py:1259-1373`; 60s TTL cache keyed by `(days, limit)`; returns `(issues, ok)`.                                       |
| W1.2  | windowed `_infer_default_column`                                  | Done   | `collect.py:1418-1453`; reads `completed:` frontmatter, returns `"completed"` when in-window, else `None`.                    |
| W1.2b | new `_infer_issue_default_column`                                 | Done   | `collect.py:1456-1475`; wired into `_annotate_issues_queue`.                                                                  |
| W1.3  | annotate-queue precedence (state-explicit-wins + dedupe-closed)   | Done   | `collect.py:1601-1610` (plans), `1672-1685` (issues dedupe-prefer-closed).                                                    |
| W1.4  | `_read_state_file` v1.1 tolerance                                 | Done   | `backlog: []` defaulted at 1558-1561; v1.1 fixtures parse cleanly (W1.10).                                                    |
| W1.5  | `/run-plan` Phase 5b writes `completed: <ISO-UTC-Z>`              | Done   | Uses `$ZSKILLS_PLANS_DIR/<slug>.md`; no hardcoded `plans/`.                                                                   |
| W1.5b | `backfill-plan-completed.sh`                                      | Done   | Pickaxe `-G"^status:[[:space:]]*complete$" --follow --reverse --format=%cI` + UTC normalization + rename-aware fallback.      |
| W1.5c | `skills/run-plan/SKILL.md` version bump                           | Done   | `2026.05.22+cd8504`.                                                                                                          |
| W1.6  | config fields + resolver + plumbing + truncation flag             | Done   | `execution.dashboard_completed_days` (14) + `dashboard_completed_limit` (500); schema, resolver, `collect_snapshot` threaded. |
| W1.7  | `skills/zskills-dashboard/SKILL.md` version bump                  | Done   | `2026.05.22+76b148` (re-bumped after verifier's AC1.9 comment fix).                                                           |
| W1.8  | test: bounded-by-date                                             | Done   | `tests/test_zskills_monitor_collect.sh:1214-1258`.                                                                            |
| W1.9  | test: inference within/outside + issue inference                  | Done   | Lines 1261-1290.                                                                                                              |
| W1.10 | test: v1.1 migration                                              | Done   | Lines 1293-1325.                                                                                                              |
| W1.11 | test: annotate-issues assigns completed                           | Done   | Lines 1328-1350.                                                                                                              |
| W1.12 | test: config window narrows snapshot                              | Done   | Lines 1353-1380.                                                                                                              |
| W1.13 | test: backfill idempotent                                         | Done   | Lines 1488-1513.                                                                                                              |
| W1.14 | test: plans-dir resolved from config + antipattern grep           | Done   | Lines 1516-1546.                                                                                                              |
| W1.15 | test: rename survives                                             | Done   | Lines 1548-1590; exercises rename-aware fallback.                                                                             |
| W1.15b | test: `-04:00` → `Z` normalization                               | Done   | Lines 1593-1628.                                                                                                              |
| W1.16 | test: re-upgrade takes latest                                     | Done   | Lines 1631-1682.                                                                                                              |
| W1.17 | test: block-scalar exit 3 handled                                 | Done   | Lines 1685-1729.                                                                                                              |
| W1.18 | test: cwd precheck                                                | Done   | Lines 1732-1766.                                                                                                              |
| W1.19 | test: prefers closed on dual membership (issues)                  | Done   | Lines 1383-1409.                                                                                                              |
| W1.20 | test: prefers state-explicit over inferred (plans)                | Done   | Lines 1412-1441.                                                                                                              |

### Verification

- **Test suite:** `Overall: 5385/5385 passed, 0 failed` (baseline `5371/5371`; delta `+14` matches the 14 new `_test_*` cases).
- **Acceptance criteria:** AC1.1-AC1.6, AC1.8-AC1.10 all met. AC1.7 (cold-fetch p95 / payload size) is spec-marked "single sample on local fixture; full benchmark not required" — logic verified sound, no benchmark run.
- **No `PLAN-TEXT-DRIFT:` tokens** (counts re-measured independently by verifier).
- **Inline verifier fix:** AC1.9 grep tripwire fired on a literal `--diff-filter=AM` reference inside a documentation comment in the backfill script. Verifier rephrased the comment in both source and `.claude` mirror, re-bumped `skills/zskills-dashboard/SKILL.md` to `2026.05.22+76b148`, then re-ran tests.
- **Scope-creep check:** clean (the `git diff origin/main..HEAD` showed `-343` deletions, but those were from `origin/main` advancing 2 commits during the impl agent run — #624 and a sprint report. The actual implementer diff is 13 files, +1405/-40, all in-scope.)

### Cross-phase notes

- `server.py` was NOT touched in Phase 1 by design (per the spec: "server.py write-side bumps live in Phase 2 / W2.X"). Phase 2 must bump all four `"version": "1.1"` write sites to `"1.2"` and extend `_validate_queue_body` to accept `backlog` + explicitly reject `completed` writes.
- `_annotate_issues_queue` signature changed (added `now_utc`, `window_days` kwargs with defaults). Phase 2/3 callers should pass `now_utc` from the snapshot rather than rely on the `datetime.now(timezone.utc)` default.
- The pickaxe primary invocation specified by AC1.9 (`-G"…complete$" --follow --reverse --format=%cI`) is preserved as the first attempt in the backfill script; a rename-aware fallback handles the documented git 2.x quirk where `-G` combined with `--follow` silently drops pre-rename history matches. W1.15 exercises the fallback.
- Branch is behind `origin/main` by 2 commits (#624 + sprint report) at end-of-phase. Will rebase before the final-phase push per `modes/pr.md` "Rebase point 2".

### User Sign-off

(No UI files changed in Phase 1 — Backend phase only. Sign-off accumulates for the final phase.)
