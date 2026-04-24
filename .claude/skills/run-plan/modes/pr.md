# /run-plan — PR Landing Mode

PR landing replaces cherry-pick with push + PR creation, clean-tree rebases, CI polling with fix cycles, auto-merge request, and post-merge status upgrade.

When `LANDING_MODE == pr`, landing replaces cherry-pick with push + PR creation.

**Rebase strategy:** Rebase onto latest main only when the tree is clean.
NEVER stash + rebase. NEVER `git merge origin/main`.

**Rebase point 1: between phases (finish mode only)**

After the verification agent commits Phase N, BEFORE dispatching Phase N+1's
impl agent:

```bash
cd "$WORKTREE_PATH"
git fetch origin main
PRE_REBASE=$(git rev-parse HEAD)
git rebase origin/main
# Tree is clean (verification agent just committed). No stash needed.
if [ $? -ne 0 ]; then
  echo "REBASE CONFLICT: Phase $N changes conflict with main."

  # --- Agent-assisted conflict resolution ---
  # LLM agents can read both sides of a conflict and resolve intelligently.
  # Only bail if the conflict is genuinely too complex or resolution fails.
  #
  # 1. Check scope: how many files are conflicted?
  CONFLICT_FILES=$(git diff --name-only --diff-filter=U)
  CONFLICT_COUNT=$(echo "$CONFLICT_FILES" | grep -c .)
  echo "Conflicted files ($CONFLICT_COUNT): $CONFLICT_FILES"

  # 2. If manageable (≤5 files), attempt resolution
  if [ "$CONFLICT_COUNT" -le 5 ]; then
    echo "Attempting agent-assisted resolution..."
    # The agent reads each conflicted file, understands both sides' intent,
    # and produces a merged version. For each file:
    #   - Read the file (contains <<<<<<< / ======= / >>>>>>> markers)
    #   - Understand what "ours" (the phase work) and "theirs" (main) intended
    #   - Write a clean merged version that preserves both changes
    #   - git add <file>
    #
    # After resolving all files: git rebase --continue
    # Then run tests to verify the resolution is correct.
    #
    # If tests pass: resolution succeeded, continue normally.
    # If tests fail: the resolution was wrong. Abort and bail.
    #   git rebase --abort  (if still rebasing)
    #   Fall through to the bail block below.
    #
    # If the agent genuinely can't understand the conflict (ambiguous intent,
    # too intertwined, or not confident): don't guess. Abort immediately.
    # A wrong silent resolution is worse than bailing clearly.
  fi

  # 3. If resolution wasn't attempted (too many files) or failed:
  #    Abort the rebase and write a clear conflict marker.
  #    Check if we're still in a rebase state before aborting.
  if [ -d "$(git rev-parse --git-dir)/rebase-merge" ] || [ -d "$(git rev-parse --git-dir)/rebase-apply" ]; then
    git rebase --abort
  fi

  cat <<LANDED | bash scripts/write-landed.sh "$WORKTREE_PATH"
status: conflict
date: $(TZ=America/New_York date -Iseconds)
source: run-plan
method: pr
branch: $BRANCH_NAME
phase: $N
reason: rebase-conflict-between-phases
conflict_files: $CONFLICT_FILES
commits: $(git log main.."$BRANCH_NAME" --format='%h' | tr '\n' ' ')
LANDED

  # CLEAR communication: tell the user exactly what happened and how to resume.
  echo ""
  echo "=========================================="
  echo "REBASE CONFLICT — could not auto-resolve"
  echo "=========================================="
  echo "Phase: $N"
  echo "Conflicted files: $CONFLICT_FILES"
  echo "Worktree: $WORKTREE_PATH (clean — rebase aborted)"
  echo "Branch: $BRANCH_NAME (all phase commits intact)"
  echo ""
  echo "To resume:"
  echo "  1. cd $WORKTREE_PATH"
  echo "  2. git rebase origin/main"
  echo "  3. Resolve conflicts, git add, git rebase --continue"
  echo "  4. rm .landed"
  echo "  5. Re-run /run-plan"
  echo "=========================================="
  exit 1
fi
if [ "$(git rev-parse HEAD)" != "$PRE_REBASE" ]; then
  echo "Main moved -- re-verifying before Phase $((N+1))..."
  # Dispatch /verify-changes worktree for full re-verification.
  # The verification agent is dispatched the same way as implementation
  # agents -- prompt includes "FIRST: cd $WORKTREE_PATH".
  # Re-verification has its OWN fix cycle (max 2 attempts), INDEPENDENT
  # of the CI fix budget. If re-verification fails after its own max
  # attempts, STOP -- same as any verification failure (write report,
  # mark phase as failed).
fi
```

