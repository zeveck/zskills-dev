---
name: do
argument-hint: "<description> [--rounds N] [auto] [every SCHEDULE] [now] | stop [query] | next [query] | now [query]"
description: >-
  Lightweight task dispatcher for ad-hoc work: documentation, examples,
  refactoring, content updates. Worktree/direct/pr landing modes via flag
  or execution.landing config. Recurring via every SCHEDULE; stop/next
  manage the schedule.
metadata:
  version: "2026.06.05+498b5d"
---

# /do \<description> [--rounds N] [auto] [every SCHEDULE] [now] | stop [query] | next [query] | now [query] — Lightweight Task Dispatcher

Execute small, ad-hoc tasks with structured research, verification, and
optional isolation or autonomous landing. Can be scheduled for recurring maintenance
tasks. For work that doesn't warrant the full ceremony of `/run-plan` (plan
phases) or `/fix-issues` (batch bug fixing).

**Ultrathink throughout.**

## When to Use `/do`

| Task | Use |
|------|-----|
| Documentation, examples, presentations, screenshots | `/do` |
| Small refactors, one-off fixes, content updates | `/do` |
| Adding a new block type | `/add-block` (10-step workflow) |
| Newsletter entry | `/do` |
| Batch bug fixing (N issues) | `/fix-issues N` |
| Executing a plan phase | `/run-plan` |
| Multi-file feature work with dependencies | `/run-plan` |

**Rule of thumb:** if the task needs a worktree, separate verification agent,
and a persistent report file, it's too big for `/do`. Use `/run-plan` instead.

## Arguments

```
/do <description> [worktree|direct|pr] [auto] [every SCHEDULE] [now]
/do stop | next
```

- **description** (required) — what to do, in natural language
- **landing flags** (optional, mutually exclusive) — override the
  `execution.landing` default in `.claude/zskills-config.json`:
  - **worktree** — isolate in `/tmp/<project>-do-<slug>/`, cherry-pick
    back to main after verification. Matches `execution.landing: "cherry-pick"`.
  - **pr** — named worktree + feature branch, push, create PR to main,
    poll CI. Matches `execution.landing: "pr"`.
  - **direct** — work on main in place, no landing step. Matches
    `execution.landing: "direct"`.
  - When no flag is given, read `execution.landing` from config.
    (`cherry-pick` → worktree, `pr` → pr, `direct` → direct, missing
    config → direct.)
- **auto** (optional, positional, case-insensitive) — land autonomously.
  PR mode: opens PR + requests auto-merge via `--auto` to `/land-pr`,
  which requests GitHub auto-merge once required checks pass. Worktree
  mode: cherry-picks to main, pushes. Direct mode: pushes main.
  Verification (`/verify-changes`) runs on ALL code changes regardless
  of the `auto` flag — `auto` controls autonomous landing (push/merge),
  not whether to verify. Mirrors the broad-autonomy convention in
  `/run-plan`, `/fix-issues`.
- **every SCHEDULE** (optional) — self-schedule recurring runs via cron:
  - Accepts intervals: `4h`, `2h`, `30m`, `12h`
  - Accepts time-of-day: `day at 9am`, `day at 14:00`, `weekday at 9am`
  - Without `now`: schedules only, does NOT run immediately
  - With `now`: schedules AND runs immediately
  - Each run re-registers the cron (self-perpetuating)
  - Cron is session-scoped — dies when the session dies
- **now** (optional) — run immediately. When combined with `every`, runs
  immediately AND schedules. Without `every`, `now` is the default behavior.
- **--force** (optional) — bypass the triage redirect (Phase 0a). It does
  NOT bypass the Phase 0b review: a review REJECT still HALTS regardless of
  `--force`. To skip the review entirely, use `--rounds 0`; `--force --rounds 0`
  does both (past the size guard AND no review). Persists into the cron prompt
  verbatim when used with `every`.
