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
- **`--auto` is gated on the positional `auto` token** (issue #236 —
  matches /run-plan, /fix-issues, /do). Without `auto`,
  auto-merge stays OFF and the PR settles at `pr-ready` after CI passes;
  with `auto`, `LAND_ARGS` includes `--auto` and `/land-pr`'s existing
  auto-merge path takes over (same CI gate, same behavior as the other
  4 skills).
- `<CALLER_PRE_INVOKE_BODY_PREP>` = empty (commit's body is fixed at PR
  creation; no per-phase update like /run-plan does)
- `<CALLER_REBASE_CONFLICT_HANDLER>` = no agent-assisted resolution (no
  worktree, no plan context); break and surface the bail
- `<DISPATCH_FIX_CYCLE_AGENT_HERE>` = staged-files list (from
  `git diff --name-only origin/main..HEAD`) + recent commit subjects

```bash
# === BEGIN CANONICAL /land-pr CALLER LOOP ===
# Per skills/land-pr/references/caller-loop-pattern.md.
if [ -n "${ZSH_VERSION:-}" ]; then setopt KSH_ARRAYS BASH_REMATCH SH_WORD_SPLIT 2>/dev/null || true; fi

ATTEMPT=0
MAX="${CI_MAX_ATTEMPTS:-2}"
RESULT_FILE="/tmp/land-pr-result-$BRANCH_SLUG-$$.txt"

# Tracking-setup block (Plan LAND_PR_BYPASS_HARDENING Phase 2):
# write requires.land-pr.<id> and fulfilled.commit.<id> markers BEFORE
# LAND_ARGS assembly so the hook fence recognises the dispatch and the
# dashboard sees an in-flight /commit pr. Explicit-finalize (NOT trap)
# runs after the caller-loop closes (same fence — variables survive).
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
PIPELINE_ID="commit.$BRANCH_SLUG"
PIPELINE_ID=$(bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/sanitize-pipeline-id.sh" "$PIPELINE_ID")
# Echo (do not env-export) the pipeline id — the tier-2
# transcript-propagation idiom (the `echo "ZSKILLS_PIPELINE_ID=..."` line
# below) satisfies the conformance test at `tests/test-skill-conformance.sh:1050`
# which forbids the env-export side-channel form. The Claude Code harness
# propagates the variable into /land-pr's bash fences via the transcript,
# where /land-pr Step 8b consumes it
# (`PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"`).
echo "ZSKILLS_PIPELINE_ID=$PIPELINE_ID"
[ -n "$PIPELINE_ID" ] || { echo "tracking: empty PIPELINE_ID — refusing flat write" >&2; exit 1; }
TRACK_DIR="$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
mkdir -p "$TRACK_DIR"
NOW_ISO=$(TZ="${TIMEZONE:-UTC}" date -Iseconds)
HEAD_BRANCH=$(git symbolic-ref --short HEAD)
# fulfilled.<skill>.<id> start-marker (per #228 Part B).
cat > "$TRACK_DIR/fulfilled.commit.$BRANCH_SLUG" <<MARK
status: started
date: $NOW_ISO
skill: commit
mode: pr
branch: $HEAD_BRANCH
MARK
# requires.land-pr.<id> (drives hook STOP-message Pattern 2 + dashboard).
cat > "$TRACK_DIR/requires.land-pr.$BRANCH_SLUG" <<MARK
skill: land-pr
parent: commit
id: $BRANCH_SLUG
branch: $HEAD_BRANCH
date: $NOW_ISO
MARK

# LAND_OUTCOME tracker (R-5-8 — `__init__` default avoids token-overload
# with CI_STATUS=unknown which maps to pr-ready). Set by case arms below.
LAND_OUTCOME=__init__

LANDED_SOURCE="commit"
LAND_ARGS="--branch=$BRANCH --title=\"$PR_TITLE\" --body-file=$BODY_FILE --result-file=$RESULT_FILE --landed-source=$LANDED_SOURCE --tracking-id=$BRANCH_SLUG"

