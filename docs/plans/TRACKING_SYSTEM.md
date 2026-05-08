---
title: Skill Tracking System — Mechanical Enforcement of Skill Invocations and Step Completion
created: 2026-04-05
status: complete
---

# Plan: Skill Tracking System — Mechanical Enforcement of Skill Invocations and Step Completion

## Overview

Agents bypass skill invocations and skip verification steps during autonomous pipeline execution. Instructions don't prevent this — the agent had explicit instructions and skipped them. Only git hooks survive because they run on every commit regardless.

This plan implements a tracking file system in `.claude/tracking/` where skills write marker files on entry, at step completion, and when delegating to other skills. Hooks check these files before allowing commits on main, blocking when required skills weren't invoked or required steps were skipped.

**Core insight:** Separate the moment of opting into guardrails (early, when the agent is cooperative) from the moment of being tempted to bypass them (later, during implementation). Skills create tracking files early. Hooks enforce them later. The agent cannot delete tracking files — only the user can.

**Scope:** Every skill that delegates to another skill or has multi-step processes with skippable steps. This includes: `/research-and-go`, `/research-and-plan`, `/run-plan`, `/draft-plan`, `/fix-issues`, `/add-block`, `/add-example`, and `/verify-changes`. (`/commit` is not directly tracked — the hook fires on the `git cherry-pick` and `git commit` commands that `/commit` issues, so enforcement is automatic.)

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Foundation & Hook Infrastructure | ✅ Done | `8057691`, `72338d5` | 61/61 tests pass, hook enforcement + cleanup script + tests |
| 2 — Pipeline Orchestration Skills | ✅ Done | `980957f` | research-and-go, research-and-plan delegation markers |
| 3 — Execution Skills | ✅ Done | `c65be09` | run-plan, draft-plan, verify-changes fulfillment + step markers |
| 4 — Dispatch Skills | ✅ Done | `2b76e5c` | fix-issues, add-block, add-example step markers |
| 5 — Tests & Integration | ✅ Done | `7e31b1e` | /update-zskills awareness, CLAUDE_TEMPLATE.md docs |

## Tracking System Design

### Directory

`.claude/tracking/` in the **main repo** — gitignored, not committed. All files are plain text with human-readable metadata. Hooks check **file existence only** — never parse content. This keeps hooks fast (well within 5-second timeout) and dependency-free (bash only).

**Skills and hooks use DIFFERENT path resolution** — this is the key to worktree exemption:

**Skills** write to the MAIN repo's tracking directory using `git-common-dir`:
```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
TRACKING_DIR="$MAIN_ROOT/.claude/tracking"
```
In the main repo, `git-common-dir` returns `.git`; in a linked worktree, it returns `<main-repo>/.git`. Either way, `$MAIN_ROOT` resolves to the main repo. This is the same pattern `/verify-changes` uses for writing reports to main from worktrees.

**Hooks** check the LOCAL repo's tracking directory using `show-toplevel`:
```bash
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
TRACKING_DIR="$REPO_ROOT/.claude/tracking"
```
In the main repo, this resolves to the main repo (where tracking files exist → enforcement active). In a worktree, this resolves to the worktree root (where `.claude/tracking/` doesn't exist because it's gitignored → enforcement skipped).

**Why the split:** All tracking state is centralized in the main repo (skills always write there). But enforcement only activates where the tracking directory physically exists — which is only the main repo, never worktrees. No explicit worktree detection needed.

### File Types and Naming Convention

**Pattern:** `{type}.{skill}.{id}[.{step}]`

| Type | Pattern | Created By | Purpose |
|------|---------|------------|---------|
| `pipeline` | `pipeline.active` | Top-level orchestrator (research-and-go, fix-issues) | Sentinel: a pipeline is active, hooks go strict |
| `requires` | `requires.{skill}.{id}` | Parent skill before delegating | Declares that a child skill must be invoked |
| `fulfilled` | `fulfilled.{skill}.{id}` | Child skill on entry | Proves the child skill was actually invoked |
| `step` | `step.{skill}.{id}.{step-name}` | Skill after completing each step | Proves a specific step was completed |

**Examples:**
```
.claude/tracking/
  pipeline.active                          # research-and-go is running
  requires.draft-plan.1                    # must invoke /draft-plan for sub-plan 1
  requires.draft-plan.2                    # must invoke /draft-plan for sub-plan 2
  requires.run-plan.meta                   # must invoke /run-plan for meta-plan
  requires.run-plan.1                      # must invoke /run-plan for sub-plan 1
  fulfilled.draft-plan.1                   # /draft-plan was invoked for sub-plan 1
  fulfilled.draft-plan.2                   # /draft-plan was invoked for sub-plan 2
  fulfilled.run-plan.meta                  # /run-plan was invoked for meta-plan
  step.run-plan.1.verify                   # run-plan sub-1 completed verification
  step.run-plan.1.report                   # run-plan sub-1 wrote report
  step.add-block.DiscreteFilter.tests      # add-block wrote unit tests
  step.add-block.DiscreteFilter.example    # add-block created example model
  step.add-block.DiscreteFilter.verify     # add-block ran verification agent
```

### File Content Format

Each tracking file contains human-readable metadata (one key=value per line). Hooks never read this — it exists for debugging and cleanup display.

```
skill=run-plan
id=1
plan=plans/barbarain_2_engine.md
description=Engine & State Machine
requiredBy=research-and-go
createdAt=2026-04-05T15:00:00-04:00
```

### Hook Enforcement Rules

The hook fires on every `git commit` and `git cherry-pick` command. Tracking enforcement activates only when `.claude/tracking/` exists.

**Worktree handling (key design):** Skills write tracking files to the MAIN repo (via `git-common-dir`), centralizing all state. Hooks check the LOCAL repo (via `show-toplevel`). Since `.claude/tracking/` is gitignored, worktrees never have it locally — so enforcement naturally skips in worktrees. No `.worktreepurpose` checks or explicit worktree detection needed.

**On main (`.claude/tracking/` exists):**
1. **Delegation check:** For every `requires.*` file, check that a matching `fulfilled.*` file exists. Block if any requirement is unfulfilled.
2. **Verify-before-land check:** For every `step.{skill}.{id}.implement` marker, check that `step.{skill}.{id}.verify` exists. Block if trying to land unverified work. Note: only `step.*` prefixed markers are checked — `phasestep.*` markers (per-phase progress in finish mode) are NOT checked by the hook.
3. **Report-before-land check:** For every `step.{skill}.{id}.verify` marker, check that `step.{skill}.{id}.report` exists. Block if trying to land without a report.

