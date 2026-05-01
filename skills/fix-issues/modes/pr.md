# /fix-issues — PR Mode (Per-Issue)

Land each verified fix via one PR per issue with rebase, push, CI polling, and auto-merge on success.
### PR mode landing

When `LANDING_MODE == pr`, landing replaces cherry-pick with **per-issue
`/land-pr` dispatch**. Each fixed issue is handled independently: one
branch, one PR, one `.landed` marker per worktree. A failure on one
issue (rebase conflict, CI failure, PR creation error) does NOT block
the others — `/land-pr` writes that issue's `.landed` marker and the
caller loop `continue`s to the next issue.

**Auto-flag gating.** Rebase, push, PR creation, **CI polling, and the fix cycle ALL run regardless of `$AUTO`** — they're either low-risk (review-surfacing) or reversible (the fix cycle pushes commits to the feature branch, which the user can revert). Goal: by the time the user reviews the PR, it is as clean as the agent could get it.

Only the final `gh pr merge --auto --squash` call is gated on `$AUTO` — and that gate now lives inside `/land-pr`'s `pr-merge.sh` (Phase 1B WI 1.6). **Only `gh pr merge --auto --squash` is gated on `auto`.** Without `auto`, the PR settles at status `pr-ready` after CI passes (or `pr-ci-failing` after fix-cycle exhaustion) and waits for human review and merge on GitHub.

**Per-issue /land-pr dispatch.** `/fix-issues pr` no longer owns
rebase, push, PR creation, CI polling, the fix cycle, the merge call,
or the `.landed` marker write — those all move to `/land-pr` (see
`skills/land-pr/SKILL.md`). What stays in `/fix-issues pr`:

- The outer `for issue in "${FIXED_ISSUES[@]}"` loop (per-issue scope).
- Per-issue derived variables (`$BRANCH_NAME`, `$ISSUE_TITLE`,
  `$WORKTREE_PATH`).
- The PR title template `Fix #N: ISSUE_TITLE` (fix-issues-specific).
- The PR body template referencing `Fixes #N` (fix-issues-specific).
- The fix-cycle agent's `<CALLER_WORK_CONTEXT>` slot — filled with
  the issue body and the change summary.

**Loop over every fixed issue** (and any grouped issue worktrees from
Phase 2). `$FIXED_ISSUES` is the list of issue numbers whose worktrees
have verified commits on `fix/issue-NNN`.

`/fix-issues pr` customizations of the canonical pattern:
- `$LANDED_SOURCE = "fix-issues"`
- `$WORKTREE_PATH = $ISSUE_WORKTREE` (per-issue worktree)
- `$AUTO = $AUTO` (auto-merge gated on caller's `--auto` flag, passed
  through to `/land-pr` via `--auto`)
