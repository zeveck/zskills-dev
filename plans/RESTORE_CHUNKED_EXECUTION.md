---
title: Restore Features Destroyed by faab84b + Add Defense Layer
created: 2026-04-15
status: active
---

# Plan: Restore Features Destroyed by faab84b + Add Defense Layer

## Overview

On 2026-04-12, commit `faab84b` ("feat: fix tracking enforcement")
deleted 232 lines from `skills/run-plan/SKILL.md` plus sweeping
changes across 23 files. The commit message described none of the
deletions. The plan that drove it (`plans/TRACKING_FIX.md`) made zero
references to any of the deleted features. Out-of-scope over-reach.

This plan restores every destroyed feature and adds the defense
mechanism that should have caught the original deletion.

The design is grounded in actual code — not assumptions. Every
mechanism specified below has been verified against the relevant file
and line. Where Claude Code internal behavior matters (e.g., subagent
transcript handling), the assumption is stated explicitly so future
testing can validate.

### Design goals (per user direction)

1. **Natural chunking on `finish auto`** so large pipelines break up across
   cron-fired top-level turns automatically. Eliminates late-phase
   fatigue. Each turn is a fresh top-level context with full Agent tool.
2. **Per-pipeline trackers** for hook enforcement, with parallel pipelines
   permitted (scoped tracking already implemented in current hooks). Most
   important: verification ALWAYS runs when required, by FRESH agents
   wherever possible.
3. **Two landing modes supported**:
   - **Cherry-pick mode (default)**: work in worktrees, cherry-pick to
     main per phase. Bookkeeping commits go on main.
   - **PR mode**: feature branch per plan, all phases accumulate, push
     and `gh pr create` at end, poll CI, fix failures, auto-merge.
     Bookkeeping commits go on the feature branch (not main).

### What was destroyed (verified against current tree vs `git show 635a16f`)

1. **Chunked finish auto** — Step 0 idempotent re-entry check + Phase 5c
   chunked-transition section in `/run-plan`. Each plan phase fires as its
   own cron-scheduled top-level turn.
2. **Cross-branch final verification** — `/research-and-go` writes a
   `requires.verify-changes.final.<META_PLAN_SLUG>` marker that gates
   pipeline completion until top-level `/verify-changes branch` fires
   and writes the fulfillment marker.
