# Plan Report — Restructure /run-plan and Siblings with Progressive Disclosure

## Close-out — 2026-04-19

**Status:** Complete ✅ (all 5 phases landed).
**Runtime:** 4 chunked cron-fired turns (Phase 1 → 2 → 3 → 4) + 1 validation turn (Phase 5), ~1.5 hours wall.

### Landed commits (main branch)

| Phase | Commit(s) | Skill(s) touched |
|-------|-----------|------------------|
| 1 | `2c62a57` | /commit (417→277 lines, 2 modes) |
| 2 | `bc2bcbd` | /do (669→455, 3 modes) |
| 3 | `8e52a6d` | /fix-issues (1460→1057, 2 modes + 1 reference) |
| 4 | `192fbe9, 8ea4ae8, 6afad52, fefaa7a` (4 atomic sub-commits 4A/4B/4C/4D) | /run-plan (2589→1534, 4 modes + 2 references) |

### Totals

- **Source SKILL.md reduction:** 5135 → 3323 lines (-35%)
- **Extracted files:** 13 (5 in modes/, 2 in references/ for /run-plan; 2 in modes/ for /commit; 3 in modes/ for /do; 2 in modes/ + 1 in references/ for /fix-issues)
- **Byte-preservation:** all 13 extracted files diff-clean against source ranges
- **Tracking-marker invariants:** all four skills hold (pre = post, R3-F1 corrected pattern)
- **`## Key Rules` + `## Edge Cases`:** preserved in every SKILL.md (R3-DA1/2/3 guards held)
- **Test suite (`bash tests/run-all.sh`):** 531/531 PASS post-restructure (4 test-scope drifts fixed inline during Phase 5, see below)

### Deferred canaries (require real GitHub / manual coordination)

These were listed in the plan's Phase 5 but are NOT auto-dispatched — they hit real GitHub state and need user-driven execution:

- **CANARY6 (multi-PR sequential PR mode)** — creates real PRs. Run manually via `/run-plan plans/CANARY6_MULTI_PR.md auto pr` when ready.
- **CI fix-cycle canary** — `/ci-fix-canary` skill, real PR with CI. Run manually.
- **WI 5.5 manual PR-mode spot-check** — throwaway plan + PR + close. Run manually.
- **CANARY10 PR-mode E2E** — explicitly manual per the canary's own flag (`plans/CANARY10_PR_MODE.md:2-3`).

Recommendation: the automated test suite (531/531) validates structural invariants — skill conformance, tracking integration, phase-5b gate, scope halt, canary failure injection. The deferred canaries validate end-to-end GitHub integration, which is the same set of behaviors RESTRUCTURE didn't touch (byte-preservation preserved the underlying logic). Defer unless regression suspicion surfaces.

### Plan-text corrections made during Phase 5

Three acceptance-criterion line-count bands were stale (arithmetically unreachable). Fixed inline per refined Gaps policy:

| Phase | Stale band | Corrected band | Actual |
|-------|------------|----------------|--------|
| 1 | 340-380 | 265-295 (±5% of arithmetic 278) | 277 ✓ |
| 3 | 850-950 | 1010-1115 (±5% of arithmetic 1061) | 1057 ✓ |
| 4 | 700-900 | 1457-1611 (±5% of arithmetic 1534) | 1534 ✓ |

All three were caught by the implementation agents pre-commit and originally logged as "non-blocking plan-text issues." The Gaps policy has been tightened (see plan) to require inline plan-text fixes of this class going forward.

### Test-scope drifts fixed in Phase 5 (4 failures → all PASS)

RESTRUCTURE moved content from SKILL.md files to new mode/reference files. Four tests searched only SKILL.md for content that now lives in mode files:

| Test | Fix |
|------|-----|
| `test-scope-halt.sh` Case 5: `grep -q "⚠️ Flag"` in SKILL.md | Broadened to `grep -qr` across `skills/run-plan/` |
| `test-scope-halt.sh` Case 6: `HALTED` error prefix in SKILL.md | Broadened to `grep -qr` |
| `test-skill-invariants.sh`: `/run-plan halts on scope-violation flag` | Broadened to search whole skill dir |
| `test-canary-failures.sh`: `'Do NOT stash' appears >=2 in COMMIT_SKILL` | Broadened via `find skills/commit -name '*.md'` |

