---
name: quickfix
disable-model-invocation: true
argument-hint: "[<description>] [--branch <name>] [--yes] [--from-here] [--skip-tests] [--force] [--rounds N]"
description: >-
  Ship an in-flight edit (or short agent-authored fix) as a PR without a
  worktree. Two auto-detected modes: user-edited (dirty tree + description →
  carry edits to a branch and commit) and agent-dispatched (clean tree +
  description → model-layer dispatch performs edits, then we commit). PR-only:
  requires execution.landing == "pr". Runs testing.unit_cmd (aligned with
  full_cmd to satisfy the project pre-commit hook), commits, pushes, and
  creates a PR via gh. No worktree; no .landed marker.
  Usage: /quickfix [<description>] [--branch <name>] [--yes] [--from-here] [--skip-tests] [--force] [--rounds N]
metadata:
  version: "2026.05.02+3852b0"
---

# /quickfix — In-Flight Fix → PR

`/quickfix` turns the current main checkout (with or without dirty edits)
into a one-commit PR without leaving main. No worktree. No cherry-pick.
Lifecycle: triage → review → commit → push → PR → CI poll → fix cycle.

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

## Entry self-assertion (WI 1.1)

At entry, when the SDK exposes `$SKILL_SELF` (path to this file), assert
that the frontmatter still carries `disable-model-invocation: true`:

```bash
if [ -n "${SKILL_SELF:-}" ] && [ -f "$SKILL_SELF" ]; then
  if ! grep -q '^disable-model-invocation: true$' "$SKILL_SELF"; then
    echo "ERROR: /quickfix SKILL.md missing 'disable-model-invocation: true'" >&2
    exit 1
  fi
fi
# If $SKILL_SELF cannot be located (test-harness injection, older runtime),
# the check is a no-op — the frontmatter grep in tests/run-all.sh still
# enforces the invariant at CI time.
```

## Argument parser (WI 1.2)

Bash-regex idiom matching `skills/do/SKILL.md:70-92`. Recognized flags:
`--branch <name>`, `--yes` / `-y`, `--from-here`, `--skip-tests`. Everything
else becomes the DESCRIPTION (trimmed of leading/trailing whitespace).
Empty DESCRIPTION is allowed at parse time — mode detection (WI 1.5)
decides whether it is fatal.

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
YES_FLAG=0
FROM_HERE=0
SKIP_TESTS=0
FORCE=0
ROUNDS=1

i=0
while [ $i -lt ${#ARGS[@]} ]; do
  arg="${ARGS[$i]}"
  case "$arg" in
    --branch)
      i=$((i+1))
      BRANCH_OVERRIDE="${ARGS[$i]:-}"
      ;;
    --yes|-y)    YES_FLAG=1 ;;
    --from-here) FROM_HERE=1 ;;
    --skip-tests) SKIP_TESTS=1 ;;
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

**Check 2 — landing == pr.**

```bash
if [ "$LANDING" != "pr" ]; then
  echo "ERROR: /quickfix requires execution.landing == \"pr\" (got \"$LANDING\"). Use /commit or /do for non-PR landing." >&2
  exit 1
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
  echo "ERROR: /quickfix requires testing.unit_cmd (or pass --skip-tests)." >&2
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

Verify we are on main or master (unless `--from-here` is passed). Capture
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
      echo "ERROR: /quickfix must run on main or master (got '$CURRENT_BRANCH'). Pass --from-here to override." >&2
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
`REDIRECT:/fix-issues:reason`, `REDIRECT:ask-user:reason`.

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

**Per-target redirect message templates** (must be exact-text-grep-able).
Each message is **two physical lines** in the printed output (the
linebreak is a real newline, not the literal `\n` characters):

| target | Line 1 | Line 2 |
|--------|--------|--------|
| `/draft-plan` | `Triage: redirecting to /draft-plan. Reason: <reason>` | `This task spans more than one concept; /draft-plan will research and decompose it. Run \`/draft-plan <description>\` instead, or re-invoke with --force to bypass.` |
| `/run-plan` | `Triage: redirecting to /run-plan. Reason: <reason>` | `This task references an existing plan file. Run \`/run-plan <plan-path>\` to execute it, or re-invoke with --force to bypass.` |
| `/fix-issues` | `Triage: redirecting to /fix-issues. Reason: <reason>` | `This task references a GitHub issue. Run \`/fix-issues <issue-number>\` instead, or re-invoke with --force to bypass.` |
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

