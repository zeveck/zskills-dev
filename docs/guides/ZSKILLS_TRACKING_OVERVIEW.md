# Z Skills Tracking System Overview

## Purpose

The tracking system exists because agents bypass verification when given the opportunity. The motivating failure case: during a `/research-and-go` pipeline, an agent abandoned `/run-plan` entirely and dispatched raw `Agent` tools instead of using the `Skill` tool. This skipped all verification -- no worktrees, no verification agents, no playwright testing, no reports. The code that landed was untested and broken.

Instructions alone cannot prevent this. An agent can ignore any rule written in a skill file because it can simply not invoke the skill. The tracking system solves this by separating the moment of opting into guardrails (early, when the agent is cooperative) from the moment of being enforced (later, at `git commit`/`cherry-pick`/`push`, when the agent is tempted to cut corners). Git hooks run on every commit regardless of what the agent did or did not invoke, so they are the one enforcement point that cannot be bypassed.

The system creates sentinel and requirement files early in the pipeline. These files activate strict hook enforcement that blocks commits unless verification has actually occurred. The result: an agent that skips verification cannot land code.

## Architecture

### Where markers live

All tracking markers live in `.zskills/tracking/` in the **main repository root** (not in worktrees). This directory is gitignored -- markers are ephemeral process state, not version-controlled content.

```
<project-root>/
  .zskills/
    tracking/
      pipeline.fix-issues.sprint          # sentinel/mutex
      requires.verify-changes.sprint      # delegation requirement
      fulfilled.verify-changes.sprint     # delegation fulfillment
      step.fix-issues.sprint.execute      # phase progress
      step.fix-issues.sprint.verify
      step.fix-issues.sprint.report
    config.json                           # user-managed config (reads allowed, writes blocked)
```

### How markers are found from worktrees

Agents run in git worktrees, which have separate working directories but share the same `.git` metadata. The hook resolves the main repo root using `git-common-dir`:

```bash
TRACKING_ROOT=$(cd "$(git rev-parse --git-common-dir 2>/dev/null || echo .git)/.." && pwd)
TRACKING_DIR="$TRACKING_ROOT/.zskills/tracking"
```

This means an agent in `/tmp/worktree-thermal-domain/` reads and writes markers in the main repo's `.zskills/tracking/`, not a local copy. All agents and the orchestrator see the same marker state.

### Pipeline association (two-tier)

The hook determines which pipeline the current session belongs to using a two-tier mechanism:

**Tier 1: `.zskills-tracked` in LOCAL repo root (worktree agents).**
The orchestrator writes a `.zskills-tracked` file in each worktree before dispatching agents. This file contains a single line: the pipeline ID. It associates the worktree agent with its pipeline.

Example content:
```
run-plan.thermal-domain
```

**Tier 2: `ZSKILLS_PIPELINE_ID=<id>` in transcript (orchestrators on main).**
Orchestrators on main do not have a `.zskills-tracked` file. Instead, they echo `ZSKILLS_PIPELINE_ID=<id>` early in execution. The hook greps the transcript for this pattern and extracts the value:

```bash
PIPELINE_ID=$(grep -o 'ZSKILLS_PIPELINE_ID=[^[:space:]"]*' "$TRANSCRIPT" 2>/dev/null | tail -1 | cut -d= -f2)
```

The transcript is a stable append-only JSONL file that survives context compaction. The hook uses `tail -1` (last match) so that sequential `/run-plan` invocations in the same session work correctly -- each new invocation echoes a new `ZSKILLS_PIPELINE_ID=` line, and the hook picks up the most recent one.

**Neither tier matches** -- the session is unrelated to any pipeline. Tracking enforcement is **skipped entirely**. This is critical: it means a developer or an unrelated agent can commit freely even while a pipeline is running.

### Pipeline scoping via suffix matching

Each marker name ends with a pipeline-scoped suffix. The hook uses **suffix matching** to determine whether a marker belongs to the current pipeline:

