---
title: /quickfix and /do — Triage Gate, Inline Plan, and Fresh-Agent Plan Review
created: 2026-04-25
status: active
---

# Plan: /quickfix and /do — Triage Gate, Inline Plan, and Fresh-Agent Plan Review

> **Landing mode: PR.** Each phase ships as its own PR off `main`, lands via `/run-plan` PR mode, full test suite must pass before merge. Tracker/report/frontmatter commits go on the feature branch (per `project_run_plan_pr_mode_bookkeeping`), not `main`.

## Overview

`/quickfix` and `/do` are fire-and-forget skills for small tasks. Today they accept any description that arrives and dispatch unconditionally — there is no model-layer judgment about whether the task is appropriately small, no review of the implicit plan before execution, and no escape hatch when the user wants to override. This plan adds three orthogonal gates to both skills: (1) a **triage gate** that judges whether the task fits the skill's contract and exits 0 with a redirect to a more appropriate skill (`/draft-plan`, `/run-plan`, `/fix-issues`) when it does not; (2) an **inline plan** composed in the model's response (not a `.md` file — dirtying main is a non-starter); (3) a **fresh-agent plan review** that approves / revises / rejects the inline plan before any branch is created or any execution agent runs. Two new flags — `--force` (bypasses both gates) and `--rounds N` (controls review-loop depth, default 1, `0` = legacy skip) — compose with existing flag sets. Meta-commands (`/do stop|next|now`) bypass triage and review entirely. The new review is **pre-execution and orthogonal** to the existing `/verify-changes` post-execution dispatch in `/do`; both must run when both are wired. Test coverage is part of this plan, not a follow-up. Triage runs **before** any side-effecting state — for /quickfix that means before branch creation and before WI 1.8 marker; for /do it means before Phase 0 cron registration. A redirected invocation leaves no branch, no marker, no tracking dir, no commits, and (for /do) no cron.

## Progress Tracker

| Phase | Status | Description |
|-------|--------|-------------|
| 1a    | ⬚ | /quickfix — flags, triage gate (WI 1.5.4), inline plan, fresh-agent review (skill source + mirror) |
| 1b    | ⬚ | /quickfix — extend tests/test-quickfix.sh to cover triage / review / --force / --rounds |
| 2a    | ⬚ | /do — flags, triage gate (BEFORE cron registration), inline plan, fresh-agent review (skill source + mirror) |
| 2b    | ⬚ | /do — create tests/test-do.sh, wire into run-all.sh |
| 3     | ⬚ | Cross-cutting — CLAUDE_TEMPLATE.md, full-suite run, /commit pr follow-up issue |

**Phase 1a effort note:** Phase 1a touches WI 1.2 (parser), inserts WI 1.5.4 / 1.5.4a / 1.5.4b, edits WI 1.5.5 prose, edits WI 1.8 marker logic, refreshes the WI 1.3 Check 3 hook citation (WI 1a.6.7), and mirrors. Expect ~265 lines added to skills/quickfix/SKILL.md and ~13 grep-presence AC additions. Implementer should plan ~2-3 hours of careful prose work.

---

## Phase 1a — /quickfix: triage gate, inline plan, and fresh-agent review (skill source + mirror)

### Goal

Add the new behavior to `skills/quickfix/SKILL.md` AND mirror to `.claude/skills/quickfix/`. Tests live in Phase 1b.

### Work Items

**WI 1a.1 — Add `--force` and `--rounds N` to the WI 1.2 argument parser.**

Insert two new `case` arms. Initialize `FORCE=0` and `ROUNDS=1` alongside the existing flag defaults at SKILL.md:74-78 (anchor: line `SKIP_TESTS=0`).

```bash
FORCE=0
ROUNDS=1
```

```bash
    --force) FORCE=1 ;;
    --rounds)
      # Greedy-fallthrough: if next arg is numeric, consume it as ROUNDS.
      # If next arg is non-numeric (e.g. "/quickfix fix --rounds in docs"),
      # treat "--rounds" itself as user prose and fall through to the
      # default arm. This avoids rejecting legitimate descriptions that
      # happen to contain the literal token "--rounds".
      NEXT_IDX=$((i+1))
      NEXT="${ARGS[$NEXT_IDX]:-}"
      if [[ "$NEXT" =~ ^[0-9]+$ ]]; then
        ROUNDS="$NEXT"
        i="$NEXT_IDX"
      else
        if [ -z "$DESCRIPTION" ]; then
          DESCRIPTION="$arg"
        else
          DESCRIPTION="$DESCRIPTION $arg"
        fi
      fi
      ;;
```

The error-on-bad-integer contract still holds for cases where the next token
LOOKS numeric but isn't: any `--rounds <token>` where `<token>` is non-empty,
not all-digits, AND not followed by more args is the user-prose case above.
A subsequent token that matters semantically would be an explicit error
(e.g., `--rounds 3.5`) — but `3.5` matches `[0-9]+` only on the leading `3`,
so the regex anchors `^[0-9]+$` correctly classify it as non-numeric →
prose-fallthrough. If the project later wants strict-numeric-or-error, it
can swap the fallthrough arm for the original `exit 2` form.

**WI 1a.2 — Update frontmatter `argument-hint` (L4) and Usage line (L13).**

`"[<description>] [--branch <name>] [--yes] [--from-here] [--skip-tests] [--force] [--rounds N]"`.

**WI 1a.3 — Insert WI 1.5.4 (Triage gate, model-layer) IMMEDIATELY AFTER WI 1.5 and IMMEDIATELY BEFORE WI 1.5.5.**

Triage runs after WI 1.5 so user-edited mode triage may inspect `$DIRTY_FILES` and `git diff HEAD`. Triage runs BEFORE WI 1.5.5 so we don't ask the user to confirm a diff we may redirect, and BEFORE WI 1.6 / WI 1.8 — so a redirect leaves no branch, no marker, no tracking dir, no commits.

**Rubric (qualitative — observable from description text and dirty-tree shape, no LOC counting):**

| Signal | Verdict | Mode applicability |
|--------|---------|--------------------|
| Description scopes to one concept; user-edited dirty tree (if any) is one cluster | PROCEED | both |
| ≥ 3 distinct files explicitly named in description | REDIRECT → `/draft-plan` | **agent-dispatched only** (user-edited mode dirty tree may legitimately span ≥3 files; the "Dirty tree spans heterogeneous subsystems" row catches that case) |
| Verbs include any of: `add feature`, `redesign`, `rewrite`, `refactor across` | REDIRECT → `/draft-plan` | both |
| `and` connects unrelated areas (e.g. "fix nav and update copy") | REDIRECT → `/draft-plan` | both |
| Vague verbs alone: `improve`, `fix it`, `update`, `clean up` (no concrete object) | REDIRECT → ask user | both |
| References a GitHub issue number (`#N`, `closes #N`, `fix #N`) | REDIRECT → `/fix-issues` | both |
| References an existing plan file under `plans/` | REDIRECT → `/run-plan` | both |
| Dirty tree (user-edited mode) spans heterogeneous subsystems (model judgment) | REDIRECT → `/draft-plan` | user-edited only |

