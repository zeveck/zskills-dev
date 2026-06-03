# /quickfix — Phases 3–6 (make the change → push)

> Execution modes for `/quickfix`, loaded after Phase 2 mode detection +
> branch creation in `SKILL.md`. The persistent shell carries `$MODE`,
> `$SLUG`, `$BRANCH`, `$BASE_BRANCH`, `$MARKER`, `$PIPELINE_ID`,
> `$ZSKILLS_PIPELINE_ID`, and `$ISSUE_NUMS` (+ back-compat `$ISSUE_NUM`)
> from Phase 2 into these phases.
> After Phase 6 (push), read `modes/land.md` for Phase 7.

## Phase 3 — Make the change

### WI 1.10 — User-edited mode

Enumerate changed files. Re-compute the three sets after the branch
switch so `CHANGED_FILES` reflects what will be staged (untracked files
carry across; new untracked on the new branch still count).

The user has already affirmed the dirty-tree scope at the model-layer
WI 1.5.5 prompt (or `$AUTO_FLAG=1` caused WI 1.5.5 to be skipped), so no
further bash confirmation runs here. (Phase 4 of QUICKFIX_GRAMMAR_REDESIGN
deleted the vestigial `read -r` block per DA H7; the production decline
path is WI 1.5.5 which exits BEFORE WI 1.8 runs — no marker, no branch.)

```bash
if [ "$MODE" = "user-edited" ]; then
  MODS=$(git diff --name-only HEAD)
  DELS=$(git diff --name-only --diff-filter=D HEAD)
  UNTRACKED=$(git ls-files --others --exclude-standard)
  CHANGED_FILES=$(printf '%s\n%s\n' "$MODS" "$UNTRACKED" | sed '/^$/d' | sort -u)

  echo "=== /quickfix user-edited mode ==="
  echo "Branch: $BRANCH (base: $BASE_BRANCH)"
  echo "Description: $DESCRIPTION"
  echo ""
  echo "Files changed:"
  echo "$CHANGED_FILES" | sed 's/^/  /'
  if [ -n "$DELS" ]; then
    echo "Files deleted:"
    echo "$DELS" | sed 's/^/  /'
  fi
  echo ""
  git --no-pager diff HEAD
fi
```

### WI 1.11 — Agent-dispatched mode

This is a **model-layer instruction**, not a bash block. Skills cannot
dispatch agents from bash (per CREATE_WORKTREE R-F1). Same pattern as
`skills/do/SKILL.md:342-358`.

When `MODE == "agent-dispatched"`:

1. Capture `PRE_HEAD=$(git rev-parse HEAD)` before dispatching.
2. Check `agents.min_model` from `.claude/zskills-config.json`; if set
   to a specific model, include the hint in the dispatch prompt
   (default `auto` → omit, inherit parent model).
3. **Dispatch one Agent tool call** with `subagent_type: "implementer"`. This
   inherits the Layer 0 Bash-timeout extension (see
   `.claude/agents/implementer.md` + the "Verifier-cannot-run rule" section in
   CLAUDE.md) so the impl agent's Bash calls don't trigger the bg+Monitor
   stall pattern (irrelevant here since the agent is told not to run
   tests, but the shape is uniform across all impl-class dispatches).
   The prompt instructs the subagent to:
   - `cd $MAIN_ROOT`
   - Implement `$DESCRIPTION`
   - **Do NOT** `git commit`, `git add`, or modify the index
   - **Do NOT** run tests, builds, linters, or formatters
   - When finished, list newly untracked files in the "done" report
   - **IMPORTANT:** Only leave files untracked that you intend to commit
     as part of this change. Delete any scratch, debug, or log files you
     created during exploration before reporting done. The skill will
     include all your remaining untracked files in the commit — any
     lingering scratch will ship in the PR.
4. After the Agent returns, verify:
   - `POST_HEAD=$(git rev-parse HEAD)`; if `POST_HEAD != PRE_HEAD`, the
     agent committed unexpectedly → exit 5 with cleanup (checkout base,
     delete branch).
   - `DIRTY_AFTER` is the sorted union of tracked modifications AND
     newly untracked files. The agent is expected (per step 3's
     IMPORTANT clause) to have cleaned up scratch/debug/log files
     before reporting done, so any remaining untracked files ARE part
     of the intended commit and SHOULD be staged. Definition:
     ```bash
     DIRTY_AFTER=$(printf '%s\n%s\n' "$(git diff --name-only HEAD)" "$(git ls-files --others --exclude-standard)" | sed '/^$/d' | sort -u)
     ```
   - If `DIRTY_AFTER` is empty, the agent did not change the tree →
     exit 5 with cleanup.
5. Populate:
   ```bash
   CHANGED_FILES="$DIRTY_AFTER"
   DELS=$(git diff --name-only --diff-filter=D HEAD)
   ```
6. Proceed to the test gate (WI 1.12).

## Phase 4 — Test gate (WI 1.12)

