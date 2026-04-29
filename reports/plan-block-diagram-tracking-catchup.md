# Plan Report — Block-Diagram Tracking-Naming Catch-up

## Phase — 2 Lint guard + canary cases for block-diagram [UNFINALIZED]

**Plan:** plans/BLOCK_DIAGRAM_TRACKING_CATCHUP.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-block-diagram-tracking-catchup
**Branch:** feat/block-diagram-tracking-catchup
**Commits:** 6662368

### Work Items

| # | Item | Status | Commit |
|---|------|--------|--------|
| 1 | Baseline grep `> "[^"]*\.zskills/tracking/[a-zA-Z]'` in `skills/` + `block-diagram/` returns 0 (Phase 1 migration verified clean) | Done | 6662368 |
| 2 | Cross-skill invariant lint added to `tests/test-skill-invariants.sh` (post-`isolation: "worktree"` check) | Done | 6662368 |
| 3 | Manual lint smoke: revert one Phase 1 site → lint fails (exit 1, FAIL line); restore → lint passes (exit 0) | Done | 6662368 |
| 4 | Canary case 9 — `block-diagram delegation pair: requires + fulfilled co-located in PIPELINE_ID subdir → allow` | Done | 6662368 |
| 5 | Canary case 10 — `block-diagram missing fulfillment: requires.add-example.Integrator unfulfilled → deny` | Done | 6662368 |
| 6 | Canary case 11 — `block-diagram cross-name isolation: Gain not blocked by Integrator's unmet requires` | Done | 6662368 |
| 7 | Section header in `tests/test-canary-failures.sh` updated `(8 cases)` → `(11 cases)` | Done | 6662368 |

### Verification

- **Test suite:** PASSED (975/975 in verifier session). Phase 1's `parity: worktrees` host-environment flake did not reproduce.
- **Acceptance criteria:**
  - Baseline grep returns 0 ✓
  - Lint phrase present (≥1 line; actual 2 — auto-corrected from stale "1 line" in AC2 because the verbatim insert block contains the phrase in both the header comment and the check description) ✓
  - Manual lint smoke independently re-run by verifier: PASS → revert site → FAIL with lint diagnostic → restore → PASS, with `git diff block-diagram/` clean afterward ✓
  - Section header `(11 cases)` exactly 1 line ✓
  - 3 new cases pass with PASS lines ✓
  - Pre/post canary count delta = 3 (101 → 104) ✓
  - Full suite green ✓

### Plan-text drift auto-corrected

- **AC2 (lint phrase grep count):** `1 line` → `≥1 line`. Reason: the verbatim insert block specified by Work Item 2 contains the phrase `no skill writes flat-layout tracking markers` in both the header comment and the check description string. A faithful insertion produces 2 matches, not 1. The lint is functionally correct; only the AC verification command's expected count was stale. Inline audit comment recorded next to the AC.

### Notes

- Branch is rebased onto `7afd6f0` (the main HEAD captured at start of Phase 2). Main has since advanced again (zskills-monitor-plan Phase 4 landed during this turn). Final-phase landing will need a fresh rebase before push — handled by Phase 3's run.

## Phase — 1 Migrate add-block + add-example writers (paired) [UNFINALIZED]

**Plan:** plans/BLOCK_DIAGRAM_TRACKING_CATCHUP.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-block-diagram-tracking-catchup
**Branch:** feat/block-diagram-tracking-catchup
**Commits:** 0e9c37e

### Work Items

| # | Item | Status | Commit |
|---|------|--------|--------|
| 1 | Pre-tracking caller cleanup at SKILL.md:16,20 (`scripts/create-worktree.sh` → `.claude/skills/create-worktree/scripts/create-worktree.sh`) | Done | 0e9c37e |
| 2 | add-block: Top-of-skill PIPELINE_ID resolution + BLOCK_SLUG | Done | 0e9c37e |
| 3 | add-block: 12 tracking sites migrated to `$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/` subdir layout | Done | 0e9c37e |
| 4 | add-block: 2 sanitizer calls via `.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh` (PIPELINE_ID + BLOCK_SLUG) | Done | 0e9c37e |
| 5 | add-block: Delegation contract pinned (NAME == BLOCK_NAME), worked example for whitespace-bearing identifiers | Done | 0e9c37e |
| 6 | add-block: Batch-mode aggregate `requires.add-example.${BLOCK_SLUG}` prose | Done | 0e9c37e |
| 7 | add-example: Top-of-skill 3-tier PIPELINE_ID resolver (env → `.zskills-tracked` → `add-example.${NAME}`) + NAME_SLUG | Done | 0e9c37e |
| 8 | add-example: 7 tracking sites migrated to subdir layout | Done | 0e9c37e |
| 9 | add-example: 2 sanitizer calls (PIPELINE_ID + NAME_SLUG) | Done | 0e9c37e |
| 10 | add-example: Tier-3 fallback (no exit-1 on missing PIPELINE_ID) — supports standalone use | Done | 0e9c37e |

### Verification

- **Test suite:** PASSED (943/943 in verifier session). One transient `parity: worktrees` flake observed in implementer session; verifier reproduced 943/943 PASS and confirmed test source has no `block-diagram/` references — pre-existing host-environment flake from concurrent worktree mutations during the test run, not a regression.
- **Acceptance criteria (all 14 + dry-run):**
  - Zero flat writes ✓
  - add-block subdir-write count = 12 ✓
  - add-example subdir-write count = 7 ✓
  - Sanitizer calls = 2/2 ✓
  - No pre-#97 sanitizer or create-worktree paths ✓
  - BLOCK_SLUG / NAME_SLUG present ✓
  - ZSKILLS_PIPELINE_ID block in both ✓
  - add-example tier-3 fallback present, no hard-error exit ✓
  - No mirror sync edits ✓
  - No new sanitizer file ✓
  - No migrate-tracking helper ✓
  - All 28 fenced bash blocks compile (`bash -n`) ✓
- **Delegation dry-run:** 5/5 expected paths produced exactly:
  - `add-block.Gain/{requires,fulfilled}.add-example.Gain` (Case A: clean ID, parent/child pair-match)
  - `add-block.My_Block/{requires,fulfilled}.add-example.My_Block` (Case B: whitespace ID `My Block`, sanitised slug pair-matches)
  - `add-example.Integrator/fulfilled.add-example.Integrator` (Case C: standalone, tier-3 fallback)

### Notes

- `block-diagram/` is NOT mirrored to `.claude/skills/`, so no mirror sync was needed (Shared Conventions). Verified: `grep -c '^\.claude/skills/'` on diff → 0.
- `parity: worktrees` flake (impl session) was caused by transient `cw-smoke-*` worktrees spawned by `tests/test-create-worktree.sh` interleaving between node and python `git worktree list` calls. Re-running tests in the verifier session showed 943/943 pass — flake is environmental and pre-dates this change. Not failing verification.
