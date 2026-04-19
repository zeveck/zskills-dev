# Plan Report — Restructure /run-plan and Siblings with Progressive Disclosure

## Phase 1 — /commit restructure [UNFINALIZED]

**Plan:** plans/RESTRUCTURE_RUN_PLAN.md
**Status:** Verified (pending land)
**Worktree:** /tmp/zskills-cp-restructure-run-plan-phase-1
**Branch:** cp-restructure-run-plan-1
**Commits:** e695d66 — `refactor(commit): extract pr and land modes to modes/`

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1.1 | Create skills/commit/modes/ | Done | |
| 1.2 | Extract PR subcommand → modes/pr.md | Done | 97 lines (3-line header + body lines 235-328) |
| 1.3 | Extract Land section → modes/land.md | Done | 63 lines; ends at 388 (Key Rules at 389 preserved) |
| 1.4 | Dispatch stubs in SKILL.md | Done | Both use active "Read … in full" |
| 1.5 | Arguments-section cross-ref | Done | |
| 1.6 | Pre-edit original captured | Done | /tmp/commit-original.md, 417 lines |
| 1.6b | Byte-preservation pr.md | PASS | `diff` empty |
| 1.6c | Byte-preservation land.md | PASS | `diff` empty; `## Key Rules` count = 1 |
| 1.6d | Header structure | PASS | H1 + blank + ≤25-word sentence ending in `.` |
| 1.6e | Tracking-marker invariant | PASS | PRE=3 POST=3 (R3-F1 corrected pattern) |
| 1.7 | Mirror to .claude/skills/commit/ | Done | `diff -r` empty |
| 1.8 | /commit smoke test | Deferred | Covered by Phase 5 canaries |
| 1.9 | Commit created by verifier | Done | e695d66 |

### Verification

Independent verification agent (commit `e695d66` on `cp-restructure-run-plan-1`):
- Byte-preservation: both mode files diff-clean against original lines 235-328 and 329-388.
- `## Key Rules` preserved in SKILL.md (R3-DA1 guard held).
- Tracking-marker invariant: PRE=3 POST=3 (verified section-by-section, not coincidental).
- Mirror `diff -r` empty.
- 6 files staged; `.worktreepurpose` / `.zskills-tracked` correctly untracked (gitignored).

### Post-edit line counts

| File | Before | After |
|------|-------:|------:|
| skills/commit/SKILL.md | 417 | 277 |
| skills/commit/modes/pr.md | — | 97 |
| skills/commit/modes/land.md | — | 63 |

### Plan-text issues flagged (non-blocking — for future /refine-plan round)

1. **Acceptance criterion line-count band (340–380) is stale.** Correct arithmetic: `417 - (94 extracted to pr.md) - (60 extracted to land.md) + (~15 dispatch stubs) ≈ 278`. Actual 277 is structurally correct. Plan's 340–380 band appears to have been authored before exact boundaries were fixed.
2. **WI 1.6d sub-rule "line 4 must NOT start with `## `" conflicts with byte-preservation.** The extracted body's first line is a `## Phase N` heading, so line 4 of each mode file IS `## `. Byte-preservation is primary; accept as known inconsistency until the plan reconciles.

Both are plan-text issues, not implementation defects. Implementation is correct.
