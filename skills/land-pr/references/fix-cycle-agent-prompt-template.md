# Fix-cycle agent prompt template (`/land-pr` CI failure)

When `/land-pr` reports `CI_STATUS=fail` and the caller's loop has
budget remaining (`$ATTEMPT < $MAX`), the caller dispatches a
fix-cycle agent at orchestrator level to diagnose and patch the
failure, then `continue`s the loop to re-invoke `/land-pr`.

This file is the canonical prompt template. Callers (Phases 2–5) copy
it and substitute `<CALLER_WORK_CONTEXT>` with their session-specific
context (plan content, issue body, task description, etc.).

## Where the agent runs

**Orchestrator level — NOT a nested subagent.**

`/land-pr` was loaded into your context by the Skill tool, so its
prose runs at top level. The fix-cycle agent dispatch is at the SAME
level — a sibling Agent call, not a child of `/land-pr`. The agent
itself has the full Agent toolset (Read, Edit, Write, Bash, Grep, etc.)
but **MUST NOT dispatch further Agent calls** — Claude Code subagents
cannot dispatch sub-subagents (Anthropic design).

If the agent's fix attempt requires nested agent dispatch, it must
stop and report. The caller's loop will retry up to `$CI_MAX_ATTEMPTS`
times; persistent failure means the issue genuinely needs human
intervention.

## Prompt template

```
You are a CI fix-cycle agent dispatched after `/land-pr` reported
CI_STATUS=fail on PR ${PR_URL} (#${PR_NUMBER}). Your job: diagnose
the failure, patch the code, commit and push. The caller's loop
will then re-invoke `/land-pr` automatically — you do NOT need to
re-run any landing primitives yourself.

## Constraints

- **You are running at orchestrator level. Do NOT dispatch further
  Agent tools.** Claude Code subagents cannot dispatch sub-subagents.
  If your fix attempt requires nested agent dispatch (e.g., parallel
  research, multi-agent review), STOP and report — the caller's loop
  will retry up to its max attempts, and persistent failure here is
  a signal the issue needs human attention.
- **Do not invoke `/land-pr` yourself.** The caller's loop owns
  re-invocation. Your job ends after `git push` (or after a clean
  diagnosis with no fixable code change).
- **Do not modify `.github/workflows/`** unless the failure is
  clearly a workflow bug (typo, wrong path, etc.) and not a code
  bug. Workflow changes need human review.
- **Honor existing tests.** Per CLAUDE.md "NEVER weaken tests to
  make them pass." If a test is genuinely wrong (testing the wrong
  expected value), say so explicitly in your report. Otherwise fix
  the code, not the test.
- **No `--no-verify`** on commits. Pre-commit hooks exist for safety.

## Inputs

- **PR URL:** ${PR_URL}
- **PR number:** ${PR_NUMBER}
- **Branch:** ${BRANCH_NAME}
- **Worktree path:** ${WORKTREE_PATH}  (cd here before any git/bash ops)
- **CI failure log:** ${CI_LOG_FILE}
  ${CI_LOG_FILE_NOTE}  # e.g., "(empty — log capture failed; run `gh pr checks ${PR_NUMBER}` and `gh run view --log-failed <run-id>` manually)"
- **Caller work context (the work that was being landed):**
  ${CALLER_WORK_CONTEXT}

## Procedure

1. Read ${CI_LOG_FILE} (if non-empty). Identify the failing test or
   failing build step. If the log is empty, run
   `gh pr checks ${PR_NUMBER}` to identify the failing check, then
   `gh run view --log-failed <run-id>` for the log.
2. cd ${WORKTREE_PATH}. Read the failing test source and the code it
   exercises. Form a hypothesis about the root cause.
3. **State the root cause explicitly** before writing any fix. Per
   CLAUDE.md /investigate discipline: PROVE you understand the
   failure before patching. A two-attempt cap applies (CLAUDE.md
   "NEVER thrash on a failing fix") — if your first fix doesn't
   resolve the failure, your second attempt must address a
   demonstrably different root cause.
4. Patch the code. Re-run the failing test locally if reasonable.
5. `git add` the changed files (be specific — avoid `git add -A`).
6. `git commit -m "<descriptive message>"`. The caller's loop relies
   on a new commit being pushable.
7. `git push` (the branch already has upstream tracking from the
   prior `/land-pr` invocation).
8. Report back: what was the root cause? What did you change?

## Output format

End your reply with a one-line summary the orchestrator can log:

```
FIX-CYCLE: root_cause="<short>" files_changed=<n> commit=<sha-or-pending>
```

If you could not fix the failure (test is genuinely wrong, requires
human judgment, requires nested agents, etc.), end with:

```
FIX-CYCLE-PUNT: reason="<short>"
```

The caller's loop will increment its attempt counter regardless;
PUNT is informational, telling the user / next iteration why this
attempt didn't produce a fix commit.
```

## Notes for callers

- **Customize `<CALLER_WORK_CONTEXT>` with session-specific context.**
  /run-plan passes the current phase's plan content. /commit pr
  passes the commit message and changed-file list. /do pr passes the
  task description. /fix-issues pr passes the issue body. /quickfix
  passes its description and triage notes.
- **Pass `${CI_LOG_FILE}` verbatim from the result file.** Don't
  re-derive it — the path is what `pr-monitor.sh` chose.
- **If `${CI_LOG_FILE}` is empty,** include
  `${CI_LOG_FILE_NOTE}="(empty — log capture failed; run \`gh pr
  checks ${PR_NUMBER}\` and \`gh run view --log-failed <run-id>\`
  manually)"`. The agent handles the missing-log case gracefully.
- **The `${CALLER_WORK_CONTEXT}` block is the only template slot
  callers customize.** Everything else (constraints, procedure,
  output format) is identical across callers, intentionally — a
  uniform fix-cycle UX is part of the unification.
