# /run-plan — PR Landing Mode

PR landing replaces cherry-pick with push + PR creation, clean-tree rebases, CI polling with fix cycles, auto-merge request, and post-merge status upgrade.

When `LANDING_MODE == pr`, landing replaces cherry-pick with push + PR creation.

**Rebase strategy:** Rebase onto latest main only when the tree is clean.
NEVER stash + rebase. NEVER `git merge origin/main`.

**Rebase point 1: between phases (finish mode only)**

After the verification agent commits Phase N, BEFORE dispatching Phase N+1's
impl agent:

```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
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

  cat <<LANDED | bash "$CLAUDE_PROJECT_DIR/.claude/skills/commit/scripts/write-landed.sh" "$WORKTREE_PATH"
status: conflict
date: $(TZ="${TIMEZONE:-UTC}" date -Iseconds)
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
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
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

  cat <<LANDED | bash "$CLAUDE_PROJECT_DIR/.claude/skills/commit/scripts/write-landed.sh" "$WORKTREE_PATH"
status: conflict
date: $(TZ="${TIMEZONE:-UTC}" date -Iseconds)
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

**PR title and body construction (caller-owned):**

`/run-plan` constructs the PR title and writes the body to a temp file BEFORE
invoking `/land-pr`. The body file is consumed by `/land-pr`'s
`pr-push-and-create.sh` on initial PR creation. On subsequent phases (existing
PR detected before the loop), `/run-plan` splices the marker-enclosed progress
section into the live PR body via `gh pr edit` — `/land-pr` does NOT touch the
body on existing PRs, preserving any user-added review notes outside the
markers.

```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
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

# Write body to a temp file — /land-pr's --body-file is required and must
# be a non-empty regular file. Per-PLAN_SLUG path so concurrent pipelines
# don't collide.
BODY_FILE="/tmp/pr-body-${PLAN_SLUG}.md"
printf '%s\n' "$PR_BODY" > "$BODY_FILE"
```

**`/land-pr` dispatch (caller loop):**

`/run-plan` no longer owns push, PR creation, CI polling, fix-cycle, auto-merge,
or the `.landed` marker for the success / push-failed / CI-failing paths.
Those move to `/land-pr` (see `skills/land-pr/SKILL.md`). `/run-plan`'s
remaining responsibilities here are:

1. Per-iteration body splice on existing PRs (caller-owned per WI 2.1; the
   bash-regex `BASH_REMATCH` splice at `skills/run-plan/SKILL.md:1715-1745`
   stays as the source of truth and is invoked from
   `<CALLER_PRE_INVOKE_BODY_PREP>`).
2. Agent-assisted rebase-conflict resolution when `STATUS=rebase-conflict`
   AND conflict-files count ≤ 5 (WI 2.3).
3. Fix-cycle agent dispatch with plan context when `CI_STATUS=fail` and
   `$ATTEMPT < $MAX` (WI 2.4).
4. The pre-`/land-pr` "rebase-conflict-too-many-files" `.landed` write
   (already handled by the rebase points 1 and 2 blocks above; `/run-plan`
   does NOT write `.landed` for any other path — `/land-pr` does).

**ADAPTIVE_CRON_BACKOFF Mode A interaction (per WI 2.5a):** while the loop
below is running, `/land-pr`'s synchronous CI monitoring (`pr-monitor.sh`,
default 600 s) and the wrapping fix-cycle (up to ~10 min on a 2-attempt cycle)
keep this orchestrator turn open. Cron `*/1` fires arriving in that window
hit `/run-plan`'s Step 0 pre-flight, increment the per-phase
`in-progress-defers.<phase>` counter, and step the cadence down at boundary
fires `C+1 ∈ {1, 10, 16, 26}`. The phase still finishes correctly — Step 0
defers, the original turn writes `.landed` via `/land-pr`. No code change
needed here; the adaptive machinery (`SKILL.md:439-573`) is correct by design.

```bash
# === BEGIN CANONICAL /land-pr CALLER LOOP ===
# Per skills/land-pr/references/caller-loop-pattern.md.

