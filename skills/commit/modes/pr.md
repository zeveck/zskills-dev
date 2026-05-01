# /commit pr — PR Subcommand Mode

Loaded by /commit when the first argument token is `pr`; replaces Phases 1–5 to push the current branch and open a PR.
## Phase 6 (PR subcommand) — PR Mode (if `pr` is the first token)

**This phase runs INSTEAD OF Phases 1–5 when `pr` is the first token.**
It pushes the current branch and creates a PR to main via the shared
`/land-pr` skill (rebase + push + create + CI poll + fix-cycle loop).

**Step 1 — Pre-check: clean working tree required:**
```bash
DIRTY=$(git status --porcelain 2>/dev/null)
if [ -n "$DIRTY" ]; then
  echo "ERROR: Working tree has uncommitted changes."
  echo "Run \`/commit\` first to create a commit, then \`/commit pr\` to push and create the PR."
  exit 1
fi
```

**Step 2 — Branch guard:**
```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$BRANCH" == "main" || "$BRANCH" == "master" ]]; then
  echo "ERROR: Cannot create PR from main. Create a feature branch first."
  exit 1
fi
```

**Step 3 — Construct PR title and body BEFORE invoking /land-pr:**

`/land-pr`'s `pr-push-and-create.sh` consumes `--body-file=$BODY_FILE` on
initial PR creation. Title is derived from the branch name (existing /commit
convention); body is recent commits since divergence from `origin/main`
(NOT local `main` — local main may be stale after rebase).

```bash
# PR title: strip branch prefix, convert hyphens to spaces, title-case
BRANCH_SHORT="${BRANCH##*/}"  # remove prefix like feat/
PR_TITLE=$(echo "$BRANCH_SHORT" | tr '-' ' ' | sed 's/\b./\u&/g')

# Body: recent commits since divergence from origin/main (not local main —
# may be stale after rebase). Per-BRANCH_SLUG path so concurrent /commit pr
# invocations on parallel worktrees do not collide.
BRANCH_SLUG="${BRANCH//\//-}"
BODY_FILE="/tmp/pr-body-commit-$BRANCH_SLUG.md"
git log origin/main..HEAD --format='- %h %s' | head -15 > "$BODY_FILE"
```

**Step 4 — Dispatch `/land-pr` (canonical caller loop):**

`/commit pr` no longer owns rebase, push, PR creation, CI polling, or the
fix-cycle. Those move to `/land-pr` (see `skills/land-pr/SKILL.md`).
`/commit pr`'s remaining responsibility here is the fix-cycle agent
dispatch on `CI_STATUS=fail` — staged-files + recent-commit-subject context
sent at orchestrator level.

`/commit pr` customizations of the canonical pattern:
- `$LANDED_SOURCE = "commit"`
- No `--worktree-path` (no worktree — `/commit pr` runs in the main repo)
- No `--auto` (auto-merge stays OFF for `/commit pr`)
- `<CALLER_PRE_INVOKE_BODY_PREP>` = empty (commit's body is fixed at PR
  creation; no per-phase update like /run-plan does)
- `<CALLER_REBASE_CONFLICT_HANDLER>` = no agent-assisted resolution (no
  worktree, no plan context); break and surface the bail
- `<DISPATCH_FIX_CYCLE_AGENT_HERE>` = staged-files list (from
  `git diff --name-only origin/main..HEAD`) + recent commit subjects

