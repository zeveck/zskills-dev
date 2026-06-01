---
title: /fix-issues Sprint Report
status: complete
---

# /fix-issues sprint — sprint-20260601-030804-dq30m5

**Mode:** N=2, dashboard, auto, every 30m
**Picks:** #877 (only — #883 deferred per dependency)

## Triage (4 candidates available after parallel session's 3 claims)

| # | Verdict | Action |
|---|---------|--------|
| **#877** | Actionable — shared in-flight guard helper + 3-skill integration. Well-spec'd in body. | Dispatched. |
| **#883** | Depends on #877 (body: "reuse #877's shared detection helper, keyed on work id"). | Deferred to next fire after #877 lands. |
| #881 | Held by parallel session. | Skip (foreign-held). |
| #884 | Held by parallel session. | Skip (foreign-held). |

This fire shipped N=1 because #883's premise required #877 to land first. Dispatching them in parallel would have wasted #883's implementer agent on a missing helper.

## Landed (1)

### #877 — Shared session-scoped in-flight guard
- **PR:** https://github.com/zeveck/zskills-dev/pull/901 — merged clean.
- **Files (16):** new `skills/create-worktree/scripts/check-inflight-batch.sh` (~527 lines, subcommands `check / write / clear / list / resolve-session-id`); integration in `/fix-issues/modes/sprint.md`, `/work-on-plans/modes/execute.md`, `/qe-audit/SKILL.md` (NEW Phase 0b + Phase 9 — qe-audit had no sentinel before); 7 mirror files; new 32-assertion test suite `tests/test-inflight-batch-guard.sh`; `metadata.version` bumps on 4 SKILL.md files.
- **Tests:** 6759/6759 passed (+50 from this PR).

## Key design call — session-scoping mechanism

Walks `$$`'s PPID chain on Linux until landing on the first descendant of PID 1 (init), forms session-id as `pid-<pid>.<start_time>` using `/proc/<pid>/stat` field 22 (start in clock-ticks-since-boot). Constant across all turns of one Claude Code REPL session (the harness/CLI persists across turns) and differs across sessions (different PIDs + start_times). **Critical:** preserves LEGITIMATE parallel pipelines — different sessions can each run their own sprint concurrently (different session-ids), gating only on "my session already has a fresh, un-finalized run sentinel for this skill."

Non-Linux fallback: lazily-stamped `.zskills/session-id` file with 24h refresh (only matters if zskills ever ships outside Linux containers — flagged for future revisit).

## Two robustness traps closed
- **Session-scoping** — dead/other session's sentinel never gates this one.
- **Staleness escape** — 7200s (2h) default, configurable via `ZSKILLS_INFLIGHT_MAX_AGE_SECONDS` / `--max-age-seconds`.

## Subcommand carve-out
Structural, not flag-based. The router peels `stop`/`next`/`sync`/`add`/`rank`/`remove`/`reconsider`/`default` off BEFORE the mode files containing the guard are read. For `/qe-audit` the Phase 0b guard comes after the existing `stop`/`next`/`every-without-now` exits.

## Tangential concerns worth follow-up (not in this PR)
- Dashboard chip surfacing live in-flight sentinels — UX enhancement, not correctness gap.
- #883 (re-entry guard for `/run-plan` + `/do`) — same helper, different skip-key. Next fire's natural pick.
- Session-id fallback refresh window (24h) — only matters on non-Linux.

## Sprint metadata

- Sprint pipeline ID: fix-issues.sprint-20260601-030804-dq30m5
- Sprint worktree: /tmp/zskills-fix-issues-sprint-20260601-030804-dq30m5
- Issue claim for #877 released cleanly.
- Cron: `*/30 * * * *` — next fire ~30 min; #883 likely picks up if not claimed by parallel session.
