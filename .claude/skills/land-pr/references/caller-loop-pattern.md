# Canonical `/land-pr` caller loop pattern

This is the production-ready bash that callers (Phases 2–5: `/run-plan`,
`/commit pr`, `/do pr`, `/fix-issues pr`, `/quickfix`) copy verbatim and
customize only:

1. The pre-invoke body-prep block (`<CALLER_PRE_INVOKE_BODY_PREP>`).
2. The rebase-conflict handler (`<CALLER_REBASE_CONFLICT_HANDLER>`).
3. The fix-cycle agent dispatch block (`<DISPATCH_FIX_CYCLE_AGENT_HERE>`).

Everything else is identical across callers. This is intentional: a
single canonical loop means one place to fix bugs, one set of tests
(WI 1B.3 / 1B.4 cover the loop semantics), and one mental model for
maintainers.

## Key contracts

- **`/land-pr` is idempotent per call.** Re-invoking with the same
  branch is a no-op for steps already done: rebase up-to-date is
  exit 0; push up-to-date is exit 0; existing PR is detected and not
  re-created. The loop relies on this — the `continue` after a
  fix-cycle agent run re-enters `/land-pr` cleanly.
- **Body updates are CALLER-OWNED, not `/land-pr`'s.** /land-pr writes
  the body only on initial PR creation. Subsequent body updates
  (e.g., /run-plan's HTML-comment-marker progress splice) happen in
  `<CALLER_PRE_INVOKE_BODY_PREP>` BEFORE invoking /land-pr. This
  preserves user-added review notes.
- **Result-file values are single-line shell-safe.** Never `source`
  the result file. Use the allow-list parser below — it cannot
  evaluate shell metacharacters, even in maliciously-crafted PR
  titles or stderr text.
- **Fix-cycle agent runs at orchestrator level.** /land-pr was
  invoked at orchestrator level via the Skill tool, which loads its
  prose into your (top-level) context. Therefore the fix-cycle
  Agent dispatch is also at orchestrator level — NOT a nested
  subagent. See `fix-cycle-agent-prompt-template.md`.

## The canonical loop

```bash
# === BEGIN CANONICAL /land-pr CALLER LOOP ===
# Caller fills in: $BRANCH_NAME, $PR_TITLE, $BODY_FILE, $WORKTREE_PATH (optional),
# $LANDED_SOURCE, $AUTO ("true"/"false"), $CI_MAX_ATTEMPTS (default 2),
# $ISSUE_NUM (optional), and the fix-cycle agent dispatch block below.

ATTEMPT=0
MAX="${CI_MAX_ATTEMPTS:-2}"
# Sanitize $BRANCH_NAME for use in /tmp paths — branch names commonly
# contain `/` (feat/x, smoke/y), which would create unintended subdirs.
BRANCH_SLUG="${BRANCH_NAME//\//-}"
RESULT_FILE="/tmp/land-pr-result-$BRANCH_SLUG-$$.txt"

while :; do
  # Caller is responsible for any per-iteration body update BEFORE
  # invoking /land-pr. /run-plan splices its progress section into
  # $BODY_FILE here. Other callers regenerate $BODY_FILE here if they
  # need to. This block is a no-op for callers that compose the body
  # once before the loop.
  #
  #   <CALLER_PRE_INVOKE_BODY_PREP>
  #

  LAND_ARGS="--branch=$BRANCH_NAME --title=\"$PR_TITLE\" --body-file=$BODY_FILE --result-file=$RESULT_FILE --landed-source=$LANDED_SOURCE"
  [ -n "$WORKTREE_PATH" ] && LAND_ARGS="$LAND_ARGS --worktree-path=$WORKTREE_PATH"
  [ "$AUTO" = "true" ] && LAND_ARGS="$LAND_ARGS --auto"
  [ -n "$ISSUE_NUM" ] && LAND_ARGS="$LAND_ARGS --issue=$ISSUE_NUM"

  # Invoke /land-pr via the Skill tool. The Skill tool loads /land-pr's
  # prose into the current (orchestrator) context — so its internal
  # bash blocks run here, and any agent dispatches inside it (none
  # planned) would be at orchestrator level too. After /land-pr's
  # procedure completes, $RESULT_FILE is populated.
  #
  # Skill: { skill: "land-pr", args: "$LAND_ARGS" }

  if [ ! -f "$RESULT_FILE" ]; then
    echo "ERROR: /land-pr produced no result file at $RESULT_FILE" >&2
    exit 1
  fi

  # SAFE allow-list parsing (per WI 1.7). Never `source`. Reading line
  # by line and dispatching on a fixed key set guarantees that even
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

  # Sidecar cleanup — capture paths of files that should be cleaned up.
  # Per DA1-12: do NOT include CI_LOG_FILE in this list. The cleanup
  # pattern was previously `[[ "$f" != *"$CI_LOG_FILE"* ]]`, which has
  # two bugs: (a) when CI_LOG_FILE is empty (the CI=pass case), the
  # pattern `*""*` matches everything → no sidecars are cleaned, leaking
  # indefinitely; (b) substring containment can spuriously skip
  # CALL_ERROR_FILE if its path happens to contain CI_LOG_FILE as a
  # prefix. Build the array from cleanup-targets only.
  # Per DA2-11: use an array (not space-joined string) to avoid
  # field-splitting bugs if a sidecar path ever contains spaces.
  _CLEANUP_PATHS=("${LP[CALL_ERROR_FILE]:-}" "${LP[CONFLICT_FILES_LIST]:-}")
  rm -f "$RESULT_FILE"

  case "$STATUS" in
    rebase-conflict)
      # Caller-specific: if conflict-file count is small, dispatch
      # agent-assisted rebase resolution at orchestrator level, then
      # `continue` to re-invoke /land-pr. If too large or no agent
      # path, break and let the caller's .landed conflict marker stand.
      #
      #   <CALLER_REBASE_CONFLICT_HANDLER>
      #
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
      break ;;  # --no-monitor was used; caller's choice to skip CI poll
    fail)
      if [ "$ATTEMPT" -ge "$MAX" ]; then
        echo "INFO: CI fix-cycle exhausted ($ATTEMPT/$MAX); PR settles at pr-ci-failing" >&2
        break
      fi
      # ===== CALLER-SPECIFIC FIX-CYCLE AGENT DISPATCH =====
      # The agent runs at orchestrator level (NOT a nested subagent —
      # /land-pr was already invoked at orchestrator level via the
      # Skill tool; this dispatch is at the same level).
      #
      # Caller customizes the prompt with their work context (plan
      # content, issue body, task description, etc.) and the failure
      # log path (${LP[CI_LOG_FILE]}). See
      # `fix-cycle-agent-prompt-template.md` for the template.
      #
      #   <DISPATCH_FIX_CYCLE_AGENT_HERE>
      #
      # ====================================================
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
# intentionally NOT in the array — the caller may want to retain
# failure logs after the loop exits; if cleanup is needed, the caller
# does it explicitly after consuming the log.
for f in "${_CLEANUP_PATHS[@]}"; do
  [ -n "$f" ] && [ -f "$f" ] && rm -f "$f"
done
# === END CANONICAL /land-pr CALLER LOOP ===
```

## Why the allow-list parser, not `source`

A maliciously-crafted PR title or stderr text could reach the result
file (writer-side validation in `/land-pr` rejects multi-line and
shell-metacharacter values, but defense-in-depth matters). Sourcing the
file would evaluate any embedded `$(...)`, backticks, or variable
expansions. The allow-list parser:

1. Reads line by line — no shell evaluation of file contents.
2. Splits on the first `=` — no expansion of either side.
3. Dispatches via `case` against a fixed key set — unknown keys are
   warned and ignored, never assigned.
4. Stores into an associative array — no `eval`, no `declare`, no
   `printf -v`.

This guarantees that no value, however crafted, can reach shell
evaluation in the caller. The allow-list also catches truncated or
malformed result files: missing keys produce empty `LP[KEY]` lookups
(via `:-`), not undefined-variable errors.
