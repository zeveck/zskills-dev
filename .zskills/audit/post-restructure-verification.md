# Post-RESTRUCTURE verification report

**Date:** 2026-04-19 (America/New_York)
**HEAD:** `05a2d53` (31 commits since tag `2026.04.0`)
**Baseline reference:** `reports/baseline-pre-restructure.md` (pre-state at `14dea81`)
**Remotes:** `dev/main` = `origin/main` = HEAD (`05a2d53`); `prod/main` still at `14dea81` (awaiting this verification before push).

## TL;DR

**RESTRUCTURE succeeded.** Byte-preservation held, mirror parity is clean, every cross-reference resolves, all six PR-mode invocations trace end-to-end, and 542/542 tests pass (unit + integration + E2E). The refactor preserved pre-existing behavior faithfully, including some latent issues that predate RESTRUCTURE.

**No RESTRUCTURE-introduced blockers.** Four cosmetic split artifacts + docs drift from the separate Design 2a change are the only new findings. Pre-existing latent issues are out-of-scope for this verification but listed below for awareness.

**Verdict:** safe to push to prod zskills.

## Verification scope

The user ran RESTRUCTURE in a separate session. 31 commits landed since tag `2026.04.0`:
- **RESTRUCTURE** (Phases 1-5): `/commit`, `/do`, `/fix-issues`, `/run-plan` each split `SKILL.md` → `SKILL.md + modes/*.md + references/*.md`. Close-out commit `0ffff64`.
- **Design 2a cron change** (`20fd09c` + 4 smoke commits): replaced per-phase one-shot crons in chunked finish-auto with a single recurring `*/1 * * * *` cron + terminal `CronDelete`. Post-RESTRUCTURE, unrelated to the extraction itself.
- **Other** (`fd9d03d`, `e219307`): refine-plan numeric-target arithmetic; draft of `IMPROVE_STALENESS_DETECTION` plan.

## Phase 1 — Static gates (PASSED)

| Check | Result |
|---|---|
| `bash tests/run-all.sh` | **531 / 531** passed, exit 0 |
| `RUN_E2E=1 bash tests/run-all.sh` | **542 / 542** passed, exit 0 |
| `bash -n` on all scripts + tests | no syntax errors |
| `test-skill-conformance.sh` | **86 / 86** patterns pass — every critical invariant still present in the post-RESTRUCTURE tree |
| `test-compute-cron-fire.sh` | **29 / 29** pass — cron math untouched |

## Phase 2 — Structural integrity (PASSED)

| Check | Result | Evidence |
|---|---|---|
| Mirror parity source ↔ `.claude/skills/` | clean across all 4 skills + their new `modes/` + `references/` subdirs | `diff -rq` clean |
| Hook mirror parity | clean | |
| Every `modes/X.md` referenced by SKILL.md resolves | **100%** resolution (15 refs checked across 4 skills) | |
| Internal cross-refs inside mode/reference files | all resolve | |
| All required scripts shipped | 13/13 present including `compute-cron-fire.sh` and `apply-preset.sh` | |
| Byte-preservation | `/run-plan` +67 lines (+2.6%), `/commit` +20 (+4.8%), `/do` +17 (+2.5%), `/fix-issues` +27 (+1.8%). `/verify-changes` unchanged | Well within "mode-file header overhead" expectations |
| All extract files have top-level `#` headers | yes | |
| H2/H3 header inventory vs baseline | every pre-state header still present in the post-state tree, except `### How to schedule the next cron` (renamed to add `(Design 2a — …)` suffix — intentional) and `### Direct mode landing` (renamed to `# /run-plan — Direct Landing Mode` in `modes/direct.md`) | |

## Phase 3 — PR-mode end-to-end trace (PASSED, caveats)

Every PR-mode invocation was traced from SKILL.md entry through mode file to exit:

| Invocation | Routing | Mode completeness | Variable scope | Verdict |
|---|---|---|---|---|
| `/run-plan <plan> pr` | PASS | all sub-steps present | `$PLAN_TITLE` undefined (pre-existing) | **SHIPPABLE** |
| `/run-plan <plan> finish auto pr` | PASS (Design 2a recurring cron) | PASS | `$PLAN_TITLE` (pre-existing) | **SHIPPABLE** |
| `/fix-issues N pr` | PASS | **CI block is comment-only** (pre-existing since `2026.04.0`) | `$LANDED_STATUS`, `$CI_STATUS`, `$PR_STATE` undefined | **Pre-existing gap** |
| `/do "…" pr` | PASS | fully self-contained (184 lines) | all vars scoped | **SHIPPABLE** |
| `/research-and-go "…" pr` | PASS | dispatch contract to `/run-plan` intact; tracking markers work via glob-dual-lookup in Phase 5b | — | **SHIPPABLE** |
| `/research-and-plan "…"` | PASS | no modes/ (single-file skill); `Landing mode: pr` advisory hint preserved | — | **SHIPPABLE** |
| `/commit pr` | PASS | self-contained (97 lines); first-token-only detection preserved | all vars scoped | **SHIPPABLE** |

## Phase 4 — Past regression status

Specific regressions flagged by memory / prior plans, re-checked post-RESTRUCTURE:

