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
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)

# Sprint-level fulfilled.fix-issues.$SPRINT_ID start-marker (Plan
# LAND_PR_BYPASS_HARDENING Phase 2). Written ONCE at sprint start
# (i.e., at the top of the per-issue loop flow); finalized at sprint
# end via explicit-finalize based on $SPRINT_OUTCOME below. Variables
# $PIPELINE_ID and $SPRINT_ID are presumed set by the "Sprint identity"
# section at skills/fix-issues/modes/sprint.md:122-126.
NOW_ISO=$(TZ="${TIMEZONE:-UTC}" date -Iseconds)
mkdir -p "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
cat > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/fulfilled.fix-issues.$SPRINT_ID" <<MARK
status: started
date: $NOW_ISO
skill: fix-issues
mode: pr
sprint: $SPRINT_ID
MARK

# Per-issue land-outcome accumulator → sprint-level $SPRINT_OUTCOME.
# Any per-issue `failed` outcome makes the sprint `failed`; all
# `complete` → `complete`.
SPRINT_OUTCOME=complete

for issue in "${FIXED_ISSUES[@]}"; do
  ISSUE_NUM="$issue"
  BRANCH_NAME="fix/issue-${ISSUE_NUM}"
  PROJECT_NAME=$(basename "$PROJECT_ROOT")
  WORKTREE_PATH="/tmp/${PROJECT_NAME}-fix-issue-${ISSUE_NUM}"
  BRANCH_SLUG="${BRANCH_NAME//\//-}"

  # Per-issue requires.land-pr.<ISSUE_NUM> (drives hook STOP-message
  # Pattern 2 + dashboard for this issue's PR land).
  ISSUE_NOW_ISO=$(TZ="${TIMEZONE:-UTC}" date -Iseconds)
  cat > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/requires.land-pr.$ISSUE_NUM" <<MARK
