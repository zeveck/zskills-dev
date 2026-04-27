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

**Phase 1a effort note:** Phase 1a touches WI 1.2 (parser), inserts WI 1.5.4 / 1.5.4a / 1.5.4b, edits WI 1.5.5 prose, edits WI 1.8 marker logic, and mirrors. Expect ~250 lines added to skills/quickfix/SKILL.md and ~6 small AC additions. Implementer should plan ~2-3 hours of careful prose work.

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
      i=$((i+1))
      ROUNDS="${ARGS[$i]:-}"
      if ! [[ "$ROUNDS" =~ ^[0-9]+$ ]]; then
        echo "ERROR: --rounds requires a non-negative integer (got '$ROUNDS')." >&2
        exit 2
      fi
      ;;
```

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

**WI 1a.8 — Mirror `skills/quickfix/` to `.claude/skills/quickfix/` byte-identically.**

```bash
cd /workspaces/zskills
rm -rf .claude/skills/quickfix
cp -r skills/quickfix .claude/skills/quickfix
```

Verify: `diff -rq skills/quickfix .claude/skills/quickfix` → no output, rc=0. Mirror is part of THIS phase to avoid divergence between source-landing and mirror-landing.

### Design & Constraints

- No new bash dependencies. WI 1.2 case-arm additions, `CANCEL_REASON` (user-decline only), `--rounds` integer validator, separator-required VERDICT parser regex.
- No `jq`.
- Pre-commit hook is not engaged (no commits during triage/review).
- Triage IS a "surface signal not patch" feature.
- Soft-reject vs hard-reject: REVISE cycles that exhaust `$ROUNDS` are treated as soft-reject. Two consecutive malformed verdicts also soft-reject.
- Triage-redirect and review-reject leave no branch, no marker, no tracking dir, no commits.
- Test seam env vars are gated on `_ZSKILLS_TEST_HARNESS=1`; without it, they are unset at entry. Production invocations cannot accidentally honor a stale test env var.

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
- `diff -rq skills/quickfix .claude/skills/quickfix` → no output, rc=0.
- Existing test suite (`bash tests/test-quickfix.sh`) still passes.

### Dependencies

None.

---

## Phase 1b — /quickfix: extend test suite for triage / review / --force / --rounds

### Goal

Add 10 cases to `tests/test-quickfix.sh`. Cases 44–53.

### Test architecture

Triage and review are model-layer prose. Three-tier:
- Structural greps for prose.
- Bash plumbing tests for `--force` / `--rounds` parsing + `CANCEL_REASON` writeback.
- Stub-verdict harness via `_ZSKILLS_TEST_HARNESS=1` + `_ZSKILLS_TEST_TRIAGE_VERDICT` / `_ZSKILLS_TEST_REVIEW_VERDICT` (documented in WI 1a.3a).

### Work Items

- **Case 44**: `--force` parsed → `FORCE=1`.
- **Case 45**: `--rounds 3` → `ROUNDS=3`. `--rounds notanumber` → rc=2 + discriminator `--rounds requires a non-negative integer`.
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
- **Case 53**: `--rounds 0` skip path documented in prose AND stderr WARN present.

### Acceptance Criteria

- `bash tests/test-quickfix.sh` passes (43 + 10 = 53 cases).

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
if [[ "$ARGUMENTS" =~ (^|[[:space:]])--rounds[[:space:]]+([^[:space:]]+)($|[[:space:]]) ]]; then
  ROUNDS_RAW="${BASH_REMATCH[2]}"
  if ! [[ "$ROUNDS_RAW" =~ ^[0-9]+$ ]]; then
    echo "ERROR: --rounds requires a non-negative integer (got '$ROUNDS_RAW')." >&2
    exit 2
  fi
  ROUNDS="$ROUNDS_RAW"
fi
```

Validation: `fix tooltip --force --rounds 3 pr` strips to `fix tooltip` after the full chain.

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

Orthogonality with /verify-changes (Phase 3) explicitly documented: "pre-review judges PLAN; /verify-changes judges DIFF; both run when both apply."

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

Note: `TASK_DESCRIPTION_FOR_CRON` is the original `$ARGUMENTS` minus the `every <schedule>` token and minus any meta-command tokens — i.e. the same payload Phase 1.5's strip chain operates on, but preserving `pr`/`worktree`/`direct`/`push` tokens. The model composes this from `$ARGUMENTS` directly in Phase 0.

