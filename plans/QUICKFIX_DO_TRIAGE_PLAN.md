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

**Phase 1a effort note:** Phase 1a touches WI 1.2 (parser), inserts WI 1.5.4 / 1.5.4a / 1.5.4b, edits WI 1.5.5 prose, edits WI 1.8 marker logic, refreshes the WI 1.3 Check 3 hook citation (WI 1a.6.7), and mirrors. Expect roughly 250-300 lines added to `skills/quickfix/SKILL.md` (planning estimate, not an acceptance criterion) and **20** grep-presence AC additions in the Acceptance Criteria block (counted by `awk '/^### Acceptance Criteria/,/^### Dependencies/' ... | grep -cE '^- .*grep'`). Implementer should plan ~2-3 hours of careful prose work.

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

Production invocations MUST dispatch a real model-layer triage decision. The test harness needs a deterministic stub. Use the `_ZSKILLS_TEST_*` prefix and a required companion harness flag as a hygiene convention to prevent accidental env-var inheritance from forwarding a stale test stub into production invocation (this is hygiene, not a security boundary — see Phase 1a Design & Constraints):

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

OBSERVABLE-SIGNAL RULE (mandatory): count the **Acceptance** bullets in
the inline plan. If >4 Acceptance bullets are present, you MUST return
`VERDICT: REVISE -- too many concepts; consider /draft-plan` regardless
of whether each bullet individually looks reasonable. This is a hard
auto-REVISE — not a judgment call. The Acceptance-bullet ceiling is the
concrete observable that distinguishes "task fits /quickfix" from "task
should /draft-plan." If the model proposes an Acceptance section that
exceeds the ceiling, the inline plan needs to be split, not rubber-stamped.

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

**Verdict parser (separator-required for REVISE/REJECT):** trim trailing whitespace from the first line, then match against this regex (in priority order). The fence MUST be ` ```regex `, NOT ` ```bash ` — `tests/test-quickfix.sh:226-235`'s `extract_full_flow` AWK extractor copies every `^```bash$`…`^```$` block between WI 1.5 and Phase 4 into `FULL_FLOW_SCRIPT` and exec's it. A `bash` fence here would dump bare regex strings into the executed script and Bash would error `command not found: ^VERDICT:`. Phase 1b Case 52's AWK-extraction logic must accordingly match `^```regex$` (or another non-bash fence) rather than `^```bash$` for THIS block. The same constraint applies to ALL documentation-only fences inserted by Phase 1a between WI 1.5 and Phase 4: any fence whose body is not literally executable bash MUST use a non-bash fence tag.

```regex
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

The current WI 1.5.5 (skills/quickfix/SKILL.md:265-289) says the user-decline path "set the tracking marker's `status` to `cancelled` and commit nothing. No branch is created yet at this point, so no rollback is needed." This wording predates the new triage/review gates and is misleading in the new design.

**Distinguish the two decline paths.** WI 1.5.5 itself has TWO decline arms with different marker semantics — the prose must capture both:

- **Model-layer decline (production path).** The model directly executes WI 1.5.5 in production: it asks the user, sees decline, calls `exit 0` from this WI's body. WI 1.5.5 runs BEFORE WI 1.8 in source order (L265 vs L348 in current `skills/quickfix/SKILL.md`), so at the model-layer decline point **no marker has been written and the EXIT trap has not been registered.** Production `exit 0` from this point leaves no marker — identical to triage-redirect / review-reject paths.
- **Bash-fallback decline (test-fixture path).** The `case "$answer" in *)` arm at WI 1.10 (skills/quickfix/SKILL.md:467-484) is the deterministic fallback used by the test suite under `--yes`-bypassed prompt fixtures. This arm runs AFTER WI 1.8 (the trap is registered, the marker exists at `status: started`). Setting `CANCEL_REASON='user-declined'` + `CANCELLED=1` lets the EXIT trap's `finalize_marker` transition the marker to `status: cancelled` + append `reason: user-declined`.

Update the WI 1.5.5 prose to:

> "Only proceed if the user affirms. If the user declines, exit cleanly with `exit 0`. There are two decline paths with different marker semantics:
>
> 1. **Production (model-layer) decline.** When the model itself executes WI 1.5.5 and the user types `n`, the script exits BEFORE WI 1.8 has run — no marker has been written, the EXIT trap is not registered, and no branch has been created. Identical observable end state to triage-redirect and review-reject: empty disk.
> 2. **Test-fixture (bash-fallback) decline.** When the bash extractor in the test suite hits the `case "$answer" in *)` arm at WI 1.10 (with `--yes`-bypassed prompt), WI 1.8 has already run — the marker exists at `status: started` and the EXIT trap is registered. WI 1.10 sets `CANCEL_REASON='user-declined'` and `CANCELLED=1`; the trap then runs `finalize_marker` which transitions `status: started` → `status: cancelled` and appends `reason: user-declined`.
>
> No branch is created at this confirmation point in either path, so no branch rollback is needed. (Triage redirect and review reject paths exit BEFORE WI 1.8 and write no marker at all — observably identical to the production decline path above.)"

The Phase 1b Case 49 grep `reason: user-declined` is correct — it asserts the test-fixture marker, which is the only path that produces a `reason:` line.

**WI 1a.6.7 — Refresh stale hook citation in WI 1.3 Check 3 prose.**

While editing `skills/quickfix/SKILL.md`, also update the stale citation at L165-172 (the WI 1.3 Check 3 "Test-cmd alignment gate" prose). Currently cites `hooks/block-unsafe-project.sh.template:188-229`; the actual transcript-check region is now at L412-427 (the commit-transcript safety net introduced by SKILL_FILE_DRIFT_FIX). Update:

| Old | New |
|-----|-----|
| `hooks/block-unsafe-project.sh.template:188-229` | `hooks/block-unsafe-project.sh.template:412-427` |

This is hygiene — the line range had drifted in unrelated commits before this plan landed. Verification: `grep -n 'FULL_TEST_CMD' hooks/block-unsafe-project.sh.template` returns L243, L252, L346, L351, L412-427 (the relevant safety net). The 188-229 region is unrelated to transcript checking in current state.

**WI 1a.7 — Update WI 1.8 marker shape and WI 1.10 rollback to add the optional `reason:` line for the user-decline path only.**

Marker started shape unchanged. Triage-redirect and review-reject leave NO marker (they exit before WI 1.8). Only the user-declined path (WI 1.5.5 / WI 1.10, after WI 1.8) needs `reason:`.

**Anchor by content, NOT by line number.** Phase 1a inserts WI 1.5.4 / 1.5.4a / 1.5.4b earlier in the file (~265 lines added before WI 1.8 / WI 1.10 per the effort-note estimate). Any pre-edit line citation (e.g. "around L374" or "around L467-484") will be stale by the time the implementer reaches WI 1a.7 within the SAME phase. Use these grep anchors:

```bash
# finalize_marker function start (was L375 pre-edit; will shift):
grep -n '^finalize_marker() {' skills/quickfix/SKILL.md
# Cancelled-by-user path within WI 1.10 (was L473 pre-edit; will shift):
grep -n 'Cancelled by user. Cleaning up branch' skills/quickfix/SKILL.md
```

**Edit 1 — Add `reason:` write to `finalize_marker`.**

The `finalize_marker` body has an outer `if [ -f "$MARKER" ]; then ... fi` guard wrapping a single `sed -i` line. Insert the new `reason:` block AFTER the closing `fi` of that outer guard and BEFORE the function's closing `}`. Placement after the `fi` (not nested inside it) is required so the reasoning is explicit: the new block has its own redundant `[ -f "$MARKER" ]` check, making it self-guarding and order-independent — placement nested inside vs outside the outer guard would be functionally equivalent today, but pinning OUTSIDE prevents future refactors of the outer guard from accidentally breaking the reason-write path.

```bash
  # NEW BLOCK — placed AFTER the outer `fi` (not nested inside it):
  if [ "$CANCELLED" -eq 1 ] && [ -n "${CANCEL_REASON:-}" ] && [ -f "$MARKER" ] \
     && ! grep -q '^reason:' "$MARKER"; then
    printf 'reason: %s\n' "$CANCEL_REASON" >> "$MARKER"
  fi
