---
name: land-pr
user-invocable: false
description: Helper for PR landing — rebase, push, create-or-detect PR, poll CI, optional auto-merge. Dispatched via the Skill tool by /run-plan, /commit pr, /do pr, /fix-issues pr, /quickfix (and orchestrator agents landing one-off PRs). Returns state via --result-file for caller-driven fix-cycle loops. Not for direct slash invocation — humans should use /commit pr instead.
argument-hint: --branch <name> --title <title> --body-file <path> --result-file <path> [--auto] [--worktree-path <path>] [--landed-source <skill>] [--ci-timeout <sec>] [--no-monitor] [--pr <num>] [--issue <num>] [--tracking-id <id>]
metadata:
  version: "2026.05.18+f83cc1"
---

# /land-pr — land a feature branch as a PR

`/land-pr` owns the rebase → push → create-or-detect → monitor → merge
sequence for a feature branch that is already in a presentable state.
Five callers (`/run-plan`, `/commit pr`, `/do pr`, `/fix-issues pr`,
`/quickfix`) dispatch into this skill via the Skill tool. `/land-pr` is
a helper, not a user-facing command: the API requires `--body-file` and
`--result-file`, both of which only make sense when a caller has set
them up. Users wanting to ship an existing branch should use `/commit pr`,
which dispatches `/land-pr` internally with the right arguments.

The skill is a **prose-driven procedure**: when invoked, you (Claude) read
this SKILL.md and execute the procedure step-by-step, calling the four
deterministic scripts under `scripts/` as you go. Data hand-off back to
the caller is **file-based** via `--result-file`, parsed by an allow-list
parser in the caller (see `references/caller-loop-pattern.md`).

The caller's loop pattern (idempotent re-invocation, allow-list result
parsing, CI-fix-cycle agent dispatch) lives in
`references/caller-loop-pattern.md`. The fix-cycle agent prompt template
lives in `references/fix-cycle-agent-prompt-template.md`. Phases 2–5 of
the PR_LANDING_UNIFICATION plan copy from these references.

## When invoked

**At orchestrator level only.** /land-pr was loaded into your context by
the Skill tool (or a direct slash invocation). Internal Agent dispatches
inside /land-pr — none planned, but if added — must run at orchestrator
level. Callers therefore must NOT dispatch /land-pr from inside an Agent
prompt block. This is a documented contract; conformance assertions in
Phase 6 verify caller skills follow it.

## Argument parsing (WI 1.2)

Parse `$ARGUMENTS` using the bash-regex idiom that matches `/quickfix`
and `/do`. Required: `--branch`, `--title`, `--body-file`, `--result-file`.
Optional: `--auto` (bool, default false), `--worktree-path`,
`--landed-source` (default `land-pr`), `--ci-timeout` (default 600),
`--no-monitor` (skip CI poll, return after create), `--pr <num>` (resume
mode: skip rebase/push/create, jump to monitor), `--issue <num>`
(passes through to `.landed` schema), `--tracking-id <id>` (when present,
write `fulfilled.land-pr.<id>` on successful merge to satisfy a parent
skill's `requires.land-pr.<id>` marker — `/run-plan` PR mode passes this;
the other 4 callers do not, preserving their no-fulfillment behavior).

```bash
ARGS=( "$@" )
BRANCH=""
TITLE=""
BODY_FILE=""
RESULT_FILE=""
AUTO_FLAG=false
WORKTREE_PATH=""
LANDED_SOURCE="land-pr"
CI_TIMEOUT=600
NO_MONITOR=false
PR_RESUME=""
ISSUE_NUM=""
BASE_BRANCH="main"
TRACKING_ID=""

i=0
while [ $i -lt ${#ARGS[@]} ]; do
  arg="${ARGS[$i]}"
  case "$arg" in
    --branch)         i=$((i+1)); BRANCH="${ARGS[$i]:-}" ;;
    --title)          i=$((i+1)); TITLE="${ARGS[$i]:-}" ;;
    --body-file)      i=$((i+1)); BODY_FILE="${ARGS[$i]:-}" ;;
    --result-file)    i=$((i+1)); RESULT_FILE="${ARGS[$i]:-}" ;;
    --auto)           AUTO_FLAG=true ;;
    --worktree-path)  i=$((i+1)); WORKTREE_PATH="${ARGS[$i]:-}" ;;
    --landed-source)  i=$((i+1)); LANDED_SOURCE="${ARGS[$i]:-}" ;;
    --ci-timeout)     i=$((i+1)); CI_TIMEOUT="${ARGS[$i]:-}" ;;
    --no-monitor)     NO_MONITOR=true ;;
    --pr)             i=$((i+1)); PR_RESUME="${ARGS[$i]:-}" ;;
    --issue)          i=$((i+1)); ISSUE_NUM="${ARGS[$i]:-}" ;;
    --base)           i=$((i+1)); BASE_BRANCH="${ARGS[$i]:-}" ;;
    --tracking-id)    i=$((i+1)); TRACKING_ID="${ARGS[$i]:-}" ;;
    *) echo "ERROR: /land-pr: unknown arg: $arg" >&2; exit 2 ;;
  esac
  i=$((i+1))
done

# Validation. Each fail-fast gate prints a discriminator line to stderr.
if [ -z "$BRANCH" ]; then
  echo "ERROR: /land-pr requires --branch" >&2; exit 2
fi
if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
  echo "ERROR: /land-pr: --branch must not be 'main' or 'master'" >&2; exit 2
fi
if [ -z "$TITLE" ]; then
  echo "ERROR: /land-pr requires --title" >&2; exit 2
fi
if [ "${#TITLE}" -gt 120 ]; then
  echo "ERROR: /land-pr: --title must be ≤ 120 chars (got ${#TITLE})" >&2; exit 2
fi
if [ -z "$BODY_FILE" ] || [ ! -s "$BODY_FILE" ]; then
  echo "ERROR: /land-pr: --body-file must exist and be non-empty (got '$BODY_FILE')" >&2; exit 2
fi
if [ -z "$RESULT_FILE" ]; then
  echo "ERROR: /land-pr requires --result-file" >&2; exit 2
fi
RESULT_DIR=$(dirname "$RESULT_FILE")
if [ ! -d "$RESULT_DIR" ]; then
  echo "ERROR: /land-pr: --result-file parent dir does not exist: $RESULT_DIR" >&2; exit 2
fi
if [ -n "$PR_RESUME" ] && ! [[ "$PR_RESUME" =~ ^[0-9]+$ ]]; then
  echo "ERROR: /land-pr: --pr must be numeric (got '$PR_RESUME')" >&2; exit 2
fi
if ! [[ "$CI_TIMEOUT" =~ ^[0-9]+$ ]]; then
  echo "ERROR: /land-pr: --ci-timeout must be numeric (got '$CI_TIMEOUT')" >&2; exit 2
fi

# Branch names commonly contain `/` (smoke/foo, feat/bar). Sanitize for
# use in /tmp sidecar filenames so we never accidentally create an
# unintended /tmp subdirectory. The slug is for filenames only — the
# real $BRANCH is what we pass to git/gh.
BRANCH_SLUG="${BRANCH//\//-}"
```

