# Plan Report — Completed + Backlog dashboard sections

**Plan completed:** 2026-05-22 (status: complete + completed: ISO-UTC-Z written to frontmatter via Phase 5b).
**Total commits on `feat/completed-backlog-sections`:** 17 (5 phase impl + 5 bookkeeping + 7 post-rebase repairs / signature merges).
**Final test tally:** `Overall: 5898/5898 passed, 0 failed`.
**Phase status:** all 5 ✅.

## Phase — 5 Integration, conformance, end-to-end verification

**Plan:** plans/completed-backlog-sections.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-completed-backlog-sections (branch `feat/completed-backlog-sections`)
**Commits:** `999045b`

### Work Items

| #     | Item                                                                | Status   | Notes                                                                                                                                       |
| ----- | ------------------------------------------------------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| W5.1  | Four-site `PLAN_COLUMNS` / `ISSUE_COLUMNS` conformance grep         | Done     | 7 assertions in `tests/test-skill-conformance.sh:2900-2976`. Encodes server/frontend tuple asymmetry per D4 with prose comment.            |
| W5.2  | Full suite + pass-count gating                                      | Done     | `Overall: 5898/5898 passed, 0 failed`. Pre-Phase-5 baseline 5891; delta +7 matches new conformance assertions exactly.                       |
| W5.3  | Playwright-cli end-to-end                                           | Deferred | Empty `dev_server.cmd` in project config; JSDOM harnesses from Phases 3-4 cover DOM-level invariants. Recipe documented in PR body.        |
| W5.4  | #618 follow-up                                                      | Moot     | PR #636 landed independently 2026-05-22T07:57:38Z. All 11 canonical statuses verified present in `landedPillClass()` at `app.js:1358-1377`. |
| W5.5  | Final `skills/zskills-dashboard/SKILL.md metadata.version` bump     | Done     | `2026.05.22+42ffc1` after Phase 5's comment-marker edit shifted content hash. Mirror parity verified.                                       |
| W5.6  | PR test plan checkboxes + body                                      | Done     | `/tmp/pr-body-completed-backlog-sections.md` composed. 6 checked items + 1 unchecked-annotated playwright deferral.                         |
| W5.7  | Conformance test extension                                          | Done     | Same artifact as W5.1.                                                                                                                       |

### Verification