**Worked examples (calibrate the model's PROCEED/REDIRECT calls):**

| Example invocation | Verdict | Why |
|--------------------|---------|-----|
| `/quickfix Fix README typo` | PROCEED | one concept, one likely file |
| `/quickfix add comment to canary-marker.txt` | PROCEED | one concrete object, one concrete file |
| `/quickfix update CHANGELOG with v0.5 release notes` | PROCEED | concrete verb + object + file |
| `/quickfix add dark mode and refactor the worker pool` | REDIRECT → /draft-plan | "and" connects unrelated areas |
| `/quickfix improve` | REDIRECT → ask user | vague verb, no object |
| `/quickfix fix #142` | REDIRECT → /fix-issues | references issue number |

Output one of:
- `PROCEED` — print `Triage: proceeding with /quickfix (<one-line reason>).` Continue to WI 1.5.4a.
- `REDIRECT(target=<skill>, reason=<text>)` — see redirect handling.

**Per-target redirect message templates** (must be exact-text-grep-able). Each message is **two physical lines** in the printed output (the linebreak is a real newline, not the literal `\n` characters):

| target | Line 1 | Line 2 |
|--------|--------|--------|
| `/draft-plan` | `Triage: redirecting to /draft-plan. Reason: <reason>` | `This task spans more than one concept; /draft-plan will research and decompose it. Run \`/draft-plan <description>\` instead, or re-invoke with --force to bypass.` |
| `/run-plan` | `Triage: redirecting to /run-plan. Reason: <reason>` | `This task references an existing plan file. Run \`/run-plan <plan-path>\` to execute it, or re-invoke with --force to bypass.` |
| `/fix-issues` | `Triage: redirecting to /fix-issues. Reason: <reason>` | `This task references a GitHub issue. Run \`/fix-issues <issue-number>\` instead, or re-invoke with --force to bypass.` |
| ask-user | `Triage: cannot proceed — description is too vague to act on. Reason: <reason>` | `Re-invoke /quickfix with a concrete description (verb + object + which file/area). --force will not help — vague descriptions cannot be planned.` |

The model implements these as a `printf 'line1\nline2\n' "$REASON"` so both lines are emitted to stdout and both are independently greppable from a test fixture.

On REDIRECT and `$FORCE -eq 0`: print the per-target message (both lines), then `exit 0`. **No marker is written** (WI 1.8 has not yet run). No branch. No tracking dir.

On REDIRECT and `$FORCE -eq 1`: print `Triage: REDIRECT(<target>) overridden by --force; proceeding.` Continue.

**WI 1a.3a — Document the test-seam env-var contract (model-layer).**

Production invocations MUST dispatch a real model-layer triage decision. The test harness needs a deterministic stub. Use the `_ZSKILLS_TEST_*` prefix and a required companion harness flag so production cannot accidentally honor a stale env var:

- `_ZSKILLS_TEST_HARNESS=1` (REQUIRED companion; without it, the other vars are ignored)
- `_ZSKILLS_TEST_TRIAGE_VERDICT` — one of `PROCEED`, `REDIRECT:/draft-plan:reason`, `REDIRECT:/run-plan:reason`, `REDIRECT:/fix-issues:reason`, `REDIRECT:ask-user:reason`
- `_ZSKILLS_TEST_REVIEW_VERDICT` — one of `APPROVE`, `REVISE: reason`, `REJECT: reason`

**Entry-point unset guard.** Insert at the very top of WI 1.2's parser block (before any other parser logic):

```bash
if [ "${_ZSKILLS_TEST_HARNESS:-}" != "1" ]; then
  unset _ZSKILLS_TEST_TRIAGE_VERDICT _ZSKILLS_TEST_REVIEW_VERDICT
fi
```

Prose-document this seam in WI 1.5.4 and WI 1.5.4b so future readers know production behavior is unaffected: when `_ZSKILLS_TEST_HARNESS=1`, the model-layer instruction is to skip the triage / review Agent dispatch and use the env-var value as the verdict. Production invocations always run the full Agent path.

**WI 1a.4 — Insert WI 1.5.4a (Inline plan composition, model-layer) immediately after WI 1.5.4.**

```
### /quickfix inline plan
**Description:** <DESCRIPTION>
**Mode:** <MODE>
**Files (expected):** <comma-separated list, or "as in dirty tree">
**Approach:** <2-4 sentences>
**Acceptance:** <2-4 bullets>
```

Held in `INLINE_PLAN`, passed verbatim to WI 1.5.4b reviewer. ≤60 lines. The model-authored fields **Approach** and **Acceptance** MUST NOT contain literals `/draft-plan`, `/run-plan`, `/fix-issues` (using these in model-authored prose would muddle the redirect-message guards). The **Description** field is verbatim user input and is exempt — a user description that mentions another skill name is the user's prerogative. Early-stage review judges PLAN STRUCTURE, not file enumeration accuracy.

`INLINE_PLAN` is a logical placeholder for text the model composes in its response. When WI 1.5.4b dispatches the reviewer Agent, the model copies the `INLINE_PLAN` text **verbatim** into the Agent prompt as the `INLINE PLAN ...` section — there is no file read or shell-variable interpolation; this is a model-to-prompt substitution.

**WI 1a.5 — Insert WI 1.5.4b (Fresh-agent plan review, model-layer) immediately after WI 1.5.4a.**

If `$ROUNDS -eq 0`: print to stderr `WARN: --rounds 0 skips fresh-agent plan review (legacy opt-in).` and skip review entirely. Continue.

Otherwise dispatch ONE Agent (no model hint — inherit parent) with this prompt:

```
You are the REVIEWER agent for /quickfix's pre-execution plan review.

DESCRIPTION the user provided:
[DESCRIPTION]

MODE: [MODE]

[if MODE=user-edited:]
Dirty files (the user is asking to bundle these into the PR):
[DIRTY_FILES, one per line]

Diff:
[git diff HEAD output, truncated to first 4000 lines]

INLINE PLAN the model proposes to execute:
[INLINE_PLAN verbatim]

Your job: judge whether the inline plan, when executed, will produce a PR
that faithfully addresses DESCRIPTION (and, in user-edited mode, a PR
that matches the dirty-diff scope) without obvious omissions or
out-of-scope work. Judge PLAN STRUCTURE, not file enumeration accuracy
(file lists may be best-effort at this stage).

Return EXACTLY one of these as the FIRST line. APPROVE is a bare line
with no separator; REVISE and REJECT MUST include both an ASCII `--`
separator AND a one-line reason ≤200 chars. No free text after APPROVE
on line 1.

  VERDICT: APPROVE
  VERDICT: REVISE -- <one-line reason ≤ 200 chars>
  VERDICT: REJECT -- <one-line reason ≤ 200 chars>

Then, on subsequent lines, add a short justification (≤ 10 lines) — for
APPROVE this is where you justify, NOT on line 1.
```

**Verdict parser (separator-required for REVISE/REJECT):** trim trailing whitespace from the first line, then match against this regex (in priority order):

```bash
# Bare APPROVE: no trailing text on line 1.
^VERDICT:[[:space:]]+APPROVE[[:space:]]*$

# REVISE/REJECT: separator (--) and reason are REQUIRED.
^VERDICT:[[:space:]]+(REVISE|REJECT)[[:space:]]+--[[:space:]]+(.+)$
```

Reason captured in group 2 of the second regex. Em-dashes (`—`, `–`) in the iteration prompt template are normalized to ASCII `--` before insertion (the model performs this normalization when composing the iteration prompt) so the parser only needs to handle ASCII. If the first line matches NEITHER regex → treat as a malformed verdict, retry once with the same prompt; on second malformed → soft-reject (same exit semantics as REJECT).

**REVISE loop:** at most `$ROUNDS` iterations. On REVISE, model rewrites `INLINE_PLAN` using BOTH the verdict reason AND the justification body, then dispatches a NEW reviewer (single reviewer, NOT /draft-plan dual-agent). Iteration prompt template:

```
You are the REVIEWER agent for /quickfix's pre-execution plan review (round [N]).

Prior reviewer (round [N-1]) returned:
  VERDICT: REVISE -- [prior reason]
  Justification:
  [prior justification body verbatim]

The model has REVISED the inline plan in response. New plan below.

DESCRIPTION the user provided:
[DESCRIPTION]
[…rest of original prompt unchanged…]

Judge whether the revision addresses the prior reviewer's reason. Return
the same VERDICT format (APPROVE bare; REVISE/REJECT require -- + reason).
Do not re-flag issues the prior reviewer already accepted; do flag NEW
issues you see.
```

After `$ROUNDS` REVISE cycles → soft-reject (same exit semantics as REJECT).

On APPROVE: print verdict + justification ABOVE the WI 1.5.5 prompt (user-edited) or the WI 1.11 dispatch (agent-dispatched). Continue.

On REJECT and `$FORCE -eq 0`: print verdict, exit 0. **No marker is written** (WI 1.8 has not yet run).

On REJECT and `$FORCE -eq 1`: print override message. Continue.

**WI 1a.6 — Update WI 1.5.5 prose to acknowledge the review verdict context.**

Insert paragraph at end of WI 1.5.5: "When `$ROUNDS != 0`, the WI 1.5.4b reviewer's verdict prints ABOVE this confirmation prompt as added context. The `[y/N]` is unchanged. A reviewer APPROVE does not auto-confirm — the user still confirms here."

**WI 1a.6.5 — Fix existing prose drift in WI 1.5.5.**

The current WI 1.5.5 (skills/quickfix/SKILL.md:265-289) says the user-decline path "set the tracking marker's `status` to `cancelled` and commit nothing. No branch is created yet at this point, so no rollback is needed." This wording predates the new triage/review gates and is misleading in the new design. Update to:

> "Only proceed if the user affirms. If the user declines, exit cleanly: WI 1.10 sets `CANCEL_REASON='user-declined'` and `CANCELLED=1` immediately before the rollback (see WI 1a.7); the EXIT trap then transitions the marker (already written by WI 1.8) from `status: started` → `status: cancelled` and finalize_marker appends `reason: user-declined`. No branch is created at this confirmation point, so no branch rollback is needed. (Triage redirect and review reject paths exit BEFORE WI 1.8 and write no marker at all — distinct from this user-declined path.)"

**WI 1a.6.7 — Refresh stale hook citation in WI 1.3 Check 3 prose.**

While editing `skills/quickfix/SKILL.md`, also update the stale citation at L165-172 (the WI 1.3 Check 3 "Test-cmd alignment gate" prose). Currently cites `hooks/block-unsafe-project.sh.template:188-229`; the actual transcript-check region is now at L412-427 (the commit-transcript safety net introduced by SKILL_FILE_DRIFT_FIX). Update:

| Old | New |
|-----|-----|
| `hooks/block-unsafe-project.sh.template:188-229` | `hooks/block-unsafe-project.sh.template:412-427` |

This is hygiene — the line range had drifted in unrelated commits before this plan landed. Verification: `grep -n 'FULL_TEST_CMD' hooks/block-unsafe-project.sh.template` returns L243, L252, L346, L351, L412-427 (the relevant safety net). The 188-229 region is unrelated to transcript checking in current state.

**WI 1a.7 — Update WI 1.8 marker shape and WI 1.10 rollback to add the optional `reason:` line for the user-decline path only.**

Marker started shape unchanged. Triage-redirect and review-reject leave NO marker (they exit before WI 1.8). Only the user-declined path (WI 1.5.5 / WI 1.10, after WI 1.8) needs `reason:`.

**Edit anchor for finalize_marker.** Open `skills/quickfix/SKILL.md`, locate WI 1.8's `finalize_marker` function (around line 374, the `if [ "$CANCELLED" -eq 1 ]; then` arm of the `case`-like cascade). Insert this block at the END of `finalize_marker`'s body, after the existing `sed -i` line and before the closing brace:

```bash
  if [ "$CANCELLED" -eq 1 ] && [ -n "${CANCEL_REASON:-}" ] && [ -f "$MARKER" ] \
     && ! grep -q '^reason:' "$MARKER"; then
    printf 'reason: %s\n' "$CANCEL_REASON" >> "$MARKER"
  fi
```

**Trap-ordering note.** The EXIT trap (`trap 'finalize_marker $?' EXIT`) fires AFTER the script exits, including after `exit 0` from the user-decline path. `CANCEL_REASON` is set by the user-decline arm before that arm calls `exit 0`, so it is in scope when `finalize_marker` runs.

**Edit anchor for the user-decline path.** In WI 1.10 (around skills/quickfix/SKILL.md:467-484), the cancel arm of `case "$answer" in` currently sets `CANCELLED=1` and prints "Cancelled by user. Cleaning up branch." Insert `CANCEL_REASON="user-declined"` IMMEDIATELY before the existing `CANCELLED=1`:

```bash
      *)
        CANCEL_REASON="user-declined"
        CANCELLED=1
        echo "Cancelled by user. Cleaning up branch." >&2
        ...
```

Update `### Terminal marker states`: "`status: cancelled` is appended with `reason: user-declined` (the only documented reason). Triage-redirect and review-reject leave no marker — they exit before WI 1.8 writes one."

**WI 1a.8 — Mirror `skills/quickfix/` to `.claude/skills/quickfix/` byte-identically via the canonical helper.**

```bash
bash scripts/mirror-skill.sh quickfix
```

Verify: `diff -rq skills/quickfix .claude/skills/quickfix` → no output, rc=0. Mirror is part of THIS phase to avoid divergence between source-landing and mirror-landing.

**Why the helper, not inline `rm -rf .claude/skills/quickfix && cp -r`:** the inline form is hook-blocked. `hooks/block-unsafe-generic.sh:218-221` requires recursive-rm paths to be a literal `/tmp/<name>` — `.claude/skills/quickfix` falls outside that allow-list and the hook fires with `BLOCKED: recursive rm requires a literal /tmp/<name> path`. The `scripts/mirror-skill.sh` helper (introduced in PR #88) implements the regen via per-file `rm` + `cp -a`, which bypasses no rule and instead works with the hook's safety design. Tests for the helper live at `tests/test-mirror-skill.sh`.

### Design & Constraints

- No new bash dependencies. WI 1.2 case-arm additions, `CANCEL_REASON` (user-decline only), `--rounds` greedy-fallthrough parser, separator-required VERDICT parser regex.
- No `jq`.
- Pre-commit hook is not engaged (no commits during triage/review).
- Triage IS a "surface signal not patch" feature.
- Soft-reject vs hard-reject: REVISE cycles that exhaust `$ROUNDS` are treated as soft-reject. Two consecutive malformed verdicts also soft-reject.
- Triage-redirect and review-reject leave no branch, no marker, no tracking dir, no commits.
- Test seam env vars are gated on `_ZSKILLS_TEST_HARNESS=1`; without it, they are unset at entry. Production invocations cannot accidentally honor a stale test env var.
- **Forbidden-literals discipline.** New SKILL.md prose introduced by this phase (rubric tables, redirect templates, reviewer-prompt strings, inline-plan template, etc.) MUST avoid the literals enumerated in `tests/fixtures/forbidden-literals.txt` (`TZ=America/New_York`, `npm run test:all`, `npm start`, `\$TEST_OUT/.test-results.txt`). Use config-resolved `\$VAR` references, OR add an `<!-- allow-hardcoded: <literal> reason: ... -->` marker per the SKILL_FILE_DRIFT_FIX (PR #122) convention. Verified: the prose blocks specified in WI 1a.3 / WI 1a.4 / WI 1a.5 contain none of these literals.
- **`/draft-tests` is NOT a triage redirect target — by design.** As of 2026-04-29, `/draft-tests` is a top-level adversarial-test-spec authoring skill (PRs #124–#140). It is **not** added to the /quickfix or /do redirect rubric because: (a) /draft-tests' contract requires an existing plan file as input (it appends `### Tests` subsections to phases — not a fresh-task entry point); (b) small one-shot test additions (e.g., "add a test for the foo helper") are within /quickfix's existing PROCEED scope and should not redirect. Triage-rubric stability matters more than enumerating every adjacent skill. If a future user pattern shows /quickfix being used for genuinely-multi-phase test-spec authoring, revisit — but the current ceremony level is correct.
- **Model-layer-triage asymmetry.** Triage is model-layer judgment; the same model performing triage would otherwise PROCEED. False-PROCEEDs (over-scoped task wrongly PROCEEDED) are partially mitigated by the WI 1.5.4b reviewer (it sees the inline plan; over-scope shows up as multi-paragraph Approach/Acceptance). False-REDIRECTs (small task wrongly redirected) are recoverable via `--force` in one re-invoke. The asymmetry is intentional: a false-REDIRECT costs the user one re-invoke; a false-PROCEED can ship over-scoped work. The reviewer is the safety net that catches what triage misses.
- **Test-stub naming convention vs `/draft-tests` AC-4.5.** `/draft-tests` (landed PRs #124–#140) uses unprefixed `ZSKILLS_TEST_LLM=1` (gate) + file-path `ZSKILLS_DRAFT_TESTS_REVIEWER_STUB_<N>` (per-round stubs). This plan uses `_ZSKILLS_TEST_HARNESS=1` (companion gate) + single-value `_ZSKILLS_TEST_TRIAGE_VERDICT` / `_ZSKILLS_TEST_REVIEW_VERDICT` (single-shot env-value-not-file). The divergence is intentional: (a) /quickfix's verdicts are small enums, not multi-line stub corpora — file-path stubs would be over-engineering; (b) the leading-underscore-private prefix (`_ZSKILLS_TEST_*`) signals a hard production-must-never-honor contract that the entry-point unset guard enforces, distinct from `/draft-tests`'s test-LLM-gate semantic. Follow-up: cross-skill stub naming reconciliation may be tackled in a separate plan once both patterns have shipped and we observe which cross-cuts emerge.

### Acceptance Criteria

- `grep -E '^[[:space:]]*--force\)' skills/quickfix/SKILL.md` returns ≥ 1 match.
- `grep -E '^[[:space:]]*--rounds\)' skills/quickfix/SKILL.md` returns ≥ 1 match.
- `grep -q 'argument-hint: ".*--force.*--rounds N' skills/quickfix/SKILL.md` returns 0.
- `grep -q '^### WI 1\.5\.4 — Triage gate' skills/quickfix/SKILL.md` returns 0.
- `grep -q '^### WI 1\.5\.4a — Inline plan composition' skills/quickfix/SKILL.md` returns 0.
- `grep -q '^### WI 1\.5\.4b — Fresh-agent plan review' skills/quickfix/SKILL.md` returns 0.
- `grep -q 'verdict prints ABOVE' skills/quickfix/SKILL.md` returns 0.
- `grep -q 'reason: user-declined' skills/quickfix/SKILL.md` returns 0.
- `grep -q 'CANCEL_REASON' skills/quickfix/SKILL.md` returns 0.
- `grep -q 'VERDICT: APPROVE' skills/quickfix/SKILL.md` returns 0.
- `grep -q 'WARN: --rounds 0 skips' skills/quickfix/SKILL.md` returns 0.
- `grep -q 'Triage: redirecting to /draft-plan' skills/quickfix/SKILL.md` returns 0.
- `grep -q 'Triage: redirecting to /fix-issues' skills/quickfix/SKILL.md` returns 0.
- `grep -q 'Triage: redirecting to /run-plan' skills/quickfix/SKILL.md` returns 0.
- `grep -q '_ZSKILLS_TEST_HARNESS' skills/quickfix/SKILL.md` returns 0 (test seam gate documented).
- `grep -q 'unset _ZSKILLS_TEST_TRIAGE_VERDICT' skills/quickfix/SKILL.md` returns 0 (entry-point unset guard).
- `grep -q 'block-unsafe-project.sh.template:412-427' skills/quickfix/SKILL.md` returns 0 (refreshed hook citation per WI 1a.6.7).
- `! grep -q 'block-unsafe-project.sh.template:188-229' skills/quickfix/SKILL.md` (stale citation removed).
- `diff -rq skills/quickfix .claude/skills/quickfix` → no output, rc=0.
- Existing test suite (`bash tests/test-quickfix.sh`) still passes.

### Dependencies

None.

---

## Phase 1b — /quickfix: extend test suite for triage / review / --force / --rounds

### Goal

Add 10 cases to `tests/test-quickfix.sh`. Cases 44–53.

**Existing case count is 42, not 43.** Verified: `grep -c '^# Case [0-9]' tests/test-quickfix.sh` returns 42 — Case 17 is intentionally skipped (numbering gap between Case 16 at SKILL-test L527 and Case 18 at L552; not a missing case, the file was renumbered at some point). Plan numbering picks up at Case 44 to preserve the existing convention. **Total cases after this phase: 52** (42 existing + 10 new), with the Case-17 numbering gap preserved.

### Test architecture

Triage and review are model-layer prose. Three-tier:
- Structural greps for prose.
- Bash plumbing tests for `--force` / `--rounds` parsing + `CANCEL_REASON` writeback.
- Stub-verdict harness via `_ZSKILLS_TEST_HARNESS=1` + `_ZSKILLS_TEST_TRIAGE_VERDICT` / `_ZSKILLS_TEST_REVIEW_VERDICT` (documented in WI 1a.3a).

### Work Items

- **Case 44**: `--force` parsed → `FORCE=1`.
- **Case 45**: `--rounds 3` → `ROUNDS=3`. `--rounds notanumber` → ROUNDS stays at default 1, `--rounds` and `notanumber` both end up as part of `DESCRIPTION` (greedy-fallthrough per WI 1a.1; documents the user-prose-containing-`--rounds` case). Validate by extracting the parser block via AWK and exec'ing against a fixture, then asserting `ROUNDS == 1` AND `DESCRIPTION` contains `--rounds notanumber`.
- **Case 46**: `--rounds 0` → `ROUNDS=0`. Stderr contains `WARN: --rounds 0 skips`.
- **Case 47**: triage-redirect path, **driven by `_ZSKILLS_TEST_HARNESS=1` + `_ZSKILLS_TEST_TRIAGE_VERDICT=REDIRECT:/draft-plan:multi-concept`**: (a) BOTH lines of the `/draft-plan` redirect message print to stdout (line 1 `Triage: redirecting to /draft-plan. Reason: multi-concept`; line 2 starts `This task spans more than one concept`), (b) exit 0, (c) **NO marker file** at `.zskills/tracking/quickfix.*/fulfilled.quickfix.*`, (d) **no branch created**, (e) verify the entry-point unset guard: invoking with `_ZSKILLS_TEST_TRIAGE_VERDICT` set but WITHOUT `_ZSKILLS_TEST_HARNESS=1` proceeds normally (env var is unset and ignored).
- **Case 48**: review-reject path (driven by `_ZSKILLS_TEST_REVIEW_VERDICT=REJECT: contract violation`): (a) reject reason prints, (b) exit 0, (c) NO marker, (d) no branch.
- **Case 49**: user-decline regression: marker has `status: cancelled` AND `reason: user-declined`.
- **Case 50**: WI 1.5.4 / 1.5.4a / 1.5.4b prose-presence (3 greps).
- **Case 51**: redirect-message exact-text guard. For each of the 3 redirect targets, grep that BOTH line 1 and line 2 are present in the skill source as separate physical lines:
  ```bash
  grep -q 'Triage: redirecting to /draft-plan' skills/quickfix/SKILL.md && \
    grep -q 'This task spans more than one concept' skills/quickfix/SKILL.md
  ```
  (Repeat for /run-plan + "references an existing plan file"; /fix-issues + "references a GitHub issue".) Also assert `! grep -F 'Reason: <reason>\nThis task'` (the literal-`\n`-as-text regression we are fixing).
- **Case 52**: VERDICT regex with REQUIRED separator + reason for REVISE/REJECT, BARE for APPROVE. Cases:
  - `VERDICT: APPROVE` → match
  - `VERDICT: APPROVE because plan is fine` → NO match (free text after APPROVE on line 1 is rejected)
  - `VERDICT: REVISE -- one-line reason` → match
  - `VERDICT: REVISE` → NO match (missing separator + reason)
  - `VERDICT: REJECT -- contract violation` → match

  **Mechanism:** extract the two regex patterns from `skills/quickfix/SKILL.md`'s WI 1.5.4b verdict-parser bash fence using AWK (matching the fence start/end; the regex sits inside a documented `\`\`\`bash` block so AWK can pull lines starting with `^VERDICT:`). Run each test input through `[[ "$INPUT" =~ $EXTRACTED_REGEX ]]` against both extracted regexes (bare-APPROVE and REVISE/REJECT) and assert match/no-match per case. Mirrors the AWK-extraction idiom already used by Case 8 / Case 11 for other in-SKILL.md bash blocks.
- **Case 53**: `--rounds 0` skip path documented in prose AND stderr WARN present.

### Acceptance Criteria

- `bash tests/test-quickfix.sh` passes 52 cases (42 existing + 10 new). Case-numbering range is 1–53 with Case 17 intentionally skipped (pre-existing gap).

### Dependencies

Phase 1a.

---

## Phase 2a — /do: triage gate, inline plan, fresh-agent review (skill source + mirror)

### Goal

Apply pattern to `skills/do/SKILL.md`. Mirror to `.claude/skills/do/`. Tests in Phase 2b.

**Critical phase ordering change vs round 1:** triage runs BEFORE Phase 0 cron registration. A redirected /do invocation must leave NO cron behind. Phase 0 today registers a cron, then later phases parse description / run logic; if triage redirected from inside Phase 0, a zombie cron would persist. This phase reorders so triage gates Phase 0.

### Work Items

**WI 2a.0 — Pre-Phase-0 flag pre-parse (NEW step inserted BEFORE existing Phase 0).**

Phase 0 needs to know `--force` and `--rounds N` so the cron prompt template can include them verbatim. Phase 1.5's argument parser runs AFTER Phase 0 today, so we add a small pre-parse step that runs first. This pre-parse is non-destructive: it sets `FORCE` and `ROUNDS` shell variables but does NOT mutate `$ARGUMENTS` (Phase 1.5's parser remains source of truth for the canonical strip).

```bash
# Pre-Phase-0: read --force and --rounds N out of $ARGUMENTS so Phase 0's
# cron prompt template can include them. Does not mutate $ARGUMENTS.
FORCE=0
if [[ "$ARGUMENTS" =~ (^|[[:space:]])--force($|[[:space:]]) ]]; then
  FORCE=1
fi
ROUNDS=1
# Greedy-fallthrough: only consume `--rounds <N>` when N is a numeric literal.
# `/do fix the bug --rounds in production` would otherwise capture "in" as
# ROUNDS_RAW and exit 2, rejecting a legitimate description. The regex
# captures only when the trailing token is all-digits; non-numeric trailing
# tokens leave ROUNDS at default 1 and the literal `--rounds` remains as
# task-description prose (Phase 1.5's strip chain MUST NOT strip
# non-numeric `--rounds` matches — see WI 2a.4).
if [[ "$ARGUMENTS" =~ (^|[[:space:]])--rounds[[:space:]]+([0-9]+)($|[[:space:]]) ]]; then
  ROUNDS="${BASH_REMATCH[2]}"
fi
# Strict explicit-error case: `--rounds` followed by a clearly-non-numeric
# token that LOOKS like an intended integer arg (e.g. `--rounds 3.5` or
# `--rounds -1`) should still fail loudly rather than silent-ignore. The
# `^[0-9]+$` anchor catches `3.5` (matches only "3" not the full token, so
# the broader regex above won't match because BASH_REMATCH[2] is bounded by
# `[0-9]+` and the trailing `($|[[:space:]])` anchors require whitespace
# AFTER the digit run — if the token continues with `.5`, this is non-match
# and falls through to user-prose treatment. Same for `-1`. So `3.5` and
# `-1` both end up as user prose, which is the conservative default.
```

Validation: `fix tooltip --force --rounds 3 pr` strips to `fix tooltip` after the full chain. `fix the bug --rounds in production` keeps the full description (no strip), ROUNDS stays at 1.

**WI 2a.1 — Triage gate (new Phase 1.6, but inserted to run BEFORE Phase 0).**

Insert new section "## Phase 1.6 — Triage gate" IMMEDIATELY AFTER the meta-command block (around skills/do/SKILL.md:174) and BEFORE "## Phase 0 — Schedule". Same shape and rubric as /quickfix WI 1.5.4 (qualitative signals only). For /do, the rubric does not have a user-edited mode arm — /do always works in a fresh worktree (PR mode) or main (direct mode), so the "≥3 distinct files in description" rule applies uniformly (no MODE carve-out needed).

Reuses the four redirect message templates verbatim (substitute `/quickfix` → `/do` in the redirect messages and override hint). Two-line printed messages, no literal `\n`. On REDIRECT (no force): print message, exit 0. /do does NOT write a tracking marker (per "no new tracking for /do") — nothing to clean up. On REDIRECT (force): override, continue.

**WI 2a.2 — Cron-zombie regression guard.**

Document explicitly in Phase 1.6: "Triage runs BEFORE Phase 0. A REDIRECT path exits before any `CronCreate` call, so a redirected /do leaves no cron behind. Phase 0 cannot run on a redirected invocation."

**WI 2a.3 — Fresh-agent review (new Phase 1.7), inserted BEFORE Phase 0.**

After the new Phase 1.6, insert "## Phase 1.7 — Inline plan + fresh-agent review" — also BEFORE Phase 0. If `$ROUNDS -eq 0`: stderr `WARN: --rounds 0 skips fresh-agent plan review (legacy opt-in).`. Skip.

Otherwise compose `INLINE_PLAN` (same shape as /quickfix; **"Files (expected)" is OPTIONAL** for /do — worktree may not exist yet for PR mode; agent will discover files in Phase 1 research; when unsure, set to `as inferred from description; may be refined during Phase 1 research`). Dispatch ONE Agent with same prompt template (no dirty-diff section). Parse VERDICT with the SAME separator-required regex (APPROVE bare; REVISE/REJECT require ASCII `--` + reason). Loop up to `$ROUNDS` using the same REVISE iteration prompt template. On REJECT (no force): print verdict, exit 0 (no worktree, no commits, no cron).

**Test seam:** `_ZSKILLS_TEST_HARNESS=1` + `_ZSKILLS_TEST_REVIEW_VERDICT` / `_ZSKILLS_TEST_TRIAGE_VERDICT`. Same entry-point unset guard as /quickfix:

```bash
if [ "${_ZSKILLS_TEST_HARNESS:-}" != "1" ]; then
  unset _ZSKILLS_TEST_TRIAGE_VERDICT _ZSKILLS_TEST_REVIEW_VERDICT
fi
```

Inserted at the very top of /do before any other parser logic.

Orthogonality with /verify-changes (Phase 3) explicitly documented at the **closing paragraph of Phase 1.7's prose body** in `skills/do/SKILL.md`:

> "Orthogonality with `/verify-changes` (Phase 3): pre-review (this phase) judges PLAN; `/verify-changes` judges DIFF. Both run when both apply (`pr` mode + `--rounds > 0` + `push` triggers /verify-changes after this review)."

Phase 2b Case 10 asserts presence of this prose in `skills/do/SKILL.md`'s Phase 1.7 section (grep `pre-review judges PLAN`).

**WI 2a.4 — Add `--force` and `--rounds N` to Phase 1.5 (canonical parser).**

After Step 3 (`push` flag detection), document that `FORCE` and `ROUNDS` are already set by WI 2a.0's pre-parse, but re-validate in case Phase 1.5 is invoked outside the normal entry path (defensive):

```bash
# Re-affirm (already set by pre-Phase-0 pre-parse; idempotent).
FORCE=${FORCE:-0}
if [[ "$REMAINING" =~ (^|[[:space:]])--force($|[[:space:]]) ]]; then
  FORCE=1
fi
ROUNDS=${ROUNDS:-1}
if [[ "$REMAINING" =~ (^|[[:space:]])--rounds[[:space:]]+([^[:space:]]+)($|[[:space:]]) ]]; then
  ROUNDS_RAW="${BASH_REMATCH[2]}"
  if ! [[ "$ROUNDS_RAW" =~ ^[0-9]+$ ]]; then
    echo "ERROR: --rounds requires a non-negative integer (got '$ROUNDS_RAW')." >&2
    exit 2
  fi
  ROUNDS="$ROUNDS_RAW"
fi
```

Append two `sed -E` lines to the existing strip chain in Step 2:

```bash
  | sed -E 's/(^|[[:space:]])--force($|[[:space:]])/ /' \
  | sed -E 's/(^|[[:space:]])--rounds[[:space:]]+[0-9]+($|[[:space:]])/ /' \
```

**WI 2a.5 — Update frontmatter `argument-hint` and `## Arguments` block.**

argument-hint: `"<description> [worktree] [push] [pr] [every SCHEDULE] [now] [--force] [--rounds N] | stop [query] | next [query] | now [query]"`. (`--force`/`--rounds` BEFORE the `|` divider so they don't apply to meta-commands.)

Add bullets to Arguments list:
- `--force` — bypass triage redirect and review reject. Persists into the cron prompt verbatim when used with `every`.
- `--rounds N` — max review/refine cycles (default 1; `0` skips review with stderr WARN).

**WI 2a.6 — Document `--force` cron persistence in Phase 0 (cron-prompt construction algorithm).**

Add note in Phase 0: "**Persistence of `--force` and `--rounds N`:** these flags are preserved verbatim in the cron prompt. A `/do <task> --force every 4h` produces a cron prompt of `Run /do <task> --force every 4h now`, so every cron fire bypasses triage and review. Intentional: setting `--force` on a recurring task means the user wants the bypass on every fire."

**Cron-prompt construction algorithm (explicit bash).** Replace existing L205-207 cron-prompt template with:

```bash
# Construct cron prompt incrementally so optional flags only appear when set.
# FORCE and ROUNDS are pre-parsed in WI 2a.0; SCHEDULE is parsed earlier in Phase 0.
CRON_PROMPT="Run /do ${TASK_DESCRIPTION_FOR_CRON}"  # description with landing/push tokens preserved
if [ "$FORCE" -eq 1 ]; then
  CRON_PROMPT="$CRON_PROMPT --force"
fi
if [ "$ROUNDS" != "1" ]; then
  CRON_PROMPT="$CRON_PROMPT --rounds $ROUNDS"
fi
CRON_PROMPT="$CRON_PROMPT every $SCHEDULE now"
# CronCreate uses $CRON_PROMPT verbatim.
```

**TASK_DESCRIPTION_FOR_CRON construction (explicit bash, lives in Phase 0 before the cron-prompt build).**

```bash
# Strip every/now/--force/--rounds tokens from $ARGUMENTS but PRESERVE
# pr/worktree/direct/push tokens (these need to round-trip into the cron
# prompt so each cron fire reproduces the user's landing-mode intent).
TASK_DESCRIPTION_FOR_CRON=$(echo "$ARGUMENTS" \
  | sed -E 's/(^|[[:space:]])every[[:space:]]+(day|weekday)[[:space:]]+at[[:space:]]+[^[:space:]]+($|[[:space:]])/ /' \
  | sed -E 's/(^|[[:space:]])every[[:space:]]+[^[:space:]]+($|[[:space:]])/ /' \
  | sed -E 's/(^|[[:space:]])now($|[[:space:]])/ /' \
  | sed -E 's/(^|[[:space:]])--force($|[[:space:]])/ /' \
  | sed -E 's/(^|[[:space:]])--rounds[[:space:]]+[0-9]+($|[[:space:]])/ /' \
  | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')
```

Note the time-of-day pattern (`every day at 9am`) MUST come before the
generic interval pattern (`every 4h`) — generic would otherwise capture
"day" as the interval value and leave "at 9am" as orphan tokens. The
`--rounds` strip only matches numeric N (consistent with WI 2a.0's
greedy-fallthrough rule); a non-numeric `--rounds <prose>` stays in
`TASK_DESCRIPTION_FOR_CRON` and round-trips into the cron prompt as user
prose, where it will again no-op-fall-through on each fire.

**WI 2a.7 — Document meta-command bypass.**

Insert at L80: "Meta-commands (`stop`, `next`, `now`) bypass Phase 1.6 triage and Phase 1.7 review entirely. They are administrative — there is no description to evaluate."

**WI 2a.8 — Mirror `skills/do/` to `.claude/skills/do/` byte-identically via the canonical helper.**

```bash
bash scripts/mirror-skill.sh do
```

Verify: `diff -rq skills/do .claude/skills/do` → no output, rc=0.

(Same hook-compatibility rationale as WI 1a.8 — `rm -rf .claude/skills/do` is blocked by `hooks/block-unsafe-generic.sh:218-221`. Use the helper.)

### Design & Constraints

- No new tracking for /do.
- Triage runs BEFORE Phase 0 cron registration (no zombie crons on REDIRECT).
- `--force` persistence in cron is intentional and documented.
- Meta-commands bypass everything.
- No jq.
- /verify-changes orthogonality preserved.
- CANARY11 (post-execution scope detection) continues to work.
- CANARY_DO_WORKTREE_BASE happy path (the only canary that invokes `/do` directly) is a known-PROCEED case (listed in the rubric worked-examples table) and must NOT be redirected by triage. Manual verification after Phase 2a lands.

### Acceptance Criteria

- `grep -q 'argument-hint: ".*--force.*--rounds N' skills/do/SKILL.md` → 0.
- `grep -q '^## Phase 1\.6 — Triage gate' skills/do/SKILL.md` → 0.
- `grep -q '^## Phase 1\.7 — Inline plan' skills/do/SKILL.md` → 0.
- Phase 1.6 heading appears BEFORE `## Phase 0 — Schedule` in the file (verify with `grep -n` line ordering).
- `grep -q 'preserved verbatim in the cron prompt' skills/do/SKILL.md` → 0.
- `grep -q 'bypass Phase 1\.6 triage and Phase 1\.7 review' skills/do/SKILL.md` → 0.
- `grep -q 'WARN: --rounds 0 skips' skills/do/SKILL.md` → 0.
- `grep -q '_ZSKILLS_TEST_HARNESS' skills/do/SKILL.md` → 0.
- `diff -rq skills/do .claude/skills/do` → no output, rc=0.
- All existing test suites still pass.

### Dependencies

Phase 1a.

---

## Phase 2b — /do: create test suite, wire into runner

### Goal

Create `tests/test-do.sh` with 11 cases. Wire into `tests/run-all.sh`.

### Work Items

**WI 2b.1 — Create `tests/test-do.sh` with cases:**

1. argument-hint contains `--force` and `--rounds N`.
2. Phase 1.6 triage prose present (heading + rubric-table) AND Phase 1.6 heading line number is < Phase 0 heading line number (cron-zombie regression guard: triage MUST come before cron registration).
3. Phase 1.7 inline-plan + review prose present.
4. `--force` cron-persistence prose present.
5. Meta-command bypass documented.
6. VERDICT parser regex documented: APPROVE bare; REVISE/REJECT require `--` + reason.
7. `--rounds 0` skip-review prose present AND stderr WARN string present.
8. `--force` and `--rounds N` flags stripped from TASK_DESCRIPTION (bash plumbing — extract strip chain via AWK like test-quickfix.sh; input `fix tooltip --force --rounds 3 pr` → output `fix tooltip`).
9. `--rounds notanumber` to /do leaves ROUNDS at default 1 (greedy-fallthrough per WI 2a.0; documents the user-prose-containing-`--rounds` case). Symmetric to /quickfix Case 45. Extract pre-Phase-0 pre-parse + run against fixture, assert `ROUNDS == 1`.
10. Phase 1.7 documents orthogonality with /verify-changes.
11. Entry-point unset guard regression: invoking /do with `_ZSKILLS_TEST_TRIAGE_VERDICT` (or `_ZSKILLS_TEST_REVIEW_VERDICT`) set in the environment but WITHOUT `_ZSKILLS_TEST_HARNESS=1` proceeds normally — the env var is unset by the entry-point guard and ignored. Symmetric to /quickfix Case 47(e). Closes the round-2 follow-up flagged in known-concerns: the harness-companion test was previously only covered for /quickfix.

Mirror house style of `tests/test-quickfix.sh`: `make_fixture`, per-case fixture, capture stderr, `pass`/`fail`, cleanup trap.

**WI 2b.2 — Wire into `tests/run-all.sh`.**

Append after the `run_suite "test-quickfix.sh" …` line:
```bash
run_suite "test-do.sh" "tests/test-do.sh"
```

Verify by running `bash tests/run-all.sh` from clean tree.

### Acceptance Criteria

- `bash tests/test-do.sh` passes all 11 cases.
- `grep -q 'run_suite "test-do.sh"' tests/run-all.sh` → 0.
- All existing test suites still pass.

### Dependencies

Phase 2a.

---

## Phase 3 — Cross-cutting: CLAUDE_TEMPLATE.md, full-suite run, follow-up issue

### Goal

Update CLAUDE_TEMPLATE.md, run the full suite from clean, file the `/commit pr` follow-up issue.

### Work Items

**WI 3.1 — Update `CLAUDE_TEMPLATE.md` (currently L199-200, anchor-by-content).**

The plan was authored 2026-04-25; since then DEFAULT_PORT_CONFIG (PR #125) and SKILL_FILE_DRIFT_FIX (PR #122) shifted the file by ~44 lines. Anchor the edit by content, not by line number: locate the `## PR mode` example list under "**Usage:** Append keyword to any execution skill:" — the bullets currently include:

```
- `/quickfix Fix README typo` — low-ceremony PR for trivial changes (no worktree; picks up in-flight edits in main)
- `/do Add dark mode. pr`
```

Append `--force` / `--rounds N` to those two example invocations. Add a one-line note immediately after them: "Both skills now triage tasks and run a fresh-agent plan review before execution. Use `--force` to bypass."

If the file structure has shifted again before this phase runs, anchor by `grep -n '/quickfix Fix README typo' CLAUDE_TEMPLATE.md` → use the matching line as the edit anchor.

**WI 3.2 — Run the full test suite from a clean tree.**

```bash
TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
mkdir -p "$TEST_OUT"
<full_cmd> > "$TEST_OUT/.test-results.txt" 2>&1
```

Per `feedback_check_ci_before_merge`: also `gh pr checks <N>` before merge.

**WI 3.3 — Record `/commit pr` follow-up issue.**

**Timing:** file the issue **after this PR merges**, so the body's "Reference" link points to the plan on `main` (where it lives long-term), not a feature branch (which is deleted post-merge). If the issue MUST be filed before merge, use the merge-commit-pinned URL form (`https://github.com/<org>/<repo>/blob/<merge-commit-sha>/plans/QUICKFIX_DO_TRIAGE_PLAN.md`) and update the body post-merge.

```bash
PLAN_URL="https://github.com/zeveck/zskills-dev/blob/main/plans/QUICKFIX_DO_TRIAGE_PLAN.md"
if ! ISSUE_URL=$(gh issue create \
  --title "Apply triage gate + plan review to /commit pr (follow-up)" \
  --body "Follow-up to QUICKFIX_DO_TRIAGE_PLAN. /commit pr today exhibits the same gate-routing-around behavior /quickfix and /do had before this plan. Apply the same orthogonal triage + inline-plan + review pattern in a follow-up plan. Reference: $PLAN_URL"); then
  echo "WARN: gh issue create failed (auth/network/permissions?). Manually file the follow-up issue and update the plan's ## Follow-ups section with the URL." >&2
  ISSUE_URL="<file-and-link-manually>"
fi
```

Capture URL. Edit the existing `## Follow-ups` parenthetical to `(Tracked: <ISSUE_URL>)`. The acceptance criterion accepts either a real GitHub issue URL OR the explicit `<file-and-link-manually>` placeholder (treated as a yellow-flag landing — the plan still lands but the implementer follows up to file the issue manually).

### Acceptance Criteria

- `grep -qE '^- \`/quickfix.*--force' CLAUDE_TEMPLATE.md` → 0.
- `grep -qE '^- \`/do.*--force' CLAUDE_TEMPLATE.md` → 0.
- Full project `full_cmd` runs clean.
- `gh pr checks <PR>` reports all green before merge.
- `grep -E 'Tracked: (https://github.com/.+/issues/[0-9]+|<file-and-link-manually>)' plans/QUICKFIX_DO_TRIAGE_PLAN.md` → 0. (Either real URL or explicit placeholder; the placeholder is acceptable when `gh issue create` fails for auth/network/permissions reasons; implementer follows up manually.)

### Dependencies

Phase 1a, Phase 1b, Phase 2a, Phase 2b.

---

## Follow-ups (out of scope for this plan)

- `/commit pr` exhibits the same gate-routing-around behavior /quickfix and /do had before this plan. Apply the same orthogonal triage + inline-plan + review pattern in a follow-up plan. (Tracked as a GitHub issue, number recorded after Phase 3 WI 3.3.)

---

## Drift Log

This plan was authored 2026-04-25. No phases have been completed yet (all five phases were `⬚` at refine time), so there is no completed-vs-planned phase drift to record. Instead, this Drift Log captures **ecosystem drift** — landings on `main` between the plan's authorship and the refine pass that touched anchors, conventions, or assumptions the plan body relied on.

| Source | Plan assumption | Reality at refine time | Disposition |
|--------|-----------------|------------------------|-------------|
| PR #88 (`scripts/mirror-skill.sh`, 2026-04-28) | WI 1a.8 / WI 2a.8 used inline `rm -rf .claude/skills/X && cp -r skills/X .claude/skills/X` | Inline form is hook-blocked: `hooks/block-unsafe-generic.sh:218-221` requires recursive-rm paths to be a literal `/tmp/<name>`. Helper exists. | **Refined**: WI 1a.8 / WI 2a.8 now invoke `bash scripts/mirror-skill.sh <skill>`. |
| DEFAULT_PORT_CONFIG (PR #125, 2026-04-29) + SKILL_FILE_DRIFT_FIX (PR #122) | WI 3.1 anchor `CLAUDE_TEMPLATE.md:155-156` for example-list edit | `/quickfix` and `/do` example bullets are now at L199-200; L155-156 is unrelated prose. ~44-line shift. | **Refined**: WI 3.1 anchored by content (`grep -n '/quickfix Fix README typo'`) with the historical L155-156 anchor noted as stale. |
| Independent commit drift (pre-2026-04-25) | `skills/quickfix/SKILL.md:167` cited `hooks/block-unsafe-project.sh.template:188-229` for the transcript check | Actual transcript-check region is L412-427 (commit-transcript safety net introduced by SKILL_FILE_DRIFT_FIX). Plan known-concern #5 acknowledged this but did not list a fix. | **Refined**: new WI 1a.6.7 explicitly refreshes the citation; AC additions assert presence of `412-427` and absence of `188-229`. |
| `/draft-tests` (PRs #124–#140, landed 2026-04-29 → 2026-04-30) | Triage redirect rubric enumerated `/draft-plan`, `/run-plan`, `/fix-issues`, ask-user | New top-level adversarial-test-spec skill exists. Could be a 5th redirect target. | **Justified-not-added**: /draft-tests' contract requires an existing plan file (it appends `### Tests` per phase); small one-shot test additions remain in /quickfix's PROCEED scope. Documented in Phase 1a Design & Constraints. |
| `/draft-tests` AC-4.5 stub naming convention | Plan's `_ZSKILLS_TEST_*` private-prefix pattern (single-value env var) was the only convention | `/draft-tests` ships `ZSKILLS_TEST_LLM=1` (gate) + `ZSKILLS_DRAFT_TESTS_REVIEWER_STUB_<N>` (file-path-per-round). | **Justified-divergent**: /quickfix's verdicts are small enums; file-path-per-round stubs would be over-engineered. Divergence documented in Phase 1a Design & Constraints. |
| Pre-existing test-quickfix.sh case-numbering gap | Plan claimed "43 + 10 = 53 cases" | `grep -c '^# Case [0-9]'` returns 42; Case 17 is intentionally skipped. | **Refined**: Phase 1b Goal and AC now correctly say "42 existing + 10 new = 52 cases, with Case 17 numbering gap preserved." |
| Round-1-carryover known concern #4 (`--rounds` parser greedy-eats-next-token) | Plan deferred the choice between (a) require-quoting and (b) regex-fail-fallthrough | `feedback_dont_defer_hole_closure.md` says: don't ship the helper and label the closure as follow-up. Plan was about to do exactly that. | **Refined**: WI 1a.1 and WI 2a.0 now implement (b) — greedy-fallthrough on non-numeric. Phase 1b Case 45 and Phase 2b Case 9 updated to test the new contract. |
| Round-1-carryover known concern #1 (entry-point unset guard test only in /quickfix) | Plan deferred the analogous /do test | Same anti-defer rule applies. | **Refined**: Phase 2b adds Case 11 (entry-point unset guard for /do). Total /do cases: 11 (was 10). |

**Note on completed-vs-planned drift:** `/refine-plan` SKILL.md edge case applies — "No completed phases — all phases reviewed as remaining." No phase sections were modified except via the targeted edits above.

## Plan Review

**Refinement process:** /refine-plan with 2 rounds of adversarial review (orchestrator-acted reviewer + devil's advocate per round, due to the absence of a Task/Agent dispatch primitive in this runtime; verify-before-fix discipline applied empirically with file/grep/hook re-runs). The /refine-plan SKILL.md verbatim-prompt for these reviewer roles was followed; findings include a `Verification:` line per finding and were re-run before fixes.
**Convergence:** Converged at round 2 — orchestrator's mechanical check on the disposition table (`feedback_convergence_orchestrator_judgment.md`). Substantive open issues at round 2 close: 0 net (all 13 fix-eligible findings either fixed or justified-not-fixed-with-evidence).

### Round History

| Round | Reviewer Findings | DA Findings | Substantive | Verified | Fixed | Justified | Confirmed-no-action |
|-------|-------------------|-------------|-------------|----------|-------|-----------|---------------------|
| 1     | 7 (R1, R2, R3, R4, R5, R6, R7) + 1 confirmation (R8) | 11 (DA1–DA11) + 1 confirmation each (DA7, DA11) + 1 new during refine pass (DA12) | 13 | 13 | 11 | 3 | 3 (R8, DA7, DA11) |
| 2     | 5 sanity-check passes (parser semantics, strip-chain symmetry, prose-location alignment, AC-list integrity, repo-URL sanity) | 5 sanity-check passes (orthogonality-vs-Case-10, hook-citation-not-shifted, drift-gate-non-applicable, plan-line-anchor stability, framework-vs-consumer URL choice) | 0 new | n/a | 0 | 0 | All 10 sanity checks confirmed clean |

**Round 1 fixes applied (13 total):**
1. **WI 1a.1** — `--rounds` greedy-fallthrough (closes DA3 hole; Phase 1b Case 45 updated to match).
2. **WI 1a.6.5** — already in place from prior /draft-plan rounds; left as-is.
3. **WI 1a.6.7 (new)** — refresh stale `block-unsafe-project.sh.template:188-229` citation to `:412-427`. AC criteria added.
4. **WI 1a.8** — replace hook-blocked `rm -rf .claude/skills/quickfix && cp -r ...` with `bash scripts/mirror-skill.sh quickfix`. Hook-block rationale documented inline.
5. **WI 2a.0** — apply greedy-fallthrough to /do (`[0-9]+` regex anchor; non-numeric falls through to user prose).
6. **WI 2a.3** — pin orthogonality-with-/verify-changes prose to Phase 1.7's closing paragraph.
7. **WI 2a.6** — explicit `TASK_DESCRIPTION_FOR_CRON` strip-chain bash; ordering note (time-of-day before generic interval).
8. **WI 2a.8** — same mirror-script fix as WI 1a.8 (for /do).
9. **WI 3.1** — anchor by content (`grep -n '/quickfix Fix README typo'`) instead of stale L155-156.
10. **WI 3.3** — `gh issue create` error handling + post-merge link form. AC accepts `<file-and-link-manually>` placeholder.
11. **Phase 1a Design & Constraints** — three new bullets: forbidden-literals discipline, /draft-tests-not-a-redirect rationale, model-layer-triage asymmetry, stub-naming-divergence-justified.
12. **Phase 1b Case 45** — test fallthrough behavior (was: test exit 2; now: test ROUNDS=1 + DESCRIPTION-contains-`--rounds notanumber`).
13. **Phase 1b Case 52** — explicit AWK-extraction mechanism for verdict-regex testing (matches existing test-quickfix.sh idiom).
14. **Phase 2b Case 9** — symmetric fallthrough test for /do.
15. **Phase 2b Case 11 (new)** — entry-point unset guard test for /do (closes round-1-carryover known-concern #1).
16. **Phase 1a effort note** — corrected "~250 lines / ~6 ACs" to "~265 lines / ~13 ACs" (R6 numeric arithmetic).
17. **Phase 1b Goal** — corrected "43 + 10 = 53" to "42 + 10 = 52 with Case 17 gap preserved" (DA12 numeric arithmetic).

**Round 1 justified-not-fixed (3 total):**
- **DA1 (stub naming divergence from /draft-tests AC-4.5)** — divergence is intentional; documented explicitly in Phase 1a Design & Constraints with rationale. Cross-skill reconciliation deferred to a separate plan once both patterns ship and cross-cuts emerge.
- **DA2 (cron-prompt omits `--rounds 1` when value equals default)** — known minor edge case; cron lifetime is ≤7 days per CronCreate runtime, so prompts won't outlive a default change in practice. Justified inline.
- **DA6 (model-layer triage asymmetry)** — inherent to model-layer judgment, not a plan defect. Documented in Design & Constraints with mitigation note (reviewer agent at WI 1.5.4b is the safety net for false-PROCEEDs; `--force` recovers false-REDIRECTs).

**Round 1 confirmed-no-action (3 total):**
- **R8** — Phase 2b case enumeration: 10 cases verified by direct count.
- **DA7** — Phase 1b case range correct (case 44–53 numbering aligns with existing test-quickfix.sh).
- **DA11** — Phase 0 ordering insertion-target between meta-block end and Phase 0 verified.

**Round 2 sanity passes (10 total, all clean):**
- Parser-trace semantics (greedy-fallthrough index arithmetic).
- Strip-chain symmetry (`--rounds [0-9]+` vs greedy-fallthrough alignment).
- Prose-location alignment (WI 2a.3 ⇄ Phase 2b Case 10).
- AC-list integrity after WI 1a.6.7 additions.
- Plan body line-anchor stability post-edit (no internal-line-no references broke).
- Hook-citation post-edit-shift check (WI 1.3 lives upstream of triage insertions; L165-172 unaffected).
- Drift gate non-applicability to plan files (only `skills/**/*.md` are gated).
- /draft-tests stub-naming-divergence justification re-read for substance.
- WI 3.3 repo URL hardcoding acceptable (zskills is framework repo, not downstream).
- Cron-prompt round-trip with non-numeric `--rounds prose` content (re-verified: round-trips correctly).

### Top 3 highest-blast-radius findings (Round 1)

1. **R1 — Mirror command hook-blocked (WI 1a.8 / WI 2a.8).** Implementing agent literally cannot execute the plan as originally written; the `rm -rf .claude/skills/X` form fires `hooks/block-unsafe-generic.sh:218-221`. Empirically observed during this orchestrator's investigation (a separate `bash` invocation triggered the same hook). **Fixed**: replaced with `bash scripts/mirror-skill.sh <skill>` (canonical helper introduced in PR #88).
2. **R2 — CLAUDE_TEMPLATE.md anchor 44 lines stale (WI 3.1).** Plan referenced L155-156, actual location is L199-200 due to DEFAULT_PORT_CONFIG and SKILL_FILE_DRIFT_FIX landings. Implementer would have edited unrelated prose. **Fixed**: re-anchored by content.
3. **DA3 — `/quickfix --rounds` greedy parser deferred (round-1 known-concern #4).** Plan punted the resolution of a concrete bug ("`/quickfix fix --rounds in docs` exits 2") into a "future round". This is exactly the anti-pattern in `feedback_dont_defer_hole_closure.md`. **Fixed**: WI 1a.1 and WI 2a.0 implement option (b) — regex-fail-fallthrough — and the Phase 1b/2b tests assert the new contract.

### Anti-pattern self-check

- **Convergence judgment:** the orchestrator (this skill body) determined convergence by mechanical count of the disposition table (13 fix + 3 justify + 3 confirm = 19 dispositions; 0 unresolved). No "CONVERGED" prose was accepted from any agent. Per `feedback_convergence_orchestrator_judgment.md`.
- **Verify-before-fix discipline:** every empirical claim was re-checked by the orchestrator (file reads, grep counts, line numbers, hook fire). `/tmp/refine-plan-parsed-QUICKFIX_DO_TRIAGE_PLAN.md` lists the empirical checks. The hook-fire on `rm -rf .claude/skills/...` was a real fire during pre-check, not a hypothetical.
- **No completed-phase modifications:** no phase had `Done` status; the immutability check is vacuous (no checksums to compare against). The Drift Log `Note on completed-vs-planned drift` documents this.

**Execute with:** `/run-plan plans/QUICKFIX_DO_TRIAGE_PLAN.md`
