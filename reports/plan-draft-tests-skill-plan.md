# Plan Report — /draft-tests Skill

## Phase — 1 Skeleton, ingestion, and checksum gate

**Plan:** plans/DRAFT_TESTS_SKILL_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-draft-tests-skill-plan
**Branch:** feat/draft-tests-skill-plan
**Commits:** 2cf6897, 5201b8e

### Work Items

| # | Item | Status | Commit |
|---|------|--------|--------|
| 1.1 | `skills/draft-tests/SKILL.md` with frontmatter (`name`, `disable-model-invocation`, `argument-hint` incl. `[guidance...]`, description) | Done | 2cf6897 |
| 1.2 | Argument parsing: plan-file detection, `rounds N`, guidance text join with usage-string error | Done | 2cf6897 |
| 1.3 | Tracking fulfillment via canonical idiom + per-pipeline subdir + cross-skill `sanitize-pipeline-id.sh` form (bare-relative form refused) | Done | 2cf6897 |
| 1.4 | Plan-file parser: frontmatter, Progress Tracker, phase classification (Done/✅/[x] vs Pending) | Done | 2cf6897 |
| 1.4b | Per-Pending-phase delegate vs non-delegate predicate; `delegate_phases:` and `non_delegate_pending_phases:` lists in parsed-state | Done | 2cf6897 |
| 1.5 | SHA-256 checksum per Completed phase with broad-form section-boundary rule (any `## <name>` outside fenced code blocks) AND fenced-code-block awareness | Done | 2cf6897 |
| 1.6 | AC-ID assignment with three-predicate classifier (canonical-skip, ambiguous-refuse-with-advisory, plain-assign) | Done | 2cf6897 |
| 1.7b | Pending phases without `### Acceptance Criteria` block recorded in `ac_less:` and retained in `non_delegate_pending_phases:`, advisory emitted | Done | 2cf6897 |
| 1.7 | Refuse-to-run checks: missing plan / missing tracker → error; all-Completed → continue (route to backfill, not exit) | Done | 2cf6897 |

### Verification
- Test suite: **1275/1275 passed, 0 failed** (baseline 1213/1213; +62 new tests in `tests/test-draft-tests.sh`).
- Per-AC verification (AC-1.1 through AC-1.7b): all PASS, independently re-checked by a fresh verification agent against fixture plans.
- Source/mirror parity: `diff -rq skills/draft-tests/ .claude/skills/draft-tests/` clean.
- Conformance suite: 170/170; invariants suite: 36/36.
- Plan-text drift: zero `PLAN-TEXT-DRIFT:` tokens from either implementation or verification agent.

### Implementation notes
- `parse-plan.sh` factored under `skills/draft-tests/scripts/` because Phase 1's mechanics (parse, classify, checksum, AC-ID, ac-less detection) are far more deterministic than `/refine-plan`'s prose-only architecture. Registered Tier 1 in `skills/update-zskills/references/script-ownership.md` (16 entries) and added to `STALE_LIST` in `update-zskills/SKILL.md` so consumer checkouts will not retain bare-relative copies.
- 7 fixture plans under `tests/fixtures/draft-tests/` cover mixed-status, trailing-sections, fenced-headings, ambiguous-prefixes, all-completed, ac-less-and-normal, and no-tracker scenarios.
- The fenced-code-block-aware section-boundary scan is the load-bearing checksum invariant; the regression fixture `fenced-headings.md` proves the awk-style state-tracker correctly skips `## ` headings inside ` ``` ` fences and includes the fenced bytes in the checksummed span.
- Phases 2–6 are stubbed in SKILL.md with deferral notes; the architectural hooks for Phase 3's `### Tests` skip on `ac_less:` phases and Phase 4's coverage-floor exclusion of ac-less phases are documented inline so downstream phases can wire to the single source of truth.