- **Test suite:** `Overall: 5898/5898 passed, 0 failed`.
- **Acceptance criteria:** AC5.1, AC5.2, AC5.4, AC5.5 all met. AC5.3 N/A-by-deferral.
- **No PLAN-TEXT-DRIFT tokens.**
- **Scope-creep check:** clean — 6 files in expected paths + one mode-only mirror sync (`claim-fence-helpers.sh`: PR #645-era source/mirror inconsistency, now consistent at 644).

### Plan-wide outcome

The feature ships a fully-bidirectional Triage↔Backlog and Drafted↔Backlog drag affordance with a read-only Completed band derived per-snapshot from GitHub `closedAt` (issues) and plan-frontmatter `completed:` (plans). Backend state schema bumped to v1.2 with a documented v1.1↔v1.2 hard-cut migration. Server validator rejects POSTs to `completed` with literal `"completed column is read-only"`. Frontend renders below-panel Backlog + Completed bands with truncation banner and count-derived collapse. Phase 5's conformance test locks the deliberate server-omits-`completed` asymmetry (D4) across four literal sites so any future refactor "fixing the inconsistency" must do so deliberately.

### User Sign-off

(Manual playwright-cli walkthrough deferred per the project's empty `dev_server.cmd`. JSDOM harnesses cover DOM-level invariants; consumer projects with configured dev servers can layer real-event tests on top.)

---

## Phase — 4 Drag-target wiring + Completed read-only semantics

**Plan:** plans/completed-backlog-sections.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-completed-backlog-sections (branch `feat/completed-backlog-sections`)
**Commits:** `852dcb9`

### Work Items

| #     | Item                                                                          | Status   | Notes                                                                                                                                          |
| ----- | ----------------------------------------------------------------------------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| W4.1  | `buildIssueCard` / `buildPlanCard` completed-card guard                       | Done     | `isCompleted` gate suppresses draggable, claim-chip, per-card buttons, move-all chevron. Plan completed → plain `<span>` title (DA10).         |
| W4.2  | `onDrop` completed reject + backlog dispatch                                  | Done     | `console.warn` + no-op on completed-target drop; backlog targets route through normal `postQueue` path.                                        |
| W4.3  | Chevron-renderer skip on completed                                            | Done     | `renderBelowPanelBand` emits chevrons under `if (c === "backlog")` only. Active-row uses `ACTIVE_*_COLUMNS` (excludes completed).             |
| W4.4  | Drag from Backlog → leftmost-active rewrite per D5                            | Done     | When `sourceColumn === "backlog"`, target rewrites to `"triage"` (issues) / `"drafted"` (plans). Explicit D5 cite in code comment.            |
| W4.5  | Single `postQueue` helper                                                     | Done     | `grep -cE "fetch\\([^)]*api/queue" app.js == 1`.                                                                                                |
| W4.6  | Composition checks (claim chip, move-all, lastGoodQueues deepClone)           | Done     | All three covered. Claim chip suppressed on completed cards (W4.10 enforces). Move-all skips completed (W4.11). DeepClone iterates 5/4-tuples. |
| W4.7  | Skill version bump                                                            | Done     | `skills/zskills-dashboard/SKILL.md metadata.version: 2026.05.22+fd083a`.                                                                       |
| W4.8  | NEW `tests/test-dashboard-completed-readonly.sh`                              | Done     | 18 PASSes via JSDOM render. Registered in `tests/run-all.sh`.                                                                                  |
| W4.9  | NEW `tests/test-dashboard-backlog-bidir.sh`                                   | Done     | 23 PASSes via JSDOM harness driving `onDragStart`/`onDrop` directly. Playwright path deferred (dev_server.cmd empty) — documented in header.   |
| W4.10 | extended `test-fix-issues-claim-render-dom.sh` with `completed_column_no_claim_chip` | Done | DOM assertion: no `.claim-chip` even with populated claim payload.                                                                              |
| W4.11 | extended `test_zskills_monitor_dashboard_ui.sh` with `move_all_chevron_absent_on_completed` | Done | Static-grep assertion for guard pattern.                                                                                                       |
| W4.12 | extended `test_zskills_monitor_dashboard_ui.sh` with `single_fetch_helper_post` | Done | Grep count == 1 asserted.                                                                                                                       |

### Verification

- **Test suite:** `Overall: 5640/5640 passed, 0 failed`.
- **Acceptance criteria:** AC4.1–AC4.8 all met.
- **No PLAN-TEXT-DRIFT tokens.**
- **Scope-creep check:** clean — 7 files in expected paths + 2 new test files (× source/mirror parity where applicable).
- **Mirror invariant:** source and `.claude/skills/` byte-identical for both `SKILL.md` and `app.js`.

### Cross-phase notes

- **Phase 5 will need to encode an asymmetry in W5.1's four-site conformance grep.** The frontend (`app.js`) has 5/4-element tuples including `completed`; the server (`server.py`) deliberately has 4/3-element tuples EXCLUDING `completed` (the validator's writeable-target whitelist). This is intentional per Locked Decision D4 — `completed` is read-only on the API surface and W2.2 hard-rejects writes. W5.1's conformance grep cannot assume identical tuple ordering across all four sites; it must encode the rule "server omits `completed`; frontend includes it."
- **W4.4 chevron-vs-drag D5 ambiguity** (verifier-flagged). Backlog's `«` column-head chevron uses `moveAllInColumn`'s adjacent-step semantics. For plans, that points to `ready` (NOT `drafted` as D5 would prescribe). For issues, `triage` happens to be both leftmost-active AND adjacent-prev so the issue is moot there. The W4.4 spec is literally scoped to "the `onDrop` handler" — drag-only — so the implementation is spec-compliant. Phase 5 may want to consider whether the chevron should also obey D5; if yes, an explicit override for plans-backlog `«` → `drafted` is required.
- **W5.4 #618 follow-up is MOOT.** PR #636 (`fix(zskills-dashboard): map all 11 canonical .landed statuses in landedPillClass`) landed on main at 2026-05-22T07:57:38Z, absorbed by the chore commit `9b07013` ahead of this phase. Phase 5 should either skip W5.4 entirely or note that the follow-up was filed and landed independently.
- **W3.13 manual playwright still deferred** (dev_server.cmd empty); same deferral applies to W4.9's playwright path.

### User Sign-off

(No interactive UI sign-off in Phase 4 — JSDOM tests cover DOM-level assertions; playwright-cli manual deferred per the project's empty dev_server.cmd config. Accumulated sign-off for the final phase: zero items needing human review until consumer projects with configured dev servers exercise the band UI.)

---

## Phase — 3 Frontend rendering + below-panel band layout [UNFINALIZED]

**Plan:** plans/completed-backlog-sections.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-completed-backlog-sections (branch `feat/completed-backlog-sections`)
**Commits:** `c6f0b73`

### Work Items

| #     | Item                                                                     | Status   | Notes                                                                                                                                  |
| ----- | ------------------------------------------------------------------------ | -------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| W3.1  | Extend `PLAN_COLUMNS` / `ISSUE_COLUMNS` + labels                         | Done     | Full 5-col plans / 4-col issues; labels for both new columns.                                                                          |
| W3.2  | `deepCloneQueues` allocator + `liveIssueNumbers`                         | Done     | Tuple-driven loops pick up `backlog` and `completed` mechanically; bonus `postQueue` strip of `completed` (defense-in-depth).          |
| W3.3  | `fingerprintPlans` / `fingerprintIssues` include new columns + flags     | Done     | Issues fingerprint also includes `(closed_issues_truncated, closed_issues_limit)` so banner re-renders on flag toggle.                |
| W3.4  | Below-panel-band markup in renderPlans / renderIssues                    | Done     | Sibling block after the active `.columns`; each band has 2 `<ul class="dropzone">` children with `data-kind` + `data-column` attrs.    |
| W3.5  | `.below-panel-band` CSS layout primitive                                 | Done     | Standalone 2-col grid, dashed separator, `[hidden]` collapse. NOT composed with `.columns-2` (per D3).                                  |
| W3.6  | (removed in spec)                                                         | n/a      | #618 follow-up filed separately.                                                                                                       |
| W3.7  | Count-derived collapse logic                                              | Done     | Band hides only when BOTH sub-columns empty; Backlog always renders with "Drag here to defer" placeholder.                              |
| W3.7b | Truncation banner with double-interpolated limit                          | Done     | Non-dismissable; template literal interpolates `${closed_issues_limit}` exactly twice; no localStorage; disappears when flag absent.    |
| W3.8  | `skills/zskills-dashboard/SKILL.md metadata.version`                      | Done     | `2026.05.22+83f4bb`, hash recheck-confirmed.                                                                                            |
| W3.9  | test: `renders_completed_band_below_issues_panel`                         | Done     | Static-grep falsifiable equivalent of the spec's DOM assertion.                                                                         |
| W3.10 | test: `renders_backlog_band_below_plans_panel`                            | Done     | Same convention.                                                                                                                       |
| W3.11 | test: `below_panel_band_visible_when_backlog_empty_but_no_completed`      | Done     | Asserts Backlog drop-target visible when Completed has items but Backlog is empty.                                                       |
| W3.12 | test: `below_panel_band_collapse_when_both_empty`                         | Done     | Asserts `hidden` attribute set when both columns empty.                                                                                  |
| W3.12b | test: `truncation_banner_renders_with_actual_limit_value`                | Done     | Asserts interpolation count == 2, no placeholder leak, early-return on falsy flag.                                                       |
| W3.13 | Manual playwright-cli verification                                        | Deferred | `dev_server.cmd` is empty in `.claude/zskills-config.json` for this project. To be exercised in consumer projects with the cmd set.    |

### Verification

- **Test suite:** `Overall: 5544/5544 passed, 0 failed`.
- **Acceptance criteria:** AC3.1, AC3.2, AC3.3, AC3.5, AC3.6 all met. AC3.4 removed in spec.
- **No PLAN-TEXT-DRIFT tokens.**
- **Scope-creep check:** clean — 7 files in expected paths (source + mirror for app.js/app.css/SKILL.md, plus the test file).
- **Inline verifier action:** none required; impl was clean.

### Cross-phase notes

- The implementer's `postQueue` `completed`-strip is a client-side defense-in-depth addition (not in spec) that prevents accidental POST to the read-only column from any UI path. The server's W2.2 hard-reject remains the authoritative defense.
- Active row (3-col plans / 2-col issues) is unchanged; the below-band is a sibling block, NOT a new column inside the existing grid.
- Phase 4 territory (flagged by verifier):
  1. **Completed cards need `draggable=false`** per D5 — Phase 4 must add per-card guard on `data-column === "completed"` in `buildPlanCard` / `buildIssueCard`. Same guard suppresses claim-chip (D7b) and per-card move buttons (D5).
  2. **Move-all chevron in Backlog column-head** would currently target `PLAN_COLUMNS[ci+1] = completed`. Phase 4 must add a guard that suppresses the right-chevron when the next-target column is `completed` (terminal read-only).
  3. **Backlog `«`-chevron back to active** not yet emitted by `renderBelowPanelBand`; Phase 4 decision whether to add it (D5: rewrite to leftmost active on promote).
  4. **Active-row right-chevron from Ready → Backlog** is now possible; Phase 4 verifies this works end-to-end (`moveAllInColumn`).
  5. **`fingerprintIssues` references module-level `lastSnapshot`** behind `typeof` guard (app.js:529). Defensible for standalone-extraction harnesses but flag for Phase 5 conformance.

### User Sign-off

(No interactive UI sign-off in Phase 3 — visual playwright-cli check deferred per W3.13. Sign-off accumulates for the final phase.)

---

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
