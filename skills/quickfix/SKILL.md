---
name: quickfix
argument-hint: "[<description>] [auto] [from-here] [skip-tests] [--force] [--branch <name>] [--rounds N]"
description: >-
  Ship an in-flight edit (or short agent-authored fix) from main as a
  one-commit PR without a worktree. Two auto-detected modes: user-edited
  (dirty tree + description) and agent-dispatched (clean tree +
  description). Lifecycle: triage → review → commit → verify → push → PR
  → CI poll → fix cycle (dispatched via 'land-pr'). PR-lifecycle: when
  execution.landing is 'worktree' or 'direct', soft-redirects to
  '/do worktree' or '/commit' respectively. No .landed marker.
  Positional auto: auto-merge.
metadata:
  version: "2026.05.31+9063b5"
---

# /quickfix — In-Flight Fix → PR

`/quickfix` turns the current main checkout (with or without dirty edits)
into a one-commit PR without leaving main. No worktree. No cherry-pick.
Lifecycle: triage → review → commit → verify → push → PR → CI poll → fix cycle.

**Ultrathink throughout.**

## Modes (auto-detected)

| DIRTY_FILES empty? | DESCRIPTION | Mode | Action |
|--------------------|-------------|------|--------|
| No  | non-empty | **user-edited** | pick up dirty tree, commit under description |
| No  | empty     | — | exit 2 (user-edited mode requires a description) |
| Yes | non-empty | **agent-dispatched** | model-layer dispatch of an agent to implement, then commit |
| Yes | empty     | — | exit 2 (need edits or description) |

The mode is discovered by looking at the working tree **before** branching,
so dirty edits made on main are carried across (via `git checkout -b`) into
the new feature branch.

## Coexistence with other skills

- `/do pr` — fresh worktree, agent-dispatched, for larger tasks.
- `/commit pr` — already on a feature branch with commits ready.
- `/fix-issues pr` — batches of GitHub-issue-driven fixes in per-issue worktrees.
- `/quickfix` — on **main** with in-flight edits (or clean main + description).

Pick `/quickfix` when the edit is small enough that leaving main is more
ceremony than the change is worth, but a PR is still required.

## Argument parser (WI 1.2)

Bash-regex idiom matching `skills/do/SKILL.md:70-92`. Recognized flags:
`--branch <name>`, `--rounds N`, `--force`. Recognized positional tokens
(case-insensitive, anywhere in the arg vector): `auto`,
`from-here`, `skip-tests`. The positional `auto` token enables
auto-merge via `/land-pr` and matches the convention in `/run-plan`,
`/fix-issues`, and `/do`. Everything else becomes the DESCRIPTION
(trimmed of leading/trailing whitespace). Empty DESCRIPTION is allowed
at parse time — mode detection (WI 1.5) decides whether it is fatal.

- **from-here** (optional) — override the "must run on main/master"
  preflight check (WI 1.4). Use when you intentionally want to base the
  feature branch off a non-main checkout.
- **skip-tests** (optional) — skip the WI 1.12 test gate. Warn-only;
  use only for emergency hotfixes where the test suite is unrelated.
- **--force** (optional) — bypass a triage REDIRECT verdict (WI 1.5.4) and
  proceed with `/quickfix` anyway. Dashed form to match `/do`,
  `/work-on-plans`, and `/cleanup-merged` — `--force` is a safety-gate
  override, distinct from the positional verb/mode tokens.

WI 1.5.5's confirmation prompt is bypassed when `AUTO_FLAG=1`.