**Rebase point 2: before push (all PR mode runs)**

After the LAST phase's verification agent commits, before pushing:

```bash
cd "$WORKTREE_PATH"
git fetch origin main
PRE_REBASE=$(git rev-parse HEAD)
git rebase origin/main
if [ $? -ne 0 ]; then
  echo "REBASE CONFLICT: Branch conflicts with main before push."

  # --- Agent-assisted conflict resolution (same as between-phases) ---
  CONFLICT_FILES=$(git diff --name-only --diff-filter=U)
  CONFLICT_COUNT=$(echo "$CONFLICT_FILES" | grep -c .)
  echo "Conflicted files ($CONFLICT_COUNT): $CONFLICT_FILES"

  if [ "$CONFLICT_COUNT" -le 5 ]; then
    echo "Attempting agent-assisted resolution..."
    # Read each conflicted file, understand both sides, merge intelligently.
    # After resolving: git add <file>, git rebase --continue, run tests.
    # If tests pass → continue to push. If tests fail → abort and bail.
    # If not confident about the resolution → don't guess, abort immediately.
  fi

  # If resolution wasn't attempted or failed: abort and bail clearly.
  if [ -d "$(git rev-parse --git-dir)/rebase-merge" ] || [ -d "$(git rev-parse --git-dir)/rebase-apply" ]; then
    git rebase --abort
  fi

  cat <<LANDED | bash scripts/write-landed.sh "$WORKTREE_PATH"
status: conflict
date: $(TZ=America/New_York date -Iseconds)
source: run-plan
method: pr
branch: $BRANCH_NAME
reason: rebase-conflict-before-push
conflict_files: $CONFLICT_FILES
commits: $(git log main.."$BRANCH_NAME" --format='%h' | tr '\n' ' ')
LANDED

  echo ""
  echo "=========================================="
  echo "REBASE CONFLICT — could not auto-resolve"
  echo "=========================================="
  echo "Conflicted files: $CONFLICT_FILES"
  echo "Worktree: $WORKTREE_PATH (clean — rebase aborted)"
  echo "Branch: $BRANCH_NAME (all phase commits intact)"
  echo ""
  echo "To resume:"
  echo "  1. cd $WORKTREE_PATH"
  echo "  2. git rebase origin/main"
  echo "  3. Resolve conflicts, git add, git rebase --continue"
  echo "  4. rm .landed"
  echo "  5. Re-run /run-plan"
  echo "=========================================="
  exit 1
fi
if [ "$(git rev-parse HEAD)" != "$PRE_REBASE" ]; then
  echo "Main moved since last verification -- re-verifying..."
  # Dispatch /verify-changes worktree for full re-verification.
  # The verification agent's prompt includes "FIRST: cd $WORKTREE_PATH".
  # This includes tests, code review, and manual testing if UI files changed.
  # Re-verification has its OWN fix cycle (max 2 attempts), INDEPENDENT
  # of the CI fix budget. If re-verification fails after its own max
  # attempts, STOP -- same as any verification failure.
  # If re-verification passes, proceed to push.
fi
```

**Mark tracker ✅ Done on feature branch (PR mode, before push):**