skill: land-pr
parent: fix-issues
id: $ISSUE_NUM
branch: $BRANCH_NAME
date: $ISSUE_NOW_ISO
MARK

  # Per-issue LAND_OUTCOME tracker (R-5-8 default).
  LAND_OUTCOME=__init__

  # Fetch issue title for the PR title (fix-issues-specific template).
  ISSUE_TITLE=$(gh issue view "$ISSUE_NUM" --json title --jq '.title')
  if [ -z "$ISSUE_TITLE" ]; then
    ISSUE_TITLE="Issue $ISSUE_NUM"
  fi
  PR_TITLE="Fix #${ISSUE_NUM}: ${ISSUE_TITLE}"

  # PR body: explicit, with Fixes #N linking. Composed once before the
  # caller loop; /land-pr writes the body only on initial PR creation,
  # so a per-issue static body is the right choice here.
  #
  # Per-issue change summary: bullet list of commit subjects added to the
  # feature branch beyond origin/main. Tolerant of empty (no commits yet)
  # and of detached HEAD (worktree at branch tip).
  CHANGE_SUMMARY=$(cd "$WORKTREE_PATH" && git log origin/main..HEAD --format='- %s' 2>/dev/null)
  CHANGE_SUMMARY="${CHANGE_SUMMARY:-_(no commits yet — body will be updated on first push)_}"
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
  LAND_ARGS="--branch=$BRANCH_NAME --title=\"$PR_TITLE\" --body-file=$BODY_FILE --result-file=$RESULT_FILE --landed-source=$LANDED_SOURCE --worktree-path=$WORKTREE_PATH --issue=$ISSUE_NUM --tracking-id=$ISSUE_NUM"
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
      LAND_OUTCOME=monitor-failed
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
        CONFLICT_FILES_LIST|CALL_ERROR_FILE|REBASE_STDERR_FILE)
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
    _CLEANUP_PATHS=("${LP[CALL_ERROR_FILE]:-}" "${LP[CONFLICT_FILES_LIST]:-}" "${LP[REBASE_STDERR_FILE]:-}")
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
        LAND_OUTCOME=$STATUS
        break ;;
      push-failed|create-failed|monitor-failed|merge-failed|rebase-failed)
        echo "ERROR: /land-pr STATUS=$STATUS for issue #$ISSUE_NUM REASON=${LP[REASON]:-} (see ${LP[CALL_ERROR_FILE]:-no-error-file})" >&2
        LAND_OUTCOME=$STATUS
        break ;;
      behind-thrash)
        # Step 6b exhausted auto-rebase budget (issue #624). pr-ready
        # surface but discriminator preserved in $LAND_OUTCOME.
        echo "/land-pr STATUS=behind-thrash for issue #$ISSUE_NUM — auto-rebase budget exhausted, manual rebase needed" >&2
        LAND_OUTCOME=$STATUS
        break ;;
      auto-rebase-conflict|auto-rebase-blocked)
        # Step 6b auto-rebase merge-conflicted, or mergeStateStatus
        # settled at BLOCKED for non-CI reasons. Issue #624 — must NOT
        # be silently coerced to pr-ready by the CI-status check below.
        echo "/land-pr STATUS=$STATUS for issue #$ISSUE_NUM REASON=${LP[REASON]:-} — manual intervention needed" >&2
        LAND_OUTCOME=$STATUS
        break ;;
      created|monitored|merged) ;;  # fall through to CI-status check
      *)
        # Unknown STATUS — fail loud rather than coerce via CI-status
        # (issue #624 — closes the silent fall-through gap).
        echo "WARN: unrecognized /land-pr STATUS=$STATUS for issue #$ISSUE_NUM — settling at unknown-status" >&2
        LAND_OUTCOME="unknown-status-$STATUS"
        break ;;
    esac

    case "$CI_STATUS" in
      pass|none|skipped)
        if [ "${LP[PR_STATE]:-}" = "MERGED" ]; then
          LAND_OUTCOME=merged
        else
          LAND_OUTCOME=pr-ready
        fi
        break ;;  # /land-pr already requested merge if --auto
      pending)
        LAND_OUTCOME=pr-ready
        break ;;  # settle at pr-ready
      not-monitored)
        LAND_OUTCOME=created
        break ;;  # --no-monitor was used (none of /fix-issues pr's flows do this)
      fail)
        if [ "$ATTEMPT" -ge "$MAX" ]; then
          echo "INFO: CI fix-cycle exhausted for issue #$ISSUE_NUM ($ATTEMPT/$MAX); PR settles at pr-ci-failing" >&2
          LAND_OUTCOME=pr-ci-failing
          break
        fi
        # ===== <DISPATCH_FIX_CYCLE_AGENT_HERE> — /fix-issues pr customization =====
        #
        # Dispatch a fix-cycle agent at orchestrator level (NOT a nested
        # subagent — /land-pr was already invoked at orchestrator level
        # via the Skill tool; this dispatch is at the same level).
        #
        # Dispatch shape: use the `Agent` tool with subagent_type: "implementer".
        # This inherits the Layer 0 Bash-timeout extension
        # (.claude/agents/implementer.md + CLAUDE.md "Verifier-cannot-run rule")
        # so the fix-cycle agent's long test runs don't trigger the
        # bg+Monitor stall pattern.
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
        LAND_OUTCOME=pr-ready
        break ;;
      *)
        echo "WARN: CI_STATUS='$CI_STATUS' unrecognized for issue #$ISSUE_NUM — settling at pr-ready" >&2
        LAND_OUTCOME=pr-ready
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

  # Per-issue explicit-finalize (Plan LAND_PR_BYPASS_HARDENING Phase 2).
  # Remove the per-issue requires.land-pr.<ISSUE_NUM> marker regardless
  # of LAND_OUTCOME. Update sprint-level $SPRINT_OUTCOME based on this
  # issue's outcome (any non-success → sprint failed).
  rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/requires.land-pr.$ISSUE_NUM"

  # Release the claim based on per-issue LAND_OUTCOME (plan W2.6a — round 2
  # re-anchor R2.3 — keyed on $LAND_OUTCOME, not $STATUS).
  # Hold on `created` because the PR is in flight on the remote;
  # releasing would let a concurrent pipeline open a duplicate PR. The
  # claim is released when the PR resolves (merged/pr-ready/failed) on a
  # later fire; a stalled-PR claim is cleared manually via `claim-issue.sh
  # release` (no TTL auto-reap — same precedent as #684 for plan claims).
  # `monitored` is NOT a reachable LAND_OUTCOME value (it is a STATUS that
  # falls through to the CI_STATUS case where LAND_OUTCOME resolves to one
  # of {merged, pr-ready, created, pr-ci-failing}); it would be dead code
  # if listed in the case, so it is intentionally absent. (DA3.1.)
  CLAIM_HELPER="$CLAUDE_PROJECT_DIR/.claude/skills/fix-issues/scripts/claim-issue.sh"
  case "$LAND_OUTCOME" in
    merged|pr-ready|pr-ci-failing|rebase-conflict|rebase-failed|push-failed|create-failed|monitor-failed|merge-failed)
      bash "$CLAIM_HELPER" release "$ISSUE_NUM" --require-pipeline "$PIPELINE_ID" \
        || echo "fix-issues: claim release for #$ISSUE_NUM returned non-zero (continuing)" >&2 ;;
    created)
      echo "fix-issues: holding claim for #$ISSUE_NUM (LAND_OUTCOME=created — PR is in flight); claim is released when the PR resolves on a later fire" >&2 ;;
    *)
      echo "fix-issues: unknown LAND_OUTCOME=$LAND_OUTCOME for #$ISSUE_NUM; defaulting to HOLD" >&2 ;;
  esac

  case "$LAND_OUTCOME" in
    merged|created|pr-ready) ;;  # success-equivalent; sprint outcome unchanged
    *) SPRINT_OUTCOME=failed ;;
  esac

  echo "Issue #$ISSUE_NUM -> PR: ${PR_URL:-<not-created>} (status: ${STATUS:-unknown}, ci: ${CI_STATUS:-unknown})"
done

# Sprint-level explicit-finalize: rewrite fulfilled.fix-issues.$SPRINT_ID
# from `status: started` to `status: $SPRINT_OUTCOME` (one of {complete,
# failed}). Sprint-level fulfillment signals "all issues' PR-land loops
# have completed" regardless of per-issue outcome.
sed -i "s/^status: started$/status: $SPRINT_OUTCOME/" \
  "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/fulfilled.fix-issues.$SPRINT_ID"
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

