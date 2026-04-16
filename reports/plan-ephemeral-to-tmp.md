# Plan Report — Route ephemeral test outputs to /tmp

## Phase — 1 Update CLAUDE.md + CLAUDE_TEMPLATE.md with canonical idiom [UNFINALIZED]

**Plan:** plans/EPHEMERAL_TO_TMP.md
**Status:** Verified in worktree (cherry-pick pending)
**Worktree:** /tmp/zskills-cp-ephemeral-to-tmp-phase-1
**Branch:** cp-ephemeral-to-tmp-1
**Commit on feature branch:** 5bd2b01

### Work Items
| # | Item | Status |
|---|------|--------|
| 1 | Edit CLAUDE.md:31-34 — replace convention block with 3-line `TEST_OUT` idiom + cwd-safety note | Done |
| 2 | Edit CLAUDE_TEMPLATE.md:42-45 — hardcode `.test-results.txt` (drop `{{TEST_OUTPUT_FILE}}` placeholder — no substitution path existed at `skills/update-zskills/SKILL.md:413-438`) | Done |
| 3 | Verify no other file documents the old convention as guidance | Done — only CLAUDE.md + CLAUDE_TEMPLATE.md (plus plan self-references) match `"Capture test output to a file"` |

### Verification
- Fresh-eyes verifier report: `reports/verify-worktree-zskills-cp-ephemeral-to-tmp-phase-1.md`
- Scope: `✓ Clean` (only CLAUDE.md + CLAUDE_TEMPLATE.md modified)
- Acceptance greps:
  - `grep -n 'TEST_OUTPUT_FILE' CLAUDE_TEMPLATE.md` → 0 matches ✓
  - `grep -rEn "Capture test output to a file" .` → only in CLAUDE.md + CLAUDE_TEMPLATE.md (+ plan self-references) ✓
  - `grep -n 'test-results.txt' CLAUDE.md CLAUDE_TEMPLATE.md` → all hits inside new `"$TEST_OUT/.test-results.txt"` pattern ✓
- Tests: `bash tests/run-all.sh` → 235/235 passed, 0 failed
- Verdict: **PASS** — ready to cherry-pick to main

### Pre-existing blocker resolved
At phase dispatch, `skills/run-plan/SKILL.md` and its `.claude/skills/run-plan/SKILL.md` mirror were out of sync (commit `7efd93b` forgot to mirror). This failed the `test-skill-invariants.sh` mirror-sync check on main (234/235) and blocked Phase 1's "all green" acceptance criterion. Resolved as a separate housekeeping commit (`058b060`) before the worktree was rebased; no scope creep on the feature branch.

### Commits in this phase
- `058b060` — `chore(mirror): re-sync run-plan/SKILL.md mirror (forgotten in 7efd93b)` (housekeeping, on main directly; unblocked Phase 1's test suite)
- `5bd2b01` — `docs: canonical TEST_OUT idiom in CLAUDE.md + CLAUDE_TEMPLATE.md` (on feature branch, pending cherry-pick)
- `7d07fea` — `chore: mark EPHEMERAL_TO_TMP phase 1 in progress` (tracker update on main)