**WI 2a.7 — Document meta-command bypass.**

Insert at L80: "Meta-commands (`stop`, `next`, `now`) bypass Phase 1.6 triage and Phase 1.7 review entirely. They are administrative — there is no description to evaluate."

**WI 2a.8 — Mirror `skills/do/` to `.claude/skills/do/` byte-identically.**

```bash
cd /workspaces/zskills
rm -rf .claude/skills/do
cp -r skills/do .claude/skills/do
```

Verify: `diff -rq skills/do .claude/skills/do` → no output, rc=0.

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

Create `tests/test-do.sh` with 10 cases. Wire into `tests/run-all.sh`.

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
9. `--rounds notanumber` to /do exits rc=2 with `--rounds requires a non-negative integer` discriminator (extract pre-Phase-0 pre-parse + run against fixture). Validates the error contract symmetry with /quickfix.
10. Phase 1.7 documents orthogonality with /verify-changes.

Mirror house style of `tests/test-quickfix.sh`: `make_fixture`, per-case fixture, capture stderr, `pass`/`fail`, cleanup trap.

**WI 2b.2 — Wire into `tests/run-all.sh`.**

Append after the `run_suite "test-quickfix.sh" …` line:
```bash
run_suite "test-do.sh" "tests/test-do.sh"
```

Verify by running `bash tests/run-all.sh` from clean tree.

### Acceptance Criteria

- `bash tests/test-do.sh` passes all 10 cases.
- `grep -q 'run_suite "test-do.sh"' tests/run-all.sh` → 0.
- All existing test suites still pass.

### Dependencies

Phase 2a.

---

## Phase 3 — Cross-cutting: CLAUDE_TEMPLATE.md, full-suite run, follow-up issue

### Goal

Update CLAUDE_TEMPLATE.md, run the full suite from clean, file the `/commit pr` follow-up issue.

### Work Items

**WI 3.1 — Update `CLAUDE_TEMPLATE.md` L155-156.**

Append `--force` / `--rounds N` to the existing example invocations. Add a one-line note: "Both skills now triage tasks and run a fresh-agent plan review before execution. Use `--force` to bypass."

**WI 3.2 — Run the full test suite from a clean tree.**

```bash
TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
mkdir -p "$TEST_OUT"
<full_cmd> > "$TEST_OUT/.test-results.txt" 2>&1
```

Per `feedback_check_ci_before_merge`: also `gh pr checks <N>` before merge.

**WI 3.3 — Record `/commit pr` follow-up.**

```bash
gh issue create \
  --title "Apply triage gate + plan review to /commit pr (follow-up)" \
  --body "Follow-up to QUICKFIX_DO_TRIAGE_PLAN. /commit pr today exhibits the same gate-routing-around behavior /quickfix and /do had before this plan. Apply the same orthogonal triage + inline-plan + review pattern in a follow-up plan. Reference: <link to this plan>"
```

Capture URL. Edit the existing `## Follow-ups` parenthetical to `(Tracked: <issue-URL>)`.

### Acceptance Criteria

- `grep -qE '^- \`/quickfix.*--force' CLAUDE_TEMPLATE.md` → 0.
- `grep -qE '^- \`/do.*--force' CLAUDE_TEMPLATE.md` → 0.
- Full project `full_cmd` runs clean.
- `gh pr checks <PR>` reports all green before merge.
- `grep -E 'Tracked: https://github.com/.+/issues/[0-9]+' plans/QUICKFIX_DO_TRIAGE_PLAN.md` → 0.

### Dependencies

Phase 1a, Phase 1b, Phase 2a, Phase 2b.

---

## Follow-ups (out of scope for this plan)

- `/commit pr` exhibits the same gate-routing-around behavior /quickfix and /do had before this plan. Apply the same orthogonal triage + inline-plan + review pattern in a follow-up plan. (Tracked as a GitHub issue, number recorded after Phase 3 WI 3.3.)

---

## Plan Quality