## Result-file safety contract (WI 1.7)

The result file is a sequence of `KEY=VALUE` lines. **Every value is a
single-line, shell-safe token** — no `\n`, `\r`, `$`, backticks,
`&`, `?`, `#`. Multi-line content (stderr text, conflict file lists)
goes in **sidecar files** referenced by path; only the path goes in the
result file.

Before writing each `KEY=VALUE` line, validate the value with this
helper:

```bash
validate_result_value() {
  local key="$1" value="$2"
  if [[ "$value" =~ [$'\n\r$`&?#'] ]]; then
    echo "ERROR: /land-pr: result-file VALUE for $key contains forbidden characters" >&2
    return 1
  fi
}
```

The result file is overwritten **atomically**: write to
`$RESULT_FILE.tmp`, then `mv` to `$RESULT_FILE`. Callers see either
the old file or the new file, never a partial write.

### Result-file schema

```
STATUS=created|monitored|merged|push-failed|rebase-conflict|create-failed|monitor-failed|merge-failed|rebase-failed|behind-thrash|auto-rebase-conflict|auto-rebase-blocked
PR_URL=<https-url-no-metacharacters-or-empty>
PR_NUMBER=<digits-or-empty>
PR_EXISTING=true|false
CI_STATUS=pass|fail|pending|none|skipped|unknown|not-monitored
CI_LOG_FILE=<path-or-empty>
MERGE_REQUESTED=true|false
MERGE_REASON=auto-not-requested|ci-not-passing|auto-merge-disabled-on-repo|gh-error|empty
PR_STATE=OPEN|MERGED|UNKNOWN|not-checked
REASON=<short-token-or-empty>           # e.g., rebase-conflict, network, abort-failed, auto-rebase-exhausted, auto-rebase-push-failed-rcN, mergeStateStatus-<status>, auto-rebase-unknown
CONFLICT_FILES_LIST=<path-or-empty>     # sidecar file with one conflict path per line
CALL_ERROR_FILE=<path-or-empty>         # sidecar file with stderr text from failed gh/git call
REBASE_STDERR_FILE=<path-or-empty>      # sidecar file with stderr from Step 6b auto-rebase loop
```

Caller parsing pattern: see `references/caller-loop-pattern.md`. Never
`source` the result file — use the allow-list line-by-line parser.

## Canonical `.landed` schema (WI 1.11)

When `--worktree-path` is supplied, `/land-pr` writes a `.landed` marker
at `<worktree>/.landed` via `bash "$CLAUDE_PROJECT_DIR/.claude/skills/commit/scripts/write-landed.sh"`.
The schema is canonical across all callers:

<!-- allow-hardcoded: TZ=America/New_York reason: schema-doc fence showing the .landed `date:` field's canonical form; the runtime call lives in the bash fence further down (also marked); per-skill $TIMEZONE migration is scoped to plans/SKILL_FILE_DRIFT_FIX.md, not this plan -->
```
status: <required>      # landed | pr-ready | pr-ci-failing | pr-failed | conflict | pr-state-unknown
date: <required>        # ISO-8601, NY tz: $(TZ=America/New_York date -Iseconds)
source: <required>      # caller skill name (run-plan, commit, do, fix-issues, quickfix, land-pr)
method: <required>      # always "pr" in this plan's scope
branch: <required>      # feature branch name
pr: <optional>          # PR URL; present only after pr-push-and-create.sh succeeds
ci: <optional>          # CI_STATUS value; present only after pr-monitor.sh ran
pr_state: <optional>    # PR_STATE value; present only after pr-merge.sh ran
commits: <optional>     # space-separated SHA list of commits on the branch
issue: <optional>       # GitHub issue number; present for /fix-issues caller
reason: <optional>      # short token: rebase-conflict-too-many-files, ci-fix-cycle-exhausted, etc.
conflict_files: <optional>  # space-separated paths; present for status=conflict (small lists only)
```

`/run-plan` may write its own `.landed` for the pre-`/land-pr`
"rebase-conflict-too-many-files" case (when it bails before invoking
`/land-pr`). The schema is the same in both write paths.

## Procedure (WI 1.12)

When `/land-pr` is invoked, run the steps below. Each step has a
clear input/output contract and a clear failure mode. Compose the
final result-file in step 9 from accumulated state.

### Step 1 — Initialize result variables

```bash
STATUS=""
PR_URL=""
PR_NUMBER=""
PR_EXISTING=""
CI_STATUS=""
CI_LOG_FILE=""
MERGE_REQUESTED="false"
MERGE_REASON=""
PR_STATE="not-checked"
REASON=""
CONFLICT_FILES_LIST=""
CALL_ERROR_FILE=""
```

### Step 2 — Resume-mode short-circuit (`--pr <num>`)

If `$PR_RESUME` is set, skip rebase / push / create — the caller has
already done those and wants to monitor an existing PR. Set
`PR_NUMBER=$PR_RESUME` and jump to step 6 (monitor).

**Use case for `--pr <num>`:** caller previously invoked
`/land-pr --no-monitor` (or had a monitor timeout); the PR exists and
the branch is pushed; now the caller wants to monitor (or re-monitor)
without re-running rebase/push/create.

```bash
if [ -n "$PR_RESUME" ]; then
  PR_NUMBER="$PR_RESUME"
  PR_EXISTING=true
  # Recover PR_URL via gh — single read, no jq binary, bash regex on JSON.
  PR_VIEW_JSON=$(gh pr view "$PR_NUMBER" --json url 2>/dev/null) || PR_VIEW_JSON=""
  if [[ "$PR_VIEW_JSON" =~ \"url\":[[:space:]]*\"([^\"]+)\" ]]; then
    PR_URL="${BASH_REMATCH[1]}"
  fi
  # Skip steps 3–4.
fi
```

(The `2>/dev/null` here is acceptable on this single read because
recovery to empty PR_URL is an explicit handled outcome — the result
file's PR_URL just stays empty if `gh pr view` fails. Other fallible
calls in this skill MUST capture stderr to a sidecar; this is the
documented exception for the resume-mode metadata recovery.)

### Step 3 — Rebase (skipped in resume mode)

Run `pr-rebase.sh` against the configured base branch. Parse its
stdout for `CONFLICT_FILES_LIST` / `REASON`. Map the exit code:

```bash
if [ -z "$PR_RESUME" ]; then
  REBASE_STDOUT=$(bash "$CLAUDE_PROJECT_DIR/.claude/skills/land-pr/scripts/pr-rebase.sh" \
    --branch "$BRANCH" --base "$BASE_BRANCH")
  REBASE_RC=$?

  while IFS='=' read -r KEY VALUE; do
    case "$KEY" in
      CONFLICT_FILES_LIST) CONFLICT_FILES_LIST="$VALUE" ;;
      REASON) REASON="$VALUE" ;;
    esac
  done <<<"$REBASE_STDOUT"

  if [ "$REBASE_RC" -eq 10 ]; then
    STATUS="rebase-conflict"
    # Jump to step 9 (compose .landed + result file).
  elif [ "$REBASE_RC" -eq 11 ]; then
    STATUS="rebase-failed"
    # Jump to step 9.
  fi
