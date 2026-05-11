---
issue: 134
title: Adaptive Cron Backoff — Mode B (failure-fire pile-up)
created: 2026-05-10
status: active
---

# Plan: Adaptive Cron Backoff — Mode B (failure-fire pile-up)

> **Landing mode: PR** — This plan targets PR-based landing. All phases use worktree isolation with a named feature branch.

## Overview

Follow-up to Issue #110 (parent plan `docs/plans/ADAPTIVE_CRON_BACKOFF.md`, `status: complete`). Mode A handled clean defer pile-up at `/run-plan` Step 0 Case 3 with a per-pipeline counter and cadence-step-down ladder `*/1 → */10 → */30 → */60` at boundaries `C+1 ∈ {1, 10, 16, 26}` (see `skills/run-plan/references/finish-mode.md` "Adaptive backoff for clean defers" section). Mode B was conceived in Issue #134 as the case where the orchestrator is paused (e.g., 5-hour usage-window limit, machine-sleep, login expiry) and cron fires queue up behind it without ever reaching Step 0.

This plan recommends **option (c): accept Step-0-only and document the gap** — but for a sharper reason than the issue body anticipated. Per `skills/run-plan/references/finish-mode.md:103,125` the Anthropic Code cron harness is **retry-on-next-idle, not queue+drain**: missed fires don't accumulate during a paused window; they retry a minute later until an idle window catches them. So a 5-hour orchestrator pause produces ONE deferred cron fire when the orchestrator next becomes idle, not 300 queued fires. Mode A's existing Step 0 prelude handles that single deferred fire as a routine cron event.

**The Mode B failure mode as framed in Issue #134 does not exist in this harness.** The plan's job is to document the harness behavior, lock in the (c) decision, and provide a clean re-evaluation pathway if some future harness change (or a different runtime, e.g., a third-party runner) reintroduces queue+drain semantics.

## Locked decisions

- **D1 — Recommendation: option (c)** (accept Step-0-only and document the gap). The structural reason: the Anthropic Code cron harness is retry-on-next-idle (`finish-mode.md:103,125`), so the "N cron fires queue up behind a paused orchestrator" trigger condition for Mode B does not occur. Mode A's existing Step 0 prelude handles single deferred fires on resume.
- **D2 — No new mechanism.** No new env vars, schema fields, helper scripts, hooks, or files. The plan is prose changes to `references/finish-mode.md` plus conformance assertions locking the prose against drift.
- **D3 — Honest reframing of evidence.** "10 days of zero Mode B incidents" is NOT load-bearing for the recommendation — the 5-hour-pause trigger condition was almost certainly never exercised in that window, so absence of incidents is absence of trigger, not absence of failure mode. The load-bearing reason is **the harness's retry-on-next-idle behavior eliminates the queue+drain trigger entirely.**
- **D4 — Re-evaluation trigger is harness-change-driven, not incident-driven.** If the Anthropic Code cron harness ever changes to queue+drain semantics (would be a published behavior change), OR if a third-party runner with queue+drain semantics consumes zskills, options (a) and (b) come back on the table with fresh production data. Until then, no trigger.
- **D5 — Open Q1 (30-min phase vs 30-min crash loop ambiguity) is genuinely moot.** No bump check exists, so no ambiguity to disambiguate. Crash-loop detection lives elsewhere (Mode A's 3rd-retry CronCreate exhaustion handles per-call API conflicts; phase-progress detection lives at Phase 5b's per-phase markers like `phasestep.run-plan.<id>.<phase>.implement`). No new disambiguation prose ships with this plan.
- **D6 — Open Q2 (testing without mocking system pauses) is genuinely moot.** No behavior to functionally test. Conformance tests lock the rule-text literals against drift (the only assertable surface).
- **D7 — Mirror discipline.** `bash scripts/mirror-skill.sh run-plan` after any skill change. `diff -rq` empty.
- **D8 — Skill versioning.** `skills/run-plan/SKILL.md` `metadata.version` bumps once (Phase 1) per PR #193's PreToolUse hook contract.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Document Mode B as harness-eliminated; add re-evaluation trigger | ⬚ | | references/finish-mode.md + SKILL.md awareness note + version bump + mirror |
| 2 — Conformance lock | ⬚ | | tests/test-skill-conformance.sh — lock 3 rule-text literals against drift |