```
requires.verify-changes.run-plan.thermal-domain
                        ^^^^^^^^^^^^^^^^^^^^^^^^^
                        pipeline ID suffix
```

When `PIPELINE_ID` is set (from `.zskills-tracked` or transcript), the hook only checks markers whose basename ends with `.$PIPELINE_ID`. This means:

- Pipeline A's markers do not block Pipeline B.
- An agent scoped to `run-plan.pipeline-B` ignores `requires.verify-changes.run-plan.pipeline-A`.

Suffix matching also prevents false positives: a pipeline ID of `plan` does NOT match a marker ending in `.run-plan.thermal-domain`, because the check is `*.$PIPELINE_ID` (literal dot + full ID).

### Parent signaling

When `/research-and-go` dispatches `/research-and-plan`, it passes `parent=research-and-go` in the arguments:

```
/research-and-plan auto parent=research-and-go <description>
```

This tells `/research-and-plan` that it was dispatched by a parent pipeline rather than invoked standalone. When `/research-and-plan` sees `parent=research-and-go`, it skips creating requirement files (since the parent already created them). Without this flag, a standalone `/research-and-plan` invocation creates its own requirement files for each phase.

## Marker Types

| Marker Pattern | Purpose | Example | Created By |
|---|---|---|---|
| `pipeline.<skill>.<scope>` | Sentinel/mutex -- prevents duplicate pipelines | `pipeline.fix-issues.sprint` | Orchestrator on entry |
| `requires.<skill>.<pipeline-id>` | Declares that a skill must be invoked | `requires.verify-changes.run-plan.thermal-domain` | Orchestrator before dispatching verification |
| `fulfilled.<skill>.<pipeline-id>` | Records that a required skill was invoked | `fulfilled.verify-changes.run-plan.thermal-domain` | The invoked skill on entry |
| `step.<skill>.<pipeline-id>.<stage>` | Records phase progress through the pipeline | `step.run-plan.thermal-domain.implement` | Orchestrator after each phase completes |
| `phasestep.<skill>.<pipeline-id>.<phase>.<stage>` | Per-phase progress (NOT enforced by hook) | `phasestep.run-plan.thermal-domain.phase3.implement` | Orchestrator (informational only) |

### Marker contents

Markers are plain text files with key-value pairs. They are human-readable and carry metadata about who created them and when:

```
# pipeline sentinel
skill: fix-issues
mode: sprint
count: 3
focus: default
startedAt: 2026-04-10T14:30:00-04:00

# requires marker
skill: verify-changes
parent: run-plan
id: thermal-domain
date: 2026-04-10T15:00:00-04:00

# step marker
phase: Phase 2 — Implement thermal domain
completed: 2026-04-10T15:45:00-04:00

# fulfilled marker
skill: run-plan
id: thermal-domain
plan: plans/THERMAL_PLAN.md
phase: Phase 2
status: started
date: 2026-04-10T14:35:00-04:00
```

## Enforcement Model

The hook (`block-unsafe-project.sh`) checks tracking state on three git operations: `git commit`, `git cherry-pick`, and `git push`. The enforcement logic is identical for all three (with minor differences in how code files are detected).

### Pipeline association (who gets checked)

The hook determines whether to enforce tracking using the two-tier mechanism:

1. **`.zskills-tracked` in LOCAL repo root** (Tier 1) -- if present, read the pipeline ID from it. The session is associated with that specific pipeline.
2. **`ZSKILLS_PIPELINE_ID=<id>` in transcript** (Tier 2) -- if no `.zskills-tracked` exists, grep the transcript for the `ZSKILLS_PIPELINE_ID=` pattern and extract the value (last match). If found, the session is associated with that pipeline.
3. **None of the above** -- the session is unrelated to any pipeline. Tracking enforcement is **skipped entirely**. This is critical: it means a developer or an unrelated agent can commit freely even while a pipeline is running.

### What gets checked

For each associated session, the hook checks:

#### Code-files exemption