When `MODE == "user-edited"` (i.e. `$DIRTY_FILES` is non-empty), the model
MUST, before proceeding to slug/branch creation:

1. Show the user the full dirty-file list (one per line).
2. Show the output of `git diff HEAD`.
3. Explicitly ask: **"Commit all of these files as part of '<DESCRIPTION>'? [y/N]"**
4. Only proceed if the user affirms. If the user declines, exit cleanly
   with `exit 0`. There are two decline paths with different marker
   semantics:

   1. **Production (model-layer) decline.** When the model itself
      executes WI 1.5.5 and the user types `n`, the script exits BEFORE
      WI 1.8 has run — no marker has been written, the EXIT trap is not
      registered, and no branch has been created. Identical observable
      end state to triage-redirect and review-reject: empty disk.
   2. **Test-fixture (bash-fallback) decline.** When the bash extractor
      in the test suite hits the `case "$answer" in *)` arm at WI 1.10
      (with `--yes`-bypassed prompt), WI 1.8 has already run — the
      marker exists at `status: started` and the EXIT trap is
      registered. WI 1.10 sets `CANCEL_REASON='user-declined'` and
      `CANCELLED=1`; the trap then runs `finalize_marker` which
      transitions `status: started` → `status: cancelled` and appends
      `reason: user-declined`.

   No branch is created at this confirmation point in either path, so
   no branch rollback is needed. (Triage redirect and review reject
   paths exit BEFORE WI 1.8 and write no marker at all — observably
   identical to the production decline path above.)

**Rationale:** user-edited mode accepts dirty-tree input so the user can
ship a one-line fix without stashing. But without an explicit
confirmation, the model could loosely match `$DESCRIPTION` to the dirty
files and accidentally bundle unrelated in-flight work into the PR. Don't
rely on description-to-filename pattern-matching — always surface the full
diff and confirm before branching.

This confirmation supersedes WI 1.10's bash `read -r` prompt, which now
exists only as a fallback for the literal-script execution path used by
`tests/test-quickfix.sh` Case 43 (invoked with `--yes`).

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
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
PIPELINE_ID=$(bash "$MAIN_ROOT/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh" "quickfix.$SLUG")
echo "ZSKILLS_PIPELINE_ID=$PIPELINE_ID"

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

CANCELLED=0
CANCEL_REASON=""
finalize_marker() {
  local rc="$1"
  local final
  if [ "$CANCELLED" -eq 1 ]; then
    final="cancelled"
  elif [ "$rc" -eq 0 ]; then
    final="complete"
  else
    final="failed"
  fi
  # Rewrite the status line, preserving the rest.
  if [ -f "$MARKER" ]; then
    sed -i "s/^status: started$/status: $final/" "$MARKER"
  fi
  # Append `reason:` for the user-decline path only. Placed AFTER the
  # outer `fi` (not nested inside it) so the new block is self-guarding
  # via its own `[ -f "$MARKER" ]` check — pinning OUTSIDE prevents
  # future refactors of the outer guard from accidentally breaking the
  # reason-write path.
  if [ "$CANCELLED" -eq 1 ] && [ -n "${CANCEL_REASON:-}" ] && [ -f "$MARKER" ] \
     && ! grep -q '^reason:' "$MARKER"; then
    printf 'reason: %s\n' "$CANCEL_REASON" >> "$MARKER"
  fi
}
trap 'finalize_marker $?' EXIT
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

## Phase 3 — Make the change

### WI 1.10 — User-edited mode

Enumerate changed files, show the diff, optionally prompt. Re-compute
the three sets after the branch switch so `CHANGED_FILES` reflects what
will be staged (untracked files carry across; new untracked on the new
branch still count).

**Note:** The bash confirmation block below is vestigial in real
(model-driven) `/quickfix` invocation — WI 1.5.5 already obtained the
user's explicit confirmation. It remains in place to support
literal-script execution in `tests/test-quickfix.sh` Case 43, which
passes `--yes` to bypass the `read -r`. Do not re-prompt the user if WI
1.5.5 already did.