- **--no-claim** (optional) — claim absolutely NOTHING; treat every `#N` in
  the description as a mere mention. This now suppresses ALL claims (#1032),
  not just the stray-ref warning: the pre-flight forces `ISSUE_NUMS` empty so
  the mode files acquire no claims AND skips the stray-`#N` check (#959). The
  stray-`#N` check normally STOPS when the description references an issue
  currently held in-flight by a foreign pipeline (to prevent duplicating its
  work — the closed-PR-#888-vs-landed-#901 footgun), and warns on any other
  stray `#N`. Pass `--no-claim` when you do NOT want /do to claim, halt, or
  warn on any referenced issue — including claim-positioned ones. Concretely
  `Fix #5 / #6 --no-claim` acquires neither #5 nor #6: under `--no-claim`
  even a leading `#N` or `Fix #N …` is a pure mention.
- **--rounds N** (optional) — max review/refine cycles (default 1; `0` skips
  review with stderr WARN).
- **stop** — cancel `/do` cron(s). Bare `/do stop` → all crons.
  With query `/do stop Check docs` → targets matching cron.
- **next** — check next fire time. Bare → all. With query → targeted.

**Detection:** If `$ARGUMENTS` starts with a quoted string (`"..."`),
the quoted text is the description — skip meta-command detection entirely.
This lets users escape edge cases like `/do "Now fix the tooltip bug"`.

Otherwise, check the **first word** of `$ARGUMENTS`:
- `stop [query]` — meta-command: cancel crons. Bare → all. With query → targeted.
- `next [query]` — meta-command: show fire times. Bare → all. With query → targeted.
- `now [query]` — meta-command: trigger immediately. Bare → all/ask. With query → targeted.

Meta-commands (`stop`, `next`, `now`) bypass Phase 0a triage and Phase 0b review entirely. They are administrative — there is no description to evaluate.

If the first word is NOT a meta-command, it's a regular task. Parse
trailing flags from the END backward:
- `worktree` — recognized at the end (landing flag)
- `direct` — recognized at the end (landing flag)
- `pr` — recognized at the end (landing flag; use extended pattern with `.!?` punctuation, since task descriptions are prose-like and "pr" may appear as "PR." at end of sentence)
- `auto` — recognized anywhere (case-insensitive positional token; broad-autonomy opt-in across all 3 modes. Mirrors /run-plan, /fix-issues.)
- `every <schedule>` — recognized at the end (e.g., `every 4h`, `every day at 9am`)
- `now` — recognized at the end (only meaningful with `every`: run now AND schedule)

**Landing-flag detection** — resolves to `LANDING_MODE ∈ {pr, worktree, direct}`.
Explicit flag wins; otherwise fall back to `execution.landing` in
`.claude/zskills-config.json`; otherwise default `direct`. See Phase 1.5
for the full resolution block.

Everything before the trailing flags is the task description.

This means:
- `/do stop` — stop all `/do` crons
- `/do stop Check docs` — stop the "Check docs" cron
- `/do next` — show all fire times
- `/do next Check docs` — show fire time for "Check docs"
- `/do now` — trigger (if one) or ask (if multiple)
- `/do now Check docs` — trigger the "Check docs" cron
- `/do Push the latest changes` — description only, no flags
- `/do Update the presentation auto` — description + auto (direct + verify + push)
- `/do Fix the tooltip bug worktree` — worktree + verify (no auto-land)
- `/do Fix the tooltip bug worktree auto` — worktree + verify + cherry-pick + push
- `/do Check docs every day at 9am` — schedule "Check docs" daily
- `/do Add dark mode. pr` — description + pr flag (PR mode)
- `/do Add dark mode pr auto` — PR mode + auto-merge opt-in

Examples:
- `/do Add example models for Integrator and Derivative blocks`
- `/do Sort the screenshots in session-sequence-snapshots`
- `/do Refactor color constants in main.css worktree`
- `/do Update the presentation with Phase 3 results auto`
- `/do Make sure docs are up to date every day at 9am`
- `/do Check for broken links in examples every 12h now`
- `/do Add dark mode to editor pr`
- `/do next` — all scheduled tasks
- `/do next Check docs` — specific task
- `/do stop` — cancel all
- `/do stop Check docs` — cancel specific task

## Meta-Commands: stop / next / now

These commands query or control `/do` crons. They work in two modes:

- **Bare** (`/do stop`, `/do next`, `/do now`) — applies to ALL `/do` crons
- **Targeted** (`/do stop Check docs`, `/do next Check docs`) — applies to the matching cron

### Cron Matching (for targeted commands)

When a description is present with `stop`/`next`/`now`, find the matching
cron by comparing the description against all `/do` cron prompts:

1. `CronList` → find all whose prompt starts with `Run /do`
2. Extract each cron's task description (strip `Run /do ` prefix and
   trailing flags)
3. **Fuzzy match:** check if the user's description words appear in the
   cron's description (case-insensitive, order-independent). E.g.,
   "Check docs" matches "Make sure docs are up to date" because both
   key words overlap. The user won't have tons of similar `/do` crons,
   so loose matching is fine.
4. **One match** → act on it. **Multiple matches** → list them, ask
   which one. **No matches** → report "no matching /do cron found."

### Now

1. `CronList` → find `/do` crons (all, or matching if description given)
2. **One cron:** extract prompt, **run immediately.** Cron stays active.
3. **Multiple (bare only):** list them, ask which to trigger.
4. **None:** report `No active /do cron to trigger.` and **exit.**

### Next

1. `CronList` → find `/do` crons (all, or matching if description given)
2. For each, parse the cron expression and compute the next fire time.
   Use `TZ="${TIMEZONE:-UTC}" date` for the timezone. Show both relative
   and absolute:
   > Active /do crons:
   > 1. ~14h 47m (~9:03 AM ET tomorrow, cron XXXX)
   >    Prompt: Run /do Make sure docs are up to date every day at 9am now
   > 2. ~3h 12m (~8:15 PM ET, cron YYYY)
   >    Prompt: Run /do Check broken links every 4h now
3. **None:** `No active /do cron in this session.`
4. **Exit.**

### Stop

1. `CronList` → find `/do` crons (all, or matching if description given)
2. **Bare with one cron:** delete it. Report what was cancelled.
3. **Bare with multiple:** list them, ask which to cancel (or "all").
4. **Targeted:** delete the matched cron. Report what was cancelled.
5. **None:** report "no active /do cron found."
6. **Exit.**

## Pre-flight — Flag pre-parse (runs before Phase 0a/0b/0c)

Phase 0a (triage) and Phase 0b (review) need to know `--force` and
`--rounds N`; Phase 0c (cron registration) needs them so the cron prompt
template can include them verbatim. Phase 2 (PR mode) needs to know the
positional `auto` token so it can pass `--auto` to `/land-pr`. Phase 1.5's
argument parser runs AFTER Phase 0c today, so this pre-parse runs first —
at the very top of the skill, before Phase 0a. This pre-parse is
non-destructive: it sets `FORCE`, `ROUNDS`, and `AUTO_FLAG` shell
variables but does NOT mutate `$ARGUMENTS` (Phase 1.5's parser remains
source of truth for the canonical strip).

```bash
# Pre-flight (runs before Phase 0a/0b/0c): read --force and --rounds N out
# of $ARGUMENTS so Phase 0c's cron prompt template can include them, and
# Phase 0a/0b can branch on them. Does not mutate $ARGUMENTS.

# Entry-point unset guard (WI 2a.3 test seam) — keep first so any code path
# that later reads _ZSKILLS_TEST_* env vars (triage, review, cron-prompt
# construction) sees the production-cleared values when the harness flag
# is absent.
if [ "${_ZSKILLS_TEST_HARNESS:-}" != "1" ]; then
  unset _ZSKILLS_TEST_TRIAGE_VERDICT _ZSKILLS_TEST_REVIEW_VERDICT
fi

FORCE=0
if [[ "$ARGUMENTS" =~ (^|[[:space:]])--force($|[[:space:]]) ]]; then
  FORCE=1
fi
# Issue #959: `--no-claim` opt-out. When present, the stray-`#N` pre-flight
# (the #907 loop below) treats every bare `#N` as a mere mention — it
# suppresses BOTH the new foreign-held STOP and the #907 warn. Use it when a
# /do legitimately references an issue it is NOT working (e.g. "fix tooltip,
# related to #340"). Claim-positioned `#N` (in ISSUE_NUMS) are independent of
# this flag — they still go through the mode files' A5.5 acquire-or-decline.
NO_CLAIM=0
if [[ "$ARGUMENTS" =~ (^|[[:space:]])--no-claim($|[[:space:]]) ]]; then
  NO_CLAIM=1
fi
# Issue #297: positional `auto` token (case-insensitive, anywhere in the
# args) opts /do pr into /land-pr's auto-merge path. Mirrors
# /run-plan, /fix-issues. Pre-parsed here so Phase 1.5's strip chain and
# Phase 2 mode dispatch both see AUTO_FLAG.
# AUTO_FLAG is consumed by:
#   - modes/pr.md to inject --auto into LAND_ARGS for /land-pr (PR mode)
#   - Phase 4 (Land) as the gate to push/cherry-pick+push (direct/worktree modes)
# Note: Phase 3 dispatches /verify-changes unconditionally for code
# changes (issue #713) — AUTO_FLAG no longer gates verification.
AUTO_FLAG=0
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[aA][uU][tT][oO]($|[[:space:]]) ]]; then
  AUTO_FLAG=1