Before any tracking check, the hook inspects staged files (for commit) or diff files (for push). If only non-code files are staged (markdown, images, etc.), tracking enforcement is skipped. Code file extensions: `.js`, `.ts`, `.json`, `.css`, `.html`, `.rs`, `.py`, `.go`, `.rb` (commit/cherry-pick) plus `.jsx`, `.mjs`, `.cjs`, `.tsx`, `.scss`, `.vue`, `.svelte`, `.java`, `.kt`, `.swift`, `.c`, `.cc`, `.cpp`, `.h`, `.hpp`, `.sh`, `.php` (push).

#### Delegation check

For each `requires.*` marker matching the current pipeline, the hook checks for a corresponding `fulfilled.*` marker (same name with `requires.` replaced by `fulfilled.`). If any requirement is unfulfilled, the operation is **blocked**:

```
BLOCKED: Required skill invocation 'verify-changes.run-plan.thermal-domain'
not yet fulfilled. Invoke the required skill via the Skill tool.
To clear stale tracking: ! bash scripts/clear-tracking.sh
```

#### Step enforcement

For each `step.*.implement` marker matching the current pipeline, the hook checks for a corresponding `step.*.verify` marker. If implementation exists without verification, the operation is **blocked**:

```
BLOCKED: run-plan.thermal-domain has implementation but no verification.
Run verification before landing.
```

For each `step.*.verify` marker, the hook checks for a corresponding `step.*.report` marker. If verification exists without a report, the operation is **blocked**:

```
BLOCKED: run-plan.thermal-domain verified but no report written.
Write report before landing.
```

Note: `phasestep.*` markers are explicitly ignored by the hook -- they are informational only and do not trigger enforcement.

### Operations and their checks

| Operation | Tracking Checks | Code File Detection |
|---|---|---|
| `git commit` | Delegation + step enforcement | `git diff --cached --name-only` |
| `git cherry-pick` | Delegation + step enforcement | N/A (always checked) |
| `git push` | Delegation + step enforcement | `git diff --name-only @{u}..HEAD` |

## Commit Workflow

The verification-before-commit pattern is the core mechanism that prevents unverified code from landing.

### The pattern

1. **Orchestrator creates `requires.*` marker.** Before dispatching a verification agent, the orchestrator writes a delegation requirement (e.g., `requires.verify-changes.run-plan.thermal-domain`). From this point, any code commit in this pipeline is blocked until the requirement is fulfilled.

2. **Implementation agent writes code, runs tests, does NOT commit.** The implementation agent works in a worktree. It can run tests, iterate on fixes, but it never calls `git commit`. This is by design -- the committing agent must have the test command in its transcript for the hook's test gate to pass.

3. **Orchestrator dispatches verification agent to the same worktree.** A fresh agent with no memory of the implementation is dispatched. It receives a prompt including: the worktree path, the tracking ID, instructions to create the fulfillment marker, and the test recipe.

4. **Verification agent creates fulfillment marker on entry.** As its first action, the verification agent writes `fulfilled.verify-changes.run-plan.thermal-domain`. This satisfies the delegation check.

5. **Verification agent runs tests, manual testing, checks acceptance criteria.** The agent runs the full test suite, performs playwright-cli manual verification if UI files changed, reviews the diff against the plan, and checks for stubs, deferred work, and missing tests.

6. **Verification passes -- verification agent commits the code.** Because the verification agent's transcript contains the test command (`npm run test:all`), the hook's test gate passes. Because the fulfillment marker exists, the delegation check passes. The commit succeeds.

7. **Orchestrator writes `step.*` markers.** After the verification agent returns, the orchestrator creates `step.*.verify` and `step.*.report` markers as the pipeline progresses.

### Why the implementation agent cannot commit

If the implementation agent committed, two problems arise:

1. Its transcript might not contain the full test command (it may have run individual test files during development).
2. There would be no independent verification -- the same agent that wrote the code would be declaring it correct.