```bash
if [ "$MODE" = "user-edited" ]; then
  MODS=$(git diff --name-only HEAD)
  DELS=$(git diff --name-only --diff-filter=D HEAD)
  UNTRACKED=$(git ls-files --others --exclude-standard)
  CHANGED_FILES=$(printf '%s\n%s\n' "$MODS" "$UNTRACKED" | sed '/^$/d' | sort -u)

  echo "=== /quickfix user-edited mode ==="
  echo "Branch: $BRANCH (base: $BASE_BRANCH)"
  echo "Description: $DESCRIPTION"
  echo ""
  echo "Files changed:"
  echo "$CHANGED_FILES" | sed 's/^/  /'
  if [ -n "$DELS" ]; then
    echo "Files deleted:"
    echo "$DELS" | sed 's/^/  /'
  fi
  echo ""
  git --no-pager diff HEAD

  if [ "$YES_FLAG" -eq 0 ]; then
    printf 'Proceed? [y/N] '
    read -r answer
    case "$answer" in
      y|Y|yes|YES) ;;
      *)
        CANCEL_REASON="user-declined"
        CANCELLED=1
        echo "Cancelled by user. Cleaning up branch." >&2
        if ! git checkout "$BASE_BRANCH"; then
          echo "ERROR: cleanup: failed to checkout $BASE_BRANCH. Repo may be in an intermediate state; manual recovery needed." >&2
          exit 6
        fi
        if ! git branch -D "$BRANCH"; then
          echo "ERROR: cleanup: failed to delete branch $BRANCH. Manual recovery: 'git branch -D $BRANCH'." >&2
          exit 6
        fi
        exit 0
        ;;
    esac
  fi
fi
```

### WI 1.11 — Agent-dispatched mode

This is a **model-layer instruction**, not a bash block. Skills cannot
dispatch agents from bash (per CREATE_WORKTREE R-F1). Same pattern as
`skills/do/SKILL.md:342-358`.

When `MODE == "agent-dispatched"`:

1. Capture `PRE_HEAD=$(git rev-parse HEAD)` before dispatching.
2. Check `agents.min_model` from `.claude/zskills-config.json`; if set
   to a specific model, include the hint in the dispatch prompt
   (default `auto` → omit, inherit parent model).
3. **Dispatch one Agent tool call** with a prompt that instructs the
   subagent to:
   - `cd $MAIN_ROOT`
   - Implement `$DESCRIPTION`
   - **Do NOT** `git commit`, `git add`, or modify the index
   - **Do NOT** run tests, builds, linters, or formatters
   - When finished, list newly untracked files in the "done" report
   - **IMPORTANT:** Only leave files untracked that you intend to commit
     as part of this change. Delete any scratch, debug, or log files you
     created during exploration before reporting done. The skill will
     include all your remaining untracked files in the commit — any
     lingering scratch will ship in the PR.
4. After the Agent returns, verify:
   - `POST_HEAD=$(git rev-parse HEAD)`; if `POST_HEAD != PRE_HEAD`, the
     agent committed unexpectedly → exit 5 with cleanup (checkout base,
     delete branch).
   - `DIRTY_AFTER` is the sorted union of tracked modifications AND
     newly untracked files. The agent is expected (per step 3's
     IMPORTANT clause) to have cleaned up scratch/debug/log files
     before reporting done, so any remaining untracked files ARE part
     of the intended commit and SHOULD be staged. Definition:
     ```bash
     DIRTY_AFTER=$(printf '%s\n%s\n' "$(git diff --name-only HEAD)" "$(git ls-files --others --exclude-standard)" | sed '/^$/d' | sort -u)
     ```
   - If `DIRTY_AFTER` is empty, the agent did not change the tree →
     exit 5 with cleanup.
5. Populate:
   ```bash
   CHANGED_FILES="$DIRTY_AFTER"
   DELS=$(git diff --name-only --diff-filter=D HEAD)
   ```
6. Proceed to the test gate (WI 1.12).

## Phase 4 — Test gate (WI 1.12)

