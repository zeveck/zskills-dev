---
issue: 110
title: Adaptive Backoff for /run-plan finish auto Chunking Cron
created: 2026-04-29
status: complete
---

# Plan: Adaptive Backoff for /run-plan finish auto Chunking Cron

> **Landing mode: PR** -- This plan targets PR-based landing. All phases
> use worktree isolation with a named feature branch.

## Overview

Issue #110 reports that the chunked `finish auto` recurring `*/1` cron
produces a high count of visible "Run /run-plan ..." defer turns during
long phases. The user-facing cost is the LLM-turn wall (~$0.01/turn) plus
transcript clutter.

**Empirical signal we trust.** Memory `feedback_cron_chunking_noise`
(2026-04-21) records 30-90 visible defer turns observed for 30-90 min
phases on a healthy `*/1` recurring cron. That is Mode A: clean defers,
where the orchestrator reaches Step 0 Case 3 and exits.

**Empirical signal we do NOT trust.** The "300 prompts piled up" figure
in the issue body is **uncorroborated by the canonical incident record**
(`reports/plan-consumer-stub-callouts-plan.md:283-287` does not state any
pile-up count — verified). Furthermore, per-lane research
(`-prior-art.md`) found that the `aa471f42f50ea0c19` incident was actually
**Mode B-dominated**: the implementer agent was paused mid-dispatch by a
5-hour usage-window limit; the orchestrator never reached Step 0 during
the pause window, so Step 0 Case 3's defer counter would not have fired
on those queued prompts. Mode A's machinery does NOT solve Mode B.

This plan therefore commits to **Mode A only**: it fixes the verifiable
30-90-defer-turn cost on long phases (issue body's ~$0.30 per 30-min
phase, scaled by phase count). It does not claim to address the actual
incident pattern. Mode B requires a separate design pass with its own
implementation experiment (the bump-check site has three untested
options; speccing without prototyping would be design-by-guess).

