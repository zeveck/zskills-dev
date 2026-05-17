# `auto` and `unattended` tokens — canonical semantics

This reference is the **single source of truth** for the meanings of
`auto` and `unattended` as positional arguments across the four
PR-landing caller skills (`/quickfix`, `/run-plan`, `/fix-issues`,
`/do`). Every SKILL.md that parses one of these tokens links here
instead of restating the table.

## Rationale

Two concerns historically rode on the single token `auto`:

1. **Auto-merge** — pass `--auto` through to `/land-pr` so the
   resulting GitHub PR has `gh pr merge --auto` enabled.
2. **Human-review-gate skipping** — internal to a skill, run past
   confirmation prompts (scope confirmation, "ready to land?",
   between-phase "continue?", issue-list approval) without
   pausing for the operator.

These two concerns are **orthogonal**: a user may want auto-merge
without skipping skill-internal review (a sprint of small PRs they
still want to scope-confirm one at a time), or skip the gates without
auto-merging (a long unattended run that drops a stack of `pr-ready`
PRs for human merge). Conflating both under `auto` produced surprising
behavior in every skill — see issue #310. This redesign splits them
into two independent tokens.

## Definitions

| Token | Meaning (canonical) | Caller behaviors |
|-------|---------------------|------------------|
| `auto` | Pass `--auto` to `/land-pr` on the resulting PR(s). Nothing else. | **`/quickfix`:** PR opens with auto-merge requested. **`/do` (per #303):** same, in PR mode only (the AUTO_FLAG pre-flight only feeds `modes/pr.md`; worktree/direct modes ignore it). **`/run-plan`:** each per-phase `/land-pr` dispatch passes `--auto`. **`/fix-issues`:** each per-issue `/land-pr` dispatch passes `--auto`. **Note for /run-plan:** the legacy `finish auto` composite (chunked-cron) is preserved as a backward-compatible alias that sets BOTH `AUTO_FLAG=1` AND `UNATTENDED_FLAG=1`. |
| `unattended` | Skip human-review-gate checkpoints inside the skill. | **`/quickfix`:** force the WI 1.5.5a SKIP branch (model bypasses scope confirmation; stderr NOTE emitted for the audit log). **`/do`:** skip the "ready to land?" confirmation between implementer and landing IF such a gate exists; otherwise documented forward-placeholder for the gate Phase 3 introduces. **`/run-plan`:** skip between-phase "continue?" prompts (replaces what `finish auto` used to mean for run-plan chunked execution; cron-fired phases continue automatically). **`/fix-issues`:** skip Phase 2 issue-list approval gate AND per-issue selection gate. |

## Anti-pattern callout

> **`unattended` alone is NOT full autonomy.** `/fix-issues 5
> unattended` skips approval gates but does NOT auto-merge. PRs sit
> at `pr-ready` waiting for manual merge. For fully unattended
> sprints, use `/fix-issues 5 auto unattended`.

## Composition rules

- `auto` and `unattended` are **independent**. Typing one does not
  imply the other. See the anti-pattern above.
- **Order-insensitive:** `/fix-issues 5 auto unattended` is
  equivalent to `/fix-issues 5 unattended auto`.
- **Case-insensitive:** matches the existing `auto` parsing
  (`AUTO`, `Auto`, `auto` all parse identically; same for
  `unattended`).
- **`/run-plan finish auto` composite alias:** parses as
  `FINISH_MODE="finish-auto"` AND `AUTO_FLAG=1` AND
  `UNATTENDED_FLAG=1`. This is the load-bearing
  backward-compatible alias — existing cron-scheduled
  `/run-plan ... finish auto` invocations keep their prior
  semantics (both auto-merge each phase's PR AND skip
  between-phase prompts).

## Explicit non-rules

- `unattended` does **NOT** change the `/fix-issues` for-loop into
  parallel dispatch (PR #309 serial-loop rule — `requires.land-pr.*`
  markers are serial-by-design; parallelizing would deadlock).
- `unattended` does **NOT** bypass the branch-collision check, the
  test-cmd alignment gate, the parallel-invocation gate, or any
  safety guard.
- In `/quickfix`, `unattended` forces the WI 1.5.5a SKIP branch —
  this is **explicit risk acceptance**, not "unattended is harmless."
  The stderr NOTE is the audit trail.

## Migration note

Existing `/fix-issues N auto` invocations that previously triggered
the broad-auto behavior (both auto-merge and gate-skipping) now
trigger **only** auto-merge. Users who want the prior all-in-one
behavior must type: `/fix-issues N auto unattended`.

**Cron migration:** see D5 of `docs/plans/QUICKFIX_GRAMMAR_REDESIGN.md`
for the landing-day `CronList` scan + 3-month runtime promote period.
On landing day, scheduled crons that pass `auto` to any of the four
callers are scanned; the operator is shown the list and prompted to
rewrite each entry (typically appending `unattended` to preserve the
prior behavior). During the 3-month promote period, the four callers
emit a stderr NOTE when invoked with `auto` alone, reminding the
operator that `auto` no longer implies gate-skipping.

## Cross-references

- Memory anchor:
  [`feedback_auto_arg_is_auto_merge.md`](../../home/vscode/.claude/projects/-workspaces-zskills/memory/feedback_auto_arg_is_auto_merge.md)
  — the user's prior decision that typing `auto` to a PR-landing
  caller IS explicit opt-in to auto-merge (not revoked by
  clarifying questions). This redesign preserves that semantics and
  factors out the gate-skipping concern into `unattended`.
- Plan:
  [`docs/plans/QUICKFIX_GRAMMAR_REDESIGN.md`](../docs/plans/QUICKFIX_GRAMMAR_REDESIGN.md)
  — the full design context, decisions D1–D11, and per-phase work
  items. This reference doc is the lock-in artifact for D1–D11
  consumed by Phases 2–6.