ATTEMPT=0
MAX="${CI_MAX_ATTEMPTS:-2}"
# Sanitize $BRANCH_NAME for use in /tmp paths — branch names commonly
# contain `/` (feat/x, smoke/y), which would create unintended subdirs.
BRANCH_SLUG="${BRANCH_NAME//\//-}"
RESULT_FILE="/tmp/land-pr-result-$BRANCH_SLUG-$$.txt"

# /run-plan customizations of the canonical pattern:
#   $LANDED_SOURCE = "run-plan"
#   $WORKTREE_PATH = the per-phase PR-mode worktree
#   $AUTO          = "true" when /run-plan was invoked with `auto` finish-mode
#   $BODY_FILE     = constructed above
#   $BRANCH_NAME   = the per-phase or per-plan feature branch
#   $PR_TITLE      = constructed above
LANDED_SOURCE="run-plan"

while :; do
  # <CALLER_PRE_INVOKE_BODY_PREP> — per WI 2.1
  #
  # When a PR already exists for $BRANCH_NAME (subsequent phases in finish
  # mode), splice the progress section into the live PR body BEFORE
  # invoking /land-pr. /land-pr does NOT touch the body on existing PRs,
  # so this is the caller's only chance to refresh the progress checklist.
  #
  # The splice implementation is the bash-regex (`BASH_REMATCH`) splice
  # owned by Phase 4 (Update Progress Tracking) at
  # skills/run-plan/SKILL.md:1715-1745. It is the source of truth and is
  # NOT duplicated here — Phase 4 already runs before Phase 6's caller
  # loop on every phase iteration where a PR already exists.
  #
  # First-phase invocation (no PR yet): no body splice needed; $BODY_FILE
  # already includes the markers, /land-pr's pr-push-and-create.sh
  # consumes it on initial PR creation.
  #
  # Recovery paths (per WI 2.1; all gracefully degrade — none escalate to
  # `.landed conflict` because the feature-branch plan-tracker commit is
  # the source of truth and the PR body is a convenience surface):
  #   - gh-pr-view-failed: NOTICE, retry once, NOTICE-and-skip on second fail.
  #   - body-markers-missing: NOTICE-and-skip ("expected for PRs not opened
  #     by /run-plan PR mode"); design property at SKILL.md:1758-1761.
  #   - gh-pr-edit-failed: WARN-and-continue.

  # Build /land-pr arg vector. --body-file is required; --auto and
  # --worktree-path are conditional.
  LAND_ARGS="--branch=$BRANCH_NAME --title=\"$PR_TITLE\" --body-file=$BODY_FILE --result-file=$RESULT_FILE --landed-source=$LANDED_SOURCE"
  [ -n "$WORKTREE_PATH" ] && LAND_ARGS="$LAND_ARGS --worktree-path=$WORKTREE_PATH"
  [ "$AUTO" = "true" ] && LAND_ARGS="$LAND_ARGS --auto"

  # Invoke /land-pr via the Skill tool. The Skill tool loads /land-pr's
  # prose into the current (orchestrator) context — so its internal bash
  # blocks run here, and any agent dispatches inside it (none planned)
  # would be at orchestrator level too. After /land-pr's procedure
  # completes, $RESULT_FILE is populated.
  #
  # Skill: { skill: "land-pr", args: "$LAND_ARGS" }

  if [ ! -f "$RESULT_FILE" ]; then
    echo "ERROR: /land-pr produced no result file at $RESULT_FILE" >&2
    exit 1
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

  # Sidecar cleanup paths (per DA1-12, DA2-11). CI_LOG_FILE is intentionally
  # NOT in the array — the fix-cycle agent below reads it.
  _CLEANUP_PATHS=("${LP[CALL_ERROR_FILE]:-}" "${LP[CONFLICT_FILES_LIST]:-}")
  rm -f "$RESULT_FILE"

  case "$STATUS" in
    rebase-conflict)
      # <CALLER_REBASE_CONFLICT_HANDLER> — per WI 2.3
      #
      # /land-pr's pr-rebase.sh aborted the rebase, leaving a clean tree.
      # Read CONFLICT_FILES_LIST sidecar to count files. If ≤ 5, dispatch
      # an orchestrator-level (NOT nested) agent that runs `git rebase
      # origin/main` itself in $WORKTREE_PATH, resolves conflicts, and
      # signals success. Then `continue` the loop — /land-pr's next
      # rebase will be a no-op since the conflict is resolved.
      #
      # On > 5 files OR agent failure: /land-pr already wrote
      # `.landed status=conflict` (per its WI 1.11 status table row 1)
      # via write-landed.sh; just `break`.

      CONFLICT_FILES_LIST_PATH="${LP[CONFLICT_FILES_LIST]:-}"
      CONFLICT_COUNT=0
      if [ -n "$CONFLICT_FILES_LIST_PATH" ] && [ -f "$CONFLICT_FILES_LIST_PATH" ]; then
        CONFLICT_COUNT=$(grep -c . "$CONFLICT_FILES_LIST_PATH")
      fi
      echo "/land-pr returned rebase-conflict ($CONFLICT_COUNT files)."

      if [ "$CONFLICT_COUNT" -gt 0 ] && [ "$CONFLICT_COUNT" -le 5 ]; then
        echo "Attempting agent-assisted resolution at orchestrator level..."
        # Dispatch an orchestrator-level Agent (NOT nested inside another
        # Agent — Claude Code subagents cannot dispatch sub-subagents).
        # The agent's prompt:
        #
        #   You are a rebase-conflict-resolution agent.
        #
        #   FIRST: cd $WORKTREE_PATH
        #
        #   /land-pr aborted the rebase on this worktree, leaving a clean
        #   tree. Re-run `git rebase origin/main` to reproduce the
        #   conflict, then resolve each conflicted file:
        #     - Read the file (contains <<<<<<< / ======= / >>>>>>> markers).
        #     - Understand "ours" (the phase work) and "theirs" (main).
        #     - Write a clean merged version preserving both intents.
        #     - git add <file>
        #   After resolving all files: git rebase --continue
        #
        #   Run the project test suite locally to verify the resolution.
        #   If tests pass: report success. If tests fail or you cannot
        #   confidently resolve a file: git rebase --abort and report
        #   failure.
        #
        #   Conflict file list: $CONFLICT_FILES_LIST_PATH
        #
        # If the agent reports success → `continue` to re-invoke /land-pr.
        # If the agent reports failure → `break`; /land-pr's `.landed
        # conflict` marker stands.
        #
        # (The agent dispatch is conceptual prose — at runtime, the
        # orchestrator calls Agent with the prompt above. The exact
        # success-signaling mechanism is the agent's final message
        # containing the literal token "REBASE-RESOLVED" or
        # "REBASE-PUNT".)
        :  # placeholder; orchestrator replaces with actual Agent dispatch
        # On success: continue
        # On failure: break
        break  # conservative default — if no agent dispatch path is wired,
               # treat as too-many-files and let /land-pr's marker stand.
      else
        echo "Conflict count $CONFLICT_COUNT > 5 (or empty list); skipping agent-assisted resolution."
        # /land-pr already wrote .landed status=conflict.
      fi
      break ;;

    push-failed|create-failed|monitor-failed|merge-failed|rebase-failed)
      echo "ERROR: /land-pr STATUS=$STATUS REASON=${LP[REASON]:-} (see ${LP[CALL_ERROR_FILE]:-no-error-file})" >&2
      break ;;
    created|monitored|merged) ;;  # fall through to CI-status check
  esac

  case "$CI_STATUS" in
    pass|none|skipped)
      break ;;  # /land-pr already requested merge if --auto
    pending)
      break ;;  # settle at pr-ready; user / cron can resume with --pr
    not-monitored)
      break ;;  # --no-monitor was used (none of /run-plan's flows do this)
    fail)
      if [ "$ATTEMPT" -ge "$MAX" ]; then
        echo "INFO: CI fix-cycle exhausted ($ATTEMPT/$MAX); PR settles at pr-ci-failing" >&2
        break
      fi
      # ===== <DISPATCH_FIX_CYCLE_AGENT_HERE> — per WI 2.4 =====
      #
      # Dispatch a fix-cycle agent at orchestrator level (NOT a nested
      # subagent — /land-pr was already invoked at orchestrator level
      # via the Skill tool; this dispatch is at the same level).
      #
      # Prompt structure follows
      # skills/land-pr/references/fix-cycle-agent-prompt-template.md.
      # /run-plan fills <CALLER_WORK_CONTEXT> with plan title, current
      # phase number, current phase title, current phase work items
      # (read from $PLAN_FILE).
      #
      # Inputs (substituted into the template):
      #   PR URL       = ${LP[PR_URL]}
      #   PR number    = ${LP[PR_NUMBER]}
      #   Branch       = $BRANCH_NAME
      #   Worktree     = $WORKTREE_PATH
      #   CI log file  = ${LP[CI_LOG_FILE]}
      #   Caller work context (CALLER_WORK_CONTEXT):
      #     Plan title:  $PLAN_TITLE
      #     Phase:       $CURRENT_PHASE_NUM — $CURRENT_PHASE_TITLE
      #     Plan file:   $PLAN_FILE
      #     Work items:  (extracted from $PLAN_FILE for $CURRENT_PHASE_NUM)
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
      # After the agent completes (regardless of success/punt), the
      # caller's loop increments $ATTEMPT and `continue`s — /land-pr is
      # idempotent, so re-invoking with the new commit on the branch
      # re-monitors CI cleanly.
      # =========================================================
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