3. **Tool-list-aware dispatch** — preamble in `/run-plan`, `/fix-issues`,
   `/verify-changes`, `/add-block` that checks for the `Agent` tool and
   falls back to inline verification when running as a subagent
   (Claude Code subagents have no `Agent` tool — Anthropic design,
   https://code.claude.com/docs/en/sub-agents).
4. **`/research-and-plan` prohibition explanation** — full ~38-line
   `### Why /draft-plan must be invoked via the Skill tool, not the
   Agent tool` section with the docs URL, recursion-mechanism
   explanation, and past-failure context. Current tree has only a
   ~15-line shortened version.
5. **Early requires-lockdown in `/run-plan`** — `requires.verify-changes.$TRACKING_ID`
   creation at skill ENTRY (Phase 1 step 8), not Phase 2. Ensures the
   hook gates landing even if Phase 2/3 are skipped entirely.

### What's also needed but was NEVER built

6. **Regression invariants test** — no test existed for any deleted
   feature. Static grep-level invariants prevent silent re-deletion.
7. **Behavioral E2E canaries** — exercise chunked finish auto, parallel
   pipelines, final-verify gating, and PR-mode end-to-end.
8. **Scope-vs-plan judgment in `/verify-changes`** — extends the
   existing review prompt with a "does this diff serve the plan's
   stated goal?" question. `/run-plan` halts if the verify report
   flags scope creep. **This is the actual defense against future
   `faab84b`-class regressions** — an LLM judgment captures
   over-reach more robustly than mechanical scope-comments would.
9. **Orphaned-reference reconciliation** — current tree has 4 orphan
   references describing chunked execution. After Phase A restores
   the feature, re-read each.

### Critical design decisions (with verification)

**Marker naming:** `requires.verify-changes.final.<META_PLAN_SLUG>` where
`META_PLAN_SLUG` matches `basename "$META_PLAN_PATH" .md | tr '[:upper:]_' '[:lower:]-'`
— the same convention `/run-plan` uses to derive `TRACKING_ID`
(`skills/run-plan/SKILL.md:388-398`). Verified: hook suffix-match pattern
`*.${PIPELINE_ID#*.}` (`hooks/block-unsafe-project.sh.template:250`)
matches a marker named `*.meta-add-dark-mode` against
`PIPELINE_ID=run-plan.meta-add-dark-mode` — and does NOT match against
sub-plan or research-and-go scopes. Sub-plan landings proceed unblocked
(correct: per-phase chunked landing is the design). Only the meta-plan
orchestrator's pipeline-completion event is gated.

**`/research-and-go` pre-decides the meta-plan path at Step 0** so the
slug is deterministic before any research happens. Verified:
`/research-and-plan` accepts `output FILE` as an optional first arg
(`skills/research-and-plan/SKILL.md:3,8,21`). Currently `/research-and-go`
doesn't pass it, letting `/research-and-plan` pick. Plan changes
`/research-and-go` Step 0 to derive `META_PLAN_PATH` from `$SCOPE`,
write the final-verify marker immediately, then pass
`output $META_PLAN_PATH` in Step 1.

**CRITICAL HOLE — hook's `CODE_FILES` gate:** Verified at hook lines
243 and 453: the `requires.*` enforcement on `git commit` AND `git push`
is gated on `CODE_FILES` being non-empty. The meta-plan's pipeline-
completion commit (Phase 5b sub-step 3: `chore: mark plan complete —
<plan-name>` at `skills/run-plan/SKILL.md:1082-1083`) is content-only
— just the plan `.md` file. **The hook will not enforce the
final-verify marker on this commit.** Cherry-pick block (lines 354-365)
is NOT code-gated, but the meta-plan's Phase 5b commit is a `git commit`
in delegate mode, not a cherry-pick.

**Therefore**: orchestrator-level check at the TOP of Phase 5b is
REQUIRED, not optional. Phase 5b's first sub-step (NEW) detects the
marker, schedules the verify cron, schedules a re-entry cron, exits
— sub-steps 1-4 of Phase 5b never run, Phase 5c never runs, Phase 6
never runs. The hook is a backstop only.

**Phase 1 amendment**: current `skills/run-plan/SKILL.md:351` exits
"Plan complete" if all phases done. Under restored chunked, the
re-entry cron (after final-verify completes) needs to reach Phase 5b
to run sub-steps 1-4. Phase 1's "all phases complete" check must
also check frontmatter — if `status: complete` already set, exit;
if not, route directly to Phase 5b.

**Existing infrastructure verified:**
- `scripts/post-run-invariants.sh` exists (139 lines, 7 invariants).
  Already invoked by /run-plan after every plan run. Takes named
  args (`--worktree`, `--branch`, `--landed-status`, `--plan-slug`,
  `--plan-file`). Plan references it; no changes needed.
- Failure Protocol defined at `skills/run-plan/SKILL.md:1913`. 4
  steps: kill cron, restore working tree, write failure to report,
  alert user. Many existing call sites in /run-plan. Phase H's halt
  invokes this protocol idiom.
- /verify-changes report paths (verified at SKILL.md:328-336):
  `branch` scope → `reports/verify-branch-{branch-name}.md`;
  `worktree` scope → `reports/verify-worktree-{name}.md`. /run-plan
  Phase 6 halt logic (Phase H) needs to know which path to grep.

**Subagent transcript behavior:** Claude Code's per-invocation
transcript_path handling is internal to the harness. The hook's two-
tier resolution (Tier 1 `.zskills-tracked` in worktree, Tier 2
`ZSKILLS_PIPELINE_ID=` in transcript via `tail -1`) is robust to
either model — Tier 1 wins for worktree commits regardless. This is
verified by Agent B's analysis but flagged as a Claude Code internal
that should be validated by canary CANARY9 (parallel pipelines).

### What's explicitly out of scope

- Modifying the hook's `CODE_FILES` gate. Phase 5c orchestrator check
  works around it; widening the hook is a separate concern.
- Redesign of `finish` / `every` user-facing semantics. `every SCHEDULE`
  stays as a `/run-plan` argument.
- Any changes to `/draft-plan` or `/refine-plan`.
- Full restructure of the EXECUTION_MODES architecture.

### Reconciliation required since `635a16f`

- `.claude/tracking/` → `.zskills/tracking/` (migrated by `3ed16ad`/`faab84b`).
- PR landing mode exists now; chunked finish auto must interop with
  its async merge lifecycle (handled in Phase A's PR-mode branching).
- `ZSKILLS_PIPELINE_ID` echo convention exists (verified at
  `skills/run-plan/SKILL.md:619` and `skills/research-and-go/SKILL.md:65`).
- Hook pipeline scoping (verified at `hooks/block-unsafe-project.sh.template:250`).

### Source of truth for restoration

```bash
git show 635a16f -- skills/run-plan/SKILL.md
git show 635a16f -- skills/research-and-go/SKILL.md
git show 635a16f -- skills/research-and-plan/SKILL.md
git show 635a16f -- skills/verify-changes/SKILL.md
git show 635a16f -- skills/fix-issues/SKILL.md
git show 635a16f -- block-diagram/add-block/SKILL.md
```

All restored content is verbatim from `635a16f`, adjusted only for
the reconciliation points above.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| A -- Chunked finish auto in /run-plan | ✅ Done | `f0e51b9` | Step 0 + Phase 5b gate + Phase 5c | | | Step 0 + Phase 5b gate + Phase 5c (chunked transition only) |
| B -- Cross-branch final verify in /research-and-go | ✅ Done | `e4bc50a` | Pre-decide path; marker at Step 0 | | | Pre-decide path; write marker at Step 0 |
| C -- Tool-list-aware dispatch in 4 skills | ✅ Done | `3f0f8c2` | 4 skills restored | | | run-plan, fix-issues, verify-changes, add-block |
| D -- /research-and-plan prohibition explanation | ✅ Done | `3f6e9c9` | Full ~38-line section restored | | | ~38-line block restoration |
| E -- Early requires-lockdown in /run-plan | ✅ Done | `f7f3475` | Marker at entry | | | Move marker creation to Phase 1 step 8 |
| H -- Scope-vs-plan judgment in /verify-changes | ✅ Done | `8e5634d` | Scope vs plan Q + Scope Assessment + halt-on-flag check |
| G -- Orphaned-reference reconciliation | ✅ Done | `N/A` | Zero-diff: all 4 sites already accurate post-Phase-A |
| F -- Invariants test + behavioral canaries | ✅ Done | `45445ad` | 3 new test scripts + extended test-hooks + 5 canary plans (10 files) |

### Dependency graph and execution order

Edges: phase X → phase Y means "Y depends on X."

```
A ──┬── G
    └── F
B ──── F
C ──── F
D ──── F
E ──── F
H ──── F
```

**Execution order** (linear, single-track): A → B → C → D → E → H → G → F.

**Parallelizable** (if running concurrent worktrees): A, B, C, D, E, H
can all start in parallel. G runs after A. F runs last (after all of
A–E and H — it asserts every restoration anchor exists). For chunked
finish auto, each phase fires as its own cron-fired turn, so the
linear order is what /run-plan executes naturally.

**Why F is last**: its invariants test grep-asserts anchor strings
that only exist post-restoration. If F runs before A–E and H, the
test fails immediately. F-last keeps CI green during incremental
restoration.

**Why G after A**: G reconciles references to chunked execution.
Those references are accurate again only after A restores Phase 5c.

---

## Phase A -- Chunked finish auto in /run-plan

### Goal

Restore chunked finish-auto execution: `/run-plan <plan> finish auto`
processes one plan phase per cron-fired top-level turn. Idempotent
re-entry. PR-mode-aware next-phase scheduling. Final-verify gate
integrated in Phase 5c.

### Reference

`git show 635a16f -- skills/run-plan/SKILL.md` — Step 0 at top of
Phase 1 preflight, and Phase 5c between Phase 5b and Phase 6.

### Work Items

- [ ] **Insert Step 0 Idempotent re-entry check** at the top of Phase 1
      preflight (before "1. In-progress git operation?" at current
      `skills/run-plan/SKILL.md:291`):
      ```bash
      # Step 0: Re-emit pipeline ID first (cron-fired turns are fresh sessions)
      TRACKING_ID=$(basename "$PLAN_FILE" .md | tr '[:upper:]_' '[:lower:]-')
      echo "ZSKILLS_PIPELINE_ID=run-plan.$TRACKING_ID"
      ```
      Then read plan frontmatter (status field) and plan tracker
      (phase statuses). Four exit-cleanly cases:
      1. **Frontmatter `status: complete`**: plan truly done. Exit
         "Plan complete (already)."
      2. **All phases Done + frontmatter NOT complete**: Phase 5b
         needs to run (it owns the final-verify gate logic via its
         new first sub-step). Skip Phase 1 sub-steps 2-9 and Phase
         2-5; **route directly to Phase 5b**. (See Phase 1 step 3
         amendment below.) Phase 5b's gate handles the
         verify-pending vs verify-fulfilled vs no-marker cases —
         single source of truth, no duplicated logic in Step 0.
      3. **Next-target phase already In Progress** (per tracker):
         "Phase X already in progress, deferring." Exit.
      4. **Otherwise**: proceed with normal preflight (steps 1-9)
         then Phase 2.
      Prose: "Stale crons harmless — duplicate fires exit cleanly
      via this check. Re-entry routes to Phase 5b which owns
      verify-pending state and self-rescheduling."
- [ ] **Amend Phase 1 step 3** ("Determine target phase" at current
      `skills/run-plan/SKILL.md:349-355`). Current text says "If ALL
      phases complete: report 'Plan complete' → stop." Change to:
      > If ALL phases complete:
      > - If frontmatter `status: complete`: report "Plan complete"
      >   → stop. If `every`, delete cron via CronList + CronDelete.
      > - If frontmatter NOT complete: route to Phase 5b directly
      >   (Phase 5b's gate handles final-verify deferral; if
      >   final-verify is satisfied or not required, Phase 5b
      >   completes the plan).
      This is what makes the chunked re-entry path actually reach
      Phase 5b after final-verify fulfillment.
- [ ] **Update Arguments section** (current `skills/run-plan/SKILL.md:33-43`).
      Replace "runs all phases without pausing (overnight)" and "runs all
      phases in one session" with the chunked model:
      > With `auto`: each phase runs as its own cron-fired top-level
      > turn (~1–2 min between phases via one-shot crons scheduled by
      > Phase 5c). The first phase runs immediately; each subsequent
      > phase is scheduled after the prior phase lands. Preserves
      > fresh context per phase — no late-phase fatigue.
      Replace the "`finish` and `every` are mutually exclusive
      because combining them is meaningless" paragraph with:
      > **`finish` and `every` are mutually exclusive.** `finish auto`
      > schedules its own ~1-min one-shot crons internally. `every N`
      > schedules a recurring cron at user-set cadence. Combining them
      > would produce two overlapping cron schedules. Use one or the
      > other.
- [ ] **Insert `## Phase 5c — Chunked finish auto transition`**
      immediately before `## Phase 6 — Land` (current `skills/run-plan/SKILL.md:1100`).
      Adapted from `git show 635a16f`. Sections:
  - **Why chunked execution**: prose about late-phase fatigue and
    fresh-context-per-turn benefits.
  - **Idempotent re-entry**: cross-reference Step 0.
  - **When this turn schedules the next cron**: after Phase 6 land
    succeeds for the current phase. Branches:
    1. **NEXT incomplete phase exists in this plan** → schedule
       one-shot cron (`recurring: false`) for `/run-plan <plan-file>
       finish auto` ~1-2 min from now. Exit.
    2. **THIS plan is a sub-plan delegate** (detected via
       `tracking-index=N` arg from research-and-go Step 1b — see
       `skills/research-and-go/SKILL.md:135`): after sub-plan's last
       phase lands, recover meta-plan path from
       `requires.run-plan.N` marker content (or `pipeline.research-and-go.*`
       sentinel — see Step 1b). Schedule one-shot cron for
       `/run-plan <META_PLAN_PATH> finish auto`. Exit.
    3. **All phases done (meta or standalone)**: do NOT schedule a
       next-phase cron. Phase 5b has already run (or will run on the
       next /run-plan invocation/re-entry — see Phase 1 step 3
       amendment). Exit cleanly. The final-verify gate lives in
       Phase 5b's first sub-step (see Phase 5b changes below); Phase
       5c does not handle final-verify directly.
  - **PR-mode branching for next-phase cron**: do NOT poll
    `gh pr view --json state` inside the cron turn. Instead, Phase 5c
    reads the just-written `.landed` status file (verified at
    `skills/run-plan/SKILL.md:1795-1806`):
    - `status: landed` → schedule next-phase cron, exit.
    - `status: pr-ready` or `pr-ci-failing` → schedule a SHORT
      re-entry cron (~5 min) whose prompt re-fires `/run-plan <plan>
      finish auto`. Step 0's idempotent check will see the current
      phase is still In Progress and re-attempt the PR-state poll
      via Phase 6.
    - `status: conflict` or `pr-failed` → invoke Failure Protocol,
      do not schedule next cron.
    - In cherry-pick / direct mode, the land event is synchronous
      (`.landed` written immediately) and next-phase cron schedules
      directly.
  - **`scripts/post-run-invariants.sh` ordering**: Phase 5c's
    next-phase cron schedule runs AFTER `post-run-invariants.sh`
    passes. If invariants fail, do NOT schedule the next cron;
    invoke Failure Protocol.
  - **User Verify items**: in chunked mode, the current phase
    lands per-phase. If the just-landed phase has User Verify
    items, schedule next-phase cron AND output the User Verify
    items in this turn's completion message. Per-phase landing IS
    the chunked model — do NOT hold landing until all phases
    complete.
  - **How to schedule the next cron**: bash to compute target
    minute, then `CronCreate` with `recurring: false`.
- [ ] **Phase 5b first sub-step (NEW): Final-verify gate.** Insert
      as new "0. Final-verify gate" before existing sub-step "1.
      Audit phase compliance" at `skills/run-plan/SKILL.md:1029`:
      > 0. **Final-verify gate** (only if final-verify marker exists)
      >
      > Check for the cross-branch final-verify marker:
      > ```bash
      > MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
      > MARKER="$MAIN_ROOT/.zskills/tracking/requires.verify-changes.final.$TRACKING_ID"
      > FULFILLED="$MAIN_ROOT/.zskills/tracking/fulfilled.verify-changes.final.$TRACKING_ID"
      > ```
      > Three branches:
      > 1. **Marker exists AND fulfilled missing**: defer pipeline
      >    completion until /verify-changes branch runs at top
      >    level. Use self-rescheduling pattern with exponential
      >    backoff (rationale: /verify-changes branch can take
      >    5–60 min depending on cumulative diff size; fixed-time
      >    second cron risks firing before fulfillment exists,
      >    causing visible "still pending" turns).
      >
      >    Read attempt counter file:
      >    `$MAIN_ROOT/.zskills/tracking/verify-pending-attempts.$TRACKING_ID`
      >    (numeric content; absent = 0). On each invocation:
      >    - Increment attempt counter, write back to file.
      >    - Compute backoff: `attempt 1: 10min, 2: 20min, 3: 40min,
      >      4+: 60min` (capped). This is the re-entry cron interval.
      >    - On attempt 1 only: schedule the verify cron itself —
      >      `Run /verify-changes branch tracking-id=$TRACKING_ID`
      >      one-shot, ~1 min from now.
      >    - On every attempt: schedule re-entry cron —
      >      `Run /run-plan <plan-file> finish auto` one-shot,
      >      `<backoff>` from now.
      >    - Exit with message: "Final cross-branch verify pending
      >      (attempt <N>). Re-entry scheduled in <backoff>.
      >      Verify cron: <id-if-attempt-1>. Re-entry cron: <id>."
      >    Do NOT run Phase 5b sub-steps 1-4. Do NOT run Phase 5c.
      >    Do NOT run Phase 6.
      > 2. **Marker exists AND fulfilled exists**: verify completed.
      >    Delete the attempt counter file (cleanup). Proceed to
      >    sub-step 1.
      > 3. **No marker** (standalone plan, not via /research-and-go):
      >    proceed to sub-step 1.
- [ ] **Phase 5b idempotency** (in addition to gate above). Add at
      the very top of Phase 5b, BEFORE the gate:
      > If frontmatter is already `status: complete`: this is a
      > no-op re-entry. Exit cleanly without re-committing.
      Combined with the gate, Phase 5b becomes:
      > 0a. Idempotent early-exit (frontmatter already complete)
      > 0b. Final-verify gate (defer if marker pending)
      > 1. Audit phase compliance
      > 2. Close linked issue
      > 3. Update plan frontmatter (the canonical pipeline-completion commit)
      > 4. Update SPRINT_REPORT.md
- [ ] **Clarify** in a comment near `requires.verify-changes.$TRACKING_ID`
      creation (currently at `skills/run-plan/SKILL.md:785-790`, moving
      to Phase 1 step 8 in Phase E): this is the per-pipeline
      verification requirement. **Distinct** from
      `requires.verify-changes.final.<META_PLAN_SLUG>` (different
      lifecycle, different marker name). Phase A does not modify or
      consolidate this marker.
- [ ] **Mirror all changes** into `.claude/skills/run-plan/SKILL.md`.

### Acceptance Criteria

- [ ] `grep -q "Idempotent re-entry check (chunked finish auto only)"
      skills/run-plan/SKILL.md` — exits 0.
- [ ] `grep -q "Phase 5c — Chunked finish auto transition"
      skills/run-plan/SKILL.md` — exits 0.
- [ ] Arguments section describes chunked model (no "overnight" /
      "without pausing" / "one session" wording for `finish auto`).
- [ ] Phase 5c contains explicit branches for `landed`/`pr-ready`/
      `pr-ci-failing`/`conflict`/`pr-failed` based on `.landed`
      status file — no `gh pr view` polling inside the turn.
- [ ] Phase 5c contains the meta-plan final-verify branch (schedule
      verify cron + re-entry cron, exit without running Phase 5b).
- [ ] Step 0 re-entry's first sub-step is the pipeline-ID re-emission.
- [ ] Phase 5b has a documented idempotent no-op early exit.
- [ ] `post-run-invariants.sh` ordering documented (invariants BEFORE
      next-phase cron schedule).
- [ ] `.claude/skills/run-plan/SKILL.md` byte-identical to source.
- [ ] `bash tests/run-all.sh` continues to pass.
- [ ] **Diff review**: commit touches ONLY
      `skills/run-plan/SKILL.md` and `.claude/skills/run-plan/SKILL.md`.

### Dependencies

None.

---

## Phase B -- Cross-branch final verify in /research-and-go

### Goal

Restore the cross-branch final verification by writing a
`requires.verify-changes.final.<META_PLAN_SLUG>` marker at
`/research-and-go` Step 0, with the meta-plan path pre-decided
(passed to `/research-and-plan` via `output FILE` arg). Drop the
`every 4h` wrapper from Step 2's internal cron prompt. Drop the
blanket auto-cleanup at Step 3 that would wipe the marker.

### Reference

`git show 635a16f -- skills/research-and-go/SKILL.md` — Step 0
lockdown block, Step 2 cron scheduling.

### Work Items

- [ ] **Pre-decide meta-plan path at Step 0**. Insert AFTER
      `pipeline.research-and-go.$SCOPE` creation (current
      `skills/research-and-go/SKILL.md:56`) and AFTER
      `ZSKILLS_PIPELINE_ID` echo (`:65`):
      ```bash
      # Pre-decide the meta-plan path so the final-verify marker can
      # be written immediately (gate is in place from pipeline start).
      SCOPE_UPPER=$(echo "$SCOPE" | tr 'a-z-' 'A-Z_')
      META_PLAN_PATH="plans/META_${SCOPE_UPPER}.md"
      META_PLAN_SLUG=$(basename "$META_PLAN_PATH" .md | tr '[:upper:]_' '[:lower:]-')
      # Convention matches /run-plan TRACKING_ID derivation
      # (skills/run-plan/SKILL.md:388-398).
      
      # Final-verify lockdown — gates the meta-plan's pipeline-
      # completion event (Phase 5b / Phase 6 push).
      printf 'skill=verify-changes\nscope=branch\nrequiredBy=research-and-go\nmeta_plan=%s\nmeta_plan_slug=%s\ncreatedAt=%s\n' \
        "$META_PLAN_PATH" "$META_PLAN_SLUG" "$(date -Iseconds)" \
        > "$MAIN_ROOT/.zskills/tracking/requires.verify-changes.final.$META_PLAN_SLUG"
      ```
      Include explanatory prose: "The marker is named with the meta-
      plan slug to match the pipeline scope the meta-plan `/run-plan`
      will emit (`run-plan.<META_PLAN_SLUG>`). The hook's pipeline-
      scoping pattern (`*.${PIPELINE_ID#*.}` in
      `hooks/block-unsafe-project.sh.template:250`) enforces this
      marker on the meta-plan orchestrator's commits but NOT on
      sub-plan commits (sub-plans run under their own scopes).
      Note: hook enforcement is gated on `CODE_FILES` being non-
      empty (hook line 243); since the meta-plan's pipeline-
      completion commit is content-only, the hook is a backstop —
      `/run-plan` Phase 5c does the orchestrator-level check that
      actually defers Phase 5b until the fulfillment marker exists."
- [ ] **Pass `output META_PLAN_PATH` to `/research-and-plan`** in
      Step 1 (current `skills/research-and-go/SKILL.md:88`). Change:
      ```
      /research-and-plan auto parent=research-and-go <description>
      ```
      to:
      ```
      /research-and-plan output $META_PLAN_PATH auto parent=research-and-go <description>
      ```
      And update Step 1's "The meta-plan file path comes back from
      `/research-and-plan`" prose: now research-and-go DECIDES the
      path; `/research-and-plan` writes to it. Confirm the path was
      written successfully before proceeding.
- [ ] **Modify Step 2 cron prompt** (current `skills/research-and-go/SKILL.md:167-173`).
      Strip `every 4h now` from the INTERNAL cron prompt:
      ```bash
      if [ -n "$LANDING_ARG" ]; then
        RUN_PROMPT="Run /run-plan $META_PLAN_PATH finish auto $LANDING_ARG"
      else
        RUN_PROMPT="Run /run-plan $META_PLAN_PATH finish auto"
      fi
      ```
      Cron is one-shot (`recurring: false`). Chunked finish auto
      self-perpetuates via Phase 5c. The user-facing `every N`
      argument on `/run-plan` is unaffected — this change only
      removes the hardcoded wrapper from research-and-go's
      kickoff. Update prose accordingly.
- [ ] **Remove auto-cleanup from Step 3 Pipeline Cleanup** (current
      `skills/research-and-go/SKILL.md:202-219`). Replace the
      blanket `rm -f "$MAIN_ROOT/.zskills/tracking"/*` (lines 206-208)
      with prose that documents the chunked model:
      > Under chunked finish auto, `/research-and-go` Step 2
      > schedules a cron and exits — Step 3 never runs in-session.
      > Cleanup happens when the user (or a future automation)
      > observes the pipeline is complete. Run
      > `bash scripts/clear-tracking.sh` (interactive) to wipe
      > tracking. Do NOT auto-wipe — `requires.verify-changes.final.*`
      > and its fulfillment marker are pipeline-completion records
      > that should survive until the user confirms the pipeline
      > finished.
      Also remove the sentinel-cleanup at `:213-215` that wipes
      `pipeline.research-and-go.$SCOPE` — same reason.
- [ ] **Add new Step 3 — Final cross-branch verification (prose)**.
      Describes what the user observes:
      > After the meta-plan's last sub-plan completes its last
      > phase, `/run-plan` Phase 5c detects the
      > `requires.verify-changes.final.$META_PLAN_SLUG` marker.
      > It schedules:
      > 1. A cron firing `Run /verify-changes branch tracking-id=$META_PLAN_SLUG`
      > 2. A re-entry cron firing `Run /run-plan $META_PLAN_PATH finish auto`
      > The verify cron runs at top level (full Agent tool),
      > performs cross-branch verification (`git diff main...HEAD`),
      > and on success writes `fulfilled.verify-changes.final.$META_PLAN_SLUG`.
      > The re-entry cron then completes Phase 5b (mark plan
      > complete) cleanly. The user sees the verify report as the
      > final turn before the pipeline is truly complete.
      > Reference: scheduling logic lives in `/run-plan` Phase 5c
      > (Phase A). This Step 3 is documentation only — research-
      > and-go has already exited.
- [ ] **Mirror** into `.claude/skills/research-and-go/SKILL.md`.

### Acceptance Criteria

- [ ] `grep -q "requires.verify-changes.final.\$META_PLAN_SLUG"
      skills/research-and-go/SKILL.md` — exits 0.
- [ ] `grep -q "fulfilled.verify-changes.final"
      skills/research-and-go/SKILL.md` — exits 0.
- [ ] `META_PLAN_PATH` derivation block exists in Step 0.
- [ ] `/research-and-plan` invocation in Step 1 includes
      `output $META_PLAN_PATH`.
- [ ] Step 2 cron prompt no longer contains `every 4h now`.
- [ ] Step 3 has documentation prose about final cross-branch
      verification (no auto-cleanup `rm -f`).
- [ ] `.claude/skills/research-and-go/SKILL.md` mirrors source.
- [ ] `bash tests/run-all.sh` passes.
- [ ] **Diff review**: commit touches ONLY
      `skills/research-and-go/SKILL.md` and
      `.claude/skills/research-and-go/SKILL.md`.

### Dependencies

None (independent of Phase A; Phase A's Phase 5c references this
marker but doesn't depend on Phase B for its own commit).

---

## Phase C -- Tool-list-aware dispatch in 4 skills

### Goal

Restore the "Check your tool list" preamble in `/run-plan`,
`/fix-issues`, `/add-block`, and `/verify-changes`. Without it, any
skill invoked as a subagent tries to dispatch sub-subagents (which
fail by Anthropic design) and degrades unpredictably.

### Reference

`git show 635a16f` for each skill at the lines noted. Verified
preamble missing in current tree via grep for "Check your tool list"
returning 0 hits across all four files.

### Work Items

- [ ] **`skills/run-plan/SKILL.md`**: insert `### Dispatch protocol`
      subsection at the start of Phase 3 (current line 797). Use
      the `635a16f` "Check your tool list" prose. Cite
      https://code.claude.com/docs/en/sub-agents.
- [ ] **`skills/fix-issues/SKILL.md`**: insert at the verification
      dispatch section (verify location via `git show 635a16f`).
      Same preamble.
- [ ] **`block-diagram/add-block/SKILL.md`**: insert at the
      verification dispatch section. Same preamble. **Note:**
      `.claude/skills/add-block/` does NOT exist (verified). No
      mirror to create.
- [ ] **`skills/verify-changes/SKILL.md`**: this is the most-gutted.
      `635a16f` had the full "Check your tool list first" section
      with freshness-mode taxonomy at lines 26-56. Restore it
      verbatim, adjusted only for any current heading-level
      changes. Place after the existing `## Arguments` section.
- [ ] **Mirror** the three skills with mirrors:
      `.claude/skills/run-plan/SKILL.md`,
      `.claude/skills/fix-issues/SKILL.md`,
      `.claude/skills/verify-changes/SKILL.md`.
      `block-diagram/add-block/SKILL.md` has no mirror.

### Acceptance Criteria

- [ ] `grep -q "Check your tool list" skills/run-plan/SKILL.md` — 0.
- [ ] `grep -q "Check your tool list" skills/fix-issues/SKILL.md` — 0.
- [ ] `grep -q "Check your tool list" skills/verify-changes/SKILL.md` — 0.
- [ ] `grep -q "Check your tool list"
      block-diagram/add-block/SKILL.md` — 0.
- [ ] Each preamble cites
      https://code.claude.com/docs/en/sub-agents.
- [ ] Each preamble specifies the two behaviors:
      `Agent`-tool-present → dispatch fresh subagent; `Agent`-tool-
      absent → run verification inline.
- [ ] Mirror sync: `diff -q skills/X/SKILL.md .claude/skills/X/SKILL.md`
      returns empty for X in {run-plan, fix-issues, verify-changes}.
- [ ] `bash tests/run-all.sh` passes.
- [ ] **Diff review**: commit touches ONLY the four skill source
      files plus the three existing mirrors. Seven files max.

### Dependencies

None.

---

## Phase D -- /research-and-plan prohibition explanation

### Goal

Restore the full ~38-line `### Why /draft-plan must be invoked via
the Skill tool, not the Agent tool` section. Current tree has only a
~15-line shortened version (verified — see analysis below).

### Reference

`git show 635a16f -- skills/research-and-plan/SKILL.md` lines 74-115.

Current tree: `skills/research-and-plan/SKILL.md:78-87` has only the
`**PROHIBITED**` block. Missing from current vs `635a16f`:

- The `### Why /draft-plan must be invoked via the Skill tool, not
  the Agent tool` heading itself.
- "Subagents in Claude Code cannot dispatch further subagents."
  prose.
- The Anthropic docs URL: https://code.claude.com/docs/en/sub-agents.
- "The Skill tool is the recursion mechanism." section.
- "If you instead Agent-dispatch a subagent" failure-mode prose.
- "This rule applies to /draft-plan because it has internal
  dispatches" generalization.
- 4-paragraph "Past failure" explanation (current tree has only one
  sentence referencing "violated three separate times").

### Work Items

- [ ] Replace the current `**PROHIBITED**` block at lines 78-87
      with the full `### Why /draft-plan must be invoked via the
      Skill tool, not the Agent tool` section from `635a16f` lines
      74-115. Verbatim restoration.
- [ ] Mirror into `.claude/skills/research-and-plan/SKILL.md`.

### Acceptance Criteria

- [ ] `grep -q "Subagents in Claude Code cannot dispatch further subagents"
      skills/research-and-plan/SKILL.md` — exits 0.
- [ ] `grep -q "Skill tool is the recursion mechanism"
      skills/research-and-plan/SKILL.md` — exits 0.
- [ ] `grep -q "code.claude.com/docs/en/sub-agents"
      skills/research-and-plan/SKILL.md` — exits 0.
- [ ] Section length ≥30 lines (anchor-phrase checks above are the
      load-bearing assertions; line count is secondary).
- [ ] Mirror matches source (`diff -q` returns empty).
- [ ] `bash tests/run-all.sh` passes.
- [ ] **Diff review**: commit touches ONLY
      `skills/research-and-plan/SKILL.md` and
      `.claude/skills/research-and-plan/SKILL.md`.

### Dependencies

None.

---

## Phase E -- Early requires-lockdown in /run-plan

### Goal

Move the `requires.verify-changes.$TRACKING_ID` creation from Phase 2
(`skills/run-plan/SKILL.md:785-790`) to Phase 1 step 8 (alongside the
existing `fulfilled.run-plan.$TRACKING_ID` creation at
`:395-397`). Matches `635a16f` placement.

### Rationale (already audited)

Verified at `hooks/block-unsafe-project.sh.template:246-257`: the
hook's `requires.*` enforcement loop only iterates over EXISTING
markers. If `requires.verify-changes.$TRACKING_ID` is never created
(because Phase 2 is skipped), the loop never sees it and the hook
never blocks. That is a real regression — agents that fall through
Phase 2/3 to Phase 6 land are unguarded.

No need to "audit and maybe close" — evidence already supports
moving.

### Work Items

- [ ] **Move marker creation** from current `skills/run-plan/SKILL.md:785-790`
      (in Phase 2 "Pre-verification tracking") to Phase 1 step 8
      (currently at `:388-398`). Place immediately after the
      `fulfilled.run-plan.$TRACKING_ID` creation. Combined block:
      ```bash
      MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
      mkdir -p "$MAIN_ROOT/.zskills/tracking"
      printf 'skill: run-plan\nid: %s\nplan: %s\nphase: %s\nstatus: started\ndate: %s\n' \
        "$TRACKING_ID" "$PLAN_FILE" "$PHASE" "$(TZ=America/New_York date -Iseconds)" \
        > "$MAIN_ROOT/.zskills/tracking/fulfilled.run-plan.$TRACKING_ID"
      
      # Lock down verification requirement IMMEDIATELY (was Phase 2,
      # now skill entry — ensures hook blocks landing even if Phase
      # 2/3 are skipped via error path).
      printf 'skill: verify-changes\nparent: run-plan\nid: %s\ndate: %s\n' \
        "$TRACKING_ID" "$(TZ=America/New_York date -Iseconds)" \
        > "$MAIN_ROOT/.zskills/tracking/requires.verify-changes.$TRACKING_ID"
      ```
- [ ] **Update Phase 2's pre-verification section**: replace the
      removed marker creation with a brief note: "The
      `requires.verify-changes.$TRACKING_ID` marker was created at
      skill entry (Phase 1 step 8). The hook is enforcing it. Pass
      the tracking ID to the verification agent so it can create
      its own fulfillment marker."
- [ ] Mirror into `.claude/skills/run-plan/SKILL.md`.

### Acceptance Criteria

- [ ] `requires.verify-changes.$TRACKING_ID` creation appears in
      Phase 1 step 8.
- [ ] Phase 2's pre-verification section no longer creates the
      marker (just references it).
- [ ] Mirror matches source.
- [ ] `bash tests/run-all.sh` passes.
- [ ] **Diff review**: commit touches ONLY
      `skills/run-plan/SKILL.md` and
      `.claude/skills/run-plan/SKILL.md`.

### Dependencies

None (read-only audit already done; this is a code change).

---

## Phase F -- Automated test coverage + manual canary specs

### Goal

Lock down everything that CAN be automated to A+ confidence (runs
in `tests/run-all.sh`, fails CI loudly on regression). Document the
remainder as manual canaries with explicit user procedures.

### What's locked down (automated, A+)

These are bash-level integration tests that don't require Claude
Code's cron firing, fresh-session subagents, real GitHub state, or
LLM judgment. They run in CI on every commit. If any fails, halt.

1. **Static skill anchors** — grep for every restored feature's
   load-bearing string (Step 0 heading, Phase 5c heading,
   final-verify marker name, "Check your tool list" preamble in 4
   skills, "Subagents in Claude Code cannot dispatch" prose, scope
   assessment in /verify-changes, etc.). One bash file:
   `tests/test-skill-invariants.sh`. Detail spec follows.
2. **Hook pipeline scoping** — extend `tests/test-hooks.sh` with
   cases proving the suffix-match filter works correctly:
   - marker `requires.X.meta-foo` + PIPELINE_ID `run-plan.meta-foo`
     → enforced
   - same marker + PIPELINE_ID `run-plan.foo-backend` → skipped
   - same marker + PIPELINE_ID `research-and-go.meta-foo` → skipped
     (different prefix, suffix doesn't match per `${PIPELINE_ID#*.}`
     stripping behavior)
   - empty PIPELINE_ID → skipped (per hook line 230)
   - This is the foundation for CANARY8's "parallel pipelines don't
     cross-block" claim — if these unit cases pass, parallel
     pipelines are mechanically guaranteed not to cross-block.
3. **Phase 5b gate unit test** — `tests/test-phase-5b-gate.sh` (new
     file). Synthesizes tracking state and asserts gate behavior:
   - Marker exists, fulfilled missing, attempt counter absent →
     gate triggers; counter writes 1; backoff = 10min; cron A
     scheduled (mock — assert CronCreate-equivalent invocation);
     cron B scheduled at +10min; exit code = 0 (orchestrator
     defers cleanly).
   - Marker exists, fulfilled missing, attempt counter = 2 → no
     cron A scheduled this round (already scheduled on attempt 1);
     counter writes 3; backoff = 40min; cron B scheduled at +40min.
   - Marker exists, fulfilled exists → gate proceeds; counter file
     deleted.
   - No marker → gate proceeds.
   - Frontmatter status: complete → idempotent early-exit fires
     (before gate); no cron actions.
   The test runs the gate as a bash function in isolation — does
   not require real /run-plan invocation. Validates the entire
   self-rescheduling state machine.
4. **Halt-on-scope-flag unit test** — `tests/test-scope-halt.sh`
     (new file). Synthesizes a verify report file with `⚠️ Flag` in
     a Scope Assessment section, runs /run-plan's halt-detection
     bash logic, asserts exit non-zero with the documented error
     message. Reverse case: report without flag, halt does not
     fire. Tests the bash detection — not the LLM judgment that
     PRODUCES the flag.
5. **/verify-changes argument parser unit test** — extend
     `tests/test-hooks.sh` (or new `tests/test-arg-parsers.sh`)
     with cases for `Run /verify-changes branch tracking-id=X`:
   - SCOPE = "branch", TRACKING_ID = "X" — assert.
   - `Run /verify-changes worktree` → SCOPE = "worktree",
     TRACKING_ID = "" (no tracking).
   - `Run /verify-changes last 3` → SCOPE = "last 3",
     TRACKING_ID = "".
   - Token-order doesn't matter: `tracking-id=X branch` parses
     same as `branch tracking-id=X`.
   - Validates Phase H's parser before any cron-fired use.
6. **Mirror-sync** — already in `tests/test-skill-invariants.sh`.
   Catches restorations that forget to mirror.
7. **post-run-invariants invocation** — assert /run-plan SKILL.md
   still references `post-run-invariants.sh`. If anyone removes
   the call, the test fails.

### What's manual (irreducibly user-executed, with explicit procedures)

These require Claude Code's actual cron firing, fresh-session
subagent dispatch, real GitHub state, or LLM judgment quality
testing. They get plan files in `plans/` documenting exact user
procedure + expected observation, but NOT in `tests/run-all.sh`.

- **CANARY7 — Chunked finish auto end-to-end**: requires real
  CronCreate firing, fresh sessions per turn. User executes,
  observes timestamps and cron IDs. Procedure documented in
  `plans/CANARY7_CHUNKED_FINISH.md`.
- **CANARY9 — Cross-branch final-verify gating end-to-end**:
  requires real `/research-and-go` execution, multiple cron fires,
  real `/verify-changes branch` run. User executes. Procedure in
  `plans/CANARY9_FINAL_VERIFY.md`.
- **CANARY10 — PR mode end-to-end**: requires real GitHub state
  (PR creation, CI execution, merge). User executes. Procedure in
  `plans/CANARY10_PR_MODE.md`. (User confirmed: happy to do
  manually.)
- **CANARY11 — Scope-vs-plan LLM judgment**: tests whether
  `/verify-changes`'s LLM reviewer actually CATCHES deliberate
  scope creep. The bash detection is automated (item 4 above);
  the LLM-judgment quality is what's manual. User runs a
  synthetic plan with a deliberate over-reaching commit;
  inspects whether `/verify-changes` flagged it. Procedure in
  `plans/CANARY11_SCOPE_VIOLATION.md`.

### Why the split matters

The automated tests give A+ confidence that the **mechanisms work
correctly under the documented inputs**. The manual canaries
validate **end-to-end behavior under real Claude Code conditions**
(cron firing, subagent transcripts, GitHub APIs, LLM quality).
Both layers are necessary; neither is sufficient alone. After
implementation, all 7 automated tests must pass before the manual
canaries are run — manual canaries are wasted effort if the
foundation tests fail.

### Work Items

#### Automated tests (locked down to A+ — run in CI)

- [ ] **Create `tests/test-skill-invariants.sh`** (new file). Asserts
      every restored feature's anchor text exists. Output format
      MUST match `tests/run-all.sh`'s regex `\d+ passed, \d+ failed`
      (see `tests/run-all.sh:25-27`). Use a dynamic counter, not a
      hardcoded number:
      ```bash
      #!/bin/bash
      # Regression invariants for features deleted by faab84b.
      
      PASS=0
      FAIL=0
      check() {
        local desc="$1"
        local cmd="$2"
        if eval "$cmd"; then
          PASS=$((PASS+1))
        else
          echo "FAIL: $desc" >&2
          FAIL=$((FAIL+1))
        fi
      }
      
      # Phase A: chunked finish auto
      check "chunked finish auto Step 0" \
        'grep -q "Idempotent re-entry check (chunked finish auto only)" skills/run-plan/SKILL.md'
      check "chunked finish auto Phase 5c" \
        'grep -q "Phase 5c — Chunked finish auto transition" skills/run-plan/SKILL.md'
      
      # Phase B: cross-branch final verify
      check "final-verify marker in research-and-go" \
        'grep -q "requires.verify-changes.final" skills/research-and-go/SKILL.md'
      check "final-verify fulfillment ref" \
        'grep -q "fulfilled.verify-changes.final" skills/research-and-go/SKILL.md'
      check "research-and-go pre-decides meta-plan path" \
        'grep -q "META_PLAN_PATH=" skills/research-and-go/SKILL.md'
      check "research-and-go drops every 4h" \
        '! grep -q "every 4h now" skills/research-and-go/SKILL.md'
      
      # Phase C: tool-list-aware dispatch (4 skills)
      for f in skills/run-plan/SKILL.md skills/fix-issues/SKILL.md \
               skills/verify-changes/SKILL.md \
               block-diagram/add-block/SKILL.md; do
        check "tool-list-aware dispatch in $f" \
          "grep -q 'Check your tool list' '$f'"
      done
      
      # Phase D: prohibition explanation (anchor phrases)
      check "prohibition: subagents cannot dispatch" \
        'grep -q "Subagents in Claude Code cannot dispatch further subagents" skills/research-and-plan/SKILL.md'
      check "prohibition: skill tool recursion mechanism" \
        'grep -q "Skill tool is the recursion mechanism" skills/research-and-plan/SKILL.md'
      check "prohibition: docs URL" \
        'grep -q "code.claude.com/docs/en/sub-agents" skills/research-and-plan/SKILL.md'
      
      # Phase E: early requires-lockdown
      # The marker creation must appear in Phase 1 (before Phase 2).
      # Heuristic: count lines before the first "## Phase 2" heading
      # and verify the marker creation line is within that range.
      LOCKDOWN_LINE=$(grep -n "requires.verify-changes.\$TRACKING_ID" skills/run-plan/SKILL.md | head -1 | cut -d: -f1)
      PHASE2_LINE=$(grep -n "^## Phase 2" skills/run-plan/SKILL.md | head -1 | cut -d: -f1)
      if [ -n "$LOCKDOWN_LINE" ] && [ -n "$PHASE2_LINE" ] && [ "$LOCKDOWN_LINE" -lt "$PHASE2_LINE" ]; then
        check "early requires-lockdown (Phase 1)" 'true'
      else
        check "early requires-lockdown (Phase 1)" 'false'
      fi
      
      # Phase H: scope-vs-plan judgment in /verify-changes
      check "verify-changes: scope assessment in review prompt" \
        'grep -q "Scope vs plan" skills/verify-changes/SKILL.md'
      check "verify-changes: scope assessment in report format" \
        'grep -q "Scope Assessment" skills/verify-changes/SKILL.md'
      check "verify-changes: argument parser" \
        'grep -q "Parsing \$ARGUMENTS" skills/verify-changes/SKILL.md'
      check "verify-changes: branch-scope marker stem" \
        'grep -q "verify-changes.final" skills/verify-changes/SKILL.md'
      check "/run-plan halts on scope-violation flag" \
        'grep -q "Scope Assessment" skills/run-plan/SKILL.md'

      # Phase A: Phase 5b idempotency + final-verify gate
      check "Phase 5b: final-verify gate present" \
        'grep -q "Final-verify gate" skills/run-plan/SKILL.md'
      check "Phase 5b: idempotent early-exit present" \
        'grep -q "frontmatter is already.*status: complete" skills/run-plan/SKILL.md'

      # post-run-invariants.sh still invoked by /run-plan
      check "post-run-invariants.sh invoked by /run-plan" \
        'grep -q "post-run-invariants.sh" skills/run-plan/SKILL.md'
      
      # Mirror sync (catches restores that forget to mirror)
      for f in run-plan research-and-go fix-issues verify-changes research-and-plan; do
        if [ -d ".claude/skills/$f" ]; then
          check "mirror sync: $f" \
            "diff -q 'skills/$f/SKILL.md' '.claude/skills/$f/SKILL.md' >/dev/null"
        fi
      done
      
      # Emit format expected by tests/run-all.sh
      echo "Results: $PASS passed, $FAIL failed"
      [ "$FAIL" -eq 0 ]
      ```
- [ ] **Wire into `tests/run-all.sh`**: add explicit `run_suite` line
      after the existing three (verified at `tests/run-all.sh:37-39`):
      ```bash
      run_suite "test-skill-invariants.sh" "tests/test-skill-invariants.sh"
      ```
- [ ] **Artificial-break validation**: temporarily rename
      "Idempotent re-entry check" → "Idempotent check" in
      `skills/run-plan/SKILL.md`, run
      `bash tests/test-skill-invariants.sh`, confirm it FAILS
      loudly, revert. This proves the invariants test catches
      regression. Document the result.
- [ ] **Extend `tests/test-hooks.sh`** with hook-scoping cases.
      Add a new test function `test_pipeline_scoping_filter()`
      using existing test-harness conventions (synthesize tracking
      dir + transcript file, invoke hook, assert decision).
      
      Naming convention used in test cases below mirrors real
      pipeline naming: `research-and-go.<SCOPE>` (parent),
      `run-plan.meta-<SCOPE>` (meta-plan, where META_ prefix is
      added by Phase B's Step 0 path derivation),
      `run-plan.<SUB_PLAN_SLUG>` (each sub-plan).
      
      Cases:
      - **A — exact-match enforce**: marker
        `requires.verify-changes.final.meta-foo` + PIPELINE_ID
        `run-plan.meta-foo` + commit on code file → hook BLOCKS.
        (`${PIPELINE_ID#*.}=meta-foo`, pattern `*.meta-foo`, base
        ends `.meta-foo` → match.)
      - **B — sub-plan does not see parent's marker**: same marker
        + PIPELINE_ID `run-plan.foo-backend` + commit → hook
        ALLOWS. (`${PIPELINE_ID#*.}=foo-backend`, pattern
        `*.foo-backend`, base ends `.meta-foo` ≠ `.foo-backend` →
        no match.)
      - **C — research-and-go scope filters meta marker**: same
        marker + PIPELINE_ID `research-and-go.foo` + commit →
        hook ALLOWS. (`${PIPELINE_ID#*.}=foo`, pattern `*.foo`,
        base ends `.meta-foo`. Required boundary: `*.foo` matches
        only if base ends with literal `.foo`. The character before
        `foo` in `meta-foo` is `-`, not `.`. No match → ALLOW.
        This is what makes the SCOPE/META_PLAN_SLUG distinction
        safe — `research-and-go.foo` and `run-plan.meta-foo` have
        DIFFERENT suffixes after `${PIPELINE_ID#*.}` stripping.)
      - **D — collision case (edge)**: marker
        `requires.X.meta-foo` + PIPELINE_ID
        `research-and-go.meta-foo` + commit → hook BLOCKS.
        (Suffixes collide. This is an artificial collision since
        natural research-and-go SCOPE comes from $DESCRIPTION and
        META_PLAN_SLUG comes from `meta-${SCOPE}` — they cannot
        collide unless user manipulates inputs. Test exists to
        document the edge case behavior, not a normal scenario.)
      - **E — empty PIPELINE_ID skip**: marker + empty transcript
        + commit → hook ALLOWS (per hook line 230 short-circuit).
      - **F — no marker present**: empty tracking dir + any
        PIPELINE_ID + commit → hook ALLOWS.
      
      If cases A–C and E–F pass, parallel pipelines are
      mechanically guaranteed not to cross-block. Case D documents
      the edge case that requires user discipline (don't choose
      goal descriptions whose SCOPE collides with the META_PLAN_SLUG
      naming convention).
- [ ] **Create `tests/test-phase-5b-gate.sh`** (new file). Tests
      Phase 5b's first sub-step in isolation:
      - Stub the bash function `phase_5b_gate()` extracted from
        `skills/run-plan/SKILL.md`. Or, more practically, the test
        sources the relevant snippet from a test-fixture script.
      - Test cases per the gate's three branches AND the
        idempotent early-exit AND the self-rescheduling backoff
        progression (attempts 1, 2, 3, 4 — verify backoff = 10,
        20, 40, 60 min).
      - Mock CronCreate by checking the script's exit message for
        the expected cron-prompt strings.
- [ ] **Create `tests/test-scope-halt.sh`** (new file). Tests
      `/run-plan`'s halt-on-scope-flag detection:
      - Synthesize a verify report file with `## Scope Assessment`
        + `⚠️ Flag` row → assert halt fires (exit non-zero, error
        message contains the report path).
      - Synthesize report with `## Scope Assessment` but no flag
        rows → assert halt does NOT fire.
      - No verify report file at all → assert halt does NOT fire
        (graceful — old plans without /verify-changes runs).
- [ ] **Add /verify-changes argument-parser cases** to
      `tests/test-hooks.sh` (or new `tests/test-arg-parsers.sh`):
      - `branch tracking-id=meta-foo` → SCOPE=branch, TRACKING_ID=meta-foo.
      - `tracking-id=meta-foo branch` → same (token order independent).
      - `worktree` → SCOPE=worktree, TRACKING_ID="".
      - `last 3` → SCOPE="last 3", TRACKING_ID="".
      - `branch tracking-id=meta-foo extra-junk-token` → tolerated
        (extra tokens ignored).
- [ ] **Wire all new test files into `tests/run-all.sh`**: add
      `run_suite` lines for every new test file.

#### Manual canary specs (irreducibly user-executed)

- [ ] **CANARY7 — Chunked finish auto** (`plans/CANARY7_CHUNKED_FINISH.md`):
      2-phase plan with trivial file ops. Run
      `/run-plan plans/CANARY7_CHUNKED_FINISH.md finish auto`.
      Verification asserts:
  - Phase 1 fires in turn 1; Phase 2 fires in turn 2 (separate cron-
    fired turns). Use `tracking/step.run-plan.canary7-chunked-finish.implement`
    file mtime to confirm — Phase 1 and Phase 2 mtimes should differ
    by at least the cron firing interval (~1 min target). NOT
    wall-clock between turns (which can be <60s due to minute-rollover).
  - Between Phase 1 land and Phase 2 fire, a one-shot cron exists
    in CronList with prompt matching `.*finish auto`.
  - Step 0's idempotent re-entry executes on Phase 2's turn (verify
    via tracker state — Phase 1 status = Done at moment Phase 2's
    turn starts).
- [ ] **CANARY8 — Parallel pipelines** (`plans/CANARY8_PARALLEL.md`):
      two simultaneous /run-plan invocations on disjoint trivial
      plans. Verify:
  - Both pipelines complete without one blocking the other.
  - Each pipeline's tracking markers are independent (no cross-
    pipeline `requires.*` enforcement bleeds across).
  - This validates Agent B's analysis of pipeline scoping. Likely
    a manual canary (parallel session orchestration is hard to
    automate).
- [ ] **CANARY9 — Cross-branch final-verify gating**
      (`plans/CANARY9_FINAL_VERIFY.md`):
      A minimal `/research-and-go` invocation on a synthetic
      goal that produces a 1-sub-plan meta-plan. Verify:
  - At Step 0, `requires.verify-changes.final.<META_SLUG>` marker
    appears in `.zskills/tracking/`.
  - Sub-plan executes and lands per-phase normally (final-verify
    marker doesn't block sub-plan landings — sub-plan is in
    different scope).
  - When sub-plan completes its last phase, meta-plan Phase 5c
    detects "all done + marker exists + no fulfillment" and
    schedules `/verify-changes branch tracking-id=<META_SLUG>` cron.
  - `/verify-changes branch` runs at top level, produces
    `fulfilled.verify-changes.final.<META_SLUG>`.
  - Re-entry cron fires `/run-plan ... finish auto` again. Phase 5b
    proceeds and completes.
  - Likely a manual canary because it requires multiple cron-fired
    turns over real wall-clock time.
- [ ] **CANARY10 — PR mode end-to-end** (`plans/CANARY10_PR_MODE.md`):
      2-phase plan run with `pr` arg. Verify:
  - Per-phase commits land on the feature branch (not main).
  - At pipeline end, `git push origin <feature-branch>` runs.
  - `gh pr create` creates the PR.
  - CI runs (synthetic test).
  - PR auto-merges; feature branch cleanup happens.
  - Manual canary (requires real GitHub state).
- [ ] **CANARY11 — Scope-vs-plan judgment**
      (`plans/CANARY11_SCOPE_VIOLATION.md`):
      Synthetic plan whose stated goal is "fix typo in CANARY11.txt"
      but whose implementation agent is INSTRUCTED to also delete an
      unrelated file (simulating `faab84b`-class over-reach).
      Verify:
  - `/verify-changes` runs and its report contains a "Scope
    Assessment" section flagging the unrelated deletion.
  - `/run-plan` Phase 6 (or wherever the halt logic lives) detects
    the flag and halts before landing.
  - Operator-driven canary; document expected behavior.

### Acceptance Criteria

**Automated tests (all green in `bash tests/run-all.sh`):**

- [ ] `tests/test-skill-invariants.sh` exists, executable, exits 0.
- [ ] `tests/test-phase-5b-gate.sh` exists, exits 0, all gate
      branches + backoff progression covered.
- [ ] `tests/test-scope-halt.sh` exists, exits 0.
- [ ] `tests/test-hooks.sh` extended with pipeline-scoping cases
      AND argument-parser cases. All pass.
- [ ] `tests/run-all.sh` runs all four test files via `run_suite`
      lines (verified by grepping run-all.sh for each test name).
- [ ] Artificial-break validation completed and reverted (proves
      invariants test catches regression).

**Manual canary specs exist as plan files (not auto-tested):**

- [ ] `plans/CANARY7_CHUNKED_FINISH.md` — 2-phase plan, mtime-based
      timing assertions, user procedure documented.
- [ ] `plans/CANARY8_PARALLEL.md` — two-pipeline procedure, even
      though hook-scoping logic is auto-tested, real-session
      observation has separate value.
- [ ] `plans/CANARY9_FINAL_VERIFY.md` — research-and-go end-to-end.
- [ ] `plans/CANARY10_PR_MODE.md` — PR mode end-to-end (user has
      committed to running this manually).
- [ ] `plans/CANARY11_SCOPE_VIOLATION.md` — scope-vs-plan LLM
      judgment quality.

**Diff review**: commit touches ONLY:
- `tests/test-skill-invariants.sh` (new)
- `tests/test-phase-5b-gate.sh` (new)
- `tests/test-scope-halt.sh` (new)
- `tests/test-hooks.sh` (extended with new test functions)
- `tests/run-all.sh` (extended with new run_suite calls)
- `plans/CANARY7_CHUNKED_FINISH.md` (new)
- `plans/CANARY8_PARALLEL.md` (new)
- `plans/CANARY9_FINAL_VERIFY.md` (new)
- `plans/CANARY10_PR_MODE.md` (new)
- `plans/CANARY11_SCOPE_VIOLATION.md` (new)

10 files. No others.

### Dependencies

All of A, B, C, D, E, H must land before Phase F's automated tests
will pass (they assert anchor presence). G is independent (purely
documentation reconciliation). Recommended order: A → B → C → D →
E → H → G → F. Alternative: F can land alongside the others if
each test file is added with the corresponding restoration phase
(coupling each invariant to its restoration commit). Linear order
is simpler.

---

## Phase G -- Orphaned-reference reconciliation

### Goal

After Phase A restores chunked execution, re-read the four orphaned
references that describe it and reconcile wording. Minimum touch.

### Work Items

- [ ] **`skills/run-plan/SKILL.md:673`** ("persists across cron
      turns for chunked execution"). Read in context. After Phase A
      restores Phase 5c, this reference is accurate. Likely zero-diff.
- [ ] **`skills/run-plan/SKILL.md:730`** (same phrase near Phase 6
      Land). Same treatment.
- [ ] **`plans/EXECUTION_MODES_DESIGN.md:23`** ("progress tracking
      failure across cron turns"). Historical context describing
      why worktrees were chosen — preserve as historical rationale.
      Zero-diff.
- [ ] **`plans/EXECUTION_MODES_DESIGN.md:30`** ("across cron turns
      for chunked execution"). Accurate against restored chunked
      model. Zero-diff.
- [ ] Mirror any changes to `.claude/skills/run-plan/SKILL.md`.

### Acceptance Criteria

- [ ] All four sites reviewed; each is unchanged (with note in plan
      tracker) or tightened to match reality.
- [ ] No new prose added beyond what reconciliation requires.
- [ ] `bash tests/run-all.sh` passes.
- [ ] **Diff review** (zero-diff outcome is expected and acceptable):
      if any change, commit touches ONLY
      `skills/run-plan/SKILL.md`, `.claude/skills/run-plan/SKILL.md`,
      and `plans/EXECUTION_MODES_DESIGN.md` (any subset).

### Dependencies

Phase A.

---

## Phase H -- Scope-vs-plan judgment in /verify-changes

### Goal

Add a "scope-vs-plan judgment" review question to `/verify-changes`'s
existing review prompt. The dispatched reviewer compares the diff
against the plan's stated goal and flags out-of-purpose changes.
`/run-plan` reads the verify report and halts on flags. This is the
defense against future `faab84b`-class regressions: an LLM judgment
catches subtle over-reach that mechanical scope-comments cannot.

Also add an `$ARGUMENTS` parser to `/verify-changes` so it can be
fired as a cron-fired top-level turn with `tracking-id=X`, writing a
`.final`-suffixed fulfillment marker that matches Phase B's lockdown
marker.

### Reference

Agent C's research report identified concrete edits with file:line
insertion points.

### Work Items

#### `/verify-changes` SKILL.md edits

- [ ] **Add `### Parsing $ARGUMENTS` subsection** between current
      `## Arguments` (ending `skills/verify-changes/SKILL.md:55`)
      and `## Tracking Fulfillment` (`:57`):
      ```bash
      SCOPE=""
      TRACKING_ID=""
      for tok in $ARGUMENTS; do
        case "$tok" in
          tracking-id=*) TRACKING_ID="${tok#tracking-id=}" ;;
          worktree|branch|last) SCOPE="$tok" ;;
          [0-9]*) [ "$SCOPE" = "last" ] && SCOPE="last $tok" ;;
        esac
      done
      ```
      Lets `/verify-changes branch tracking-id=X` parse correctly
      when fired as a cron-fired top-level turn.
- [ ] **Add branch-scope marker stem** to the Tracking Fulfillment
      block (current `:57-68`) and Phase 7 final-marker block
      (`:430-442`):
      ```bash
      MARKER_STEM="verify-changes"
      [ "$SCOPE" = "branch" ] && MARKER_STEM="verify-changes.final"
      ```
      Then write to
      `"$MAIN_ROOT/.zskills/tracking/fulfilled.$MARKER_STEM.$TRACKING_ID"`.
      This produces `fulfilled.verify-changes.final.<id>` in branch
      scope, matching `requires.verify-changes.final.<id>` from
      Phase B.
- [ ] **Add scope-vs-plan question** to the per-file checklist in
      Phase 1 (currently `:85-89`):
      ```markdown
         - **Scope vs plan:** does this change stay within the plan's
           stated goal? Flag any file touched that is not mentioned by
           the plan's Work Items or Acceptance Criteria, AND any
           deletion/rewrite of features unrelated to the plan's
           purpose. (Regression guard: commit faab84b silently
           deleted unrelated features because no reviewer asked
           this question.)
      ```
- [ ] **Add Scope Assessment section** to the report format
      (currently `:348-385`). Insert after "Changes Reviewed":
      ```markdown
      ## Scope Assessment
      
      **Plan goal:** {one-line quote from plan's Goal section}
      
      | File | In-scope? | Rationale |
      |------|-----------|-----------|
      | src/foo.js | Yes | Listed in Work Item #2 |
      | src/bar.js | ⚠️ Flag | Deletes `bar()` — not mentioned in plan |
      
      If any row is flagged, verification is **NOT** clean — fix or
      justify before signing off.
      ```
      Mark this section **mandatory** in `branch` scope (whole-
      pipeline cumulative diff) and **recommended** in other scopes.
- [ ] **Document cron-fired top-level invocation** in the Examples
      block of `## Arguments` (currently around `:55`):
      ```markdown
      Cron-fired top-level example (final cross-branch verification at the end of a
      /research-and-go pipeline):
      
      `"Run /verify-changes branch tracking-id=meta-add-dark-mode"`
      
      Parses as `SCOPE=branch`, `TRACKING_ID=meta-add-dark-mode`, and
      on successful completion writes
      `.zskills/tracking/fulfilled.verify-changes.final.meta-add-dark-mode`,
      matching the `requires.verify-changes.final.meta-add-dark-mode`
      lockdown marker created by `/research-and-go` Step 0.
      ```
- [ ] Mirror to `.claude/skills/verify-changes/SKILL.md`.

#### `/run-plan` SKILL.md edits — halt on scope flag

- [ ] **Edit Phase 6 Pre-landing checklist** (current
      `skills/run-plan/SKILL.md:1129-1133`). The checklist already
      has 5 bail-out checks — add a 6th:
      ```
      6. `/verify-changes` Scope Assessment — grep the verify report
         for the scope-violation flag. If found, STOP.
      ```
      The report path depends on the verify scope /run-plan invoked.
      For worktree-mode verification (the default in /run-plan
      Phase 3, see `skills/run-plan/SKILL.md` worktree-verify
      dispatch), the path is
      `reports/verify-worktree-${WORKTREE_NAME}.md` where
      WORKTREE_NAME is `basename "$WORKTREE_PATH"` (verified at
      `skills/verify-changes/SKILL.md:333`). Concrete bash:
      ```bash
      VERIFY_REPORT="reports/verify-worktree-$(basename "$WORKTREE_PATH").md"
      if [ -f "$VERIFY_REPORT" ] && grep -q "⚠️ Flag" "$VERIFY_REPORT"; then
        echo "HALTED: /verify-changes flagged scope violations in $VERIFY_REPORT." >&2
        echo "Review the Scope Assessment section, fix the diff, re-verify, and re-run." >&2
        # Invoke Failure Protocol per skills/run-plan/SKILL.md:1913 —
        # kill cron, restore working tree, write failure to plan
        # report, alert user.
        # See "Failure Protocol" section for exact steps.
        exit 1
      fi
      ```
      For delegate-mode verification (which runs on main, see
      `skills/run-plan/SKILL.md:810-823`), the verify report is
      whatever scope the delegate used — typically `branch` or
      `worktree`. Implementation should determine the correct path
      based on what was passed to /verify-changes. (The dispatched
      /verify-changes invocation already knows its scope; /run-plan
      should record the report path it expects in a variable when
      dispatching, and re-use that variable for the halt check.)
- [ ] Mirror to `.claude/skills/run-plan/SKILL.md`.

### Acceptance Criteria

- [ ] `grep -q "Parsing \$ARGUMENTS" skills/verify-changes/SKILL.md` — 0.
- [ ] `grep -q "verify-changes.final" skills/verify-changes/SKILL.md` — 0.
- [ ] `grep -q "Scope vs plan" skills/verify-changes/SKILL.md` — 0.
- [ ] `grep -q "Scope Assessment" skills/verify-changes/SKILL.md` — 0.
- [ ] `grep -q "Scope Assessment" skills/run-plan/SKILL.md` — 0
      (the halt-on-flag check references this section name).
- [ ] `/verify-changes branch tracking-id=test` invocation parses
      correctly (test via dry-run or mock).
- [ ] `/run-plan` Phase 3-to-6 transition halts on a verify report
      containing a scope-violation flag (validated by CANARY11).
- [ ] `.claude/skills/verify-changes/SKILL.md` and
      `.claude/skills/run-plan/SKILL.md` mirror their sources.
- [ ] `bash tests/run-all.sh` passes.
- [ ] **Diff review**: commit touches ONLY
      `skills/verify-changes/SKILL.md`,
      `.claude/skills/verify-changes/SKILL.md`,
      `skills/run-plan/SKILL.md`,
      `.claude/skills/run-plan/SKILL.md`. Four files.

### Dependencies

None (independent of A–E; F's invariants reference H's anchors).

**Recommended ordering**: Phase H BEFORE Phase F so F's invariants
test can include H's anchor checks without skip-mode complexity.
Phases A–E can run in any order (A and B are independent; C, D, E
are each independent of A and B). G runs after A. F runs after
A–E and H.

---

## Verification after completion

After all eight phases land:

1. `bash tests/run-all.sh` — all four test suites pass.
2. `bash tests/test-skill-invariants.sh` — every restored feature
   anchor is present, all mirrors in sync.
3. `grep -c "Idempotent re-entry" skills/run-plan/SKILL.md` — ≥1.
4. `grep -c "Phase 5c — Chunked finish auto"
   skills/run-plan/SKILL.md` — 1.
5. `grep -c "requires.verify-changes.final"
   skills/research-and-go/SKILL.md` — ≥1.
6. `grep -c "Check your tool list"
   skills/run-plan/SKILL.md skills/fix-issues/SKILL.md
   skills/verify-changes/SKILL.md
   block-diagram/add-block/SKILL.md` — ≥4.
7. `grep -c "Scope Assessment" skills/verify-changes/SKILL.md` — ≥1.
8. `grep -c "Subagents in Claude Code cannot dispatch further subagents"
   skills/research-and-plan/SKILL.md` — 1.
9. All `.claude/skills/` mirrors in sync (`diff -q` returns empty
   for each pair that has a mirror).
10. **Behavioral canaries executed manually**:
    - CANARY7 (chunked finish auto): pass — separate cron fires
      observed.
    - CANARY8 (parallel pipelines): pass — no cross-blocking.
    - CANARY9 (final-verify gating): pass — meta-plan defers
      Phase 5b until /verify-changes branch fulfills.
    - CANARY10 (PR mode E2E): pass — PR created, CI runs, merge.
    - CANARY11 (scope-vs-plan flag): pass — /verify-changes
      flags deliberate scope violation; /run-plan halts.

If all 10 checks pass, the restoration is complete and the defense
mechanism is in place.

## Scope discipline (lessons from faab84b)

Each phase's commit MUST touch only the files enumerated in that
phase's Acceptance Criteria "Diff review" bullet. **This is honor
system during execution.** The mechanical defense built by Phase H
(LLM scope-vs-plan judgment in /verify-changes) catches
post-implementation, not pre-commit — so each phase's implementing
agent must self-police during impl, and /verify-changes catches
deviations during verify.

If during implementation an agent discovers a needed change outside
the declared file list, STOP and report to the user — do not expand
scope silently. Over-reach is what caused the regression this plan
restores. Don't repeat it while restoring.

After Phase H lands, future plans get the LLM scope check in
verification. This plan's own A–G phases predate that check; trust
+ vigilance only.
