# Plan Report — Move skill-owned scripts into the skills that use them

## Phase — 1 Inventory cleanup: fix dead refs, write ownership registry [UNFINALIZED]

**Plan:** plans/SCRIPTS_INTO_SKILLS_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-scripts-into-skills-plan
**Branch:** feat/scripts-into-skills-plan
**Commits:** 7fc20c4 (orchestrator H4→H3 heading fix), 49c666b (impl + ownership registry), bb4d661 (tracker + prose drift fix)

### Work Items

| # | Item | Status | Source |
|---|------|--------|--------|
| 1.2 | 3 dead script refs in skills/fix-issues/SKILL.md replaced with manual gh recipes (skipped-issues.cjs, sync-issues.js, issue-stats.js) | Done | 49c666b |
| 1.3 | review-feedback.js ref stripped from skills/review-feedback/SKILL.md | Done | 49c666b |
| 1.4 | skills/update-zskills/references/script-ownership.md written (18 rows: 14 Tier-1 + 4 Tier-2). Plan Overview table synchronized | Done | 49c666b |
| 1.5 | Mirror parity for fix-issues, review-feedback, update-zskills | Done | 49c666b |
| 1.6 | rel-root-cw-cw-smoke-43859 verified absent; __pycache__ deferred to Phase 2 WI 2.8b per plan | Done | 49c666b |
| (orchestrator) | H4 → H3 phase sub-heading restoration (refine-plan output had wrong levels) | Done | 7fc20c4 |
| (orchestrator) | Phase 4 tracker mark-in-progress + 3 prose drift fixes (verifier-flagged "13 moves" → "14"; Tier-2 list updated) | Done | bb4d661 |

### Verification

- Test suite: PASSED (931/931, no delta from baseline — docs-only phase)
- All 9 acceptance criteria verified by independent verification agent
- Mirror parity holds for all 3 skills (`diff -r` clean)
- Verifier independently re-detected 3 PLAN-TEXT-DRIFT prose drifts (13→14 / Tier-2 omitted mirror-skill.sh) — fixed inline in commit `bb4d661`
- `script-ownership.md` registry contract: 14 Tier-1 + 4 Tier-2 rows; canonical Tier-1 parser; STALE_LIST documented

### Notes

- Phase 1 is foundational/registry only — no script moves yet.
- Phase 2 will move single-owner Tier-1 scripts (apply-preset, compute-cron-fire, post-run-invariants, briefing.*, statusline) into their owning skills' `scripts/` subdirs.
- Phase 3a/3b will move shared Tier-1 scripts (create-worktree, worktree-add-safe, land-phase, etc.) and sweep cross-skill callers.
- Phase 4 will rewrite `/update-zskills` install flow.
- Phase 5 will sweep tests + README/CLAUDE.md/CLAUDE_TEMPLATE.
- Phase 6: docs and close-out.

### PLAN-TEXT-DRIFT findings

3 prose drifts caught by the verifier (binding ACs all passed):
- Line 84 ("13 moves" → 14): fixed inline in bb4d661
- Line 86 (Tier-2 list omitted mirror-skill.sh): fixed inline
- Line 2414 ("13 scripts moved" → 14): fixed inline

These were stragglers from the refine-plan output where per-table counts synced but free-form prose did not. All 3 corrected on the feature branch.