By separating implementation from committing, the system guarantees that every committed line of code was reviewed and tested by a fresh agent.

## Config Protection

`.claude/zskills-config.json` is a user-managed configuration file. No dedicated protection mechanism exists for it — depending on the user's permission mode, writes to `.claude/` may prompt or auto-accept, but there is no file-specific rule. Agents may write the config when that is the explicit job (e.g., `/update-zskills`). Outside of those flows, treat the config as user-managed: read freely, and only modify it when the current skill's contract says to.

## Cleanup

```bash
! bash scripts/clear-tracking.sh
```

This script is **user-only** -- the hook blocks agents from executing it. It:

1. Resolves the main repo root via `git-common-dir`.
2. Lists all tracking files with their contents.
3. Prompts for confirmation (`y/N`).
4. Removes all files in `.zskills/tracking/` on confirmation.

The `!` prefix is required in Claude Code to run the command as the user (bypassing hook checks).

## Five Complete Examples

### Example 1: /run-plan single phase (cherry-pick mode)

Scenario: The user runs `/run-plan plans/THERMAL_PLAN.md Phase2 auto`. The plan has a Phase 2 that implements the thermal domain.

**Step 1 -- Orchestrator declares pipeline ID and sets up tracking:**

The orchestrator echoes the pipeline ID early:
```bash
echo "ZSKILLS_PIPELINE_ID=run-plan.thermal-domain"
```

Then creates the fulfillment marker on entry:
```
.zskills/tracking/
  fulfilled.run-plan.thermal-domain     # created on skill entry
```

File content of `fulfilled.run-plan.thermal-domain`:
```
skill: run-plan
id: thermal-domain
plan: plans/THERMAL_PLAN.md
phase: Phase 2
status: started
date: 2026-04-10T14:30:00-04:00
```

**Step 2 -- Orchestrator writes `.zskills-tracked` in worktree and dispatches implementation agent:**

```
<worktree>/.zskills-tracked           -> "run-plan.thermal-domain"
```

The implementation agent works in the worktree, writes code, runs tests. It does NOT commit.

**Step 3 -- Orchestrator creates implementation step marker:**

```
.zskills/tracking/
  fulfilled.run-plan.thermal-domain
  step.run-plan.thermal-domain.implement    # NEW
```

**Step 4 -- Orchestrator creates verification requirement and dispatches verification agent:**

```
.zskills/tracking/
  fulfilled.run-plan.thermal-domain
  step.run-plan.thermal-domain.implement
  requires.verify-changes.run-plan.thermal-domain    # NEW
```

At this point, if anyone in pipeline `run-plan.thermal-domain` tries to commit code, the hook blocks:
```
BLOCKED: Required skill invocation 'verify-changes.run-plan.thermal-domain'
not yet fulfilled.
```

**Step 5 -- Verification agent enters, creates fulfillment marker:**

```
.zskills/tracking/
  fulfilled.run-plan.thermal-domain
  step.run-plan.thermal-domain.implement
  requires.verify-changes.run-plan.thermal-domain
  fulfilled.verify-changes.run-plan.thermal-domain    # NEW
```

Verification agent runs `npm run test:all`, reviews diff, runs playwright-cli. All pass. Agent commits in worktree. The hook checks:
- Delegation: `requires.verify-changes.run-plan.thermal-domain` has matching `fulfilled.*` -- PASS
- Steps: The step markers (`implement`/`verify`/`report`) gate the **cherry-pick to main**, not the worktree commit. The worktree commit is gated by the delegation check (`requires.*`/`fulfilled.*`) and the test transcript check.

**Step 6 -- Orchestrator writes verify and report step markers:**

```
.zskills/tracking/
  fulfilled.run-plan.thermal-domain
  step.run-plan.thermal-domain.implement
  step.run-plan.thermal-domain.verify       # NEW
  requires.verify-changes.run-plan.thermal-domain
  fulfilled.verify-changes.run-plan.thermal-domain
  step.run-plan.thermal-domain.report       # NEW
```