fi
```

If `STATUS` is set to `rebase-conflict` or `rebase-failed`, skip
steps 4–7 and proceed to step 8/9.

### Step 4 — Push and create-or-detect PR (skipped in resume mode)

```bash
if [ -z "$PR_RESUME" ] && [ -z "$STATUS" ]; then
  PUSH_STDOUT=$(bash "$CLAUDE_PROJECT_DIR/.claude/skills/land-pr/scripts/pr-push-and-create.sh" \
    --branch "$BRANCH" --base "$BASE_BRANCH" \
    --title "$TITLE" --body-file "$BODY_FILE")
  PUSH_RC=$?

  while IFS='=' read -r KEY VALUE; do
    case "$KEY" in
      PR_EXISTING) PR_EXISTING="$VALUE" ;;
      PR_URL) PR_URL="$VALUE" ;;
      PR_NUMBER) PR_NUMBER="$VALUE" ;;
      CALL_ERROR_FILE) CALL_ERROR_FILE="$VALUE" ;;
    esac
  done <<<"$PUSH_STDOUT"

  case "$PUSH_RC" in
    0) : ;;  # success, fall through
    12) STATUS="push-failed" ;;
    13) STATUS="create-failed" ;;
    14) STATUS="create-failed"; REASON="invalid-pr-number" ;;
    *)  STATUS="create-failed"; REASON="push-create-rc-$PUSH_RC" ;;
  esac
fi
```

### Step 5 — `--no-monitor` short-circuit

If `$NO_MONITOR` is true and PR creation succeeded, set
`STATUS=created` `CI_STATUS=not-monitored` and jump to step 8.

**Use case for `--no-monitor`:** caller wants to report the PR URL
mid-flight, or split the create-and-monitor flow across two cron-fired
turns. None of the 5 callers in this plan use `--no-monitor` — it is
reserved for future callers.

```bash
if [ -z "$STATUS" ] && [ "$NO_MONITOR" = "true" ]; then
  STATUS="created"
  CI_STATUS="not-monitored"
fi
```

### Step 6 — Monitor CI

> **Past failure (PR #131, 2026-04-30) — DO NOT skip this step.**
> The agent skipped Step 6 on PR #131, read the previous inline bash
> block as suggestion-prose, did one snapshot `gh pr checks 131`
> showing `pending`, reported that in the summary, and exited. User
> discovered the midnight CI flake 20+ minutes later by manual polling.
> The polling logic now lives in `scripts/pr-monitor.sh` so it MUST be
> invoked explicitly — paraphrasing or substituting a single
> `gh pr checks` snapshot is a skill-step skip.
>
> Issue #133 documents this past-failure preamble; the conformance
> assertion `check land-pr "PR #131 past-failure preamble"` (added in
> WI 3.4) verifies the wording survives.

If `STATUS` is unset (or `created` with `CI_STATUS=not-monitored`
already set in step 5, in which case skip), run `pr-monitor.sh`:

```bash
if [ -z "$STATUS" ] || { [ "$STATUS" = "created" ] && [ "$CI_STATUS" != "not-monitored" ]; }; then
  CI_LOG_OUT="/tmp/land-pr-ci-log-$BRANCH_SLUG-$$.txt"
  MONITOR_STDOUT=$(bash "$CLAUDE_PROJECT_DIR/.claude/skills/land-pr/scripts/pr-monitor.sh" \
    --pr "$PR_NUMBER" --timeout "$CI_TIMEOUT" --log-out "$CI_LOG_OUT")
  MONITOR_RC=$?

  while IFS='=' read -r KEY VALUE; do
    case "$KEY" in
      CI_STATUS) CI_STATUS="$VALUE" ;;
      CI_LOG_FILE) CI_LOG_FILE="$VALUE" ;;
    esac
  done <<<"$MONITOR_STDOUT"

  if [ "$MONITOR_RC" -ne 0 ]; then
    STATUS="monitor-failed"
    REASON="monitor-rc-$MONITOR_RC"
  else
    STATUS="monitored"
  fi
