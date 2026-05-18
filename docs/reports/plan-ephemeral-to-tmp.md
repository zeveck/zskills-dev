# Plan Report — Route ephemeral test outputs to /tmp

## Phase — 4 Remove wildcard .gitignore + .claude/logs (landed)

**Plan:** plans/EPHEMERAL_TO_TMP.md
**Status:** Landed on main — **PLAN COMPLETE**
**Commit on main:** 86ca2e7

### Work Items
| # | Item | Status |
|---|------|--------|
| 1 | Pre-gate filesystem scan (find, not git status) | PASS — zero leaks |
| 2 | Remove 412b097 wildcard .gitignore (9 lines) | Done |
| 3 | Add .claude/logs/ to .gitignore | Done (line 11, trailing slash) |
| 4 | Final acceptance grep | PASS — all 40 hits intentional |
| 5 | Post-edit clean-tree | PASS — no .test-* in git status after test run |

### Verification
- Scope: `✓ Clean` — only `.gitignore` (1 file)
- Tests: 235/235
- Stale artifacts cleaned: `.test-results.txt` (orchestrator), `.test-results-integration.txt` (Apr 12), `.review-diff.txt` (Apr 13) — all previously hidden by wildcards

## Phase — 3 Hook message + land-phase.sh + regression test (landed)

**Plan:** plans/EPHEMERAL_TO_TMP.md
**Status:** Landed on main
**Commit on main:** 66d9138

### Work Items
| # | Item | Status |
|---|------|--------|
| 1 | Hook error message → TEST_OUT idiom | Done |
| 2 | land-phase.sh /tmp cleanup block | Done (non-fatal, after EPHEMERAL_FILES loop) |
| 3 | tests/test-hooks.sh extended compound assertion | Done (pass count unchanged) |
| 4 | Hook mirror synced | Done |

### Verification
- Scope: `✓ Clean` — 4 files
- Tests: 235/235
- EPHEMERAL_FILES array preserved (contract canary)

## Phase — 2 Update skill recipes + mirrors (landed)

**Plan:** plans/EPHEMERAL_TO_TMP.md
**Status:** Landed on main
**Worktree:** /tmp/zskills-cp-ephemeral-to-tmp-phase-2 (cleaned up)
**Branch:** cp-ephemeral-to-tmp-2 (deleted)
**Commit on main:** d60e6eb (cherry-picked from 8c2cfe5)

### Work Items
| # | Item | Status |
|---|------|--------|
| 1 | skills/run-plan/SKILL.md — hygiene prose, impl recipe ×2, retry, baseline, verifier dispatch, verifier compare, code-comment | Done (23 TEST_OUT refs) |
| 2 | skills/verify-changes/SKILL.md — recipe ×2, prose refs ×3 | Done |
| 3 | skills/investigate/SKILL.md — recipe + prose ref | Done |
| 4 | skills/fix-issues/SKILL.md — remove cleanup .test-results.txt (keep grep filter) | Done |
| 5 | skills/update-zskills/SKILL.md — skipped (only config example, stays as-is per plan) | N/A |
| 6 | All 4 mirrors synced via batch-cp | Done |

### Verification
- Scope: `✓ Clean` — exactly 8 files (4 source + 4 mirror), no scope creep
- Mirror sync: `diff -rq` → all identical
- Acceptance grep: 44 hits, all intentional (new idiom, hygiene prose, fix-issues filter, config example)
- Zero bare writable `> .test-results.txt` redirects remain
- DA1 (verifier cwd): PASS — explicit `<worktree-path>` + orchestrator-runtime note
- DA2 (hygiene canary): PASS — filenames retained in "should NEVER appear" prose
- DA7 (fix-issues filter): PASS — `\.test-results` in grep-v preserved
- Tests: 235/235 passed, 0 failed
- Verifier report: `reports/verify-worktree-zskills-cp-ephemeral-to-tmp-phase-2.md`

## Phase — 1 Update CLAUDE.md + CLAUDE_TEMPLATE.md with canonical idiom (landed)

**Plan:** plans/EPHEMERAL_TO_TMP.md
**Status:** Landed on main
**Worktree:** /tmp/zskills-cp-ephemeral-to-tmp-phase-1 (cleaned up by land-phase.sh)
**Branch:** cp-ephemeral-to-tmp-1 (deleted)
**Commit on main:** 56780f9 (cherry-picked from feature-branch 5bd2b01)

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
- `058b060` — `chore(mirror): re-sync run-plan/SKILL.md mirror (forgotten in 7efd93b)` (housekeeping on main; unblocked Phase 1's test suite)
- `7d07fea` — `chore: mark EPHEMERAL_TO_TMP phase 1 in progress` (tracker 🟡 on main)
- `1111d60` — `docs(reports): EPHEMERAL_TO_TMP phase 1 report (pre-landing)` (report + PLAN_REPORT.md index refresh)
- `56780f9` — `docs: canonical TEST_OUT idiom in CLAUDE.md + CLAUDE_TEMPLATE.md` (cherry-pick of feature-branch 5bd2b01 to main)
- Final tracker update to ✅ Done commits separately via run-plan Phase 6 step 9