PR mode has no post-landing window the orchestrator controls — auto-merge
is asynchronous. So the Done update must be made on the feature branch
**before push**, captured in the squash. Also regen `reports/plan-{slug}.md`
and `PLAN_REPORT.md` here if they need post-landing updates (strip
`[UNFINALIZED]`, add merge note).

```bash
cd "$WORKTREE_PATH"
# Edit plan file: change tracker row 🟡 → ✅ with commit hash
git add <plan-file> [reports/plan-{slug}.md PLAN_REPORT.md]
git commit -m "chore: mark phase <name> done (landed)"
```

If push/CI/auto-merge fails, the branch has optimistic Done state — fine
because it's on feature branch, not main. Main only gets Done on successful
squash-merge. Retry reuses the existing Done commit.

**Push + PR creation:**

```bash
cd "$WORKTREE_PATH"

# --- Construct PR title and body ---
# $PLAN_SLUG, $PLAN_TITLE, $CURRENT_PHASE_NUM, $CURRENT_PHASE_TITLE come from
# the plan parser (Phase 1 of /run-plan's execution).
# $FINISH_MODE is true when running in finish mode (all remaining phases).

if [ "$FINISH_MODE" = "true" ]; then
  PR_TITLE="[${PLAN_SLUG}] ${PLAN_TITLE}"
else
  PR_TITLE="[${PLAN_SLUG}] Phase ${CURRENT_PHASE_NUM}: ${CURRENT_PHASE_TITLE}"
fi

# Collect completed phases for the body
COMPLETED_PHASES=$(grep -E '^\| .* \| ✅' "$PLAN_FILE" | sed 's/|//g' | awk '{$1=$1};1' || echo "See plan file")

# The progress section is wrapped with HTML-comment markers so that Phase 4
# (Update Progress Tracking) can splice in updated progress as later phases
# land, without clobbering user-authored prose outside the markers. The
# markers are literal sentinels — do not rename them without updating the
# Phase 4 splice logic in skills/run-plan/SKILL.md.
PR_BODY="## Plan: ${PLAN_TITLE}

<!-- run-plan:progress:start -->
**Phases completed:**
${COMPLETED_PHASES}
<!-- run-plan:progress:end -->

**Report:** See \`reports/plan-${PLAN_SLUG}.md\` for details.

---
Generated by \`/run-plan\`"

# --- Push (error-check each branch; a silent push failure would make
#     downstream polling watch stale CI or hang on a branch that
#     doesn't exist on origin yet) ---
if git ls-remote --heads origin "$BRANCH_NAME" | grep -q "$BRANCH_NAME"; then
  echo "Remote branch $BRANCH_NAME already exists. Pushing updates."
  if ! git push origin "$BRANCH_NAME"; then
    echo "ERROR: git push to existing $BRANCH_NAME failed. Aborting before PR creation." >&2
    cat <<LANDED | bash scripts/write-landed.sh "$WORKTREE_PATH"
status: pr-failed
date: $(TZ=America/New_York date -Iseconds)
source: run-plan
method: pr
branch: $BRANCH_NAME
reason: push-failed-to-existing-remote
commits: $(git log main.."$BRANCH_NAME" --format='%h' | tr '\n' ' ')
LANDED
    exit 1
  fi
else
  if ! git push -u origin "$BRANCH_NAME"; then
    echo "ERROR: git push -u (first-time) failed for $BRANCH_NAME. Aborting before PR creation." >&2
    cat <<LANDED | bash scripts/write-landed.sh "$WORKTREE_PATH"
status: pr-failed
date: $(TZ=America/New_York date -Iseconds)
source: run-plan
method: pr
branch: $BRANCH_NAME
reason: push-failed-first-time
commits: $(git log main.."$BRANCH_NAME" --format='%h' | tr '\n' ' ')
LANDED
    exit 1
  fi
fi

# --- PR creation ---
EXISTING_PR=$(gh pr list --head "$BRANCH_NAME" --json number --jq '.[0].number' 2>/dev/null)
if [ -n "$EXISTING_PR" ]; then
  echo "PR #$EXISTING_PR already exists for $BRANCH_NAME. Updated with latest push."
  # Query URL defensively — a transient `gh pr view` failure here used to
  # leave PR_URL empty, which the downstream "Verify PR was created"
  # block misinterprets as "PR creation failed" and writes pr-failed
  # even though the PR really exists.
  if ! PR_URL=$(gh pr view "$EXISTING_PR" --json url --jq '.url' 2>&1); then
    echo "ERROR: could not query existing PR #$EXISTING_PR URL (gh pr view failed): $PR_URL" >&2
    echo "Branch is pushed; investigate manually. Writing .landed with pr-failed." >&2
    PR_URL=""
  fi
  PR_NUMBER="$EXISTING_PR"
else
  PR_URL=$(gh pr create \
    --title "$PR_TITLE" \
    --body "$PR_BODY" \
    --base main \
    --head "$BRANCH_NAME")
  if [ -n "$PR_URL" ]; then
    # Extract PR_NUMBER from PR_URL directly — avoids a second `gh pr view`
    # call that can independently fail and leave PR_NUMBER unset (whereas
    # PR_URL here is known-good).
    # PR_URL format: https://github.com/<owner>/<repo>/pull/<N>
    PR_NUMBER="${PR_URL##*/}"
    # Sanity-check: PR_NUMBER should be all digits.
    if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
      echo "ERROR: extracted PR_NUMBER='$PR_NUMBER' from PR_URL='$PR_URL' is not numeric." >&2
      # Fall back to gh pr view, with error capture this time.
      if ! PR_NUMBER=$(gh pr view --json number --jq '.number' 2>&1); then
        echo "ERROR: fallback gh pr view also failed: $PR_NUMBER" >&2
        PR_NUMBER=""
      fi
    fi
  fi
fi

# --- Verify PR was created ---
if [ -z "$PR_URL" ]; then
  echo "WARNING: PR creation failed. Branch pushed but PR not created."
  echo "Manual fallback: gh pr create --base main --head $BRANCH_NAME"
  cat <<LANDED | bash scripts/write-landed.sh "$WORKTREE_PATH"
status: pr-failed
date: $(TZ=America/New_York date -Iseconds)
source: run-plan
method: pr
branch: $BRANCH_NAME
pr:
commits: $(git log main.."$BRANCH_NAME" --format='%h' | tr '\n' ' ')
LANDED
  # Report and stop -- PR creation failed
fi
```

