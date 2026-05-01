# /do — PR Mode (Path A)

Full end-to-end PR flow: create branch, worktree, dispatch agents, open the PR, poll CI, then write the landing marker.
### Path A: PR mode (`LANDING_MODE="pr"`)

Selected when the user passes `pr` explicitly, or when
`execution.landing` in `.claude/zskills-config.json` is `"pr"`.

**This path replaces the normal Phase 2–5 flow entirely. After the PR is created, skip to Phase 5 Report.**

**Step A1 — Compose task slug (model-layer).** Set shell variable
`TASK_SLUG` to a kebab-case identifier matching
`^[a-z0-9]+(-[a-z0-9]+)*$`, ≤30 chars, a 3–5 word summary of the task.
Compose from `$TASK_DESCRIPTION`'s essential verbs/nouns — not a verbatim
prefix of the input. Multi-line descriptions compose the same way as
single-line ones: distill the intent, don't splice lines.

```bash
if [ -z "${TASK_SLUG:-}" ]; then
  echo "ERROR: TASK_SLUG not set — model-layer composition step skipped." >&2
  exit 5
fi
if ! [[ "$TASK_SLUG" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || [ ${#TASK_SLUG} -gt 30 ]; then
  echo "ERROR: TASK_SLUG must match ^[a-z0-9]+(-[a-z0-9]+)*\$ and be ≤30 chars (got '$TASK_SLUG')." >&2
  exit 2
fi
```

**Step A2 — Collision check (BEFORE deriving BRANCH_NAME or WORKTREE_PATH):**
```bash
PROJECT_NAME=$(basename "$(git rev-parse --show-toplevel)")
if [ -d "/tmp/${PROJECT_NAME}-do-${TASK_SLUG}" ]; then
  TASK_SLUG="${TASK_SLUG}-$(date +%s | tail -c 5)"
fi
```

**Step A3 — Derive BRANCH_NAME and WORKTREE_PATH from (possibly suffixed) TASK_SLUG:**
```bash
# Read .execution.branch_prefix via bash-regex (no external jq dependency).
# Preserve empty-string when the key is present-but-empty; default "feat/"
# only when the key is absent or the config file is missing.
BRANCH_PREFIX="feat/"
if [ -f .claude/zskills-config.json ]; then
  _CFG=$(cat .claude/zskills-config.json)
  if [[ "$_CFG" =~ \"branch_prefix\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    BRANCH_PREFIX="${BASH_REMATCH[1]}"
  fi
  unset _CFG
fi
BRANCH_NAME="${BRANCH_PREFIX}do-${TASK_SLUG}"
WORKTREE_PATH="/tmp/${PROJECT_NAME}-do-${TASK_SLUG}"
```

**Step A4 — Sanitize TASK_SLUG + construct PIPELINE_ID (BEFORE worktree creation):**
```bash
# Route TASK_SLUG through the shared sanitizer (collapses any character
# outside [a-zA-Z0-9._-] into `_`, truncates to 128 bytes). KEEP this
# defensive call: removing would require exhaustive downstream audit of
# TASK_SLUG consumers (R2-M4). It is safe to run this BEFORE worktree
# creation because the sanitized slug is needed by --pipeline-id.
TASK_SLUG=$(bash "$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh" "$TASK_SLUG")
PIPELINE_ID="do.${TASK_SLUG}"
```

**Step A5 — Worktree creation (pre-flight prune+fetch+ff-merge is owned by create-worktree.sh):**
```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
# /do expects a fresh branch per task — no legitimate resume.
# --pipeline-id passes $PIPELINE_ID explicitly; the script sanitizes it
# again internally (idempotent on already-safe inputs) and writes the
# sanitized value to the worktree's .zskills-tracked. No env var reliance,
# no cross-invocation pollution.
WORKTREE_PATH=$(bash "$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/create-worktree.sh" \
  --prefix do \
  --branch-name "${BRANCH_PREFIX}do-${TASK_SLUG}" \
  --purpose "do PR mode; task=${TASK_SLUG}" \
  --pipeline-id "$PIPELINE_ID" \
  "${TASK_SLUG}")
RC=$?
if [ "$RC" -ne 0 ]; then
  echo "create-worktree failed (rc=$RC) for /do PR mode" >&2
  exit "$RC"
fi
# create-worktree.sh has now written $PIPELINE_ID (sanitized) to
# $WORKTREE_PATH/.zskills-tracked.
```
Do NOT echo `ZSKILLS_PIPELINE_ID=do.${TASK_SLUG}` as shell output in the main session — the `.zskills-tracked` file in the worktree is the single source of truth.