When `--skip-tests` is passed, warn and skip. Otherwise run the project's
`unit_cmd` with output captured to a per-quickfix `/tmp/zskills-tests`
directory (never piped — see CLAUDE.md's "capture test output to a file,
never pipe" rule).

```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
if [ "$SKIP_TESTS" -eq 1 ]; then
  echo "WARN: --skip-tests passed; skipping $UNIT_CMD" >&2
else
  TEST_OUT="/tmp/zskills-tests/$(basename "$MAIN_ROOT")-quickfix-$SLUG"
  mkdir -p "$TEST_OUT"
  if ! bash -c "$UNIT_CMD" > "$TEST_OUT/${TEST_OUTPUT_FILE:-.test-results.txt}" 2>&1; then
    echo "ERROR: tests failed. See $TEST_OUT/${TEST_OUTPUT_FILE:-.test-results.txt}" >&2
    # Rollback: leave edits in the working tree (user may have work to save),
    # drop back to base, delete the feature branch.
    if ! git checkout "$BASE_BRANCH"; then
      echo "ERROR: cleanup: failed to checkout $BASE_BRANCH after test failure." >&2
      exit 6
    fi
    if ! git branch -D "$BRANCH"; then
      echo "ERROR: cleanup: failed to delete branch $BRANCH after test failure." >&2
      exit 6
    fi
    exit 4
  fi
fi
```

## Phase 5 — Commit (WI 1.13)

CLAUDE.md feature-complete discipline applies: stage by name only (never
`git add .` or `-A`). Reject directories — everything in `CHANGED_FILES`
must be a regular file path. Deletions are staged via `git add -u` on the
DELS list.

**Never bypass the pre-commit hook.** If the hook fires, fix the root
cause and rerun; do not pass any flag that would skip hook verification.

On commit failure, clean up verified-each-step: any cleanup step that
itself fails exits 6 (manual intervention).

```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
# Stage: reject directory entries.
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if [ -d "$MAIN_ROOT/$f" ]; then
    echo "ERROR: refusing to stage directory '$f' (stage individual files only)." >&2
    exit 5
  fi
done <<< "$CHANGED_FILES"

# shellcheck disable=SC2086
# CHANGED_FILES is a newline-separated list; xargs -r0 with tr guards against spaces-in-paths.
while IFS= read -r f; do
  [ -z "$f" ] && continue
  git add -- "$f"
done <<< "$CHANGED_FILES"

if [ -n "$DELS" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    git add -u -- "$f"
  done <<< "$DELS"
fi

# Co-author line for agent-dispatched mode comes from $COMMIT_CO_AUTHOR
# (resolved by the helper at fence-top). Empty value means no
# Co-Authored-By trailer (consumer opt-out).
```

**Compose the commit subject (model-layer).** Look at `git diff --cached`
and `git diff --cached --stat`. Set shell variable `COMMIT_SUBJECT` to a
conventional-commit line: `type(scope): summary` (type ∈ {feat, fix, docs,
refactor, chore, test, build, ci, style, perf, revert}; scope is the
primary skill/module/file being changed; summary ≤ 70 chars describing
what was actually changed). DESCRIPTION is the task spec — it goes into
the commit body as context, **not** the subject line.

The next bash fence consumes `$COMMIT_SUBJECT` to compose the full body
and invoke `git commit`. If the commit fails, the same fence runs the
cleanup (checkout base, delete branch, exit 5; each cleanup step
verified, any that itself fails exits 6 for manual intervention). Never
pass `--no-verify` — fix the root cause and retry (max 2 attempts on the
same error, then STOP and report).

```bash
# Resolve $COMMIT_CO_AUTHOR at fence-top — context compaction may have
# lost vars set in the earlier helper-source fence (per the convention at
# run-plan/modes/pr.md:325-345).
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"

# The model must set COMMIT_SUBJECT before this fence runs (see prose
# above). DESCRIPTION goes in the body as context, not the subject line.
if [ -z "${COMMIT_SUBJECT:-}" ]; then
  echo "ERROR: COMMIT_SUBJECT not set — model-layer composition step skipped." >&2
  exit 5
fi

if [ "$MODE" = "user-edited" ]; then
  # No Co-Authored-By: the human authored the edits.
  COMMIT_BODY=$(cat <<COMMIT_EOF
$COMMIT_SUBJECT

$DESCRIPTION

🤖 Generated with /quickfix (user-edited)
COMMIT_EOF
)
elif [ -n "$COMMIT_CO_AUTHOR" ]; then
  # agent-dispatched + co_author configured: include Co-Authored-By trailer.
  COMMIT_BODY=$(cat <<COMMIT_EOF
$COMMIT_SUBJECT

$DESCRIPTION

🤖 Generated with /quickfix (agent-dispatched)

Co-Authored-By: $COMMIT_CO_AUTHOR
COMMIT_EOF
)
else
  # agent-dispatched + co_author empty (consumer opt-out): no trailer.
  COMMIT_BODY=$(cat <<COMMIT_EOF
$COMMIT_SUBJECT

$DESCRIPTION

🤖 Generated with /quickfix (agent-dispatched)
COMMIT_EOF
)
fi

if ! git commit -m "$COMMIT_BODY"; then
  echo "ERROR: git commit failed (pre-commit hook, hook exit, or other)." >&2
  if ! git reset HEAD -- . ; then
    echo "ERROR: cleanup: git reset HEAD failed." >&2
    exit 6
  fi
  if ! git checkout "$BASE_BRANCH"; then
    echo "ERROR: cleanup: failed to checkout $BASE_BRANCH." >&2
    exit 6
  fi
  if ! git branch -D "$BRANCH"; then
    echo "ERROR: cleanup: failed to delete branch $BRANCH." >&2
    exit 6
  fi
  exit 5
fi
```

## Phase 6 — Push (WI 1.14)

**Bare-branch form ONLY.** Never use a `src:dst` refspec when pushing
the feature branch (especially not one whose right-hand side targets a
protected ref). The refspec strip in `hooks/block-unsafe-generic.sh:215-220`
(`PUSH_TARGET="${PUSH_TARGET%%:*}"` followed by a protected-ref gate)
means refspec forms could bypass the guard when the right-hand side is a
protected ref — the bare form is independently sound and does not depend
on that strip.

On push failure, leave branch and commit intact; the user retries manually.

```bash
if ! git push -u origin "$BRANCH"; then
  echo "ERROR: git push failed. Branch '$BRANCH' and its commit are intact locally; retry manually once the remote is reachable." >&2
  exit 5
fi
```

## Phase 7 — PR creation, CI poll, fix-cycle (WI 1.15) — dispatch `/land-pr`

`/quickfix` no longer owns inline PR creation, CI polling, or the fix-cycle.
Those move to `/land-pr` (see `skills/land-pr/SKILL.md`). `/quickfix`'s
remaining responsibilities here are (a) compose `$PR_TITLE` + body file
BEFORE invoking /land-pr, (b) drive the canonical caller loop, (c) on
`CI_STATUS=fail` dispatch a fix-cycle agent at orchestrator level whose
work-context slot is the user's `$DESCRIPTION` plus the staged commit
subject, and (d) preserve the WI 1.16 `pr: $PR_URL` marker append + the
WI 1.17 return-to-base-branch behavior on success.

**Compose $PR_TITLE (model-layer).** Set shell variable `PR_TITLE` to a
single-line conventional-commit style title of the form
`type(scope): summary` (type ∈ {feat, fix, docs, refactor, chore, test,
build, ci, style, perf, revert}; scope is the primary module/file being
changed; summary describes what's actually changing). ≤70 chars, no
newlines. Compose from what the PR actually does — not a verbatim prefix
of the description.

PR body is composed once before the loop and written to a `$BODY_FILE`
that `/land-pr`'s `pr-push-and-create.sh` consumes via `--body-file`. The
heredoc uses `<<-EOF` with **tab-indented** body lines (tabs are stripped
by `<<-`; using spaces would render the body as a code block on GitHub).

```bash
if [ -z "${PR_TITLE:-}" ]; then
  echo "ERROR: PR_TITLE not set — model-layer composition step skipped." >&2
  exit 5
fi
if [[ "$PR_TITLE" == *$'\n'* ]] || [ ${#PR_TITLE} -gt 70 ]; then
  echo "ERROR: PR_TITLE must be a single line ≤70 chars (got '$PR_TITLE')." >&2
  exit 2
fi

# Per-BRANCH_SLUG body file path so concurrent /quickfix invocations on
# parallel slugs do not collide.
BRANCH_SLUG="${BRANCH//\//-}"
BODY_FILE="/tmp/pr-body-quickfix-$BRANCH_SLUG.md"
cat > "$BODY_FILE" <<-EOF
	## Summary

	$DESCRIPTION

	Mode: \`$MODE\`
	Base: \`$BASE_BRANCH\`
	Slug: \`$SLUG\`

	## Test plan

	- Ran project \`unit_cmd\` before commit (or --skip-tests).
	- Review diff.

	🤖 Generated with /quickfix
	EOF
```

`/quickfix` customizations of the canonical caller-loop pattern (per
`skills/land-pr/references/caller-loop-pattern.md`):

- `$LANDED_SOURCE = "quickfix"`
- **No `--worktree-path`** — `/quickfix` has no worktree; this means
  `/land-pr` does NOT write a `.landed` marker. The two artifact systems
  coexist intentionally: `/quickfix`'s fulfillment marker (with `pr:` URL
  appended below) tracks the `/quickfix` lifecycle; `.landed` is for
  worktree-using callers.
- **No `--auto`** — auto-merge stays OFF for `/quickfix` (matches
  pre-migration behavior; the change here is additive CI monitoring +
  fix-cycle, not auto-merge).
- `<CALLER_PRE_INVOKE_BODY_PREP>` = empty (`/quickfix` composes the body
  once above; no per-phase update like /run-plan does).
- `<CALLER_REBASE_CONFLICT_HANDLER>` = no agent-assisted resolution
  (`/quickfix` has no worktree and no plan context); break and surface
  the bail.
- `<DISPATCH_FIX_CYCLE_AGENT_HERE>` = user's `$DESCRIPTION` + staged
  commit subject (`$COMMIT_SUBJECT`).

```bash
# === BEGIN CANONICAL /land-pr CALLER LOOP ===
# Per skills/land-pr/references/caller-loop-pattern.md.

ATTEMPT=0
MAX="${CI_MAX_ATTEMPTS:-2}"
RESULT_FILE="/tmp/land-pr-result-$BRANCH_SLUG-$$.txt"

LANDED_SOURCE="quickfix"
LAND_ARGS="--branch=$BRANCH --title=\"$PR_TITLE\" --body-file=$BODY_FILE --result-file=$RESULT_FILE --landed-source=$LANDED_SOURCE"

while :; do
  # <CALLER_PRE_INVOKE_BODY_PREP> — empty for /quickfix.
  #
  # /quickfix composes the body once above and never refreshes it.
  # /land-pr touches the body only on initial PR creation; on existing
  # PRs (the second-iteration retry case) the body is preserved as-is —
  # fine for /quickfix because the body content is a static
  # description+mode snapshot, not a progress checklist that drifts.

  # Invoke /land-pr via the Skill tool. The Skill tool loads /land-pr's
  # prose into the current (orchestrator) context — its internal bash
  # blocks run here.
  #
  # Skill: { skill: "land-pr", args: "$LAND_ARGS" }

  if [ ! -f "$RESULT_FILE" ]; then
    echo "ERROR: /land-pr produced no result file at $RESULT_FILE" >&2
    exit 5
  fi

  # SAFE allow-list parsing (per WI 1.7). Never `source`. Reading line by
  # line and dispatching on a fixed key set guarantees that even
  # maliciously-crafted values cannot reach shell evaluation.
  declare -A LP
  while IFS='=' read -r KEY VALUE; do
    case "$KEY" in
      STATUS|PR_URL|PR_NUMBER|PR_EXISTING|CI_STATUS|CI_LOG_FILE|\
      MERGE_REQUESTED|MERGE_REASON|PR_STATE|REASON|\
      CONFLICT_FILES_LIST|CALL_ERROR_FILE)
        LP["$KEY"]="$VALUE" ;;
      "") ;;  # blank line — ignore
      *) printf 'WARN: /land-pr result has unknown key %q — ignoring\n' "$KEY" >&2 ;;
    esac
  done < "$RESULT_FILE"

  STATUS="${LP[STATUS]:-}"
  CI_STATUS="${LP[CI_STATUS]:-}"
  PR_URL="${LP[PR_URL]:-}"
  PR_NUMBER="${LP[PR_NUMBER]:-}"

  # Sidecar cleanup paths. CI_LOG_FILE intentionally NOT in the array —
  # the fix-cycle agent below reads it.
  _CLEANUP_PATHS=("${LP[CALL_ERROR_FILE]:-}" "${LP[CONFLICT_FILES_LIST]:-}")
  rm -f "$RESULT_FILE"

  # WI 1.16 — append the PR URL to the fulfillment marker as soon as
  # /land-pr emits one (first iteration where STATUS ∈ {created, monitored,
  # merged}). Append-once is enforced via the `pr:` line absence check:
  # subsequent loop iterations will re-emit the same PR_URL (since
  # /land-pr is idempotent and the PR already exists), but the marker
  # already carries the line. The EXIT trap (registered by WI 1.8) flips
  # `status: started` → `status: complete` at script end.
  if [ -n "$PR_URL" ] && [ -f "$MARKER" ] && ! grep -q '^pr: ' "$MARKER"; then
    printf 'pr: %s\n' "$PR_URL" >> "$MARKER"
  fi

  case "$STATUS" in
    rebase-conflict)
      # <CALLER_REBASE_CONFLICT_HANDLER> — /quickfix has no worktree and
      # no plan context, so no agent-assisted resolution path. /land-pr
      # already aborted the rebase — break and surface to user.
      echo "/land-pr returned rebase-conflict. Resolve manually and re-run \`/quickfix\` (or land manually)." >&2
      break ;;
    push-failed|create-failed|monitor-failed|merge-failed|rebase-failed)
      echo "ERROR: /land-pr STATUS=$STATUS REASON=${LP[REASON]:-} (see ${LP[CALL_ERROR_FILE]:-no-error-file})" >&2
      break ;;
    created|monitored|merged) ;;  # fall through to CI-status check
  esac

  case "$CI_STATUS" in
    pass|none|skipped)
      break ;;  # /land-pr already requested merge if --auto (none for /quickfix)
    pending)
      break ;;  # settle at pr-ready
    not-monitored)
      break ;;  # --no-monitor was used (none of /quickfix's flows do this)
    fail)
      if [ "$ATTEMPT" -ge "$MAX" ]; then
        echo "INFO: CI fix-cycle exhausted ($ATTEMPT/$MAX); PR settles at pr-ci-failing" >&2
        break
      fi
      # ===== <DISPATCH_FIX_CYCLE_AGENT_HERE> — /quickfix customization =====
      #
      # Dispatch a fix-cycle agent at orchestrator level (NOT a nested
      # subagent — /land-pr was already invoked at orchestrator level
      # via the Skill tool; this dispatch is at the same level).
      #
      # Prompt structure follows
      # skills/land-pr/references/fix-cycle-agent-prompt-template.md.
      # /quickfix fills <CALLER_WORK_CONTEXT> with the user's original
      # `$DESCRIPTION` and the staged commit subject `$COMMIT_SUBJECT` —
      # the agent gets the same intent the commit captured, plus the CI
      # failure log.
      #
      # Inputs (substituted into the template):
      #   PR URL       = ${LP[PR_URL]}
      #   PR number    = ${LP[PR_NUMBER]}
      #   Branch       = $BRANCH
      #   Worktree     = (none — agent works in the current repo root)
      #   CI log file  = ${LP[CI_LOG_FILE]}
      #   Caller work context (CALLER_WORK_CONTEXT):
      #     Description: $DESCRIPTION
      #     Commit subject: $COMMIT_SUBJECT
      #     Mode: $MODE
      #     Branch: $BRANCH
      #     Recent commits on this branch:
      #       $(git log origin/$BASE_BRANCH..HEAD --format='%h %s')
      #
      # Constraints (verbatim from the template):
      #   - You are running at orchestrator level. Do NOT dispatch
      #     further Agent tools.
      #   - Do not invoke /land-pr yourself. The caller's loop owns
      #     re-invocation.
      #   - Do not modify .github/workflows/ unless the failure is
      #     clearly a workflow bug.
      #   - Honor existing tests (CLAUDE.md "NEVER weaken tests").
      #   - No --no-verify on commits.
      #
      # Procedure: read CI log → diagnose → state root cause → patch →
      # commit → push. The agent ends its reply with one line:
      #   FIX-CYCLE: root_cause="..." files_changed=N commit=<sha>
      # or
      #   FIX-CYCLE-PUNT: reason="..."
      #
      # After the agent completes, the caller's loop increments $ATTEMPT
      # and `continue`s — /land-pr is idempotent.
      # =====================================================================
      ATTEMPT=$((ATTEMPT + 1))
      continue ;;  # re-enter loop, /land-pr is idempotent
    unknown)
      echo "WARN: CI_STATUS=unknown — settling at pr-ready" >&2
      break ;;
    *)
      echo "WARN: CI_STATUS='$CI_STATUS' unrecognized — settling at pr-ready" >&2
      break ;;
  esac
done

# Sidecar cleanup (after final iteration). CI_LOG_FILE intentionally
# NOT in the array — useful for post-mortem inspection.
for f in "${_CLEANUP_PATHS[@]}"; do
  [ -n "$f" ] && [ -f "$f" ] && rm -f "$f"
done

# Body file cleanup — keep until after the loop in case a re-invocation
# needs it (only consumed on the first iteration where the PR doesn't
# exist yet, but defensive).
rm -f "$BODY_FILE"

# Print the PR URL on stdout so the user sees something actionable.
if [ -n "$PR_URL" ]; then
  echo "$PR_URL"
fi

# WI 1.17 — return to base branch on success.
# The PR exists on GitHub; locally we leave the user where they started
# (on $BASE_BRANCH) so subsequent commands don't accidentally pile onto
# the feature branch. Forgiving: if the checkout fails, warn but do not
# fail the run — the PR is already created.
if ! git checkout "$BASE_BRANCH"; then
  echo "WARN: PR created at $PR_URL but failed to checkout back to $BASE_BRANCH. Run 'git checkout $BASE_BRANCH' manually." >&2
fi
# === END CANONICAL /land-pr CALLER LOOP ===
```

The EXIT trap finalizes the marker to `complete` on success. The CI poll
and fix-cycle are owned by `/land-pr`; `/quickfix`'s pre-PR triage
(WI 1.5.4) and plan-review (WI 1.5.4b) gates remain upstream of this
phase — CI monitoring is additive coverage on top, not a replacement for
them.

### Terminal marker states

The fulfillment marker at `$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/fulfilled.quickfix.$SLUG`
transitions from `status: started` at WI 1.8 entry to exactly one of:

- `status: complete` — PR created, URL appended via `pr: $PR_URL` (the
  append happens in the caller loop on the first iteration where
  `/land-pr` returns a `STATUS=created|monitored|merged`).
- `status: cancelled` is appended with `reason: user-declined` (the only
  documented reason). Triage-redirect, review-reject, and production
  model-layer decline at WI 1.5.5 leave no marker — they exit before
  WI 1.8 writes one.
- `status: failed` — any non-zero exit path after the marker was written.

No `.landed` marker is written. `/quickfix` has no worktree (no
`--worktree-path` is passed to `/land-pr`), and PR state is authoritative
via `gh pr view` — there is no cherry-pick-landing step to attest to.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success (PR created) or user-cancelled confirmation |
| 1 | Config / environment error (landing, gh, not-on-main, fetch failed, unit_cmd unset, full_cmd mismatch, parallel in progress, ls-remote network) |
| 2 | Input error (no edits + no description; user-edited no description; branch exists local/remote; slug empty or contains slash) |
| 4 | Test failure (`unit_cmd` non-zero) |
| 5 | Commit / push / PR-create / agent failure |
| 6 | Cleanup failure — manual intervention needed (a rollback step returned non-zero; repo in intermediate state) |

## Key Rules

- **PR-only.** `execution.landing != "pr"` → hard error; point to `/commit` or `/do`.
- **Aligned test-cmd.** `unit_cmd` set and (if `full_cmd` set) `unit_cmd == full_cmd`; otherwise the project pre-commit hook will block our commit.
- **Dirty tree is input.** Show diff, optionally confirm, carry across via `git checkout -b`. Never stash.
- **Never bypass the pre-commit hook.** Hooks exist for safety; fix the root cause.
- **No error suppression on fallible operations.** Distinguish network failure from branch-exists; check each cleanup step.
- **Bare-branch push only.** `git push -u origin "$BRANCH"` — never a refspec pointed at a protected ref.
- **No `.landed` marker.** `/quickfix` has no worktree; PR state is authoritative via `gh pr view`.
- **Full lifecycle.** triage → review → commit → push → PR → CI poll → fix cycle. PR creation, CI monitoring, and the fix cycle are dispatched via `/land-pr`; on `CI_STATUS=fail`, a fix-cycle agent runs at orchestrator level (up to `CI_MAX_ATTEMPTS`, default 2). Auto-merge stays OFF. The success path returns the user to `$BASE_BRANCH`.