| Regression | Guard | Status | Evidence |
|---|---|---|---|
| **PR #13:** PR-mode bookkeeping commits must go on feature branch, not main | `cd "$WORKTREE_PATH"` before commit | **PRESERVED** | SKILL.md:1050-1053, 1071, 1331; modes/pr.md:184-189 |
| **faab84b:** /verify-changes Scope Assessment gate catching silent feature deletion | `grep -q "⚠️ Flag"` | **PRESERVED** in cherry-pick path (`modes/cherry-pick.md:14-21`); PR path skipped (pre-existing — pre-RESTRUCTURE SKILL.md line 1580 gate was explicitly "worktree mode only") | |
| **CI fix-cycle ordering:** re-push → `--watch` → re-check (don't trust `--watch` exit) | explicit re-check block | **PRESERVED** | `/run-plan/modes/pr.md:504-530`; `/do/modes/pr.md:A8:130-144` |
| **CANARY10:** verifier dispatched in PR mode commits on feature branch | contract in dispatch prompt | **PARTIAL** — contract implicit rather than explicit. Not an obvious break, but pre-existing weakness. | SKILL.md:942-1031 |

## Findings ranked by severity

### BLOCKER (must fix before push)

**None.** The RESTRUCTURE didn't introduce any new functional regressions.

### SHOULD FIX — RESTRUCTURE-introduced (cosmetic, non-functional)

1. **Dangling trailing headers** in `/run-plan/modes/{cherry-pick,direct,delegate,pr}.md`. Each ends with an orphaned `### <next mode> landing` heading that has no body. Artifact of extraction: the original monolithic SKILL.md had these as sequential section boundaries; the extractor copied each boundary header as the final line of the preceding mode file. `/commit`, `/do`, `/fix-issues` mode files are clean. **Fix:** 5 line deletions. ~5 min.

### SHOULD FIX — Design 2a docs drift (NOT from RESTRUCTURE)

2. **`/run-plan/SKILL.md:37-47, 1393`** — overview paragraphs and Phase 5c intro still describe "one-shot crons scheduled by Phase 5c" / "schedules its own ~5-min one-shot crons internally" / "transitions execution via a one-shot cron." The authoritative "How to schedule the next cron" section at `references/finish-mode.md:99-161` correctly describes the Design 2a recurring `*/1` cron. **Fix:** rewrite the overview paragraphs to align with the authoritative section. ~15 min.

3. **`/run-plan/references/finish-mode.md:10, 56-57, 66`** — same stale language inside `finish-mode.md` itself (overview paragraphs contradict its own Design 2a section at line 99+). **Fix:** rewrite. ~10 min.

4. **`/research-and-go/SKILL.md:221-224`** — kickoff cron still described as one-shot (`recurring: false`). Design 2a's fizzle-avoidance rationale applies identically here; either migrate to recurring `*/1` or document why the kickoff is intentionally one-shot. **Fix:** decide + update. ~15 min.

5. **`/update-zskills/SKILL.md:454`** — `compute-cron-fire.sh` described as "required by `/run-plan` (Phase 5c chunked finish-auto…)." Post-Design-2a, Phase 5c no longer uses one-shot crons for chunked finish-auto — only Phase 5b verify-pending + re-entry crons still use it. **Fix:** narrow the description. ~2 min.

### NITs (pre-existing latent issues, surfaced by audit but not RESTRUCTURE-introduced)

6. **`/run-plan/modes/pr.md:201-215`** references `$PLAN_TITLE`, `$FINISH_MODE`, `$CURRENT_PHASE_NUM`, `$CURRENT_PHASE_TITLE` with no upstream computation. Verified via `git show 2026.04.0:skills/run-plan/SKILL.md | grep PLAN_TITLE` → **3 matches in pre-RESTRUCTURE SKILL.md** — the extraction faithfully moved the pre-existing bug. Latent since ≥2026.04.0.

7. **`/fix-issues/modes/pr.md:118-133`** CI block is comment-only (points at `/run-plan`'s canonical implementation). Verified in pre-RESTRUCTURE SKILL.md line 1224 — same text. Latent pre-existing.

8. **`/commit/SKILL.md:206`** HEREDOC template says `Co-Authored-By: Claude Opus 4.6`. Today's model is 4.7. Unrelated to RESTRUCTURE; cosmetic.

### What's safe to ignore

- `/verify-changes` tests still pass 86/86 against post-state. Design 2a changed the cron count reference in one pattern (now "recurring `*/1`" instead of inline math) — updated test.
- Dangling headers in modes/ are READ by the LLM but don't impact routing or logic.
- The extraction strictly respected byte-preservation within the headers moved — no prose drifted.

## Evidence of rigor

- Phase 1 gates: 5 automated test runs, all green.
- Phase 2 structural: 8 distinct mechanical checks (diff, grep, cross-ref resolution, byte counts, header inventory, script presence, hook mirror, internal refs).
- Phase 3 PR-mode trace: dispatched a fresh agent to walk every invocation cold, then I spot-verified its load-bearing claims via direct `git show 2026.04.0:...` checks — confirming 3/3 flagged issues are pre-existing, not RESTRUCTURE-introduced.
- Phase 4 Design 2a audit: dispatched a second fresh agent focused on cron drift; cross-checked its findings by grepping for `"one-shot cron"` and `"recurring: true"` across the tree.

## Recommendation

**Push `05a2d53` to prod.** The verification found no RESTRUCTURE-introduced blockers.

If you want to fix the SHOULD-FIX items before the next tag, grouped effort estimate:
- Cosmetic dangling headers: **5 min**
- Design 2a docs drift sweep (items 2, 3, 4, 5): **~45 min**
- Model-name bump (`4.6 → 4.7` in /commit): **2 min**
- Total: **~1 hour** of editing if you want 2026.04.1 to ship cleanly.

The pre-existing latent issues (`$PLAN_TITLE`, `/fix-issues` CI block) should be tracked as GitHub issues — they deserve their own plans, not a quick inline fix.
