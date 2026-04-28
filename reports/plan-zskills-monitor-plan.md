# Plan Report — Zskills Monitor Dashboard

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
