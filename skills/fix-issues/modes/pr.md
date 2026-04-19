# /fix-issues — PR Mode (Per-Issue)

Land each verified fix via one PR per issue with rebase, push, CI polling, and auto-merge on success.
### PR mode landing

When `LANDING_MODE == pr`, landing replaces cherry-pick with **per-issue
rebase + push + PR creation + CI + auto-merge**. Each fixed issue is
handled independently: one branch, one PR, one `.landed` marker per
worktree. A failure on one issue (rebase conflict, CI failure, PR
creation error) does NOT block the others — mark that issue's status
and continue to the next.

**Loop over every fixed issue** (and any grouped issue worktrees from
Phase 2). `$FIXED_ISSUES` is the list of issue numbers whose worktrees
have verified commits on `fix/issue-NNN`.

**Rebase before push** (same pattern as `/run-plan` PR mode rebase point 2,
but per issue — fix-issues is single-phase per issue, so only one rebase
point is needed):

```bash
cd "$WORKTREE_PATH"
git fetch origin main
PRE_REBASE=$(git rev-parse HEAD)
git rebase origin/main
if [ $? -ne 0 ]; then
  # Abort and mark this issue as conflict. Continue to the next issue.
  if [ -d "$(git rev-parse --git-dir)/rebase-merge" ] || \
     [ -d "$(git rev-parse --git-dir)/rebase-apply" ]; then
    git rebase --abort
  fi
  echo "REBASE CONFLICT for issue #$ISSUE_NUM."
  cat <<LANDED | bash scripts/write-landed.sh "$WORKTREE_PATH"
status: conflict
date: $(TZ=America/New_York date -Iseconds)
source: fix-issues
method: pr
branch: $BRANCH_NAME
issue: $ISSUE_NUM
reason: rebase-conflict
LANDED
  continue  # Move to next issue
fi
if [ "$(git rev-parse HEAD)" != "$PRE_REBASE" ]; then
  echo "Main moved -- re-verifying issue #$ISSUE_NUM before push..."
  # Dispatch /verify-changes worktree re-verification.
  # Agent prompt includes "FIRST: cd $WORKTREE_PATH".
  # Re-verification has its own fix cycle (max 2 attempts), independent
  # of the CI fix budget. If re-verification fails after its own max
  # attempts, mark the issue as pr-failed and move on.
fi
```

**Push + PR creation (per issue):**

