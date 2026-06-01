---
title: /fix-issues Sprint Report
status: complete
---

# /fix-issues sprint — sprint-20260601-014727-dq30m4

**Mode:** N=2, dashboard, auto, every 30m
**Picks:** #868, #867 (claim-before-worktree discipline; parallel session held #862, #869 — dropped past them per dashboard race-loser policy)

## Landed (2)

### #868 — /quickfix dual-lane sanitize-pipeline-id.sh path
- **PR:** https://github.com/zeveck/zskills-dev/pull/897 — merged clean
- **Fix:** `skills/quickfix/SKILL.md:713` `bash "$MAIN_ROOT/.claude/skills/.../sanitize-pipeline-id.sh"` → `bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/sanitize-pipeline-id.sh"` (matches `/do`, `/fix-issues`, `/run-plan` peer pattern)
- **Tests:** 6709/6709 + new regression-guard case 9b ensuring the mirror-only path stays gone; fixture's `make_fixture` updated to ship resolver scripts so `$ZSKILLS_SKILLS_ROOT` actually populates in the extracted harness.
- **Sister-defect audit:** other `.claude/skills/...` references in `/quickfix` reviewed — all are correct LEGACY-LANE fallbacks inside proper dual-lane conditionals; no follow-up scope.

### #867 — /run-plan preflight gate becomes lane-agnostic
- **PR:** https://github.com/zeveck/zskills-dev/pull/899 — merged after auto-rebase (BEHIND on first poll due to parallel session's PR landing during CI; resolved cleanly).
- **Fix:** replaced broken `grep -qE '^(UNIT_TEST_CMD|FULL_TEST_CMD)=.*\{\{' .claude/hooks/block-unsafe-project.sh 2>/dev/null` (plugin-lane-blind + scanning for `{{...}}` placeholders that no longer exist in hook body) with dual-lane `zskills-resolve-config.sh` sourcing + `$FULL_TEST_CMD` check.
- **Prose rewrite:** dropped `{{...}}` framing; described two actual failure modes (missing/malformed `.claude/zskills-config.json`, Case-C runtime block); fixed stale citation `:134-147` → `hooks/block-unsafe-project.sh.template:611-630`; added `:714-729` and `:579-606` citations.
- **Files (2):** `skills/run-plan/SKILL.md` (+54/-36) + mirror. Version: `c74b30` → re-bumped post-merge to `bd3dd9`.
- **Tests:** 6708/6708.

## Conflict resolution

#867's rebase hit a version-only conflict on `skills/run-plan/SKILL.md:12` and `.claude/skills/run-plan/SKILL.md:12` — both sides bumped `metadata.version` independently. Resolved by edit-directly (per `feedback_single_region_rebase_conflict_edit_directly`) using my version, then recomputed the post-rebase content hash and re-bumped. No content dropped.

## Sprint metadata

- Sprint pipeline ID: fix-issues.sprint-20260601-014727-dq30m4
- Sprint worktree: /tmp/zskills-fix-issues-sprint-20260601-014727-dq30m4
- Issue claims released cleanly.
- Cron: `*/30 * * * *` — next fire ~30 min.