**Scope decision: Mode A only.** Implements the per-phase defer counter
at Step 0 Case 3 ("clean defers" — orchestrator reaches Step 0 and finds
the next-target phase already In Progress). Does not implement Mode B.
A follow-up issue is filed in Phase 1 of this plan (WI 1.0 below; issue
#134) so the deferral is concretely tracked, not handwaved.

Per memory `feedback_dont_defer_hole_closure`, deferring is suspect when
the deferred work IS the change. Here it is not: Mode A and Mode B
address different runtime states (Mode A: Step 0 reached and counter
incremented; Mode B: Step 0 never reached, queue of prompts piled up
behind a paused orchestrator). The Mode A counter machinery is a strict
subset of any unified design — shipping it first is sequencing, not
deferring closure.

**Out of scope (deferred to follow-up issue #134 filed in WI 1.0):**

- Mode B failure-fire pile-up.
- Unified `fires-since-last-progress.$TRACKING_ID` counter at cron-fire
  entry (the Mode B equivalent of Mode A's per-phase counter).
- Heartbeat markers to distinguish "30-min phase in flight" from "30-min
  crash loop" (only relevant if Mode B is in scope, and only matters for
  the Mode B counter; see Q3 resolution below for why this distinction
  doesn't change the Mode A design).
- Durable cron persistence across Claude session restarts (issue body
  line 122 already calls this orthogonal).
- Phase 5b verify-pending backoff (`verify-pending-attempts.*`) is
  **explicitly walled off** per `references/finish-mode.md:151-155`. This
  plan must NOT modify Phase 5b's one-shot machinery.

## Open Questions Resolved

The 6 open questions from `/tmp/draft-plan-110-framing.md` (verbatim from
issue addendum lines 429-441):

1. **Where does the bump check live?** — **DEFERRED** to follow-up issue
   #134 filed by WI 1.0 of this plan. Question is N/A under the chosen
   Mode A scope (the bump check lives in Step 0 Case 3 by definition,
   since that is the only entry point Mode A covers). Recording this
   resolution explicitly so the follow-up does not re-litigate.

2. **Interaction with Phase 5b verify-pending backoff?** — **RESOLVED:
   they coexist as mutually-exclusive runtime states.** Phase 5b's
   verify-pending branch is entered only when all phases are Done +
   frontmatter not complete + final marker exists + fulfilled missing.
   In that branch, the recurring `*/1` chunking cron is no longer the
   driver — Phase 5b owns the cadence via its own one-shot reschedules.
   The new `in-progress-defers.<phase>` counter is per-phase scoped and
   is reset by Phase 5b's plan-completion path (Phase 1 of this plan
   adds the rm). The two backoffs use different filenames, different
   machinery (recurring stepdown vs one-shot reschedule), and different
   lifetimes — there is no shared state to interleave. Plan states this
   explicitly in `references/finish-mode.md` (Phase 2 of this plan).

3. **What counts as "progress"?** — **RESOLVED honestly: identical
   backoff for healthy long phases and crash loops, by design.** The
   research (domain lane, point 5) flagged that
   `step.run-plan.<id>.implement` is written ONLY at end-of-phase
   (verified at `skills/run-plan/SKILL.md:1086-1090`). So Mode A's
   per-phase counter cannot distinguish a healthy 30-min implementer
   agent from a 30-min crash loop — both will trigger 12 defer fires and
   both will step the cadence from `*/1` to `*/10`. **This is acceptable
   because:**
   - Backoff cadence does NOT affect work correctness, only firing rate.
     A healthy phase finishes; the next cron fire (now at `*/10` or
     `*/30`) reaches Step 0 with the next-target phase NEW and routes to
     Case 4. Case 4's counter-reset glob-rms `in-progress-defers.*`,
     restoring `*/1` cadence on the NEXT cadence-change opportunity (but
     the existing recurring cron stays at the stepped-down cadence until
     a Case 3 fire on the new phase steps it back down further; in
     practice, fast new phases trigger Case 4 quickly enough that
     cadence creeps back to `*/1` over the next phase's first few
     fires).
   - The cost of "30 defer turns over 30 healthy minutes" is exactly
     what we're trying to bound. We accept the cost of treating a
     healthy phase like a slow one — that IS the point of stepping
     down.
   - Heartbeat markers to distinguish the two cases would introduce new
     machinery (a separate marker write inside the implementer agent
     loop) which Mode B's design pass should weigh against the
     simpler "accept identical backoff" choice. Out of scope for Mode A.

   This resolution is documented in `references/finish-mode.md` Phase 2
   of this plan.

4. **Counter cleanup on plan completion?** — **RESOLVED: cleanup at five
   sites for both counter types.** (a) Step 0 Case 4 entry on a new phase:
   rm `in-progress-defers.*` AND `cron-recovery-needed.*`. (b) Phase 5b
   sub-step 0b Branch 2 (marker AND fulfilled exist — line ~1820): add
   rm of both alongside the existing `verify-pending-attempts.$TRACKING_ID`
   rm. (c) Failure Protocol: NEW cleanup step that removes
   `in-progress-defers.*`, `cron-recovery-needed.*`, AND
   `verify-pending-attempts.*`. (d) `/run-plan stop`: after CronDelete,
   rm both `in-progress-defers.*` and `cron-recovery-needed.*` for the
   pipeline. (e) Step 0 Case 1 (frontmatter `status: complete`, R6 fix):
   rm both alongside the existing terminal CronDelete. **Diagnostic value
   not preserved post-completion** — counter file is removed, not kept.
   Rationale: Phase 5b's `verify-pending-attempts.$TRACKING_ID` is also
   rm'd at success (SKILL.md:1820), so removing the counter at success is
   consistent with that precedent.

   **During-phase counter inspection (N4 clarification).** While a phase
   is in flight (i.e., before any of the five cleanup sites fire), the
   counter file is fully visible at
   `$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/in-progress-defers.<phase>`.
   Users debugging a long-running phase can `cat` it to see "we are at
   N defers" mid-phase. The post-completion rm only triggers AFTER the
   phase's terminal cleanup site has run; the file is not removed during
   the phase. Phase 4 acceptance criterion locks this:
   `ls .zskills/tracking/<pipeline>/in-progress-defers.* 2>/dev/null`
   returns empty after Phase 5b plan-complete reaches its cleanup site.

5. **Test fixture?** — **RESOLVED via pure-bash function pattern.**
   Phase 3 of this plan creates `tests/test-runplan-defer-backoff.sh`
   following the exact shape of `tests/test-phase-5b-gate.sh:51-92`:
   extract `defer_backoff_step()` as a pure-bash function reading globals
   (counter value, current cadence, plan-file, phase number, simulated
   CronCreate verify result) and emitting structured decision lines
   (`WRITE_COUNTER N`, `REPLACE_CRON <expr>`, `DELETE_COUNTER`,
   `WARN no-cron-match`, `WARN cron-replace-failed`,
   `WRITE_RECOVERY_MARKER <phase>`, `DELETE_ALL_MATCHING_CRONS`,
   `PROCEED defer-message-printed`/`PROCEED defer-message-silent`). 8 cases
   from issue body + 2 new cases (CronDelete-succeeds-CronCreate-fails
   recovery; multi-match concurrency) + 3 sentinel-recovery cases (added
   to cover the WI 1.2 prelude). Test fixtures use `mktemp -d` with
   synthesized counter files; cron tools are NOT mocked — the function
   emits decision lines and the test asserts on those.

6. **Concurrency?** — **RESOLVED via "delete-all-prompt-matches before
   create" pattern, with documented stop-vs-Case-3 race limitation.**
   CronCreate does not de-duplicate. The existing `stop` command
   (SKILL.md:300) already uses prefix-match-delete-all as its pattern.
   The new decision rule (Phase 1 of this plan) adopts the same pattern:
   when cadence change is needed, CronList → match all whose prompt
   contains `Run /run-plan <plan-file> finish auto` → CronDelete ALL of
   them → CronCreate ONE at the new cadence. This collapses any
   accidental duplicates in the same operation. The per-phase counter is
   `$PIPELINE_ID`-scoped (separate subdirectories), so two parallel
   pipelines on different plan-files have distinct counters and distinct
   crons. Two parallel pipelines on the SAME plan-file would conflict
   (same cron prompt, same counter path) — call this out in
   `references/finish-mode.md` as "do not launch two `finish auto`
   pipelines on the same plan-file simultaneously" (consistent with the
   existing `stop` command's system-wide blast radius).

   **Stop-vs-Case-3 race (DA5).** If the user types `/run-plan stop`
   while a cron-fired Case 3 is mid Delete+Create at WI 1.3 step 4b, the
   user's `stop` will succeed (deleting the existing cron) and Case 3
   step 4c will then CronCreate a brand-new cron at the new cadence —
   defeating the user's stop. Documented as a known race in
   `references/finish-mode.md`: "running `/run-plan stop` while a Case 3
   cadence-change is in flight may resurrect the cron once; run `stop`
   again to confirm." This is acceptable for the Mode A scope; a
   sentinel-based stop-requested check would add complexity to the
   already-constrained Case 3 decision rule and is not justified by the
   single observed race window per cadence change.

## High-severity race recovery (CronDelete-succeeds + CronCreate-fails)

The research flagged this as HIGH severity: if `CronDelete` succeeds but
the subsequent `CronCreate` fails, the recurring cron is gone and the
pipeline silently stalls.

**Note on Step 0 entry sources.** Step 0 is reached only from (a) a cron
fire of `Run /run-plan <plan> finish auto`, or (b) a fresh user
invocation of the same. `/run-plan next` and `/run-plan stop` short-
circuit BEFORE Step 0 (verified: SKILL.md:281-293 for `next`,
SKILL.md:295-305 for `stop`). The race by hypothesis destroys the
recurring cron, so cron-fire recovery is unavailable. Recovery must
either (i) prevent the missing-cron state from arising in the first
place (inline retry), or (ii) surface to the user immediately so they
can act.

**Chosen recovery: inline retry at Case 3, then immediate user-visible
WARN if retries exhaust.** The Case 3 decision rule attempts CronCreate
up to 3 times inline (with verify-via-CronList between attempts) before
declaring the cron unrecoverable. If all 3 retries fail:

1. Write a `cron-recovery-needed.<phase>` sentinel marker (informational;
   used by sentinel-prelude on the next user invocation, see below).
2. Emit a prominent user-facing WARN message in the cron-fired turn's
   final output:
   ```
   ⚠ /run-plan finish auto: failed to update cron after 3 attempts.
   Pipeline is stalled until you re-invoke /run-plan <plan> finish auto.

   If the next invocation also fails: run /run-plan stop to clear all
   crons, then file an issue at github.com/zeveck/zskills-dev/issues/new
   with the contents of .zskills/tracking/<pipeline-id>/cron-recovery-needed.<phase>
   and your CronList output.
   ```
   The user sees this in the terminal output of the defer-fire turn and
   can act immediately. The escalation sentence (N2 fix) gives users a
   complete action ladder: try once → if still failing, stop + file → no
   guessing whether to retry indefinitely.
3. Counter is held unchanged (so when the user re-invokes, the next
   Case 3 entry retries the cadence change with the same target).
4. Inter-attempt spacing during the 3-retry loop: `sleep 2` between
   attempts (N1 fix). Without spacing, all 3 retries fall inside the
   same ~1-second window and a transient rate-limit-class CronCreate
   failure would burn the whole retry budget. 2 seconds is the cheapest
   spacing that crosses a typical rate-limit bucket window.

**Sentinel-prelude on next user invocation.** WI 1.2 adds a sentinel
check to Step 0, BETWEEN the `TRACKING_ID=` assignment (SKILL.md:425)
and the case-dispatch (SKILL.md:432-449). When a fresh user invocation
fires `/run-plan <plan> finish auto`, this prelude detects
`cron-recovery-needed.*` and reattempts CronCreate of the recurring
`*/1` cron. On success, removes the marker and proceeds to case
dispatch. On failure, emits the same WARN and proceeds anyway (Step 0
will route to Case 3 or Case 4 normally, which has its own retry; if
THAT also fails, the user sees the WARN twice in the same session, which
is the legitimate signal that something is wrong with their cron tool
state).

Rationale for this design over alternatives:

- **"Order Create-then-Delete"** creates a brief window with two crons
  firing, doubling fire rate during the window (and risking the new
  cadence's Case 3 firing before the old cron is deleted, which would
  spawn ANOTHER Create-then-Delete). Adds complexity; rejected.
- **"Sentinel + retry on next cron fire"** requires a fire to happen,
  which by hypothesis will not happen if the cron was deleted. **This
  was the original plan's design and was wrong** — DA1 caught this. Now
  fixed.
- **Chosen approach (inline retry + sentinel for user re-invoke)**:
  bounded recovery within the failing turn (3 retries × CronCreate is
  cheap), and a user-visible signal if even the inline retry fails. The
  sentinel marker is a belt-and-suspenders backup for the case where the
  user re-invokes — but the primary recovery channel is the user
  reading the WARN and acting.

**Acknowledged limitation:** if all 3 inline retries fail AND the user
does not re-invoke `/run-plan`, the pipeline does silently stall. This
is documented in `references/finish-mode.md` Phase 2 of this plan. The
user-visible WARN at the failing turn IS the safety mechanism — agents
reading session transcripts see the message; users reading their
terminal see the message.

The `cron-recovery-needed.<phase>` marker is written under
`.zskills/tracking/$PIPELINE_ID/`. It is informational (not enforcement
— the hook does not enforce arbitrary prefixes per
`docs/tracking/TRACKING_NAMING.md:454`).

## Style and discipline notes

- **Anchoring on case-name + heading text, NOT raw line numbers.** The
  issue body cites Case 3 at SKILL.md:426-427; current line is 446-447
  (20 lines of drift, verified). Phases anchor on `### Preflight checks`
  heading + "Idempotent re-entry check" + "Case N" labels. Implementing
  agents use `grep -n "Idempotent re-entry check" skills/run-plan/SKILL.md`
  to find current location.
- **Mirror discipline.** Every phase that edits `skills/run-plan/` ends
  with `bash scripts/mirror-skill.sh run-plan`.
  `tests/test-skill-invariants.sh:99-104` enforces parity.
- **Test command resolution.** Test run uses `$FULL_TEST_CMD` resolved via
  `. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"`,
  never hardcoded `npm run test:all` or `bash tests/run-all.sh`.
- **Bash regex over jq.** Per memory `feedback_no_jq_in_skills`, JSON
  parsing in skills uses `BASH_REMATCH`. This plan does not introduce jq.
- **No `|| true` on cron operations.** Each `CronDelete`/`CronCreate` is
  followed by an explicit verify (CronList re-check). Failure is surfaced
  as `WARN`, never silenced.
- **Acceptance grep portability.** Use `grep -F` for literal-string
  checks (works on GNU + BSD grep). Avoid `\|` BRE alternation, which
  is GNU-only — DA8 caught this.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Counter machinery + Step 0 prelude/Case 1/Case 3/Case 4 + stop + Phase 5b cleanup + follow-up issue | ✅ Done | `316350d` | 9 work items (1.0–1.8) all completed; tests 1353/1353 |
| 2 — Documentation: finish-mode.md table + failure-protocol.md cleanup step | ✅ Done | `c881f9f` | Backoff table + reset triggers + DA4/DA5/A1/N2 prose in finish-mode.md; new step 5 in failure-protocol.md |
| 3 — Test fixture: tests/test-runplan-defer-backoff.sh | ✅ Done | `d969f09` | 14 functional + 2 anchor cases; 435 lines (in [370, 440] band); standalone test passes 16/16 |
| 4 — Mirror, invariants, run-all.sh, regression check | ✅ Done | `88f414b` | run-all.sh registers new test (line 52); test-skill-invariants extended +4 #110 anchors (36→40 pass); mirror parity confirmed |

## Phase 1 — Counter machinery + Step 0 prelude/Case 1/Case 3/Case 4 + stop + Phase 5b cleanup + follow-up issue

### Goal

Implement the adaptive backoff state machine inside `skills/run-plan/SKILL.md`:
the sentinel-recovery prelude (with cadence-sanity check), the decision
rule at Step 0 Case 3 (with inline retry on CronCreate failure), the
counter reset at Step 0 Case 4, the recovery-marker + counter rm at
Step 0 Case 1 (terminal cleanup), the counter rm at Phase 5b sub-step
0b Branch 2, and the counter rm in the `stop` command. File the Mode B
follow-up issue. Surface the high-severity race via inline retry +
user-visible WARN (with escalation pointer) + `cron-recovery-needed.*`
sentinel.

### Work Items

1.0 **File the Mode B follow-up issue.** Before any code edits, run:

```bash
gh issue create \
  --title "[/run-plan finish auto] Mode B: failure-fire pile-up backoff (followup to #110)" \
  --body "Follow-up to issue #110 (Mode A landed via plans/ADAPTIVE_CRON_BACKOFF.md).

Mode A handles clean defers at Step 0 Case 3. Mode B handles the case where
the orchestrator is paused (e.g., 5-hour usage-window limit) and cron fires
queue up behind it without ever reaching Step 0. The actual incident in
\`reports/plan-consumer-stub-callouts-plan.md:283-287\` was Mode B-dominated.

Open design questions (see /tmp/draft-plan-110-framing.md from #110):
1. Where does the bump check live? Three options, all untested:
   (a) cron-prompt preamble (every cron prompt starts with a bump-check stub)
   (b) UserPromptSubmit hook pattern-matching \`Run /run-plan\`
   (c) accept Step-0-only and document the gap
2. 30-min phase vs 30-min crash loop ambiguity — heartbeat markers needed?
3. How to test without mocking system-level pauses?

Should be designed via /draft-plan once Mode A has run in production for a
few real plans and we have data on whether Mode A alone is sufficient."
```

Capture the new issue number (call it `MODE_B_ISSUE` in shell context).
The plan's Overview (line ~46), Out-of-scope block (line ~56), and Q1
deferral (line ~77) each contain a literal placeholder string — the
five-character sequence `[` `T` `B` `D` `]`. Verify exactly three such
placeholders exist in those three regions before substituting (the
WI-instruction prose AVOIDS the literal placeholder by using descriptive
text instead, so the implementer's `sed` will only hit the three
intended sites):

```bash
grep -nF "$(printf '[T''BD]')" plans/ADAPTIVE_CRON_BACKOFF.md
# Expect exactly 3 lines, in Overview / Out-of-scope / Q1-deferral.
sed -i "s/\[TBD\]/#${MODE_B_ISSUE}/g" plans/ADAPTIVE_CRON_BACKOFF.md
grep -cF "$(printf '[T''BD]')" plans/ADAPTIVE_CRON_BACKOFF.md
# Expect 0.
```

The `printf '[T''BD]'` trick concatenates `[T` and `BD]` so the
WI-instruction prose itself never matches the substitution target —
only the three placeholder sites in Overview/Out-of-scope/Q1 do. (If
the implementer prefers a simpler invocation: edit the three sites by
hand using `Edit` tool searches; the sed shortcut is convenience, not
mandate.)

1.1 **Locate the Step 0 four-case dispatch.**

```bash
grep -n "Idempotent re-entry check" skills/run-plan/SKILL.md
```

Research-time anchor: line 420 (drift confirmed: 426 → 446, +20 lines
since issue filed). Then locate Case 3 ("Next-target phase already In
Progress") and Case 4 ("Otherwise: proceed with normal preflight") inside
the same numbered list (research-time: lines 446-449).

1.2 **Add a sentinel-marker prelude AFTER `TRACKING_ID=` and BEFORE the
case dispatch.** Per DA2, the prelude's pseudocode references
`$TRACKING_ID`, which is computed inside Step 0's bash block at
SKILL.md:425. Insert the prelude AFTER line 427 (the closing ` ``` ` of
the `TRACKING_ID=...; echo "ZSKILLS_PIPELINE_ID=..."` block) and BEFORE
line 429 (the prose "Then read the plan frontmatter..."). The prelude
goes inside its own bash fenced block:

```bash
# Sentinel: a prior turn detected a CronDelete-succeeds + CronCreate-fails
# race. Before doing anything else, attempt to re-establish the recurring
# */1 cron. (Counter held; this is recovery, not normal flow.)
PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
if compgen -G "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/cron-recovery-needed.*" >/dev/null 2>&1; then
  # CronList → check if a Run /run-plan <plan-file> finish auto cron
  # already exists (a stale fire from before the failed Delete may have
  # raced ahead of us).
  # If exists AND cadence ∈ {*/1, */10, */30, */60} (sane backoff cadence
  #   set, A1 fix): rm cron-recovery-needed.* (already recovered at a
  #   sane cadence; trust it).
  # If exists BUT cadence ∉ {*/1, */10, */30, */60} (A1 fix: third-party
  #   cron at e.g. */15, or scheduler corruption returning bad cadence):
  #   emit WARN cron-recovery-bad-cadence with the observed cadence
  #   string, force CronDelete on ALL matching crons, then fall through
  #   to the "missing" branch below to CronCreate at */1.
  # If missing: CronCreate cron="*/1 * * * *" recurring=true
  #             prompt="Run /run-plan <plan-file> finish auto"
  #             then verify via CronList again AND verify the new cron's
  #             cadence is exactly "*/1 * * * *" (not just "exists").
  #             On success: rm cron-recovery-needed.*. On failure: leave
  #             marker, emit WARN cron-recovery-failed and continue to
  #             case dispatch (Case 3's own inline retry may succeed, or
  #             Case 4 will happen-path past the missing cron).
fi
```

The cadence-sanity check (A1 fix) protects against three failure modes
discovered post-Round-1: (i) a third-party tool created a recurring cron
with the same prompt at a different cadence (e.g., `*/15`); (ii) Case 3's
3-retry exhaustion left a partial-success cron at the wrong target
cadence (CronCreate succeeded, scheduler returned different actual
cadence); (iii) the previous turn's CronCreate raced with another
top-level invocation. Without this check, the "exists, rm marker" branch
would silently accept a wrong cadence and the pipeline would run at the
wrong fire rate indefinitely.

Note: `MAIN_ROOT` is computed at SKILL.md line ~1087 in Phase 5b's
post-implementation tracking block; for use in Step 0's prelude, the
implementing agent should add `MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)`
to the prelude bash block immediately above the `PIPELINE_ID=` line.
(SKILL.md may already compute MAIN_ROOT earlier; verify with
`grep -n 'MAIN_ROOT=' skills/run-plan/SKILL.md` and only add if not
already in scope at line 425.)

1.3 **Replace Case 3's "output and exit" with the decision rule.** Current
text (research-time): "**Next-target phase already In Progress** (per
tracker): output \"Phase X already in progress, deferring.\" Exit cleanly."
Replace with the 6-step decision rule from issue body, with inline
retry on CronCreate failure (DA1 fix):

1. Read `C` from `$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/in-progress-defers.<phase>`
   (default 0 if missing).
2. Read current cadence `R` via `CronList` substring match on
   `Run /run-plan <plan-file> finish auto`. If multi-match: pick the
   first for cadence read (the delete-all step in 4 will collapse all).
   If no match: emit `WARN no-cron-match`, do NOT increment counter,
   output defer message, exit.
3. Compute target cadence `T` from `C+1`: `<10` → `*/1`, `10..15` → `*/10`,
   `16..25` → `*/30`, `≥26` → `*/60`.
4. If `T != R`:
   a. CronList → enumerate ALL prompts containing
      `Run /run-plan <plan-file> finish auto`.
   b. CronDelete each ID.
   c. CronCreate ONE cron with `cron: T`, `recurring: true`,
      `prompt: "Run /run-plan <plan-file> finish auto"`.
   d. Verify: CronList again; if no match found OR cadence != `T`,
      `sleep 2` (N1 fix: inter-attempt spacing protects against
      rate-limit-class CronCreate failures, which would otherwise burn
      all 3 retries inside the same rate-limit window), then retry steps
      c–d up to 2 more times (3 total CronCreate attempts; total
      worst-case wall-time on the failing path ≈ 4-6s of sleep + 6 LLM
      tool calls). If all 3 attempts fail: write
      `cron-recovery-needed.<phase>` marker, emit
      `WARN cron-replace-failed (3 retries exhausted)` to stdout AND
      output a prominent user-visible WARN to the turn's final message:

      > ⚠ /run-plan finish auto: failed to update cron after 3 attempts.
      > Pipeline is stalled until you re-invoke /run-plan <plan>
      > finish auto.
      >
      > If the next invocation also fails: run `/run-plan stop` to
      > clear all crons, then file an issue at
      > github.com/zeveck/zskills-dev/issues/new with the contents of
      > .zskills/tracking/<pipeline-id>/cron-recovery-needed.<phase>
      > and your `CronList` output.

      (N2 fix: extend WARN with explicit escalation path — `/run-plan
      stop` + manual `gh issue` filing — so users have a complete
      action ladder rather than a re-invoke-or-give-up choice.)

      Do NOT increment counter. Exit.
5. If `T == R`: no cron action.
6. Write `C+1` to the counter file. Output defer message ONLY at
   `C+1 ∈ {1, 10, 16, 26}` (silent on intermediate fires).

1.4 **Add Case 4 entry counter reset.** Current text (research-time):
"**Otherwise**: proceed with normal preflight (steps 1-9) then Phase 2."
Add a bash precursor BEFORE the "proceed" line:

```bash
# Phase advancing — clear all per-phase defer counters AND any stale
# recovery sentinel from a prior phase.
PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/in-progress-defers."*
rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/cron-recovery-needed."*
```

(Harmless on first phase — rm of missing files is a no-op.)

1.5 **Add Phase 5b sub-step 0b Branch 2 cleanup.** Locate via
`grep -n "verify-pending-attempts.\$TRACKING_ID" skills/run-plan/SKILL.md`
(research-time: line 1820). Add TWO rm lines directly below the existing
rm — `in-progress-defers.*` AND `cron-recovery-needed.*` (DA6 fix):

```bash
rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/verify-pending-attempts.$TRACKING_ID"
rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/in-progress-defers."*       # NEW (#110)
rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/cron-recovery-needed."*    # NEW (#110)
```

1.6 **Add `stop` command cleanup.** Locate via `grep -n "## Stop"
skills/run-plan/SKILL.md` (research-time: line 295). After the "Delete
ALL whose prompt starts with `Run /run-plan` using `CronDelete`" step,
add a counter rm step:

```bash
PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/in-progress-defers."*
rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/cron-recovery-needed."*
```

1.7 **Add Case 1 (frontmatter complete) recovery-marker cleanup (R6 fix).**
The sentinel prelude (WI 1.2) runs BEFORE case dispatch. If a stale
`cron-recovery-needed.<phase>` marker survives because a prior race left
it and the user never re-invoked, then the user later flips frontmatter
to `complete` and triggers a fresh `finish auto`, the prelude would
detect the marker, CronCreate a `*/1` recurring cron (resurrection), then
Case 1 would immediately CronDelete it — net: a wasted Create+Delete
cycle plus a brief race window where the spawned `*/1` cron may fire one
extra time before Case 1's delete lands. Locate Case 1 via
`grep -n 'Frontmatter \`status: complete\`' skills/run-plan/SKILL.md`
(research-time: line 433). After the existing "CronList ... CronDelete"
step (line 434-435) but BEFORE the "exit with 'Plan complete (already)'"
text (line 438), add:

```bash
PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/cron-recovery-needed."*
rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/in-progress-defers."*
```

This makes Case 1 a complete terminal cleanup: cron deleted, recovery
marker rm'd, counter rm'd. The sentinel prelude on a future stale fire
will find no marker and short-circuit, avoiding the doomed
CronCreate→CronDelete cycle.

1.8 **Mirror.**

```bash
bash scripts/mirror-skill.sh run-plan
```

### Design & Constraints

- **Counter scope chosen: per-phase**
  (`.zskills/tracking/$PIPELINE_ID/in-progress-defers.<phase>`), not
  pipeline-scoped. Reason: Case 4 entry on a new phase auto-resets via
  glob-rm of all `in-progress-defers.*` siblings, eliminating the need
  for a "what counts as progress" definition (see Q3 resolution: this
  is per-phase scoping, NOT a "progress detection" mechanism — both
  healthy long phases and crash loops produce the same backoff signal,
  by design and by acceptance).
- **Marker prefix not enforced.** `in-progress-defers.<phase>` and
  `cron-recovery-needed.<phase>` are NOT in the
  `requires.*|fulfilled.*|step.*` enforcement allow-list per
  `docs/tracking/TRACKING_NAMING.md:454`. They are informational state
  files; the tracking hook silently ignores them. This is correct.
- **Multi-match handling.** Step 4 deletes ALL matching crons before
  creating one new one — same pattern as `/run-plan stop` (SKILL.md:300).
  This is the cleanest way to recover from accidental duplicates.
- **Defer-message printing rule.** Print the full defer message only at
  `C+1 ∈ {1, 10, 16, 26}` (boundary fires) so users see meaningful step-
  down events but not minute-by-minute noise. Counter is bumped silently
  on intermediate fires.
- **Inline retry at WI 1.3 step 4d.** 3 attempts (1 initial + 2 retry).
  Each attempt is a CronCreate + CronList verify (~2 cheap LLM tool
  calls). Total worst-case cost on a failing path: 6 tool calls + a
  user-visible WARN. The retry budget is small enough not to compound
  the original noise problem; large enough to recover from transient
  scheduler issues.
- **Atomicity.** The decision rule is robust to crashes per the issue
  body's atomicity table: crash before step 4 → counter unchanged;
  crash mid-step-4 (after Delete, before Create) → next user invocation
  hits the sentinel prelude (WI 1.2) which re-establishes the cron, OR
  the inline retry catches it before declaring stall; crash post-
  CronCreate-pre-counter-write → next fire reads same `C`, target ==
  actual, no-op cron action, counter advances normally.

**Files changed.**
- `skills/run-plan/SKILL.md` — ~115 lines added across 6 edit sites:
  sentinel-marker prelude with cadence-sanity check (~25 lines, up from
  ~15 — A1 fix adds the `∈ {*/1, */10, */30, */60}` check and bad-cadence
  WARN branch), Case 3 decision rule with inline retry + 2s sleep
  (~55 lines prose+pseudocode replacing ~3 lines, up from ~50 — N1 fix
  adds `sleep 2` directive + N2 fix extends WARN copy with escalation
  pointer), Case 4 reset (~7 lines), Case 1 terminal cleanup (~5 lines —
  R6 fix), Phase 5b cleanup (~2 lines addition), `stop` command counter
  rm (~5 lines), MAIN_ROOT scope-add at prelude if needed (~1 line).
- `.claude/skills/run-plan/SKILL.md` — auto-mirrored.

### Acceptance Criteria

- `grep -F 'in-progress-defers' skills/run-plan/SKILL.md | wc -l` ≥ 6
  (sentinel area, Case 3 decision rule reads + writes, Case 4 reset,
  Case 1 terminal rm — R6 fix, Phase 5b rm, `stop` rm — at least 6
  distinct mentions).
- `grep -F 'cron-recovery-needed' skills/run-plan/SKILL.md | wc -l` ≥ 6
  (sentinel detection, Case 3 step 4d marker write, Case 4 reset,
  Case 1 terminal rm — R6 fix, Phase 5b rm, `stop` rm).
- `grep -F 'cron-recovery-bad-cadence' skills/run-plan/SKILL.md | wc -l` ≥ 1
  (A1 fix: prelude cadence-sanity-check WARN string present).
- `grep -F 'sleep 2' skills/run-plan/SKILL.md | wc -l` ≥ 1
  (N1 fix: inter-attempt spacing directive present in Case 3 retry loop;
  if pre-existing `sleep 2` matches happen elsewhere, tighten to a
  more-specific grep `grep -F 'sleep 2' skills/run-plan/SKILL.md | grep -F 'retry'` ≥ 1
  during implementation).
- `grep -F 'github.com/zeveck/zskills-dev/issues/new' skills/run-plan/SKILL.md | wc -l` ≥ 1
  (N2 fix: escalation pointer present in user-visible WARN).
- `grep -F 'WARN no-cron-match' skills/run-plan/SKILL.md | wc -l` ≥ 1.
- `grep -F 'WARN cron-replace-failed' skills/run-plan/SKILL.md | wc -l` ≥ 1.
- `grep -F '*/10' skills/run-plan/SKILL.md | wc -l` ≥ 1 (DA8 fix:
  separate `grep -F` calls, not BRE alternation).
- `grep -F '*/30' skills/run-plan/SKILL.md | wc -l` ≥ 1.
- `grep -F '*/60' skills/run-plan/SKILL.md | wc -l` ≥ 1.
- `grep -F '3 retries exhausted' skills/run-plan/SKILL.md | wc -l` ≥ 1
  OR `grep -F '3 attempts' skills/run-plan/SKILL.md | wc -l` ≥ 1
  (inline-retry budget documented in the prose).
- `diff -r skills/run-plan .claude/skills/run-plan` produces no output
  (mirror clean).
- `bash tests/test-skill-invariants.sh` exits 0 (mirror parity test).
- `gh issue list --state open --search 'Mode B: failure-fire' --json number | grep -F '"number"' | wc -l` ≥ 1
  (Mode B follow-up issue exists).
- `grep -cF "$(printf '[T''BD]')" plans/ADAPTIVE_CRON_BACKOFF.md` outputs `0`
  (N3 fix: the WI 1.0 sed substitution completed; all three placeholder
  sites in Overview, Out-of-scope, and Q1 deferral were replaced with
  the concrete `#NNN` follow-up issue number. The `printf` split
  prevents this AC line itself from matching.).

### Dependencies

None. This is the foundation phase.

## Phase 2 — Documentation: finish-mode.md backoff table + failure-protocol.md cleanup step

### Goal

Document the new behavior in the two reference files: backoff schedule
table + reset-trigger list in `references/finish-mode.md` (including the
Q3 honest-tradeoff note, the inline-retry recovery, the user-visible
WARN, and the stop-vs-Case-3 race), NEW tracking-files cleanup step in
`references/failure-protocol.md`.

### Work Items

2.1 **`references/finish-mode.md`** — locate the heading `### How to schedule
the next cron (Design 2a — single persistent recurring cron)` (research-
time: line 99). The insertion neighbours are bold-paragraph anchors
INSIDE that `###` block, NOT headings — the implementing agent must
re-grep at edit time because line numbers WILL drift:

```bash
grep -n '^\*\*Special case: Phase 5b final-verify gate\.\*\*' \
  skills/run-plan/references/finish-mode.md
grep -n '^After ensuring the cron exists' \
  skills/run-plan/references/finish-mode.md
```

After the existing `**Special case: Phase 5b final-verify gate.**`
paragraph (research-time: lines 151-155) and BEFORE the `After ensuring
the cron exists, output the chunking message` paragraph (research-time:
line 157), insert a new sub-section. **Heading level: `####` (NOT `###`).**
A `###` would terminate the parent `### How to schedule the next cron`
block and re-parent later paragraphs; `####` correctly nests the new
backoff content under it. Heading text: `#### Adaptive backoff for clean
defers (Issue #110)`. Contents:

- One paragraph explaining the per-phase counter and stepdown thresholds.
- The backoff schedule table (verbatim from issue body, lines 25-32, but
  with corrected fire counts per research domain table at lines 50-56:
  30 min → 12 fires, 60 min → 15, 120 min → 17, 300 min → 23, 720 min →
  31). Cite "fire counts derived from cumulative cadence, not issue body
  raw figures."
- The reset-trigger list (Case 4 entry, Phase 5b plan-completion,
  Failure Protocol, `/run-plan stop`).
- Explicit cross-reference: "This is distinct from Phase 5b's
  verify-pending one-shot backoff (`verify-pending-attempts.*`); they
  coexist as mutually-exclusive runtime states. See SKILL.md Phase 5b
  sub-step 0b."
- Explicit concurrency note: "Two `finish auto` pipelines on the same
  plan-file simultaneously would share the recurring cron prompt and
  cause counter ambiguity. Do not launch concurrent `finish auto`
  pipelines on the same plan-file." (Same scope as `/run-plan stop`'s
  system-wide effect.)
- **Stop-vs-Case-3 race (DA5).** "If you run `/run-plan stop` while a
  Case 3 cadence-change is in flight (between CronDelete and
  CronCreate), Case 3's CronCreate may resurrect the cron after your
  stop. Run `/run-plan stop` again if needed; the second invocation will
  catch the resurrected cron."
- **Healthy-phase vs crash-loop ambiguity (DA4).** "The per-phase counter
  cannot distinguish a healthy long-running phase (implementer agent
  doing real work) from a phase that is crash-looping. Both produce the
  same backoff signal because `step.run-plan.<id>.implement` is written
  only at end-of-phase. This is acceptable: the cost of treating a
  healthy phase like a slow one is exactly the cost we are bounding
  here. When the phase eventually finishes (crash loop or healthy), the
  next cron fire reaches Case 4, which rms `in-progress-defers.*`,
  resetting the counter for the next phase."
- **High-severity race recovery.** "If CronDelete succeeds but CronCreate
  fails, Case 3 retries inline up to 3 times with a 2-second sleep
  between attempts. If all 3 retries fail, a `cron-recovery-needed.<phase>`
  marker is written and a prominent WARN is emitted in the turn's final
  output asking the user to re-invoke `/run-plan <plan> finish auto`,
  with an escalation pointer to `/run-plan stop` + `gh issue create` if
  the next invocation also fails. The next user invocation hits the
  Step 0 sentinel-prelude, which re-attempts CronCreate before case
  dispatch AND verifies cadence sanity (`*/1, */10, */30, */60`) — if a
  found cron is at an unexpected cadence (e.g., a third-party `*/15`
  cron with the same prompt), the prelude force-deletes it and creates
  a fresh `*/1`. The pipeline does NOT silently stall: the user-visible
  WARN is the safety mechanism."
- **During-phase inspection.** "While a phase is in flight, the counter
  file at `.zskills/tracking/<pipeline-id>/in-progress-defers.<phase>`
  is human-readable (`cat` it to see the current defer count). The five
  cleanup sites (Case 4, Case 1, Phase 5b, Failure Protocol, `stop`)
  remove the file at terminal moments only; during-phase inspection is
  always available."

2.2 **`references/failure-protocol.md`** — currently has NO tracking-files
cleanup. Add a NEW step **5. Clean tracking counter files** between the
existing step 4 ("Alert the user", lines 65-84) and the "When to trigger"
section (line 86). **Why position 5 (after Alert), not 1/2/3 (R9 fix):**
the alert message at step 4 (lines 70-84 of failure-protocol.md)
references runtime state in plain text — "Cron job [ID] has been
CANCELLED", "Stash was [restored / not needed]". Running counter-rm
BEFORE step 4 would not affect those references (cron + stash, not
counters), but running counter-rm in step 1 (alongside cron-kill) or
step 2 (alongside stash-restore) would conflate domains: step 1 is
"protect against the cron stomping" (system-level), step 2 is "preserve
working-tree integrity" (filesystem-level), step 3 is "audit-trail
write" (report-level), step 4 is "user comms" (signal). Counter cleanup
is none of those — it's post-mortem hygiene that is safe to do last
because nothing downstream depends on the counter values once the run
has failed. Contents:

```markdown
### 5. Clean tracking counter files

After alerting the user, remove the per-pipeline tracking counters so a
re-invocation of `/run-plan <plan-file> finish auto` starts fresh:

\`\`\`bash
PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$(basename "$PLAN_FILE" .md | tr '[:upper:]_' '[:lower:]-')}"
rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/in-progress-defers."*
rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/verify-pending-attempts."*
rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/cron-recovery-needed."*
\`\`\`

Do NOT remove other markers under the pipeline subdirectory — only the
counter files. The `step.*` and `fulfilled.*` markers are part of the
plan's audit trail.
```

2.3 **Mirror.**

```bash
bash scripts/mirror-skill.sh run-plan
```

### Design & Constraints

- **Doc-only phase.** No bash logic added; this phase exists to make the
  Phase 1 changes legible to future readers and to satisfy the
  failure-protocol cleanup step from issue body's required changes #5.
- **Forbidden literals.** `tests/fixtures/forbidden-literals.txt` is
  scoped to `skills/**/*.md` per its header. Cron expressions like `*/10`,
  `*/30`, `*/60` in `references/finish-mode.md` ARE under that scope —
  verify the literal list does not deny these (research-time check
  passes; the deny-list does not include cron expressions).
- **Issue cross-reference.** Both new sections explicitly cite "Issue
  #110" so future readers can follow the design decision back to source.

**Files changed.**
- `skills/run-plan/references/finish-mode.md` — ~85 lines added
  (paragraph + table ~25 lines + reset list ~10 lines + cross-references
  + Q3 tradeoff + race/recovery with sleep+escalation+cadence-sanity +
  DA5 stop-race + during-phase inspection ~50 lines, up ~10 from prior
  estimate to cover N1/N2/A1/N4 doc additions).
- `skills/run-plan/references/failure-protocol.md` — ~17 lines added (new
  step 5 with bash block + R9 ordering rationale embedded).
- `.claude/skills/run-plan/references/finish-mode.md` — auto-mirrored.
- `.claude/skills/run-plan/references/failure-protocol.md` — auto-mirrored.

### Acceptance Criteria

- `grep -F '*/10' skills/run-plan/references/finish-mode.md | wc -l` ≥ 1.
- `grep -F '*/30' skills/run-plan/references/finish-mode.md | wc -l` ≥ 1.
- `grep -F '*/60' skills/run-plan/references/finish-mode.md | wc -l` ≥ 1.
- `grep -F 'in-progress-defers' skills/run-plan/references/finish-mode.md | wc -l` ≥ 1.
- `grep -F 'in-progress-defers' skills/run-plan/references/failure-protocol.md | wc -l` ≥ 1.
- `grep -F 'cron-recovery-needed' skills/run-plan/references/failure-protocol.md | wc -l` ≥ 1.
- `grep -F '#110' skills/run-plan/references/finish-mode.md | wc -l` ≥ 1.
- `grep -F '#### Adaptive backoff for clean defers' skills/run-plan/references/finish-mode.md | wc -l` ≥ 1
  (R1 fix: locks both placement AND heading level — must be `####` to
  nest under `### How to schedule the next cron`, not `###` which would
  terminate the parent block).
- `grep -F 'healthy' skills/run-plan/references/finish-mode.md | wc -l` ≥ 1
  (Q3 honest-tradeoff note present).
- `grep -F 'stop' skills/run-plan/references/finish-mode.md | wc -l` ≥ 2
  (existing references plus DA5 race note — adjust threshold during
  implementation if existing count is higher; the goal is "DA5 race note
  is present", verifiable also by `grep -F 'resurrect' finish-mode.md`).
- `grep -F 'resurrect' skills/run-plan/references/finish-mode.md | wc -l` ≥ 1
  (DA5 race documentation present).
- `diff -r skills/run-plan .claude/skills/run-plan` produces no output.
- `bash tests/test-skill-invariants.sh` exits 0.

### Dependencies

Phase 1 — the bash machinery must exist before the prose describing it
lands; otherwise documentation drifts ahead of implementation.

## Phase 3 — Test fixture: tests/test-runplan-defer-backoff.sh

### Goal

Lock the Phase 1 decision rule against regression via a pure-bash test
file mirroring the `tests/test-phase-5b-gate.sh:51-92` pattern. Function
`defer_backoff_step()` re-implements the decision rule (including
sentinel-prelude with cadence-sanity check, and inline retry with
inter-attempt sleep) and emits structured decision lines; tests assert
on those lines for 14 cases (8 from the issue body + 2 new cases for
the high-severity race and multi-match concurrency + 3 new cases for
the WI 1.2 sentinel-recovery prelude + 1 new case for the A1
cadence-sanity rejection).

### Work Items

3.1 **Create `tests/test-runplan-defer-backoff.sh`.** Skeleton mirrors
`tests/test-phase-5b-gate.sh:1-100` exactly:

- Header docstring (~25 lines) explaining the function-extraction pattern,
  scope, and what the test locks down.
- `pass`/`fail` helpers identical to phase-5b-gate (lines 31-39).
- `defer_backoff_step()` pure-bash function that reads bash globals
  `COUNTER_VALUE`, `CURRENT_CADENCE`, `CRONLIST_MATCH_COUNT`,
  `CRONCREATE_VERIFY_RESULT` (one of `ok` / `missing` / `missing-after-3-retries`),
  `PHASE`, `PLAN_FILE`, `TRACKING_ID`, `RECOVERY_MARKER_PRESENT`
  (`yes`/`no` for the prelude path). Returns 0 always; emits decision
  lines on stdout:
  - `WRITE_COUNTER <N>` — counter advances to N.
  - `REPLACE_CRON <expr>` — cadence change required (e.g.,
    `REPLACE_CRON */10`).
  - `DELETE_COUNTER` — Case 4 reset path (also rms recovery markers).
  - `WARN no-cron-match` — CronList found 0 matches.
  - `WARN cron-replace-failed` — CronCreate-verify failed; counter held.
  - `WRITE_RECOVERY_MARKER <phase>` — sentinel for high-severity race
    (after 3-retry exhaustion).
  - `DELETE_ALL_MATCHING_CRONS` — multi-match collapse.
  - `PROCEED defer-message-printed` — boundary-fire message print.
  - `PROCEED defer-message-silent` — intermediate-fire silent advance.
  - `PRELUDE_RECOVERY_ATTEMPTED` — sentinel prelude detected the marker
    and attempted CronCreate.
  - `PRELUDE_RECOVERY_OK` — prelude CronCreate succeeded; marker rm'd.
  - `PRELUDE_RECOVERY_FAILED` — prelude CronCreate failed; marker held.
  - `EMIT_USER_WARN cron-stalled` — user-visible final-output WARN.
  - `WARN cron-recovery-bad-cadence <observed>` — A1 fix: prelude found
    cron at out-of-set cadence (e.g., `*/15`).
  - `SLEEP_BETWEEN_RETRIES` — N1 fix: marker line emitted between retry
    attempts to assert the spacing directive ran (test does not actually
    sleep; the function emits the marker line in lieu of `sleep 2` so
    the test stays fast).

3.2 **Test cases** (each follows
`setup_fixture`/`exec`/`teardown_fixture`/assert idiom from phase-5b-gate
lines 113-124):

- **Case 1**: `COUNTER_VALUE=0`, `CURRENT_CADENCE=*/1`,
  `CRONLIST_MATCH_COUNT=1`, `RECOVERY_MARKER_PRESENT=no` — expect
  `WRITE_COUNTER 1`, `PROCEED defer-message-printed`, no `REPLACE_CRON`.
- **Case 2**: `COUNTER_VALUE=9`, `CURRENT_CADENCE=*/1`,
  `CRONCREATE_VERIFY_RESULT=ok` — expect `DELETE_ALL_MATCHING_CRONS`,
  `REPLACE_CRON */10`, `WRITE_COUNTER 10`,
  `PROCEED defer-message-printed` (10 is a boundary).
- **Case 3**: `COUNTER_VALUE=15`, `CURRENT_CADENCE=*/10`,
  `CRONCREATE_VERIFY_RESULT=ok` — expect `REPLACE_CRON */30`,
  `WRITE_COUNTER 16`, `PROCEED defer-message-printed`.
- **Case 4**: `COUNTER_VALUE=25`, `CURRENT_CADENCE=*/30`,
  `CRONCREATE_VERIFY_RESULT=ok` — expect `REPLACE_CRON */60`,
  `WRITE_COUNTER 26`, `PROCEED defer-message-printed`.
- **Case 5**: `COUNTER_VALUE=30`, `CURRENT_CADENCE=*/60` — expect
  `WRITE_COUNTER 31`, no `REPLACE_CRON` (cap held),
  `PROCEED defer-message-silent`.
- **Case 6**: `CRONLIST_MATCH_COUNT=0` — expect `WARN no-cron-match`,
  no `WRITE_COUNTER` line.
- **Case 7**: `COUNTER_VALUE=9`, `CURRENT_CADENCE=*/10` (idempotent
  re-run after partial crash where Delete+Create already advanced
  cadence but counter write failed) — expect no `REPLACE_CRON` (target
  == actual), `WRITE_COUNTER 10`, `PROCEED defer-message-printed`.
- **Case 8**: Case 4 entry on a NEW phase number — expect
  `DELETE_COUNTER` (per-phase glob rm of both `in-progress-defers.*`
  AND `cron-recovery-needed.*`).
- **Case 9 (NEW, high-severity race, retry exhaustion)**:
  `COUNTER_VALUE=9`, `CURRENT_CADENCE=*/1`,
  `CRONCREATE_VERIFY_RESULT=missing-after-3-retries` — expect
  `DELETE_ALL_MATCHING_CRONS`, `WARN cron-replace-failed`,
  `WRITE_RECOVERY_MARKER 4`, `EMIT_USER_WARN cron-stalled`, no
  `WRITE_COUNTER` line (counter held at 9).
- **Case 10 (NEW, concurrency, multi-match)**:
  `CRONLIST_MATCH_COUNT=2` (two crons with the same prompt due to a
  duplicate CronCreate), `COUNTER_VALUE=9`,
  `CRONCREATE_VERIFY_RESULT=ok` — expect `DELETE_ALL_MATCHING_CRONS`
  (both crons deleted, then ONE created at `*/10`), `REPLACE_CRON */10`,
  `WRITE_COUNTER 10`.
- **Case 11 (NEW, prelude — marker present, prelude CronCreate succeeds)**:
  `RECOVERY_MARKER_PRESENT=yes`, `CRONCREATE_VERIFY_RESULT=ok` (the
  prelude's CronCreate verify) — expect `PRELUDE_RECOVERY_ATTEMPTED`,
  `PRELUDE_RECOVERY_OK`, then proceeds to normal case dispatch (e.g.,
  Case 3 if `COUNTER_VALUE` and `CURRENT_CADENCE` indicate that path).
- **Case 12 (NEW, prelude — marker present, cron already exists,
  no-op)**: `RECOVERY_MARKER_PRESENT=yes`, `CRONLIST_MATCH_COUNT=1`
  (prelude's CronList finds existing cron) — expect
  `PRELUDE_RECOVERY_ATTEMPTED`, `PRELUDE_RECOVERY_OK` (marker rm'd
  because cron is already present), no `REPLACE_CRON` from prelude.
- **Case 13 (NEW, prelude — marker present, prelude CronCreate fails)**:
  `RECOVERY_MARKER_PRESENT=yes`, `CRONCREATE_VERIFY_RESULT=missing` (the
  prelude's own CronCreate also fails) — expect
  `PRELUDE_RECOVERY_ATTEMPTED`, `PRELUDE_RECOVERY_FAILED` (marker held),
  then proceeds to normal case dispatch which has its own retry path.
- **Case 14 (NEW, A1 fix — prelude cadence-sanity check rejects unknown
  cadence)**: `RECOVERY_MARKER_PRESENT=yes`, `CRONLIST_MATCH_COUNT=1`,
  `CURRENT_CADENCE=*/15` (a third-party tool created a recurring cron
  with the same prompt at an out-of-set cadence) — expect
  `PRELUDE_RECOVERY_ATTEMPTED`, `WARN cron-recovery-bad-cadence */15`,
  `DELETE_ALL_MATCHING_CRONS` (force-delete the bad-cadence cron),
  followed by a fresh CronCreate at `*/1` (assert
  `REPLACE_CRON */1` or equivalent line indicating the prelude's
  fallback create), then `PRELUDE_RECOVERY_OK` (marker rm'd because the
  recovery path completed successfully at the correct cadence).

3.3 **Anchor-grep cases (final 2 cases per phase-5b-gate:233-247
precedent).**

- **Anchor case A**: `grep -F 'in-progress-defers' skills/run-plan/SKILL.md`
  must produce ≥ 5 matches (locks Phase 1's edits in place).
- **Anchor case B**: `grep -F '*/10' skills/run-plan/references/finish-mode.md`
  AND `grep -F '*/30' ...` AND `grep -F '*/60' ...` each ≥ 1 (locks
  Phase 2's table). Use three separate `grep -F` invocations, not BRE
  alternation (DA8 fix).

3.4 **Final results print** matches phase-5b-gate:249-255 (`Results:
$PASS_COUNT passed, $FAIL_COUNT failed`; `exit 1` on any fail). This
format matches the `tests/run-all.sh` regex.

### Design & Constraints

- **Pure-bash function pattern.** Cron tools are NOT mocked. The function
  emits decision lines and the test asserts on those (substring match
  with `[[ $OUT == *"..."* ]]`). This mirrors phase-5b-gate exactly and
  avoids the brittleness of mocking LLM tools.
- **Test fixture isolation.** Each case calls `setup_fixture` (mktemp -d)
  and `teardown_fixture` (rm -rf). No trap; explicit pairing per case.
- **No jq.** Per memory `feedback_no_jq_in_skills`, parsing if needed uses
  `BASH_REMATCH`. The decision-line format is line-oriented; no JSON
  parsing required.
- **Forbidden-literals scope.** `tests/fixtures/forbidden-literals.txt` is
  scoped to `skills/**/*.md` per its header — `tests/test-runplan-defer-backoff.sh`
  is NOT gated. Cron expressions `*/1`, `*/10`, `*/30`, `*/60` may appear
  freely in test fixture text.

**Files changed.**
- `tests/test-runplan-defer-backoff.sh` — NEW. Estimated **~395 lines**:
  25 (header docstring) + 12 (pass/fail helpers) + 100
  (`defer_backoff_step()` body — covers prelude WITH cadence-sanity branch
  per A1, normal-flow, 3-retry CronCreate logic with `sleep 2` per N1,
  WARN-emit branches per N2; up from 90 in round-1's estimate to
  accommodate the cadence-sanity branch ~10 extra lines) + 15
  (setup/teardown fixture helpers) + 8 simple cases × 14 (= 112) +
  5 complex cases × 20 (= 100; cases 9, 10, 11, 12, 13 each have 4-5
  decision-line assertions) + 1 NEW prelude-cadence-bad case × 16 (= 16;
  Case 14 below) + 25 (results-print + 2 anchor-grep cases) =
  25+12+100+15+112+100+16+25 = **405 lines**.

  *Re-derivation (DA7 + round-2 fixes)*: function body grows by ~10 lines
  for the cadence-sanity branch (A1) and ~5 for the `sleep 2` + WARN
  copy (N1/N2; offset by removing some redundant comments → net +10),
  and Case 14 adds 16 lines for the new test case (assertion list of 5
  + setup/teardown wrappers). Round to **~400 lines** in implementation;
  band **370–440** is acceptable per the band-not-pin convention from
  `RESTRUCTURE_RUN_PLAN`.

### Acceptance Criteria

- `bash tests/test-runplan-defer-backoff.sh` exits 0.
- Output contains `Results: 16 passed, 0 failed` (14 functional cases +
  2 anchor cases).
- `bash tests/run-all.sh` exits 0 (full regression — including
  `test-phase-5b-gate.sh`, `test-skill-invariants.sh`, and the new
  `test-runplan-defer-backoff.sh`; Phase 4 WI 4.0 adds the test to
  `run-all.sh`'s explicit list since it does NOT glob — verified
  research-time).
- `grep -c '^# Case' tests/test-runplan-defer-backoff.sh` ≥ 14 (each
  case is comment-headed).
- File is executable: `[ -x tests/test-runplan-defer-backoff.sh ]`.
- `wc -l tests/test-runplan-defer-backoff.sh` outputs a count in the
  range **[370, 440]** (band-not-pin per re-derivation above).

### Dependencies

Phase 1 — the test re-implements the decision rule from Phase 1's prose;
the prose must be authoritative before the test can mirror it.

Phase 2 — anchor cases A and B grep the docs, which Phase 2 writes.

## Phase 4 — Mirror parity, run-all.sh registration, invariants extension, regression check

### Goal

Final mirror sync, register the new test in `tests/run-all.sh` (mandatory
— not optional, because `run-all.sh` does NOT glob; it lists each test
explicitly), optional addition to `tests/test-skill-invariants.sh` to
lock the new SKILL.md anchors against future deletion, and full
regression run.

### Work Items

4.0 **Add the new test to `tests/run-all.sh`.** This is MANDATORY (not
optional): `tests/run-all.sh` does not glob — it lists each test
explicitly via `run_suite "test-NAME.sh" "tests/test-NAME.sh"` (verified
research-time: 29 explicit `run_suite` lines). Locate the existing
`run_suite "test-phase-5b-gate.sh" ...` line (research-time: line 47)
and add a new line below it:

```bash
run_suite "test-runplan-defer-backoff.sh" "tests/test-runplan-defer-backoff.sh"
```

(Place it adjacent to phase-5b-gate since they share the function-
extraction pattern.)

4.1 **Re-mirror to ensure all phases land cleanly.**

```bash
bash scripts/mirror-skill.sh run-plan
```

(Idempotent — should produce no diff after Phases 1-3 already ran it.
Catches the case where a later phase forgot to mirror.)

4.2 **(Optional) Extend `tests/test-skill-invariants.sh`** with a small
regression block. Locate the existing run-plan anchor block via
`grep -n 'run-plan' tests/test-skill-invariants.sh` (research-time:
~lines 32-34, 88-92, 95-96). Add 4 grep checks (one per critical
Phase 1 anchor) after the existing `Phase 5b` block (~line 92):

```bash
# Issue #110: adaptive cron backoff anchors
check "issue #110: in-progress-defers counter" \
  'grep -q "in-progress-defers" skills/run-plan/SKILL.md'
check "issue #110: cron-recovery-needed sentinel" \
  'grep -q "cron-recovery-needed" skills/run-plan/SKILL.md'
check "issue #110: cron-replace-failed WARN" \
  'grep -q "WARN cron-replace-failed" skills/run-plan/SKILL.md'
check "issue #110: backoff documented in finish-mode" \
  'grep -q "in-progress-defers" skills/run-plan/references/finish-mode.md'
```

This is the same lock-down pattern that `tests/test-skill-invariants.sh`
already uses for other run-plan anchors. (Pattern verified at
research-time: lines 32-35 use `check "..." 'grep -q "..." skills/run-plan/SKILL.md'`.)

4.3 **Run full regression.**

```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
mkdir -p "$TEST_OUT"
$FULL_TEST_CMD > "$TEST_OUT/.test-results.txt" 2>&1
```

Read `$TEST_OUT/.test-results.txt`; expect 0 failures and the new test
file in the count.

### Design & Constraints

- **WI 4.0 is MANDATORY.** Earlier draft framed test registration as
  optional via globbing assumption. `tests/run-all.sh` explicitly lists
  each test, so a new test file is invisible to the regression run
  unless registered (verified via `grep -n 'run_suite' tests/run-all.sh`
  shows 29 explicit lines).
- **WI 4.2 is optional.** It locks the new anchors against silent
  deletion in future refactors. If the existing invariants file does
  not have a clean place to add this block, skip 4.2 and rely on
  Phase 3's anchor-grep cases to catch regression.
- **Do not weaken tests.** Per CLAUDE.md, never loosen assertions to
  make tests pass. If a regression appears in
  `test-skill-invariants.sh` from WI 4.2, fix the SKILL.md anchor
  (which may have drifted during edits), not the test.
- **Mirror is idempotent.** Re-running `mirror-skill.sh` on already-
  clean state should produce no diff. If it does, a prior phase forgot
  to mirror — investigate before continuing.

**Files changed.**
- `tests/run-all.sh` — 1 line added (run_suite registration).
- (Optionally) `tests/test-skill-invariants.sh` — ~10 lines added if
  WI 4.2 is included.

### Acceptance Criteria

- `grep -F 'test-runplan-defer-backoff' tests/run-all.sh | wc -l` ≥ 1
  (WI 4.0 done — replaces previous "verify by inspection" criterion).
- `bash scripts/mirror-skill.sh run-plan` exits 0 with no diff.
- `diff -r skills/run-plan .claude/skills/run-plan` produces no output.
- `$FULL_TEST_CMD` exits 0 (resolved via `zskills-resolve-config.sh`,
  NOT hardcoded).
- (If WI 4.2 done) `bash tests/test-skill-invariants.sh` exits 0 with
  the new anchor checks active.
- **N4 fix (post-completion cleanup verifiable):** after a manual
  `finish auto` run reaches Phase 5b plan-complete (verification step 1
  in "Verification after completion" below), `ls .zskills/tracking/<pipeline-id>/in-progress-defers.* 2>/dev/null`
  returns empty (file removed at the cleanup site) AND
  `ls .zskills/tracking/<pipeline-id>/cron-recovery-needed.* 2>/dev/null`
  returns empty. This is a manual-test acceptance criterion (no
  automated test; the cleanup logic is exercised by Phase 3 Case 8
  `DELETE_COUNTER` assertion on the function-level path).

### Dependencies

Phases 1, 2, 3 — this phase verifies their joint work and adds the
mandatory `run-all.sh` registration plus an optional hard lock.

## Verification after completion

1. Confirm cron behavior in a real `finish auto` pipeline (manual test):
   schedule a chunked plan with a deliberate ~30-min phase, observe that
   defer messages print only at counter values 1 and 10, and that the
   cron transitions from `*/1` to `*/10` after the 10th defer. Cron
   inspectable via `CronList`.
2. Confirm Failure Protocol cleanup: trigger a synthetic Failure Protocol
   path (e.g., create a fake `cron-recovery-needed.<phase>` marker, then
   manually invoke the protocol), confirm the marker is removed.
3. Confirm `/run-plan stop` removes counter files: write a synthetic
   `in-progress-defers.4`, run `/run-plan stop`, confirm file is gone.
4. Confirm sentinel-prelude recovery: simulate the high-severity race by
   manually CronDelete'ing the recurring cron AND writing a synthetic
   `cron-recovery-needed.4` marker; re-invoke `/run-plan <plan> finish
   auto`; observe Step 0 prelude detects marker, calls CronCreate, and
   removes marker. (This is the manual analog of Phase 3 Case 11.)

## Out-of-scope follow-up issues

- **Mode B failure-fire pile-up** (cron fires while orchestrator paused
  mid-dispatch by usage limits). Filed as a concrete GitHub issue in
  WI 1.0 of this plan; the issue captures the open architectural
  questions (bump-check site, heartbeat markers, test methodology) for
  a future `/draft-plan` pass.
- **Heartbeat markers for in-flight implementer agents** — only relevant
  if Mode B is in scope; included in the Mode B follow-up issue above.
- **Durable cron persistence** — orthogonal; per issue body line 122,
  file separately if desired.

## Plan Quality

**Drafting process:** /draft-plan with 2 rounds of adversarial review.
**Convergence:** Converged at round 2 per orchestrator judgment.
**Remaining concerns:** None substantive. Mode B (failure-fire pile-up)
is deferred to a follow-up issue filed by Phase 1 WI 1.0 — that is by
design, not a gap.

### Round History

| Round | Reviewer Findings | DA Findings | Resolved | Notes |
|-------|-------------------|-------------|----------|-------|
| 1 | 9 (lost to file-write collision; 5 re-checked in round 2) | 8 | 10/17 (R5, R7 from task brief + 8 DA) | DA1 (HIGH) and DA2 (HIGH) invalidated initial sentinel-recovery design; redesigned to inline-retry. DA4 forced honest Q3 resolution. |
| 2 | Combined R + DA single agent (file collision lesson) | — | 8/8 (3 MEDIUM + 5 LOW), 0 not-reproduced | All round-2 findings had verifiable anchors. Surgical fixes only — heading level, cadence-sanity check, follow-up-issue placeholder, sleep between retries, WARN escalation, Failure-Protocol step rationale. |

### Anti-rubber-stamp dispositions (verified at finalize)

- **300-prompts uncorroborated finding** — engaged honestly in Overview's "Empirical signal we do NOT trust" paragraph; preserved through both refines.
- **Q3 healthy-vs-crash-loop tradeoff** — accepted explicitly; identical backoff documented as a tradeoff, not "moot".
- **HIGH-severity race recovery** — redesigned from incoherent sentinel to inline-retry-with-WARN; limitations explicitly acknowledged; user-visible escalation path specified.

### Verification artifacts

- Research: `/tmp/draft-plan-research-ADAPTIVE_CRON_BACKOFF*.md`
- Round 1 review: `/tmp/draft-plan-review-ADAPTIVE_CRON_BACKOFF-round-1.md`
- Round 1 disposition: `/tmp/draft-plan-disposition-ADAPTIVE_CRON_BACKOFF-round-1.md`
- Round 2 review: `/tmp/draft-plan-review-ADAPTIVE_CRON_BACKOFF-round-2.md`
- Round 2 disposition: `/tmp/draft-plan-disposition-ADAPTIVE_CRON_BACKOFF-round-2.md`