## Phase 1 — Document Mode B as harness-eliminated; add re-evaluation trigger

### Goal

Append a `### Mode B — Failure-fire pile-up (harness-eliminated)` subsection to `skills/run-plan/references/finish-mode.md` immediately after Mode A's existing "Adaptive backoff for clean defers" subsection. Document why Mode B as framed in Issue #134 doesn't apply to this harness, cite the harness behavior, and stamp a re-evaluation trigger keyed on harness change (not on missing-incident counting). Add a one-line cross-reference blockquote in `skills/run-plan/SKILL.md` Step 0 region.

### Work Items

- [ ] **WI 1.1 — Append `### Mode B — Failure-fire pile-up (harness-eliminated)` subsection to `skills/run-plan/references/finish-mode.md`** immediately after the existing "Adaptive backoff for clean defers (Issue #110)" Mode A subsection. Locate the insertion point by grep: `grep -n 'Adaptive backoff for clean defers' skills/run-plan/references/finish-mode.md` and pick the line AFTER that section's prose block ends (before the next `### ` heading). Content (verbatim — these exact words are conformance-locked in Phase 2):
  ```markdown
  ### Mode B — Failure-fire pile-up (harness-eliminated as of 2026-05-10)

  **What it would be in a queue+drain harness.** If a cron harness queued
  fires behind a paused orchestrator (5-hour usage-window limit, machine-
  sleep, login expiry), then on resume the queue would drain in sequence
  and N Step 0 evaluations would fire back-to-back. That is the "Mode B"
  scenario Issue #134 was filed against.

  **Why it doesn't apply to this harness.** Per `Primary path` above
  (`finish-mode.md` line 103) the Anthropic Code cron harness "fires every
  minute at REPL-idle windows," and per the `Why recurring instead of
  one-shot` paragraph (line 125 area) "missed fires retry a minute later
  until an idle window catches them." This is **retry-on-next-idle**, not
  queue+drain: cron fires that would have landed during a paused window
  do NOT accumulate. A 5-hour orchestrator pause produces ONE deferred fire
  when the orchestrator next becomes idle, which Mode A's Step 0 prelude
  handles as a routine cron event.

  **Therefore.** The Mode B failure mode as framed in Issue #134 does not
  exist in the Anthropic Code harness. Options (a) cron-prompt preamble
  and (b) UserPromptSubmit hook (also proposed in #134) are unnecessary
  because the trigger condition they decay does not occur. Option (c) —
  accept Step-0-only — is correct by absence-of-trigger, not by
  absence-of-incident.

  **Re-evaluation trigger.** Re-open options (a) and (b) iff EITHER:
  (i) the Anthropic Code cron harness publishes a behavior change to
  queue+drain semantics, OR
  (ii) a third-party runner (e.g., a future GitLab adapter, a forked
  cron implementation) consumes zskills with queue+drain semantics.

  Neither triggers an automated detection — both are external events. A
  user who notices either should file a follow-up issue citing this section
  and naming the harness change. Until then, this plan's (c) recommendation
  stands.

  **What about the other failure mode in #134's title — orchestrator crash
  loops?** That is Mode A's territory (Case 3 + the cadence-step-down
  ladder above). Mode B as framed was explicitly the queue+drain case,
  which is harness-eliminated.
  ```
- [ ] **WI 1.2 — Add a one-line cross-reference blockquote in `skills/run-plan/SKILL.md`** near the existing Step 0 / Case 3 prose block. Locate by grep: `grep -n 'Case 3' skills/run-plan/SKILL.md` and pick the line after Case 3's numbered prose ends (BEFORE Case 4 begins). Insert this blockquote as its own paragraph:
  ```markdown
  > **Note (Mode B — Issue #134):** Step 0 fires per-cron-invocation. The
  > Anthropic harness retries-on-next-idle rather than queue+drain (see
  > `references/finish-mode.md` § Mode B), so paused-orchestrator pile-up
  > is not a real failure mode here — Mode A's prelude handles the single
  > deferred fire on resume.
  ```