**`.landed` marker for PR mode:**

After successful push + PR creation, re-read CI config, poll CI checks, run the
fix cycle if needed, request auto-merge, and write the `.landed` marker with the
final status based on CI results.

```bash
# --- Re-read config at point of use ---
# Do NOT rely on $CONFIG_CONTENT from earlier -- context compaction may
# have lost it. Re-read the config file now.
CI_AUTO_FIX=true
CI_MAX_ATTEMPTS=2
FULL_TEST_CMD=""
CONFIG_FILE="$PROJECT_ROOT/.claude/zskills-config.json"
if [ -f "$CONFIG_FILE" ]; then
  CI_CONFIG=$(cat "$CONFIG_FILE" 2>/dev/null)
  if [[ "$CI_CONFIG" =~ \"auto_fix\"[[:space:]]*:[[:space:]]*(true|false) ]]; then
    CI_AUTO_FIX="${BASH_REMATCH[1]}"
  fi
  if [[ "$CI_CONFIG" =~ \"max_fix_attempts\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
    CI_MAX_ATTEMPTS="${BASH_REMATCH[1]}"
  fi
  if [[ "$CI_CONFIG" =~ \"full_cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    FULL_TEST_CMD="${BASH_REMATCH[1]}"
  fi
fi
```

**Skip CI when disabled:**

```bash
if [ "$CI_AUTO_FIX" = "false" ]; then
  echo "CI auto-fix disabled (ci.auto_fix: false). PR created -- CI results are the user's responsibility."
  CI_STATUS="skipped"
fi
```

