# /quickfix — Phase 7 (PR creation, CI poll, fix-cycle via `/land-pr`)

> Final phase of the `/quickfix` lifecycle, loaded after `modes/execute.md`
> pushes the branch (Phase 6). The persistent shell carries `$PR_TITLE`
> (composed model-layer below), `$BRANCH`, `$BASE_BRANCH`, `$MARKER`,
> `$SLUG`, `$PIPELINE_ID`, `$ZSKILLS_PIPELINE_ID`, and `$ISSUE_NUM` from
> the earlier phases. Exit codes + Key Rules live in
> `references/exit-codes-and-rules.md`.

## Phase 7 — PR creation, CI poll, fix-cycle (WI 1.15) — dispatch `/land-pr`

`/quickfix` no longer owns inline PR creation, CI polling, or the fix-cycle.
Those move to `/land-pr` (see `skills/land-pr/SKILL.md`). `/quickfix`'s
remaining responsibilities here are (a) compose `$PR_TITLE` + body file
BEFORE invoking /land-pr, (b) drive the canonical caller loop, (c) on
`CI_STATUS=fail` dispatch a fix-cycle agent at orchestrator level whose
work-context slot is the user's `$DESCRIPTION` plus the staged commit
subject, and (d) preserve the WI 1.16 `pr: $PR_URL` marker append + the
WI 1.17 return-to-base-branch behavior on success.

**Compose $PR_TITLE (model-layer).** Set shell variable `PR_TITLE` to a
single-line conventional-commit style title of the form
`type(scope): summary` (type ∈ {feat, fix, docs, refactor, chore, test,
build, ci, style, perf, revert}; scope is the primary module/file being
changed; summary describes what's actually changing). ≤70 chars, no
newlines. Compose from what the PR actually does — not a verbatim prefix
of the description.

PR body is composed once before the loop and written to a `$BODY_FILE`
that `/land-pr`'s `pr-push-and-create.sh` consumes via `--body-file`. The
heredoc uses `<<-EOF` with **tab-indented** body lines (tabs are stripped
by `<<-`; using spaces would render the body as a code block on GitHub).

```bash
if [ -z "${PR_TITLE:-}" ]; then
  echo "ERROR: PR_TITLE not set — model-layer composition step skipped." >&2
  exit 5
fi
if [[ "$PR_TITLE" == *$'\n'* ]] || [ ${#PR_TITLE} -gt 70 ]; then
  echo "ERROR: PR_TITLE must be a single line ≤70 chars (got '$PR_TITLE')." >&2
  exit 2
fi

# Per-BRANCH_SLUG body file path so concurrent /quickfix invocations on
# parallel slugs do not collide.
BRANCH_SLUG="${BRANCH//\//-}"
BODY_FILE="/tmp/pr-body-quickfix-$BRANCH_SLUG.md"
cat > "$BODY_FILE" <<-EOF
	## Summary

	$DESCRIPTION

	Mode: \`$MODE\`
	Base: \`$BASE_BRANCH\`
	Slug: \`$SLUG\`

	## Test plan

	- Ran project \`unit_cmd\` before commit (or skip-tests).
	- Independent \`/verify-changes\` before push (or skipped via --force/skip-tests).
	- Review diff.

	🤖 Generated with /quickfix
	EOF
```

`/quickfix` customizations of the canonical caller-loop pattern (per
`skills/land-pr/references/caller-loop-pattern.md`):

- `$LANDED_SOURCE = "quickfix"`
- **No `--worktree-path`** — `/quickfix` has no worktree; this means
  `/land-pr` does NOT write a `.landed` marker. The two artifact systems
  coexist intentionally: `/quickfix`'s fulfillment marker (with `pr:` URL
  appended below) tracks the `/quickfix` lifecycle; `.landed` is for
  worktree-using callers.
- **`--auto` is gated on the positional `auto` token** (issue #235 —
  matches /run-plan, /fix-issues, /do). Without `auto`, auto-merge stays
  OFF and the PR settles at `pr-ready` after CI passes; with `auto`,
  `LAND_ARGS` includes `--auto` and `/land-pr`'s existing auto-merge
  path takes over (same CI gate, same behavior as the other 3 skills).
- `<CALLER_PRE_INVOKE_BODY_PREP>` = empty (`/quickfix` composes the body
  once above; no per-phase update like /run-plan does).