When `skip-tests` is passed, warn and skip. Otherwise run the project's
`unit_cmd` with output captured to a per-quickfix `/tmp/zskills-tests`
directory (never piped — see CLAUDE.md's "capture test output to a file,
never pipe" rule).

```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
if [ "$SKIP_TESTS" -eq 1 ]; then
  echo "WARN: skip-tests passed; skipping $UNIT_CMD" >&2
else
  TEST_OUT="/tmp/zskills-tests/$(basename "$MAIN_ROOT")-quickfix-$SLUG"
  mkdir -p "$TEST_OUT"
  if ! bash -c "$UNIT_CMD" > "$TEST_OUT/${TEST_OUTPUT_FILE:-.test-results.txt}" 2>&1; then
    echo "ERROR: tests failed. See $TEST_OUT/${TEST_OUTPUT_FILE:-.test-results.txt}" >&2
    # Rollback: leave edits in the working tree (user may have work to save),
    # drop back to base, delete the feature branch.
    if ! git checkout "$BASE_BRANCH"; then
      echo "ERROR: cleanup: failed to checkout $BASE_BRANCH after test failure." >&2
      exit 6
    fi
    if ! git branch -D "$BRANCH"; then
      echo "ERROR: cleanup: failed to delete branch $BRANCH after test failure." >&2
      exit 6
    fi
    # Explicit fail-finalize (issue #241).
    [ -f "$MARKER" ] && sed -i "s/^status: started$/status: failed/" "$MARKER"
    # Release the issue claim(s) (only if any were acquired at WI 1.8) —
    # this abandon path is after the acquire and before the Phase 7 finalize.
    if [ "${#ISSUE_NUMS[@]}" -gt 0 ]; then
      for _ISSUE_N in "${ISSUE_NUMS[@]}"; do
        bash "$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/claim-issue.sh" release "$_ISSUE_N" --require-pipeline "$PIPELINE_ID"
      done
      unset _ISSUE_N
    fi
    exit 4
  fi
fi
```

## Phase 5 — Commit (WI 1.13)

CLAUDE.md feature-complete discipline applies: stage by name only (never
`git add .` or `-A`). Reject directories — everything in `CHANGED_FILES`
must be a regular file path. Deletions are staged via `git add -u` on the
DELS list.

**Never bypass the pre-commit hook.** If the hook fires, fix the root
cause and rerun; do not pass any flag that would skip hook verification.

On commit failure, clean up verified-each-step: any cleanup step that
itself fails exits 6 (manual intervention).

```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
# Stage: reject directory entries.
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if [ -d "$MAIN_ROOT/$f" ]; then
    echo "ERROR: refusing to stage directory '$f' (stage individual files only)." >&2
    exit 5
  fi
done <<< "$CHANGED_FILES"

# shellcheck disable=SC2086
# CHANGED_FILES is a newline-separated list; xargs -r0 with tr guards against spaces-in-paths.
while IFS= read -r f; do
  [ -z "$f" ] && continue
  git add -- "$f"
done <<< "$CHANGED_FILES"

if [ -n "$DELS" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    git add -u -- "$f"
  done <<< "$DELS"
fi

# Co-author line for agent-dispatched mode comes from $COMMIT_CO_AUTHOR
# (resolved by the helper at fence-top). Empty value means no
# Co-Authored-By trailer (consumer opt-out).
```

**Compose the commit subject (model-layer).** Look at `git diff --cached`
and `git diff --cached --stat`. Set shell variable `COMMIT_SUBJECT` to a
conventional-commit line: `type(scope): summary` (type ∈ {feat, fix, docs,
refactor, chore, test, build, ci, style, perf, revert}; scope is the
primary skill/module/file being changed; summary ≤ 70 chars describing
what was actually changed). DESCRIPTION is the task spec — it goes into
the commit body as context, **not** the subject line.

The next bash fence consumes `$COMMIT_SUBJECT` to compose the full body
and invoke `git commit`. If the commit fails, the same fence runs the
cleanup (checkout base, delete branch, exit 5; each cleanup step
verified, any that itself fails exits 6 for manual intervention). Never
pass `--no-verify` — fix the root cause and retry (max 2 attempts on the
same error, then STOP and report).

```bash
# Resolve $COMMIT_CO_AUTHOR at fence-top — context compaction may have
# lost vars set in the earlier helper-source fence (per the convention at
# run-plan/modes/pr.md:325-345).
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi

# The model must set COMMIT_SUBJECT before this fence runs (see prose
# above). DESCRIPTION goes in the body as context, not the subject line.
if [ -z "${COMMIT_SUBJECT:-}" ]; then
  echo "ERROR: COMMIT_SUBJECT not set — model-layer composition step skipped." >&2
  exit 5
fi

if [ "$MODE" = "user-edited" ]; then
  # No Co-Authored-By: the human authored the edits.
  COMMIT_BODY=$(cat <<COMMIT_EOF
$COMMIT_SUBJECT

$DESCRIPTION

🤖 Generated with /quickfix (user-edited)
COMMIT_EOF
)
elif [ -n "$COMMIT_CO_AUTHOR" ]; then
  # agent-dispatched + co_author configured: include Co-Authored-By trailer.
  COMMIT_BODY=$(cat <<COMMIT_EOF
$COMMIT_SUBJECT

$DESCRIPTION

🤖 Generated with /quickfix (agent-dispatched)

Co-Authored-By: $COMMIT_CO_AUTHOR
COMMIT_EOF
)
else
  # agent-dispatched + co_author empty (consumer opt-out): no trailer.
  COMMIT_BODY=$(cat <<COMMIT_EOF
$COMMIT_SUBJECT

$DESCRIPTION

🤖 Generated with /quickfix (agent-dispatched)
COMMIT_EOF
)
fi

if ! git commit -m "$COMMIT_BODY"; then
  echo "ERROR: git commit failed (pre-commit hook, hook exit, or other)." >&2
  if ! git reset HEAD -- . ; then
    echo "ERROR: cleanup: git reset HEAD failed." >&2
    exit 6
  fi
  if ! git checkout "$BASE_BRANCH"; then
    echo "ERROR: cleanup: failed to checkout $BASE_BRANCH." >&2
    exit 6
  fi
  if ! git branch -D "$BRANCH"; then
    echo "ERROR: cleanup: failed to delete branch $BRANCH." >&2
    exit 6
  fi
  # Explicit fail-finalize (issue #241).
  [ -f "$MARKER" ] && sed -i "s/^status: started$/status: failed/" "$MARKER"
  # Release the issue claim(s) (only if any were acquired at WI 1.8).
  if [ "${#ISSUE_NUMS[@]}" -gt 0 ]; then
    for _ISSUE_N in "${ISSUE_NUMS[@]}"; do
      bash "$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/claim-issue.sh" release "$_ISSUE_N" --require-pipeline "$PIPELINE_ID"
    done
    unset _ISSUE_N
  fi
  exit 5
fi
```

## Phase 5.5 — Verify (WI 1.13.5)

Independent verification of the committed diff before push. Mirrors
`/do` Phase 3 (issue #713 — verification runs on all code changes,
not just `auto`). Skipped when `$FORCE -eq 1` (which already bypasses
triage + review) or when `$SKIP_TESTS -eq 1`.

**Dispatch a separate verification agent** running `/verify-changes`.
This is the full 7-phase verification: diff review, test coverage audit,
full test suite, manual verification if UI, fix problems, re-verify until
clean. Push (Phase 6) only happens if this agent reports clean.

**Dispatch shape.** Use the `Agent` tool with `subagent_type: "verifier"`.
The prompt should include the branch name (`$BRANCH`), the commit
subject (`$COMMIT_SUBJECT`), and the task description (`$DESCRIPTION`)
so the verifier has full context. After the dispatch returns, pipe
`$VERIFIER_RESPONSE` through
`bash "$CLAUDE_PROJECT_DIR/.claude/hooks/verify-response-validate.sh"`;
on exit 1 STOP — do NOT push.

**Layer 3 — verifier response validation:**

```bash
printf '%s' "$VERIFIER_RESPONSE" | bash "$CLAUDE_PROJECT_DIR/.claude/hooks/verify-response-validate.sh"
VALIDATE_EXIT=$?
```

On `VALIDATE_EXIT=1` — STOP. Do NOT push. Emit:

```
STOP: verifier returned without meaningful results.

$(cat /tmp/last-validate-stderr)

This is a verification FAIL, not a license to push. Surface to the
user. If the verifier agent file is missing, run /update-zskills.
```

**Skip conditions:** When `$FORCE -eq 1` or `$SKIP_TESTS -eq 1`, print
a WARN and skip this phase — `--force` is the explicit "trust-prompt"
opt-out for both triage/review and verification, and `skip-tests` signals
the user knows the change doesn't need a full verification pass.

## Phase 6 — Push (WI 1.14)

**Bare-branch form ONLY.** Never use a `src:dst` refspec when pushing
the feature branch (especially not one whose right-hand side targets a
protected ref). The refspec strip in `hooks/block-unsafe-generic.sh:215-220`
(`PUSH_TARGET="${PUSH_TARGET%%:*}"` followed by a protected-ref gate)
means refspec forms could bypass the guard when the right-hand side is a
protected ref — the bare form is independently sound and does not depend
on that strip.

On push failure, leave branch and commit intact; the user retries manually.

```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
if ! git push -u origin "$BRANCH"; then
  echo "ERROR: git push failed. Branch '$BRANCH' and its commit are intact locally; retry manually once the remote is reachable." >&2
  # Explicit fail-finalize (issue #241).
  [ -f "$MARKER" ] && sed -i "s/^status: started$/status: failed/" "$MARKER"
  # Release the issue claim(s) (only if any were acquired at WI 1.8).
  if [ "${#ISSUE_NUMS[@]}" -gt 0 ]; then
    for _ISSUE_N in "${ISSUE_NUMS[@]}"; do
      bash "$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/claim-issue.sh" release "$_ISSUE_N" --require-pipeline "$PIPELINE_ID"
    done
    unset _ISSUE_N
  fi
  exit 5
fi
```