fi
```

### Step 6b — Auto-rebase BEHIND PRs post-CI-green (Issue #266)

After Step 6 returns `CI_STATUS=pass`, the PR's `mergeStateStatus` may
be `BEHIND` because `origin/$BASE_BRANCH` advanced while CI was running
(a sibling PR landed). On repos with "Require branches to be up to date
before merging" branch protection, GitHub's auto-merge waits indefinitely
in this state — the auto-merge does NOT auto-rebase the branch. Without
this step, the PR sits at `OPEN/BEHIND` until someone manually rebases
and force-pushes.

This step closes that loop: detect BEHIND, rebase locally onto current
`origin/$BASE_BRANCH`, force-push with lease, re-poll CI, re-check
`mergeStateStatus`. Bounded at **3 iterations** to avoid pathological
churn when many PRs are landing rapidly.

**Skip conditions (skip the whole Step 6b loop):**
- `$AUTO_FLAG != true` — BEHIND recovery is only useful when auto-merge
  is requested. Without `--auto`, BEHIND is the caller's problem to
  resolve manually.
- `$STATUS` already set to a failure terminus (`rebase-conflict`,
  `push-failed`, `create-failed`, `monitor-failed`, `rebase-failed`,
  `merge-failed`) — Step 6b shouldn't run after upstream failures.
- `$CI_STATUS != pass` — only act on green CI (avoid spinning on a
  permanently-failing PR).
- `$PR_NUMBER` empty — nothing to rebase against.

**`mergeStateStatus` handling (the loop is keyed off this):**
- `CLEAN` / `HAS_HOOKS` / `UNSTABLE` → mergeable, break loop, proceed
  to Step 7.
- `BEHIND` → fire the rebase + force-push + re-poll iteration.
- `BLOCKED` → branch protection blocking (e.g., review required); break
  loop with `STATUS=auto-rebase-blocked REASON=mergeStateStatus-BLOCKED`.
- `CONFLICTING` → genuine GitHub-side merge conflict; break loop with
  `STATUS=auto-rebase-blocked REASON=mergeStateStatus-CONFLICTING`.
- `UNKNOWN` → break loop with `STATUS=auto-rebase-blocked
  REASON=auto-rebase-unknown`.

**Iteration cap is hardcoded 3.** If exhausted still BEHIND, set
`STATUS=behind-thrash REASON=auto-rebase-exhausted`, skip Step 7
(merge), proceed to Step 8 where the status mapping table maps
`behind-thrash → pr-ready` (the PR is real and reviewable; the
auto-rebase loop just gave up).

All rebase/push/fetch stderr is captured to a single sidecar
`/tmp/land-pr-auto-rebase-stderr-$BRANCH_SLUG-$$.log`, referenced via
`REBASE_STDERR_FILE` in the result file when the loop fails.

```bash
if [ -z "$STATUS" ] \
   && [ "$AUTO_FLAG" = "true" ] \
   && [ "$CI_STATUS" = "pass" ] \
   && [ -n "$PR_NUMBER" ]; then
  REBASE_STDERR="/tmp/land-pr-auto-rebase-stderr-$BRANCH_SLUG-$$.log"
  : > "$REBASE_STDERR"
  AUTO_REBASE_ITER=0
  AUTO_REBASE_MAX=3

  # Initial mergeStateStatus probe.
  MS_JSON=$(gh pr view "$PR_NUMBER" --json mergeStateStatus 2>>"$REBASE_STDERR")
  MS_STATE=""
  if [[ "$MS_JSON" =~ \"mergeStateStatus\":[[:space:]]*\"([^\"]+)\" ]]; then
    MS_STATE="${BASH_REMATCH[1]}"
  fi

  while [ "$MS_STATE" = "BEHIND" ] && [ "$AUTO_REBASE_ITER" -lt "$AUTO_REBASE_MAX" ]; do
    AUTO_REBASE_ITER=$((AUTO_REBASE_ITER + 1))
    echo "INFO: /land-pr Step 6b: PR #$PR_NUMBER is BEHIND (iter $AUTO_REBASE_ITER/$AUTO_REBASE_MAX); rebasing + force-pushing" >&2

    # Rebase onto current origin/$BASE_BRANCH. Use WORKTREE_PATH when
    # provided; otherwise operate against current working dir.
    REBASE_DIR="${WORKTREE_PATH:-$(pwd)}"
    if ! git -C "$REBASE_DIR" fetch origin "$BASE_BRANCH" 2>>"$REBASE_STDERR"; then
      STATUS="auto-rebase-conflict"
      REASON="auto-rebase-fetch-failed-rc$?"
      break
    fi
    if ! git -C "$REBASE_DIR" rebase "origin/$BASE_BRANCH" 2>>"$REBASE_STDERR"; then
      # Rebase conflict — capture conflict files, abort, surface.
      CONFLICT_PATHS=$(git -C "$REBASE_DIR" diff --name-only --diff-filter=U 2>>"$REBASE_STDERR" | tr '\n' ' ' | sed 's/ $//')
      git -C "$REBASE_DIR" rebase --abort 2>>"$REBASE_STDERR" || true
      if [ -n "$CONFLICT_PATHS" ]; then
        CONFLICT_FILES_SIDECAR="/tmp/land-pr-auto-rebase-conflicts-$BRANCH_SLUG-$$.list"
        printf '%s\n' $CONFLICT_PATHS > "$CONFLICT_FILES_SIDECAR"
        CONFLICT_FILES_LIST="$CONFLICT_FILES_SIDECAR"
      fi
      STATUS="auto-rebase-conflict"
      REASON="auto-rebase-conflict-iter$AUTO_REBASE_ITER"
      break
    fi

    # Force-push with lease.
    if ! git -C "$REBASE_DIR" push --force-with-lease origin "$BRANCH" 2>>"$REBASE_STDERR"; then
      PUSH_RC=$?
      # On non-final iterations, retry: fetch+rebase loop top will pick
      # up any new origin moves. On final iteration, surface failure.
      if [ "$AUTO_REBASE_ITER" -ge "$AUTO_REBASE_MAX" ]; then
        STATUS="auto-rebase-blocked"
        REASON="auto-rebase-push-failed-rc$PUSH_RC"
        break
      fi
      echo "WARN: /land-pr Step 6b: push --force-with-lease failed (rc=$PUSH_RC); retrying" >&2
      # Refresh mergeStateStatus and continue loop.
      MS_JSON=$(gh pr view "$PR_NUMBER" --json mergeStateStatus 2>>"$REBASE_STDERR")
      MS_STATE=""
      if [[ "$MS_JSON" =~ \"mergeStateStatus\":[[:space:]]*\"([^\"]+)\" ]]; then
        MS_STATE="${BASH_REMATCH[1]}"
      fi
      continue
    fi

    # Re-poll CI on the rebased commit.
    CI_LOG_OUT="/tmp/land-pr-ci-log-$BRANCH_SLUG-rebase$AUTO_REBASE_ITER-$$.txt"
    MONITOR_STDOUT=$(bash "$CLAUDE_PROJECT_DIR/.claude/skills/land-pr/scripts/pr-monitor.sh" \
      --pr "$PR_NUMBER" --timeout "$CI_TIMEOUT" --log-out "$CI_LOG_OUT")
    MONITOR_RC=$?
    while IFS='=' read -r KEY VALUE; do
      case "$KEY" in
        CI_STATUS) CI_STATUS="$VALUE" ;;
        CI_LOG_FILE) CI_LOG_FILE="$VALUE" ;;
      esac
    done <<<"$MONITOR_STDOUT"
    if [ "$MONITOR_RC" -ne 0 ] || [ "$CI_STATUS" != "pass" ]; then
      # CI failed (or monitor failed) on the rebased commit. Don't keep
      # spinning the rebase loop — surface and let the caller's fix-cycle
      # take over.
      STATUS="auto-rebase-blocked"
      REASON="auto-rebase-ci-${CI_STATUS:-monitor-failed}-iter$AUTO_REBASE_ITER"
      break
    fi

    # Re-check mergeStateStatus.
    MS_JSON=$(gh pr view "$PR_NUMBER" --json mergeStateStatus 2>>"$REBASE_STDERR")
    MS_STATE=""
    if [[ "$MS_JSON" =~ \"mergeStateStatus\":[[:space:]]*\"([^\"]+)\" ]]; then
      MS_STATE="${BASH_REMATCH[1]}"
    fi

    case "$MS_STATE" in
      CLEAN|HAS_HOOKS|UNSTABLE)
        echo "INFO: /land-pr Step 6b: mergeStateStatus=$MS_STATE after rebase (iter $AUTO_REBASE_ITER); proceeding to merge" >&2
        break
        ;;
      BEHIND)
        # Loop continues.
        ;;
      BLOCKED|CONFLICTING)
        STATUS="auto-rebase-blocked"
        REASON="mergeStateStatus-$MS_STATE"
        break
        ;;
      UNKNOWN|"")
        STATUS="auto-rebase-blocked"
        REASON="auto-rebase-unknown"
        break
        ;;
      *)
        STATUS="auto-rebase-blocked"
        REASON="mergeStateStatus-$MS_STATE"
        break
        ;;
    esac
  done

  # Loop exhausted still BEHIND → behind-thrash.
  if [ -z "$STATUS" ] && [ "$MS_STATE" = "BEHIND" ] && [ "$AUTO_REBASE_ITER" -ge "$AUTO_REBASE_MAX" ]; then
    STATUS="behind-thrash"
    REASON="auto-rebase-exhausted"
  fi

  # Reference the sidecar in the result file if the loop failed.
  if [ -s "$REBASE_STDERR" ] \
     && { [ "$STATUS" = "behind-thrash" ] \
          || [ "$STATUS" = "auto-rebase-conflict" ] \
          || [ "$STATUS" = "auto-rebase-blocked" ]; }; then
    REBASE_STDERR_FILE="$REBASE_STDERR"
  else
    rm -f "$REBASE_STDERR"
  fi