**Staleness protection:** If `pipeline.active` exists and is older than 8 hours (check file modification time with `find`), the hook logs a WARNING to stderr but does NOT block. This prevents crashed/timed-out pipelines from poisoning the commit hook indefinitely. The error message includes: "Stale pipeline detected (>8h old). To clear: `! bash scripts/clear-tracking.sh`"

**Graceful degradation:**
- If `.claude/tracking/` doesn't exist, skip all tracking checks (backward compatible — also the mechanism for worktree exemption).
- If no `pipeline.active` sentinel exists but individual step markers exist, still enforce step checks (standalone skill mode).
- Content-only commits (only `.md`, `.txt`, `.yml`, `.png`, `.jpg` files staged) are exempt from all tracking checks. Note: `.json` files ARE treated as code for this check (they can contain meaningful configuration like `package.json` scripts).

**Concurrency:** Only one pipeline can be active at a time. If `pipeline.active` exists when a new pipeline starts, the new pipeline refuses with a clear message. This prevents concurrent pipelines from corrupting tracking state.

### Cleanup

`scripts/clear-tracking.sh` — removes all files in `.claude/tracking/`. Hook blocks agents from running it. User runs via `! bash scripts/clear-tracking.sh`.

The script lists what it's clearing before removing, so the user can see the tracking state.

---

## Phase 1 — Foundation & Hook Infrastructure

### Goal
Create the tracking directory infrastructure, cleanup script, and all hook enforcement logic.

### Work Items

- [ ] Add `.claude/tracking/` to `.gitignore`
- [ ] Create `scripts/clear-tracking.sh` — lists tracking files with content, then removes them. Confirms before deleting.
- [ ] Add tracking file protection to `hooks/block-unsafe-project.sh.template`:
  - Block recursive deletion targeting `.claude/tracking` directory (regex: `rm[[:space:]].*-[a-zA-Z]*r[a-zA-Z]*.*\.claude/tracking`). Individual file deletion within the directory is ALLOWED (skills need to update their own tracking files).
  - Block agent execution of clear-tracking script (regex: `(bash|sh|\.\/).*clear-tracking`). Reading the script (`cat`, `grep`, `ls`) is allowed — only execution is blocked.
- [ ] Add delegation enforcement to `hooks/block-unsafe-project.sh.template`:
  - On `git commit` and `git cherry-pick`, if `.claude/tracking/` exists AND any `requires.*` files exist, check each has a matching `fulfilled.*` file. Block with specific message naming the unfulfilled requirement AND including cleanup instructions: "To clear stale tracking: `! bash scripts/clear-tracking.sh`"
  - Staleness check: if `pipeline.active` exists and is older than 8 hours, log warning to stderr but allow the commit (prevents crashed pipelines from permanently blocking).
  - Skip check if only content files staged (reuse existing CODE_FILES detection logic — the check is already inside the `git commit` block). Treat `.json` as code (not content-only).
  - No worktree detection needed: `.claude/tracking/` is gitignored so it doesn't exist in worktrees. The `[ -d "$TRACKING_DIR" ]` check naturally skips enforcement in worktrees.
- [ ] Add step enforcement to `hooks/block-unsafe-project.sh.template`:
  - On `git commit` and `git cherry-pick`: if any `step.*.implement` marker exists without a matching `step.*.verify` marker, block with descriptive message. Only check `step.*` prefix — ignore `phasestep.*` prefix (per-phase progress markers).
  - Same content-only exemption.
- [ ] Upgrade placeholder-to-block behavior:
  - In the existing test verification section (find the `if $HAS_TESTS; then` block after the `FULL_TEST_CHECK` placeholder check), change from `echo "WARNING..."` to `block_with_reason "BLOCKED: Test infrastructure detected but FULL_TEST_CMD not configured in block-unsafe-project.sh. Configure it so the pre-commit test check works."` Apply same change to the equivalent cherry-pick section.
  - Also add `vitest.config.*` to the `HAS_TESTS` file detection list alongside `jest.config.*`, `.mocharc.*`, etc.
- [ ] Add `.json` to the CODE_FILES extension regex — find the existing `\.(js|ts|css|html|rs|py|go|rb)$` pattern in the hook template and add `json` to the alternation: `\.(js|ts|json|css|html|rs|py|go|rb)$`. This ensures `.json` commits (e.g., `package.json` script changes) are not treated as content-only.
- [ ] Hook uses `REPO_ROOT` via `git rev-parse --show-toplevel` (LOCAL path) for the tracking directory check — NOT `git-common-dir`. This is deliberate: in worktrees, `show-toplevel` returns the worktree root where `.claude/tracking/` doesn't exist (gitignored), so enforcement naturally skips. In the main repo, it returns the main repo where tracking files do exist.
- [ ] Update the installed copy at `.claude/hooks/block-unsafe-project.sh` to match the template changes.

### Design & Constraints

**Hook timeout:** All checks must complete within 5 seconds. File existence checks (`[ -f ... ]`) are O(1). Globbing `requires.*` files is O(n) where n is number of tracking files — even 100 files is <1ms. No JSON parsing, no external tools.

**Tracking file protection regex patterns:**
```bash
# Block recursive deletion of tracking directory
if [[ "$INPUT" =~ rm[[:space:]].*-[a-zA-Z]*r[a-zA-Z]*.*\.claude/tracking ]]; then
  block_with_reason "BLOCKED: Cannot recursively delete tracking directory. To clear tracking state: ! bash scripts/clear-tracking.sh"
fi

# Block agent execution of clear-tracking script (reading is OK)
if [[ "$INPUT" =~ (bash|sh|\.\/).*clear-tracking ]]; then
  block_with_reason "BLOCKED: Only the user can run the clear-tracking script. Run: ! bash scripts/clear-tracking.sh"
fi
```