```

**Trap-ordering note.** The EXIT trap (`trap 'finalize_marker $?' EXIT`) fires AFTER the script exits, including after `exit 0` from the test-fixture user-decline path. `CANCEL_REASON` is set by the user-decline arm before that arm calls `exit 0`, so it is in scope when `finalize_marker` runs. (Production model-layer decline at WI 1.5.5 exits BEFORE the trap is registered; that path leaves no marker by design — see WI 1a.6.5.)

**Edit 2 — `CANCEL_REASON="user-declined"` in WI 1.10 cancel arm.**

In WI 1.10's `case "$answer" in *) ... esac` block (find via `grep -n 'Cancelled by user. Cleaning up branch'` then look 2 lines up for the `*)` arm), the cancel arm currently sets `CANCELLED=1` and prints "Cancelled by user. Cleaning up branch." Insert `CANCEL_REASON="user-declined"` IMMEDIATELY before the existing `CANCELLED=1`:

```bash
      *)
        CANCEL_REASON="user-declined"
        CANCELLED=1
        echo "Cancelled by user. Cleaning up branch." >&2
        ...
```

Update `### Terminal marker states`: "`status: cancelled` is appended with `reason: user-declined` (the only documented reason). Triage-redirect, review-reject, and production model-layer decline at WI 1.5.5 leave no marker — they exit before WI 1.8 writes one."

**WI 1a.8 — Mirror `skills/quickfix/` to `.claude/skills/quickfix/` byte-identically via the canonical helper.**

**Pre-mirror state check.** `scripts/mirror-skill.sh` performs `cp -a "$SRC/." "$DST/"` plus per-file orphan-removal via `diff -rq`. It does not validate that the source is itself in a clean, committed state, AND its orphan-removal step will silently delete any UNTRACKED file present in the destination but not in the source (e.g., a stray `notes.md` left by a prior agent). Before invoking the helper, the implementer MUST verify the destination side has NO pre-existing uncommitted state of any kind — modified, staged, OR untracked — because any of those would be silently absorbed (modified/staged) or silently deleted (untracked) without git history. `git diff --quiet` is INSUFFICIENT here: it does not detect untracked files. Use `git status --porcelain`, which surfaces all three states (`??` for untracked, `[ MAD]` for modified/added/deleted, `[MARC] ` for staged):

**Pinned precondition (final form):**

```bash
# Mirror destination must have no pre-existing uncommitted state — modified,
# staged, OR untracked. Any such state is from a prior session and would be
# silently absorbed (modified/staged) or silently deleted (untracked, via
# the helper's orphan-removal step) without git history. `git diff --quiet`
# is insufficient because it does not detect untracked files; use
# `git status --porcelain` to cover all three states.
#
# The source side WILL have uncommitted edits at this point (this WI is
# the LAST step in Phase 1a before commit); that is expected and not checked.
[ -z "$(git status --porcelain -- .claude/skills/quickfix)" ] || \
  { echo "ERROR: pre-existing uncommitted/untracked state in .claude/skills/quickfix; resolve before mirroring" >&2; exit 1; }
```

