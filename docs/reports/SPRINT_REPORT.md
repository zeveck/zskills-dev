---
title: /fix-issues Sprint Report
status: complete
---

# /fix-issues sprint — sprint-20260531-143854-docstidy

**Mode:** N=1, auto, every 2h, cron-fired sprint
**Started:** 2026-05-31T11:37:18-04:00
**Open issues at sprint start:** 7 (#67, #832, #833, #835, #836, #839, #842)
**Skip-tagged (dropped by Phase 2 filter):** 3 (#67 deferred; #832, #833 needs-decision)
**Newly researched:** 4 (#835, #836, #839, #842)
**Actionable picks:** 1 (#842)

## Triage of newly-researched candidates

| # | Title | Verdict | Route |
|---|-------|---------|-------|
| #835 | /draft-tests extract phases into mode/reference files (2072→split) | Mechanical refactor but L-sized; body says "trace variable flow before splitting" — variable graph across 6 phases is dense. Authors explicitly say "/do scale; no /draft-plan needed" but lower confidence than smaller splits. | Skip this fire; tag for next /do pr. |
| #836 | /quickfix extract phases into mode/reference files (1533→split) | Mechanical but body says "Lower confidence than /draft-tests proposal — if extraction reveals variable graph too entangled, may be appropriate to land a partial split." | Skip this fire; tag for next /do pr. |
| #839 | /session-report handoff mode — durable hand-off | Substantial new feature; body has explicit "Design note (the one real question)" section needing author judgment. | Skip — /draft-plan first. |
| #842 | Tidy docs/ root → docs/guides/ + link fix | Mechanical file-move + link-fix; body explicitly says "**not** a design surface, so this does **not** need /draft-plan. A single /do pr (worktree) pass." | /do pr → LANDED. |

## Landed this fire

### #842 — docs/ root tidy + link fix
- **PR:** https://github.com/zeveck/zskills-dev/pull/845 (merged, CI pass)
- **Branch:** `feat/do-docs-guides-tidy`
- **Commit:** `dc7bce11145abefc3388f2ec09d67e4367c727e7`
- **Moves (7):** WORKFLOWS / PLUGIN_INSTALL / PLUGIN_MIGRATION / INSPECTING_AND_MONITORING (.md + .html + assets/zskills-dashboard.png) all moved to `docs/guides/`; repo-root ZSKILLS_TRACKING_OVERVIEW.md moved to `docs/guides/` for adjacency.
- **Inbound-link edits (~9 files):** README.md, skills/update-zskills/SKILL.md (+ mirror), docs/skills/README.md, docs/plans/PLUGIN_DISTRIBUTION.md, docs/reports/plan-plugin-distribution.md, intra-guides relative-path shifts.
- **New file:** `docs/README.md` (subdir index).
- **Skill version bump:** `skills/update-zskills/SKILL.md` (`d1fb40` → `3853ab`) — link-edit changed content hash; flagged by conformance test on first run, fixed cleanly.
- **Tests:** `bash tests/run-all.sh` — 6570/6570 passed (0 failed). Verify-greps for old paths return zero hits.

## Implementer-surfaced sidefinding (not actioned this fire)

The implementer noted that `tests/test-plans-render-index.sh` mutates `docs/plans/SKILL_VERIFICATION_SMOKES.md` (inserts a `completed:` frontmatter timestamp) as a side-effect — a test-bug since the test should write into a copy, not the live plan file. The implementer reverted the mutation to keep this PR's diff feature-scoped. **Worth filing as a follow-up GH issue** if not already known.

## Open backlog (deferred to future fires)

- **#835, #836** — large skill refactors, mechanical but L-sized; next /do pr candidates.
- **#839** — /draft-plan first (open design question).
- **#67, #832, #833** — skip-tagged.

## Sprint metadata

- Sprint pipeline ID: fix-issues.sprint-20260531-143854-docstidy
- Sprint worktree: /tmp/zskills-fix-issues-sprint-20260531-143854-docstidy
- Issue claim for #842 acquired and released cleanly.
- Cron: `36 */2 * * *` — next fire ~2h.
