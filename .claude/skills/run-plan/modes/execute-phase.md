# /run-plan — Execute Phase (Phases 2-6)

This file contains the per-phase execution pipeline: implement, verify,
drift-detect, update progress, write report, plan completion, and land.
Variables from SKILL.md's argument-detection and Phase 1 parsing are in
scope: `$PLAN_FILE`, `$PHASE`, `$TRACKING_ID`, `$LANDING_MODE`,
`$FINISH_MODE`, `$AUTO_FLAG`, `$AUTO_ARG`, `$FULL_TEST_CMD`, `$TEST_MODE`,
`$BRANCH_PREFIX`, `$PLAN_FILE_FOR_READ`, `$WORKTREE_PATH`, etc.

## Phase 2 — Implement

### Execution mode detection

Check the phase text for an execution mode directive:

- **`### Execution: delegate <skill> [args]`** — delegate mode. The phase
  runs a skill (e.g., `/add-block`, `/run-plan`) that manages its own
  isolation. The orchestrating agent runs on **main**, not in a worktree.
  See "Delegate mode" below.
- **`### Execution: worktree`** or **no directive** — default worktree mode.
  See "Worktree mode" below.
- **`### Execution: direct`** — direct mode. No worktree — agent works
  directly on main. Phase 6 is a no-op (work is already on main). Only
  valid when `LANDING_MODE` is `direct` (validated in argument detection).
  See "Direct mode" below.

### Delegate mode

The orchestrating agent runs on main and calls the specified skill. The
skill manages its own worktree, verification, and landing.

1. **Dispatch agent on main** (no `isolation: "worktree"`). Give the agent:
   - The verbatim phase text (same rule as worktree mode)
   - Instruction to run the specified skill with the given arguments
   - Instruction to wait for the skill to finish and report the result

2. **Agent timeout: 2 hours.** Same as worktree mode.

3. **After the delegate skill finishes**, /run-plan proceeds to Phase 3
   (verification) which runs on main — checking that the delegated work
   actually landed correctly.

4. **In `finish` mode:** each delegate phase runs independently (no shared
   worktree — the delegate skill creates and destroys its own).