Then run the mirror helper:

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
- **Model-layer-triage asymmetry.** Triage is model-layer judgment; the same model performing triage would otherwise PROCEED. False-REDIRECTs (small task wrongly redirected) are recoverable via `--force` in one re-invoke. False-PROCEEDs (over-scoped task wrongly PROCEEDED) are the dangerous direction. The asymmetry is intentional: a false-REDIRECT costs the user one re-invoke; a false-PROCEED can ship over-scoped work. The WI 1.5.4b reviewer is the safety net that catches some false-PROCEEDs — but is itself a model judgment, sharing the same self-grading blind spot. The reviewer's purchase comes from an **observable signal** rather than vibes-based pattern matching: the inline plan MUST list one Acceptance bullet per top-level concept, with ≤4 Acceptance bullets total. If the reviewer sees >4 Acceptance bullets, it MUST auto-REVISE with reason `too many concepts; consider /draft-plan` (regardless of whether the bullets individually look reasonable). This binds the reviewer's safety-net role to a concrete observable rather than a plausibility claim, addressing the "both gates self-grade" concern. Phase 1a's WI 1a.4 inline-plan template already caps Acceptance at 2-4 bullets; the reviewer's >4-bullet auto-REVISE is the enforcement mechanism. Documented in the WI 1.5.4b reviewer prompt (see WI 1a.5).
- **No post-execution diff review for /quickfix (accepted asymmetry vs /do).** /quickfix runs pre-execution plan review only; /do runs pre-execution plan review (this plan) AND post-execution `/verify-changes` for non-PR push (existing behavior). Why /quickfix omits the post-execution diff check: /quickfix's contract is a single-commit PR opened against `main`; PR review (human or `/review`) is the post-execution diff check, and the GitHub PR UI is the natural review surface. Adding `/verify-changes`-style auto-review would conflict with /quickfix's fire-and-forget intent and duplicate work the human reviewer (or `/review` on the PR) is going to do anyway. /do's larger scope, optional non-PR landing modes, and absence of a guaranteed PR review surface justify the additional `/verify-changes` pass. The asymmetry is acknowledged and intentional, not an oversight: pre-execution plan reviewer is judgmentally weaker than post-execution diff review, but for /quickfix's small-task scope and PR-only landing, the cost-benefit favors fire-and-forget. If a future user pattern shows /quickfix systematically shipping over-scoped work that the PR reviewer catches downstream, revisit by adding an optional `--review-after` flag — not by making post-review the default.
- **Test-stub naming convention vs `/draft-tests` AC-4.5.** `/draft-tests` (landed PRs #124–#140) uses unprefixed `ZSKILLS_TEST_LLM=1` (gate) + file-path `ZSKILLS_DRAFT_TESTS_REVIEWER_STUB_<N>` (per-round stubs). This plan uses `_ZSKILLS_TEST_HARNESS=1` (companion gate) + single-value `_ZSKILLS_TEST_TRIAGE_VERDICT` / `_ZSKILLS_TEST_REVIEW_VERDICT` (single-shot env-value-not-file). The divergence is intentional: (a) /quickfix's verdicts are small enums, not multi-line stub corpora — file-path stubs would be over-engineering; (b) the leading-underscore-private prefix (`_ZSKILLS_TEST_*`) is a **convention to prevent accidental env-var inheritance from forwarding test stubs into production invocation**, NOT a security boundary. The unset guard (WI 1a.3a) enforces this convention by clearing the test vars at entry when the harness flag is absent — so a test stub left in the parent shell can't leak into a fresh production `/quickfix` run. An adversary who can modify SKILL.md itself can defeat the guard by removing it; this is acknowledged and outside the threat model. The framing here is "hygiene against ambient leakage," not "hardened security control." Follow-up: cross-skill stub naming reconciliation may be tackled in a separate plan once both patterns have shipped and we observe which cross-cuts emerge.

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
- `grep -q 'OBSERVABLE-SIGNAL RULE' skills/quickfix/SKILL.md` returns 0 (reviewer-prompt observable-signal rule prose present per WI 1a.5 / DA10 closure).
- `grep -q 'too many concepts; consider /draft-plan' skills/quickfix/SKILL.md` returns 0 (auto-REVISE reason string from the OBSERVABLE-SIGNAL rule present so the rule cannot be silently weakened).
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

**Existing case count is 42, not 43.** Verified: `grep -c '^# Case [0-9]' tests/test-quickfix.sh` returns 42 at refine time. The skill's pre-existing case numbering has a gap (Case 17 is missing — the file was renumbered at some point and the gap was preserved). Plan numbering picks up at the highest existing case number + 1 to preserve the existing convention; new cases are 44-53. The Acceptance Criterion below is stated as **"42 + 10 = 52 cases"** with the case-numbering RANGE 1-53; if the pre-existing gap is closed by an unrelated future commit, the AC's "52 cases" count still holds (10 new cases regardless of whether existing count is 42 or 43) — the Acceptance counts cases, not numbers. The implementer should NOT renumber existing cases; the gap is pre-existing artifact and is left as-is.

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
- **Case 50**: **Phase-1.5-block-position assertion.** Phase 1a ACs (`grep -q '^### WI 1\.5\.4(a|b)? — '` series) already enforce heading PRESENCE. To avoid duplicate-presence grepping (Phase 1a is a hard gate; the headings cannot be absent when 1b runs), Case 50 instead asserts ORDERING and ADJACENCY: extract the line numbers of `^### WI 1\.5\b`, `^### WI 1\.5\.4\b`, `^### WI 1\.5\.4a\b`, `^### WI 1\.5\.4b\b`, `^### WI 1\.5\.5\b` from `skills/quickfix/SKILL.md` and assert they are strictly ascending in that order (1.5 < 1.5.4 < 1.5.4a < 1.5.4b < 1.5.5). This catches a regression where a future edit moves a heading without removing it (presence-grep would still pass; ordering breaks).
- **Case 51**: redirect-message exact-text guard. For each of the 3 redirect targets, grep that BOTH line 1 and line 2 are present in the skill source as separate physical lines:
  ```bash
  grep -q 'Triage: redirecting to /draft-plan' skills/quickfix/SKILL.md && \
    grep -q 'This task spans more than one concept' skills/quickfix/SKILL.md
  ```
  (Repeat for /run-plan + "references an existing plan file"; /fix-issues + "references a GitHub issue".)

  **Strengthened structural assertion (replaces the weak `! grep -F 'Reason: <reason>\nThis task'`).** The original `! grep -F` test caught only a literal-backslash-n regression — a narrow failure mode that adds little signal. Replace with: extract the redirect-message markdown table (the `| target | Line 1 | Line 2 |` block in WI 1.5.4) via AWK, then for EACH of the 4 documented targets (`/draft-plan`, `/run-plan`, `/fix-issues`, `ask-user`), assert (a) the row exists, (b) the Line 2 column starts with the documented opener:
    - `/draft-plan` Line 2 starts with `This task spans more than one concept`
    - `/run-plan` Line 2 starts with `This task references an existing plan file`
    - `/fix-issues` Line 2 starts with `This task references a GitHub issue`
    - `ask-user` Line 2 starts with `Re-invoke /quickfix with a concrete description`

  Also assert the table has exactly 4 data rows (excluding header + separator). This catches structural regressions (missing target, swapped columns, dropped opener) — broader and more meaningful than the literal-`\n`-as-text regression.
- **Case 52**: VERDICT regex with REQUIRED separator + reason for REVISE/REJECT, BARE for APPROVE. Cases:
  - `VERDICT: APPROVE` → match
  - `VERDICT: APPROVE because plan is fine` → NO match (free text after APPROVE on line 1 is rejected)
  - `VERDICT: REVISE -- one-line reason` → match
  - `VERDICT: REVISE` → NO match (missing separator + reason)
  - `VERDICT: REJECT -- contract violation` → match

  **Mechanism:** extract the two regex patterns from `skills/quickfix/SKILL.md`'s WI 1.5.4b verdict-parser **`regex` fence** (NOT `bash` — see DA1 / WI 1a.5 fence-tag discipline; a `bash` fence here would be extracted by `extract_full_flow` and exec'd as commands). The AWK extractor for THIS case matches `^```regex$` … `^```$`. Run each test input through `[[ "$INPUT" =~ $EXTRACTED_REGEX ]]` against both extracted regexes (bare-APPROVE and REVISE/REJECT) and assert match/no-match per case.

  **Fence-tag co-discipline assertion (NEW).** Also assert that NO `^```bash$` fences appear between `^### WI 1\.5\.4b` and `^### WI 1\.5\.5` whose body contains a literal `^VERDICT:` line — `awk '/^### WI 1\.5\.4b/,/^### WI 1\.5\.5/' skills/quickfix/SKILL.md | awk '/^```bash$/{infence=1;next} infence && /^```$/{infence=0;next} infence' | grep -c '^\^VERDICT:'` returns 0. This catches a regression where the regex block is moved back into a `bash` fence (which would silently break Case 43's stderr cleanliness).