**Delegation and step enforcement pseudocode:**
```bash
# Hook uses LOCAL repo root (show-toplevel), NOT git-common-dir.
# In main repo: resolves to main repo (tracking dir exists → enforce).
# In worktree: resolves to worktree root (tracking dir absent → skip).
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
TRACKING_DIR="$REPO_ROOT/.claude/tracking"

# Skip if tracking dir doesn't exist (backward compatible)
if [ -d "$TRACKING_DIR" ]; then

  # Skip if only content files staged
  # CODE_FILES includes .json (must be added to the existing regex)
  if [ -n "$CODE_FILES" ]; then

    # Staleness check: if pipeline.active is >8h old, warn but don't block
    PIPELINE_STALE=false
    if [ -f "$TRACKING_DIR/pipeline.active" ]; then
      STALE=$(find "$TRACKING_DIR/pipeline.active" -mmin +480 2>/dev/null)
      if [ -n "$STALE" ]; then
        echo "WARNING: Stale pipeline detected (>8h old). To clear: ! bash scripts/clear-tracking.sh" >&2
        PIPELINE_STALE=true
      fi
    fi

    # Delegation check (always, regardless of pipeline.active sentinel)
    # Only skip if pipeline is stale (>8h)
    if ! $PIPELINE_STALE; then
      for req in "$TRACKING_DIR"/requires.*; do
        [ -f "$req" ] || continue
        base=$(basename "$req")
        fulfilled="${TRACKING_DIR}/${base/requires./fulfilled.}"
        if [ ! -f "$fulfilled" ]; then
          block_with_reason "BLOCKED: Required skill invocation '${base#requires.}' not yet fulfilled. Invoke the required skill via the Skill tool. To clear stale tracking: ! bash scripts/clear-tracking.sh"
        fi
      done
    fi

    # Step enforcement (always, even without pipeline.active sentinel)
    # Only check step.* prefix, NOT phasestep.* (per-phase progress)
    if ! $PIPELINE_STALE; then
      for impl in "$TRACKING_DIR"/step.*.implement; do
        [ -f "$impl" ] || continue
        verify="${impl/\.implement/.verify}"
        if [ ! -f "$verify" ]; then
          session=$(basename "$impl" .implement)
          block_with_reason "BLOCKED: ${session#step.} has implementation but no verification. Run verification before landing. To clear: ! bash scripts/clear-tracking.sh"
        fi
      done

      for verif in "$TRACKING_DIR"/step.*.verify; do
        [ -f "$verif" ] || continue
        report="${verif/\.verify/.report}"
        if [ ! -f "$report" ]; then
          session=$(basename "$verif" .verify)
          block_with_reason "BLOCKED: ${session#step.} verified but no report written. Write report before landing. To clear: ! bash scripts/clear-tracking.sh"
        fi
      done
    fi
  fi
fi
```

**Path resolution split (critical for worktree exemption):**
- **Skills** use `git rev-parse --git-common-dir` → writes always go to the main repo's `.claude/tracking/`
- **Hooks** use `git rev-parse --show-toplevel` → checks the LOCAL directory, which in worktrees doesn't have `.claude/tracking/` (gitignored)
- This split ensures: all state is centralized (skills write to one place), but enforcement only fires on main (hooks check locally)

**clear-tracking.sh script:**
```bash
#!/bin/bash
# Clear all skill tracking files. Only the user should run this.
# Agents are blocked from invoking this script by the PreToolUse hook.

MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir 2>/dev/null || echo .git)/.." && pwd)
TRACKING_DIR="$MAIN_ROOT/.claude/tracking"

if [ ! -d "$TRACKING_DIR" ]; then
  echo "No tracking directory found at $TRACKING_DIR"
  exit 0
fi

files=$(ls "$TRACKING_DIR" 2>/dev/null)
if [ -z "$files" ]; then
  echo "Tracking directory is empty."
  exit 0
fi

echo "Current tracking state:"
echo "========================"
for f in "$TRACKING_DIR"/*; do
  [ -f "$f" ] || continue
  echo ""
  echo "--- $(basename "$f") ---"
  cat "$f"
done
echo ""
echo "========================"
echo ""

read -p "Remove all tracking files? [y/N] " confirm
if [[ "$confirm" =~ ^[Yy] ]]; then
  rm -f "$TRACKING_DIR"/*
  echo "Tracking files cleared."
else
  echo "Cancelled."
fi
```

### Acceptance Criteria