**CI pre-check (avoid hang on repos with no CI):**

`gh pr checks --watch` hangs indefinitely if no checks are configured. GitHub
Actions has a registration delay (5-30s after push), so retry before concluding
there are no checks:

```bash
CHECK_COUNT=0
for _i in 1 2 3; do
  CHECK_COUNT=$(gh pr checks "$PR_NUMBER" --json name --jq 'length' 2>/dev/null || echo "0")
  [ "$CHECK_COUNT" != "0" ] && break
  sleep 10
done
if [ "$CHECK_COUNT" = "0" ]; then
  echo "No CI checks configured for this repo. Skipping CI polling."
  CI_STATUS="none"
fi
```

**CI polling:**

```bash
echo "Waiting for $CHECK_COUNT CI check(s) on PR #$PR_NUMBER..."
CI_LOG="/tmp/ci-failure-${PR_NUMBER}.txt"

# Timeout: 10 minutes. In cron mode, a hung --watch blocks the entire turn.
# Exit code 124 from timeout means "timed out" -- treat as "checks still pending".
timeout 600 gh pr checks "$PR_NUMBER" --watch 2>"$CI_LOG.stderr"
WATCH_EXIT=$?

# `gh pr checks --watch` exit code is UNRELIABLE across gh versions —
# some (observed in the CI_FIX_CYCLE_CANARY run, 2026-04-18) return 0
# even when a check concluded `fail`, making --watch useless as a
# pass/fail signal. Only trust exit 124 from `timeout(1)` to mean
# "still running, give up waiting." For every other outcome, re-check
# explicitly with `gh pr checks $PR_NUMBER` (no --watch), which DOES
# signal via exit code: 0=all pass, 1=any failure, 8=some still pending.
if [ "$WATCH_EXIT" -eq 124 ]; then
  echo "CI checks timed out after 10 minutes. Treating as pending."
  CI_STATUS="pending"
  # Write .landed with pr-ready so the next cron turn re-checks.
  # Do NOT enter the fix cycle -- checks are still running, not failing.
else
  if gh pr checks "$PR_NUMBER" >/dev/null 2>&1; then
    echo "CI checks passed."
    CI_STATUS="pass"
  else
    CHECK_RC=$?
    echo "CI checks did not pass (gh pr checks rc=$CHECK_RC). Reading failure logs..."
    CI_STATUS="fail"
    FAILED_RUN_ID=$(gh run list --branch "$BRANCH_NAME" --status failure --limit 1 \
      --json databaseId --jq '.[0].databaseId' 2>/dev/null)
    if [ -n "$FAILED_RUN_ID" ]; then
      gh run view "$FAILED_RUN_ID" --log-failed 2>&1 | head -500 > "$CI_LOG"
    fi
  fi
fi
```

Note: `gh pr checks --watch` is used WITHOUT `--fail-fast` (that flag may
not exist in all gh versions). The re-check AFTER the watch is what
actually determines pass/fail — do not rely on the watch's exit code alone.

**Timeout handling:** If `CI_STATUS` is `"pending"` (timeout exit 124), skip the
fix cycle entirely and write `.landed` with `status: pr-ready`. The next cron
turn will re-enter Phase 6, see the existing PR, and re-poll CI.

**CI failure fix cycle:**