**Step 7 -- Orchestrator cherry-picks to main:**

The orchestrator runs `git cherry-pick <commit>` on main. The hook checks:
- Delegation: `requires.verify-changes.run-plan.thermal-domain` has matching `fulfilled.*` -- PASS
- Steps: `step.run-plan.thermal-domain.implement` has `.verify` -- PASS. `.verify` has `.report` -- PASS.
- Cherry-pick succeeds.

**Step 8 -- Post-landing cleanup:**

```
.zskills/tracking/
  fulfilled.run-plan.thermal-domain
  step.run-plan.thermal-domain.implement
  step.run-plan.thermal-domain.verify
  step.run-plan.thermal-domain.report
  step.run-plan.thermal-domain.land         # NEW
  requires.verify-changes.run-plan.thermal-domain
  fulfilled.verify-changes.run-plan.thermal-domain
```

Orchestrator removes `.zskills-tracked` from the worktree.

---

### Example 2: /fix-issues sprint with 3 issues (parallel agents)

Scenario: The user runs `/fix-issues 3`. The skill picks 3 issues from GitHub and dispatches parallel agents.

**Step 1 -- Sprint sentinel and pipeline ID declaration:**

The orchestrator echoes the pipeline ID:
```bash
echo "ZSKILLS_PIPELINE_ID=fix-issues.sprint"
```

```
.zskills/tracking/
  pipeline.fix-issues.sprint
```

Content:
```
skill: fix-issues
mode: sprint
count: 3
focus: default
startedAt: 2026-04-10T10:00:00-04:00
```

**Step 2 -- Preflight and prioritize steps:**

```
.zskills/tracking/
  pipeline.fix-issues.sprint
  step.fix-issues.sprint.preflight          # after preflight checks pass
  step.fix-issues.sprint.prioritize         # after issue selection
```

**Step 3 -- Orchestrator writes `.zskills-tracked` in worktrees and dispatches 3 parallel agents:**

Each worktree gets:
```
<worktree-issue-101>/.zskills-tracked    -> "fix-issues.sprint"
<worktree-issue-102>/.zskills-tracked    -> "fix-issues.sprint"
<worktree-issue-103>/.zskills-tracked    -> "fix-issues.sprint"
```

All three agents share the same pipeline ID (`fix-issues.sprint`), so they all see the same markers.

**Step 4 -- Execute step marker (after all agents return):**

```
.zskills/tracking/
  pipeline.fix-issues.sprint
  step.fix-issues.sprint.preflight
  step.fix-issues.sprint.prioritize
  step.fix-issues.sprint.execute            # NEW
```

**Step 5 -- Pre-verification requirement:**

```
.zskills/tracking/
  ...
  requires.verify-changes.sprint            # NEW
```

At this point, code commits in the `fix-issues.sprint` pipeline are blocked until verification is fulfilled.

**Step 6 -- Verification agents dispatched (one per worktree):**

Each verification agent creates the fulfillment marker on entry:
```
.zskills/tracking/
  ...
  fulfilled.verify-changes.sprint           # NEW (created by first verify agent)
```

Each verification agent runs tests and commits in its respective worktree. The delegation check passes because `fulfilled.verify-changes.sprint` exists.

**Step 7 -- Post-verify and report:**

```
.zskills/tracking/
  pipeline.fix-issues.sprint
  step.fix-issues.sprint.preflight
  step.fix-issues.sprint.prioritize
  step.fix-issues.sprint.execute
  step.fix-issues.sprint.verify             # NEW
  step.fix-issues.sprint.report             # NEW
  requires.verify-changes.sprint
  fulfilled.verify-changes.sprint
```

**Step 8 -- Cherry-pick landing:**

Orchestrator cherry-picks each worktree's commits to main. The hook checks all markers for the `fix-issues.sprint` pipeline -- delegation fulfilled, steps complete. Cherry-picks succeed.

**Step 9 -- Cleanup:**

