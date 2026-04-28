# Plan Report — Zskills Monitor Dashboard

## Phase — 3 /work-on-plans queue mutation + scheduling [UNFINALIZED]

**Plan:** plans/ZSKILLS_MONITOR_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-zskills-monitor-plan
**Branch:** feat/zskills-monitor-plan
**Commits:** f9290b7 (impl: 6 subcommands + flock + 28 tests), 905099b (tracker mark in-progress)

### Work Items

| # | Item | Status | Source |
|---|------|--------|--------|
| 3.1 | CLI parse for queue mutate (add/rank/remove/default) + schedule (every/stop) subcommands | Done | f9290b7 |
| 3.2 | Cross-process flock helper for monitor-state.json RMW | Done | f9290b7 |
| 3.3 | every cron + mode capture (captured > live default precedence) | Done | f9290b7 |
| 3.4 | schedule_under_1h() rejection of <1h with finish + verbatim diagnostic | Done | f9290b7 |
| 3.5 | stop deletes via CronDelete + state idle reset; next reads $WORK_STATE | Done | f9290b7 |
| 3.6 | fulfilled.work-on-plans.<sprint-id> markers for mutating subcommands | Done | f9290b7 |
| 3.7 | Mirror parity for /work-on-plans skill | Done | f9290b7 |

### Verification

- Test suite: PASSED (971/971, +28 from baseline 943)
- All 10 ACs pass
- Cross-process flock: 8/8 racers land with lock; 5/8 without (negative control proves race + that the lock prevents lost updates)
- Slug regex `^[a-z][a-z0-9-]*$` forbids leading digit (per AC-2 — leading digits reserved for execute-mode N)
- Schedule rejection: `30m`/`5m`/`*/30 *`/`*/2 *` all detected as <1h; `1h`/`4h` accepted
- No `eval` over user input, no `jq`, no `kill -9`
- Mirror byte-identical

### Notable scope decisions (verifier-accepted)

1. Slug regex is `^[a-z][a-z0-9-]*$` with explicit `^[0-9]` reject before general regex — belt-and-braces for AC-2's "digit-prefix reserved for execute-mode N" rule.
2. ensure_monitor_state() bootstrap helper duplicates Phase 1's heredoc (rather than `source`-ing) because SKILL.md remains a single-file LLM-driven prompt with no shared `.sh` to import.
3. .gitignore extended now (Phase 3) instead of Phase 5 — Phase 3 is the first phase that creates `monitor-state.json` / `work-on-plans-state.json` / `monitor-state.json.lock` in the working tree.

### Notes

- Phase 3 completes the `/work-on-plans` skill surface. The remaining phases shift to data aggregation (4), HTTP server (5), dashboard UI (6, 7), `/zskills-dashboard` skill (8), and `/plans rebuild` migration (9).
- One transient flake observed in `test-briefing-parity` from a parallel session's worktree appearing/vanishing during the implementer's run; pre-existing environmental flake, not introduced by Phase 3. Verifier's full-suite run was clean.

---

## Phase — 2 Remove /plans work modes [UNFINALIZED]

**Plan:** plans/ZSKILLS_MONITOR_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-zskills-monitor-plan
**Branch:** feat/zskills-monitor-plan
**Commits:** 76dbece (impl: 5 files updated), 783db9d (tracker mark in-progress)

### Work Items

| # | Item | Status | Source |
|---|------|--------|--------|
| 2.1 | skills/plans/SKILL.md — argument-hint, description, H1 trimmed; pointer to /work-on-plans; work/stop/next-run removed | Done | 76dbece |
| 2.2 | README.md — /plans row drops "batch execution"; new /work-on-plans row | Done | 76dbece |
| 2.3 | CHANGELOG.md — Migration entry + Cron-cleanup scope paragraph (session-scoped caveat) | Done | 76dbece |
| 2.4 | PRESENTATION.html — cron-scheduling row example uses /work-on-plans | Done | 76dbece |
| 2.5 | /plans bare-mode footer ranking-independent note | Done | 76dbece |
| 2.6 | Cron cleanup (best-effort, session-scoped) | Done | 76dbece |
| 2.7 | Mirror parity for /plans skill | Done | 76dbece |