- **Case 53**: `--rounds 0` skip path documented in prose AND stderr WARN present.

### Acceptance Criteria

- `bash tests/test-quickfix.sh` passes 52 cases (42 existing + 10 new). Case numbers are 44-53 for new cases. Pre-existing numbering gaps (e.g. the missing Case 17) are preserved as-is.

### Dependencies

Phase 1a.

---

## Phase 2a — /do: triage gate, inline plan, fresh-agent review (skill source + mirror)

### Goal

Apply pattern to `skills/do/SKILL.md`. Mirror to `.claude/skills/do/`. Tests in Phase 2b.

**Critical phase ordering change vs round 1:** triage and review must run BEFORE cron registration. A redirected /do invocation must leave NO cron behind. The existing Phase 0 today registers a cron, then later phases parse description / run logic; if triage redirected from inside Phase 0, a zombie cron would persist.

**Naming choice (numeric flow preserved).** Rather than naming the new pre-cron stages `Phase 1.6` / `Phase 1.7` (which would read as "1.6 then 1.7 then 0 then 1 then 1.5 then 2" and confuse future readers who assume `1.6 > 1.5`), this plan splits the existing `Phase 0` into three sub-phases that flow numerically: `## Phase 0a — Triage`, `## Phase 0b — Inline plan + fresh-agent review`, `## Phase 0c — Schedule (cron registration)` (the latter is the existing Phase 0 body, renamed). Reading order is `0a → 0b → 0c → 1 → 1.5 → 2 → ...`, matching ordinary plan-numbering convention. ACs that key on heading text are updated accordingly.

### Work Items

**WI 2a.0 — Pre-flight flag pre-parse (NEW step inserted BEFORE Phase 0a triage).**

Phase 0a (triage) and Phase 0b (review) need to know `--force` and `--rounds N`; Phase 0c (cron registration) needs them so the cron prompt template can include them verbatim. Phase 1.5's argument parser runs AFTER Phase 0c today, so we add a small pre-parse step that runs first — at the very top of the skill, before Phase 0a. This pre-parse is non-destructive: it sets `FORCE` and `ROUNDS` shell variables but does NOT mutate `$ARGUMENTS` (Phase 1.5's parser remains source of truth for the canonical strip).

```bash
# Pre-flight (runs before Phase 0a/0b/0c): read --force and --rounds N out
# of $ARGUMENTS so Phase 0c's cron prompt template can include them, and
# Phase 0a/0b can branch on them. Does not mutate $ARGUMENTS.

# Entry-point unset guard (WI 2a.3 test seam) — keep first so any code path
# that later reads _ZSKILLS_TEST_* env vars (triage, review, cron-prompt
# construction) sees the production-cleared values when the harness flag
# is absent. Symmetric to /quickfix WI 1a.3a.
if [ "${_ZSKILLS_TEST_HARNESS:-}" != "1" ]; then
  unset _ZSKILLS_TEST_TRIAGE_VERDICT _ZSKILLS_TEST_REVIEW_VERDICT
fi

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

**WI 2a.1 — Triage gate (new `## Phase 0a — Triage`, inserted BEFORE current Phase 0).**

Rename the current `## Phase 0 — Schedule` heading to `## Phase 0c — Schedule` (cron registration body unchanged). Insert new section `## Phase 0a — Triage` IMMEDIATELY AFTER the meta-command block (anchor by content: after the `## Meta-Commands: stop / next / now` section ends and before the renamed Phase 0c). Same shape and rubric as /quickfix WI 1.5.4 (qualitative signals only). For /do, the rubric does not have a user-edited mode arm — /do always works in a fresh worktree (PR mode) or main (direct mode), so the "≥3 distinct files in description" rule applies uniformly (no MODE carve-out needed).

Reuses the four redirect message templates verbatim (substitute `/quickfix` → `/do` in the redirect messages and override hint). Two-line printed messages, no literal `\n`. On REDIRECT (no force): print message, exit 0. /do does NOT write a tracking marker (per "no new tracking for /do") — nothing to clean up. On REDIRECT (force): override, continue.

**WI 2a.2 — Cron-zombie regression guard.**

Document explicitly in Phase 0a: "Phase 0a (triage) runs BEFORE Phase 0c (cron registration). A REDIRECT path exits before any `CronCreate` call, so a redirected /do leaves no cron behind. Phase 0c cannot run on a redirected invocation."

**WI 2a.3 — Fresh-agent review (new `## Phase 0b — Inline plan + fresh-agent review`).**

After Phase 0a, insert `## Phase 0b — Inline plan + fresh-agent review` — also BEFORE Phase 0c. If `$ROUNDS -eq 0`: stderr `WARN: --rounds 0 skips fresh-agent plan review (legacy opt-in).`. Skip.

Otherwise compose `INLINE_PLAN` (same shape as /quickfix; **"Files (expected)" is OPTIONAL** for /do — worktree may not exist yet for PR mode; agent will discover files in Phase 1 research; when unsure, set to `as inferred from description; may be refined during Phase 1 research`). Dispatch ONE Agent with same prompt template (no dirty-diff section). Parse VERDICT with the SAME separator-required regex (APPROVE bare; REVISE/REJECT require ASCII `--` + reason). Loop up to `$ROUNDS` using the same REVISE iteration prompt template. On REJECT (no force): print verdict, exit 0 (no worktree, no commits, no cron).

**Test seam:** `_ZSKILLS_TEST_HARNESS=1` + `_ZSKILLS_TEST_REVIEW_VERDICT` / `_ZSKILLS_TEST_TRIAGE_VERDICT`. The entry-point unset guard is already inline in WI 2a.0's pre-flight bash fence (immediately before the `FORCE=0` initialization, so it precedes any code path that reads `_ZSKILLS_TEST_*` env vars — triage, review, or cron-prompt construction). Symmetric to /quickfix WI 1a.3a's anchor at the top of WI 1.2's parser. WI 2a.3 does NOT need to insert it separately — the guard ships as part of WI 2a.0's fence to avoid a cross-WI splice hazard.

Orthogonality with /verify-changes (Phase 3) explicitly documented at the **closing paragraph of Phase 0b's prose body** in `skills/do/SKILL.md`:

> "Orthogonality with `/verify-changes` (Phase 3): pre-review (this phase) judges PLAN; `/verify-changes` judges DIFF. Both run when both apply: `--rounds > 0` triggers this pre-review (any landing mode); the `push` flag with code changes (`worktree`/`direct` mode only — see Phase 3) triggers /verify-changes after execution. PR mode (Path A) handles its own push internally and does **not** invoke /verify-changes (per `skills/do/SKILL.md` Phase 4 'Not applicable to PR mode' note)."