fi
```

### Step 7 — Merge (gated on `--auto`)

Always run `pr-merge.sh` — it owns the auto/CI gating internally.

```bash
if [ -n "$PR_NUMBER" ] && [ "$STATUS" != "rebase-conflict" ] && [ "$STATUS" != "rebase-failed" ] && [ "$STATUS" != "push-failed" ] && [ "$STATUS" != "create-failed" ] && [ "$STATUS" != "behind-thrash" ] && [ "$STATUS" != "auto-rebase-conflict" ] && [ "$STATUS" != "auto-rebase-blocked" ]; then
  MERGE_STDOUT=$(bash "$CLAUDE_PROJECT_DIR/.claude/skills/land-pr/scripts/pr-merge.sh" \
    --pr "$PR_NUMBER" --auto-flag "$AUTO_FLAG" --ci-status "${CI_STATUS:-not-monitored}")
  MERGE_RC=$?

  while IFS='=' read -r KEY VALUE; do
    case "$KEY" in
      MERGE_REQUESTED) MERGE_REQUESTED="$VALUE" ;;
      MERGE_REASON) MERGE_REASON="$VALUE" ;;
      PR_STATE) PR_STATE="$VALUE" ;;
      CALL_ERROR_FILE) CALL_ERROR_FILE="$VALUE" ;;
    esac
  done <<<"$MERGE_STDOUT"

  if [ "$MERGE_RC" -eq 30 ]; then
    STATUS="merge-failed"
    REASON="${REASON:-merge-rc-30}"
  elif [ "$MERGE_REQUESTED" = "true" ] && [ "$PR_STATE" = "MERGED" ]; then
    STATUS="merged"
  fi