These are not weakened tests — the INTENT (content must exist somewhere in the skill) is preserved; only the SCOPE (where to search) was corrected for post-restructure layout. Changes are in commit that closes Phase 5.

### Process issues surfaced (advisory, for future /refine-plan enhancement)

Three instances of the same class of miss: /refine-plan's adversarial review did not re-derive numeric acceptance targets arithmetically, so stale bands shipped into Phases 1/3/4. Byte-preservation compensated — no incorrect code landed. Layered failure:

1. **/refine-plan** — adversarial reviewer/DA dimensions don't include "numeric target arithmetic verification." Fix: add Dimension 7 to both agents. (Slip-in, ~10 min.)
2. **/run-plan Phase 1 staleness check** — triggers on textual markers only ("drafted before"), not arithmetic drift. Needs design work → deferred to `plans/IMPROVE_STALENESS_DETECTION.md` (to be drafted).
3. **Orchestrator response to agent staleness flags** — implementation agents caught each drift and flagged explicitly; orchestrator logged "non-blocking" instead of updating the plan inline. Policy fix committed in this phase (refined Gaps policy).

### Downstream-plan handoff (WI 5.12)

Two active downstream plans reference specific line numbers/patterns in `/do`, `/fix-issues`, and `/run-plan` that this restructure has moved. Before either plan is executed, run:

- `/refine-plan plans/CREATE_WORKTREE_SKILL.md` — updates citations to `skills/run-plan/SKILL.md:603, :814`, `skills/fix-issues/SKILL.md:809`, `skills/do/SKILL.md:322, :482` → their new mode-file paths.
- `/refine-plan plans/QUICKFIX_SKILL.md` — updates citations to `skills/do/SKILL.md:70-92` (still in place, may drift slightly) and `skills/do/SKILL.md:342-358` → `skills/do/modes/pr.md`.

Both plans already tolerate the move (CREATE_WORKTREE explicitly documents coordination with RESTRUCTURE; QUICKFIX cites idioms semantically). The refinement is line-number maintenance, not architectural.

### Execution order from here

User-confirmed sequence:

1. ✅ Phase 5 close-out (this)
2. Next: slip in /refine-plan arithmetic-verification fix (Path A per earlier plan)
3. Next: draft `plans/IMPROVE_STALENESS_DETECTION.md` for /run-plan changes
4. Then: run that plan via /run-plan

---

## Phase 4 — /run-plan restructure (4 atomic sub-commits)

**Plan:** plans/RESTRUCTURE_RUN_PLAN.md
**Status:** Landed ✅
**Worktree:** /tmp/zskills-cp-restructure-run-plan-phase-4 (cleaned)
**Branch:** cp-restructure-run-plan-4 (deleted post-land)
**Commits (cherry-picked in order 4A→4B→4C→4D):**
- **4A** `192fbe9` — `refactor(run-plan): extract finish-mode and failure-protocol to references/`
- **4B** `8ea4ae8` — `refactor(run-plan): extract direct, delegate, cherry-pick landing modes to modes/`
- **4C** `6afad52` — `refactor(run-plan): extract PR landing mode to modes/pr.md`
- **4D** `fefaa7a` — `refactor(run-plan): tidy Phase 6 dispatch, update cross-reference, mirror install`

**Post-land test gate:** `bash tests/test-hooks.sh` → 219/219 passed

### Extraction summary

| Sub-commit | Destination | Source range | Lines |
|-----------|-------------|-------------:|------:|
| 4A | references/finish-mode.md | 1384..1543 | 163 (incl. 3-line header) |
| 4A | references/failure-protocol.md | 2460..2555 | 99 |
| 4B | modes/direct.md | 1547..1553 | 10 |
| 4B | modes/delegate.md | 1554..1566 | 16 |
| 4B | modes/cherry-pick.md | 1567..1710 | 147 |
| 4C | modes/pr.md | 1711..2371 | 664 |
| **Total extracted** | | | **1099 lines** |

