---
title: /fix-issues Sprint Report
status: complete
---

# /fix-issues sprint — sprint-20260530-050017-locale

**Mode:** N=1, auto, every 2h, cron-fired sprint
**Started:** 2026-05-30T01:24:09-04:00
**Open issues at sprint start:** 2 (#827, #67)
**Actionable picks:** 1 (#827)

## Triage

| # | Title | Verdict | Route |
|---|-------|---------|-------|
| #827 | claim-{plan,issue}.sh locale-dependent EEXIST match (`"File exists"`) breaks self-re-entry under non-English locales | Actionable, S (one-line LC_ALL=C prefix per file + behavioral test + version bumps) | /do pr (--force --auto) |
| #67  | GitLab support — deferred until prereqs land | Already skip-tagged `deferred` (filter: `SKIP_TAGGED="67:deferred"`) | Skip — dropped by Phase 2 SKIP_TAGGED filter |

## Landed this fire

### #827 — LC_ALL=C on claim-script mkdir
- **PR:** https://github.com/zeveck/zskills-dev/pull/828 (merged, CI pass)
- **Branch:** `feat/do-locale-c-claim-mkdir`
- **Commit:** `09e71b1ab06af01f4393335657b27a8b45ec39e8`
- **Files (9):** source + mirror of `claim-plan.sh` and `claim-issue.sh` (`LC_ALL=C` prefix on the mkdir line); source + mirror of `run-plan` and `fix-issues` SKILL.md (`metadata.version` bump); `tests/test-claim-self-reentry.sh` (new section e1-e4 — e1/e2 always run; e3/e4 exercise the localized branch under a non-English `LC_ALL` and skip gracefully with a stderr note when no such locale is installed).
- **Tests:** `bash tests/run-all.sh` — 6555/6555 passed (0 failed). Devcontainer has no `fr_FR.UTF-8`, so e3/e4 emitted the documented skip note here; CI runners with localized glibc will exercise the localized branch automatically.
- **Skill versions bumped:** `skills/run-plan/SKILL.md` (`2026.05.30+9e8919`); `skills/fix-issues/SKILL.md` (`2026.05.30+3fa96f`).

## Sprint metadata

- Sprint pipeline ID: fix-issues.sprint-20260530-050017-locale
- Sprint worktree: /tmp/zskills-fix-issues-sprint-20260530-050017-locale
- Issue claim for #827 acquired and released on merge.
- Cron: `36 */2 * * *` — next fire ~2h.