```bash
if [ "$CI_STATUS" = "fail" ] && [ "$CI_MAX_ATTEMPTS" -gt 0 ]; then
  # Post initial CI status comment using gh api (returns comment ID).
  # gh pr comment does NOT return comment URL/ID, so we use the API directly.
  # The `|| true` preserves the assignment on gh api failure (network/auth);
  # downstream `[ -n "$COMMENT_ID" ]` guards the PATCH calls. We warn to
  # stderr so the failure is visible instead of silently losing the PR-side
  # commentary of the fix cycle.
  COMMENT_ID=$(gh api "repos/{owner}/{repo}/issues/$PR_NUMBER/comments" \
    -f body="**CI Status:** Investigating failure..." --jq '.id' 2>/dev/null || true)
  if [ -z "$COMMENT_ID" ]; then
    echo "WARNING: failed to create CI-status PR comment on #$PR_NUMBER (auth/network?) — fix cycle will not post updates" >&2
  fi

  for ATTEMPT in $(seq 1 "$CI_MAX_ATTEMPTS"); do
    echo "CI fix attempt $ATTEMPT/$CI_MAX_ATTEMPTS..."

    # Update the single status comment (edit, not append spam)
    COMMENT_BODY="**CI Fix -- Attempt $ATTEMPT/$CI_MAX_ATTEMPTS**

Failure from \`gh run view --log-failed\`:
\`\`\`
$(tail -50 "$CI_LOG" 2>/dev/null || echo "No failure log available")
\`\`\`

Attempting fix..."
    if [ -n "$COMMENT_ID" ]; then
      gh api -X PATCH "repos/{owner}/{repo}/issues/comments/$COMMENT_ID" \
        -f body="$COMMENT_BODY" 2>/dev/null \
        || echo "WARNING: failed to update CI-status PR comment on attempt $ATTEMPT (auth/network?)" >&2
    fi

    # --- Dispatch CI fix agent ---
    # Before dispatching: check agents.min_model in .claude/zskills-config.json.
    # If set, use that model or higher (ordinal: haiku=1 < sonnet=2 < opus=3).
    # Never dispatch with a lower-ordinal model than the configured minimum.
    #
    # The /run-plan ORCHESTRATOR dispatches this agent via the Agent tool.
    # The agent does NOT use isolation: "worktree" -- the worktree already
    # exists. Instead, the agent's prompt tells it to work in $WORKTREE_PATH.
    #
    # Tracking: The worktree has .zskills-tracked (written by the orchestrator
    # in 3b.1), so the tracking hooks allow commits. The fix agent's
    # transcript will contain test commands (it runs tests before committing),
    # satisfying the test gate.
    #
    # Agent prompt (inline, not a skill):
    #
    #   CI checks failed on PR #$PR_NUMBER for branch $BRANCH_NAME.
    #   The failure log is at $CI_LOG -- read it to understand what failed.
    #
    #   FIRST: cd $WORKTREE_PATH
    #   All work happens in that directory. Do not work in any other directory.
    #
    #   Steps:
    #   1. Read $CI_LOG. Identify the failure type:
    #      - Test failure -> find the failing test, read the source, fix the code
    #      - Build error -> fix the compilation/bundling issue
    #      - Lint error -> fix the style violation
    #      - Environment issue -> may not be fixable, report and stop
    #   2. Make the minimal fix. Do not refactor or improve unrelated code.
    #   3. Run tests locally to verify the fix:
    #      - If FULL_TEST_CMD is set:
    #        TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
    #        mkdir -p "$TEST_OUT"
    #        "$FULL_TEST_CMD > "$TEST_OUT/.test-results.txt" 2>&1"
    #      - If FULL_TEST_CMD is empty: look for package.json scripts (npm test),
    #        or test files matching common patterns. If no test command can be
    #        determined, skip local testing and note it in the commit message.
    #      Read "$TEST_OUT/.test-results.txt" to check for failures.
    #   4. If tests pass, commit with message:
    #      "fix: address CI failure -- <short description of what was fixed>"
    #   5. If tests fail on the same error after one fix attempt, STOP.
    #      Do not thrash. Report what you tried and what failed.
    #
    #   Do NOT:
    #   - Weaken tests to make them pass
    #   - Skip the local test run
    #   - Touch code unrelated to the CI failure
    #   - Use git add . (stage specific files by name)

    # After fix agent completes, push to branch (auto-updates PR, re-triggers CI).
    # Error-check: if push fails (auth timeout, rate-limit, network), the
    # subsequent poll would wait on stale CI for 10 min and then falsely
    # conclude a failure. Bail loudly instead.
    cd "$WORKTREE_PATH"
    if ! git push origin "$BRANCH_NAME"; then
      echo "ERROR: fix-cycle push failed on attempt $ATTEMPT — aborting CI fix cycle." >&2
      CI_STATUS="fail"
      break
    fi

    # CI registration delay: GitHub needs 5-30s to register new check runs
    # after a push. Run the same pre-check retry loop before --watch to avoid
    # watching stale checks from the previous push.
    echo "Waiting for CI to register new checks after push..."
    for _j in 1 2 3; do
      NEW_CHECK_COUNT=$(gh pr checks "$PR_NUMBER" --json name --jq 'length' 2>/dev/null || echo "0")
      [ "$NEW_CHECK_COUNT" != "0" ] && break
      sleep 10
    done

    echo "Waiting for CI re-check..."
    timeout 600 gh pr checks "$PR_NUMBER" --watch 2>"$CI_LOG.stderr"
    WATCH_EXIT=$?
    # See the pass/fail-determination block above: `--watch`'s exit
    # code is unreliable; re-check explicitly with `gh pr checks`.
    if [ "$WATCH_EXIT" -eq 124 ]; then
      echo "CI checks timed out after fix attempt $ATTEMPT. Treating as pending."
      CI_STATUS="pending"
      break
    fi
    if gh pr checks "$PR_NUMBER" >/dev/null 2>&1; then
      echo "CI checks passed after fix attempt $ATTEMPT."
      CI_STATUS="pass"
      break
    fi
    # Re-read failure logs for next attempt
    FAILED_RUN_ID=$(gh run list --branch "$BRANCH_NAME" --status failure --limit 1 \
      --json databaseId --jq '.[0].databaseId' 2>/dev/null)
    if [ -n "$FAILED_RUN_ID" ]; then
      gh run view "$FAILED_RUN_ID" --log-failed 2>&1 | head -500 > "$CI_LOG"
    fi
  done

  # Final comment update
  if [ "$CI_STATUS" = "pass" ]; then
    FINAL_BODY="**CI Passed** after fix attempt $ATTEMPT. Ready for review."
  else
    FINAL_BODY="**CI Fix Exhausted** ($CI_MAX_ATTEMPTS attempts)

CI is still failing. Manual intervention needed.

Last failure:
\`\`\`
$(tail -50 "$CI_LOG" 2>/dev/null || echo "No failure log available")
\`\`\`"
  fi
  if [ -n "$COMMENT_ID" ]; then
    gh api -X PATCH "repos/{owner}/{repo}/issues/comments/$COMMENT_ID" \
      -f body="$FINAL_BODY" 2>/dev/null \
      || echo "WARNING: failed to post final CI-status PR comment (auth/network?)" >&2
  fi
fi
```