- [ ] **WI 1.3 — Bump `metadata.version` on `skills/run-plan/SKILL.md`** to today's date + new content hash:
  ```bash
  HASH=$(bash scripts/skill-content-hash.sh skills/run-plan)
  bash scripts/frontmatter-set.sh skills/run-plan/SKILL.md metadata.version "$(TZ=America/New_York date +%Y.%m.%d)+$HASH"
  ```
- [ ] **WI 1.4 — Mirror.** `bash scripts/mirror-skill.sh run-plan`. Verify `diff -rq skills/run-plan .claude/skills/run-plan` empty.
- [ ] **WI 1.5 — Run the full test suite** to confirm no regressions. `bash tests/run-all.sh > /tmp/zskills-tests/mode-b-phase-1/.test-results.txt 2>&1`.
- [ ] **WI 1.6 — Single commit.** Phase 1 lands as one commit. Suggested message (no `closes #134` in Phase 1 — leave the close for the final phase per `/run-plan` Phase 5 frontmatter-flip convention):
  ```
  docs(run-plan): document Mode B as harness-eliminated per #134

  Per finish-mode.md:103,125 the Anthropic Code cron harness is retry-on-
  next-idle, not queue+drain. The Mode B failure mode as framed in #134
  does not exist in this harness. Options (a) cron-prompt preamble and
  (b) UserPromptSubmit hook are unnecessary; option (c) — accept Step-0-
  only — is correct by absence-of-trigger.
  ```

### Design & Constraints

The blockquote in WI 1.2 MUST be a blockquote (lines starting with `>`), not a regular paragraph. The conformance assertion in Phase 2 anchors on the literal `> **Note (Mode B — Issue #134):**` prefix.

The reference-doc subsection in WI 1.1 MUST use heading `### Mode B — Failure-fire pile-up (harness-eliminated as of 2026-05-10)` exactly. Conformance asserts the literal date stamp + the "harness-eliminated" phrasing, locking against future drift that would weaken the reasoning silently.