```bash
# === BEGIN CANONICAL /land-pr CALLER LOOP ===
# Per skills/land-pr/references/caller-loop-pattern.md.

ATTEMPT=0
MAX="${CI_MAX_ATTEMPTS:-2}"
RESULT_FILE="/tmp/land-pr-result-$BRANCH_SLUG-$$.txt"

LANDED_SOURCE="commit"
LAND_ARGS="--branch=$BRANCH --title=\"$PR_TITLE\" --body-file=$BODY_FILE --result-file=$RESULT_FILE --landed-source=$LANDED_SOURCE"

while :; do
  # <CALLER_PRE_INVOKE_BODY_PREP> — empty for /commit pr.
  #
  # /commit pr composes the body once before the loop (Step 3 above) and
  # never refreshes it. /land-pr touches the body only on initial PR
  # creation; on existing PRs (the second-iteration retry case) the body
  # is preserved as-is — fine for /commit pr because the body content is
  # a static commit-log snapshot, not a progress-checklist that drifts.

  # Invoke /land-pr via the Skill tool. The Skill tool loads /land-pr's
  # prose into the current (orchestrator) context — its internal bash
  # blocks run here.
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

  # Sidecar cleanup paths. CI_LOG_FILE intentionally NOT in the array —
  # the fix-cycle agent below reads it.
  _CLEANUP_PATHS=("${LP[CALL_ERROR_FILE]:-}" "${LP[CONFLICT_FILES_LIST]:-}")
  rm -f "$RESULT_FILE"

  case "$STATUS" in
    rebase-conflict)
      # <CALLER_REBASE_CONFLICT_HANDLER> — /commit pr has no worktree and
      # no plan context, so no agent-assisted resolution path. /land-pr
      # already wrote `.landed status=conflict` (or printed equivalent
      # diagnostics) and aborted the rebase — break and surface to user.
      echo "/land-pr returned rebase-conflict. Resolve manually and re-run \`/commit pr\`." >&2
      break ;;
    push-failed|create-failed|monitor-failed|merge-failed|rebase-failed)
      echo "ERROR: /land-pr STATUS=$STATUS REASON=${LP[REASON]:-} (see ${LP[CALL_ERROR_FILE]:-no-error-file})" >&2
      break ;;
    created|monitored|merged) ;;  # fall through to CI-status check
  esac

  case "$CI_STATUS" in
    pass|none|skipped)
      break ;;  # /land-pr already requested merge if --auto (none for /commit pr)
    pending)
      break ;;  # settle at pr-ready
    not-monitored)
      break ;;  # --no-monitor was used (none of /commit pr's flows do this)
    fail)
      if [ "$ATTEMPT" -ge "$MAX" ]; then
        echo "INFO: CI fix-cycle exhausted ($ATTEMPT/$MAX); PR settles at pr-ci-failing" >&2
        break
      fi
      # ===== <DISPATCH_FIX_CYCLE_AGENT_HERE> — /commit pr customization =====
      #
      # Dispatch a fix-cycle agent at orchestrator level (NOT a nested
      # subagent — /land-pr was already invoked at orchestrator level
      # via the Skill tool; this dispatch is at the same level).
      #
      # Prompt structure follows
      # skills/land-pr/references/fix-cycle-agent-prompt-template.md.
      # /commit pr fills <CALLER_WORK_CONTEXT> with the recent-commit log
      # and the changed-files list — the closest analog to /run-plan's
      # plan-content slot.
      #
      # Inputs (substituted into the template):
      #   PR URL       = ${LP[PR_URL]}
      #   PR number    = ${LP[PR_NUMBER]}
      #   Branch       = $BRANCH
      #   Worktree     = (none — agent works in the current repo root)
      #   CI log file  = ${LP[CI_LOG_FILE]}
      #   Caller work context (CALLER_WORK_CONTEXT):
      #     Recent commits on this branch:
      #       $(git log origin/main..HEAD --format='%h %s')
      #     Files changed on this branch:
      #       $(git diff --name-only origin/main..HEAD)
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
# === END CANONICAL /land-pr CALLER LOOP ===
```

**PR mode does NOT:**
- Auto-merge (no `--auto` passed to `/land-pr`)
- Write `.landed` markers (`/commit pr` has no worktree)
- Run Phases 1–5 (all commits must already exist — clean tree is required)

**After the caller loop exits, exit.** Skip Phases 1–5 and 7.