**Step A6 — Dispatch implementation agent (wait for completion):**

**Before dispatching:** Check `agents.min_model` in `.claude/zskills-config.json`. If set,
use that model or higher (ordinal: haiku=1 < sonnet=2 < opus=3). Never dispatch with a
lower-ordinal model than the configured minimum.

Dispatch an Agent (without `isolation: "worktree"` — the worktree already exists) with this prompt:

```
You are implementing: $TASK_DESCRIPTION

FIRST: cd $WORKTREE_PATH
All work happens in that directory. Do NOT work in any other directory.
You are on branch $BRANCH_NAME (already checked out in the worktree).

Implement the task. Commit changes when done:
- Stage files by name (not git add .)
- Do NOT commit to main
- Commit message should summarize what was implemented

Check agents.min_model in .claude/zskills-config.json before dispatching
any sub-agents. Use that model or higher (haiku=1 < sonnet=2 < opus=3).
```

Wait for the implementation agent to complete. If the agent reports failure or exits without committing:
```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
cat > "$WORKTREE_PATH/.landed" <<LANDED
status: conflict
date: $(TZ="${TIMEZONE:-UTC}" date -Iseconds)
source: do
branch: $BRANCH_NAME
LANDED
```
Exit with error directing the user to inspect `$WORKTREE_PATH`.

**Step A7 — Compose PR title and body BEFORE invoking /land-pr:**

`/land-pr` owns rebase, push, PR creation, CI polling, fix-cycle, and the
`.landed` marker write (canonical schema, including `pr-state-unknown` on
exhausted `gh pr view` retries). `/do pr` is responsible only for the
title/body composition and the fix-cycle agent's task-context slot.

```bash
cd "$WORKTREE_PATH"

# Compose $PR_TITLE (model-layer). Set shell variable PR_TITLE to a
# single-line title, ≤60 chars, that MUST begin with the literal prefix
# `do: ` (four characters: d, o, colon, space — preserving /do's existing
# convention). After the prefix, summarize what the task actually did —
# compose from the completed work, not a verbatim prefix of
# $TASK_DESCRIPTION.
if [ -z "${PR_TITLE:-}" ]; then
  echo "ERROR: PR_TITLE not set — model-layer composition step skipped." >&2
  exit 5
fi
if [[ "$PR_TITLE" == *$'\n'* ]] || [ ${#PR_TITLE} -gt 60 ] || [[ "$PR_TITLE" != do:\ * ]]; then
  echo "ERROR: PR_TITLE must be a single line ≤60 chars starting with 'do: ' (got '$PR_TITLE')." >&2
  exit 2
fi

# PR body: explicit, not --fill (the title and body are constructed by the
# skill, not auto-derived from commits). Per-BRANCH_SLUG path so
# concurrent /do pr invocations on parallel worktrees do not collide.
BRANCH_SLUG="${BRANCH_NAME//\//-}"
BODY_FILE="/tmp/pr-body-do-$BRANCH_SLUG.md"
cat > "$BODY_FILE" <<BODY
Task: ${TASK_DESCRIPTION}

Worktree: ${WORKTREE_PATH}
Commits: $(git log origin/main..HEAD --format='%h %s' | head -10)
BODY
```

**Step A8 — Dispatch `/land-pr` (canonical caller loop):**

`/do pr` no longer owns rebase, push, PR creation, CI polling, or the
`.landed` write — those move to `/land-pr` (see `skills/land-pr/SKILL.md`).
`/do pr` gains a fix-cycle on CI failure (drift fix) — the fix-cycle
agent's `<CALLER_WORK_CONTEXT>` slot is filled with the original task
description.

`/do pr` customizations of the canonical pattern:
- `$LANDED_SOURCE = "do"`
- `$WORKTREE_PATH` set (the per-task worktree from Step A5)
- No `--auto` (auto-merge stays OFF for `/do pr`)
- `<CALLER_PRE_INVOKE_BODY_PREP>` = empty (do's body is fixed at PR
  creation; no per-phase update like /run-plan does)
- `<CALLER_REBASE_CONFLICT_HANDLER>` = no agent-assisted resolution
  (single-task scope, no plan context); break and surface the bail
- `<DISPATCH_FIX_CYCLE_AGENT_HERE>` = task description (`$TASK_DESCRIPTION`)