- `$ISSUE_NUM = $ISSUE_NUM` (passed through via `--issue=$ISSUE_NUM`;
  `/land-pr` writes it into the `.landed` marker's `issue:` field)
- `<CALLER_PRE_INVOKE_BODY_PREP>` = empty (per-issue body is composed
  once before the loop and never refreshed)
- `<CALLER_REBASE_CONFLICT_HANDLER>` = no agent-assisted resolution at
  per-issue scope (each issue has its own narrow worktree); break and
  let `/land-pr`'s `.landed status=conflict` marker stand
- `<DISPATCH_FIX_CYCLE_AGENT_HERE>` = issue body (`gh issue view`) +
  change summary

```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
for issue in "${FIXED_ISSUES[@]}"; do
  ISSUE_NUM="$issue"
  BRANCH_NAME="fix/issue-${ISSUE_NUM}"
  PROJECT_NAME=$(basename "$PROJECT_ROOT")
  WORKTREE_PATH="/tmp/${PROJECT_NAME}-fix-issue-${ISSUE_NUM}"
  BRANCH_SLUG="${BRANCH_NAME//\//-}"

  # Fetch issue title for the PR title (fix-issues-specific template).
  ISSUE_TITLE=$(gh issue view "$ISSUE_NUM" --json title --jq '.title')
  if [ -z "$ISSUE_TITLE" ]; then
    ISSUE_TITLE="Issue $ISSUE_NUM"
  fi
  PR_TITLE="Fix #${ISSUE_NUM}: ${ISSUE_TITLE}"

  # PR body: explicit, with Fixes #N linking. Composed once before the
  # caller loop; /land-pr writes the body only on initial PR creation,
  # so a per-issue static body is the right choice here.
  BODY_FILE="/tmp/pr-body-fix-issues-$BRANCH_SLUG.md"
  cat > "$BODY_FILE" <<BODY
Fixes #${ISSUE_NUM}

## Changes
${CHANGE_SUMMARY}

## Test plan
- [ ] Verify the fix resolves the original issue
- [ ] All existing tests pass
BODY

  # === BEGIN CANONICAL /land-pr CALLER LOOP ===
  # Per skills/land-pr/references/caller-loop-pattern.md.

  ATTEMPT=0
  MAX="${CI_MAX_ATTEMPTS:-2}"
  RESULT_FILE="/tmp/land-pr-result-$BRANCH_SLUG-$$.txt"

  LANDED_SOURCE="fix-issues"
  LAND_ARGS="--branch=$BRANCH_NAME --title=\"$PR_TITLE\" --body-file=$BODY_FILE --result-file=$RESULT_FILE --landed-source=$LANDED_SOURCE --worktree-path=$WORKTREE_PATH --issue=$ISSUE_NUM"
  [ "$AUTO" = "true" ] && LAND_ARGS="$LAND_ARGS --auto"

  while :; do
    # <CALLER_PRE_INVOKE_BODY_PREP> — empty for /fix-issues pr.
    #
    # The per-issue body is composed once before this loop (above) and
    # never refreshed. /land-pr touches the body only on initial PR
    # creation; on existing PRs (the second-iteration retry case) the
    # body is preserved as-is — fine for /fix-issues pr because the
    # body content is a static `Fixes #N` + change-summary snapshot,
    # not a progress checklist that drifts.

    # Invoke /land-pr via the Skill tool. The Skill tool loads
    # /land-pr's prose into the current (orchestrator) context — so its
    # internal bash blocks run here.
    #
    # Skill: { skill: "land-pr", args: "$LAND_ARGS" }

    if [ ! -f "$RESULT_FILE" ]; then
      echo "ERROR: /land-pr produced no result file at $RESULT_FILE for issue #$ISSUE_NUM" >&2
      break
    fi

    # SAFE allow-list parsing (per WI 1.7). Never `source`. Reading
    # line by line and dispatching on a fixed key set guarantees that
    # even maliciously-crafted values cannot reach shell evaluation.
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

    # Sidecar cleanup paths. CI_LOG_FILE intentionally NOT in the array
    # — the fix-cycle agent below reads it.
    _CLEANUP_PATHS=("${LP[CALL_ERROR_FILE]:-}" "${LP[CONFLICT_FILES_LIST]:-}")
    rm -f "$RESULT_FILE"

    case "$STATUS" in
      rebase-conflict)
        # <CALLER_REBASE_CONFLICT_HANDLER> — /fix-issues pr is per-issue
        # scope with a narrow worktree and no broader plan context, so
        # no agent-assisted resolution path. /land-pr already wrote
        # `.landed status=conflict` (with `issue: $ISSUE_NUM` per
        # --issue passthrough) and aborted the rebase — break out of
        # the inner loop and `continue` to the next issue.
        echo "/land-pr returned rebase-conflict for issue #$ISSUE_NUM. Resolve manually in $WORKTREE_PATH or re-run." >&2
        break ;;
      push-failed|create-failed|monitor-failed|merge-failed|rebase-failed)
        echo "ERROR: /land-pr STATUS=$STATUS for issue #$ISSUE_NUM REASON=${LP[REASON]:-} (see ${LP[CALL_ERROR_FILE]:-no-error-file})" >&2
        break ;;
      created|monitored|merged) ;;  # fall through to CI-status check
    esac

    case "$CI_STATUS" in
      pass|none|skipped)
        break ;;  # /land-pr already requested merge if --auto
      pending)
        break ;;  # settle at pr-ready
      not-monitored)
        break ;;  # --no-monitor was used (none of /fix-issues pr's flows do this)
      fail)
        if [ "$ATTEMPT" -ge "$MAX" ]; then
          echo "INFO: CI fix-cycle exhausted for issue #$ISSUE_NUM ($ATTEMPT/$MAX); PR settles at pr-ci-failing" >&2
          break
        fi
        # ===== <DISPATCH_FIX_CYCLE_AGENT_HERE> — /fix-issues pr customization =====
        #
        # Dispatch a fix-cycle agent at orchestrator level (NOT a nested
        # subagent — /land-pr was already invoked at orchestrator level
        # via the Skill tool; this dispatch is at the same level).
        #
        # Prompt structure follows
        # skills/land-pr/references/fix-cycle-agent-prompt-template.md.
        # /fix-issues pr fills <CALLER_WORK_CONTEXT> with the original
        # issue body (so the agent understands the user-facing problem)
        # and the change summary (so the agent knows what's already been
        # done on the branch).
        #
        # Inputs (substituted into the template):
        #   PR URL       = ${LP[PR_URL]}
        #   PR number    = ${LP[PR_NUMBER]}
        #   Branch       = $BRANCH_NAME
        #   Worktree     = $WORKTREE_PATH
        #   CI log file  = ${LP[CI_LOG_FILE]}
        #   Caller work context (CALLER_WORK_CONTEXT):
        #     Issue:        #$ISSUE_NUM — $ISSUE_TITLE
        #     Issue body:   $(gh issue view "$ISSUE_NUM" --json body --jq '.body')
        #     Change summary so far:
        #       $CHANGE_SUMMARY
        #     Recent commits on this branch:
        #       $(cd "$WORKTREE_PATH" && git log origin/main..HEAD --format='%h %s')
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
        # After the agent completes, the caller's loop increments
        # $ATTEMPT and `continue`s — /land-pr is idempotent.
        # ===========================================================
        ATTEMPT=$((ATTEMPT + 1))
        continue ;;  # re-enter loop, /land-pr is idempotent
      unknown)
        echo "WARN: CI_STATUS=unknown for issue #$ISSUE_NUM — settling at pr-ready" >&2
        break ;;
      *)
        echo "WARN: CI_STATUS='$CI_STATUS' unrecognized for issue #$ISSUE_NUM — settling at pr-ready" >&2
        break ;;
    esac
  done

  # Sidecar cleanup (after final iteration of inner loop). CI_LOG_FILE
  # intentionally NOT in the array — useful for post-mortem inspection.
  for f in "${_CLEANUP_PATHS[@]}"; do
    [ -n "$f" ] && [ -f "$f" ] && rm -f "$f"
  done

  # Body file cleanup — keep until after the loop in case a re-invocation
  # needs it (only consumed on the first iteration where the PR doesn't
  # exist yet, but defensive).
  rm -f "$BODY_FILE"
  # === END CANONICAL /land-pr CALLER LOOP ===

  echo "Issue #$ISSUE_NUM -> PR: ${PR_URL:-<not-created>} (status: ${STATUS:-unknown}, ci: ${CI_STATUS:-unknown})"