fi
# Issue-number parse (claim-work-item Phase 2 / W2.2). Collect ALL `#N`
# references in the description into the ISSUE_NUMS array so the mode
# files can fan-out the claim acquire across every closed issue. The
# leading match is ANCHORED to the start of the description (optionally
# preceded by a close-keyword: close/closes/closed/fix/fixes/fixed/
# resolve/resolves/resolved, case-insensitive; an optional leading
# double-quote is tolerated for /do's quoted-description carve-out
# `/do "Fix #N ..."`). Subsequent matches recognize TWO boundary
# classes:
#   - STRONG separators (`/`, `+`, `&`) — bare `#N` allowed because
#     these don't naturally appear in English prose before a `#`
#     reference. Canonical patterns: "fix #N + #M", "Closes #N / Closes
#     #M", "fix #N & #M".
#   - WEAK separators (`,`, `;`, ` and `, ` or `) — require an explicit
#     close-keyword between the separator and `#N`. This is what blocks
#     "Closes #832, see also #999" from accidentally claiming #999
#     (comma is a normal prose punctuator, so bare `#N` after it would
#     over-capture) while still accepting "Closes #832, Closes #833".
# After the close-keyword (in any of leading/strong/weak passes), an
# optional `issue[s]?:?` filler token is tolerated between the keyword
# and `#N` (#920): "Fix issue #906", "fixes issues #906", "Resolves
# issue: #906" all parse. The token MUST be adjacent to `#N` — a word
# between `issue` and `#N` (e.g. "Fix issue ticketing for #906") breaks
# the adjacency and no capture occurs, preserving #863's
# strong-vs-weak separator discipline.
# When no issue reference is in scope (the common /do case) ISSUE_NUMS
# stays empty and the mode files claim nothing. ISSUE_NUM is kept as a
# back-compat scalar (= ISSUE_NUMS[0] when non-empty, else empty).
# claim-issue.sh rejects non-numeric input with exit 2; the `[0-9]+`
# capture guarantees a bare integer.
ISSUE_NUMS=()
_DO_ISSUE_KW='([cC][lL][oO][sS][eE][sSdD]?|[fF][iI][xX]([eE][sSdD])?|[rR][eE][sS][oO][lL][vV][eE][sSdD]?)'
_DO_ISSUE_FILLER='([iI][sS][sS][uU][eE][sS]?:?[[:space:]]+)?'
# Leading anchored match (optional close-keyword, optional leading quote,
# optional `issue[s]?:?` filler between kw and `#N`). BASH_REMATCH groups
# (kw branch): 1=kw outer, 2=kw inner, 3=optional filler, 4=digit capture.
# `_DO_CHAIN_SUFFIX` records the description text IMMEDIATELY AFTER the
# leading ref, and `_DO_HAS_ANCHOR` records whether the leading match
# populated ISSUE_NUMS. The strong-separator loop below anchors on this
# leading ref: a strong-separator `#N` is captured ONLY when it is
# contiguously chained to the already-claimed leading ref (#1032). Without
# a leading anchor (description starts mid-prose, no claim-positioned
# leading `#N`), the chain captures nothing — so a slash-separated citation
# like `supersedes #999/#1004` or a bare-cited `#960/#967` claims nothing.
_DO_HAS_ANCHOR=0
_DO_CHAIN_SUFFIX=""
if [[ "$ARGUMENTS" =~ ^[[:space:]]*\"?${_DO_ISSUE_KW}[[:space:]]+${_DO_ISSUE_FILLER}#([0-9]+) ]]; then
  ISSUE_NUMS+=("${BASH_REMATCH[4]}")
  _DO_HAS_ANCHOR=1
  _DO_CHAIN_SUFFIX="${ARGUMENTS#*"${BASH_REMATCH[0]}"}"
elif [[ "$ARGUMENTS" =~ ^[[:space:]]*\"?#([0-9]+) ]]; then
  ISSUE_NUMS+=("${BASH_REMATCH[1]}")
  _DO_HAS_ANCHOR=1
  _DO_CHAIN_SUFFIX="${ARGUMENTS#*"${BASH_REMATCH[0]}"}"
fi
# Subsequent strong-separator matches (`/`, `+`, `&`): bare `#N` OK; if
# the keyword is present, the optional `issue[s]?:?` filler is also
# permitted between the kw and `#N`. The regex is `^`-ANCHORED and runs
# against `_DO_CHAIN_SUFFIX` (the text right after the previous captured
# ref), so it consumes ONLY a contiguous `(<sep> #N)+` chain starting
# immediately after the leading claimed ref — arbitrary prose between the
# anchor and a `<sep> #N` breaks the chain and stops the loop (#1032).
# When there is no leading anchor, the loop body never runs. BASH_REMATCH
# groups: 1=outer kw+filler wrapper, 2=kw outer, 3=kw inner, 4=optional
# filler, 5=digit capture.
if [ "$_DO_HAS_ANCHOR" -eq 1 ]; then
  while [[ "$_DO_CHAIN_SUFFIX" =~ ^[[:space:]]*[/+\&][[:space:]]*(${_DO_ISSUE_KW}[[:space:]]+${_DO_ISSUE_FILLER})?#([0-9]+) ]]; do
    ISSUE_NUMS+=("${BASH_REMATCH[5]}")
    _DO_CHAIN_SUFFIX="${_DO_CHAIN_SUFFIX#*"${BASH_REMATCH[0]}"}"
  done
fi
unset _DO_HAS_ANCHOR _DO_CHAIN_SUFFIX
# Subsequent weak-separator matches (`,`, `;`, ` and `, ` or `): require
# close-keyword before `#N` so prose like "Closes #N, see also #M" doesn't
# over-capture #M. Optional `issue[s]?:?` filler is allowed between kw and
# `#N`. BASH_REMATCH groups: 1=outer separator, 2=and/or word, 3=kw outer,
# 4=kw inner, 5=optional filler, 6=digit capture.
_DO_REMAINING="$ARGUMENTS"
while [[ "$_DO_REMAINING" =~ ([[:space:]]*[,\;][[:space:]]*|[[:space:]](and|or|AND|OR|And|Or)[[:space:]]+)${_DO_ISSUE_KW}[[:space:]]+${_DO_ISSUE_FILLER}#([0-9]+) ]]; do
  ISSUE_NUMS+=("${BASH_REMATCH[6]}")
  _DO_REMAINING="${_DO_REMAINING#*"${BASH_REMATCH[0]}"}"
done
# Dedupe preserving first-seen order (acquire is order-dependent for the
# partial-rollback contract; releases are idempotent per claim-issue.sh).
declare -A _DO_SEEN=()
_DO_UNIQUE=()
for _n in "${ISSUE_NUMS[@]:-}"; do
  [ -z "$_n" ] && continue
  if [ -z "${_DO_SEEN[$_n]:-}" ]; then _DO_UNIQUE+=("$_n"); _DO_SEEN[$_n]=1; fi
done
ISSUE_NUMS=("${_DO_UNIQUE[@]}")
unset _DO_SEEN _DO_UNIQUE _DO_REMAINING _DO_ISSUE_KW _DO_ISSUE_FILLER _n
# Back-compat scalar (= first claimed issue, or empty when none). Mode
# files still reference $ISSUE_NUM in skip-empty guards; new fan-out code
# iterates "${ISSUE_NUMS[@]}".
ISSUE_NUM="${ISSUE_NUMS[0]:-}"
# `--no-claim` (#1032) means "claim absolutely nothing." Reset the populated
# ISSUE_NUMS (and the back-compat scalar) to empty so the mode files' claim
# fan-out acquires NOTHING — even for claim-positioned refs like `Fix #5 / #6`.
# This is the deterministic escape hatch: any future parser edge case can be
# neutralized with --no-claim. The stray-ref check below is still guarded by
# the same NO_CLAIM flag, so an emptied ISSUE_NUMS does not cause a
# contradictory STOP/warn (the whole stray-ref block is skipped when
# NO_CLAIM=1).
if [ "$NO_CLAIM" -eq 1 ]; then
  ISSUE_NUMS=()
  ISSUE_NUM=""
fi
# Unclaimed-reference check (#907 warn + #959 foreign-held STOP). If the
# description contains a `#N` token that the claim-position rules above did
# NOT capture into ISSUE_NUMS, the reference is real but UN-claimed by this
# /do run. A silent no-claim is the footgun that let `/do Build … for #877`
# run without claiming #877: a parallel /fix-issues cron then picked up the
# unclaimed issue and duplicated the work (closed PR #888 vs landed #901).
#
# Two-tier handling per stray (non-ISSUE_NUMS) `#N` (#959):
#   1. READ-ONLY foreign-held check. If issue N currently has a LIVE claim
#      held by a DIFFERENT pipeline, STOP (clean exit 0 — decline, not an
#      error). #907's warn fails UNSAFE in autonomous use (an agent reads
#      the warn and proceeds anyway, re-creating the #877 duplication); the
#      STOP fails SAFE and is recoverable via `--no-claim`. We DO NOT acquire
#      on stray refs (that would spuriously claim "see #340" mentions — the
#      over-capture the conservative ISSUE_NUMS parser deliberately avoids).
#   2. Not held (or no claim.json) → keep the #907 warn and proceed.
#
# Foreign-vs-self is decided by READING `.zskills/claims/issue-N/claim.json`
# and comparing its `pipeline_id` to THIS run's pipeline_id — exactly the
# pattern hooks/block-fix-issue-unclaimed.sh uses. We do NOT use
# filter-in-flight-issue-claims.sh alone: it drops the caller's OWN pipeline
# claims too and cannot distinguish foreign from self, which would wrongly
# stop on self-re-entry. Fail-OPEN discipline mirrors
# block-fix-issue-unclaimed.sh: a missing/malformed claim.json, or a missing
# pipeline_id, is treated as "not held" → warn-and-proceed, never a false
# STOP. (In practice a stray ref is by definition never acquired by THIS /do
# run, so any live claim on it is foreign; the self-exclusion below is the
# belt-and-suspenders that keeps a hypothetical self-claim from stopping us.)
#
# Accepted residual (intentional, safe-direction): a false-STOP fires ONLY
# when a /do mentions an issue that is in flight RIGHT NOW but isn't actually
# being worked (`fix tooltip, related to #340` while #340 is live). Recover
# with `--no-claim`. Mentions of closed/old issues never trigger (no live
# claim). This is the irreducible cost of "issues optional + can't tell
# work-from-mention out of free text" — the failure mode relocates from
# "fails → duplicates silently" to "fails → halts with a clear message".
#
# `--no-claim` (NO_CLAIM=1, parsed in the pre-parse above) suppresses BOTH
# the STOP and the warn — every bare `#N` is then a pure mention. It ALSO
# forces ISSUE_NUMS empty above (#1032), so claim-positioned refs are not
# acquired either; --no-claim means "claim absolutely nothing."
#
# Resolve MAIN_ROOT the same way block-fix-issue-unclaimed.sh does:
# `git rev-parse --git-common-dir` parent, falling back to
# ${CLAUDE_PROJECT_DIR:-$PWD}. This is correct from a worktree too (the
# claims live under the MAIN repo's .zskills/).
# Resolve a WORKING Python 3 (probe-RUN each candidate: on Windows
# `command -v python3` finds a non-executable MS Store stub). Honors
# ZSKILLS_PYTHON; empty if none works.
zskills_resolve_python() {
  local cand
  for cand in "${ZSKILLS_PYTHON:-}" python3 python; do
    [ -n "$cand" ] || continue
    command -v "$cand" >/dev/null 2>&1 || continue
    if "$cand" -c 'import sys; sys.exit(0 if sys.version_info[0]==3 else 1)' >/dev/null 2>&1; then
      command -v "$cand"; return 0
    fi
  done
  return 1
}
if [ "$NO_CLAIM" -ne 1 ]; then
  _DO_MAIN_ROOT=""
  if _DO_COMMON_DIR=$(git rev-parse --git-common-dir 2>/dev/null) && [ -n "$_DO_COMMON_DIR" ]; then
    if _DO_RESOLVED=$(cd "$_DO_COMMON_DIR/.." 2>/dev/null && pwd); then
      _DO_MAIN_ROOT="$_DO_RESOLVED"
    fi
  fi
  [ -z "$_DO_MAIN_ROOT" ] && _DO_MAIN_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
  _DO_PYTHON="$(zskills_resolve_python || true)"
  # This run's pipeline_id, if already known (mode files set PIPELINE_ID as
  # `do.<task-slug>`). In the pre-flight it is typically unset; an empty
  # value can never equal a real stored pipeline_id, so every live claim on a
  # stray ref reads as foreign — which is exactly right (stray refs are never
  # self-claimed). When set, it provides the explicit self-exclusion.
  _DO_SELF_PIPELINE_ID="${PIPELINE_ID:-}"
  _DO_WARN_REMAINING="$ARGUMENTS"
  while [[ "$_DO_WARN_REMAINING" =~ \#([0-9]+) ]]; do
    _DO_REF="${BASH_REMATCH[1]}"
    _DO_WARN_REMAINING="${_DO_WARN_REMAINING#*"${BASH_REMATCH[0]}"}"
    _DO_CLAIMED=0
    for _n in "${ISSUE_NUMS[@]:-}"; do
      [ "$_n" = "$_DO_REF" ] && { _DO_CLAIMED=1; break; }
    done
    [ "$_DO_CLAIMED" -eq 1 ] && continue
    # Stray ref — read its claim.json (if any) and decide foreign vs not-held.
    _DO_CLAIM_FILE="${_DO_MAIN_ROOT}/.zskills/claims/issue-${_DO_REF}/claim.json"
    _DO_STORED_PID=""
    if [ -f "$_DO_CLAIM_FILE" ] && [ -n "$_DO_PYTHON" ]; then
      _DO_STORED_PID=$("$_DO_PYTHON" - "$_DO_CLAIM_FILE" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        sys.stdout.write(json.load(f).get("pipeline_id", "") or "")
except Exception:
    pass
PY
)
    fi
    if [ -n "$_DO_STORED_PID" ] && [ "$_DO_STORED_PID" != "$_DO_SELF_PIPELINE_ID" ]; then
      # Foreign-held in-flight → STOP (decline, clean exit 0).
      echo "STOP: /do: description references #${_DO_REF}, which is currently held by a foreign pipeline (claim pipeline_id: ${_DO_STORED_PID}, claim at ${_DO_CLAIM_FILE})." >&2
      echo "      Another pipeline is already working #${_DO_REF}; proceeding would duplicate its work (the exact failure of closed PR #888 vs landed #901)." >&2
      echo "      If you are ONLY referencing #${_DO_REF} and not working it, re-run with --no-claim to treat the reference as a mention and skip this check." >&2
      exit 0
    fi
    # Not held (no claim.json / malformed / self) → #907 warn + proceed.
    echo "WARN: /do: description references #${_DO_REF} but it is not in claim position — NO claim was acquired for it. Prefix the description with the issue number (e.g. \"#${_DO_REF} …\" or \"Fix #${_DO_REF} …\") to claim it and prevent a parallel pipeline from duplicating the work. If you are only referencing #${_DO_REF} (not working it), pass --no-claim to silence this." >&2
  done
  unset _DO_WARN_REMAINING _DO_REF _DO_CLAIMED _n _DO_MAIN_ROOT _DO_COMMON_DIR _DO_RESOLVED _DO_PYTHON _DO_SELF_PIPELINE_ID _DO_CLAIM_FILE _DO_STORED_PID
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

Validation: `fix tooltip --force --rounds 3 pr` strips to `fix tooltip` after
the full chain. `fix the bug --rounds in production` keeps the full
description (no strip), ROUNDS stays at 1.

## Phase 0a — Triage

Before any cron registration, fresh-agent review, or task work, the model
runs a triage gate to decide whether `/do` is the right skill for this
description. **Phase 0a runs BEFORE Phase 0c (cron registration).** A
REDIRECT path exits before any `CronCreate` call, so a redirected `/do`
leaves no cron behind. Phase 0c cannot run on a redirected invocation.

This is a **model-layer instruction**, not a bash block. Triage runs
BEFORE Phase 0b (review) and BEFORE Phase 0c (cron registration) — so a
redirect leaves no cron, no marker, no branch, no commits. /do does NOT
write a tracking marker (no new tracking for /do) — there is nothing to
clean up on redirect.

**Test seam (production behavior unaffected).** When
`_ZSKILLS_TEST_HARNESS=1` is set, the model MUST skip the triage Agent
dispatch and instead use the value of `_ZSKILLS_TEST_TRIAGE_VERDICT` as
the verdict. Production invocations (where the harness flag is absent and
the entry-point unset guard at the pre-flight has already cleared the
test vars) always run the full Agent path. Recognized stub values:
`PROCEED`, `REDIRECT:/draft-plan:reason`, `REDIRECT:/run-plan:reason`,
`REDIRECT:ask-user:reason`.

The model judges `$DESCRIPTION` against this rubric — qualitative,
observable from description text, no LOC counting. /do always works in a
fresh worktree (PR mode) or main (direct/worktree mode), so the
file-enumeration rule applies uniformly (no MODE carve-out needed).

| Signal | Verdict |
|--------|---------|
| Description scopes to one concept | PROCEED |
| Description enumerates many distinct files (roughly ≥8–10) OR sprawls across clearly unrelated concerns | REDIRECT → `/draft-plan` |
| Verbs include any of: `add feature`, `redesign`, `rewrite`, `refactor across` | REDIRECT → `/draft-plan` |
| `and` connects unrelated areas (e.g. "fix nav and update copy") | REDIRECT → `/draft-plan` |
| Vague verbs alone: `improve`, `fix it`, `update`, `clean up` (no concrete object) | REDIRECT → ask user |
| References an existing plan file under `$ZSKILLS_PLANS_DIR` | REDIRECT → `/run-plan` |

The file-enumeration row is a **model-layer judgment, not a hard count.**
~8–10 is a calibration anchor, not a threshold to mechanically tally:
- Judge **LOGICAL files**, not raw count. A source file and its mirror, or
  a generated file and its source, count as ONE logical file (editing
  `hooks/X.sh` plus its `.claude/hooks/X.sh` mirror is ONE logical file).
  Generated-doc doubling does not inflate.
- A **wide-but-settled mechanical change** — one concept, many files (e.g. a
  bulk rename, a single find-replace across the tree) — stays `/do`. Width is
  not depth (CLAUDE.md: "heavy is staging or design depth, not breadth").
- The row only fires when the description **explicitly enumerates** a sprawl
  of distinct files or unrelated concerns.

**Division of labor.** The file-enumeration row is a coarse backstop for
**sprawling, explicitly-enumerated** descriptions — it catches "edit A.js,
B.css, C.html, D.json, … and rework the build" before any work starts. The
real depth/concept gate is **Phase 0b's acceptance-bullet ceiling** (>4
Acceptance bullets → REVISE), which judges the composed inline plan rather
than the raw description text. Issue-numbered descriptions (`Fix #N`) name no
files, so this triage row never fires on them — that is expected; Phase 0b's
inline-plan review is what catches an over-scoped `Fix #N`.

**Worked examples (calibrate the model's PROCEED/REDIRECT calls):**

| Example invocation | Verdict | Why |
|--------------------|---------|-----|
| `/do Fix README typo` | PROCEED | one concept, one likely file |
| `/do Sort the screenshots in session-sequence-snapshots` | PROCEED | one concrete object |
| `/do Update the presentation with Phase 3 results auto` | PROCEED | concrete verb + object |
| `/do Rename `oldHelper` to `newHelper` across the codebase` | PROCEED | wide-but-settled mechanical change — one concept, many files; width is not depth |
| `/do Bump the copyright year in all source headers` | PROCEED | one concept applied uniformly; logical-file count is 1 concept regardless of raw file count |
| `/do Rework auth.js, session.js, db/pool.js, routes/login.js, the CSS, the config, and the build script` | REDIRECT → /draft-plan | enumerates ~7+ distinct files across unrelated concerns — sprawling scope |
| `/do add dark mode and refactor the worker pool` | REDIRECT → /draft-plan | "and" connects unrelated areas |
| `/do improve` | REDIRECT → ask user | vague verb, no object |
| `/do Fix #853 — auto-route completed plans` | PROCEED | issue-numbered descriptions claim the issue(s) via ISSUE_NUMS and proceed |

Output one of:

- `PROCEED` — print `Triage: proceeding with /do (<one-line reason>).` Continue to Phase 0b.
- `REDIRECT(target=<skill>, reason=<text>)` — see redirect handling.

**Per-target redirect message templates** (must be exact-text-grep-able).
Each message is **two physical lines** in the printed output (the
linebreak is a real newline, not the literal `\n` characters):

| target | Line 1 | Line 2 |
|--------|--------|--------|
| `/draft-plan` | `Triage: redirecting to /draft-plan. Reason: <reason>` | `This task spans more than one concept; /draft-plan will research and decompose it. Run \`/draft-plan <description>\` instead, or re-invoke with --force to bypass.` |
| `/run-plan` | `Triage: redirecting to /run-plan. Reason: <reason>` | `This task references an existing plan file. Run \`/run-plan <plan-path>\` to execute it, or re-invoke with --force to bypass.` |
| ask-user | `Triage: cannot proceed — description is too vague to act on. Reason: <reason>` | `Re-invoke /do with a concrete description (verb + object + which file/area). --force will not help — vague descriptions cannot be planned.` |

The model implements these as a `printf 'line1\nline2\n' "$REASON"` so
both lines are emitted to stdout and both are independently greppable
from a test fixture.

On REDIRECT and `$FORCE -eq 0`: print the per-target message (both
lines), then `exit 0`. **No marker is written** (no tracking for /do).
No cron. No branch.

On REDIRECT and `$FORCE -eq 1`: print
`Triage: REDIRECT(<target>) overridden by --force; proceeding.`
Continue to Phase 0b.

## Phase 0b — Inline plan + fresh-agent review

After Phase 0a, before Phase 0c (cron registration), the model composes a
short inline plan and dispatches one fresh Agent to review it. This phase
runs BEFORE Phase 0c so a REJECT exits before any `CronCreate` call.

**Skip when `--rounds 0`.** If `$ROUNDS -eq 0`: print to stderr
`WARN: --rounds 0 skips fresh-agent plan review (legacy opt-in).` and
skip review entirely. Continue to Phase 0c.

**Inline plan composition (model-layer).** This is a **model-layer
instruction**, not a bash block. After triage returns PROCEED (or after
`--force` overrides a REDIRECT), the model composes a short inline plan
held in `INLINE_PLAN`. `INLINE_PLAN` is a logical placeholder for text
the model composes in its response. When the reviewer Agent is dispatched,
the model copies the `INLINE_PLAN` text **verbatim** into the Agent prompt
as the `INLINE PLAN ...` section — there is no file read or shell-variable
interpolation; this is a model-to-prompt substitution.

```text
### /do inline plan
**Description:** <DESCRIPTION>
**Mode:** <LANDING_MODE> (or "as inferred from description; will be resolved in Phase 1.5")
**Files (expected):** <comma-separated list, OR "as inferred from description; may be refined during Phase 1 research">
**Approach:** <2-4 sentences>
**Acceptance:** <2-4 bullets>
```

Constraints:

- ≤60 lines total.
- "Files (expected)" is OPTIONAL for /do — the worktree may not exist yet
  for PR mode; the agent will discover files in Phase 1 research. When
  unsure, set to `as inferred from description; may be refined during
  Phase 1 research`.
- The model-authored fields **Approach** and **Acceptance** MUST NOT
  contain the literals for other skills (`/draft-plan`, `/run-plan`,
  `/fix-issues`) — using these in model-authored prose would muddle the
  redirect-message guards.
- The **Description** field is verbatim user input and is exempt — a
  user description that mentions another skill name is the user's
  prerogative.
- Early-stage review judges PLAN STRUCTURE, not file enumeration accuracy.

**Fresh-agent plan review (model-layer).** This is a **model-layer
instruction**, not a bash block.

**Test seam (production behavior unaffected).** When
`_ZSKILLS_TEST_HARNESS=1` is set, the model MUST skip the reviewer Agent
dispatch and instead use the value of `_ZSKILLS_TEST_REVIEW_VERDICT` as
the verdict (one of `APPROVE`, `REVISE: reason`, `REJECT: reason`).
Production invocations always run the full Agent path.

Otherwise dispatch ONE Agent (no model hint — inherit parent) with this
prompt:

```text
You are the REVIEWER agent for /do's pre-execution plan review.

DESCRIPTION the user provided:
[DESCRIPTION]

LANDING_MODE: [LANDING_MODE]

INLINE PLAN the model proposes to execute:
[INLINE_PLAN verbatim]

Your job: judge whether the inline plan, when executed, will produce a
change set that faithfully addresses DESCRIPTION without obvious
omissions or out-of-scope work. Judge PLAN STRUCTURE, not file
enumeration accuracy (file lists may be best-effort at this stage).

OBSERVABLE-SIGNAL RULE (mandatory): count the **Acceptance** bullets in
the inline plan. If >4 Acceptance bullets are present, you MUST return
`VERDICT: REVISE -- too many concepts; consider /draft-plan` regardless
of whether each bullet individually looks reasonable. This is a hard
auto-REVISE — not a judgment call. The Acceptance-bullet ceiling is the
concrete observable that distinguishes "task fits /do" from "task
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
You are the REVIEWER agent for /do's pre-execution plan review (round [N]).

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

On APPROVE: print verdict + justification, continue to Phase 0c.

On REJECT: print verdict, `exit 0` — **regardless of `$FORCE`.** A review
REJECT always HALTS; `--force` only bypasses the Phase 0a triage redirect, not
the Phase 0b review veto (issue #1118). **No marker is written** (no tracking
for /do). No worktree, no commits, no cron. To skip the review entirely, use
`--rounds 0` (which short-circuits this phase before it runs); `--force
--rounds 0` bypasses both the triage redirect and the review.

Orthogonality with `/verify-changes` (Phase 3): pre-review judges PLAN; `/verify-changes` judges DIFF. Both run when both apply: `--rounds > 0` triggers this pre-review (any landing mode); code changes in `worktree`/`direct` mode trigger /verify-changes unconditionally after execution (issue #713 — `auto` controls landing, not verification). PR mode (Path A) ALSO runs the same DIFF verification gate before landing: it invokes /verify-changes (Layer-3 validated, STOP-on-fail) at its own Step A6.5 (`skills/do/modes/pr.md`) BEFORE dispatching /land-pr — closing the gap (issue #1014) where /do pr was the only PR-mode caller with no local verification gate and relied solely on CI. CI via /land-pr is the backstop, not the gate.

## Phase 0c — Schedule (if `every` is present)

If `$ARGUMENTS` contains `every <schedule>`:

1. **Parse the schedule** — convert to a cron expression.

   **For interval-based schedules** (`4h`, `12h`): use the CURRENT minute
   as the offset so the first fire is a full interval from now. Check with
   `date +%M`:
   - `4h` at minute 9 → `9 */4 * * *`

   **For time-of-day schedules**: offset round minutes by a few:
   - `day at 9am` → `3 9 * * *`
   - `weekday at 9am` → `3 9 * * 1-5`

2. **Deduplicate** — `CronList` and check for existing `/do` crons.
   Extract the task description from each cron's prompt by stripping
   `Run /do ` prefix and trailing flags (`every`, `now`, `worktree`, `auto`).
   - If an existing cron's extracted description **exactly matches** (case-
     insensitive) the new task's description, replace it (`CronDelete` +
     recreate). This is a re-registration of the same task.
   - Otherwise, keep it — the user has multiple crons for different tasks.
   - During an **autonomous cron fire** (the invocation itself came from a
     cron), never ask the user — default to keeping both. During an
     **interactive invocation**, if descriptions are similar but not exact,
     list existing crons and ask: "Replace this one, or keep both?"

3. **Construct `TASK_DESCRIPTION_FOR_CRON`** — strip every/now/--force/--rounds
   tokens from `$ARGUMENTS` but PRESERVE pr/worktree/direct/auto tokens (these
   need to round-trip into the cron prompt so each cron fire reproduces the
   user's landing-mode and autonomy intent).

   Quoted-description carve-out: /do supports a leading quoted description
   (see "Detection" above). When `$ARGUMENTS` begins with `"..."`, peel the
   quoted segment off, strip-chain only the unquoted suffix, then reassemble.
   This prevents `/do "fix --force usage in scripts" --force every 4h` from
   corrupting the user-prose `--force` substring inside the quotes.

   ```bash
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
     | sed -E 's/(^|[[:space:]])--no-claim($|[[:space:]])/ /' \
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

   The time-of-day pattern (`every day at 9am`) MUST come before the
   generic interval pattern (`every 4h`) — generic would otherwise capture
   "day" as the interval value and leave "at 9am" as orphan tokens. The
   `--rounds` strip only matches numeric N (consistent with WI 2a.0's
   greedy-fallthrough rule); a non-numeric `--rounds <prose>` stays in
   `TASK_DESCRIPTION_FOR_CRON` and round-trips into the cron prompt as user
   prose, where it will again no-op-fall-through on each fire.

   **Quoted-description known limit.** A quoted description containing a
   literal `every <token>` substring (e.g., `/do "audit every PR" every 4h`)
   is also protected — only the unquoted suffix is strip-chained. A
   multi-segment quoted form (`/do "fix" --force "every 4h"`) is not
   supported; the regex matches only the leading quote pair.

4. **Construct the cron prompt** incrementally so optional flags only appear
   when set. `FORCE` and `ROUNDS` are pre-parsed in WI 2a.0; `SCHEDULE` is
   parsed in step 1 above. Always include `now` in the cron prompt so each
   cron fire runs immediately AND re-registers itself. Note: this `now` is
   for the CRON's invocation, not the current invocation.

   ```bash
   # Construct cron prompt incrementally so optional flags only appear when set.
   CRON_PROMPT="Run /do ${TASK_DESCRIPTION_FOR_CRON}"  # description with landing/auto tokens preserved
   if [ "$FORCE" -eq 1 ]; then
     CRON_PROMPT="$CRON_PROMPT --force"
   fi
   if [ "$ROUNDS" != "1" ]; then
     CRON_PROMPT="$CRON_PROMPT --rounds $ROUNDS"
   fi
   CRON_PROMPT="$CRON_PROMPT every $SCHEDULE now"
   # CronCreate uses $CRON_PROMPT verbatim.
   ```

   **Persistence of `--force` and `--rounds N`:** these flags are preserved verbatim in the cron prompt. A `/do <task> --force every 4h` produces a cron prompt of `Run /do <task> --force every 4h now`, so every cron fire bypasses triage and review. Intentional: setting `--force` on a recurring task means the user wants the bypass on every fire.

5. **Create the cron** — `CronCreate` with `recurring: true`, passing
   `$CRON_PROMPT` verbatim.

6. **Confirm** with wall-clock time.

7. **If `now` is present:** proceed to Phase 1.
   **If `now` is NOT present:** **Exit.** The cron fires later.

If `every` is NOT present, skip this phase (bare invocation runs immediately).

## Phase 1 — Understand & Research

Before touching anything:

1. **Parse the task description** — what is being asked? What files are
   involved? What's the expected outcome?

2. **Identify relevant files and current state:**
   - Search for files related to the task (Glob, Grep)
   - Read existing content that will be modified
   - Check for related skills, conventions, or guidelines (e.g., model
     design rules for example models, newsletter format for entries)

3. **Classify the change type** — this determines verification intensity
   in Phase 3:
   - **Content only** — markdown, images, presentations, documentation.
     No tests needed.
   - **Code** — JavaScript, CSS, HTML, model files. Tests needed.
   - **Mixed** — both content and code. Tests needed for code portion.

4. **Plan the work** — no formal document, just mental clarity on what
   to do and in what order. If the task is bigger than expected (would
   take 1000+ lines of changes, has complex dependencies), suggest
   `/run-plan` instead and ask the user.

## Phase 1.5 — Argument Parsing (always before Phase 1 research)

Before any research or execution, parse flags from `$ARGUMENTS`.

**Step 1: Resolve `LANDING_MODE`.** Precedence: explicit flag (`pr`,
`direct`, `worktree`) → `execution.landing` in
`.claude/zskills-config.json` (`cherry-pick` → `worktree`, `pr` → `pr`,
`direct` → `direct`) → fallback `direct`.

```bash
REMAINING="$ARGUMENTS"
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
CONFIG_FILE="$MAIN_ROOT/.claude/zskills-config.json"

ARG_LANDING=""
if [[ "$REMAINING" =~ (^|[[:space:]])[pP][rR]($|[[:space:]]|[.!?]) ]]; then
  ARG_LANDING="pr"
elif [[ "$REMAINING" =~ (^|[[:space:]])[dD][iI][rR][eE][cC][tT]($|[[:space:]]) ]]; then
  ARG_LANDING="direct"
elif [[ "$REMAINING" =~ (^|[[:space:]])worktree($|[[:space:]]) ]]; then
  ARG_LANDING="worktree"
fi

if [ -n "$ARG_LANDING" ]; then
  LANDING_MODE="$ARG_LANDING"
elif [ -f "$CONFIG_FILE" ] && [[ $(cat "$CONFIG_FILE") =~ \"landing\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
  case "${BASH_REMATCH[1]}" in
    pr)          LANDING_MODE="pr" ;;
    cherry-pick) LANDING_MODE="worktree" ;;
    direct)      LANDING_MODE="direct" ;;
    *)           LANDING_MODE="direct" ;;  # unknown → safe default
  esac
else
  LANDING_MODE="direct"
fi

# Guard: direct + main_protected is an error (same contract as /run-plan
# and /fix-issues). Prevents silently committing to main when the repo
# requires PR/feature-branch workflow.
if [ "$LANDING_MODE" = "direct" ] && [ -f "$CONFIG_FILE" ] \
   && grep -q '"main_protected"[[:space:]]*:[[:space:]]*true' "$CONFIG_FILE"; then
  echo "ERROR: direct mode is incompatible with main_protected: true. Use pr, worktree, or change config."
  exit 1
fi
```

**Step 2: Derive `TASK_DESCRIPTION`** (strip landing tokens):
```bash
TASK_DESCRIPTION=$(echo "$REMAINING" \
  | sed -E 's/(^|[[:space:]])[pP][rR]($|[[:space:]]|[.!?])/ /' \
  | sed -E 's/(^|[[:space:]])[dD][iI][rR][eE][cC][tT]($|[[:space:]])/ /' \
  | sed -E 's/(^|[[:space:]])worktree($|[[:space:]])/ /' \
  | sed -E 's/(^|[[:space:]])[aA][uU][tT][oO]($|[[:space:]])/ /' \
  | sed -E 's/(^|[[:space:]])--force($|[[:space:]])/ /' \
  | sed -E 's/(^|[[:space:]])--no-claim($|[[:space:]])/ /' \
  | sed -E 's/(^|[[:space:]])--rounds[[:space:]]+[0-9]+($|[[:space:]])/ /' \
  | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')
if [ -z "$TASK_DESCRIPTION" ]; then
  echo "ERROR: Task description required. Usage: /do <task description> [pr|direct|worktree] [auto]"
  exit 1
fi
```

The `sed -E` lines strip `auto`, `--force`, `--no-claim`, and `--rounds N`
(numeric N only) from `TASK_DESCRIPTION` so they don't leak into downstream
prompts.
`auto` is the positional auto-merge opt-in (issue #297; mirrors
/run-plan, /fix-issues) — it is pre-parsed at WI 2a.0 into `AUTO_FLAG`,
read by `modes/pr.md` to inject `--auto` into the `/land-pr` invocation,
and stripped here so it never appears as user prose in the task prompt.
Non-numeric `--rounds <prose>` is left in place — symmetric with the
pre-flight greedy-fallthrough rule (WI 2a.0): a non-numeric trailing
token after `--rounds` is user prose, not a flag, and must NOT raise
exit 2.

**Step 3: Re-affirm `FORCE` and `ROUNDS`** (already set by the pre-flight
pre-parse; idempotent re-validation in case Phase 1.5 is invoked outside
the normal entry path — defensive). The regex MUST match the pre-flight
exactly: numeric-only `[0-9]+` capture with greedy-fallthrough on
non-numeric (no exit-2 branch — that would contradict the pre-flight's
contract that `/do fix the bug --rounds in production` is a legitimate
description). `AUTO_FLAG` is likewise already set by the pre-flight
pre-parse (see Pre-flight); Phase 4 (Land) reads it directly without
re-affirming here.

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

## Phase 2 — Execute

Select the execution path based on `LANDING_MODE` (resolved in Phase 1.5),
then **read the corresponding mode file in full and follow its
procedure end-to-end**. Do not proceed until you have read the file.

| `LANDING_MODE` | Path | Mode file |
|----------------|------|-----------|
| `pr`           | A    | [modes/pr.md](modes/pr.md) |
| `worktree`     | B    | [modes/worktree.md](modes/worktree.md) |
| `direct`       | C    | [modes/direct.md](modes/direct.md) |

**`$ISSUE_NUMS` propagates into the mode files** (array set in the
Pre-flight pre-parse; `$ISSUE_NUM` is kept as a back-compat scalar = the
first element). When `${#ISSUE_NUMS[@]} -gt 0`, the mode file fans out
the `claim-issue.sh` acquire across every element AFTER it constructs
its `PIPELINE_ID` (the C1/M1 rule — never acquire before a non-empty
PIPELINE_ID exists). The acquire is NEVER placed here in SKILL.md before
mode dispatch: PIPELINE_ID is empty at this point, so `--pipeline-id ""`
would fail usage-error exit 2.

## Phase 3 — Verify

Verification intensity matches the change type (from Phase 1):

### Content-only changes (md, jpg, png, presentations)

- **Spot-check:** formatting, links, file organization, image references
- **Do NOT run tests** — running 4,000+ tests for a markdown edit is
  wasteful, and pre-existing failures would block the task unnecessarily
- **Dispatch a separate verification agent (worktree/direct mode).** Tell
  the agent explicitly: "These are content-only changes (no code). Review
  the diff for correctness and completeness — do NOT run `npm test` or
  `npm run test:all`. Your job is: do these changes make sense? Are the
  right files included? Anything accidentally staged? Formatting correct?"
  Do NOT invoke `/verify-changes` for content-only changes — it will run
  the full test suite regardless. Instead, dispatch a plain review agent.

  **Dispatch shape.** Use the `Agent` tool with `subagent_type: "verifier"`. The verifier's tool allowlist (`Read, Grep, Glob, Bash, Edit, Write`) is sufficient for content review (Read + Grep cover the main path); the prose preamble above keeps it from running tests. After the dispatch returns, pipe `$VERIFIER_RESPONSE` through `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/verify-response-validate.sh"`; on exit 1 STOP — do NOT push.

  **Layer 3 — verifier response validation:**

  ```bash
  printf '%s' "$VERIFIER_RESPONSE" | bash "$CLAUDE_PROJECT_DIR/.claude/hooks/verify-response-validate.sh"
  VALIDATE_EXIT=$?
  ```

  On `VALIDATE_EXIT=1` — STOP. Do NOT push. Emit:

  ```
  STOP: verifier returned without meaningful results.

  $(cat /tmp/last-validate-stderr)

  This is a verification FAIL. Surface to the user. If the verifier
  agent file is missing, run /update-zskills.
  ```

### Code changes (js, css, html)

- **Run `$FULL_TEST_CMD`** (canonical form — maintainers: see
  `references/canonical-config-prelude.md` §1 in the zskills source) — all
  suites must pass, not just unit tests.
  **CRITICAL — Bash tool timeout:** invoke with `timeout: 600000` (10
  min); default 120000ms is shorter than the suite's runtime (~3-4
  min). Do NOT recover from a Bash timeout by retrying with
  `run_in_background: true` + `Monitor` / `BashOutput` — wake events
  do not reliably deliver to subagents (you may be one), so the wait
  never returns and the dispatch hangs at "Tests are running. Let me
  wait for the monitor." Past failure: 6+ subagent crashes with that
  phrase across 2026-04-29 and 2026-04-30. Always foreground-Bash with
  explicit long timeout; capture to file; read the file on return.
- **If tests fail: fix them.** Do not check if failures are pre-existing.
  Do not stash, checkout old commits, or create comparison worktrees.
  If you touched code and tests fail, they're yours to fix. (See
  CLAUDE.md: "NEVER modify the working tree to check if a failure is
  pre-existing.")
- **Dispatch a separate verification agent (worktree/direct mode)** running
  `/verify-changes`. This is the full 7-phase verification: diff review,
  test coverage audit, `npm run test:all`, manual verification if UI, fix
  problems, re-verify until clean. Landing (push/cherry-pick) only happens
  if this agent reports clean. Runs for ALL code changes regardless of the
  `auto` flag (issue #713) — `auto` controls autonomous landing, not
  whether to verify.

  **Dispatch shape.** Use the `Agent` tool with `subagent_type: "verifier"`. After the dispatch returns, pipe `$VERIFIER_RESPONSE` through `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/verify-response-validate.sh"`; on exit 1 STOP — do NOT push.

  **Layer 3 — verifier response validation:**

  ```bash
  printf '%s' "$VERIFIER_RESPONSE" | bash "$CLAUDE_PROJECT_DIR/.claude/hooks/verify-response-validate.sh"
  VALIDATE_EXIT=$?
  ```

  On `VALIDATE_EXIT=1` — STOP. Do NOT push. Emit:

  ```
  STOP: verifier returned without meaningful results.

  $(cat /tmp/last-validate-stderr)

  This is a verification FAIL, not a license to push. Surface to the
  user. If the verifier agent file is missing, run /update-zskills.
  ```

### Mixed changes

- Run tests for the code portion
- Spot-check the content portion
- Full `/verify-changes` via separate agent (worktree/direct mode)

## Phase 4 — Land (if auto flag present, Path C/B only)

Only reached if `AUTO_FLAG=1` (the `auto` token was present in the user's invocation) AND Phase 3 verification passed (Phase 3 verification runs unconditionally for code changes — see issue #713). This is the **push/land** step. Not applicable to PR mode (Path A — PR mode does its OWN push/land through `/land-pr` in Phase 2 Step A8, after its own verification gate in Step A6.5; AUTO_FLAG in PR mode is consumed by `modes/pr.md` to request auto-merge via `--auto` to `/land-pr`). Note this exclusion is about the push/land step only — PR mode DOES verify (Step A6.5), it just lands differently.

1. **If on main (Path C):**
   ```bash
   git push
   ```

2. **If in worktree (Path B):** dispatch `/commit land` to cherry-pick worktree commits onto main, then push.

   Dispatch via the Skill tool:

   ```
   Skill: { skill: "commit", args: "land" }
   ```

   `/commit land` (encoded in [`skills/commit/modes/land.md`](../commit/modes/land.md))
   handles the full landing flow:
   - Try-without-stash: does NOT run `git stash -u` (the
     `hooks/block-unsafe-generic.sh` gate denies bare/push/save/-u stash
     writes; `git cherry-pick` itself refuses on overlap, which preserves
     evidence of conflicting work in other sessions).
   - Cherry-picks worktree commits onto main sequentially. On any
     refusal or conflict: STOPs and reports — does NOT `--abort`, stash,
     or force-resolve.
   - Runs the full test suite after the cherry-picks land.
   - Writes the `.landed` marker on the worktree (`status: full`, source
     `commit-land`, with the list of cherry-picked hashes).

   On a clean return from `/commit land`:
   - Push main (`git push`).
   - Report what was pushed (commit hashes, branch).

   On a STOP report from `/commit land` (conflict, test failure, or
   refused cherry-pick): surface to the user verbatim. If `/do` has an
   active cron, kill it (`CronList` + `CronDelete` any whose prompt
   starts with `Run /do`). Do NOT force-push or resolve automatically.

3. **If verification failed:** do NOT push. Report the verification
   findings and stop.

## Phase 5 — Report

**Release the issue claim(s) (worktree/direct modes).** Phase 5 is the
universal terminal reached on BOTH the `auto` and non-`auto` exits of
worktree and direct modes — so the issue claims (acquired by the mode
file when `${#ISSUE_NUMS[@]} -gt 0`) are released HERE, not in Phase 4
Land (which is `AUTO_FLAG=1`-gated and would leak the claims on the
dominant non-auto path). PR mode (Path A) handles its own release inside
`modes/pr.md`'s finalize block and exits before reaching this section.
Skip when no issue claim was acquired (the common /do case — `ISSUE_NUMS`
empty):

```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
# $ISSUE_NUMS (Pre-flight pre-parse) and $PIPELINE_ID (set in the mode file:
# do.${TASK_SLUG}) survive in the persistent shell. Release each claim in
# order — releases are idempotent per claim-issue.sh, and ownership-safe via
# --require-pipeline. Skip entirely when no issues were claimed.
if [ "${#ISSUE_NUMS[@]}" -gt 0 ] && [ -n "${PIPELINE_ID:-}" ]; then
  for _ISSUE_N in "${ISSUE_NUMS[@]}"; do
    bash "$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/claim-issue.sh" release "$_ISSUE_N" --require-pipeline "$PIPELINE_ID"
  done
  unset _ISSUE_N
fi

# Issue #883 — clear the in-flight sentinel for worktree/direct modes
# (PR mode handles its own clear inside modes/pr.md's explicit-finalize
# block, before exiting and skipping this Phase 5). $PIPELINE_ID was
# set by the mode file (worktree.md: do.${TASK_SLUG} unsuffixed;
# direct.md: do.${ISSUE_NUMS[0]}); both modes match the WRITE key
# exactly, so a single clear works for both. Skip entirely when
# $PIPELINE_ID never got set (the no-issue direct-mode path).
INFLIGHT_HELPER="$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/check-inflight-batch.sh"
if [ -x "$INFLIGHT_HELPER" ] && [ -n "${PIPELINE_ID:-}" ]; then
  bash "$INFLIGHT_HELPER" clear do --pipeline-id "$PIPELINE_ID" || true
fi
```

Brief inline output. No persistent report file.

**On main (no worktree, no auto):**
```
Done. [1-2 sentence summary of what was done]
Changed: file1.js, file2.md (+N lines)
Committed: abc1234 — "commit message"
```

**On main with auto:**
<!-- allow-hardcoded: npm run test:all reason: report-template example string the agent prints in its completion message; not an executable command -->
```
Done and pushed. [1-2 sentence summary]
Changed: file1.js, file2.md (+N lines)
Committed: abc1234 — "commit message"
Pushed to: origin/main
Verification: clean (npm run test:all passed, /verify-changes clean)
```

**In worktree (no auto):**
```
Done. [1-2 sentence summary]
Worktree: ../do-<slug>/
Branch: do/<slug>
Commits: abc1234, def5678
To land: git cherry-pick abc1234 def5678
To discard: git worktree remove ../do-<slug>/
```

**In worktree with auto:**
```
Done and pushed. [1-2 sentence summary]
Cherry-picked to main: abc1234, def5678
Pushed to: origin/main
Verification: clean (/verify-changes clean)
Worktree: ../do-<slug>/ (can be removed)
```

**PR mode (pr flag):**
```
Done. [1-2 sentence summary of what was implemented]
PR: <PR_URL>
Branch: <BRANCH_NAME>
Worktree: <WORKTREE_PATH>
CI: passed | failed | no checks
Status: pr-ready | pr-ci-failing | landed
```

## Error Handling

- **Test failures (code changes):** stop, fix the code, re-test. Never
  weaken tests. Never check if failures are pre-existing.
- **Content issues:** stop, fix formatting/links/references, re-check.
- **Cherry-pick conflict (worktree + auto):** stop, report the conflict.
  Do not resolve automatically — conflicts need human judgment.
- **Push failure (auth, remote, etc.):** stop, report the error.
- **Task is bigger than expected:** stop, suggest `/run-plan` instead.
  Ask the user before continuing.
- **PR mode: rebase conflict:** write `.landed` with `status: conflict`,
  report to user, direct them to inspect `$WORKTREE_PATH`.
- **PR mode: CI failure:** write `.landed` with `status: pr-ci-failing`,
  report the failure. Do NOT dispatch fix agents.
- **PR mode: implementation agent fails without committing:** write
  `.landed` with `status: conflict` and exit with an error message.
- **If stuck on anything:** report the state and ask the user for
  guidance. Do not retry the same approach in a loop.
- **Release the issue claim(s) on every abandon path (worktree/direct modes).**
  When `${#ISSUE_NUMS[@]} -gt 0` and the mode file acquired
  `claim-issue.sh` claims, any error exit above (test failure, content
  issue, cherry-pick conflict, push failure, task-too-big) MUST release
  each one before stopping so the next pipeline can pick the issue(s) up:
  ```bash
  for _ISSUE_N in "${ISSUE_NUMS[@]}"; do
    bash "$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/claim-issue.sh" release "$_ISSUE_N" --require-pipeline "$PIPELINE_ID"
  done
  ```
  (only if any claim was acquired — skip when `ISSUE_NUMS` is empty).
  PR mode's abandon-path releases live inside `modes/pr.md`.

## Key Rules

- **Match verification to change type** — content-only tasks skip tests
  (but still get a content-review agent). Code tasks run tests AND get
  full `/verify-changes`. `auto` controls landing, not verification.
- **Never weaken tests** — fix the code, not the test.
- **Never modify the working tree to check pre-existing failures** — if
  you touched code and tests fail, fix them. No stash-and-compare, no
  checkout-old-commit, no comparison worktrees.
- **Protect other agents' work** — do not commit unrelated changes that
  happen to be in the working tree. Stage only files related to the task.
- **Worktree naming (worktree flag)** — use `../do-<slug>/` where `<slug>`
  is a short kebab-case description derived from the task (e.g.,
  `do-sort-screenshots`, `do-integrator-examples`). Include a timestamp
  suffix if a worktree with that name already exists. Uses manual
  `git worktree add` — NOT `isolation: "worktree"`.
- **Worktree naming (pr flag)** — use `/tmp/<project>-do-<slug>/` with
  a named branch `<branch_prefix>do-<slug>`. Both BRANCH_NAME and
  WORKTREE_PATH derive from TASK_SLUG (after any collision suffix).
- **No persistent report files** — `/do` outputs results inline. It does
  NOT write any report file under `$ZSKILLS_AUDIT_DIR`
  (e.g., the canonical `SPRINT_REPORT.md` / `PLAN_REPORT.md` artifacts owned by other skills).
  The commit is the artifact.
- **All code changes require verification** — worktree/direct mode always
  dispatches a separate verification agent (full `/verify-changes` for code,
  content-review agent for content-only) before any push. `auto` controls
  autonomous landing, not whether verification runs (issue #713).
- **PR mode CI runs through `/land-pr`** — `/do pr` dispatches the
  shared `/land-pr` skill, which polls CI and (on failure) drives a
  fix-cycle agent loop with the task description as work context.
- **PR body uses `git log origin/main..HEAD`** — never `git log main..HEAD`
  (local main may be stale after rebase).
- **PR titles and bodies are explicit** — never use `--fill` when creating a PR (the title and body are constructed by the skill, not auto-derived from commits).
- **Slug collision suffix targets TASK_SLUG itself** — not just WORKTREE_PATH.
  Both BRANCH_NAME and WORKTREE_PATH must pick up the suffix.
- **Respect CLAUDE.md** — all standard rules apply (no external deps, no
  bundlers, no weakened tests, etc.)