Use cases:
- `### Execution: delegate /add-block DiscreteFilter` — block expansion
- `### Execution: delegate /run-plan plans/SUB_PLAN.md finish auto` — meta-plans
- `### Execution: delegate /draft-plan plans/FOO.md <description> auto` — plan generation (omit `auto` if /run-plan was invoked without auto; thread `$AUTO_ARG` per #648)

### Plan-text drift signals

Include this VERBATIM in the dispatch prompt (delegate mode) so the
delegated skill's implementing agent surfaces stale numeric acceptance
criteria during its work:

> If during your work you observe a plan's acceptance criterion
> contains a numeric target (lines / tests / cases / commits / files)
> that doesn't match reality, emit a line of the form:
>
> ```
> PLAN-TEXT-DRIFT: phase=<N> bullet=<M> field=<str> plan=<stated> actual=<measured>
> ```
>
> in your final report. One per drift. Advisory — continue your work.

Tokens are parsed by `.claude/skills/run-plan/scripts/plan-drift-correct.sh --parse <report-file>`
in Phase 3.5. Format is single-line, space-delimited; `<field>` MUST NOT
contain `:` or `=`.

### Direct mode

When `LANDING_MODE` is `direct`:
- Do NOT create a worktree
- Agent works directly on main (current working directory)
- `### Execution: direct` in phase text is the recognized directive
- Phase 6: no-op (work is already on main, nothing to land)
- `.landed` marker: not written (no worktree to mark)

**Validation (already checked in argument detection):** `direct` + `main_protected: true` -> error before dispatch.

### Worktree mode (default)

One worktree for the entire phase (not per-item like `/fix-issues`).
**In `finish` mode, reuse the SAME worktree across all phases** — create
it once before the first phase, pass the same path to every phase's agent:

**Agent timeout: 2 hours.** Note the dispatch time. If the implementation
agent hasn't returned after 2 hours, declare it **failed**:
- Mark the phase as "Timed out" in `$ZSKILLS_REPORTS_DIR/plan-{slug}.md`
- The phase stays incomplete for the next run
- The worktree is a cleanup artifact — do NOT auto-land late results
- If the agent eventually returns, ignore it. Timed out = failed, period.
- If the plan was drafted with `/draft-plan`, the phase may be too large —
  consider splitting it (each phase should be ~3-5 components, ~500 lines).

1. **Create worktree via `.claude/skills/create-worktree/scripts/create-worktree.sh`** (do NOT use `isolation: "worktree"`):
   ```bash
   if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
     . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
   else
     . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
   fi
   PLAN_SLUG=$(basename "$PLAN_FILE" .md | tr '[:upper:]' '[:lower:]' | tr '_' '-')
   PROJECT_NAME=$(basename "$PROJECT_ROOT")

   # In finish/finish-auto modes, use one plan-scoped worktree shared
   # across all phases (Issue #191). In explicit single-phase invocations,
   # use a phase-scoped worktree.
   if [ "$FINISH_MODE" = "finish" ] || [ "$FINISH_MODE" = "finish-auto" ]; then
     CP_WORKTREE_PATH="/tmp/${PROJECT_NAME}-cp-${PLAN_SLUG}"
     CP_SLUG="${PLAN_SLUG}"
   else
     CP_WORKTREE_PATH="/tmp/${PROJECT_NAME}-cp-${PLAN_SLUG}-phase-${PHASE}"
     CP_SLUG="${PLAN_SLUG}-phase-${PHASE}"
   fi

   # Resume detection: directory-based, symmetric to PR mode's check at
   # execute-phase.md:372-375 (below). An existing plan-scoped cherry-pick
   # worktree means we're resuming the same plan across cron turns.
   if [ -d "$CP_WORKTREE_PATH" ]; then
     echo "Resuming existing cherry-pick worktree at $CP_WORKTREE_PATH"
     WORKTREE_PATH="$CP_WORKTREE_PATH"
   else
     WT=$(bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/create-worktree.sh" \
       --prefix cp \
       --allow-resume \
       --purpose "run-plan cherry-pick; plan=${PLAN_SLUG}; phase=${PHASE}; finish-mode=${FINISH_MODE:-single}" \
       --pipeline-id "run-plan.${TRACKING_ID}" \
       "${CP_SLUG}")
     RC=$?
     if [ "$RC" -ne 0 ]; then
       echo "create-worktree failed (rc=$RC) for cherry-pick mode" >&2
       exit "$RC"
     fi
     WORKTREE_PATH="$WT"
   fi
   # Derived by create-worktree.sh: path ${WORKTREE_ROOT}/${PROJECT_NAME}-cp-${CP_SLUG},
   # branch cp-${CP_SLUG} (unified across modes — used by post-run-invariants.sh).
   # The --allow-resume flag is required because in finish/finish-auto modes
   # the same branch (cp-${PLAN_SLUG}) is reused across phases.
   # Pre-flight prune+fetch+ff-merge, .zskills-tracked write, and .worktreepurpose
   # write are all owned by the script; do NOT duplicate them here.
   ```

   Cherry-pick mode worktree scope:
   - finish / finish-auto: one plan-scoped worktree shared across phases
     (path `/tmp/${PROJECT_NAME}-cp-${PLAN_SLUG}`, branch
     `cp-${PLAN_SLUG}`). Commits accumulate across phases; landing happens
     once after the final phase (see Phase 2's landing flow). Worktree is
     removed only after the final landing.
   - Single-phase invocations (`/run-plan plan.md <phase>`): one phase-
     scoped worktree (path `/tmp/${PROJECT_NAME}-cp-${PLAN_SLUG}-phase-${PHASE}`,
     branch `cp-${PLAN_SLUG}-phase-${PHASE}`). Lands that one phase.
     Worktree removed after that phase's landing.

2. **Dispatch implementation agent WITHOUT `isolation: "worktree"`.** The
   prompt tells the agent the worktree path and requires absolute paths:

   **Dispatch shape.** Use the `Agent` tool with `subagent_type: "implementer"`.
   This inherits the Layer 0 Bash-timeout extension (see
   `.claude/agents/implementer.md` + the "Verifier-cannot-run rule" section in
   CLAUDE.md) so the impl agent's Bash calls to run long test suites
   don't trigger the bg+Monitor stall pattern.

   **Before dispatching any Agent:** check `agents.min_model` in
   `.claude/zskills-config.json`. If set, use that model or higher
   (ordinal: haiku=1 < sonnet=2 < opus=3). Never dispatch with a
   lower-ordinal model than the configured minimum.

   ```
   You are working in worktree: $WORKTREE_PATH

   IMPORTANT: Use ABSOLUTE PATHS for all file operations.
   - Bash: run `cd $WORKTREE_PATH` before commands
   - Read/Edit/Write/Grep: use $WORKTREE_PATH/... paths
   Do not work in any other directory.
   ```

   **Hygiene constraint — NEVER commit ephemeral pipeline files.** The
   files `.worktreepurpose`, `.zskills-tracked`, and `.landed` are worktree
   lifecycle markers and must stay UNTRACKED throughout the run.

   Test output lives OUTSIDE the worktree, at `/tmp/zskills-tests/<worktree-
   basename>/` (see CLAUDE.md). The filenames `.test-results.txt` and
   `.test-baseline.txt` should NEVER appear in the worktree at all; if they
   do, a stale writer leaked them, and `.claude/skills/commit/scripts/land-phase.sh` treats any
   git-tracked version as a landing-time error (a canary for contract
   violations — not a normal-path cleanup).

   Do NOT include any of these files in `git add` when dispatching
   implementation or verification agents. When staging for a commit, name
   specific source files explicitly (`git add skills/X.md tests/Y.sh ...`)
   rather than patterns that could sweep ephemerals in. `.claude/skills/commit/scripts/land-phase.sh`
   expects the lifecycle markers to be untracked and will refuse to clean up a
   worktree that has any of them tracked — a staged-delete left over
   from a commit would block `git worktree remove` and leak zombies.

   **Failed-run cleanup:** If a phase fails terminally, write `.landed` with
   `status: failed` in the worktree before invoking the Failure Protocol. The
   cron preamble runs `git worktree prune` to clean up stale entries from
   container restarts or crashed runs.

3. **Agent prompt MUST include the verbatim plan text.** The implementing
   agent receives the EXACT text of the phase from the plan file — not a
   summary, not bullet points extracted from it, not "implement the mechanical
   domain." The full section with every requirement, formula, constraint,
   design note, and acceptance criterion.

   **The plan is the spec.** If the agent doesn't have the verbatim text,
   it will guess, and it will guess wrong.

   **For plan sections longer than ~100 lines:** write the verbatim text to
   a temp file (e.g., `/tmp/phase-text.md`) and tell the agent to `Read`
   the file. This avoids the natural LLM tendency to compress long text
   when inlining it in a prompt. Shorter sections can be inlined directly.

4. **If dispatching sub-agents for parallel work items**, each sub-agent gets:
   - The **full phase context** (verbatim) — so they understand the big picture
   - Their **specific scope** clearly delineated — e.g., "you are implementing
     Mass, Spring, Damper. Another agent is implementing sensors and force
     source."
   - **What parallel agents are doing** — enough to avoid conflicts (shared
     files, shared infrastructure) but not so much detail that it confuses
     their scope. Format: "Another agent is handling: [list of items]. You
     should not modify [shared files] until that work lands."
   - **Shared infrastructure dependencies** — if a base class or domain
     definition must exist first, that must be built sequentially before
     dispatching parallel agents. Never dispatch parallel agents that both
     need to create the same file.

5. **Within-phase parallelism is the agent's judgment call** — if items are
   independent (e.g., Mass, Spring, Damper components), the agent may dispatch
   sub-agents. If there's shared infrastructure to build first, it works
   sequentially then parallelizes. The skill does NOT force parallelism.

6. **Commit discipline:**
   - One logical unit per commit — clean git history
   - `$FULL_TEST_CMD` before every commit (resolved from config — see argument-detection section)
   - Tests alongside implementation, not deferred to later
   - The implementation agent does NOT commit. The verification agent runs the full test suite and commits if verification passes. This ensures the hook's test gate is satisfied (the committing agent's transcript contains the test command).
   - **Declare pipeline ID** early in execution (before any git operation):
     ```bash
     echo "ZSKILLS_PIPELINE_ID=run-plan.$TRACKING_ID"
     ```
     This echo is read by the tracking hook from the session transcript to
     scope marker checks to this pipeline. Uses last-match so re-invocations
     in the same session work correctly.
   - **Before dispatching any worktree agent**, write `.zskills-tracked` in the worktree:
     ```bash
     printf '%s\n' "run-plan.$TRACKING_ID" > "<worktree-path>/.zskills-tracked"
     ```
     Where `$TRACKING_ID` is the plan slug (e.g., `thermal-domain`). This file associates the worktree agent with this pipeline for hook enforcement.
   - **Rebase onto current main before final commit:**
     ```bash
     # Guard: ensure we're on the worktree branch, not accidentally on main
     CURRENT=$(git rev-parse --abbrev-ref HEAD)
     [ "$CURRENT" = "main" ] && { echo "ERROR: on main, expected worktree branch"; exit 1; }
     git fetch origin main && git rebase origin/main
     ```
     This ensures the commit contains only the agent's changes, not stale
     copies of files other agents already fixed on main. If rebase
     conflicts, abort (`git rebase --abort`) and proceed — the cherry-pick
     verification will catch stale files via selective extraction.

7. **Running tests in worktrees — CRITICAL.** Agents waste hours getting
   tests working in worktrees without these instructions. Include this
   VERBATIM in every implementation and verification agent prompt:

   > **Worktree test recipe:**
   >
   > **CRITICAL — Bash tool timeout:** when invoking `$FULL_TEST_CMD` via
   > the `Bash` tool, **pass `timeout: 600000`** (10 minutes). The default
   > 120000ms (2 min) is shorter than the suite's actual runtime (~3-4
   > min in zskills) and causes the Bash call to time out. **Do NOT
   > recover by retrying with `run_in_background: true` + `Monitor` /
   > `BashOutput` polling** — wake events for background processes do
   > not reliably deliver to subagents (you are a subagent), so the wait
   > never returns and the dispatch hangs at "Tests are running. Let me
   > wait for the monitor." Past failure: 6+ subagent crashes with
   > exactly that phrase across 2026-04-29 and 2026-04-30 sessions.
   > Always foreground-Bash with explicit long timeout; capture to file
   > as below; read the file when the call returns.
   >
   > 1. Start a dev server FIRST: `$DEV_SERVER_CMD &`
   > 2. Wait for it: `sleep 3`
   > 3. Run tests with output captured to a file (`Bash` tool with
   >    `timeout: 600000`):
   >    ```bash
   >    TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
   >    mkdir -p "$TEST_OUT"
   >    $FULL_TEST_CMD > "$TEST_OUT/$TEST_OUTPUT_FILE" 2>&1
   >    ```
   >    **Never pipe** through `| tail`, `| head`, `| grep` — it loses
   >    output and forces re-runs. Capture once, read the file.
   > 4. The dev server must stay running for E2E tests. If source files
   >    changed (they will have — you're implementing), E2E tests FAIL
   >    (not skip) without a dev server.
   > 5. If tests fail, **read `"$TEST_OUT/$TEST_OUTPUT_FILE"`** to find the failures.
   >    Then run ONLY the failing test file to iterate on the fix:
   >    `node --test tests/the-failing-file.test.js`
   >    Do NOT re-run `$FULL_TEST_CMD` to diagnose — that wastes
   >    minutes when the single file takes 30 seconds.
   > 6. After fixing, run the single file again to confirm. Then run
   >    ```bash
   >    TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
   >    mkdir -p "$TEST_OUT"
   >    $FULL_TEST_CMD > "$TEST_OUT/$TEST_OUTPUT_FILE" 2>&1
   >    ```
   >    ONE more time as the final gate before committing.
   > 7. Max 2 fix attempts at the same error — do not thrash.
   > 8. If a test fails in code you didn't touch, it may be pre-existing.
   >    See `/verify-changes` Phase 3 for the pre-existing failure protocol.

8. **No steps skipped or deferred.** If the plan says "implement 7 components,"
   implement 7 components. If it says "write tests for free vibration," write
   those exact tests. Do not stop after the easy items and declare the hard
   ones "future work."

### Plan-text drift signals

Include this VERBATIM in every implementation-agent prompt (worktree
mode) so the agent flags numeric acceptance bands that don't match
reality at execution time:

> If during your work you observe a plan's acceptance criterion
> contains a numeric target (lines / tests / cases / commits / files)
> that doesn't match reality, emit a line of the form:
>
> ```
> PLAN-TEXT-DRIFT: phase=<N> bullet=<M> field=<str> plan=<stated> actual=<measured>
> ```
>
> in your final report. One per drift. Advisory — continue your work.

Tokens are parsed by `.claude/skills/run-plan/scripts/plan-drift-correct.sh --parse <report-file>`
in Phase 3.5. Format is single-line, space-delimited; `<field>` MUST NOT
contain `:` or `=`. Phase format: `phase=1`, `phase=4A`, etc.; bullet is
the 1-indexed ordinal of a numeric-bearing bullet within the phase's
`### Acceptance Criteria` section.

### PR mode (Phase 2)

When `LANDING_MODE == pr`, the orchestrator creates a persistent worktree with
a named feature branch. All phases accumulate on the same branch (one PR per
plan). The worktree persists across cron turns for chunked execution.

**Mixed mode validation:** When `LANDING_MODE` is `pr`, scan the current phase text:
- `### Execution: direct` → ERROR: "Mixed execution modes not allowed in PR
  plans. All phases must use worktree or delegate mode."
- `### Execution: delegate ...` → OK (delegate manages its own isolation)
- `### Execution: worktree` or no directive → OK (default)

**Branch naming:** `{branch_prefix}{plan-slug}`
- `branch_prefix` from config (`execution.branch_prefix`), default `"feat/"`
- `plan-slug` derived from plan file path: lowercase, hyphens, no extension
  - `$ZSKILLS_PLANS_DIR/THERMAL_DOMAIN.md` → `thermal-domain`
  - `$ZSKILLS_PLANS_DIR/ADD_FILTER_BLOCK.md` → `add-filter-block`

<!-- allow-hardcoded: "plans/ reason: illustrative example showing user-typed plan-file argument value (the literal slash-command form `/run-plan plans/THERMAL_DOMAIN.md`); the actual plans-dir is resolved via $ZSKILLS_PLANS_DIR (zskills-paths.sh) at the read-authority block earlier in the skill -->
```bash
# Derive plan slug — example with user-typed plan path
PLAN_FILE="plans/THERMAL_DOMAIN.md"
PLAN_SLUG=$(basename "$PLAN_FILE" .md | tr '[:upper:]' '[:lower:]' | tr '_' '-')

BRANCH_NAME="${BRANCH_PREFIX}${PLAN_SLUG}"
FEATURE_BRANCH="$BRANCH_NAME"  # unified across modes — used by post-run-invariants.sh
PROJECT_NAME=$(basename "$PROJECT_ROOT")
WORKTREE_PATH="/tmp/${PROJECT_NAME}-pr-${PLAN_SLUG}"
```

**PR-mode bookkeeping rule:** in PR mode, orchestrator bookkeeping (tracker updates, plan reports, `$ZSKILLS_AUDIT_DIR/PLAN_REPORT.md` regen, plan-frontmatter completion, mark-Done) commits **inside the worktree on the feature branch**, not on `main`. The feature branch is the single source of truth; the squash merge lands everything atomically on `origin/main`, keeping local `main` in lockstep. In cherry-pick/direct mode these commits stay on `main` as before. Every "commit on main" instruction below for bookkeeping must be read through this lens.

**Worktree creation — via `.claude/skills/create-worktree/scripts/create-worktree.sh`, NOT `isolation: "worktree"`:**

```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
# Resume detection stays directory-based (R2-M1): an existing PR worktree
# means we're resuming the same plan across cron turns.
if [ -d "$WORKTREE_PATH" ]; then
  echo "Resuming existing PR worktree at $WORKTREE_PATH"
else
  WORKTREE_PATH=$(bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/create-worktree.sh" \
    --prefix pr \
    --branch-name "$BRANCH_NAME" \
    --allow-resume \
    --purpose "run-plan PR mode; plan=${PLAN_SLUG}" \
    --pipeline-id "run-plan.${TRACKING_ID}" \
    "${PLAN_SLUG}")
  RC=$?
  if [ "$RC" -ne 0 ]; then
    echo "create-worktree failed (rc=$RC) for PR mode" >&2
    exit "$RC"
  fi
fi
# create-worktree.sh owns pre-flight prune+fetch+ff-merge, the
# underlying safe add (with ZSKILLS_ALLOW_BRANCH_RESUME=1 set via
# --allow-resume), .zskills-tracked (from --pipeline-id), and
# .worktreepurpose writes.
```

**One branch per plan.** All phases accumulate on the same branch. The worktree
persists across cron turns for chunked execution. Do NOT create a new worktree
per phase.

**Dispatching agents to the worktree:** Dispatch agents WITHOUT
`isolation: "worktree"`. The agent's prompt tells it to work in the worktree:

```
Agent tool prompt:
  "You are implementing Phase N of plan X.
   FIRST: cd /tmp/myproject-pr-thermal-domain
   All work happens in that directory. Do not work in any other directory.

   <phase work items here>

   Commit rules:
   - Do NOT commit. The verification agent commits after review.
   - Stage specific files by name (not git add .)
   ..."
```

The key line is `FIRST: cd $WORKTREE_PATH` — the agent treats this as a
mandatory first action. Without `isolation: "worktree"`, the agent starts in
the main repo directory, so the `cd` instruction is essential.

**Test baseline capture (orchestrator practice):** Before dispatching the
implementation agent, the orchestrator captures a test baseline in the worktree:

```bash
# Resolve config-derived vars at fence-top — context compaction may have
# lost vars set in earlier fences (per the convention at modes/pr.md:325-345).
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi

# Orchestrator captures baseline BEFORE impl agent starts
cd "$WORKTREE_PATH"
if [ -n "$FULL_TEST_CMD" ]; then
  TEST_OUT="/tmp/zskills-tests/$(basename "$WORKTREE_PATH")"
  mkdir -p "$TEST_OUT"
  $FULL_TEST_CMD > "$TEST_OUT/.test-baseline.txt" 2>&1 || true
fi
```

### Post-implementation tracking

After the implementation agent finishes (whether worktree or delegate mode),
create the implementation step marker. Per the PR-mode bookkeeping rule,
the bookkeeping anchor is `$WORKTREE_PATH` in PR mode and `$CLAUDE_PROJECT_DIR`
otherwise — sourced via the path-config helper:
```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
BOOKKEEPING_ROOT="$CLAUDE_PROJECT_DIR"
[ "$LANDING_MODE" = "pr" ] && [ -n "$WORKTREE_PATH" ] && BOOKKEEPING_ROOT="$WORKTREE_PATH"
ZSKILLS_PATHS_ROOT="$BOOKKEEPING_ROOT" \
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh" ]; then
    . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh"
  else
    source "$BOOKKEEPING_ROOT/.claude/skills/update-zskills/scripts/zskills-paths.sh"
  fi
PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
PIPELINE_ID=$(bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/sanitize-pipeline-id.sh" "$PIPELINE_ID")
PLAN_SLUG=$(basename "$PLAN_FILE" .md | tr '[:upper:]' '[:lower:]' | tr '_' '-')
printf 'phase: %s\ncompleted: %s\n' "$PHASE" "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
  > "$BOOKKEEPING_ROOT/.zskills/tracking/$PIPELINE_ID/step.run-plan.$TRACKING_ID.implement"
bash "$ZSKILLS_SKILLS_ROOT/run-plan/scripts/claim-plan.sh" \
  set-phase "$PLAN_SLUG" --require-pipeline "$PIPELINE_ID" --current-phase "Phase $PHASE — implemented" || true
```

### Pre-verification tracking

The `requires.verify-changes.$TRACKING_ID` marker was created at skill
entry (Phase 1 step 8). The hook is enforcing it. Pass the tracking ID to
the verification agent so it can create its own fulfillment marker.

> **Note:** The per-pipeline verification requirement
> (`requires.verify-changes.$TRACKING_ID`) is **distinct** from
> `requires.verify-changes.final.<META_PLAN_SLUG>` which is a cross-branch
> final verification marker with a different lifecycle — created by
> `/research-and-go` Step 0, fulfilled after ALL sub-plans complete. Phase A
> does not modify or consolidate this marker; the two coexist independently.

Pass the tracking ID to the verification agent in the dispatch prompt so it
can create its own fulfillment marker:
> Your tracking ID is `$TRACKING_ID`. On entry, create
> `fulfilled.verify-changes.$TRACKING_ID` in the main repo's
> `.zskills/tracking/` directory.

## Phase 3 — Verify (separate agent)

Critical: the verification agent is NOT the implementing agent. Fresh eyes
catch implementer blindspots — deferred hard parts, missing tests, stubs,
shortcuts.

### Dispatch protocol

**Check your tool list.** If `Agent` (or `Task`) is in your tool list,
you are at top level — dispatch a fresh verification subagent per the
protocol below. The implementation subagent (in its worktree) and the
verification subagent are sibling subagents of you, the top-level
orchestrator. The verifier has independent context from the implementer.

**If you do NOT have the `Agent` tool**, you are running as a subagent
yourself (Claude Code subagents have no Agent tool, by Anthropic's
design at https://code.claude.com/docs/en/sub-agents). Run `/verify-changes
worktree` inline in your current context — the verifier subagent (you)
is fresh relative to the implementer subagent that ran in a separate
context. This fallback is mostly defensive since /run-plan typically runs
at top level.

**Agent timeout: 45 minutes.** Verification should take 15-30 minutes —
reading diffs, running tests, checking acceptance criteria. If a verification
agent hasn't returned after 45 minutes, it is thrashing (likely on test
setup or repeated test failures). Declare it **failed** and invoke the
Failure Protocol. Do NOT let verification agents run indefinitely — they
are the most common source of time waste.

### Delegate mode verification

**Dispatch shape.** Use the `Agent` tool with `subagent_type: "verifier"` (same agent definition as worktree mode — `.claude/agents/verifier.md`). The Layer 3 invocation block (`### Failure Protocol — verifier response validation` below) applies identically: pipe the verifier's response through `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/verify-response-validate.sh"` immediately after the dispatch returns; on `VALIDATE_EXIT=1` OR 45-min timeout, emit the verbatim STOP message and halt the pipeline.

If this phase used delegate execution, verification runs on **main**:

1. **Verify commits landed** — check `git log --oneline -10` for the
   delegate's commits. If expected commits are missing, the delegate
   failed to land — invoke Failure Protocol.
2. **Run `$FULL_TEST_CMD` on main** (resolve via the dual-lane prelude in
   references/canonical-config-prelude.md §1 if you don't already have it in
   your environment) — the delegate already tested, but
   /run-plan verifies against the plan's acceptance criteria.
3. **Check acceptance criteria** from the verbatim plan text — the delegate
   skill doesn't know the plan's criteria, only /run-plan does.
4. Dispatch a verification agent if needed (same rules as worktree mode
   below, but targeting main instead of a worktree path).

#### Plan-text drift signals (delegate mode verification)

Include this VERBATIM in the verifier dispatch prompt:

> If during your verification you observe a plan's acceptance criterion
> contains a numeric target (lines / tests / cases / commits / files)
> that doesn't match reality, emit a line of the form:
>
> ```
> PLAN-TEXT-DRIFT: phase=<N> bullet=<M> field=<str> plan=<stated> actual=<measured>
> ```
>
> in your final report. One per drift. Advisory — continue your work.

**Verifiers MUST re-detect drift independently.** Do not forward the
implementation agent's tokens — re-measure each numeric acceptance
criterion against current reality. If implementation skipped the check
OR implementation IS the source of drift, the verifier catches it.
Phase 3.5 processes the UNION of both reports' tokens.

#### Smoke-procedure revert mechanics (delegate mode verification)

Include this VERBATIM in the verifier dispatch prompt:

> Many plan ACs include manual smoke procedures: temporarily modify a
> file under test → run a script → confirm a behavior change → revert
> the throwaway. When you revert, **first check whether the file has
> uncommitted changes**: `git status -s <file>`. A line beginning with
> ` M`, `MM`, `AM`, or any other dirty-state marker means uncommitted
> impl work is present.
>
> - **Uncommitted: DO NOT use `git checkout <file>`.** It reverts to
>   HEAD, which is the pre-implementation state — silently wiping the
>   implementer's uncommitted work. /run-plan's design contract is
>   "implementer writes, verifier commits"; the file you're
>   smoke-testing typically has uncommitted impl changes. Use Edit to
>   remove the specific throwaway lines you added, or save+restore
>   with `cp <file> /tmp/$(basename <file>).pre-smoke` and
>   `cp /tmp/$(basename <file>).pre-smoke <file>` (basename avoids
>   creating nested /tmp paths that don't exist for relative paths
>   with subdirectories).
> - **Clean (no uncommitted changes)**: `git checkout <file>` is safe
>   and reverts only your throwaway.
>
> This guidance applies to **mid-smoke reverts only**. Post-failure
> rollbacks (e.g., Phase 3.5 plan-file rollback) run after something
> has gone wrong on files that should match HEAD — `git checkout` is
> correct there.
>
> If you suspect the file under test has been clobbered (file size
> drops, expected lines vanish), STOP. Do NOT reconstruct from the
> spec — even if you re-run every AC against the reconstruction, the
> orchestrator cannot validate that your reconstruction matches the
> implementer's actual intent. Invoke the Failure Protocol so the
> orchestrator can re-dispatch implementation cleanly against a
> known-clean baseline.

### Worktree mode verification

**Dispatch shape.** Use the `Agent` tool with `subagent_type: "verifier"`. The verifier agent definition lives at `.claude/agents/verifier.md` — `tools: Read, Grep, Glob, Bash, Edit, Write`; frontmatter PreToolUse hook (`inject-bash-timeout.sh`) auto-extends every Bash call's timeout to 600000 ms (10 min) so the bg+Monitor recovery reflex never engages. The verifier CANNOT dispatch sub-subagents — fix-agent dispatch (Phase 3 step 3 "fresh fix agent") stays at the orchestrator level. If the dispatch returns "no such agent" or equivalent, the verifier agent file is missing — STOP and run `/update-zskills` (Phase 5 of the verifier-agent-fix plan teaches it to install `.claude/agents/verifier.md`).

1. **Dispatch verification agent** targeting the worktree's changes. The
   verification agent is dispatched with `subagent_type: "verifier"` and
   **without** `isolation: "worktree"` — the
   Agent tool's `isolation` parameter creates a NEW worktree, it cannot attach
   to an existing one.

   **Before dispatching:** check `agents.min_model` in `.claude/zskills-config.json`.
   If set, use that model or higher (ordinal: haiku=1 < sonnet=2 < opus=3). Never
   dispatch with a lower-ordinal model than the configured minimum.

   Give the verification agent:
   - The **worktree path** from Phase 2 (so it can read files and run tests
     there). The verifier must run tests via:

     ```bash
     if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
       . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
     else
       . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
     fi
     cd <worktree-path>
     TEST_OUT="/tmp/zskills-tests/$(basename "<worktree-path>")"
     mkdir -p "$TEST_OUT"
     $FULL_TEST_CMD > "$TEST_OUT/${TEST_OUTPUT_FILE:-.test-results.txt}" 2>&1
     ```

     The orchestrator substitutes `$FULL_TEST_CMD` in the prompt with the
     config-resolved literal command BEFORE dispatching the agent — the
     verifier never resolves it themselves (don't let them search the repo).
     If `TEST_MODE=skipped`, dispatch this block with the instruction
     "Do NOT run tests; report `Tests: skipped — no test infra` in your
     verification report" instead of the bash block above.

     Note: compute `$TEST_OUT` from the worktree-path LITERAL you were handed,
     NOT from `$(pwd)` at prompt-entry time — the orchestrator dispatches you
     without `isolation`, so your initial cwd is the orchestrator's (typically
     main), and a pre-cd `$(pwd)` would yield the wrong basename and miss the
     baseline.

     Orchestrator-runtime note: when the orchestrator constructs the verifier
     prompt, it substitutes the literal string `<worktree-path>` with the
     actual worktree path BEFORE dispatching. The verifier sees a fully-
     substituted prompt — no placeholder parsing on its side. Both orchestrator
     baseline capture (line 811) and verifier `$TEST_OUT` derivation MUST use
     `basename` of the SAME path literal, so the baseline and the results land
     in the same `/tmp/zskills-tests/<name>/` bucket.

   - The **worktree branch name** (so it can diff against main using the
     merge-base form: `git diff $(git merge-base origin/main HEAD)..HEAD`,
     or commit-only: `git show HEAD`. Do NOT use `main...<branch>` or
     bare `origin/main..HEAD --stat` — those are symmetric and produce
     false-positive scope-creep on sibling-sprint cadence. See
     `.claude/agents/verifier.md`.)
   - The **verbatim phase text** from the plan (same text the implementer got)
   - Instruction to run `/verify-changes worktree` — the verification agent
     runs this, NOT you. Do NOT run verification yourself — you are the
     orchestrator with implementer bias.
   - The **work items checklist** — verify each item was actually implemented,
     not stubbed or skipped
   - The **`"$TEST_OUT/.test-baseline.txt"` file** captured before implementation
     started (if `FULL_TEST_CMD` is configured). The verification agent should:
     - Read `"$TEST_OUT/.test-baseline.txt"` (baseline captured before implementation)
     - Compare against `"$TEST_OUT/${TEST_OUTPUT_FILE:-.test-results.txt}"` (results after running tests now)
     - **New failures** (in results but not in baseline) → regressions, must
       be fixed before the phase can commit
     - **Pre-existing failures** (in both baseline and results) → note in report,
       do not fix (these predate this phase)
     - **Resolved failures** (in baseline but not in results) → note positively
       as improvements
     - If `"$TEST_OUT/.test-baseline.txt"` is absent (`FULL_TEST_CMD` not configured),
       treat all failures as potentially new — report all of them
     - **Tally check (mandatory).** Assert the results file contains a
       canonical summary line — for zskills literally
       `Overall: N/M passed, F failed`. If the line is **absent**, the suite
       did not complete (truncation / hang / OOM) — FAIL verification, do not
       count inline PASS lines as success. Then require `F == 0` AND `N == M`
       AND (when baseline is present) `N >= baseline_N`. Past firing
       2026-05-18: verifier reported "3313/3313 passed" by counting inline
       PASS lines; final tally was 3311/3313 — two regressions slipped
       (anchor `feedback_verify_by_count_not_any_fail`).

2. **Additional plan-specific checks** (the verifier checks these against the
   verbatim plan text — not against a summary):
   - Do commits cover ALL work items listed in the plan? Any missing?
   - Does implementation follow the plan's stated approach? (e.g., "use
     internal displacement state for Spring" — did it actually do that?)
   - Are constraints respected? (no external solvers, etc.)
   - Any deferred hard parts, stubs, TODOs, or placeholder implementations?
   - Do acceptance criteria match? (e.g., "test free vibration x(t) = A cos(wt)"
     — does that exact test exist with that exact formula?)

   **"Noted as gap" is a verification FAILURE.** If any work item, acceptance
   criterion, or checklist item was skipped and merely noted — that is not a
   pass. It is a fail. The verifier must not rationalize skipped steps as
   "not blockers" or "gaps for future work." If the plan says to do it and
   it wasn't done, verification fails. Period.

   Past failure: Block Expansion Plan Phase 1 — the implementer skipped the
   example model (Step 7 of `/add-block`) and runtime entry (Step 10). The
   verifier saw both skips but wrote "gaps noted" instead of invoking the
   Failure Protocol. The phase was reported as complete with missing work.

3. **If verification fails:**
   - Without `auto`: present findings, ask user what to do
   - With `auto`: dispatch a **fresh fix agent** for the missing items.
     The fix agent receives: the worktree path, the verbatim plan text,
     the specific items that failed verification, and instructions to
     complete them — not summarize them, not note them, COMPLETE them.
     If the missing item is an example model, the fix agent calls
     `/add-example`. If it's a runtime entry, the fix agent adds it.
     The fix agent is NOT the implementer — it's a fresh agent with no
     bias toward "this is good enough."

     **Dispatcher: the orchestrator (top-level `/run-plan`), not the verifier subagent.** The verifier's tool allowlist excludes `Agent`; sub-subagent dispatch is categorically unavailable per https://code.claude.com/docs/en/sub-agents. The verifier reports failed-AC findings back; the orchestrator dispatches the fresh fix agent.

     After the fix agent finishes, re-verify (max 2 rounds). If still
     failing after 2 fix+verify cycles, **STOP** — needs human judgment.
     Invoke the Failure Protocol.

### Failure Protocol — verifier response validation

**Failure Protocol — verifier response validation (Layer 3).**

**Detection runs immediately after the verifier `Agent` dispatch returns**, before any tracker write or commit:

```bash
printf '%s' "$VERIFIER_RESPONSE" | bash "$CLAUDE_PROJECT_DIR/.claude/hooks/verify-response-validate.sh"
VALIDATE_EXIT=$?
```

The script (sourced from `hooks/verify-response-validate.sh` at zskills source; installed by `/update-zskills` Step C) checks:
- **Stalled-string trigger** — case-insensitive substring match of any of 7 whitelisted phrases against the LAST 10 LINES of the response (`let me wait for the monitor`, `tests are running. let me wait`, `monitor will signal`, `monitor to signal`, `still searching. let me wait`, `waiting on bashoutput`, `polling bashoutput`).
- **Min-byte threshold** — response < 200 bytes is treated as empty/stub.

Exit 0 = PASS (proceed to tracker write + commit). Exit 1 = FAIL — read stderr to see which pattern or threshold fired.

**AND** detect agent-timeout-exceeded: if the dispatch took longer than 45 minutes (existing rule, line ~1275-1280), treat as failed.

**On detection (`VALIDATE_EXIT=1` OR timeout):** STOP. Do NOT write the verification step marker. Do NOT proceed to Phase 3.5 plan-drift correction. Do NOT proceed to Phase 4 commit. Emit the verbatim STOP message:

```
STOP: verifier returned without meaningful results.

$(cat /tmp/last-validate-stderr)

This is a verification FAIL, not a routing decision.

Failure Protocol:
1. Roll back any uncommitted phase work in <worktree-path>
   (git status; user-driven cleanup).
2. Tracker entry: requires.verify-changes.<TRACKING_ID> stays unfulfilled.
3. If you just installed the verifier agent (this is the first
   dispatch of the session post-install), restart Claude Code (or
   open a new session) before re-dispatching — `.claude/agents/`
   is auto-discovered ONLY at session start (per
   code.claude.com/docs/en/sub-agents priority table). There is
   no in-session reload command; `/agents reload` does not exist.
4. Halt the pipeline. Do not auto-retry. Re-dispatch only after
   surfacing the failure and confirming the verifier agent file is
   installed (.claude/agents/verifier.md exists; bash
   $CLAUDE_PROJECT_DIR/.claude/hooks/inject-bash-timeout.sh < /dev/null
   exits 0).
```

**Inline self-verification is NOT acceptable recovery.** Per CLAUDE.md ## Verifier-cannot-run rule.

**No automatic re-dispatch.** Re-dispatching with the same agent type hits the same wall.

#### Plan-text drift signals (worktree mode verification)

Include this VERBATIM in the verifier dispatch prompt:

> If during your verification you observe a plan's acceptance criterion
> contains a numeric target (lines / tests / cases / commits / files)
> that doesn't match reality, emit a line of the form:
>
> ```
> PLAN-TEXT-DRIFT: phase=<N> bullet=<M> field=<str> plan=<stated> actual=<measured>
> ```
>
> in your final report. One per drift. Advisory — continue your work.

**Verifiers MUST re-detect drift independently.** Do not forward the
implementation agent's tokens — re-measure each numeric acceptance
criterion against current reality. If implementation skipped the check
OR implementation IS the source of drift, the verifier catches it.
Phase 3.5 processes the UNION of both reports' tokens.

#### Smoke-procedure revert mechanics (worktree mode verification)

Include this VERBATIM in the verifier dispatch prompt:

> Many plan ACs include manual smoke procedures: temporarily modify a
> file under test → run a script → confirm a behavior change → revert
> the throwaway. When you revert, **first check whether the file has
> uncommitted changes**: `git status -s <file>`. A line beginning with
> ` M`, `MM`, `AM`, or any other dirty-state marker means uncommitted
> impl work is present.
>
> - **Uncommitted: DO NOT use `git checkout <file>`.** It reverts to
>   HEAD, which is the pre-implementation state — silently wiping the
>   implementer's uncommitted work. /run-plan's design contract is
>   "implementer writes, verifier commits"; the file you're
>   smoke-testing typically has uncommitted impl changes. Use Edit to
>   remove the specific throwaway lines you added, or save+restore
>   with `cp <file> /tmp/$(basename <file>).pre-smoke` and
>   `cp /tmp/$(basename <file>).pre-smoke <file>` (basename avoids
>   creating nested /tmp paths that don't exist for relative paths
>   with subdirectories).
> - **Clean (no uncommitted changes)**: `git checkout <file>` is safe
>   and reverts only your throwaway.
>
> This guidance applies to **mid-smoke reverts only**. Post-failure
> rollbacks (e.g., Phase 3.5 plan-file rollback) run after something
> has gone wrong on files that should match HEAD — `git checkout` is
> correct there.
>
> If you suspect the file under test has been clobbered (file size
> drops, expected lines vanish), STOP. Do NOT reconstruct from the
> spec — even if you re-run every AC against the reconstruction, the
> orchestrator cannot validate that your reconstruction matches the
> implementer's actual intent. Invoke the Failure Protocol so the
> orchestrator can re-dispatch implementation cleanly against a
> known-clean baseline.

### Post-verification tracking

After verification passes, create the verification step marker. Per the
PR-mode bookkeeping rule, the bookkeeping anchor is `$WORKTREE_PATH` in PR
mode and `$CLAUDE_PROJECT_DIR` otherwise — sourced via the path-config helper:
```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
BOOKKEEPING_ROOT="$CLAUDE_PROJECT_DIR"
[ "$LANDING_MODE" = "pr" ] && [ -n "$WORKTREE_PATH" ] && BOOKKEEPING_ROOT="$WORKTREE_PATH"
ZSKILLS_PATHS_ROOT="$BOOKKEEPING_ROOT" \
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh" ]; then
    . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh"
  else
    source "$BOOKKEEPING_ROOT/.claude/skills/update-zskills/scripts/zskills-paths.sh"
  fi
PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
PIPELINE_ID=$(bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/sanitize-pipeline-id.sh" "$PIPELINE_ID")
PLAN_SLUG=$(basename "$PLAN_FILE" .md | tr '[:upper:]' '[:lower:]' | tr '_' '-')
printf 'phase: %s\nresult: pass\ncompleted: %s\n' "$PHASE" "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
  > "$BOOKKEEPING_ROOT/.zskills/tracking/$PIPELINE_ID/step.run-plan.$TRACKING_ID.verify"
bash "$ZSKILLS_SKILLS_ROOT/run-plan/scripts/claim-plan.sh" \
  set-phase "$PLAN_SLUG" --require-pipeline "$PIPELINE_ID" --current-phase "Phase $PHASE — verified" || true
```

## Phase 3.5 — Detect and auto-correct plan-text drift

Runs AFTER Phase 3's `### Post-verification tracking` writes
`step.run-plan.$TRACKING_ID.verify`, and BEFORE Phase 4's tracker
commit. Reads both the implementation agent's and verification
agent's reports for `PLAN-TEXT-DRIFT:` tokens and auto-corrects
the plan file.

### 1. Gather reports

Concatenate the implementation agent's final-message text and the
verification agent's final-message text into a single parse input.
Both agents' outputs are available from Phase 2 and Phase 3 agent
dispatches.

### 2. Parse tokens

```bash
bash "$ZSKILLS_SKILLS_ROOT/run-plan/scripts/plan-drift-correct.sh" --parse <combined-reports>
```
Produces one `<phase>|<bullet>|<field>|<stated>|<actual>` line per
drift. Zero lines = no drifts → skip to step 6.

### 3. Per-drift decision

For each record, compute drift via:
```bash
bash "$ZSKILLS_SKILLS_ROOT/run-plan/scripts/plan-drift-correct.sh" --drift "<stated>" "<actual>"
```
Decision table:

| Drift | Byte-preservation / test gate | Action |
|-------|-------------------------------|--------|
| ≤10%  | held                          | auto-correct + count |
| 10-20% | held                         | auto-correct + count + note in phase report |
| >20%  | held                          | ABORT: do NOT correct, report to user, escalate to Failure Protocol (plan intent likely wrong, not just arithmetic) |
| any   | failed                        | Failure Protocol (byte-preservation failure always escalates) |
| unsupported `<stated>` form (exit 2) | — | skip, log as "non-derivable" in phase report |

### 4. Auto-correct

For each "auto-correct" record:
```bash
NEW_BAND="$(bash "$ZSKILLS_SKILLS_ROOT/run-plan/scripts/plan-drift-correct.sh" --drift-band <actual> 5)"  # ±5% of actual
bash "$ZSKILLS_SKILLS_ROOT/run-plan/scripts/plan-drift-correct.sh" --correct <plan-file> <phase> <bullet> "$NEW_BAND" --audit "was <stated>"
```
`--audit` appends `<!-- Auto-corrected YYYY-MM-DD: was <stated>, arithmetic says <actual> -->` inline on the bullet.

### 5. Marker ordering and failure handling

`.verify` is ALREADY written by Phase 3. That satisfies the hook's
landing gate (`hooks/block-unsafe-project.sh.template:341 etc.`
globs `step.*.verify`). If Phase 3.5 proceeds cleanly, write an
informational marker:

```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
BOOKKEEPING_ROOT="$CLAUDE_PROJECT_DIR"
[ "$LANDING_MODE" = "pr" ] && [ -n "$WORKTREE_PATH" ] && BOOKKEEPING_ROOT="$WORKTREE_PATH"
ZSKILLS_PATHS_ROOT="$BOOKKEEPING_ROOT" \
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh" ]; then
    . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh"
  else
    source "$BOOKKEEPING_ROOT/.claude/skills/update-zskills/scripts/zskills-paths.sh"
  fi
PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
PIPELINE_ID=$(bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/sanitize-pipeline-id.sh" "$PIPELINE_ID")
printf 'phase: %s\ndrifts_found: %s\ndrifts_corrected: %s\ndrifts_escalated: %s\ncompleted: %s\n' \
  "$PHASE" "$FOUND" "$CORRECTED" "$ESCALATED" "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
  > "$BOOKKEEPING_ROOT/.zskills/tracking/$PIPELINE_ID/phasestep.run-plan.$TRACKING_ID.$PHASE.drift-detect"
```

Uses the `phasestep.*` prefix (informational; hook ignores). The
`step.*.verify` marker stays as-is.

If Phase 3.5 fails (e.g., `.claude/skills/run-plan/scripts/plan-drift-correct.sh` exits
non-zero mid-correction, or >20% drift case triggers), the
orchestrator MUST:
1. `git checkout -- <plan-file>` to revert any partial corrections.
2. DELETE `step.run-plan.$TRACKING_ID.verify` (so the landing gate
   re-blocks — the pipeline is no longer verified-and-clean, it's
   verified-but-drift-escalated).
3. Write `phasestep.run-plan.$TRACKING_ID.$PHASE.drift-fail` with
   the error detail.
4. Invoke Failure Protocol.

### 6. Commit-location rule

The auto-correction edits the plan file. Where does the edit commit?

**Cherry-pick / direct mode:** commit on main, bundled with Phase 4's
tracker commit. Combined message:
```
chore: mark phase <name> in progress (+ auto-corrected <N> stale acceptance bands)
```
If N == 0: default Phase 4 message.

**PR mode:** commit inside the worktree on the feature branch,
bundled with Phase 4's feature-branch tracker commit. Same combined
message. The next phase's Phase 1 parse reads the plan file from
the worktree (since `finish auto` PR-mode runs consecutive phases
in the SAME worktree), so the corrected band is visible to the next
phase's thrash-detection.

### 7. Thrash rule

If the SAME `<phase>+<bullet>` pair gets a `PLAN-TEXT-DRIFT:` token
on a subsequent Phase 3.5 invocation (across phases in the same
`/run-plan finish auto` execution), the first correction was
wrong. ABORT:
1. Write `phasestep.*.drift-fail` with "thrash detected: phase
   P bullet B re-flagged after correction."
2. Do NOT correct a second time.
3. Invoke Failure Protocol.

Thrash rule is scoped to the current `/run-plan` invocation's
history, NOT across sessions. State is tracked in-memory by the
orchestrator during `finish auto`; for cron-fired chunked runs,
the rule relies on re-reading the plan file from the correct
location (worktree for PR mode, main for cherry-pick / direct).

### 8. Interaction with /refine-plan

Phase 3.5 corrects small arithmetic drift only. If the scan finds
multiple fields with >10% drift OR the plan's own extraction rules
are arithmetically inconsistent (detected by the pre-dispatch gate
in Phase 1 step 6), append a recommendation to the phase report:
"Recommend running `/refine-plan <plan-file>$AUTO_ARG` after close-out; this
plan has structural drift beyond per-band correction scope."

Do NOT auto-dispatch `/refine-plan` mid-run — too expensive and
scope-overlapping.

## Phase 4 — Update Progress Tracking

After verification passes. The plan file tracks progress across phases — an
orchestrator concern, not an implementation artifact. Update it promptly so
the next cron invocation sees the correct phase status and advances
(preventing infinite loops).

> If Phase 3.5 auto-corrected any acceptance bands, those edits are
> staged alongside the tracker update here and land as a single
> commit.

**Commit location depends on `LANDING_MODE`** (see PR-mode bookkeeping rule):
cherry-pick/direct commits on main; PR mode `cd "$WORKTREE_PATH"` first and
commits on the feature branch.

1. **Update the plan file's progress tracker on main** — change the phase
   status to Done with the commit hash (from worktree branch or delegate's
   landed commits) and notes. Examples
   by format:
   - Table: `| **4b: Mechanical** | ✅ Done | \`abc1234\` | 7 components, 45 tests |`
   - Checklist: `- [x] Phase 4b — Mechanical Domain (abc1234, 7 components)`
   - Section: add `**Status:** ✅ Done (abc1234)` to the section header

2. **Update companion progress doc on main** if one exists — add
   implementation details, architecture notes, lessons learned

3. **If no tracker exists:**
   - Interactive mode: suggest adding one to the plan file, ask user
   - Auto mode: note in the report that no tracker was updated

4. **Mark the phase as 🟡 In Progress and commit** (mode-conditional location):
   ```bash
   # PR mode only: cd "$WORKTREE_PATH" first (cherry-pick/direct: stay on main)
   git add <plan-file> [companion-doc]
   git commit -m "chore: mark phase <name> in progress"
   ```
   Not ✅ Done yet — Phase 6 updates to Done after landing succeeds (in
   cherry-pick/direct via a main commit, in PR mode via a commit on the
   feature branch *before* push so it's captured in the squash). If
   landing fails in either mode, tracker correctly reads In Progress.

5. **(PR mode only) Sync the GitHub PR body's progress section.** The PR
   body was snapshotted at PR-open time in Phase 6 (Step 5, Create PR) and
   wrapped with HTML-comment markers (`<!-- run-plan:progress:start -->`
   and `<!-- run-plan:progress:end -->`). As subsequent phases land on the
   feature branch, the PR body must be updated so readers see current
   progress — not the stale Phase 1 snapshot.

   Skip this step entirely in cherry-pick / direct modes — there is no PR.
   The helper handles all in-PR-mode gating (missing PR, missing markers,
   gh failure) gracefully and never blocks Phase 4 since the worktree
   tracker commit is the source of truth and the PR body is a convenience
   surface.

   ```bash
   if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
     . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
   else
     . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
   fi
   # Resolve PR_NUMBER for this branch when not already set, then invoke
   # the splice helper. Trailing `|| true` ensures Phase 4 never fails on
   # a body-sync failure — the helper itself exits 0 for the documented
   # graceful failure modes (missing PR, missing markers, gh edit error).
   if [ "$LANDING_MODE" = "pr" ]; then
     PR_NUMBER="${PR_NUMBER:-$(gh pr list --head "$BRANCH_NAME" --json number --jq '.[0].number' 2>/dev/null)}"
     if [ -n "$PR_NUMBER" ]; then
       bash "$ZSKILLS_SKILLS_ROOT/run-plan/scripts/sync-pr-body-progress.sh" \
         --pr "$PR_NUMBER" \
         --plan-file "$PLAN_FILE" \
         --branch "$BRANCH_NAME" || true
     fi
   fi
   ```

   **Design properties:** idempotent (re-run with no tracker change leaves
   the body byte-identical); preserves user-authored prose outside the
   markers; pure bash (no jq, no python). See
   `skills/run-plan/scripts/sync-pr-body-progress.sh` for the
   implementation, marker sentinels, and graceful-failure discriminator
   lines (NOTICE / WARNING / ERROR).

## Phase 5 — Write Report

**PREPEND** new phase sections after the H1 in `$ZSKILLS_REPORTS_DIR/plan-{slug}.md`
(`{slug}` from plan filename, e.g., `FEATURE_PLAN.md` → `plan-physics module`).
Newest phase at the top — the reader's question is "what needs my
attention?" and that's always the newest phase.

Resolve `$ZSKILLS_AUDIT_DIR` via the path-config helper at the top of the
fence (PR mode anchors on `$WORKTREE_PATH`, otherwise `$CLAUDE_PROJECT_DIR`):
```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
BOOKKEEPING_ROOT="$CLAUDE_PROJECT_DIR"
[ "$LANDING_MODE" = "pr" ] && [ -n "$WORKTREE_PATH" ] && BOOKKEEPING_ROOT="$WORKTREE_PATH"
ZSKILLS_PATHS_ROOT="$BOOKKEEPING_ROOT" \
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh" ]; then
    . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh"
  else
    source "$BOOKKEEPING_ROOT/.claude/skills/update-zskills/scripts/zskills-paths.sh"
  fi
mkdir -p "$ZSKILLS_AUDIT_DIR"  # idempotent — always create before write
```

If the file doesn't exist, create it with a `# Plan Report — {plan name}`
heading. Never overwrite the file — each phase adds a section.

**File location and commit follow the PR-mode bookkeeping rule**: in PR
mode, the helper above resolves `$ZSKILLS_AUDIT_DIR` to a worktree-relative
path and the commit lands on the feature branch. Cherry-pick/direct:
write/regen/commit on main (unchanged).

After writing, regenerate `$ZSKILLS_AUDIT_DIR/PLAN_REPORT.md` as an **index**
of all plan reports:
1. Scan `$ZSKILLS_REPORTS_DIR/plan-*.md` files
2. For each: extract plan name, phase count, overall status, unchecked `[ ]`
3. Write index with Needs Sign-off section (linked items) + Plans table
4. Staleness rule: items >7 days flagged STALE

**Report format** — each phase gets one `## Phase` section:

```markdown
## Phase — 4b Translational Mechanical Domain [UNFINALIZED]

**Plan:** plans/FEATURE_PLAN.md
**Status:** Completed (verified)
**Worktree:** ../plan-physics module-4b
**Commits:** abc1234, def5678

### Work Items
| # | Item | Status | Commit |
|---|------|--------|--------|
| 1 | Mass component | Done | abc1234 |
| 2 | Spring component | Done | def5678 |

### Verification
- Test suite: PASSED (4342 tests)
- Acceptance criteria: all met

### User Sign-off
{Only if UI files changed. Omit entirely for non-UI phases.}

- [ ] **P4b-1** — Variable viewer panel
  1. Open the app, load a physics module model (e.g., voltage-divider example)
  2. Run the simulation
  3. Click the lightning icon in the toolstrip
  4. Verify the Physical Variables panel opens with columns for V, I, P
  5. Check that values update after simulation completes
  ![viewer panel](.playwright/output/phase4b-variable-viewer.png)

- [ ] **P4b-2** — Toolstrip button
  1. Verify the lightning icon appears in the toolstrip
  2. Click it — panel should toggle open/closed
```

**Report format rules:**
- **One checkbox per item.** Do NOT use a summary table with `[ ]` AND a
  detail section with `[ ]` — the viewer counts both as separate checkboxes.
  Use only the checklist format above.
- **Phase-prefixed IDs** — `P4b-1`, `P2-3`, not `#1`, `#2` (which reset
  per phase and collide).
- **Include verification instructions** under each checkbox — numbered
  steps, screenshots. The reviewer needs to know what to do, not just
  what to check off.
- **One item per verifiable thing** — "3 check blocks in Block Explorer"
  is wrong. Each block gets its own checkbox.
- **Avoid literal `[ ]` in description text** — the viewer renders it as
  a phantom checkbox. Describe instead: "bracket pair" or use backtick
  escaping.

### Post-report tracking

After writing the report and regenerating the index, create the report step marker:
```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
BOOKKEEPING_ROOT="$CLAUDE_PROJECT_DIR"
[ "$LANDING_MODE" = "pr" ] && [ -n "$WORKTREE_PATH" ] && BOOKKEEPING_ROOT="$WORKTREE_PATH"
ZSKILLS_PATHS_ROOT="$BOOKKEEPING_ROOT" \
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh" ]; then
    . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh"
  else
    source "$BOOKKEEPING_ROOT/.claude/skills/update-zskills/scripts/zskills-paths.sh"
  fi
PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
PIPELINE_ID=$(bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/sanitize-pipeline-id.sh" "$PIPELINE_ID")
PLAN_SLUG=$(basename "$PLAN_FILE" .md | tr '[:upper:]' '[:lower:]' | tr '_' '-')
printf 'phase: %s\ncompleted: %s\n' "$PHASE" "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
  > "$BOOKKEEPING_ROOT/.zskills/tracking/$PIPELINE_ID/step.run-plan.$TRACKING_ID.report"
bash "$ZSKILLS_SKILLS_ROOT/run-plan/scripts/claim-plan.sh" \
  set-phase "$PLAN_SLUG" --require-pipeline "$PIPELINE_ID" --current-phase "Phase $PHASE — reported" || true
```

## Phase 5b — Plan Completion

Triggers when ALL phases are done: either the last phase just finished
(single-phase run where it was the only remaining phase), or in `finish`
mode after all phases complete. Run this BEFORE Phase 6 (Land).

### 0a. Idempotent early-exit

If frontmatter is already `status: complete`: this is a no-op re-entry.
**Release the plan claim before the no-op exit (W2a.4 site 2)** —
Phase 1 acquired the claim for this pipeline; without an explicit
release here the claim leaks until /run-plan stop or an operator
manually runs `claim-plan.sh release <slug>`.
Exit 12 (pipeline mismatch) is tolerated — it means another pipeline
owns the claim and our session must not touch it.

```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
PIPELINE_ID=$(bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/sanitize-pipeline-id.sh" "$PIPELINE_ID")
bash "$ZSKILLS_SKILLS_ROOT/run-plan/scripts/claim-plan.sh" \
  release "$PLAN_SLUG" --require-pipeline "$PIPELINE_ID" 2>/dev/null || true
```

**Issue-claim release (W3.3 / W3.5 — already-complete no-op).** Release any
linked `issue-<N>` claim alongside the plan claim on this no-op exit path,
re-parsing the bare-integer issue number(s) from `$PLAN_FILE_FOR_READ`'s
frontmatter (same normalization as the acquire fence). Without this, the
issue claim leaks until `/run-plan stop` or a manual release.
```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
ISSUE_NUMS=()
while IFS= read -r raw; do
  n=$(printf '%s' "$raw" | tr -d '"'\''#[:space:]')
  case "$n" in ''|*[!0-9]*) continue ;; esac
  [ "$n" -gt 0 ] 2>/dev/null && ISSUE_NUMS+=("$n")
done < <(awk '
  NR==1 && $0 != "---" { exit }
  NR==1 { infm=1; next }
  infm && $0 == "---" { exit }
  infm && /^[[:space:]]*issue:[[:space:]]*/ { sub(/^[[:space:]]*issue:[[:space:]]*/, "", $0); print $0 }
' "$PLAN_FILE_FOR_READ" 2>/dev/null)
for N in "${ISSUE_NUMS[@]}"; do
  bash "$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/claim-issue.sh" \
    release "$N" --require-pipeline "$PIPELINE_ID" 2>/dev/null || true
done
```

Exit cleanly without re-committing. Output "Plan already complete (no-op)."

### 0b. Final-verify gate

**Only applies if a final-verify marker exists.** Check for the cross-branch
final-verify marker:

```bash
# The final-verify marker is written by /research-and-go into ITS pipeline
# subdir (research-and-go.$META_PLAN_SLUG/), not into this /run-plan's own
# subdir. /research-and-go runs in the main session, so the marker lives
# under $CLAUDE_PROJECT_DIR/.zskills/tracking — not the PR-mode worktree.
# Use glob-dual-lookup: prefer any research-and-go.*/ subdir whose marker
# basename matches this TRACKING_ID; fall back to the legacy flat path
# during the Phase 2-6 transitional window.
MAIN_ROOT="$CLAUDE_PROJECT_DIR"
MARKER=$(ls "$MAIN_ROOT/.zskills/tracking/"research-and-go.*/requires.verify-changes.final."$TRACKING_ID" 2>/dev/null | head -1)
[ -z "$MARKER" ] && MARKER="$MAIN_ROOT/.zskills/tracking/requires.verify-changes.final.$TRACKING_ID"
FULFILLED=$(ls "$MAIN_ROOT/.zskills/tracking/"research-and-go.*/fulfilled.verify-changes.final."$TRACKING_ID" 2>/dev/null | head -1)
[ -z "$FULFILLED" ] && FULFILLED="$MAIN_ROOT/.zskills/tracking/fulfilled.verify-changes.final.$TRACKING_ID"
```

Three branches:

1. **Marker exists AND fulfilled missing**: defer pipeline completion until
   `/verify-changes branch` runs at top level. Use self-rescheduling pattern
   with exponential backoff.

   Rationale: `/verify-changes branch` can take 5–60 min depending on
   cumulative diff size; a fixed-time second cron risks firing before
   fulfillment exists, causing visible "still pending" turns.

   Read attempt counter file:
   `$MAIN_ROOT/.zskills/tracking/verify-pending-attempts.$TRACKING_ID`
   (numeric content; absent = 0). On each invocation:

   - Increment attempt counter, write back to file.
   - Compute backoff: `attempt 1: 10min, 2: 20min, 3: 40min, 4+: 60min`
     (capped at 60min).
   - On attempt 1 only: schedule the verify cron itself —
     `Run /verify-changes branch tracking-id=$TRACKING_ID` one-shot,
     ~5 min from now.
   - On every attempt: schedule re-entry cron —
     `Run /run-plan <plan-file> finish auto` one-shot, `<backoff>` from now.
   - Exit with message:
     > Final cross-branch verify pending (attempt <N>). Re-entry scheduled
     > in <backoff>. Verify cron: <id-if-attempt-1>. Re-entry cron: <id>.

   Do NOT run Phase 5b sub-steps 1–4. Do NOT run Phase 5c. Do NOT run
   Phase 6.

   ```bash
   if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
     . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
   else
     . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
   fi
   # Self-rescheduling with exponential backoff
   PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
   PIPELINE_ID=$(bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/sanitize-pipeline-id.sh" "$PIPELINE_ID")
   ATTEMPTS_FILE="$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/verify-pending-attempts.$TRACKING_ID"
   if [ -f "$ATTEMPTS_FILE" ]; then
     ATTEMPT=$(( $(cat "$ATTEMPTS_FILE") + 1 ))
   else
     ATTEMPT=1
   fi
   echo "$ATTEMPT" > "$ATTEMPTS_FILE"

   # Compute backoff minutes: 10, 20, 40, 60 (capped)
   case "$ATTEMPT" in
     1) BACKOFF_MIN=10 ;;
     2) BACKOFF_MIN=20 ;;
     3) BACKOFF_MIN=40 ;;
     *) BACKOFF_MIN=60 ;;
   esac
   ```

   On attempt 1, schedule the verify cron (~5 min from now) via the
   `.claude/skills/run-plan/scripts/compute-cron-fire.sh` helper. The helper handles +5 default
   margin, :00/:30 avoidance, and all minute/hour/day/month/year
   rollovers correctly (inlined bash versions previously got day+month
   rollover wrong — at 23:58, the naive math pinned the cron to
   earlier-today, and it would fire ~365 days out).
   ```bash
   if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
     . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
   else
     . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
   fi
   VERIFY_CRON=$(bash "$ZSKILLS_SKILLS_ROOT/run-plan/scripts/compute-cron-fire.sh")
   ```
   Then call `CronCreate` with:
   - `cron`: `"$VERIFY_CRON"`
   - `recurring`: false
   - `prompt`: `"Run /verify-changes branch tracking-id=$TRACKING_ID"`

   On every attempt, schedule re-entry cron (`<backoff>` from now). Pass
   `--allow-marks` because the re-entry cadence is backoff-driven, not
   API-busy-avoidance-driven:
   ```bash
   if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
     . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
   else
     . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
   fi
   REENTRY_CRON=$(bash "$ZSKILLS_SKILLS_ROOT/run-plan/scripts/compute-cron-fire.sh" --offset "$BACKOFF_MIN" --allow-marks)
   ```
   Then call `CronCreate` with:
   - `cron`: `"$REENTRY_CRON"`
   - `recurring`: false
   - `prompt`: `"Run /run-plan <plan-file> finish auto"`

   Then exit this turn.

2. **Marker exists AND fulfilled exists**: verify completed. Delete the
   attempt counter file (cleanup):
   ```bash
   if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
     . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
   else
     . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
   fi
   PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
   PIPELINE_ID=$(bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/sanitize-pipeline-id.sh" "$PIPELINE_ID")
   rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/verify-pending-attempts.$TRACKING_ID"
   rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/in-progress-defers."*       # NEW (#110)
   rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/cron-recovery-needed."*    # NEW (#110)
   ```
   Proceed to sub-step 1.

3. **No marker** (standalone plan, not via /research-and-go): proceed to
   sub-step 1.

### 1. Audit phase compliance

Before declaring the plan complete, verify every phase has a clean status:

1. **Check completion indicators** — every phase must have one of: Done,
   a commit hash, ✅, `[x]`. If any phase lacks a completion indicator,
   WARN (do not hard-block):
   > Phase 3 has no completion indicator — review before closing.

2. **Scan for unresolved gaps** — check each phase's status line AND its
   corresponding section in `$ZSKILLS_REPORTS_DIR/plan-{slug}.md` for any of these
   phrases (case-insensitive): "noted as gap", "deferred", "skipped",
   "future work". If found, WARN (do not hard-block):
   > Phase 3 has unresolved gaps — review before closing.

   List all flagged phases together so the user can review in one pass.

3. If running with `auto` and warnings were emitted, log them in the
   report but continue — these are advisory, not blocking.

### 2. Close linked issue (if any)

If the plan file has YAML frontmatter with an `issue:` field (e.g.,
`issue: 42` or `issue: "#42"`):

1. **Check issue state:**
   ```bash
   gh issue view <N> --json state --jq '.state'
   ```

2. **If open:** close it with a summary comment listing key commits and
   what was accomplished:
   ```bash
   gh issue close <N> --comment "Resolved via plan execution.

   Plan: <plan-file>
   Key commits: <comma-separated list of commit hashes from all phases>
   Phases completed: <count>

   All phases passed verification. See $ZSKILLS_REPORTS_DIR/plan-{slug}.md for details."
   ```

3. **If already closed:** no action needed — log "Issue #N already closed."

4. **If no `issue:` field:** skip this step entirely.

### 3. Update plan frontmatter

Change `status: active` (or `status: in-progress`) to `status: complete`
in the plan file's YAML frontmatter. If the plan has no `status:` field,
add one: `status: complete`. **Also write a `completed:` ISO-8601 UTC
datetime field** so the dashboard's Completed-window inference and the
backfill-script idempotency guard both have a canonical source of truth
(D1 of the completed-backlog-sections plan). The path-config helper
resolves `$ZSKILLS_PLANS_DIR` — NEVER hardcode `plans/<slug>.md`:

```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
ZSKILLS_PATHS_ROOT="${WORKTREE_PATH:-$CLAUDE_PROJECT_DIR}" \
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh" ]; then
    . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh"
  else
    source "${WORKTREE_PATH:-$CLAUDE_PROJECT_DIR}/.claude/skills/update-zskills/scripts/zskills-paths.sh"
  fi
# PR mode only: cd "$WORKTREE_PATH" first (cherry-pick/direct: stay on main)
# Plan file path resolved via $ZSKILLS_PLANS_DIR — NEVER hardcoded plans/.
PLAN_FILE="$ZSKILLS_PLANS_DIR/<slug>.md"
bash scripts/frontmatter-set.sh "$PLAN_FILE" status complete
completed_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
bash scripts/frontmatter-set.sh "$PLAN_FILE" completed "$completed_ts"
git add "$PLAN_FILE"
git commit -m "chore: mark plan complete — <plan-name>"
```

The `completed:` field is **full ISO-8601 UTC datetime**
(`YYYY-MM-DDTHH:MM:SSZ`), NOT a date-only string — matches GH's
`closedAt` format so cross-source date comparison in the dashboard is
uniform. Do not use `date -I` or `cut -c1-10`; both produce date-only
strings that mix poorly with the full-datetime form the historical
backfill emits.

### 4. Update sprint report

Resolve `$ZSKILLS_AUDIT_DIR` via the path-config helper:
```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
ZSKILLS_PATHS_ROOT="$CLAUDE_PROJECT_DIR" \
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh" ]; then
    . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh"
  else
    source "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-paths.sh"
  fi
```

Check if `$ZSKILLS_REPORTS_DIR/SPRINT_REPORT.md` exists. If it does:

1. Search for the closed issue number (from step 2) or the plan filename
   in a "Skipped" section (look for headers or list items containing
   "Skipped", "Too Complex", "Deferred", or "Punted").

2. If found, append a note to that entry:
   > Resolved via /run-plan (plan: <plan-file>)

3. If the sprint report file does not exist, or the issue/plan is not
   mentioned in a skipped section, skip this step.

### 5. Remind about stale tracking markers

After plan completion, the `fulfilled.run-plan.<id>` marker stays on disk
as the canonical completion record, but the pipeline's `requires.*`,
`step.*`, `verify-pending-attempts.*`, and `fulfilled.verify-changes.*`
markers (which are bookkeeping, not history) persist in
`.zskills/tracking/` indefinitely. Over many plan runs these accumulate
and can cause subtle drift (e.g., a test that invokes the hook's push
path from a zskills-tracked worktree may trip tracking enforcement
against a leftover `requires.*` from a prior pipeline).

Count remaining non-completion markers across all pipelines and surface
a one-line reminder. Do NOT auto-clean — this skill's job is
to run plans, not manage long-term tracking state. The user runs
`bash .claude/skills/update-zskills/scripts/clear-tracking.sh` when they're ready.

```bash
# This count surfaces accumulated bookkeeping across ALL pipelines (not just
# this run's) — anchor on $CLAUDE_PROJECT_DIR so it always inspects main's
# tracking even when a PR-mode run is in progress.
MAIN_ROOT="$CLAUDE_PROJECT_DIR"
# Count markers from both layouts during the Phase 2-6 transitional window:
# (1) per-pipeline subdirs (.zskills/tracking/*/…) — Option B primary, and
# (2) legacy flat basenames directly under .zskills/tracking/ — flat fallback.
MARKER_COUNT=$(ls "$MAIN_ROOT/.zskills/tracking/"*/requires.* \
                    "$MAIN_ROOT/.zskills/tracking/"*/step.* \
                    "$MAIN_ROOT/.zskills/tracking/"*/verify-pending-attempts.* \
                    "$MAIN_ROOT/.zskills/tracking/"*/fulfilled.verify-changes.* \
                    "$MAIN_ROOT/.zskills/tracking/"requires.* \
                    "$MAIN_ROOT/.zskills/tracking/"step.* \
                    "$MAIN_ROOT/.zskills/tracking/"verify-pending-attempts.* \
                    "$MAIN_ROOT/.zskills/tracking/"fulfilled.verify-changes.* 2>/dev/null \
                | wc -l)
if [ "$MARKER_COUNT" -ge 10 ]; then
  echo "NOTE: $MARKER_COUNT bookkeeping tracking markers on disk across completed pipelines."
  echo "      Run: bash .claude/skills/update-zskills/scripts/clear-tracking.sh   (preserves fulfilled.run-plan.* completion records)"
fi
```

Threshold `10` is a judgment call — below that the accumulation is not
yet disruptive. Adjust if it proves noisy or too quiet in practice.

## Phase 5c — Chunked finish auto transition (CRITICAL for finish auto mode)

When `finish auto` is active and Phase 5b determined another phase
is queued, Phase 5c transitions execution to the next phase via a
one-shot cron.

**Read [references/finish-mode.md](references/finish-mode.md) in full
and follow its procedure.** It covers cron scheduling, timestamp/TZ
handling, and Phase 5b gating. Do not proceed past Phase 5b without
reading this file.

## Phase 6 — Land

### Final-phase gating in finish/finish-auto modes (Issue #191)

In `finish` and `finish-auto` modes, the cherry-pick worktree is
plan-scoped (one worktree shared across all phases — see Phase 2 worktree
creation). Commits accumulate across phases and landing happens ONCE
after the FINAL phase. Per-phase landing is NOT the chunked model.

Before dispatching to `modes/cherry-pick.md`, compute whether any
incomplete phases remain in the plan's Progress Tracker. Use
`$PLAN_FILE_FOR_READ` (the authoritative source resolved at the top of
Phase 1 — main's copy in cherry-pick/direct modes, the feature-branch
worktree's copy in PR mode).

```bash
# Count rows in the Progress Tracker whose Status column is ⬚ (not started).
# 🟡 (in progress) does NOT count as remaining — the current phase is
# itself 🟡 at the moment Phase 6 runs (it flips to ✅ after landing).
#
# Tracker-shape assumption (the regex's hidden contract):
#   - The Progress Tracker is a markdown pipe table whose first column is
#     Phase and second column is Status.
#   - The Status column is where ⬚ / 🟡 / ✅ markers live.
#   - Header / separator rows (`| Phase | Status | ... |` and
#     `|-------|--------|...|`) don't contain ⬚, so the regex's
#     `^\|[^|]*\|[[:space:]]*⬚[[:space:]]*\|` (literal `|`, any non-`|`,
#     literal `|`, optional whitespace, ⬚, optional whitespace, literal
#     `|`) matches phase rows only.
#   - Plans following the project convention always have Phase in column 1
#     and Status in column 2 (every plan in docs/plans/ as of #240 does).
#   - The regex requires the Status cell to contain ONLY the glyph (modulo
#     whitespace). Narrative prose elsewhere on the page mentioning `⬚`
#     (disposition tables, design notes, review-history rows that name the
#     glyph) does NOT match — the col-2 anchor + whitespace-only fence
#     makes false positives structurally impossible (#256).
#   - Dependency: Progress Tracker Status cells MUST contain just the glyph
#     (no trailing text like "⬚ (blocked)") for the regex to count them.
#     This convention is already in use across plans; the tight regex
#     makes it structurally required rather than aspirational.
REMAINING_PHASES=$(grep -cE '^\|[^|]*\|[[:space:]]*⬚[[:space:]]*\|' "$PLAN_FILE_FOR_READ" || true)
REMAINING_PHASES="${REMAINING_PHASES:-0}"
```

Gate the landing dispatch:

```bash
# Single-phase invocations land as today. Finish/finish-auto modes land
# only when no incomplete phases remain (i.e., the current phase is the
# final one).
if [ "$FINISH_MODE" != "finish" ] && [ "$FINISH_MODE" != "finish-auto" ] || [ "$REMAINING_PHASES" -eq 0 ]; then
  LAND_NOW=true
else
  LAND_NOW=false
fi
```

When `LAND_NOW=false`, skip the landing dispatch below and proceed to
Phase 5c (next-phase cron). Commits remain on the plan-scoped feature
branch; the worktree is preserved for the next phase. When `LAND_NOW=true`,
dispatch to the landing mode below as normal.

If individual non-final phases have User Verify items, accumulate them
across phases — surface in the per-phase completion message and re-surface
them all in the final phase's completion message. The final landing waits
on cumulative sign-off.

**If LANDING_MODE = direct**: Read [modes/direct.md](modes/direct.md) in full and follow it.

**If LANDING_MODE = delegate**: Read [modes/delegate.md](modes/delegate.md) in full and follow it.

**If LANDING_MODE = cherry-pick (default)**: Read [modes/cherry-pick.md](modes/cherry-pick.md) in full and follow it.

**If LANDING_MODE = pr**: Read [modes/pr.md](modes/pr.md) in full and follow it.

### Post-landing tracking

After successful landing (cherry-pick + tests pass), create the land step
marker and update the fulfillment file. Post-landing happens on `main`
regardless of `LANDING_MODE` (cherry-pick: after cherry-pick to main; PR:
after PR merge), so anchor on `$CLAUDE_PROJECT_DIR`:
```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
ZSKILLS_PATHS_ROOT="$CLAUDE_PROJECT_DIR" \
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh" ]; then
    . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh"
  else
    source "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-paths.sh"
  fi
MAIN_ROOT="$CLAUDE_PROJECT_DIR"
PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
PIPELINE_ID=$(bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/sanitize-pipeline-id.sh" "$PIPELINE_ID")
printf 'phase: %s\ncompleted: %s\n' "$PHASE" "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.run-plan.$TRACKING_ID.land"

printf 'skill: run-plan\nid: %s\nplan: %s\nphase: %s\nstatus: complete\ndate: %s\n' \
  "$TRACKING_ID" "$PLAN_FILE" "$PHASE" "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/fulfilled.run-plan.$TRACKING_ID"
```

**Plan-claim release (W2a.4 site 3 — terminal merge).** Anchor on
/run-plan's OWN `fulfilled.run-plan.$TRACKING_ID` marker write above
(the canonical run-plan-internal terminal-merge signal — /land-pr's
upstream `fulfilled.land-pr.<id>` is READ here, never written by
/run-plan). Releasing earlier (e.g., at Phase 5b §1-5) would leave the
plan unclaimed during /land-pr's CI-poll window, allowing a second
/work-on-plans dispatch to re-pick the plan and double-fire /land-pr.
Exit 12 here invokes Failure Protocol — a pipeline-mismatch at
terminal merge indicates a stomped claim.
```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
bash "$ZSKILLS_SKILLS_ROOT/run-plan/scripts/claim-plan.sh" \
  release "$PLAN_SLUG" --require-pipeline "$PIPELINE_ID"
rc=$?
if [ "$rc" -eq 12 ]; then
  echo "Pipeline mismatch at terminal merge — claim was stomped; invoking Failure Protocol." >&2
  exit 1
elif [ "$rc" -ne 0 ]; then
  echo "Release failed (rc=$rc)" >&2; exit 1
fi
```

**Issue-claim release (W3.3 / W3.5 — terminal merge).** Release every
linked `issue-<N>` claim run-plan held for this plan's lifetime, alongside
the plan claim above. Re-parse the bare-integer issue number(s) from
`$PLAN_FILE_FOR_READ`'s frontmatter (same normalization as the acquire fence
in SKILL.md). Exit 12 (pipeline mismatch) is tolerated per-issue — it means
another pipeline owns that issue claim (e.g., the WARN-and-PROCEED path
never won it) and we must not clobber it.
```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
ISSUE_NUMS=()
while IFS= read -r raw; do
  n=$(printf '%s' "$raw" | tr -d '"'\''#[:space:]')
  case "$n" in ''|*[!0-9]*) continue ;; esac
  [ "$n" -gt 0 ] 2>/dev/null && ISSUE_NUMS+=("$n")
done < <(awk '
  NR==1 && $0 != "---" { exit }
  NR==1 { infm=1; next }
  infm && $0 == "---" { exit }
  infm && /^[[:space:]]*issue:[[:space:]]*/ { sub(/^[[:space:]]*issue:[[:space:]]*/, "", $0); print $0 }
' "$PLAN_FILE_FOR_READ" 2>/dev/null)
for N in "${ISSUE_NUMS[@]}"; do
  bash "$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/claim-issue.sh" \
    release "$N" --require-pipeline "$PIPELINE_ID" 2>/dev/null || true
done
```

Remove the worktree's `.zskills-tracked` to avoid associating future agents with a dead pipeline:
```bash
rm -f "<worktree-path>/.zskills-tracked"
```

In `finish` mode, per-phase markers use the `phasestep` prefix (the hook
ignores these — they are informational only):
```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
BOOKKEEPING_ROOT="$CLAUDE_PROJECT_DIR"
[ "$LANDING_MODE" = "pr" ] && [ -n "$WORKTREE_PATH" ] && BOOKKEEPING_ROOT="$WORKTREE_PATH"
ZSKILLS_PATHS_ROOT="$BOOKKEEPING_ROOT" \
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh" ]; then
    . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh"
  else
    source "$BOOKKEEPING_ROOT/.claude/skills/update-zskills/scripts/zskills-paths.sh"
  fi
PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
PIPELINE_ID=$(bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/sanitize-pipeline-id.sh" "$PIPELINE_ID")
printf 'phase: %s\ncompleted: %s\n' "$PHASE" "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
  > "$BOOKKEEPING_ROOT/.zskills/tracking/$PIPELINE_ID/phasestep.run-plan.$TRACKING_ID.$PHASE.implement"
```
After the cross-phase verification in `finish` mode completes, aggregate
with `step.*` markers:
```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
BOOKKEEPING_ROOT="$CLAUDE_PROJECT_DIR"
[ "$LANDING_MODE" = "pr" ] && [ -n "$WORKTREE_PATH" ] && BOOKKEEPING_ROOT="$WORKTREE_PATH"
ZSKILLS_PATHS_ROOT="$BOOKKEEPING_ROOT" \
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh" ]; then
    . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh"
  else
    source "$BOOKKEEPING_ROOT/.claude/skills/update-zskills/scripts/zskills-paths.sh"
  fi
PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
PIPELINE_ID=$(bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/sanitize-pipeline-id.sh" "$PIPELINE_ID")
for stage in implement verify report land; do
  printf 'phases: all\ncompleted: %s\n' "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
    > "$BOOKKEEPING_ROOT/.zskills/tracking/$PIPELINE_ID/step.run-plan.$TRACKING_ID.$stage"
done
```

### Post-run invariants check (mandatory — mechanical gate)

Before declaring the run complete, the orchestrator MUST invoke
`.claude/skills/run-plan/scripts/post-run-invariants.sh` to assert end-state correctness. This
catches silent failures in `land-phase.sh` (e.g., a branch delete that
was accepted but didn't take effect) that would otherwise accumulate
zombies across runs. The script is an enforced gate — NOT prose the
orchestrator might "satisfy conceptually" and skip.

Invoke it with named args, unified across modes (cherry-pick and PR use
the same `FEATURE_BRANCH` variable; direct mode passes empty for both
worktree and branch):

```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
# FEATURE_BRANCH unified across modes — both cherry-pick and PR set this
# at worktree creation time (cherry-pick uses cp-${PLAN_SLUG}-${PHASE},
# PR uses ${BRANCH_PREFIX}${PLAN_SLUG}).
bash "$ZSKILLS_SKILLS_ROOT/run-plan/scripts/post-run-invariants.sh" \
  --worktree      "$WORKTREE_PATH" \
  --branch        "$FEATURE_BRANCH" \
  --landed-status "$LANDED_STATUS" \
  --plan-slug     "$PLAN_SLUG" \
  --plan-file     "$PLAN_FILE"
```

The script asserts 7 invariants:
1. Worktree directory gone from disk
2. Worktree removed from git's worktree registry
3. Local feature branch deleted (when `--landed-status landed`)
4. Remote feature branch deleted (when `--landed-status landed`)
5. Plan report exists at `$ZSKILLS_REPORTS_DIR/plan-<slug>.md`
6. No 🟡 In Progress rows linger in the tracker
7. Local main reconcilable with origin/main (WARN-level; user may have
   legitimate unpushed local commits)

Non-zero exit from the script means one or more invariants failed. When
that happens: STOP. Do not self-reschedule the cron. Do not advance to
the next phase. Report the specific failures to the user; they need to
investigate and fix before another run.

For direct mode (no worktree, no feature branch), pass empty strings
for `--worktree` and `--branch`; the script skips those checks.

**Unified FEATURE_BRANCH convention:** at worktree creation (Phase 2),
both cherry-pick and PR modes export a single `FEATURE_BRANCH` variable
that the invariants check reads. Cherry-pick sets it to the
auto-generated `cp-${PLAN_SLUG}-${PHASE}`; PR mode sets it to
`${BRANCH_PREFIX}${PLAN_SLUG}`. Do not use different variable names per
mode — that's how invariant #3 silently skips in cherry-pick mode.