```bash
# === BEGIN CANONICAL /land-pr CALLER LOOP ===
# Per skills/land-pr/references/caller-loop-pattern.md.

ATTEMPT=0
MAX="${CI_MAX_ATTEMPTS:-2}"
RESULT_FILE="/tmp/land-pr-result-$BRANCH_SLUG-$$.txt"

LANDED_SOURCE="do"
LAND_ARGS="--branch=$BRANCH_NAME --title=\"$PR_TITLE\" --body-file=$BODY_FILE --result-file=$RESULT_FILE --landed-source=$LANDED_SOURCE --worktree-path=$WORKTREE_PATH"

while :; do
  # <CALLER_PRE_INVOKE_BODY_PREP> — empty for /do pr.
  #
  # /do pr composes the body once before the loop (Step A7 above) and
  # never refreshes it. /land-pr touches the body only on initial PR
  # creation; on existing PRs (the second-iteration retry case) the body
  # is preserved as-is — fine for /do pr because the body content is a
  # static task-description + commit-log snapshot, not a progress
  # checklist that drifts.

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
      # <CALLER_REBASE_CONFLICT_HANDLER> — /do pr is single-task with no
      # plan context, so no agent-assisted resolution path. /land-pr
      # already wrote `.landed status=conflict` and aborted the rebase —
      # break and surface to user.
      echo "/land-pr returned rebase-conflict. Resolve manually in $WORKTREE_PATH and re-run \`/do pr\` (or land manually)." >&2
      break ;;
    push-failed|create-failed|monitor-failed|merge-failed|rebase-failed)
      echo "ERROR: /land-pr STATUS=$STATUS REASON=${LP[REASON]:-} (see ${LP[CALL_ERROR_FILE]:-no-error-file})" >&2
      break ;;
    created|monitored|merged) ;;  # fall through to CI-status check
  esac

  case "$CI_STATUS" in
    pass|none|skipped)
      break ;;  # /land-pr already requested merge if --auto (none for /do pr)
    pending)
      break ;;  # settle at pr-ready
    not-monitored)
      break ;;  # --no-monitor was used (none of /do pr's flows do this)
    fail)
      if [ "$ATTEMPT" -ge "$MAX" ]; then
        echo "INFO: CI fix-cycle exhausted ($ATTEMPT/$MAX); PR settles at pr-ci-failing" >&2
        break
      fi
      # ===== <DISPATCH_FIX_CYCLE_AGENT_HERE> — /do pr customization =====
      #
      # Dispatch a fix-cycle agent at orchestrator level (NOT a nested
      # subagent — /land-pr was already invoked at orchestrator level
      # via the Skill tool; this dispatch is at the same level).
      #
      # Prompt structure follows
      # skills/land-pr/references/fix-cycle-agent-prompt-template.md.
      # /do pr fills <CALLER_WORK_CONTEXT> with the original task
      # description — the agent gets the same brief as the implementation
      # agent did, plus the CI failure log.
      #
      # Inputs (substituted into the template):
      #   PR URL       = ${LP[PR_URL]}
      #   PR number    = ${LP[PR_NUMBER]}
      #   Branch       = $BRANCH_NAME
      #   Worktree     = $WORKTREE_PATH
      #   CI log file  = ${LP[CI_LOG_FILE]}
      #   Caller work context (CALLER_WORK_CONTEXT):
      #     Task: $TASK_DESCRIPTION
      #     Branch: $BRANCH_NAME
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
      # After the agent completes, the caller's loop increments $ATTEMPT
      # and `continue`s — /land-pr is idempotent.
      # ====================================================================
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

**Note on the `.landed` schema:** `/land-pr` writes the canonical schema
(per its WI 1.11) — additive over the previous `/do pr` schema. Existing
fields (`status`, `date`, `source`, `branch`, `pr`) are all preserved;
new fields (`method`, `pr_state`, `merge_requested`, `merge_reason`,
`reason`, `commits`) are present when relevant. `/fix-report` and the
worktree-cleanup tooling handle the new fields gracefully (they read
fewer fields than the marker has — additive change is safe).

The `pr-state-unknown` status (when `gh pr view` exhausts retries) is now
emitted by `/land-pr`'s status-mapping table (WI 1.12 row 9), preserving
the previous /do pr behavior unchanged.

After the caller loop exits, output the Phase 5 PR report and **exit** (skip Phases 3-4).

