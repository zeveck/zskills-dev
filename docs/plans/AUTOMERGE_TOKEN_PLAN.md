# Plan: `automerge` positional token

**Status**: Implemented  
**Date**: 2026-06-10  
**Addresses**: ZSKILLS_TODO item 1

## Problem

`/run-plan finish auto`, `/fix-issues N auto`, `/do X pr auto`, `/commit pr auto`, and `/draft-tests auto` all pass `--auto` to `/land-pr`, which requests GitHub/GitLab auto-merge. Users want unattended execution (`auto`) but don't always want the PR to land without human review. Currently there's no way to separate these concerns.

## Design

### New token: `automerge`

A positional token (like `auto`) accepted by all skills that currently accept `auto`. It implies `auto` (unattended execution) AND requests auto-merge. The bare `auto` token retains unattended execution but **no longer requests merge**.

This is a **behavior change**: existing `auto` users who relied on auto-merge must switch to `automerge`. This is intentional — the safer default is "create PR but don't merge."

### Resolution (simple, no config)

| User passes | Unattended? | Auto-merge? |
|-------------|-------------|-------------|
| (nothing)   | No          | No          |
| `auto`      | Yes         | No (**changed**) |
| `automerge` | Yes         | Yes         |

No config field. Explicit token, explicit behavior.

### `auto merge` (two words) — treat as `automerge`

If the arg parser sees `auto` followed by `merge` as adjacent positional tokens, treat it as `automerge`. No hint, no warning — the intent is unambiguous. This lives in each caller's arg-parse block.

### /land-pr interface change

`/land-pr` currently accepts `--auto` (bool). Change to:

- `--auto` — unattended mode (CI polling, fix cycles, BEHIND recovery all still run)
- `--automerge` — request auto-merge (implies `--auto` behavior for all gating)

**`pr-merge.sh` interface rename**: Change the `--auto-flag` parameter to `--automerge-flag` (and internal variable to `AUTOMERGE_FLAG`). This eliminates the semantic trap where the parameter name says "auto" but means "merge." Single rename, one file.

The Step 6b BEHIND recovery gates on `AUTO_FLAG` — that stays unchanged (rebasing a BEHIND branch is useful for unattended callers even without merge). Update the comment at SKILL.md line ~432 which incorrectly says "BEHIND recovery is only useful when auto-merge is requested" — after this change, it's useful whenever unattended.

Step 7d (drive queued auto-merge) gates on both `AUTO_FLAG` and `MERGE_REQUESTED` — MERGE_REQUESTED will simply be `false` when `--automerge` wasn't passed, so it self-skips correctly.

## Files to modify

### 1. `/land-pr` (the merge chokepoint)

**`skills/land-pr/SKILL.md`**
- Frontmatter `argument-hint`: add `[--automerge]`
- Arg parse: add `--automerge) AUTOMERGE_FLAG=true ;;`
- Initialize: `AUTOMERGE_FLAG=false`
- Step 7 dispatch to `pr-merge.sh`: pass `--automerge-flag "$AUTOMERGE_FLAG"`
- Description: clarify `--auto` = unattended, `--automerge` = auto-merge
- Update comment at line ~432 re: BEHIND recovery rationale (no longer tied to merge — useful for any unattended caller)

**`skills/land-pr/scripts/pr-merge.sh`**
- Rename `--auto-flag` parameter → `--automerge-flag`
- Rename internal variable `AUTO_FLAG` → `AUTOMERGE_FLAG`
- Gate logic unchanged (still checks the flag for `true`/`false`)

### 2. Caller skills (5 files)

Each currently does: `[ "$AUTO" = "true" ] && LAND_ARGS="$LAND_ARGS --auto"`

Change to:
```bash
[ "$AUTO" = "true" ] && LAND_ARGS="$LAND_ARGS --auto"
[ "$AUTOMERGE" = "true" ] && LAND_ARGS="$LAND_ARGS --automerge"
```

**Files:**
- `skills/run-plan/modes/pr.md` (line ~400) — conditional append
- `skills/fix-issues/modes/pr.md` (line ~138) — conditional append
- `skills/do/modes/pr.md` (line ~478) — conditional append
- `skills/commit/modes/pr.md` (line ~138) — conditional append
- `skills/draft-tests/modes/land.md` (line ~197) — **NOTE**: this file hardcodes `--auto` directly in the LAND_ARGS string literal rather than conditionally appending. Must restructure: remove `--auto` from the string, add conditional appends for both `--auto` and `--automerge` after it (matching the pattern used by the other 4 callers).

### 3. SKILL.md frontmatter (argument-hint + arg parse)

Each skill that accepts `auto` must also accept `automerge`:

- `skills/run-plan/SKILL.md` — hint: `[auto|automerge]`; parse `automerge` token
- `skills/fix-issues/SKILL.md` — same
- `skills/do/SKILL.md` — same
- `skills/commit/SKILL.md` — same
- `skills/draft-tests/SKILL.md` — same