# Sidecar cleanup (after final iteration). _CLEANUP_PATHS contains only
# CALL_ERROR_FILE and CONFLICT_FILES_LIST (transient). CI_LOG_FILE is
# intentionally NOT in the array — useful for post-mortem inspection.
for f in "${_CLEANUP_PATHS[@]}"; do
  [ -n "$f" ] && [ -f "$f" ] && rm -f "$f"
done

# Body file cleanup — keep until after the loop in case any future
# /land-pr re-invocation needs to re-read it (it is consumed by
# pr-push-and-create.sh, which only runs on the first iteration where
# the PR doesn't exist yet).
rm -f "$BODY_FILE"
# === END CANONICAL /land-pr CALLER LOOP ===
```

**`.landed` status values for PR mode (`/land-pr`-owned):**

`/land-pr` writes `.landed` for all paths after rebase succeeds — push-failed,
CI-failing, landed, pr-ready, etc. — using its WI 1.11 canonical schema and
WI 1.12 status mapping table (top-down, first-match-wins). `/run-plan` writes
`.landed` only for the pre-`/land-pr` "rebase-conflict-too-many-files" case
(see rebase points 1 and 2 above).

| Scenario | `.landed status` | Writer |
|----------|-----------------|--------|
| PR merged (auto-merge accepted, PR_STATE=MERGED) | `landed` | /land-pr |
| PR open, CI passed, awaiting review | `pr-ready` | /land-pr |
| PR open, CI timed out (still running) | `pr-ready` | /land-pr |
| PR open, CI failing after max attempts | `pr-ci-failing` | /land-pr |
| Branch pushed, PR creation failed | `pr-failed` | /land-pr |
| Push failed | `pr-failed` | /land-pr |
| Rebase conflict (too-many-files, pre-/land-pr) | `conflict` | /run-plan |
| Rebase conflict (bailed inside /land-pr) | `conflict` | /land-pr |
| PR state unknown (gh pr view exhausted retries) | `pr-state-unknown` | /land-pr |

### Post-landing tracking