# Auto gate (issue #236) — append `--auto` when the caller passed
# the positional `auto` token (parsed in skills/commit/SKILL.md and
# propagated as $AUTO_FLAG=1). Mirrors /run-plan, /fix-issues, /do.
# `--automerge` additionally requests auto-merge on the PR.
# Without `automerge`, `/land-pr` runs through PR creation +
# CI poll + fix-cycle but does NOT call `gh pr merge --auto --squash`;
# the PR settles at `pr-ready` for human review.
[ "${AUTO_FLAG:-0}" = "1" ] && LAND_ARGS="$LAND_ARGS --auto"
[ "${AUTOMERGE_FLAG:-0}" = "1" ] && LAND_ARGS="$LAND_ARGS --automerge"

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
    # Inline cleanup before exit (DA-3-1 / R-4-9 — this exit bypasses the
    # explicit-finalize block at end-of-fence). Variables in scope (same fence).
    rm -f "$TRACK_DIR/requires.land-pr.$BRANCH_SLUG"
    sed -i "s/^status: started$/status: failed/" "$TRACK_DIR/fulfilled.commit.$BRANCH_SLUG"
    exit 1
  fi

  # SAFE allow-list parsing (per WI 1.7). Never `source`. Reading line by
  # line and dispatching on a fixed key set guarantees that even
  # maliciously-crafted values cannot reach shell evaluation.
  # zsh portability (#1155): assoc subscripts must be UNQUOTED — zsh uses the
  # subscript text verbatim, so LP["$KEY"] and ${LP[STATUS]} address different
  # keys. Keep assignment and lookup styles consistent-unquoted.
  declare -A LP
  while IFS='=' read -r KEY VALUE; do
    case "$KEY" in
      STATUS|PR_URL|PR_NUMBER|PR_EXISTING|CI_STATUS|CI_LOG_FILE|\
      MERGE_REQUESTED|MERGE_REASON|PR_STATE|REASON|\
      CONFLICT_FILES_LIST|CALL_ERROR_FILE|REBASE_STDERR_FILE)
        LP[$KEY]="$VALUE" ;;
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
  _CLEANUP_PATHS=("${LP[CALL_ERROR_FILE]:-}" "${LP[CONFLICT_FILES_LIST]:-}" "${LP[REBASE_STDERR_FILE]:-}")
  rm -f "$RESULT_FILE"

  case "$STATUS" in
    rebase-conflict)
      # <CALLER_REBASE_CONFLICT_HANDLER> — /commit pr has no worktree and
      # no plan context, so no agent-assisted resolution path. /land-pr
      # already wrote `.zskills/landed status=conflict` (or printed equivalent
      # diagnostics) and aborted the rebase — break and surface to user.
      echo "/land-pr returned rebase-conflict. Resolve manually and re-run \`/commit pr\`." >&2
      LAND_OUTCOME=$STATUS
      break ;;
    push-failed|create-failed|monitor-failed|merge-failed|rebase-failed)
      echo "ERROR: /land-pr STATUS=$STATUS REASON=${LP[REASON]:-} (see ${LP[CALL_ERROR_FILE]:-no-error-file})" >&2
      LAND_OUTCOME=$STATUS
      break ;;
    behind-thrash)
      # Step 6b exhausted auto-rebase budget. pr-ready surface, but the
      # discriminator is preserved in $LAND_OUTCOME for the explicit-
      # finalize block + tracking marker (failure-class — `*)` arm below
      # in the finalize maps to FINAL=failed).
      echo "/land-pr STATUS=behind-thrash — auto-rebase budget exhausted, manual rebase needed" >&2
      LAND_OUTCOME=$STATUS
      break ;;
    auto-rebase-conflict|auto-rebase-blocked)
      # Step 6b auto-rebase merge-conflicted, or mergeStateStatus settled
      # at BLOCKED for non-CI reasons. Issue #624 — must NOT be silently
      # coerced to pr-ready by the CI-status check below.
      echo "/land-pr STATUS=$STATUS REASON=${LP[REASON]:-} — manual intervention needed" >&2
      LAND_OUTCOME=$STATUS
      break ;;
    created|monitored|merged) ;;  # fall through to CI-status check
    *)
      # Unknown STATUS — fail loud rather than coerce via the CI-status
      # check below (issue #624 — closes the silent fall-through gap).
      echo "WARN: unrecognized /land-pr STATUS=$STATUS — settling at unknown-status" >&2
      LAND_OUTCOME="unknown-status-$STATUS"
      break ;;
  esac

  case "$CI_STATUS" in
    pass|none|skipped)
      # PR_STATE=MERGED → merged; PR_STATE=OPEN (or anything else) → pr-ready.
      if [ "${LP[PR_STATE]:-}" = "MERGED" ]; then
        LAND_OUTCOME=merged
      else
        LAND_OUTCOME=pr-ready
      fi
      break ;;  # /land-pr already requested merge if --automerge (gated on AUTOMERGE_FLAG per issue #236)
    pending)
      LAND_OUTCOME=pr-ready
      break ;;  # settle at pr-ready
    not-monitored)
      LAND_OUTCOME=created
      break ;;  # --no-monitor was used (none of /commit pr's flows do this)
    fail)
      if [ "$ATTEMPT" -ge "$MAX" ]; then
        echo "INFO: CI fix-cycle exhausted ($ATTEMPT/$MAX); PR settles at pr-ci-failing" >&2
        LAND_OUTCOME=pr-ci-failing
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
      LAND_OUTCOME=pr-ready
      break ;;
    *)
      echo "WARN: CI_STATUS='$CI_STATUS' unrecognized — settling at pr-ready" >&2
      LAND_OUTCOME=pr-ready
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
# Explicit-finalize block (Plan LAND_PR_BYPASS_HARDENING Phase 2 — must
# live in the SAME fence as the caller-loop per R-4-7 so $LAND_OUTCOME
# survives). R-5-6: no `cancelled)` arm — /commit pr has no $CANCELLED.
case "$LAND_OUTCOME" in
  merged|created|pr-ready) FINAL=complete ;;
  *) FINAL=failed ;;
esac
sed -i "s/^status: started$/status: $FINAL/" "$TRACK_DIR/fulfilled.commit.$BRANCH_SLUG"
rm -f "$TRACK_DIR/requires.land-pr.$BRANCH_SLUG"
```

**PR mode does NOT:**
- Auto-merge **unless the positional `automerge` token is passed**
  (issue #236 — `/commit pr automerge` or, via config-default-to-pr,
  `/commit automerge`). With bare `auto`, `LAND_ARGS` includes `--auto`
  (unattended mode) but omits `--automerge`, so the PR settles at
  `pr-ready` after CI passes. With `automerge`, `--automerge` is appended
  and `/land-pr` invokes `gh pr merge --auto --squash`.
- Write `.zskills/landed` markers (`/commit pr` has no worktree)
- Run Phases 1–5 (all commits must already exist — clean tree is required)

**After the caller loop exits, exit.** Skip Phases 1–5 and 7.
