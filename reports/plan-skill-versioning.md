# Plan Report — Skill Versioning

## Phase — 2 Tooling [UNFINALIZED]

**Plan:** plans/SKILL_VERSIONING.md
**Status:** Completed (verified inline)
**Worktree:** /tmp/zskills-pr-skill-versioning
**Branch:** feat/skill-versioning
**Commit:** 27effe5

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 2.1 | `scripts/frontmatter-get.sh` | Done | 251L; supports stdin `-`, dotted keys, block-scalar reads |
| 2.2 | `scripts/frontmatter-set.sh` | Done | 300L; idempotent, atomic mv, mode-preserving; exit 3 on block-scalar overwrite |
| 2.3 | `scripts/skill-content-hash.sh` | Done | 276L; first exec line `export LC_ALL=C`; canonical projection per §1.1; rejects binary; outputs 6-char sha256 |
| 2.4 | `tests/test-frontmatter-helpers.sh` | Done | 30 cases (≥26 required); fixtures under `tests/fixtures/frontmatter/` (7 files) |
| 2.5 | `tests/test-skill-content-hash.sh` | Done | 8 cases including dotfile invariance + block-scalar continuation safety; fixtures under `tests/fixtures/skill-versioning/` (5 dirs) |
| 2.6 | Register in `tests/run-all.sh` | Done | Both files alphabetically placed |
| 2.7 | Smoke recipe in `references/skill-versioning.md` §1.10 | Done | Appended block; uses `/tmp` copy (no real-skill mutation) |
| 2.8 | Commit message | Done | `feat(scripts): add frontmatter-get/set/skill-content-hash helpers + tests for skill versioning` |

### Verification

- AC #1 — All 3 scripts executable: **OK**
- AC #2 — `bash -n` syntax-clean: **OK** (all 3)
- AC #3 — `tests/test-frontmatter-helpers.sh`: **30/30 PASS** (≥26 required)
- AC #4 — `tests/test-skill-content-hash.sh`: **8/8 PASS** (≥6 required, spec also asks for 8)
- AC #5 — `grep -c` for new tests in run-all.sh: **2**
- AC #6 — `frontmatter-get skills/run-plan/SKILL.md name` → **`run-plan`**
- AC #7 — Stdin form → **`run-plan`**
- AC #8 — `skill-content-hash skills/run-plan` → **`0c846e`** matches `^[0-9a-f]{6}$`
- AC #9 — Determinism: **0c846e == 0c846e**
- AC #10 — `grep -c jq` on all 5 files: **0** (all)
- AC #11 — `bash tests/run-all.sh`: **1845/1845 PASS, 0 failed** (+38 vs 1807 baseline)
- AC #12 — Round-trip property: **5/5** cases pass

Verifier subagent prone to Monitor anti-pattern; orchestrator did verification inline with proper `timeout: 600000` foreground bash.

### Plan-text drift signals

None.

### Cross-phase dependencies

- Phase 1 (`references/skill-versioning.md` §1.10) — naming contract satisfied; smoke recipe appended.
- Phases 3-6 will rely on these helpers; they are now stable + tested.

### Next phase

Phase 3 — Migration: seed all 26 core + 3 add-on skills via two-pass migration; extend conformance test. Scheduled via `*/1` cron with adaptive backoff.

---

## Phase — 1 Decision & Specification [UNFINALIZED]

**Plan:** plans/SKILL_VERSIONING.md
**Status:** Completed (verified inline)
**Worktree:** /tmp/zskills-pr-skill-versioning
**Branch:** feat/skill-versioning
**Commit:** 8133bde

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1.1 | Author `references/skill-versioning.md` covering §1.1–§1.11 verbatim | Done | 287 lines; 11 H2 sections + Appendix A (regex) + Appendix B (canonical hash-input rule) |
| 1.2 | Append `## Skill versioning` paragraph to `CLAUDE.md` | Done | Verbatim from plan work item 1.2; added at line 169 |
| 1.3 | Verify SKILL_VERSIONING in PLAN_INDEX.md (idempotent) | Done | Row already present at line 17 (no edit needed) |

### Verification

- AC #1 — `grep -c '^## 1\.' references/skill-versioning.md`: **11** (≥11 required)
- AC #2 — `grep -c 'Trade-offs considered' references/skill-versioning.md`: **11** (≥11 required)
- AC #3 — `grep -q '^## Skill versioning' CLAUDE.md`: **OK** (exit 0)
- AC #4 — `grep -q 'SKILL_VERSIONING' plans/PLAN_INDEX.md`: **OK** (exit 0)
- AC #5 — `git diff --stat` scope: **OK** (only `CLAUDE.md` modified, `references/skill-versioning.md` new; no edits to skills/, block-diagram/, tests/, hooks/, scripts/)
- AC #6 — `bash tests/run-all.sh`: **PASS** (1807/1807 tests pass, 0 failed, 0 skipped)

Verifier subagent hit the known Monitor anti-pattern (subagents can't reliably wait on backgrounded Bash); orchestrator did verification inline with proper foreground `timeout: 600000`. All 6 ACs independently verified before commit.

### Plan-text drift signals

```
PLAN-TEXT-DRIFT: phase=1 bullet=1.1 field=trade-offs-block-coverage plan="each section ends with a 2-3 line 'Trade-offs considered' block" actual="source plan §1.6 (Mirror interaction) lacks a 'Trade-offs considered' block; 10 of 11 §1.x sections in source have one"
```

**Disposition:** Non-derivable (no numeric target); Phase 3.5 logged as informational, no auto-correct attempted. Implementer synthesized a Trade-offs block for §1.6 in `references/skill-versioning.md` to satisfy AC #2 (the synthesis covers the rejected alternatives "extend the mirror script's allow-list" and "migrate the two mirror-only skills now"). The synthesized block is judgment-class but uncontroversial. Recommendation: backfill source plan §1.6 with the same block in a future refine-plan pass for consistency.

### Cross-phase dependencies

None — Phase 1 is the foundational decision phase. The reference doc is now the single source of truth that Phases 2-6 cite by section anchor.

### Next phase

Phase 2 — Tooling (`frontmatter-get.sh`, `frontmatter-set.sh`, `skill-content-hash.sh` + tests). Scheduled via cron per `finish auto` chunked execution.
