# Plan Report — Completed + Backlog dashboard sections

## Phase — 2 Server validator + version writers (`server.py`) [UNFINALIZED]

**Plan:** plans/completed-backlog-sections.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-completed-backlog-sections (branch `feat/completed-backlog-sections`)
**Commits:** `ba8cfac`

### Work Items

| #     | Item                                                                    | Status | Notes                                                                                                                  |
| ----- | ----------------------------------------------------------------------- | ------ | ---------------------------------------------------------------------------------------------------------------------- |
| W2.1  | Extend `PLAN_COLUMNS` / `ISSUE_COLUMNS` with `backlog`                  | Done   | `server.py:81-82`. `completed` is NOT in either tuple (W2.2 enforces explicit reject).                                 |
| W2.2  | Explicit pre-loop `completed` rejection in `_validate_queue_body`       | Done   | `server.py:460-466` (plans), `495-501` (issues). Error message contains literal `"completed column is read-only"`.     |
| W2.3  | Bump four `"version": "1.1"` sites + startup log line                   | Done   | Sites at 321, 332, 339, 954 all → `"1.2"`. Startup log at 1240-1243 (sys.stderr.write, matches house style).           |
| W2.4  | No-code-change confirmation of `_handle_queue_post`                     | Done   | Column-tuple-driven write path at 954-958 inherits `backlog` automatically. W2.8 exercises end-to-end.                  |
| W2.5  | Bump `skills/zskills-dashboard/SKILL.md metadata.version`               | Done   | `2026.05.22+26ef28`; hash + mirror verified.                                                                            |
| W2.6  | test: `validate_queue_body_accepts_backlog`                             | Done   | POST `issues.backlog: [N]` returns no error.                                                                            |
| W2.7  | test: `validate_queue_body_rejects_completed_in_post`                   | Done   | Asserts 400 + literal `"completed column is read-only"` for both plans + issues + distinctness vs generic unknown-col. |
| W2.8  | test: `queue_post_roundtrip_backlog`                                    | Done   | POST → state-file `"version": "1.2"` + persisted backlog + GET roundtrip.                                               |
| W2.9  | test: `state_file_version_bumped_all_sites`                             | Done   | Asserts `grep -c '"version": "1.1"' == 0` AND `grep -c '"version": "1.2"' >= 4`.                                       |

### Verification

- **Test suite:** `Overall: 5476/5476 passed, 0 failed`.
- **Acceptance criteria:** AC2.1-AC2.5 all met.
- **No PLAN-TEXT-DRIFT tokens.**
- **Design adaptation noted:** W2.3 startup log uses `sys.stderr.write` (matching the existing `Listening on …` line at `server.py:1228-1230`) rather than `log.info(...)` (which would require introducing `logging` setup not currently present). Format remains operator-greppable: `PLAN_COLUMNS=… ISSUE_COLUMNS=… state_version=1.2`.
- **Test-fixture preservation pattern:** the implementer documented a NOTE block in the test file explaining the constraint that downstream `sample-plan` + `42` fixtures used by the #281 regression check must be echoed in mid-suite POSTs. Phase 3 frontend tests that exercise POST flows should follow the same convention.
- **Scope-creep check:** clean — 5 files in expected paths (server.py + mirror, zskills-dashboard SKILL.md + mirror, test file).

### Cross-phase notes

- The `backlog` column is now WRITABLE on `/api/queue`; the `completed` column is HARD-REJECTED. Phase 3 must NOT render a UI drop target on the Completed sub-column (per Locked Decisions D3, D5). The validator's read-only-on-API contract is the structural backstop, but the UI affordance must also be suppressed.
- Phase 3 must extend `app.js` `PLAN_COLUMNS` / `ISSUE_COLUMNS` arrays to mirror the server's tuple order (drafted, reviewed, ready, backlog, completed for plans; triage, ready, backlog, completed for issues). W5.1 (Phase 5) will conformance-check the four sites with full-tuple-ordering grep.
- Branch state at end-of-Phase-2: 4 commits on top of origin/main (`7bf3652`): `845e974` (P1 impl), `d181163` (P1 tracker), `76b8ebc` (P1 version repair), `ba8cfac` (P2). No rebase needed yet; Phase 3 rebase point fires before Phase 3 impl.

### User Sign-off

(No UI files changed in Phase 2. Sign-off accumulates for the final phase.)

---

## Phase — 1 Backend (`collect.py` + state schema v1.2) [UNFINALIZED]

**Plan:** plans/completed-backlog-sections.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-completed-backlog-sections (branch `feat/completed-backlog-sections`)
**Commits:** `845e974` (impl, formerly `3b6a5cb` pre-rebase), `76b8ebc` (post-rebase version repair)

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
