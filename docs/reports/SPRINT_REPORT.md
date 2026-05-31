---
title: /fix-issues Sprint Report
status: complete
---

# /fix-issues sprint — sprint-20260531-165117-dtsplit

**Mode:** N=1, auto, every 2h, cron-fired sprint
**Started:** 2026-05-31T16:04:22-04:00 (sprint dispatched 2026-05-31 16:51 UTC; completed after one rate-limit recovery + post-split conformance fix cycle)
**Open issues at sprint start:** 5 (#67, #832, #833, #835, #836)
**Skip-tagged:** 3 (#67 deferred; #832, #833 needs-decision)
**Newly researched:** 0 (#836 closed by a parallel session between fires)
**Actionable picks:** 1 (#835)

## Landed this fire

### #835 — /draft-tests SKILL.md split
- **PR:** https://github.com/zeveck/zskills-dev/pull/855 (merged, CI pass on rebase, BEHIND → CLEAN after force-push)
- **Branch:** `feat/do-drafttests-split`
- **Commit:** `b47dc6a` (rebased atop #854 + #851)
- **Files (19):** `skills/draft-tests/SKILL.md` slimmed 2072 → 233 lines; 3 new `modes/` files (draft 1096, backfill 421, land 246) and 2 new `references/` files (test-spec-format 130, design-constraints 71); mirror copies under `.claude/skills/draft-tests/`. Plus 7 test files updated to the post-split conformance pattern (5 draft-tests test files + test-skill-conformance.sh + test-skill-invariants.sh).
- **Tests:** `bash tests/run-all.sh` — 6574/6574 passed (0 failed, 0 skipped). Initial run had 69 post-split conformance failures (all root-caused to tests grep'ing SKILL.md for content that moved to modes/); resolved via the conformance test updates.
- **Skill version bump:** `skills/draft-tests/SKILL.md` (+ mirror) bumped to `2026.05.31+57c781`.

## Sprint mechanics notes

- **Rate-limit recovery:** The first implementer agent dispatch hit an Anthropic rate limit after ~52 tool uses with the bulk of the split done (slim SKILL.md + 5 split files + mirrors). The orchestrator resumed inline — ran the test suite, identified the 69 conformance failures, fixed them by adding the `skill_grep()` helper to the 5 draft-tests test files (modeled on `tests/test-fix-issues.sh:34`'s post-split pattern), added 3 entries to `test-skill-invariants.sh`'s `ISSUE_606_ALLOWLIST` for the new mode files, and retargeted the `LAND_PR_CALLERS` entry in `test-skill-conformance.sh` from `skills/draft-tests/SKILL.md` to `skills/draft-tests/modes/land.md`. Total: 1 implementer agent + ~5 orchestrator-level conformance fixes.
- **Auto-rebase fire:** Post-CI-green, the PR was BEHIND because `origin/main` advanced (#851 + #854 landed during the run). Rebased + `git push --force-with-lease`; CI re-ran green on the new SHA; auto-merge fired cleanly.

## Sidefinding follow-up (from last fire — closed)

The `test-plans-render-index.sh` sidefinding from sprint 20260531-143854 was fixed in commit `0916480` ("test(backfill): run backfill in a throwaway clone so the test never mutates live docs/plans"). Cycle from surfacing → fix in one sprint cycle — good.

## Open backlog

- **#67, #832, #833** — skip-tagged.
- #836 closed by parallel session before this fire dispatched it.
- No new issues require action.

## Sprint metadata

- Sprint pipeline ID: fix-issues.sprint-20260531-165117-dtsplit
- Sprint worktree: /tmp/zskills-fix-issues-sprint-20260531-165117-dtsplit
- Issue claim for #835 acquired and released cleanly.
- Cron: `36 */2 * * *` — next fire ~2h.