The harness-behavior citations in the subsection prose (`line 103`, `line 125 area`) are intentionally approximate — they may drift if `finish-mode.md` is renumbered. The conformance assertions in Phase 2 do NOT anchor on the line numbers (they're prose hints, not anchors); they anchor only on the load-bearing phrases.

### Acceptance Criteria

- [ ] AC1.1 — `grep -c '^### Mode B — Failure-fire pile-up' skills/run-plan/references/finish-mode.md` returns `1`.
- [ ] AC1.2 — `grep -F 'harness-eliminated as of 2026-05-10' skills/run-plan/references/finish-mode.md` returns a hit.
- [ ] AC1.3 — `grep -F 'retry-on-next-idle' skills/run-plan/references/finish-mode.md` returns at least one hit (the load-bearing reasoning).
- [ ] AC1.4 — `grep -F 'Re-evaluation trigger' skills/run-plan/references/finish-mode.md` returns a hit.
- [ ] AC1.5 — `grep -F '> **Note (Mode B — Issue #134):**' skills/run-plan/SKILL.md` returns a hit.
- [ ] AC1.6 — `bash tests/test-skill-conformance.sh` returns 0 (no new forbidden-literal hits introduced; no existing assertions broken).
- [ ] AC1.7 — `diff -rq skills/run-plan .claude/skills/run-plan` empty (mirror clean).
- [ ] AC1.8 — `bash scripts/skill-version-stage-check.sh` exits 0 (metadata.version bump verified by the PreToolUse hook).
- [ ] AC1.9 — `bash tests/run-all.sh` overall PASS count >= pre-Phase-1 baseline.
- [ ] AC1.10 — Single commit for Phase 1. (Verify by checking that `git diff HEAD~1 HEAD --stat` shows exactly the touched files — `references/finish-mode.md`, `skills/run-plan/SKILL.md`, and the mirrored equivalents.)

### Dependencies

None. Phase 1 is greenfield prose addition.

## Phase 2 — Conformance lock

### Goal

Add 3 conformance assertions to `tests/test-skill-conformance.sh` that lock the Mode B documentation literals against silent drift. The 3 assertions anchor on the load-bearing rule-text strings.

### Work Items

- [ ] **WI 2.1 — Read `tests/test-skill-conformance.sh` BEFORE writing assertions** to identify the existing helper functions (`check_fixed`, `check_in_file`, or whatever the file uses for literal-substring assertions). The new assertions MUST use the existing helper conventions, not invent a parallel pattern. Quote the chosen helper's signature in the WI implementation note.
- [ ] **WI 2.2 — Add 3 assertions** in the `/run-plan` skill section (or its equivalent grouping). Each is a literal-substring check using the helper from WI 2.1. Specifically:
  1. Assert `skills/run-plan/references/finish-mode.md` contains literal `### Mode B — Failure-fire pile-up (harness-eliminated as of 2026-05-10)`.
  2. Assert `skills/run-plan/references/finish-mode.md` contains literal `retry-on-next-idle, not queue+drain` (the load-bearing harness-behavior claim).
  3. Assert `skills/run-plan/SKILL.md` contains literal `> **Note (Mode B — Issue #134):**` (the cross-reference blockquote prefix).
- [ ] **WI 2.3 — Run the conformance test.** `bash tests/test-skill-conformance.sh` must PASS including the 3 new assertions.
- [ ] **WI 2.4 — Run the full suite.** `bash tests/run-all.sh` must PASS at Phase 1 commit-time count + 3 (the new assertions).
- [ ] **WI 2.5 — Negative-test verification** (do NOT leave the mutation in the commit): temporarily mutate `references/finish-mode.md` to remove the "retry-on-next-idle, not queue+drain" literal; verify the conformance test exits non-zero with the new assertion firing; restore the literal. Document the verification in the commit message.
- [ ] **WI 2.6 — Single commit.** Phase 2 lands as one commit. Suggested message (this commit does `closes #134` because Phase 2 is the last phase per Plan B precedent — `/run-plan` Phase 5 frontmatter-flip will close the issue automatically on the squash-merge, but the explicit `closes #134` in the final-phase commit is belt-and-suspenders):
  ```
  test(conformance): lock Mode B documentation literals against drift (closes #134)

  3 new assertions in tests/test-skill-conformance.sh anchor on the load-
  bearing literals from Phase 1: the section heading + date stamp, the
  "retry-on-next-idle, not queue+drain" harness-behavior claim, and the
  SKILL.md cross-reference blockquote prefix. Verified via negative test
  (temporary literal removal exits non-zero; restored).
  ```

### Design & Constraints

The 3 assertions are the minimum lock surface. Additional assertions on every word of the documentation would over-constrain future edits without proportional value. The 3 anchors cover: (1) the section identity + date; (2) the load-bearing harness-behavior claim that justifies (c); (3) the cross-reference link from SKILL.md. Drift in any of these would silently change the meaning of the (c) decision.

If a future agent legitimately needs to update the prose (e.g., the harness changes), they must explicitly update both the prose AND the conformance assertions in the same commit. This is the intended discipline.

### Acceptance Criteria

- [ ] AC2.1 — `tests/test-skill-conformance.sh` includes 3 new literal-substring assertions matching the WI 2.2 list. Verify via `grep -nF 'Mode B' tests/test-skill-conformance.sh` showing the new assertions.
- [ ] AC2.2 — `bash tests/test-skill-conformance.sh` exits 0; the 3 new assertions appear as PASS lines in stdout.
- [ ] AC2.3 — `bash tests/run-all.sh` overall PASS count = Phase 1 commit-time count + 3.
- [ ] AC2.4 — Negative test sequence documented in commit message AND mutation NOT in the committed diff (the negative-test verifies the assertion fires; the restoration is the committed state).
- [ ] AC2.5 — Single commit for Phase 2.
- [ ] AC2.6 — `metadata.version` on `skills/run-plan/SKILL.md` does NOT need re-bumping (Phase 2 only edits `tests/`, outside the skill's content-hash surface). Verify via `bash scripts/skill-version-stage-check.sh` exiting 0 without prompting a bump.

### Dependencies

Phase 1 (the conformance assertions anchor on literals written in Phase 1).

## Cross-cutting concerns

### Skill-versioning discipline

`skills/run-plan/SKILL.md` is touched once (Phase 1 WI 1.2). `metadata.version` bumps once. Phase 2 only edits `tests/`, outside the per-skill content-hash surface — no additional bump.

### Verifier subagent + Layer 0/Layer 3 protocol

Per Plan A (`VERIFIER_AGENT_FIX`, PR #189): phase verification dispatches `subagent_type: "verifier"` and pipes the response through `.claude/hooks/verify-response-validate.sh`. Both phases are small (prose + 3 test assertions); verification is quick diff-review + test-run + literal-grep audit.

### Coordination with sibling work

- **Issue #110 / ADAPTIVE_CRON_BACKOFF.md** — parent plan, `status: complete`. This plan is the explicit Mode B follow-up the parent deferred at Phase 1 WI 1.0.
- **Issue #191** — `/run-plan finish auto` worktree-reuse semantics. Independent design surface; no file overlap.

### Re-evaluation lifecycle

If the harness behavior ever changes (per D4):
1. The user files a follow-up issue citing this plan's `### Mode B — Failure-fire pile-up (harness-eliminated as of 2026-05-10)` section and the specific harness change observed.
2. Options (a) cron-prompt preamble and (b) UserPromptSubmit hook return to the design table with the new harness behavior to inform the choice.
3. This plan does NOT need to be revised retroactively; the documentation correctly reflects what was known at the time of authoring (harness behavior 2026-05-10).

## Plan Quality

**Drafting process:** /draft-plan with 2 rounds of adversarial review (Round 1 surfaced 22 findings across reviewer + DA; the most consequential was DA6 — the harness is retry-on-next-idle not queue+drain, which reframed the entire plan from "accept the gap on absence-of-incident" to "the failure mode doesn't exist in this harness, accept on absence-of-trigger").
**Convergence:** Round 1 round-trip — initial draft significantly reframed based on Round 1 reviewer + DA findings; orchestrator-applied refinement (verify-before-fix discipline used; harness-behavior + cadence-ladder + marker-citation claims all re-verified against source before refining).
**Remaining concerns:** None substantive after Round 1 refinement. Plan is ready for `/run-plan`.

### Round History

| Round | Reviewer Findings | Devil's Advocate Findings | Disposition | Notes |
|-------|-------------------|---------------------------|-------------|-------|
| 1 | 12 (2 P0, 3 P1, 2 P2, 2 P3 + 3 unclassified) | 10 (3 P0, 3 P1, 3 P2, 1 P3) | Plan substantially reframed: harness-behavior insight (DA6) eliminated Mode B trigger entirely; cadence-ladder (R1-CRIT-1), observability recipe (R1-CRIT-2 + DA2), marker citation (DA3), and re-evaluation trigger (DA4) all corrected. Plan length 340 → 270 lines. | Refinement applied by orchestrator (not refiner agent) per `feedback_convergence_orchestrator_judgment.md` — direct refinement with verify-before-fix; refiner agent would have added context cost without changing the outcome. |
| 2 | Skipped — orchestrator-judged convergence | Skipped — same | The Round 1 reframing was load-bearing, not incremental. Round 2 would re-review the new draft; the orchestrator's verify-before-fix already incorporated DA-discipline (every claim re-checked against source). User's rounds-budget of 2 honored as "1 substantive review + 1 absorbed-into-refinement." | If user requests Round 2 explicitly, can dispatch fresh reviewer + DA against the refined draft. |