fi
```

### Step 7b — Fast-forward local main after successful merge

When `pr-merge.sh` confirmed `PR_STATE=MERGED`, refresh local `$BASE_BRANCH`
so subsequent worktree creations and any consumer of `main` see ground
truth. Without this step, local `main`'s ref + working tree stay at the
pre-merge SHA after a squash-merge, and downstream skills anchor on stale
ground state. Issue #254. Failure modes are surfaced loud — never silent —
and never destructive (mirrors the fetch+ff-merge+ahead-check discipline
from `create-worktree.sh:268-291`, landed via #225 / PR #232).

```bash
if [ "$MERGE_REQUESTED" = "true" ] && [ "$PR_STATE" = "MERGED" ]; then
  MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)/.." && pwd)
  if [ -z "$MAIN_ROOT" ] || { [ ! -d "$MAIN_ROOT/.git" ] && [ ! -f "$MAIN_ROOT/.git" ]; }; then
    echo "WARN: /land-pr Step 7b: could not resolve MAIN_ROOT; skipping local-main FF" >&2
  else
    MAIN_HEAD_REF=$(git -C "$MAIN_ROOT" symbolic-ref --short HEAD 2>/dev/null || echo "")
    MAIN_DIRTY=""
    if [ -n "$MAIN_HEAD_REF" ]; then
      MAIN_DIRTY=$(git -C "$MAIN_ROOT" status --porcelain 2>/dev/null | head -1)
    fi
    AHEAD=$(git -C "$MAIN_ROOT" rev-list --count "origin/$BASE_BRANCH..$BASE_BRANCH" 2>/dev/null || echo "0")

    if [ "$MAIN_HEAD_REF" != "$BASE_BRANCH" ]; then
      echo "INFO: /land-pr Step 7b: MAIN_ROOT not on $BASE_BRANCH (HEAD=$MAIN_HEAD_REF); skipping local-main FF" >&2
    elif [ -n "$MAIN_DIRTY" ]; then
      echo "WARN: /land-pr Step 7b: MAIN_ROOT working tree dirty; skipping local-main FF" >&2
    elif [ "$AHEAD" -gt 0 ]; then
      echo "WARN: /land-pr Step 7b: local $BASE_BRANCH is $AHEAD commit(s) ahead of origin — refusing FF" >&2
    else
      FF_STDERR="/tmp/land-pr-ff-stderr-$BRANCH_SLUG-$$.log"
      if git -C "$MAIN_ROOT" fetch origin "$BASE_BRANCH" 2>"$FF_STDERR" \
         && git -C "$MAIN_ROOT" merge --ff-only "origin/$BASE_BRANCH" 2>>"$FF_STDERR"; then
        echo "INFO: /land-pr Step 7b: fast-forwarded local $BASE_BRANCH to origin/$BASE_BRANCH"
        rm -f "$FF_STDERR"
      else
        echo "WARN: /land-pr Step 7b: fetch+ff-merge failed (see $FF_STDERR); local $BASE_BRANCH not updated" >&2
      fi
    fi
  fi