### Verification

- Test suite: PASSED (943/943, no delta — docs/skill-text only)
- All 7 ACs pass; verifier independently re-detected zero PLAN-TEXT-DRIFT
- PRESENTATION.html row Skill cell change (`/plans` → `/work-on-plans`) verified consistent with table pattern
- /plans skill no longer claims batch execution; pointer to /work-on-plans is canonical migration path

### Notes

- Phase 2 is the cleanup half of the Phase 1+2 migration. Phase 1 shipped /work-on-plans; Phase 2 retires the older /plans work modes.
- Cron cleanup is session-scoped (CronList/CronDelete only see this session's crons) — caveat noted in CHANGELOG.

---

## Phase — 1 /work-on-plans execute-only CLI [UNFINALIZED]

**Plan:** plans/ZSKILLS_MONITOR_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-zskills-monitor-plan
**Branch:** feat/zskills-monitor-plan
**Commits:** 12270a0 (impl: new skill + parent: marker docs), 08e18c3 (tracker mark in-progress)

### Work Items

| # | Item | Status | Source |
|---|------|--------|--------|
| 1.1 | skills/work-on-plans/SKILL.md (677 lines) with frontmatter | Done | 12270a0 |
| 1.2 | CLI parse: read-only (no args, next) + execute (N\|all [phase\|finish] [continue]); Phase 3 subcommands stub | Done | 12270a0 |
| 1.3 | Sync sub-step: reads .zskills/monitor-state.json, auto-creates with bootstrap precedence | Done | 12270a0 |
| 1.4 | Resolve sub-step: inline tr-based slug rule, unknown-slug fail-loud | Done | 12270a0 |
| 1.5 | Dispatch sub-step: mode precedence (CLI > entry > default > "phase"), Skill-tool dispatch | Done | 12270a0 |
| 1.6 | Failure policy: 3-arm detection (text grep, marker timeout, Skill error); stop or continue | Done | 12270a0 |
| 1.7 | Sprint state lifecycle: state=sprint → heartbeat → idle; corrupt JSON resets | Done | 12270a0 |
| 1.8 | Tracking markers: step.work-on-plans, requires.run-plan with parent: work-on-plans, fulfilled.* | Done | 12270a0 |
| 1.9 | docs/tracking/TRACKING_NAMING.md "Parent-tagged markers" subsection (refine F-10 fix) | Done | 12270a0 |
| 1.10 | Mirror parity: bash scripts/mirror-skill.sh work-on-plans | Done | 12270a0 |

### Verification

- Test suite: PASSED (943/943, no delta — skill-body-only change)
- All ACs pass
- No jq, no eval over user input, no `$(())` over uncontrolled values
- Canonical post-Phase-B caller form for sanitize-pipeline-id.sh (`$MAIN_ROOT/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh`)
- Mirror byte-identical
- "Parent-tagged markers" subsection inserted at line 317 of TRACKING_NAMING.md

### PLAN-TEXT-DRIFT findings

2 spec-gap drifts flagged (non-numeric, non-blocking — Phase 3.5 doesn't auto-correct these):

1. Phase 1 WI says "acquire cross-process flock" but Shared Schemas line 94 says "no cross-process file locks" until Phase 5. Implementer correctly used `os.replace()` (POSIX-atomic) per Shared Schemas. WI text contradicts Shared Schemas constraint — should reconcile in a future refine.
2. AC's cross-process-lock test references `/work-on-plans add` — a Phase 3 subcommand. Cannot be exercised in Phase 1; SKILL.md correctly stubs `add` with "Phase 3 not yet landed" diagnostic.

Both are spec-gap inconsistencies, not numeric drift. Verifier independently confirmed.

### Notes

- Phase 1 is foundational: ships the read+execute path of `/work-on-plans`. Phase 2 retires `/plans work` modes. Phase 3 adds queue mutation + scheduling subcommands.
- This is a 9-phase plan. Phases 4-7 build the data aggregation library, HTTP server, dashboard UI, and write-back. Phase 8 creates `/zskills-dashboard` skill. Phase 9 migrates `/plans rebuild` to the new Python aggregator.