Phase 2b Case 10 asserts presence of this prose in `skills/do/SKILL.md`'s Phase 0b section: grep `pre-review judges PLAN` AND grep `! pr mode.*verify-changes` (the latter ensuring the negation prose stays — guards against a future edit that mis-claims PR mode triggers /verify-changes).

**WI 2a.4 — Add `--force` and `--rounds N` to Phase 1.5 (canonical parser).**

After Step 3 (`push` flag detection), document that `FORCE` and `ROUNDS` are already set by WI 2a.0's pre-parse, but re-validate idempotently in case Phase 1.5 is invoked outside the normal entry path (defensive). The regex MUST match WI 2a.0 exactly: numeric-only `[0-9]+` capture with greedy-fallthrough on non-numeric (no exit-2 branch — that would contradict WI 2a.0's contract that `/do fix the bug --rounds in production` is a legitimate description).

```bash
# Re-affirm (already set by pre-flight pre-parse; idempotent).
# Regex is numeric-only — symmetric with WI 2a.0. Non-numeric trailing
# tokens after `--rounds` are user prose (greedy-fallthrough) and DO NOT
# raise exit 2 — that would re-introduce the closed greedy bug.
FORCE=${FORCE:-0}
if [[ "$REMAINING" =~ (^|[[:space:]])--force($|[[:space:]]) ]]; then
  FORCE=1
fi
ROUNDS=${ROUNDS:-1}
if [[ "$REMAINING" =~ (^|[[:space:]])--rounds[[:space:]]+([0-9]+)($|[[:space:]]) ]]; then
  ROUNDS="${BASH_REMATCH[2]}"
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

**WI 2a.6 — Document `--force` cron persistence in Phase 0c (cron-prompt construction algorithm).**

Add note in Phase 0c: "**Persistence of `--force` and `--rounds N`:** these flags are preserved verbatim in the cron prompt. A `/do <task> --force every 4h` produces a cron prompt of `Run /do <task> --force every 4h now`, so every cron fire bypasses triage and review. Intentional: setting `--force` on a recurring task means the user wants the bypass on every fire."

**Cron-prompt construction algorithm (explicit bash).** Anchor by content (locate via `grep -n 'Run /do' skills/do/SKILL.md` — the existing cron-prompt template line; pre-edit it was around L205-207, but Phase 2a's heading restructure shifts line numbers). Replace the existing cron-prompt template with:

```bash
# Construct cron prompt incrementally so optional flags only appear when set.
# FORCE and ROUNDS are pre-parsed in WI 2a.0; SCHEDULE is parsed earlier in Phase 0c.
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

**TASK_DESCRIPTION_FOR_CRON construction (explicit bash, lives in Phase 0c before the cron-prompt build).**

