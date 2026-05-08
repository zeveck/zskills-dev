---
title: /refine-plan Skill
created: 2026-04-13
status: complete
---

# Plan: /refine-plan Skill

## Overview

Create the `/refine-plan` skill -- a lightweight adversarial review scoped to the remaining (unexecuted) phases of an existing plan. Plans drift during execution: phases get added, work items expand, lessons surface mid-run. The remaining unexecuted phases become inconsistent with completed work. `/draft-plan` is too heavy for this (it includes research and blank-slate drafting). `/refine-plan` is `/draft-plan` Phases 3-5 (adversarial review, refine, converge) applied only to remaining phases, with completed phases as read-only context.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 -- Write skills/refine-plan/SKILL.md | ✅ Done | `2489320` | 405-line skill definition |
| 2 -- Install + Verify | ✅ Done | `2c4abf5` | Installed, structural verification passed |

---

## Phase 1 -- Write skills/refine-plan/SKILL.md

### Goal

Create the complete `/refine-plan` skill definition at `skills/refine-plan/SKILL.md` following the standard YAML frontmatter + markdown body format used by all zskills skills.

### Work Items

- [ ] 1.1 -- Create `skills/refine-plan/` directory and `SKILL.md` file
- [ ] 1.2 -- YAML frontmatter: `name: refine-plan`, `disable-model-invocation: false`, `argument-hint: "<plan-file> [rounds N]"`, description summarizing the skill's purpose
- [ ] 1.3 -- Arguments section with detection logic for `<plan-file>` (required, path to plan .md) and `[rounds N]` (optional, default 2). Detection rules: first token ending in `.md` or containing `/` is the plan file; `rounds` followed by a number sets max cycles; error if no plan file detected
- [ ] 1.4 -- Phase 1 of the skill's runtime flow -- Parse Plan: read the plan file, parse YAML frontmatter, parse Progress Tracker table to classify phases as completed (status contains checkmark/Done) vs remaining (everything else: empty `⬚`, in-progress, blocked). Validate that at least one remaining phase exists (error if all phases are done). Write parsed state to `/tmp/refine-plan-parsed-<slug>.md` for persistence across compaction
- [ ] 1.5 -- Phase 2 of the skill's runtime flow -- Adversarial Review (parallel agents): dispatch Reviewer agent and Devil's Advocate agent simultaneously. Both receive: (a) full plan text, (b) completed phases clearly marked as READ-ONLY CONTEXT, (c) remaining phases as the REVIEW TARGET. Specify the six reviewer dimensions and six devil's advocate dimensions detailed in Design & Constraints below. Write findings to `/tmp/refine-plan-review-round-N-<slug>.md`
- [ ] 1.6 -- Phase 3 of the skill's runtime flow -- Refine: single agent receives current remaining phases + all findings. Addresses every finding: fix it (update the plan text) or justify why it's not a problem (with evidence). May NOT ignore or defer findings. Completed phases are NEVER modified. Output is the updated remaining phases only
- [ ] 1.7 -- Phase 4 of the skill's runtime flow -- Convergence Check: count substantive issues from the round. 0 substantive issues = converged, proceed to write. Issues remain AND rounds < max = back to Phase 2 with refined draft. Max rounds reached = proceed to write with remaining-concerns note
- [ ] 1.8 -- Phase 5 of the skill's runtime flow -- Write Updated Plan: reassemble the plan file by concatenating: (a) original YAML frontmatter (unchanged), (b) original title + overview (unchanged), (c) Progress Tracker (unchanged), (d) completed phases (unchanged, byte-for-byte), (e) refined remaining phases. Write in place to the original plan file path. Append two sections at the end: (1) a **Drift Log** documenting where completed phases diverged from the plan-as-written — compare git history of the plan file (at draft time vs now) against completed phase markers to identify additions, removals, and modifications that happened during execution. Format as a table: Phase | Planned | Actual | Why. This does NOT modify completed phases — it's a historical record for future readers. (2) a **Plan Review** section documenting: rounds taken, convergence status, remaining concerns, round history table
- [ ] 1.8b -- Drift Log specification: the refiner agent identifies structural drift by: (1) `git log --follow --stat <plan-file>` to find all commits that touched the plan (summary only, avoids context overflow), (2) `git show <earliest-reachable-commit>:<plan-file>` to retrieve the original version. Compare original vs current structurally: phase headings, phase count, work item counts per phase — not raw diffs. If only one commit exists for the file (no prior version), note "no prior version available — drift log based on current state only." Use `--all` flag to search across all refs (handles worktree-drafted plans where the original may only exist on a feature branch). The Drift Log is informational — it explains WHY the executed plan differs from the drafted plan, without changing anything
- [ ] 1.9 -- Tracking section: follow the same tracking pattern as /draft-plan. Create fulfillment file on start (`fulfilled.refine-plan.<tracking-id>`), step markers after review (`step.refine-plan.<tracking-id>.review`) and after write (`step.refine-plan.<tracking-id>.finalize`), update fulfillment to complete at end. Tracking ID derived from plan file slug (e.g., `plans/EXECUTION_MODES.md` -> `execution-modes`)
- [ ] 1.10 -- Key Rules section with these constraints: (a) NEVER modify completed phases -- they are immutable context. Immutability is verified mechanically: completed phase sections must be byte-identical before and after refinement (verified via checksum or diff). Not even heading typo fixes. (b) NEVER rewrite from scratch -- only refine remaining phases, (c) every finding must be addressed (fix or justify), (d) convergence means no new substantive issues (not rephrased old ones), (e) write parsed state AND findings to /tmp/ files for persistence across compaction, (f) plan file updated IN PLACE (not to a new path), (g) ultrathink throughout, (h) default 2 rounds (lighter than /draft-plan's 3)
- [ ] 1.11 -- Edge Cases section: plan with no remaining phases (exit cleanly: "All phases complete — nothing to refine. Run with a plan that has remaining phases."), plan with no completed phases (review all phases -- effectively a lighter /draft-plan review pass, still generate Drift Log showing "no completed phases"), plan file doesn't exist (error), plan file has no Progress Tracker (attempt to infer status from phase section content; if unable, error with guidance), plan mid-execution by another agent (warn but proceed -- the review is advisory), plan has sub-phases like 3a/3b (treat each sub-phase independently for completed/remaining classification), round findings file already exists from prior invocation (overwrite not append)

### Design & Constraints

**Skill file format.** The skill definition must follow the exact format of existing skills in `skills/`. Reference `skills/draft-plan/SKILL.md` for structure:
- YAML frontmatter block with `name`, `disable-model-invocation`, `argument-hint`, `description`
- H1 title matching the skill invocation pattern
- Prose introduction explaining the skill's purpose and philosophy
- `## Arguments` section with code block and detection rules
- Runtime phases as `## Phase N -- Name` sections with detailed instructions
- `## Key Rules` section with bulleted constraints
- `## Edge Cases` section

**Completed phase detection.** Parse the Progress Tracker table. A phase row is "completed" if its Status column contains any of: `Done`, a checkmark character (`✅`), or `[x]`. Everything else (`⬚`, `In Progress`, `Blocked`, empty) is "remaining."

**Reviewer agent dimensions (6):**
1. Stale references -- code/files/APIs mentioned in remaining phases that were replaced or renamed by completed phases
2. Consistency -- do remaining phase specs match what completed phases actually built (not what they planned to build)?
3. Sizing -- are remaining phases still right-sized (~3-5 components, ~500 lines) given what's known now?
4. Specification gaps -- do remaining phases reference decisions, APIs, or data structures that should have been defined by completed phases but are missing?
5. Dependency correctness -- are remaining phase dependencies correct given completed work and remaining phase ordering?
6. Acceptance criteria coverage -- do acceptance criteria cover all work items in remaining phases?

**Devil's Advocate agent dimensions (6):**
1. Invalidated assumptions -- assumptions in remaining phases that completed work disproved
2. Unnecessary work items -- things remaining phases plan to do that completed phases already handled
3. Deferred hard parts -- difficult items hidden behind vague language in remaining phases
4. Hidden dependencies -- undeclared dependencies between remaining phases
5. Scope drift -- remaining phases that grew beyond original intent without justification
6. Integration risks -- ways remaining work will break when combined with completed work

**Completed-phase immutability** must be stated in at least three places within the skill definition: the introduction, the refine phase, and the key rules section.

**`/tmp/` file naming convention:** `/tmp/refine-plan-<type>-<slug>.md` where `<slug>` comes from the plan filename (e.g., `EXECUTION_MODES` from `plans/EXECUTION_MODES.md`).

**Distinction from /draft-plan.** The skill MUST NOT include /draft-plan's research phase or drafting phase. It starts at the review stage. Default rounds are 2 (not 3) because this is a refinement pass on an existing plan, not blank-slate creation.

### Acceptance Criteria

- [ ] `skills/refine-plan/SKILL.md` exists and follows the standard skill format (frontmatter, heading, arguments, phases, key rules, edge cases)
- [ ] YAML frontmatter includes `name: refine-plan`, `argument-hint`, `description`
- [ ] Arguments section documents `<plan-file>` and `[rounds N]` with detection logic and examples
- [ ] All five internal runtime phases are specified with enough detail for an implementing agent to build the feature using ONLY this file
- [ ] Reviewer agent prompt includes all 6 review dimensions listed above
- [ ] Devil's Advocate agent prompt includes all 6 adversarial dimensions listed above
- [ ] Completed-phase immutability is stated in at least 3 places (introduction, refine phase, key rules)
- [ ] Tracking section follows the /draft-plan pattern (fulfillment + step markers)
- [ ] Key Rules section includes all 7 constraints
- [ ] Edge Cases section covers all 7 cases
- [ ] Drift Log specified: compares completed phases against git history to document structural drift
- [ ] Write phase produces both Drift Log and Plan Review sections

### Dependencies

None -- this is Phase 1.

---

## Phase 2 -- Install + Verify

### Goal

Sync the new skill to `.claude/skills/refine-plan/SKILL.md` (the installed location Claude Code reads) and verify the skill works by running it against an existing plan file with both completed and remaining phases.

### Work Items

- [ ] 2.1 -- Create `.claude/skills/refine-plan/` directory
- [ ] 2.2 -- Copy `skills/refine-plan/SKILL.md` to `.claude/skills/refine-plan/SKILL.md`
- [ ] 2.3 -- Verify the skill is well-formed: valid YAML frontmatter parses without errors, no markdown syntax issues, all section headings present
- [ ] 2.4 -- Test against a COPY of `plans/EXECUTION_MODES.md` (has 4 completed phases and 5 remaining phases -- ideal test case): copy the plan to a temp location first (`cp plans/EXECUTION_MODES.md /tmp/EXECUTION_MODES_TEST.md`), invoke `/refine-plan /tmp/EXECUTION_MODES_TEST.md rounds 1`, then verify: (a) completed phases (1, 2, 3a, 3b-i) are byte-identical vs the original (diff the completed-phase sections), (b) remaining phases (3b-ii, 3b-iii, 4, 5a, 5b) have review findings applied, (c) findings file exists at `/tmp/refine-plan-review-round-1-EXECUTION_MODES_TEST.md`, (d) Drift Log section was appended, (e) Plan Review section was appended. The original plan file is never touched — test operates on the copy only
- [ ] 2.5 -- Test edge case against a fully-completed plan: invoke `/refine-plan plans/TRACKING_FIX.md` (all 3 phases are `✅ Done`) and verify it exits with "nothing to review" message
- [ ] 2.6 -- Verify tracking artifacts: check that `.zskills/tracking/fulfilled.refine-plan.execution-modes` exists and contains `status: complete` after the test run

### Design & Constraints

The install step is a simple file copy -- no transformation needed. The source in `skills/` is the authoritative copy; `.claude/skills/` is the installed copy that Claude Code reads at runtime.

**Critical: test against a copy, never the original.** Item 2.4 copies the plan to `/tmp/` and runs `/refine-plan` against the copy. The original plan file is never touched during testing. This avoids the risk of a crashed test leaving the plan modified.

If the skill invocation fails or produces incorrect output, fix the skill definition in `skills/refine-plan/SKILL.md`, re-copy to `.claude/skills/`, and re-test. Do NOT weaken the verification to match broken output.

### Acceptance Criteria

- [ ] `.claude/skills/refine-plan/SKILL.md` exists and is identical to `skills/refine-plan/SKILL.md`
- [ ] YAML frontmatter parses without errors (validated with a simple grep or yaml parser)
- [ ] Live test against EXECUTION_MODES.md completes without errors
- [ ] Completed phases in the test plan are byte-identical before and after the review (verified via diff)
- [ ] Remaining phases show evidence of refinement (diff is non-empty for remaining phase sections)
- [ ] Fully-completed plan test exits cleanly with appropriate message
- [ ] Tracking fulfillment file exists with `status: complete`
- [ ] Test operates on a copy — original plan file is untouched

### Dependencies

Phase 1 must be complete (the skill definition must exist before it can be installed).