fi
```

### Step 8 — Compose `.landed` (auto-detect worktree if `--worktree-path` omitted)

Use this **status mapping table** to derive `.landed`'s `status` field.
**Evaluation: top-down, first-match-wins.** Failure-exits and
pre-conditions come first; CI_STATUS=fail and CI_STATUS=pending take
precedence over MERGE_REQUESTED/PR_STATE rows because the
merge-requested-but-CI-failed combo (auto-merge accepted but CI
changed after) should NOT be reported as `landed`.

| # | Condition (top-down, first match wins) | → `.landed status` |
|---|----------------------------------------|--------------------|
| 1 | STATUS=rebase-conflict | conflict |
| 1b | STATUS=auto-rebase-conflict | conflict |
| 2 | STATUS in {push-failed, create-failed, rebase-failed, merge-failed, monitor-failed} | pr-failed |
| 2b | STATUS=behind-thrash | pr-ready |
| 2c | STATUS=auto-rebase-blocked | pr-ready |
| 3 | CI_STATUS=fail | pr-ci-failing |
| 4 | CI_STATUS=pending | pr-ready |
| 5 | CI_STATUS=unknown | pr-ready |
| 6 | MERGE_REQUESTED=true AND PR_STATE=MERGED AND CI_STATUS in {pass, none, skipped} | landed |
| 7 | MERGE_REQUESTED=true AND PR_STATE=OPEN AND CI_STATUS in {pass, none, skipped} | pr-ready |
| 8 | MERGE_REQUESTED=true AND PR_STATE=UNKNOWN AND CI_STATUS in {pass, none, skipped} | pr-state-unknown |
| 9 | MERGE_REQUESTED=false (auto-merge-disabled-on-repo) AND CI_STATUS in {pass, none, skipped} | pr-ready |
| 10 | MERGE_REQUESTED=false (auto-not-requested) AND CI_STATUS in {pass, none, skipped} | pr-ready |

Compose the body and pipe to `write-landed.sh`. When `--worktree-path`
is omitted, auto-detect from cwd: if cwd is a registered **linked**
worktree of the current repo (NOT the main worktree, which has no
associated branch-of-work to mark), use it as the marker target. This
closes the Issue #205 gap where orchestrator-direct `/land-pr` dispatch
from inside a worktree but without `--worktree-path` silently skipped
the `.landed` write. `--worktree-path` remains an explicit override.

<!-- allow-hardcoded: TZ=America/New_York reason: matches the schema doc above and the established idiom across skills; per-skill $TIMEZONE migration is scoped to plans/SKILL_FILE_DRIFT_FIX.md, not this plan -->
```bash
# Auto-detect WORKTREE_PATH from cwd when caller didn't pass --worktree-path.
# Detection uses `git rev-parse` (worktree root + git-dir vs git-common-dir
# divergence indicates a LINKED worktree, not the main worktree) plus
# membership in `git worktree list --porcelain` for defense-in-depth.
if [ -z "$WORKTREE_PATH" ]; then
  CANDIDATE=$(git rev-parse --show-toplevel 2>/dev/null) || CANDIDATE=""
  if [ -n "$CANDIDATE" ]; then
    GIT_DIR=$(git -C "$CANDIDATE" rev-parse --git-dir 2>/dev/null) || GIT_DIR=""
    GIT_COMMON_DIR=$(git -C "$CANDIDATE" rev-parse --git-common-dir 2>/dev/null) || GIT_COMMON_DIR=""
    # Linked worktree: per-worktree git-dir differs from common-dir.
    # Main worktree (or non-worktree dir): they match (or are empty on failure).
    if [ -n "$GIT_DIR" ] && [ -n "$GIT_COMMON_DIR" ] && [ "$GIT_DIR" != "$GIT_COMMON_DIR" ]; then
      # Verify membership in `git worktree list` to guard against odd
      # checkout layouts that happen to expose distinct git-dirs.
      if git -C "$CANDIDATE" worktree list --porcelain 2>/dev/null | grep -qF "worktree $CANDIDATE"; then
        WORKTREE_PATH="$CANDIDATE"
      fi
    fi
  fi
fi

if [ -n "$WORKTREE_PATH" ]; then
  # Derive .landed status from the table above.
  LANDED_STATUS="pr-ready"  # default fallback
  case "$STATUS" in
    rebase-conflict|auto-rebase-conflict) LANDED_STATUS="conflict" ;;
    push-failed|create-failed|rebase-failed|merge-failed|monitor-failed)
      LANDED_STATUS="pr-failed" ;;
    behind-thrash|auto-rebase-blocked) LANDED_STATUS="pr-ready" ;;
    *)
      case "$CI_STATUS" in
        fail) LANDED_STATUS="pr-ci-failing" ;;
        pending|unknown) LANDED_STATUS="pr-ready" ;;
        pass|none|skipped|not-monitored)
          if [ "$MERGE_REQUESTED" = "true" ]; then
            case "$PR_STATE" in
              MERGED) LANDED_STATUS="landed" ;;
              OPEN) LANDED_STATUS="pr-ready" ;;
              UNKNOWN) LANDED_STATUS="pr-state-unknown" ;;
              *) LANDED_STATUS="pr-ready" ;;
            esac
          else
            LANDED_STATUS="pr-ready"
          fi
          ;;
      esac
      ;;
  esac

  # Metadata-only capture; on rare git failures (detached HEAD with
  # missing origin/$BASE_BRANCH ref) COMMITS_LIST stays empty rather than
  # aborting .landed write. Stderr goes to a discarded log, not the
  # null device — keeps the file inspectable post-mortem.
  #
  # Use `origin/$BASE_BRANCH` (NOT local `$BASE_BRANCH`): in multi-PR
  # sequential sprints, local main goes stale relative to origin/main
  # after each auto-merge, which over-populates this list with squash
  # commits from prior sprints' PRs (Issue #203). pr-rebase.sh fetches
  # origin/$BASE_BRANCH earlier in the pipeline, so it's always current
  # by the time we reach Step 8.
  GIT_LOG_STDERR="/tmp/land-pr-commits-list-stderr-$BRANCH_SLUG-$$.log"
  COMMITS_LIST=$(cd "$WORKTREE_PATH" && git log --format=%H "origin/$BASE_BRANCH..HEAD" 2>"$GIT_LOG_STDERR" | tr '\n' ' ' | sed 's/ $//')
  LANDED_DATE=$(TZ=America/New_York date -Iseconds)

  {
    printf 'status: %s\n' "$LANDED_STATUS"
    printf 'date: %s\n'   "$LANDED_DATE"
    printf 'source: %s\n' "$LANDED_SOURCE"
    printf 'method: pr\n'
    printf 'branch: %s\n' "$BRANCH"
    [ -n "$PR_URL" ]         && printf 'pr: %s\n'        "$PR_URL"
    [ -n "$CI_STATUS" ]      && printf 'ci: %s\n'        "$CI_STATUS"
    [ "$PR_STATE" != "not-checked" ] && printf 'pr_state: %s\n' "$PR_STATE"
    [ -n "$COMMITS_LIST" ]   && printf 'commits: %s\n'   "$COMMITS_LIST"
    [ -n "$ISSUE_NUM" ]      && printf 'issue: %s\n'     "$ISSUE_NUM"
    [ -n "$REASON" ]         && printf 'reason: %s\n'    "$REASON"
  } | bash "$CLAUDE_PROJECT_DIR/.claude/skills/commit/scripts/write-landed.sh" "$WORKTREE_PATH"