### Post-edit line counts

| File | Before | After |
|------|-------:|------:|
| skills/run-plan/SKILL.md | 2589 | 1534 |
| skills/run-plan/modes/direct.md | — | 10 |
| skills/run-plan/modes/delegate.md | — | 16 |
| skills/run-plan/modes/cherry-pick.md | — | 147 |
| skills/run-plan/modes/pr.md | — | 664 |
| skills/run-plan/references/finish-mode.md | — | 163 |
| skills/run-plan/references/failure-protocol.md | — | 99 |

### Invariants

| Check | Result |
|-------|--------|
| Byte-preservation (all 6 extracted files) | PASS — all diffs empty |
| `^## Key Rules` count in SKILL.md | PASS — 1 (R3-DA2 guard held) |
| `^## Edge Cases` count in SKILL.md | PASS — 1 (R3-DA2 guard held) |
| Tracking invariant (R3-F1 corrected pattern) | PASS — PRE=49 POST=49 |
| Semantic tracking check (R3-F6) | PASS — positive=12, negative=0 (no hardcoded pipeline IDs) |
| Mirror `diff -r skills/run-plan .claude/skills/run-plan` | PASS — empty |
| Mirror `diff -r skills/fix-issues .claude/skills/fix-issues` | PASS — empty |
| 4D.2 cross-ref update (R3-F4, R3-DA5 hardened) | PASS — PRE_OLD=1 → POST_OLD=0, POST_NEW=1, POST_ANY stable at 1 |
| Frontmatter byte-identical to pre-edit | PASS |

### Plan-text issues flagged (non-blocking — for future /refine-plan round 2)

1. **Plan acceptance criterion "SKILL.md 700–900 lines" is unreachable within Phase 4 scope.** Phase 4 extracts 1099 lines (close to the plan's "~1200" estimate), leaving ~1534 in SKILL.md. The 700–900 target would require extracting Phases 1-5 (~1100 lines: Phase 1 Parse, Phase 2 Implement, Phase 3 Verify, Phase 4 Update Tracker, Phase 5 Write Report) — but plan Design & Constraints explicitly keeps those IN SKILL.md ("orchestration — stays"). Third consecutive phase where the acceptance line-count band is arithmetically stale (Phase 1 was 340-380 → actual 277; Phase 3 was 850-950 → actual 1057; Phase 4 is 700-900 → actual 1534). Byte-preservation is the authoritative invariant and held throughout.
2. **Mode files end with the next section's `###` heading** (e.g., `modes/direct.md` ends with `### Delegate mode landing`). This is the natural outcome of the plan's contiguous-byte-preservation rule (each range terminates at the next heading). Semantically unusual but correctness-preserving. Consider a cosmetic cleanup pass in a follow-up plan if desired.
3. **`.landed` intro trap** — the implementation agent initially wrote `modes/pr.md`'s intro containing the literal `.landed`, which bumped the R3-F1 tracking-marker count by 1. Rephrased to "clean-tree rebases, CI polling with fix cycles, auto-merge request, and post-merge status upgrade". This is the third phase where the intro-drift guard caught a near-miss — worth documenting as a permanent rule for mode/reference file intros.

### Downstream-plan impact

- **Cross-reference update** at `skills/fix-issues/modes/pr.md` line 119: now points at `skills/run-plan/modes/pr.md` (was `skills/run-plan/SKILL.md`). Phase 3's byte-preservation preserved the original; Phase 4D.2 rewrote it.
- **QUICKFIX_SKILL.md and CREATE_WORKTREE_SKILL.md** now have stale line-number citations (they reference specific lines in `/do`, `/fix-issues`, `/run-plan` that have moved into modes/*.md and references/*.md). Phase 5 WI 5.12 will document this in the close-out handoff report.

---

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