- `<CALLER_REBASE_CONFLICT_HANDLER>` = no agent-assisted resolution
  (`/quickfix` has no worktree and no plan context); break and surface
  the bail.
- `<DISPATCH_FIX_CYCLE_AGENT_HERE>` = user's `$DESCRIPTION` + staged
  commit subject (`$COMMIT_SUBJECT`).

```bash
# === BEGIN CANONICAL /land-pr CALLER LOOP ===
# Per skills/land-pr/references/caller-loop-pattern.md.

ATTEMPT=0
MAX="${CI_MAX_ATTEMPTS:-2}"
RESULT_FILE="/tmp/land-pr-result-$BRANCH_SLUG-$$.txt"

LANDED_SOURCE="quickfix"
LAND_ARGS="--branch=$BRANCH --title=\"$PR_TITLE\" --body-file=$BODY_FILE --result-file=$RESULT_FILE --landed-source=$LANDED_SOURCE --tracking-id=$SLUG"
# Issue #235: positional `auto` token (parsed in WI 1.2) opts /quickfix
# into /land-pr's auto-merge path. Mirrors /run-plan, /fix-issues, /do.
[ "${AUTO_FLAG:-0}" = "1" ] && LAND_ARGS="$LAND_ARGS --auto"

# LAND_OUTCOME tracker (issue #241 — explicit-finalize pattern matches
# /commit pr / /do pr / /fix-issues pr). Set by case arms below; read by
# the post-loop explicit-finalize block.
LAND_OUTCOME=__init__

while :; do
  # <CALLER_PRE_INVOKE_BODY_PREP> — empty for /quickfix.
  #
  # /quickfix composes the body once above and never refreshes it.
  # /land-pr touches the body only on initial PR creation; on existing
  # PRs (the second-iteration retry case) the body is preserved as-is —
  # fine for /quickfix because the body content is a static
  # description+mode snapshot, not a progress checklist that drifts.

  # Invoke /land-pr via the Skill tool. The Skill tool loads /land-pr's
  # prose into the current (orchestrator) context — its internal bash
  # blocks run here.
  #
  # Skill: { skill: "land-pr", args: "$LAND_ARGS" }

  if [ ! -f "$RESULT_FILE" ]; then
    echo "ERROR: /land-pr produced no result file at $RESULT_FILE" >&2
    # Inline cleanup before exit (issue #241; bypasses the end-of-fence
    # explicit-finalize block). $MARKER survives from WI 1.8 in the
    # persistent shell.
    [ -f "$MARKER" ] && sed -i "s/^status: started$/status: failed/" "$MARKER"
    # Issue #629: standalone /quickfix doesn't set ZSKILLS_PIPELINE_ID;
    # only callers like /fix-issues do. Guard the rm so the cleanup
    # silently no-ops on standalone (no parent pipeline marker to remove)
    # and runs correctly when called by a parent pipeline. Mirrors the
    # `[ -n "${ZSKILLS_PIPELINE_ID:-}" ]` guard at line 1310 below.
    [ -n "${ZSKILLS_PIPELINE_ID:-}" ] && rm -f "$MAIN_ROOT/.zskills/tracking/$ZSKILLS_PIPELINE_ID/requires.land-pr.$SLUG" 2>/dev/null
    # Release the issue claim (only if one was acquired at WI 1.8). This
    # early exit bypasses the end-of-fence explicit-finalize release.
    if [ -n "${ISSUE_NUM:-}" ]; then
      bash "$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/claim-issue.sh" release "$ISSUE_NUM" --require-pipeline "$PIPELINE_ID"
    fi
    exit 5
  fi

  # SAFE allow-list parsing (per WI 1.7). Never `source`. Reading line by
  # line and dispatching on a fixed key set guarantees that even
  # maliciously-crafted values cannot reach shell evaluation.
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

  # Sidecar cleanup paths. CI_LOG_FILE intentionally NOT in the array —
  # the fix-cycle agent below reads it.
  _CLEANUP_PATHS=("${LP[CALL_ERROR_FILE]:-}" "${LP[CONFLICT_FILES_LIST]:-}" "${LP[REBASE_STDERR_FILE]:-}")
  rm -f "$RESULT_FILE"

  # WI 1.16 — append the PR URL to the fulfillment marker as soon as
  # /land-pr emits one (first iteration where STATUS ∈ {created, monitored,
  # merged}). Append-once is enforced via the `pr:` line absence check:
  # subsequent loop iterations will re-emit the same PR_URL (since
  # /land-pr is idempotent and the PR already exists), but the marker
  # already carries the line. The EXIT trap (registered by WI 1.8) flips
  # `status: started` → `status: complete` at script end.
  if [ -n "$PR_URL" ] && [ -f "$MARKER" ] && ! grep -q '^pr: ' "$MARKER"; then
    printf 'pr: %s\n' "$PR_URL" >> "$MARKER"
  fi

  case "$STATUS" in
    rebase-conflict)
      # <CALLER_REBASE_CONFLICT_HANDLER> — /quickfix has no worktree and
      # no plan context, so no agent-assisted resolution path. /land-pr
      # already aborted the rebase — break and surface to user.
      echo "/land-pr returned rebase-conflict. Resolve manually and re-run \`/quickfix\` (or land manually)." >&2
      LAND_OUTCOME=$STATUS
      break ;;
    push-failed|create-failed|monitor-failed|merge-failed|rebase-failed)
      echo "ERROR: /land-pr STATUS=$STATUS REASON=${LP[REASON]:-} (see ${LP[CALL_ERROR_FILE]:-no-error-file})" >&2
      LAND_OUTCOME=$STATUS
      break ;;
    behind-thrash)
      # Step 6b exhausted auto-rebase budget (issue #624). pr-ready
      # surface but discriminator preserved in $LAND_OUTCOME.
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
      # Unknown STATUS — fail loud rather than coerce via CI-status
      # (issue #624 — closes the silent fall-through gap).
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
      break ;;  # /land-pr already requested merge if --auto
    pending)
      LAND_OUTCOME=pr-ready
      break ;;  # settle at pr-ready
    not-monitored)
      LAND_OUTCOME=created
      break ;;  # --no-monitor was used (none of /quickfix's flows do this)
    fail)
      if [ "$ATTEMPT" -ge "$MAX" ]; then
        echo "INFO: CI fix-cycle exhausted ($ATTEMPT/$MAX); PR settles at pr-ci-failing" >&2
        LAND_OUTCOME=pr-ci-failing
        break
      fi
      # ===== <DISPATCH_FIX_CYCLE_AGENT_HERE> — /quickfix customization =====
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
      # /quickfix fills <CALLER_WORK_CONTEXT> with the user's original
      # `$DESCRIPTION` and the staged commit subject `$COMMIT_SUBJECT` —
      # the agent gets the same intent the commit captured, plus the CI
      # failure log.
      #
      # Inputs (substituted into the template):
      #   PR URL       = ${LP[PR_URL]}
      #   PR number    = ${LP[PR_NUMBER]}
      #   Branch       = $BRANCH
      #   Worktree     = (none — agent works in the current repo root)
      #   CI log file  = ${LP[CI_LOG_FILE]}
      #   Caller work context (CALLER_WORK_CONTEXT):
      #     Description: $DESCRIPTION
      #     Commit subject: $COMMIT_SUBJECT
      #     Mode: $MODE
      #     Branch: $BRANCH
      #     Recent commits on this branch:
      #       $(git log origin/$BASE_BRANCH..HEAD --format='%h %s')
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

# Print the PR URL on stdout so the user sees something actionable.
if [ -n "$PR_URL" ]; then
  echo "$PR_URL"
fi

# WI 1.17 — return to base branch on success.
# The PR exists on GitHub; locally we leave the user where they started
# (on $BASE_BRANCH) so subsequent commands don't accidentally pile onto
# the feature branch. Forgiving: if the checkout fails, warn but do not
# fail the run — the PR is already created.
if ! git checkout "$BASE_BRANCH"; then
  echo "WARN: PR created at $PR_URL but failed to checkout back to $BASE_BRANCH. Run 'git checkout $BASE_BRANCH' manually." >&2
fi
# === END CANONICAL /land-pr CALLER LOOP ===
# Explicit-finalize block (Plan LAND_PR_BYPASS_HARDENING Phase 2 / issue
# #241 — must live in the SAME fence as the caller-loop per R-4-7 so
# $LAND_OUTCOME survives). Replaces the broken `trap 'finalize_marker $?'
# EXIT` pattern that fired at WI 1.8 fence-exit (skill entry) instead of
# at flow end. Mirrors /commit pr / /do pr / /fix-issues pr.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
# Reconstruct $MARKER path from $ZSKILLS_PIPELINE_ID + $SLUG (both
# preserved across fences by the persistent-shell harness; $SLUG also
# round-trips through the model-layer composition step at WI 1.6).
if [ -n "${ZSKILLS_PIPELINE_ID:-}" ] && [ -n "${SLUG:-}" ]; then
  _FINALIZE_MARKER="$MAIN_ROOT/.zskills/tracking/$ZSKILLS_PIPELINE_ID/fulfilled.quickfix.$SLUG"