```bash
rm -f "$MAIN_ROOT/.zskills/tracking/pipeline.fix-issues.sprint"
```

Also remove `.zskills-tracked` from each worktree.

**Pipeline scoping note:** If two separate `/fix-issues` sprints somehow ran in parallel (e.g., different focus areas), they would share the same pipeline ID `fix-issues.sprint` because the sentinel blocks concurrent sprints. The sentinel (`pipeline.fix-issues.sprint`) acts as a mutex -- a second sprint cannot start while the first is running.

---

### Example 3: /research-and-go full pipeline

Scenario: The user runs `/research-and-go "add thermal and mechanical simulation domains"`. The pipeline decomposes into 2 sub-plans.

**Step 0 -- Tracking setup and pipeline ID declaration:**

```bash
SCOPE="add-thermal-and-mechanical-simul"   # slugified, 30-char max
echo "ZSKILLS_PIPELINE_ID=research-and-go.$SCOPE"
```

```
.zskills/tracking/
  pipeline.research-and-go.add-thermal-and-mechanical-simul
```

Content:
```
skill=research-and-go
goal=add thermal and mechanical simulation domains
startedAt=2026-04-10T09:00:00-04:00
```

**Step 1 -- Decompose (`/research-and-plan` with parent signaling):**

The orchestrator dispatches `/research-and-plan` with the `parent=research-and-go` flag:

```
/research-and-plan auto parent=research-and-go add thermal and mechanical simulation domains
```

Because `parent=research-and-go` is present, `/research-and-plan` knows it was dispatched by a parent pipeline and skips creating its own requirement files (the parent already handles those).

Research agents survey the codebase. `/research-and-plan` produces:
- `plans/THERMAL_DOMAIN_PLAN.md` (sub-plan 1)
- `plans/MECHANICAL_DOMAIN_PLAN.md` (sub-plan 2)
- `plans/ADD_THERMAL_AND_MECHANICAL_META.md` (meta-plan)

**Step 1b -- Lock down requirements:**

```
.zskills/tracking/
  pipeline.research-and-go.add-thermal-and-mechanical-simul
  requires.draft-plan.1                     # sub-plan 1 drafting
  requires.draft-plan.2                     # sub-plan 2 drafting
  requires.run-plan.1                       # sub-plan 1 execution
  requires.run-plan.2                       # sub-plan 2 execution
  requires.run-plan.meta                    # meta-plan execution
```

Each `requires.*` file contains:
```
skill=run-plan
index=1
requiredBy=research-and-go
createdAt=2026-04-10T09:15:00-04:00
```

**Step 2 -- Execute sub-plans via `/run-plan`:**

`/run-plan` is dispatched for each sub-plan. Each invocation:
1. Creates `fulfilled.run-plan.1` (or `.2`, `.meta`) on entry.
2. Writes `.zskills-tracked` in its worktree with `run-plan.thermal-domain` (its own tracking ID).
3. Goes through the full implement -> verify -> commit -> cherry-pick cycle.
4. Creates its own `step.run-plan.<id>.implement`, `.verify`, `.report` markers.

As sub-plans complete:
```
.zskills/tracking/
  pipeline.research-and-go.add-thermal-and-mechanical-simul
  requires.draft-plan.1
  requires.draft-plan.2
  requires.run-plan.1
  requires.run-plan.2
  requires.run-plan.meta
  fulfilled.draft-plan.1                    # draft-plan created these
  fulfilled.draft-plan.2
  fulfilled.run-plan.1                      # run-plan sub-plan 1 done
  step.run-plan.thermal-domain.implement
  step.run-plan.thermal-domain.verify
  step.run-plan.thermal-domain.report
  step.run-plan.thermal-domain.land
  fulfilled.run-plan.2                      # run-plan sub-plan 2 done
  step.run-plan.mechanical-domain.implement
  step.run-plan.mechanical-domain.verify
  step.run-plan.mechanical-domain.report
  step.run-plan.mechanical-domain.land
  fulfilled.run-plan.meta                   # meta-plan execution done
```