- [ ] `.claude/tracking/` is in `.gitignore`
- [ ] `scripts/clear-tracking.sh` exists, is executable, shows tracking state before clearing, prompts for confirmation
- [ ] Hook blocks recursive `rm -r .claude/tracking` but allows individual file deletion within the directory
- [ ] Hook blocks execution of `clear-tracking` script (`bash scripts/clear-tracking.sh`) but allows reading it (`cat`, `grep`)
- [ ] Hook blocks `git commit` when `requires.X` exists without `fulfilled.X` (delegation enforcement)
- [ ] Hook blocks `git commit` when `step.X.implement` exists without `step.X.verify` (step enforcement)
- [ ] Hook blocks `git cherry-pick` with same delegation and step checks
- [ ] Hook ignores `phasestep.*` markers (only checks `step.*` prefix)
- [ ] Hook warns but allows when `pipeline.active` is older than 8 hours (staleness protection)
- [ ] Hook allows commits in worktrees (`.claude/tracking/` doesn't exist there — gitignored)
- [ ] Hook allows content-only commits regardless of tracking state (`.json` treated as code)
- [ ] Hook silently passes when `.claude/tracking/` doesn't exist (backward compatible)
- [ ] All error messages include: "To clear: `! bash scripts/clear-tracking.sh`" (the `!` prefix runs the command in the user's shell, bypassing PreToolUse hooks)
- [ ] Placeholder warning upgraded to block when test infrastructure exists (both commit and cherry-pick sections, including vitest.config.* detection)
- [ ] `.json` added to CODE_FILES extension regex
- [ ] Hook uses `REPO_ROOT` via `git rev-parse --show-toplevel` (LOCAL path) for tracking dir check — NOT `git-common-dir` (worktree exemption depends on this)
- [ ] All enforcement completes within 5-second hook timeout
- [ ] **Phase 1 is self-testing:** Add hook enforcement tests to `tests/test-hooks.sh` as part of this phase (not deferred to Phase 5). Tests cover: tracking file protection, delegation enforcement, step enforcement, staleness, backward compatibility. Use the project hook test harness described in Phase 5's Design & Constraints section. This ensures the foundation is verified before any skill modifications build on it.

### Dependencies
None — this is the foundation phase.

---

## Phase 2 — Pipeline Orchestration Skills

### Goal
Add delegation requirement markers to skills that orchestrate other skills: `/research-and-go` and `/research-and-plan`.

### Work Items

- [ ] Modify `skills/research-and-go/SKILL.md` — add Step 0 (before current Step 1):
  - Check for existing `pipeline.active`: if it exists, STOP — another pipeline is in progress. Tell the user: "A pipeline is already active. Clear it with `! bash scripts/clear-tracking.sh` or wait for it to finish."
  - Create `.claude/tracking/pipeline.active` sentinel file with metadata:
    ```bash
    MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
    mkdir -p "$MAIN_ROOT/.claude/tracking"
    printf 'skill=research-and-go\ngoal=%s\nstartedAt=%s\n' "$DESCRIPTION" "$(date -Iseconds)" > "$MAIN_ROOT/.claude/tracking/pipeline.active"
    ```
- [ ] Modify `skills/research-and-go/SKILL.md` — add Step 1b (after decomposition, before execution):
  - After `/research-and-plan` returns with the meta-plan and sub-plan list, create requirement files for EVERY expected skill invocation:
    - `requires.draft-plan.{1..N}` — one per sub-plan that was drafted
    - `requires.run-plan.meta` — for the meta-plan execution
    - `requires.run-plan.{1..N}` — one per sub-plan execution
  - Instructions must be explicit: "For each of the N sub-plans identified, create a requirement file. For example, if /research-and-plan produced 5 sub-plans:"
    ```bash
    MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
    for i in 1 2 3 4 5; do
      printf 'skill=draft-plan\nindex=%d\nrequiredBy=research-and-go\ncreatedAt=%s\n' "$i" "$(date -Iseconds)" > "$MAIN_ROOT/.claude/tracking/requires.draft-plan.$i"
      printf 'skill=run-plan\nindex=%d\nrequiredBy=research-and-go\ncreatedAt=%s\n' "$i" "$(date -Iseconds)" > "$MAIN_ROOT/.claude/tracking/requires.run-plan.$i"
    done
    printf 'skill=run-plan\nid=meta\nrequiredBy=research-and-go\ncreatedAt=%s\n' "$(date -Iseconds)" > "$MAIN_ROOT/.claude/tracking/requires.run-plan.meta"
    ```
  - This is the "locking down the world" moment — after this, the hooks enforce that every required skill is actually invoked.
  - **Tracking ID passing:** When dispatching `/research-and-plan` and later `/run-plan`, include the tracking ID in the dispatch. For `/run-plan`, pass the meta-plan tracking context: "Your tracking ID is `meta`. The sub-plans have tracking IDs `1` through `N`. When you delegate sub-plan execution, pass the corresponding tracking ID to each sub-`/run-plan`."
- [ ] Modify `skills/research-and-plan/SKILL.md` — add tracking awareness to Step 4 (meta-plan writing):
  - After writing the meta-plan, if `.claude/tracking/pipeline.active` exists, create requirement files for each sub-plan's `/run-plan` delegation:
    - `requires.run-plan.{1..N}` for each phase in the meta-plan that delegates to `/run-plan`
  - This handles the case where `/research-and-plan` is invoked standalone (not via `/research-and-go`) — the delegation tracking still activates.
  - Note: `/research-and-plan` already has the 3-layer mechanical check for `/draft-plan` (Step 2b). The tracking system supplements this — it doesn't replace it. The grep check catches plans missing `## Plan Quality`; the tracking system catches skills never invoked at all.

### Design & Constraints

**Timing is critical.** Requirement files must be created:
- AFTER decomposition (so we know the sub-plan count)
- BEFORE any execution begins (so hooks are active for all implementation commits)

If `/research-and-go` creates requirements between Steps 1 and 2, and Step 2 immediately invokes `/run-plan <meta-plan> finish auto`, the hooks are active before any implementation agent commits.

**Pipeline completion cleanup:** After `/research-and-go` Step 3 (Report) completes successfully, add instruction to clear tracking files: `rm -f .claude/tracking/*`. This removes stale state so the next pipeline starts clean. Individual file deletion is allowed by the hook (only recursive directory deletion is blocked).

**Requirement file content (human-readable, not parsed by hooks):**
```
skill=draft-plan
index=1
plan=plans/barbarain_1_story.md
description=Story & World Data
requiredBy=research-and-go
createdAt=2026-04-05T15:00:00-04:00
```

**Fulfillment files are NOT created in this phase** — they're created by the child skills (Phase 3). This phase only declares requirements.

**Edge case: re-runs.** If `/research-and-go` is re-invoked after a partial failure, it should check for existing tracking files and either clear them (fresh start) or skip already-fulfilled requirements. The skill instructions should say: "If `.claude/tracking/pipeline.active` already exists, check if this is a re-run. If requirement files exist, verify which are already fulfilled and only create requirements for unfulfilled ones."

### Acceptance Criteria

- [ ] `/research-and-go` creates `pipeline.active` as its very first action
- [ ] `/research-and-go` creates all `requires.draft-plan.{1..N}` and `requires.run-plan.{1..N}` files after decomposition, before execution
- [ ] `/research-and-plan` creates `requires.run-plan.{1..N}` files after writing meta-plan (when pipeline.active exists)
- [ ] Requirement files contain human-readable metadata (skill, index, plan path, description, requiredBy, timestamp)
- [ ] Re-run handling: existing tracking state is detected and handled (not blindly overwritten)

### Dependencies
Phase 1 must be complete (tracking directory and hook enforcement must exist).

---

## Phase 3 — Execution Skills (Fulfillment & Step Markers)

### Goal
Add fulfillment file creation and step completion markers to skills that execute work: `/run-plan`, `/draft-plan`, and `/verify-changes`.

### Work Items

#### /run-plan (skills/run-plan/SKILL.md)

- [ ] Add preflight placeholder check — in Phase 1 preflight (find the "Preflight checks" section, before the existing git state checks):
  - Check: `grep -q '{{' .claude/hooks/block-unsafe-project.sh 2>/dev/null`
  - If placeholders found AND project has test infrastructure (package.json with "test", or vitest.config.*/jest.config.* exists), STOP with message: "block-unsafe-project.sh has unconfigured placeholders but project has test infrastructure. Configure UNIT_TEST_CMD, FULL_TEST_CMD, and UI_FILE_PATTERNS before running /run-plan."
- [ ] Add fulfillment file creation — on entry (Phase 1, after parsing the plan):
  - **Tracking ID:** Use the ID passed by the parent skill. If invoked standalone (no tracking ID passed), use the plan file slug (e.g., `plans/FEATURE_PLAN.md` → ID `FEATURE_PLAN`).
  - Create fulfillment file (always write to MAIN repo):
    ```bash
    MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
    mkdir -p "$MAIN_ROOT/.claude/tracking"
    printf 'skill=run-plan\nid=%s\nplan=%s\nstartedAt=%s\n' "$TRACKING_ID" "$PLAN_PATH" "$(date -Iseconds)" > "$MAIN_ROOT/.claude/tracking/fulfilled.run-plan.$TRACKING_ID"
    ```
- [ ] Add delegation requirement for verification — before Phase 3 (dispatching verification agent):
  - Create `requires.verify-changes.{id}` (e.g., `requires.verify-changes.FEATURE_PLAN`)
  - Pass tracking ID to the verification agent: "Your tracking ID is `{id}`. Create `fulfilled.verify-changes.{id}` as your first action."
- [ ] Add step markers at each key phase completion:
  - After Phase 2 (implement): `step.run-plan.{id}.implement`
  - After Phase 3 (verify): `step.run-plan.{id}.verify`
  - After Phase 5 (report): `step.run-plan.{id}.report`
  - After Phase 6 (land): `step.run-plan.{id}.land`
  - In `finish` mode, per-phase markers use `phasestep` prefix: `phasestep.run-plan.{id}.{phase-num}.implement`, `phasestep.run-plan.{id}.{phase-num}.verify`. Aggregate `step.*` markers are created after the cross-phase verification (the `finish` mode overall verification section).
- [ ] Update fulfillment file on completion — after Phase 6 landing succeeds, update `fulfilled.run-plan.{id}` with completedAt, phases completed, tests passed, playwright used, report path.

#### /draft-plan (skills/draft-plan/SKILL.md)

- [ ] Add fulfillment file creation — on entry (beginning of Phase 1 Research):
  - **Tracking ID:** Use the ID passed by the parent skill (e.g., `/research-and-plan` passes `1` for the first sub-plan). If invoked standalone, use the output file slug.
  - Create fulfillment file (always write to MAIN repo):
    ```bash
    MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
    mkdir -p "$MAIN_ROOT/.claude/tracking"
    printf 'skill=draft-plan\nid=%s\noutput=%s\nstartedAt=%s\n' "$TRACKING_ID" "$OUTPUT_PATH" "$(date -Iseconds)" > "$MAIN_ROOT/.claude/tracking/fulfilled.draft-plan.$TRACKING_ID"
    ```
- [ ] Add step markers:
  - After Phase 1 (research) completes: create `step.draft-plan.{id}.research`
  - After Phase 3 (adversarial review, first round): create `step.draft-plan.{id}.review`
  - After Phase 6 (finalize): create `step.draft-plan.{id}.finalize`
- [ ] Update fulfillment file on completion — after Phase 6, update with completedAt, rounds completed, convergence status.

#### /verify-changes (skills/verify-changes/SKILL.md)

- [ ] Add fulfillment file creation — on entry, create `fulfilled.verify-changes.{id}` where `{id}` is the tracking ID passed by the parent (or scope-slug if standalone). Always write to MAIN repo:
    ```bash
    MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
    mkdir -p "$MAIN_ROOT/.claude/tracking"
    printf 'skill=verify-changes\nid=%s\nscope=%s\nstartedAt=%s\n' "$TRACKING_ID" "$SCOPE" "$(date -Iseconds)" > "$MAIN_ROOT/.claude/tracking/fulfilled.verify-changes.$TRACKING_ID"
    ```
- [ ] Add step markers — `/verify-changes` is frequently the delegated verification skill. It should create markers so the parent knows verification actually ran:
  - After Phase 3 (run tests): create `step.verify-changes.{id}.tests-run`
  - After Phase 4 (manual verification): create `step.verify-changes.{id}.manual-verified` (only if UI changes were present)
  - After Phase 7 (report): create `step.verify-changes.{id}.complete`
- [ ] These markers supplement — not replace — the existing transcript-based playwright-cli check. The transcript check catches the case where `/verify-changes` is skipped entirely. The tracking system catches the case where it's invoked but steps are skipped within it.

### Design & Constraints

**Tracking ID passing (explicit, not auto-detected):** When a parent skill dispatches a child, it passes the tracking ID explicitly. The child uses this ID directly — no directory scanning needed.

**Convention for passing tracking IDs:** The parent includes a concrete bash command in the agent dispatch prompt with the tracking ID baked in:
```
Your tracking ID is 1. As your FIRST action, create the fulfillment file:

MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
mkdir -p "$MAIN_ROOT/.claude/tracking"
printf 'skill=draft-plan\nid=1\nstartedAt=%s\n' "$(date -Iseconds)" > "$MAIN_ROOT/.claude/tracking/fulfilled.draft-plan.1"
```

This is a concrete bash command, not a natural language instruction. The parent includes the full command with the ID baked in — the child copies and runs it.

- If the child is invoked standalone (user types `/run-plan plans/foo.md`), it uses the plan file slug as the ID (e.g., `FEATURE_PLAN`).
- This eliminates race conditions when multiple skills are dispatched in parallel (e.g., concurrent `/draft-plan` agents from `/research-and-plan`).

**Nested /run-plan (meta → sub):** When `/run-plan` executes a meta-plan in `finish` mode with `delegate /run-plan` phases:
- The outer `/run-plan` has tracking ID `meta` and creates `fulfilled.run-plan.meta`.
- Each inner `/run-plan` gets tracking ID `1`, `2`, etc. — passed by the outer via the delegate dispatch prompt.
- The outer creates its own step markers: `step.run-plan.meta.implement`, `step.run-plan.meta.verify`, `step.run-plan.meta.report`.
- The inner skills create their own fulfillment files and step markers independently.

**/run-plan must create `requires.verify-changes.{id}` before dispatching verification.** This is the most important delegation — the entire system was motivated by agents skipping verification. Before Phase 3 (dispatch verification agent), /run-plan creates `requires.verify-changes.{id}`. The verification skill creates `fulfilled.verify-changes.{id}` on entry.

**Finish mode step markers — two prefixes:** Per-phase progress uses `phasestep.*` prefix; aggregate status uses `step.*` prefix. The hook only checks `step.*`:
- Per-phase: `phasestep.run-plan.{id}.{phase-num}.implement`, `phasestep.run-plan.{id}.{phase-num}.verify`
- Aggregate (after cross-phase verification): `step.run-plan.{id}.implement`, `step.run-plan.{id}.verify`, `step.run-plan.{id}.report`

**Skills always write to MAIN repo:** Every tracking file creation must resolve to the main repo's tracking directory via `git-common-dir`, even when running in a worktree:
```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
mkdir -p "$MAIN_ROOT/.claude/tracking"
printf '...' > "$MAIN_ROOT/.claude/tracking/fulfilled.run-plan.$TRACKING_ID"
```
Skill instructions MUST include the `MAIN_ROOT` derivation in each tracking file creation command. Do NOT use bare `mkdir -p .claude/tracking` — in a worktree, that creates the directory locally and breaks the worktree exemption (the hook would then see tracking files in the worktree and enforce there).

**Decision rule for `step` vs `phasestep` prefix:** Use `step.*` for markers the hook checks (implement/verify/report gates that must be satisfied before landing). Use `phasestep.*` for per-phase progress that is informational only (the hook ignores these).

### Acceptance Criteria

- [ ] `/run-plan` creates `fulfilled.run-plan.{id}` on entry using the tracking ID passed by the parent (or plan slug if standalone)
- [ ] `/run-plan` creates `requires.verify-changes.{id}` before dispatching verification agent
- [ ] `/run-plan` creates step markers after implement, verify, report, and land (`step.*` prefix)
- [ ] `/run-plan` uses `phasestep.*` prefix for per-phase markers in finish mode
- [ ] `/run-plan` preflight checks for `{{` placeholders and blocks if test infrastructure exists
- [ ] `/draft-plan` creates `fulfilled.draft-plan.{id}` on entry using the tracking ID passed by the parent (or output slug if standalone)
- [ ] `/draft-plan` creates step markers after research, review, and finalize
- [ ] `/verify-changes` creates `fulfilled.verify-changes.{id}` on entry using tracking ID from parent
- [ ] `/verify-changes` creates step markers through completion
- [ ] All tracking IDs are passed explicitly from parent to child — no auto-detection
- [ ] Every tracking file creation uses `MAIN_ROOT` via `git-common-dir` (never bare `.claude/tracking`)
- [ ] Fulfillment files are updated with completion metadata on skill exit

### Dependencies
Phase 1 must be complete (hook enforcement active). Phase 2 should be complete (requirement files exist to match against), but Phase 3 skills work in standalone mode too.

---

## Phase 4 — Dispatch Skills (Requirements & Step Markers)

### Goal
Add delegation requirement markers and step completion tracking to skills that dispatch implementation agents: `/fix-issues`, `/add-block`, and `/add-example`.

### Work Items

#### /fix-issues (skills/fix-issues/SKILL.md)

- [ ] Add sentinel on sprint entry — at the beginning of Phase 1 (Preflight), if the mode is a sprint (N provided):
  - Create `pipeline.active` if it doesn't already exist (fix-issues can be the top-level orchestrator, similar to research-and-go)
  - Metadata: skill=fix-issues, mode=sprint, count=N, timestamp
- [ ] Add step markers for sprint lifecycle:
  - After Phase 1 (preflight + sync): create `step.fix-issues.sprint.preflight`
  - After Phase 2 (prioritize): create `step.fix-issues.sprint.prioritize`
  - After Phase 3 (execute — all agents return): create `step.fix-issues.sprint.execute`
  - After Phase 4 (verification agents return): create `step.fix-issues.sprint.verify`
  - After Phase 5 (report written): create `step.fix-issues.sprint.report`
  - After Phase 6 (land): create `step.fix-issues.sprint.land`
- [ ] Add delegation requirements for Phase 4 verification:
  - Before dispatching verification agents in Phase 4, create `requires.verify-changes.sprint` so the hook can verify that `/verify-changes` was actually invoked for the sprint results.
  - `/verify-changes` creates `fulfilled.verify-changes.sprint` on entry (via Phase 3 changes).
- [ ] Add delegation requirements for plan mode:
  - In `plan` mode (line 239), when dispatching `/draft-plan` for skipped issues, create `requires.draft-plan.{issue-number}` for each plan being drafted.

#### /add-block (block-diagram/add-block/SKILL.md)

- [ ] Add step markers for the 13-step lifecycle. The most critical steps (those historically skipped) get markers:
  - After Step 6 (unit tests written): create `step.add-block.{BlockName}.tests`
  - After Step 7 (example model created via `/add-example`): create `step.add-block.{BlockName}.example`
  - After Step 8 (codegen): create `step.add-block.{BlockName}.codegen` (or `step.add-block.{BlockName}.codegen-deferred` if a GitHub issue was filed instead)
  - After Step 9 (manual testing via `/manual-testing`): create `step.add-block.{BlockName}.manual-test`
  - After Step 10b (self-audit passed): create `step.add-block.{BlockName}.self-audit`
  - After Step 11 (verification via `/verify-changes`): create `step.add-block.{BlockName}.verify`
- [ ] Add delegation requirement for Step 7:
  - Before invoking `/add-example`, create `requires.add-example.{BlockName}`
  - `/add-example` creates `fulfilled.add-example.{BlockName}` on entry (via add-example changes below).
- [ ] Add delegation requirement for Step 11:
  - Before dispatching verification agent, create `requires.verify-changes.{BlockName}`
  - The hook ensures verification was actually dispatched before landing (Step 12).
- [ ] The self-audit gate (Step 10b) should check that all step markers exist before proceeding. Add instruction: "Before running the self-audit checklist, verify that tracking files exist for: tests, example (or example-deferred), codegen (or codegen-deferred), manual-test. If any are missing, the step was skipped — go back and complete it before auditing."

#### /add-example (block-diagram/add-example/SKILL.md)

- [ ] Add fulfillment file creation — on entry:
  - Create `fulfilled.add-example.{name}` (where `name` is the example model name or the block name from the requirement file)
- [ ] Add step markers:
  - After Phase 2 (build — model file created): create `step.add-example.{name}.build`
  - After Phase 3 (register — added to EXAMPLE_MODELS and tests): create `step.add-example.{name}.register`
  - After Phase 4b (screenshot taken): create `step.add-example.{name}.screenshot`
  - After Phase 4c (unit tests with value assertions): create `step.add-example.{name}.tests`
  - After Phase 5a (verification agent dispatched): create `step.add-example.{name}.verify`

### Design & Constraints

**Batch mode for /add-block:** When adding multiple blocks in batch mode, each block gets its own set of step markers (keyed by BlockName). The hook checks each independently. A batch of 5 blocks means 5 sets of markers.

**Deferred steps:** Some steps in /add-block are legitimately deferrable (e.g., Step 8 codegen when Rust isn't available). The step marker for deferred steps uses a `-deferred` suffix: `step.add-block.{BlockName}.codegen-deferred`. The hook treats both `codegen` and `codegen-deferred` as satisfying the step requirement. The deferred marker must include the GitHub issue number in its content.

**fix-issues is a top-level orchestrator:** Like /research-and-go, it can be the entry point for a pipeline. It creates `pipeline.active` if one doesn't already exist. If one already exists (e.g., a plan-mode /fix-issues is invoked from within a /research-and-go pipeline), it adds its own delegation requirements without touching the existing sentinel.

**Step marker creation is bash one-liners:** Each marker instruction in the skill is a simple:
```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
mkdir -p "$MAIN_ROOT/.claude/tracking"
printf 'skill=add-block\nblock=DiscreteFilter\nstep=tests\ncompletedAt=%s\n' "$(date -Iseconds)" > "$MAIN_ROOT/.claude/tracking/step.add-block.DiscreteFilter.tests"
```
Note: always use `printf` (not `echo`) for tracking files — `echo "...\n..."` does NOT produce newlines in bash without `-e` flag.

### Acceptance Criteria

- [ ] `/fix-issues` creates `pipeline.active` sentinel on sprint entry
- [ ] `/fix-issues` creates step markers after each phase (preflight through land)
- [ ] `/fix-issues` creates delegation requirements for `/verify-changes` and `/draft-plan` invocations
- [ ] `/add-block` creates step markers for historically-skipped steps (tests, example, codegen, manual-test, self-audit, verify)
- [ ] `/add-block` creates delegation requirements for `/add-example` (Step 7) and `/verify-changes` (Step 11)
- [ ] `/add-block` self-audit (Step 10b) checks for tracking file existence before proceeding
- [ ] `/add-example` creates fulfillment file on entry and step markers through completion
- [ ] Deferred steps use `-deferred` suffix with GitHub issue number in content
- [ ] Batch mode: each block in a batch has independent tracking markers

### Dependencies
Phase 1 must be complete (hook infrastructure). Phase 3 should be complete (verify-changes creates fulfillment files that match the requirements from this phase).

---

## Phase 5 — Tests & Integration

### Goal
Add remaining test coverage (hook enforcement tests were added in Phase 1), integration with `/update-zskills`, and documentation updates.

### Work Items

#### Test additions (tests/test-hooks.sh)

- [ ] Add tests for tracking file protection:
  - `expect_deny "rm -rf .claude/tracking"` — blocks recursive directory deletion
  - `expect_deny "rm -r .claude/tracking/"` — blocks recursive deletion variant
  - `expect_allow "rm .claude/tracking/pipeline.active"` — individual file deletion is ALLOWED (skills update their own files)
  - `expect_allow "rm -f .claude/tracking/requires.run-plan.1"` — individual deletion with -f is allowed
  - `expect_deny "bash scripts/clear-tracking.sh"` — blocks agent cleanup execution
  - `expect_deny "sh scripts/clear-tracking.sh"` — blocks sh variant
  - `expect_allow "cat scripts/clear-tracking.sh"` — reading the script is allowed
  - `expect_allow "ls .claude/tracking/"` — reading is allowed
  - `expect_allow "printf 'test' > .claude/tracking/fulfilled.run-plan.1"` — writing is allowed

- [ ] Add tests for delegation enforcement:
  - Setup: create `.claude/tracking/` dir with `requires.run-plan.1` file but NO `fulfilled.run-plan.1`
  - `expect_deny "git commit -m test"` — blocks commit when requirement unfulfilled
  - Setup: also create `fulfilled.run-plan.1`
  - `expect_allow "git commit -m test"` — allows commit when requirement fulfilled
  - Setup: create only `fulfilled.run-plan.1` (no requirement file)
  - `expect_allow "git commit -m test"` — allows commit when no requirements exist

- [ ] Add tests for step enforcement:
  - Setup: create `step.run-plan.1.implement` but NO `step.run-plan.1.verify`
  - `expect_deny "git commit -m test"` — blocks commit without verification
  - Setup: also create `step.run-plan.1.verify`
  - `expect_allow "git commit -m test"` — allows commit with verification

- [ ] Add tests for worktree exemption (via tracking dir not existing):
  - Setup: create `requires.run-plan.1` in MAIN repo's tracking dir, but make the hook resolve MAIN_ROOT to a directory WITHOUT `.claude/tracking/`
  - `expect_project_allow "git commit -m test"` — allows commit when tracking dir doesn't exist at resolved MAIN_ROOT
  - Alternative simpler test: just verify that when `.claude/tracking/` doesn't exist, all tracking checks are skipped (this is the backward-compatibility test, which also covers worktrees)

- [ ] Add tests for content-only exemption:
  - Verify that the code file detection logic correctly exempts content-only commits from tracking checks

- [ ] Add tests for placeholder-to-block:
  - Setup: hook with `FULL_TEST_CMD="{{FULL_TEST_CMD}}"` and a `package.json` with `"test"` field
  - `expect_deny "git commit -m test"` — blocks when placeholder unconfigured but tests exist
  - Verify the error message mentions configuring FULL_TEST_CMD

- [ ] Add tests for backward compatibility:
  - Setup: no `.claude/tracking/` directory exists
  - `expect_allow "git commit -m test"` — allows commit (graceful degradation)

#### Integration with /update-zskills

- [ ] Modify `skills/update-zskills/SKILL.md` — add awareness of tracking infrastructure:
  - In the audit step (Step 4 — Check Scripts), add `clear-tracking.sh` to the checked scripts list
  - In the Fill Script Gaps step, copy `clear-tracking.sh` from portable assets to `scripts/` if missing
  - In the hook configuration step, when filling placeholders in `block-unsafe-project.sh`, note that the tracking enforcement section has no placeholders (it works out of the box)
  - Add `.claude/tracking/` to `.gitignore` during installation if not already present

#### Documentation

- [ ] Update `CLAUDE_TEMPLATE.md` — if a section references hook enforcement, add a brief note about tracking file enforcement being active when `.claude/tracking/` exists
- [ ] No changes to `CLAUDE.md` in the zskills repo itself — it already has the hook system documented

### Design & Constraints

**Project hook test harness (concrete implementation):** The project hook reads from stdin AND from the filesystem (transcript, tracking dir, package.json, git state). Testing requires a mock environment. Add this setup function to `tests/test-hooks.sh`:

```bash
# ─── Project hook test harness ───
PROJECT_HOOK="hooks/block-unsafe-project.sh.template"
TEST_TMPDIR=""

setup_project_test() {
  TEST_TMPDIR=$(mktemp -d)
  mkdir -p "$TEST_TMPDIR/.claude/hooks"
  mkdir -p "$TEST_TMPDIR/.claude/tracking"

  # Copy and configure the hook template
  cp "$PROJECT_HOOK" "$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh"
  sed -i 's|{{UNIT_TEST_CMD}}|npm test|g' "$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh"
  sed -i 's|{{FULL_TEST_CMD}}|npm run test:all|g' "$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh"
  sed -i 's|{{UI_FILE_PATTERNS}}|src/ui/|g' "$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh"

  # Create mock package.json with test script
  printf '{"scripts":{"test":"vitest","test:all":"vitest run"}}\n' > "$TEST_TMPDIR/package.json"

  # Create mock transcript with test command
  printf 'npm run test:all\n' > "$TEST_TMPDIR/.transcript"

  # Initialize git repo (needed for git diff --cached, etc.)
  (cd "$TEST_TMPDIR" && git init -q && git add -A && git commit -q -m "init" 2>/dev/null)
}

teardown_project_test() {
  [ -n "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
  TEST_TMPDIR=""
}

# expect_project_deny and expect_project_allow pipe JSON into the project hook
# running in the test tmpdir context
expect_project_deny() {
  local cmd="$1"
  local json="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$cmd\"},\"transcript_path\":\"$TEST_TMPDIR/.transcript\"}"
  local result
  result=$(echo "$json" | REPO_ROOT="$TEST_TMPDIR" bash "$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh" 2>/dev/null)
  if [[ "$result" == *"permissionDecision"*"deny"* ]]; then
    pass "$cmd → denied (expected)"
  else
    fail "$cmd → allowed (expected deny)"
  fi
}

expect_project_allow() {
  local cmd="$1"
  local json="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$cmd\"},\"transcript_path\":\"$TEST_TMPDIR/.transcript\"}"
  local result
  result=$(echo "$json" | REPO_ROOT="$TEST_TMPDIR" bash "$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh" 2>/dev/null)
  if [[ -z "$result" ]] || [[ "$result" != *"deny"* ]]; then
    pass "$cmd → allowed (expected)"
  else
    fail "$cmd → denied (expected allow)"
  fi
}
```

Each test case calls `setup_project_test`, creates tracking files in `$TEST_TMPDIR/.claude/tracking/`, runs `expect_project_deny`/`expect_project_allow`, then calls `teardown_project_test`.

**Note on REPO_ROOT:** The hook script derives `REPO_ROOT` from `git rev-parse --show-toplevel`. The test harness may need to ensure this resolves to `$TEST_TMPDIR`. The `cd "$TEST_TMPDIR" && git init` in setup handles this for commands that run inside the tmpdir. If the hook uses `$REPO_ROOT` without computing it (i.e., it's passed as an env var), set it in the test.

### Acceptance Criteria

- [ ] `tests/test-hooks.sh` has tests for: tracking file protection (4+ cases), delegation enforcement (3+ cases), step enforcement (2+ cases), worktree exemption (1+ case), content-only exemption, placeholder-to-block (2+ cases), backward compatibility (1+ case)
- [ ] All new tests pass when run via `bash tests/test-hooks.sh`
- [ ] All existing tests still pass (no regressions)
- [ ] `/update-zskills` audit recognizes `clear-tracking.sh` as an expected script
- [ ] `/update-zskills` copies `clear-tracking.sh` during installation
- [ ] `/update-zskills` adds `.claude/tracking/` to `.gitignore`
- [ ] `tests/run-all.sh` still aggregates all test results correctly

### Dependencies
Phases 1-4 must be complete (all enforcement logic and skill modifications in place before testing).

---

## Plan Quality

**Drafting process:** /draft-plan with 2 rounds of adversarial review
**Convergence:** Converged at round 2 (no new CRITICAL issues; remaining items are MINOR)
**Remaining concerns:** `find -mmin` portability on minimal Alpine containers (MINOR — target is Debian/Ubuntu devcontainers)

**General implementation note:** When skill modifications reference insertion points, use textual anchors (e.g., "after the `extract_transcript` function", "before the `# No match — allow` comment") — NOT line numbers. Line numbers shift after each phase's changes. The implementing agent should re-read each file and locate insertion points by content.

### Round History
| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1     | 14 issues (2 CRITICAL, 6 MAJOR, 6 MINOR) | 14 issues (2 CRITICAL, 7 MAJOR, 5 MINOR) | 13/13 unique issues resolved |
| 2     | 8 issues (1 CRITICAL, 4 MAJOR, 3 MINOR) | 5 issues (1 MAJOR, 1 MODERATE, 2 MINOR, 1 non-issue) | 8/8 unique issues resolved |

### Round 1 Resolutions
1. **Worktree detection** (CRITICAL) → Eliminated: `.claude/tracking/` is gitignored so it doesn't exist in worktrees. No detection logic needed.
2. **Tracking ID auto-detection** (CRITICAL) → Replaced with explicit ID passing from parent to child.
3. **`/commit` in scope** (CRITICAL) → Removed from scope; hook fires on git operations `/commit` issues.
4. **Nested /run-plan** (MAJOR) → Added explicit meta/sub tracking ID rules.
5. **Per-phase vs aggregate markers** (MAJOR) → Two prefixes: `phasestep.*` (per-phase, not checked by hook) and `step.*` (aggregate, checked).
6. **/run-plan missing verify-changes delegation** (MAJOR) → Added `requires.verify-changes.{id}` before Phase 3 dispatch.
7. **Stale tracking blocks all commits** (MAJOR) → 8-hour staleness check + instructive error messages.
8. **Phase 5 test harness** (MAJOR) → Added concrete `setup_project_test` function with full mock environment.
9. **Concurrent pipelines** (MAJOR) → One at a time; new pipeline refuses if `pipeline.active` exists.
10. **`echo "...\n..."` doesn't produce newlines** (MAJOR) → All examples use `printf` throughout.
11. **Line number references stale** (MAJOR) → Added note to use textual anchors, not line numbers.
12. **clear-tracking regex too broad** (MINOR) → Narrowed to `(bash|sh|\.\/).*clear-tracking`.
13. **No cleanup after completion** (MINOR) → Added pipeline completion cleanup to /research-and-go Step 3.

### Round 2 Resolutions
1. **Test cases contradict spec** (CRITICAL) → Rewrote tests: `rm -rf .claude/tracking` is denied, individual `rm .claude/tracking/file` is allowed (skills update their own files).
2. **Worktree skills write to wrong tracking dir** (MAJOR) → Skills use `git-common-dir` to write to MAIN repo. Hook uses `show-toplevel` to check LOCAL path. In worktrees, the local path has no tracking dir (gitignored) → enforcement skips. Updated pseudocode, skill instructions, and design docs.
3. **.json not in CODE_FILES** (MAJOR) → Added explicit work item to add `.json` to the extension regex.
4. **Delegation check nested inside pipeline.active** (MAJOR) → Moved delegation loop outside pipeline.active check. Staleness only gates the enforcement skip, not the check itself.
5. **Tracking ID passing mechanism underspecified** (MAJOR/MINOR) → Added concrete convention: parent includes full bash command with ID baked in (mechanical, not interpretive).
6. **Worktree test conflicts with design** (MINOR) → Rewrote test to use tracking-dir-not-existing approach.
7. **Phase 1 should be self-testing** (MODERATE) → Moved hook tests from Phase 5 into Phase 1 acceptance criteria.
8. **phasestep vs step unclear** (MINOR) → Added one-line decision rule in Design & Constraints.