elif [ -n "${MARKER:-}" ]; then
  _FINALIZE_MARKER="$MARKER"
else
  _FINALIZE_MARKER=""
fi
case "${LAND_OUTCOME:-__init__}" in
  merged|created|pr-ready) FINAL=complete ;;
  *) FINAL=failed ;;
esac
if [ -n "$_FINALIZE_MARKER" ] && [ -f "$_FINALIZE_MARKER" ]; then
  sed -i "s/^status: started$/status: $FINAL/" "$_FINALIZE_MARKER"
fi

# Cleanup transient requires marker (Plan LAND_PR_BYPASS_HARDENING Phase 2
# / R-5-5 / DA-4-5). Glob cleanup targets ANY requires.land-pr.* in the
# active quickfix.* pipeline subdir under MAIN_ROOT.
if [ -n "$ZSKILLS_PIPELINE_ID" ]; then
  rm -f "$MAIN_ROOT/.zskills/tracking/$ZSKILLS_PIPELINE_ID/requires.land-pr."*
else
  # Fallback: glob ALL quickfix.* subdirs. Acceptable per Residual
  # Risk #8 (cleanup race); orphans recovered by clear-tracking.sh.
  find "$MAIN_ROOT/.zskills/tracking" \
    -maxdepth 2 -type d -name 'quickfix.*' \
    -exec sh -c 'rm -f "$1"/requires.land-pr.*' _ {} \;