**Step 3 -- Report and cleanup:**

On success (all phases passed), all tracking files are removed:
```bash
rm -f "$MAIN_ROOT/.zskills/tracking"/*
```

On failure, tracking files are preserved so a re-run can pick up where it left off.

---

### Example 4: Parallel pipelines (two /run-plan instances in worktrees)

Scenario: Two `/run-plan` instances run simultaneously -- Pipeline A for `thermal-domain` and Pipeline B for `mechanical`.

**Marker state:**

```
.zskills/tracking/
  # Pipeline A markers
  fulfilled.run-plan.thermal-domain
  step.run-plan.thermal-domain.implement
  requires.verify-changes.run-plan.thermal-domain

  # Pipeline B markers
  fulfilled.run-plan.mechanical
  step.run-plan.mechanical.implement
  requires.verify-changes.run-plan.mechanical
```

**Pipeline A's worktree:**
```
<worktree-thermal>/.zskills-tracked -> "run-plan.thermal-domain"
```

**Pipeline B's worktree:**
```
<worktree-mechanical>/.zskills-tracked -> "run-plan.mechanical"
```

**Hook behavior when Pipeline A's agent tries to commit:**

1. Hook reads `.zskills-tracked` -> `PIPELINE_ID = "run-plan.thermal-domain"`.
2. Scans `requires.*` markers. Finds:
   - `requires.verify-changes.run-plan.thermal-domain` -- ends with `.run-plan.thermal-domain` -- MATCH. Checks for `fulfilled.verify-changes.run-plan.thermal-domain` -- does NOT exist -- **BLOCKED**.
   - `requires.verify-changes.run-plan.mechanical` -- ends with `.run-plan.mechanical` -- does NOT end with `.run-plan.thermal-domain` -- SKIP.
3. Result: Pipeline A is blocked by its own unfulfilled requirement, but Pipeline B's unfulfilled requirement is invisible to it.

**Hook behavior when Pipeline B's agent tries to commit (after its verification runs):**

1. Hook reads `.zskills-tracked` -> `PIPELINE_ID = "run-plan.mechanical"`.
2. Finds `requires.verify-changes.run-plan.mechanical` -- MATCH. Checks for `fulfilled.verify-changes.run-plan.mechanical` -- exists -- PASS.
3. Finds `requires.verify-changes.run-plan.thermal-domain` -- does NOT match -- SKIP.
4. Result: Pipeline B commits successfully even though Pipeline A has unfulfilled requirements.

**Key insight:** Each pipeline operates independently. `.zskills-tracked` scopes enforcement so that only the markers belonging to the current pipeline are checked. Parallel work proceeds without interference.

---

### Example 5: Parallel orchestrators on main (transcript-scoped)

Scenario: Two orchestrator sessions run on main simultaneously. Session X runs `/run-plan plans/THERMAL_PLAN.md` and Session Y runs `/run-plan plans/MECHANICAL_PLAN.md`. Neither uses worktrees for the orchestrator itself -- both operate on main and use Tier 2 (transcript) for pipeline association.

**Session X's transcript contains:**
```
echo "ZSKILLS_PIPELINE_ID=run-plan.thermal-domain"
```

**Session Y's transcript contains:**
```
echo "ZSKILLS_PIPELINE_ID=run-plan.mechanical"
```

**Marker state:**

```
.zskills/tracking/
  # Pipeline X markers
  fulfilled.run-plan.thermal-domain
  step.run-plan.thermal-domain.implement
  requires.verify-changes.run-plan.thermal-domain

  # Pipeline Y markers
  fulfilled.run-plan.mechanical
  step.run-plan.mechanical.implement
  requires.verify-changes.run-plan.mechanical
  fulfilled.verify-changes.run-plan.mechanical
```

**Hook behavior when Session X (on main) tries to cherry-pick:**