fi
```

### Step 8b — Write `fulfilled.land-pr.<id>` (only when `--tracking-id` given AND row-6 merge gate holds)

Write the fulfillment marker ONLY when the caller passed `--tracking-id`
AND the PR is actually merged on main. Match the row-6 gate from Step 8's
`.landed` status-mapping table:

> `MERGE_REQUESTED=true AND PR_STATE=MERGED AND CI_STATUS in {pass, none, skipped}`

Any other state (pr-ready, pr-ci-failing, push-failed, rebase-conflict,
pr-state-unknown, etc.) means the work isn't actually landed — do NOT
fulfill. The 4 non-/run-plan callers never pass `--tracking-id`, so this
block is a no-op for them (preserves current behavior exactly).

```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
if [ -n "$TRACKING_ID" ] \
   && [ "$MERGE_REQUESTED" = "true" ] \
   && [ "$PR_STATE" = "MERGED" ] \
   && { [ "$CI_STATUS" = "pass" ] || [ "$CI_STATUS" = "none" ] || [ "$CI_STATUS" = "skipped" ]; }; then
  PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
  MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)/.." && pwd)
  PIPELINE_SUBDIR="$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
  if [ -d "$PIPELINE_SUBDIR" ]; then
    printf 'skill: land-pr\nid: %s\npr: %s\nbranch: %s\ndate: %s\n' \
      "$TRACKING_ID" "$PR_URL" "$BRANCH" "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
      > "$PIPELINE_SUBDIR/fulfilled.land-pr.$TRACKING_ID"
  fi
fi
```

### Step 9 — Write the result file (atomic; allow-list parser will read it)

Default any unset values to the empty string, then validate every
value before writing. Atomic write via `.tmp` + `mv`.

```bash
# Defaults for unset values.
: "${STATUS:=monitored}"
: "${PR_URL:=}"
: "${PR_NUMBER:=}"
: "${PR_EXISTING:=false}"
: "${CI_STATUS:=not-monitored}"
: "${CI_LOG_FILE:=}"
: "${MERGE_REQUESTED:=false}"
: "${MERGE_REASON:=empty}"
: "${PR_STATE:=not-checked}"
: "${REASON:=}"
: "${CONFLICT_FILES_LIST:=}"
: "${CALL_ERROR_FILE:=}"
: "${REBASE_STDERR_FILE:=}"

TMP_RESULT="$RESULT_FILE.tmp"
: > "$TMP_RESULT"

write_kv() {
  local key="$1" value="$2"
  validate_result_value "$key" "$value" || return 1
  printf '%s=%s\n' "$key" "$value" >> "$TMP_RESULT"
}

write_kv STATUS              "$STATUS"              || exit 40
write_kv PR_URL              "$PR_URL"              || exit 40
write_kv PR_NUMBER           "$PR_NUMBER"           || exit 40
write_kv PR_EXISTING         "$PR_EXISTING"         || exit 40
write_kv CI_STATUS           "$CI_STATUS"           || exit 40
write_kv CI_LOG_FILE         "$CI_LOG_FILE"         || exit 40
write_kv MERGE_REQUESTED     "$MERGE_REQUESTED"     || exit 40
write_kv MERGE_REASON        "$MERGE_REASON"        || exit 40
write_kv PR_STATE            "$PR_STATE"            || exit 40
write_kv REASON              "$REASON"              || exit 40
write_kv CONFLICT_FILES_LIST "$CONFLICT_FILES_LIST" || exit 40
write_kv CALL_ERROR_FILE     "$CALL_ERROR_FILE"     || exit 40
write_kv REBASE_STDERR_FILE  "$REBASE_STDERR_FILE"  || exit 40

mv "$TMP_RESULT" "$RESULT_FILE"
```

### Step 10 — One-line summary to stdout

```bash
echo "STATUS=$STATUS PR=${PR_URL:-(none)} CI=${CI_STATUS:-(none)}"
```

## Idempotency contract

`/land-pr` is **idempotent per call** — re-invoking with the same branch
is a no-op for steps already done:

- `pr-rebase.sh`: `git rebase origin/<base>` is a no-op when the local
  branch is already on top of the base. Exit 0.
- `pr-push-and-create.sh`: `git push` with no new commits is a no-op
  (gh's "Everything up-to-date" message). `gh pr list` detects an
  existing PR; we emit `PR_EXISTING=true` and exit 0 without calling
  `gh pr create` again. The script does NOT call `gh pr edit --body-file`
  on the existing-PR path — body update is the caller's responsibility.
- `pr-monitor.sh`: stateless — re-running after a `pending` outcome
  resumes polling the same PR cleanly.
- `pr-merge.sh`: `gh pr merge --auto` is idempotent (re-requesting
  auto-merge on a PR that already has it queued is a no-op).

The fix-cycle re-invocation case (caller pushed a fix commit, /land-pr
is called again) does NOT cause spurious conflicts: the local branch's
new commits are already rebased on `origin/main` from the prior pass.

## Cross-skill dispatch contract

- **Skill-tool dispatch, single-string args.** Per
  `skills/research-and-plan/SKILL.md:140`, callers invoke /land-pr
  via `Skill: { skill: "land-pr", args: "<flags>" }`. Same-context
  recursion per `skills/research-and-plan/SKILL.md:87-105`. Therefore
  data hand-off is file-based (the result file), not via stdout.
- **No `jq` binary.** `gh ... --json` is gh's built-in formatter; we
  bash-regex its output. The standalone `jq` binary is prohibited per
  the `feedback_no_jq_in_skills` memory.
- **No `|| true`, no `2>/dev/null`** on fallible operations (with one
  documented exception: the `--pr` resume-mode metadata recovery in
  step 2, which is an explicit handled outcome).
- **No `--no-verify`** on commits.