```bash
# Strip every/now/--force/--rounds tokens from $ARGUMENTS but PRESERVE
# pr/worktree/direct/push tokens (these need to round-trip into the cron
# prompt so each cron fire reproduces the user's landing-mode intent).
#
# Quoted-description carve-out: /do supports a leading quoted description
# (skills/do/SKILL.md:71-73). When $ARGUMENTS begins with `"..."`, peel
# the quoted segment off, strip-chain only the unquoted suffix, then
# reassemble. This prevents `/do "fix --force usage in scripts" --force
# every 4h` from corrupting the user-prose `--force` substring inside
# the quotes.
if [[ "$ARGUMENTS" =~ ^([[:space:]]*\"[^\"]*\")[[:space:]]*(.*)$ ]]; then
  QUOTED_HEAD="${BASH_REMATCH[1]}"
  REST="${BASH_REMATCH[2]}"
else
  QUOTED_HEAD=""
  REST="$ARGUMENTS"
fi
STRIPPED_REST=$(echo "$REST" \
  | sed -E 's/(^|[[:space:]])every[[:space:]]+(day|weekday)[[:space:]]+at[[:space:]]+[^[:space:]]+($|[[:space:]])/ /' \
  | sed -E 's/(^|[[:space:]])every[[:space:]]+[^[:space:]]+($|[[:space:]])/ /' \
  | sed -E 's/(^|[[:space:]])now($|[[:space:]])/ /' \
  | sed -E 's/(^|[[:space:]])--force($|[[:space:]])/ /' \
  | sed -E 's/(^|[[:space:]])--rounds[[:space:]]+[0-9]+($|[[:space:]])/ /' \
  | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')
if [ -n "$QUOTED_HEAD" ] && [ -n "$STRIPPED_REST" ]; then
  TASK_DESCRIPTION_FOR_CRON="$QUOTED_HEAD $STRIPPED_REST"
elif [ -n "$QUOTED_HEAD" ]; then
  TASK_DESCRIPTION_FOR_CRON="$QUOTED_HEAD"
else
  TASK_DESCRIPTION_FOR_CRON="$STRIPPED_REST"
fi
```

Note the time-of-day pattern (`every day at 9am`) MUST come before the
generic interval pattern (`every 4h`) — generic would otherwise capture
"day" as the interval value and leave "at 9am" as orphan tokens. The
`--rounds` strip only matches numeric N (consistent with WI 2a.0's
greedy-fallthrough rule); a non-numeric `--rounds <prose>` stays in
`TASK_DESCRIPTION_FOR_CRON` and round-trips into the cron prompt as user
prose, where it will again no-op-fall-through on each fire.

**Quoted-description known limit.** A quoted description containing a
literal `every <token>` substring (e.g., `/do "audit every PR" every
4h`) is also protected — only the unquoted suffix is strip-chained. A
multi-segment quoted form (`/do "fix" --force "every 4h"`) is not
supported; the regex matches only the leading quote pair. Phase 2b
Case 12 (NEW) asserts the protected case; multi-segment is documented
unsupported.

**WI 2a.7 — Document meta-command bypass.**

Anchor by content, NOT by line number (L80 is unstable post-WI-2a.1 insertion). Locate the existing meta-command bullet block — three lines starting with `- `stop [query]``, `- `next [query]``, `- `now [query]`` (currently L76-78 in pre-edit /do/SKILL.md). Insert the bypass note as a new paragraph immediately AFTER that bullet block and BEFORE the `If the first word is NOT a meta-command,` sentence:

> "Meta-commands (`stop`, `next`, `now`) bypass Phase 0a triage and Phase 0b review entirely. They are administrative — there is no description to evaluate."

Acceptance: `grep -B1 'bypass Phase 0a triage and Phase 0b review' skills/do/SKILL.md` — the line immediately above the bypass note must be one of the meta-command bullets (`- \`now [query]\`` or similar) or an empty line separating that block. If `grep -B1` returns content from the trailing-flag parsing block, the anchor was applied at the wrong location.

**WI 2a.8 — Mirror `skills/do/` to `.claude/skills/do/` byte-identically via the canonical helper.**

**Pre-mirror state check** (symmetric to WI 1a.8 — uses `git status --porcelain`, not `git diff --quiet`, to also catch untracked files that the helper's orphan-removal step would silently delete):

```bash
[ -z "$(git status --porcelain -- .claude/skills/do)" ] || \
  { echo "ERROR: pre-existing uncommitted/untracked state in .claude/skills/do; resolve before mirroring" >&2; exit 1; }
```

Then run the mirror helper:

```bash
bash scripts/mirror-skill.sh do
```

Verify: `diff -rq skills/do .claude/skills/do` → no output, rc=0.

(Same hook-compatibility rationale as WI 1a.8 — `rm -rf .claude/skills/do` is blocked by `hooks/block-unsafe-generic.sh:218-221`. Use the helper.)

### Design & Constraints

- No new tracking for /do.
- Triage (Phase 0a) runs BEFORE cron registration (Phase 0c) (no zombie crons on REDIRECT).
- `--force` persistence in cron is intentional and documented.
- Meta-commands bypass everything.
- No jq.
- /verify-changes orthogonality preserved; PR mode (Path A) explicitly does NOT invoke /verify-changes (per R3 — the existing Phase 4 'Not applicable to PR mode' note governs).
- CANARY11 (post-execution scope detection) continues to work.
- CANARY_DO_WORKTREE_BASE happy path (the only canary that invokes `/do` directly) is a known-PROCEED case (listed in the rubric worked-examples table) and must NOT be redirected by triage. Manual verification after Phase 2a lands.

### Acceptance Criteria

- `grep -q 'argument-hint: ".*--force.*--rounds N' skills/do/SKILL.md` → 0.
- `grep -q '^## Phase 0a — Triage' skills/do/SKILL.md` → 0.
- `grep -q '^## Phase 0b — Inline plan' skills/do/SKILL.md` → 0.
- `grep -q '^## Phase 0c — Schedule' skills/do/SKILL.md` → 0 (current Phase 0 renamed).
- `! grep -q '^## Phase 0 — Schedule' skills/do/SKILL.md` (old heading removed).
- Phase 0a heading appears BEFORE Phase 0b which appears BEFORE Phase 0c in the file (verify by extracting `grep -nE '^## Phase 0[abc]' skills/do/SKILL.md` and asserting line numbers ascend).
- `grep -q 'preserved verbatim in the cron prompt' skills/do/SKILL.md` → 0.
- `grep -q 'bypass Phase 0a triage and Phase 0b review' skills/do/SKILL.md` → 0.
- `grep -q 'WARN: --rounds 0 skips' skills/do/SKILL.md` → 0.
- `grep -q '_ZSKILLS_TEST_HARNESS' skills/do/SKILL.md` → 0.
- `grep -q 'OBSERVABLE-SIGNAL RULE' skills/do/SKILL.md` → 0 (reviewer-prompt observable-signal rule prose present; symmetric to /quickfix per WI 2a.3 "same prompt template").
- `grep -q 'too many concepts; consider /draft-plan' skills/do/SKILL.md` → 0 (auto-REVISE reason string present so the rule cannot be silently weakened).
- `grep -q 'pre-review judges PLAN' skills/do/SKILL.md` → 0 (orthogonality prose present).
- `grep -q 'PR mode (Path A) handles its own push internally and does \*\*not\*\* invoke /verify-changes' skills/do/SKILL.md` → 0 (PR-mode negation prose present per R3).
- `diff -rq skills/do .claude/skills/do` → no output, rc=0.
- All existing test suites still pass.

### Dependencies

Phase 1a.

---

## Phase 2b — /do: create test suite, wire into runner

### Goal

Create `tests/test-do.sh` with 13 cases. Wire into `tests/run-all.sh`.

### Work Items

**WI 2b.1 — Create `tests/test-do.sh` with cases:**

1. argument-hint contains `--force` and `--rounds N`.
2. Phase 0a triage prose present (heading + rubric-table) AND Phase 0a heading line number is < Phase 0c heading line number (cron-zombie regression guard: triage MUST come before cron registration). Verify via: `grep -nE '^## Phase 0[ac]' skills/do/SKILL.md` returns Phase 0a's line number first, ascending.
3. Phase 0b inline-plan + review prose present.
4. `--force` cron-persistence prose present.
5. Meta-command bypass documented (and anchored after meta-command bullet block, NOT in trailing-flag parsing region — assert `grep -B1 'bypass Phase 0a triage and Phase 0b review'` returns one of the meta-command bullet lines or an empty separator).
6. VERDICT parser regex documented: APPROVE bare; REVISE/REJECT require `--` + reason.
7. `--rounds 0` skip-review prose present AND stderr WARN string present.
8. `--force` and `--rounds N` flags stripped from TASK_DESCRIPTION (bash plumbing). **Extraction window pinned:** extract Phase 1.5 Step 2's complete `TASK_DESCRIPTION=$(echo "$REMAINING" \ ...)` block (the chain that includes pr/worktree/direct strips PLUS the new `--force`/`--rounds [0-9]+` strips from WI 2a.4) — NOT just WI 2a.4's two added lines in isolation, which would leave the input `pr` token un-stripped. Use AWK fence start/end matching to capture the complete block, then run input `fix tooltip --force --rounds 3 pr` and assert output `fix tooltip`.
9. `--rounds notanumber` to /do leaves ROUNDS at default 1 (greedy-fallthrough per WI 2a.0; documents the user-prose-containing-`--rounds` case). Symmetric to /quickfix Case 45. Extract pre-flight pre-parse + run against fixture, assert `ROUNDS == 1`.
10. Phase 0b documents orthogonality with /verify-changes (positive grep `pre-review judges PLAN`) AND PR-mode negation prose present (positive grep on `PR mode (Path A) handles its own push internally and does \*\*not\*\* invoke /verify-changes`). Closes R3.
11. Entry-point unset guard regression: invoking /do with `_ZSKILLS_TEST_TRIAGE_VERDICT` (or `_ZSKILLS_TEST_REVIEW_VERDICT`) set in the environment but WITHOUT `_ZSKILLS_TEST_HARNESS=1` proceeds normally — the env var is unset by the entry-point guard and ignored. Symmetric to /quickfix Case 47(e). Closes the round-2 follow-up flagged in known-concerns: the harness-companion test was previously only covered for /quickfix.
12. **Phase 1.5 re-validation does NOT exit 2 on non-numeric `--rounds`** (closes R2). Extract WI 2a.4's defensive re-validation block, run with input `fix the bug --rounds in production`, assert exit code is NOT 2 AND ROUNDS stays at default 1 AND no `ERROR:` text on stderr. Symmetric guarantee to WI 2a.0.
13. **Quoted-description protection (closes DA3).** Run TASK_DESCRIPTION_FOR_CRON construction (extract block from WI 2a.6) with input `"fix --force usage in scripts" --force every 4h`. Assert output equals `"fix --force usage in scripts"` — the quoted-segment `--force` substring is preserved; the trailing flag `--force` is stripped.

Mirror house style of `tests/test-quickfix.sh`: `make_fixture`, per-case fixture, capture stderr, `pass`/`fail`, cleanup trap.

**WI 2b.2 — Wire into `tests/run-all.sh`.**

Append after the `run_suite "test-quickfix.sh" …` line:
```bash
run_suite "test-do.sh" "tests/test-do.sh"
```

Verify by running `bash tests/run-all.sh` from clean tree.

### Acceptance Criteria

- `bash tests/test-do.sh` passes all 13 cases.
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
| Round-1-carryover known concern #1 (entry-point unset guard test only in /quickfix) | Plan deferred the analogous /do test | Same anti-defer rule applies. | **Refined**: Phase 2b adds Case 11 (entry-point unset guard for /do), Case 12 (Phase-1.5 re-validation does NOT exit 2 on non-numeric `--rounds`), Case 13 (quoted-description protection in `TASK_DESCRIPTION_FOR_CRON` strip). Total /do cases: 13 (was 10). |

**Note on completed-vs-planned drift:** `/refine-plan` SKILL.md edge case applies — "No completed phases — all phases reviewed as remaining." No phase sections were modified except via the targeted edits above.

## Plan Review

**Refinement process:** /refine-plan with 2 rounds of adversarial review (orchestrator-acted reviewer + devil's advocate per round, due to the absence of a Task/Agent dispatch primitive in this runtime; verify-before-fix discipline applied empirically with file/grep/hook re-runs). The /refine-plan SKILL.md verbatim-prompt for these reviewer roles was followed; findings include a `Verification:` line per finding and were re-run before fixes.
**Convergence:** Converged at round 2 — orchestrator's mechanical check on the disposition table (`feedback_convergence_orchestrator_judgment.md`). Substantive open issues at round 2 close: 0 net. Round 1 disposition arithmetic: **17 fixed + 3 justified-not-fixed + 2 confirmed-no-action = 22 total dispositions; 0 unresolved.** Round 2 disposition arithmetic: **10 fixed + 0 justified-not-fixed + 0 confirmed-no-action = 10 total dispositions; 0 unresolved.** Combined: 22 + 10 = 32 unique substantive findings dispositioned across 2 rounds.

### Round History

| Round | Reviewer Findings | DA Findings | Substantive (after dedup) | Verified | Fixed | Justified | Confirmed-no-action |
|-------|-------------------|-------------|---------------------------|----------|-------|-----------|---------------------|
| 1     | 13 (R1–R13) | 11 (DA1–DA11) + 1 added during refine pass (DA12) — total 12 | 22 (after dedup; R8/DA7/DA11 originally classified as confirmations were reclassified substantive on re-audit per R2-7) | 22 | 17 | 3 | 2 (R10 effort-note soft hedge, R12 Case-17 numbering soft hedge) |
| 2     | 8 (R2-1 through R2-8) | 5 (DA2-1 through DA2-5) | 10 (after dedup; R2-1=DA2-1, R2-4=DA2-4, R2-5=DA2-5) | 10 | 10 | 0 | 0 |

**Round 1 fixes applied (17 total — list count is authoritative; prior header inconsistencies of 11 and 13 were arithmetic errors and are reconciled here):**
1. **WI 1a.1** — `--rounds` greedy-fallthrough (closes DA3 hole; Phase 1b Case 45 updated to match).
2. **WI 1a.6.5** — already in place from prior /draft-plan rounds; left as-is.
3. **WI 1a.6.7 (new)** — refresh stale `block-unsafe-project.sh.template:188-229` citation to `:412-427`. AC criteria added.
4. **WI 1a.8** — replace hook-blocked `rm -rf .claude/skills/quickfix && cp -r ...` with `bash scripts/mirror-skill.sh quickfix`. Hook-block rationale documented inline.
5. **WI 2a.0** — apply greedy-fallthrough to /do (`[0-9]+` regex anchor; non-numeric falls through to user prose).
6. **WI 2a.3** — pin orthogonality-with-/verify-changes prose to Phase 0b's closing paragraph.
7. **WI 2a.6** — explicit `TASK_DESCRIPTION_FOR_CRON` strip-chain bash; ordering note (time-of-day before generic interval).
8. **WI 2a.8** — same mirror-script fix as WI 1a.8 (for /do).
9. **WI 3.1** — anchor by content (`grep -n '/quickfix Fix README typo'`) instead of stale L155-156.
10. **WI 3.3** — `gh issue create` error handling + post-merge link form. AC accepts `<file-and-link-manually>` placeholder.
11. **Phase 1a Design & Constraints** — three new bullets: forbidden-literals discipline, /draft-tests-not-a-redirect rationale, model-layer-triage asymmetry, stub-naming-divergence-justified.
12. **Phase 1b Case 45** — test fallthrough behavior (was: test exit 2; now: test ROUNDS=1 + DESCRIPTION-contains-`--rounds notanumber`).
13. **Phase 1b Case 52** — explicit AWK-extraction mechanism for verdict-regex testing (matches existing test-quickfix.sh idiom).
14. **Phase 2b Case 9** — symmetric fallthrough test for /do.
15. **Phase 2b Case 11 (new)** — entry-point unset guard test for /do (closes round-1-carryover known-concern #1).
16. **Phase 1a effort note** — corrected "~250 lines / ~6 ACs" to "~250-300 lines / 18 grep ACs" (R4/R6/R10/DA5 numeric arithmetic; the actual grep-AC count was 18, not 13 as the prior round wrote).
17. **Phase 1b Goal** — corrected "43 + 10 = 53" to "42 + 10 = 52 with Case 17 gap preserved" (DA12 numeric arithmetic).

**Round 1 justified-not-fixed (3 total):**
- **DA1 (stub naming divergence from /draft-tests AC-4.5)** — divergence is intentional; documented explicitly in Phase 1a Design & Constraints with rationale. Cross-skill reconciliation deferred to a separate plan once both patterns ship and cross-cuts emerge.
- **DA2 (cron-prompt omits `--rounds 1` when value equals default)** — known minor edge case. Justification: cron is **session-scoped** (per `skills/do/SKILL.md:64` — "Cron is session-scoped — dies when the session dies"); a default-rounds change landed in a future session would land in a session where prior crons have already died and been re-registered. The omission cannot cause stale-default round-trip. (Earlier prose claimed "cron lifetime ≤7 days per CronCreate runtime" — that was unsupported and removed; no source documents a 7-day cron lifetime, and the actual primitive is session-scoped, which is a strictly stronger guarantee for this concern.)
- **DA6 (model-layer triage asymmetry)** — inherent to model-layer judgment, not a plan defect. Documented in Design & Constraints with mitigation note (reviewer agent at WI 1.5.4b is the safety net for false-PROCEEDs; `--force` recovers false-REDIRECTs).

**Round 1 confirmed-no-action (2 total — re-mapped per Round 2 R2-7):**
- **R10** — Phase 1a effort note "~265 lines added" is judgment-class soft hedge, not a measurable AC. Acknowledged in prose ("planning estimate, not an acceptance criterion") with no AC added; the catastrophic-under-implementation guard suggested in R10's recommendation was deemed unnecessary at this scope.
- **R12** — Phase 1b "Case 17 numbering gap" claim depends on a fragile pre-existing artifact. Softened in Phase 1b Goal prose to "Pre-existing numbering gaps (e.g. the missing Case 17) are preserved as-is" / "the Acceptance counts cases, not numbers"; no further mechanical enforcement added.

(The earlier text listed **R8 / DA7 / DA11** as confirmed-no-action — those entries were inherited from a prior single-agent run and were materially wrong. R8 was substantive (off-by-one count, fixed via reconciliation), DA7 was Case 50 redundancy (fixed by repurposing the case to ordering/adjacency), and DA11 was the security-theater framing (fixed by softening WI 1a.3a + Design & Constraints prose). Re-mapped here per R2-7.)

**Round 2 fixes applied (10 total):**
1. **L868** — stale `Phase 1.7` reference in fix-list item 6 → `Phase 0b` (R2-1 / DA2-1).
2. **L911 / L853** — convergence arithmetic reconciled to round-1 actuals: was `13 fix + 3 justify + 3 confirm = 19`; now `17 fix + 3 justify + 2 confirm = 22` (with the confirm count re-mapped per R2-7) (R2-3).
3. **Phase 1a + Phase 2a Acceptance Criteria** — added two grep ACs each to assert the OBSERVABLE-SIGNAL rule (`OBSERVABLE-SIGNAL RULE` heading + `too many concepts; consider /draft-plan` reason string) so the rule cannot be silently weakened. Phase 1a effort-note grep-AC count updated 18 → 20 (R2-4 / DA2-4).
4. **Phase 1b Case 50** — replaced stale plan-line citation `L323-325` with content anchor (`grep -q '^### WI 1\.5\.4(a|b)? — '` series); ordering/adjacency assertion is unchanged (R2-5 / DA2-5).
5. **Drift Log /do test-suite case count** — corrected `Total /do cases: 11 (was 10)` to `Total /do cases: 13 (was 10)` and enumerated Cases 11/12/13 (R2-6).
6. **Plan Review confirmed-no-action items** — re-mapped from inherited-but-incorrect R8/DA7/DA11 (which were substantive and fixed) to R10 + R12 (genuine soft-hedge candidates); count 3 → 2 (R2-7).
7. **Round History row 1 enumeration** — was `7 (R1, R2, R3, R4, R5, R6, R7) + 1 confirmation (R8)`, now `13 (R1–R13)`; column header softened to `Substantive (after dedup)`; row narrative explains the R8/DA7/DA11 reclassification (R2-8).
8. **WI 1a.8 + WI 2a.8 mirror pre-check** — replaced `git diff --quiet` with `git status --porcelain` so the check also detects untracked files that the helper's orphan-removal step would silently delete (DA2-2).
9. **WI 2a.0 / WI 2a.3 unset-guard inlining** — moved the `_ZSKILLS_TEST_*` unset guard inline into WI 2a.0's pre-flight bash fence (immediately before `FORCE=0`), eliminating the cross-WI splice hazard where WI 2a.3 directed the implementer to amend WI 2a.0's already-finalized fence (DA2-3).
10. **Convergence statement** — rewrote `Convergence` paragraph to surface combined round-1 + round-2 disposition arithmetic (`22 + 10 = 32 unique substantive findings dispositioned`), replacing the prior single-round narrative.

### Top 3 highest-blast-radius findings (Round 1)

1. **R1 — Mirror command hook-blocked (WI 1a.8 / WI 2a.8).** Implementing agent literally cannot execute the plan as originally written; the `rm -rf .claude/skills/X` form fires `hooks/block-unsafe-generic.sh:218-221`. Empirically observed during this orchestrator's investigation (a separate `bash` invocation triggered the same hook). **Fixed**: replaced with `bash scripts/mirror-skill.sh <skill>` (canonical helper introduced in PR #88).
2. **R2 — CLAUDE_TEMPLATE.md anchor 44 lines stale (WI 3.1).** Plan referenced L155-156, actual location is L199-200 due to DEFAULT_PORT_CONFIG and SKILL_FILE_DRIFT_FIX landings. Implementer would have edited unrelated prose. **Fixed**: re-anchored by content.
3. **DA3 — `/quickfix --rounds` greedy parser deferred (round-1 known-concern #4).** Plan punted the resolution of a concrete bug ("`/quickfix fix --rounds in docs` exits 2") into a "future round". This is exactly the anti-pattern in `feedback_dont_defer_hole_closure.md`. **Fixed**: WI 1a.1 and WI 2a.0 implement option (b) — regex-fail-fallthrough — and the Phase 1b/2b tests assert the new contract.

### Anti-pattern self-check

- **Convergence judgment:** the orchestrator (this skill body) determined convergence by mechanical count of the disposition table (Round 1: 17 fix + 3 justify + 2 confirm = 22 dispositions; Round 2: 10 fix + 0 justify + 0 confirm = 10 dispositions; combined 32 across 2 rounds, 0 unresolved). No "CONVERGED" prose was accepted from any agent. Per `feedback_convergence_orchestrator_judgment.md`.
- **Verify-before-fix discipline:** every empirical claim was re-checked by the orchestrator (file reads, grep counts, line numbers, hook fire). `/tmp/refine-plan-parsed-QUICKFIX_DO_TRIAGE_PLAN.md` lists the empirical checks. The hook-fire on `rm -rf .claude/skills/...` was a real fire during pre-check, not a hypothetical.
- **No completed-phase modifications:** no phase had `Done` status; the immutability check is vacuous (no checksums to compare against). The Drift Log `Note on completed-vs-planned drift` documents this.

**Execute with:** `/run-plan plans/QUICKFIX_DO_TRIAGE_PLAN.md`