1. No `.zskills-tracked` in LOCAL root (main has none) -- Tier 1 does not match.
2. Tier 2: grep transcript for `ZSKILLS_PIPELINE_ID=`, take last match -> `run-plan.thermal-domain`.
3. `PIPELINE_ID = "run-plan.thermal-domain"`.
4. Checks `requires.verify-changes.run-plan.thermal-domain` -- MATCH. No `fulfilled.*` -- **BLOCKED**.
5. `requires.verify-changes.run-plan.mechanical` -- does NOT match -- SKIP.

**Hook behavior when Session Y (on main) tries to cherry-pick:**

1. Tier 2: grep transcript -> `run-plan.mechanical`.
2. `PIPELINE_ID = "run-plan.mechanical"`.
3. Checks `requires.verify-changes.run-plan.mechanical` -- MATCH. `fulfilled.*` exists -- PASS.
4. Step markers: `.implement` has `.verify`? Not yet -- **BLOCKED** (or passes if orchestrator already wrote `.verify` and `.report`).

**Key insight:** Each orchestrator session has its own transcript, so `ZSKILLS_PIPELINE_ID` is session-scoped. Two orchestrators on main do not interfere with each other because each transcript contains only that session's pipeline ID. The hook greps each session's own transcript independently.

**Sequential invocations in the same session:** If a user runs `/run-plan thermal` then later `/run-plan mechanical` in the same REPL session, the transcript accumulates both `ZSKILLS_PIPELINE_ID=` lines. The hook uses `tail -1` to pick the **last** one, so the second invocation's pipeline ID takes effect. This is correct because the first pipeline has already completed by the time the second starts.

## Troubleshooting

### "BLOCKED: Required skill invocation '...' not yet fulfilled"

**What it means:** A `requires.*` marker exists without a matching `fulfilled.*` marker. The orchestrator declared that a skill (usually `/verify-changes`) must be invoked, but it has not been invoked yet.

**How to resolve:**
1. Check `.zskills/tracking/` for the specific `requires.*` file mentioned.
2. If the pipeline is actively running, wait for the verification agent to create the fulfillment marker.
3. If the pipeline crashed or the agent was interrupted, ask the user to either:
   - Re-dispatch the verification agent.
   - Run `! bash scripts/clear-tracking.sh` to clear stale state.

### Hook blocks everything (all commits fail)

**Check `.zskills-tracked`:** If this file exists in a worktree root, the hook associates the session with that pipeline and enforces tracking. If you are not part of that pipeline, remove the file (or ask the user to).

**Check marker state:** Run `ls -la .zskills/tracking/` to see all markers. Look for `requires.*` without matching `fulfilled.*`, or `step.*.implement` without `.verify`/`.report`.

**Check if tracking dir exists:** If `.zskills/tracking/` does not exist, tracking enforcement is completely disabled (backward compatible).

### Parallel work blocked

**Check which pipeline you are in:** Read `.zskills-tracked` in your worktree to see your pipeline ID. If you are scoped to the wrong pipeline, the hook is checking markers that do not belong to you.

**Pipeline scoping:** If the suffix in your `.zskills-tracked` does not match the markers that are blocking you, something wrote the wrong pipeline ID. The orchestrator is responsible for writing the correct ID before dispatching agents.

**Unrelated sessions:** If you are not part of any pipeline (no `.zskills-tracked` in your worktree, no `ZSKILLS_PIPELINE_ID` in transcript), the hook should skip enforcement entirely. If it is still blocking, check whether a stale `.zskills-tracked` file exists somewhere it should not.

### Stale markers from a crashed pipeline

**What happened:** A pipeline crashed or was interrupted, leaving `requires.*` markers without matching `fulfilled.*` markers. New sessions in the same pipeline scope are blocked.

**How to clear:**
```bash
! bash scripts/clear-tracking.sh
```

This lists all tracking files with their contents, prompts for confirmation, and removes them. Only the user can run this command -- the hook blocks agents from executing it.