**Auto-merge and `.landed` upgrade:**

After CI resolution, request auto-merge and upgrade the `.landed` marker:

```bash
# --- Auto-merge: request merge when CI passes ---
# gh pr merge --auto --squash requires that auto-merge is enabled in the
# GitHub repo settings (Settings > General > Allow auto-merge). It is OFF
# by default. If not enabled, `--auto` exits non-zero with
# "Auto merge is not allowed for this repository". That's an EXPECTED
# fallback (PR stays open, agent writes status: pr-ready, user merges
# manually). Any OTHER non-zero stderr — auth, network, rate-limit, PR
# already merged, etc. — is an unexpected failure we want visible.
# So: capture stderr, inspect it, suppress only the documented expected
# error, warn loudly on anything else.
if [ "$CI_STATUS" = "pass" ] || [ "$CI_STATUS" = "none" ] || [ "$CI_STATUS" = "skipped" ]; then
  MERGE_ERR=$(gh pr merge "$PR_NUMBER" --auto --squash 2>&1 >/dev/null) || true
  if [ -n "$MERGE_ERR" ]; then
    if echo "$MERGE_ERR" | grep -qiE "auto[- ]merge is not allowed"; then
      : # expected — repo doesn't have auto-merge enabled; fall through to pr-ready
    else
      echo "WARNING: gh pr merge --auto failed with unexpected error: $MERGE_ERR" >&2
    fi
  fi
  # Give GitHub a moment to process the merge
  sleep 5
  # Distinguish "call failed" from "PR is OPEN". If the API call fails
  # (network / auth / rate-limit), retry up to 3 times with 2s/4s backoff
  # (6s max). On total failure, record UNKNOWN and propagate
  # pr-state-unknown into .landed so the state-loss is visible and
  # actionable — downstream tooling can detect the literal string.
  PR_STATE="UNKNOWN"
  for attempt in 1 2 3; do
    if STATE_OUT=$(gh pr view "$PR_NUMBER" --json state --jq '.state' 2>&1); then
      PR_STATE="$STATE_OUT"
      break
    fi
    echo "WARN: gh pr view attempt $attempt failed: $STATE_OUT" >&2
    [ $attempt -lt 3 ] && sleep $((attempt * 2))
  done
  if [ "$PR_STATE" = "UNKNOWN" ]; then
    echo "ERROR: gh pr view failed 3 times for PR #$PR_NUMBER. Recording pr-state-unknown." >&2
    LANDED_STATUS="pr-state-unknown"
  fi
else
  PR_STATE="OPEN"
fi

# --- Determine .landed status ---
# Preserve pr-state-unknown from the retry loop above — it takes
# precedence over CI/PR-state derived statuses because the underlying
# PR state is unknown and must not be silently reclassified.
if [ "${LANDED_STATUS:-}" = "pr-state-unknown" ]; then
  : # keep LANDED_STATUS=pr-state-unknown
elif [ "$CI_STATUS" = "pending" ]; then
  # Timeout: checks still running. Write pr-ready so next cron turn re-checks.
  LANDED_STATUS="pr-ready"
elif [ "$CI_STATUS" = "fail" ]; then
  LANDED_STATUS="pr-ci-failing"
elif [ "$PR_STATE" = "MERGED" ]; then
  LANDED_STATUS="landed"
else
  # PR is open -- either awaiting required reviews, or auto-merge
  # not supported. Agent's work is done either way.
  LANDED_STATUS="pr-ready"
fi

# --- Upgrade .landed marker ---
cat <<LANDED | bash scripts/write-landed.sh "$WORKTREE_PATH"
status: $LANDED_STATUS
date: $(TZ=America/New_York date -Iseconds)
source: run-plan
method: pr
branch: $BRANCH_NAME
pr: $PR_URL
ci: $CI_STATUS
pr_state: $PR_STATE
commits: $(git log main.."$BRANCH_NAME" --format='%h' | tr '\n' ' ')
LANDED

# --- Cleanup on merge ---
# When PR was merged (status: landed), call land-phase.sh to remove the worktree.
# The work is on main via the merge -- the worktree is no longer needed.
if [ "$LANDED_STATUS" = "landed" ]; then
  bash scripts/land-phase.sh "$WORKTREE_PATH"
fi
```

**`.landed` status values for PR mode:**

| Scenario | status | method | ci | pr_state |
|----------|--------|--------|----|----------|
| PR merged (auto-merge) | `landed` | `pr` | `pass`/`none`/`skipped` | `MERGED` |
| PR open, CI passed, awaiting review | `pr-ready` | `pr` | `pass`/`none`/`skipped` | `OPEN` |
| PR open, CI timed out (still running) | `pr-ready` | `pr` | `pending` | `OPEN` |
| PR open, CI failing after max attempts | `pr-ci-failing` | `pr` | `fail` | `OPEN` |
| Branch pushed, PR creation failed | `pr-failed` | `pr` | _(not set)_ | _(not set)_ |
| Rebase conflict | `conflict` | `pr` | _(not set)_ | _(not set)_ |

### Post-landing tracking