fi

# Release the issue claim (claim-work-item Phase 2 / W2.4) — only if one
# was acquired at WI 1.8 (ISSUE_NUM survives in the persistent shell).
# Release-on-resolution regardless of created vs merged vs pr-ready: the
# /quickfix invocation is terminating either way and /quickfix is one-shot
# (no later fire re-releases). $PIPELINE_ID = quickfix.$SLUG; reconstruct
# from $ZSKILLS_PIPELINE_ID if it didn't survive across fences.
if [ -n "${ISSUE_NUM:-}" ]; then
  _RELEASE_PIPELINE="${PIPELINE_ID:-${ZSKILLS_PIPELINE_ID:-}}"
  if [ -n "$_RELEASE_PIPELINE" ]; then
    bash "$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/claim-issue.sh" release "$ISSUE_NUM" --require-pipeline "$_RELEASE_PIPELINE"
  fi
fi
```

The end-of-fence explicit-finalize block (issue #241) rewrites the
marker's `status` based on `$LAND_OUTCOME` — `merged`/`created`/`pr-ready`
→ `status: complete`; anything else → `status: failed`. Early-exit
cleanup paths (Phase 1.10 user-decline, Phase 4 test failure, Phase 5
commit failure, Phase 5.5 verification failure, Phase 6 push failure,
and the no-result-file exit-5 path
inside the caller-loop) write `status: cancelled` or `status: failed`
inline before exiting. The CI poll and fix-cycle are owned by
`/land-pr`; `/quickfix`'s pre-PR triage (WI 1.5.4) and plan-review (WI
1.5.4b) gates remain upstream of this phase — CI monitoring is additive
coverage on top, not a replacement for them.

### Terminal marker states

The fulfillment marker at `$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/fulfilled.quickfix.$SLUG`
transitions from `status: started` at WI 1.8 entry to exactly one of:

- `status: complete` — PR created, URL appended via `pr: $PR_URL` (the
  append happens in the caller loop on the first iteration where
  `/land-pr` returns a `STATUS=created|monitored|merged`).
- `status: cancelled` is appended with `reason: user-declined` (the only
  documented reason). Triage-redirect, review-reject, and production
  model-layer decline at WI 1.5.5 leave no marker — they exit before
  WI 1.8 writes one.
- `status: failed` — any non-zero exit path after the marker was written.

No `.landed` marker is written. `/quickfix` has no worktree (no
`--worktree-path` is passed to `/land-pr`), and PR state is authoritative
via `gh pr view` — there is no cherry-pick-landing step to attest to.