```bash
for issue in "${FIXED_ISSUES[@]}"; do
  ISSUE_NUM="$issue"
  BRANCH_NAME="fix/issue-${ISSUE_NUM}"
  PROJECT_NAME=$(basename "$PROJECT_ROOT")
  WORKTREE_PATH="/tmp/${PROJECT_NAME}-fix-issue-${ISSUE_NUM}"

  # Fetch issue title for the PR title
  ISSUE_TITLE=$(gh issue view "$ISSUE_NUM" --json title --jq '.title' 2>/dev/null || echo "Issue $ISSUE_NUM")

  cd "$WORKTREE_PATH"

  # Push (new or update)
  if git ls-remote --heads origin "$BRANCH_NAME" | grep -q "$BRANCH_NAME"; then
    echo "Remote branch $BRANCH_NAME already exists. Pushing updates."
    git push origin "$BRANCH_NAME"
  else
    git push -u origin "$BRANCH_NAME"
  fi

  # Existing PR? Update, don't duplicate.
  EXISTING_PR=$(gh pr list --head "$BRANCH_NAME" --json number --jq '.[0].number' 2>/dev/null)
  if [ -n "$EXISTING_PR" ]; then
    PR_URL=$(gh pr view "$EXISTING_PR" --json url --jq '.url')
    PR_NUMBER="$EXISTING_PR"
  else
    PR_URL=$(gh pr create \
      --title "Fix #${ISSUE_NUM}: ${ISSUE_TITLE}" \
      --body "$(cat <<EOF
Fixes #${ISSUE_NUM}

## Changes
${CHANGE_SUMMARY}

## Test plan
- [ ] Verify the fix resolves the original issue
- [ ] All existing tests pass
EOF
)" \
      --base main \
      --head "$BRANCH_NAME")
    if [ -n "$PR_URL" ]; then
      PR_NUMBER=$(gh pr view --json number --jq '.number')
    fi
  fi

  # If PR creation failed, write pr-failed marker and continue.
  if [ -z "$PR_URL" ]; then
    echo "WARNING: PR creation failed for issue #$ISSUE_NUM. Branch pushed but PR not created."
    cat <<LANDED | bash scripts/write-landed.sh "$WORKTREE_PATH"
status: pr-failed
date: $(TZ=America/New_York date -Iseconds)
source: fix-issues
method: pr
branch: $BRANCH_NAME
issue: $ISSUE_NUM
pr:
commits: $(git log main.."$BRANCH_NAME" --format='%h' | tr '\n' ' ')
LANDED
    continue
  fi

  # --- CI check + auto-merge: same pattern as /run-plan 3b-iii ---
  # See skills/run-plan/modes/pr.md "PR mode landing" for the canonical
  # implementation: config re-read, pre-check retry, polling, fix cycle,
  # auto-merge, .landed upgrade.
  #
  # Differences from /run-plan PR mode:
  #   - source: "fix-issues" (not "run-plan")
  #   - .landed marker includes `issue: $ISSUE_NUM`
  #   - `timeout 300` per issue (NOT 600) to avoid serial accumulation
  #     across N issues. If CI doesn't resolve in 5 min for a given issue,
  #     write status: pr-ready and move on. The next cron turn or the
  #     user re-checks.
  #
  # Parallel optimization (future): if the orchestrator can dispatch
  # sub-agents, each issue's CI polling can run in parallel. Not required
  # for initial implementation.

  # --- .landed marker (per issue) ---
  # $LANDED_STATUS, $CI_STATUS, $PR_STATE come from the CI/auto-merge block.
  cat <<LANDED | bash scripts/write-landed.sh "$WORKTREE_PATH"
status: $LANDED_STATUS
date: $(TZ=America/New_York date -Iseconds)
source: fix-issues
method: pr
branch: $BRANCH_NAME
pr: $PR_URL
ci: $CI_STATUS
pr_state: $PR_STATE
issue: $ISSUE_NUM
commits: $(git log main.."$BRANCH_NAME" --format='%h' | tr '\n' ' ')
LANDED

  echo "Issue #$ISSUE_NUM -> PR: $PR_URL (status: $LANDED_STATUS)"

  # Cleanup on merge: same as /run-plan PR mode -- if status is `landed`
  # (PR merged), call land-phase.sh to remove the worktree.
  if [ "$LANDED_STATUS" = "landed" ]; then
    bash scripts/land-phase.sh "$WORKTREE_PATH"
  fi
done
```

**`.landed` status values for PR mode** (same as `/run-plan`):

| Scenario | status | method | ci | pr_state |
|----------|--------|--------|----|----------|
| PR merged (auto-merge) | `landed` | `pr` | `pass`/`none`/`skipped` | `MERGED` |
| PR open, CI passed, awaiting review | `pr-ready` | `pr` | `pass`/`none`/`skipped` | `OPEN` |
| PR open, CI timed out (still running) | `pr-ready` | `pr` | `pending` | `OPEN` |
| PR open, CI failing after max attempts | `pr-ci-failing` | `pr` | `fail` | `OPEN` |
| Branch pushed, PR creation failed | `pr-failed` | `pr` | _(not set)_ | _(not set)_ |
| Rebase conflict | `conflict` | `pr` | _(not set)_ | _(not set)_ |

In all PR mode markers, the `issue:` field records which GitHub issue the
branch resolves. `/fix-report` reads this field to group PR URLs with
issue numbers in the sprint summary.