**Drafting process:** /draft-plan with 2 rounds of adversarial review (1 reviewer + 1 devil's advocate per round, single-refiner verify-before-fix).
**Convergence:** Converged at round 2.
**Remaining concerns:** 5 known un-addressed findings — none are design holes:
1. The `_ZSKILLS_TEST_HARNESS` entry-point unset is described in both /quickfix and /do but the test for it lives only in Case 47 (/quickfix). A future round could add an analogous case in `tests/test-do.sh`.
2. `TASK_DESCRIPTION_FOR_CRON` in WI 2a.6 is described loosely ("model composes from `$ARGUMENTS`"). The Phase 1.5 strip chain already handles this; a stricter spec could pin the exact strip steps.
3. The Phase 2b Case 2 line-ordering check (`Phase 1.6` line number < `Phase 0` line number) uses `grep -n` numeric comparison — robust but could be a more idiomatic bash test.
4. **Round 1 carry-over (DA3): `/quickfix --rounds` parser eats next token.** With the WI 1a.1 implementation as written, `/quickfix fix --rounds in docs` reads "in" as the integer arg, fails the regex, exits 2 — rejecting a legitimate description. Either (a) require quoting for descriptions containing `--rounds`, or (b) on regex-fail, treat as description token and fall through. Pick one and apply consistently to /do. Slipped through round 1's review-file mishap and was not flagged in round 2.
5. **Round 1 carry-over (DA7): stale hook line citation.** `skills/quickfix/SKILL.md:167` cites `hooks/block-unsafe-project.sh.template:188-229` for the transcript check; the actual region is L323-340. Drift in an unrelated commit. Not blocking — the plan can refresh while editing the file. Slipped through round 1's review-file mishap.

### Round History

| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1     | 14 (2 blocking, 8 substantive, 4 minor) | 12 (1 blocking, 6 substantive, 5 minor) | 13 verified+fixed; remainder open into round 2 |
| 2     | 12 (3 blocking, 5 substantive, 4 minor) | 12 (3 blocking, 7 substantive, 2 minor) | 24 verified+fixed; ≤3 minor refinements remain |

### Round 1 highlights (closed)

- Marker timing: triage/review redirect paths wrote `reason: triage-redirect` to a marker that didn't exist yet (WI 1.8 ran later). Fixed by exiting before WI 1.8 — no marker on these paths.
- /do `--force --rounds N` not stripped from TASK_DESCRIPTION. Added explicit sed lines.
- VERDICT regex hard-coded em-dash; ASCII variants failed. Made tolerant in round 1, then tightened in round 2 to require ASCII `--` for REVISE/REJECT (and bare for APPROVE) to avoid the dual-permissive failure mode round 2 found.
- Phase 2 split into 2a (skill source) + 2b (test file).
- Triage placed at WI 1.5.4 (between WI 1.5 and WI 1.5.5) so we don't ask the user `[y/N]` on a diff we'll then redirect.
- Mirrors moved into source phases (1a.8, 2a.8) — no source/runtime divergence window.
- Per-target redirect templates (`/draft-plan`, `/run-plan`, `/fix-issues`, ask-user) — single template was wrong shape for each.

### Round 2 highlights (closed)

- Cron zombie: /do registered cron in Phase 0 BEFORE triage in Phase 1.6, so a non-`--force` redirect left a perpetual no-op cron. Fixed by reordering: triage runs BEFORE Phase 0.
- "≥3 distinct files named" rubric regressed legitimate /quickfix user-edited multi-file dirty trees. Fixed by gating that rule to agent-dispatched mode only.
- Test-seam env-var leak hazard: a stale `QUICKFIX_TEST_REVIEW_VERDICT` in a user shell silently bypassed production review. Fixed with `_ZSKILLS_TEST_*` prefix + required `_ZSKILLS_TEST_HARNESS=1` companion + entry-point unset guard.
- Literal `\n` in redirect templates: would have been emitted as the two-character string instead of a newline. Fixed by specifying real linebreaks + `printf 'line1\nline2\n'`.
- VERDICT regex was too permissive on bare `VERDICT: REVISE` (empty reason → degenerate REVISE→REVISE loop) AND too strict on `VERDICT: APPROVE looks good` (rejected). Fixed: APPROVE bare; REVISE/REJECT require `--` + reason; malformed → retry once → soft-reject.
- INLINE_PLAN bash-var vs model-text ambiguity: clarified as "logical placeholder for text the model composes; copy verbatim into Agent prompt."
- WI 1.5.5 prose drift: existing wording said marker is set to cancelled at decline, but no marker exists at WI 1.5.5 time. Added WI 1a.6.5 fix.
- /quickfix vs /do `--rounds` error contracts: aligned both to exit 2 with the same discriminator.
- `--force` cron prompt construction: specified explicit incremental-construction bash so optional flags appear only when set.

**Execute with:** `/run-plan plans/QUICKFIX_DO_TRIAGE_PLAN.md`