```bash
# Entry-point unset guard for the model-layer test seam. Without the
# REQUIRED companion flag _ZSKILLS_TEST_HARNESS=1, clear any inherited
# _ZSKILLS_TEST_* vars so a stale stub from a parent shell cannot leak
# into a fresh production /quickfix invocation. See WI 1a.3a.
if [ "${_ZSKILLS_TEST_HARNESS:-}" != "1" ]; then
  unset _ZSKILLS_TEST_TRIAGE_VERDICT _ZSKILLS_TEST_REVIEW_VERDICT
fi

ARGS=( "$@" )
DESCRIPTION=""
BRANCH_OVERRIDE=""
FROM_HERE=0
SKIP_TESTS=0
FORCE=0
ROUNDS=1
AUTO_FLAG=0

i=0
while [ $i -lt ${#ARGS[@]} ]; do
  arg="${ARGS[$i]}"
  case "$arg" in
    --branch)
      i=$((i+1))
      BRANCH_OVERRIDE="${ARGS[$i]:-}"
      ;;
    # Dashed safety-gate override `--force` (case-sensitive — `--Force`,
    # `--FORCE` etc. are NOT accepted; this matches /do, /work-on-plans,
    # /cleanup-merged conventions). The positional bare `force` form was
    # retired in favor of this dashed form (issue #810).
    --force) FORCE=1 ;;
    # Positional `from-here` / `skip-tests` tokens (case-insensitive).
    # Bracket-class form matches each letter case-insensitively; the hyphen
    # between bracket classes is treated as a literal character (NOT inside
    # a class). Verified: matches `from-here`, `From-Here`, `FROM-HERE`;
    # does NOT match `FromHere`, `FROMHERE`, `from-here2`.
    [fF][rR][oO][mM]-[hH][eE][rR][eE]) FROM_HERE=1 ;;
    [sS][kK][iI][pP]-[tT][eE][sS][tT][sS]) SKIP_TESTS=1 ;;
    # Positional `auto` token (case-insensitive). Recognized anywhere in
    # the arg vector — `/quickfix <desc> auto` and `/quickfix auto <desc>`
    # both set AUTO_FLAG=1. Mirrors the convention in /run-plan,
    # /fix-issues, /do. The token never falls through to DESCRIPTION.
    [aA][uU][tT][oO]) AUTO_FLAG=1 ;;
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
    *)
      if [ -z "$DESCRIPTION" ]; then
        DESCRIPTION="$arg"
      else
        DESCRIPTION="$DESCRIPTION $arg"
      fi
      ;;
  esac
  i=$((i+1))
done

# Trim
DESCRIPTION="${DESCRIPTION#"${DESCRIPTION%%[![:space:]]*}"}"
DESCRIPTION="${DESCRIPTION%"${DESCRIPTION##*[![:space:]]}"}"

# Issue-number parse (claim-work-item Phase 2 / W2.4). /quickfix usually
# works an in-flight edit, not an issue — but when the description begins
# with a `#N` reference (optionally preceded by a close-keyword:
# close/closes/closed/fix/fixes/fixed/resolve/resolves/resolved, case-
# insensitive) extract the bare integer into ISSUE_NUM so WI 1.8 can
# claim the issue via claim-issue.sh. The regex is ANCHORED to the start
# of the description so a `#NNN` literal appearing later in prose (e.g.,
# a quoted example, a line reference, a follow-up "see also #N") does
# NOT set ISSUE_NUM. When no issue reference is in scope (the common
# case) ISSUE_NUM stays empty and nothing is claimed. claim-issue.sh
# rejects non-numeric input with exit 2; the `[0-9]+` capture guarantees
# a bare integer.
ISSUE_NUM=""
if [[ "$DESCRIPTION" =~ ^[[:space:]]*([cC][lL][oO][sS][eE][sSdD]?|[fF][iI][xX]([eE][sSdD])?|[rR][eE][sS][oO][lL][vV][eE][sSdD]?)[[:space:]]+#([0-9]+) ]]; then
  ISSUE_NUM="${BASH_REMATCH[3]}"
elif [[ "$DESCRIPTION" =~ ^[[:space:]]*#([0-9]+) ]]; then
  ISSUE_NUM="${BASH_REMATCH[1]}"
fi
```

## Phase 1 — Pre-flight

### WI 1.3 — Config and environment gates

Resolve `MAIN_ROOT` first so every subsequent path is anchored:

```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
```

Then run the fail-fast gates. Each prints a **single discriminator keyword
line** to stderr and exits:

**Check 1 — `gh` available.**

```bash
if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: /quickfix requires gh (not found on PATH)." >&2
  exit 1
fi
```

**Read config once (bash-regex parsing, no `jq` dependency).**

All subsequent config reads extract from this single capture. Pattern
matches `skills/update-zskills/SKILL.md` Step 0.5. An unmatched key
leaves its variable at the default assigned before the regex test; an
empty string in the config ("present but empty") matches the regex and
is passed through verbatim.

```bash
CONFIG_CONTENT=$(cat "$MAIN_ROOT/.claude/zskills-config.json")

LANDING="direct"
if [[ "$CONFIG_CONTENT" =~ \"landing\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
  LANDING="${BASH_REMATCH[1]}"
fi

UNIT_CMD=""
if [[ "$CONFIG_CONTENT" =~ \"unit_cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
  UNIT_CMD="${BASH_REMATCH[1]}"
fi

FULL_CMD=""
if [[ "$CONFIG_CONTENT" =~ \"full_cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
  FULL_CMD="${BASH_REMATCH[1]}"
fi
```

**Check 2 — landing == pr (soft redirect for non-PR modes).**

`/quickfix` is PR-shaped end-to-end (push, PR creation, CI poll, fix
cycle — all dispatched via `/land-pr`). When `execution.landing` is `worktree`
or `direct`, we cannot meaningfully execute the lifecycle here — but
emitting a hard error contradicts the project principle "all skills
should work in all landing modes" (PR #290 review, issue #293). Instead,
print a two-line redirect to the right skill for the configured landing
mode and `exit 0` so the user can re-invoke the suggested skill. The
redirect uses the same two-line printf template `/quickfix` uses for
triage redirects (WI 1.5.4 — line 1 names the target + reason, line 2
gives the exact re-invocation hint). `pr` (or unset) falls through and
preserves the current PR-lifecycle behavior.

```bash
if [ "$LANDING" = "worktree" ]; then
  printf 'Triage: redirecting to /do worktree. Reason: /quickfix requires execution.landing == "pr" (got "worktree").\nThe project is configured for worktree-based landing. Run `/do worktree <description>` instead — it creates an isolated worktree, lands via cherry-pick, and matches your config.\n'
  exit 0
elif [ "$LANDING" = "direct" ]; then
  printf 'Triage: redirecting to /commit. Reason: /quickfix requires execution.landing == "pr" (got "direct").\nThe project is configured for direct-to-main landing. Run `/commit` instead — it commits in place without the PR scaffolding /quickfix layers on.\n'
  exit 0
fi
```

**Check 3 — test-cmd alignment gate (LOAD-BEARING).**

The project's pre-commit hook (`hooks/block-unsafe-project.sh.template:412-427`)
rejects `git commit` with staged code files unless the Claude transcript
contains the configured `FULL_TEST_CMD`. `/quickfix` runs the project's
`unit_cmd` before committing, so we require `unit_cmd` is set AND — if
`full_cmd` is also set — `full_cmd == unit_cmd`. Otherwise the hook will
block our commit mid-flow.

```bash
if [ "$SKIP_TESTS" -eq 0 ] && [ -z "$UNIT_CMD" ]; then
  echo "ERROR: /quickfix requires testing.unit_cmd (or pass skip-tests)." >&2
  exit 1
fi
if [ -n "$FULL_CMD" ] && [ "$FULL_CMD" != "$UNIT_CMD" ]; then
  echo "ERROR: testing.full_cmd differs from testing.unit_cmd. Project's pre-commit hook checks full_cmd in transcript; align the two or use /commit pr / /do pr." >&2
  exit 1
fi
```

### WI 1.3.5 — Parallel-invocation gate (with staleness)

Refuse to start if another `/quickfix` is already in flight. A marker is
considered **stale** once it is older than `STALE_AGE_SECONDS=3600` (one
hour) — in that case we warn and proceed; otherwise we exit 1.

```bash
STALE_AGE_SECONDS=3600
NOW_EPOCH=$(date +%s)
for marker in "$MAIN_ROOT"/.zskills/tracking/quickfix.*/fulfilled.quickfix.*; do
  [ -f "$marker" ] || continue
  if grep -q '^status: started' "$marker"; then
    # Extract `date:` — GNU date -d is required to parse ISO-8601 back to epoch.
    DATE_LINE=$(grep '^date:' "$marker" | head -n1 | sed 's/^date: //')
    MARKER_EPOCH=$(date -d "$DATE_LINE" +%s 2>/dev/null || echo 0)
    AGE=$((NOW_EPOCH - MARKER_EPOCH))
    if [ "$AGE" -lt "$STALE_AGE_SECONDS" ]; then
      echo "ERROR: another /quickfix is in progress ($marker, age ${AGE}s). Wait or remove the marker." >&2
      exit 1
    else
      echo "WARN: stale /quickfix marker ($marker, age ${AGE}s > ${STALE_AGE_SECONDS}s); proceeding." >&2
    fi
  fi
done
```

### WI 1.4 — Main-ref fetch

Verify we are on main or master (unless `from-here` is passed). Capture
the current branch as `BASE_BRANCH` and fetch the remote ref. **Do NOT
a fast-forward merge of origin into a dirty working tree — paths that
overlap the incoming changes would abort the merge and leave us in a
partial state. Local main may stay stale; the branch creation step
(WI 1.9) branches directly from `origin/$BASE_BRANCH`.

```bash
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$FROM_HERE" -eq 0 ]; then
  case "$CURRENT_BRANCH" in
    main|master) ;;
    *)
      echo "ERROR: /quickfix must run on main or master (got '$CURRENT_BRANCH'). Pass from-here to override." >&2
      exit 1
      ;;
  esac
fi
BASE_BRANCH="$CURRENT_BRANCH"

if ! git fetch origin "$BASE_BRANCH"; then
  echo "ERROR: failed to fetch origin/$BASE_BRANCH (network or auth?)." >&2
  exit 1
fi
```

## Phase 2 — Mode detection and slug

### WI 1.5 — Mode detection

Compute the dirty-file set on entry (deduplicated union of modified,
deleted, and untracked):

```bash
MODS=$(git diff --name-only HEAD)
DELS=$(git diff --name-only --diff-filter=D HEAD)
UNTRACKED=$(git ls-files --others --exclude-standard)
DIRTY_FILES=$(printf '%s\n%s\n%s\n' "$MODS" "$DELS" "$UNTRACKED" | sed '/^$/d' | sort -u)

if [ -n "$DIRTY_FILES" ] && [ -n "$DESCRIPTION" ]; then
  MODE="user-edited"
elif [ -n "$DIRTY_FILES" ] && [ -z "$DESCRIPTION" ]; then
  echo "ERROR: user-edited mode requires a description. Usage: /quickfix <description> [flags]" >&2
  exit 2
elif [ -z "$DIRTY_FILES" ] && [ -n "$DESCRIPTION" ]; then
  MODE="agent-dispatched"
else
  echo "ERROR: /quickfix needs either in-flight edits or a description. Usage: /quickfix [<description>] [flags]" >&2
  exit 2
fi
```

### WI 1.5.4 — Triage gate (model-layer)

This is a **model-layer instruction**, not a bash block. Triage runs after
WI 1.5 so user-edited mode triage may inspect `$DIRTY_FILES` and the
output of `git diff HEAD`. Triage runs BEFORE WI 1.5.5 so we don't ask
the user to confirm a diff we may redirect, and BEFORE WI 1.6 / WI 1.8 —
so a redirect leaves no branch, no marker, no tracking dir, no commits.

**Test seam (production behavior unaffected).** When
`_ZSKILLS_TEST_HARNESS=1` is set, the model MUST skip the triage Agent
dispatch and instead use the value of `_ZSKILLS_TEST_TRIAGE_VERDICT` as
the verdict. Production invocations (where the harness flag is absent
and the entry-point unset guard at WI 1.2 has already cleared the test
vars) always run the full Agent path. Recognized stub values:
`PROCEED`, `REDIRECT:/draft-plan:reason`, `REDIRECT:/run-plan:reason`,
`REDIRECT:ask-user:reason`.

The model judges `$DESCRIPTION` (and, in user-edited mode, the dirty-tree
shape) against this rubric — qualitative, observable from description
text and dirty-tree shape, no LOC counting:

| Signal | Verdict | Mode applicability |
|--------|---------|--------------------|
| Description scopes to one concept; user-edited dirty tree (if any) is one cluster | PROCEED | both |
| ≥ 3 distinct files explicitly named in description | REDIRECT → `/draft-plan` | **agent-dispatched only** (user-edited mode dirty tree may legitimately span ≥3 files; the "Dirty tree spans heterogeneous subsystems" row catches that case) |
| Verbs include any of: `add feature`, `redesign`, `rewrite`, `refactor across` | REDIRECT → `/draft-plan` | both |
| `and` connects unrelated areas (e.g. "fix nav and update copy") | REDIRECT → `/draft-plan` | both |
| Vague verbs alone: `improve`, `fix it`, `update`, `clean up` (no concrete object) | REDIRECT → ask user | both |
| References an existing plan file under `$ZSKILLS_PLANS_DIR` | REDIRECT → `/run-plan` | both |
| Dirty tree (user-edited mode) spans heterogeneous subsystems (model judgment) | REDIRECT → `/draft-plan` | user-edited only |

**Worked examples (calibrate the model's PROCEED/REDIRECT calls):**

| Example invocation | Verdict | Why |
|--------------------|---------|-----|
| `/quickfix Fix README typo` | PROCEED | one concept, one likely file |
| `/quickfix add comment to canary-marker.txt` | PROCEED | one concrete object, one concrete file |
| `/quickfix update CHANGELOG with v0.5 release notes` | PROCEED | concrete verb + object + file |
| `/quickfix add dark mode and refactor the worker pool` | REDIRECT → /draft-plan | "and" connects unrelated areas |
| `/quickfix improve` | REDIRECT → ask user | vague verb, no object |
| `/quickfix Fix #853 typo` | PROCEED | issue-numbered descriptions claim the issue via ISSUE_NUM and proceed |

Output one of:

- `PROCEED` — print `Triage: proceeding with /quickfix (<one-line reason>).` Continue to WI 1.5.4a.
- `REDIRECT(target=<skill>, reason=<text>)` — see redirect handling.

**Per-target redirect message templates** (must be exact-text-grep-able).
Each message is **two physical lines** in the printed output (the
linebreak is a real newline, not the literal `\n` characters):

| target | Line 1 | Line 2 |
|--------|--------|--------|
| `/draft-plan` | `Triage: redirecting to /draft-plan. Reason: <reason>` | `This task spans more than one concept; /draft-plan will research and decompose it. Run \`/draft-plan <description>\` instead, or re-invoke with --force to bypass.` |
| `/run-plan` | `Triage: redirecting to /run-plan. Reason: <reason>` | `This task references an existing plan file. Run \`/run-plan <plan-path>\` to execute it, or re-invoke with --force to bypass.` |
| ask-user | `Triage: cannot proceed — description is too vague to act on. Reason: <reason>` | `Re-invoke /quickfix with a concrete description (verb + object + which file/area). --force will not help — vague descriptions cannot be planned.` |

The model implements these as a `printf 'line1\nline2\n' "$REASON"` so
both lines are emitted to stdout and both are independently greppable
from a test fixture.

On REDIRECT and `$FORCE -eq 0`: print the per-target message (both
lines), then `exit 0`. **No marker is written** (WI 1.8 has not yet
run). No branch. No tracking dir.

On REDIRECT and `$FORCE -eq 1`: print
`Triage: REDIRECT(<target>) overridden by --force; proceeding.`
Continue.

### WI 1.5.4a — Inline plan composition (model-layer)

This is a **model-layer instruction**, not a bash block. After triage
returns PROCEED (or after `--force` overrides a REDIRECT), the model
composes a short inline plan held in `INLINE_PLAN`. `INLINE_PLAN` is a
logical placeholder for text the model composes in its response. When
WI 1.5.4b dispatches the reviewer Agent, the model copies the
`INLINE_PLAN` text **verbatim** into the Agent prompt as the
`INLINE PLAN ...` section — there is no file read or shell-variable
interpolation; this is a model-to-prompt substitution.

```text
### /quickfix inline plan
**Description:** <DESCRIPTION>
**Mode:** <MODE>
**Files (expected):** <comma-separated list, or "as in dirty tree">
**Approach:** <2-4 sentences>
**Acceptance:** <2-4 bullets>
```

Constraints:

- ≤60 lines total.
- The model-authored fields **Approach** and **Acceptance** MUST NOT
  contain the literals for other skills (`/draft-plan`, `/run-plan`,
  `/fix-issues`) — using these in model-authored prose would muddle
  the redirect-message guards.
- The **Description** field is verbatim user input and is exempt — a
  user description that mentions another skill name is the user's
  prerogative.
- Early-stage review judges PLAN STRUCTURE, not file enumeration
  accuracy.

### WI 1.5.4b — Fresh-agent plan review (model-layer)

This is a **model-layer instruction**, not a bash block.

**Test seam (production behavior unaffected).** When
`_ZSKILLS_TEST_HARNESS=1` is set, the model MUST skip the reviewer
Agent dispatch and instead use the value of
`_ZSKILLS_TEST_REVIEW_VERDICT` as the verdict (one of `APPROVE`,
`REVISE: reason`, `REJECT: reason`). Production invocations always run
the full Agent path.

If `$ROUNDS -eq 0`: print to stderr
`WARN: --rounds 0 skips fresh-agent plan review (legacy opt-in).` and
skip review entirely. Continue.

Otherwise dispatch ONE Agent (no model hint — inherit parent) with this
prompt:

```text
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

**Verdict parser (separator-required for REVISE/REJECT).** Trim trailing
whitespace from the first line, then match against this regex (in
priority order):

```regex
# Bare APPROVE: no trailing text on line 1.
^VERDICT:[[:space:]]+APPROVE[[:space:]]*$

# REVISE/REJECT: separator (--) and reason are REQUIRED.
^VERDICT:[[:space:]]+(REVISE|REJECT)[[:space:]]+--[[:space:]]+(.+)$
```

Reason captured in group 2 of the second regex. Em-dashes (`—`, `–`) in
the iteration prompt template are normalized to ASCII `--` before
insertion (the model performs this normalization when composing the
iteration prompt) so the parser only needs to handle ASCII. If the
first line matches NEITHER regex → treat as a malformed verdict, retry
once with the same prompt; on second malformed → soft-reject (same exit
semantics as REJECT).

**REVISE loop.** At most `$ROUNDS` iterations. On REVISE, the model
rewrites `INLINE_PLAN` using BOTH the verdict reason AND the
justification body, then dispatches a NEW reviewer (single reviewer,
NOT /draft-plan dual-agent). Iteration prompt template:

```text
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

On APPROVE: print verdict + justification ABOVE the WI 1.5.5 prompt
(user-edited) or the WI 1.11 dispatch (agent-dispatched). Continue.

On REJECT and `$FORCE -eq 0`: print verdict, exit 0. **No marker is
written** (WI 1.8 has not yet run).

On REJECT and `$FORCE -eq 1`: print override message. Continue.

### WI 1.5.5 — Dirty-tree confirmation (model-layer)

This is a **model-layer instruction**, not a bash block.

**If `$AUTO_FLAG=1`, skip this WI entirely.** Emit stderr NOTE: "NOTE: WI
1.5.5 confirmation skipped (auto)." and proceed to WI 1.6. The `auto`
token is an explicit user opt-in to full autonomy — both auto-merge of
the resulting PR AND skipping the skill-internal scope-confirmation
gate. This makes `/quickfix`'s `auto` semantic match `/run-plan` and
`/fix-issues`, where `auto` means "skip skill-internal gates + auto-merge".

When `MODE == "user-edited"` (i.e. `$DIRTY_FILES` is non-empty), the model
MUST, before proceeding to slug/branch creation:

1. Show the user the full dirty-file list (one per line).
2. Show the output of `git diff HEAD`.
3. Explicitly ask: **"Commit all of these files as part of '<DESCRIPTION>'? [y/N]"**
4. Only proceed if the user affirms. If the user declines, exit cleanly
   with `exit 0`. The script exits BEFORE WI 1.8 has run — no marker
   has been written, and no branch has been created. Identical
   observable end state to triage-redirect and review-reject: empty
   disk. No branch rollback needed (none was created).

   (Phase 4 of QUICKFIX_GRAMMAR_REDESIGN deleted the prior
   bash-fallback decline path at WI 1.10. Per DA H7's mitigation, the
   vestigial `read -r` confirmation prompt is removed — model-layer
   WI 1.5.5 is the sole production gate. Coverage for the decline path
   now lives at model-layer per Phase 5's testability caveat.)

**Rationale:** user-edited mode accepts dirty-tree input so the user can
ship a one-line fix without stashing. But without an explicit
confirmation, the model could loosely match `$DESCRIPTION` to the dirty
files and accidentally bundle unrelated in-flight work into the PR. Don't
rely on description-to-filename pattern-matching — always surface the full
diff and confirm before branching.

This confirmation is the SOLE scope-protection gate. WI 1.10's prior
bash `read -r` confirmation was deleted in Phase 4 of
QUICKFIX_GRAMMAR_REDESIGN; there is no env-var test seam.

When `$ROUNDS != 0`, the WI 1.5.4b reviewer's verdict prints ABOVE this
confirmation prompt as added context. The `[y/N]` is unchanged. A
reviewer APPROVE does not auto-confirm — the user still confirms here.

### WI 1.6 — Slug derivation

**Compose $SLUG (model-layer).** Set shell variable `SLUG` to a kebab-case
identifier matching `^[a-z0-9]+(-[a-z0-9]+)*$`, ≤40 chars, a 3–6 word
summary of the task. Compose from the description's essential verbs/nouns
— not a verbatim prefix of the input. Multi-line descriptions compose the
same way as single-line ones: distill the intent, don't splice lines.

```bash
if [ -z "${SLUG:-}" ]; then
  echo "ERROR: SLUG not set — model-layer composition step skipped." >&2
  exit 5
fi
if ! [[ "$SLUG" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || [ ${#SLUG} -gt 40 ]; then
  echo "ERROR: SLUG must match ^[a-z0-9]+(-[a-z0-9]+)*\$ and be ≤40 chars (got '$SLUG')." >&2
  exit 2
fi
```

Examples:

| Input | Composed SLUG |
|-------|---------------|
| `Fix README typo!` | `fix-readme-typo` |
| `Fix the broken link in docs/intro.md` | `fix-broken-docs-link` |
| `  Update CHANGELOG  ` | `update-changelog` |
| Multi-line: `"Refactor the worker pool\n\nIt's currently unbounded..."` | `refactor-worker-pool` |
| `!!!` | (model cannot compose a slug from punctuation → validator exit 2 after any attempt) |

### WI 1.7 — Branch naming

`--branch` overrides verbatim. Otherwise prefix the slug with
`execution.branch_prefix` (default `quickfix/`; empty string allowed).

```bash
if [ -n "$BRANCH_OVERRIDE" ]; then
  BRANCH="$BRANCH_OVERRIDE"
else
  # branch_prefix: empty string ("present but empty") is legal and distinct
  # from the key being absent. Only fall back to the default when the key
  # is entirely missing.
  if [[ "$CONFIG_CONTENT" =~ \"branch_prefix\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    BRANCH_PREFIX="${BASH_REMATCH[1]}"
  else
    BRANCH_PREFIX="quickfix/"
  fi
  BRANCH="${BRANCH_PREFIX}${SLUG}"
fi
```

| `--branch` | `branch_prefix` | Slug | BRANCH |
|------------|-----------------|------|--------|
| (absent) | (absent) | `fix-readme-typo` | `quickfix/fix-readme-typo` |
| (absent) | `"fix/"` | `fix-readme-typo` | `fix/fix-readme-typo` |
| (absent) | `""` | `fix-readme-typo` | `fix-readme-typo` |
| `custom/foo` | (any) | (any) | `custom/foo` (verbatim) |

### WI 1.8 — Tracking setup

Construct `PIPELINE_ID` via the sanitizer (not a raw string), echo it to
the transcript (tier-2 tracking per `tests/test-hooks.sh:245`), and write
the `started` marker under the pipeline-scoped tracking dir.

```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
PIPELINE_ID=$(bash "$MAIN_ROOT/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh" "quickfix.$SLUG")
echo "ZSKILLS_PIPELINE_ID=$PIPELINE_ID"

[ -n "$PIPELINE_ID" ] || { echo "tracking: empty PIPELINE_ID — refusing flat write" >&2; exit 1; }
TRACK_DIR="$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
MARKER="$TRACK_DIR/fulfilled.quickfix.$SLUG"
mkdir -p "$TRACK_DIR"

NOW_ISO=$(TZ="${TIMEZONE:-UTC}" date -Iseconds)
cat > "$MARKER" <<MARK
status: started
date: $NOW_ISO
skill: quickfix
mode: $MODE
slug: $SLUG
branch: $BRANCH
base: $BASE_BRANCH
MARK

# requires.land-pr.<id> (Plan LAND_PR_BYPASS_HARDENING Phase 2 — drives
# hook STOP-message Pattern 2 + dashboard). Variables $TRACK_DIR, $SLUG,
# $BRANCH, $NOW_ISO are all in scope here (fence A 631-678). Cleanup is
# best-effort glob at end of caller-loop (DA-4-5) since $SLUG is
# out-of-fence-scope at the line 1244 cleanup site.
cat > "$TRACK_DIR/requires.land-pr.$SLUG" <<MARK
skill: land-pr
parent: quickfix
id: $SLUG
branch: $BRANCH
date: $NOW_ISO
MARK

# Issue claim (claim-work-item Phase 2 / W2.4). Acquire here — where
# PIPELINE_ID is established and the `started` marker is written — and
# BEFORE branch creation (WI 1.9). Only when the description referenced an
# issue (ISSUE_NUM non-empty, parsed in WI 1.2); skip otherwise (the common
# /quickfix case). This stops a concurrent /fix-issues cron from
# double-working the same issue. Released in the Phase 7 explicit-finalize
# and the fail-finalize abandon sites (test fail, commit fail, push fail).
if [ -n "${ISSUE_NUM:-}" ]; then
  CLAIM_HELPER="$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/claim-issue.sh"
  bash "$CLAIM_HELPER" acquire "$ISSUE_NUM" --pipeline-id "$PIPELINE_ID" --sprint-id "$PIPELINE_ID"
  ACQ_RC=$?
  case "$ACQ_RC" in
    0)  : ;;  # acquired (fresh or self-re-entry) — proceed
    10) echo "issue #$ISSUE_NUM is being worked by another pipeline; declining." >&2; exit 0 ;;
    11) echo "claim-issue.sh: filesystem error acquiring issue #$ISSUE_NUM; stopping." >&2; exit 1 ;;
    2)  echo "claim-issue.sh: usage error (empty PIPELINE_ID or non-numeric ISSUE_NUM=$ISSUE_NUM) — internal bug; stopping." >&2; exit 1 ;;
    *)  echo "claim-issue.sh: unexpected exit $ACQ_RC acquiring issue #$ISSUE_NUM; stopping." >&2; exit 1 ;;
  esac
fi

# Explicit-finalize pattern (Plan LAND_PR_BYPASS_HARDENING Phase 2; issue
# #241 — matches /commit pr / /do pr / /fix-issues pr). The marker
# starts as `status: started`; each terminal path (test fail at Phase 4,
# commit/push fail at Phase 5/6, /land-pr fail or success at Phase 7)
# explicitly rewrites the status via inline `sed -i` before exiting OR
# at the end of the Phase 7 caller-loop fence. NO `trap … EXIT` is used:
# a bash `trap EXIT` set inside a SKILL.md ```bash code fence fires when
# THAT fence's `bash` invocation ends — not when the skill flow ends —
# so the trap-based pattern stamped `complete` almost immediately on
# skill entry, regardless of actual outcome. (The `status: cancelled`
# terminal — formerly written by WI 1.10's bash-fallback decline — is
# documented at Exit codes / marker semantics; the production decline
# path now lives at model-layer WI 1.5.5 and writes no marker, since
# the user declines BEFORE WI 1.8 runs.)
```

### WI 1.9 — Branch creation

Created from `MAIN_ROOT` so `git checkout -b` carries the dirty tree
across. Three checks before branching:

1. Local ref collision → exit 2.
2. Remote collision via `git ls-remote` — distinguish **network/auth
   failure** (non-zero rc → exit 1) from **branch exists on remote**
   (non-empty output → exit 2). Do not suppress errors here; the two
   outcomes have different remediations.
3. `git checkout -b "$BRANCH" "origin/$BASE_BRANCH"`.

```bash
cd "$MAIN_ROOT"

if git rev-parse --verify --quiet "refs/heads/$BRANCH" >/dev/null; then
  echo "ERROR: branch '$BRANCH' already exists locally. Pick a different slug, pass --branch, or delete the stale branch." >&2
  exit 2
fi

REMOTE_OUT=$(git ls-remote --heads origin "$BRANCH")
REMOTE_RC=$?
if [ "$REMOTE_RC" -ne 0 ]; then
  echo "ERROR: git ls-remote failed for 'origin $BRANCH' (network/auth). Rerun after fixing connectivity." >&2
  exit 1
fi
if [ -n "$REMOTE_OUT" ]; then
  echo "ERROR: branch '$BRANCH' already exists on origin. Pick a different slug or pass --branch." >&2
  exit 2
fi

if ! git checkout -b "$BRANCH" "origin/$BASE_BRANCH"; then
  echo "ERROR: git checkout -b failed (dirty-tree conflict with base?). Resolve and retry." >&2
  exit 5
fi
```

## After Phase 2 — read the execution and landing modes

Phase 2 above (mode detection through WI 1.9 branch creation) is the
router the dispatcher must read before any work happens — it establishes
`$MODE`, `$SLUG`, `$BRANCH`, `$BASE_BRANCH`, `$PIPELINE_ID`, the
`fulfilled.quickfix.$SLUG` start-marker, and the `requires.land-pr.$SLUG`
marker. The rest of the lifecycle was extracted into two mode files plus a
reference, loaded on demand so a /quickfix invocation does not pay the
context cost of the entire lifecycle up front:

1. **After Phase 2 mode detection + branch creation, read
   `modes/execute.md`** for Phases 3–6 (make the change → test gate →
   commit → verify → push). The shared shell variables established above
   (`$MODE`, `$SLUG`, `$BRANCH`, `$BASE_BRANCH`, `$MARKER`, `$PIPELINE_ID`,
   `$ZSKILLS_PIPELINE_ID`, `$ISSUE_NUM`, `$CHANGED_FILES`, `$DELS`,
   `$COMMIT_SUBJECT`) all survive into those phases via the persistent
   shell.
2. **Then read `modes/land.md`** for Phase 7 (PR creation, CI poll, and
   the fix-cycle dispatched via `/land-pr`), which consumes
   `$PR_TITLE`, `$BRANCH`, `$BASE_BRANCH`, `$MARKER`, `$SLUG`,
   `$ZSKILLS_PIPELINE_ID`, and `$ISSUE_NUM`.
3. **Exit codes and Key Rules** live in `references/exit-codes-and-rules.md`.

Read these in order; do not skip ahead. Phases 3–7 are a single
straight-line lifecycle continuing the persistent shell from Phase 2.
