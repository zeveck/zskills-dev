# Plan Report — Restructure /run-plan and Siblings with Progressive Disclosure

## Phase 3 — /fix-issues restructure

**Plan:** plans/RESTRUCTURE_RUN_PLAN.md
**Status:** Landed ✅
**Worktree:** /tmp/zskills-cp-restructure-run-plan-phase-3 (cleaned)
**Branch:** cp-restructure-run-plan-3 (deleted post-land)
**Commits:** a0cea66 (worktree) → 8e52a6d (main)
**Post-land test gate:** `bash tests/test-hooks.sh` → 219/219 passed

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 3.1 | Create modes/ + references/ | Done | |
| 3.4 | Extract cherry-pick body → modes/cherry-pick.md | Done | 131 lines; orig 982-1109 byte-identical |
| 3.4b | Extract PR body → modes/pr.md | Done | 174 lines; orig 1110-1280 byte-identical; cross-reference at line 119 preserved verbatim |
| 3.5 | Extract Failure Protocol → references/failure-protocol.md | Done | 125 lines; orig 1299-1420 (terminated at Key Rules-1 per R3-DA3) |
| 3.6 | Phase 6 dispatch stub | Done | Preamble (964-981) + Post-land tracking (1281-1298) preserved |
| 3.7 | Failure Protocol stub | Done | |
| 3.8 | Byte-preservation + headers | PASS | All 3 diffs empty; headers 17/18/23 words ending in `.` |
| 3.8b | Tracking invariant (R3-F1) | PASS | PRE=36 POST=36 |
| 3.10 | Mirror `diff -r` | Done | Empty |
| — | `## Key Rules` preserved (R3-DA3) | PASS | count=1 |
| — | `worktree-add-safe.sh` in SKILL.md | PASS | Line 809 (inside Phase 3 Execute, not touched) — intact for CREATE_WORKTREE Phase 2 migration |
| — | Cross-reference `skills/run-plan/SKILL.md` in modes/pr.md | PASS | Line 119 preserved; Phase 4D.2 will rewrite to `modes/pr.md` |

### Post-edit line counts

| File | Before | After |
|------|-------:|------:|
| skills/fix-issues/SKILL.md | 1460 | 1057 |
| skills/fix-issues/modes/cherry-pick.md | — | 131 |
| skills/fix-issues/modes/pr.md | — | 174 |
| skills/fix-issues/references/failure-protocol.md | — | 125 |

Plan-target band was 850-950 — actual 1057 is a plan arithmetic approximation (similar to Phase 1). Byte-preservation (authoritative) passed.

### Downstream-plan idiom preservation

- **Worktree-creation block** at original fix-issues:791-814 (cited by `plans/CREATE_WORKTREE_SKILL.md` WI 3.1): preserved in-place at line 809 in post-edit SKILL.md (block is inside Phase 3 Execute, not touched by this restructure). CREATE_WORKTREE's migration target remains contiguous at one path.
- **Cross-reference to /run-plan PR-mode** at original fix-issues:1225: preserved verbatim at `skills/fix-issues/modes/pr.md:119`. Phase 4 WI 4D.2 will rewrite it to point at `skills/run-plan/modes/pr.md`.

---

## Phase 2 — /do restructure

**Plan:** plans/RESTRUCTURE_RUN_PLAN.md
**Status:** Landed ✅
**Worktree:** /tmp/zskills-cp-restructure-run-plan-phase-2 (cleaned)
**Branch:** cp-restructure-run-plan-2 (deleted post-land)
**Commits:** db5619a (worktree) → bc2bcbd (cherry-picked to main)
**Post-land test gate:** `bash tests/test-hooks.sh` → 219/219 passed

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 2.1 | Create skills/do/modes/ | Done | |
| 2.3 | Extract Path A → modes/pr.md | Done | 183 lines; body = orig 283-462 byte-identical |
| 2.4 | Extract Path B → modes/worktree.md | Done | 27 lines; body = orig 463-486 byte-identical |
| 2.5 | Extract Path C → modes/direct.md | Done | 21 lines; body = orig 487-504 byte-identical |
| 2.6 | Dispatch stub in Phase 2 SKILL.md | Done | Routing table: pr→A, worktree→B, neither→C |
| 2.7 | Phase 3/4/5 bodies preserved in SKILL.md | Done | R3-F2 commitment honored |
| 2.8 | Byte-preservation + headers | PASS | All 3 diffs empty; headers 19/16/16 words ending in `.` |
| 2.8b | Tracking-marker invariant | PASS | PRE=9 POST=9 (R3-F1 pattern) |
| 2.9 | Mirror to .claude/skills/do/ | Done | `diff -r` empty |
| — | `## Key Rules` preserved | PASS | count=1 |
| — | Argument-parser idiom preserved (lines 70-92) | PASS | `LANDING_MODE="pr"` still at original location |

### Post-edit line counts

| File | Before | After |
|------|-------:|------:|
| skills/do/SKILL.md | 669 | 455 |
| skills/do/modes/pr.md | — | 183 |
| skills/do/modes/worktree.md | — | 27 |
| skills/do/modes/direct.md | — | 21 |

### Downstream-plan idiom preservation (per user's refinement focus)

- **Argument-parser idiom** at `skills/do/SKILL.md` lines ~70-92 (cited by `plans/QUICKFIX_SKILL.md` WI 1.2 and `plans/CREATE_WORKTREE_SKILL.md` WI 1a.2): **preserved in place** — stays in SKILL.md, not extracted.
- **Agent-dispatch idiom** at original `skills/do/SKILL.md:342-358` (cited by QUICKFIX WI 1.11): now at `skills/do/modes/pr.md` inside Step A6 "Dispatch implementation agent" — byte-preserved. QUICKFIX's line reference becomes stale; Phase 5 WI 5.12 will document the handoff.
- **Worktree-creation site** at original `skills/do/SKILL.md:322` (PR-mode, cited by CREATE_WORKTREE WI 3.2): now at `skills/do/modes/pr.md`.
- **Worktree-creation site** at original `skills/do/SKILL.md:482` (worktree-mode, cited by CREATE_WORKTREE WI 3.3): now at `skills/do/modes/worktree.md`.

---

## Phase 1 — /commit restructure

**Plan:** plans/RESTRUCTURE_RUN_PLAN.md
**Status:** Landed ✅
**Worktree:** /tmp/zskills-cp-restructure-run-plan-phase-1 (cleaned)
**Branch:** cp-restructure-run-plan-1 (deleted post-land)
**Commits:** e695d66 (worktree) → 2c62a57 (cherry-picked to main)
**Post-land test gate:** `bash tests/test-hooks.sh` → 219/219 passed

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
