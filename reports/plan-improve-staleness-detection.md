# Plan Report — Improve /run-plan Staleness Detection (Arithmetic Drift)

## Phase — 2 Post-implement auto-correct gate (Phase 3.5) [UNFINALIZED]

**Plan:** plans/IMPROVE_STALENESS_DETECTION.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-improve-staleness-detection
**Branch:** feat/improve-staleness-detection
**Commits:** e370ab9 (impl + tests), e5f3128 (tracker mark in-progress)

### Work Items

| # | Item | Status | Source |
|---|------|--------|--------|
| 2.1 | New `## Phase 3.5` H2 section in skills/run-plan/SKILL.md | Done | e370ab9 |
| 2.2 | Verbatim Phase 3.5 content (8 numbered subsections, 5-row decision table) | Done | e370ab9 |
| 2.3 | Phase 4 opening prose blockquote referencing Phase 3.5 | Done | e370ab9 |
| 2.4 | Mirror parity (per-file cp) | Done | e370ab9 |
| 2.5 | 5 new integration test cases for Phase 3.5 orchestration (e2e, thrash, escalate, multi) | Done | e370ab9 |
| 2.6 | Commit | Done | e370ab9 |

### Verification

- Test suite: PASSED (902/902, +5 from Phase 1 baseline 897)
- All 8 acceptance criteria verified by independent verification agent
- Mirror clean: `diff -r skills/run-plan .claude/skills/run-plan` empty
- Phase 3.5 H2 inserted at line 1233 (between Phase 3's `### Post-verification tracking` and `## Phase 4`)
- Decision-table 5 rows verbatim (≤10%, 10-20%, >20%, byte-pres failed, unsupported)
- DELETE-verify-on-failure rule documented; thrash rule scoped per-execution
- `^## Phase ` count: main 10 → branch 11 (Δ=+1, the new Phase 3.5)

### PLAN-TEXT-DRIFT findings

None against Phase 2 acceptance criteria. Implementer + verifier independently confirmed no drift.

### Notes

- Phase 3.5 wraps `scripts/plan-drift-correct.sh` (Phase 1) into the orchestration flow. Implementation runs the script as a black box; the skill prose only orchestrates parse → drift → correct/escalate decisions and the marker-ordering rules.
- `step.*.verify` written by Phase 3 satisfies the hook's landing gate; Phase 3.5 success writes informational `phasestep.*.drift-detect`; failure DELETEs `step.*.verify` to re-block landing.
- Phase 3 will land the pre-dispatch arithmetic gate (Phase 1 step 6 extension) and the `--eval` mode for integer arithmetic.

---

## Phase — 1 Standardize PLAN-TEXT-DRIFT token + scripts/plan-drift-correct.sh [UNFINALIZED]

**Plan:** plans/IMPROVE_STALENESS_DETECTION.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-improve-staleness-detection
**Branch:** feat/improve-staleness-detection
**Commits:** 33fa174 (impl + tests), 07a3cf6 (tracker mark in-progress)

### Work Items

| # | Item | Status | Source |
|---|------|--------|--------|
| 1.1 | Token format documented in SKILL.md | Done | 33fa174 |
| 1.2 | `scripts/plan-drift-correct.sh` (501 lines, --parse / --drift / --correct, set -eu, no eval) | Done | 33fa174 |
| 1.3 | `tests/test-plan-drift-correct.sh` (34 cases, ≥20 required) | Done | 33fa174 |
| 1.4 | Registered in `tests/run-all.sh` | Done | 33fa174 |
| 1.5 | `### Plan-text drift signals` H3 in 4 dispatch sections | Done | 33fa174 |
| 1.6 | Key Rules bullet | Done | 33fa174 |
| 1.7 | `docs/tracking/TRACKING_NAMING.md` allow-list update | Done | 33fa174 |
| 1.8 | CHANGELOG entry | Done | 33fa174 |
| 1.9 | Mirror parity (per-file cp) | Done | 33fa174 |
| 1.10 | Commit | Done | 33fa174 |

### Verification

- Test suite: PASSED (897/897, +34 from baseline 863)
- All 11 acceptance criteria verified by independent verification agent
- Mirror clean: `diff -r skills/run-plan .claude/skills/run-plan` empty
- Byte-preservation (lines 1-285) holds
- No `eval`, no `$(( ))` over user input, no `jq` in script
- All 5 `<stated>` forms supported (range, ≤, ≥, ~/literal, exactly); "any other form" exits 2

### PLAN-TEXT-DRIFT findings (informational; Phase 3.5 doesn't exist yet)

Both implementer and verifier independently flagged drift in Phase 1 acceptance bullets. Binding criteria all pass; drifts are in parenthetical/documentation references:

```
PLAN-TEXT-DRIFT: phase=1 bullet=10 field=test-count plan=~551 actual=897
PLAN-TEXT-DRIFT: phase=1 bullet=11 field=parse-plan-line plan=286 actual=349
```

- bullet=10: parenthetical "(existing 531 + new 20 ≈ 551)" is stale; baseline was 863 + 34 = 897. Binding "100% pass rate" criterion holds.
- bullet=11: prose says "Phase 1 Parse Plan at line 286 in the current source" — actual is line 349. The 285-line slice still operates correctly (everything in lines 1-285 is pre-Phase-1 and untouched), so byte-preservation passes; the 286 reference is stale documentation only.

These tokens are recorded for posterity. Once Phase 2 lands (Phase 3.5 gate), a future `/run-plan` invocation on this plan would auto-correct them within the ≤10% / 10–20% bands. For now they are documented and bypass-able.

### Notes

- Phase 1 is a foundation-only phase: ships the token spec, the helper script, and tests. No `/run-plan` SKILL.md flow change yet (the new H3 subsections are content additions, not behavioral changes).
- Phase 2 will add `## Phase 3.5` (post-implement auto-correct gate) wrapping `scripts/plan-drift-correct.sh`.
- Phase 3 will extend Phase 1 step 6 with a pre-dispatch arithmetic gate plus `--eval` mode for integer +/- evaluation.