**Important**: The codebase uses **regex matching** (not case statements) for positional tokens:
```bash
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[aA][uU][tT][oO]($|[[:space:]]) ]]; then
  AUTO_FLAG=1
fi
```

Since `automerge` contains `auto` as a substring, **order matters**. Parse `automerge` FIRST, then `auto`:
```bash
# automerge (must precede auto — substring match)
AUTOMERGE_FLAG=0
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[aA][uU][tT][oO][mM][eE][rR][gG][eE]($|[[:space:]]) ]]; then
  AUTOMERGE_FLAG=1
  AUTO_FLAG=1
fi
# auto (standalone — does NOT match inside 'automerge' due to word boundary)
AUTO_FLAG=${AUTO_FLAG:-0}
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[aA][uU][tT][oO]($|[[:space:]]) ]]; then
  AUTO_FLAG=1
fi
```

Note: the `($|[[:space:]])` boundary already prevents `auto` from matching inside `automerge` (because `automerge` has trailing characters). So the existing `auto` regex is safe. The key requirement is simply adding the `automerge` regex.

**`auto merge` (two words)**: The `auto` regex fires (correctly) and sets `AUTO_FLAG=1`. We also need a regex for `merge` preceded by `auto`:
```bash
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[aA][uU][tT][oO][[:space:]]+[mM][eE][rR][gG][eE]($|[[:space:]]) ]]; then
  AUTOMERGE_FLAG=1
fi
```

**Strip chain** (`sed` lines that remove tokens from TASK_DESCRIPTION): must add `automerge` stripping BEFORE the `auto` strip (since `auto` sed won't match inside `automerge` anyway due to word boundary, but for clarity strip the longer token first):
```bash
| sed -E 's/(^|[[:space:]])[aA][uU][tT][oO][mM][eE][rR][gG][eE]($|[[:space:]])/ /' \
| sed -E 's/(^|[[:space:]])[aA][uU][tT][oO]($|[[:space:]])/ /' \
```

Same applies to `auto merge` (two words) — add a strip for the two-word form:
```bash
| sed -E 's/(^|[[:space:]])[aA][uU][tT][oO][[:space:]]+[mM][eE][rR][gG][eE]($|[[:space:]])/ /' \
```

### 4. Doc pages (5 skill docs)

For each: `docs/skills/{run-plan,do,commit,fix-issues,draft-tests}.md`

- Arguments table: add `automerge` row — "Unattended execution + auto-merge. Implies `auto`."
- Update existing `auto` row description: "Unattended execution (no merge). See `automerge`."
- Flow-diagram blocks (`<div class="flow-step optional">`): update any that mention auto-merge to reflect the new token
- Tips & Gotchas: add bullet — "`auto` runs unattended but does not merge; use `automerge` for unattended + auto-merge."

### 5. `/work-on-plans`

Confirmed: `/work-on-plans` dispatches `/run-plan ... auto` unconditionally (modes/execute.md line ~456). It's a batch-execution skill — auto is always implied. Decision: **add `automerge` support** so the user can choose whether batch execution also merges.

- `skills/work-on-plans/SKILL.md` — accept `automerge` token, pass to `/run-plan`
- `skills/work-on-plans/modes/execute.md` — conditionally append `automerge` to the `/run-plan` dispatch

### 6. `/research-and-go`

Confirmed: no `--auto`/LAND_ARGS references. This skill dispatches `/do` or `/run-plan` but doesn't touch merge. **No change needed.**

### 7. Changelog

- `CHANGELOG.md` — entry under Unreleased: "Breaking: `auto` no longer requests auto-merge; use `automerge` for the previous behavior"
- `README.md` — no change needed (skills table doesn't describe tokens)

## Migration / breaking change

This is a **breaking change** for users whose cron schedules or workflows use `auto` expecting auto-merge. Mitigations:

- CHANGELOG notes the break clearly
- The behavior failure mode is safe (PR created but not merged — user notices on first run and adds `automerge`)
- `auto merge` (two words) works as `automerge` so muscle-memory typos aren't punished

**Specific impact on `/work-on-plans`**: This skill dispatches `/run-plan ... auto` unconditionally for batch execution. After this change, batch runs will no longer auto-merge by default. Users who want batch-and-merge must invoke `/work-on-plans automerge`. This is intentional — batch execution creating PRs for morning review is the safer default.

## What does NOT change

- `--auto` still gates BEHIND recovery (Step 6b) — unattended callers still benefit from automated rebase
- `--auto` still gates fix-cycle iteration — the agent still retries failing CI
- `pr-monitor.sh` still runs regardless
- All existing result-file statuses remain valid
- The `auto-not-requested` MERGE_REASON now fires when `--auto` is passed without `--automerge` (previously only when `--auto` was absent). **Verified safe**: callers parse MERGE_REASON into their result array but never branch on its value — they branch only on STATUS (merged, pr-ready, etc.). The MERGE_REASON is informational/logging only.

## Difficulty

Medium. ~12 files touched, each change is small and mechanical. The risk is in the behavioral break for existing `auto` users — but the failure mode is safe (PR created, not merged).