done
```

**`.landed` status values for PR mode** (`/land-pr`-owned, per its WI
1.11 canonical schema and WI 1.12 status mapping table — same as
`/run-plan`, `/commit pr`, and `/do pr`):

| Scenario | status | method | ci | pr_state |
|----------|--------|--------|----|----------|
| PR merged (auto-merge) | `landed` | `pr` | `pass`/`none`/`skipped` | `MERGED` |
| PR open, CI passed, awaiting review | `pr-ready` | `pr` | `pass`/`none`/`skipped` | `OPEN` |
| PR open, CI timed out (still running) | `pr-ready` | `pr` | `pending` | `OPEN` |
| PR open, CI failing after max attempts | `pr-ci-failing` | `pr` | `fail` | `OPEN` |
| Branch pushed, PR creation failed | `pr-failed` | `pr` | _(not set)_ | _(not set)_ |
| Rebase conflict | `conflict` | `pr` | _(not set)_ | _(not set)_ |
| `gh pr view` exhausted | `pr-state-unknown` | `pr` | varies | _(not set)_ |

In all PR mode markers, the `issue:` field records which GitHub issue
the branch resolves — populated via `--issue=$ISSUE_NUM` passthrough to
`/land-pr` (per Phase 1A WI 1.2). `/fix-report` reads this field to
group PR URLs with issue numbers in the sprint summary.

