---
title: /fix-issues Sprint Report
status: complete
---

# /fix-issues sprint — sprint-20260529-230905-fnormal

**Mode:** N=1, auto, every 2h, cron-fired sprint
**Started:** 2026-05-29T19:47:00-04:00
**Open issues at sprint start:** 3 (#810, #803, #67)

## Triage

| # | Title | Verdict | Route |
|---|-------|---------|-------|
| #810 | Normalize force-flag form across skills (`--force` dashed, retire bare `force`) | Actionable, well-scoped multi-file refactor | /do pr (M) |
| #803 | Agents should claim a work-item before working it — unify via shared claim primitive | Plan-scale; new skill; issue body says "warrants /draft-plan adversarial review" | Skip — needs /draft-plan |
| #67  | GitLab (glab) support — deferred until prerequisite plans land | Author-deferred; "Action now: none" | Skip — author-deferred |

One actionable pick: **#810**.

## Work landed this fire

### #810 — `--force` normalization
- **PR:** https://github.com/zeveck/zskills-dev/pull/822 (merged)
- **Branch:** feat/do-force-flag-normalize
- **Commit:** f926a661d3300f9688fbb85c74c3b579f96e6b7e
- **Files (11):** `skills/quickfix/SKILL.md`, `skills/cleanup-merged/SKILL.md`, mirror copies under `.claude/skills/`, `docs/skills/{quickfix,cleanup-merged}.md`, `CLAUDE_TEMPLATE.md`, `.claude/rules/zskills/managed.md` (re-rendered), `tests/test-skill-conformance.sh`, `tests/test-quickfix.sh`, `tests/test-cleanup-merged-namelist.sh`.
- **Tests:** `bash tests/run-all.sh` — 6518/6518 passed (0 failed, 0 skipped). CI: pass.
- **Skill versions bumped:** `skills/quickfix/SKILL.md`, `skills/cleanup-merged/SKILL.md`.

## Skips

- **#803** — flagged for future `/draft-plan` dispatch (the issue body itself calls for adversarial review). No tracker row written this fire — will be picked up by the next `/fix-issues sync`.
- **#67** — already tracked in `docs/issues/ISSUES_PLAN.md` as `Action now: none` (author-deferred until prerequisite plans land). Left untouched.

## Sprint metadata

- Sprint pipeline ID: fix-issues.sprint-20260529-230905-fnormal
- Sprint worktree: /tmp/zskills-fix-issues-sprint-20260529-230905-fnormal (sprint-level container; no per-issue work landed here)
- Issue claim acquired for #810; released on merge.
- Cron: `36 */2 * * *` — next fire ~2h after this report.
